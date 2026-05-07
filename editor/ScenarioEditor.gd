extends Node2D
class_name ScenarioEditor

enum Tool {
	SELECT,
	ROOM,
	CORRIDOR_L,
	DOOR,
	WINDOW,
	OBJECT,
	IGNITION,
	DELETE
}

const PIXELS_PER_METER: float = 64.0
const GRID_M: float = 0.25
const OUTSIDE_ID: int = -1
const DEFAULT_SAVE_PATH: String = "user://editor_scenario.json"
const RUNTIME_EXPORT_PATH: String = "user://last_editor_runtime_template.json"
const SCENARIOS_RES_PATH: String = "res://scenarios"
const MAIN_SCENE_PATH: String = "res://scenes/SimulationScene.tscn"
const MAIN_MENU_PATH: String = "res://scenes/MainMenu.tscn"
const EditorGridScript = preload("res://editor/EditorGrid.gd")
const ObjectLibraryScript = preload("res://editor/ObjectLibrary.gd")
const Serializer = preload("res://editor/ScenarioSerializer.gd")

var editor_data: Dictionary = {}
var current_tool: int = Tool.SELECT

var selected_room_id: int = -1
var selected_opening_index: int = -1
var selected_object_room_id: int = -1
var selected_object_index: int = -1

var is_dragging_room: bool = false
var drag_start_m: Vector2 = Vector2.ZERO
var drag_current_m: Vector2 = Vector2.ZERO
var pending_door_room_id: int = -1
var corridor_width_m: float = 1.20

var is_dragging_object: bool = false
var drag_object_cursor_offset_m: Vector2 = Vector2.ZERO

var _ui_root: Control
var _status_label: Label
var _path_edit: LineEdit
var _object_kind_option: OptionButton
var _name_edit: LineEdit
var _kind_edit: LineEdit
var _height_spin: SpinBox
var _fuel_spin: SpinBox
var _hrr_spin: SpinBox
var _tool_buttons: Dictionary = {}
var _scenario_option: OptionButton
var _hvac_option: OptionButton
var _scenario_paths: Array[String] = []
var _stop_time_spin: SpinBox
# Propiedades de objeto seleccionado
var _obj_name_edit: LineEdit
var _obj_width_spin: SpinBox
var _obj_height_spin: SpinBox
var _obj_fuel_spin: SpinBox
var _obj_hrr_spin: SpinBox
var _obj_props_container: Control

# Propiedades de apertura seleccionada
var _opening_props_container: Control
var _opening_type_label: Label
var _opening_width_spin: SpinBox
var _opening_height_spin: SpinBox
var _opening_sill_spin: SpinBox
var _opening_open_option: OptionButton

var _room_fill: Color = Color(0.14, 0.18, 0.21, 0.62)
var _room_selected_fill: Color = Color(0.17, 0.29, 0.36, 0.70)
var _room_outline: Color = Color(0.74, 0.82, 0.88, 0.92)
var _door_color: Color = Color(0.35, 0.92, 0.58, 0.95)
var _window_color: Color = Color(0.25, 0.72, 1.0, 0.95)
var _object_color: Color = Color(0.95, 0.55, 0.22, 0.88)
var _object_selected_color: Color = Color(1.0, 0.78, 0.30, 0.96)
var _ignition_color: Color = Color(1.0, 0.18, 0.08, 0.98)


func _ready() -> void:
	_create_empty_scenario()
	_setup_grid()
	if not _bind_existing_ui():
		_setup_ui()
	_set_tool(Tool.SELECT)
	queue_redraw()


func _setup_grid() -> void:
	var grid: Node2D = get_node_or_null("EditorGrid") as Node2D
	if grid == null:
		grid = EditorGridScript.new()
		grid.name = "EditorGrid"
		add_child(grid)
		move_child(grid, 0)
	grid.set("pixels_per_meter", PIXELS_PER_METER)
	grid.set("grid_m", GRID_M)


func _create_empty_scenario() -> void:
	editor_data = {
		"version": 1,
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {},
		"rooms_data": [],
		"openings_data": []
	}


func _setup_ui() -> void:
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas == null:
		canvas = CanvasLayer.new()
		canvas.name = "CanvasLayer"
		add_child(canvas)

	_ui_root = canvas.get_node_or_null("UI") as Control
	if _ui_root == null:
		_ui_root = Control.new()
		_ui_root.name = "UI"
		canvas.add_child(_ui_root)
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_PASS

	var panel := PanelContainer.new()
	panel.name = "ToolsPanel"
	panel.position = Vector2(12.0, 12.0)
	panel.custom_minimum_size = Vector2(440.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_root.add_child(panel)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	panel.add_child(main)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	main.add_child(toolbar)
	_add_tool_button(toolbar, "Sel", Tool.SELECT)
	_add_tool_button(toolbar, "Room", Tool.ROOM)
	_add_tool_button(toolbar, "Corr L", Tool.CORRIDOR_L)
	_add_tool_button(toolbar, "Door", Tool.DOOR)
	_add_tool_button(toolbar, "Window", Tool.WINDOW)
	_add_tool_button(toolbar, "Object", Tool.OBJECT)
	_add_tool_button(toolbar, "Ignite", Tool.IGNITION)
	_add_tool_button(toolbar, "Del", Tool.DELETE)

	var object_row := HBoxContainer.new()
	main.add_child(object_row)
	var object_label := Label.new()
	object_label.text = "Object"
	object_label.custom_minimum_size.x = 72.0
	object_row.add_child(object_label)
	_object_kind_option = OptionButton.new()
	_object_kind_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kind in ObjectLibraryScript.get_object_kinds():
		_object_kind_option.add_item(kind)
	object_row.add_child(_object_kind_option)

	main.add_child(HSeparator.new())

	var properties_title := Label.new()
	properties_title.text = "Room properties"
	main.add_child(properties_title)

	_name_edit = _add_line_edit(main, "Nombre")
	_kind_edit = _add_line_edit(main, "Tipo")
	_height_spin = _add_spin(main, "Alto (m)", 1.8, 6.0, 0.1)
	_fuel_spin = _add_spin(main, "Combust. MJ", 0.0, 10000.0, 10.0)
	_hrr_spin = _add_spin(main, "HRR máx kW", 0.0, 5000.0, 10.0)

	var apply_button := Button.new()
	apply_button.text = "Aplicar habitación"
	apply_button.pressed.connect(_apply_room_properties)
	main.add_child(apply_button)

	main.add_child(HSeparator.new())

	# --- Propiedades del objeto seleccionado ---
	var obj_title := Label.new()
	obj_title.text = "Propiedades del objeto"
	main.add_child(obj_title)

	_obj_props_container = VBoxContainer.new()
	_obj_props_container.add_theme_constant_override("separation", 4)
	main.add_child(_obj_props_container)

	_obj_name_edit = _add_line_edit(_obj_props_container, "Nombre")
	_obj_width_spin = _add_spin(_obj_props_container, "Ancho (m)", 0.1, 20.0, 0.05)
	_obj_height_spin = _add_spin(_obj_props_container, "Fondo (m)", 0.1, 20.0, 0.05)
	_obj_fuel_spin = _add_spin(_obj_props_container, "Combust. MJ", 0.0, 5000.0, 10.0)
	_obj_hrr_spin = _add_spin(_obj_props_container, "HRR máx kW", 0.0, 5000.0, 10.0)

	var apply_obj_button := Button.new()
	apply_obj_button.text = "Aplicar objeto"
	apply_obj_button.pressed.connect(_apply_object_properties)
	_obj_props_container.add_child(apply_obj_button)

	var delete_obj_button := Button.new()
	delete_obj_button.text = "Borrar objeto (Del)"
	delete_obj_button.pressed.connect(_delete_selected)
	_obj_props_container.add_child(delete_obj_button)

	main.add_child(HSeparator.new())

	# --- Propiedades de apertura seleccionada ---
	var opening_title_label := Label.new()
	opening_title_label.text = "Propiedades de apertura"
	main.add_child(opening_title_label)

	_opening_props_container = VBoxContainer.new()
	_opening_props_container.add_theme_constant_override("separation", 4)
	main.add_child(_opening_props_container)

	_opening_type_label = Label.new()
	_opening_type_label.add_theme_font_size_override("font_size", 11)
	_opening_type_label.modulate = Color(0.75, 0.88, 1.0, 1.0)
	_opening_props_container.add_child(_opening_type_label)

	_opening_width_spin = _add_spin(_opening_props_container, "Ancho (m)", 0.3, 6.0, 0.05)
	_opening_height_spin = _add_spin(_opening_props_container, "Alto (m)", 0.5, 3.5, 0.05)
	_opening_sill_spin = _add_spin(_opening_props_container, "Alféizar (m)", 0.0, 2.0, 0.05)

	var op_open_row := HBoxContainer.new()
	_opening_props_container.add_child(op_open_row)
	var op_open_label := Label.new()
	op_open_label.text = "Estado inicial"
	op_open_label.custom_minimum_size.x = 96.0
	op_open_row.add_child(op_open_label)
	_opening_open_option = OptionButton.new()
	_opening_open_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opening_open_option.add_item("Cerrada", 0)
	_opening_open_option.add_item("Abierta", 1)
	op_open_row.add_child(_opening_open_option)

	var apply_opening_button := Button.new()
	apply_opening_button.text = "Aplicar apertura"
	apply_opening_button.pressed.connect(_apply_opening_properties)
	_opening_props_container.add_child(apply_opening_button)

	main.add_child(HSeparator.new())

	var path_row := HBoxContainer.new()
	main.add_child(path_row)
	_path_edit = LineEdit.new()
	_path_edit.text = DEFAULT_SAVE_PATH
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_path_edit)

	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 4)
	main.add_child(file_row)
	_add_action_button(file_row, "Guardar", _save_pressed)
	_add_action_button(file_row, "Cargar", _load_pressed)
	_add_action_button(file_row, "Export runtime", _export_runtime_pressed)

	main.add_child(HSeparator.new())

	# --- Tiempo de parada ---
	_stop_time_spin = _add_spin(main, "Parar a (s)", 0.0, 86400.0, 30.0)
	_stop_time_spin.value = 0.0
	var stop_hint := Label.new()
	stop_hint.text = "(0 = no parar nunca)"
	stop_hint.add_theme_font_size_override("font_size", 10)
	stop_hint.modulate = Color(0.7, 0.7, 0.7)
	main.add_child(stop_hint)
	_stop_time_spin.value_changed.connect(func(v: float):
		editor_data["stop_time_s"] = v)

	main.add_child(HSeparator.new())

	var hvac_row := HBoxContainer.new()
	hvac_row.add_theme_constant_override("separation", 4)
	main.add_child(hvac_row)
	var hvac_label := Label.new()
	hvac_label.text = "HVAC"
	hvac_label.custom_minimum_size.x = 86.0
	hvac_row.add_child(hvac_label)
	_hvac_option = OptionButton.new()
	_hvac_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hvac_row.add_child(_hvac_option)
	_populate_hvac_option()
	if not _hvac_option.item_selected.is_connected(_on_hvac_option_selected):
		_hvac_option.item_selected.connect(_on_hvac_option_selected)

	main.add_child(HSeparator.new())

	# ---- Panel de escenarios predefinidos ----
	var scenarios_title := Label.new()
	scenarios_title.text = "Scenarios"
	main.add_child(scenarios_title)

	var scenarios_row := HBoxContainer.new()
	scenarios_row.add_theme_constant_override("separation", 4)
	main.add_child(scenarios_row)
	_scenario_option = OptionButton.new()
	_scenario_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenarios_row.add_child(_scenario_option)
	_add_action_button(scenarios_row, "Load", _load_scenario_pressed)

	main.add_child(HSeparator.new())

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	main.add_child(action_row)
	var run_button := Button.new()
	run_button.text = "✓ Iniciar simulación"
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_button.custom_minimum_size = Vector2(0.0, 36.0)
	run_button.pressed.connect(_run_simulation_pressed)
	action_row.add_child(run_button)
	var cancel_button := Button.new()
	cancel_button.text = "✗ Cancelar"
	cancel_button.custom_minimum_size = Vector2(100.0, 36.0)
	cancel_button.pressed.connect(_cancel_pressed)
	action_row.add_child(cancel_button)

	_scan_scenario_files()

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(410.0, 0.0)
	main.add_child(_status_label)

	_refresh_property_panel()
	_set_status("Listo. Dibuja habitaciones arrastrando con Room. Selecciona objetos con Sel y borra con Del.")


