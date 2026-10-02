"""Gate B option D contract: the checkers must pass a clean replay and kill each defect.

Synthetic ledger-v3-shaped trajectories only; no Godot, no engine change.
"""

from __future__ import annotations

import copy
import math
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "simulation"))

import check_g3_option_d_contract as ck  # noqa: E402
import replay_g3_option_d as rp  # noqa: E402


DT = 1.0 / 12.0


def _obj(key, *, alloc, state_before="flaming", state_after="flaming", active=True, cap=100.0):
    return {"id": key, "is_proxy": False, "allocated_MJ": alloc, "active_before": active,
            "state_before": state_before, "state_after": state_after, "max_hrr_kw": cap}


def _row(t, target_kw, *, objects, pyrolysis_kw=None, pool_gen=0.0, fire=True):
    p = target_kw if pyrolysis_kw is None else pyrolysis_kw
    return {"time_s": t, "dt_s": DT, "hrr_requested_kw": target_kw,
            "actual_pool_burn_kw": 0.0, "fire_present_before": fire,
            "flame_target_kw": target_kw, "smolder_target_kw": 0.0, "pyrolysis_kw": p,
            "consumed_MJ": p * DT / 1000.0, "pool_generation_MJ": pool_gen,
            "o2_extinguished": False, "objects": objects}


def _sofa_rows(*, deplete_at=None, n=4800, fall_kw_s=0.4):
    """20 s ramp to 80 kW, hold to 60 s, then a linear fall; one 100 kW object.

    The default fall (0.4 kW/s) is slower than the filter, so the fall excess
    exceeds the rise lag and R can be released by the object's own flame.
    ``deplete_at`` (s) marks exactly one step flaming -> burned_out.
    """
    rows = []
    deplete_step = None if deplete_at is None else round(deplete_at / DT) - 1
    for k in range(n):
        t = (k + 1) * DT
        target = min(80.0, 4.0 * t) if t < 60.0 else max(0.0, 80.0 - fall_kw_s * (t - 60.0))
        state_after = "flaming"
        state_before = "flaming"
        alloc = target * DT / 1000.0
        active = True
        if deplete_step is not None and k >= deplete_step:
            if k == deplete_step:
                state_after = "burned_out"
            else:
                state_before = state_after = "burned_out"
                alloc, target, active = 0.0, 0.0, False
        rows.append(_row(t, target, objects=[_obj("sofa", alloc=alloc, state_before=state_before,
                                                  state_after=state_after, active=active)]))
    return rows


def _replay(rows, *, gate="rate", post="tail", drive=1.0):
    return rp.replay(rows, lambda _t: drive, gate=gate, post=post)


def test_clean_ventilated_replay_passes_every_check_and_closes():
    records = _replay(_sofa_rows())
    assert ck.run_all(records) == {name: [] for name in ck.CHECKS}
    summary = rp.summarize(records)
    assert summary["R_peak_MJ"] > 0.1           # the filter lag is real
    assert summary["R_final_MJ"] < 1e-6          # and is released by the own flame
    assert abs(summary["closure_MJ"]) < 1e-12


def test_k2_kills_release_above_the_o2_permit():
    records = _replay(_sofa_rows(), gate="none", drive=0.5)
    assert ck.k2_power_permit(records), "section 7.3 literal must exceed flame_drive * max_hrr"
    assert ck.k2_power_permit(_replay(_sofa_rows(), gate="rate", drive=0.5)) == []


def test_k2_kills_release_while_fresh_pyrolysate_is_unburned():
    rows = _sofa_rows()
    for row in rows[900:1200]:
        row["pyrolysis_kw"] = row["flame_target_kw"] + 30.0
        row["consumed_MJ"] = row["pyrolysis_kw"] * DT / 1000.0
        row["objects"][0]["allocated_MJ"] = row["consumed_MJ"]
    assert ck.k2_power_permit(_replay(rows, gate="none"))
    gated = _replay(rows, gate="rate")
    assert ck.k2_power_permit(gated) == []
    assert all(o["rel_MJ"] == 0.0 for r in gated[900:1200] for o in r["objects"])


def test_k3_kills_release_by_a_foreign_flame():
    records = _replay(_sofa_rows())
    mutated = copy.deepcopy(records)
    for record in mutated[800:900]:
        cold = {"id": "chair", "C_MJ": 0.0, "B0_MJ": 0.0, "acc_MJ": 0.0, "G_MJ": 0.0,
                "U_MJ": 0.0, "R_before_MJ": 0.01, "R_after_MJ": 0.0099, "rel_MJ": 0.0001,
                "max_hrr_kw": 100.0, "own_viable": False, "tail_active": False,
                "release_allowed": True, "reason": "room_flame", "state_before": "heating",
                "state_after": "heating"}
        record["objects"].append(cold)
    assert ck.k3_no_foreign_flame(mutated)


