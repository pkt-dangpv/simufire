extends SceneTree

## Real GDScript fixture of the isolated n-heptane Cp adapter. The expected
## numbers below are generated in Python from the offline auditors, never from
## the adapter. A failed check is recorded and the run goes on, so a broken
## mutant ends as a failed fixture and not as an unrelated script error.
const Real = preload("res://sim/fire/HeptaneRealCpProfiles.gd")
const Canonical = preload("res://sim/fire/SensibleEnthalpyModel.gd")
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const Controller = preload("res://sim/fire/PrescribedSensiblePhaseController.gd")
const SCOPE: String = "real_primary_source_property_isolated_not_fire_validation"
const FLAGS: Array[String] = ["physical_approval", "integration_enabled", "product_activation",
	"ledger_composition_approval"]
const REPORT_KEYS: Array[String] = ["valid", "errors", "candidate", "scope", "physical_approval",
	"integration_enabled", "product_activation", "ledger_composition_approval"]
const PHASES: Array[String] = ["liquid", "gas"]
# BEGIN GENERATED EXPECTATIONS (scripts/simulation/build_g3_heptane_real_cp_profiles.py)
const EXPECTED: Dictionary = {
	"liquid": {
		"schema": "g3_real_liquid_isobaric_cp_v1",
		"knots": 14.0,
		"support": [279.985531, 371.102911],
		"points": [
			[279.985531, 2.179215962949, -40.165288739730016],
			[281.17005694, 2.183331352326607, -37.581513510019334],
			[282.483995, 2.187896357239, -34.70975228175689],
			[284.982459, 2.196576751529, -29.232528171144406],
			[287.480917, 2.2054219836645, -23.73342369317743],
			[289.979375, 2.2142672158, -18.212219774219527],
			[292.4780695, 2.2232465620325, -12.668224139047386],
			[294.976764, 2.232225908265, -7.101791860830499],
			[296.556111, 2.2380016700435, -3.5717716032711366],
			[298.135458, 2.243777431822, -0.03262941367405825],
			[298.15, 2.2438327557963076, 0.0],
			[299.0551025, 2.2472761519905, 2.0324569501050505],
			[299.974747, 2.250774872159, 4.100760892644287],
			[301.58035006, 2.256924631892639, 7.719548951277231],
			[304.9727775, 2.2699182628775, 15.39804197767087],
			[309.970808, 2.289061653596, 26.791002313381803],
			[314.9691545, 2.3088953376075, 38.28209343044813],
			[319.967501, 2.328729021619, 49.87232017257545],
			[324.966274, 2.3493352512629997, 61.56461086234897],
			[325.544221, 2.351717697636152, 62.92309058667766],
			[329.965047, 2.369941480907, 73.35990741649884],
			[334.964539, 2.3913464881379998, 85.26191797196715],
			[339.964031, 2.412751495369, 97.27094268984678],
			[344.96367399999997, 2.4350585429035, 109.38960245143618],
			[349.963317, 2.457365590438, 121.61978948708224],
			[350.23703098, 2.4586182815275985, 122.29257624268793],
			[354.96309, 2.4802477650609998, 133.9632624567139],
			[359.962863, 2.503129939684, 146.4211411052069],
			[364.9632245, 2.526711835309, 158.99665468659023],
			[369.963586, 2.550293730934, 171.69008627095383],
			[370.5332485, 2.553075693181, 173.14368536323627],
			[370.55620672, 2.5531878102701504, 173.20230072368128],
			[371.102911, 2.555857655428, 174.59886923508722],
		],
		"intervals": [
			[
				279.985531,
				371.102911,
				214.76415797481724,
				["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K", "interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
			[
				371.102911,
				279.985531,
				-214.76415797481724,
				["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K", "interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
			[
				298.15,
				371.102911,
				174.59886923508722,
				["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K", "interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
			[
				279.985531,
				298.15,
				40.165288739730016,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				284.982459,
				289.979375,
				11.020308396924879,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				319.967501,
				371.102911,
				124.72654906251176,
				["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K", "interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
			[
				370.5332485,
				371.102911,
				1.4551838718509487,
				["interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
			[
				319.967501,
				319.967501,
				0.0,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				279.985531,
				279.985531,
				0.0,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				371.102911,
				371.102911,
				0.0,
				["interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
			[
				280.985531,
				358.962863,
				181.90463511749545,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
		],
		"point_kinds": [
			[
				279.985531,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				298.15,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				319.967501,
				["tabulated_Csat_of_the_source_converted_to_Cp_here"],
			],
			[
				371.102911,
				["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K", "interpolation_towards_a_row_beyond_the_adjusted_table"],
			],
		],
		"tier_kinds": ["tabulated_Csat_of_the_source_converted_to_Cp_here", "same_table_with_source_error_rising_above_360_K", "interpolation_towards_a_row_beyond_the_adjusted_table"],
		"csat_only_cp_kj_kg_k": [2.1793122464660866, 2.196661525779756, 2.214334924698721, 2.2322707346748034, 2.243804579540931, 2.2507900723388263, 2.2889864259554553, 2.3285121379818268, 2.369508059885211, 2.4120054180136794, 2.4561679117441813, 2.501301085932185, 2.5475833715724017, 2.5530278494582346],
	},
	"gas": {
		"schema": "g3_real_ideal_gas_cp_v1",
		"knots": 19.0,
		"support": [298.135458, 469.991581],
		"points": [
			[298.135458, 1.647024526068, -0.023951505536310806],
			[298.15, 1.6470898373476006, 0.0],
			[299.0551025, 1.651154849206, 1.492624755705687],
			[299.974747, 1.655285172344, 3.0129994459048635],
			[300.36958759900006, 1.6570577786806968, 3.6669231833429996],
			[304.9727775, 1.6777234437825002, 11.34223880598643],
			[309.970808, 1.700161715221, 19.7836253310848],
			[314.9691545, 1.7225366702535, 28.337541578880902],
			[319.967501, 1.744911625286, 37.00329560485136],
			[324.966274, 1.7672750076904997, 45.781607460793225],
			[329.965047, 1.789638390095, 54.671708788887486],
			[334.964539, 1.8119641194385, 63.67480025568377],
			[338.865359151, 1.8293836202415612, 70.77692157555492],
			[339.964031, 1.834289848782, 72.78950902772705],
			[344.96367399999997, 1.8567546588275, 82.01646144530618],
			[349.963317, 1.879219468873, 91.35572989317572],
			[354.96309, 1.9015971779749998, 100.80734238760631],
			[359.962863, 1.923974887077, 110.37083834780694],
			[364.9632245, 1.9462946263504999, 120.04721168259023],
			[369.963586, 1.968614365624, 129.83519178232677],
			[374.964315, 1.9909144489535, 139.7354570670234],
			[379.965044, 2.013214532283, 149.74723902512827],
			[384.0635195, 2.0312959535398534, 158.03540259294732],
			[384.9659435, 2.03527721645, 159.87028920612477],
			[389.966843, 2.057339900617, 170.10367265334068],
			[394.9678785, 2.0791764165065, 180.4471051274726],
			[399.968914, 2.101012932396, 190.89974279276427],
			[404.970051, 2.122623308774, 201.46123453289243],
			[409.971188, 2.144233685152, 212.13080272590844],
			[414.972396, 2.165597958468, 222.90798497327123],
			[419.973604, 2.186962231784, 233.7920143952562],
			[424.97519450000004, 2.2080287407255, 244.78298694310087],
			[429.976785, 2.229095249667, 255.8793255419354],
			[430.636528833, 2.231855909789499, 257.3508680503182],
			[434.97854900000004, 2.250024843437, 267.0810763586176],
			[439.980313, 2.270954437207, 278.38751206395307],
			[444.9820655, 2.291636375616, 289.79798706621017],
			[449.983818, 2.312318314025, 301.3119080056095],
			[454.9858785, 2.3327200391255003, 312.92928943924915],
			[459.987939, 2.353121764226, 324.64872153614573],
			[464.98976, 2.373445399393, 336.46944298459573],
			[468.960444262, 2.3895792710977726, 345.9256765339135],
			[469.991581, 2.39376903456, 348.3918196182203],
		],
		"intervals": [
			[
				298.135458,
				469.991581,
				348.41577112375666,
				["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
			],
			[
				469.991581,
				298.135458,
				-348.41577112375666,
				["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
			],
			[
				298.15,
				469.991581,
				348.3918196182203,
				["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
			],
			[
				298.135458,
				298.15,
				0.023951505536310806,
				["assumption_adopted_by_source_for_vapour_pressure_consistency"],
			],
			[
				299.974747,
				309.970808,
				16.770625885179935,
				["assumption_adopted_by_source_for_vapour_pressure_consistency"],
			],
			[
				379.965044,
				469.991581,
				198.64458059309206,
				["fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
			],
			[
				464.98976,
				469.991581,
				11.922376633624594,
				["fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
			],
			[
				379.965044,
				379.965044,
				0.0,
				["fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
			],
			[
				298.135458,
				298.135458,
				0.0,
				["assumption_adopted_by_source_for_vapour_pressure_consistency"],
			],
			[
				469.991581,
				469.991581,
				0.0,
				["extrapolation_tabulated_by_source"],
			],
			[
				370.963586,
				464.990266,
				204.66460811729212,
				["fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
			],
		],
		"point_kinds": [
			[
				298.135458,
				["assumption_adopted_by_source_for_vapour_pressure_consistency"],
			],
			[
				298.15,
				["assumption_adopted_by_source_for_vapour_pressure_consistency"],
			],
			[
				379.965044,
				["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure"],
			],
			[
				469.991581,
				["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
			],
		],
		"tier_kinds": ["assumption_adopted_by_source_for_vapour_pressure_consistency", "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure", "extrapolation_tabulated_by_source"],
	},
}
# END GENERATED EXPECTATIONS
var _failures: Array[String] = []
var _failed: bool = false
var _checks: int = 0
var _groups: Array[String] = []
var _observations: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_groups.append("R01")
	for phase: String in PHASES:
		_content(phase)
	for bad: Variant in ["g3_synthetic_isobaric_cp_v1", "liquid", "", 1, null, [], true]:
		_rejects(Real.approved_profile(bad), "approved_profile of an unknown schema")
	_groups.append("R02")
	for phase: String in PHASES:
		_points(phase)
	_groups.append("R03")
	for phase: String in PHASES:
		_intervals(phase)
	_groups.append("R04")
	for phase: String in PHASES:
		_support(phase)
	_groups.append("R05")
	for phase: String in PHASES:
		_limits(phase)
	_groups.append("R06")
	for phase: String in PHASES:
		_strict(phase)
	for bad: Variant in [null, [], "profile", 1, 1.5, false, {}]:
		_rejects(Real.validate_profile(bad), "profile that is not an approved Dictionary")
		_rejects(Real.evaluate(bad, 300.0), "evaluation of a profile that is not approved")
		_rejects(Real.evaluate_interval(bad, 300.0, 310.0), "interval of a profile that is not approved")
	_groups.append("R07")
	for phase: String in PHASES:
		_independence(phase)
	_groups.append("R08")
	for phase: String in PHASES:
		_reports(phase)
	_groups.append("R09")
	for phase: String in PHASES:
		_canonical(phase)
	_groups.append("R10")
	_isolation()
	print("G3_HEPTANE_REAL_CP " + JSON.stringify({"groups": _groups, "checks": _checks,
		"failures": _failures, "observations": _observations}, "", false, true))
	if _failed:
		quit(1)
		return
	print("G3_HEPTANE_REAL_CP_PASS")
	quit(0)


func _content(phase: String) -> void:
	var expected: Dictionary = EXPECTED[phase]
	var result: Dictionary = Real.approved_profile(expected["schema"])
	_expect(result.get("valid", false), phase + " approved profile available")
	var profile: Dictionary = _candidate(result)
	var samples: Array = _list(profile, "samples")
	_expect(float(samples.size()) == expected["knots"], phase + " knot count")
	_expect(profile.get("schema") == expected["schema"], phase + " schema")
	_expect(profile.get("component_id") == "n-heptane", phase + " substance")
	_expect(profile.get("phase") == phase, phase + " phase label")
	_expect(profile.get("caloric_model") == ("declared_liquid" if phase == "liquid" else "ideal_gas"),
		phase + " caloric model")
	_expect(profile.get("pressure_path") == "constant_pressure", phase + " pressure path")
	_expect(_number(profile, "reference_temperature_k") == 298.15, phase + " reference temperature")
	_expect(_number(profile, "reference_pressure_pa") == 100000.0, phase + " reference pressure")
	_expect(profile.get("temperature_scale") == "ITS-90_kelvin", phase + " scale label")
	_expect(profile.get("quantity") == "isobaric_specific_heat", phase + " quantity")
	_expect(profile.get("quantity_unit") == "kJ/(kg*K)", phase + " unit")
	_expect(profile.get("interpolation") == "piecewise_linear", phase + " interpolation")
	_expect(_number(profile, "molar_mass_g_mol") == 100.2, phase + " molar mass of the source")
	_expect(profile.get("calibration_status") == "primary_source_property_not_fire_validation",
		phase + " calibration status")
	var provenance: String = str(profile.get("provenance", ""))
	_expect(provenance.begins_with("primary:sha256:") and not provenance.begins_with("synthetic:"),
		phase + " provenance is not synthetic")
	if samples.size() >= 2:
		_expect(samples[0].get("temperature_k") == expected["support"][0], phase + " support start")
		_expect(samples[-1].get("temperature_k") == expected["support"][1], phase + " support end")
	var kinds: Array = []
	for tier: Variant in _list(profile, "evidence_tiers"):
		kinds.append(tier.get("evidence_kind") if typeof(tier) == TYPE_DICTIONARY else null)
	_expect(kinds == expected["tier_kinds"], phase + " evidence classes")
	_expect(Real.validate_profile(profile).get("valid", false), phase + " approved profile validates")
	if phase == "liquid":
		_expect(samples.size() == expected["csat_only_cp_kj_kg_k"].size(), "Csat control has every knot")
		var differs: int = 0
		for index: int in range(mini(samples.size(), expected["csat_only_cp_kj_kg_k"].size())):
			if samples[index].get("cp_kj_kg_k") != expected["csat_only_cp_kj_kg_k"][index]:
				differs += 1
		_expect(differs == samples.size(), "every liquid knot is a converted Cp, not Csat")


func _points(phase: String) -> void:
	var expected: Dictionary = EXPECTED[phase]
	var profile: Dictionary = _profile(phase)
	var first: float = NAN
	var last: float = NAN
	for point: Array in expected["points"]:
		var result: Dictionary = Real.evaluate(profile, point[0])
		_expect(result.get("valid", false), phase + " query accepted " + str(point[0]))
		var candidate: Dictionary = _candidate(result)
		_expect(candidate.get("temperature_k") == point[0], phase + " query temperature echoed")
		_near(_number(candidate, "cp_kj_kg_k"), point[1], phase + " Cp at " + str(point[0]))
		var enthalpy: float = _number(candidate, "specific_sensible_enthalpy_kj_kg")
		_near(enthalpy, point[2], phase + " enthalpy at " + str(point[0]))
		if point[0] < 298.15:
			_expect(enthalpy < 0.0, phase + " enthalpy negative below the reference")
		elif point[0] > 298.15:
			_expect(enthalpy > 0.0, phase + " enthalpy positive above the reference")
		if point[0] == expected["support"][0]:
			first = enthalpy
		if point[0] == expected["support"][1]:
			last = enthalpy
	var reference: Dictionary = _candidate(Real.evaluate(profile, 298.15))
	_expect(reference.get("specific_sensible_enthalpy_kj_kg") == 0.0, phase + " exact zero at the reference")
	_observe(phase + "_first_h", first)
	_observe(phase + "_last_h", last)
	_observe(phase + "_reference_cp", _number(reference, "cp_kj_kg_k"))
	_observe(phase + "_minimum_k", _number(reference, "minimum_temperature_k"))
	_observe(phase + "_maximum_k", _number(reference, "maximum_temperature_k"))


func _intervals(phase: String) -> void:
	var expected: Dictionary = EXPECTED[phase]
	var profile: Dictionary = _profile(phase)
	for interval: Array in expected["intervals"]:
		var label: String = phase + " interval " + str(interval[0]) + " to " + str(interval[1])
		var result: Dictionary = Real.evaluate_interval(profile, interval[0], interval[1])
		_expect(result.get("valid", false), label + " accepted")
		var candidate: Dictionary = _candidate(result)
		var change: float = _number(candidate, "specific_enthalpy_change_kj_kg")
		_near(change, interval[2], label + " change")
		_expect(_kinds(candidate) == interval[3], label + " evidence classes of the interval")
		_expect(candidate.get("start_temperature_k") == interval[0]
			and candidate.get("end_temperature_k") == interval[1], label + " ends echoed")
		_expect(candidate.get("enthalpy_interval_k") == [minf(interval[0], interval[1]),
			maxf(interval[0], interval[1])], label + " interval reported")
		var back: float = _number(_candidate(Real.evaluate_interval(profile, interval[1], interval[0])),
			"specific_enthalpy_change_kj_kg")
		_near(back, -interval[2], label + " antisymmetric")
		var start_h: float = _number(_candidate(Real.evaluate(profile, interval[0])),
			"specific_sensible_enthalpy_kj_kg")
		var end_h: float = _number(_candidate(Real.evaluate(profile, interval[1])),
			"specific_sensible_enthalpy_kj_kg")
		_near(change, end_h - start_h, label + " equals the difference of evaluations")
		var middle: float = 0.5 * interval[0] + 0.5 * interval[1]
		var left: float = _number(_candidate(Real.evaluate_interval(profile, interval[0], middle)),
			"specific_enthalpy_change_kj_kg")
		var right: float = _number(_candidate(Real.evaluate_interval(profile, middle, interval[1])),
			"specific_enthalpy_change_kj_kg")
		_near(left + right, interval[2], label + " additive")
		if interval[0] == interval[1]:
			_expect(candidate.get("specific_enthalpy_change_kj_kg") == 0.0, label + " exact zero")
	_observe(phase + "_full_change", _number(_candidate(Real.evaluate_interval(profile,
		expected["support"][0], expected["support"][1])), "specific_enthalpy_change_kj_kg"))


func _support(phase: String) -> void:
	var low: float = EXPECTED[phase]["support"][0]
	var high: float = EXPECTED[phase]["support"][1]
	var profile: Dictionary = _profile(phase)
	_expect(Real.evaluate(profile, low).get("valid", false), phase + " lower bound accepted")
	_expect(Real.evaluate(profile, high).get("valid", false), phase + " upper bound accepted")
	for outside: float in [low - 1.0e-6, high + 1.0e-6, low - 10.0, high + 10.0, 0.0, -5.0, 1000.0]:
		var result: Dictionary = Real.evaluate(profile, outside)
		_rejects(result, phase + " no extrapolation at " + str(outside))
		_explains(result, "no extrapolation", phase + " extrapolation named")
		_rejects(Real.evaluate_interval(profile, 298.15, outside), phase + " interval end outside")
		_rejects(Real.evaluate_interval(profile, outside, 298.15), phase + " interval start outside")
	for bad: Variant in [NAN, INF, -INF, true, "300", null, [], {}]:
		var result: Dictionary = Real.evaluate(profile, bad)
		_rejects(result, phase + " query that is not a finite number")
		_explains(result, "finite numeric", phase + " nonfinite query named")
		var first: Dictionary = Real.evaluate_interval(profile, bad, 300.0)
		_rejects(first, phase + " interval start that is not a finite number")
		_explains(first, "finite numeric", phase + " nonfinite interval start named")
		var second: Dictionary = Real.evaluate_interval(profile, 300.0, bad)
		_rejects(second, phase + " interval end that is not a finite number")
		_explains(second, "finite numeric", phase + " nonfinite interval end named")


func _limits(phase: String) -> void:
	var expected: Dictionary = EXPECTED[phase]
	var profile: Dictionary = _profile(phase)
	for item: Array in expected["point_kinds"]:
		var candidate: Dictionary = _candidate(Real.evaluate(profile, item[0]))
		_expect(_kinds(candidate) == item[1], phase + " evidence classes from the reference to " + str(item[0]))
		var low: float = minf(298.15, item[0])
		var high: float = maxf(298.15, item[0])
		_expect(candidate.get("enthalpy_interval_k") == [low, high], phase + " integrated interval reported")
		for tier: Variant in _list(candidate, "evidence_tiers"):
			var span: Variant = tier.get("its90_range_k") if typeof(tier) == TYPE_DICTIONARY else null
			_expect(typeof(span) == TYPE_ARRAY and span.size() == 2 and span[0] >= low and span[1] <= high
				and span[0] <= span[1], phase + " tier clipped to the interval")
		_expect(candidate.get("declared_errors") == profile.get("declared_errors"),
			phase + " declared limits travel with the result")
		_expect(candidate.get("total_uncertainty_quantified") == false, phase + " no total uncertainty claimed")
		_expect(candidate.get("temperature_scale") == "ITS-90_kelvin"
			and _number(candidate, "molar_mass_g_mol") == 100.2
			and candidate.get("provenance") == profile.get("provenance")
			and candidate.get("calibration_status") == profile.get("calibration_status"),
			phase + " scale, basis and provenance travel with the result")
	var declared: Dictionary = profile.get("declared_errors", {})
	var absent: Array[String] = ["source_error_statement_above_360_k_percent"]
	if phase == "gas":
		absent = ["source_accuracy_statement", "source_uncertainty_in_assumed_range",
			"scale_approximation_residual_percent"]
		_expect(declared.get("real_gas_departure_applied") == false, "ideal gas, no real-gas correction")
		_expect(declared.get("molar_mass_and_scale_verified_at_origin") == false,
			"gas molar mass and scale still assumed")
	else:
		_expect(declared.get("volumetric_article_inspected") == false, "density article not inspected")
		_expect(_number(declared, "conversion_abs_j_mol_k") > 0.0, "Csat to Cp conversion residue declared")
	for key: String in absent:
		_expect(declared.has(key) and typeof(declared[key]) == TYPE_NIL,
			phase + " absent uncertainty stays absent: " + key)
	_expect(declared.get("scale_conversion_kind") == "approximate_on_smoothed_values",
		phase + " scale conversion declared approximate")
	_expect(declared.get("fire_validation") == false, phase + " no fire validation")


func _strict(phase: String) -> void:
	var base: Dictionary = _profile(phase)
	var other: String = "gas" if phase == "liquid" else "liquid"
	for key: String in base:
		var missing: Dictionary = base.duplicate(true)
		missing.erase(key)
		_rejects(Real.validate_profile(missing), phase + " missing " + key)
	var edits: Array = [["extra", 1.0], ["latent_heat_kj_kg", 300.0],
		["schema", EXPECTED[other]["schema"]], ["schema", "g3_synthetic_isobaric_cp_v1"], ["schema", 1],
		["component_id", "heptane"], ["component_id", 7], ["phase", other], ["phase", "solid"],
		["caloric_model", "ideal_gas" if phase == "liquid" else "declared_liquid"],
		["caloric_model", "real_gas"], ["pressure_path", "saturation_curve"],
		["quantity", "saturation_heat_capacity"], ["quantity_unit", "J/(mol*K)"],
		["quantity_unit", "kJ/(kg*K) "], ["temperature_scale", "synthetic_kelvin"],
		["temperature_scale", "IPTS-48_kelvin"], ["interpolation", "nearest"],
		["reference_temperature_k", 298.16], ["reference_temperature_k", 298], ["reference_temperature_k", true],
		["reference_pressure_pa", 101325.0], ["reference_pressure_pa", 100000],
		["reference_pressure_pa", "100000"], ["molar_mass_g_mol", 100.0], ["molar_mass_g_mol", 100.20404],
		["molar_mass_g_mol", "100.2"], ["provenance", "synthetic: relabelled"],
		["provenance", str(base.get("provenance", "")) + "0"], ["calibration_status", "fire_validated"],
		["native_support_k", [0.0, 2000.0]], ["samples", []], ["samples", "none"], ["samples", null],
		["evidence_tiers", []], ["declared_errors", {}], ["witnesses", []]]
	for edit: Array in edits:
		var changed: Dictionary = base.duplicate(true)
		changed[edit[0]] = edit[1]
		_rejects(Real.validate_profile(changed), phase + " " + str(edit[0]) + " = " + str(edit[1]))
		# Evaluation needs a sample list; a broken mutant must fail a check, not the script.
		if edit[0] != "samples":
			_rejects(Real.evaluate(changed, 300.0), phase + " evaluation with " + str(edit[0]) + " changed")
	var count: int = _list(base, "samples").size()
	for bad: Variant in [NAN, INF, -INF, true, "2.2", null, 2, -2.0, 0.0]:
		for field: String in ["temperature_k", "cp_kj_kg_k"]:
			var invalid: Dictionary = base.duplicate(true)
			invalid["samples"][count / 2][field] = bad
			_rejects(Real.validate_profile(invalid), phase + " sample " + field + " = " + str(bad))
	for factor: float in [1000.0, 0.001, 100.2, 100.2 / 100.0, 1.0 + 1.0e-9, 1.0 - 1.0e-9, -1.0]:
		var scaled: Dictionary = base.duplicate(true)
		for sample: Dictionary in scaled["samples"]:
			sample["cp_kj_kg_k"] *= factor
		_rejects(Real.validate_profile(scaled), phase + " Cp scaled by " + str(factor))
		var single: Dictionary = base.duplicate(true)
		single["samples"][1]["cp_kj_kg_k"] *= factor
		_rejects(Real.validate_profile(single), phase + " one Cp scaled by " + str(factor))
	for offset: float in [0.01, -0.01, 0.0245, 1.0e-6]:
		var shifted: Dictionary = base.duplicate(true)
		for sample: Dictionary in shifted["samples"]:
			sample["temperature_k"] += offset
		_rejects(Real.validate_profile(shifted), phase + " labels shifted by " + str(offset))
	var removed: Dictionary = base.duplicate(true)
	removed["samples"].remove_at(count / 2)
	_rejects(Real.validate_profile(removed), phase + " knot removed")
	var coarse: Dictionary = base.duplicate(true)
	coarse["samples"] = [base["samples"][0], base["samples"][-1]]
	_rejects(Real.validate_profile(coarse), phase + " resampled to two knots")
	var added: Dictionary = base.duplicate(true)
	added["samples"].append({"temperature_k": 480.0, "cp_kj_kg_k": 2.6})
	_rejects(Real.validate_profile(added), phase + " knot added outside the support")
	var reversed_samples: Dictionary = base.duplicate(true)
	reversed_samples["samples"].reverse()
	_rejects(Real.validate_profile(reversed_samples), phase + " knots reversed")
	var extra_sample: Dictionary = base.duplicate(true)
	extra_sample["samples"][0]["extra"] = 1.0
	_rejects(Real.validate_profile(extra_sample), phase + " sample with an extra key")
	var not_dictionary: Dictionary = base.duplicate(true)
	not_dictionary["samples"][0] = [279.0, 2.0]
	_rejects(Real.validate_profile(not_dictionary), phase + " sample that is not a Dictionary")
	if phase == "liquid":
		var csat: Dictionary = base.duplicate(true)
		for index: int in range(count):
			csat["samples"][index]["cp_kj_kg_k"] = EXPECTED["liquid"]["csat_only_cp_kj_kg_k"][index]
		var refused: Dictionary = Real.validate_profile(csat)
		_rejects(refused, "Csat relabelled as Cp")
		_explains(refused, "samples", "Csat relabelling located in the samples")
		_rejects(Real.evaluate(csat, 330.0), "evaluation of Csat relabelled as Cp")
	var upgraded: Dictionary = base.duplicate(true)
	upgraded["evidence_tiers"][0]["evidence_kind"] = "measurement"
	_rejects(Real.validate_profile(upgraded), phase + " evidence class upgraded")
	var widened: Dictionary = base.duplicate(true)
	widened["evidence_tiers"][-1]["its90_range_k"][1] += 100.0
	_rejects(Real.validate_profile(widened), phase + " evidence range widened")
	var fewer: Dictionary = base.duplicate(true)
	fewer["evidence_tiers"].remove_at(0)
	_rejects(Real.validate_profile(fewer), phase + " evidence class dropped")
	for key: String in base.get("declared_errors", {}):
		var value: Variant = base["declared_errors"][key]
		var replaced: Dictionary = base.duplicate(true)
		if typeof(value) == TYPE_NIL:
			replaced["declared_errors"][key] = 0.0
		elif typeof(value) == TYPE_BOOL:
			replaced["declared_errors"][key] = not value
		elif typeof(value) == TYPE_FLOAT:
			replaced["declared_errors"][key] = 0.0
		else:
			replaced["declared_errors"][key] = "exact"
		_rejects(Real.validate_profile(replaced), phase + " declared limit altered: " + key)
		var dropped: Dictionary = base.duplicate(true)
		dropped["declared_errors"].erase(key)
		_rejects(Real.validate_profile(dropped), phase + " declared limit dropped: " + key)
	var invented: Dictionary = base.duplicate(true)
	invented["declared_errors"]["total_uncertainty_percent"] = 0.1
	_rejects(Real.validate_profile(invented), phase + " invented total uncertainty")
	var witness: Dictionary = base.duplicate(true)
	witness["witnesses"][0]["specific_sensible_enthalpy_kj_kg"] *= -1.0
	_rejects(Real.validate_profile(witness), phase + " witness sign changed")


func _independence(phase: String) -> void:
	var schema: String = EXPECTED[phase]["schema"]
	var first: Dictionary = _candidate(Real.approved_profile(schema))
	var second: Dictionary = _candidate(Real.approved_profile(schema))
	var pristine: Dictionary = second.duplicate(true)
	_expect(not first.is_read_only() and not _list(first, "samples").is_read_only(),
		phase + " approved copy is writable, not the constant")
	if not first.is_read_only() and not _list(first, "samples").is_read_only() and not first["samples"].is_empty():
		first["samples"][0]["cp_kj_kg_k"] = 999.0
		first["declared_errors"]["fire_validation"] = true
		first["phase"] = "changed"
	_expect(second == pristine, phase + " copies do not alias each other")
	_expect(_candidate(Real.approved_profile(schema)) == pristine, phase + " approved content not altered by a caller")
	var input: Dictionary = pristine.duplicate(true)
	var validated: Dictionary = _candidate(Real.validate_profile(input))
	if not validated.is_read_only() and validated.has("samples") and not validated["samples"].is_read_only():
		validated["samples"][0]["cp_kj_kg_k"] = 999.0
	_expect(input == pristine, phase + " validation returns an independent copy")
	var evaluated: Dictionary = _candidate(Real.evaluate(input, 330.0))
	if evaluated.has("declared_errors") and not evaluated["declared_errors"].is_read_only():
		evaluated["declared_errors"]["fire_validation"] = true
		evaluated["evidence_tiers"].clear()
		evaluated["enthalpy_interval_k"][0] = 0.0
	_expect(input == pristine, phase + " evaluation leaves its input unchanged")
	Real.evaluate(input, INF)
	Real.evaluate_interval(input, 300.0, 1000.0)
	_expect(input == pristine, phase + " rejection leaves its input unchanged")
	var again: Dictionary = _candidate(Real.evaluate(input, 330.0))
	_expect(again.get("declared_errors") == pristine.get("declared_errors")
		and not _list(again, "evidence_tiers").is_empty(), phase + " results do not alias earlier results")
	_expect(_candidate(Real.approved_profile(schema)) == pristine, phase + " approved content intact at the end")


func _reports(phase: String) -> void:
	var profile: Dictionary = _profile(phase)
	var reports: Array = [Real.approved_profile(EXPECTED[phase]["schema"]), Real.validate_profile(profile),
		Real.evaluate(profile, 330.0), Real.evaluate_interval(profile, 310.0, 330.0),
		Real.approved_profile("unknown"), Real.validate_profile({}), Real.evaluate(profile, INF),
		Real.evaluate(profile, 1000.0), Real.evaluate_interval(profile, 310.0, 1000.0)]
	for report: Dictionary in reports:
		_expect(report.get("scope") == SCOPE, phase + " scope explicit")
		for flag: String in FLAGS:
			_expect(report.has(flag) and typeof(report[flag]) == TYPE_BOOL and report[flag] == false,
				phase + " no authority " + flag)
		var keys: Array = report.keys()
		keys.sort()
		var wanted: Array = REPORT_KEYS.duplicate()
		wanted.sort()
		_expect(keys == wanted, phase + " report is closed")
		_expect(typeof(report.get("errors")) == TYPE_ARRAY
			and report.get("errors", [""]).is_empty() == report.get("valid", false),
			phase + " errors present exactly when rejected")


func _canonical(phase: String) -> void:
	var profile: Dictionary = _profile(phase)
	var samples: Array = _list(profile, "samples")
	var twin: Dictionary = {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_twin",
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "samples": samples.duplicate(true),
		"provenance": "synthetic: twin of the knots, labels only",
		"calibration_status": "synthetic_not_material_calibration"}
	for point: Array in EXPECTED[phase]["points"]:
		var real_candidate: Dictionary = _candidate(Real.evaluate(profile, point[0]))
		var twin_candidate: Dictionary = _candidate(Canonical.evaluate(twin, point[0]))
		_expect(real_candidate.has("cp_kj_kg_k") and real_candidate.get("cp_kj_kg_k") == twin_candidate.get("cp_kj_kg_k")
			and real_candidate.get("specific_sensible_enthalpy_kj_kg")
			== twin_candidate.get("specific_sensible_enthalpy_kj_kg"),
			phase + " same integral as the synthetic schema at " + str(point[0]))
	var huge: Array = [{"temperature_k": 298.15, "cp_kj_kg_k": 1.0e308},
		{"temperature_k": 398.15, "cp_kj_kg_k": 1.0e308}]
	_expect(not Canonical.integrate(huge, 398.15).get("errors", []).is_empty(), "shared integral rejects overflow")
	_expect(not Canonical.integrate(samples, 1000.0).get("errors", []).is_empty(), "shared integral never extrapolates")


func _isolation() -> void:
	var liquid: Dictionary = _profile("liquid")
	var gas: Dictionary = _profile("gas")
	for profile: Dictionary in [liquid, gas]:
		var refused: Dictionary = Canonical.validate_profile(profile)
		_expect(not refused.get("valid", true), "synthetic helper refuses a real profile")
		_expect(not Canonical.evaluate(profile, 330.0).get("valid", true), "synthetic helper does not evaluate a real profile")
	_rejects(Real.validate_profile(_synthetic("liquid", "n-heptane")), "real adapter refuses a synthetic profile")
	_rejects(Real.evaluate(_synthetic("gas", "n-heptane"), 330.0), "real adapter does not evaluate a synthetic profile")
	var state: Dictionary = {"schema": "g3_phase_sensible_state_v1", "component_id": "n-heptane",
		"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0, "vapour_fuel_kg": 0.0, "o2_kg": 10.0,
		"thermal_budget_kj": 1000.0, "deposited_heat_kj": 0.0, "liquid_sensible_kj": 0.0, "vapour_sensible_kj": 0.0}
	var request: Dictionary = {"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1, "heat_liquid_kj": 0.0,
		"heat_vapour_kj": 0.0, "emitted_vapour_temperature_k": 298.15}
	var control: Dictionary = Budget.propose_phase_sensible(state, request, _material(null, null))
	_expect(control.get("valid", false), "ledger control with synthetic profiles is accepted")
	for pair: Array in [[liquid, null], [null, gas], [liquid, gas]]:
		var refused: Dictionary = Budget.propose_phase_sensible(state, request, _material(pair[0], pair[1]))
		_expect(not refused.get("valid", true) and not refused.get("errors", []).is_empty(),
			"ledger refuses a real profile")
		_expect("unsupported schema" in str(refused.get("errors", [])), "ledger refusal comes from the synthetic schema")
	var owner_control: Dictionary = Controller.new().initialize(_context(null, null))
	_expect(owner_control.get("valid", false), "owner control with synthetic profiles is accepted")
	for pair: Array in [[liquid, null], [null, gas], [liquid, gas]]:
		var refused: Dictionary = Controller.new().initialize(_context(pair[0], pair[1]))
		_expect(not refused.get("valid", true), "sensible owner refuses a real profile")


func _synthetic(phase: String, component: String) -> Dictionary:
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": component,
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration",
		"provenance": "synthetic: isolation control", "samples": [
			{"temperature_k": 273.15, "cp_kj_kg_k": 2.0 if phase == "liquid" else 1.0},
			{"temperature_k": 498.15, "cp_kj_kg_k": 2.0 if phase == "liquid" else 1.0}]}


func _material(liquid: Variant, gas: Variant) -> Dictionary:
	return {"schema": "g3_phase_sensible_material_v1", "component_id": "n-heptane",
		"liquid_profile": liquid if liquid != null else _synthetic("liquid", "n-heptane"),
		"vapour_profile": gas if gas != null else _synthetic("gas", "n-heptane"),
		"reference_material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid",
			"vapour_phase": "gas", "water_product_phase": "gas", "atom_mass_basis": "nominal_C12_H1_O16",
			"chemical_energy_basis": "complete_oxidation_net", "reference_temperature_k": 298.15,
			"reference_pressure_pa": 100000.0, "mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
			"liquid_heat_kj_kg": 19000.0, "vapour_heat_kj_kg": 20000.0,
			"phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic: isolation control, not a measured fuel"}}


func _context(liquid: Variant, gas: Variant) -> Dictionary:
	return {"schema": "g3_prescribed_sensible_context_v1",
		"program": {"profile_id": "synthetic_constant", "component_id": "n-heptane", "initial_mass_kg": 1.0,
			"mode": "prescribed", "quantity": "modeled_component_emission", "unit": "kg/s",
			"time_origin": "synthetic_zero", "outside_domain": "reject", "interpolation": "piecewise_linear",
			"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.0}]},
		"material": _material(liquid, gas),
		"attribution": {"input_component_id": "n-heptane", "modeled_component_id": "n-heptane",
			"input_quantity": "modeled_component_emission", "rule": "same_declared_component",
			"status": "synthetic_declared_emission", "provenance": "synthetic:no_experimental_approval"},
		"seed": {"schema": "g3_prescribed_sensible_seed_v1", "initial_o2_kg": 10.0,
			"initial_thermal_budget_kj": 1000.0, "initial_liquid_sensible_kj": 0.0,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"}}


func _profile(phase: String) -> Dictionary:
	return _candidate(Real.approved_profile(EXPECTED[phase]["schema"]))


func _candidate(result: Variant) -> Dictionary:
	if typeof(result) == TYPE_DICTIONARY and typeof(result.get("candidate")) == TYPE_DICTIONARY:
		return result["candidate"]
	return {}


func _list(source: Dictionary, key: String) -> Array:
	return source[key] if typeof(source.get(key)) == TYPE_ARRAY else []


func _number(source: Dictionary, key: String) -> float:
	var value: Variant = source.get(key)
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else NAN


func _kinds(candidate: Dictionary) -> Array:
	var kinds: Array = []
	for tier: Variant in _list(candidate, "evidence_tiers"):
		kinds.append(tier.get("evidence_kind") if typeof(tier) == TYPE_DICTIONARY else null)
	return kinds


func _observe(key: String, value: float) -> void:
	# JSON has no NaN: a broken mutant must still print a parseable report.
	_observations[key] = null if is_nan(value) or is_inf(value) else value


func _rejects(result: Variant, label: String) -> void:
	var refused: bool = typeof(result) == TYPE_DICTIONARY and result.get("valid", true) == false
	refused = refused and typeof(result.get("errors")) == TYPE_ARRAY and not result["errors"].is_empty()
	refused = refused and typeof(result.get("candidate")) == TYPE_DICTIONARY and result["candidate"].is_empty()
	if refused:
		for flag: String in FLAGS:
			refused = refused and result.get(flag, true) == false
	_expect(refused, label + " fails closed")


func _explains(result: Dictionary, text: String, label: String) -> void:
	_expect(text in str(result.get("errors", [])), label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected)
		<= 1.0e-9 + 1.0e-12 * maxf(absf(actual), absf(expected)), label)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
