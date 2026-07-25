from __future__ import annotations

import csv
import math
from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33r1_boundary_partition as audit,
)


REPO_ROOT = Path(__file__).resolve().parents[1]
CFAST_DIR = REPO_ROOT / "sim" / "validation" / "cfast"


def _write_minimal_sim_csv(path: Path) -> None:
    families = ("wall", "ambient", "exterior", "exterior_counterflow")
    fieldnames = [
        "time_s",
        "room_id",
        "phase3_shadow_upper_gas_kg",
        "phase3_shadow_lower_gas_kg",
        "phase3_shadow_upper_energy_kj",
        "phase3_shadow_lower_energy_kj",
        "phase3_shadow_wall_energy_post_kj",
        "phase3_shadow_wall_temp_post_c",
        "phase3_shadow_thermo_temp_upper_c",
        "phase3_shadow_thermo_temp_lower_c",
        "phase3_shadow_thermo_interface_m",
    ]
    for family in families:
        for zone in ("upper", "lower"):
            for direction in ("in", "out"):
                fieldnames.append(
                    "phase3_shadow_enthalpy_"
                    f"{family}_{zone}_{direction}_kj_total"
                )
    rows = []
    for time_s in (60, 120, 180):
        row = {field: "0" for field in fieldnames}
        row.update(
            {
                "time_s": str(time_s),
                "room_id": "0",
                "phase3_shadow_upper_gas_kg": "20",
                "phase3_shadow_lower_gas_kg": "20",
                "phase3_shadow_wall_energy_post_kj": str(time_s * 10),
                "phase3_shadow_wall_temp_post_c": "21",
                "phase3_shadow_thermo_temp_upper_c": "100",
                "phase3_shadow_thermo_temp_lower_c": "30",
                "phase3_shadow_thermo_interface_m": "1.0",
                "phase3_shadow_enthalpy_wall_upper_out_kj_total": str(
                    time_s * 20
                ),
                "phase3_shadow_enthalpy_wall_lower_out_kj_total": str(
                    time_s * 2
                ),
                "phase3_shadow_enthalpy_ambient_upper_out_kj_total": str(
                    time_s * 5
                ),
                "phase3_shadow_enthalpy_exterior_upper_out_kj_total": str(
                    time_s
                ),
            }
        )
        rows.append(row)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def test_read_cfast_walls_skips_metadata_rows() -> None:
    rows = audit.read_cfast_walls(
        CFAST_DIR / "cfast_corridor_chain_walls.csv"
    )
    assert float(rows[0]["Time"]) == pytest.approx(0.0)
    assert float(rows[-1]["Time"]) == pytest.approx(590.0)
    assert "CEILT_1" in rows[0]


def test_surface_areas_close_full_enclosure() -> None:
    areas = audit.surface_areas_m2(5.0, 4.0, 2.4, 0.8)
    assert areas["ceiling"] == pytest.approx(20.0)
    assert areas["floor"] == pytest.approx(20.0)
    assert sum(areas.values()) == pytest.approx(83.2)
    assert areas["upper_wall"] == pytest.approx(28.8)
    assert areas["lower_wall"] == pytest.approx(14.4)


def test_surface_areas_clamp_interface() -> None:
    low = audit.surface_areas_m2(5.0, 4.0, 2.4, -1.0)
    high = audit.surface_areas_m2(5.0, 4.0, 2.4, 9.0)
    assert low["lower_wall"] == pytest.approx(0.0)
    assert high["upper_wall"] == pytest.approx(0.0)


def test_semi_infinite_constant_temperature_has_zero_flux() -> None:
    flux = audit.semi_infinite_heat_flux_w_m2(
        [0.0, 10.0, 20.0], [20.0, 20.0, 20.0]
    )
    assert flux == pytest.approx([0.0, 0.0, 0.0])


def test_semi_infinite_linear_ramp_matches_duhamel_solution() -> None:
    flux = audit.semi_infinite_heat_flux_w_m2(
        [0.0, 10.0], [20.0, 30.0]
    )
    factor = math.sqrt(
        audit.CONCRETE_K_W_M_K
        * audit.CONCRETE_RHO_KG_M3
        * audit.CONCRETE_CP_J_KG_K
        / math.pi
    )
    assert flux[1] == pytest.approx(2.0 * factor * math.sqrt(10.0))


