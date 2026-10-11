#!/usr/bin/env python3
"""The house cases of stage M2-V: whole runs with the room oxygen inventory on, and the
causal control of the historical gap.

``o2_closed`` and ``o2_reopen_300`` are the diagnostic controls of
``run_g3_energy_controls.py``, unchanged: the product house, a sofa in the Salon, the
Salon door closed and, in the second, opened at 300 s. Nothing of them is disabled,
raised or replaced. Every launch goes through the monitored launcher, one Godot at a
time, and writes ``o2_inventory_trace.jsonl``, one row per step. Kinds of run:

- ``off``: the historical route. Its six outputs must equal, byte for byte, those of
  the identity run given with ``--identity-run``: the trace is passive.
- ``on``: the same scenario with ``o2_room_inventory_enabled`` raised through the
  ``engine_overrides`` of the headless diagnostic runner. Evaluated here, in Python:
  the three budgets of every step with the transit, every venting event against its
  closed form, C1 and C2, the fire, what the cap of the sink clipped, and whether any
  room is ever richer than the outside air.
- ``gap_passive``: the historical route with a DIAGNOSTIC COPY of the oxygen system
  that only counts, call by call, what ``_apply_room_o2_mass_delta`` was asked to
  apply, what it applied and what it discarded, and why. Its six outputs must equal
  those of the identity run: the counters change nothing.
- ``gap_control``: the same copy with the ceiling of that one function taken out, and
  the per-writer ledger of the engine on. This run is NOT the historical route and is
  not a fix of the transport: it is the control that tells that discard from any
  other cause.

A diagnostic copy is an exact text replacement in the working tree (every anchor once),
its diff is saved next to the run, and the original bytes are put back and verified by
SHA-256 before anything else runs. A run that the mode refuses is not hidden: the route,
the step and what had happened until then are reported, and it is not said to be whole.

    python scripts/simulation/run_g3_o2_venting_house.py --kind on --kind off \
        --identity-run runs/g3_balance_identity_off_ledgeroff_<stamp> --out <file.json>

``--latest`` evaluates the latest run of every kind of every case instead of launching.
"""

from __future__ import annotations

import argparse
import copy
import csv
import difflib
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_energy_controls as energy  # noqa: E402
from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402
from scripts.simulation import run_g3_o2_selection_house as m2  # noqa: E402

SCHEMA = "g3_o2_venting_house_v1"
CASES = m2.CASES
KINDS = ("off", "on", "gap_passive", "gap_control")
LABEL = "g3_o2_venting_house"
SWITCH = m2.SWITCH
TRACE = m2.TRACE
VENTING = "pressure_venting"
BY_STEP = "o2_budget_by_step.csv"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"
# Oracle constants, written here and not read from the engine.
M_O2, M_AIR, DENSITY = 2.0 * 15.999 / 1000.0, 28.9647 / 1000.0, 1.2
KG_PER_MJ, CAP, OUTSIDE = 0.076, 0.05, 0.209
GAP_KG = 1.0e-9
# A room counts as richer than the outside air above this much of a mole fraction.
RICHER = 1.0e-12
# A credit to a room already at the outside concentration counts above this: below it, it is the rounding of a room at 0.209.
CREDIT_KG = 1.0e-12

# ---------------------------------------------------------------- the diagnostic copy

_COUNTERS = '''var room_o2_inventory = null
## DIAGNOSTIC COPY (stage M2-V, causal control of the historical gap). It only counts.
## The distributed system does not have this.
var g3_o2_diagnostic_counters: Dictionary = {"variant": "%s", "by_category_site_and_room": {}}
var _g3_site: String = "unknown"


func _g3_count(category: String, room: RoomModel, amount_kg: float, by_site: bool = true) -> void:
	var counters: Dictionary = g3_o2_diagnostic_counters
	counters[category + "_kg"] = float(counters.get(category + "_kg", 0.0)) + amount_kg
	counters[category + "_calls"] = int(counters.get(category + "_calls", 0)) + 1
	if by_site:
		var key: String = "%%s|%%s|%%d" %% [category, _g3_site, room.id]
		var by: Dictionary = counters["by_category_site_and_room"]
		by[key] = float(by.get(key, 0.0)) + amount_kg
'''

