extends SceneTree

## Synthetic integration fixture only; NOT SimulationEngine or a furniture test.
const Release = preload("res://sim/fire/PrescribedFuelReleaseModel.gd")
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const MASS_TOL: float = 1.0e-12
const ENERGY_TOL: float = 1.0e-9
var _failed: bool = false
var _checks: int = 0
var _groups: int = 0
var _failures: Array[String] = []
var _material: Dictionary


func _init() -> void:
	call_deferred("_run")


func _program() -> Dictionary:
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/g3_mass_material_profile_synthetic.json"))
	var data: Dictionary = profile["release"].duplicate(true)
	data.erase("provenance")
	data["profile_id"] = profile["id"]
	data["initial_mass_kg"] = profile["initial_mass"]["value"]
	_material = {
		"mass_fractions": profile["material"]["mass_fractions"].duplicate(true),
		"chemical_heat_kj_per_kg": profile["material"]["chemical_heat"]["value"],
		"chemical_energy_basis": profile["material"]["chemical_heat"]["basis"],
		"provenance": "synthetic:mass-triangle-not-furniture",
	}
	return data


func _state(oxygen: float = 5.0) -> Dictionary:
	return {"initial_fuel_mass_kg": 1.0, "solid_fuel_kg": 1.0, "released_fuel_kg": 0.0, "o2_kg": oxygen}


