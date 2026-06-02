extends Node

const FirstPersonControllerScript = preload("res://view/fp/FirstPersonController.gd")
const Minimap2DScript = preload("res://ui/Minimap2D.gd")
const MAIN_MENU_PATH: String = "res://scenes/MainMenu.tscn"
const STARTUP_OPTIONS_PATH: String = "user://startup_sim_options.json"

@onready var building: BuildingModel = $World/BuildingModel
@onready var engine: SimulationEngine = $World/SimulationEngine
@onready var visualizer: Visualizer = $World/Visualizer
@onready var world_3d: Node3D = get_node_or_null("World3D") as Node3D
@onready var visualizer_3d = get_node_or_null("World3D/Visualizer3D")
@onready var hud: HUD = $UI/HUD

const TIME_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0]

var playback_paused: bool = true
var _graphs_dir_dialog: FileDialog = null
var _graphs_view_window: Window = null
var _technical_summary_window: Window = null
var _graph_textures: Array[Texture2D] = []
var _graph_image_cells: Array[Control] = []
var _graph_scrolls: Array[ScrollContainer] = []
var _graph_grids: Array[GridContainer] = []
var _graphs_room_tabs: TabContainer = null
var _graphs_room_selector: OptionButton = null
var _graphs_room_prev_button: Button = null
var _graphs_room_next_button: Button = null
var _graph_drag_scroll: ScrollContainer = null
var _graph_zoom: float = 1.0
var _view_update_accum_s: float = 0.0
var _view_3d_update_accum_s: float = 0.0
const VIEW_RUNNING_UPDATE_INTERVAL_S: float = 0.05
const VIEW_3D_RUNNING_UPDATE_INTERVAL_S: float = 0.12
var view_3d_enabled: bool = false
var first_person_enabled: bool = false
var first_person_controller = null
var minimap_2d = null


func _ready() -> void:
	_setup_graph_dialogs()
	if hud != null:
		hud.bind_building(building)
		_connect_hud_signals()
	_setup_minimap()
	_setup_first_person_controller()
	_set_3d_view_enabled(view_3d_enabled)
	if engine != null:
		engine.time_scale = 1.0
		_apply_startup_engine_options()
		# W-01: capturar pantalla 3D cuando la simulación genera el export JSON.
		_connect_once(engine.export_screenshot_requested, _on_export_screenshot_requested)
		_connect_once(engine.technical_summary_ready, _on_technical_summary_ready)
	_connect_visualizer_signals()
	_update_views()


func _apply_startup_engine_options() -> void:
	if engine == null or _is_validation_mode():
		return
	var options: Dictionary = _load_startup_options()
	if options.is_empty():
		return
	if engine.has_method("apply_runtime_options"):
		engine.apply_runtime_options(options)


func _load_startup_options() -> Dictionary:
	if not FileAccess.file_exists(STARTUP_OPTIONS_PATH):
		return {}
	var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _is_validation_mode() -> bool:
	for arg in OS.get_cmdline_user_args():
		var arg_text: String = String(arg)
		if arg_text == "--validation-case" or arg_text.begins_with("--validation-case="):
			return true
	return false


func _connect_hud_signals() -> void:
	_connect_once(hud.play_requested, _on_play_requested)
	_connect_once(hud.pause_requested, _on_pause_requested)
	_connect_once(hud.slower_requested, _on_slower_requested)
	_connect_once(hud.faster_requested, _on_faster_requested)
	_connect_once(hud.stop_and_generate_requested, _on_stop_and_generate_requested)
	_connect_once(hud.exit_without_graphs_requested, _on_exit_without_graphs_requested)
	_connect_once(hud.view_3d_toggled, _on_view_3d_toggled)
	_connect_once(hud.first_person_toggled, _on_first_person_toggled)
	_connect_once(hud.hvac_toggled, _on_hvac_toggled)
	_connect_once(hud.opening_fraction_requested, _on_opening_fraction_requested)


func _connect_visualizer_signals() -> void:
	if visualizer != null:
		_connect_once(visualizer.room_clicked, _on_room_clicked)
		_connect_once(visualizer.opening_clicked, _on_opening_clicked)
	if visualizer_3d != null:
		_connect_once(visualizer_3d.room_clicked, _on_room_clicked)
		_connect_once(visualizer_3d.opening_clicked, _on_opening_clicked)


