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
const DEFAULT_FLOOR_HEIGHT_M: float = 2.90
const EditorGridScript = preload("res://editor/EditorGrid.gd")
const ObjectLibraryScript = preload("res://editor/ObjectLibrary.gd")
const Serializer = preload("res://editor/ScenarioSerializer.gd")
const EDITOR_LOGO_PATH: String = "res://assets/ui/simufire_logo_editor.png"
const EDITOR_FONT_PATH: String = "res://assets/fonts/bahnschrift.ttf"



const UI_BG: Color = Color(0.00, 0.01, 0.01, 1.0)
const UI_PANEL: Color = Color(0.02, 0.05, 0.07, 0.94)
const UI_PANEL_DARK: Color = Color(0.00, 0.02, 0.03, 0.98)
const UI_FIELD: Color = Color(0.03, 0.07, 0.09, 0.96)
const UI_BORDER: Color = Color(0.18, 0.22, 0.25, 0.92)
const UI_BORDER_HOT: Color = Color(1.00, 0.25, 0.00, 0.98)
const UI_BLUE: Color = Color(0.00, 0.70, 0.88, 0.96)
const UI_GREEN: Color = Color(0.55, 1.00, 0.36, 0.96)
const UI_YELLOW: Color = Color(1.00, 0.78, 0.00, 0.96)
const UI_TEXT: Color = Color(0.90, 0.94, 0.96, 0.98)
const UI_TEXT_MUTED: Color = Color(0.49, 0.55, 0.60, 0.92)

#Zoom raton
const ZOOM_IN_FACTOR := 1.10
const ZOOM_OUT_FACTOR := 0.90
const MIN_ZOOM := 0.35
const MAX_ZOOM := 4.0
const PAN_SPEED := 650.0

var is_middle_panning := false
var last_mouse_pos := Vector2.ZERO
@onready var camera: Camera2D = $World/Camera2D

###################

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
var current_floor_index: int = 0

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
var _floor_option: OptionButton
var _floor_level_spin: SpinBox
var _floor_status_label: Label
var _scenario_paths: Array[String] = []
var _stop_time_spin: SpinBox
var _corridor_width_spin: SpinBox
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

var _room_fill: Color = Color(0.05, 0.07, 0.09, 0.72)
var _room_selected_fill: Color = Color(0.08, 0.14, 0.16, 0.84)
var _room_outline: Color = Color(0.28, 0.32, 0.35, 0.95)
var _corridor_fill: Color = Color(0.03, 0.10, 0.11, 0.76)
var _corridor_selected_fill: Color = Color(0.04, 0.18, 0.19, 0.88)
var _corridor_outline: Color = UI_BLUE
var _corridor_preview_fill: Color = Color(0.00, 0.70, 0.88, 0.22)
var _corridor_preview_outline: Color = Color(0.00, 0.84, 1.00, 0.92)
var _corridor_path_color: Color = UI_YELLOW
var _door_color: Color = UI_GREEN
var _window_color: Color = UI_BLUE
var _object_color: Color = Color(1.00, 0.25, 0.00, 0.86)
var _object_selected_color: Color = UI_YELLOW
var _ignition_color: Color = Color(1.00, 0.08, 0.02, 0.98)

var _editor_theme: Theme
var _editor_font: Font
var _editor_title_font: Font

# Menú contextual (clic derecho)
const _CTX_EDIT      := 1
const _CTX_DELETE    := 2
const _CTX_ADD_DOOR  := 3
const _CTX_ADD_WIN   := 4
const _CTX_IGNITE    := 5
const _CTX_DUPLICATE := 6
const _CTX_DESELECT  := 7
var _context_menu: PopupMenu = null
var _ctx_pos_m: Vector2 = Vector2.ZERO
var _ctx_room_id: int = -1
var _ctx_obj_index: int = -1
var _ctx_opening_index: int = -1

func _ready() -> void:
	_create_empty_scenario()
	_setup_grid()
	if not _bind_existing_ui():
		_setup_ui()
	_apply_editor_visual_style()
	_ensure_floor_data()
	_sync_floor_controls()
	_set_tool(Tool.SELECT)
	queue_redraw()


func _setup_grid() -> void:
	var world: Node2D = get_node_or_null("World") as Node2D
	if world == null:
		world = Node2D.new()
		world.name = "World"
		add_child(world)
		move_child(world, 0)

	var grid: Node2D = world.get_node_or_null("EditorGrid") as Node2D
	if grid == null:
		grid = EditorGridScript.new()
		grid.name = "EditorGrid"
		world.add_child(grid)

	grid.set("pixels_per_meter", PIXELS_PER_METER)
	grid.set("grid_m", GRID_M)
	grid.z_index = -100
	grid.set("background_color", UI_BG)
	grid.set("minor_color", Color(0.05, 0.08, 0.10, 0.62))
	grid.set("major_color", Color(0.13, 0.17, 0.20, 0.80))
	grid.set("axis_color", Color(1.00, 0.25, 0.00, 0.50))

func _apply_editor_visual_style() -> void:
	RenderingServer.set_default_clear_color(UI_BG)
	if _ui_root == null:
		return
	_editor_font = _make_system_font(PackedStringArray(["Roboto Condensed", "Bahnschrift", "Segoe UI", "Arial Narrow", "Arial"]), 500, 92)
	_editor_title_font = _make_system_font(PackedStringArray(["Bahnschrift SemiBold Condensed", "Agency FB", "Roboto Condensed", "Arial Narrow", "Arial"]), 700, 82)
	# Respeta el tema definido en la escena (.tres) si existe; si no, genera uno por codigo.
	if _ui_root.theme == null:
		_editor_theme = _build_editor_theme()
		_ui_root.theme = _editor_theme
	else:
		_editor_theme = _ui_root.theme
	_ensure_editor_branding()
	_style_editor_controls(_ui_root)


func _make_system_font(names: PackedStringArray, weight: int, stretch: int) -> Font:
	var project_font := load(EDITOR_FONT_PATH) as FontFile
	if project_font != null:
		return project_font
	var font := SystemFont.new()
	font.font_names = names
	font.font_weight = weight
	font.font_stretch = stretch
	return font


