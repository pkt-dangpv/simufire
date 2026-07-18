extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

var _failed: bool = false


func _init() -> void:
	_test_closed_transaction_scales_every_quantity()
	_test_empty_upper_zone_bootstraps_from_lower()
	_test_extinction_rejects_the_whole_transaction()
	_test_no_fire_is_an_inert_transaction()
	if _failed:
		quit(1)
		return
	print("PHASE3_F32B1_COMBUSTION_TRANSACTION_PASS")
	quit(0)


func _test_closed_transaction_scales_every_quantity() -> void:
	var setup: Dictionary = _make_setup(0.13, true)
	var building = setup["building"]
	var room = setup["room"]
	var combustion = CombustionSystemScript.new()
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	combustion.begin_phase3_shadow_step(building)
	room.hrr_kw = 100.0
	room.hrr_target_kw = 100.0
	room.o2_hrr_factor = 1.0
	room.fuel_consumed_MJ_step = 0.1
	room.smoke_prod_kg_s = 0.02
	room.retained_unburned_MJ = 1.2
	room.fire_time_s = 1.0
	var transaction: Dictionary = combustion.evaluate_phase3_canonical_combustion_step(
		room,
		1.0,
		_context(),
		ledger.get_canonical_combustion_input(0),
		{},
		_species_result()
	)
	var decision: float = float(transaction.get("decision_fraction", -1.0))
	_assert_true(decision > 0.0 and decision < 1.0, "canonical throttle must be partial")
	_assert_close(
		float(transaction.get("accepted_hrr_kw", 0.0)),
		100.0 * decision,
		"HRR common decision"
	)
	_assert_close(
		float(transaction.get("accepted_fuel_MJ", 0.0)),
		0.1 * decision,
		"fuel common decision"
	)
	_assert_close(
		_sum_species(transaction.get("accepted_species_kg", {})),
		_sum_species(transaction.get("requested_species_kg", {})) * decision,
		"species common decision"
	)
	_assert_true(ledger.stage_canonical_combustion_transaction(transaction), "stage")
	_assert_true(ledger.finalize_canonical_combustion_bundle(
		0,
		{"sensible_enthalpy_kj": 70.0},
		{"gas_mass_kg": 0.3, "sensible_enthalpy_kj": 0.0},
		"fixture-1"
	), "bundle")
	ledger.finalize_step(building, 20.0)
	var result: Dictionary = ledger.get_results().get("0", {})
	_assert_close(_value(result, "phase3_shadow_combustion_atomic_fraction"), 1.0, "atomic")
	_assert_close(_value(result, "phase3_shadow_combustion_o2_residual_kg"), 0.0, "O2")
	_assert_close(_value(result, "phase3_shadow_combustion_energy_residual_kj"), 0.0, "energy")
	_assert_close(_value(result, "phase3_shadow_combustion_species_residual_kg"), 0.0, "species")
	_assert_close(_value(result, "phase3_shadow_combustion_zero_o2_flame_flag"), 0.0, "flame")
	_free_setup(setup)


func _test_empty_upper_zone_bootstraps_from_lower() -> void:
	var setup: Dictionary = _make_setup(0.209, true)
	var building = setup["building"]
	var room = setup["room"]
	room.lower_gas_kg += room.upper_gas_kg
	room.upper_gas_kg = 0.0
	room.upper_energy_kj = 0.0
	var combustion = CombustionSystemScript.new()
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	combustion.begin_phase3_shadow_step(building)
	room.hrr_kw = 100.0
	room.hrr_target_kw = 100.0
	room.fuel_consumed_MJ_step = 0.1
	var transaction: Dictionary = combustion.evaluate_phase3_canonical_combustion_step(
		room, 1.0, _context(), ledger.get_canonical_combustion_input(0), {}, _species_result()
	)
	_assert_true(String(transaction.get("o2_source_zone", "")) == "lower", "bootstrap source")
	_assert_true(float(transaction.get("decision_fraction", 0.0)) > 0.0, "bootstrap decision")
	_assert_true(ledger.stage_canonical_combustion_transaction(transaction), "bootstrap stage")
	_assert_true(ledger.finalize_canonical_combustion_bundle(
		0,
		{"sensible_enthalpy_kj": 70.0},
		{"gas_mass_kg": 0.3, "sensible_enthalpy_kj": 0.0},
		"fixture-bootstrap"
	), "bootstrap bundle")
	ledger.finalize_step(building, 20.0)
	var result: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		_value(result, "phase3_shadow_combustion_o2_source_zone_code"), 2.0, "lower code"
	)
	_assert_true(_value(result, "phase3_shadow_upper_gas_kg") > 0.0, "upper zone created")
	_assert_close(_value(result, "phase3_shadow_combustion_atomic_fraction"), 1.0, "bootstrap atomic")
	_free_setup(setup)


