extends SceneTree

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")

var _failed: bool = false


func _init() -> void:
	_test_nominal_products_close()
	_test_partial_acceptance_uses_one_fraction()
	_test_fuel_cap_does_not_fake_rich_combustion()
	_test_zero_o2_stops_every_accepted_product()
	_test_carbon_cap_is_conservative()
	_test_explicit_object_profile_stays_shadow_only()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V2_FIRE_PRODUCTS_PASS")
	quit(0)


func _test_nominal_products_close() -> void:
	var products: Dictionary = _products(
		_context(), _source(0.209, 1.0), _state(), 1.0
	)
	_assert_close(_value(products, "supported_flag"), 1.0, "nominal support")
	_assert_close(_value(products, "common_fraction"), 1.0, "nominal fraction")
	_assert_close(_value(products, "requested_fuel_MJ"), 0.3, "nominal fuel")
	_assert_close(_value(products, "accepted_fuel_MJ"), 0.3, "accepted fuel")
	_assert_close(
		_value(products, "requested_total_energy_kj"), 300.0, "requested energy"
	)
	_assert_close(
		_value(products, "accepted_total_energy_kj"), 300.0, "accepted energy"
	)
	_assert_close(_value(products, "fuel_residual_MJ"), 0.0, "fuel residual")
	_assert_close(_value(products, "o2_residual_kg"), 0.0, "O2 residual")
	_assert_close(_value(products, "energy_residual_kj"), 0.0, "energy residual")
	_assert_close(
		_value(products, "accepted_carbon_residual_kg"),
		0.0,
		"carbon residual"
	)


func _test_partial_acceptance_uses_one_fraction() -> void:
	var products: Dictionary = _products(
		_context(), _source(0.124, 0.0076), _state(), 1.0
	)
	_assert_close(
		_value(products, "common_fraction"), 1.0 / 3.0, "partial fraction"
	)
	_assert_close(_value(products, "accepted_fuel_MJ"), 0.1, "partial fuel")
	_assert_close(_value(products, "accepted_o2_kg"), 0.0076, "partial O2")
	_assert_close(
		_value(products, "accepted_total_energy_kj"), 100.0, "partial energy"
	)
	var requested: Dictionary = products.get("requested_species_kg", {})
	var accepted: Dictionary = products.get("accepted_species_kg", {})
	for species_name in requested.keys():
		_assert_close(
			float(accepted.get(species_name, 0.0)),
			float(requested[species_name]) / 3.0,
			"partial " + String(species_name)
		)
	_assert_close(
		_value(products, "species_common_fraction_residual_kg"),
		0.0,
		"species common residual"
	)


func _test_fuel_cap_does_not_fake_rich_combustion() -> void:
	var state: Dictionary = _state()
	var combustion = CombustionSystemScript.new()
	var products: Dictionary = combustion.evaluate_phase3_canonical_fire_products(
		1.0,
		_context(),
		_source(0.209, 1.0),
		state,
		{
			"active_flag": 1.0,
			"supported_flag": 1.0,
			"proposal_hrr_kw": 300.0,
			"accepted_hrr_kw": 100.0,
			"decision_fraction": 1.0 / 3.0,
			"accepted_fuel_MJ": 0.1,
			"accepted_o2_kg": 0.0076,
			"o2_inventory_cap_kw": 10000.0,
			"ventilation_cap_kw": -1.0,
			"fuel_cap_kw": 100.0,
		}
	)
	_assert_close(
		_value(products, "common_fraction"), 1.0 / 3.0, "fuel-cap fraction"
	)
	_assert_close(
		_value(products, "quality_phi"), 1.0, "fuel cap keeps normal phi"
	)
	_assert_close(_value(products, "accepted_fuel_MJ"), 0.1, "fuel-cap debit")


func _test_zero_o2_stops_every_accepted_product() -> void:
	var products: Dictionary = _products(
		_context(), _source(0.025, 0.0), _state(), 1.0
	)
	_assert_close(_value(products, "common_fraction"), 0.0, "zero fraction")
	_assert_close(_value(products, "accepted_fuel_MJ"), 0.0, "zero fuel")
	_assert_close(_value(products, "accepted_o2_kg"), 0.0, "zero O2")
	_assert_close(
		_value(products, "accepted_total_energy_kj"), 0.0, "zero energy"
	)
	for species_value in Dictionary(
		products.get("accepted_species_kg", {})
	).values():
		_assert_close(float(species_value), 0.0, "zero species")