func _build_editor_theme() -> Theme:
	var theme := Theme.new()
	var control_types: Array[String] = [
		"Label", "Button", "LineEdit", "OptionButton", "SpinBox", "PopupMenu",
		"CheckBox", "Tree", "ItemList"
	]
	for type_name in control_types:
		theme.set_font("font", type_name, _editor_font)

	theme.set_font_size("font_size", "Label", 12)
	theme.set_font_size("font_size", "Button", 11)
	theme.set_font_size("font_size", "LineEdit", 12)
	theme.set_font_size("font_size", "OptionButton", 11)
	theme.set_font_size("font_size", "SpinBox", 12)

	theme.set_color("font_color", "Label", UI_TEXT)
	theme.set_color("font_color", "Button", UI_TEXT)
	theme.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0, 1.0))
	theme.set_color("font_pressed_color", "Button", UI_BORDER_HOT)
	theme.set_color("font_focus_color", "Button", UI_TEXT)
	theme.set_color("font_disabled_color", "Button", Color(0.34, 0.38, 0.42, 0.72))
	theme.set_color("font_color", "LineEdit", UI_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", UI_TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", UI_BORDER_HOT)
	theme.set_color("font_color", "OptionButton", UI_TEXT)

	var panel_box: StyleBoxFlat = _stylebox(UI_PANEL, UI_BORDER, 1, 0, Vector2(12.0, 12.0))
	var field_box: StyleBoxFlat = _stylebox(UI_FIELD, UI_BORDER, 1, 0, Vector2(8.0, 6.0))
	var field_focus_box: StyleBoxFlat = _stylebox(UI_FIELD, UI_BLUE, 1, 0, Vector2(8.0, 6.0))
	var button_box: StyleBoxFlat = _stylebox(UI_PANEL_DARK, UI_BORDER, 1, 0, Vector2(12.0, 7.0))
	var button_hover_box: StyleBoxFlat = _stylebox(Color(0.04, 0.10, 0.12, 0.98), UI_BLUE, 1, 0, Vector2(12.0, 7.0))
	var button_pressed_box: StyleBoxFlat = _stylebox(Color(0.16, 0.05, 0.01, 0.98), UI_BORDER_HOT, 1, 0, Vector2(12.0, 7.0))
	var button_disabled_box: StyleBoxFlat = _stylebox(Color(0.03, 0.04, 0.05, 0.82), Color(0.10, 0.12, 0.14, 0.80), 1, 0, Vector2(12.0, 7.0))

	theme.set_stylebox("panel", "PanelContainer", panel_box)
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, button_box)
		theme.set_stylebox("hover", type_name, button_hover_box)
		theme.set_stylebox("pressed", type_name, button_pressed_box)
		theme.set_stylebox("focus", type_name, _stylebox(Color(0.04, 0.08, 0.10, 0.58), UI_BLUE, 1, 0, Vector2(12.0, 7.0)))
		theme.set_stylebox("disabled", type_name, button_disabled_box)
	for type_name in ["LineEdit", "SpinBox"]:
		theme.set_stylebox("normal", type_name, field_box)
		theme.set_stylebox("focus", type_name, field_focus_box)
		theme.set_stylebox("read_only", type_name, _stylebox(Color(0.02, 0.03, 0.04, 0.85), UI_BORDER, 1, 0, Vector2(8.0, 6.0)))

	var separator := StyleBoxLine.new()
	separator.color = Color(0.18, 0.22, 0.25, 0.72)
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	return theme


