#!/usr/bin/env python3
"""Attribute the F3.3v3 early R0 mass/interface error to explicit owners.

This read-only audit compares a canonical-shadow SimuFire CSV with the
committed CFAST corridor exports. It closes the total room-mass equation
without treating plume transfer or projection as net boundary flow.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import analyze_phase3_f33s_layer_mass_o2 as f33s


CFAST_DIR = ROOT / "sim" / "validation" / "cfast"
CHECKPOINTS = tuple(range(10, 181, 10))
R0_LEAK_COLUMNS = (
    "L_Room_1_Outside_1",
    "L_Room_1_Outside_2",
)
BUDGET_TOLERANCE_KG = 0.05
OWNER_ZERO_TOLERANCE_KG = 1.0e-6


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def read_cfast_vents(path: Path) -> list[dict[str, str]]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if len(lines) < 5:
        raise ValueError(f"invalid CFAST vent export: {path}")
    header = next(csv.reader([lines[0]]))
    rows = [
        dict(zip(header, values))
        for values in csv.reader(lines[4:])
        if values and values[0].strip()
    ]
    if not rows:
        raise ValueError(f"empty CFAST vent export: {path}")
    return rows


def integrate_cfast_column(
    rows: Iterable[dict[str, str]], checkpoint_s: float, column: str
) -> float:
    ordered = sorted(rows, key=lambda row: _number(row["Time"]))
    if not ordered or column not in ordered[0]:
        raise ValueError(f"CFAST vent column is missing: {column}")
    total = 0.0
    found_checkpoint = abs(_number(ordered[0]["Time"]) - checkpoint_s) <= 0.11
    for previous, current in zip(ordered, ordered[1:]):
        t0 = _number(previous["Time"])
        t1 = _number(current["Time"])
        if t0 >= checkpoint_s:
            break
        if t1 > checkpoint_s + 0.11:
            raise ValueError(
                f"checkpoint {checkpoint_s:g}s is absent from CFAST vent export"
            )
        total += (
            0.5
            * (_number(previous[column]) + _number(current[column]))
            * (t1 - t0)
        )
        if abs(t1 - checkpoint_s) <= 0.11:
            found_checkpoint = True
            break
    if not found_checkpoint:
        raise ValueError(
            f"checkpoint {checkpoint_s:g}s is absent from CFAST vent export"
        )
    return total


def read_sim_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    required = {
        "time_s",
        "room_id",
        "phase3_shadow_mass_residence_initial_upper_kg",
        "phase3_shadow_mass_residence_observed_upper_kg",
        "phase3_shadow_mass_residence_room_residual_kg",
    }
    missing = required - set(rows[0] if rows else ())
    if missing:
        raise ValueError(
            f"{path}: missing F3.3 mass-residence columns: {sorted(missing)}"
        )
    return rows


def sim_row_at(
    rows: Iterable[dict[str, str]], room_id: int, checkpoint_s: float
) -> dict[str, str]:
    candidates = [
        row for row in rows if int(_number(row.get("room_id"))) == room_id
    ]
    if not candidates:
        raise ValueError(f"SimuFire room {room_id} is absent")
    row = min(
        candidates,
        key=lambda candidate: abs(_number(candidate["time_s"]) - checkpoint_s),
    )
    if abs(_number(row["time_s"]) - checkpoint_s) > 0.11:
        raise ValueError(f"SimuFire checkpoint {checkpoint_s:g}s is absent")
    return row


def _room_mass(room: dict[str, Any]) -> float:
    return _number(room.get("upper_mass_kg")) + _number(
        room.get("lower_mass_kg")
    )


def attribute_checkpoint(
    *,
    checkpoint_s: int,
    sim_row: dict[str, str],
    cfast_initial_room: dict[str, Any],
    cfast_checkpoint: dict[str, Any],
    cfast_compartment_rows: list[dict[str, str]],
    cfast_vent_rows: list[dict[str, str]],
) -> dict[str, Any]:
    owners = f33s.residence_owners(sim_row)
    cfast_room = cfast_checkpoint["rooms"]["0"]

    sim_initial = _number(
        sim_row.get("phase3_shadow_mass_residence_initial_upper_kg")
    ) + _number(
        sim_row.get("phase3_shadow_mass_residence_initial_lower_kg")
    )
    sim_upper = _number(
        sim_row.get("phase3_shadow_mass_residence_observed_upper_kg")
    )
    sim_lower = _number(
        sim_row.get("phase3_shadow_mass_residence_observed_lower_kg")
    )
    sim_final = sim_upper + sim_lower
    cfast_initial = _room_mass(cfast_initial_room)
    cfast_final = _room_mass(cfast_room)

    cfast_pyrolysis = f33m.integrate_scalar(
        cfast_compartment_rows, checkpoint_s, "PYROL_1"
    )
    cfast_door_out = _number(
        cfast_checkpoint["routes"]["0->1"].get("mass_kg")
    )
    cfast_door_in = _number(
        cfast_checkpoint["routes"]["1->0"].get("mass_kg")
    )
    cfast_door_net_out = cfast_door_out - cfast_door_in
    cfast_exterior_net_out = sum(
        integrate_cfast_column(cfast_vent_rows, checkpoint_s, column)
        for column in R0_LEAK_COLUMNS
    )

    sim_combustion_source = owners["combustion"]["room_kg"]
    sim_door_net_out = -(
        owners["interior_opening"]["room_kg"]
        + owners["interior_pressure"]["room_kg"]
    )
    sim_exterior_net_out = -(
        owners["exterior"]["room_kg"]
        + owners["exterior_counterflow"]["room_kg"]
    )

    initial_mass_bias = sim_initial - cfast_initial
    combustion_source_bias = sim_combustion_source - cfast_pyrolysis
    doorway_outflow_deficit = cfast_door_net_out - sim_door_net_out
    exterior_outflow_deficit = (
        cfast_exterior_net_out - sim_exterior_net_out
    )
    predicted_total_error = (
        initial_mass_bias
        + combustion_source_bias
        + doorway_outflow_deficit
        + exterior_outflow_deficit
    )
    observed_total_error = sim_final - cfast_final

    cfast_budget_prediction = (
        cfast_initial
        + cfast_pyrolysis
        - cfast_door_net_out
        - cfast_exterior_net_out
    )
    sim_budget_prediction = (
        sim_initial
        + sim_combustion_source
        - sim_door_net_out
        - sim_exterior_net_out
    )
    projection_net = sum(
        owners[family]["room_kg"] for family in f33s.PROJECTION_FAMILIES
    )
    cfast_plume = f33m.integrate_scalar(
        cfast_compartment_rows, checkpoint_s, "PLUM_1"
    )
    sim_plume = owners["plume"]["upper_kg"]
    residence_residual = max(
        abs(
            _number(
                sim_row.get("phase3_shadow_mass_residence_upper_residual_kg")
            )
        ),
        abs(
            _number(
                sim_row.get("phase3_shadow_mass_residence_lower_residual_kg")
            )
        ),
        abs(
            _number(
                sim_row.get("phase3_shadow_mass_residence_room_residual_kg")
            )
        ),
    )

    return {
        "checkpoint_s": checkpoint_s,
        "sim_upper_mass_kg": sim_upper,
        "cfast_upper_mass_kg": _number(cfast_room.get("upper_mass_kg")),
        "upper_mass_error_kg": sim_upper
        - _number(cfast_room.get("upper_mass_kg")),
        "sim_lower_mass_kg": sim_lower,
        "cfast_lower_mass_kg": _number(cfast_room.get("lower_mass_kg")),
        "lower_mass_error_kg": sim_lower
        - _number(cfast_room.get("lower_mass_kg")),
        "sim_total_mass_kg": sim_final,
        "cfast_total_mass_kg": cfast_final,
        "observed_total_mass_error_kg": observed_total_error,
        "predicted_total_mass_error_kg": predicted_total_error,
        "decomposition_residual_kg": (
            observed_total_error - predicted_total_error
        ),
        "initial_mass_bias_kg": initial_mass_bias,
        "combustion_gas_source_bias_kg": combustion_source_bias,
        "doorway_net_outflow_deficit_kg": doorway_outflow_deficit,
        "exterior_net_outflow_deficit_kg": exterior_outflow_deficit,
        "sim_combustion_gas_source_kg": sim_combustion_source,
        "cfast_pyrolysis_gas_source_kg": cfast_pyrolysis,
        "sim_doorway_net_out_kg": sim_door_net_out,
        "cfast_doorway_net_out_kg": cfast_door_net_out,
        "sim_exterior_net_out_kg": sim_exterior_net_out,
        "cfast_exterior_net_out_kg": cfast_exterior_net_out,
        "sim_plume_transfer_kg": sim_plume,
        "cfast_plume_transfer_kg": cfast_plume,
        "plume_transfer_error_kg": sim_plume - cfast_plume,
        "projection_net_mass_kg": projection_net,
        "residence_ledger_max_residual_kg": residence_residual,
        "sim_budget_residual_kg": sim_final - sim_budget_prediction,
        "cfast_budget_residual_kg": cfast_final - cfast_budget_prediction,
    }


def build_audit(
    *,
    candidate_csv: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    cfast_vents_path: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    sim_rows = read_sim_rows(candidate_csv)
    cfast_zone_rows = f33m.read_cfast_zone(cfast_zone_path)
    cfast_compartment_rows = f33m.read_cfast_compartments(
        cfast_compartments_path
    )
    cfast_vent_rows = read_cfast_vents(cfast_vents_path)
    cfast_initial = f33m.build_cfast_checkpoint(
        0, cfast_zone_rows, cfast_compartment_rows
    )["rooms"]["0"]

    snapshots: dict[str, Any] = {}
    for checkpoint in checkpoints:
        snapshots[str(checkpoint)] = attribute_checkpoint(
            checkpoint_s=checkpoint,
            sim_row=sim_row_at(sim_rows, 0, checkpoint),
            cfast_initial_room=cfast_initial,
            cfast_checkpoint=f33m.build_cfast_checkpoint(
                checkpoint, cfast_zone_rows, cfast_compartment_rows
            ),
            cfast_compartment_rows=cfast_compartment_rows,
            cfast_vent_rows=cfast_vent_rows,
        )

    final_key = str(max(int(value) for value in snapshots))
    final = snapshots[final_key]
    decomposition_closes = abs(
        final["decomposition_residual_kg"]
    ) <= BUDGET_TOLERANCE_KG
    ledgers_close = max(
        abs(final["sim_budget_residual_kg"]),
        abs(final["cfast_budget_residual_kg"]),
        abs(final["residence_ledger_max_residual_kg"]),
    ) <= BUDGET_TOLERANCE_KG
    projection_is_quiet = abs(
        final["projection_net_mass_kg"]
    ) <= OWNER_ZERO_TOLERANCE_KG
    plume_is_internal = final["sim_plume_transfer_kg"] > 0.0 and abs(
        f33s.residence_owners(sim_row_at(sim_rows, 0, int(final_key)))[
            "plume"
        ]["room_kg"]
    ) <= OWNER_ZERO_TOLERANCE_KG
    positive_boundary_terms = {
        "exterior_boundary_net_outflow": final[
            "exterior_net_outflow_deficit_kg"
        ],
        "interior_doorway_net_outflow": final[
            "doorway_net_outflow_deficit_kg"
        ],
        "initial_state": final["initial_mass_bias_kg"],
    }
    primary_owner = max(
        positive_boundary_terms,
        key=lambda name: positive_boundary_terms[name],
    )
    return {
        "candidate_csv": str(candidate_csv),
        "checkpoints": snapshots,
        "thresholds": {
            "budget_tolerance_kg": BUDGET_TOLERANCE_KG,
            "owner_zero_tolerance_kg": OWNER_ZERO_TOLERANCE_KG,
        },
        "verdict": {
            "mass_decomposition_closes": decomposition_closes,
            "source_ledgers_close": ledgers_close,
            "projection_is_primary": not projection_is_quiet,
            "plume_is_net_mass_owner": not plume_is_internal,
            "primary_positive_mass_error_owner": primary_owner,
            "combustion_gas_source_missing": final[
                "combustion_gas_source_bias_kg"
            ]
            < -BUDGET_TOLERANCE_KG,
            "interface_partition_resolved": False,
            "next_experiment": (
                "audit exterior leakage topology and per-zone outflow before "
                "changing plume, HRR, projection, or a global flow gain"
            ),
        },
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3v3b R0 mass/interface attribution")
    print(
        "time  dMtotal  predicted  residual  exterior  doorway  "
        "comb-src  plume-delta"
    )
    for checkpoint, snapshot in audit["checkpoints"].items():
        print(
            f"{checkpoint:>4} "
            f"{snapshot['observed_total_mass_error_kg']:>8.3f} "
            f"{snapshot['predicted_total_mass_error_kg']:>9.3f} "
            f"{snapshot['decomposition_residual_kg']:>8.3f} "
            f"{snapshot['exterior_net_outflow_deficit_kg']:>8.3f} "
            f"{snapshot['doorway_net_outflow_deficit_kg']:>7.3f} "
            f"{snapshot['combustion_gas_source_bias_kg']:>8.3f} "
            f"{snapshot['plume_transfer_error_kg']:>11.3f}"
        )
    verdict = audit["verdict"]
    print("\nprimary owner:", verdict["primary_positive_mass_error_owner"])
    print("mass decomposition closes:", verdict["mass_decomposition_closes"])
    print("projection is primary:", verdict["projection_is_primary"])
    print("plume is net mass owner:", verdict["plume_is_net_mass_owner"])
    print("next experiment:", verdict["next_experiment"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--candidate-csv",
        type=Path,
        default=Path("runs/phase3_f33v3a/180_on/sim_log.csv"),
    )
    parser.add_argument(
        "--cfast-zone",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_zone.csv",
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_compartments.csv",
    )
    parser.add_argument(
        "--cfast-vents",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_vents.csv",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    audit = build_audit(
        candidate_csv=args.candidate_csv,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
        cfast_vents_path=args.cfast_vents,
    )
    _print_audit(audit)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    verdict = audit["verdict"]
    return (
        0
        if verdict["mass_decomposition_closes"]
        and verdict["source_ledgers_close"]
        and not verdict["projection_is_primary"]
        and not verdict["plume_is_net_mass_owner"]
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
