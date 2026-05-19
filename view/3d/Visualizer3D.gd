extends Node3D
class_name Visualizer3D

signal room_clicked(room_id: int)
signal opening_clicked(opening_index: int, screen_pos: Vector2)

## Basic editable 3D view for the same BuildingModel / SimulationEngine state.
## The scene owns the camera, lights, and container nodes; this script only
## rebuilds generated room meshes from the current building template.

const SmokeAnimation3D := preload("res://view/3d/smoke/SmokeAnimation3D.gd")
const SmokeLayerVisuals := preload("res://view/3d/smoke/SmokeLayerVisuals.gd")
const SmokeOpeningCurtain3D := preload("res://view/3d/smoke/SmokeOpeningCurtain3D.gd")
const SmokePuffSpriteFactory := preload("res://view/3d/smoke/SmokePuffSpriteFactory.gd")
const SmokeVolumeMaterialFactory := preload("res://view/3d/smoke/SmokeVolumeMaterialFactory.gd")
const CameraOrbit3D := preload("res://view/3d/camera/CameraOrbit3D.gd")
const FireAnimation3D := preload("res://view/3d/fire/FireAnimation3D.gd")
const FireMeshFactory := preload("res://view/3d/fire/FireMeshFactory.gd")
const FurniturePlacement3D := preload("res://view/3d/furniture/FurniturePlacement3D.gd")
const FurnitureShapeBuilder := preload("res://view/3d/furniture/FurnitureShapeBuilder.gd")
const FurnitureStateVisuals := preload("res://view/3d/furniture/FurnitureStateVisuals.gd")
const FurnitureVisualClassifier := preload("res://view/3d/furniture/FurnitureVisualClassifier.gd")
const OpeningPose3D := preload("res://view/3d/openings/OpeningPose3D.gd")
const RoomShellFactory := preload("res://view/3d/geometry/RoomShellFactory.gd")
const ScreenPicking3D := preload("res://view/3d/interaction/ScreenPicking3D.gd")

@export_group("Scene Nodes")
@export var building_path: NodePath
@export var rooms_path: NodePath = NodePath("Rooms")
@export var openings_path: NodePath = NodePath("Openings")
@export var atmosphere_path: NodePath = NodePath("Atmosphere")
@export var labels_path: NodePath = NodePath("Labels")
@export var camera_rig_path: NodePath = NodePath("CameraRig")
@export var camera_path: NodePath = NodePath("CameraRig/Camera3D")

@export_group("Geometry")
@export var meters_to_units: float = 1.0
@export var wall_thickness_m: float = 0.07
@export var floor_thickness_m: float = 0.04
@export var room_inset_m: float = 0.04
@export var default_room_height_m: float = 2.4
@export var opening_marker_depth_m: float = 0.08

@export_group("Visibility")
@export var show_walls: bool = true
@export var show_openings: bool = true
@export var show_room_labels: bool = true
@export var show_smoke_volume: bool = true
@export var show_hot_layer: bool = false
@export var show_layer_150c: bool = false
@export var show_hrr_columns: bool = true
@export var show_fuel_objects_3d: bool = true
@export var show_detector_markers_3d: bool = true
@export var show_victim_markers_3d: bool = true
@export var fuel_object_3d_height_m: float = 0.34
@export var smoke_puff_count: int = 42
@export var show_smoke_geometry_in_first_person: bool = true
@export var show_smoke_puffs_in_first_person: bool = true
@export var show_smoke_ceiling_masks: bool = true

@export_group("Colors")
@export var floor_color: Color = Color(0.18, 0.18, 0.17, 1.0)
@export var hot_floor_color: Color = Color(0.46, 0.30, 0.18, 1.0)
@export var wall_color: Color = Color(0.84, 0.86, 0.82, 0.42)
@export var hot_wall_color: Color = Color(1.00, 0.42, 0.12, 0.68)
@export var wall_outline_color: Color = Color(0.95, 0.95, 0.90, 0.72)
@export var smoke_color: Color = Color(0.22, 0.23, 0.25, 0.22)
@export var smoke_puff_color: Color = Color(0.42, 0.43, 0.45, 0.24)
@export var smoke_layer_edge_color: Color = Color(0.50, 0.53, 0.56, 0.38)
@export var hot_layer_color: Color = Color(1.00, 0.58, 0.18, 0.18)
@export var layer_150c_color: Color = Color(1.00, 0.12, 0.06, 0.70)
@export var fire_color: Color = Color(1.00, 0.38, 0.06, 0.88)
@export var fire_core_color: Color = Color(1.0, 0.84, 0.24, 0.96)
@export var fire_glow_color: Color = Color(1.0, 0.22, 0.04, 0.28)
@export var fire_ceiling_cap_color: Color = Color(1.0, 0.34, 0.05, 0.42)
@export var door_color: Color = Color(0.26, 0.86, 0.32, 0.92)
@export var window_color: Color = Color(0.24, 0.56, 1.00, 0.92)
@export var hole_color: Color = Color(1.00, 0.78, 0.00, 0.86)
@export var closed_opening_color: Color = Color(0.54, 0.56, 0.58, 0.70)
@export var label_color: Color = Color(1.0, 0.96, 0.84, 1.0)
@export var detector_marker_color: Color = Color(0.35, 0.76, 1.0, 1.0)
@export var detector_triggered_color: Color = Color(1.0, 0.40, 0.18, 1.0)
@export var victim_marker_color: Color = Color(0.95, 0.86, 0.48, 1.0)
@export var victim_incapacitated_color: Color = Color(0.58, 0.58, 0.62, 1.0)

@export_group("Dynamics")
@export var smoke_visible_threshold_kg: float = 0.01
@export var smoke_reference_kg: float = 1.2
@export var smoke_min_visible_depth_m: float = 0.05
@export var smoke_hrr_reference_kw: float = 900.0
@export var smoke_hrr_depth_boost_m: float = 0.55
@export var smoke_hrr_alpha_boost: float = 0.18
@export var smoke_opening_blend_depth_m: float = 1.55
@export var smoke_grow_lerp: float = 0.08
@export var smoke_clear_lerp: float = 0.035
@export var hot_layer_visible_drop_m: float = 0.12
@export var layer_150c_visible_drop_m: float = 0.12
@export var hrr_reference_kw: float = 1000.0
@export var fire_min_visible_hrr_kw: float = 0.5
@export var fire_base_radius_m: float = 0.16
@export var fire_max_radius_m: float = 0.52
@export var fire_max_extra_height_m: float = 2.2
@export var fire_ceiling_clearance_m: float = 0.06
@export var fire_ceiling_cap_start_fraction: float = 0.86
@export var fire_ceiling_cap_min_radius_m: float = 0.36
@export var fire_ceiling_cap_max_radius_m: float = 1.35
@export var fire_ceiling_cap_thickness_m: float = 0.14
@export var fire_flicker_strength: float = 0.12
@export var fire_light_energy_per_1000kw: float = 2.4
@export var fire_light_range_min_m: float = 2.0
@export var fire_light_range_max_m: float = 9.5
@export var temp_heat_floor_start_c: float = 80.0
@export var temp_heat_floor_full_c: float = 450.0
@export var temp_heat_wall_start_c: float = 60.0
@export var temp_heat_wall_full_c: float = 550.0

@export_group("Camera")
@export var enable_mouse_camera: bool = true
@export var orbit_with_left_drag_on_model: bool = true
@export var camera_distance_m: float = 13.0
@export var min_camera_distance_m: float = 4.0
@export var max_camera_distance_m: float = 35.0
@export var camera_orbit_x_deg: float = -56.0
@export var camera_orbit_y_deg: float = 42.0
@export var camera_orbit_sensitivity: float = 0.006
@export var camera_zoom_step_m: float = 0.8

var building: BuildingModel = null
var state: Dictionary = {}

var _rooms_root: Node3D = null
var _openings_root: Node3D = null
var _atmosphere_root: Node3D = null
var _labels_root: Node3D = null
var _camera_rig: Node3D = null
var _camera: Camera3D = null

var _room_items: Dictionary = {}
var _opening_items: Dictionary = {}
var _built: bool = false
var _bounds_m: Rect2 = Rect2()
var _origin_offset_m: Vector2 = Vector2.ZERO
var _camera_distance: float = 13.0
var _orbit_x: float = 0.0
var _orbit_y: float = 0.0
var _orbit_dragging: bool = false
var _selected_room_id: int = -1
var _selected_opening_index: int = -1
var _fire_phase: float = 0.0
var _input_active: bool = true
var _first_person_overlay: bool = false


func _ready() -> void:
	set_process_input(true)
	_resolve_nodes()
	_resolve_building()
	_camera_distance = camera_distance_m
	_orbit_x = deg_to_rad(camera_orbit_x_deg)
	_orbit_y = deg_to_rad(camera_orbit_y_deg)
	_rebuild_scene()
	_fit_camera_to_building()
	_apply_camera_transform()
	set_active(is_visible_in_tree())


func _process(delta: float) -> void:
	if not visible:
		return
	_fire_phase += delta
	_update_fire_animation()
	_update_smoke_animation()


