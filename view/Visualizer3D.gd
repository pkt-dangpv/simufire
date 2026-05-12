extends Node3D
class_name Visualizer3D

signal room_clicked(room_id: int)

## Basic editable 3D view for the same BuildingModel / SimulationEngine state.
## The scene owns the camera, lights, and container nodes; this script only
## rebuilds generated room meshes from the current building template.

const SMOKE_TEXTURE_LIGHT := preload("res://assets/smoke/02_humo_superior_ligero_spritesheet_128.png")
const SMOKE_TEXTURE_MEDIUM := preload("res://assets/smoke/03_humo_superior_medio_spritesheet_128.png")
const SMOKE_TEXTURE_DENSE := preload("res://assets/smoke/04_humo_superior_denso_spritesheet_128.png")
const SMOKE_VOLUME_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

uniform vec4 smoke_color : source_color = vec4(0.18, 0.19, 0.20, 0.34);
uniform float density = 1.0;
uniform float turbulence = 0.55;
uniform float drift_speed = 0.10;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * drift_speed;
	float n1 = noise(uv * 3.5 + vec2(t, -t * 0.7));
	float n2 = noise(uv * 8.0 + vec2(-t * 1.6, t * 1.1));
	float n = mix(n1, n2, turbulence);
	float soft_edge = smoothstep(0.00, 0.10, uv.y) * (1.0 - smoothstep(0.94, 1.0, uv.y));
	float alpha = smoke_color.a * density * mix(0.42, 1.05, n) * max(0.42, soft_edge);
	ALBEDO = smoke_color.rgb * mix(0.72, 1.08, n);
	ALPHA = clamp(alpha, 0.0, smoke_color.a);
}
"""
const FLAME_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 flame_color : source_color = vec4(1.0, 0.32, 0.04, 0.85);
uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.26, 1.0);
uniform float emission_energy = 1.35;
uniform float flicker_speed = 2.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * flicker_speed;
	float n = noise(vec2(uv.x * 3.0, uv.y * 5.5 - t));
	float center = abs(uv.x - 0.5) * 2.0;
	float width = mix(0.58, 0.04, pow(uv.y, 0.72));
	float lick = sin((uv.y * 8.0 - t * 3.1) + n * 2.4) * 0.08;
	float body = 1.0 - smoothstep(width, width + 0.20, center + lick);
	float base = smoothstep(0.0, 0.10, uv.y);
	float tip = 1.0 - smoothstep(0.72, 1.0, uv.y + n * 0.09);
	float alpha = clamp(body * base * tip * flame_color.a, 0.0, 1.0);
	vec3 col = mix(flame_color.rgb, core_color.rgb, clamp((1.0 - center) * (1.0 - uv.y * 0.45), 0.0, 1.0));
	ALBEDO = col;
	EMISSION = col * emission_energy;
	ALPHA = alpha;
}
"""
const FIRE_CAP_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 cap_color : source_color = vec4(1.0, 0.34, 0.05, 0.42);
uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.22, 0.70);
uniform float emission_energy = 0.95;
uniform float flicker_speed = 1.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float r = length(centered);
	float t = TIME * flicker_speed;
	float n = noise(UV * 7.0 + vec2(t, -t * 0.63));
	float broken_edge = 1.0 - smoothstep(0.58 + n * 0.18, 1.04, r);
	float tongues = smoothstep(0.34, 0.95, n) * broken_edge;
	float alpha = cap_color.a * broken_edge * mix(0.26, 1.0, tongues);
	vec3 col = mix(cap_color.rgb, core_color.rgb, tongues * (1.0 - smoothstep(0.0, 0.95, r)));
	ALBEDO = col;
	EMISSION = col * emission_energy;
	ALPHA = clamp(alpha, 0.0, cap_color.a);
}
"""
const SMOKE_CEILING_MASK_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

void fragment() {
	ALBEDO = vec3(0.55, 0.57, 0.58);
	ALPHA = 0.075;
}
"""

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
@export var fuel_object_3d_height_m: float = 0.34
@export var smoke_puff_count: int = 28
@export var show_smoke_geometry_in_first_person: bool = true
@export var show_smoke_puffs_in_first_person: bool = false
@export var show_smoke_ceiling_masks: bool = true

@export_group("Colors")
@export var floor_color: Color = Color(0.18, 0.18, 0.17, 1.0)
@export var hot_floor_color: Color = Color(0.46, 0.30, 0.18, 1.0)
@export var wall_color: Color = Color(0.84, 0.86, 0.82, 0.42)
@export var hot_wall_color: Color = Color(1.00, 0.42, 0.12, 0.68)
@export var wall_outline_color: Color = Color(0.95, 0.95, 0.90, 0.72)
@export var smoke_color: Color = Color(0.26, 0.27, 0.30, 0.28)
@export var smoke_puff_color: Color = Color(0.34, 0.35, 0.38, 0.30)
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


