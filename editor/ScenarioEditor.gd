extends Node2D
class_name ScenarioEditor

enum Tool {
	SELECT,
	EXTERIOR_WALL,
	ROOM,
	CORRIDOR_L,
	STAIRS,
	DOOR,
	HOLE,
	WINDOW,
	OBJECT,
	IGNITION,
	PLAYER_START,
	DELETE,
	DETECTOR,
	VICTIM
}

enum ObjectMouseMode {
	NONE,
	MOVE,
	RESIZE_WIDTH,
	RESIZE_LENGTH,
	ROTATE
}

enum EditorViewMode {
	MODE_2D,
	MODE_3D,
	MODE_FP
}

enum EditorLeftTab {
	TOOLS,
	SELECTION,
	SCENARIO
}

const GRID_M: float = 0.25
const OUTSIDE_ID: int = -1
const DEFAULT_SAVE_PATH: String = "user://editor_scenario.json"
const RUNTIME_EXPORT_PATH: String = "user://last_editor_runtime_template.json"
const RETURN_TO_EDITOR_FLAG_PATH: String = "user://return_to_editor.flag"
const SCENARIOS_RES_PATH: String = "res://scenarios"
const VALIDATION_CASES_PATH: String = "res://sim/validation/cases"
const MAIN_SCENE_PATH: String = "res://scenes/SimulationScene.tscn"
const MAIN_MENU_PATH: String = "res://scenes/MainMenu.tscn"
const DEFAULT_FLOOR_HEIGHT_M: float = 2.90
const EditorGridScript = preload("res://editor/EditorGrid.gd")
const ObjectLibraryScript = preload("res://editor/ObjectLibrary.gd")
const Serializer = preload("res://editor/ScenarioSerializer.gd")
## El panel de propiedades del lado derecho, en su modulo: 53 mandos y el
## reparto de lo que enseña cada uno (E-12).
const PropertyPanelScript = preload("res://editor/EditorPropertyPanel.gd")
## Las reglas de escalera del editor -el vocabulario de giros y lo que se deduce
## de un arrastre- en su modulo (E-12). Las MEDIDAS del tramo no estan ahi: son
## las de view/geometry/StairPlanRules.gd, que ya comparten el mundo FP y el visor
## 3D, y que el editor llevaba copiadas.
const StairPlanRules = preload("res://editor/StairPlanRules.gd")
const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")
const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const Visualizer3DScript = preload("res://view/3d/Visualizer3D.gd")
const FirstPersonControllerScript = preload("res://view/fp/FirstPersonController.gd")
const UILocalizationScript = preload("res://ui/UILocalization.gd")
const EDITOR_LOGO_PATH: String = "res://assets/ui/simufire_logo_editor.png"
const EDITOR_FONT_PATH: String = "res://assets/fonts/bahnschrift.ttf"
const EDITOR_FONT_SIZE_BODY: int = 13
const EDITOR_FONT_SIZE_COMPACT: int = 12
const EDITOR_FONT_SIZE_HEADING: int = 15
const EDITOR_FONT_SIZE_BUTTON: int = 12
const EDITOR_FONT_SIZE_STATUS: int = 13
const EDITOR_HOVER_HELP_DELAY_S: float = 1.0
const EDITOR_HOVER_HELP_MOVE_TOL_PX: float = 4.0
const EDITOR_LEFT_PANEL_WIDTH_PX: float = 276.0
const EDITOR_RIGHT_PANEL_WIDTH_PX: float = 244.0
const EDITOR_SIDE_PANEL_TOP_PX: float = 16.0
const EDITOR_SIDE_PANEL_BOTTOM_PX: float = 76.0
const EDITOR_TOP_BAR_HEIGHT_PX: float = 96.0



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
@export var object_handle_radius_px: float = 6.5
const OBJECT_HANDLE_HIT_RADIUS_M: float = 0.22
const OBJECT_ROTATE_HANDLE_OFFSET_M: float = 0.38
const OBJECT_WALL_SNAP_M: float = GRID_M * 0.75

@export_group("Editor UI")
@export var load_error_dialog_title: String = "Error al cargar escenario"
@export var max_undo_steps: int = 48
@export var pixels_per_meter: float = 64.0
@export_range(0.05, 2.0, 0.05) var hover_help_delay_s: float = EDITOR_HOVER_HELP_DELAY_S
@export_range(0.0, 16.0, 0.5) var hover_help_move_tolerance_px: float = EDITOR_HOVER_HELP_MOVE_TOL_PX
@export_range(240.0, 360.0, 1.0) var editor_left_panel_width_px: float = EDITOR_LEFT_PANEL_WIDTH_PX
@export_range(220.0, 320.0, 1.0) var editor_right_panel_width_px: float = EDITOR_RIGHT_PANEL_WIDTH_PX
@export_range(0.0, 64.0, 1.0) var editor_side_panel_top_px: float = EDITOR_SIDE_PANEL_TOP_PX
@export_range(48.0, 140.0, 1.0) var editor_side_panel_bottom_px: float = EDITOR_SIDE_PANEL_BOTTOM_PX
@export_range(72.0, 160.0, 1.0) var editor_top_bar_height_px: float = EDITOR_TOP_BAR_HEIGHT_PX
@export_range(8, 22, 1) var editor_font_size_body: int = EDITOR_FONT_SIZE_BODY
@export_range(8, 20, 1) var editor_font_size_compact: int = EDITOR_FONT_SIZE_COMPACT
@export_range(10, 26, 1) var editor_font_size_heading: int = EDITOR_FONT_SIZE_HEADING
@export_range(8, 22, 1) var editor_font_size_button: int = EDITOR_FONT_SIZE_BUTTON
@export_range(8, 22, 1) var editor_font_size_status: int = EDITOR_FONT_SIZE_STATUS

@export_group("Object Editing")
@export var object_move_snap_m: float = 0.05
@export var object_resize_snap_m: float = 0.05
@export var object_rotation_snap_deg: float = 15.0
@export var object_axis_snap_threshold_deg: float = 5.0

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
var selected_detector_index: int = -1
var selected_victim_index: int = -1
var selected_player_start_room_id: int = -1
var selected_exterior_wall_index: int = -1
## Lo ultimo copiado con Ctrl+C. Vive en memoria y muere con el editor: pegar
## entre dos sesiones no es lo que hace falta aqui, y un portapapeles en disco
## traeria la pregunta de que hacer cuando el escenario de origen ya no existe.
var _clipboard: Dictionary = {}
var _props: RefCounted = PropertyPanelScript.new()

var is_dragging_room: bool = false
var is_dragging_exterior_wall: bool = false
var drag_start_m: Vector2 = Vector2.ZERO
var drag_current_m: Vector2 = Vector2.ZERO
var pending_door_room_id: int = -1
var corridor_width_m: float = 1.20
var opening_tool_width_m: float = 1.20
var current_floor_index: int = 0

var is_dragging_object: bool = false
var drag_object_cursor_offset_m: Vector2 = Vector2.ZERO
var object_mouse_mode: int = ObjectMouseMode.NONE
var object_drag_start_center_m: Vector2 = Vector2.ZERO
var object_drag_start_size_m: Vector2 = Vector2.ONE
var object_drag_start_rotation_deg: float = 0.0
var is_dragging_room_geometry: bool = false
var room_mouse_mode: int = ObjectMouseMode.NONE
var room_drag_cursor_offset_m: Vector2 = Vector2.ZERO
var room_drag_start_center_m: Vector2 = Vector2.ZERO
var room_drag_start_rect_m: Rect2 = Rect2()
var room_drag_start_rotation_deg: float = 0.0
var _undo_stack: Array[Dictionary] = []
## Pila de rehacer. Con instantaneas completas sale casi gratis: al deshacer, el
## estado actual pasa a esta pila, y rehacer es la misma operacion al reves.
var _redo_stack: Array[Dictionary] = []
## Si el escenario tiene cambios que no estan en disco. No confundir con
## `_editor_runtime_dirty`, que solo dice si hay que refrescar las vistas 3D.
var _unsaved_changes: bool = false

var _ui_root: Control
var _status_label: Label
var _path_edit: LineEdit
var _object_kind_option: OptionButton
var _tool_buttons: Dictionary = {}
var _scenario_option: OptionButton
var _hvac_option: OptionButton
var _interior_lights_check: CheckBox
var _floor_option: OptionButton
var _floor_level_spin: SpinBox
var _floor_status_label: Label
var _floor_delete_button: Button
var _building_type_option: OptionButton
var _apartment_floor_spin: SpinBox
var _element_list: ItemList
var _element_list_sync_in_progress: bool = false
var _editor_view_mode: int = EditorViewMode.MODE_2D
var _editor_mode_buttons: Dictionary = {}
var _editor_world_3d: Node3D
var _editor_building_model: BuildingModel
var _editor_visualizer_3d: Visualizer3D
var _editor_fp_controller: FirstPersonController
var _editor_runtime_dirty: bool = false
var _editor_3d_drag_active: bool = false
var _help_toggle_button: Button
var _help_panel: PanelContainer
var _help_label: Label
var _help_dialog: AcceptDialog
var _help_dialog_label: Label
var _help_dialog_page_label: Label
var _help_page_index: int = 0
var _hover_help_check: CheckBox
var _hover_help_enabled: bool = true
## Con que pestana abre el editor. Abria por Archivo, asi que lo primero que se
## veia al entrar era guardar, cargar y exportar, y las herramientas de dibujo
## -y con ellas las plantas, la lista de elementos y el interruptor de la ayuda
## contextual- quedaban a un clic de distancia sin que nada lo indicara.
var _active_left_tab: int = EditorLeftTab.TOOLS
var _left_tab_buttons: Dictionary = {}
var _hover_help_popup: PanelContainer
var _hover_help_popup_label: Label
var _hover_help_idle_s: float = 0.0
var _hover_help_last_screen_pos: Vector2 = Vector2.ZERO
var _hover_help_world_pos_m: Vector2 = Vector2.ZERO
var _hover_help_text: String = ""
var _hover_help_has_mouse: bool = false
var _scenario_paths: Array[String] = []
var _stop_time_spin: SpinBox
var _corridor_width_spin: SpinBox
var _stair_tool_section: Control
var _stair_tool_turn_option: OptionButton
var _opening_tool_section: Control
var _opening_tool_width_spin: SpinBox
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _load_error_helper: EditorLoadErrorDialog = EditorLoadErrorDialog.new()
var _template_builder = BuildingTemplateScript.new()
# Propiedades de objeto seleccionado

# Propiedades de apertura seleccionada
# Propiedades de detector seleccionado
# Propiedades de victima seleccionada

@export var _room_fill: Color = Color(0.05, 0.07, 0.09, 0.72)
@export var _room_selected_fill: Color = Color(0.08, 0.14, 0.16, 0.84)
@export var _room_outline: Color = Color(0.28, 0.32, 0.35, 0.95)
@export var _lower_floor_ghost_fill: Color = Color(0.55, 0.64, 0.68, 0.14)
@export var _lower_floor_ghost_outline: Color = Color(0.70, 0.82, 0.88, 0.28)
@export var _exterior_wall_color: Color = Color(1.00, 0.84, 0.28, 0.98)
@export var _exterior_wall_selected_color: Color = Color(1.00, 1.00, 0.70, 1.0)
@export var _corridor_fill: Color = Color(0.03, 0.10, 0.11, 0.76)
@export var _corridor_selected_fill: Color = Color(0.04, 0.18, 0.19, 0.88)
@export var _corridor_outline: Color = UI_BLUE
@export var _corridor_preview_fill: Color = Color(0.00, 0.70, 0.88, 0.22)
@export var _corridor_preview_outline: Color = Color(0.00, 0.84, 1.00, 0.92)
@export var _corridor_path_color: Color = UI_YELLOW
@export var _door_color: Color = UI_GREEN
@export var _window_color: Color = UI_BLUE
@export var _object_color: Color = Color(1.00, 0.25, 0.00, 0.86)
@export var _object_selected_color: Color = UI_YELLOW
@export var _ignition_color: Color = Color(1.00, 0.08, 0.02, 0.98)
@export var _detector_smoke_color: Color = Color(0.20, 0.65, 1.00, 0.95)
@export var _detector_heat_color: Color = Color(1.00, 0.45, 0.10, 0.95)
@export var _detector_co_color: Color = Color(0.95, 0.92, 0.20, 0.95)
@export var _victim_color: Color = Color(0.25, 0.95, 0.45, 0.95)
@export var _player_start_color: Color = Color(0.58, 0.88, 1.0, 0.96)

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
const _CTX_ADD_HOLE  := 8
const _CTX_MARK_EXTERIOR := 9
const _CTX_SET_PLAYER_START := 10
const _CTX_PASTE     := 11
# ── Tolerancias para detección de paredes adyacentes / solapadas ──────────
const _CONN_GAP_TOL: float = 0.30       # brecha máxima entre paredes (m)
const _CONN_OVERLAP_FRAC: float = 0.85  # solapamiento máximo (fracción de dim menor)
const _CONN_MIN_SHARED: float = 0.20    # longitud mínima de pared compartida (m)
const _CONN_CLICK_TOL: float = 0.40     # radio de clic para detectar pared (m)

var _context_menu: PopupMenu = null
var _ctx_pos_m: Vector2 = Vector2.ZERO
var _ctx_room_id: int = -1
var _ctx_obj_index: int = -1
var _ctx_opening_index: int = -1
var _ctx_exterior_wall_index: int = -1

func _ready() -> void:
	UILocalizationScript.ensure_loaded()
	_create_empty_scenario()
	_load_returned_runtime_if_requested()
	_setup_grid()
	if not _bind_existing_ui():
		push_error("ScenarioEditor: ScenarioEditorScene.tscn incompleta — la escena es la fuente de verdad de la UI del editor")
		return
	_bind_editor_mode_controls()
	_ensure_file_dialogs()
	_apply_editor_visual_style()
	_ensure_floor_data()
	_sync_floor_controls()
	_ensure_editor_3d_nodes()
	_set_tool(Tool.SELECT)
	_set_editor_view_mode(EditorViewMode.MODE_2D, true)
	queue_redraw()


func _load_returned_runtime_if_requested() -> void:
	if not FileAccess.file_exists(RETURN_TO_EDITOR_FLAG_PATH):
		return
	var user_dir := DirAccess.open("user://")
	if user_dir != null:
		user_dir.remove("return_to_editor.flag")
	if not FileAccess.file_exists(RUNTIME_EXPORT_PATH):
		return
	var loaded: Dictionary = Serializer.load_scenario(RUNTIME_EXPORT_PATH)
	if loaded.is_empty():
		return
	editor_data = Serializer.normalize_editor_data(loaded)


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

	grid.set("pixels_per_meter", pixels_per_meter)
	grid.set("grid_m", GRID_M)
	grid.z_index = -100
	grid.set("background_color", UI_BG)
	grid.set("minor_color", Color(0.05, 0.08, 0.10, 0.62))
	grid.set("major_color", Color(0.13, 0.17, 0.20, 0.80))
	grid.set("axis_color", Color(1.00, 0.25, 0.00, 0.50))


func _ui_text(key: String, fallback: String) -> String:
	return UILocalizationScript.t(key, fallback)

func _apply_editor_visual_style() -> void:
	RenderingServer.set_default_clear_color(UI_BG)
	if _ui_root == null:
		return
	_editor_font = _make_system_font(PackedStringArray(["Roboto Condensed", "Bahnschrift", "Segoe UI", "Arial Narrow", "Arial"]), 500, 92)
	_editor_title_font = _make_system_font(PackedStringArray(["Bahnschrift SemiBold Condensed", "Agency FB", "Roboto Condensed", "Arial Narrow", "Arial"]), 700, 82)
	# El tema viene de la escena (ui/SimuFireTheme.tres). Duplicar antes de
	# aplicar los tamanos de fuente del editor: mutar el .tres compartido
	# contaminaria el menu y el HUD en la misma sesion.
	if _ui_root.theme == null:
		push_error("ScenarioEditor: la escena no asigna theme (ui/SimuFireTheme.tres)")
		_editor_theme = Theme.new()
	else:
		_editor_theme = _ui_root.theme.duplicate(true)
	_ui_root.theme = _editor_theme
	_apply_editor_theme_font_sizes(_editor_theme)
	_normalize_editor_panel_readability()
	_ensure_editor_branding()
	_ensure_left_editor_tabs()
	_sync_left_editor_tab_visibility()
	_ensure_hover_help_popup()
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




func _apply_editor_theme_font_sizes(theme: Theme) -> void:
	if theme == null:
		return
	theme.set_font_size("font_size", "Label", editor_font_size_body)
	theme.set_font_size("font_size", "Button", editor_font_size_button)
	theme.set_font_size("font_size", "LineEdit", editor_font_size_body)
	theme.set_font_size("font_size", "OptionButton", editor_font_size_button)
	theme.set_font_size("font_size", "SpinBox", editor_font_size_body)
	theme.set_font_size("font_size", "CheckBox", editor_font_size_body)
	theme.set_font_size("font_size", "ItemList", editor_font_size_compact)
	theme.set_font_size("font_size", "PopupMenu", editor_font_size_body)


func _normalize_editor_panel_readability() -> void:
	var left_width_px: float = maxf(240.0, editor_left_panel_width_px)
	var right_width_px: float = maxf(220.0, editor_right_panel_width_px)
	var left_panel := _ui_root.get_node_or_null("LeftPanel") as Control
	if left_panel != null:
		left_panel.scale = Vector2.ONE
		left_panel.offset_top = editor_side_panel_top_px
		left_panel.offset_right = left_width_px
		left_panel.offset_bottom = -editor_side_panel_bottom_px
		left_panel.custom_minimum_size.x = left_width_px
		var left_vbox := _find_left_vbox()
		if left_vbox != null:
			left_vbox.add_theme_constant_override("separation", 5)
	var right_panel := _ui_root.get_node_or_null("RightPanel") as Control
	if right_panel != null:
		right_panel.scale = Vector2.ONE
		right_panel.offset_left = -right_width_px
		right_panel.offset_right = -12.0
		right_panel.offset_top = editor_side_panel_top_px
		right_panel.offset_bottom = -editor_side_panel_bottom_px
		right_panel.custom_minimum_size.x = right_width_px
		var right_vbox := right_panel.get_node_or_null("VBox") as VBoxContainer
		if right_vbox != null:
			right_vbox.add_theme_constant_override("separation", 4)
	# El layout base del TopBar (offsets, columnas, tamano de botones) vive en
	# ScenarioEditorScene.tscn; aqui solo se aplica la altura export-driven.
	var top_bar := _ui_root.get_node_or_null("TopBar") as Control
	if top_bar != null:
		top_bar.offset_bottom = editor_top_bar_height_px
		top_bar.custom_minimum_size.y = editor_top_bar_height_px - 8.0


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


func _ensure_editor_branding() -> void:
	# BrandHeader/Logo/EditorModeLabel viven en ScenarioEditorScene.tscn;
	# aqui solo se aplican fuente y color dinamicos.
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	var brand := left_vbox.get_node_or_null("BrandHeader") as VBoxContainer
	if brand == null:
		push_error("ScenarioEditor: falta BrandHeader en ScenarioEditorScene.tscn")
		return
	var mode_label := brand.get_node_or_null("EditorModeLabel") as Label
	if mode_label != null:
		mode_label.add_theme_font_override("font", _editor_title_font)
		mode_label.add_theme_font_size_override("font_size", editor_font_size_body)
		mode_label.add_theme_color_override("font_color", UI_TEXT_MUTED)


func _ensure_left_editor_tabs() -> void:
	# EditorTabsRow y sus botones viven en ScenarioEditorScene.tscn; aqui
	# solo se conectan y se sincroniza el estado.
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	var row := left_vbox.get_node_or_null("EditorTabsRow") as HBoxContainer
	if row == null:
		push_error("ScenarioEditor: falta EditorTabsRow en ScenarioEditorScene.tscn")
		return
	_left_tab_buttons.clear()
	_ensure_left_tab_button(row, "TabTools", EditorLeftTab.TOOLS)
	_ensure_left_tab_button(row, "TabSelection", EditorLeftTab.SELECTION)
	_ensure_left_tab_button(row, "TabScenario", EditorLeftTab.SCENARIO)
	var old_templates_tab := row.get_node_or_null("TabTemplates") as Button
	if old_templates_tab != null:
		old_templates_tab.visible = false
	_sync_left_tab_buttons()


func _ensure_left_tab_button(parent: Control, button_name: String, tab_id: int) -> Button:
	var button := parent.get_node_or_null(button_name) as Button
	if button == null:
		push_error("ScenarioEditor: falta %s en EditorTabsRow (ScenarioEditorScene.tscn)" % button_name)
		return null
	button.tooltip_text = _left_tab_tooltip(tab_id)
	var callback := Callable(self, "_set_left_editor_tab").bind(tab_id)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	_left_tab_buttons[tab_id] = button
	return button


func _set_left_editor_tab(tab_id: int) -> void:
	_active_left_tab = tab_id
	_sync_left_tab_buttons()
	_sync_left_editor_tab_visibility()


func _sync_left_tab_buttons() -> void:
	for key in _left_tab_buttons.keys():
		var button := _left_tab_buttons[key] as Button
		if button != null:
			button.button_pressed = int(key) == _active_left_tab
			button.tooltip_text = _left_tab_tooltip(int(key))


func _left_tab_tooltip(tab_id: int) -> String:
	match tab_id:
		EditorLeftTab.TOOLS:
			return "Dibujo: herramientas de creación y edición sobre el plano."
		EditorLeftTab.SELECTION:
			return "Lista: selecciona salas, objetos, aperturas, detectores, víctimas e inicio FP cuando se solapan."
		EditorLeftTab.SCENARIO:
			return "Archivo: guardar, cargar, plantillas, tiempo, luces, tipo de edificio y HVAC."
	return ""


func _sync_left_editor_tab_visibility() -> void:
	if _ui_root == null:
		return
	var tools_visible: bool = _active_left_tab == EditorLeftTab.TOOLS
	var selection_visible: bool = _active_left_tab == EditorLeftTab.SELECTION
	var scenario_visible: bool = _active_left_tab == EditorLeftTab.SCENARIO

	_set_left_paths_visible([
		"ViewModeRow",
		"FloorSection",
		"ObjectLabel",
		"ObjectToolLabel",
		"ObjectToolSection",
		"ObjectTypeOption",
		"CorridorSectionLabel",
		"CorridorWidthRow",
		"CorridorWidthSpin",
		"OpeningToolSection",
		"HoverHelpRow"
	], tools_visible)
	_set_left_paths_visible([
		"ElementListTitle",
		"ElementList"
	], selection_visible)
	_set_left_paths_visible([
		"PathEdit",
		"BtnSave",
		"BtnLoad",
		"BtnExportRuntime",
		"StopTimeLabel",
		"StopTimeSpin",
		"LightingRow",
		"BuildingTypeRow",
		"ApartmentFloorRow",
		"ScenarioLabel",
		"HVACRow",
		"ScenarioOption",
		"BtnLoadScenario"
	], scenario_visible)
	_set_left_paths_visible(["SeparatorA", "SeparatorB"], false)
	if _status_label != null:
		_status_label.visible = true
		_status_label.custom_minimum_size = Vector2(0.0, 54.0)
	_sync_tool_option_visibility()


func _set_left_paths_visible(paths: Array, visible: bool) -> void:
	for raw_path in paths:
		_set_left_path_visible(String(raw_path), visible)


func _set_left_path_visible(path: String, visible: bool) -> void:
	var node := _get_left_node(path) as Control
	if node != null:
		node.visible = visible


func _ensure_hover_help_popup() -> void:
	# El popup vive en ScenarioEditorScene.tscn (estilo/tamano editables);
	# aqui solo se enlaza y se aplica el tamano de fuente export-driven.
	if _ui_root == null or _hover_help_popup != null:
		return
	_hover_help_popup = _ui_root.get_node_or_null("HoverHelpPopup") as PanelContainer
	if _hover_help_popup == null:
		push_error("ScenarioEditor: falta HoverHelpPopup en ScenarioEditorScene.tscn")
		return
	# La escena se guarda visible para editarla; oculto hasta hacer hover.
	_hover_help_popup.visible = false
	_hover_help_popup_label = _hover_help_popup.get_node_or_null("Margin/HoverHelpLabel") as Label
	if _hover_help_popup_label != null:
		_hover_help_popup_label.add_theme_font_size_override("font_size", editor_font_size_body)


func _show_hover_help_popup(text: String) -> void:
	_ensure_hover_help_popup()
	if _hover_help_popup == null or _hover_help_popup_label == null:
		return
	if text == "":
		_hover_help_popup.visible = false
		return
	_hover_help_popup_label.text = text
	var viewport_size: Vector2 = get_viewport_rect().size
	var popup_size: Vector2 = Vector2(250.0, 42.0)
	var pos: Vector2 = _hover_help_last_screen_pos + Vector2(16.0, -46.0)
	pos.x = clampf(pos.x, 12.0, maxf(12.0, viewport_size.x - popup_size.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, viewport_size.y - popup_size.y - 12.0))
	_hover_help_popup.position = pos
	_hover_help_popup.visible = true
	_hover_help_popup.move_to_front()


func _bind_editor_mode_controls() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	var row := _scene_control(left_vbox, "ViewModeRow") as HBoxContainer
	if row == null:
		return
	_ensure_editor_mode_button(row, "BtnViewMode2D", EditorViewMode.MODE_2D)
	_ensure_editor_mode_button(row, "BtnViewMode3D", EditorViewMode.MODE_3D)
	_ensure_editor_mode_button(row, "BtnViewModeFP", EditorViewMode.MODE_FP)
	_update_editor_mode_buttons()


func _ensure_editor_mode_button(parent: Control, button_name: String, mode: int) -> Button:
	var button := parent.get_node_or_null(button_name) as Button
	if button == null:
		push_error("ScenarioEditor: falta %s en ViewModeRow (ScenarioEditorScene.tscn)" % button_name)
		return null
	button.tooltip_text = _editor_view_mode_tooltip(mode)
	var callback := Callable(self, "_set_editor_view_mode").bind(mode)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	_editor_mode_buttons[mode] = button
	return button


func _update_editor_mode_buttons() -> void:
	for key in _editor_mode_buttons.keys():
		var button := _editor_mode_buttons[key] as Button
		if button != null:
			button.button_pressed = int(key) == _editor_view_mode
			button.tooltip_text = _editor_view_mode_tooltip(int(key))


func _editor_view_mode_tooltip(mode: int) -> String:
	match mode:
		EditorViewMode.MODE_2D:
			return "Vista 2D: edición precisa de geometría, aperturas, objetos y planta."
		EditorViewMode.MODE_3D:
			return "Vista 3D: inspección orbital y edición de elementos simples."
		EditorViewMode.MODE_FP:
			return "Vista FP: inspección en primera persona desde el marcador Inicio FP."
	return ""


func _ensure_editor_3d_nodes() -> void:
	_editor_world_3d = get_node_or_null("EditorWorld3D") as Node3D
	if _editor_world_3d == null:
		_editor_world_3d = Node3D.new()
		_editor_world_3d.name = "EditorWorld3D"
		_editor_world_3d.visible = false
		add_child(_editor_world_3d)
	else:
		_editor_world_3d.visible = false

	_editor_building_model = _editor_world_3d.get_node_or_null("EditorBuildingModel") as BuildingModel
	if _editor_building_model == null:
		_editor_building_model = BuildingModelScript.new() as BuildingModel
		_editor_building_model.name = "EditorBuildingModel"
		_editor_world_3d.add_child(_editor_building_model)

	_editor_visualizer_3d = _editor_world_3d.get_node_or_null("Visualizer3D") as Visualizer3D
	if _editor_visualizer_3d == null:
		_editor_visualizer_3d = Visualizer3DScript.new() as Visualizer3D
		_editor_visualizer_3d.name = "Visualizer3D"
		_editor_visualizer_3d.building_path = NodePath("../EditorBuildingModel")
		_add_editor_visualizer_children(_editor_visualizer_3d)
		_editor_world_3d.add_child(_editor_visualizer_3d)
	else:
		_editor_visualizer_3d.building_path = NodePath("../EditorBuildingModel")
	if _editor_visualizer_3d != null:
		_editor_visualizer_3d.show_legend = false
		if not _editor_visualizer_3d.room_clicked.is_connected(_on_editor_3d_room_clicked):
			_editor_visualizer_3d.room_clicked.connect(_on_editor_3d_room_clicked)
		if not _editor_visualizer_3d.opening_clicked.is_connected(_on_editor_3d_opening_clicked):
			_editor_visualizer_3d.opening_clicked.connect(_on_editor_3d_opening_clicked)
		if not _editor_visualizer_3d.object_clicked.is_connected(_on_editor_3d_object_clicked):
			_editor_visualizer_3d.object_clicked.connect(_on_editor_3d_object_clicked)
		if not _editor_visualizer_3d.detector_clicked.is_connected(_on_editor_3d_detector_clicked):
			_editor_visualizer_3d.detector_clicked.connect(_on_editor_3d_detector_clicked)
		if not _editor_visualizer_3d.victim_clicked.is_connected(_on_editor_3d_victim_clicked):
			_editor_visualizer_3d.victim_clicked.connect(_on_editor_3d_victim_clicked)
		if not _editor_visualizer_3d.player_start_clicked.is_connected(_on_editor_3d_player_start_clicked):
			_editor_visualizer_3d.player_start_clicked.connect(_on_editor_3d_player_start_clicked)
		if not _editor_visualizer_3d.floor_clicked.is_connected(_on_editor_3d_floor_clicked):
			_editor_visualizer_3d.floor_clicked.connect(_on_editor_3d_floor_clicked)
		if not _editor_visualizer_3d.element_drag_started.is_connected(_on_editor_3d_element_drag_started):
			_editor_visualizer_3d.element_drag_started.connect(_on_editor_3d_element_drag_started)
		if not _editor_visualizer_3d.object_dragged.is_connected(_on_editor_3d_object_dragged):
			_editor_visualizer_3d.object_dragged.connect(_on_editor_3d_object_dragged)
		if not _editor_visualizer_3d.detector_dragged.is_connected(_on_editor_3d_detector_dragged):
			_editor_visualizer_3d.detector_dragged.connect(_on_editor_3d_detector_dragged)
		if not _editor_visualizer_3d.victim_dragged.is_connected(_on_editor_3d_victim_dragged):
			_editor_visualizer_3d.victim_dragged.connect(_on_editor_3d_victim_dragged)
		if not _editor_visualizer_3d.player_start_dragged.is_connected(_on_editor_3d_player_start_dragged):
			_editor_visualizer_3d.player_start_dragged.connect(_on_editor_3d_player_start_dragged)
		if not _editor_visualizer_3d.element_drag_ended.is_connected(_on_editor_3d_element_drag_ended):
			_editor_visualizer_3d.element_drag_ended.connect(_on_editor_3d_element_drag_ended)

	_editor_fp_controller = _editor_world_3d.get_node_or_null("FirstPersonController") as FirstPersonController
	if _editor_fp_controller == null:
		_editor_fp_controller = FirstPersonControllerScript.new() as FirstPersonController
		_editor_fp_controller.name = "FirstPersonController"
		_editor_world_3d.add_child(_editor_fp_controller)
	if _editor_fp_controller != null and not _editor_fp_controller.exit_requested.is_connected(_on_editor_fp_exit_requested):
		_editor_fp_controller.exit_requested.connect(_on_editor_fp_exit_requested)

	_sync_editor_runtime_views()
	if _editor_visualizer_3d != null:
		_editor_visualizer_3d.set_active(false)
	if _editor_fp_controller != null:
		_editor_fp_controller.set_active(false)
	_editor_world_3d.visible = false


