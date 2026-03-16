extends Node

# ============================================================
# MAIN
# ------------------------------------------------------------
# Responsabilidad:
# - arrancar la simulación
# - crear el SimulationEngine
# - avanzar el engine en cada frame físico
# - recoger el estado resultante
# - actualizar HUD
#
# Main NO debe hacer física del incendio.
# Main NO debe recalcular humo, O2 o temperatura.
# Todo eso debe vivir en SimulationEngine y los modelos.
# ============================================================


# ============================================================
# REFERENCIAS A NODOS DE ESCENA
# ============================================================

@onready var building: BuildingModel = $World/BuildingModel
@onready var hud: HUD = $UI/HUD
@onready var status_label: Label = $UI/HUD/StatusPanel/MarginContainer/StatusLabel

# Si tienes también un TimeLabel separado en HUD, descomenta esto
# y úsalo en _apply_state_to_ui().
# @onready var time_label: Label = $UI/HUD/TimeLabel


# ============================================================
# MOTOR DE SIMULACIÓN
# ============================================================

var engine: SimulationEngine = null


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	print("Main ready")

	# Validación básica de escena
	if building == null:
		push_error("BuildingModel no encontrado en Main/World")
		return

	if hud == null:
		push_error("HUD no encontrado en Main/UI")
		return

	if status_label == null:
		push_error("StatusLabel no encontrado en HUD")
		return

	# --------------------------------------------------------
	# Crear el SimulationEngine.
	#
	# IMPORTANTE:
	# Esta línea asume que SimulationEngine.gd tiene:
	#
	# func _init(building_model: BuildingModel, smoke_model: SmokeModel) -> void:
	#     ...
	#
	# Si tu SimulationEngine actual todavía espera otros argumentos,
	# tendrás que alinear su _init con esta nueva arquitectura.
	# --------------------------------------------------------
	engine = SimulationEngine.new(building, building.smoke_model)

	if engine == null:
		push_error("No se pudo crear SimulationEngine")
		return

	# Estado inicial en pantalla
	var initial_state: Dictionary = engine.get_state()
	_apply_state_to_ui(initial_state)


# ============================================================
# LOOP DE SIMULACIÓN
# ============================================================

func _physics_process(delta: float) -> void:
	# Si no hay engine o building, no simulamos
	if engine == null or building == null:
		return

	# El time_scale sigue viniendo de BuildingModel,
	# pero quien avanza la simulación real es el engine.
	var sim_delta: float = delta * building.time_scale

	# Avanzar simulación
	engine.step(sim_delta)

	# Leer snapshot resultante
	var state: Dictionary = engine.get_state()

	# Actualizar interfaz
	_apply_state_to_ui(state)


# ============================================================
# UI / PRESENTACIÓN
# ============================================================

func _apply_state_to_ui(state: Dictionary) -> void:
	# Mantener la actualización general del HUD, si ya la tienes implementada
	hud.update_state(state)

	# Leemos la sala 0 como sala principal de debug
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

	print("HUD room0 HRR=", float(state.get("0", {}).get("hrr_kw", 0.0)))

	# Si quieres controlar aquí el tiempo mostrado y tienes un TimeLabel:
	# var sim_time_s: float = float(state.get("sim_time_s", 0.0))
	# var total_seconds: int = int(sim_time_s)
	# time_label.text = "TIME %02d:%02d" % [total_seconds / 60, total_seconds % 60]