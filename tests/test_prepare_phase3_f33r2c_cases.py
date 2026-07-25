"""Contracts for scratch-only F3.3r2c case preparation."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "scripts" / "simulation" / "prepare_phase3_f33r2c_cases.py"
SPEC = importlib.util.spec_from_file_location("prepare_f33r2c", SCRIPT_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_builds_only_scratch_variants_with_documented_source_pair():
    cases = MODULE.build_cases()
    assert set(cases) == {
        "corridor_off.json",
        "corridor_cfast_boundary.json",
        "corridor_physical_boundary.json",
        "corridor_no_opening.json",
        "sealed_material_fixture.json",
    }
    for case in cases.values():
        engine = case["engine_overrides"]
        assert engine["hrr_chi_rad_normal"] == 0.35
        assert engine["hrr_chi_rad_low_o2"] == 0.35
        assert engine["plume_fire_diameter_m"] == 0.6196
        assert case["duration_s"] == 180.0
        assert "log_file_path" not in engine
        assert "csv_log_file_path" not in engine


def test_off_differs_from_cfast_boundary_only_by_multisurface_activation():
    cases = MODULE.build_cases()
    off = cases["corridor_off.json"]
    on = cases["corridor_cfast_boundary.json"]
    off["engine_overrides"]["phase3_canonical_multisurface_shadow_enabled"] = True
    assert off == on


def test_cfast_boundary_matches_independent_compartment_surface_contract():
    case = MODULE.build_cases()["corridor_cfast_boundary.json"]
    overrides = {entry["id"]: entry for entry in case["room_overrides"]}
    for room_id in (0, 1, 2):
        room = overrides[room_id]
        for surface in room["phase3_surface_boundaries"].values():
            assert surface == {
                "exterior_fraction": 1.0,
                "inter_room_fraction": 0.0,
                "adiabatic_fraction": 0.0,
            }
        assert room["wall_k_kw_m_k"] == 0.00175
        assert room["wall_rho_kg_m3"] == 2200.0
        assert room["wall_cp_kj_kg_k"] == 1.0
        assert room["wall_thickness_m"] == 0.15


def test_physical_wall_fractions_close_and_expose_unsupported_pairing():
    case = MODULE.build_cases()["corridor_physical_boundary.json"]
    overrides = {entry["id"]: entry for entry in case["room_overrides"]}
    for room_id, room in overrides.items():
        for name, surface in room["phase3_surface_boundaries"].items():
            assert abs(sum(surface.values()) - 1.0) < 1.0e-12
            if name in ("upper_wall", "lower_wall"):
                assert surface["inter_room_fraction"] > 0.0
        if room_id == 1:
            upper = room["phase3_surface_boundaries"]["upper_wall"]
            assert abs(upper["exterior_fraction"] - 3.0 / 17.0) < 1.0e-12


def test_no_opening_control_closes_every_interior_opening():
    case = MODULE.build_cases()["corridor_no_opening.json"]
    for opening in case["opening_overrides"]:
        if int(opening.get("b", -1)) >= 0:
            assert opening["open_fraction"] == 0.0


def test_writer_does_not_touch_official_case_directory():
    scratch = ROOT / "runs" / "_pytest_f33r2c_cases"
    try:
        written = MODULE.write_cases(scratch)
        assert len(written) == 5
        assert all(path.parent == scratch for path in written)
    finally:
        if scratch.exists():
            for path in scratch.iterdir():
                path.unlink()
            scratch.rmdir()
