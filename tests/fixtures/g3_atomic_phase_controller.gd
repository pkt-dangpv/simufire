extends SceneTree

const Controller = preload("res://sim/fire/PrescribedPhaseBudgetController.gd")
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _context(budget: float = 1000.0, oxygen: float = 10.0, linear: bool = false) -> Dictionary:
	var id: String = "synthetic_component" if linear else "synthetic_observed_reservoir"
	return {
		"schema": "g3_prescribed_phase_context_v1",
		"program": {"profile_id": "synthetic_constant", "component_id": id, "initial_mass_kg": 1.0,
			"mode": "prescribed", "quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
			"unit": "kg/s", "time_origin": "synthetic_zero", "outside_domain": "reject",
			"interpolation": "piecewise_linear" if linear else "piecewise_constant_left",
			"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.0}]},
		"material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid", "vapour_phase": "gas",
			"reference_temperature_k": 298.15, "reference_pressure_pa": 100000.0, "water_product_phase": "gas",
			"atom_mass_basis": "nominal_C12_H1_O16", "chemical_energy_basis": "complete_oxidation_net",
			"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0}, "liquid_heat_kj_kg": 19000.0,
			"vapour_heat_kj_kg": 20000.0, "phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic:not_heptane"},
		"attribution": {"input_component_id": id, "modeled_component_id": "synthetic_component",
			"input_quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
			"rule": "same_declared_component" if linear else "all_depletion_as_reference_vapour",
			"status": "synthetic_declared_emission" if linear else "conditional_not_measured_emission",
			"provenance": "synthetic:no_experimental_approval"},
		"seed": {"initial_o2_kg": oxygen, "initial_thermal_budget_kj": budget,
			"energy_boundary_kind": "synthetic_independent_initial_budget", "energy_boundary_provenance": "synthetic:independent_seed"},
	}


func _new(context: Dictionary = _context()) -> RefCounted:
	var owner: RefCounted = Controller.new()
	_valid(owner.initialize(context), "initialize")
	return owner


func _commit(owner: RefCounted, end: float, oxidation: float) -> Dictionary:
	var result: Dictionary = owner.commit_step(end, oxidation, owner.snapshot()["generation"])
	_valid(result, "commit")
	if not result.get("valid", false):
		# Preserve the behavioral failure above; keep a broken mutant from
		# turning subsequent fixture lookups into an unrelated script error.
		result["step"] = {"physical_dt_s": -1.0, "source_dt_s": -1.0, "requested_release_kg": -1.0,
			"accepted_release_kg": -1.0, "rejected_release_kg": -1.0, "accepted_oxidation_kg": -1.0}
		result["no_op"] = false
	return result


