extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_disabled_has_no_ledger_fields()
	_test_exact_mass_route_ledger_closure()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33D1_MASS_RESIDENCE_LEDGER_PASS")
		quit(0)


func _test_disabled_has_no_ledger_fields() -> void:
	var building = _make_building()
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.finalize_step(building, 20.0)
	_assert_true(
		not system.get_results()["0"].has(
			"phase3_shadow_mass_residence_room_residual_kg"
		),
		"disabled ledger does not add result fields"
	)
	building.free()


func _test_exact_mass_route_ledger_closure() -> void:
	var building = _make_building()
	var system = Phase3ZoneMassSystemScript.new()
	system.configure_mass_residence_diagnostics(true)
	system.begin_step(building, true)
	_add_route(system, "plume", "canonical_combustion_plume", 0, 0, "lower", "upper", 4.0)
	_add_route(system, "interior", "canonical_interior_opening", 0, 1, "upper", "upper", 3.0)
	_add_route(system, "exterior_in", "canonical_exterior_pressure", -1, 1, "lower", "lower", 2.0)
	_add_route(system, "exterior_out", "canonical_exterior_pressure", 0, -1, "upper", "upper", 1.0)
	_add_route(system, "parcel", "delayed_parcel_delivery", 1, 0, "upper", "upper", 0.5)
	# Only the 24.8 kg remaining in room 0 lower may be accepted.
	_add_route(system, "limited", "canonical_interior_pressure", 0, 1, "lower", "lower", 100.0)
	_add_route(system, "collapse", "zone_collapse", 1, 1, "upper", "lower", 0.25)
	system.add_request(system.make_request(
		"legacy:room1:lower", "thermal_carry", -1, 1,
		"lower", "lower", 1.0, 0.0
	))
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results()
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_observed_upper_kg"]), 29.3, "room0 upper")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_observed_lower_kg"]), 0.0, "room0 lower")
	_assert_close(float(results["1"]["phase3_shadow_mass_residence_observed_upper_kg"]), 31.05, "room1 upper")
	_assert_close(float(results["1"]["phase3_shadow_mass_residence_observed_lower_kg"]), 56.85, "room1 lower")
	for room_key in results.keys():
		_assert_close(float(results[room_key]["phase3_shadow_mass_residence_upper_residual_kg"]), 0.0, "upper closure")
		_assert_close(float(results[room_key]["phase3_shadow_mass_residence_lower_residual_kg"]), 0.0, "lower closure")
		_assert_close(float(results[room_key]["phase3_shadow_mass_residence_room_residual_kg"]), 0.0, "room closure")
		_assert_close(float(results[room_key]["phase3_shadow_mass_residence_building_residual_kg"]), 0.0, "building closure")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_plume_lower_out_kg_total"]), 4.0, "plume lower out")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_plume_upper_in_kg_total"]), 4.0, "plume upper in")
	_assert_close(float(results["1"]["phase3_shadow_mass_residence_interior_opening_upper_in_kg_total"]), 3.0, "opening family")
	_assert_close(float(results["1"]["phase3_shadow_mass_residence_exterior_lower_in_kg_total"]), 2.0, "exterior family")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_parcel_upper_in_kg_total"]), 0.5, "parcel family")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_interior_pressure_lower_out_kg_total"]), 24.8, "accepted mass only")
	_assert_close(float(results["1"]["phase3_shadow_mass_residence_zone_collapse_upper_out_kg_total"]), 0.25, "collapse family")
	_assert_close(float(results["1"]["phase3_shadow_mass_residence_legacy_lower_in_kg_total"]), 1.0, "legacy family")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_wall_upper_out_kg_total"]), 0.0, "wall moves no mass")
	_assert_close(float(results["0"]["phase3_shadow_mass_residence_reconcile_upper_out_kg_total"]), 0.0, "reconcile moves no mass")
	building.free()


func _add_route(
		system,
		bundle_id: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		mass_kg: float
	) -> void:
	var route: Dictionary = system.make_atomic_route(
		bundle_id + ":route", cause, source_room_id, destination_room_id,
		source_zone, destination_zone, mass_kg, 0.0
	)
	system.add_atomic_bundle(system.make_atomic_bundle(
		bundle_id, cause, [route], {"kind": "fixture"}
	))


func _make_building():
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_room(0),
		1: _make_room(1),
	}
	return building


func _make_room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.upper_gas_kg = 28.8
	room.lower_gas_kg = 28.8
	room.upper_energy_kj = 0.0
	room.lower_energy_kj = 0.0
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
