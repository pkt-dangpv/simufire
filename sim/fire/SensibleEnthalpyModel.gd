extends RefCounted
## Synthetic isobaric property only. Not a material calibration or zone EOS.
## Canonical signed integral of piecewise-linear Cp, with no phase latent heat.

const SCOPE: String = "synthetic_isobaric_property_not_material_calibration"
const REFERENCE_K: float = 298.15
const REFERENCE_PA: float = 100000.0
const FIELDS: Array[String] = ["schema", "component_id", "phase", "caloric_model",
	"pressure_path", "reference_temperature_k", "reference_pressure_pa",
	"temperature_scale", "quantity", "quantity_unit", "interpolation", "samples",
	"provenance", "calibration_status"]
const FIXED: Dictionary = {"schema": "g3_synthetic_isobaric_cp_v1",
	"pressure_path": "constant_pressure", "temperature_scale": "synthetic_kelvin",
	"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
	"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration"}


static func validate_profile(profile: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(profile) != TYPE_DICTIONARY:
		return _reject(["profile must be a Dictionary"])
	for key: Variant in profile:
		if typeof(key) != TYPE_STRING or key not in FIELDS:
			errors.append("unexpected profile key: " + str(key))
	for key: String in FIELDS:
		if not profile.has(key):
			errors.append("missing profile key: " + key)
	for key: String in FIXED:
		if typeof(profile.get(key)) != TYPE_STRING or profile.get(key) != FIXED[key]:
			errors.append("unsupported " + key)
	for key: String in ["component_id", "provenance"]:
		if typeof(profile.get(key)) != TYPE_STRING or profile[key].strip_edges().is_empty():
			errors.append(key + " must be a nonempty String")
	# This declaration is not an authenticity check of experimental provenance.
	if typeof(profile.get("provenance")) == TYPE_STRING:
		if not profile["provenance"].begins_with("synthetic:"):
			errors.append("provenance must explicitly declare synthetic:")
	var phase: Variant = profile.get("phase")
	if typeof(phase) != TYPE_STRING or phase not in ["liquid", "gas"]:
		errors.append("unsupported phase")
	elif typeof(profile.get("caloric_model")) != TYPE_STRING:
		errors.append("caloric_model must be a String")
	elif profile["caloric_model"] != ("declared_liquid" if phase == "liquid" else "ideal_gas"):
		errors.append("phase/caloric_model mismatch")
	if not _number(profile.get("reference_temperature_k")):
		errors.append("reference temperature must be finite numeric")
	elif float(profile["reference_temperature_k"]) != REFERENCE_K:
		errors.append("unsupported reference temperature")
	if not _number(profile.get("reference_pressure_pa")):
		errors.append("reference pressure must be finite numeric")
	elif float(profile["reference_pressure_pa"]) != REFERENCE_PA:
		errors.append("unsupported reference pressure")
	var samples: Variant = profile.get("samples")
	if typeof(samples) != TYPE_ARRAY or samples.size() < 2:
		errors.append("samples must be an Array of at least two points")
		return _reject(errors)
	var previous: float = -1.0
	for sample: Variant in samples:
		if typeof(sample) != TYPE_DICTIONARY:
			errors.append("sample must be a Dictionary")
			continue
		if sample.size() != 2 or not sample.has("temperature_k") or not sample.has("cp_kj_kg_k"):
			errors.append("sample must have exactly temperature_k and cp_kj_kg_k")
			continue
		if not _number(sample["temperature_k"]) or not _number(sample["cp_kj_kg_k"]):
			errors.append("sample values must be finite numeric, never bool")
			continue
		var temperature: float = float(sample["temperature_k"])
		var cp: float = float(sample["cp_kj_kg_k"])
		if temperature <= 0.0 or temperature <= previous:
			errors.append("temperatures must be positive and strictly increasing")
		if cp <= 0.0:
			errors.append("Cp must be strictly positive")
		previous = temperature
	if not errors.is_empty():
		return _reject(errors)
	if REFERENCE_K < float(samples[0]["temperature_k"]) or REFERENCE_K > float(samples[-1]["temperature_k"]):
		return _reject(["reference outside profile support"])
	return _success(profile.duplicate(true))


static func evaluate(profile: Variant, temperature_k: Variant) -> Dictionary:
	var checked: Dictionary = validate_profile(profile)
	if not checked["valid"]:
		return checked
	if not _number(temperature_k):
		return _reject(["query temperature must be finite numeric, never bool"])
	var temperature: float = float(temperature_k)
	var samples: Array = checked["candidate"]["samples"]
	var minimum: float = float(samples[0]["temperature_k"])
	var maximum: float = float(samples[-1]["temperature_k"])
	if temperature < minimum or temperature > maximum:
		return _reject(["query outside profile support; no extrapolation"])
	var lower: float = minf(REFERENCE_K, temperature)
	var upper: float = maxf(REFERENCE_K, temperature)
	var integral: float = 0.0
	var query_cp: float = -1.0
	for index: int in range(samples.size() - 1):
		var left: Dictionary = samples[index]
		var right: Dictionary = samples[index + 1]
		var t0: float = float(left["temperature_k"])
		var t1: float = float(right["temperature_k"])
		var c0: float = float(left["cp_kj_kg_k"])
		var c1: float = float(right["cp_kj_kg_k"])
		if temperature >= t0 and temperature <= t1:
			query_cp = _cp_at(temperature, t0, t1, c0, c1)
		var a: float = maxf(lower, t0)
		var b: float = minf(upper, t1)
		if b <= a:
			continue
		var ca: float = _cp_at(a, t0, t1, c0, c1)
		var cb: float = _cp_at(b, t0, t1, c0, c1)
		# Stable mean avoids overflowing Cp(a)+Cp(b) when its half is finite.
		var area: float = (0.5 * ca + 0.5 * cb) * (b - a)
		integral += area
		if not _number(area) or not _number(integral):
			return _reject(["sensible integral overflow"])
	if not _number(query_cp) or query_cp <= 0.0:
		return _reject(["Cp evaluation overflow or underflow"])
	var signed_integral: float = -integral if temperature < REFERENCE_K else integral
	var candidate: Dictionary = {"component_id": profile["component_id"], "phase": profile["phase"],
		"caloric_model": profile["caloric_model"], "pressure_path": profile["pressure_path"],
		"reference_temperature_k": REFERENCE_K, "reference_pressure_pa": REFERENCE_PA,
		"minimum_temperature_k": minimum, "maximum_temperature_k": maximum,
		"temperature_k": temperature, "cp_kj_kg_k": query_cp,
		"specific_sensible_enthalpy_kj_kg": signed_integral,
		"provenance": profile["provenance"], "calibration_status": profile["calibration_status"]}
	return _success(candidate)


static func _cp_at(t: float, t0: float, t1: float, c0: float, c1: float) -> float:
	if t == t0:
		return c0
	if t == t1:
		return c1
	var fraction: float = (t - t0) / (t1 - t0)
	return c0 + fraction * (c1 - c0)


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value))


static func _success(candidate: Dictionary) -> Dictionary:
	return {"valid": true, "errors": [], "candidate": candidate, "scope": SCOPE,
		"physical_approval": false, "integration_enabled": false, "product_activation": false}


static func _reject(errors: Array) -> Dictionary:
	return {"valid": false, "errors": errors, "candidate": {}, "scope": SCOPE,
		"physical_approval": false, "integration_enabled": false, "product_activation": false}
