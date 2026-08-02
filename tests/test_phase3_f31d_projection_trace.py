"""F3.1d structural checks for passive per-call projection tracing."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_projection_trace_is_default_off():
    assert "var projection_diagnostics_enabled: bool = false" in SOLVER


def test_trace_resets_once_per_diagnostic_step():
    begin = _function(SOLVER, "begin_projection_diagnostics_step")
    assert "_projection_trace_events.clear()" in begin
    assert "_projection_call_index = 0" in begin
    engine_begin = _function(ENGINE, "_phase3_zone_diag_begin_step")
    assert "if not phase3_zone_diagnostics_enabled:" in engine_begin
    assert "zone_fire_solver.begin_projection_diagnostics_step()" in engine_begin


def test_trace_read_is_defensive_copy():
    getter = _function(SOLVER, "get_projection_trace_events")
    assert "duplicate(true)" in getter


def test_projection_captures_all_state_boundaries():
    project = _function(SOLVER, "project_room_state")
    for key in ('"pre"', '"ensured"', '"pre_geometry"', '"post"'):
        assert key in project
    assert project.index("pre_state") < project.index("ensure_room_state")
    assert project.index("ensured_state") < project.index("projection_energy_before_kj")


def test_projection_trace_has_eos_targets_and_caps():
    project = _function(SOLVER, "project_room_state")
    for key in (
        '"upper_density_kg_m3"',
        '"lower_density_kg_m3"',
        '"max_upper_mass_kg"',
        '"target_lower_mass_kg"',
        '"upper_cap_mass_delta_kg"',
        '"upper_cap_energy_delta_kj"',
    ):
        assert key in project


def test_projection_trace_separates_delta_families():
    project = _function(SOLVER, "project_room_state")
    for key in (
        '"ensure_mass_delta_kg"',
        '"ensure_energy_delta_kj"',
        '"temperature_projection_energy_delta_kj"',
        '"lower_projection_mass_delta_kg"',
        '"lower_projection_energy_delta_kj"',
        '"total_mass_delta_kg"',
        '"total_energy_delta_kj"',
    ):
        assert key in project


def test_projection_trace_is_gated_before_state_capture():
    project = _function(SOLVER, "project_room_state")
    assert "var trace_enabled: bool = projection_diagnostics_enabled" in project
    assert "_projection_state(room) if trace_enabled else {}" in project
    assert "if trace_enabled:" in project


def test_engine_wires_trace_to_effective_passive_diagnostics_flags():
    sync = _function(ENGINE, "_sync_auxiliary_services")
    assert (
        "zone_fire_solver.projection_diagnostics_enabled = "
        "_phase3_projection_diagnostics_active()"
    ) in sync
    active = _function(ENGINE, "_phase3_projection_diagnostics_active")
    assert (
        "phase3_zone_diagnostics_enabled or "
        "phase3_runtime_ownership_ledger_enabled"
    ) in active
    assert "phase3_projection_trace_enabled" not in ENGINE


def test_engine_exposes_trace_only_with_effective_diagnostics():
    get_state = _function(ENGINE, "get_state")
    assert "if _phase3_projection_diagnostics_active():" in get_state
    assert 'state["phase3_projection_trace"]' in get_state


def test_all_runtime_projection_call_sites_have_explicit_causes():
    for cause in (
        "thermal_energy_projection",
        "thermal_post_combustion_sync",
        "thermal_post_losses_sync",
        "gas_exchange_sync",
        "reconcile_layer_sync",
        "final_clamp_active",
        "final_clamp_quiescent",
        "stairwell_temperature_cap",
    ):
        assert f'"{cause}"' in THERMAL + ENGINE
    for line in (THERMAL + "\n" + ENGINE).splitlines():
        if "sync_room_upper_layer(" not in line or line.lstrip().startswith("func "):
            continue
        assert ", dt," in line


def test_sync_callable_keeps_backward_compatible_default_cause():
    sync = _function(THERMAL, "sync_room_upper_layer")
    assert 'projection_cause: String = "thermal_layer_sync"' in sync


def test_runner_jsonl_is_explicit_opt_in():
    assert 'scenario.get("phase3_projection_trace_enabled", false)' in RUNNER
    assert '_out_dir.path_join("projection_trace.jsonl")' in RUNNER
    append = _function(RUNNER, "_append_projection_trace")
    assert "if not _projection_trace_enabled" in append
    assert 'state.get("phase3_projection_trace", [])' in append
    assert 'event["sim_time_s"] = sim_time_s' in append
    assert "store_line(JSON.stringify(event))" in append


def test_runner_appends_once_after_each_engine_step():
    loop = _function(RUNNER, "_run_loop")
    assert loop.count("_append_projection_trace(state, sim_time_s)") == 1
    assert loop.index("engine.step(") < loop.index("_append_projection_trace")


def test_runner_manifest_adds_trace_path_only_when_enabled():
    manifest = _function(RUNNER, "_write_manifest")
    assert "if _projection_trace_enabled:" in manifest
    assert 'manifest["projection_trace_path"] = _projection_trace_path' in manifest


def test_legacy_csv_schema_has_no_projection_trace_columns():
    assert "phase3_projection_trace" not in LOG
    assert "projection_trace.jsonl" not in LOG


def test_patch_adds_no_projection_authority_flag():
    combined = SOLVER + THERMAL + ENGINE + RUNNER
    assert "projection_authority" not in combined
    assert "phase3_f31d_authority" not in combined
