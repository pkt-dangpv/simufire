"""Tests for the F3.3r2c staged correspondence analyzer."""

from __future__ import annotations

import csv
from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33r2c_correspondence as audit,
)

ROOT = Path(__file__).resolve().parents[1]


def _row(**updates: str) -> dict[str, str]:
    row = {
        "time_s": "180",
        "room_id": "0",
        "temp_upper_c": "100",
        "phase3_shadow_thermo_temp_upper_c": "100",
        "phase3_shadow_thermo_temp_lower_c": "30",
        "phase3_shadow_thermo_interface_m": "1",
        "phase3_shadow_upper_gas_kg": "20",
        "phase3_shadow_lower_gas_kg": "20",
        "phase3_shadow_multisurface_energy_post_kj": "100",
        "phase3_shadow_multisurface_cumulative_fire_radiation_kj": "40",
        "phase3_shadow_multisurface_cumulative_gas_exchange_kj": "60",
        "phase3_shadow_multisurface_cumulative_exterior_removed_kj": "0",
        "phase3_shadow_multisurface_cumulative_energy_residual_kj": "0",
    }
    row.update(updates)
    return row


def test_sim_snapshot_partitions_storage_and_exports_surfaces():
    row = _row()
    for surface in audit.SURFACES:
        prefix = f"phase3_shadow_multisurface_{surface}"
        row[prefix + "_energy_kj"] = "25"
        row[prefix + "_temp_inner_c"] = "21"
    result = audit.sim_snapshot([row], 0, 180)
    assert result["surface_storage_kj"] == pytest.approx(100)
    assert result["fire_radiation_kj"] == pytest.approx(40)
    assert result["gas_driven_surface_storage_kj"] == pytest.approx(60)
    assert result["surfaces"]["ceiling"]["energy_kj"] == pytest.approx(25)


def test_legacy_comparison_ignores_shadow_fields():
    off = [_row()]
    on = [_row(phase3_shadow_thermo_temp_upper_c="999")]
    result = audit.compare_legacy_cells(off, on)
    assert result["same_rows"] is True
    assert result["different_cells"] == 0
    on[0]["temp_upper_c"] = "101"
    result = audit.compare_legacy_cells(off, on)
    assert result["different_cells"] == 1


def test_gate_uses_absolute_limit():
    assert audit._gate("x", 9.0, 10.0, 1.0)["pass"] is True
    assert audit._gate("x", 8.99, 10.0, 1.0)["pass"] is False


def test_real_cfast_reference_matches_f33r1_contract():
    wall_rows = audit.f33r1.read_cfast_walls(
        audit.CFAST_DIR / "cfast_corridor_chain_walls.csv"
    )
    zone_rows = audit.f33m.read_cfast_zone(
        audit.CFAST_DIR / "cfast_corridor_chain_zone.csv"
    )
    compartment_rows = audit.f33m.read_cfast_compartments(
        audit.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
    )
    surfaces = audit.f33r1.estimate_cfast_surface_storage(
        wall_rows=wall_rows,
        zone_rows=zone_rows,
        compartment_rows=compartment_rows,
        room_id=0,
    )
    cfast = audit.f33m.build_cfast_checkpoint(
        180, zone_rows, compartment_rows
    )
    radiation = (
        audit.f33r1.RADIATIVE_FRACTION
        * cfast["rooms"]["0"]["hrr_energy_kj"]
    )
    assert surfaces[180]["total_surface_storage_kj"] == pytest.approx(
        26993.37, rel=1.0e-4
    )
    assert radiation == pytest.approx(13392.4, rel=1.0e-4)


def test_read_rows_rejects_empty_file():
    path = ROOT / "runs" / "_pytest_f33r2c_empty.csv"
    try:
        with path.open("w", newline="", encoding="utf-8") as handle:
            csv.writer(handle).writerow(["time_s", "room_id"])
        with pytest.raises(ValueError, match="empty CSV"):
            audit.read_rows(path)
    finally:
        path.unlink(missing_ok=True)
