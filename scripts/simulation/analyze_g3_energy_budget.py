#!/usr/bin/env python3
"""Read-only decomposition of G3 solid-fuel and retained-pool energy.

This is an accounting diagnostic, not a new combustion law. In particular,
``solid_unreleased_MJ`` is *not* assumed to be stored gas: the current engine
does not carry an inventory for the HRR smoothing delay.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from analyze_g3_fuel_ledger import load


def _number(row: dict, key: str, *, default: float | None = None) -> float:
    value = float(row[key] if key in row else default)
    if not math.isfinite(value):
        raise ValueError(f"nonfinite {key} at t={row.get('time_s')}")
    return value


def step_budget(row: dict) -> dict[str, float]:
    dt = _number(row, "dt_s")
    if dt <= 0.0:
        raise ValueError("dt_s must be positive")
    consumed = _number(row, "consumed_MJ")
    if consumed > 0.0 and any(
        key not in row
        for key in ("pyrolysis_kw", "flame_target_kw", "smolder_target_kw")
    ):
        raise ValueError("positive fuel debit without pyrolysis/target observation")
    pyrolysis = _number(row, "pyrolysis_kw", default=0.0) * dt / 1000.0
    solid_release = _number(row, "actual_solid_burn_kw") * dt / 1000.0
    pool_release = _number(row, "actual_pool_burn_kw") * dt / 1000.0
    pool_generation = _number(row, "pool_generation_MJ")
    target = (
        _number(row, "flame_target_kw", default=0.0)
        + _number(row, "smolder_target_kw", default=0.0)
    ) * dt / 1000.0
    target_gap = consumed - target - pool_generation
    smoothing_gap = target - solid_release
    solid_unreleased = consumed - solid_release - pool_generation
    return {
        "consumed_MJ": consumed,
        "pyrolysis_MJ": pyrolysis,
        "solid_release_MJ": solid_release,
        "pool_generation_MJ": pool_generation,
        "pool_release_MJ": pool_release,
        "target_gap_MJ": target_gap,
        "smoothing_gap_MJ": smoothing_gap,
        "solid_unreleased_MJ": solid_unreleased,
        "decomposition_residual_MJ": solid_unreleased - target_gap - smoothing_gap,
        "pyrolysis_debit_residual_MJ": pyrolysis - consumed,
        # Includes the engine's decay/backdraft terms; they are not yet
        # separately observed, so do not call this a numerical closure.
        "pool_other_reduction_MJ": (
            _number(row, "pool_before_MJ") + pool_generation - pool_release
            - _number(row, "pool_after_MJ")
        ),
    }


def summarize(rows: list[dict]) -> dict:
    if not rows:
        raise ValueError("no ledger rows")
    budgets = [step_budget(row) for row in rows]
    keys = budgets[0].keys()
    total = {key: math.fsum(row[key] for row in budgets) for key in keys}
    total["steps"] = len(rows)
    total["peak_positive_smoothing_gap_MJ"] = max(
        row["smoothing_gap_MJ"] for row in budgets
    )
    total["peak_negative_smoothing_gap_MJ"] = min(
        row["smoothing_gap_MJ"] for row in budgets
    )
    total["max_step_decomposition_residual_MJ"] = max(
        abs(row["decomposition_residual_MJ"]) for row in budgets
    )
    total["max_step_pyrolysis_debit_residual_MJ"] = max(
        abs(row["pyrolysis_debit_residual_MJ"]) for row in budgets
    )
    total["pool_before_MJ"] = _number(rows[0], "pool_before_MJ")
    total["pool_after_MJ"] = _number(rows[-1], "pool_after_MJ")
    return total


def filter_attribution(
    rows: list[dict], *, rise_tau_s: float, fall_tau_s: float
) -> dict[str, float]:
    """Attribute ``T - B`` to the asymmetric first-order HRR filter.

    Rebuilds the unclamped filter output ``y_f = y + (T - y)(1 - exp(-dt/tau))``
    from the previous applied HRR ``y`` and the requested target ``T``, with
    ``tau`` = rise or fall constant. Exact algebra per step:
    ``T - B = (T - y_f) + (y_f - B)``; the first term is the filter lag (split by
    rise/fall), the second the explicit_objects clamp (0 in legacy). Only valid
    when the rise constant is fixed (``ventilation_response_factor`` = 0); the
    caller must check ``max_abs_legacy_filter_error_kw`` on a legacy run.
    """
    if rise_tau_s <= 0.0 or fall_tau_s <= 0.0:
        raise ValueError("filter time constants must be positive")
    if not rows:
        raise ValueError("no ledger rows")
    applied_before = 0.0
    rise = fall = clamp = 0.0
    peak_kw = 0.0
    max_error_kw = 0.0
    for row in rows:
        dt = _number(row, "dt_s")
        target_kw = _number(row, "hrr_requested_kw")
        applied_kw = _number(row, "hrr_applied_kw")
        pool_kw = _number(row, "actual_pool_burn_kw")
        tau = rise_tau_s if target_kw > applied_before else fall_tau_s
        filtered_kw = applied_before + (target_kw - applied_before) * (
            1.0 - math.exp(-dt / tau)
        )
        lag_MJ = (target_kw - filtered_kw) * dt / 1000.0
        if target_kw > applied_before:
            rise += lag_MJ
        else:
            fall += lag_MJ
        clamp += (filtered_kw - applied_kw) * dt / 1000.0
        if not row.get("switch_on", False) and pool_kw == 0.0:
            max_error_kw = max(max_error_kw, abs(filtered_kw - applied_kw))
        peak_kw = max(peak_kw, applied_kw)
        applied_before = applied_kw
    dt0 = _number(rows[0], "dt_s")
    return {
        "rise_lag_MJ": rise,
        "fall_excess_MJ": fall,
        "clamp_removed_MJ": clamp,
        "peak_applied_kw": peak_kw,
        "final_applied_kw": applied_before,
        # Discrete effective constants: over a monotone ramp, sum((T - y_f) dt)
        # equals tau_eff * (ramp height), tau_eff = dt / (e^{dt/tau} - 1).
        "rise_tau_eff_s": dt0 / math.expm1(dt0 / rise_tau_s),
        "fall_tau_eff_s": dt0 / math.expm1(dt0 / fall_tau_s),
        "max_abs_legacy_filter_error_kw": max_error_kw,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("--room", type=int, default=0)
    args = parser.parse_args()
    output = {}
    for path in sorted(args.run_root.glob("*/g3_fuel_ledger_v3.jsonl")):
        output[path.parent.name] = summarize(load(path, room_id=args.room))
    if not output:
        raise ValueError(f"no G3 ledger files under {args.run_root}")
    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
