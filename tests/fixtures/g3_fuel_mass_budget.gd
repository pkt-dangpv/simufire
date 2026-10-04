extends SceneTree

## D1: analytical controls of the actual GDScript kernel, no SimulationEngine.
## Synthetic composition and heat are not a calibration of methane or furniture.
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const MASS_TOL: float = 1.0e-12
const ENERGY_TOL: float = 1.0e-9
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: int = 0


func _init() -> void:
	call_deferred("_run")


func _state() -> Dictionary:
	return {"initial_fuel_mass_kg": 1.0, "solid_fuel_kg": 1.0, "released_fuel_kg": 0.0, "o2_kg": 5.0}


func _material() -> Dictionary:
	return {
		"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
		"chemical_heat_kj_per_kg": 20000.0,
		"chemical_energy_basis": "complete_oxidation_net",
		"provenance": "synthetic:nominal-CHO-algebra-only",
	}


func _request(release: float, oxidation: float) -> Dictionary:
	return {"dt_s": 1.0, "release_kg": release, "oxidation_kg": oxidation, "release_mode": "prescribed_mass_transfer"}


func _run() -> void:
	var s: Dictionary = _state()
	s["o2_kg"] = 0.0
	var released_only: Dictionary = _valid(s, _request(0.1, 0.1), _material(), "no oxygen")
	_near(float(released_only.get("accepted_release_kg", -1.0)), 0.1, MASS_TOL, "release without O2")
	_near(float(released_only.get("accepted_oxidation_kg", -1.0)), 0.0, MASS_TOL, "no oxidation without O2")
	_near(float(released_only.get("oxidation_heat_kj", -1.0)), 0.0, ENERGY_TOL, "no heat without O2")
	var full: Dictionary = _valid(_state(), _request(0.1, 0.1), _material(), "abundant oxygen")
	_near(float(full.get("o2_consumed_kg", -1.0)), 0.4, MASS_TOL, "stoichiometric O2")
	_near(float(full.get("products_kg", {}).get("co2", -1.0)), 0.275, MASS_TOL, "CO2 contains oxidant mass")
	_near(float(full.get("products_kg", {}).get("water_vapour", -1.0)), 0.225, MASS_TOL, "water contains oxidant mass")
	_near(float(full.get("oxidation_heat_kj", -1.0)), 2000.0, ENERGY_TOL, "chemical heat")

	var half: Dictionary = _valid(_state(), _request(0.005, 0.0025), _material(), "same heat more emission")
	var all_burned: Dictionary = _valid(_state(), _request(0.0025, 0.0025), _material(), "same heat less emission")
	_near(float(half.get("oxidation_heat_kj", -1.0)), 50.0, ENERGY_TOL, "counterexample heat")
	_check(half.get("oxidation_heat_kj") == all_burned.get("oxidation_heat_kj"), "same heat distinct emission")
	_near(float(half.get("candidate", {}).get("released_fuel_kg", -1.0)), 0.0025, MASS_TOL, "unoxidized fuel remains")
	_near(float(all_burned.get("candidate", {}).get("released_fuel_kg", -1.0)), 0.0, MASS_TOL, "no unoxidized fuel")

	s = _state()
	s["o2_kg"] = 0.04
	var limited: Dictionary = _valid(s, _request(0.1, 0.1), _material(), "oxygen limited")
	_near(float(limited.get("accepted_oxidation_kg", -1.0)), 0.01, MASS_TOL, "oxygen limits oxidized mass")
	_near(float(limited.get("candidate", {}).get("released_fuel_kg", -1.0)), 0.09, MASS_TOL, "O2 cap leaves fuel")
	s = _state()
	s["solid_fuel_kg"] = 0.0
	s["released_fuel_kg"] = 0.1
	var tail: Dictionary = _valid(s, _request(1.0, 1.0), _material(), "solid exhausted gas remains")
	_near(float(tail.get("accepted_release_kg", -1.0)), 0.0, MASS_TOL, "cannot release exhausted solid")
	_near(float(tail.get("accepted_oxidation_kg", -1.0)), 0.1, MASS_TOL, "can oxidize previously released fuel")
	var capped: Dictionary = _valid(_state(), _request(2.0, 2.0), _material(), "fuel exhausted")
	_near(float(capped.get("accepted_release_kg", -1.0)), 1.0, MASS_TOL, "release availability cap")
	_near(float(capped.get("accepted_oxidation_kg", -1.0)), 1.0, MASS_TOL, "oxidation availability cap")
	s = _state()
	s["solid_fuel_kg"] = 0.0
	var empty: Dictionary = _valid(s, _request(1.0, 1.0), _material(), "empty inventory")
	_near(float(empty.get("oxidation_heat_kj", -1.0)), 0.0, ENERGY_TOL, "empty inventory no heat")
	var req: Dictionary = _request(0.1, 0.1)
	req["dt_s"] = 0.0
	var zero: Dictionary = _valid(_state(), req, _material(), "zero step")
	_check(zero.get("candidate") == _state(), "zero step leaves inventories unchanged")

	var mat: Dictionary = _material()
	mat["heat_of_gasification_kj_kg"] = 1000.0
	req = _request(0.1, 0.1)
	req["release_mode"] = "thermal_budgeted"
	req["release_heat_budget_kj"] = 10.0
	var thermal: Dictionary = _valid(_state(), req, mat, "thermal budget limits release")
	_near(float(thermal.get("accepted_release_kg", -1.0)), 0.01, MASS_TOL, "release cost availability")
	_near(float(thermal.get("release_cost_kj", -1.0)), 10.0, ENERGY_TOL, "release cost paid explicitly")
	_near(float(thermal.get("oxidation_heat_kj", -1.0)), 200.0, ENERGY_TOL, "same step heat not reused for release")
	req["release_heat_budget_kj"] = 0.0
	var no_heat: Dictionary = _valid(_state(), req, mat, "no external heat budget")
	_near(float(no_heat.get("accepted_release_kg", -1.0)), 0.0, MASS_TOL, "no free thermal release")

	mat = _material()
	mat["mass_fractions"] = {"C": 0.4, "H": 0.1, "O": 0.5}
	_valid(_state(), _request(0.125, 0.05), mat, "oxygenated CHO fuel")
	mat["mass_fractions"] = {"C": 1.0, "H": 0.0, "O": 0.0}
	_valid(_state(), _request(0.03, 0.015), mat, "pure carbon algebraic control")
	mat["mass_fractions"] = {"C": 0.0, "H": 1.0, "O": 0.0}
	_valid(_state(), _request(0.03, 0.015), mat, "pure hydrogen algebraic control")
	mat["mass_fractions"] = {"C": 0.0, "H": 0.0, "O": 1.0}
	_invalid(_state(), _request(0.1, 0.1), mat, "not an oxygen-requiring fuel")
	_invalid(null, {}, {}, "missing structures")
	mat = _material()
	mat.erase("provenance")
	_invalid(_state(), _request(0.1, 0.1), mat, "missing provenance")
	mat = _material()
	mat["chemical_energy_basis"] = "measured_effective_HOC"
	_invalid(_state(), _request(0.1, 0.1), mat, "effective heat is not chemical basis")
	mat = _material()
	mat["mass_fractions"]["N"] = 0.01
	_invalid(_state(), _request(0.1, 0.1), mat, "unsupported composition")
	mat = _material()
	mat["mass_fractions"]["C"] = 0.70
	_invalid(_state(), _request(0.1, 0.1), mat, "fractions do not sum to one")
	_invalid(_state(), _request(0.1, 0.1), {}, "missing material")
	req = _request(0.1, 0.1)
	req["dt_s"] = -1.0
	_invalid(_state(), req, _material(), "negative timestep")
	req = _request(0.1, 0.1)
	req["release_mode"] = "unknown"
	_invalid(_state(), req, _material(), "unknown release mode")
	req["release_mode"] = "thermal_budgeted"
	_invalid(_state(), req, _material(), "thermal mode missing cost and budget")
	mat = _material()
	mat["heat_of_gasification_kj_kg"] = 0.0
	req["release_heat_budget_kj"] = 10.0
	_invalid(_state(), req, mat, "zero thermal release cost rejected")
	req["release_mode"] = "prescribed_mass_transfer"
	_invalid(_state(), req, mat, "thermal data cannot be silently ignored")
	for value in [-0.1, INF, NAN, true, "1.0"]:
		s = _state()
		s["solid_fuel_kg"] = value
		_invalid(s, _request(0.1, 0.1), _material(), "invalid numeric state")
		req = _request(0.1, 0.1)
		req["release_kg"] = value
		_invalid(_state(), req, _material(), "invalid numeric request")
	s = _state()
	s["initial_fuel_mass_kg"] = 0.1
	_invalid(s, _request(0.1, 0.1), _material(), "inconsistent initial mass")
	s = _state()
	s["fuel_energy_MJ"] = 120.0
	_invalid(s, _request(0.1, 0.1), _material(), "unsupported energetic fallback")
	mat = _material()
	mat["chemical_heat_kj_per_kg"] = 1.0e308
	s = _state()
	s["initial_fuel_mass_kg"] = 10.0
	s["solid_fuel_kg"] = 10.0
	_invalid(s, _request(0.1, 0.1), mat, "derived chemical energy overflow")
	var original_s: Dictionary = _state()
	var original_r: Dictionary = _request(0.1, 0.05)
	var original_m: Dictionary = _material()
	var serialized: String = var_to_str([original_s, original_r, original_m])
	var first: Dictionary = Budget.propose(original_s, original_r, original_m)
	_check(var_to_str([original_s, original_r, original_m]) == serialized, "inputs never mutated")
	_check(first == Budget.propose(original_s, original_r, original_m), "deterministic proposal")
	first["candidate"]["solid_fuel_kg"] = 999.0
	_check(original_s == _state(), "candidate does not alias input")
	_check(Budget.MASS_ABS_TOL_KG == MASS_TOL, "mass tolerance fixed before controls")
	_check(Budget.ENERGY_ABS_TOL_KJ == ENERGY_TOL, "energy tolerance fixed before controls")
	print("G3_FUEL_MASS_BUDGET " + JSON.stringify({"failures": _failures, "checks": _checks, "groups": _groups}))
	if _failed:
		quit(1)
	else:
		print("G3_FUEL_MASS_BUDGET_PASS")
		quit(0)


