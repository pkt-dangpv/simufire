from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33c1_enthalpy_residence_ledger.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_enthalpy_residence_diagnostics_enabled: bool = false" in ENGINE
    assert '"phase3_enthalpy_residence_diagnostics_enabled"' in STATE
    assert "var phase3_enthalpy_residence_diagnostics_enabled: bool = false" in LOG


def test_ledger_is_configured_only_with_the_full_f33b_stack():
    body = _function(ENGINE, "_sync_auxiliary_services")
    for flag in (
        "phase3_canonical_zone_shadow_enabled",
        "phase3_canonical_persistence_shadow_enabled",
        "phase3_canonical_combustion_shadow_enabled",
        "phase3_canonical_interior_opening_shadow_enabled",
        "phase3_canonical_interior_pressure_shadow_enabled",
        "phase3_enthalpy_residence_diagnostics_enabled",
    ):
        assert flag in body
    assert "configure_enthalpy_residence_diagnostics" in body


def test_initial_state_and_cumulative_ledger_are_persistent_but_resettable():
    begin = _function(SYSTEM, "begin_step")
    reset = _function(SYSTEM, "reset")
    assert "_enthalpy_residence_initial_by_room" in begin
    assert "_new_enthalpy_residence_record" in begin
    assert "_enthalpy_residence_initial_by_room.clear()" in reset
    assert "_enthalpy_residence_cumulative_by_room.clear()" in reset


def test_atomic_routes_are_recorded_after_bundle_acceptance_is_known():
    # H3.2-M extracted the fraction into `_evaluate_atomic_bundle_acceptance`.
    # The invariant is unchanged: acceptance must be known before any route is
    # recorded, and recording must precede application.
    body = _function(SYSTEM, "_apply_atomic_bundle")
    accepted = body.index('float(evaluation["accepted_fraction"])')
    record = body.index("_record_enthalpy_residence_route")
    apply_route = body.index("_apply_atomic_route")
    assert accepted < record < apply_route


def test_legacy_requests_and_zone_collapse_are_not_hidden():
    request = _function(SYSTEM, "_apply_request")
    collapse = _function(SYSTEM, "_collapse_degenerate_zones")
    assert "_record_enthalpy_residence_route" in request
    assert "_record_enthalpy_zone_collapse" in collapse
    assert '"zone_collapse"' in SYSTEM


def test_result_exposes_zone_room_and_building_closure():
    for field in (
        "phase3_shadow_enthalpy_expected_upper_kj",
        "phase3_shadow_enthalpy_expected_lower_kj",
        "phase3_shadow_enthalpy_upper_residual_kj",
        "phase3_shadow_enthalpy_lower_residual_kj",
        "phase3_shadow_enthalpy_room_residual_kj",
        "phase3_shadow_enthalpy_building_residual_kj",
    ):
        assert field in SYSTEM


def test_cause_families_cover_f33b_energy_owners():
    classifier = _function(SYSTEM, "_enthalpy_cause_family")
    for cause in (
        "canonical_combustion_convective_heat",
        "canonical_combustion_plume",
        "thermal_upper_to_lower",
        "canonical_upper_to_wall",
        "canonical_upper_to_ambient",
        "canonical_exterior_pressure",
        "canonical_exterior_counterflow_upper_out",
        "canonical_interior_opening",
        "canonical_interior_pressure",
        "delayed_parcel_carve",
    ):
        assert cause in classifier


def test_csv_columns_are_separately_opt_in():
    assert "if phase3_enthalpy_residence_diagnostics_enabled:" in LOG
    assert LOG.count("_phase3_enthalpy_residence_fields()") == 3
    fields = _function(LOG, "_phase3_enthalpy_residence_fields")
    assert "phase3_shadow_enthalpy_room_residual_kj" in fields
    assert "phase3_shadow_enthalpy_building_residual_kj" in fields


def test_runner_flag_implies_f33b_and_prior_stack():
    block = RUNNER.split("if args.phase3_enthalpy_residence_diagnostics:", 1)[1]
    for flag in (
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
        "--phase3-canonical-plume-shadow",
        "--phase3-canonical-interzone-heat-shadow",
        "--phase3-canonical-wall-ambient-shadow",
        "--phase3-canonical-exterior-counterflow-shadow",
        "--phase3-canonical-post-opening-coupling-shadow",
        "--phase3-canonical-interior-opening-shadow",
        "--phase3-canonical-interior-pressure-shadow",
        "--phase3-enthalpy-residence-diagnostics",
    ):
        assert flag in block
    assert "engine.phase3_enthalpy_residence_diagnostics_enabled = true" in HEADLESS


def test_runtime_fixture_covers_default_off_and_exact_closure():
    assert "PHASE3_F33C1_ENTHALPY_RESIDENCE_LEDGER_PASS" in FIXTURE
    assert "_test_disabled_has_no_ledger_fields" in FIXTURE
    assert "_test_exact_route_ledger_closure" in FIXTURE
    assert "phase3_shadow_enthalpy_building_residual_kj" in FIXTURE
