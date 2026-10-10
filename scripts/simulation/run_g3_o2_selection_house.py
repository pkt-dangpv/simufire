#!/usr/bin/env python3
"""The house cases with the room oxygen inventory on and off, with the transit measured.

``o2_closed`` and ``o2_reopen_300`` are the diagnostic controls of
``run_g3_energy_controls.py``, unchanged: the product house, a sofa in the Salon, the
Salon door closed and, in the second, opened at 300 s. Each runs twice through the
monitored launcher, one Godot at a time:

- OFF: the historical route. Its outputs must equal, byte for byte, those of the
  identity run given with ``--identity-run``: the trace this script asks for is passive.
- ON: the same scenario with ``o2_room_inventory_enabled`` raised through the
  ``engine_overrides`` of the headless diagnostic runner. No product scenario, editor
  or catalogue names that switch.

Both write ``o2_inventory_trace.jsonl``, one row per step, with what the state shows:
the oxygen of every room, the queue in transit, the selections and the operations of
the owner. The budgets are evaluated here, in Python, from those rows.

A case the mode refuses is not hidden and not simplified: the route that refused it,
the step and what had happened until then are reported, and the case is not said to
be supported.

    python scripts/simulation/run_g3_o2_selection_house.py \
        --identity-run runs/g3_balance_identity_off_ledgeroff_<stamp> --out <file.json>

``--existing DIR`` (repeatable) evaluates runs already made instead of launching, and
``--latest`` the latest run of every kind of every case. ``--writers`` launches only the
historical route with the per-writer ledger of the engine on, to read which writers of
the room number each case needs.
"""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_energy_controls as energy  # noqa: E402
from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402

SCHEMA = "g3_o2_selection_house_v1"
CASES = ("o2_closed", "o2_reopen_300")
SWITCH = "o2_room_inventory_enabled"
TRACE = "o2_inventory_trace.jsonl"
TRACE_ARG = "--o2-inventory-trace"
# The passive per-writer ledger the engine already has: who wrote which oxygen number.
WRITERS_ARG = "--phase3-o2-attribution-diagnostics"
# Writers of the room number that stage M1 or M2 put behind the owner, by the name the ledger gives them.
WRITERS_BEHIND_THE_OWNER = {"oes_bulk_combustion_and_ach": "the sink and the infiltration, through the owner"}
# Sum of the changes of a fraction over a whole run below which a writer only rounds.
ROUNDING = 1.0e-9
IDENTICAL_FILES = ("sim_log.csv", "sim_log.txt", "fuel_source_ledger.jsonl", "co_inventory_trace.jsonl",
                   "fuel_object_state_snapshot.json", "events.json")
# Oracle constants, written here and not read from the engine.
M_O2, M_AIR, DENSITY = 2.0 * 15.999 / 1000.0, 28.9647 / 1000.0, 1.2
KG_PER_MJ, CAP, OUTSIDE = 0.076, 0.05, 0.209
GAP_KG = 1.0e-9
TOL_ABS_KG, TOL_REL = 1.0e-3, 1.0e-4


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _x(o2_kg: float, volume_m3: float) -> float:
    return o2_kg / ((volume_m3 * DENSITY / M_AIR) * M_O2)


def _parcel(mole_fraction: float, gas_kg: float) -> float:
    return mole_fraction * (gas_kg / M_AIR) * M_O2


def _infiltration_per_hour(scenario: dict) -> float:
    if "ach_infiltration" in scenario.get("engine_overrides", {}):
        return float(scenario["engine_overrides"]["ach_infiltration"])
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    return float(re.search(r"^@export var ach_infiltration: float = ([\d.]+)", engine, flags=re.M).group(1))


