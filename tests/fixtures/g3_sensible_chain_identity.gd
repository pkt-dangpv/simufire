extends SceneTree

## Before/after identity corpus of the SYNTHETIC ledger and sensible owner.
## It makes no claim of its own: every proposal, preview, commit, restore,
## snapshot and report is serialised bit for bit and hashed, so the digest
## moves if any value, type, key order or message of the synthetic path moves.
const Budget = preload("res://sim/fire/FuelMassBudgetModel.gd")
const Controller = preload("res://sim/fire/PrescribedSensiblePhaseController.gd")
var _state: int = 20261007
var _context: HashingContext = HashingContext.new()
var _counts: Dictionary = {"cases": 0, "valid": 0, "rejected": 0}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_context.start(HashingContext.HASH_SHA256)
	_ledger_corpus()
	_owner_corpus()
	print("G3_SENSIBLE_CHAIN_IDENTITY " + JSON.stringify({"cases": _counts["cases"],
		"valid": _counts["valid"], "rejected": _counts["rejected"],
		"sha256": _context.finish().hex_encode()}))
	print("G3_SENSIBLE_CHAIN_IDENTITY_DONE")
	quit(0)


func _ledger_corpus() -> void:
	for variant: int in range(4):
		var material: Dictionary = _material(variant % 2 == 1)
		var state: Dictionary = _phase(1.0 + 0.5 * variant, 10.0 - 2.0 * variant, 1000.0 * (variant + 1))
		for step: int in range(120):
			var request: Dictionary = {"dt_s": [0.0, 0.5, 1.0, 2.0][step % 4],
				"release_kg": 0.2 * _unit(), "oxidation_kg": 0.15 * _unit(),
				"heat_liquid_kj": 60.0 * _unit() if step % 3 != 0 else 0.0,
				"heat_vapour_kj": 20.0 * _unit() if step % 5 == 0 else 0.0,
				"emitted_vapour_temperature_k": 273.15 + 225.0 * _unit()}
			var result: Dictionary = Budget.propose_phase_sensible(state, request, material)
			_record(result)
			if result.get("valid", false):
				state = result["candidate"]
		for key: String in state:
			var missing: Dictionary = state.duplicate(true)
			missing.erase(key)
			_record(Budget.propose_phase_sensible(missing, _idle(), material))
			for bad: Variant in [NAN, INF, -1.0, true, "1", null, 7]:
				var changed: Dictionary = state.duplicate(true)
				changed[key] = bad
				_record(Budget.propose_phase_sensible(changed, _idle(), material))
		for key: String in _idle():
			for bad: Variant in [NAN, -INF, -1.0, false, "1", null, 1.0e308, 600.0, 100.0]:
				var request: Dictionary = _idle()
				request["dt_s"] = 1.0
				request[key] = bad
				_record(Budget.propose_phase_sensible(state, request, material))
		for key: String in ["liquid_profile", "vapour_profile"]:
			for edit: Array in [["schema", "g3_real_liquid_isobaric_cp_v1"], ["phase", "solid"],
				["temperature_scale", "ITS-90_kelvin"], ["provenance", "primary:sha256:0"],
				["component_id", "n-heptane"], ["samples", []], ["extra", 1.0]]:
				var changed: Dictionary = material.duplicate(true)
				changed[key][edit[0]] = edit[1]
				_record(Budget.propose_phase_sensible(state, _idle(), changed))
		for edit: Array in [["schema", "g3_phase_real_sensible_material_v1"], ["component_id", 3],
			["reference_material", {}], ["liquid_profile", null], ["extra", true]]:
			var changed: Dictionary = material.duplicate(true)
			changed[edit[0]] = edit[1]
			_record(Budget.propose_phase_sensible(state, _idle(), changed))
		for key: String in material["reference_material"]:
			for bad: Variant in [null, -1.0, "x", 1.0e308]:
				var changed: Dictionary = material.duplicate(true)
				changed["reference_material"][key] = bad
				_record(Budget.propose_phase_sensible(state, _idle(), changed))
	for bad: Variant in [null, [], "state", 1, {}]:
		_record(Budget.propose_phase_sensible(bad, _idle(), _material(false)))
		_record(Budget.propose_phase_sensible(_phase(1.0, 10.0, 1000.0), bad, _material(false)))
		_record(Budget.propose_phase_sensible(_phase(1.0, 10.0, 1000.0), _idle(), bad))


