extends CharacterBody3D
class_name FirstPersonController

signal exit_requested
signal opening_changed

const OUTSIDE_ID: int = -1
const STANCE_STAND: int = 0
const STANCE_CROUCH: int = 1
const STANCE_PRONE: int = 2
const STARTUP_OPTIONS_PATH: String = "user://startup_sim_options.json"

@export var wall_thickness_m: float = 0.10
@export var floor_thickness_m: float = 0.10
@export var ceiling_thickness_m: float = 0.08
@export var closed_door_thickness_m: float = 0.08
@export var person_height_m: float = 1.80
@export var crouch_height_m: float = 1.05
@export var prone_height_m: float = 0.36
@export var stand_speed_m_s: float = 2.25
@export var crouch_speed_m_s: float = 1.15
@export var prone_speed_m_s: float = 0.42
@export var mouse_sensitivity: float = 0.0022
@export var interaction_range_m: float = 1.75
@export var gravity_m_s2: float = 12.0
@export var boundary_height_m: float = 2.6

@export_group("Iluminacion FP")
@export var ambient_fill_enabled: bool = true
@export var ambient_fill_energy: float = 0.30
@export var ambient_fill_color: Color = Color(0.72, 0.78, 0.82, 1.0)
@export var room_ceiling_lights_enabled: bool = true
@export var room_ceiling_light_energy: float = 0.56
@export var room_ceiling_light_range_extra_m: float = 1.25
@export var room_ceiling_light_color: Color = Color(1.0, 0.88, 0.68, 1.0)
@export var landing_light_energy: float = 0.92
@export var landing_light_closed_ratio: float = 0.12
@export var landing_light_range_m: float = 3.6
@export var landing_light_color: Color = Color(1.0, 0.84, 0.56, 1.0)
@export var window_light_energy: float = 0.86
@export var window_light_range_m: float = 4.8
@export var window_light_color: Color = Color(0.66, 0.78, 1.0, 1.0)
@export var opening_lights_cast_shadows: bool = false

@export_group("Materiales FP")
@export var use_procedural_surface_noise: bool = false
@export var material_noise_frequency: float = 0.075
@export var wall_skirting_height_m: float = 0.10
@export var show_landing_recess: bool = true
@export var landing_recess_depth_m: float = 1.25

@export_group("Ventanas FP")
@export var window_open_angle_deg: float = 68.0
@export var window_collision_when_closed: bool = true
@export var opening_panel_clearance_m: float = 0.028
@export var opening_frame_interior_offset_m: float = 0.120
@export var opening_frame_color: Color = Color(0.46, 0.34, 0.22, 1.0)
@export var window_glass_closed_color: Color = Color(0.52, 0.70, 0.88, 0.42)
@export var window_glass_open_color: Color = Color(0.62, 0.82, 1.0, 0.22)

@export_group("Exterior FP")
@export var exterior_context_enabled: bool = true
@export_enum("Dia", "Noche") var exterior_lighting_mode: String = "Dia"
@export var exterior_floor_drop_m: float = 5.8
@export var city_view_width_m: float = 22.0
@export var city_building_distance_m: float = 11.0
@export var city_backdrop_distance_m: float = 24.0
@export var city_building_count_per_window: int = 6
@export var exterior_day_window_light_energy: float = 1.05
@export var exterior_night_window_light_energy: float = 0.14
@export var exterior_day_window_light_color: Color = Color(0.86, 0.92, 1.0, 1.0)
@export var exterior_night_window_light_color: Color = Color(0.46, 0.58, 0.76, 1.0)
@export var exterior_day_landing_light_energy: float = 0.82
@export var exterior_night_landing_light_energy: float = 0.52
@export var exterior_day_landing_light_color: Color = Color(0.92, 0.88, 0.76, 1.0)
@export var exterior_night_landing_light_color: Color = Color(1.0, 0.70, 0.38, 1.0)
@export var exterior_facade_color: Color = Color(0.62, 0.61, 0.56, 1.0)
@export var city_sky_color: Color = Color(0.74, 0.84, 0.92, 1.0)
@export var city_street_color: Color = Color(0.34, 0.35, 0.34, 1.0)
@export var city_window_color: Color = Color(0.46, 0.58, 0.64, 1.0)
@export var city_window_lit_color: Color = Color(0.86, 0.92, 0.96, 1.0)
@export var city_night_sky_color: Color = Color(0.08, 0.11, 0.16, 1.0)
@export var city_night_street_color: Color = Color(0.08, 0.08, 0.09, 1.0)
@export var city_night_window_color: Color = Color(0.12, 0.16, 0.20, 1.0)
@export var city_night_window_lit_color: Color = Color(1.0, 0.76, 0.42, 1.0)
@export_range(0.0, 1.0, 0.01) var city_day_lit_window_ratio: float = 0.07
@export_range(0.0, 1.0, 0.01) var city_night_lit_window_ratio: float = 0.56

@export_group("Muebles FP")
@export var show_furniture: bool = true
@export var furniture_collision_enabled: bool = false
@export var furniture_wall_margin_m: float = 0.08
@export var furniture_state_tint_enabled: bool = false
@export var furniture_upholstery_color: Color = Color(0.43, 0.34, 0.29, 1.0)
@export var furniture_wood_color: Color = Color(0.46, 0.31, 0.19, 1.0)
@export var furniture_light_fabric_color: Color = Color(0.76, 0.71, 0.62, 1.0)
@export var furniture_rug_color: Color = Color(0.47, 0.28, 0.22, 1.0)
@export var furniture_counter_color: Color = Color(0.22, 0.22, 0.20, 1.0)

@export_group("Humo FP")
@export var smoke_overlay_visibility_reference_m: float = 14.0
@export var smoke_overlay_layer_clearance_m: float = 0.10
@export var smoke_overlay_layer_transition_m: float = 0.42
@export var smoke_overlay_max_alpha: float = 0.92

var building: BuildingModel = null

var _camera: Camera3D = null
var _collision_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _world_root: Node3D = null
var _prompt_layer: CanvasLayer = null
var _prompt_label: Label = null
var _origin_offset_m: Vector2 = Vector2.ZERO
var _bounds_m: Rect2 = Rect2()
var _active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _stance: int = STANCE_STAND
var _opening_nodes: Dictionary = {}
var _furniture_nodes: Dictionary = {}
var _nearest_opening_index: int = -1
var _state: Dictionary = {}
var _visibility_overlay: ColorRect = null
var _current_room_id: int = -1


func _ready() -> void:
	_create_player_nodes()
	set_active(false)


func setup(next_building: BuildingModel) -> void:
	building = next_building
	_apply_startup_lighting_options()
	_rebuild_world()
	_place_at_entry()


func set_active(enabled: bool) -> void:
	_active = enabled
	visible = enabled
	if _world_root != null:
		_world_root.visible = enabled
	set_physics_process(enabled)
	set_process(enabled)
	set_process_input(enabled)
	set_process_unhandled_input(false)
	if _camera != null:
		_camera.current = enabled
	if _prompt_layer != null:
		_prompt_layer.visible = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_update_prompt()
	else:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_nearest_opening_index = -1
		if _prompt_label != null:
			_prompt_label.visible = false
		if _visibility_overlay != null:
			_visibility_overlay.color = Color(0.08, 0.09, 0.09, 0.0)


func rebuild_from_building() -> void:
	_apply_startup_lighting_options()
	_rebuild_world()
	_place_at_entry()


func set_state(next_state: Dictionary) -> void:
	_state = next_state
	_sync_opening_panels()
	_update_furniture_state_visuals()
	_update_visibility_overlay()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_apply_movement(delta)
	_update_prompt()
	_update_visibility_overlay()


func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - motion.relative.y * mouse_sensitivity,
			deg_to_rad(-82.0),
			deg_to_rad(82.0)
		)
		rotation.y = _yaw
		if _camera != null:
			_camera.rotation.x = _pitch
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			exit_requested.emit()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_F:
			_interact_with_nearest_opening()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_CTRL:
			_cycle_stance()
			get_viewport().set_input_as_handled()


func _create_player_nodes() -> void:
	_ensure_world_root()

	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.24
	_capsule.height = person_height_m

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "PlayerCollision"
	_collision_shape.shape = _capsule
	add_child(_collision_shape)

	_camera = Camera3D.new()
	_camera.name = "FirstPersonCamera"
	_camera.fov = 75.0
	_camera.near = 0.03
	add_child(_camera)
	_apply_stance(true)

	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "FirstPersonPromptLayer"
	add_child(_prompt_layer)
	_visibility_overlay = ColorRect.new()
	_visibility_overlay.name = "SmokeVisibilityOverlay"
	_visibility_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_visibility_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visibility_overlay.color = Color(0.08, 0.09, 0.09, 0.0)
	_prompt_layer.add_child(_visibility_overlay)
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -260.0
	_prompt_label.offset_right = 260.0
	_prompt_label.offset_top = -92.0
	_prompt_label.offset_bottom = -44.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.visible = false
	_prompt_layer.add_child(_prompt_label)


func _ensure_world_root() -> void:
	if _world_root != null and is_instance_valid(_world_root):
		return
	var parent_host := get_parent() as Node3D
	if parent_host != null:
		_world_root = parent_host.get_node_or_null("FirstPersonWorld") as Node3D
	if _world_root == null:
		_world_root = get_node_or_null("FirstPersonWorld") as Node3D
	if _world_root == null:
		_world_root = Node3D.new()
		_world_root.name = "FirstPersonWorld"
		add_child(_world_root)
	_world_root.set_as_top_level(true)
	_world_root.global_transform = Transform3D.IDENTITY
	_world_root.visible = _active


func _apply_startup_lighting_options() -> void:
	if not FileAccess.file_exists(STARTUP_OPTIONS_PATH):
		return
	var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var mode: String = String(Dictionary(parsed).get("exterior_lighting_mode", exterior_lighting_mode))
	match mode.strip_edges().to_lower():
		"noche":
			exterior_lighting_mode = "Noche"
		_:
			exterior_lighting_mode = "Dia"


func _rebuild_world() -> void:
	_ensure_world_root()
	if _world_root == null:
		return
	for child in _world_root.get_children():
		child.free()
	_world_root.global_transform = Transform3D.IDENTITY
	_world_root.visible = _active
	_opening_nodes.clear()
	_furniture_nodes.clear()

	if building == null:
		return

	var rects: Dictionary = building.get_room_rects_m()
	if rects.is_empty():
		return

	_bounds_m = _compute_bounds(rects)
	_origin_offset_m = -(_bounds_m.position + _bounds_m.size * 0.5)

	_create_floors(rects)
	_create_ceilings(rects)
	_create_walls(rects)
	_create_world_lighting(rects)
	_create_opening_panels()
	_create_exterior_context()
	_create_furniture(rects)
	_create_outer_boundary()


func _create_floors(rects: Dictionary) -> void:
	for room_id in rects.keys():
		var rect: Rect2 = Rect2(rects[room_id])
		var body := StaticBody3D.new()
		body.name = "Floor_%s" % str(room_id)
		_world_root.add_child(body)
		var center: Vector3 = _to_world(Vector3(
			rect.position.x + rect.size.x * 0.5,
			-floor_thickness_m * 0.5,
			rect.position.y + rect.size.y * 0.5
		))
		_add_box(body, "FloorMesh", Vector3(rect.size.x, floor_thickness_m, rect.size.y), center, _floor_material_for_room(int(room_id)), true)


func _create_ceilings(rects: Dictionary) -> void:
	for room_id in rects.keys():
		var rect: Rect2 = Rect2(rects[room_id])
		var room: RoomModel = building.get_room(int(room_id))
		var height_m: float = room.height_m if room != null else 2.4
		var body := StaticBody3D.new()
		body.name = "Ceiling_%s" % str(room_id)
		_world_root.add_child(body)
		var center: Vector3 = _to_world(Vector3(
			rect.position.x + rect.size.x * 0.5,
			height_m + ceiling_thickness_m * 0.5,
			rect.position.y + rect.size.y * 0.5
		))
		_add_box(body, "CeilingMesh", Vector3(rect.size.x, ceiling_thickness_m, rect.size.y), center, _ceiling_material_for_room(int(room_id)), true)


func _create_walls(rects: Dictionary) -> void:
	for room_id in rects.keys():
		var rect: Rect2 = Rect2(rects[room_id])
		var room: RoomModel = building.get_room(int(room_id))
		var height_m: float = room.height_m if room != null else 2.4
		_add_wall_side(rect, int(room_id), "top", height_m)
		_add_wall_side(rect, int(room_id), "bottom", height_m)
		_add_wall_side(rect, int(room_id), "left", height_m)
		_add_wall_side(rect, int(room_id), "right", height_m)


func _add_wall_side(rect: Rect2, room_id: int, side: String, height_m: float) -> void:
	var length: float = rect.size.x if side == "top" or side == "bottom" else rect.size.y
	var openings: Array = _opening_specs_for_side(rect, room_id, side, height_m)
	openings.sort_custom(func(a, b): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))

	var cursor: float = 0.0
	for opening in openings:
		var start: float = clampf(float(opening.get("start", 0.0)), 0.0, length)
		var end: float = clampf(float(opening.get("end", 0.0)), 0.0, length)
		if start > cursor + 0.03:
			_create_wall_segment(rect, room_id, side, cursor, start, height_m)
		if end > start + 0.03:
			var bottom_m: float = clampf(float(opening.get("bottom_m", 0.0)), 0.0, height_m)
			var top_m: float = clampf(float(opening.get("top_m", height_m)), 0.0, height_m)
			if bottom_m > 0.03:
				_create_wall_segment_height(rect, room_id, side, start, end, 0.0, bottom_m)
			if top_m < height_m - 0.03:
				_create_wall_segment_height(rect, room_id, side, start, end, top_m, height_m)
		cursor = maxf(cursor, end)
	if cursor < length - 0.03:
		_create_wall_segment(rect, room_id, side, cursor, length, height_m)


func _create_wall_segment(rect: Rect2, room_id: int, side: String, start: float, end: float, height_m: float) -> void:
	_create_wall_segment_height(rect, room_id, side, start, end, 0.0, height_m)


