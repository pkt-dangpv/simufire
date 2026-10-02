#!/usr/bin/env python3
"""Read-only: flame on/off cycles of an O2-limited room under option D (design section 11).

Works on two existing switch-ON runs of the same case: ``--pre`` (engine before
option D) and ``--optd`` (engine with option D). It runs no engine and changes
no physics. Three things:

1. **Timeline** common to both branches (1 s rows): selected and zonal O2,
   ``flame_drive``, crossings of the ``can_flame`` threshold, target, applied
   heat, O2 debit and exterior O2, R accrual/release, temperatures.
2. **Cycles** of the option-D run: how much R is born in each one.
3. **Controls**, declared before running them in
   ``runs/g3_flame_cycle_control_20261001/PREDECLARATION.md``:

   * A - the engine's own accounting (``replay_g3_option_d``) with the measured
     ``flame_drive`` as a fixed input, lifted just above the threshold so it
     never crosses it. Open loop.
   * B - a closed-loop harness: engine equations on the fire side, an O2
     excess integrator fed by the measured exterior O2 (60 s means) on the
     other. No fitted parameter. Interventions: no reset, continuous target,
     frozen O2, half the time step.

The harness is not the engine: what it shows about the engine is limited by
how well it reproduces the engine's own runs, which it reports.

    python scripts/simulation/analyze_g3_optd_flame_cycles.py \
        --pre runs/g3_energy_pre_on_X/o2_closed --optd runs/g3_optd_final_on_Y/o2_closed \
        --optd-half-dt runs/g3_optd_final_on_Y/o2_closed_dt24 --o2-min-ref 0.10 --out runs/out_dir
"""

from __future__ import annotations

import argparse
import copy
import csv
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_g3_option_d_contract as ck  # noqa: E402
import replay_g3_option_d as rp  # noqa: E402
from analyze_g3_fuel_ledger import load  # noqa: E402


CAN_FLAME_DRIVE = rp.CAN_FLAME_DRIVE     # can_flame = flame_drive > 0.08
O2_KG_PER_MJ = 0.076                     # FireModel.o2_consumption_kg_per_MJ
O2_NOMINAL = 0.209                       # FireModel.o2_nominal
O2_FACTOR_RISE_TAU_S, O2_FACTOR_FALL_TAU_S = 14.0, 32.0   # fire_o2_hrr_{rise,fall}_tau_s
FUEL_DECAY_FRACTION = 0.15               # decay_factor = fuel_fraction / 0.15 below it
SUPPLY_WINDOW_S = 60.0
fsum = math.fsum


def _ts(row: dict) -> float:
    return (row["flame_target_kw"] + row["smolder_target_kw"]) if row["fire_present_before"] else 0.0


def _flame(row: dict) -> bool:
    return bool(row["fire_present_before"]) and row["flame_target_kw"] > 0.0


def _v2(case_dir: Path) -> list[dict]:
    rows = [json.loads(line) for line in (case_dir / "fuel_source_ledger.jsonl").open(encoding="utf-8")]
    return [row for row in rows if row["room_id"] == 0]


def _csv_room0(case_dir: Path) -> list[dict]:
    with (case_dir / "sim_log.csv").open(encoding="utf-8-sig", newline="") as handle:
        return [row for row in csv.DictReader(handle) if row["room_id"] == "0"]


def _r_net(row: dict) -> tuple[float, float]:
    objects = (row.get("optd") or {}).get("objects") or {}
    return fsum(o["acc_MJ"] for o in objects.values()), fsum(o["rel_MJ"] for o in objects.values())


# --------------------------------------------------------------------------
# Selected O2 per step, from the engine's own flame_drive
# --------------------------------------------------------------------------

def _flame_possible(x: float, o2_min: float) -> float:
    return min(1.0, max(0.0, (x - (o2_min - 0.015)) / 0.040))


