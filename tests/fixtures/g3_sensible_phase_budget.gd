extends SceneTree

const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: Array[String] = []
var _observations: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var s: Dictionary = _state()
	var m: Dictionary = _material()
	var r: Dictionary = _request(0.1, 0.1)
	_group("L01")
	var p: Dictionary = _valid(s, r, m, "reference")
	var old: Dictionary = {}
	for key: String in Budget.PHASE_STATE_KEYS:
		old[key] = s[key]
	var ref: Dictionary = Budget.propose_phase_reference(old,
		{"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1}, m["reference_material"])
	for key: String in Budget.PHASE_STATE_KEYS:
		_near(p.get("candidate", {}).get(key, -1), ref.get("candidate", {}).get(key, -2), "reference " + key)
	_near(p.get("chemical_oxidation_heat_kj", -1), ref.get("oxidation_heat_kj", -2), "chemical equivalence")
	_group("L02")
	var hot: Dictionary = _hot()
	var heating: Dictionary = _request(0.0, 0.0, 398.15, 20.0, 10.0)
	p = _valid(hot, heating, m, "heat only")
	_near(p.get("candidate", {}).get("thermal_budget_kj", -1), 970.0, "heat debit once")
	_near(p.get("candidate", {}).get("liquid_sensible_kj", -1), 120.0, "liquid heat stored")
	_near(p.get("candidate", {}).get("vapour_sensible_kj", -1), 20.0, "vapour heat stored")
	_near(p.get("candidate", {}).get("deposited_heat_kj", -1), 0.0, "heating not combustion")
	_group("L03")
	p = _valid(hot, _request(0.1, 0.1, 398.15, 20.0, 10.0), m, "analytic hot")
	_observe("hot_cost", p.get("release_cost_kj", -1), 98.0)
	_observe("hot_liquid_sensible", p.get("candidate", {}).get("liquid_sensible_kj", -1), 108.0)
	_observe("hot_vapour_sensible", p.get("candidate", {}).get("vapour_sensible_kj", -1), 20.0)
	_observe("hot_q", p.get("deposited_increment_kj", -1), 2010.0)
	_observe("hot_budget", p.get("candidate", {}).get("thermal_budget_kj", -1), 872.0)
	_observe("hot_total", p.get("total_after_kj", -1), 24110.0)
	_near(p.get("chemical_oxidation_heat_kj", -1), 2000.0, "Q differs from chemical")
	_group("L04")
	var cold: Dictionary = _hot()
	cold["liquid_sensible_kj"] = -50.0
	cold["vapour_sensible_kj"] = -5.0
	p = _valid(cold, _request(0.1, 0.1, 273.15), m, "analytic cold")
	_observe("cold_cost", p.get("release_cost_kj", -1), 102.5)
	_observe("cold_q", p.get("deposited_increment_kj", -1), 1997.5)
	_observe("cold_liquid_sensible", p.get("candidate", {}).get("liquid_sensible_kj", 1), -45.0)
	_observe("cold_vapour_sensible", p.get("candidate", {}).get("vapour_sensible_kj", 1), -5.0)
	_group("L05")
	var limited: Dictionary = _hot()
	limited["thermal_budget_kj"] = 49.0
	p = _valid(limited, _request(0.1, 0.1, 378.15), m, "B cap")
	_near(p.get("accepted_release_kg", -1), 0.05, "B limits accepted mass")
	_near(p.get("release_budget_deficit_kj", -1), 49.0, "explicit B deficit")
	limited["deposited_heat_kj"] = 1e6
	var with_q: Dictionary = _valid(limited, _request(0.1, 0.1, 378.15), m, "Q cannot finance")
	_near(with_q.get("accepted_release_kg", -1), 0.05, "previous Q not B")
	limited["thermal_budget_kj"] = 0.0
	p = _valid(limited, _request(1.0, 1.0, 378.15), m, "same step heat not B")
	_near(p.get("accepted_release_kg", -1), 0.0, "oxidation cannot finance release")
	_near(p.get("accepted_oxidation_kg", -1), 0.2, "old vapour burns without B")
	_group("L06")
	for oxygen: float in [0.0, 0.2, 10.0]:
		var trial: Dictionary = _state()
		trial["o2_kg"] = oxygen
		p = _valid(trial, _request(0.1, 0.1), m, "O2 cap")
		_near(p.get("accepted_oxidation_kg", -1), minf(0.1, oxygen / 4.0), "O2 limits burn")
		_near(p.get("o2_consumed_kg", -1), minf(0.4, oxygen), "O2 consumed")
	_near(p.get("products_kg", {}).get("co2", -1), 0.275, "canonical CO2")
	_near(p.get("products_kg", {}).get("water_vapour", -1), 0.225, "canonical water")
	_group("L07")
	p = _valid(s, _request(10.0, 10.0), m, "inventory cap")
	_near(p.get("accepted_release_kg", -1), 1.0, "liquid cap")
	_near(p.get("accepted_oxidation_kg", -1), 1.0, "vapour cap")
	_near(p.get("candidate", {}).get("liquid_sensible_kj", -1), 0.0, "empty liquid S")
	_near(p.get("candidate", {}).get("vapour_sensible_kj", -1), 0.0, "empty vapour S")
	_group("L08")
	var idle: Dictionary = _request(1.0, 1.0, 398.15, 2000.0, 2000.0)
	idle["dt_s"] = 0.0
	p = _valid(hot, idle, m, "dt zero")
	_expect(p.get("candidate") == hot, "zero step exact snapshot")
	_near(p.get("accepted_heating_kj", -1), 0.0, "no zero-step heat")
	var fast: Dictionary = r.duplicate(true)
	fast["dt_s"] = 0.001
	_expect(Budget.propose_phase_sensible(s, fast, m) == Budget.propose_phase_sensible(s, r, m), "requests per STEP")
	var exact_idle: Dictionary = _hot()
	exact_idle["liquid_sensible_kj"] = 0.17
	exact_idle["vapour_sensible_kj"] = 0.03
	p = _valid(exact_idle, _request(0.0, 0.0), m, "positive idle step")
	_expect(p.get("candidate") == exact_idle, "idle preserves accounts exactly")
	_group("L09")
	var history: Dictionary = _state()
	var initial_total: float = 20000.0
	for i: int in range(10):
		var next: Dictionary = _valid(history, _request(0.05, 0.02, 323.15, 5.0, 0.0), m, "history")
		if next.get("valid", false):
			_near(next["total_after_kj"], initial_total, "multi-step total")
			history = next["candidate"].duplicate(true)
	_expect(Budget.propose_phase_sensible(history.duplicate(true), r, m) == Budget.propose_phase_sensible(history, r, m), "restart deterministic")
	_group("L10")
	var absent: Dictionary = _state()
	_reject(absent, _request(0.0, 0.0, 298.15, 0.0, 1.0), m, "heating absent vapour")
	absent["vapour_sensible_kj"] = 1e-20
	_reject(absent, r, m, "no finite S in absent phase")
	absent = _state()
	absent["liquid_fuel_kg"] = 0.0
	absent["liquid_sensible_kj"] = 1e-20
	_reject(absent, r, m, "no finite liquid S absent")
	_group("L11")
	var tiny: Dictionary = _state()
	tiny["liquid_fuel_kg"] = 1e-20
	tiny["liquid_sensible_kj"] = 1e-18
	p = _valid(tiny, _request(0.0, 0.0), m, "tiny phase retained")
	_expect(p.get("candidate", {}).get("liquid_sensible_kj", 0.0) != 0.0, "no small mass erasure")
	_expect(p.get("candidate", {}).get("liquid_fuel_kg", 0.0) == 1e-20, "tiny inventory exact")
	_group("L12")
	for key: String in ["liquid_profile", "vapour_profile"]:
		var wrong: Dictionary = m.duplicate(true)
		wrong[key]["component_id"] = "other"
		_reject(s, r, wrong, "profile identity")
		wrong = m.duplicate(true)
		wrong[key]["phase"] = "gas" if key == "liquid_profile" else "liquid"
		wrong[key]["caloric_model"] = "ideal_gas" if key == "liquid_profile" else "declared_liquid"
		_reject(s, r, wrong, "profile phase")
	var foreign: Dictionary = s.duplicate(true)
	foreign["component_id"] = "other"
	_reject(foreign, r, m, "state identity")
	_group("L13")
	for family: String in ["state", "request", "material"]:
		var template: Dictionary = s if family == "state" else (r if family == "request" else m)
		for key: String in template:
			var missing: Dictionary = template.duplicate(true)
			missing.erase(key)
			_reject_family(family, missing, s, r, m, "missing " + key)
			if typeof(template[key]) in [TYPE_INT, TYPE_FLOAT]:
				for bad: Variant in [NAN, INF, true, "1"]:
					var invalid: Dictionary = template.duplicate(true)
					invalid[key] = bad
					_reject_family(family, invalid, s, r, m, "bad " + key)
		var extra: Dictionary = template.duplicate(true)
		extra["unexpected"] = 1.0
		_reject_family(family, extra, s, r, m, "closed schema")
		_reject_family(family, null, s, r, m, "not dictionary")
	_group("L14")
	for key: String in ["schema", "component_id"]:
		for bad: Variant in [true, "", "incompatible"]:
			var wrong: Dictionary = s.duplicate(true)
			wrong[key] = bad
			_reject(wrong, r, m, "state String schema")
			wrong = m.duplicate(true)
			wrong[key] = bad
			_reject(s, r, wrong, "material String schema")
	for key: String in m["reference_material"]:
		var wrong: Dictionary = m.duplicate(true)
		wrong["reference_material"].erase(key)
		_reject(s, r, wrong, "reference key missing")
		wrong = m.duplicate(true)
		wrong["reference_material"][key] = true
		_reject(s, r, wrong, "reference bool")
	_group("L15")
	var over: Dictionary = _state()
	over["liquid_sensible_kj"] = 10000.0
	_reject(over, r, m, "initial outside support")
	_reject(s, _request(0.0, 0.0, 298.15, 800.0), m, "heated outside support")
	_reject(s, _request(0.1, 0.1, 600.0), m, "emission outside support")
	_reject(s, _request(0.0, 0.0, 298.15, 1200.0), m, "insufficient heating B")
	var zero_cost: Dictionary = m.duplicate(true)
	zero_cost["reference_material"]["liquid_heat_kj_kg"] = 19999.0
	zero_cost["reference_material"]["phase_enthalpy_kj_kg"] = 1.0
	_reject(_hot(), _request(0.1, 0.0), zero_cost, "nonpositive release cost")
	_group("L16")
	var overflow: Dictionary = _state()
	overflow["initial_fuel_mass_kg"] = 1e308
	overflow["liquid_fuel_kg"] = 1e308
	_reject(overflow, r, m, "potential overflow")
	_reject(s, _request(0.0, 0.0, 298.15, 1e308, 1e308), m, "heat overflow")
	var invalid_profile: Dictionary = m.duplicate(true)
	invalid_profile["vapour_profile"]["samples"][0]["cp_kj_kg_k"] = 1e308
	invalid_profile["vapour_profile"]["samples"][1]["cp_kj_kg_k"] = 1e308
	_reject(s, _request(0.1, 0.1, 398.15), invalid_profile, "profile integral overflow")
	var deficit_overflow: Dictionary = _material()
	deficit_overflow["liquid_profile"] = _profile("liquid", 1e-300)
	deficit_overflow["reference_material"]["liquid_heat_kj_kg"] = 1.0
	deficit_overflow["reference_material"]["vapour_heat_kj_kg"] = 1e200
	deficit_overflow["reference_material"]["phase_enthalpy_kj_kg"] = 1e200
	var huge: Dictionary = _state()
	huge["initial_fuel_mass_kg"] = 1e200
	huge["liquid_fuel_kg"] = 1e200
	huge["thermal_budget_kj"] = 1.0
	_reject(huge, _request(1e200, 0.0), deficit_overflow, "reported budget deficit overflow")
	_group("L17")
	var copies: Array = [s.duplicate(true), r.duplicate(true), m.duplicate(true)]
	p = _valid(s, r, m, "immutable")
	_expect(s == copies[0] and r == copies[1] and m == copies[2], "inputs untouched")
	if p.get("valid", false):
		p["candidate"]["liquid_fuel_kg"] = 999.0
	_expect(s == copies[0], "candidate no alias")
	_reject(s, _request(0.0, 0.0, 900.0), m, "rejection immutable")
	_expect(s == copies[0] and m == copies[2], "rejected inputs untouched")
	_group("L18")
	# Nonlinear gas Cp: s(348.15)=75, s(398.15)=200. The mixed S is
	# 275 kJ in 2 kg, not 2*s(mean temperature)=262.5 kJ.
	var nonlinear: Dictionary = m.duplicate(true)
	nonlinear["vapour_profile"]["samples"] = [
		{"temperature_k": 273.15, "cp_kj_kg_k": 0.5},
		{"temperature_k": 498.15, "cp_kj_kg_k": 5.0}]
	var mix: Dictionary = _state()
	mix["initial_fuel_mass_kg"] = 2.0
	mix["vapour_fuel_kg"] = 1.0
	mix["vapour_sensible_kj"] = 75.0
	mix["thermal_budget_kj"] = 2000.0
	p = _valid(mix, _request(1.0, 0.0, 398.15), nonlinear, "nonlinear enthalpy mix")
	_near(p.get("candidate", {}).get("vapour_sensible_kj", -1), 275.0, "sum enthalpies not temperatures")
	_group("L19")
	var signed_q: Dictionary = _state()
	signed_q["deposited_heat_kj"] = -500.0
	p = _valid(signed_q, _request(0.0, 0.0), m, "signed reservoir reference")
	_near(p.get("candidate", {}).get("deposited_heat_kj", 0), -500.0, "Q signed offset")
	var very_cold: Dictionary = m.duplicate(true)
	very_cold["vapour_profile"] = _profile("gas", 1000.0)
	var cold_vapour: Dictionary = _state()
	cold_vapour["vapour_fuel_kg"] = 0.2
	cold_vapour["initial_fuel_mass_kg"] = 1.2
	cold_vapour["vapour_sensible_kj"] = -5000.0
	p = _valid(cold_vapour, _request(0.0, 0.1), very_cold, "signed sensible delivery")
	_near(p.get("deposited_increment_kj", 0), -500.0, "signed delivery not chemical HRR")
	for key: String in ["dt_s", "release_kg", "oxidation_kg", "heat_liquid_kj", "heat_vapour_kj"]:
		var wrong: Dictionary = r.duplicate(true)
		wrong[key] = -1.0
		_reject(s, wrong, m, "negative request")
	_group("L20")
	for budget: float in [0.0, 50.0, 1000.0]:
		for oxygen: float in [0.0, 0.2, 10.0]:
			var grid: Dictionary = _state()
			grid["thermal_budget_kj"] = budget
			grid["o2_kg"] = oxygen
			p = _valid(grid, r, m, "analytic grid")
			_near(p.get("accepted_release_kg", -1), minf(0.1, budget / 1000.0), "grid release")
			_near(p.get("accepted_oxidation_kg", -1), minf(minf(0.1, budget / 1000.0), oxygen / 4.0), "grid oxidation")
	print("G3_SENSIBLE_PHASE_BUDGET " + JSON.stringify({"groups": _groups,
		"checks": _checks, "failures": _failures, "observations": _observations}))
	if _failed:
		quit(1)
		return
	print("G3_SENSIBLE_PHASE_BUDGET_PASS")
	quit(0)


func _profile(phase: String, cp: float) -> Dictionary:
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_CHO",
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration",
		"provenance": "synthetic: constant Cp ledger oracle", "samples": [
			{"temperature_k": 273.15, "cp_kj_kg_k": cp},
			{"temperature_k": 498.15, "cp_kj_kg_k": cp}]}


func _material() -> Dictionary:
	return {"schema": "g3_phase_sensible_material_v1", "component_id": "synthetic_CHO",
		"liquid_profile": _profile("liquid", 2.0), "vapour_profile": _profile("gas", 1.0),
		"reference_material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid",
			"vapour_phase": "gas", "water_product_phase": "gas", "atom_mass_basis": "nominal_C12_H1_O16",
			"chemical_energy_basis": "complete_oxidation_net", "reference_temperature_k": 298.15,
			"reference_pressure_pa": 100000.0, "mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
			"liquid_heat_kj_kg": 19000.0, "vapour_heat_kj_kg": 20000.0,
			"phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic: CHO ledger, not a measured fuel"}}