func set_active(active: bool, camera_active: bool = true, input_active: bool = true, first_person_overlay: bool = false) -> void:
	visible = active
	_input_active = active and input_active
	_first_person_overlay = active and first_person_overlay
	if _camera != null:
		_camera.current = active and camera_active
	_apply_overlay_visibility()
	if not active:
		_orbit_dragging = false


func set_state(next_state: Dictionary) -> void:
	state = next_state
	if not _built:
		_resolve_building()
		_rebuild_scene()
	_update_dynamic_state()


func rebuild_from_building() -> void:
	_built = false
	_rebuild_scene()
	_fit_camera_to_building()
	_update_dynamic_state()


func select_opening(opening_index: int) -> void:
	_selected_opening_index = opening_index
	_update_openings()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_active or not enable_mouse_camera or not is_visible_in_tree():
		return

	if event is InputEventMouseMotion and _orbit_dragging:
		var mm := event as InputEventMouseMotion
		var orbit: Vector2 = CameraOrbit3D.drag_orbit(Vector2(_orbit_x, _orbit_y), mm.relative, camera_orbit_sensitivity)
		_orbit_x = orbit.x
		_orbit_y = orbit.y
		_apply_camera_transform()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if ScreenPicking3D.is_screen_point_over_model(_camera, _bounds_m, mb.position, meters_to_units, _origin_offset_m):
					var opening_index: int = ScreenPicking3D.opening_index_at_screen_pos(_camera, _opening_items, mb.position)
					if opening_index >= 0:
						_selected_opening_index = opening_index
						_update_openings()
						opening_clicked.emit(opening_index, mb.position)
						get_viewport().set_input_as_handled()
						return
					var rid: int = ScreenPicking3D.room_id_at_screen_pos(_camera, building, mb.position, meters_to_units, _origin_offset_m)
					if rid >= 0:
						_selected_room_id = rid
						_selected_opening_index = -1
						_update_openings()
						room_clicked.emit(rid)
						get_viewport().set_input_as_handled()
					elif _selected_room_id >= 0:
						_selected_room_id = -1
						_selected_opening_index = -1
						_update_openings()
						room_clicked.emit(-1)
						get_viewport().set_input_as_handled()
				else:
					if _selected_room_id >= 0 or _selected_opening_index >= 0:
						_selected_room_id = -1
						_selected_opening_index = -1
						_update_openings()
						room_clicked.emit(-1)
						get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and ScreenPicking3D.is_screen_point_over_model(_camera, _bounds_m, mb.position, meters_to_units, _origin_offset_m):
			_orbit_dragging = true
			get_viewport().set_input_as_handled()
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP and ScreenPicking3D.is_screen_point_over_model(_camera, _bounds_m, mb.position, meters_to_units, _origin_offset_m):
			_camera_distance = CameraOrbit3D.zoom_distance(_camera_distance, camera_zoom_step_m, true, min_camera_distance_m, max_camera_distance_m)
			_apply_camera_transform()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and ScreenPicking3D.is_screen_point_over_model(_camera, _bounds_m, mb.position, meters_to_units, _origin_offset_m):
			_camera_distance = CameraOrbit3D.zoom_distance(_camera_distance, camera_zoom_step_m, false, min_camera_distance_m, max_camera_distance_m)
			_apply_camera_transform()
			get_viewport().set_input_as_handled()


func _resolve_nodes() -> void:
	_rooms_root = _get_or_create_node3d(rooms_path, "Rooms")
	_openings_root = _get_or_create_node3d(openings_path, "Openings")
	_atmosphere_root = _get_or_create_node3d(atmosphere_path, "Atmosphere")
	_labels_root = _get_or_create_node3d(labels_path, "Labels")
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	_camera = get_node_or_null(camera_path) as Camera3D
	_apply_overlay_visibility()


func _apply_overlay_visibility() -> void:
	if _rooms_root != null:
		_rooms_root.visible = not _first_person_overlay
	if _openings_root != null:
		_openings_root.visible = not _first_person_overlay
	if _labels_root != null:
		_labels_root.visible = not _first_person_overlay
	if _atmosphere_root != null:
		_atmosphere_root.visible = true
		for child in _atmosphere_root.get_children():
			if String(child.name).begins_with("FuelObjects_"):
				child.visible = show_fuel_objects_3d and not _first_person_overlay
			elif String(child.name).begins_with("SafetyMarkers_"):
				child.visible = not _first_person_overlay
	var sun := get_node_or_null("Sun") as Light3D
	if sun != null:
		sun.visible = not _first_person_overlay
	var fill := get_node_or_null("FillLight") as Light3D
	if fill != null:
		fill.visible = not _first_person_overlay


func _resolve_building() -> void:
	if building != null:
		return
	if not building_path.is_empty():
		building = get_node_or_null(building_path) as BuildingModel
	if building == null:
		building = get_node_or_null("../../World/BuildingModel") as BuildingModel


func _get_or_create_node3d(path: NodePath, fallback_name: String) -> Node3D:
	var node := get_node_or_null(path) as Node3D
	if node != null:
		return node

	node = Node3D.new()
	node.name = fallback_name
	add_child(node)
	return node


func _rebuild_scene() -> void:
	if building == null or _rooms_root == null:
		return

	_clear_container(_rooms_root)
	_clear_container(_openings_root)
	_clear_container(_atmosphere_root)
	_clear_container(_labels_root)
	_room_items.clear()
	_opening_items.clear()

	var rects: Dictionary = building.get_room_rects_m()
	if rects.is_empty():
		return

	_bounds_m = _compute_bounds(rects)
	_origin_offset_m = -(_bounds_m.position + _bounds_m.size * 0.5)

	var room_ids: Array[int] = []
	for key in rects.keys():
		room_ids.append(int(key))
	room_ids.sort()

	for room_id in room_ids:
		_create_room(room_id, Rect2(rects[room_id]))

	_create_exterior_wall_visuals()
	_create_stair_visuals()

	for index in range(building.get_opening_count()):
		_create_opening(index)

	_create_exterior_context_visuals()

	_built = true


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.free()


func _compute_bounds(rects: Dictionary) -> Rect2:
	var first: bool = true
	var bounds := Rect2()
	for value in rects.values():
		var rect := Rect2(value)
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds


func _create_room(room_id: int, rect_m: Rect2) -> void:
	var height_m: float = _get_room_height(room_id)
	var floor_level_m: float = _get_room_floor_level(room_id)
	var shell: Dictionary = RoomShellFactory.create_room_shell(
		_rooms_root,
		_labels_root,
		room_id,
		_get_room_name(room_id),
		_get_room_label(room_id),
		rect_m,
		height_m,
		{
			"meters_to_units": meters_to_units,
			"origin_offset_m": _origin_offset_m,
			"floor_thickness_m": floor_thickness_m,
			"floor_level_m": floor_level_m,
			"wall_thickness_m": wall_thickness_m,
			"show_walls": show_walls,
			"show_room_labels": show_room_labels,
			"floor_color": floor_color,
			"wall_color": wall_color,
			"label_color": label_color,
		}
	)
	var floor := shell.get("floor") as MeshInstance3D
	var walls: Array = shell.get("walls", [])
	var room_node := shell.get("room_node") as Node3D
	var room: RoomModel = building.get_room(room_id) if building != null else null
	if floor != null and _is_stair_room(room) and floor_level_m > 0.20:
		floor.visible = false
		_create_stairwell_upper_floor_visual(room_id, rect_m, floor_level_m, room_node)

	var smoke := _create_box("SmokeVolume", Vector3.ONE, _make_smoke_volume_material())
	smoke.visible = false
	_disable_shadow_casting(smoke)
	_atmosphere_root.add_child(smoke)

	var smoke_edge := _create_box("SmokeLayerEdge_%02d" % room_id, Vector3.ONE, _make_smoke_volume_material())
	smoke_edge.visible = false
	_disable_shadow_casting(smoke_edge)
	_atmosphere_root.add_child(smoke_edge)

	var smoke_puffs_root := Node3D.new()
	smoke_puffs_root.name = "SmokePuffs_%02d" % room_id
	smoke_puffs_root.visible = false
	_atmosphere_root.add_child(smoke_puffs_root)
	var smoke_puffs: Array[Sprite3D] = []
	for puff_i in range(maxi(0, smoke_puff_count)):
		var puff := SmokePuffSpriteFactory.create_puff_sprite("SmokeWisp_%02d_%02d" % [room_id, puff_i])
		puff.set_meta("seed", float(room_id * 23 + puff_i * 17 + 3))
		smoke_puffs_root.add_child(puff)
		smoke_puffs.append(puff)

	var smoke_ceiling_mask := SmokeLayerVisuals.create_ceiling_mask("SmokeCeilingMask_%02d" % room_id)
	smoke_ceiling_mask.visible = show_smoke_ceiling_masks
	_atmosphere_root.add_child(smoke_ceiling_mask)

	var hot := _create_box("HotLayer_%02d" % room_id, Vector3.ONE, _make_material(hot_layer_color, true))
	hot.visible = false
	_disable_shadow_casting(hot)
	_atmosphere_root.add_child(hot)

	var l150 := _create_box("Layer150C_%02d" % room_id, Vector3.ONE, _make_material(layer_150c_color, true))
	l150.visible = false
	_disable_shadow_casting(l150)
	_atmosphere_root.add_child(l150)

	var fire_root := Node3D.new()
	fire_root.name = "Fire_%02d" % room_id
	fire_root.visible = false
	_atmosphere_root.add_child(fire_root)
	var fire_glow := FireMeshFactory.create_flame_mesh("Glow", fire_glow_color, fire_core_color)
	fire_root.add_child(fire_glow)
	var fire_tongues: Array[MeshInstance3D] = []
	for tongue_i in range(8):
		var tongue_color: Color = fire_color.lerp(fire_core_color, 0.18 + float(tongue_i) * 0.08)
		var tongue := FireMeshFactory.create_flame_mesh("Tongue_%02d" % tongue_i, tongue_color, fire_core_color)
		tongue.set_meta("seed", float(room_id * 19 + tongue_i * 11 + 5))
		fire_root.add_child(tongue)
		fire_tongues.append(tongue)
	var fire_cap := FireMeshFactory.create_ceiling_cap_mesh("CeilingCap", fire_ceiling_cap_color, fire_core_color)
	fire_cap.visible = false
	fire_root.add_child(fire_cap)
	var fire_core := FireMeshFactory.create_flame_mesh("Core", fire_core_color, fire_core_color)
	fire_root.add_child(fire_core)
	var fire_light := OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.42, 0.12, 1.0)
	fire_light.light_energy = 0.0
	fire_light.omni_range = fire_light_range_min_m
	fire_light.shadow_enabled = false
	fire_light.position = Vector3(0.0, 0.9, 0.0)
	fire_root.add_child(fire_light)

	var label := shell.get("label") as Label3D

	var fuel_objects_root := Node3D.new()
	fuel_objects_root.name = "FuelObjects_%02d" % room_id
	_atmosphere_root.add_child(fuel_objects_root)

	var safety_markers_root := Node3D.new()
	safety_markers_root.name = "SafetyMarkers_%02d" % room_id
	_atmosphere_root.add_child(safety_markers_root)

	_room_items[room_id] = {
		"rect": rect_m,
		"height_m": height_m,
		"floor_level_m": floor_level_m,
		"floor": floor,
		"walls": walls,
		"smoke": smoke,
		"smoke_edge": smoke_edge,
		"smoke_puffs_root": smoke_puffs_root,
		"smoke_puffs": smoke_puffs,
		"smoke_ceiling_mask": smoke_ceiling_mask,
		"hot": hot,
		"l150": l150,
		"fire_root": fire_root,
		"fire_glow": fire_glow,
		"fire_tongues": fire_tongues,
		"fire_cap": fire_cap,
		"fire_core": fire_core,
		"fire_light": fire_light,
		"label": label,
		"fire_height_m": 0.0,
		"fire_radius_m": fire_base_radius_m,
		"fire_cap_radius_m": 0.0,
		"fire_cap_weight": 0.0,
		"fire_light_energy_target": 0.0,
		"fire_phase": float(room_id) * 1.37,
		"smoke_visual_depth_m": 0.0,
		"smoke_bottom_m": height_m,
		"smoke_alpha": 0.0,
		"fuel_objects_root": fuel_objects_root,
		"fuel_obj_nodes": {},
		"safety_markers_root": safety_markers_root,
		"detector_nodes": {},
		"victim_nodes": {}
	}


