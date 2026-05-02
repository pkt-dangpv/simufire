extends Control
class_name HUD

signal play_requested
signal pause_requested
signal slower_requested
signal faster_requested
signal stop_and_generate_requested

@export var show_status_panel: bool = false
@export var status_panel_room_id: int = 0
@export var compact_status_panel: bool = true
@export var show_openings_panel: bool = true

## Tamaño de fuente del encabezado de cada tarjeta de sala.
@export var font_size_header: int = 11
## Tamaño de fuente de los datos de cada tarjeta de sala.
@export var font_size_data: int = 10
## Margen interior (px) de cada tarjeta de sala.
@export var card_margin_px: int = 5
## Color normal de los datos de cada tarjeta (sin alerta).
@export var card_data_color: Color = Color(0.80, 0.90, 0.80, 1.0)
## Color de tarjeta en estado de alerta (O2 bajo o FED alto).
@export var card_alert_color: Color = Color(1.0, 0.82, 0.65, 1.0)
## Color de tarjeta en estado de flashover o HRR muy alto.
@export var card_flashover_color: Color = Color(1.0, 0.55, 0.55, 1.0)

@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel
@onready var time_label: Label = $MarginContainer/TimeLabel
@onready var openings_panel: PanelContainer = $OpeningsPanel
@onready var opening_selector: OptionButton = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningSelector
@onready var opening_status_label: Label = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningStatusLabel
@onready var btn_opening_close: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningClose
@onready var btn_opening_open: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningOpen
@onready var btn_stop_graphs: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnStopGraphs") as Button
@onready var btn_time_back: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeBack") as Button
@onready var btn_play: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPlay") as Button
@onready var btn_pause: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPause") as Button
@onready var btn_time_forward: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeForward") as Button
@onready var time_scale_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/TimeScaleLabel") as Label
@onready var playback_status_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/PlaybackStatusLabel") as Label
@onready var rooms_data_vbox: GridContainer = get_node_or_null("RoomsDataPanel/MarginContainer/ScrollContainer/RoomsGrid") as GridContainer

var building: BuildingModel = null
var selected_opening_index: int = 0
var _selector_sync_in_progress: bool = false
var _known_opening_count: int = -1
var _room_cards: Dictionary = {}  # room_id -> {header, data, card}


func _ready() -> void:
	if status_panel != null:
		status_panel.visible = show_status_panel
	if openings_panel != null:
		openings_panel.visible = show_openings_panel

	if opening_selector != null and not opening_selector.item_selected.is_connected(_on_opening_selected):
		opening_selector.item_selected.connect(_on_opening_selected)
	if btn_opening_open != null and not btn_opening_open.pressed.is_connected(_on_open_button_pressed):
		btn_opening_open.pressed.connect(_on_open_button_pressed)
	if btn_opening_close != null and not btn_opening_close.pressed.is_connected(_on_close_button_pressed):
		btn_opening_close.pressed.connect(_on_close_button_pressed)
	if btn_stop_graphs != null and not btn_stop_graphs.pressed.is_connected(_on_stop_graphs_pressed):
		btn_stop_graphs.pressed.connect(_on_stop_graphs_pressed)
	if btn_time_back != null and not btn_time_back.pressed.is_connected(_on_time_back_pressed):
		btn_time_back.pressed.connect(_on_time_back_pressed)
	if btn_play != null and not btn_play.pressed.is_connected(_on_play_pressed):
		btn_play.pressed.connect(_on_play_pressed)
	if btn_pause != null and not btn_pause.pressed.is_connected(_on_pause_pressed):
		btn_pause.pressed.connect(_on_pause_pressed)
	if btn_time_forward != null and not btn_time_forward.pressed.is_connected(_on_time_forward_pressed):
		btn_time_forward.pressed.connect(_on_time_forward_pressed)

	_refresh_opening_controls()
	_update_time_controls(0.0, false, false, false, 1.0)


func bind_building(next_building: BuildingModel) -> void:
	building = next_building
	_known_opening_count = -1
	_refresh_opening_controls()
	_rebuild_rooms_panel()


func update_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var total_seconds: int = int(sim_time_s)
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = int(total_seconds % 60)
	time_label.text = "TIME %02d:%02d" % [minutes, seconds]
	_update_time_controls(
		sim_time_s,
		bool(state.get("playback_paused", false)),
		bool(state.get("simulation_finished", false)),
		bool(state.get("graphs_launched", false)),
		float(state.get("time_scale", 0.0))
	)

	_refresh_opening_controls()
	_update_rooms_panel(state)

	if status_panel == null or not show_status_panel:
		return

	var room_state: Dictionary = state.get(str(status_panel_room_id), {})
	status_label.text = build_room_status_text(room_state)