func _create_wall_segment_height(rect: Rect2, room_id: int, side: String, start: float, end: float, y_min_m: float, y_max_m: float) -> void:
	var span: float = maxf(0.0, end - start)
	var height_m: float = maxf(0.0, y_max_m - y_min_m)
	if span <= 0.03 or height_m <= 0.03:
		return
	var body := StaticBody3D.new()
	body.name = "Wall_%s" % side
	_world_root.add_child(body)

	var size: Vector3
	var center: Vector3
	var center_y: float = y_min_m + height_m * 0.5
	if side == "top" or side == "bottom":
		size = Vector3(span, height_m, wall_thickness_m)
		var z: float = rect.position.y if side == "top" else rect.position.y + rect.size.y
		center = _to_world(Vector3(rect.position.x + start + span * 0.5, center_y, z))
	else:
		size = Vector3(wall_thickness_m, height_m, span)
		var x: float = rect.position.x if side == "left" else rect.position.x + rect.size.x
		center = _to_world(Vector3(x, center_y, rect.position.y + start + span * 0.5))
	_add_box(body, "WallMesh", size, center, _wall_material_for_room(room_id), true)
	_create_skirting_segment(rect, side, start, end)


func _create_skirting_segment(rect: Rect2, side: String, start: float, end: float) -> void:
	var span: float = maxf(0.0, end - start)
	if span <= 0.05 or wall_skirting_height_m <= 0.0:
		return
	var center: Vector3
	var size: Vector3
	var normal: Vector3 = _inside_normal_for_side(side)
	if side == "top" or side == "bottom":
		var z: float = rect.position.y if side == "top" else rect.position.y + rect.size.y
		center = _to_world(Vector3(rect.position.x + start + span * 0.5, wall_skirting_height_m * 0.5, z)) + normal * (wall_thickness_m * 0.5 + 0.012)
		size = Vector3(span, wall_skirting_height_m, 0.028)
	else:
		var x: float = rect.position.x if side == "left" else rect.position.x + rect.size.x
		center = _to_world(Vector3(x, wall_skirting_height_m * 0.5, rect.position.y + start + span * 0.5)) + normal * (wall_thickness_m * 0.5 + 0.012)
		size = Vector3(0.028, wall_skirting_height_m, span)
	_add_box(_world_root, "Skirting_%s" % side, size, center, _mat(Color(0.34, 0.27, 0.20, 1.0), false), false)


func _create_world_lighting(rects: Dictionary) -> void:
	if ambient_fill_enabled:
		var fill := OmniLight3D.new()
		fill.name = "FP_AmbientFill"
		fill.light_color = ambient_fill_color
		fill.light_energy = ambient_fill_energy
		fill.omni_range = maxf(8.0, maxf(_bounds_m.size.x, _bounds_m.size.y) * 1.35)
		fill.shadow_enabled = false
		fill.position = _to_world(Vector3(
			_bounds_m.position.x + _bounds_m.size.x * 0.5,
			1.6,
			_bounds_m.position.y + _bounds_m.size.y * 0.5
		))
		_world_root.add_child(fill)

	if not room_ceiling_lights_enabled:
		return
	for room_id in rects.keys():
		var rect := Rect2(rects[room_id])
		var room: RoomModel = building.get_room(int(room_id))
		var height_m: float = room.height_m if room != null else 2.4
		var area_m2: float = maxf(1.0, rect.size.x * rect.size.y)
		var light := OmniLight3D.new()
		light.name = "CeilingLight_%s" % str(room_id)
		light.light_color = room_ceiling_light_color
		light.light_energy = room_ceiling_light_energy * clampf(sqrt(area_m2 / 14.0), 0.72, 1.35)
		light.omni_range = maxf(rect.size.x, rect.size.y) * 0.68 + room_ceiling_light_range_extra_m
		light.shadow_enabled = false
		light.position = _to_world(Vector3(
			rect.position.x + rect.size.x * 0.5,
			maxf(1.8, height_m - 0.22),
			rect.position.y + rect.size.y * 0.5
		))
		_world_root.add_child(light)
		_add_box(
			_world_root,
			"CeilingFixture_%s" % str(room_id),
			Vector3(0.34, 0.035, 0.34),
			light.position + Vector3(0.0, 0.035, 0.0),
			_mat(Color(1.0, 0.86, 0.58, 1.0), false, Color(1.0, 0.72, 0.36, 1.0), 0.55),
			false
		)


func _create_opening_panels() -> void:
	if building == null:
		return
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null:
			continue
		var info: Dictionary = _opening_info(index)
		if info.is_empty():
			continue

		var body := StaticBody3D.new()
		body.name = "Opening_%02d" % index
		_world_root.add_child(body)
		var mesh := MeshInstance3D.new()
		mesh.name = "Panel"
		mesh.mesh = BoxMesh.new()
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		var asset: Node3D = null
		var window_leaf_left: Node3D = null
		var window_leaf_right: Node3D = null
		if op.type == OpeningModel.Type.WINDOW:
			mesh.visible = false
			var leaf_width_m: float = float(info.get("width_m", op.width_m)) * 0.5
			var leaf_height_m: float = float(info.get("height_m", op.height_m))
			window_leaf_left = _create_window_leaf_visual(
				_world_root,
				"WindowLeafLeft_%02d" % index,
				leaf_width_m,
				leaf_height_m,
				0.045,
				1.0
			)
			window_leaf_right = _create_window_leaf_visual(
				_world_root,
				"WindowLeafRight_%02d" % index,
				leaf_width_m,
				leaf_height_m,
				0.045,
				-1.0
			)
		else:
			asset = _try_build_opening_asset(body, op)
			if asset != null:
				mesh.visible = false
		_opening_nodes[index] = {
			"body": body,
			"mesh": mesh,
			"shape": shape,
			"asset": asset,
			"window_leaf_left": window_leaf_left,
			"window_leaf_right": window_leaf_right,
			"info": info,
			"frame": _create_opening_frame(index, op, info),
			"light": _create_opening_light(op, info)
		}
		_create_landing_recess(index, op, info)
		_update_opening_panel(index)


func _create_opening_light(op: OpeningModel, info: Dictionary) -> OmniLight3D:
	if op == null or not op.is_exterior_opening():
		return null
	if op.type != OpeningModel.Type.WINDOW and op.type != OpeningModel.Type.DOOR:
		return null
	var light := OmniLight3D.new()
	light.name = "LandingLight" if op.type == OpeningModel.Type.DOOR else "WindowDaylight"
	light.light_color = _effective_landing_light_color() if op.type == OpeningModel.Type.DOOR else _effective_window_light_color()
	light.light_energy = 0.0
	light.omni_range = landing_light_range_m if op.type == OpeningModel.Type.DOOR else window_light_range_m
	light.shadow_enabled = opening_lights_cast_shadows
	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var inward: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var outside_offset: float = landing_recess_depth_m * 0.58 if op.type == OpeningModel.Type.DOOR else 0.55
	light.position = center - inward * outside_offset
	light.position.y = 2.05 if op.type == OpeningModel.Type.DOOR else maxf(1.35, center.y)
	_world_root.add_child(light)
	return light


func _exterior_is_night() -> bool:
	return exterior_lighting_mode.strip_edges().to_lower() == "noche"


func _effective_window_light_energy() -> float:
	return exterior_night_window_light_energy if _exterior_is_night() else exterior_day_window_light_energy


func _effective_window_light_color() -> Color:
	return exterior_night_window_light_color if _exterior_is_night() else exterior_day_window_light_color


func _effective_landing_light_energy() -> float:
	return exterior_night_landing_light_energy if _exterior_is_night() else exterior_day_landing_light_energy


func _effective_landing_light_color() -> Color:
	return exterior_night_landing_light_color if _exterior_is_night() else exterior_day_landing_light_color


func _effective_city_sky_color() -> Color:
	return city_night_sky_color if _exterior_is_night() else city_sky_color


func _effective_city_street_color() -> Color:
	return city_night_street_color if _exterior_is_night() else city_street_color


func _effective_city_window_color() -> Color:
	return city_night_window_color if _exterior_is_night() else city_window_color


func _effective_city_window_lit_color() -> Color:
	return city_night_window_lit_color if _exterior_is_night() else city_window_lit_color


func _effective_city_lit_window_ratio() -> float:
	return city_night_lit_window_ratio if _exterior_is_night() else city_day_lit_window_ratio


func _create_opening_frame(index: int, op: OpeningModel, info: Dictionary) -> Node3D:
	var frame_root := Node3D.new()
	frame_root.name = "OpeningFrame_%02d" % index
	_world_root.add_child(frame_root)

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	center += normal * opening_frame_interior_offset_m
	var width_m: float = float(info.get("width_m", 0.8))
	var height_m: float = float(info.get("height_m", 2.0))
	var sill_m: float = float(info.get("sill_m", 0.0))
	var horizontal: bool = String(info.get("orientation", "horizontal")) == "horizontal"
	var depth_m: float = 0.075
	var bar_m: float = 0.075
	var mat := _mat(opening_frame_color, false)
	var frame_width: float = width_m + bar_m * 2.0
	var frame_height: float = height_m + bar_m * 2.0
	var mid_y: float = sill_m + height_m * 0.5
	var top_y: float = sill_m + height_m + bar_m * 0.5
	var bottom_y: float = maxf(bar_m * 0.5, sill_m - bar_m * 0.5)

	if horizontal:
		_add_box(frame_root, "FrameTop", Vector3(frame_width, bar_m, depth_m), Vector3(center.x, top_y, center.z), mat, false)
		_add_box(frame_root, "FrameBottom", Vector3(frame_width, bar_m, depth_m), Vector3(center.x, bottom_y, center.z), mat, false)
		_add_box(frame_root, "FrameLeft", Vector3(bar_m, frame_height, depth_m), Vector3(center.x - width_m * 0.5 - bar_m * 0.5, mid_y, center.z), mat, false)
		_add_box(frame_root, "FrameRight", Vector3(bar_m, frame_height, depth_m), Vector3(center.x + width_m * 0.5 + bar_m * 0.5, mid_y, center.z), mat, false)
	else:
		_add_box(frame_root, "FrameTop", Vector3(depth_m, bar_m, frame_width), Vector3(center.x, top_y, center.z), mat, false)
		_add_box(frame_root, "FrameBottom", Vector3(depth_m, bar_m, frame_width), Vector3(center.x, bottom_y, center.z), mat, false)
		_add_box(frame_root, "FrameLeft", Vector3(depth_m, frame_height, bar_m), Vector3(center.x, mid_y, center.z - width_m * 0.5 - bar_m * 0.5), mat, false)
		_add_box(frame_root, "FrameRight", Vector3(depth_m, frame_height, bar_m), Vector3(center.x, mid_y, center.z + width_m * 0.5 + bar_m * 0.5), mat, false)

	return frame_root


func _create_landing_recess(index: int, op: OpeningModel, info: Dictionary) -> void:
	if not show_landing_recess or op == null:
		return
	if not op.is_exterior_opening() or op.type != OpeningModel.Type.DOOR:
		return

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var horizontal: bool = String(info.get("orientation", "horizontal")) == "horizontal"
	var width_m: float = maxf(1.45, float(info.get("width_m", 0.85)) + 0.95)
	var depth_m: float = maxf(1.85, landing_recess_depth_m)
	var corridor_height_m: float = 2.45

	var floor_center: Vector3 = center - normal * (depth_m * 0.5 + 0.08)
	floor_center.y = -floor_thickness_m * 0.5
	var floor_size := Vector3(width_m, floor_thickness_m, depth_m) if horizontal else Vector3(depth_m, floor_thickness_m, width_m)
	_add_box(
		_world_root,
		"LandingFloor_%02d" % index,
		floor_size,
		floor_center,
		_mat(Color(0.32, 0.31, 0.28, 1.0), false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 4100 + index),
		false
	)

	var wall_center: Vector3 = center - normal * (depth_m + 0.11)
	wall_center.y = corridor_height_m * 0.5
	var wall_size := Vector3(width_m, corridor_height_m, wall_thickness_m) if horizontal else Vector3(wall_thickness_m, corridor_height_m, width_m)
	_add_box(
		_world_root,
		"LandingBackWall_%02d" % index,
		wall_size,
		wall_center,
		_mat(Color(0.70, 0.70, 0.66, 1.0), false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 4200 + index),
		false
	)

	var side_wall_size := Vector3(wall_thickness_m, corridor_height_m, depth_m) if horizontal else Vector3(depth_m, corridor_height_m, wall_thickness_m)
	for side_sign in [-1.0, 1.0]:
		var side_center: Vector3 = floor_center + tangent * side_sign * (width_m * 0.5 + wall_thickness_m * 0.5)
		side_center.y = corridor_height_m * 0.5
		_add_box(
			_world_root,
			"LandingSideWall_%02d" % index,
			side_wall_size,
			side_center,
			_mat(Color(0.66, 0.66, 0.61, 1.0), false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 4250 + index),
			false
		)

	var ceiling_center: Vector3 = floor_center
	ceiling_center.y = corridor_height_m + ceiling_thickness_m * 0.5
	_add_box(
		_world_root,
		"LandingCeiling_%02d" % index,
		Vector3(width_m, ceiling_thickness_m, depth_m) if horizontal else Vector3(depth_m, ceiling_thickness_m, width_m),
		ceiling_center,
		_mat(Color(0.78, 0.77, 0.71, 1.0), false),
		false
	)

	var fixture_center: Vector3 = center - normal * (depth_m * 0.62)
	fixture_center.y = 2.18
	_add_box(
		_world_root,
		"LandingFixture_%02d" % index,
		Vector3(0.42, 0.035, 0.42),
		fixture_center,
		_mat(_effective_landing_light_color(), false, _effective_landing_light_color(), 0.85),
		false
	)

	var surface_center: Vector3 = wall_center + normal * (wall_thickness_m * 0.5 + 0.026)
	var neighbor_center: Vector3 = surface_center - tangent * (width_m * 0.22)
	neighbor_center.y = 0.98
	_add_oriented_box(
		_world_root,
		"LandingNeighborDoor_%02d" % index,
		neighbor_center,
		tangent,
		0.72,
		1.86,
		0.045,
		_mat(Color(0.38, 0.25, 0.15, 1.0), false),
		false
	)
	var handle_center: Vector3 = neighbor_center + tangent * 0.24 + normal * 0.035
	handle_center.y = 0.98
	_add_oriented_box(
		_world_root,
		"LandingNeighborHandle_%02d" % index,
		handle_center,
		tangent,
		0.055,
		0.055,
		0.055,
		_mat(Color(0.72, 0.58, 0.30, 1.0), false),
		false
	)

	var lift_center: Vector3 = surface_center + tangent * (width_m * 0.27)
	lift_center.y = 1.02
	_add_oriented_box(
		_world_root,
		"LandingLiftDoors_%02d" % index,
		lift_center,
		tangent,
		0.72,
		1.90,
		0.036,
		_mat(Color(0.46, 0.48, 0.47, 1.0), false),
		false
	)
	var lift_split: Vector3 = lift_center + normal * 0.028
	_add_oriented_box(
		_world_root,
		"LandingLiftSplit_%02d" % index,
		lift_split,
		tangent,
		0.025,
		1.86,
		0.018,
		_mat(Color(0.20, 0.20, 0.19, 1.0), false),
		false
	)
	var panel_center: Vector3 = surface_center + tangent * (width_m * 0.47)
	panel_center.y = 1.18
	_add_oriented_box(
		_world_root,
		"LandingLiftPanel_%02d" % index,
		panel_center,
		tangent,
		0.14,
		0.32,
		0.035,
		_mat(Color(0.11, 0.12, 0.12, 1.0), false, Color(0.8, 0.62, 0.28, 1.0), 0.18),
		false
	)