func _run() -> void:
	var program: Dictionary = _program()
	var initialized: Dictionary = Release.initial_progress(program)
	_check(initialized.get("valid", false), "initialize synthetic program")
	var progress: Dictionary = initialized.get("candidate", {})
	var full: Dictionary = _preview(program, progress, 10.0, "triangle whole interval")
	_near(float(full.get("release_kg", -1.0)), 0.5, MASS_TOL, "analytic triangle 0.5 kg")
	_near(float(_preview(program, progress, 2.0, "partial ramp").get("release_kg", -1.0)), 0.04, MASS_TOL, "partial triangle 0.04 kg")
	_near(float(_preview(program, progress, 0.0, "zero interval").get("release_kg", -1.0)), 0.0, MASS_TOL, "zero interval no emission")
	var serialized: String = var_to_str([program, progress])
	var again: Dictionary = Release.propose(program, progress, 10.0)
	_check(again == full, "preview deterministic")
	_check(var_to_str([program, progress]) == serialized, "preview does not mutate inputs or advance clock")
	var acknowledged: Dictionary = _ack(program, progress, 10.0, 0.1, "cap rejects demand")
	var capped_progress: Dictionary = acknowledged.get("candidate", {})
	_near(float(capped_progress.get("accepted_kg", -1.0)), 0.1, MASS_TOL, "accepted is not scheduled")
	_near(float(capped_progress.get("rejected_kg", -1.0)), 0.4, MASS_TOL, "rejection recorded")
	_near(float(capped_progress.get("time_s", -1.0)), 10.0, MASS_TOL, "rejected demand advances committed clock")
	_near(float(_preview(program, capped_progress, 10.0, "same committed endpoint").get("release_kg", -1.0)), 0.0, MASS_TOL, "no queue or duplicate emission")
	_invalid(Release.acknowledge(program, capped_progress, 10.0, 0.1), "stale nonzero ack cannot commit twice")
	_invalid(Release.acknowledge(program, progress, 10.0, 0.6), "accepted cannot exceed requested")
	_invalid(Release.propose(program, progress, 10.01), "no extrapolation beyond end")
	_invalid(Release.propose(program, capped_progress, 9.0), "no time reversal")
	_invalid(Release.acknowledge(program, progress, 10.0, -0.1), "negative acceptance rejected")
	_invalid(Release.acknowledge(program, progress, 10.0, true), "boolean acceptance rejected")
	var amended: Dictionary = program.duplicate(true)
	amended["samples"][1]["rate_kg_s"] = 0.08
	_invalid(Release.propose(amended, progress, 10.0), "changed curve invalidates old cursor")
	amended = program.duplicate(true)
	amended["component_id"] = "another_component"
	_invalid(Release.propose(amended, progress, 10.0), "changed component invalidates old cursor")
	var malformed: Dictionary = progress.duplicate(true)
	malformed["accepted_kg"] = 0.1
	_invalid(Release.propose(program, malformed, 10.0), "counter sum cannot invent accepted mass")
	malformed = progress.duplicate(true)
	malformed["time_s"] = 5.0
	_invalid(Release.propose(program, malformed, 10.0), "time cannot skip unrecorded schedule")
	for bad in [null, {}, true, INF, NAN, -1.0]:
		_invalid(Release.propose(program, progress, bad), "invalid endpoint")
	_invalid(Release.propose(program, null, 1.0), "missing progress")
	_invalid(Release.initial_progress(null), "missing program")
	for key in ["unit", "quantity", "mode", "interpolation", "outside_domain"]:
		amended = program.duplicate(true)
		amended[key] = "unsupported"
		_invalid(Release.initial_progress(amended), "invalid boundary convention " + key)
	for value in [-1.0, INF, NAN, true, "0.1"]:
		amended = program.duplicate(true)
		amended["samples"][1]["rate_kg_s"] = value
		_invalid(Release.initial_progress(amended), "invalid rate")
	amended = program.duplicate(true)
	amended["samples"][2]["time_s"] = 4.0
	_invalid(Release.initial_progress(amended), "nonmonotonic curve")
	amended = program.duplicate(true)
	amended["samples"][0]["time_s"] = 1.0
	_invalid(Release.initial_progress(amended), "missing time-zero domain")
	amended = program.duplicate(true)
	amended["initial_mass_kg"] = 0.1
	_invalid(Release.initial_progress(amended), "declared mass less than integral")
	amended = program.duplicate(true)
	amended["fuel_energy_MJ"] = 20.0
	_invalid(Release.initial_progress(amended), "no legacy MJ fallback")
	amended = program.duplicate(true)
	amended["initial_mass_kg"] = 1.0e308
	amended["samples"] = [{"time_s": 0.0, "rate_kg_s": 1.0e308}, {"time_s": 1.0e308, "rate_kg_s": 1.0e308}]
	_invalid(Release.initial_progress(amended), "integral overflow")
	amended = program.duplicate(true)
	amended["samples"] = [{"time_s": 0.0, "rate_kg_s": 0.02}, {"time_s": 3.0, "rate_kg_s": 0.08}, {"time_s": 4.0, "rate_kg_s": 0.01}]
	var asymmetric: Dictionary = Release.initial_progress(amended)
	_near(float(_preview(amended, asymmetric.get("candidate", {}), 4.0, "asymmetric interval").get("release_kg", -1.0)), 0.195, MASS_TOL, "asymmetric analytic integral")
	var coarse: Dictionary = _campaign(program, [10.0], 5.0)
	var fine: Dictionary = _campaign(program, [0.3, 1.1, 2.7, 5.0, 6.1, 7.7, 9.9, 10.0], 5.0)
	_compare(coarse, fine, "subdivision abundant oxygen")
	_near(float(coarse.get("heat_kj", -1.0)), 10000.0, ENERGY_TOL, "analytic chemical heat")
	_near(float(coarse.get("co2_kg", -1.0)), 1.1, MASS_TOL, "analytic CO2")
	_near(float(coarse.get("water_kg", -1.0)), 0.45, MASS_TOL, "analytic water")
	var zero_o2: Dictionary = _campaign(program, [5.0, 10.0], 0.0)
	_near(float(zero_o2.get("fuel", {}).get("released_fuel_kg", -1.0)), 0.5, MASS_TOL, "zero O2 does not erase prescribed emission")
	_near(float(zero_o2.get("heat_kj", -1.0)), 0.0, ENERGY_TOL, "zero O2 no oxidation heat")
	_compare(_campaign(program, [10.0], 0.24), _campaign(program, [1.0, 5.0, 10.0], 0.24), "subdivision limited oxygen")
	# Snapshot both progress and fuel. Recompute and commit the same next interval.
	var first: Dictionary = _step(program, progress, _state(), 5.0)
	var snapshot: Dictionary = first.duplicate(true)
	var second: Dictionary = _step(program, first.get("progress", {}), first.get("fuel", {}), 10.0)
	var restored: Dictionary = _step(program, snapshot.get("progress", {}), snapshot.get("fuel", {}), 10.0)
	_check(second == restored, "restoring both snapshots is deterministic")
	_check(_campaign(program, [10.0], 5.0) == coarse, "reset both snapshots reproduces complete run")
	# Inventory cap: only budget acceptance counts; no later retry of rejected mass.
	var small: Dictionary = _state()
	small["solid_fuel_kg"] = 0.1
	var capped: Dictionary = _step(program, progress, small, 10.0)
	_near(float(capped.get("progress", {}).get("accepted_kg", -1.0)), 0.1, MASS_TOL, "solid cap acknowledged as 0.1")
	_near(float(capped.get("progress", {}).get("rejected_kg", -1.0)), 0.4, MASS_TOL, "solid cap is rejected demand not emitted fuel")
	_near(float(capped.get("fuel", {}).get("solid_fuel_kg", -1.0)), 0.0, MASS_TOL, "solid cannot become negative")
	# Thermal rejection is not converted into delayed prescribed emission.
	var preview: Dictionary = Release.propose(program, progress, 5.0)
	var thermal_material: Dictionary = _material.duplicate(true)
	thermal_material["heat_of_gasification_kj_kg"] = 1000.0
	var thermal: Dictionary = Budget.propose(_state(), {"dt_s": 5.0, "release_kg": preview["release_kg"],
		"oxidation_kg": 0.0, "release_mode": "thermal_budgeted", "release_heat_budget_kj": 0.0}, thermal_material)
	_check(thermal.get("valid", false), "thermal cap fixture valid")
	var thermal_ack: Dictionary = _ack(program, progress, 5.0, thermal.get("accepted_release_kg", -1.0), "thermal rejection")
	_near(float(thermal_ack.get("candidate", {}).get("rejected_kg", -1.0)), 0.25, MASS_TOL, "thermal refusal records rejection")
	_near(float(_preview(program, thermal_ack.get("candidate", {}), 10.0, "after thermal refusal").get("release_kg", -1.0)), 0.25, MASS_TOL, "next interval contains only its own prescribed mass")
	_check(var_to_str([program, progress]) == serialized, "all tests preserve original inputs")
	_check(Release.MASS_ABS_TOL_KG == MASS_TOL and Release.REL_TOL == 1.0e-12, "tolerances predeclared")
	print("G3_PRESCRIBED_RELEASE " + JSON.stringify({"checks": _checks, "groups": _groups, "failures": _failures, "program": program}))
	if _failed:
		quit(1)
	else:
		print("G3_PRESCRIBED_RELEASE_PASS")
		quit(0)


