extends SceneTree

## H3.2b1 activation repair: the causal flag ALONE must produce data.
##
## Until 2026-08-20 `_phase3_projection_diagnostics_active()` listed only the zone
## diagnostics and the runtime ownership ledger. `_sync_auxiliary_services()`
## reasserts `ZoneFireSolver.projection_diagnostics_enabled` from that gate and is
## called repeatedly during a run, so a session started with
## `--phase3-projection-causal-diagnostics` alone had the per-call trace switched
## back off at every logging point. The ledger accumulated nothing and reported
## `data_available: false`. It failed CLOSED -- it never produced wrong numbers --
## but the flag on its own did nothing.
##
## This fixture pins the repair at the level where it lives: the activation gate,
## the trace lifecycle and the ledger's response to real projection events. The
## end-to-end proof is the scenario run recorded in the H3.2b3 document; a fixture
## cannot substitute for it and does not claim to.
##
## It deliberately does NOT touch the zone birth/death counters. They remain
## blind, and repairing them is H3.2b1b, before H3.2b4.

const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")
const ZoneFireSolverScript = preload("res://sim/core/ZoneFireSolver.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const LedgerScript = preload("res://sim/core/Phase3ProjectionCausalLedger.gd")

const EXPECTED_TESTS: int = 6
const AMBIENT_C: float = 20.0
## Deliberately far above anything these states reach, so the upper
## temperature limit never binds and cannot confound the counts. This
## fixture is about activation, not about the limit -- that is H3.2b5.
const MAX_UPPER_TEMP_C: float = 1200.0

var _failed: bool = false
var _completed: Array[String] = []


func _done(label: String) -> void:
	_completed.append(label)


func _init() -> void:
	_test_causal_flag_alone_opens_the_activation_gate()
	_test_causal_flag_alone_activates_nothing_else()
	_test_real_projection_calls_produce_events_the_ledger_counts()
	_test_begin_step_resets_the_trace_so_steps_do_not_accumulate()
	_test_ledger_leaves_legacy_room_state_untouched()
	_test_ledger_reports_available_when_the_trace_really_ran()
	if _completed.size() != EXPECTED_TESTS:
		push_error("H3.2b1-ACTIVATION ABORTED: %d/%d completed; ran %s"
			% [_completed.size(), EXPECTED_TESTS, str(_completed)])
		quit(1)
		return
	if _failed:
		quit(1)
		return
	print("PHASE3_H32B1_CAUSAL_ONLY_ACTIVATION_PASS")
	quit(0)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## RoomModel is RefCounted, so it is never freed explicitly -- calling
## free() on one aborts the enclosing test, which is how the fail-closed
## counter caught this in the first place.
func _room(room_id: int = 0):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.5
	room.reset_dynamic_state(AMBIENT_C, 0.209)
	room.upper_gas_kg = 8.0
	room.upper_energy_kj = 1600.0
	room.lower_gas_kg = 45.0
	room.lower_energy_kj = 90.0
	return room


func _solver():
	var solver = ZoneFireSolverScript.new()
	solver.two_zone_energy_enabled = true
	solver.projection_diagnostics_enabled = true
	return solver


func _state_bytes(room) -> PackedByteArray:
	return var_to_bytes({
		"upper_gas_kg": room.upper_gas_kg,
		"lower_gas_kg": room.lower_gas_kg,
		"upper_energy_kj": room.upper_energy_kj,
		"lower_energy_kj": room.lower_energy_kj,
		"temp_upper_c": room.temp_upper_c,
		"temp_lower_c": room.temp_lower_c,
		"thermal_layer_m": room.thermal_layer_m,
	})


# --------------------------------------------------------------------------
# The activation gate
# --------------------------------------------------------------------------

func _test_causal_flag_alone_opens_the_activation_gate() -> void:
	var engine = SimulationEngineScript.new()
	_expect(not engine._phase3_projection_diagnostics_active(),
		"with every flag off the gate is closed")
	engine.phase3_projection_causal_diagnostics_enabled = true
	_expect(engine._phase3_projection_diagnostics_active(),
		"the causal flag ALONE now opens the activation gate")
	engine.free()
	_done("gate_opens")


func _test_causal_flag_alone_activates_nothing_else() -> void:
	## The repair must not turn a causal user into a zone-diagnostics user or a
	## shadow user. Those change the CSV surface and run the primitive
	## respectively, and neither was opted into.
	var engine = SimulationEngineScript.new()
	engine.phase3_projection_causal_diagnostics_enabled = true
	_expect(not engine.phase3_zone_diagnostics_enabled,
		"zone diagnostics stay off, so the shared CSV surface is untouched")
	_expect(not engine.phase3_residual_projection_shadow_enabled,
		"the H3.2b3 shadow stays off, so the primitive is not evaluated")
	_expect(not engine.phase3_runtime_ownership_ledger_enabled,
		"the runtime ownership ledger stays off")
	# And the per-step zone diagnostics export stays empty, which is what the
	# CSV columns are built from.
	_expect(engine._phase3_zone_diag_export().is_empty(),
		"the zone diagnostics export is empty, so no CSV column can appear")
	engine.free()
	_done("nothing_else_activated")


# --------------------------------------------------------------------------
# The trace really runs, and the ledger really counts it
# --------------------------------------------------------------------------

func _test_real_projection_calls_produce_events_the_ledger_counts() -> void:
	var solver = _solver()
	var room = _room()
	solver.begin_projection_diagnostics_step()
	for i in range(3):
		solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, "final_clamp_active")
	var events: Array = solver.get_projection_trace_events()
	_expect(events.size() == 3,
		"three real projection calls emit three trace events")
	_expect(String(events[0]["cause"]) == "final_clamp_active",
		"and the cause survives into the event")

	var ledger = LedgerScript.new()
	ledger.enabled = true
	ledger.accumulate_step(events, {})
	var totals: Dictionary = ledger.summary()["totals"]
	_expect(int(totals["projection_call_count_total"]) == 3,
		"the ledger counts every call -- not null, not zero")
	_expect(int(totals["room_steps_total"]) == 1,
		"one room in one timestep is one room-step")
	_expect(int(totals["projection_calls_per_room_step_max"]) == 3,
		"and the multiplicity maximum is real")
	_done("events_counted")


