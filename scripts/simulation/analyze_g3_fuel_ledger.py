"""G3-3 passive fuel ledger (schema ``g3_fuel_ledger_v3``): owners and closure.

Pure Python, read-only. The engine only *records* what ``step_room_fire`` did
(behind a member flag of ``CombustionSystem`` that the headless runner sets);
this module assigns every consumed MJ to an owner and checks that inventories
close, step by step and cumulatively.

Owners of the fire's solid consumption in one step:

* ``object:<id>`` - MJ debited from an explicit fuel object by the allocation;
* ``room_load``   - MJ the fire consumed but no object was debited for, in a
  room that declares a positive room load (legacy total owns it);
* ``aggregate``   - consumption in a room with no explicit objects (the
  ``room_proxy`` carries the room aggregate);
* ``unowned``     - MJ the fire consumed that no object was debited for, in a
  room whose load is declared only through objects. No owner exists.

``discarded`` is object inventory removed without any fire consumption (the
legacy burnout snap of <= 0.001 MJ to zero). It is reported, never hidden.

Closure tolerance, fixed before the fix was written (see G3-3 document):
``STEP_TOL_MJ`` per step and ``STEP_TOL_MJ * steps`` cumulatively for energy;
``SPECIES_REL_TOL`` for the species partition identity. Float64 rounding at
these magnitudes is < 1e-15 MJ; the smallest physical engine threshold is
1e-6 MJ and the burnout snap is 1e-3 MJ.

Released heat is *not* expected to equal consumption: HRR is a smoothed state,
30 % of unburned pyrolysate enters the retained pool and the rest is not
tracked. ``released_MJ`` and pool flows are reported, not closed.
"""

from __future__ import annotations

import json
import math
from pathlib import Path


SCHEMA = "g3_fuel_ledger_v3"
STEP_TOL_MJ = 1.0e-9
SPECIES_REL_TOL = 1.0e-12
SPECIES = ("co_kg", "co2_kg", "hcn_kg", "smoke_kg")


def _f(value: object, where: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"non-finite value at {where}")
    return number


def load(path: Path, room_id: int = 0) -> list[dict]:
    rows, last = [], -math.inf
    with Path(path).open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            row = json.loads(line)
            if row.get("schema_version") != SCHEMA:
                raise ValueError(f"{path}:{number}: schema mismatch")
            if int(row["room_id"]) != room_id:
                continue
            time_s = _f(row["time_s"], f"{path}:{number}")
            if time_s <= last:
                raise ValueError(f"{path}:{number}: non-monotonic time")
            last = time_s
            rows.append(row)
    return rows


