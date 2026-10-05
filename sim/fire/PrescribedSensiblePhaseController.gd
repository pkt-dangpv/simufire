extends RefCounted

## Isolated, single-thread in-memory owner, NOT SimulationEngine integration.
## Versioned successor of the reference caller. It OWNS context, source
## progress, phases, accumulated thermal accounts, clocks and generation.
## The sensible state is never rebuilt from accumulated mass: two histories
## with equal mass may differ in heating, enthalpy and budget, so the thermal
## accounts are kept and only cross-checked. Closed synthetic B/O2 seed.
## No zone EOS, predicted evaporation, cooling or product authorization.
## Preview is pure; commit recomputes the intent and swaps ONE aggregate root.
const Release = preload("res://sim/fire/PrescribedFuelReleaseModel.gd")
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const VERSION: String = "prescribed_sensible_phase_controller_v1"
const CONTEXT_SCHEMA: String = "g3_prescribed_sensible_context_v1"
const SEED_SCHEMA: String = "g3_prescribed_sensible_seed_v1"
const REQUEST_SCHEMA: String = "g3_prescribed_sensible_request_v1"
const SNAPSHOT_SCHEMA: String = "g3_prescribed_sensible_snapshot_v1"
const PHASE_SCHEMA: String = "g3_phase_sensible_state_v1"
const BOUNDARY_KIND: String = "synthetic_independent_initial_budget"
const MAX_GENERATION: int = 9223372036854775807
const CONTEXT_KEYS: Array[String] = ["schema", "program", "material", "attribution", "seed"]
const PROGRAM_TEXT_KEYS: Array[String] = [
	"profile_id", "component_id", "mode", "quantity", "unit", "time_origin",
	"interpolation", "outside_domain",
]
const ATTRIBUTION_KEYS: Array[String] = [
	"input_component_id", "modeled_component_id", "input_quantity", "rule", "status", "provenance",
]
const SEED_KEYS: Array[String] = [
	"schema", "initial_o2_kg", "initial_thermal_budget_kj", "initial_liquid_sensible_kj",
	"energy_boundary_kind", "energy_boundary_provenance",
]
const REQUEST_KEYS: Array[String] = [
	"schema", "end_time_s", "oxidation_kg", "heat_liquid_kj", "heat_vapour_kj",
	"emitted_vapour_temperature_k",
]
const OWNED_KEYS: Array[String] = [
	"schema", "context_fingerprint", "generation", "physical_time_s", "progress", "phase", "totals",
]
const TOTAL_KEYS: Array[String] = [
	"oxidized_fuel_kg", "co2_kg", "water_vapour_kg", "o2_consumed_kg",
	"heating_liquid_kj", "heating_vapour_kj", "release_cost_kj",
	"released_liquid_sensible_kj", "emitted_vapour_sensible_kj",
	"oxidized_sensible_kj", "chemical_oxidation_heat_kj",
]
const SIGNED_TOTAL_KEYS: Array[String] = [
	"released_liquid_sensible_kj", "emitted_vapour_sensible_kj", "oxidized_sensible_kj",
]
var _context: Dictionary = {}
var _owned: Dictionary = {}


