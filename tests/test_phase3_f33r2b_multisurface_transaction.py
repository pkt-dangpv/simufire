"""Structural checks for the opt-in F3.3r2b multisurface transaction."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/Phase3SurfaceEnergySolver.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
CASES = tuple((ROOT / "sim/validation/cases").glob("*.json"))


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_requires_parent_contracts():
    assert (
        "@export var phase3_canonical_multisurface_shadow_enabled: bool = false"
        in ENGINE
    )
    active = _function(ENGINE, "_phase3_canonical_multisurface_active")
    for parent in (
        "phase3_canonical_zone_shadow_enabled",
        "phase3_canonical_persistence_shadow_enabled",
        "phase3_canonical_combustion_shadow_enabled",
        "phase3_canonical_multisurface_shadow_enabled",
    ):
        assert parent in active
    assert '"phase3_canonical_multisurface_shadow_enabled"' in STATE


def test_flag_has_no_cli_or_official_case_activation():
    assert "--phase3-canonical-multisurface" not in RUNNER
    assert "--phase3-canonical-multisurface" not in HEADLESS
    for case_path in CASES:
        assert "phase3_canonical_multisurface_shadow_enabled" not in case_path.read_text(
            encoding="utf-8"
        ), case_path.name


def test_multisurface_state_is_persistent_but_step_records_reset():
    reset = _function(SYSTEM, "reset")
    step_reset = _function(SYSTEM, "_reset_step_state")
    begin = _function(SYSTEM, "begin_step")
    assert "_canonical_surface_state_by_room.clear()" in reset
    assert "_canonical_surface_state_by_room.clear()" not in step_reset
    assert "_canonical_multisurface_by_room.clear()" in step_reset
    assert "_canonical_surface_state_by_room.clear()" in begin
    assert "if not persistence_enabled" in begin


def test_prepare_uses_explicit_geometry_material_and_four_surfaces():
    body = _function(SYSTEM, "prepare_canonical_multisurface_room")
    for field in ("floor_area_m2", "perimeter_m", "height_m", "interface_m"):
        assert field in body
    for field in (
        "conductivity_kw_m_k",
        "density_kg_m3",
        "cp_kj_kg_k",
        "thickness_m",
        "emissivity",
    ):
        assert field in SYSTEM
    for surface in ("ceiling", "upper_wall", "lower_wall", "floor"):
        assert f'"{surface}"' in body
    assert "_validate_multisurface_geometry" in body
    assert "_validate_multisurface_material" in body
    assert "_multisurface_material_matches" in body


def test_interface_migration_is_area_weighted_and_energy_audited():
    body = _function(SYSTEM, "prepare_canonical_multisurface_room")
    assert "_mix_surface_area_profiles" in body
    assert "_canonical_multisurface_total_energy(state)" in body
    assert "migration_residual_kj = energy_post_kj - energy_pre_kj" in body
    mix = _function(SYSTEM, "_mix_surface_area_profiles")
    assert "float(target_nodes[index]) * target_area_m2" in mix
    assert "float(donor_nodes[index]) * moved_area_m2" in mix


def test_combustion_radiation_is_metadata_until_atomic_commit():
    evaluator = _function(COMBUSTION, "evaluate_phase3_canonical_combustion_step")
    assert "requested_radiative_energy_kj" in evaluator
    assert "accepted_radiative_energy_kj" in evaluator
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", evaluator)
    stage = _function(SYSTEM, "stage_canonical_combustion_transaction")
    assert 'record["accepted_radiative_energy_kj"]' in stage
    assert "Phase3SurfaceEnergySolverScript.step_surface" not in stage


def test_bundle_finalizes_radiation_as_exact_convective_complement():
    bundle = _function(SYSTEM, "finalize_canonical_combustion_bundle")
    assert "accepted_total_fire_energy_kj - accepted_heat_kj" in bundle
    assert "requested_total_fire_energy_kj - requested_heat_kj" in bundle
    assert "fire_partition_residual_kj" in bundle


def test_surface_deposit_uses_atomic_fraction_and_area_emissivity_split():
    body = _function(
        SYSTEM, "commit_canonical_multisurface_combustion_radiation"
    )
    assert 'combustion.get("atomic_accepted_fraction", 1.0)' in body
    assert ') * atomic_fraction' in body
    assert 'surface.get("area_m2", 0.0)' in body
    assert 'surface.get("emissivity", 0.0)' in body
    assert "Phase3SurfaceEnergySolverScript.step_surface" in body
    assert '"fire_radiation_energy_kj": surface_radiation_kj' in body
    assert "_canonical_surface_state_by_room[room_key] = state_post" in body


def test_surface_commit_is_atomic_and_duplicate_guarded():
    body = _function(
        SYSTEM, "commit_canonical_multisurface_combustion_radiation"
    )
    candidate = body.index("var candidate_surfaces")
    solve = body.index("Phase3SurfaceEnergySolverScript.step_surface")
    commit = body.index("_canonical_surface_state_by_room[room_key] = state_post")
    assert candidate < solve < commit
    assert "_canonical_multisurface_radiation_committed_by_room.has" in body
    assert "_canonical_multisurface_duplicate_commit_count += 1" in body


def test_old_lumped_wall_path_is_mutually_exclusive():
    queue = _function(SYSTEM, "queue_canonical_wall_ambient_transfer")
    assert (
        "if canonical_multisurface_shadow_enabled:\n\t\treturn false" in queue
    )
    thermal = _function(ENGINE, "_phase3_shadow_collect_thermal_requests")
    assert "and not _phase3_canonical_multisurface_active()" in thermal
    sync = _function(ENGINE, "_sync_auxiliary_services")
    assert "and not phase3_canonical_multisurface_shadow_enabled" in sync


def test_zero_area_surfaces_are_inert_and_cannot_receive_radiation():
    step = _function(SOLVER, "step_surface")
    assert "if area_m2 <= EPSILON:" in step
    assert "cannot deposit radiation on zero-area surface" in step
    validate = _function(SOLVER, "_validate_state")
    assert "area_m2 < 0.0" in validate


def test_new_fields_do_not_change_csv_schema():
    assert "phase3_shadow_multisurface" not in LOG
    assert "phase3_shadow_combustion_requested_radiative_energy_kj" not in LOG


def test_multisurface_functions_do_not_mutate_roommodel():
    bodies = "".join(
        _function(SYSTEM, name)
        for name in (
            "prepare_canonical_multisurface_room",
            "commit_canonical_multisurface_combustion_radiation",
            "_commit_canonical_multisurface_records",
        )
    )
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", bodies)


def test_direct_runtime_fixture_covers_transaction_edges():
    fixture = (
        ROOT / "tests/fixtures/phase3_f33r2b_multisurface_transaction.gd"
    ).read_text(encoding="utf-8")
    assert "PHASE3_F33R2B_MULTISURFACE_TRANSACTION_PASS" in fixture
    for test_name in (
        "_test_default_off_is_inert",
        "_test_seeded_geometry_and_zero_area_edges",
        "_test_full_atomic_acceptance_routes_radiation_once",
        "_test_partial_atomic_acceptance_scales_radiation",
        "_test_atomic_rejection_keeps_surfaces_unchanged",
        "_test_interface_migration_conserves_surface_energy",
        "_test_lumped_wall_path_is_mutually_exclusive",
    ):
        assert test_name in fixture
