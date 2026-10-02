#!/usr/bin/env python3
"""Read-only comparison of the ``o2_closed`` rise-tau diagnostic with its controls.

Four switch-ON runs of the same scenario: the engine before option D and the
engine with option D, each at the control ``fire_hrr_rise_tau_s`` (6 s) and at
the diagnostic value. Reports what changed per cycle and in total, and the
on-run length that the O2 balance predicts for each run:

    0.076 * T_s * [L - tau (1 - exp(-L / tau))] = exterior_O2_rate * (L + dt)

It runs no engine and adjusts nothing.

    python scripts/simulation/analyze_g3_rise_tau_diagnostic.py \
        --pre-control runs/g3_energy_pre_on_X/o2_closed --optd-control runs/g3_optd_final_on_Y/o2_closed \
        --pre-diag runs/DIAG/onpre_tau3/o2_closed --optd-diag runs/DIAG/optd_tau3/o2_closed \
        --diag-rise-tau-s 3 --o2-min-ref 0.10 --out runs/DIAG/analysis
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze_g3_optd_flame_cycles as fc  # noqa: E402
import check_g3_option_d_contract as ck  # noqa: E402
import replay_g3_option_d as rp  # noqa: E402
from analyze_g3_fuel_ledger import load  # noqa: E402


CONTROL_RISE_TAU_S = 6.0
RISE_FACTOR = 1.8            # CombustionSystem: rise tau = fire_hrr_rise_tau_s * 1.8 without ventilation response
REGULAR_FROM_CYCLE = 1       # the first cycle burns the O2 stored during the first long flame-off
fsum = math.fsum


def _median(values: list[float]) -> float | None:
    return sorted(values)[len(values) // 2] if values else None


def filter_residual_kw(rows: list[dict], tau_s: float) -> float:
    """Largest gap between the engine's solid request and a first-order rise of ``tau_s``."""
    worst, previous = 0.0, 0.0
    for row in rows:
        optd, target = row.get("optd"), row["hrr_requested_kw"]
        tau = tau_s if target > previous else rp.FALL_TAU_S
        filtered = previous + (target - previous) * (1.0 - math.exp(-row["dt_s"] / tau))
        if optd and target > 0.0:
            worst = max(worst, abs((filtered - row["actual_pool_burn_kw"]) - optd["request_solid_kw"]))
        previous = row["hrr_applied_kw"]
    return worst


def balance_on_run_s(target_kw: float, supply_kg_s: float, tau_s: float, dt: float) -> float:
    """Length of the on-run at which the fire's O2 debit equals the exterior O2 supplied."""
    low, high = 1e-6, 600.0
    for _ in range(80):
        middle = 0.5 * (low + high)
        debit = fc.O2_KG_PER_MJ * target_kw / 1000.0 * (middle - tau_s * (1.0 - math.exp(-middle / tau_s)))
        if debit < supply_kg_s * (middle + dt):
            low = middle
        else:
            high = middle
    return 0.5 * (low + high)


def common(case_dir: Path, rows: list[dict]) -> dict:
    csv_rows = fc._csv_room0(case_dir)
    late = [r for r in csv_rows if float(r["time_s"]) >= 480.0]
    peak = max(csv_rows, key=lambda r: float(r["hrr_kw"]))
    flames = [fc._flame(row) for row in rows]
    burning = [row for row in rows if row["fire_present_before"]]
    solid = fsum(row["actual_solid_burn_kw"] * row["dt_s"] / 1000.0 for row in rows)
    target = fsum(fc._ts(row) * row["dt_s"] / 1000.0 for row in rows)
    return {
        "peak_hrr_kw": float(peak["hrr_kw"]), "peak_hrr_time_s": float(peak["time_s"]),
        "peak_temp_upper_c": max(float(r["temp_upper_c"]) for r in csv_rows),
        "flame_off_events": sum(1 for was, now in zip(flames, flames[1:]) if was and not now),
        "first_flame_off_s": next((row["time_s"] for row, was, now in zip(rows[1:], flames, flames[1:]) if was and not now), None),
        "heat_solid_MJ": solid, "target_integral_MJ": target,
        "consumed_MJ": fsum(row["consumed_MJ"] for row in burning),
        "heat_above_target_MJ": fsum(max(0.0, row["actual_solid_burn_kw"] - fc._ts(row)) * row["dt_s"] / 1000.0 for row in rows),
        "o2_fire_kg": float(csv_rows[-1]["o2_consumed_fire_kg_total"]),
        "o2_selected_from_480s": [min(float(r["o2_lower"]) for r in late), max(float(r["o2_lower"]) for r in late)],
        "o2_upper_480_900": [float(late[0]["o2_upper"]), float(late[-1]["o2_upper"])],
        "o2_room_480_900": [float(late[0]["o2"]), float(late[-1]["o2"])],
        "temp_upper_480_900_c": [float(late[0]["temp_upper_c"]), float(late[-1]["temp_upper_c"])],
    }


