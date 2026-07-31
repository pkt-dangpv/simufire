#!/usr/bin/env python3
"""Audit the F3.3v3h2 passive coupled pressure solver preview.

The preview runs the pure F3.3v3h1 solver over the already-resolved canonical
step and compares it with what the legacy interior path actually did. It writes
no route and no physical state, so this audit proves two separate things:

1. **isolation** - OFF and ON share every column and every value, and ON only
   adds `phase3_shadow_coupled_solver_*` columns;
2. **solver behaviour** - how often the solve converges, how many iterations it
   needs, whether counterflow survives, and how far the coupled solution
   diverges from the legacy transport.

Read the divergence columns carefully. `coupled_vs_legacy_pressure_delta_pa` is NOT a
solver accuracy metric: the solver predicts the pressure that the *coupled*
transport would produce, while `observed` is what the *legacy* additive path
actually produced. The two transports differ by construction, so the gap
measures how much the architecture would change the answer. Solver accuracy is
`normalized_residual`, which is driven to zero on every converged step.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RUN_ROOT = ROOT / "runs" / "phase3_f33v3h2"
PREFIX = "phase3_shadow_coupled_solver_"

# H2 is a preview, so the only hard gates are isolation and the invariants the
# solver itself promises. Convergence rate is measured and reported, not gated:
# characterising it is precisely what this phase is for.
RESIDUAL_TOLERANCE = 1.0e-12


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def compare_columns(
    off_rows: list[dict[str, str]], on_rows: list[dict[str, str]]
) -> dict[str, Any]:
    if not off_rows or not on_rows:
        raise ValueError("OFF and ON CSVs must contain rows")
    shared = [field for field in off_rows[0] if field in on_rows[0]]
    differences = 0
    first: dict[str, Any] | None = None
    if len(off_rows) != len(on_rows):
        differences += abs(len(off_rows) - len(on_rows))
    for index, (off, on) in enumerate(zip(off_rows, on_rows)):
        for field in shared:
            if off[field] == on[field]:
                continue
            differences += 1
            if first is None:
                first = {
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
        "shared_value_difference_count": differences,
        "first_difference": first,
        "new_column_count": len(new_columns),
        "new_columns_all_coupled_solver": all(
            field.startswith(PREFIX) for field in new_columns
        ),
        "missing_on_columns": [
            field for field in off_rows[0] if field not in on_rows[0]
        ],
    }


def active_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [r for r in rows if float(r[f"{PREFIX}enabled_flag"]) > 0.0]


def final_rows(
    rows: list[dict[str, str]], checkpoint_s: float
) -> list[dict[str, str]]:
    matches = [
        r
        for r in active_rows(rows)
        if abs(float(r["time_s"]) - checkpoint_s) <= 0.11
    ]
    if not matches:
        raise ValueError(f"no active preview row at {checkpoint_s:g}s")
    return matches


def solver_behaviour(
    rows: list[dict[str, str]], checkpoint_s: float
) -> dict[str, Any]:
    tail = final_rows(rows, checkpoint_s)

    def total(field: str, reducer=max) -> float:
        return reducer(float(r[f"{PREFIX}{field}_total"]) for r in tail)

    def current(field: str, reducer=max) -> float:
        column = f"{PREFIX}{field}"
        if column not in tail[0]:
            return 0.0
        return reducer(float(r[column]) for r in tail)

    steps = total("step_count")
    converged = total("converged_step_count")
    failed = total("failed_step_count")
    guard_row = max(
        tail, key=lambda r: float(r.get(f"{PREFIX}cycle_guard_attempt_total", 0.0))
    )
    return {
        "physical_step_count": steps,
        "converged_step_count": converged,
        "failed_step_count": failed,
        "convergence_rate": converged / steps if steps > 0 else 0.0,
        "iteration_cap_step_count": total("iteration_cap_step_count"),
        "damping_exhausted_step_count": total("damping_exhausted_step_count"),
        "max_iterations": total("max_iterations"),
        "max_normalized_residual": total("max_normalized_residual"),
        "counterflow_violation_count": total("counterflow_violation_count"),
        "regularization_active_count": total("regularization_active_count"),
        "rescue_attempted_step_count": total("rescue_attempted_step_count")
        if f"{PREFIX}rescue_attempted_step_count_total" in tail[0]
        else 0.0,
        "rescue_accepted_step_count": total("rescue_accepted_step_count")
        if f"{PREFIX}rescue_accepted_step_count_total" in tail[0]
        else 0.0,
        "cycle_guard_attempt_total": current("cycle_guard_attempt_total"),
        "cycle_guard_accept_total": current("cycle_guard_accept_total"),
        "cycle_guard_last_rho": float(
            guard_row.get(f"{PREFIX}cycle_guard_last_rho", 0.0)
        ),
        "cycle_guard_last_cosine": float(
            guard_row.get(f"{PREFIX}cycle_guard_last_cosine", 0.0)
        ),
        "cycle_detect_total": current("cycle_detect_total"),
        "cycle_detect_after_budget_total": current(
            "cycle_detect_after_budget_total"
        ),
        "cycle_contraction_min": current("cycle_contraction_min", min),
        "cycle_contraction_max": current("cycle_contraction_max"),
        "post_budget_cycle_streak_max": current(
            "post_budget_cycle_streak_max"
        ),
        "post_budget_cycle_solve_count": total(
            "post_budget_cycle_solve_count"
        ) if f"{PREFIX}post_budget_cycle_solve_count_total" in tail[0]
        else 0.0,
        "post_budget_cycle_converged_solve_count": total(
            "post_budget_cycle_converged_solve_count"
        ) if f"{PREFIX}post_budget_cycle_converged_solve_count_total" in tail[0]
        else 0.0,
        "post_budget_cycle_iteration_cap_solve_count": total(
            "post_budget_cycle_iteration_cap_solve_count"
        ) if f"{PREFIX}post_budget_cycle_iteration_cap_solve_count_total" in tail[0]
        else 0.0,
        "post_budget_cycle_damping_exhausted_solve_count": total(
            "post_budget_cycle_damping_exhausted_solve_count"
        ) if f"{PREFIX}post_budget_cycle_damping_exhausted_solve_count_total" in tail[0]
        else 0.0,
        "max_abs_pressure_divergence_pa": total(
            "max_abs_coupled_vs_legacy_pressure_delta_pa"
        ),
        "max_abs_net_mass_difference_kg": total(
            "max_abs_net_mass_difference_kg"
        ),
    }


def divergence_trace(rows: list[dict[str, str]], room_id: int) -> list[dict[str, Any]]:
    trace = []
    for row in active_rows(rows):
        if int(float(row["room_id"])) != room_id:
            continue
        trace.append(
            {
                "time_s": float(row["time_s"]),
                "converged": float(row[f"{PREFIX}converged_flag"]) > 0.0,
                "iterations": float(row[f"{PREFIX}iterations"]),
                "normalized_residual": float(row[f"{PREFIX}normalized_residual"]),
                "solved_pressure_gauge_pa": float(
                    row[f"{PREFIX}solved_pressure_gauge_pa"]
                ),
                "observed_pressure_gauge_pa": float(
                    row[f"{PREFIX}observed_pressure_gauge_pa"]
                ),
                "pressure_divergence_pa": float(
                    row[f"{PREFIX}coupled_vs_legacy_pressure_delta_pa"]
                ),
                "predicted_net_mass_kg": float(
                    row[f"{PREFIX}predicted_net_mass_kg"]
                ),
                "legacy_net_mass_kg": float(row[f"{PREFIX}legacy_net_mass_kg"]),
                "owner_source_mass_kg": float(
                    row[f"{PREFIX}owner_source_mass_kg"]
                ),
                "owner_source_energy_kj": float(
                    row[f"{PREFIX}owner_source_energy_kj"]
                ),
            }
        )
    return trace


REQUIRED_VERDICTS = (
    "row_counts_match",
    "all_shared_values_identical",
    "only_coupled_solver_columns_added",
    "preview_active",
    "converged_steps_close_their_residual",
    "no_counterflow_violation",
)


def build_audit(
    *, off_csv: Path, on_csv: Path, checkpoint_s: float, room_id: int
) -> dict[str, Any]:
    off_rows = read_csv(off_csv)
    on_rows = read_csv(on_csv)
    isolation = compare_columns(off_rows, on_rows)
    behaviour = solver_behaviour(on_rows, checkpoint_s)
    trace = divergence_trace(on_rows, room_id)
    verdict = {
        "row_counts_match": isolation["off_rows"] == isolation["on_rows"],
        "all_shared_values_identical": (
            isolation["shared_value_difference_count"] == 0
        ),
        "only_coupled_solver_columns_added": (
            isolation["new_columns_all_coupled_solver"]
            and not isolation["missing_on_columns"]
        ),
        "preview_active": behaviour["physical_step_count"] > 0,
        # Every converged step must actually close its own residual. This is the
        # solver's own promise and is separate from how often it converges.
        "converged_steps_close_their_residual": (
            behaviour["max_normalized_residual"] <= RESIDUAL_TOLERANCE
        ),
        "no_counterflow_violation": (
            behaviour["counterflow_violation_count"] == 0.0
        ),
        # Measured, deliberately not gated at H2.
        "converges_every_step": behaviour["failed_step_count"] == 0.0,
        "runtime_authority_ready": False,
    }
    verdict["preview_pass"] = all(verdict[k] for k in REQUIRED_VERDICTS)
    return {
        "checkpoint_s": checkpoint_s,
        "isolation": isolation,
        "solver_behaviour": behaviour,
        "divergence_trace": trace,
        "verdict": verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", default="060")
    parser.add_argument("--checkpoint", type=float, default=None)
    parser.add_argument("--room", type=int, default=0)
    parser.add_argument("--off-csv", type=Path)
    parser.add_argument("--on-csv", type=Path)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    checkpoint = (
        args.checkpoint if args.checkpoint is not None else float(int(args.stage))
    )
    off_csv = args.off_csv or DEFAULT_RUN_ROOT / f"{args.stage}_off" / "sim_log.csv"
    on_csv = args.on_csv or DEFAULT_RUN_ROOT / f"{args.stage}_on" / "sim_log.csv"
    result = build_audit(
        off_csv=off_csv, on_csv=on_csv, checkpoint_s=checkpoint, room_id=args.room
    )
    result["stage"] = args.stage
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["verdict"]["preview_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
