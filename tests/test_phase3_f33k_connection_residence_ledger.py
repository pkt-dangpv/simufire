from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33k_connection_residence_ledger.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_summary_only():
    assert (
        "@export var phase3_connection_residence_diagnostics_enabled: bool = false"
        in ENGINE
    )
    summary = _function(ENGINE, "build_technical_summary")
    assert '"phase3_connection_residence"' in summary
    assert "phase3_connection_residence" not in LOG


def test_full_residence_stack_is_required():
    sync = _function(ENGINE, "_sync_auxiliary_services")
    assert "phase3_enthalpy_residence_diagnostics_active" in sync
    assert "phase3_mass_residence_diagnostics_active" in sync
    assert "configure_connection_residence_diagnostics" in sync


def test_opening_and_pressure_routes_receive_connection_identity():
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert queue.count("_tag_connection_route(") == 2
    assert '"opening:%d"' in _function(SYSTEM, "_tag_connection_route")


def test_recording_occurs_after_acceptance_before_mutation():
    # H3.2-M extracted the fraction into `_evaluate_atomic_bundle_acceptance`
    # so the coupled shadow bundle can reuse it. The invariant is unchanged:
    # acceptance is known first, then recorded, then applied.
    apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
    accepted = apply_bundle.index('float(evaluation["accepted_fraction"])')
    record = apply_bundle.index("_record_connection_residence_route")
    mutate = apply_bundle.index("_apply_atomic_route")
    assert accepted < record < mutate


def test_connection_result_reports_mass_energy_temperature_and_destination():
    result = _function(SYSTEM, "get_connection_residence_results")
    for field in (
        "accepted_mass_kg",
        "accepted_enthalpy_kj",
        "mass_weighted_source_temp_c",
        "destination_upper_fraction",
        "source_upper_mass_kg",
        "source_lower_mass_kg",
        "destination_upper_mass_kg",
        "destination_lower_mass_kg",
    ):
        assert field in SYSTEM or field in result


def test_reset_clears_cumulative_records():
    assert "_connection_residence_cumulative.clear()" in _function(SYSTEM, "reset")


def test_runner_flag_implies_both_residence_ledgers():
    block = RUNNER.split("if args.phase3_connection_residence_diagnostics:", 1)[1]
    for flag in (
        "--phase3-enthalpy-residence-diagnostics",
        "--phase3-mass-residence-diagnostics",
        "--phase3-connection-residence-diagnostics",
    ):
        assert flag in block
    assert "engine.phase3_connection_residence_diagnostics_enabled = true" in HEADLESS


def test_temporary_buoyancy_runtime_selector_was_removed():
    marker = "phase3_f33k_buoyancy_runtime_experiment"
    for source in (ENGINE, RUNNER, HEADLESS):
        assert marker not in source


def test_fixture_covers_off_exact_totals_temperature_fraction_and_reset():
    assert "PHASE3_F33K_CONNECTION_RESIDENCE_LEDGER_PASS" in FIXTURE
    for marker in (
        "default OFF has no connection records",
        "opening mass",
        "opening enthalpy",
        "opening source temperature",
        "opening lower destination",
        "pressure upper destination",
        "reset clears cumulative connection records",
    ):
        assert marker in FIXTURE
