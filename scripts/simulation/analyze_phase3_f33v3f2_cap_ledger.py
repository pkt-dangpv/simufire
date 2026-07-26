#!/usr/bin/env python3
"""Audit F3.3v3f2 fixed-gross cap direction and cumulative bias."""

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


DEFAULT_RUN = ROOT / "runs" / "phase3_f33v3f2" / "180_cap_ledger"
DEFAULT_CFAST = ROOT / "sim" / "validation" / "cfast"
PREFIX = "phase3_shadow_fixed_gross_"


def read_room_rows(path: Path, room_id: int) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return [
            row
            for row in csv.DictReader(handle)
            if int(float(row["room_id"])) == room_id
        ]


def cap_intervals(rows: list[dict[str, str]]) -> list[dict[str, float]]:
    fields = (
        "cap_count_total",
        "cap_positive_count_total",
        "cap_negative_count_total",
        "cap_rejected_abs_kg_total",
    )
    previous = {field: 0.0 for field in fields}
    intervals: list[dict[str, float]] = []
    for row in rows:
        current = {
            field: float(row[f"{PREFIX}{field}"]) for field in fields
        }
        if current["cap_count_total"] > previous["cap_count_total"]:
            intervals.append(
                {
                    "time_s": float(row["time_s"]),
                    **{
                        field: current[field] - previous[field]
                        for field in fields
                    },
                }
            )
        previous = current
    return intervals


def build_audit(
    *,
    sim_csv: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    room_id: int = 0,
    checkpoint_s: int = 180,
) -> dict[str, Any]:
    rows = read_room_rows(sim_csv, room_id)
    if not rows:
        raise ValueError(f"room {room_id} is absent")
    final = rows[-1]
    cfast = f33m.build_cfast_checkpoint(
        checkpoint_s,
        f33m.read_cfast_zone(cfast_zone_path),
        f33m.read_cfast_compartments(cfast_compartments_path),
    )
    cfast_net = (
        cfast["routes"]["0->1"]["mass_kg"]
        - cfast["routes"]["1->0"]["mass_kg"]
    )
    requested_total = float(
        final[f"{PREFIX}pressure_requested_net_out_kg_total"]
    )
    accepted_total = float(
        final[f"{PREFIX}pressure_accepted_net_out_kg_total"]
    )
    cap_requested_positive = float(
        final[f"{PREFIX}cap_requested_positive_kg_total"]
    )
    cap_requested_negative = float(
        final[f"{PREFIX}cap_requested_negative_abs_kg_total"]
    )
    cap_accepted_positive = float(
        final[f"{PREFIX}cap_accepted_positive_kg_total"]
    )
    cap_accepted_negative = float(
        final[f"{PREFIX}cap_accepted_negative_abs_kg_total"]
    )
    cap_requested_signed = cap_requested_positive - cap_requested_negative
    cap_accepted_signed = cap_accepted_positive - cap_accepted_negative
    uncapped_requested = requested_total - cap_requested_signed
    reconstruction = uncapped_requested + cap_accepted_signed
    cap_count = float(final[f"{PREFIX}cap_count_total"])
    positive_count = float(final[f"{PREFIX}cap_positive_count_total"])
    negative_count = float(final[f"{PREFIX}cap_negative_count_total"])
    metrics = {
        "cfast_net_mass_out_kg": cfast_net,
        "requested_pressure_net_out_kg": requested_total,
        "accepted_pressure_net_out_kg": accepted_total,
        "requested_share_of_cfast": requested_total / cfast_net,
        "accepted_share_of_cfast": accepted_total / cfast_net,
        "cap_count": cap_count,
        "positive_cap_count": positive_count,
        "negative_cap_count": negative_count,
        "cap_requested_signed_kg": cap_requested_signed,
        "cap_accepted_signed_kg": cap_accepted_signed,
        "cap_directional_bias_kg": cap_accepted_signed - cap_requested_signed,
        "cap_rejected_abs_kg": float(
            final[f"{PREFIX}cap_rejected_abs_kg_total"]
        ),
        "cap_max_rejected_abs_kg": float(
            final[f"{PREFIX}cap_max_rejected_abs_kg"]
        ),
        "uncapped_requested_net_out_kg": uncapped_requested,
        "accepted_reconstruction_kg": reconstruction,
        "accepted_reconstruction_residual_kg": (
            reconstruction - accepted_total
        ),
    }
    verdict = {
        "cap_count_closes": cap_count == positive_count + negative_count,
        "accepted_reconstruction_closes": (
            abs(metrics["accepted_reconstruction_residual_kg"]) <= 1.0e-4
        ),
        "pressure_request_is_near_cfast": (
            abs(metrics["requested_share_of_cfast"] - 1.0) <= 0.15
        ),
        "posthoc_cap_reverses_capped_integral": (
            cap_requested_signed > 0.0 and cap_accepted_signed < 0.0
        ),
        "static_same_pressure_normalization_is_sufficient": False,
        "next_gate": (
            "Replace additive opening+pressure routes only inside a new "
            "default-OFF canonical shadow branch, then let accepted fixed-"
            "gross transport evolve the pressure state for 180 s."
        ),
    }
    return {
        "checkpoint_s": checkpoint_s,
        "room_id": room_id,
        "metrics": metrics,
        "cap_intervals": cap_intervals(rows),
        "verdict": verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sim-csv", type=Path, default=DEFAULT_RUN / "sim_log.csv"
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
        sim_csv=args.sim_csv,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
    )
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(rendered + "\n", encoding="utf-8")
    required = (
        "cap_count_closes",
        "accepted_reconstruction_closes",
        "pressure_request_is_near_cfast",
        "posthoc_cap_reverses_capped_integral",
    )
    return 0 if all(result["verdict"][key] for key in required) else 1


if __name__ == "__main__":
    raise SystemExit(main())
