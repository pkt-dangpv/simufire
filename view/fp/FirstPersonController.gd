extends CharacterBody3D
class_name FirstPersonController

signal exit_requested
signal opening_changed

const FPVisibilityOverlay := preload("res://view/fp/FPVisibilityOverlay.gd")
const FPOpeningVisuals := preload("res://view/fp/FPOpeningVisuals.gd")
const FPOpeningInteraction := preload("res://view/fp/FPOpeningInteraction.gd")
const FPPlayerMotion := preload("res://view/fp/FPPlayerMotion.gd")
const FireAnimation3D := preload("res://view/3d/fire/FireAnimation3D.gd")
const FireMeshFactory := preload("res://view/3d/fire/FireMeshFactory.gd")
const FurniturePlacement3D := preload("res://view/3d/furniture/FurniturePlacement3D.gd")
const FurnitureShapeBuilder := preload("res://view/3d/furniture/FurnitureShapeBuilder.gd")
const FurnitureStateVisuals := preload("res://view/3d/furniture/FurnitureStateVisuals.gd")
const FurnitureVisualClassifier := preload("res://view/3d/furniture/FurnitureVisualClassifier.gd")
const FurnitureVisualLayout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const OUTSIDE_ID: int = -1
const STANCE_STAND: int = 0
const STANCE_CROUCH: int = 1
const STANCE_PRONE: int = 2
const OPENING_FRACTION_STEPS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const OPENING_HOLD_THRESHOLD_S: float = 0.35
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
@export var interaction_range_m: float = 1.30
@export var interaction_aim_dot_min: float = 0.48
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
@export var window_glass_shard_color: Color = Color(0.74, 0.92, 1.0, 0.34)
@export var window_glass_crack_color: Color = Color(0.88, 0.98, 1.0, 0.78)

@export_group("Exterior FP")
@export var exterior_context_enabled: bool = true
@export_enum("Dia", "Noche") var exterior_lighting_mode: String = "Dia"
@export var exterior_floor_drop_m: float = 5.8
@export var city_view_width_m: float = 22.0
@export var city_building_distance_m: float = 15.0
@export var city_backdrop_distance_m: float = 32.0
@export var exterior_window_obstacles_enabled: bool = true
@export var city_building_count_per_window: int = 3
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

@export_group("Marcadores FP")
@export var show_fp_detectors: bool = true
@export var show_fp_victims: bool = true
@export var fp_detector_color: Color = Color(0.35, 0.76, 1.0, 1.0)
@export var fp_detector_triggered_color: Color = Color(1.0, 0.38, 0.16, 1.0)
@export var fp_victim_color: Color = Color(0.95, 0.86, 0.48, 1.0)
@export var fp_victim_incapacitated_color: Color = Color(0.58, 0.58, 0.62, 1.0)
## Color del marcador de víctima cuando FED ≥ fp_victim_fed_fatal_threshold (por defecto rojo oscuro).
@export var fp_victim_fatal_color: Color = Color(0.72, 0.12, 0.12, 1.0)
## Umbral FED para estado incapacitada (FP-04). Default NFPA 1710: 0.3.
@export var fp_victim_fed_incapacitated_threshold: float = 0.3
## Umbral FED para estado mortal (FP-04). Default FED = 1.0.
@export var fp_victim_fed_fatal_threshold: float = 1.0

@export_group("Alarmas FP")
## Reproduce un beep procedural 3D cuando un detector visible pasa a estado activado.
@export var fp_detector_alarm_enabled: bool = true
@export_range(-40.0, 6.0, 0.5) var fp_detector_alarm_volume_db: float = -8.0
@export_range(1.0, 40.0, 0.5) var fp_detector_alarm_max_distance_m: float = 18.0
@export_range(200.0, 2400.0, 10.0) var fp_detector_alarm_frequency_hz: float = 880.0
@export_range(0.05, 1.0, 0.01) var fp_detector_alarm_beep_duration_s: float = 0.18
@export_range(0.15, 3.0, 0.01) var fp_detector_alarm_interval_s: float = 0.75

@export_group("Mobiliario FP")
@export var show_fp_furniture: bool = true
@export var fp_furniture_generic_height_m: float = 0.34

@export_group("Humo FP")
@export var smoke_overlay_visibility_reference_m: float = 26.0
@export var smoke_overlay_layer_clearance_m: float = 0.10
@export var smoke_overlay_layer_transition_m: float = 0.48
@export var smoke_overlay_max_alpha: float = 0.97
@export var fp_visibility_clear_m: float = 30.0

@export_group("Fuego FP")
@export var show_fp_fire: bool = true
@export var fp_fire_min_visible_hrr_kw: float = 0.5
@export var fp_fire_reference_hrr_kw: float = 1000.0
@export var fp_fire_base_radius_m: float = 0.14
@export var fp_fire_max_radius_m: float = 0.48
@export var fp_fire_max_height_m: float = 1.75
@export var fp_fire_ceiling_clearance_m: float = 0.10
@export var fp_fire_ceiling_cap_thickness_m: float = 0.20
@export var fp_fire_light_energy_per_1000kw: float = 2.2
@export var fp_fire_light_range_min_m: float = 2.0
@export var fp_fire_light_range_max_m: float = 8.0
@export var fp_fire_flicker_strength: float = 0.13
@export var fp_fire_color: Color = Color(1.0, 0.34, 0.08, 0.90)
@export var fp_fire_core_color: Color = Color(1.0, 0.86, 0.34, 0.95)
@export var fp_fire_glow_color: Color = Color(1.0, 0.16, 0.03, 0.28)
@export var fp_fire_ceiling_cap_color: Color = Color(1.0, 0.24, 0.04, 0.18)

@export_group("Preset FP")
## Perfil de configuración aplicado en _ready(). Asignar un .tres de res://view/fp/presets/ desde el Inspector.
@export var fp_preset: FPPreset = null

@export_group("Technical Overlay")
## Muestra panel HUD en FP con T, CO, CO₂, O₂, HCN, FED y visibilidad en tiempo real.
@export var show_technical_overlay: bool = true
## Muestra readout compacto de visibilidad en FP cuando el overlay técnico está oculto.
@export var show_visibility_readout: bool = true
## Intervalo real de refresco del texto FP. Mantiene datos legibles aunque la simulación vaya acelerada.
@export_range(0.05, 1.0, 0.05) var fp_hud_refresh_interval_s: float = 0.35

@export_group("FP HUD Layout")
## Rect del panel superior de estado FP. x/y son offsets desde su ancla; w/h son tamaño.
@export var fp_status_panel_rect: Rect2 = Rect2(18.0, 18.0, 360.0, 66.0)
## Rect del panel técnico. Usa ancla superior izquierda para no pisar controles inferiores.
@export var technical_overlay_panel_rect: Rect2 = Rect2(18.0, 92.0, 212.0, 160.0)
## Rect del readout compacto de visibilidad. Usa ancla inferior izquierda.
@export var visibility_readout_panel_rect: Rect2 = Rect2(18.0, -70.0, 178.0, 46.0)
## Rect del prompt de interacción central.
@export var fp_prompt_panel_rect: Rect2 = Rect2(-180.0, 22.0, 360.0, 60.0)

var building: BuildingModel = null

var _camera: Camera3D = null
var _collision_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _world_root: Node3D = null
var _prompt_layer: CanvasLayer = null
var _fp_status_panel: PanelContainer = null
var _fp_status_label: Label = null
var _technical_overlay_panel: PanelContainer = null
var _technical_overlay_label: Label = null
var _visibility_readout_panel: PanelContainer = null
var _visibility_readout_label: Label = null
var _prompt_panel: PanelContainer = null
var _prompt_label: Label = null
var _crosshair_h: ColorRect = null
var _crosshair_v: ColorRect = null
var _origin_offset_m: Vector2 = Vector2.ZERO
var _bounds_m: Rect2 = Rect2()
var _active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _stance: int = STANCE_STAND
var _opening_nodes: Dictionary = {}
var _detector_nodes: Dictionary = {}
var _victim_nodes: Dictionary = {}
var _furniture_nodes_by_room: Dictionary = {}
var _fire_nodes_by_room: Dictionary = {}
var _ceiling_lights_by_room: Dictionary = {}
var _ceiling_light_base_energy_by_room: Dictionary = {}
var _ceiling_light_base_range_by_room: Dictionary = {}
var _detector_alarm_stream: AudioStreamWAV = null
var _nearest_opening_index: int = -1
var _state: Dictionary = {}
var _visibility_overlay: ColorRect = null
var _current_room_id: int = -1
var _fp_fire_phase: float = 0.0
var _f_key_down: bool = false
var _f_hold_mode: bool = false
var _f_hold_elapsed_s: float = 0.0
var _f_hold_opening_index: int = -1
var _f_hold_fraction: float = 0.0
var _last_fp_hud_update_msec: int = 0


func _ready() -> void:
	apply_preset()
	_create_player_nodes()
	set_active(false)


func setup(next_building: BuildingModel) -> void:
	building = next_building
	_apply_startup_lighting_options()
	_rebuild_world()
	_place_at_entry()


## Aplica los valores de [param p] (o de [member fp_preset] si p es null) sobre las propiedades
## de este controlador. Sin efecto si el preset es null. Seguro llamarlo en cualquier momento.
func apply_preset(p: FPPreset = null) -> void:
	var src: FPPreset = p if p != null else fp_preset
	if src == null:
		return
	ambient_fill_enabled = src.ambient_fill_enabled
	room_ceiling_lights_enabled = src.room_ceiling_lights_enabled
	exterior_lighting_mode = src.exterior_lighting_mode
	exterior_context_enabled = src.exterior_context_enabled
	show_fp_detectors = src.show_fp_detectors
	show_fp_victims = src.show_fp_victims
	fp_detector_alarm_enabled = src.fp_detector_alarm_enabled
	smoke_overlay_max_alpha = src.smoke_overlay_max_alpha
	fp_visibility_clear_m = src.fp_visibility_clear_m
	show_technical_overlay = src.show_technical_overlay
	show_visibility_readout = src.show_visibility_readout
	fp_victim_fed_incapacitated_threshold = src.fp_victim_fed_incapacitated_threshold
	fp_victim_fed_fatal_threshold = src.fp_victim_fed_fatal_threshold


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
		apply_hud_layout()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_update_status_hud(true)
		_update_prompt()
		_update_safety_marker_states()
	else:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_nearest_opening_index = -1
		_cancel_opening_hold()
		if _prompt_panel != null:
			_prompt_panel.visible = false
		if _visibility_overlay != null:
			_visibility_overlay.color = Color(0.08, 0.09, 0.09, 0.0)
		_stop_detector_alarms()


func rebuild_from_building() -> void:
	_apply_startup_lighting_options()
	_rebuild_world()
	_place_at_entry()


func set_state(next_state: Dictionary) -> void:
	_state = next_state
	_sync_opening_panels()
	_update_smoke_light_attenuation()
	_update_fp_furniture_visuals()
	_update_fp_fire_visuals()
	_update_safety_marker_states()
	_update_visibility_overlay()
	_update_status_hud()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_fp_fire_phase += delta
	_apply_movement(delta)
	_update_opening_hold(delta)
	_animate_fp_fire()
	_update_prompt()
	_update_visibility_overlay()
	_update_status_hud()


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
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if _f_key_down and (mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mouse_event.pressed:
			_adjust_held_opening_fraction(1 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F:
			if key_event.pressed and not key_event.echo:
				_begin_opening_hold()
			elif not key_event.pressed:
				_finish_opening_hold()
			get_viewport().set_input_as_handled()
			return
		if _f_key_down and key_event.pressed and not key_event.echo and key_event.keycode >= KEY_1 and key_event.keycode <= KEY_5:
			_set_held_opening_fraction_by_step(int(key_event.keycode - KEY_1))
			get_viewport().set_input_as_handled()
			return
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			exit_requested.emit()
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

	_fp_status_panel = PanelContainer.new()
	_fp_status_panel.name = "FirstPersonStatusPanel"
	_fp_status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_apply_panel_rect(_fp_status_panel, fp_status_panel_rect)
	_fp_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fp_status_panel.add_theme_stylebox_override("panel", _make_fp_hud_style())
	_prompt_layer.add_child(_fp_status_panel)
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 10)
	status_margin.add_theme_constant_override("margin_top", 7)
	status_margin.add_theme_constant_override("margin_right", 10)
	status_margin.add_theme_constant_override("margin_bottom", 7)
	_fp_status_panel.add_child(status_margin)
	_fp_status_label = Label.new()
	_fp_status_label.name = "FirstPersonStatusLabel"
	_fp_status_label.add_theme_font_size_override("font_size", 12)
	_fp_status_label.add_theme_color_override("font_color", Color(0.88, 0.94, 0.92, 1.0))
	_fp_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_margin.add_child(_fp_status_label)

	_technical_overlay_panel = PanelContainer.new()
	_technical_overlay_panel.name = "TechnicalOverlayPanel"
	_technical_overlay_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_apply_panel_rect(_technical_overlay_panel, technical_overlay_panel_rect)
	_technical_overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_technical_overlay_panel.add_theme_stylebox_override("panel", _make_fp_hud_style())
	_technical_overlay_panel.visible = false
	_prompt_layer.add_child(_technical_overlay_panel)
	var overlay_margin := MarginContainer.new()
	overlay_margin.add_theme_constant_override("margin_left", 10)
	overlay_margin.add_theme_constant_override("margin_top", 7)
	overlay_margin.add_theme_constant_override("margin_right", 10)
	overlay_margin.add_theme_constant_override("margin_bottom", 7)
	_technical_overlay_panel.add_child(overlay_margin)
	_technical_overlay_label = Label.new()
	_technical_overlay_label.name = "TechnicalOverlayLabel"
	_technical_overlay_label.add_theme_font_size_override("font_size", 12)
	_technical_overlay_label.add_theme_color_override("font_color", Color(0.88, 0.94, 0.92, 1.0))
	overlay_margin.add_child(_technical_overlay_label)

	_visibility_readout_panel = PanelContainer.new()
	_visibility_readout_panel.name = "VisibilityReadoutPanel"
	_visibility_readout_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_apply_panel_rect(_visibility_readout_panel, visibility_readout_panel_rect)
	_visibility_readout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visibility_readout_panel.add_theme_stylebox_override("panel", _make_fp_hud_style())
	_visibility_readout_panel.visible = false
	_prompt_layer.add_child(_visibility_readout_panel)
	var vis_margin := MarginContainer.new()
	vis_margin.add_theme_constant_override("margin_left", 10)
	vis_margin.add_theme_constant_override("margin_top", 7)
	vis_margin.add_theme_constant_override("margin_right", 10)
	vis_margin.add_theme_constant_override("margin_bottom", 7)
	_visibility_readout_panel.add_child(vis_margin)
	_visibility_readout_label = Label.new()
	_visibility_readout_label.name = "VisibilityReadoutLabel"
	_visibility_readout_label.add_theme_font_size_override("font_size", 14)
	_visibility_readout_label.add_theme_color_override("font_color", Color(0.88, 0.94, 0.92, 1.0))
	vis_margin.add_child(_visibility_readout_label)

	_crosshair_h = ColorRect.new()
	_crosshair_h.name = "CrosshairH"
	_crosshair_h.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair_h.offset_left = -9.0
	_crosshair_h.offset_top = -1.0
	_crosshair_h.offset_right = 9.0
	_crosshair_h.offset_bottom = 1.0
	_crosshair_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_h.color = Color(1.0, 0.86, 0.45, 0.72)
	_prompt_layer.add_child(_crosshair_h)
	_crosshair_v = ColorRect.new()
	_crosshair_v.name = "CrosshairV"
	_crosshair_v.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair_v.offset_left = -1.0
	_crosshair_v.offset_top = -9.0
	_crosshair_v.offset_right = 1.0
	_crosshair_v.offset_bottom = 9.0
	_crosshair_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_v.color = Color(1.0, 0.86, 0.45, 0.72)
	_prompt_layer.add_child(_crosshair_v)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "PromptPanel"
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER)
	_apply_panel_rect(_prompt_panel, fp_prompt_panel_rect)
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	_prompt_panel.add_theme_stylebox_override("panel", _make_fp_hud_style())
	_prompt_layer.add_child(_prompt_panel)
	var prompt_margin := MarginContainer.new()
	prompt_margin.add_theme_constant_override("margin_left", 12)
	prompt_margin.add_theme_constant_override("margin_top", 8)
	prompt_margin.add_theme_constant_override("margin_right", 12)
	prompt_margin.add_theme_constant_override("margin_bottom", 8)
	_prompt_panel.add_child(prompt_margin)
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	prompt_margin.add_child(_prompt_label)
	apply_hud_layout()


