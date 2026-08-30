from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")
TRACE_RECORD = (ROOT / "sim/core/Phase3ProjectionTraceRecord.gd")
RESIDUAL_SHADOW = (
    ROOT / "sim/core" / ("Phase3Residual" + "ProjectionShadow.gd")
).read_text(encoding="utf-8")
RESIDUAL_PRIMITIVE = (
    ROOT / "sim/core" / ("Phase3Residual" + "Projection.gd")
).read_text(encoding="utf-8")
O2_LEDGER = (ROOT / "sim/core/Phase3O2AcceptanceLedger.gd").read_text(
    encoding="utf-8"
)
CAUSAL_LEDGER = (ROOT / "sim/core/Phase3ProjectionCausalLedger.gd").read_text(
    encoding="utf-8"
)
TRANSITION_LEDGER = (
    ROOT / "sim/core/Phase3ZoneTransitionLedger.gd"
).read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
GODOT_TEST_LAUNCHER = ROOT / "tests/godot_runtime_launcher.py"
DIRECT_GODOT_TESTS = (
    ROOT / "tests/test_case_runner_report_write_fail_closed.py",
    ROOT / "tests/test_p1r2_tick_boundary_runtime.py",
    ROOT / "tests/test_phase3_f33v2c_fuel_object_sync.py",
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}("
    start = source.index(marker)
    next_function = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_function < 0 else source[start:next_function]


def test_headless_clock_loop_does_not_export_diagnostics_twice_per_tick():
    body = _function(RUNNER, "_run_loop")

    assert "var sim_time_s: float = engine.sim_time_s" in body
    assert "sim_time_s = engine.sim_time_s" in body
    assert body.count("engine.get_state()") == 1
    assert "if _projection_trace_enabled:" in body
    assert "_append_projection_trace(state, sim_time_s)" in body


def test_internal_diagnostic_consumers_share_the_step_trace_read_only():
    public_getter = _function(SOLVER, "get_projection_trace_events")
    internal_peek = _function(SOLVER, "peek_projection_trace_records")

    assert "TraceRecordScript.to_dictionary" in public_getter
    assert "return _projection_trace_records" in internal_peek
    assert "duplicate" not in internal_peek

    for function_name in (
        "_phase3_runtime_ownership_export",
        "_phase3_projection_diagnostics_accumulate_shared",
    ):
        body = _function(ENGINE, function_name)
        assert "zone_fire_solver.peek_projection_trace_records()" in body
        assert "zone_fire_solver.get_projection_trace_events()" not in body


def test_projection_trace_allocates_one_compact_record_per_call():
    assert TRACE_RECORD.is_file()
    schema = TRACE_RECORD.read_text(encoding="utf-8")
    project = _function(SOLVER, "project_room_state")

    assert "enum Field" in schema
    assert "func new_record() -> Array:" in schema
    assert "func capture_state(record: Array" in schema
    assert "func to_dictionary(record: Array) -> Dictionary:" in schema
    allocator = _function(SOLVER, "_projection_trace_record_for_call")
    assert "TraceRecordScript.new_record()" not in project
    assert project.count("_projection_trace_record_for_call()") == 1
    assert allocator.count("TraceRecordScript.new_record()") == 1
    assert "_projection_trace_record_pool" in allocator
    assert project.count("TraceRecordScript.capture_state(") == 4
    assert "_projection_state(room)" not in project
    assert "_projection_trace_records.append(trace_record)" in project
    assert "_projection_trace_records.append({" not in project


def test_external_state_and_summary_keep_defensive_trace_copies():
    state = _function(ENGINE, "get_state")
    assert "zone_fire_solver.get_projection_trace_events()" in state
    assert (
        'summary["phase3_projection_trace"] = '
        "zone_fire_solver.get_projection_trace_events()" in ENGINE
    )


def test_runtime_ownership_is_exported_once_per_state_snapshot():
    get_state = _function(ENGINE, "get_state")
    context = _function(ENGINE, "_build_state_context")

    assert get_state.count("_phase3_runtime_ownership_export()") == 1
    assert "_build_state_context(ownership)" in get_state
    assert 'ownership.get("rooms", {})' in context
    assert 'ownership.get("parcel", {})' in context


def test_runtime_ownership_stage_checkpoints_are_compact_and_in_place():
    snapshot = _function(ENGINE, "_phase3_runtime_ownership_snapshot")
    stage = _function(ENGINE, "_phase3_runtime_ownership_record_stage")

    assert "enum RuntimeOwnershipState" in ENGINE
    assert "_phase3_runtime_ownership_room_state(room)" in snapshot
    assert "_phase3_runtime_ownership_snapshot()" not in stage
    assert "_phase3_runtime_ownership_room_state(room)" not in stage
    assert "room.upper_gas_kg" in stage
    assert "room.lower_energy_kj" in stage
    assert "_phase3_runtime_ownership_checkpoint[room_key] = before" in stage
    assert 'after.get("upper_mass_kg"' not in stage


def test_runtime_ownership_stage_deltas_serialize_only_at_export():
    stage = _function(ENGINE, "_phase3_runtime_ownership_record_stage")
    export = _function(ENGINE, "_phase3_runtime_ownership_export")

    assert "_phase3_runtime_ownership_new_step_block()" in stage
    assert '"%s_%s_delta_step"' not in stage
    assert "stage_offset + RuntimeOwnershipState.UPPER_MASS_KG" in stage
    assert "stage_offset + RuntimeOwnershipState.LOWER_ENERGY_KJ" in stage
    assert '"%s_%s_delta_step"' in export


def test_residual_shadow_reuses_only_exact_pure_projection_inputs():
    accumulate = _function(RESIDUAL_SHADOW, "accumulate_event")
    cached = _function(RESIDUAL_SHADOW, "_derive_cached")

    assert accumulate.count("_derive_cached(") == 2
    assert "ResidualProjectionScript.derive_observables(" in cached
    assert "ResidualProjectionScript.derive(" not in cached
    assert "enum DeriveCache" in RESIDUAL_SHADOW
    for field in (
        "UPPER_MASS_KG",
        "UPPER_ENERGY_KJ",
        "LOWER_MASS_KG",
        "LOWER_ENERGY_KJ",
        "FLOOR_AREA_M2",
        "ROOM_HEIGHT_M",
        "AMBIENT_C",
        "RESULT",
    ):
        assert f"DeriveCache.{field}" in cached
    assert "cached.get(" not in cached
    assert "is_equal_approx" not in cached
    assert "snapped" not in cached


def test_residual_shadow_updates_room_and_cause_without_pair_allocations():
    accumulate = _function(RESIDUAL_SHADOW, "accumulate_step")
    helper = _function(RESIDUAL_SHADOW, "_accumulate_signed_gross_max")

    assert "var blocks: Array = [room_block, cause_block]" not in accumulate
    assert "first: Array, second: Array" in helper
    assert "for raw in blocks" not in helper


def test_residual_shadow_caches_constant_room_geometry_for_the_run():
    geometry = _function(ENGINE, "_phase3_residual_projection_shadow_geometry")
    reset = _function(ENGINE, "reset_simulation")

    assert "_phase3_residual_projection_shadow_geometry_cache" in ENGINE
    assert "if not _phase3_residual_projection_shadow_geometry_cache.is_empty()" in geometry
    assert "return _phase3_residual_projection_shadow_geometry_cache" in geometry
    assert "_phase3_residual_projection_shadow_geometry_cache.clear()" in reset


def test_residual_shadow_materializes_compact_global_totals_only_on_export():
    accumulate = _function(RESIDUAL_SHADOW, "accumulate_event")
    summary = _function(RESIDUAL_SHADOW, "summary")

    assert "enum TotalMetric" in RESIDUAL_SHADOW
    assert "var _totals: Array" in RESIDUAL_SHADOW
    assert "_totals_dictionary()" in summary
    assert '_bump("' not in accumulate
    assert '_bump_int("' not in accumulate


def test_public_residual_projection_builds_from_the_same_compact_observables():
    public_derive = _function(RESIDUAL_PRIMITIVE, "derive")
    compact_derive = _function(RESIDUAL_PRIMITIVE, "derive_observables")

    assert "derive_observables(" in public_derive
    assert "-> Array:" in compact_derive
    assert "_validate_inputs(" in compact_derive
    assert '"pressure_abs_pa"' in public_derive
    assert '"interface_height_m"' in public_derive


def test_o2_combination_avoids_pre_serialization_deep_copy_only_internally():
    public_samples = _function(O2_LEDGER, "samples")
    internal_samples = _function(O2_LEDGER, "peek_samples")
    combined = _function(ENGINE, "_phase3_o2_attribution_combined")

    assert "duplicate(true)" in public_samples
    assert "return _samples" in internal_samples
    assert "duplicate" not in internal_samples
    assert "samples.append_array(ledger.peek_samples())" in combined
    assert "ledger.samples()" not in combined


def test_direct_godot_tests_share_the_monitored_no_window_launcher():
    assert GODOT_TEST_LAUNCHER.is_file()
    launcher = GODOT_TEST_LAUNCHER.read_text(encoding="utf-8")
    assert "mutation_audit._run_monitored(" in launcher
    assert "mutation_audit._godot_processes()" in launcher

    for path in DIRECT_GODOT_TESTS:
        source = path.read_text(encoding="utf-8")
        assert "from tests.godot_runtime_launcher import run_godot" in source
        assert "subprocess.run(" not in source


def test_zone_stage_diagnostics_use_compact_internal_state_and_deltas():
    snapshot = _function(ENGINE, "_phase3_zone_diag_snapshot")
    stage = _function(ENGINE, "_phase3_zone_diag_record_stage")
    export = _function(ENGINE, "_phase3_zone_diag_export")

    assert "enum ZoneDiagState" in ENGINE
    assert "ZONE_DIAG_STAGES" in ENGINE
    assert "_phase3_zone_diag_room_state(room)" in snapshot
    assert "_phase3_zone_diag_snapshot()" not in stage
    assert "stage_offset + ZoneDiagQuantity.MASS_KG" in stage
    assert "stage_offset + ZoneDiagQuantity.ENERGY_KJ" in stage
    assert 'stage_name + "_mass_delta_kg_step"' in export
    assert 'stage_name + "_energy_delta_kj_step"' in export


def test_zone_and_runtime_ownership_share_room_captures_in_step():
    begin = _function(ENGINE, "_phase3_zone_runtime_begin_step_shared")
    stage = _function(ENGINE, "_phase3_zone_runtime_record_stage_shared")
    step = _function(ENGINE, "step")

    assert begin.count("for room_id in building.get_rooms().keys():") == 1
    assert stage.count("for room_id in building.get_rooms().keys():") == 1
    assert "phase3_zone_diagnostics_enabled" in begin
    assert "phase3_runtime_ownership_ledger_enabled" in begin
    assert "phase3_zone_diagnostics_enabled" in stage
    assert "phase3_runtime_ownership_ledger_enabled" in stage
    assert step.count("_phase3_zone_runtime_begin_step_shared()") == 1
    assert "_phase3_zone_diag_begin_step()" not in step
    assert "_phase3_runtime_ownership_begin_step()" not in step
    assert '_phase3_zone_runtime_record_stage_shared("", "pool_fire")' in step
    for stage_name in (
        "oxygen_exchange",
        "combustion",
        "thermal",
        "suppression",
        "gas_exchange",
        "hvac",
        "other",
        "reconcile",
    ):
        assert (
            f'_phase3_zone_runtime_record_stage_shared("{stage_name}", '
            f'"{stage_name}")' in step
        )
    assert (
        '_phase3_zone_runtime_record_stage_shared("projection_clamp", '
        '"clamp_rooms")' in step
    )
    assert "_phase3_zone_diag_record_stage(" not in step
    assert "_phase3_runtime_ownership_record_stage(" not in step


def test_causal_ledger_consumes_compact_zone_attribution_without_exporting_it():
    accumulate = _function(
        ENGINE, "_phase3_projection_diagnostics_accumulate_shared"
    )

    assert "finish_step_compact(" in accumulate
    assert "_phase3_zone_diag_export()" not in accumulate
    assert "func accumulate_step_compact(" in CAUSAL_LEDGER
    assert "func _accumulate_residuals_compact(" in CAUSAL_LEDGER


def test_causal_ledger_accumulates_room_and_cause_metrics_in_compact_blocks():
    room = _function(CAUSAL_LEDGER, "_room")
    cause = _function(CAUSAL_LEDGER, "_cause")
    summary = _function(CAUSAL_LEDGER, "summary")

    assert "enum CausalRoomMetric" in CAUSAL_LEDGER
    assert "enum CausalCauseMetric" in CAUSAL_LEDGER
    assert "-> Array:" in room
    assert "-> Array:" in cause
    assert "_room_dictionary(" in summary
    assert "_cause_dictionary(" in summary


def test_o2_attribution_accumulates_compact_entries_and_materializes_on_export():
    entry = _function(O2_LEDGER, "_entry")
    record = _function(O2_LEDGER, "record")
    summary = _function(O2_LEDGER, "summary")

    assert "enum EntryField" in O2_LEDGER
    assert "-> Array:" in entry
    assert "EntryField.APPLICATIONS" in record
    assert "_totals_dictionary()" in summary
    assert "_entry_dictionary(" in _function(O2_LEDGER, "_totals_dictionary")


def test_o2_entry_lookup_reuses_only_an_exact_owner_zone_pair():
    entry = _function(O2_LEDGER, "_entry")
    clear = _function(O2_LEDGER, "clear")

    assert "owner == _last_owner and zone == _last_zone" in entry
    assert "entry = _last_entry" in entry
    assert "String(entry[EntryField.REASON_CODE]) != reason" in entry
    assert "_last_entry.clear()" in clear


def test_zone_transition_uses_fixed_predicate_counter_blocks():
    transition = (ROOT / "sim/core/Phase3ZoneTransitionLedger.gd").read_text(
        encoding="utf-8"
    )
    counter = _function(transition, "_counter_block")
    bucket = _function(transition, "_bucket")
    summary = _function(transition, "summary")

    assert "enum CounterField" in transition
    assert "-> Array:" in counter
    assert "-> Array:" in bucket
    assert "_totals_dictionary()" in summary
    assert "_rooms_dictionary()" in summary


def test_engine_dispatches_projection_trace_once_to_all_passive_consumers():
    shared = _function(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    step = _function(ENGINE, "step")

    assert shared.count("zone_fire_solver.peek_projection_trace_records()") == 1
    assert shared.count("for raw in trace_events:") == 1
    assert "_phase3_projection_causal_ledger.accumulate_event(event)" in shared
    assert "_phase3_residual_projection_shadow.accumulate_event(" in shared
    assert "_phase3_zone_transition_ledger.observe_call(event)" in shared
    assert step.count("_phase3_projection_diagnostics_accumulate_shared()") == 1
    assert "_phase3_projection_causal_accumulate()" not in step
    assert "_phase3_residual_projection_shadow_accumulate()" not in step
    assert "_phase3_zone_transition_observe()" not in step
    assert "func accumulate_event(event: Array) -> void:" in CAUSAL_LEDGER
    assert "func accumulate_event(" in RESIDUAL_SHADOW
    assert "func observe_call(event: Array) -> void:" in TRANSITION_LEDGER
