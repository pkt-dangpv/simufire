#!/usr/bin/env python3
"""Offline oracle of the contract of stage M3 of the oxygen authority. It is not the engine.

Stage M3 is not implemented. This module states its contract in a form that can be run
and broken: a small reference of the transaction the contract asks for, a checker of
its invariants that looks only at what a step shows from outside, and one variant of
the reference for every defect the future implementation will have to be protected
against. The reference passing the checker proves nothing about the engine; what it
gives is the list of invariants written without ambiguity, and the evidence that each
declared defect is caught by the invariant it was declared against.

The transaction, per room that burns and per step:

1. The step opens: the owner builds the selection of the room, with what it holds
   (``M``) and what it owes in transit. ``available = max(0, M - obligations)``. A
   positive arrival that has not been delivered is not in it.
2. The fire proposes: its power after its filter and guards, and the fuel, the pool
   and the products it would write with that power. Nothing is written.
3. The fire asks for the oxygen of that power, ``k * heat``. It is granted what is
   available, and the owner RESERVES it for this room and step: the inventory does not
   change yet and nothing else can spend it. ``f = granted / asked``.
4. Everything extensive of the step is written with ``f``: heat, fuel, pool, products.
   The memory of the filter keeps the power that was accepted.
5. The transit delivers what is due, as it does today, and then the sink debits exactly
   what was reserved: no cap, nothing recomputed. What was reserved was available less
   everything the room owed, so the debit cannot fail and cannot be clipped.

Units: kg of O2, MJ, kW, s. ``k`` is the coefficient the engine uses today, taken as
its contract and not as a calorimetric measurement.

    python scripts/simulation/g3_m3_contract_model.py      # runs the declared scenarios
"""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import math

K_KG_PER_MJ = 0.076
CAP_PER_STEP = 0.05
# Tolerances of the contract. Dimensions in the name.
TOL_KG = 1.0e-9
TOL_MJ = TOL_KG / K_KG_PER_MJ
TOL_FRACTION = 1.0e-12

INVARIANTS = {
    "I1_debit_is_the_oxygen_of_the_heat": "kg debited in the step = k x MJ of heat accepted, within 1e-9 kg",
    "I2_no_heat_beyond_the_accepted": "MJ released in the step = MJ accepted: nothing adds heat after the decision",
    "I3_debit_within_the_available": "kg debited <= what the selection of the step said was available",
    "I4_inventory_never_negative": "the inventory is never below zero, also when what the room owes arrives",
    "I5_one_reservation_and_one_debit": "one reservation per room that burns and step and one debit, at the sink, of exactly that; nothing clipped",
    "I6_one_fraction_for_the_step": "fuel, pool and every product of the step are the proposed ones times the same fraction as the heat",
    "I7_filter_keeps_the_accepted": "the memory of the filter after the step is the power accepted, not the one proposed",
    "I8_building_budget_with_transit": "inventories plus transit change by exterior minus debit, within 1e-9 kg",
    "I9_refusal_writes_nothing": "a step the owner refuses writes no heat, fuel, pool, product or oxygen",
    "I10_selection_of_this_step": "the decision uses the selection built when this step opened, not an earlier one and not one rebuilt",
}

# Defects the future implementation must be protected against, with the invariant each was declared against.
DECLARED_DEFECTS = {
    "X01_limit_only_before_the_filter": "I1_debit_is_the_oxygen_of_the_heat",
    "X02_heat_accepted_above_the_backed": "I1_debit_is_the_oxygen_of_the_heat",
    "X03_fuel_and_products_from_the_refused_proposal": "I6_one_fraction_for_the_step",
    "X04_pending_arrival_spent": "I3_debit_within_the_available",
    "X05_obligation_ignored": "I4_inventory_never_negative",
    "X06_second_decision_on_the_same_oxygen": "I5_one_reservation_and_one_debit",
    "X07_late_debit_clipped": "I1_debit_is_the_oxygen_of_the_heat",
    "X08_stale_selection": "I10_selection_of_this_step",
    "X09_partial_write_on_refusal": "I9_refusal_writes_nothing",
    "X10_filter_keeps_the_proposal": "I7_filter_keeps_the_accepted",
    "X11_heat_added_after_the_decision": "I2_no_heat_beyond_the_accepted",
}


@dataclass
class Entry:
    """A signed net in transit to the room: positive arrives, negative is owed."""
    net_kg: float
    due_step: int


