extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

var _failed: bool = false


func _init() -> void:
	var thermal = ThermalSystemScript.new()
	if not thermal.has_method("_is_building_post_extinction"):
		_assert(false, "global extinction predicate is missing")
		quit(1)
		return
	_assert(
		not bool(thermal.call("_is_building_post_extinction")),
		"missing building reference is not post-extinction"
	)

	var building = BuildingModelScript.new()
	var burning_room = RoomModelScript.new()
	burning_room.id = 0
	burning_room.hrr_kw = 50.0
	var receiving_room = RoomModelScript.new()
	receiving_room.id = 1
	receiving_room.hrr_kw = 0.0
	building.rooms = {0: burning_room, 1: receiving_room}
	thermal.set_references(building, SmokeModelScript.new())

	_assert(
		not bool(thermal.call("_is_building_post_extinction")),
		"a quiescent receiving room cannot end the building fire"
	)
	burning_room.hrr_kw = 0.0
	_assert(
		bool(thermal.call("_is_building_post_extinction")),
		"all rooms quiescent means global post-extinction"
	)

	if _failed:
		quit(1)
		return
	print("P1R_V3_GLOBAL_EXTINCTION_GATE_PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("P1R V3 global extinction gate: " + message)