def _factor_next(previous: float, x: float, dt: float, o2_min: float) -> float:
    target = 0.0 if x <= o2_min else min(1.0, (x - o2_min) / (O2_NOMINAL - o2_min))
    tau = O2_FACTOR_RISE_TAU_S if target >= previous else O2_FACTOR_FALL_TAU_S
    return previous + (target - previous) * (1.0 - math.exp(-dt / tau))


def selected_o2_per_step(rows: list[dict], csv_rows: list[dict], o2_min: float, since_s: float) -> dict[int, float]:
    """Invert ``flame_drive = o2_hrr_factor(x) * flame_possible(x)`` step by step.

    Valid while the sub-ventilated O2 floor is inactive (upper layer below its
    start temperature), which holds from ``since_s`` on in the closed room.
    """
    # Seed o2_hrr_factor from the first CSV row at or after since_s; the CSV is
    # written after its step, so the reconstruction starts on the next one.
    seed = next(r for r in csv_rows if float(r["time_s"]) >= since_s)
    start = 1 + min(range(len(rows)), key=lambda i: abs(rows[i]["time_s"] - float(seed["time_s"])))
    factor = float(seed["o2_hrr_factor"])
    selected: dict[int, float] = {}
    for index in range(start, len(rows)):
        row = rows[index]
        drive = row["optd"]["flame_drive"]
        low, high = o2_min - 0.015, O2_NOMINAL
        for _ in range(60):
            middle = 0.5 * (low + high)
            if _factor_next(factor, middle, row["dt_s"], o2_min) * _flame_possible(middle, o2_min) < drive:
                low = middle
            else:
                high = middle
        selected[index] = 0.5 * (low + high)
        factor = _factor_next(factor, selected[index], row["dt_s"], o2_min)
    return selected


# --------------------------------------------------------------------------
# Timeline (1 s) and cycles
# --------------------------------------------------------------------------

def timeline(pre: dict, optd: dict, o2_min: float) -> list[dict]:
    out = []
    for second in range(int(optd["csv"][-1]["time_s_float"]) + 1):
        record = {"time_s": second}
        for name, branch in (("pre", pre), ("optd", optd)):
            steps = branch["by_second"].get(second, [])
            csv_row = branch["csv_by_second"].get(second)
            rows, v2 = branch["rows"], branch["v2"]
            flames = [_flame(rows[i]) for i in steps]
            previous = [_flame(rows[i - 1]) if i else False for i in steps]
            duration = fsum(rows[i]["dt_s"] for i in steps) or 1.0
            if name == "optd":
                drives = [rows[i]["optd"]["flame_drive"] for i in steps if rows[i].get("optd")]
                drive = drives[-1] if drives else None
            else:
                drive = None if csv_row is None else float(csv_row["o2_hrr_factor"]) * _flame_possible(
                    float(csv_row["o2_lower"]), o2_min)
            record.update({
                f"{name}_o2_selected": None if csv_row is None else float(csv_row["o2_lower"]),
                f"{name}_o2_upper": None if csv_row is None else float(csv_row["o2_upper"]),
                f"{name}_o2_room": None if csv_row is None else float(csv_row["o2"]),
                f"{name}_flame_drive": drive,
                f"{name}_can_flame_fraction": (sum(flames) / len(flames)) if flames else None,
                f"{name}_flame_off_events": sum(1 for was, now in zip(previous, flames) if was and not now),
                f"{name}_flame_on_events": sum(1 for was, now in zip(previous, flames) if now and not was),
                f"{name}_target_kw": fsum(_ts(rows[i]) * rows[i]["dt_s"] for i in steps) / duration,
                f"{name}_applied_kw": fsum(rows[i]["hrr_applied_kw"] * rows[i]["dt_s"] for i in steps) / duration,
                f"{name}_o2_fire_debit_kg": fsum(v2[i]["room_o2_consumed_fire_kg_total_delta"] for i in steps),
                f"{name}_o2_exterior_net_kg": fsum(v2[i]["room_o2_exterior_net_kg_total_delta"] for i in steps),
                f"{name}_R_accrued_MJ": fsum(branch["acc"][i] for i in steps),
                f"{name}_R_released_MJ": fsum(branch["rel"][i] for i in steps),
                f"{name}_R_MJ": branch["balance"][steps[-1]] if steps else None,
                f"{name}_temp_upper_c": None if csv_row is None else float(csv_row["temp_upper_c"]),
                f"{name}_temp_lower_c": None if csv_row is None else float(csv_row["temp_lower_c"]),
            })
        out.append(record)
    return out


