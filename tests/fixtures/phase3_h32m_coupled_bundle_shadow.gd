extends SceneTree

const ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const EngineScript = preload("res://sim/core/SimulationEngine.gd")
const LogWriterScript = preload("res://sim/core/SimulationLogWriter.gd")
const StateBuilderScript = preload("res://sim/core/SimulationStateBuilder.gd")
const HeadlessRunnerScript = preload("res://tools/run_scenario_headless.gd")

var _failed: bool = false


func _init() -> void:
	_check_bundle_is_mechanical_and_isolated()
	_check_non_convergence_is_explicit_fallback()
	_check_duplicate_bundle_is_local()
	_check_wired_scripts_instantiate()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32M_COUPLED_BUNDLE_SHADOW_PASS")
	quit(0)


func _check_bundle_is_mechanical_and_isolated() -> void:
	var system = ZoneMassSystemScript.new()
	system.configure_coupled_interior_bundle_shadow(true)
	system._snapshots = _shadow()
	system._species_transit_reservoir = {
		"parcel:1": {
			"connection_id": "opening:7",
			"gas_mass_kg": 4.0,
			"sensible_enthalpy_kj": 40.0,
			"accepted_fraction": 0.25,
		}
	}
	var snapshot_before: String = JSON.stringify(system._snapshots)
	system._record_coupled_interior_bundle_shadow(_solved(true), 20.0)
	var record: Dictionary = system._coupled_interior_bundle_record
	_assert(float(record["enabled_flag"]) == 1.0, "enabled")
	_assert(float(record["valid_flag"]) == 1.0, "valid")
	_assert(float(record["bundle_count"]) == 1.0, "one coupled bundle")
	_assert(float(record["route_count"]) == 2.0, "two zonal routes")
	_assert(float(record["zero_route_skipped_count"]) == 1.0, "empty route skipped")
	_assert(
		is_equal_approx(float(record["accepted_fraction"]), 0.5),
		"one donor fraction"
	)
	_assert(is_equal_approx(float(record["requested_mass_kg"]), 3.0), "request")
	_assert(
		is_equal_approx(float(record["inventory_limited_mass_kg"]), 1.5),
		"inventory-limited mass"
	)
	_assert(
		is_equal_approx(float(record["inventory_limited_energy_kj"]), 15.0),
		"inventory-limited enthalpy"
	)
	_assert(is_equal_approx(float(record["accepted_mass_kg"]), 1.5), "accepted")
	_assert(is_equal_approx(float(record["accepted_energy_kj"]), 15.0), "enthalpy")
	_assert(float(record["counterflow_connection_count"]) == 1.0, "counterflow")
	_assert(float(record["counterflow_violation_count"]) == 0.0, "counterflow valid")
	_assert(float(record["parcel_overlap_count"]) == 1.0, "parcel overlap")
	_assert(is_equal_approx(float(record["parcel_overlap_mass_kg"]), 1.0), "parcel mass")
	_assert(is_equal_approx(float(record["parcel_overlap_energy_kj"]), 10.0), "parcel energy")
	_assert(float(record["mass_conservation_residual_kg"]) == 0.0, "mass closure")
	_assert(float(record["energy_conservation_residual_kj"]) == 0.0, "energy closure")
	_assert(float(record["double_limit_count"]) == 0.0, "no double limit")
	var cumulative: Dictionary = system._coupled_interior_bundle_cumulative
	_assert(
		is_equal_approx(float(cumulative["min_accepted_fraction"]), 0.5),
		"minimum donor fraction retained"
	)
	_assert(
		float(cumulative["max_abs_mass_conservation_residual_kg"]) == 0.0,
		"maximum mass residual retained"
	)
	_assert(float(record["source_inputs_independent_flag"]) == 0.0, "sources circular")
	_assert(float(record["comparison_valid_flag"]) == 0.0, "comparison invalid")
	_assert(
		String(record["source_provenance"])
				== "post_minus_pre_minus_legacy_interior",
		"source provenance explicit"
	)
	_assert(
		String(record["comparison_invalid_reason"])
				== "circular_legacy_source_reconstruction",
		"invalid comparison reason explicit"
	)
	_assert(system._atomic_bundle_count == 0, "legacy bundle count untouched")
	_assert(system._atomic_route_count == 0, "legacy route count untouched")
	_assert(system._atomic_bundle_ids.is_empty(), "legacy ids untouched")
	_assert(system._transactions.is_empty(), "no transaction emitted")
	_assert(JSON.stringify(system._snapshots) == snapshot_before, "state untouched")


