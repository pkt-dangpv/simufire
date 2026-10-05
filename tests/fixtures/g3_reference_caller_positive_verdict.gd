extends SceneTree

## Reference caller: a state is accepted only on an explicit positive verdict.
## The validator is replaced by a controlled test double, never by editing the
## owner, a syntax error or a crash. A double that reports no error and confirms
## nothing must be rejected by every consumer, and must write nothing.
const Controller = preload("res://sim/fire/PrescribedPhaseBudgetController.gd")
const GROUPS: Array[String] = ["_p01", "_p02", "_p03", "_p04", "_p05", "_p06", "_p07", "_p08"]
const DIAGNOSTIC: String = "state validation ended without a positive verdict"
const NO_RESULT: String = "step preview returned no explicit positive result"
const APPROVALS: Array[String] = ["scientific_approval", "predictive_evaporation_approval",
	"engine_integration", "production_activation"]
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: Array[String] = []
var _completed: Array[String] = []


## Controlled substitution of the validator and of the preview result.
class Probe extends "res://sim/fire/PrescribedPhaseBudgetController.gd":
	var calls: int = 0
	var silent_calls: Array = []
	var contradictory_calls: Array = []
	var staged_preview: Dictionary = {}


	func arm(silent: Array = [], contradictory: Array = []) -> void:
		calls = 0
		silent_calls = silent
		contradictory_calls = contradictory


	func _check_owned(value: Variant, context: Dictionary, errors: Array[String]) -> bool:
		calls += 1
		if calls in silent_calls:
			# No error reported and nothing confirmed.
			return false
		if calls in contradictory_calls:
			errors.append("double: reported an error while claiming success")
			return true
		return super._check_owned(value, context, errors)


	func preview_step(end_time_s: Variant, oxidation_requested_kg: Variant) -> Dictionary:
		if not staged_preview.is_empty():
			return staged_preview.duplicate(true)
		return super.preview_step(end_time_s, oxidation_requested_kg)


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


## A probe one valid step into its history, with its validator disarmed.
func _stepped() -> Probe:
	var owner: Probe = Probe.new()
	_accepts(owner.initialize(_context()), "probe initialize")
	_accepts(owner.commit_step(1.0, 0.1, 0), "probe first step")
	owner.arm()
	return owner


func _forged(snapshot: Dictionary) -> Dictionary:
	var forged: Dictionary = snapshot.duplicate(true)
	forged["phase"]["thermal_budget_kj"] = 5000.0
	forged["phase"]["liquid_fuel_kg"] = 0.25
	return forged


## The seam itself changes nothing: an unarmed probe is the real owner.
func _p01() -> void:
	_group("P01")
	var real: RefCounted = Controller.new()
	var probe: Probe = Probe.new()
	_expect(real.initialize(_context()) == probe.initialize(_context()), "seam: same initialize")
	_expect(probe.calls == 1, "initialize consults the validator once")
	_expect(real.commit_step(1.0, 0.1, 0) == probe.commit_step(1.0, 0.1, 0), "seam: same first step")
	_expect(probe.calls == 3, "a step validates the current state and the candidate")
	var saved: Dictionary = _snapshot(real).duplicate(true)
	_expect(real.commit_step(2.0, 0.1, 1) == probe.commit_step(2.0, 0.1, 1), "seam: same second step")
	_expect(real.restore(saved, 2) == probe.restore(saved, 2), "seam: same restore")
	_expect(probe.calls == 7, "restore validates the current state and the requested snapshot")
	_expect(_snapshot(real) == _snapshot(probe), "seam: same final state")
	_near(float(_snapshot(real).get("phase", {}).get("thermal_budget_kj", NAN)), 900.0, "valid input keeps its budget")
	_near(float(_snapshot(real).get("phase", {}).get("deposited_heat_kj", NAN)), 2000.0, "valid input keeps its heat")
	_expect(_snapshot(real).get("generation", -1) == 3, "valid input keeps its generations")
	_completed.append("P01")


## Initialize: no positive verdict, no owner; the instance stays reusable.
func _p02() -> void:
	_group("P02")
	var context: Dictionary = _context()
	var copy: Dictionary = context.duplicate(true)
	var owner: Probe = Probe.new()
	owner.arm([1])
	var refused: Variant = owner.initialize(context)
	_rejects(refused, "initialize without a verdict", true)
	_expect(_snapshot(owner).is_empty(), "initialize without a verdict leaves no owner")
	_expect(owner.get("_context").is_empty(), "initialize without a verdict leaves no context")
	_expect(context == copy, "initialize without a verdict leaves its input untouched")
	_rejects(owner.preview_step(1.0, 0.1), "refused owner is still uninitialized", false)
	owner.arm([], [1])
	refused = owner.initialize(context)
	_rejects(refused, "initialize with a contradictory verdict", false)
	_expect(_has_error(refused, "double: reported"), "the reported error is kept")
	_expect(_snapshot(owner).is_empty(), "contradictory verdict leaves no owner")
	owner.arm()
	_accepts(owner.initialize(context), "the same instance initializes after the refusals")
	var real: RefCounted = Controller.new()
	_accepts(real.initialize(_context()), "real initialize")
	_expect(_snapshot(owner) == _snapshot(real), "it initializes to the canonical state")
	_completed.append("P02")