func _unhandled_input(event: InputEvent) -> void:
	if not _input_active or not enable_mouse_camera or not is_visible_in_tree():
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
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_screen_point_over_model(mb.position):
					var rid: int = _get_room_id_at_screen_pos(mb.position)
					if rid >= 0:
						_selected_room_id = rid
						room_clicked.emit(rid)
						get_viewport().set_input_as_handled()
					elif _selected_room_id >= 0:
						_selected_room_id = -1
						room_clicked.emit(-1)
						get_viewport().set_input_as_handled()
				else:
					if _selected_room_id >= 0:
						_selected_room_id = -1
						room_clicked.emit(-1)
						get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and _is_screen_point_over_model(mb.position):
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

	for index in range(building.get_opening_count()):
		_create_opening(index)

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

	var smoke := _create_box("SmokeVolume", Vector3.ONE, _make_smoke_volume_material())
	smoke.visible = false
	_atmosphere_root.add_child(smoke)

	var smoke_edge := _create_box("SmokeLayerEdge_%02d" % room_id, Vector3.ONE, _make_material(smoke_layer_edge_color, true))
	smoke_edge.visible = false
	_atmosphere_root.add_child(smoke_edge)

	var smoke_puffs_root := Node3D.new()
	smoke_puffs_root.name = "SmokePuffs_%02d" % room_id
	smoke_puffs_root.visible = false
	_atmosphere_root.add_child(smoke_puffs_root)
	var smoke_puffs: Array[Sprite3D] = []
	for puff_i in range(maxi(0, smoke_puff_count)):
		var puff := _create_smoke_puff_sprite("SmokeWisp_%02d_%02d" % [room_id, puff_i])
		puff.set_meta("seed", float(room_id * 23 + puff_i * 17 + 3))
		smoke_puffs_root.add_child(puff)
		smoke_puffs.append(puff)

	var smoke_ceiling_mask := _create_smoke_ceiling_mask("SmokeCeilingMask_%02d" % room_id)
	smoke_ceiling_mask.visible = show_smoke_ceiling_masks
	_atmosphere_root.add_child(smoke_ceiling_mask)

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
	var fire_tongues: Array[MeshInstance3D] = []
	for tongue_i in range(5):
		var tongue_color: Color = fire_color.lerp(fire_core_color, 0.18 + float(tongue_i) * 0.08)
		var tongue := _create_flame_mesh("Tongue_%02d" % tongue_i, tongue_color)
		tongue.set_meta("seed", float(room_id * 19 + tongue_i * 11 + 5))
		fire_root.add_child(tongue)
		fire_tongues.append(tongue)
	var fire_cap := _create_fire_ceiling_cap_mesh("CeilingCap", fire_ceiling_cap_color)
	fire_cap.visible = false
	fire_root.add_child(fire_cap)
	var fire_core := _create_flame_mesh("Core", fire_core_color)
	fire_root.add_child(fire_core)
	var fire_light := OmniLight3D.new()
	fire_light.name = "FireLight"
	fire_light.light_color = Color(1.0, 0.42, 0.12, 1.0)
	fire_light.light_energy = 0.0
	fire_light.omni_range = fire_light_range_min_m
	fire_light.position = Vector3(0.0, 0.9, 0.0)
	fire_root.add_child(fire_light)

	var label := Label3D.new()
	label.name = "Label_%02d" % room_id
	label.text = _get_room_label(room_id)
	label.modulate = label_color
	label.font_size = 54
	label.pixel_size = 0.014
	label.outline_size = 6
	label.no_depth_test = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = 3  # TextServer.AUTOWRAP_WORD_ARBITRARY
	label.width = (minf(rect_m.size.x, rect_m.size.y) * 0.82) / 0.014
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = _room_center(rect_m, floor_thickness_m + 0.012)
	label.visible = show_room_labels
	_labels_root.add_child(label)

	var fuel_objects_root := Node3D.new()
	fuel_objects_root.name = "FuelObjects_%02d" % room_id
	_atmosphere_root.add_child(fuel_objects_root)

	_room_items[room_id] = {
		"rect": rect_m,
		"height_m": height_m,
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
		"fuel_obj_nodes": {}
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

	# Cortina de humo: para puertas interiores entre dos salas, añadir un quad
	# que rellena el vano con el humo promedio de ambas salas, eliminando el
	# salto visual de capa entre habitaciones con distinto smoke_bottom_m.
	if op.type == OpeningModel.Type.DOOR and not op.is_exterior_opening() \
			and op.a != BuildingModel.OUTSIDE_ID and op.b != BuildingModel.OUTSIDE_ID:
		var curtain := _create_box(
			"SmokeCurtain_%02d" % index,
			Vector3(pose["size"]) * meters_to_units,
			_make_material(Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0), true)
		)
		curtain.position = marker.position
		curtain.visible = false
		_atmosphere_root.add_child(curtain)
		_opening_items[index]["smoke_curtain"] = curtain
		_opening_items[index]["curtain_pose"] = pose


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
	var smoke_layer_m: float = clampf(float(rs.get("smoke_display_layer_m", rs.get("smoke_layer_m", rs.get("h_layer_m", height_m)))), 0.0, height_m)
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
	_update_fire_visual(item, rect, height_m, hrr_kw, rs)

	if label != null:
		label.visible = show_room_labels
		label.text = _get_room_label(room_id, rs)

	_update_room_fuel_objects_3d(item, rs, rect)


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
	if ceiling_mask != null:
		ceiling_mask.visible = show_smoke_volume and show_smoke_ceiling_masks and current_depth_m > smoke_min_visible_depth_m
		if ceiling_mask.visible:
			var ceiling_mesh := ceiling_mask.mesh as BoxMesh
			if ceiling_mesh != null:
				ceiling_mesh.size = Vector3(
					maxf(0.05, rect.size.x - room_inset_m * 2.0),
					0.018,
					maxf(0.05, rect.size.y - room_inset_m * 2.0)
				) * meters_to_units
			ceiling_mask.position = _room_center(rect, height_m + 0.004)

	var alpha: float = clampf(
		smoke_color.a
			+ smoke_kg / maxf(0.01, smoke_reference_kg) * 0.28
			+ hrr_smoke_t * smoke_hrr_alpha_boost,
		0.10,
		0.58
	)
	var smoke_mat := node.material_override as ShaderMaterial
	if smoke_mat != null:
		smoke_mat.set_shader_parameter("smoke_color", Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha * 0.78))
		smoke_mat.set_shader_parameter("density", clampf(0.55 + alpha * 1.25, 0.45, 1.35))
		smoke_mat.set_shader_parameter("turbulence", clampf(0.42 + hrr_smoke_t * 0.38, 0.42, 0.86))
		smoke_mat.set_shader_parameter("drift_speed", 0.055 + hrr_smoke_t * 0.16)
	else:
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha * 0.62)

	var visual_bottom_m: float = height_m - current_depth_m
	item["smoke_bottom_m"] = visual_bottom_m
	item["smoke_alpha"] = alpha

	if smoke_geometry_visible:
		var mesh := node.mesh as BoxMesh
		if mesh != null:
			mesh.size = Vector3(
				maxf(0.05, rect.size.x - room_inset_m * 2.0),
				current_depth_m,
				maxf(0.05, rect.size.y - room_inset_m * 2.0)
			) * meters_to_units
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

	var puffs_root := item.get("smoke_puffs_root") as Node3D
	if puffs_root != null:
		puffs_root.visible = smoke_puffs_visible


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
	var anchor_pos: Vector3 = _room_center(rect, 0.0)
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
	anchor_y_m = _fire_base_height_for_fuel_object(best_obj, kind_name)
	anchor_radius_m = clampf(maxf(minf(size_m.x, size_m.y) * 0.34, sqrt(maxf(0.01, size_m.x * size_m.y)) * 0.20), fire_base_radius_m, fire_max_radius_m)
	anchor_pos = _to_world(Vector3(
		rect.position.x + pos_m.x + size_m.x * 0.5,
		anchor_y_m,
		rect.position.y + pos_m.y + size_m.y * 0.5
	))
	return {"position": anchor_pos, "base_y_m": anchor_y_m, "radius_m": anchor_radius_m}