func build_room_status_text(room_state: Dictionary) -> String:
	if room_state.is_empty():
		return "Sin datos"

	if compact_status_panel:
		var compact_lines: Array[String] = [
			"HRR %.0f kW" % float(room_state.get("hrr_kw", 0.0)),
			"T@0.9 %.0f C | O2 %.1f%%" % [
				float(room_state.get("temp_at_0_9m_c", room_state.get("temp_lower_c", 0.0))),
				float(room_state.get("o2", 0.0)) * 100.0
			],
			"SmL %.2f m | CO %.0f ppm" % [
				float(room_state.get("smoke_layer_m", room_state.get("h_layer_m", 0.0))),
				float(room_state.get("co_ppm", 0.0))
			]
		]

		if bool(room_state.get("flashover_triggered", false)):
			compact_lines.append("FLASHOVER")

		return "\n".join(PackedStringArray(compact_lines))

	var lines: Array[String] = [
		"HRR: %.0f kW" % float(room_state.get("hrr_kw", 0.0)),
		"Upper: %.1f C" % float(room_state.get("temp_upper_c", 0.0)),
		"Lower: %.1f C" % float(room_state.get("temp_lower_c", 0.0)),
		"T@0.9m: %.1f C" % float(room_state.get("temp_at_0_9m_c", room_state.get("temp_lower_c", 0.0))),
		"SmokeLayer: %.2f m" % float(room_state.get("smoke_layer_m", room_state.get("h_layer_m", 0.0))),
		"HotLayer: %.2f m" % float(room_state.get("hot_layer_m", room_state.get("thermal_layer_m", 0.0))),
		"Layer150C: %.2f m" % float(room_state.get("layer_150c_m", 0.0)),
		"T@1.8m: %.1f C" % float(room_state.get("temp_at_1_8m_c", 0.0)),
		"O2: %.1f%%" % (float(room_state.get("o2", 0.0)) * 100.0),
		"Smoke: %.4f kg" % float(room_state.get("smoke_kg", 0.0)),
		"CO: %.0f ppm" % float(room_state.get("co_ppm", 0.0)),
		"P: %.2f Pa" % float(room_state.get("overpressure_pa", 0.0))
	]

	if bool(room_state.get("flashover_triggered", false)):
		lines.append("Flashover: true")

	return "\n".join(PackedStringArray(lines))


func _rebuild_rooms_panel() -> void:
	if rooms_data_vbox == null:
		return
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
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", card_margin_px)
		margin.add_theme_constant_override("margin_top", card_margin_px - 1)
		margin.add_theme_constant_override("margin_right", card_margin_px)
		margin.add_theme_constant_override("margin_bottom", card_margin_px - 1)
		card.add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 1)
		margin.add_child(vbox)

		var header := Label.new()
		header.add_theme_font_size_override("font_size", font_size_header)
		header.text = "R%d" % room_id
		vbox.add_child(header)

		var data_lbl := Label.new()
		data_lbl.add_theme_font_size_override("font_size", font_size_data)
		data_lbl.text = "\u2014"
		data_lbl.modulate = card_data_color
		vbox.add_child(data_lbl)

		rooms_data_vbox.add_child(card)
		_room_cards[room_id] = {"header": header, "data": data_lbl, "card": card}


func _update_rooms_panel(state: Dictionary) -> void:
	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	for room_id in _room_cards.keys():
		var d: Dictionary = _room_cards[room_id]
		var rs: Dictionary = state.get(str(room_id), {})
		var header_lbl: Label = d["header"] as Label
		var data_lbl: Label = d["data"] as Label
		var card: PanelContainer = d["card"] as PanelContainer

		if rs.is_empty():
			data_lbl.text = "Sin datos"
			card.modulate = Color(1, 1, 1, 1)
			continue

		var room_name: String = String(rs.get("name", ""))
		if room_name != "":
			header_lbl.text = "R%d %s" % [room_id, room_name]
		else:
			header_lbl.text = "R%d" % room_id

		var hrr: float = float(rs.get("hrr_kw", 0.0))
		var t_upper: float = float(rs.get("temp_upper_c", 20.0))
		var t_lower: float = float(rs.get("temp_lower_c", 20.0))
		var t09: float = float(rs.get("temp_at_0_9m_c", t_lower))
		var o2_pct: float = float(rs.get("o2", 0.209)) * 100.0
		var smoke_l: float = float(rs.get("smoke_layer_m", rs.get("h_layer_m", float(rs.get("height_m", 2.4)))))
		var co_ppm: float = float(rs.get("co_ppm", 0.0))
		var fed: float = float(rs.get("fed", 0.0))
		var flashover: bool = _is_flashover_indicator_visible(rs, sim_time_s)
		var fuel_capacity_mj: float = float(rs.get("fuel_capacity_MJ", rs.get("fuel_energy_MJ", 0.0)))
		var remaining_fuel_mj: float = float(rs.get("fuel_objects_remaining_MJ", rs.get("remaining_fuel_MJ", 0.0)))

		var svv_pct: float = float(rs.get("svv_worst_pct", -1.0))
		if svv_pct < 0.0:
			var h_m: float = float(rs.get("height_m", 2.4))
			var l150: float = float(rs.get("layer_150c_m", h_m))
			if l150 >= 1.8:
				svv_pct = 100.0
			elif l150 >= 0.5:
				svv_pct = 90.0 + 9.0 * (l150 - 0.5) / 1.3
			else:
				svv_pct = clampf(l150 / 0.5 * 90.0, 0.0, 90.0)

		var lines: PackedStringArray = PackedStringArray()
		if hrr > 0.5:
			lines.append("HRR %.0fkW" % hrr)
		lines.append("T+ %.0f  T- %.0fC" % [t_upper, t_lower])
		lines.append("T@0.9m %.0fC" % t09)
		lines.append("O2 %.1f%%  SmL %.2fm" % [o2_pct, smoke_l])
		if co_ppm > 1.0:
			lines.append("CO %.0fppm" % co_ppm)
		lines.append("Comb %.0f/%.0fMJ" % [remaining_fuel_mj, fuel_capacity_mj])
		lines.append("FED %.2f  SVV %.0f%%" % [fed, svv_pct])
		if flashover:
			lines.append("!FLASHOVER!")
		data_lbl.text = "\n".join(lines)

		if flashover or hrr > 500.0:
			card.modulate = card_flashover_color
		elif o2_pct < 18.0 or fed > 0.3:
			card.modulate = card_alert_color
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _is_flashover_indicator_visible(room_state: Dictionary, sim_time_s: float) -> bool:
	if not bool(room_state.get("flashover_triggered", false)):
		return false
	var flash_time_s: float = float(room_state.get("flashover_time_s", -1.0))
	if flash_time_s < 0.0:
		return true
	return sim_time_s <= flash_time_s + 22.0