func _create_stair_visuals() -> void:
	if building == null or _rooms_root == null:
		return
	var rects: Dictionary = building.get_room_rects_m()
	for room_id in rects.keys():
		var lower_room: RoomModel = building.get_room(int(room_id))
		if lower_room == null or not _is_stair_room(lower_room):
			continue
		var lower_level_m: float = lower_room.floor_level_z_m
		var upper_level_m: float = _find_next_floor_level_above(lower_level_m)
		if upper_level_m <= lower_level_m + 0.20:
			continue
		var rect := Rect2(rects[room_id])
		var stair_root := Node3D.new()
		stair_root.name = "Stairs_%02d" % int(room_id)
		_rooms_root.add_child(stair_root)
		var steps: int = 14
		var start_margin_m: float = 0.22
		var run_m: float = maxf(0.8, rect.size.y - start_margin_m - _stair_top_landing_depth_m(rect))
		var step_depth_m: float = run_m / float(steps)
		var step_width_m: float = _stair_ramp_width_m(rect)
		var rise_m: float = (upper_level_m - lower_level_m) / float(steps)
		var x: float = rect.position.x + rect.size.x * 0.5
		for i in range(steps):
			var step_h: float = rise_m * float(i + 1)
			var z: float = rect.position.y + start_margin_m + step_depth_m * (float(i) + 0.5)
			var step := _create_box(
				"Step_%02d" % i,
				Vector3(step_width_m, maxf(0.04, step_h), step_depth_m * 0.92) * meters_to_units,
				_make_material(Color(0.38, 0.32, 0.25, 1.0), false)
			)
			step.position = _to_world(Vector3(x, lower_level_m + step_h * 0.5, z))
			stair_root.add_child(step)
		var rail := _create_box(
			"Handrail",
			Vector3(0.06, 0.08, run_m) * meters_to_units,
			_make_material(Color(0.18, 0.14, 0.10, 1.0), false)
		)
		rail.position = _to_world(Vector3(rect.position.x + rect.size.x - 0.18, lower_level_m + 1.05, rect.position.y + rect.size.y * 0.5))
		stair_root.add_child(rail)


func _create_exterior_wall_visuals() -> void:
	if building == null or _rooms_root == null:
		return
	for i in range(building.exterior_walls.size()):
		if typeof(building.exterior_walls[i]) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = building.exterior_walls[i]
		var a: Vector2 = wall.get("a", Vector2.ZERO)
		var b: Vector2 = wall.get("b", Vector2.ZERO)
		var axis: Vector2 = b - a
		var length_m: float = axis.length()
		if length_m <= 0.05:
			continue
		var thickness_m: float = maxf(0.05, float(wall.get("thickness_m", wall_thickness_m * 2.0)))
		var root := Node3D.new()
		root.name = "ExteriorWall_%02d" % i
		_rooms_root.add_child(root)
		var mesh := _create_box(
			"WallMesh",
			Vector3(length_m, default_room_height_m, thickness_m) * meters_to_units,
			_make_material(Color(0.72, 0.70, 0.64, 0.72), true)
		)
		mesh.position = _to_world(Vector3((a.x + b.x) * 0.5, default_room_height_m * 0.5, (a.y + b.y) * 0.5))
		mesh.rotation.y = -atan2(axis.y, axis.x)
		root.add_child(mesh)


func _create_stairwell_upper_floor_visual(room_id: int, rect: Rect2, floor_level_m: float, parent: Node3D) -> void:
	if parent == null:
		parent = _rooms_root
	var ramp_width_m: float = _stair_ramp_width_m(rect)
	var ramp_left_m: float = rect.position.x + rect.size.x * 0.5 - ramp_width_m * 0.5
	var ramp_right_m: float = ramp_left_m + ramp_width_m
	var landing_depth_m: float = _stair_top_landing_depth_m(rect)
	var landing_start_z_m: float = rect.position.y + rect.size.y - landing_depth_m
	var mat := _make_material(floor_color, false)

	var left_width_m: float = maxf(0.0, ramp_left_m - rect.position.x)
	if left_width_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairSideFloorLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y), floor_level_m, mat)

	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - ramp_right_m)
	if right_width_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairSideFloorRight_%s" % str(room_id), Rect2(ramp_right_m, rect.position.y, right_width_m, rect.size.y), floor_level_m, mat)

	if landing_depth_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairTopLanding_%s" % str(room_id), Rect2(rect.position.x, landing_start_z_m, rect.size.x, landing_depth_m), floor_level_m, mat)


func _add_stairwell_floor_visual(parent: Node3D, node_name: String, rect: Rect2, floor_level_m: float, mat: StandardMaterial3D) -> void:
	var slab := _create_box(
		node_name,
		Vector3(rect.size.x, floor_thickness_m, rect.size.y) * meters_to_units,
		mat
	)
	slab.position = _to_world(Vector3(
		rect.position.x + rect.size.x * 0.5,
		floor_level_m - floor_thickness_m * 0.5,
		rect.position.y + rect.size.y * 0.5
	))
	parent.add_child(slab)


func _stair_ramp_width_m(rect: Rect2) -> float:
	return minf(maxf(0.82, rect.size.x * 0.50), maxf(0.82, rect.size.x - 0.96))


func _stair_top_landing_depth_m(rect: Rect2) -> float:
	return clampf(rect.size.y * 0.22, 0.72, 1.05)


func _create_opening(index: int) -> void:
	if not show_openings or building == null:
		return

	var op: OpeningModel = building.get_opening_at(index)
	if op == null:
		return

	var pose: Dictionary = _opening_pose(op)
	if pose.is_empty():
		return

	var material_color: Color = _opening_color(op)
	if op.is_closed():
		material_color = closed_opening_color

	var marker := _create_box(
		"Opening_%02d" % index,
		Vector3(pose["size"]) * meters_to_units,
		_make_material(material_color, true)
	)
	var opening_floor_m: float = float(pose.get("floor_level_m", 0.0))
	marker.position = _to_world(Vector3(pose["position"].x, opening_floor_m + pose["position"].y, pose["position"].z))
	_openings_root.add_child(marker)
	_opening_items[index] = {"marker": marker}

	# Cortina de humo: rellena el vano abierto y suaviza el salto visual de capa
	# entre estancias o hacia el exterior.
	if op.type == OpeningModel.Type.DOOR or op.type == OpeningModel.Type.WINDOW or op.type == OpeningModel.Type.HOLE:
		var curtain := _create_box(
			"SmokeCurtain_%02d" % index,
			Vector3(pose["size"]) * meters_to_units,
			_make_smoke_volume_material()
		)
		curtain.position = marker.position
		curtain.visible = false
		_disable_shadow_casting(curtain)
		_atmosphere_root.add_child(curtain)
		_opening_items[index]["smoke_curtain"] = curtain
		_opening_items[index]["curtain_pose"] = pose


