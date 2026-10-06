extends RefCounted
## Real n-heptane Cp profiles approved by the offline gates of 2026-10-05 (gas)
## and 2026-10-06 (liquid). Isolated property adapter: strict binding to the
## approved content below and the canonical integral of SensibleEnthalpyModel.
## Liquid: isobaric Cp at 100 kPa derived from Csat. Gas: ideal-gas Cp with an
## assumed, a correlated and a source-extrapolated range. The ITS-90 conversion
## is approximate. No engine, EOS, transport, editor or product consumes this;
## its only consumers are the isolated sensible ledger and its versioned real
## owner, which are prototypes and approve nothing.
## The binding compares against these constants; it is not a signature and does
## not prove where a profile came from.
## The liquid values are derived here from Csat of NBS RP2526 with liquid density
## data whose source is the National Institute of Standards and Technology,
## ThermoML/Data Archive, doi:10.18434/mds2-2422; they are not NIST values.

const Canonical = preload("res://sim/fire/SensibleEnthalpyModel.gd")
const SCOPE: String = "real_primary_source_property_isolated_not_fire_validation"
const MAX_ERRORS: int = 8
# BEGIN GENERATED APPROVED CONTENT (scripts/simulation/build_g3_heptane_real_cp_profiles.py)
const APPROVED: Dictionary = {
	"g3_real_liquid_isobaric_cp_v1": {
		"schema": "g3_real_liquid_isobaric_cp_v1",
		"component_id": "n-heptane",
		"caloric_model": "declared_liquid",
		"pressure_path": "constant_pressure",
		"temperature_scale": "ITS-90_kelvin",
		"quantity": "isobaric_specific_heat",
		"quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear",
		"calibration_status": "primary_source_property_not_fire_validation",
		"phase": "liquid",
		"reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0,
		"samples": [
			{"temperature_k": 279.985531, "cp_kj_kg_k": 2.179215962949},
			{"temperature_k": 284.982459, "cp_kj_kg_k": 2.196576751529},
			{"temperature_k": 289.979375, "cp_kj_kg_k": 2.2142672158},
			{"temperature_k": 294.976764, "cp_kj_kg_k": 2.232225908265},
			{"temperature_k": 298.135458, "cp_kj_kg_k": 2.243777431822},
			{"temperature_k": 299.974747, "cp_kj_kg_k": 2.250774872159},
			{"temperature_k": 309.970808, "cp_kj_kg_k": 2.289061653596},
			{"temperature_k": 319.967501, "cp_kj_kg_k": 2.328729021619},
			{"temperature_k": 329.965047, "cp_kj_kg_k": 2.369941480907},
			{"temperature_k": 339.964031, "cp_kj_kg_k": 2.412751495369},
			{"temperature_k": 349.963317, "cp_kj_kg_k": 2.457365590438},
			{"temperature_k": 359.962863, "cp_kj_kg_k": 2.503129939684},
			{"temperature_k": 369.963586, "cp_kj_kg_k": 2.550293730934},
			{"temperature_k": 371.102911, "cp_kj_kg_k": 2.555857655428},
		],
		"provenance": "primary:sha256:40138b0b81980477244431bd66c9b55adb775edbaf3d4e218f4f2d7b434bd3f9;volumetric:sha256:07643839f2f4c98f344faed4d2eed5c6bf671098a31d524d69ea8720c1dca73b;sources:sha256:d4caffbd6b0121dfd9e7e838157cf20d6c8d485aedf1bb78cf94d4bb307bec02;review:sha256:8d5bbc873b5282005d812687b65aa9c942d645fb88c41f0c0ceea9b8969b9fda;adapter:g3_heptane_liquid_cp_adapter_v1",
		"molar_mass_g_mol": 100.2,
		"native_support_k": [280.0, 371.139179],
		"evidence_tiers": [
			{
				"native_range_k": [280.0, 360.0],
				"its90_range_k": [279.985531, 359.962863],
				"evidence_kind": "tabulated_Csat_of_the_source_converted_to_Cp_here",
			},
			{
				"native_range_k": [360.0, 370.0],
				"its90_range_k": [359.962863, 369.963586],
				"evidence_kind": "same_table_with_source_error_rising_above_360_K",
			},
			{
				"native_range_k": [370.0, 371.139179],
				"its90_range_k": [369.963586, 371.102911],
				"evidence_kind": "interpolation_towards_a_row_beyond_the_adjusted_table",
			},
		],
		"declared_errors": {
			"source_probable_error_percent_280_to_360_k": 0.1,
			"source_error_kind": "probable_error_as_stated_not_a_standard_uncertainty",
			"source_error_statement_above_360_k_percent": null,
			"conversion_abs_j_mol_k": 0.01,
			"scale_conversion_kind": "approximate_on_smoothed_values",
			"scale_difference_to_published_evaluation_percent": 0.07,
			"cp_interpolation_abs_j_mol_k": 0.025,
			"label_abs_k": 0.0006,
			"scale_factor_abs": 0.0001,
			"volumetric_sample_purity_mol_percent": 99.3,
			"volumetric_article_inspected": false,
			"fire_validation": false,
		},
		"witnesses": [
			{"temperature_k": 279.985531, "specific_sensible_enthalpy_kj_kg": -40.165288739730016},
			{"temperature_k": 369.963586, "specific_sensible_enthalpy_kj_kg": 171.69008627095383},
			{"temperature_k": 371.102911, "specific_sensible_enthalpy_kj_kg": 174.59886923508722},
		],
	},
	"g3_real_ideal_gas_cp_v1": {
		"schema": "g3_real_ideal_gas_cp_v1",
		"component_id": "n-heptane",
		"caloric_model": "ideal_gas",
		"pressure_path": "constant_pressure",
		"temperature_scale": "ITS-90_kelvin",
		"quantity": "isobaric_specific_heat",
		"quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear",
		"calibration_status": "primary_source_property_not_fire_validation",
		"phase": "gas",
		"reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0,
		"samples": [
			{"temperature_k": 298.135458, "cp_kj_kg_k": 1.647024526068},
			{"temperature_k": 299.974747, "cp_kj_kg_k": 1.655285172344},
			{"temperature_k": 309.970808, "cp_kj_kg_k": 1.700161715221},
			{"temperature_k": 319.967501, "cp_kj_kg_k": 1.744911625286},
			{"temperature_k": 329.965047, "cp_kj_kg_k": 1.789638390095},
			{"temperature_k": 339.964031, "cp_kj_kg_k": 1.834289848782},
			{"temperature_k": 349.963317, "cp_kj_kg_k": 1.879219468873},
			{"temperature_k": 359.962863, "cp_kj_kg_k": 1.923974887077},
			{"temperature_k": 369.963586, "cp_kj_kg_k": 1.968614365624},
			{"temperature_k": 379.965044, "cp_kj_kg_k": 2.013214532283},
			{"temperature_k": 389.966843, "cp_kj_kg_k": 2.057339900617},
			{"temperature_k": 399.968914, "cp_kj_kg_k": 2.101012932396},
			{"temperature_k": 409.971188, "cp_kj_kg_k": 2.144233685152},
			{"temperature_k": 419.973604, "cp_kj_kg_k": 2.186962231784},
			{"temperature_k": 429.976785, "cp_kj_kg_k": 2.229095249667},
			{"temperature_k": 439.980313, "cp_kj_kg_k": 2.270954437207},
			{"temperature_k": 449.983818, "cp_kj_kg_k": 2.312318314025},
			{"temperature_k": 459.987939, "cp_kj_kg_k": 2.353121764226},
			{"temperature_k": 469.991581, "cp_kj_kg_k": 2.39376903456},
		],
		"provenance": "primary:sha256:40138b0b81980477244431bd66c9b55adb775edbaf3d4e218f4f2d7b434bd3f9;sources:sha256:22c38e5c2c9c17445c82d3defa3f5f99e4733b97c06ac78e5670daf29e267da2;review:sha256:71e0c2fce7cee228e10d65629ea8dd8ed7eac559d89c2cd635fa69af71260bb3;adapter:g3_heptane_ideal_gas_cp_adapter_v1",
		"molar_mass_g_mol": 100.2,
		"native_support_k": [298.16, 470.0],
		"evidence_tiers": [
			{
				"native_range_k": [298.16, 370.0],
				"its90_range_k": [298.135458, 369.963586],
				"evidence_kind": "assumption_adopted_by_source_for_vapour_pressure_consistency",
			},
			{
				"native_range_k": [370.0, 466.0],
				"its90_range_k": [369.963586, 465.990266],
				"evidence_kind": "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure",
			},
			{
				"native_range_k": [466.0, 470.0],
				"its90_range_k": [465.990266, 469.991581],
				"evidence_kind": "extrapolation_tabulated_by_source",
			},
		],
		"declared_errors": {
			"cp_interpolation_abs_j_mol_k": 0.007,
			"label_abs_k": 0.0006,
			"scale_factor_abs": 0.0001,
			"source_fit_percent": 0.05,
			"source_precision_percent": 0.1,
			"source_accuracy_statement": null,
			"source_uncertainty_in_assumed_range": null,
			"real_gas_departure_applied": false,
			"scale_conversion_kind": "approximate_on_smoothed_values",
			"scale_approximation_residual_percent": null,
			"molar_mass_and_scale_verified_at_origin": false,
			"fire_validation": false,
		},
		"witnesses": [
			{"temperature_k": 298.135458, "specific_sensible_enthalpy_kj_kg": -0.023951505536310806},
			{"temperature_k": 369.963586, "specific_sensible_enthalpy_kj_kg": 129.83519178232677},
			{"temperature_k": 469.991581, "specific_sensible_enthalpy_kj_kg": 348.3918196182203},
		],
	},
}
# END GENERATED APPROVED CONTENT