## Preview: both validations are required, and it stays pure.
func _p03() -> void:
	_group("P03")
	var owner: Probe = _stepped()
	var before: Dictionary = _snapshot(owner).duplicate(true)
	var expected: Variant = owner.preview_step(2.0, 0.1)
	_accepts(expected, "preview on a validated state")
	owner.arm([1])
	_rejects(owner.preview_step(2.0, 0.1), "preview without a verdict on the current state", true)
	_expect(owner.calls == 1, "no candidate is built on an unconfirmed state")
	owner.arm([2])
	_rejects(owner.preview_step(2.0, 0.1), "preview without a verdict on the candidate", true)
	_expect(owner.calls == 2, "the candidate was the unconfirmed one")
	for call: int in [1, 2]:
		owner.arm([], [call])
		var refused: Variant = owner.preview_step(2.0, 0.1)
		_rejects(refused, "preview with a contradictory verdict", false)
		_expect(_has_error(refused, "double: reported"), "preview keeps the reported error")
	owner.arm([1])
	var both: Variant = owner.preview_step(-1.0, 0.1)
	_rejects(both, "preview with a bad argument and no verdict", true)
	_expect(_has_error(both, "end_time_s"), "argument errors are still reported")
	_expect(_snapshot(owner) == before, "rejected previews write nothing")
	owner.arm()
	for i: int in range(3):
		_expect(owner.preview_step(2.0, 0.1) == expected, "repeated preview is identical")
	_expect(_snapshot(owner) == before, "preview stays pure")
	_expect(_snapshot(owner).get("generation", -1) == 1, "preview does not advance the generation")
	_completed.append("P03")


## Commit: nothing is confirmed unless both validations were positive.
func _p04() -> void:
	_group("P04")
	var owner: Probe = _stepped()
	var before: Dictionary = _snapshot(owner).duplicate(true)
	for call: int in [1, 2]:
		owner.arm([call])
		_rejects(owner.commit_step(2.0, 0.1, 1), "commit without a verdict", true)
		_expect(_snapshot(owner) == before, "commit without a verdict writes nothing")
		owner.arm([], [call])
		_rejects(owner.commit_step(2.0, 0.1, 1), "commit with a contradictory verdict", false)
		_expect(_snapshot(owner) == before, "commit with a contradictory verdict writes nothing")
	owner.arm()
	_rejects(owner.commit_step(2.0, 0.1, 0), "stale generation", false)
	_rejects(owner.commit_step(2.0, 0.1, 2), "future generation", false)
	_expect(owner.calls == 0, "a generation conflict is refused before any validation")
	_expect(_snapshot(owner) == before, "generation conflicts write nothing")
	_accepts(owner.commit_step(2.0, 0.1, 1), "valid commit after the refusals")
	_near(float(_snapshot(owner).get("phase", {}).get("thermal_budget_kj", NAN)), 800.0, "budget after the refusals")
	_near(float(_snapshot(owner).get("phase", {}).get("deposited_heat_kj", NAN)), 4000.0, "heat after the refusals")
	_expect(_snapshot(owner).get("generation", -1) == 2, "one generation for the one committed step")
	_rejects(owner.commit_step(3.0, 0.1, 1), "double commit with one generation", false)
	_completed.append("P04")