func _fire_base_height_for_fuel_object(obj: Dictionary, kind_name: String) -> float:
	var elevation_m: float = maxf(0.0, float(obj.get("elevation_m", 0.0)))
	match kind_name:
		"sofa":
			return maxf(elevation_m, 0.62)
		"bed":
			return maxf(elevation_m, 0.60)
		"table":
			return maxf(elevation_m, 0.78)
		"wardrobe":
			return maxf(elevation_m, 1.45)
		"storage", "kitchen_unit":
			return maxf(elevation_m, 0.86)
		"curtain":
			return maxf(elevation_m, 1.15)
		"rug", "pool":
			return maxf(elevation_m, 0.06)
		"textile_pile", "containers", "clutter":
			return maxf(elevation_m, 0.24)
		_:
			return maxf(elevation_m, 0.30)


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
	var puffs_root := item.get("smoke_puffs_root") as Node3D
	if puffs_root == null or not puffs_root.visible:
		return
	var puffs: Array = item.get("smoke_puffs", [])
	if puffs.is_empty():
		return

	var rect := Rect2(item.get("rect", Rect2()))
	var depth_m: float = float(item.get("smoke_visual_depth_m", 0.0))
	var bottom_m: float = float(item.get("smoke_bottom_m", float(item.get("height_m", default_room_height_m))))
	var height_m: float = float(item.get("height_m", default_room_height_m))
	var alpha: float = float(item.get("smoke_alpha", smoke_puff_color.a))
	if depth_m <= smoke_min_visible_depth_m:
		puffs_root.visible = false
		return

	var usable_w: float = maxf(0.08, rect.size.x - room_inset_m * 2.0)
	var usable_d: float = maxf(0.08, rect.size.y - room_inset_m * 2.0)
	var puff_base: float = clampf(minf(rect.size.x, rect.size.y) * 0.18, 0.26, 0.72)
	var smoke_texture: Texture2D = _smoke_texture_for_alpha(alpha)
	for i in range(puffs.size()):
		var puff := puffs[i] as Sprite3D
		if puff == null:
			continue
		var seed: float = float(puff.get_meta("seed", i))
		var phase: float = _fire_phase * (0.34 + fposmod(seed, 5.0) * 0.035) + seed
		var x_frac: float = fposmod(seed * 0.618 + sin(phase) * 0.070, 1.0)
		var z_frac: float = fposmod(seed * 0.382 + cos(phase * 0.83) * 0.070, 1.0)
		var y_frac: float = 0.12 + fposmod(seed * 0.271, 0.78)
		var x_m: float = rect.position.x + room_inset_m + x_frac * usable_w
		var z_m: float = rect.position.y + room_inset_m + z_frac * usable_d
		var y_m: float = bottom_m + depth_m * y_frac + sin(phase * 1.7) * minf(depth_m * 0.055, 0.055)
		y_m = clampf(y_m, bottom_m + 0.06, height_m - 0.18)
		puff.position = _to_world(Vector3(x_m, y_m, z_m))
		var wobble: float = 1.0 + sin(phase * 1.3) * 0.10
		var sprite_scale: float = puff_base * lerpf(0.58, 1.05, fposmod(seed * 0.13, 1.0)) * wobble
		puff.scale = Vector3.ONE * sprite_scale * meters_to_units
		puff.rotation_degrees.z = sin(phase * 0.42) * 9.0 + seed * 3.0
		puff.texture = smoke_texture
		var frame_count: int = maxi(1, puff.hframes * puff.vframes)
		puff.frame = int(fposmod(floor(_fire_phase * 5.0 + seed), float(frame_count)))
		var puff_alpha: float = clampf(alpha * lerpf(0.42, 0.92, fposmod(seed * 0.47, 1.0)), 0.08, 0.62)
		puff.modulate = Color(0.72, 0.74, 0.76, puff_alpha)


func _smoke_texture_for_alpha(alpha: float) -> Texture2D:
	if alpha > 0.54:
		return SMOKE_TEXTURE_DENSE
	if alpha > 0.30:
		return SMOKE_TEXTURE_MEDIUM
	return SMOKE_TEXTURE_LIGHT