func _stylebox(bg: Color, border: Color, border_width: int, radius: int, margin: Vector2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_right = radius
	box.corner_radius_bottom_left = radius
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	return box


func _layout_editor_shell() -> void:
	pass  # Layout controlled by scene anchors


func _ensure_editor_branding() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	var brand := left_vbox.get_node_or_null("BrandHeader") as VBoxContainer
	if brand == null:
		brand = VBoxContainer.new()
		brand.name = "BrandHeader"
		brand.custom_minimum_size = Vector2(0.0, 220.0)
		brand.add_theme_constant_override("separation", 6)
		left_vbox.add_child(brand)
		left_vbox.move_child(brand, 0)

	var logo := brand.get_node_or_null("Logo") as TextureRect
	if logo == null:
		logo = TextureRect.new()
		logo.name = "Logo"
		logo.custom_minimum_size = Vector2(292.0, 205.0)
		logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		brand.add_child(logo)
	logo.texture = load(EDITOR_LOGO_PATH) as Texture2D

	var mode_label := brand.get_node_or_null("EditorModeLabel") as Label
	if mode_label == null:
		mode_label = Label.new()
		mode_label.name = "EditorModeLabel"
		mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		brand.add_child(mode_label)
	mode_label.text = "TACTICAL SCENARIO EDITOR"
	mode_label.add_theme_font_override("font", _editor_title_font)
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", UI_TEXT_MUTED)


func _find_left_vbox() -> VBoxContainer:
	var left_vbox := _ui_root.get_node_or_null("LeftPanel/VBox") as VBoxContainer
	if left_vbox != null:
		return left_vbox
	left_vbox = _ui_root.get_node_or_null("ToolsPanel/VBox") as VBoxContainer
	if left_vbox != null:
		return left_vbox
	var panel := _ui_root.get_node_or_null("ToolsPanel") as PanelContainer
	if panel != null:
		for child in panel.get_children():
			if child is VBoxContainer:
				return child as VBoxContainer
	return null


func _style_editor_controls(node: Node) -> void:
	if node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", _stylebox(UI_PANEL, UI_BORDER, 1, 0, Vector2(12.0, 12.0)))
	if node is Label:
		var label := node as Label
		label.add_theme_font_override("font", _editor_font)
		label.add_theme_color_override("font_color", UI_TEXT)
		if _is_heading_label(label):
			label.text = label.text.to_upper()
			label.add_theme_font_override("font", _editor_title_font)
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_color", UI_BORDER_HOT)
		elif label.name == "StatusLabel":
			label.add_theme_font_size_override("font_size", 11)
			label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		elif label.name == "EditorModeLabel":
			label.add_theme_font_override("font", _editor_title_font)
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		else:
			label.add_theme_font_size_override("font_size", 11)
			if not label.text.contains(":") and label.text.length() <= 36:
				label.text = label.text.to_upper()
	if node is Button:
		var button := node as Button
		button.text = button.text.to_upper()
		button.add_theme_font_override("font", _editor_title_font)
		button.add_theme_font_size_override("font_size", 11)
	if node is LineEdit:
		var edit := node as LineEdit
		edit.add_theme_font_override("font", _editor_font)
		edit.add_theme_font_size_override("font_size", 12)
	if node is OptionButton:
		var option := node as OptionButton
		option.add_theme_font_override("font", _editor_title_font)
		option.add_theme_font_size_override("font_size", 11)
	for child in node.get_children():
		_style_editor_controls(child)


func _is_heading_label(label: Label) -> bool:
	var n: String = label.name.to_lower()
	if n == "editormodelabel":
		return false
	return n.ends_with("title") or n == "objectlabel" or n == "scenariolabel" or n == "stoptimelabel"


func _create_empty_scenario() -> void:
	editor_data = {
		"version": 1,
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"floors": _default_floors(),
		"room_rect_m": {},
		"rooms_data": [],
		"openings_data": []
	}
	current_floor_index = 0


func _default_floors() -> Array:
	return [
		{"name": "PB", "level_m": 0.0}
	]


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
	main.name = "VBox"
	main.add_theme_constant_override("separation", 8)
	panel.add_child(main)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	main.add_child(toolbar)
	_add_tool_button(toolbar, "Sel", Tool.SELECT)
	_add_tool_button(toolbar, "Room", Tool.ROOM)
	_add_tool_button(toolbar, "Pasillo", Tool.CORRIDOR_L)
	_add_tool_button(toolbar, "Door", Tool.DOOR)
	_add_tool_button(toolbar, "Window", Tool.WINDOW)
	_add_tool_button(toolbar, "Object", Tool.OBJECT)
	_add_tool_button(toolbar, "Ignite", Tool.IGNITION)
	_add_tool_button(toolbar, "Del", Tool.DELETE)

	_create_floor_controls(main)
	main.add_child(HSeparator.new())

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

	_corridor_width_spin = _add_spin(main, "Pasillo (m)", 0.6, 3.0, 0.05)
	_corridor_width_spin.value = corridor_width_m
	_corridor_width_spin.value_changed.connect(_on_corridor_width_changed)

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


func _create_floor_controls(parent: Control) -> void:
	var title := Label.new()
	title.name = "FloorTitle"
	title.text = "Plantas"
	parent.add_child(title)

	var row := HBoxContainer.new()
	row.name = "FloorRow"
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	_floor_option = OptionButton.new()
	_floor_option.name = "FloorOption"
	_floor_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_floor_option)
	if not _floor_option.item_selected.is_connected(_on_floor_selected):
		_floor_option.item_selected.connect(_on_floor_selected)

	var add_button := Button.new()
	add_button.name = "BtnAddFloor"
	add_button.text = "+ Planta"
	add_button.custom_minimum_size = Vector2(86.0, 28.0)
	add_button.pressed.connect(_add_floor_pressed)
	row.add_child(add_button)

	_floor_level_spin = _add_spin(parent, "Cota (m)", -2.0, 30.0, 0.05)
	_floor_level_spin.name = "FloorLevelSpin"
	if not _floor_level_spin.value_changed.is_connected(_on_floor_level_changed):
		_floor_level_spin.value_changed.connect(_on_floor_level_changed)

	_floor_status_label = Label.new()
	_floor_status_label.name = "FloorStatusLabel"
	_floor_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_floor_status_label.add_theme_font_size_override("font_size", 10)
	_floor_status_label.modulate = UI_TEXT_MUTED
	parent.add_child(_floor_status_label)
	_sync_floor_controls()


func _ensure_floor_data() -> void:
	if typeof(editor_data.get("floors", [])) != TYPE_ARRAY:
		editor_data["floors"] = _default_floors()
	var floors: Array = editor_data.get("floors", [])
	if floors.is_empty():
		floors = _default_floors()
	var normalized: Array = []
	for i in range(floors.size()):
		if typeof(floors[i]) != TYPE_DICTIONARY:
			continue
		var raw: Dictionary = floors[i]
		var level_m: float = float(raw.get("level_m", 0.0 if normalized.is_empty() else normalized.size() * DEFAULT_FLOOR_HEIGHT_M))
		normalized.append({
			"name": String(raw.get("name", _default_floor_name(normalized.size()))),
			"level_m": level_m
		})
	for raw_room in editor_data.get("rooms_data", []):
		if typeof(raw_room) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = raw_room
		_add_floor_level_if_missing(normalized, float(room.get("floor_level_z_m", 0.0)))
	if normalized.is_empty():
		normalized = _default_floors()
	normalized.sort_custom(func(a, b): return float(a.get("level_m", 0.0)) < float(b.get("level_m", 0.0)))
	for i in range(normalized.size()):
		var floor: Dictionary = normalized[i]
		if String(floor.get("name", "")).strip_edges() == "":
			floor["name"] = _default_floor_name(i)
		normalized[i] = floor
	editor_data["floors"] = normalized
	current_floor_index = clampi(current_floor_index, 0, normalized.size() - 1)


func _add_floor_level_if_missing(floors: Array, level_m: float) -> void:
	for raw in floors:
		if typeof(raw) == TYPE_DICTIONARY and absf(float(raw.get("level_m", 0.0)) - level_m) < 0.05:
			return
	floors.append({"name": _default_floor_name(floors.size()), "level_m": level_m})


func _default_floor_name(index: int) -> String:
	return "PB" if index <= 0 else "P%d" % index


func _get_floors() -> Array:
	_ensure_floor_data()
	return editor_data.get("floors", [])