_COUNTING = '''	var actual_delta_kg: float = (room.o2 - o2_before) * room_air_mass_kg
	var g3_unclamped: float = room_o2_mass_kg / room_air_mass_kg
	_g3_count("intended", room, delta_o2_kg, false)
	_g3_count("applied", room, actual_delta_kg, false)
	if g3_unclamped > o2_nominal:
		_g3_count("discarded_at_the_ceiling", room, delta_o2_kg - actual_delta_kg)
		_g3_count("left_above_the_ceiling", room, maxf(0.0, room.o2 - maxf(o2_before, o2_nominal)) * room_air_mass_kg)
	elif g3_unclamped < 0.0:
		_g3_count("discarded_at_the_floor", room, delta_o2_kg - actual_delta_kg)
	else:
		_g3_count("rounding", room, delta_o2_kg - actual_delta_kg, false)
'''

# (old, new): every `old` must occur exactly once in the oxygen system.
_PASSIVE_EDITS = (
    ("var room_o2_inventory = null\n", _COUNTERS % "passive"),
    ("\t_apply_room_o2_mass_delta(room_a, o2_b_out_kg, air_density_kg_m3)\n",
     "\t_g3_site = \"background_exchange\"\n\t_apply_room_o2_mass_delta(room_a, o2_b_out_kg, air_density_kg_m3)\n"),
    ("\t\t_apply_room_o2_mass_delta(hot_room, hot_room_delta_o2_kg, air_density_kg_m3)\n",
     "\t\t_g3_site = \"credit_to_the_hot_room_at_once\"\n\t\t_apply_room_o2_mass_delta(hot_room, hot_room_delta_o2_kg, air_density_kg_m3)\n"),
    ("\t_apply_room_o2_mass_delta(cold_room, cold_room_delta_o2_kg, air_density_kg_m3)\n",
     "\t_g3_site = \"cold_room_at_once\"\n\t_apply_room_o2_mass_delta(cold_room, cold_room_delta_o2_kg, air_density_kg_m3)\n"),
    ("\t\t_apply_room_o2_mass_delta(target, delta_o2_kg, air_density_kg_m3)\n",
     "\t\t_g3_site = \"deferred_delivery\"\n\t\t_apply_room_o2_mass_delta(target, delta_o2_kg, air_density_kg_m3)\n"),
    ("\tif room == null or absf(delta_o2_kg) <= 0.000001:\n\t\treturn\n\n\tvar room_air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)\n\tvar o2_before: float = room.o2\n",
     "\tif room == null or absf(delta_o2_kg) <= 0.000001:\n\t\tif room != null:\n\t\t\t_g3_count(\"dropped_below_the_threshold\", room, delta_o2_kg)\n\t\treturn\n\n"
     "\tvar room_air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)\n\tvar o2_before: float = room.o2\n"),
    ("\tvar actual_delta_kg: float = (room.o2 - o2_before) * room_air_mass_kg\n", _COUNTING),
)
# The control: the same counters, and the ceiling of that one write taken out.
_CEILING = ("\troom.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)\n\t# SF-O1F",
            "\troom.o2 = maxf(0.0, room_o2_mass_kg / room_air_mass_kg)\n\t# SF-O1F")
