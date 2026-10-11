extends RefCounted

## Isolated prescribed mass boundary, NOT pyrolysis prediction or engine integration.
## The offline profile audit handles evidence; this module checks only the rate
## program and progress. It never approves material provenance or computes heat.
## Acknowledge advances the prescribed clock even when some mass was rejected.
## Rejected demand is recorded, never queued. Replaying requires a coherent
## caller-owned snapshot of BOTH progress and physical fuel inventories.
## Measured depletion uses constant interval means and a separate version;
## it is a reservoir replay, NOT verified gaseous component emission.
const MASS_ABS_TOL_KG: float = 1.0e-12
const REL_TOL: float = 1.0e-12
const PROGRAM_VERSION: String = "prescribed_fuel_release_v1"
const MEASURED_PROGRAM_VERSION: String = "prescribed_measured_depletion_v1"
const PROGRAM_KEYS: Array[String] = [
	"profile_id", "component_id", "initial_mass_kg", "mode", "quantity", "unit",
	"time_origin", "interpolation", "outside_domain", "samples",
]
const PROGRESS_KEYS: Array[String] = [
	"fingerprint", "time_s", "scheduled_kg", "accepted_kg", "rejected_kg",
]
const SAMPLE_KEYS: Array[String] = ["time_s", "rate_kg_s"]
const PROGRAM_LITERALS: Dictionary = {
	"mode": "prescribed", "unit": "kg/s", "outside_domain": "reject",
}


static func initial_progress(program: Variant) -> Dictionary:
	var checked: Dictionary = _program(program)
	if not checked["valid"]:
		return checked
	return {"valid": true, "errors": [], "candidate": {
		"fingerprint": checked["fingerprint"], "time_s": 0.0,
		"scheduled_kg": 0.0, "accepted_kg": 0.0, "rejected_kg": 0.0,
	}}


## Pure preview. The caller must commit budget and progress atomically later.
static func propose(program: Variant, progress: Variant, end_time_s: Variant) -> Dictionary:
	var checked: Dictionary = _program(program)
	if not checked["valid"]:
		return checked
	var errors: Array[String] = []
	var p: Dictionary = _object(progress, PROGRESS_KEYS, "progress", errors)
	if typeof(p.get("fingerprint")) not in [TYPE_STRING, TYPE_STRING_NAME] or p.get("fingerprint") != checked["fingerprint"]:
		errors.append("progress fingerprint does not match rate program/version")
	var start: float = _number(p.get("time_s"), "progress.time_s", errors)
	var end: float = _number(end_time_s, "end_time_s", errors)
	var scheduled: float = _number(p.get("scheduled_kg"), "scheduled_kg", errors)
	var accepted: float = _number(p.get("accepted_kg"), "accepted_kg", errors)
	var rejected: float = _number(p.get("rejected_kg"), "rejected_kg", errors)
	var samples: Array = checked["samples"]
	var interpolation: String = checked["interpolation"]
	var domain_end: float = float(samples[-1]["time_s"])
	if start > domain_end or end > domain_end or end < start:
		errors.append("interval outside rate domain or before committed time")
	if not errors.is_empty():
		return _invalid(errors)
	var expected: float = _integral(samples, 0.0, start, interpolation)
	if not _near(scheduled, expected) or not _near(accepted + rejected, scheduled):
		errors.append("progress counters disagree with prescribed integral")
	var request: float = _integral(samples, start, end, interpolation)
	var next_scheduled: float = _integral(samples, 0.0, end, interpolation)
	if not _finite(request) or request < 0.0 or not _finite(next_scheduled):
		errors.append("nonfinite or negative integral")
	if not _near(scheduled + request, next_scheduled):
		errors.append("interval and cumulative integrals disagree")
	if not errors.is_empty():
		return _invalid(errors)
	return {
		"valid": true, "errors": [], "dt_s": end - start, "release_kg": request,
		"start_time_s": start, "end_time_s": end,
		"next_scheduled_kg": next_scheduled, "fingerprint": checked["fingerprint"],
		"scope": checked["scope"],
	}


## Does not trust or apply a cached proposal: recomputes from CURRENT progress.
## A second nonzero acknowledgement at the already committed time is rejected.
static func acknowledge(
	program: Variant, progress: Variant, end_time_s: Variant, accepted_release_kg: Variant
) -> Dictionary:
	var preview: Dictionary = propose(program, progress, end_time_s)
	if not preview["valid"]:
		return preview
	var errors: Array[String] = []
	var accepted: float = _number(accepted_release_kg, "accepted_release_kg", errors)
	var requested: float = float(preview["release_kg"])
	if accepted > requested:
		errors.append("accepted release exceeds prescribed request")
	if not errors.is_empty():
		return _invalid(errors)
	var rejected: float = requested - accepted
	var candidate: Dictionary = {
		"fingerprint": preview["fingerprint"], "time_s": float(preview["end_time_s"]),
		"scheduled_kg": float(preview["next_scheduled_kg"]),
		"accepted_kg": float(progress["accepted_kg"]) + accepted,
		"rejected_kg": float(progress["rejected_kg"]) + rejected,
	}
	if not _near(float(candidate["accepted_kg"]) + float(candidate["rejected_kg"]), float(candidate["scheduled_kg"])):
		errors.append("acknowledged counters do not close")
	if not errors.is_empty():
		return _invalid(errors)
	return {"valid": true, "errors": [], "candidate": candidate,
		"accepted_this_step_kg": accepted, "rejected_this_step_kg": rejected}


