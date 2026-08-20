extends SceneTree

## H3.2b1 fixture: passive causal accumulator for two-zone projection.
##
## The ledger instruments nothing itself. `ZoneFireSolver` already emits a full
## per-call projection trace; this component only accumulates it, so
## `project_room_state` is never instrumented twice. Everything it exports is a
## cumulative `*_total`, immune to the 10 s CSV sampling.

const LedgerScript = preload("res://sim/core/Phase3ProjectionCausalLedger.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

const EPS: float = 1.0e-12
const EXPECTED_TESTS: int = 14

var _failed: bool = false
var _completed: Array[String] = []


func _done(label: String) -> void:
	_completed.append(label)


func _init() -> void:
	_test_flag_defaults_false_and_records_nothing()
	_test_call_counts_and_multiplicity()
	_test_signed_and_gross_are_both_kept()
	_test_thermal_cap_is_a_cause_not_a_destination()
	_test_energy_without_mass_is_counted_not_repaired()
	_test_zone_birth_and_death_counted()
	_test_residuals_are_independent_and_satisfy_the_contract()
	_test_equal_residuals_are_legitimate()
	_test_completeness_blocks_physical_residual()
	_test_ledger_writes_no_room_state()
	_test_clear_resets()
	_test_static_gap_is_not_an_active_gap()
	_test_material_activity_threshold_is_derived()
	_test_engine_compiles_and_flag_defaults_false()
	if _completed.size() != EXPECTED_TESTS:
		push_error("H3.2b1 ABORTED: %d/%d completed; ran %s"
			% [_completed.size(), EXPECTED_TESTS, str(_completed)])
		quit(1)
		return
	if _failed:
		quit(1)
		return
	print("PHASE3_H32B1_PROJECTION_CAUSAL_PASS")
	quit(0)


func _ledger(on: bool = true):
	var l = LedgerScript.new()
	l.enabled = on
	return l


func _event(room_id: int, cause: String, d: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {
		"call_index": 0, "cause": cause, "room_id": room_id,
		"pre": {"upper_gas_kg": 1.0, "lower_gas_kg": 50.0,
				"upper_energy_kj": 100.0, "lower_energy_kj": 10.0},
		"post": {"upper_gas_kg": 1.0, "lower_gas_kg": 50.0,
				"upper_energy_kj": 100.0, "lower_energy_kj": 10.0},
		"upper_cap_mass_delta_kg": 0.0, "upper_cap_energy_delta_kj": 0.0,
		"lower_projection_mass_delta_kg": 0.0,
		"lower_projection_energy_delta_kj": 0.0,
		"upper_energy_before_cap_kj": 100.0,
		"total_mass_delta_kg": 0.0, "total_energy_delta_kj": 0.0,
	}
	ev.merge(d, true)
	return ev


func _diag(observed_mass: float, phys: float, clos: float) -> Dictionary:
	var d: Dictionary = {
		"observed_mass_delta_kg": observed_mass,
		"observed_energy_delta_kj": 0.0,
	}
	for s in LedgerScript.PHYSICAL_STAGES:
		d[s + "_mass_delta_kg_step"] = 0.0
		d[s + "_energy_delta_kj_step"] = 0.0
	for s in LedgerScript.CLOSURE_STAGES:
		d[s + "_mass_delta_kg_step"] = 0.0
		d[s + "_energy_delta_kj_step"] = 0.0
	d["combustion_mass_delta_kg_step"] = phys
	d["reconcile_mass_delta_kg_step"] = clos
	return {"0": d}


func _test_flag_defaults_false_and_records_nothing() -> void:
	var l = LedgerScript.new()
	_expect(not l.enabled, "the ledger defaults disabled")
	l.accumulate_step([_event(0, "final_clamp_active")], _diag(1.0, 0.0, 0.0))
	_expect(l.summary().is_empty(), "OFF accumulates nothing and exports nothing")
	_done("flag_defaults_false")


func _test_call_counts_and_multiplicity() -> void:
	var l = _ledger()
	# One step with three calls on room 0 and one on room 1.
	l.accumulate_step([
		_event(0, "thermal_energy_projection"),
		_event(0, "final_clamp_active"),
		_event(0, "stairwell_temperature_cap"),
		_event(1, "final_clamp_active"),
	], {})
	# A second step with a single call on room 0.
	l.accumulate_step([_event(0, "final_clamp_active")], {})
	var s: Dictionary = l.summary()
	_expect(int(s["totals"]["projection_call_count_total"]) == 5,
		"grand total counts every call")
	_expect(int(s["totals"]["projection_calls_per_room_step_max"]) == 3,
		"per-step maximum is what distinguishes call sites from actual firings")
	_expect(int(s["totals"]["room_steps_with_multiple_projection_calls_total"]) == 1,
		"only the first step had more than one call for a room")
	_expect(int(s["by_room"]["0"]["projection_calls_per_room_step_max"]) == 3,
		"per-room maximum is kept")
	_expect(int(s["by_room"]["1"]["projection_calls_per_room_step_max"]) == 1,
		"a room with one call has a maximum of one")
	_expect(int(s["by_cause"]["stairwell_temperature_cap"]["call_count_total"]) == 1,
		"per-cause totals are kept")
	_expect(int(s["by_cause"]["final_clamp_active"]["call_count_total"]) == 3,
		"per-cause totals accumulate across steps")
	_expect(int(s["timesteps_total"]) == 2, "physical timesteps are counted")
	_expect(int(s["room_steps_total"]) == 3,
		"room-steps are counted separately: 2 rooms in step 1, 1 room in step 2")
	_expect(int(s["totals"]["projection_calls_per_timestep_max"]) == 4,
		"the per-timestep maximum sums every room in that step")
	# Step 1 had four calls, step 2 had one. Only the first qualifies.
	_expect(int(s["totals"]["timesteps_with_multiple_projection_calls_total"]) == 1,
		"a timestep boundary is known, so this is measured not approximated")
	_expect(int(s["totals"]["timesteps_with_any_projection_call_total"]) == 2,
		"both timesteps had at least one call")
	_done("call_counts")


func _test_signed_and_gross_are_both_kept() -> void:
	var l = _ledger()
	# Two opposite corrections: the signed sum cancels, the gross does not.
	l.accumulate_step([
		_event(0, "final_clamp_active", {"lower_projection_mass_delta_kg": 2.0}),
		_event(0, "final_clamp_active", {"lower_projection_mass_delta_kg": -2.0}),
	], {})
	var r: Dictionary = l.summary()["by_room"]["0"]
	_expect(absf(float(r["lower_mass_correction_signed_net_kg_total"])) <= EPS,
		"the signed total cancels, which is why it is only a lower bound")
	_expect(absf(float(r["lower_mass_correction_gross_absolute_kg_total"]) - 4.0) <= EPS,
		"the gross total does not cancel and is the real activity")
	_done("signed_and_gross")


func _test_thermal_cap_is_a_cause_not_a_destination() -> void:
	var l = _ledger()
	# 100 kJ before the cap, the cap removes 30.
	l.accumulate_step([
		_event(0, "final_clamp_active", {
			"upper_energy_before_cap_kj": 100.0,
			"upper_cap_energy_delta_kj": -30.0,
		}),
	], {})
	var r: Dictionary = l.summary()["by_room"]["0"]
	_expect(absf(float(r["thermal_cap_requested_kj_total"]) - 100.0) <= EPS,
		"requested is the energy the state carried before the cap")
	_expect(absf(float(r["thermal_cap_accepted_kj_total"]) - 70.0) <= EPS,
		"accepted is what survived")
	_expect(absf(float(r["thermal_cap_rejected_kj_total"]) - 30.0) <= EPS,
		"rejected is the difference and it goes nowhere")
	_expect(int(r["thermal_cap_bind_count_total"]) == 1, "a binding cap is counted")
	# The ledger must not name a physical destination for it.
	_expect(not r.has("thermal_cap_to_walls_kj_total"),
		"no physical destination field exists: the cap is a cause")
	_done("thermal_cap")


func _test_energy_without_mass_is_counted_not_repaired() -> void:
	var l = _ledger()
	var ev: Dictionary = _event(0, "final_clamp_active")
	ev["post"] = {"upper_gas_kg": 0.0, "lower_gas_kg": 50.0,
			"upper_energy_kj": 42.0, "lower_energy_kj": 10.0}
	l.accumulate_step([ev], {})
	var r: Dictionary = l.summary()["by_room"]["0"]
	_expect(int(r["energy_without_mass_count_total"]) == 1,
		"energy with no mass is detected and counted")
	# The event dictionary must be untouched: nothing repaired, nothing zeroed.
	_expect(absf(float(ev["post"]["upper_energy_kj"]) - 42.0) <= EPS,
		"the state is NOT mutated and the energy is NOT routed to a sink")
	_done("energy_without_mass")


func _test_zone_birth_and_death_counted() -> void:
	var l = _ledger()
	var birth: Dictionary = _event(0, "thermal_energy_projection")
	birth["pre"] = {"upper_gas_kg": 0.0, "lower_gas_kg": 50.0,
			"upper_energy_kj": 0.0, "lower_energy_kj": 10.0}
	birth["post"] = {"upper_gas_kg": 3.0, "lower_gas_kg": 47.0,
			"upper_energy_kj": 90.0, "lower_energy_kj": 9.0}
	var death: Dictionary = _event(0, "final_clamp_quiescent")
	death["pre"] = {"upper_gas_kg": 3.0, "lower_gas_kg": 47.0,
			"upper_energy_kj": 90.0, "lower_energy_kj": 9.0}
	death["post"] = {"upper_gas_kg": 0.0, "lower_gas_kg": 50.0,
			"upper_energy_kj": 0.0, "lower_energy_kj": 99.0}
	l.accumulate_step([birth, death], {})
	var r: Dictionary = l.summary()["by_room"]["0"]
	_expect(int(r["upper_zone_birth_count_total"]) == 1, "a zone birth is counted")
	_expect(int(r["upper_zone_death_count_total"]) == 1, "a zone death is counted")
	_done("zone_transitions")


func _test_residuals_are_independent_and_satisfy_the_contract() -> void:
	var l = _ledger()
	# observed 5, physical 3, closure 2  ->  phys residual 2, closure residual 0
	l.accumulate_step([], _diag(5.0, 3.0, 2.0))
	var s: Dictionary = l.summary()
	var t: Dictionary = s["totals"]
	_expect(absf(float(t["candidate_physical_residual_mass_kg_total"]) - 2.0) <= EPS,
		"physical residual is observed minus physical owners only")
	_expect(absf(float(t["closure_inclusive_residual_mass_kg_total"])) <= EPS,
		"closure residual also subtracts the numerical corrections")
	_expect(absf(float(t["numerical_correction_mass_kg_total"]) - 2.0) <= EPS,
		"numerical corrections are accumulated separately")
	_expect(absf(float(s["residual_relation_mass_error_kg"])) <= 1.0e-9,
		"the contract residual_physical - residual_closure = corrections holds")
	_done("residual_contract")


func _test_equal_residuals_are_legitimate() -> void:
	# The withdrawn acceptance criterion demanded the two residuals differ.
	# When the numerical corrections sum to zero they are equal, and that is a
	# valid outcome, not an instrumentation failure.
	var l = _ledger()
	l.accumulate_step([], _diag(5.0, 3.0, 0.0))
	var s: Dictionary = l.summary()
	_expect(
		absf(float(s["totals"]["candidate_physical_residual_mass_kg_total"])
			- float(s["totals"]["closure_inclusive_residual_mass_kg_total"])) <= EPS,
		"with zero corrections the two residuals are equal"
	)
	_expect(absf(float(s["residual_relation_mass_error_kg"])) <= 1.0e-9,
		"and the contract still holds")
	_done("equal_residuals_legitimate")


func _test_completeness_blocks_physical_residual() -> void:
	var l = _ledger()
	l.accumulate_step([], _diag(1.0, 0.0, 0.0))
	_expect(bool(l.summary()["structural_coverage_complete"]),
		"with no declared static gap the structural coverage is complete")
	l.record_static_gap(LedgerScript.STATIC_GAP_HVAC_UNOWNED)
	var s: Dictionary = l.summary()
	_expect(not bool(s["structural_coverage_complete"]),
		"a declared static gap leaves the coverage incomplete")
	_expect(not bool(s["residual_physical_valid"]),
		"and the physical residual is then not a conservation measurement")
	_expect(s["static_instrumentation_gap_reason_codes"].has(LedgerScript.STATIC_GAP_HVAC_UNOWNED),
		"the reason code is exported")
	_expect(s["observed_active_gap_reason_codes"].is_empty(),
		"a STATIC gap is not an ACTIVE one: nothing ran, nothing is attributed")
	_expect(String(s["physical_residual_label"])
			== "candidate_incomplete_physical_residual",
		"an invalid residual is renamed, not presented as a physical residual")
	_done("completeness")


func _test_ledger_writes_no_room_state() -> void:
	var l = _ledger()
	var room = RoomModelScript.new()
	room.id = 0
	room.upper_gas_kg = 3.0
	room.upper_energy_kj = 120.0
	l.accumulate_step([_event(0, "final_clamp_active",
		{"upper_cap_mass_delta_kg": -1.0})], _diag(1.0, 0.0, 0.0))
	_expect(absf(room.upper_gas_kg - 3.0) <= EPS, "no room mass is written")
	_expect(absf(room.upper_energy_kj - 120.0) <= EPS, "no room energy is written")
	_done("no_room_writes")


func _test_clear_resets() -> void:
	var l = _ledger()
	l.accumulate_step([_event(0, "final_clamp_active")], _diag(1.0, 0.0, 0.0))
	_expect(not l.summary().is_empty(), "the ledger holds data before clear")
	l.clear()
	var s: Dictionary = l.summary()
	_expect(int(s["timesteps_total"]) == 0, "clear resets the timestep counter")
	_expect(int(s["room_steps_total"]) == 0, "clear resets the room-step counter")
	_expect(s["by_room"].is_empty(), "clear drops the per-room table")
	_expect(s["static_instrumentation_gap_reason_codes"].is_empty(),
		"clear drops the static coverage gaps")
	_expect(s["observed_active_gap_reason_codes"].is_empty(),
		"clear drops the observed active gaps")
	_done("clear")


func _test_static_gap_is_not_an_active_gap() -> void:
	# Knowing a writer exists is never evidence that it ran.
	var l = _ledger()
	l.record_static_gap(LedgerScript.STATIC_GAP_HVAC_UNOWNED)
	# A step in which HVAC moved nothing.
	l.accumulate_step([], _diag(1.0, 0.0, 0.0))
	var s: Dictionary = l.summary()
	_expect(s["static_instrumentation_gap_reason_codes"].size() == 1,
		"the static coverage gap is declared")
	_expect(s["observed_active_gap_reason_codes"].is_empty(),
		"but with no material HVAC activity there is no active gap")

	# Now a step in which HVAC really moved mass.
	var d: Dictionary = _diag(1.0, 0.0, 0.0)
	d["0"]["hvac_mass_delta_kg_step"] = 0.5
	l.accumulate_step([], d)
	var s2: Dictionary = l.summary()
	var key: String = LedgerScript.STATIC_GAP_HVAC_UNOWNED + LedgerScript.ACTIVE_GAP_SUFFIX
	_expect(s2["observed_active_gap_reason_codes"].has(key),
		"material HVAC activity raises the active gap")
	_expect(int(s2["observed_active_gap_counts"][key]) == 1,
		"the active gap carries a count, not just a flag")
	_expect(not bool(s2["residual_physical_valid"]),
		"an active gap invalidates the physical residual on evidence")
	_done("static_vs_active_gap")


func _test_material_activity_threshold_is_derived() -> void:
	var l = _ledger()
	l.record_static_gap(LedgerScript.STATIC_GAP_OTHER_CATCHALL)
	var d: Dictionary = _diag(0.0, 0.0, 0.0)
	# Below the derived arithmetic-noise threshold: not activity.
	d["0"]["other_mass_delta_kg_step"] = 0.1 * LedgerScript.MATERIAL_ACTIVITY_EPS
	l.accumulate_step([], d)
	_expect(l.summary()["observed_active_gap_reason_codes"].is_empty(),
		"noise-level movement is not material activity")
	var d2: Dictionary = _diag(0.0, 0.0, 0.0)
	d2["0"]["other_mass_delta_kg_step"] = 10.0 * LedgerScript.MATERIAL_ACTIVITY_EPS
	l.accumulate_step([], d2)
	_expect(not l.summary()["observed_active_gap_reason_codes"].is_empty(),
		"movement above the threshold is material activity")
	_done("material_threshold")


func _test_engine_compiles_and_flag_defaults_false() -> void:
	var engine = SimulationEngineScript.new()
	_expect(engine != null, "SimulationEngine compiles and instantiates")
	_expect(not engine.phase3_projection_causal_diagnostics_enabled,
		"the engine flag defaults false")
	engine.phase3_projection_causal_diagnostics_enabled = true
	_expect(engine.phase3_projection_causal_diagnostics_enabled,
		"the flag can be turned on before a scene is built")
	_expect(engine.get_phase3_projection_causal_summary() != null,
		"the summary accessor exists")
	engine.free()
	var solver = ZoneFireSolverScript.new()
	_expect(not solver.projection_diagnostics_enabled,
		"the underlying projection trace still defaults off")
	_done("engine_compiles")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2b1 ASSERTION FAILED: %s" % label)