func initialize(context: Variant) -> Dictionary:
	if not _owned.is_empty():
		return _failure(["already initialized; use a new owner for another context"])
	var errors: Array[String] = []
	var c: Dictionary = _object(context, CONTEXT_KEYS, "context", errors)
	_literal(c.get("schema"), CONTEXT_SCHEMA, "context schema", errors)
	var program: Dictionary = _object(c.get("program"), Release.PROGRAM_KEYS, "program", errors)
	var material: Dictionary = _object(c.get("material"), Budget.SENSIBLE_MATERIAL_KEYS, "material", errors)
	var a: Dictionary = _object(c.get("attribution"), ATTRIBUTION_KEYS, "attribution", errors)
	var seed: Dictionary = _object(c.get("seed"), SEED_KEYS, "seed", errors)
	# Text is typed here first: the delegates compare these fields as strings.
	for key: String in PROGRAM_TEXT_KEYS:
		_text(program.get(key), "program." + key, errors)
	for key: String in ATTRIBUTION_KEYS:
		_text(a.get(key), "attribution." + key, errors)
	_text(material.get("component_id"), "material.component_id", errors)
	_literal(seed.get("schema"), SEED_SCHEMA, "seed schema", errors)
	_number(seed.get("initial_o2_kg"), false, "initial_o2_kg", errors)
	_number(seed.get("initial_thermal_budget_kj"), false, "initial_thermal_budget_kj", errors)
	_number(seed.get("initial_liquid_sensible_kj"), true, "initial_liquid_sensible_kj", errors)
	_literal(seed.get("energy_boundary_kind"), BOUNDARY_KIND, "initial energy boundary", errors)
	_text(seed.get("energy_boundary_provenance"), "energy_boundary_provenance", errors)
	if not errors.is_empty():
		return _failure(errors)
	if a["input_component_id"] != program["component_id"] or a["input_quantity"] != program["quantity"]:
		errors.append("attribution does not match input program")
	if program["quantity"] == "modeled_component_emission":
		if a["rule"] != "same_declared_component" or a["status"] != "synthetic_declared_emission" or a["modeled_component_id"] != a["input_component_id"]:
			errors.append("invalid declared component association")
	else:
		if a["rule"] != "all_depletion_as_reference_vapour" or a["status"] != "conditional_not_measured_emission" or a["modeled_component_id"] == a["input_component_id"]:
			errors.append("measured depletion requires explicit conditional, separate component")
	if a["modeled_component_id"] != material["component_id"]:
		errors.append("attribution does not model the declared material component")
	if not errors.is_empty():
		return _failure(errors)
	var canonical: Dictionary = _canonical(c)
	var initialized: Dictionary = Release.initial_progress(canonical["program"])
	if not initialized.get("valid", false):
		return _failure(["invalid release program: " + str(initialized.get("errors"))])
	var checked: Dictionary = Budget.propose_phase_sensible(_seed_phase(canonical), _idle(), canonical["material"])
	if not checked.get("valid", false):
		return _failure(["invalid sensible material/seed: " + str(checked.get("errors"))])
	var candidate: Dictionary = {
		"schema": SNAPSHOT_SCHEMA, "context_fingerprint": _fingerprint(canonical),
		"generation": 0, "physical_time_s": 0.0, "progress": initialized["candidate"].duplicate(true),
		"phase": checked["candidate"].duplicate(true), "totals": {},
	}
	for key: String in TOTAL_KEYS:
		candidate["totals"][key] = 0.0
	_check_owned(candidate, canonical, errors)
	if not errors.is_empty():
		return _failure(errors)
	_context = canonical
	_owned = candidate
	return _success({}, false)


func snapshot() -> Dictionary:
	return _owned.duplicate(true)