func _add_editor_visualizer_children(visualizer: Node3D) -> void:
	for node_name in ["Rooms", "Openings", "Atmosphere", "Labels"]:
		if visualizer.get_node_or_null(node_name) == null:
			var container := Node3D.new()
			container.name = node_name
			visualizer.add_child(container)
	var camera_rig := visualizer.get_node_or_null("CameraRig") as Node3D
	if camera_rig == null:
		camera_rig = Node3D.new()
		camera_rig.name = "CameraRig"
		visualizer.add_child(camera_rig)
	var camera_3d := camera_rig.get_node_or_null("Camera3D") as Camera3D
	if camera_3d == null:
		camera_3d = Camera3D.new()
		camera_3d.name = "Camera3D"
		camera_3d.fov = 45.0
		camera_3d.position = Vector3(0.0, 0.0, 13.0)
		camera_rig.add_child(camera_3d)
	if visualizer.get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
		sun.light_energy = 1.8
		visualizer.add_child(sun)
	if visualizer.get_node_or_null("FillLight") == null:
		var fill := OmniLight3D.new()
		fill.name = "FillLight"
		fill.position = Vector3(0.0, 5.0, 0.0)
		fill.light_energy = 0.35
		fill.omni_range = 18.0
		visualizer.add_child(fill)


func _sync_editor_runtime_views() -> void:
	if _editor_building_model == null:
		return
	_lock_all_object_visual_poses()
	var runtime_template: Dictionary = Serializer.to_runtime_template(editor_data)
	_editor_building_model.load_template_data(runtime_template, true)
	if _editor_visualizer_3d != null:
		_editor_visualizer_3d.building = _editor_building_model
		_editor_visualizer_3d.rebuild_from_building()
		_editor_visualizer_3d.set_state({})
	if _editor_fp_controller != null:
		_editor_fp_controller.setup(_editor_building_model)
		_editor_fp_controller.set_state({})
	_editor_runtime_dirty = false
	_sync_editor_visualizer_selection()


func _mark_editor_runtime_dirty() -> void:
	_editor_runtime_dirty = true


func _lock_all_object_visual_poses() -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	var changed: bool = false
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		var room_changed: bool = false
		for j in range(objects.size()):
			if typeof(objects[j]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[j]
			if bool(obj.get("visual_pose_locked", false)):
				continue
			obj["visual_pose_locked"] = true
			objects[j] = obj
			room_changed = true
		if room_changed:
			room["fuel_objects"] = objects
			rooms[i] = room
			changed = true
	if changed:
		editor_data["rooms_data"] = rooms


func _refresh_editor_runtime_if_needed() -> void:
	if not _editor_runtime_dirty:
		return
	if _editor_3d_drag_active:
		return
	if _editor_view_mode != EditorViewMode.MODE_3D and _editor_view_mode != EditorViewMode.MODE_FP:
		return
	_sync_editor_runtime_views()


func _sync_editor_visualizer_selection() -> void:
	if _editor_visualizer_3d == null:
		return
	if selected_room_id >= 0:
		_editor_visualizer_3d.select_room(selected_room_id)
	elif selected_opening_index >= 0:
		_editor_visualizer_3d.select_opening(selected_opening_index)
	elif selected_object_room_id >= 0 and selected_object_index >= 0:
		var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
		_editor_visualizer_3d.select_object(selected_object_room_id, String(obj.get("id", "")))
	elif selected_detector_index >= 0:
		var detector_id: String = _detector_id_for_index(selected_detector_index)
		_editor_visualizer_3d.select_detector(detector_id)
	elif selected_victim_index >= 0:
		var victim_id: String = _victim_id_for_index(selected_victim_index)
		_editor_visualizer_3d.select_victim(victim_id)
	elif selected_player_start_room_id >= 0 and _editor_visualizer_3d.has_method("select_player_start"):
		_editor_visualizer_3d.select_player_start()
	else:
		_editor_visualizer_3d.clear_selection()


func _set_editor_view_mode(mode: int, force: bool = false) -> void:
	if not force and _editor_view_mode == mode:
		return
	if mode == EditorViewMode.MODE_3D or mode == EditorViewMode.MODE_FP:
		_ensure_editor_3d_nodes()
		_sync_editor_runtime_views()
	_clear_drag()
	_editor_3d_drag_active = false
	is_middle_panning = false
	_editor_view_mode = mode
	if not _tool_available_in_current_mode(current_tool):
		current_tool = Tool.SELECT
	var use_2d: bool = _editor_view_mode == EditorViewMode.MODE_2D
	var use_3d: bool = _editor_view_mode == EditorViewMode.MODE_3D
	var use_fp: bool = _editor_view_mode == EditorViewMode.MODE_FP
	var world_2d := get_node_or_null("World") as CanvasItem
	if world_2d != null:
		world_2d.visible = use_2d
	if camera != null:
		camera.enabled = use_2d
	if _editor_world_3d != null:
		_editor_world_3d.visible = use_3d or use_fp
	if _editor_visualizer_3d != null:
		_editor_visualizer_3d.set_active(use_3d or use_fp, use_3d, use_3d, use_fp)
		_update_editor_visualizer_drag_mode()
	if _editor_fp_controller != null:
		_editor_fp_controller.set_active(use_fp)
	_update_editor_mode_buttons()
	_update_tool_buttons_enabled()
	_sync_tool_option_visibility()
	if use_2d:
		_set_status("Modo 2D: editor clásico activo.")
	elif use_3d:
		_set_status("Modo 3D: edita aberturas y elementos simples. La geometría de salas sigue en 2D.")
	else:
		_set_status("Modo FP: inspeccion activa. Pulsa Esc para volver a 2D.")
	queue_redraw()


func _update_tool_buttons_enabled() -> void:
	for tool_id in _tool_buttons.keys():
		var button := _tool_buttons[tool_id] as Button
		if button is Button:
			button.disabled = not _tool_available_in_current_mode(int(tool_id))
	_sync_tool_button_states()


func _sync_tool_button_states() -> void:
	for key in _tool_buttons.keys():
		var button := _tool_buttons[key] as Button
		if button != null:
			button.button_pressed = int(key) == current_tool
			button.tooltip_text = _tool_tooltip(int(key))


func _tool_available_in_current_mode(tool_id: int) -> bool:
	if _editor_view_mode == EditorViewMode.MODE_2D:
		return true
	if _editor_view_mode == EditorViewMode.MODE_3D:
		return _is_3d_simple_tool(tool_id)
	return false


func _is_3d_simple_tool(tool_id: int) -> bool:
	return tool_id in [
		Tool.SELECT,
		Tool.DOOR,
		Tool.HOLE,
		Tool.WINDOW,
		Tool.OBJECT,
		Tool.IGNITION,
		Tool.PLAYER_START,
		Tool.DELETE,
		Tool.DETECTOR,
		Tool.VICTIM
	]


## Nombre de la tecla que activa una herramienta. Sale de TOOL_SHORTCUTS, la
## misma tabla que escucha el teclado, para que no puedan discrepar.
func _tool_shortcut_label(tool_id: int) -> String:
	for keycode in TOOL_SHORTCUTS:
		if int(TOOL_SHORTCUTS[keycode]) == tool_id:
			return OS.get_keycode_string(int(keycode))
	return ""


func _tool_tooltip(tool_id: int) -> String:
	var text: String = _tool_hint(tool_id)
	if text == "":
		return ""
	# Un atajo que no se anuncia en ningun sitio es un atajo que no existe: la
	# tecla se escribe en el tooltip de la propia herramienta.
	var key_label: String = _tool_shortcut_label(tool_id)
	if key_label != "":
		text = "%s  [tecla %s]" % [text, key_label]
	if not _tool_available_in_current_mode(tool_id):
		return "%s\nNo disponible en el modo actual." % text
	return text


func _update_editor_visualizer_drag_mode() -> void:
	if _editor_visualizer_3d != null and _editor_visualizer_3d.has_method("set_element_drag_enabled"):
		_editor_visualizer_3d.set_element_drag_enabled(_editor_view_mode == EditorViewMode.MODE_3D and current_tool == Tool.SELECT)


func _on_editor_fp_exit_requested() -> void:
	_set_editor_view_mode(EditorViewMode.MODE_2D)


func _on_editor_3d_room_clicked(room_id: int) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool == Tool.DELETE:
		_set_status("El borrado de geometría de salas se mantiene en 2D.")
		return
	if current_tool != Tool.SELECT:
		return
	if room_id >= 0:
		_select_room(room_id)
	else:
		_clear_selection()
		_set_status("Sin selección.")


func _on_editor_3d_opening_clicked(opening_index: int, _screen_pos: Vector2) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool == Tool.DELETE:
		if _delete_opening(opening_index):
			_sync_editor_3d_after_direct_edit()
		return
	if current_tool != Tool.SELECT:
		return
	var openings: Array = editor_data.get("openings_data", [])
	if opening_index < 0 or opening_index >= openings.size():
		return
	_select_opening(opening_index)


func _on_editor_3d_object_clicked(room_id: int, object_id: String) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	var object_index: int = _object_index_for_id(room_id, object_id)
	if object_index < 0:
		return
	match current_tool:
		Tool.DELETE:
			_delete_object(room_id, object_index)
			_sync_editor_3d_after_direct_edit()
		Tool.IGNITION:
			_mark_object_as_ignition(room_id, object_index)
			_sync_editor_3d_after_direct_edit()
		Tool.SELECT:
			_select_object(room_id, object_index)


func _on_editor_3d_detector_clicked(detector_id: String) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	var detector_index: int = _detector_index_for_id(detector_id)
	if detector_index < 0:
		return
	if current_tool == Tool.DELETE:
		_select_detector(detector_index)
		_delete_selected()
		_sync_editor_3d_after_direct_edit()
	elif current_tool == Tool.SELECT:
		_select_detector(detector_index)


func _on_editor_3d_victim_clicked(victim_id: String) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	var victim_index: int = _victim_index_for_id(victim_id)
	if victim_index < 0:
		return
	if current_tool == Tool.DELETE:
		_select_victim(victim_index)
		_delete_selected()
		_sync_editor_3d_after_direct_edit()
	elif current_tool == Tool.SELECT:
		_select_victim(victim_index)


func _on_editor_3d_player_start_clicked(room_id: int) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool == Tool.DELETE:
		_select_player_start(room_id)
		_delete_selected()
		_sync_editor_3d_after_direct_edit()
	elif current_tool == Tool.SELECT:
		_select_player_start(room_id)


func _on_editor_3d_floor_clicked(room_id: int, floor_pos_m: Vector2) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if room_id < 0:
		return
	match current_tool:
		Tool.DOOR:
			_create_door_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.HOLE:
			_create_hole_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.WINDOW:
			_create_window_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.OBJECT:
			_create_object_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.DETECTOR:
			_create_detector_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.VICTIM:
			_create_victim_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.PLAYER_START:
			_create_player_start_at(floor_pos_m)
			_sync_editor_3d_after_direct_edit()
		Tool.IGNITION:
			_set_status("Ignición 3D: pulsa directamente sobre un objeto combustible.")
		Tool.DELETE:
			_set_status("Borrado 3D: pulsa una apertura, objeto, detector, víctima o inicio FP.")


func _on_editor_3d_element_drag_started(kind: String) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool != Tool.SELECT:
		return
	_editor_3d_drag_active = true
	_push_undo_snapshot("move_3d_" + kind)


func _on_editor_3d_object_dragged(room_id: int, object_id: String, floor_pos_m: Vector2) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool != Tool.SELECT:
		return
	var object_index: int = _object_index_for_id(room_id, object_id)
	if object_index < 0:
		return
	_move_object_center_to(room_id, object_index, floor_pos_m, true)
	selected_object_room_id = room_id
	selected_object_index = object_index
	var obj: Dictionary = _get_object(room_id, object_index)
	_sync_object_property_fields(obj)
	queue_redraw()


func _on_editor_3d_detector_dragged(detector_id: String, floor_pos_m: Vector2) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool != Tool.SELECT:
		return
	var detector_index: int = _detector_index_for_id(detector_id)
	if detector_index < 0:
		return
	_move_detector_to(detector_index, floor_pos_m)
	selected_detector_index = detector_index
	_sync_detector_property_fields(Dictionary(Array(editor_data.get("detectors", []))[detector_index]))
	queue_redraw()


func _on_editor_3d_victim_dragged(victim_id: String, floor_pos_m: Vector2) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool != Tool.SELECT:
		return
	var victim_index: int = _victim_index_for_id(victim_id)
	if victim_index < 0:
		return
	_move_victim_to(victim_index, floor_pos_m)
	selected_victim_index = victim_index
	_sync_victim_property_fields(Dictionary(Array(editor_data.get("victims", []))[victim_index]))
	queue_redraw()


func _on_editor_3d_player_start_dragged(floor_pos_m: Vector2) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		return
	if current_tool != Tool.SELECT:
		return
	_move_player_start_to(floor_pos_m)
	var start: Dictionary = Dictionary(editor_data.get("player_start", {})) if typeof(editor_data.get("player_start", {})) == TYPE_DICTIONARY else {}
	selected_player_start_room_id = int(start.get("room_id", -1))
	queue_redraw()


func _on_editor_3d_element_drag_ended(kind: String) -> void:
	if _editor_view_mode != EditorViewMode.MODE_3D:
		_editor_3d_drag_active = false
		return
	_editor_3d_drag_active = false
	_mark_editor_runtime_dirty()
	_sync_editor_runtime_views()
	_refresh_property_panel()
	match kind:
		"object":
			_set_status("Objeto movido en 3D.")
		"detector":
			_set_status("Detector movido en 3D.")
		"victim":
			_set_status("Víctima movida en 3D.")
		"player_start":
			_set_status("Inicio FP movido en 3D.")
		_:
			_set_status("Elemento movido en 3D.")
	queue_redraw()


func _sync_editor_3d_after_direct_edit() -> void:
	_mark_editor_runtime_dirty()
	if _editor_view_mode == EditorViewMode.MODE_3D:
		_sync_editor_runtime_views()
	_refresh_property_panel()
	queue_redraw()


func _move_object_center_to(room_id: int, object_index: int, world_center_m: Vector2, visual_pose_locked: bool = true) -> void:
	var obj: Dictionary = _get_object(room_id, object_index)
	if obj.is_empty():
		return
	var room_rect: Rect2 = _get_room_rect(room_id)
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		return
	var size: Vector2 = _object_size_m(obj)
	var local_pos: Vector2 = _snap_object_m(world_center_m - room_rect.position - size * 0.5)
	local_pos = _clamp_object_local_pos_for_rotation(room_rect, size, local_pos, float(obj.get("rotation_deg", 0.0)))
	_set_object_position(room_id, object_index, local_pos, visual_pose_locked)


func _move_detector_to(detector_index: int, world_pos_m: Vector2) -> void:
	var dets: Array = editor_data.get("detectors", [])
	if detector_index < 0 or detector_index >= dets.size() or typeof(dets[detector_index]) != TYPE_DICTIONARY:
		return
	var det: Dictionary = dets[detector_index]
	var room_id: int = _find_room_at(world_pos_m)
	if room_id < 0:
		room_id = int(det.get("room_id", -1))
	var room_rect: Rect2 = _get_room_rect(room_id)
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		return
	var local_pos: Vector2 = _snap_m(world_pos_m - room_rect.position)
	local_pos.x = clampf(local_pos.x, 0.0, maxf(0.0, room_rect.size.x))
	local_pos.y = clampf(local_pos.y, 0.0, maxf(0.0, room_rect.size.y))
	det["room_id"] = room_id
	det["x_m"] = local_pos.x
	det["y_m"] = local_pos.y
	dets[detector_index] = det
	editor_data["detectors"] = dets


func _move_victim_to(victim_index: int, world_pos_m: Vector2) -> void:
	var vics: Array = editor_data.get("victims", [])
	if victim_index < 0 or victim_index >= vics.size() or typeof(vics[victim_index]) != TYPE_DICTIONARY:
		return
	var vic: Dictionary = vics[victim_index]
	var room_id: int = _find_room_at(world_pos_m)
	if room_id < 0:
		room_id = int(vic.get("room_id", -1))
	var room_rect: Rect2 = _get_room_rect(room_id)
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		return
	var local_pos: Vector2 = _snap_m(world_pos_m - room_rect.position)
	local_pos.x = clampf(local_pos.x, 0.0, maxf(0.0, room_rect.size.x))
	local_pos.y = clampf(local_pos.y, 0.0, maxf(0.0, room_rect.size.y))
	vic["room_id"] = room_id
	vic["x_m"] = local_pos.x
	vic["y_m"] = local_pos.y
	vics[victim_index] = vic
	editor_data["victims"] = vics


func _move_player_start_to(world_pos_m: Vector2) -> void:
	var start: Dictionary = Dictionary(editor_data.get("player_start", {})) if typeof(editor_data.get("player_start", {})) == TYPE_DICTIONARY else {}
	var room_id: int = _find_room_at(world_pos_m)
	if room_id < 0:
		room_id = int(start.get("room_id", -1))
	var room: Dictionary = _get_room(room_id)
	var room_rect: Rect2 = _get_room_rect(room_id)
	if room.is_empty() or room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		return
	var local_pos: Vector2 = _snap_m(world_pos_m - room_rect.position)
	local_pos.x = clampf(local_pos.x, 0.0, maxf(0.0, room_rect.size.x))
	local_pos.y = clampf(local_pos.y, 0.0, maxf(0.0, room_rect.size.y))
	start["room_id"] = room_id
	start["position_m"] = Serializer.vector_to_data(local_pos)
	start["floor_level_z_m"] = float(room.get("floor_level_z_m", 0.0))
	start["yaw_deg"] = float(start.get("yaw_deg", 0.0))
	editor_data["player_start"] = start


func _sync_detector_property_fields(det: Dictionary) -> void:
	_props.fill_detector(det)


func _sync_victim_property_fields(vic: Dictionary) -> void:
	_props.fill_victim(vic)


func _object_index_for_id(room_id: int, object_id: String) -> int:
	var room: Dictionary = _get_room(room_id)
	if room.is_empty():
		return -1
	var objects: Array = room.get("fuel_objects", [])
	for i in range(objects.size()):
		if typeof(objects[i]) == TYPE_DICTIONARY and String(Dictionary(objects[i]).get("id", "")) == object_id:
			return i
	return -1


func _detector_index_for_id(detector_id: String) -> int:
	var detectors: Array = editor_data.get("detectors", [])
	for i in range(detectors.size()):
		if typeof(detectors[i]) == TYPE_DICTIONARY and String(Dictionary(detectors[i]).get("id", "")) == detector_id:
			return i
	return -1


func _victim_index_for_id(victim_id: String) -> int:
	var victims: Array = editor_data.get("victims", [])
	for i in range(victims.size()):
		if typeof(victims[i]) == TYPE_DICTIONARY and String(Dictionary(victims[i]).get("id", "")) == victim_id:
			return i
	return -1


func _detector_id_for_index(index: int) -> String:
	var detectors: Array = editor_data.get("detectors", [])
	if index < 0 or index >= detectors.size() or typeof(detectors[index]) != TYPE_DICTIONARY:
		return ""
	return String(Dictionary(detectors[index]).get("id", ""))


func _victim_id_for_index(index: int) -> String:
	var victims: Array = editor_data.get("victims", [])
	if index < 0 or index >= victims.size() or typeof(victims[index]) != TYPE_DICTIONARY:
		return ""
	return String(Dictionary(victims[index]).get("id", ""))


func _find_left_vbox() -> VBoxContainer:
	# La ruta buena lleva el ScrollContainer que se anadio para que el panel no
	# se coma sus propios botones; las de debajo son escenas antiguas.
	var left_vbox := _ui_root.get_node_or_null("LeftPanel/Scroll/VBox") as VBoxContainer
	if left_vbox != null:
		return left_vbox
	left_vbox = _ui_root.get_node_or_null("LeftPanel/VBox") as VBoxContainer
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


func _get_left_node(path: String) -> Node:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return null
	return left_vbox.get_node_or_null(path)


## Los tres ayudantes que el panel izquierdo comparte con el derecho. El panel
## derecho se llevo su copia al modulo; estos se quedan porque los usan la barra
## de herramientas y las secciones de la izquierda.
func _set_node_visible(path: String, visible: bool) -> void:
	if _ui_root == null:
		return
	var node := _get_ui_node(path) as Control
	if node != null:
		node.visible = visible


## Una casilla vive dentro de su fila con la etiqueta al lado: esconder la
## casilla sola dejaria la etiqueta huerfana.
func _set_control_row_visible(control: Control, visible: bool) -> void:
	if control == null:
		return
	var parent := control.get_parent() as Control
	if parent != null and parent is HBoxContainer:
		parent.visible = visible
	else:
		control.visible = visible


func _stair_turn_mode_from_option(option: OptionButton) -> String:
	if option == null:
		return StairPlanRules.MODE_AUTO
	return _stair_turn_mode_from_item_id(option.get_selected_id())


func _get_ui_node(path: String) -> Node:
	if _ui_root == null:
		return null
	var node := _ui_root.get_node_or_null(path)
	if node != null:
		return node
	var left_prefix := "LeftPanel/Scroll/VBox/"
	if path == "LeftPanel/Scroll/VBox":
		return _find_left_vbox()
	if path.begins_with(left_prefix):
		return _get_left_node(path.substr(left_prefix.length()))
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
			label.add_theme_font_size_override("font_size", editor_font_size_heading)
			label.add_theme_color_override("font_color", UI_BORDER_HOT)
		elif label.name == "StatusLabel":
			label.add_theme_font_size_override("font_size", editor_font_size_status)
			label.custom_minimum_size.y = maxf(label.custom_minimum_size.y, 72.0)
			label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		elif label.name == "ControlsHelp":
			label.add_theme_font_size_override("font_size", editor_font_size_body)
			label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		elif label.name == "FloorStatusLabel":
			label.add_theme_font_size_override("font_size", editor_font_size_compact)
			label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		elif label.name == "EditorModeLabel":
			label.add_theme_font_override("font", _editor_title_font)
			label.add_theme_font_size_override("font_size", editor_font_size_body)
			label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		else:
			label.add_theme_font_size_override("font_size", editor_font_size_body)
			if not label.text.contains(":") and label.text.length() <= 36:
				label.text = label.text.to_upper()
	if node is Button:
		var button := node as Button
		button.text = button.text.to_upper()
		# El foco no se apaga: el tema trae recuadro de foco, y sin foco no hay
		# tabulador, que en un panel de catorce casillas obliga a clicar una a una.
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_override("font", _editor_title_font)
		button.add_theme_font_size_override("font_size", editor_font_size_button)
	if node is LineEdit:
		var edit := node as LineEdit
		edit.add_theme_font_override("font", _editor_font)
		edit.add_theme_font_size_override("font_size", editor_font_size_body)
	if node is SpinBox:
		var spin := node as SpinBox
		# SpinBox nace sin foco: aqui hay que pedirlo, no solo no quitarlo.
		spin.focus_mode = Control.FOCUS_ALL
		spin.add_theme_font_override("font", _editor_font)
		spin.add_theme_font_size_override("font_size", editor_font_size_body)
	if node is OptionButton:
		var option := node as OptionButton
		option.focus_mode = Control.FOCUS_ALL
		option.add_theme_font_override("font", _editor_title_font)
		option.add_theme_font_size_override("font_size", editor_font_size_button)
	if node is ItemList:
		var item_list := node as ItemList
		item_list.focus_mode = Control.FOCUS_ALL
		item_list.add_theme_font_override("font", _editor_font)
		item_list.add_theme_font_size_override("font_size", editor_font_size_compact)
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
		"building_type": "single_family",
		"apartment_floor_number": 1,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"interior_lights_on": true,
		"exterior_lighting_mode": "Dia",
		"floors": _default_floors(),
		"exterior_walls": [],
		"room_rect_m": {},
		"rooms_data": [],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"player_start": {}
	}
	current_floor_index = 0
	_undo_stack.clear()
	_redo_stack.clear()


func _push_undo_snapshot(_label: String = "") -> void:
	if editor_data.is_empty():
		return
	_undo_stack.append(editor_data.duplicate(true))
	while _undo_stack.size() > max_undo_steps:
		_undo_stack.remove_at(0)
	# Una accion nueva invalida el rehacer: a partir de aqui la historia es otra.
	_redo_stack.clear()
	_unsaved_changes = true
	_mark_editor_runtime_dirty()


func _undo_last_action() -> void:
	if _undo_stack.is_empty():
		_set_status("No hay acciones para deshacer.")
		return
	var snapshot: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(editor_data.duplicate(true))
	while _redo_stack.size() > max_undo_steps:
		_redo_stack.remove_at(0)
	_apply_history_snapshot(snapshot, "Última acción deshecha.")


## Rehacer: la misma operacion que deshacer, en la direccion contraria.
##
## Con instantaneas completas sale casi gratis, y su ausencia se notaba: habia
## 48 pasos de deshacer y ninguno de rehacer, asi que un Ctrl+Z de mas perdia el
## trabajo sin remedio.
func _redo_last_action() -> void:
	if _redo_stack.is_empty():
		_set_status("No hay acciones para rehacer.")
		return
	var snapshot: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(editor_data.duplicate(true))
	while _undo_stack.size() > max_undo_steps:
		_undo_stack.remove_at(0)
	_apply_history_snapshot(snapshot, "Acción rehecha.")


## Deja el editor en el estado de una instantanea. Lo comparten deshacer y
## rehacer para que no se separen al tocar uno de los dos.
func _apply_history_snapshot(snapshot: Dictionary, message: String) -> void:
	_unsaved_changes = true
	editor_data = Serializer.normalize_editor_data(snapshot.duplicate(true))
	_ensure_floor_data()
	current_floor_index = clampi(current_floor_index, 0, _get_floors().size() - 1)
	pending_door_room_id = -1
	is_dragging_room = false
	is_dragging_exterior_wall = false
	is_dragging_object = false
	object_mouse_mode = ObjectMouseMode.NONE
	_sync_floor_controls()
	_sync_hvac_option_from_data()
	_sync_lighting_controls_from_data()
	_sync_building_type_option_from_data()
	_clear_selection()
	_mark_editor_runtime_dirty()
	_set_status(message)
	queue_redraw()


func _default_floors() -> Array:
	return [
		{"name": "PB", "level_m": 0.0}
	]










func _populate_building_type_option() -> void:
	if _building_type_option == null:
		return
	if _building_type_option.get_item_count() == 0:
		_building_type_option.add_item("Casa unifamiliar", 0)
		_building_type_option.add_item("Piso", 1)
	_sync_building_type_option_from_data()


func _sync_building_type_option_from_data() -> void:
	if _building_type_option == null:
		return
	var building_type: String = String(editor_data.get("building_type", "single_family")).to_lower()
	_building_type_option.select(1 if building_type == "apartment" else 0)
	_sync_apartment_floor_control()


func _on_building_type_selected(index: int) -> void:
	var new_type: String = "apartment" if index == 1 else "single_family"
	if String(editor_data.get("building_type", "single_family")).to_lower() == new_type:
		return
	_push_undo_snapshot("building_type")
	editor_data["building_type"] = new_type
	_sync_apartment_floor_control()
	_set_status("Exterior configurado como %s." % ("piso" if index == 1 else "casa unifamiliar"))


func _sync_apartment_floor_control() -> void:
	if _apartment_floor_spin == null:
		return
	_apartment_floor_spin.value = int(editor_data.get("apartment_floor_number", 1))
	var is_apartment: bool = String(editor_data.get("building_type", "single_family")).to_lower() == "apartment"
	_set_control_row_visible(_apartment_floor_spin, is_apartment)


func _on_apartment_floor_changed(value: float) -> void:
	var next_floor: int = int(round(value))
	if int(editor_data.get("apartment_floor_number", 1)) == next_floor:
		return
	_push_undo_snapshot("apartment_floor")
	editor_data["apartment_floor_number"] = next_floor
	_set_status("Planta exterior del piso: %d." % next_floor)


func _bind_controls_help_block(parent: Control) -> void:
	_hover_help_check = _scene_control(parent, "HoverHelpRow/HoverHelpCheck") as CheckBox
	if _hover_help_check != null:
		_hover_help_check.tooltip_text = "Activa carteles sobre los elementos dibujados al dejar el cursor quieto en el plano."
		var hover_callable := Callable(self, "_on_hover_help_toggled")
		if not _hover_help_check.toggled.is_connected(hover_callable):
			_hover_help_check.toggled.connect(hover_callable)

	_help_toggle_button = _scene_control(parent, "ControlsHelpToggle") as Button
	if _help_toggle_button != null:
		_help_toggle_button.toggle_mode = false
		_help_toggle_button.text = "AYUDA DEL EDITOR"
		_help_toggle_button.tooltip_text = "Abre la guía rápida del editor en una ventana modal paginada."
		var help_callable := Callable(self, "_show_editor_help_dialog")
		if not _help_toggle_button.pressed.is_connected(help_callable):
			_help_toggle_button.pressed.connect(help_callable)

	_help_panel = _scene_control(parent, "ControlsHelpPanel") as PanelContainer
	if _help_panel != null:
		_help_panel.visible = false
	# La guia la escribe el codigo, no la escena: se arma con las teclas de
	# TOOL_SHORTCUTS y con el nombre de cada herramienta.
	_help_label = _scene_control(parent, "ControlsHelpPanel/Margin/ControlsHelp") as Label
	if _help_label != null:
		_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_help_label.add_theme_font_size_override("font_size", editor_font_size_body)
		_help_label.add_theme_color_override("font_color", UI_TEXT_MUTED)
		_help_label.text = _editor_help_text()

	_move_controls_help_after_element_list(parent)
	_set_controls_help_expanded(false)
	_ensure_editor_help_dialog()


func _set_controls_help_expanded(expanded: bool) -> void:
	if _help_panel != null:
		_help_panel.visible = expanded
	if _help_toggle_button != null:
		_help_toggle_button.text = "AYUDA DEL EDITOR"


func _ensure_editor_help_dialog() -> void:
	if _help_dialog != null:
		return
	_help_dialog = AcceptDialog.new()
	_help_dialog.name = "EditorHelpDialog"
	_help_dialog.title = "Ayuda del editor"
	_help_dialog.exclusive = true
	_help_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	_help_dialog.size = Vector2i(620, 420)
	add_child(_help_dialog)

	var root_box := VBoxContainer.new()
	root_box.name = "HelpRoot"
	root_box.add_theme_constant_override("separation", 10)
	_help_dialog.add_child(root_box)

	_help_dialog_label = Label.new()
	_help_dialog_label.name = "HelpPageText"
	_help_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_dialog_label.custom_minimum_size = Vector2(560.0, 270.0)
	_help_dialog_label.add_theme_font_size_override("font_size", editor_font_size_body)
	_help_dialog_label.add_theme_color_override("font_color", UI_TEXT)
	root_box.add_child(_help_dialog_label)

	var nav_row := HBoxContainer.new()
	nav_row.name = "HelpNav"
	nav_row.add_theme_constant_override("separation", 8)
	root_box.add_child(nav_row)

	var prev_button := Button.new()
	prev_button.text = "< Anterior"
	prev_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_button.pressed.connect(_show_previous_help_page)
	nav_row.add_child(prev_button)

	_help_dialog_page_label = Label.new()
	_help_dialog_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_dialog_page_label.custom_minimum_size.x = 96.0
	nav_row.add_child(_help_dialog_page_label)

	var next_button := Button.new()
	next_button.text = "Siguiente >"
	next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_button.pressed.connect(_show_next_help_page)
	nav_row.add_child(next_button)


func _show_editor_help_dialog() -> void:
	_ensure_editor_help_dialog()
	_help_page_index = 0
	_update_editor_help_dialog_page()
	_help_dialog.popup_centered()


func _show_previous_help_page() -> void:
	var pages: PackedStringArray = _editor_help_pages()
	if pages.is_empty():
		return
	_help_page_index = posmod(_help_page_index - 1, pages.size())
	_update_editor_help_dialog_page()


func _show_next_help_page() -> void:
	var pages: PackedStringArray = _editor_help_pages()
	if pages.is_empty():
		return
	_help_page_index = posmod(_help_page_index + 1, pages.size())
	_update_editor_help_dialog_page()