static func _program(program: Variant) -> Dictionary:
	var errors: Array[String] = []
	var data: Dictionary = _object(program, PROGRAM_KEYS, "program", errors)
	for key in ["profile_id", "component_id", "time_origin"]:
		if typeof(data.get(key)) != TYPE_STRING or String(data.get(key, "")).strip_edges().is_empty():
			errors.append(key + " must be a nonempty string")
	# Type first: comparing a number, bool or container with text aborts the script.
	for key in PROGRAM_LITERALS:
		if typeof(data.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or data.get(key) != PROGRAM_LITERALS[key]:
			errors.append("unsupported rate program " + key)
	var textual: bool = typeof(data.get("interpolation")) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(data.get("quantity")) in [TYPE_STRING, TYPE_STRING_NAME]
	var linear: bool = textual and data.get("interpolation") == "piecewise_linear" and data.get("quantity") == "modeled_component_emission"
	var measured: bool = textual and data.get("interpolation") == "piecewise_constant_left" and data.get("quantity") == "measured_reservoir_depletion"
	if not linear and not measured:
		errors.append("unsupported interpolation/quantity pair")
	var mass: float = _number(data.get("initial_mass_kg"), "initial_mass_kg", errors)
	var raw: Variant = data.get("samples")
	var samples: Array = []
	if typeof(raw) != TYPE_ARRAY or raw.size() < 2:
		errors.append("samples must be an array with >= 2 points")
	else:
		for item in raw:
			var point: Dictionary = _object(item, SAMPLE_KEYS, "sample", errors)
			var t: float = _number(point.get("time_s"), "sample time", errors)
			var rate: float = _number(point.get("rate_kg_s"), "sample rate", errors)
			if not samples.is_empty() and t <= float(samples[-1]["time_s"]):
				errors.append("sample times must strictly increase")
			samples.append({"time_s": t, "rate_kg_s": rate})
		if samples[0]["time_s"] != 0.0:
			errors.append("sample domain must start at zero")
		if measured and samples[-1]["rate_kg_s"] != 0.0:
			errors.append("measured terminal sample must have zero rate; no interval follows it")
	if not errors.is_empty():
		return _invalid(errors)
	var interpolation: String = String(data["interpolation"])
	var total: float = _integral(samples, 0.0, float(samples[-1]["time_s"]), interpolation)
	if not _finite(total) or total > mass + MASS_ABS_TOL_KG + REL_TOL * maxf(mass, total):
		errors.append("rate integral exceeds initial mass or overflows")
	if not errors.is_empty():
		return _invalid(errors)
	# Canonical keys and full numeric precision; no clock/material values are inferred.
	var version: String = MEASURED_PROGRAM_VERSION if measured else PROGRAM_VERSION
	var fingerprint: String = (version + JSON.stringify(data, "", true, true)).sha256_text()
	var scope: String = "measured_depletion_replay_not_emission_calibration" if measured else "prescribed_boundary_not_material_calibration"
	return {"valid": true, "errors": [], "samples": samples, "fingerprint": fingerprint,
		"interpolation": interpolation, "scope": scope}


static func _integral(samples: Array, start: float, end: float, interpolation: String) -> float:
	var total: float = 0.0
	for i in range(samples.size() - 1):
		var t0: float = float(samples[i]["time_s"])
		var t1: float = float(samples[i + 1]["time_s"])
		var lo: float = maxf(start, t0)
		var hi: float = minf(end, t1)
		if hi <= lo:
			continue
		var r0: float = float(samples[i]["rate_kg_s"])
		if interpolation == "piecewise_constant_left":
			total += (hi - lo) * r0
			continue
		var r1: float = float(samples[i + 1]["rate_kg_s"])
		var a: float = (lo - t0) / (t1 - t0)
		var b: float = (hi - t0) / (t1 - t0)
		var left: float = (1.0 - a) * r0 + a * r1
		var right: float = (1.0 - b) * r0 + b * r1
		total += (hi - lo) * (0.5 * left + 0.5 * right)
	return total


static func _object(value: Variant, keys: Array[String], label: String, errors: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(label + " must be dictionary")
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
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		errors.append(label + " must be finite nonnegative numeric")
		return 0.0
	var number: float = float(value)
	if not _finite(number) or number < 0.0:
		errors.append(label + " invalid number")
		return 0.0
	return number


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _near(a: float, b: float) -> bool:
	return _finite(a) and _finite(b) and absf(a - b) <= MASS_ABS_TOL_KG + REL_TOL * maxf(absf(a), absf(b))


static func _invalid(errors: Array[String]) -> Dictionary:
	return {"valid": false, "errors": errors, "candidate": {}}