func _run() -> void:
	_group("A01")
	var context: Dictionary = _context()
	var owner: RefCounted = _new(context)
	var before: String = var_to_str(owner.snapshot())
	var preview: Dictionary = owner.preview_step(1.0, 0.1)
	_valid(preview, "preview")
	if not preview.get("valid", false):
		_finish()
		return
	_expect(owner.preview_step(1.0, 0.1) == preview, "deterministic preview")
	_expect(var_to_str(owner.snapshot()) == before, "preview does not write")
	context["seed"]["initial_thermal_budget_kj"] = 0.0
	context["program"]["samples"][0]["rate_kg_s"] = 0.0
	_expect(owner.preview_step(1.0, 0.1) == preview, "context deep copy")
	var exported: Dictionary = owner.snapshot()
	exported["phase"]["liquid_fuel_kg"] = 0.0
	_expect(var_to_str(owner.snapshot()) == before, "snapshot deep copy")
	if _failed:
		# An aliased snapshot has already corrupted this owner. Record that
		# behavioral failure and stop before unrelated restore lookups fail.
		_finish()
		return
	preview["candidate"]["phase"]["thermal_budget_kj"] = 0.0
	preview["report"]["confirmed"]["phase"]["liquid_fuel_kg"] = 0.0
	_expect(var_to_str(owner.snapshot()) == before, "preview/report cannot mutate owner")
	_reject(owner, owner.initialize(_context()), before, "reinitialize forbidden")

	_group("A02")
	var result: Dictionary = _commit(owner, 1.0, 0.1)
	var state: Dictionary = owner.snapshot()
	_near(state["phase"]["liquid_fuel_kg"], 0.9, false, "liquid debit")
	_near(state["phase"]["vapour_fuel_kg"], 0.0, false, "burned vapor")
	_near(state["phase"]["o2_kg"], 9.6, false, "oxygen debit")
	_near(state["phase"]["thermal_budget_kj"], 900.0, true, "phase debit")
	_near(state["phase"]["deposited_heat_kj"], 2000.0, true, "vapor oxidation heat")
	_near(state["totals"]["co2_kg"], 0.275, false, "CO2")
	_near(state["totals"]["water_vapour_kg"], 0.225, false, "water")
	_near(result["step"]["accepted_release_kg"], 0.1, false, "accepted release")
	_expect(state["generation"] == 1, "single generation")
	_check_totals(state, 1000.0, 10.0)

	_group("A03")
	var no_oxygen: RefCounted = _new(_context(1000.0, 0.0))
	_commit(no_oxygen, 1.0, 0.1)
	state = no_oxygen.snapshot()
	_near(state["phase"]["vapour_fuel_kg"], 0.1, false, "stored unoxidized vapor")
	_near(state["phase"]["deposited_heat_kj"], 0.0, true, "no oxygen no heat")
	_check_totals(state, 1000.0, 0.0)

	_group("A04")
	var capped: RefCounted = _new(_context(50.0))
	result = _commit(capped, 1.0, 0.1)
	_near(result["step"]["accepted_release_kg"], 0.05, false, "cap accepted")
	_near(result["step"]["rejected_release_kg"], 0.05, false, "cap rejected")
	_near(capped.snapshot()["phase"]["deposited_heat_kj"], 1000.0, true, "cap heat")
	_near(capped.snapshot()["progress"]["time_s"], 1.0, false, "cap advances source")
	_check_totals(capped.snapshot(), 50.0, 10.0)

	_group("A05")
	var no_budget: RefCounted = _new(_context(0.0))
	_commit(no_budget, 1.0, 0.1)
	_near(no_budget.snapshot()["phase"]["liquid_fuel_kg"], 1.0, false, "no budget no debit")
	_near(no_budget.snapshot()["progress"]["rejected_kg"], 0.1, false, "no budget rejection")
	_expect(no_budget.snapshot()["generation"] == 1, "zero acceptance still commits clock")

	_group("A06")
	var limited: RefCounted = _new(_context(1000.0, 0.2))
	result = _commit(limited, 1.0, 0.1)
	_near(result["step"]["accepted_release_kg"], 0.1, false, "oxygen must not restrict transfer")
	_near(result["step"]["accepted_oxidation_kg"], 0.05, false, "oxygen cap")
	_near(limited.snapshot()["phase"]["vapour_fuel_kg"], 0.05, false, "limited stored vapor")
	_check_totals(limited.snapshot(), 1000.0, 0.2)

	_group("A07")
	result = _commit(capped, 2.0, 1.0)
	_near(result["step"]["requested_release_kg"], 0.1, false, "do not reemit rejected prefix")
	_near(result["step"]["accepted_release_kg"], 0.0, false, "Q is not available B")
	_near(capped.snapshot()["progress"]["rejected_kg"], 0.15, false, "cumulative rejection")
	_near(capped.snapshot()["phase"]["deposited_heat_kj"], 1000.0, true, "no new heat")

	_group("A08")
	before = var_to_str(owner.snapshot())
	_reject(owner, owner.commit_step(1.0, 0.1, 0), before, "stale/double commit")
	_reject(owner, owner.commit_step(2.0, 0.1, 0), before, "stale new endpoint")

	_group("A09")
	var mixed: Dictionary = owner.snapshot()
	var fresh: RefCounted = _new()
	mixed["progress"] = fresh.snapshot()["progress"]
	_reject(owner, owner.restore(mixed, 1), before, "mixed history")
	mixed["physical_time_s"] = 0.0
	_reject(owner, owner.restore(mixed, 1), before, "mixed history even when clocks agree")

	_group("A10")
	var saved: Dictionary = owner.snapshot()
	_commit(owner, 2.0, 0.1)
	var second: Dictionary = owner.snapshot()
	_valid(owner.restore(saved, 2), "restore complete")
	_expect(owner.snapshot()["generation"] == 3, "restore uses current generation")
	before = var_to_str(owner.snapshot())
	_reject(owner, owner.commit_step(2.0, 0.1, 1), before, "old intent invalid after restore")
	_commit(owner, 2.0, 0.1)
	var replayed: Dictionary = owner.snapshot()
	second.erase("generation")
	replayed.erase("generation")
	_expect(second == replayed, "coherent restored replay")

	_group("A11")
	for family in ["material", "seed", "attribution"]:
		context = _context()
		if family == "material":
			context["material"]["liquid_heat_kj_kg"] += 10.0
			context["material"]["vapour_heat_kj_kg"] += 10.0
		elif family == "seed":
			context["seed"]["initial_thermal_budget_kj"] = 2000.0
		else:
			context["attribution"]["provenance"] = "synthetic:different_attribution"
		var foreign: RefCounted = _new(context)
		before = var_to_str(foreign.snapshot())
		_reject(foreign, foreign.restore(saved, 0), before, "context mismatch " + family)
	# Identity must also reject changes that leave every physical number equal.
	for family in ["material", "seed"]:
		context = _context()
		if family == "material":
			context["material"]["provenance"] = "synthetic:different_material_identity"
		else:
			context["seed"]["energy_boundary_provenance"] = "synthetic:different_boundary_identity"
		var identity_owner: RefCounted = _new(context)
		before = var_to_str(identity_owner.snapshot())
		_reject(identity_owner, identity_owner.restore(fresh.snapshot(), 0), before, "physical equality not identity " + family)

	_group("A12")
	var uninitialized: RefCounted = Controller.new()
	_expect(not uninitialized.preview_step(1.0, 0.1)["valid"], "uninitialized preview")
	_expect(not uninitialized.commit_step(1.0, 0.1, 0)["valid"], "uninitialized commit")
	for bad in [true, -1.0, INF, NAN, "1", {}, null]:
		before = var_to_str(owner.snapshot())
		_reject(owner, owner.commit_step(bad, 0.1, owner.snapshot()["generation"]), before, "invalid time")
		_reject(owner, owner.commit_step(3.0, bad, owner.snapshot()["generation"]), before, "invalid oxidation")
		_reject(owner, owner.commit_step(3.0, 0.1, bad), before, "invalid generation")
		_reject(owner, owner.restore(bad, owner.snapshot()["generation"]), before, "invalid snapshot")
	for family in ["context", "program", "material", "attribution", "seed"]:
		context = _context()
		var target: Dictionary = context if family == "context" else context[family]
		target["unexpected"] = 1.0
		_expect(not Controller.new().initialize(context)["valid"], "extra context field " + family)
		context = _context()
		target = context if family == "context" else context[family]
		target.erase(target.keys()[0])
		_expect(not Controller.new().initialize(context)["valid"], "missing context field " + family)
	for field in ["initial_o2_kg", "initial_thermal_budget_kj"]:
		for bad in [true, INF, NAN, -1.0, "1"]:
			context = _context()
			context["seed"][field] = bad
			_expect(not Controller.new().initialize(context)["valid"], "invalid seed")
	context = _context()
	context["attribution"]["status"] = "measured_emission"
	_expect(not Controller.new().initialize(context)["valid"], "no measured emission promotion")
	context = _context()
	context["attribution"]["input_component_id"] = "foreign"
	_expect(not Controller.new().initialize(context)["valid"], "association mismatch")
	context = _context()
	context["seed"]["energy_boundary_kind"] = "measured_from_HRR"
	_expect(not Controller.new().initialize(context)["valid"], "no HRR funding")

	_group("A13")
	var tail: RefCounted = _new()
	_commit(tail, 2.0, 0.0)
	result = _commit(tail, 3.0, 0.1)
	_near(result["step"]["requested_release_kg"], 0.0, false, "no tail release")
	_near(result["step"]["physical_dt_s"], 1.0, false, "physical tail time")
	_near(result["step"]["source_dt_s"], 0.0, false, "source cursor stopped")
	_near(result["step"]["accepted_oxidation_kg"], 0.1, false, "tail oxidation remains possible")
	_expect(result["report"]["source_finished"], "source finished")
	_near(tail.snapshot()["phase"]["vapour_fuel_kg"], 0.1, false, "remaining vapor not extinguished")
	_expect(not result["report"].has("fire_extinguished"), "no inferred extinction")
	_check_totals(tail.snapshot(), 1000.0, 10.0)

	_group("A14")
	var crossing: RefCounted = _new()
	_commit(crossing, 1.5, 0.0)
	result = _commit(crossing, 2.5, 0.0)
	_near(result["step"]["requested_release_kg"], 0.05, false, "crossing interval only")
	_near(result["step"]["physical_dt_s"], 1.0, false, "crossing physical dt")
	_near(result["step"]["source_dt_s"], 0.5, false, "crossing source dt")
	_near(crossing.snapshot()["physical_time_s"], 2.5, false, "not truncating physical clock")
	_near(crossing.snapshot()["progress"]["time_s"], 2.0, false, "no source extrapolation")

	_group("A15")
	before = var_to_str(tail.snapshot())
	result = _commit(tail, 3.0, 1.0)
	_expect(result["no_op"], "zero dt no-op")
	_expect(var_to_str(tail.snapshot()) == before, "zero dt generation/state intact")
	_near(result["step"]["accepted_oxidation_kg"], 0.0, false, "zero dt cannot burn")

	_group("A16")
	for key in ["thermal_budget_kj", "deposited_heat_kj", "o2_kg", "liquid_fuel_kg", "vapour_fuel_kg"]:
		mixed = tail.snapshot()
		mixed["phase"][key] += 0.01
		_reject(tail, tail.restore(mixed, tail.snapshot()["generation"]), before, "tampered phase " + key)
	for key in ["oxidized_fuel_kg", "co2_kg", "water_vapour_kg"]:
		mixed = tail.snapshot()
		mixed["totals"][key] += 0.01
		_reject(tail, tail.restore(mixed, tail.snapshot()["generation"]), before, "tampered totals " + key)

	_group("A17")
	context = _context(1.1e308)
	context["program"]["initial_mass_kg"] = 4.0e303
	var overflow: RefCounted = Controller.new()
	_expect(not overflow.initialize(context)["valid"], "finite terms nonfinite aggregate")
	_expect(overflow.snapshot().is_empty(), "overflow cannot initialize half an owner")
	var exhausted_generation: Dictionary = tail.snapshot()
	exhausted_generation["generation"] = Controller.MAX_GENERATION
	# Direct reflection used only as a test seam; not a supported public restore.
	var at_limit: RefCounted = _new()
	at_limit.set("_owned", exhausted_generation)
	before = var_to_str(at_limit.snapshot())
	_reject(at_limit, at_limit.commit_step(4.0, 0.1, Controller.MAX_GENERATION), before, "generation overflow commit")
	_reject(at_limit, at_limit.restore(saved, Controller.MAX_GENERATION), before, "generation overflow restore")

	_group("A18")
	for linear in [false, true]:
		var whole: RefCounted = _new(_context(1000.0, 10.0, linear))
		_commit(whole, 2.0, 1.0)
		for times in [[0.5, 1.0, 1.5, 2.0], [0.13, 0.87, 1.23, 2.0]]:
			var divided: RefCounted = _new(_context(1000.0, 10.0, linear))
			for end in times:
				_commit(divided, end, 1.0)
			for key in Controller.Budget.PHASE_STATE_KEYS:
				_near(divided.snapshot()["phase"][key], whole.snapshot()["phase"][key], key.ends_with("_kj"), "partition phase " + key)
			for key in Controller.TOTAL_KEYS:
				_near(divided.snapshot()["totals"][key], whole.snapshot()["totals"][key], false, "partition products " + key)
			_near(divided.snapshot()["progress"]["accepted_kg"], 0.1 if linear else 0.2, false, "partition integral")

	_group("A19")
	mixed = capped.snapshot()
	mixed["progress"]["accepted_kg"] = 0.2
	mixed["progress"]["rejected_kg"] = 0.0
	before = var_to_str(capped.snapshot())
	_reject(capped, capped.restore(mixed, capped.snapshot()["generation"]), before, "balanced cursor cannot restore fuel independently")

	_group("A20")
	for response in [owner.preview_step(3.0, 0.0), owner.commit_step(3.0, 0.0, -1),
		owner.restore(saved, owner.snapshot()["generation"]), owner.commit_step(3.0, 0.0, owner.snapshot()["generation"])]:
		var report: Dictionary = response["report"]
		_expect(report["confirmed"] == response.get("snapshot", owner.snapshot()) if not response.has("candidate") else report["confirmed"] != response["candidate"], "report is confirmed not preview")
		for key in ["scientific_approval", "predictive_evaporation_approval", "engine_integration", "production_activation"]:
			_expect(report[key] == false, "no approval " + key)
		_expect(report["attribution"]["status"] == "conditional_not_measured_emission", "report carries conditional attribution")
	# Snapshot imports are coherency checks, not historical authenticity proofs.
	_finish()