def _rows(folder: Path) -> list[dict]:
    with (folder / TRACE).open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def _fire(rows: list[dict], room: str) -> dict:
    """What the fire of a room did, read from the trace. Measured, not a criterion."""
    power = [float(row["rooms"][room]["power_kw"]) for row in rows]
    times = [float(row["time_s"]) for row in rows]
    burned = [value > 0.0 for value in power]
    went_out = [times[i] for i in range(1, len(power)) if burned[i - 1] and not burned[i]]
    came_back = [times[i] for i in range(1, len(power)) if not burned[i - 1] and burned[i] and any(burned[:i])]
    read = [float(row["rooms"][room]["oxygen_the_fire_read"]) for row in rows]
    last = rows[-1]["rooms"][room]
    return {
        "peak_kw": max(power), "time_of_the_peak_s": times[power.index(max(power))],
        "heat_MJ": float(last["heat_kj"]) / 1000.0, "fire_clock_s": float(last["fire_clock_s"]),
        "seconds_with_power": sum(burned) * (times[1] - times[0]), "power_at_the_end_kw": power[-1],
        "times_it_went_out": len(went_out), "went_out_at_s": went_out[:6],
        "times_it_came_back": len(came_back), "came_back_at_s": came_back[:6],
        "lowest_oxygen_the_fire_read": min(read), "fire_reads_at_the_end": last["fire_reads"],
        "lowest_room_number": min(float(row["rooms"][room]["o2"]) for row in rows),
        "room_number_at_the_end": float(last["o2"]), "lower_number_at_the_end": float(last["o2_lower"]),
        "upper_number_at_the_end": float(last["o2_upper"]),
        "debit_of_the_room_kg": float(last["debit_room_kg"]), "declared_as_consumed_kg": float(last["declared_kg"]),
        "demand_of_the_heat_kg": float(last["heat_kj"]) / 1000.0 * KG_PER_MJ,
    }