def pre_branch(case_dir: Path, since_s: float = 360.0) -> dict:
    rows = load(case_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    out = common(case_dir, rows)
    window = [row for row in rows if row["time_s"] >= since_s]
    flames = [fc._flame(row) for row in window]
    on_runs, off_runs, run = [], [], 0.0
    for index, row in enumerate(window):
        if index and flames[index] != flames[index - 1]:
            (on_runs if flames[index - 1] else off_runs).append(run)
            run = 0.0
        run += row["dt_s"]
    (on_runs if flames[-1] else off_runs).append(run)
    out.update({
        "since_s": since_s,
        "flame_offs_since": sum(1 for was, now in zip(flames, flames[1:]) if was and not now),
        "on_run_mean_s": fsum(on_runs) / len(on_runs) if on_runs else None,
        "off_run_mean_s": fsum(off_runs) / len(off_runs) if off_runs else None,
        "time_on_s": fsum(on_runs), "time_off_s": fsum(off_runs),
    })
    return out


def optd_branch(case_dir: Path, o2_min: float, rise_tau_s: float) -> tuple[dict, list[dict]]:
    tau = rise_tau_s * RISE_FACTOR
    branch = fc._branch(case_dir)
    rows, v2 = branch["rows"], branch["v2"]
    out = common(case_dir, rows)
    first_off = out["first_flame_off_s"]
    selected = fc.selected_o2_per_step(rows, branch["csv"], o2_min, first_off - 60.0)
    items = fc.cycles(rows, v2, selected, first_off - 1.0)
    regular = [c for c in items[REGULAR_FROM_CYCLE:] if c["drive_at_off"] is not None]
    start_s, end_s = items[1]["t_on_s"], rows[-1]["time_s"] + rows[-1]["dt_s"]
    reference = fc.engine_reference(rows, start_s, end_s)
    supply = fc.supply_means(rows, v2, start_s)
    supply_mean = fsum(v for _, v in supply) / len(supply)
    engine = rp.summarize(ck.records_from_engine(rows))
    born_before = branch["balance"][next(i for i, row in enumerate(rows) if row["time_s"] >= first_off) - 1]
    median_target = _median([c["target_on_kw"] for c in regular])
    full_target = [c for c in regular if c["target_on_kw"] >= 0.99 * max(x["target_on_kw"] for x in regular)]
    out.update({
        "rise_tau_effective_s": tau,
        "filter_residual_kw_with_this_tau": filter_residual_kw(rows, tau),
        "filter_residual_kw_with_control_tau": filter_residual_kw(rows, CONTROL_RISE_TAU_S * RISE_FACTOR),
        "first_reignition_s": items[0]["t_on_s"],
        "cycles": len(items),
        "R_before_first_flame_off_MJ": born_before,
        "R_final_MJ": branch["balance"][-1],
        "R_born_in_cycles_MJ": fsum(c["R_accrued_MJ"] for c in items),
        "R_released_MJ": engine["release_MJ"],
        "R_first_cycle_MJ": items[0]["R_accrued_MJ"], "first_cycle_on_s": items[0]["on_s"],
        "since_second_reignition": {
            "start_s": start_s, "flame_offs": reference["flame_offs"], "R_born_MJ": reference["R_born_MJ"],
            "R_rate_kw": reference["R_born_MJ"] * 1000.0 / (end_s - start_s),
            "heat_MJ": reference["heat_MJ"], "heat_mean_kw": reference["heat_MJ"] * 1000.0 / (end_s - start_s),
            "on_run_median_s": reference["on_run_median_s"],
            "off_run_median_steps": reference["off_run_median_steps"],
            "time_on_s": reference["time_on_s"], "time_off_s": reference["time_off_s"],
        },
        "full_target_cycles": {
            "count": len(full_target),
            "target_on_kw": _median([c["target_on_kw"] for c in full_target]),
            "on_run_median_s": _median([c["on_s"] for c in full_target]),
            "R_per_cycle_median_MJ": _median([c["R_accrued_MJ"] for c in full_target]),
            "applied_peak_median_kw": _median([c["applied_peak_kw"] for c in full_target]),
        },
        "R_per_cycle_median_MJ": _median([c["R_accrued_MJ"] for c in regular]),
        "target_on_median_kw": median_target,
        "o2_debit_over_exterior_median": _median(
            [c["o2_fire_debit_kg"] / c["o2_exterior_net_kg"] for c in regular if c["o2_exterior_net_kg"] > 0.0]),
        "drive_at_off": [min(c["drive_at_off"] for c in regular), max(c["drive_at_off"] for c in regular)],
        "drive_at_on": [min(c["drive_at_on"] for c in regular), max(c["drive_at_on"] for c in regular)],
        "o2_selected_swing_median": _median([c["o2_selected_swing"] for c in regular if c["o2_selected_swing"] is not None]),
        "exterior_o2_rate_kg_s": supply_mean,
        "exterior_o2_sustains_kw": supply_mean / fc.O2_KG_PER_MJ * 1000.0,
        "balance_on_run_s_at_full_target": balance_on_run_s(
            max(c["target_on_kw"] for c in regular), supply_mean, tau, rows[0]["dt_s"]),
        "G_MJ": engine["G_MJ"], "U_MJ": engine["U_MJ"], "closure_MJ": engine["closure_MJ"],
    })
    return out, items


def first_difference_s(a_dir: Path, b_dir: Path) -> float | None:
    a = load(a_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    b = load(b_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    return next((x["time_s"] for x, y in zip(a, b)
                 if abs(x["hrr_applied_kw"] - y["hrr_applied_kw"]) > 1e-9 or abs(fc._ts(x) - fc._ts(y)) > 1e-9), None)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ("pre-control", "optd-control", "pre-diag", "optd-diag"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--diag-rise-tau-s", type=float, required=True)
    parser.add_argument("--o2-min-ref", type=float, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    optd_control, control_items = optd_branch(args.optd_control, args.o2_min_ref, CONTROL_RISE_TAU_S)
    optd_diag, diag_items = optd_branch(args.optd_diag, args.o2_min_ref, args.diag_rise_tau_s)
    report = {
        "diag_rise_tau_s": args.diag_rise_tau_s,
        "first_step_that_differs_s": {
            "optd control vs diag": first_difference_s(args.optd_control, args.optd_diag),
            "pre control vs diag": first_difference_s(args.pre_control, args.pre_diag),
            "pre diag vs optd diag": first_difference_s(args.pre_diag, args.optd_diag),
        },
        "optd_control": optd_control, "optd_diag": optd_diag,
        "pre_control": pre_branch(args.pre_control), "pre_diag": pre_branch(args.pre_diag),
    }
    if args.out is not None:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        for name, items in (("cycles_optd_control.csv", control_items), ("cycles_optd_diag.csv", diag_items)):
            with (args.out / name).open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(items[0]))
                writer.writeheader()
                writer.writerows(items)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