## Pure. The request is an intent with absolute physical end time; masses and
## heat are per STEP. A rejected ledger proposal rejects the whole transaction.
func preview_step(request: Variant) -> Dictionary:
	if _owned.is_empty():
		return _failure(["not initialized"])
	var errors: Array[String] = []
	_check_owned(_owned, _context, errors)
	var r: Dictionary = _object(request, REQUEST_KEYS, "request", errors)
	_literal(r.get("schema"), REQUEST_SCHEMA, "request schema", errors)
	var end: float = _number(r.get("end_time_s"), false, "end_time_s", errors)
	var oxidation: float = _number(r.get("oxidation_kg"), false, "oxidation_kg", errors)
	var heat_liquid: float = _number(r.get("heat_liquid_kj"), false, "heat_liquid_kj", errors)
	var heat_vapour: float = _number(r.get("heat_vapour_kj"), false, "heat_vapour_kj", errors)
	var emitted_k: float = _number(r.get("emitted_vapour_temperature_k"), false, "emitted_vapour_temperature_k", errors)
	if not errors.is_empty():
		return _failure(errors)
	if end < float(_owned["physical_time_s"]):
		return _failure(["physical time cannot go backwards"])
	var physical_dt: float = end - float(_owned["physical_time_s"])
	if physical_dt > 0.0 and int(_owned["generation"]) == MAX_GENERATION:
		return _failure(["generation overflow"])
	var source_end: float = minf(end, _domain_end(_context))
	var demand: Dictionary = Release.propose(_context["program"], _owned["progress"], source_end)
	if not demand.get("valid", false):
		return _failure(["source preview rejected: " + str(demand.get("errors"))])
	var before: Dictionary = _owned["phase"].duplicate(true)
	var ledger: Dictionary = Budget.propose_phase_sensible(before, {
		"dt_s": physical_dt, "release_kg": demand["release_kg"], "oxidation_kg": oxidation,
		"heat_liquid_kj": heat_liquid, "heat_vapour_kj": heat_vapour,
		"emitted_vapour_temperature_k": emitted_k,
	}, _context["material"])
	if not ledger.get("valid", false):
		return _failure(["sensible ledger rejected: " + str(ledger.get("errors"))])
	var progress: Dictionary = Release.acknowledge(_context["program"], _owned["progress"],
		source_end, ledger["accepted_release_kg"])
	if not progress.get("valid", false):
		return _failure(["source acknowledgement rejected: " + str(progress.get("errors"))])
	var after: Dictionary = ledger["candidate"]
	# The ledger accepts prescribed heat entirely or rejects; none at dt = 0.
	var heated_liquid: float = heat_liquid if physical_dt > 0.0 else 0.0
	var heated_vapour: float = heat_vapour if physical_dt > 0.0 else 0.0
	# Exact account differences of the canonical states; no second integral.
	var released_sensible: float = float(before["liquid_sensible_kj"]) + heated_liquid - float(after["liquid_sensible_kj"])
	var emitted_sensible: float = float(after["vapour_sensible_kj"]) + float(ledger["oxidized_sensible_kj"]) - (float(before["vapour_sensible_kj"]) + heated_vapour)
	var step: Dictionary = {
		"physical_dt_s": physical_dt, "source_dt_s": demand["dt_s"],
		"requested_release_kg": demand["release_kg"], "accepted_release_kg": ledger["accepted_release_kg"],
		"rejected_release_kg": ledger["rejected_release_kg"], "requested_oxidation_kg": oxidation,
		"accepted_oxidation_kg": ledger["accepted_oxidation_kg"], "rejected_oxidation_kg": ledger["rejected_oxidation_kg"],
		"heating_liquid_kj": heated_liquid, "heating_vapour_kj": heated_vapour,
		"release_cost_kj": ledger["release_cost_kj"], "release_cost_kj_kg": ledger["release_cost_kj_kg"],
		"release_budget_deficit_kj": ledger["release_budget_deficit_kj"],
		"released_liquid_sensible_kj": released_sensible, "emitted_vapour_sensible_kj": emitted_sensible,
		"oxidized_sensible_kj": ledger["oxidized_sensible_kj"],
		"chemical_oxidation_heat_kj": ledger["chemical_oxidation_heat_kj"],
		"deposited_increment_kj": ledger["deposited_increment_kj"], "o2_consumed_kg": ledger["o2_consumed_kg"],
		"co2_kg": ledger["products_kg"]["co2"], "water_vapour_kg": ledger["products_kg"]["water_vapour"],
	}
	var candidate: Dictionary = _owned.duplicate(true)
	candidate["physical_time_s"] = end
	candidate["generation"] = int(_owned["generation"]) + (1 if physical_dt > 0.0 else 0)
	candidate["progress"] = progress["candidate"].duplicate(true)
	candidate["phase"] = after.duplicate(true)
	var totals: Dictionary = candidate["totals"]
	totals["oxidized_fuel_kg"] += float(step["accepted_oxidation_kg"])
	for key: String in ["co2_kg", "water_vapour_kg", "o2_consumed_kg", "heating_liquid_kj",
		"heating_vapour_kj", "release_cost_kj", "released_liquid_sensible_kj",
		"emitted_vapour_sensible_kj", "oxidized_sensible_kj", "chemical_oxidation_heat_kj"]:
		totals[key] += float(step[key])
	_check_owned(candidate, _context, errors)
	if not errors.is_empty():
		return _failure(errors)
	return {"valid": true, "errors": [], "candidate": candidate, "step": step, "report": _report()}