def evaluate_on(rows: list[dict], scenario: dict) -> dict:
    """The three budgets of every step, the selections and the transit, with the mode on."""
    per_hour = _infiltration_per_hour(scenario)
    out = {"steps": 0, "room_gap_kg": 0.0, "building_gap_kg": 0.0, "oracle_gap_kg": 0.0,
           "largest_transit_kg": 0.0, "largest_number_of_entries": 0, "consumed_kg": 0.0, "clipped_kg": 0.0,
           "outside_kg": 0.0, "delayed_exchanges": 0, "debits": 0, "debits_on_the_selection_the_fire_read": 0,
           "rooms_where_the_fire_read_its_selection": 0, "rooms_consulted": 0, "more_than_one_debit_in_a_step": 0,
           "debits_above_what_was_available": 0, "selections_missing": 0, "lowest_inventory_kg": float("inf"),
           "refused": None}
    previous_time = 0.0
    for row in rows:
        if out["refused"] is None and (row.get("failure") or row.get("state") == "rejected"):
            out["refused"] = {"time_s": row["time_s"], "step": row.get("step"), "failure": row.get("failure"),
                              "rejections": row.get("rejections", [])}
        if out["refused"] is not None:
            continue
        dt = float(row["time_s"]) - previous_time
        previous_time = float(row["time_s"])
        out["steps"] += 1
        before, rooms = row["before"], row["rooms"]
        by_room = {room: 0.0 for room in rooms}
        outside = consumed = 0.0
        debits: dict = {}
        for operation in row["operations"]:
            kind = operation["kind"]
            if kind == "consume":
                room = str(int(operation["room"]))
                by_room[room] -= operation["applied_kg"]
                consumed += operation["applied_kg"]
                out["clipped_kg"] += operation["clipped_kg"]
                debits.setdefault(room, []).append(operation)
            elif kind == "outside":
                by_room[str(int(operation["room"]))] += operation["in_kg"] - operation["out_kg"]
                outside += operation["in_kg"] - operation["out_kg"]
            elif kind == "interior":
                by_room[str(int(operation["donor"]))] += operation["to_donor_kg"] - operation["to_receiver_kg"]
                if operation["delayed"]:
                    out["delayed_exchanges"] += 1
                else:
                    by_room[str(int(operation["receiver"]))] += operation["to_receiver_kg"] - operation["to_donor_kg"]
            elif kind == "arrival":
                by_room[str(int(operation["room"]))] += operation["net_kg"]
        expected = 0.0
        total_before = float(before["transit_kg"])
        total_after = float(row["transit_kg"])
        for room, state in rooms.items():
            held_before = float(before["inventory_kg"][room])
            held_after = float(state["inventory_kg"])
            total_before += held_before
            total_after += held_after
            out["room_gap_kg"] = max(out["room_gap_kg"], abs(held_after - held_before - by_room[room]))
            out["lowest_inventory_kg"] = min(out["lowest_inventory_kg"], held_after)
            # Closed forms, on what the room holds when the oxygen step reaches it.
            held = held_before + float(before["due"].get(room, 0.0))
            demand = float(state["power_kw"]) / 1000.0 * KG_PER_MJ * dt
            gas = float(state["volume_m3"]) * (per_hour / 3600.0) * DENSITY * dt
            expected += _parcel(OUTSIDE - _x(held, float(state["volume_m3"])), gas) - min(demand, held * CAP)
            # The selection of the room: the one the fire read and the one the sink debited.
            selection = row["selections"].get(room)
            if selection is None:
                out["selections_missing"] += 1
                continue
            out["rooms_consulted"] += 1
            if float(state["oxygen_the_fire_read"]) == float(selection["mole_fraction"]) \
                    and state["fire_reads"] == selection["deposit"] == "room_inventory" \
                    and abs(float(selection["mole_fraction"]) - _x(held_before, float(state["volume_m3"]))) <= 1.0e-12:
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
        out["building_gap_kg"] = max(out["building_gap_kg"], abs(change - (outside - consumed)))
        out["oracle_gap_kg"] = max(out["oracle_gap_kg"], abs(change - expected))
        out["largest_transit_kg"] = max(out["largest_transit_kg"], abs(float(row["transit_kg"])))
        out["largest_number_of_entries"] = max(out["largest_number_of_entries"], int(row["transit_entries"]))
        out["consumed_kg"] += consumed
        out["outside_kg"] += outside
    last = rows[out["steps"] - 1] if out["steps"] else rows[0]
    out["transit_at_the_end_kg"] = float(last["transit_kg"])
    out["transport_accumulators_of_the_house_kg"] = sum(float(state["transport_kg"]) for state in last["rooms"].values())
    out["transport_plus_transit_kg"] = out["transport_accumulators_of_the_house_kg"] + out["transit_at_the_end_kg"]
    out["closes_in_every_step"] = out["refused"] is None and max(
        out["room_gap_kg"], out["building_gap_kg"], out["oracle_gap_kg"]) <= GAP_KG
    return out


def evaluate_off(rows: list[dict]) -> dict:
    """The historical route: its queue in transit, measured, against its accumulators."""
    last = rows[-1]
    transport = sum(float(state["transport_kg"]) for state in last["rooms"].values())
    return {
        "steps": len(rows),
        "transit_at_the_end_kg": float(last["transit_kg"]),
        "largest_transit_kg": max(abs(float(row["transit_kg"])) for row in rows),
        "largest_number_of_entries": max(int(row["transit_entries"]) for row in rows),
        "transport_accumulators_of_the_house_kg": transport,
        "transport_plus_transit_kg": transport + float(last["transit_kg"]),
        "largest_transport_plus_transit_kg": max(
            abs(sum(float(state["transport_kg"]) for state in row["rooms"].values()) + float(row["transit_kg"])) for row in rows),
    }