func apply_hud_layout() -> void:
	if _fp_status_panel != null:
		_fp_status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_apply_panel_rect(_fp_status_panel, fp_status_panel_rect)
	if _technical_overlay_panel != null:
		_technical_overlay_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_apply_panel_rect(_technical_overlay_panel, technical_overlay_panel_rect)
	if _visibility_readout_panel != null:
		_visibility_readout_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_apply_panel_rect(_visibility_readout_panel, visibility_readout_panel_rect)
	if _prompt_panel != null:
		_prompt_panel.set_anchors_preset(Control.PRESET_CENTER)
		_apply_panel_rect(_prompt_panel, fp_prompt_panel_rect)


func _apply_panel_rect(panel: Control, rect: Rect2) -> void:
	if panel == null:
		return
	panel.offset_left = rect.position.x
	panel.offset_top = rect.position.y
	panel.offset_right = rect.position.x + rect.size.x
	panel.offset_bottom = rect.position.y + rect.size.y


func _make_fp_hud_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.01, 0.025, 0.03, 0.78)
	box.border_color = Color(0.95, 0.58, 0.22, 0.76)
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_right = 0
	box.corner_radius_bottom_left = 0
	return box


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
	var next_mode: String = exterior_lighting_mode
	var next_interior_lights_on: bool = room_ceiling_lights_enabled
	if FileAccess.file_exists(STARTUP_OPTIONS_PATH):
		var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.READ)
		if file != null:
			var text: String = file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var startup: Dictionary = Dictionary(parsed)
				next_mode = String(startup.get("exterior_lighting_mode", next_mode))
				next_interior_lights_on = bool(startup.get("interior_lights_on", next_interior_lights_on))
	if building != null:
		next_mode = building.exterior_lighting_mode
		next_interior_lights_on = building.interior_lights_on
	exterior_lighting_mode = "Noche" if next_mode.strip_edges().to_lower() == "noche" else "Dia"
	room_ceiling_lights_enabled = next_interior_lights_on


func _rebuild_world() -> void:
	_ensure_world_root()
	if _world_root == null:
		return
	for child in _world_root.get_children():
		child.free()
	_world_root.global_transform = Transform3D.IDENTITY
	_world_root.visible = _active
	_opening_nodes.clear()
	_detector_nodes.clear()
	_victim_nodes.clear()
	_furniture_nodes_by_room.clear()
	_fire_nodes_by_room.clear()
	_ceiling_lights_by_room.clear()
	_ceiling_light_base_energy_by_room.clear()
	_ceiling_light_base_range_by_room.clear()

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
	_create_stairs(rects)
	_create_world_lighting(rects)
	_create_fp_furniture_nodes(rects)
	_create_fp_fire_nodes(rects)
	_create_opening_panels()
	_create_exterior_context()
	_create_safety_markers(rects)
	_create_outer_boundary()
	_update_fp_furniture_visuals()
	_update_fp_fire_visuals()


func _create_floors(rects: Dictionary) -> void:
	for room_id in rects.keys():
		var rect: Rect2 = Rect2(rects[room_id])
		var room: RoomModel = building.get_room(int(room_id)) if building != null else null
		var floor_level_m: float = room.floor_level_z_m if room != null else 0.0
		if room != null and _room_is_stairwell(room) and room.floor_level_z_m > 0.20:
			_create_stairwell_upper_floor(int(room_id), rect, room.floor_level_z_m, _room_stair_run_direction(room), room.stair_turn_degrees)
			continue
		var slabs: Array[Rect2] = _split_rect_by_voids(rect, _vertical_stair_voids_for_floor(floor_level_m))
		for i in range(slabs.size()):
			var slab: Rect2 = slabs[i]
			var node_name: String = "Floor_%s" % str(room_id) if slabs.size() == 1 and _rect_same(slab, rect) else "FloorPart_%s_%02d" % [str(room_id), i]
			_add_floor_slab(node_name, slab, floor_level_m, _floor_material_for_room(int(room_id)))


