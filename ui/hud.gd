extends Control
class_name HUD

@export var show_status_panel: bool = false
@export var status_panel_room_id: int = 0
@export var compact_status_panel: bool = true
@export var show_openings_panel: bool = true

@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel
@onready var time_label: Label = $MarginContainer/TimeLabel
@onready var openings_panel: PanelContainer = $OpeningsPanel
@onready var opening_selector: OptionButton = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningSelector
@onready var opening_status_label: Label = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningStatusLabel
@onready var btn_opening_close: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningClose
@onready var btn_opening_open: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningOpen

var building: BuildingModel = null
var selected_opening_index: int = 0
var _selector_sync_in_progress: bool = false
var _known_opening_count: int = -1


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

	_refresh_opening_controls()


func bind_building(next_building: BuildingModel) -> void:
	building = next_building
	_known_opening_count = -1
	_refresh_opening_controls()


func update_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var total_seconds: int = int(sim_time_s)
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = int(total_seconds % 60)
	time_label.text = "TIME %02d:%02d" % [minutes, seconds]

	_refresh_opening_controls()

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
