extends SceneTree

const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_default_off()
	_test_real_vertical_mix_event()
	_test_real_minimal_layer_event()
	_test_deterministic_ids_and_pure_export()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0B_THERMAL_PHYSICAL_OWNERS_PASS")
	quit(0)


func _test_default_off() -> void:
	var thermal = _thermal(false)
	var room = _room()
	thermal._record_phase3_physical_owner_event(
		"off", "local_source", room, 0.0, 0.0, 1.0, 0.0
	)
	_expect(thermal.get_phase3_physical_owner_events().is_empty(), "default OFF")


func _test_real_vertical_mix_event() -> void:
	var thermal = _thermal(true)
	var room = _room()
	room.upper_gas_kg = 4.0
	room.lower_gas_kg = 30.0
	room.upper_energy_kj = 400.0
	room.lower_energy_kj = 0.0
	room.temp_upper_c = 120.0
	room.temp_lower_c = 20.0
	room.width_m = 10.0
	room.length_m = 2.0
	room.thermal_layer_m = 1.0
	thermal._apply_post_transfer_vertical_mix(room, 0.1)
	var events: Array = thermal.get_phase3_physical_owner_events()
	_expect(events.size() == 1, "vertical mix emits once")
	if events.size() == 1:
		var event: Dictionary = events[0]
		_expect(String(event["classification"]) == "interzone_redistribution", "mix class")
		_expect(float(event["upper_energy_delta_kj"]) < 0.0, "mix upper debit")
		_expect(float(event["lower_energy_delta_kj"]) > 0.0, "mix lower credit")
		_expect(
			absf(float(event["upper_energy_delta_kj"]) + float(event["lower_energy_delta_kj"])) <= 1.0e-12,
			"mix energy conserved"
		)
	_expect(bool(thermal.get_phase3_physical_owner_summary()["valid"]), "mix aggregate valid")


func _test_real_minimal_layer_event() -> void:
	var thermal = _thermal(true)
	var room = _room()
	room.upper_gas_kg = 0.0
	room.lower_gas_kg = 30.0
	room.upper_energy_kj = 0.0
	room.lower_energy_kj = 60.0
	thermal._ensure_minimal_upper_gas(room, 20.0)
	var events: Array = thermal.get_phase3_physical_owner_events()
	_expect(events.size() == 1, "minimal layer emits once")
	if events.size() == 1:
		var event: Dictionary = events[0]
		_expect(float(event["upper_mass_delta_kg"]) > 0.0, "layer upper credit")
		_expect(float(event["lower_mass_delta_kg"]) < 0.0, "layer lower debit")
		_expect(bool(thermal.get_phase3_physical_owner_summary()["valid"]), "layer valid")


func _test_deterministic_ids_and_pure_export() -> void:
	var thermal = _thermal(true)
	var room = _room()
	thermal._record_phase3_physical_owner_event(
		"source", "local_source", room, 0.0, 0.0, 1.0, 0.0
	)
	thermal._record_phase3_physical_owner_event(
		"sink", "local_source", room, 0.0, 0.0, -0.5, 0.0
	)
	var before: String = JSON.stringify(thermal.get_phase3_physical_owner_events())
	var first: Dictionary = thermal.get_phase3_physical_owner_summary()
	var second: Dictionary = thermal.get_phase3_physical_owner_summary()
	_expect(JSON.stringify(first) == JSON.stringify(second), "summary idempotent")
	_expect(JSON.stringify(thermal.get_phase3_physical_owner_events()) == before, "export pure")
	var events: Array = thermal.get_phase3_physical_owner_events()
	_expect(String(events[0]["event_id"]).begins_with("thermal:000000:"), "first stable id")
	_expect(String(events[1]["event_id"]).begins_with("thermal:000001:"), "second stable id")


func _thermal(enabled: bool):
	var thermal = ThermalSystemScript.new()
	var solver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	thermal.set_zone_fire_solver(solver)
	thermal._smoke_model = SmokeModelScript.new()
	thermal.two_zone_solver_enabled = true
	thermal.phase3_physical_owner_ledger_enabled = enabled
	return thermal


func _room():
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.4
	room.thermal_layer_m = 1.2
	room.temp_upper_c = 80.0
	room.temp_lower_c = 20.0
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0b ASSERTION FAILED: %s" % label)
