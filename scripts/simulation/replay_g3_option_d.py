#!/usr/bin/env python3
"""Offline RECONSTRUCTION of Gate B option D variants on measured ledgers.

Read-only. Not a combustion law and not an engine change: it replays the
per-object balance ``R`` (design section 8) on the trajectories recorded by
ledger v3 (``g3_fuel_ledger_v3``) of a switch-ON run.

Exogenous assumption (the reason every number is a reconstruction): the
requested target ``T``, ``T_s``, pyrolysis ``P``, pool burn, per-object debits
and states are taken from the ON run as if option D did not feed back into
them. The engine does feed back (``thermal_feedback_coeff``, O2 follows the
applied heat), so ventilated cases are a close approximation and the
O2-limited room is indicative only.

``flame_drive`` is not in ledger v3; it is rebuilt from ``sim_log.csv``
(1 s rows, held between rows) as ``o2_hrr_factor * flame_possible_factor`` of
``CombustionSystem.step_room_fire`` (non-FDS branch).

Variants (``--gate`` x ``--post``):

* gate ``none``  - section 7.3 literal: release only bounded by object power.
* gate ``rate``  - section 8.3: release needs ``can_flame``, no unburned fresh
  pyrolysate in the step (``P - T_s <= eps``) and each object's heat stays
  within ``flame_drive * max_hrr_kw_i``.
* post ``conserve`` - R of a depleted object is kept and declared, never heat.
* post ``tail``     - an object that depletes while flaming may release its
  own R as ``R (1 - exp(-dt/tau_f))`` per step, gated as above, until the
  tail rate falls below ``0.25 * fire_extinction_hrr_kw``; interrupted or
  finished tails never restart and the rest of R stays declared.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from analyze_g3_fuel_ledger import load  # noqa: E402


SCHEMA = "g3_option_d_replay_v1"
RISE_TAU_S = 6.0 * 1.8      # fire_hrr_rise_tau_s * 1.8 (ventilation_response_factor = 0)
FALL_TAU_S = 20.0           # fire_hrr_fall_tau_s
EXTINCTION_HRR_KW = 8.0     # fire_extinction_hrr_kw (engine default)
TAIL_MIN_KW = 0.25 * EXTINCTION_HRR_KW   # engine zeroes hrr below this (step_room_fire)
CAN_FLAME_DRIVE = 0.08      # can_flame = flame_drive > 0.08
EPS_KW = 1.0e-9
GATES = ("none", "rate")
POSTS = ("conserve", "tail")


def flame_drive_series(csv_path: Path, o2_min_ref: float, room_id: int = 0) -> list[tuple[float, float]]:
    series = []
    with Path(csv_path).open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if row.get("room_id") != str(room_id):
                continue
            mode = row["fire_o2_mode_used"]
            o2_ref = float(row["o2_lower"]) if mode == "plume_lower" else float(row["o2"])
            possible = min(1.0, max(0.0, (o2_ref - (o2_min_ref - 0.015)) / 0.040))
            series.append((float(row["time_s"]), float(row["o2_hrr_factor"]) * possible))
    if not series:
        raise ValueError(f"{csv_path}: no room {room_id} rows")
    return series


def _held(series: list[tuple[float, float]]):
    """Stateless sample-and-hold: the last CSV row at or before ``time_s``."""
    times = [time_s for time_s, _ in series]

    def at(time_s: float) -> float:
        index = max(0, bisect.bisect_right(times, time_s + 1e-9) - 1)
        return series[index][1]
    return at


def _waterfill(total: float, weights: dict, caps: dict) -> dict:
    given = {key: 0.0 for key in caps}
    open_keys = [key for key in caps if caps[key] > 0.0 and weights.get(key, 0.0) > 0.0]
    remaining = total
    while remaining > 1e-18 and open_keys:
        base = math.fsum(weights[key] for key in open_keys)
        spent = 0.0
        still_open = []
        for key in open_keys:
            share = min(caps[key] - given[key], remaining * weights[key] / base)
            given[key] += share
            spent += share
            if caps[key] - given[key] > 1e-18:
                still_open.append(key)
        remaining -= spent
        if spent <= 1e-18:
            break
        open_keys = still_open
    return given


def replay(rows: list[dict], flame_drive_at, *, gate: str, post: str) -> list[dict]:
    """Return one record per step with the per-object option-D balance."""
    if gate not in GATES or post not in POSTS:
        raise ValueError(f"unknown variant {gate}/{post}")
    applied_kw = 0.0
    balance: dict[str, float] = {}
    tail: dict[str, str] = {}
    records = []
    for row in rows:
        dt = float(row["dt_s"])
        target_kw = float(row["hrr_requested_kw"])
        pool_kw = float(row["actual_pool_burn_kw"])
        tau = RISE_TAU_S if target_kw > applied_kw else FALL_TAU_S
        filtered_kw = applied_kw + (target_kw - applied_kw) * (1.0 - math.exp(-dt / tau))
        solid_request_kw = filtered_kw - pool_kw
        fire = bool(row["fire_present_before"])
        ts_kw = (row["flame_target_kw"] + row["smolder_target_kw"]) if fire else 0.0
        p_kw = row["pyrolysis_kw"] if fire else 0.0
        consumed = float(row["consumed_MJ"]) if fire else 0.0
        drive = flame_drive_at(float(row["time_s"]))
        can_flame = drive > CAN_FLAME_DRIVE
        fresh_all_burn = p_kw - ts_kw <= EPS_KW
        o2_extinguished = bool(row.get("o2_extinguished", False))
        pool_gen = float(row["pool_generation_MJ"])
        unburned_U = consumed - ts_kw * dt / 1000.0 - pool_gen
        objects = [obj for obj in row["objects"] if not obj["is_proxy"]]
        alloc = {obj["id"]: float(obj["allocated_MJ"]) for obj in objects}
        total_alloc = math.fsum(alloc.values())
        weight = {key: (value / total_alloc if total_alloc > 0.0 else 0.0) for key, value in alloc.items()}
        base_kw = min(max(solid_request_kw, 0.0), ts_kw)
        lag = (ts_kw - base_kw) * dt / 1000.0
        unowned_lag = lag if total_alloc <= 0.0 and lag > 0.0 else 0.0
        o2_ok = can_flame and not o2_extinguished and (gate == "none" or fresh_all_burn)
        per = {}
        caps = {}
        tail_caps = {}
        for obj in objects:
            key = obj["id"]
            balance.setdefault(key, 0.0)
            base_i_kw = weight[key] * base_kw
            if gate == "rate":
                room_kw = max(0.0, drive * float(obj["max_hrr_kw"]) - base_i_kw)
            else:
                room_kw = max(0.0, float(obj["max_hrr_kw"]) - base_i_kw)
            own_viable = obj["active_before"] and alloc[key] > 0.0 and obj["state_before"] == "flaming"
            tail_active = post == "tail" and tail.get(key) == "active"
            if tail_active and not o2_ok:
                tail[key] = "interrupted"
                tail_active = False
            if tail_active and balance[key] / FALL_TAU_S * 1000.0 < TAIL_MIN_KW:
                tail[key] = "ended"
                tail_active = False
            allowed = o2_ok and (own_viable or tail_active)
            reason = "allowed" if allowed else (
                "o2_gate" if (own_viable or tail_active) else
                ("tail_" + tail[key] if key in tail else "not_viable"))
            per[key] = {
                "id": key, "C_MJ": alloc[key], "B0_MJ": base_i_kw * dt / 1000.0,
                "acc_MJ": weight[key] * lag, "G_MJ": weight[key] * pool_gen,
                "U_MJ": weight[key] * unburned_U, "R_before_MJ": balance[key],
                "max_hrr_kw": float(obj["max_hrr_kw"]), "own_viable": own_viable,
                "tail_active": tail_active, "release_allowed": allowed, "reason": reason,
                "state_before": obj["state_before"], "state_after": obj["state_after"],
            }
            balance[key] += per[key]["acc_MJ"]
            if allowed and own_viable:
                caps[key] = min(balance[key], room_kw * dt / 1000.0)
            elif allowed and tail_active:
                tail_caps[key] = min(balance[key] * (1.0 - math.exp(-dt / FALL_TAU_S)),
                                     room_kw * dt / 1000.0)
        excess = max(0.0, solid_request_kw - ts_kw) * dt / 1000.0
        released = _waterfill(excess, {k: balance[k] for k in caps}, caps)
        released.update(tail_caps)
        for key, item in per.items():
            rel = released.get(key, 0.0)
            balance[key] -= rel
            item["rel_MJ"] = rel
            item["R_after_MJ"] = balance[key]
            if post == "tail" and item["state_before"] == "flaming" \
                    and item["state_after"] == "burned_out" and key not in tail:
                tail[key] = "active"
                item["depleted_now"] = True
        heat = math.fsum(item["B0_MJ"] + item["rel_MJ"] for item in per.values())
        applied_kw = heat * 1000.0 / dt + pool_kw
        records.append({
            "schema_version": SCHEMA, "gate": gate, "post": post,
            "time_s": row["time_s"], "dt_s": dt, "fire": fire,
            "Ts_kw": ts_kw, "P_kw": p_kw, "flame_drive": drive, "can_flame": can_flame,
            "fresh_all_burn": fresh_all_burn, "consumed_MJ": consumed,
            "pool_generation_MJ": pool_gen, "U_MJ": unburned_U, "unowned_lag_MJ": unowned_lag,
            "applied_kw": applied_kw, "objects": list(per.values()),
        })
    return records


def summarize(records: list[dict]) -> dict:
    fsum = math.fsum
    owners = sorted({obj["id"] for rec in records for obj in rec["objects"]})
    out = {"steps": len(records)}
    out["C_MJ"] = fsum(o["C_MJ"] for r in records for o in r["objects"])
    out["B_MJ"] = fsum(o["B0_MJ"] + o["rel_MJ"] for r in records for o in r["objects"])
    out["G_MJ"] = fsum(o["G_MJ"] for r in records for o in r["objects"])
    out["U_MJ"] = fsum(o["U_MJ"] for r in records for o in r["objects"])
    out["release_MJ"] = fsum(o["rel_MJ"] for r in records for o in r["objects"])
    out["release_below_drive_0p99_MJ"] = fsum(
        o["rel_MJ"] for r in records if r["flame_drive"] < 0.99 for o in r["objects"])
    out["release_with_unburned_fresh_MJ"] = fsum(
        o["rel_MJ"] for r in records if not r["fresh_all_burn"] for o in r["objects"])
    out["o2_for_release_kg"] = out["release_MJ"] * 0.076
    out["unowned_lag_MJ"] = fsum(r["unowned_lag_MJ"] for r in records)
    peak = 0.0
    peak_t = 0.0
    for r in records:
        total = fsum(o["R_after_MJ"] for o in r["objects"])
        if total > peak:
            peak, peak_t = total, r["time_s"]
    out["R_peak_MJ"], out["R_peak_t_s"] = peak, peak_t
    final = {key: 0.0 for key in owners}
    for obj in records[-1]["objects"]:
        final[obj["id"]] = obj["R_after_MJ"]
    out["R_final_by_owner_MJ"] = final
    out["R_final_MJ"] = fsum(final.values())
    out["closure_MJ"] = out["C_MJ"] - out["B_MJ"] - out["R_final_MJ"] - out["G_MJ"] - out["U_MJ"]
    out["B_over_C"] = out["B_MJ"] / out["C_MJ"] if out["C_MJ"] else None
    post = {}
    for key in owners:
        depleted_at = None
        heat_after = 0.0
        last_release_t = None
        r_at_depletion = None
        for r in records:
            for o in r["objects"]:
                if o["id"] != key:
                    continue
                if depleted_at is not None:
                    heat_after += o["rel_MJ"]
                    if o["rel_MJ"] > 0.0:
                        last_release_t = r["time_s"]
                if depleted_at is None and o["state_before"] == "flaming" \
                        and o["state_after"] == "burned_out":
                    depleted_at = r["time_s"]
                    r_at_depletion = o["R_after_MJ"]
        post[key] = {
            "depleted_at_s": depleted_at, "R_at_depletion_MJ": r_at_depletion,
            "heat_after_depletion_MJ": heat_after,
            "tail_duration_s": (last_release_t - depleted_at)
            if (depleted_at is not None and last_release_t is not None) else 0.0,
        }
    out["post_depletion"] = post
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case_dir", type=Path, help="run case dir with ledger v3 and sim_log.csv")
    parser.add_argument("--o2-min-ref", type=float, required=True,
                        help="fire_o2_min_for_flame of the case (engine 0.122; v7 geometry 0.10)")
    parser.add_argument("--gate", choices=GATES, required=True)
    parser.add_argument("--post", choices=POSTS, required=True)
    parser.add_argument("--records", type=Path, help="optional JSONL output of step records")
    args = parser.parse_args()
    rows = load(args.case_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    drive = _held(flame_drive_series(args.case_dir / "sim_log.csv", args.o2_min_ref))
    records = replay(rows, drive, gate=args.gate, post=args.post)
    if args.records is not None:
        with args.records.open("w", encoding="utf-8") as handle:
            for record in records:
                handle.write(json.dumps(record) + "\n")
    print(json.dumps(summarize(records), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
