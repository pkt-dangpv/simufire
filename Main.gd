extends Node

# ============================================================
# MAIN
# ------------------------------------------------------------
# Responsabilidad:
# - arrancar la simulacion
# - localizar referencias de escena
# - avanzar el SimulationEngine
# - leer el estado agregado del engine
# - actualizar HUD y Visualizer
#
# Main NO debe:
# - hacer fisica del incendio
# - recalcular HRR, humo, O2 o temperatura
# - contener logica del modelo
# ============================================================

@onready var building: BuildingModel = $World/BuildingModel
@onready var engine: SimulationEngine = $World/SimulationEngine
@onready var hud: HUD = $UI/HUD
@onready var visualizer: Visualizer = $World/Visualizer


func _ready() -> void:
	if building == null:
		push_error("Main: BuildingModel no encontrado en $World/BuildingModel")
		return
	if engine == null:
		push_error("Main: SimulationEngine no encontrado en $World/SimulationEngine")
		return
	if hud == null:
		push_error("Main: HUD no encontrado en $UI/HUD")
		return

	_apply_state_to_ui(engine.get_state())


func _physics_process(delta: float) -> void:
	if engine == null:
		return

	engine.step(delta)
	_apply_state_to_ui(engine.get_state())


func _apply_state_to_ui(state: Dictionary) -> void:
	if hud != null:
		hud.update_state(state)
	if visualizer != null:
		visualizer.set_state(state)
