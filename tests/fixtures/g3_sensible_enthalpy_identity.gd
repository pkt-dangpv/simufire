extends SceneTree

## Before/after identity corpus of the synthetic helper. It makes no claim of
## its own: every validation and evaluation result is serialised bit for bit
## and hashed, so the digest moves if any value, type, key order or message
## of the synthetic contract moves.
const Model = preload("res://sim/fire/SensibleEnthalpyModel.gd")
var _state: int = 20261006


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var counts: Dictionary = {"cases": 0, "valid": 0, "rejected": 0}
	var profiles: Array = []
	for size: int in [2, 3, 5, 8, 13, 21]:
		for phase: String in ["liquid", "gas"]:
			profiles.append(_random_profile(size, phase))
	profiles.append(_profile([273.15, 373.15], [2.0, 2.0], "liquid"))
	profiles.append(_profile([273.15, 373.15], [1.75, 2.75], "liquid"))
	profiles.append(_profile([298.15, 348.15, 398.15], [1.0, 3.0, 2.0], "gas"))
	profiles.append(_profile([298.15, 398.15], [1.0e308, 1.0e308], "liquid"))
	profiles.append(_profile([1.0e-300, 298.15, 1.0e300], [1.0e-300, 1.0, 1.0e-300], "gas"))
	for profile: Dictionary in profiles:
		_record(context, counts, Model.validate_profile(profile))
		var samples: Array = profile["samples"]
		var queries: Array = [298.15, 0.0, -1.0, NAN, INF, -INF, true, "298.15", null, 298]
		for index: int in range(samples.size()):
			var knot: float = samples[index]["temperature_k"]
			queries.append(knot)
			queries.append(knot * (1.0 + 1.0e-15))
			queries.append(knot * (1.0 - 1.0e-15))
			if index > 0:
				var previous: float = samples[index - 1]["temperature_k"]
				queries.append(0.5 * knot + 0.5 * previous)
				queries.append(previous + (knot - previous) * _unit())
		for query: Variant in queries:
			_record(context, counts, Model.evaluate(profile, query))
	var base: Dictionary = _profile([273.15, 323.15, 373.15], [2.0, 2.5, 2.25], "liquid")
	var edits: Array = [["schema", "other"], ["schema", 1], ["phase", "solid"], ["phase", "gas"],
		["caloric_model", "ideal_gas"], ["caloric_model", null], ["pressure_path", "saturation"],
		["reference_temperature_k", 298.16], ["reference_temperature_k", true],
		["reference_pressure_pa", 101325.0], ["reference_pressure_pa", "100000"],
		["temperature_scale", "ITS-90_kelvin"], ["quantity", "saturation_specific_heat"],
		["quantity_unit", "J/(mol*K)"], ["interpolation", "nearest"], ["samples", []],
		["samples", [null, 2.0]], ["samples", "none"], ["provenance", "primary:sha256:0"],
		["provenance", ""], ["calibration_status", "approved"], ["component_id", " "],
		["component_id", 7], ["extra", 1.0], ["molar_mass_g_mol", 100.2]]
	for edit: Array in edits:
		var changed: Dictionary = base.duplicate(true)
		changed[edit[0]] = edit[1]
		_record(context, counts, Model.validate_profile(changed))
		_record(context, counts, Model.evaluate(changed, 300.0))
	for key: String in base:
		var missing: Dictionary = base.duplicate(true)
		missing.erase(key)
		_record(context, counts, Model.validate_profile(missing))
		_record(context, counts, Model.evaluate(missing, 300.0))
	for bad: Variant in [NAN, INF, -INF, true, "2", null, 0.0, -1.0, 2]:
		for field: String in ["temperature_k", "cp_kj_kg_k"]:
			for index: int in range(3):
				var invalid: Dictionary = base.duplicate(true)
				invalid["samples"][index][field] = bad
				_record(context, counts, Model.validate_profile(invalid))
				_record(context, counts, Model.evaluate(invalid, 300.0))
	for bad: Variant in [null, false, 1, 1.5, [], "profile", {}]:
		_record(context, counts, Model.validate_profile(bad))
		_record(context, counts, Model.evaluate(bad, 300.0))
	var digest: String = context.finish().hex_encode()
	print("G3_SENSIBLE_IDENTITY " + JSON.stringify({"cases": counts["cases"],
		"valid": counts["valid"], "rejected": counts["rejected"], "sha256": digest}))
	print("G3_SENSIBLE_IDENTITY_DONE")
	quit(0)


func _record(context: HashingContext, counts: Dictionary, result: Dictionary) -> void:
	counts["cases"] += 1
	counts["valid" if result.get("valid", false) else "rejected"] += 1
	context.update(var_to_bytes(result))


func _unit() -> float:
	_state = (_state * 1103515245 + 12345) % 2147483648
	return float(_state) / 2147483648.0


func _random_profile(size: int, phase: String) -> Dictionary:
	var temperatures: Array = []
	var cps: Array = []
	var temperature: float = 220.0 + 40.0 * _unit()
	for index: int in range(size):
		temperatures.append(temperature)
		cps.append(0.5 + 4.0 * _unit())
		temperature += 1.0 + 60.0 * _unit()
	if temperatures[-1] < 298.15:
		temperatures[-1] = 298.15 + 30.0 * _unit() + 1.0
	return _profile(temperatures, cps, phase)


func _profile(temperatures: Array, cps: Array, phase: String) -> Dictionary:
	var samples: Array = []
	for index: int in range(temperatures.size()):
		samples.append({"temperature_k": temperatures[index], "cp_kj_kg_k": cps[index]})
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_" + phase,
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "samples": samples,
		"provenance": "synthetic: identity corpus, not a measured material",
		"calibration_status": "synthetic_not_material_calibration"}
