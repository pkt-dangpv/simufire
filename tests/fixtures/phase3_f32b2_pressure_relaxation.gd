extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


var _failed: bool = false


func _init() -> void:
	_test_exact_equilibrium_fraction()
	_test_negative_pressure_reseeds_lower_without_crossing()
	_test_positive_pressure_outflow_stops_at_equilibrium()
	_test_default_off_preserves_explicit_crossing()
	# `quit()` only requests a shutdown, so execution continues. Return
	# explicitly or the PASS marker below would still be printed.
	if _failed:
		quit(1)
		return
	print("PHASE3_F32B2_PRESSURE_RELAXATION_PASS")
	quit(0)


func _test_exact_equilibrium_fraction() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var result: Dictionary = system.compute_exterior_pressure_relaxation(
		-34018.53516835, 34.62478616, 0.0, false, 48.0, 20.0
	)
	_assert_close(float(result["fraction"]), 0.5585144068, "measured fraction", 2.0e-4)
	_assert_close(float(result["predicted_post_pa"]), 0.0, "measured post pressure")
	_assert_close(float(result["crossing_prevented_flag"]), 1.0, "crossing flag")


func _test_negative_pressure_reseeds_lower_without_crossing() -> void:
	var setup: Dictionary = _make_building(32.0, 0.0)
	var result: Dictionary = _run_once(setup, true)
	_assert_true(_value(result, "phase3_shadow_exterior_pressure_pre_pa") < 0.0, "inflow pre pressure")
	_assert_true(_value(result, "phase3_shadow_exterior_raw_requested_gas_kg") > _value(result, "phase3_shadow_exterior_accepted_gas_kg"), "inflow limited")
	_assert_true(_value(result, "phase3_shadow_exterior_pressure_equilibrium_fraction") < 1.0, "inflow fraction")
	_assert_close(_value(result, "phase3_shadow_exterior_pressure_predicted_post_pa"), 0.0, "inflow predicted post")
	_assert_close(_value(result, "phase3_shadow_thermo_pressure_gauge_pa"), 0.0, "inflow actual post", 1.0e-5)
	_assert_close(_value(result, "phase3_shadow_exterior_degenerate_lower_reseed_flag"), 1.0, "lower reseed flag")
	_assert_true(_value(result, "phase3_shadow_lower_gas_kg") > 0.0, "lower zone recreated")
	_assert_close(_value(result, "phase3_shadow_upper_gas_kg"), 32.0, "upper inventory preserved")
	_assert_close(
		_value(result, "phase3_shadow_exterior_degenerate_lower_reseed_mass_kg"),
		_value(result, "phase3_shadow_lower_gas_kg"),
		"reseed mass telemetry"
	)
	_assert_close(_value(result, "phase3_shadow_exterior_lower_reseed_count_total"), 1.0, "reseed count")
	_assert_close(
		_value(result, "phase3_shadow_exterior_lower_reseed_mass_kg_total"),
		_value(result, "phase3_shadow_lower_gas_kg"),
		"reseed cumulative mass"
	)
	_assert_close(_value(result, "phase3_shadow_exterior_lower_reseed_first_step_index"), 1.0, "reseed first step")
	_assert_boundary_residuals(result, "inflow")
	_free_setup(setup)


func _test_positive_pressure_outflow_stops_at_equilibrium() -> void:
	var setup: Dictionary = _make_building(64.0, 0.0)
	var result: Dictionary = _run_once(setup, true)
	_assert_true(_value(result, "phase3_shadow_exterior_pressure_pre_pa") > 0.0, "outflow pre pressure")
	_assert_close(_value(result, "phase3_shadow_exterior_direction"), 1.0, "outflow direction")
	_assert_true(_value(result, "phase3_shadow_exterior_pressure_equilibrium_fraction") < 1.0, "outflow fraction")
	_assert_close(_value(result, "phase3_shadow_thermo_pressure_gauge_pa"), 0.0, "outflow actual post", 1.0e-5)
	_assert_close(_value(result, "phase3_shadow_lower_gas_kg"), 0.0, "outflow stays one-zone")
	_assert_boundary_residuals(result, "outflow")
	_free_setup(setup)


func _test_default_off_preserves_explicit_crossing() -> void:
	var setup: Dictionary = _make_building(32.0, 0.0)
	var result: Dictionary = _run_once(setup, false)
	_assert_close(_value(result, "phase3_shadow_exterior_relaxation_enabled_flag"), 0.0, "default off")
	_assert_close(_value(result, "phase3_shadow_exterior_pressure_equilibrium_fraction"), 1.0, "default fraction")
	_assert_true(_value(result, "phase3_shadow_thermo_pressure_gauge_pa") > 0.0, "legacy explicit crossing retained")
	_assert_close(_value(result, "phase3_shadow_lower_gas_kg"), 0.0, "default does not reseed lower")
	_free_setup(setup)


func _make_building(total_mass_kg: float, upper_energy_kj: float) -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = total_mass_kg
	room.lower_gas_kg = 0.0
	room.upper_energy_kj = upper_energy_kj
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.15
	room.o2_lower = 0.209
	building.rooms = {0: room}
	var opening = OpeningModelScript.new(
		0,
		BuildingModelScript.OUTSIDE_ID,
		OpeningModelScript.Type.WINDOW,
		2.0,
		2.0,
		1.0,
		0.0
	)
	opening.open_fraction_smooth = 1.0
	building.openings = [opening]
	return {"building": building, "room": room}


func _run_once(setup: Dictionary, relaxation_enabled: bool) -> Dictionary:
	var building = setup["building"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_exterior_boundary_requests(
		building, 0.1, 20.0, 0.209, 0.0, 0.0, 0.61, relaxation_enabled
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
		push_error(label)
		_failed = true


func _assert_close(
		actual: float,
		expected: float,
		label: String,
		tolerance: float = 1.0e-8
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %.12g got %.12g" % [label, expected, actual])
		_failed = true