func _create_exterior_context_visuals() -> void:
	if building == null or _rooms_root == null:
		return
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or not op.is_exterior_opening():
			continue
		var pose: Dictionary = _opening_pose(op)
		if pose.is_empty():
			continue
		if String(building.building_type).to_lower() == "apartment":
			if op.type == OpeningModel.Type.DOOR:
				_create_apartment_landing_context(index, op, pose)
			elif op.type == OpeningModel.Type.WINDOW:
				_create_apartment_window_context(index, op, pose)
		else:
			if op.type == OpeningModel.Type.DOOR:
				_create_single_family_entry_context(index, op, pose)
			elif op.type == OpeningModel.Type.WINDOW:
				_create_residential_window_context(index, op, pose)


func _create_apartment_landing_context(index: int, op: OpeningModel, pose: Dictionary) -> void:
	var normal: Vector2 = _outside_normal_for_wall(op.wall_side)
	var center: Vector3 = Vector3(pose["position"].x, float(pose.get("floor_level_m", 0.0)), pose["position"].z)
	var size_x: float = 5.4 if absf(normal.y) > 0.5 else 2.9
	var size_z: float = 2.9 if absf(normal.y) > 0.5 else 5.4
	var floor_center := Vector3(center.x + normal.x * size_x * 0.5, center.y - floor_thickness_m * 0.6, center.z + normal.y * size_z * 0.5)
	var root := Node3D.new()
	root.name = "ApartmentLanding_%02d" % index
	_rooms_root.add_child(root)
	var slab := _create_box("LandingFloor", Vector3(size_x, floor_thickness_m, size_z) * meters_to_units, _make_material(Color(0.34, 0.34, 0.32, 1.0), false))
	slab.position = _to_world(floor_center)
	root.add_child(slab)
	var back_wall_center := Vector3(center.x + normal.x * size_x, center.y + 1.15, center.z + normal.y * size_z)
	var wall_size := Vector3(size_x, 2.3, 0.08) if absf(normal.y) > 0.5 else Vector3(0.08, 2.3, size_z)
	var wall := _create_box("LandingBackWall", wall_size * meters_to_units, _make_material(Color(0.68, 0.66, 0.60, 0.82), true))
	wall.position = _to_world(back_wall_center)
	root.add_child(wall)
	_add_landing_panels(root, center, normal, size_x, size_z)


func _add_landing_panels(root: Node3D, door_center: Vector3, normal: Vector2, size_x: float, size_z: float) -> void:
	var tangent := Vector2(-normal.y, normal.x)
	var base := Vector3(door_center.x + normal.x * (size_x if absf(normal.y) > 0.5 else size_x * 0.92), door_center.y + 1.05, door_center.z + normal.y * (size_z if absf(normal.x) > 0.5 else size_z * 0.92))
	for i in range(3):
		var offset: float = (float(i) - 1.0) * 1.35
		var pos := Vector3(base.x + tangent.x * offset, base.y, base.z + tangent.y * offset)
		var panel_size := Vector3(0.82, 1.95, 0.06) if absf(normal.y) > 0.5 else Vector3(0.06, 1.95, 0.82)
		var panel := _create_box("FlatDoor_%d" % i, panel_size * meters_to_units, _make_material(Color(0.22, 0.19, 0.15, 1.0), false))
		panel.position = _to_world(pos)
		root.add_child(panel)
	var lift_pos := Vector3(base.x + tangent.x * 2.25, base.y, base.z + tangent.y * 2.25)
	var lift_size := Vector3(1.0, 2.0, 0.07) if absf(normal.y) > 0.5 else Vector3(0.07, 2.0, 1.0)
	var lift := _create_box("ElevatorDoor", lift_size * meters_to_units, _make_material(Color(0.42, 0.45, 0.46, 1.0), false))
	lift.position = _to_world(lift_pos)
	root.add_child(lift)
	for j in range(5):
		var step_pos := Vector3(door_center.x - tangent.x * 2.25 + normal.x * (0.55 + float(j) * 0.16), door_center.y + 0.04 + float(j) * 0.035, door_center.z - tangent.y * 2.25 + normal.y * (0.55 + float(j) * 0.16))
		var step_size := Vector3(0.9, 0.07, 0.18) if absf(normal.y) > 0.5 else Vector3(0.18, 0.07, 0.9)
		var step := _create_box("LandingStair_%d" % j, step_size * meters_to_units, _make_material(Color(0.40, 0.36, 0.30, 1.0), false))
		step.position = _to_world(step_pos)
		root.add_child(step)


func _create_single_family_entry_context(index: int, op: OpeningModel, pose: Dictionary) -> void:
	var normal: Vector2 = _outside_normal_for_wall(op.wall_side)
	var center: Vector3 = Vector3(pose["position"].x, float(pose.get("floor_level_m", 0.0)), pose["position"].z)
	var root := Node3D.new()
	root.name = "SingleFamilyExterior_%02d" % index
	_rooms_root.add_child(root)
	var path_size := Vector3(1.25, floor_thickness_m, 3.4) if absf(normal.y) > 0.5 else Vector3(3.4, floor_thickness_m, 1.25)
	var path := _create_box("EntryPath", path_size * meters_to_units, _make_material(Color(0.46, 0.45, 0.40, 1.0), false))
	path.position = _to_world(Vector3(center.x + normal.x * 1.7, center.y - floor_thickness_m * 0.5, center.z + normal.y * 1.7))
	root.add_child(path)
	var street_size := Vector3(5.8, floor_thickness_m, 0.55) if absf(normal.y) > 0.5 else Vector3(0.55, floor_thickness_m, 5.8)
	var street := _create_box("StreetEdge", street_size * meters_to_units, _make_material(Color(0.12, 0.13, 0.13, 1.0), false))
	street.position = _to_world(Vector3(center.x + normal.x * 3.6, center.y - floor_thickness_m * 0.52, center.z + normal.y * 3.6))
	root.add_child(street)
	var garden_size := Vector3(2.2, floor_thickness_m, 1.25) if absf(normal.y) > 0.5 else Vector3(1.25, floor_thickness_m, 2.2)
	for side in [-1.0, 1.0]:
		var tangent := Vector2(-normal.y, normal.x)
		var garden := _create_box("ResidentialStrip_%s" % str(side), garden_size * meters_to_units, _make_material(Color(0.18, 0.32, 0.20, 1.0), false))
		garden.position = _to_world(Vector3(center.x + normal.x * 1.4 + tangent.x * side * 1.7, center.y - floor_thickness_m * 0.55, center.z + normal.y * 1.4 + tangent.y * side * 1.7))
		root.add_child(garden)


func _create_apartment_window_context(index: int, op: OpeningModel, pose: Dictionary) -> void:
	_create_window_backdrop(index, op, pose, Color(0.48, 0.50, 0.52, 0.55), "ApartmentFacade")


func _create_residential_window_context(index: int, op: OpeningModel, pose: Dictionary) -> void:
	_create_window_backdrop(index, op, pose, Color(0.22, 0.34, 0.20, 0.52), "ResidentialView")


func _create_window_backdrop(index: int, op: OpeningModel, pose: Dictionary, color: Color, name_prefix: String) -> void:
	var normal: Vector2 = _outside_normal_for_wall(op.wall_side)
	var center: Vector3 = Vector3(pose["position"].x, float(pose.get("floor_level_m", 0.0)) + float(pose["position"].y), pose["position"].z)
	var backdrop_size := Vector3(2.8, 1.7, 0.05) if absf(normal.y) > 0.5 else Vector3(0.05, 1.7, 2.8)
	var panel := _create_box("%s_%02d" % [name_prefix, index], backdrop_size * meters_to_units, _make_material(color, true))
	panel.position = _to_world(Vector3(center.x + normal.x * 0.75, center.y, center.z + normal.y * 0.75))
	_rooms_root.add_child(panel)


func _outside_normal_for_wall(wall_side: String) -> Vector2:
	match wall_side.strip_edges().to_lower():
		"top", "north":
			return Vector2(0.0, -1.0)
		"bottom", "south":
			return Vector2(0.0, 1.0)
		"left", "west":
			return Vector2(-1.0, 0.0)
		"right", "east":
			return Vector2(1.0, 0.0)
	return Vector2(0.0, -1.0)


func _opening_color(op: OpeningModel) -> Color:
	if op == null:
		return door_color
	if op.type == OpeningModel.Type.WINDOW:
		return window_color
	if op.type == OpeningModel.Type.HOLE:
		return hole_color
	return door_color