func _owner_corpus() -> void:
	for variant: int in range(6):
		var context: Dictionary = _owner_context(500.0 * (variant + 1), 10.0 - variant,
			[0.0, 20.0, -10.0][variant % 3], 1.0 + 0.25 * variant, variant % 2 == 0)
		var owner: RefCounted = Controller.new()
		_record(owner.preview_step(_request(0.5)))
		_record(owner.commit_step(_request(0.5), 0))
		_record(owner.initialize(context))
		_record(owner.initialize(context))
		_record({"snapshot": owner.snapshot()})
		var saved: Array = []
		var time: float = 0.0
		for step: int in range(40):
			time += [0.0, 0.1, 0.25, 0.5][step % 4]
			var request: Dictionary = _request(time, 0.05 * _unit(), 30.0 * _unit() if step % 2 == 0 else 0.0,
				5.0 * _unit() if step % 7 == 0 else 0.0, 280.0 + 200.0 * _unit())
			_record(owner.preview_step(request))
			var generation: int = owner.snapshot().get("generation", -1)
			_record(owner.commit_step(request, generation if step % 9 != 4 else generation + 3))
			if step % 6 == 0:
				saved.append(owner.snapshot())
			if step % 11 == 10 and not saved.is_empty():
				_record(owner.restore(saved[step % saved.size()], owner.snapshot().get("generation", -1)))
				time = owner.snapshot().get("physical_time_s", time)
		_record(owner.preview_step(_request(time - 1.0)))
		for bad: Variant in [null, 1, "request", {}, []]:
			_record(owner.preview_step(bad))
			_record(owner.restore(bad, owner.snapshot().get("generation", -1)))
		var forged: Dictionary = owner.snapshot()
		forged["phase"]["thermal_budget_kj"] = 5000.0
		_record(owner.restore(forged, owner.snapshot().get("generation", -1)))
		forged = owner.snapshot()
		forged["context_fingerprint"] = "0"
		_record(owner.restore(forged, owner.snapshot().get("generation", -1)))
		_record(owner.restore(owner.snapshot(), true))
		_record({"snapshot": owner.snapshot()})
	var base: Dictionary = _owner_context(1000.0, 10.0, 0.0, 1.0, true)
	for key: String in base:
		var missing: Dictionary = base.duplicate(true)
		missing.erase(key)
		_record(Controller.new().initialize(missing))
	for edit: Array in [["schema", "g3_prescribed_real_sensible_context_v1"], ["seed", {}], ["program", null],
		["material", 1], ["attribution", []], ["extra", 1]]:
		var changed: Dictionary = base.duplicate(true)
		changed[edit[0]] = edit[1]
		_record(Controller.new().initialize(changed))
	for key: String in base["seed"]:
		for bad: Variant in [null, -1.0, "x", NAN, true]:
			var changed: Dictionary = base.duplicate(true)
			changed["seed"][key] = bad
			_record(Controller.new().initialize(changed))
	for key: String in base["attribution"]:
		var changed: Dictionary = base.duplicate(true)
		changed["attribution"][key] = "other"
		_record(Controller.new().initialize(changed))
	for bad: Variant in [null, [], "context", 1, {}]:
		_record(Controller.new().initialize(bad))


func _record(result: Dictionary) -> void:
	_counts["cases"] += 1
	_counts["valid" if result.get("valid", false) else "rejected"] += 1
	_context.update(var_to_bytes(result))


func _unit() -> float:
	_state = (_state * 1103515245 + 12345) % 2147483648
	return float(_state) / 2147483648.0