func _animate_fire_item(item: Dictionary) -> void:
	var fire_root := item.get("fire_root") as Node3D
	var fire_core := item.get("fire_core") as MeshInstance3D
	var fire_glow := item.get("fire_glow") as MeshInstance3D
	var fire_cap := item.get("fire_cap") as MeshInstance3D
	var fire_light := item.get("fire_light") as OmniLight3D
	if fire_root == null or fire_core == null or fire_glow == null:
		return

	var height_m: float = float(item.get("fire_height_m", 0.0))
	var radius_m: float = float(item.get("fire_radius_m", fire_base_radius_m))
	var room_height_m: float = float(item.get("fire_available_height_m", item.get("height_m", default_room_height_m)))
	var cap_radius_m: float = float(item.get("fire_cap_radius_m", 0.0))
	var cap_weight: float = clampf(float(item.get("fire_cap_weight", 0.0)), 0.0, 1.0)
	var phase: float = float(item.get("fire_phase", 0.0))
	var flicker: float = 1.0 \
			+ sin(_fire_phase * 8.5 + phase) * fire_flicker_strength \
			+ sin(_fire_phase * 15.0 + phase * 0.7) * fire_flicker_strength * 0.45
	var max_column_h: float = maxf(0.04, room_height_m)
	var core_h: float = minf(max_column_h, maxf(0.04, height_m * flicker))
	var glow_h: float = minf(max_column_h, maxf(0.04, height_m * 0.76 * (1.0 + (flicker - 1.0) * 0.55)))
	var core_r: float = maxf(0.03, radius_m * flicker)
	var glow_r: float = maxf(0.04, radius_m * 1.85)

	fire_core.scale = Vector3(core_r, core_h, core_r) * meters_to_units
	fire_core.position = Vector3(0.0, core_h * meters_to_units * 0.5, 0.0)
	fire_glow.scale = Vector3(glow_r, glow_h, glow_r) * meters_to_units
	fire_glow.position = Vector3(0.0, glow_h * meters_to_units * 0.38, 0.0)

	var tongues: Array = item.get("fire_tongues", [])
	for i in range(tongues.size()):
		var tongue := tongues[i] as MeshInstance3D
		if tongue == null:
			continue
		var seed: float = float(tongue.get_meta("seed", i))
		var wave: float = 1.0 + sin(_fire_phase * (7.0 + fposmod(seed, 4.0)) + seed) * fire_flicker_strength * 0.85
		var angle: float = seed * 1.97 + sin(_fire_phase * 1.8 + seed) * 0.28
		var orbit_r: float = radius_m * (0.22 + fposmod(seed * 0.17, 0.38))
		var tongue_h: float = minf(max_column_h, maxf(0.04, height_m * lerpf(0.48, 0.92, fposmod(seed * 0.29, 1.0)) * wave))
		var tongue_r: float = maxf(0.025, radius_m * lerpf(0.34, 0.68, fposmod(seed * 0.41, 1.0)))
		tongue.visible = height_m > 0.05
		tongue.position = Vector3(
			cos(angle) * orbit_r * meters_to_units,
			tongue_h * meters_to_units * 0.48,
			sin(angle) * orbit_r * meters_to_units
		)
		tongue.scale = Vector3(tongue_r, tongue_h, tongue_r * 0.72) * meters_to_units
		tongue.rotation_degrees.y = rad_to_deg(angle) + 90.0

	if fire_light != null:
		var base_energy: float = float(item.get("fire_light_energy_target", fire_light.light_energy))
		fire_light.light_energy = base_energy * clampf(0.92 + (flicker - 1.0) * 0.85, 0.65, 1.35)

	if fire_cap != null:
		fire_cap.visible = cap_weight > 0.03 and cap_radius_m > 0.03
		if fire_cap.visible:
			var cap_wave: float = 1.0 + sin(_fire_phase * 5.4 + phase) * fire_flicker_strength * 0.22
			var cap_h: float = fire_ceiling_cap_thickness_m * lerpf(0.65, 1.25, cap_weight)
			var ceiling_y_m: float = maxf(cap_h, room_height_m)
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
		var item_dict: Dictionary = Dictionary(_opening_items[index])
		var marker := item_dict.get("marker") as MeshInstance3D
		if marker == null:
			continue
		var mat := marker.material_override as StandardMaterial3D
		if mat != null:
			var open_color: Color = door_color if op.type == OpeningModel.Type.DOOR else window_color
			mat.albedo_color = closed_opening_color.lerp(open_color, clampf(op.open_fraction, 0.0, 1.0))

		# Cortina de humo: suaviza el salto visual de capa entre salas adyacentes.
		# La cortina es un quad en el vano de la puerta que toma la altura promedio
		# de las capas de las dos salas, eliminando el escalón brusco de humo.
		var curtain := item_dict.get("smoke_curtain") as MeshInstance3D
		if curtain == null:
			continue
		var pose: Dictionary = Dictionary(item_dict.get("curtain_pose", {}))
		if pose.is_empty():
			curtain.visible = false
			continue

		var open_frac: float = op.effective_open_fraction()
		if open_frac <= 0.0 or not show_smoke_volume or (_first_person_overlay and not show_smoke_geometry_in_first_person):
			curtain.visible = false
			continue

		var item_a: Dictionary = _room_items.get(op.a, {})
		var item_b: Dictionary = _room_items.get(op.b, {})
		if item_a.is_empty() or item_b.is_empty():
			curtain.visible = false
			continue

		var height_a: float = float(item_a.get("height_m", 2.4))
		var height_b: float = float(item_b.get("height_m", 2.4))
		var room_height_m: float = (height_a + height_b) * 0.5

		var bottom_a: float = float(item_a.get("smoke_bottom_m", height_a))
		var bottom_b: float = float(item_b.get("smoke_bottom_m", height_b))
		var alpha_a: float = float(item_a.get("smoke_alpha", 0.0))
		var alpha_b: float = float(item_b.get("smoke_alpha", 0.0))

		# Usar el mínimo de las dos alturas de fondo para la cortina (el humo
		# más bajo de las dos salas define la frontera visible del vano).
		var curtain_bottom_m: float = minf(bottom_a, bottom_b)
		var curtain_depth_m: float = maxf(0.0, room_height_m - curtain_bottom_m)
		var curtain_alpha: float = (alpha_a + alpha_b) * 0.5 * open_frac

		curtain.visible = curtain_depth_m > smoke_min_visible_depth_m and curtain_alpha > 0.02
		if curtain.visible:
			var door_width_m: float = float(Vector3(pose["size"]).x)
			var door_height_m: float = float(Vector3(pose["size"]).y)
			var thickness_m: float = float(Vector3(pose["size"]).z)
			var curtain_mesh := curtain.mesh as BoxMesh
			if curtain_mesh != null:
				curtain_mesh.size = Vector3(
					door_width_m,
					minf(curtain_depth_m, door_height_m),
					thickness_m
				) * meters_to_units
			var curtain_mat := curtain.material_override as StandardMaterial3D
			if curtain_mat != null:
				curtain_mat.albedo_color = Color(
					smoke_color.r, smoke_color.g, smoke_color.b,
					clampf(curtain_alpha * 0.55, 0.04, 0.45)
				)
			var pos3: Vector3 = Vector3(pose["position"])
			var curtain_center_y: float = curtain_bottom_m + minf(curtain_depth_m, door_height_m) * 0.5
			curtain.position = _to_world(Vector3(pos3.x, curtain_center_y, pos3.z))


