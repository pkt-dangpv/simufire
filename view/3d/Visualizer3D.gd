extends Node3D
class_name Visualizer3D

signal room_clicked(room_id: int)
signal opening_clicked(opening_index: int, screen_pos: Vector2)
signal object_clicked(room_id: int, object_id: String)
signal detector_clicked(detector_id: String)
signal victim_clicked(victim_id: String)
signal player_start_clicked(room_id: int)
signal floor_clicked(room_id: int, floor_pos_m: Vector2)
signal element_drag_started(kind: String)
signal object_dragged(room_id: int, object_id: String, floor_pos_m: Vector2)
signal detector_dragged(detector_id: String, floor_pos_m: Vector2)
signal victim_dragged(victim_id: String, floor_pos_m: Vector2)
signal player_start_dragged(floor_pos_m: Vector2)
signal element_drag_ended(kind: String)
## Emitido tras capturar y guardar un PNG de la vista 3D (V3D-05). path = ruta absoluta.
signal screenshot_saved(path: String)
## Emitido si la captura falla. message = descripcion del error.
signal screenshot_failed(message: String)

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
const FurnitureVisualLayout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const OpeningPose3D := preload("res://view/3d/openings/OpeningPose3D.gd")
const RoomShellFactory := preload("res://view/3d/geometry/RoomShellFactory.gd")
const Legend3DScene: PackedScene = preload("res://view/3d/Legend3D.tscn")
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
@export_range(30.0, 120.0, 1.0) var door_leaf_max_open_angle_deg: float = 90.0

@export_group("Visibility")
@export var show_walls: bool = true
@export var show_openings: bool = true
## Dibuja hojas de puerta 3D que rotan segun open_fraction en la vista orbital.
@export var show_door_leaf_animation_3d: bool = true
@export var show_room_labels: bool = true
## Muestra FED acumulado de la víctima más expuesta en cada sala (V3D-04).
@export var show_fed_labels: bool = false
@export var show_smoke_volume: bool = true
@export var show_hot_layer: bool = false
@export var show_layer_150c: bool = false
## Muestra una banda semitransparente desde la interfaz de capa de humo hasta el techo (V3D-01).
@export var show_layer_gradient: bool = false
## Aplica heatmap de temperatura en el color de las paredes (V3D-03).
@export var show_wall_heatmap: bool = true
@export var show_hrr_columns: bool = true
## Muestra la llama del visor 3D tambien en primera persona. Apagado por
## defecto: FP ya tiene su propia llama con luz sombreada, y la del 3D
## (sin sombras) iluminaba salas vecinas a traves de las paredes.
@export var show_fire_in_first_person: bool = false
@export var show_fuel_objects_3d: bool = true
## Mantiene visible el mobiliario 3D compartido cuando la camara FP esta activa.
@export var show_fuel_objects_in_first_person: bool = true
@export var fp_fuel_object_update_interval_s: float = 0.25
@export var show_detector_markers_3d: bool = true
@export var show_victim_markers_3d: bool = true
## Muestra leyenda de colores activos en esquina superior derecha de la vista 3D (V3D-02).
## Desactivada por defecto para no solaparse con el HUD de salas; se puede activar desde Inspector.
@export var show_legend: bool = false
@export var show_exterior_context_3d: bool = false
@export var fuel_object_3d_height_m: float = 0.34
@export var smoke_puff_count: int = 12
@export var show_smoke_geometry_in_first_person: bool = true
@export var show_smoke_puffs_in_first_person: bool = false
@export var show_smoke_opening_curtains: bool = false
@export var show_smoke_opening_curtains_in_first_person: bool = false
@export var show_smoke_ceiling_masks: bool = true
@export var show_cold_air_inflow_curtains: bool = false
@export var show_fire_smoke_plume: bool = false

@export_group("Colors")
@export var floor_color: Color = Color(0.18, 0.18, 0.17, 1.0)
@export var hot_floor_color: Color = Color(0.46, 0.30, 0.18, 1.0)
@export var wall_color: Color = Color(0.84, 0.86, 0.82, 0.42)
@export var hot_wall_color: Color = Color(1.00, 0.42, 0.12, 0.68)
@export var wall_outline_color: Color = Color(0.95, 0.95, 0.90, 0.72)
@export var smoke_color: Color = Color(0.028, 0.027, 0.025, 0.54)
@export var smoke_puff_color: Color = Color(0.055, 0.052, 0.048, 0.42)
@export var layer_gradient_top_color: Color = Color(0.10, 0.09, 0.08, 0.54)
@export var layer_gradient_bottom_color: Color = Color(0.30, 0.26, 0.20, 0.08)
@export var smoke_hot_outflow_color: Color = Color(1.00, 0.46, 0.16, 0.24)
@export var cold_air_inflow_color: Color = Color(0.18, 0.52, 1.00, 0.09)
@export var hot_layer_color: Color = Color(1.00, 0.58, 0.18, 0.18)
@export var layer_150c_color: Color = Color(1.00, 0.12, 0.06, 0.70)
@export var fire_color: Color = Color(1.00, 0.38, 0.06, 0.88)
@export var fire_core_color: Color = Color(1.0, 0.84, 0.24, 0.96)
@export var fire_glow_color: Color = Color(1.0, 0.22, 0.04, 0.28)
@export var fire_ceiling_cap_color: Color = Color(1.0, 0.34, 0.05, 0.42)
@export var door_color: Color = Color(0.26, 0.86, 0.32, 0.92)
@export var window_color: Color = Color(0.24, 0.56, 1.00, 0.92)
@export var window_broken_color: Color = Color(1.00, 0.72, 0.12, 0.92)
@export var hole_color: Color = Color(1.00, 0.78, 0.00, 0.86)
@export var closed_opening_color: Color = Color(0.54, 0.56, 0.58, 0.70)
@export var label_color: Color = Color(1.0, 0.96, 0.84, 1.0)
@export var fed_label_warn_color: Color = Color(1.0, 0.72, 0.12, 1.0)
@export var fed_label_danger_color: Color = Color(1.0, 0.18, 0.10, 1.0)
@export var detector_marker_color: Color = Color(0.35, 0.76, 1.0, 1.0)
@export var detector_triggered_color: Color = Color(1.0, 0.40, 0.18, 1.0)
@export var victim_marker_color: Color = Color(0.95, 0.86, 0.48, 1.0)
@export var victim_incapacitated_color: Color = Color(0.58, 0.58, 0.62, 1.0)
@export var player_start_marker_color: Color = Color(0.58, 0.88, 1.0, 1.0)
@export var selection_highlight_color: Color = Color(1.0, 0.88, 0.18, 1.0)

@export_group("Dynamics")
@export var smoke_visible_threshold_kg: float = 0.003
@export var smoke_reference_kg: float = 0.35
@export var smoke_density_reference_kg_m3: float = 0.018
@export var smoke_dense_visibility_m: float = 12.0
@export var smoke_ceiling_mask_max_alpha: float = 0.92
@export var smoke_light_min_transmission: float = 0.10
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
## Energia de la luz del fuego cuando HRR = 1000 kW (referencia 1 MW).
@export var fire_light_energy_per_1000kw: float = 2.4
## Exponente de la ley de potencia energia = E_1MW * (HRR/1000)^exp.
## 0.5-0.6 = perceptual (fuegos pequenos ya iluminan); 1.0 = lineal.
@export_range(0.3, 1.0, 0.05) var fire_light_energy_exponent: float = 0.55
## Alcance de la luz a 1 MW; escala con sqrt(HRR).
@export var fire_light_range_at_1mw_m: float = 10.0
@export var fire_light_range_min_m: float = 2.0
@export var fire_light_range_max_m: float = 12.0
@export var fire_light_color: Color = Color(1.0, 0.42, 0.12, 1.0)
## Sombras en la luz del fuego (evita iluminar a traves de paredes/muebles).
## En la vista dollhouse el coste suele compensar solo con pocas salas ardiendo.
@export var fire_light_cast_shadows: bool = false
## Atenuacion de la OmniLight del fuego. <1.0 luz mas uniforme; >1.0 mas concentrada.
@export_range(0.2, 4.0, 0.05) var fire_light_attenuation: float = 1.0
## Altura (m) de la luz del fuego sobre la base de la llama.
@export var fire_light_height_m: float = 0.9
## Transmision minima del humo aplicada a la luz del fuego (la llama vive
## bajo la capa de humo; si es visible, ilumina al menos esta fraccion).
@export_range(0.0, 1.0, 0.05) var fire_light_min_transmission: float = 0.35
## Fraccion de la altura disponible que puede alcanzar la llama en la vista
## 3D. La vista dollhouse no tiene techos: una llama a techo completo se
## proyecta por encima de la silueta de los muros desde camaras bajas.
@export_range(0.3, 1.0, 0.02) var fire_max_height_fraction: float = 0.72
@export var temp_heat_floor_start_c: float = 80.0
@export var temp_heat_floor_full_c: float = 450.0
@export var temp_heat_wall_start_c: float = 60.0
@export var temp_heat_wall_full_c: float = 550.0

@export_group("Camera")
@export var enable_mouse_camera: bool = true
@export var orbit_with_left_drag_on_model: bool = true
@export var allow_element_drag: bool = true
@export var camera_distance_m: float = 13.0
@export var min_camera_distance_m: float = 4.0
@export var max_camera_distance_m: float = 35.0
@export var camera_orbit_x_deg: float = -56.0
@export var camera_orbit_y_deg: float = 42.0
@export var camera_orbit_sensitivity: float = 0.006
@export var camera_zoom_step_m: float = 0.8

@export_group("Debug")
## Muestra el nombre del cuarto + altura de capa de humo en los labels de sala (V3D-06).
@export var debug_show_layer_heights: bool = false
## Muestra la temperatura media de capa superior en etiqueta de sala (V3D-06).
@export var debug_show_room_temps: bool = false
## Muestra el HRR (kW) de cada sala en la etiqueta (V3D-06).
@export var debug_show_hrr_values: bool = false

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
var _player_start_node: Node3D = null
var _built: bool = false
var _bounds_m: Rect2 = Rect2()
var _origin_offset_m: Vector2 = Vector2.ZERO
var _camera_distance: float = 13.0
var _orbit_x: float = 0.0
var _orbit_y: float = 0.0
var _orbit_dragging: bool = false
var _selected_room_id: int = -1
var _selected_opening_index: int = -1
var _selected_object_room_id: int = -1
var _selected_object_id: String = ""
var _selected_detector_id: String = ""
var _selected_victim_id: String = ""
var _selected_player_start: bool = false
var _dragging_element_kind: String = ""
var _dragging_element_id: String = ""
var _dragging_element_room_id: int = -1
var _drag_floor_level_m: float = 0.0
var _drag_floor_offset_m: Vector2 = Vector2.ZERO
var _drag_start_floor_pos_m: Vector2 = Vector2.ZERO
var _drag_started_emitted: bool = false
var _last_fp_fuel_object_update_msec: int = 0
var _fire_phase: float = 0.0
var _input_active: bool = true
var _first_person_overlay: bool = false
var _legend_canvas: CanvasLayer = null
var _legend_panel: PanelContainer = null
var _legend_vbox: VBoxContainer = null
var _legend_flags_hash: int = -1


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
	var was_first_person_overlay: bool = _first_person_overlay
	visible = active
	_input_active = active and input_active
	_first_person_overlay = active and first_person_overlay
	if _first_person_overlay != was_first_person_overlay:
		_last_fp_fuel_object_update_msec = 0
	if _camera != null:
		_camera.current = active and camera_active
	_apply_overlay_visibility()
	if not active:
		_orbit_dragging = false
		_clear_element_drag()


func set_element_drag_enabled(enabled: bool) -> void:
	allow_element_drag = enabled
	if not allow_element_drag:
		_clear_element_drag()


func set_state(next_state: Dictionary) -> void:
	state = next_state
	if not _built:
		_resolve_building()
		_rebuild_scene()
	_update_dynamic_state()
	_update_legend()


func rebuild_from_building() -> void:
	_built = false
	_rebuild_scene()
	_fit_camera_to_building()
	_update_dynamic_state()
	_update_room_selection_visuals()


## Captura la vista actual del viewport y la guarda como PNG (V3D-05).
## output_dir: carpeta absoluta de destino. Si esta vacio usa la carpeta del proyecto.
## Emite screenshot_saved(path) o screenshot_failed(message).
func capture_screenshot_to(output_dir: String = "") -> void:
	var vp := get_viewport()
	if vp == null:
		screenshot_failed.emit("Viewport no disponible")
		return
	var legend_was_visible: bool = _legend_canvas != null and _legend_canvas.visible
	if _legend_canvas != null:
		_legend_canvas.visible = false
	# frame_post_draw no dispara nunca en --headless (no hay render): la
	# corrutina se colgaria sin emitir senal. Ahi basta un process_frame.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if _legend_canvas != null:
		_legend_canvas.visible = legend_was_visible
	if img == null:
		screenshot_failed.emit("get_image() devolvio null")
		return
	var dir: String = output_dir.strip_edges()
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = ProjectSettings.globalize_path("res://")
	var ts: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var file_path: String = dir.path_join("simufire_3d_%s.png" % ts)
	var err: Error = img.save_png(file_path)
	if err == OK:
		screenshot_saved.emit(file_path)
	else:
		screenshot_failed.emit("Error %d al guardar %s" % [err, file_path])


