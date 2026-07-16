extends Control
class_name HUD

signal play_requested
signal pause_requested
signal slower_requested
signal faster_requested
signal stop_and_generate_requested
signal exit_without_graphs_requested
signal return_to_editor_requested
signal view_3d_toggled(enabled: bool)
signal first_person_toggled(enabled: bool)
signal hvac_toggled(enabled: bool)
signal opening_fraction_requested(opening_index: int, open_fraction: float)

const SimuFireThemeScript = preload("res://ui/SimuFireTheme.gd")
## Plantilla de tarjeta (salas/victimas) editable en scenes/HudCard.tscn.
const HudCardScene: PackedScene = preload("res://scenes/HudCard.tscn")
const HUDOpeningActionView = preload("res://ui/HUDOpeningActionView.gd")
const HUDOpeningSummary = preload("res://ui/HUDOpeningSummary.gd")
const HUDPlaybackLabels = preload("res://ui/HUDPlaybackLabels.gd")
const HUDRoomSummary = preload("res://ui/HUDRoomSummary.gd")
const UILocalizationScript = preload("res://ui/UILocalization.gd")
const OPENING_FRACTION_STEPS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
const HUD_PANEL_PATHS: Array[String] = [
	"OpeningsPanel",
	"OpeningActionPanel",
	"TimeControlsPanel",
	"RoomsDataPanel",
	"StatusPanel",
	"VictimsPanel"
]
const EXIT_MENU_EXIT_ONLY: int = 1
const EXIT_MENU_SAVE_GRAPHS: int = 2
const EXIT_MENU_RETURN_EDITOR: int = 3

@export var show_status_panel: bool = false
@export var status_panel_room_id: int = 0
@export var compact_status_panel: bool = true
@export var show_openings_panel: bool = true
@export var show_view_toggle: bool = true

@export_group("Atajos de teclado")
@export var keyboard_shortcuts_enabled: bool = true
@export var key_time_back: Key = KEY_LEFT
@export var key_time_forward: Key = KEY_RIGHT
@export var key_rooms_scroll_up: Key = KEY_UP
@export var key_rooms_scroll_down: Key = KEY_DOWN
@export var key_play_pause: Key = KEY_SPACE
@export var key_stop_and_generate: Key = KEY_END
@export var rooms_scroll_step_px: float = 78.0

@export_group("HUD Layout")
@export_range(10, 28, 1) var time_label_font_size: int = 18
@export_range(8, 20, 1) var shortcut_help_font_size: int = 11
@export_range(8, 22, 1) var opening_status_font_size: int = 12
@export_range(8, 22, 1) var action_button_font_size: int = 12
@export var panel_content_margin_px: Vector2 = Vector2(12.0, 10.0)
@export_range(2, 24, 1) var opening_compact_h_separation_px: int = 10
@export_range(0, 12, 1) var opening_compact_v_separation_px: int = 3
@export_range(8, 20, 1) var opening_compact_label_font_size: int = 11
@export_range(64.0, 180.0, 1.0) var opening_compact_min_label_width_px: float = 88.0
@export_range(88.0, 220.0, 1.0) var opening_compact_wide_label_width_px: float = 132.0
@export_range(24.0, 96.0, 1.0) var openings_panel_base_height_px: float = 44.0
@export_range(12.0, 36.0, 1.0) var openings_panel_row_height_px: float = 18.0
@export_range(80.0, 220.0, 1.0) var openings_panel_min_height_px: float = 110.0
@export_range(160.0, 480.0, 1.0) var openings_panel_max_height_px: float = 320.0

@export_group("Tarjetas de salas")
## Tamaño de fuente del encabezado de cada tarjeta de sala.
@export var font_size_header: int = 13
## Tamaño de fuente de los datos de cada tarjeta de sala.
@export var font_size_data: int = 12
## Margen interior (px) de cada tarjeta de sala.
@export var card_margin_px: int = 7
## Color normal de los datos de cada tarjeta (sin alerta).
@export var card_data_color: Color = Color(0.80, 0.90, 0.80, 1.0)
## Color de tarjeta en estado de alerta (O2 bajo o FED alto).
@export var card_alert_color: Color = Color(1.0, 0.82, 0.65, 1.0)
## Color de tarjeta en estado de flashover o HRR muy alto.
@export var card_flashover_color: Color = Color(1.0, 0.55, 0.55, 1.0)
## Si es true, el aviso de flashover permanece visible mientras flashover_triggered sea true.
@export var flashover_indicator_permanent: bool = true