func _create_box(node_name: String, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _make_smoke_volume_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SMOKE_VOLUME_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("smoke_color", smoke_color)
	material.set_shader_parameter("density", 0.72)
	material.set_shader_parameter("turbulence", 0.55)
	material.set_shader_parameter("drift_speed", 0.08)
	return material


func _create_smoke_ceiling_mask(node_name: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var shader := Shader.new()
	shader.code = SMOKE_CEILING_MASK_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _create_flame_mesh(node_name: String, color: Color) -> MeshInstance3D:
	var mesh := _create_cross_flame_mesh()
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = _make_flame_material(color)
	return node


func _create_cross_flame_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(3):
		var angle: float = float(i) * PI / 3.0
		var right := Vector3(cos(angle), 0.0, sin(angle))
		var start_index: int = vertices.size()
		vertices.append(-right)
		vertices.append(right)
		vertices.append(right + Vector3.UP)
		vertices.append(-right + Vector3.UP)
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(0.0, 1.0))
		indices.append_array(PackedInt32Array([
			start_index,
			start_index + 1,
			start_index + 2,
			start_index,
			start_index + 2,
			start_index + 3
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _create_fire_ceiling_cap_mesh(node_name: String, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.82
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 22
	mesh.rings = 2
	var shader := Shader.new()
	shader.code = FIRE_CAP_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cap_color", color)
	material.set_shader_parameter("core_color", fire_core_color)
	material.set_shader_parameter("emission_energy", 0.95)
	material.set_shader_parameter("flicker_speed", 1.65 + color.a)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


func _make_flame_material(color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = FLAME_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("flame_color", color)
	material.set_shader_parameter("core_color", fire_core_color)
	material.set_shader_parameter("emission_energy", 1.45)
	material.set_shader_parameter("flicker_speed", 2.4 + color.a)
	return material


func _create_smoke_puff_sprite(node_name: String) -> Sprite3D:
	var node := Sprite3D.new()
	node.name = node_name
	node.texture = SMOKE_TEXTURE_MEDIUM
	node.hframes = 8
	node.vframes = 1
	node.frame = 0
	node.pixel_size = 0.010
	node.modulate = Color(0.72, 0.74, 0.76, 0.28)
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.double_sided = true
	node.shaded = false
	node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	return node


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.metallic = 0.0
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


func _get_room_label(room_id: int, _room_state: Dictionary = {}) -> String:
	return "R%d" % room_id


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

		var node: Node3D
		if fuel_obj_nodes.has(obj_id):
			node = fuel_obj_nodes[obj_id] as Node3D
		else:
			node = _create_fuel_object_node(obj_id, kind_name, size_m)
			fuel_objects_root.add_child(node)
			fuel_obj_nodes[obj_id] = node

		if node == null:
			continue
		if _fuel_shape_needs_rebuild(node, kind_name, size_m):
			_rebuild_fuel_object_shape(node, kind_name, size_m)

		var center_x: float = rect.position.x + pos_m.x + size_m.x * 0.5
		var center_z: float = rect.position.y + pos_m.y + size_m.y * 0.5
		node.position = _to_world(Vector3(center_x, 0.0, center_z))
		node.rotation_degrees.y = float(obj.get("rotation_deg", 0.0))

		var color: Color = _fuel_object_color_3d(state_name)
		var fuel_mj: float = maxf(0.01, float(obj.get("fuel_energy_MJ", 1.0)))
		var remaining_ratio: float = clampf(float(obj.get("remaining_fuel_MJ", fuel_mj)) / fuel_mj, 0.0, 1.0)
		_apply_fuel_object_state_visual(node, state_name, color, remaining_ratio, bool(obj.get("is_primary_ignition_source", false)))

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
	var kind_text: String = String(obj.get("kind", "")).strip_edges().to_lower()
	var name_text: String = String(obj.get("name", "")).strip_edges().to_lower()
	var id_text: String = String(obj.get("id", "")).strip_edges().to_lower()
	var tokens: String = "%s %s %s" % [kind_text, name_text, id_text]

	if tokens.contains("sofa") or tokens.contains("sillon") or tokens.contains("sillón") or tokens.contains("armchair") or tokens.contains("couch"):
		return "sofa"
	if tokens.contains("cama") or tokens.contains("bed") or tokens.contains("colchon"):
		return "bed"
	if tokens.contains("mesa") or tokens.contains("table") or tokens.contains("desk"):
		return "table"
	if tokens.contains("cortina") or tokens.contains("curtain"):
		return "curtain"
	if tokens.contains("armario") or tokens.contains("wardrobe"):
		return "wardrobe"
	if tokens.contains("libreria") or tokens.contains("librería") or tokens.contains("shelf") or tokens.contains("bookshelf") or tokens.contains("bookcase"):
		return "storage"
	if tokens.contains("alfombra") or tokens.contains("rug") or tokens.contains("moqueta") or tokens.contains("tapete"):
		return "rug"
	if tokens.contains("textil") or tokens.contains("textiles") or tokens.contains("ropa"):
		return "textile_pile"
	if tokens.contains("liquido") or tokens.contains("grasa") or tokens.contains("pool"):
		return "pool"
	if tokens.contains("plastico") or tokens.contains("plastic"):
		return "containers"
	if tokens.contains("cocina") or tokens.contains("kitchen"):
		return "kitchen_unit"
	if tokens.contains("mobiliario_tapizado"):
		return "sofa"
	if tokens.contains("mobiliario_madera"):
		return "storage"
	if tokens.contains("mobiliario_mixto"):
		return "clutter"
	if tokens.contains("resto"):
		return "clutter"
	return "clutter"


func _fuel_shape_needs_rebuild(node: Node3D, kind_name: String, size_m: Vector2) -> bool:
	if String(node.get_meta("kind_name", "")) != kind_name:
		return true
	if absf(float(node.get_meta("size_x", -1.0)) - size_m.x) > 0.001:
		return true
	if absf(float(node.get_meta("size_y", -1.0)) - size_m.y) > 0.001:
		return true
	return false


func _rebuild_fuel_object_shape(node: Node3D, kind_name: String, size_m: Vector2) -> void:
	_clear_container(node)
	node.set_meta("kind_name", kind_name)
	node.set_meta("size_x", size_m.x)
	node.set_meta("size_y", size_m.y)

	if _try_build_fp_furniture_asset(node, kind_name, size_m):
		_add_fuel_heat_glow(node, size_m)
		return

	match kind_name:
		"sofa":
			_build_sofa_shape(node, size_m)
		"bed":
			_build_bed_shape(node, size_m)
		"table":
			_build_table_shape(node, size_m)
		"curtain":
			_build_curtain_shape(node, size_m)
		"wardrobe":
			_build_wardrobe_shape(node, size_m)
		"storage":
			_build_storage_shape(node, size_m)
		"kitchen_unit":
			_build_kitchen_unit_shape(node, size_m)
		"rug":
			_build_rug_shape(node, size_m)
		"textile_pile":
			_build_textile_pile_shape(node, size_m)
		"pool":
			_build_pool_shape(node, size_m)
		"containers":
			_build_container_shape(node, size_m)
		"clutter":
			_build_clutter_shape(node, size_m)
		_:
			_build_generic_fuel_shape(node, size_m)
	_add_fuel_heat_glow(node, size_m)


func _try_build_fp_furniture_asset(parent: Node3D, kind_name: String, size_m: Vector2) -> bool:
	var asset_kind: String = kind_name
	match kind_name:
		"storage":
			asset_kind = "dresser"
		"containers":
			asset_kind = "plastic_bin"
		"table":
			asset_kind = "table"
		_:
			asset_kind = kind_name
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
	instance.scale = Vector3(maxf(0.05, size_m.x), 1.0, maxf(0.05, size_m.y)) * meters_to_units
	_prepare_asset_materials_3d(instance)
	parent.add_child(instance)
	return true


func _prepare_asset_materials_3d(root: Node) -> void:
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
			_prepare_asset_materials_3d(child)


func _build_sofa_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var arm_w: float = minf(0.22, x * 0.13)
	var back_d: float = minf(0.20, z * 0.24)
	_add_fuel_box(parent, "ShadowBase", Vector3(0.0, 0.08, z * 0.05), Vector3(x * 0.94, 0.10, z * 0.72), Color(0.20, 0.16, 0.14, 1.0))
	_add_fuel_ellipsoid(parent, "SeatRounded", Vector3(0.0, 0.27, z * 0.08), Vector3(x * 0.88, 0.30, z * 0.68), Color(0.50, 0.38, 0.31, 1.0))
	_add_fuel_ellipsoid(parent, "BackRounded", Vector3(0.0, 0.58, -z * 0.5 + back_d * 0.62), Vector3(x * 0.92, 0.70, back_d * 1.35), Color(0.37, 0.28, 0.24, 1.0))
	_add_fuel_ellipsoid(parent, "ArmLeft", Vector3(-x * 0.5 + arm_w * 0.65, 0.39, z * 0.05), Vector3(arm_w * 1.25, 0.48, z * 0.68), Color(0.39, 0.29, 0.24, 1.0))
	_add_fuel_ellipsoid(parent, "ArmRight", Vector3(x * 0.5 - arm_w * 0.65, 0.39, z * 0.05), Vector3(arm_w * 1.25, 0.48, z * 0.68), Color(0.39, 0.29, 0.24, 1.0))
	for i in range(3):
		var cx: float = lerpf(-x * 0.26, x * 0.26, float(i) / 2.0)
		_add_fuel_ellipsoid(parent, "Cushion_%d" % i, Vector3(cx, 0.45, z * 0.12), Vector3(x * 0.26, 0.10, z * 0.52), Color(0.58, 0.44, 0.36, 1.0))


func _build_bed_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_fuel_box(parent, "BedFrame", Vector3(0.0, 0.16, 0.0), Vector3(x, 0.18, z), Color(0.32, 0.22, 0.17, 1.0))
	_add_fuel_ellipsoid(parent, "MattressRounded", Vector3(0.0, 0.36, 0.0), Vector3(x * 0.95, 0.28, z * 0.92), Color(0.72, 0.68, 0.59, 1.0))
	_add_fuel_ellipsoid(parent, "BlanketSoft", Vector3(0.0, 0.53, z * 0.10), Vector3(x * 0.90, 0.09, z * 0.58), Color(0.56, 0.44, 0.34, 1.0))
	_add_fuel_ellipsoid(parent, "PillowA", Vector3(-x * 0.24, 0.61, -z * 0.34), Vector3(x * 0.36, 0.13, z * 0.18), Color(0.84, 0.80, 0.70, 1.0))
	_add_fuel_ellipsoid(parent, "PillowB", Vector3(x * 0.24, 0.61, -z * 0.34), Vector3(x * 0.36, 0.13, z * 0.18), Color(0.84, 0.80, 0.70, 1.0))
	_add_fuel_box(parent, "Headboard", Vector3(0.0, 0.55, -z * 0.52), Vector3(x, 0.72, 0.08), Color(0.36, 0.25, 0.18, 1.0))


func _build_table_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var leg_w: float = minf(0.10, minf(x, z) * 0.14)
	_add_fuel_ellipsoid(parent, "SoftTableTop", Vector3(0.0, 0.74, 0.0), Vector3(x, 0.10, z), Color(0.48, 0.34, 0.22, 1.0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_fuel_cylinder(parent, "Leg", Vector3(sx * (x * 0.5 - leg_w), 0.36, sz * (z * 0.5 - leg_w)), Vector3(leg_w, 0.70, leg_w), Color(0.34, 0.22, 0.14, 1.0))


func _build_curtain_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.05, size_m.y)
	var panels: int = 6
	var panel_w: float = x / float(panels)
	for i in range(panels):
		var offset_x: float = -x * 0.5 + panel_w * (float(i) + 0.5)
		var fold_z: float = (-0.5 if i % 2 == 0 else 0.5) * minf(0.08, z)
		_add_fuel_box(parent, "Panel_%d" % i, Vector3(offset_x, 0.90, fold_z), Vector3(panel_w * 0.72, 1.80, maxf(0.035, z * 0.55)), Color(0.53, 0.37, 0.30, 1.0))
	_add_fuel_box(parent, "Rail", Vector3(0.0, 1.83, 0.0), Vector3(x, 0.04, maxf(0.04, z)), Color(0.30, 0.24, 0.20, 1.0))


func _build_wardrobe_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_fuel_box(parent, "Body", Vector3(0.0, 0.88, 0.0), Vector3(x, 1.76, z), Color(0.45, 0.31, 0.19, 1.0))
	_add_fuel_box(parent, "DoorLeft", Vector3(-x * 0.25, 0.90, z * 0.5 + 0.012), Vector3(x * 0.46, 1.58, 0.035), Color(0.54, 0.38, 0.23, 1.0))
	_add_fuel_box(parent, "DoorRight", Vector3(x * 0.25, 0.90, z * 0.5 + 0.012), Vector3(x * 0.46, 1.58, 0.035), Color(0.54, 0.38, 0.23, 1.0))
	_add_fuel_box(parent, "HandleLeft", Vector3(-x * 0.06, 0.90, z * 0.5 + 0.04), Vector3(0.025, 0.42, 0.025), Color(0.76, 0.62, 0.36, 1.0))
	_add_fuel_box(parent, "HandleRight", Vector3(x * 0.06, 0.90, z * 0.5 + 0.04), Vector3(0.025, 0.42, 0.025), Color(0.76, 0.62, 0.36, 1.0))


func _build_storage_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var long_axis: float = maxf(x, z)
	var shallow_axis: float = minf(x, z)
	var shelf_height: float = clampf(long_axis * 0.55, 0.70, 1.70)
	var is_x_long: bool = x >= z
	var width: float = long_axis
	var depth: float = clampf(shallow_axis, 0.24, 0.62)
	var body_size := Vector3(width, shelf_height, depth)
	var body_center := Vector3(0.0, shelf_height * 0.5, 0.0)
	if not is_x_long:
		body_size = Vector3(depth, shelf_height, width)
	_add_fuel_box(parent, "ShelfBack", body_center, body_size, Color(0.38, 0.26, 0.17, 1.0))
	for level in range(3):
		var y: float = shelf_height * (0.24 + float(level) * 0.25)
		var shelf_size := Vector3(width * 0.92, 0.045, depth * 1.08)
		if not is_x_long:
			shelf_size = Vector3(depth * 1.08, 0.045, width * 0.92)
		_add_fuel_box(parent, "Shelf_%d" % level, Vector3(0.0, y, 0.0), shelf_size, Color(0.55, 0.39, 0.24, 1.0))
	var item_count: int = clampi(int(round(long_axis * 2.0)), 2, 5)
	for i in range(item_count):
		var t: float = (float(i) + 0.5) / float(item_count) - 0.5
		var y_item: float = shelf_height * (0.34 + 0.18 * float(i % 3))
		var offset := Vector3(t * width * 0.70, y_item, depth * 0.05)
		var item_size := Vector3(width / float(item_count) * 0.45, 0.20 + 0.05 * float(i % 2), depth * 0.40)
		if not is_x_long:
			offset = Vector3(depth * 0.05, y_item, t * width * 0.70)
			item_size = Vector3(depth * 0.40, 0.20 + 0.05 * float(i % 2), width / float(item_count) * 0.45)
		_add_fuel_box(parent, "ShelfLoad_%d" % i, offset, item_size, Color(0.44, 0.32, 0.23, 1.0))


func _build_kitchen_unit_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_fuel_box(parent, "Cabinet", Vector3(0.0, 0.42, 0.0), Vector3(x, 0.84, z), Color(0.50, 0.36, 0.24, 1.0))
	_add_fuel_box(parent, "Counter", Vector3(0.0, 0.88, 0.0), Vector3(x * 1.04, 0.08, z * 1.06), Color(0.20, 0.20, 0.18, 1.0))
	for i in range(3):
		var cx: float = lerpf(-x * 0.32, x * 0.32, float(i) / 2.0)
		_add_fuel_box(parent, "Door_%d" % i, Vector3(cx, 0.44, z * 0.5 + 0.012), Vector3(x * 0.25, 0.58, 0.035), Color(0.58, 0.42, 0.28, 1.0))
		_add_fuel_box(parent, "Handle_%d" % i, Vector3(cx, 0.58, z * 0.5 + 0.04), Vector3(x * 0.12, 0.025, 0.025), Color(0.76, 0.62, 0.36, 1.0))


func _build_textile_pile_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	for i in range(6):
		var seed: float = float(i) * 1.73
		var offset := Vector3(
			sin(seed) * x * 0.22,
			0.10 + float(i % 3) * 0.055,
			cos(seed * 0.8) * z * 0.20
		)
		var item_size := Vector3(
			x * (0.34 + 0.08 * float(i % 2)),
			0.12,
			z * (0.28 + 0.07 * float((i + 1) % 2))
		)
		_add_fuel_ellipsoid(parent, "Fold_%d" % i, offset, item_size, Color(0.55, 0.42, 0.35, 1.0))


func _build_rug_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	_add_fuel_ellipsoid(parent, "RugBody", Vector3(0.0, 0.035, 0.0), Vector3(x, 0.055, z), Color(0.52, 0.32, 0.24, 1.0))
	_add_fuel_ellipsoid(parent, "RugInner", Vector3(0.0, 0.052, 0.0), Vector3(x * 0.78, 0.035, z * 0.70), Color(0.70, 0.50, 0.36, 1.0))
	var fringe_z: float = z * 0.5 + 0.025
	_add_fuel_box(parent, "FringeA", Vector3(0.0, 0.045, -fringe_z), Vector3(x * 0.86, 0.018, 0.035), Color(0.80, 0.68, 0.52, 1.0))
	_add_fuel_box(parent, "FringeB", Vector3(0.0, 0.045, fringe_z), Vector3(x * 0.86, 0.018, 0.035), Color(0.80, 0.68, 0.52, 1.0))


func _build_pool_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 36
	var mat := _make_material(Color(0.18, 0.12, 0.08, 0.78), true)
	mat.roughness = 0.42
	var puddle := MeshInstance3D.new()
	puddle.name = "FuelPuddle"
	puddle.mesh = mesh
	puddle.material_override = mat
	puddle.position = Vector3(0.0, 0.018, 0.0) * meters_to_units
	puddle.scale = Vector3(x, 0.025, z) * meters_to_units
	puddle.set_meta("base_color", Color(0.18, 0.12, 0.08, 0.78))
	parent.add_child(puddle)
	_add_fuel_box(parent, "PanLip", Vector3(0.0, 0.045, 0.0), Vector3(x * 1.04, 0.035, 0.035), Color(0.24, 0.22, 0.20, 1.0))


func _build_container_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var count: int = 3
	for i in range(count):
		var offset_x: float = lerpf(-x * 0.25, x * 0.25, float(i) / float(count - 1))
		_add_fuel_cylinder(parent, "PlasticContainer_%d" % i, Vector3(offset_x, 0.24, sin(float(i)) * z * 0.12), Vector3(x * 0.20, 0.48, z * 0.20), Color(0.36, 0.38, 0.36, 1.0))
		_add_fuel_box(parent, "Lid_%d" % i, Vector3(offset_x, 0.50, sin(float(i)) * z * 0.12), Vector3(x * 0.24, 0.045, z * 0.24), Color(0.24, 0.27, 0.25, 1.0))


func _build_clutter_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	for i in range(7):
		var seed: float = float(i) * 2.11
		var offset := Vector3(
			sin(seed) * x * 0.28,
			0.09 + float(i % 3) * 0.09,
			cos(seed * 0.7) * z * 0.28
		)
		var color := Color(0.43 + 0.05 * float(i % 2), 0.32, 0.23, 1.0)
		if i % 3 == 0:
			_add_fuel_ellipsoid(parent, "SoftLoad_%d" % i, offset, Vector3(x * 0.24, 0.18, z * 0.22), color)
		else:
			_add_fuel_box(parent, "BoxLoad_%d" % i, offset, Vector3(x * 0.22, 0.18, z * 0.20), color)


func _build_generic_fuel_shape(parent: Node3D, size_m: Vector2) -> void:
	var x: float = maxf(0.2, size_m.x)
	var z: float = maxf(0.2, size_m.y)
	var h: float = maxf(0.22, fuel_object_3d_height_m)
	_add_fuel_ellipsoid(parent, "GenericPile", Vector3(0.0, h * 0.5, 0.0), Vector3(x, h, z), Color(0.48, 0.42, 0.34, 1.0))


func _add_fuel_box(parent: Node3D, node_name: String, center_m: Vector3, size_m: Vector3, color: Color) -> MeshInstance3D:
	var mesh := _create_box(node_name, size_m * meters_to_units, _make_material(color, false))
	mesh.position = center_m * meters_to_units
	mesh.set_meta("base_color", color)
	parent.add_child(mesh)
	return mesh


func _add_fuel_ellipsoid(parent: Node3D, node_name: String, center_m: Vector3, size_m: Vector3, color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = sphere
	node.material_override = _make_material(color, false)
	node.position = center_m * meters_to_units
	node.scale = size_m * meters_to_units
	node.set_meta("base_color", color)
	parent.add_child(node)
	return node


func _add_fuel_cylinder(parent: Node3D, node_name: String, center_m: Vector3, size_m: Vector3, color: Color) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 14
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = cylinder
	node.material_override = _make_material(color, false)
	node.position = center_m * meters_to_units
	node.scale = size_m * meters_to_units
	node.set_meta("base_color", color)
	parent.add_child(node)
	return node


func _add_fuel_heat_glow(parent: Node3D, size_m: Vector2) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 32
	var mat := _make_material(Color(1.0, 0.32, 0.08, 0.0), true)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.26, 0.06, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow := MeshInstance3D.new()
	glow.name = "HeatGlow"
	glow.mesh = mesh
	glow.material_override = mat
	glow.visible = false
	glow.position = Vector3(0.0, 0.025, 0.0) * meters_to_units
	glow.scale = Vector3(maxf(0.1, size_m.x), 0.018, maxf(0.1, size_m.y)) * meters_to_units
	parent.add_child(glow)


func _apply_fuel_object_state_visual(root: Node3D, state_name: String, state_color: Color, remaining_ratio: float, is_ignition_source: bool) -> void:
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
	_apply_fuel_materials_recursive(root, state_name, state_color, heat_t, char_t)

	var glow := root.get_node_or_null("HeatGlow") as MeshInstance3D
	if glow != null:
		glow.visible = heat_t > 0.05 or is_ignition_source
		var mat := glow.material_override as StandardMaterial3D
		if mat != null:
			var alpha: float = clampf(heat_t * 0.30 + (0.12 if is_ignition_source else 0.0), 0.0, 0.48)
			mat.albedo_color = Color(state_color.r, state_color.g * 0.60, state_color.b * 0.30, alpha)
			mat.emission_energy_multiplier = heat_t * 0.75 + (0.18 if is_ignition_source else 0.0)


func _apply_fuel_materials_recursive(root: Node, state_name: String, state_color: Color, heat_t: float, char_t: float) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			if mesh_node.name == "HeatGlow":
				continue
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var base_color: Color = Color(mesh_node.get_meta("base_color", Color(0.55, 0.52, 0.48, 1.0)))
				var char_color: Color = Color(0.10, 0.09, 0.08, 1.0)
				var final_color: Color = base_color.lerp(char_color, clampf(char_t * 0.75, 0.0, 0.85))
				final_color = final_color.lerp(state_color, heat_t * 0.42)
				if state_name == "burned_out":
					final_color = Color(0.11, 0.11, 0.10, 1.0)
				mat.albedo_color = final_color
				mat.emission_enabled = heat_t > 0.05
				if mat.emission_enabled:
					mat.emission = Color(state_color.r, state_color.g * 0.65, state_color.b * 0.20, 1.0)
					mat.emission_energy_multiplier = heat_t * (1.55 if state_name == "flaming" else 0.65)
				else:
					mat.emission_energy_multiplier = 0.0
		if child.get_child_count() > 0:
			_apply_fuel_materials_recursive(child, state_name, state_color, heat_t, char_t)


func _create_fuel_object_box(obj_id: String, size_m: Vector2, height_m: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(
		maxf(0.05, size_m.x) * meters_to_units,
		maxf(0.05, height_m) * meters_to_units,
		maxf(0.05, size_m.y) * meters_to_units
	)
	var mat := _make_material(Color(0.55, 0.52, 0.48, 1.0), false)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var node := MeshInstance3D.new()
	node.name = "FuelObj_" + obj_id
	node.mesh = mesh
	node.material_override = mat
	return node


func _fuel_object_color_3d(state_name: String) -> Color:
	match state_name:
		"flaming":    return Color(1.00, 0.22, 0.08, 1.0)
		"pyrolyzing": return Color(1.00, 0.54, 0.10, 1.0)
		"heating":    return Color(1.00, 0.80, 0.22, 1.0)
		"decaying":   return Color(0.72, 0.36, 0.16, 1.0)
		"burned_out": return Color(0.18, 0.18, 0.18, 1.0)
		_:            return Color(0.55, 0.52, 0.48, 1.0)


func _get_room_id_at_screen_pos(screen_pos: Vector2) -> int:
	if _camera == null or building == null:
		return -1
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return -1
	var t: float = -ray_origin.y / ray_dir.y
	if t < 0.0:
		return -1
	var hit: Vector3 = ray_origin + ray_dir * t
	var hit_m := Vector2(
		hit.x / maxf(0.0001, meters_to_units) - _origin_offset_m.x,
		hit.z / maxf(0.0001, meters_to_units) - _origin_offset_m.y
	)
	var rects: Dictionary = building.get_room_rects_m()
	var sorted_ids: Array = []
	for k in rects.keys():
		sorted_ids.append(int(k))
	sorted_ids.sort()
	for room_id in sorted_ids:
		if rects[room_id].has_point(hit_m):
			return room_id
	return -1


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
