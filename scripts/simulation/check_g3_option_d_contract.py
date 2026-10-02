#!/usr/bin/env python3
"""Falsification checks of the Gate B option D contract (design section 8).

Pure Python, read-only. Runs on step records with the per-object balance
``R`` (schema ``g3_option_d_replay_v1``, produced today by
``replay_g3_option_d.py``; a future engine ledger must emit the same fields).
Each check returns human-readable violations; an empty list is a pass.

Tolerances were fixed before any option-D engine run (section 8.6):
``STEP_TOL_MJ`` per step and object for energy identities, ``POWER_TOL_KW``
for power bounds. ``U`` and the retained-pool decay are *reported*, never
used to close the physical balance.
"""

from __future__ import annotations

import json
import math
from pathlib import Path


STEP_TOL_MJ = 1.0e-9
POWER_TOL_KW = 1.0e-6
FALL_TAU_S = 20.0
TAIL_MIN_KW = 2.0


def _objects(records: list[dict]):
    for record in records:
        for obj in record["objects"]:
            yield record, obj


def k1_conservation(records: list[dict]) -> list[str]:
    """C_i = B_i + dR_i + G_i + U_i per step and object; R_i >= 0; no unowned lag."""
    bad = []
    for record, obj in _objects(records):
        heat = obj["B0_MJ"] + obj["rel_MJ"]
        residual = obj["C_MJ"] - heat - (obj["R_after_MJ"] - obj["R_before_MJ"]) \
            - obj["G_MJ"] - obj["U_MJ"]
        if abs(residual) > STEP_TOL_MJ:
            bad.append(f"t={record['time_s']:.3f} {obj['id']}: residual {residual:.3e} MJ")
        if obj["R_after_MJ"] < -STEP_TOL_MJ:
            bad.append(f"t={record['time_s']:.3f} {obj['id']}: negative R {obj['R_after_MJ']:.3e}")
    for record in records:
        if record.get("unowned_lag_MJ", 0.0) > STEP_TOL_MJ:
            bad.append(f"t={record['time_s']:.3f}: lag without owner {record['unowned_lag_MJ']:.3e} MJ")
    return bad


def k2_power_permit(records: list[dict]) -> list[str]:
    """MODEL POWER PERMIT (not an O2 mass bound): released R stays within what
    the engine's own O2 *factor* permits.

    A release needs can_flame, all fresh pyrolysate burning in the step
    (P - T_s <= eps) and the object's heat within flame_drive * max_hrr_kw.
    flame_drive is a smoothed concentration factor; P = T_s is NOT evidence of
    sufficient oxygen. The O2 mass bound is K0R/K8 (OxygenExchangeSystem).
    """
    bad = []
    for record, obj in _objects(records):
        if obj["rel_MJ"] <= 0.0:
            continue
        dt = record["dt_s"]
        heat_kw = (obj["B0_MJ"] + obj["rel_MJ"]) * 1000.0 / dt
        limit_kw = record["flame_drive"] * obj["max_hrr_kw"]
        where = f"t={record['time_s']:.3f} {obj['id']}"
        if not record["can_flame"]:
            bad.append(f"{where}: R released without can_flame")
        if not record["fresh_all_burn"]:
            bad.append(f"{where}: R released while fresh pyrolysate is unburned (P>T_s)")
        if heat_kw > limit_kw + POWER_TOL_KW:
            bad.append(f"{where}: heat {heat_kw:.4f} kW above power permit {limit_kw:.4f} kW")
    return bad


def k3_no_foreign_flame(records: list[dict]) -> list[str]:
    """R_i is released only by i's own flame (own debit, flaming) or i's own tail.

    A tail may only start in the step where i itself goes flaming -> burned_out.
    """
    bad = []
    tail_started: set[str] = set()
    for record, obj in _objects(records):
        key = obj["id"]
        own = obj["C_MJ"] > 0.0 and obj["state_before"] == "flaming"
        if obj["rel_MJ"] > 0.0 and not own:
            # Engine ledgers carry the engine's own tail state; it must have been
            # opened by this object's depletion while flaming (never inferred).
            engine_tail_ok = obj.get("tail_state_before", 1) == 1
            if not (obj.get("tail_active") and key in tail_started and engine_tail_ok):
                bad.append(f"t={record['time_s']:.3f} {key}: released {obj['rel_MJ']:.3e} MJ "
                           f"without own flame or own tail")
        if obj["state_before"] == "flaming" and obj["state_after"] == "burned_out":
            tail_started.add(key)
    return bad


