extends SceneTree

const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var s: Dictionary = _state()
	var m: Dictionary = _material()
	var p: Dictionary = _valid(s, _request(0.1, 0.1), m, "complete")
	_near(p.get("phase_cost_kj", -1), 100.0, "phase cost")
	_near(p.get("oxidation_heat_kj", -1), 2000.0, "vapour heat, not liquid heat")
	_near(p.get("o2_consumed_kg", -1), 0.4, "oxygen stoichiometry")
	_near(p.get("products_kg", {}).get("co2", -1), 0.275, "CO2")
	_near(p.get("products_kg", {}).get("water_vapour", -1), 0.225, "water vapour")
	_near(p.get("candidate", {}).get("liquid_fuel_kg", -1), 0.9, "liquid debit")
	_near(p.get("candidate", {}).get("vapour_fuel_kg", -1), 0.0, "vapour consumed")
	_near(p.get("total_before_kj", -1), 20000.0, "analytical initial total")
	_near(p.get("candidate", {}).get("deposited_heat_kj", -1)
		- (1000.0 - p.get("candidate", {}).get("thermal_budget_kj", -1)), 1900.0, "net heat")
	for oxygen in [0.0, 0.2, 10.0]:
		for thermal in [0.0, 50.0, 1000.0]:
			var sample: Dictionary = _state()
			sample["o2_kg"] = oxygen
			sample["thermal_budget_kj"] = thermal
			var result: Dictionary = _valid(sample, _request(0.1, 0.1), m, "caps")
			var release: float = minf(0.1, thermal / 1000.0)
			_near(result.get("accepted_release_kg", -1), release, "thermal cap")
			_near(result.get("accepted_oxidation_kg", -1), minf(release, oxygen / 4.0), "oxygen cap")
	var stored: Dictionary = _state()
	stored["liquid_fuel_kg"] = 0.8
	stored["vapour_fuel_kg"] = 0.2
	stored["thermal_budget_kj"] = 0.0
	stored["deposited_heat_kj"] = 100000.0
	p = _valid(stored, _request(1.0, 0.1), m, "no borrowing combustion heat")
	_near(p.get("accepted_release_kg", -1), 0.0, "previous Q cannot fund release")
	_near(p.get("accepted_oxidation_kg", -1), 0.1, "previous vapour can burn")
	_near(p.get("candidate", {}).get("deposited_heat_kj", -1), 102000.0, "cumulative Q")
	stored["liquid_fuel_kg"] = 0.0
	p = _valid(stored, _request(100.0, 100.0), m, "no liquid")
	_near(p.get("accepted_release_kg", -1), 0.0, "liquid cap")
	_near(p.get("accepted_oxidation_kg", -1), 0.2, "vapour cap")
	var zero: Dictionary = _request(1.0, 1.0)
	zero["dt_s"] = 0.0
	p = _valid(s, zero, m, "zero timestep")
	_expect(p.get("candidate") == s, "zero step unchanged")
	# Requests are kg per step, not rates: changing positive dt alone does not scale them.
	var quick: Dictionary = _request(0.1, 0.1)
	quick["dt_s"] = 0.001
	_expect(_valid(s, quick, m, "dt scope") == _valid(s, _request(0.1, 0.1), m, "dt scope control"), "kg per STEP")
	var half: Dictionary = _valid(s, _request(0.05, 0.05), m, "subdivision first")
	var split: Dictionary = _valid(half.get("candidate", {}), _request(0.05, 0.05), m, "subdivision second")
	var full: Dictionary = _valid(s, _request(0.1, 0.1), m, "subdivision full")
	for key in s:
		_near(split.get("candidate", {}).get(key, -1), full.get("candidate", {}).get(key, -1), "subdivision " + key)
	# Restart from a deep copy gives the same result; output mutations cannot alias inputs.
	_expect(Budget.propose_phase_reference(half["candidate"].duplicate(true), _request(0.05, 0.05), m) == split, "restart")
	var immutable: Dictionary = s.duplicate(true)
	full["candidate"]["liquid_fuel_kg"] = 999.0
	_expect(s == immutable, "no output alias")
	var depleted: Dictionary = s.duplicate(true)
	depleted["thermal_budget_kj"] = 2000.0
	for step in range(12):
		var next: Dictionary = _valid(depleted, _request(0.1, 0.1), m, "depletion")
		depleted = next.get("candidate", {})
	_near(depleted.get("liquid_fuel_kg", -1), 0.0, "empty reservoir")
	_near(depleted.get("vapour_fuel_kg", -1), 0.0, "no tail")
	# Rejected demand is not queued for a later empty request.
	var limited: Dictionary = s.duplicate(true)
	limited["thermal_budget_kj"] = 50.0
	p = _valid(limited, _request(1.0, 1.0), m, "rejected demand")
	var no_queue: Dictionary = p.get("candidate", {}).duplicate(true)
	no_queue["thermal_budget_kj"] = 1000.0
	p = _valid(no_queue, _request(0.0, 0.0), m, "no queue")
	_near(p.get("accepted_release_kg", -1), 0.0, "no delayed request")
	for family in ["state", "request", "material"]:
		var template: Dictionary = s if family == "state" else (_request(0.1, 0.1) if family == "request" else m)
		for key in template:
			var missing: Dictionary = template.duplicate(true)
			missing.erase(key)
			_reject_family(family, missing, s, m, "missing " + key)
			if typeof(template[key]) in [TYPE_INT, TYPE_FLOAT]:
				for bad in [-1.0, NAN, INF, true, "1"]:
					var invalid: Dictionary = template.duplicate(true)
					invalid[key] = bad
					_reject_family(family, invalid, s, m, "invalid " + key)
		var extra: Dictionary = template.duplicate(true)
		extra["fuel_energy_MJ"] = 1.0
		_reject_family(family, extra, s, m, "legacy key")
		_reject_family(family, null, s, m, "not dictionary")
	for key in ["schema", "liquid_phase", "vapour_phase", "water_product_phase", "atom_mass_basis", "chemical_energy_basis", "provenance"]:
		var wrong: Dictionary = m.duplicate(true)
		wrong[key] = ""
		_reject_family("material", wrong, s, m, "incompatible " + key)
	for key in ["liquid_heat_kj_kg", "vapour_heat_kj_kg", "phase_enthalpy_kj_kg", "reference_temperature_k", "reference_pressure_pa"]:
		var wrong: Dictionary = m.duplicate(true)
		wrong[key] += 1.0
		_reject_family("material", wrong, s, m, "basis/Hess " + key)
		_reject(Budget.propose_phase_reference(s, _request(0.0, 0.0), wrong), "idle material contract " + key)
	var excess: Dictionary = s.duplicate(true)
	excess["vapour_fuel_kg"] = 0.1
	_reject_family("state", excess, s, m, "exceeds initial")
	var bad_cho: Dictionary = m.duplicate(true)
	bad_cho["mass_fractions"] = {"C": 0.0, "H": 0.0, "O": 1.0}
	_reject_family("material", bad_cho, s, m, "noncombustible CHO")
	bad_cho["mass_fractions"] = {"C": 0.75, "H": 0.25, "O": 0.01}
	_reject_family("material", bad_cho, s, m, "fraction sum")
	var overflow: Dictionary = s.duplicate(true)
	overflow["initial_fuel_mass_kg"] = 4.0e303
	overflow["liquid_fuel_kg"] = 4.0e303
	overflow["thermal_budget_kj"] = 8.0e307
	overflow["deposited_heat_kj"] = 8.0e307
	_reject(Budget.propose_phase_reference(overflow, _request(0.0, 0.0), m), "nonfinite TOTAL alone")
	# V1 must not silently reinterpret the v2 material/state.
	_reject(Budget.propose(s, _request(0.1, 0.1), m), "cross API rejected")
	print("G3_PHASE_REFERENCE_BUDGET " + JSON.stringify({"checks": _checks, "failures": _failures}))
	if _failed:
		quit(1)
		return
	print("G3_PHASE_REFERENCE_BUDGET_PASS")
	quit(0)