DIAGNOSTIC_EDITS = {
    "gap_passive": _PASSIVE_EDITS,
    "gap_control": tuple((old, new.replace('"variant": "passive"', '"variant": "ceiling_taken_out"')) for old, new in _PASSIVE_EDITS)
                   + (_CEILING,),
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def diagnostic_source(kind: str, original: str) -> str:
    """The oxygen system of a diagnostic copy, from the distributed one. Every anchor exactly once."""
    patched = original
    for old, new in DIAGNOSTIC_EDITS[kind]:
        if original.count(old) != 1:
            raise RuntimeError(f"diagnostic copy {kind}: anchor found {original.count(old)} times: {old[:60]!r}")
        patched = patched.replace(old, new)
    return patched


class DiagnosticCopy:
    """Puts a diagnostic copy of the oxygen system in the working tree and takes it out again."""

    def __init__(self, kind: str):
        self.kind = kind
        self.path = ROOT / OXYGEN
        self.original = self.path.read_bytes()
        self.patched = diagnostic_source(kind, self.original.decode("utf-8")).encode("utf-8")
        self.diff = "".join(difflib.unified_diff(
            self.original.decode("utf-8").splitlines(keepends=True), self.patched.decode("utf-8").splitlines(keepends=True),
            OXYGEN, f"{OXYGEN} (diagnostic copy: {kind})"))

    def __enter__(self):
        self.path.write_bytes(self.patched)
        return self

    def __exit__(self, *_):
        self.path.write_bytes(self.original)
        if _sha(self.path.read_bytes()) != _sha(self.original):
            raise RuntimeError(f"{OXYGEN} not restored byte for byte")
        return False

    def describe(self) -> dict:
        return {"file": OXYGEN, "kind": self.kind, "original_sha256": _sha(self.original), "copy_sha256": _sha(self.patched),
                "diff_sha256": _sha(self.diff.encode("utf-8")), "diff_lines": len(self.diff.splitlines()),
                "restored_sha256": _sha(self.path.read_bytes()), "restored": _sha(self.path.read_bytes()) == _sha(self.original)}


# ---------------------------------------------------------------- oracle

def _n_o2(volume_m3: float) -> float:
    """kg of O2 a room would hold at mole fraction one: its reference moles by the molar mass of O2."""
    return (volume_m3 * DENSITY / M_AIR) * M_O2


def _dilution(held_kg: float, gas_kg: float, volume_m3: float) -> dict:
    """The dilution of the contract, in closed form: gas enters, mixes with the room, the same mass of mixture leaves."""
    room_gas = volume_m3 * DENSITY
    entering = OUTSIDE * gas_kg * M_O2 / M_AIR
    return {"in_kg": entering, "out_kg": (held_kg + entering) * gas_kg / (room_gas + gas_kg),
            "after_kg": (held_kg + entering) * room_gas / (room_gas + gas_kg)}


# ---------------------------------------------------------------- mode on

def evaluate_on(rows: list[dict], scenario: dict, folder: Path | None = None) -> dict:
    """Budgets, venting, selections, transit and enrichment of every step, with the mode on."""
    per_hour = m2._infiltration_per_hour(scenario)
    out = {"steps": 0, "room_gap_kg": 0.0, "building_gap_kg": 0.0, "oracle_gap_kg": 0.0,
           "largest_transit_kg": 0.0, "largest_number_of_entries": 0, "consumed_kg": 0.0, "clipped_kg": 0.0, "steps_with_a_clip": 0,
           "outside_kg": 0.0, "infiltration_net_kg": 0.0, "delayed_exchanges": 0, "debits": 0,
           "debits_on_the_selection_the_fire_read": 0, "rooms_where_the_fire_read_its_selection": 0, "rooms_consulted": 0,
           "more_than_one_debit_in_a_step": 0, "debits_above_what_was_available": 0, "selections_missing": 0,
           "lowest_inventory_kg": float("inf"), "refused": None}
    venting = {"events": 0, "gas_kg": 0.0, "in_kg": 0.0, "out_kg": 0.0, "net_kg": 0.0, "worst_operation_kg": 0.0,
               "more_than_one_event_of_a_room_in_a_step": 0, "first_at_s": None, "last_at_s": None, "by_room": {},
               "largest_event_gas_kg": 0.0, "events_with_a_negative_net": 0}
    richer = {"rooms": {}, "credits_to_a_room_at_or_above_the_outside": {}}
    by_step: list[list] = []
    previous_time = 0.0
    for row in rows:
        if out["refused"] is None and (row.get("failure") or row.get("state") == "rejected"):
            out["refused"] = {"time_s": row["time_s"], "step": row.get("step"), "failure": row.get("failure"),
                              "rejections": row.get("rejections", [])}
        if out["refused"] is not None:
            continue
        time_s = float(row["time_s"])
        dt = time_s - previous_time
        previous_time = time_s
        out["steps"] += 1
        before, rooms = row["before"], row["rooms"]
        volume = {room: float(state["volume_m3"]) for room, state in rooms.items()}
        by_room = {room: 0.0 for room in rooms}
        outside = consumed = clipped = venting_expected = 0.0
        step_in = step_out = infiltration = 0.0
        debits: dict = {}
        events_by_room: dict = {}

        def credit(room: str, net_kg: float, held_kg: float, how: str) -> None:
            """A positive net into a room that is already at the outside concentration, or above it."""
            if net_kg > CREDIT_KG and held_kg / _n_o2(volume[room]) >= OUTSIDE - RICHER:
                item = richer["credits_to_a_room_at_or_above_the_outside"].setdefault(how, {"count": 0, "kg": 0.0, "by_room": {}})
                item["count"] += 1
                item["kg"] += net_kg
                item["by_room"][room] = item["by_room"].get(room, 0.0) + net_kg

        for operation in row["operations"]:
            kind = operation["kind"]
            if kind == "consume":
                room = str(int(operation["room"]))
                by_room[room] -= operation["applied_kg"]
                consumed += operation["applied_kg"]
                clipped += operation["clipped_kg"]
                debits.setdefault(room, []).append(operation)
            elif kind == "outside":
                room = str(int(operation["room"]))
                net = operation["in_kg"] - operation["out_kg"]
                by_room[room] += net
                outside += net
                if operation.get("cause") == VENTING:
                    expected = _dilution(float(operation["before_kg"]), float(operation["gas_kg"]), volume[room])
                    venting_expected += expected["in_kg"] - expected["out_kg"]
                    venting["worst_operation_kg"] = max(
                        venting["worst_operation_kg"], abs(operation["in_kg"] - expected["in_kg"]),
                        abs(operation["out_kg"] - expected["out_kg"]), abs(operation["after_kg"] - expected["after_kg"]))
                    venting["events"] += 1
                    venting["gas_kg"] += operation["gas_kg"]
                    venting["in_kg"] += operation["in_kg"]
                    venting["out_kg"] += operation["out_kg"]
                    venting["net_kg"] += net
                    venting["largest_event_gas_kg"] = max(venting["largest_event_gas_kg"], operation["gas_kg"])
                    venting["events_with_a_negative_net"] += net < 0.0
                    venting["first_at_s"] = time_s if venting["first_at_s"] is None else venting["first_at_s"]
                    venting["last_at_s"] = time_s
                    item = venting["by_room"].setdefault(room, {"events": 0, "in_kg": 0.0, "out_kg": 0.0, "gas_kg": 0.0})
                    item["events"] += 1
                    item["in_kg"] += operation["in_kg"]
                    item["out_kg"] += operation["out_kg"]
                    item["gas_kg"] += operation["gas_kg"]
                    events_by_room[room] = events_by_room.get(room, 0) + 1
                    step_in += operation["in_kg"]
                    step_out += operation["out_kg"]
                    credit(room, net, float(operation["before_kg"]), "venting")
                else:
                    infiltration += net
                    credit(room, net, float(operation["before_kg"]), "infiltration")
            elif kind == "interior":
                donor, receiver = str(int(operation["donor"])), str(int(operation["receiver"]))
                donor_net = operation["to_donor_kg"] - operation["to_receiver_kg"]
                by_room[donor] += donor_net
                credit(donor, donor_net, float(operation["donor_before_kg"]), "credit to the donor of an exchange, at once")
                if operation["delayed"]:
                    out["delayed_exchanges"] += 1
                else:
                    by_room[receiver] -= donor_net
                    credit(receiver, -donor_net, float(operation["receiver_before_kg"]), "receiver of an exchange with no delay")
            elif kind == "arrival":
                room = str(int(operation["room"]))
                by_room[room] += operation["net_kg"]
                credit(room, operation["net_kg"], float(operation["before_kg"]), "arrival of the transit")
        venting["more_than_one_event_of_a_room_in_a_step"] += sum(count > 1 for count in events_by_room.values())
        expected = venting_expected
        total_before = float(before["transit_kg"])
        total_after = float(row["transit_kg"])
        worst_room = 0.0
        highest_x = 0.0
        for room, state in rooms.items():
            held_before = float(before["inventory_kg"][room])
            held_after = float(state["inventory_kg"])
            total_before += held_before
            total_after += held_after
            worst_room = max(worst_room, abs(held_after - held_before - by_room[room]))
            out["lowest_inventory_kg"] = min(out["lowest_inventory_kg"], held_after)
            # Closed forms, on what the room holds when the oxygen step reaches it.
            held = held_before + float(before["due"].get(room, 0.0))
            demand = float(state["power_kw"]) / 1000.0 * KG_PER_MJ * dt
            gas = volume[room] * (per_hour / 3600.0) * DENSITY * dt
            expected += m2._parcel(OUTSIDE - m2._x(held, volume[room]), gas) - min(demand, held * CAP)
            # Is the room richer than the outside air, and is it so once what travels to it is counted?
            x = held_after / _n_o2(volume[room])
            highest_x = max(highest_x, x)
            in_transit = float(row.get("transit_to", {}).get(room, 0.0))
            effective = (held_after + in_transit) / _n_o2(volume[room])
            if x > OUTSIDE + RICHER:
                item = richer["rooms"].setdefault(room, {
                    "steps": 0, "first_at_s": time_s, "last_at_s": time_s, "largest_excess_of_the_fraction": 0.0,
                    "largest_excess_kg": 0.0, "at_s": time_s, "steps_in_which_the_effective_reading_is_richer_too": 0,
                    "largest_excess_of_the_effective_fraction": 0.0, "excess_kg_seconds": 0.0})
                item["steps"] += 1
                item["last_at_s"] = time_s
                item["excess_kg_seconds"] += (held_after - OUTSIDE * _n_o2(volume[room])) * dt
                if x - OUTSIDE > item["largest_excess_of_the_fraction"]:
                    item["largest_excess_of_the_fraction"] = x - OUTSIDE
                    item["largest_excess_kg"] = held_after - OUTSIDE * _n_o2(volume[room])
                    item["at_s"] = time_s
                if effective > OUTSIDE + RICHER:
                    item["steps_in_which_the_effective_reading_is_richer_too"] += 1
                    item["largest_excess_of_the_effective_fraction"] = max(
                        item["largest_excess_of_the_effective_fraction"], effective - OUTSIDE)
            # The selection of the room: the one the fire read and the one the sink debited.
            selection = row["selections"].get(room)
            if selection is None:
                out["selections_missing"] += 1
                continue
            out["rooms_consulted"] += 1
            if float(state["oxygen_the_fire_read"]) == float(selection["mole_fraction"]) \
                    and state["fire_reads"] == selection["deposit"] == "room_inventory" \
                    and abs(float(selection["mole_fraction"]) - m2._x(held_before, volume[room])) <= 1.0e-12:
                out["rooms_where_the_fire_read_its_selection"] += 1
            room_debits = debits.get(room, [])
            if len(room_debits) > 1:
                out["more_than_one_debit_in_a_step"] += 1
            for debit in room_debits:
                out["debits"] += 1
                if int(debit["selection_id"]) == int(selection["id"]) and selection["served_to"] == ["fire", "sink"]:
                    out["debits_on_the_selection_the_fire_read"] += 1
                if debit["applied_kg"] > float(selection["available_kg"]) + max(0.0, float(before["due"].get(room, 0.0))):
                    out["debits_above_what_was_available"] += 1
        change = total_after - total_before
        building_gap = abs(change - (outside - consumed))
        oracle_gap = abs(change - expected)
        out["room_gap_kg"] = max(out["room_gap_kg"], worst_room)
        out["building_gap_kg"] = max(out["building_gap_kg"], building_gap)
        out["oracle_gap_kg"] = max(out["oracle_gap_kg"], oracle_gap)
        out["largest_transit_kg"] = max(out["largest_transit_kg"], abs(float(row["transit_kg"])))
        out["largest_number_of_entries"] = max(out["largest_number_of_entries"], int(row["transit_entries"]))
        out["consumed_kg"] += consumed
        out["clipped_kg"] += clipped
        out["steps_with_a_clip"] += clipped > 0.0
        out["outside_kg"] += outside
        out["infiltration_net_kg"] += infiltration
        salon = rooms["0"]
        by_step.append([f"{time_s:.6f}", repr(worst_room), repr(building_gap), repr(oracle_gap), repr(float(row["transit_kg"])),
                        int(row["transit_entries"]), repr(total_after - float(row["transit_kg"])), repr(consumed), repr(clipped),
                        repr(infiltration), repr(step_in), repr(step_out), repr(float(salon["power_kw"])),
                        repr(float(salon["heat_kj"]) / 1000.0), repr(float(salon["o2"])), repr(highest_x)])
    if folder is not None:
        with (folder / BY_STEP).open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["time_s", "residual_by_operations_kg", "residual_of_the_building_with_transit_kg",
                             "residual_against_the_closed_forms_kg", "transit_kg", "transit_entries", "inventories_kg",
                             "consumed_kg", "clipped_by_the_cap_kg", "infiltration_net_kg", "venting_in_kg", "venting_out_kg",
                             "salon_power_kw", "salon_heat_MJ", "salon_mole_fraction", "highest_mole_fraction_of_the_house"])
            writer.writerows(by_step)
    last = rows[out["steps"] - 1] if out["steps"] else rows[0]
    out["transit_at_the_end_kg"] = float(last["transit_kg"])
    out["transport_accumulators_of_the_house_kg"] = sum(float(state["transport_kg"]) for state in last["rooms"].values())
    out["transport_plus_transit_kg"] = out["transport_accumulators_of_the_house_kg"] + out["transit_at_the_end_kg"]
    out["closes_in_every_step"] = out["refused"] is None and max(
        out["room_gap_kg"], out["building_gap_kg"], out["oracle_gap_kg"]) <= GAP_KG
    first = rows[0]
    out["by_room"] = {room: {
        "volume_m3": float(state["volume_m3"]), "start_kg": float(first["before"]["inventory_kg"][room]),
        "end_kg": float(state["inventory_kg"]), "mole_fraction_at_the_end": float(state["o2"]),
        "debit_kg": float(state["debit_room_kg"]), "exterior_kg": float(state["exterior_kg"]),
        "transport_kg": float(state["transport_kg"]), "in_transit_to_it_at_the_end_kg": float(last.get("transit_to", {}).get(room, 0.0)),
        "residual_kg": float(state["inventory_kg"]) - (float(first["before"]["inventory_kg"][room]) - float(state["debit_room_kg"])
                                                       + float(state["exterior_kg"]) + float(state["transport_kg"])),
    } for room, state in last["rooms"].items()}
    out["house"] = {
        "start_kg": sum(item["start_kg"] for item in out["by_room"].values()),
        "end_kg": sum(item["end_kg"] for item in out["by_room"].values()),
        "consumed_kg": out["consumed_kg"], "outside_net_kg": out["outside_kg"], "transit_at_the_end_kg": out["transit_at_the_end_kg"],
    }
    out["house"]["residual_with_transit_kg"] = out["house"]["end_kg"] + out["house"]["transit_at_the_end_kg"] - (
        out["house"]["start_kg"] + out["house"]["outside_net_kg"] - out["house"]["consumed_kg"])
    venting["net_is_in_minus_out"] = abs(venting["net_kg"] - (venting["in_kg"] - venting["out_kg"])) <= GAP_KG
    for item in richer["rooms"].values():
        item["seconds"] = item["last_at_s"] - item["first_at_s"]
    richer["any_room_richer_than_the_outside"] = bool(richer["rooms"])
    richer["explained_by_the_transit_alone"] = bool(richer["rooms"]) and all(
        item["steps_in_which_the_effective_reading_is_richer_too"] == 0 for item in richer["rooms"].values())
    return {"budget": out, "venting": venting, "richer_than_the_outside": richer}


