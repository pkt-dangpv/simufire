extends CharacterBody3D
class_name FirstPersonController

signal exit_requested
signal opening_changed

const OUTSIDE_ID: int = -1
const STANCE_STAND: int = 0
const STANCE_CROUCH: int = 1
const STANCE_PRONE: int = 2

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
@export var window_light_energy: float = 1.05
@export var window_light_range_m: float = 5.8

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
var _nearest_opening_index: int = -1
var _state: Dictionary = {}
var _visibility_overlay: ColorRect = null
var _current_room_id: int = -1


func _ready() -> void:
	_create_player_nodes()
	set_active(false)


func setup(next_building: BuildingModel) -> void:
	building = next_building
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
	_rebuild_world()
	_place_at_entry()


func set_state(next_state: Dictionary) -> void:
	_state = next_state
	_sync_opening_panels()
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
	var host := get_parent() as Node3D
	if host == null:
		host = self
	_world_root = host.get_node_or_null("FirstPersonWorld") as Node3D
	if _world_root == null:
		_world_root = Node3D.new()
		_world_root.name = "FirstPersonWorld"
		host.add_child(_world_root)
	_world_root.set_as_top_level(true)
	_world_root.global_transform = Transform3D.IDENTITY
	_world_root.visible = _active


func _rebuild_world() -> void:
	_ensure_world_root()
	if _world_root == null:
		return
	for child in _world_root.get_children():
		child.free()
	_world_root.global_transform = Transform3D.IDENTITY
	_world_root.visible = _active
	_opening_nodes.clear()

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
	_create_opening_panels()
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
		_add_box(body, "FloorMesh", Vector3(rect.size.x, floor_thickness_m, rect.size.y), center, _mat(Color(0.28, 0.27, 0.24, 1.0), false), true)


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
		_add_box(body, "CeilingMesh", Vector3(rect.size.x, ceiling_thickness_m, rect.size.y), center, _mat(Color(0.73, 0.74, 0.70, 1.0), false), true)


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
			_create_wall_segment(rect, side, cursor, start, height_m)
		if end > start + 0.03:
			var bottom_m: float = clampf(float(opening.get("bottom_m", 0.0)), 0.0, height_m)
			var top_m: float = clampf(float(opening.get("top_m", height_m)), 0.0, height_m)
			if bottom_m > 0.03:
				_create_wall_segment_height(rect, side, start, end, 0.0, bottom_m)
			if top_m < height_m - 0.03:
				_create_wall_segment_height(rect, side, start, end, top_m, height_m)
		cursor = maxf(cursor, end)
	if cursor < length - 0.03:
		_create_wall_segment(rect, side, cursor, length, height_m)


func _create_wall_segment(rect: Rect2, side: String, start: float, end: float, height_m: float) -> void:
	_create_wall_segment_height(rect, side, start, end, 0.0, height_m)


func _create_wall_segment_height(rect: Rect2, side: String, start: float, end: float, y_min_m: float, y_max_m: float) -> void:
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
	_add_box(body, "WallMesh", size, center, _mat(Color(0.82, 0.83, 0.79, 1.0), false), true)


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
		_opening_nodes[index] = {
			"body": body,
			"mesh": mesh,
			"shape": shape,
			"info": info,
			"light": _create_opening_light(op, info)
		}
		_update_opening_panel(index)


func _create_opening_light(op: OpeningModel, info: Dictionary) -> OmniLight3D:
	if op == null or not op.is_exterior_opening():
		return null
	if op.type != OpeningModel.Type.WINDOW and op.type != OpeningModel.Type.DOOR:
		return null
	var light := OmniLight3D.new()
	light.name = "ExteriorLight"
	light.light_color = Color(1.0, 0.93, 0.78, 1.0)
	light.light_energy = 0.0
	light.omni_range = window_light_range_m
	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var inward: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	light.position = center + inward * 0.42
	light.position.y = maxf(1.2, center.y)
	_world_root.add_child(light)
	return light


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
	var immersion: float = clampf((eye_height_m + 0.25 - smoke_layer_m) / 0.65, 0.0, 1.0)
	var alpha_from_visibility: float = clampf((8.0 - visibility_m) / 8.0, 0.0, 0.86)
	var alpha_from_smoke: float = clampf(smoke_kg / 2.2, 0.0, 0.42)
	var heat_tint: float = clampf((upper_temp_c - 80.0) / 420.0, 0.0, 1.0)
	var alpha: float = maxf(alpha_from_visibility, alpha_from_smoke) * immersion
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
	var light := data.get("light") as OmniLight3D
	var info: Dictionary = data.get("info", {})
	if body == null or mesh == null or shape == null or info.is_empty():
		return

	var is_door: bool = op.type == OpeningModel.Type.DOOR
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
	if is_door and open_amount > 0.01:
		var swing_sign: float = -1.0 if tangent.cross(normal).y < 0.0 else 1.0
		visual_yaw = base_yaw + deg_to_rad(82.0) * open_amount * swing_sign
		var hinge: Vector3 = center - tangent * width_m * 0.5
		var rotated_tangent: Vector3 = Basis(Vector3.UP, visual_yaw).x.normalized()
		visual_center = hinge + rotated_tangent * width_m * 0.5

	body.position = visual_center
	body.rotation = Vector3(0.0, visual_yaw, 0.0)
	var box_mesh := mesh.mesh as BoxMesh
	if box_mesh != null:
		box_mesh.size = size
	mesh.position = Vector3.ZERO
	mesh.material_override = _opening_material(op)
	var box_shape := shape.shape as BoxShape3D
	if box_shape != null:
		box_shape.size = size
	shape.position = Vector3.ZERO
	shape.disabled = (not is_door) or open_amount > 0.05
	if light != null:
		var area_factor: float = clampf(width_m * height_m / 2.2, 0.35, 1.55)
		if op.type == OpeningModel.Type.WINDOW:
			light.light_energy = window_light_energy * area_factor * lerpf(0.55, 1.0, open_amount)
			light.omni_range = window_light_range_m * lerpf(0.80, 1.10, open_amount)
		else:
			light.light_energy = window_light_energy * area_factor * clampf(open_amount, 0.0, 1.0) * 0.80
			light.omni_range = window_light_range_m * 0.90


func _opening_material(op: OpeningModel) -> StandardMaterial3D:
	if op.type == OpeningModel.Type.DOOR:
		if op.open_fraction > 0.5:
			return _mat(Color(0.26, 0.78, 0.35, 0.55), true)
		return _mat(Color(0.42, 0.28, 0.16, 1.0), false)
	if op.open_fraction > 0.5:
		return _mat(Color(0.22, 0.58, 1.0, 0.32), true)
	return _mat(Color(0.20, 0.46, 0.78, 0.72), true)


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


func _mat(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	material.metallic = 0.0
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