func _valid(s: Dictionary, r: Dictionary, m: Dictionary, label: String) -> Dictionary:
	var originals: Array = [s.duplicate(true), r.duplicate(true), m.duplicate(true)]
	var p: Dictionary = Budget.propose_phase_reference(s, r, m)
	_expect(s == originals[0] and r == originals[1] and m == originals[2], label + " immutable")
	_expect(p.get("valid", false), label + " valid " + str(p.get("errors")))
	if not p.get("valid", false):
		return p
	_near(p["total_after_kj"], p["total_before_kj"], label + " A+B+Q")
	_near(p["mass_residual_kg"], 0.0, label + " mass")
	for element in ["C", "H", "O"]:
		_near(p["element_residuals_kg"][element], 0.0, label + " element " + element)
	return p


func _reject_family(family: String, bad: Variant, s: Dictionary, m: Dictionary, label: String) -> void:
	var r: Dictionary = _request(0.1, 0.1)
	var original: String = JSON.stringify([s, r, m, bad])
	var p: Dictionary = Budget.propose_phase_reference(bad if family == "state" else s,
		bad if family == "request" else r, bad if family == "material" else m)
	_expect(original == JSON.stringify([s, r, m, bad]), label + " rejected immutable")
	_reject(p, label)


func _reject(p: Dictionary, label: String) -> void:
	_expect(not p.get("valid", true) and not p.get("errors", []).is_empty()
		and p.get("candidate", {"unexpected": true}).is_empty(), label + " fails closed")


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected)
		<= 1.0e-9 + 1.0e-12 * maxf(absf(actual), absf(expected)), label)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)


func _state() -> Dictionary:
	return {"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0, "vapour_fuel_kg": 0.0,
		"o2_kg": 10.0, "thermal_budget_kj": 1000.0, "deposited_heat_kj": 0.0}


func _request(release: float, oxidation: float) -> Dictionary:
	return {"dt_s": 1.0, "release_kg": release, "oxidation_kg": oxidation}


func _material() -> Dictionary:
	return {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid",
		"vapour_phase": "gas", "reference_temperature_k": 298.15, "reference_pressure_pa": 100000.0,
		"water_product_phase": "gas", "atom_mass_basis": "nominal_C12_H1_O16",
		"chemical_energy_basis": "complete_oxidation_net", "mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
		"liquid_heat_kj_kg": 19000.0, "vapour_heat_kj_kg": 20000.0,
		"phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic analytical control; not heptane"}
