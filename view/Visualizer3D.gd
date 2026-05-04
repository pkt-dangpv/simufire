extends Node3D
class_name Visualizer3D

## Basic editable 3D view for the same BuildingModel / SimulationEngine state.
## The scene owns the camera, lights, and container nodes; this script only
## rebuilds generated room meshes from the current building template.

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

@export_group("Colors")
@export var floor_color: Color = Color(0.18, 0.18, 0.17, 1.0)
@export var hot_floor_color: Color = Color(0.46, 0.30, 0.18, 1.0)
@export var wall_color: Color = Color(0.84, 0.86, 0.82, 0.42)
@export var hot_wall_color: Color = Color(1.00, 0.42, 0.12, 0.68)
@export var wall_outline_color: Color = Color(0.95, 0.95, 0.90, 0.72)
@export var smoke_color: Color = Color(0.26, 0.27, 0.30, 0.28)
@export var smoke_layer_edge_color: Color = Color(0.58, 0.62, 0.66, 0.55)
@export var hot_layer_color: Color = Color(1.00, 0.58, 0.18, 0.18)
@export var layer_150c_color: Color = Color(1.00, 0.12, 0.06, 0.70)
@export var fire_color: Color = Color(1.00, 0.38, 0.06, 0.88)
@export var fire_core_color: Color = Color(1.0, 0.84, 0.24, 0.96)
@export var fire_glow_color: Color = Color(1.0, 0.22, 0.04, 0.28)
@export var fire_ceiling_cap_color: Color = Color(1.0, 0.34, 0.05, 0.42)
@export var door_color: Color = Color(0.26, 0.86, 0.32, 0.92)
@export var window_color: Color = Color(0.24, 0.56, 1.00, 0.92)
@export var closed_opening_color: Color = Color(0.54, 0.56, 0.58, 0.70)
@export var label_color: Color = Color(1.0, 0.96, 0.84, 1.0)

@export_group("Dynamics")
@export var smoke_visible_threshold_kg: float = 0.01
@export var smoke_reference_kg: float = 1.2
@export var smoke_min_visible_depth_m: float = 0.05
@export var smoke_hrr_reference_kw: float = 900.0
@export var smoke_hrr_depth_boost_m: float = 0.55
@export var smoke_hrr_alpha_boost: float = 0.18
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
var _fire_phase: float = 0.0


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


func set_active(active: bool) -> void:
	visible = active
	if _camera != null:
		_camera.current = active
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


func _input(event: InputEvent) -> void:
	if not enable_mouse_camera or not is_visible_in_tree():
		return

	if event is InputEventMouseMotion and _orbit_dragging:
		var mm := event as InputEventMouseMotion
		_orbit_y -= mm.relative.x * camera_orbit_sensitivity
		_orbit_x = clampf(
			_orbit_x - mm.relative.y * camera_orbit_sensitivity,
			deg_to_rad(-82.0),
			deg_to_rad(-18.0)
		)
		_apply_camera_transform()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and orbit_with_left_drag_on_model:
			if mb.pressed:
				_orbit_dragging = _is_screen_point_over_model(mb.position)
				if _orbit_dragging:
					get_viewport().set_input_as_handled()
			else:
				_orbit_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_dragging = true
			get_viewport().set_input_as_handled()
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP and _is_screen_point_over_model(mb.position):
			_camera_distance = maxf(min_camera_distance_m, _camera_distance - camera_zoom_step_m)
			_apply_camera_transform()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and _is_screen_point_over_model(mb.position):
			_camera_distance = minf(max_camera_distance_m, _camera_distance + camera_zoom_step_m)
			_apply_camera_transform()
			get_viewport().set_input_as_handled()


