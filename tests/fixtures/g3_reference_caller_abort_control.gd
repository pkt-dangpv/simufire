extends SceneTree

## ABORT CONTROL, not part of the normal suite. It deliberately provokes real
## script errors: the validator double aborts half way, as an unforeseen fault
## would. The normal suite must emit no script error; this control must emit
## exactly the ones it provokes, all of them on the marked line of THIS file.
## Run only through scripts/simulation/run_g3_positive_verdict_mutations.py
## --abort-control, in an isolated project and under the monitor.
const Controller = preload("res://sim/fire/PrescribedPhaseBudgetController.gd")
const GROUPS: Array[String] = ["_k01", "_k02", "_k03", "_k04"]
const DIAGNOSTIC: String = "state validation ended without a positive verdict"
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: Array[String] = []
var _completed: Array[String] = []
var _aborts: int = 0
var _observations: Dictionary = {}


## A validator that really aborts on the chosen calls and adds no error.
class Aborting extends "res://sim/fire/PrescribedPhaseBudgetController.gd":
	var calls: int = 0
	var abort_calls: Array = []
	var aborted: int = 0


	func arm(aborting: Array = []) -> void:
		calls = 0
		abort_calls = aborting


	func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> bool:
		calls += 1
		if calls in abort_calls:
			aborted += 1
			var number: Variant = 1
			var text: Variant = "text"
			if number != text:  # ABORT LINE: a real script error stops this function here.
				pass
			# Never reached. If the abort went unnoticed this would be an acceptance.
			return true
		return super._check_owned(value, context, errors)


func _initialize() -> void:
	for group: String in GROUPS:
		call_deferred(group)
	call_deferred("_finish")


