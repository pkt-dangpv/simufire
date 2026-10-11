extends SceneTree

## Real isolated sensible owner. Synthetic algebra only; expected numbers are
## predeclared in tests/test_g3_sensible_phase_controller.py, not taken from
## the owner. A failed check is recorded and the run continues without
## turning a broken mutant into an unrelated script error.
const Controller = preload("res://sim/fire/PrescribedSensiblePhaseController.gd")
const APPROVALS: Array[String] = ["scientific_approval", "predictive_evaporation_approval",
	"engine_integration", "production_activation"]
const NUMERIC_PHASE: Array[String] = ["initial_fuel_mass_kg", "liquid_fuel_kg", "vapour_fuel_kg",
	"o2_kg", "thermal_budget_kj", "deposited_heat_kj", "liquid_sensible_kj", "vapour_sensible_kj"]
## Predeclared pins; the Python contract test checks they equal its own table.
const EXPECTED: Dictionary = {
	"hot1_liquid": 0.9, "hot1_vapour": 0.1, "hot1_budget": 872.0, "hot1_sl": 18.0, "hot1_sv": 10.0,
	"hot1_cost": 108.0, "hot2_liquid": 0.8, "hot2_vapour": 0.15, "hot2_o2": 9.8, "hot2_co2": 0.1375,
	"hot2_water": 0.1125, "hot2_budget": 764.0, "hot2_q": 1005.0, "hot2_sl": 16.0, "hot2_sv": 15.0,
	"hot2_heating_l": 20.0, "hot2_heating_v": 5.0, "hot2_cost": 211.0, "hot2_emitted": 15.0,
	"hot2_released": 4.0, "hot2_oxidized_sensible": 5.0, "hot2_chemical": 1000.0,
	"hot2_total": 20000.0, "ref2_liquid": 0.8, "ref2_vapour": 0.15, "ref2_o2": 9.8,
	"ref2_co2": 0.1375, "ref2_water": 0.1125, "ref2_budget": 800.0, "ref2_q": 1000.0, "ref2_sl": 0.0,
	"ref2_sv": 0.0, "ref2_cost": 200.0, "ref2_total": 20000.0, "hot3_q": 4020.0, "hot3_budget": 764.0,
	"hot3_sl": 16.0, "hot3_sv": 0.0, "ref3_q": 4000.0, "ref3_budget": 800.0, "ref3_sl": 0.0,
	"ref3_sv": 0.0, "first_liquid": 0.8, "first_heating_l": 20.0, "first_sl": 16.0,
	"first_budget": 784.0, "first_cost": 196.0, "first_released": 4.0, "later_liquid": 0.8,
	"later_heating_l": 20.0, "later_sl": 160.0 / 9.0, "later_budget": 7040.0 / 9.0,
	"later_cost": 1780.0 / 9.0, "later_released": 20.0 / 9.0, "cold_cost": 102.5,
	"cold_budget": 897.5, "cold_sl": -45.0, "cold_sv": 0.0, "cold_q": 1997.5,
	"cold_oxidized_sensible": -2.5, "cold_released": -5.0, "cold_emitted": -2.5,
	"cold_total": 19950.0, "cap_accepted": 0.05, "cap_rejected": 0.05, "cap_deficit": 54.0,
	"cap_budget": 0.0, "cap_sl": 19.0, "cap_q": 1005.0, "cap_total": 19074.0,
	"cap_next_accepted": 0.0, "cap_rejected_total": 0.15, "o2_oxidized": 0.05, "o2_vapour": 0.05,
	"o2_left": 0.0, "exh_liquid": 0.0, "exh_sl": 0.0, "exh_budget": 808.0, "exh_released": 8.0,
	"exh_total": 4808.0, "exh_heated_sv": 10.0, "exh_heated_budget": 798.0, "cross_demand": 0.05,
	"cross_physical_dt": 1.0, "cross_source_dt": 0.5, "cross_cursor": 2.0, "cross_time": 2.5,
}
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: Array[String] = []
var _observations: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _profile(phase: String, cp: float) -> Dictionary:
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_CHO",
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration",
		"provenance": "synthetic: constant Cp owner oracle", "samples": [
			{"temperature_k": 273.15, "cp_kj_kg_k": cp},
			{"temperature_k": 498.15, "cp_kj_kg_k": cp}]}


