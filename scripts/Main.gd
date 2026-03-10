extends Node

@onready var building = $World/BuildingModel
@onready var hud = $UI/HUD
@onready var status_label = $UI/HUD/StatusPanel/MarginContainer/StatusLabel

func _ready() -> void:
	print("Main ready")
	building.state_changed.connect(_on_building_state)

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
