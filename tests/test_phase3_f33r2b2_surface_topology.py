"""Structural contracts for F3.3r2b2 physical enclosure topology."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROOM = (ROOT / "sim/building/RoomModel.gd").read_text(encoding="utf-8")
BUILDING = (ROOT / "sim/BuildingModel.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
SERIALIZER = (ROOT / "editor/ScenarioSerializer.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33r2b2_surface_topology.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_room_owns_explicit_physical_topology_and_building_deep_copies_it():
    assert "var phase3_surface_boundaries: Dictionary = {}" in ROOM
    load = _function(BUILDING, "_load_from_template")
    assert '"phase3_surface_boundaries"' in load
    assert "Dictionary(phase3_boundaries).duplicate(true)" in load


def test_editor_runtime_serialization_preserves_nested_room_metadata():
    runtime = _function(SERIALIZER, "to_runtime_template")
    normalize = _function(SERIALIZER, "normalize_editor_data")
    assert "Dictionary(raw_room).duplicate(true)" in runtime
    assert "rooms_data.append(room)" in runtime
    assert "Dictionary(raw_room).duplicate(true)" in normalize
    assert "rooms.append(room)" in normalize


def test_topology_contract_requires_all_surfaces_and_three_fractions():
    build = _function(SYSTEM, "build_canonical_surface_boundary_context")
    assert "for surface_name in CANONICAL_SURFACE_NAMES" in build
    for name in (
        "exterior_fraction",
        "inter_room_fraction",
        "adiabatic_fraction",
    ):
        assert name in build
    assert "fractions do not sum to one" in build
    assert "SURFACE_FRACTION_TOLERANCE" in build


def test_topology_fails_closed_without_geometric_or_visual_inference():
    build = _function(SYSTEM, "build_canonical_surface_boundary_context")
    assert '"valid": false' in build
    assert '"adiabatic_surface_count": 4.0' in build
    assert '"exterior_by_surface": {}' in build
    forbidden = ("room_rect_m", "exterior_walls", "Mesh", "Visual", "opening")
    assert all(token not in build for token in forbidden)


def test_exterior_fraction_scales_fixed_canonical_coefficient():
    build = _function(SYSTEM, "build_canonical_surface_boundary_context")
    assert "CANONICAL_EXTERIOR_H_KW_M2_K * exterior_fraction" in build
    assert "const CANONICAL_EXTERIOR_H_KW_M2_K: float = 0.025" in SYSTEM
    assert "exterior_h_kw_m2_k" not in ROOM


def test_inter_room_fraction_is_visible_but_not_silently_exchanged():
    build = _function(SYSTEM, "build_canonical_surface_boundary_context")
    assert '"unsupported_inter_room_surface_count"' in build
    assert "paired-surface correspondence" in build
    engine_queue = _function(
        ENGINE, "_phase3_shadow_queue_canonical_multisurface_exchange"
    )
    assert '"unsupported_inter_room_surface_count"' in engine_queue


def test_engine_uses_room_physics_metadata_only_in_multisurface_shadow():
    queue = _function(
        ENGINE, "_phase3_shadow_queue_canonical_multisurface_exchange"
    )
    assert "room.phase3_surface_boundaries" in queue
    assert "build_canonical_surface_boundary_context" in queue
    assert "building.outside_temp_c" in queue
    assert "Visual" not in queue


def test_no_official_validation_case_activates_surface_topology():
    case_dir = ROOT / "sim/validation/cases"
    activated = []
    for path in case_dir.glob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        for room in data.get("room_overrides", []):
            if "phase3_surface_boundaries" in room:
                activated.append(path.name)
    assert activated == []


def test_topology_and_exchange_diagnostics_are_exported_in_shadow_csv():
    for field in (
        "phase3_shadow_multisurface_boundary_metadata_complete_flag",
        "phase3_shadow_multisurface_exterior_fraction_sum",
        "phase3_shadow_multisurface_inter_room_fraction_sum",
        "phase3_shadow_multisurface_adiabatic_fraction_sum",
        "phase3_shadow_multisurface_unsupported_inter_room_count",
    ):
        assert LOG.count(f'"{field}"') == 1
        assert f",{field}" in LOG


def test_runtime_fixture_covers_f33r2b2_stop_gates():
    assert "PHASE3_F33R2B2_SURFACE_TOPOLOGY_PASS" in FIXTURE
    for name in (
        "_test_missing_topology_fails_adiabatic",
        "_test_valid_mixed_topology",
        "_test_explicit_zero_exterior_is_complete",
        "_test_invalid_topologies_fail_closed",
        "_test_building_loads_deep_copy",
        "_test_mixed_exterior_exchange_closes",
    ):
        assert name in FIXTURE