@onready var status_panel: PanelContainer = get_node_or_null("StatusPanel") as PanelContainer
@onready var status_label: Label = get_node_or_null("StatusPanel/MarginContainer/StatusLabel") as Label
@onready var time_label: Label = $MarginContainer/TimeLabel
@onready var openings_panel: PanelContainer = $OpeningsPanel
@onready var openings_title: Label = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningsTitle
@onready var opening_selector: OptionButton = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningSelector
@onready var opening_status_label: Label = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningStatusLabel
@onready var opening_buttons_row: HBoxContainer = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow
@onready var btn_opening_close: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningClose
@onready var btn_opening_open: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningOpen
@onready var btn_stop_graphs: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnStopGraphs") as Button
@onready var btn_time_back: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeBack") as Button
@onready var btn_play: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPlay") as Button
@onready var btn_pause: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPause") as Button
@onready var btn_time_forward: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeForward") as Button
@onready var btn_view_3d: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnView3D") as Button
@onready var btn_first_person: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnFirstPerson") as Button
@onready var btn_hvac: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnHVAC") as Button
@onready var exit_options_menu: PopupMenu = get_node_or_null("ExitOptionsMenu") as PopupMenu
@onready var time_scale_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/TimeScaleLabel") as Label
@onready var playback_status_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/PlaybackStatusLabel") as Label
@onready var shortcut_help_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ShortcutHelpLabel") as Label
@onready var _rooms_data_panel: PanelContainer = get_node_or_null("RoomsDataPanel") as PanelContainer
@onready var rooms_scroll_container: ScrollContainer = get_node_or_null("RoomsDataPanel/MarginContainer/ScrollContainer") as ScrollContainer
@onready var rooms_data_vbox: GridContainer = get_node_or_null("RoomsDataPanel/MarginContainer/ScrollContainer/RoomsGrid") as GridContainer
@onready var _victims_panel: PanelContainer = get_node_or_null("VictimsPanel") as PanelContainer
@onready var _victims_vbox: VBoxContainer = get_node_or_null("VictimsPanel/MarginContainer/VBoxContainer/VictimsRows") as VBoxContainer

var building: BuildingModel = null
var selected_opening_index: int = 0
var _selector_sync_in_progress: bool = false
var _room_cards: Dictionary = {}  # room_id -> {header, data, card}
var _playback_paused: bool = true
var _simulation_finished: bool = false
var _graphs_launched: bool = false
var _sim_time_s: float = 0.0
var _view_mode_label: String = "2D"
var _first_person_enabled: bool = false
var _opening_compact_grid: GridContainer = null
var _openings_compact_signature: String = ""
var _opening_action_panel: PanelContainer = null
var _opening_action_title: Label = null
var _opening_action_buttons: Array[Button] = []
var _opening_action_index: int = -1
var _victim_rows: Dictionary = {}  # victim_id -> {header: Label, data: Label, card: PanelContainer}


func _ready() -> void:
	UILocalizationScript.ensure_loaded()
	_configure_mouse_filters()
	_ensure_openings_compact_list()
	_ensure_opening_action_panel()
	_ensure_exit_options_menu()
	_ensure_victims_panel()
	_apply_hud_visual_style()
	if status_panel != null:
		status_panel.visible = show_status_panel
	if openings_panel != null:
		openings_panel.visible = show_openings_panel
		openings_panel.scale = Vector2.ONE
	_apply_mode_panel_visibility()

	_ensure_first_person_button()
	_ensure_hvac_button()
	_connect_ui_signals()
	if btn_view_3d != null:
		btn_view_3d.visible = show_view_toggle

	_refresh_opening_controls()
	_update_time_controls(0.0, false, false, false, 1.0)
	_update_view_toggle(false)
	_update_first_person_toggle(false)
	_update_hvac_button(false, false)
	_apply_hud_visual_style()
	_sync_shortcut_labels()
	_apply_hud_panel_layout()
	if get_viewport() != null:
		_connect_once(get_viewport().size_changed, _apply_hud_panel_layout)


func _connect_ui_signals() -> void:
	if opening_selector != null:
		_connect_once(opening_selector.item_selected, _on_opening_selected)
	if btn_opening_open != null:
		_connect_once(btn_opening_open.pressed, _on_open_button_pressed)
	if btn_opening_close != null:
		_connect_once(btn_opening_close.pressed, _on_close_button_pressed)
	if btn_stop_graphs != null:
		_connect_once(btn_stop_graphs.pressed, _on_stop_graphs_pressed)
	if btn_time_back != null:
		_connect_once(btn_time_back.pressed, _on_time_back_pressed)
	if btn_play != null:
		_connect_once(btn_play.pressed, _on_play_pressed)
	if btn_pause != null:
		_connect_once(btn_pause.pressed, _on_pause_pressed)
	if btn_time_forward != null:
		_connect_once(btn_time_forward.pressed, _on_time_forward_pressed)
	if btn_view_3d != null:
		_connect_once(btn_view_3d.pressed, _on_view_3d_pressed)
	if btn_first_person != null:
		_connect_once(btn_first_person.pressed, _on_first_person_pressed)
	if btn_hvac != null:
		_connect_once(btn_hvac.pressed, _on_hvac_pressed)
	if exit_options_menu != null:
		_connect_once(exit_options_menu.id_pressed, _on_exit_option_pressed)


func _connect_once(target_signal: Signal, target_callable: Callable) -> void:
	if not target_signal.is_connected(target_callable):
		target_signal.connect(target_callable)


