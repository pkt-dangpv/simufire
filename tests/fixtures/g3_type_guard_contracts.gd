extends SceneTree

## Typed-text contract of the three older isolated owners. A value of the
## wrong TYPE where text is expected must be a structured rejection, never a
## script error. Synthetic inputs only; no physics is asserted beyond controls.
## Each group runs in its own deferred call, so an owner that aborts cannot
## keep the remaining groups or the report from running.
const Release = preload("res://sim/fire/PrescribedFuelReleaseModel.gd")
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const Caller = preload("res://sim/fire/PrescribedPhaseBudgetController.gd")
const Owner = preload("res://sim/fire/PrescribedSensiblePhaseController.gd")
const GROUPS: Array[String] = ["_t01", "_t02", "_t03", "_t04", "_t05", "_t06", "_t07", "_t08", "_t09", "_t10", "_t11", "_t12"]
const PROGRAM_LITERALS: Array[String] = ["mode", "unit", "outside_domain", "interpolation", "quantity"]
const PROGRAM_NAMES: Array[String] = ["profile_id", "component_id", "time_origin"]
const REFERENCE_LITERALS: Array[String] = ["schema", "liquid_phase", "vapour_phase", "water_product_phase",
	"atom_mass_basis", "chemical_energy_basis"]
var _failed: bool = false
var _failures: Array[String] = []
var _checks: int = 0
var _groups: Array[String] = []
var _completed: Array[String] = []
var _observations: Dictionary = {}

## Not text: an object that only PRINTS as the expected literal. Converting a
## value with str() before comparing would accept it; type validation must not.
class Impostor:
	extends RefCounted
	var _text: String = ""


	func _init(text: String) -> void:
		_text = text


	func _to_string() -> String:
		return _text


func _initialize() -> void:
	for group: String in GROUPS:
		call_deferred(group)
	call_deferred("_finish")


## Wrong types only. null and absent fields are separate, older rejections.
func _wrong_types() -> Array:
	return [1, -3, 2.5, true, false, [], ["prescribed"], {}, {"mode": "prescribed"}]


