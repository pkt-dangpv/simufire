extends Control
class_name HUD

@onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel
@onready var time_label: Label = $MarginContainer/TimeLabel

func update_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	var total_seconds: int = int(sim_time_s)
	time_label.text = "TIME %02d:%02d" % [total_seconds / 60, total_seconds % 60]

	var rs: Dictionary = state.get("0", {})
	if rs.is_empty():
		status_label.text = "Sin datos de room 0"
		return

	status_label.text = \
		"HRR: %.0f kW\nUpper: %.1f C\nLower: %.1f C\nLayer: %.2f m\nO2: %.3f\nSmoke: %.4f kg" % [
			float(rs.get("hrr_kw", 0.0)),
			float(rs.get("temp_upper_c", 0.0)),
			float(rs.get("temp_lower_c", 0.0)),
			float(rs.get("h_layer_m", 0.0)),
			float(rs.get("o2", 0.0)),
			float(rs.get("smoke_kg", 0.0))
		]