#!/usr/bin/env python3
"""Audit one staged F3.3v3g3 persistent pressure-network gate.

The candidate applies the F3.3v3g2 blended routes to the canonical shadow only.
This audit proves three independent things for a single duration:

1. live isolation - every non-`phase3_shadow_*` column is byte-identical
   between the baseline (g2 ON, g3 OFF) and the candidate (g2 ON, g3 ON);
2. stability - pressure request and cap counts do not grow monotonically, the
   accepted transport stays bidirectional, no occupied zone collapses and the
   EOS stays valid;
3. closure - the atomic bundle applies exactly the requested fraction and every
   conservation residual stays inside its invariant.

It exits non-zero when any mandatory verdict fails, so a staged run can be
stopped before the next duration is launched.
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


DEFAULT_RUN_ROOT = ROOT / "runs" / "phase3_f33v3g3"
DEFAULT_CFAST = ROOT / "sim" / "validation" / "cfast"
PREFIX = "phase3_shadow_pressure_network_persistent_"
SHADOW_PREFIX = "phase3_shadow_"

MASS_TOLERANCE_KG = 1.0e-9
ENERGY_TOLERANCE_KJ = 1.0e-7
O2_TOLERANCE_KG = 1.0e-9
SPECIES_TOLERANCE_KG = 1.0e-9
CORRESPONDENCE_TOLERANCE = 0.05
NET_MASS_TOLERANCE = 0.25

# F3.3v3f2 baselines the staged targets are measured against.
F33V3F2_REQUESTED_NET_KG = 6.368
F33V3F2_CAP_COUNT = 79
MONOTONIC_GROWTH_LIMIT = 10


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def compare_live_columns(
    off_rows: list[dict[str, str]], on_rows: list[dict[str, str]]
) -> dict[str, Any]:
    """Only canonical shadow columns may differ; everything else may not."""
    if not off_rows or not on_rows:
        raise ValueError("baseline and candidate CSVs must contain rows")
    shared = [field for field in off_rows[0] if field in on_rows[0]]
    live = [field for field in shared if not field.startswith(SHADOW_PREFIX)]
    live_differences = 0
    shadow_differences = 0
    first_live_difference: dict[str, Any] | None = None
    changed_shadow_columns: set[str] = set()
    if len(off_rows) != len(on_rows):
        live_differences += abs(len(off_rows) - len(on_rows))
    for index, (off, on) in enumerate(zip(off_rows, on_rows)):
        for field in shared:
            if off[field] == on[field]:
                continue
            if field.startswith(SHADOW_PREFIX):
                shadow_differences += 1
                changed_shadow_columns.add(field)
                continue
            live_differences += 1
            if first_live_difference is None:
                first_live_difference = {
                    "row": index,
                    "field": field,
                    "baseline": off[field],
                    "candidate": on[field],
                }
    new_columns = [field for field in on_rows[0] if field not in off_rows[0]]
    return {
        "baseline_rows": len(off_rows),
        "candidate_rows": len(on_rows),
        "shared_columns": len(shared),
        "live_columns": len(live),
        "live_value_difference_count": live_differences,
        "first_live_difference": first_live_difference,
        "shadow_value_difference_count": shadow_differences,
        "changed_shadow_column_count": len(changed_shadow_columns),
        "new_column_count": len(new_columns),
        "new_columns_all_persistent": all(
            field.startswith(PREFIX) for field in new_columns
        ),
        "missing_candidate_columns": [
            field for field in off_rows[0] if field not in on_rows[0]
        ],
    }


def active_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [row for row in rows if float(row[f"{PREFIX}enabled_flag"]) > 0.0]


def final_rows(
    rows: list[dict[str, str]], checkpoint_s: float
) -> list[dict[str, str]]:
    matches = [
        row
        for row in active_rows(rows)
        if abs(float(row["time_s"]) - checkpoint_s) <= 0.11
    ]
    if not matches:
        raise ValueError(f"no active candidate row at {checkpoint_s:g}s")
    return matches


def cumulative_contract(
    rows: list[dict[str, str]], checkpoint_s: float
) -> dict[str, Any]:
    tail = final_rows(rows, checkpoint_s)
    first_active_time = min(float(row["time_s"]) for row in active_rows(rows))
    first_sample = [
        row
        for row in active_rows(rows)
        if abs(float(row["time_s"]) - first_active_time) <= 0.11
    ]

    def total(field: str, reducer=max) -> float:
        return reducer(float(row[f"{PREFIX}{field}_total"]) for row in tail)

    return {
        "first_active_sample_time_s": first_active_time,
        "applied_step_count": total("applied_step_count"),
        "candidate_cap_count": total("candidate_cap_count"),
        "base_fallback_count": total("base_fallback_count"),
        "base_fallback_count_at_first_sample": max(
            float(row[f"{PREFIX}base_fallback_count_total"])
            for row in first_sample
        ),
        "full_fallback_count": total("full_fallback_count"),
        "full_fallback_count_at_first_sample": max(
            float(row[f"{PREFIX}full_fallback_count_total"])
            for row in first_sample
        ),
        "invalid_count": total("invalid_count"),
        "invalid_count_at_first_sample": max(
            float(row[f"{PREFIX}invalid_count_total"]) for row in first_sample
        ),
        "non_descent_count": total("non_descent_count"),
        "crossing_limited_count": total("crossing_limited_count"),
        "requested_pressure_net_positive_kg": total(
            "requested_pressure_net_positive_kg"
        ),
        "requested_pressure_net_negative_abs_kg": total(
            "requested_pressure_net_negative_abs_kg"
        ),
        "accepted_net_positive_kg": total("accepted_net_positive_kg"),
        "accepted_net_negative_abs_kg": total("accepted_net_negative_abs_kg"),
        "max_consecutive_same_sign_count": total(
            "max_consecutive_same_sign_count"
        ),
        "max_monotonic_request_growth_count": total(
            "max_monotonic_request_growth_count"
        ),
        "max_prediction_divergence_streak": total(
            "max_prediction_divergence_streak"
        ),
        "max_abs_prediction_error_pa2": total("max_abs_prediction_error_pa2"),
        "max_objective_increase_pa2": total("max_objective_increase_pa2"),
        "min_post_upper_gas_kg": total("min_post_upper_gas_kg", min),
        "min_post_lower_gas_kg": total("min_post_lower_gas_kg", min),
        "unexpected_zone_collapse_count": total(
            "unexpected_zone_collapse_count"
        ),
        "eos_invalid_count": total("eos_invalid_count"),
        "bundle_double_limit_count": total("bundle_double_limit_count"),
        "min_accepted_bundle_fraction": total(
            "min_accepted_bundle_fraction", min
        ),
        "live_isolation_violation_count": total(
            "live_isolation_violation_count"
        ),
        "max_residuals": {
            "mass_residual_kg": total("max_abs_mass_residual_kg"),
            "energy_residual_kj": total("max_abs_energy_residual_kj"),
            "o2_residual_kg": total("max_abs_o2_residual_kg"),
            "species_residual_kg": total("max_abs_species_residual_kg"),
        },
    }


def room_state(rows: list[dict[str, str]], checkpoint_s: float) -> list[dict[str, Any]]:
    table = []
    for row in final_rows(rows, checkpoint_s):
        table.append(
            {
                "room_id": int(float(row["room_id"])),
                "alpha_accepted": float(row[f"{PREFIX}alpha_accepted"]),
                "applied_flag": float(row[f"{PREFIX}applied_flag"]),
                "requested_bundle_fraction": float(
                    row[f"{PREFIX}requested_bundle_fraction"]
                ),
                "accepted_bundle_fraction": float(
                    row[f"{PREFIX}accepted_bundle_fraction"]
                ),
                "post_upper_gas_kg": float(row[f"{PREFIX}post_upper_gas_kg"]),
                "post_lower_gas_kg": float(row[f"{PREFIX}post_lower_gas_kg"]),
                "post_upper_energy_kj": float(
                    row[f"{PREFIX}post_upper_energy_kj"]
                ),
                "post_lower_energy_kj": float(
                    row[f"{PREFIX}post_lower_energy_kj"]
                ),
                "post_pressure_gauge_pa": float(
                    row[f"{PREFIX}post_pressure_gauge_pa"]
                ),
                "post_interface_m": float(row[f"{PREFIX}post_interface_m"]),
                "post_eos_valid_flag": float(
                    row[f"{PREFIX}post_eos_valid_flag"]
                ),
                "objective_pre_pa2": float(row[f"{PREFIX}objective_pre_pa2"]),
                "objective_predicted_pa2": float(
                    row[f"{PREFIX}objective_predicted_pa2"]
                ),
                "objective_observed_pa2": float(
                    row[f"{PREFIX}objective_observed_pa2"]
                ),
                "objective_prediction_error_pa2": float(
                    row[f"{PREFIX}objective_prediction_error_pa2"]
                ),
                "requested_pressure_net_out_kg_total": float(
                    row[f"{PREFIX}requested_pressure_net_positive_kg_total"]
                )
                - float(
                    row[f"{PREFIX}requested_pressure_net_negative_abs_kg_total"]
                ),
                "accepted_net_out_kg_total": float(
                    row[f"{PREFIX}accepted_net_positive_kg_total"]
                )
                - float(row[f"{PREFIX}accepted_net_negative_abs_kg_total"]),
            }
        )
    return table


def pressure_divergence(
    off_rows: list[dict[str, str]],
    on_rows: list[dict[str, str]],
    checkpoint_s: float,
) -> dict[str, Any]:
    """Baseline-versus-candidate drift of the canonical shadow pressure.

    This is the direct feedback measurement: the candidate is the only thing
    allowed to move the canonical pressure, so any systematic growth of the
    ratio is one-way pressure feedback rather than a transient.
    """
    gauge = "phase3_shadow_thermo_pressure_gauge_pa"
    requested = (
        "phase3_shadow_fixed_gross_pressure_requested_net_out_kg_total"
    )
    samples = []
    worst_ratio = 0.0
    for off, on in zip(off_rows, on_rows):
        if int(float(off["room_id"])) != 0:
            continue
        if float(off["time_s"]) <= 0.0:
            continue
        baseline_pa = float(off[gauge])
        candidate_pa = float(on[gauge])
        ratio = (
            abs(candidate_pa) / abs(baseline_pa)
            if abs(baseline_pa) > 1.0e-9
            else 0.0
        )
        worst_ratio = max(worst_ratio, ratio)
        samples.append(
            {
                "time_s": float(off["time_s"]),
                "baseline_gauge_pa": baseline_pa,
                "candidate_gauge_pa": candidate_pa,
                "gauge_ratio": ratio,
                "baseline_requested_net_kg_total": float(off[requested]),
                "candidate_requested_net_kg_total": float(on[requested]),
            }
        )
    final = [
        sample
        for sample in samples
        if abs(sample["time_s"] - checkpoint_s) <= 0.11
    ]
    tail = final[-1] if final else samples[-1]
    baseline_request = tail["baseline_requested_net_kg_total"]
    return {
        "samples": samples,
        "max_gauge_ratio": worst_ratio,
        "final_baseline_gauge_pa": tail["baseline_gauge_pa"],
        "final_candidate_gauge_pa": tail["candidate_gauge_pa"],
        # Comparable to the F3.3v3f2 6.368 kg baseline: both are the relaxed
        # pressure route net, not the raw pre-relaxation demand.
        "final_baseline_requested_net_kg": baseline_request,
        "final_candidate_requested_net_kg": tail[
            "candidate_requested_net_kg_total"
        ],
        "requested_growth_vs_baseline": (
            tail["candidate_requested_net_kg_total"] / baseline_request
            if abs(baseline_request) > 1.0e-9
            else 0.0
        ),
    }


def cfast_correspondence(
    rows: list[dict[str, str]],
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    checkpoint_s: int,
) -> dict[str, Any]:
    """R0 doorway correspondence from the accepted canonical route ledger."""
    room = [
        row
        for row in rows
        if int(float(row["room_id"])) == 0
        and abs(float(row["time_s"]) - checkpoint_s) <= 0.11
    ][-1]
    cfast = f33m.build_cfast_checkpoint(
        checkpoint_s,
        f33m.read_cfast_zone(cfast_zone_path),
        f33m.read_cfast_compartments(cfast_compartments_path),
    )
    cfast_out = cfast["routes"]["0->1"]
    cfast_in = cfast["routes"]["1->0"]
    fixed_gross = "phase3_shadow_pressure_network_"
    accepted_out = float(room[f"{fixed_gross}accepted_out_mass_kg_total"])
    accepted_in = float(room[f"{fixed_gross}accepted_in_mass_kg_total"])
    accepted_enthalpy = float(
        room[f"{fixed_gross}accepted_net_enthalpy_out_kj_total"]
    )
    cfast_gross = cfast_out["mass_kg"] + cfast_in["mass_kg"]
    cfast_net_mass = cfast_out["mass_kg"] - cfast_in["mass_kg"]
    cfast_enthalpy = cfast_out["enthalpy_kj"] - cfast_in["enthalpy_kj"]
    return {
        "accepted_out_mass_kg": accepted_out,
        "accepted_in_mass_kg": accepted_in,
        "accepted_gross_mass_kg": accepted_out + accepted_in,
        "accepted_net_mass_out_kg": accepted_out - accepted_in,
        "accepted_net_enthalpy_out_kj": accepted_enthalpy,
        "cfast_gross_mass_kg": cfast_gross,
        "cfast_net_mass_out_kg": cfast_net_mass,
        "cfast_net_enthalpy_out_kj": cfast_enthalpy,
        "gross_mass_relative_error": (
            (accepted_out + accepted_in - cfast_gross) / cfast_gross
        ),
        "net_mass_relative_error": (
            (accepted_out - accepted_in - cfast_net_mass) / cfast_net_mass
        ),
        "net_enthalpy_relative_error": (
            (accepted_enthalpy - cfast_enthalpy) / cfast_enthalpy
        ),
    }


# Checked at every stage. These are duration-independent contracts.
REQUIRED_VERDICTS = (
    "row_counts_match",
    "live_columns_identical",
    "only_persistent_columns_added",
    "candidate_active",
    "candidate_applied",
    "no_full_fallback_after_first_sample",
    "no_invalid_step_after_first_sample",
    "no_unexpected_zone_collapse",
    "eos_always_valid",
    "lower_shadow_gas_positive",
    "bundle_applies_the_requested_fraction",
    "no_monotonic_request_growth",
    "no_pressure_runaway",
    "no_prediction_runaway",
    "transport_is_bidirectional",
    "mass_closure_ok",
    "energy_closure_ok",
    "o2_closure_ok",
    "species_closure_ok",
    "no_live_isolation_violation",
    "requested_transport_within_2x_baseline",
    "cap_count_within_2x_baseline",
)

# Only meaningful at the final 180 s gate. At 30 s the *baseline* itself is
# -51% on gross and -17.6% on net enthalpy versus CFAST, because the fire is
# still growing, so applying the 180 s envelope earlier would compare the
# candidate against a target the accepted architecture does not meet either.
FINAL_STAGE_VERDICTS = (
    "gross_mass_within_5pct",
    "net_enthalpy_within_5pct",
)

TARGET_VERDICTS = ("net_mass_within_25pct",)

FINAL_CHECKPOINT_S = 180
PRESSURE_RUNAWAY_RATIO = 2.0
PREDICTION_DIVERGENCE_LIMIT = 10


def build_audit(
    *,
    off_csv: Path,
    on_csv: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    checkpoint_s: int,
) -> dict[str, Any]:
    off_rows = read_csv(off_csv)
    on_rows = read_csv(on_csv)
    isolation = compare_live_columns(off_rows, on_rows)
    cumulative = cumulative_contract(on_rows, checkpoint_s)
    divergence = pressure_divergence(off_rows, on_rows, checkpoint_s)
    rooms = room_state(on_rows, checkpoint_s)
    correspondence = cfast_correspondence(
        on_rows, cfast_zone_path, cfast_compartments_path, checkpoint_s
    )
    residuals = cumulative["max_residuals"]
    requested_magnitude_kg = (
        cumulative["requested_pressure_net_positive_kg"]
        + cumulative["requested_pressure_net_negative_abs_kg"]
    )
    verdict = {
        "row_counts_match": (
            isolation["baseline_rows"] == isolation["candidate_rows"]
        ),
        "live_columns_identical": (
            isolation["live_value_difference_count"] == 0
        ),
        "only_persistent_columns_added": (
            isolation["new_columns_all_persistent"]
            and not isolation["missing_candidate_columns"]
        ),
        "candidate_active": cumulative["applied_step_count"] > 0,
        "candidate_applied": all(
            room["applied_flag"] > 0.0 for room in rooms
        ),
        # The known ignition-transient fail-closed steps are allowed, but only
        # inside the first logged interval; appearing later is a STOP.
        "no_full_fallback_after_first_sample": (
            cumulative["full_fallback_count"]
            == cumulative["full_fallback_count_at_first_sample"]
        ),
        "no_invalid_step_after_first_sample": (
            cumulative["invalid_count"]
            == cumulative["invalid_count_at_first_sample"]
        ),
        "no_unexpected_zone_collapse": (
            cumulative["unexpected_zone_collapse_count"] == 0.0
        ),
        "eos_always_valid": cumulative["eos_invalid_count"] == 0.0,
        "lower_shadow_gas_positive": (
            cumulative["min_post_lower_gas_kg"] > 0.0
        ),
        # A second limiting stage would mean the blended routes were bounded
        # twice; the g2 inventory bound must already be sufficient.
        "bundle_applies_the_requested_fraction": (
            cumulative["bundle_double_limit_count"] == 0.0
            and cumulative["min_accepted_bundle_fraction"] >= 1.0 - 1.0e-9
        ),
        "no_monotonic_request_growth": (
            cumulative["max_monotonic_request_growth_count"]
            < MONOTONIC_GROWTH_LIMIT
        ),
        "transport_is_bidirectional": (
            cumulative["accepted_net_positive_kg"] > 0.0
            and cumulative["accepted_net_negative_abs_kg"] > 0.0
        ),
        "mass_closure_ok": (
            residuals["mass_residual_kg"] <= MASS_TOLERANCE_KG
        ),
        "energy_closure_ok": (
            residuals["energy_residual_kj"] <= ENERGY_TOLERANCE_KJ
        ),
        "o2_closure_ok": residuals["o2_residual_kg"] <= O2_TOLERANCE_KG,
        "species_closure_ok": (
            residuals["species_residual_kg"] <= SPECIES_TOLERANCE_KG
        ),
        "no_live_isolation_violation": (
            cumulative["live_isolation_violation_count"] == 0.0
        ),
        # Compared on the relaxed pressure route net, the same basis as the
        # F3.3v3f2 6.368 kg reference.
        "requested_transport_within_2x_baseline": (
            divergence["final_candidate_requested_net_kg"]
            <= 2.0 * F33V3F2_REQUESTED_NET_KG
        ),
        "no_pressure_runaway": (
            divergence["max_gauge_ratio"] <= PRESSURE_RUNAWAY_RATIO
        ),
        "no_prediction_runaway": (
            cumulative["max_prediction_divergence_streak"]
            < PREDICTION_DIVERGENCE_LIMIT
        ),
        "cap_count_within_2x_baseline": (
            cumulative["candidate_cap_count"] <= 2 * F33V3F2_CAP_COUNT
        ),
        "gross_mass_within_5pct": (
            abs(correspondence["gross_mass_relative_error"])
            <= CORRESPONDENCE_TOLERANCE
        ),
        "net_enthalpy_within_5pct": (
            abs(correspondence["net_enthalpy_relative_error"])
            <= CORRESPONDENCE_TOLERANCE
        ),
        "net_mass_within_25pct": (
            abs(correspondence["net_mass_relative_error"])
            <= NET_MASS_TOLERANCE
        ),
        "runtime_authority_ready": False,
    }
    required = list(REQUIRED_VERDICTS)
    if checkpoint_s >= FINAL_CHECKPOINT_S:
        required += list(FINAL_STAGE_VERDICTS)
    verdict["stage_pass"] = all(verdict[key] for key in required)
    verdict["target_pass"] = all(verdict[key] for key in TARGET_VERDICTS)
    verdict["cfast_envelope_gated"] = checkpoint_s >= FINAL_CHECKPOINT_S
    verdict["failed_checks"] = [key for key in required if not verdict[key]]
    return {
        "checkpoint_s": checkpoint_s,
        "isolation": isolation,
        "all_step_contract": cumulative,
        "pressure_divergence": divergence,
        "raw_requested_transport_magnitude_kg": requested_magnitude_kg,
        "rooms": rooms,
        "correspondence": correspondence,
        "verdict": verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", default="180", help="Stage label, e.g. 030.")
    parser.add_argument("--checkpoint", type=int, default=None)
    parser.add_argument("--off-csv", type=Path)
    parser.add_argument("--on-csv", type=Path)
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
    stage = args.stage
    checkpoint = args.checkpoint if args.checkpoint is not None else int(stage)
    off_csv = args.off_csv or DEFAULT_RUN_ROOT / f"{stage}_off" / "sim_log.csv"
    on_csv = args.on_csv or DEFAULT_RUN_ROOT / f"{stage}_on" / "sim_log.csv"
    result = build_audit(
        off_csv=off_csv,
        on_csv=on_csv,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
        checkpoint_s=checkpoint,
    )
    result["stage"] = stage
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["verdict"]["stage_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
