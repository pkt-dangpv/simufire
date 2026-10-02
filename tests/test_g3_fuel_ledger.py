"""G3-3 passive fuel ledger v3: owner partition, closure and ownership contract."""

from __future__ import annotations

import copy

import pytest

from scripts.simulation.analyze_g3_fuel_ledger import (
    STEP_TOL_MJ,
    closure_failures,
    explicit_owned_failures,
    step_owners,
    summarize,
)

DT = 1.0 / 12.0


def _obj(object_id, before, allocated, *, lost=0.0, hrr=0.0, cap=100.0, active=True, proxy=False):
    return {
        "id": object_id, "is_proxy": proxy, "active_before": active,
        "remaining_before_MJ": before, "remaining_after_MJ": before - allocated - lost,
        "allocated_MJ": allocated, "max_hrr_kw": cap, "hrr_after_kw": hrr,
        "co_yield_kg_per_MJ": 0.0004, "state_before": "flaming", "state_after": "flaming",
    }


def _row(t, consumed, objects, *, fire_before=10.0, room_mj=0.0, solid_kw=None, co=1e-6,
         mode="explicit_owned", fire_after=None):
    solid_kw = consumed * 1000.0 / DT if solid_kw is None else solid_kw
    return {
        "schema_version": "g3_fuel_ledger_v3", "time_s": t, "room_id": 0, "dt_s": DT,
        "switch_on": mode == "explicit_owned", "ownership_mode": mode,
        "declared_room_fuel_MJ": room_mj, "declared_room_max_hrr_kw": 0.0,
        "fire_present_before": True, "fire_extinguished_this_step": False,
        "fire_remaining_before_MJ": fire_before,
        "fire_remaining_after_MJ": fire_before - consumed if fire_after is None else fire_after,
        "consumed_MJ": consumed, "hrr_requested_kw": solid_kw, "hrr_applied_kw": solid_kw,
        "actual_solid_burn_kw": solid_kw, "actual_pool_burn_kw": 0.0, "power_cap_kw": 100.0,
        "species": {"co_kg": co, "co2_kg": 10 * co, "hcn_kg": co / 10, "smoke_kg": 5 * co},
        "objects": objects,
    }


def _owned_run():
    rows, fire, sofa = [], 3.0, 3.0
    for i in range(10):
        burn = 0.001
        rows.append(_row(i * DT, burn, [_obj("sofa", sofa, burn, hrr=12.0),
                                        _obj("chair", 3.0, 0.0, active=False)], fire_before=fire))
        fire -= burn
        sofa -= burn
    return rows


def test_owned_run_closes_and_satisfies_the_contract() -> None:
    summary = summarize(_owned_run())
    assert summary["owners_MJ"] == {"object:sofa": pytest.approx(0.01)}
    assert closure_failures(summary) == []
    assert explicit_owned_failures(summary) == []
    assert summary["objects_final_MJ"]["chair"] == 3.0
    for key, item in summary["species"].items():
        assert item["by_owner"]["object:sofa"] == pytest.approx(item["total"]), key


def test_consumption_without_object_debit_is_unowned_or_room_load() -> None:
    rows = _owned_run()
    rows[3]["consumed_MJ"] += 0.002  # the fire consumes more than any object gave
    rows[3]["fire_remaining_after_MJ"] -= 0.002
    unowned = summarize(rows)
    assert unowned["unowned_MJ"] == pytest.approx(0.002)
    assert "O1_unowned_MJ" in explicit_owned_failures(unowned)
    as_room = copy.deepcopy(rows)
    for row in as_room:
        row["declared_room_fuel_MJ"] = 3.0
        row["ownership_mode"] = "legacy_room_load"
    assert summarize(as_room)["room_load_MJ"] == pytest.approx(0.002)
    step = step_owners(rows[3])
    assert step["species"]["co_kg"]["by_owner"]["unowned"] == pytest.approx(1e-6 * 0.002 / 0.003)


def test_discard_inactive_debit_power_and_heat_mutations_are_detected() -> None:
    discard = _owned_run()
    discard[-1]["objects"][0]["remaining_after_MJ"] -= 0.0005  # burnout snap
    assert "O2_discarded_MJ" in explicit_owned_failures(summarize(discard))

    inactive = _owned_run()
    inactive[2]["objects"][1]["allocated_MJ"] = 0.001
    inactive[2]["objects"][1]["remaining_after_MJ"] = 2.999
    inactive[2]["consumed_MJ"] += 0.001
    inactive[2]["fire_remaining_after_MJ"] -= 0.001
    assert "O3_inactive_object_debited" in explicit_owned_failures(summarize(inactive))

    power = _owned_run()
    power[4]["objects"][0]["hrr_after_kw"] = 150.0  # object above its own 100 kW
    assert "O4_power_cap" in explicit_owned_failures(summarize(power))

    heat = _owned_run()
    heat[5]["actual_solid_burn_kw"] = heat[5]["hrr_applied_kw"] = 40.0  # > pyrolysis of the step
    assert "O5_heat_without_fuel_owner" in explicit_owned_failures(summarize(heat))


def test_numerical_closure_failures_are_reported_not_hidden() -> None:
    broken_fire = _owned_run()
    broken_fire[1]["fire_remaining_after_MJ"] -= 10 * STEP_TOL_MJ
    assert "K1_fire_inventory_step" in closure_failures(summarize(broken_fire))
    gained = _owned_run()
    gained[6]["objects"][0]["remaining_after_MJ"] += 10 * STEP_TOL_MJ
    assert "K2_object_gained_inventory" in closure_failures(summarize(gained))
    # Below the declared tolerance nothing is reported.
    fine = _owned_run()
    fine[1]["fire_remaining_after_MJ"] -= 0.1 * STEP_TOL_MJ
    assert closure_failures(summarize(fine)) == []


def test_aggregate_room_is_its_own_single_owner() -> None:
    rows = [_row(i * DT, 0.002, [_obj("room_proxy_0", 3.0 - 0.002 * i, 0.0, proxy=True)],
                 fire_before=3.0 - 0.002 * i, room_mj=3.0, mode="aggregate") for i in range(5)]
    summary = summarize(rows)
    assert summary["owners_MJ"] == {"aggregate": pytest.approx(0.01)}
    assert summary["unowned_MJ"] == 0.0
    assert closure_failures(summary) == []
