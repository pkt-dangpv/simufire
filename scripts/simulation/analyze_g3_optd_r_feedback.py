#!/usr/bin/env python3
"""Read-only: why the engine's R differs from the offline replay (design section 10).

Compares, for one control case, two switch-ON runs that already exist:

* ``--pre``: the engine BEFORE option D (the trajectory the replay took as
  exogenous to predict R);
* ``--optd``: the engine WITH option D (ledger v3 with the ``optd`` block).

It runs nothing and changes nothing. It separates the difference in final R
into parts that can be measured on the ledgers:

* the same accounting on the same trajectory (replay of the option-D run with
  the engine's own ``flame_drive``) - order of application;
* ``flame_drive`` rebuilt from the 1 s CSV instead of the engine's per-step
  value - reconstruction of an input;
* the O2 mass bound - steps where it reduced a release;
* the trajectory itself (the feedback the exogenous replay ignores), with the
  identity ``R_final = sum(T_s) dt - B`` and the flame on/off cycles.

    python scripts/simulation/analyze_g3_optd_r_feedback.py \
        --pre runs/g3_energy_pre_on_X/o2_closed --optd runs/g3_optd_final_on_Y/o2_closed \
        --o2-min-ref 0.10
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_g3_option_d_contract as ck  # noqa: E402
import replay_g3_option_d as rp  # noqa: E402
from analyze_g3_fuel_ledger import load  # noqa: E402


FUEL_DECAY_FRACTION = 0.15   # CombustionSystem: decay_factor = fuel_fraction / 0.15 below it
SUMMARY_KEYS = ("C_MJ", "B_MJ", "G_MJ", "U_MJ", "release_MJ", "R_final_MJ", "closure_MJ")
CSV_FINAL_KEYS = ("o2_lower", "temp_upper_c", "o2_hrr_factor", "o2_consumed_fire_kg_total",
                  "hrr_kj_total", "fuel_consumed_MJ_total", "retained_unburned_MJ")
fsum = math.fsum


def _ts(row: dict) -> float:
    return (row["flame_target_kw"] + row["smolder_target_kw"]) if row["fire_present_before"] else 0.0


def _mj(kw: float, row: dict) -> float:
    return kw * row["dt_s"] / 1000.0


def _csv_room0(case_dir: Path) -> list[dict]:
    with (case_dir / "sim_log.csv").open(encoding="utf-8-sig", newline="") as handle:
        return [row for row in csv.DictReader(handle) if row["room_id"] == "0"]


def _engine_drive(rows: list[dict]):
    table = {round(row["time_s"], 6): row["optd"]["flame_drive"] for row in rows if row.get("optd")}
    return lambda time_s: table.get(round(time_s, 6), 0.0)


def totals(rows: list[dict]) -> dict:
    burning = [row for row in rows if row["fire_present_before"]]
    out = {
        "C_MJ": fsum(row["consumed_MJ"] for row in burning),
        "B_solid_MJ": fsum(_mj(row["actual_solid_burn_kw"], row) for row in rows),
        "sum_Ts_MJ": fsum(_mj(_ts(row), row) for row in rows),
        "G_MJ": fsum(row["pool_generation_MJ"] for row in burning),
        "heat_above_Ts_MJ": fsum(_mj(max(0.0, row["actual_solid_burn_kw"] - _ts(row)), row) for row in rows),
        "heat_below_Ts_MJ": fsum(_mj(max(0.0, _ts(row) - row["actual_solid_burn_kw"]), row) for row in rows),
    }
    out["U_MJ"] = out["C_MJ"] - out["sum_Ts_MJ"] - out["G_MJ"]
    return out


def net_r(records: list[dict], lo: float, hi: float) -> float:
    return fsum(obj["acc_MJ"] - obj["rel_MJ"]
                for record in records if lo <= record["time_s"] < hi for obj in record["objects"])


def max_step_difference(replayed: list[dict], rows: list[dict]) -> dict:
    worst = {"acc_MJ": 0.0, "rel_MJ": 0.0, "B0_MJ": 0.0, "R_after_MJ": 0.0}
    for record, row in zip(replayed, rows):
        engine = (row.get("optd") or {}).get("objects") or {}
        for obj in record["objects"]:
            if obj["id"] in engine:
                for key in worst:
                    worst[key] = max(worst[key], abs(obj[key] - engine[obj["id"]][key]))
    return worst


def gates(rows: list[dict]) -> dict:
    steps = [row for row in rows if row.get("optd")]
    reasons: dict[str, int] = {}
    for row in steps:
        for obj in row["optd"]["objects"].values():
            reasons[obj["reason"]] = reasons.get(obj["reason"], 0) + 1
    return {
        "steps": len(steps),
        "mass_limited_steps": sum(bool(row["optd"]["mass_limited"]) for row in steps),
        "mass_headroom_min_MJ": min(row["optd"]["mass_headroom_MJ"] for row in steps),
        "filter_excess_above_Ts_MJ": fsum(
            _mj(max(0.0, row["optd"]["request_solid_kw"] - row["optd"]["Ts_kw"]), row) for row in steps),
        "reasons": reasons,
    }


def flame_cycles(rows: list[dict], since_s: float) -> dict:
    """Runs of consecutive steps with / without a flame target, from ``since_s``."""
    runs = {True: [], False: []}
    applied_before_off, applied_after_off, ts_on = [], [], []
    state, length, previous = None, 0.0, None
    for row in rows:
        if row["time_s"] < since_s or not row["fire_present_before"]:
            continue
        flame = row["flame_target_kw"] > 0.0
        if flame:
            ts_on.append(_ts(row))
        if state is None:
            state, length = flame, row["dt_s"]
        elif flame == state:
            length += row["dt_s"]
        else:
            runs[state].append(length)
            if state:
                applied_before_off.append(previous["actual_solid_burn_kw"])
                applied_after_off.append(row["actual_solid_burn_kw"])
            state, length = flame, row["dt_s"]
        previous = row
    if state is not None:
        runs[state].append(length)
    mean = lambda values: fsum(values) / len(values) if values else None  # noqa: E731
    return {
        "flame_off_events": len(applied_before_off),
        "time_on_s": fsum(runs[True]), "time_off_s": fsum(runs[False]),
        "on_run_mean_s": mean(runs[True]), "off_run_mean_s": mean(runs[False]),
        "Ts_mean_while_on_kw": mean(ts_on),
        "applied_before_flame_off_kw": mean(applied_before_off),
        "applied_after_flame_off_kw": mean(applied_after_off),
    }


def upward_variation_kw(rows: list[dict]) -> float:
    total, previous = 0.0, 0.0
    for row in rows:
        total += max(0.0, _ts(row) - previous)
        previous = _ts(row)
    return total


def temperature_channel(rows: list[dict], since_s: float) -> dict:
    """T_s owed to rad_feedback: it only shows while the ideal HRR is below the power cap."""
    heat, steps, at_cap, rad_max = 0.0, 0, 0, 1.0
    for row in rows:
        optd = row.get("optd")
        if not optd or not optd["can_flame"] or row["flame_target_kw"] <= 0.0 or row["time_s"] < since_s:
            continue
        ideal = row["flame_target_kw"] / optd["flame_drive"]
        if ideal >= row["power_cap_kw"] * (1.0 - 1e-9):
            at_cap += 1
            continue
        solid = next(obj for obj in row["objects"] if not obj["is_proxy"])
        decay = min(1.0, solid["remaining_before_MJ"] / row["fire_fuel_energy_MJ"] / FUEL_DECAY_FRACTION)
        rad = ideal / (row["power_cap_kw"] * decay)
        rad_max = max(rad_max, rad)
        heat += _mj(row["flame_target_kw"] * (1.0 - 1.0 / rad), row)
        steps += 1
    return {"flaming_steps_at_cap": at_cap, "flaming_steps_below_cap": steps,
            "rad_feedback_max": rad_max, "Ts_from_rad_feedback_MJ": heat}


def analyze(pre_dir: Path, optd_dir: Path, o2_min_ref: float, late_s: float) -> dict:
    pre = load(pre_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    optd = load(optd_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    if len(pre) != len(optd):
        raise ValueError("the two runs do not have the same number of steps")
    drive_pre = rp._held(rp.flame_drive_series(pre_dir / "sim_log.csv", o2_min_ref))
    drive_optd_csv = rp._held(rp.flame_drive_series(optd_dir / "sim_log.csv", o2_min_ref))

    replay_pre = rp.replay(pre, drive_pre, gate="rate", post="tail")
    replay_optd_csv = rp.replay(optd, drive_optd_csv, gate="rate", post="tail")
    replay_optd_engine = rp.replay(optd, _engine_drive(optd), gate="rate", post="tail")
    engine = ck.records_from_engine(optd)
    summary = {
        "replay_of_pre_csv_drive": rp.summarize(replay_pre),
        "replay_of_optd_csv_drive": rp.summarize(replay_optd_csv),
        "replay_of_optd_engine_drive": rp.summarize(replay_optd_engine),
        "engine_optd": rp.summarize(engine),
    }
    r = {name: item["R_final_MJ"] for name, item in summary.items()}

    split = next(
        (a["time_s"] for a, b in zip(pre, optd)
         if abs(a["actual_solid_burn_kw"] - b["actual_solid_burn_kw"]) > 1e-9 or abs(_ts(a) - _ts(b)) > 1e-9),
        math.inf)
    t_pre, t_optd = totals(pre), totals(optd)
    csv_pre, csv_optd = _csv_room0(pre_dir)[-1], _csv_room0(optd_dir)[-1]
    return {
        "summaries": {name: {key: item[key] for key in SUMMARY_KEYS} for name, item in summary.items()},
        "R_difference_MJ": {
            "engine_minus_replay_of_pre": r["engine_optd"] - r["replay_of_pre_csv_drive"],
            "order_of_application (engine - replay of its own trajectory, engine drive)":
                r["engine_optd"] - r["replay_of_optd_engine_drive"],
            "flame_drive_rebuilt_from_csv (replay engine drive - replay csv drive)":
                r["replay_of_optd_engine_drive"] - r["replay_of_optd_csv_drive"],
            "trajectory (replay of optd - replay of pre, both csv drive)":
                r["replay_of_optd_csv_drive"] - r["replay_of_pre_csv_drive"],
        },
        "max_step_difference_replay_vs_engine": max_step_difference(replay_optd_engine, optd),
        "gates_optd": gates(optd),
        "engine_totals": {"pre": t_pre, "optd": t_optd},
        "identity_R_equals_sumTs_minus_B": {
            "delta_sum_Ts_MJ (optd - pre)": t_optd["sum_Ts_MJ"] - t_pre["sum_Ts_MJ"],
            "delta_B_MJ (engine optd - replay of pre)":
                t_optd["B_solid_MJ"] - summary["replay_of_pre_csv_drive"]["B_MJ"],
            "delta_B_MJ (engine optd - engine pre)": t_optd["B_solid_MJ"] - t_pre["B_solid_MJ"],
        },
        "divergence": {
            "first_step_that_differs_s": split,
            "first_pre_step_with_heat_above_Ts_s": next(
                (row["time_s"] for row in pre if row["actual_solid_burn_kw"] - _ts(row) > 1e-9), None),
            "net_R_before_MJ": {"replay_of_pre": net_r(replay_pre, 0.0, split), "engine_optd": net_r(engine, 0.0, split)},
            "net_R_after_MJ": {"replay_of_pre": net_r(replay_pre, split, math.inf),
                               "engine_optd": net_r(engine, split, math.inf)},
        },
        "flame_cycles_from_late_s": {"late_s": late_s, "pre": flame_cycles(pre, late_s), "optd": flame_cycles(optd, late_s)},
        "Ts_upward_variation_kw": {"pre": upward_variation_kw(pre), "optd": upward_variation_kw(optd)},
        "flame_drive_optd_late": _percentiles(
            [row["optd"]["flame_drive"] for row in optd if row["time_s"] >= late_s and row.get("optd")]),
        "temperature_channel_optd": temperature_channel(optd, split),
        "csv_final": {key: {"pre": csv_pre[key], "optd": csv_optd[key]} for key in CSV_FINAL_KEYS},
    }


def _percentiles(values: list[float]) -> dict:
    values = sorted(values)
    if not values:
        return {}
    pick = lambda q: values[min(len(values) - 1, int(q * len(values)))]  # noqa: E731
    return {"min": values[0], "p10": pick(0.10), "p50": pick(0.50), "p90": pick(0.90), "max": values[-1]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pre", type=Path, required=True, help="case dir of the switch-ON run before option D")
    parser.add_argument("--optd", type=Path, required=True, help="case dir of the switch-ON run with option D")
    parser.add_argument("--o2-min-ref", type=float, required=True,
                        help="fire_o2_min_for_flame of the case (engine 0.122; v7 geometry 0.10)")
    parser.add_argument("--late-s", type=float, default=360.0, help="start of the flame-cycle statistics")
    args = parser.parse_args()
    print(json.dumps(analyze(args.pre, args.optd, args.o2_min_ref, args.late_s), indent=2))


if __name__ == "__main__":
    main()