func _apply_hud_visual_style() -> void:
	# El theme lo asigna SimulationScene.tscn (ui/SimuFireTheme.tres);
	# aqui solo se ajusta el contenido dinamico.
	SimuFireThemeScript.apply_control_tree(self)

	if time_label != null:
		time_label.add_theme_font_override("font", SimuFireThemeScript.title_font())
		time_label.add_theme_font_size_override("font_size", time_label_font_size)
		time_label.add_theme_color_override("font_color", SimuFireThemeScript.TEXT)
	if time_scale_label != null:
		time_scale_label.add_theme_color_override("font_color", SimuFireThemeScript.TEXT)
	if playback_status_label != null:
		playback_status_label.add_theme_color_override("font_color", SimuFireThemeScript.ORANGE)
	if shortcut_help_label != null:
		shortcut_help_label.add_theme_font_override("font", SimuFireThemeScript.body_font())
		shortcut_help_label.add_theme_font_size_override("font_size", shortcut_help_font_size)
		shortcut_help_label.add_theme_color_override("font_color", SimuFireThemeScript.MUTED)
		shortcut_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shortcut_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if opening_status_label != null:
		opening_status_label.add_theme_font_override("font", SimuFireThemeScript.title_font())
		opening_status_label.add_theme_font_size_override("font_size", opening_status_font_size)
	if _opening_compact_grid != null:
		_opening_compact_grid.add_theme_constant_override("h_separation", opening_compact_h_separation_px)
		_opening_compact_grid.add_theme_constant_override("v_separation", opening_compact_v_separation_px)
	if openings_panel != null:
		openings_panel.scale = Vector2.ONE

	for panel_path in HUD_PANEL_PATHS:
		var panel := get_node_or_null(panel_path) as PanelContainer
		if panel != null:
			panel.add_theme_stylebox_override("panel", SimuFireThemeScript.stylebox(SimuFireThemeScript.PANEL, SimuFireThemeScript.BORDER, 1, 0, panel_content_margin_px))

	var action_buttons: Array[Button] = [
		btn_play, btn_pause, btn_time_forward, btn_time_back, btn_view_3d,
		btn_first_person, btn_hvac, btn_opening_close, btn_opening_open, btn_stop_graphs
	]
	for button in action_buttons:
		if button == null:
			continue
		button.text = button.text.to_upper()
		button.add_theme_font_override("font", SimuFireThemeScript.title_font())
		button.add_theme_font_size_override("font_size", action_button_font_size)
		button.focus_mode = Control.FOCUS_NONE


func _apply_hud_panel_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var right_margin: float = 8.0
	var panel_gap: float = 10.0
	var panel_width: float = clampf(viewport_size.x * 0.30, 320.0, 392.0)
	var bottom_reserved: float = 122.0

	if openings_panel != null:
		openings_panel.anchor_left = 1.0
		openings_panel.anchor_right = 1.0
		openings_panel.anchor_top = 1.0
		openings_panel.anchor_bottom = 1.0
		openings_panel.offset_left = -panel_width
		openings_panel.offset_right = -right_margin
		openings_panel.offset_bottom = -bottom_reserved
		var openings_height: float = maxf(openings_panel_min_height_px, openings_panel.offset_bottom - openings_panel.offset_top)
		openings_panel.offset_top = openings_panel.offset_bottom - openings_height

	if _victims_panel != null:
		_victims_panel.anchor_left = 1.0
		_victims_panel.anchor_right = 1.0
		_victims_panel.anchor_top = 1.0
		_victims_panel.anchor_bottom = 1.0
		_victims_panel.offset_left = -panel_width
		_victims_panel.offset_right = -right_margin
		var victims_height: float = clampf(maxf(_victims_panel.size.y, 118.0), 96.0, 156.0)
		var victims_bottom: float = (openings_panel.offset_top if openings_panel != null else -bottom_reserved) - panel_gap
		_victims_panel.offset_bottom = victims_bottom
		_victims_panel.offset_top = victims_bottom - victims_height

	if _rooms_data_panel != null:
		_rooms_data_panel.anchor_left = 1.0
		_rooms_data_panel.anchor_right = 1.0
		_rooms_data_panel.anchor_top = 0.0
		_rooms_data_panel.anchor_bottom = 1.0
		_rooms_data_panel.offset_left = -panel_width
		_rooms_data_panel.offset_right = -right_margin
		_rooms_data_panel.offset_top = 8.0
		var stack_top: float = openings_panel.offset_top if openings_panel != null else -bottom_reserved
		if _victims_panel != null and _victims_panel.visible:
			stack_top = _victims_panel.offset_top
		_rooms_data_panel.offset_bottom = minf(-bottom_reserved, stack_top - panel_gap)
		if viewport_size.y + _rooms_data_panel.offset_bottom - _rooms_data_panel.offset_top < 150.0:
			_rooms_data_panel.offset_bottom = -bottom_reserved


func _configure_mouse_filters() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for panel_path in HUD_PANEL_PATHS:
		var panel := get_node_or_null(panel_path) as Control
		if panel != null:
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if rooms_scroll_container != null:
		rooms_scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP


func _unhandled_key_input(event: InputEvent) -> void:
	if not keyboard_shortcuts_enabled:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if _matches_shortcut(key_event, key_time_back):
		_on_time_back_pressed()
		get_viewport().set_input_as_handled()
	elif _matches_shortcut(key_event, key_time_forward):
		_on_time_forward_pressed()
		get_viewport().set_input_as_handled()
	elif _matches_shortcut(key_event, key_rooms_scroll_up):
		scroll_rooms_panel(-1)
		get_viewport().set_input_as_handled()
	elif _matches_shortcut(key_event, key_rooms_scroll_down):
		scroll_rooms_panel(1)
		get_viewport().set_input_as_handled()
	elif _matches_shortcut(key_event, key_play_pause):
		_on_play_pause_shortcut_pressed()
		get_viewport().set_input_as_handled()
	elif _matches_shortcut(key_event, key_stop_and_generate):
		_on_stop_graphs_pressed()
		get_viewport().set_input_as_handled()


