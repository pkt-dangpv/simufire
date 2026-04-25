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

const TIME_SCALE_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0]

var _simulation_paused: bool = false
var _validation_mode: bool = false


func _ready() -> void:
	_validation_mode = _is_validation_mode()

	if building == null:
		push_error("Main: BuildingModel no encontrado en $World/BuildingModel")
		return
	if engine == null:
		push_error("Main: SimulationEngine no encontrado en $World/SimulationEngine")
		return
	if hud == null:
		push_error("Main: HUD no encontrado en $UI/HUD")
		return

	hud.bind_building(building)
	if not hud.play_requested.is_connected(_on_play_requested):
		hud.play_requested.connect(_on_play_requested)
	if not hud.pause_requested.is_connected(_on_pause_requested):
		hud.pause_requested.connect(_on_pause_requested)
	if not hud.slower_requested.is_connected(_on_slower_requested):
		hud.slower_requested.connect(_on_slower_requested)
	if not hud.faster_requested.is_connected(_on_faster_requested):
		hud.faster_requested.connect(_on_faster_requested)
	if not hud.stop_and_generate_requested.is_connected(_on_stop_and_generate_requested):
		hud.stop_and_generate_requested.connect(_on_stop_and_generate_requested)

	if not _validation_mode:
		_apply_state_to_ui(_build_ui_state())


func _physics_process(delta: float) -> void:
	if _validation_mode:
		return
	if engine == null:
		return

	if not _simulation_paused and not engine.is_finished:
		engine.step(delta)
	_apply_state_to_ui(_build_ui_state())


func _apply_state_to_ui(state: Dictionary) -> void:
	if hud != null:
		hud.update_state(state)
	if visualizer != null:
		visualizer.set_state(state)


func _build_ui_state() -> Dictionary:
	if engine == null:
		return {}

	var state: Dictionary = engine.get_state()
	state["playback_paused"] = _simulation_paused or engine.is_finished
	state["time_scale"] = engine.time_scale
	state["simulation_finished"] = engine.is_finished
	state["graphs_launched"] = engine.are_graphs_launched()
	return state


func _on_play_requested() -> void:
	if engine == null or engine.is_finished:
		return

	_simulation_paused = false


func _on_pause_requested() -> void:
	if engine == null or engine.is_finished:
		return

	_simulation_paused = true


func _on_slower_requested() -> void:
	if engine == null or engine.is_finished:
		return

	_set_time_scale_by_step(_find_time_scale_step_index(engine.time_scale) - 1)


func _on_faster_requested() -> void:
	if engine == null or engine.is_finished:
		return

	_set_time_scale_by_step(_find_time_scale_step_index(engine.time_scale) + 1)


func _on_stop_and_generate_requested() -> void:
	if engine == null:
		return

	if engine.stop_and_generate_graphs():
		_simulation_paused = true


func _find_time_scale_step_index(current_scale: float) -> int:
	var best_index: int = 0
	var best_diff: float = INF

	for idx in range(TIME_SCALE_STEPS.size()):
		var diff: float = absf(TIME_SCALE_STEPS[idx] - current_scale)
		if diff < best_diff:
			best_diff = diff
			best_index = idx

	return best_index


func _set_time_scale_by_step(step_index: int) -> void:
	if engine == null:
		return

	var clamped_index: int = clampi(step_index, 0, TIME_SCALE_STEPS.size() - 1)
	engine.time_scale = TIME_SCALE_STEPS[clamped_index]


func _is_validation_mode() -> bool:
	for arg in OS.get_cmdline_user_args():
		var arg_text: String = String(arg)
		if arg_text == "--validation-case" or arg_text.begins_with("--validation-case="):
			return true
	return false