func _resolve_nodes() -> void:
	_rooms_root = _get_or_create_node3d(rooms_path, "Rooms")
	_openings_root = _get_or_create_node3d(openings_path, "Openings")
	_atmosphere_root = _get_or_create_node3d(atmosphere_path, "Atmosphere")
	_labels_root = _get_or_create_node3d(labels_path, "Labels")
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	_camera = get_node_or_null(camera_path) as Camera3D


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

	for index in range(building.get_opening_count()):
		_create_opening(index)

	_built = true


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


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
	var room_node := Node3D.new()
	room_node.name = "Room_%02d_%s" % [room_id, _safe_name(_get_room_name(room_id))]
	_rooms_root.add_child(room_node)

	var height_m: float = _get_room_height(room_id)
	var floor := _create_box(
		"Floor",
		Vector3(rect_m.size.x, floor_thickness_m, rect_m.size.y) * meters_to_units,
		_make_material(floor_color, false)
	)
	floor.position = _room_center(rect_m, -floor_thickness_m * 0.5)
	room_node.add_child(floor)

	var walls: Array[MeshInstance3D] = []
	if show_walls:
		var w := wall_thickness_m
		walls.append(_add_wall(room_node, "WallTop", rect_m, Vector3(rect_m.size.x + w, height_m, w), Vector2(rect_m.position.x + rect_m.size.x * 0.5, rect_m.position.y)))
		walls.append(_add_wall(room_node, "WallBottom", rect_m, Vector3(rect_m.size.x + w, height_m, w), Vector2(rect_m.position.x + rect_m.size.x * 0.5, rect_m.position.y + rect_m.size.y)))
		walls.append(_add_wall(room_node, "WallLeft", rect_m, Vector3(w, height_m, rect_m.size.y + w), Vector2(rect_m.position.x, rect_m.position.y + rect_m.size.y * 0.5)))
		walls.append(_add_wall(room_node, "WallRight", rect_m, Vector3(w, height_m, rect_m.size.y + w), Vector2(rect_m.position.x + rect_m.size.x, rect_m.position.y + rect_m.size.y * 0.5)))

	var smoke := _create_box("SmokeVolume", Vector3.ONE, _make_material(smoke_color, true))
	smoke.visible = false
	_atmosphere_root.add_child(smoke)

	var smoke_edge := _create_box("SmokeLayerEdge_%02d" % room_id, Vector3.ONE, _make_material(smoke_layer_edge_color, true))
	smoke_edge.visible = false
	_atmosphere_root.add_child(smoke_edge)

	var hot := _create_box("HotLayer_%02d" % room_id, Vector3.ONE, _make_material(hot_layer_color, true))
	hot.visible = false
	_atmosphere_root.add_child(hot)

	var l150 := _create_box("Layer150C_%02d" % room_id, Vector3.ONE, _make_material(layer_150c_color, true))
	l150.visible = false
	_atmosphere_root.add_child(l150)

	var fire_root := Node3D.new()
	fire_root.name = "Fire_%02d" % room_id
	fire_root.visible = false
	_atmosphere_root.add_child(fire_root)
	var fire_glow := _create_flame_mesh("Glow", fire_glow_color)
	fire_root.add_child(fire_glow)
	var fire_cap := _create_fire_ceiling_cap_mesh("CeilingCap", fire_ceiling_cap_color)
	fire_cap.visible = false
	fire_root.add_child(fire_cap)
	var fire_core := _create_flame_mesh("Core", fire_core_color)
	fire_root.add_child(fire_core)

	var label := Label3D.new()
	label.name = "Label_%02d" % room_id
	label.text = _get_room_label(room_id)
	label.modulate = label_color
	label.font_size = 54
	label.pixel_size = 0.014
	label.outline_size = 6
	label.no_depth_test = false
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = _room_center(rect_m, floor_thickness_m + 0.012)
	label.visible = show_room_labels
	_labels_root.add_child(label)

	_room_items[room_id] = {
		"rect": rect_m,
		"height_m": height_m,
		"floor": floor,
		"walls": walls,
		"smoke": smoke,
		"smoke_edge": smoke_edge,
		"hot": hot,
		"l150": l150,
		"fire_root": fire_root,
		"fire_glow": fire_glow,
		"fire_cap": fire_cap,
		"fire_core": fire_core,
		"label": label,
		"fire_height_m": 0.0,
		"fire_radius_m": fire_base_radius_m,
		"fire_cap_radius_m": 0.0,
		"fire_cap_weight": 0.0,
		"fire_phase": float(room_id) * 1.37,
		"smoke_visual_depth_m": 0.0
	}


