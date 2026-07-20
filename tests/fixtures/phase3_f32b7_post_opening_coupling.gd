extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

var _failed: bool = false


func _init() -> void:
	_test_closed_state_keeps_upper_source()
	_test_counterflow_selects_lower_source()
	_test_counterflow_without_lower_o2_cannot_burn()
	_test_lower_o2_debit_is_atomic()
	_test_heskestad_source_term_is_opt_in()
	if _failed:
		quit(1)
		return
	print("PHASE3_F32B7_POST_OPENING_COUPLING_PASS")
	quit(0)


func _test_closed_state_keeps_upper_source() -> void:
	var setup: Dictionary = _make_setup(0.06, 0.209)
	var transaction: Dictionary = _evaluate(setup, 0.0, 0.0)
	_assert_true(String(transaction.get("o2_source_zone", "")) == "upper", "closed upper source")
	_assert_close(
		float(transaction.get("post_opening_coupling_active_flag", -1.0)),
		0.0,
		"closed coupling inactive"
	)
	_assert_true(float(transaction.get("decision_fraction", 1.0)) < 0.10, "closed upper throttle")
	_free_setup(setup)


func _test_counterflow_selects_lower_source() -> void:
	var setup: Dictionary = _make_setup(0.06, 0.209)
	var transaction: Dictionary = _evaluate(setup, 0.10, 0.0209)
	_assert_true(String(transaction.get("o2_source_zone", "")) == "lower", "open lower source")
	_assert_close(
		float(transaction.get("post_opening_source_switched_to_lower_flag", 0.0)),
		1.0,
		"lower switch telemetry"
	)
	_assert_true(float(transaction.get("decision_fraction", 0.0)) > 0.99, "fresh lower full HRR")
	_free_setup(setup)


func _test_counterflow_without_lower_o2_cannot_burn() -> void:
	var setup: Dictionary = _make_setup(0.06, 0.0)
	var transaction: Dictionary = _evaluate(setup, 0.10, 0.0209)
	_assert_true(String(transaction.get("o2_source_zone", "")) == "lower", "starved lower selected")
	_assert_close(float(transaction.get("decision_fraction", -1.0)), 0.0, "no lower O2 no burn")
	_assert_close(float(transaction.get("zero_o2_flame_flag", -1.0)), 0.0, "no zombie flame")
	_free_setup(setup)


func _test_lower_o2_debit_is_atomic() -> void:
	var setup: Dictionary = _make_setup(0.06, 0.209)
	var building = setup["building"]
	var room = setup["room"]
	var combustion = CombustionSystemScript.new()
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	combustion.begin_phase3_shadow_step(building)
	var before: Dictionary = ledger.get_canonical_combustion_input(0)
	var transaction: Dictionary = combustion.evaluate_phase3_canonical_combustion_step(
		room, 1.0, _context(0.10, 0.0209), before, {}, {}
	)
	_assert_true(ledger.stage_canonical_combustion_transaction(transaction), "atomic stage")
	_assert_true(ledger.finalize_canonical_combustion_bundle(0, {}, {}, "f32b7"), "atomic bundle")
	ledger.finalize_step(building, 20.0)
	var result: Dictionary = ledger.get_results()["0"]
	var lower_mass_kg: float = float(result["phase3_shadow_lower_gas_kg"])
	var post_lower_o2_kg: float = lower_mass_kg * float(
		result["phase3_shadow_persistent_post_lower_o2_fraction"]
	)
	var expected_o2_kg: float = float(before["lower_o2_kg"]) \
			- float(transaction["accepted_o2_kg"])
	_assert_close(post_lower_o2_kg, expected_o2_kg, "atomic lower O2 debit")
	_assert_close(
		float(result["phase3_shadow_combustion_o2_residual_kg"]),
		0.0,
		"atomic O2 residual"
	)
	_assert_close(
		float(result["phase3_shadow_post_opening_lower_o2_closure_residual_kg"]),
		0.0,
		"coupled lower O2 closure"
	)
	_free_setup(setup)


func _test_heskestad_source_term_is_opt_in() -> void:
	var setup: Dictionary = _make_setup(0.06, 0.209)
	var room = setup["room"]
	var thermal = ThermalSystemScript.new()
	thermal.plume_mccaffrey_qc_fraction = 0.3
	var canonical_input: Dictionary = {
		"valid": true,
		"lower_gas_kg": 38.0,
		"lower_energy_kj": 0.0,
		"lower_o2_fraction": 0.209,
		"interface_m": 1.0,
	}
	var baseline: Dictionary = thermal.preview_phase3_canonical_plume_flux(
		room, canonical_input, 1.0, false
	)
	var coupled: Dictionary = thermal.preview_phase3_canonical_plume_flux(
		room, canonical_input, 1.0, true
	)
	var expected_source_kg: float = 0.0018 * 1280.0 * 0.3
	_assert_close(
		float(baseline.get("source_term_mass_kg", -1.0)),
		0.0,
		"source term default off"
	)
	_assert_close(
		float(coupled.get("source_term_mass_kg", 0.0)),
		expected_source_kg,
		"source term opt in"
	)
	_assert_close(
		float(coupled.get("gas_mass_kg", 0.0))
				- float(baseline.get("gas_mass_kg", 0.0)),
		expected_source_kg,
		"source term adds mass exactly"
	)
	_free_setup(setup)


func _evaluate(setup: Dictionary, exchange_kg: float, incoming_o2_kg: float) -> Dictionary:
	var building = setup["building"]
	var room = setup["room"]
	var combustion = CombustionSystemScript.new()
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	combustion.begin_phase3_shadow_step(building)
	return combustion.evaluate_phase3_canonical_combustion_step(
		room,
		1.0,
		_context(exchange_kg, incoming_o2_kg),
		ledger.get_canonical_combustion_input(0),
		{},
		{}
	)


func _make_setup(upper_o2: float, lower_o2: float) -> Dictionary:
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
	room.o2_lower = lower_o2
	room.o2 = upper_o2
	room.o2_hrr_factor = 1.0
	room.temp_upper_c = 120.0
	var fire = FireModelScript.new()
	fire.fuel_energy_MJ = 1000.0
	fire.remaining_fuel_MJ = 1000.0
	fire.max_hrr_kw = 1280.0
	fire.o2_nominal = 0.209
	fire.o2_min_for_flame = 0.055
	fire.o2_consumption_kg_per_MJ = 0.076
	room.fire = fire
	room.hrr_kw = 1280.0
	room.hrr_target_kw = 1280.0
	room.fuel_consumed_MJ_step = 1.28
	building.rooms = {0: room}
	return {"building": building, "room": room}


func _context(exchange_kg: float, incoming_o2_kg: float) -> Dictionary:
	return {
		"ambient_c": 20.0,
		"fire_o2_mode": "upper",
		"fire_o2_full_hrr_open": 0.15,
		"fire_fds_extinction_enabled": false,
		"fire_o2_hrr_rise_tau_s": 0.001,
		"fire_o2_hrr_fall_tau_s": 0.001,
		"phase3_post_opening_coupling_enabled": true,
		"phase3_post_opening_counterflow_exchange_kg": exchange_kg,
		"phase3_post_opening_counterflow_incoming_o2_kg": incoming_o2_kg,
	}


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