func _profile(phase: String, cp: float, sloped: bool) -> Dictionary:
	return {"schema": "g3_synthetic_isobaric_cp_v1", "component_id": "synthetic_CHO",
		"phase": phase, "caloric_model": "declared_liquid" if phase == "liquid" else "ideal_gas",
		"pressure_path": "constant_pressure", "reference_temperature_k": 298.15,
		"reference_pressure_pa": 100000.0, "temperature_scale": "synthetic_kelvin",
		"quantity": "isobaric_specific_heat", "quantity_unit": "kJ/(kg*K)",
		"interpolation": "piecewise_linear", "calibration_status": "synthetic_not_material_calibration",
		"provenance": "synthetic: chain identity corpus", "samples": [
			{"temperature_k": 273.15, "cp_kj_kg_k": cp},
			{"temperature_k": 385.65, "cp_kj_kg_k": cp * (1.25 if sloped else 1.0)},
			{"temperature_k": 498.15, "cp_kj_kg_k": cp * (1.1 if sloped else 1.0)}]}


func _material(sloped: bool) -> Dictionary:
	return {"schema": "g3_phase_sensible_material_v1", "component_id": "synthetic_CHO",
		"liquid_profile": _profile("liquid", 2.0, sloped), "vapour_profile": _profile("gas", 1.0, sloped),
		"reference_material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid",
			"vapour_phase": "gas", "water_product_phase": "gas", "atom_mass_basis": "nominal_C12_H1_O16",
			"chemical_energy_basis": "complete_oxidation_net", "reference_temperature_k": 298.15,
			"reference_pressure_pa": 100000.0, "mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0},
			"liquid_heat_kj_kg": 19000.0, "vapour_heat_kj_kg": 20000.0,
			"phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic: CHO identity corpus, not a measured fuel"}}


func _phase(mass: float, oxygen: float, budget: float) -> Dictionary:
	return {"schema": "g3_phase_sensible_state_v1", "component_id": "synthetic_CHO",
		"initial_fuel_mass_kg": mass, "liquid_fuel_kg": mass, "vapour_fuel_kg": 0.0, "o2_kg": oxygen,
		"thermal_budget_kj": budget, "deposited_heat_kj": 0.0, "liquid_sensible_kj": 0.0,
		"vapour_sensible_kj": 0.0}


func _idle() -> Dictionary:
	return {"dt_s": 0.0, "release_kg": 0.0, "oxidation_kg": 0.0, "heat_liquid_kj": 0.0,
		"heat_vapour_kj": 0.0, "emitted_vapour_temperature_k": 298.15}


func _owner_context(budget: float, oxygen: float, liquid_sensible: float, mass: float, linear: bool) -> Dictionary:
	var id: String = "synthetic_CHO" if linear else "synthetic_observed_reservoir"
	return {"schema": "g3_prescribed_sensible_context_v1",
		"program": {"profile_id": "synthetic_constant", "component_id": id, "initial_mass_kg": mass,
			"mode": "prescribed", "quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
			"unit": "kg/s", "time_origin": "synthetic_zero", "outside_domain": "reject",
			"interpolation": "piecewise_linear" if linear else "piecewise_constant_left",
			"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.05},
				{"time_s": 6.0, "rate_kg_s": 0.0}]},
		"material": _material(not linear),
		"attribution": {"input_component_id": id, "modeled_component_id": "synthetic_CHO",
			"input_quantity": "modeled_component_emission" if linear else "measured_reservoir_depletion",
			"rule": "same_declared_component" if linear else "all_depletion_as_reference_vapour",
			"status": "synthetic_declared_emission" if linear else "conditional_not_measured_emission",
			"provenance": "synthetic:no_experimental_approval"},
		"seed": {"schema": "g3_prescribed_sensible_seed_v1", "initial_o2_kg": oxygen,
			"initial_thermal_budget_kj": budget, "initial_liquid_sensible_kj": liquid_sensible,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"}}


func _request(end: float, oxidation: float = 0.0, heat_liquid: float = 0.0,
	heat_vapour: float = 0.0, temperature: float = 298.15) -> Dictionary:
	return {"schema": "g3_prescribed_sensible_request_v1", "end_time_s": end,
		"oxidation_kg": oxidation, "heat_liquid_kj": heat_liquid, "heat_vapour_kj": heat_vapour,
		"emitted_vapour_temperature_k": temperature}