## Independent copy of the approved profile of one real schema.
static func approved_profile(schema: Variant) -> Dictionary:
	if typeof(schema) != TYPE_STRING or not APPROVED.has(schema):
		return _reject(["unsupported real schema"])
	return _success(APPROVED[schema].duplicate(true))


## Accepts only a profile equal, value by value and type by type, to the
## approved content of its schema. Closed: no extra, missing or relabelled field.
static func validate_profile(profile: Variant) -> Dictionary:
	if typeof(profile) != TYPE_DICTIONARY:
		return _reject(["profile must be a Dictionary"])
	var schema: Variant = profile.get("schema")
	if typeof(schema) != TYPE_STRING or not APPROVED.has(schema):
		return _reject(["unsupported real schema"])
	var errors: Array[String] = []
	_same(profile, APPROVED[schema], "profile", errors)
	if not errors.is_empty():
		return _reject(errors)
	return _success(profile.duplicate(true))


## Cp and signed sensible enthalpy h(T) - h(298.15 K). The limits reported are
## those of the whole integrated interval, not only of the end point.
static func evaluate(profile: Variant, temperature_k: Variant) -> Dictionary:
	var checked: Dictionary = validate_profile(profile)
	if not checked["valid"]:
		return checked
	if not _number(temperature_k):
		return _reject(["query temperature must be finite numeric, never bool"])
	var approved: Dictionary = checked["candidate"]
	var temperature: float = float(temperature_k)
	var integrated: Dictionary = Canonical.integrate(approved["samples"], temperature)
	if not integrated["errors"].is_empty():
		return _reject(integrated["errors"])
	var low: float = minf(Canonical.REFERENCE_K, temperature)
	var high: float = maxf(Canonical.REFERENCE_K, temperature)
	var candidate: Dictionary = _described(approved, low, high)
	candidate["temperature_k"] = temperature
	candidate["cp_kj_kg_k"] = integrated["cp_kj_kg_k"]
	candidate["specific_sensible_enthalpy_kj_kg"] = integrated["specific_sensible_enthalpy_kj_kg"]
	return _success(candidate)