func _opening_pose(op: OpeningModel) -> Dictionary:
	if building == null:
		return {}
	var room_id: int = op.a if op.a != BuildingModel.OUTSIDE_ID else op.b
	var other_id: int = op.b if op.a == room_id else op.a
	if other_id != BuildingModel.OUTSIDE_ID and absf(_get_room_floor_level(room_id) - _get_room_floor_level(other_id)) > 0.20:
		return {}
	var pose: Dictionary = OpeningPose3D.compute(op, building.get_room_rects_m(), BuildingModel.OUTSIDE_ID, opening_marker_depth_m)
	if not pose.is_empty():
		pose["floor_level_m"] = _get_room_floor_level(room_id)
	return pose


func _update_dynamic_state() -> void:
	for room_id in _room_items.keys():
		_update_room(int(room_id))
	_update_openings()


func _update_room(room_id: int) -> void:
	var item: Dictionary = _room_items[room_id]
	var rect := Rect2(item["rect"])
	var height_m: float = float(item["height_m"])
	var rs: Dictionary = state.get(str(room_id), {})
	if rs.is_empty():
		return

	var floor := item["floor"] as MeshInstance3D
	var walls: Array = item.get("walls", [])
	var smoke := item["smoke"] as MeshInstance3D
	var smoke_edge := item["smoke_edge"] as MeshInstance3D
	var hot := item["hot"] as MeshInstance3D
	var l150 := item["l150"] as MeshInstance3D
	var label := item["label"] as Label3D
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))

	var temp_upper_c: float = float(rs.get("temp_upper_c", 20.0))
	var smoke_kg: float = float(rs.get("smoke_kg", 0.0))
	var smoke_layer_m: float = clampf(float(rs.get("smoke_display_layer_m", rs.get("smoke_layer_m", rs.get("h_layer_m", height_m)))), 0.0, height_m)
	var hot_layer_m: float = clampf(float(rs.get("hot_layer_m", rs.get("thermal_layer_m", height_m))), 0.0, height_m)
	var layer_150c_m: float = clampf(float(rs.get("layer_150c_m", height_m)), 0.0, height_m)
	var hrr_kw: float = maxf(0.0, float(rs.get("hrr_kw", 0.0)))
	var visibility_m: float = float(rs.get("visibility_m", 30.0))

	var floor_mat := floor.material_override as StandardMaterial3D
	if floor_mat != null:
		var heat_t: float = clampf(
			inverse_lerp(temp_heat_floor_start_c, temp_heat_floor_full_c, temp_upper_c),
			0.0,
			1.0
		)
		floor_mat.albedo_color = floor_color.lerp(hot_floor_color, heat_t)
	_update_wall_temperature(walls, temp_upper_c)

	_update_smoke_volume(item, smoke, smoke_edge, rect, height_m, smoke_layer_m, smoke_kg, hrr_kw, visibility_m)
	SmokeLayerVisuals.update_layer_box(
		hot,
		rect,
		height_m,
		hot_layer_m,
		hot_layer_color,
		show_hot_layer and temp_upper_c > temp_heat_floor_start_c and hot_layer_m < height_m - hot_layer_visible_drop_m,
		room_inset_m,
		meters_to_units,
		_origin_offset_m,
		floor_level_m
	)
	SmokeLayerVisuals.update_layer_box(
		l150,
		rect,
		height_m,
		layer_150c_m,
		layer_150c_color,
		show_layer_150c and temp_upper_c >= 150.0 and layer_150c_m < height_m - layer_150c_visible_drop_m,
		room_inset_m,
		meters_to_units,
		_origin_offset_m,
		floor_level_m
	)
	_update_fire_visual(item, rect, height_m, hrr_kw, rs)

	if label != null:
		label.visible = show_room_labels
		label.text = _get_room_label(room_id, rs)

	_update_room_fuel_objects_3d(item, rs, rect)
	_update_room_safety_markers_3d(room_id, item, rect)


func _update_wall_temperature(walls: Array, temp_upper_c: float) -> void:
	var heat_t: float = clampf(
		inverse_lerp(temp_heat_wall_start_c, temp_heat_wall_full_c, temp_upper_c),
		0.0,
		1.0
	)
	var color: Color = wall_color.lerp(hot_wall_color, heat_t)
	for wall in walls:
		var wall_mesh := wall as MeshInstance3D
		if wall_mesh == null:
			continue
		var mat := wall_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = color


func _update_smoke_volume(
	item: Dictionary,
	node: MeshInstance3D,
	edge_node: MeshInstance3D,
	rect: Rect2,
	height_m: float,
	smoke_layer_m: float,
	smoke_kg: float,
	hrr_kw: float,
	visibility_m: float
) -> void:
	if node == null:
		return
	var target_depth_m: float = maxf(0.0, height_m - smoke_layer_m)
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))
	if smoke_kg <= smoke_visible_threshold_kg:
		target_depth_m = 0.0
	var hrr_smoke_t: float = clampf(sqrt(maxf(0.0, hrr_kw) / maxf(1.0, smoke_hrr_reference_kw)), 0.0, 1.0)
	if hrr_kw > fire_min_visible_hrr_kw:
		target_depth_m = maxf(target_depth_m, smoke_hrr_depth_boost_m * hrr_smoke_t)
	target_depth_m = clampf(target_depth_m, 0.0, height_m)

	var current_depth_m: float = float(item.get("smoke_visual_depth_m", 0.0))
	var lerp_weight: float = smoke_grow_lerp if target_depth_m > current_depth_m else smoke_clear_lerp
	current_depth_m = lerpf(current_depth_m, target_depth_m, clampf(lerp_weight, 0.0, 1.0))
	if target_depth_m <= 0.0 and current_depth_m < 0.01:
		current_depth_m = 0.0
	item["smoke_visual_depth_m"] = current_depth_m

	var smoke_geometry_visible: bool = show_smoke_volume \
		and current_depth_m > smoke_min_visible_depth_m \
		and (not _first_person_overlay or show_smoke_geometry_in_first_person)
	var smoke_puffs_visible: bool = show_smoke_volume \
		and current_depth_m > smoke_min_visible_depth_m * 1.4 \
		and (not _first_person_overlay or show_smoke_puffs_in_first_person)
	node.visible = smoke_geometry_visible
	if edge_node != null:
		edge_node.visible = smoke_geometry_visible
	var ceiling_mask := item.get("smoke_ceiling_mask") as MeshInstance3D
	SmokeLayerVisuals.update_ceiling_mask(
		ceiling_mask,
		rect,
		height_m,
		show_smoke_volume and show_smoke_ceiling_masks and not _first_person_overlay and current_depth_m > smoke_min_visible_depth_m,
		room_inset_m,
		meters_to_units,
		_origin_offset_m,
		floor_level_m
	)

	var visibility_t: float = clampf((18.0 - visibility_m) / 18.0, 0.0, 1.0)
	var alpha_cap: float = 0.62 if _first_person_overlay else 0.50
	var alpha: float = clampf(
		smoke_color.a
			+ smoke_kg / maxf(0.01, smoke_reference_kg) * 0.20
			+ visibility_t * (0.24 if _first_person_overlay else 0.14)
			+ hrr_smoke_t * smoke_hrr_alpha_boost * 0.72,
		0.07,
		alpha_cap
	)
	var render_depth_m: float = maxf(
		smoke_min_visible_depth_m,
		current_depth_m - (0.045 if _first_person_overlay else 0.018)
	)
	var smoke_mat := node.material_override as ShaderMaterial
	if smoke_mat != null:
		var volume_alpha_scale: float = 1.52 if _first_person_overlay else 0.76
		smoke_mat.set_shader_parameter("smoke_color", Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha * volume_alpha_scale))
		var volume_density: float = clampf(0.66 + alpha * 1.50 + visibility_t * 0.22, 0.56, 1.46) if _first_person_overlay else clampf(0.44 + alpha * 1.12 + visibility_t * 0.12, 0.38, 1.04)
		smoke_mat.set_shader_parameter("density", volume_density)
		smoke_mat.set_shader_parameter("turbulence", clampf(0.58 + hrr_smoke_t * 0.34, 0.50, 0.95))
		smoke_mat.set_shader_parameter("drift_speed", 0.070 + hrr_smoke_t * 0.18)
		smoke_mat.set_shader_parameter("volume_depth_m", maxf(render_depth_m, 0.05))
		smoke_mat.set_shader_parameter("edge_softness", lerpf(0.16, 0.30, hrr_smoke_t) if _first_person_overlay else lerpf(0.12, 0.24, hrr_smoke_t))
		smoke_mat.set_shader_parameter("bottom_waviness", lerpf(0.18, 0.34, hrr_smoke_t) if _first_person_overlay else lerpf(0.12, 0.26, hrr_smoke_t))
		smoke_mat.set_shader_parameter("edge_band_strength", 0.76 if _first_person_overlay else 0.30)
		smoke_mat.set_shader_parameter("side_visibility", 0.0 if _first_person_overlay else 0.22)
		smoke_mat.set_shader_parameter("bottom_surface_strength", 1.10 if _first_person_overlay else 0.72)
		smoke_mat.set_shader_parameter("top_visibility", 0.0)
	else:
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha * 0.48)

	var visual_bottom_m: float = height_m - current_depth_m
	item["smoke_bottom_m"] = visual_bottom_m
	item["smoke_alpha"] = alpha

	if smoke_geometry_visible:
		var mesh := node.mesh as BoxMesh
		if mesh != null:
			mesh.size = Vector3(
				maxf(0.05, rect.size.x - room_inset_m * 2.0),
				render_depth_m,
				maxf(0.05, rect.size.y - room_inset_m * 2.0)
			) * meters_to_units
		node.position = _room_center(rect, visual_bottom_m + render_depth_m * 0.5, floor_level_m)

		if edge_node != null:
			var edge_mesh := edge_node.mesh as BoxMesh
			var edge_height_m: float = 0.16 if _first_person_overlay else 0.030
			if edge_mesh != null:
				edge_mesh.size = Vector3(
					maxf(0.05, rect.size.x - room_inset_m * 2.0),
					edge_height_m,
					maxf(0.05, rect.size.y - room_inset_m * 2.0)
				) * meters_to_units
			edge_node.position = _room_center(rect, visual_bottom_m + edge_height_m * 0.5, floor_level_m)
			var edge_shader := edge_node.material_override as ShaderMaterial
			if edge_shader != null:
				var edge_alpha: float = clampf(alpha * (0.74 if _first_person_overlay else 0.30), 0.06, 0.38)
				edge_shader.set_shader_parameter("smoke_color", Color(smoke_layer_edge_color.r, smoke_layer_edge_color.g, smoke_layer_edge_color.b, edge_alpha))
				edge_shader.set_shader_parameter("density", 1.05 if _first_person_overlay else 0.48)
				edge_shader.set_shader_parameter("turbulence", 0.86)
				edge_shader.set_shader_parameter("drift_speed", 0.13)
				edge_shader.set_shader_parameter("volume_depth_m", maxf(edge_height_m, 0.05))
				edge_shader.set_shader_parameter("edge_softness", 0.24)
				edge_shader.set_shader_parameter("bottom_waviness", 0.42)
				edge_shader.set_shader_parameter("edge_band_strength", 1.05 if _first_person_overlay else 0.78)
				edge_shader.set_shader_parameter("side_visibility", 0.00 if _first_person_overlay else 0.10)
				edge_shader.set_shader_parameter("bottom_surface_strength", 1.22 if _first_person_overlay else 0.88)
				edge_shader.set_shader_parameter("top_visibility", 0.0)

	var puffs_root := item.get("smoke_puffs_root") as Node3D
	if puffs_root != null:
		puffs_root.visible = smoke_puffs_visible


