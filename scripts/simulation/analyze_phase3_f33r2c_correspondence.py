#!/usr/bin/env python3
"""Evaluate the staged F3.3r2c multi-surface correspondence STOP gate."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import analyze_phase3_f33r1_boundary_partition as f33r1


CHECKPOINTS = (60, 120, 180)
CFAST_DIR = ROOT / "sim" / "validation" / "cfast"
SURFACES = ("ceiling", "upper_wall", "lower_wall", "floor")
ENERGY_RESIDUAL_TOLERANCE_KJ = 1.0e-4

# Valid F3.3p1 180 s state errors versus CFAST. F3.3r2c may not worsen them.
P1_R0_MAX_ERRORS = {
    "upper_mass_kg": abs(25.484 - 26.943),
    "lower_mass_kg": abs(14.673 - 15.406),
    "interface_m": abs(0.681 - 0.736),
}


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"empty CSV: {path}")
    return rows


def row_at(
    rows: Iterable[dict[str, str]], room_id: int, checkpoint_s: float
) -> dict[str, str]:
    selected = [
        row for row in rows if int(_number(row.get("room_id"))) == room_id
    ]
    if not selected:
        raise ValueError(f"room {room_id} missing from SimuFire CSV")
    row = min(
        selected,
        key=lambda candidate: abs(
            _number(candidate.get("time_s")) - checkpoint_s
        ),
    )
    if abs(_number(row.get("time_s")) - checkpoint_s) > 0.11:
        raise ValueError(
            f"checkpoint {checkpoint_s:g}s missing for room {room_id}"
        )
    return row


def sim_snapshot(
    rows: list[dict[str, str]], room_id: int, checkpoint_s: int
) -> dict[str, Any]:
    row = row_at(rows, room_id, checkpoint_s)
    surfaces: dict[str, Any] = {}
    for surface in SURFACES:
        prefix = f"phase3_shadow_multisurface_{surface}"
        surfaces[surface] = {
            "area_m2": _number(row.get(prefix + "_area_m2")),
            "energy_kj": _number(row.get(prefix + "_energy_kj")),
            "temp_inner_c": _number(row.get(prefix + "_temp_inner_c"), 20.0),
            "temp_middle_c": _number(row.get(prefix + "_temp_middle_c"), 20.0),
            "temp_outer_c": _number(row.get(prefix + "_temp_outer_c"), 20.0),
            "cumulative_gas_exchange_kj": _number(
                row.get(prefix + "_cumulative_gas_exchange_kj")
            ),
            "cumulative_fire_radiation_kj": _number(
                row.get(prefix + "_cumulative_fire_radiation_kj")
            ),
            "cumulative_exterior_removed_kj": _number(
                row.get(prefix + "_cumulative_exterior_removed_kj")
            ),
        }
    surface_storage_kj = _number(
        row.get("phase3_shadow_multisurface_energy_post_kj")
    )
    fire_radiation_kj = _number(
        row.get(
            "phase3_shadow_multisurface_cumulative_fire_radiation_kj"
        )
    )
    return {
        "time_s": _number(row.get("time_s")),
        "upper_temp_c": _number(
            row.get("phase3_shadow_thermo_temp_upper_c"), 20.0
        ),
        "lower_temp_c": _number(
            row.get("phase3_shadow_thermo_temp_lower_c"), 20.0
        ),
        "interface_m": _number(row.get("phase3_shadow_thermo_interface_m")),
        "upper_mass_kg": _number(row.get("phase3_shadow_upper_gas_kg")),
        "lower_mass_kg": _number(row.get("phase3_shadow_lower_gas_kg")),
        "surface_storage_kj": surface_storage_kj,
        "fire_radiation_kj": fire_radiation_kj,
        "gas_driven_surface_storage_kj": (
            surface_storage_kj - fire_radiation_kj
        ),
        "cumulative_gas_exchange_kj": _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_gas_exchange_kj"
            )
        ),
        "cumulative_exterior_removed_kj": _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_exterior_removed_kj"
            )
        ),
        "cumulative_energy_residual_kj": _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_energy_residual_kj"
            )
        ),
        "boundary_metadata_complete": _number(
            row.get(
                "phase3_shadow_multisurface_boundary_metadata_complete_flag"
            )
        ),
        "unsupported_inter_room_count": _number(
            row.get(
                "phase3_shadow_multisurface_unsupported_inter_room_count"
            )
        ),
        "surfaces": surfaces,
    }


def _relative_error(actual: float, expected: float) -> float:
    return abs(actual - expected) / max(abs(expected), 1.0e-12)


def compare_legacy_cells(
    off_rows: list[dict[str, str]], on_rows: list[dict[str, str]]
) -> dict[str, Any]:
    off_by_key = {
        (_number(row.get("time_s")), int(_number(row.get("room_id")))): row
        for row in off_rows
    }
    on_by_key = {
        (_number(row.get("time_s")), int(_number(row.get("room_id")))): row
        for row in on_rows
    }
    shared_keys = sorted(off_by_key.keys() & on_by_key.keys())
    if len(shared_keys) != len(off_by_key) or len(shared_keys) != len(on_by_key):
        return {
            "same_rows": False,
            "compared_cells": 0,
            "different_cells": -1,
            "examples": [],
        }
    shared_fields = sorted(
        set(off_rows[0]) & set(on_rows[0])
        - {
            field
            for field in set(off_rows[0]) | set(on_rows[0])
            if field.startswith("phase3_shadow_")
        }
    )
    differences: list[dict[str, Any]] = []
    difference_count = 0
    compared = 0
    for key in shared_keys:
        off = off_by_key[key]
        on = on_by_key[key]
        for field in shared_fields:
            compared += 1
            off_value = off.get(field, "")
            on_value = on.get(field, "")
            try:
                equal = math.isclose(
                    float(off_value),
                    float(on_value),
                    rel_tol=0.0,
                    abs_tol=1.0e-9,
                )
            except ValueError:
                equal = off_value == on_value
            if not equal:
                difference_count += 1
                if len(differences) < 20:
                    differences.append(
                        {
                            "time_s": key[0],
                            "room_id": key[1],
                            "field": field,
                            "off": off_value,
                            "on": on_value,
                        }
                    )
    return {
        "same_rows": True,
        "shared_legacy_fields": len(shared_fields),
        "compared_cells": compared,
        "different_cells": difference_count,
        "examples": differences,
    }


def _gate(
    name: str, actual: float, expected: float, maximum_error: float
) -> dict[str, Any]:
    error = abs(actual - expected)
    return {
        "name": name,
        "actual": actual,
        "expected": expected,
        "absolute_error": error,
        "maximum_error": maximum_error,
        "pass": error <= maximum_error,
    }


def build_audit(
    *,
    off_csv: Path,
    candidate_csv: Path,
    physical_csv: Path | None = None,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    checkpoint_values = tuple(checkpoints)
    off_rows = read_rows(off_csv)
    candidate_rows = read_rows(candidate_csv)
    physical_rows = read_rows(physical_csv) if physical_csv else None
    zone_rows = f33m.read_cfast_zone(
        CFAST_DIR / "cfast_corridor_chain_zone.csv"
    )
    compartment_rows = f33m.read_cfast_compartments(
        CFAST_DIR / "cfast_corridor_chain_compartments.csv"
    )
    wall_rows = f33r1.read_cfast_walls(
        CFAST_DIR / "cfast_corridor_chain_walls.csv"
    )
    cfast_surfaces = f33r1.estimate_cfast_surface_storage(
        wall_rows=wall_rows,
        zone_rows=zone_rows,
        compartment_rows=compartment_rows,
        room_id=0,
        checkpoints=checkpoint_values,
    )

    snapshots: dict[str, Any] = {}
    for checkpoint in checkpoint_values:
        cfast = f33m.build_cfast_checkpoint(
            checkpoint, zone_rows, compartment_rows
        )
        cfast_r0 = cfast["rooms"]["0"]
        direct_fire_radiation_kj = (
            f33r1.RADIATIVE_FRACTION
            * _number(cfast_r0.get("hrr_energy_kj"))
        )
        total_surface_kj = _number(
            cfast_surfaces[checkpoint].get("total_surface_storage_kj")
        )
        snapshots[str(checkpoint)] = {
            "cfast": {
                "rooms": cfast["rooms"],
                "surface_storage_kj": total_surface_kj,
                "fire_radiation_kj": direct_fire_radiation_kj,
                "gas_driven_surface_storage_kj": (
                    total_surface_kj - direct_fire_radiation_kj
                ),
                "surfaces": cfast_surfaces[checkpoint],
            },
            "off": {
                str(room_id): sim_snapshot(
                    off_rows, room_id, checkpoint
                )
                for room_id in (0, 1, 2)
            },
            "candidate": {
                str(room_id): sim_snapshot(
                    candidate_rows, room_id, checkpoint
                )
                for room_id in (0, 1, 2)
            },
        }
        if physical_rows is not None:
            snapshots[str(checkpoint)]["physical"] = {
                str(room_id): sim_snapshot(
                    physical_rows, room_id, checkpoint
                )
                for room_id in (0, 1, 2)
            }

    final = snapshots[str(checkpoint_values[-1])]
    cfast = final["cfast"]
    candidate = final["candidate"]
    cfast_rooms = cfast["rooms"]
    r0 = candidate["0"]
    gates = [
        _gate(
            "R0 total surface storage",
            r0["surface_storage_kj"],
            cfast["surface_storage_kj"],
            0.15 * cfast["surface_storage_kj"],
        ),
        _gate(
            "R0 gas-driven surface storage",
            r0["gas_driven_surface_storage_kj"],
            cfast["gas_driven_surface_storage_kj"],
            0.10 * cfast["gas_driven_surface_storage_kj"],
        ),
        _gate(
            "R0 accepted fire radiation",
            r0["fire_radiation_kj"],
            cfast["fire_radiation_kj"],
            0.02 * cfast["fire_radiation_kj"],
        ),
        _gate(
            "cumulative multi-surface energy residual",
            r0["cumulative_energy_residual_kj"],
            0.0,
            ENERGY_RESIDUAL_TOLERANCE_KJ,
        ),
    ]
    temperature_limits = {
        "0": (31.0, 10.0),
        "1": (15.0, 15.0),
        "2": (15.0, 5.0),
    }
    for room_id, (upper_limit, lower_limit) in temperature_limits.items():
        gates.append(
            _gate(
                f"R{room_id} upper temperature",
                candidate[room_id]["upper_temp_c"],
                cfast_rooms[room_id]["upper_temp_c"],
                upper_limit,
            )
        )
        gates.append(
            _gate(
                f"R{room_id} lower temperature",
                candidate[room_id]["lower_temp_c"],
                cfast_rooms[room_id]["lower_temp_c"],
                lower_limit,
            )
        )
    for field, maximum_error in P1_R0_MAX_ERRORS.items():
        gates.append(
            _gate(
                f"R0 {field} no worse than F3.3p1",
                candidate["0"][field],
                cfast_rooms["0"][field],
                maximum_error,
            )
        )

    physical_sensitivity: dict[str, float] | None = None
    if "physical" in final:
        physical_r0 = final["physical"]["0"]
        physical_sensitivity = {
            field: physical_r0[field] - r0[field]
            for field in (
                "surface_storage_kj",
                "fire_radiation_kj",
                "gas_driven_surface_storage_kj",
                "upper_temp_c",
                "lower_temp_c",
                "interface_m",
                "upper_mass_kg",
                "lower_mass_kg",
            )
        }

    return {
        "checkpoints": snapshots,
        "legacy_invariance": compare_legacy_cells(off_rows, candidate_rows),
        "final_gates": gates,
        "gate_pass_count": sum(bool(gate["pass"]) for gate in gates),
        "gate_fail_count": sum(not bool(gate["pass"]) for gate in gates),
        "decision": "GO" if all(bool(gate["pass"]) for gate in gates) else "NO-GO",
        "physical_topology_sensitivity": physical_sensitivity,
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3r2c multi-surface correspondence")
    print("time  surface MJ  fire-rad MJ  gas-driven MJ  R0 upper/lower/interface")
    for checkpoint, values in audit["checkpoints"].items():
        candidate = values["candidate"]["0"]
        print(
            f"{checkpoint:>4} "
            f"{candidate['surface_storage_kj'] / 1000:>10.3f} "
            f"{candidate['fire_radiation_kj'] / 1000:>12.3f} "
            f"{candidate['gas_driven_surface_storage_kj'] / 1000:>13.3f} "
            f"{candidate['upper_temp_c']:.2f}/"
            f"{candidate['lower_temp_c']:.2f}/"
            f"{candidate['interface_m']:.3f}"
        )
    print("\n180 s STOP gates")
    for gate in audit["final_gates"]:
        print(
            f"{'PASS' if gate['pass'] else 'FAIL'} "
            f"{gate['name']}: actual={gate['actual']:.6g}, "
            f"expected={gate['expected']:.6g}, "
            f"error={gate['absolute_error']:.6g}, "
            f"limit={gate['maximum_error']:.6g}"
        )
    legacy = audit["legacy_invariance"]
    print(
        "\nlegacy invariance: "
        f"{legacy['different_cells']} differences / "
        f"{legacy['compared_cells']} compared cells"
    )
    print(f"decision: {audit['decision']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--off-csv",
        type=Path,
        default=Path("runs/phase3_f33r2c/180_corridor_off/sim_log.csv"),
    )
    parser.add_argument(
        "--candidate-csv",
        type=Path,
        default=Path("runs/phase3_f33r2c/180_corridor_cfast/sim_log.csv"),
    )
    parser.add_argument(
        "--physical-csv",
        type=Path,
        default=Path("runs/phase3_f33r2c/180_corridor_physical/sim_log.csv"),
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    audit = build_audit(
        off_csv=args.off_csv,
        candidate_csv=args.candidate_csv,
        physical_csv=args.physical_csv,
    )
    _print_audit(audit)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0 if audit["decision"] == "GO" else 1


if __name__ == "__main__":
    raise SystemExit(main())
