"""Structural checks for F3.2b1 passive closed combustion/plume transactions."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_combustion_transaction_active_flag",
    "phase3_shadow_combustion_canonical_o2_ref",
    "phase3_shadow_combustion_o2_source_zone_code",
    "phase3_shadow_combustion_extinction_o2_limit",
    "phase3_shadow_combustion_canonical_o2_hrr_factor",
    "phase3_shadow_combustion_legacy_o2_hrr_factor",
    "phase3_shadow_combustion_legacy_hrr_kw",
    "phase3_shadow_combustion_accepted_hrr_kw",
    "phase3_shadow_combustion_decision_fraction",
    "phase3_shadow_combustion_atomic_fraction",
    "phase3_shadow_combustion_effective_fraction",
    "phase3_shadow_combustion_requested_o2_kg",
    "phase3_shadow_combustion_accepted_o2_kg",
    "phase3_shadow_combustion_requested_fuel_MJ",
    "phase3_shadow_combustion_accepted_fuel_MJ",
    "phase3_shadow_combustion_requested_species_kg",
    "phase3_shadow_combustion_accepted_species_kg",
    "phase3_shadow_combustion_requested_convective_energy_kj",
    "phase3_shadow_combustion_accepted_convective_energy_kj",
    "phase3_shadow_combustion_requested_plume_mass_kg",
    "phase3_shadow_combustion_accepted_plume_mass_kg",
    "phase3_shadow_combustion_remaining_fuel_MJ",
    "phase3_shadow_combustion_retained_unburned_MJ",
    "phase3_shadow_combustion_zero_o2_flame_flag",
    "phase3_shadow_combustion_o2_residual_kg",
    "phase3_shadow_combustion_energy_residual_kj",
    "phase3_shadow_combustion_species_residual_kg",
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_canonical_combustion_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_combustion_shadow_enabled"' in STATE
    assert "phase3_canonical_combustion_authority" not in ENGINE


def test_evaluator_is_pure_and_uses_canonical_pre_step_o2():
    body = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    assert 'canonical_input.get("upper_o2_kg"' in body
    assert 'canonical_input.get("lower_o2_kg"' in body
    assert 'canonical_input.get("upper_gas_kg"' in body
    assert 'canonical_input.get("lower_gas_kg"' in body
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", body)
    assert not re.search(r"\bfire\.\w+\s*[+\-*/]?=", body)


def test_evaluator_applies_one_fraction_to_hrr_fuel_o2_and_species():
    body = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    assert "accepted_hrr_kw: float = legacy_hrr_kw * accepted_fraction" in body
    assert "accepted_o2_kg: float = requested_o2_kg * accepted_fraction" in body
    assert "accepted_fuel_MJ: float = requested_fuel_MJ * accepted_fraction" in body
    assert "_scale_phase3_species(" in body
    assert '"heat_scale": accepted_fraction' in body
    assert '"plume_scale": pow(accepted_fraction' in body


def test_extinction_forces_factor_and_transaction_to_zero():
    body = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    assert "if extinguished:\n\t\tcanonical_factor = 0.0" in body
    assert "if canonical_factor <= 0.0:\n\t\t\tthrottle_fraction = 0.0" in body
    assert '"zero_o2_flame_flag"' in body


def test_pre_fire_snapshot_is_captured_before_live_step():
    step = _function(ENGINE, "step")
    capture = step.index("combustion_system.begin_phase3_shadow_step(building)")
    live_fire = step.index("_step_fire(dt)")
    evaluate = step.index("_phase3_shadow_collect_species_requests(dt)")
    assert capture < live_fire < evaluate


def test_closed_transaction_suppresses_split_legacy_owners():
    oxygen = _function(ENGINE, "_phase3_shadow_collect_oxygen_requests")
    species = _function(ENGINE, "_phase3_shadow_collect_species_requests")
    thermal = _function(ENGINE, "_phase3_shadow_collect_thermal_requests")
    assert "phase3_canonical_combustion_shadow_enabled" in oxygen
    assert 'cause.begins_with("combustion_o2_")' in oxygen
    assert "stage_canonical_combustion_transaction" in species
    assert 'cause == "combustion_convective_heat"' in thermal
    assert 'cause == "plume_entrainment"' in thermal
    assert "finalize_canonical_combustion_bundle" in thermal


def test_bundle_contains_o2_species_heat_and_plume_routes():
    body = _function(SYSTEM, "finalize_canonical_combustion_bundle")
    for cause in (
        "canonical_combustion_o2_sink",
        "canonical_combustion_species_source",
        "canonical_combustion_convective_heat",
        "canonical_combustion_plume",
    ):
        assert cause in body
    assert '"kind": "canonical_combustion"' in body
    assert "add_atomic_bundle(bundle)" in body


def test_atomic_result_commits_interpolated_fire_state():
    body = _function(SYSTEM, "_record_atomic_bundle_result")
    assert 'result_kind == "canonical_combustion"' in body
    assert "_interpolate_combustion_state(" in body
    finalize = _function(SYSTEM, "finalize_step")
    assert "_persistent_combustion_state[combustion_room_key]" in finalize


def test_reset_clears_fire_persistence_but_step_reset_does_not():
    reset = _function(SYSTEM, "reset")
    step_reset = _function(SYSTEM, "_reset_step_state")
    assert "_persistent_combustion_state.clear()" in reset
    assert "_persistent_combustion_state.clear()" not in step_reset
    assert "_canonical_combustion_by_room.clear()" in step_reset


def test_csv_fields_are_separately_gated_and_unique():
    assert "if phase3_canonical_combustion_shadow_enabled:" in LOG
    for field in FIELDS:
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_all_parent_shadow_contracts():
    block = RUNNER.split("if args.phase3_canonical_combustion_shadow:", 1)[1]
    assert 'cmd.append("--phase3-canonical-shadow")' in block
    assert 'cmd.append("--phase3-canonical-exterior-shadow")' in block
    assert 'cmd.append("--phase3-canonical-persistence-shadow")' in block
    assert 'cmd.append("--phase3-canonical-combustion-shadow")' in block
    assert "engine.phase3_canonical_combustion_shadow_enabled = true" in HEADLESS


def test_default_off_has_no_roommodel_or_live_hrr_authority():
    stage = _function(SYSTEM, "stage_canonical_combustion_transaction")
    bundle = _function(SYSTEM, "finalize_canonical_combustion_bundle")
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", stage + bundle)
    room_model = (ROOT / "sim/building/RoomModel.gd").read_text(encoding="utf-8")
    assert "phase3_shadow_combustion_accepted_hrr_kw" not in room_model


def test_direct_runtime_fixture_exists():
    fixture = ROOT / "tests/fixtures/phase3_f32b1_combustion_transaction.gd"
    source = fixture.read_text(encoding="utf-8")
    assert "PHASE3_F32B1_COMBUSTION_TRANSACTION_PASS" in source
    assert "_test_closed_transaction_scales_every_quantity" in source
    assert "_test_empty_upper_zone_bootstraps_from_lower" in source
    assert "_test_extinction_rejects_the_whole_transaction" in source
    assert "_test_no_fire_is_an_inert_transaction" in source