func _update_fire_visual(item: Dictionary, rect: Rect2, room_height_m: float, hrr_kw: float, rs: Dictionary = {}) -> void:
	var fire_root := item.get("fire_root") as Node3D
	if fire_root == null:
		return
	var anchor: Dictionary = _find_fire_anchor(item, rect, rs)
	var fire_pos: Vector3 = Vector3(anchor.get("position", _room_center(rect, 0.0)))
	var fire_base_y_m: float = float(anchor.get("base_y_m", 0.0))
	var source_radius_m: float = float(anchor.get("radius_m", fire_base_radius_m))
	var available_height_m: float = maxf(0.24, room_height_m - fire_base_y_m - fire_ceiling_clearance_m)
	var target_height: float = 0.0
	var target_radius: float = fire_base_radius_m
	var target_cap_radius: float = 0.0
	var target_cap_weight: float = 0.0
	if show_hrr_columns and hrr_kw > fire_min_visible_hrr_kw:
		var fire_t: float = clampf(hrr_kw / maxf(1.0, hrr_reference_kw), 0.0, 1.8)
		var ceiling_height_m: float = maxf(0.16, available_height_m)
		var free_plume_height_m: float = clampf(
			0.16 + fire_t * fire_max_extra_height_m,
			0.16,
			available_height_m + fire_max_extra_height_m
		)
		target_height = minf(free_plume_height_m, ceiling_height_m)
		target_radius = maxf(source_radius_m, lerpf(fire_base_radius_m, fire_max_radius_m, clampf(fire_t, 0.0, 1.0)))
		var near_ceiling_t: float = clampf(
			inverse_lerp(ceiling_height_m * fire_ceiling_cap_start_fraction, ceiling_height_m, free_plume_height_m),
			0.0,
			1.0
		)
		var over_ceiling_t: float = clampf(
			(free_plume_height_m - ceiling_height_m) / maxf(0.10, fire_max_extra_height_m),
			0.0,
			1.0
		)
		target_cap_weight = maxf(near_ceiling_t * 0.35, over_ceiling_t)
		if target_cap_weight > 0.0:
			var room_cap_limit_m: float = maxf(
				fire_ceiling_cap_min_radius_m,
				minf(fire_ceiling_cap_max_radius_m, minf(rect.size.x, rect.size.y) * 0.46)
			)
			target_cap_radius = lerpf(
				fire_ceiling_cap_min_radius_m,
				room_cap_limit_m,
				clampf(maxf(near_ceiling_t, over_ceiling_t), 0.0, 1.0)
			)

	var current_height: float = float(item.get("fire_height_m", 0.0))
	var current_radius: float = float(item.get("fire_radius_m", fire_base_radius_m))
	var current_cap_radius: float = float(item.get("fire_cap_radius_m", 0.0))
	var current_cap_weight: float = float(item.get("fire_cap_weight", 0.0))
	current_height = lerpf(current_height, target_height, 0.20)
	current_radius = lerpf(current_radius, target_radius, 0.24)
	current_cap_radius = lerpf(current_cap_radius, target_cap_radius, 0.22)
	current_cap_weight = lerpf(current_cap_weight, target_cap_weight, 0.22)
	item["fire_height_m"] = current_height
	item["fire_radius_m"] = current_radius
	item["fire_cap_radius_m"] = current_cap_radius
	item["fire_cap_weight"] = current_cap_weight
	item["fire_available_height_m"] = available_height_m

	fire_root.visible = current_height > 0.05
	fire_root.position = fire_pos
	var fire_light := item.get("fire_light") as OmniLight3D
	if fire_light != null:
		var hrr_t: float = clampf(hrr_kw / 1000.0, 0.0, 4.0)
		var target_energy: float = fire_light_energy_per_1000kw * hrr_t if fire_root.visible else 0.0
		item["fire_light_energy_target"] = target_energy
		fire_light.light_energy = target_energy
		fire_light.omni_range = lerpf(fire_light_range_min_m, fire_light_range_max_m, clampf(hrr_kw / 1800.0, 0.0, 1.0))
		fire_light.position.y = maxf(0.35, minf(available_height_m - 0.10, current_height * 0.45 + 0.45)) * meters_to_units
	if fire_root.visible:
		_animate_fire_item(item)


func _find_fire_anchor(item: Dictionary, rect: Rect2, rs: Dictionary) -> Dictionary:
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))
	var anchor_pos: Vector3 = _room_center(rect, 0.0, floor_level_m)
	var anchor_y_m: float = 0.0
	var anchor_radius_m: float = fire_base_radius_m
	var fuel_objects: Array = rs.get("fuel_objects", [])
	if fuel_objects.is_empty():
		item["fire_anchor_id"] = ""
		return {"position": anchor_pos, "base_y_m": anchor_y_m, "radius_m": anchor_radius_m}

	var best_obj: Dictionary = {}
	var best_score: float = -1.0
	var room_hrr_kw: float = maxf(float(rs.get("hrr_kw", 0.0)), float(rs.get("burned_hrr_kw", 0.0)))
	var previous_id: String = String(item.get("fire_anchor_id", ""))
	var previous_obj: Dictionary = {}
	var previous_score: float = -1.0
	for raw in fuel_objects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw
		var obj_id: String = String(obj.get("id", ""))
		var is_previous_anchor: bool = previous_id != "" and obj_id == previous_id
		if is_previous_anchor:
			previous_obj = obj
		var state_name: String = String(obj.get("state", "cold")).to_lower()
		var score: float = maxf(float(obj.get("hrr_kw", 0.0)), float(obj.get("hrr", 0.0)))
		var is_active_state: bool = state_name == "flaming" or state_name == "pyrolyzing" or state_name == "decaying"
		match state_name:
			"flaming":
				score += 1000.0
			"pyrolyzing":
				score += 620.0
			"decaying":
				score += 220.0
			"heating":
				score += 45.0
		var is_primary_source: bool = bool(obj.get("is_primary_ignition_source", false))
		if is_primary_source:
			score += 240.0
		if is_previous_anchor:
			score += 180.0
		if not is_active_state and score <= 0.01 and not is_previous_anchor and not (is_primary_source and room_hrr_kw > fire_min_visible_hrr_kw):
			continue
		if score > best_score:
			best_score = score
			best_obj = obj
		if is_previous_anchor:
			previous_score = score

	if best_obj.is_empty():
		if not previous_obj.is_empty() and room_hrr_kw > fire_min_visible_hrr_kw:
			best_obj = previous_obj
		else:
			item["fire_anchor_id"] = ""
			return {"position": anchor_pos, "base_y_m": anchor_y_m, "radius_m": anchor_radius_m}
	if not previous_obj.is_empty() and previous_score > maxf(1.0, best_score * 0.35):
		best_obj = previous_obj
	item["fire_anchor_id"] = String(best_obj.get("id", ""))

	var pos_m: Vector2 = _vector2_from_variant(best_obj.get("position_m", Vector2.ZERO), Vector2.ZERO)
	var size_m: Vector2 = _vector2_from_variant(best_obj.get("size_m", Vector2(0.5, 0.5)), Vector2(0.5, 0.5))
	var kind_name: String = _fuel_visual_archetype(best_obj)
	anchor_y_m = FurniturePlacement3D.fire_base_height_for(best_obj, kind_name)
	anchor_radius_m = clampf(maxf(minf(size_m.x, size_m.y) * 0.34, sqrt(maxf(0.01, size_m.x * size_m.y)) * 0.20), fire_base_radius_m, fire_max_radius_m)
	anchor_pos = _to_world(Vector3(
		rect.position.x + pos_m.x + size_m.x * 0.5,
		floor_level_m + anchor_y_m,
		rect.position.y + pos_m.y + size_m.y * 0.5
	))
	return {"position": anchor_pos, "base_y_m": anchor_y_m, "radius_m": anchor_radius_m}