func _context(budget: float = 1000.0, oxygen: float = 10.0, liquid_sensible: float = 0.0,
	mass: float = 1.0, linear: bool = false) -> Dictionary:
	var id: String = "synthetic_CHO" if linear else "synthetic_observed_reservoir"
	return {
		"schema": "g3_prescribed_sensible_context_v1",
		"program": {"profile_id": "synthetic_constant", "component_id": id, "initial_mass_kg": mass,
			"mode": "prescribed", "quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
			"unit": "kg/s", "time_origin": "synthetic_zero", "outside_domain": "reject",
			"interpolation": "piecewise_linear" if linear else "piecewise_constant_left",
			"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.0}]},
		"material": {"schema": "g3_phase_sensible_material_v1", "component_id": "synthetic_CHO",
			"liquid_profile": _profile("liquid", 2.0), "vapour_profile": _profile("gas", 1.0),
			"reference_material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid",
				"vapour_phase": "gas", "water_product_phase": "gas", "atom_mass_basis": "nominal_C12_H1_O16",
				"chemical_energy_basis": "complete_oxidation_net", "reference_temperature_k": 298.15,
				"reference_pressure_pa": 100000.0, "mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
				"liquid_heat_kj_kg": 19000.0, "vapour_heat_kj_kg": 20000.0,
				"phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic: CHO owner, not a measured fuel"}},
		"attribution": {"input_component_id": id, "modeled_component_id": "synthetic_CHO",
			"input_quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
			"rule": "same_declared_component" if linear else "all_depletion_as_reference_vapour",
			"status": "synthetic_declared_emission" if linear else "conditional_not_measured_emission",
			"provenance": "synthetic:no_experimental_approval"},
		"seed": {"schema": "g3_prescribed_sensible_seed_v1", "initial_o2_kg": oxygen,
			"initial_thermal_budget_kj": budget, "initial_liquid_sensible_kj": liquid_sensible,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"},
	}


func _request(end: float, oxidation: float = 0.0, heat_liquid: float = 0.0,
	heat_vapour: float = 0.0, temperature: float = 298.15) -> Dictionary:
	return {"schema": "g3_prescribed_sensible_request_v1", "end_time_s": end,
		"oxidation_kg": oxidation, "heat_liquid_kj": heat_liquid, "heat_vapour_kj": heat_vapour,
		"emitted_vapour_temperature_k": temperature}


func _new(context: Dictionary = _context()) -> RefCounted:
	var owner: RefCounted = Controller.new()
	_valid(owner.initialize(context), "initialize")
	return owner


func _commit(owner: RefCounted, request: Dictionary) -> Dictionary:
	var result: Dictionary = owner.commit_step(request, _generation(owner))
	_valid(result, "commit to " + str(request.get("end_time_s")))
	return result


func _run() -> void:
	_group("W01")
	var context: Dictionary = _context()
	var fresh: RefCounted = Controller.new()
	_expect(fresh.snapshot().is_empty(), "empty before initialization")
	_expect(not fresh.preview_step(_request(1.0)).get("valid", true), "uninitialized preview")
	_expect(not fresh.commit_step(_request(1.0), 0).get("valid", true), "uninitialized commit")
	_expect(not fresh.restore({}, 0).get("valid", true), "uninitialized restore")
	# Fails late, inside the ledger: an early write would leave half an owner.
	var unsupported: Dictionary = _context(1000.0, 10.0, 10000.0)
	var refused: Dictionary = fresh.initialize(unsupported)
	_expect(not refused.get("valid", true), "seed outside support refused")
	_expect(refused.get("candidate", {"bad": 1}).is_empty(), "refused initialization has no candidate")
	_expect(fresh.snapshot().is_empty(), "refused initialization leaves no owner")
	if _failed:
		_finish()
		return
	_valid(fresh.initialize(context), "initialize after a refusal")
	var state: Dictionary = fresh.snapshot().duplicate(true)
	_expect(state.get("schema") == "g3_prescribed_sensible_snapshot_v1", "snapshot schema")
	_expect(state.get("generation") == 0 and typeof(state.get("generation")) == TYPE_INT, "initial generation")
	_expect(typeof(state.get("context_fingerprint")) == TYPE_STRING and str(state.get("context_fingerprint")).length() == 64, "fingerprint text")
	_near(_time(fresh), 0.0, "initial physical time")
	_near(_progress(fresh, "time_s"), 0.0, "initial source time")
	for pair: Array in [["liquid_fuel_kg", 1.0], ["vapour_fuel_kg", 0.0], ["o2_kg", 10.0],
		["thermal_budget_kj", 1000.0], ["deposited_heat_kj", 0.0], ["liquid_sensible_kj", 0.0],
		["vapour_sensible_kj", 0.0], ["initial_fuel_mass_kg", 1.0]]:
		_near(_phase(fresh, pair[0]), pair[1], "initial " + pair[0])
	for key: String in Controller.TOTAL_KEYS:
		_expect(_total(fresh, key) == 0.0, "initial account " + key)
	_expect(state.get("totals", {}).size() == Controller.TOTAL_KEYS.size(), "closed accounts")
	var before: Dictionary = fresh.snapshot().duplicate(true)
	_reject(fresh, fresh.initialize(_context()), before, "reinitialize forbidden")

	_group("W02")
	var owner: RefCounted = _new(context)
	before = owner.snapshot().duplicate(true)
	var request: Dictionary = _request(1.0, 0.0, 20.0, 0.0, 398.15)
	var request_copy: Dictionary = request.duplicate(true)
	var preview: Dictionary = owner.preview_step(request)
	_valid(preview, "preview")
	if not preview.get("valid", false):
		_finish()
		return
	for i: int in range(3):
		_expect(owner.preview_step(request) == preview, "deterministic preview")
	_expect(owner.snapshot() == before, "preview does not write")
	_expect(request == request_copy, "request untouched")
	_expect(preview["candidate"]["generation"] == 1 and _generation(owner) == 0, "candidate generation is not confirmed")
	context["seed"]["initial_thermal_budget_kj"] = 0.0
	context["program"]["samples"][0]["rate_kg_s"] = 0.0
	context["material"]["liquid_profile"]["samples"][0]["cp_kj_kg_k"] = 9.0
	context["attribution"]["provenance"] = "synthetic:edited_after_initialization"
	_expect(owner.preview_step(request) == preview, "context deep copy")
	var exported: Dictionary = owner.snapshot()
	exported["phase"]["liquid_fuel_kg"] = 0.0
	exported["totals"]["heating_liquid_kj"] = 5.0
	exported["progress"]["accepted_kg"] = 0.5
	_expect(owner.snapshot() == before, "snapshot deep copy")
	if _failed:
		# An aliased snapshot has corrupted this owner; stop on that failure.
		_finish()
		return
	var edited: Dictionary = owner.preview_step(request)
	_valid(edited, "preview to edit")
	if not edited.get("valid", false):
		_finish()
		return
	edited["candidate"]["phase"]["thermal_budget_kj"] = 0.0
	edited["report"]["confirmed"]["phase"]["liquid_fuel_kg"] = 0.0
	edited["report"]["attribution"]["status"] = "measured_emission"
	edited["step"]["accepted_release_kg"] = 9.0
	_expect(owner.snapshot() == before, "preview and report cannot mutate the owner")
	_expect(owner.preview_step(request) == preview, "edited preview is not retained")

	_group("W03")
	var hot: RefCounted = _new()
	var result: Dictionary = _commit(hot, _request(1.0, 0.0, 20.0, 0.0, 398.15))
	_observe("hot1_liquid", _phase(hot, "liquid_fuel_kg"))
	_observe("hot1_vapour", _phase(hot, "vapour_fuel_kg"))
	_observe("hot1_budget", _phase(hot, "thermal_budget_kj"))
	_observe("hot1_sl", _phase(hot, "liquid_sensible_kj"))
	_observe("hot1_sv", _phase(hot, "vapour_sensible_kj"))
	_observe("hot1_cost", _step(result, "release_cost_kj"))
	_near(_step(result, "release_cost_kj_kg"), 1080.0, "hot cost per kg")
	_expect(_generation(hot) == 1, "one generation per committed step")
	before = hot.snapshot().duplicate(true)
	if result.get("valid", false):
		result["snapshot"]["phase"]["o2_kg"] = 0.0
		result["report"]["confirmed"]["totals"]["heating_liquid_kj"] = 0.0
		result["step"]["release_cost_kj"] = 0.0
	_expect(hot.snapshot() == before, "commit response cannot mutate the owner")
	_closes(hot, 1.0, 10.0, 1000.0, 0.0, "hot step 1")
	result = _commit(hot, _request(2.0, 0.05, 0.0, 5.0, 348.15))
	_observe_history("hot2_", hot, true)
	_expect(_generation(hot) == 2, "second generation")
	_closes(hot, 1.0, 10.0, 1000.0, 0.0, "hot step 2")

	_group("W04")
	var reference: RefCounted = _new()
	_commit(reference, _request(1.0))
	_commit(reference, _request(2.0, 0.05))
	_observe_history("ref2_", reference, false)
	_closes(reference, 1.0, 10.0, 1000.0, 0.0, "reference step 2")
	_expect(hot.snapshot().get("context_fingerprint") == reference.snapshot().get("context_fingerprint"), "both histories share one context")
	for key: String in ["liquid_fuel_kg", "vapour_fuel_kg", "o2_kg"]:
		_expect(_phase(hot, key) == _phase(reference, key), "equal mass " + key)
	for key: String in ["oxidized_fuel_kg", "co2_kg", "water_vapour_kg", "o2_consumed_kg"]:
		_expect(_total(hot, key) == _total(reference, key), "equal mass account " + key)
	for key: String in ["accepted_kg", "rejected_kg", "scheduled_kg", "time_s"]:
		_expect(_progress(hot, key) == _progress(reference, key), "equal source progress " + key)
	for key: String in ["thermal_budget_kj", "deposited_heat_kj", "liquid_sensible_kj", "vapour_sensible_kj"]:
		_expect(absf(_phase(hot, key) - _phase(reference, key)) > 1.0, "thermal history distinguishes " + key)
	for key: String in ["heating_liquid_kj", "heating_vapour_kj", "release_cost_kj", "emitted_vapour_sensible_kj"]:
		_expect(absf(_total(hot, key) - _total(reference, key)) > 1.0, "thermal account distinguishes " + key)
	var first: RefCounted = _new()
	_commit(first, _request(1.0, 0.0, 20.0))
	_commit(first, _request(2.0))
	var later: RefCounted = _new()
	_commit(later, _request(1.0))
	_commit(later, _request(2.0, 0.0, 20.0))
	for pair: Array in [["first_", first], ["later_", later]]:
		_observe(pair[0] + "liquid", _phase(pair[1], "liquid_fuel_kg"))
		_observe(pair[0] + "heating_l", _total(pair[1], "heating_liquid_kj"))
		_observe(pair[0] + "sl", _phase(pair[1], "liquid_sensible_kj"))
		_observe(pair[0] + "budget", _phase(pair[1], "thermal_budget_kj"))
		_observe(pair[0] + "cost", _total(pair[1], "release_cost_kj"))
		_observe(pair[0] + "released", _total(pair[1], "released_liquid_sensible_kj"))
		_closes(pair[1], 1.0, 10.0, 1000.0, 0.0, pair[0] + "order")
	_expect(_total(first, "heating_liquid_kj") == _total(later, "heating_liquid_kj"), "equal total heating")
	_expect(absf(_phase(first, "liquid_sensible_kj") - _phase(later, "liquid_sensible_kj")) > 1.0, "order changes liquid sensible")
	_expect(absf(_phase(first, "thermal_budget_kj") - _phase(later, "thermal_budget_kj")) > 1.0, "order changes budget")

	_group("W05")
	var hot_saved: Dictionary = hot.snapshot().duplicate(true)
	var reference_saved: Dictionary = reference.snapshot().duplicate(true)
	_commit(hot, _request(3.0, 0.15))
	_commit(reference, _request(3.0, 0.15))
	for pair: Array in [["hot3_", hot], ["ref3_", reference]]:
		_observe(pair[0] + "q", _phase(pair[1], "deposited_heat_kj"))
		_observe(pair[0] + "budget", _phase(pair[1], "thermal_budget_kj"))
		_observe(pair[0] + "sl", _phase(pair[1], "liquid_sensible_kj"))
		_observe(pair[0] + "sv", _phase(pair[1], "vapour_sensible_kj"))
		_closes(pair[1], 1.0, 10.0, 1000.0, 0.0, pair[0] + "continuation")
	var hot_final: Dictionary = hot.snapshot().duplicate(true)
	var reference_final: Dictionary = reference.snapshot().duplicate(true)
	_valid(hot.restore(hot_saved, _generation(hot)), "restore hot history")
	_expect(_generation(hot) == 4, "restore assigns current generation + 1")
	_expect(_without_generation(hot.snapshot()) == _without_generation(hot_saved), "restore keeps every thermal account")
	_near(_total(hot, "heating_liquid_kj"), 20.0, "restored heating not lost")
	_commit(hot, _request(3.0, 0.15))
	_expect(_without_generation(hot.snapshot()) == _without_generation(hot_final), "restored continuation equals continuous")
	var restarted_hot: RefCounted = _new()
	_valid(restarted_hot.restore(hot_saved, 0), "restart hot in a new owner")
	_expect(_generation(restarted_hot) == 1, "restart generation is new, not saved")
	_commit(restarted_hot, _request(3.0, 0.15))
	_expect(_without_generation(restarted_hot.snapshot()) == _without_generation(hot_final), "restart equals continuous hot")
	var restarted_reference: RefCounted = _new()
	_valid(restarted_reference.restore(reference_saved, 0), "restart reference in a new owner")
	_commit(restarted_reference, _request(3.0, 0.15))
	_expect(_without_generation(restarted_reference.snapshot()) == _without_generation(reference_final), "restart equals continuous reference")
	_near(_phase(restarted_hot, "deposited_heat_kj") - _phase(restarted_reference, "deposited_heat_kj"), 20.0, "restored histories still differ in Q")
	_near(_phase(restarted_reference, "thermal_budget_kj") - _phase(restarted_hot, "thermal_budget_kj"), 36.0, "restored histories still differ in B")
	_expect(_phase(restarted_hot, "vapour_fuel_kg") == _phase(restarted_reference, "vapour_fuel_kg"), "restored histories keep equal mass")

	_group("W06")
	var guarded: RefCounted = _new()
	var forged: Dictionary = guarded.preview_step(_request(1.0, 0.0, 20.0, 0.0, 398.15))
	_valid(forged, "preview to forge")
	if forged.get("valid", false):
		forged["candidate"]["phase"]["thermal_budget_kj"] = 5000.0
		forged["candidate"]["generation"] = 40
	before = guarded.snapshot().duplicate(true)
	_reject(guarded, guarded.commit_step(forged.get("candidate", {}), 0), before, "candidate is not a request")
	_reject(guarded, guarded.commit_step(forged, 0), before, "preview is not a request")
	for extra: String in ["phase", "candidate", "snapshot", "totals"]:
		var smuggled: Dictionary = _request(1.0)
		smuggled[extra] = forged.get("candidate", {}).get("phase", {})
		_reject(guarded, guarded.commit_step(smuggled, 0), before, "smuggled " + extra)
	_commit(guarded, _request(1.0, 0.0, 20.0, 0.0, 398.15))
	_near(_phase(guarded, "thermal_budget_kj"), 872.0, "commit recomputes; forged preview ignored")
	_expect(_generation(guarded) == 1, "forged generation ignored")
	var stale: Dictionary = guarded.preview_step(_request(2.0))
	_near(_step(stale, "requested_release_kg"), 0.1, "preview before an intervening commit")
	_commit(guarded, _request(1.5))
	before = guarded.snapshot().duplicate(true)
	_reject(guarded, guarded.commit_step(_request(2.0), 1), before, "intent of a stale preview")
	result = _commit(guarded, _request(2.0))
	_near(_step(result, "requested_release_kg"), 0.05, "commit uses the current state, not the stale preview")

	_group("W07")
	before = guarded.snapshot().duplicate(true)
	var current: int = _generation(guarded)
	_reject(guarded, guarded.commit_step(_request(3.0), current - 1), before, "stale generation")
	_reject(guarded, guarded.commit_step(_request(3.0), current + 1), before, "future generation")
	for bad: Variant in [float(current), true, str(current), null, -1, {}, [current]]:
		_reject(guarded, guarded.commit_step(_request(3.0), bad), before, "invalid generation type")
		_reject(guarded, guarded.restore(before, bad), before, "invalid restore generation type")
	_commit(guarded, _request(3.0))
	before = guarded.snapshot().duplicate(true)
	_reject(guarded, guarded.commit_step(_request(4.0), current), before, "double commit with one generation")
	_reject(guarded, guarded.restore(hot_saved, current), before, "restore with a consumed generation")
	var at_limit: RefCounted = _new()
	var limit_state: Dictionary = at_limit.snapshot().duplicate(true)
	limit_state["generation"] = Controller.MAX_GENERATION
	# Direct reflection is a test seam only; it is not a supported restore.
	at_limit.set("_owned", limit_state)
	before = at_limit.snapshot().duplicate(true)
	_reject(at_limit, at_limit.commit_step(_request(1.0), Controller.MAX_GENERATION), before, "generation overflow in commit")
	_reject(at_limit, at_limit.restore(limit_state, Controller.MAX_GENERATION), before, "generation overflow in restore")
	result = at_limit.commit_step(_request(0.0, 1.0), Controller.MAX_GENERATION)
	_expect(result.get("valid", false) and result.get("no_op", false), "no-op needs no new generation")

	_group("W08")
	var initial: RefCounted = _new()
	var initial_saved: Dictionary = initial.snapshot().duplicate(true)
	for change: String in ["liquid_cp", "vapour_cp_sample", "reference_heats", "reference_provenance",
		"profile_provenance", "attribution_provenance", "seed_budget", "seed_liquid_sensible",
		"seed_provenance", "program_rate", "program_profile_id"]:
		var changed: Dictionary = _changed_context(change)
		_expect(changed["material"]["component_id"] == "synthetic_CHO", "same component_id " + change)
		var foreign: RefCounted = _new(changed)
		_expect(foreign.snapshot().get("context_fingerprint") != initial_saved.get("context_fingerprint"), "content bound " + change)
		before = foreign.snapshot().duplicate(true)
		_reject(foreign, foreign.restore(initial_saved, 0), before, "foreign content " + change)
		_reject(foreign, foreign.restore(hot_saved, 0), before, "foreign history " + change)
		before = initial.snapshot().duplicate(true)
		_reject(initial, initial.restore(foreign.snapshot(), _generation(initial)), before, "reverse foreign content " + change)

	_group("W09")
	var plain: RefCounted = _new()
	var reordered_context: Dictionary = _reordered(_context())
	_expect(reordered_context.keys() != _context().keys(), "control really permutes keys")
	var reordered: RefCounted = _new(reordered_context)
	_expect(reordered.snapshot().get("context_fingerprint") == plain.snapshot().get("context_fingerprint"), "key order is not content")
	var integer_context: Dictionary = _integers(_context())
	_expect(typeof(integer_context["seed"]["initial_o2_kg"]) == TYPE_INT and typeof(integer_context["program"]["initial_mass_kg"]) == TYPE_INT, "control really uses integers")
	var integers: RefCounted = _new(integer_context)
	_expect(integers.snapshot().get("context_fingerprint") == plain.snapshot().get("context_fingerprint"), "int and float are one content")
	var signed_zero: Dictionary = _context()
	signed_zero["seed"]["initial_liquid_sensible_kj"] = -1.0 * 0.0
	_expect(_new(signed_zero).snapshot().get("context_fingerprint") == plain.snapshot().get("context_fingerprint"), "negative zero is zero")
	_commit(plain, _request(1.0, 0.0, 20.0, 0.0, 398.15))
	_valid(reordered.restore(plain.snapshot(), 0), "reordered owner restores the same content")
	_valid(integers.restore(plain.snapshot(), 0), "integer owner restores the same content")
	_expect(_without_generation(integers.snapshot()) == _without_generation(plain.snapshot()), "integer owner holds the same accounts")
	var next_double: Dictionary = _context(1000.0 * (1.0 + 2.220446049250313e-16))
	_expect(next_double["seed"]["initial_thermal_budget_kj"] != 1000.0, "control really changes the number")
	_expect(_new(next_double).snapshot().get("context_fingerprint") != _new().snapshot().get("context_fingerprint"), "smallest numeric change is content")
	var spaced: Dictionary = _context()
	spaced["attribution"]["provenance"] = "synthetic:no_experimental_approval "
	_expect(_new(spaced).snapshot().get("context_fingerprint") != _new().snapshot().get("context_fingerprint"), "text is bound exactly")

	_group("W10")
	var heated: RefCounted = _new()
	_commit(heated, _request(1.0))
	_commit(heated, _request(2.0))
	var unheated: Dictionary = heated.snapshot().duplicate(true)
	for i: int in range(3):
		_valid(heated.preview_step(_request(3.0, 0.0, 20.0, 10.0)), "heating preview")
	_expect(heated.snapshot() == unheated, "repeated preview never debits")
	result = _commit(heated, _request(3.0, 0.0, 20.0, 10.0))
	_near(_phase(heated, "thermal_budget_kj"), 770.0, "heating debited once")
	_near(_phase(heated, "liquid_sensible_kj"), 20.0, "liquid heating stored once")
	_near(_phase(heated, "vapour_sensible_kj"), 10.0, "vapour heating stored once")
	_near(_phase(heated, "deposited_heat_kj"), 0.0, "heating is not combustion")
	_near(_total(heated, "heating_liquid_kj"), 20.0, "liquid heating account")
	_near(_total(heated, "heating_vapour_kj"), 10.0, "vapour heating account")
	_near(_total(heated, "release_cost_kj"), 200.0, "heating is not release cost")
	_near(_step(result, "accepted_release_kg"), 0.0, "heat-only step releases nothing")
	_closes(heated, 1.0, 10.0, 1000.0, 0.0, "heat only")
	_valid(heated.restore(unheated, _generation(heated)), "restore before heating")
	_commit(heated, _request(3.0, 0.0, 20.0, 10.0))
	_near(_phase(heated, "thermal_budget_kj"), 770.0, "replayed heating not doubled")
	_near(_total(heated, "heating_liquid_kj"), 20.0, "replayed account not doubled")

	_group("W11")
	var capped: RefCounted = _new(_context(74.0))
	result = _commit(capped, _request(1.0, 0.05, 20.0, 0.0, 398.15))
	_observe("cap_accepted", _step(result, "accepted_release_kg"))
	_observe("cap_rejected", _step(result, "rejected_release_kg"))
	_observe("cap_deficit", _step(result, "release_budget_deficit_kj"))
	_observe("cap_budget", _phase(capped, "thermal_budget_kj"))
	_observe("cap_sl", _phase(capped, "liquid_sensible_kj"))
	_observe("cap_q", _phase(capped, "deposited_heat_kj"))
	_observe("cap_total", _account(capped, "total_kj"))
	_near(_progress(capped, "time_s"), 1.0, "limited demand still advances the source")
	_closes(capped, 1.0, 10.0, 74.0, 0.0, "budget cap")
	result = _commit(capped, _request(2.0, 1.0))
	_observe("cap_next_accepted", _step(result, "accepted_release_kg"))
	_observe("cap_rejected_total", _progress(capped, "rejected_kg"))
	_near(_step(result, "requested_release_kg"), 0.1, "rejected prefix is not reemitted")
	_near(_step(result, "rejected_release_kg"), 0.1, "step rejection is only the demand of this step")
	_near(_step(result, "release_budget_deficit_kj"), 98.0, "deficit of this step only")
	_near(_phase(capped, "deposited_heat_kj"), 1005.0, "deposited heat is never budget")
	_near(_phase(capped, "liquid_fuel_kg"), 0.95, "no release financed by Q")
	before = capped.snapshot().duplicate(true)
	_reject(capped, capped.commit_step(_request(3.0, 0.0, 1.0), _generation(capped)), before, "heating without budget")
	_near(_time(capped), 2.0, "refused heating does not advance the clock")

	_group("W12")
	var limited: RefCounted = _new(_context(1000.0, 0.2))
	result = _commit(limited, _request(1.0, 0.1))
	_observe("o2_oxidized", _step(result, "accepted_oxidation_kg"))
	_observe("o2_vapour", _phase(limited, "vapour_fuel_kg"))
	_observe("o2_left", _phase(limited, "o2_kg"))
	_near(_step(result, "accepted_release_kg"), 0.1, "oxygen does not restrict release")
	_near(_step(result, "rejected_oxidation_kg"), 0.05, "oxidation rejection reported")
	_closes(limited, 1.0, 0.2, 1000.0, 0.0, "oxygen cap")
	var small: RefCounted = _new(_context(1000.0, 10.0, 8.0, 0.2))
	_commit(small, _request(1.0))
	_near(_phase(small, "liquid_sensible_kj"), 4.0, "half of the liquid sensible left")
	_commit(small, _request(2.0))
	_observe("exh_liquid", _phase(small, "liquid_fuel_kg"))
	_observe("exh_sl", _phase(small, "liquid_sensible_kj"))
	_observe("exh_budget", _phase(small, "thermal_budget_kj"))
	_observe("exh_released", _total(small, "released_liquid_sensible_kj"))
	_observe("exh_total", _account(small, "total_kj"))
	_expect(_phase(small, "liquid_fuel_kg") == 0.0 and _phase(small, "liquid_sensible_kj") == 0.0, "exhausted liquid is exactly empty")
	_closes(small, 0.2, 10.0, 1000.0, 8.0, "exhaustion")
	before = small.snapshot().duplicate(true)
	_reject(small, small.commit_step(_request(3.0, 0.0, 1.0), _generation(small)), before, "heating exhausted liquid")
	_commit(small, _request(3.0, 0.0, 0.0, 10.0))
	_observe("exh_heated_sv", _phase(small, "vapour_sensible_kj"))
	_observe("exh_heated_budget", _phase(small, "thermal_budget_kj"))
	result = _commit(small, _request(4.0, 5.0))
	_near(_step(result, "accepted_oxidation_kg"), 0.2, "oxidation limited by vapour inventory")
	_expect(_phase(small, "vapour_fuel_kg") == 0.0 and _phase(small, "vapour_sensible_kj") == 0.0, "exhausted vapour is exactly empty")
	_near(_phase(small, "deposited_heat_kj"), 4010.0, "vapour sensible delivered with oxidation")
	_closes(small, 0.2, 10.0, 1000.0, 8.0, "all fuel oxidized")

	_group("W13")
	var tail: RefCounted = _new()
	_commit(tail, _request(2.0))
	_expect(tail.preview_step(_request(2.0)).get("report", {}).get("source_finished", false), "source finished at its end")
	result = _commit(tail, _request(3.0, 0.1, 0.0, 5.0))
	_near(_step(result, "requested_release_kg"), 0.0, "no release after the source")
	_near(_step(result, "physical_dt_s"), 1.0, "physical clock continues")
	_near(_step(result, "source_dt_s"), 0.0, "source clock stopped")
	_near(_step(result, "accepted_oxidation_kg"), 0.1, "oxidation continues after the source")
	_near(_phase(tail, "vapour_sensible_kj"), 2.5, "vapour heated after the source")
	_near(_phase(tail, "deposited_heat_kj"), 2002.5, "delivery after the source")
	_near(_progress(tail, "time_s"), 2.0, "no source extrapolation")
	_near(_time(tail), 3.0, "physical time not truncated")
	_expect(not result.get("report", {}).has("fire_extinguished"), "no inferred extinction")
	_closes(tail, 1.0, 10.0, 1000.0, 0.0, "after source end")
	var crossing: RefCounted = _new()
	_commit(crossing, _request(1.5))
	result = _commit(crossing, _request(2.5))
	_observe("cross_demand", _step(result, "requested_release_kg"))
	_observe("cross_physical_dt", _step(result, "physical_dt_s"))
	_observe("cross_source_dt", _step(result, "source_dt_s"))
	_observe("cross_cursor", _progress(crossing, "time_s"))
	_observe("cross_time", _time(crossing))

	_group("W14")
	before = tail.snapshot().duplicate(true)
	var zero: Dictionary = tail.preview_step(_request(3.0, 1.0, 50.0, 50.0, 398.15))
	_valid(zero, "zero-dt preview")
	_expect(zero.get("candidate", {}) == before, "zero-dt candidate is the confirmed state")
	_expect(zero.get("candidate", {}).get("generation", -1) == _generation(tail), "generation does not advance at dt 0")
	result = tail.commit_step(_request(3.0, 1.0, 50.0, 50.0, 398.15), _generation(tail))
	_valid(result, "zero-dt commit")
	_expect(result.get("no_op", false), "zero dt is a no-op")
	_expect(tail.snapshot() == before, "no-op leaves the aggregate identical")
	for key: String in ["accepted_oxidation_kg", "accepted_release_kg", "heating_liquid_kj", "heating_vapour_kj", "deposited_increment_kj"]:
		_expect(_step(result, key) == 0.0, "no-op quantity " + key)
	_reject(tail, tail.commit_step(_request(3.0, 0.0, 0.0, 0.0, 900.0), _generation(tail)), before, "dt 0 still validates the request")
	result = _commit(tail, _request(4.0))
	_expect(not result.get("no_op", true), "positive idle step is a step")
	_expect(_generation(tail) == int(before.get("generation", -9)) + 1, "idle step advances generation")
	_near(_time(tail), 4.0, "idle step advances physical time")
	_expect(tail.snapshot().get("phase") == before.get("phase"), "idle step keeps the phase exactly")
	_expect(tail.snapshot().get("totals") == before.get("totals"), "idle step keeps the accounts exactly")
	_expect(tail.snapshot().get("progress") == before.get("progress"), "idle step keeps the finished source exactly")

	_group("W15")
	var absent: RefCounted = _new()
	before = absent.snapshot().duplicate(true)
	_reject(absent, absent.commit_step(_request(1.0, 0.0, 0.0, 1.0), 0), before, "heating absent vapour")
	_near(_time(absent), 0.0, "refused transaction keeps the clock")
	var tiny_context: Dictionary = _context()
	tiny_context["program"]["samples"][0]["rate_kg_s"] = 1.0e-20
	var tiny: RefCounted = _new(tiny_context)
	_commit(tiny, _request(1.0, 0.0, 0.0, 0.0, 398.15))
	_expect(_phase(tiny, "vapour_fuel_kg") == 1.0e-20, "tiny vapour mass retained")
	_expect(_phase(tiny, "vapour_sensible_kj") != 0.0, "tiny sensible not erased")
	_near(_phase(tiny, "vapour_sensible_kj") * 1.0e18, 1.0, "tiny sensible value")
	var tiny_saved: Dictionary = tiny.snapshot().duplicate(true)
	_valid(tiny.restore(tiny_saved, _generation(tiny)), "restore tiny phase")
	_expect(_phase(tiny, "vapour_sensible_kj") == float(tiny_saved["phase"]["vapour_sensible_kj"]), "restore keeps tiny sensible exactly")
	_commit(tiny, _request(2.0, 1.0, 0.0, 0.0, 398.15))
	_expect(_phase(tiny, "vapour_fuel_kg") == 0.0 and _phase(tiny, "vapour_sensible_kj") == 0.0, "tiny vapour fully oxidized")

	_group("W16")
	var cold: RefCounted = _new(_context(1000.0, 10.0, -50.0))
	result = _commit(cold, _request(1.0, 0.1, 0.0, 0.0, 273.15))
	_observe("cold_cost", _step(result, "release_cost_kj"))
	_observe("cold_budget", _phase(cold, "thermal_budget_kj"))
	_observe("cold_sl", _phase(cold, "liquid_sensible_kj"))
	_observe("cold_sv", _phase(cold, "vapour_sensible_kj"))
	_observe("cold_q", _phase(cold, "deposited_heat_kj"))
	_observe("cold_oxidized_sensible", _total(cold, "oxidized_sensible_kj"))
	_observe("cold_released", _total(cold, "released_liquid_sensible_kj"))
	_observe("cold_emitted", _total(cold, "emitted_vapour_sensible_kj"))
	_observe("cold_total", _account(cold, "total_kj"))
	_closes(cold, 1.0, 10.0, 1000.0, -50.0, "cold history")
	var cold_saved: Dictionary = cold.snapshot().duplicate(true)
	_valid(cold.restore(cold_saved, _generation(cold)), "restore signed accounts")
	_near(_total(cold, "oxidized_sensible_kj"), -2.5, "restored negative account keeps its sign")
	for outside: float in [-50.5, 400.5]:
		var unsupported_owner: RefCounted = Controller.new()
		_expect(not unsupported_owner.initialize(_context(1000.0, 10.0, outside)).get("valid", true), "seed sensible outside support")
		_expect(unsupported_owner.snapshot().is_empty(), "unsupported seed leaves no owner")
	var empty_context: Dictionary = _context(1000.0, 10.0, 1.0, 0.0)
	empty_context["program"]["samples"][0]["rate_kg_s"] = 0.0
	_expect(not Controller.new().initialize(empty_context).get("valid", true), "absent liquid cannot hold sensible")
	var supported: RefCounted = _new()
	before = supported.snapshot().duplicate(true)
	for temperature: float in [200.0, 600.0]:
		_reject(supported, supported.commit_step(_request(1.0, 0.0, 0.0, 0.0, temperature), 0), before, "emission outside support")
	_reject(supported, supported.commit_step(_request(1.0, 0.0, 500.0), 0), before, "heating outside support")
	_reject(supported, supported.commit_step(_request(1.0, 0.0, 1200.0), 0), before, "heating above budget")

	_group("W17")
	_check_request_schema()
	_check_context_schema()
	_check_snapshot_schema(hot_saved)

	_group("W18")
	var audited: RefCounted = _new()
	_valid(audited.restore(hot_saved, 0), "load hot history")
	before = audited.snapshot().duplicate(true)
	var generation: int = _generation(audited)
	for key: String in NUMERIC_PHASE:
		var tampered: Dictionary = hot_saved.duplicate(true)
		tampered["phase"][key] += 0.01
		_reject(audited, audited.restore(tampered, generation), before, "tampered phase " + key)
	for key: String in Controller.TOTAL_KEYS:
		var tampered: Dictionary = hot_saved.duplicate(true)
		tampered["totals"][key] += 0.01
		_reject(audited, audited.restore(tampered, generation), before, "tampered account " + key)
	var mixed: Dictionary = hot_saved.duplicate(true)
	mixed["totals"] = reference_saved["totals"].duplicate(true)
	_reject(audited, audited.restore(mixed, generation), before, "hot phase with reference accounts")
	mixed = hot_saved.duplicate(true)
	mixed["phase"] = reference_saved["phase"].duplicate(true)
	_reject(audited, audited.restore(mixed, generation), before, "reference phase with hot accounts")
	mixed = hot_saved.duplicate(true)
	mixed["phase"]["liquid_sensible_kj"] = 0.0
	mixed["phase"]["vapour_sensible_kj"] = 0.0
	_reject(audited, audited.restore(mixed, generation), before, "sensible dropped as if rebuilt from mass")
	mixed = hot_saved.duplicate(true)
	mixed["progress"]["accepted_kg"] += 0.01
	mixed["progress"]["rejected_kg"] = maxf(0.0, float(mixed["progress"]["rejected_kg"]) - 0.01)
	mixed["progress"]["scheduled_kg"] = float(mixed["progress"]["accepted_kg"]) + float(mixed["progress"]["rejected_kg"])
	_reject(audited, audited.restore(mixed, generation), before, "cursor edited without its fuel")
	mixed = capped.snapshot().duplicate(true)
	mixed["progress"]["accepted_kg"] = 0.2
	mixed["progress"]["rejected_kg"] = 0.0
	var capped_before: Dictionary = capped.snapshot().duplicate(true)
	_reject(capped, capped.restore(mixed, _generation(capped)), capped_before, "balanced cursor cannot restore fuel")
	mixed = tail.snapshot().duplicate(true)
	mixed["physical_time_s"] = 1.5
	var tail_before: Dictionary = tail.snapshot().duplicate(true)
	_reject(tail, tail.restore(mixed, _generation(tail)), tail_before, "physical clock behind the source cursor")
	mixed = hot_saved.duplicate(true)
	mixed["physical_time_s"] = 1.0
	_reject(audited, audited.restore(mixed, generation), before, "physical clock moved alone")
	# Declared limit: an edit that keeps EVERY identity is accepted. The check
	# is coherency of the accounts, not authenticity of the saved history.
	var coherent: Dictionary = hot_saved.duplicate(true)
	coherent["totals"]["heating_liquid_kj"] += 1.0
	coherent["totals"]["release_cost_kj"] -= 1.0
	coherent["totals"]["released_liquid_sensible_kj"] += 1.0
	_valid(audited.restore(coherent, generation), "coherent edit accepted: coherency is not authenticity")
	_valid(audited.restore(reference_saved, _generation(audited)), "another coherent history of the same context")
	_near(_phase(audited, "liquid_sensible_kj"), 0.0, "restored the other history")

	_group("W19")
	var overflow_context: Dictionary = _context(1.1e308)
	overflow_context["program"]["initial_mass_kg"] = 4.0e303
	var overflowed: RefCounted = Controller.new()
	_expect(not overflowed.initialize(overflow_context).get("valid", true), "finite terms with nonfinite total")
	_expect(overflowed.snapshot().is_empty(), "overflow leaves no owner")
	audited = _new()
	_valid(audited.restore(hot_saved, 0), "reload hot history")
	before = audited.snapshot().duplicate(true)
	generation = _generation(audited)
	var huge: Dictionary = hot_saved.duplicate(true)
	huge["totals"]["heating_liquid_kj"] = 1.7e308
	huge["totals"]["heating_vapour_kj"] = 1.7e308
	_reject(audited, audited.restore(huge, generation), before, "accumulated heating overflow")
	huge = hot_saved.duplicate(true)
	huge["totals"]["emitted_vapour_sensible_kj"] = 1.7e308
	huge["totals"]["released_liquid_sensible_kj"] = -1.7e308
	_reject(audited, audited.restore(huge, generation), before, "signed account overflow")
	huge = hot_saved.duplicate(true)
	huge["phase"]["deposited_heat_kj"] = 1.7e308
	huge["totals"]["chemical_oxidation_heat_kj"] = 1.7e308
	_reject(audited, audited.restore(huge, generation), before, "deposited heat overflow")
	huge = hot_saved.duplicate(true)
	huge["physical_time_s"] = INF
	_reject(audited, audited.restore(huge, generation), before, "nonfinite physical time")
	_reject(audited, audited.commit_step(_request(1.0e308, 1.0e308, 1.0e308, 1.0e308), generation), before, "finite request with overflowing heat")

	_group("W20")
	for linear: bool in [false, true]:
		var whole: RefCounted = _new(_context(1000.0, 10.0, 0.0, 1.0, linear))
		_commit(whole, _request(2.0, 1.0, 0.0, 0.0, 348.15))
		for times: Array in [[0.5, 1.0, 1.5, 2.0], [0.13, 0.87, 1.23, 2.0]]:
			var divided: RefCounted = _new(_context(1000.0, 10.0, 0.0, 1.0, linear))
			for end: float in times:
				_commit(divided, _request(end, 1.0, 0.0, 0.0, 348.15))
			for key: String in NUMERIC_PHASE:
				_near(_phase(divided, key), _phase(whole, key), "partition phase " + key)
			for key: String in Controller.TOTAL_KEYS:
				_near(_total(divided, key), _total(whole, key), "partition account " + key)
			_near(_progress(divided, "accepted_kg"), 0.1 if linear else 0.2, "partition integral")
	var long_context: Dictionary = _context(5000.0, 50.0)
	long_context["program"]["samples"] = [{"time_s": 0.0, "rate_kg_s": 0.004}, {"time_s": 200.0, "rate_kg_s": 0.0}]
	var long_run: RefCounted = _new(long_context)
	var halfway: Dictionary = {}
	var plan: Array = []
	var clock: float = 0.0
	for i: int in range(1, 121):
		clock += 0.5 + 0.37 * float(i % 7)
		plan.append(_request(clock, 0.002, 0.5, 0.05 if i > 1 else 0.0, 298.15 + 20.0 * float(i % 5)))
	for i: int in range(plan.size()):
		_commit(long_run, plan[i])
		if i == 59:
			halfway = long_run.snapshot().duplicate(true)
	_expect(_generation(long_run) == 120, "one generation per step of a long history")
	_closes(long_run, 1.0, 50.0, 5000.0, 0.0, "long irregular history")
	_near(_total(long_run, "heating_liquid_kj"), 60.0, "long history liquid heating")
	_near(_total(long_run, "heating_vapour_kj"), 5.95, "long history vapour heating")
	var resumed: RefCounted = _new(long_context)
	_valid(resumed.restore(halfway, 0), "restart a long history halfway")
	for i: int in range(60, plan.size()):
		_commit(resumed, plan[i])
	_expect(_without_generation(resumed.snapshot()) == _without_generation(long_run.snapshot()), "restarted long history equals continuous")

	_group("W21")
	var reported: RefCounted = _new()
	_valid(reported.restore(hot_final, 0), "load final hot history")
	var responses: Array = [Controller.new().preview_step(_request(1.0)), reported.preview_step(_request(9.0)),
		reported.commit_step(_request(9.0), -1), reported.restore(hot_saved, _generation(reported)),
		reported.commit_step(_request(9.0, 0.15), _generation(reported))]
	for response: Dictionary in responses:
		var report: Dictionary = response.get("report", {})
		for key: String in APPROVALS:
			_expect(report.get(key, true) == false, "no approval " + key)
		_expect(report.get("controller_version") == Controller.VERSION, "report version")
		_expect(report.get("fingerprint_scope") == "context_content_binding_not_signature_or_history_proof", "fingerprint is not a signature")
		_expect(str(report.get("scope")).contains("not_evaporation_prediction"), "report scope")
		if report.get("initialized", false):
			_expect(report.get("attribution", {}).get("status") == "conditional_not_measured_emission", "report carries conditional attribution")
			_expect(report.get("energy_boundary_kind") == "synthetic_independent_initial_budget", "report carries the synthetic boundary")
			if response.has("snapshot"):
				_expect(report.get("confirmed") == response["snapshot"], "report describes the confirmed state")
			if response.get("valid", false) and response.has("candidate"):
				_expect(report.get("confirmed") != response["candidate"], "report is not the preview candidate")
	var accounts: Dictionary = reported.preview_step(_request(9.0)).get("report", {}).get("accounts", {})
	_near(float(accounts.get("potential_a_kj", NAN)), 15200.0, "account A")
	_near(float(accounts.get("sensible_s_kj", NAN)), 16.0, "account S")
	_near(float(accounts.get("budget_b_kj", NAN)), 764.0, "account B")
	_near(float(accounts.get("deposited_q_kj", NAN)), 4020.0, "account Q")
	_near(float(accounts.get("total_kj", NAN)), 20000.0, "account total")
	_near(float(accounts.get("chemical_oxidation_heat_kj", NAN)), 4000.0, "chemical heat is separate")
	_near(float(accounts.get("oxidized_sensible_kj", NAN)), 20.0, "oxidized sensible is separate")
	_expect(float(accounts.get("deposited_q_kj", 0.0)) != float(accounts.get("chemical_oxidation_heat_kj", 0.0)), "Q is not chemical heat")

	_group("W22")
	var declared: RefCounted = _new(_context(1000.0, 10.0, 0.0, 1.0, true))
	result = _commit(declared, _request(2.0, 0.0, 10.0, 0.0, 348.15))
	_near(_progress(declared, "accepted_kg"), 0.1, "linear declared program")
	_expect(result.get("report", {}).get("attribution", {}).get("status") == "synthetic_declared_emission", "declared attribution")
	_closes(declared, 1.0, 10.0, 1000.0, 0.0, "declared program")
	var unbound: Dictionary = _context()
	unbound["attribution"]["modeled_component_id"] = "another_component"
	_expect(not Controller.new().initialize(unbound).get("valid", true), "modeled component must be the material")
	unbound = _context(1000.0, 10.0, 0.0, 1.0, true)
	unbound["material"]["component_id"] = "renamed"
	unbound["material"]["liquid_profile"]["component_id"] = "renamed"
	unbound["material"]["vapour_profile"]["component_id"] = "renamed"
	_expect(not Controller.new().initialize(unbound).get("valid", true), "declared component must be the material")
	_finish()


func _check_request_schema() -> void:
	var owner: RefCounted = _new()
	var before: Dictionary = owner.snapshot().duplicate(true)
	var template: Dictionary = _request(1.0, 0.05, 1.0, 0.0, 348.15)
	for key: String in template:
		var missing: Dictionary = template.duplicate(true)
		missing.erase(key)
		_reject(owner, owner.commit_step(missing, 0), before, "request missing " + key)
		if key == "schema":
			continue
		for bad: Variant in [NAN, INF, -INF, true, "1", null, -1.0, [], {}]:
			var invalid: Dictionary = template.duplicate(true)
			invalid[key] = bad
			_reject(owner, owner.commit_step(invalid, 0), before, "request bad " + key)
			_expect(not owner.preview_step(invalid).get("valid", true), "preview bad " + key)
	for bad: Variant in [1, 1.0, true, "", "g3_prescribed_sensible_request_v0", null, {}]:
		var versioned: Dictionary = template.duplicate(true)
		versioned["schema"] = bad
		_reject(owner, owner.commit_step(versioned, 0), before, "request schema")
	var extra: Dictionary = template.duplicate(true)
	extra["unexpected"] = 1.0
	_reject(owner, owner.commit_step(extra, 0), before, "request closed schema")
	for bad: Variant in [null, 1.0, "request", [], true]:
		_reject(owner, owner.commit_step(bad, 0), before, "request not a dictionary")
		_expect(not owner.preview_step(bad).get("valid", true), "preview not a dictionary")
	_reject(owner, owner.commit_step(_request(1.0), 0.0), before, "float generation")
	_valid(owner.commit_step(template, 0), "template request is valid")
	before = owner.snapshot().duplicate(true)
	_reject(owner, owner.commit_step(_request(0.5), 1), before, "physical time backwards")


func _check_context_schema() -> void:
	for family: String in ["context", "program", "material", "attribution", "seed"]:
		var keys: Array = (_context() if family == "context" else _context()[family]).keys()
		for key: String in keys:
			var missing: Dictionary = _context()
			(missing if family == "context" else missing[family]).erase(key)
			_refuse_context(missing, "missing " + family + "." + key)
		var extra: Dictionary = _context()
		(extra if family == "context" else extra[family])["unexpected"] = 1.0
		_refuse_context(extra, "extra field in " + family)
		if family != "context":
			var wrong: Dictionary = _context()
			wrong[family] = "not a dictionary"
			_refuse_context(wrong, family + " not a dictionary")
	for nested: String in ["liquid_profile", "vapour_profile", "reference_material"]:
		var broken: Dictionary = _context()
		broken["material"][nested].erase(broken["material"][nested].keys()[0])
		_refuse_context(broken, "missing nested field in " + nested)
		broken = _context()
		broken["material"][nested]["unexpected"] = 1.0
		_refuse_context(broken, "extra nested field in " + nested)
	for field: String in ["initial_o2_kg", "initial_thermal_budget_kj", "initial_liquid_sensible_kj"]:
		var bads: Array = [true, INF, -INF, NAN, "1", null, [], {}]
		if field != "initial_liquid_sensible_kj":
			bads.append(-1.0)
		for bad: Variant in bads:
			var seeded: Dictionary = _context()
			seeded["seed"][field] = bad
			_refuse_context(seeded, "seed " + field)
	for bad: Variant in [1, true, "", "g3_prescribed_sensible_seed_v0", null]:
		var seeded: Dictionary = _context()
		seeded["seed"]["schema"] = bad
		_refuse_context(seeded, "seed schema")
		seeded = _context()
		seeded["schema"] = bad
		_refuse_context(seeded, "context schema")
	for bad: Variant in ["declared_conditional_initial_budget", "measured_from_HRR", 1, true, null]:
		var seeded: Dictionary = _context()
		seeded["seed"]["energy_boundary_kind"] = bad
		_refuse_context(seeded, "energy boundary kind")
	# A number where text is expected must be refused, not raise a script error.
	for key: String in Controller.PROGRAM_TEXT_KEYS:
		for bad: Variant in [1, 2.0, true, null, "", "  "]:
			var typed: Dictionary = _context()
			typed["program"][key] = bad
			_refuse_context(typed, "program text " + key)
	for key: String in Controller.ATTRIBUTION_KEYS:
		for bad: Variant in [3, true, null, ""]:
			var typed: Dictionary = _context()
			typed["attribution"][key] = bad
			_refuse_context(typed, "attribution text " + key)
	for bad: Variant in [7, true, null, "", "other"]:
		var typed: Dictionary = _context()
		typed["material"]["component_id"] = bad
		_refuse_context(typed, "material component text")
	var promoted: Dictionary = _context()
	promoted["attribution"]["status"] = "measured_emission"
	_refuse_context(promoted, "no measured emission promotion")
	promoted = _context()
	promoted["attribution"]["input_component_id"] = "foreign"
	_refuse_context(promoted, "attribution must match the program")
	promoted = _context()
	promoted["program"]["samples"][0]["rate_kg_s"] = 5.0
	_refuse_context(promoted, "program above the initial mass")
	for bad: Variant in [null, 1.0, "context", [], true]:
		var owner: RefCounted = Controller.new()
		_expect(not owner.initialize(bad).get("valid", true), "context not a dictionary")
		_expect(owner.snapshot().is_empty(), "invalid context leaves no owner")


func _check_snapshot_schema(saved: Dictionary) -> void:
	var owner: RefCounted = _new()
	_valid(owner.restore(saved, 0), "valid snapshot restores")
	var before: Dictionary = owner.snapshot().duplicate(true)
	var generation: int = _generation(owner)
	for key: String in Controller.OWNED_KEYS:
		var missing: Dictionary = saved.duplicate(true)
		missing.erase(key)
		_reject(owner, owner.restore(missing, generation), before, "snapshot missing " + key)
	var extra: Dictionary = saved.duplicate(true)
	extra["unexpected"] = 1.0
	_reject(owner, owner.restore(extra, generation), before, "snapshot closed schema")
	for section: String in ["progress", "phase", "totals"]:
		for key: String in saved[section]:
			var missing: Dictionary = saved.duplicate(true)
			missing[section].erase(key)
			_reject(owner, owner.restore(missing, generation), before, "snapshot missing " + section + "." + key)
			for bad: Variant in [NAN, INF, true, "1", null, {}]:
				var invalid: Dictionary = saved.duplicate(true)
				invalid[section][key] = bad
				_reject(owner, owner.restore(invalid, generation), before, "snapshot bad " + section + "." + key)
		extra = saved.duplicate(true)
		extra[section]["unexpected"] = 1.0
		_reject(owner, owner.restore(extra, generation), before, "snapshot closed " + section)
		var wrong: Dictionary = saved.duplicate(true)
		wrong[section] = "not a dictionary"
		_reject(owner, owner.restore(wrong, generation), before, "snapshot " + section + " not a dictionary")
	for bad: Variant in [1.0, -1, true, "0", null, NAN]:
		var versioned: Dictionary = saved.duplicate(true)
		versioned["generation"] = bad
		_reject(owner, owner.restore(versioned, generation), before, "snapshot generation")
	for key: String in ["schema", "context_fingerprint"]:
		for bad: Variant in [1, 1.0, true, null, "", "g3_prescribed_phase_snapshot_v1"]:
			var versioned: Dictionary = saved.duplicate(true)
			versioned[key] = bad
			_reject(owner, owner.restore(versioned, generation), before, "snapshot " + key)
	for bad: Variant in [NAN, INF, -1.0, true, "2", null]:
		var timed: Dictionary = saved.duplicate(true)
		timed["physical_time_s"] = bad
		_reject(owner, owner.restore(timed, generation), before, "snapshot physical time")
	for bad: Variant in [null, 1.0, "snapshot", [], true]:
		_reject(owner, owner.restore(bad, generation), before, "snapshot not a dictionary")


func _refuse_context(context: Dictionary, label: String) -> void:
	var owner: RefCounted = Controller.new()
	var result: Dictionary = owner.initialize(context)
	_expect(not result.get("valid", true), label + " refused")
	_expect(not result.get("errors", []).is_empty(), label + " explains the refusal")
	_expect(owner.snapshot().is_empty(), label + " leaves no owner")


func _changed_context(change: String) -> Dictionary:
	var context: Dictionary = _context()
	var material: Dictionary = context["material"]
	match change:
		"liquid_cp":
			material["liquid_profile"] = _profile("liquid", 2.5)
		"vapour_cp_sample":
			material["vapour_profile"]["samples"][1]["cp_kj_kg_k"] = 1.5
		"reference_heats":
			material["reference_material"]["liquid_heat_kj_kg"] += 10.0
			material["reference_material"]["vapour_heat_kj_kg"] += 10.0
		"reference_provenance":
			material["reference_material"]["provenance"] = "synthetic: another declared reference"
		"profile_provenance":
			material["liquid_profile"]["provenance"] = "synthetic: another declared profile"
		"attribution_provenance":
			context["attribution"]["provenance"] = "synthetic:different_attribution"
		"seed_budget":
			context["seed"]["initial_thermal_budget_kj"] = 2000.0
		"seed_liquid_sensible":
			context["seed"]["initial_liquid_sensible_kj"] = 1.0
		"seed_provenance":
			context["seed"]["energy_boundary_provenance"] = "synthetic:different_boundary_identity"
		"program_rate":
			context["program"]["samples"][0]["rate_kg_s"] = 0.05
		"program_profile_id":
			context["program"]["profile_id"] = "synthetic_constant_renamed"
	return context


func _reordered(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var keys: Array = value.keys()
		keys.reverse()
		var result: Dictionary = {}
		for key: Variant in keys:
			result[key] = _reordered(value[key])
		return result
	if typeof(value) == TYPE_ARRAY:
		var items: Array = []
		for item: Variant in value:
			items.append(_reordered(item))
		return items
	return value


func _integers(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _integers(value[key])
		return result
	if typeof(value) == TYPE_ARRAY:
		var items: Array = []
		for item: Variant in value:
			items.append(_integers(item))
		return items
	if typeof(value) == TYPE_FLOAT and value == floorf(value) and absf(value) < 1.0e15:
		return int(value)
	return value


func _observe_history(prefix: String, owner: RefCounted, thermal_accounts: bool) -> void:
	_observe(prefix + "liquid", _phase(owner, "liquid_fuel_kg"))
	_observe(prefix + "vapour", _phase(owner, "vapour_fuel_kg"))
	_observe(prefix + "o2", _phase(owner, "o2_kg"))
	_observe(prefix + "co2", _total(owner, "co2_kg"))
	_observe(prefix + "water", _total(owner, "water_vapour_kg"))
	_observe(prefix + "budget", _phase(owner, "thermal_budget_kj"))
	_observe(prefix + "q", _phase(owner, "deposited_heat_kj"))
	_observe(prefix + "sl", _phase(owner, "liquid_sensible_kj"))
	_observe(prefix + "sv", _phase(owner, "vapour_sensible_kj"))
	_observe(prefix + "cost", _total(owner, "release_cost_kj"))
	_observe(prefix + "total", _account(owner, "total_kj"))
	if thermal_accounts:
		_observe(prefix + "heating_l", _total(owner, "heating_liquid_kj"))
		_observe(prefix + "heating_v", _total(owner, "heating_vapour_kj"))
		_observe(prefix + "emitted", _total(owner, "emitted_vapour_sensible_kj"))
		_observe(prefix + "released", _total(owner, "released_liquid_sensible_kj"))
		_observe(prefix + "oxidized_sensible", _total(owner, "oxidized_sensible_kj"))
		_observe(prefix + "chemical", _total(owner, "chemical_oxidation_heat_kj"))


## Independent closure from the declared synthetic numbers, not owner helpers.
func _closes(owner: RefCounted, mass: float, oxygen: float, budget: float, liquid_sensible: float, label: String) -> void:
	var fuel: float = _phase(owner, "liquid_fuel_kg") + _phase(owner, "vapour_fuel_kg")
	_near(fuel + _phase(owner, "o2_kg") + _total(owner, "co2_kg") + _total(owner, "water_vapour_kg"), mass + oxygen, label + " mass")
	_near(fuel + _total(owner, "co2_kg") * 3.0 / 11.0 / 0.75, mass, label + " carbon")
	_near(fuel * 0.25 + _total(owner, "water_vapour_kg") / 9.0, mass * 0.25, label + " hydrogen")
	_near(_phase(owner, "o2_kg") + 4.0 * _total(owner, "oxidized_fuel_kg"), oxygen, label + " oxygen")
	_near(_phase(owner, "liquid_fuel_kg") * 19000.0 + _phase(owner, "vapour_fuel_kg") * 20000.0
		+ _phase(owner, "liquid_sensible_kj") + _phase(owner, "vapour_sensible_kj")
		+ _phase(owner, "thermal_budget_kj") + _phase(owner, "deposited_heat_kj"),
		mass * 19000.0 + liquid_sensible + budget, label + " A+S+B+Q")
	_near(_phase(owner, "thermal_budget_kj") + _total(owner, "heating_liquid_kj")
		+ _total(owner, "heating_vapour_kj") + _total(owner, "release_cost_kj"), budget, label + " B account")
	_near(_phase(owner, "deposited_heat_kj"), 20000.0 * _total(owner, "oxidized_fuel_kg")
		+ _total(owner, "oxidized_sensible_kj"), label + " Q account")
	_near(_phase(owner, "liquid_sensible_kj") + _total(owner, "released_liquid_sensible_kj"),
		liquid_sensible + _total(owner, "heating_liquid_kj"), label + " liquid S account")
	_near(_phase(owner, "vapour_sensible_kj") + _total(owner, "oxidized_sensible_kj"),
		_total(owner, "heating_vapour_kj") + _total(owner, "emitted_vapour_sensible_kj"), label + " vapour S account")
	_near(_account(owner, "total_kj"), mass * 19000.0 + liquid_sensible + budget, label + " reported total")


func _finish() -> void:
	print("G3_SENSIBLE_PHASE_CONTROLLER " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "observations": _observations}))
	if _failed:
		quit(1)
		return
	print("G3_SENSIBLE_PHASE_CONTROLLER_PASS")
	quit(0)


func _generation(owner: RefCounted) -> int:
	var value: Variant = owner.snapshot().get("generation", -1)
	return value if typeof(value) == TYPE_INT else -1


func _time(owner: RefCounted) -> float:
	return _float(owner.snapshot().get("physical_time_s"))


func _phase(owner: RefCounted, key: String) -> float:
	return _float(_section(owner, "phase").get(key))


func _total(owner: RefCounted, key: String) -> float:
	return _float(_section(owner, "totals").get(key))


func _progress(owner: RefCounted, key: String) -> float:
	return _float(_section(owner, "progress").get(key))


func _account(owner: RefCounted, key: String) -> float:
	var report: Dictionary = owner.preview_step(_request(_time(owner))).get("report", {})
	var accounts: Variant = report.get("accounts", {})
	return _float(accounts.get(key)) if typeof(accounts) == TYPE_DICTIONARY else NAN


func _step(result: Dictionary, key: String) -> float:
	var step: Variant = result.get("step", {})
	return _float(step.get(key)) if typeof(step) == TYPE_DICTIONARY else NAN


func _section(owner: RefCounted, name: String) -> Dictionary:
	var value: Variant = owner.snapshot().get(name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _float(value: Variant) -> float:
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else NAN


func _without_generation(snapshot: Dictionary) -> Dictionary:
	var copy: Dictionary = snapshot.duplicate(true)
	copy.erase("generation")
	return copy


func _group(id: String) -> void:
	_groups.append(id)


func _valid(result: Dictionary, label: String) -> void:
	_expect(result.get("valid", false), label + " " + str(result.get("errors")))


func _reject(owner: RefCounted, result: Dictionary, before: Dictionary, label: String) -> void:
	_expect(not result.get("valid", true), label + " rejected")
	_expect(result.get("candidate", {"bad": 1}).is_empty(), label + " no applicable candidate")
	_expect(not result.get("errors", []).is_empty(), label + " explains the rejection")
	_expect(owner.snapshot() == before, label + " no write")
	for key: String in APPROVALS:
		_expect(result.get("report", {}).get(key, true) == false, label + " no approval")


func _observe(key: String, actual: float) -> void:
	# A nonfinite value would not be valid JSON for the contract test.
	_observations[key] = actual if not is_nan(actual) and not is_inf(actual) else null
	_expect(EXPECTED.has(key), key + " is a predeclared oracle")
	_near(actual, float(EXPECTED.get(key, NAN)), key)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= 1.0e-9 + 1.0e-12 * maxf(absf(actual), absf(expected)), label + " observed=" + str(actual))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