func _program(linear: bool = false) -> Dictionary:
	var id: String = "synthetic_component" if linear else "synthetic_observed_reservoir"
	return {"profile_id": "synthetic_constant", "component_id": id, "initial_mass_kg": 1.0,
		"mode": "prescribed", "quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
		"unit": "kg/s", "time_origin": "synthetic_zero", "outside_domain": "reject",
		"interpolation": "piecewise_linear" if linear else "piecewise_constant_left",
		"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.0}]}


func _reference() -> Dictionary:
	return {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid", "vapour_phase": "gas",
		"reference_temperature_k": 298.15, "reference_pressure_pa": 100000.0, "water_product_phase": "gas",
		"atom_mass_basis": "nominal_C12_H1_O16", "chemical_energy_basis": "complete_oxidation_net",
		"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0}, "liquid_heat_kj_kg": 19000.0,
		"vapour_heat_kj_kg": 20000.0, "phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic:not_heptane"}


func _phase_state() -> Dictionary:
	return {"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0, "vapour_fuel_kg": 0.0, "o2_kg": 10.0,
		"thermal_budget_kj": 1000.0, "deposited_heat_kj": 0.0}


func _phase_request() -> Dictionary:
	return {"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1}


func _context() -> Dictionary:
	return {"schema": "g3_prescribed_phase_context_v1", "program": _program(), "material": _reference(),
		"attribution": {"input_component_id": "synthetic_observed_reservoir", "modeled_component_id": "synthetic_component",
			"input_quantity": "measured_reservoir_depletion", "rule": "all_depletion_as_reference_vapour",
			"status": "conditional_not_measured_emission", "provenance": "synthetic:no_experimental_approval"},
		"seed": {"initial_o2_kg": 10.0, "initial_thermal_budget_kj": 1000.0,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"}}


func _profile(phase: String, cp: float) -> Dictionary:
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_CHO",
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration",
		"provenance": "synthetic: constant Cp type-guard control", "samples": [
			{"temperature_k": 273.15, "cp_kj_kg_k": cp}, {"temperature_k": 498.15, "cp_kj_kg_k": cp}]}


func _sensible_material() -> Dictionary:
	return {"schema": "g3_phase_sensible_material_v1", "component_id": "synthetic_CHO",
		"liquid_profile": _profile("liquid", 2.0), "vapour_profile": _profile("gas", 1.0),
		"reference_material": _reference()}


func _sensible_context() -> Dictionary:
	return {"schema": "g3_prescribed_sensible_context_v1", "program": _program(), "material": _sensible_material(),
		"attribution": {"input_component_id": "synthetic_observed_reservoir", "modeled_component_id": "synthetic_CHO",
			"input_quantity": "measured_reservoir_depletion", "rule": "all_depletion_as_reference_vapour",
			"status": "conditional_not_measured_emission", "provenance": "synthetic:no_experimental_approval"},
		"seed": {"schema": "g3_prescribed_sensible_seed_v1", "initial_o2_kg": 10.0,
			"initial_thermal_budget_kj": 1000.0, "initial_liquid_sensible_kj": 0.0,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"}}


## Provider: every text field of the program, through its three entry points.
func _t01() -> void:
	_group("T01")
	var baseline: Variant = Release.initial_progress(_program())
	_accepts(baseline, "provider valid program")
	var progress: Dictionary = _candidate(baseline)
	for key: String in PROGRAM_LITERALS + PROGRAM_NAMES:
		for bad: Variant in _wrong_types():
			var program: Dictionary = _program()
			program[key] = bad
			var copy: Dictionary = program.duplicate(true)
			var cursor: Dictionary = progress.duplicate(true)
			_rejects(Release.initial_progress(program), "provider initial " + key)
			_rejects(Release.propose(program, cursor, 1.0), "provider propose " + key)
			_rejects(Release.acknowledge(program, cursor, 1.0, 0.05), "provider acknowledge " + key)
			_expect(program == copy and cursor == progress, "provider inputs untouched " + key)
		var absent: Dictionary = _program()
		absent[key] = null
		_rejects(Release.initial_progress(absent), "provider null " + key)
		absent.erase(key)
		_rejects(Release.initial_progress(absent), "provider missing " + key)
	for key: String in PROGRAM_LITERALS:
		var unknown: Dictionary = _program()
		unknown[key] = "unknown_text"
		_rejects(Release.initial_progress(unknown), "provider unknown text " + key)
		unknown[key] = ""
		_rejects(Release.initial_progress(unknown), "provider empty text " + key)
	for linear: bool in [false, true]:
		_accepts(Release.initial_progress(_program(linear)), "provider valid text kept")
	_completed.append("T01")


## Provider: the program identity carried by the progress.
func _t02() -> void:
	_group("T02")
	var progress: Dictionary = _candidate(Release.initial_progress(_program()))
	var expected: Variant = Release.propose(_program(), progress, 1.0)
	_accepts(expected, "provider valid progress")
	_near(_number(expected, "release_kg"), 0.1, "provider valid demand")
	for bad: Variant in _wrong_types():
		var cursor: Dictionary = progress.duplicate(true)
		cursor["fingerprint"] = bad
		var copy: Dictionary = cursor.duplicate(true)
		_rejects(Release.propose(_program(), cursor, 1.0), "provider propose fingerprint type")
		_rejects(Release.acknowledge(_program(), cursor, 1.0, 0.05), "provider acknowledge fingerprint type")
		_expect(cursor == copy, "provider progress untouched")
	for other: Variant in [null, "", "0123456789abcdef"]:
		var cursor: Dictionary = progress.duplicate(true)
		cursor["fingerprint"] = other
		_rejects(Release.propose(_program(), cursor, 1.0), "provider foreign fingerprint")
	var missing: Dictionary = progress.duplicate(true)
	missing.erase("fingerprint")
	_rejects(Release.propose(_program(), missing, 1.0), "provider missing fingerprint")
	_expect(Release.propose(_program(), progress, 1.0) == expected, "provider valid proposal unchanged")
	var acknowledged: Variant = Release.acknowledge(_program(), progress, 1.0, 0.05)
	_accepts(acknowledged, "provider valid acknowledgement")
	_near(float(_candidate(acknowledged).get("rejected_kg", NAN)), 0.05, "provider valid rejection recorded")
	_completed.append("T02")


## Mass kernel v1: the declared chemical energy basis and its text siblings.
func _t03() -> void:
	_group("T03")
	var state: Dictionary = {"initial_fuel_mass_kg": 1.0, "solid_fuel_kg": 1.0, "released_fuel_kg": 0.0, "o2_kg": 10.0}
	var request: Dictionary = {"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1, "release_mode": "prescribed_mass_transfer"}
	var material: Dictionary = {"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0}, "chemical_heat_kj_per_kg": 20000.0,
		"chemical_energy_basis": "complete_oxidation_net", "provenance": "synthetic:type_guard_control"}
	var baseline: Variant = Budget.propose(state, request, material)
	_accepts(baseline, "kernel valid material")
	_near(_number(baseline, "oxidation_heat_kj"), 2000.0, "kernel valid heat")
	# Any nonempty text is a valid provenance; the other two are closed literals.
	for field: Array in [["chemical_energy_basis", true, "unknown_text"], ["provenance", true, ""],
		["release_mode", false, "unknown_text"]]:
		for bad: Variant in _wrong_types() + [null, field[2]]:
			var changed_material: Dictionary = material.duplicate(true)
			var changed_request: Dictionary = request.duplicate(true)
			if field[1]:
				changed_material[field[0]] = bad
			else:
				changed_request[field[0]] = bad
			var copies: Array = [state.duplicate(true), changed_request.duplicate(true), changed_material.duplicate(true)]
			_rejects(Budget.propose(state, changed_request, changed_material), "kernel " + field[0])
			_expect(state == copies[0] and changed_request == copies[1] and changed_material == copies[2], "kernel inputs untouched " + field[0])
	var missing: Dictionary = material.duplicate(true)
	missing.erase("chemical_energy_basis")
	_rejects(Budget.propose(state, request, missing), "kernel missing basis")
	_expect(Budget.propose(state, request, material) == baseline, "kernel valid proposal unchanged")
	_completed.append("T03")


## Reference phase ledger: the six declared literals and the provenance.
func _t04() -> void:
	_group("T04")
	var baseline: Variant = Budget.propose_phase_reference(_phase_state(), _phase_request(), _reference())
	_accepts(baseline, "reference valid material")
	_near(float(_candidate(baseline).get("thermal_budget_kj", NAN)), 900.0, "reference valid budget")
	_near(float(_candidate(baseline).get("deposited_heat_kj", NAN)), 2000.0, "reference valid heat")
	for key: String in REFERENCE_LITERALS + ["provenance"]:
		for bad: Variant in _wrong_types():
			var material: Dictionary = _reference()
			material[key] = bad
			var copies: Array = [_phase_state(), _phase_request(), material.duplicate(true)]
			var state: Dictionary = _phase_state()
			var request: Dictionary = _phase_request()
			_rejects(Budget.propose_phase_reference(state, request, material), "reference " + key)
			_expect(state == copies[0] and request == copies[1] and material == copies[2], "reference inputs untouched " + key)
		var absent: Dictionary = _reference()
		absent[key] = null
		_rejects(Budget.propose_phase_reference(_phase_state(), _phase_request(), absent), "reference null " + key)
		absent.erase(key)
		_rejects(Budget.propose_phase_reference(_phase_state(), _phase_request(), absent), "reference missing " + key)
	for key: String in REFERENCE_LITERALS:
		var unknown: Dictionary = _reference()
		unknown[key] = "unknown_text"
		_rejects(Budget.propose_phase_reference(_phase_state(), _phase_request(), unknown), "reference unknown text " + key)
	_expect(Budget.propose_phase_reference(_phase_state(), _phase_request(), _reference()) == baseline, "reference valid proposal unchanged")
	_completed.append("T04")


## Sensible ledger: already guarded; kept as a regression control of the composition.
func _t05() -> void:
	_group("T05")
	var state: Dictionary = {"schema": "g3_phase_sensible_state_v1", "component_id": "synthetic_CHO",
		"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0, "vapour_fuel_kg": 0.0, "o2_kg": 10.0,
		"thermal_budget_kj": 1000.0, "deposited_heat_kj": 0.0, "liquid_sensible_kj": 0.0, "vapour_sensible_kj": 0.0}
	var request: Dictionary = {"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1, "heat_liquid_kj": 0.0,
		"heat_vapour_kj": 0.0, "emitted_vapour_temperature_k": 298.15}
	var baseline: Variant = Budget.propose_phase_sensible(state, request, _sensible_material())
	_accepts(baseline, "sensible valid material")
	_near(float(_candidate(baseline).get("thermal_budget_kj", NAN)), 900.0, "sensible valid budget")
	for key: String in REFERENCE_LITERALS + ["provenance"]:
		for bad: Variant in _wrong_types():
			var material: Dictionary = _sensible_material()
			material["reference_material"][key] = bad
			_rejects(Budget.propose_phase_sensible(state, request, material), "sensible reference " + key)
	for key: String in ["schema", "component_id"]:
		for bad: Variant in _wrong_types():
			var material: Dictionary = _sensible_material()
			material[key] = bad
			_rejects(Budget.propose_phase_sensible(state, request, material), "sensible material " + key)
			var typed_state: Dictionary = state.duplicate(true)
			typed_state[key] = bad
			_rejects(Budget.propose_phase_sensible(typed_state, request, _sensible_material()), "sensible state " + key)
	_expect(Budget.propose_phase_sensible(state, request, _sensible_material()) == baseline, "sensible valid proposal unchanged")
	_completed.append("T05")


## Reference caller: an invalid initialize leaves no owner and no partial state.
func _t06() -> void:
	_group("T06")
	var cases: Array = []
	for bad: Variant in _wrong_types():
		for path: Array in [["schema"], ["program", "mode"], ["program", "quantity"], ["program", "interpolation"],
			["material", "schema"], ["material", "liquid_phase"], ["material", "chemical_energy_basis"],
			["attribution", "status"], ["attribution", "rule"], ["seed", "energy_boundary_kind"],
			["seed", "energy_boundary_provenance"]]:
			cases.append([path, bad])
	for item: Array in cases:
		var context: Dictionary = _context()
		var target: Dictionary = context
		for index: int in range(item[0].size() - 1):
			target = target[item[0][index]]
		target[item[0][-1]] = item[1]
		var copy: Dictionary = context.duplicate(true)
		var owner: RefCounted = Caller.new()
		var label: String = "caller initialize " + ".".join(PackedStringArray(item[0]))
		_rejects(owner.initialize(context), label)
		_expect(_snapshot(owner).is_empty(), label + " leaves no owner")
		_expect(context == copy, label + " input untouched")
		_rejects(owner.preview_step(1.0, 0.1), label + " still uninitialized")
		_accepts(owner.initialize(_context()), label + " then a valid initialize")
		_expect(_snapshot(owner).get("generation", -1) == 0, label + " initializes cleanly")
	for other: Variant in [null, "", "g3_prescribed_phase_context_v0"]:
		var context: Dictionary = _context()
		context["schema"] = other
		var owner: RefCounted = Caller.new()
		_rejects(owner.initialize(context), "caller unknown context schema")
		_expect(_snapshot(owner).is_empty(), "caller unknown schema leaves no owner")
	var missing: Dictionary = _context()
	missing.erase("schema")
	_rejects(Caller.new().initialize(missing), "caller missing context schema")
	_completed.append("T06")


## Reference caller: invalid restores on a live owner change nothing.
func _t07() -> void:
	_group("T07")
	var owner: RefCounted = Caller.new()
	_accepts(owner.initialize(_context()), "caller valid context")
	_accepts(owner.commit_step(1.0, 0.1, 0), "caller valid step")
	var saved: Dictionary = _snapshot(owner).duplicate(true)
	_near(float(saved.get("phase", {}).get("thermal_budget_kj", NAN)), 900.0, "caller valid budget")
	var expected: Variant = owner.preview_step(2.0, 0.1)
	_accepts(expected, "caller valid preview")
	for key: String in ["schema", "context_fingerprint"]:
		for bad: Variant in _wrong_types():
			var edited: Dictionary = saved.duplicate(true)
			edited[key] = bad
			var copy: Dictionary = edited.duplicate(true)
			_rejects(owner.restore(edited, 1), "caller restore " + key)
			_expect(_snapshot(owner) == saved, "caller restore " + key + " no write")
			_expect(edited == copy, "caller restore " + key + " input untouched")
		for other: Variant in [null, "", "unknown_text"]:
			var edited: Dictionary = saved.duplicate(true)
			edited[key] = other
			_rejects(owner.restore(edited, 1), "caller restore unknown " + key)
			_expect(_snapshot(owner) == saved, "caller restore unknown " + key + " no write")
		var missing: Dictionary = saved.duplicate(true)
		missing.erase(key)
		_rejects(owner.restore(missing, 1), "caller restore missing " + key)
	for bad: Variant in _wrong_types():
		var edited: Dictionary = saved.duplicate(true)
		edited["progress"]["fingerprint"] = bad
		_rejects(owner.restore(edited, 1), "caller restore progress fingerprint")
		_expect(_snapshot(owner) == saved, "caller restore progress fingerprint no write")
	_expect(_snapshot(owner).get("generation", -1) == 1, "caller generation intact after refusals")
	_expect(owner.preview_step(2.0, 0.1) == expected, "caller context and state intact after refusals")
	_accepts(owner.commit_step(2.0, 0.1, 1), "caller valid step after refusals")
	_near(float(_snapshot(owner).get("phase", {}).get("thermal_budget_kj", NAN)), 800.0, "caller budget after refusals")
	_near(float(_snapshot(owner).get("phase", {}).get("deposited_heat_kj", NAN)), 4000.0, "caller heat after refusals")
	_accepts(owner.restore(saved, 2), "caller valid restore after refusals")
	_expect(_snapshot(owner).get("generation", -1) == 3, "caller valid restore generation")
	_completed.append("T07")


## Reference caller: a mistyped identity must not switch the coherence check off.
func _t08() -> void:
	_group("T08")
	var owner: RefCounted = Caller.new()
	_accepts(owner.initialize(_context()), "caller context for tampering")
	_accepts(owner.commit_step(1.0, 0.1, 0), "caller step for tampering")
	var saved: Dictionary = _snapshot(owner).duplicate(true)
	for bad: Variant in [1, 2.5, true, []]:
		for key: String in ["schema", "context_fingerprint"]:
			var forged: Dictionary = saved.duplicate(true)
			forged[key] = bad
			forged["phase"]["thermal_budget_kj"] = 5000.0
			forged["phase"]["liquid_fuel_kg"] = 0.25
			_rejects(owner.restore(forged, 1), "forged snapshot behind mistyped " + key)
			_expect(_snapshot(owner) == saved, "forged snapshot behind mistyped " + key + " no write")
	_near(float(_snapshot(owner).get("phase", {}).get("thermal_budget_kj", NAN)), 900.0, "owner budget not forged")
	_expect(_is_text(_snapshot(owner).get("schema"), "g3_prescribed_phase_snapshot_v1"), "owner schema still text")
	var tampered: Dictionary = saved.duplicate(true)
	tampered["phase"]["thermal_budget_kj"] = 5000.0
	_rejects(owner.restore(tampered, 1), "coherence check still active")
	_accepts(owner.commit_step(2.0, 0.1, 1), "owner still usable")
	_completed.append("T08")


## Composition with the sensible owner and its ledger does not regress.
func _t09() -> void:
	_group("T09")
	for path: Array in [["program", "mode"], ["program", "quantity"], ["material", "reference_material", "schema"],
		["material", "reference_material", "liquid_phase"], ["schema"], ["seed", "schema"]]:
		for bad: Variant in _wrong_types():
			var context: Dictionary = _sensible_context()
			var target: Dictionary = context
			for index: int in range(path.size() - 1):
				target = target[path[index]]
			target[path[-1]] = bad
			var owner: RefCounted = Owner.new()
			var label: String = "sensible owner " + ".".join(PackedStringArray(path))
			_rejects(owner.initialize(context), label)
			_expect(_snapshot(owner).is_empty(), label + " leaves no owner")
	var sensible: RefCounted = Owner.new()
	_accepts(sensible.initialize(_sensible_context()), "sensible owner valid context")
	_accepts(sensible.commit_step({"schema": "g3_prescribed_sensible_request_v1", "end_time_s": 1.0,
		"oxidation_kg": 0.0, "heat_liquid_kj": 20.0, "heat_vapour_kj": 0.0,
		"emitted_vapour_temperature_k": 398.15}, 0), "sensible owner valid step")
	_near(float(_snapshot(sensible).get("phase", {}).get("thermal_budget_kj", NAN)), 872.0, "sensible owner valid budget")
	for bad: Variant in _wrong_types():
		var edited: Dictionary = _snapshot(sensible).duplicate(true)
		edited["progress"]["fingerprint"] = bad
		_rejects(sensible.restore(edited, 1), "sensible owner restore progress fingerprint")
	_completed.append("T09")


## Inherited fingerprints are not part of this fix: their values must not move.
func _t10() -> void:
	_group("T10")
	for linear: bool in [false, true]:
		var progress: Dictionary = _candidate(Release.initial_progress(_program(linear)))
		_observe("provider_linear" if linear else "provider_measured", progress.get("fingerprint"))
	var owner: RefCounted = Caller.new()
	_accepts(owner.initialize(_context()), "caller fingerprint context")
	_observe("caller_context", _snapshot(owner).get("context_fingerprint"))
	_observe("caller_progress", _snapshot(owner).get("progress", {}).get("fingerprint"))
	var sensible: RefCounted = Owner.new()
	_accepts(sensible.initialize(_sensible_context()), "sensible fingerprint context")
	_observe("sensible_context", _snapshot(sensible).get("context_fingerprint"))
	_expect(_observations.get("caller_progress") == _observations.get("provider_measured"), "caller carries the provider fingerprint")
	_completed.append("T10")


## Acceptance kept, not widened: a StringName equal to the literal was valid
## text before this fix. It stays valid, unconverted, with the same fingerprint.
func _t11() -> void:
	_group("T11")
	var progress: Dictionary = _candidate(Release.initial_progress(_program()))
	var named: Dictionary = _program()
	for key: String in PROGRAM_LITERALS:
		named[key] = StringName(named[key])
	var named_progress: Variant = Release.initial_progress(named)
	_accepts(named_progress, "provider StringName literals")
	_expect(_is_text(_candidate(named_progress).get("fingerprint"), str(progress.get("fingerprint"))), "provider StringName fingerprint unchanged")
	var cursor: Dictionary = progress.duplicate(true)
	cursor["fingerprint"] = StringName(str(cursor.get("fingerprint")))
	_accepts(Release.propose(_program(), cursor, 1.0), "provider StringName progress identity")
	named["mode"] = &"unknown_text"
	_rejects(Release.initial_progress(named), "provider unknown StringName")
	var material: Dictionary = _reference()
	for key: String in REFERENCE_LITERALS:
		material[key] = StringName(material[key])
	var reference: Variant = Budget.propose_phase_reference(_phase_state(), _phase_request(), material)
	_accepts(reference, "reference StringName literals")
	_expect(_candidate(reference) == _candidate(Budget.propose_phase_reference(_phase_state(), _phase_request(), _reference())), "reference StringName same candidate")
	material["schema"] = &"unknown_text"
	_rejects(Budget.propose_phase_reference(_phase_state(), _phase_request(), material), "reference unknown StringName")
	var state: Dictionary = {"initial_fuel_mass_kg": 1.0, "solid_fuel_kg": 1.0, "released_fuel_kg": 0.0, "o2_kg": 10.0}
	var request: Dictionary = {"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1, "release_mode": "prescribed_mass_transfer"}
	_accepts(Budget.propose(state, request, {"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
		"chemical_heat_kj_per_kg": 20000.0, "chemical_energy_basis": &"complete_oxidation_net",
		"provenance": "synthetic:type_guard_control"}), "kernel StringName basis")
	var text_owner: RefCounted = Caller.new()
	_accepts(text_owner.initialize(_context()), "caller text context")
	var context: Dictionary = _context()
	context["schema"] = &"g3_prescribed_phase_context_v1"
	var owner: RefCounted = Caller.new()
	_accepts(owner.initialize(context), "caller StringName context schema")
	_expect(_is_text(_snapshot(owner).get("context_fingerprint"), str(_snapshot(text_owner).get("context_fingerprint"))), "caller StringName fingerprint unchanged")
	var saved: Dictionary = _snapshot(owner).duplicate(true)
	saved["schema"] = StringName(str(saved.get("schema")))
	saved["context_fingerprint"] = StringName(str(saved.get("context_fingerprint")))
	_accepts(owner.restore(saved, 0), "caller StringName snapshot identity")
	saved["schema"] = &"unknown_text"
	_rejects(owner.restore(saved, 1), "caller unknown StringName snapshot schema")
	_completed.append("T11")


## Validation is by type, never by converting the value to text.
func _t12() -> void:
	_group("T12")
	_expect(str(Impostor.new("prescribed")) == "prescribed", "control: the impostor prints as the literal")
	for key: String in PROGRAM_LITERALS:
		var program: Dictionary = _program()
		program[key] = Impostor.new(str(program[key]))
		_rejects(Release.initial_progress(program), "provider impostor " + key)
	var progress: Dictionary = _candidate(Release.initial_progress(_program()))
	progress["fingerprint"] = Impostor.new(str(progress.get("fingerprint")))
	_rejects(Release.propose(_program(), progress, 1.0), "provider impostor fingerprint")
	for key: String in REFERENCE_LITERALS:
		var material: Dictionary = _reference()
		material[key] = Impostor.new(str(material[key]))
		_rejects(Budget.propose_phase_reference(_phase_state(), _phase_request(), material), "reference impostor " + key)
	var state: Dictionary = {"initial_fuel_mass_kg": 1.0, "solid_fuel_kg": 1.0, "released_fuel_kg": 0.0, "o2_kg": 10.0}
	var request: Dictionary = {"dt_s": 1.0, "release_kg": 0.1, "oxidation_kg": 0.1, "release_mode": "prescribed_mass_transfer"}
	_rejects(Budget.propose(state, request, {"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
		"chemical_heat_kj_per_kg": 20000.0, "chemical_energy_basis": Impostor.new("complete_oxidation_net"),
		"provenance": "synthetic:type_guard_control"}), "kernel impostor basis")
	var context: Dictionary = _context()
	context["schema"] = Impostor.new("g3_prescribed_phase_context_v1")
	var refused: RefCounted = Caller.new()
	_rejects(refused.initialize(context), "caller impostor context schema")
	_expect(_snapshot(refused).is_empty(), "caller impostor context leaves no owner")
	var owner: RefCounted = Caller.new()
	_accepts(owner.initialize(_context()), "caller context for impostor")
	var saved: Dictionary = _snapshot(owner).duplicate(true)
	for key: String in ["schema", "context_fingerprint"]:
		var edited: Dictionary = saved.duplicate(true)
		edited[key] = Impostor.new(str(saved.get(key)))
		_rejects(owner.restore(edited, 0), "caller impostor snapshot " + key)
		_expect(_snapshot(owner) == saved, "caller impostor snapshot " + key + " no write")
	_completed.append("T12")


func _finish() -> void:
	# A group that aborted half way recorded its id but never completed.
	for id: String in _groups:
		if id not in _completed:
			_failed = true
			_failures.append("group aborted before completing: " + id)
	if _groups.size() != GROUPS.size():
		_failed = true
		_failures.append("not every group started")
	print("G3_TYPE_GUARD_CONTRACTS " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "observations": _observations}))
	if _failed or _completed.size() != GROUPS.size():
		quit(1)
		return
	print("G3_TYPE_GUARD_CONTRACTS_PASS")
	quit(0)


func _snapshot(owner: RefCounted) -> Dictionary:
	var value: Variant = owner.snapshot()
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _candidate(result: Variant) -> Dictionary:
	if typeof(result) != TYPE_DICTIONARY or typeof(result.get("candidate")) != TYPE_DICTIONARY:
		return {}
	return result["candidate"]


func _number(result: Variant, key: String) -> float:
	if typeof(result) != TYPE_DICTIONARY or typeof(result.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
		return NAN
	return float(result[key])


## The fixture must not repeat the defect it tests: type before comparing.
func _is_text(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected


func _group(id: String) -> void:
	_groups.append(id)


func _observe(key: String, value: Variant) -> void:
	_observations[key] = value if typeof(value) == TYPE_STRING else null
	_expect(typeof(value) == TYPE_STRING and str(value).length() == 64, key + " is a sha256 text")


func _accepts(result: Variant, label: String) -> void:
	_expect(typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result.get("valid"), label + " accepted")


## Structured rejection of the owners' own contract: valid=false, explicit
## errors and an empty candidate. An aborted call returns none of the three.
func _rejects(result: Variant, label: String) -> void:
	var data: Dictionary = result if typeof(result) == TYPE_DICTIONARY else {}
	_expect(typeof(result) == TYPE_DICTIONARY, label + " returns a dictionary")
	_expect(typeof(data.get("valid")) == TYPE_BOOL and not data.get("valid"), label + " structured valid=false")
	_expect(typeof(data.get("errors")) == TYPE_ARRAY and not data.get("errors").is_empty(), label + " explicit errors")
	_expect(typeof(data.get("candidate")) == TYPE_DICTIONARY and data.get("candidate").is_empty(), label + " empty candidate")


func _near(actual: float, expected: float, label: String) -> void:
	_expect(not is_nan(actual) and not is_inf(actual) and absf(actual - expected) <= 1.0e-9 + 1.0e-12 * maxf(absf(actual), absf(expected)), label + " observed=" + str(actual))


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		_failures.append(label)