## Signed enthalpy change h(end) - h(start), both inside the support.
static func evaluate_interval(profile: Variant, start_k: Variant, end_k: Variant) -> Dictionary:
	var checked: Dictionary = validate_profile(profile)
	if not checked["valid"]:
		return checked
	if not _number(start_k) or not _number(end_k):
		return _reject(["interval temperatures must be finite numeric, never bool"])
	var approved: Dictionary = checked["candidate"]
	var start: float = float(start_k)
	var end: float = float(end_k)
	var first: Dictionary = Canonical.integrate(approved["samples"], start)
	if not first["errors"].is_empty():
		return _reject(first["errors"])
	var second: Dictionary = Canonical.integrate(approved["samples"], end)
	if not second["errors"].is_empty():
		return _reject(second["errors"])
	# Both terms are finite: the shared integral rejects overflow and the content is fixed.
	var change: float = second["specific_sensible_enthalpy_kj_kg"] - first["specific_sensible_enthalpy_kj_kg"]
	var candidate: Dictionary = _described(approved, minf(start, end), maxf(start, end))
	candidate["start_temperature_k"] = start
	candidate["end_temperature_k"] = end
	candidate["start_cp_kj_kg_k"] = first["cp_kj_kg_k"]
	candidate["end_cp_kj_kg_k"] = second["cp_kj_kg_k"]
	candidate["specific_enthalpy_change_kj_kg"] = change
	return _success(candidate)


