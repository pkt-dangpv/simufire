extends Node

# ============================================================
# MAIN
# ------------------------------------------------------------
# Responsabilidad:
# - arrancar la simulación
# - localizar referencias de escena
# - avanzar el SimulationEngine
# - leer el estado agregado del engine
# - actualizar HUD y Visualizer
#
# Main NO debe:
# - hacer física del incendio
# - recalcular HRR, humo, O2 o temperatura
# - contener lógica del modelo
# ============================================================


# ============================================================
# REFERENCIAS A NODOS DE ESCENA
# ------------------------------------------------------------
# Ajusta estas rutas si tu árbol real cambia.
# ============================================================

@onready var building: BuildingModel = $World/BuildingModel
@onready var engine: SimulationEngine = $World/SimulationEngine
@onready var hud: HUD = $UI/HUD
@onready var visualizer: Visualizer = $World/Visualizer
@onready var status_label: Label = $UI/HUD/StatusPanel/MarginContainer/StatusLabel

# Si tienes TimeLabel dentro de HUD y quieres usarlo aquí:
# @onready var time_label: Label = $UI/HUD/TimeLabel


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	print("Main ready")

	# --------------------------------------------------------
	# Validación básica de escena
	# --------------------------------------------------------
	if building == null:
		push_error("Main: BuildingModel no encontrado en $World/BuildingModel")
		return

	if engine == null:
		push_error("Main: SimulationEngine no encontrado en $World/SimulationEngine")
		return

	if hud == null:
		push_error("Main: HUD no encontrado en $UI/HUD")
		return

	if status_label == null:
		push_error("Main: StatusLabel no encontrado en HUD")
		return

	# --------------------------------------------------------
	# Estado inicial en pantalla
	# --------------------------------------------------------
	var initial_state: Dictionary = engine.get_state()
	_apply_state_to_ui(initial_state)


# ============================================================
# LOOP DE SIMULACIÓN
# ------------------------------------------------------------
# El tiempo y el escalado viven en SimulationEngine.
# Main solo llama step(delta).
# ============================================================

func _physics_process(delta: float) -> void:
	if engine == null:
		return

	engine.step(delta)

	var state: Dictionary = engine.get_state()
	_apply_state_to_ui(state)


# ============================================================
# UI / PRESENTACIÓN
# ------------------------------------------------------------
# Main solo pinta datos ya calculados por el engine.
# ============================================================

func _apply_state_to_ui(state: Dictionary) -> void:
	if hud != null:
		hud.update_state(state)

	if visualizer != null:
		visualizer.set_state(state)

	var r0: Dictionary = state.get("0", {})
	if r0.is_empty():
		status_label.text = "Sin datos de la sala 0"
		return

	var hrr: float = float(r0.get("hrr_kw", 0.0))
	var temp_upper: float = float(r0.get("temp_upper_c", 0.0))
	var temp_lower: float = float(r0.get("temp_lower_c", 0.0))
	var layer: float = float(r0.get("h_layer_m", 0.0))
	var o2_value: float = float(r0.get("o2", 0.0))
	var smoke: float = float(r0.get("smoke_kg", 0.0))
	var flashover: bool = bool(r0.get("flashover_triggered", false))

	status_label.text = \
		"HRR: %.0f kW\nUpper: %.1f C\nLower: %.1f C\nLayer: %.2f m\nO2: %.3f\nSmoke: %.2f kg\nFlashover: %s" \
		% [hrr, temp_upper, temp_lower, layer, o2_value, smoke, str(flashover)]

	# Si quieres mostrar tiempo aquí en vez de dentro del HUD:
	# var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	# var total_seconds: int = int(sim_time_s)
	# time_label.text = "TIME %02d:%02d" % [total_seconds / 60, total_seconds % 60]