func select_room(room_id: int) -> void:
	_selected_room_id = room_id
	_selected_opening_index = -1
	_selected_object_room_id = -1
	_selected_object_id = ""
	_selected_detector_id = ""
	_selected_victim_id = ""
	_selected_player_start = false
	_apply_selection_visuals()


func select_opening(opening_index: int) -> void:
	_selected_room_id = -1
	_selected_opening_index = opening_index
	_selected_object_room_id = -1
	_selected_object_id = ""
	_selected_detector_id = ""
	_selected_victim_id = ""
	_selected_player_start = false
	_apply_selection_visuals()


func select_object(room_id: int, object_id: String) -> void:
	_selected_room_id = -1
	_selected_opening_index = -1
	_selected_object_room_id = room_id
	_selected_object_id = object_id
	_selected_detector_id = ""
	_selected_victim_id = ""
	_selected_player_start = false
	_apply_selection_visuals()


func select_detector(detector_id: String) -> void:
	_selected_room_id = -1
	_selected_opening_index = -1
	_selected_object_room_id = -1
	_selected_object_id = ""
	_selected_detector_id = detector_id
	_selected_victim_id = ""
	_selected_player_start = false
	_apply_selection_visuals()


func select_victim(victim_id: String) -> void:
	_selected_room_id = -1
	_selected_opening_index = -1
	_selected_object_room_id = -1
	_selected_object_id = ""
	_selected_detector_id = ""
	_selected_victim_id = victim_id
	_selected_player_start = false
	_apply_selection_visuals()


func select_player_start() -> void:
	_selected_room_id = -1
	_selected_opening_index = -1
	_selected_object_room_id = -1
	_selected_object_id = ""
	_selected_detector_id = ""
	_selected_victim_id = ""
	_selected_player_start = true
	_apply_selection_visuals()


func clear_selection() -> void:
	_selected_room_id = -1
	_selected_opening_index = -1
	_selected_object_room_id = -1
	_selected_object_id = ""
	_selected_detector_id = ""
	_selected_victim_id = ""
	_selected_player_start = false
	_apply_selection_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_active or not enable_mouse_camera or not is_visible_in_tree():
		return

	if event is InputEventMouseMotion and _is_element_dragging():
		var drag_motion := event as InputEventMouseMotion
		_update_element_drag(drag_motion.position)
		get_viewport().set_input_as_handled()
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
					var player_start_hit: Dictionary = _player_start_at_screen_pos(mb.position)
					if not player_start_hit.is_empty():
						var start_room_id: int = int(player_start_hit.get("room_id", -1))
						select_player_start()
						player_start_clicked.emit(start_room_id)
						_begin_element_drag("player_start", "player_start", start_room_id, mb.position)
						get_viewport().set_input_as_handled()
						return
					var safety_hit: Dictionary = _safety_marker_at_screen_pos(mb.position)
					if not safety_hit.is_empty():
						var hit_type: String = String(safety_hit.get("type", ""))
						var hit_id: String = String(safety_hit.get("id", ""))
						if hit_type == "detector":
							select_detector(hit_id)
							detector_clicked.emit(hit_id)
							_begin_element_drag(hit_type, hit_id, -1, mb.position)
						elif hit_type == "victim":
							select_victim(hit_id)
							victim_clicked.emit(hit_id)
							_begin_element_drag(hit_type, hit_id, -1, mb.position)
						get_viewport().set_input_as_handled()
						return
					var object_hit: Dictionary = _fuel_object_at_screen_pos(mb.position)
					if not object_hit.is_empty():
						var object_room_id: int = int(object_hit.get("room_id", -1))
						var object_id: String = String(object_hit.get("object_id", ""))
						select_object(object_room_id, object_id)
						object_clicked.emit(object_room_id, object_id)
						_begin_element_drag("object", object_id, object_room_id, mb.position)
						get_viewport().set_input_as_handled()
						return
					var opening_index: int = ScreenPicking3D.opening_index_at_screen_pos(_camera, _opening_items, mb.position)
					if opening_index >= 0:
						select_opening(opening_index)
						opening_clicked.emit(opening_index, mb.position)
						get_viewport().set_input_as_handled()
						return
					var rid: int = ScreenPicking3D.room_id_at_screen_pos(_camera, building, mb.position, meters_to_units, _origin_offset_m)
					if rid >= 0:
						select_room(rid)
						room_clicked.emit(rid)
						var rid_level_m: float = _get_room_floor_level(rid)
						var floor_hit: Variant = _screen_to_floor_at_level(mb.position, rid_level_m)
						if typeof(floor_hit) == TYPE_VECTOR2:
							floor_clicked.emit(rid, Vector2(floor_hit))
						get_viewport().set_input_as_handled()
					elif _has_selection():
						clear_selection()
						room_clicked.emit(-1)
						get_viewport().set_input_as_handled()
				else:
					if _has_selection():
						clear_selection()
						room_clicked.emit(-1)
						get_viewport().set_input_as_handled()
			elif _is_element_dragging():
				_finish_element_drag()
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
	_build_legend_ui()
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
				child.visible = show_fuel_objects_3d and (not _first_person_overlay or show_fuel_objects_in_first_person)
			elif String(child.name).begins_with("SafetyMarkers_"):
				child.visible = not _first_person_overlay
			elif String(child.name).begins_with("Fire_"):
				child.visible = child.visible and (not _first_person_overlay or show_fire_in_first_person)
	var sun := get_node_or_null("Sun") as Light3D
	if sun != null:
		sun.visible = not _first_person_overlay
	var fill := get_node_or_null("FillLight") as Light3D
	if fill != null:
		fill.visible = not _first_person_overlay
	if _legend_panel != null:
		_legend_panel.visible = show_legend and not _first_person_overlay


func _build_legend_ui() -> void:
	if _legend_canvas != null:
		return
	# La leyenda vive en scenes/Legend3D.tscn (posicion/estilo editables);
	# aqui solo se instancia y se enlazan panel y contenedor de filas.
	_legend_canvas = Legend3DScene.instantiate() as CanvasLayer
	add_child(_legend_canvas)
	_legend_panel = _legend_canvas.get_node("LegendPanel") as PanelContainer
	_legend_vbox = _legend_canvas.get_node("LegendPanel/Margin/Rows") as VBoxContainer