def evaluate_writers(rows: list[dict]) -> dict:
    """Who wrote the room number in a historical run, and from when. Read from the ledger of the engine."""
    first: dict = {}
    last: dict = {}
    for row in rows:
        for key, entry in row.get("writers", {}).items():
            last[key] = entry
            if entry["accepted_fraction_total"] and key not in first:
                first[key] = row["time_s"]
    room_number = {}
    for key, entry in sorted(last.items()):
        owner, zone = key.split("|")
        if zone != "bulk":
            continue
        room_number[owner] = {
            "applications": entry["applications"], "change_of_the_number_summed": entry["accepted_fraction_total"],
            "first_seen_changing_it_by_s": first.get(key),
            # A write of the same number can differ from it by a rounding: that is not a route.
            "status": WRITERS_BEHIND_THE_OWNER.get(owner, "writes nothing" if abs(entry["accepted_fraction_total"]) < ROUNDING
                                                    else "NOT integrated: refused with the mode on"),
        }
    return {"what": "writers of the room number seen by the passive ledger of the engine, historical route; sampled every 120 steps",
            "not_in_the_ledger": "the interior exchange of the oxygen system and its queue, which stage M1 put behind the owner",
            "room_number": room_number,
            "needed_and_not_integrated": sorted(owner for owner, item in room_number.items()
                                                if item["status"].startswith("NOT integrated"))}


def contracts(folder: Path) -> dict:
    """C1 and C2 in their corrected form (tests/test_oxygen_contract.py) on the trace of a run.

    With the mode on the room number is a mole fraction and the accumulators are real
    kilograms, so the inventory of C1 is taken from the oxygen trace, not from
    ``o2 x air_mass_kg``.
    """
    per: dict = {}
    with (folder / "sim_log.csv").open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            per.setdefault(row["room_name"], []).append(row)
    owned = {}
    trace = folder / TRACE
    if trace.is_file():
        rows = _rows(trace.parent)
        if rows and rows[0]["owned"]:
            first, last = rows[0], rows[-1]
            owned = {room: (float(first["before"]["inventory_kg"][room]), float(last["rooms"][room]["inventory_kg"]))
                     for room in last["rooms"]}
    out = {"c1": True, "c2": True, "c1_worst_residual_kg": 0.0, "c2_heat_minus_debit_kg": 0.0,
           "c2_primary_minus_debit_kg": 0.0, "inventory_from": "the oxygen trace, kg of O2" if owned else "room number x air mass"}
    for index, rows_of_room in enumerate(per.values()):
        first, last = rows_of_room[0], rows_of_room[-1]
        air = float(last["air_mass_kg"])
        room = str(int(float(last["room_id"]))) if "room_id" in last else str(index)
        initial, final = owned.get(room, (float(first["o2"]) * air, float(last["o2"]) * air))
        tolerance = max(TOL_ABS_KG, TOL_REL * initial)
        debit = float(last["o2_consumed_bulk_kg_total"])
        residual = final - (initial - debit + float(last["o2_net_transport_kg_total"])
                            + float(last["o2_exterior_net_kg_total"]) + float(last["o2_zone_sync_kg_total"]))
        if abs(residual) > abs(out["c1_worst_residual_kg"]):
            out["c1_worst_residual_kg"] = residual
        out["c1"] = out["c1"] and abs(residual) <= tolerance
        demand = float(last["hrr_kj_total"]) * KG_PER_MJ / 1000.0
        if demand <= 0.0:
            continue
        primary = float(last["o2_consumed_fire_kg_total"])
        out["c2_heat_minus_debit_kg"] = max(out["c2_heat_minus_debit_kg"], demand - debit, key=abs)
        out["c2_primary_minus_debit_kg"] = max(out["c2_primary_minus_debit_kg"], primary - debit, key=abs)
        out["c2"] = out["c2"] and abs(demand - debit) <= tolerance and abs(primary - debit) <= tolerance
    return out


