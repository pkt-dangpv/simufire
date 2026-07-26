extends SceneTree

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")

var _failed: bool = false


func _init() -> void:
	_test_nominal_and_moderate_o2_keep_the_same_proposal()
	_test_zero_o2_rejects_without_advancing_age()
	_test_inventory_and_ventilation_caps_are_explicit()
	_test_unfiltered_growth_uses_the_t2_target()
	_test_intraroom_capability_without_active_spread_is_supported()
	_test_unsupported_mode_is_not_silently_accepted()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V1_FIRE_PROPOSAL_PASS")
	quit(0)


func _test_nominal_and_moderate_o2_keep_the_same_proposal() -> void:
	var combustion = CombustionSystemScript.new()
	var nominal: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, _context(), _source(0.209, 0.025, 1.0), _state()
	)
	var moderate: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, _context(), _source(0.124, 0.025, 1.0), _state()
	)
	_assert_close(_value(nominal, "supported_flag"), 1.0, "nominal support")
	_assert_close(_value(nominal, "proposal_age_s"), 80.0, "nominal age")
	_assert_close(_value(nominal, "curve_hrr_kw"), 300.0, "curve cap")
	_assert_close(_value(nominal, "proposal_hrr_kw"), 300.0, "nominal proposal")
	_assert_close(_value(nominal, "accepted_hrr_kw"), 300.0, "nominal accepted")
	_assert_close(
		_value(moderate, "proposal_hrr_kw"),
		_value(nominal, "proposal_hrr_kw"),
		"moderate O2 proposal independence"
	)
	_assert_close(_value(moderate, "accepted_hrr_kw"), 300.0, "moderate accepted")


func _test_zero_o2_rejects_without_advancing_age() -> void:
	var combustion = CombustionSystemScript.new()
	var result: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, _context(), _source(0.025, 0.025, 0.0), _state()
	)
	_assert_close(_value(result, "hard_extinction_flag"), 1.0, "hard extinction")
	_assert_close(_value(result, "proposal_age_s"), 79.0, "frozen age")
	_assert_close(_value(result, "accepted_hrr_kw"), 0.0, "zero O2 accepted")
	_assert_close(_value(result, "accepted_o2_kg"), 0.0, "zero O2 debit")
	_assert_close(_value(result, "accepted_fuel_MJ"), 0.0, "zero O2 fuel")
	_assert_close(_value(result, "zero_o2_flame_flag"), 0.0, "zero O2 flame")


func _test_inventory_and_ventilation_caps_are_explicit() -> void:
	var combustion = CombustionSystemScript.new()
	var inventory_limited: Dictionary = \
			combustion.evaluate_phase3_canonical_fire_proposal(
				1.0, _context(), _source(0.124, 0.025, 0.0076), _state()
			)
	_assert_close(
		_value(inventory_limited, "o2_inventory_cap_kw"), 100.0, "O2 cap"
	)
	_assert_close(
		_value(inventory_limited, "accepted_hrr_kw"), 100.0, "O2-limited HRR"
	)
	_assert_close(
		_value(inventory_limited, "decision_fraction"), 1.0 / 3.0, "common fraction"
	)
	_assert_close(
		_value(inventory_limited, "accepted_o2_kg"), 0.0076, "accepted O2"
	)
	_assert_close(
		_value(inventory_limited, "accepted_fuel_MJ"), 0.1, "accepted fuel"
	)

	var vent_context: Dictionary = _context()
	vent_context["kawagoe_limit_kw"] = 120.0
	var ventilation_limited: Dictionary = \
			combustion.evaluate_phase3_canonical_fire_proposal(
				1.0, vent_context, _source(0.209, 0.025, 1.0), _state()
			)
	_assert_close(
		_value(ventilation_limited, "ventilation_cap_kw"), 120.0, "vent cap"
	)
	_assert_close(
		_value(ventilation_limited, "accepted_hrr_kw"), 120.0, "vent-limited HRR"
	)