## Takes the intent and the expected generation, never an external candidate.
func commit_step(request: Variant, expected_generation: Variant) -> Dictionary:
	if not _generation_matches(expected_generation):
		return _failure(["generation conflict or uninitialized owner"])
	var proposal: Dictionary = preview_step(request)
	if not proposal["valid"]:
		return proposal
	var no_op: bool = proposal["step"]["physical_dt_s"] == 0.0
	if not no_op:
		_owned = proposal["candidate"].duplicate(true)
	return _success(proposal["step"], no_op)


## Complete, context-bound restore with a NEW generation. A coherent snapshot
## is accepted; this is a coherency check, not a proof of the saved history.
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
	_owned = candidate
	return _success({}, false)


## Returns the canonical dt = 0 audit of the phase state, or {} when invalid.
func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> Dictionary:
	var before: int = errors.size()
	var s: Dictionary = _object(value, OWNED_KEYS, "snapshot", errors)
	_literal(s.get("schema"), SNAPSHOT_SCHEMA, "snapshot schema", errors)
	_literal(s.get("context_fingerprint"), _fingerprint(context), "snapshot/context identity", errors)
	if not _valid_generation(s.get("generation")):
		errors.append("invalid generation")
	var physical_time: float = _number(s.get("physical_time_s"), false, "physical_time_s", errors)
	var phase: Dictionary = _object(s.get("phase"), Budget.SENSIBLE_STATE_KEYS, "phase", errors)
	var totals: Dictionary = _object(s.get("totals"), TOTAL_KEYS, "totals", errors)
	var progress: Dictionary = _object(s.get("progress"), Release.PROGRESS_KEYS, "progress", errors)
	_text(progress.get("fingerprint"), "progress.fingerprint", errors)
	var t: Dictionary = {}
	for key: String in TOTAL_KEYS:
		t[key] = _number(totals.get(key), key in SIGNED_TOTAL_KEYS, "totals." + key, errors)
	if errors.size() != before:
		return {}
	var source: Dictionary = Release.propose(context["program"], progress, progress["time_s"])
	if not source.get("valid", false):
		errors.append("invalid source progress")
		return {}
	if float(progress["time_s"]) != minf(physical_time, _domain_end(context)):
		errors.append("physical/source clocks disagree")
	var material: Dictionary = context["material"]
	var audit: Dictionary = Budget.propose_phase_sensible(phase, _idle(), material)
	var origin: Dictionary = Budget.propose_phase_sensible(_seed_phase(context), _idle(), material)
	if not audit.get("valid", false) or not origin.get("valid", false):
		errors.append("invalid sensible phase state: " + str(audit.get("errors")))
		return {}
	var seed: Dictionary = context["seed"]
	var mass: float = float(context["program"]["initial_mass_kg"])
	var accepted: float = float(progress["accepted_kg"])
	# Canonical chemistry of the accumulated oxidized mass; no second stoichiometry.
	var chemistry: Dictionary = Budget.propose_phase_reference({
		"initial_fuel_mass_kg": mass, "liquid_fuel_kg": 0.0, "vapour_fuel_kg": t["oxidized_fuel_kg"],
		"o2_kg": seed["initial_o2_kg"], "thermal_budget_kj": 0.0, "deposited_heat_kj": 0.0,
	}, {"dt_s": 1.0, "release_kg": 0.0, "oxidation_kg": t["oxidized_fuel_kg"]}, material["reference_material"])
	if not chemistry.get("valid", false):
		errors.append("invalid canonical oxidation recomposition")
		return {}
	_compare(t["oxidized_fuel_kg"], chemistry["accepted_oxidation_kg"], false, "oxidation history", errors)
	_compare(t["co2_kg"], chemistry["products_kg"]["co2"], false, "cumulative CO2", errors)
	_compare(t["water_vapour_kg"], chemistry["products_kg"]["water_vapour"], false, "cumulative water", errors)
	_compare(t["o2_consumed_kg"], chemistry["o2_consumed_kg"], false, "cumulative O2", errors)
	_compare(t["chemical_oxidation_heat_kj"], chemistry["oxidation_heat_kj"], true, "chemical heat history", errors)
	if float(phase["initial_fuel_mass_kg"]) != mass:
		errors.append("phase initial mass is not the program initial mass")
	_compare(float(phase["liquid_fuel_kg"]) + accepted, mass, false, "liquid/accepted mass", errors)
	_compare(float(phase["vapour_fuel_kg"]) + t["oxidized_fuel_kg"], accepted, false, "vapour/oxidized mass", errors)
	_compare(float(phase["o2_kg"]) + t["o2_consumed_kg"], seed["initial_o2_kg"], false, "oxygen history", errors)
	# Thermal history is owned, not derived: sums against the seed, per account.
	_compare(float(phase["thermal_budget_kj"]) + t["heating_liquid_kj"] + t["heating_vapour_kj"] + t["release_cost_kj"],
		seed["initial_thermal_budget_kj"], true, "B history", errors)
	_compare(float(phase["liquid_sensible_kj"]) + t["released_liquid_sensible_kj"],
		float(seed["initial_liquid_sensible_kj"]) + t["heating_liquid_kj"], true, "liquid sensible history", errors)
	_compare(float(phase["vapour_sensible_kj"]) + t["oxidized_sensible_kj"],
		t["heating_vapour_kj"] + t["emitted_vapour_sensible_kj"], true, "vapour sensible history", errors)
	_compare(float(phase["deposited_heat_kj"]), t["chemical_oxidation_heat_kj"] + t["oxidized_sensible_kj"], true, "Q history", errors)
	_compare(t["release_cost_kj"] + t["released_liquid_sensible_kj"],
		accepted * float(material["reference_material"]["phase_enthalpy_kj_kg"]) + t["emitted_vapour_sensible_kj"],
		true, "release cost history", errors)
	_compare(audit["total_before_kj"], origin["total_before_kj"], true, "aggregate A+S+B+Q", errors)
	return audit if errors.size() == before else {}


