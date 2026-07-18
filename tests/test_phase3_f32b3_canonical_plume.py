from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_canonical_plume_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_plume_shadow_enabled"' in STATE


def test_canonical_plume_uses_persistent_thermodynamic_input():
    assert "func get_canonical_thermodynamic_input(" in SYSTEM
    assert "derive_canonical_thermodynamic_state(" in SYSTEM
    assert "preview_phase3_canonical_plume_flux(" in THERMAL
    assert "canonical_input.get(\"interface_m\"" in THERMAL
    assert "canonical_input.get(\"lower_gas_kg\"" in THERMAL
    assert "canonical_input.get(\"lower_energy_kj\"" in THERMAL


def test_engine_replaces_only_plume_candidate_when_enabled():
    assert "if phase3_canonical_plume_shadow_enabled and building != null:" in ENGINE
    assert "get_canonical_thermodynamic_input(" in ENGINE
    assert "preview_phase3_canonical_plume_flux(" in ENGINE
    assert 'if cause == "plume_entrainment":' in ENGINE
    assert "for room_id in phase3_zone_mass_system.get_canonical_combustion_room_ids():" in ENGINE


def test_plume_transfer_is_capped_by_canonical_lower_inventory():
    assert "requested_mass_kg: float = minf(" in THERMAL
    assert "lower_mass_kg" in THERMAL
    assert "lower_fraction: float = requested_mass_kg" in THERMAL


def test_b3_does_not_add_csv_columns_or_authority_path():
    assert "phase3_canonical_plume_shadow_enabled" not in LOG
    assert "phase3_canonical_plume_authority" not in ENGINE


def test_runner_flag_implies_complete_b2_parent_stack():
    block = RUNNER.split("if args.phase3_canonical_plume_shadow:", 1)[1]
    for flag in [
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
        "--phase3-canonical-plume-shadow",
    ]:
        assert flag in block
    assert "engine.phase3_canonical_plume_shadow_enabled = true" in HEADLESS


def test_direct_runtime_fixture_exists():
    fixture = ROOT / "tests/fixtures/phase3_f32b3_canonical_plume.gd"
    source = fixture.read_text(encoding="utf-8")
    assert "PHASE3_F32B3_CANONICAL_PLUME_PASS" in source
    assert "_test_canonical_interface_controls_plume" in source
    assert "_test_transfer_preserves_lower_specific_enthalpy" in source
    assert "_test_empty_lower_zone_requests_nothing" in source