func _create_exterior_context() -> void:
	if not exterior_context_enabled or building == null:
		return
	var root := Node3D.new()
	root.name = "ExteriorContext"
	_world_root.add_child(root)
	_create_exterior_lighting(root)

	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or not op.is_exterior_opening() or op.type != OpeningModel.Type.WINDOW:
			continue
		var info: Dictionary = _opening_info(index)
		if info.is_empty():
			continue
		_create_window_city_view(root, index, info)


func _create_window_city_view(parent: Node3D, index: int, info: Dictionary) -> void:
	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var width_m: float = float(info.get("width_m", 1.0))
	var height_m: float = float(info.get("height_m", 1.0))
	var sill_m: float = float(info.get("sill_m", 0.9))

	_create_exterior_window_reveal(parent, index, center, normal, tangent, width_m, height_m, sill_m)
	_create_exterior_window_sill(parent, index, center, normal, tangent, width_m, sill_m)

	var sky_center: Vector3 = center - normal * city_backdrop_distance_m
	sky_center.y = 4.0
	var sky_color: Color = _effective_city_sky_color()
	_add_oriented_box(
		parent,
		"CitySky_%02d" % index,
		sky_center,
		tangent,
		city_view_width_m * 1.75,
		14.0,
		0.08,
		_mat(sky_color, false, sky_color, 0.48 if not _exterior_is_night() else 0.22),
		false
	)

	var street_center: Vector3 = center - normal * (city_building_distance_m * 0.78)
	street_center.y = -exterior_floor_drop_m - 0.03
	_add_oriented_box(
		parent,
		"CityStreet_%02d" % index,
		street_center,
		tangent,
		city_view_width_m * 1.55,
		0.055,
		city_building_distance_m * 1.35,
		_mat(_effective_city_street_color(), false, _effective_city_street_color(), 0.045 if not _exterior_is_night() else 0.0),
		false
	)

	var count: int = maxi(1, city_building_count_per_window)
	var span_step: float = city_view_width_m / float(count)
	for slot in range(count):
		var slot_t: float = (float(slot) + 0.5) / float(count) - 0.5
		var seed: float = float(index * 31 + slot * 17)
		var building_width: float = clampf(span_step * (0.72 + fposmod(seed * 0.37, 0.32)), 1.6, 4.6)
		var building_depth: float = 0.72 + fposmod(seed * 0.19, 0.34)
		var building_height: float = 7.5 + fposmod(seed * 1.13, 7.2)
		var distance: float = city_building_distance_m + fposmod(seed * 0.23, 2.4)
		var building_center: Vector3 = center - normal * distance + tangent * (slot_t * city_view_width_m)
		building_center.y = -exterior_floor_drop_m + building_height * 0.5
		var tone: float = fposmod(seed * 0.11, 0.24)
		var building_color := Color(0.34 + tone, 0.36 + tone * 0.72, 0.37 + tone * 0.55, 1.0)
		_add_oriented_box(
			parent,
			"CityBuilding_%02d_%02d" % [index, slot],
			building_center,
			tangent,
			building_width,
			building_height,
			building_depth,
			_mat(building_color, false, building_color, 0.035 if not _exterior_is_night() else 0.0),
			false
		)
		_create_city_windows(parent, index, slot, building_center, normal, tangent, building_width, building_height, building_depth, seed)


func _create_exterior_window_reveal(
	parent: Node3D,
	index: int,
	center: Vector3,
	normal: Vector3,
	tangent: Vector3,
	width_m: float,
	height_m: float,
	sill_m: float
) -> void:
	var reveal_center: Vector3 = center - normal * 0.105
	var band_depth: float = 0.055
	var band_m: float = 0.16
	var facade_mat := _mat(exterior_facade_color, false)
	var top_center: Vector3 = reveal_center
	top_center.y = sill_m + height_m + band_m * 0.5
	_add_oriented_box(parent, "ExteriorWindowTop_%02d" % index, top_center, tangent, width_m + band_m * 2.0, band_m, band_depth, facade_mat, false)
	var bottom_center: Vector3 = reveal_center
	bottom_center.y = maxf(0.05, sill_m - band_m * 0.5)
	_add_oriented_box(parent, "ExteriorWindowBottom_%02d" % index, bottom_center, tangent, width_m + band_m * 2.0, band_m, band_depth, facade_mat, false)
	for side_sign in [-1.0, 1.0]:
		var side_center: Vector3 = reveal_center + tangent * side_sign * (width_m * 0.5 + band_m * 0.5)
		side_center.y = sill_m + height_m * 0.5
		_add_oriented_box(parent, "ExteriorWindowSide_%02d" % index, side_center, tangent, band_m, height_m + band_m * 2.0, band_depth, facade_mat, false)


func _create_exterior_lighting(parent: Node3D) -> void:
	var sky_light := DirectionalLight3D.new()
	sky_light.name = "ExteriorSkyLight"
	sky_light.light_color = Color(0.88, 0.92, 1.0, 1.0) if not _exterior_is_night() else Color(0.34, 0.44, 0.62, 1.0)
	sky_light.light_energy = 0.58 if not _exterior_is_night() else 0.16
	sky_light.shadow_enabled = false
	sky_light.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(28.0), 0.0)
	parent.add_child(sky_light)

	var exterior_fill := OmniLight3D.new()
	exterior_fill.name = "ExteriorSoftFill"
	exterior_fill.light_color = Color(0.78, 0.86, 0.94, 1.0) if not _exterior_is_night() else Color(0.25, 0.33, 0.46, 1.0)
	exterior_fill.light_energy = 0.18 if not _exterior_is_night() else 0.06
	exterior_fill.omni_range = maxf(14.0, city_view_width_m * 0.9)
	exterior_fill.shadow_enabled = false
	exterior_fill.position = _to_world(Vector3(
		_bounds_m.position.x + _bounds_m.size.x * 0.5,
		3.2,
		_bounds_m.position.y + _bounds_m.size.y * 0.5
	))
	parent.add_child(exterior_fill)


func _create_exterior_window_sill(parent: Node3D, index: int, center: Vector3, normal: Vector3, tangent: Vector3, width_m: float, sill_m: float) -> void:
	var slab_center: Vector3 = center - normal * 0.40
	slab_center.y = maxf(0.22, sill_m - 0.10)
	_add_oriented_box(parent, "ExteriorSill_%02d" % index, slab_center, tangent, width_m + 0.52, 0.08, 0.42, _mat(Color(0.55, 0.54, 0.49, 1.0), false), false)


func _create_city_windows(
	parent: Node3D,
	opening_index: int,
	building_slot: int,
	building_center: Vector3,
	normal: Vector3,
	tangent: Vector3,
	building_width: float,
	building_height: float,
	building_depth: float,
	seed: float
) -> void:
	var columns: int = maxi(1, int(floor(building_width / 0.78)))
	var rows: int = maxi(2, int(floor((building_height - 1.0) / 1.18)))
	var face_center: Vector3 = building_center + normal * (building_depth * 0.5 + 0.014)
	for row in range(rows):
		var y: float = -exterior_floor_drop_m + 0.85 + float(row) * 1.18
		if y > building_center.y + building_height * 0.5 - 0.45:
			continue
		for column in range(columns):
			var col_t: float = (float(column) + 0.5) / float(columns) - 0.5
			var lit_roll: float = fposmod(seed * 0.173 + float(row) * 0.277 + float(column) * 0.619, 1.0)
			var lit: bool = lit_roll < _effective_city_lit_window_ratio()
			var win_center: Vector3 = face_center + tangent * (col_t * building_width * 0.72)
			win_center.y = y
			var win_color: Color = _effective_city_window_lit_color() if lit else _effective_city_window_color()
			var emission_energy: float = 0.30 if lit and _exterior_is_night() else 0.08 if lit else 0.018 if not _exterior_is_night() else 0.0
			_add_oriented_box(
				parent,
				"CityWindow_%02d_%02d_%02d_%02d" % [opening_index, building_slot, row, column],
				win_center,
				tangent,
				0.34,
				0.42,
				0.018,
				_mat(win_color, false, win_color if lit else Color(0.0, 0.0, 0.0, 0.0), emission_energy),
				false
			)


func _create_furniture(rects: Dictionary) -> void:
	if not show_furniture or building == null:
		return
	var furniture_root := Node3D.new()
	furniture_root.name = "Furniture"
	_world_root.add_child(furniture_root)

	for room_key in rects.keys():
		var room_id: int = int(room_key)
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var rect := Rect2(rects[room_key])
		var room_root := Node3D.new()
		room_root.name = "Furniture_Room_%s" % str(room_id)
		furniture_root.add_child(room_root)

		var specs: Array = _fuel_object_furniture_specs(room, rect)
		if specs.is_empty():
			specs = _fallback_furniture_specs(room, rect)
		for raw_spec in specs:
			if typeof(raw_spec) != TYPE_DICTIONARY:
				continue
			_create_furniture_piece(room_root, room, rect, Dictionary(raw_spec))

	_update_furniture_state_visuals()


func _fuel_object_furniture_specs(room: RoomModel, rect: Rect2) -> Array:
	var specs: Array = []
	if room == null:
		return specs
	var auto_layout: bool = _fuel_objects_need_auto_layout(room)
	var index: int = 0
	for raw_obj in room.fuel_objects:
		var obj := raw_obj as FuelObjectModel
		if obj == null:
			continue
		if String(obj.id).begins_with("room_proxy_"):
			continue
		var room_kind: String = room.kind.to_lower()
		var visual_kind: String = _classify_furniture_kind(obj.kind, obj.name, obj.id)
		if (room_kind.contains("pasillo") or room_kind.contains("hall") or room_kind.contains("corridor")) and visual_kind != "rug":
			continue
		var spec: Dictionary
		if auto_layout:
			spec = _auto_furniture_spec_for_object(room, rect, obj, index)
		else:
			spec = _spec_from_fuel_object(obj)
		if not spec.is_empty():
			specs.append(spec)
			index += 1
	return specs


func _fuel_objects_need_auto_layout(room: RoomModel) -> bool:
	if room == null:
		return false
	var explicit_count: int = 0
	var default_count: int = 0
	for raw_obj in room.fuel_objects:
		var obj := raw_obj as FuelObjectModel
		if obj == null or String(obj.id).begins_with("room_proxy_"):
			continue
		explicit_count += 1
		if obj.position_m.length_squared() < 0.0001 and obj.size_m.distance_to(Vector2.ONE) < 0.001:
			default_count += 1
	return explicit_count > 0 and default_count == explicit_count


func _spec_from_fuel_object(obj: FuelObjectModel) -> Dictionary:
	if obj == null:
		return {}
	var kind: String = _classify_furniture_kind(obj.kind, obj.name, obj.id)
	var size_m := _sane_furniture_size(kind, obj.size_m)
	return _make_furniture_spec(
		obj.id,
		obj.name,
		kind,
		obj.position_m,
		size_m,
		obj.rotation_deg,
		obj.elevation_m,
		true
	)