func _create_stairwell_upper_floor(room_id: int, rect: Rect2, floor_level_m: float, stair_dir: Vector2, turn_degrees: float = 0.0) -> void:
	var ramp_width_m: float = _stair_ramp_width_m(rect, stair_dir)
	var landing_depth_m: float = _stair_top_landing_depth_m(rect, stair_dir)
	var material := _floor_material_for_room(room_id)
	if turn_degrees >= 179.0 and _stair_cross_span_m(rect, stair_dir) >= 1.65:
		_create_switchback_stairwell_upper_floor(room_id, rect, floor_level_m, stair_dir, material)
		return

	if absf(stair_dir.x) > absf(stair_dir.y):
		var ramp_top_m: float = rect.position.y + rect.size.y * 0.5 - ramp_width_m * 0.5
		var ramp_bottom_m: float = ramp_top_m + ramp_width_m
		var top_height_m: float = maxf(0.0, ramp_top_m - rect.position.y)
		if top_height_m >= 0.28:
			_add_floor_slab("StairSideFloorTop_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, rect.size.x, top_height_m), floor_level_m, material)
		var bottom_height_m: float = maxf(0.0, rect.position.y + rect.size.y - ramp_bottom_m)
		if bottom_height_m >= 0.28:
			_add_floor_slab("StairSideFloorBottom_%s" % str(room_id), Rect2(rect.position.x, ramp_bottom_m, rect.size.x, bottom_height_m), floor_level_m, material)
		if landing_depth_m >= 0.28:
			var landing_x_m: float = rect.position.x + rect.size.x - landing_depth_m if stair_dir.x > 0.0 else rect.position.x
			_add_floor_slab("StairTopLanding_%s" % str(room_id), Rect2(landing_x_m, rect.position.y, landing_depth_m, rect.size.y), floor_level_m, material)
		return

	var ramp_left_m: float = rect.position.x + rect.size.x * 0.5 - ramp_width_m * 0.5
	var ramp_right_m: float = ramp_left_m + ramp_width_m
	var left_width_m: float = maxf(0.0, ramp_left_m - rect.position.x)
	if left_width_m >= 0.28:
		_add_floor_slab("StairSideFloorLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y), floor_level_m, material)
	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - ramp_right_m)
	if right_width_m >= 0.28:
		_add_floor_slab("StairSideFloorRight_%s" % str(room_id), Rect2(ramp_right_m, rect.position.y, right_width_m, rect.size.y), floor_level_m, material)
	if landing_depth_m >= 0.28:
		var landing_y_m: float = rect.position.y + rect.size.y - landing_depth_m if stair_dir.y > 0.0 else rect.position.y
		_add_floor_slab("StairTopLanding_%s" % str(room_id), Rect2(rect.position.x, landing_y_m, rect.size.x, landing_depth_m), floor_level_m, material)


func _create_switchback_stairwell_upper_floor(room_id: int, rect: Rect2, floor_level_m: float, stair_dir: Vector2, material: StandardMaterial3D) -> void:
	var gap_m: float = 0.18
	var cross_span_m: float = _stair_cross_span_m(rect, stair_dir)
	var flight_width_m: float = clampf((cross_span_m - gap_m) * 0.5, 0.72, 1.05)
	var shaft_width_m: float = minf(cross_span_m, flight_width_m * 2.0 + gap_m + 0.18)
	if absf(stair_dir.x) > absf(stair_dir.y):
		var shaft_top_m: float = rect.position.y + rect.size.y * 0.5 - shaft_width_m * 0.5
		var shaft_bottom_m: float = shaft_top_m + shaft_width_m
		var top_height_m: float = maxf(0.0, shaft_top_m - rect.position.y)
		if top_height_m >= 0.28:
			_add_floor_slab("StairSwitchbackSideTop_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, rect.size.x, top_height_m), floor_level_m, material)
		var bottom_height_m: float = maxf(0.0, rect.position.y + rect.size.y - shaft_bottom_m)
		if bottom_height_m >= 0.28:
			_add_floor_slab("StairSwitchbackSideBottom_%s" % str(room_id), Rect2(rect.position.x, shaft_bottom_m, rect.size.x, bottom_height_m), floor_level_m, material)
		return

	var shaft_left_m: float = rect.position.x + rect.size.x * 0.5 - shaft_width_m * 0.5
	var shaft_right_m: float = shaft_left_m + shaft_width_m
	var left_width_m: float = maxf(0.0, shaft_left_m - rect.position.x)
	if left_width_m >= 0.28:
		_add_floor_slab("StairSwitchbackSideLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y), floor_level_m, material)
	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - shaft_right_m)
	if right_width_m >= 0.28:
		_add_floor_slab("StairSwitchbackSideRight_%s" % str(room_id), Rect2(shaft_right_m, rect.position.y, right_width_m, rect.size.y), floor_level_m, material)


func _add_floor_slab(node_name: String, rect: Rect2, floor_level_m: float, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	_world_root.add_child(body)
	var center: Vector3 = _to_world(Vector3(
		rect.position.x + rect.size.x * 0.5,
		-floor_thickness_m * 0.5,
		rect.position.y + rect.size.y * 0.5
	), floor_level_m)
	_add_box(body, "FloorMesh", Vector3(rect.size.x, floor_thickness_m, rect.size.y), center, material, true)


func _add_ceiling_slab(node_name: String, rect: Rect2, floor_level_m: float, height_m: float, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	_world_root.add_child(body)
	var center: Vector3 = _to_world(Vector3(
		rect.position.x + rect.size.x * 0.5,
		height_m + ceiling_thickness_m * 0.5,
		rect.position.y + rect.size.y * 0.5
	), floor_level_m)
	_add_box(body, "CeilingMesh", Vector3(rect.size.x, ceiling_thickness_m, rect.size.y), center, material, true)


func _create_ceilings(rects: Dictionary) -> void:
	for room_id in rects.keys():
		var rect: Rect2 = Rect2(rects[room_id])
		var room: RoomModel = building.get_room(int(room_id))
		if room != null and _room_is_stairwell(room):
			continue
		var height_m: float = room.height_m if room != null else 2.4
		var floor_level_m: float = room.floor_level_z_m if room != null else 0.0
		var slabs: Array[Rect2] = _split_rect_by_voids(rect, _vertical_stair_voids_for_ceiling(floor_level_m))
		for i in range(slabs.size()):
			var slab: Rect2 = slabs[i]
			var node_name: String = "Ceiling_%s" % str(room_id) if slabs.size() == 1 and _rect_same(slab, rect) else "CeilingPart_%s_%02d" % [str(room_id), i]
			_add_ceiling_slab(node_name, slab, floor_level_m, height_m, _ceiling_material_for_room(int(room_id)))


func _create_walls(rects: Dictionary) -> void:
	for room_id in rects.keys():
		var rect: Rect2 = Rect2(rects[room_id])
		var room: RoomModel = building.get_room(int(room_id))
		if room != null and _room_is_stairwell(room) and not room.stair_has_walls:
			continue
		var height_m: float = room.height_m if room != null else 2.4
		var floor_level_m: float = room.floor_level_z_m if room != null else 0.0
		_add_wall_side(rect, int(room_id), "top", height_m, floor_level_m)
		_add_wall_side(rect, int(room_id), "bottom", height_m, floor_level_m)
		_add_wall_side(rect, int(room_id), "left", height_m, floor_level_m)
		_add_wall_side(rect, int(room_id), "right", height_m, floor_level_m)


func _add_wall_side(rect: Rect2, room_id: int, side: String, height_m: float, floor_level_m: float) -> void:
	var length: float = rect.size.x if side == "top" or side == "bottom" else rect.size.y
	var openings: Array = _opening_specs_for_side(rect, room_id, side, height_m)
	openings.sort_custom(func(a, b): return float(a.get("start", 0.0)) < float(b.get("start", 0.0)))

	var cursor: float = 0.0
	for opening in openings:
		var start: float = clampf(float(opening.get("start", 0.0)), 0.0, length)
		var end: float = clampf(float(opening.get("end", 0.0)), 0.0, length)
		if start > cursor + 0.03:
			_create_wall_segment(rect, room_id, side, cursor, start, height_m, floor_level_m)
		if end > start + 0.03:
			var bottom_m: float = clampf(float(opening.get("bottom_m", 0.0)), 0.0, height_m)
			var top_m: float = clampf(float(opening.get("top_m", height_m)), 0.0, height_m)
			if bottom_m > 0.03:
				_create_wall_segment_height(rect, room_id, side, start, end, 0.0, bottom_m, floor_level_m)
			if top_m < height_m - 0.03:
				_create_wall_segment_height(rect, room_id, side, start, end, top_m, height_m, floor_level_m)
		cursor = maxf(cursor, end)
	if cursor < length - 0.03:
		_create_wall_segment(rect, room_id, side, cursor, length, height_m, floor_level_m)


func _create_wall_segment(rect: Rect2, room_id: int, side: String, start: float, end: float, height_m: float, floor_level_m: float) -> void:
	_create_wall_segment_height(rect, room_id, side, start, end, 0.0, height_m, floor_level_m)


func _create_wall_segment_height(rect: Rect2, room_id: int, side: String, start: float, end: float, y_min_m: float, y_max_m: float, floor_level_m: float) -> void:
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
		center = _to_world(Vector3(rect.position.x + start + span * 0.5, center_y, z), floor_level_m)
	else:
		size = Vector3(wall_thickness_m, height_m, span)
		var x: float = rect.position.x if side == "left" else rect.position.x + rect.size.x
		center = _to_world(Vector3(x, center_y, rect.position.y + start + span * 0.5), floor_level_m)
	_add_box(body, "WallMesh", size, center, _wall_material_for_room(room_id), true)
	_create_skirting_segment(rect, side, start, end, floor_level_m)


func _create_skirting_segment(rect: Rect2, side: String, start: float, end: float, floor_level_m: float) -> void:
	var span: float = maxf(0.0, end - start)
	if span <= 0.05 or wall_skirting_height_m <= 0.0:
		return
	var center: Vector3
	var size: Vector3
	var normal: Vector3 = _inside_normal_for_side(side)
	if side == "top" or side == "bottom":
		var z: float = rect.position.y if side == "top" else rect.position.y + rect.size.y
		center = _to_world(Vector3(rect.position.x + start + span * 0.5, wall_skirting_height_m * 0.5, z), floor_level_m) + normal * (wall_thickness_m * 0.5 + 0.012)
		size = Vector3(span, wall_skirting_height_m, 0.028)
	else:
		var x: float = rect.position.x if side == "left" else rect.position.x + rect.size.x
		center = _to_world(Vector3(x, wall_skirting_height_m * 0.5, rect.position.y + start + span * 0.5), floor_level_m) + normal * (wall_thickness_m * 0.5 + 0.012)
		size = Vector3(0.028, wall_skirting_height_m, span)
	_add_box(_world_root, "Skirting_%s" % side, size, center, _mat(Color(0.34, 0.27, 0.20, 1.0), false), false)


func _create_stairs(rects: Dictionary) -> void:
	if building == null:
		return
	for room_id in rects.keys():
		var room: RoomModel = building.get_room(int(room_id))
		if room == null or not _room_is_stairwell(room):
			continue
		var lower_level_m: float = room.floor_level_z_m
		var upper_level_m: float = _find_next_floor_level_above(lower_level_m)
		if upper_level_m <= lower_level_m + 0.20:
			continue
		var rect: Rect2 = Rect2(rects[room_id])
		_create_stair_ramp(rect, lower_level_m, upper_level_m, _room_stair_run_direction(room), room.stair_has_railings, room.stair_turn_degrees)


func _create_stair_ramp(rect: Rect2, lower_level_m: float, upper_level_m: float, stair_dir: Vector2, has_railings: bool, turn_degrees: float = 0.0) -> void:
	if turn_degrees >= 179.0 and _stair_cross_span_m(rect, stair_dir) >= 1.65:
		_create_switchback_stair_ramp(rect, lower_level_m, upper_level_m, stair_dir, has_railings)
		return
	var start_margin_m: float = 0.22
	var run_m: float = maxf(0.8, _stair_long_span_m(rect, stair_dir) - start_margin_m - _stair_top_landing_depth_m(rect, stair_dir))
	var rise_m: float = upper_level_m - lower_level_m
	var angle: float = atan2(rise_m, run_m)
	var center_2d: Vector2 = _stair_point_along_run(rect, stair_dir, start_margin_m + run_m * 0.5)
	var center_y: float = lower_level_m + rise_m * 0.5
	var center_world: Vector3 = _to_world(Vector3(center_2d.x, center_y, center_2d.y))
	var ramp_size := Vector3(_stair_ramp_width_m(rect, stair_dir), 0.16, sqrt(run_m * run_m + rise_m * rise_m))
	var yaw: float = atan2(stair_dir.x, stair_dir.y)

	var body := StaticBody3D.new()
	body.name = "StairRamp"
	_world_root.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ramp_size
	shape.shape = box
	shape.position = center_world
	shape.rotation.x = -angle
	shape.rotation.y = yaw
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	mesh.name = "StairRampMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = ramp_size
	mesh.mesh = box_mesh
	mesh.position = center_world
	mesh.rotation.x = -angle
	mesh.rotation.y = yaw
	mesh.material_override = _mat(Color(0.35, 0.29, 0.22, 1.0), false)
	_world_root.add_child(mesh)

	var steps: int = 12
	var step_depth: float = run_m / float(steps)
	var step_width: float = ramp_size.x
	for i in range(steps):
		var step_h: float = rise_m * float(i + 1) / float(steps)
		var step_2d: Vector2 = _stair_point_along_run(rect, stair_dir, start_margin_m + step_depth * (float(i) + 0.5))
		var step_center := _to_world(Vector3(
			step_2d.x,
			lower_level_m + step_h - 0.025,
			step_2d.y
		))
		var step := _add_box(
			_world_root,
			"StairStep_%02d" % i,
			Vector3(step_width, 0.05, step_depth * 0.92),
			step_center,
			_mat(Color(0.42, 0.35, 0.27, 1.0), false),
			false
		)
		step.rotation.y = yaw
	if has_railings:
		_create_stair_railings(rect, lower_level_m, rise_m, run_m, stair_dir, yaw, angle)


func _create_switchback_stair_ramp(rect: Rect2, lower_level_m: float, upper_level_m: float, stair_dir: Vector2, has_railings: bool) -> void:
	var normal := Vector2(-stair_dir.y, stair_dir.x)
	var start_margin_m: float = 0.22
	var landing_depth_m: float = clampf(_stair_long_span_m(rect, stair_dir) * 0.18, 0.70, 0.95)
	var run_m: float = maxf(0.72, _stair_long_span_m(rect, stair_dir) - start_margin_m - landing_depth_m - 0.20)
	var gap_m: float = 0.18
	var flight_width_m: float = clampf((_stair_cross_span_m(rect, stair_dir) - gap_m) * 0.5, 0.72, 1.05)
	var rise_half_m: float = (upper_level_m - lower_level_m) * 0.5
	var lane_offset_m: float = flight_width_m * 0.5 + gap_m * 0.5
	var entry_distance_m: float = start_margin_m
	var landing_distance_m: float = start_margin_m + run_m
	var flight_a_start: Vector2 = _stair_point_along_run(rect, stair_dir, entry_distance_m) - normal * lane_offset_m
	var flight_b_start: Vector2 = _stair_point_along_run(rect, stair_dir, landing_distance_m) + normal * lane_offset_m
	_create_stair_flight_segment("StairFlightA", flight_a_start, stair_dir, flight_width_m, run_m, lower_level_m, rise_half_m, has_railings)
	_create_stair_flight_segment("StairFlightB", flight_b_start, -stair_dir, flight_width_m, run_m, lower_level_m + rise_half_m, rise_half_m, has_railings)
	var landing_center_2d: Vector2 = _stair_point_along_run(rect, stair_dir, landing_distance_m + landing_depth_m * 0.5)
	var landing_size: Vector3
	if absf(stair_dir.x) > absf(stair_dir.y):
		landing_size = Vector3(landing_depth_m, 0.14, flight_width_m * 2.0 + gap_m)
	else:
		landing_size = Vector3(flight_width_m * 2.0 + gap_m, 0.14, landing_depth_m)
	_add_box(
		_world_root,
		"StairSwitchbackLanding",
		landing_size,
		_to_world(Vector3(landing_center_2d.x, lower_level_m + rise_half_m, landing_center_2d.y)),
		_mat(Color(0.40, 0.33, 0.25, 1.0), false),
		true
	)


func _create_stair_flight_segment(node_name: String, start_2d: Vector2, flight_dir: Vector2, width_m: float, run_m: float, lower_y_m: float, rise_m: float, has_railings: bool) -> void:
	var angle: float = atan2(rise_m, run_m)
	var yaw: float = atan2(flight_dir.x, flight_dir.y)
	var center_2d: Vector2 = start_2d + flight_dir * (run_m * 0.5)
	var center_world: Vector3 = _to_world(Vector3(center_2d.x, lower_y_m + rise_m * 0.5, center_2d.y))
	var ramp_size := Vector3(width_m, 0.15, sqrt(run_m * run_m + rise_m * rise_m))
	var body := StaticBody3D.new()
	body.name = node_name
	_world_root.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ramp_size
	shape.shape = box
	shape.position = center_world
	shape.rotation.x = -angle
	shape.rotation.y = yaw
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "%sMesh" % node_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = ramp_size
	mesh.mesh = box_mesh
	mesh.position = center_world
	mesh.rotation.x = -angle
	mesh.rotation.y = yaw
	mesh.material_override = _mat(Color(0.35, 0.29, 0.22, 1.0), false)
	_world_root.add_child(mesh)
	var steps: int = 8
	var step_depth: float = run_m / float(steps)
	for i in range(steps):
		var step_center_2d: Vector2 = start_2d + flight_dir * (step_depth * (float(i) + 0.5))
		var step := _add_box(
			_world_root,
			"%sStep_%02d" % [node_name, i],
			Vector3(width_m, 0.05, step_depth * 0.90),
			_to_world(Vector3(step_center_2d.x, lower_y_m + rise_m * float(i + 1) / float(steps) - 0.025, step_center_2d.y)),
			_mat(Color(0.42, 0.35, 0.27, 1.0), false),
			false
		)
		step.rotation.y = yaw
	if has_railings:
		var normal := Vector2(-flight_dir.y, flight_dir.x)
		var rail_length_m: float = sqrt(run_m * run_m + rise_m * rise_m)
		for side in [-1.0, 1.0]:
			var rail_center_2d: Vector2 = center_2d + normal * (width_m * 0.5 + 0.08) * side
			var rail := _add_box(
				_world_root,
				"%sRailing" % node_name,
				Vector3(0.045, 0.08, rail_length_m),
				_to_world(Vector3(rail_center_2d.x, lower_y_m + rise_m * 0.5 + 0.82, rail_center_2d.y)),
				_mat(Color(0.18, 0.14, 0.10, 1.0), false),
				false
			)
			rail.rotation.x = -angle
			rail.rotation.y = yaw


func _create_stair_railings(rect: Rect2, lower_level_m: float, rise_m: float, run_m: float, stair_dir: Vector2, yaw: float, angle: float) -> void:
	var center_2d: Vector2 = _stair_point_along_run(rect, stair_dir, 0.22 + run_m * 0.5)
	var normal := Vector2(-stair_dir.y, stair_dir.x)
	var half_width: float = _stair_ramp_width_m(rect, stair_dir) * 0.5 + 0.08
	var rail_length_m: float = sqrt(run_m * run_m + rise_m * rise_m)
	for side in [-1.0, 1.0]:
		var rail_2d: Vector2 = center_2d + normal * half_width * side
		var rail := _add_box(
			_world_root,
			"StairRailing",
			Vector3(0.045, 0.08, rail_length_m),
			_to_world(Vector3(rail_2d.x, lower_level_m + rise_m * 0.5 + 0.82, rail_2d.y)),
			_mat(Color(0.18, 0.14, 0.10, 1.0), false),
			false
		)
		rail.rotation.x = -angle
		rail.rotation.y = yaw


func _stair_long_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.x if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.y


func _stair_cross_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.y if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.x


func _stair_ramp_width_m(rect: Rect2, stair_dir: Vector2 = Vector2.DOWN) -> float:
	var cross_span: float = _stair_cross_span_m(rect, stair_dir)
	return minf(maxf(0.82, cross_span * 0.50), maxf(0.82, cross_span - 0.96))


func _stair_top_landing_depth_m(rect: Rect2, stair_dir: Vector2 = Vector2.DOWN) -> float:
	return clampf(_stair_long_span_m(rect, stair_dir) * 0.22, 0.72, 1.05)


func _stair_point_along_run(rect: Rect2, stair_dir: Vector2, distance_from_entry_m: float) -> Vector2:
	var center: Vector2 = rect.get_center()
	if absf(stair_dir.x) > absf(stair_dir.y):
		var entry_x: float = rect.position.x if stair_dir.x > 0.0 else rect.position.x + rect.size.x
		return Vector2(entry_x + stair_dir.x * distance_from_entry_m, center.y)
	var entry_y: float = rect.position.y if stair_dir.y > 0.0 else rect.position.y + rect.size.y
	return Vector2(center.x, entry_y + stair_dir.y * distance_from_entry_m)


func _vertical_stair_voids_for_floor(floor_level_m: float) -> Array[Rect2]:
	return _vertical_stair_voids_for_level(floor_level_m, true)


func _vertical_stair_voids_for_ceiling(floor_level_m: float) -> Array[Rect2]:
	return _vertical_stair_voids_for_level(floor_level_m, false)


func _vertical_stair_voids_for_level(floor_level_m: float, upper_floor: bool) -> Array[Rect2]:
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
		var target_level: float = upper_room.floor_level_z_m if upper_floor else lower_room.floor_level_z_m
		if absf(target_level - floor_level_m) > 0.05:
			continue
		var rect: Rect2 = Rect2(building.room_rect_m.get(lower_room.id, Rect2()))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		result.append(_stair_vertical_void_rect(rect, _room_stair_run_direction(lower_room), lower_room.stair_turn_degrees))
	return result


func _stair_vertical_void_rect(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Rect2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	if turn_degrees >= 179.0:
		var gap_m: float = 0.18
		var cross_span_m: float = _stair_cross_span_m(rect, stair_dir)
		var flight_width_m: float = clampf((cross_span_m - gap_m) * 0.5, 0.72, 1.05)
		var shaft_width_m: float = minf(cross_span_m, flight_width_m * 2.0 + gap_m + 0.18)
		if absf(stair_dir.x) > absf(stair_dir.y):
			return Rect2(
				Vector2(rect.position.x, rect.get_center().y - shaft_width_m * 0.5),
				Vector2(rect.size.x, shaft_width_m)
			)
		return Rect2(
			Vector2(rect.get_center().x - shaft_width_m * 0.5, rect.position.y),
			Vector2(shaft_width_m, rect.size.y)
		)
	var width_m: float = minf(_stair_ramp_width_m(rect, stair_dir), maxf(0.2, _stair_cross_span_m(rect, stair_dir) - 0.2))
	var run_m: float = minf(
		maxf(0.80, _stair_long_span_m(rect, stair_dir) - _stair_top_landing_depth_m(rect, stair_dir) - 0.22),
		maxf(0.2, _stair_long_span_m(rect, stair_dir) - 0.2)
	)
	var start_margin_m: float = 0.22
	if absf(stair_dir.x) > absf(stair_dir.y):
		var x_m: float = rect.position.x + start_margin_m if stair_dir.x > 0.0 else rect.position.x + rect.size.x - start_margin_m - run_m
		return Rect2(Vector2(x_m, rect.get_center().y - width_m * 0.5), Vector2(run_m, width_m))
	var y_m: float = rect.position.y + start_margin_m if stair_dir.y > 0.0 else rect.position.y + rect.size.y - start_margin_m - run_m
	return Rect2(Vector2(rect.get_center().x - width_m * 0.5, y_m), Vector2(width_m, run_m))


func _split_rect_by_voids(rect: Rect2, voids: Array[Rect2]) -> Array[Rect2]:
	var slabs: Array[Rect2] = [rect]
	for void_rect in voids:
		var next: Array[Rect2] = []
		for slab in slabs:
			for piece in _subtract_rect(slab, void_rect):
				if piece.size.x >= 0.08 and piece.size.y >= 0.08:
					next.append(piece)
		slabs = next
	return slabs


func _subtract_rect(rect: Rect2, void_rect: Rect2) -> Array[Rect2]:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or void_rect.size.x <= 0.0 or void_rect.size.y <= 0.0:
		return [rect]
	if not rect.intersects(void_rect, true):
		return [rect]
	var cut: Rect2 = rect.intersection(void_rect)
	if cut.size.x <= 0.001 or cut.size.y <= 0.001:
		return [rect]
	var pieces: Array[Rect2] = []
	var rect_end: Vector2 = rect.position + rect.size
	var cut_end: Vector2 = cut.position + cut.size
	if cut.position.y > rect.position.y + 0.001:
		pieces.append(Rect2(rect.position, Vector2(rect.size.x, cut.position.y - rect.position.y)))
	if cut_end.y < rect_end.y - 0.001:
		pieces.append(Rect2(Vector2(rect.position.x, cut_end.y), Vector2(rect.size.x, rect_end.y - cut_end.y)))
	if cut.position.x > rect.position.x + 0.001:
		pieces.append(Rect2(Vector2(rect.position.x, cut.position.y), Vector2(cut.position.x - rect.position.x, cut.size.y)))
	if cut_end.x < rect_end.x - 0.001:
		pieces.append(Rect2(Vector2(cut_end.x, cut.position.y), Vector2(rect_end.x - cut_end.x, cut.size.y)))
	return pieces


func _rect_same(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= 0.001 and a.size.distance_to(b.size) <= 0.001


func _create_world_lighting(rects: Dictionary) -> void:
	if ambient_fill_enabled:
		var fill := OmniLight3D.new()
		fill.name = "FP_AmbientFill"
		fill.light_color = ambient_fill_color
		var fill_energy: float = ambient_fill_energy
		if not room_ceiling_lights_enabled:
			fill_energy *= 0.38 if not _exterior_is_night() else 0.12
		fill.light_energy = fill_energy
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
		if room != null and _room_is_stairwell(room):
			continue
		var height_m: float = room.height_m if room != null else 2.4
		var floor_level_m: float = room.floor_level_z_m if room != null else 0.0
		var area_m2: float = maxf(1.0, rect.size.x * rect.size.y)
		var light := OmniLight3D.new()
		light.name = "CeilingLight_%s" % str(room_id)
		light.light_color = room_ceiling_light_color
		var base_energy: float = room_ceiling_light_energy * clampf(sqrt(area_m2 / 14.0), 0.72, 1.35)
		var base_range: float = maxf(rect.size.x, rect.size.y) * 0.68 + room_ceiling_light_range_extra_m
		light.light_energy = base_energy
		light.omni_range = base_range
		light.shadow_enabled = false
		light.position = _to_world(Vector3(
			rect.position.x + rect.size.x * 0.5,
			maxf(1.8, height_m - 0.22),
			rect.position.y + rect.size.y * 0.5
		), floor_level_m)
		_world_root.add_child(light)
		_ceiling_lights_by_room[int(room_id)] = light
		_ceiling_light_base_energy_by_room[int(room_id)] = base_energy
		_ceiling_light_base_range_by_room[int(room_id)] = base_range
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
		if op.type == OpeningModel.Type.HOLE:
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
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))
	light.position = center - inward * outside_offset
	light.position.y = floor_level_m + 2.05 if op.type == OpeningModel.Type.DOOR else maxf(floor_level_m + 1.35, center.y)
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
	if op != null and op.type == OpeningModel.Type.WINDOW:
		return frame_root

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	center += normal * opening_frame_interior_offset_m
	var width_m: float = float(info.get("width_m", 0.8))
	var height_m: float = float(info.get("height_m", 2.0))
	var sill_m: float = float(info.get("sill_m", 0.0))
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))
	var horizontal: bool = String(info.get("orientation", "horizontal")) == "horizontal"
	var depth_m: float = 0.075
	var bar_m: float = 0.075
	var mat := _mat(opening_frame_color, false)
	var frame_width: float = width_m + bar_m * 2.0
	var frame_height: float = height_m + bar_m * 2.0
	var mid_y: float = sill_m + height_m * 0.5
	var top_y: float = floor_level_m + sill_m + height_m + bar_m * 0.5
	var bottom_y: float = floor_level_m + maxf(bar_m * 0.5, sill_m - bar_m * 0.5)
	mid_y += floor_level_m

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
	if not _is_apartment_building():
		_create_single_family_entry_recess(index, op, info)
		return

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var horizontal: bool = String(info.get("orientation", "horizontal")) == "horizontal"
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))
	var width_m: float = maxf(5.40, float(info.get("width_m", 0.85)) + 4.10)
	var depth_m: float = maxf(3.30, landing_recess_depth_m * 2.35)
	var corridor_height_m: float = 2.62

	var floor_center: Vector3 = center - normal * (depth_m * 0.5 + 0.08)
	floor_center.y = floor_level_m - floor_thickness_m * 0.5
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
	wall_center.y = floor_level_m + corridor_height_m * 0.5
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
		side_center.y = floor_level_m + corridor_height_m * 0.5
		_add_box(
			_world_root,
			"LandingSideWall_%02d" % index,
			side_wall_size,
			side_center,
			_mat(Color(0.66, 0.66, 0.61, 1.0), false, Color(0.0, 0.0, 0.0, 0.0), 0.0, 4250 + index),
			false
		)

	var ceiling_center: Vector3 = floor_center
	ceiling_center.y = floor_level_m + corridor_height_m + ceiling_thickness_m * 0.5
	_add_box(
		_world_root,
		"LandingCeiling_%02d" % index,
		Vector3(width_m, ceiling_thickness_m, depth_m) if horizontal else Vector3(depth_m, ceiling_thickness_m, width_m),
		ceiling_center,
		_mat(Color(0.78, 0.77, 0.71, 1.0), false),
		false
	)

	var fixture_center: Vector3 = center - normal * (depth_m * 0.62)
	fixture_center.y = floor_level_m + 2.18
	_add_box(
		_world_root,
		"LandingFixture_%02d" % index,
		Vector3(0.42, 0.035, 0.42),
		fixture_center,
		_mat(_effective_landing_light_color(), false, _effective_landing_light_color(), 0.85),
		false
	)

	var surface_center: Vector3 = wall_center + normal * (wall_thickness_m * 0.5 + 0.026)
	var neighbor_offsets: Array[float] = [-width_m * 0.36, -width_m * 0.12, width_m * 0.12]
	for door_i in range(neighbor_offsets.size()):
		var offset_t: float = float(neighbor_offsets[door_i])
		var neighbor_center: Vector3 = surface_center + tangent * offset_t
		neighbor_center.y = floor_level_m + 1.02
		_add_oriented_box(
			_world_root,
			"LandingNeighborDoor_%02d_%02d" % [index, door_i],
			neighbor_center,
			tangent,
			0.78,
			1.94,
			0.050,
			_mat(Color(0.34, 0.22, 0.13, 1.0), false),
			false
		)
		var handle_center: Vector3 = neighbor_center + tangent * 0.25 + normal * 0.038
		handle_center.y = floor_level_m + 1.02
		_add_oriented_box(
			_world_root,
			"LandingNeighborHandle_%02d_%02d" % [index, door_i],
			handle_center,
			tangent,
			0.055,
			0.055,
			0.055,
			_mat(Color(0.72, 0.58, 0.30, 1.0), false),
			false
		)

	var lift_center: Vector3 = surface_center + tangent * (width_m * 0.38)
	lift_center.y = floor_level_m + 1.04
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
	panel_center.y = floor_level_m + 1.18
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
	_create_landing_stair_run(index, floor_level_m, center - normal * 0.74 - tangent * (width_m * 0.43), -normal, tangent, true)
	_create_landing_stair_run(index + 1000, floor_level_m, center - normal * 1.05 + tangent * (width_m * 0.43), -normal, tangent, false)