func scroll_rooms_panel(direction: int) -> void:
	if rooms_scroll_container == null or direction == 0:
		return
	var scrollbar := rooms_scroll_container.get_v_scroll_bar()
	if scrollbar == null:
		return
	scrollbar.value = clampf(
		scrollbar.value + rooms_scroll_step_px * float(direction),
		scrollbar.min_value,
		scrollbar.max_value
	)


func bind_building(next_building: BuildingModel) -> void:
	building = next_building
	_refresh_opening_controls()
	_rebuild_rooms_panel()
	_rebuild_victims_panel()
	if building != null:
		_update_hvac_button(building.is_hvac_available(), building.is_hvac_on())


func update_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var step_us: int = int(state.get("step_time_us", 0))
	time_label.text = HUDPlaybackLabels.time_text(sim_time_s) + ("  [%d µs]" % step_us if step_us > 0 else "")
	_view_mode_label = HUDPlaybackLabels.view_mode_label(
		bool(state.get("view_3d_enabled", false)),
		bool(state.get("first_person_enabled", false))
	)
	_first_person_enabled = bool(state.get("first_person_enabled", false))
	_update_time_controls(
		sim_time_s,
		bool(state.get("playback_paused", false)),
		bool(state.get("simulation_finished", false)),
		bool(state.get("graphs_launched", false)),
		float(state.get("time_scale", 0.0))
	)
	_update_view_toggle(bool(state.get("view_3d_enabled", false)))
	_update_first_person_toggle(bool(state.get("first_person_enabled", false)))
	_update_hvac_button(bool(state.get("hvac_exists", false)), bool(state.get("hvac_on", false)))
	if _first_person_enabled:
		hide_opening_action()
	_apply_mode_panel_visibility()

	if not _first_person_enabled:
		_refresh_opening_controls()
		_update_rooms_panel(state)
		_update_victims_panel(state)
		_refresh_opening_action_panel()

	if status_panel == null or status_label == null or not show_status_panel:
		return

	var room_state: Dictionary = state.get(str(status_panel_room_id), {})
	status_label.text = build_room_status_text(room_state)


func show_room_detail(room_id: int) -> void:
	if room_id < 0:
		show_status_panel = false
		if status_panel != null:
			status_panel.visible = false
		return
	status_panel_room_id = room_id
	show_status_panel = true
	if status_panel != null:
		status_panel.visible = true


func build_room_status_text(room_state: Dictionary) -> String:
	return HUDRoomSummary.detail_text(room_state)


func _rebuild_rooms_panel() -> void:
	if rooms_data_vbox == null:
		return
	rooms_data_vbox.columns = 1
	for child in rooms_data_vbox.get_children():
		child.queue_free()
	_room_cards.clear()

	if building == null:
		return

	var rects: Dictionary = building.get_room_rects_m()
	var sorted_ids: Array = []
	for k in rects.keys():
		sorted_ids.append(int(k))
	sorted_ids.sort()

	for room_id in sorted_ids:
		var parts: Dictionary = _instance_hud_card(62.0, card_margin_px - 1)
		var card := parts["card"] as PanelContainer
		var header := parts["header"] as Label
		var data_lbl := parts["data"] as Label
		_style_room_card(card, "normal", false)
		header.text = "R%d" % room_id
		rooms_data_vbox.add_child(card)
		_room_cards[room_id] = {"header": header, "data": data_lbl, "card": card}


## Instancia scenes/HudCard.tscn y aplica las fuentes/colores configurados
## en los exports del HUD. Devuelve {card, header, data}.
func _instance_hud_card(min_height_px: float, vertical_margin_px: int) -> Dictionary:
	var card := HudCardScene.instantiate() as PanelContainer
	card.custom_minimum_size = Vector2(0.0, min_height_px)
	var margin := card.get_node("Margin") as MarginContainer
	margin.add_theme_constant_override("margin_left", card_margin_px)
	margin.add_theme_constant_override("margin_top", vertical_margin_px)
	margin.add_theme_constant_override("margin_right", card_margin_px)
	margin.add_theme_constant_override("margin_bottom", vertical_margin_px)
	var header := card.get_node("Margin/Rows/Header") as Label
	header.add_theme_font_override("font", SimuFireThemeScript.title_font())
	header.add_theme_font_size_override("font_size", font_size_header)
	header.add_theme_color_override("font_color", SimuFireThemeScript.TEXT)
	var data_lbl := card.get_node("Margin/Rows/Data") as Label
	data_lbl.add_theme_font_override("font", SimuFireThemeScript.body_font())
	data_lbl.add_theme_font_size_override("font_size", font_size_data)
	data_lbl.add_theme_color_override("font_color", card_data_color)
	return {"card": card, "header": header, "data": data_lbl}


func _update_rooms_panel(state: Dictionary) -> void:
	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	for room_id in _room_cards.keys():
		var d: Dictionary = _room_cards[room_id]
		var rs: Dictionary = state.get(str(room_id), {})
		var header_lbl: Label = d["header"] as Label
		var data_lbl: Label = d["data"] as Label
		var card: PanelContainer = d["card"] as PanelContainer

		if rs.is_empty():
			data_lbl.text = UILocalizationScript.t("hud.no_data", "Sin datos")
			_style_room_card(card, "normal", show_status_panel and room_id == status_panel_room_id)
			continue

		var summary: Dictionary = HUDRoomSummary.card_summary(int(room_id), rs, sim_time_s, flashover_indicator_permanent)
		header_lbl.text = String(summary.get("header", "R%d" % int(room_id)))
		data_lbl.text = String(summary.get("text", UILocalizationScript.t("hud.no_data", "Sin datos")))
		data_lbl.add_theme_color_override("font_color", card_data_color)
		_style_room_card(card, String(summary.get("severity", "normal")), show_status_panel and room_id == status_panel_room_id)