## Restore: the current state AND the requested snapshot must be confirmed.
func _p05() -> void:
	_group("P05")
	var owner: Probe = _stepped()
	var saved: Dictionary = _snapshot(owner).duplicate(true)
	_accepts(owner.commit_step(2.0, 0.1, 1), "second step")
	owner.arm()
	var before: Dictionary = _snapshot(owner).duplicate(true)
	var expected: Variant = owner.preview_step(3.0, 0.1)
	var forged: Dictionary = _forged(saved)
	var forged_copy: Dictionary = forged.duplicate(true)
	owner.arm([1])
	_rejects(owner.restore(saved, 2), "restore without a verdict on the current state", true)
	_expect(_snapshot(owner) == before, "unconfirmed current state: nothing written")
	owner.arm([2])
	_rejects(owner.restore(forged, 2), "restore of a forged snapshot without a verdict", true)
	_expect(_snapshot(owner) == before, "forged snapshot is not written")
	_near(float(_snapshot(owner).get("phase", {}).get("thermal_budget_kj", NAN)), 800.0, "budget not replaced by the forged one")
	owner.arm([2])
	_rejects(owner.restore(saved, 2), "restore of a coherent snapshot that was not confirmed", true)
	_expect(_snapshot(owner) == before, "unconfirmed snapshot: nothing written")
	owner.arm([1, 2])
	_rejects(owner.restore(saved, 2), "restore with neither verdict", true)
	for call: int in [1, 2]:
		owner.arm([], [call])
		var refused: Variant = owner.restore(saved, 2)
		_rejects(refused, "restore with a contradictory verdict", false)
		_expect(_has_error(refused, "double: reported"), "restore keeps the reported error")
	owner.arm()
	var explained: Variant = owner.restore(forged, 2)
	_rejects(explained, "restore of a forged snapshot, real validator", false)
	_expect(_has_error(explained, "does not close"), "historical messages are kept")
	_expect(not _has_error(explained, DIAGNOSTIC), "no generic diagnostic when the validator explains itself")
	_expect(_snapshot(owner) == before, "every refused restore left the snapshot intact")
	_expect(_snapshot(owner).get("generation", -1) == 2, "every refused restore left the generation intact")
	_expect(owner.preview_step(3.0, 0.1) == expected, "every refused restore left the context intact")
	_expect(forged == forged_copy, "restore does not modify its input")
	owner.arm()
	_accepts(owner.restore(saved, 2), "valid restore after the refusals")
	_expect(_snapshot(owner).get("generation", -1) == 3, "restore assigns a new generation")
	var restored: Dictionary = _snapshot(owner).duplicate(true)
	restored.erase("generation")
	var original: Dictionary = saved.duplicate(true)
	original.erase("generation")
	_expect(restored == original, "valid restore brings back the saved state")
	_completed.append("P05")


## Commit needs an explicit preview result; an absent verdict never writes.
func _p06() -> void:
	_group("P06")
	var owner: Probe = _stepped()
	var before: Dictionary = _snapshot(owner).duplicate(true)
	var genuine: Variant = owner.preview_step(2.0, 0.1)
	_accepts(genuine, "genuine preview")
	var forged: Dictionary = _forged(before)
	forged["generation"] = 2
	var step: Dictionary = {"physical_dt_s": 1.0}
	for staged: Dictionary in [
		{"candidate": forged, "step": step},
		{"valid": null, "candidate": forged, "step": step},
		{"valid": "true", "candidate": forged, "step": step},
		{"valid": 1, "candidate": forged, "step": step},
		{"valid": true, "step": step},
		{"valid": true, "candidate": forged},
		{"valid": true, "candidate": "not a dictionary", "step": step},
		{"valid": true, "candidate": forged, "step": "not a dictionary"},
		{"errors": []},
	]:
		owner.staged_preview = staged
		var refused: Variant = owner.commit_step(2.0, 0.1, 1)
		_rejects(refused, "commit on a preview without an explicit positive result", false)
		_expect(_has_error(refused, NO_RESULT), "commit explains the missing result")
		_expect(_snapshot(owner) == before, "commit without an explicit result writes nothing")
	# An explicit rejection passes through unchanged, as before.
	owner.staged_preview = {"valid": false, "errors": ["staged rejection"], "candidate": {}}
	var passed: Variant = owner.commit_step(2.0, 0.1, 1)
	_rejects(passed, "commit on an explicit preview rejection", false)
	_expect(_has_error(passed, "staged rejection") and not _has_error(passed, NO_RESULT), "the preview rejection is returned as is")
	_expect(_snapshot(owner) == before, "commit on a rejected preview writes nothing")
	owner.staged_preview = {}
	_accepts(owner.commit_step(2.0, 0.1, 1), "commit on the genuine preview")
	_expect(_snapshot(owner) == genuine.get("candidate"), "commit writes exactly the validated candidate")
	_completed.append("P06")


