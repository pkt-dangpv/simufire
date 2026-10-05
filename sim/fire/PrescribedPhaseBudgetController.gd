extends RefCounted

## Isolated, single-thread in-memory owner, NOT SimulationEngine integration.
## Closed initial B/O2 only. Reference phases, no sensible energy or feedback.
## Preview is pure; commit recomputes intent and swaps ONE aggregate root.
const Release = preload("res://sim/fire/PrescribedFuelReleaseModel.gd")
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const VERSION: String = "prescribed_phase_controller_v1"
const MAX_GENERATION: int = 9223372036854775807
const CONTEXT_KEYS: Array[String] = ["schema", "program", "material", "attribution", "seed"]
const ATTRIBUTION_KEYS: Array[String] = [
	"input_component_id", "modeled_component_id", "input_quantity", "rule", "status", "provenance",
]
const SEED_KEYS: Array[String] = [
	"initial_o2_kg", "initial_thermal_budget_kj", "energy_boundary_kind", "energy_boundary_provenance",
]
const OWNED_KEYS: Array[String] = [
	"schema", "context_fingerprint", "generation", "physical_time_s", "progress", "phase", "totals",
]
const TOTAL_KEYS: Array[String] = ["oxidized_fuel_kg", "co2_kg", "water_vapour_kg"]
var _context: Dictionary = {}
var _owned: Dictionary = {}


func initialize(context: Variant) -> Dictionary:
	if not _owned.is_empty():
		return _failure(["already initialized; use a new owner for another context"])
	var errors: Array[String] = []
	var c: Dictionary = _object(context, CONTEXT_KEYS, "context", errors)
	if typeof(c.get("schema")) not in [TYPE_STRING, TYPE_STRING_NAME] or c.get("schema") != "g3_prescribed_phase_context_v1":
		errors.append("incompatible context schema")
	var a: Dictionary = _object(c.get("attribution"), ATTRIBUTION_KEYS, "attribution", errors)
	var seed: Dictionary = _object(c.get("seed"), SEED_KEYS, "seed", errors)
	for key in ATTRIBUTION_KEYS:
		_text(a.get(key), "attribution." + key, errors)
	_number(seed.get("initial_o2_kg"), "initial_o2_kg", errors)
	_number(seed.get("initial_thermal_budget_kj"), "initial_thermal_budget_kj", errors)
	_text(seed.get("energy_boundary_provenance"), "energy_boundary_provenance", errors)
	if seed.get("energy_boundary_kind") not in ["synthetic_independent_initial_budget", "declared_conditional_initial_budget"]:
		errors.append("unsupported initial energy boundary")
	var initialized: Dictionary = Release.initial_progress(c.get("program"))
	if not initialized.get("valid", false):
		errors.append("invalid release program: " + str(initialized.get("errors")))
	if not errors.is_empty():
		return _failure(errors)
	var program: Dictionary = c["program"]
	if a["input_component_id"] != program["component_id"] or a["input_quantity"] != program["quantity"]:
		errors.append("attribution does not match input program")
	if program["quantity"] == "modeled_component_emission":
		if a["rule"] != "same_declared_component" or a["status"] != "synthetic_declared_emission" or a["modeled_component_id"] != a["input_component_id"]:
			errors.append("invalid declared component association")
	else:
		if a["rule"] != "all_depletion_as_reference_vapour" or a["status"] != "conditional_not_measured_emission" or a["modeled_component_id"] == a["input_component_id"]:
			errors.append("measured depletion requires explicit conditional, separate component")
	if not errors.is_empty():
		return _failure(errors)
	var checked: Dictionary = Budget.propose_phase_reference(_seed_phase(c), _request(0.0, 0.0, 0.0), c.get("material"))
	if not checked.get("valid", false):
		return _failure(["invalid reference material/seed: " + str(checked.get("errors"))])
	var candidate: Dictionary = {
		"schema": "g3_prescribed_phase_snapshot_v1", "context_fingerprint": _fingerprint(c),
		"generation": 0, "physical_time_s": 0.0, "progress": initialized["candidate"].duplicate(true),
		"phase": checked["candidate"].duplicate(true),
		"totals": {"oxidized_fuel_kg": 0.0, "co2_kg": 0.0, "water_vapour_kg": 0.0},
	}
	_check_owned(candidate, c, errors)
	if not errors.is_empty():
		return _failure(errors)
	_context = c.duplicate(true)
	_owned = candidate.duplicate(true)
	return _success({}, false)