func _add_wall(parent: Node3D, wall_name: String, rect_m: Rect2, size_m: Vector3, pos_m: Vector2) -> MeshInstance3D:
	var room_height_m: float = size_m.y
	var wall := _create_box(wall_name, size_m * meters_to_units, _make_material(wall_color, true))
	wall.position = _to_world(Vector3(pos_m.x, room_height_m * 0.5, pos_m.y))
	parent.add_child(wall)
	return wall


func _create_opening(index: int) -> void:
	if not show_openings or building == null:
		return

	var op: OpeningModel = building.get_opening_at(index)
	if op == null:
		return

	var pose: Dictionary = _opening_pose(op)
	if pose.is_empty():
		return

	var material_color: Color = door_color if op.type == OpeningModel.Type.DOOR else window_color
	if op.is_closed():
		material_color = closed_opening_color

	var marker := _create_box(
		"Opening_%02d" % index,
		Vector3(pose["size"]) * meters_to_units,
		_make_material(material_color, true)
	)
	marker.position = _to_world(Vector3(pose["position"].x, pose["position"].y, pose["position"].z))
	_openings_root.add_child(marker)
	_opening_items[index] = {"marker": marker}


func _opening_pose(op: OpeningModel) -> Dictionary:
	var room_id: int = op.a if op.a != BuildingModel.OUTSIDE_ID else op.b
	if not building.get_room_rects_m().has(room_id):
		return {}

	var rect := Rect2(building.get_room_rects_m()[room_id])
	var center_y: float = op.sill_m + op.height_m * 0.5
	var side: String = op.wall_side.strip_edges().to_lower()

	if op.is_exterior_opening() and side != "":
		return _opening_pose_on_wall(rect, side, op.width_m, op.height_m, center_y)

	var other_id: int = op.b if op.a == room_id else op.a
	if building.get_room_rects_m().has(other_id):
		var other := Rect2(building.get_room_rects_m()[other_id])
		var shared := _shared_wall_pose(rect, other, op.width_m, op.height_m, center_y)
		if not shared.is_empty():
			return shared

	var c1: Vector2 = rect.position + rect.size * 0.5
	var size := Vector3(op.width_m, op.height_m, opening_marker_depth_m)
	return {"position": Vector3(c1.x, center_y, c1.y), "size": size}


func _opening_pose_on_wall(rect: Rect2, side: String, width_m: float, height_m: float, center_y: float) -> Dictionary:
	var x_mid: float = rect.position.x + rect.size.x * 0.5
	var z_mid: float = rect.position.y + rect.size.y * 0.5
	var d: float = opening_marker_depth_m
	match side:
		"top", "north":
			return {"position": Vector3(x_mid, center_y, rect.position.y), "size": Vector3(width_m, height_m, d)}
		"bottom", "south":
			return {"position": Vector3(x_mid, center_y, rect.position.y + rect.size.y), "size": Vector3(width_m, height_m, d)}
		"left", "west":
			return {"position": Vector3(rect.position.x, center_y, z_mid), "size": Vector3(d, height_m, width_m)}
		"right", "east":
			return {"position": Vector3(rect.position.x + rect.size.x, center_y, z_mid), "size": Vector3(d, height_m, width_m)}
		_:
			return {"position": Vector3(x_mid, center_y, z_mid), "size": Vector3(width_m, height_m, d)}