func _sync_floor_controls() -> void:
	var floors: Array = _get_floors()
	if _floor_option != null:
		_floor_option.clear()
		for i in range(floors.size()):
			var floor: Dictionary = floors[i]
			_floor_option.add_item("%s  %.2fm" % [String(floor.get("name", _default_floor_name(i))), float(floor.get("level_m", 0.0))], i)
		if _floor_option.get_item_count() > 0:
			_floor_option.select(clampi(current_floor_index, 0, _floor_option.get_item_count() - 1))
	if _floor_level_spin != null and not floors.is_empty():
		var level_m: float = _current_floor_level_m()
		if absf(_floor_level_spin.value - level_m) > 0.001:
			_floor_level_spin.value = level_m
	_update_floor_status()


func _update_floor_status() -> void:
	if _floor_status_label == null:
		return
	var rooms_on_floor: int = 0
	for room in editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and _is_room_on_current_floor(room):
			rooms_on_floor += 1
	_floor_status_label.text = "Editando %s. Nuevas habitaciones, puertas, objetos y ventanas se crean en esta planta. Salas: %d." % [
		_current_floor_name(),
		rooms_on_floor
	]


func _on_floor_selected(index: int) -> void:
	current_floor_index = clampi(index, 0, maxi(0, _get_floors().size() - 1))
	pending_door_room_id = -1
	_clear_selection()
	_sync_floor_controls()
	_set_status("Planta activa: %s." % _current_floor_name())
	queue_redraw()


func _add_floor_pressed() -> void:
	var floors: Array = _get_floors()
	var next_level_m: float = 0.0
	if not floors.is_empty():
		next_level_m = float(floors[floors.size() - 1].get("level_m", 0.0)) + DEFAULT_FLOOR_HEIGHT_M
	floors.append({"name": _default_floor_name(floors.size()), "level_m": next_level_m})
	editor_data["floors"] = floors
	current_floor_index = floors.size() - 1
	pending_door_room_id = -1
	_clear_selection()
	_sync_floor_controls()
	_set_status("Nueva planta creada: %s." % _current_floor_name())
	queue_redraw()


func _on_floor_level_changed(value: float) -> void:
	var floors: Array = _get_floors()
	if current_floor_index < 0 or current_floor_index >= floors.size():
		return
	var floor: Dictionary = floors[current_floor_index]
	var selected_floor_name: String = String(floor.get("name", _default_floor_name(current_floor_index)))
	var previous_level_m: float = float(floor.get("level_m", 0.0))
	if absf(previous_level_m - value) <= 0.001:
		return
	floor["level_m"] = value
	floors[current_floor_index] = floor
	editor_data["floors"] = floors
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = rooms[i]
		if absf(float(room.get("floor_level_z_m", 0.0)) - previous_level_m) < 0.05:
			room["floor_level_z_m"] = value
			rooms[i] = room
	editor_data["rooms_data"] = rooms
	_ensure_floor_data()
	var normalized_floors: Array = editor_data.get("floors", [])
	for i in range(normalized_floors.size()):
		if typeof(normalized_floors[i]) != TYPE_DICTIONARY:
			continue
		var normalized_floor: Dictionary = normalized_floors[i]
		if String(normalized_floor.get("name", "")) == selected_floor_name and absf(float(normalized_floor.get("level_m", 0.0)) - value) < 0.05:
			current_floor_index = i
			break
	_sync_floor_controls()
	queue_redraw()


func _current_floor_level_m() -> float:
	var floors: Array = _get_floors()
	if floors.is_empty():
		return 0.0
	var floor: Dictionary = floors[clampi(current_floor_index, 0, floors.size() - 1)]
	return float(floor.get("level_m", 0.0))


func _current_floor_name() -> String:
	var floors: Array = _get_floors()
	if floors.is_empty():
		return "PB"
	var floor: Dictionary = floors[clampi(current_floor_index, 0, floors.size() - 1)]
	return String(floor.get("name", _default_floor_name(current_floor_index)))


func _room_floor_level(room: Dictionary) -> float:
	return float(room.get("floor_level_z_m", 0.0))


func _room_id_floor_level(room_id: int) -> float:
	var room: Dictionary = _get_room(room_id)
	return _room_floor_level(room) if not room.is_empty() else 0.0


func _is_room_on_current_floor(room: Dictionary) -> bool:
	return absf(_room_floor_level(room) - _current_floor_level_m()) < 0.05


func _opening_on_current_floor(opening: Dictionary) -> bool:
	var a_id: int = int(opening.get("a", -1))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	if a_id < 0:
		return false
	var a_on_floor: bool = absf(_room_id_floor_level(a_id) - _current_floor_level_m()) < 0.05
	if b_id == OUTSIDE_ID:
		return a_on_floor
	return a_on_floor and absf(_room_id_floor_level(b_id) - _current_floor_level_m()) < 0.05


func _set_tool(tool_id: int) -> void:
	current_tool = tool_id
	pending_door_room_id = -1
	for key in _tool_buttons.keys():
		var button: Button = _tool_buttons[key]
		button.button_pressed = int(key) == current_tool
	_clear_drag()
	_set_status(_tool_hint(current_tool))
	# Resaltar el control de ancho de pasillo solo cuando la herramienta pasillo esta activa
	var corridor_section := get_node_or_null("CanvasLayer/UI/LeftPanel/VBox/CorridorSectionLabel") as Label
	if corridor_section != null:
		corridor_section.add_theme_color_override(
			"font_color",
			Color(1.0, 0.5, 0.0, 1.0) if current_tool == Tool.CORRIDOR_L else Color(0.49, 0.55, 0.60, 0.92)
		)


func _tool_hint(tool_id: int) -> String:
	match tool_id:
		Tool.SELECT:
			return "Seleccionar: clic en habitacion, objeto o apertura. Clic derecho para opciones."
		Tool.ROOM:
			return "Estancia: arrastra para crear una estancia en %s." % _current_floor_name()
		Tool.CORRIDOR_L:
			return "Pasillo: arrastra para crear un pasillo. Diagonal = giro en L. Ajusta ANCHO arriba a la izquierda. (%.2f m actualmente)" % corridor_width_m
		Tool.DOOR:
			return "Puerta: pulsa una pared compartida o exterior en %s para crear puerta." % _current_floor_name()
		Tool.WINDOW:
			return "Ventana: pulsa cerca de una pared exterior en %s." % _current_floor_name()
		Tool.OBJECT:
			return "Objeto: pulsa dentro de una estancia de %s para colocar el combustible elegido." % _current_floor_name()
		Tool.IGNITION:
			return "Ignicion: pulsa un objeto de %s para marcarlo como foco inicial." % _current_floor_name()
		Tool.DELETE:
			return "Borrar: elimina objeto, apertura o estancia bajo el cursor en %s." % _current_floor_name()
	return ""