func _vector2_from_variant(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return fallback


func _update_fire_animation() -> void:
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		var fire_root := item.get("fire_root") as Node3D
		if fire_root != null and fire_root.visible:
			_animate_fire_item(item)


func _update_smoke_animation() -> void:
	for room_id in _room_items.keys():
		_animate_smoke_item(_room_items[room_id])


func _animate_smoke_item(item: Dictionary) -> void:
	SmokeAnimation3D.animate(item, _fire_phase, {
		"meters_to_units": meters_to_units,
		"origin_offset_m": _origin_offset_m,
		"room_inset_m": room_inset_m,
		"default_room_height_m": default_room_height_m,
		"smoke_min_visible_depth_m": smoke_min_visible_depth_m,
		"smoke_puff_color": smoke_puff_color,
	})


func _animate_fire_item(item: Dictionary) -> void:
	FireAnimation3D.animate(item, _fire_phase, {
		"meters_to_units": meters_to_units,
		"fire_base_radius_m": fire_base_radius_m,
		"default_room_height_m": default_room_height_m,
		"fire_flicker_strength": fire_flicker_strength,
		"fire_ceiling_cap_thickness_m": fire_ceiling_cap_thickness_m,
	})


func _update_openings() -> void:
	if building == null:
		return
	for index in _opening_items.keys():
		var op: OpeningModel = building.get_opening_at(int(index))
		if op == null:
			continue
		var item_dict: Dictionary = Dictionary(_opening_items[index])
		var marker := item_dict.get("marker") as MeshInstance3D
		if marker == null:
			continue
		var mat := marker.material_override as StandardMaterial3D
		if mat != null:
			var open_color: Color = _opening_color(op)
			var marker_color: Color = closed_opening_color.lerp(open_color, clampf(op.open_fraction, 0.0, 1.0))
			if int(index) == _selected_opening_index:
				marker_color = marker_color.lerp(Color(1.0, 0.88, 0.18, 1.0), 0.55)
			mat.albedo_color = marker_color

		SmokeOpeningCurtain3D.update(item_dict, op, _room_items, {
			"show_smoke_volume": show_smoke_volume,
			"first_person_overlay": _first_person_overlay,
			"show_smoke_geometry_in_first_person": show_smoke_geometry_in_first_person,
			"smoke_opening_blend_depth_m": smoke_opening_blend_depth_m,
			"smoke_min_visible_depth_m": smoke_min_visible_depth_m,
			"meters_to_units": meters_to_units,
			"origin_offset_m": _origin_offset_m,
			"smoke_color": smoke_color,
		})


func _create_box(node_name: String, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _make_smoke_volume_material() -> ShaderMaterial:
	return SmokeVolumeMaterialFactory.create_volume(smoke_color)


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.metallic = 0.0
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _disable_shadow_casting(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_disable_shadow_casting(child)


func _room_center(rect_m: Rect2, y_m: float, floor_level_m: float = 0.0) -> Vector3:
	var center: Vector2 = rect_m.position + rect_m.size * 0.5
	return _to_world(Vector3(center.x, floor_level_m + y_m, center.y))


func _to_world(pos_m: Vector3) -> Vector3:
	return Vector3(
		(pos_m.x + _origin_offset_m.x) * meters_to_units,
		pos_m.y * meters_to_units,
		(pos_m.z + _origin_offset_m.y) * meters_to_units
	)


func _get_room_height(room_id: int) -> float:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	if room != null:
		return maxf(0.1, room.height_m)
	return default_room_height_m


func _get_room_floor_level(room_id: int) -> float:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	return room.floor_level_z_m if room != null else 0.0


func _is_stair_room(room: RoomModel) -> bool:
	if room == null:
		return false
	var kind: String = room.kind.to_lower()
	var name: String = room.name.to_lower()
	return kind.contains("escalera") or kind.contains("stair") or name.contains("escalera") or name.contains("stair")


func _find_next_floor_level_above(level_m: float) -> float:
	var best: float = INF
	if building == null:
		return -1.0
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(room_id))
		if room != null and room.floor_level_z_m > level_m + 0.20:
			best = minf(best, room.floor_level_z_m)
	return best if best < INF else -1.0


func _get_room_name(room_id: int) -> String:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	if room != null and room.name != "":
		return room.name
	return "Sala_%02d" % room_id


func _get_room_label(room_id: int, _room_state: Dictionary = {}) -> String:
	var room_name: String = _get_room_name(room_id).strip_edges()
	if room_name != "":
		return room_name
	return "R%d" % room_id


func _update_room_safety_markers_3d(room_id: int, item: Dictionary, rect: Rect2) -> void:
	var root := item.get("safety_markers_root") as Node3D
	if root == null:
		return
	root.visible = not _first_person_overlay and (show_detector_markers_3d or show_victim_markers_3d)
	if building == null:
		root.visible = false
		return

	var detector_nodes: Dictionary = item.get("detector_nodes", {})
	var victim_nodes: Dictionary = item.get("victim_nodes", {})
	var seen_detectors: Dictionary = {}
	var seen_victims: Dictionary = {}
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))
	var room_height_m: float = float(item.get("height_m", default_room_height_m))

	if show_detector_markers_3d:
		var detector_states: Dictionary = _state_records_by_id(Array(state.get("detectors", [])))
		for raw_det in building.detectors:
			if typeof(raw_det) != TYPE_DICTIONARY:
				continue
			var det: Dictionary = raw_det
			if int(det.get("room_id", -1)) != room_id:
				continue
			var det_id: String = String(det.get("id", "det_%d" % detector_nodes.size()))
			seen_detectors[det_id] = true
			var node := detector_nodes.get(det_id) as Node3D
			if node == null:
				node = _create_detector_marker_node(det_id)
				root.add_child(node)
				detector_nodes[det_id] = node
			var local_pos: Vector2 = _safety_local_position(det, rect)
			node.position = _to_world(Vector3(rect.position.x + local_pos.x, floor_level_m + room_height_m - 0.08, rect.position.y + local_pos.y))
			var det_state: Dictionary = detector_states.get(det_id, {})
			var triggered: bool = bool(det_state.get("triggered", det.get("triggered", false)))
			_set_marker_color(node, detector_triggered_color if triggered else detector_marker_color)

	if show_victim_markers_3d:
		var victim_states: Dictionary = _state_records_by_id(Array(state.get("victims", [])))
		for raw_vic in building.victims:
			if typeof(raw_vic) != TYPE_DICTIONARY:
				continue
			var vic: Dictionary = raw_vic
			if int(vic.get("room_id", -1)) != room_id:
				continue
			var vic_id: String = String(vic.get("id", "vic_%d" % victim_nodes.size()))
			seen_victims[vic_id] = true
			var node := victim_nodes.get(vic_id) as Node3D
			if node == null:
				node = _create_victim_marker_node(vic_id)
				root.add_child(node)
				victim_nodes[vic_id] = node
			var local_pos: Vector2 = _safety_local_position(vic, rect)
			node.position = _to_world(Vector3(rect.position.x + local_pos.x, floor_level_m, rect.position.y + local_pos.y))
			var vic_state: Dictionary = victim_states.get(vic_id, {})
			var incapacitated: bool = bool(vic_state.get("incapacitated", vic.get("incapacitated", false)))
			_set_marker_color(node, victim_incapacitated_color if incapacitated else victim_marker_color)

	_prune_marker_nodes(detector_nodes, seen_detectors)
	_prune_marker_nodes(victim_nodes, seen_victims)
	item["detector_nodes"] = detector_nodes
	item["victim_nodes"] = victim_nodes