func _connect_once(target_signal: Signal, target_callable: Callable) -> void:
	if not target_signal.is_connected(target_callable):
		target_signal.connect(target_callable)


func _physics_process(delta: float) -> void:
	if playback_paused or engine == null:
		return
	engine.step(delta)
	_update_views_for_frame(delta)


func _input(event: InputEvent) -> void:
	if _graph_drag_scroll == null or not is_instance_valid(_graph_drag_scroll):
		return
	if event is InputEventMouseMotion:
		_pan_graph_scroll(_graph_drag_scroll, (event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_stop_graph_drag()
			get_viewport().set_input_as_handled()


func _update_views() -> void:
	if engine == null:
		return
	_view_update_accum_s = 0.0
	_view_3d_update_accum_s = 0.0
	var state := _build_view_state()
	var visualizer_2d_active: bool = not view_3d_enabled and not first_person_enabled
	var visualizer_3d_active: bool = view_3d_enabled or first_person_enabled
	if visualizer != null and visualizer_2d_active:
		visualizer.set_state(state)
	if visualizer_3d != null and visualizer_3d_active:
		visualizer_3d.set_state(state)
	if minimap_2d != null and view_3d_enabled:
		minimap_2d.set_state(state)
	if first_person_controller != null and first_person_enabled:
		first_person_controller.set_state(state)
	if hud != null:
		hud.update_state(state)


func _build_view_state() -> Dictionary:
	var state := engine.get_state()
	state["playback_paused"] = playback_paused
	state["time_scale"] = engine.time_scale
	state["simulation_finished"] = engine.is_finished
	state["graphs_launched"] = engine.are_graphs_launched()
	state["view_3d_enabled"] = view_3d_enabled
	state["first_person_enabled"] = first_person_enabled
	if first_person_controller != null:
		state["fp_player"] = first_person_controller.get_player_marker_state()
	return state


func _update_views_for_frame(delta: float) -> void:
	if engine == null:
		return
	if first_person_enabled:
		_update_views()
		return

	_view_update_accum_s += delta
	_view_3d_update_accum_s += delta
	var should_update_view: bool = _view_update_accum_s >= VIEW_RUNNING_UPDATE_INTERVAL_S
	var should_update_3d: bool = view_3d_enabled and _view_3d_update_accum_s >= VIEW_3D_RUNNING_UPDATE_INTERVAL_S
	if not should_update_view and not should_update_3d:
		return

	var state: Dictionary = _build_view_state()
	if view_3d_enabled:
		if should_update_view:
			_view_update_accum_s = 0.0
			if minimap_2d != null:
				minimap_2d.set_state(state)
			if hud != null:
				hud.update_state(state)
		if should_update_3d:
			_view_3d_update_accum_s = 0.0
			if visualizer_3d != null:
				visualizer_3d.set_state(state)
		return

	if should_update_view:
		_view_update_accum_s = 0.0
		if visualizer != null:
			visualizer.set_state(state)
		if hud != null:
			hud.update_state(state)


func _on_play_requested() -> void:
	playback_paused = false
	_update_views()


func _on_pause_requested() -> void:
	playback_paused = true
	_update_views()


func _on_slower_requested() -> void:
	if engine != null:
		engine.time_scale = _pick_time_speed(engine.time_scale, -1)
	_update_views()


func _on_faster_requested() -> void:
	if engine != null:
		engine.time_scale = _pick_time_speed(engine.time_scale, 1)
	_update_views()


func _on_view_3d_toggled(enabled: bool) -> void:
	_set_3d_view_enabled(enabled)


func _on_first_person_toggled(enabled: bool) -> void:
	_set_first_person_enabled(enabled)


func _on_hvac_toggled(enabled: bool) -> void:
	if building != null:
		building.set_hvac_on(enabled)
	_update_views()


func _on_room_clicked(room_id: int) -> void:
	if hud != null:
		hud.hide_opening_action()
		hud.show_room_detail(room_id)
	if visualizer != null:
		visualizer.select_opening(-1)
	if visualizer_3d != null:
		visualizer_3d.select_opening(-1)
	_update_views()


func _on_opening_clicked(opening_index: int, screen_pos: Vector2) -> void:
	if visualizer != null:
		visualizer.select_opening(opening_index)
	if visualizer_3d != null:
		visualizer_3d.select_opening(opening_index)
	if hud != null:
		hud.show_room_detail(-1)
		hud.show_opening_action(opening_index, screen_pos)
	_update_views()


func _on_opening_fraction_requested(opening_index: int, open_fraction: float) -> void:
	if building == null:
		return
	if building.set_opening_fraction(opening_index, open_fraction):
		if visualizer != null:
			visualizer.select_opening(opening_index)
		if visualizer_3d != null:
			visualizer_3d.select_opening(opening_index)
		if hud != null:
			hud.show_opening_action(opening_index)
		_update_views()


func _set_3d_view_enabled(enabled: bool) -> void:
	view_3d_enabled = enabled
	if enabled:
		first_person_enabled = false
	_sync_view_mode()
	_update_views()


func _set_first_person_enabled(enabled: bool) -> void:
	first_person_enabled = enabled
	if enabled:
		view_3d_enabled = false
	_sync_view_mode()
	_update_views()


func _sync_view_mode() -> void:
	var visualizer_2d_active: bool = not view_3d_enabled and not first_person_enabled
	var visualizer_3d_active: bool = view_3d_enabled or first_person_enabled
	var orbit_controls_active: bool = view_3d_enabled and not first_person_enabled

	if visualizer != null:
		visualizer.visible = visualizer_2d_active
	if world_3d != null:
		world_3d.visible = visualizer_3d_active
	if visualizer_3d != null:
		visualizer_3d.set_active(visualizer_3d_active, orbit_controls_active, orbit_controls_active, first_person_enabled)
	if first_person_controller != null:
		first_person_controller.set_active(first_person_enabled)
	if minimap_2d != null:
		minimap_2d.visible = view_3d_enabled and not first_person_enabled


func _setup_minimap() -> void:
	if hud == null or minimap_2d != null:
		return
	minimap_2d = Minimap2DScript.new()
	minimap_2d.name = "Minimap2D"
	minimap_2d.set_anchors_preset(Control.PRESET_TOP_LEFT)
	minimap_2d.offset_left = 14.0
	minimap_2d.offset_top = 14.0
	minimap_2d.offset_right = 242.0
	minimap_2d.offset_bottom = 174.0
	minimap_2d.visible = false
	minimap_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap_2d)
	minimap_2d.bind_building(building)


func _setup_first_person_controller() -> void:
	if world_3d == null or first_person_controller != null:
		return
	first_person_controller = world_3d.get_node_or_null("FirstPersonController")
	if first_person_controller == null:
		first_person_controller = FirstPersonControllerScript.new()
		first_person_controller.name = "FirstPersonController"
		world_3d.add_child(first_person_controller)
	first_person_controller.setup(building)
	_connect_once(first_person_controller.exit_requested, _on_first_person_exit_requested)
	_connect_once(first_person_controller.opening_changed, _on_first_person_opening_changed)


func _on_first_person_exit_requested() -> void:
	_set_first_person_enabled(false)


func _on_first_person_opening_changed() -> void:
	_update_views()


func _on_stop_and_generate_requested() -> void:
	playback_paused = true
	_update_views()
	if _graphs_dir_dialog != null:
		_graphs_dir_dialog.popup_centered_ratio(0.72)


func _on_exit_without_graphs_requested() -> void:
	playback_paused = true
	if first_person_enabled:
		_set_first_person_enabled(false)
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _pick_time_speed(current_speed: float, direction: int) -> float:
	if direction == 0:
		return current_speed

	if direction > 0:
		for speed in TIME_SPEEDS:
			if speed > current_speed + 0.001:
				return speed
		return TIME_SPEEDS[TIME_SPEEDS.size() - 1]

	for i in range(TIME_SPEEDS.size() - 1, -1, -1):
		var speed: float = TIME_SPEEDS[i]
		if speed < current_speed - 0.001:
			return speed
	return TIME_SPEEDS[0]


func _setup_graph_dialogs() -> void:
	_graphs_dir_dialog = FileDialog.new()
	_graphs_dir_dialog.name = "GraphsDirectoryDialog"
	_graphs_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_graphs_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_graphs_dir_dialog.title = "Guardar graficas y log"
	_graphs_dir_dialog.set("use_native_dialog", true)
	_graphs_dir_dialog.dir_selected.connect(_on_graphs_dir_selected)
	add_child(_graphs_dir_dialog)

	_graphs_view_window = Window.new()
	_graphs_view_window.name = "GraphsViewer"
	_graphs_view_window.title = "Graficas de simulacion"
	_graphs_view_window.size = Vector2i(1500, 820)
	_graphs_view_window.min_size = Vector2i(1280, 680)
	_graphs_view_window.wrap_controls = false
	_graphs_view_window.visible = false
	_graphs_view_window.close_requested.connect(_on_graphs_window_close_requested)
	_graphs_view_window.size_changed.connect(_on_graphs_window_size_changed)
	add_child(_graphs_view_window)

	_technical_summary_window = Window.new()
	_technical_summary_window.name = "TechnicalSummaryWindow"
	_technical_summary_window.title = "Resumen tecnico post-simulacion"
	_technical_summary_window.size = Vector2i(1180, 760)
	_technical_summary_window.min_size = Vector2i(980, 620)
	_technical_summary_window.wrap_controls = false
	_technical_summary_window.visible = false
	_technical_summary_window.close_requested.connect(_on_technical_summary_window_close_requested)
	add_child(_technical_summary_window)


func _on_graphs_dir_selected(dir_path: String) -> void:
	if engine == null:
		return

	var launched: bool = engine.stop_and_generate_graphs("manual_stop_button", dir_path)
	_update_views()
	if not launched:
		_show_graphs_message("No se pudieron generar graficas: la simulacion no tenia datos o ya estaban lanzadas.")
		return

	var graphs_dir: String = engine.get_last_graphs_dir()
	if engine.was_last_graph_generation_ok() and graphs_dir != "":
		_show_graphs_window(graphs_dir)
	else:
		_show_graphs_message("No se pudieron generar graficas. Revisa que Python y matplotlib esten disponibles.")


## W-01: Captura la vista 3D (si está activa) en el directorio de exportación.
func _on_export_screenshot_requested(output_dir: String) -> void:
	if visualizer_3d == null:
		return
	if not view_3d_enabled and not first_person_enabled:
		return
	visualizer_3d.capture_screenshot_to(output_dir)


func _on_technical_summary_ready(summary: Dictionary, output_dir: String) -> void:
	_show_technical_summary_window(summary, output_dir)


func _on_technical_summary_window_close_requested() -> void:
	if _technical_summary_window != null:
		_technical_summary_window.hide()


func _clear_technical_summary_window() -> void:
	if _technical_summary_window == null:
		return
	for child in _technical_summary_window.get_children():
		child.queue_free()


func _show_technical_summary_window(summary: Dictionary, output_dir: String = "") -> void:
	if summary.is_empty() or _technical_summary_window == null:
		return

	_clear_technical_summary_window()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_technical_summary_window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var global_summary: Dictionary = Dictionary(summary.get("global", {}))
	var scenario_name: String = String(summary.get("scenario", ""))
	var title := Label.new()
	title.text = "Resumen tecnico | %s | t=%s" % [
		scenario_name if not scenario_name.is_empty() else "escenario",
		_format_summary_time(float(summary.get("sim_duration_s", 0.0)))
	]
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var resolved_output_dir: String = output_dir if not output_dir.strip_edges().is_empty() else String(summary.get("output_dir", ""))
	var export_label := Label.new()
	export_label.text = "Export: %s" % (resolved_output_dir if not resolved_output_dir.is_empty() else "sin directorio")
	export_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(export_label)

	var metrics := GridContainer.new()
	metrics.columns = 4
	metrics.add_theme_constant_override("h_separation", 8)
	metrics.add_theme_constant_override("v_separation", 8)
	root.add_child(metrics)
	_add_summary_metric(metrics, "HRR pico", "%.0f kW (R%d)" % [float(global_summary.get("peak_hrr_kw", 0.0)), int(global_summary.get("peak_hrr_room_id", -1))])
	_add_summary_metric(metrics, "Temp. pico", "%.0f C (R%d)" % [float(global_summary.get("peak_temp_upper_c", 0.0)), int(global_summary.get("peak_temp_room_id", -1))])
	_add_summary_metric(metrics, "CO pico", "%.0f ppm (R%d)" % [float(global_summary.get("peak_co_upper_ppm", 0.0)), int(global_summary.get("peak_co_room_id", -1))])
	_add_summary_metric(metrics, "HCN pico", "%.1f ppm (R%d)" % [float(global_summary.get("peak_hcn_upper_ppm", 0.0)), int(global_summary.get("peak_hcn_room_id", -1))])
	_add_summary_metric(metrics, "O2 minimo", "%.1f%% (R%d)" % [float(global_summary.get("min_o2_pct", 0.0)), int(global_summary.get("min_o2_room_id", -1))])
	_add_summary_metric(metrics, "Vis. minima", "%.1f m (R%d)" % [float(global_summary.get("min_visibility_m", 0.0)), int(global_summary.get("min_visibility_room_id", -1))])
	_add_summary_metric(metrics, "FED max", "%.2f (R%d)" % [float(global_summary.get("peak_fed", 0.0)), int(global_summary.get("peak_fed_room_id", -1))])
	_add_summary_metric(metrics, "Detectores", "%d/%d" % [int(global_summary.get("detectors_triggered", 0)), int(global_summary.get("detector_count", 0))])

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_summary_rooms_tab(Array(summary.get("rooms", []))))
	tabs.add_child(_build_summary_victims_tab(Array(summary.get("victims", []))))
	tabs.add_child(_build_summary_detectors_tab(Array(summary.get("detectors", []))))
	tabs.add_child(_build_summary_files_tab(resolved_output_dir))

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(button_row)
	var close_button := Button.new()
	close_button.text = "Cerrar"
	close_button.custom_minimum_size = Vector2(110.0, 34.0)
	close_button.pressed.connect(_on_technical_summary_window_close_requested)
	button_row.add_child(close_button)

	_technical_summary_window.popup_centered(_technical_summary_window.size)