## The verdict itself: true only for a coherent state that reported nothing.
func _p07() -> void:
	_group("P07")
	var owner: RefCounted = Controller.new()
	_accepts(owner.initialize(_context()), "real initialize")
	_accepts(owner.commit_step(1.0, 0.1, 0), "real step")
	var state: Dictionary = _snapshot(owner).duplicate(true)
	var context: Dictionary = owner.get("_context")
	var errors: Array[String] = []
	var verdict: Variant = owner._check_owned(state, context, errors)
	_expect(typeof(verdict) == TYPE_BOOL and verdict and errors.is_empty(), "coherent state: positive verdict, no error")
	_expect(owner._accepted(state, context, errors) and errors.is_empty(), "coherent state: accepted")
	var cases: Dictionary = {}
	var structural: Dictionary = state.duplicate(true)
	structural.erase("totals")
	cases["structural exit"] = structural
	var source: Dictionary = state.duplicate(true)
	source["progress"]["scheduled_kg"] = 0.5
	cases["source exit"] = source
	cases["identity exit"] = _forged(state)
	var clocks: Dictionary = state.duplicate(true)
	clocks["physical_time_s"] = 0.5
	cases["clock mismatch"] = clocks
	var foreign: Dictionary = state.duplicate(true)
	foreign["context_fingerprint"] = "0000"
	cases["foreign context"] = foreign
	for label: String in cases:
		errors = []
		verdict = owner._check_owned(cases[label], context, errors)
		_expect(typeof(verdict) == TYPE_BOOL and not verdict, label + ": negative verdict")
		_expect(not errors.is_empty(), label + ": explained")
		var reported: int = errors.size()
		_expect(not owner._accepted(cases[label], context, errors), label + ": not accepted")
		_expect(not errors.has(DIAGNOSTIC), label + ": no generic diagnostic over a real explanation")
		_expect(errors.size() > reported, label + ": the second check explained itself again")
	# An earlier error in the list does not make a later coherent state invalid,
	# and does not make it accepted by accident either.
	errors = ["earlier error of another check"]
	verdict = owner._check_owned(state, context, errors)
	_expect(typeof(verdict) == TYPE_BOOL and verdict and errors.size() == 1, "verdict is about this call only")
	_expect(_snapshot(owner) == state, "validating writes nothing")
	_completed.append("P07")


## No integration or activation is introduced, and inputs stay untouched.
func _p08() -> void:
	_group("P08")
	var context: Dictionary = _context()
	var copy: Dictionary = context.duplicate(true)
	var owner: Probe = Probe.new()
	var responses: Array = [owner.preview_step(1.0, 0.1)]
	owner.arm([1])
	responses.append(owner.initialize(context))
	owner.arm()
	responses.append(owner.initialize(context))
	owner.arm([2])
	responses.append(owner.commit_step(1.0, 0.1, 0))
	owner.arm()
	responses.append(owner.commit_step(1.0, 0.1, 0))
	owner.arm([2])
	responses.append(owner.restore(_snapshot(owner), 1))
	for response: Variant in responses:
		var report: Dictionary = response.get("report", {}) if typeof(response) == TYPE_DICTIONARY else {}
		for key: String in APPROVALS:
			_expect(report.get(key, true) == false, "no approval " + key)
		_expect(str(report.get("scope")).contains("not_evaporation_prediction"), "report scope unchanged")
	_expect(context == copy, "context input untouched")
	_expect(_snapshot(owner).get("schema") == "g3_prescribed_phase_snapshot_v1", "snapshot schema unchanged")
	_expect(str(_snapshot(owner).keys()) == str(Controller.OWNED_KEYS), "snapshot keys unchanged")
	_completed.append("P08")


func _finish() -> void:
	for id: String in _groups:
		if id not in _completed:
			_failed = true
			_failures.append("group aborted before completing: " + id)
	if _groups.size() != GROUPS.size():
		_failed = true
		_failures.append("not every group started")
	print("G3_REFERENCE_CALLER_POSITIVE_VERDICT " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures}))
	if _failed:
		quit(1)
		return
	print("G3_REFERENCE_CALLER_POSITIVE_VERDICT_PASS")
	quit(0)


func _snapshot(owner: RefCounted) -> Dictionary:
	var value: Variant = owner.snapshot()
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _has_error(result: Variant, text: String) -> bool:
	if typeof(result) != TYPE_DICTIONARY or typeof(result.get("errors")) != TYPE_ARRAY:
		return false
	for error: Variant in result["errors"]:
		if typeof(error) == TYPE_STRING and error.contains(text):
			return true
	return false


func _group(id: String) -> void:
	_groups.append(id)


func _accepts(result: Variant, label: String) -> void:
	_expect(typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result.get("valid"), label + " accepted")


## Structured rejection: valid=false, explicit errors and an empty candidate.
## `diagnosed` states whether the generic missing-verdict diagnostic is expected.
func _rejects(result: Variant, label: String, diagnosed: bool) -> void:
	var data: Dictionary = result if typeof(result) == TYPE_DICTIONARY else {}
	_expect(typeof(data.get("valid")) == TYPE_BOOL and not data.get("valid"), label + " structured valid=false")
	_expect(typeof(data.get("errors")) == TYPE_ARRAY and not data.get("errors").is_empty(), label + " explicit errors")
	_expect(typeof(data.get("candidate")) == TYPE_DICTIONARY and data.get("candidate").is_empty(), label + " empty candidate")
	_expect(_has_error(result, DIAGNOSTIC) == diagnosed, label + (" carries" if diagnosed else " does not carry") + " the missing-verdict diagnostic")


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= 1.0e-9 + 1.0e-12 * maxf(absf(actual), absf(expected)), label + " observed=" + str(actual))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