func _test_begin_step_resets_the_trace_so_steps_do_not_accumulate() -> void:
	## The gate matters precisely because it is what causes
	## `begin_projection_diagnostics_step()` to run. Without the reset the events
	## of every step would still be present on the next one and each call would
	## be counted again and again.
	var solver = _solver()
	var room = _room()

	solver.begin_projection_diagnostics_step()
	solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, "final_clamp_active")
	solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, "final_clamp_active")
	var first: Array = solver.get_projection_trace_events()
	_expect(first.size() == 2, "step one emitted two events")

	solver.begin_projection_diagnostics_step()
	_expect(solver.get_projection_trace_events().is_empty(),
		"the per-step reset clears the trace")
	solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, "reconcile_layer_sync")
	var second: Array = solver.get_projection_trace_events()
	_expect(second.size() == 1,
		"step two sees only its own event, never step one's")

	# Two steps accumulated through the ledger give 3, not 2 + (2+1) = 5.
	var ledger = LedgerScript.new()
	ledger.enabled = true
	ledger.accumulate_step(first, {})
	ledger.accumulate_step(second, {})
	var totals: Dictionary = ledger.summary()["totals"]
	_expect(int(totals["projection_call_count_total"]) == 3,
		"cumulative counts are per-step, never re-counted")
	_expect(int(totals["timesteps_total"]) == 2, "and two timesteps are two")
	_done("per_step_reset")


# --------------------------------------------------------------------------
# Still passive
# --------------------------------------------------------------------------

func _test_ledger_leaves_legacy_room_state_untouched() -> void:
	var solver = _solver()
	var room = _room()
	solver.begin_projection_diagnostics_step()
	solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, "final_clamp_active")
	var after_projection: PackedByteArray = _state_bytes(room)

	var ledger = LedgerScript.new()
	ledger.enabled = true
	ledger.accumulate_step(solver.get_projection_trace_events(), {})
	ledger.summary()
	var after_ledger: PackedByteArray = _state_bytes(room)
	_expect(after_projection == after_ledger,
		"accumulating the ledger changes no byte of legacy room state")
	_done("legacy_state_intact")


func _test_ledger_reports_available_when_the_trace_really_ran() -> void:
	## The symptom of the old defect was `data_available: false` with
	## `projection_trace_unavailable`. With the trace genuinely running, the
	## ledger reports available and the reason list is empty.
	var solver = _solver()
	var room = _room()
	solver.begin_projection_diagnostics_step()
	solver.project_room_state(room, AMBIENT_C, MAX_UPPER_TEMP_C, "final_clamp_active")

	var ledger = LedgerScript.new()
	ledger.enabled = true
	ledger.accumulate_step(solver.get_projection_trace_events(), {})
	var summary: Dictionary = ledger.summary()
	_expect(bool(summary["data_available"]),
		"with the trace running the ledger reports data available")
	_expect(summary["unavailable_reason_codes"].is_empty(),
		"and names no missing dependency")

	# The negative control: a ledger told the trace was missing must still say
	# so, so the assertion above cannot pass merely because nothing can fail.
	var blind = LedgerScript.new()
	blind.enabled = true
	blind.record_unavailable(LedgerScript.REASON_TRACE_UNAVAILABLE)
	blind.accumulate_step([], {})
	_expect(not bool(blind.summary()["data_available"]),
		"a ledger without its trace still fails closed")
	_done("data_available")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2b1-ACTIVATION ASSERTION FAILED: %s" % label)