func _style_room_card(card: PanelContainer, severity: String, selected: bool) -> void:
	if card == null:
		return
	var bg: Color = Color(0.01, 0.03, 0.04, 0.88)
	var border: Color = Color(0.12, 0.20, 0.24, 0.90)
	var border_width: int = 1
	if severity == "flash":
		border = card_flashover_color
		border_width = 2
	elif severity == "alert":
		border = card_alert_color
		border_width = 2
	elif selected:
		border = SimuFireThemeScript.ORANGE
		border_width = 2
	card.modulate = Color(1.0, 1.0, 1.0, 1.0)
	card.add_theme_stylebox_override("panel", SimuFireThemeScript.stylebox(bg, border, border_width, 0, Vector2(7.0, 6.0)))


func _is_flashover_indicator_visible(room_state: Dictionary, sim_time_s: float) -> bool:
	return HUDRoomSummary.is_flashover_visible(room_state, sim_time_s, flashover_indicator_permanent)


func _update_view_toggle(is_3d_enabled: bool) -> void:
	if btn_view_3d == null:
		return
	btn_view_3d.visible = show_view_toggle
	btn_view_3d.set_pressed_no_signal(is_3d_enabled)
	btn_view_3d.text = "3D"


func _apply_mode_panel_visibility() -> void:
	if status_panel != null:
		status_panel.visible = show_status_panel and not _first_person_enabled
	if openings_panel != null:
		openings_panel.visible = show_openings_panel and not _first_person_enabled
	if _rooms_data_panel != null:
		_rooms_data_panel.visible = not _first_person_enabled
	if _victims_panel != null:
		_victims_panel.visible = (not _first_person_enabled) and not _victim_rows.is_empty()
	_apply_hud_panel_layout()


func _ensure_first_person_button() -> void:
	if btn_first_person != null:
		return
	var row := get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow") as HBoxContainer
	if row == null:
		return
	btn_first_person = Button.new()
	btn_first_person.name = "BtnFirstPerson"
	btn_first_person.custom_minimum_size = Vector2(70.0, 34.0)
	btn_first_person.toggle_mode = true
	btn_first_person.text = "FP"
	row.add_child(btn_first_person)


func _update_first_person_toggle(enabled: bool) -> void:
	if btn_first_person == null:
		return
	btn_first_person.set_pressed_no_signal(enabled)
	btn_first_person.text = "FP"


func _ensure_hvac_button() -> void:
	if btn_hvac != null:
		return
	var row := get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow") as HBoxContainer
	if row == null:
		return
	btn_hvac = Button.new()
	btn_hvac.name = "BtnHVAC"
	btn_hvac.custom_minimum_size = Vector2(92.0, 34.0)
	btn_hvac.toggle_mode = true
	btn_hvac.text = "HVAC OFF"
	row.add_child(btn_hvac)


func _ensure_exit_options_menu() -> void:
	if exit_options_menu == null:
		exit_options_menu = PopupMenu.new()
		exit_options_menu.name = "ExitOptionsMenu"
		add_child(exit_options_menu)
	exit_options_menu.clear()
	exit_options_menu.add_item(UILocalizationScript.t("hud.exit_only", "Salir sin guardar"), EXIT_MENU_EXIT_ONLY)
	exit_options_menu.add_item(UILocalizationScript.t("hud.exit_editor", "Volver al editor"), EXIT_MENU_RETURN_EDITOR)
	exit_options_menu.add_item(UILocalizationScript.t("hud.exit_save_graphs", "Salir y guardar + graficas"), EXIT_MENU_SAVE_GRAPHS)
	exit_options_menu.add_theme_font_override("font", SimuFireThemeScript.title_font())
	exit_options_menu.add_theme_font_size_override("font_size", action_button_font_size)
	exit_options_menu.add_theme_stylebox_override("panel", SimuFireThemeScript.stylebox(SimuFireThemeScript.PANEL_DARK, SimuFireThemeScript.BORDER, 1, 0, Vector2(10.0, 8.0)))
	exit_options_menu.add_theme_stylebox_override("hover", SimuFireThemeScript.stylebox(Color(0.04, 0.10, 0.12, 0.98), SimuFireThemeScript.BLUE, 1, 0, Vector2(10.0, 8.0)))
	exit_options_menu.add_theme_color_override("font_color", SimuFireThemeScript.TEXT)
	exit_options_menu.add_theme_color_override("font_hover_color", Color.WHITE)


func _ensure_victims_panel() -> void:
	var title_lbl := get_node_or_null("VictimsPanel/MarginContainer/VBoxContainer/VictimsPanelTitle") as Label
	if title_lbl == null:
		return
	title_lbl.add_theme_font_override("font", SimuFireThemeScript.title_font())
	title_lbl.add_theme_font_size_override("font_size", font_size_header)
	title_lbl.add_theme_color_override("font_color", SimuFireThemeScript.TEXT)


