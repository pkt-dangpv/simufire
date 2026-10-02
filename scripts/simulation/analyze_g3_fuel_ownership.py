"""Per-step ownership analysis of a G3 ``fuel_source_ledger.jsonl`` (room 0).

Pure Python and read-only: it never changes the engine or a scenario. For
every ledger step it compares the energy consumed by the room fire with the
energy that left explicit fuel objects (``room_proxy_*`` excluded) and keeps
the CO and smoke the room generated in that step.

Definitions (fixed before the 2026-09-29 runs; see G3-1 closure document):

* ``unowned`` step: the room declares explicit objects, the fire consumes
  energy (> ``ENERGY_EPS_MJ``) and no explicit object burns
  (<= ``ENERGY_EPS_MJ``). Its MJ, CO and smoke have no object owner.
* ``net_gap_MJ`` = room consumption - explicit burn over the run. Positive:
  energy burned without an object; negative: objects drained more than the
  fire consumed (inventory desynchronisation).
* ``double_count``: the same energy counted twice, i.e. the object HRR sum
  exceeds the room HRR, or explicit burn exceeds room consumption by more
  than ``DOUBLE_COUNT_REL`` of it. Doubling would be of order 100 %; the
  known step desynchronisation of the single-object control is 0.005 %.

The engine computes no per-object species, so an inactive object's effect on
CO/smoke is measured by counterfactual runs, not inferred here.
"""

from __future__ import annotations

import json
import math
from pathlib import Path


SCHEMA = "g3_fuel_source_step_v2"
ENERGY_EPS_MJ = 1.0e-6
HRR_EPS_KW = 1.0e-3
DOUBLE_COUNT_REL = 0.01
OWNERLESS_REL = 0.01


def _finite(value: object, where: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"non-finite value at {where}")
    return number


def load_rows(path: Path, room_id: int = 0) -> list[dict]:
    rows = []
    last_time = -math.inf
    with Path(path).open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            row = json.loads(line)
            if row.get("schema_version") != SCHEMA:
                raise ValueError(f"{path}:{line_number}: ledger schema mismatch")
            if int(row.get("room_id", -1)) != room_id:
                continue
            time_s = _finite(row["time_s"], f"{path}:{line_number}")
            if time_s <= last_time:
                raise ValueError(f"{path}:{line_number}: non-monotonic time")
            last_time = time_s
            rows.append(row)
    if not rows:
        raise ValueError(f"{path}: no ledger rows for room {room_id}")
    return rows


