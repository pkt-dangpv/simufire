extends SceneTree

const Model = preload("res://sim/fire/SensibleEnthalpyModel.gd")
var _failures: Array[String] = []
var _failed: bool = false
var _checks: int = 0
var _groups: Array[String] = []
var _observations: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var constant: Dictionary = _profile([273.15, 373.15], [2.0, 2.0])
	var linear: Dictionary = _profile([273.15, 373.15], [1.75, 2.75])
	var piecewise: Dictionary = _profile([298.15, 348.15, 398.15], [1.0, 3.0, 2.0])
	_groups.append("S01")
	_value(constant, 348.15, 100.0, "constant_above")
	_groups.append("S02")
	_value(linear, 323.15, 53.125, "linear_above")
	_groups.append("S03")
	_value(constant, 298.15, 0.0, "constant_reference")
	_expect(Model.evaluate(constant, 298.15)["candidate"]["specific_sensible_enthalpy_kj_kg"] == 0.0, "exact zero")
	_groups.append("S04")
	_value(constant, 273.15, -50.0, "constant_below")
	_value(linear, 273.15, -46.875, "linear_below")
	_groups.append("S05")
	_value(piecewise, 398.15, 225.0, "piecewise_end")
	var interior_ref: Dictionary = _profile([248.15, 273.15, 323.15, 373.15, 398.15], [1.5, 1.75, 2.25, 2.75, 3.0])
	_near(_h(interior_ref, 248.15), -87.5, "multiple intervals below internal reference")
	_near(_h(interior_ref, 348.15), 112.5, "partial interval above internal reference")
	_groups.append("S06")
	for i: int in range(3):
		var result: Dictionary = Model.evaluate(piecewise, piecewise["samples"][i]["temperature_k"])
		_expect(result["valid"], "knot accepted")
		_near(result["candidate"]["cp_kj_kg_k"], [1.0, 3.0, 2.0][i], "exact knot Cp")
	_groups.append("S07")
	_value(piecewise, 373.15, 168.75, "piecewise_partial")
	_near(Model.evaluate(piecewise, 373.15)["candidate"]["cp_kj_kg_k"], 2.5, "partial Cp")
	_groups.append("S08")
	var split: Dictionary = _profile([273.15, 298.15, 323.15, 348.15, 373.15], [1.75, 2.0, 2.25, 2.5, 2.75])
	for temperature: float in [273.15, 286.15, 298.15, 321.15, 373.15]:
		_near(_h(split, temperature), _h(linear, temperature), "subdivision invariant")
	_groups.append("S09")
	for key: String in constant:
		var missing: Dictionary = constant.duplicate(true)
		missing.erase(key)
		_reject(Model.validate_profile(missing), "missing " + key)
	_changed(constant, "extra", 1)
	_changed(constant, "schema", "anything")
	_changed(constant, "quantity_unit", "J/(mol*K)")
	_changed(constant, "component_id", " ")
	_changed(constant, "component_id", 42)
	_changed(constant, "provenance", "measured experiment")
	_changed(constant, "calibration_status", "approved")
	for bad: Variant in [null, false, 1, [], "profile"]:
		_reject(Model.validate_profile(bad), "profile type")
	for bad: Variant in [true, "323.15", null, [], {}]:
		_reject(Model.evaluate(constant, bad), "query type")
	var extra_sample: Dictionary = constant.duplicate(true)
	extra_sample["samples"][0]["extra"] = 1
	_reject(Model.validate_profile(extra_sample), "sample extra key")
	_changed(constant, "samples", [{"temperature_k": 298.15, "cp_kj_kg_k": 2.0}])
	_changed(constant, "samples", [null, 2.0])
	_groups.append("S10")
	_reject(Model.validate_profile(_profile([273.15, 273.15, 373.15], [2.0, 2.0, 2.0])), "duplicate")
	_reject(Model.validate_profile(_profile([373.15, 273.15], [2.0, 2.0])), "unordered")
	_reject(Model.validate_profile(_profile([0.0, 373.15], [2.0, 2.0])), "zero Kelvin")
	_groups.append("S11")
	for cp: float in [0.0, -1.0]:
		_reject(Model.validate_profile(_profile([273.15, 373.15], [cp, 2.0])), "nonpositive Cp")
	_groups.append("S12")
	for temperature: float in [273.14, 373.16, -1.0, 0.0]:
		_reject(Model.evaluate(constant, temperature), "no extrapolation")
	_reject(Model.validate_profile(_profile([300.0, 400.0], [2.0, 2.0])), "reference outside support")
	_groups.append("S13")
	for bad: Variant in [NAN, INF, -INF, true, "2"]:
		var invalid: Dictionary = constant.duplicate(true)
		invalid["samples"][0]["cp_kj_kg_k"] = bad
		_reject(Model.validate_profile(invalid), "Cp nonnumeric/nonfinite")
		invalid = constant.duplicate(true)
		invalid["samples"][0]["temperature_k"] = bad
		_reject(Model.validate_profile(invalid), "T nonnumeric/nonfinite")
	for bad: float in [NAN, INF, -INF]:
		_reject(Model.evaluate(constant, bad), "query nonfinite")
	var huge: Dictionary = _profile([298.15, 398.15], [1.0e308, 1.0e308])
	_reject(Model.evaluate(huge, 398.15), "integral overflow")
	_expect(Model.evaluate(huge, 298.15)["valid"], "large finite Cp at reference")
	_groups.append("S14")
	_changed(constant, "phase", "solid")
	_changed(constant, "phase", "gas")
	_changed(constant, "caloric_model", "ideal_gas")
	_changed(constant, "caloric_model", true)
	_groups.append("S15")
	for bad: Variant in [298.16, true, NAN, "298.15", 0.0]:
		_changed(constant, "reference_temperature_k", bad)
	for bad: Variant in [101325.0, true, INF, "100000", 0.0]:
		_changed(constant, "reference_pressure_pa", bad)
	_changed(constant, "temperature_scale", "IPTS1948")
	_groups.append("S16")
	_changed(constant, "quantity", "saturation_specific_heat")
	_changed(constant, "pressure_path", "saturation")
	_changed(constant, "interpolation", "nearest")
	_changed(constant, "latent_heat_kj_kg", 1000.0)
	_groups.append("S17")
	var before: Dictionary = constant.duplicate(true)
	var validated: Dictionary = Model.validate_profile(constant)
	_expect(validated["valid"], "valid copy")
	validated["candidate"]["samples"][0]["cp_kj_kg_k"] = 999.0
	_expect(constant == before, "returned profile deeply independent")
	var evaluated: Dictionary = Model.evaluate(constant, 348.15)
	evaluated["candidate"]["component_id"] = "changed"
	_expect(constant == before, "evaluate input unchanged")
	Model.evaluate(constant, INF)
	_expect(constant == before, "rejection input unchanged")
	_groups.append("S18")
	for result: Dictionary in [Model.validate_profile(constant), Model.evaluate(constant, 348.15), Model.evaluate(constant, INF)]:
		_expect(result["scope"] == "synthetic_isobaric_property_not_material_calibration", "scope explicit")
		for flag: String in ["physical_approval", "integration_enabled", "product_activation"]:
			_expect(result[flag] == false, "no authority " + flag)
	_groups.append("S19")
	for index: int in range(101):
		var delta: float = float(index) - 25.0
		_near(_h(linear, 298.15 + delta), 2.0 * delta + 0.005 * delta * delta, "analytic grid")
	_groups.append("S20")
	var gas: Dictionary = _profile([273.15, 373.15], [4.0, 4.0])
	gas["phase"] = "gas"
	gas["caloric_model"] = "ideal_gas"
	gas["component_id"] = "synthetic_gas_B"
	_near(_h(gas, 348.15), 200.0, "independent gas")
	_near(_h(constant, 348.15), 100.0, "liquid unaffected")
	_expect(Model.evaluate(gas, 348.15)["candidate"]["component_id"] == "synthetic_gas_B", "identity")
	print("G3_SENSIBLE_ENTHALPY " + JSON.stringify({"groups": _groups, "checks": _checks,
		"failures": _failures, "observations": _observations}))
	if _failed:
		quit(1)
		return
	print("G3_SENSIBLE_ENTHALPY_PASS")
	quit(0)