func _update_editor_help_dialog_page() -> void:
	var pages: PackedStringArray = _editor_help_pages()
	if pages.is_empty():
		return
	_help_page_index = clampi(_help_page_index, 0, pages.size() - 1)
	if _help_dialog_label != null:
		_help_dialog_label.text = pages[_help_page_index]
	if _help_dialog_page_label != null:
		_help_dialog_page_label.text = "%d / %d" % [_help_page_index + 1, pages.size()]


func _move_controls_help_after_element_list(parent: Control) -> void:
	if _help_toggle_button == null or _help_panel == null:
		return
	var anchor := parent.get_node_or_null("ElementList") as Control
	if anchor == null:
		anchor = parent.get_node_or_null("FloorSection") as Control
	if anchor == null or anchor.get_parent() != parent:
		return
	var hover_row := parent.get_node_or_null("HoverHelpRow") as Control
	if hover_row != null:
		parent.move_child(hover_row, mini(anchor.get_index() + 1, parent.get_child_count() - 1))
		parent.move_child(_help_toggle_button, mini(hover_row.get_index() + 1, parent.get_child_count() - 1))
	else:
		parent.move_child(_help_toggle_button, mini(anchor.get_index() + 1, parent.get_child_count() - 1))
	parent.move_child(_help_panel, mini(_help_toggle_button.get_index() + 1, parent.get_child_count() - 1))


func _on_hover_help_toggled(enabled: bool) -> void:
	_hover_help_enabled = enabled
	_reset_hover_help()


func _editor_help_text() -> String:
	return "\n\n".join(_editor_help_pages())


func _editor_help_pages() -> PackedStringArray:
	return PackedStringArray([
		"Dibujo\n\nElige una herramienta en la barra superior o pulsa su tecla. Sala, Pasillo y Escalera se crean arrastrando. Puerta, Ventana y Hueco se colocan clicando sobre una pared. Objeto, Detector, Víctima e Inicio FP se colocan clicando dentro de una sala.",
		"Teclas\n\n%s.\nEsc vuelve a %s. Ctrl+Z deshace, Ctrl+Y rehace y Supr borra la selección. Ctrl+C copia, Ctrl+V pega donde esté el cursor y Ctrl+D duplica al lado. Ctrl+S guarda y Ctrl+O carga. Mientras escribes en una casilla, las teclas de herramienta no responden." % [_tool_shortcuts_line(), _tool_display_name(Tool.SELECT)],
		"Selección\n\nUsa %s para elegir elementos en el plano. Si un objeto, detector o víctima está encima de una sala, el editor prioriza el elemento pequeño antes que la sala. La pestaña Lista permite seleccionar cosas cuando se solapan." % _tool_display_name(Tool.SELECT),
		"Edición\n\nEl panel derecho muestra solo las propiedades del elemento seleccionado. Las salas y objetos tienen tiradores para mover, redimensionar y rotar. Cada casilla numérica lleva su unidad escrita dentro, y al dejar el cursor sobre un control se explica qué hace. Supr borra la selección y Ctrl+Z deshace.",
		"Archivo\n\nLa pestaña Archivo agrupa guardar, cargar, exportar runtime, tiempo de parada, luces, tipo de edificio, HVAC y plantillas. Iniciar simulación valida y exporta el escenario antes de abrir SimulationScene. Si sales con cambios sin guardar, el editor pregunta antes."
	])


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
	if _floor_delete_button != null:
		_floor_delete_button.disabled = floors.size() <= 1
	_update_floor_status()
	_refresh_element_list()


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


func _refresh_element_list() -> void:
	if _element_list == null:
		return
	_element_list_sync_in_progress = true
	_element_list.clear()
	var selected_item_index: int = -1
	var row_index: int = 0
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if not _is_room_on_current_floor(room_dict):
			continue
		var room_id: int = int(room_dict.get("id", -1))
		var room_label: String = "%s  R%d  %s" % [_element_type_label_for_room(room_dict), room_id, _room_display_name(room_dict, room_id)]
		_element_list.add_item(room_label)
		_element_list.set_item_metadata(row_index, {"type": "room", "room_id": room_id})
		if selected_room_id == room_id:
			selected_item_index = row_index
		row_index += 1

		var objects: Array = room_dict.get("fuel_objects", [])
		for obj_index in range(objects.size()):
			if typeof(objects[obj_index]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[obj_index]
			_element_list.add_item("  Objeto  %s" % String(obj.get("name", obj.get("kind", "obj"))))
			_element_list.set_item_metadata(row_index, {"type": "object", "room_id": room_id, "object_index": obj_index})
			if selected_object_room_id == room_id and selected_object_index == obj_index:
				selected_item_index = row_index
			row_index += 1

	for i in range(Array(editor_data.get("openings_data", [])).size()):
		var openings: Array = editor_data.get("openings_data", [])
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var opening: Dictionary = openings[i]
		if not _opening_on_current_floor(opening):
			continue
		_element_list.add_item(_element_label_for_opening(opening, i))
		_element_list.set_item_metadata(row_index, {"type": "opening", "opening_index": i})
		if selected_opening_index == i:
			selected_item_index = row_index
		row_index += 1

	for i in range(Array(editor_data.get("detectors", [])).size()):
		var dets: Array = editor_data.get("detectors", [])
		if typeof(dets[i]) != TYPE_DICTIONARY:
			continue
		var det: Dictionary = dets[i]
		var room_id: int = int(det.get("room_id", -1))
		if not _is_room_on_current_floor(_get_room(room_id)):
			continue
		_element_list.add_item("Detector  %s  R%d" % [String(det.get("id", str(i))), room_id])
		_element_list.set_item_metadata(row_index, {"type": "detector", "detector_index": i})
		if selected_detector_index == i:
			selected_item_index = row_index
		row_index += 1

	for i in range(Array(editor_data.get("victims", [])).size()):
		var vics: Array = editor_data.get("victims", [])
		if typeof(vics[i]) != TYPE_DICTIONARY:
			continue
		var vic: Dictionary = vics[i]
		var room_id: int = int(vic.get("room_id", -1))
		if not _is_room_on_current_floor(_get_room(room_id)):
			continue
		_element_list.add_item("Víctima  %s  R%d" % [String(vic.get("name", vic.get("id", str(i)))), room_id])
		_element_list.set_item_metadata(row_index, {"type": "victim", "victim_index": i})
		if selected_victim_index == i:
			selected_item_index = row_index
		row_index += 1

	var start: Dictionary = Dictionary(editor_data.get("player_start", {})) if typeof(editor_data.get("player_start", {})) == TYPE_DICTIONARY else {}
	if not start.is_empty():
		var start_room_id: int = int(start.get("room_id", -1))
		if _is_room_on_current_floor(_get_room(start_room_id)):
			_element_list.add_item("Inicio FP  R%d" % start_room_id)
			_element_list.set_item_metadata(row_index, {"type": "player_start", "room_id": start_room_id})
			if selected_player_start_room_id == start_room_id:
				selected_item_index = row_index
			row_index += 1

	if row_index == 0:
		_element_list.add_item("Sin elementos en %s" % _current_floor_name())
		_element_list.set_item_disabled(0, true)
	elif selected_item_index >= 0:
		_element_list.select(selected_item_index)
	_element_list_sync_in_progress = false


func _element_type_label_for_room(room: Dictionary) -> String:
	if StairPlanRules.is_stair_room(room):
		return "Escalera"
	if _is_corridor_room(room):
		return "Pasillo"
	return "Estancia"


func _element_label_for_opening(opening: Dictionary, index: int) -> String:
	var type_text: String = String(opening.get("type", "door"))
	var label: String = "Puerta"
	if type_text == "window":
		label = "Ventana"
	elif type_text == "hole":
		label = "Hueco"
	if bool(opening.get("is_vertical", false)):
		label = "Hueco vertical"
	var a_id: int = int(opening.get("a", -1))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	var target: String = "exterior" if b_id == OUTSIDE_ID else "R%d-R%d" % [a_id, b_id]
	return "%s  %02d  %s" % [label, index, target]


func _on_element_list_item_selected(index: int) -> void:
	if _element_list_sync_in_progress or _element_list == null:
		return
	var meta: Variant = _element_list.get_item_metadata(index)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var data: Dictionary = meta
	match String(data.get("type", "")):
		"room":
			_select_room(int(data.get("room_id", -1)))
		"object":
			_select_object(int(data.get("room_id", -1)), int(data.get("object_index", -1)))
		"opening":
			_select_opening(int(data.get("opening_index", -1)))
		"detector":
			_select_detector(int(data.get("detector_index", -1)))
		"victim":
			_select_victim(int(data.get("victim_index", -1)))
		"player_start":
			_select_player_start(int(data.get("room_id", -1)))


func _on_floor_selected(index: int) -> void:
	current_floor_index = clampi(index, 0, maxi(0, _get_floors().size() - 1))
	pending_door_room_id = -1
	_clear_selection()
	_sync_floor_controls()
	_set_status("Planta activa: %s." % _current_floor_name())
	queue_redraw()


func _add_floor_pressed() -> void:
	_push_undo_snapshot("add_floor")
	var floors: Array = _get_floors()
	var lower_level_m: float = _current_floor_level_m()
	var next_level_m: float = 0.0
	if not floors.is_empty():
		lower_level_m = float(floors[floors.size() - 1].get("level_m", 0.0))
		next_level_m = lower_level_m + DEFAULT_FLOOR_HEIGHT_M
	floors.append({"name": _default_floor_name(floors.size()), "level_m": next_level_m})
	editor_data["floors"] = floors
	_copy_stairs_from_level_to_level(lower_level_m, next_level_m)
	current_floor_index = floors.size() - 1
	pending_door_room_id = -1
	_clear_selection()
	_sync_floor_controls()
	_set_status("Nueva planta creada: %s." % _current_floor_name())
	queue_redraw()


func _delete_floor_pressed() -> void:
	var floors: Array = _get_floors()
	if floors.size() <= 1:
		_set_status("No se puede borrar la unica planta.")
		return
	if current_floor_index < 0 or current_floor_index >= floors.size():
		return
	_push_undo_snapshot("delete_floor")
	var floor: Dictionary = floors[current_floor_index]
	var level_m: float = float(floor.get("level_m", 0.0))
	var room_ids_to_delete: Array[int] = []
	for room in editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and absf(float(Dictionary(room).get("floor_level_z_m", 0.0)) - level_m) < 0.05:
			room_ids_to_delete.append(int(Dictionary(room).get("id", -1)))

	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size() - 1, -1, -1):
		if typeof(rooms[i]) == TYPE_DICTIONARY and room_ids_to_delete.has(int(Dictionary(rooms[i]).get("id", -1))):
			rooms.remove_at(i)
	editor_data["rooms_data"] = rooms

	var rects: Dictionary = editor_data.get("room_rect_m", {})
	for room_id in room_ids_to_delete:
		rects.erase(str(room_id))
	editor_data["room_rect_m"] = rects

	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size() - 1, -1, -1):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = openings[i]
		if room_ids_to_delete.has(int(op.get("a", -999))) or room_ids_to_delete.has(int(op.get("b", -999))):
			openings.remove_at(i)
	editor_data["openings_data"] = openings

	var dets: Array = editor_data.get("detectors", [])
	for i in range(dets.size() - 1, -1, -1):
		if typeof(dets[i]) == TYPE_DICTIONARY and room_ids_to_delete.has(int(Dictionary(dets[i]).get("room_id", -1))):
			dets.remove_at(i)
	editor_data["detectors"] = dets

	var vics: Array = editor_data.get("victims", [])
	for i in range(vics.size() - 1, -1, -1):
		if typeof(vics[i]) == TYPE_DICTIONARY and room_ids_to_delete.has(int(Dictionary(vics[i]).get("room_id", -1))):
			vics.remove_at(i)
	editor_data["victims"] = vics

	floors.remove_at(current_floor_index)
	editor_data["floors"] = floors
	current_floor_index = clampi(current_floor_index - 1, 0, floors.size() - 1)
	_clear_selection()
	_ensure_floor_data()
	_sync_floor_controls()
	_set_status("Planta %s eliminada." % String(floor.get("name", "")))
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
	_push_undo_snapshot("floor_level")
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
	if bool(opening.get("is_vertical", false)):
		var b_on_floor: bool = b_id != OUTSIDE_ID and absf(_room_id_floor_level(b_id) - _current_floor_level_m()) < 0.05
		return a_on_floor or b_on_floor
	if b_id == OUTSIDE_ID:
		return a_on_floor
	return a_on_floor and absf(_room_id_floor_level(b_id) - _current_floor_level_m()) < 0.05


## Tecla de cada herramienta. En un editor de planos se cambia de herramienta
## cada pocos segundos: sin teclas, cada cambio es un viaje del raton a la barra
## de arriba y vuelta.
##
## Los digitos siguen el orden de la barra; las letras son la inicial de lo que
## colocan. Escape vuelve a seleccionar, que es lo que hace todo editor.
##
## Escape va el ultimo a proposito: el tooltip anuncia la primera tecla de la
## lista, y "1" se lee mas rapido que "Escape".
const TOOL_SHORTCUTS: Dictionary = {
	KEY_1: Tool.SELECT,
	KEY_2: Tool.EXTERIOR_WALL,
	KEY_3: Tool.ROOM,
	KEY_4: Tool.CORRIDOR_L,
	KEY_5: Tool.STAIRS,
	KEY_6: Tool.DOOR,
	KEY_7: Tool.WINDOW,
	KEY_8: Tool.HOLE,
	KEY_9: Tool.OBJECT,
	KEY_0: Tool.DELETE,
	KEY_D: Tool.DETECTOR,
	KEY_V: Tool.VICTIM,
	KEY_F: Tool.PLAYER_START,
	KEY_I: Tool.IGNITION,
	KEY_ESCAPE: Tool.SELECT,
}


## Nombre visible de cada herramienta y su clave de traduccion. Lo leen los
## botones de la barra y la pagina de teclas de la ayuda: una sola lista, para
## que la ayuda no anuncie un nombre que el boton ya no lleva.
const TOOL_NAMES: Dictionary = {
	Tool.SELECT: ["editor.tool.select", "Selección"],
	Tool.EXTERIOR_WALL: ["editor.tool.exterior", "Exterior"],
	Tool.ROOM: ["editor.tool.room", "Sala"],
	Tool.CORRIDOR_L: ["editor.tool.corridor", "Pasillo"],
	Tool.STAIRS: ["editor.tool.stairs", "Escalera"],
	Tool.DOOR: ["editor.tool.door", "Puerta"],
	Tool.WINDOW: ["editor.tool.window", "Ventana"],
	Tool.HOLE: ["editor.tool.hole", "Hueco"],
	Tool.OBJECT: ["editor.tool.object", "Objeto"],
	Tool.DELETE: ["editor.tool.delete", "Borrar"],
	Tool.DETECTOR: ["editor.tool.detector", "Detector"],
	Tool.VICTIM: ["editor.tool.victim", "Víctima"],
	Tool.PLAYER_START: ["editor.tool.player_start", "Inicio FP"],
	Tool.IGNITION: ["editor.tool.ignition", "Ignición"],
}


## Icono de cada herramienta. Dibujo de linea de 18 px en ui/icons, en blanco:
## el color lo pone el tema segun el estado del boton, asi que la herramienta
## activa enciende su icono con el mismo naranja que su etiqueta.
##
## Una barra de solo texto en mayusculas se lee como prototipo, y con catorce
## herramientas el icono es lo que se reconoce antes de leer.
const TOOL_ICONS: Dictionary = {
	Tool.SELECT: "res://ui/icons/tool_select.svg",
	Tool.EXTERIOR_WALL: "res://ui/icons/tool_exterior.svg",
	Tool.ROOM: "res://ui/icons/tool_room.svg",
	Tool.CORRIDOR_L: "res://ui/icons/tool_corridor.svg",
	Tool.STAIRS: "res://ui/icons/tool_stairs.svg",
	Tool.DOOR: "res://ui/icons/tool_door.svg",
	Tool.WINDOW: "res://ui/icons/tool_window.svg",
	Tool.HOLE: "res://ui/icons/tool_hole.svg",
	Tool.OBJECT: "res://ui/icons/tool_object.svg",
	Tool.DELETE: "res://ui/icons/tool_delete.svg",
	Tool.DETECTOR: "res://ui/icons/tool_detector.svg",
	Tool.VICTIM: "res://ui/icons/tool_victim.svg",
	Tool.PLAYER_START: "res://ui/icons/tool_player_start.svg",
	Tool.IGNITION: "res://ui/icons/tool_ignite.svg",
}


func _tool_icon(tool_id: int) -> Texture2D:
	if not TOOL_ICONS.has(tool_id):
		return null
	var path: String = String(TOOL_ICONS[tool_id])
	if not ResourceLoader.exists(path):
		push_error("ScenarioEditor: falta el icono %s" % path)
		return null
	return load(path) as Texture2D


func _tool_display_name(tool_id: int) -> String:
	if not TOOL_NAMES.has(tool_id):
		return ""
	var entry: Array = TOOL_NAMES[tool_id]
	return _ui_text(String(entry[0]), String(entry[1]))


## La linea de teclas de la ayuda, escrita desde la misma tabla que las escucha.
## Escape se cuenta aparte porque comparte herramienta con el 1.
func _tool_shortcuts_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for keycode in TOOL_SHORTCUTS:
		if int(keycode) == KEY_ESCAPE:
			continue
		parts.append("%s %s" % [
			OS.get_keycode_string(int(keycode)),
			_tool_display_name(int(TOOL_SHORTCUTS[keycode]))
		])
	return " · ".join(parts)


func _tool_for_keycode(keycode: int) -> int:
	return int(TOOL_SHORTCUTS[keycode]) if TOOL_SHORTCUTS.has(keycode) else -1


## Cierto si el foco esta en algo donde se escribe. Sin esto, teclear "sala" en
## el nombre de una habitacion cambiaria de herramienta cuatro veces.
func _keyboard_is_typing() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return false
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is SpinBox


func _set_tool(tool_id: int) -> void:
	if not _tool_available_in_current_mode(tool_id):
		_set_status("Esa herramienta esta reservada al modo 2D.")
		_sync_tool_button_states()
		return
	current_tool = tool_id
	pending_door_room_id = -1
	_sync_tool_button_states()
	_clear_drag()
	_set_status(_tool_hint(current_tool))
	_sync_tool_option_visibility()
	_update_editor_visualizer_drag_mode()
	# Resaltar el control de ancho de pasillo solo cuando la herramienta pasillo esta activa
	var corridor_section := _get_left_node("CorridorSectionLabel") as Label
	if corridor_section != null:
		corridor_section.add_theme_color_override(
			"font_color",
			Color(1.0, 0.5, 0.0, 1.0) if current_tool == Tool.CORRIDOR_L else Color(0.49, 0.55, 0.60, 0.92)
		)


func _tool_hint(tool_id: int) -> String:
	if _editor_view_mode == EditorViewMode.MODE_3D:
		match tool_id:
			Tool.SELECT:
				return _ui_text("editor.tooltip_3d_select", "3D seleccionar: selecciona y arrastra objetos, detectores, víctimas o inicio FP. Botón derecho orbita.")
			Tool.DOOR:
				return "3D Puerta: pulsa el suelo muy cerca de una pared compartida o exterior."
			Tool.HOLE:
				return "3D Hueco: pulsa el suelo muy cerca de una pared compartida."
			Tool.WINDOW:
				return "3D Ventana: pulsa el suelo muy cerca de una pared exterior."
			Tool.OBJECT:
				return _ui_text("editor.tooltip_3d_object", "3D objeto: pulsa el suelo de una habitación para colocar el combustible elegido.")
			Tool.IGNITION:
				return "3D Ignición: pulsa directamente sobre un objeto combustible."
			Tool.PLAYER_START:
				return "3D Inicio FP: pulsa el suelo de una habitación para colocar la aparición."
			Tool.DELETE:
				return "3D Borrar: pulsa apertura, objeto, detector, víctima o inicio FP. Salas y muros siguen en 2D."
			Tool.DETECTOR:
				return "3D Detector: pulsa el suelo de una habitación para colocar un detector."
			Tool.VICTIM:
				return "3D Víctima: pulsa el suelo de una habitación para marcar una víctima."
	match tool_id:
		Tool.SELECT:
			return "Seleccionar: clic en habitación, objeto o apertura. Clic derecho para opciones."
		Tool.EXTERIOR_WALL:
			return "Exterior: arrastra para dibujar muros exteriores rectos. También puedes marcar el contorno de una habitación."
		Tool.ROOM:
			return "Estancia: arrastra para crear una estancia en %s." % _current_floor_name()
		Tool.CORRIDOR_L:
			return "Pasillo: arrastra para crear un pasillo. Diagonal = giro en L. Ajusta ANCHO arriba a la izquierda. (%.2f m actualmente)" % corridor_width_m
		Tool.STAIRS:
			return "Escalera (%s): arrastra desde la ENTRADA hacia donde SUBE en %s. Crea la planta superior si falta y recorta el hueco en suelos/techos solapados." % [StairPlanRules.turn_mode_label(_selected_stair_tool_turn_mode()), _current_floor_name()]
		Tool.DOOR:
			return "Puerta: pulsa una pared compartida o exterior en %s para crear puerta." % _current_floor_name()
		Tool.HOLE:
			return "Hueco: pulsa una pared compartida en %s. Se crea un paso sin puerta con ancho máximo limitado por el paramento." % _current_floor_name()
		Tool.WINDOW:
			return "Ventana: pulsa cerca de una pared exterior en %s." % _current_floor_name()
		Tool.OBJECT:
			return "Objeto: pulsa dentro de una estancia de %s para colocar el combustible elegido." % _current_floor_name()
		Tool.IGNITION:
			return "Ignición: pulsa un objeto de %s para marcarlo como foco inicial." % _current_floor_name()
		Tool.PLAYER_START:
			return "Inicio FP: pulsa dentro de una estancia de %s para colocar donde aparece el jugador." % _current_floor_name()
		Tool.DELETE:
			return "Borrar: elimina objeto, apertura o estancia bajo el cursor en %s." % _current_floor_name()
		Tool.DETECTOR:
			return "Detector: pulsa dentro de una habitación de %s para colocar un detector de humo, calor o CO." % _current_floor_name()
		Tool.VICTIM:
			return "Víctima: pulsa dentro de una habitación de %s para marcar la posición de una víctima." % _current_floor_name()
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if _editor_view_mode == EditorViewMode.MODE_3D:
		_handle_3d_editor_input(event)
		return
	if _editor_view_mode != EditorViewMode.MODE_2D:
		return
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
		# Las teclas de herramienta no se comen lo que se esta escribiendo en una
		# casilla: si el foco esta en un campo de texto, manda el campo.
		if not _keyboard_is_typing() and not event.ctrl_pressed and not event.alt_pressed:
			var shortcut_tool: int = _tool_for_keycode(event.keycode)
			if shortcut_tool >= 0:
				_set_tool(shortcut_tool)
				get_viewport().set_input_as_handled()
				return
		if event.keycode == KEY_C and event.ctrl_pressed:
			_copy_selection()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_V and event.ctrl_pressed:
			_paste_clipboard()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_D and event.ctrl_pressed:
			_duplicate_selection()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_S and event.ctrl_pressed:
			_save_pressed()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_O and event.ctrl_pressed:
			_load_pressed()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed:
			_redo_last_action()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Y and event.ctrl_pressed:
			_redo_last_action()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_undo_last_action()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selected()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		_track_hover_help_mouse(event.position)
		if is_dragging_exterior_wall:
			drag_current_m = _screen_to_m(event.position)
			queue_redraw()
		elif is_dragging_room:
			drag_current_m = _screen_to_m(event.position)
			queue_redraw()
		elif is_dragging_room_geometry:
			_update_dragged_room_geometry(_screen_to_m(event.position))
		elif is_dragging_object:
			_update_dragged_object(_screen_to_m_raw(event.position))
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event

	# Clic derecho: menú contextual
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if mouse_event.pressed and not _is_pointer_over_ui():
			_show_context_menu(mouse_event.position, _screen_to_m_raw(mouse_event.position))
			get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _is_pointer_over_ui():
		return

	var pos_m: Vector2 = _screen_to_m_for_tool(mouse_event.position)
	if mouse_event.pressed:
		_handle_press(pos_m)
	else:
		_handle_release(pos_m)


func _handle_3d_editor_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_Y and key_event.ctrl_pressed or (
		key_event.keycode == KEY_Z and key_event.ctrl_pressed and key_event.shift_pressed
	):
		_redo_last_action()
		_sync_editor_runtime_views()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_Z and key_event.ctrl_pressed:
		_undo_last_action()
		_sync_editor_runtime_views()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE:
		_delete_selected_3d_simple()
		get_viewport().set_input_as_handled()


func _delete_selected_3d_simple() -> void:
	if selected_opening_index >= 0:
		if _delete_opening(selected_opening_index):
			_sync_editor_3d_after_direct_edit()
		return
	if selected_detector_index >= 0 \
			or selected_victim_index >= 0 \
			or selected_player_start_room_id >= 0 \
			or (selected_object_room_id >= 0 and selected_object_index >= 0):
		_delete_selected()
		_sync_editor_3d_after_direct_edit()
		return
	if selected_room_id >= 0 or selected_exterior_wall_index >= 0:
		_set_status("El borrado de geometría sigue reservado al modo 2D.")
		return
	_set_status("No hay ninguna apertura ni elemento simple seleccionado para borrar.")


func _input(event: InputEvent) -> void:
	if _editor_view_mode != EditorViewMode.MODE_2D:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or not _is_arrow_key(key_event.keycode):
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is OptionButton or focus_owner is ItemList or focus_owner is Button:
		get_viewport().set_input_as_handled()


func _is_arrow_key(keycode: int) -> bool:
	return keycode == KEY_LEFT or keycode == KEY_RIGHT or keycode == KEY_UP or keycode == KEY_DOWN


func _handle_press(pos_m: Vector2) -> void:
	match current_tool:
		Tool.EXTERIOR_WALL:
			is_dragging_exterior_wall = true
			drag_start_m = pos_m
			drag_current_m = pos_m
		Tool.ROOM, Tool.CORRIDOR_L, Tool.STAIRS:
			is_dragging_room = true
			drag_start_m = pos_m
			drag_current_m = pos_m
		Tool.SELECT:
			# Si el objeto ya está seleccionado, iniciar arrastre
			if selected_object_room_id >= 0 and selected_object_index >= 0:
				var handle_mode: int = _find_selected_object_handle_at(pos_m)
				if handle_mode != ObjectMouseMode.NONE:
					_begin_object_mouse_edit(handle_mode, pos_m)
					return
				var hit: Dictionary = _find_object_at(pos_m)
				if not hit.is_empty() and int(hit["room_id"]) == selected_object_room_id and int(hit["object_index"]) == selected_object_index:
					_begin_object_mouse_edit(ObjectMouseMode.MOVE, pos_m)
					return
			if selected_room_id >= 0:
				var room_handle_mode: int = _find_selected_room_handle_at(pos_m)
				if room_handle_mode != ObjectMouseMode.NONE:
					_begin_room_mouse_edit(room_handle_mode, pos_m)
					return
				if _has_non_room_selection_hit_at(pos_m):
					_select_at(pos_m)
					return
				var selected_room: Dictionary = _get_room(selected_room_id)
				if not selected_room.is_empty() and _rotated_rect_has_point(_get_room_rect(selected_room_id), _room_rotation_deg(selected_room_id), pos_m):
					_begin_room_mouse_edit(ObjectMouseMode.MOVE, pos_m)
					return
			_select_at(pos_m)
		Tool.DOOR:
			_create_door_at(pos_m)
		Tool.HOLE:
			_create_hole_at(pos_m)
		Tool.WINDOW:
			_create_window_at(pos_m)
		Tool.OBJECT:
			_create_object_at(pos_m)
		Tool.IGNITION:
			_mark_ignition_at(pos_m)
		Tool.PLAYER_START:
			_create_player_start_at(pos_m)
		Tool.DELETE:
			_delete_at(pos_m)
		Tool.DETECTOR:
			_create_detector_at(pos_m)
		Tool.VICTIM:
			_create_victim_at(pos_m)


func _handle_release(pos_m: Vector2) -> void:
	if is_dragging_room_geometry:
		var completed_mode: int = room_mouse_mode
		is_dragging_room_geometry = false
		room_mouse_mode = ObjectMouseMode.NONE
		room_drag_cursor_offset_m = Vector2.ZERO
		if completed_mode == ObjectMouseMode.ROTATE:
			_set_status("Ángulo de la habitación actualizado.")
		elif completed_mode == ObjectMouseMode.RESIZE_WIDTH or completed_mode == ObjectMouseMode.RESIZE_LENGTH:
			_set_status("Tamaño de la habitación actualizado.")
		else:
			_set_status("Habitación movida.")
		_refresh_element_list()
		queue_redraw()
		return

	if is_dragging_object:
		var completed_mode: int = object_mouse_mode
		is_dragging_object = false
		object_mouse_mode = ObjectMouseMode.NONE
		drag_object_cursor_offset_m = Vector2.ZERO
		if completed_mode == ObjectMouseMode.ROTATE:
			_set_status("Rotacion del objeto actualizada.")
		elif completed_mode == ObjectMouseMode.RESIZE_WIDTH or completed_mode == ObjectMouseMode.RESIZE_LENGTH:
			_set_status("Tamaño del objeto actualizado.")
		else:
			_set_status("Objeto movido.")
		queue_redraw()
		return

	if is_dragging_exterior_wall:
		drag_current_m = pos_m
		var start_wall_m: Vector2 = _snap_m(drag_start_m)
		var end_wall_m: Vector2 = _snap_m(drag_current_m)
		_clear_drag()
		if start_wall_m.distance_to(end_wall_m) < GRID_M:
			var wall_index: int = _find_exterior_wall_at(pos_m)
			if wall_index >= 0:
				_select_exterior_wall(wall_index)
			else:
				_set_status("Arrastra para dibujar un muro exterior.")
			queue_redraw()
			return
		_add_exterior_wall(start_wall_m, end_wall_m)
		queue_redraw()
		return

	if (current_tool != Tool.ROOM and current_tool != Tool.CORRIDOR_L and current_tool != Tool.STAIRS) or not is_dragging_room:
		return

	drag_current_m = pos_m
	var start_m: Vector2 = drag_start_m
	var end_m: Vector2 = drag_current_m
	var rect: Rect2 = _normalized_rect(start_m, end_m)
	_clear_drag()

	if current_tool == Tool.CORRIDOR_L:
		_push_undo_snapshot("create_corridor")
		_create_corridor_from_drag(start_m, end_m)
		queue_redraw()
		return

	if current_tool == Tool.STAIRS:
		var stair_dir: Vector2 = StairPlanRules.run_direction_from_drag(start_m, end_m, rect)
		var stair_long_m: float = StairGeometry.long_span_m(rect, stair_dir)
		var stair_cross_m: float = StairGeometry.cross_span_m(rect, stair_dir)
		if stair_long_m < GRID_M * 5.0 or stair_cross_m < GRID_M * 3.0:
			_set_status("La escalera es demasiado pequeña: arrastra al menos %.2f m de largo y %.2f m de ancho." % [GRID_M * 5.0, GRID_M * 3.0])
			queue_redraw()
			return
		_push_undo_snapshot("create_stairs")
		_create_stairs_from_rect(rect, start_m, end_m)
		queue_redraw()
		return

	if rect.size.x < GRID_M or rect.size.y < GRID_M:
		_set_status("La habitación es demasiado pequeña.")
		queue_redraw()
		return

	_push_undo_snapshot("create_room")
	var room_id: int = _create_room(_snap_rect_to_adjacent_rooms(rect))
	_select_room(room_id)
	_set_status("Habitación %d creada." % room_id)
	queue_redraw()


func _is_pointer_over_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null or _ui_root == null:
		return false
	if hovered == _ui_root:
		return false
	if _hover_help_popup != null and (hovered == _hover_help_popup or _hover_help_popup.is_ancestor_of(hovered)):
		return false
	return _ui_root.is_ancestor_of(hovered)


