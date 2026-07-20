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
    assert "@export var phase3_canonical_wall_ambient_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_wall_ambient_shadow_enabled"' in STATE


def test_preview_does_not_read_legacy_room_state():
    marker = "func preview_phase3_canonical_wall_ambient_flux("
    body = THERMAL.split(marker, 1)[1].split("\nfunc ", 1)[0]
    assert "room." not in body
    for key in ["upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj"]:
        assert f'canonical_input.get("{key}"' in body


def test_wall_state_is_separate_and_persistent():
    assert "var _canonical_wall_state_by_room: Dictionary = {}" in SYSTEM
    assert "func get_canonical_wall_ambient_input(" in SYSTEM
    assert '"wall_energy_kj"' in SYSTEM
    assert "_canonical_wall_state_by_room[room_key]" in SYSTEM


def test_finite_reservoir_equilibrium_is_explicit():
    body = THERMAL.split("func preview_phase3_canonical_wall_ambient_flux(", 1)[1]
    assert "equilibrium_temp_c" in body
    assert "upper_capacity_kj_k" in body
    assert "lower_capacity_kj_k" in body
    assert "wall_capacity_kj_k" in body


def test_atomic_bundle_owns_all_gas_facing_routes():
    assert "func queue_canonical_wall_ambient_transfer(" in SYSTEM
    assert '"kind": "canonical_wall_ambient"' in SYSTEM
    for cause in [
        "canonical_upper_to_wall",
        "canonical_wall_to_upper",
        "canonical_lower_to_wall",
        "canonical_wall_to_lower",
        "canonical_upper_to_ambient",
        "canonical_lower_to_ambient",
    ]:
        assert cause in SYSTEM


def test_engine_suppresses_only_replaced_legacy_shadow_owners():
    block = ENGINE.split("var canonical_wall_causes", 1)[1].split(
        "for flux in thermal_system.drain_phase3_shadow_flux_results()", 1
    )[0]
    for cause in [
        "thermal_upper_radiative_loss",
        "thermal_upper_to_ambient",
        "thermal_wall_absorption",
        "thermal_wall_emission",
        "thermal_lower_decay",
        "thermal_lower_fresh_air_cooling",
    ]:
        assert cause in block


def test_wall_and_total_boundary_residuals_are_exported():
    assert 'record["gas_wall_energy_residual_kj"]' in SYSTEM
    assert 'record["total_boundary_energy_residual_kj"]' in SYSTEM
    assert "phase3_shadow_wall_boundary_residual_kj" in LOG


def test_csv_schema_is_conditioned_on_new_flag():
    assert "var phase3_canonical_wall_ambient_shadow_enabled: bool = false" in LOG
    assert "if phase3_canonical_wall_ambient_shadow_enabled:" in LOG
    assert "phase3_shadow_wall_energy_post_kj" in LOG


def test_runner_flag_implies_complete_b5a_parent_stack():
    block = RUNNER.split("if args.phase3_canonical_wall_ambient_shadow:", 1)[1]
    for flag in [
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
        "--phase3-canonical-plume-shadow",
        "--phase3-canonical-interzone-heat-shadow",
        "--phase3-canonical-wall-ambient-shadow",
    ]:
        assert flag in block
    assert "engine.phase3_canonical_wall_ambient_shadow_enabled = true" in HEADLESS


def test_no_mass_o2_or_species_routes_are_created():
    block = SYSTEM.split("func queue_canonical_wall_ambient_transfer(", 1)[1].split("\nfunc ", 1)[0]
    assert "0.0, upper_wall_signed_kj, 0.0, {}" in block
    assert "0.0, upper_ambient_kj, 0.0, {}" in block


def test_direct_runtime_fixture_exists():
    source = (ROOT / "tests/fixtures/phase3_f32b5b_wall_ambient.gd").read_text(
        encoding="utf-8"
    )
    assert "PHASE3_F32B5B_WALL_AMBIENT_PASS" in source
    assert "_test_many_steps_conserve_gas_wall_energy" in source
    assert "_test_prior_loss_limits_atomic_acceptance" in source