@dataclass
class Room:
    inventory_kg: float
    memory_kw: float = 0.0
    fuel_MJ: float = 1.0e9
    pool_MJ: float = 0.0
    transit: list = field(default_factory=list)


@dataclass
class Proposal:
    """What the fire would write with its power after the filter. Not proportional to one another on purpose."""
    power_kw: float
    heat_MJ: float
    fuel_MJ: float
    pool_credit_MJ: float
    products_kg: dict


def smooth(current: float, target: float, dt: float, rise_tau_s: float = 6.0, fall_tau_s: float = 20.0) -> float:
    """The first-order filter of the fire, as the engine writes it."""
    tau = rise_tau_s if target >= current else fall_tau_s
    return current + (target - current) * (1.0 - math.exp(-dt / tau))


def propose(room: Room, target_kw: float, dt: float, limit_target_kw: float | None = None) -> Proposal:
    aimed = target_kw if limit_target_kw is None else min(target_kw, limit_target_kw)
    power = smooth(room.memory_kw, aimed, dt)
    # Fuel follows what the fire aims at and the products follow a mixture: the engine does not keep them proportional to the heat.
    return Proposal(power_kw=power, heat_MJ=power * dt / 1000.0, fuel_MJ=1.15 * target_kw * dt / 1000.0,
                    pool_credit_MJ=0.05 * max(0.0, target_kw - power) * dt / 1000.0,
                    products_kg={"co": 0.0004 * power * dt / 1000.0, "smoke": 0.012 * max(power, target_kw) * dt / 1000.0,
                                 "co2": 0.083 * power * dt / 1000.0})


def available_kg(inventory_kg: float, transit: list) -> float:
    return max(0.0, inventory_kg - sum(-entry.net_kg for entry in transit if entry.net_kg < 0.0))


