"""Structural contracts for F3.3r2b1 gas/surface/exterior exchange."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/Phase3SurfaceEnergySolver.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33r2b1_multisurface_exchange.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_preview_is_snapshot_only_and_separate_from_queue():
    preview = _function(SYSTEM, "preview_canonical_multisurface_exchange")
    queue = _function(SYSTEM, "queue_canonical_multisurface_exchange")
    assert "_snapshots.has(room_key)" in preview
    assert "_canonical_surface_state_by_room" in preview
    assert "add_atomic_bundle" not in preview
    assert "_canonical_surface_state_by_room[room_key] =" not in preview
    assert "add_atomic_bundle(make_atomic_bundle(" in queue


def test_preview_has_explicit_convection_radiation_and_boundary_metadata():
    preview = _function(SYSTEM, "preview_canonical_multisurface_exchange")
    assert "STEFAN_BOLTZMANN_KW_M2_K4" in preview
    assert '"interior_h_kw_m2_k": interior_h' in preview
    assert '"gas_radiation_energy_kj": gas_radiation_kj' in preview
    assert '"exterior_by_surface"' in preview
    assert '"boundary_metadata_complete_flag"' in preview
    assert '"adiabatic_surface_count"' in preview


def test_queue_uses_signed_zone_energy_routes_and_one_atomic_fraction():
    queue = _function(SYSTEM, "queue_canonical_multisurface_exchange")
    assert "for zone_name in [ZONE_UPPER, ZONE_LOWER]" in queue
    assert '"canonical_" + zone_name + "_to_multisurface"' in queue
    assert '"canonical_multisurface_to_" + zone_name' in queue
    result = _function(SYSTEM, "_record_atomic_bundle_result")
    assert 'result_kind == "canonical_multisurface_exchange"' in result
    assert 'exchange_record["accepted_fraction"] = exchange_fraction' in result


def test_surface_commit_applies_prescribed_accepted_energies_once():
    commit = _function(
        SYSTEM, "commit_canonical_multisurface_combustion_radiation"
    )
    assert '"interior_convection_energy_kj": convection_kj' in commit
    assert '"gas_radiation_energy_kj": gas_radiation_kj' in commit
    assert '"fire_radiation_energy_kj": surface_radiation_kj' in commit
    assert '"exterior_energy_removed_kj": exterior_removed_kj' in commit
    assert 'candidate_surfaces[surface_name] = solved["post_state"]' in commit
    assert commit.count("_canonical_surface_state_by_room[room_key] = state_post") == 1
    assert '"combined_energy_residual_kj"' in commit


def test_engine_prepares_all_rooms_and_resolves_physical_topology():
    collect = _function(ENGINE, "_phase3_shadow_collect_thermal_requests")
    prepare = _function(ENGINE, "_phase3_prepare_canonical_multisurface_room")
    queue = _function(
        ENGINE, "_phase3_shadow_queue_canonical_multisurface_exchange"
    )
    assert "for raw_room_id in building.get_rooms().keys()" in collect
    assert "_phase3_prepare_canonical_multisurface_room" in collect
    assert "prepare_canonical_multisurface_room" in prepare
    assert "build_canonical_surface_boundary_context" in queue
    assert "room.phase3_surface_boundaries" in queue


def test_solver_prescribed_boundary_api_is_fail_closed():
    validate = _function(SOLVER, "_validate_boundary")
    assert "prescribed convection conflicts with interior coefficient" in validate
    assert "prescribed exterior energy conflicts with exterior coefficient" in validate


def test_runtime_fixture_covers_f33r2b1_stop_gates():
    assert "PHASE3_F33R2B1_MULTISURFACE_EXCHANGE_PASS" in FIXTURE
    for name in (
        "_test_default_off_fails_closed",
        "_test_preview_is_adiabatic_without_topology",
        "_test_full_gas_to_surface_exchange",
        "_test_partial_and_rejected_atomic_exchange",
        "_test_surface_to_gas_signed_exchange",
        "_test_explicit_exterior_loss_closes_combined_ledger",
    ):
        assert name in FIXTURE
