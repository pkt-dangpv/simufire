extends SceneTree

## Numerical replay of measured LIQUID reservoir depletion, not gas emission.
## No FuelMassBudgetModel, oxidation, O2, HRR, solid inventory or engine here.
const Release = preload("res://sim/fire/PrescribedFuelReleaseModel.gd")
const TOL: float = 1.0e-9
var _checks: int = 0
var _failed: bool = false
var _failures: Array[String] = []
var _max_error: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/g3_isohept9_measured_replay.json"))
	var program: Dictionary = data["program"]
	var observations: Array = data["observations"]
	_check(data["mass_tolerance_kg"] == TOL, "predeclared numerical tolerance unchanged")
	_check(not data["scientific_approval"] and not data["engine_integration"] and not data["production_activation"], "not an approved engine profile")
	_check(observations.size() == 101, "all measured nodes in predeclared window")
	var initialized: Dictionary = Release.initial_progress(program)
	_check(initialized.get("valid", false), "measured rate program valid " + str(initialized.get("errors")))
	if not initialized.get("valid", false):
		_finish({})
		return
	var start: Dictionary = initialized["candidate"]
	var nodes: Array = []
	for row in observations:
		if row["time_s"] > 0.0:
			nodes.append(row["time_s"])
	var regular: Array = []
	for i in range(1, 401):
		regular.append(i * 1.25)
	var irregular: Array = []
	var steps: Array = [0.3, 4.9, 7.7, 1.25, 11.8]
	var t: float = 0.0
	var index: int = 0
	while t < 500.0:
		t = minf(500.0, t + float(steps[index % steps.size()]))
		irregular.append(t)
		index += 1
	var coarse: Dictionary = _campaign(program, observations, nodes)
	var fine: Dictionary = _campaign(program, observations, regular)
	var crossed: Dictionary = _campaign(program, observations, irregular)
	var whole: Dictionary = _campaign(program, observations, [500.0])
	for result in [coarse, fine, crossed, whole]:
		_near(float(result.get("remaining_kg", -1.0)), 0.306292, "measured mass at 500 s retained")
		_near(float(result.get("progress", {}).get("scheduled_kg", -1.0)), 19.359537, "measured net decrease retained")
		_near(float(result.get("progress", {}).get("rejected_kg", -1.0)), 0.0, "no invented rejection")
	var preview: Dictionary = Release.propose(program, start, 5.0)
	_near(float(preview.get("release_kg", -1.0)), 19.665829 - 19.634843, "first interval uses left rate, not trapezoid")
	_check(preview.get("scope") == "measured_depletion_replay_not_emission_calibration", "quantity remains measured depletion")
	var stable: String = var_to_str([program, start])
	_check(preview == Release.propose(program, start, 5.0), "preview deterministic")
	_check(var_to_str([program, start]) == stable, "preview no input mutation")
	var first: Dictionary = Release.acknowledge(program, start, 5.0, preview.get("release_kg", -1.0))
	_check(first.get("valid", false), "first commit valid")
	if not first.get("valid", false):
		_finish({})
		return
	var restored: Dictionary = first.get("candidate", {}).duplicate(true)
	_check(Release.propose(program, restored, 10.0) == Release.propose(program, first.get("candidate", {}), 10.0), "restored cursor repeats next proposal")
	var saved: Dictionary = {"progress": restored, "remaining_kg": 19.634843}
	var resumed: Dictionary = _campaign(program, observations, [6.1, 12.3, 77.7, 250.0, 500.0], saved)
	_near(float(resumed.get("remaining_kg", -1.0)), float(coarse.get("remaining_kg", -2.0)), "joint cursor/reservoir snapshot restart")
	_invalid(Release.acknowledge(program, restored, 5.0, 0.01), "duplicate nonzero acknowledgement")
	_invalid(Release.propose(program, restored, 4.0), "backwards time")
	_invalid(Release.propose(program, start, 500.01), "no tail extrapolation")
	var rejected: Dictionary = Release.acknowledge(program, start, 5.0, 0.0)
	_check(rejected.get("valid", false), "synthetic full refusal valid")
	if not rejected.get("valid", false):
		_finish({})
		return
	var after: Dictionary = Release.propose(program, rejected.get("candidate", {}), 10.0)
	_near(float(after.get("release_kg", -1.0)), 19.634843 - float(observations[2]["mass_kg"]), "refusal not queued into next interval")
	# Synthetic cap: reservoir has less available mass than the measured program.
	var capped: Dictionary = Release.acknowledge(program, start, 500.0, 0.1)
	_check(capped.get("valid", false), "synthetic availability cap valid")
	_near(float(capped.get("candidate", {}).get("rejected_kg", -1.0)), 19.259537, "cap rejects remainder, not emitted")
	var altered: Dictionary = program.duplicate(true)
	altered["samples"][1]["rate_kg_s"] *= 0.5
	_invalid(Release.propose(altered, restored, 10.0), "changed rates invalidate cursor")
	for key in ["unit", "quantity", "interpolation"]:
		altered = program.duplicate(true)
		altered[key] = "unsupported"
		_invalid(Release.initial_progress(altered), "unsupported measured convention " + key)
	altered = program.duplicate(true)
	altered["quantity"] = "modeled_component_emission"
	_invalid(Release.initial_progress(altered), "do not relabel measured depletion as emission")
	altered = program.duplicate(true)
	altered["samples"][-1]["rate_kg_s"] = 0.01
	_invalid(Release.initial_progress(altered), "terminal rate must be zero")
	altered = program.duplicate(true)
	altered["samples"].remove_at(1)
	_invalid(Release.propose(altered, restored, 10.0), "omitted interval changes identity")
	altered = program.duplicate(true)
	altered["initial_mass_kg"] = 19.0
	_invalid(Release.initial_progress(altered), "measured demand exceeds declared reservoir")
	_finish({"node": coarse, "subdivided": fine, "irregular": crossed, "whole": whole})