func _context() -> Dictionary:
	return {"schema": "g3_prescribed_phase_context_v1",
		"program": {"profile_id": "synthetic_constant", "component_id": "synthetic_observed_reservoir",
			"initial_mass_kg": 1.0, "mode": "prescribed", "quantity": "measured_reservoir_depletion",
			"unit": "kg/s", "time_origin": "synthetic_zero", "outside_domain": "reject",
			"interpolation": "piecewise_constant_left",
			"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.0}]},
		"material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid", "vapour_phase": "gas",
			"reference_temperature_k": 298.15, "reference_pressure_pa": 100000.0, "water_product_phase": "gas",
			"atom_mass_basis": "nominal_C12_H1_O16", "chemical_energy_basis": "complete_oxidation_net",
			"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0}, "liquid_heat_kj_kg": 19000.0,
			"vapour_heat_kj_kg": 20000.0, "phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic:not_heptane"},
		"attribution": {"input_component_id": "synthetic_observed_reservoir", "modeled_component_id": "synthetic_component",
			"input_quantity": "measured_reservoir_depletion", "rule": "all_depletion_as_reference_vapour",
			"status": "conditional_not_measured_emission", "provenance": "synthetic:no_experimental_approval"},
		"seed": {"initial_o2_kg": 10.0, "initial_thermal_budget_kj": 1000.0,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"}}


func _stepped() -> Aborting:
	var owner: Aborting = Aborting.new()
	_accepts(owner.initialize(_context()), "control initialize")
	_accepts(owner.commit_step(1.0, 0.1, 0), "control first step")
	owner.arm()
	return owner


## What the caller of an aborted validator actually receives.
func _k01() -> void:
	_group("K01")
	var owner: Aborting = _stepped()
	var errors: Array[String] = []
	owner.arm([1])
	var verdict: Variant = owner._check_owned(owner.snapshot(), owner.get("_context"), errors)
	_aborts += owner.aborted
	_observations["aborted_verdict"] = type_string(typeof(verdict)) + ":" + str(verdict)
	_observations["errors_added_by_abort"] = errors.size()
	_expect(typeof(verdict) == TYPE_BOOL and not verdict, "an aborted validator yields a negative verdict")
	_expect(errors.is_empty(), "an aborted validator reports no error: the old decision would have accepted")
	_completed.append("K01")


## Initialize: a validator that aborts initializes nothing.
func _k02() -> void:
	_group("K02")
	var owner: Aborting = Aborting.new()
	owner.arm([1])
	_rejects(owner.initialize(_context()), "initialize with an aborted validation")
	_aborts += owner.aborted
	_expect(owner.snapshot().is_empty() and owner.get("_context").is_empty(), "aborted validation leaves no owner")
	owner.arm()
	_accepts(owner.initialize(_context()), "the same instance initializes afterwards")
	_completed.append("K02")


## Step: an aborted validation of the state or of the candidate confirms nothing.
func _k03() -> void:
	_group("K03")
	var owner: Aborting = _stepped()
	var before: Dictionary = owner.snapshot().duplicate(true)
	var seen: int = owner.aborted
	for call: int in [1, 2]:
		owner.arm([call])
		_rejects(owner.preview_step(2.0, 0.1), "preview with an aborted validation")
		owner.arm([call])
		_rejects(owner.commit_step(2.0, 0.1, 1), "commit with an aborted validation")
		_expect(owner.snapshot() == before, "aborted validation writes nothing")
	_aborts += owner.aborted - seen
	owner.arm()
	_accepts(owner.commit_step(2.0, 0.1, 1), "valid commit afterwards")
	_expect(owner.snapshot().get("generation", -1) == 2, "one generation for the one committed step")
	_completed.append("K03")


## Restore: the forged snapshot that used to be written is refused.
func _k04() -> void:
	_group("K04")
	var owner: Aborting = _stepped()
	var saved: Dictionary = owner.snapshot().duplicate(true)
	_accepts(owner.commit_step(2.0, 0.1, 1), "second step")
	var before: Dictionary = owner.snapshot().duplicate(true)
	var forged: Dictionary = saved.duplicate(true)
	forged["phase"]["thermal_budget_kj"] = 5000.0
	forged["phase"]["liquid_fuel_kg"] = 0.25
	var seen: int = owner.aborted
	for call: int in [1, 2]:
		owner.arm([call])
		_rejects(owner.restore(forged, 2), "restore of a forged snapshot with an aborted validation")
		_expect(owner.snapshot() == before, "forged snapshot not written")
		owner.arm([call])
		_rejects(owner.restore(saved, 2), "restore of a coherent snapshot with an aborted validation")
		_expect(owner.snapshot() == before, "unconfirmed snapshot not written")
	_aborts += owner.aborted - seen
	_expect(owner.snapshot().get("generation", -1) == 2, "generation intact")
	owner.arm()
	_accepts(owner.restore(saved, 2), "valid restore afterwards")
	_completed.append("K04")


func _finish() -> void:
	for id: String in _groups:
		if id not in _completed:
			_failed = true
			_failures.append("group aborted before completing: " + id)
	if _groups.size() != GROUPS.size():
		_failed = true
		_failures.append("not every group started")
	print("G3_REFERENCE_CALLER_ABORT_CONTROL " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "provoked_aborts": _aborts, "observations": _observations}))
	if _failed:
		quit(1)
		return
	print("G3_REFERENCE_CALLER_ABORT_CONTROL_PASS")
	quit(0)


func _group(id: String) -> void:
	_groups.append(id)


func _accepts(result: Variant, label: String) -> void:
	_expect(typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result.get("valid"), label + " accepted")


func _rejects(result: Variant, label: String) -> void:
	var data: Dictionary = result if typeof(result) == TYPE_DICTIONARY else {}
	_expect(typeof(data.get("valid")) == TYPE_BOOL and not data.get("valid"), label + " structured valid=false")
	_expect(typeof(data.get("errors")) == TYPE_ARRAY and data.get("errors").has(DIAGNOSTIC), label + " carries the missing-verdict diagnostic")
	_expect(typeof(data.get("candidate")) == TYPE_DICTIONARY and data.get("candidate").is_empty(), label + " empty candidate")


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