func _create_single_family_entry_recess(index: int, _op: OpeningModel, info: Dictionary) -> void:
	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))
	var porch_center: Vector3 = center - normal * 0.62
	porch_center.y = floor_level_m - floor_thickness_m * 0.5
	_add_oriented_box(
		_world_root,
		"HousePorch_%02d" % index,
		porch_center,
		tangent,
		1.65,
		floor_thickness_m,
		1.20,
		_mat(Color(0.47, 0.45, 0.39, 1.0), false),
		false
	)
	var path_center: Vector3 = center - normal * 2.35
	path_center.y = floor_level_m - floor_thickness_m * 0.52
	_add_oriented_box(
		_world_root,
		"HouseEntryPath_%02d" % index,
		path_center,
		tangent,
		1.10,
		floor_thickness_m,
		3.05,
		_mat(Color(0.42, 0.42, 0.37, 1.0), false),
		false
	)
	var street_center: Vector3 = center - normal * 4.35
	street_center.y = floor_level_m - floor_thickness_m * 0.55
	_add_oriented_box(
		_world_root,
		"HouseStreet_%02d" % index,
		street_center,
		tangent,
		7.20,
		floor_thickness_m,
		0.80,
		_mat(Color(0.12, 0.13, 0.13, 1.0), false),
		false
	)
	for side_sign in [-1.0, 1.0]:
		var garden_center: Vector3 = center - normal * 1.75 + tangent * side_sign * 1.65
		garden_center.y = floor_level_m - floor_thickness_m * 0.57
		_add_oriented_box(
			_world_root,
			"HouseGarden_%02d_%s" % [index, str(side_sign)],
			garden_center,
			tangent,
			1.65,
			floor_thickness_m,
			2.45,
			_mat(Color(0.17, 0.33, 0.19, 1.0), false),
			false
		)
		var house_center: Vector3 = center - normal * 5.05 + tangent * side_sign * 2.45
		house_center.y = floor_level_m + 0.70
		_add_oriented_box(
			_world_root,
			"NeighbourHouse_%02d_%s" % [index, str(side_sign)],
			house_center,
			tangent,
			1.55,
			1.40,
			0.70,
			_mat(Color(0.55, 0.50, 0.43, 1.0), false),
			false
		)


func _create_landing_stair_run(index: int, floor_level_m: float, base_center: Vector3, run_dir: Vector3, tangent: Vector3, ascending: bool) -> void:
	var step_mat := _mat(Color(0.42, 0.37, 0.30, 1.0), false)
	for step_i in range(6):
		var step_center: Vector3 = base_center + run_dir.normalized() * (float(step_i) * 0.22)
		var rise: float = 0.055 * float(step_i + 1)
		step_center.y = floor_level_m + (rise if ascending else -rise * 0.62) + 0.035
		_add_oriented_box(
			_world_root,
			"LandingStairStep_%02d_%02d" % [index, step_i],
			step_center,
			tangent,
			0.92,
			0.07,
			0.18,
			step_mat,
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
		if _is_apartment_building():
			_create_window_city_view(root, index, info)
		else:
			_create_window_residential_view(root, index, info)


func _is_apartment_building() -> bool:
	return building != null and String(building.building_type).strip_edges().to_lower() == "apartment"


func _create_window_city_view(parent: Node3D, index: int, info: Dictionary) -> void:
	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var width_m: float = float(info.get("width_m", 1.0))
	var height_m: float = float(info.get("height_m", 1.0))
	var sill_m: float = float(info.get("sill_m", 0.9))

	_create_exterior_window_reveal(parent, index, center, normal, tangent, width_m, height_m, sill_m)

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

	if exterior_window_obstacles_enabled and city_building_count_per_window > 0:
		var count: int = maxi(1, city_building_count_per_window)
		var span_step: float = city_view_width_m / float(count)
		for slot in range(count):
			var slot_t: float = (float(slot) + 0.5) / float(count) - 0.5
			var seed: float = float(index * 31 + slot * 17)
			var building_width: float = clampf(span_step * (0.72 + fposmod(seed * 0.37, 0.32)), 1.6, 4.6)
			var building_depth: float = 0.72 + fposmod(seed * 0.19, 0.34)
			var building_height: float = 7.5 + fposmod(seed * 1.13, 7.2)
			var distance: float = city_building_distance_m + 2.8 + fposmod(seed * 0.23, 3.6)
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


func _create_window_residential_view(parent: Node3D, index: int, info: Dictionary) -> void:
	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var width_m: float = float(info.get("width_m", 1.0))
	var height_m: float = float(info.get("height_m", 1.0))
	var sill_m: float = float(info.get("sill_m", 0.9))
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))

	_create_exterior_window_reveal(parent, index, center, normal, tangent, width_m, height_m, sill_m)

	var sky_center: Vector3 = center - normal * city_backdrop_distance_m
	sky_center.y = floor_level_m + 4.2
	var sky_color: Color = Color(0.70, 0.84, 0.94, 1.0) if not _exterior_is_night() else Color(0.08, 0.12, 0.18, 1.0)
	_add_oriented_box(
		parent,
		"ResidentialSky_%02d" % index,
		sky_center,
		tangent,
		city_view_width_m * 1.35,
		10.0,
		0.08,
		_mat(sky_color, false, sky_color, 0.42 if not _exterior_is_night() else 0.10),
		false
	)

	var lawn_center: Vector3 = center - normal * 2.65
	lawn_center.y = floor_level_m - floor_thickness_m * 0.55
	_add_oriented_box(
		parent,
		"ResidentialLawn_%02d" % index,
		lawn_center,
		tangent,
		city_view_width_m * 0.62,
		floor_thickness_m,
		3.45,
		_mat(Color(0.17, 0.34, 0.20, 1.0), false, Color(0.08, 0.18, 0.08, 1.0), 0.03 if not _exterior_is_night() else 0.0),
		false
	)
	var street_center: Vector3 = center - normal * 5.55
	street_center.y = floor_level_m - floor_thickness_m * 0.58
	_add_oriented_box(
		parent,
		"ResidentialStreet_%02d" % index,
		street_center,
		tangent,
		city_view_width_m * 0.74,
		floor_thickness_m,
		0.90,
		_mat(Color(0.13, 0.14, 0.14, 1.0), false),
		false
	)
	if exterior_window_obstacles_enabled:
		for slot in range(3):
			var slot_t: float = float(slot - 1) * 2.85
			var house_center: Vector3 = center - normal * (7.2 + float(slot % 2) * 0.45) + tangent * slot_t
			house_center.y = floor_level_m + 0.78
			_add_oriented_box(
				parent,
				"ResidentialHouse_%02d_%02d" % [index, slot],
				house_center,
				tangent,
				1.75,
				1.55,
				0.82,
				_mat(Color(0.55, 0.50, 0.43, 1.0), false),
				false
			)
			var roof_center: Vector3 = house_center
			roof_center.y = floor_level_m + 1.62
			_add_oriented_box(
				parent,
				"ResidentialRoof_%02d_%02d" % [index, slot],
				roof_center,
				tangent,
				1.95,
				0.16,
				0.98,
				_mat(Color(0.31, 0.15, 0.10, 1.0), false),
				false
			)


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
	var reveal_center: Vector3 = center - normal * 0.205
	var band_depth: float = 0.035
	var band_m: float = 0.12
	var floor_level_m: float = center.y - (sill_m + height_m * 0.5)
	var facade_mat := _mat(exterior_facade_color, false)
	var top_center: Vector3 = reveal_center
	top_center.y = floor_level_m + sill_m + height_m + band_m * 0.5
	_add_oriented_box(parent, "ExteriorWindowTop_%02d" % index, top_center, tangent, width_m + band_m * 2.0, band_m, band_depth, facade_mat, false)
	var bottom_center: Vector3 = reveal_center
	bottom_center.y = floor_level_m + maxf(0.05, sill_m - band_m * 0.5)
	_add_oriented_box(parent, "ExteriorWindowBottom_%02d" % index, bottom_center, tangent, width_m + band_m * 2.0, band_m, band_depth, facade_mat, false)
	for side_sign in [-1.0, 1.0]:
		var side_center: Vector3 = reveal_center + tangent * side_sign * (width_m * 0.5 + band_m * 0.5)
		side_center.y = floor_level_m + sill_m + height_m * 0.5
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
	var slab_center: Vector3 = center - normal * 0.62
	slab_center.y = maxf(0.22, center.y - 0.50)
	_add_oriented_box(parent, "ExteriorSill_%02d" % index, slab_center, tangent, width_m + 0.36, 0.06, 0.30, _mat(Color(0.55, 0.54, 0.49, 1.0), false), false)


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
	var columns: int = clampi(int(floor(building_width / 0.95)), 1, 3)
	var rows: int = clampi(int(floor((building_height - 1.0) / 1.55)), 2, 6)
	var face_center: Vector3 = building_center + normal * (building_depth * 0.5 + 0.014)
	for row in range(rows):
		var y: float = -exterior_floor_drop_m + 0.95 + float(row) * 1.55
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


func _create_fp_furniture_nodes(rects: Dictionary) -> void:
	if building == null or _world_root == null:
		return
	var root := Node3D.new()
	root.name = "FPFurniture"
	root.visible = show_fp_furniture
	_world_root.add_child(root)

	for raw_room_id in rects.keys():
		var room_id: int = int(raw_room_id)
		var room_root := Node3D.new()
		room_root.name = "FuelObjects_%02d" % room_id
		room_root.visible = false
		root.add_child(room_root)
		_furniture_nodes_by_room[room_id] = {
			"room_id": room_id,
			"rect": Rect2(rects[raw_room_id]),
			"root": room_root,
			"fuel_obj_nodes": {},
		}


