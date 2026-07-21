extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_disabled_has_no_ledger_fields()
	_test_exact_route_ledger_closure()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33C1_ENTHALPY_RESIDENCE_LEDGER_PASS")
		quit(0)


func _test_disabled_has_no_ledger_fields() -> void:
	var building = _make_building()
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.finalize_step(building, 20.0)
	_assert_true(
		not system.get_results()["0"].has(
			"phase3_shadow_enthalpy_room_residual_kj"
		),
		"disabled ledger does not add result fields"
	)
	building.free()


func _test_exact_route_ledger_closure() -> void:
	var building = _make_building()
	var system = Phase3ZoneMassSystemScript.new()
	system.configure_enthalpy_residence_diagnostics(true)
	system.begin_step(building, true)
	_add_route(system, "combustion", "canonical_combustion_convective_heat", -1, 0, "upper", "upper", 10.0)
	_add_route(system, "interzone", "thermal_upper_to_lower", 0, 0, "upper", "lower", 5.0)
	_add_route(system, "interior", "canonical_interior_opening", 0, 1, "upper", "upper", 7.0)
	_add_route(system, "wall", "canonical_upper_to_wall", 0, -1, "upper", "upper", 3.0)
	system.add_request(system.make_request(
		"legacy:room1:lower", "thermal_carry", -1, 1,
		"lower", "lower", 0.0, 2.0
	))
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results()
	_assert_close(float(results["0"]["phase3_shadow_enthalpy_observed_upper_kj"]), 45.0, "room0 upper")
	_assert_close(float(results["0"]["phase3_shadow_enthalpy_observed_lower_kj"]), 5.0, "room0 lower")
	_assert_close(float(results["1"]["phase3_shadow_enthalpy_observed_upper_kj"]), 17.0, "room1 upper")
	_assert_close(float(results["1"]["phase3_shadow_enthalpy_observed_lower_kj"]), 2.0, "room1 lower")
	for room_key in results.keys():
		_assert_close(float(results[room_key]["phase3_shadow_enthalpy_upper_residual_kj"]), 0.0, "upper closure")
		_assert_close(float(results[room_key]["phase3_shadow_enthalpy_lower_residual_kj"]), 0.0, "lower closure")
		_assert_close(float(results[room_key]["phase3_shadow_enthalpy_room_residual_kj"]), 0.0, "room closure")
		_assert_close(float(results[room_key]["phase3_shadow_enthalpy_building_residual_kj"]), 0.0, "building closure")
	_assert_close(float(results["0"]["phase3_shadow_enthalpy_combustion_upper_in_kj_total"]), 10.0, "combustion family")
	_assert_close(float(results["0"]["phase3_shadow_enthalpy_interzone_upper_out_kj_total"]), 5.0, "interzone out")
	_assert_close(float(results["0"]["phase3_shadow_enthalpy_interzone_lower_in_kj_total"]), 5.0, "interzone in")
	_assert_close(float(results["1"]["phase3_shadow_enthalpy_interior_opening_upper_in_kj_total"]), 7.0, "interior family")
	_assert_close(float(results["0"]["phase3_shadow_enthalpy_wall_upper_out_kj_total"]), 3.0, "wall family")
	_assert_close(float(results["1"]["phase3_shadow_enthalpy_legacy_lower_in_kj_total"]), 2.0, "legacy family")
	building.free()


func _add_route(
		system,
		bundle_id: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		energy_kj: float
	) -> void:
	var route: Dictionary = system.make_atomic_route(
		bundle_id + ":route", cause, source_room_id, destination_room_id,
		source_zone, destination_zone, 0.0, energy_kj
	)
	system.add_atomic_bundle(system.make_atomic_bundle(
		bundle_id, cause, [route], {"kind": "fixture"}
	))


func _make_building():
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_room(0, 50.0, 0.0),
		1: _make_room(1, 10.0, 0.0),
	}
	return building


func _make_room(room_id: int, upper_energy_kj: float, lower_energy_kj: float):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.upper_gas_kg = 28.8
	room.lower_gas_kg = 28.8
	room.upper_energy_kj = upper_energy_kj
	room.lower_energy_kj = lower_energy_kj
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	return room


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(actual: float, expected: float, label: String, tolerance: float = 1.0e-9) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %s got %s" % [label, str(expected), str(actual)])
		_failed = true