def evaluate(folder: Path, identity: Path | None) -> dict:
    scenario = json.loads((folder / "scenario.json").read_text(encoding="utf-8"))
    rows = _rows(folder)
    mode_on = bool(rows[0]["owned"])
    result = {"folder": folder.relative_to(ROOT).as_posix() if folder.is_relative_to(ROOT) else folder.as_posix(),
              "mode": "on" if mode_on else "off", "switch_in_the_scenario": scenario["engine_overrides"].get(SWITCH, False),
              "trace_rows": len(rows)}
    result["budget"] = evaluate_on(rows, scenario) if mode_on else evaluate_off(rows)
    if any("writers" in row for row in rows):
        result["mode"] = "writers"
        result["writers"] = evaluate_writers(rows)
    usable = rows[:result["budget"]["steps"]] if mode_on and result["budget"]["steps"] else rows
    result["fire"] = _fire(usable, "0")
    if (folder / "sim_log.csv").is_file() and (not mode_on or result["budget"]["refused"] is None):
        result["contracts"] = contracts(folder)
    if not mode_on and identity is not None and "writers" not in result:
        twin = identity / folder.name
        result["identical_to_the_identity_run"] = {
            name: (twin / name).is_file() and _sha(folder / name) == _sha(twin / name) for name in IDENTICAL_FILES}
    return result


def launch(case: str, mode_on: bool, writers: bool = False) -> Path:
    scenario = copy.deepcopy(energy.cases()[case])
    scenario["engine_overrides"][batch.SWITCH] = False
    if mode_on:
        scenario["engine_overrides"][SWITCH] = True
    baseline.TIMEOUT_S = 3600
    label = f"g3_o2_selection_house_{'writers' if writers else 'on' if mode_on else 'off'}"
    before = set((ROOT / "runs").glob(label + "_*"))
    error = ""
    try:
        baseline.run(case_scenarios={case: scenario}, output_label=label,
                     report_schema=f"{SCHEMA}_{'on' if mode_on else 'off'}",
                     extra_runner_args=[TRACE_ARG, WRITERS_ARG] if writers else [TRACE_ARG])
    except RuntimeError as exc:
        # With the mode on a refused run does not reach its end: that is a result, kept below.
        error = str(exc)
    created = sorted(set((ROOT / "runs").glob(label + "_*")) - before)
    if len(created) != 1 or not (created[0] / case / TRACE).is_file():
        raise RuntimeError(f"{case} {'on' if mode_on else 'off'}: no trace was written: {error}")
    (created[0] / case / "launch_error.txt").write_text(error, encoding="utf-8")
    return created[0] / case


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity-run", type=Path, help="switch-off identity run of this tree")
    parser.add_argument("--existing", type=Path, action="append", default=[], help="case folder of a run already made")
    parser.add_argument("--case", action="append", choices=CASES, help="default: both")
    parser.add_argument("--latest", action="store_true",
                        help="evaluate the latest run of every kind (off, on, writers) of every case instead of launching")
    parser.add_argument("--writers", action="store_true",
                        help="only the historical route with the per-writer ledger of the engine on: which routes the case needs")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    folders = [path.resolve() for path in args.existing]
    if args.latest:
        for case in args.case or CASES:
            for kind in ("off", "on", "writers"):
                found = sorted((ROOT / "runs").glob(f"g3_o2_selection_house_{kind}_*/{case}/{TRACE}"))
                if found:
                    folders.append(found[-1].parent)
    if not folders:
        for case in args.case or CASES:
            if args.writers:
                folders.append(launch(case, False, writers=True))
                continue
            for mode_on in (False, True):
                folders.append(launch(case, mode_on))
    identity = args.identity_run.resolve() if args.identity_run else None
    results: dict = {}
    for folder in folders:
        item = evaluate(folder, identity)
        error = folder / "launch_error.txt"
        item["launch_error"] = error.read_text(encoding="utf-8") if error.is_file() else ""
        results.setdefault(folder.name, {})[item["mode"]] = item
    record = {"schema": SCHEMA, "gap_accepted_kg": GAP_KG, "cases": results}
    args.out.write_text(json.dumps(record, indent=1, ensure_ascii=False), encoding="utf-8")
    for case, modes in results.items():
        for mode, item in modes.items():
            budget = item["budget"]
            print(case, mode, "steps", budget["steps"], "transit at the end", budget["transit_at_the_end_kg"],
                  "transport+transit", budget["transport_plus_transit_kg"],
                  "refused", budget.get("refused"), "heat MJ", round(item["fire"]["heat_MJ"], 3))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