func _add_tool_button(parent: Control, label: String, tool_id: int) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(50.0, 28.0)
	button.pressed.connect(Callable(self, "_set_tool").bind(tool_id))
	parent.add_child(button)
	_tool_buttons[tool_id] = button


func _add_action_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_line_edit(parent: Control, label: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var row_label := Label.new()
	row_label.text = label
	row_label.custom_minimum_size.x = 96.0
	row.add_child(row_label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _add_spin(parent: Control, label: String, min_value: float, max_value: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var row_label := Label.new()
	row_label.text = label
	row_label.custom_minimum_size.x = 96.0
	row.add_child(row_label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _set_tool(tool_id: int) -> void:
	current_tool = tool_id
	pending_door_room_id = -1
	for key in _tool_buttons.keys():
		var button: Button = _tool_buttons[key]
		button.button_pressed = int(key) == current_tool
	_clear_drag()
	_set_status(_tool_hint(current_tool))


func _tool_hint(tool_id: int) -> String:
	match tool_id:
		Tool.SELECT:
			return "Select: selecciona habitaciones, objetos o aperturas."
		Tool.ROOM:
			return "Room: arrastra para crear una estancia."
		Tool.CORRIDOR_L:
			return "Corr L: arrastra una diagonal para crear un pasillo con giro de 90 grados."
		Tool.DOOR:
			return "Door: pulsa una pared compartida o una pared exterior para crear puerta."
		Tool.WINDOW:
			return "Window: pulsa cerca de una pared exterior."
		Tool.OBJECT:
			return "Object: pulsa dentro de una estancia para colocar el combustible elegido."
		Tool.IGNITION:
			return "Ignite: pulsa un objeto para marcarlo como foco inicial."
		Tool.DELETE:
			return "Delete: elimina objeto, apertura o estancia bajo el cursor."
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selected()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if is_dragging_room:
			drag_current_m = _screen_to_m(event.position)
			queue_redraw()
		elif is_dragging_object:
			_update_dragged_object(_screen_to_m(event.position))
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _is_pointer_over_ui():
		return

	var pos_m: Vector2 = _screen_to_m(mouse_event.position)
	if mouse_event.pressed:
		_handle_press(pos_m)
	else:
		_handle_release(pos_m)


func _handle_press(pos_m: Vector2) -> void:
	match current_tool:
		Tool.ROOM, Tool.CORRIDOR_L:
			is_dragging_room = true
			drag_start_m = pos_m
			drag_current_m = pos_m
		Tool.SELECT:
			# Si el objeto ya está seleccionado, iniciar arrastre
			if selected_object_room_id >= 0 and selected_object_index >= 0:
				var hit: Dictionary = _find_object_at(pos_m)
				if not hit.is_empty() and int(hit["room_id"]) == selected_object_room_id and int(hit["object_index"]) == selected_object_index:
					var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
					var rr: Rect2 = _get_room_rect(selected_object_room_id)
					var obj_pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
					drag_object_cursor_offset_m = (rr.position + obj_pos) - pos_m
					is_dragging_object = true
					return
			_select_at(pos_m)
		Tool.DOOR:
			_create_door_at(pos_m)
		Tool.WINDOW:
			_create_window_at(pos_m)
		Tool.OBJECT:
			_create_object_at(pos_m)
		Tool.IGNITION:
			_mark_ignition_at(pos_m)
		Tool.DELETE:
			_delete_at(pos_m)


func _handle_release(pos_m: Vector2) -> void:
	if is_dragging_object:
		is_dragging_object = false
		drag_object_cursor_offset_m = Vector2.ZERO
		_set_status("Objeto movido.")
		queue_redraw()
		return

	if (current_tool != Tool.ROOM and current_tool != Tool.CORRIDOR_L) or not is_dragging_room:
		return

	drag_current_m = pos_m
	var start_m: Vector2 = drag_start_m
	var end_m: Vector2 = drag_current_m
	var rect: Rect2 = _normalized_rect(start_m, end_m)
	_clear_drag()

	if rect.size.x < GRID_M or rect.size.y < GRID_M:
		_set_status("La habitacion es demasiado pequena.")
		queue_redraw()
		return

	if current_tool == Tool.CORRIDOR_L:
		_create_l_corridor(start_m, end_m)
	else:
		var room_id: int = _create_room(rect)
		_select_room(room_id)
		_set_status("Habitacion %d creada." % room_id)
	queue_redraw()


func _is_pointer_over_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	return hovered != null and _ui_root != null and _ui_root.is_ancestor_of(hovered)


func _screen_to_m(screen_pos: Vector2) -> Vector2:
	var local_px: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_pos
	return _snap_m(local_px / PIXELS_PER_METER)


func _m_to_px(pos_m: Vector2) -> Vector2:
	return pos_m * PIXELS_PER_METER


func _rect_to_px(rect_m: Rect2) -> Rect2:
	return Rect2(_m_to_px(rect_m.position), rect_m.size * PIXELS_PER_METER)


func _snap_m(pos_m: Vector2) -> Vector2:
	return Vector2(snappedf(pos_m.x, GRID_M), snappedf(pos_m.y, GRID_M))


func _normalized_rect(a: Vector2, b: Vector2) -> Rect2:
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size := Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(pos, size)


func _clear_drag() -> void:
	is_dragging_room = false
	drag_start_m = Vector2.ZERO
	drag_current_m = Vector2.ZERO


func _update_dragged_object(pos_m: Vector2) -> void:
	if selected_object_room_id < 0 or selected_object_index < 0:
		is_dragging_object = false
		return
	var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
	if obj.is_empty():
		is_dragging_object = false
		return
	var rr: Rect2 = _get_room_rect(selected_object_room_id)
	var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
	var new_world_m: Vector2 = _snap_m(pos_m + drag_object_cursor_offset_m)
	var new_local_m: Vector2 = new_world_m - rr.position
	new_local_m.x = clampf(new_local_m.x, 0.0, maxf(0.0, rr.size.x - size.x))
	new_local_m.y = clampf(new_local_m.y, 0.0, maxf(0.0, rr.size.y - size.y))
	_set_object_position(selected_object_room_id, selected_object_index, new_local_m)
	queue_redraw()


func _set_object_position(room_id: int, obj_index: int, local_pos: Vector2) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		if obj_index >= 0 and obj_index < objects.size() and typeof(objects[obj_index]) == TYPE_DICTIONARY:
			var obj: Dictionary = objects[obj_index]
			obj["position_m"] = Serializer.vector_to_data(local_pos)
			objects[obj_index] = obj
			room["fuel_objects"] = objects
			rooms[i] = room
			editor_data["rooms_data"] = rooms
		return


func _create_room(rect: Rect2, room_name: String = "", kind_name: String = "generic") -> int:
	var id: int = _next_room_id()
	var rooms: Array = editor_data.get("rooms_data", [])
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	var room := {
		"id": id,
		"name": room_name if room_name != "" else "Room %d" % id,
		"kind": kind_name,
		"height_m": 2.7,
		"fuel_energy_MJ": 0.0,
		"max_hrr_kw": 0.0,
		"fuel_objects": []
	}
	rooms.append(room)
	rects[str(id)] = Serializer.rect_to_data(rect)
	editor_data["rooms_data"] = rooms
	editor_data["room_rect_m"] = rects
	return id


func _create_l_corridor(start_m: Vector2, end_m: Vector2) -> void:
	var dx: float = end_m.x - start_m.x
	var dy: float = end_m.y - start_m.y
	var width_m: float = corridor_width_m
	if absf(dx) < width_m * 1.5 or absf(dy) < width_m * 1.5:
		_set_status("El pasillo en L necesita ancho y largo suficientes en ambos brazos.")
		return

	var sx: float = 1.0 if dx >= 0.0 else -1.0
	var sy: float = 1.0 if dy >= 0.0 else -1.0
	var corner_x: float = end_m.x
	var h_a: Vector2 = start_m
	var h_b: Vector2 = Vector2(corner_x, start_m.y + sy * width_m)
	var v_a: Vector2 = Vector2(corner_x - sx * width_m, start_m.y + sy * width_m)
	var v_b: Vector2 = end_m

	var horizontal_rect: Rect2 = _normalized_rect(h_a, h_b)
	var vertical_rect: Rect2 = _normalized_rect(v_a, v_b)
	if horizontal_rect.size.x < width_m or horizontal_rect.size.y < GRID_M \
			or vertical_rect.size.x < GRID_M or vertical_rect.size.y < width_m:
		_set_status("El giro del pasillo queda demasiado pequeno.")
		return

	var base_name: String = "Pasillo %d" % _next_room_id()
	var first_id: int = _create_room(horizontal_rect, "%s A" % base_name, "corridor")
	var second_id: int = _create_room(vertical_rect, "%s B" % base_name, "corridor")
	var shared: Dictionary = _shared_wall_between(first_id, second_id)
	if not shared.is_empty():
		_add_opening(
			first_id,
			second_id,
			"door",
			String(shared["wall"]),
			float(shared["offset_m"]),
			minf(width_m, 1.20),
			2.05,
			0.0,
			1.0
		)
	_select_room(first_id)
	_set_status("Pasillo en L creado como habitaciones %d y %d conectadas." % [first_id, second_id])


func _next_room_id() -> int:
	var next_id: int = 0
	for room in editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY:
			next_id = maxi(next_id, int(room.get("id", -1)) + 1)
	return next_id


func _next_object_id() -> String:
	var count: int = 0
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		count += Array(room.get("fuel_objects", [])).size()
	return "obj_%03d" % (count + 1)


func _select_at(pos_m: Vector2) -> void:
	var hit_obj: Dictionary = _find_object_at(pos_m)
	if not hit_obj.is_empty():
		_select_object(int(hit_obj["room_id"]), int(hit_obj["object_index"]))
		return

	var opening_index: int = _find_opening_at(pos_m)
	if opening_index >= 0:
		_select_opening(opening_index)
		return

	var room_id: int = _find_room_at(pos_m)
	if room_id >= 0:
		_select_room(room_id)
	else:
		_clear_selection()
		_set_status("Sin seleccion.")
	queue_redraw()


func _select_room(room_id: int) -> void:
	selected_room_id = room_id
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	_refresh_property_panel()
	_set_status("Seleccionada habitacion %d." % room_id)
	queue_redraw()


func _select_opening(index: int) -> void:
	selected_room_id = -1
	selected_opening_index = index
	selected_object_room_id = -1
	selected_object_index = -1
	_refresh_property_panel()
	var opening: Dictionary = Array(editor_data.get("openings_data", []))[index]
	_set_status("Seleccionada apertura %d (%s)." % [index, String(opening.get("type", "door"))])
	queue_redraw()


func _select_object(room_id: int, object_index: int) -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = room_id
	selected_object_index = object_index
	_refresh_property_panel()
	var obj: Dictionary = _get_object(room_id, object_index)
	_set_status("Seleccionado objeto %s." % String(obj.get("name", obj.get("id", ""))))
	queue_redraw()


func _clear_selection() -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	_refresh_property_panel()


func _refresh_property_panel() -> void:
	if _name_edit == null:
		return

	var has_obj: bool = selected_object_room_id >= 0 and selected_object_index >= 0
	var room: Dictionary = _get_room(selected_room_id)
	var has_room: bool = not room.is_empty()

	# Panel habitación
	_name_edit.editable = has_room
	_kind_edit.editable = has_room
	_height_spin.editable = has_room
	_fuel_spin.editable = has_room
	_hrr_spin.editable = has_room

	if has_room:
		_name_edit.text = String(room.get("name", ""))
		_kind_edit.text = String(room.get("kind", "generic"))
		_height_spin.value = float(room.get("height_m", 2.7))
		_fuel_spin.value = float(room.get("fuel_energy_MJ", 0.0))
		_hrr_spin.value = float(room.get("max_hrr_kw", 0.0))
	else:
		_name_edit.text = ""
		_kind_edit.text = ""
		_height_spin.value = 2.7
		_fuel_spin.value = 0.0
		_hrr_spin.value = 0.0

	# Panel objeto
	if _obj_props_container != null:
		_obj_props_container.visible = has_obj

	if has_obj:
		var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
		if not obj.is_empty():
			_obj_name_edit.text = String(obj.get("name", obj.get("kind", "")))
			var sz: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
			_obj_width_spin.value = sz.x
			_obj_height_spin.value = sz.y
			_obj_fuel_spin.value = float(obj.get("fuel_energy_MJ", 0.0))
			_obj_hrr_spin.value = float(obj.get("max_hrr_kw", 0.0))

	# Panel apertura
	var openings_arr: Array = editor_data.get("openings_data", [])
	var has_opening_sel: bool = selected_opening_index >= 0 and selected_opening_index < openings_arr.size()
	if _opening_props_container != null:
		_opening_props_container.visible = has_opening_sel
	if has_opening_sel and _opening_width_spin != null:
		var opening: Dictionary = openings_arr[selected_opening_index]
		var op_type: String = String(opening.get("type", "door"))
		if _opening_type_label != null:
			var exterior_suffix: String = " exterior" if int(opening.get("b", OUTSIDE_ID)) == OUTSIDE_ID else ""
			_opening_type_label.text = ("Puerta" if op_type == "door" else "Ventana") + exterior_suffix
		_opening_width_spin.value = float(opening.get("width_m", 0.9))
		_opening_height_spin.value = float(opening.get("height_m", 2.0))
		if _opening_sill_spin != null:
			_opening_sill_spin.editable = op_type == "window"
			_opening_sill_spin.value = float(opening.get("sill_m", 0.0))
		if _opening_open_option != null:
			var frac: float = float(opening.get("open_fraction", 1.0))
			_opening_open_option.select(0 if frac <= 0.01 else 1)


func _apply_room_properties() -> void:
	if selected_room_id < 0:
		_set_status("Selecciona una habitacion antes de aplicar propiedades.")
		return

	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		if int(rooms[i].get("id", -1)) != selected_room_id:
			continue
		var room: Dictionary = rooms[i]
		room["name"] = _name_edit.text.strip_edges()
		room["kind"] = _kind_edit.text.strip_edges()
		room["height_m"] = _height_spin.value
		room["fuel_energy_MJ"] = _fuel_spin.value
		room["max_hrr_kw"] = _hrr_spin.value
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		_set_status("Propiedades de habitacion %d actualizadas." % selected_room_id)
		queue_redraw()
		return


func _get_room(room_id: int) -> Dictionary:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and int(room.get("id", -1)) == room_id:
			return room
	return {}


func _get_room_rect(room_id: int) -> Rect2:
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	return Serializer.rect2_from_data(rects.get(str(room_id), Rect2()))


func _get_object(room_id: int, object_index: int) -> Dictionary:
	var room: Dictionary = _get_room(room_id)
	var objects: Array = room.get("fuel_objects", [])
	if object_index < 0 or object_index >= objects.size():
		return {}
	if typeof(objects[object_index]) != TYPE_DICTIONARY:
		return {}
	return objects[object_index]


func _find_room_at(pos_m: Vector2) -> int:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(room.get("id", -1))
		if _get_room_rect(room_id).has_point(pos_m):
			return room_id
	return -1


func _find_object_at(pos_m: Vector2) -> Dictionary:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(room.get("id", -1))
		var room_rect: Rect2 = _get_room_rect(room_id)
		var objects: Array = room.get("fuel_objects", [])
		for object_index in range(objects.size()):
			if typeof(objects[object_index]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[object_index]
			var pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
			var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
			var obj_rect := Rect2(room_rect.position + pos, size)
			if obj_rect.has_point(pos_m):
				return {"room_id": room_id, "object_index": object_index}
	return {}


func _find_opening_at(pos_m: Vector2) -> int:
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var segment: PackedVector2Array = _opening_segment_m(openings[i])
		if segment.size() != 2:
			continue
		if _distance_to_segment(pos_m, segment[0], segment[1]) <= 0.18:
			return i
	return -1


func _create_object_at(pos_m: Vector2) -> void:
	var room_id: int = _find_room_at(pos_m)
	if room_id < 0:
		_set_status("Pulsa dentro de una habitacion para colocar un objeto.")
		return

	var selected: int = _object_kind_option.selected
	var kind: String = _object_kind_option.get_item_text(selected) if selected >= 0 else "sofa"
	var room_rect: Rect2 = _get_room_rect(room_id)
	var obj: Dictionary = ObjectLibraryScript.create_object(kind, _next_object_id(), room_id, Vector2.ZERO)
	var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
	var local_pos: Vector2 = pos_m - room_rect.position - size * 0.5
	local_pos.x = clampf(local_pos.x, 0.0, maxf(0.0, room_rect.size.x - size.x))
	local_pos.y = clampf(local_pos.y, 0.0, maxf(0.0, room_rect.size.y - size.y))
	obj["position_m"] = Serializer.vector_to_data(local_pos)
	_add_object_to_room(room_id, obj)
	_select_object(room_id, Array(_get_room(room_id).get("fuel_objects", [])).size() - 1)
	_set_status("Objeto %s colocado en habitacion %d." % [kind, room_id])
	queue_redraw()


func _add_object_to_room(room_id: int, obj: Dictionary) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		if int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		objects.append(obj)
		room["fuel_objects"] = objects
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		return


func _mark_ignition_at(pos_m: Vector2) -> void:
	var hit: Dictionary = _find_object_at(pos_m)
	if hit.is_empty():
		_set_status("Pulsa sobre un objeto combustible para marcar el foco inicial.")
		return

	var target_room_id: int = int(hit["room_id"])
	var target_index: int = int(hit["object_index"])
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		for j in range(objects.size()):
			if typeof(objects[j]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[j]
			obj["is_primary_ignition_source"] = int(room.get("id", -1)) == target_room_id and j == target_index
			objects[j] = obj
		room["fuel_objects"] = objects
		rooms[i] = room
	editor_data["rooms_data"] = rooms
	_select_object(target_room_id, target_index)
	_set_status("Foco inicial marcado.")
	queue_redraw()


func _create_door_at(pos_m: Vector2) -> void:
	var shared: Dictionary = _find_shared_wall_at(pos_m)
	if not shared.is_empty():
		_add_opening(int(shared["a"]), int(shared["b"]), "door", String(shared["wall"]), float(shared["offset_m"]), 0.9, 2.05, 0.0, 1.0)
		_set_status("Puerta creada entre habitaciones %d y %d." % [int(shared["a"]), int(shared["b"])])
		queue_redraw()
		return

	var exterior_wall: Dictionary = _find_wall_at(pos_m)
	var door_width_m: float = 0.95
	if not exterior_wall.is_empty() and _is_wall_exterior(
		int(exterior_wall["room_id"]),
		String(exterior_wall["wall"]),
		float(exterior_wall["offset_m"]),
		door_width_m
	):
		_add_opening(
			int(exterior_wall["room_id"]),
			OUTSIDE_ID,
			"door",
			String(exterior_wall["wall"]),
			float(exterior_wall["offset_m"]),
			door_width_m,
			2.05,
			0.0,
			1.0
		)
		_set_status("Puerta exterior creada en habitacion %d." % int(exterior_wall["room_id"]))
		queue_redraw()
		return

	var room_id: int = _find_room_at(pos_m)
	if room_id < 0:
		_set_status("Pulsa una pared compartida, una pared exterior o una habitacion.")
		return

	if pending_door_room_id < 0:
		pending_door_room_id = room_id
		_set_status("Primera habitacion %d seleccionada para puerta." % room_id)
		return

	if pending_door_room_id == room_id:
		_set_status("Selecciona una segunda habitacion adyacente.")
		return

	var connection: Dictionary = _shared_wall_between(pending_door_room_id, room_id)
	if connection.is_empty():
		_set_status("Las habitaciones %d y %d no comparten pared." % [pending_door_room_id, room_id])
		pending_door_room_id = -1
		return

	_add_opening(
		pending_door_room_id,
		room_id,
		"door",
		String(connection["wall"]),
		float(connection["offset_m"]),
		0.9,
		2.05,
		0.0,
		1.0
	)
	_set_status("Puerta creada entre habitaciones %d y %d." % [pending_door_room_id, room_id])
	pending_door_room_id = -1
	queue_redraw()


func _create_window_at(pos_m: Vector2) -> void:
	var wall: Dictionary = _find_wall_at(pos_m)
	if wall.is_empty():
		_set_status("Pulsa cerca de una pared para crear una ventana.")
		return

	var window_width_m: float = 1.2
	if not _is_wall_exterior(int(wall["room_id"]), String(wall["wall"]), float(wall["offset_m"]), window_width_m):
		_set_status("Pulsa un tramo de pared exterior para crear una ventana.")
		return

	_add_opening(int(wall["room_id"]), OUTSIDE_ID, "window", String(wall["wall"]), float(wall["offset_m"]), window_width_m, 1.1, 0.9, 1.0)
	_set_status("Ventana exterior creada en habitacion %d." % int(wall["room_id"]))
	queue_redraw()


func _add_opening(a: int, b: int, type_str: String, wall: String, offset_m: float, width_m: float, height_m: float, sill_m: float, open_fraction: float) -> void:
	var openings: Array = editor_data.get("openings_data", [])
	openings.append({
		"a": a,
		"b": b,
		"type": type_str,
		"wall": wall,
		"offset_m": offset_m,
		"width_m": width_m,
		"height_m": height_m,
		"sill_m": sill_m,
		"open_fraction": open_fraction
	})
	editor_data["openings_data"] = openings
	selected_opening_index = openings.size() - 1
	selected_room_id = -1
	selected_object_room_id = -1
	selected_object_index = -1


func _delete_at(pos_m: Vector2) -> void:
	var hit_obj: Dictionary = _find_object_at(pos_m)
	if not hit_obj.is_empty():
		_delete_object(int(hit_obj["room_id"]), int(hit_obj["object_index"]))
		return

	var opening_index: int = _find_opening_at(pos_m)
	if opening_index >= 0:
		var openings: Array = editor_data.get("openings_data", [])
		openings.remove_at(opening_index)
		editor_data["openings_data"] = openings
		_clear_selection()
		_set_status("Apertura eliminada.")
		queue_redraw()
		return

	var room_id: int = _find_room_at(pos_m)
	if room_id >= 0:
		_delete_room(room_id)
		return

	_set_status("No hay nada que eliminar bajo el cursor.")


func _delete_object(room_id: int, object_index: int) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		if int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		if object_index >= 0 and object_index < objects.size():
			objects.remove_at(object_index)
			room["fuel_objects"] = objects
			rooms[i] = room
			editor_data["rooms_data"] = rooms
			_clear_selection()
			_set_status("Objeto eliminado.")
			queue_redraw()
		return


func _delete_room(room_id: int) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size() - 1, -1, -1):
		if typeof(rooms[i]) == TYPE_DICTIONARY and int(rooms[i].get("id", -1)) == room_id:
			rooms.remove_at(i)
	editor_data["rooms_data"] = rooms

	var rects: Dictionary = editor_data.get("room_rect_m", {})
	rects.erase(str(room_id))
	editor_data["room_rect_m"] = rects

	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size() - 1, -1, -1):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var opening: Dictionary = openings[i]
		if int(opening.get("a", -999)) == room_id or int(opening.get("b", -999)) == room_id:
			openings.remove_at(i)
	editor_data["openings_data"] = openings

	_clear_selection()
	_set_status("Habitacion %d eliminada." % room_id)
	queue_redraw()


func _find_wall_at(pos_m: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = 0.22
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(room.get("id", -1))
		var rect: Rect2 = _get_room_rect(room_id)
		for wall in ["top", "bottom", "left", "right"]:
			var segment: PackedVector2Array = _wall_segment(rect, wall, _wall_length(rect, wall) * 0.5, _wall_length(rect, wall))
			var dist: float = _distance_to_segment(pos_m, segment[0], segment[1])
			if dist < best_distance:
				best_distance = dist
				var offset: float = _offset_on_wall(rect, wall, pos_m)
				best = {"room_id": room_id, "wall": wall, "offset_m": offset}
	return best


func _find_shared_wall_at(pos_m: Vector2) -> Dictionary:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var a_id: int = int(rooms[i].get("id", -1))
		for j in range(i + 1, rooms.size()):
			if typeof(rooms[j]) != TYPE_DICTIONARY:
				continue
			var b_id: int = int(rooms[j].get("id", -1))
			var shared: Dictionary = _shared_wall_between(a_id, b_id, pos_m)
			if not shared.is_empty():
				return shared
	return {}


func _is_wall_exterior(room_id: int, wall: String, offset_m: float, width_m: float) -> bool:
	var rect: Rect2 = _get_room_rect(room_id)
	var wall_seg: PackedVector2Array = _wall_segment(rect, wall, offset_m, width_m)
	if wall_seg.size() != 2:
		return false

	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var other_id: int = int(room.get("id", -1))
		if other_id == room_id:
			continue
		var shared: Dictionary = _shared_wall_between(room_id, other_id)
		if shared.is_empty() or String(shared.get("wall", "")) != wall:
			continue
		var other_seg: PackedVector2Array = _shared_wall_segment(room_id, other_id, wall)
		if other_seg.size() == 2 and _segments_overlap_m(wall_seg[0], wall_seg[1], other_seg[0], other_seg[1]):
			return false
	return true


func _shared_wall_segment(room_id: int, other_id: int, wall: String) -> PackedVector2Array:
	var rect: Rect2 = _get_room_rect(room_id)
	var other_rect: Rect2 = _get_room_rect(other_id)
	match wall:
		"left", "right":
			var start_y: float = maxf(rect.position.y, other_rect.position.y)
			var end_y: float = minf(rect.position.y + rect.size.y, other_rect.position.y + other_rect.size.y)
			if end_y - start_y <= 0.05:
				return PackedVector2Array()
			var edge_x: float = rect.position.x if wall == "left" else rect.position.x + rect.size.x
			return PackedVector2Array([Vector2(edge_x, start_y), Vector2(edge_x, end_y)])
		"top", "bottom":
			var start_x: float = maxf(rect.position.x, other_rect.position.x)
			var end_x: float = minf(rect.position.x + rect.size.x, other_rect.position.x + other_rect.size.x)
			if end_x - start_x <= 0.05:
				return PackedVector2Array()
			var edge_y: float = rect.position.y if wall == "top" else rect.position.y + rect.size.y
			return PackedVector2Array([Vector2(start_x, edge_y), Vector2(end_x, edge_y)])
	return PackedVector2Array()


func _segments_overlap_m(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	if a1.distance_to(a2) <= 0.0001 or b1.distance_to(b2) <= 0.0001:
		return false
	var horizontal: bool = absf(a1.y - a2.y) <= 0.001
	if horizontal:
		if absf(a1.y - b1.y) > 0.05:
			return false
		var a_min: float = minf(a1.x, a2.x)
		var a_max: float = maxf(a1.x, a2.x)
		var b_min: float = minf(b1.x, b2.x)
		var b_max: float = maxf(b1.x, b2.x)
		return minf(a_max, b_max) - maxf(a_min, b_min) > 0.05
	if absf(a1.x - b1.x) > 0.05:
		return false
	var ay_min: float = minf(a1.y, a2.y)
	var ay_max: float = maxf(a1.y, a2.y)
	var by_min: float = minf(b1.y, b2.y)
	var by_max: float = maxf(b1.y, b2.y)
	return minf(ay_max, by_max) - maxf(ay_min, by_min) > 0.05


func _shared_wall_between(a_id: int, b_id: int, click_m: Vector2 = Vector2(1.0e20, 1.0e20)) -> Dictionary:
	var a_rect: Rect2 = _get_room_rect(a_id)
	var b_rect: Rect2 = _get_room_rect(b_id)
	var tol: float = 0.05
	var click_filter: bool = click_m.x < 1.0e19 and click_m.y < 1.0e19

	if absf(a_rect.position.x + a_rect.size.x - b_rect.position.x) <= tol:
		return _vertical_shared_wall(a_id, b_id, a_rect, b_rect, "right", click_m, click_filter)
	if absf(b_rect.position.x + b_rect.size.x - a_rect.position.x) <= tol:
		return _vertical_shared_wall(a_id, b_id, a_rect, b_rect, "left", click_m, click_filter)
	if absf(a_rect.position.y + a_rect.size.y - b_rect.position.y) <= tol:
		return _horizontal_shared_wall(a_id, b_id, a_rect, b_rect, "bottom", click_m, click_filter)
	if absf(b_rect.position.y + b_rect.size.y - a_rect.position.y) <= tol:
		return _horizontal_shared_wall(a_id, b_id, a_rect, b_rect, "top", click_m, click_filter)
	return {}


func _vertical_shared_wall(a_id: int, b_id: int, a_rect: Rect2, b_rect: Rect2, wall: String, click_m: Vector2, click_filter: bool) -> Dictionary:
	var start_y: float = maxf(a_rect.position.y, b_rect.position.y)
	var end_y: float = minf(a_rect.position.y + a_rect.size.y, b_rect.position.y + b_rect.size.y)
	if end_y - start_y <= 0.2:
		return {}
	var edge_x: float = a_rect.position.x + a_rect.size.x if wall == "right" else a_rect.position.x
	if click_filter:
		if absf(click_m.x - edge_x) > 0.22 or click_m.y < start_y or click_m.y > end_y:
			return {}
	var center_y: float = clampf(click_m.y if click_filter else (start_y + end_y) * 0.5, start_y, end_y)
	return {
		"a": a_id,
		"b": b_id,
		"wall": wall,
		"offset_m": center_y - a_rect.position.y
	}


func _horizontal_shared_wall(a_id: int, b_id: int, a_rect: Rect2, b_rect: Rect2, wall: String, click_m: Vector2, click_filter: bool) -> Dictionary:
	var start_x: float = maxf(a_rect.position.x, b_rect.position.x)
	var end_x: float = minf(a_rect.position.x + a_rect.size.x, b_rect.position.x + b_rect.size.x)
	if end_x - start_x <= 0.2:
		return {}
	var edge_y: float = a_rect.position.y + a_rect.size.y if wall == "bottom" else a_rect.position.y
	if click_filter:
		if absf(click_m.y - edge_y) > 0.22 or click_m.x < start_x or click_m.x > end_x:
			return {}
	var center_x: float = clampf(click_m.x if click_filter else (start_x + end_x) * 0.5, start_x, end_x)
	return {
		"a": a_id,
		"b": b_id,
		"wall": wall,
		"offset_m": center_x - a_rect.position.x
	}


func _offset_on_wall(rect: Rect2, wall: String, pos_m: Vector2) -> float:
	match wall:
		"top", "bottom":
			return clampf(pos_m.x - rect.position.x, 0.0, rect.size.x)
		"left", "right":
			return clampf(pos_m.y - rect.position.y, 0.0, rect.size.y)
	return 0.0


func _wall_length(rect: Rect2, wall: String) -> float:
	if wall == "top" or wall == "bottom":
		return rect.size.x
	return rect.size.y


func _wall_start_dir(rect: Rect2, wall: String) -> Dictionary:
	match wall:
		"top":
			return {"start": rect.position, "dir": Vector2.RIGHT}
		"bottom":
			return {"start": rect.position + Vector2(0.0, rect.size.y), "dir": Vector2.RIGHT}
		"left":
			return {"start": rect.position, "dir": Vector2.DOWN}
		"right":
			return {"start": rect.position + Vector2(rect.size.x, 0.0), "dir": Vector2.DOWN}
	return {"start": rect.position, "dir": Vector2.RIGHT}


func _wall_segment(rect: Rect2, wall: String, offset_m: float, width_m: float) -> PackedVector2Array:
	var wall_data: Dictionary = _wall_start_dir(rect, wall)
	var start: Vector2 = wall_data["start"]
	var dir: Vector2 = wall_data["dir"]
	var length: float = _wall_length(rect, wall)
	var half_width: float = minf(width_m, length) * 0.5
	var center_offset: float = clampf(offset_m, half_width, maxf(half_width, length - half_width))
	var center: Vector2 = start + dir * center_offset
	return PackedVector2Array([center - dir * half_width, center + dir * half_width])


func _opening_segment_m(opening: Dictionary) -> PackedVector2Array:
	var a_id: int = int(opening.get("a", -1))
	if a_id < 0:
		return PackedVector2Array()
	var rect: Rect2 = _get_room_rect(a_id)
	var wall: String = String(opening.get("wall", ""))
	if wall == "":
		var b_id: int = int(opening.get("b", OUTSIDE_ID))
		var shared: Dictionary = _shared_wall_between(a_id, b_id)
		wall = String(shared.get("wall", "top"))
	var width: float = float(opening.get("width_m", 0.9))
	var offset: float = float(opening.get("offset_m", _wall_length(rect, wall) * 0.5))
	return _wall_segment(rect, wall, offset, width)


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _save_pressed() -> void:
	editor_data = Serializer.normalize_editor_data(editor_data)
	if Serializer.save_scenario(_path_edit.text.strip_edges(), editor_data):
		_set_status("Escenario guardado en %s." % _path_edit.text.strip_edges())
	else:
		_set_status("No se pudo guardar el escenario.")


func _load_pressed() -> void:
	var loaded: Dictionary = Serializer.load_scenario(_path_edit.text.strip_edges())
	if loaded.is_empty():
		_set_status("No se pudo cargar el escenario.")
		return
	editor_data = loaded
	if _stop_time_spin != null:
		_stop_time_spin.value = float(editor_data.get("stop_time_s", 0.0))
	_sync_hvac_option_from_data()
	_clear_selection()
	_set_status("Escenario cargado desde %s." % _path_edit.text.strip_edges())
	queue_redraw()


func _export_runtime_pressed() -> void:
	editor_data = Serializer.normalize_editor_data(editor_data)
	var runtime_template: Dictionary = Serializer.to_runtime_template(editor_data)
	var runtime_rooms: Array = runtime_template.get("rooms_data", [])
	if runtime_rooms.is_empty():
		_set_status("No se exporta: el escenario no tiene habitaciones.")
		return
	if Serializer.save_runtime_template(RUNTIME_EXPORT_PATH, editor_data):
		_set_status("Template runtime exportado en %s." % RUNTIME_EXPORT_PATH)
	else:
		_set_status("No se pudo exportar el template runtime.")


func _delete_selected() -> void:
	if selected_object_room_id >= 0 and selected_object_index >= 0:
		_delete_object(selected_object_room_id, selected_object_index)
	elif selected_opening_index >= 0:
		var openings: Array = editor_data.get("openings_data", [])
		openings.remove_at(selected_opening_index)
		editor_data["openings_data"] = openings
		_clear_selection()
		_set_status("Apertura eliminada.")
		queue_redraw()
	elif selected_room_id >= 0:
		_delete_room(selected_room_id)


func _apply_object_properties() -> void:
	if selected_object_room_id < 0 or selected_object_index < 0:
		_set_status("Selecciona un objeto antes de aplicar propiedades.")
		return
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		if int(rooms[i].get("id", -1)) != selected_object_room_id:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		if selected_object_index < 0 or selected_object_index >= objects.size():
			return
		var obj: Dictionary = objects[selected_object_index]
		obj["name"] = _obj_name_edit.text.strip_edges()
		var new_w: float = _obj_width_spin.value
		var new_h: float = _obj_height_spin.value
		obj["size_m"] = {"x": new_w, "y": new_h}
		obj["footprint_m2"] = new_w * new_h
		obj["fuel_energy_MJ"] = _obj_fuel_spin.value
		obj["remaining_fuel_MJ"] = _obj_fuel_spin.value
		obj["max_hrr_kw"] = _obj_hrr_spin.value
		objects[selected_object_index] = obj
		room["fuel_objects"] = objects
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		_set_status("Propiedades del objeto actualizadas.")
		queue_redraw()
		return


func _apply_opening_properties() -> void:
	if selected_opening_index < 0:
		_set_status("Selecciona una puerta o ventana primero.")
		return
	var openings: Array = editor_data.get("openings_data", [])
	if selected_opening_index >= openings.size():
		return
	var op: Dictionary = openings[selected_opening_index]
	if _opening_width_spin != null:
		op["width_m"] = _opening_width_spin.value
	if _opening_height_spin != null:
		op["height_m"] = _opening_height_spin.value
	if _opening_sill_spin != null:
		op["sill_m"] = _opening_sill_spin.value
	if _opening_open_option != null:
		op["open_fraction"] = 0.0 if _opening_open_option.selected == 0 else 1.0
	openings[selected_opening_index] = op
	editor_data["openings_data"] = openings
	_set_status("Apertura actualizada.")
	queue_redraw()


func _draw() -> void:
	_draw_rooms()
	_draw_openings()
	_draw_objects()
	if is_dragging_room:
		var rect: Rect2 = _normalized_rect(drag_start_m, drag_current_m)
		var rect_px: Rect2 = _rect_to_px(rect)
		draw_rect(rect_px, Color(0.25, 0.68, 0.95, 0.18), true)
		draw_rect(rect_px, Color(0.55, 0.90, 1.0, 0.85), false, 2.0)
		if ThemeDB.fallback_font != null and rect.size.x > 0.01 and rect.size.y > 0.01:
			var area: float = rect.size.x * rect.size.y
			var preview_text: String = "%.2f × %.2f m  (%.2f m²)" % [rect.size.x, rect.size.y, area]
			draw_string(
				ThemeDB.fallback_font,
				rect_px.position + Vector2(6.0, 18.0),
				preview_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				maxf(60.0, rect_px.size.x - 8.0),
				12,
				Color(0.55, 0.90, 1.0, 0.95)
			)


func _draw_rooms() -> void:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(room.get("id", -1))
		var rect: Rect2 = _get_room_rect(room_id)
		var rect_px: Rect2 = _rect_to_px(rect)
		var fill: Color = _room_selected_fill if room_id == selected_room_id else _room_fill
		draw_rect(rect_px, fill, true)
		draw_rect(rect_px, _room_outline, false, 2.0)
		if ThemeDB.fallback_font != null:
			var h: float = float(room.get("height_m", 2.7))
			var area_m2: float = rect.size.x * rect.size.y
			var vol_m3: float = area_m2 * h
			var dim_text: String = "%.2f × %.2f m" % [rect.size.x, rect.size.y]
			var area_text: String = "%.2f m²  ·  %.2f m³" % [area_m2, vol_m3]
			draw_string(
				ThemeDB.fallback_font,
				rect_px.position + Vector2(8.0, 18.0),
				String(room.get("name", "Room %d" % room_id)),
				HORIZONTAL_ALIGNMENT_LEFT,
				maxf(40.0, rect_px.size.x - 12.0),
				13,
				Color(0.94, 0.97, 1.0, 0.92)
			)
			if rect_px.size.y >= 36.0:
				draw_string(
					ThemeDB.fallback_font,
					rect_px.position + Vector2(8.0, 32.0),
					dim_text,
					HORIZONTAL_ALIGNMENT_LEFT,
					maxf(40.0, rect_px.size.x - 12.0),
					11,
					Color(0.75, 0.88, 0.95, 0.85)
				)
			if rect_px.size.y >= 52.0:
				draw_string(
					ThemeDB.fallback_font,
					rect_px.position + Vector2(8.0, 46.0),
					area_text,
					HORIZONTAL_ALIGNMENT_LEFT,
					maxf(40.0, rect_px.size.x - 12.0),
					11,
					Color(0.65, 0.82, 0.65, 0.85)
				)


func _draw_openings() -> void:
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var opening: Dictionary = openings[i]
		var segment_m: PackedVector2Array = _opening_segment_m(opening)
		if segment_m.size() != 2:
			continue
		var p1: Vector2 = _m_to_px(segment_m[0])
		var p2: Vector2 = _m_to_px(segment_m[1])
		var type_str: String = String(opening.get("type", "door"))
		var color: Color = _window_color if type_str == "window" else _door_color
		if i == selected_opening_index:
			color = Color(1.0, 1.0, 0.45, 1.0)
		draw_line(p1, p2, Color(0.04, 0.06, 0.07, 0.95), 8.0)
		draw_line(p1, p2, color, 4.0)


func _draw_objects() -> void:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_id: int = int(room.get("id", -1))
		var room_rect: Rect2 = _get_room_rect(room_id)
		var objects: Array = room.get("fuel_objects", [])
		for object_index in range(objects.size()):
			if typeof(objects[object_index]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[object_index]
			var pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
			var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
			var obj_rect_px: Rect2 = _rect_to_px(Rect2(room_rect.position + pos, size))
			var selected: bool = room_id == selected_object_room_id and object_index == selected_object_index
			var fill: Color = _object_selected_color if selected else _object_color
			draw_rect(obj_rect_px, fill, true)
			draw_rect(obj_rect_px, Color(0.18, 0.09, 0.04, 0.92), false, 1.5)
			if bool(obj.get("is_primary_ignition_source", false)):
				draw_circle(obj_rect_px.get_center(), 7.0, _ignition_color)
				draw_circle(obj_rect_px.get_center(), 3.5, Color(1.0, 0.94, 0.25, 0.98))
			if ThemeDB.fallback_font != null and obj_rect_px.size.x >= 48.0:
				draw_string(
					ThemeDB.fallback_font,
					obj_rect_px.position + Vector2(4.0, 13.0),
					String(obj.get("name", obj.get("kind", ""))),
					HORIZONTAL_ALIGNMENT_LEFT,
					obj_rect_px.size.x - 8.0,
					10,
					Color(0.08, 0.05, 0.03, 0.9)
				)


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _scan_scenario_files() -> void:
	if _scenario_option == null:
		return
	_scenario_option.clear()
	_scenario_paths.clear()

	var dir := DirAccess.open(SCENARIOS_RES_PATH)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_scenario_paths.append(SCENARIOS_RES_PATH + "/" + file_name)
			_scenario_option.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_scenario_pressed() -> void:
	if _scenario_option == null:
		return
	var idx: int = _scenario_option.selected
	if idx < 0 or idx >= _scenario_paths.size():
		_set_status("Selecciona un escenario de la lista.")
		return
	var path: String = _scenario_paths[idx]
	var loaded: Dictionary = Serializer.load_scenario(path)
	if loaded.is_empty():
		_set_status("No se pudo cargar: %s" % path)
		return
	editor_data = loaded
	if _stop_time_spin != null:
		_stop_time_spin.value = float(editor_data.get("stop_time_s", 0.0))
	_sync_hvac_option_from_data()
	_clear_selection()
	_set_status("Escenario cargado: %s" % path.get_file())
	queue_redraw()


func _run_simulation_pressed() -> void:
	editor_data = Serializer.normalize_editor_data(editor_data)
	var runtime_rooms: Array = editor_data.get("rooms_data", [])
	if runtime_rooms.is_empty():
		_set_status("El escenario no tiene habitaciones. No se puede ejecutar.")
		return
	if not Serializer.save_runtime_template(RUNTIME_EXPORT_PATH, editor_data):
		_set_status("Error al exportar el template runtime.")
		return
	_set_status("Iniciando simulación...")
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _cancel_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


# ============================================================
# UI FÍSICA EN ESCENA
# ------------------------------------------------------------
# Permite editar la interfaz directamente desde Godot.
# Si los nodos existen en ScenarioEditorScene.tscn, se usan;
# si no existen, el script cae al _setup_ui() antiguo.
# ============================================================
func _bind_existing_ui() -> bool:
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas == null:
		return false
	_ui_root = canvas.get_node_or_null("UI") as Control
	if _ui_root == null:
		return false

	var btn_select := _ui_root.get_node_or_null("TopBar/HBox/BtnSelect") as Button
	var btn_room := _ui_root.get_node_or_null("TopBar/HBox/BtnRoom") as Button
	var btn_corridor := _ui_root.get_node_or_null("TopBar/HBox/BtnCorridorL") as Button
	var btn_door := _ui_root.get_node_or_null("TopBar/HBox/BtnDoor") as Button
	var btn_window := _ui_root.get_node_or_null("TopBar/HBox/BtnWindow") as Button
	var btn_object := _ui_root.get_node_or_null("TopBar/HBox/BtnObject") as Button
	var btn_ignite := _ui_root.get_node_or_null("TopBar/HBox/BtnIgnite") as Button
	var btn_delete := _ui_root.get_node_or_null("TopBar/HBox/BtnDelete") as Button
	if btn_corridor == null:
		var topbar := _ui_root.get_node_or_null("TopBar/HBox") as HBoxContainer
		if topbar != null:
			btn_corridor = Button.new()
			btn_corridor.name = "BtnCorridorL"
			btn_corridor.text = "Corr L"
			btn_corridor.custom_minimum_size = Vector2(82.0, 34.0)
			topbar.add_child(btn_corridor)

	var required_buttons: Array[Button] = [btn_select, btn_room, btn_corridor, btn_door, btn_window, btn_object, btn_ignite, btn_delete]
	for b in required_buttons:
		if b == null:
			return false

	_tool_buttons.clear()
	_register_tool_button(btn_select, Tool.SELECT)
	_register_tool_button(btn_room, Tool.ROOM)
	_register_tool_button(btn_corridor, Tool.CORRIDOR_L)
	_register_tool_button(btn_door, Tool.DOOR)
	_register_tool_button(btn_window, Tool.WINDOW)
	_register_tool_button(btn_object, Tool.OBJECT)
	_register_tool_button(btn_ignite, Tool.IGNITION)
	_register_tool_button(btn_delete, Tool.DELETE)

	_object_kind_option = _ui_root.get_node_or_null("LeftPanel/VBox/ObjectTypeOption") as OptionButton
	_path_edit = _ui_root.get_node_or_null("LeftPanel/VBox/PathEdit") as LineEdit
	_scenario_option = _ui_root.get_node_or_null("LeftPanel/VBox/ScenarioOption") as OptionButton
	_hvac_option = _ui_root.get_node_or_null("LeftPanel/VBox/HVACOption") as OptionButton
	_stop_time_spin = _ui_root.get_node_or_null("LeftPanel/VBox/StopTimeSpin") as SpinBox
	_status_label = _ui_root.get_node_or_null("LeftPanel/VBox/StatusLabel") as Label

	_name_edit = _ui_root.get_node_or_null("RightPanel/VBox/RoomNameEdit") as LineEdit
	_kind_edit = _ui_root.get_node_or_null("RightPanel/VBox/RoomKindEdit") as LineEdit
	_height_spin = _ui_root.get_node_or_null("RightPanel/VBox/RoomHeightSpin") as SpinBox
	_fuel_spin = _ui_root.get_node_or_null("RightPanel/VBox/FuelEnergySpin") as SpinBox
	_hrr_spin = _ui_root.get_node_or_null("RightPanel/VBox/MaxHrrSpin") as SpinBox

	_obj_props_container = _ui_root.get_node_or_null("RightPanel/VBox/ObjProps") as Control
	_obj_name_edit = _ui_root.get_node_or_null("RightPanel/VBox/ObjProps/ObjNameEdit") as LineEdit
	_obj_width_spin = _ui_root.get_node_or_null("RightPanel/VBox/ObjProps/ObjWidthSpin") as SpinBox
	_obj_height_spin = _ui_root.get_node_or_null("RightPanel/VBox/ObjProps/ObjHeightSpin") as SpinBox
	_obj_fuel_spin = _ui_root.get_node_or_null("RightPanel/VBox/ObjProps/ObjFuelSpin") as SpinBox
	_obj_hrr_spin = _ui_root.get_node_or_null("RightPanel/VBox/ObjProps/ObjHrrSpin") as SpinBox

	_opening_props_container = _ui_root.get_node_or_null("RightPanel/VBox/OpeningProps") as Control
	_opening_type_label = _ui_root.get_node_or_null("RightPanel/VBox/OpeningProps/OpeningTypeLabel") as Label
	_opening_width_spin = _ui_root.get_node_or_null("RightPanel/VBox/OpeningProps/OpeningWidthSpin") as SpinBox
	_opening_height_spin = _ui_root.get_node_or_null("RightPanel/VBox/OpeningProps/OpeningHeightSpin") as SpinBox
	_opening_sill_spin = _ui_root.get_node_or_null("RightPanel/VBox/OpeningProps/OpeningSillSpin") as SpinBox
	_opening_open_option = _ui_root.get_node_or_null("RightPanel/VBox/OpeningProps/OpeningOpenOption") as OptionButton
	_connect_button(_ui_root.get_node_or_null("RightPanel/VBox/OpeningProps/BtnApplyOpening") as Button, _apply_opening_properties)

	if _object_kind_option == null or _path_edit == null or _scenario_option == null or _status_label == null:
		return false
	if _name_edit == null or _kind_edit == null or _height_spin == null or _fuel_spin == null or _hrr_spin == null:
		return false

	_populate_object_type_option()
	_ensure_hvac_option_in_existing_ui()
	_path_edit.text = DEFAULT_SAVE_PATH

	# Poblamos el OptionButton de estado inicial de apertura
	if _opening_open_option != null and _opening_open_option.get_item_count() == 0:
		_opening_open_option.add_item("Cerrada", 0)
		_opening_open_option.add_item("Abierta", 1)

	_connect_button(_ui_root.get_node_or_null("LeftPanel/VBox/BtnSave") as Button, _save_pressed)
	_connect_button(_ui_root.get_node_or_null("LeftPanel/VBox/BtnLoad") as Button, _load_pressed)
	_connect_button(_ui_root.get_node_or_null("LeftPanel/VBox/BtnExportRuntime") as Button, _export_runtime_pressed)
	_connect_button(_ui_root.get_node_or_null("LeftPanel/VBox/BtnLoadScenario") as Button, _load_scenario_pressed)
	_connect_button(_ui_root.get_node_or_null("RightPanel/VBox/BtnApplyRoom") as Button, _apply_room_properties)
	_connect_button(_ui_root.get_node_or_null("RightPanel/VBox/ObjProps/BtnApplyObject") as Button, _apply_object_properties)
	_connect_button(_ui_root.get_node_or_null("RightPanel/VBox/ObjProps/BtnDeleteObject") as Button, _delete_selected)
	_connect_button(_ui_root.get_node_or_null("BottomBar/HBox/BtnStartSimulation") as Button, _run_simulation_pressed)
	_connect_button(_ui_root.get_node_or_null("BottomBar/HBox/BtnCancel") as Button, _cancel_pressed)

	if _stop_time_spin != null:
		_stop_time_spin.value = 0.0
		if not _stop_time_spin.value_changed.is_connected(_on_stop_time_changed):
			_stop_time_spin.value_changed.connect(_on_stop_time_changed)
	_sync_hvac_option_from_data()

	_scan_scenario_files()
	_refresh_property_panel()
	_set_status("Listo. UI editable desde la escena. Dibuja habitaciones con Room.")
	return true


func _register_tool_button(button: Button, tool_id: int) -> void:
	button.toggle_mode = true
	if not button.pressed.is_connected(Callable(self, "_set_tool").bind(tool_id)):
		button.pressed.connect(Callable(self, "_set_tool").bind(tool_id))
	_tool_buttons[tool_id] = button


func _connect_button(button: Button, callback: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _populate_object_type_option() -> void:
	if _object_kind_option == null:
		return
	_object_kind_option.clear()
	for kind in ObjectLibraryScript.get_object_kinds():
		_object_kind_option.add_item(kind)


func _on_stop_time_changed(v: float) -> void:
	editor_data["stop_time_s"] = v


func _ensure_hvac_option_in_existing_ui() -> void:
	if _hvac_option != null:
		_populate_hvac_option()
		if not _hvac_option.item_selected.is_connected(_on_hvac_option_selected):
			_hvac_option.item_selected.connect(_on_hvac_option_selected)
		return

	var left_vbox := _ui_root.get_node_or_null("LeftPanel/VBox") as VBoxContainer
	if left_vbox == null:
		return

	var row := HBoxContainer.new()
	row.name = "HVACRow"
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = "HVAC"
	label.custom_minimum_size.x = 82.0
	row.add_child(label)
	_hvac_option = OptionButton.new()
	_hvac_option.name = "HVACOption"
	_hvac_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hvac_option)
	left_vbox.add_child(row)
	var scenario_option := left_vbox.get_node_or_null("ScenarioOption") as OptionButton
	if scenario_option != null:
		left_vbox.move_child(row, scenario_option.get_index())
	_populate_hvac_option()
	if not _hvac_option.item_selected.is_connected(_on_hvac_option_selected):
		_hvac_option.item_selected.connect(_on_hvac_option_selected)


func _populate_hvac_option() -> void:
	if _hvac_option == null:
		return
	if _hvac_option.get_item_count() == 0:
		_hvac_option.add_item("Sin HVAC", 0)
		_hvac_option.add_item("Instalado OFF", 1)
		_hvac_option.add_item("Instalado ON", 2)
	_sync_hvac_option_from_data()


func _sync_hvac_option_from_data() -> void:
	if _hvac_option == null:
		return
	var mode: String = String(editor_data.get("hvac_mode", "none")).to_lower()
	match mode:
		"on":
			_hvac_option.select(2)
		"off":
			_hvac_option.select(1)
		_:
			_hvac_option.select(0)


func _on_hvac_option_selected(index: int) -> void:
	var mode: String = "none"
	if index == 1:
		mode = "off"
	elif index == 2:
		mode = "on"
	editor_data["hvac_mode"] = mode
	editor_data["hvac_data"] = {
		"exists": mode != "none",
		"on": mode == "on",
		"mode": mode
	}