def analyze_rows(rows: list[dict]) -> dict[str, object]:
    totals = {
        "room_consumed_MJ": 0.0,
        "explicit_burn_MJ": 0.0,
        "unowned_MJ": 0.0,
        "co_generated_kg": 0.0,
        "co_generated_unowned_kg": 0.0,
        "smoke_generated_kg": 0.0,
        "smoke_generated_unowned_kg": 0.0,
        "nominal_explicit_co_kg": 0.0,
        "step_gap_positive_MJ": 0.0,
        "step_gap_negative_MJ": 0.0,
    }
    objects: dict[str, dict[str, object]] = {}
    unowned_steps = 0
    first_unowned_time_s = None
    last_consuming_time_s = None
    max_object_hrr_excess_kw = 0.0
    max_hrr_kw = 0.0
    has_explicit = False
    for row in rows:
        where = f"t={row['time_s']}"
        consumed = _finite(row["room_fuel_consumed_delta_MJ"], where)
        explicit = _finite(row["explicit_object_burn_delta_MJ"], where)
        co = _finite(row["room_co_generated_delta_kg"], where)
        smoke = _finite(row["room_smoke_generated_kg_total_delta"], where)
        hrr = _finite(row["hrr_after_kw"], where)
        max_hrr_kw = max(max_hrr_kw, hrr)
        totals["room_consumed_MJ"] += consumed
        totals["explicit_burn_MJ"] += explicit
        totals["co_generated_kg"] += co
        totals["smoke_generated_kg"] += smoke
        totals["nominal_explicit_co_kg"] += _finite(row["nominal_explicit_co_from_burn_kg"], where)
        if consumed > ENERGY_EPS_MJ:
            last_consuming_time_s = float(row["time_s"])
        explicit_rows = [obj for obj in row["objects"] if not obj.get("is_proxy")]
        if explicit_rows:
            has_explicit = True
            gap = consumed - explicit
            if gap > 0.0:
                totals["step_gap_positive_MJ"] += gap
            else:
                totals["step_gap_negative_MJ"] += -gap
            if consumed > ENERGY_EPS_MJ and explicit <= ENERGY_EPS_MJ:
                totals["unowned_MJ"] += consumed
                totals["co_generated_unowned_kg"] += co
                totals["smoke_generated_unowned_kg"] += smoke
                unowned_steps += 1
                if first_unowned_time_s is None:
                    first_unowned_time_s = float(row["time_s"])
        object_hrr_sum = 0.0
        for obj in explicit_rows:
            state = objects.setdefault(str(obj["id"]), {
                "burn_MJ": 0.0, "max_hrr_kw": 0.0, "steps_burning": 0,
                "initial_remaining_MJ": _finite(obj["remaining_before_MJ"], where),
                "final_remaining_MJ": 0.0, "final_state": "",
                "co_yield_kg_per_MJ": _finite(obj["co_yield_kg_per_MJ"], where),
                "exhausted_time_s": None,
            })
            burn = _finite(obj["burn_MJ"], where)
            object_hrr = _finite(obj["hrr_after_kw"], where)
            remaining = _finite(obj["remaining_after_MJ"], where)
            object_hrr_sum += object_hrr
            state["burn_MJ"] = float(state["burn_MJ"]) + burn
            state["max_hrr_kw"] = max(float(state["max_hrr_kw"]), object_hrr)
            state["steps_burning"] = int(state["steps_burning"]) + (1 if burn > ENERGY_EPS_MJ else 0)
            if state["exhausted_time_s"] is None and remaining <= 0.001 < float(state["initial_remaining_MJ"]):
                state["exhausted_time_s"] = float(row["time_s"])
            state["final_remaining_MJ"] = remaining
            state["final_state"] = str(obj["state_after"])
        max_object_hrr_excess_kw = max(max_object_hrr_excess_kw, object_hrr_sum - hrr)
    consumed = totals["room_consumed_MJ"]
    inactive = sorted(
        object_id for object_id, state in objects.items()
        if abs(float(state["burn_MJ"])) <= ENERGY_EPS_MJ and float(state["max_hrr_kw"]) <= HRR_EPS_KW
    )
    return {
        "steps": len(rows),
        "has_explicit_objects": has_explicit,
        **totals,
        "net_gap_MJ": consumed - totals["explicit_burn_MJ"],
        "unowned_steps": unowned_steps,
        "first_unowned_time_s": first_unowned_time_s,
        "last_consuming_time_s": last_consuming_time_s,
        "max_hrr_kw": max_hrr_kw,
        "max_object_hrr_excess_over_room_kw": max_object_hrr_excess_kw,
        "effective_co_yield_kg_per_MJ": totals["co_generated_kg"] / consumed if consumed > ENERGY_EPS_MJ else None,
        "effective_smoke_yield_kg_per_MJ": totals["smoke_generated_kg"] / consumed if consumed > ENERGY_EPS_MJ else None,
        "objects": objects,
        "inactive_objects": inactive,
        "remaining_in_explicit_objects_MJ": sum(float(s["final_remaining_MJ"]) for s in objects.values()),
        # Burned by the fire plus still held by objects, minus what objects held
        # initially. With no declared room load it must be ~0 (conservation).
        "inventory_excess_MJ": consumed + sum(float(s["final_remaining_MJ"]) for s in objects.values())
            - sum(float(s["initial_remaining_MJ"]) for s in objects.values()),
    }


def analyze(path: Path, room_id: int = 0) -> dict[str, object]:
    return analyze_rows(load_rows(path, room_id))


CONTRACT_REL = 0.01  # Declared before the 2026-09-29 batch; not fitted to it.


def _rel_diff(a: float, b: float) -> float:
    scale = max(abs(a), abs(b), 1.0e-12)
    return abs(a - b) / scale