func _update_legend() -> void:
	if _legend_panel == null or _legend_vbox == null:
		return
	var flags_hash: int = int(show_hot_layer) | (int(show_layer_150c) << 1) | (int(show_layer_gradient) << 2) | (int(_first_person_overlay) << 3)
	if flags_hash == _legend_flags_hash:
		return
	_legend_flags_hash = flags_hash
	for child in _legend_vbox.get_children():
		child.queue_free()

	var entries: Array = []
	entries.append({"color": floor_color, "label": "Suelo / frio"})
	entries.append({"color": hot_floor_color, "label": "Suelo / caliente"})
	entries.append({"color": smoke_color, "label": "Humo"})
	if show_hot_layer:
		entries.append({"color": hot_layer_color, "label": "Capa caliente"})
	if show_layer_150c:
		entries.append({"color": layer_150c_color, "label": "Capa 150 °C"})
	if show_layer_gradient:
		entries.append({"color": layer_gradient_top_color, "label": "Gradiente capa"})

	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = Color(entry["color"])
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var lbl := Label.new()
		lbl.text = String(entry["label"])
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.88, 1.0))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		_legend_vbox.add_child(row)

	_legend_panel.visible = show_legend and not _first_person_overlay


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
	_player_start_node = null

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

	if show_exterior_context_3d:
		_create_exterior_context_visuals()

	_built = true
	_update_room_selection_visuals()


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		# remove_child inmediato: los nodos nuevos del rebuild reutilizan los
		# mismos nombres y una colision los renombraria (@Nombre@N).
		container.remove_child(child)
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
	var height_m: float = _get_room_height(room_id)
	var floor_level_m: float = _get_room_floor_level(room_id)
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var is_stair: bool = _is_stair_room(room)
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
			"show_walls": show_walls and (not is_stair or room.stair_has_walls),
			"show_room_labels": show_room_labels,
			"floor_color": floor_color,
			"wall_color": wall_color,
			"label_color": label_color,
		}
	)
	var floor := shell.get("floor") as MeshInstance3D
	var walls: Array = shell.get("walls", [])
	var room_node := shell.get("room_node") as Node3D
	var floor_parts: Array[MeshInstance3D] = []
	if floor != null and is_stair and floor_level_m > 0.20:
		floor.visible = false
		_create_stairwell_upper_floor_visual(room_id, rect_m, floor_level_m, room_node, _room_stair_run_direction(room), room.stair_turn_degrees)
	elif floor != null:
		var slabs: Array[Rect2] = _split_rect_by_voids(rect_m, _vertical_stair_voids_for_floor(floor_level_m))
		if not (slabs.size() == 1 and _rect_same(slabs[0], rect_m)):
			floor.visible = false
			for i in range(slabs.size()):
				floor_parts.append(_add_floor_void_part_visual(room_node, "FloorVoidPart_%02d_%02d" % [room_id, i], slabs[i], floor_level_m))

	var smoke := _create_box("SmokeVolume", Vector3.ONE, _make_smoke_volume_material())
	smoke.visible = false
	_disable_shadow_casting(smoke)
	_atmosphere_root.add_child(smoke)

	var smoke_plume := _create_box("SmokePlume_%02d" % room_id, Vector3.ONE, _make_smoke_volume_material())
	smoke_plume.visible = false
	_disable_shadow_casting(smoke_plume)
	_atmosphere_root.add_child(smoke_plume)

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

	var gradient_band := _create_box("LayerGradient_%02d" % room_id, Vector3.ONE, _make_material(layer_gradient_top_color, true))
	gradient_band.visible = false
	_disable_shadow_casting(gradient_band)
	_atmosphere_root.add_child(gradient_band)

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
	fire_light.light_color = fire_light_color
	fire_light.light_energy = 0.0
	fire_light.omni_range = fire_light_range_min_m
	fire_light.omni_attenuation = fire_light_attenuation
	fire_light.shadow_enabled = fire_light_cast_shadows
	fire_light.position = Vector3(0.0, fire_light_height_m, 0.0)
	fire_root.add_child(fire_light)

	var label := shell.get("label") as Label3D

	var center_2d: Vector2 = rect_m.position + rect_m.size * 0.5
	var fed_label := Label3D.new()
	fed_label.name = "FedLabel_%02d" % room_id
	fed_label.text = ""
	fed_label.modulate = label_color
	fed_label.font_size = 40
	fed_label.pixel_size = 0.014
	fed_label.outline_size = 5
	fed_label.no_depth_test = false
	fed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fed_label.position = _to_world(Vector3(center_2d.x, floor_level_m + height_m * 0.68, center_2d.y))
	fed_label.visible = false
	if _labels_root != null:
		_labels_root.add_child(fed_label)

	var fuel_objects_root := Node3D.new()
	fuel_objects_root.name = "FuelObjects_%02d" % room_id
	_atmosphere_root.add_child(fuel_objects_root)

	var safety_markers_root := Node3D.new()
	safety_markers_root.name = "SafetyMarkers_%02d" % room_id
	_atmosphere_root.add_child(safety_markers_root)

	_room_items[room_id] = {
		"room_id": room_id,
		"rect": rect_m,
		"height_m": height_m,
		"floor_level_m": floor_level_m,
		"floor": floor,
		"floor_parts": floor_parts,
		"walls": walls,
		"smoke": smoke,
		"smoke_plume": smoke_plume,
		"smoke_puffs_root": smoke_puffs_root,
		"smoke_puffs": smoke_puffs,
		"smoke_ceiling_mask": smoke_ceiling_mask,
		"gradient_band": gradient_band,
		"hot": hot,
		"l150": l150,
		"fire_root": fire_root,
		"fire_glow": fire_glow,
		"fire_tongues": fire_tongues,
		"fire_cap": fire_cap,
		"fire_core": fire_core,
		"fire_light": fire_light,
		"label": label,
		"fed_label": fed_label,
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
		var stair_dir: Vector2 = _room_stair_run_direction(lower_room)
		if lower_room.stair_turn_degrees >= 179.0 and _stair_cross_span_m(rect, stair_dir) >= 1.65:
			_create_switchback_stair_visuals(stair_root, rect, lower_level_m, upper_level_m, stair_dir, lower_room.stair_has_railings)
			continue
		var steps: int = 14
		var start_margin_m: float = 0.22
		var run_m: float = maxf(0.8, _stair_long_span_m(rect, stair_dir) - start_margin_m - _stair_top_landing_depth_m(rect, stair_dir))
		var step_depth_m: float = run_m / float(steps)
		var step_width_m: float = _stair_ramp_width_m(rect, stair_dir)
		var rise_total_m: float = upper_level_m - lower_level_m
		var rise_m: float = rise_total_m / float(steps)
		var yaw: float = atan2(stair_dir.x, stair_dir.y)
		for i in range(steps):
			var step_h: float = rise_m * float(i + 1)
			var step_2d: Vector2 = _stair_point_along_run(rect, stair_dir, start_margin_m + step_depth_m * (float(i) + 0.5))
			var step := _create_box(
				"Step_%02d" % i,
				Vector3(step_width_m, maxf(0.04, step_h), step_depth_m * 0.92) * meters_to_units,
				_make_material(Color(0.38, 0.32, 0.25, 1.0), false)
			)
			step.position = _to_world(Vector3(step_2d.x, lower_level_m + step_h * 0.5, step_2d.y))
			step.rotation.y = yaw
			stair_root.add_child(step)
		if lower_room.stair_has_railings:
			var center_2d: Vector2 = _stair_point_along_run(rect, stair_dir, start_margin_m + run_m * 0.5)
			var normal := Vector2(-stair_dir.y, stair_dir.x)
			var half_width: float = step_width_m * 0.5 + 0.08
			var rail_angle: float = atan2(rise_total_m, run_m)
			var rail_length_m: float = sqrt(run_m * run_m + rise_total_m * rise_total_m)
			for side in [-1.0, 1.0]:
				var rail_2d: Vector2 = center_2d + normal * half_width * side
				var rail := _create_box(
					"Handrail",
					Vector3(0.055, 0.08, rail_length_m) * meters_to_units,
					_make_material(Color(0.18, 0.14, 0.10, 1.0), false)
				)
				rail.position = _to_world(Vector3(rail_2d.x, lower_level_m + rise_total_m * 0.5 + 0.82, rail_2d.y))
				rail.rotation.x = -rail_angle
				rail.rotation.y = yaw
				stair_root.add_child(rail)


func _create_switchback_stair_visuals(stair_root: Node3D, rect: Rect2, lower_level_m: float, upper_level_m: float, stair_dir: Vector2, has_railings: bool) -> void:
	var normal := Vector2(-stair_dir.y, stair_dir.x)
	var start_margin_m: float = 0.22
	var landing_depth_m: float = clampf(_stair_long_span_m(rect, stair_dir) * 0.18, 0.70, 0.95)
	var run_m: float = maxf(0.72, _stair_long_span_m(rect, stair_dir) - start_margin_m - landing_depth_m - 0.20)
	var gap_m: float = 0.18
	var flight_width_m: float = clampf((_stair_cross_span_m(rect, stair_dir) - gap_m) * 0.5, 0.72, 1.05)
	var rise_half_m: float = (upper_level_m - lower_level_m) * 0.5
	var lane_offset_m: float = flight_width_m * 0.5 + gap_m * 0.5
	var landing_distance_m: float = start_margin_m + run_m
	var flight_a_start: Vector2 = _stair_point_along_run(rect, stair_dir, start_margin_m) - normal * lane_offset_m
	var flight_b_start: Vector2 = _stair_point_along_run(rect, stair_dir, landing_distance_m) + normal * lane_offset_m
	_create_stair_visual_flight_segment(stair_root, "FlightA", flight_a_start, stair_dir, flight_width_m, run_m, lower_level_m, rise_half_m, has_railings)
	_create_stair_visual_flight_segment(stair_root, "FlightB", flight_b_start, -stair_dir, flight_width_m, run_m, lower_level_m + rise_half_m, rise_half_m, has_railings)
	var landing_center_2d: Vector2 = _stair_point_along_run(rect, stair_dir, landing_distance_m + landing_depth_m * 0.5)
	var landing_size: Vector3
	if absf(stair_dir.x) > absf(stair_dir.y):
		landing_size = Vector3(landing_depth_m, 0.12, flight_width_m * 2.0 + gap_m)
	else:
		landing_size = Vector3(flight_width_m * 2.0 + gap_m, 0.12, landing_depth_m)
	var landing := _create_box(
		"SwitchbackLanding",
		landing_size * meters_to_units,
		_make_material(Color(0.40, 0.33, 0.25, 1.0), false)
	)
	landing.position = _to_world(Vector3(landing_center_2d.x, lower_level_m + rise_half_m, landing_center_2d.y))
	stair_root.add_child(landing)


func _create_stair_visual_flight_segment(stair_root: Node3D, node_prefix: String, start_2d: Vector2, flight_dir: Vector2, width_m: float, run_m: float, lower_level_m: float, rise_m: float, has_railings: bool) -> void:
	var steps: int = 8
	var step_depth_m: float = run_m / float(steps)
	var yaw: float = atan2(flight_dir.x, flight_dir.y)
	for i in range(steps):
		var step_h: float = rise_m * float(i + 1) / float(steps)
		var step_2d: Vector2 = start_2d + flight_dir * (step_depth_m * (float(i) + 0.5))
		var step := _create_box(
			"%sStep_%02d" % [node_prefix, i],
			Vector3(width_m, maxf(0.04, step_h), step_depth_m * 0.90) * meters_to_units,
			_make_material(Color(0.38, 0.32, 0.25, 1.0), false)
		)
		step.position = _to_world(Vector3(step_2d.x, lower_level_m + step_h * 0.5, step_2d.y))
		step.rotation.y = yaw
		stair_root.add_child(step)
	if has_railings:
		var normal := Vector2(-flight_dir.y, flight_dir.x)
		var center_2d: Vector2 = start_2d + flight_dir * (run_m * 0.5)
		var rail_angle: float = atan2(rise_m, run_m)
		var rail_length_m: float = sqrt(run_m * run_m + rise_m * rise_m)
		for side in [-1.0, 1.0]:
			var rail_2d: Vector2 = center_2d + normal * (width_m * 0.5 + 0.08) * side
			var rail := _create_box(
				"%sHandrail" % node_prefix,
				Vector3(0.055, 0.08, rail_length_m) * meters_to_units,
				_make_material(Color(0.18, 0.14, 0.10, 1.0), false)
			)
			rail.position = _to_world(Vector3(rail_2d.x, lower_level_m + rise_m * 0.5 + 0.82, rail_2d.y))
			rail.rotation.x = -rail_angle
			rail.rotation.y = yaw
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


func _create_stairwell_upper_floor_visual(room_id: int, rect: Rect2, floor_level_m: float, parent: Node3D, stair_dir: Vector2, turn_degrees: float = 0.0) -> void:
	if parent == null:
		parent = _rooms_root
	var ramp_width_m: float = _stair_ramp_width_m(rect, stair_dir)
	var landing_depth_m: float = _stair_top_landing_depth_m(rect, stair_dir)
	var mat := _make_material(floor_color, false)
	if turn_degrees >= 179.0 and _stair_cross_span_m(rect, stair_dir) >= 1.65:
		_create_switchback_stairwell_upper_floor_visual(room_id, rect, floor_level_m, parent, stair_dir, mat)
		return

	if absf(stair_dir.x) > absf(stair_dir.y):
		var ramp_top_m: float = rect.position.y + rect.size.y * 0.5 - ramp_width_m * 0.5
		var ramp_bottom_m: float = ramp_top_m + ramp_width_m
		var top_height_m: float = maxf(0.0, ramp_top_m - rect.position.y)
		if top_height_m >= 0.28:
			_add_stairwell_floor_visual(parent, "StairSideFloorTop_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, rect.size.x, top_height_m), floor_level_m, mat)
		var bottom_height_m: float = maxf(0.0, rect.position.y + rect.size.y - ramp_bottom_m)
		if bottom_height_m >= 0.28:
			_add_stairwell_floor_visual(parent, "StairSideFloorBottom_%s" % str(room_id), Rect2(rect.position.x, ramp_bottom_m, rect.size.x, bottom_height_m), floor_level_m, mat)
		if landing_depth_m >= 0.28:
			var landing_x_m: float = rect.position.x + rect.size.x - landing_depth_m if stair_dir.x > 0.0 else rect.position.x
			_add_stairwell_floor_visual(parent, "StairTopLanding_%s" % str(room_id), Rect2(landing_x_m, rect.position.y, landing_depth_m, rect.size.y), floor_level_m, mat)
		return

	var ramp_left_m: float = rect.position.x + rect.size.x * 0.5 - ramp_width_m * 0.5
	var ramp_right_m: float = ramp_left_m + ramp_width_m
	var left_width_m: float = maxf(0.0, ramp_left_m - rect.position.x)
	if left_width_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairSideFloorLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y), floor_level_m, mat)

	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - ramp_right_m)
	if right_width_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairSideFloorRight_%s" % str(room_id), Rect2(ramp_right_m, rect.position.y, right_width_m, rect.size.y), floor_level_m, mat)

	if landing_depth_m >= 0.28:
		var landing_y_m: float = rect.position.y + rect.size.y - landing_depth_m if stair_dir.y > 0.0 else rect.position.y
		_add_stairwell_floor_visual(parent, "StairTopLanding_%s" % str(room_id), Rect2(rect.position.x, landing_y_m, rect.size.x, landing_depth_m), floor_level_m, mat)


func _create_switchback_stairwell_upper_floor_visual(room_id: int, rect: Rect2, floor_level_m: float, parent: Node3D, stair_dir: Vector2, mat: StandardMaterial3D) -> void:
	var gap_m: float = 0.18
	var cross_span_m: float = _stair_cross_span_m(rect, stair_dir)
	var flight_width_m: float = clampf((cross_span_m - gap_m) * 0.5, 0.72, 1.05)
	var shaft_width_m: float = minf(cross_span_m, flight_width_m * 2.0 + gap_m + 0.18)
	if absf(stair_dir.x) > absf(stair_dir.y):
		var shaft_top_m: float = rect.position.y + rect.size.y * 0.5 - shaft_width_m * 0.5
		var shaft_bottom_m: float = shaft_top_m + shaft_width_m
		var top_height_m: float = maxf(0.0, shaft_top_m - rect.position.y)
		if top_height_m >= 0.28:
			_add_stairwell_floor_visual(parent, "StairSwitchbackSideTop_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, rect.size.x, top_height_m), floor_level_m, mat)
		var bottom_height_m: float = maxf(0.0, rect.position.y + rect.size.y - shaft_bottom_m)
		if bottom_height_m >= 0.28:
			_add_stairwell_floor_visual(parent, "StairSwitchbackSideBottom_%s" % str(room_id), Rect2(rect.position.x, shaft_bottom_m, rect.size.x, bottom_height_m), floor_level_m, mat)
		return

	var shaft_left_m: float = rect.position.x + rect.size.x * 0.5 - shaft_width_m * 0.5
	var shaft_right_m: float = shaft_left_m + shaft_width_m
	var left_width_m: float = maxf(0.0, shaft_left_m - rect.position.x)
	if left_width_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairSwitchbackSideLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y), floor_level_m, mat)
	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - shaft_right_m)
	if right_width_m >= 0.28:
		_add_stairwell_floor_visual(parent, "StairSwitchbackSideRight_%s" % str(room_id), Rect2(shaft_right_m, rect.position.y, right_width_m, rect.size.y), floor_level_m, mat)


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


func _add_floor_void_part_visual(parent: Node3D, node_name: String, rect: Rect2, floor_level_m: float) -> MeshInstance3D:
	var slab := _create_box(
		node_name,
		Vector3(rect.size.x, floor_thickness_m, rect.size.y) * meters_to_units,
		_make_material(floor_color, false)
	)
	slab.position = _to_world(Vector3(
		rect.position.x + rect.size.x * 0.5,
		floor_level_m - floor_thickness_m * 0.5,
		rect.position.y + rect.size.y * 0.5
	))
	if parent != null:
		parent.add_child(slab)
	return slab