def unbacked_heat(fire: dict, budget: dict) -> dict:
    """What stage M3 has to close: heat whose oxygen the cap of the sink did not debit. Measured, nothing is adjusted."""
    demand, debit = fire["demand_of_the_heat_kg"], fire["debit_of_the_room_kg"]
    return {"demand_of_the_heat_kg": demand, "debit_kg": debit, "not_debited_kg": demand - debit,
            "clipped_by_the_cap_kg": budget["clipped_kg"], "steps_with_a_clip": budget["steps_with_a_clip"],
            "heat_with_no_debit_MJ": (demand - debit) / KG_PER_MJ,
            "what": "0.076 kg per MJ of the heat of the Salon against what its inventory was debited; the difference is what the "
                    "5 % cap clipped. Stage M3: the heat is not fitted to it here"}


# ---------------------------------------------------------------- historical route

def evaluate_off(rows: list[dict]) -> dict:
    """The historical route: its queue, its accumulators and, in a diagnostic copy, what each write discarded."""
    out = m2.evaluate_off(rows)
    gap = [sum(float(state["transport_kg"]) for state in row["rooms"].values()) + float(row["transit_kg"]) for row in rows]
    losing = [index for index in range(len(gap)) if gap[index] - (gap[index - 1] if index else 0.0) < -1.0e-9]
    out["steps_in_which_the_gap_grows"] = len(losing)
    out["gap_grows_from_s"] = float(rows[losing[0]]["time_s"]) if losing else None
    out["gap_grows_until_s"] = float(rows[losing[-1]]["time_s"]) if losing else None
    out["highest_room_number"] = max(float(state["o2"]) for row in rows for state in row["rooms"].values())
    counters = rows[-1].get("diagnostic_counters")
    if counters is None:
        return out
    lost = lambda row: sum(float(row["diagnostic_counters"].get(key, 0.0)) for key in (  # noqa: E731
        "discarded_at_the_ceiling_kg", "discarded_at_the_floor_kg", "dropped_below_the_threshold_kg"))
    explained = [gap[index] + lost(rows[index]) for index in range(len(rows))]
    by: dict = {}
    for key, value in counters["by_category_site_and_room"].items():
        category, site, room = key.split("|")
        item = by.setdefault(category, {"kg": 0.0, "by_site": {}, "by_room": {}})
        item["kg"] += value
        item["by_site"][site] = item["by_site"].get(site, 0.0) + value
        item["by_room"][room] = item["by_room"].get(room, 0.0) + value
    ceiling_steps = [index for index in range(len(rows)) if float(rows[index]["diagnostic_counters"].get("discarded_at_the_ceiling_kg", 0.0))
                     - (float(rows[index - 1]["diagnostic_counters"].get("discarded_at_the_ceiling_kg", 0.0)) if index else 0.0) > 1.0e-12]
    above = [row for row in rows if any(float(state["o2"]) > OUTSIDE + RICHER for state in row["rooms"].values())]
    out["diagnostic_copy"] = {
        "variant": counters["variant"],
        "calls": counters.get("applied_calls", 0), "asked_to_apply_kg": counters.get("intended_kg", 0.0),
        "applied_kg": counters.get("applied_kg", 0.0),
        "discarded_at_the_ceiling_kg": counters.get("discarded_at_the_ceiling_kg", 0.0),
        "discarded_at_the_ceiling_calls": counters.get("discarded_at_the_ceiling_calls", 0),
        "discarded_at_the_floor_kg": counters.get("discarded_at_the_floor_kg", 0.0),
        "dropped_below_the_threshold_kg": counters.get("dropped_below_the_threshold_kg", 0.0),
        "dropped_below_the_threshold_calls": counters.get("dropped_below_the_threshold_calls", 0),
        "rounding_of_the_writes_that_were_not_clipped_kg": counters.get("rounding_kg", 0.0),
        "left_above_the_ceiling_by_these_writes_kg": counters.get("left_above_the_ceiling_kg", 0.0),
        "by_category": by,
        "steps_with_a_discard_at_the_ceiling": len(ceiling_steps),
        "discards_at_the_ceiling_from_s": float(rows[ceiling_steps[0]]["time_s"]) if ceiling_steps else None,
        "discards_at_the_ceiling_until_s": float(rows[ceiling_steps[-1]]["time_s"]) if ceiling_steps else None,
        "gap_at_the_end_kg": gap[-1],
        "gap_plus_what_the_writes_discarded_at_the_end_kg": explained[-1],
        "largest_gap_plus_what_the_writes_discarded_kg": max(abs(value) for value in explained),
        "largest_gap_kg": max(abs(value) for value in gap),
        "steps_in_which_a_room_number_ends_above_the_outside": len(above),
        "highest_room_number_at_the_end_of_a_step": out["highest_room_number"],
    }
    return out