func _screen_to_m(screen_pos: Vector2) -> Vector2:
	return _snap_m(_screen_to_m_raw(screen_pos))


func _screen_to_m_raw(screen_pos: Vector2) -> Vector2:
	var local_px: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_pos
	return local_px / pixels_per_meter


func _screen_to_m_for_tool(screen_pos: Vector2) -> Vector2:
	match current_tool:
		Tool.SELECT, Tool.OBJECT, Tool.IGNITION, Tool.DETECTOR, Tool.VICTIM, Tool.PLAYER_START:
			return _screen_to_m_raw(screen_pos)
		_:
			return _screen_to_m(screen_pos)


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
	_ctx_exterior_wall_index = -1

	var menu := _get_context_menu()
	menu.clear()

	var hit_obj: Dictionary = _find_object_at(pos_m)
	var hit_opening: int = _find_opening_at(pos_m)
	var hit_wall: int = _find_exterior_wall_at(pos_m)
	var hit_room: int = _find_room_at(pos_m)

	if not hit_obj.is_empty():
		_ctx_room_id     = int(hit_obj.get("room_id", -1))
		_ctx_obj_index   = int(hit_obj.get("object_index", -1))
		var obj: Dictionary = _get_object(_ctx_room_id, _ctx_obj_index)
		menu.add_item("Mostrar propiedades: %s" % str(obj.get("name", "objeto")), _CTX_EDIT)
		menu.add_item("Duplicar objeto  [Ctrl+D]", _CTX_DUPLICATE)
		menu.add_separator()
		menu.add_item("Borrar objeto", _CTX_DELETE)
	elif hit_opening >= 0:
		_ctx_opening_index = hit_opening
		menu.add_item("Mostrar propiedades apertura", _CTX_EDIT)
		menu.add_separator()
		menu.add_item("Borrar apertura", _CTX_DELETE)
	elif hit_wall >= 0:
		_ctx_exterior_wall_index = hit_wall
		menu.add_item("Mostrar propiedades muro exterior", _CTX_EDIT)
		menu.add_separator()
		menu.add_item("Borrar muro exterior", _CTX_DELETE)
	elif hit_room >= 0:
		_ctx_room_id = hit_room
		var room: Dictionary = _get_room(hit_room)
		var rname: String = _room_display_name(room, hit_room)
		menu.add_item("Mostrar propiedades: %s" % rname, _CTX_EDIT)
		menu.add_separator()
		menu.add_item("Añadir puerta aquí", _CTX_ADD_DOOR)
		menu.add_item("Añadir hueco aquí", _CTX_ADD_HOLE)
		menu.add_item("Añadir ventana aquí", _CTX_ADD_WIN)
		menu.add_item("Punto inicio jugador aquí", _CTX_SET_PLAYER_START)
		menu.add_item("Marcar contorno exterior", _CTX_MARK_EXTERIOR)
		menu.add_item("Marcar ignición aquí", _CTX_IGNITE)
		menu.add_separator()
		menu.add_item("Duplicar habitación con lo que hay dentro  [Ctrl+D]", _CTX_DUPLICATE)
		menu.add_item("Borrar habitación", _CTX_DELETE)
	else:
		menu.add_item("Deseleccionar todo", _CTX_DESELECT)

	# Pegar solo aparece cuando hay algo copiado: una opcion que nunca hace nada
	# es una opcion que estorba.
	if not _clipboard.is_empty():
		menu.add_separator()
		menu.add_item("Pegar aquí: %s  [Ctrl+V]" % _payload_label(_clipboard), _CTX_PASTE)

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
			elif _ctx_exterior_wall_index >= 0:
				_select_exterior_wall(_ctx_exterior_wall_index)
			elif _ctx_room_id >= 0:
				_select_room(_ctx_room_id)
		_CTX_DELETE:
			if _ctx_obj_index >= 0:
				_select_object(_ctx_room_id, _ctx_obj_index)
				_delete_selected()
			elif _ctx_opening_index >= 0:
				_select_opening(_ctx_opening_index)
				_delete_selected()
			elif _ctx_exterior_wall_index >= 0:
				_select_exterior_wall(_ctx_exterior_wall_index)
				_delete_selected()
			elif _ctx_room_id >= 0:
				_select_room(_ctx_room_id)
				_delete_selected()
		_CTX_ADD_DOOR:
			_set_tool(Tool.DOOR)
			_create_door_at(_ctx_pos_m)
		_CTX_ADD_HOLE:
			_set_tool(Tool.HOLE)
			_create_hole_at(_ctx_pos_m)
		_CTX_ADD_WIN:
			_set_tool(Tool.WINDOW)
			_create_window_at(_ctx_pos_m)
		_CTX_IGNITE:
			_set_tool(Tool.IGNITION)
			_mark_ignition_at(_ctx_pos_m)
		_CTX_MARK_EXTERIOR:
			if _ctx_room_id >= 0:
				_mark_room_as_exterior(_ctx_room_id)
		_CTX_SET_PLAYER_START:
			if _ctx_room_id >= 0:
				_set_player_start_at(_ctx_room_id, _ctx_pos_m)
		_CTX_DUPLICATE:
			# Duplicar trabaja sobre la seleccion, asi que primero se selecciona
			# aquello sobre lo que se ha pulsado.
			if _ctx_obj_index >= 0:
				_select_object(_ctx_room_id, _ctx_obj_index)
			elif _ctx_room_id >= 0:
				_select_room(_ctx_room_id)
			_duplicate_selection()
		_CTX_PASTE:
			# Donde se pulso el boton derecho, no donde este el raton ahora: al
			# abrirse el menu el cursor ya se ha movido.
			_paste_clipboard_at(_ctx_pos_m)
		_CTX_DESELECT:
			_clear_selection()
			queue_redraw()


# ---------------------------------------------------------------------------
# Copiar, pegar y duplicar
# ---------------------------------------------------------------------------
## En un editor de plantas duplicar es la operacion que mas se repite: cuatro
## dormitorios iguales eran cuatro veces dibujar y cuatro veces ajustar las
## mismas propiedades.
##
## Tres verbos y un solo camino: copiar guarda la seleccion, pegar la inserta
## donde mira el usuario y duplicar hace las dos cosas al lado del original sin
## tocar lo copiado, que es lo que hace cualquier editor.


## Lo que se copia de la seleccion actual, listo para insertarse otra vez.
##
## Una habitacion se lleva lo que tiene dentro -objetos, detectores y victimas-,
## que es justo lo que hace cara la copia a mano. No se lleva sus puertas ni sus
## ventanas: una apertura une dos salas concretas por un paramento concreto, y
## copiarla dejaria una puerta a ninguna parte.
func _selection_payload() -> Dictionary:
	if selected_room_id >= 0:
		var room: Dictionary = _get_room(selected_room_id)
		if room.is_empty():
			return {}
		return {
			"kind": "room",
			"room": room.duplicate(true),
			"rect": Serializer.rect_to_data(_get_room_rect(selected_room_id)),
			"detectors": _elements_in_room("detectors", selected_room_id),
			"victims": _elements_in_room("victims", selected_room_id)
		}
	if selected_object_room_id >= 0 and selected_object_index >= 0:
		var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
		if obj.is_empty():
			return {}
		return {"kind": "object", "object": obj.duplicate(true), "room_id": selected_object_room_id}
	if selected_detector_index >= 0:
		var det: Dictionary = _element_at("detectors", selected_detector_index)
		if det.is_empty():
			return {}
		return {"kind": "detector", "detector": det.duplicate(true)}
	if selected_victim_index >= 0:
		var vic: Dictionary = _element_at("victims", selected_victim_index)
		if vic.is_empty():
			return {}
		return {"kind": "victim", "victim": vic.duplicate(true)}
	return {}


func _element_at(list_key: String, index: int) -> Dictionary:
	var items: Array = editor_data.get(list_key, [])
	if index < 0 or index >= items.size() or typeof(items[index]) != TYPE_DICTIONARY:
		return {}
	return items[index]


func _elements_in_room(list_key: String, room_id: int) -> Array:
	var found: Array = []
	for item in Array(editor_data.get(list_key, [])):
		if typeof(item) == TYPE_DICTIONARY and int(Dictionary(item).get("room_id", -1)) == room_id:
			found.append(Dictionary(item).duplicate(true))
	return found


func _payload_label(payload: Dictionary) -> String:
	match String(payload.get("kind", "")):
		"room":
			var room: Dictionary = payload.get("room", {})
			return "habitación «%s»" % _room_display_name(room, int(room.get("id", -1)))
		"object":
			var obj: Dictionary = payload.get("object", {})
			return "objeto %s" % String(obj.get("name", obj.get("id", "")))
		"detector":
			return "detector %s" % String(Dictionary(payload.get("detector", {})).get("id", ""))
		"victim":
			return "víctima %s" % String(Dictionary(payload.get("victim", {})).get("name", ""))
	return "nada"


func _copy_selection() -> void:
	var payload: Dictionary = _selection_payload()
	if payload.is_empty():
		_set_status("Copiar necesita algo seleccionado: una habitación, un objeto, un detector o una víctima.")
		return
	_clipboard = payload
	_set_status("Copiada la %s. Ctrl+V la pega donde esté el cursor." % _payload_label(payload))


func _paste_clipboard() -> void:
	_paste_clipboard_at(_mouse_pos_m())


func _paste_clipboard_at(pos_m: Vector2) -> void:
	if _clipboard.is_empty():
		_set_status("No hay nada copiado. Ctrl+C copia lo que esté seleccionado.")
		return
	_insert_payload(_clipboard, pos_m, false)


## Duplicar no toca el portapapeles: quien copia una cosa y duplica otra espera
## que Ctrl+V siga pegando la primera.
func _duplicate_selection() -> void:
	var payload: Dictionary = _selection_payload()
	if payload.is_empty():
		_set_status("Duplicar necesita algo seleccionado: una habitación, un objeto, un detector o una víctima.")
		return
	_insert_payload(payload, Vector2.ZERO, true)


## beside = al lado del original (duplicar). Si no, en pos_m (pegar).
func _insert_payload(payload: Dictionary, pos_m: Vector2, beside: bool) -> void:
	match String(payload.get("kind", "")):
		"room":
			_insert_room_payload(payload, pos_m, beside)
		"object":
			_insert_object_payload(payload, pos_m, beside)
		"detector":
			_insert_point_payload(payload, "detector", "detectors", pos_m, beside)
		"victim":
			_insert_point_payload(payload, "victim", "victims", pos_m, beside)
		_:
			_set_status("Eso no se puede pegar.")


## La copia cae en la planta que se esta editando, no en la del original: es lo
## que permite repetir la distribucion de la planta baja en la primera.
func _insert_room_payload(payload: Dictionary, pos_m: Vector2, beside: bool) -> void:
	var source_rect: Rect2 = Serializer.rect2_from_data(payload.get("rect", {}))
	if source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		_set_status("La habitación copiada no tiene geometría válida.")
		return
	var rect := source_rect
	if beside:
		rect.position = _snap_m(source_rect.position + Vector2(source_rect.size.x + GRID_M, 0.0))
	else:
		rect.position = _snap_m(pos_m)

	_push_undo_snapshot("duplicate_room" if beside else "paste_room")
	var room: Dictionary = Dictionary(payload.get("room", {})).duplicate(true)
	var new_id: int = _next_room_id()
	room["id"] = new_id
	room["name"] = _copy_name(String(room.get("name", "")), _room_names())
	room["floor_level_z_m"] = _current_floor_level_m()
	# El foco inicial no se clona: solo hay uno, y dos objetos marcados dejarian
	# el escenario contradiciendose consigo mismo.
	var objects: Array = []
	for obj in Array(room.get("fuel_objects", [])):
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var copy_obj: Dictionary = Dictionary(obj).duplicate(true)
		copy_obj["id"] = _next_object_id_including(objects)
		copy_obj["room_id"] = new_id
		copy_obj["is_primary_ignition_source"] = false
		objects.append(copy_obj)
	room["fuel_objects"] = objects

	var rooms: Array = editor_data.get("rooms_data", [])
	rooms.append(room)
	editor_data["rooms_data"] = rooms
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	rects[str(new_id)] = Serializer.rect_to_data(rect)
	editor_data["room_rect_m"] = rects

	# Detectores y victimas guardan su posicion local a la sala, asi que basta
	# apuntarlos a la copia para que caigan en el mismo sitio de la copia.
	var dets: Array = editor_data.get("detectors", [])
	for det in Array(payload.get("detectors", [])):
		var copy_det: Dictionary = Dictionary(det).duplicate(true)
		copy_det["id"] = _next_detector_id()
		copy_det["room_id"] = new_id
		dets.append(copy_det)
	editor_data["detectors"] = dets
	var vics: Array = editor_data.get("victims", [])
	for vic in Array(payload.get("victims", [])):
		var copy_vic: Dictionary = Dictionary(vic).duplicate(true)
		copy_vic["id"] = _next_victim_id()
		copy_vic["room_id"] = new_id
		copy_vic["name"] = _copy_name(String(copy_vic.get("name", "")), _victim_names())
		vics.append(copy_vic)
	editor_data["victims"] = vics

	_update_floor_status()
	_select_room(new_id)
	_set_status("Copiada como «%s» en %s, con %d objetos, %d detectores y %d víctimas. Las puertas y ventanas no se copian." % [
		String(room.get("name", "")),
		_current_floor_name(),
		objects.size(),
		Array(payload.get("detectors", [])).size(),
		Array(payload.get("victims", [])).size()
	])
	queue_redraw()


## Como _next_object_id(), contando ademas los que aun no estan en el arbol: al
## copiar una sala entera sus objetos se numeran antes de insertarse.
func _next_object_id_including(pending: Array) -> String:
	var taken: Dictionary = {}
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		for obj in Array(Dictionary(room).get("fuel_objects", [])):
			if typeof(obj) == TYPE_DICTIONARY:
				taken[String(Dictionary(obj).get("id", ""))] = true
	for pending_obj in pending:
		if typeof(pending_obj) == TYPE_DICTIONARY:
			taken[String(Dictionary(pending_obj).get("id", ""))] = true
	return _first_free_id("obj_%03d", taken)


func _insert_object_payload(payload: Dictionary, pos_m: Vector2, beside: bool) -> void:
	var room_id: int = int(payload.get("room_id", -1)) if beside else _find_room_at(pos_m)
	if room_id < 0 or _get_room(room_id).is_empty():
		_set_status("Pega el objeto dentro de una habitación de %s." % _current_floor_name())
		return
	var rect: Rect2 = _get_room_rect(room_id)
	var obj: Dictionary = Dictionary(payload.get("object", {})).duplicate(true)
	var size: Vector2 = _object_size_m(obj)
	var local: Vector2
	if beside:
		local = _snap_object_m(Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO)) + Vector2(0.5, 0.5))
	else:
		local = _snap_object_m(pos_m - rect.position - size * 0.5)
	_push_undo_snapshot("duplicate_object" if beside else "paste_object")
	obj["id"] = _next_object_id()
	obj["room_id"] = room_id
	obj["is_primary_ignition_source"] = false
	obj["position_m"] = Serializer.vector_to_data(_clamp_object_local_pos_for_rotation(
		rect, size, local, float(obj.get("rotation_deg", 0.0))
	))
	obj["visual_pose_locked"] = true
	_add_object_to_room(room_id, obj)
	_select_object(room_id, Array(_get_room(room_id).get("fuel_objects", [])).size() - 1)
	_set_status("Objeto %s copiado en la habitación %d." % [String(obj.get("id", "")), room_id])
	queue_redraw()


## Detectores y victimas comparten forma -id, room_id y un punto local dentro de
## la sala-, asi que comparten pegado.
func _insert_point_payload(payload: Dictionary, kind: String, list_key: String, pos_m: Vector2, beside: bool) -> void:
	var item: Dictionary = Dictionary(payload.get(kind, {})).duplicate(true)
	var room_id: int = int(item.get("room_id", -1)) if beside else _find_room_at(pos_m)
	if room_id < 0 or _get_room(room_id).is_empty():
		_set_status("Pega el elemento dentro de una habitación de %s." % _current_floor_name())
		return
	var rect: Rect2 = _get_room_rect(room_id)
	var local: Vector2
	if beside:
		local = Vector2(float(item.get("x_m", 0.0)), float(item.get("y_m", 0.0))) + Vector2(GRID_M, GRID_M)
	else:
		local = pos_m - rect.position
	local.x = clampf(snappedf(local.x, GRID_M), 0.0, maxf(0.0, rect.size.x))
	local.y = clampf(snappedf(local.y, GRID_M), 0.0, maxf(0.0, rect.size.y))
	_push_undo_snapshot(("duplicate_" if beside else "paste_") + kind)
	item["room_id"] = room_id
	item["x_m"] = local.x
	item["y_m"] = local.y
	var items: Array = editor_data.get(list_key, [])
	if kind == "detector":
		item["id"] = _next_detector_id()
	else:
		item["id"] = _next_victim_id()
		item["name"] = _copy_name(String(item.get("name", "")), _victim_names())
	items.append(item)
	editor_data[list_key] = items
	if kind == "detector":
		_select_detector(items.size() - 1)
		_set_status("Detector %s copiado en la habitación %d." % [String(item.get("id", "")), room_id])
	else:
		_select_victim(items.size() - 1)
		_set_status("Víctima %s copiada en la habitación %d." % [String(item.get("name", "")), room_id])
	queue_redraw()


## "Salón" -> "Salón (copia)" -> "Salón (copia 2)". El sufijo se recorta antes de
## volver a ponerlo, para que copiar una copia no encadene "(copia) (copia)".
func _copy_name(base_name: String, taken: Dictionary) -> String:
	var base: String = base_name.strip_edges()
	var suffix_at: int = base.rfind(" (copia")
	if suffix_at > 0 and base.ends_with(")"):
		base = base.substr(0, suffix_at)
	if base == "":
		base = "Copia"
	var candidate: String = "%s (copia)" % base
	var n: int = 2
	while taken.has(candidate):
		candidate = "%s (copia %d)" % [base, n]
		n += 1
	return candidate


func _room_names() -> Dictionary:
	var names: Dictionary = {}
	for room in editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY:
			names[String(Dictionary(room).get("name", ""))] = true
	return names


func _victim_names() -> Dictionary:
	var names: Dictionary = {}
	for vic in Array(editor_data.get("victims", [])):
		if typeof(vic) == TYPE_DICTIONARY:
			names[String(Dictionary(vic).get("name", ""))] = true
	return names


## Donde esta el raton, en metros del plano. Pegar donde mira el usuario es lo
## que hace cualquier editor de planos.
func _mouse_pos_m() -> Vector2:
	return _screen_to_m(get_viewport().get_mouse_position())


func _set_player_start_at(room_id: int, world_pos_m: Vector2) -> void:
	var room: Dictionary = _get_room(room_id)
	var rect: Rect2 = _get_room_rect(room_id)
	if room.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_push_undo_snapshot("set_player_start")
	var local_pos: Vector2 = world_pos_m - rect.position
	local_pos.x = clampf(local_pos.x, 0.0, rect.size.x)
	local_pos.y = clampf(local_pos.y, 0.0, rect.size.y)
	editor_data["player_start"] = {
		"room_id": room_id,
		"position_m": Serializer.vector_to_data(local_pos),
		"floor_level_z_m": float(room.get("floor_level_z_m", 0.0)),
		"yaw_deg": 0.0
	}
	_select_room(room_id)
	_set_status("Punto de inicio del jugador definido en %s." % _room_display_name(room, room_id))
	_refresh_element_list()
	queue_redraw()


func _create_player_start_at(pos_m: Vector2) -> void:
	var room_id: int = _find_room_at(pos_m)
	if room_id < 0:
		_set_status("Pulsa dentro de una estancia de la planta activa para colocar el inicio FP.")
		return
	_set_player_start_at(room_id, pos_m)


func _m_to_px(pos_m: Vector2) -> Vector2:
	return pos_m * pixels_per_meter


func _rect_to_px(rect_m: Rect2) -> Rect2:
	return Rect2(_m_to_px(rect_m.position), rect_m.size * pixels_per_meter)


func _snap_m(pos_m: Vector2) -> Vector2:
	return Vector2(snappedf(pos_m.x, GRID_M), snappedf(pos_m.y, GRID_M))


func _snap_object_m(pos_m: Vector2) -> Vector2:
	var step: float = maxf(0.0, object_move_snap_m)
	if step <= 0.0:
		return pos_m
	return Vector2(snappedf(pos_m.x, step), snappedf(pos_m.y, step))


func _snap_object_size_value(value_m: float) -> float:
	var step: float = maxf(0.0, object_resize_snap_m)
	if step <= 0.0:
		return maxf(0.10, value_m)
	return maxf(0.10, snappedf(value_m, step))


func _clean_object_rotation_deg(rotation_deg: float) -> float:
	var value: float = _normalize_degrees_signed(rotation_deg)
	var threshold: float = maxf(0.0, object_axis_snap_threshold_deg)
	for axis in [0.0, 90.0, -90.0, 180.0]:
		if absf(_normalize_degrees_signed(value - axis)) <= threshold:
			return _normalize_degrees_signed(axis)
	if absf(value) <= 0.001:
		return 0.0
	return value


func _snap_object_rotation_deg(rotation_deg: float) -> float:
	var value: float = _clean_object_rotation_deg(rotation_deg)
	var step: float = maxf(0.0, object_rotation_snap_deg)
	if step <= 0.0:
		return value
	return _clean_object_rotation_deg(snappedf(value, step))


func _normalized_rect(a: Vector2, b: Vector2) -> Rect2:
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var size := Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(pos, size)


func _clear_drag() -> void:
	is_dragging_room = false
	is_dragging_exterior_wall = false
	is_dragging_room_geometry = false
	is_dragging_object = false
	room_mouse_mode = ObjectMouseMode.NONE
	object_mouse_mode = ObjectMouseMode.NONE
	drag_object_cursor_offset_m = Vector2.ZERO
	drag_start_m = Vector2.ZERO
	drag_current_m = Vector2.ZERO


func _begin_room_mouse_edit(mode: int, pos_m: Vector2) -> void:
	if selected_room_id < 0:
		return
	var room: Dictionary = _get_room(selected_room_id)
	if room.is_empty():
		return
	var rect: Rect2 = _get_room_rect(selected_room_id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_push_undo_snapshot("edit_room_mouse")
	room_mouse_mode = mode
	is_dragging_room_geometry = true
	room_drag_start_rect_m = rect
	room_drag_start_center_m = rect.get_center()
	room_drag_start_rotation_deg = float(room.get("rotation_deg", 0.0))
	room_drag_cursor_offset_m = rect.position - pos_m


func _update_dragged_room_geometry(pos_m: Vector2) -> void:
	if selected_room_id < 0:
		is_dragging_room_geometry = false
		return
	match room_mouse_mode:
		ObjectMouseMode.RESIZE_WIDTH, ObjectMouseMode.RESIZE_LENGTH:
			_resize_selected_room_with_mouse(pos_m)
		ObjectMouseMode.ROTATE:
			_rotate_selected_room_with_mouse(pos_m)
		_:
			var new_pos: Vector2 = _snap_m(pos_m + room_drag_cursor_offset_m)
			var next_rect := Rect2(new_pos, room_drag_start_rect_m.size)
			if absf(_normalize_degrees_signed(room_drag_start_rotation_deg)) <= 0.001:
				next_rect = _snap_rect_to_adjacent_rooms(next_rect, selected_room_id)
			_set_room_rect(selected_room_id, next_rect)
	_sync_room_geometry_fields(selected_room_id)
	queue_redraw()


func _resize_selected_room_with_mouse(pos_m: Vector2) -> void:
	var local_mouse: Vector2 = _world_to_room_local(pos_m, room_drag_start_center_m, room_drag_start_rotation_deg)
	var new_size: Vector2 = room_drag_start_rect_m.size
	var center_shift_local := Vector2.ZERO
	if room_mouse_mode == ObjectMouseMode.RESIZE_WIDTH:
		new_size.x = maxf(0.25, local_mouse.x + room_drag_start_rect_m.size.x * 0.5)
		new_size.x = snappedf(new_size.x, GRID_M)
		center_shift_local.x = (new_size.x - room_drag_start_rect_m.size.x) * 0.5
	else:
		new_size.y = maxf(0.25, local_mouse.y + room_drag_start_rect_m.size.y * 0.5)
		new_size.y = snappedf(new_size.y, GRID_M)
		center_shift_local.y = (new_size.y - room_drag_start_rect_m.size.y) * 0.5
	var new_center_m: Vector2 = room_drag_start_center_m + Transform2D(deg_to_rad(room_drag_start_rotation_deg), Vector2.ZERO) * center_shift_local
	var next_rect := Rect2(_snap_m(new_center_m - new_size * 0.5), new_size)
	if absf(_normalize_degrees_signed(room_drag_start_rotation_deg)) <= 0.001:
		next_rect = _snap_rect_to_adjacent_rooms(next_rect, selected_room_id)
	_set_room_rect(selected_room_id, next_rect)


func _rotate_selected_room_with_mouse(pos_m: Vector2) -> void:
	var dir: Vector2 = pos_m - room_drag_start_center_m
	if dir.length_squared() < 0.0001:
		return
	var rotation_deg: float = snappedf(rad_to_deg(atan2(dir.y, dir.x)) + 90.0, 1.0)
	var room: Dictionary = _get_room(selected_room_id)
	if StairPlanRules.is_stair_room(room):
		rotation_deg = snappedf(rotation_deg / 90.0, 1.0) * 90.0
	_set_room_rotation(selected_room_id, _normalize_degrees_signed(rotation_deg))


func _world_to_room_local(pos_m: Vector2, center_m: Vector2, rotation_deg: float) -> Vector2:
	return Transform2D(deg_to_rad(-rotation_deg), Vector2.ZERO) * (pos_m - center_m)


func _set_room_rect(room_id: int, rect: Rect2) -> void:
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	var snapped_rect := Rect2(_snap_m(rect.position), Vector2(maxf(0.25, snappedf(rect.size.x, GRID_M)), maxf(0.25, snappedf(rect.size.y, GRID_M))))
	rects[str(room_id)] = Serializer.rect_to_data(snapped_rect)
	editor_data["room_rect_m"] = rects
	var room: Dictionary = _get_room(room_id)
	if StairPlanRules.is_stair_room(room):
		_sync_linked_stair_rects(room_id, snapped_rect)
		_sync_vertical_stair_openings(room_id)


func _set_room_rotation(room_id: int, rotation_deg: float) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	var stair_dir: Vector2 = StairPlanRules.direction_from_rotation(rotation_deg)
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		room["rotation_deg"] = rotation_deg
		if StairPlanRules.is_stair_room(room):
			room["stair_run_direction_m"] = Serializer.vector_to_data(stair_dir)
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		if StairPlanRules.is_stair_room(room):
			_apply_stair_rotation_to_linked_rooms(room_id, rotation_deg, stair_dir)
			_sync_vertical_stair_openings(room_id)
		return


func _sync_room_geometry_fields(room_id: int) -> void:
	if selected_room_id != room_id:
		return
	if _get_room(room_id).is_empty():
		return
	_props.fill_room_rect(_get_room_rect(room_id))


func _begin_object_mouse_edit(mode: int, pos_m: Vector2) -> void:
	if selected_object_room_id < 0 or selected_object_index < 0:
		return
	var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
	if obj.is_empty():
		return
	var rr: Rect2 = _get_room_rect(selected_object_room_id)
	var obj_pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
	var size: Vector2 = _object_size_m(obj)
	_push_undo_snapshot("edit_object_mouse")
	object_mouse_mode = mode
	is_dragging_object = true
	drag_object_cursor_offset_m = (rr.position + obj_pos) - pos_m
	object_drag_start_center_m = _object_world_center(rr, obj)
	object_drag_start_size_m = size
	object_drag_start_rotation_deg = float(obj.get("rotation_deg", 0.0))


func _update_dragged_object(pos_m: Vector2) -> void:
	if selected_object_room_id < 0 or selected_object_index < 0:
		is_dragging_object = false
		return
	var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
	if obj.is_empty():
		is_dragging_object = false
		return
	var rr: Rect2 = _get_room_rect(selected_object_room_id)
	match object_mouse_mode:
		ObjectMouseMode.RESIZE_WIDTH, ObjectMouseMode.RESIZE_LENGTH:
			_resize_selected_object_with_mouse(pos_m, rr)
		ObjectMouseMode.ROTATE:
			_rotate_selected_object_with_mouse(pos_m)
		_:
			var size: Vector2 = _object_size_m(obj)
			var new_world_m: Vector2 = _snap_object_m(pos_m + drag_object_cursor_offset_m)
			var new_local_m: Vector2 = new_world_m - rr.position
			new_local_m = _clamp_object_local_pos_for_rotation(rr, size, new_local_m, float(obj.get("rotation_deg", 0.0)))
			_set_object_position(selected_object_room_id, selected_object_index, new_local_m, true)
	_sync_object_property_fields(_get_object(selected_object_room_id, selected_object_index))
	queue_redraw()


func _resize_selected_object_with_mouse(pos_m: Vector2, rr: Rect2) -> void:
	var current_obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
	if current_obj.is_empty():
		return
	var local_mouse: Vector2 = _world_to_object_local(pos_m, object_drag_start_center_m, object_drag_start_rotation_deg)
	var new_size: Vector2 = object_drag_start_size_m
	var center_shift_local := Vector2.ZERO
	if object_mouse_mode == ObjectMouseMode.RESIZE_WIDTH:
		new_size.x = local_mouse.x + object_drag_start_size_m.x * 0.5
		new_size.x = clampf(_snap_object_size_value(new_size.x), 0.10, maxf(0.10, rr.size.x))
		center_shift_local.x = (new_size.x - object_drag_start_size_m.x) * 0.5
	else:
		new_size.y = local_mouse.y + object_drag_start_size_m.y * 0.5
		new_size.y = clampf(_snap_object_size_value(new_size.y), 0.10, maxf(0.10, rr.size.y))
		center_shift_local.y = (new_size.y - object_drag_start_size_m.y) * 0.5
	var rotation_deg: float = _clean_object_rotation_deg(float(current_obj.get("rotation_deg", object_drag_start_rotation_deg)))
	var new_center_world_m: Vector2 = object_drag_start_center_m + _object_transform(rotation_deg) * center_shift_local
	var new_local_pos: Vector2 = new_center_world_m - rr.position - new_size * 0.5
	new_local_pos = _clamp_object_local_pos_for_rotation(rr, new_size, new_local_pos, rotation_deg)
	_set_object_geometry(
		selected_object_room_id,
		selected_object_index,
		new_local_pos,
		new_size,
		rotation_deg,
		float(current_obj.get("elevation_m", 0.0)),
		true
	)


func _rotate_selected_object_with_mouse(pos_m: Vector2) -> void:
	var dir: Vector2 = pos_m - object_drag_start_center_m
	if dir.length_squared() < 0.0001:
		return
	var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
	if obj.is_empty():
		return
	var rotation_deg: float = _snap_object_rotation_deg(rad_to_deg(atan2(dir.y, dir.x)) + 90.0)
	_set_object_rotation(selected_object_room_id, selected_object_index, rotation_deg)


func _set_object_position(room_id: int, obj_index: int, local_pos: Vector2, visual_pose_locked: bool = false) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		if obj_index >= 0 and obj_index < objects.size() and typeof(objects[obj_index]) == TYPE_DICTIONARY:
			var obj: Dictionary = objects[obj_index]
			obj["position_m"] = Serializer.vector_to_data(local_pos)
			if visual_pose_locked:
				obj["visual_pose_locked"] = true
			objects[obj_index] = obj
			room["fuel_objects"] = objects
			rooms[i] = room
			editor_data["rooms_data"] = rooms
		return


func _set_object_rotation(room_id: int, obj_index: int, rotation_deg: float) -> void:
	var obj: Dictionary = _get_object(room_id, obj_index)
	if obj.is_empty():
		return
	_set_object_geometry(
		room_id,
		obj_index,
		Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO)),
		_object_size_m(obj),
		rotation_deg,
		float(obj.get("elevation_m", 0.0))
	)


