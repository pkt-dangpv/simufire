#!/usr/bin/env python3
"""Compare the F3.3v3f3 dynamic fixed-gross candidate with its baseline."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE = (
    ROOT / "runs" / "phase3_f33v3f2" / "180_cap_ledger" / "sim_log.csv"
)
DEFAULT_CANDIDATE = (
    ROOT / "runs" / "phase3_f33v3f3" / "180_candidate" / "sim_log.csv"
)
PREFIX = "phase3_shadow_fixed_gross_"


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def compare_live_values(
    baseline_fields: list[str],
    baseline_rows: list[dict[str, str]],
    candidate_fields: list[str],
    candidate_rows: list[dict[str, str]],
) -> dict[str, Any]:
    candidate_set = set(candidate_fields)
    live_fields = [
        field
        for field in baseline_fields
        if field in candidate_set and not field.startswith("phase3_shadow_")
    ]
    differences: list[dict[str, Any]] = []
    for row_index, (baseline, candidate) in enumerate(
        zip(baseline_rows, candidate_rows)
    ):
        for field in live_fields:
            if baseline[field] != candidate[field]:
                differences.append(
                    {
                        "row_index": row_index,
                        "field": field,
                        "baseline": baseline[field],
                        "candidate": candidate[field],
                    }
                )
    return {
        "baseline_row_count": len(baseline_rows),
        "candidate_row_count": len(candidate_rows),
        "rows_align": len(baseline_rows) == len(candidate_rows),
        "shared_live_field_count": len(live_fields),
        "live_value_difference_count": len(differences),
        "first_live_differences": differences[:10],
    }


def final_room_row(
    rows: list[dict[str, str]], room_id: int
) -> dict[str, str]:
    matching = [
        row for row in rows if int(float(row["room_id"])) == room_id
    ]
    if not matching:
        raise ValueError(f"room {room_id} is absent")
    return matching[-1]


def fixed_gross_metrics(row: dict[str, str]) -> dict[str, float]:
    fields = {
        "cap_count": "cap_count_total",
        "positive_cap_count": "cap_positive_count_total",
        "negative_cap_count": "cap_negative_count_total",
        "requested_pressure_net_out_kg": (
            "pressure_requested_net_out_kg_total"
        ),
        "accepted_pressure_net_out_kg": (
            "pressure_accepted_net_out_kg_total"
        ),
        "rejected_abs_kg": "cap_rejected_abs_kg_total",
        "preview_out_kg": "preview_out_mass_kg_total",
        "preview_in_kg": "preview_in_mass_kg_total",
        "preview_net_enthalpy_out_kj": (
            "preview_net_enthalpy_out_kj_total"
        ),
    }
    result = {
        name: float(row[f"{PREFIX}{field}"])
        for name, field in fields.items()
    }
    result.update(
        {
            "upper_gas_kg": float(row["phase3_shadow_upper_gas_kg"]),
            "lower_gas_kg": float(row["phase3_shadow_lower_gas_kg"]),
            "pressure_gauge_pa": float(
                row["phase3_shadow_thermo_pressure_gauge_pa"]
            ),
            "zone_mass_residual_kg": float(
                row["phase3_shadow_mass_residual_kg"]
            ),
            "zone_energy_residual_kj": float(
                row["phase3_shadow_energy_residual_kj"]
            ),
        }
    )
    return result


def build_audit(
    *,
    baseline_csv: Path,
    candidate_csv: Path,
    room_id: int = 0,
) -> dict[str, Any]:
    baseline_fields, baseline_rows = read_csv(baseline_csv)
    candidate_fields, candidate_rows = read_csv(candidate_csv)
    isolation = compare_live_values(
        baseline_fields,
        baseline_rows,
        candidate_fields,
        candidate_rows,
    )
    baseline = fixed_gross_metrics(final_room_row(baseline_rows, room_id))
    candidate = fixed_gross_metrics(final_room_row(candidate_rows, room_id))
    ratios = {
        "requested_pressure_ratio": (
            candidate["requested_pressure_net_out_kg"]
            / baseline["requested_pressure_net_out_kg"]
        ),
        "cap_count_ratio": (
            candidate["cap_count"] / baseline["cap_count"]
        ),
        "rejected_mass_ratio": (
            candidate["rejected_abs_kg"] / baseline["rejected_abs_kg"]
        ),
    }
    isolation_ok = (
        isolation["rows_align"]
        and isolation["shared_live_field_count"] > 0
        and isolation["live_value_difference_count"] == 0
    )
    one_way_pressure_runaway = (
        candidate["positive_cap_count"] > 1000
        and candidate["negative_cap_count"] == 0
        and ratios["requested_pressure_ratio"] > 10.0
    )
    lower_zone_collapsed = candidate["lower_gas_kg"] <= 1.0e-6
    return {
        "room_id": room_id,
        "isolation": isolation,
        "baseline": baseline,
        "candidate": candidate,
        "ratios": ratios,
        "verdict": {
            "isolation_ok": isolation_ok,
            "one_way_pressure_runaway": one_way_pressure_runaway,
            "lower_zone_collapsed": lower_zone_collapsed,
            "candidate_stable": not (
                one_way_pressure_runaway or lower_zone_collapsed
            ),
            "runtime_authority_ready": False,
            "decision": "NO-GO",
            "next_gate": (
                "Design an implicit or under-relaxed interior pressure "
                "network solve. Do not retry direct route replacement or "
                "per-step clipping."
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline-csv", type=Path, default=DEFAULT_BASELINE
    )
    parser.add_argument(
        "--candidate-csv", type=Path, default=DEFAULT_CANDIDATE
    )
    parser.add_argument("--room", type=int, default=0)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    result = build_audit(
        baseline_csv=args.baseline_csv,
        candidate_csv=args.candidate_csv,
        room_id=args.room,
    )
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(rendered + "\n", encoding="utf-8")
    verdict = result["verdict"]
    return 0 if (
        verdict["isolation_ok"]
        and verdict["one_way_pressure_runaway"]
        and verdict["lower_zone_collapsed"]
        and not verdict["candidate_stable"]
        and not verdict["runtime_authority_ready"]
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