func _update_fp_furniture_visuals() -> void:
	if _furniture_nodes_by_room.is_empty():
		return
	var root: Node3D = null
	if _world_root != null:
		root = _world_root.get_node_or_null("FPFurniture") as Node3D
	if root != null:
		root.visible = show_fp_furniture
	for raw_room_id in _furniture_nodes_by_room.keys():
		var room_id: int = int(raw_room_id)
		var item: Dictionary = _furniture_nodes_by_room[raw_room_id]
		_update_fp_room_furniture(room_id, item)


func _update_fp_room_furniture(room_id: int, item: Dictionary) -> void:
	var room_root := item.get("root") as Node3D
	if room_root == null:
		return
	var fuel_obj_nodes: Dictionary = Dictionary(item.get("fuel_obj_nodes", {}))
	var rect := Rect2(item.get("rect", Rect2(Vector2.ZERO, Vector2.ONE)))
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var room_state: Dictionary = _room_state_for_furniture(room_id)
	var room_name: String = room.name if room != null else String(room_state.get("name", ""))
	var room_kind: String = room.kind if room != null else String(room_state.get("kind", ""))
	var objects: Array = _normalized_fp_furniture_objects(
		room_id,
		room_name,
		room_kind,
		rect,
		Array(room_state.get("fuel_objects", [])).duplicate()
	)

	var seen_ids: Dictionary = {}
	for raw_obj in objects:
		if typeof(raw_obj) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw_obj
		var obj_id: String = String(obj.get("id", ""))
		if obj_id == "" or obj_id.begins_with("room_proxy_"):
			continue
		var size_m: Vector2 = _vector2_from_variant(obj.get("size_m", Vector2(0.5, 0.5)), Vector2(0.5, 0.5))
		size_m.x = maxf(0.05, size_m.x)
		size_m.y = maxf(0.05, size_m.y)
		var position_m: Vector2 = _vector2_from_variant(obj.get("position_m", Vector2.ZERO), Vector2.ZERO)
		var rotation_deg: float = float(obj.get("rotation_deg", 0.0))
		var visual_center_m: Vector2 = position_m + size_m * 0.5
		var visual_size_m: Vector2 = size_m
		if not bool(obj.get("visual_pose_locked", false)):
			var visual_pose: Dictionary = FurniturePlacement3D.clamp_visual_pose(rect, position_m, size_m, rotation_deg)
			visual_center_m = Vector2(visual_pose.get("center_m", visual_center_m))
			visual_size_m = Vector2(visual_pose.get("size_m", visual_size_m))

		var kind_name: String = FurnitureVisualClassifier.visual_archetype(obj)
		var node := fuel_obj_nodes.get(obj_id) as Node3D
		if node == null:
			node = _create_fp_fuel_object_node(obj_id, kind_name, visual_size_m)
			room_root.add_child(node)
			fuel_obj_nodes[obj_id] = node
		elif FurnitureVisualClassifier.shape_needs_rebuild(node, kind_name, visual_size_m):
			_rebuild_fp_fuel_object_shape(node, kind_name, visual_size_m)
		if node == null:
			continue

		var floor_level_m: float = room.floor_level_z_m if room != null else float(room_state.get("floor_level_z_m", 0.0))
		node.position = _to_world(Vector3(
			rect.position.x + visual_center_m.x,
			0.0,
			rect.position.y + visual_center_m.y
		), floor_level_m)
		node.rotation_degrees.y = rotation_deg
		node.visible = show_fp_furniture
		node.set_meta("room_id", room_id)
		node.set_meta("object_id", obj_id)
		node.set_meta("size_x_m", visual_size_m.x)
		node.set_meta("size_y_m", visual_size_m.y)

		var state_name: String = String(obj.get("state", "cold"))
		var color: Color = FurnitureStateVisuals.color_for_state(state_name)
		var fuel_mj: float = maxf(0.01, float(obj.get("fuel_energy_MJ", 1.0)))
		var remaining_ratio: float = clampf(float(obj.get("remaining_fuel_MJ", fuel_mj)) / fuel_mj, 0.0, 1.0)
		FurnitureStateVisuals.apply(node, state_name, color, remaining_ratio, bool(obj.get("is_primary_ignition_source", false)))
		seen_ids[obj_id] = true

	for stale_id in fuel_obj_nodes.keys():
		if seen_ids.has(stale_id):
			continue
		var stale_node := fuel_obj_nodes[stale_id] as Node
		if stale_node != null:
			stale_node.free()
		fuel_obj_nodes.erase(stale_id)
	item["fuel_obj_nodes"] = fuel_obj_nodes
	room_root.visible = show_fp_furniture and fuel_obj_nodes.size() > 0


func _normalized_fp_furniture_objects(
	room_id: int,
	room_name: String,
	room_kind: String,
	rect: Rect2,
	raw_objects: Array
) -> Array:
	var normalized_objects: Array = []
	for raw_snapshot in raw_objects:
		if typeof(raw_snapshot) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = FurnitureVisualLayout.normalize_spec(
			room_id,
			room_name,
			room_kind,
			rect.size,
			Dictionary(raw_snapshot)
		)
		if not bool(normalized.get("visual_hidden", false)):
			normalized_objects.append(normalized)
	return normalized_objects


func _room_state_for_furniture(room_id: int) -> Dictionary:
	if _state.has(str(room_id)):
		var room_state: Dictionary = Dictionary(_state.get(str(room_id), {}))
		if not room_state.is_empty():
			return room_state
	if _state.has(room_id):
		var int_room_state: Dictionary = Dictionary(_state.get(room_id, {}))
		if not int_room_state.is_empty():
			return int_room_state
	return _build_static_fp_room_state(room_id)


func _build_static_fp_room_state(room_id: int) -> Dictionary:
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
		"floor_level_z_m": room.floor_level_z_m,
		"fuel_objects": _build_static_fp_fuel_object_snapshots(room),
	}


func _build_static_fp_fuel_object_snapshots(room: RoomModel) -> Array:
	var snapshots: Array = []
	if room == null:
		return snapshots
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if String(obj.id).begins_with("room_proxy_"):
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
			"state": _fp_fuel_object_state_name(int(obj.state)),
			"is_primary_ignition_source": bool(obj.is_primary_ignition_source),
		})
	return snapshots


func _fp_fuel_object_state_name(state_id: int) -> String:
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