func snapshot() -> Dictionary:
	return _owned.duplicate(true)


func preview_step(end_time_s: Variant, oxidation_requested_kg: Variant) -> Dictionary:
	var errors: Array[String] = []
	if _owned.is_empty():
		return _failure(["not initialized"])
	_check_owned(_owned, _context, errors)
	var end: float = _number(end_time_s, "end_time_s", errors)
	var oxidation: float = _number(oxidation_requested_kg, "oxidation_requested_kg", errors)
	if end < float(_owned["physical_time_s"]):
		errors.append("physical time cannot go backwards")
	if not errors.is_empty():
		return _failure(errors)
	var physical_dt: float = end - float(_owned["physical_time_s"])
	if physical_dt > 0.0 and int(_owned["generation"]) == MAX_GENERATION:
		return _failure(["generation overflow"])
	var source_end: float = minf(end, _domain_end(_context))
	var demand: Dictionary = Release.propose(_context["program"], _owned["progress"], source_end)
	if not demand.get("valid", false):
		return _failure(["source preview rejected: " + str(demand.get("errors"))])
	var phase_input: Dictionary = _owned["phase"].duplicate(true)
	var phase: Dictionary = Budget.propose_phase_reference(phase_input,
		_request(physical_dt, demand["release_kg"], oxidation), _context["material"])
	if not phase.get("valid", false):
		return _failure(["phase preview rejected: " + str(phase.get("errors"))])
	var progress: Dictionary = Release.acknowledge(_context["program"], _owned["progress"],
		source_end, phase["accepted_release_kg"])
	if not progress.get("valid", false):
		return _failure(["source acknowledgement rejected: " + str(progress.get("errors"))])
	var candidate: Dictionary = _owned.duplicate(true)
	candidate["physical_time_s"] = end
	candidate["generation"] = int(_owned["generation"]) + (1 if physical_dt > 0.0 else 0)
	candidate["progress"] = progress["candidate"].duplicate(true)
	candidate["phase"] = phase["candidate"].duplicate(true)
	candidate["totals"]["oxidized_fuel_kg"] += float(phase["accepted_oxidation_kg"])
	candidate["totals"]["co2_kg"] += float(phase["products_kg"]["co2"])
	candidate["totals"]["water_vapour_kg"] += float(phase["products_kg"]["water_vapour"])
	_check_owned(candidate, _context, errors)
	if not errors.is_empty():
		return _failure(errors)
	return {"valid": true, "errors": [], "candidate": candidate.duplicate(true), "step": {
		"physical_dt_s": physical_dt, "source_dt_s": demand["dt_s"],
		"requested_release_kg": demand["release_kg"], "accepted_release_kg": phase["accepted_release_kg"],
		"rejected_release_kg": phase["rejected_release_kg"], "requested_oxidation_kg": oxidation,
		"accepted_oxidation_kg": phase["accepted_oxidation_kg"], "rejected_oxidation_kg": phase["rejected_oxidation_kg"],
		"phase_cost_kj": phase["phase_cost_kj"], "oxidation_heat_kj": phase["oxidation_heat_kj"],
	}, "report": _report()}


func commit_step(end_time_s: Variant, oxidation_requested_kg: Variant, expected_generation: Variant) -> Dictionary:
	if not _generation_matches(expected_generation):
		return _failure(["generation conflict or uninitialized owner"])
	var proposal: Dictionary = preview_step(end_time_s, oxidation_requested_kg)
	if not proposal["valid"]:
		return proposal
	var no_op: bool = proposal["step"]["physical_dt_s"] == 0.0
	if not no_op:
		_owned = proposal["candidate"].duplicate(true)
	return _success(proposal["step"], no_op)


