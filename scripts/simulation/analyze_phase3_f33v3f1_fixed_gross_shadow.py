#!/usr/bin/env python3
"""Audit the F3.3v3f1 fixed-gross pressure-skew shadow preview."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m


DEFAULT_RUN_ROOT = ROOT / "runs" / "phase3_f33v3f1"
DEFAULT_CFAST = ROOT / "sim" / "validation" / "cfast"
PREFIX = "phase3_shadow_fixed_gross_"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def compare_shared_columns(
    off_rows: list[dict[str, str]], on_rows: list[dict[str, str]]
) -> dict[str, Any]:
    if not off_rows or not on_rows:
        raise ValueError("OFF and ON CSVs must contain rows")
    shared = [field for field in off_rows[0] if field in on_rows[0]]
    differences = 0
    first_difference: dict[str, Any] | None = None
    if len(off_rows) != len(on_rows):
        differences += abs(len(off_rows) - len(on_rows))
    for index, (off, on) in enumerate(zip(off_rows, on_rows)):
        for field in shared:
            if off[field] == on[field]:
                continue
            differences += 1
            if first_difference is None:
                first_difference = {
                    "row": index,
                    "field": field,
                    "off": off[field],
                    "on": on[field],
                }
    return {
        "off_rows": len(off_rows),
        "on_rows": len(on_rows),
        "shared_columns": len(shared),
        "new_columns": [field for field in on_rows[0] if field not in off_rows[0]],
        "shared_value_difference_count": differences,
        "first_difference": first_difference,
    }


def final_room_row(
    rows: list[dict[str, str]], room_id: int, checkpoint_s: float
) -> dict[str, str]:
    candidates = [
        row
        for row in rows
        if int(float(row["room_id"])) == room_id
        and abs(float(row["time_s"]) - checkpoint_s) <= 0.11
    ]
    if not candidates:
        raise ValueError(f"room {room_id} checkpoint {checkpoint_s:g}s absent")
    return candidates[-1]


def build_audit(
    *,
    off_csv: Path,
    on_csv: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    checkpoint_s: int = 180,
) -> dict[str, Any]:
    off_rows = read_csv(off_csv)
    on_rows = read_csv(on_csv)
    invariance = compare_shared_columns(off_rows, on_rows)
    room = final_room_row(on_rows, 0, checkpoint_s)
    cfast = f33m.build_cfast_checkpoint(
        checkpoint_s,
        f33m.read_cfast_zone(cfast_zone_path),
        f33m.read_cfast_compartments(cfast_compartments_path),
    )
    cfast_out = cfast["routes"]["0->1"]
    cfast_in = cfast["routes"]["1->0"]
    preview_out = float(room[f"{PREFIX}preview_out_mass_kg_total"])
    preview_in = float(room[f"{PREFIX}preview_in_mass_kg_total"])
    preview_enthalpy = float(
        room[f"{PREFIX}preview_net_enthalpy_out_kj_total"]
    )
    cfast_gross = cfast_out["mass_kg"] + cfast_in["mass_kg"]
    cfast_enthalpy = cfast_out["enthalpy_kj"] - cfast_in["enthalpy_kj"]
    residual_fields = (
        "mass_residual_kg",
        "energy_residual_kj",
        "o2_residual_kg",
        "species_residual_kg",
    )
    max_residuals = {
        field: max(abs(float(row[f"{PREFIX}{field}"])) for row in on_rows)
        for field in residual_fields
    }
    correspondence = {
        "preview_out_mass_kg": preview_out,
        "preview_in_mass_kg": preview_in,
        "preview_gross_mass_kg": preview_out + preview_in,
        "preview_net_mass_out_kg": preview_out - preview_in,
        "preview_net_enthalpy_out_kj": preview_enthalpy,
        "cfast_out_mass_kg": cfast_out["mass_kg"],
        "cfast_in_mass_kg": cfast_in["mass_kg"],
        "cfast_gross_mass_kg": cfast_gross,
        "cfast_net_mass_out_kg": cfast_out["mass_kg"] - cfast_in["mass_kg"],
        "cfast_net_enthalpy_out_kj": cfast_enthalpy,
        "gross_mass_relative_error": (
            (preview_out + preview_in - cfast_gross) / cfast_gross
        ),
        "net_enthalpy_relative_error": (
            (preview_enthalpy - cfast_enthalpy) / cfast_enthalpy
        ),
        "cap_count_total_room_0": float(
            room[f"{PREFIX}cap_count_total"]
        ),
    }
    closure_ok = all(value <= 1.0e-9 for value in max_residuals.values())
    verdict = {
        "off_on_shared_values_identical": (
            invariance["shared_value_difference_count"] == 0
        ),
        "closure_ok": closure_ok,
        "gross_mass_within_3pct": (
            abs(correspondence["gross_mass_relative_error"]) <= 0.03
        ),
        "net_enthalpy_within_1pct": (
            abs(correspondence["net_enthalpy_relative_error"]) <= 0.01
        ),
        "runtime_authority_ready": False,
        "next_gate": (
            "Explain directional cap frequency and test an authoritative "
            "replacement in a separate opt-in STOP gate."
        ),
    }
    return {
        "checkpoint_s": checkpoint_s,
        "invariance": invariance,
        "max_residuals": max_residuals,
        "correspondence": correspondence,
        "verdict": verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--off-csv",
        type=Path,
        default=DEFAULT_RUN_ROOT / "180_off" / "sim_log.csv",
    )
    parser.add_argument(
        "--on-csv",
        type=Path,
        default=DEFAULT_RUN_ROOT / "180_on" / "sim_log.csv",
    )
    parser.add_argument(
        "--cfast-zone",
        type=Path,
        default=DEFAULT_CFAST / "cfast_corridor_chain_zone.csv",
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=DEFAULT_CFAST / "cfast_corridor_chain_compartments.csv",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    result = build_audit(
        off_csv=args.off_csv,
        on_csv=args.on_csv,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
    )
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(rendered + "\n", encoding="utf-8")
    return 0 if all(
        result["verdict"][key]
        for key in (
            "off_on_shared_values_identical",
            "closure_ok",
            "gross_mass_within_3pct",
            "net_enthalpy_within_1pct",
        )
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