func _state_records_by_id(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = raw_record
		var id_text: String = String(record.get("id", ""))
		if id_text != "":
			result[id_text] = record
	return result


func _safety_local_position(data: Dictionary, rect: Rect2) -> Vector2:
	if data.has("x_m") and data.has("y_m"):
		return Vector2(
			clampf(float(data.get("x_m", rect.size.x * 0.5)), 0.0, rect.size.x),
			clampf(float(data.get("y_m", rect.size.y * 0.5)), 0.0, rect.size.y)
		)
	return rect.size * 0.5


func _create_detector_marker_node(detector_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Detector_" + _safe_node_name(detector_id)
	var disk := MeshInstance3D.new()
	disk.name = "MarkerMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.11 * meters_to_units
	mesh.bottom_radius = 0.11 * meters_to_units
	mesh.height = 0.035 * meters_to_units
	mesh.radial_segments = 24
	disk.mesh = mesh
	disk.material_override = _make_material(detector_marker_color, false)
	root.add_child(disk)
	return root


func _create_victim_marker_node(victim_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Victim_" + _safe_node_name(victim_id)
	var mat := _make_material(victim_marker_color, false)
	var body := _create_human_limb_mesh("MarkerMesh", 0.16, 0.70, mat)
	body.rotation_degrees.x = 90.0
	body.position = Vector3(0.0, 0.14 * meters_to_units, 0.0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13 * meters_to_units
	head_mesh.height = 0.26 * meters_to_units
	head_mesh.radial_segments = 14
	head_mesh.rings = 7
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.14 * meters_to_units, -0.48 * meters_to_units)
	head.material_override = mat
	root.add_child(head)
	for side in [-1.0, 1.0]:
		var arm := _create_human_limb_mesh("Arm_%s" % str(side), 0.055, 0.48, mat)
		arm.rotation_degrees.z = 90.0
		arm.rotation_degrees.y = 12.0 * side
		arm.position = Vector3(side * 0.31 * meters_to_units, 0.10 * meters_to_units, -0.05 * meters_to_units)
		root.add_child(arm)
		var leg := _create_human_limb_mesh("Leg_%s" % str(side), 0.07, 0.56, mat)
		leg.rotation_degrees.x = 90.0
		leg.rotation_degrees.z = 7.0 * side
		leg.position = Vector3(side * 0.12 * meters_to_units, 0.11 * meters_to_units, 0.50 * meters_to_units)
		root.add_child(leg)
	return root


func _create_human_limb_mesh(node_name: String, radius_m: float, length_m: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius_m * meters_to_units
	mesh.height = length_m * meters_to_units
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	return mesh_instance


func _set_marker_color(root: Node3D, color: Color) -> void:
	var mat := _make_material(color, false)
	_set_marker_color_recursive(root, mat)


func _set_marker_color_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_set_marker_color_recursive(child, mat)


func _prune_marker_nodes(nodes: Dictionary, seen_ids: Dictionary) -> void:
	for stale_id in nodes.keys():
		if seen_ids.has(stale_id):
			continue
		var stale_node := nodes[stale_id] as Node
		if stale_node != null:
			stale_node.free()
		nodes.erase(stale_id)


func _safe_node_name(value: String) -> String:
	var cleaned: String = value.strip_edges()
	for ch in [" ", "/", "\\", ":", ".", "#"]:
		cleaned = cleaned.replace(ch, "_")
	return cleaned if cleaned != "" else "marker"


func _update_room_fuel_objects_3d(item: Dictionary, rs: Dictionary, rect: Rect2) -> void:
	var fuel_objects_root := item.get("fuel_objects_root") as Node3D
	if fuel_objects_root == null:
		return
	var fuel_obj_nodes: Dictionary = item.get("fuel_obj_nodes", {})
	var objects: Array = rs.get("fuel_objects", [])

	if _first_person_overlay:
		fuel_objects_root.visible = false
		return
	if not show_fuel_objects_3d:
		fuel_objects_root.visible = false
		return
	if objects.is_empty():
		fuel_objects_root.visible = fuel_obj_nodes.size() > 0
		return
	fuel_objects_root.visible = true

	var seen_ids: Dictionary = {}
	for raw_obj in objects:
		if typeof(raw_obj) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw_obj
		var obj_id: String = String(obj.get("id", ""))
		if obj_id == "":
			continue
		if obj_id.begins_with("room_proxy_"):
			continue
		seen_ids[obj_id] = true

		var pos_v = obj.get("position_m", Vector2.ZERO)
		var sz_v = obj.get("size_m", Vector2(0.5, 0.5))
		var pos_m := Vector2(float(pos_v.x) if typeof(pos_v) == TYPE_VECTOR2 else float(pos_v.get("x", 0.0)),
				float(pos_v.y) if typeof(pos_v) == TYPE_VECTOR2 else float(pos_v.get("y", 0.0)))
		var size_m := Vector2(float(sz_v.x) if typeof(sz_v) == TYPE_VECTOR2 else float(sz_v.get("x", 0.5)),
				float(sz_v.y) if typeof(sz_v) == TYPE_VECTOR2 else float(sz_v.get("y", 0.5)))
		if size_m.x < 0.05 or size_m.y < 0.05:
			continue

		var state_name: String = String(obj.get("state", "cold"))
		var kind_name: String = _fuel_visual_archetype(obj)
		var rotation_deg: float = float(obj.get("rotation_deg", 0.0))
		var visual_pose: Dictionary = FurniturePlacement3D.clamp_visual_pose(rect, pos_m, size_m, rotation_deg)
		var visual_center_m: Vector2 = visual_pose.get("center_m", pos_m + size_m * 0.5)
		var visual_size_m: Vector2 = visual_pose.get("size_m", size_m)

		var node: Node3D
		if fuel_obj_nodes.has(obj_id):
			node = fuel_obj_nodes[obj_id] as Node3D
		else:
			node = _create_fuel_object_node(obj_id, kind_name, visual_size_m)
			fuel_objects_root.add_child(node)
			fuel_obj_nodes[obj_id] = node

		if node == null:
			continue
		if _fuel_shape_needs_rebuild(node, kind_name, visual_size_m):
			_rebuild_fuel_object_shape(node, kind_name, visual_size_m)

		var center_x: float = rect.position.x + visual_center_m.x
		var center_z: float = rect.position.y + visual_center_m.y
		node.position = _to_world(Vector3(center_x, float(item.get("floor_level_m", 0.0)), center_z))
		node.rotation_degrees.y = rotation_deg

		var color: Color = FurnitureStateVisuals.color_for_state(state_name)
		var fuel_mj: float = maxf(0.01, float(obj.get("fuel_energy_MJ", 1.0)))
		var remaining_ratio: float = clampf(float(obj.get("remaining_fuel_MJ", fuel_mj)) / fuel_mj, 0.0, 1.0)
		FurnitureStateVisuals.apply(node, state_name, color, remaining_ratio, bool(obj.get("is_primary_ignition_source", false)))

		# SF-AUD-004: llama 3D por objeto — se muestra cuando estado es FLAMING.
		# Se crea al primer ciclo y se escala por hrr_kw del objeto.
		var obj_flame := node.get_node_or_null("ObjFlame") as MeshInstance3D
		var obj_hrr_kw: float = maxf(0.0, float(obj.get("hrr_kw", 0.0)))
		if state_name == "flaming" and obj_hrr_kw > 0.5:
			if obj_flame == null:
				obj_flame = FireMeshFactory.create_flame_mesh("ObjFlame", fire_color, fire_core_color)
				node.add_child(obj_flame)
			obj_flame.visible = true
			var flame_scale: float = clampf(
				0.10 + sqrt(maxf(0.0, obj_hrr_kw / maxf(1.0, float(obj.get("max_hrr_kw", 100.0))))),
				0.08, 0.55
			) * minf(float(visual_size_m.x), float(visual_size_m.y)) * meters_to_units
			obj_flame.scale = Vector3(flame_scale, flame_scale * 1.4, flame_scale)
			obj_flame.position = Vector3(0.0, fuel_object_3d_height_m * meters_to_units, 0.0)
		elif obj_flame != null:
			obj_flame.visible = false

	for stale_id in fuel_obj_nodes.keys():
		if seen_ids.has(stale_id):
			continue
		var stale_node := fuel_obj_nodes[stale_id] as Node
		if stale_node != null:
			stale_node.free()
		fuel_obj_nodes.erase(stale_id)

	item["fuel_obj_nodes"] = fuel_obj_nodes
	fuel_objects_root.visible = fuel_obj_nodes.size() > 0


func _create_fuel_object_node(obj_id: String, kind_name: String, size_m: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "FuelObj_" + obj_id
	_rebuild_fuel_object_shape(node, kind_name, size_m)
	return node


func _fuel_visual_archetype(obj: Dictionary) -> String:
	return FurnitureVisualClassifier.visual_archetype(obj)


func _fuel_shape_needs_rebuild(node: Node3D, kind_name: String, size_m: Vector2) -> bool:
	return FurnitureVisualClassifier.shape_needs_rebuild(node, kind_name, size_m)


func _rebuild_fuel_object_shape(node: Node3D, kind_name: String, size_m: Vector2) -> void:
	_clear_container(node)
	node.set_meta("kind_name", kind_name)
	node.set_meta("size_x", size_m.x)
	node.set_meta("size_y", size_m.y)
	FurnitureShapeBuilder.rebuild(node, kind_name, size_m, meters_to_units, fuel_object_3d_height_m)


func _fit_camera_to_building() -> void:
	if _bounds_m.size == Vector2.ZERO:
		return
	_camera_distance = CameraOrbit3D.fit_distance(_bounds_m, meters_to_units, min_camera_distance_m, max_camera_distance_m)


func _apply_camera_transform() -> void:
	CameraOrbit3D.apply_transform(_camera_rig, _camera, _orbit_x, _orbit_y, _camera_distance)