func _auto_furniture_spec_for_object(room: RoomModel, rect: Rect2, obj: FuelObjectModel, index: int) -> Dictionary:
	var kind: String = _classify_furniture_kind(obj.kind, obj.name, obj.id)
	var room_kind: String = room.kind.to_lower()
	var w: float = maxf(0.8, rect.size.x)
	var d: float = maxf(0.8, rect.size.y)
	var pos := Vector2(0.25 + float(index % 3) * 0.55, 0.25 + float(index / 3) * 0.55)
	var size := _sane_furniture_size(kind, obj.size_m)
	var tokens: String = _furniture_tokens(obj.kind, obj.name, obj.id)

	if room_kind.contains("dorm") or room_kind.contains("bed"):
		match kind:
			"bed":
				size = Vector2(minf(2.00, maxf(1.35, w - 1.15)), minf(1.35, maxf(0.90, d - 1.10)))
				pos = Vector2(0.25, 0.35)
			"wardrobe", "bookcase", "storage", "dresser":
				size = Vector2(0.42, minf(1.80, maxf(0.85, d - 0.65)))
				pos = Vector2(w - size.x - 0.22, 0.30)
			"textile_pile":
				size = Vector2(minf(1.50, maxf(0.70, w - 1.50)), 0.58 if tokens.contains("bedding") else 0.45)
				pos = Vector2(0.48, 0.66 if tokens.contains("bedding") else maxf(0.35, d - 0.70))
			_:
				size = Vector2(minf(0.95, maxf(0.45, w - 1.20)), minf(0.62, maxf(0.40, d - 1.20)))
				pos = Vector2(maxf(0.25, w - size.x - 0.42), maxf(0.30, d - size.y - 0.42))
	elif room_kind.contains("salon") or room_kind.contains("living"):
		match kind:
			"sofa", "armchair":
				size = Vector2(minf(2.25, maxf(0.85, w - 0.70)), 0.82)
				pos = Vector2(0.35, 0.32)
			"table", "coffee_table":
				size = Vector2(minf(1.20, maxf(0.65, w * 0.28)), 0.62)
				pos = Vector2(w * 0.40, d * 0.45)
			"bookcase", "wardrobe", "storage", "dresser", "tv_stand":
				size = Vector2(minf(1.65, maxf(0.70, w - 0.80)), 0.36)
				pos = Vector2(0.55, maxf(0.28, d - 0.58))
			"rug", "textile_pile":
				kind = "rug" if not tokens.contains("cortina") and not tokens.contains("curtain") else kind
				size = Vector2(minf(2.30, maxf(1.05, w - 1.20)), minf(1.35, maxf(0.70, d - 1.40)))
				pos = Vector2((w - size.x) * 0.45, (d - size.y) * 0.55)
			_:
				size = Vector2(0.70, 0.50)
				pos = Vector2(maxf(0.35, w - 1.05), maxf(0.35, d - 1.05))
	elif room_kind.contains("cocina") or room_kind.contains("kitchen"):
		match kind:
			"kitchen_unit", "storage", "dresser":
				kind = "kitchen_unit"
				size = Vector2(minf(maxf(1.25, w - 1.10), 3.20), 0.62)
				pos = Vector2(0.30, 0.22)
			"pool":
				size = Vector2(0.42, 0.42)
				pos = Vector2(minf(w - 0.75, 1.75), 0.34)
			"table", "coffee_table":
				size = Vector2(minf(1.10, maxf(0.70, w - 1.30)), 0.70)
				pos = Vector2(maxf(0.40, w - size.x - 0.55), maxf(0.55, d - size.y - 0.50))
			_:
				size = Vector2(0.58, 0.46)
				pos = Vector2(maxf(0.40, w - 1.05), maxf(0.55, d - 0.85))
	elif room_kind.contains("pasillo") or room_kind.contains("hall") or room_kind.contains("corridor"):
		match kind:
			"rug", "textile_pile":
				kind = "rug"
				size = Vector2(minf(0.82, maxf(0.36, w - 0.45)), minf(maxf(0.75, d - 0.75), 4.80))
				pos = Vector2((w - size.x) * 0.50, 0.42)
			_:
				size = Vector2(minf(0.42, maxf(0.28, w - 0.55)), minf(0.95, maxf(0.45, d - 0.75)))
				pos = Vector2(0.16, 0.35 + float(index) * 0.70)
	elif room_kind.contains("bano") or room_kind.contains("baño") or room_kind.contains("bath"):
		match kind:
			"plastic_bin":
				size = Vector2(0.40, 0.40)
				pos = Vector2(0.28, 0.35)
			"textile_pile":
				size = Vector2(0.50, 0.72)
				pos = Vector2(maxf(0.40, w - 0.82), 0.28)
			_:
				kind = "bath_vanity"
				size = Vector2(minf(0.85, maxf(0.55, w - 1.10)), 0.42)
				pos = Vector2((w - size.x) * 0.50, maxf(0.30, d - 0.72))
	else:
		size = Vector2(0.70, 0.55)
		pos = Vector2(0.25 + float(index % 3) * 0.78, 0.28 + float(index / 3) * 0.72)

	return _make_furniture_spec(obj.id, obj.name, kind, pos, size, 0.0, obj.elevation_m, true)


func _fallback_furniture_specs(room: RoomModel, rect: Rect2) -> Array:
	var specs: Array = []
	if room == null:
		return specs
	var room_id: int = room.id
	var kind: String = room.kind.to_lower()
	var w: float = maxf(0.8, rect.size.x)
	var d: float = maxf(0.8, rect.size.y)

	if kind.contains("salon") or kind.contains("living"):
		var sofa_w: float = minf(2.35, maxf(1.25, w - 0.85))
		specs.append(_make_furniture_spec("visual_%d_sofa" % room_id, "Sofa", "sofa", Vector2(0.35, 0.30), Vector2(sofa_w, 0.82)))
		var rug_size := Vector2(minf(2.40, maxf(1.10, w - 1.20)), minf(1.35, maxf(0.70, d - 1.55)))
		specs.append(_make_furniture_spec("visual_%d_rug" % room_id, "Alfombra", "rug", Vector2((w - rug_size.x) * 0.45, (d - rug_size.y) * 0.54), rug_size))
		specs.append(_make_furniture_spec("visual_%d_table" % room_id, "Mesa centro", "coffee_table", Vector2(w * 0.42, d * 0.45), Vector2(minf(1.15, w * 0.28), 0.62)))
		specs.append(_make_furniture_spec("visual_%d_tv" % room_id, "Mueble TV", "tv_stand", Vector2(0.55, maxf(0.25, d - 0.58)), Vector2(minf(1.70, w - 1.10), 0.36)))
	elif kind.contains("dorm") or kind.contains("bed"):
		var bed_size := Vector2(minf(2.00, maxf(1.45, w - 1.15)), minf(1.35, maxf(0.90, d - 1.05)))
		specs.append(_make_furniture_spec("visual_%d_bed" % room_id, "Cama", "bed", Vector2(0.25, 0.35), bed_size))
		specs.append(_make_furniture_spec("visual_%d_wardrobe" % room_id, "Armario", "wardrobe", Vector2(w - 0.62, 0.30), Vector2(0.42, minf(1.75, d - 0.65))))
		specs.append(_make_furniture_spec("visual_%d_nightstand" % room_id, "Mesilla", "dresser", Vector2(minf(w - 0.85, bed_size.x + 0.45), 0.45), Vector2(0.42, 0.42)))
		specs.append(_make_furniture_spec("visual_%d_bedrug" % room_id, "Alfombra", "rug", Vector2(0.55, maxf(0.35, d - 0.78)), Vector2(minf(1.40, w - 1.10), 0.48)))
	elif kind.contains("cocina") or kind.contains("kitchen"):
		specs.append(_make_furniture_spec("visual_%d_counter" % room_id, "Encimera", "kitchen_unit", Vector2(0.28, 0.20), Vector2(minf(maxf(1.35, w - 1.00), 3.30), 0.62)))
		if w > 2.45 and d > 1.75:
			specs.append(_make_furniture_spec("visual_%d_kitchen_table" % room_id, "Mesa cocina", "table", Vector2(maxf(0.42, w - 1.62), maxf(0.55, d - 1.12)), Vector2(1.05, 0.68)))
		specs.append(_make_furniture_spec("visual_%d_pan" % room_id, "Grasa y aceites", "pool", Vector2(minf(w - 0.75, 1.70), 0.34), Vector2(0.42, 0.42), 0.0, 0.90))
	elif kind.contains("pasillo") or kind.contains("hall") or kind.contains("corridor"):
		specs.append(_make_furniture_spec("visual_%d_runner" % room_id, "Alfombra pasillo", "rug", Vector2(maxf(0.12, (w - minf(0.82, w - 0.36)) * 0.50), 0.42), Vector2(minf(0.82, maxf(0.36, w - 0.36)), minf(4.90, maxf(0.75, d - 0.80)))))
		specs.append(_make_furniture_spec("visual_%d_console" % room_id, "Consola", "console", Vector2(0.15, 0.35), Vector2(minf(0.42, maxf(0.28, w - 0.50)), 0.85)))
	elif kind.contains("bano") or kind.contains("baño") or kind.contains("bath"):
		specs.append(_make_furniture_spec("visual_%d_vanity" % room_id, "Mueble lavabo", "bath_vanity", Vector2((w - minf(0.85, w - 0.70)) * 0.50, maxf(0.28, d - 0.72)), Vector2(minf(0.85, maxf(0.55, w - 0.70)), 0.42)))
		specs.append(_make_furniture_spec("visual_%d_towels" % room_id, "Toallas", "textile_pile", Vector2(maxf(0.35, w - 0.85), 0.28), Vector2(0.50, 0.68)))
		specs.append(_make_furniture_spec("visual_%d_bin" % room_id, "Cubo", "plastic_bin", Vector2(0.28, 0.35), Vector2(0.38, 0.38)))
	else:
		specs.append(_make_furniture_spec("visual_%d_shelf" % room_id, "Estanteria", "bookcase", Vector2(0.22, 0.28), Vector2(0.42, minf(1.35, d - 0.55))))
		specs.append(_make_furniture_spec("visual_%d_boxes" % room_id, "Cajas", "clutter", Vector2(maxf(0.40, w - 1.05), maxf(0.40, d - 1.00)), Vector2(0.72, 0.58)))
	return specs


func _make_furniture_spec(
	obj_id: String,
	obj_name: String,
	kind: String,
	position_m: Vector2,
	size_m: Vector2,
	rotation_deg: float = 0.0,
	elevation_m: float = 0.0,
	source_fuel: bool = false
) -> Dictionary:
	return {
		"id": obj_id,
		"name": obj_name,
		"kind": kind,
		"position_m": position_m,
		"size_m": size_m,
		"rotation_deg": rotation_deg,
		"elevation_m": elevation_m,
		"source_fuel": source_fuel
	}


func _create_furniture_piece(parent: Node3D, _room: RoomModel, room_rect: Rect2, spec: Dictionary) -> void:
	var obj_id: String = String(spec.get("id", "furniture"))
	var kind: String = String(spec.get("kind", "clutter"))
	var pos_m: Vector2 = Vector2(spec.get("position_m", Vector2.ZERO))
	var size_m: Vector2 = _sane_furniture_size(kind, Vector2(spec.get("size_m", Vector2.ONE)))
	var local_rect: Rect2 = _clamp_furniture_rect(Rect2(pos_m, size_m), room_rect, kind)
	if local_rect.size.x <= 0.05 or local_rect.size.y <= 0.05:
		return

	var layout: Dictionary = _furniture_layout(kind, room_rect, local_rect, float(spec.get("rotation_deg", 0.0)))
	var shape_size: Vector2 = Vector2(layout.get("shape_size", local_rect.size))
	var yaw: float = float(layout.get("yaw", 0.0))
	var center_2d: Vector2 = room_rect.position + local_rect.position + local_rect.size * 0.5
	var root: Node3D = StaticBody3D.new() if furniture_collision_enabled else Node3D.new()
	root.name = "Furniture_" + _safe_node_name(obj_id)
	root.position = _to_world(Vector3(center_2d.x, 0.0, center_2d.y))
	root.rotation.y = yaw
	root.set_meta("furniture_kind", kind)
	root.set_meta("fuel_object_id", obj_id)
	parent.add_child(root)

	_build_furniture_shape(root, kind, shape_size, float(spec.get("elevation_m", 0.0)))
	if bool(spec.get("source_fuel", false)):
		_furniture_nodes[obj_id] = root


func _classify_furniture_kind(kind_text: String, name_text: String, id_text: String) -> String:
	var tokens: String = _furniture_tokens(kind_text, name_text, id_text)
	if tokens.contains("butaca") or tokens.contains("armchair"):
		return "armchair"
	if tokens.contains("sofa") or tokens.contains("sillon") or tokens.contains("sillón") or tokens.contains("couch"):
		return "sofa"
	if tokens.contains("cama") or tokens.contains("bed") or tokens.contains("colchon") or tokens.contains("colchón") or tokens.contains("mattress"):
		return "bed"
	if tokens.contains("mesa centro") or tokens.contains("coffee"):
		return "coffee_table"
	if tokens.contains("escritorio") or tokens.contains("desk"):
		return "desk"
	if tokens.contains("mesa") or tokens.contains("table"):
		return "table"
	if tokens.contains("tv"):
		return "tv_stand"
	if tokens.contains("libreria") or tokens.contains("librería") or tokens.contains("bookshelf") or tokens.contains("bookcase") or tokens.contains("shelf"):
		return "bookcase"
	if tokens.contains("armario") or tokens.contains("wardrobe") or tokens.contains("despensa"):
		return "wardrobe"
	if tokens.contains("encimera") or tokens.contains("cocina") or tokens.contains("kitchen") or tokens.contains("cabinet") or tokens.contains("counter"):
		return "kitchen_unit"
	if tokens.contains("alfombra") or tokens.contains("rug") or tokens.contains("moqueta") or tokens.contains("tapete"):
		return "rug"
	if tokens.contains("cortina") or tokens.contains("curtain"):
		return "curtain"
	if tokens.contains("grasa") or tokens.contains("aceite") or tokens.contains("liquido") or tokens.contains("líquido") or tokens.contains("pool"):
		return "pool"
	if tokens.contains("plastico") or tokens.contains("plástico") or tokens.contains("plastic") or tokens.contains("cubo") or tokens.contains("bin"):
		return "plastic_bin"
	if tokens.contains("toalla") or tokens.contains("pano") or tokens.contains("paño") or tokens.contains("textil") or tokens.contains("textile") or tokens.contains("ropa") or tokens.contains("bedding"):
		return "textile_pile"
	if tokens.contains("comoda") or tokens.contains("cómoda") or tokens.contains("cajonera") or tokens.contains("mesilla") or tokens.contains("aparador") or tokens.contains("consola") or tokens.contains("zapatero"):
		return "dresser"
	if tokens.contains("mobiliario_tapizado"):
		return "sofa"
	if tokens.contains("mobiliario_madera"):
		return "storage"
	if tokens.contains("mobiliario_mixto") or tokens.contains("resto") or tokens.contains("remaining") or tokens.contains("mixed"):
		return "clutter"
	return "clutter"


func _furniture_tokens(kind_text: String, name_text: String, id_text: String) -> String:
	return ("%s %s %s" % [kind_text, name_text, id_text]).strip_edges().to_lower()