def cycles(rows: list[dict], v2: list[dict], selected: dict[int, float], since_s: float) -> list[dict]:
    """One record per flame-on run plus the flame-off run that follows it."""
    index = next(i for i, row in enumerate(rows) if row["time_s"] >= since_s and row["fire_present_before"]
                 and not _flame(row))
    while index < len(rows) and not _flame(rows[index]):
        index += 1
    out = []
    while index < len(rows):
        on_start = index
        while index < len(rows) and _flame(rows[index]):
            index += 1
        off_start = index
        while index < len(rows) and not _flame(rows[index]):
            index += 1
        on, both = range(on_start, off_start), range(on_start, index)
        accrued, released = zip(*(_r_net(rows[i]) for i in both))
        xs = [selected[i] for i in both if i in selected]
        out.append({
            "t_on_s": rows[on_start]["time_s"],
            "on_s": fsum(rows[i]["dt_s"] for i in on),
            "off_s": fsum(rows[i]["dt_s"] for i in range(off_start, index)),
            "off_steps": index - off_start,
            "R_accrued_MJ": fsum(accrued),
            "R_accrued_while_on_MJ": fsum(_r_net(rows[i])[0] for i in on),
            "R_released_MJ": fsum(released),
            "target_on_kw": fsum(_ts(rows[i]) for i in on) / len(on),
            "applied_peak_kw": max(rows[i]["hrr_applied_kw"] for i in both),
            "heat_MJ": fsum(rows[i]["hrr_applied_kw"] * rows[i]["dt_s"] / 1000.0 for i in both),
            "o2_fire_debit_kg": fsum(v2[i]["room_o2_consumed_fire_kg_total_delta"] for i in both),
            "o2_exterior_net_kg": fsum(v2[i]["room_o2_exterior_net_kg_total_delta"] for i in both),
            "drive_at_on": rows[on_start]["optd"]["flame_drive"],
            "drive_at_off": rows[off_start]["optd"]["flame_drive"] if off_start < len(rows) else None,
            "o2_selected_swing": (max(xs) - min(xs)) if xs else None,
        })
    return out


def cycle_summary(items: list[dict]) -> dict:
    def quantiles(values):
        values = sorted(values)
        pick = lambda q: values[min(len(values) - 1, int(q * len(values)))]  # noqa: E731
        return {"min": values[0], "p25": pick(0.25), "median": pick(0.5), "p75": pick(0.75), "max": values[-1]}

    offs = [c["drive_at_off"] for c in items if c["drive_at_off"] is not None]
    return {
        "cycles": len(items),
        "first_reignition_s": items[0]["t_on_s"],
        "R_accrued_MJ": fsum(c["R_accrued_MJ"] for c in items),
        "R_accrued_while_on_MJ": fsum(c["R_accrued_while_on_MJ"] for c in items),
        "R_released_MJ": fsum(c["R_released_MJ"] for c in items),
        "R_per_cycle_MJ": quantiles([c["R_accrued_MJ"] for c in items]),
        "on_run_s": quantiles([c["on_s"] for c in items]),
        "off_run_steps": quantiles([c["off_steps"] for c in items if c["drive_at_off"] is not None]),
        "drive_at_on": {"min": min(c["drive_at_on"] for c in items), "max": max(c["drive_at_on"] for c in items)},
        "drive_at_off": {"min": min(offs), "max": max(offs)},
        "o2_fire_debit_over_exterior_net": quantiles(
            [c["o2_fire_debit_kg"] / c["o2_exterior_net_kg"] for c in items if c["o2_exterior_net_kg"] > 0.0]),
        "closed_form_rise_lag_MJ": fsum(
            c["target_on_kw"] * rp.RISE_TAU_S * (1.0 - math.exp(-c["on_s"] / rp.RISE_TAU_S)) / 1000.0 for c in items),
    }


