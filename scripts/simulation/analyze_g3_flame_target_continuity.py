#!/usr/bin/env python3
"""Read-only comparison of the flame-target continuity controls (design section 13).

Each run is ``o2_closed`` with the G3 switch ON and a different setting of the
diagnostic key ``fire_diag_flame_target_window`` / ``..._jump_fraction``. For
every run it reports flame-offs and their length, target and applied heat,
selected and zonal O2, exterior O2 against the fire's debit, heat, R per cycle
and in total, and the accounting closure; and it checks on the ledger that the
key changed the flame target only inside its window and by the declared line.

It runs no engine and adjusts nothing.

    python scripts/simulation/analyze_g3_flame_target_continuity.py \
        --runs runs/g3_flame_target_continuity_20261001 \
        --optd-control runs/g3_optd_final_on_Y/o2_closed --pre-control runs/g3_energy_pre_on_X/o2_closed
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze_g3_optd_flame_cycles as fc  # noqa: E402
import check_g3_option_d_contract as ck  # noqa: E402
import replay_g3_option_d as rp  # noqa: E402
from analyze_g3_fuel_ledger import load  # noqa: E402


THRESHOLD = fc.CAN_FLAME_DRIVE
LATE_S = (450.0, 900.5)          # fixed before the runs: the engine cycles regularly from 447 s
POWER_S = (600.0, 900.5)
IDENTITY_FILES = (
    "scenario.json", "sim_log.csv", "sim_log.txt", "events.json", "fuel_object_state_snapshot.json",
    "fuel_source_ledger.jsonl", "g3_fuel_ledger_v3.jsonl", "co_inventory_trace.jsonl",
)
fsum = math.fsum


def _median(values: list[float]) -> float | None:
    return sorted(values)[len(values) // 2] if values else None


def _mean(values: list[float]) -> float | None:
    return fsum(values) / len(values) if values else None


def identity(run_dir: Path, control_dir: Path) -> dict:
    out = {}
    for name in IDENTITY_FILES:
        a, b = control_dir / name, run_dir / name
        if not a.exists() or not b.exists():
            out[name] = "missing"
            continue
        same = hashlib.sha256(a.read_bytes()).digest() == hashlib.sha256(b.read_bytes()).digest()
        out[name] = "identical" if same else "DIFFERENT"
    return out


def key_check(rows: list[dict], window: float, jump: float) -> dict:
    """The ledger's own record of the key: where it acted and whether it followed the line."""
    inside = [row for row in rows if "diag_flame_target" in row]
    worst_formula = worst_scale = 0.0
    for row in inside:
        d = row["diag_flame_target"]
        at_threshold = d["smolder_at_threshold_kw"] + d["jump_fraction"] * (
            d["ideal_kw"] * THRESHOLD - d["smolder_at_threshold_kw"])
        at_top = d["ideal_kw"] * (THRESHOLD + d["window"])
        line = at_threshold + (at_top - at_threshold) * (d["flame_drive"] - THRESHOLD) / d["window"]
        worst_formula = max(worst_formula, abs(min(row["pyrolysis_kw"] / row["fuel_scale"], line) - d["target_kw"]))
        worst_scale = max(worst_scale, abs(d["target_kw"] * row["fuel_scale"] - row["flame_target_kw"]))
    drives = [row["diag_flame_target"]["flame_drive"] for row in inside]
    with_drive = [row for row in rows if row.get("optd")]
    should = [row for row in with_drive
              if window > 0.0 and THRESHOLD < row["optd"]["flame_drive"] < THRESHOLD + window]
    return {
        "steps_with_key_record": len(inside),
        "record_drive_range": [min(drives), max(drives)] if drives else None,
        "records_outside_window": sum(1 for d in drives if not THRESHOLD < d < THRESHOLD + window),
        "steps_in_window_by_engine_drive": len(should) if with_drive else None,
        "steps_in_window_without_record": sum(1 for row in should if "diag_flame_target" not in row),
        "max_abs_target_minus_declared_line_kw": worst_formula,
        "max_abs_ledger_target_minus_record_kw": worst_scale,
        "target_lowered_MJ": fsum(
            (row["diag_flame_target"]["original_target_kw"] - row["diag_flame_target"]["target_kw"])
            * row["fuel_scale"] * row["dt_s"] / 1000.0 for row in inside),
        "settings_seen": sorted({(row["diag_flame_target"]["window"], row["diag_flame_target"]["jump_fraction"])
                                 for row in inside}),
        "declared": [window, jump],
    }