func _test_extinction_rejects_the_whole_transaction() -> void:
	var setup: Dictionary = _make_setup(0.05, true)
	var building = setup["building"]
	var room = setup["room"]
	var combustion = CombustionSystemScript.new()
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	combustion.begin_phase3_shadow_step(building)
	room.hrr_kw = 500.0
	room.hrr_target_kw = 500.0
	room.fuel_consumed_MJ_step = 0.5
	room.smoke_prod_kg_s = 0.2
	var transaction: Dictionary = combustion.evaluate_phase3_canonical_combustion_step(
		room, 1.0, _context(), ledger.get_canonical_combustion_input(0), {}, _species_result()
	)
	_assert_close(float(transaction.get("decision_fraction", -1.0)), 0.0, "decision")
	_assert_close(float(transaction.get("accepted_hrr_kw", -1.0)), 0.0, "HRR")
	_assert_close(float(transaction.get("accepted_o2_kg", -1.0)), 0.0, "O2")
	_assert_close(float(transaction.get("accepted_fuel_MJ", -1.0)), 0.0, "fuel")
	_assert_close(_sum_species(transaction.get("accepted_species_kg", {})), 0.0, "species")
	_assert_close(float(transaction.get("zero_o2_flame_flag", -1.0)), 0.0, "zero-O2 flame")
	_free_setup(setup)


func _test_no_fire_is_an_inert_transaction() -> void:
	var setup: Dictionary = _make_setup(0.209, false)
	var building = setup["building"]
	var room = setup["room"]
	var combustion = CombustionSystemScript.new()
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	combustion.begin_phase3_shadow_step(building)
	var transaction: Dictionary = combustion.evaluate_phase3_canonical_combustion_step(
		room, 1.0, _context(), ledger.get_canonical_combustion_input(0), {}, {}
	)
	_assert_close(float(transaction.get("decision_fraction", -1.0)), 0.0, "no-fire decision")
	_assert_close(float(transaction.get("accepted_hrr_kw", -1.0)), 0.0, "no-fire HRR")
	_free_setup(setup)


func _make_setup(upper_o2: float, with_fire: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 38.0
	room.upper_energy_kj = 900.0
	room.lower_energy_kj = 0.0
	room.o2_upper = upper_o2
	room.o2_lower = 0.209
	room.o2 = upper_o2
	room.o2_hrr_factor = 1.0
	room.temp_upper_c = 120.0
	if with_fire:
		var fire = FireModelScript.new()
		fire.fuel_energy_MJ = 100.0
		fire.remaining_fuel_MJ = 100.0
		fire.max_hrr_kw = 500.0
		fire.o2_nominal = 0.209
		fire.o2_min_for_flame = 0.12
		fire.o2_consumption_kg_per_MJ = 0.076
		room.fire = fire
		room.hrr_kw = 100.0
		room.hrr_target_kw = 100.0
	building.rooms = {0: room}
	return {"building": building, "room": room}


func _context() -> Dictionary:
	return {
		"ambient_c": 20.0,
		"fire_o2_mode": "upper",
		"fire_o2_full_hrr_open": 0.209,
		"fire_fds_extinction_enabled": false,
		"fire_o2_hrr_rise_tau_s": 14.0,
		"fire_o2_hrr_fall_tau_s": 32.0,
	}


func _species_result() -> Dictionary:
	return {
		"total_species_kg": {"co": 0.01, "co2": 0.1, "hcn": 0.001},
		"upper_species_kg": {"co": 0.01, "co2": 0.1, "hcn": 0.001},
		"lower_species_kg": {"co": 0.0, "co2": 0.0, "hcn": 0.0},
	}


func _sum_species(species: Dictionary) -> float:
	var total: float = 0.0
	for value in species.values():
		total += float(value)
	return total


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
	if absf(actual - expected) > 1.0e-8 * maxf(1.0, absf(expected)):
		_fail("%s expected %s got %s" % [label, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