def test_k4_kills_silent_loss_and_vanishing_owner():
    records = _replay(_sofa_rows(deplete_at=65.0), post="conserve")
    assert ck.k4_no_silent_loss(records) == []
    dropped = copy.deepcopy(records)
    for record in dropped[-10:]:
        for obj in record["objects"]:
            obj["R_before_MJ"] = obj["R_after_MJ"] = 0.0     # R written off quietly
    assert ck.k4_no_silent_loss(dropped)
    vanished = copy.deepcopy(records)
    vanished[-1]["objects"] = []
    assert ck.k4_no_silent_loss(vanished)


def test_conserve_keeps_r_declared_after_depletion():
    records = _replay(_sofa_rows(deplete_at=62.0), post="conserve")
    summary = rp.summarize(records)
    assert summary["R_final_MJ"] > 0.1
    assert summary["post_depletion"]["sofa"]["heat_after_depletion_MJ"] == 0.0
    assert ck.run_all(records) == {name: [] for name in ck.CHECKS}


def test_tail_is_finite_and_k5_kills_unbounded_post_depletion_heat():
    records = _replay(_sofa_rows(deplete_at=62.0), post="tail")
    assert ck.run_all(records) == {name: [] for name in ck.CHECKS}
    info = rp.summarize(records)["post_depletion"]["sofa"]
    r_d = info["R_at_depletion_MJ"]
    assert 0.0 < info["heat_after_depletion_MJ"] <= r_d
    assert info["tail_duration_s"] <= ck.FALL_TAU_S * math.log(
        r_d * 1000.0 / (ck.TAIL_MIN_KW * ck.FALL_TAU_S)) + DT + 1e-9
    assert rp.summarize(records)["R_final_MJ"] <= ck.TAIL_MIN_KW * ck.FALL_TAU_S / 1000.0 + 1e-12

    unbounded = copy.deepcopy(records)
    for record in unbounded[-300:]:          # keep releasing long after the tail ended
        obj = record["objects"][0]
        obj["rel_MJ"] = 0.001
        obj["R_after_MJ"] = obj["R_before_MJ"] - 0.001
    assert ck.k5_bounded_post_depletion(unbounded)


def test_tail_never_starts_from_another_objects_flame():
    rows = _sofa_rows(deplete_at=62.0)
    for row in rows:                         # a second, still-burning object keeps a flame
        row["objects"].append(_obj("chair", alloc=row["consumed_MJ"], cap=100.0))
        row["consumed_MJ"] *= 2.0
    records = _replay(rows, post="conserve")
    after = [o for r in records if r["time_s"] > 62.1 for o in r["objects"] if o["id"] == "sofa"]
    assert after and all(o["rel_MJ"] == 0.0 for o in after)
    assert ck.run_all(records) == {name: [] for name in ck.CHECKS}


def test_k6_allows_accrual_but_kills_release_or_decrease_when_forbidden():
    rows = _sofa_rows()
    for row in rows[600:700]:                # latent transition: stale state, own target > 0
        row["objects"][0]["state_before"] = "decaying"
    records = _replay(rows)
    grew = [o for r in records[600:700] for o in r["objects"] if o["acc_MJ"] > 0.0]
    assert grew, "accrual in a non-viable step is legitimate"
    assert ck.k6_hold_when_forbidden(records) == []
    mutated = copy.deepcopy(records)
    obj = mutated[650]["objects"][0]
    obj["rel_MJ"] = 1e-4
    obj["R_after_MJ"] = obj["R_before_MJ"] - 1e-4
    assert ck.k6_hold_when_forbidden(mutated)


def test_k1_kills_heat_without_fuel_and_unowned_lag():
    records = _replay(_sofa_rows())
    mutated = copy.deepcopy(records)
    mutated[500]["objects"][0]["B0_MJ"] += 1e-6
    assert ck.k1_conservation(mutated)
    mutated = copy.deepcopy(records)
    mutated[500]["unowned_lag_MJ"] = 1e-6
    assert ck.k1_conservation(mutated)


def test_k7_detects_r_entering_the_pool():
    records = _replay(_sofa_rows())

    def formula(record):
        return 0.30 * max(0.0, record["P_kw"] - record["Ts_kw"]) * record["dt_s"] / 1000.0

    assert ck.k7_no_r_to_pool(records, formula) == []
    mutated = copy.deepcopy(records)
    mutated[-1]["pool_generation_MJ"] += 0.05
    assert ck.k7_no_r_to_pool(mutated, formula)


@pytest.mark.parametrize("gate,post", [(g, p) for g in rp.GATES for p in rp.POSTS])
def test_replay_variants_close_exactly(gate, post):
    summary = rp.summarize(_replay(_sofa_rows(deplete_at=62.0), gate=gate, post=post))
    assert abs(summary["closure_MJ"]) < 1e-12