func restore(saved: Variant, expected_generation: Variant) -> Dictionary:
	if not _generation_matches(expected_generation):
		return _failure(["generation conflict or uninitialized owner"])
	if int(_owned["generation"]) == MAX_GENERATION:
		return _failure(["generation overflow"])
	var errors: Array[String] = []
	_check_owned(_owned, _context, errors)
	_check_owned(saved, _context, errors)
	if not errors.is_empty():
		return _failure(errors)
	var candidate: Dictionary = saved.duplicate(true)
	candidate["generation"] = int(_owned["generation"]) + 1
	_owned = candidate.duplicate(true)
	return _success({}, false)


func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> void:
	var s: Dictionary = _object(value, OWNED_KEYS, "snapshot", errors)
	# Type first: an aborted check would add no error and let the snapshot through.
	var textual: bool = typeof(s.get("schema")) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(s.get("context_fingerprint")) in [TYPE_STRING, TYPE_STRING_NAME]
	if not textual or s.get("schema") != "g3_prescribed_phase_snapshot_v1" or s.get("context_fingerprint") != _fingerprint(context):
		errors.append("snapshot/context identity mismatch")
	if not _valid_generation(s.get("generation")):
		errors.append("invalid generation")
	var physical_time: float = _number(s.get("physical_time_s"), "physical_time_s", errors)
	var phase: Dictionary = _object(s.get("phase"), Budget.PHASE_STATE_KEYS, "phase", errors)
	var totals: Dictionary = _object(s.get("totals"), TOTAL_KEYS, "totals", errors)
	for key in Budget.PHASE_STATE_KEYS:
		_number(phase.get(key), "phase." + key, errors)
	for key in TOTAL_KEYS:
		_number(totals.get(key), "totals." + key, errors)
	var progress: Dictionary = _object(s.get("progress"), Release.PROGRESS_KEYS, "progress", errors)
	if not errors.is_empty():
		return
	var source: Dictionary = Release.propose(context["program"], progress, progress["time_s"])
	if not source.get("valid", false):
		errors.append("invalid source progress")
		return
	if float(progress["time_s"]) != minf(physical_time, _domain_end(context)):
		errors.append("physical/source clocks disagree")
	var recomposed_release: Dictionary = Budget.propose_phase_reference(_seed_phase(context),
		_request(1.0, progress["accepted_kg"], 0.0), context["material"])
	if not recomposed_release.get("valid", false):
		errors.append("invalid canonical release recomposition")
		return
	var recomposed: Dictionary = Budget.propose_phase_reference(recomposed_release["candidate"],
		_request(1.0, 0.0, totals["oxidized_fuel_kg"]), context["material"])
	if not recomposed.get("valid", false):
		errors.append("invalid canonical oxidation recomposition")
		return
	_compare(progress["accepted_kg"], recomposed_release["accepted_release_kg"], false, "release history", errors)
	_compare(totals["oxidized_fuel_kg"], recomposed["accepted_oxidation_kg"], false, "oxidation history", errors)
	for key in Budget.PHASE_STATE_KEYS:
		_compare(phase[key], recomposed["candidate"][key], key.ends_with("_kj"), "phase/history " + key, errors)
	_compare(totals["co2_kg"], recomposed["products_kg"]["co2"], false, "cumulative CO2", errors)
	_compare(totals["water_vapour_kg"], recomposed["products_kg"]["water_vapour"], false, "cumulative water", errors)
	var mass_before: float = float(context["program"]["initial_mass_kg"]) + float(context["seed"]["initial_o2_kg"])
	var mass_after: float = float(phase["liquid_fuel_kg"]) + float(phase["vapour_fuel_kg"]) + float(phase["o2_kg"]) + float(totals["co2_kg"]) + float(totals["water_vapour_kg"])
	_compare(mass_before, mass_after, false, "aggregate mass", errors)
	var material: Dictionary = context["material"]
	var initial_total: float = float(context["program"]["initial_mass_kg"]) * float(material["liquid_heat_kj_kg"]) + float(context["seed"]["initial_thermal_budget_kj"])
	var final_total: float = float(phase["liquid_fuel_kg"]) * float(material["liquid_heat_kj_kg"]) + float(phase["vapour_fuel_kg"]) * float(material["vapour_heat_kj_kg"]) + float(phase["thermal_budget_kj"]) + float(phase["deposited_heat_kj"])
	_compare(initial_total, final_total, true, "aggregate A+B+Q", errors)