func _unhandled_input(event: InputEvent) -> void:
	# Zoom con rueda y desplazamiento con botón central
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at_mouse(ZOOM_IN_FACTOR)
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at_mouse(ZOOM_OUT_FACTOR)
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_middle_panning = event.pressed
			last_mouse_pos = event.position
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and is_middle_panning:
		var mouse_delta: Vector2 = event.position - last_mouse_pos
		camera.global_position -= mouse_delta / camera.zoom.x
		last_mouse_pos = event.position
		get_viewport().set_input_as_handled()
		return

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

	# Clic derecho: menú contextual
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if mouse_event.pressed and not _is_pointer_over_ui():
			_show_context_menu(mouse_event.position, _screen_to_m(mouse_event.position))
			get_viewport().set_input_as_handled()
		return

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

	if current_tool == Tool.CORRIDOR_L:
		_create_corridor_from_drag(start_m, end_m)
		queue_redraw()
		return

	if rect.size.x < GRID_M or rect.size.y < GRID_M:
		_set_status("La habitacion es demasiado pequena.")
		queue_redraw()
		return

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


# ---------------------------------------------------------------------------
# Menú contextual (clic derecho)
# ---------------------------------------------------------------------------
func _get_context_menu() -> PopupMenu:
	if _context_menu != null:
		return _context_menu
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	var canvas := get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas != null:
		canvas.add_child(_context_menu)
	else:
		add_child(_context_menu)
	_context_menu.id_pressed.connect(_on_context_id_pressed)
	return _context_menu


func _show_context_menu(screen_pos: Vector2, pos_m: Vector2) -> void:
	_ctx_pos_m = pos_m
	_ctx_room_id = -1
	_ctx_obj_index = -1
	_ctx_opening_index = -1

	var menu := _get_context_menu()
	menu.clear()

	var hit_obj: Dictionary = _find_object_at(pos_m)
	var hit_opening: int = _find_opening_at(pos_m)
	var hit_room: int = _find_room_at(pos_m)

	if not hit_obj.is_empty():
		_ctx_room_id     = int(hit_obj.get("room_id", -1))
		_ctx_obj_index   = int(hit_obj.get("object_index", -1))
		var obj: Dictionary = _get_object(_ctx_room_id, _ctx_obj_index)
		menu.add_item("Editar: %s" % str(obj.get("name", "objeto")), _CTX_EDIT)
		menu.add_item("Duplicar objeto", _CTX_DUPLICATE)
		menu.add_separator()
		menu.add_item("Borrar objeto", _CTX_DELETE)
	elif hit_opening >= 0:
		_ctx_opening_index = hit_opening
		menu.add_item("Editar apertura", _CTX_EDIT)
		menu.add_separator()
		menu.add_item("Borrar apertura", _CTX_DELETE)
	elif hit_room >= 0:
		_ctx_room_id = hit_room
		var room: Dictionary = _get_room(hit_room)
		var rname: String = str(room.get("name", "Habitacion %d" % hit_room))
		menu.add_item("Editar: %s" % rname, _CTX_EDIT)
		menu.add_separator()
		menu.add_item("Anadir puerta aqui", _CTX_ADD_DOOR)
		menu.add_item("Anadir ventana aqui", _CTX_ADD_WIN)
		menu.add_item("Marcar ignicion aqui", _CTX_IGNITE)
		menu.add_separator()
		menu.add_item("Borrar habitacion", _CTX_DELETE)
	else:
		menu.add_item("Deseleccionar todo", _CTX_DESELECT)

	if menu.get_item_count() == 0:
		return
	menu.popup(Rect2i(int(screen_pos.x), int(screen_pos.y), 0, 0))


func _on_context_id_pressed(id: int) -> void:
	match id:
		_CTX_EDIT:
			if _ctx_obj_index >= 0:
				_select_object(_ctx_room_id, _ctx_obj_index)
			elif _ctx_opening_index >= 0:
				_select_opening(_ctx_opening_index)
			elif _ctx_room_id >= 0:
				_select_room(_ctx_room_id)
		_CTX_DELETE:
			if _ctx_obj_index >= 0:
				_select_object(_ctx_room_id, _ctx_obj_index)
				_delete_selected()
			elif _ctx_opening_index >= 0:
				_select_opening(_ctx_opening_index)
				_delete_selected()
			elif _ctx_room_id >= 0:
				_select_room(_ctx_room_id)
				_delete_selected()
		_CTX_ADD_DOOR:
			_set_tool(Tool.DOOR)
			_create_door_at(_ctx_pos_m)
		_CTX_ADD_WIN:
			_set_tool(Tool.WINDOW)
			_create_window_at(_ctx_pos_m)
		_CTX_IGNITE:
			_set_tool(Tool.IGNITION)
			_mark_ignition_at(_ctx_pos_m)
		_CTX_DUPLICATE:
			_duplicate_object_at_context()
		_CTX_DESELECT:
			_clear_selection()
			queue_redraw()


func _duplicate_object_at_context() -> void:
	if _ctx_room_id < 0 or _ctx_obj_index < 0:
		return
	var obj: Dictionary = _get_object(_ctx_room_id, _ctx_obj_index)
	if obj.is_empty():
		return
	var dup: Dictionary = obj.duplicate(true)
	var pos: Vector2 = Serializer.vector2_from_data(dup.get("position_m", Vector2.ZERO))
	dup["position_m"] = {"x": pos.x + 0.5, "y": pos.y + 0.5}
	var room: Dictionary = _get_room(_ctx_room_id)
	var objects: Array = room.get("fuel_objects", [])
	objects.append(dup)
	room["fuel_objects"] = objects
	_select_object(_ctx_room_id, objects.size() - 1)
	_set_status("Objeto duplicado.")
	queue_redraw()


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
		"floor_level_z_m": _current_floor_level_m(),
		"fuel_energy_MJ": 0.0,
		"max_hrr_kw": 0.0,
		"fuel_objects": []
	}
	rooms.append(room)
	rects[str(id)] = Serializer.rect_to_data(rect)
	editor_data["rooms_data"] = rooms
	editor_data["room_rect_m"] = rects
	_update_floor_status()
	return id