def test_semi_infinite_cooling_has_negative_flux() -> None:
    flux = audit.semi_infinite_heat_flux_w_m2(
        [0.0, 10.0], [30.0, 20.0]
    )
    assert flux[1] < 0.0


@pytest.mark.parametrize(
    ("times", "temperatures"),
    [([0.0], [20.0, 21.0]), ([0.0, 0.0], [20.0, 21.0])],
)
def test_semi_infinite_rejects_invalid_series(
    times: list[float], temperatures: list[float]
) -> None:
    with pytest.raises(ValueError):
        audit.semi_infinite_heat_flux_w_m2(times, temperatures)


def test_canonical_boundary_snapshot_uses_signed_ledgers() -> None:
    row = {
        "time_s": "60",
        "room_id": "0",
        "phase3_shadow_enthalpy_wall_upper_out_kj_total": "10",
        "phase3_shadow_enthalpy_wall_upper_in_kj_total": "2",
        "phase3_shadow_enthalpy_wall_lower_out_kj_total": "4",
        "phase3_shadow_enthalpy_wall_lower_in_kj_total": "1",
        "phase3_shadow_enthalpy_ambient_upper_out_kj_total": "5",
        "phase3_shadow_enthalpy_exterior_lower_out_kj_total": "3",
    }
    result = audit.canonical_boundary_snapshot([row], 0, 60)
    assert result["wall_upper_sink_kj"] == pytest.approx(8.0)
    assert result["wall_lower_sink_kj"] == pytest.approx(3.0)
    assert result["wall_sink_kj"] == pytest.approx(11.0)
    assert result["total_boundary_sink_kj"] == pytest.approx(19.0)


def test_real_cfast_surface_storage_is_positive_and_partitioned() -> None:
    walls = audit.read_cfast_walls(
        CFAST_DIR / "cfast_corridor_chain_walls.csv"
    )
    zones = audit.f33m.read_cfast_zone(
        CFAST_DIR / "cfast_corridor_chain_zone.csv"
    )
    compartments = audit.f33m.read_cfast_compartments(
        CFAST_DIR / "cfast_corridor_chain_compartments.csv"
    )
    result = audit.estimate_cfast_surface_storage(
        wall_rows=walls,
        zone_rows=zones,
        compartment_rows=compartments,
        room_id=0,
    )
    final = result[180]
    assert final["total_surface_storage_kj"] == pytest.approx(
        26993.37, rel=1.0e-4
    )
    assert final["upper_surface_storage_kj"] > (
        final["lower_surface_storage_kj"]
    )
    assert sum(final["surface_area_m2"].values()) == pytest.approx(83.2)


def test_build_audit_separates_direct_radiation() -> None:
    sim_csv = REPO_ROOT / "runs" / "_pytest_f33r1_sim.csv"
    try:
        _write_minimal_sim_csv(sim_csv)
        result = audit.build_audit(
            base_sim_csv=sim_csv,
            material_sim_csv=sim_csv,
            cfast_zone_path=CFAST_DIR / "cfast_corridor_chain_zone.csv",
            cfast_compartments_path=(
                CFAST_DIR / "cfast_corridor_chain_compartments.csv"
            ),
            cfast_walls_path=CFAST_DIR / "cfast_corridor_chain_walls.csv",
        )
        final = result["final_partition"]
        assert final["cfast_surface_storage_kj"] == pytest.approx(
            26993.37, rel=1.0e-4
        )
        assert final["cfast_direct_fire_radiation_kj"] == pytest.approx(
            13392.4, rel=1.0e-4
        )
        assert final["cfast_gas_driven_surface_storage_kj"] == pytest.approx(
            13600.97, rel=1.0e-4
        )
        assert (
            result["interpretation"]["full_area_patch_authorized"] is False
        )
    finally:
        sim_csv.unlink(missing_ok=True)