func _finish() -> void:
	print("G3_ATOMIC_PHASE_CONTROLLER " + JSON.stringify({"checks": _checks, "groups": _groups, "failures": _failures}))
	if _failed:
		quit(1)
		return
	print("G3_ATOMIC_PHASE_CONTROLLER_PASS")
	quit(0)


func _check_totals(state: Dictionary, budget: float, oxygen: float) -> void:
	var phase: Dictionary = state["phase"]
	var products: Dictionary = state["totals"]
	_near(float(phase["liquid_fuel_kg"]) + float(phase["vapour_fuel_kg"]) + float(phase["o2_kg"]) + float(products["co2_kg"]) + float(products["water_vapour_kg"]), 1.0 + oxygen, false, "independent mass total")
	_near(float(phase["liquid_fuel_kg"]) * 19000.0 + float(phase["vapour_fuel_kg"]) * 20000.0 + float(phase["thermal_budget_kj"]) + float(phase["deposited_heat_kj"]), 19000.0 + budget, true, "independent energy total")
	_near(float(phase["liquid_fuel_kg"]) + float(phase["vapour_fuel_kg"]) + float(products["co2_kg"]) * 3.0 / 11.0 / 0.75, 1.0, false, "independent carbon total")
	_near((float(phase["liquid_fuel_kg"]) + float(phase["vapour_fuel_kg"])) * 0.25 + float(products["water_vapour_kg"]) / 9.0, 0.25, false, "independent hydrogen total")


func _group(id: String) -> void:
	_groups.append(id)


func _valid(result: Dictionary, label: String) -> void:
	_expect(result.get("valid", false), label + " " + str(result.get("errors")))


func _reject(owner: RefCounted, result: Dictionary, before: String, label: String) -> void:
	_expect(not result.get("valid", true), label + " rejected")
	_expect(result.get("candidate", {}).is_empty(), label + " no applicable candidate")
	_expect(var_to_str(owner.snapshot()) == before, label + " no partial write")


func _near(actual: float, expected: float, energy: bool, label: String) -> void:
	var tol: float = 1.0e-9 if energy else 1.0e-12
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= tol + 1.0e-12 * maxf(absf(actual), absf(expected)), label)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