func _test_carbon_cap_is_conservative() -> void:
	var state: Dictionary = _state()
	var profile: Dictionary = state["product_profile"]
	profile["smoke_yield_kg_per_MJ"] = 1.0
	profile["co_yield_kg_per_MJ"] = 0.2
	profile["co2_yield_kg_per_MJ"] = 0.2
	state["product_profile"] = profile
	var products: Dictionary = _products(
		_context(), _source(0.209, 1.0), state, 1.0
	)
	_assert_true(_value(products, "carbon_scale") < 1.0, "carbon cap active")
	_assert_true(
		_value(products, "requested_carbon_products_kg")
				<= _value(products, "requested_carbon_available_kg") + 1.0e-10,
		"carbon products bounded"
	)
	_assert_close(
		_value(products, "requested_carbon_residual_kg"),
		0.0,
		"requested carbon closure"
	)


func _test_explicit_object_profile_stays_shadow_only() -> void:
	var state: Dictionary = _state()
	var profile: Dictionary = state["product_profile"]
	profile["object_count"] = 3.0
	profile["object_sync_required_flag"] = 1.0
	state["product_profile"] = profile
	var products: Dictionary = _products(
		_context(), _source(0.209, 1.0), state, 1.0
	)
	_assert_close(
		_value(products, "object_sync_required_flag"), 1.0, "object sync flag"
	)
	_assert_close(_value(products, "profile_object_count"), 3.0, "object count")


func _products(
	context: Dictionary,
	source: Dictionary,
	state: Dictionary,
	dt: float
	) -> Dictionary:
	var combustion = CombustionSystemScript.new()
	var proposal: Dictionary = combustion.evaluate_phase3_canonical_fire_proposal(
		dt, context, source, state
	)
	return combustion.evaluate_phase3_canonical_fire_products(
		dt, context, source, state, proposal
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
		"retained_unburned_MJ": 0.0,
		"secondary_hrr_gain_kw": 0.0,
		"flashover_hrr_multiplier": 1.0,
		"flashover_triggered_flag": false,
		"backdraft_active_flag": false,
		"backdraft_triggered_flag": false,
		"fire_latent_active_flag": false,
		"o2_consumption_kg_per_MJ": 0.076,
		"product_profile": {
			"object_count": 0.0,
			"object_sync_required_flag": 0.0,
			"smoke_yield_kg_per_MJ": 0.0088,
			"soot_fraction": 1.0,
			"co_yield_kg_per_MJ": 0.00025,
			"co2_yield_kg_per_MJ": 0.0831,
			"hcn_yield_kg_per_MJ": 0.00004,
			"hcl_yield_kg_per_MJ": 0.0,
			"acrolein_yield_kg_per_MJ": 0.00002,
			"formaldehyde_yield_kg_per_MJ": 0.000015,
			"chi_rad_normal": 0.35,
		},
	}


func _context() -> Dictionary:
	return {
		"thermal_feedback_coeff": 0.0,
		"fire_unburned_generation_fraction": 0.0,
		"fire_pool_release_max_fraction": 0.0,
		"fire_spread_enabled": false,
		"fire_o2_independent": false,
		"fire_hrr_rise_tau_s": 0.0,
		"fire_hrr_fall_tau_s": 0.0,
		"kawagoe_limit_kw": 0.0,
		"co_base_yield_kg_per_MJ": 0.00025,
		"co_max_yield_kg_per_MJ": 0.0125,
		"fire_co_yield_force_kg_per_MJ": -1.0,
		"fire_co_phi_rate": 2.0,
		"co2_base_yield_kg_per_MJ": 0.0831,
		"co2_min_yield_kg_per_MJ": 0.0594,
		"co2_phi_decay_rate": 2.5,
		"hcn_base_yield_kg_per_MJ": 0.00004,
		"hcn_max_yield_kg_per_MJ": 0.00025,
		"fuel_c_kg_per_MJ": 0.027,
		"hrr_chi_rad_normal": 0.35,
		"hrr_chi_rad_low_o2": 0.50,
	}


func _source(o2_ref: float, available_o2_kg: float) -> Dictionary:
	return {
		"o2_ref": o2_ref,
		"extinction_limit": 0.025,
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