func _create_corridor_from_drag(start_m: Vector2, end_m: Vector2) -> void:
	var layout: Dictionary = _build_corridor_layout(start_m, end_m)
	if layout.has("error"):
		_set_status(String(layout["error"]))
		return

	var rects: Array = layout.get("rects", [])
	if rects.is_empty():
		_set_status("El pasillo no tiene tamano suficiente.")
		return

	var base_id: int = _next_room_id()
	var base_name: String = "Pasillo %d" % base_id
	var mode: String = String(layout.get("mode", "straight"))
	if mode == "straight":
		var corridor_id: int = _create_room(Rect2(rects[0]), base_name, "corridor")
		_select_room(corridor_id)
		_set_status("%s creado como tramo recto de %.2f m." % [base_name, float(layout.get("length_m", 0.0))])
		return

	var first_id: int = _create_room(Rect2(rects[0]), "%s tramo A" % base_name, "corridor")
	var second_id: int = _create_room(Rect2(rects[1]), "%s tramo B" % base_name, "corridor")
	var shared: Dictionary = _shared_wall_between(first_id, second_id)
	if not shared.is_empty():
		_add_opening(
			first_id,
			second_id,
			"door",
			String(shared["wall"]),
			float(shared["offset_m"]),
			minf(corridor_width_m, 1.20),
			2.05,
			0.0,
			1.0
		)
	_select_room(first_id)
	_set_status("%s creado en L como tramos %d y %d." % [base_name, first_id, second_id])


func _create_l_corridor(start_m: Vector2, end_m: Vector2) -> void:
	_create_corridor_from_drag(start_m, end_m)


func _build_corridor_layout(start_m: Vector2, end_m: Vector2) -> Dictionary:
	var dx: float = end_m.x - start_m.x
	var dy: float = end_m.y - start_m.y
	var width_m: float = maxf(GRID_M, corridor_width_m)
	var abs_dx: float = absf(dx)
	var abs_dy: float = absf(dy)
	if abs_dx < GRID_M and abs_dy < GRID_M:
		return {"error": "Arrastra para marcar la direccion del pasillo."}

	if abs_dx >= maxf(width_m * 1.25, abs_dy * 2.0) or abs_dy < width_m * 0.60:
		var length_x: float = abs_dx
		if length_x < width_m:
			return {"error": "El tramo recto es demasiado corto para el ancho elegido."}
		var y_center: float = start_m.y
		var x_min: float = minf(start_m.x, end_m.x)
		return {
			"mode": "straight",
			"orientation": "horizontal",
			"rects": [Rect2(Vector2(x_min, y_center - width_m * 0.5), Vector2(length_x, width_m))],
			"length_m": length_x
		}

	if abs_dy >= maxf(width_m * 1.25, abs_dx * 2.0) or abs_dx < width_m * 0.60:
		var length_y: float = abs_dy
		if length_y < width_m:
			return {"error": "El tramo recto es demasiado corto para el ancho elegido."}
		var x_center: float = start_m.x
		var y_min: float = minf(start_m.y, end_m.y)
		return {
			"mode": "straight",
			"orientation": "vertical",
			"rects": [Rect2(Vector2(x_center - width_m * 0.5, y_min), Vector2(width_m, length_y))],
			"length_m": length_y
		}

	if abs_dx < width_m * 1.5 or abs_dy < width_m * 1.5:
		return {"error": "El pasillo en L necesita largo suficiente en ambos brazos."}

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
		return {"error": "El giro del pasillo queda demasiado pequeno."}

	return {
		"mode": "l",
		"orientation": "horizontal_first",
		"rects": [horizontal_rect, vertical_rect],
		"corner_m": Vector2(corner_x, start_m.y),
		"length_m": horizontal_rect.size.x + vertical_rect.size.y
	}


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


func _is_corridor_room(room: Dictionary) -> bool:
	var kind_name: String = String(room.get("kind", "")).strip_edges().to_lower()
	var name_text: String = String(room.get("name", "")).strip_edges().to_lower()
	return kind_name in ["corridor", "pasillo", "hallway", "distribuidor"] or name_text.begins_with("pasillo")


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
		if not _is_room_on_current_floor(room):
			continue
		var room_id: int = int(room.get("id", -1))
		if _get_room_rect(room_id).has_point(pos_m):
			return room_id
	return -1


func _find_object_at(pos_m: Vector2) -> Dictionary:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if not _is_room_on_current_floor(room):
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
		if not _opening_on_current_floor(openings[i]):
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
	_update_floor_status()
	queue_redraw()