func _step(program: Dictionary, progress: Dictionary, fuel: Dictionary, end: float) -> Dictionary:
	var preview: Dictionary = _preview(program, progress, end, "joint interval")
	if not preview.get("valid", false):
		return {}
	var budget: Dictionary = Budget.propose(fuel, {"dt_s": preview["dt_s"], "release_kg": preview["release_kg"],
		"oxidation_kg": 10.0, "release_mode": "prescribed_mass_transfer"}, _material)
	_check(budget.get("valid", false), "budget accepted interval")
	if not budget.get("valid", false):
		return {}
	var ack: Dictionary = _ack(program, progress, end, budget["accepted_release_kg"], "joint acknowledgement")
	if not ack.get("valid", false):
		return {}
	return {"fuel": budget["candidate"], "progress": ack["candidate"], "heat_kj": budget["oxidation_heat_kj"],
		"co2_kg": budget["products_kg"]["co2"], "water_kg": budget["products_kg"]["water_vapour"]}


func _campaign(program: Dictionary, endpoints: Array, oxygen: float) -> Dictionary:
	var progress: Dictionary = Release.initial_progress(program).get("candidate", {})
	var fuel: Dictionary = _state(oxygen)
	var heat: float = 0.0
	var co2: float = 0.0
	var water: float = 0.0
	for end in endpoints:
		var result: Dictionary = _step(program, progress, fuel, float(end))
		if result.is_empty():
			return {}
		progress = result["progress"]
		fuel = result["fuel"]
		heat += float(result["heat_kj"])
		co2 += float(result["co2_kg"])
		water += float(result["water_kg"])
	_near(float(progress["scheduled_kg"]), float(progress["accepted_kg"]) + float(progress["rejected_kg"]), MASS_TOL, "schedule closes")
	_near(1.0 + oxygen, float(fuel["solid_fuel_kg"]) + float(fuel["released_fuel_kg"])
		+ float(fuel["o2_kg"]) + co2 + water, MASS_TOL, "campaign independent total mass")
	_near(20000.0, (float(fuel["solid_fuel_kg"]) + float(fuel["released_fuel_kg"])) * 20000.0 + heat, ENERGY_TOL, "campaign independent chemical energy")
	var remaining: float = float(fuel["solid_fuel_kg"]) + float(fuel["released_fuel_kg"])
	_near(0.6, remaining * 0.6 + co2 * 3.0 / 11.0, MASS_TOL, "campaign independent carbon")
	_near(0.1, remaining * 0.1 + water / 9.0, MASS_TOL, "campaign independent hydrogen")
	_near(0.3 + oxygen, remaining * 0.3 + float(fuel["o2_kg"]) + co2 * 8.0 / 11.0 + water * 8.0 / 9.0, MASS_TOL, "campaign independent oxygen")
	return {"fuel": fuel, "progress": progress, "heat_kj": heat, "co2_kg": co2, "water_kg": water}


