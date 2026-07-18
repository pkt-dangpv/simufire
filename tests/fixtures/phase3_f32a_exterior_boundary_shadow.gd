extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


func _init() -> void:
	_test_no_area_has_no_event()
	_test_positive_pressure_outflow()
	_test_negative_pressure_inflow()
	_test_inventory_cap_and_atomic_residuals()
	_test_deterministic_result()
	print("PHASE3_F32A_EXTERIOR_BOUNDARY_SHADOW_PASS")
	quit(0)


func _test_no_area_has_no_event() -> void:
	var setup: Dictionary = _make_building(48.0, 800.0, 0.0, 0.0)
	var result: Dictionary = _run_once(setup, 0.1, 0.0)
	_assert_close(_value(result, "phase3_shadow_exterior_event_count"), 0.0, "no area event")
	_assert_close(_value(result, "phase3_shadow_exterior_requested_gas_kg"), 0.0, "no area mass")
	_free_setup(setup)


func _test_positive_pressure_outflow() -> void:
	var setup: Dictionary = _make_building(48.0, 800.0, 0.001, 1.0)
	var result: Dictionary = _run_once(setup, 0.1, 0.0)
	_assert_true(_value(result, "phase3_shadow_exterior_pressure_pre_pa") > 0.0, "positive pressure")
	_assert_close(_value(result, "phase3_shadow_exterior_direction"), 1.0, "outflow direction")
	_assert_true(_value(result, "phase3_shadow_exterior_accepted_gas_kg") > 0.0, "outflow accepted")
	_assert_close(
		_value(result, "phase3_shadow_mass_residual_kg"),
		-_value(result, "phase3_shadow_exterior_accepted_gas_kg"),
		"outflow mass delta"
	)
	_assert_boundary_residuals(result, "outflow")
	_free_setup(setup)


func _test_negative_pressure_inflow() -> void:
	var setup: Dictionary = _make_building(40.0, 0.0, 0.001, 1.0)
	var result: Dictionary = _run_once(setup, 0.1, 0.0)
	_assert_true(_value(result, "phase3_shadow_exterior_pressure_pre_pa") < 0.0, "negative pressure")
	_assert_close(_value(result, "phase3_shadow_exterior_direction"), -1.0, "inflow direction")
	_assert_true(_value(result, "phase3_shadow_exterior_accepted_gas_kg") > 0.0, "inflow accepted")
	_assert_close(
		_value(result, "phase3_shadow_mass_residual_kg"),
		_value(result, "phase3_shadow_exterior_accepted_gas_kg"),
		"inflow mass delta"
	)
	_assert_close(
		_value(result, "phase3_shadow_exterior_accepted_energy_kj"),
		0.0,
		"ambient sensible energy"
	)
	_assert_boundary_residuals(result, "inflow")
	_free_setup(setup)


func _test_inventory_cap_and_atomic_residuals() -> void:
	var setup: Dictionary = _make_building(48.0, 4000.0, 20.0, 1.0)
	var result: Dictionary = _run_once(setup, 5.0, 0.0)
	var fraction: float = _value(result, "phase3_shadow_exterior_accepted_fraction")
	_assert_true(fraction >= 0.0 and fraction < 1.0, "inventory fraction capped")
	_assert_true(_value(result, "phase3_shadow_upper_gas_kg") >= 0.0, "upper mass nonnegative")
	_assert_true(_value(result, "phase3_shadow_lower_gas_kg") >= 0.0, "lower mass nonnegative")
	_assert_close(
		_value(result, "phase3_shadow_exterior_requested_gas_kg"),
		_value(result, "phase3_shadow_exterior_accepted_gas_kg")
				+ _value(result, "phase3_shadow_exterior_rejected_gas_kg"),
		"requested split"
	)
	_assert_boundary_residuals(result, "capped")
	_free_setup(setup)


func _test_deterministic_result() -> void:
	var first_setup: Dictionary = _make_building(48.0, 800.0, 0.002, 1.0)
	var second_setup: Dictionary = _make_building(48.0, 800.0, 0.002, 1.0)
	var first: Dictionary = _run_once(first_setup, 0.1, 0.0)
	var second: Dictionary = _run_once(second_setup, 0.1, 0.0)
	for field_name in [
		"phase3_shadow_exterior_pressure_pre_pa",
		"phase3_shadow_exterior_requested_gas_kg",
		"phase3_shadow_exterior_accepted_gas_kg",
		"phase3_shadow_exterior_accepted_fraction",
		"phase3_shadow_upper_gas_kg",
		"phase3_shadow_lower_gas_kg"
	]:
		_assert_close(_value(first, field_name), _value(second, field_name), "deterministic " + field_name)
	_free_setup(first_setup)
	_free_setup(second_setup)


func _make_building(
		total_mass_kg: float,
		upper_energy_kj: float,
		opening_area_m2: float,
		open_fraction: float
	) -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = minf(8.0, total_mass_kg)
	room.lower_gas_kg = maxf(0.0, total_mass_kg - room.upper_gas_kg)
	room.upper_energy_kj = upper_energy_kj
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.18
	room.o2_lower = 0.209
	room.smoke_kg = 0.4
	room.co_kg = 0.08
	room.co_upper_kg = 0.06
	room.co2_kg = 0.16
	room.co2_upper_kg = 0.12
	room.hcn_kg = 0.02
	room.hcn_upper_kg = 0.015
	building.rooms = {0: room}
	var opening_width_m: float = sqrt(maxf(0.0, opening_area_m2))
	var opening_height_m: float = opening_width_m
	if opening_area_m2 <= 0.0:
		opening_width_m = 1.0
		opening_height_m = 1.0
	var opening = OpeningModelScript.new(
		0,
		BuildingModelScript.OUTSIDE_ID,
		OpeningModelScript.Type.WINDOW,
		opening_width_m,
		opening_height_m,
		open_fraction,
		0.0
	)
	opening.open_fraction_smooth = open_fraction
	building.openings = [opening]
	return {"building": building, "room": room}


func _run_once(setup: Dictionary, dt: float, leakage_area_m2: float) -> Dictionary:
	var building = setup["building"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building)
	system.queue_canonical_exterior_boundary_requests(
		building, dt, 20.0, 0.209, leakage_area_m2, 0.0
	)
	_assert_true(
		system.suppress_legacy_pressure_purge_event({
			"mechanism": "pressure_venting", "source_room_id": 0
		}),
		"pressure owner suppressed"
	)
	_assert_true(
		not system.suppress_legacy_pressure_purge_event({
			"mechanism": "ach_infiltration", "source_room_id": 0
		}),
		"other exterior owner remains"
	)
	system.finalize_step(building, 20.0)
	return system.get_results().get("0", {})


func _assert_boundary_residuals(result: Dictionary, label: String) -> void:
	for field_name in [
		"phase3_shadow_exterior_mass_residual_kg",
		"phase3_shadow_exterior_energy_residual_kj",
		"phase3_shadow_exterior_o2_residual_kg",
		"phase3_shadow_exterior_species_residual_kg"
	]:
		_assert_close(_value(result, field_name), 0.0, label + " " + field_name)


func _value(result: Dictionary, field_name: String) -> float:
	return float(result.get(field_name, 0.0))


func _free_setup(setup: Dictionary) -> void:
	var building = setup.get("building")
	if building != null:
		building.free()


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label)


func _assert_close(actual: float, expected: float, label: String) -> void:
	var tolerance: float = 1.0e-8 * maxf(1.0, absf(expected))
	if absf(actual - expected) > tolerance:
		_fail("%s expected %.12g got %.12g" % [label, expected, actual])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