func _set_object_geometry(room_id: int, obj_index: int, local_pos: Vector2, size_m: Vector2, rotation_deg: float, elevation_m: float, visual_pose_locked: bool = true) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		var objects: Array = room.get("fuel_objects", [])
		if obj_index < 0 or obj_index >= objects.size() or typeof(objects[obj_index]) != TYPE_DICTIONARY:
			return
		var obj: Dictionary = objects[obj_index]
		var clean_rotation_deg: float = _clean_object_rotation_deg(rotation_deg)
		var clean_size_m := Vector2(maxf(0.10, size_m.x), maxf(0.10, size_m.y))
		var clamped_pos: Vector2 = _clamp_object_local_pos_for_rotation(_get_room_rect(room_id), clean_size_m, local_pos, clean_rotation_deg)
		obj["position_m"] = Serializer.vector_to_data(clamped_pos)
		obj["size_m"] = Serializer.vector_to_data(clean_size_m)
		obj["rotation_deg"] = clean_rotation_deg
		obj["elevation_m"] = maxf(0.0, elevation_m)
		obj["footprint_m2"] = maxf(0.0, clean_size_m.x * clean_size_m.y)
		if visual_pose_locked:
			obj["visual_pose_locked"] = true
		objects[obj_index] = obj
		room["fuel_objects"] = objects
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		return


func _clamp_object_local_pos(room_rect: Rect2, size_m: Vector2, local_pos: Vector2) -> Vector2:
	return _clamp_object_local_pos_for_rotation(room_rect, size_m, local_pos, 0.0)


func _clamp_object_local_pos_for_rotation(room_rect: Rect2, size_m: Vector2, local_pos: Vector2, rotation_deg: float) -> Vector2:
	var clamped_size := Vector2(maxf(0.05, size_m.x), maxf(0.05, size_m.y))
	var center: Vector2 = local_pos + clamped_size * 0.5
	var extents: Vector2 = _rotated_object_aabb_size(clamped_size, rotation_deg)
	var min_center: Vector2 = extents * 0.5
	var max_center: Vector2 = room_rect.size - extents * 0.5
	if max_center.x < min_center.x:
		center.x = room_rect.size.x * 0.5
	else:
		center.x = clampf(center.x, min_center.x, max_center.x)
		if center.x - min_center.x <= OBJECT_WALL_SNAP_M:
			center.x = min_center.x
		elif max_center.x - center.x <= OBJECT_WALL_SNAP_M:
			center.x = max_center.x
	if max_center.y < min_center.y:
		center.y = room_rect.size.y * 0.5
	else:
		center.y = clampf(center.y, min_center.y, max_center.y)
		if center.y - min_center.y <= OBJECT_WALL_SNAP_M:
			center.y = min_center.y
		elif max_center.y - center.y <= OBJECT_WALL_SNAP_M:
			center.y = max_center.y
	return center - clamped_size * 0.5


func _rotated_object_aabb_size(size_m: Vector2, rotation_deg: float) -> Vector2:
	var angle: float = deg_to_rad(rotation_deg)
	var c: float = absf(cos(angle))
	var s: float = absf(sin(angle))
	return Vector2(size_m.x * c + size_m.y * s, size_m.x * s + size_m.y * c)


func _object_visual_min_from_local_pos(size_m: Vector2, local_pos: Vector2, rotation_deg: float) -> Vector2:
	return local_pos + size_m * 0.5 - _rotated_object_aabb_size(size_m, rotation_deg) * 0.5


func _object_local_pos_from_visual_min(size_m: Vector2, visual_min: Vector2, rotation_deg: float) -> Vector2:
	return visual_min + _rotated_object_aabb_size(size_m, rotation_deg) * 0.5 - size_m * 0.5


func _create_room(rect: Rect2, room_name: String = "", kind_name: String = "generic") -> int:
	return _create_room_at_level(rect, room_name, kind_name, _current_floor_level_m())


func _create_room_at_level(rect: Rect2, room_name: String = "", kind_name: String = "generic", floor_level_m: float = 0.0, height_m: float = 2.7) -> int:
	var id: int = _next_room_id()
	var rooms: Array = editor_data.get("rooms_data", [])
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	var room := {
		"id": id,
		"name": room_name if room_name != "" else "Room %d" % id,
		"kind": kind_name,
		"rotation_deg": 0.0,
		"height_m": height_m,
		"floor_level_z_m": floor_level_m,
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


func _create_stairs_from_rect(rect: Rect2, start_m: Vector2, end_m: Vector2) -> void:
	var lower_level_m: float = _current_floor_level_m()
	var upper_floor_index: int = _next_floor_index_above(lower_level_m)
	if upper_floor_index < 0:
		upper_floor_index = _add_floor_at_level(lower_level_m + DEFAULT_FLOOR_HEIGHT_M)
	var floors: Array = _get_floors()
	var upper_level_m: float = float(Dictionary(floors[upper_floor_index]).get("level_m", lower_level_m + DEFAULT_FLOOR_HEIGHT_M))
	var lower_name: String = "Escalera %s" % _current_floor_name()
	var upper_name: String = "Escalera %s" % String(Dictionary(floors[upper_floor_index]).get("name", _default_floor_name(upper_floor_index)))
	var lower_id: int = _create_room_at_level(rect, lower_name, "escalera", lower_level_m, minf(upper_level_m - lower_level_m, 3.2))
	var upper_id: int = _create_room_at_level(rect, upper_name, "escalera", upper_level_m, 2.55)
	var stair_dir: Vector2 = StairPlanRules.run_direction_from_drag(start_m, end_m, rect)
	var turn_mode: String = _selected_stair_tool_turn_mode()
	var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, turn_mode)
	_apply_stair_defaults_to_room(lower_id, stair_dir, turn_degrees)
	_apply_stair_defaults_to_room(upper_id, stair_dir, turn_degrees)
	_set_stair_turn_mode_for_room(lower_id, turn_mode)
	_set_stair_turn_mode_for_room(upper_id, turn_mode)
	_add_vertical_stair_opening(lower_id, upper_id, rect)
	_select_room(lower_id)
	_sync_floor_controls()
	_set_status("Escalera creada: %s. Se recorta hueco vertical de paso en suelos/techos solapados." % ("dos tramos con descansillo 180" if turn_degrees >= 179.0 else "tramo recto"))


func _apply_stair_defaults_to_room(room_id: int, stair_dir: Vector2, turn_degrees: float = 0.0) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		room["stair_run_direction_m"] = Serializer.vector_to_data(stair_dir)
		room["stair_has_walls"] = false
		room["stair_has_railings"] = true
		room["stair_turn_degrees"] = turn_degrees
		if not room.has("stair_turn_mode"):
			room["stair_turn_mode"] = StairPlanRules.turn_mode_from_degrees(turn_degrees)
		room["stair_flight_count"] = 2 if turn_degrees >= 179.0 else 1
		room["rotation_deg"] = _normalize_degrees_signed(rad_to_deg(atan2(stair_dir.y, stair_dir.x)) - 90.0)
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		return


func _selected_stair_tool_turn_mode() -> String:
	return _stair_turn_mode_from_option(_stair_tool_turn_option)


func _select_stair_turn_option(option: OptionButton, mode: String) -> void:
	if option == null:
		return
	_populate_stair_turn_options(option)
	var target_id: int = 0
	match StairPlanRules.normalized_turn_mode(mode):
		StairPlanRules.MODE_STRAIGHT:
			target_id = 1
		StairPlanRules.MODE_SWITCHBACK:
			target_id = 2
	for i in range(option.get_item_count()):
		if option.get_item_id(i) == target_id:
			option.select(i)
			return


func _populate_stair_turn_options(option: OptionButton) -> void:
	if option == null or option.get_item_count() > 0:
		return
	option.add_item("Auto", 0)
	option.add_item("Recta", 1)
	option.add_item("180°", 2)


func _set_stair_turn_mode_for_room(room_id: int, mode: String) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		room["stair_turn_mode"] = StairPlanRules.normalized_turn_mode(mode)
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		return


func _set_stair_turn_degrees_for_room(room_id: int, turn_degrees: float) -> void:
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY or int(rooms[i].get("id", -1)) != room_id:
			continue
		var room: Dictionary = rooms[i]
		room["stair_turn_degrees"] = turn_degrees
		room["stair_flight_count"] = 2 if turn_degrees >= 179.0 else 1
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		return


func _next_floor_index_above(level_m: float) -> int:
	var floors: Array = _get_floors()
	var best_index: int = -1
	var best_level: float = INF
	for i in range(floors.size()):
		if typeof(floors[i]) != TYPE_DICTIONARY:
			continue
		var floor_level_m: float = float(Dictionary(floors[i]).get("level_m", 0.0))
		if floor_level_m > level_m + 0.20 and floor_level_m < best_level:
			best_level = floor_level_m
			best_index = i
	return best_index


func _add_floor_at_level(level_m: float) -> int:
	var floors: Array = _get_floors()
	floors.append({"name": _default_floor_name(floors.size()), "level_m": level_m})
	floors.sort_custom(func(a, b): return float(Dictionary(a).get("level_m", 0.0)) < float(Dictionary(b).get("level_m", 0.0)))
	editor_data["floors"] = floors
	for i in range(floors.size()):
		if absf(float(Dictionary(floors[i]).get("level_m", 0.0)) - level_m) < 0.05:
			return i
	return floors.size() - 1


func _add_vertical_stair_opening(lower_id: int, upper_id: int, rect: Rect2) -> void:
	var openings: Array = editor_data.get("openings_data", [])
	for raw_op in openings:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		if bool(op.get("is_vertical", false)) and int(op.get("a", -1)) == lower_id and int(op.get("b", -1)) == upper_id:
			return
	var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(_get_room(lower_id))
	var turn_degrees: float = float(_get_room(lower_id).get("stair_turn_degrees", 0.0))
	var void_rect: Rect2 = StairGeometry.vertical_void_rect(rect, stair_dir, turn_degrees)
	openings.append({
		"a": lower_id,
		"b": upper_id,
		"type": "hole",
		"width_m": void_rect.size.x if absf(stair_dir.y) >= absf(stair_dir.x) else void_rect.size.y,
		"height_m": void_rect.size.y if absf(stair_dir.y) >= absf(stair_dir.x) else void_rect.size.x,
		"open_fraction": 1.0,
		"offset_is_fraction": false,
		"is_vertical": true
	})
	editor_data["openings_data"] = openings


func _copy_stairs_from_level_to_level(lower_level_m: float, upper_level_m: float) -> void:
	var lower_stairs: Array[Dictionary] = []
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if absf(float(room_dict.get("floor_level_z_m", 0.0)) - lower_level_m) < 0.05 and StairPlanRules.is_stair_room(room_dict):
			lower_stairs.append(room_dict)
	if lower_stairs.is_empty():
		return

	for lower_room in lower_stairs:
		var lower_id: int = int(lower_room.get("id", -1))
		var rect: Rect2 = _get_room_rect(lower_id)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var upper_id: int = _find_matching_stair_room_at_level(rect, upper_level_m)
		if upper_id < 0:
			var floor_name: String = _floor_name_for_level(upper_level_m)
			upper_id = _create_room_at_level(rect, "Escalera %s" % floor_name, "escalera", upper_level_m, 2.55)
		var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(lower_room)
		var turn_mode: String = StairPlanRules.turn_mode_for_room(lower_room)
		var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, turn_mode)
		_apply_stair_defaults_to_room(lower_id, stair_dir, turn_degrees)
		_apply_stair_defaults_to_room(upper_id, stair_dir, turn_degrees)
		_set_stair_turn_mode_for_room(lower_id, turn_mode)
		_set_stair_turn_mode_for_room(upper_id, turn_mode)
		_add_vertical_stair_opening(lower_id, upper_id, rect)


func _find_matching_stair_room_at_level(rect: Rect2, level_m: float) -> int:
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if not StairPlanRules.is_stair_room(room_dict):
			continue
		if absf(float(room_dict.get("floor_level_z_m", 0.0)) - level_m) >= 0.05:
			continue
		var other_rect: Rect2 = _get_room_rect(int(room_dict.get("id", -1)))
		if rect.position.distance_to(other_rect.position) <= 0.05 and rect.size.distance_to(other_rect.size) <= 0.05:
			return int(room_dict.get("id", -1))
	return -1


func _linked_vertical_stair_room_ids(room_id: int) -> Array[int]:
	var ids: Array[int] = []
	for raw_op in editor_data.get("openings_data", []):
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		if not bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", -1))
		if a_id == room_id and b_id >= 0:
			ids.append(b_id)
		elif b_id == room_id and a_id >= 0:
			ids.append(a_id)
	return ids


func _sync_linked_stair_rects(room_id: int, rect: Rect2) -> void:
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	for linked_id in _linked_vertical_stair_room_ids(room_id):
		var linked_room: Dictionary = _get_room(linked_id)
		if StairPlanRules.is_stair_room(linked_room):
			rects[str(linked_id)] = Serializer.rect_to_data(rect)
	editor_data["room_rect_m"] = rects


func _apply_stair_rotation_to_linked_rooms(room_id: int, rotation_deg: float, stair_dir: Vector2) -> void:
	var linked_ids: Array[int] = _linked_vertical_stair_room_ids(room_id)
	if linked_ids.is_empty():
		return
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var linked_id: int = int(Dictionary(rooms[i]).get("id", -1))
		if linked_ids.find(linked_id) < 0:
			continue
		var room: Dictionary = rooms[i]
		if not StairPlanRules.is_stair_room(room):
			continue
		room["rotation_deg"] = rotation_deg
		room["stair_run_direction_m"] = Serializer.vector_to_data(stair_dir)
		rooms[i] = room
	editor_data["rooms_data"] = rooms


func _sync_vertical_stair_openings(room_id: int) -> void:
	var openings: Array = editor_data.get("openings_data", [])
	var changed: bool = false
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = openings[i]
		if not bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", -1))
		if a_id != room_id and b_id != room_id:
			continue
		var lower_id: int = a_id
		if _room_id_floor_level(b_id) < _room_id_floor_level(a_id):
			lower_id = b_id
		var rect: Rect2 = _get_room_rect(lower_id)
		var lower_room: Dictionary = _get_room(lower_id)
		var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(lower_room)
		var turn_mode: String = StairPlanRules.turn_mode_for_room(lower_room)
		var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, turn_mode)
		_set_stair_turn_degrees_for_room(lower_id, turn_degrees)
		var other_id: int = b_id if lower_id == a_id else a_id
		if other_id >= 0:
			_set_stair_turn_mode_for_room(other_id, turn_mode)
			_set_stair_turn_degrees_for_room(other_id, turn_degrees)
		var void_rect: Rect2 = StairGeometry.vertical_void_rect(rect, stair_dir, turn_degrees)
		op["width_m"] = void_rect.size.x if absf(stair_dir.y) >= absf(stair_dir.x) else void_rect.size.y
		op["height_m"] = void_rect.size.y if absf(stair_dir.y) >= absf(stair_dir.x) else void_rect.size.x
		openings[i] = op
		changed = true
	if changed:
		editor_data["openings_data"] = openings


func _floor_name_for_level(level_m: float) -> String:
	var floors: Array = _get_floors()
	for i in range(floors.size()):
		if typeof(floors[i]) == TYPE_DICTIONARY and absf(float(Dictionary(floors[i]).get("level_m", 0.0)) - level_m) < 0.05:
			return String(Dictionary(floors[i]).get("name", _default_floor_name(i)))
	return _default_floor_name(floors.size())


func _create_corridor_from_drag(start_m: Vector2, end_m: Vector2) -> void:
	var layout: Dictionary = _build_corridor_layout(start_m, end_m)
	if layout.has("error"):
		_set_status(String(layout["error"]))
		return

	var rects: Array = layout.get("rects", [])
	if rects.is_empty():
		_set_status("El pasillo no tiene tamaño suficiente.")
		return

	var base_id: int = _next_room_id()
	var base_name: String = "Pasillo %d" % base_id
	var mode: String = String(layout.get("mode", "straight"))
	if mode == "straight":
		var corridor_id: int = _create_room(_snap_rect_to_adjacent_rooms(Rect2(rects[0])), base_name, "corridor")
		_select_room(corridor_id)
		_set_status("%s creado como tramo recto de %.2f m." % [base_name, float(layout.get("length_m", 0.0))])
		return

	var first_id: int = _create_room(_snap_rect_to_adjacent_rooms(Rect2(rects[0])), "%s tramo A" % base_name, "corridor")
	var second_id: int = _create_room(_snap_rect_to_adjacent_rooms(Rect2(rects[1])), "%s tramo B" % base_name, "corridor")
	var shared: Dictionary = _shared_wall_between(first_id, second_id)
	if not shared.is_empty():
		var max_width_m: float = _max_opening_width_for_shared(first_id, second_id, String(shared["wall"]))
		_add_opening(
			first_id,
			second_id,
			"hole",
			String(shared["wall"]),
			float(shared["offset_m"]),
			minf(corridor_width_m, max_width_m),
			2.05,
			0.0,
			1.0,
			false
		)
	_select_room(first_id)
	_set_status("%s creado en L como tramos %d y %d." % [base_name, first_id, second_id])


func _snap_rect_to_adjacent_rooms(rect: Rect2, skip_room_id: int = -2147483648) -> Rect2:
	var min_size: float = GRID_M * 2.0
	var left: float   = rect.position.x
	var right: float  = rect.position.x + rect.size.x
	var top: float    = rect.position.y
	var bottom: float = rect.position.y + rect.size.y

	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if not _is_room_on_current_floor(room):
			continue
		var room_id: int = int(room.get("id", -1))
		if room_id == skip_room_id:
			continue
		var r: Rect2 = _get_room_rect(room_id)
		var r_right:  float = r.position.x + r.size.x
		var r_bottom: float = r.position.y + r.size.y

		# ── Eje X: requiere solape vertical suficiente ──
		var y_overlap: float = minf(bottom, r_bottom) - maxf(top, r.position.y)
		if y_overlap >= _CONN_MIN_SHARED:
			# Arista izquierda del nuevo rect → arista derecha de sala existente
			if absf(left - r_right) < _CONN_GAP_TOL and right - r_right >= min_size:
				left = r_right
			# Arista derecha del nuevo rect → arista izquierda de sala existente
			if absf(right - r.position.x) < _CONN_GAP_TOL and r.position.x - left >= min_size:
				right = r.position.x

		# ── Eje Y: requiere solape horizontal suficiente ──
		var x_overlap: float = minf(right, r_right) - maxf(left, r.position.x)
		if x_overlap >= _CONN_MIN_SHARED:
			# Arista superior del nuevo rect → arista inferior de sala existente
			if absf(top - r_bottom) < _CONN_GAP_TOL and bottom - r_bottom >= min_size:
				top = r_bottom
			# Arista inferior del nuevo rect → arista superior de sala existente
			if absf(bottom - r.position.y) < _CONN_GAP_TOL and r.position.y - top >= min_size:
				bottom = r.position.y

	return Rect2(Vector2(left, top), Vector2(maxf(min_size, right - left), maxf(min_size, bottom - top)))


func _build_corridor_layout(start_m: Vector2, end_m: Vector2) -> Dictionary:
	var dx: float = end_m.x - start_m.x
	var dy: float = end_m.y - start_m.y
	var width_m: float = maxf(GRID_M, corridor_width_m)
	var abs_dx: float = absf(dx)
	var abs_dy: float = absf(dy)
	if abs_dx < GRID_M and abs_dy < GRID_M:
		return {"error": "Arrastra para marcar la dirección del pasillo."}

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
		return {"error": "El giro del pasillo queda demasiado pequeño."}

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


## Primer id libre, no "cuantos hay mas uno". El contador simple repetia id en
## cuanto se borraba algo, y duplicar multiplica esas coincidencias.
func _next_object_id() -> String:
	var taken: Dictionary = {}
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		for obj in Array(room.get("fuel_objects", [])):
			if typeof(obj) == TYPE_DICTIONARY:
				taken[String(Dictionary(obj).get("id", ""))] = true
	return _first_free_id("obj_%03d", taken)


## El primer "<patron> %03d" que nadie use.
func _first_free_id(pattern: String, taken: Dictionary) -> String:
	var n: int = 1
	while taken.has(pattern % n):
		n += 1
	return pattern % n


func _select_at(pos_m: Vector2) -> void:
	var det_index: int = _find_detector_at(pos_m)
	if det_index >= 0:
		_select_detector(det_index)
		return

	var vic_index: int = _find_victim_at(pos_m)
	if vic_index >= 0:
		_select_victim(vic_index)
		return

	var hit_obj: Dictionary = _find_object_at(pos_m)
	if not hit_obj.is_empty():
		_select_object(int(hit_obj["room_id"]), int(hit_obj["object_index"]))
		return

	var opening_index: int = _find_opening_at(pos_m)
	if opening_index >= 0:
		_select_opening(opening_index)
		return

	var exterior_wall_index: int = _find_exterior_wall_at(pos_m)
	if exterior_wall_index >= 0:
		_select_exterior_wall(exterior_wall_index)
		return

	if _player_start_hit_test(pos_m):
		var start: Dictionary = Dictionary(editor_data.get("player_start", {})) if typeof(editor_data.get("player_start", {})) == TYPE_DICTIONARY else {}
		_select_player_start(int(start.get("room_id", -1)))
		return

	var room_id: int = _find_room_at(pos_m)
	if room_id >= 0:
		_select_room(room_id)
	else:
		_clear_selection()
		_set_status("Sin selección.")
	queue_redraw()


func _has_non_room_selection_hit_at(pos_m: Vector2) -> bool:
	return _find_detector_at(pos_m) >= 0 \
		or _find_victim_at(pos_m) >= 0 \
		or not _find_object_at(pos_m).is_empty() \
		or _find_opening_at(pos_m) >= 0 \
		or _find_exterior_wall_at(pos_m) >= 0 \
		or _player_start_hit_test(pos_m)


func _select_room(room_id: int) -> void:
	selected_room_id = room_id
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	_set_status("Habitación %d seleccionada. Ajusta X/Y, ancho, fondo y ángulo en Propiedades." % room_id)
	queue_redraw()


func _select_opening(index: int) -> void:
	selected_room_id = -1
	selected_opening_index = index
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	var opening: Dictionary = Array(editor_data.get("openings_data", []))[index]
	_set_status("Seleccionada apertura %d (%s)." % [index, String(opening.get("type", "door"))])
	queue_redraw()


func _select_object(room_id: int, object_index: int) -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = room_id
	selected_object_index = object_index
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	var obj: Dictionary = _get_object(room_id, object_index)
	_set_status("Seleccionado objeto %s." % String(obj.get("name", obj.get("id", ""))))
	queue_redraw()


func _clear_selection() -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()


func _select_player_start(room_id: int) -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = room_id
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	_set_status("Inicio FP seleccionado. Arrástralo en 3D para cambiar el punto de aparición.")
	queue_redraw()


## Junta lo que hay seleccionado y se lo pasa al panel, que solo sabe de mandos.
##
## Lo que el panel no puede calcular por su cuenta va calculado aqui: el
## rectangulo de la sala, si es escalera, el texto del angulo, la posicion visual
## del objeto -que depende de su giro- y los topes de la apertura.
func _refresh_property_panel() -> void:
	var room: Dictionary = _get_room(selected_room_id)
	var has_room: bool = not room.is_empty()
	var obj: Dictionary = {}
	if selected_object_room_id >= 0 and selected_object_index >= 0:
		obj = _get_object(selected_object_room_id, selected_object_index)
	var state: Dictionary = {
		"room": room,
		"room_rect": _get_room_rect(selected_room_id) if has_room else Rect2(),
		"room_rotation_deg": _normalize_degrees_signed(float(room.get("rotation_deg", 0.0))) if has_room else 0.0,
		"room_is_stair": has_room and StairPlanRules.is_stair_room(room),
		"stair_turn_item_id": _stair_turn_item_id_for_mode(StairPlanRules.turn_mode_for_room(room)) if has_room else 0,
		"stair_angle_text": _stair_angle_text(selected_room_id, room) if has_room else "",
		"object": obj,
		"opening": _element_at("openings_data", selected_opening_index),
		"detector": _element_at("detectors", selected_detector_index),
		"victim": _element_at("victims", selected_victim_index),
		"wall": _element_at("exterior_walls", selected_exterior_wall_index)
	}
	if not obj.is_empty():
		var size_m: Vector2 = _object_size_m(obj)
		state["object_size"] = size_m
		state["object_rotation_deg"] = _normalize_degrees_signed(float(obj.get("rotation_deg", 0.0)))
		state["object_visual_pos"] = _object_visual_min_from_local_pos(
			size_m,
			Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO)),
			float(obj.get("rotation_deg", 0.0))
		)
	var opening: Dictionary = state["opening"]
	if not opening.is_empty():
		state["opening_type_label"] = _opening_type_label_text(opening)
		state["opening_max_width_m"] = _max_width_for_opening(opening)
		state["opening_max_offset_m"] = 200.0 if bool(opening.get("is_vertical", false)) else _wall_length(
			_get_room_rect(int(opening.get("a", -1))),
			String(opening.get("wall", "top"))
		)
	_props.show(state)
	_refresh_element_list()


## "Puerta", "Ventana exterior", "Hueco vertical"... El nombre que lleva la ficha
## de la apertura seleccionada.


## El desplegable del tipo de escalera guarda 0 auto, 1 recta y 2 en U. El
## vocabulario es del editor, que lo comparte con la herramienta de la barra
## izquierda; el panel solo enseña el widget.


## El panel pide; el editor decide. Todo lo que toca datos -deshacer incluido-
## se queda de este lado.
func _on_property_panel_action(action: String) -> void:
	match action:
		PropertyPanelScript.ACTION_ROOM_APPLY:
			_apply_room_properties()
		PropertyPanelScript.ACTION_ROOM_DELETE:
			_delete_selected_room()
		PropertyPanelScript.ACTION_ROOM_MARK_EXTERIOR:
			_mark_selected_room_exterior()
		PropertyPanelScript.ACTION_OBJECT_APPLY:
			_apply_object_properties()
		PropertyPanelScript.ACTION_OPENING_APPLY:
			_apply_opening_properties()
		PropertyPanelScript.ACTION_DETECTOR_APPLY:
			_apply_detector_properties()
		PropertyPanelScript.ACTION_VICTIM_APPLY:
			_apply_victim_properties()
		PropertyPanelScript.ACTION_WALL_APPLY:
			_apply_exterior_wall_properties()
		PropertyPanelScript.ACTION_DELETE_SELECTED:
			_delete_selected()
func _stair_turn_item_id_for_mode(mode: String) -> int:
	match StairPlanRules.normalized_turn_mode(mode):
		StairPlanRules.MODE_STRAIGHT:
			return 1
		StairPlanRules.MODE_SWITCHBACK:
			return 2
	return 0


func _stair_turn_mode_from_item_id(item_id: int) -> String:
	match item_id:
		1:
			return StairPlanRules.MODE_STRAIGHT
		2:
			return StairPlanRules.MODE_SWITCHBACK
	return StairPlanRules.MODE_AUTO
func _opening_type_label_text(opening: Dictionary) -> String:
	var op_type: String = String(opening.get("type", "door"))
	var type_label: String = "Puerta"
	if op_type == "window":
		type_label = "Ventana"
	elif op_type == "hole":
		type_label = "Hueco"
	if bool(opening.get("is_vertical", false)):
		type_label = "Hueco vertical"
	if int(opening.get("b", OUTSIDE_ID)) == OUTSIDE_ID:
		return type_label + " exterior"
	return type_label


## La posicion que se enseña no es la que se guarda: en el plano el objeto se
## agarra por su esquina visual, que depende del giro.
func _sync_object_property_fields(obj: Dictionary) -> void:
	if obj.is_empty():
		return
	var size_m: Vector2 = _object_size_m(obj)
	var pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
	if selected_object_room_id >= 0:
		pos = _object_visual_min_from_local_pos(size_m, pos, float(obj.get("rotation_deg", 0.0)))
	_props.fill_object(obj, pos, size_m, _normalize_degrees_signed(float(obj.get("rotation_deg", 0.0))))


func _update_stair_angle_label(room_id: int, room: Dictionary) -> void:
	_props.set_stair_angle_text(_stair_angle_text(room_id, room))


## La linea que resume la escalera: pendiente, tramos y hacia donde sube. Cadena
## vacia si la sala no es una escalera, y entonces el panel la esconde.
func _stair_angle_text(room_id: int, room: Dictionary) -> String:
	if room_id < 0 or room.is_empty() or not StairPlanRules.is_stair_room(room):
		return ""
	var rect: Rect2 = _get_room_rect(room_id)
	var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(room)
	var slope_deg: float = _stair_slope_angle_deg(room_id, room, rect)
	var turn_degrees: float = float(room.get("stair_turn_degrees", 0.0))
	var mode_text: String = "2 tramos + descansillo 180" if turn_degrees >= 179.0 else "tramo recto"
	return "Subida %.0f° | %s | orientacion %s" % [slope_deg, mode_text, StairPlanRules.direction_label(stair_dir)]


## La pendiente es geometria, pero la altura que salva la escalera es un dato del
## escenario: hay que mirar el hueco vertical o la cota de la planta de arriba.
## Aqui se busca la altura y el modulo hace la trigonometria.
func _stair_slope_angle_deg(room_id: int, room: Dictionary, rect: Rect2) -> float:
	return StairPlanRules.slope_angle_deg(
		rect,
		StairPlanRules.run_direction_for_room(room),
		float(room.get("stair_turn_degrees", 0.0)),
		_stair_rise_for_room(room_id, room)
	)


func _stair_rise_for_room(room_id: int, room: Dictionary) -> float:
	var current_level: float = float(room.get("floor_level_z_m", 0.0))
	for raw_op in editor_data.get("openings_data", []):
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		if not bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", -1))
		if a_id != room_id and b_id != room_id:
			continue
		return absf(_room_id_floor_level(a_id) - _room_id_floor_level(b_id))
	var upper_index: int = _next_floor_index_above(current_level)
	if upper_index >= 0:
		var floors: Array = _get_floors()
		if upper_index < floors.size() and typeof(floors[upper_index]) == TYPE_DICTIONARY:
			return maxf(0.0, float(Dictionary(floors[upper_index]).get("level_m", current_level + DEFAULT_FLOOR_HEIGHT_M)) - current_level)
	return DEFAULT_FLOOR_HEIGHT_M


func _apply_room_properties() -> void:
	if selected_room_id < 0:
		_set_status("Selecciona una habitación antes de aplicar propiedades.")
		return

	var fields: Dictionary = _props.read_room()
	var rooms: Array = editor_data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		if int(rooms[i].get("id", -1)) != selected_room_id:
			continue
		_push_undo_snapshot("edit_room")
		var room: Dictionary = rooms[i]
		room["name"] = String(fields.get("name", ""))
		room["kind"] = String(fields.get("kind", ""))
		room["rotation_deg"] = _normalize_degrees_signed(float(fields.get("rotation_deg", 0.0)))
		if StairPlanRules.is_stair_room(room):
			room["stair_run_direction_m"] = Serializer.vector_to_data(StairPlanRules.direction_from_rotation(float(room.get("rotation_deg", 0.0))))
			room["stair_turn_mode"] = _stair_turn_mode_from_item_id(int(fields.get("stair_turn_item_id", 0)))
			room["stair_has_walls"] = bool(fields.get("stair_has_walls", false))
			room["stair_has_railings"] = bool(fields.get("stair_has_railings", true))
		room["height_m"] = float(fields.get("height_m", 2.7))
		room["fuel_energy_MJ"] = float(fields.get("fuel_energy_MJ", 0.0))
		room["max_hrr_kw"] = float(fields.get("max_hrr_kw", 0.0))
		rooms[i] = room
		editor_data["rooms_data"] = rooms
		var next_rect := Rect2(
			Vector2(float(fields.get("x_m", 0.0)), float(fields.get("y_m", 0.0))),
			Vector2(maxf(0.25, float(fields.get("width_m", 1.0))), maxf(0.25, float(fields.get("depth_m", 1.0))))
		)
		_set_room_rect(selected_room_id, next_rect)
		if StairPlanRules.is_stair_room(room):
			var stair_dir: Vector2 = Serializer.vector2_from_data(room.get("stair_run_direction_m", Vector2.DOWN))
			var stair_mode: String = StairPlanRules.turn_mode_for_room(room)
			var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(next_rect, stair_dir, stair_mode)
			_set_stair_turn_degrees_for_room(selected_room_id, turn_degrees)
			for linked_id in _linked_vertical_stair_room_ids(selected_room_id):
				_set_stair_turn_mode_for_room(linked_id, stair_mode)
				_set_stair_turn_degrees_for_room(linked_id, turn_degrees)
			_apply_stair_rotation_to_linked_rooms(selected_room_id, float(room.get("rotation_deg", 0.0)), stair_dir)
			_sync_vertical_stair_openings(selected_room_id)
		_set_status("Propiedades de habitación %d actualizadas." % selected_room_id)
		_refresh_element_list()
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