def step(room: Room, target_kw: float, dt: float, index: int, defect: str = "", owner_refuses: bool = False,
         previous_available_kg: float | None = None) -> dict:
    """One step of the reference transaction, or of one declared defect. Returns what the step shows from outside."""
    before = {"inventory_kg": room.inventory_kg, "memory_kw": room.memory_kw, "fuel_MJ": room.fuel_MJ, "pool_MJ": room.pool_MJ,
              "transit_kg": sum(entry.net_kg for entry in room.transit)}
    opened_available = available_kg(room.inventory_kg, room.transit)
    selection_available = opened_available
    if defect == "X04_pending_arrival_spent":
        selection_available += sum(entry.net_kg for entry in room.transit if entry.net_kg > 0.0 and entry.due_step <= index)
    if defect == "X05_obligation_ignored":
        selection_available = room.inventory_kg
    if defect == "X08_stale_selection" and previous_available_kg is not None:
        selection_available = previous_available_kg
    limit_target = selection_available / K_KG_PER_MJ / dt * 1000.0 if defect == "X01_limit_only_before_the_filter" else None
    proposal = propose(room, target_kw, dt, limit_target)
    asked = K_KG_PER_MJ * proposal.heat_MJ
    record = {"index": index, "dt": dt, "before": before, "available_at_the_opening_kg": opened_available,
              "selection_used_is_of_this_step": defect != "X08_stale_selection",
              "proposed": {"power_kw": proposal.power_kw, "heat_MJ": proposal.heat_MJ, "fuel_MJ": proposal.fuel_MJ,
                           "pool_credit_MJ": proposal.pool_credit_MJ, "products_kg": dict(proposal.products_kg)},
              "asked_kg": asked, "reservations": [], "debits": [], "refused": owner_refuses, "clipped_at_the_sink_kg": 0.0}
    if owner_refuses and defect != "X09_partial_write_on_refusal":
        # Nothing is written: the run stops here.
        record.update(heat_MJ=0.0, fuel_MJ=0.0, pool_credit_MJ=0.0, products_kg={name: 0.0 for name in proposal.products_kg},
                      fraction=0.0, memory_kw=room.memory_kw, inventory_kg=room.inventory_kg,
                      transit_kg=before["transit_kg"], lowest_inventory_kg=room.inventory_kg, arrived_kg=0.0)
        return record
    granted = min(asked, selection_available)
    if defect == "X01_limit_only_before_the_filter":
        granted = min(asked, room.inventory_kg * CAP_PER_STEP)
    fraction = granted / asked if asked > 0.0 else 1.0
    heat = proposal.heat_MJ * fraction
    scale_rest = fraction
    reserved = granted
    if defect in ("X02_heat_accepted_above_the_backed", "X01_limit_only_before_the_filter"):
        heat = proposal.heat_MJ
    if defect == "X03_fuel_and_products_from_the_refused_proposal":
        scale_rest = 1.0
    if defect == "X09_partial_write_on_refusal":
        reserved = 0.0
    if reserved > 0.0:
        record["reservations"].append(reserved)
    if defect == "X06_second_decision_on_the_same_oxygen" and asked > 0.0:
        # A second decision of the same step is granted against the same availability.
        again = min(0.5 * asked, selection_available)
        record["reservations"].append(again)
        reserved += again
        heat += again / K_KG_PER_MJ
    lowest = room.inventory_kg
    # The transit delivers what is due, after the decision.
    arrived = 0.0
    remaining = []
    for entry in room.transit:
        if entry.due_step <= index:
            room.inventory_kg += entry.net_kg
            arrived += entry.net_kg
            lowest = min(lowest, room.inventory_kg)
        else:
            remaining.append(entry)
    room.transit = remaining
    # The sink debits what was reserved, after the arrivals.
    debit = reserved
    if defect == "X07_late_debit_clipped":
        debit = min(reserved, max(0.0, room.inventory_kg) * CAP_PER_STEP)
        record["clipped_at_the_sink_kg"] = reserved - debit
    if debit > 0.0:
        room.inventory_kg -= debit
        record["debits"].append({"where": "sink", "kg": debit})
        lowest = min(lowest, room.inventory_kg)
    released = heat
    if defect == "X11_heat_added_after_the_decision":
        released = heat * 2.2
    room.fuel_MJ -= proposal.fuel_MJ * scale_rest
    room.pool_MJ += proposal.pool_credit_MJ * scale_rest
    room.memory_kw = proposal.power_kw if defect == "X10_filter_keeps_the_proposal" else proposal.power_kw * fraction
    record.update(heat_MJ=heat, released_MJ=released, fuel_MJ=proposal.fuel_MJ * scale_rest,
                  pool_credit_MJ=proposal.pool_credit_MJ * scale_rest,
                  products_kg={name: value * scale_rest for name, value in proposal.products_kg.items()},
                  fraction=fraction, memory_kw=room.memory_kw, inventory_kg=room.inventory_kg,
                  transit_kg=sum(entry.net_kg for entry in room.transit), lowest_inventory_kg=lowest, arrived_kg=arrived)
    return record


def violated(record: dict) -> list[str]:
    """The invariants a step breaks, from what it shows. It reads the record, not the function that made it."""
    broken = []
    debited = sum(item["kg"] for item in record["debits"])
    proposed = record["proposed"]
    if record["refused"]:
        wrote = record["heat_MJ"] or record["fuel_MJ"] or record["pool_credit_MJ"] or debited or any(record["products_kg"].values()) \
            or record["inventory_kg"] != record["before"]["inventory_kg"] or record["memory_kw"] != record["before"]["memory_kw"]
        return ["I9_refusal_writes_nothing"] if wrote else []
    if abs(debited - K_KG_PER_MJ * record["heat_MJ"]) > TOL_KG:
        broken.append("I1_debit_is_the_oxygen_of_the_heat")
    if abs(record["released_MJ"] - record["heat_MJ"]) > TOL_MJ:
        broken.append("I2_no_heat_beyond_the_accepted")
    if debited > record["available_at_the_opening_kg"] + TOL_KG:
        broken.append("I3_debit_within_the_available")
    if record["lowest_inventory_kg"] < -TOL_KG:
        broken.append("I4_inventory_never_negative")
    wanted = 1 if record["heat_MJ"] > 0.0 else 0
    if len(record["reservations"]) != wanted or len(record["debits"]) != wanted or record["clipped_at_the_sink_kg"] > 0.0 \
            or abs(sum(record["reservations"]) - debited) > TOL_KG:
        broken.append("I5_one_reservation_and_one_debit")
    if proposed["heat_MJ"] > 0.0:
        fraction = record["heat_MJ"] / proposed["heat_MJ"]
        pairs = [(record["fuel_MJ"], proposed["fuel_MJ"]), (record["pool_credit_MJ"], proposed["pool_credit_MJ"])]
        pairs += [(record["products_kg"][name], proposed["products_kg"][name]) for name in proposed["products_kg"]]
        if any(abs(got - fraction * asked) > TOL_FRACTION * max(1.0, abs(asked)) for got, asked in pairs) \
                or not -TOL_FRACTION <= fraction <= 1.0 + TOL_FRACTION:
            broken.append("I6_one_fraction_for_the_step")
        if abs(record["memory_kw"] - fraction * proposed["power_kw"]) > TOL_FRACTION * max(1.0, proposed["power_kw"]):
            broken.append("I7_filter_keeps_the_accepted")
    change = record["inventory_kg"] + record["transit_kg"] - record["before"]["inventory_kg"] - record["before"]["transit_kg"]
    if abs(change + debited) > TOL_KG:
        broken.append("I8_building_budget_with_transit")
    if not record["selection_used_is_of_this_step"]:
        broken.append("I10_selection_of_this_step")
    return broken