func _report() -> Dictionary:
	var result: Dictionary = {
		"scope": "isolated_synthetic_sensible_owner_not_evaporation_prediction_or_EOS",
		"controller_version": VERSION, "initialized": not _owned.is_empty(),
		"fingerprint_scope": "context_content_binding_not_signature_or_history_proof",
		"scientific_approval": false, "predictive_evaporation_approval": false,
		"engine_integration": false, "production_activation": false,
	}
	if not _owned.is_empty():
		result["confirmed"] = snapshot()
		result["source_finished"] = float(_owned["physical_time_s"]) >= _domain_end(_context)
		result["attribution"] = _context["attribution"].duplicate(true)
		result["energy_boundary_kind"] = _context["seed"]["energy_boundary_kind"]
		result["accounts"] = _accounts()
	return result


## A, S and the total come from the ledger audit; Q is not chemical heat.
func _accounts() -> Dictionary:
	var audit: Dictionary = Budget.propose_phase_sensible(_owned["phase"], _idle(), _context["material"])
	if not audit.get("valid", false):
		return {}
	return {
		"potential_a_kj": audit["potential_before_kj"], "sensible_s_kj": audit["sensible_before_kj"],
		"budget_b_kj": _owned["phase"]["thermal_budget_kj"], "deposited_q_kj": _owned["phase"]["deposited_heat_kj"],
		"total_kj": audit["total_before_kj"],
		"chemical_oxidation_heat_kj": _owned["totals"]["chemical_oxidation_heat_kj"],
		"oxidized_sensible_kj": _owned["totals"]["oxidized_sensible_kj"],
	}


func _success(step: Dictionary, no_op: bool) -> Dictionary:
	return {"valid": true, "errors": [], "snapshot": snapshot(), "step": step.duplicate(true),
		"report": _report(), "no_op": no_op}