func _shared_wall_pose(a: Rect2, b: Rect2, width_m: float, height_m: float, center_y: float) -> Dictionary:
	var eps: float = 0.01
	var a_right: float = a.position.x + a.size.x
	var b_right: float = b.position.x + b.size.x
	var a_bottom: float = a.position.y + a.size.y
	var b_bottom: float = b.position.y + b.size.y

	if abs(a_right - b.position.x) < eps or abs(b_right - a.position.x) < eps:
		var x: float = a_right if abs(a_right - b.position.x) < eps else a.position.x
		var z1: float = maxf(a.position.y, b.position.y)
		var z2: float = minf(a_bottom, b_bottom)
		if z2 > z1:
			return {"position": Vector3(x, center_y, (z1 + z2) * 0.5), "size": Vector3(opening_marker_depth_m, height_m, minf(width_m, z2 - z1))}

	if abs(a_bottom - b.position.y) < eps or abs(b_bottom - a.position.y) < eps:
		var z: float = a_bottom if abs(a_bottom - b.position.y) < eps else a.position.y
		var x1: float = maxf(a.position.x, b.position.x)
		var x2: float = minf(a_right, b_right)
		if x2 > x1:
			return {"position": Vector3((x1 + x2) * 0.5, center_y, z), "size": Vector3(minf(width_m, x2 - x1), height_m, opening_marker_depth_m)}

	return {}


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

	var temp_upper_c: float = float(rs.get("temp_upper_c", 20.0))
	var smoke_kg: float = float(rs.get("smoke_kg", 0.0))
	var smoke_layer_m: float = clampf(float(rs.get("smoke_layer_m", rs.get("h_layer_m", height_m))), 0.0, height_m)
	var hot_layer_m: float = clampf(float(rs.get("hot_layer_m", rs.get("thermal_layer_m", height_m))), 0.0, height_m)
	var layer_150c_m: float = clampf(float(rs.get("layer_150c_m", height_m)), 0.0, height_m)
	var hrr_kw: float = maxf(0.0, float(rs.get("hrr_kw", 0.0)))

	var floor_mat := floor.material_override as StandardMaterial3D
	if floor_mat != null:
		var heat_t: float = clampf(
			inverse_lerp(temp_heat_floor_start_c, temp_heat_floor_full_c, temp_upper_c),
			0.0,
			1.0
		)
		floor_mat.albedo_color = floor_color.lerp(hot_floor_color, heat_t)
	_update_wall_temperature(walls, temp_upper_c)

	_update_smoke_volume(item, smoke, smoke_edge, rect, height_m, smoke_layer_m, smoke_kg, hrr_kw)
	_update_layer_box(
		hot,
		rect,
		height_m,
		hot_layer_m,
		hot_layer_color,
		show_hot_layer and temp_upper_c > temp_heat_floor_start_c and hot_layer_m < height_m - hot_layer_visible_drop_m
	)
	_update_layer_box(
		l150,
		rect,
		height_m,
		layer_150c_m,
		layer_150c_color,
		show_layer_150c and temp_upper_c >= 150.0 and layer_150c_m < height_m - layer_150c_visible_drop_m
	)
	_update_fire_visual(item, rect, height_m, hrr_kw)

	if label != null:
		label.visible = show_room_labels
		label.text = _get_room_label(room_id, rs)


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
	hrr_kw: float
) -> void:
	if node == null:
		return
	var target_depth_m: float = maxf(0.0, height_m - smoke_layer_m)
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

	node.visible = show_smoke_volume and current_depth_m > smoke_min_visible_depth_m
	if edge_node != null:
		edge_node.visible = node.visible
	if not node.visible:
		return

	var mesh := node.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(
			maxf(0.05, rect.size.x - room_inset_m * 2.0),
			current_depth_m,
			maxf(0.05, rect.size.y - room_inset_m * 2.0)
		) * meters_to_units

	var alpha: float = clampf(
		smoke_color.a
			+ smoke_kg / maxf(0.01, smoke_reference_kg) * 0.28
			+ hrr_smoke_t * smoke_hrr_alpha_boost,
		0.12,
		0.78
	)
	var mat := node.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha)

	var visual_bottom_m: float = height_m - current_depth_m
	node.position = _room_center(rect, visual_bottom_m + current_depth_m * 0.5)

	if edge_node != null:
		var edge_mesh := edge_node.mesh as BoxMesh
		if edge_mesh != null:
			edge_mesh.size = Vector3(
				maxf(0.05, rect.size.x - room_inset_m * 2.0),
				0.018,
				maxf(0.05, rect.size.y - room_inset_m * 2.0)
			) * meters_to_units
		edge_node.position = _room_center(rect, visual_bottom_m)