func _add_summary_metric(parent: GridContainer, title_text: String, value_text: String) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210.0, 58.0)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 12)
	box.add_child(title)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 16)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(value)


func _build_summary_rooms_tab(rooms: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Salas"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	if rooms.is_empty():
		_add_summary_text_row(box, "Sin salas en el resumen.")
		return scroll
	for raw_room in rooms:
		var room: Dictionary = Dictionary(raw_room)
		var flash_text: String = "Flashover %s" % _format_summary_time(float(room.get("flashover_time_s", -1.0))) if bool(room.get("flashover_triggered", false)) else "Sin flashover"
		_add_summary_text_row(box, "R%d %s | %s | HRR %.0f kW @ %s | T %.0f C | CO %.0f ppm | HCN %.1f ppm | O2 min %.1f%% | Vis min %.1f m | FED %.2f" % [
			int(room.get("room_id", -1)),
			String(room.get("room_name", "")),
			flash_text,
			float(room.get("peak_hrr_kw", 0.0)),
			_format_summary_time(float(room.get("peak_hrr_time_s", -1.0))),
			float(room.get("peak_temp_upper_c", 0.0)),
			float(room.get("peak_co_upper_ppm", 0.0)),
			float(room.get("peak_hcn_upper_ppm", 0.0)),
			float(room.get("min_o2_pct", 0.0)),
			float(room.get("min_visibility_m", 0.0)),
			float(room.get("peak_fed", 0.0)),
		])
	return scroll


func _build_summary_victims_tab(victims: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Victimas"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	if victims.is_empty():
		_add_summary_text_row(box, "Sin victimas definidas.")
		return scroll
	for raw_victim in victims:
		var victim: Dictionary = Dictionary(raw_victim)
		var fed_time: float = float(victim.get("time_to_fed_1_s", -1.0))
		var fed_text: String = "FED=1 en %s" % _format_summary_time(fed_time) if fed_time >= 0.0 else "FED<1"
		_add_summary_text_row(box, "%s | R%d | FED final %.2f | %s" % [
			String(victim.get("victim_name", victim.get("victim_id", "?"))),
			int(victim.get("room_id", -1)),
			float(victim.get("fed_final", 0.0)),
			fed_text,
		])
	return scroll


func _build_summary_detectors_tab(detectors: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Detectores"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	if detectors.is_empty():
		_add_summary_text_row(box, "Sin detectores definidos.")
		return scroll
	for raw_detector in detectors:
		var detector: Dictionary = Dictionary(raw_detector)
		var triggered: bool = bool(detector.get("triggered", false))
		var status: String = "Activado en %s" % _format_summary_time(float(detector.get("triggered_at_s", -1.0))) if triggered else "No activado"
		_add_summary_text_row(box, "%s | %s | R%d | %s" % [
			String(detector.get("detector_id", "?")),
			String(detector.get("type", "smoke")),
			int(detector.get("room_id", -1)),
			status,
		])
	return scroll


func _build_summary_files_tab(output_dir: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "Archivos"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	if output_dir.strip_edges().is_empty():
		_add_summary_text_row(box, "Sin directorio de export.")
		return box
	_add_summary_text_row(box, output_dir.path_join("summary.json"))
	_add_summary_text_row(box, output_dir.path_join("events.json"))
	_add_summary_text_row(box, output_dir.path_join("sim_log.csv"))
	_add_summary_text_row(box, output_dir.path_join("sim_log.txt"))
	return box


func _add_summary_text_row(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)


func _format_summary_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--"
	return "%.1fs" % seconds


func _show_graphs_window(graphs_dir: String) -> void:
	if _graphs_view_window == null:
		return

	# Ajustar tamaño al de la ventana principal antes de mostrar.
	var main_win: Window = get_window()
	if main_win != null:
		var ws: Vector2i = main_win.size
		_graphs_view_window.size = Vector2i(maxi(ws.x - 40, 1280), maxi(ws.y - 60, 720))
	else:
		_graphs_view_window.size = Vector2i(1500, 820)

	_clear_graphs_view_window()
	_graph_zoom = 1.0

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	_graphs_view_window.add_child(root)

	var header := Label.new()
	header.text = "Graficas y log guardados en: %s" % graphs_dir
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(header)

	# Barra de zoom
	var zoom_bar := HBoxContainer.new()
	zoom_bar.add_theme_constant_override("separation", 6)
	root.add_child(zoom_bar)
	var lbl_zoom := Label.new()
	lbl_zoom.text = "Zoom:"
	zoom_bar.add_child(lbl_zoom)
	var btn_zoom_out := Button.new()
	btn_zoom_out.text = "  -  "
	btn_zoom_out.pressed.connect(_on_graph_zoom_out)
	zoom_bar.add_child(btn_zoom_out)
	var btn_zoom_in := Button.new()
	btn_zoom_in.text = "  +  "
	btn_zoom_in.pressed.connect(_on_graph_zoom_in)
	zoom_bar.add_child(btn_zoom_in)
	var btn_zoom_reset := Button.new()
	btn_zoom_reset.text = "100%"
	btn_zoom_reset.pressed.connect(_on_graph_zoom_reset)
	zoom_bar.add_child(btn_zoom_reset)

	var room_nav := HBoxContainer.new()
	room_nav.add_theme_constant_override("separation", 8)
	root.add_child(room_nav)
	_graphs_room_prev_button = Button.new()
	_graphs_room_prev_button.text = "<"
	_graphs_room_prev_button.tooltip_text = "Sala anterior"
	_graphs_room_prev_button.pressed.connect(_on_graph_room_prev)
	room_nav.add_child(_graphs_room_prev_button)
	_graphs_room_selector = OptionButton.new()
	_graphs_room_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graphs_room_selector.item_selected.connect(_on_graph_room_selected)
	room_nav.add_child(_graphs_room_selector)
	_graphs_room_next_button = Button.new()
	_graphs_room_next_button.text = ">"
	_graphs_room_next_button.tooltip_text = "Sala siguiente"
	_graphs_room_next_button.pressed.connect(_on_graph_room_next)
	room_nav.add_child(_graphs_room_next_button)

	var tabs := TabContainer.new()
	_graphs_room_tabs = tabs
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 18)
	tabs.add_theme_color_override("font_selected_color", Color(0.94, 0.94, 0.90, 1.0))
	tabs.add_theme_color_override("font_unselected_color", Color(0.70, 0.72, 0.72, 1.0))
	tabs.tab_changed.connect(_on_graph_room_tab_changed)
	root.add_child(tabs)

	var dir := DirAccess.open(graphs_dir)
	if dir == null:
		var err := Label.new()
		err.text = "No se pudo abrir la carpeta de graficas."
		root.add_child(err)
		_graphs_view_window.popup_centered()
		return

	var room_dirs: Array[String] = []
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir() and name.begins_with("ROOM_"):
			room_dirs.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	room_dirs.sort()
	if _graphs_room_selector != null:
		_graphs_room_selector.clear()
		for room_dir_name in room_dirs:
			_graphs_room_selector.add_item(_format_room_tab_name(room_dir_name))
	room_nav.visible = not room_dirs.is_empty()

	for room_dir_name in room_dirs:
		var room_path: String = graphs_dir.path_join(room_dir_name)
		var room_scroll := ScrollContainer.new()
		room_scroll.name = _format_room_tab_name(room_dir_name)
		room_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		room_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		room_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		room_scroll.gui_input.connect(_on_graph_scroll_gui_input.bind(room_scroll))
		tabs.add_child(room_scroll)
		_graph_scrolls.append(room_scroll)

		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_top", 18)
		margin.add_theme_constant_override("margin_right", 28)
		margin.add_theme_constant_override("margin_bottom", 28)
		room_scroll.add_child(margin)

		var grid := GridContainer.new()
		grid.columns = _graph_column_count()
		grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 18)
		margin.add_child(grid)
		_graph_grids.append(grid)

		for image_name in _collect_graph_images(room_path):
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(500.0 * _graph_zoom, 330.0 * _graph_zoom)
			cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			cell.add_theme_constant_override("separation", 4)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(cell)
			_graph_image_cells.append(cell)

			var title := Label.new()
			title.text = image_name.get_basename().capitalize()
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(title)

			var tex_rect := TextureRect.new()
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.custom_minimum_size = Vector2(480.0 * _graph_zoom, 280.0 * _graph_zoom)
			tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			tex_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(tex_rect)

			var img := Image.new()
			if img.load(room_path.path_join(image_name)) == OK:
				var texture := ImageTexture.create_from_image(img)
				_graph_textures.append(texture)
				tex_rect.texture = texture
				var image_size: Vector2i = img.get_size()
				var tex_base: Vector2 = _graph_texture_base_size(image_size)
				tex_rect.set_meta("image_size", image_size)
				tex_rect.set_meta("base_size", tex_base)
				cell.set_meta("base_size", tex_base + Vector2(24.0, 42.0))
				tex_rect.custom_minimum_size = tex_base * _graph_zoom
				cell.custom_minimum_size = Vector2(cell.get_meta("base_size")) * _graph_zoom

	if room_dirs.is_empty():
		var empty := Label.new()
		empty.text = "No se encontraron graficas de habitaciones en la carpeta elegida."
		tabs.add_child(empty)

	_refresh_graph_grid_columns()
	_sync_graph_room_nav()
	_graphs_view_window.popup_centered(_graphs_view_window.size)


func _show_graphs_message(message: String) -> void:
	if _graphs_view_window == null:
		return

	_clear_graphs_view_window()
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	_graphs_view_window.add_child(root)

	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(label)
	_graphs_view_window.popup_centered()


func _on_graphs_window_close_requested() -> void:
	if _graphs_view_window != null:
		_graphs_view_window.hide()


func _clear_graphs_view_window() -> void:
	_stop_graph_drag()
	for child in _graphs_view_window.get_children():
		child.queue_free()
	_graph_textures.clear()
	_graph_image_cells.clear()
	_graph_scrolls.clear()
	_graph_grids.clear()
	_graphs_room_tabs = null
	_graphs_room_selector = null
	_graphs_room_prev_button = null
	_graphs_room_next_button = null


func _on_graph_zoom_in() -> void:
	_set_graph_zoom(_graph_zoom * 1.25)


func _on_graph_zoom_out() -> void:
	_set_graph_zoom(_graph_zoom / 1.25)


func _on_graph_zoom_reset() -> void:
	_set_graph_zoom(1.0)


func _on_graph_room_selected(index: int) -> void:
	if _graphs_room_tabs == null or not is_instance_valid(_graphs_room_tabs):
		return
	if index < 0 or index >= _graphs_room_tabs.get_tab_count():
		return
	_graphs_room_tabs.current_tab = index
	_sync_graph_room_nav()


func _on_graph_room_prev() -> void:
	_shift_graph_room(-1)


func _on_graph_room_next() -> void:
	_shift_graph_room(1)


func _on_graph_room_tab_changed(_tab: int) -> void:
	_sync_graph_room_nav()


func _shift_graph_room(delta: int) -> void:
	if _graphs_room_tabs == null or not is_instance_valid(_graphs_room_tabs):
		return
	var count: int = _graphs_room_tabs.get_tab_count()
	if count <= 0:
		return
	_graphs_room_tabs.current_tab = posmod(_graphs_room_tabs.current_tab + delta, count)
	_sync_graph_room_nav()


func _sync_graph_room_nav() -> void:
	if _graphs_room_tabs == null or not is_instance_valid(_graphs_room_tabs):
		return
	var count: int = _graphs_room_tabs.get_tab_count()
	var current: int = clampi(_graphs_room_tabs.current_tab, 0, maxi(0, count - 1))
	if _graphs_room_selector != null and is_instance_valid(_graphs_room_selector):
		_graphs_room_selector.disabled = count <= 1
		if count > 0 and _graphs_room_selector.selected != current:
			_graphs_room_selector.select(current)
	if _graphs_room_prev_button != null and is_instance_valid(_graphs_room_prev_button):
		_graphs_room_prev_button.disabled = count <= 1
	if _graphs_room_next_button != null and is_instance_valid(_graphs_room_next_button):
		_graphs_room_next_button.disabled = count <= 1


func _set_graph_zoom(next_zoom: float) -> void:
	_graph_zoom = clampf(next_zoom, 0.25, 4.0)
	_apply_graph_zoom()


func _apply_graph_zoom() -> void:
	for cell in _graph_image_cells:
		if not is_instance_valid(cell):
			continue
		var cell_base: Vector2 = Vector2(cell.get_meta("base_size", Vector2(960.0, 560.0)))
		cell.custom_minimum_size = cell_base * _graph_zoom
		for child in cell.get_children():
			if child is TextureRect:
				if child.has_meta("image_size"):
					var image_size: Vector2i = Vector2i(child.get_meta("image_size"))
					var recalculated_base: Vector2 = _graph_texture_base_size(image_size)
					child.set_meta("base_size", recalculated_base)
					cell.set_meta("base_size", recalculated_base + Vector2(24.0, 42.0))
					cell_base = Vector2(cell.get_meta("base_size", Vector2(960.0, 560.0)))
					cell.custom_minimum_size = cell_base * _graph_zoom
				var tex_base: Vector2 = Vector2(child.get_meta("base_size", Vector2(940.0, 520.0)))
				child.custom_minimum_size = tex_base * _graph_zoom


func _graph_column_count() -> int:
	var width: int = 1500
	if _graphs_view_window != null:
		width = max(_graphs_view_window.size.x, _graphs_view_window.min_size.x)
	return 2 if width >= 1180 else 1


func _refresh_graph_grid_columns() -> void:
	var columns: int = _graph_column_count()
	for grid in _graph_grids:
		if is_instance_valid(grid):
			grid.columns = columns
	_apply_graph_zoom()


func _on_graphs_window_size_changed() -> void:
	_refresh_graph_grid_columns()


func _graph_texture_base_size(image_size: Vector2i) -> Vector2:
	var width: float = maxf(1.0, float(image_size.x))
	var height: float = maxf(1.0, float(image_size.y))
	var max_width: float = 620.0
	if _graphs_view_window != null:
		var columns: float = float(_graph_column_count())
		var fit_width: float = (float(_graphs_view_window.size.x) - 120.0) / columns - 36.0
		max_width = clampf(fit_width, 420.0, 700.0)
	var base_w: float = clampf(width, 420.0, max_width)
	var base_h: float = base_w * height / width
	return Vector2(base_w, maxf(base_h, 240.0))


func _on_graph_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and _graph_drag_scroll == scroll:
				_stop_graph_drag()
				scroll.accept_event()
			return
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				_graph_drag_scroll = scroll
				scroll.accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if mouse_event.ctrl_pressed:
					_set_graph_zoom(_graph_zoom * 1.12)
					scroll.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse_event.ctrl_pressed:
					_set_graph_zoom(_graph_zoom / 1.12)
					scroll.accept_event()
	elif event is InputEventMouseMotion and _graph_drag_scroll == scroll:
		_pan_graph_scroll(scroll, (event as InputEventMouseMotion).relative)
		scroll.accept_event()


func _pan_graph_scroll(scroll: ScrollContainer, delta: Vector2) -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	scroll.scroll_horizontal = maxi(0, int(round(float(scroll.scroll_horizontal) - delta.x)))
	scroll.scroll_vertical = maxi(0, int(round(float(scroll.scroll_vertical) - delta.y)))


func _stop_graph_drag() -> void:
	_graph_drag_scroll = null


func _collect_graph_images(room_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(room_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _format_room_tab_name(room_dir_name: String) -> String:
	var clean: String = room_dir_name.replace("ROOM_", "")
	var parts: PackedStringArray = clean.split("_", false, 1)
	if parts.size() == 2:
		return "R%s %s" % [parts[0], parts[1].replace("_", " ")]
	return clean.replace("_", " ")