func _compare(a: Dictionary, b: Dictionary, label: String) -> void:
	_groups += 1
	for key in ["solid_fuel_kg", "released_fuel_kg", "o2_kg"]:
		_near(float(a.get("fuel", {}).get(key, -1.0)), float(b.get("fuel", {}).get(key, -2.0)), MASS_TOL, label + key)
	for key in ["scheduled_kg", "accepted_kg", "rejected_kg"]:
		_near(float(a.get("progress", {}).get(key, -1.0)), float(b.get("progress", {}).get(key, -2.0)), MASS_TOL, label + key)
	for key in ["heat_kj", "co2_kg", "water_kg"]:
		_near(float(a.get(key, -1.0)), float(b.get(key, -2.0)), ENERGY_TOL if key == "heat_kj" else MASS_TOL, label + key)


func _preview(program: Dictionary, progress: Dictionary, end: float, label: String) -> Dictionary:
	_groups += 1
	var result: Dictionary = Release.propose(program, progress, end)
	_check(result.get("valid", false), label + " valid preview " + str(result.get("errors")))
	return result


func _ack(program: Dictionary, progress: Dictionary, end: float, accepted: float, label: String) -> Dictionary:
	_groups += 1
	var result: Dictionary = Release.acknowledge(program, progress, end, accepted)
	_check(result.get("valid", false), label + " valid ack " + str(result.get("errors")))
	return result


func _invalid(result: Dictionary, label: String) -> void:
	_groups += 1
	_check(not result.get("valid", true), label + " rejected")
	_check(not result.get("errors", []).is_empty(), label + " explicit errors")
	_check(result.get("candidate", {}) == {}, label + " no candidate")


func _near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= tolerance, label)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed = true
		_failures.append(label)
