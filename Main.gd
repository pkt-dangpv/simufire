extends Node

const FirstPersonControllerScript = preload("res://view/fp/FirstPersonController.gd")
const Minimap2DScript = preload("res://ui/Minimap2D.gd")
const MAIN_MENU_PATH: String = "res://scenes/MainMenu.tscn"

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
var _graph_textures: Array[Texture2D] = []
var _graph_image_cells: Array[Control] = []
var _graph_scrolls: Array[ScrollContainer] = []
var _graph_drag_scroll: ScrollContainer = null
var _graph_zoom: float = 1.0
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
	_connect_visualizer_signals()
	_update_views()


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
	_update_views()


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
	var state := engine.get_state()
	state["playback_paused"] = playback_paused
	state["time_scale"] = engine.time_scale
	state["simulation_finished"] = engine.is_finished
	state["graphs_launched"] = engine.are_graphs_launched()
	state["view_3d_enabled"] = view_3d_enabled
	state["first_person_enabled"] = first_person_enabled
	if first_person_controller != null:
		state["fp_player"] = first_person_controller.get_player_marker_state()
	if visualizer != null:
		visualizer.set_state(state)
	if visualizer_3d != null:
		visualizer_3d.set_state(state)
	if hud != null:
		hud.update_state(state)
	if minimap_2d != null:
		minimap_2d.set_state(state)
	if first_person_controller != null:
		first_person_controller.set_state(state)


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
		minimap_2d.visible = visualizer_3d_active


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
	_graphs_view_window.size = Vector2i(1060, 660)
	_graphs_view_window.min_size = Vector2i(800, 500)
	_graphs_view_window.wrap_controls = false
	_graphs_view_window.visible = false
	_graphs_view_window.close_requested.connect(_on_graphs_window_close_requested)
	add_child(_graphs_view_window)


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


func _show_graphs_window(graphs_dir: String) -> void:
	if _graphs_view_window == null:
		return

	# Ajustar tamaño al de la ventana principal antes de mostrar.
	var main_win: Window = get_window()
	if main_win != null:
		var ws: Vector2i = main_win.size
		_graphs_view_window.size = Vector2i(maxi(ws.x - 40, 1060), maxi(ws.y - 60, 660))

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

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		room_scroll.add_child(grid)

		for image_name in _collect_graph_images(room_path):
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(480.0 * _graph_zoom, 300.0 * _graph_zoom)
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
			tex_rect.custom_minimum_size = Vector2(470.0 * _graph_zoom, 260.0 * _graph_zoom)
			tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(tex_rect)

			var img := Image.new()
			if img.load(room_path.path_join(image_name)) == OK:
				var texture := ImageTexture.create_from_image(img)
				_graph_textures.append(texture)
				tex_rect.texture = texture

	if room_dirs.is_empty():
		var empty := Label.new()
		empty.text = "No se encontraron graficas de habitaciones en la carpeta elegida."
		tabs.add_child(empty)

	_graphs_view_window.popup_centered()


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


func _on_graph_zoom_in() -> void:
	_set_graph_zoom(_graph_zoom * 1.25)


func _on_graph_zoom_out() -> void:
	_set_graph_zoom(_graph_zoom / 1.25)


func _on_graph_zoom_reset() -> void:
	_set_graph_zoom(1.0)


func _set_graph_zoom(next_zoom: float) -> void:
	_graph_zoom = clampf(next_zoom, 0.25, 4.0)
	_apply_graph_zoom()


func _apply_graph_zoom() -> void:
	for cell in _graph_image_cells:
		if not is_instance_valid(cell):
			continue
		cell.custom_minimum_size = Vector2(480.0 * _graph_zoom, 300.0 * _graph_zoom)
		for child in cell.get_children():
			if child is TextureRect:
				child.custom_minimum_size = Vector2(470.0 * _graph_zoom, 260.0 * _graph_zoom)


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
				_set_graph_zoom(_graph_zoom * 1.12)
				scroll.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
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
