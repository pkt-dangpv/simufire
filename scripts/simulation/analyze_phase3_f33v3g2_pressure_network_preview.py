#!/usr/bin/env python3
"""Audit the F3.3v3g2 passive interior pressure-network preview.

The audit proves two independent facts:

1. isolation - the OFF and ON runs share every legacy and F3.3v3f1 column with
   byte-identical values, so the preview changes no live state;
2. contract - every active preview step descends the network objective, keeps
   both predicted zone inventories positive, closes mass, energy, O2 and
   species atomically and preserves the CFAST gross/enthalpy correspondence.
"""

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


DEFAULT_RUN_ROOT = ROOT / "runs" / "phase3_f33v3g2"
DEFAULT_CFAST = ROOT / "sim" / "validation" / "cfast"
PREFIX = "phase3_shadow_pressure_network_"

MASS_TOLERANCE_KG = 1.0e-9
ENERGY_TOLERANCE_KJ = 1.0e-7
O2_TOLERANCE_KG = 1.0e-9
SPECIES_TOLERANCE_KG = 1.0e-9
OBJECTIVE_TOLERANCE_PA2 = 1.0e-9
CORRESPONDENCE_TOLERANCE = 0.05

REASON_NAMES = {
    0.0: "invalid",
    1.0: "optimal",
    2.0: "crossing",
    3.0: "inventory",
    4.0: "non_descent",
    5.0: "zero_response",
    6.0: "no_connections",
}


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
    new_columns = [field for field in on_rows[0] if field not in off_rows[0]]
    return {
        "off_rows": len(off_rows),
        "on_rows": len(on_rows),
        "shared_columns": len(shared),
        "missing_off_columns": [
            field for field in off_rows[0] if field not in on_rows[0]
        ],
        "new_column_count": len(new_columns),
        "new_columns_all_pressure_network": all(
            field.startswith(PREFIX) for field in new_columns
        ),
        "shared_value_difference_count": differences,
        "first_difference": first_difference,
    }


def active_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [row for row in rows if float(row[f"{PREFIX}enabled_flag"]) > 0.0]


def step_contract(rows: list[dict[str, str]]) -> dict[str, Any]:
    active = active_rows(rows)
    objective_violations = 0
    worst_objective_increase = 0.0
    invalid_steps = 0
    negative_quantity_steps = 0
    collapse_steps = 0
    min_predicted_upper = None
    min_predicted_lower = None
    max_residuals = {
        "gross_mass_residual_kg": 0.0,
        "mass_residual_kg": 0.0,
        "energy_residual_kj": 0.0,
        "o2_residual_kg": 0.0,
        "species_residual_kg": 0.0,
    }
    alpha_bounds = {
        "alpha_optimal": [None, None],
        "alpha_crossing": [None, None],
        "alpha_inventory": [None, None],
        "alpha_accepted": [None, None],
    }
    reason_counts: dict[str, int] = {}
    for row in active:
        pre = float(row[f"{PREFIX}objective_pre_pa2"])
        post = float(row[f"{PREFIX}objective_post_pa2"])
        increase = post - pre
        if increase > OBJECTIVE_TOLERANCE_PA2:
            objective_violations += 1
        worst_objective_increase = max(worst_objective_increase, increase)
        if float(row[f"{PREFIX}valid_flag"]) <= 0.0:
            invalid_steps += 1
        if float(row[f"{PREFIX}negative_quantity_count"]) > 0.0:
            negative_quantity_steps += 1
        if float(row[f"{PREFIX}predicted_collapse_count_step"]) > 0.0:
            collapse_steps += 1
        upper = float(row[f"{PREFIX}predicted_min_upper_gas_kg"])
        lower = float(row[f"{PREFIX}predicted_min_lower_gas_kg"])
        min_predicted_upper = (
            upper if min_predicted_upper is None else min(min_predicted_upper, upper)
        )
        min_predicted_lower = (
            lower if min_predicted_lower is None else min(min_predicted_lower, lower)
        )
        for field in max_residuals:
            max_residuals[field] = max(
                max_residuals[field], abs(float(row[f"{PREFIX}{field}"]))
            )
        for field, bounds in alpha_bounds.items():
            value = float(row[f"{PREFIX}{field}"])
            bounds[0] = value if bounds[0] is None else min(bounds[0], value)
            bounds[1] = value if bounds[1] is None else max(bounds[1], value)
        reason = REASON_NAMES.get(
            float(row[f"{PREFIX}limiting_reason_code"]), "unknown"
        )
        reason_counts[reason] = reason_counts.get(reason, 0) + 1
    return {
        "active_step_row_count": len(active),
        "objective_increase_count": objective_violations,
        "worst_objective_increase_pa2": worst_objective_increase,
        "invalid_step_row_count": invalid_steps,
        "negative_quantity_step_row_count": negative_quantity_steps,
        "predicted_collapse_step_row_count": collapse_steps,
        "min_predicted_upper_gas_kg": min_predicted_upper,
        "min_predicted_lower_gas_kg": min_predicted_lower,
        "max_residuals": max_residuals,
        "alpha_bounds": {
            field: {"min": bounds[0], "max": bounds[1]}
            for field, bounds in alpha_bounds.items()
        },
        "limiting_reason_counts": reason_counts,
    }