func _check_non_convergence_is_explicit_fallback() -> void:
	var system = ZoneMassSystemScript.new()
	system.configure_coupled_interior_bundle_shadow(true)
	system._snapshots = _shadow()
	var failed: Dictionary = _solved(false)
	failed["limiting_reason"] = "iteration_cap"
	system._record_coupled_interior_bundle_shadow(failed, 20.0)
	var record: Dictionary = system._coupled_interior_bundle_record
	_assert(float(record["valid_flag"]) == 0.0, "fallback is not valid")
	_assert(float(record["solver_fallback_count"]) == 1.0, "fallback counted")
	_assert(String(record["fallback_reason"]) == "iteration_cap", "reason kept")
	_assert(float(record["bundle_count"]) == 0.0, "no copied legacy fallback")


func _check_duplicate_bundle_is_local() -> void:
	var system = ZoneMassSystemScript.new()
	system.configure_coupled_interior_bundle_shadow(true)
	system._snapshots = _shadow()
	system._record_coupled_interior_bundle_shadow(_solved(true), 20.0)
	system._record_coupled_interior_bundle_shadow(_solved(true), 20.0)
	var record: Dictionary = system._coupled_interior_bundle_record
	_assert(float(record["duplicate_bundle_count"]) == 1.0, "duplicate local")
	_assert(system._atomic_duplicate_bundle_count == 0, "legacy duplicate untouched")


func _check_wired_scripts_instantiate() -> void:
	for entry in [
		{"label": "engine", "instance": EngineScript.new()},
		{"label": "log writer", "instance": LogWriterScript.new()},
		{"label": "state builder", "instance": StateBuilderScript.new()},
		{"label": "headless runner", "instance": HeadlessRunnerScript.new()},
	]:
		var instance: Object = entry["instance"]
		_assert(instance != null, String(entry["label"]) + " compiles")
		if instance is Node:
			instance.free()


func _solved(converged: bool) -> Dictionary:
	return {
		"valid": true,
		"converged": converged,
		"limiting_reason": "",
		"zonal_decomposition_valid": true,
		"zonal_exterior_connection_skipped_count": 0.0,
		"counterflow_violation_count": 0.0,
		"connections": [{
			"connection_id": "opening:7",
			"zonal_decomposition_applicable": true,
			"zonal_routes": [
				{
					"direction": "a_to_b",
					"source_room_id": 0,
					"destination_room_id": 1,
					"source_zone": "lower",
					"destination_zone": "lower",
					"gas_mass_kg": 0.0,
					"sensible_energy_kj": 0.0,
				},
				{
					"direction": "a_to_b",
					"source_room_id": 0,
					"destination_room_id": 1,
					"source_zone": "upper",
					"destination_zone": "lower",
					"gas_mass_kg": 2.0,
					"sensible_energy_kj": 20.0,
				},
				{
					"direction": "b_to_a",
					"source_room_id": 1,
					"destination_room_id": 0,
					"source_zone": "upper",
					"destination_zone": "lower",
					"gas_mass_kg": 1.0,
					"sensible_energy_kj": 10.0,
				},
			],
		}],
	}


func _shadow() -> Dictionary:
	return {
		"0": _room_state(1.0, 10.0),
		"1": _room_state(10.0, 100.0),
	}


func _room_state(upper_mass: float, upper_energy: float) -> Dictionary:
	return {
		"upper_gas_kg": upper_mass,
		"lower_gas_kg": 10.0,
		"upper_energy_kj": upper_energy,
		"lower_energy_kj": 100.0,
		"upper_o2_kg": 0.0,
		"lower_o2_kg": 0.0,
		"upper_species_kg": {},
		"lower_species_kg": {},
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-M coupled bundle shadow: " + message)