def step_owners(row: dict) -> dict[str, object]:
    """Owner partition and closure residuals of one ledger step."""
    where = f"t={row['time_s']}"
    consumed = _f(row["consumed_MJ"], where) if row["fire_present_before"] else 0.0
    explicit = [o for o in row["objects"] if not o["is_proxy"]]
    owners: dict[str, float] = {}
    allocated_total = 0.0
    discarded = 0.0
    inventory_residual = 0.0
    over_cap = []
    for obj in explicit:
        allocated = _f(obj["allocated_MJ"], where)
        before = _f(obj["remaining_before_MJ"], where)
        after = _f(obj["remaining_after_MJ"], where)
        # Inventory lost without an allocation (burnout snap) is 'discarded'.
        lost = before - after - allocated
        if lost > STEP_TOL_MJ:
            discarded += lost
        elif lost < -STEP_TOL_MJ:
            inventory_residual = max(inventory_residual, -lost)
        if allocated:
            owners[f"object:{obj['id']}"] = allocated
        allocated_total += allocated
        cap = _f(obj["max_hrr_kw"], where)
        if cap > 0.0 and _f(obj["hrr_after_kw"], where) > cap * (1.0 + 1.0e-12) + 1.0e-9:
            over_cap.append(obj["id"])
    remainder = consumed - allocated_total
    if explicit:
        label = "room_load" if _f(row["declared_room_fuel_MJ"], where) > 0.0 else "unowned"
    else:
        label = "aggregate"
    if abs(remainder) > STEP_TOL_MJ or not explicit:
        owners[label] = owners.get(label, 0.0) + remainder
    solid_released = _f(row["actual_solid_burn_kw"], where) * _f(row["dt_s"], where) / 1000.0
    fire_residual = 0.0
    if row["fire_present_before"] and not row["fire_extinguished_this_step"]:
        fire_residual = abs(
            _f(row["fire_remaining_before_MJ"], where) - consumed - _f(row["fire_remaining_after_MJ"], where)
        )
    # Species are attributed by consumed-energy share: accounting, not chemistry.
    species_share = {}
    for key in SPECIES:
        total = _f(row["species"][key], where)
        shares = {owner: total * mj / consumed for owner, mj in owners.items()} if consumed > 0.0 else {}
        partition_error = abs(sum(shares.values()) - total) if shares else (abs(total) if consumed <= 0.0 else 0.0)
        species_share[key] = {"total": total, "by_owner": shares, "partition_error": partition_error,
                              "without_consumption": total if consumed <= 0.0 else 0.0}
    return {
        "time_s": float(row["time_s"]),
        "consumed_MJ": consumed,
        "owners_MJ": owners,
        "allocated_MJ": allocated_total,
        "discarded_MJ": discarded,
        "negative_object_residual_MJ": inventory_residual,
        "fire_inventory_residual_MJ": fire_residual,
        "partition_residual_MJ": abs(consumed - sum(owners.values())),
        "released_MJ": _f(row["hrr_applied_kw"], where) * _f(row["dt_s"], where) / 1000.0,
        "solid_released_MJ": solid_released,
        "pool_released_MJ": _f(row["actual_pool_burn_kw"], where) * _f(row["dt_s"], where) / 1000.0,
        # Solid heat released this step beyond the fuel pyrolysed (and debited)
        # this step: heat with no fuel owner in the step it is released.
        "solid_release_without_consumption_MJ": max(0.0, solid_released - consumed),
        "active_objects": sorted(o["id"] for o in explicit if o["active_before"]),
        "allocated_to_inactive_MJ": sum(_f(o["allocated_MJ"], where) for o in explicit if not o["active_before"]),
        "active_power_cap_kw": sum(max(0.0, _f(o["max_hrr_kw"], where)) for o in explicit if o["active_before"]),
        "hrr_requested_kw": _f(row["hrr_requested_kw"], where),
        "hrr_applied_kw": _f(row["hrr_applied_kw"], where),
        "power_cap_kw": _f(row["power_cap_kw"], where),
        "objects_over_own_cap": over_cap,
        "species": species_share,
    }


def summarize(rows: list[dict]) -> dict[str, object]:
    if not rows:
        return {"steps": 0}
    steps = [step_owners(row) for row in rows]
    owners: dict[str, float] = {}
    for step in steps:
        for owner, mj in step["owners_MJ"].items():
            owners[owner] = owners.get(owner, 0.0) + mj
    species: dict[str, dict[str, float]] = {}
    for key in SPECIES:
        by_owner: dict[str, float] = {}
        for step in steps:
            for owner, kg in step["species"][key]["by_owner"].items():
                by_owner[owner] = by_owner.get(owner, 0.0) + kg
        species[key] = {
            "total": sum(step["species"][key]["total"] for step in steps),
            "by_owner": by_owner,
            "without_consumption": sum(step["species"][key]["without_consumption"] for step in steps),
            "max_partition_error": max(step["species"][key]["partition_error"] for step in steps),
        }
    first = next((row for row in rows if row["fire_present_before"]), rows[0])
    last = rows[-1]
    objects0 = {o["id"]: _f(o["remaining_before_MJ"], "first") for o in first["objects"] if not o["is_proxy"]}
    objects1 = {o["id"]: _f(o["remaining_after_MJ"], "last") for o in last["objects"] if not o["is_proxy"]}
    consumed = sum(step["consumed_MJ"] for step in steps)
    allocated = sum(step["allocated_MJ"] for step in steps)
    discarded = sum(step["discarded_MJ"] for step in steps)
    object_closure = abs(sum(objects0.values()) - allocated - discarded - sum(objects1.values()))
    fire_closure = None
    if first["fire_present_before"] and last["fire_present_before"] and not last["fire_extinguished_this_step"]:
        fire_closure = abs(_f(first["fire_remaining_before_MJ"], "first") - consumed
                           - _f(last["fire_remaining_after_MJ"], "last"))
    return {
        "steps": len(steps),
        "mode": sorted({row["ownership_mode"] for row in rows}),
        "switch_on": sorted({bool(row["switch_on"]) for row in rows}),
        "consumed_MJ": consumed,
        "released_MJ": sum(step["released_MJ"] for step in steps),
        "solid_released_MJ": sum(step["solid_released_MJ"] for step in steps),
        "pool_released_MJ": sum(step["pool_released_MJ"] for step in steps),
        "solid_release_without_consumption_MJ": sum(step["solid_release_without_consumption_MJ"] for step in steps),
        "allocated_to_inactive_MJ": sum(step["allocated_to_inactive_MJ"] for step in steps),
        "max_solid_hrr_over_active_cap_kw": max(
            [row["actual_solid_burn_kw"] - step["active_power_cap_kw"]
             for step, row in zip(steps, rows)
             if row["fire_present_before"] and any(not o["is_proxy"] for o in row["objects"])] or [0.0]),
        "owners_MJ": owners,
        "allocated_MJ": allocated,
        "discarded_MJ": discarded,
        "unowned_MJ": owners.get("unowned", 0.0),
        "room_load_MJ": owners.get("room_load", 0.0),
        "max_step_fire_residual_MJ": max(step["fire_inventory_residual_MJ"] for step in steps),
        "max_step_partition_residual_MJ": max(step["partition_residual_MJ"] for step in steps),
        "max_step_negative_object_residual_MJ": max(step["negative_object_residual_MJ"] for step in steps),
        "cumulative_object_closure_MJ": object_closure,
        "cumulative_fire_closure_MJ": fire_closure,
        "max_hrr_requested_kw": max(step["hrr_requested_kw"] for step in steps),
        "max_hrr_applied_kw": max(step["hrr_applied_kw"] for step in steps),
        "max_hrr_over_power_cap_kw": max(
            [step["hrr_applied_kw"] - step["power_cap_kw"]
             for step, row in zip(steps, rows) if row["fire_present_before"]] or [0.0]),
        "objects_over_own_cap": sorted({oid for step in steps for oid in step["objects_over_own_cap"]}),
        "objects_initial_MJ": objects0,
        "objects_final_MJ": objects1,
        "species": species,
    }


