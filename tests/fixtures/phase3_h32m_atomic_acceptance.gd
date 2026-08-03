extends SceneTree

const ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

var _failed: bool = false


func _init() -> void:
	_check_pure_global_acceptance()
	_check_legacy_application_uses_the_same_fraction()
	_check_invalid_input_fails_closed()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32M_ATOMIC_ACCEPTANCE_PASS")
	quit(0)


func _check_pure_global_acceptance() -> void:
	var system = ZoneMassSystemScript.new()
	var shadow: Dictionary = _shadow()
	var routes: Array = _routes(system)
	var before: String = JSON.stringify(shadow)
	var evaluation: Dictionary = system._evaluate_atomic_bundle_acceptance(
		shadow, routes
	)
	_assert(bool(evaluation.get("valid", false)), "evaluation is valid")
	_assert(
		is_equal_approx(float(evaluation["accepted_fraction"]), 0.5),
		"one global donor fraction limits both routes"
	)
	_assert(JSON.stringify(shadow) == before, "evaluation never mutates shadow")
	_assert(
		JSON.stringify(routes) == JSON.stringify(_routes(system)),
		"evaluation never mutates routes"
	)
	var demands: Dictionary = evaluation.get("source_demands", {})
	_assert(demands.size() == 1, "routes aggregate into one source-zone demand")
	var demand: Dictionary = demands.values()[0]
	_assert(is_equal_approx(float(demand["gas_mass_kg"]), 6.0), "mass demand")
	_assert(
		is_equal_approx(float(demand["sensible_enthalpy_kj"]), 60.0),
		"energy demand"
	)
	# Mutating the returned diagnostic must never alias caller-owned routes.
	demand["gas_mass_kg"] = 999.0
	_assert(
		is_equal_approx(float(routes[0]["gas_mass_kg"]), 2.0),
		"source-demands result owns its data"
	)


func _check_legacy_application_uses_the_same_fraction() -> void:
	var system = ZoneMassSystemScript.new()
	var shadow: Dictionary = _shadow()
	var routes: Array = _routes(system)
	var bundle: Dictionary = system.make_atomic_bundle(
		"h32m:acceptance", "h32m_acceptance_fixture", routes, {}
	)
	var rejected: Dictionary = {}
	system._apply_atomic_bundle(shadow, bundle, rejected, {}, {})
	_assert(system._atomic_bundle_count == 1, "legacy bundle is counted once")
	_assert(system._atomic_route_count == 2, "legacy routes are counted once")
	_assert(
		is_equal_approx(system._atomic_min_accepted_fraction, 0.5),
		"legacy path consumes the extracted fraction"
	)
	_assert(
		is_equal_approx(float(shadow["0"]["upper_gas_kg"]), 0.0),
		"donor debit uses the shared fraction"
	)
	_assert(
		is_equal_approx(float(shadow["1"]["lower_gas_kg"]), 11.0),
		"first destination receives its accepted share"
	)
	_assert(
		is_equal_approx(float(shadow["2"]["lower_gas_kg"]), 12.0),
		"second destination receives its accepted share"
	)
	_assert(is_equal_approx(float(rejected["0"]), 3.0), "rejection preserved")


func _check_invalid_input_fails_closed() -> void:
	var system = ZoneMassSystemScript.new()
	var evaluation: Dictionary = system._evaluate_atomic_bundle_acceptance(
		_shadow(), [{"valid": false}]
	)
	_assert(not bool(evaluation.get("valid", true)), "invalid route is rejected")
	_assert(
		is_equal_approx(float(evaluation.get("accepted_fraction", 1.0)), 0.0),
		"invalid route accepts nothing"
	)


func _routes(system) -> Array:
	return [
		system.make_atomic_route(
			"h32m:r0", "h32m_fixture", 0, 1, "upper", "lower",
			2.0, 20.0
		),
		system.make_atomic_route(
			"h32m:r1", "h32m_fixture", 0, 2, "upper", "lower",
			4.0, 40.0
		),
	]


func _shadow() -> Dictionary:
	return {
		"0": _room_state(3.0, 30.0, 10.0, 100.0),
		"1": _room_state(10.0, 100.0, 10.0, 100.0),
		"2": _room_state(10.0, 100.0, 10.0, 100.0),
	}


func _room_state(
		upper_mass: float, upper_energy: float,
		lower_mass: float, lower_energy: float
	) -> Dictionary:
	return {
		"upper_gas_kg": upper_mass,
		"lower_gas_kg": lower_mass,
		"upper_energy_kj": upper_energy,
		"lower_energy_kj": lower_energy,
		"upper_o2_kg": 0.0,
		"lower_o2_kg": 0.0,
		"upper_species_kg": {},
		"lower_species_kg": {},
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-M atomic acceptance: " + message)