func _create_fp_fuel_object_node(obj_id: String, kind_name: String, size_m: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "FuelObj_" + _safe_node_name(obj_id)
	_rebuild_fp_fuel_object_shape(node, kind_name, size_m)
	return node


func _rebuild_fp_fuel_object_shape(node: Node3D, kind_name: String, size_m: Vector2) -> void:
	_clear_node_children(node)
	node.set_meta("kind_name", kind_name)
	node.set_meta("size_x", size_m.x)
	node.set_meta("size_y", size_m.y)
	FurnitureShapeBuilder.rebuild(node, kind_name, size_m, 1.0, fp_furniture_generic_height_m)


func _clear_node_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.free()


func _create_fp_fire_nodes(rects: Dictionary) -> void:
	if building == null or _world_root == null:
		return
	var root := Node3D.new()
	root.name = "FPFire"
	root.visible = show_fp_fire
	_world_root.add_child(root)

	for raw_room_id in rects.keys():
		var room_id: int = int(raw_room_id)
		var room: RoomModel = building.get_room(room_id)
		var rect := Rect2(rects[raw_room_id])
		var height_m: float = _room_height(room)
		var floor_level_m: float = room.floor_level_z_m if room != null else 0.0

		var fire_root := Node3D.new()
		fire_root.name = "Fire_%02d" % room_id
		fire_root.visible = false
		root.add_child(fire_root)

		var fire_glow := FireMeshFactory.create_flame_mesh("Glow", fp_fire_glow_color, fp_fire_core_color)
		fire_root.add_child(fire_glow)

		var fire_tongues: Array[MeshInstance3D] = []
		for tongue_i in range(6):
			var tongue_color: Color = fp_fire_color.lerp(fp_fire_core_color, 0.18 + float(tongue_i) * 0.09)
			var tongue := FireMeshFactory.create_flame_mesh("Tongue_%02d" % tongue_i, tongue_color, fp_fire_core_color)
			tongue.set_meta("seed", float(room_id * 23 + tongue_i * 13 + 7))
			fire_root.add_child(tongue)
			fire_tongues.append(tongue)

		var fire_cap := FireMeshFactory.create_ceiling_cap_mesh("CeilingCap", fp_fire_ceiling_cap_color, fp_fire_core_color)
		fire_cap.visible = false
		fire_root.add_child(fire_cap)

		var fire_core := FireMeshFactory.create_flame_mesh("Core", fp_fire_core_color, fp_fire_core_color)
		fire_root.add_child(fire_core)

		var fire_light := OmniLight3D.new()
		fire_light.name = "FireLight"
		fire_light.light_color = Color(1.0, 0.42, 0.12, 1.0)
		fire_light.light_energy = 0.0
		fire_light.omni_range = fp_fire_light_range_min_m
		fire_light.shadow_enabled = false
		fire_light.position = Vector3(0.0, 0.65, 0.0)
		fire_root.add_child(fire_light)

		_fire_nodes_by_room[room_id] = {
			"room_id": room_id,
			"rect": rect,
			"height_m": height_m,
			"floor_level_m": floor_level_m,
			"fire_root": fire_root,
			"fire_glow": fire_glow,
			"fire_tongues": fire_tongues,
			"fire_cap": fire_cap,
			"fire_core": fire_core,
			"fire_light": fire_light,
			"fire_height_m": 0.0,
			"fire_radius_m": fp_fire_base_radius_m,
			"fire_cap_radius_m": 0.0,
			"fire_cap_weight": 0.0,
			"fire_available_height_m": height_m,
			"fire_light_energy_target": 0.0,
			"fire_phase": float(room_id) * 1.37,
			"fire_anchor_id": "",
		}


func _update_fp_fire_visuals() -> void:
	if _fire_nodes_by_room.is_empty():
		return
	var root: Node3D = null
	if _world_root != null:
		root = _world_root.get_node_or_null("FPFire") as Node3D
	if root != null:
		root.visible = show_fp_fire
	for raw_room_id in _fire_nodes_by_room.keys():
		var room_id: int = int(raw_room_id)
		var item: Dictionary = _fire_nodes_by_room[raw_room_id]
		_update_fp_fire_item(room_id, item)


func _update_fp_fire_item(room_id: int, item: Dictionary) -> void:
	var fire_root := item.get("fire_root") as Node3D
	if fire_root == null:
		return
	var rs: Dictionary = _room_state_for_fire(room_id)
	var hrr_kw: float = _fp_fire_hrr_kw(rs)
	var has_visible_fire: bool = show_fp_fire and hrr_kw > fp_fire_min_visible_hrr_kw
	var rect := Rect2(item.get("rect", Rect2(Vector2.ZERO, Vector2.ONE)))
	var room_height_m: float = maxf(0.24, float(item.get("height_m", boundary_height_m)))
	var anchor: Dictionary = _fp_fire_anchor(item, rect, rs)
	if anchor.is_empty():
		has_visible_fire = false
	var fire_pos: Vector3 = Vector3(anchor.get("position", _to_world(Vector3(rect.get_center().x, 0.0, rect.get_center().y))))
	var fire_base_y_m: float = float(anchor.get("base_y_m", 0.0))
	var source_radius_m: float = float(anchor.get("radius_m", fp_fire_base_radius_m))
	var available_height_m: float = maxf(0.24, room_height_m - fire_base_y_m - fp_fire_ceiling_clearance_m)

	var target_height: float = 0.0
	var target_radius: float = fp_fire_base_radius_m
	var target_cap_radius: float = 0.0
	var target_cap_weight: float = 0.0
	if has_visible_fire:
		var fire_t: float = clampf(hrr_kw / maxf(1.0, fp_fire_reference_hrr_kw), 0.0, 1.8)
		var fire_strength: float = clampf(sqrt(maxf(0.0, fire_t)), 0.0, 1.35)
		var free_plume_height_m: float = clampf(
			0.18 + fire_strength * fp_fire_max_height_m,
			0.12,
			available_height_m + fp_fire_max_height_m * 0.30
		)
		target_height = minf(free_plume_height_m, available_height_m)
		target_radius = maxf(
			source_radius_m,
			lerpf(fp_fire_base_radius_m, fp_fire_max_radius_m, clampf(fire_strength, 0.0, 1.0))
		)
		var near_ceiling_t: float = clampf(
			inverse_lerp(available_height_m * 0.82, available_height_m, free_plume_height_m),
			0.0,
			1.0
		)
		var over_ceiling_t: float = clampf(
			(free_plume_height_m - available_height_m) / maxf(0.10, fp_fire_max_height_m * 0.30),
			0.0,
			1.0
		)
		target_cap_weight = maxf(near_ceiling_t * 0.35, over_ceiling_t)
		if target_cap_weight > 0.0:
			var cap_limit_m: float = maxf(0.30, minf(fp_fire_max_radius_m * 2.8, minf(rect.size.x, rect.size.y) * 0.46))
			target_cap_radius = lerpf(fp_fire_max_radius_m * 0.70, cap_limit_m, clampf(target_cap_weight, 0.0, 1.0))

	var current_height: float = lerpf(float(item.get("fire_height_m", 0.0)), target_height, 0.28 if has_visible_fire else 0.36)
	var current_radius: float = lerpf(float(item.get("fire_radius_m", fp_fire_base_radius_m)), target_radius, 0.28)
	var current_cap_radius: float = lerpf(float(item.get("fire_cap_radius_m", 0.0)), target_cap_radius, 0.24)
	var current_cap_weight: float = lerpf(float(item.get("fire_cap_weight", 0.0)), target_cap_weight, 0.24)
	item["fire_height_m"] = current_height
	item["fire_radius_m"] = current_radius
	item["fire_cap_radius_m"] = current_cap_radius
	item["fire_cap_weight"] = current_cap_weight
	item["fire_available_height_m"] = available_height_m

	fire_root.position = fire_pos
	fire_root.visible = show_fp_fire and current_height > 0.05

	var fire_light := item.get("fire_light") as OmniLight3D
	if fire_light != null:
		var hrr_light_t: float = clampf(hrr_kw / 1000.0, 0.0, 4.0) if has_visible_fire else 0.0
		var smoke_transmission: float = _light_smoke_transmission_for_room(room_id, room_height_m)
		var target_energy: float = fp_fire_light_energy_per_1000kw * hrr_light_t * smoke_transmission if fire_root.visible else 0.0
		item["fire_light_energy_target"] = target_energy
		fire_light.light_energy = target_energy
		fire_light.omni_range = lerpf(
			fp_fire_light_range_min_m,
			fp_fire_light_range_max_m,
			clampf(hrr_kw / 1800.0, 0.0, 1.0)
		) * lerpf(0.58, 1.0, smoke_transmission)
		var light_top_m: float = maxf(0.25, available_height_m - 0.10)
		fire_light.position.y = minf(light_top_m, maxf(0.25, current_height * 0.45 + 0.45))
	if fire_root.visible:
		_animate_fp_fire_item(item)


func _room_state_for_fire(room_id: int) -> Dictionary:
	if _state.has(str(room_id)):
		return Dictionary(_state.get(str(room_id), {}))
	if _state.has(room_id):
		return Dictionary(_state.get(room_id, {}))
	return {}


func _fp_fire_hrr_kw(room_state: Dictionary) -> float:
	var hrr_kw: float = maxf(float(room_state.get("hrr_kw", 0.0)), float(room_state.get("burned_hrr_kw", 0.0)))
	var fuel_objects: Array = Array(room_state.get("fuel_objects", []))
	for raw in fuel_objects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw
		hrr_kw = maxf(hrr_kw, maxf(float(obj.get("hrr_kw", 0.0)), float(obj.get("hrr", 0.0))))
	return hrr_kw


func _fp_fire_anchor(item: Dictionary, rect: Rect2, rs: Dictionary) -> Dictionary:
	var floor_level_m: float = float(item.get("floor_level_m", 0.0))
	var center_2d: Vector2 = rect.get_center()
	var anchor_pos: Vector3 = _to_world(Vector3(center_2d.x, 0.02, center_2d.y), floor_level_m)
	var anchor_y_m: float = 0.02
	var anchor_radius_m: float = fp_fire_base_radius_m
	var best_obj: Dictionary = _fp_fire_anchor_object(item, rs)
	if best_obj.is_empty():
		item["fire_anchor_id"] = ""
		return {}

	item["fire_anchor_id"] = String(best_obj.get("id", ""))
	var pos_m: Vector2 = _vector2_from_variant(best_obj.get("position_m", rect.size * 0.5), rect.size * 0.5)
	var size_m: Vector2 = _vector2_from_variant(best_obj.get("size_m", Vector2(0.5, 0.5)), Vector2(0.5, 0.5))
	size_m.x = maxf(0.05, size_m.x)
	size_m.y = maxf(0.05, size_m.y)
	var local_center: Vector2 = pos_m + size_m * 0.5
	local_center.x = clampf(local_center.x, 0.10, maxf(0.10, rect.size.x - 0.10))
	local_center.y = clampf(local_center.y, 0.10, maxf(0.10, rect.size.y - 0.10))
	anchor_y_m = _fp_fire_base_y_for_object(best_obj)
	anchor_radius_m = clampf(
		maxf(minf(size_m.x, size_m.y) * 0.34, sqrt(maxf(0.01, size_m.x * size_m.y)) * 0.20),
		fp_fire_base_radius_m,
		fp_fire_max_radius_m
	)
	anchor_pos = _to_world(Vector3(rect.position.x + local_center.x, anchor_y_m, rect.position.y + local_center.y), floor_level_m)
	return {"position": anchor_pos, "base_y_m": anchor_y_m, "radius_m": anchor_radius_m}


func _fp_fire_anchor_object(item: Dictionary, rs: Dictionary) -> Dictionary:
	var fuel_objects: Array = Array(rs.get("fuel_objects", []))
	if fuel_objects.is_empty():
		return {}
	var room_hrr_kw: float = _fp_fire_hrr_kw(rs)
	var previous_id: String = String(item.get("fire_anchor_id", ""))
	var previous_obj: Dictionary = {}
	var previous_score: float = -1.0
	var best_obj: Dictionary = {}
	var best_score: float = -1.0
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
		if bool(obj.get("is_primary_ignition_source", false)):
			score += 240.0
		if is_previous_anchor:
			score += 180.0
		if not is_active_state and score <= 0.01 and not is_previous_anchor and room_hrr_kw <= fp_fire_min_visible_hrr_kw:
			continue
		if score > best_score:
			best_score = score
			best_obj = obj
		if is_previous_anchor:
			previous_score = score
	if not previous_obj.is_empty() and previous_score > maxf(1.0, best_score * 0.35):
		return previous_obj
	return best_obj


func _fp_fire_base_y_for_object(obj: Dictionary) -> float:
	var elevation_m: float = maxf(0.0, float(obj.get("elevation_m", 0.0)))
	var label: String = ("%s %s" % [String(obj.get("kind", "")), String(obj.get("name", ""))]).to_lower()
	var object_top_m: float = 0.08
	if label.contains("sofa") or label.contains("sillon") or label.contains("armchair"):
		object_top_m = 0.34
	elif label.contains("cama") or label.contains("bed") or label.contains("mattress"):
		object_top_m = 0.42
	elif label.contains("mesa") or label.contains("table") or label.contains("desk"):
		object_top_m = 0.74
	elif label.contains("chair") or label.contains("silla"):
		object_top_m = 0.46
	elif label.contains("cabinet") or label.contains("armario") or label.contains("shelf"):
		object_top_m = 0.62
	elif label.contains("curtain") or label.contains("cortina"):
		object_top_m = 0.95
	return clampf(elevation_m + object_top_m, 0.02, 1.25)


func _animate_fp_fire() -> void:
	for raw_room_id in _fire_nodes_by_room.keys():
		var item: Dictionary = _fire_nodes_by_room[raw_room_id]
		var fire_root := item.get("fire_root") as Node3D
		if fire_root != null and fire_root.visible:
			_animate_fp_fire_item(item)


func _animate_fp_fire_item(item: Dictionary) -> void:
	FireAnimation3D.animate(item, _fp_fire_phase, {
		"meters_to_units": 1.0,
		"fire_base_radius_m": fp_fire_base_radius_m,
		"default_room_height_m": boundary_height_m,
		"fire_flicker_strength": fp_fire_flicker_strength,
		"fire_ceiling_cap_thickness_m": fp_fire_ceiling_cap_thickness_m,
	})


func _create_safety_markers(rects: Dictionary) -> void:
	if building == null or _world_root == null:
		return
	var root := Node3D.new()
	root.name = "SafetyMarkers"
	_world_root.add_child(root)

	if show_fp_detectors:
		for raw_det in building.detectors:
			if typeof(raw_det) != TYPE_DICTIONARY:
				continue
			var det: Dictionary = raw_det
			var room_id: int = int(det.get("room_id", -1))
			if not rects.has(room_id):
				continue
			var room: RoomModel = building.get_room(room_id)
			var rect := Rect2(rects[room_id])
			var det_id: String = String(det.get("id", "det_%d" % _detector_nodes.size()))
			var node := _create_fp_detector_marker(det_id)
			node.position = _safety_world_position(det, rect, room, _room_height(room) - 0.08)
			root.add_child(node)
			_detector_nodes[det_id] = node

	if show_fp_victims:
		for raw_vic in building.victims:
			if typeof(raw_vic) != TYPE_DICTIONARY:
				continue
			var vic: Dictionary = raw_vic
			var room_id: int = int(vic.get("room_id", -1))
			if not rects.has(room_id):
				continue
			var room: RoomModel = building.get_room(room_id)
			var rect := Rect2(rects[room_id])
			var vic_id: String = String(vic.get("id", "vic_%d" % _victim_nodes.size()))
			var node := _create_fp_victim_marker(vic_id)
			node.position = _safety_world_position(vic, rect, room, 0.0)
			root.add_child(node)
			_victim_nodes[vic_id] = node

	_update_safety_marker_states()


func _create_fp_detector_marker(detector_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Detector_" + _safe_node_name(detector_id)
	root.set_meta("detector_id", detector_id)
	root.set_meta("alarm_triggered", false)
	root.set_meta("alarm_active", false)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MarkerMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.11
	mesh.bottom_radius = 0.11
	mesh.height = 0.035
	mesh.radial_segments = 24
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _mat(fp_detector_color, false)
	root.add_child(mesh_instance)
	root.add_child(_create_fp_detector_alarm_player())
	return root


func _create_fp_detector_alarm_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "DetectorAlarm"
	player.stream = _get_detector_alarm_stream()
	player.volume_db = fp_detector_alarm_volume_db
	player.max_distance = fp_detector_alarm_max_distance_m
	player.autoplay = false
	player.set_meta("simufire_fp_alarm", true)
	return player


func _get_detector_alarm_stream() -> AudioStreamWAV:
	if _detector_alarm_stream == null:
		_detector_alarm_stream = _build_detector_alarm_stream()
	return _detector_alarm_stream


func _build_detector_alarm_stream() -> AudioStreamWAV:
	var sample_rate: int = 22050
	var interval_s: float = maxf(fp_detector_alarm_interval_s, fp_detector_alarm_beep_duration_s + 0.02)
	var total_frames: int = maxi(1, int(round(interval_s * float(sample_rate))))
	var beep_frames: int = clampi(int(round(fp_detector_alarm_beep_duration_s * float(sample_rate))), 1, total_frames)
	var fade_frames: int = maxi(1, mini(int(beep_frames / 2), int(round(0.012 * float(sample_rate)))))
	var frequency_hz: float = clampf(fp_detector_alarm_frequency_hz, 80.0, 6000.0)
	var data := PackedByteArray()
	data.resize(total_frames * 2)
	for i in range(total_frames):
		var sample: float = 0.0
		if i < beep_frames:
			var envelope: float = 1.0
			if i < fade_frames:
				envelope = float(i) / float(fade_frames)
			elif i > beep_frames - fade_frames:
				envelope = float(beep_frames - i) / float(fade_frames)
			sample = sin(TAU * frequency_hz * float(i) / float(sample_rate)) * 0.38 * clampf(envelope, 0.0, 1.0)
		var pcm: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		var unsigned_pcm: int = pcm & 0xffff
		data[i * 2] = unsigned_pcm & 0xff
		data[i * 2 + 1] = (unsigned_pcm >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total_frames
	return stream


func _create_fp_victim_marker(victim_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Victim_" + _safe_node_name(victim_id)
	var mat := _mat(fp_victim_color, false)
	var body := _create_fp_human_limb_mesh("MarkerMesh", 0.16, 0.70, mat)
	body.rotation_degrees.x = 90.0
	body.position = Vector3(0.0, 0.14, 0.0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.26
	head_mesh.radial_segments = 14
	head_mesh.rings = 7
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.14, -0.48)
	head.material_override = mat
	root.add_child(head)
	for side in [-1.0, 1.0]:
		var arm := _create_fp_human_limb_mesh("Arm_%s" % str(side), 0.055, 0.48, mat)
		arm.rotation_degrees.z = 90.0
		arm.rotation_degrees.y = 12.0 * side
		arm.position = Vector3(side * 0.31, 0.10, -0.05)
		root.add_child(arm)
		var leg := _create_fp_human_limb_mesh("Leg_%s" % str(side), 0.07, 0.56, mat)
		leg.rotation_degrees.x = 90.0
		leg.rotation_degrees.z = 7.0 * side
		leg.position = Vector3(side * 0.12, 0.11, 0.50)
		root.add_child(leg)
	return root


func _create_fp_human_limb_mesh(node_name: String, radius_m: float, length_m: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius_m
	mesh.height = length_m
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	return mesh_instance


func _safety_world_position(data: Dictionary, rect: Rect2, room: RoomModel, y_m: float) -> Vector3:
	var local_pos: Vector2 = _safety_local_position(data, rect)
	var floor_level_m: float = room.floor_level_z_m if room != null else 0.0
	return _to_world(Vector3(rect.position.x + local_pos.x, y_m, rect.position.y + local_pos.y), floor_level_m)


func _safety_local_position(data: Dictionary, rect: Rect2) -> Vector2:
	if data.has("x_m") and data.has("y_m"):
		return Vector2(
			clampf(float(data.get("x_m", rect.size.x * 0.5)), 0.0, rect.size.x),
			clampf(float(data.get("y_m", rect.size.y * 0.5)), 0.0, rect.size.y)
		)
	return rect.size * 0.5


func _room_height(room: RoomModel) -> float:
	return room.height_m if room != null else boundary_height_m


func _update_safety_marker_states() -> void:
	var detector_states: Dictionary = _state_records_by_id(Array(_state.get("detectors", [])))
	for det_id in _detector_nodes.keys():
		var node := _detector_nodes[det_id] as Node3D
		if node == null:
			continue
		node.visible = show_fp_detectors
		var record: Dictionary = detector_states.get(det_id, {})
		var triggered: bool = bool(record.get("triggered", node.get_meta("alarm_triggered", false)))
		_set_marker_material(node, fp_detector_triggered_color if triggered else fp_detector_color)
		_sync_detector_alarm(node, triggered)

	var victim_states: Dictionary = _state_records_by_id(Array(_state.get("victims", [])))
	for vic_id in _victim_nodes.keys():
		var node := _victim_nodes[vic_id] as Node3D
		if node == null:
			continue
		node.visible = show_fp_victims
		var record: Dictionary = victim_states.get(vic_id, {})
		var vic_fed: float = float(record.get("fed", 0.0))
		var vic_color: Color
		if vic_fed >= fp_victim_fed_fatal_threshold:
			vic_color = fp_victim_fatal_color
		elif vic_fed >= fp_victim_fed_incapacitated_threshold:
			vic_color = fp_victim_incapacitated_color
		else:
			vic_color = fp_victim_color
		_set_marker_material(node, vic_color)


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


func _set_marker_material(root: Node3D, color: Color) -> void:
	_set_marker_material_recursive(root, _mat(color, false))


func _sync_detector_alarm(detector_node: Node3D, triggered: bool) -> void:
	detector_node.set_meta("alarm_triggered", triggered)
	var alarm_active: bool = _active and fp_detector_alarm_enabled and show_fp_detectors and detector_node.visible and triggered
	detector_node.set_meta("alarm_active", alarm_active)
	var player := detector_node.get_node_or_null("DetectorAlarm") as AudioStreamPlayer3D
	if player == null:
		return
	player.volume_db = fp_detector_alarm_volume_db
	player.max_distance = fp_detector_alarm_max_distance_m
	if alarm_active:
		if player.stream == null:
			player.stream = _get_detector_alarm_stream()
		if not player.playing:
			player.play()
	elif player.playing:
		player.stop()


func _stop_detector_alarms() -> void:
	for det_id in _detector_nodes.keys():
		var node := _detector_nodes[det_id] as Node3D
		if node == null:
			continue
		node.set_meta("alarm_active", false)
		var player := node.get_node_or_null("DetectorAlarm") as AudioStreamPlayer3D
		if player != null and player.playing:
			player.stop()


func _set_marker_material_recursive(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_set_marker_material_recursive(child, material)


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

	var glass_w: float = maxf(0.08, leaf_width_m * 0.94)
	var glass_h: float = maxf(0.12, height_m * 0.94)
	var frame_m: float = minf(0.055, maxf(0.028, leaf_width_m * 0.055))
	var frame_color: Color = opening_frame_color.lightened(0.08)
	_add_local_box(leaf, "Glass", Vector3.ZERO, Vector3(glass_w, glass_h, thickness_m * 0.30), window_glass_closed_color, false)
	_add_local_box(leaf, "LeafFrameTop", Vector3(0.0, glass_h * 0.5 - frame_m * 0.5, 0.0), Vector3(glass_w, frame_m, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafFrameBottom", Vector3(0.0, -glass_h * 0.5 + frame_m * 0.5, 0.0), Vector3(glass_w, frame_m, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafFrameLeft", Vector3(-glass_w * 0.5 + frame_m * 0.5, 0.0, 0.0), Vector3(frame_m, glass_h, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafFrameRight", Vector3(glass_w * 0.5 - frame_m * 0.5, 0.0, 0.0), Vector3(frame_m, glass_h, thickness_m), frame_color, false)
	_add_local_box(leaf, "LeafHandle", Vector3(handle_sign * glass_w * 0.34, -glass_h * 0.03, -thickness_m * 0.72), Vector3(0.035, glass_h * 0.18, 0.035), Color(0.76, 0.58, 0.27, 1.0), false)
	_create_window_broken_detail(leaf, glass_w, glass_h, thickness_m)
	_set_window_leaf_broken(leaf, false)
	return leaf


func _create_window_broken_detail(leaf: Node3D, glass_w: float, glass_h: float, thickness_m: float) -> void:
	var hw: float = glass_w * 0.5
	var hh: float = glass_h * 0.5
	var z: float = -thickness_m * 0.48
	_add_local_glass_shard(leaf, "BrokenShardTop", [
		Vector2(-hw * 0.92, hh * 0.88),
		Vector2(-hw * 0.10, hh * 0.92),
		Vector2(-hw * 0.24, hh * 0.16),
		Vector2(-hw * 0.78, hh * 0.28)
	], z)
	_add_local_glass_shard(leaf, "BrokenShardSide", [
		Vector2(hw * 0.22, hh * 0.76),
		Vector2(hw * 0.88, hh * 0.86),
		Vector2(hw * 0.78, -hh * 0.20),
		Vector2(hw * 0.34, -hh * 0.02)
	], z)
	_add_local_glass_shard(leaf, "BrokenShardBottom", [
		Vector2(-hw * 0.76, -hh * 0.32),
		Vector2(-hw * 0.22, -hh * 0.10),
		Vector2(hw * 0.02, -hh * 0.82),
		Vector2(-hw * 0.84, -hh * 0.88)
	], z)
	_add_local_rotated_box(leaf, "CrackA", Vector3(-hw * 0.16, hh * 0.32, z - 0.002), Vector3(glass_w * 0.72, 0.010, 0.012), window_glass_crack_color, deg_to_rad(-28.0))
	_add_local_rotated_box(leaf, "CrackB", Vector3(hw * 0.10, -hh * 0.10, z - 0.003), Vector3(glass_w * 0.56, 0.010, 0.012), window_glass_crack_color, deg_to_rad(34.0))
	_add_local_rotated_box(leaf, "CrackC", Vector3(hw * 0.26, hh * 0.22, z - 0.004), Vector3(glass_h * 0.44, 0.010, 0.012), window_glass_crack_color, deg_to_rad(76.0))


func _add_local_glass_shard(leaf: Node3D, node_name: String, points: Array, z: float) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	for raw_point in points:
		var point: Vector2 = raw_point
		vertices.append(Vector3(point.x, point.y, z))
	var indices := PackedInt32Array([0, 1, 2])
	if vertices.size() == 3:
		indices = PackedInt32Array([0, 1, 2])
	elif vertices.size() >= 4:
		indices = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	var mat := _mat(window_glass_shard_color, true)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	leaf.add_child(node)
	return node


func _add_local_rotated_box(parent: Node3D, node_name: String, center_m: Vector3, size_m: Vector3, color: Color, rotation_z: float) -> MeshInstance3D:
	var node := _add_local_box(parent, node_name, center_m, size_m, color, false)
	node.rotation.z = rotation_z
	return node


func _set_window_leaf_broken(leaf: Node3D, broken: bool) -> void:
	if leaf == null:
		return
	var glass := leaf.get_node_or_null("Glass") as MeshInstance3D
	if glass != null:
		glass.visible = not broken
	for child in leaf.get_children():
		if not (child is Node3D):
			continue
		var child_name: String = String(child.name)
		if child_name.begins_with("BrokenShard") or child_name.begins_with("Crack"):
			(child as Node3D).visible = broken


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
	if with_collision and parent is StaticBody3D:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size_m
		shape.shape = box
		shape.position = center_m
		parent.add_child(shape)
	return mesh


func _safe_node_name(value: String) -> String:
	var result: String = value.strip_edges()
	if result == "":
		return "marker"
	result = result.replace(" ", "_")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	result = result.replace(":", "_")
	return result


func _create_outer_boundary() -> void:
	var grow: float = 0.22
	var rect: Rect2 = _bounds_m.grow(grow)
	var vertical_span: Dictionary = _building_vertical_span()
	var min_y: float = float(vertical_span.get("min_y", 0.0))
	var max_y: float = float(vertical_span.get("max_y", boundary_height_m))
	var height_m: float = maxf(boundary_height_m, max_y - min_y + 0.35)
	var center_y: float = min_y + height_m * 0.5
	_create_boundary_segment(Vector3(rect.position.x + rect.size.x * 0.5, center_y, rect.position.y - grow), Vector3(rect.size.x + grow * 2.0, height_m, wall_thickness_m))
	_create_boundary_segment(Vector3(rect.position.x + rect.size.x * 0.5, center_y, rect.position.y + rect.size.y + grow), Vector3(rect.size.x + grow * 2.0, height_m, wall_thickness_m))
	_create_boundary_segment(Vector3(rect.position.x - grow, center_y, rect.position.y + rect.size.y * 0.5), Vector3(wall_thickness_m, height_m, rect.size.y + grow * 2.0))
	_create_boundary_segment(Vector3(rect.position.x + rect.size.x + grow, center_y, rect.position.y + rect.size.y * 0.5), Vector3(wall_thickness_m, height_m, rect.size.y + grow * 2.0))


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
	var input_vec: Vector2 = FPPlayerMotion.read_input_vector()
	var direction: Vector3 = FPPlayerMotion.horizontal_direction(global_transform.basis, input_vec)
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
		if _prompt_panel != null:
			_prompt_panel.visible = false
		return
	var op: OpeningModel = building.get_opening_at(_nearest_opening_index)
	if op == null:
		if _prompt_panel != null:
			_prompt_panel.visible = false
		return
	if op.type == OpeningModel.Type.WINDOW and op.glass_broken:
		_prompt_label.text = "Ventana rota | ventilacion %.0f%%" % (op.open_fraction * 100.0)
		if _prompt_panel != null:
			_prompt_panel.visible = true
		return
	if _f_key_down and _f_hold_opening_index == _nearest_opening_index:
		var kind: String = "puerta" if op.type == OpeningModel.Type.DOOR else "ventana"
		var selected_pct: int = int(round(_f_hold_fraction * 100.0))
		if _f_hold_mode:
			_prompt_label.text = "F pulsado: rueda o 1-5 para %s (%d%%). Suelta para aplicar." % [kind, selected_pct]
		else:
			var toggle_pct: int = 0 if op.open_fraction > 0.01 else 100
			_prompt_label.text = "Suelta F: %s %d%% | manten F para elegir grado" % [kind, toggle_pct]
	else:
		var toggle_frac: float = 0.0 if op.open_fraction > 0.01 else 1.0
		_prompt_label.text = FPOpeningInteraction.prompt_text(op.type == OpeningModel.Type.DOOR, op.open_fraction, toggle_frac)
	if _prompt_panel != null:
		_prompt_panel.visible = true


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
	var smoke_view: Dictionary = _compute_fp_smoke_view(room_state)
	var heat_tint: float = float(smoke_view.get("heat_tint", 0.0))
	var alpha: float = float(smoke_view.get("overlay_alpha", 0.0))
	_visibility_overlay.color = Color(
		lerpf(0.08, 0.18, heat_tint),
		lerpf(0.09, 0.11, heat_tint),
		lerpf(0.09, 0.07, heat_tint),
		alpha
	)


func _compute_fp_smoke_view(room_state: Dictionary) -> Dictionary:
	var room_rect := Rect2()
	if building != null and _current_room_id >= 0:
		var rects: Dictionary = building.get_room_rects_m()
		room_rect = Rect2(rects.get(_current_room_id, Rect2()))
	var eye_world_y_m: float = _camera.global_position.y if _camera != null else global_position.y + _current_height()
	var eye_height_m: float = maxf(0.0, eye_world_y_m - _get_room_floor_level(_current_room_id))
	return FPVisibilityOverlay.compute(room_state, room_rect, eye_height_m, {
		"clear_visibility_m": fp_visibility_clear_m,
		"visibility_reference_m": smoke_overlay_visibility_reference_m,
		"layer_clearance_m": smoke_overlay_layer_clearance_m,
		"layer_transition_m": smoke_overlay_layer_transition_m,
		"max_alpha": smoke_overlay_max_alpha
	})


func _update_status_hud(force: bool = false) -> void:
	if _fp_status_label == null:
		return
	var now_msec: int = Time.get_ticks_msec()
	var min_interval_msec: int = int(maxf(0.01, fp_hud_refresh_interval_s) * 1000.0)
	if not force and _last_fp_hud_update_msec > 0 and now_msec - _last_fp_hud_update_msec < min_interval_msec:
		return
	_last_fp_hud_update_msec = now_msec
	var room_label: String = "SIN SALA"
	var visibility_label: String = "Vis --"
	var has_data: bool = false
	if building != null:
		_current_room_id = _find_current_room_id()
		if _current_room_id >= 0:
			room_label = "R%d" % _current_room_id
			var room_state: Dictionary = Dictionary(_state.get(str(_current_room_id), {}))
			var room_name: String = String(room_state.get("name", ""))
			if room_name != "":
				room_label = "%s %s" % [room_label, room_name]
			if not room_state.is_empty():
				var smoke_view: Dictionary = _compute_fp_smoke_view(room_state)
				visibility_label = _format_fp_visibility(float(smoke_view.get("fp_visibility_m", room_state.get("visibility_m", 30.0))))
				_update_technical_overlay(room_state, smoke_view)
				has_data = true
	_fp_status_label.text = "FP | %s | %s | %s\nESC salir | F usar | CTRL postura" % [
		room_label,
		_stance_label(),
		visibility_label
	]
	var technical_visible: bool = show_technical_overlay and has_data
	if _technical_overlay_panel != null:
		_technical_overlay_panel.visible = technical_visible
	if _visibility_readout_panel != null:
		_visibility_readout_panel.visible = show_visibility_readout and has_data and not technical_visible
	if _visibility_readout_label != null and has_data:
		_visibility_readout_label.text = visibility_label


func _update_technical_overlay(room_state: Dictionary, smoke_view: Dictionary) -> void:
	if _technical_overlay_label == null:
		return
	# Temperatura según postura: usa campos interpolados por altura del motor de simulación.
	var temp_c: float
	match _stance:
		STANCE_STAND:
			temp_c = float(room_state.get("temp_at_1_8m_c", room_state.get("temp_upper_c", 20.0)))
		STANCE_CROUCH:
			temp_c = float(room_state.get("temp_at_1_1m_c", room_state.get("temp_upper_c", 20.0)))
		_: # STANCE_PRONE
			temp_c = float(room_state.get("temp_at_0_5m_c", room_state.get("temp_lower_c", 20.0)))
	# Gases: usa la capa coherente con la postura para evitar mezclar upper y promedio.
	var co_ppm: float = float(room_state.get("co_upper_ppm", 0.0))
	var co2_vol_pct: float = float(room_state.get("co2_upper_ppm", 4000.0)) / 10000.0
	var o2_key: String = "o2_upper" if _stance == STANCE_STAND else "o2_lower"
	var o2_vol_pct: float = float(room_state.get(o2_key, room_state.get("o2", 0.209))) * 100.0
	var hcn_ppm: float = float(room_state.get("hcn_upper_ppm", 0.0))
	var fed_val: float = float(room_state.get("fed", 0.0))
	var vis_m: float = float(smoke_view.get("fp_visibility_m", room_state.get("visibility_m", 30.0)))
	_technical_overlay_label.text = (
		"T  %5.0f °C\nCO %5.0f ppm\nCO₂ %4.1f %%vol\nO₂  %4.1f %%vol\nHCN %4.0f ppm\nFED  %.2f\nVis  %s"
		% [temp_c, co_ppm, co2_vol_pct, o2_vol_pct, hcn_ppm, fed_val, _format_fp_visibility(vis_m)]
	)

func _format_fp_visibility(visibility_m: float) -> String:
	return FPVisibilityOverlay.format_visibility(visibility_m, fp_visibility_clear_m)


func _stance_label() -> String:
	return FPPlayerMotion.stance_label(_stance, STANCE_CROUCH, STANCE_PRONE)


func _find_current_room_id() -> int:
	if building == null:
		return -1
	var pos_m := Vector2(global_position.x - _origin_offset_m.x, global_position.z - _origin_offset_m.y)
	var y_m: float = global_position.y
	var rects: Dictionary = building.get_room_rects_m()
	var best_room_id: int = -1
	var best_floor_m: float = -INF
	for key in rects.keys():
		var rect: Rect2 = Rect2(rects[key])
		if not rect.has_point(pos_m):
			continue
		var room_id: int = int(key)
		var room: RoomModel = building.get_room(room_id)
		var floor_level_m: float = room.floor_level_z_m if room != null else 0.0
		var height_m: float = room.height_m if room != null else 2.5
		if y_m >= floor_level_m - 0.25 and y_m <= floor_level_m + height_m + 0.35 and floor_level_m > best_floor_m:
			best_floor_m = floor_level_m
			best_room_id = room_id
	if best_room_id != -1:
		return best_room_id

	var nearest_room_id: int = -1
	var nearest_vertical_delta: float = INF
	for key in rects.keys():
		var rect: Rect2 = Rect2(rects[key])
		if not rect.has_point(pos_m):
			continue
		var room_id: int = int(key)
		var floor_level_m: float = _get_room_floor_level(room_id)
		var delta_m: float = absf(y_m - floor_level_m)
		if delta_m < nearest_vertical_delta:
			nearest_vertical_delta = delta_m
			nearest_room_id = room_id
	return nearest_room_id


func get_player_marker_state() -> Dictionary:
	if building == null:
		return {}
	var room_id: int = _find_current_room_id()
	var floor_level_m: float = _get_room_floor_level(room_id) if room_id >= 0 else global_position.y
	return {
		"active": _active,
		"room_id": room_id,
		"position_m": Vector2(global_position.x - _origin_offset_m.x, global_position.z - _origin_offset_m.y),
		"floor_level_z_m": floor_level_m,
		"yaw_deg": rad_to_deg(_yaw)
	}


func _next_opening_fraction(current: float) -> float:
	return FPOpeningInteraction.next_fraction(current, OPENING_FRACTION_STEPS)


func _begin_opening_hold() -> void:
	if building == null:
		return
	_nearest_opening_index = _find_nearest_opening()
	if _nearest_opening_index < 0:
		return
	var op: OpeningModel = building.get_opening_at(_nearest_opening_index)
	if op == null:
		return
	if op.type == OpeningModel.Type.WINDOW and op.glass_broken:
		return
	_f_key_down = true
	_f_hold_mode = false
	_f_hold_elapsed_s = 0.0
	_f_hold_opening_index = _nearest_opening_index
	_f_hold_fraction = _closest_opening_step(op.open_fraction)
	_update_prompt()


func _update_opening_hold(delta: float) -> void:
	if not _f_key_down:
		return
	_f_hold_elapsed_s += delta
	if not _f_hold_mode and _f_hold_elapsed_s >= OPENING_HOLD_THRESHOLD_S:
		_f_hold_mode = true
		_update_prompt()


func _finish_opening_hold() -> void:
	if not _f_key_down:
		return
	var opening_index: int = _f_hold_opening_index
	var use_hold_fraction: bool = _f_hold_mode
	var selected_fraction: float = _f_hold_fraction
	_cancel_opening_hold()
	if building == null or opening_index < 0:
		return
	var op: OpeningModel = building.get_opening_at(opening_index)
	if op == null:
		return
	if op.type == OpeningModel.Type.WINDOW and op.glass_broken:
		return
	var next_frac: float = selected_fraction if use_hold_fraction else (0.0 if op.open_fraction > 0.01 else 1.0)
	_apply_opening_fraction(opening_index, next_frac)


func _cancel_opening_hold() -> void:
	_f_key_down = false
	_f_hold_mode = false
	_f_hold_elapsed_s = 0.0
	_f_hold_opening_index = -1
	_f_hold_fraction = 0.0


func _adjust_held_opening_fraction(direction: int) -> void:
	if building == null or _f_hold_opening_index < 0:
		return
	_f_hold_mode = true
	var idx: int = _opening_step_index(_f_hold_fraction)
	idx = clampi(idx + (1 if direction > 0 else -1), 0, OPENING_FRACTION_STEPS.size() - 1)
	_f_hold_fraction = float(OPENING_FRACTION_STEPS[idx])
	_update_prompt()


func _set_held_opening_fraction_by_step(step_index: int) -> void:
	if building == null or _f_hold_opening_index < 0:
		return
	_f_hold_mode = true
	var idx: int = clampi(step_index, 0, OPENING_FRACTION_STEPS.size() - 1)
	_f_hold_fraction = float(OPENING_FRACTION_STEPS[idx])
	_update_prompt()


func _closest_opening_step(value: float) -> float:
	return float(OPENING_FRACTION_STEPS[_opening_step_index(value)])


func _opening_step_index(value: float) -> int:
	var closest_idx: int = 0
	var best_delta: float = INF
	for i in range(OPENING_FRACTION_STEPS.size()):
		var delta: float = absf(value - float(OPENING_FRACTION_STEPS[i]))
		if delta < best_delta:
			best_delta = delta
			closest_idx = i
	return closest_idx


func _apply_opening_fraction(opening_index: int, next_frac: float) -> void:
	if building == null:
		return
	if building.set_opening_fraction(opening_index, clampf(next_frac, 0.0, 1.0)):
		_update_opening_panel(opening_index)
		opening_changed.emit()
	_update_prompt()


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
	if op.type == OpeningModel.Type.WINDOW and op.glass_broken:
		return
	var next_frac: float = 0.0 if op.open_fraction > 0.01 else 1.0
	_apply_opening_fraction(_nearest_opening_index, next_frac)


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
	open_amount: float,
	broken: bool = false
) -> void:
	var visual_open_amount: float = 0.0 if broken else open_amount
	var pose: Dictionary = FPOpeningVisuals.compute_window_leaf_pair(
		center,
		tangent,
		normal,
		base_yaw,
		width_m,
		visual_open_amount,
		deg_to_rad(window_open_angle_deg),
		opening_panel_clearance_m
	)

	left_leaf.visible = true
	right_leaf.visible = true
	left_leaf.position = Vector3(pose.get("left_center", center))
	right_leaf.position = Vector3(pose.get("right_center", center))
	left_leaf.rotation = Vector3(0.0, float(pose.get("left_yaw", base_yaw)), 0.0)
	right_leaf.rotation = Vector3(0.0, float(pose.get("right_yaw", base_yaw)), 0.0)
	var glass_color: Color = window_glass_closed_color.lerp(window_glass_open_color, clampf(visual_open_amount, 0.0, 1.0))
	_set_window_leaf_glass_color(left_leaf, glass_color)
	_set_window_leaf_glass_color(right_leaf, glass_color)
	_set_window_leaf_broken(left_leaf, broken)
	_set_window_leaf_broken(right_leaf, broken)


func _cycle_stance() -> void:
	_stance = FPPlayerMotion.next_stance(_stance)
	_apply_stance(false)
	_update_status_hud()


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
	return FPPlayerMotion.stance_height(
		_stance,
		STANCE_STAND,
		STANCE_CROUCH,
		STANCE_PRONE,
		person_height_m,
		crouch_height_m,
		prone_height_m
	)


func _current_speed() -> float:
	return FPPlayerMotion.stance_speed(
		_stance,
		STANCE_STAND,
		STANCE_CROUCH,
		STANCE_PRONE,
		stand_speed_m_s,
		crouch_speed_m_s,
		prone_speed_m_s
	)


func _find_nearest_opening() -> int:
	var best_index: int = -1
	var best_score: float = INF
	var player_xz := Vector2(global_position.x, global_position.z)
	var view_origin: Vector3 = _camera.global_position if _camera != null else global_position
	var view_forward: Vector3 = (-_camera.global_transform.basis.z).normalized() if _camera != null else (-global_transform.basis.z).normalized()
	for index in _opening_nodes.keys():
		var op: OpeningModel = building.get_opening_at(int(index))
		if op == null:
			continue
		var info: Dictionary = Dictionary(_opening_nodes[index]).get("info", {})
		var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
		var dist: float = player_xz.distance_to(Vector2(center.x, center.z))
		if dist > interaction_range_m:
			continue
		var aim_target := Vector3(center.x, clampf(view_origin.y, 0.65, center.y + 0.25), center.z)
		var to_opening: Vector3 = (aim_target - view_origin).normalized()
		var aim_dot: float = view_forward.dot(to_opening)
		if aim_dot < interaction_aim_dot_min:
			continue
		var score: float = dist + (1.0 - aim_dot) * 0.55
		if score < best_score:
			best_score = score
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
	var is_broken_window: bool = is_window and op.glass_broken
	var open_amount: float = clampf(op.open_fraction, 0.0, 1.0)
	var width_m: float = float(info.get("width_m", 0.8))
	var height_m: float = float(info.get("height_m", 2.0))
	var sill_m: float = float(info.get("sill_m", 0.0))
	var floor_level_m: float = float(info.get("floor_level_m", 0.0))
	var panel_thickness: float = closed_door_thickness_m if is_door else 0.045
	var size := Vector3(width_m, height_m, panel_thickness)

	var center: Vector3 = Vector3(info.get("center", Vector3.ZERO))
	center.y = floor_level_m + sill_m + height_m * 0.5
	var visual_center: Vector3 = center
	var tangent: Vector3 = Vector3(info.get("tangent", Vector3.RIGHT)).normalized()
	var normal: Vector3 = Vector3(info.get("normal", Vector3.FORWARD)).normalized()
	var smoke_transmission: float = _light_smoke_transmission_for_opening(op)
	var base_yaw: float = atan2(-tangent.z, tangent.x)
	var visual_yaw: float = base_yaw
	if is_door:
		var closed_side: Vector3 = normal if _door_swing_direction(op) == "in" else -normal
		visual_center += closed_side * opening_panel_clearance_m
	elif is_window:
		visual_center -= normal * opening_panel_clearance_m

	if is_door and open_amount > 0.01:
		var base_swing_sign: float = -1.0 if tangent.cross(normal).y < 0.0 else 1.0
		var hinge_sign: float = -1.0 if _door_hinge_side(op) == "left" else 1.0
		var direction_sign: float = 1.0 if _door_swing_direction(op) == "in" else -1.0
		var swing_sign: float = base_swing_sign * -hinge_sign * direction_sign
		visual_yaw = base_yaw + deg_to_rad(82.0) * open_amount * swing_sign
		var hinge: Vector3 = center + tangent * hinge_sign * width_m * 0.5
		var rotated_tangent: Vector3 = Basis(Vector3.UP, visual_yaw).x.normalized()
		var clearance_side: Vector3 = normal if _door_swing_direction(op) == "in" else -normal
		visual_center = hinge - rotated_tangent * hinge_sign * width_m * 0.5 + clearance_side * opening_panel_clearance_m
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
			open_amount,
			is_broken_window
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
		shape.disabled = is_broken_window or (not window_collision_when_closed) or open_amount > 0.05
		if light != null:
			var window_area_factor: float = clampf(width_m * height_m / 2.2, 0.35, 1.55)
			light.light_color = _effective_window_light_color()
			light.light_energy = _effective_window_light_energy() * window_area_factor * lerpf(0.45, 1.0, open_amount) * smoke_transmission
			light.omni_range = window_light_range_m * lerpf(0.72, 1.08, open_amount) * lerpf(0.72, 1.0, smoke_transmission)
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
			light.light_energy = _effective_window_light_energy() * area_factor * lerpf(0.45, 1.0, open_amount) * smoke_transmission
			light.omni_range = window_light_range_m * lerpf(0.72, 1.08, open_amount) * lerpf(0.72, 1.0, smoke_transmission)
		else:
			light.light_color = _effective_landing_light_color()
			light.light_energy = _effective_landing_light_energy() * area_factor * lerpf(landing_light_closed_ratio, 1.0, open_amount) * smoke_transmission
			light.omni_range = landing_light_range_m * lerpf(0.78, 1.12, open_amount) * lerpf(0.70, 1.0, smoke_transmission)


func _update_smoke_light_attenuation() -> void:
	if _ceiling_lights_by_room.is_empty() or _state.is_empty():
		return
	for key in _ceiling_lights_by_room.keys():
		var room_id: int = int(key)
		var light := _ceiling_lights_by_room[key] as OmniLight3D
		if light == null:
			continue
		var room: RoomModel = building.get_room(room_id) if building != null else null
		var transmission: float = _light_smoke_transmission_for_room(room_id, _room_height(room))
		var base_energy: float = float(_ceiling_light_base_energy_by_room.get(room_id, room_ceiling_light_energy))
		var base_range: float = float(_ceiling_light_base_range_by_room.get(room_id, room_ceiling_light_range_extra_m))
		light.light_energy = base_energy * transmission
		light.omni_range = base_range * lerpf(0.50, 1.0, transmission)


func _light_smoke_transmission_for_room(room_id: int, height_m: float) -> float:
	var room_state: Dictionary = Dictionary(_state.get(str(room_id), {}))
	if room_state.is_empty():
		return 1.0
	var visibility_m: float = float(room_state.get("visibility_m", 30.0))
	var smoke_kg: float = float(room_state.get("smoke_kg", 0.0))
	var layer_m: float = clampf(
		float(room_state.get("smoke_display_layer_m", room_state.get("smoke_layer_m", room_state.get("h_layer_m", height_m)))),
		0.0,
		height_m
	)
	var depth_m: float = maxf(0.0, height_m - layer_m)
	var layer_block: float = clampf(depth_m / maxf(0.1, height_m), 0.0, 1.0)
	var visibility_block: float = clampf((16.0 - visibility_m) / 16.0, 0.0, 1.0)
	var rects: Dictionary = building.get_room_rects_m() if building != null else {}
	var rect := Rect2(rects.get(room_id, Rect2(Vector2.ZERO, Vector2.ONE)))
	var upper_volume_m3: float = maxf(0.05, rect.size.x * rect.size.y * maxf(depth_m, 0.05))
	var density_block: float = clampf((smoke_kg / upper_volume_m3) / 0.018, 0.0, 1.0) if smoke_kg > 0.0 and depth_m > 0.0 else 0.0
	var blocked: float = clampf(
		maxf(visibility_block * 0.82, density_block * 0.72) * lerpf(0.42, 1.0, layer_block)
			+ layer_block * 0.24,
		0.0,
		1.0
	)
	return clampf(1.0 - blocked, 0.08, 1.0)


func _light_smoke_transmission_for_opening(op: OpeningModel) -> float:
	if op == null or not op.is_exterior_opening():
		return 1.0
	var room_id: int = op.a if op.a != OUTSIDE_ID else op.b
	var room_state: Dictionary = Dictionary(_state.get(str(room_id), {}))
	if room_state.is_empty():
		return 1.0
	var room: RoomModel = building.get_room(room_id) if building != null else null
	var height_m: float = _room_height(room)
	var visibility_m: float = float(room_state.get("visibility_m", 30.0))
	var layer_m: float = clampf(
		float(room_state.get("smoke_display_layer_m", room_state.get("smoke_layer_m", room_state.get("h_layer_m", height_m)))),
		0.0,
		height_m
	)
	var visibility_block: float = clampf((12.0 - visibility_m) / 12.0, 0.0, 1.0)
	var layer_block: float = clampf((height_m - layer_m) / maxf(0.1, height_m), 0.0, 1.0)
	var blocked: float = maxf(visibility_block * 0.72, layer_block * 0.48)
	return clampf(1.0 - blocked, 0.14, 1.0)


func _door_swing_direction(op: OpeningModel) -> String:
	var direction: String = String(op.swing_direction if op != null else "in").strip_edges().to_lower()
	return "out" if direction == "out" else "in"


func _door_hinge_side(op: OpeningModel) -> String:
	var hinge: String = String(op.hinge_side if op != null else "left").strip_edges().to_lower()
	return "right" if hinge == "right" else "left"


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
		return _opening_info_on_side(rect, room_id, side, width_m, height_m, sill_m, op.offset_m, op.offset_is_fraction, true)

	var other_id: int = op.b if op.a == room_id else op.a
	if not rects.has(other_id):
		return {}
	if absf(_get_room_floor_level(room_id) - _get_room_floor_level(other_id)) > 0.20:
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
		op.offset_is_fraction,
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
	offset_is_fraction: bool,
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
	if offset_is_fraction:
		center_axis = allowed_start + allowed_length * offset
	else:
		center_axis = side_axis_start + offset
	width_m = minf(width_m, maxf(0.20, allowed_length))
	center_axis = clampf(center_axis, allowed_start + width_m * 0.5, allowed_end - width_m * 0.5)

	var x: float = center_axis if horizontal else (rect.position.x if side == "left" else rect.position.x + rect.size.x)
	var z: float = (rect.position.y if side == "top" else rect.position.y + rect.size.y) if horizontal else center_axis
	var floor_level_m: float = _get_room_floor_level(room_id)
	var center: Vector3 = _to_world(Vector3(x, sill_m + height_m * 0.5, z), floor_level_m)
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
		"exterior": exterior,
		"floor_level_m": floor_level_m
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
	if not building.player_start.is_empty():
		var start: Dictionary = building.player_start
		var room_id: int = int(start.get("room_id", -1))
		var rects: Dictionary = building.get_room_rects_m()
		if rects.has(room_id):
			var rect: Rect2 = Rect2(rects[room_id])
			var local_pos: Vector2 = Vector2(start.get("position_m", Vector2(rect.size.x * 0.5, rect.size.y * 0.5)))
			local_pos.x = clampf(local_pos.x, 0.0, rect.size.x)
			local_pos.y = clampf(local_pos.y, 0.0, rect.size.y)
			var floor_level_m: float = float(start.get("floor_level_z_m", _get_room_floor_level(room_id)))
			global_position = _to_world(Vector3(rect.position.x + local_pos.x, 0.05, rect.position.y + local_pos.y), floor_level_m)
			_yaw = deg_to_rad(float(start.get("yaw_deg", 0.0)))
			_pitch = 0.0
			rotation.y = _yaw
			if _camera != null:
				_camera.rotation.x = _pitch
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
		var floor_level_m: float = float(info.get("floor_level_m", 0.0))
		global_position = center + inward * 0.75
		global_position.y = floor_level_m + 0.05
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
		global_position = _to_world(Vector3(rect.position.x + rect.size.x * 0.5, 0.05, rect.position.y + rect.size.y * 0.5), _get_room_floor_level(first_id))
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


func _building_vertical_span() -> Dictionary:
	var min_y: float = 0.0
	var max_y: float = boundary_height_m
	if building == null:
		return {"min_y": min_y, "max_y": max_y}
	for key in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(key))
		if room == null:
			continue
		min_y = minf(min_y, room.floor_level_z_m)
		max_y = maxf(max_y, room.floor_level_z_m + room.height_m)
	return {"min_y": min_y, "max_y": max_y}


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


func _get_room_floor_level(room_id: int) -> float:
	if building == null:
		return 0.0
	var room: RoomModel = building.get_room(room_id)
	return room.floor_level_z_m if room != null else 0.0


func _room_is_stairwell(room: RoomModel) -> bool:
	if room == null:
		return false
	var label: String = ("%s %s" % [room.kind, room.name]).to_lower()
	return label.contains("escalera") or label.contains("stair")


func _room_stair_run_direction(room: RoomModel) -> Vector2:
	if room == null:
		return Vector2.DOWN
	var value: Vector2 = room.stair_run_direction_m
	if absf(value.x) > absf(value.y):
		return Vector2.RIGHT if value.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if value.y >= 0.0 else Vector2.UP


func _find_next_floor_level_above(level_m: float) -> float:
	if building == null:
		return level_m
	var best: float = INF
	for key in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(key))
		if room != null and room.floor_level_z_m > level_m + 0.20:
			best = minf(best, room.floor_level_z_m)
	return level_m if is_inf(best) else best


func _to_world(pos_m: Vector3, floor_level_m: float = 0.0) -> Vector3:
	return Vector3(pos_m.x + _origin_offset_m.x, pos_m.y + floor_level_m, pos_m.z + _origin_offset_m.y)


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