func _rebuild_victims_panel() -> void:
	if _victims_vbox == null:
		return
	for child in _victims_vbox.get_children():
		child.queue_free()
	_victim_rows.clear()

	var victims_list: Array = []
	if building != null:
		victims_list = Array(building.victims)

	if victims_list.is_empty():
		if _victims_panel != null:
			_victims_panel.visible = false
		return

	for vic in victims_list:
		if typeof(vic) != TYPE_DICTIONARY:
			continue
		var vic_id: String = String(vic.get("id", ""))
		if vic_id.is_empty():
			continue
		var vic_name: String = String(vic.get("name", vic_id))
		var room_id: int = int(vic.get("room_id", 0))

		var parts: Dictionary = _instance_hud_card(46.0, 3)
		var card := parts["card"] as PanelContainer
		var header := parts["header"] as Label
		var data_lbl := parts["data"] as Label
		_style_room_card(card, "normal", false)
		header.text = "%s (R%d)" % [vic_name, room_id]
		data_lbl.text = "FED: 0.00"

		_victims_vbox.add_child(card)
		_victim_rows[vic_id] = {"header": header, "data": data_lbl, "card": card}

	if _victims_panel != null:
		_victims_panel.visible = not _victim_rows.is_empty()
		_apply_mode_panel_visibility()


func _update_victims_panel(state: Dictionary) -> void:
	if _first_person_enabled or _victims_panel == null or not _victims_panel.visible:
		return
	var victims_state: Array = Array(state.get("victims", []))
	for vic_state in victims_state:
		if typeof(vic_state) != TYPE_DICTIONARY:
			continue
		var vic_id: String = String(vic_state.get("id", ""))
		if vic_id.is_empty() or not _victim_rows.has(vic_id):
			continue
		var row: Dictionary = _victim_rows[vic_id]
		var fed: float = float(vic_state.get("fed", 0.0))
		var incapacitated: bool = bool(vic_state.get("incapacitated", false))

		var data_lbl: Label = row["data"] as Label
		var card: PanelContainer = row["card"] as PanelContainer

		var status_suffix: String = ""
		var severity: String = "normal"
		if incapacitated:
			status_suffix = "  INCAPACITADO"
			severity = "flash"
		elif fed >= 0.5:
			severity = "alert"
		data_lbl.text = "FED: %.2f%s" % [fed, status_suffix]
		_style_room_card(card, severity, false)


func _update_hvac_button(hvac_exists: bool, hvac_on: bool) -> void:
	if btn_hvac == null:
		return
	btn_hvac.visible = hvac_exists
	btn_hvac.disabled = not hvac_exists
	btn_hvac.set_pressed_no_signal(hvac_on)
	btn_hvac.text = "HVAC ON" if hvac_on else "HVAC OFF"


func _ensure_openings_compact_list() -> void:
	if _opening_compact_grid != null:
		return
	var box := get_node_or_null("OpeningsPanel/MarginContainer/VBoxContainer") as VBoxContainer
	if box == null:
		return
	_opening_compact_grid = GridContainer.new()
	_opening_compact_grid.name = "OpeningsCompactList"
	_opening_compact_grid.visible = false
	_opening_compact_grid.columns = 2
	_opening_compact_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opening_compact_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_opening_compact_grid.add_theme_constant_override("h_separation", opening_compact_h_separation_px)
	_opening_compact_grid.add_theme_constant_override("v_separation", opening_compact_v_separation_px)
	box.add_child(_opening_compact_grid)


func _ensure_opening_action_panel() -> void:
	if _opening_action_panel != null:
		return
	var view: Dictionary = HUDOpeningActionView.create(self, OPENING_FRACTION_STEPS, _on_opening_fraction_button_pressed)
	_opening_action_panel = view.get("panel") as PanelContainer
	_opening_action_title = view.get("title") as Label
	_opening_action_buttons.clear()
	for raw_button in Array(view.get("buttons", [])):
		if raw_button is Button:
			_opening_action_buttons.append(raw_button)


func _set_openings_panel_compact() -> void:
	_ensure_openings_compact_list()
	if opening_selector != null:
		opening_selector.visible = false
	if opening_status_label != null:
		opening_status_label.visible = false
	if opening_buttons_row != null:
		opening_buttons_row.visible = false
	if _opening_compact_grid != null:
		_opening_compact_grid.visible = true
	if openings_title != null:
		openings_title.text = UILocalizationScript.t("hud.openings_title", "Estado de aperturas")


func _update_openings_compact_list() -> void:
	if _opening_compact_grid == null:
		return
	if building == null:
		_rebuild_openings_compact_grid(["Sin BuildingModel"], 1)
		return
	var summaries: Array[Dictionary] = building.build_opening_summaries()
	if summaries.is_empty():
		_rebuild_openings_compact_grid(["Sin aperturas"], 1)
		return
	var items: Array = []
	var columns: int = 4 if summaries.size() > 18 else (3 if summaries.size() > 8 else 2)
	for summary in summaries:
		items.append(summary)
	_rebuild_openings_compact_grid(items, columns)


