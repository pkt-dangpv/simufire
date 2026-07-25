#!/usr/bin/env python3
"""Audit Phase 3 F3.3r1 boundary-energy partition.

The audit estimates CFAST surface heat storage from the exported inner-surface
temperature histories and a semi-infinite concrete response. It then separates
direct fire radiation from gas-driven surface uptake and compares that
partition with the canonical wall, ambient and exterior ledgers.

This tool is read-only. It never changes simulation state, validation cases,
reports, expected values, tolerances or gaps.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.simulation import (
    analyze_phase3_f33m_source_correspondence as f33m,
)
from scripts.simulation import (
    analyze_phase3_f33q_boundary_energy as f33q,
)


CHECKPOINTS = (60, 120, 180)
ROOM_GEOMETRY_M = {
    0: (5.0, 4.0, 2.4),
    1: (1.5, 7.0, 2.4),
    2: (3.5, 3.0, 2.4),
}
SURFACE_PREFIXES = {
    "ceiling": "CEILT",
    "upper_wall": "UWALLT",
    "lower_wall": "LWALLT",
    "floor": "FLOORT",
}
CONCRETE_K_W_M_K = 1.75
CONCRETE_RHO_KG_M3 = 2200.0
CONCRETE_CP_J_KG_K = 1000.0
RADIATIVE_FRACTION = 0.35


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def read_cfast_walls(path: Path) -> list[dict[str, str]]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if len(lines) < 5:
        raise ValueError(f"CFAST wall CSV has no data rows: {path}")
    header = next(csv.reader([lines[0]]))
    return [
        dict(zip(header, values))
        for values in csv.reader(lines[4:])
        if values and values[0].strip()
    ]


def read_sim_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"empty SimuFire CSV: {path}")
    return rows


def surface_areas_m2(
    width_m: float,
    length_m: float,
    height_m: float,
    interface_m: float,
) -> dict[str, float]:
    floor_area_m2 = width_m * length_m
    perimeter_m = 2.0 * (width_m + length_m)
    interface_m = min(max(interface_m, 0.0), height_m)
    return {
        "ceiling": floor_area_m2,
        "upper_wall": perimeter_m * (height_m - interface_m),
        "lower_wall": perimeter_m * interface_m,
        "floor": floor_area_m2,
    }


def semi_infinite_heat_flux_w_m2(
    times_s: list[float],
    surface_temp_c: list[float],
    *,
    conductivity_w_m_k: float = CONCRETE_K_W_M_K,
    density_kg_m3: float = CONCRETE_RHO_KG_M3,
    specific_heat_j_kg_k: float = CONCRETE_CP_J_KG_K,
) -> list[float]:
    """Return inward heat flux for a prescribed surface-temperature history.

    The Duhamel solution is evaluated for piecewise-linear temperature data.
    The 180 s penetration depth is much smaller than the 0.15 m CFAST slab,
    so the semi-infinite approximation is appropriate for this attribution
    audit. It is not a replacement wall model.
    """
    if len(times_s) != len(surface_temp_c):
        raise ValueError("time and temperature lengths differ")
    if not times_s:
        return []
    if conductivity_w_m_k <= 0.0 or density_kg_m3 <= 0.0 \
            or specific_heat_j_kg_k <= 0.0:
        raise ValueError("material properties must be positive")
    if any(times_s[index] <= times_s[index - 1] for index in range(1, len(times_s))):
        raise ValueError("times must be strictly increasing")

    effusivity_factor = math.sqrt(
        conductivity_w_m_k * density_kg_m3 * specific_heat_j_kg_k
        / math.pi
    )
    fluxes: list[float] = []
    for current_index, current_time_s in enumerate(times_s):
        convolution = 0.0
        for interval_index in range(1, current_index + 1):
            start_s = times_s[interval_index - 1]
            end_s = times_s[interval_index]
            slope_k_s = (
                surface_temp_c[interval_index]
                - surface_temp_c[interval_index - 1]
            ) / (end_s - start_s)
            convolution += 2.0 * slope_k_s * (
                math.sqrt(max(0.0, current_time_s - start_s))
                - math.sqrt(max(0.0, current_time_s - end_s))
            )
        fluxes.append(effusivity_factor * convolution)
    return fluxes


def _sim_row_at(
    rows: Iterable[dict[str, str]], room_id: int, checkpoint_s: float
) -> dict[str, str]:
    candidates = [
        row for row in rows if int(_number(row.get("room_id"))) == room_id
    ]
    if not candidates:
        raise ValueError(f"room {room_id} is absent from SimuFire CSV")
    return min(
        candidates,
        key=lambda row: abs(_number(row.get("time_s")) - checkpoint_s),
    )


def canonical_boundary_snapshot(
    rows: list[dict[str, str]], room_id: int, checkpoint_s: float
) -> dict[str, float]:
    row = _sim_row_at(rows, room_id, checkpoint_s)

    def family_zone_sink(family: str, zone: str) -> float:
        prefix = f"phase3_shadow_enthalpy_{family}_{zone}_"
        return (
            _number(row.get(prefix + "out_kj_total"))
            - _number(row.get(prefix + "in_kj_total"))
        )

    wall_upper_kj = family_zone_sink("wall", "upper")
    wall_lower_kj = family_zone_sink("wall", "lower")
    ambient_upper_kj = family_zone_sink("ambient", "upper")
    ambient_lower_kj = family_zone_sink("ambient", "lower")
    exterior_upper_kj = family_zone_sink("exterior", "upper") \
        + family_zone_sink("exterior_counterflow", "upper")
    exterior_lower_kj = family_zone_sink("exterior", "lower") \
        + family_zone_sink("exterior_counterflow", "lower")
    return {
        "time_s": _number(row.get("time_s")),
        "wall_upper_sink_kj": wall_upper_kj,
        "wall_lower_sink_kj": wall_lower_kj,
        "wall_sink_kj": wall_upper_kj + wall_lower_kj,
        "ambient_upper_sink_kj": ambient_upper_kj,
        "ambient_lower_sink_kj": ambient_lower_kj,
        "ambient_sink_kj": ambient_upper_kj + ambient_lower_kj,
        "exterior_sink_kj": exterior_upper_kj + exterior_lower_kj,
        "total_boundary_sink_kj": (
            wall_upper_kj
            + wall_lower_kj
            + ambient_upper_kj
            + ambient_lower_kj
            + exterior_upper_kj
            + exterior_lower_kj
        ),
        "wall_reservoir_energy_kj": _number(
            row.get("phase3_shadow_wall_energy_post_kj")
        ),
        "wall_temp_c": _number(
            row.get("phase3_shadow_wall_temp_post_c"), 20.0
        ),
        "upper_temp_c": _number(
            row.get("phase3_shadow_thermo_temp_upper_c"), 20.0
        ),
        "lower_temp_c": _number(
            row.get("phase3_shadow_thermo_temp_lower_c"), 20.0
        ),
        "interface_m": _number(
            row.get("phase3_shadow_thermo_interface_m")
        ),
    }


def estimate_cfast_surface_storage(
    *,
    wall_rows: list[dict[str, str]],
    zone_rows: list[dict[str, str]],
    compartment_rows: list[dict[str, str]],
    room_id: int,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[int, dict[str, Any]]:
    if room_id not in ROOM_GEOMETRY_M:
        raise ValueError(f"unsupported corridor room id: {room_id}")
    checkpoint_values = tuple(checkpoints)
    max_checkpoint = max(checkpoint_values)
    selected_rows = [
        row for row in wall_rows if _number(row.get("Time")) <= max_checkpoint
    ]
    if not selected_rows:
        raise ValueError("no CFAST wall rows inside checkpoint range")
    times_s = [_number(row.get("Time")) for row in selected_rows]
    suffix = room_id + 1
    temperatures = {
        surface: [
            _number(row.get(f"{prefix}_{suffix}"))
            for row in selected_rows
        ]
        for surface, prefix in SURFACE_PREFIXES.items()
    }
    fluxes = {
        surface: semi_infinite_heat_flux_w_m2(times_s, values)
        for surface, values in temperatures.items()
    }

    width_m, length_m, height_m = ROOM_GEOMETRY_M[room_id]
    areas_by_index: list[dict[str, float]] = []
    for time_s in times_s:
        room = f33m.build_cfast_checkpoint(
            int(round(time_s)), zone_rows, compartment_rows
        )["rooms"][str(room_id)]
        areas_by_index.append(
            surface_areas_m2(
                width_m,
                length_m,
                height_m,
                _number(room.get("interface_m")),
            )
        )

    cumulative_kj = {surface: 0.0 for surface in SURFACE_PREFIXES}
    result: dict[int, dict[str, Any]] = {}
    checkpoint_set = set(checkpoint_values)
    if int(round(times_s[0])) in checkpoint_set:
        result[int(round(times_s[0]))] = {
            "surface_storage_kj": cumulative_kj.copy()
        }
    for index in range(1, len(times_s)):
        dt_s = times_s[index] - times_s[index - 1]
        for surface in SURFACE_PREFIXES:
            power_start_w = (
                fluxes[surface][index - 1]
                * areas_by_index[index - 1][surface]
            )
            power_end_w = (
                fluxes[surface][index]
                * areas_by_index[index][surface]
            )
            cumulative_kj[surface] += (
                0.5 * (power_start_w + power_end_w) * dt_s / 1000.0
            )
        rounded_time = int(round(times_s[index]))
        if rounded_time in checkpoint_set:
            upper_kj = (
                cumulative_kj["ceiling"]
                + cumulative_kj["upper_wall"]
            )
            lower_kj = (
                cumulative_kj["lower_wall"]
                + cumulative_kj["floor"]
            )
            result[rounded_time] = {
                "surface_storage_kj": cumulative_kj.copy(),
                "upper_surface_storage_kj": upper_kj,
                "lower_surface_storage_kj": lower_kj,
                "total_surface_storage_kj": upper_kj + lower_kj,
                "surface_temp_c": {
                    surface: temperatures[surface][index]
                    for surface in SURFACE_PREFIXES
                },
                "surface_area_m2": areas_by_index[index].copy(),
            }
    missing = checkpoint_set - result.keys()
    if missing:
        raise ValueError(f"CFAST wall checkpoints absent: {sorted(missing)}")
    return result


def build_audit(
    *,
    base_sim_csv: Path,
    material_sim_csv: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    cfast_walls_path: Path,
    room_id: int = 0,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    checkpoint_values = tuple(checkpoints)
    base_rows = read_sim_rows(base_sim_csv)
    material_rows = read_sim_rows(material_sim_csv)
    zone_rows = f33m.read_cfast_zone(cfast_zone_path)
    compartment_rows = f33m.read_cfast_compartments(
        cfast_compartments_path
    )
    wall_rows = read_cfast_walls(cfast_walls_path)
    cfast_surfaces = estimate_cfast_surface_storage(
        wall_rows=wall_rows,
        zone_rows=zone_rows,
        compartment_rows=compartment_rows,
        room_id=room_id,
        checkpoints=checkpoint_values,
    )
    boundary_audit = f33q.build_audit(
        sim_csv_path=base_sim_csv,
        cfast_zone_path=cfast_zone_path,
        cfast_compartments_path=cfast_compartments_path,
        cfast_walls_path=cfast_walls_path,
        checkpoints=checkpoint_values,
    )
    inferred_boundary_by_checkpoint: dict[int, float] = {}
    cumulative_boundary_kj = 0.0
    for window in boundary_audit["windows"]:
        cumulative_boundary_kj += _number(
            window["cfast"].get("inferred_boundary_sink_kj")
        )
        inferred_boundary_by_checkpoint[int(window["end_s"])] = (
            cumulative_boundary_kj
        )

    result_checkpoints: dict[str, Any] = {}
    for checkpoint_s in checkpoint_values:
        cfast_room = f33m.build_cfast_checkpoint(
            checkpoint_s, zone_rows, compartment_rows
        )["rooms"][str(room_id)]
        direct_fire_radiation_kj = (
            RADIATIVE_FRACTION
            * _number(cfast_room.get("hrr_energy_kj"))
            if room_id == 0
            else 0.0
        )
        total_surface_kj = _number(
            cfast_surfaces[checkpoint_s].get("total_surface_storage_kj")
        )
        gas_driven_surface_kj = total_surface_kj - direct_fire_radiation_kj
        inferred_boundary_kj = inferred_boundary_by_checkpoint[checkpoint_s]
        result_checkpoints[str(checkpoint_s)] = {
            "cfast": {
                **cfast_surfaces[checkpoint_s],
                "direct_fire_radiation_kj": direct_fire_radiation_kj,
                "gas_driven_surface_storage_kj": gas_driven_surface_kj,
                "inferred_gas_boundary_sink_kj": inferred_boundary_kj,
                "implied_leakage_or_model_residual_kj": (
                    inferred_boundary_kj - gas_driven_surface_kj
                ),
            },
            "base": canonical_boundary_snapshot(
                base_rows, room_id, checkpoint_s
            ),
            "material": canonical_boundary_snapshot(
                material_rows, room_id, checkpoint_s
            ),
        }

    final = result_checkpoints[str(checkpoint_values[-1])]
    material = final["material"]
    cfast = final["cfast"]
    return {
        "room_id": room_id,
        "checkpoints": result_checkpoints,
        "final_partition": {
            "cfast_surface_storage_kj": cfast[
                "total_surface_storage_kj"
            ],
            "cfast_direct_fire_radiation_kj": cfast[
                "direct_fire_radiation_kj"
            ],
            "cfast_gas_driven_surface_storage_kj": cfast[
                "gas_driven_surface_storage_kj"
            ],
            "cfast_implied_leakage_or_model_residual_kj": cfast[
                "implied_leakage_or_model_residual_kj"
            ],
            "material_wall_sink_kj": material["wall_sink_kj"],
            "material_ambient_bypass_kj": material["ambient_sink_kj"],
            "material_exterior_sink_kj": material["exterior_sink_kj"],
            "material_wall_reservoir_energy_kj": material[
                "wall_reservoir_energy_kj"
            ],
            "unrepresented_wall_energy_kj": (
                cfast["total_surface_storage_kj"]
                - material["wall_reservoir_energy_kj"]
            ),
        },
        "interpretation": {
            "direct_fire_radiation_missing_from_wall_reservoir": True,
            "ambient_decay_bypasses_wall_reservoir": True,
            "full_area_patch_authorized": False,
            "next_contract": (
                "direct combustion radiation plus per-surface/zone "
                "wall reservoirs"
            ),
        },
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3r1 boundary-partition audit")
    print(
        "time  CFAST surfaces  direct fire rad  gas-driven surfaces  "
        "gas boundary  material wall/ambient/exterior"
    )
    for checkpoint_s, values in audit["checkpoints"].items():
        cfast = values["cfast"]
        material = values["material"]
        print(
            f"{checkpoint_s:>4} "
            f"{cfast['total_surface_storage_kj'] / 1000:>14.3f} "
            f"{cfast['direct_fire_radiation_kj'] / 1000:>15.3f} "
            f"{cfast['gas_driven_surface_storage_kj'] / 1000:>20.3f} "
            f"{cfast['inferred_gas_boundary_sink_kj'] / 1000:>13.3f} "
            f"{material['wall_sink_kj'] / 1000:.3f}/"
            f"{material['ambient_sink_kj'] / 1000:.3f}/"
            f"{material['exterior_sink_kj'] / 1000:.3f} MJ"
        )
    final = audit["final_partition"]
    print(
        "final missing wall storage: "
        f"{final['unrepresented_wall_energy_kj'] / 1000:.3f} MJ"
    )
    print(
        "decision: full-area patch NO-GO; next contract is direct combustion "
        "radiation plus per-surface/zone wall reservoirs"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-sim-csv",
        type=Path,
        default=Path("runs/phase3_f33r0_base/sim_log.csv"),
    )
    parser.add_argument(
        "--material-sim-csv",
        type=Path,
        default=Path("runs/phase3_f33r0_material/sim_log.csv"),
    )
    parser.add_argument(
        "--cfast-zone",
        type=Path,
        default=Path(
            "sim/validation/cfast/cfast_corridor_chain_zone.csv"
        ),
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=Path(
            "sim/validation/cfast/cfast_corridor_chain_compartments.csv"
        ),
    )
    parser.add_argument(
        "--cfast-walls",
        type=Path,
        default=Path(
            "sim/validation/cfast/cfast_corridor_chain_walls.csv"
        ),
    )
    parser.add_argument("--room-id", type=int, default=0)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    audit = build_audit(
        base_sim_csv=args.base_sim_csv,
        material_sim_csv=args.material_sim_csv,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
        cfast_walls_path=args.cfast_walls,
        room_id=args.room_id,
    )
    _print_audit(audit)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"json={args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