func _vertical_stair_voids_for_floor(floor_level_m: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if building == null:
		return result
	for raw_op in building.get_openings():
		var op := raw_op as OpeningModel
		if op == null or not op.is_vertical:
			continue
		var lower_room: RoomModel = building.get_room(op.a)
		var upper_room: RoomModel = building.get_room(op.b)
		if lower_room == null or upper_room == null:
			continue
		if upper_room.floor_level_z_m < lower_room.floor_level_z_m:
			var tmp := lower_room
			lower_room = upper_room
			upper_room = tmp
		if absf(upper_room.floor_level_z_m - floor_level_m) > 0.05:
			continue
		var rect: Rect2 = Rect2(building.room_rect_m.get(lower_room.id, Rect2()))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		result.append(_stair_vertical_void_rect(rect, _room_stair_run_direction(lower_room), lower_room.stair_turn_degrees))
	return result


func _stair_vertical_void_rect(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Rect2:
	return StairGeometry.vertical_void_rect(rect, stair_dir, turn_degrees)


func _split_rect_by_voids(rect: Rect2, voids: Array[Rect2]) -> Array[Rect2]:
	return StairGeometry.split_rect_by_voids(rect, voids)


func _subtract_rect(rect: Rect2, void_rect: Rect2) -> Array[Rect2]:
	return StairGeometry.subtract_rect(rect, void_rect)


func _rect_same(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= 0.001 and a.size.distance_to(b.size) <= 0.001


func _stair_long_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return StairGeometry.long_span_m(rect, stair_dir)


func _stair_cross_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return StairGeometry.cross_span_m(rect, stair_dir)


func _stair_ramp_width_m(rect: Rect2, stair_dir: Vector2 = Vector2.DOWN) -> float:
	return StairGeometry.ramp_width_m(rect, stair_dir)


func _stair_top_landing_depth_m(rect: Rect2, stair_dir: Vector2 = Vector2.DOWN) -> float:
	return StairGeometry.top_landing_depth_m(rect, stair_dir)


func _stair_point_along_run(rect: Rect2, stair_dir: Vector2, distance_from_entry_m: float) -> Vector2:
	return StairGeometry.point_along_run(rect, stair_dir, distance_from_entry_m)


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
	_opening_items[index] = {"marker": marker, "pose": pose}
	if op.type == OpeningModel.Type.DOOR and not op.is_vertical:
		_create_door_leaf_visual(index, op, pose, marker)
	if op.type == OpeningModel.Type.WINDOW:
		var pose_size: Vector3 = Vector3(pose["size"]) * meters_to_units
		var crack_mat := _make_material(Color(1.0, 0.95, 0.72, 0.95), true)
		var crack_h_size := Vector3(maxf(pose_size.x, 0.02) * 0.68, 0.025, 0.018) if pose_size.x >= pose_size.z else Vector3(0.018, 0.025, maxf(pose_size.z, 0.02) * 0.68)
		var crack_v_size := Vector3(0.025, maxf(pose_size.y, 0.02) * 0.58, 0.018) if pose_size.x >= pose_size.z else Vector3(0.018, maxf(pose_size.y, 0.02) * 0.58, 0.025)
		var crack_h := _create_box("BrokenGlassCrackH_%02d" % index, crack_h_size, crack_mat)
		var crack_v := _create_box("BrokenGlassCrackV_%02d" % index, crack_v_size, crack_mat)
		crack_h.visible = false
		crack_v.visible = false
		marker.add_child(crack_h)
		marker.add_child(crack_v)
		_opening_items[index]["broken_crack_h"] = crack_h
		_opening_items[index]["broken_crack_v"] = crack_v

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
		var inflow := _create_box(
			"AirInflowCurtain_%02d" % index,
			Vector3(pose["size"]) * meters_to_units,
			SmokeVolumeMaterialFactory.create_volume(cold_air_inflow_color)
		)
		inflow.position = marker.position
		inflow.visible = false
		_disable_shadow_casting(inflow)
		_atmosphere_root.add_child(inflow)
		_opening_items[index]["smoke_curtain"] = curtain
		_opening_items[index]["air_inflow_curtain"] = inflow
		_opening_items[index]["curtain_pose"] = pose


func _create_door_leaf_visual(index: int, op: OpeningModel, pose: Dictionary, marker: MeshInstance3D) -> void:
	if marker == null or op == null:
		return
	var pose_size: Vector3 = Vector3(pose["size"])
	var horizontal_wall: bool = pose_size.x >= pose_size.z
	var leaf_width_m: float = maxf(0.05, pose_size.x if horizontal_wall else pose_size.z)
	var leaf_height_m: float = maxf(0.10, pose_size.y)
	var leaf_thickness_m: float = maxf(0.028, opening_marker_depth_m * 0.46)
	var hinge_left: bool = op.hinge_side.strip_edges().to_lower() != "right"
	var axis_sign: float = 1.0 if hinge_left else -1.0

	var hinge_local := Vector3.ZERO
	var panel_local := Vector3.ZERO
	var panel_size := Vector3.ZERO
	var closed_dir := Vector2.ZERO
	if horizontal_wall:
		hinge_local.x = (-pose_size.x * 0.5 if hinge_left else pose_size.x * 0.5) * meters_to_units
		panel_local.x = axis_sign * leaf_width_m * 0.5 * meters_to_units
		panel_size = Vector3(leaf_width_m, leaf_height_m, leaf_thickness_m) * meters_to_units
		closed_dir = Vector2(axis_sign, 0.0)
	else:
		hinge_local.z = (-pose_size.z * 0.5 if hinge_left else pose_size.z * 0.5) * meters_to_units
		panel_local.z = axis_sign * leaf_width_m * 0.5 * meters_to_units
		panel_size = Vector3(leaf_thickness_m, leaf_height_m, leaf_width_m) * meters_to_units
		closed_dir = Vector2(0.0, axis_sign)

	var pivot := Node3D.new()
	pivot.name = "DoorLeafPivot_%02d" % index
	pivot.position = hinge_local
	pivot.set_meta("simufire_opening_index", index)
	pivot.set_meta("closed_dir_xz", closed_dir)
	pivot.set_meta("full_open_angle_rad", _door_leaf_full_open_angle(op, closed_dir, horizontal_wall))
	marker.add_child(pivot)

	var panel := _create_box("DoorLeaf_%02d" % index, panel_size, _make_material(door_color, true))
	panel.position = panel_local
	panel.set_meta("leaf_width_m", leaf_width_m)
	panel.set_meta("leaf_height_m", leaf_height_m)
	pivot.add_child(panel)

	_opening_items[index]["door_leaf_pivot"] = pivot
	_opening_items[index]["door_leaf_panel"] = panel
	_update_door_leaf_visual(_opening_items[index], op)


func _door_leaf_full_open_angle(op: OpeningModel, closed_dir: Vector2, horizontal_wall: bool) -> float:
	var normal: Vector2 = _door_swing_normal_xz(op, horizontal_wall)
	var angle: float = _signed_y_rotation_from_xz(closed_dir, normal)
	if is_zero_approx(angle):
		angle = -PI * 0.5 if op.hinge_side.strip_edges().to_lower() != "right" else PI * 0.5
	var max_angle: float = deg_to_rad(clampf(door_leaf_max_open_angle_deg, 30.0, 120.0))
	return (1.0 if angle >= 0.0 else -1.0) * minf(absf(angle), max_angle)


func _door_swing_normal_xz(op: OpeningModel, horizontal_wall: bool) -> Vector2:
	var normal := Vector2(0.0, 1.0) if horizontal_wall else Vector2(1.0, 0.0)
	match op.wall_side.strip_edges().to_lower():
		"top", "north":
			normal = Vector2(0.0, 1.0)
		"bottom", "south":
			normal = Vector2(0.0, -1.0)
		"left", "west":
			normal = Vector2(1.0, 0.0)
		"right", "east":
			normal = Vector2(-1.0, 0.0)
	if op.swing_direction.strip_edges().to_lower() == "out":
		normal = -normal
	return normal.normalized()


func _signed_y_rotation_from_xz(from_dir: Vector2, to_dir: Vector2) -> float:
	var from_n: Vector2 = from_dir.normalized()
	var to_n: Vector2 = to_dir.normalized()
	if from_n == Vector2.ZERO or to_n == Vector2.ZERO:
		return 0.0
	var cross: float = from_n.x * to_n.y - from_n.y * to_n.x
	var dot: float = clampf(from_n.dot(to_n), -1.0, 1.0)
	return -atan2(cross, dot)


func _create_exterior_context_visuals() -> void:
	if building == null or _rooms_root == null:
		return
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or not op.is_exterior_opening():
			continue
		var pose: Dictionary = _get_cached_opening_pose(index)
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
	var soft_color := Color(color.r, color.g, color.b, minf(color.a, 0.22))
	var backdrop_size := Vector3(2.8, 1.7, 0.05) if absf(normal.y) > 0.5 else Vector3(0.05, 1.7, 2.8)
	var panel := _create_box("%s_%02d" % [name_prefix, index], backdrop_size * meters_to_units, _make_material(soft_color, true))
	panel.position = _to_world(Vector3(center.x + normal.x * 1.65, center.y, center.z + normal.y * 1.65))
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
		if op.glass_broken:
			return window_broken_color
		return window_color
	if op.type == OpeningModel.Type.HOLE:
		return hole_color
	return door_color


func _get_cached_opening_pose(index: int) -> Dictionary:
	if _opening_items.has(index):
		var item: Dictionary = Dictionary(_opening_items[index])
		if item.has("pose"):
			return Dictionary(item["pose"])
	if building == null:
		return {}
	var op: OpeningModel = building.get_opening_at(index)
	if op == null:
		return {}
	return _opening_pose(op)


func _opening_pose(op: OpeningModel) -> Dictionary:
	if building == null:
		return {}
	var room_id: int = op.a if op.a != BuildingModel.OUTSIDE_ID else op.b
	var other_id: int = op.b if op.a == room_id else op.a
	var pose: Dictionary = OpeningPose3D.compute(op, building.get_room_rects_m(), BuildingModel.OUTSIDE_ID, opening_marker_depth_m)
	if not pose.is_empty():
		if op.is_vertical and other_id != BuildingModel.OUTSIDE_ID:
			var floor_a_m: float = _get_room_floor_level(op.a)
			var floor_b_m: float = _get_room_floor_level(op.b)
			var lower_room_id: int = op.a if floor_a_m <= floor_b_m else op.b
			var upper_room_id: int = op.b if lower_room_id == op.a else op.a
			var lower_floor_m: float = minf(floor_a_m, floor_b_m)
			var upper_floor_m: float = maxf(floor_a_m, floor_b_m)
			var marker_y_m: float = upper_floor_m - lower_floor_m
			if marker_y_m <= 0.20:
				marker_y_m = _get_room_height(lower_room_id)
			var position := Vector3(pose["position"])
			position.y = marker_y_m
			pose["position"] = position
			pose["floor_level_m"] = lower_floor_m
			pose["lower_room_id"] = lower_room_id
			pose["upper_room_id"] = upper_room_id
			pose["upper_floor_level_m"] = upper_floor_m
			pose["vertical_span_m"] = maxf(0.30, upper_floor_m - lower_floor_m)
		else:
			if other_id != BuildingModel.OUTSIDE_ID and absf(_get_room_floor_level(room_id) - _get_room_floor_level(other_id)) > 0.20:
				return {}
			pose["floor_level_m"] = _get_room_floor_level(room_id)
	return pose


func _update_dynamic_state() -> void:
	var update_fuel_objects: bool = _should_update_fuel_objects_this_pass()
	for room_id in _room_items.keys():
		_update_room(int(room_id), update_fuel_objects)
	_update_openings()
	_update_player_start_marker_3d()
	_apply_selection_visuals()


func _should_update_fuel_objects_this_pass() -> bool:
	if not _first_person_overlay:
		return true
	var interval_ms: int = int(maxf(0.0, fp_fuel_object_update_interval_s) * 1000.0)
	if interval_ms <= 0:
		return true
	var now_msec: int = Time.get_ticks_msec()
	if _last_fp_fuel_object_update_msec == 0 or now_msec - _last_fp_fuel_object_update_msec >= interval_ms:
		_last_fp_fuel_object_update_msec = now_msec
		return true
	return false


func _room_state_for_visuals(room_id: int) -> Dictionary:
	var raw_state: Variant = state.get(str(room_id), {})
	if typeof(raw_state) == TYPE_DICTIONARY:
		var room_state: Dictionary = raw_state
		if not room_state.is_empty():
			return room_state
	return _build_static_room_state(room_id)


func _build_static_room_state(room_id: int) -> Dictionary:
	if building == null:
		return {}
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return {}
	return {
		"id": room.id,
		"name": room.name,
		"kind": room.kind,
		"height_m": room.height_m,
		"hrr_kw": room.hrr_kw,
		"temp_upper_c": room.temp_upper_c,
		"smoke_kg": room.smoke_kg,
		"smoke_layer_m": room.h_layer_m,
		"smoke_display_layer_m": room.h_layer_m,
		"hot_layer_m": room.thermal_layer_m,
		"layer_150c_m": room.layer_150c_m,
		"visibility_m": room.visibility_m,
		"overpressure_pa": room.overpressure_pa,
		"fuel_objects": _build_static_fuel_object_snapshots(room)
	}


func _build_static_fuel_object_snapshots(room: RoomModel) -> Array:
	var snapshots: Array = []
	if room == null:
		return snapshots
	for obj in room.fuel_objects:
		if obj == null:
			continue
		snapshots.append({
			"id": String(obj.id),
			"name": String(obj.name),
			"kind": String(obj.kind),
			"room_id": int(obj.room_id),
			"position_m": obj.position_m,
			"size_m": obj.size_m,
			"rotation_deg": float(obj.rotation_deg),
			"visual_pose_locked": bool(obj.visual_pose_locked),
			"elevation_m": float(obj.elevation_m),
			"fuel_energy_MJ": maxf(0.0, obj.fuel_energy_MJ),
			"remaining_fuel_MJ": maxf(0.0, obj.remaining_fuel_MJ),
			"max_hrr_kw": maxf(0.0, obj.max_hrr_kw),
			"hrr_kw": maxf(0.0, obj.hrr_kw),
			"state": _fuel_object_state_name(int(obj.state)),
			"is_primary_ignition_source": bool(obj.is_primary_ignition_source)
		})
	return snapshots


func _fuel_object_state_name(state_id: int) -> String:
	match state_id:
		FuelObjectModel.State.HEATING:
			return "heating"
		FuelObjectModel.State.PYROLYZING:
			return "pyrolyzing"
		FuelObjectModel.State.FLAMING:
			return "flaming"
		FuelObjectModel.State.DECAYING:
			return "decaying"
		FuelObjectModel.State.BURNED_OUT:
			return "burned_out"
		_:
			return "cold"


func _update_room(room_id: int, update_fuel_objects: bool = true) -> void:
	var item: Dictionary = _room_items[room_id]
	var rect := Rect2(item["rect"])
	var height_m: float = float(item["height_m"])
	var rs: Dictionary = _room_state_for_visuals(room_id)
	if rs.is_empty():
		return

	var floor := item["floor"] as MeshInstance3D
	var walls: Array = item.get("walls", [])
	var smoke := item["smoke"] as MeshInstance3D
	var gradient_band := item.get("gradient_band") as MeshInstance3D
	var hot := item["hot"] as MeshInstance3D
	var l150 := item["l150"] as MeshInstance3D
	var label := item["label"] as Label3D
	var fed_label := item.get("fed_label") as Label3D
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))

	var temp_upper_c: float = float(rs.get("temp_upper_c", 20.0))
	var smoke_kg: float = float(rs.get("smoke_kg", 0.0))
	var smoke_layer_m: float = clampf(float(rs.get("smoke_display_layer_m", rs.get("smoke_layer_m", rs.get("h_layer_m", height_m)))), 0.0, height_m)
	var hot_layer_m: float = clampf(float(rs.get("hot_layer_m", rs.get("thermal_layer_m", height_m))), 0.0, height_m)
	var layer_150c_m: float = clampf(float(rs.get("layer_150c_m", height_m)), 0.0, height_m)
	var hrr_kw: float = maxf(0.0, float(rs.get("hrr_kw", 0.0)))
	var visibility_m: float = float(rs.get("visibility_m", 30.0))
	item["kind"] = String(rs.get("kind", ""))
	item["temp_upper_c"] = temp_upper_c
	item["overpressure_pa"] = float(rs.get("overpressure_pa", 0.0))
	item["visibility_m"] = visibility_m
	item["hrr_kw"] = hrr_kw

	var heat_t: float = clampf(
		inverse_lerp(temp_heat_floor_start_c, temp_heat_floor_full_c, temp_upper_c),
		0.0,
		1.0
	)
	var floor_display_color: Color = _selection_tinted_room_color(room_id, floor_color.lerp(hot_floor_color, heat_t))
	_apply_floor_color(floor, floor_display_color)
	for raw_part in Array(item.get("floor_parts", [])):
		_apply_floor_color(raw_part as MeshInstance3D, floor_display_color)
	if show_wall_heatmap:
		_update_wall_temperature(walls, temp_upper_c)
	else:
		_update_wall_temperature(walls, 20.0)

	_update_smoke_volume(item, smoke, rect, height_m, smoke_layer_m, smoke_kg, hrr_kw, visibility_m)
	if gradient_band != null:
		var grad_depth_m: float = maxf(0.0, height_m - smoke_layer_m)
		var grad_visible: bool = show_layer_gradient and smoke_kg > smoke_visible_threshold_kg and grad_depth_m > 0.05
		SmokeLayerVisuals.update_layer_box(
			gradient_band,
			rect,
			height_m,
			smoke_layer_m,
			layer_gradient_top_color,
			grad_visible,
			room_inset_m,
			meters_to_units,
			_origin_offset_m,
			floor_level_m
		)
		if grad_visible and gradient_band.material_override != null:
			var mat := gradient_band.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = layer_gradient_top_color
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

	if fed_label != null:
		var max_fed: float = 0.0
		for raw_vic in Array(state.get("victims", [])):
			if typeof(raw_vic) == TYPE_DICTIONARY:
				var vic: Dictionary = raw_vic
				if int(vic.get("room_id", -1)) == room_id:
					max_fed = maxf(max_fed, float(vic.get("fed", 0.0)))
		if show_fed_labels and max_fed > 0.0:
			fed_label.text = "FED %.2f" % max_fed
			if max_fed >= 1.0:
				fed_label.modulate = fed_label_danger_color
			elif max_fed >= 0.3:
				fed_label.modulate = fed_label_warn_color
			else:
				fed_label.modulate = label_color
			fed_label.visible = true
		else:
			fed_label.visible = false

	if update_fuel_objects:
		_update_room_fuel_objects_3d(item, rs, rect)
	else:
		_sync_room_fuel_objects_3d_visibility(item)
	_update_room_safety_markers_3d(room_id, item, rect)


func _sync_room_fuel_objects_3d_visibility(item: Dictionary) -> void:
	var fuel_objects_root := item.get("fuel_objects_root") as Node3D
	if fuel_objects_root == null:
		return
	fuel_objects_root.visible = show_fuel_objects_3d \
		and (not _first_person_overlay or show_fuel_objects_in_first_person) \
		and fuel_objects_root.get_child_count() > 0


func _update_room_selection_visuals() -> void:
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		var floor := item.get("floor") as MeshInstance3D
		var display_color: Color = _selection_tinted_room_color(int(room_id), _room_base_floor_color(int(room_id)))
		_apply_floor_color(floor, display_color)
		for raw_part in Array(item.get("floor_parts", [])):
			_apply_floor_color(raw_part as MeshInstance3D, display_color)
		var label := item.get("label") as Label3D
		if label != null:
			label.modulate = selection_highlight_color if int(room_id) == _selected_room_id else label_color


func _apply_floor_color(floor_node: MeshInstance3D, color: Color) -> void:
	if floor_node == null:
		return
	var mat := floor_node.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color


func _apply_selection_visuals() -> void:
	_update_room_selection_visuals()
	_update_fuel_object_selection_visuals()
	_update_safety_marker_selection_visuals()


func _has_selection() -> bool:
	return _selected_room_id >= 0 \
		or _selected_opening_index >= 0 \
		or _selected_object_id != "" \
		or _selected_detector_id != "" \
		or _selected_victim_id != "" \
		or _selected_player_start


func screen_to_floor_m(screen_pos: Vector2) -> Variant:
	return ScreenPicking3D.floor_hit_m(_camera, screen_pos, meters_to_units, _origin_offset_m)


func _screen_to_floor_at_level(screen_pos: Vector2, floor_level_m: float) -> Variant:
	return ScreenPicking3D.floor_hit_at_level(_camera, screen_pos, meters_to_units, _origin_offset_m, floor_level_m)


func _begin_element_drag(kind: String, element_id: String, room_id: int, screen_pos: Vector2) -> void:
	if not allow_element_drag:
		return
	var level_m: float = 0.0
	if room_id >= 0:
		level_m = _get_room_floor_level(room_id)
	else:
		var node: Node3D = null
		match kind:
			"detector", "victim":
				node = _safety_marker_node(kind, element_id)
			"player_start":
				node = _player_start_node
		if node != null:
			level_m = node.global_position.y / maxf(0.0001, meters_to_units)
	var floor_hit: Variant = _screen_to_floor_at_level(screen_pos, level_m)
	if typeof(floor_hit) != TYPE_VECTOR2:
		return
	var element_pos: Variant = _element_floor_position_m(kind, element_id, room_id)
	if typeof(element_pos) != TYPE_VECTOR2:
		return
	_dragging_element_kind = kind
	_dragging_element_id = element_id
	_dragging_element_room_id = room_id
	_drag_floor_level_m = level_m
	_drag_floor_offset_m = Vector2(element_pos) - Vector2(floor_hit)
	_drag_start_floor_pos_m = Vector2(element_pos)
	_drag_started_emitted = false


func _update_element_drag(screen_pos: Vector2) -> void:
	if not _is_element_dragging():
		return
	var floor_hit: Variant = _screen_to_floor_at_level(screen_pos, _drag_floor_level_m)
	if typeof(floor_hit) != TYPE_VECTOR2:
		return
	var next_floor_pos_m: Vector2 = Vector2(floor_hit) + _drag_floor_offset_m
	if not _drag_started_emitted:
		if next_floor_pos_m.distance_to(_drag_start_floor_pos_m) < 0.03:
			return
		_drag_started_emitted = true
		element_drag_started.emit(_dragging_element_kind)
	_move_dragged_element_preview(next_floor_pos_m)
	match _dragging_element_kind:
		"object":
			object_dragged.emit(_dragging_element_room_id, _dragging_element_id, next_floor_pos_m)
		"detector":
			detector_dragged.emit(_dragging_element_id, next_floor_pos_m)
		"victim":
			victim_dragged.emit(_dragging_element_id, next_floor_pos_m)
		"player_start":
			player_start_dragged.emit(next_floor_pos_m)


func _finish_element_drag() -> void:
	if _drag_started_emitted:
		element_drag_ended.emit(_dragging_element_kind)
	_clear_element_drag()


func _clear_element_drag() -> void:
	_dragging_element_kind = ""
	_dragging_element_id = ""
	_dragging_element_room_id = -1
	_drag_floor_offset_m = Vector2.ZERO
	_drag_start_floor_pos_m = Vector2.ZERO
	_drag_started_emitted = false


func _is_element_dragging() -> bool:
	return _dragging_element_kind != "" and _dragging_element_id != ""


func _element_floor_position_m(kind: String, element_id: String, room_id: int) -> Variant:
	var node: Node3D = null
	match kind:
		"object":
			node = _fuel_object_node(room_id, element_id)
		"detector", "victim":
			node = _safety_marker_node(kind, element_id)
		"player_start":
			node = _player_start_node
	if node == null:
		return null
	return _node_floor_position_m(node)


func _move_dragged_element_preview(floor_pos_m: Vector2) -> void:
	var node: Node3D = null
	match _dragging_element_kind:
		"object":
			node = _fuel_object_node(_dragging_element_room_id, _dragging_element_id)
		"detector", "victim":
			node = _safety_marker_node(_dragging_element_kind, _dragging_element_id)
		"player_start":
			node = _player_start_node
	if node == null:
		return
	var next_pos: Vector3 = _to_world(Vector3(floor_pos_m.x, 0.0, floor_pos_m.y))
	var current_global: Vector3 = node.global_position
	current_global.x = next_pos.x
	current_global.z = next_pos.z
	node.global_position = current_global


func _fuel_object_node(room_id: int, object_id: String) -> Node3D:
	if not _room_items.has(room_id):
		return null
	var item: Dictionary = _room_items[room_id]
	var fuel_obj_nodes: Dictionary = item.get("fuel_obj_nodes", {})
	return fuel_obj_nodes.get(object_id) as Node3D


func _safety_marker_node(kind: String, marker_id: String) -> Node3D:
	var nodes_key: String = "detector_nodes" if kind == "detector" else "victim_nodes"
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		var marker_nodes: Dictionary = item.get(nodes_key, {})
		if marker_nodes.has(marker_id):
			return marker_nodes.get(marker_id) as Node3D
	return null


func _node_floor_position_m(node: Node3D) -> Vector2:
	return Vector2(
		node.global_position.x / maxf(0.0001, meters_to_units) - _origin_offset_m.x,
		node.global_position.z / maxf(0.0001, meters_to_units) - _origin_offset_m.y
	)


func _fuel_object_at_screen_pos(screen_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = 999999.0
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		var fuel_obj_nodes: Dictionary = item.get("fuel_obj_nodes", {})
		for object_id in fuel_obj_nodes.keys():
			var node := fuel_obj_nodes[object_id] as Node3D
			var distance: float = _node_screen_distance(node, screen_pos)
			if distance < best_distance:
				best_distance = distance
				best = {
					"room_id": int(room_id),
					"object_id": String(object_id)
				}
	return best if best_distance <= 34.0 else {}


func _safety_marker_at_screen_pos(screen_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = 999999.0
	for _room_id in _room_items.keys():
		var item: Dictionary = _room_items[_room_id]
		var detector_nodes: Dictionary = item.get("detector_nodes", {})
		for detector_id in detector_nodes.keys():
			var detector_node := detector_nodes[detector_id] as Node3D
			var det_distance: float = _node_screen_distance(detector_node, screen_pos)
			if det_distance < best_distance:
				best_distance = det_distance
				best = {"type": "detector", "id": String(detector_id)}
		var victim_nodes: Dictionary = item.get("victim_nodes", {})
		for victim_id in victim_nodes.keys():
			var victim_node := victim_nodes[victim_id] as Node3D
			var vic_distance: float = _node_screen_distance(victim_node, screen_pos)
			if vic_distance < best_distance:
				best_distance = vic_distance
				best = {"type": "victim", "id": String(victim_id)}
	return best if best_distance <= 32.0 else {}


func _player_start_at_screen_pos(screen_pos: Vector2) -> Dictionary:
	if _player_start_node == null or not _player_start_node.is_visible_in_tree() or building == null:
		return {}
	var distance: float = _node_screen_distance(_player_start_node, screen_pos)
	if distance > 34.0:
		return {}
	return {
		"room_id": int(building.player_start.get("room_id", -1))
	}


func _node_screen_distance(node: Node3D, screen_pos: Vector2) -> float:
	if _camera == null or node == null or not node.is_visible_in_tree():
		return 999999.0
	if _camera.is_position_behind(node.global_position):
		return 999999.0
	return _camera.unproject_position(node.global_position).distance_to(screen_pos)


func _room_base_floor_color(room_id: int) -> Color:
	var rs: Dictionary = state.get(str(room_id), {})
	if rs.is_empty():
		return floor_color
	var temp_upper_c: float = float(rs.get("temp_upper_c", 20.0))
	var heat_t: float = clampf(
		inverse_lerp(temp_heat_floor_start_c, temp_heat_floor_full_c, temp_upper_c),
		0.0,
		1.0
	)
	return floor_color.lerp(hot_floor_color, heat_t)


func _selection_tinted_room_color(room_id: int, base_color: Color) -> Color:
	if room_id != _selected_room_id:
		return base_color
	return base_color.lerp(Color(1.0, 0.88, 0.18, 1.0), 0.52)


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
	if smoke_kg <= smoke_visible_threshold_kg and visibility_m >= smoke_dense_visibility_m:
		target_depth_m = 0.0
	var hrr_smoke_t: float = clampf(sqrt(maxf(0.0, hrr_kw) / maxf(1.0, smoke_hrr_reference_kw)), 0.0, 1.0)
	if hrr_kw > fire_min_visible_hrr_kw:
		target_depth_m = maxf(target_depth_m, smoke_hrr_depth_boost_m * hrr_smoke_t)
	target_depth_m = clampf(target_depth_m, 0.0, height_m)

	var target_optics: Dictionary = _smoke_optical_terms(rect, height_m, target_depth_m, smoke_kg, visibility_m, hrr_smoke_t)
	var visibility_t: float = maxf(
		clampf((28.0 - visibility_m) / 28.0, 0.0, 1.0),
		float(target_optics.get("visibility_t", 0.0))
	)
	var density_t: float = float(target_optics.get("density_t", 0.0))
	var layer_depth_t: float = float(target_optics.get("layer_depth_t", 0.0))
	var mass_t: float = float(target_optics.get("mass_t", 0.0))
	var alpha_cap: float = 0.86 if _first_person_overlay else 0.70
	var alpha_floor: float = 0.08 if target_depth_m > smoke_min_visible_depth_m else 0.0
	var alpha: float = clampf(
		smoke_color.a * 0.22
			+ mass_t * (0.30 if _first_person_overlay else 0.22)
			+ density_t * (0.30 if _first_person_overlay else 0.25)
			+ visibility_t * (0.36 if _first_person_overlay else 0.28)
			+ layer_depth_t * (0.16 if _first_person_overlay else 0.12)
			+ hrr_smoke_t * smoke_hrr_alpha_boost * 0.96,
		alpha_floor,
		alpha_cap
	)
	item["smoke_physics_depth_m"] = target_depth_m
	item["smoke_physics_bottom_m"] = height_m - target_depth_m
	item["smoke_physics_alpha"] = alpha if target_depth_m > smoke_min_visible_depth_m else 0.0
	var spill: Dictionary = _same_floor_opening_smoke_spill_for_room(int(item.get("room_id", -1)), height_m)
	if not spill.is_empty():
		target_depth_m = maxf(target_depth_m, float(spill.get("depth_m", 0.0)))
		hrr_smoke_t = maxf(hrr_smoke_t, float(spill.get("heat_t", 0.0)) * 0.48)
		alpha = maxf(alpha, float(spill.get("alpha", 0.0)))
	item["smoke_heat_t"] = hrr_smoke_t
	item["smoke_visibility_t"] = visibility_t

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
		and current_depth_m > maxf(0.16, smoke_min_visible_depth_m * 2.6) \
		and alpha > 0.105 \
		and (not _first_person_overlay or show_smoke_puffs_in_first_person)
	node.visible = smoke_geometry_visible
	var current_optics: Dictionary = _smoke_optical_terms(rect, height_m, current_depth_m, smoke_kg, visibility_m, hrr_smoke_t)
	var smoke_light_transmission: float = _smoke_light_transmission_from_terms(current_optics)
	item["smoke_light_transmission"] = smoke_light_transmission
	var mask_alpha: float = clampf(
		0.025 + float(current_optics.get("optical_t", 0.0)) * smoke_ceiling_mask_max_alpha * (0.86 if _first_person_overlay else 1.0),
		0.0,
		smoke_ceiling_mask_max_alpha
	)
	var ceiling_mask := item.get("smoke_ceiling_mask") as MeshInstance3D
	SmokeLayerVisuals.update_ceiling_mask(
		ceiling_mask,
		rect,
		height_m,
		show_smoke_volume \
			and show_smoke_ceiling_masks \
			and current_depth_m > smoke_min_visible_depth_m \
			and (not _first_person_overlay or show_smoke_geometry_in_first_person),
		room_inset_m,
		meters_to_units,
		mask_alpha,
		Color(smoke_color.r, smoke_color.g, smoke_color.b, 1.0),
		-0.026 if _first_person_overlay else 0.004,
		_origin_offset_m,
		floor_level_m
	)

	var render_depth_m: float = maxf(
		smoke_min_visible_depth_m,
		current_depth_m - (0.045 if _first_person_overlay else 0.018)
	)
	var smoke_mat := node.material_override as ShaderMaterial
	if smoke_mat != null:
		_apply_smoke_volume_shader(smoke_mat, alpha, visibility_t, hrr_smoke_t, render_depth_m)
	else:
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(smoke_color.r, smoke_color.g, smoke_color.b, alpha * 0.48)

	var visual_bottom_m: float = height_m - current_depth_m
	item["smoke_bottom_m"] = visual_bottom_m
	item["smoke_alpha"] = alpha if smoke_geometry_visible else 0.0

	if smoke_geometry_visible:
		var room_smoke_width_m: float = maxf(0.05, rect.size.x - room_inset_m * 2.0)
		var room_smoke_depth_m: float = maxf(0.05, rect.size.y - room_inset_m * 2.0)
		var mesh := node.mesh as BoxMesh
		if mesh != null:
			mesh.size = Vector3(room_smoke_width_m, render_depth_m, room_smoke_depth_m) * meters_to_units
		node.position = _room_center(rect, visual_bottom_m + render_depth_m * 0.5, floor_level_m)

	var puffs_root := item.get("smoke_puffs_root") as Node3D
	if puffs_root != null:
		puffs_root.visible = smoke_puffs_visible


func _smoke_optical_terms(
	rect: Rect2,
	height_m: float,
	smoke_depth_m: float,
	smoke_kg: float,
	visibility_m: float,
	hrr_smoke_t: float
) -> Dictionary:
	var depth_m: float = clampf(smoke_depth_m, 0.0, maxf(0.0, height_m))
	var layer_depth_t: float = clampf(depth_m / maxf(0.10, height_m), 0.0, 1.0)
	var area_m2: float = maxf(0.05, rect.size.x * rect.size.y)
	var upper_volume_m3: float = maxf(0.05, area_m2 * maxf(depth_m, 0.05))
	var smoke_concentration_kg_m3: float = smoke_kg / upper_volume_m3 if smoke_kg > 0.0 and depth_m > 0.0 else 0.0
	var density_t: float = clampf(
		smoke_concentration_kg_m3 / maxf(0.001, smoke_density_reference_kg_m3),
		0.0,
		1.0
	)
	var dense_visibility_m: float = maxf(0.10, smoke_dense_visibility_m)
	var visibility_t: float = clampf((dense_visibility_m - visibility_m) / dense_visibility_m, 0.0, 1.0)
	var mass_t: float = clampf(smoke_kg / maxf(0.01, smoke_reference_kg), 0.0, 1.0)
	var optical_t: float = clampf(
		maxf(visibility_t, density_t * 0.90) * lerpf(0.34, 1.0, layer_depth_t)
			+ layer_depth_t * 0.20
			+ mass_t * 0.12
			+ hrr_smoke_t * 0.08,
		0.0,
		1.0
	)
	return {
		"layer_depth_t": layer_depth_t,
		"density_t": density_t,
		"visibility_t": visibility_t,
		"mass_t": mass_t,
		"optical_t": optical_t,
		"smoke_concentration_kg_m3": smoke_concentration_kg_m3,
	}


func _smoke_light_transmission_from_terms(optics: Dictionary) -> float:
	var blocked: float = clampf(
		float(optics.get("optical_t", 0.0)) * 0.86
			+ float(optics.get("density_t", 0.0)) * 0.16
			+ float(optics.get("layer_depth_t", 0.0)) * 0.20,
		0.0,
		1.0
	)
	return clampf(1.0 - blocked, smoke_light_min_transmission, 1.0)


func _same_floor_opening_smoke_spill_for_room(room_id: int, height_m: float) -> Dictionary:
	if building == null or room_id < 0:
		return {}
	var target_floor_m: float = _get_room_floor_level(room_id)
	var best_depth_m: float = 0.0
	var best_alpha: float = 0.0
	var best_heat_t: float = 0.0

	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or op.is_closed() or op.is_vertical or op.is_exterior_opening():
			continue
		if op.a != room_id and op.b != room_id:
			continue
		var source_id: int = op.b if op.a == room_id else op.a
		if source_id < 0 or not _room_items.has(source_id):
			continue
		if absf(_get_room_floor_level(source_id) - target_floor_m) > 0.20:
			continue

		var source_item: Dictionary = Dictionary(_room_items[source_id])
		var source_alpha: float = float(source_item.get("smoke_physics_alpha", source_item.get("smoke_alpha", 0.0)))
		if source_alpha <= smoke_color.a * 0.35:
			continue

		var source_height_m: float = float(source_item.get("height_m", height_m))
		var source_bottom_m: float = clampf(
			float(source_item.get("smoke_physics_bottom_m", source_item.get("smoke_bottom_m", source_height_m))),
			0.0,
			source_height_m
		)
		var source_depth_m: float = maxf(0.0, source_height_m - source_bottom_m)
		if source_depth_m <= smoke_min_visible_depth_m:
			continue

		var pose: Dictionary = _get_cached_opening_pose(index)
		if pose.is_empty():
			continue
		var pose_size: Vector3 = Vector3(pose["size"])
		var pos3: Vector3 = Vector3(pose["position"])
		var opening_bottom_m: float = pos3.y - pose_size.y * 0.5
		var opening_top_m: float = pos3.y + pose_size.y * 0.5
		var neutral_plane_m: float = lerpf(opening_bottom_m, opening_top_m, 0.56)
		var pass_depth_m: float = opening_top_m - maxf(source_bottom_m, neutral_plane_m)
		if pass_depth_m <= smoke_min_visible_depth_m:
			continue

		var open_frac: float = op.effective_open_fraction()
		var source_temp_c: float = float(source_item.get("temp_upper_c", 20.0))
		var source_hrr_kw: float = maxf(0.0, float(source_item.get("hrr_kw", 0.0)))
		var heat_t: float = clampf(
			maxf((source_temp_c - 35.0) / 360.0, sqrt(source_hrr_kw / 1500.0)),
			0.0,
			1.0
		)
		var candidate_depth_m: float = clampf(
			maxf(pass_depth_m * 1.12, source_depth_m * 0.42) * lerpf(0.45, 1.0, open_frac),
			0.0,
			height_m * 0.62
		)
		var candidate_alpha: float = clampf(
			source_alpha * (0.36 + heat_t * 0.30) * open_frac,
			0.0,
			0.34 if _first_person_overlay else 0.26
		)
		if candidate_depth_m > best_depth_m:
			best_depth_m = candidate_depth_m
		if candidate_alpha > best_alpha:
			best_alpha = candidate_alpha
		if heat_t > best_heat_t:
			best_heat_t = heat_t

	if best_depth_m <= smoke_min_visible_depth_m or best_alpha <= 0.018:
		return {}
	return {
		"depth_m": best_depth_m,
		"alpha": best_alpha,
		"heat_t": best_heat_t,
	}


func _apply_smoke_volume_shader(
	smoke_mat: ShaderMaterial,
	alpha: float,
	visibility_t: float,
	hrr_smoke_t: float,
	render_depth_m: float
) -> void:
	var volume_alpha_scale: float = 2.10 if _first_person_overlay else 1.32
	var volume_density: float = clampf(
		0.92 + alpha * 1.90 + visibility_t * 0.38,
		0.78,
		2.05
	) if _first_person_overlay else clampf(
		0.66 + alpha * 1.62 + visibility_t * 0.24,
		0.52,
		1.48
	)
	_set_smoke_shader_params(smoke_mat, {
		"smoke_color": Color(smoke_color.r, smoke_color.g, smoke_color.b, clampf(alpha * volume_alpha_scale, 0.0, 0.98)),
		"density": volume_density,
		"turbulence": clampf(0.58 + hrr_smoke_t * 0.34, 0.50, 0.95),
		"drift_speed": 0.045 + hrr_smoke_t * 0.13,
		"volume_depth_m": maxf(render_depth_m, 0.05),
		"edge_softness": lerpf(0.28, 0.48, hrr_smoke_t) if _first_person_overlay else lerpf(0.22, 0.38, hrr_smoke_t),
		"bottom_waviness": lerpf(0.16, 0.34, hrr_smoke_t) if _first_person_overlay else lerpf(0.12, 0.28, hrr_smoke_t),
		"edge_band_strength": 0.24 if _first_person_overlay else 0.20,
		"side_visibility": 0.0 if _first_person_overlay else 0.34,
		"bottom_surface_strength": 0.46 if _first_person_overlay else 0.38,
		"top_visibility": 0.08 if _first_person_overlay else 0.03,
		"vertical_gradient_strength": 0.82 if _first_person_overlay else 0.90,
		"lower_density_floor": 0.18 if _first_person_overlay else 0.10,
		"flow_strength": hrr_smoke_t * (0.16 if _first_person_overlay else 0.11),
		"flow_speed": 0.18 + hrr_smoke_t * 0.15,
	})


func _set_smoke_shader_params(material: ShaderMaterial, params: Dictionary) -> void:
	for key in params.keys():
		material.set_shader_parameter(String(key), params[key])


func _update_fire_visual(item: Dictionary, rect: Rect2, room_height_m: float, hrr_kw: float, rs: Dictionary = {}) -> void:
	var fire_root := item.get("fire_root") as Node3D
	if fire_root == null:
		return
	var anchor: Dictionary = _find_fire_anchor(item, rect, rs)
	var has_fire_anchor: bool = not anchor.is_empty()
	var fire_pos: Vector3 = Vector3(anchor.get("position", _room_center(rect, 0.0)))
	var fire_base_y_m: float = float(anchor.get("base_y_m", 0.0))
	var source_radius_m: float = float(anchor.get("radius_m", fire_base_radius_m))
	var available_height_m: float = maxf(0.24, room_height_m - fire_base_y_m - fire_ceiling_clearance_m)
	var target_height: float = 0.0
	var target_radius: float = fire_base_radius_m
	var target_cap_radius: float = 0.0
	var target_cap_weight: float = 0.0
	if has_fire_anchor and show_hrr_columns and hrr_kw > fire_min_visible_hrr_kw:
		var fire_t: float = clampf(hrr_kw / maxf(1.0, hrr_reference_kw), 0.0, 1.8)
		var ceiling_height_m: float = maxf(0.16, available_height_m * fire_max_height_fraction)
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

	fire_root.visible = current_height > 0.05 and (not _first_person_overlay or show_fire_in_first_person)
	fire_root.position = fire_pos
	_update_fire_smoke_plume(item, fire_pos, fire_base_y_m, room_height_m, hrr_kw, current_radius)
	var fire_light := item.get("fire_light") as OmniLight3D
	if fire_light != null:
		# Misma ley de potencia HRR -> luz que en FP (ver FirstPersonController).
		var hrr_ratio: float = maxf(0.0, hrr_kw) / 1000.0
		var smoke_transmission: float = maxf(
			float(item.get("smoke_light_transmission", 1.0)),
			fire_light_min_transmission
		)
		var target_energy: float = 0.0
		if fire_root.visible and hrr_ratio > 0.0:
			target_energy = fire_light_energy_per_1000kw \
				* pow(minf(hrr_ratio, 4.0), fire_light_energy_exponent) \
				* smoke_transmission
		item["fire_light_energy_target"] = target_energy
		fire_light.light_energy = target_energy
		fire_light.omni_range = clampf(
			fire_light_range_at_1mw_m * sqrt(maxf(0.0, hrr_ratio)),
			fire_light_range_min_m,
			fire_light_range_max_m
		) * lerpf(0.70, 1.0, smoke_transmission)
		fire_light.position.y = maxf(0.35, minf(available_height_m - 0.10, current_height * 0.45 + 0.45)) * meters_to_units
	if fire_root.visible:
		_animate_fire_item(item)


func _update_fire_smoke_plume(
	item: Dictionary,
	fire_pos: Vector3,
	fire_base_y_m: float,
	room_height_m: float,
	hrr_kw: float,
	fire_radius_m: float
) -> void:
	var plume := item.get("smoke_plume") as MeshInstance3D
	if plume == null:
		return
	if not show_fire_smoke_plume:
		plume.visible = false
		return
	var hrr_t: float = clampf(sqrt(maxf(0.0, hrr_kw) / maxf(1.0, smoke_hrr_reference_kw)), 0.0, 1.0)
	var smoke_alpha_room: float = float(item.get("smoke_alpha", 0.0))
	if not show_smoke_volume or hrr_kw <= fire_min_visible_hrr_kw or (hrr_t <= 0.035 and smoke_alpha_room <= 0.04):
		plume.visible = false
		return

	var floor_level_m: float = float(item.get("floor_level_m", 0.0))
	var smoke_bottom_m: float = clampf(float(item.get("smoke_bottom_m", room_height_m)), 0.0, room_height_m)
	var start_m: float = clampf(fire_base_y_m + 0.14, 0.05, room_height_m - 0.16)
	var target_top_m: float = minf(room_height_m - 0.08, maxf(smoke_bottom_m + 0.12, start_m + 0.36))
	var plume_height_m: float = maxf(0.0, target_top_m - start_m)
	if plume_height_m <= 0.18:
		plume.visible = false
		return

	var plume_width_m: float = clampf(fire_radius_m * lerpf(1.35, 2.20, hrr_t), 0.22, 1.35)
	var plume_depth_m: float = plume_width_m * lerpf(0.78, 1.08, hrr_t)
	var plume_mesh := plume.mesh as BoxMesh
	if plume_mesh != null:
		plume_mesh.size = Vector3(plume_width_m, plume_height_m, plume_depth_m) * meters_to_units
	plume.position = Vector3(
		fire_pos.x,
		(floor_level_m + start_m + plume_height_m * 0.5) * meters_to_units,
		fire_pos.z
	)
	plume.visible = true

	var plume_alpha: float = clampf(0.055 + smoke_alpha_room * 0.34 + hrr_t * 0.12, 0.04, 0.22)
	var plume_shader := plume.material_override as ShaderMaterial
	if plume_shader != null:
		_set_smoke_shader_params(plume_shader, {
			"smoke_color": Color(smoke_color.r, smoke_color.g, smoke_color.b, plume_alpha),
			"density": clampf(0.34 + hrr_t * 0.70, 0.30, 1.02),
			"turbulence": 0.92,
			"drift_speed": 0.13 + hrr_t * 0.18,
			"volume_depth_m": maxf(plume_height_m, 0.05),
			"edge_softness": 0.40,
			"bottom_waviness": 0.34,
			"edge_band_strength": 0.34,
			"side_visibility": 0.50,
			"bottom_surface_strength": 0.12,
			"top_visibility": 0.0,
			"vertical_gradient_strength": 0.26,
			"lower_density_floor": 0.18,
			"flow_strength": 0.42 + hrr_t * 0.32,
			"flow_speed": 0.42 + hrr_t * 0.20,
			"flow_direction": 0.0,
		})


func _find_fire_anchor(item: Dictionary, rect: Rect2, rs: Dictionary) -> Dictionary:
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))
	var anchor_pos: Vector3 = _room_center(rect, 0.0, floor_level_m)
	var anchor_y_m: float = 0.0
	var anchor_radius_m: float = fire_base_radius_m
	var fuel_objects: Array = rs.get("fuel_objects", [])
	if fuel_objects.is_empty():
		item["fire_anchor_id"] = ""
		return {}

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
		var is_active_state: bool = state_name == "flaming" or state_name == "pyrolyzing" or state_name == "decaying"
		var score: float = maxf(float(obj.get("hrr_kw", 0.0)), float(obj.get("hrr", 0.0))) if is_active_state else 0.0
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
			return {}
	if not previous_obj.is_empty() and previous_score > maxf(1.0, best_score * 0.35):
		best_obj = previous_obj
	item["fire_anchor_id"] = String(best_obj.get("id", ""))

	var pos_m: Vector2 = _vector2_from_variant(best_obj.get("position_m", Vector2.ZERO), Vector2.ZERO)
	var size_m: Vector2 = _vector2_from_variant(best_obj.get("size_m", Vector2(0.5, 0.5)), Vector2(0.5, 0.5))
	var kind_name: String = _fuel_visual_archetype(best_obj)
	# Mismo tope que FP (_fp_fire_base_y_for_object): una elevation_m alta no
	# debe plantar la llama en el techo — la base queda a media sala como mucho.
	var room_height_m: float = maxf(0.5, float(item.get("height_m", default_room_height_m)))
	anchor_y_m = clampf(
		FurniturePlacement3D.fire_base_height_for(best_obj, kind_name),
		0.02,
		minf(1.25, room_height_m * 0.55)
	)
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
			var open_color: Color = window_broken_color if op.type == OpeningModel.Type.WINDOW and op.glass_broken else _opening_color(op)
			var marker_color: Color = closed_opening_color.lerp(open_color, clampf(op.open_fraction, 0.0, 1.0))
			if int(index) == _selected_opening_index:
				marker_color = marker_color.lerp(Color(1.0, 0.88, 0.18, 1.0), 0.55)
			mat.albedo_color = marker_color
		_update_door_leaf_visual(item_dict, op)
		var broken_crack_h := item_dict.get("broken_crack_h") as MeshInstance3D
		if broken_crack_h != null:
			broken_crack_h.visible = op.type == OpeningModel.Type.WINDOW and op.glass_broken
		var broken_crack_v := item_dict.get("broken_crack_v") as MeshInstance3D
		if broken_crack_v != null:
			broken_crack_v.visible = op.type == OpeningModel.Type.WINDOW and op.glass_broken

		SmokeOpeningCurtain3D.update(item_dict, op, _room_items, {
			"show_smoke_volume": show_smoke_volume,
			"show_smoke_opening_curtains": show_smoke_opening_curtains \
				and (not _first_person_overlay or show_smoke_opening_curtains_in_first_person),
			"first_person_overlay": _first_person_overlay,
			"show_smoke_geometry_in_first_person": show_smoke_geometry_in_first_person,
			"smoke_opening_blend_depth_m": smoke_opening_blend_depth_m,
			"smoke_min_visible_depth_m": smoke_min_visible_depth_m,
			"meters_to_units": meters_to_units,
			"origin_offset_m": _origin_offset_m,
			"smoke_color": smoke_color,
			"hot_smoke_outflow_color": smoke_hot_outflow_color,
			"cold_air_inflow_color": cold_air_inflow_color,
			"show_cold_air_inflow_curtains": show_cold_air_inflow_curtains,
		})


func _update_door_leaf_visual(item_dict: Dictionary, op: OpeningModel) -> void:
	var pivot := item_dict.get("door_leaf_pivot") as Node3D
	var panel := item_dict.get("door_leaf_panel") as MeshInstance3D
	if pivot == null or panel == null or op == null:
		return
	var visible_leaf: bool = show_door_leaf_animation_3d and op.type == OpeningModel.Type.DOOR and not op.is_vertical
	pivot.visible = visible_leaf
	panel.visible = visible_leaf
	if not visible_leaf:
		return
	var full_angle: float = float(pivot.get_meta("full_open_angle_rad", deg_to_rad(90.0)))
	pivot.rotation.y = full_angle * clampf(op.open_fraction, 0.0, 1.0)
	var mat := panel.material_override as StandardMaterial3D
	if mat != null:
		var leaf_color: Color = closed_opening_color.lerp(door_color, clampf(op.open_fraction, 0.0, 1.0))
		mat.albedo_color = Color(leaf_color.r, leaf_color.g, leaf_color.b, maxf(leaf_color.a, 0.72))


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


func _room_stair_run_direction(room: RoomModel) -> Vector2:
	if room == null:
		return Vector2.DOWN
	var value: Vector2 = room.stair_run_direction_m
	if absf(value.x) > absf(value.y):
		return Vector2.RIGHT if value.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if value.y >= 0.0 else Vector2.UP


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
	var base: String = room_name if room_name != "" else "R%d" % room_id
	if not (debug_show_layer_heights or debug_show_room_temps or debug_show_hrr_values):
		return base
	var parts: PackedStringArray = PackedStringArray()
	parts.append(base)
	if debug_show_layer_heights:
		var layer_m: float = float(_room_state.get("smoke_display_layer_m", _room_state.get("smoke_layer_m", _room_state.get("h_layer_m", -1.0))))
		if layer_m >= 0.0:
			parts.append("L %.1fm" % layer_m)
	if debug_show_room_temps:
		var temp_c: float = float(_room_state.get("temp_upper_c", -999.0))
		if temp_c > -999.0:
			parts.append("%.0f\u00b0C" % temp_c)
	if debug_show_hrr_values:
		var hrr: float = float(_room_state.get("hrr_kw", 0.0))
		if hrr > 0.0:
			parts.append("%.0fkW" % hrr)
	return "\n".join(parts)


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
			var detector_color: Color = detector_triggered_color if triggered else detector_marker_color
			if det_id == _selected_detector_id:
				detector_color = detector_color.lerp(selection_highlight_color, 0.60)
			_set_marker_color(node, detector_color)

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
			var victim_color: Color = victim_incapacitated_color if incapacitated else victim_marker_color
			if vic_id == _selected_victim_id:
				victim_color = victim_color.lerp(selection_highlight_color, 0.60)
			_set_marker_color(node, victim_color)

	_prune_marker_nodes(detector_nodes, seen_detectors)
	_prune_marker_nodes(victim_nodes, seen_victims)
	item["detector_nodes"] = detector_nodes
	item["victim_nodes"] = victim_nodes


func _update_safety_marker_selection_visuals() -> void:
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		_update_room_safety_markers_3d(int(room_id), item, Rect2(item.get("rect", Rect2())))


func _update_player_start_marker_3d() -> void:
	if building == null or _atmosphere_root == null or _first_person_overlay or building.player_start.is_empty():
		if _player_start_node != null:
			_player_start_node.visible = false
		return
	var start: Dictionary = building.player_start
	var room_id: int = int(start.get("room_id", -1))
	var rects: Dictionary = building.get_room_rects_m()
	if not rects.has(room_id):
		if _player_start_node != null:
			_player_start_node.visible = false
		return
	var rect := Rect2(rects[room_id])
	var local_pos: Vector2 = _vector2_from_variant(start.get("position_m", rect.size * 0.5), rect.size * 0.5)
	local_pos.x = clampf(local_pos.x, 0.0, rect.size.x)
	local_pos.y = clampf(local_pos.y, 0.0, rect.size.y)
	if _player_start_node == null:
		_player_start_node = _create_player_start_marker_node()
		_atmosphere_root.add_child(_player_start_node)
	var floor_level_m: float = float(start.get("floor_level_z_m", _get_room_floor_level(room_id)))
	_player_start_node.position = _to_world(Vector3(rect.position.x + local_pos.x, floor_level_m + 0.05, rect.position.y + local_pos.y))
	_player_start_node.rotation_degrees.y = float(start.get("yaw_deg", 0.0))
	_player_start_node.visible = true
	var marker_color: Color = player_start_marker_color.lerp(selection_highlight_color, 0.58) if _selected_player_start else player_start_marker_color
	_set_marker_color(_player_start_node, marker_color)


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


func _create_player_start_marker_node() -> Node3D:
	var root := Node3D.new()
	root.name = "PlayerStart"
	var mat := _make_material(player_start_marker_color, false)
	var disk := MeshInstance3D.new()
	disk.name = "MarkerDisk"
	var disk_mesh := CylinderMesh.new()
	disk_mesh.top_radius = 0.17 * meters_to_units
	disk_mesh.bottom_radius = 0.17 * meters_to_units
	disk_mesh.height = 0.035 * meters_to_units
	disk_mesh.radial_segments = 28
	disk.mesh = disk_mesh
	disk.material_override = mat
	root.add_child(disk)
	var arrow := MeshInstance3D.new()
	arrow.name = "DirectionArrow"
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.08, 0.04, 0.34) * meters_to_units
	arrow.mesh = arrow_mesh
	arrow.position = Vector3(0.0, 0.025 * meters_to_units, -0.20 * meters_to_units)
	arrow.material_override = mat
	root.add_child(arrow)
	return root


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
	# has_meta primero: get_meta(nombre, null) con default null tambien
	# lanza error de engine cuando la clave no existe.
	var cached: Variant = root.get_meta("marker_mat") if root.has_meta("marker_mat") else null
	var mat: StandardMaterial3D
	if cached is StandardMaterial3D and cached.albedo_color.is_equal_approx(color):
		return
	if cached is StandardMaterial3D:
		cached.albedo_color = color
		return
	mat = _make_material(color, false)
	root.set_meta("marker_mat", mat)
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
			if stale_node.get_parent() != null:
				stale_node.get_parent().remove_child(stale_node)
			stale_node.queue_free()
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
	var room_id: int = int(item.get("room_id", -1))
	var objects: Array = Array(rs.get("fuel_objects", [])).duplicate()
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var room_name: String = room.name if room != null else String(rs.get("name", ""))
	var room_kind: String = room.kind if room != null else String(rs.get("kind", ""))
	var normalized_objects: Array = []
	for raw_snapshot in objects:
		if typeof(raw_snapshot) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = FurnitureVisualLayout.normalize_spec(room_id, room_name, room_kind, rect.size, Dictionary(raw_snapshot))
		if not bool(normalized.get("visual_hidden", false)):
			normalized_objects.append(normalized)
	objects = normalized_objects

	if _first_person_overlay and not show_fuel_objects_in_first_person:
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
	var placed_solid_rects: Array[Rect2] = []
	for raw_obj in objects:
		if typeof(raw_obj) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw_obj
		var obj_id: String = String(obj.get("id", ""))
		if obj_id == "":
			continue
		if obj_id.begins_with("room_proxy_"):
			continue

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
		var visual_pose_locked: bool = bool(obj.get("visual_pose_locked", false))
		var visual_center_m: Vector2 = pos_m + size_m * 0.5
		var visual_size_m: Vector2 = size_m
		if not visual_pose_locked:
			var visual_pose: Dictionary = FurniturePlacement3D.clamp_visual_pose(rect, pos_m, size_m, rotation_deg)
			visual_center_m = visual_pose.get("center_m", visual_center_m)
			visual_size_m = visual_pose.get("size_m", visual_size_m)
		if _is_solid_fuel_visual_kind(kind_name):
			var visual_rect := Rect2(visual_center_m - visual_size_m * 0.5, visual_size_m)
			if not visual_pose_locked:
				visual_rect = _resolve_fuel_visual_rect(room_id, rect, visual_rect, placed_solid_rects)
				if _fuel_visual_rect_conflicts(room_id, rect, visual_rect, placed_solid_rects):
					continue
			visual_center_m = visual_rect.position + visual_rect.size * 0.5
			visual_size_m = visual_rect.size
			placed_solid_rects.append(visual_rect)
		seen_ids[obj_id] = true

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
		node.set_meta("room_id", room_id)
		node.set_meta("object_id", obj_id)
		node.set_meta("size_x_m", visual_size_m.x)
		node.set_meta("size_y_m", visual_size_m.y)

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
			if stale_node.get_parent() != null:
				stale_node.get_parent().remove_child(stale_node)
			stale_node.queue_free()
		fuel_obj_nodes.erase(stale_id)

	item["fuel_obj_nodes"] = fuel_obj_nodes
	fuel_objects_root.visible = fuel_obj_nodes.size() > 0
	_update_fuel_object_selection_visuals()