func _rebuild_openings_compact_grid(items: Array, columns: int) -> void:
	if _opening_compact_grid == null:
		return
	var signature: String = "%d|%s" % [columns, HUDOpeningSummary.compact_signature(items)]
	if signature == _openings_compact_signature:
		return
	_openings_compact_signature = signature
	for child in _opening_compact_grid.get_children():
		child.queue_free()
	_opening_compact_grid.columns = maxi(1, columns)
	_resize_openings_panel_for_count(items.size(), columns)
	for text_value in items:
		var label := Label.new()
		var summary: Dictionary = Dictionary(text_value) if text_value is Dictionary else {}
		label.text = HUDOpeningSummary.compact_label(summary) if not summary.is_empty() else String(text_value)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size = Vector2(opening_compact_min_label_width_px if columns >= 3 else opening_compact_wide_label_width_px, 0.0)
		label.add_theme_font_override("font", SimuFireThemeScript.body_font())
		label.add_theme_font_size_override("font_size", opening_compact_label_font_size)
		label.add_theme_color_override("font_color", HUDOpeningSummary.compact_color(summary))
		_opening_compact_grid.add_child(label)


func _resize_openings_panel_for_count(item_count: int, columns: int) -> void:
	if openings_panel == null:
		return
	openings_panel.scale = Vector2.ONE
	var rows: int = ceili(float(maxi(1, item_count)) / float(maxi(1, columns)))
	var target_height: float = clampf(
		openings_panel_base_height_px + float(rows) * openings_panel_row_height_px,
		openings_panel_min_height_px,
		openings_panel_max_height_px
	)
	openings_panel.offset_top = openings_panel.offset_bottom - target_height
	_apply_hud_panel_layout()


func _refresh_opening_controls() -> void:
	if openings_panel == null:
		return

	openings_panel.visible = show_openings_panel and not _first_person_enabled
	if not show_openings_panel or _first_person_enabled:
		return

	_set_openings_panel_compact()
	_update_openings_compact_list()


func _refresh_opening_status() -> void:
	if openings_panel == null or not show_openings_panel:
		return

	if building == null or building.get_opening_count() <= 0:
		_set_openings_panel_empty("No hay aperturas disponibles")
		return

	if selected_opening_index >= building.get_opening_count():
		selected_opening_index = max(0, building.get_opening_count() - 1)

	var status_text: String = building.get_opening_status_text(selected_opening_index)
	if opening_status_label != null:
		opening_status_label.text = status_text

	var op: OpeningModel = building.get_opening_at(selected_opening_index)
	var has_selection: bool = op != null
	if btn_opening_open != null:
		btn_opening_open.disabled = not has_selection or op.is_fully_open()
	if btn_opening_close != null:
		btn_opening_close.disabled = not has_selection or op.is_closed()


func _set_openings_panel_empty(message: String) -> void:
	if opening_selector != null:
		_selector_sync_in_progress = true
		opening_selector.clear()
		_selector_sync_in_progress = false
	if opening_status_label != null:
		opening_status_label.text = message
	if btn_opening_open != null:
		btn_opening_open.disabled = true
	if btn_opening_close != null:
		btn_opening_close.disabled = true


