extends RefCounted
class_name SimulationEngine

var sim_time: float = 0.0

var building: BuildingModel
var fire: FireModel
var smoke: SmokeModel


func _init(building_model: BuildingModel, fire_model: FireModel, smoke_model: SmokeModel):
	building = building_model
	fire = fire_model
	smoke = smoke_model


func step(delta: float) -> void:
	sim_time += delta
	
	# 1 incendio
	fire.step(delta)
	
	# 2 humo
	_step_smoke(delta)


func _step_smoke(delta: float) -> void:
	var room: RoomModel = building.rooms.get(0)

	if room == null:
		return

	smoke.step_room_smoke(room, fire.hrr_kw, delta)


func get_state() -> Dictionary:
	var room: RoomModel = building.rooms.get(0)

	if room == null:
		return {}

	return {
		"0": room.to_state_dict()
	}