def k4_no_silent_loss(records: list[dict]) -> list[str]:
    """R carries over exactly between steps, owners never vanish, final R is declared."""
    bad = []
    last: dict[str, float] = {}
    for record in records:
        seen = set()
        for obj in record["objects"]:
            key = obj["id"]
            seen.add(key)
            if key in last and abs(obj["R_before_MJ"] - last[key]) > STEP_TOL_MJ:
                bad.append(f"t={record['time_s']:.3f} {key}: R jumped "
                           f"{last[key]:.9f} -> {obj['R_before_MJ']:.9f} MJ between steps")
            last[key] = obj["R_after_MJ"]
        for key in set(last) - seen:
            if last[key] > STEP_TOL_MJ:
                bad.append(f"t={record['time_s']:.3f} {key}: owner vanished holding {last[key]:.9f} MJ")
    totals = {name: math.fsum(obj[name] for _, obj in _objects(records))
              for name in ("C_MJ", "B0_MJ", "rel_MJ", "G_MJ", "U_MJ")}
    final = math.fsum(obj["R_after_MJ"] for obj in records[-1]["objects"]) if records else 0.0
    initial = math.fsum(obj["R_before_MJ"] for obj in records[0]["objects"]) if records else 0.0
    closure = totals["C_MJ"] - totals["B0_MJ"] - totals["rel_MJ"] - (final - initial) \
        - totals["G_MJ"] - totals["U_MJ"]
    if abs(closure) > STEP_TOL_MJ * max(1, len(records)):
        bad.append(f"cumulative closure {closure:.3e} MJ (declared R_final {final:.9f})")
    return bad


def k5_bounded_post_depletion(records: list[dict]) -> list[str]:
    """After i depletes: heat from R_i <= R_i at depletion, never after the tail ends,
    tail rate never above R_i/tau_f, duration <= tau_f ln(R_d/(q_min tau_f)) + dt."""
    bad = []
    depleted: dict[str, tuple[float, float]] = {}
    released_after: dict[str, float] = {}
    ended: set[str] = set()
    for record, obj in _objects(records):
        key = obj["id"]
        dt = record["dt_s"]
        if key in depleted:
            rel = obj["rel_MJ"]
            released_after[key] = released_after.get(key, 0.0) + rel
            t0, r_dep = depleted[key]
            where = f"t={record['time_s']:.3f} {key}"
            if rel > 0.0 and key in ended:
                bad.append(f"{where}: tail restarted after ending")
            if rel > obj["R_before_MJ"] * (1.0 - math.exp(-dt / FALL_TAU_S)) + STEP_TOL_MJ:
                bad.append(f"{where}: tail faster than R/tau_f")
            if released_after[key] > r_dep + STEP_TOL_MJ:
                bad.append(f"{where}: post-depletion heat {released_after[key]:.6f} > R_d {r_dep:.6f}")
            limit_s = FALL_TAU_S * math.log(r_dep * 1000.0 / (TAIL_MIN_KW * FALL_TAU_S)) \
                if r_dep * 1000.0 > TAIL_MIN_KW * FALL_TAU_S else 0.0
            if rel > 0.0 and record["time_s"] - t0 > limit_s + dt + 1e-9:
                bad.append(f"{where}: tail longer than {limit_s:.2f} s")
            if rel <= 0.0:
                ended.add(key)
        elif obj["state_before"] == "flaming" and obj["state_after"] == "burned_out":
            depleted[key] = (record["time_s"], obj["R_after_MJ"])
    return bad


def k6_hold_when_forbidden(records: list[dict]) -> list[str]:
    """F4 revised: when release is forbidden, rel_i = 0 and R_i does not decrease.
    (R_i may grow: accrual of the step's own lag is legitimate in any state.)"""
    bad = []
    for record, obj in _objects(records):
        if obj["release_allowed"]:
            continue
        if obj["rel_MJ"] != 0.0:
            bad.append(f"t={record['time_s']:.3f} {obj['id']}: release while forbidden ({obj['reason']})")
        if obj["R_after_MJ"] < obj["R_before_MJ"] - STEP_TOL_MJ:
            bad.append(f"t={record['time_s']:.3f} {obj['id']}: R decreased while forbidden")
    return bad


def k7_no_r_to_pool(records: list[dict], pool_formula_MJ) -> list[str]:
    """G is the engine formula of the step's own targets; R never enters the pool.

    ``pool_formula_MJ(record)`` returns the independent formula value
    (0.30 * (P - T_s) * dt with flame, 0 in latent phase)."""
    bad = []
    for record in records:
        expected = pool_formula_MJ(record)
        if abs(record["pool_generation_MJ"] - expected) > STEP_TOL_MJ:
            bad.append(f"t={record['time_s']:.3f}: pool generation {record['pool_generation_MJ']:.9f} "
                       f"!= formula {expected:.9f}")
    return bad


O2_KG_PER_MJ = 0.076     # fire.o2_consumption_kg_per_MJ (Thornton)