func _report() -> Dictionary:
	var result: Dictionary = {
		"scope": "isolated_closed_reference_ledger_not_evaporation_prediction",
		"initialized": not _owned.is_empty(), "scientific_approval": false,
		"predictive_evaporation_approval": false, "engine_integration": false, "production_activation": false,
	}
	if not _owned.is_empty():
		result["confirmed"] = snapshot()
		result["source_finished"] = float(_owned["physical_time_s"]) >= _domain_end(_context)
		result["attribution"] = _context["attribution"].duplicate(true)
		result["energy_boundary_kind"] = _context["seed"]["energy_boundary_kind"]
	return result


func _success(step: Dictionary, no_op: bool) -> Dictionary:
	return {"valid": true, "errors": [], "snapshot": snapshot(), "step": step.duplicate(true),
		"report": _report(), "no_op": no_op}


func _failure(errors: Array[String]) -> Dictionary:
	return {"valid": false, "errors": errors.duplicate(), "candidate": {}, "snapshot": snapshot(), "report": _report()}


func _generation_matches(value: Variant) -> bool:
	return not _owned.is_empty() and _valid_generation(value) and value == _owned["generation"]


static func _valid_generation(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


static func _fingerprint(context: Dictionary) -> String:
	return (VERSION + JSON.stringify(context, "", true, true)).sha256_text()


static func _seed_phase(context: Dictionary) -> Dictionary:
	return {"initial_fuel_mass_kg": float(context["program"]["initial_mass_kg"]),
		"liquid_fuel_kg": float(context["program"]["initial_mass_kg"]), "vapour_fuel_kg": 0.0,
		"o2_kg": float(context["seed"]["initial_o2_kg"]),
		"thermal_budget_kj": float(context["seed"]["initial_thermal_budget_kj"]), "deposited_heat_kj": 0.0}


static func _request(dt: float, release: float, oxidation: float) -> Dictionary:
	return {"dt_s": dt, "release_kg": release, "oxidation_kg": oxidation}


static func _domain_end(context: Dictionary) -> float:
	return float(context["program"]["samples"][-1]["time_s"])


static func _object(value: Variant, keys: Array[String], label: String, errors: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(label + " must be a dictionary")
		return {}
	if value.size() != keys.size():
		errors.append(label + " missing/extra fields")
	for key in keys:
		if not value.has(key):
			errors.append(label + " missing " + key)
	for key in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append(label + " unsupported key")
	return value


static func _number(value: Variant, label: String, errors: Array[String]) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append(label + " must be a finite nonnegative number")
		return 0.0
	var number: float = float(value)
	if not _finite(number) or number < 0.0:
		errors.append(label + " must be a finite nonnegative number")
		return 0.0
	return number


static func _text(value: Variant, label: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		errors.append(label + " must be nonempty text")


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _compare(a: float, b: float, energy: bool, label: String, errors: Array[String]) -> void:
	var absolute: float = Budget.ENERGY_ABS_TOL_KJ if energy else Budget.MASS_ABS_TOL_KG
	if not _finite(a) or not _finite(b) or absf(a - b) > absolute + Budget.REL_TOL * maxf(absf(a), absf(b)):
		errors.append(label + " does not close")