def closure_failures(summary: dict[str, object]) -> list[str]:
    """Numerical closure of the ledger itself (independent of ownership)."""
    steps = int(summary["steps"])
    failures = []
    if steps == 0:
        return failures
    if float(summary["max_step_fire_residual_MJ"]) > STEP_TOL_MJ:
        failures.append("K1_fire_inventory_step")
    if float(summary["max_step_partition_residual_MJ"]) > STEP_TOL_MJ:
        failures.append("K3_owner_partition_step")
    if float(summary["max_step_negative_object_residual_MJ"]) > STEP_TOL_MJ:
        failures.append("K2_object_gained_inventory")
    if float(summary["cumulative_object_closure_MJ"]) > STEP_TOL_MJ * steps:
        failures.append("K4_object_inventory_cumulative")
    fire = summary["cumulative_fire_closure_MJ"]
    if fire is not None and float(fire) > STEP_TOL_MJ * steps:
        failures.append("K4_fire_inventory_cumulative")
    for key, item in summary["species"].items():
        if float(item["max_partition_error"]) > SPECIES_REL_TOL * max(1.0, abs(float(item["total"]))):
            failures.append(f"K5_species_partition_{key}")
    return failures


def explicit_owned_failures(summary: dict[str, object]) -> list[str]:
    """Ownership contract of the ``explicit_owned`` mode (switch ON).

    O1 no unowned MJ; O2 no inventory discarded without consumption;
    O3 nothing allocated to an object inactive at the start of the step;
    O4 solid HRR within the sum of active objects' caps and every object
    within its own cap; O5 no solid heat released beyond the fuel debited in
    the same step. Numerical tolerance as in ``closure_failures``.
    """
    steps = max(1, int(summary["steps"]))
    tol = STEP_TOL_MJ * steps
    failures = []
    if float(summary["unowned_MJ"]) > tol:
        failures.append("O1_unowned_MJ")
    if float(summary["discarded_MJ"]) > tol:
        failures.append("O2_discarded_MJ")
    if float(summary["allocated_to_inactive_MJ"]) > tol:
        failures.append("O3_inactive_object_debited")
    if float(summary["max_solid_hrr_over_active_cap_kw"]) > 1.0e-9 or summary["objects_over_own_cap"]:
        failures.append("O4_power_cap")
    if float(summary["solid_release_without_consumption_MJ"]) > tol:
        failures.append("O5_heat_without_fuel_owner")
    return failures