# --------------------------------------------------------------------------
# Control A: engine accounting, measured flame_drive lifted above the threshold
# --------------------------------------------------------------------------

def control_a(rows: list[dict], since_s: float) -> dict:
    engine_drive = {round(row["time_s"], 6): row["optd"]["flame_drive"] for row in rows if row.get("optd")}
    lifted_rows = copy.deepcopy(rows)
    floor = CAN_FLAME_DRIVE + 1e-9
    ideal = None
    changed, largest = 0, 0.0
    for row in lifted_rows:
        optd = row.get("optd")
        if not optd:
            continue
        if _flame(row):
            ideal = row["flame_target_kw"] / optd["flame_drive"]
        if row["time_s"] < since_s or optd["flame_drive"] >= floor or ideal is None:
            continue
        largest = max(largest, floor - optd["flame_drive"])
        target = ideal * floor
        row["flame_target_kw"], row["smolder_target_kw"] = target, 0.0
        row["hrr_requested_kw"] = target + row["actual_pool_burn_kw"]
        row["pyrolysis_kw"] = max(row["pyrolysis_kw"], target)
        for obj in row["objects"]:
            if not obj["is_proxy"]:
                obj["state_before"] = "flaming"
        engine_drive[round(row["time_s"], 6)] = floor
        changed += 1

    def born(replayed: list[dict]) -> float:
        return fsum(o["acc_MJ"] - o["rel_MJ"] for rec in replayed if rec["time_s"] >= since_s for o in rec["objects"])

    drive_at = lambda t: engine_drive.get(round(t, 6), 0.0)  # noqa: E731
    measured = {round(row["time_s"], 6): row["optd"]["flame_drive"] for row in rows if row.get("optd")}
    baseline = rp.replay(rows, lambda t: measured.get(round(t, 6), 0.0), gate="rate", post="tail")
    lifted = rp.replay(lifted_rows, drive_at, gate="rate", post="tail")
    return {
        "since_s": since_s, "steps_lifted": changed, "largest_lift_of_flame_drive": largest,
        "R_born_measured_drive_MJ": born(baseline), "R_born_lifted_drive_MJ": born(lifted),
        "R_attributable_to_crossings_MJ": born(baseline) - born(lifted),
        "applied_heat_lifted_MJ": fsum(rec["applied_kw"] * rec["dt_s"] / 1000.0 for rec in lifted if rec["time_s"] >= since_s),
        "applied_heat_measured_MJ": fsum(rec["applied_kw"] * rec["dt_s"] / 1000.0 for rec in baseline if rec["time_s"] >= since_s),
    }


# --------------------------------------------------------------------------
# Control B: closed-loop harness
# --------------------------------------------------------------------------

