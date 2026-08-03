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
    assert "@export var phase3_canonical_interzone_heat_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_interzone_heat_shadow_enabled"' in STATE


def test_preview_uses_only_canonical_input():
    marker = "func preview_phase3_canonical_interzone_heat_flux("
    body = THERMAL.split(marker, 1)[1].split("\nfunc ", 1)[0]
    for key in [
        "upper_gas_kg",
        "lower_gas_kg",
        "upper_energy_kj",
        "temp_upper_c",
        "temp_lower_c",
        "interface_m",
    ]:
        assert f'canonical_input.get("{key}"' in body
    assert "room." not in body


def test_capacity_reduced_formula_and_equilibrium_limit_are_explicit():
    assert "upper_capacity_kj_k * lower_capacity_kj_k" in THERMAL
    assert "capacity_candidate_kj" in THERMAL
    assert "equilibrium_limit_kj" in THERMAL
    assert "minf(capacity_candidate_kj, equilibrium_limit_kj)" in THERMAL


def test_inverted_gradient_cannot_request_downward_heat():
    assert "if delta_t_c <= 1.0e-9:" in THERMAL
    assert 'result["direction_code"] = -1.0' in THERMAL


def test_engine_replaces_only_legacy_interzone_request():
    assert 'cause == "thermal_upper_to_lower"' in ENGINE
    assert "_phase3_shadow_queue_canonical_interzone_heat(room_id, flux, dt)" in ENGINE
    assert "continue" in ENGINE.split('cause == "thermal_upper_to_lower"', 1)[1][:180]


def test_atomic_bundle_caps_energy_at_application_time():
    assert "func queue_canonical_interzone_heat_transfer(" in SYSTEM
    assert '"kind": "canonical_interzone_heat"' in SYSTEM
    atomic = SYSTEM.split(
        "func _evaluate_atomic_bundle_acceptance(", 1
    )[1].split("\nfunc ", 1)[0]
    assert 'zone + "_energy_kj"' in atomic
    assert 'demand.get("sensible_enthalpy_kj"' in atomic


def test_interzone_result_closes_requested_energy():
    assert 'interzone_record["accepted_kj"]' in SYSTEM
    assert 'interzone_record["rejected_kj"]' in SYSTEM
    assert 'interzone_record["energy_residual_kj"]' in SYSTEM


def test_csv_schema_is_conditioned_on_new_flag():
    assert "var phase3_canonical_interzone_heat_shadow_enabled: bool = false" in LOG
    assert "if phase3_canonical_interzone_heat_shadow_enabled:" in LOG
    assert "phase3_shadow_interzone_requested_kj" in LOG


def test_runner_flag_implies_complete_b3_parent_stack():
    block = RUNNER.split("if args.phase3_canonical_interzone_heat_shadow:", 1)[1]
    for flag in [
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
        "--phase3-canonical-plume-shadow",
        "--phase3-canonical-interzone-heat-shadow",
    ]:
        assert flag in block
    assert "engine.phase3_canonical_interzone_heat_shadow_enabled = true" in HEADLESS


def test_direct_runtime_fixture_exists():
    fixture = ROOT / "tests/fixtures/phase3_f32b5a_interzone_heat.gd"
    source = fixture.read_text(encoding="utf-8")
    assert "PHASE3_F32B5A_INTERZONE_HEAT_PASS" in source
    assert "_test_equilibrium_cap_prevents_crossing" in source
    assert "_test_many_steps_conserve_energy" in source
    assert "_test_atomic_apply_and_duplicate_rejection" in source
    assert "_test_atomic_limit_after_prior_energy_loss" in source