func _campaign(program: Dictionary, observations: Array, ends: Array, snapshot: Dictionary = {}) -> Dictionary:
	var initialized: Dictionary = Release.initial_progress(program)
	var progress: Dictionary = snapshot.get("progress", initialized.get("candidate", {})).duplicate(true)
	var remaining: float = float(snapshot.get("remaining_kg", program["initial_mass_kg"]))
	# Coherent initial snapshot is an independent caller responsibility.
	_near(remaining, _expected_mass(observations, float(progress["time_s"])), "snapshot coherent")
	for end in ends:
		var preview: Dictionary = Release.propose(program, progress, end)
		_check(preview.get("valid", false), "campaign preview " + str(preview.get("errors")))
		if not preview.get("valid", false):
			return {}
		var demand: float = float(preview["release_kg"])
		var accepted: float = minf(remaining, demand)
		var ack: Dictionary = Release.acknowledge(program, progress, end, accepted)
		_check(ack.get("valid", false), "campaign acknowledgement " + str(ack.get("errors")))
		if not ack.get("valid", false):
			return {}
		# Local atomic snapshot only. NOT the physical engine applicator.
		remaining -= accepted
		progress = ack["candidate"]
		_near(remaining, _expected_mass(observations, float(end)), "mass trace retained at campaign endpoint")
		_near(remaining + float(progress["accepted_kg"]), float(program["initial_mass_kg"]), "reservoir + accepted conserves initial mass")
	return {"remaining_kg": remaining, "progress": progress, "steps": ends.size()}


func _expected_mass(observations: Array, time: float) -> float:
	for i in range(observations.size() - 1):
		var a: Dictionary = observations[i]
		var b: Dictionary = observations[i + 1]
		if time >= float(a["time_s"]) and time <= float(b["time_s"]):
			# Linear mass is the declared reconstruction; no claim of measured
			# instantaneous evaporation between the original five-second samples.
			var fraction: float = (time - float(a["time_s"])) / (float(b["time_s"]) - float(a["time_s"]))
			return (1.0 - fraction) * float(a["mass_kg"]) + fraction * float(b["mass_kg"])
	return -1.0


func _invalid(value: Dictionary, label: String) -> void:
	_check(not value.get("valid", true) and not value.get("errors", []).is_empty(), label)


func _near(actual: float, expected: float, label: String) -> void:
	var error: float = absf(actual - expected)
	_max_error = maxf(_max_error, error)
	_check(not is_nan(actual) and not is_inf(actual) and error <= TOL, label)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed = true
		_failures.append(label)


func _finish(results: Dictionary) -> void:
	print("G3_MEASURED_MASS_REPLAY " + JSON.stringify({"checks": _checks, "failures": _failures,
		"max_mass_error_kg": _max_error, "campaigns": results}))
	if not _failed:
		print("G3_MEASURED_MASS_REPLAY_PASS")
		quit(0)
	else:
		quit(1)