func _update_fuel_object_selection_visuals() -> void:
	for room_id in _room_items.keys():
		var item: Dictionary = _room_items[room_id]
		var fuel_obj_nodes: Dictionary = item.get("fuel_obj_nodes", {})
		for object_id in fuel_obj_nodes.keys():
			var node := fuel_obj_nodes[object_id] as Node3D
			if node == null:
				continue
			var selected: bool = int(room_id) == _selected_object_room_id and String(object_id) == _selected_object_id
			_set_fuel_object_selection_halo(node, selected)


func _set_fuel_object_selection_halo(node: Node3D, selected: bool) -> void:
	var halo := node.get_node_or_null("SelectionHalo") as MeshInstance3D
	if not selected:
		if halo != null:
			halo.visible = false
		return
	if halo == null:
		halo = MeshInstance3D.new()
		halo.name = "SelectionHalo"
		node.add_child(halo)
	halo.material_override = _selection_halo_material()
	var mesh := halo.mesh as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.radial_segments = 48
		mesh.height = 0.025 * meters_to_units
		halo.mesh = mesh
	var size_x: float = float(node.get_meta("size_x_m", 0.5))
	var size_y: float = float(node.get_meta("size_y_m", 0.5))
	var radius: float = maxf(0.22, maxf(size_x, size_y) * 0.66) * meters_to_units
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	halo.position = Vector3(0.0, 0.018 * meters_to_units, 0.0)
	halo.visible = true