func _refresh_opening_controls() -> void:
	if openings_panel == null:
		return

	openings_panel.visible = show_openings_panel
	if not show_openings_panel:
		return

	if building == null or opening_selector == null:
		_set_openings_panel_empty("Sin BuildingModel enlazado")
		return

	var opening_count: int = building.get_opening_count()
	if opening_count <= 0:
		_set_openings_panel_empty("No hay puertas ni ventanas")
		return

	if opening_count != _known_opening_count or opening_selector.get_item_count() != opening_count:
		_selector_sync_in_progress = true
		opening_selector.clear()
		for summary in building.build_opening_summaries():
			var item_label: String = String(summary.get("label", "Apertura"))
			var opening_index: int = int(summary.get("index", opening_selector.get_item_count()))
			opening_selector.add_item(item_label, opening_index)

		selected_opening_index = clampi(selected_opening_index, 0, opening_count - 1)
		var selector_idx: int = _find_selector_item_by_opening_index(selected_opening_index)
		if selector_idx == -1:
			selected_opening_index = int(opening_selector.get_item_id(0))
			selector_idx = 0
		opening_selector.select(selector_idx)
		_known_opening_count = opening_count
		_selector_sync_in_progress = false

	_refresh_opening_status()


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


func _update_time_controls(
	sim_time_s: float,
	playback_paused: bool,
	simulation_finished: bool,
	graphs_launched: bool,
	time_scale: float
) -> void:
	if time_scale_label != null:
		time_scale_label.text = _format_time_scale_label(time_scale)

	if playback_status_label != null:
		if simulation_finished:
			playback_status_label.text = "DETENIDA"
		elif playback_paused:
			playback_status_label.text = "PAUSA"
		else:
			playback_status_label.text = "PLAY"

	if btn_play != null:
		btn_play.disabled = simulation_finished or not playback_paused
	if btn_pause != null:
		btn_pause.disabled = simulation_finished or playback_paused
	if btn_time_back != null:
		btn_time_back.disabled = simulation_finished
	if btn_time_forward != null:
		btn_time_forward.disabled = simulation_finished
	if btn_stop_graphs != null:
		btn_stop_graphs.disabled = sim_time_s <= 0.0 or graphs_launched
		btn_stop_graphs.text = "Generacion lanzada" if graphs_launched else "Parar + graficas"


func _format_time_scale_label(time_scale: float) -> String:
	var snapped_scale: float = snappedf(maxf(0.0, time_scale), 0.01)
	if absf(snapped_scale - round(snapped_scale)) < 0.001:
		return "x%d" % int(round(snapped_scale))
	if absf(snapped_scale * 10.0 - round(snapped_scale * 10.0)) < 0.001:
		return "x%.1f" % snapped_scale
	return "x%.2f" % snapped_scale


func _find_selector_item_by_opening_index(opening_index: int) -> int:
	if opening_selector == null:
		return -1

	for item_idx in range(opening_selector.get_item_count()):
		if opening_selector.get_item_id(item_idx) == opening_index:
			return item_idx
	return -1


func _on_opening_selected(item_index: int) -> void:
	if _selector_sync_in_progress or opening_selector == null:
		return

	selected_opening_index = opening_selector.get_item_id(item_index)
	_refresh_opening_status()


func _on_open_button_pressed() -> void:
	if building == null:
		return

	building.open_opening(selected_opening_index)
	_refresh_opening_status()


func _on_close_button_pressed() -> void:
	if building == null:
		return

	building.close_opening(selected_opening_index)
	_refresh_opening_status()


func _on_stop_graphs_pressed() -> void:
	stop_and_generate_requested.emit()


func _on_time_back_pressed() -> void:
	slower_requested.emit()


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_time_forward_pressed() -> void:
	faster_requested.emit()
