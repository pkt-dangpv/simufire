extends Node

@onready var building: BuildingModel = $World/BuildingModel
@onready var hud: HUD = $UI/HUD
@onready var status_label: Label = $UI/HUD/StatusPanel/MarginContainer/StatusLabel


func _ready() -> void:
	print("Main ready")

	if building == null:
		push_error("BuildingModel no encontrado en Main/World")
		return

	building.state_changed.connect(_on_building_state)
	building.emit_state()


func _physics_process(delta: float) -> void:
	if building == null:
		return

	var sim_delta: float = delta * building.time_scale
	building.sim_time_s += sim_delta
	building.step(sim_delta)
	building.emit_state()


func _on_building_state(state: Dictionary) -> void:
	hud.update_state(state)

	var r0: Dictionary = state.get("0", {})
	if r0.is_empty():
		status_label.text = "Sin datos de la sala 0"
		return

	var hrr: float = float(r0.get("hrr_kw", 0.0))
	var temp_upper: float = float(r0.get("temp_upper_c", 0.0))
	var temp_lower: float = float(r0.get("temp_lower_c", 0.0))
	var layer: float = float(r0.get("h_layer_m", 0.0))
	var o2_value: float = float(r0.get("o2", 0.0))
	var smoke: float = float(r0.get("smoke_mass_kg", 0.0))

	status_label.text = \
		"HRR: %.0f kW\nUpper: %.1f C\nLower: %.1f C\nLayer: %.2f m\nO2: %.3f\nSmoke: %.2f kg" \
		% [hrr, temp_upper, temp_lower, layer, o2_value, smoke]