func _valid(s: Dictionary, r: Dictionary, m: Dictionary, label: String) -> Dictionary:
	_groups += 1
	var result: Dictionary = Budget.propose(s, r, m)
	_check(bool(result.get("valid", false)), label + " accepted: " + str(result.get("errors")))
	if not bool(result.get("valid", false)):
		return result
	var after: Dictionary = result["candidate"]
	var products: Dictionary = result["products_kg"]
	# Independently reconstruct balances from inputs and outputs, not reported residuals.
	var before_mass: float = float(s["solid_fuel_kg"]) + float(s["released_fuel_kg"]) + float(s["o2_kg"])
	var remaining: float = float(after["solid_fuel_kg"]) + float(after["released_fuel_kg"])
	var after_mass: float = remaining + float(after["o2_kg"]) + float(products["co2"]) + float(products["water_vapour"])
	_near(before_mass, after_mass, MASS_TOL, label + " independent mass closure")
	var fractions: Dictionary = m["mass_fractions"]
	_near((float(s["solid_fuel_kg"]) + float(s["released_fuel_kg"])) * float(fractions["C"]),
		remaining * float(fractions["C"]) + float(products["co2"]) * 3.0 / 11.0, MASS_TOL, label + " carbon")
	_near((float(s["solid_fuel_kg"]) + float(s["released_fuel_kg"])) * float(fractions["H"]),
		remaining * float(fractions["H"]) + float(products["water_vapour"]) / 9.0, MASS_TOL, label + " hydrogen")
	_near((float(s["solid_fuel_kg"]) + float(s["released_fuel_kg"])) * float(fractions["O"]) + float(s["o2_kg"]),
		remaining * float(fractions["O"]) + float(after["o2_kg"]) + float(products["co2"]) * 8.0 / 11.0
		+ float(products["water_vapour"]) * 8.0 / 9.0, MASS_TOL, label + " oxygen")
	_near(float(s["solid_fuel_kg"]) - float(after["solid_fuel_kg"]),
		float(result["accepted_release_kg"]), MASS_TOL, label + " solid debit")
	_near(float(after["released_fuel_kg"]), float(s["released_fuel_kg"])
		+ float(result["accepted_release_kg"]) - float(result["accepted_oxidation_kg"]), MASS_TOL, label + " released inventory")
	var initial_chemical: float = (float(s["solid_fuel_kg"]) + float(s["released_fuel_kg"])) * float(m["chemical_heat_kj_per_kg"])
	_near(initial_chemical, remaining * float(m["chemical_heat_kj_per_kg"])
		+ float(result["oxidation_heat_kj"]), ENERGY_TOL, label + " independent chemical closure")
	_near(float(r.get("release_heat_budget_kj", 0.0)), float(result["release_cost_kj"])
		+ float(result["remaining_release_heat_budget_kj"]), ENERGY_TOL, label + " thermal cost closure")
	for key in ["solid_fuel_kg", "released_fuel_kg", "o2_kg"]:
		_check(float(after[key]) >= 0.0, label + " nonnegative " + key)
	return result


func _invalid(s: Variant, r: Variant, m: Variant, label: String) -> void:
	_groups += 1
	var result: Dictionary = Budget.propose(s, r, m)
	_check(not bool(result.get("valid", true)), label + " rejected")
	_check(not result.get("errors", []).is_empty(), label + " explicit errors")
	_check(result.get("candidate", {}) == {}, label + " no candidate")


func _near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= tolerance, label)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