# ---------------------------------------------------------------- declared scenarios

def scenarios() -> dict:
    """Small cases that bring every part of the contract in. Targets in kW, a room of 13.3 kg of O2 unless said."""
    return {
        "fits": {"inventory_kg": 13.3, "dt": 0.25, "targets": [600.0] * 200},
        "runs_out": {"inventory_kg": 0.6, "dt": 0.25, "targets": [700.0] * 400},
        "drop_with_power_high": {"inventory_kg": 13.3, "dt": 0.25, "targets": [700.0] * 120 + [0.0] * 120, "drop_at": 120, "drop_to_kg": 0.02},
        "pending_arrival": {"inventory_kg": 0.05, "dt": 0.25, "targets": [700.0] * 80, "entries": [(1.0, 40)]},
        "obligation": {"inventory_kg": 2.0, "dt": 0.25, "targets": [700.0] * 160, "entries": [(-1.9, 120)]},
        "refused": {"inventory_kg": 13.3, "dt": 0.25, "targets": [700.0] * 40, "refuse_at": 30},
        "coarse_step": {"inventory_kg": 1.5, "dt": 2.0, "targets": [3000.0] * 60},
    }


def run(scenario: dict, defect: str = "") -> list[dict]:
    room = Room(inventory_kg=scenario["inventory_kg"],
                transit=[Entry(net, due) for net, due in scenario.get("entries", [])])
    records = []
    previous_available = None
    for index, target in enumerate(scenario["targets"]):
        if scenario.get("drop_at") == index:
            room.inventory_kg = scenario["drop_to_kg"]
        record = step(room, target, scenario["dt"], index, defect, owner_refuses=scenario.get("refuse_at") == index,
                      previous_available_kg=previous_available)
        previous_available = record["available_at_the_opening_kg"] if previous_available is None or defect != "X08_stale_selection" \
            else previous_available
        records.append(record)
        if record["refused"]:
            break
    return records


def broken_by(defect: str = "") -> dict:
    """Invariant -> scenarios in which a run breaks it."""
    found: dict = {}
    for name, scenario in scenarios().items():
        for record in run(scenario, defect):
            for invariant in violated(record):
                found.setdefault(invariant, set()).add(name)
    return {invariant: sorted(names) for invariant, names in sorted(found.items())}


# ---------------------------------------------------------------- algebraic controls

def burned_until_it_runs_out(inventory_kg: float, power_kw: float, dt: float, seconds: float, cap: bool) -> float:
    """MJ a constant demand larger than the inventory gets in `seconds`, with the 5 % per step or with availability alone."""
    held, heat = inventory_kg, 0.0
    for _ in range(int(round(seconds / dt))):
        asked = K_KG_PER_MJ * power_kw * dt / 1000.0
        granted = min(asked, held * CAP_PER_STEP if cap else held)
        held -= granted
        heat += granted / K_KG_PER_MJ
    return heat


def cap_closed_form(inventory_kg: float, dt: float, seconds: float) -> float:
    """Closed form of the same thing when the cap acts in every step: M0 (1 - 0.95^n) / k."""
    return inventory_kg * (1.0 - (1.0 - CAP_PER_STEP) ** int(round(seconds / dt))) / K_KG_PER_MJ


def main() -> int:
    print(json.dumps({"reference": broken_by(), "defects": {name: broken_by(name) for name in DECLARED_DEFECTS}}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
