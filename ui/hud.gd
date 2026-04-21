extends Control
class_name HUD

@export var show_status_panel: bool = false
@export var status_panel_room_id: int = 0
@export var compact_status_panel: bool = true

@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel
@onready var time_label: Label = $MarginContainer/TimeLabel


func _ready() -> void:
	if status_panel != null:
		status_panel.visible = show_status_panel


func update_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var total_seconds: int = int(sim_time_s)
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = int(total_seconds % 60)
	time_label.text = "TIME %02d:%02d" % [minutes, seconds]

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