func _update_layer_box(
	node: MeshInstance3D,
	rect: Rect2,
	height_m: float,
	layer_m: float,
	color: Color,
	should_show: bool
) -> void:
	if node == null:
		return
	node.visible = should_show and layer_m > 0.02 and layer_m < height_m - 0.02
	if not node.visible:
		return

	var mesh := node.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(
			maxf(0.05, rect.size.x - room_inset_m * 2.0),
			0.025,
			maxf(0.05, rect.size.y - room_inset_m * 2.0)
		) * meters_to_units
	var mat := node.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
	node.position = _room_center(rect, layer_m)


func _update_fire_visual(item: Dictionary, rect: Rect2, room_height_m: float, hrr_kw: float) -> void:
	var fire_root := item.get("fire_root") as Node3D
	if fire_root == null:
		return
	var target_height: float = 0.0
	var target_radius: float = fire_base_radius_m
	var target_cap_radius: float = 0.0
	var target_cap_weight: float = 0.0
	if show_hrr_columns and hrr_kw > fire_min_visible_hrr_kw:
		var fire_t: float = clampf(hrr_kw / maxf(1.0, hrr_reference_kw), 0.0, 1.8)
		var ceiling_height_m: float = maxf(0.16, room_height_m - fire_ceiling_clearance_m)
		var free_plume_height_m: float = clampf(
			0.16 + fire_t * fire_max_extra_height_m,
			0.16,
			room_height_m + fire_max_extra_height_m
		)
		target_height = minf(free_plume_height_m, ceiling_height_m)
		target_radius = lerpf(fire_base_radius_m, fire_max_radius_m, clampf(fire_t, 0.0, 1.0))
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

	fire_root.visible = current_height > 0.05
	fire_root.position = _room_center(rect, 0.0)
	if fire_root.visible:
		_animate_fire_item(item)


func _update_fire_animation() -> void:
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		var fire_root := item.get("fire_root") as Node3D
		if fire_root != null and fire_root.visible:
			_animate_fire_item(item)


func _animate_fire_item(item: Dictionary) -> void:
	var fire_root := item.get("fire_root") as Node3D
	var fire_core := item.get("fire_core") as MeshInstance3D
	var fire_glow := item.get("fire_glow") as MeshInstance3D
	var fire_cap := item.get("fire_cap") as MeshInstance3D
	if fire_root == null or fire_core == null or fire_glow == null:
		return

	var height_m: float = float(item.get("fire_height_m", 0.0))
	var radius_m: float = float(item.get("fire_radius_m", fire_base_radius_m))
	var room_height_m: float = float(item.get("height_m", default_room_height_m))
	var cap_radius_m: float = float(item.get("fire_cap_radius_m", 0.0))
	var cap_weight: float = clampf(float(item.get("fire_cap_weight", 0.0)), 0.0, 1.0)
	var phase: float = float(item.get("fire_phase", 0.0))
	var flicker: float = 1.0 \
			+ sin(_fire_phase * 8.5 + phase) * fire_flicker_strength \
			+ sin(_fire_phase * 15.0 + phase * 0.7) * fire_flicker_strength * 0.45
	var max_column_h: float = maxf(0.04, room_height_m - fire_ceiling_clearance_m)
	var core_h: float = minf(max_column_h, maxf(0.04, height_m * flicker))
	var glow_h: float = minf(max_column_h, maxf(0.04, height_m * 0.76 * (1.0 + (flicker - 1.0) * 0.55)))
	var core_r: float = maxf(0.03, radius_m * flicker)
	var glow_r: float = maxf(0.04, radius_m * 1.85)

	fire_core.scale = Vector3(core_r, core_h, core_r) * meters_to_units
	fire_core.position = Vector3(0.0, core_h * meters_to_units * 0.5, 0.0)
	fire_glow.scale = Vector3(glow_r, glow_h, glow_r) * meters_to_units
	fire_glow.position = Vector3(0.0, glow_h * meters_to_units * 0.38, 0.0)

	if fire_cap != null:
		fire_cap.visible = cap_weight > 0.03 and cap_radius_m > 0.03
		if fire_cap.visible:
			var cap_wave: float = 1.0 + sin(_fire_phase * 5.4 + phase) * fire_flicker_strength * 0.22
			var cap_h: float = fire_ceiling_cap_thickness_m * lerpf(0.65, 1.25, cap_weight)
			var ceiling_y_m: float = maxf(cap_h, room_height_m - fire_ceiling_clearance_m)
			var cap_r: float = cap_radius_m * cap_wave
			fire_cap.scale = Vector3(cap_r, cap_h, cap_r * 0.82) * meters_to_units
			fire_cap.position = Vector3(0.0, (ceiling_y_m - cap_h * 0.5) * meters_to_units, 0.0)