func _failure(errors: Array[String]) -> Dictionary:
	return {"valid": false, "errors": errors.duplicate(), "candidate": {}, "snapshot": snapshot(), "report": _report()}


func _generation_matches(value: Variant) -> bool:
	return not _owned.is_empty() and _valid_generation(value) and value == _owned["generation"]


static func _valid_generation(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


## Binds the full context CONTENT to this owner version. Not a signature:
## anyone can recompute it, and it proves nothing about a saved history.
static func _fingerprint(context: Dictionary) -> String:
	return (VERSION + _serialize(context)).sha256_text()


## Sorted keys, ordered arrays, quoted text and exact IEEE-754 bits per number.
static func _serialize(value: Variant) -> String:
	var parts: PackedStringArray = PackedStringArray()
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			for key: Variant in keys:
				parts.append(JSON.stringify(str(key)) + ":" + _serialize(value[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			for item: Variant in value:
				parts.append(_serialize(item))
			return "[" + ",".join(parts) + "]"
		TYPE_INT, TYPE_FLOAT:
			var number: float = float(value)
			if number == 0.0:
				number = absf(number)
			return "f64:" + PackedFloat64Array([number]).to_byte_array().hex_encode()
		TYPE_STRING:
			return JSON.stringify(value)
	return "unsupported:" + str(typeof(value))


## Deep copy with every number as a 64-bit float, as the physics reads them.
static func _canonical(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value:
				result[key] = _canonical(value[key])
			return result
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_canonical(item))
			return items
		TYPE_INT:
			return float(value)
	return value


static func _seed_phase(context: Dictionary) -> Dictionary:
	var mass: float = float(context["program"]["initial_mass_kg"])
	return {"schema": PHASE_SCHEMA, "component_id": context["material"]["component_id"],
		"initial_fuel_mass_kg": mass, "liquid_fuel_kg": mass, "vapour_fuel_kg": 0.0,
		"o2_kg": float(context["seed"]["initial_o2_kg"]),
		"thermal_budget_kj": float(context["seed"]["initial_thermal_budget_kj"]), "deposited_heat_kj": 0.0,
		"liquid_sensible_kj": float(context["seed"]["initial_liquid_sensible_kj"]), "vapour_sensible_kj": 0.0}


## dt = 0 audit request at the reference temperature exposed by the ledger.
static func _idle() -> Dictionary:
	return {"dt_s": 0.0, "release_kg": 0.0, "oxidation_kg": 0.0, "heat_liquid_kj": 0.0,
		"heat_vapour_kj": 0.0, "emitted_vapour_temperature_k": Budget.SensibleProperties.REFERENCE_K}


static func _domain_end(context: Dictionary) -> float:
	return float(context["program"]["samples"][-1]["time_s"])


static func _object(value: Variant, keys: Array[String], label: String, errors: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(label + " must be a dictionary")
		return {}
	if value.size() != keys.size():
		errors.append(label + " missing/extra fields")
	for key: String in keys:
		if not value.has(key):
			errors.append(label + " missing " + key)
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append(label + " unsupported key")
	return value


static func _number(value: Variant, signed: bool, label: String, errors: Array[String]) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append(label + " must be a finite number, never bool or text")
		return 0.0
	var number: float = float(value)
	if not _finite(number) or (not signed and number < 0.0):
		errors.append(label + " must be finite" + ("" if signed else " and nonnegative"))
		return 0.0
	return number


static func _text(value: Variant, label: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		errors.append(label + " must be nonempty text")


## Type first: comparing a number with a String is a script error in Godot.
static func _literal(value: Variant, expected: String, label: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or value != expected:
		errors.append("incompatible " + label)


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _compare(a: float, b: float, energy: bool, label: String, errors: Array[String]) -> void:
	var absolute: float = Budget.ENERGY_ABS_TOL_KJ if energy else Budget.MASS_ABS_TOL_KG
	if not _finite(a) or not _finite(b) or absf(a - b) > absolute + Budget.REL_TOL * maxf(absf(a), absf(b)):
		errors.append(label + " does not close")