def contract_violations(
    results: dict[str, dict], declared: dict[str, dict] | None = None
) -> dict[str, list[str]]:
    """Proposed `explicit_objects` ownership contract, per case and across cases.

    Returns the violated clauses by case. An empty dict means the contract
    holds. ``explicit_room_aggregate`` is judged as ``legacy_lumped``.
    ``declared`` optionally gives, per case, the scenario's ``room_MJ`` and
    ``object_max_hrr_kw`` (id -> kW) for clauses C8/C9.
    """
    declared = declared or {}
    violations: dict[str, list[str]] = {}

    def fail(case: str, clause: str) -> None:
        violations.setdefault(case, []).append(clause)

    for case, result in results.items():
        consumed = float(result["room_consumed_MJ"])
        if classify(result)["double_count"]:
            fail(case, "C1_no_double_count")
        if result["has_explicit_objects"] and float(result["net_gap_MJ"]) > CONTRACT_REL * max(consumed, 1.0e-9):
            fail(case, "C2_every_consumed_MJ_has_an_explicit_owner")
        if result["has_explicit_objects"] and float(result["co_generated_unowned_kg"]) > CONTRACT_REL * max(
                float(result["co_generated_kg"]), 1.0e-15):
            fail(case, "C3_no_species_from_unowned_energy")
        spec = declared.get(case, {})
        if result["has_explicit_objects"] and spec.get("room_MJ", None) == 0.0 \
                and float(result["inventory_excess_MJ"]) > CONTRACT_REL * max(consumed, 1.0e-9):
            fail(case, "C8_burned_plus_remaining_equals_initial_inventory")
        for object_id, cap_kw in spec.get("object_max_hrr_kw", {}).items():
            state = result["objects"].get(object_id)
            if state is not None and cap_kw > 0.0 and float(state["max_hrr_kw"]) > cap_kw * (1.0 + CONTRACT_REL):
                fail(case, "C9_object_hrr_within_its_declared_max")
                break
    empty = results.get("empty_room")
    if empty is not None and (float(empty["room_consumed_MJ"]) > 1.0e-6
                              or float(empty["co_generated_kg"]) > 1.0e-12
                              or float(empty["smoke_generated_kg"]) > 1.0e-12):
        fail("empty_room", "C4_empty_room_creates_nothing")
    below = results.get("room_below_objects")
    if below is not None and float(below["remaining_in_explicit_objects_MJ"]) > CONTRACT_REL * sum(
            float(o["initial_remaining_MJ"]) for o in below["objects"].values()) \
            and below["last_consuming_time_s"] is not None:
        fail("room_below_objects", "C5_room_total_does_not_cap_explicit_inventory")
    single, cold = results.get("single_object"), results.get("second_object_cold")
    if single is not None and cold is not None:
        if cold["inactive_objects"] and (
                _rel_diff(float(single["co_generated_kg"]), float(cold["co_generated_kg"])) > CONTRACT_REL
                or _rel_diff(float(single["smoke_generated_kg"]), float(cold["smoke_generated_kg"])) > CONTRACT_REL):
            fail("second_object_cold", "C6_inactive_object_does_not_change_species")
        if _rel_diff(float(single["room_consumed_MJ"]), float(cold["room_consumed_MJ"])) > CONTRACT_REL:
            fail("second_object_cold", "C7_inactive_object_energy_is_not_burned")
    real = results.get("ambiguous_real_compact_salon")
    real_eq = results.get("ambiguous_real_compact_salon_cold_yields_equalised")
    if real is not None and real_eq is not None:
        changed = [o for o in real["inactive_objects"] if o != "compact_sofa"]
        if changed and (
                _rel_diff(float(real["co_generated_kg"]), float(real_eq["co_generated_kg"])) > CONTRACT_REL
                or _rel_diff(float(real["smoke_generated_kg"]), float(real_eq["smoke_generated_kg"])) > CONTRACT_REL):
            fail("ambiguous_real_compact_salon", "C6_inactive_object_does_not_change_species")
    return violations


def classify(result: dict[str, object]) -> dict[str, bool]:
    consumed = max(float(result["room_consumed_MJ"]), ENERGY_EPS_MJ)
    return {
        "double_count": float(result["max_object_hrr_excess_over_room_kw"]) > 0.01
            or -float(result["net_gap_MJ"]) > DOUBLE_COUNT_REL * consumed,
        "ownerless_fuel": bool(result["has_explicit_objects"])
            and float(result["net_gap_MJ"]) > OWNERLESS_REL * consumed,
        "aggregate_room_owner_only": not result["has_explicit_objects"]
            and float(result["room_consumed_MJ"]) > 1.0e-3,
        "inactive_objects_present": bool(result["inactive_objects"]),
    }