func _selection_halo_material() -> StandardMaterial3D:
	var mat := _make_material(Color(selection_highlight_color.r, selection_highlight_color.g, selection_highlight_color.b, 0.36), true)
	mat.no_depth_test = true
	return mat


func _is_solid_fuel_visual_kind(kind_name: String) -> bool:
	return not (kind_name == "rug" or kind_name == "curtain" or kind_name == "pool" or kind_name == "textile_pile")


func _resolve_fuel_visual_rect(room_id: int, room_rect: Rect2, local_rect: Rect2, placed_solid_rects: Array[Rect2]) -> Rect2:
	local_rect = _clamp_fuel_visual_rect(local_rect, room_rect)
	if not _fuel_visual_rect_conflicts(room_id, room_rect, local_rect, placed_solid_rects):
		return local_rect
	var margin: float = 0.10
	var max_x: float = maxf(margin, room_rect.size.x - margin - local_rect.size.x)
	var max_y: float = maxf(margin, room_rect.size.y - margin - local_rect.size.y)
	var candidates: Array[Vector2] = [
		local_rect.position + Vector2(0.0, 0.82),
		local_rect.position + Vector2(0.0, -0.82),
		local_rect.position + Vector2(0.82, 0.0),
		local_rect.position + Vector2(-0.82, 0.0),
		Vector2(margin, margin),
		Vector2(max_x, margin),
		Vector2(margin, max_y),
		Vector2(max_x, max_y),
		Vector2((room_rect.size.x - local_rect.size.x) * 0.5, (room_rect.size.y - local_rect.size.y) * 0.5)
	]
	var step_m: float = 0.24
	var cols: int = maxi(1, int(ceil(maxf(0.0, max_x - margin) / step_m)) + 1)
	var rows: int = maxi(1, int(ceil(maxf(0.0, max_y - margin) / step_m)) + 1)
	for iy in range(rows):
		for ix in range(cols):
			candidates.append(Vector2(
				lerpf(margin, max_x, 0.0 if cols <= 1 else float(ix) / float(cols - 1)),
				lerpf(margin, max_y, 0.0 if rows <= 1 else float(iy) / float(rows - 1))
			))

	var best_rect := local_rect
	var best_score: float = INF
	for candidate in candidates:
		var moved := _clamp_fuel_visual_rect(Rect2(candidate, local_rect.size), room_rect)
		if _fuel_visual_rect_conflicts(room_id, room_rect, moved, placed_solid_rects):
			continue
		var score: float = local_rect.position.distance_squared_to(moved.position)
		if score < best_score:
			best_score = score
			best_rect = moved
	return best_rect