func _profile(temperatures: Array, cps: Array) -> Dictionary:
	var samples: Array = []
	for index: int in range(temperatures.size()):
		samples.append({"temperature_k": temperatures[index], "cp_kj_kg_k": cps[index]})
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_liquid_A",
		"phase": "liquid", "caloric_model": "declared_liquid", "pressure_path": "constant_pressure",
		"reference_temperature_k": 298.15, "reference_pressure_pa": 100000.0,
		"temperature_scale": "synthetic_kelvin", "quantity": "isobaric_specific_heat",
		"quantity_unit": "kJ/(kg*K)", "interpolation": "piecewise_linear", "samples": samples,
		"provenance": "synthetic: analytical control, not a measured material",
		"calibration_status": "synthetic_not_material_calibration"}


func _h(profile: Dictionary, temperature: float) -> float:
	var result: Dictionary = Model.evaluate(profile, temperature)
	_expect(result["valid"], "evaluation valid " + str(result["errors"]))
	return result["candidate"].get("specific_sensible_enthalpy_kj_kg", NAN)


func _value(profile: Dictionary, temperature: float, expected: float, label: String) -> void:
	var actual: float = _h(profile, temperature)
	_observations[label] = actual
	_near(actual, expected, label)


func _changed(profile: Dictionary, key: String, value: Variant) -> void:
	var bad: Dictionary = profile.duplicate(true)
	bad[key] = value
	_reject(Model.validate_profile(bad), "invalid " + key)


func _reject(result: Dictionary, label: String) -> void:
	_expect(not result.get("valid", true) and not result.get("errors", []).is_empty()
		and result.get("candidate", {"unexpected": true}).is_empty(), label + " fails closed")


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected)
		<= 1.0e-9 + 1.0e-12 * maxf(absf(actual), absf(expected)), label)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