func _find_wall_at(pos_m: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = 0.22
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if not _is_room_on_current_floor(room):
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
		if not _is_room_on_current_floor(rooms[i]):
			continue
		var a_id: int = int(rooms[i].get("id", -1))
		for j in range(i + 1, rooms.size()):
			if typeof(rooms[j]) != TYPE_DICTIONARY:
				continue
			if not _is_room_on_current_floor(rooms[j]):
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
		if not _is_room_on_current_floor(room):
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
	if absf(_room_id_floor_level(a_id) - _room_id_floor_level(b_id)) > 0.05:
		return {}
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
	_ensure_floor_data()
	editor_data = Serializer.normalize_editor_data(editor_data)
	_sync_floor_controls()
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
	_ensure_floor_data()
	current_floor_index = clampi(current_floor_index, 0, _get_floors().size() - 1)
	if _stop_time_spin != null:
		_stop_time_spin.value = float(editor_data.get("stop_time_s", 0.0))
	_sync_floor_controls()
	_sync_hvac_option_from_data()
	_clear_selection()
	_set_status("Escenario cargado desde %s." % _path_edit.text.strip_edges())
	queue_redraw()


func _export_runtime_pressed() -> void:
	_ensure_floor_data()
	editor_data = Serializer.normalize_editor_data(editor_data)
	_sync_floor_controls()
	var runtime_template: Dictionary = Serializer.to_runtime_template(editor_data)
	var runtime_rooms: Array = runtime_template.get("rooms_data", [])
	if runtime_rooms.is_empty():
		_set_status("No se exporta: el escenario no tiene habitaciones.")
		return
	if Serializer.save_runtime_template(RUNTIME_EXPORT_PATH, editor_data):
		_set_status("Template runtime exportado en %s." % RUNTIME_EXPORT_PATH)
	else:
		_set_status("No se pudo exportar el template runtime.")


func _delete_selected_room() -> void:
	if selected_room_id >= 0:
		_delete_room(selected_room_id)
	else:
		_set_status("Selecciona primero una habitacion.")


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
		if current_tool == Tool.CORRIDOR_L:
			_draw_corridor_drag_preview()
			return
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


func _draw_corridor_drag_preview() -> void:
	var layout: Dictionary = _build_corridor_layout(drag_start_m, drag_current_m)
	if layout.has("error"):
		draw_line(_m_to_px(drag_start_m), _m_to_px(drag_current_m), Color(1.0, 0.34, 0.24, 0.85), 2.0)
		if ThemeDB.fallback_font != null:
			draw_string(
				ThemeDB.fallback_font,
				_m_to_px(drag_current_m) + Vector2(8.0, -8.0),
				String(layout["error"]),
				HORIZONTAL_ALIGNMENT_LEFT,
				260.0,
				12,
				Color(1.0, 0.70, 0.62, 0.95)
			)
		return

	var rects: Array = layout.get("rects", [])
	for raw_rect in rects:
		var rect := Rect2(raw_rect)
		var rect_px: Rect2 = _rect_to_px(rect)
		draw_rect(rect_px, _corridor_preview_fill, true)
		draw_rect(rect_px, _corridor_preview_outline, false, 2.5)

	var mode: String = String(layout.get("mode", "straight"))
	var start_px: Vector2 = _m_to_px(drag_start_m)
	var end_px: Vector2 = _m_to_px(drag_current_m)
	if mode == "l":
		var corner_m: Vector2 = Vector2(layout.get("corner_m", Vector2(drag_current_m.x, drag_start_m.y)))
		var corner_px: Vector2 = _m_to_px(corner_m)
		draw_line(start_px, corner_px, _corridor_path_color, 3.0)
		draw_line(corner_px, end_px, _corridor_path_color, 3.0)
		draw_circle(corner_px, 4.0, _corridor_path_color)
	else:
		draw_line(start_px, end_px, _corridor_path_color, 3.0)
	draw_circle(start_px, 4.0, Color(0.98, 1.0, 0.80, 0.95))
	draw_circle(end_px, 4.0, Color(0.98, 1.0, 0.80, 0.95))

	if ThemeDB.fallback_font != null:
		var label: String = "Pasillo %s  ancho %.2f m" % ["L" if mode == "l" else "recto", corridor_width_m]
		draw_string(
			ThemeDB.fallback_font,
			end_px + Vector2(8.0, -8.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			220.0,
			12,
			Color(0.72, 1.0, 0.94, 0.96)
		)


func _draw_rooms() -> void:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if not _is_room_on_current_floor(room):
			continue
		var room_id: int = int(room.get("id", -1))
		var rect: Rect2 = _get_room_rect(room_id)
		var rect_px: Rect2 = _rect_to_px(rect)
		var is_corridor: bool = _is_corridor_room(room)
		var fill: Color = _room_selected_fill if room_id == selected_room_id else _room_fill
		var outline: Color = _room_outline
		if is_corridor:
			fill = _corridor_selected_fill if room_id == selected_room_id else _corridor_fill
			outline = _corridor_outline
		draw_rect(rect_px, fill, true)
		draw_rect(rect_px, outline, false, 2.0)
		if is_corridor:
			_draw_corridor_room_guides(rect_px)
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


func _draw_corridor_room_guides(rect_px: Rect2) -> void:
	var center: Vector2 = rect_px.get_center()
	var half_major: float = maxf(rect_px.size.x, rect_px.size.y) * 0.5 - 10.0
	if half_major <= 4.0:
		return
	var a: Vector2
	var b: Vector2
	if rect_px.size.x >= rect_px.size.y:
		a = center - Vector2(half_major, 0.0)
		b = center + Vector2(half_major, 0.0)
	else:
		a = center - Vector2(0.0, half_major)
		b = center + Vector2(0.0, half_major)
	draw_line(a, b, Color(0.80, 1.0, 0.92, 0.36), 2.0)
	draw_circle(a, 2.5, Color(0.80, 1.0, 0.92, 0.50))
	draw_circle(b, 2.5, Color(0.80, 1.0, 0.92, 0.50))


func _draw_openings() -> void:
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var opening: Dictionary = openings[i]
		if not _opening_on_current_floor(opening):
			continue
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
		if not _is_room_on_current_floor(room):
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
	_ensure_floor_data()
	current_floor_index = clampi(current_floor_index, 0, _get_floors().size() - 1)
	if _stop_time_spin != null:
		_stop_time_spin.value = float(editor_data.get("stop_time_s", 0.0))
	_sync_floor_controls()
	_sync_hvac_option_from_data()
	_clear_selection()
	_set_status("Escenario cargado: %s" % path.get_file())
	queue_redraw()


func _run_simulation_pressed() -> void:
	_ensure_floor_data()
	editor_data = Serializer.normalize_editor_data(editor_data)
	_sync_floor_controls()
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
			btn_corridor.text = "Pasillo"
			btn_corridor.custom_minimum_size = Vector2(82.0, 34.0)
			topbar.add_child(btn_corridor)
			if btn_room != null:
				topbar.move_child(btn_corridor, btn_room.get_index() + 1)
	if btn_corridor != null:
		btn_corridor.text = "Pasillo"

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
	_hvac_option = _ui_root.get_node_or_null("LeftPanel/VBox/HVACRow/HVACOption") as OptionButton
	if _hvac_option == null:
		_hvac_option = _ui_root.get_node_or_null("LeftPanel/VBox/HVACOption") as OptionButton
	_stop_time_spin = _ui_root.get_node_or_null("LeftPanel/VBox/StopTimeSpin") as SpinBox
	_corridor_width_spin = _ui_root.get_node_or_null("LeftPanel/VBox/CorridorWidthSpin") as SpinBox
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
	_ensure_floor_controls_in_existing_ui()
	_ensure_corridor_width_control_in_existing_ui()
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
	_connect_button(_ui_root.get_node_or_null("RightPanel/VBox/BtnDeleteRoom") as Button, _delete_selected_room)
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


func _ensure_floor_controls_in_existing_ui() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return

	var section := left_vbox.get_node_or_null("FloorSection") as VBoxContainer
	if section == null:
		section = VBoxContainer.new()
		section.name = "FloorSection"
		section.add_theme_constant_override("separation", 5)
		left_vbox.add_child(section)
		var object_label := left_vbox.get_node_or_null("ObjectLabel") as Label
		if object_label != null:
			left_vbox.move_child(section, object_label.get_index())

	var title := section.get_node_or_null("FloorTitle") as Label
	if title == null:
		title = Label.new()
		title.name = "FloorTitle"
		title.text = "Plantas"
		section.add_child(title)

	var row := section.get_node_or_null("FloorRow") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "FloorRow"
		row.add_theme_constant_override("separation", 4)
		section.add_child(row)

	_floor_option = row.get_node_or_null("FloorOption") as OptionButton
	if _floor_option == null:
		_floor_option = OptionButton.new()
		_floor_option.name = "FloorOption"
		_floor_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_floor_option)
	if not _floor_option.item_selected.is_connected(_on_floor_selected):
		_floor_option.item_selected.connect(_on_floor_selected)

	var add_button := row.get_node_or_null("BtnAddFloor") as Button
	if add_button == null:
		add_button = Button.new()
		add_button.name = "BtnAddFloor"
		add_button.text = "+ Planta"
		add_button.custom_minimum_size = Vector2(86.0, 28.0)
		row.add_child(add_button)
	_connect_button(add_button, _add_floor_pressed)

	var level_row := section.get_node_or_null("FloorLevelRow") as HBoxContainer
	if level_row == null:
		level_row = HBoxContainer.new()
		level_row.name = "FloorLevelRow"
		level_row.add_theme_constant_override("separation", 4)
		section.add_child(level_row)
	var level_label := level_row.get_node_or_null("FloorLevelLabel") as Label
	if level_label == null:
		level_label = Label.new()
		level_label.name = "FloorLevelLabel"
		level_label.text = "Cota (m)"
		level_label.custom_minimum_size.x = 96.0
		level_row.add_child(level_label)
	_floor_level_spin = level_row.get_node_or_null("FloorLevelSpin") as SpinBox
	if _floor_level_spin == null:
		_floor_level_spin = SpinBox.new()
		_floor_level_spin.name = "FloorLevelSpin"
		_floor_level_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_row.add_child(_floor_level_spin)
	_floor_level_spin.min_value = -2.0
	_floor_level_spin.max_value = 30.0
	_floor_level_spin.step = 0.05
	if not _floor_level_spin.value_changed.is_connected(_on_floor_level_changed):
		_floor_level_spin.value_changed.connect(_on_floor_level_changed)

	_floor_status_label = section.get_node_or_null("FloorStatusLabel") as Label
	if _floor_status_label == null:
		_floor_status_label = Label.new()
		_floor_status_label.name = "FloorStatusLabel"
		_floor_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_floor_status_label.add_theme_font_size_override("font_size", 10)
		_floor_status_label.modulate = UI_TEXT_MUTED
		section.add_child(_floor_status_label)

	_sync_floor_controls()


func _populate_object_type_option() -> void:
	if _object_kind_option == null:
		return
	_object_kind_option.clear()
	for kind in ObjectLibraryScript.get_object_kinds():
		_object_kind_option.add_item(kind)


func _on_stop_time_changed(v: float) -> void:
	editor_data["stop_time_s"] = v


func _on_corridor_width_changed(v: float) -> void:
	corridor_width_m = clampf(v, 0.6, 3.0)
	if current_tool == Tool.CORRIDOR_L:
		_set_status(_tool_hint(current_tool))
	queue_redraw()


func _ensure_corridor_width_control_in_existing_ui() -> void:
	var left_vbox := _ui_root.get_node_or_null("LeftPanel/VBox") as VBoxContainer
	if left_vbox == null:
		return

	if _corridor_width_spin == null:
		var row := HBoxContainer.new()
		row.name = "CorridorWidthRow"
		row.add_theme_constant_override("separation", 4)
		var label := Label.new()
		label.text = "Ancho pasillo"
		label.custom_minimum_size.x = 112.0
		row.add_child(label)
		_corridor_width_spin = SpinBox.new()
		_corridor_width_spin.name = "CorridorWidthSpin"
		_corridor_width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_corridor_width_spin)
		left_vbox.add_child(row)
		var path_edit := left_vbox.get_node_or_null("PathEdit") as LineEdit
		if path_edit != null:
			left_vbox.move_child(row, path_edit.get_index())

	_corridor_width_spin.min_value = 0.6
	_corridor_width_spin.max_value = 3.0
	_corridor_width_spin.step = 0.05
	_corridor_width_spin.value = corridor_width_m
	if not _corridor_width_spin.value_changed.is_connected(_on_corridor_width_changed):
		_corridor_width_spin.value_changed.connect(_on_corridor_width_changed)


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

#zoom del mouse, centrado en la posición del cursor
func _zoom_at_mouse(factor: float) -> void:
	var mouse_world_before := camera.get_global_mouse_position()

	var new_zoom_value: float = clamp(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(new_zoom_value, new_zoom_value)

	var mouse_world_after := camera.get_global_mouse_position()
	camera.global_position += mouse_world_before - mouse_world_after

#moviemiento con las flechas
func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	if direction != Vector2.ZERO:
		camera.global_position += direction.normalized() * PAN_SPEED * delta / camera.zoom.x