def test_k0_kills_heat_without_its_oxygen():
    v3 = [{"time_s": (k + 1) * DT, "dt_s": DT, "hrr_applied_kw": 50.0} for k in range(10)]
    v2 = [{"time_s": row["time_s"],
           "room_o2_consumed_fire_kg_total_delta": 0.076 * 50.0 * DT / 1000.0} for row in v3]
    assert ck.k0_o2_debit_identity(v3, v2) == []
    truncated = copy.deepcopy(v2)
    truncated[4]["room_o2_consumed_fire_kg_total_delta"] *= 0.95   # OES cap bound
    assert ck.k0_o2_debit_identity(v3, truncated)


def test_flame_drive_sampler_is_stateless_across_replays():
    series = [(float(t), 1.0 if t < 70 else 0.3) for t in range(0, 400)]
    sampler = rp._held(series)
    first = rp.summarize(rp.replay(_sofa_rows(), sampler, gate="rate", post="tail"))
    second = rp.summarize(rp.replay(_sofa_rows(), sampler, gate="rate", post="tail"))
    assert first == second
    assert sampler(10.5) == 1.0 and sampler(75.0) == 0.3 and sampler(5.0) == 1.0


def _engine_row(t, *, applied_kw, release=0.0, headroom=1.0, extinguished=False, optd=True,
                ts_kw=50.0, p_kw=50.0, r_before=0.2, acc=0.0, base_kw=50.0):
    row = {"time_s": t, "dt_s": DT, "hrr_applied_kw": applied_kw, "fire_present_before": True,
           "fire_extinguished_this_step": extinguished, "consumed_MJ": p_kw * DT / 1000.0,
           "pool_generation_MJ": 0.0,
           "objects": [{"id": "sofa", "is_proxy": False, "allocated_MJ": p_kw * DT / 1000.0,
                        "max_hrr_kw": 100.0, "state_before": "flaming", "state_after": "flaming",
                        "r_balance_before_MJ": r_before, "r_balance_after_MJ": r_before + acc - release,
                        "tail_state_before": 0}]}
    if optd:
        row["optd"] = {
            "Ts_kw": ts_kw, "P_kw": p_kw, "flame_drive": 1.0, "can_flame": True, "fresh_all_burn": True,
            "unowned_lag_MJ": 0.0, "release_MJ": release, "mass_headroom_MJ": headroom,
            "objects": {"sofa": {"weight": 1.0, "B0_MJ": base_kw * DT / 1000.0, "acc_MJ": acc,
                                 "rel_MJ": release, "R_before_MJ": r_before,
                                 "R_after_MJ": r_before + acc - release, "release_allowed": True,
                                 "reason": "allowed", "tail_state_before": 0}}}
    return row


def _v2_row(row, fraction=1.0):
    return {"time_s": row["time_s"],
            "room_o2_consumed_fire_kg_total_delta": fraction * 0.076 * row["hrr_applied_kw"] * DT / 1000.0}


def test_engine_records_close_and_k0_split_separates_causes():
    rows = [_engine_row(DT, applied_kw=50.0), _engine_row(2 * DT, applied_kw=62.0, release=0.001)]
    assert ck.run_all(ck.records_from_engine(rows)) == {name: [] for name in ck.CHECKS}
    clean = ck.k0_split(rows, [_v2_row(r) for r in rows])
    assert all(not v for v in clean.values())
    truncated = ck.k0_split(rows, [_v2_row(rows[0], 0.9), _v2_row(rows[1], 0.9)])
    assert len(truncated["base_heat"]) == 1 and len(truncated["with_release"]) == 1
    ext = [_engine_row(DT, applied_kw=0.1, extinguished=True, optd=False)]
    small = ck.k0_split(ext, [{"time_s": DT, "room_o2_consumed_fire_kg_total_delta": 0.0}])
    assert len(small["extinction"]) == 1 and not small["extinction_over_exception"]
    big = [_engine_row(DT, applied_kw=5.0, extinguished=True, optd=False)]   # 417 J > 15 J
    assert ck.k0_split(big, [{"time_s": DT, "room_o2_consumed_fire_kg_total_delta": 0.0}])[
        "extinction_over_exception"]


def test_k8_and_k9_kill_mass_overrun_and_double_use():
    over = [_engine_row(DT, applied_kw=62.0, release=0.002, headroom=0.001)]
    assert ck.k8_mass_headroom(over)
    double = ck.records_from_engine([_engine_row(DT, applied_kw=60.0, ts_kw=40.0, p_kw=60.0, base_kw=60.0)])
    assert ck.k9_no_double_use(double)