func _clamp_fuel_visual_rect(local_rect: Rect2, room_rect: Rect2) -> Rect2:
	var margin: float = 0.10
	var max_w: float = maxf(0.10, room_rect.size.x - margin * 2.0)
	var max_d: float = maxf(0.10, room_rect.size.y - margin * 2.0)
	var size := Vector2(clampf(local_rect.size.x, 0.10, max_w), clampf(local_rect.size.y, 0.10, max_d))
	var max_x: float = maxf(margin, room_rect.size.x - margin - size.x)
	var max_y: float = maxf(margin, room_rect.size.y - margin - size.y)
	return Rect2(
		Vector2(clampf(local_rect.position.x, margin, max_x), clampf(local_rect.position.y, margin, max_y)),
		size
	)


func _fuel_visual_rect_conflicts(room_id: int, room_rect: Rect2, local_rect: Rect2, placed_solid_rects: Array[Rect2]) -> bool:
	if _fuel_visual_blocks_opening(room_id, room_rect, local_rect):
		return true
	var padded := Rect2(local_rect.position - Vector2(0.045, 0.045), local_rect.size + Vector2(0.09, 0.09))
	for placed in placed_solid_rects:
		if padded.intersects(placed, true):
			return true
	return false


func _fuel_visual_blocks_opening(room_id: int, room_rect: Rect2, local_rect: Rect2) -> bool:
	if building == null or room_id < 0:
		return false
	for clearance in _fuel_visual_opening_clearances_for_room(room_id, room_rect):
		if local_rect.intersects(clearance, true):
			return true
	return false