## `approved` is already a private deep copy of the caller's profile.
static func _described(approved: Dictionary, low: float, high: float) -> Dictionary:
	var tiers: Array = []
	for tier: Dictionary in approved["evidence_tiers"]:
		var start: float = tier["its90_range_k"][0]
		var end: float = tier["its90_range_k"][1]
		if minf(end, high) - maxf(start, low) > 0.0 or (low == high and start <= low and low <= end):
			tiers.append({"evidence_kind": tier["evidence_kind"],
				"its90_range_k": [maxf(start, low), minf(end, high)]})
	var samples: Array = approved["samples"]
	return {"schema": approved["schema"], "component_id": approved["component_id"],
		"phase": approved["phase"], "caloric_model": approved["caloric_model"],
		"pressure_path": approved["pressure_path"],
		"reference_temperature_k": approved["reference_temperature_k"],
		"reference_pressure_pa": approved["reference_pressure_pa"],
		"temperature_scale": approved["temperature_scale"],
		"molar_mass_g_mol": approved["molar_mass_g_mol"],
		"minimum_temperature_k": samples[0]["temperature_k"],
		"maximum_temperature_k": samples[-1]["temperature_k"],
		"enthalpy_interval_k": [low, high], "evidence_tiers": tiers,
		"declared_errors": approved["declared_errors"],
		"total_uncertainty_quantified": false,
		"provenance": approved["provenance"], "calibration_status": approved["calibration_status"]}


static func _same(value: Variant, expected: Variant, path: String, errors: Array[String]) -> void:
	if errors.size() >= MAX_ERRORS:
		return
	if typeof(value) != typeof(expected):
		errors.append(path + ": type differs from the approved content")
		return
	match typeof(expected):
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not expected.has(key):
					errors.append(path + ": unexpected key " + str(key))
			for key: String in expected:
				if not value.has(key):
					errors.append(path + ": missing key " + key)
				else:
					_same(value[key], expected[key], path + "." + key, errors)
		TYPE_ARRAY:
			if value.size() != expected.size():
				errors.append(path + ": length differs from the approved content")
				return
			for index: int in range(expected.size()):
				_same(value[index], expected[index], path + "[" + str(index) + "]", errors)
		TYPE_FLOAT:
			if is_nan(value) or value != expected:
				errors.append(path + ": value differs from the approved content")
		_:
			if value != expected:
				errors.append(path + ": value differs from the approved content")


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(value)) and not is_inf(float(value))


static func _success(candidate: Dictionary) -> Dictionary:
	return {"valid": true, "errors": [], "candidate": candidate, "scope": SCOPE,
		"physical_approval": false, "integration_enabled": false, "product_activation": false,
		"ledger_composition_approval": false}


static func _reject(errors: Array) -> Dictionary:
	return {"valid": false, "errors": errors, "candidate": {}, "scope": SCOPE,
		"physical_approval": false, "integration_enabled": false, "product_activation": false,
		"ledger_composition_approval": false}