def supply_means(rows: list[dict], v2: list[dict], since_s: float) -> list[tuple[float, float]]:
    """Exterior net O2 (kg/s) as means over windows of SUPPLY_WINDOW_S from ``since_s``."""
    windows: dict[int, list[float]] = {}
    for row, book in zip(rows, v2):
        if row["time_s"] < since_s:
            continue
        key = int((row["time_s"] - since_s) // SUPPLY_WINDOW_S)
        item = windows.setdefault(key, [0.0, 0.0])
        item[0] += book["room_o2_exterior_net_kg_total_delta"]
        item[1] += row["dt_s"]
    return [(since_s + key * SUPPLY_WINDOW_S, kg / seconds) for key, (kg, seconds) in sorted(windows.items())]


def harness(
    *, dt: float, start_s: float, end_s: float, supply: list[tuple[float, float]],
    off_target_kw: float, remaining_MJ: float, fuel_energy_MJ: float, power_cap_kw: float,
    reset: bool = True, frozen_o2: bool = False, continuous_mass_kg: float | None = None,
    drive_slope_per_o2: float = 0.0,
) -> dict:
    """Fire side of the engine closed over an O2 excess integrator.

    ``reset``: option D's ``B0 = min(filter, T_s)``; without it the applied
    heat is the filter output, as before option D.
    ``continuous_mass_kg``: no threshold; ``flame_drive`` varies linearly with
    the O2 excess, ``d(drive)/d(o2 fraction) = drive_slope_per_o2`` over a zone
    of that mass.
    """
    excess_kg = 1e-12          # just above the threshold: the flame has just come back
    applied_kw = off_target_kw
    time_s = start_s
    flame_before = False
    offs = ons = 0
    on_runs, off_runs, run = [], [], 0.0
    r_born = heat = target_integral = 0.0
    last_quarter_heat = last_quarter_time = 0.0
    while time_s < end_s - 1e-9:
        rate = next((value for begin, value in reversed(supply) if time_s >= begin - 1e-9), supply[0][1])
        decay = min(1.0, (remaining_MJ / fuel_energy_MJ) / FUEL_DECAY_FRACTION)
        ideal_kw = power_cap_kw * max(0.0, decay)
        if continuous_mass_kg is not None:
            drive = max(0.0, CAN_FLAME_DRIVE + drive_slope_per_o2 * excess_kg / continuous_mass_kg)
            flame, target_kw = True, ideal_kw * drive
        else:
            flame = frozen_o2 or excess_kg > 0.0
            target_kw = ideal_kw * CAN_FLAME_DRIVE if flame else off_target_kw
        tau = rp.RISE_TAU_S if target_kw > applied_kw else rp.FALL_TAU_S
        filtered_kw = applied_kw + (target_kw - applied_kw) * (1.0 - math.exp(-dt / tau))
        applied_kw = min(filtered_kw, target_kw) if reset else filtered_kw
        if reset:
            r_born += (target_kw - applied_kw) * dt / 1000.0
        heat += applied_kw * dt / 1000.0
        target_integral += target_kw * dt / 1000.0
        if time_s >= end_s - 0.25 * (end_s - start_s):
            last_quarter_heat += applied_kw * dt
            last_quarter_time += dt
        remaining_MJ -= max(target_kw, ideal_kw * CAN_FLAME_DRIVE) * dt / 1000.0
        if not frozen_o2:
            excess_kg += (rate - O2_KG_PER_MJ * applied_kw / 1000.0) * dt
        if flame != flame_before and time_s > start_s:
            (on_runs if flame_before else off_runs).append(run)
            run = 0.0
            offs += flame_before and not flame
            ons += flame and not flame_before
        run += dt
        flame_before = flame
        time_s += dt
    (on_runs if flame_before else off_runs).append(run)
    median = lambda values: sorted(values)[len(values) // 2] if values else None  # noqa: E731
    mean = lambda values: fsum(values) / len(values) if values else None  # noqa: E731
    return {
        "flame_offs": offs, "R_born_MJ": r_born if reset else None, "heat_MJ": heat,
        "target_integral_MJ": target_integral,
        "on_run_median_s": median(on_runs), "on_run_mean_s": mean(on_runs),
        "off_run_median_s": median(off_runs), "off_run_mean_s": mean(off_runs),
        "off_run_median_steps": None if not off_runs else round(median(off_runs) / dt),
        "time_on_s": fsum(on_runs), "time_off_s": fsum(off_runs),
        "heat_last_quarter_kw": last_quarter_heat / last_quarter_time if last_quarter_time else None,
        "supply_last_kw_equivalent": supply[-1][1] / O2_KG_PER_MJ * 1000.0,
    }


def engine_reference(rows: list[dict], start_s: float, end_s: float) -> dict:
    """The engine's own figures on the interval the harness simulates."""
    window = [row for row in rows if start_s - 1e-9 <= row["time_s"] < end_s + 1e-9]
    flames = [_flame(row) for row in window]
    on_runs, off_runs, run = [], [], 0.0
    for index, row in enumerate(window):
        if index and flames[index] != flames[index - 1]:
            (on_runs if flames[index - 1] else off_runs).append(run)
            run = 0.0
        run += row["dt_s"]
    (on_runs if flames[-1] else off_runs).append(run)
    median = lambda values: sorted(values)[len(values) // 2] if values else None  # noqa: E731
    return {
        "flame_offs": sum(1 for was, now in zip(flames, flames[1:]) if was and not now),
        "R_born_MJ": fsum(_r_net(row)[0] - _r_net(row)[1] for row in window),
        "heat_MJ": fsum(row["hrr_applied_kw"] * row["dt_s"] / 1000.0 for row in window),
        "on_run_median_s": median(on_runs), "off_run_median_s": median(off_runs),
        "off_run_median_steps": None if not off_runs else round(median(off_runs) / window[0]["dt_s"]),
        "time_on_s": fsum(on_runs), "time_off_s": fsum(off_runs),
    }


def control_b(branch: dict, items: list[dict], o2_factor_at_threshold: float) -> dict:
    rows, v2 = branch["rows"], branch["v2"]
    second = items[1]                       # second re-ignition: E = 0+, applied = off target
    start = next(i for i, row in enumerate(rows) if row["time_s"] >= second["t_on_s"] - 1e-9)
    start_s, end_s, dt = rows[start]["time_s"], rows[-1]["time_s"] + rows[-1]["dt_s"], rows[start]["dt_s"]
    off_steps = [row for row in rows if row["time_s"] >= start_s and row["fire_present_before"] and not _flame(row)]
    common = {
        "start_s": start_s, "end_s": end_s, "supply": supply_means(rows, v2, start_s),
        "off_target_kw": fsum(_ts(row) for row in off_steps) / len(off_steps),
        "remaining_MJ": rows[start]["fire_remaining_before_MJ"],
        "fuel_energy_MJ": rows[start]["fire_fuel_energy_MJ"], "power_cap_kw": rows[start]["power_cap_kw"],
    }
    slope = o2_factor_at_threshold / 0.040   # d(flame_drive)/d(o2), o2_hrr_factor held (its fast part)
    out = {
        "inputs": {key: common[key] for key in ("start_s", "end_s", "off_target_kw", "remaining_MJ",
                                                "fuel_energy_MJ", "power_cap_kw")},
        "supply_kg_per_s": {"min": min(v for _, v in common["supply"]), "max": max(v for _, v in common["supply"])},
        "engine": engine_reference(rows, start_s, end_s),
        "B0_harness": harness(dt=dt, **common),
        "B2_no_reset": harness(dt=dt, reset=False, **common),
        "B4_frozen_o2": harness(dt=dt, frozen_o2=True, **common),
        "B3_continuous_target": {
            f"{mass:g} kg": harness(dt=dt, continuous_mass_kg=mass, drive_slope_per_o2=slope, **common)
            for mass in (5.0, 10.0, 20.0, 40.0, 60.0)
        },
        "B1_harness_half_dt_same_inputs": harness(dt=dt / 2.0, **common),
    }
    return out


# --------------------------------------------------------------------------

def _branch(case_dir: Path, records: list[dict] | None = None) -> dict:
    rows = load(case_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    v2 = _v2(case_dir)
    if len(rows) != len(v2):
        raise ValueError(f"{case_dir}: ledger v2 and v3 differ in length")
    csv_rows = _csv_room0(case_dir)
    for row in csv_rows:
        row["time_s_float"] = float(row["time_s"])
    if records is None:
        records = ck.records_from_engine(rows)
    acc = [fsum(o["acc_MJ"] for o in rec["objects"]) for rec in records]
    rel = [fsum(o["rel_MJ"] for o in rec["objects"]) for rec in records]
    balance = [fsum(o["R_after_MJ"] for o in rec["objects"]) for rec in records]
    by_second: dict[int, list[int]] = {}
    for index, row in enumerate(rows):
        by_second.setdefault(int(math.ceil(row["time_s"] - 1e-9)), []).append(index)
    return {
        "rows": rows, "v2": v2, "csv": csv_rows, "acc": acc, "rel": rel, "balance": balance,
        "by_second": by_second, "csv_by_second": {int(round(r["time_s_float"])): r for r in csv_rows},
    }


def analyze(pre_dir: Path, optd_dir: Path, half_dt_dir: Path | None, o2_min: float, since_s: float, out: Path | None) -> dict:
    pre_rows = load(pre_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    pre_drive = rp._held(rp.flame_drive_series(pre_dir / "sim_log.csv", o2_min))
    pre = _branch(pre_dir, rp.replay(pre_rows, pre_drive, gate="rate", post="tail"))
    optd = _branch(optd_dir)
    selected = selected_o2_per_step(optd["rows"], optd["csv"], o2_min, since_s)
    check = [abs(selected[i + 1] - float(row["o2_lower"]))
             for row in optd["csv"] for i in optd["by_second"].get(int(round(row["time_s_float"])), [])[-1:]
             if i + 1 in selected and row["time_s_float"] >= since_s + 40.0]
    items = cycles(optd["rows"], optd["v2"], selected, since_s)
    born_before = fsum(a - r for a, r, row in zip(optd["acc"], optd["rel"], optd["rows"]) if row["time_s"] < since_s)
    factor = float(optd["csv"][-1]["o2_hrr_factor"])
    report = {
        "selected_o2_reconstruction_max_abs_error_vs_csv": max(check),
        "R_at_divergence_MJ": born_before, "R_final_MJ": optd["balance"][-1],
        "R_born_after_divergence_MJ": optd["balance"][-1] - born_before,
        "first_flame_off_s": next(row["time_s"] for row in optd["rows"] if row["time_s"] >= since_s
                                  and row["fire_present_before"] and not _flame(row)),
        "cycles": cycle_summary(items),
        "pre_flame_off_events_after_divergence": sum(
            1 for a, b in zip(pre["rows"], pre["rows"][1:]) if b["time_s"] >= since_s and _flame(a) and not _flame(b)),
        "control_A": control_a(optd["rows"], items[0]["t_on_s"]),
        "control_B": control_b(optd, items, factor),
    }
    if half_dt_dir is not None:
        half = _branch(half_dt_dir)
        half_selected = selected_o2_per_step(half["rows"], half["csv"], o2_min, since_s)
        half_items = cycles(half["rows"], half["v2"], half_selected, since_s)
        half_control = control_b(half, half_items, float(half["csv"][-1]["o2_hrr_factor"]))
        report["half_dt"] = {
            "cycles": cycle_summary(half_items),
            "engine": half_control["engine"], "B1_harness": half_control["B0_harness"],
            "inputs": half_control["inputs"],
        }
    if out is not None:
        out.mkdir(parents=True, exist_ok=True)
        rows_1s = timeline(pre, optd, o2_min)
        with (out / "timeline_1s.csv").open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows_1s[0]))
            writer.writeheader()
            writer.writerows(rows_1s)
        with (out / "cycles_optd.csv").open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(items[0]))
            writer.writeheader()
            writer.writerows(items)
        (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pre", type=Path, required=True)
    parser.add_argument("--optd", type=Path, required=True)
    parser.add_argument("--optd-half-dt", type=Path, help="the same case run with half the time step")
    parser.add_argument("--o2-min-ref", type=float, required=True)
    parser.add_argument("--since-s", type=float, default=293.25,
                        help="first step where the two branches differ (analyze_g3_optd_r_feedback.py)")
    parser.add_argument("--out", type=Path, help="directory for timeline_1s.csv, cycles_optd.csv and report.json")
    parser.add_argument("--rise-tau-s", type=float, default=6.0,
                        help="fire_hrr_rise_tau_s of the runs (engine default 6; the filter uses 1.8 times it)")
    args = parser.parse_args()
    rp.RISE_TAU_S = args.rise_tau_s * 1.8
    print(json.dumps(analyze(args.pre, args.optd, args.optd_half_dt, args.o2_min_ref, args.since_s, args.out), indent=2))


if __name__ == "__main__":
    main()