func _sane_furniture_size(kind: String, raw_size: Vector2) -> Vector2:
	var size := Vector2(absf(raw_size.x), absf(raw_size.y))
	if size.x < 0.05:
		size.x = 0.45
	if size.y < 0.05:
		size.y = 0.45
	match kind:
		"curtain":
			size.x = maxf(size.x, 0.55)
			size.y = clampf(size.y, 0.06, 0.18)
		"rug":
			size.x = maxf(size.x, 0.45)
			size.y = maxf(size.y, 0.35)
		"pool", "plastic_bin":
			size.x = clampf(size.x, 0.28, 0.70)
			size.y = clampf(size.y, 0.28, 0.70)
		"wardrobe", "bookcase":
			size.x = clampf(size.x, 0.32, 2.00)
			size.y = clampf(size.y, 0.32, 2.20)
		_:
			size.x = clampf(size.x, 0.22, 3.50)
			size.y = clampf(size.y, 0.22, 2.60)
	return size


func _clamp_furniture_rect(local_rect: Rect2, room_rect: Rect2, kind: String) -> Rect2:
	var margin: float = maxf(0.0, furniture_wall_margin_m)
	if kind == "rug":
		margin = minf(margin, 0.035)
	if kind == "curtain":
		margin = 0.015
	var max_w: float = maxf(0.10, room_rect.size.x - margin * 2.0)
	var max_d: float = maxf(0.10, room_rect.size.y - margin * 2.0)
	var size := Vector2(clampf(local_rect.size.x, 0.10, max_w), clampf(local_rect.size.y, 0.10, max_d))
	var max_x: float = maxf(margin, room_rect.size.x - margin - size.x)
	var max_y: float = maxf(margin, room_rect.size.y - margin - size.y)
	var pos := Vector2(clampf(local_rect.position.x, margin, max_x), clampf(local_rect.position.y, margin, max_y))
	return Rect2(pos, size)


func _furniture_layout(kind: String, room_rect: Rect2, local_rect: Rect2, rotation_deg: float) -> Dictionary:
	var footprint: Vector2 = local_rect.size
	var shape_size: Vector2 = footprint
	var side: String = _nearest_side_for_furniture(room_rect, local_rect)
	var yaw: float = 0.0

	match kind:
		"bed":
			var long_is_x: bool = footprint.x >= footprint.y
			side = _nearest_side_along_axis(room_rect, local_rect, long_is_x)
			yaw = _yaw_for_wall_side(side)
			shape_size = Vector2(minf(footprint.x, footprint.y), maxf(footprint.x, footprint.y))
		"sofa", "armchair":
			var sofa_long_is_x: bool = footprint.x >= footprint.y
			side = _nearest_side_perpendicular_to_depth(room_rect, local_rect, sofa_long_is_x)
			yaw = _yaw_for_wall_side(side)
			shape_size = Vector2(maxf(footprint.x, footprint.y), minf(footprint.x, footprint.y))
		"wardrobe", "bookcase", "dresser", "tv_stand", "console", "storage", "kitchen_unit", "bath_vanity":
			yaw = _yaw_for_wall_side(side)
			shape_size = Vector2(maxf(footprint.x, footprint.y), minf(footprint.x, footprint.y))
		"curtain":
			yaw = 0.0 if footprint.x >= footprint.y else deg_to_rad(90.0)
		_:
			yaw = 0.0
	if absf(rotation_deg) > 0.001:
		yaw = deg_to_rad(rotation_deg)
	return {"yaw": yaw, "shape_size": shape_size}


func _nearest_side_for_furniture(room_rect: Rect2, local_rect: Rect2) -> String:
	var left: float = local_rect.position.x
	var right: float = room_rect.size.x - (local_rect.position.x + local_rect.size.x)
	var top: float = local_rect.position.y
	var bottom: float = room_rect.size.y - (local_rect.position.y + local_rect.size.y)
	var best: float = top
	var side: String = "top"
	if bottom < best:
		best = bottom
		side = "bottom"
	if left < best:
		best = left
		side = "left"
	if right < best:
		side = "right"
	return side


func _nearest_side_along_axis(room_rect: Rect2, local_rect: Rect2, long_is_x: bool) -> String:
	var left: float = local_rect.position.x
	var right: float = room_rect.size.x - (local_rect.position.x + local_rect.size.x)
	var top: float = local_rect.position.y
	var bottom: float = room_rect.size.y - (local_rect.position.y + local_rect.size.y)
	if long_is_x:
		return "left" if left <= right else "right"
	return "top" if top <= bottom else "bottom"


func _nearest_side_perpendicular_to_depth(room_rect: Rect2, local_rect: Rect2, long_is_x: bool) -> String:
	var left: float = local_rect.position.x
	var right: float = room_rect.size.x - (local_rect.position.x + local_rect.size.x)
	var top: float = local_rect.position.y
	var bottom: float = room_rect.size.y - (local_rect.position.y + local_rect.size.y)
	if long_is_x:
		return "top" if top <= bottom else "bottom"
	return "left" if left <= right else "right"


func _yaw_for_wall_side(side: String) -> float:
	match side:
		"bottom":
			return PI
		"left":
			return deg_to_rad(90.0)
		"right":
			return deg_to_rad(-90.0)
		_:
			return 0.0


func _build_furniture_shape(root: Node3D, kind: String, size_m: Vector2, elevation_m: float) -> void:
	if _try_build_furniture_asset(root, kind, size_m, elevation_m):
		return
	match kind:
		"sofa":
			_build_fp_sofa(root, size_m, false)
		"armchair":
			_build_fp_sofa(root, Vector2(minf(size_m.x, 0.95), maxf(size_m.y, 0.72)), true)
		"bed":
			_build_fp_bed(root, size_m)
		"table", "desk", "coffee_table":
			_build_fp_table(root, size_m, kind)
		"wardrobe":
			_build_fp_storage(root, size_m, 1.90, true)
		"bookcase":
			_build_fp_bookcase(root, size_m)
		"kitchen_unit":
			_build_fp_kitchen_unit(root, size_m)
		"tv_stand", "console", "dresser", "storage", "bath_vanity":
			var h: float = 0.50 if kind == "tv_stand" or kind == "console" else 0.82
			if kind == "bath_vanity":
				h = 0.72
			_build_fp_storage(root, size_m, h, false)
		"rug":
			_build_fp_rug(root, size_m)
		"curtain":
			_build_fp_curtain(root, size_m)
		"textile_pile":
			_build_fp_textiles(root, size_m, elevation_m)
		"pool":
			_build_fp_pool(root, size_m, elevation_m)
		"plastic_bin":
			_build_fp_plastic_bin(root, size_m)
		_:
			_build_fp_clutter(root, size_m)


func _try_build_furniture_asset(parent: Node3D, kind: String, size_m: Vector2, elevation_m: float) -> bool:
	var asset_kind: String = kind
	match kind:
		"storage", "console", "bath_vanity":
			asset_kind = "dresser"
		"desk":
			asset_kind = "table"
		"coffee_table":
			asset_kind = "coffee_table"
		"textile_pile":
			asset_kind = "textile_pile"
		_:
			asset_kind = kind
	var scene_path: String = "res://assets/fp/furniture/%s.tscn" % asset_kind
	if not ResourceLoader.exists(scene_path):
		return false
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return false
	instance.name = "Asset_%s" % asset_kind
	instance.scale = Vector3(maxf(0.05, size_m.x), 1.0, maxf(0.05, size_m.y))
	if kind == "pool":
		instance.position.y = maxf(0.0, elevation_m)
	_prepare_asset_materials(instance)
	parent.add_child(instance)
	_add_asset_collision_box(parent, kind, size_m, elevation_m)
	return true


func _try_build_opening_asset(parent: Node3D, op: OpeningModel) -> Node3D:
	if op == null:
		return null
	var asset_name: String = "door_panel" if op.type == OpeningModel.Type.DOOR else "window_panel"
	var scene_path: String = "res://assets/fp/openings/%s.tscn" % asset_name
	if not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return null
	instance.name = "Asset_%s" % asset_name
	_prepare_asset_materials(instance)
	parent.add_child(instance)
	return instance


