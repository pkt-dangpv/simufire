#!/usr/bin/env python3
"""Audit Phase 3 F3.3q boundary-energy correspondence.

The audit compares the canonical shadow from the valid F3.3p1 180 s run with
the committed CFAST corridor-chain exports. It is read-only and never changes
simulation state, cases, reports or validation baselines.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any, Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.simulation import (
    analyze_phase3_f33m_source_correspondence as f33m,
)


CHECKPOINTS = (60, 120, 180)
BOUNDARY_FAMILIES = (
    "wall",
    "ambient",
    "exterior",
    "exterior_counterflow",
)
DOORWAY_FAMILIES = ("interior_opening", "interior_pressure")
INTERNAL_FAMILIES = (
    "plume",
    "interzone",
    "parcel",
    "legacy",
    "zone_collapse",
    "other",
)

R0_WIDTH_M = 5.0
R0_LENGTH_M = 4.0
R0_HEIGHT_M = 2.4


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def _read_sim_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def _read_cfast_walls(path: Path) -> list[dict[str, str]]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    header = next(csv.reader([lines[0]]))
    return [
        dict(zip(header, values))
        for values in csv.reader(lines[4:])
        if values and values[0].strip()
    ]


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


def _row_at(
    rows: Iterable[dict[str, str]], checkpoint_s: float
) -> dict[str, str]:
    candidates = list(rows)
    if not candidates:
        raise ValueError("empty time series")
    return min(
        candidates,
        key=lambda row: abs(_number(row.get("Time")) - checkpoint_s),
    )


def _family_net_kj(row: dict[str, str], family: str) -> float:
    prefix = f"phase3_shadow_enthalpy_{family}_"
    return (
        _number(row.get(prefix + "upper_in_kj_total"))
        + _number(row.get(prefix + "lower_in_kj_total"))
        - _number(row.get(prefix + "upper_out_kj_total"))
        - _number(row.get(prefix + "lower_out_kj_total"))
    )


def _sim_checkpoint(
    rows: list[dict[str, str]], checkpoint_s: int
) -> dict[str, Any]:
    row = _sim_row_at(rows, 0, checkpoint_s)
    families = {
        family: _family_net_kj(row, family)
        for family in (
            "combustion",
            *DOORWAY_FAMILIES,
            *BOUNDARY_FAMILIES,
            *INTERNAL_FAMILIES,
        )
    }
    upper_mass_kg = _number(row.get("phase3_shadow_upper_gas_kg"))
    lower_mass_kg = _number(row.get("phase3_shadow_lower_gas_kg"))
    upper_energy_kj = _number(row.get("phase3_shadow_upper_energy_kj"))
    lower_energy_kj = _number(row.get("phase3_shadow_lower_energy_kj"))
    return {
        "time_s": _number(row.get("time_s")),
        "stored_energy_kj": upper_energy_kj + lower_energy_kj,
        "upper_mass_kg": upper_mass_kg,
        "lower_mass_kg": lower_mass_kg,
        "upper_temp_c": f33m._canonical_temp(
            upper_mass_kg, upper_energy_kj
        ),
        "lower_temp_c": f33m._canonical_temp(
            lower_mass_kg, lower_energy_kj
        ),
        "wall_temp_c": _number(
            row.get("phase3_shadow_wall_temp_post_c"), 20.0
        ),
        "wall_energy_kj": _number(
            row.get("phase3_shadow_wall_energy_post_kj")
        ),
        "families_net_kj": families,
    }


def _cfast_checkpoint(
    checkpoint_s: int,
    zone_rows: list[dict[str, str]],
    compartment_rows: list[dict[str, str]],
    wall_rows: list[dict[str, str]],
) -> dict[str, Any]:
    checkpoint = f33m.build_cfast_checkpoint(
        checkpoint_s, zone_rows, compartment_rows
    )
    wall = _row_at(wall_rows, checkpoint_s)
    checkpoint["r0"]["surface_temp_c"] = {
        "ceiling": _number(wall.get("CEILT_1")),
        "upper_wall": _number(wall.get("UWALLT_1")),
        "lower_wall": _number(wall.get("LWALLT_1")),
        "floor": _number(wall.get("FLOORT_1")),
    }
    return checkpoint


def _delta(current: float, previous: float) -> float:
    return current - previous


def build_window(
    *,
    start_s: int,
    end_s: int,
    sim_current: dict[str, Any],
    sim_previous: dict[str, Any] | None,
    cfast_current: dict[str, Any],
    cfast_previous: dict[str, Any] | None,
) -> dict[str, Any]:
    sim_previous = sim_previous or {
        "stored_energy_kj": 0.0,
        "families_net_kj": {},
    }
    cfast_previous = cfast_previous or {
        "r0": {
            "sensible_energy_kj": 0.0,
            "convective_energy_kj": 0.0,
        },
        "routes": {
            "0->1": {"enthalpy_kj": 0.0},
            "1->0": {"enthalpy_kj": 0.0},
        },
    }

    cfast_source_kj = _delta(
        _number(cfast_current["r0"].get("convective_energy_kj")),
        _number(cfast_previous["r0"].get("convective_energy_kj")),
    )
    cfast_out_kj = _delta(
        _number(cfast_current["routes"]["0->1"].get("enthalpy_kj")),
        _number(cfast_previous["routes"]["0->1"].get("enthalpy_kj")),
    )
    cfast_in_kj = _delta(
        _number(cfast_current["routes"]["1->0"].get("enthalpy_kj")),
        _number(cfast_previous["routes"]["1->0"].get("enthalpy_kj")),
    )
    cfast_doorway_net_kj = cfast_in_kj - cfast_out_kj
    cfast_storage_delta_kj = _delta(
        _number(cfast_current["r0"].get("sensible_energy_kj")),
        _number(cfast_previous["r0"].get("sensible_energy_kj")),
    )
    cfast_inferred_boundary_sink_kj = (
        cfast_source_kj
        + cfast_doorway_net_kj
        - cfast_storage_delta_kj
    )

    sim_current_families = sim_current["families_net_kj"]
    sim_previous_families = sim_previous["families_net_kj"]

    def sim_family_delta(family: str) -> float:
        return _delta(
            _number(sim_current_families.get(family)),
            _number(sim_previous_families.get(family)),
        )

    sim_source_kj = sim_family_delta("combustion")
    sim_doorway_net_kj = sum(
        sim_family_delta(family) for family in DOORWAY_FAMILIES
    )
    sim_storage_delta_kj = _delta(
        _number(sim_current.get("stored_energy_kj")),
        _number(sim_previous.get("stored_energy_kj")),
    )
    sim_inferred_boundary_sink_kj = (
        sim_source_kj + sim_doorway_net_kj - sim_storage_delta_kj
    )
    sim_boundary_components_kj = {
        family: -sim_family_delta(family)
        for family in BOUNDARY_FAMILIES
    }
    sim_observed_boundary_sink_kj = sum(
        sim_boundary_components_kj.values()
    )
    sim_internal_net_kj = sum(
        sim_family_delta(family) for family in INTERNAL_FAMILIES
    )

    return {
        "start_s": start_s,
        "end_s": end_s,
        "cfast": {
            "source_kj": cfast_source_kj,
            "doorway_in_kj": cfast_in_kj,
            "doorway_out_kj": cfast_out_kj,
            "doorway_net_kj": cfast_doorway_net_kj,
            "storage_delta_kj": cfast_storage_delta_kj,
            "inferred_boundary_sink_kj": cfast_inferred_boundary_sink_kj,
        },
        "sim": {
            "source_kj": sim_source_kj,
            "doorway_net_kj": sim_doorway_net_kj,
            "storage_delta_kj": sim_storage_delta_kj,
            "inferred_boundary_sink_kj": sim_inferred_boundary_sink_kj,
            "observed_boundary_sink_kj": sim_observed_boundary_sink_kj,
            "boundary_components_kj": sim_boundary_components_kj,
            "internal_net_kj": sim_internal_net_kj,
            "boundary_closure_residual_kj": (
                sim_inferred_boundary_sink_kj
                - sim_observed_boundary_sink_kj
            ),
        },
        "boundary_sink_shortfall_kj": (
            cfast_inferred_boundary_sink_kj
            - sim_observed_boundary_sink_kj
        ),
    }


def build_audit(
    *,
    sim_csv_path: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    cfast_walls_path: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    sim_rows = _read_sim_rows(sim_csv_path)
    zone_rows = f33m.read_cfast_zone(cfast_zone_path)
    compartment_rows = f33m.read_cfast_compartments(
        cfast_compartments_path
    )
    wall_rows = _read_cfast_walls(cfast_walls_path)

    checkpoint_values = tuple(checkpoints)
    sim_checkpoints: dict[int, dict[str, Any]] = {}
    cfast_checkpoints: dict[int, dict[str, Any]] = {}
    windows: list[dict[str, Any]] = []
    previous_checkpoint: int | None = None

    for checkpoint_s in checkpoint_values:
        sim_checkpoints[checkpoint_s] = _sim_checkpoint(
            sim_rows, checkpoint_s
        )
        cfast_checkpoints[checkpoint_s] = _cfast_checkpoint(
            checkpoint_s,
            zone_rows,
            compartment_rows,
            wall_rows,
        )
        windows.append(
            build_window(
                start_s=previous_checkpoint or 0,
                end_s=checkpoint_s,
                sim_current=sim_checkpoints[checkpoint_s],
                sim_previous=(
                    sim_checkpoints[previous_checkpoint]
                    if previous_checkpoint is not None
                    else None
                ),
                cfast_current=cfast_checkpoints[checkpoint_s],
                cfast_previous=(
                    cfast_checkpoints[previous_checkpoint]
                    if previous_checkpoint is not None
                    else None
                ),
            )
        )
        previous_checkpoint = checkpoint_s

    floor_area_m2 = R0_WIDTH_M * R0_LENGTH_M
    enclosure_area_m2 = (
        2.0 * floor_area_m2
        + 2.0 * (R0_WIDTH_M + R0_LENGTH_M) * R0_HEIGHT_M
    )
    canonical_wall_area_m2 = 2.0 * floor_area_m2

    return {
        "sim_csv": str(sim_csv_path),
        "checkpoints": {
            str(checkpoint): {
                "sim": sim_checkpoints[checkpoint],
                "cfast": cfast_checkpoints[checkpoint]["r0"],
            }
            for checkpoint in checkpoint_values
        },
        "windows": windows,
        "cumulative_0_180": {
            "cfast_boundary_sink_kj": sum(
                window["cfast"]["inferred_boundary_sink_kj"]
                for window in windows
            ),
            "sim_boundary_sink_kj": sum(
                window["sim"]["observed_boundary_sink_kj"]
                for window in windows
            ),
            "shortfall_kj": sum(
                window["boundary_sink_shortfall_kj"]
                for window in windows
            ),
        },
        "surface_contract": {
            "r0_floor_area_m2": floor_area_m2,
            "r0_enclosure_area_m2": enclosure_area_m2,
            "canonical_wall_area_m2": canonical_wall_area_m2,
            "canonical_to_enclosure_area_ratio": (
                canonical_wall_area_m2 / enclosure_area_m2
            ),
            "sim_material_mode": "lumped fallback",
            "cfast_material_mode": "concrete, four surface classes",
        },
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3q boundary-energy correspondence")
    print(
        "window   CFAST sink   Sim sink   shortfall   "
        "Sim wall/ambient/exterior"
    )
    for window in audit["windows"]:
        components = window["sim"]["boundary_components_kj"]
        print(
            f"{window['start_s']:>3}-{window['end_s']:<3} "
            f"{window['cfast']['inferred_boundary_sink_kj'] / 1000:>10.3f} "
            f"{window['sim']['observed_boundary_sink_kj'] / 1000:>10.3f} "
            f"{window['boundary_sink_shortfall_kj'] / 1000:>10.3f} "
            f"{components['wall'] / 1000:>7.3f}/"
            f"{components['ambient'] / 1000:.3f}/"
            f"{(components['exterior'] + components['exterior_counterflow']) / 1000:.3f} MJ"
        )
    cumulative = audit["cumulative_0_180"]
    print(
        "0-180 cumulative: "
        f"CFAST={cumulative['cfast_boundary_sink_kj'] / 1000:.3f} MJ "
        f"Sim={cumulative['sim_boundary_sink_kj'] / 1000:.3f} MJ "
        f"shortfall={cumulative['shortfall_kj'] / 1000:.3f} MJ"
    )
    surface = audit["surface_contract"]
    print(
        "surface contract: "
        f"canonical={surface['canonical_wall_area_m2']:.1f} m2 "
        f"enclosure={surface['r0_enclosure_area_m2']:.1f} m2 "
        f"ratio={surface['canonical_to_enclosure_area_ratio']:.3f}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sim-csv",
        type=Path,
        default=Path("runs/phase3_f33p1_180_on_v2/sim_log.csv"),
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
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    audit = build_audit(
        sim_csv_path=args.sim_csv,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
        cfast_walls_path=args.cfast_walls,
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
