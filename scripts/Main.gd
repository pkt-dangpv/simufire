extends Node

# @onready var building = $World/BuildingModel
@onready var hud = $UI/HUD
@onready var status_label = $UI/HUD/StatusPanel/MarginContainer/StatusLabel
@onready var fire_model: FireModel = $FireModel


func _ready() -> void:
	print("Main ready")
	#building.state_changed.connect(_on_building_state)
	fire_model.fire_state.connect(_on_fire_state)


func _process(delta: float) -> void:
	fire_model.step(delta)


func _on_building_state(state: Dictionary) -> void:

	hud.update_state(state)

	var r0: Dictionary = state.get("0", {})
	if r0.is_empty():
		return

	var hrr: float = float(r0.get("hrr_kw", 0.0))
	var temp: float = float(r0.get("temp_upper_c", 0.0))
	var layer: float = float(r0.get("h_layer_m", 0.0))
	var smoke: float = float(r0.get("smoke_mass_kg", 0.0))

	status_label.text = \
		"HRR: %.0f kW\nTemp: %.0f C\nLayer: %.2f m\nSmoke: %.2f kg" \
		% [hrr, temp, layer, smoke]

func _on_fire_state(state: Dictionary) -> void:
	var hrr: float = float(state.get("HRR", 0.0))
	var temp_upper: float = float(state.get("TempUpper", 0.0))
	var temp_lower: float = float(state.get("TempLower", 0.0))
	var layer: float = float(state.get("LayerHeight", 0.0))
	var o2_value: float = float(state.get("O2", 0.0))

	status_label.text = \
		"HRR: %.0f kW\nUpper: %.1f C\nLower: %.1f C\nLayer: %.2f m\nO2: %.3f" \
		% [hrr, temp_upper, temp_lower, layer, o2_value]