func _room_display_name(room: Dictionary, room_id: int) -> String:
	var name_text: String = String(room.get("name", "")).strip_edges()
	if name_text != "":
		return name_text
	return "Room %d" % room_id


func _get_room_rect(room_id: int) -> Rect2:
	var rects: Dictionary = editor_data.get("room_rect_m", {})
	return Serializer.rect2_from_data(rects.get(str(room_id), Rect2()))


func _room_rotation_deg(room_id: int) -> float:
	var room: Dictionary = _get_room(room_id)
	return float(room.get("rotation_deg", 0.0)) if not room.is_empty() else 0.0


func _rotated_rect_points_m(rect: Rect2, rotation_deg: float) -> PackedVector2Array:
	var center: Vector2 = rect.get_center()
	var half: Vector2 = rect.size * 0.5
	var rot := Transform2D(deg_to_rad(rotation_deg), Vector2.ZERO)
	return PackedVector2Array([
		center + rot * Vector2(-half.x, -half.y),
		center + rot * Vector2(half.x, -half.y),
		center + rot * Vector2(half.x, half.y),
		center + rot * Vector2(-half.x, half.y)
	])


func _rotated_rect_has_point(rect: Rect2, rotation_deg: float, pos_m: Vector2) -> bool:
	if absf(rotation_deg) <= 0.001:
		return rect.has_point(pos_m)
	var local: Vector2 = Transform2D(deg_to_rad(-rotation_deg), Vector2.ZERO) * (pos_m - rect.get_center())
	return absf(local.x) <= rect.size.x * 0.5 and absf(local.y) <= rect.size.y * 0.5


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
		if _rotated_rect_has_point(_get_room_rect(room_id), _room_rotation_deg(room_id), pos_m):
			return room_id
	return -1


func _object_size_m(obj: Dictionary) -> Vector2:
	var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
	return Vector2(maxf(0.05, size.x), maxf(0.05, size.y))


func _object_world_center(room_rect: Rect2, obj: Dictionary) -> Vector2:
	var pos: Vector2 = Serializer.vector2_from_data(obj.get("position_m", Vector2.ZERO))
	return room_rect.position + pos + _object_size_m(obj) * 0.5


func _object_transform(rotation_deg: float) -> Transform2D:
	return Transform2D(deg_to_rad(rotation_deg), Vector2.ZERO)


func _world_to_object_local(pos_m: Vector2, center_m: Vector2, rotation_deg: float) -> Vector2:
	return Transform2D(deg_to_rad(-rotation_deg), Vector2.ZERO) * (pos_m - center_m)


func _object_contains_point(room_rect: Rect2, obj: Dictionary, pos_m: Vector2) -> bool:
	var size: Vector2 = _object_size_m(obj)
	var local: Vector2 = _world_to_object_local(pos_m, _object_world_center(room_rect, obj), float(obj.get("rotation_deg", 0.0)))
	var hit_padding_m: float = maxf(0.05, 8.0 / pixels_per_meter)
	return absf(local.x) <= size.x * 0.5 + hit_padding_m and absf(local.y) <= size.y * 0.5 + hit_padding_m


func _object_corner_points_m(room_rect: Rect2, obj: Dictionary) -> PackedVector2Array:
	var size: Vector2 = _object_size_m(obj)
	var half: Vector2 = size * 0.5
	var center: Vector2 = _object_world_center(room_rect, obj)
	var rot := _object_transform(float(obj.get("rotation_deg", 0.0)))
	return PackedVector2Array([
		center + rot * Vector2(-half.x, -half.y),
		center + rot * Vector2(half.x, -half.y),
		center + rot * Vector2(half.x, half.y),
		center + rot * Vector2(-half.x, half.y)
	])


func _object_handle_points_m(room_rect: Rect2, obj: Dictionary) -> Dictionary:
	var size: Vector2 = _object_size_m(obj)
	var center: Vector2 = _object_world_center(room_rect, obj)
	var rot := _object_transform(float(obj.get("rotation_deg", 0.0)))
	return {
		ObjectMouseMode.RESIZE_WIDTH: center + rot * Vector2(size.x * 0.5, 0.0),
		ObjectMouseMode.RESIZE_LENGTH: center + rot * Vector2(0.0, size.y * 0.5),
		ObjectMouseMode.ROTATE: center + rot * Vector2(0.0, -size.y * 0.5 - OBJECT_ROTATE_HANDLE_OFFSET_M)
	}


