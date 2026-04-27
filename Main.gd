extends Node

@onready var building: BuildingModel = $World/BuildingModel
@onready var engine: SimulationEngine = $World/SimulationEngine
@onready var visualizer: Visualizer = $World/Visualizer
@onready var hud: HUD = $UI/HUD

var playback_paused: bool = false


func _ready() -> void:
	if hud != null:
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
	_update_views()


func _physics_process(delta: float) -> void:
	if playback_paused or engine == null:
		return
	engine.step(delta)
	_update_views()


func _update_views() -> void:
	if engine == null:
		return
	var state := engine.get_state()
	state["playback_paused"] = playback_paused
	if visualizer != null:
		visualizer.set_state(state)
	if hud != null:
		hud.update_state(state)


func _on_play_requested() -> void:
	playback_paused = false
	_update_views()


func _on_pause_requested() -> void:
	playback_paused = true
	_update_views()


func _on_slower_requested() -> void:
	if engine != null:
		engine.time_scale = maxf(0.25, engine.time_scale / 2.0)
	_update_views()


func _on_faster_requested() -> void:
	if engine != null:
		engine.time_scale = minf(64.0, engine.time_scale * 2.0)
	_update_views()


func _on_stop_and_generate_requested() -> void:
	playback_paused = true
	_update_views()
