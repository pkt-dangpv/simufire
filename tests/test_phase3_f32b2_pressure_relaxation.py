from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


FIELDS = [
    "phase3_shadow_exterior_relaxation_enabled_flag",
    "phase3_shadow_exterior_raw_requested_gas_kg",
    "phase3_shadow_exterior_raw_requested_energy_kj",
    "phase3_shadow_exterior_pressure_equilibrium_fraction",
    "phase3_shadow_exterior_pressure_full_delta_pa",
    "phase3_shadow_exterior_pressure_limited_delta_pa",
    "phase3_shadow_exterior_pressure_predicted_post_pa",
    "phase3_shadow_exterior_pressure_crossing_prevented_flag",
    "phase3_shadow_exterior_degenerate_lower_reseed_flag",
    "phase3_shadow_exterior_degenerate_lower_reseed_mass_kg",
    "phase3_shadow_exterior_lower_reseed_count_total",
    "phase3_shadow_exterior_lower_reseed_mass_kg_total",
    "phase3_shadow_exterior_lower_reseed_first_step_index",
]


def test_flag_is_default_off_and_has_no_authority_pair():
    assert "@export var phase3_canonical_pressure_relaxation_shadow_enabled: bool = false" in ENGINE
    assert "phase3_canonical_pressure_relaxation_authority" not in ENGINE
    assert '"phase3_canonical_pressure_relaxation_shadow_enabled"' in STATE


def test_equilibrium_limit_uses_eos_mass_and_energy_terms():
    assert "func compute_exterior_pressure_relaxation(" in SYSTEM
    assert "requested_gas_kg * reference_temp_k" in SYSTEM
    assert "requested_energy_kj / AIR_CP_KJ_KG_K" in SYSTEM
    assert "-pressure_gauge_pa / full_delta_pa" in SYSTEM


def test_limit_scales_every_atomic_route_quantity():
    assert "func _scaled_atomic_routes(" in SYSTEM
    for quantity in ["gas_mass_kg", "sensible_enthalpy_kj", "o2_kg", "species_kg"]:
        assert quantity in SYSTEM


def test_degenerate_inflow_reseeds_lower_only_when_enabled():
    assert "pressure_relaxation_enabled and not outflow" in SYSTEM
    assert 'area_by_zone[ZONE_UPPER] = 0.0' in SYSTEM
    assert 'area_by_zone[ZONE_LOWER] = total_exterior_area_m2' in SYSTEM
    assert 'record["degenerate_lower_reseed_flag"] = 1.0' in SYSTEM


def test_engine_passes_flag_into_exterior_contract():
    assert "phase3_canonical_pressure_relaxation_shadow_enabled" in ENGINE
    assert "Phase3ZoneMassSystemScript.EXTERIOR_DISCHARGE_COEFF" in ENGINE


def test_csv_fields_are_separately_gated_and_unique():
    assert "if phase3_canonical_pressure_relaxation_shadow_enabled:" in LOG
    for field in FIELDS:
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_complete_parent_stack():
    block = RUNNER.split("if args.phase3_canonical_pressure_relaxation_shadow:", 1)[1]
    for flag in [
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
    ]:
        assert flag in block
    assert "engine.phase3_canonical_pressure_relaxation_shadow_enabled = true" in HEADLESS


def test_direct_runtime_fixture_exists():
    fixture = ROOT / "tests/fixtures/phase3_f32b2_pressure_relaxation.gd"
    source = fixture.read_text(encoding="utf-8")
    assert "PHASE3_F32B2_PRESSURE_RELAXATION_PASS" in source
    assert "_test_exact_equilibrium_fraction" in source
    assert "_test_negative_pressure_reseeds_lower_without_crossing" in source
    assert "_test_default_off_preserves_explicit_crossing" in source