def runs_of(flags: list[bool], rows: list[dict]) -> tuple[list[float], list[float]]:
    on, off, length = [], [], 0.0
    for index, row in enumerate(rows):
        if index and flags[index] != flags[index - 1]:
            (on if flags[index - 1] else off).append(length)
            length = 0.0
        length += row["dt_s"]
    if rows:
        (on if flags[-1] else off).append(length)
    return on, off


def measure(run_dir: Path) -> dict:
    rows = load(run_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    v2 = fc._v2(run_dir)
    csv_rows = fc._csv_room0(run_dir)
    scenario = json.loads((run_dir / "scenario.json").read_text(encoding="utf-8"))
    overrides = scenario["engine_overrides"]
    window = float(overrides.get("fire_diag_flame_target_window", 0.0))
    jump = float(overrides.get("fire_diag_flame_target_jump_fraction", 0.0))
    option_d = any(row.get("optd") for row in rows)
    flames = [fc._flame(row) for row in rows]
    offs = [rows[i]["time_s"] for i in range(1, len(rows)) if flames[i - 1] and not flames[i]]
    late = [i for i, row in enumerate(rows) if LATE_S[0] <= row["time_s"] < LATE_S[1]]
    power = [i for i, row in enumerate(rows) if POWER_S[0] <= row["time_s"] < POWER_S[1]]
    on_runs, off_runs = runs_of([flames[i] for i in late], [rows[i] for i in late])
    late_time = fsum(rows[i]["dt_s"] for i in late)
    power_time = fsum(rows[i]["dt_s"] for i in power)
    born = lambda i: fsum(o["acc_MJ"] - o["rel_MJ"] for o in ((rows[i].get("optd") or {}).get("objects") or {}).values())  # noqa: E731
    solid = lambda idx: fsum(rows[i]["actual_solid_burn_kw"] * rows[i]["dt_s"] for i in idx)  # noqa: E731
    target = lambda idx: fsum(fc._ts(rows[i]) * rows[i]["dt_s"] for i in idx)  # noqa: E731
    out = {
        "window": window, "jump_fraction": jump, "option_d": option_d,
        "flame_offs_total": len(offs), "first_flame_off_s": offs[0] if offs else None,
        "late": {
            "interval_s": list(LATE_S),
            "flame_offs": sum(1 for a, b in zip(late, late[1:]) if flames[a] and not flames[b]),
            "time_on_s": fsum(on_runs), "time_off_s": fsum(off_runs),
            "on_run_median_s": _median(on_runs), "on_run_max_s": max(on_runs) if on_runs else None,
            "off_run_median_s": _median(off_runs), "off_run_mean_s": _mean(off_runs),
            "off_run_median_steps": None if not off_runs else round(_median(off_runs) / rows[0]["dt_s"]),
            "R_born_MJ": fsum(born(i) for i in late) if option_d else None,
            "R_rate_kw": fsum(born(i) for i in late) * 1000.0 / late_time if option_d else None,
            "heat_mean_kw": solid(late) / late_time, "target_mean_kw": target(late) / late_time,
            "o2_fire_debit_kg_s": fsum(v2[i]["room_o2_consumed_fire_kg_total_delta"] for i in late) / late_time,
            "o2_exterior_net_kg_s": fsum(v2[i]["room_o2_exterior_net_kg_total_delta"] for i in late) / late_time,
        },
        "power_600_900": {
            "heat_mean_kw": solid(power) / power_time, "target_mean_kw": target(power) / power_time,
            "pyrolysis_mean_kw": fsum(rows[i]["pyrolysis_kw"] * rows[i]["dt_s"] for i in power) / power_time,
            "pool_burn_mean_kw": fsum(rows[i]["actual_pool_burn_kw"] * rows[i]["dt_s"] for i in power) / power_time,
            "exterior_o2_sustains_kw": fsum(v2[i]["room_o2_exterior_net_kg_total_delta"] for i in power)
            / power_time / fc.O2_KG_PER_MJ * 1000.0,
        },
        "heat_solid_MJ": solid(range(len(rows))) / 1000.0,
        "heat_pool_MJ": fsum(row["actual_pool_burn_kw"] * row["dt_s"] / 1000.0 for row in rows),
        "target_integral_MJ": target(range(len(rows))) / 1000.0,
        "consumed_MJ": fsum(row["consumed_MJ"] for row in rows if row["fire_present_before"]),
        "heat_above_target_MJ": fsum(
            max(0.0, row["actual_solid_burn_kw"] - fc._ts(row)) * row["dt_s"] / 1000.0 for row in rows),
        "pool_end_MJ": rows[-1]["pool_after_MJ"],
        "o2_fire_kg": float(csv_rows[-1]["o2_consumed_fire_kg_total"]),
        "peak_hrr_kw": max(float(r["hrr_kw"]) for r in csv_rows),
        "fire_extinguished_s": [row["time_s"] for row in rows if row.get("fire_extinguished_this_step")],
        "csv": {
            str(t): {key: float(min(csv_rows, key=lambda r: abs(float(r["time_s"]) - t))[key])
                     for key in ("o2_lower", "o2_upper", "o2", "temp_upper_c", "o2_hrr_factor", "hrr_kw")}
            for t in (480, 600, 750, 900)
        },
        "o2_selected_range_from_480s": [
            min(float(r["o2_lower"]) for r in csv_rows if float(r["time_s"]) >= 480),
            max(float(r["o2_lower"]) for r in csv_rows if float(r["time_s"]) >= 480)],
        "key_check": key_check(rows, window, jump),
    }
    if option_d:
        engine = rp.summarize(ck.records_from_engine(rows))
        drives = [rows[i]["optd"]["flame_drive"] for i in power if rows[i].get("optd")]
        crossings = sum(
            1 for a, b in zip(rows, rows[1:])
            if a.get("optd") and b.get("optd") and b["time_s"] >= LATE_S[0]
            and (a["optd"]["flame_drive"] > THRESHOLD) != (b["optd"]["flame_drive"] > THRESHOLD))
        per_cycle = []
        accrued = 0.0
        for index in late:
            accrued += born(index)
            if index + 1 < len(rows) and flames[index] and not flames[index + 1]:
                per_cycle.append(accrued)
                accrued = 0.0
        out.update({
            "R_final_MJ": engine["R_final_MJ"], "R_released_MJ": engine["release_MJ"],
            "R_at_450s_MJ": fsum(born(i) for i, row in enumerate(rows) if row["time_s"] < LATE_S[0]),
            "R_per_cycle_median_MJ": _median(per_cycle),
            "G_MJ": engine["G_MJ"], "U_MJ": engine["U_MJ"], "closure_MJ": engine["closure_MJ"],
            "crossings_of_threshold_late": crossings,
            "flame_drive_600_900": {"min": min(drives), "mean": _mean(drives), "max": max(drives)},
            "contract_violations": {name: len(v) for name, v in ck.run_all(ck.records_from_engine(rows)).items() if v},
        })
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=Path, required=True, help="directory holding <label>/o2_closed")
    parser.add_argument("--optd-control", type=Path, required=True)
    parser.add_argument("--pre-control", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    report = {"controls": {"optd": measure(args.optd_control), "pre": measure(args.pre_control)}, "runs": {}, "identity": {}}
    for case_dir in sorted(args.runs.glob("*/o2_closed")):
        label = case_dir.parent.name
        report["runs"][label] = measure(case_dir)
        if label.startswith("D0"):
            report["identity"][label] = identity(case_dir, args.optd_control)
        if label.startswith("P0"):
            report["identity"][label] = identity(case_dir, args.pre_control)
    if args.out is not None:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