# ---------------------------------------------------------------- one run

def evaluate(folder: Path, identity: Path | None) -> dict:
    scenario = json.loads((folder / "scenario.json").read_text(encoding="utf-8"))
    rows = m2._rows(folder)
    kind = (folder / "kind.txt").read_text(encoding="utf-8").strip()
    mode_on = bool(rows[0]["owned"])
    result = {"folder": folder.relative_to(ROOT).as_posix() if folder.is_relative_to(ROOT) else folder.as_posix(),
              "kind": kind, "mode": "on" if mode_on else "off",
              "switch_in_the_scenario": scenario["engine_overrides"].get(SWITCH, False), "trace_rows": len(rows)}
    if mode_on:
        result.update(evaluate_on(rows, scenario, folder))
        usable = rows[:result["budget"]["steps"]] if result["budget"]["steps"] else rows
        result["whole"] = result["budget"]["refused"] is None and len(usable) == len(rows)
    else:
        result["budget"] = evaluate_off(rows)
        usable = rows
        if any("writers" in row for row in rows):
            result["writers"] = m2.evaluate_writers(rows)
    result["fire"] = m2._fire(usable, "0")
    result["last_time_s"] = float(usable[-1]["time_s"])
    if mode_on:
        result["heat_the_debit_does_not_back"] = unbacked_heat(result["fire"], result["budget"])
    if (folder / "sim_log.csv").is_file() and (not mode_on or result["budget"]["refused"] is None):
        result["contracts"] = m2.contracts(folder)
    if identity is not None and kind in ("off", "gap_passive"):
        twin = identity / folder.name
        result["identical_to_the_identity_run"] = {
            name: (twin / name).is_file() and m2._sha(folder / name) == m2._sha(twin / name) for name in m2.IDENTICAL_FILES}
    copy_file = folder / "diagnostic_copy.json"
    if copy_file.is_file():
        result["diagnostic_copy_of_the_oxygen_system"] = json.loads(copy_file.read_text(encoding="utf-8"))
    return result