func show_opening_action(opening_index: int, screen_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if building == null or building.get_opening_at(opening_index) == null:
		hide_opening_action()
		return
	_ensure_opening_action_panel()
	_opening_action_index = opening_index
	selected_opening_index = opening_index
	if _opening_action_panel != null:
		_opening_action_panel.visible = true
		_refresh_opening_action_panel()
		if screen_pos.x >= 0.0 and screen_pos.y >= 0.0:
			_position_opening_action_panel(screen_pos)


func hide_opening_action() -> void:
	_opening_action_index = -1
	if _opening_action_panel != null:
		_opening_action_panel.visible = false


func _refresh_opening_action_panel() -> void:
	if _opening_action_panel == null or not _opening_action_panel.visible:
		return
	if building == null:
		hide_opening_action()
		return
	var op: OpeningModel = building.get_opening_at(_opening_action_index)
	if op == null:
		hide_opening_action()
		return
	var open_fraction: float = clampf(op.open_fraction, 0.0, 1.0)
	HUDOpeningActionView.update(
		_opening_action_title,
		_opening_action_buttons,
		OPENING_FRACTION_STEPS,
		"%s | %s" % [
			building.get_opening_label(_opening_action_index),
			building.get_opening_status_text(_opening_action_index)
		],
		open_fraction
	)


func _position_opening_action_panel(screen_pos: Vector2) -> void:
	HUDOpeningActionView.position_panel(_opening_action_panel, screen_pos, get_viewport_rect().size)


func _update_time_controls(
	sim_time_s: float,
	playback_paused: bool,
	simulation_finished: bool,
	graphs_launched: bool,
	time_scale: float
) -> void:
	_sim_time_s = sim_time_s
	_playback_paused = playback_paused
	_simulation_finished = simulation_finished
	_graphs_launched = graphs_launched

	if time_scale_label != null:
		time_scale_label.text = HUDPlaybackLabels.time_scale_text(time_scale)

	if playback_status_label != null:
		playback_status_label.text = HUDPlaybackLabels.playback_status_text(_view_mode_label, playback_paused, simulation_finished)

	if btn_play != null:
		btn_play.disabled = simulation_finished
		btn_play.text = HUDPlaybackLabels.play_button_text(playback_paused)
	if btn_pause != null:
		btn_pause.disabled = simulation_finished or playback_paused
	if btn_time_back != null:
		btn_time_back.disabled = simulation_finished
	if btn_time_forward != null:
		btn_time_forward.disabled = simulation_finished
	if btn_stop_graphs != null:
		btn_stop_graphs.disabled = false
		btn_stop_graphs.text = UILocalizationScript.t("hud.exit", "SALIR")
	_sync_shortcut_labels()


func _sync_shortcut_labels() -> void:
	if btn_time_back != null:
		btn_time_back.text = "-T"
		btn_time_back.tooltip_text = UILocalizationScript.fmt("hud.tooltip_time_back", "%s: retroceder escala de tiempo", [HUDPlaybackLabels.key_label(key_time_back)])
	if btn_time_forward != null:
		btn_time_forward.text = "+T"
		btn_time_forward.tooltip_text = UILocalizationScript.fmt("hud.tooltip_time_forward", "%s: avanzar escala de tiempo", [HUDPlaybackLabels.key_label(key_time_forward)])
	if btn_play != null:
		btn_play.text = HUDPlaybackLabels.play_button_text(_playback_paused)
		btn_play.tooltip_text = UILocalizationScript.fmt("hud.tooltip_play_pause", "%s: reanudar/pausa", [HUDPlaybackLabels.key_label(key_play_pause)])
	if btn_pause != null:
		btn_pause.visible = false
	if btn_stop_graphs != null:
		btn_stop_graphs.text = UILocalizationScript.t("hud.exit", "SALIR")
		btn_stop_graphs.tooltip_text = UILocalizationScript.fmt("hud.tooltip_exit", "%s: opciones de salida", [HUDPlaybackLabels.key_label(key_stop_and_generate)])
	if btn_view_3d != null:
		btn_view_3d.tooltip_text = UILocalizationScript.t("hud.tooltip_3d", "Alternar vista 3D")
	if btn_first_person != null:
		btn_first_person.tooltip_text = UILocalizationScript.t("hud.tooltip_fp", "Entrar en primera persona")
	if btn_hvac != null:
		btn_hvac.tooltip_text = UILocalizationScript.t("hud.tooltip_hvac", "Activar o desactivar HVAC")
	if shortcut_help_label != null:
		shortcut_help_label.text = HUDPlaybackLabels.shortcut_help_text(
			key_time_back,
			key_time_forward,
			key_rooms_scroll_up,
			key_rooms_scroll_down,
			key_play_pause,
			key_stop_and_generate
		)


func _matches_shortcut(event: InputEventKey, keycode: Key) -> bool:
	return HUDPlaybackLabels.matches_shortcut(event, keycode)


func _can_stop_and_generate_graphs() -> bool:
	return _sim_time_s > 0.0 and not _graphs_launched


func _on_opening_selected(item_index: int) -> void:
	if _selector_sync_in_progress or opening_selector == null:
		return

	selected_opening_index = opening_selector.get_item_id(item_index)
	_refresh_opening_status()


func _on_open_button_pressed() -> void:
	opening_fraction_requested.emit(selected_opening_index, 1.0)


func _on_close_button_pressed() -> void:
	opening_fraction_requested.emit(selected_opening_index, 0.0)


func _on_opening_fraction_button_pressed(open_fraction: float) -> void:
	if _opening_action_index < 0:
		return
	opening_fraction_requested.emit(_opening_action_index, open_fraction)


func _on_stop_graphs_pressed() -> void:
	_popup_exit_options()


func _popup_exit_options() -> void:
	_ensure_exit_options_menu()
	if exit_options_menu == null:
		return
	var graphs_index: int = exit_options_menu.get_item_index(EXIT_MENU_SAVE_GRAPHS)
	if graphs_index >= 0:
		exit_options_menu.set_item_disabled(graphs_index, not _can_stop_and_generate_graphs())
	var popup_pos := Vector2i(32, 32)
	if btn_stop_graphs != null:
		var rect: Rect2 = btn_stop_graphs.get_global_rect()
		popup_pos = Vector2i(int(rect.position.x), int(rect.position.y + rect.size.y + 4.0))
	exit_options_menu.popup(Rect2i(popup_pos, Vector2i(0, 0)))


func _on_exit_option_pressed(id: int) -> void:
	match id:
		EXIT_MENU_EXIT_ONLY:
			exit_without_graphs_requested.emit()
		EXIT_MENU_RETURN_EDITOR:
			return_to_editor_requested.emit()
		EXIT_MENU_SAVE_GRAPHS:
			if _can_stop_and_generate_graphs():
				stop_and_generate_requested.emit()


func _on_time_back_pressed() -> void:
	slower_requested.emit()


func _on_play_pressed() -> void:
	if _simulation_finished:
		return
	if _playback_paused:
		play_requested.emit()
	else:
		pause_requested.emit()


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_play_pause_shortcut_pressed() -> void:
	if _simulation_finished:
		return
	if _playback_paused:
		play_requested.emit()
	else:
		pause_requested.emit()


func _on_time_forward_pressed() -> void:
	faster_requested.emit()


func _on_view_3d_pressed() -> void:
	if btn_view_3d == null:
		return
	view_3d_toggled.emit(btn_view_3d.button_pressed)


func _on_first_person_pressed() -> void:
	if btn_first_person == null:
		return
	first_person_toggled.emit(btn_first_person.button_pressed)


func _on_hvac_pressed() -> void:
	if btn_hvac == null:
		return
	hvac_toggled.emit(btn_hvac.button_pressed)