func _create_window_leaf_visual(
	parent: Node3D,
	node_name: String,
	leaf_width_m: float,
	height_m: float,
	thickness_m: float,
	handle_sign: float
) -> Node3D:
	var leaf := Node3D.new()
	leaf.name = node_name
	parent.add_child(leaf)

	var bar_m: float = clampf(leaf_width_m * 0.12, 0.050, 0.080)
	var glass_w: float = maxf(0.08, leaf_width_m - bar_m * 2.1)
	var glass_h: float = maxf(0.12, height_m - bar_m * 2.1)
	var frame_color: Color = opening_frame_color.lightened(0.04)
	_add_local_box(leaf, "Glass", Vector3.ZERO, Vector3(glass_w, glass_h, thickness_m * 0.36), window_glass_closed_color, false)
	_add_local_box(leaf, "LeafFrameTop", Vector3(0.0, height_m * 0.5 - bar_m * 0.5, 0.0), Vector3(leaf_width_m, bar_m, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafFrameBottom", Vector3(0.0, -height_m * 0.5 + bar_m * 0.5, 0.0), Vector3(leaf_width_m, bar_m, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafFrameLeft", Vector3(-leaf_width_m * 0.5 + bar_m * 0.5, 0.0, 0.0), Vector3(bar_m, height_m, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafFrameRight", Vector3(leaf_width_m * 0.5 - bar_m * 0.5, 0.0, 0.0), Vector3(bar_m, height_m, thickness_m), frame_color, false)
	_add_local_box(
		leaf,
		"Handle",
		Vector3(handle_sign * (leaf_width_m * 0.5 - bar_m * 1.35), -height_m * 0.08, -thickness_m * 0.64),
		Vector3(0.035, 0.24, 0.035),
		Color(0.72, 0.58, 0.32, 1.0),
		false
	)
	return leaf


func _set_window_leaf_glass_color(leaf: Node3D, color: Color) -> void:
	if leaf == null:
		return
	var glass := leaf.get_node_or_null("Glass") as MeshInstance3D
	if glass == null:
		return
	var mat := glass.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color


func _prepare_asset_materials(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var material_copy := mat.duplicate() as StandardMaterial3D
				mesh_node.material_override = material_copy
				if not mesh_node.has_meta("base_color"):
					mesh_node.set_meta("base_color", material_copy.albedo_color)
		if child.get_child_count() > 0:
			_prepare_asset_materials(child)


func _add_asset_collision_box(parent: Node3D, kind: String, size_m: Vector2, elevation_m: float) -> void:
	if not furniture_collision_enabled or not (parent is StaticBody3D):
		return
	if kind == "rug" or kind == "curtain" or kind == "textile_pile" or kind == "pool":
		return
	var shape := CollisionShape3D.new()
	shape.name = "AssetCollision"
	var box := BoxShape3D.new()
	var height_m: float = _asset_collision_height(kind)
	box.size = Vector3(maxf(0.12, size_m.x), height_m, maxf(0.12, size_m.y))
	shape.shape = box
	shape.position = Vector3(0.0, maxf(0.0, elevation_m) + height_m * 0.5, 0.0)
	parent.add_child(shape)


func _asset_collision_height(kind: String) -> float:
	match kind:
		"bed":
			return 0.66
		"sofa", "armchair":
			return 0.82
		"wardrobe", "bookcase", "kitchen_unit":
			return 1.78
		"table", "desk":
			return 0.78
		"coffee_table", "tv_stand", "console":
			return 0.48
		"plastic_bin":
			return 0.55
		_:
			return 0.86


func _build_fp_sofa(parent: Node3D, size_m: Vector2, armchair: bool) -> void:
	var x: float = maxf(0.65, size_m.x)
	var z: float = maxf(0.58, size_m.y)
	var arm_w: float = minf(0.16, x * 0.16)
	var cushion_count: int = 1 if armchair or x < 1.20 else 3
	_add_local_box(parent, "SofaBase", Vector3(0.0, 0.17, 0.05), Vector3(x * 0.92, 0.18, z * 0.74), furniture_upholstery_color.darkened(0.12), true)
	_add_local_box(parent, "SofaBack", Vector3(0.0, 0.52, -z * 0.5 + 0.07), Vector3(x, 0.66, 0.14), furniture_upholstery_color.darkened(0.20), true)
	_add_local_box(parent, "SofaArmLeft", Vector3(-x * 0.5 + arm_w * 0.5, 0.38, 0.04), Vector3(arm_w, 0.44, z * 0.78), furniture_upholstery_color.darkened(0.16), true)
	_add_local_box(parent, "SofaArmRight", Vector3(x * 0.5 - arm_w * 0.5, 0.38, 0.04), Vector3(arm_w, 0.44, z * 0.78), furniture_upholstery_color.darkened(0.16), true)
	for i in range(cushion_count):
		var t: float = 0.5 if cushion_count == 1 else float(i) / float(cushion_count - 1)
		var cx: float = lerpf(-x * 0.27, x * 0.27, t)
		_add_local_box(parent, "SofaCushion_%d" % i, Vector3(cx, 0.34, 0.08), Vector3(x * 0.72 / float(cushion_count), 0.11, z * 0.55), furniture_upholstery_color.lightened(0.08), false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_local_box(parent, "SofaLeg", Vector3(sx * x * 0.34, 0.055, sz * z * 0.25), Vector3(0.055, 0.11, 0.055), furniture_wood_color.darkened(0.35), false)


func _build_fp_bed(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.78, size_m.x)
	var z: float = maxf(1.15, size_m.y)
	_add_local_box(parent, "BedFrame", Vector3(0.0, 0.17, 0.0), Vector3(x, 0.20, z), furniture_wood_color.darkened(0.10), true)
	_add_local_box(parent, "Mattress", Vector3(0.0, 0.38, 0.02), Vector3(x * 0.94, 0.25, z * 0.90), furniture_light_fabric_color, true)
	_add_local_box(parent, "Blanket", Vector3(0.0, 0.535, z * 0.12), Vector3(x * 0.90, 0.075, z * 0.52), furniture_upholstery_color.lightened(0.16), false)
	var pillow_count: int = 2 if x > 1.18 else 1
	for i in range(pillow_count):
		var cx: float = 0.0 if pillow_count == 1 else lerpf(-x * 0.23, x * 0.23, float(i))
		_add_local_box(parent, "Pillow_%d" % i, Vector3(cx, 0.61, -z * 0.34), Vector3(x * (0.36 if pillow_count == 2 else 0.48), 0.12, z * 0.16), Color(0.88, 0.84, 0.74, 1.0), false)
	_add_local_box(parent, "Headboard", Vector3(0.0, 0.56, -z * 0.5 - 0.035), Vector3(x, 0.78, 0.07), furniture_wood_color, true)


func _build_fp_table(parent: Node3D, size_m: Vector2, kind: String) -> void:
	var x: float = maxf(0.42, size_m.x)
	var z: float = maxf(0.36, size_m.y)
	var h: float = 0.42 if kind == "coffee_table" else 0.74
	if kind == "desk":
		h = 0.76
	var leg_w: float = minf(0.075, minf(x, z) * 0.14)
	_add_local_box(parent, "TableTop", Vector3(0.0, h, 0.0), Vector3(x, 0.075, z), furniture_wood_color.lightened(0.06), true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_local_box(parent, "TableLeg", Vector3(sx * (x * 0.5 - leg_w), h * 0.50, sz * (z * 0.5 - leg_w)), Vector3(leg_w, h, leg_w), furniture_wood_color.darkened(0.18), true)
	if kind == "desk":
		_add_local_box(parent, "DeskDrawer", Vector3(-x * 0.25, h - 0.16, z * 0.36), Vector3(x * 0.34, 0.18, 0.08), furniture_wood_color.darkened(0.05), false)


func _build_fp_storage(parent: Node3D, size_m: Vector2, height_m: float, tall_doors: bool) -> void:
	var x: float = maxf(0.34, size_m.x)
	var z: float = maxf(0.30, size_m.y)
	var h: float = maxf(0.36, height_m)
	_add_local_box(parent, "StorageBody", Vector3(0.0, h * 0.5, 0.0), Vector3(x, h, z), furniture_wood_color, true)
	var front_z: float = z * 0.5 + 0.012
	if tall_doors:
		_add_local_box(parent, "DoorLeft", Vector3(-x * 0.25, h * 0.51, front_z), Vector3(x * 0.45, h * 0.84, 0.035), furniture_wood_color.lightened(0.10), false)
		_add_local_box(parent, "DoorRight", Vector3(x * 0.25, h * 0.51, front_z), Vector3(x * 0.45, h * 0.84, 0.035), furniture_wood_color.lightened(0.10), false)
		_add_local_box(parent, "HandleLeft", Vector3(-x * 0.06, h * 0.50, front_z + 0.025), Vector3(0.022, h * 0.22, 0.022), Color(0.75, 0.62, 0.38, 1.0), false)
		_add_local_box(parent, "HandleRight", Vector3(x * 0.06, h * 0.50, front_z + 0.025), Vector3(0.022, h * 0.22, 0.022), Color(0.75, 0.62, 0.38, 1.0), false)
	else:
		for row in range(2):
			var cy: float = h * (0.34 + float(row) * 0.28)
			_add_local_box(parent, "Drawer_%d" % row, Vector3(0.0, cy, front_z), Vector3(x * 0.82, h * 0.18, 0.035), furniture_wood_color.lightened(0.12), false)
			_add_local_box(parent, "DrawerHandle_%d" % row, Vector3(0.0, cy, front_z + 0.025), Vector3(x * 0.25, 0.022, 0.022), Color(0.74, 0.60, 0.36, 1.0), false)


func _build_fp_bookcase(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.34, size_m.x)
	var z: float = maxf(0.28, size_m.y)
	var h: float = 1.72
	_add_local_box(parent, "BookcaseBack", Vector3(0.0, h * 0.5, -z * 0.46), Vector3(x, h, 0.045), furniture_wood_color.darkened(0.08), true)
	_add_local_box(parent, "BookcaseLeft", Vector3(-x * 0.5 + 0.025, h * 0.5, 0.0), Vector3(0.05, h, z), furniture_wood_color, true)
	_add_local_box(parent, "BookcaseRight", Vector3(x * 0.5 - 0.025, h * 0.5, 0.0), Vector3(0.05, h, z), furniture_wood_color, true)
	for level in range(4):
		var y: float = h * (0.18 + float(level) * 0.22)
		_add_local_box(parent, "Shelf_%d" % level, Vector3(0.0, y, 0.0), Vector3(x, 0.045, z), furniture_wood_color.lightened(0.06), false)
		var book_count: int = 4
		for i in range(book_count):
			var bx: float = -x * 0.36 + float(i) * x * 0.23
			var bh: float = 0.18 + 0.04 * float((i + level) % 2)
			_add_local_box(parent, "Book_%d_%d" % [level, i], Vector3(bx, y + bh * 0.5 + 0.025, z * 0.12), Vector3(x * 0.10, bh, z * 0.32), Color(0.34 + 0.08 * float(i % 2), 0.23 + 0.05 * float(level % 2), 0.18, 1.0), false)


func _build_fp_kitchen_unit(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.70, size_m.x)
	var z: float = maxf(0.45, size_m.y)
	_add_local_box(parent, "LowerCabinets", Vector3(0.0, 0.42, 0.0), Vector3(x, 0.84, z), furniture_wood_color.lightened(0.06), true)
	_add_local_box(parent, "Countertop", Vector3(0.0, 0.88, 0.0), Vector3(x * 1.03, 0.075, z * 1.04), furniture_counter_color, true)
	var doors: int = clampi(int(round(x / 0.70)), 2, 5)
	for i in range(doors):
		var t: float = (float(i) + 0.5) / float(doors) - 0.5
		_add_local_box(parent, "CabinetDoor_%d" % i, Vector3(t * x * 0.86, 0.43, z * 0.5 + 0.014), Vector3(x * 0.72 / float(doors), 0.54, 0.032), furniture_wood_color.lightened(0.14), false)
		_add_local_box(parent, "CabinetHandle_%d" % i, Vector3(t * x * 0.86, 0.56, z * 0.5 + 0.035), Vector3(x * 0.16 / float(doors), 0.022, 0.022), Color(0.72, 0.62, 0.42, 1.0), false)
	if x > 1.4:
		_add_local_box(parent, "UpperCabinet", Vector3(-x * 0.18, 1.55, -z * 0.20), Vector3(x * 0.48, 0.48, z * 0.42), furniture_wood_color.lightened(0.10), false)


func _build_fp_rug(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.36, size_m.x)
	var z: float = maxf(0.30, size_m.y)
	_add_local_box(parent, "RugOuter", Vector3(0.0, 0.018, 0.0), Vector3(x, 0.025, z), furniture_rug_color, false)
	_add_local_box(parent, "RugInner", Vector3(0.0, 0.034, 0.0), Vector3(x * 0.78, 0.016, z * 0.70), furniture_rug_color.lightened(0.22), false)
	_add_local_box(parent, "RugFringeA", Vector3(0.0, 0.034, -z * 0.5 - 0.025), Vector3(x * 0.86, 0.014, 0.035), Color(0.78, 0.68, 0.54, 1.0), false)
	_add_local_box(parent, "RugFringeB", Vector3(0.0, 0.034, z * 0.5 + 0.025), Vector3(x * 0.86, 0.014, 0.035), Color(0.78, 0.68, 0.54, 1.0), false)


func _build_fp_curtain(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.55, size_m.x)
	var panels: int = 6
	var panel_w: float = x / float(panels)
	for i in range(panels):
		var offset_x: float = -x * 0.5 + panel_w * (float(i) + 0.5)
		var fold_z: float = (-0.035 if i % 2 == 0 else 0.035)
		_add_local_box(parent, "CurtainPanel_%d" % i, Vector3(offset_x, 1.22, fold_z), Vector3(panel_w * 0.72, 1.70, 0.035), furniture_upholstery_color.lightened(0.20), false)
	_add_local_box(parent, "CurtainRail", Vector3(0.0, 2.10, 0.0), Vector3(x, 0.035, 0.045), furniture_wood_color.darkened(0.20), false)


func _build_fp_textiles(parent: Node3D, size_m: Vector2, elevation_m: float) -> void:
	var x: float = maxf(0.35, size_m.x)
	var z: float = maxf(0.30, size_m.y)
	var base_y: float = clampf(elevation_m, 0.04, 0.14)
	for i in range(5):
		var seed: float = float(i) * 1.61
		var offset := Vector3(sin(seed) * x * 0.20, base_y + 0.055 * float(i), cos(seed) * z * 0.18)
		_add_local_box(parent, "TextileFold_%d" % i, offset, Vector3(x * (0.42 - 0.03 * float(i % 2)), 0.09, z * (0.34 + 0.04 * float(i % 2))), furniture_light_fabric_color.darkened(0.06 + 0.04 * float(i % 2)), false)


func _build_fp_pool(parent: Node3D, size_m: Vector2, elevation_m: float) -> void:
	var radius: float = maxf(0.13, minf(size_m.x, size_m.y) * 0.45)
	var y: float = maxf(0.035, elevation_m + 0.025)
	_add_local_cylinder(parent, "OilPan", Vector3(0.0, y, 0.0), radius, 0.035, Color(0.18, 0.15, 0.10, 1.0), false)
	_add_local_cylinder(parent, "OilSurface", Vector3(0.0, y + 0.026, 0.0), radius * 0.86, 0.012, Color(0.10, 0.075, 0.045, 0.86), false)


func _build_fp_plastic_bin(parent: Node3D, size_m: Vector2) -> void:
	var radius: float = maxf(0.13, minf(size_m.x, size_m.y) * 0.42)
	_add_local_cylinder(parent, "BinBody", Vector3(0.0, 0.25, 0.0), radius, 0.50, Color(0.36, 0.39, 0.38, 1.0), true)
	_add_local_box(parent, "BinLid", Vector3(0.0, 0.52, 0.0), Vector3(radius * 2.25, 0.045, radius * 2.25), Color(0.25, 0.28, 0.27, 1.0), false)


func _build_fp_clutter(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.38, size_m.x)
	var z: float = maxf(0.34, size_m.y)
	for i in range(5):
		var seed: float = float(i) * 2.09
		var sx: float = x * (0.22 + 0.05 * float(i % 2))
		var sz: float = z * (0.20 + 0.04 * float((i + 1) % 2))
		var h: float = 0.16 + 0.07 * float(i % 3)
		var offset := Vector3(sin(seed) * x * 0.26, h * 0.5 + 0.02 * float(i), cos(seed * 0.8) * z * 0.25)
		_add_local_box(parent, "Clutter_%d" % i, offset, Vector3(sx, h, sz), furniture_wood_color.lightened(0.04 * float(i % 2)), false)


func _add_local_box(parent: Node3D, node_name: String, center_m: Vector3, size_m: Vector3, color: Color, with_collision: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_m
	mesh.mesh = box_mesh
	mesh.material_override = _mat(color, color.a < 1.0)
	mesh.position = center_m
	mesh.set_meta("base_color", color)
	parent.add_child(mesh)
	if with_collision and furniture_collision_enabled and parent is StaticBody3D:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size_m
		shape.shape = box
		shape.position = center_m
		parent.add_child(shape)
	return mesh


func _add_local_cylinder(parent: Node3D, node_name: String, center_m: Vector3, radius_m: float, height_m: float, color: Color, with_collision: bool) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_m
	mesh.bottom_radius = radius_m
	mesh.height = height_m
	mesh.radial_segments = 20
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = _mat(color, color.a < 1.0)
	node.position = center_m
	node.set_meta("base_color", color)
	parent.add_child(node)
	if with_collision and furniture_collision_enabled and parent is StaticBody3D:
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius_m
		cylinder.height = height_m
		shape.shape = cylinder
		shape.position = center_m
		parent.add_child(shape)
	return node


func _update_furniture_state_visuals() -> void:
	if not furniture_state_tint_enabled or _furniture_nodes.is_empty() or _state.is_empty():
		return
	for state_value in _state.values():
		if typeof(state_value) != TYPE_DICTIONARY:
			continue
		var room_state: Dictionary = state_value
		var objects: Array = room_state.get("fuel_objects", [])
		for raw_obj in objects:
			if typeof(raw_obj) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = raw_obj
			var obj_id: String = String(obj.get("id", ""))
			if obj_id == "" or not _furniture_nodes.has(obj_id):
				continue
			var fuel_mj: float = maxf(0.01, float(obj.get("fuel_energy_MJ", 1.0)))
			var remaining_ratio: float = clampf(float(obj.get("remaining_fuel_MJ", fuel_mj)) / fuel_mj, 0.0, 1.0)
			_apply_furniture_state_to_node(
				_furniture_nodes[obj_id] as Node,
				String(obj.get("state", "cold")),
				remaining_ratio
			)


func _apply_furniture_state_to_node(root: Node, state_name: String, remaining_ratio: float) -> void:
	if root == null:
		return
	var heat_t: float = 0.0
	match state_name:
		"flaming":
			heat_t = 1.0
		"pyrolyzing":
			heat_t = 0.65
		"heating":
			heat_t = 0.32
		"decaying":
			heat_t = 0.18
		_:
			heat_t = 0.0
	var char_t: float = clampf(1.0 - remaining_ratio, 0.0, 1.0)
	_apply_furniture_material_recursive(root, heat_t, char_t, _state_heat_color(state_name))


func _apply_furniture_material_recursive(root: Node, heat_t: float, char_t: float, heat_color: Color) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var base_color: Color = Color(mesh_node.get_meta("base_color", Color(0.55, 0.52, 0.48, 1.0)))
				var final_color: Color = base_color.lerp(Color(0.10, 0.09, 0.08, base_color.a), clampf(char_t * 0.75, 0.0, 0.85))
				final_color = final_color.lerp(heat_color, heat_t * 0.38)
				if heat_t <= 0.001 and char_t <= 0.001:
					final_color = base_color
				mat.albedo_color = Color(final_color.r, final_color.g, final_color.b, base_color.a)
				mat.emission_enabled = heat_t > 0.05
				if mat.emission_enabled:
					mat.emission = Color(heat_color.r, heat_color.g * 0.65, heat_color.b * 0.20, 1.0)
					mat.emission_energy_multiplier = heat_t * 1.25
				else:
					mat.emission_energy_multiplier = 0.0
		if child.get_child_count() > 0:
			_apply_furniture_material_recursive(child, heat_t, char_t, heat_color)


func _state_heat_color(state_name: String) -> Color:
	match state_name:
		"flaming":
			return Color(1.0, 0.24, 0.08, 1.0)
		"pyrolyzing":
			return Color(1.0, 0.52, 0.10, 1.0)
		"heating":
			return Color(1.0, 0.78, 0.22, 1.0)
		"decaying":
			return Color(0.72, 0.36, 0.16, 1.0)
		_:
			return Color(0.55, 0.52, 0.48, 1.0)


func _safe_node_name(value: String) -> String:
	var result: String = value.strip_edges()
	if result == "":
		return "furniture"
	result = result.replace(" ", "_")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	result = result.replace(":", "_")
	return result


func _create_outer_boundary() -> void:
	var grow: float = 0.22
	var rect: Rect2 = _bounds_m.grow(grow)
	_create_boundary_segment(Vector3(rect.position.x + rect.size.x * 0.5, boundary_height_m * 0.5, rect.position.y - grow), Vector3(rect.size.x + grow * 2.0, boundary_height_m, wall_thickness_m))
	_create_boundary_segment(Vector3(rect.position.x + rect.size.x * 0.5, boundary_height_m * 0.5, rect.position.y + rect.size.y + grow), Vector3(rect.size.x + grow * 2.0, boundary_height_m, wall_thickness_m))
	_create_boundary_segment(Vector3(rect.position.x - grow, boundary_height_m * 0.5, rect.position.y + rect.size.y * 0.5), Vector3(wall_thickness_m, boundary_height_m, rect.size.y + grow * 2.0))
	_create_boundary_segment(Vector3(rect.position.x + rect.size.x + grow, boundary_height_m * 0.5, rect.position.y + rect.size.y * 0.5), Vector3(wall_thickness_m, boundary_height_m, rect.size.y + grow * 2.0))


func _create_boundary_segment(center_m: Vector3, size_m: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "NoExitBoundary"
	_world_root.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_m
	shape.shape = box
	shape.position = _to_world(center_m)
	body.add_child(shape)


func _add_box(parent: Node3D, node_name: String, size_m: Vector3, center_world: Vector3, material: StandardMaterial3D, with_collision: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = size_m
	mesh.mesh = box_mesh
	mesh.material_override = material
	mesh.position = center_world
	parent.add_child(mesh)
	if with_collision:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size_m
		shape.shape = box
		shape.position = center_world
		parent.add_child(shape)
	return mesh


func _add_oriented_box(
	parent: Node3D,
	node_name: String,
	center_world: Vector3,
	tangent: Vector3,
	tangent_extent_m: float,
	height_m: float,
	normal_depth_m: float,
	material: StandardMaterial3D,
	with_collision: bool
) -> MeshInstance3D:
	var size_m: Vector3
	if absf(tangent.x) >= absf(tangent.z):
		size_m = Vector3(tangent_extent_m, height_m, normal_depth_m)
	else:
		size_m = Vector3(normal_depth_m, height_m, tangent_extent_m)
	return _add_box(parent, node_name, size_m, center_world, material, with_collision)


func _apply_movement(delta: float) -> void:
	var input_vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_vec.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_vec.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vec.x += 1.0
	input_vec = input_vec.normalized()

	var basis := global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var direction := (right * input_vec.x + forward * -input_vec.y).normalized()
	var speed: float = _current_speed()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= gravity_m_s2 * delta
	else:
		velocity.y = -0.05
	move_and_slide()


func _update_prompt() -> void:
	if _prompt_label == null or building == null:
		return
	_nearest_opening_index = _find_nearest_opening()
	if _nearest_opening_index < 0:
		_prompt_label.visible = false
		return
	var op: OpeningModel = building.get_opening_at(_nearest_opening_index)
	if op == null:
		_prompt_label.visible = false
		return
	var kind: String = "puerta" if op.type == OpeningModel.Type.DOOR else "ventana"
	var action: String = "cerrar" if op.open_fraction > 0.5 else "abrir"
	_prompt_label.text = "F para %s %s" % [action, kind]
	_prompt_label.visible = true


func _update_visibility_overlay() -> void:
	if _visibility_overlay == null:
		return
	if not _active or building == null or _state.is_empty():
		_visibility_overlay.color = Color(0.08, 0.09, 0.09, 0.0)
		return
	_current_room_id = _find_current_room_id()
	if _current_room_id < 0:
		_visibility_overlay.color = Color(0.08, 0.09, 0.09, 0.0)
		return
	var room_state: Dictionary = Dictionary(_state.get(str(_current_room_id), {}))
	if room_state.is_empty():
		_visibility_overlay.color = Color(0.08, 0.09, 0.09, 0.0)
		return
	var visibility_m: float = float(room_state.get("visibility_m", 30.0))
	var smoke_kg: float = float(room_state.get("smoke_kg", 0.0))
	var upper_temp_c: float = float(room_state.get("temp_upper_c", 20.0))
	var room_height_m: float = float(room_state.get("height_m", 2.4))
	var smoke_layer_m: float = clampf(
		float(room_state.get("smoke_layer_m", room_state.get("h_layer_m", room_height_m))),
		0.0,
		room_height_m
	)
	var eye_height_m: float = _camera.global_position.y if _camera != null else _current_height()
	var immersion: float = clampf(
		(eye_height_m + smoke_overlay_layer_clearance_m - smoke_layer_m) / maxf(0.05, smoke_overlay_layer_transition_m),
		0.0,
		1.0
	)
	var rects: Dictionary = building.get_room_rects_m()
	var room_rect: Rect2 = Rect2(rects.get(_current_room_id, Rect2()))
	var upper_depth_m: float = maxf(0.05, room_height_m - smoke_layer_m)
	var upper_volume_m3: float = maxf(0.05, room_rect.size.x * room_rect.size.y * upper_depth_m)
	var smoke_density_t: float = clampf((smoke_kg / upper_volume_m3) / 0.018, 0.0, 1.0)
	var alpha_from_visibility: float = clampf(
		(smoke_overlay_visibility_reference_m - visibility_m) / maxf(0.1, smoke_overlay_visibility_reference_m),
		0.0,
		0.86
	)
	var alpha_from_smoke: float = clampf(smoke_kg / 1.4, 0.0, 0.55)
	var alpha_from_layer: float = (0.24 + smoke_density_t * 0.48) * immersion
	var heat_tint: float = clampf((upper_temp_c - 80.0) / 420.0, 0.0, 1.0)
	var alpha: float = clampf(maxf(maxf(alpha_from_visibility, alpha_from_smoke) * immersion, alpha_from_layer), 0.0, smoke_overlay_max_alpha)
	var color := Color(
		lerpf(0.08, 0.18, heat_tint),
		lerpf(0.09, 0.11, heat_tint),
		lerpf(0.09, 0.07, heat_tint),
		alpha
	)
	_visibility_overlay.color = color


func _find_current_room_id() -> int:
	if building == null:
		return -1
	var pos_m := Vector2(global_position.x - _origin_offset_m.x, global_position.z - _origin_offset_m.y)
	var rects: Dictionary = building.get_room_rects_m()
	for key in rects.keys():
		var rect: Rect2 = Rect2(rects[key])
		if rect.has_point(pos_m):
			return int(key)
	return -1


func _interact_with_nearest_opening() -> void:
	if building == null:
		return
	if _nearest_opening_index < 0:
		_nearest_opening_index = _find_nearest_opening()
	if _nearest_opening_index < 0:
		return
	var op: OpeningModel = building.get_opening_at(_nearest_opening_index)
	if op == null:
		return
	if op.open_fraction > 0.5:
		building.close_opening(_nearest_opening_index)
	else:
		building.open_opening(_nearest_opening_index)
	_update_opening_panel(_nearest_opening_index)
	opening_changed.emit()
	_update_prompt()


func _sync_opening_panels() -> void:
	if building == null:
		return
	for index in _opening_nodes.keys():
		_update_opening_panel(int(index))


func _update_window_leaf_pair(
	left_leaf: Node3D,
	right_leaf: Node3D,
	center: Vector3,
	tangent: Vector3,
	normal: Vector3,
	base_yaw: float,
	width_m: float,
	_height_m: float,
	open_amount: float
) -> void:
	var leaf_width_m: float = maxf(0.08, width_m * 0.5)
	var outward: Vector3 = -normal.normalized()
	var clearance: Vector3 = outward * opening_panel_clearance_m
	var left_closed_center: Vector3 = center - tangent * (leaf_width_m * 0.5) + clearance
	var right_closed_center: Vector3 = center + tangent * (leaf_width_m * 0.5) + clearance
	var left_yaw: float = base_yaw
	var right_yaw: float = base_yaw
	var left_center: Vector3 = left_closed_center
	var right_center: Vector3 = right_closed_center

	if open_amount > 0.01:
		var angle: float = deg_to_rad(window_open_angle_deg) * open_amount
		var left_hinge: Vector3 = center - tangent * (width_m * 0.5)
		var right_hinge: Vector3 = center + tangent * (width_m * 0.5)
		left_yaw = _pick_window_leaf_yaw(base_yaw, angle, left_hinge, leaf_width_m, left_closed_center, outward, true)
		right_yaw = _pick_window_leaf_yaw(base_yaw, angle, right_hinge, leaf_width_m, right_closed_center, outward, false)
		var left_axis: Vector3 = Basis(Vector3.UP, left_yaw).x.normalized()
		var right_axis: Vector3 = Basis(Vector3.UP, right_yaw).x.normalized()
		left_center = left_hinge + left_axis * (leaf_width_m * 0.5) + clearance
		right_center = right_hinge - right_axis * (leaf_width_m * 0.5) + clearance

	left_leaf.visible = true
	right_leaf.visible = true
	left_leaf.position = left_center
	right_leaf.position = right_center
	left_leaf.rotation = Vector3(0.0, left_yaw, 0.0)
	right_leaf.rotation = Vector3(0.0, right_yaw, 0.0)
	var glass_color: Color = window_glass_closed_color.lerp(window_glass_open_color, clampf(open_amount, 0.0, 1.0))
	_set_window_leaf_glass_color(left_leaf, glass_color)
	_set_window_leaf_glass_color(right_leaf, glass_color)


func _pick_window_leaf_yaw(
	base_yaw: float,
	angle: float,
	hinge: Vector3,
	leaf_width_m: float,
	closed_center: Vector3,
	outward: Vector3,
	extends_positive_axis: bool
) -> float:
	var yaw_a: float = base_yaw + angle
	var yaw_b: float = base_yaw - angle
	var score_a: float = _window_leaf_outward_score(yaw_a, hinge, leaf_width_m, closed_center, outward, extends_positive_axis)
	var score_b: float = _window_leaf_outward_score(yaw_b, hinge, leaf_width_m, closed_center, outward, extends_positive_axis)
	return yaw_a if score_a >= score_b else yaw_b


func _window_leaf_outward_score(
	yaw: float,
	hinge: Vector3,
	leaf_width_m: float,
	closed_center: Vector3,
	outward: Vector3,
	extends_positive_axis: bool
) -> float:
	var axis: Vector3 = Basis(Vector3.UP, yaw).x.normalized()
	var signed_half_width: float = leaf_width_m * 0.5 if extends_positive_axis else -leaf_width_m * 0.5
	var candidate_center: Vector3 = hinge + axis * signed_half_width
	return (candidate_center - closed_center).dot(outward)


func _cycle_stance() -> void:
	_stance = (_stance + 1) % 3
	_apply_stance(false)


func _apply_stance(immediate: bool) -> void:
	var h: float = _current_height()
	if _capsule != null:
		_capsule.height = h
	_capsule.radius = minf(0.24, h * 0.45)
	if _collision_shape != null:
		_collision_shape.position.y = h * 0.5
	if _camera != null:
		var target_y: float = maxf(0.20, h - 0.08)
		if immediate:
			_camera.position.y = target_y
		else:
			_camera.position.y = target_y


func _current_height() -> float:
	match _stance:
		STANCE_CROUCH:
			return crouch_height_m
		STANCE_PRONE:
			return prone_height_m
		_:
			return person_height_m


func _current_speed() -> float:
	match _stance:
		STANCE_CROUCH:
			return crouch_speed_m_s
		STANCE_PRONE:
			return prone_speed_m_s
		_:
			return stand_speed_m_s


func _find_nearest_opening() -> int:
	var best_index: int = -1
	var best_dist: float = interaction_range_m
	var player_xz := Vector2(global_position.x, global_position.z)
	for index in _opening_nodes.keys():
		var op: OpeningModel = building.get_opening_at(int(index))
		if op == null:
			continue
		var info: Dictionary = Dictionary(_opening_nodes[index]).get("info", {})
		var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
		var dist: float = player_xz.distance_to(Vector2(center.x, center.z))
		if dist < best_dist:
			best_dist = dist
			best_index = int(index)
	return best_index


func _update_opening_panel(index: int) -> void:
	if not _opening_nodes.has(index) or building == null:
		return
	var op: OpeningModel = building.get_opening_at(index)
	if op == null:
		return
	var data: Dictionary = _opening_nodes[index]
	var body := data.get("body") as StaticBody3D
	var mesh := data.get("mesh") as MeshInstance3D
	var shape := data.get("shape") as CollisionShape3D
	var asset := data.get("asset") as Node3D
	var window_leaf_left := data.get("window_leaf_left") as Node3D
	var window_leaf_right := data.get("window_leaf_right") as Node3D
	var light := data.get("light") as OmniLight3D
	var info: Dictionary = data.get("info", {})
	if body == null or mesh == null or shape == null or info.is_empty():
		return

	var is_door: bool = op.type == OpeningModel.Type.DOOR
	var is_window: bool = op.type == OpeningModel.Type.WINDOW
	var open_amount: float = clampf(op.open_fraction, 0.0, 1.0)
	var width_m: float = float(info.get("width_m", 0.8))
	var height_m: float = float(info.get("height_m", 2.0))
	var sill_m: float = float(info.get("sill_m", 0.0))
	var panel_thickness: float = closed_door_thickness_m if is_door else 0.045
	var size := Vector3(width_m, height_m, panel_thickness)

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	center.y = sill_m + height_m * 0.5
	var visual_center: Vector3 = center
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var base_yaw: float = atan2(-tangent.z, tangent.x)
	var visual_yaw: float = base_yaw
	if is_door:
		visual_center += normal * opening_panel_clearance_m
	elif is_window:
		visual_center -= normal * opening_panel_clearance_m

	if is_door and open_amount > 0.01:
		var swing_sign: float = -1.0 if tangent.cross(normal).y < 0.0 else 1.0
		visual_yaw = base_yaw + deg_to_rad(82.0) * open_amount * swing_sign
		var hinge: Vector3 = center - tangent * width_m * 0.5
		var rotated_tangent: Vector3 = Basis(Vector3.UP, visual_yaw).x.normalized()
		visual_center = hinge + rotated_tangent * width_m * 0.5 + normal * opening_panel_clearance_m
	elif is_window and window_leaf_left != null and window_leaf_right != null:
		_update_window_leaf_pair(
			window_leaf_left,
			window_leaf_right,
			center,
			tangent,
			normal,
			base_yaw,
			width_m,
			height_m,
			open_amount
		)
		body.position = center - normal * opening_panel_clearance_m
		body.rotation = Vector3(0.0, base_yaw, 0.0)
		var window_box_mesh := mesh.mesh as BoxMesh
		if window_box_mesh != null:
			window_box_mesh.size = size
		mesh.visible = false
		var window_box_shape := shape.shape as BoxShape3D
		if window_box_shape != null:
			window_box_shape.size = size
		shape.position = Vector3.ZERO
		shape.disabled = (not window_collision_when_closed) or open_amount > 0.05
		if light != null:
			var window_area_factor: float = clampf(width_m * height_m / 2.2, 0.35, 1.55)
			light.light_color = _effective_window_light_color()
			light.light_energy = _effective_window_light_energy() * window_area_factor * lerpf(0.45, 1.0, open_amount)
			light.omni_range = window_light_range_m * lerpf(0.72, 1.08, open_amount)
		return

	body.position = visual_center
	body.rotation = Vector3(0.0, visual_yaw, 0.0)
	if asset != null:
		asset.position = Vector3.ZERO
		asset.rotation = Vector3.ZERO
		asset.scale = size
	var box_mesh := mesh.mesh as BoxMesh
	if box_mesh != null:
		box_mesh.size = size
	mesh.position = Vector3.ZERO
	if asset == null:
		mesh.material_override = _opening_material(op)
	var box_shape := shape.shape as BoxShape3D
	if box_shape != null:
		box_shape.size = size
	shape.position = Vector3.ZERO
	shape.disabled = (not is_door and not (is_window and window_collision_when_closed)) or open_amount > 0.05
	if light != null:
		var area_factor: float = clampf(width_m * height_m / 2.2, 0.35, 1.55)
		if op.type == OpeningModel.Type.WINDOW:
			light.light_color = _effective_window_light_color()
			light.light_energy = _effective_window_light_energy() * area_factor * lerpf(0.45, 1.0, open_amount)
			light.omni_range = window_light_range_m * lerpf(0.72, 1.08, open_amount)
		else:
			light.light_color = _effective_landing_light_color()
			light.light_energy = _effective_landing_light_energy() * area_factor * lerpf(landing_light_closed_ratio, 1.0, open_amount)
			light.omni_range = landing_light_range_m * lerpf(0.78, 1.12, open_amount)


func _opening_material(op: OpeningModel) -> StandardMaterial3D:
	if op.type == OpeningModel.Type.DOOR:
		if op.open_fraction > 0.5:
			return _mat(Color(0.50, 0.34, 0.18, 0.76), true, Color(0.0, 0.0, 0.0, 0.0), 0.0, 5201)
		return _mat(Color(0.38, 0.24, 0.13, 1.0), false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 5202)
	if op.open_fraction > 0.5:
		return _mat(window_glass_open_color, true)
	return _mat(window_glass_closed_color, true)


func _opening_specs_for_side(rect: Rect2, room_id: int, side: String, room_height_m: float) -> Array:
	var specs: Array = []
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null:
			continue
		if op.a != room_id and op.b != room_id:
			continue
		var info: Dictionary = _opening_info(index)
		if info.is_empty():
			continue
		if String(info.get("side_for_%d" % room_id, "")) != side:
			continue
		var axis_center: float = float(info.get("axis_center", 0.0))
		var width_m: float = float(info.get("width_m", 0.8))
		var side_start: float = rect.position.x if side == "top" or side == "bottom" else rect.position.y
		var bottom_m: float = 0.0
		var top_m: float = minf(room_height_m, float(info.get("height_m", 2.0)))
		if op.type == OpeningModel.Type.WINDOW:
			bottom_m = clampf(float(info.get("sill_m", op.sill_m)), 0.0, room_height_m)
			top_m = clampf(bottom_m + float(info.get("height_m", op.height_m)), 0.0, room_height_m)
		specs.append({
			"start": axis_center - side_start - width_m * 0.5,
			"end": axis_center - side_start + width_m * 0.5,
			"bottom_m": bottom_m,
			"top_m": top_m
		})
	return specs


func _opening_info(index: int) -> Dictionary:
	var op: OpeningModel = building.get_opening_at(index)
	if op == null:
		return {}
	var rects: Dictionary = building.get_room_rects_m()
	var room_id: int = op.a if op.a != OUTSIDE_ID else op.b
	if not rects.has(room_id):
		return {}
	var rect: Rect2 = Rect2(rects[room_id])
	var height_m: float = op.height_m
	var width_m: float = op.width_m
	var sill_m: float = op.sill_m
	if op.is_exterior_opening():
		var side: String = op.wall_side.to_lower()
		if side == "":
			side = "top"
		return _opening_info_on_side(rect, room_id, side, width_m, height_m, sill_m, op.offset_m, true)

	var other_id: int = op.b if op.a == room_id else op.a
	if not rects.has(other_id):
		return {}
	var other: Rect2 = Rect2(rects[other_id])
	var shared: Dictionary = _shared_side_data(rect, other)
	var side_for_room: String = String(shared.get("side", ""))
	if side_for_room == "":
		return {}
	var info: Dictionary = _opening_info_on_side(
		rect,
		room_id,
		side_for_room,
		width_m,
		height_m,
		sill_m,
		op.offset_m,
		false,
		float(shared.get("overlap_start", 0.0)),
		float(shared.get("overlap_end", 0.0))
	)
	if info.is_empty():
		return {}
	info["side_for_%d" % other_id] = _opposite_side(side_for_room)
	return info


func _opening_info_on_side(
	rect: Rect2,
	room_id: int,
	side: String,
	width_m: float,
	height_m: float,
	sill_m: float,
	offset: float,
	exterior: bool,
	segment_start: float = -1.0,
	segment_end: float = -1.0
) -> Dictionary:
	var horizontal: bool = side == "top" or side == "bottom"
	var side_length: float = rect.size.x if horizontal else rect.size.y
	var side_axis_start: float = rect.position.x if horizontal else rect.position.y
	var side_axis_end: float = side_axis_start + side_length
	var allowed_start: float = side_axis_start
	var allowed_end: float = side_axis_end
	if segment_end > segment_start:
		allowed_start = maxf(side_axis_start, segment_start)
		allowed_end = minf(side_axis_end, segment_end)
	var allowed_length: float = allowed_end - allowed_start
	if allowed_length <= 0.05:
		return {}

	var center_axis: float
	if offset <= 1.0:
		center_axis = allowed_start + allowed_length * offset
	else:
		center_axis = side_axis_start + offset
	width_m = minf(width_m, maxf(0.20, allowed_length))
	center_axis = clampf(center_axis, allowed_start + width_m * 0.5, allowed_end - width_m * 0.5)

	var x: float = center_axis if horizontal else (rect.position.x if side == "left" else rect.position.x + rect.size.x)
	var z: float = (rect.position.y if side == "top" else rect.position.y + rect.size.y) if horizontal else center_axis
	var center: Vector3 = _to_world(Vector3(x, sill_m + height_m * 0.5, z))
	var tangent: Vector3 = Vector3.RIGHT if horizontal else Vector3.FORWARD
	var normal: Vector3 = _inside_normal_for_side(side)
	return {
		"center": center,
		"axis_center": center_axis,
		"width_m": width_m,
		"height_m": height_m,
		"sill_m": sill_m,
		"orientation": "horizontal" if horizontal else "vertical",
		"side_for_%d" % room_id: side,
		"tangent": tangent,
		"normal": normal,
		"exterior": exterior
	}


func _shared_side(a: Rect2, b: Rect2) -> String:
	return String(_shared_side_data(a, b).get("side", ""))


func _shared_side_data(a: Rect2, b: Rect2) -> Dictionary:
	var eps: float = 0.01
	var min_overlap_m: float = 0.05
	var overlap_start: float
	var overlap_end: float
	if absf((a.position.x + a.size.x) - b.position.x) < eps:
		overlap_start = maxf(a.position.y, b.position.y)
		overlap_end = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if overlap_end - overlap_start > min_overlap_m:
			return {"side": "right", "overlap_start": overlap_start, "overlap_end": overlap_end}
	if absf(a.position.x - (b.position.x + b.size.x)) < eps:
		overlap_start = maxf(a.position.y, b.position.y)
		overlap_end = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if overlap_end - overlap_start > min_overlap_m:
			return {"side": "left", "overlap_start": overlap_start, "overlap_end": overlap_end}
	if absf((a.position.y + a.size.y) - b.position.y) < eps:
		overlap_start = maxf(a.position.x, b.position.x)
		overlap_end = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if overlap_end - overlap_start > min_overlap_m:
			return {"side": "bottom", "overlap_start": overlap_start, "overlap_end": overlap_end}
	if absf(a.position.y - (b.position.y + b.size.y)) < eps:
		overlap_start = maxf(a.position.x, b.position.x)
		overlap_end = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if overlap_end - overlap_start > min_overlap_m:
			return {"side": "top", "overlap_start": overlap_start, "overlap_end": overlap_end}
	return {}


func _opposite_side(side: String) -> String:
	match side:
		"top":
			return "bottom"
		"bottom":
			return "top"
		"left":
			return "right"
		"right":
			return "left"
		_:
			return ""


func _place_at_entry() -> void:
	if building == null:
		return
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or not op.is_exterior_opening() or op.type != OpeningModel.Type.DOOR:
			continue
		var info: Dictionary = _opening_info(index)
		if info.is_empty():
			continue
		var side: String = ""
		for key in info.keys():
			var ks: String = String(key)
			if ks.begins_with("side_for_"):
				side = String(info[key])
				break
		var inward: Vector3 = _inside_normal_for_side(side)
		var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
		global_position = center + inward * 0.75
		global_position.y = 0.05
		_yaw = atan2(-inward.x, -inward.z)
		_pitch = 0.0
		rotation.y = _yaw
		if _camera != null:
			_camera.rotation.x = _pitch
		return

	var rects: Dictionary = building.get_room_rects_m()
	if not rects.is_empty():
		var first_id: int = int(rects.keys()[0])
		var rect: Rect2 = Rect2(rects[first_id])
		global_position = _to_world(Vector3(rect.position.x + rect.size.x * 0.5, 0.05, rect.position.y + rect.size.y * 0.5))
		_pitch = 0.0
		if _camera != null:
			_camera.rotation.x = _pitch


func _inside_normal_for_side(side: String) -> Vector3:
	match side:
		"top":
			return Vector3(0.0, 0.0, 1.0)
		"bottom":
			return Vector3(0.0, 0.0, -1.0)
		"left":
			return Vector3.RIGHT
		"right":
			return Vector3.LEFT
		_:
			return Vector3(0.0, 0.0, 1.0)


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


func _to_world(pos_m: Vector3) -> Vector3:
	return Vector3(pos_m.x + _origin_offset_m.x, pos_m.y, pos_m.z + _origin_offset_m.y)


func _floor_material_for_room(room_id: int) -> StandardMaterial3D:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var kind: String = room.kind.to_lower() if room != null else ""
	var color := Color(0.30, 0.29, 0.26, 1.0)
	if kind.contains("bano") or kind.contains("baño") or kind.contains("bath"):
		color = Color(0.48, 0.50, 0.48, 1.0)
	elif kind.contains("cocina") or kind.contains("kitchen"):
		color = Color(0.42, 0.39, 0.34, 1.0)
	elif kind.contains("pasillo") or kind.contains("hall") or kind.contains("corridor"):
		color = Color(0.34, 0.33, 0.30, 1.0)
	elif kind.contains("dorm") or kind.contains("bed"):
		color = Color(0.35, 0.28, 0.22, 1.0)
	return _mat(color, false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 1100 + room_id)


func _wall_material_for_room(room_id: int) -> StandardMaterial3D:
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var kind: String = room.kind.to_lower() if room != null else ""
	var color := Color(0.80, 0.80, 0.75, 1.0)
	if kind.contains("cocina") or kind.contains("kitchen"):
		color = Color(0.76, 0.77, 0.72, 1.0)
	elif kind.contains("bano") or kind.contains("baño") or kind.contains("bath"):
		color = Color(0.72, 0.76, 0.76, 1.0)
	elif kind.contains("pasillo") or kind.contains("hall") or kind.contains("corridor"):
		color = Color(0.78, 0.75, 0.68, 1.0)
	return _mat(color, false)


func _ceiling_material_for_room(room_id: int) -> StandardMaterial3D:
	return _mat(Color(0.76, 0.76, 0.71, 1.0), false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 3100 + room_id)


func _mat(
	color: Color,
	transparent: bool,
	emission_color: Color = Color(0.0, 0.0, 0.0, 0.0),
	emission_energy: float = 0.0,
	noise_seed: int = -1
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	material.metallic = 0.0
	if use_procedural_surface_noise and noise_seed >= 0 and not transparent:
		material.albedo_texture = _noise_texture(noise_seed)
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_energy
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _noise_texture(seed: int) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = material_noise_frequency
	var texture := NoiseTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.noise = noise
	return texture