func _room_handle_points_m(room_id: int) -> Dictionary:
	var rect: Rect2 = _get_room_rect(room_id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	var center: Vector2 = rect.get_center()
	var rot := Transform2D(deg_to_rad(_room_rotation_deg(room_id)), Vector2.ZERO)
	return {
		ObjectMouseMode.RESIZE_WIDTH: center + rot * Vector2(rect.size.x * 0.5, 0.0),
		ObjectMouseMode.RESIZE_LENGTH: center + rot * Vector2(0.0, rect.size.y * 0.5),
		ObjectMouseMode.ROTATE: center + rot * Vector2(0.0, -rect.size.y * 0.5 - OBJECT_ROTATE_HANDLE_OFFSET_M)
	}


func _find_selected_room_handle_at(pos_m: Vector2) -> int:
	if selected_room_id < 0:
		return ObjectMouseMode.NONE
	var handles: Dictionary = _room_handle_points_m(selected_room_id)
	for mode in [ObjectMouseMode.ROTATE, ObjectMouseMode.RESIZE_WIDTH, ObjectMouseMode.RESIZE_LENGTH]:
		if not handles.has(mode):
			continue
		var hp: Vector2 = Vector2(handles[mode])
		if pos_m.distance_to(hp) <= OBJECT_HANDLE_HIT_RADIUS_M:
			return mode
	return ObjectMouseMode.NONE


func _find_selected_object_handle_at(pos_m: Vector2) -> int:
	if selected_object_room_id < 0 or selected_object_index < 0:
		return ObjectMouseMode.NONE
	var obj: Dictionary = _get_object(selected_object_room_id, selected_object_index)
	if obj.is_empty():
		return ObjectMouseMode.NONE
	var handles: Dictionary = _object_handle_points_m(_get_room_rect(selected_object_room_id), obj)
	for mode in [ObjectMouseMode.ROTATE, ObjectMouseMode.RESIZE_WIDTH, ObjectMouseMode.RESIZE_LENGTH]:
		if not handles.has(mode):
			continue
		var hp: Vector2 = Vector2(handles[mode])
		if pos_m.distance_to(hp) <= OBJECT_HANDLE_HIT_RADIUS_M:
			return mode
	return ObjectMouseMode.NONE


func _normalize_degrees_signed(value: float) -> float:
	var wrapped: float = fposmod(value + 180.0, 360.0) - 180.0
	if wrapped <= -180.0:
		return 180.0
	return wrapped


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
			if _object_contains_point(room_rect, obj, pos_m):
				return {"room_id": room_id, "object_index": object_index}
	return {}


func _find_opening_at(pos_m: Vector2) -> int:
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		if not _opening_on_current_floor(openings[i]):
			continue
		if bool(Dictionary(openings[i]).get("is_vertical", false)):
			var vertical_rect: Rect2 = _vertical_opening_rect(Dictionary(openings[i]))
			if vertical_rect.has_point(pos_m):
				return i
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
		_set_status("Pulsa dentro de una habitación para colocar un objeto.")
		return

	var selected: int = _object_kind_option.selected if _object_kind_option != null else -1
	var kind: String = _object_kind_option.get_item_text(selected) if _object_kind_option != null and selected >= 0 else "sofa"
	var room_rect: Rect2 = _get_room_rect(room_id)
	var obj: Dictionary = ObjectLibraryScript.create_object(kind, _next_object_id(), room_id, Vector2.ZERO)
	var size: Vector2 = Serializer.vector2_from_data(obj.get("size_m", Vector2.ONE))
	var local_pos: Vector2 = _snap_object_m(pos_m - room_rect.position - size * 0.5)
	local_pos = _clamp_object_local_pos(room_rect, size, local_pos)
	_push_undo_snapshot("create_object")
	obj["position_m"] = Serializer.vector_to_data(local_pos)
	obj["visual_pose_locked"] = true
	_add_object_to_room(room_id, obj)
	_select_object(room_id, Array(_get_room(room_id).get("fuel_objects", [])).size() - 1)
	_set_status("Objeto %s colocado en habitación %d." % [kind, room_id])
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
	_mark_object_as_ignition(int(hit["room_id"]), int(hit["object_index"]))


func _mark_object_as_ignition(target_room_id: int, target_index: int) -> void:
	if _get_object(target_room_id, target_index).is_empty():
		_set_status("Selecciona un objeto combustible para marcar el foco inicial.")
		return
	_push_undo_snapshot("mark_ignition")
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
	editor_data["ignition_room_id"] = target_room_id
	_select_object(target_room_id, target_index)
	_set_status("Foco inicial marcado.")
	queue_redraw()


func _next_detector_id() -> String:
	return _first_free_id("det_%03d", _taken_ids("detectors"))


func _next_victim_id() -> String:
	return _first_free_id("vic_%03d", _taken_ids("victims"))


func _taken_ids(list_key: String) -> Dictionary:
	var taken: Dictionary = {}
	for item in Array(editor_data.get(list_key, [])):
		if typeof(item) == TYPE_DICTIONARY:
			taken[String(Dictionary(item).get("id", ""))] = true
	return taken


func _create_detector_at(pos_m: Vector2) -> void:
	var room_id: int = _find_room_at(pos_m)
	if room_id < 0:
		_set_status("Pulsa dentro de una habitación para colocar un detector.")
		return
	var room_rect: Rect2 = _get_room_rect(room_id)
	var local_pos: Vector2 = pos_m - room_rect.position
	local_pos.x = clampf(snappedf(local_pos.x, GRID_M), 0.0, maxf(0.0, room_rect.size.x))
	local_pos.y = clampf(snappedf(local_pos.y, GRID_M), 0.0, maxf(0.0, room_rect.size.y))
	var dets: Array = editor_data.get("detectors", [])
	var new_id: String = _next_detector_id()
	_push_undo_snapshot("create_detector")
	dets.append({
		"id": new_id,
		"room_id": room_id,
		"type": "smoke",
		"threshold": 0.025,
		"x_m": local_pos.x,
		"y_m": local_pos.y
	})
	editor_data["detectors"] = dets
	_select_detector(dets.size() - 1)
	_set_status("Detector %s colocado en habitación %d." % [new_id, room_id])
	queue_redraw()


func _create_victim_at(pos_m: Vector2) -> void:
	var room_id: int = _find_room_at(pos_m)
	if room_id < 0:
		_set_status("Pulsa dentro de una habitación para colocar una víctima.")
		return
	var room_rect: Rect2 = _get_room_rect(room_id)
	var local_pos: Vector2 = pos_m - room_rect.position
	local_pos.x = clampf(snappedf(local_pos.x, GRID_M), 0.0, maxf(0.0, room_rect.size.x))
	local_pos.y = clampf(snappedf(local_pos.y, GRID_M), 0.0, maxf(0.0, room_rect.size.y))
	var vics: Array = editor_data.get("victims", [])
	var new_id: String = _next_victim_id()
	var vic_num: int = vics.size() + 1
	_push_undo_snapshot("create_victim")
	vics.append({
		"id": new_id,
		"room_id": room_id,
		"name": "Víctima %d" % vic_num,
		"x_m": local_pos.x,
		"y_m": local_pos.y,
		"height_m": 0.9
	})
	editor_data["victims"] = vics
	_select_victim(vics.size() - 1)
	_set_status("Víctima %s colocada en habitación %d." % [new_id, room_id])
	queue_redraw()


func _find_detector_at(pos_m: Vector2) -> int:
	var dets: Array = editor_data.get("detectors", [])
	var hit_radius_m: float = maxf(0.28, 14.0 / pixels_per_meter)
	for i in range(dets.size()):
		if typeof(dets[i]) != TYPE_DICTIONARY:
			continue
		var det: Dictionary = dets[i]
		var room_id: int = int(det.get("room_id", -1))
		var room_rect: Rect2 = _get_room_rect(room_id)
		if room_rect.size == Vector2.ZERO:
			continue
		if not _is_room_on_current_floor(_get_room(room_id)):
			continue
		var world_pos: Vector2 = room_rect.position + Vector2(float(det.get("x_m", 0.0)), float(det.get("y_m", 0.0)))
		if pos_m.distance_to(world_pos) <= hit_radius_m:
			return i
	return -1


func _find_victim_at(pos_m: Vector2) -> int:
	var vics: Array = editor_data.get("victims", [])
	var hit_radius_m: float = maxf(0.30, 16.0 / pixels_per_meter)
	for i in range(vics.size()):
		if typeof(vics[i]) != TYPE_DICTIONARY:
			continue
		var vic: Dictionary = vics[i]
		var room_id: int = int(vic.get("room_id", -1))
		var room_rect: Rect2 = _get_room_rect(room_id)
		if room_rect.size == Vector2.ZERO:
			continue
		if not _is_room_on_current_floor(_get_room(room_id)):
			continue
		var world_pos: Vector2 = room_rect.position + Vector2(float(vic.get("x_m", 0.0)), float(vic.get("y_m", 0.0)))
		if pos_m.distance_to(world_pos) <= hit_radius_m:
			return i
	return -1


func _select_detector(index: int) -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = index
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	var dets: Array = editor_data.get("detectors", [])
	if index >= 0 and index < dets.size():
		var det: Dictionary = dets[index]
		_set_status("Detector %s seleccionado." % String(det.get("id", str(index))))
	queue_redraw()


func _select_victim(index: int) -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = index
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	var vics: Array = editor_data.get("victims", [])
	if index >= 0 and index < vics.size():
		var vic: Dictionary = vics[index]
		_set_status("Víctima %s seleccionada." % String(vic.get("name", vic.get("id", str(index)))))
	queue_redraw()


func _select_exterior_wall(index: int) -> void:
	selected_room_id = -1
	selected_opening_index = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = index
	_refresh_property_panel()
	_sync_editor_visualizer_selection()
	_set_status("Muro exterior %d seleccionado." % index)
	queue_redraw()


func _apply_detector_properties() -> void:
	if selected_detector_index < 0:
		_set_status("Selecciona un detector antes de aplicar propiedades.")
		return
	var dets: Array = editor_data.get("detectors", [])
	if selected_detector_index >= dets.size():
		return
	var fields: Dictionary = _props.read_detector()
	_push_undo_snapshot("edit_detector")
	var det: Dictionary = dets[selected_detector_index]
	det["id"] = String(fields.get("id", ""))
	var idx: int = int(fields.get("type_index", 0))
	det["type"] = "smoke" if idx == 0 else ("heat" if idx == 1 else "co")
	det["threshold"] = float(fields.get("threshold", 0.025))
	var det_room_rect: Rect2 = _get_room_rect(int(det.get("room_id", -1)))
	det["x_m"] = clampf(float(fields.get("x_m", 0.0)), 0.0, maxf(0.0, det_room_rect.size.x))
	det["y_m"] = clampf(float(fields.get("y_m", 0.0)), 0.0, maxf(0.0, det_room_rect.size.y))
	dets[selected_detector_index] = det
	editor_data["detectors"] = dets
	_set_status("Propiedades del detector actualizadas.")
	queue_redraw()


func _apply_victim_properties() -> void:
	if selected_victim_index < 0:
		_set_status("Selecciona una víctima antes de aplicar propiedades.")
		return
	var vics: Array = editor_data.get("victims", [])
	if selected_victim_index >= vics.size():
		return
	var fields: Dictionary = _props.read_victim()
	_push_undo_snapshot("edit_victim")
	var vic: Dictionary = vics[selected_victim_index]
	vic["name"] = String(fields.get("name", ""))
	var vic_room_rect: Rect2 = _get_room_rect(int(vic.get("room_id", -1)))
	vic["x_m"] = clampf(float(fields.get("x_m", 0.0)), 0.0, maxf(0.0, vic_room_rect.size.x))
	vic["y_m"] = clampf(float(fields.get("y_m", 0.0)), 0.0, maxf(0.0, vic_room_rect.size.y))
	vic["height_m"] = float(fields.get("height_m", 0.9))
	vics[selected_victim_index] = vic
	editor_data["victims"] = vics
	_set_status("Propiedades de la víctima actualizadas.")
	queue_redraw()


func _create_door_at(pos_m: Vector2) -> void:
	var shared: Dictionary = _find_shared_wall_at(pos_m)
	if not shared.is_empty():
		var door_width_m: float = minf(0.9, _max_opening_width_for_shared(int(shared["a"]), int(shared["b"]), String(shared["wall"])))
		_add_opening(int(shared["a"]), int(shared["b"]), "door", String(shared["wall"]), float(shared["offset_m"]), door_width_m, 2.05, 0.0, 1.0)
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
		_set_status("Puerta exterior creada en habitación %d." % int(exterior_wall["room_id"]))
		queue_redraw()
		return

	var room_id: int = _find_room_at(pos_m)
	if room_id < 0:
		_set_status("Pulsa una pared compartida, una pared exterior o una habitación.")
		return

	if pending_door_room_id < 0:
		pending_door_room_id = room_id
		_set_status("Primera habitación %d seleccionada para puerta." % room_id)
		return

	if pending_door_room_id == room_id:
		_set_status("Selecciona una segunda habitación adyacente.")
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


func _create_hole_at(pos_m: Vector2) -> void:
	var shared: Dictionary = _find_shared_wall_at(pos_m)
	if shared.is_empty():
		_set_status("El hueco debe colocarse en un paramento compartido entre dos habitaciones.")
		return
	var max_width_m: float = _max_opening_width_for_shared(int(shared["a"]), int(shared["b"]), String(shared["wall"]))
	var width_m: float = clampf(opening_tool_width_m, 0.30, max_width_m)
	_add_opening(
		int(shared["a"]),
		int(shared["b"]),
		"hole",
		String(shared["wall"]),
		float(shared["offset_m"]),
		width_m,
		2.20,
		0.0,
		1.0
	)
	_set_status("Hueco de %.2f m creado entre habitaciones %d y %d." % [width_m, int(shared["a"]), int(shared["b"])])
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
	_set_status("Ventana exterior creada en habitación %d." % int(wall["room_id"]))
	queue_redraw()


func _add_opening(a: int, b: int, type_str: String, wall: String, offset_m: float, width_m: float, height_m: float, sill_m: float, open_fraction: float, record_undo: bool = true) -> void:
	var openings: Array = editor_data.get("openings_data", [])
	if type_str == "hole":
		sill_m = 0.0
		open_fraction = 1.0
	if record_undo:
		_push_undo_snapshot("add_opening")
	openings.append({
		"a": a,
		"b": b,
		"type": type_str,
		"wall": wall,
		"offset_m": offset_m,
		"offset_is_fraction": false,
		"width_m": width_m,
		"height_m": height_m,
		"sill_m": sill_m,
		"open_fraction": open_fraction,
		"swing_direction": "in",
		"hinge_side": "left"
	})
	editor_data["openings_data"] = openings
	selected_opening_index = openings.size() - 1
	selected_room_id = -1
	selected_object_room_id = -1
	selected_object_index = -1
	selected_detector_index = -1
	selected_victim_index = -1
	selected_player_start_room_id = -1
	selected_exterior_wall_index = -1


func _delete_opening(opening_index: int) -> bool:
	var openings: Array = editor_data.get("openings_data", [])
	if opening_index < 0 or opening_index >= openings.size():
		_set_status("No se encontro la apertura para borrar.")
		return false
	_push_undo_snapshot("delete_opening")
	openings.remove_at(opening_index)
	editor_data["openings_data"] = openings
	_clear_selection()
	_set_status("Apertura eliminada.")
	queue_redraw()
	return true


func _delete_at(pos_m: Vector2) -> void:
	var det_index: int = _find_detector_at(pos_m)
	if det_index >= 0:
		_select_detector(det_index)
		_delete_selected()
		return

	var vic_index: int = _find_victim_at(pos_m)
	if vic_index >= 0:
		_select_victim(vic_index)
		_delete_selected()
		return

	var hit_obj: Dictionary = _find_object_at(pos_m)
	if not hit_obj.is_empty():
		_delete_object(int(hit_obj["room_id"]), int(hit_obj["object_index"]))
		return

	var opening_index: int = _find_opening_at(pos_m)
	if opening_index >= 0:
		_delete_opening(opening_index)
		return

	var exterior_wall_index: int = _find_exterior_wall_at(pos_m)
	if exterior_wall_index >= 0:
		_select_exterior_wall(exterior_wall_index)
		_delete_selected()
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
			_push_undo_snapshot("delete_object")
			objects.remove_at(object_index)
			room["fuel_objects"] = objects
			rooms[i] = room
			editor_data["rooms_data"] = rooms
			_clear_selection()
			_set_status("Objeto eliminado.")
			queue_redraw()
		return


func _delete_room(room_id: int) -> void:
	_push_undo_snapshot("delete_room")
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
	if typeof(editor_data.get("player_start", {})) == TYPE_DICTIONARY and int(Dictionary(editor_data.get("player_start", {})).get("room_id", -1)) == room_id:
		editor_data["player_start"] = {}

	# Los detectores y las victimas de la sala se van con ella. Quedaban
	# apuntando a un room_id inexistente, y validate_scenario() no mira esas dos
	# listas: el escenario roto no se veia hasta ejecutarlo.
	for list_key in ["detectors", "victims"]:
		var items: Array = editor_data.get(list_key, [])
		for i in range(items.size() - 1, -1, -1):
			if typeof(items[i]) == TYPE_DICTIONARY and int(Dictionary(items[i]).get("room_id", -1)) == room_id:
				items.remove_at(i)
		editor_data[list_key] = items

	_clear_selection()
	_set_status("Habitación %d eliminada." % room_id)
	_update_floor_status()
	queue_redraw()


func _get_exterior_walls() -> Array:
	if typeof(editor_data.get("exterior_walls", [])) != TYPE_ARRAY:
		editor_data["exterior_walls"] = []
	return editor_data.get("exterior_walls", [])


func _add_exterior_wall(a_m: Vector2, b_m: Vector2, thickness_m: float = 0.16, record_undo: bool = true) -> int:
	var walls: Array = _get_exterior_walls()
	var a: Vector2 = _snap_m(a_m)
	var b: Vector2 = _snap_m(b_m)
	if a.distance_to(b) < GRID_M:
		_set_status("El muro exterior es demasiado corto.")
		return -1
	var new_wall := {
		"a": Serializer.vector_to_data(a),
		"b": Serializer.vector_to_data(b),
		"thickness_m": maxf(0.05, thickness_m)
	}
	var existing_index: int = _find_equivalent_exterior_wall(a, b)
	if existing_index >= 0:
		if record_undo:
			_push_undo_snapshot("edit_exterior_wall")
		walls[existing_index] = new_wall
		editor_data["exterior_walls"] = walls
		_select_exterior_wall(existing_index)
		_set_status("Muro exterior actualizado.")
		return existing_index
	if record_undo:
		_push_undo_snapshot("add_exterior_wall")
	walls.append(new_wall)
	editor_data["exterior_walls"] = walls
	_select_exterior_wall(walls.size() - 1)
	_set_status("Muro exterior dibujado.")
	return walls.size() - 1


func _find_equivalent_exterior_wall(a_m: Vector2, b_m: Vector2) -> int:
	var walls: Array = _get_exterior_walls()
	for i in range(walls.size()):
		if typeof(walls[i]) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = walls[i]
		var a: Vector2 = Serializer.vector2_from_data(wall.get("a", Vector2.ZERO))
		var b: Vector2 = Serializer.vector2_from_data(wall.get("b", Vector2.ZERO))
		if (a.distance_to(a_m) <= 0.05 and b.distance_to(b_m) <= 0.05) or (a.distance_to(b_m) <= 0.05 and b.distance_to(a_m) <= 0.05):
			return i
	return -1


func _find_exterior_wall_at(pos_m: Vector2) -> int:
	var walls: Array = _get_exterior_walls()
	var best_index: int = -1
	var best_distance: float = 0.24
	for i in range(walls.size()):
		if typeof(walls[i]) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = walls[i]
		var a: Vector2 = Serializer.vector2_from_data(wall.get("a", Vector2.ZERO))
		var b: Vector2 = Serializer.vector2_from_data(wall.get("b", Vector2.ZERO))
		var distance: float = _distance_to_segment(pos_m, a, b)
		if distance <= best_distance:
			best_distance = distance
			best_index = i
	return best_index


func _apply_exterior_wall_properties() -> void:
	var walls: Array = _get_exterior_walls()
	if selected_exterior_wall_index < 0 or selected_exterior_wall_index >= walls.size():
		_set_status("Selecciona un muro exterior antes de aplicar propiedades.")
		return
	var fields: Dictionary = _props.read_wall()
	var a: Vector2 = fields.get("start", Vector2.ZERO)
	var b: Vector2 = fields.get("end", Vector2.ZERO)
	if a.distance_to(b) < GRID_M:
		_set_status("El muro exterior es demasiado corto.")
		return
	_push_undo_snapshot("edit_exterior_wall")
	var wall: Dictionary = walls[selected_exterior_wall_index]
	wall["a"] = Serializer.vector_to_data(_snap_m(a))
	wall["b"] = Serializer.vector_to_data(_snap_m(b))
	wall["thickness_m"] = maxf(0.05, float(fields.get("thickness_m", 0.16)))
	walls[selected_exterior_wall_index] = wall
	editor_data["exterior_walls"] = walls
	_set_status("Muro exterior actualizado.")
	queue_redraw()


func _mark_selected_room_exterior() -> void:
	if selected_room_id < 0:
		_set_status("Selecciona una habitación para marcar su contorno exterior.")
		return
	_mark_room_as_exterior(selected_room_id)


func _mark_room_as_exterior(room_id: int) -> void:
	var rect: Rect2 = _get_room_rect(room_id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_push_undo_snapshot("mark_room_exterior")
	_add_exterior_wall(rect.position, rect.position + Vector2(rect.size.x, 0.0), 0.16, false)
	_add_exterior_wall(rect.position + Vector2(rect.size.x, 0.0), rect.position + rect.size, 0.16, false)
	_add_exterior_wall(rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y), 0.16, false)
	_add_exterior_wall(rect.position + Vector2(0.0, rect.size.y), rect.position, 0.16, false)
	_select_room(room_id)
	_set_status("Contorno exterior marcado para habitación %d." % room_id)
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

	var exterior_walls: Array = _get_exterior_walls()
	if not exterior_walls.is_empty() and not _wall_segment_matches_exterior(wall_seg[0], wall_seg[1]):
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


func _wall_segment_matches_exterior(a: Vector2, b: Vector2) -> bool:
	for raw_wall in _get_exterior_walls():
		if typeof(raw_wall) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = raw_wall
		var wa: Vector2 = Serializer.vector2_from_data(wall.get("a", Vector2.ZERO))
		var wb: Vector2 = Serializer.vector2_from_data(wall.get("b", Vector2.ZERO))
		if _segments_overlap_m(a, b, wa, wb):
			return true
	return false


func _shared_wall_segment(room_id: int, other_id: int, wall: String) -> PackedVector2Array:
	var rect: Rect2 = _get_room_rect(room_id)
	var other_rect: Rect2 = _get_room_rect(other_id)
	match wall:
		"left", "right":
			var start_y: float = maxf(rect.position.y, other_rect.position.y)
			var end_y: float = minf(rect.position.y + rect.size.y, other_rect.position.y + other_rect.size.y)
			if end_y - start_y < _CONN_MIN_SHARED:
				return PackedVector2Array()
			var edge_x: float = rect.position.x if wall == "left" else rect.position.x + rect.size.x
			return PackedVector2Array([Vector2(edge_x, start_y), Vector2(edge_x, end_y)])
		"top", "bottom":
			var start_x: float = maxf(rect.position.x, other_rect.position.x)
			var end_x: float = minf(rect.position.x + rect.size.x, other_rect.position.x + other_rect.size.x)
			if end_x - start_x < _CONN_MIN_SHARED:
				return PackedVector2Array()
			var edge_y: float = rect.position.y if wall == "top" else rect.position.y + rect.size.y
			return PackedVector2Array([Vector2(start_x, edge_y), Vector2(end_x, edge_y)])
	return PackedVector2Array()


func _max_opening_width_for_shared(room_id: int, other_id: int, wall: String) -> float:
	var segment: PackedVector2Array = _shared_wall_segment(room_id, other_id, wall)
	if segment.size() != 2:
		return 0.30
	return maxf(0.30, segment[0].distance_to(segment[1]) - 0.10)


func _max_width_for_opening(opening: Dictionary) -> float:
	if bool(opening.get("is_vertical", false)):
		var room_rect: Rect2 = _get_room_rect(int(opening.get("a", -1)))
		return maxf(0.30, room_rect.size.x - 0.10)
	var a_id: int = int(opening.get("a", -1))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	var wall: String = String(opening.get("wall", ""))
	if a_id >= 0 and b_id != OUTSIDE_ID and wall != "":
		return _max_opening_width_for_shared(a_id, b_id, wall)
	if a_id >= 0:
		var rect: Rect2 = _get_room_rect(a_id)
		if wall == "":
			wall = "top"
		return maxf(0.30, _wall_length(rect, wall) - 0.10)
	return 0.30


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


# ── _shared_wall_between ────────────────────────────────────────────────────
# Detecta si las habitaciones a_id y b_id comparten (o son adyacentes a) una
# pared.  Acepta:
#   • Contacto exacto entre paredes (tolerancia grid)
#   • Brecha entre paredes de hasta _CONN_GAP_TOL (0.30 m)
#   • Solapamiento parcial de hasta _CONN_OVERLAP_FRAC × dim_menor
# Si se pasa click_m, filtra además por proximidad al punto de clic.
# Devuelve el par de paredes con menor separación; {} si no hay conexión.
func _shared_wall_between(a_id: int, b_id: int, click_m: Vector2 = Vector2(1.0e20, 1.0e20)) -> Dictionary:
	if absf(_room_id_floor_level(a_id) - _room_id_floor_level(b_id)) > 0.05:
		return {}
	var a: Rect2 = _get_room_rect(a_id)
	var b: Rect2 = _get_room_rect(b_id)
	var click_filter: bool = click_m.x < 1.0e19
	var best: Dictionary = {}
	var best_gap: float = 1.0e20
	var min_x: float = minf(a.size.x, b.size.x)
	var min_y: float = minf(a.size.y, b.size.y)

	# ── A.right ↔ B.left  (A a la izquierda, con brecha o solape) ──
	var gap_r: float = b.position.x - (a.position.x + a.size.x)
	if gap_r >= -min_x * _CONN_OVERLAP_FRAC and gap_r <= _CONN_GAP_TOL:
		var sy: float = maxf(a.position.y, b.position.y)
		var ey: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if ey - sy >= _CONN_MIN_SHARED:
			var mid_x: float = (a.position.x + a.size.x + b.position.x) * 0.5
			if not click_filter or (absf(click_m.x - mid_x) <= _CONN_CLICK_TOL and click_m.y >= sy - 0.10 and click_m.y <= ey + 0.10):
				var ag: float = absf(gap_r)
				if ag < best_gap:
					best_gap = ag
					var cy: float = clampf(click_m.y if click_filter else (sy + ey) * 0.5, sy, ey)
					best = {"a": a_id, "b": b_id, "wall": "right", "offset_m": cy - a.position.y}

	# ── A.left ↔ B.right  (A a la derecha, con brecha o solape) ──
	var gap_l: float = a.position.x - (b.position.x + b.size.x)
	if gap_l >= -min_x * _CONN_OVERLAP_FRAC and gap_l <= _CONN_GAP_TOL:
		var sy: float = maxf(a.position.y, b.position.y)
		var ey: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
		if ey - sy >= _CONN_MIN_SHARED:
			var mid_x: float = (a.position.x + b.position.x + b.size.x) * 0.5
			if not click_filter or (absf(click_m.x - mid_x) <= _CONN_CLICK_TOL and click_m.y >= sy - 0.10 and click_m.y <= ey + 0.10):
				var ag: float = absf(gap_l)
				if ag < best_gap:
					best_gap = ag
					var cy: float = clampf(click_m.y if click_filter else (sy + ey) * 0.5, sy, ey)
					best = {"a": a_id, "b": b_id, "wall": "left", "offset_m": cy - a.position.y}

	# ── A.bottom ↔ B.top  (A encima, con brecha o solape) ──
	var gap_b: float = b.position.y - (a.position.y + a.size.y)
	if gap_b >= -min_y * _CONN_OVERLAP_FRAC and gap_b <= _CONN_GAP_TOL:
		var sx: float = maxf(a.position.x, b.position.x)
		var ex: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if ex - sx >= _CONN_MIN_SHARED:
			var mid_y: float = (a.position.y + a.size.y + b.position.y) * 0.5
			if not click_filter or (absf(click_m.y - mid_y) <= _CONN_CLICK_TOL and click_m.x >= sx - 0.10 and click_m.x <= ex + 0.10):
				var ag: float = absf(gap_b)
				if ag < best_gap:
					best_gap = ag
					var cx: float = clampf(click_m.x if click_filter else (sx + ex) * 0.5, sx, ex)
					best = {"a": a_id, "b": b_id, "wall": "bottom", "offset_m": cx - a.position.x}

	# ── A.top ↔ B.bottom  (A debajo, con brecha o solape) ──
	var gap_t: float = a.position.y - (b.position.y + b.size.y)
	if gap_t >= -min_y * _CONN_OVERLAP_FRAC and gap_t <= _CONN_GAP_TOL:
		var sx: float = maxf(a.position.x, b.position.x)
		var ex: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
		if ex - sx >= _CONN_MIN_SHARED:
			var mid_y: float = (a.position.y + b.position.y + b.size.y) * 0.5
			if not click_filter or (absf(click_m.y - mid_y) <= _CONN_CLICK_TOL and click_m.x >= sx - 0.10 and click_m.x <= ex + 0.10):
				var ag: float = absf(gap_t)
				if ag < best_gap:
					best_gap = ag
					var cx: float = clampf(click_m.x if click_filter else (sx + ex) * 0.5, sx, ex)
					best = {"a": a_id, "b": b_id, "wall": "top", "offset_m": cx - a.position.x}

	return best


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
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	if wall == "":
		var shared: Dictionary = _shared_wall_between(a_id, b_id)
		wall = String(shared.get("wall", "top"))
	var width: float = float(opening.get("width_m", 0.9))
	var offset: float = float(opening.get("offset_m", _wall_length(rect, wall) * 0.5))
	if bool(opening.get("offset_is_fraction", true)):
		if b_id != OUTSIDE_ID:
			var shared_segment: PackedVector2Array = _shared_wall_segment(a_id, b_id, wall)
			if shared_segment.size() == 2:
				return _line_segment_from_fraction(shared_segment[0], shared_segment[1], offset, width)
		offset = _wall_length(rect, wall) * clampf(offset, 0.0, 1.0)
	return _wall_segment(rect, wall, offset, width)


func _line_segment_from_fraction(a: Vector2, b: Vector2, offset_fraction: float, width_m: float) -> PackedVector2Array:
	var axis: Vector2 = b - a
	var length: float = axis.length()
	if length <= 0.0001:
		return PackedVector2Array()
	var dir: Vector2 = axis / length
	var safe_width: float = minf(width_m, length)
	var center_offset: float = clampf(length * clampf(offset_fraction, 0.0, 1.0), safe_width * 0.5, maxf(safe_width * 0.5, length - safe_width * 0.5))
	var center: Vector2 = a + dir * center_offset
	return PackedVector2Array([center - dir * safe_width * 0.5, center + dir * safe_width * 0.5])


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
	_lock_all_object_visual_poses()
	_sync_floor_controls()
	_ensure_file_dialogs()
	if _save_dialog == null:
		_save_to_path(_path_edit.text.strip_edges())
		return
	var current_path: String = _path_edit.text.strip_edges()
	if current_path == "":
		current_path = DEFAULT_SAVE_PATH
	_save_dialog.current_path = current_path
	_save_dialog.popup_centered_ratio(0.72)


func _load_pressed() -> void:
	_ensure_file_dialogs()
	if _load_dialog == null:
		_load_from_path(_path_edit.text.strip_edges())
		return
	var current_path: String = _path_edit.text.strip_edges()
	if current_path != "":
		_load_dialog.current_path = current_path
	_load_dialog.popup_centered_ratio(0.72)


func _on_save_dialog_file_selected(path: String) -> void:
	_save_to_path(path)


func _on_load_dialog_file_selected(path: String) -> void:
	_load_from_path(path)


func _save_to_path(path: String) -> void:
	var clean_path: String = path.strip_edges()
	if clean_path == "":
		_set_status("Elige un archivo para guardar la plantilla.")
		return
	if not clean_path.get_file().contains("."):
		clean_path += ".json"
	_ensure_floor_data()
	editor_data = Serializer.normalize_editor_data(editor_data)
	_lock_all_object_visual_poses()
	_sync_floor_controls()
	if _path_edit != null:
		_path_edit.text = clean_path
	if Serializer.save_scenario(clean_path, editor_data):
		_unsaved_changes = false
		_set_status("Plantilla guardada en %s." % clean_path)
	else:
		_set_status("No se pudo guardar la plantilla.")


func _show_load_error(message: String, path: String = "") -> void:
	var shown: bool = _load_error_helper.show_error(self, load_error_dialog_title, message, path)
	if not shown:
		_set_status(message)
	else:
		_set_status(message.get_slice("\n", 0))


func _load_from_path(path: String) -> void:
	var clean_path: String = path.strip_edges()
	if clean_path == "":
		_set_status("Elige un archivo .json para cargar.")
		return
	if not FileAccess.file_exists(clean_path):
		_show_load_error("Archivo no encontrado.", clean_path)
		return
	var loaded: Dictionary = Serializer.load_scenario(clean_path)
	if loaded.is_empty():
		_show_load_error("El archivo no contiene un escenario válido.\nVerifica que sea un JSON de SimuFire sin errores de formato.", clean_path)
		return
	var load_errors: Array = Serializer.validate_scenario(loaded)
	if not load_errors.is_empty():
		var error_msg: String = "El escenario tiene problemas estructurales:"
		for e in load_errors:
			error_msg += "\n\u2022 " + str(e)
		_show_load_error(error_msg, clean_path)
		return
	editor_data = loaded
	_lock_all_object_visual_poses()
	_undo_stack.clear()
	_ensure_floor_data()
	current_floor_index = clampi(current_floor_index, 0, _get_floors().size() - 1)
	if _stop_time_spin != null:
		_stop_time_spin.value = float(editor_data.get("stop_time_s", 0.0))
	_sync_floor_controls()
	_sync_hvac_option_from_data()
	_sync_lighting_controls_from_data()
	_sync_building_type_option_from_data()
	_clear_selection()
	_mark_editor_runtime_dirty()
	if _path_edit != null:
		_path_edit.text = clean_path
	_unsaved_changes = false
	_set_status("Plantilla cargada desde %s." % clean_path)
	queue_redraw()


func _ensure_file_dialogs() -> void:
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
	var parent: Node = canvas if canvas != null else self
	_save_dialog = parent.get_node_or_null("SaveTemplateDialog") as FileDialog
	if _save_dialog == null:
		_save_dialog = FileDialog.new()
		_save_dialog.name = "SaveTemplateDialog"
		parent.add_child(_save_dialog)
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.title = "Guardar plantilla"
	_save_dialog.filters = PackedStringArray(["*.json ; Plantillas SimuFire"])
	if not _save_dialog.file_selected.is_connected(_on_save_dialog_file_selected):
		_save_dialog.file_selected.connect(_on_save_dialog_file_selected)

	_load_dialog = parent.get_node_or_null("LoadTemplateDialog") as FileDialog
	if _load_dialog == null:
		_load_dialog = FileDialog.new()
		_load_dialog.name = "LoadTemplateDialog"
		parent.add_child(_load_dialog)
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_dialog.title = "Cargar plantilla"
	_load_dialog.filters = PackedStringArray(["*.json ; Plantillas SimuFire"])
	if not _load_dialog.file_selected.is_connected(_on_load_dialog_file_selected):
		_load_dialog.file_selected.connect(_on_load_dialog_file_selected)


func _export_runtime_pressed() -> void:
	_ensure_floor_data()
	editor_data = Serializer.normalize_editor_data(editor_data)
	_lock_all_object_visual_poses()
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
		_set_status("Selecciona primero una habitación.")


func _delete_selected() -> void:
	if selected_exterior_wall_index >= 0:
		var walls: Array = _get_exterior_walls()
		if selected_exterior_wall_index < walls.size():
			_push_undo_snapshot("delete_exterior_wall")
			walls.remove_at(selected_exterior_wall_index)
			editor_data["exterior_walls"] = walls
		_clear_selection()
		_set_status("Muro exterior eliminado.")
		queue_redraw()
		return
	elif selected_detector_index >= 0:
		var dets: Array = editor_data.get("detectors", [])
		if selected_detector_index < dets.size():
			_push_undo_snapshot("delete_detector")
			dets.remove_at(selected_detector_index)
			editor_data["detectors"] = dets
		_clear_selection()
		_set_status("Detector eliminado.")
		queue_redraw()
		return
	elif selected_victim_index >= 0:
		var vics: Array = editor_data.get("victims", [])
		if selected_victim_index < vics.size():
			_push_undo_snapshot("delete_victim")
			vics.remove_at(selected_victim_index)
			editor_data["victims"] = vics
		_clear_selection()
		_set_status("Víctima eliminada.")
		queue_redraw()
		return
	elif selected_player_start_room_id >= 0:
		_push_undo_snapshot("delete_player_start")
		editor_data["player_start"] = {}
		_clear_selection()
		_set_status("Inicio FP eliminado.")
		queue_redraw()
		return
	elif selected_object_room_id >= 0 and selected_object_index >= 0:
		_delete_object(selected_object_room_id, selected_object_index)
	elif selected_opening_index >= 0:
		_delete_opening(selected_opening_index)
	elif selected_room_id >= 0:
		_delete_room(selected_room_id)


func _apply_object_properties() -> void:
	if selected_object_room_id < 0 or selected_object_index < 0:
		_set_status("Selecciona un objeto antes de aplicar propiedades.")
		return
	var fields: Dictionary = _props.read_object()
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
		_push_undo_snapshot("edit_object")
		var obj: Dictionary = objects[selected_object_index]
		obj["name"] = String(fields.get("name", ""))
		var new_w: float = float(fields.get("width_m", 1.0))
		var new_h: float = float(fields.get("height_m", 1.0))
		var room_rect: Rect2 = _get_room_rect(selected_object_room_id)
		var new_rotation: float = _clean_object_rotation_deg(float(fields.get("rotation_deg", 0.0)))
		var new_pos := Vector2(float(fields.get("x_m", 0.0)), float(fields.get("y_m", 0.0)))
		new_pos = _object_local_pos_from_visual_min(Vector2(new_w, new_h), new_pos, new_rotation)
		new_pos = _clamp_object_local_pos_for_rotation(room_rect, Vector2(new_w, new_h), new_pos, new_rotation)
		obj["position_m"] = Serializer.vector_to_data(new_pos)
		obj["size_m"] = {"x": new_w, "y": new_h}
		obj["rotation_deg"] = new_rotation
		obj["elevation_m"] = maxf(0.0, float(fields.get("elevation_m", 0.0)))
		obj["footprint_m2"] = new_w * new_h
		obj["visual_pose_locked"] = true
		obj["fuel_energy_MJ"] = float(fields.get("fuel_energy_MJ", 0.0))
		obj["remaining_fuel_MJ"] = float(fields.get("fuel_energy_MJ", 0.0))
		obj["max_hrr_kw"] = float(fields.get("max_hrr_kw", 0.0))
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
	var fields: Dictionary = _props.read_opening()
	_push_undo_snapshot("edit_opening")
	var op: Dictionary = openings[selected_opening_index]
	var op_type: String = String(op.get("type", "door"))
	op["width_m"] = minf(float(fields.get("width_m", 0.9)), _max_width_for_opening(op))
	op["height_m"] = float(fields.get("height_m", 2.0))
	if not bool(op.get("is_vertical", false)):
		op["offset_m"] = clampf(
			float(fields.get("offset_m", 0.0)),
			0.0,
			_wall_length(_get_room_rect(int(op.get("a", -1))), String(op.get("wall", "top")))
		)
		op["offset_is_fraction"] = false
	op["sill_m"] = 0.0 if op_type == "hole" else float(fields.get("sill_m", 0.0))
	op["open_fraction"] = 1.0 if op_type == "hole" else (0.0 if int(fields.get("open_index", 1)) == 0 else 1.0)
	if op_type == "door":
		op["swing_direction"] = "out" if int(fields.get("swing_index", 0)) == 1 else "in"
		op["hinge_side"] = "right" if int(fields.get("hinge_index", 0)) == 1 else "left"
	openings[selected_opening_index] = op
	editor_data["openings_data"] = openings
	_set_status("Apertura actualizada.")
	queue_redraw()


func _draw() -> void:
	if _editor_view_mode != EditorViewMode.MODE_2D:
		return
	_draw_lower_floor_ghost()
	_draw_rooms()
	_draw_exterior_walls()
	_draw_openings()
	_draw_objects()
	_draw_player_start()
	_draw_detectors()
	_draw_victims()
	if is_dragging_exterior_wall:
		draw_line(_m_to_px(drag_start_m), _m_to_px(drag_current_m), _exterior_wall_selected_color, 4.0)
		var wall_length_m: float = _snap_m(drag_start_m).distance_to(_snap_m(drag_current_m))
		_draw_screen_string(_m_to_px(drag_current_m), Vector2(8.0, -8.0), "Muro exterior %.2f m" % wall_length_m, 220.0, 13, _exterior_wall_selected_color)
	if is_dragging_room:
		if current_tool == Tool.CORRIDOR_L:
			_draw_corridor_drag_preview()
			return
		var rect: Rect2 = _normalized_rect(drag_start_m, drag_current_m)
		var rect_px: Rect2 = _rect_to_px(rect)
		var fill_color: Color = Color(0.25, 0.68, 0.95, 0.18)
		var outline_color: Color = Color(0.55, 0.90, 1.0, 0.85)
		if current_tool == Tool.STAIRS:
			fill_color = Color(1.0, 0.72, 0.18, 0.20)
			outline_color = Color(1.0, 0.80, 0.28, 0.95)
		draw_rect(rect_px, fill_color, true)
		draw_rect(rect_px, outline_color, false, 2.0)
		if current_tool == Tool.STAIRS and rect.size.x > 0.01 and rect.size.y > 0.01:
			var stair_dir: Vector2 = StairPlanRules.run_direction_from_drag(drag_start_m, drag_current_m, rect)
			var stair_mode: String = _selected_stair_tool_turn_mode()
			var turn_degrees: float = StairPlanRules.turn_degrees_for_mode(rect, stair_dir, stair_mode)
			EditorDraw2D.stair_room_guides(self, rect_px, stair_dir, turn_degrees)
			var void_px: Rect2 = _rect_to_px(StairGeometry.vertical_void_rect(rect, stair_dir, turn_degrees))
			draw_rect(void_px, Color(1.0, 0.26, 0.08, 0.18), true)
			draw_rect(void_px, Color(1.0, 0.36, 0.10, 0.92), false, 2.0)
			_draw_screen_string(
				_m_to_px(drag_start_m),
				Vector2(8.0, -18.0),
				"ENTRADA",
				90.0,
				10,
				Color(0.95, 1.0, 0.82, 0.90)
			)
			_draw_screen_string(
				_m_to_px(drag_current_m),
				Vector2(8.0, -18.0),
				"SUBE",
				80.0,
				10,
				Color(1.0, 0.90, 0.35, 0.94)
			)
		if rect.size.x > 0.01 and rect.size.y > 0.01:
			var area: float = rect.size.x * rect.size.y
			var preview_text: String = "%.2f × %.2f m  (%.2f m²)" % [rect.size.x, rect.size.y, area]
			if current_tool == Tool.STAIRS:
				var stair_dir: Vector2 = StairPlanRules.run_direction_from_drag(drag_start_m, drag_current_m, rect)
				var long_m: float = StairGeometry.long_span_m(rect, stair_dir)
				var cross_m: float = StairGeometry.cross_span_m(rect, stair_dir)
				var stair_mode: String = _selected_stair_tool_turn_mode()
				var mode_label: String = StairPlanRules.turn_mode_label(stair_mode)
				if StairPlanRules.normalized_turn_mode(stair_mode) == StairPlanRules.MODE_SWITCHBACK and not StairPlanRules.can_use_180_landing(rect, stair_dir):
					mode_label += " no cabe"
				preview_text = "Escalera %s  %.2f m largo × %.2f m ancho  | ENTRADA -> SUBE" % [mode_label, long_m, cross_m]
			_draw_screen_string(
				rect_px.position,
				Vector2(6.0, 18.0),
				preview_text,
				maxf(60.0, _screen_width_px(rect_px.size.x) - 8.0),
				12,
				Color(0.55, 0.90, 1.0, 0.95)
			)


func _screen_scale_inv() -> float:
	return 1.0 / maxf(0.05, camera.zoom.x)


func _screen_width_px(world_width_px: float) -> float:
	return world_width_px * maxf(0.05, camera.zoom.x)


func _draw_screen_string(anchor_px: Vector2, offset_px: Vector2, text: String, max_width_px: float, font_size: int, color: Color) -> void:
	var font: Font = _editor_font if _editor_font != null else ThemeDB.fallback_font
	if font == null or text == "":
		return
	draw_set_transform(anchor_px, 0.0, Vector2(_screen_scale_inv(), _screen_scale_inv()))
	draw_string(
		font,
		offset_px,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		max_width_px,
		font_size,
		color
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _track_hover_help_mouse(screen_pos: Vector2) -> void:
	if not _hover_help_enabled or _is_pointer_over_ui() or _is_editor_dragging_anything():
		_reset_hover_help()
		return
	if not _hover_help_has_mouse or screen_pos.distance_to(_hover_help_last_screen_pos) > hover_help_move_tolerance_px:
		_hover_help_has_mouse = true
		_hover_help_last_screen_pos = screen_pos
		_hover_help_world_pos_m = _screen_to_m(screen_pos)
		_hover_help_idle_s = 0.0
		if _hover_help_text != "":
			_hover_help_text = ""
			_show_hover_help_popup("")
			queue_redraw()


func _update_hover_help(delta: float) -> void:
	if not _hover_help_enabled or not _hover_help_has_mouse or _is_pointer_over_ui() or _is_editor_dragging_anything():
		if _hover_help_text != "":
			_reset_hover_help()
		return
	_hover_help_idle_s += delta
	if _hover_help_idle_s < maxf(0.05, hover_help_delay_s):
		return
	var next_text: String = _hover_help_text_at(_hover_help_world_pos_m)
	if next_text != _hover_help_text:
		_hover_help_text = next_text
		_show_hover_help_popup(_hover_help_text)
		queue_redraw()


func _reset_hover_help() -> void:
	_hover_help_idle_s = 0.0
	_hover_help_has_mouse = false
	if _hover_help_text != "":
		_hover_help_text = ""
		queue_redraw()
	_show_hover_help_popup("")


func _is_editor_dragging_anything() -> bool:
	return is_middle_panning or is_dragging_room or is_dragging_exterior_wall or is_dragging_room_geometry or is_dragging_object


func _hover_help_text_at(pos_m: Vector2) -> String:
	var det_index: int = _find_detector_at(pos_m)
	if det_index >= 0:
		var dets: Array = editor_data.get("detectors", [])
		var det: Dictionary = dets[det_index] if det_index < dets.size() and typeof(dets[det_index]) == TYPE_DICTIONARY else {}
		return "Detector: %s (%s)" % [String(det.get("id", str(det_index))), _detector_type_label(String(det.get("type", "smoke")))]

	var vic_index: int = _find_victim_at(pos_m)
	if vic_index >= 0:
		var vics: Array = editor_data.get("victims", [])
		var vic: Dictionary = vics[vic_index] if vic_index < vics.size() and typeof(vics[vic_index]) == TYPE_DICTIONARY else {}
		return "Víctima: %s" % String(vic.get("name", vic.get("id", str(vic_index))))

	var hit_obj: Dictionary = _find_object_at(pos_m)
	if not hit_obj.is_empty():
		var obj: Dictionary = _get_object(int(hit_obj.get("room_id", -1)), int(hit_obj.get("object_index", -1)))
		return "Objeto: %s" % String(obj.get("name", obj.get("id", "combustible")))

	var opening_index: int = _find_opening_at(pos_m)
	if opening_index >= 0:
		var openings: Array = editor_data.get("openings_data", [])
		if opening_index < openings.size() and typeof(openings[opening_index]) == TYPE_DICTIONARY:
			return _element_label_for_opening(Dictionary(openings[opening_index]), opening_index)

	if _player_start_hit_test(pos_m):
		return "Inicio FP: aparición del jugador"

	var exterior_wall_index: int = _find_exterior_wall_at(pos_m)
	if exterior_wall_index >= 0:
		return "Muro exterior %d" % exterior_wall_index

	var room_id: int = _find_room_at(pos_m)
	if room_id >= 0:
		var room: Dictionary = _get_room(room_id)
		return "%s: %s (R%d)" % [_element_type_label_for_room(room), _room_display_name(room, room_id), room_id]
	return ""


func _detector_type_label(type_name: String) -> String:
	match type_name:
		"heat":
			return "calor"
		"co":
			return "CO"
		_:
			return "humo"


func _player_start_hit_test(pos_m: Vector2) -> bool:
	if typeof(editor_data.get("player_start", {})) != TYPE_DICTIONARY:
		return false
	var start: Dictionary = editor_data.get("player_start", {})
	var room_id: int = int(start.get("room_id", -1))
	if not _is_room_on_current_floor(_get_room(room_id)):
		return false
	var start_pos: Vector2 = Serializer.vector2_from_data(start.get("position_m", _get_room_rect(room_id).get_center()))
	return pos_m.distance_to(start_pos) <= 0.25


func _draw_corridor_drag_preview() -> void:
	var layout: Dictionary = _build_corridor_layout(drag_start_m, drag_current_m)
	if layout.has("error"):
		draw_line(_m_to_px(drag_start_m), _m_to_px(drag_current_m), Color(1.0, 0.34, 0.24, 0.85), 2.0)
		_draw_screen_string(_m_to_px(drag_current_m), Vector2(8.0, -8.0), String(layout["error"]), 260.0, 12, Color(1.0, 0.70, 0.62, 0.95))
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

	var label: String = "Pasillo %s  ancho %.2f m" % ["L" if mode == "l" else "recto", corridor_width_m]
	_draw_screen_string(end_px, Vector2(8.0, -8.0), label, 220.0, 12, Color(0.72, 1.0, 0.94, 0.96))


func _draw_lower_floor_ghost() -> void:
	var lower_level: float = _immediate_lower_floor_level()
	if is_inf(lower_level):
		return
	for room in editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if absf(float(room_dict.get("floor_level_z_m", 0.0)) - lower_level) >= 0.05:
			continue
		var rect: Rect2 = _get_room_rect(int(room_dict.get("id", -1)))
		var rect_px: Rect2 = _rect_to_px(rect)
		draw_rect(rect_px, _lower_floor_ghost_fill, true)
		draw_rect(rect_px, _lower_floor_ghost_outline, false, 1.2)
		if StairPlanRules.is_stair_room(room_dict):
			EditorDraw2D.stair_room_guides(self, rect_px, StairPlanRules.run_direction_for_room(room_dict), float(room_dict.get("stair_turn_degrees", 0.0)))
		if rect_px.size.x > 28.0 and rect_px.size.y > 24.0:
			_draw_screen_string(
				rect_px.position,
				Vector2(6.0, 16.0),
				_room_display_name(room_dict, int(room_dict.get("id", -1))),
				maxf(30.0, _screen_width_px(rect_px.size.x) - 8.0),
				10,
				Color(0.74, 0.82, 0.88, 0.34)
			)
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var opening: Dictionary = openings[i]
		if bool(opening.get("is_vertical", false)):
			continue
		if not _opening_on_level(opening, lower_level):
			continue
		var segment_m: PackedVector2Array = _opening_segment_m(opening)
		if segment_m.size() == 2:
			draw_line(_m_to_px(segment_m[0]), _m_to_px(segment_m[1]), Color(0.70, 0.84, 0.92, 0.25), 3.0)


func _immediate_lower_floor_level() -> float:
	var current_level: float = _current_floor_level_m()
	var best: float = -INF
	for floor in _get_floors():
		if typeof(floor) != TYPE_DICTIONARY:
			continue
		var level_m: float = float(Dictionary(floor).get("level_m", 0.0))
		if level_m < current_level - 0.05 and level_m > best:
			best = level_m
	if best == -INF:
		return INF
	return best


func _opening_on_level(opening: Dictionary, level_m: float) -> bool:
	var a_id: int = int(opening.get("a", -1))
	var b_id: int = int(opening.get("b", OUTSIDE_ID))
	if a_id < 0:
		return false
	if absf(_room_id_floor_level(a_id) - level_m) < 0.05:
		return true
	return b_id != OUTSIDE_ID and absf(_room_id_floor_level(b_id) - level_m) < 0.05


func _draw_exterior_walls() -> void:
	var walls: Array = _get_exterior_walls()
	for i in range(walls.size()):
		if typeof(walls[i]) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = walls[i]
		var a: Vector2 = Serializer.vector2_from_data(wall.get("a", Vector2.ZERO))
		var b: Vector2 = Serializer.vector2_from_data(wall.get("b", Vector2.ZERO))
		if a.distance_to(b) <= 0.001:
			continue
		var selected: bool = i == selected_exterior_wall_index
		var color: Color = _exterior_wall_selected_color if selected else _exterior_wall_color
		var thickness_px: float = maxf(3.0, float(wall.get("thickness_m", 0.16)) * pixels_per_meter)
		EditorDraw2D.exterior_wall(self, _m_to_px(a), _m_to_px(b), color, thickness_px, selected)


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
		var is_stairs: bool = StairPlanRules.is_stair_room(room)
		var fill: Color = _room_selected_fill if room_id == selected_room_id else _room_fill
		var outline: Color = _room_outline
		if is_corridor:
			fill = _corridor_selected_fill if room_id == selected_room_id else _corridor_fill
			outline = _corridor_outline
		if is_stairs:
			fill = Color(0.24, 0.18, 0.08, 0.86) if room_id == selected_room_id else Color(0.16, 0.12, 0.06, 0.74)
			outline = UI_YELLOW
		var rotation_deg: float = float(room.get("rotation_deg", 0.0))
		if absf(rotation_deg) > 0.001:
			var points_m: PackedVector2Array = _rotated_rect_points_m(rect, rotation_deg)
			var points_px := PackedVector2Array()
			for point_m in points_m:
				points_px.append(_m_to_px(point_m))
			draw_colored_polygon(points_px, fill)
			draw_polyline(PackedVector2Array([points_px[0], points_px[1], points_px[2], points_px[3], points_px[0]]), outline, 2.0)
		else:
			draw_rect(rect_px, fill, true)
			draw_rect(rect_px, outline, false, 2.0)
		if is_corridor:
			EditorDraw2D.corridor_room_guides(self, rect_px)
		if is_stairs:
			EditorDraw2D.stair_room_guides(self, rect_px, StairPlanRules.run_direction_for_room(room), float(room.get("stair_turn_degrees", 0.0)))
		if is_corridor or is_stairs:
			EditorDraw2D.narrow_room_dimension_labels(self, rect, rect_px, is_stairs)
		var h: float = float(room.get("height_m", 2.7))
		var area_m2: float = rect.size.x * rect.size.y
		var vol_m3: float = area_m2 * h
		var dim_text: String = "%.2f × %.2f m" % [rect.size.x, rect.size.y]
		var area_text: String = "%.2f m²  ·  %.2f m³" % [area_m2, vol_m3]
		var label_width_px: float = maxf(40.0, _screen_width_px(rect_px.size.x) - 12.0)
		_draw_screen_string(
			rect_px.position,
			Vector2(8.0, 18.0),
			_room_display_name(room, room_id),
			label_width_px,
			13,
			Color(0.94, 0.97, 1.0, 0.92)
		)
		if rect_px.size.y >= 36.0:
			_draw_screen_string(
				rect_px.position,
				Vector2(8.0, 32.0),
				dim_text,
				label_width_px,
				11,
				Color(0.75, 0.88, 0.95, 0.85)
			)
		if rect_px.size.y >= 52.0:
			_draw_screen_string(
				rect_px.position,
				Vector2(8.0, 46.0),
				area_text,
				label_width_px,
				11,
				Color(0.65, 0.82, 0.65, 0.85)
			)
		if room_id == selected_room_id:
			_draw_selected_room_handles(room_id)


func _draw_selected_room_handles(room_id: int) -> void:
	var handles: Dictionary = _room_handle_points_m(room_id)
	if handles.is_empty():
		return
	var center_px: Vector2 = _m_to_px(_get_room_rect(room_id).get_center())
	var rotate_px: Vector2 = _m_to_px(Vector2(handles.get(ObjectMouseMode.ROTATE, _get_room_rect(room_id).get_center())))
	var resize_pxs := PackedVector2Array()
	for mode in [ObjectMouseMode.RESIZE_WIDTH, ObjectMouseMode.RESIZE_LENGTH]:
		if handles.has(mode):
			resize_pxs.append(_m_to_px(Vector2(handles[mode])))
	EditorDraw2D.selection_handles(self, center_px, rotate_px, resize_pxs, object_handle_radius_px)


func _draw_openings() -> void:
	var openings: Array = editor_data.get("openings_data", [])
	for i in range(openings.size()):
		if typeof(openings[i]) != TYPE_DICTIONARY:
			continue
		var opening: Dictionary = openings[i]
		if not _opening_on_current_floor(opening):
			continue
		if bool(opening.get("is_vertical", false)):
			_draw_vertical_opening(opening, i)
			continue
		var segment_m: PackedVector2Array = _opening_segment_m(opening)
		if segment_m.size() != 2:
			continue
		var p1: Vector2 = _m_to_px(segment_m[0])
		var p2: Vector2 = _m_to_px(segment_m[1])
		var type_str: String = String(opening.get("type", "door"))
		var color: Color = _window_color if type_str == "window" else (_door_color if type_str == "door" else UI_YELLOW)
		if i == selected_opening_index:
			color = Color(1.0, 1.0, 0.45, 1.0)
		draw_line(p1, p2, Color(0.04, 0.06, 0.07, 0.95), 8.0)
		draw_line(p1, p2, color, 4.0)
		if type_str == "door":
			_draw_door_swing_preview(opening, segment_m, color)


func _draw_door_swing_preview(opening: Dictionary, segment_m: PackedVector2Array, color: Color) -> void:
	if segment_m.size() != 2:
		return
	var hinge_left: bool = String(opening.get("hinge_side", "left")).to_lower() != "right"
	var hinge_m: Vector2 = segment_m[0] if hinge_left else segment_m[1]
	var wall: String = String(opening.get("wall", "top"))
	var normal_m: Vector2 = _inside_normal_for_wall_2d(wall)
	if String(opening.get("swing_direction", "in")).to_lower() == "out":
		normal_m = -normal_m
	var width_m: float = minf(float(opening.get("width_m", 0.9)), hinge_m.distance_to(segment_m[1] if hinge_left else segment_m[0]))
	if width_m <= 0.05:
		return
	var open_end_m: Vector2 = hinge_m + normal_m * width_m
	EditorDraw2D.door_swing_preview(self, _m_to_px(hinge_m), _m_to_px(open_end_m), color)


func _inside_normal_for_wall_2d(wall: String) -> Vector2:
	match wall:
		"top":
			return Vector2.DOWN
		"bottom":
			return Vector2.UP
		"left":
			return Vector2.RIGHT
		"right":
			return Vector2.LEFT
	return Vector2.DOWN


func _draw_vertical_opening(opening: Dictionary, index: int) -> void:
	var hole_rect: Rect2 = _vertical_opening_rect(opening)
	if hole_rect.size.x <= 0.0 or hole_rect.size.y <= 0.0:
		return
	var rect_px := _rect_to_px(hole_rect)
	var color: Color = Color(1.0, 0.78, 0.20, 0.92)
	if index == selected_opening_index:
		color = Color(1.0, 1.0, 0.45, 1.0)
	EditorDraw2D.vertical_opening(self, rect_px, color)


func _vertical_opening_rect(opening: Dictionary) -> Rect2:
	var a_id: int = int(opening.get("a", -1))
	var room_rect: Rect2 = _get_room_rect(a_id)
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		return Rect2()
	var room: Dictionary = _get_room(a_id)
	if not room.is_empty() and StairPlanRules.is_stair_room(room):
		var stair_dir: Vector2 = StairPlanRules.run_direction_for_room(room)
		var turn_degrees: float = float(room.get("stair_turn_degrees", 0.0))
		return StairGeometry.vertical_void_rect(room_rect, stair_dir, turn_degrees)
	var width_m: float = minf(float(opening.get("width_m", room_rect.size.x * 0.5)), maxf(0.2, room_rect.size.x - 0.2))
	var depth_m: float = minf(float(opening.get("height_m", room_rect.size.y * 0.55)), maxf(0.2, room_rect.size.y - 0.2))
	return Rect2(room_rect.get_center() - Vector2(width_m, depth_m) * 0.5, Vector2(width_m, depth_m))


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
			var size: Vector2 = _object_size_m(obj)
			var corners_m: PackedVector2Array = _object_corner_points_m(room_rect, obj)
			var corners_px := PackedVector2Array()
			for point_m in corners_m:
				corners_px.append(_m_to_px(point_m))
			var center_px: Vector2 = _m_to_px(_object_world_center(room_rect, obj))
			var selected: bool = room_id == selected_object_room_id and object_index == selected_object_index
			var fill: Color = _object_selected_color if selected else _object_color
			draw_colored_polygon(corners_px, fill)
			draw_polyline(PackedVector2Array([corners_px[0], corners_px[1], corners_px[2], corners_px[3], corners_px[0]]), Color(0.18, 0.09, 0.04, 0.92), 1.5)
			if bool(obj.get("is_primary_ignition_source", false)):
				draw_circle(center_px, 7.0, _ignition_color)
				draw_circle(center_px, 3.5, Color(1.0, 0.94, 0.25, 0.98))
			if selected:
				_draw_selected_object_handles(room_rect, obj)
			if size.x * pixels_per_meter >= 48.0:
				var label_anchor_px: Vector2 = center_px + Vector2(-size.x * pixels_per_meter * 0.5, 0.0)
				_draw_screen_string(
					label_anchor_px,
					Vector2(4.0, 12.0),
					String(obj.get("name", obj.get("kind", ""))),
					maxf(16.0, _screen_width_px(size.x * pixels_per_meter) - 8.0),
					10,
					Color(0.08, 0.05, 0.03, 0.9)
				)


func _draw_selected_object_handles(room_rect: Rect2, obj: Dictionary) -> void:
	var handles: Dictionary = _object_handle_points_m(room_rect, obj)
	var center_px: Vector2 = _m_to_px(_object_world_center(room_rect, obj))
	var rotate_px: Vector2 = _m_to_px(Vector2(handles.get(ObjectMouseMode.ROTATE, _object_world_center(room_rect, obj))))
	var resize_pxs := PackedVector2Array()
	for mode in [ObjectMouseMode.RESIZE_WIDTH, ObjectMouseMode.RESIZE_LENGTH]:
		if handles.has(mode):
			resize_pxs.append(_m_to_px(Vector2(handles[mode])))
	EditorDraw2D.selection_handles(self, center_px, rotate_px, resize_pxs, object_handle_radius_px)


func _draw_player_start() -> void:
	if typeof(editor_data.get("player_start", {})) != TYPE_DICTIONARY:
		return
	var start: Dictionary = editor_data.get("player_start", {})
	if start.is_empty():
		return
	var room_id: int = int(start.get("room_id", -1))
	var room: Dictionary = _get_room(room_id)
	if room.is_empty() or not _is_room_on_current_floor(room):
		return
	var rect: Rect2 = _get_room_rect(room_id)
	var local_pos: Vector2 = Serializer.vector2_from_data(start.get("position_m", Vector2.ZERO))
	var world_pos: Vector2 = rect.position + local_pos
	var px: Vector2 = _m_to_px(world_pos)
	var radius: float = 9.0
	var dir := Vector2(0.0, -1.0).rotated(deg_to_rad(float(start.get("yaw_deg", 0.0))))
	EditorDraw2D.player_start_icon(self, px, dir, radius, _player_start_color)


func _draw_detectors() -> void:
	var dets: Array = editor_data.get("detectors", [])
	for i in range(dets.size()):
		if typeof(dets[i]) != TYPE_DICTIONARY:
			continue
		var det: Dictionary = dets[i]
		var room_id: int = int(det.get("room_id", -1))
		var room: Dictionary = _get_room(room_id)
		if not _is_room_on_current_floor(room):
			continue
		var room_rect: Rect2 = _get_room_rect(room_id)
		var world_pos: Vector2 = room_rect.position + Vector2(float(det.get("x_m", 0.0)), float(det.get("y_m", 0.0)))
		var px: Vector2 = _m_to_px(world_pos)
		var det_type: String = String(det.get("type", "smoke"))
		var det_color: Color = _detector_smoke_color if det_type == "smoke" else (_detector_heat_color if det_type == "heat" else _detector_co_color)
		var selected: bool = i == selected_detector_index
		var radius: float = 10.0 if selected else 8.0
		var label: String = "S" if det_type == "smoke" else ("H" if det_type == "heat" else "C")
		EditorDraw2D.detector_icon(self, px, radius, det_color, label, selected)


func _draw_victims() -> void:
	var vics: Array = editor_data.get("victims", [])
	for i in range(vics.size()):
		if typeof(vics[i]) != TYPE_DICTIONARY:
			continue
		var vic: Dictionary = vics[i]
		var room_id: int = int(vic.get("room_id", -1))
		var room: Dictionary = _get_room(room_id)
		if not _is_room_on_current_floor(room):
			continue
		var room_rect: Rect2 = _get_room_rect(room_id)
		var world_pos: Vector2 = room_rect.position + Vector2(float(vic.get("x_m", 0.0)), float(vic.get("y_m", 0.0)))
		var px: Vector2 = _m_to_px(world_pos)
		var selected: bool = i == selected_victim_index
		var r: float = 9.0 if selected else 7.0
		EditorDraw2D.victim_icon(self, px, r, _victim_color, selected)


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _scan_scenario_files() -> void:
	if _scenario_option == null:
		return
	_scenario_option.clear()
	_scenario_paths.clear()

	for preset in _template_builder.get_preset_definitions():
		if typeof(preset) != TYPE_DICTIONARY:
			continue
		var preset_data: Dictionary = preset
		var preset_id: String = String(preset_data.get("id", ""))
		if preset_id == "":
			continue
		_scenario_paths.append("preset://" + preset_id)
		_scenario_option.add_item(String(preset_data.get("name", preset_id)))

	var dir := DirAccess.open(SCENARIOS_RES_PATH)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				_scenario_paths.append(SCENARIOS_RES_PATH + "/" + file_name)
				_scenario_option.add_item(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()

	# Escenarios de validación CFAST — aparecen como "CFAST: <nombre>"
	var vdir := DirAccess.open(VALIDATION_CASES_PATH)
	if vdir != null:
		vdir.list_dir_begin()
		var vfile: String = vdir.get_next()
		while vfile != "":
			if not vdir.current_is_dir() and vfile.begins_with("cfast_") and vfile.ends_with(".json"):
				var basename: String = vfile.get_basename()
				var display: String = "CFAST: " + basename.substr(6).replace("_", " ").capitalize()
				_scenario_paths.append(VALIDATION_CASES_PATH + "/" + vfile)
				_scenario_option.add_item(display)
			vfile = vdir.get_next()
		vdir.list_dir_end()


func _load_scenario_pressed() -> void:
	if _scenario_option == null:
		return
	var idx: int = _scenario_option.selected
	if idx < 0 or idx >= _scenario_paths.size():
		_set_status("Selecciona un escenario de la lista.")
		return
	var path: String = _scenario_paths[idx]
	var loaded: Dictionary = {}
	if path.begins_with("preset://"):
		loaded = _template_builder.create_by_name(path.replace("preset://", ""))
	else:
		if not FileAccess.file_exists(path):
			_show_load_error("Archivo de escenario no encontrado.", path)
			return
		loaded = Serializer.load_scenario(path)
	if loaded.is_empty():
		_show_load_error("No se pudo cargar el escenario.\nVerifica que sea un JSON de SimuFire sin errores de formato.", path)
		return
	var normalized: Dictionary = Serializer.normalize_editor_data(loaded)
	var load_errors: Array = Serializer.validate_scenario(normalized)
	if not load_errors.is_empty():
		var error_msg: String = "El escenario tiene problemas estructurales:"
		for e in load_errors:
			error_msg += "\n\u2022 " + str(e)
		_show_load_error(error_msg, path)
		return
	editor_data = normalized
	_lock_all_object_visual_poses()
	_ensure_floor_data()
	current_floor_index = clampi(current_floor_index, 0, _get_floors().size() - 1)
	if _stop_time_spin != null:
		_stop_time_spin.value = float(editor_data.get("stop_time_s", 0.0))
	_sync_floor_controls()
	_sync_hvac_option_from_data()
	_sync_building_type_option_from_data()
	_clear_selection()
	_mark_editor_runtime_dirty()
	_set_status("Escenario cargado: %s" % path.get_file())
	queue_redraw()


func _run_simulation_pressed() -> void:
	_ensure_floor_data()
	editor_data = Serializer.normalize_editor_data(editor_data)
	_lock_all_object_visual_poses()
	_sync_floor_controls()
	var run_errors: Array = Serializer.validate_scenario(editor_data)
	if not run_errors.is_empty():
		var error_msg: String = "El escenario no es v\u00e1lido para ejecutar:"
		for e in run_errors:
			error_msg += "\n\u2022 " + str(e)
		_show_load_error(error_msg)
		return
	var runtime_rooms: Array = editor_data.get("rooms_data", [])
	if runtime_rooms.is_empty():
		_show_load_error("El escenario no tiene habitaciones. No se puede ejecutar.")
		return
	if not Serializer.save_runtime_template(RUNTIME_EXPORT_PATH, editor_data):
		_set_status("Error al exportar el template runtime.")
		return
	_set_status("Iniciando simulación...")
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _cancel_pressed() -> void:
	# Salir del editor tiraba el plano sin preguntar. Media hora de trabajo se
	# perdia por pulsar un boton, y no habia forma de recuperarla.
	if not _unsaved_changes:
		get_tree().change_scene_to_file(MAIN_MENU_PATH)
		return
	_confirm_discard_changes()


## Pregunta antes de tirar cambios sin guardar.
func _confirm_discard_changes() -> void:
	var canvas: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
	var parent: Node = canvas if canvas != null else self
	var dialog := parent.get_node_or_null("DiscardChangesDialog") as ConfirmationDialog
	if dialog == null:
		dialog = ConfirmationDialog.new()
		dialog.name = "DiscardChangesDialog"
		dialog.title = "Cambios sin guardar"
		dialog.dialog_text = "El escenario tiene cambios que no están guardados.\n\nSi sales ahora se pierden."
		dialog.ok_button_text = "Salir sin guardar"
		dialog.cancel_button_text = "Seguir editando"
		parent.add_child(dialog)
		dialog.confirmed.connect(_discard_and_leave)
	dialog.popup_centered()


func _discard_and_leave() -> void:
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
	var btn_exterior := _ui_root.get_node_or_null("TopBar/HBox/BtnExteriorWall") as Button
	var btn_room := _ui_root.get_node_or_null("TopBar/HBox/BtnRoom") as Button
	var btn_corridor := _ui_root.get_node_or_null("TopBar/HBox/BtnCorridorL") as Button
	var btn_stairs := _ui_root.get_node_or_null("TopBar/HBox/BtnStairs") as Button
	var btn_door := _ui_root.get_node_or_null("TopBar/HBox/BtnDoor") as Button
	var btn_hole := _ui_root.get_node_or_null("TopBar/HBox/BtnHole") as Button
	var btn_window := _ui_root.get_node_or_null("TopBar/HBox/BtnWindow") as Button
	var btn_object := _ui_root.get_node_or_null("TopBar/HBox/BtnObject") as Button
	var btn_ignite := _ui_root.get_node_or_null("TopBar/HBox/BtnIgnite") as Button
	var btn_player_start := _ui_root.get_node_or_null("TopBar/HBox/BtnPlayerStart") as Button
	var btn_delete := _ui_root.get_node_or_null("TopBar/HBox/BtnDelete") as Button
	var btn_detector := _ui_root.get_node_or_null("TopBar/HBox/BtnDetector") as Button
	var btn_victim := _ui_root.get_node_or_null("TopBar/HBox/BtnVictim") as Button

	# Todos los botones del toolbar viven en ScenarioEditorScene.tscn; si
	# falta alguno se aborta el bind (la escena es la fuente de verdad).
	var required_buttons: Array[Button] = [btn_select, btn_exterior, btn_room, btn_corridor, btn_stairs, btn_door, btn_hole, btn_window, btn_object, btn_ignite, btn_player_start, btn_delete]
	for b in required_buttons:
		if b == null:
			return false
	btn_select.text = _tool_display_name(Tool.SELECT)
	btn_exterior.text = _tool_display_name(Tool.EXTERIOR_WALL)
	btn_room.text = _tool_display_name(Tool.ROOM)
	btn_corridor.text = _tool_display_name(Tool.CORRIDOR_L)
	btn_stairs.text = _tool_display_name(Tool.STAIRS)
	btn_door.text = _tool_display_name(Tool.DOOR)
	btn_hole.text = _tool_display_name(Tool.HOLE)
	btn_window.text = _tool_display_name(Tool.WINDOW)
	btn_object.text = _tool_display_name(Tool.OBJECT)
	btn_ignite.text = _tool_display_name(Tool.IGNITION)
	btn_player_start.text = _tool_display_name(Tool.PLAYER_START)
	btn_delete.text = _tool_display_name(Tool.DELETE)
	if btn_detector != null:
		btn_detector.text = _tool_display_name(Tool.DETECTOR)
	if btn_victim != null:
		btn_victim.text = _tool_display_name(Tool.VICTIM)

	_tool_buttons.clear()
	_register_tool_button(btn_select, Tool.SELECT)
	_register_tool_button(btn_exterior, Tool.EXTERIOR_WALL)
	_register_tool_button(btn_room, Tool.ROOM)
	_register_tool_button(btn_corridor, Tool.CORRIDOR_L)
	_register_tool_button(btn_stairs, Tool.STAIRS)
	_register_tool_button(btn_door, Tool.DOOR)
	_register_tool_button(btn_hole, Tool.HOLE)
	_register_tool_button(btn_window, Tool.WINDOW)
	_register_tool_button(btn_object, Tool.OBJECT)
	_register_tool_button(btn_ignite, Tool.IGNITION)
	_register_tool_button(btn_player_start, Tool.PLAYER_START)
	_register_tool_button(btn_delete, Tool.DELETE)
	if btn_detector != null:
		_register_tool_button(btn_detector, Tool.DETECTOR)
	if btn_victim != null:
		_register_tool_button(btn_victim, Tool.VICTIM)

	_object_kind_option = _get_left_node("ObjectTypeOption") as OptionButton
	_path_edit = _get_left_node("PathEdit") as LineEdit
	_scenario_option = _get_left_node("ScenarioOption") as OptionButton
	_hvac_option = _get_left_node("HVACRow/HVACOption") as OptionButton
	if _hvac_option == null:
		_hvac_option = _get_left_node("HVACOption") as OptionButton
	_interior_lights_check = _get_left_node("LightingRow/InteriorLightsCheck") as CheckBox
	_stop_time_spin = _get_left_node("StopTimeSpin") as SpinBox
	_corridor_width_spin = _get_left_node("CorridorWidthSpin") as SpinBox
	_stair_tool_section = _get_left_node("StairToolSection") as Control
	_stair_tool_turn_option = _get_left_node("StairToolSection/StairToolTurnRow/StairToolTurnOption") as OptionButton
	_opening_tool_section = _get_left_node("OpeningToolSection") as Control
	_opening_tool_width_spin = _get_left_node("OpeningToolSection/OpeningToolWidthRow/OpeningToolWidthSpin") as SpinBox
	if _opening_tool_width_spin == null:
		_opening_tool_width_spin = _get_left_node("OpeningToolSection/OpeningToolWidthSpin") as SpinBox
	_status_label = _get_left_node("StatusLabel") as Label
	_building_type_option = _get_left_node("BuildingTypeRow/BuildingTypeOption") as OptionButton

	# El panel de propiedades entero -sus 53 mandos- vive en su modulo. Aqui
	# solo se le da su raiz y se escucha lo que pide.
	var props_ok: bool = _props.bind(_ui_root.get_node_or_null("RightPanel") as Control)
	if not _props.action_requested.is_connected(_on_property_panel_action):
		_props.action_requested.connect(_on_property_panel_action)
	_populate_stair_turn_options(_props.stair_turn_option())

	if _object_kind_option == null or _path_edit == null or _scenario_option == null or _status_label == null:
		return false
	if not props_ok:
		return false
	_status_label.custom_minimum_size = Vector2(0.0, 64.0)

	_populate_object_type_option()
	_bind_floor_controls()
	_bind_corridor_width_control()
	_bind_stair_tool_controls()
	_bind_opening_tool_controls()
	_bind_hvac_option()
	_bind_lighting_controls()
	_bind_building_type_controls()
	_bind_element_list()
	_bind_controls_help()
	_path_edit.text = DEFAULT_SAVE_PATH


	var save_button := _get_left_node("BtnSave") as Button
	var load_button := _get_left_node("BtnLoad") as Button
	_set_control_tooltip(save_button, "Guarda el escenario actual en la ruta indicada.")
	_set_control_tooltip(load_button, "Carga un escenario desde la ruta indicada sin perder el anterior si falla la validación.")
	_connect_button(save_button, _save_pressed)
	_connect_button(load_button, _load_pressed)
	var export_button := _get_left_node("BtnExportRuntime") as Button
	if export_button != null:
		export_button.text = _ui_text("editor.file.export_runtime", "Exportar simulación")
		export_button.tooltip_text = "Guarda una copia interna para probar la simulación; Iniciar simulación lo hace automáticamente."
	_connect_button(export_button, _export_runtime_pressed)
	var load_scenario_button := _get_left_node("BtnLoadScenario") as Button
	_set_control_tooltip(load_scenario_button, "Carga la plantilla seleccionada en el editor.")
	_connect_button(load_scenario_button, _load_scenario_pressed)
	var start_sim_button := _ui_root.get_node_or_null("BottomBar/HBox/BtnStartSimulation") as Button
	var cancel_button := _ui_root.get_node_or_null("BottomBar/HBox/BtnCancel") as Button
	_set_control_tooltip(start_sim_button, "Valida, exporta y abre la simulación con el escenario actual.")
	_set_control_tooltip(cancel_button, "Sale del editor y vuelve al menú principal.")
	_connect_button(start_sim_button, _run_simulation_pressed)
	_connect_button(cancel_button, _cancel_pressed)

	if _stop_time_spin != null:
		_stop_time_spin.value = 0.0
		if not _stop_time_spin.value_changed.is_connected(_on_stop_time_changed):
			_stop_time_spin.value_changed.connect(_on_stop_time_changed)
	_sync_hvac_option_from_data()
	_sync_lighting_controls_from_data()

	_scan_scenario_files()
	_refresh_property_panel()
	_set_status(_ui_text("editor.ready_scene", "Listo. UI editable desde la escena. Dibuja salas."))
	return true


func _register_tool_button(button: Button, tool_id: int) -> void:
	button.toggle_mode = true
	button.icon = _tool_icon(tool_id)
	button.tooltip_text = _tool_tooltip(tool_id)
	if not button.pressed.is_connected(Callable(self, "_set_tool").bind(tool_id)):
		button.pressed.connect(Callable(self, "_set_tool").bind(tool_id))
	_tool_buttons[tool_id] = button


## Un nodo que tiene que estar en ScenarioEditorScene.tscn.
##
## Si falta, no se fabrica: se dice y se sigue. Fabricarlo en silencio es lo que
## producia la divergencia entre lo que se ve en Godot y lo que se ve al jugar,
## y es lo que cerro la migracion U7; tools/validate_editor_scene_complete.gd
## comprueba que ningun Control del editor lo cree el codigo.
func _scene_control(parent: Node, path: String) -> Control:
	if parent == null:
		return null
	var control := parent.get_node_or_null(path) as Control
	if control == null:
		push_error("ScenarioEditor: falta %s bajo %s en ScenarioEditorScene.tscn" % [path, parent.name])
	return control


func _connect_button(button: Button, callback: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _set_control_tooltip(control: Control, text: String) -> void:
	if control != null:
		control.tooltip_text = text


## Casilla numerica de una fila del panel. La fila, su etiqueta y la casilla
## vienen de la escena; aqui solo se le dan los limites y el paso, que son lo
## unico que sabe el codigo y no la escena.
func _bind_spin_row(parent: Control, row_name: String, spin_name: String, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := _scene_control(parent, "%s/%s" % [row_name, spin_name]) as SpinBox
	if spin == null:
		return null
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	return spin


func _bind_check_row(parent: Control, row_name: String, check_name: String) -> CheckBox:
	return _scene_control(parent, "%s/%s" % [row_name, check_name]) as CheckBox


func _bind_option_row(parent: Control, row_name: String, option_name: String) -> OptionButton:
	return _scene_control(parent, "%s/%s" % [row_name, option_name]) as OptionButton


func _bind_building_type_controls() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	_building_type_option = _scene_control(left_vbox, "BuildingTypeRow/BuildingTypeOption") as OptionButton
	if _building_type_option != null:
		_populate_building_type_option()
		if not _building_type_option.item_selected.is_connected(_on_building_type_selected):
			_building_type_option.item_selected.connect(_on_building_type_selected)
	_apartment_floor_spin = _bind_spin_row(left_vbox, "ApartmentFloorRow", "ApartmentFloorSpin", -5.0, 80.0, 1.0)
	if _apartment_floor_spin != null:
		_apartment_floor_spin.rounded = true
		if not _apartment_floor_spin.value_changed.is_connected(_on_apartment_floor_changed):
			_apartment_floor_spin.value_changed.connect(_on_apartment_floor_changed)
	_sync_apartment_floor_control()


func _bind_element_list() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	_element_list = _scene_control(left_vbox, "ElementList") as ItemList
	if _element_list != null and not _element_list.item_selected.is_connected(_on_element_list_item_selected):
		_element_list.item_selected.connect(_on_element_list_item_selected)
	_refresh_element_list()


func _bind_controls_help() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	_bind_controls_help_block(left_vbox)


func _bind_floor_controls() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	var section := _scene_control(left_vbox, "FloorSection") as VBoxContainer
	if section == null:
		return
	_floor_option = _scene_control(section, "FloorRow/FloorOption") as OptionButton
	if _floor_option != null and not _floor_option.item_selected.is_connected(_on_floor_selected):
		_floor_option.item_selected.connect(_on_floor_selected)
	_connect_button(_scene_control(section, "FloorRow/BtnAddFloor") as Button, _add_floor_pressed)
	_floor_delete_button = _scene_control(section, "FloorRow/BtnDeleteFloor") as Button
	_connect_button(_floor_delete_button, _delete_floor_pressed)
	_floor_level_spin = _bind_spin_row(section, "FloorLevelRow", "FloorLevelSpin", -2.0, 30.0, 0.05)
	if _floor_level_spin != null and not _floor_level_spin.value_changed.is_connected(_on_floor_level_changed):
		_floor_level_spin.value_changed.connect(_on_floor_level_changed)
	_floor_status_label = _scene_control(section, "FloorStatusLabel") as Label
	if _floor_status_label != null:
		_floor_status_label.add_theme_font_size_override("font_size", editor_font_size_compact)
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


func _on_opening_tool_width_changed(v: float) -> void:
	opening_tool_width_m = clampf(v, 0.30, 6.0)
	if current_tool == Tool.HOLE:
		_set_status(_tool_hint(current_tool))


func _on_stair_tool_turn_selected(_index: int) -> void:
	if current_tool == Tool.STAIRS:
		_set_status(_tool_hint(current_tool))
	queue_redraw()


func _sync_tool_option_visibility() -> void:
	if _ui_root == null:
		return
	var tools_tab_visible: bool = _active_left_tab == EditorLeftTab.TOOLS
	var object_visible: bool = tools_tab_visible and current_tool == Tool.OBJECT
	var corridor_visible: bool = tools_tab_visible and current_tool == Tool.CORRIDOR_L
	var stair_visible: bool = tools_tab_visible and current_tool == Tool.STAIRS
	var opening_visible: bool = tools_tab_visible and current_tool == Tool.HOLE
	_set_node_visible("LeftPanel/Scroll/VBox/ObjectLabel", object_visible)
	_set_node_visible("LeftPanel/Scroll/VBox/ObjectToolLabel", object_visible)
	_set_node_visible("LeftPanel/Scroll/VBox/ObjectTypeOption", object_visible)
	if _object_kind_option != null:
		_set_control_row_visible(_object_kind_option, object_visible)
	var object_section := _get_left_node("ObjectToolSection") as Control
	if object_section != null:
		object_section.visible = object_visible
	_set_node_visible("LeftPanel/Scroll/VBox/CorridorSectionLabel", corridor_visible)
	_set_node_visible("LeftPanel/Scroll/VBox/CorridorWidthSpin", corridor_visible)
	if _corridor_width_spin != null:
		_set_control_row_visible(_corridor_width_spin, corridor_visible)
	var corridor_row := _get_left_node("CorridorWidthRow") as Control
	if corridor_row != null:
		corridor_row.visible = corridor_visible
	if _stair_tool_section != null:
		_stair_tool_section.visible = stair_visible
	if _stair_tool_turn_option != null:
		_set_control_row_visible(_stair_tool_turn_option, stair_visible)
	if _opening_tool_section != null:
		_opening_tool_section.visible = opening_visible
	if _opening_tool_width_spin != null:
		_opening_tool_width_spin.visible = current_tool == Tool.HOLE
		_set_control_row_visible(_opening_tool_width_spin, current_tool == Tool.HOLE)


func _bind_corridor_width_control() -> void:
	# En la escena la casilla cuelga directamente del VBox, sin fila propia, y la
	# enlaza _bind_existing_ui unas lineas mas arriba.
	if _corridor_width_spin == null:
		push_error("ScenarioEditor: falta CorridorWidthSpin en ScenarioEditorScene.tscn")
		return
	_corridor_width_spin.min_value = 0.6
	_corridor_width_spin.max_value = 3.0
	_corridor_width_spin.step = 0.05
	_corridor_width_spin.value = corridor_width_m
	if not _corridor_width_spin.value_changed.is_connected(_on_corridor_width_changed):
		_corridor_width_spin.value_changed.connect(_on_corridor_width_changed)


func _bind_stair_tool_controls() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	_stair_tool_section = _scene_control(left_vbox, "StairToolSection")
	if _stair_tool_section == null:
		return
	_stair_tool_turn_option = _bind_option_row(_stair_tool_section, "StairToolTurnRow", "StairToolTurnOption")
	if _stair_tool_turn_option == null:
		return
	_populate_stair_turn_options(_stair_tool_turn_option)
	if not _stair_tool_turn_option.item_selected.is_connected(_on_stair_tool_turn_selected):
		_stair_tool_turn_option.item_selected.connect(_on_stair_tool_turn_selected)


func _bind_opening_tool_controls() -> void:
	var left_vbox := _find_left_vbox()
	if left_vbox == null:
		return
	_opening_tool_section = _scene_control(left_vbox, "OpeningToolSection")
	if _opening_tool_section == null:
		return
	_opening_tool_width_spin = _bind_spin_row(_opening_tool_section, "OpeningToolWidthRow", "OpeningToolWidthSpin", 0.30, 6.0, 0.05)
	if _opening_tool_width_spin == null:
		return
	_opening_tool_width_spin.value = opening_tool_width_m
	if not _opening_tool_width_spin.value_changed.is_connected(_on_opening_tool_width_changed):
		_opening_tool_width_spin.value_changed.connect(_on_opening_tool_width_changed)


func _bind_hvac_option() -> void:
	if _hvac_option == null:
		push_error("ScenarioEditor: falta HVACRow/HVACOption en ScenarioEditorScene.tscn")
		return
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
	if String(editor_data.get("hvac_mode", "none")).to_lower() == mode:
		return
	_push_undo_snapshot("hvac_mode")
	editor_data["hvac_mode"] = mode
	editor_data["hvac_data"] = {
		"exists": mode != "none",
		"on": mode == "on",
		"mode": mode
	}

func _bind_lighting_controls() -> void:
	if _interior_lights_check == null:
		push_error("ScenarioEditor: falta LightingRow/InteriorLightsCheck en ScenarioEditorScene.tscn")
		return
	if not _interior_lights_check.toggled.is_connected(_on_interior_lights_toggled):
		_interior_lights_check.toggled.connect(_on_interior_lights_toggled)
	_sync_lighting_controls_from_data()


func _sync_lighting_controls_from_data() -> void:
	if _interior_lights_check != null:
		_interior_lights_check.set_pressed_no_signal(bool(editor_data.get("interior_lights_on", true)))


func _on_interior_lights_toggled(enabled: bool) -> void:
	if bool(editor_data.get("interior_lights_on", true)) == enabled:
		return
	_push_undo_snapshot("interior_lights")
	editor_data["interior_lights_on"] = enabled


func _zoom_at_mouse(factor: float) -> void:
	var mouse_world_before := camera.get_global_mouse_position()

	var new_zoom_value: float = clamp(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(new_zoom_value, new_zoom_value)

	var mouse_world_after := camera.get_global_mouse_position()
	camera.global_position += mouse_world_before - mouse_world_after

#moviemiento con las flechas
func _physics_process(delta: float) -> void:
	_refresh_editor_runtime_if_needed()
	if _editor_view_mode != EditorViewMode.MODE_2D:
		return
	_update_hover_help(delta)
	var direction := Vector2.ZERO

	if _editor_can_pan_with_arrows():
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


func _editor_can_pan_with_arrows() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null:
		return true
	return focus_owner is Button or focus_owner is OptionButton or focus_owner is ItemList or focus_owner is CheckBox