def cumulative_contract(
    rows: list[dict[str, str]], checkpoint_s: float
) -> dict[str, Any]:
    """Invariants over every physical step, not only the logged samples."""
    final_rows = [
        row
        for row in active_rows(rows)
        if abs(float(row["time_s"]) - checkpoint_s) <= 0.11
    ]
    if not final_rows:
        raise ValueError("no active preview row at the checkpoint")
    first_active_time = min(float(row["time_s"]) for row in active_rows(rows))
    first_sample_invalid = max(
        float(row[f"{PREFIX}invalid_count_total"])
        for row in active_rows(rows)
        if abs(float(row["time_s"]) - first_active_time) <= 0.11
    )
    return {
        "first_active_sample_time_s": first_active_time,
        "physical_step_count": max(
            float(row[f"{PREFIX}active_step_count_total"]) for row in final_rows
        ),
        "invalid_step_count": max(
            float(row[f"{PREFIX}invalid_count_total"]) for row in final_rows
        ),
        "invalid_step_count_at_first_sample": first_sample_invalid,
        "non_descent_step_count": max(
            float(row[f"{PREFIX}non_descent_count_total"]) for row in final_rows
        ),
        "inventory_limited_step_count": max(
            float(row[f"{PREFIX}inventory_limited_count_total"])
            for row in final_rows
        ),
        "crossing_limited_step_count": max(
            float(row[f"{PREFIX}crossing_limited_count_total"])
            for row in final_rows
        ),
        "negative_quantity_count": max(
            float(row[f"{PREFIX}negative_quantity_count_total"])
            for row in final_rows
        ),
        "predicted_collapse_count": max(
            float(row[f"{PREFIX}predicted_collapse_count_total"])
            for row in final_rows
        ),
        "degenerate_zone_count": max(
            float(row[f"{PREFIX}degenerate_zone_count_total"])
            for row in final_rows
        ),
        "min_predicted_upper_gas_kg": min(
            float(row[f"{PREFIX}min_predicted_upper_gas_kg_total"])
            for row in final_rows
        ),
        "min_predicted_lower_gas_kg": min(
            float(row[f"{PREFIX}min_predicted_lower_gas_kg_total"])
            for row in final_rows
        ),
        "max_objective_increase_pa2": max(
            float(row[f"{PREFIX}max_objective_increase_pa2_total"])
            for row in final_rows
        ),
        "max_residuals": {
            field: max(
                float(row[f"{PREFIX}max_abs_{field}_total"])
                for row in final_rows
            )
            for field in (
                "gross_mass_residual_kg",
                "mass_residual_kg",
                "energy_residual_kj",
                "o2_residual_kg",
                "species_residual_kg",
            )
        },
    }