func _update_openings() -> void:
	if building == null:
		return
	for index in _opening_items.keys():
		var op: OpeningModel = building.get_opening_at(int(index))
		if op == null:
			continue
		var marker := Dictionary(_opening_items[index]).get("marker") as MeshInstance3D
		if marker == null:
			continue
		var mat := marker.material_override as StandardMaterial3D
		if mat != null:
			var open_color: Color = door_color if op.type == OpeningModel.Type.DOOR else window_color
			mat.albedo_color = closed_opening_color.lerp(open_color, clampf(op.open_fraction, 0.0, 1.0))


func _create_box(node_name: String, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _create_flame_mesh(node_name: String, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.42
	mesh.height = 1.0
	mesh.radial_segments = 18
	mesh.rings = 2
	var material := _make_material(color, true)
	material.emission_enabled = true
	material.emission = Color(color.r, color.g * 0.75, color.b * 0.45, 1.0)
	material.emission_energy_multiplier = 0.65
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _create_fire_ceiling_cap_mesh(node_name: String, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.82
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 28
	mesh.rings = 2
	var material := _make_material(color, true)
	material.emission_enabled = true
	material.emission = Color(color.r, color.g * 0.72, color.b * 0.45, 1.0)
	material.emission_energy_multiplier = 0.42
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _room_center(rect_m: Rect2, y_m: float) -> Vector3:
	var center: Vector2 = rect_m.position + rect_m.size * 0.5
	return _to_world(Vector3(center.x, y_m, center.y))


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


func _get_room_name(room_id: int) -> String:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	if room != null and room.name != "":
		return room.name
	return "Sala_%02d" % room_id


func _get_room_label(room_id: int, room_state: Dictionary = {}) -> String:
	var name: String = String(room_state.get("name", _get_room_name(room_id)))
	if name == "":
		name = "Sala %d" % room_id
	return "R%d %s" % [room_id, name]


func _safe_name(value: String) -> String:
	var result: String = value.strip_edges()
	if result == "":
		return "room"
	result = result.replace(" ", "_")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	return result


func _is_screen_point_over_model(screen_pos: Vector2) -> bool:
	if _camera == null:
		return true
	if _bounds_m.size == Vector2.ZERO:
		return true

	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var direction: Vector3 = _camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return false

	var t: float = -origin.y / direction.y
	if t < 0.0:
		return false

	var hit: Vector3 = origin + direction * t
	var hit_m := Vector2(
		hit.x / maxf(0.0001, meters_to_units) - _origin_offset_m.x,
		hit.z / maxf(0.0001, meters_to_units) - _origin_offset_m.y
	)
	var expanded_bounds: Rect2 = _bounds_m.grow(0.75)
	return expanded_bounds.has_point(hit_m)


func _fit_camera_to_building() -> void:
	if _bounds_m.size == Vector2.ZERO:
		return
	var largest: float = maxf(_bounds_m.size.x, _bounds_m.size.y)
	_camera_distance = clampf(largest * meters_to_units * 1.35, min_camera_distance_m, max_camera_distance_m)


func _apply_camera_transform() -> void:
	if _camera_rig == null or _camera == null:
		return
	_camera_rig.position = Vector3.ZERO
	_camera_rig.rotation = Vector3(_orbit_x, _orbit_y, 0.0)
	_camera.position = Vector3(0.0, 0.0, _camera_distance)
	_camera.rotation = Vector3.ZERO