def k0_o2_debit_identity(v3_rows: list[dict], v2_rows: list[dict], *,
                         abs_tol_kg: float = 1.0e-12) -> list[str]:
    """Real engine runs: the fire's O2 sink equals Thornton x applied heat, per step.

    OxygenExchangeSystem debits ``hrr_kw * 0.076 * dt`` (times the path
    fraction) and truncates it to 5 % / 20 % of the zone O2 mass. A truncated
    step released heat without its oxygen; any R release must never be the
    cause. ``v2_rows`` are ``fuel_source_ledger.jsonl`` rows of the same room.

    The v2 value is a difference of two cumulative totals (~10 kg), whose
    float64 spacing is ~2e-15 kg, so the tolerance is absolute (1e-12 kg,
    fixed before option D); the smallest real defect seen is 2.7e-8 kg.
    """
    bad = []
    if len(v3_rows) != len(v2_rows):
        return [f"ledger length mismatch {len(v3_rows)} != {len(v2_rows)}"]
    for a, b in zip(v3_rows, v2_rows):
        if abs(a["time_s"] - b["time_s"]) > 1e-9:
            return [f"ledger time mismatch at {a['time_s']}"]
        expected = O2_KG_PER_MJ * a["hrr_applied_kw"] * a["dt_s"] / 1000.0
        got = b["room_o2_consumed_fire_kg_total_delta"]
        if abs(got - expected) > abs_tol_kg:
            bad.append(f"t={a['time_s']:.3f}: O2 fire sink {got:.3e} kg != 0.076*HRR*dt {expected:.3e}")
    return bad


def k9_no_double_use(records: list[dict]) -> list[str]:
    """Heat above T_s in a step where P > T_s is energy also booked in G + U."""
    bad = []
    for record in records:
        excess_p = (record["P_kw"] - record["Ts_kw"]) * record["dt_s"] / 1000.0
        if excess_p <= 1.0e-15:
            continue
        heat = math.fsum(o["B0_MJ"] + o["rel_MJ"] for o in record["objects"])
        double = min(heat - record["Ts_kw"] * record["dt_s"] / 1000.0, excess_p)
        if double > STEP_TOL_MJ:
            bad.append(f"t={record['time_s']:.3f}: {double:.3e} MJ counted as heat and as G+U")
    return bad


CHECKS = {
    "K1_conservation": k1_conservation,
    "K2_power_permit": k2_power_permit,
    "K3_no_foreign_flame": k3_no_foreign_flame,
    "K4_no_silent_loss": k4_no_silent_loss,
    "K5_bounded_post_depletion": k5_bounded_post_depletion,
    "K6_hold_when_forbidden": k6_hold_when_forbidden,
    "K9_no_double_use": k9_no_double_use,
}


def run_all(records: list[dict]) -> dict[str, list[str]]:
    return {name: check(records) for name, check in CHECKS.items()}


def separate_losses(records: list[dict]) -> dict[str, float]:
    """U (unburned, not transported) is reported apart; never part of 'closed'."""
    return {"U_MJ": math.fsum(obj["U_MJ"] for _, obj in _objects(records)),
            "G_MJ": math.fsum(obj["G_MJ"] for _, obj in _objects(records))}


EXTINCTION_EXCEPTION_J = 15.0   # pre-existing, fixed 2026-09-30 (design 8.1); never widened


