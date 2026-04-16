extends Control
class_name HUD

@onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel
@onready var time_label: Label = $MarginContainer/TimeLabel


func update_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var total_seconds: int = int(sim_time_s)
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = int(total_seconds % 60)
	time_label.text = "TIME %02d:%02d" % [minutes, seconds]

	var room_state: Dictionary = state.get("0", {})
	status_label.text = build_room_status_text(room_state)


func build_room_status_text(room_state: Dictionary) -> String:
	if room_state.is_empty():
		return "Sin datos de room 0"

	var lines: Array[String] = [
		"HRR: %.0f kW" % float(room_state.get("hrr_kw", 0.0)),
		"Upper: %.1f C" % float(room_state.get("temp_upper_c", 0.0)),
		"Lower: %.1f C" % float(room_state.get("temp_lower_c", 0.0)),
		"SmokeLayer: %.2f m" % float(room_state.get("smoke_layer_m", room_state.get("h_layer_m", 0.0))),
		"HotLayer: %.2f m" % float(room_state.get("hot_layer_m", room_state.get("thermal_layer_m", 0.0))),
		"Layer150C: %.2f m" % float(room_state.get("layer_150c_m", 0.0)),
		"T@1.8m: %.1f C" % float(room_state.get("temp_at_1_8m_c", 0.0)),
		"O2: %.3f" % float(room_state.get("o2", 0.0)),
		"Smoke: %.4f kg" % float(room_state.get("smoke_kg", 0.0)),
		"CO: %.0f ppm" % float(room_state.get("co_ppm", 0.0)),
		"P: %.2f Pa" % float(room_state.get("overpressure_pa", 0.0))
	]

	if bool(room_state.get("flashover_triggered", false)):
		lines.append("Flashover: true")

	return "\n".join(PackedStringArray(lines))