def launch(case: str, kind: str) -> Path:
    scenario = copy.deepcopy(energy.cases()[case])
    scenario["engine_overrides"][batch.SWITCH] = False
    if kind == "on":
        scenario["engine_overrides"][SWITCH] = True
    baseline.TIMEOUT_S = 3600
    label = f"{LABEL}_{kind}"
    before = set((ROOT / "runs").glob(label + "_*"))
    arguments = [m2.TRACE_ARG, m2.WRITERS_ARG] if kind == "gap_control" else [m2.TRACE_ARG]
    error = ""
    diagnostic = DiagnosticCopy(kind) if kind in DIAGNOSTIC_EDITS else None
    try:
        if diagnostic is not None:
            diagnostic.__enter__()
        baseline.run(case_scenarios={case: scenario}, output_label=label, report_schema=f"{SCHEMA}_{kind}",
                     extra_runner_args=arguments)
    except RuntimeError as exc:
        # With the mode on a refused run does not reach its end: that is a result, kept below.
        error = str(exc)
    finally:
        if diagnostic is not None:
            diagnostic.__exit__()
    created = sorted(set((ROOT / "runs").glob(label + "_*")) - before)
    if len(created) != 1 or not (created[0] / case / TRACE).is_file():
        raise RuntimeError(f"{case} {kind}: no trace was written: {error}")
    folder = created[0] / case
    (folder / "launch_error.txt").write_text(error, encoding="utf-8")
    (folder / "kind.txt").write_text(kind, encoding="utf-8")
    if diagnostic is not None:
        (folder / "diagnostic_copy.diff").write_text(diagnostic.diff, encoding="utf-8")
        (folder / "diagnostic_copy.json").write_text(json.dumps(diagnostic.describe(), indent=1), encoding="utf-8")
    return folder


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity-run", type=Path, help="switch-off identity run of this tree")
    parser.add_argument("--existing", type=Path, action="append", default=[], help="case folder of a run already made")
    parser.add_argument("--case", action="append", choices=CASES, help="default: both")
    parser.add_argument("--kind", action="append", choices=KINDS, help="default: off and on")
    parser.add_argument("--latest", action="store_true", help="evaluate the latest run of every kind of every case instead of launching")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    folders = [path.resolve() for path in args.existing]
    if args.latest:
        for case in args.case or CASES:
            for kind in args.kind or KINDS:
                found = sorted((ROOT / "runs").glob(f"{LABEL}_{kind}_*/{case}/{TRACE}"))
                if found:
                    folders.append(found[-1].parent)
    if not folders:
        for case in args.case or CASES:
            for kind in args.kind or ("off", "on"):
                folders.append(launch(case, kind))
    identity = args.identity_run.resolve() if args.identity_run else None
    results: dict = {}
    for folder in folders:
        item = evaluate(folder, identity)
        error = folder / "launch_error.txt"
        item["launch_error"] = error.read_text(encoding="utf-8") if error.is_file() else ""
        results.setdefault(folder.name, {})[item["kind"]] = item
    record = {"schema": SCHEMA, "gap_accepted_kg": GAP_KG, "cases": results}
    args.out.write_text(json.dumps(record, indent=1, ensure_ascii=False), encoding="utf-8")
    for case, kinds in results.items():
        for kind, item in kinds.items():
            budget = item["budget"]
            print(case, kind, "steps", budget["steps"], "last s", item["last_time_s"], "transit at the end", budget["transit_at_the_end_kg"],
                  "transport+transit", budget["transport_plus_transit_kg"], "refused", budget.get("refused"),
                  "heat MJ", round(item["fire"]["heat_MJ"], 3))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