def records_from_engine(v3_rows: list[dict]) -> list[dict]:
    """Engine ledger v3 rows (room 0, switch ON) -> ``g3_option_d_replay_v1`` records.

    Steps without an ``optd`` block (no fire) carry each object's balance
    unchanged, as the engine recorded it before and after the step.
    """
    records = []
    for row in v3_rows:
        dt = float(row["dt_s"])
        optd = row.get("optd")
        objects = []
        pool_gen = float(row["pool_generation_MJ"])
        if optd is not None:
            ts_kw, p_kw = float(optd["Ts_kw"]), float(optd["P_kw"])
            consumed = float(row["consumed_MJ"]) if row["fire_present_before"] else 0.0
            unburned = consumed - ts_kw * dt / 1000.0 - pool_gen
            for obj in row["objects"]:
                if obj["is_proxy"]:
                    continue
                d = optd["objects"][obj["id"]]
                w = float(d["weight"])
                objects.append({
                    "id": obj["id"], "C_MJ": float(obj["allocated_MJ"]), "B0_MJ": float(d["B0_MJ"]),
                    "acc_MJ": float(d["acc_MJ"]), "rel_MJ": float(d["rel_MJ"]),
                    "G_MJ": w * pool_gen, "U_MJ": w * unburned,
                    "R_before_MJ": float(d["R_before_MJ"]), "R_after_MJ": float(d["R_after_MJ"]),
                    "max_hrr_kw": float(obj["max_hrr_kw"]), "own_viable": d["reason"] == "allowed",
                    "tail_active": d["reason"] == "tail",
                    "tail_state_before": int(d["tail_state_before"]),
                    "release_allowed": bool(d["release_allowed"]), "reason": d["reason"],
                    "state_before": obj["state_before"], "state_after": obj["state_after"],
                })
            drive, can_flame = float(optd["flame_drive"]), bool(optd["can_flame"])
            fresh, unowned = bool(optd["fresh_all_burn"]), float(optd["unowned_lag_MJ"])
        else:
            ts_kw = p_kw = 0.0
            drive, can_flame, fresh, unowned = 0.0, False, True, 0.0
            for obj in row["objects"]:
                if obj["is_proxy"]:
                    continue
                objects.append({
                    "id": obj["id"], "C_MJ": float(obj.get("allocated_MJ", 0.0)), "B0_MJ": 0.0,
                    "acc_MJ": 0.0, "rel_MJ": 0.0, "G_MJ": 0.0, "U_MJ": 0.0,
                    "R_before_MJ": float(obj["r_balance_before_MJ"]),
                    "R_after_MJ": float(obj["r_balance_after_MJ"]),
                    "max_hrr_kw": float(obj["max_hrr_kw"]), "own_viable": False,
                    "tail_active": False, "tail_state_before": int(obj["tail_state_before"]),
                    "release_allowed": False, "reason": "no_fire",
                    "state_before": obj["state_before"], "state_after": obj["state_after"],
                })
        records.append({
            "schema_version": "g3_option_d_replay_v1", "source": "engine",
            "time_s": float(row["time_s"]), "dt_s": dt, "fire": bool(row["fire_present_before"]),
            "Ts_kw": ts_kw, "P_kw": p_kw, "flame_drive": drive, "can_flame": can_flame,
            "fresh_all_burn": fresh, "consumed_MJ": float(row["consumed_MJ"]),
            "pool_generation_MJ": pool_gen, "unowned_lag_MJ": unowned,
            "applied_kw": float(row["hrr_applied_kw"]), "objects": objects,
        })
    return records


def k0_split(v3_rows: list[dict], v2_rows: list[dict], *, abs_tol_kg: float = 1.0e-12) -> dict:
    """K0 on an engine run, split by cause. The criterion is ``with_release`` = [].

    ``extinction``: the fire-extinction step (pre-existing; allowed only up to
    EXTINCTION_EXCEPTION_J of heat and never with an R release);
    ``base_heat``: truncation of the step's non-R heat by the
    OxygenExchangeSystem cap (pre-existing, reported, not R);
    ``with_release``: a truncated step that also released R (NO-GO).
    """
    out = {"extinction": [], "extinction_over_exception": [], "base_heat": [], "with_release": []}
    if len(v3_rows) != len(v2_rows):
        raise ValueError(f"ledger length mismatch {len(v3_rows)} != {len(v2_rows)}")
    for a, b in zip(v3_rows, v2_rows):
        if abs(a["time_s"] - b["time_s"]) > 1e-9:
            raise ValueError(f"ledger time mismatch at {a['time_s']}")
        expected = O2_KG_PER_MJ * a["hrr_applied_kw"] * a["dt_s"] / 1000.0
        missing = expected - b["room_o2_consumed_fire_kg_total_delta"]
        if abs(missing) <= abs_tol_kg:
            continue
        heat_j = missing / O2_KG_PER_MJ * 1.0e6
        released = float((a.get("optd") or {}).get("release_MJ", 0.0))
        item = (round(a["time_s"], 3), missing, heat_j, released)
        if a.get("fire_extinguished_this_step"):
            out["extinction"].append(item)
            if heat_j > EXTINCTION_EXCEPTION_J or released > 0.0:
                out["extinction_over_exception"].append(item)
        elif released > 0.0:
            out["with_release"].append(item)
        else:
            out["base_heat"].append(item)
    return out


def k8_mass_headroom(v3_rows: list[dict]) -> list[str]:
    """The engine never releases more R than its declared O2 mass headroom."""
    bad = []
    for row in v3_rows:
        optd = row.get("optd")
        if optd is None:
            continue
        if float(optd["release_MJ"]) > float(optd["mass_headroom_MJ"]) + STEP_TOL_MJ:
            bad.append(f"t={row['time_s']:.3f}: release {optd['release_MJ']:.6e} MJ > "
                       f"O2 headroom {optd['mass_headroom_MJ']:.6e} MJ")
    return bad


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("records", type=Path)
    args = parser.parse_args()
    records = [json.loads(line) for line in args.records.open(encoding="utf-8")]
    result = {name: {"violations": len(v), "first": v[:3]} for name, v in run_all(records).items()}
    result["reported_not_closed"] = separate_losses(records)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
