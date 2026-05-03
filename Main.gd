extends Node

@onready var building: BuildingModel = $World/BuildingModel
@onready var engine: SimulationEngine = $World/SimulationEngine
@onready var visualizer: Visualizer = $World/Visualizer
@onready var world_3d: Node3D = get_node_or_null("World3D") as Node3D
@onready var visualizer_3d: Visualizer3D = get_node_or_null("World3D/Visualizer3D") as Visualizer3D
@onready var hud: HUD = $UI/HUD

const TIME_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0]

var playback_paused: bool = false
var _graphs_dir_dialog: FileDialog = null
var _graphs_view_window: Window = null
var _graph_textures: Array[Texture2D] = []
var _graph_image_cells: Array[Control] = []
var _graph_zoom: float = 1.0
var view_3d_enabled: bool = false


func _ready() -> void:
	_setup_graph_dialogs()
	if hud != null:
		hud.bind_building(building)
		if not hud.play_requested.is_connected(_on_play_requested):
			hud.play_requested.connect(_on_play_requested)
		if not hud.pause_requested.is_connected(_on_pause_requested):
			hud.pause_requested.connect(_on_pause_requested)
		if not hud.slower_requested.is_connected(_on_slower_requested):
			hud.slower_requested.connect(_on_slower_requested)
		if not hud.faster_requested.is_connected(_on_faster_requested):
			hud.faster_requested.connect(_on_faster_requested)
		if not hud.stop_and_generate_requested.is_connected(_on_stop_and_generate_requested):
			hud.stop_and_generate_requested.connect(_on_stop_and_generate_requested)
		if not hud.view_3d_toggled.is_connected(_on_view_3d_toggled):
			hud.view_3d_toggled.connect(_on_view_3d_toggled)
	_set_3d_view_enabled(view_3d_enabled)
	_update_views()


func _physics_process(delta: float) -> void:
	if playback_paused or engine == null:
		return
	engine.step(delta)
	_update_views()


func _update_views() -> void:
	if engine == null:
		return
	var state := engine.get_state()
	state["playback_paused"] = playback_paused
	state["time_scale"] = engine.time_scale
	state["simulation_finished"] = engine.is_finished
	state["graphs_launched"] = engine.are_graphs_launched()
	state["view_3d_enabled"] = view_3d_enabled
	if visualizer != null:
		visualizer.set_state(state)
	if visualizer_3d != null:
		visualizer_3d.set_state(state)
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
	_update_views()


func _set_3d_view_enabled(enabled: bool) -> void:
	view_3d_enabled = enabled
	if visualizer != null:
		visualizer.visible = not enabled
	if world_3d != null:
		world_3d.visible = enabled
	if visualizer_3d != null:
		visualizer_3d.set_active(enabled)


func _on_stop_and_generate_requested() -> void:
	playback_paused = true
	_update_views()
	if _graphs_dir_dialog != null:
		_graphs_dir_dialog.popup_centered_ratio(0.72)


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
	_graphs_view_window.wrap_controls = true
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
		tabs.add_child(room_scroll)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		room_scroll.add_child(grid)

		for image_name in _collect_graph_images(room_path):
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(480.0 * _graph_zoom, 300.0 * _graph_zoom)
			cell.add_theme_constant_override("separation", 4)
			grid.add_child(cell)
			_graph_image_cells.append(cell)

			var title := Label.new()
			title.text = image_name.get_basename().capitalize()
			cell.add_child(title)

			var tex_rect := TextureRect.new()
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.custom_minimum_size = Vector2(470.0 * _graph_zoom, 260.0 * _graph_zoom)
			tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	for child in _graphs_view_window.get_children():
		child.queue_free()
	_graph_textures.clear()
	_graph_image_cells.clear()


func _on_graph_zoom_in() -> void:
	_graph_zoom = minf(_graph_zoom * 1.25, 4.0)
	_apply_graph_zoom()


func _on_graph_zoom_out() -> void:
	_graph_zoom = maxf(_graph_zoom / 1.25, 0.25)
	_apply_graph_zoom()


func _on_graph_zoom_reset() -> void:
	_graph_zoom = 1.0
	_apply_graph_zoom()


func _apply_graph_zoom() -> void:
	for cell in _graph_image_cells:
		if not is_instance_valid(cell):
			continue
		cell.custom_minimum_size = Vector2(480.0 * _graph_zoom, 300.0 * _graph_zoom)
		for child in cell.get_children():
			if child is TextureRect:
				child.custom_minimum_size = Vector2(470.0 * _graph_zoom, 260.0 * _graph_zoom)


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