def component_table(
    rows: list[dict[str, str]], checkpoint_s: float
) -> list[dict[str, Any]]:
    seen: dict[str, dict[str, Any]] = {}
    for row in active_rows(rows):
        if abs(float(row["time_s"]) - checkpoint_s) > 0.11:
            continue
        key = "%d" % int(float(row[f"{PREFIX}component_index"]))
        entry = seen.setdefault(
            key,
            {
                "component_index": int(float(row[f"{PREFIX}component_index"])),
                "component_room_count": int(
                    float(row[f"{PREFIX}component_room_count"])
                ),
                "component_min_room_id": int(
                    float(row[f"{PREFIX}component_min_room_id"])
                ),
                "connection_count": int(float(row[f"{PREFIX}connection_count"])),
                "alpha_optimal": float(row[f"{PREFIX}alpha_optimal"]),
                "alpha_crossing": float(row[f"{PREFIX}alpha_crossing"]),
                "alpha_inventory": float(row[f"{PREFIX}alpha_inventory"]),
                "alpha_accepted": float(row[f"{PREFIX}alpha_accepted"]),
                "limiting_reason": REASON_NAMES.get(
                    float(row[f"{PREFIX}limiting_reason_code"]), "unknown"
                ),
                "objective_pre_pa2": float(row[f"{PREFIX}objective_pre_pa2"]),
                "objective_post_pa2": float(row[f"{PREFIX}objective_post_pa2"]),
                "directional_derivative_pa2": float(
                    row[f"{PREFIX}directional_derivative_pa2"]
                ),
                "worsening_connection_count": int(
                    float(row[f"{PREFIX}worsening_connection_count"])
                ),
                "rooms": [],
            },
        )
        entry["rooms"].append(
            {
                "room_id": int(float(row["room_id"])),
                "base_out_mass_kg": float(row[f"{PREFIX}base_out_mass_kg_step"]),
                "base_in_mass_kg": float(row[f"{PREFIX}base_in_mass_kg_step"]),
                "full_out_mass_kg": float(row[f"{PREFIX}full_out_mass_kg_step"]),
                "full_in_mass_kg": float(row[f"{PREFIX}full_in_mass_kg_step"]),
                "accepted_out_mass_kg": float(
                    row[f"{PREFIX}accepted_out_mass_kg_step"]
                ),
                "accepted_in_mass_kg": float(
                    row[f"{PREFIX}accepted_in_mass_kg_step"]
                ),
                "requested_net_mass_out_kg": float(
                    row[f"{PREFIX}requested_net_mass_out_kg_step"]
                ),
                "accepted_net_mass_out_kg": float(
                    row[f"{PREFIX}accepted_net_mass_out_kg_step"]
                ),
                "accepted_positive_net_kg_total": float(
                    row[f"{PREFIX}accepted_positive_net_kg_total"]
                ),
                "accepted_negative_net_abs_kg_total": float(
                    row[f"{PREFIX}accepted_negative_net_abs_kg_total"]
                ),
                "inventory_limited_count_total": float(
                    row[f"{PREFIX}inventory_limited_count_total"]
                ),
                "non_descent_count_total": float(
                    row[f"{PREFIX}non_descent_count_total"]
                ),
                "crossing_limited_count_total": float(
                    row[f"{PREFIX}crossing_limited_count_total"]
                ),
                "invalid_count_total": float(row[f"{PREFIX}invalid_count_total"]),
                "active_step_count_total": float(
                    row[f"{PREFIX}active_step_count_total"]
                ),
            }
        )
    return [seen[key] for key in sorted(seen, key=int)]


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
    contract = step_contract(on_rows)
    cumulative = cumulative_contract(on_rows, checkpoint_s)
    components = component_table(on_rows, checkpoint_s)
    room = final_room_row(on_rows, 0, checkpoint_s)
    cfast = f33m.build_cfast_checkpoint(
        checkpoint_s,
        f33m.read_cfast_zone(cfast_zone_path),
        f33m.read_cfast_compartments(cfast_compartments_path),
    )
    cfast_out = cfast["routes"]["0->1"]
    cfast_in = cfast["routes"]["1->0"]
    accepted_out = float(room[f"{PREFIX}accepted_out_mass_kg_total"])
    accepted_in = float(room[f"{PREFIX}accepted_in_mass_kg_total"])
    accepted_enthalpy = float(
        room[f"{PREFIX}accepted_net_enthalpy_out_kj_total"]
    )
    cfast_gross = cfast_out["mass_kg"] + cfast_in["mass_kg"]
    cfast_enthalpy = cfast_out["enthalpy_kj"] - cfast_in["enthalpy_kj"]
    correspondence = {
        "accepted_out_mass_kg": accepted_out,
        "accepted_in_mass_kg": accepted_in,
        "accepted_gross_mass_kg": accepted_out + accepted_in,
        "accepted_net_mass_out_kg": accepted_out - accepted_in,
        "accepted_net_enthalpy_out_kj": accepted_enthalpy,
        "cfast_out_mass_kg": cfast_out["mass_kg"],
        "cfast_in_mass_kg": cfast_in["mass_kg"],
        "cfast_gross_mass_kg": cfast_gross,
        "cfast_net_mass_out_kg": cfast_out["mass_kg"] - cfast_in["mass_kg"],
        "cfast_net_enthalpy_out_kj": cfast_enthalpy,
        "gross_mass_relative_error": (
            (accepted_out + accepted_in - cfast_gross) / cfast_gross
        ),
        "net_enthalpy_relative_error": (
            (accepted_enthalpy - cfast_enthalpy) / cfast_enthalpy
        ),
    }
    residuals = cumulative["max_residuals"]
    verdict = {
        "row_counts_match": invariance["off_rows"] == invariance["on_rows"],
        "off_on_shared_values_identical": (
            invariance["shared_value_difference_count"] == 0
        ),
        "only_pressure_network_columns_added": (
            invariance["new_columns_all_pressure_network"]
            and not invariance["missing_off_columns"]
        ),
        "preview_active": contract["active_step_row_count"] > 0,
        "objective_never_increases": (
            contract["objective_increase_count"] == 0
            and cumulative["max_objective_increase_pa2"]
            <= OBJECTIVE_TOLERANCE_PA2
        ),
        # Fail-closed steps are allowed but must stay inside the ignition
        # transient: they may never appear after the first logged sample.
        "no_invalid_step_after_first_sample": (
            cumulative["invalid_step_count"]
            == cumulative["invalid_step_count_at_first_sample"]
        ),
        "no_negative_payload": (
            contract["negative_quantity_step_row_count"] == 0
            and cumulative["negative_quantity_count"] == 0.0
        ),
        # A zone that is already empty pre-step is degenerate, not collapsed.
        # The preview must never drive an occupied zone to or below zero.
        "no_predicted_zone_collapse": (
            cumulative["predicted_collapse_count"] == 0.0
        ),
        "no_negative_predicted_inventory": (
            cumulative["min_predicted_upper_gas_kg"] >= 0.0
            and cumulative["min_predicted_lower_gas_kg"] >= 0.0
        ),
        "mass_closure_ok": (
            residuals["mass_residual_kg"] <= MASS_TOLERANCE_KG
            and residuals["gross_mass_residual_kg"] <= MASS_TOLERANCE_KG
        ),
        "energy_closure_ok": (
            residuals["energy_residual_kj"] <= ENERGY_TOLERANCE_KJ
        ),
        "o2_closure_ok": residuals["o2_residual_kg"] <= O2_TOLERANCE_KG,
        "species_closure_ok": (
            residuals["species_residual_kg"] <= SPECIES_TOLERANCE_KG
        ),
        "gross_mass_within_5pct": (
            abs(correspondence["gross_mass_relative_error"])
            <= CORRESPONDENCE_TOLERANCE
        ),
        "net_enthalpy_within_5pct": (
            abs(correspondence["net_enthalpy_relative_error"])
            <= CORRESPONDENCE_TOLERANCE
        ),
        "runtime_authority_ready": False,
        "next_gate": (
            "F3.3v3g3 persistent dynamic shadow, staged at 30/60/120/180 s."
        ),
    }
    return {
        "checkpoint_s": checkpoint_s,
        "invariance": invariance,
        "step_contract": contract,
        "all_step_contract": cumulative,
        "components": components,
        "correspondence": correspondence,
        "verdict": verdict,
    }


REQUIRED_VERDICTS = (
    "row_counts_match",
    "off_on_shared_values_identical",
    "only_pressure_network_columns_added",
    "preview_active",
    "objective_never_increases",
    "no_invalid_step_after_first_sample",
    "no_negative_payload",
    "no_predicted_zone_collapse",
    "no_negative_predicted_inventory",
    "mass_closure_ok",
    "energy_closure_ok",
    "o2_closure_ok",
    "species_closure_ok",
    "gross_mass_within_5pct",
    "net_enthalpy_within_5pct",
)


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
    return 0 if all(result["verdict"][key] for key in REQUIRED_VERDICTS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