func _fuel_visual_opening_clearances_for_room(room_id: int, room_rect: Rect2) -> Array[Rect2]:
	var clearances: Array[Rect2] = []
	var clearance_depth_m: float = 0.74
	var clearance_side_pad_m: float = 0.34
	for index in range(building.get_opening_count()):
		var op: OpeningModel = building.get_opening_at(index)
		if op == null or op.is_vertical or (op.a != room_id and op.b != room_id):
			continue
		var pose: Dictionary = _get_cached_opening_pose(index)
		if pose.is_empty() or bool(pose.get("is_vertical", false)):
			continue
		var pos3: Vector3 = Vector3(pose.get("position", Vector3.ZERO))
		var pose_size: Vector3 = Vector3(pose.get("size", Vector3.ONE))
		var side: String = _opening_side_for_room_rect(room_rect, pos3)
		if side == "":
			continue
		var width_m: float = maxf(pose_size.x, pose_size.z) + clearance_side_pad_m * 2.0
		var half_w: float = width_m * 0.5
		if side == "top" or side == "bottom":
			var local_x: float = pos3.x - room_rect.position.x
			var x0: float = clampf(local_x - half_w, 0.0, room_rect.size.x)
			var x1: float = clampf(local_x + half_w, 0.0, room_rect.size.x)
			var y0: float = 0.0 if side == "top" else maxf(0.0, room_rect.size.y - clearance_depth_m)
			clearances.append(Rect2(Vector2(x0, y0), Vector2(maxf(0.0, x1 - x0), minf(clearance_depth_m, room_rect.size.y))))
		else:
			var local_y: float = pos3.z - room_rect.position.y
			var y0: float = clampf(local_y - half_w, 0.0, room_rect.size.y)
			var y1: float = clampf(local_y + half_w, 0.0, room_rect.size.y)
			var x0: float = 0.0 if side == "left" else maxf(0.0, room_rect.size.x - clearance_depth_m)
			clearances.append(Rect2(Vector2(x0, y0), Vector2(minf(clearance_depth_m, room_rect.size.x), maxf(0.0, y1 - y0))))
	return clearances


func _opening_side_for_room_rect(room_rect: Rect2, pos3: Vector3) -> String:
	var eps: float = 0.08
	if absf(pos3.z - room_rect.position.y) <= eps:
		return "top"
	if absf(pos3.z - (room_rect.position.y + room_rect.size.y)) <= eps:
		return "bottom"
	if absf(pos3.x - room_rect.position.x) <= eps:
		return "left"
	if absf(pos3.x - (room_rect.position.x + room_rect.size.x)) <= eps:
		return "right"
	return ""


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