func _state() -> Dictionary:
	return {"schema": "g3_phase_sensible_state_v1", "component_id": "synthetic_CHO",
		"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0, "vapour_fuel_kg": 0.0,
		"o2_kg": 10.0, "thermal_budget_kj": 1000.0, "deposited_heat_kj": 0.0,
		"liquid_sensible_kj": 0.0, "vapour_sensible_kj": 0.0}


func _hot() -> Dictionary:
	var result: Dictionary = _state()
	result["initial_fuel_mass_kg"] = 1.2
	result["vapour_fuel_kg"] = 0.2
	result["liquid_sensible_kj"] = 100.0
	result["vapour_sensible_kj"] = 10.0
	return result


func _request(release: float, oxidation: float, temperature: float = 298.15,
	heat_l: float = 0.0, heat_v: float = 0.0) -> Dictionary:
	return {"dt_s": 1.0, "release_kg": release, "oxidation_kg": oxidation,
		"heat_liquid_kj": heat_l, "heat_vapour_kj": heat_v, "emitted_vapour_temperature_k": temperature}


func _group(name: String) -> void:
	_groups.append(name)


func _valid(s: Dictionary, r: Dictionary, m: Dictionary, label: String) -> Dictionary:
	var result: Dictionary = Budget.propose_phase_sensible(s, r, m)
	_expect(result.get("valid", false), label + " valid: " + str(result.get("errors")))
	if result.get("valid", false):
		_near(result["total_residual_kj"], 0.0, label + " total balance")
		_near(result["mass_residual_kg"], 0.0, label + " mass balance")
		for key: String in ["C", "H", "O"]:
			_near(result["element_residuals_kg"][key], 0.0, label + " element " + key)
		_expect(not result["physical_approval"] and not result["integration_enabled"] and not result["product_activation"], label + " no activation")
	return result


func _reject(s: Variant, r: Variant, m: Variant, label: String) -> void:
	var result: Dictionary = Budget.propose_phase_sensible(s, r, m)
	_expect(not result.get("valid", true), label + " rejected")
	_expect(result.get("candidate", {"bad": 1}).is_empty(), label + " no candidate")
	_expect(not result.get("errors", []).is_empty(), label + " errors")
	_expect(not result.get("physical_approval", true) and not result.get("product_activation", true), label + " no approval")


func _reject_family(family: String, value: Variant, s: Dictionary, r: Dictionary, m: Dictionary, label: String) -> void:
	_reject(value if family == "state" else s, value if family == "request" else r,
		value if family == "material" else m, label)


func _observe(key: String, actual: float, expected: float) -> void:
	_observations[key] = actual
	_near(actual, expected, key)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= 1e-9 + 1e-12 * maxf(absf(actual), absf(expected)), label + " observed=" + str(actual))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
