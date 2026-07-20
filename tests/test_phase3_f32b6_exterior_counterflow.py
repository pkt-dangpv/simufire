from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_canonical_exterior_counterflow_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_exterior_counterflow_shadow_enabled"' in STATE


def test_preview_is_pure_canonical_input():
    marker = "func preview_canonical_exterior_counterflow("
    body = SYSTEM.split(marker, 1)[1].split("\nfunc ", 1)[0]
    assert "RoomModel" not in body
    assert "room." not in body
    for key in ["upper_gas_kg", "lower_gas_kg", "upper_volume_m3", "lower_volume_m3"]:
        assert f'canonical_input.get("{key}"' in body


def test_hydrostatic_integration_solves_zero_net_exchange():
    assert "_integrate_canonical_exterior_opening" in SYSTEM
    assert '"net_kg_s": out_kg_s - in_kg_s' in SYSTEM
    assert "for _iteration in range(72)" in SYSTEM
    assert "minf(gross_upper_out_kg_s, gross_lower_in_kg_s)" in SYSTEM


def test_counterflow_and_pressure_have_distinct_bundle_owners():
    assert '"canonical_exterior_counterflow"' in SYSTEM
    assert '"canonical_exterior_pressure"' in SYSTEM
    assert '"f32b6_exterior_counterflow:' in SYSTEM
    assert '"f32a_exterior:' in SYSTEM


def test_atomic_routes_are_upper_out_and_lower_in():
    block = SYSTEM.split("func queue_canonical_exterior_counterflow_requests(", 1)[1].split(
        "\nfunc ", 1
    )[0]
    assert '"canonical_exterior_counterflow_upper_out"' in block
    assert '"canonical_exterior_counterflow_lower_in"' in block
    assert "room_id,\n\t\t\t\tEXTERIOR_ID" in block
    assert "EXTERIOR_ID,\n\t\t\t\troom_id" in block


def test_csv_schema_is_conditioned_on_b6_flag():
    assert "var phase3_canonical_exterior_counterflow_shadow_enabled: bool = false" in LOG
    assert "if phase3_canonical_exterior_counterflow_shadow_enabled:" in LOG
    assert "phase3_shadow_counterflow_neutral_plane_m" in LOG
    assert "phase3_shadow_counterflow_pressure_relief_kg_step" in LOG


def test_runner_flag_implies_complete_parent_stack():
    block = RUNNER.split("if args.phase3_canonical_exterior_counterflow_shadow:", 1)[1]
    for flag in [
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
        "--phase3-canonical-plume-shadow",
        "--phase3-canonical-interzone-heat-shadow",
        "--phase3-canonical-wall-ambient-shadow",
        "--phase3-canonical-exterior-counterflow-shadow",
    ]:
        assert flag in block
    assert "engine.phase3_canonical_exterior_counterflow_shadow_enabled = true" in HEADLESS


def test_runtime_fixture_covers_required_controls():
    fixture = (ROOT / "tests/fixtures/phase3_f32b6_exterior_counterflow.gd").read_text(
        encoding="utf-8"
    )
    assert "PHASE3_F32B6_EXTERIOR_COUNTERFLOW_PASS" in fixture
    assert "_test_equal_ambient_is_quiet" in fixture
    assert "_test_hot_upper_produces_bidirectional_exchange" in fixture
    assert "_test_inventory_cap_is_atomic" in fixture
    assert "_test_pressure_relief_and_counterflow_have_separate_owners" in fixture
    assert "_test_duplicate_bundle_is_reported" in fixture
