from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_post_opening_coupling_active_flag",
    "phase3_shadow_post_opening_source_switched_to_lower_flag",
    "phase3_shadow_post_opening_counterflow_exchange_kg_step",
    "phase3_shadow_post_opening_counterflow_incoming_o2_kg_step",
    "phase3_shadow_post_opening_source_o2_available_kg",
    "phase3_shadow_post_opening_full_hrr_o2_demand_kg_step",
    "phase3_shadow_post_opening_o2_supply_margin_kg_step",
    "phase3_shadow_post_opening_combustion_air_min_plume_mass_kg_step",
    "phase3_shadow_post_opening_plume_height_term_mass_kg_step",
    "phase3_shadow_post_opening_plume_source_term_mass_kg_step",
    "phase3_shadow_post_opening_plume_o2_to_upper_kg_step",
    "phase3_shadow_post_opening_lower_o2_closure_residual_kg",
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_canonical_post_opening_coupling_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_post_opening_coupling_shadow_enabled"' in STATE
    assert "phase3_canonical_post_opening_coupling_authority" not in ENGINE


def test_counterflow_context_is_pre_step_and_read_only():
    getter = _function(SYSTEM, "get_canonical_exterior_counterflow_request")
    assert 'record.get("requested_exchange_kg"' in getter
    assert 'record.get("requested_incoming_o2_kg"' in getter
    assert "accepted_exchange_kg" not in getter


def test_lower_source_requires_real_counterflow_and_inventory():
    body = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    assert "post_opening_coupling_enabled" in body
    assert "counterflow_exchange_kg > 0.000000001" in body
    assert "lower_gas_kg > 0.000001" in body
    assert "or post_opening_lower_source" in body


def test_o2_is_still_debited_by_existing_atomic_bundle():
    bundle = _function(SYSTEM, "finalize_canonical_combustion_bundle")
    assert 'o2_source_zone: String = String(record.get("o2_source_zone"' in bundle
    assert '"canonical_combustion_o2_sink"' in bundle
    assert "accepted_o2_kg" in bundle
    assert "combustion_air_min_plume_mass_kg" in bundle
    assert "entrained_plume_o2_kg - accepted_o2_kg" in bundle


def test_heskestad_source_term_is_post_opening_opt_in_only():
    preview = _function(
        (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8"),
        "preview_phase3_canonical_plume_flux",
    )
    assert "include_heskestad_source_term: bool = false" in preview
    assert "0.0018 * qc_kw * dt" in preview
    collector = _function(ENGINE, "_phase3_shadow_collect_thermal_requests")
    assert "include_heskestad_source_term" in collector
    assert 'counterflow_request.get("requested_exchange_kg"' in collector


def test_csv_fields_are_opt_in_and_unique():
    assert "var phase3_canonical_post_opening_coupling_shadow_enabled: bool = false" in LOG
    assert "if phase3_canonical_post_opening_coupling_shadow_enabled:" in LOG
    for field in FIELDS:
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_complete_b6_stack():
    block = RUNNER.split("if args.phase3_canonical_post_opening_coupling_shadow:", 1)[1]
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
    ):
        assert flag in block
    assert "engine.phase3_canonical_post_opening_coupling_shadow_enabled = true" in HEADLESS


def test_runtime_fixture_covers_source_switch_and_zero_o2_guard():
    source = (ROOT / "tests/fixtures/phase3_f32b7_post_opening_coupling.gd").read_text(
        encoding="utf-8"
    )
    assert "PHASE3_F32B7_POST_OPENING_COUPLING_PASS" in source
    assert "_test_closed_state_keeps_upper_source" in source
    assert "_test_counterflow_selects_lower_source" in source
    assert "_test_counterflow_without_lower_o2_cannot_burn" in source
    assert "_test_lower_o2_debit_is_atomic" in source
    assert "_test_heskestad_source_term_is_opt_in" in source