func _test_unfiltered_growth_uses_the_t2_target() -> void:
	var combustion = CombustionSystemScript.new()
	var state: Dictionary = _state()
	state["proposal_age_s"] = 9.0
	state["proposal_hrr_kw"] = 0.0
	var filtered_context: Dictionary = _context()
	filtered_context["fire_hrr_rise_tau_s"] = 6.0
	var filtered: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, filtered_context, _source(0.209, 0.025, 1.0), state
	)
	var direct_context: Dictionary = filtered_context.duplicate(true)
	direct_context["phase3_canonical_unfiltered_fire_growth_shadow_enabled"] = true
	var direct: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, direct_context, _source(0.209, 0.025, 1.0), state
	)
	_assert_true(
		_value(filtered, "proposal_hrr_kw") < _value(filtered, "proposal_target_kw"),
		"filtered growth must lag the target"
	)
	_assert_close(
		_value(direct, "proposal_hrr_kw"),
		_value(direct, "proposal_target_kw"),
		"unfiltered growth equals target"
	)
	_assert_close(
		_value(direct, "unfiltered_growth_flag"), 1.0, "unfiltered telemetry"
	)


func _test_unsupported_mode_is_not_silently_accepted() -> void:
	var combustion = CombustionSystemScript.new()
	var state: Dictionary = _state()
	state["secondary_hrr_gain_kw"] = 10.0
	var result: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, _context(), _source(0.209, 0.025, 1.0), state
	)
	_assert_close(_value(result, "supported_flag"), 0.0, "unsupported support")
	_assert_true(
		int(_value(result, "unsupported_reason_mask")) & 2 != 0,
		"secondary reason bit"
	)
	_assert_close(_value(result, "accepted_hrr_kw"), 0.0, "unsupported accepted")


func _test_intraroom_capability_without_active_spread_is_supported() -> void:
	var combustion = CombustionSystemScript.new()
	var context: Dictionary = _context()
	context["fire_intraroom_spread_enabled"] = true
	var result: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		1.0, context, _source(0.209, 0.025, 1.0), _state()
	)
	_assert_close(
		_value(result, "supported_flag"),
		1.0,
		"intraroom capability is not active room spread"
	)


func _state() -> Dictionary:
	return {
		"active_flag": true,
		"proposal_age_s": 79.0,
		"proposal_hrr_kw": 0.0,
		"proposal_target_kw": 0.0,
		"proposal_remaining_fuel_MJ": 6000.0,
		"growth_alpha_kw_s2": 0.047,
		"max_hrr_kw": 300.0,
		"fuel_energy_MJ": 6000.0,
		"remaining_fuel_MJ": 6000.0,
		"retained_unburned_MJ": 0.0,
		"secondary_hrr_gain_kw": 0.0,
		"flashover_hrr_multiplier": 1.0,
		"flashover_triggered_flag": false,
		"backdraft_active_flag": false,
		"backdraft_triggered_flag": false,
		"fire_latent_active_flag": false,
		"o2_consumption_kg_per_MJ": 0.076,
	}


func _context() -> Dictionary:
	return {
		"thermal_feedback_coeff": 0.0,
		"fire_unburned_generation_fraction": 0.0,
		"fire_pool_release_max_fraction": 0.0,
		"fire_spread_enabled": false,
		"fire_intraroom_spread_enabled": false,
		"fire_o2_independent": false,
		"fire_hrr_rise_tau_s": 0.0,
		"fire_hrr_fall_tau_s": 0.0,
		"kawagoe_limit_kw": 0.0,
	}


func _source(o2_ref: float, extinction_limit: float, available_o2_kg: float) -> Dictionary:
	return {
		"o2_ref": o2_ref,
		"extinction_limit": extinction_limit,
		"available_o2_kg": available_o2_kg,
	}


func _value(result: Dictionary, key: String) -> float:
	return float(result.get(key, 0.0))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label)


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-8 * maxf(1.0, absf(expected)):
		_fail("%s expected %s got %s" % [label, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
