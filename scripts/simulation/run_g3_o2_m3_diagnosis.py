#!/usr/bin/env python3
"""Diagnosis for the contract of stage M3 of the oxygen authority. Nothing is implemented.

Stage M3 will limit the combustion a room accepts to the oxygen its owner can debit.
This runner measures what the engine does today, with the room oxygen inventory on, so
that the contract is written from the real order of the engine and not from a budget
corrected afterwards. It changes no engine file. Every launch goes through the monitored
launcher, one Godot at a time.

1. CONTROLS. ``tests/fixtures/g3_o2_m3_diagnosis.gd`` steps the real engine in declared
   cases and writes one row per step; the rows are evaluated here, in Python: the heat
   the sink was asked to back against what it debited, where the difference is written,
   what the fire proposed against what it kept, the fuel and the products of the step
   against its heat, and what a rule of availability would have refused.
2. HOUSE. The two house cases already run whole with the mode on by stage M2-V are read
   again from their traces (their engine is the one of this tree: ``sim/`` has not
   changed), for what concerns M3: whether the room that burns is ever richer than the
   outside air, what it owes in transit, and whether a debit ever exceeded what its
   selection said was available.
3. STRESS. ``o2_stress_cap`` with the mode on, launched here. If a route the mode does
   not support refuses it, the case is kept and the cause recorded; it is not simplified.

    python scripts/simulation/run_g3_o2_m3_diagnosis.py --rows <folder outside the repository>

``--from-rows`` evaluates rows already written and launches nothing; ``--skip-stress``
leaves the stress launch out (the record then says it was not run).
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402
from scripts.simulation import run_g3_o2_selection_house as m2  # noqa: E402
from scripts.simulation import run_g3_optd_controls as optd  # noqa: E402

SCHEMA = "g3_o2_m3_contract_diagnosis_v1"
RECORD = "docs/validation/G3_O2_M3_CONTRACT_DIAGNOSIS_2026-10-11.json"
FIXTURE = "tests/fixtures/g3_o2_m3_diagnosis.gd"
PREFIX = "G3_O2_M3_DIAGNOSIS"
ROWS_ENV = "G3_O2_M3_DIAGNOSIS_OUT"
HOUSE_CASES = ("o2_closed", "o2_reopen_300")
STRESS = "o2_stress_cap"
STRESS_LABEL = "g3_o2_m3_stress_on"
# The engine whose behaviour is measured: nothing under sim/ may differ from this commit.
ENGINE_OF = "cefae4ec"
ENGINE_FILES = ("sim/fire/CombustionSystem.gd", "sim/core/OxygenExchangeSystem.gd", "sim/core/RoomOxygenInventory.gd",
                "sim/core/SimulationEngine.gd", "sim/core/GasExchangeSystem.gd", "sim/core/ThermalSystem.gd",
                "sim/building/RoomModel.gd", "sim/fire/FireModel.gd")
# The contract of the engine today, not a calorimetric measurement.
KG_PER_MJ = 0.076
CAP = 0.05
OUTSIDE = 0.209
# The engine's default limit below which the selected oxygen cannot hold a flame.
FLAME_LIMIT = 0.122
M_O2, M_AIR, DENSITY = 2.0 * 15.999 / 1000.0, 28.9647 / 1000.0, 1.2


def _git(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def engine_untouched() -> dict:
    """Every engine file measured here against the commit that published it."""
    return {relative: (ROOT / relative).read_bytes().replace(b"\r\n", b"\n")
            == _git("show", f"{ENGINE_OF}:{relative}").replace(b"\r\n", b"\n") for relative in ENGINE_FILES}


# ---------------------------------------------------------------- controls of the fixture

def launch_fixture(rows: Path) -> dict:
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    rows.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    environment[ROWS_ENV] = str(rows)
    run = godot_monitored_launch.run([godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
                                     timeout_s=2400, environment=environment)
    if not run.launched or run.faults or run.preexisting:
        raise RuntimeError(f"not a healthy run: {run.faults or run.preexisting}")
    text = (run.stdout or "") + (run.stderr or "")
    line = next((line for line in (run.stdout or "").splitlines() if line.startswith(PREFIX + " {")), None)
    if line is None:
        raise RuntimeError("the fixture did not reach its end:\n" + text[-3000:])
    payload = json.loads(line.split(" ", 1)[1])
    payload["returncode"] = run.returncode
    payload["script_errors"] = text.count("SCRIPT ERROR") + text.count("Parse Error")
    (rows / "summaries.json").write_text(json.dumps(payload, indent=1), encoding="utf-8")
    return payload


def _rows(rows: Path, case: str) -> list[dict]:
    with (rows / (case.replace(" ", "_") + ".jsonl")).open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def _spread(values: list[float]) -> dict:
    if not values:
        return {"steps": 0}
    return {"steps": len(values), "lowest": min(values), "median": statistics.median(values), "highest": max(values)}


def evaluate_case(rows: list[dict], summary: dict) -> dict:
    """What the engine did in one control, and what a rule of availability would have refused. Nothing is corrected."""
    out: dict = {"what": summary["setup"]["what"], "steps": len(rows), "time_s": summary["time_s"],
                 "failure": summary["failure"], "rejections": summary["rejections"], "injected": summary["injected"],
                 "flashover": summary["flashover"]}
    heat_sink = heat_accounted = backed = clipped = fuel = co = smoke = co2 = 0.0
    tail = over_target_steps = 0.0
    above_available_kg = above_available_steps = 0
    refused_start = refused_with_arrivals = refused_cap_start = 0.0
    fire_sees_flame_but_no_oxygen = 0
    first_clip = first_above = None
    ratios = {"fuel_MJ_per_MJ_of_heat": [], "co_g_per_MJ_of_heat": [], "smoke_g_per_MJ_of_heat": [], "co2_kg_per_MJ_of_heat": []}
    proposal = {"power_above_its_target": [], "target_above_its_power": []}
    lowest_m = float("inf")
    highest_x = 0.0
    spent_while_owing = 0.0
    largest_owed = largest_pending = 0.0
    heat_after_refusal_would_start = None
    flashover_step = None
    largest_share = 0.0
    fire_read_last = None
    heat_above_fuel = fuel_above_heat = 0.0
    for row in rows:
        dt = float(row["dt"])
        requested, applied, clip = float(row["requested_kg"]), float(row["applied_kg"]), float(row["clipped_kg"])
        step_heat = requested / KG_PER_MJ
        heat_sink += step_heat
        heat_accounted += float(row["heat_accounted_MJ"])
        backed += applied / KG_PER_MJ
        clipped += clip
        fuel += float(row["fuel_MJ"])
        co += float(row["co_kg"])
        smoke += float(row["smoke_kg"])
        co2 += float(row["co2_kg"])
        lowest_m = min(lowest_m, float(row["m_kg"]))
        highest_x = max(highest_x, float(row["x"]))
        largest_owed = max(largest_owed, float(row["owed_before_kg"]))
        largest_pending = max(largest_pending, float(row["pending_in_before_kg"]))
        if clip > 0.0 and first_clip is None:
            first_clip = row["t"]
        # The fire: what it kept against what it proposed in this step.
        power, target = float(row["power_kw"]), float(row["target_kw"])
        if power > target + 1.0e-9:
            tail += (power - target) * dt / 1000.0
            over_target_steps += 1
            proposal["power_above_its_target"].append(power - target)
        elif target > power + 1.0e-9:
            proposal["target_above_its_power"].append(target - power)
        if row.get("flashover_in_this_step"):
            flashover_step = {"t": row["t"], "heat_the_combustion_system_accounted_MJ": float(row["heat_accounted_MJ"]),
                              "heat_the_sink_was_asked_to_back_MJ": step_heat, "power_at_the_end_kw": power}
        # A rule of availability, evaluated on the selection of the step. Read only: what it WOULD refuse.
        if row["selection_available_kg"] is not None and requested > 0.0:
            available = float(row["selection_available_kg"])
            largest_share = max(largest_share, requested / available if available > 0.0 else float("inf"))
            fire_read_last = float(row["selection_x"])
            if applied > available + 1.0e-12:
                above_available_kg += applied - available
                above_available_steps += 1
                first_above = row["t"] if first_above is None else first_above
            refused_start += max(0.0, requested - available)
            refused_with_arrivals += max(0.0, requested - available - max(0.0, float(row["arrived_kg"])))
            refused_cap_start += max(0.0, requested - min(available, CAP * float(row["selection_m_kg"])))
            if max(0.0, requested - available) > 0.0 and heat_after_refusal_would_start is None:
                heat_after_refusal_would_start = row["t"]
            if float(row["selection_x"]) > FLAME_LIMIT and available < requested:
                fire_sees_flame_but_no_oxygen += 1
            if float(row["owed_before_kg"]) > 0.0:
                spent_while_owing += applied
        heat_above_fuel += max(0.0, step_heat - float(row["fuel_MJ"]))
        fuel_above_heat += max(0.0, float(row["fuel_MJ"]) - step_heat)
        # Ratios only where the step released at least 1 kJ: below that they are a division by nothing.
        if step_heat > 1.0e-3:
            ratios["fuel_MJ_per_MJ_of_heat"].append(float(row["fuel_MJ"]) / step_heat)
            ratios["co_g_per_MJ_of_heat"].append(1000.0 * float(row["co_kg"]) / step_heat)
            ratios["smoke_g_per_MJ_of_heat"].append(1000.0 * float(row["smoke_kg"]) / step_heat)
            ratios["co2_kg_per_MJ_of_heat"].append(float(row["co2_kg"]) / step_heat)
    last = rows[-1] if rows else {}
    out["heat"] = {
        "the_sink_was_asked_to_back_MJ": heat_sink, "the_combustion_system_accounted_MJ": heat_accounted,
        "backed_by_the_debit_MJ": backed, "not_backed_MJ": clipped / KG_PER_MJ,
        "asked_minus_accounted_MJ": heat_sink - heat_accounted,
    }
    out["oxygen"] = {
        "requested_kg": heat_sink * KG_PER_MJ, "applied_kg": backed * KG_PER_MJ, "clipped_by_the_cap_kg": clipped,
        "first_clip_at_s": first_clip, "steps_with_a_clip": sum(1 for row in rows if float(row["clipped_kg"]) > 0.0),
        "lowest_inventory_kg": lowest_m if rows else None, "inventory_at_the_end_kg": last.get("m_kg"),
        "highest_mole_fraction_of_the_room": highest_x,
        "lowest_mole_fraction_of_the_room": min((float(row["x"]) for row in rows), default=None),
        "largest_obligation_kg": largest_owed,
        "largest_pending_arrival_kg": largest_pending,
        "more_than_one_debit_in_a_step": sum(1 for row in rows if int(row["debits"]) > 1),
    }
    out["largest_share_of_the_available_asked_in_a_step"] = largest_share
    out["mole_fraction_the_fire_read_in_its_last_step_with_a_debit"] = fire_read_last
    out["filter"] = {
        "steps_with_power_above_the_target": int(over_target_steps), "heat_above_the_target_MJ": tail,
        "power_above_its_target_kw": _spread(proposal["power_above_its_target"]),
        "target_above_its_power_kw": _spread(proposal["target_above_its_power"]),
    }
    out["availability_at_the_opening_of_the_step"] = {
        "what": "available = what the room holds when the step opens less every negative entry in transit to it; read from the "
                "selection of stage M2. Nothing of this acted on the run",
        "debited_above_it_kg": above_available_kg, "steps_debited_above_it": above_available_steps, "first_at_s": first_above,
        "debited_while_the_room_owed_kg": spent_while_owing,
        "a_rule_without_cap_would_refuse_kg": refused_start, "would_refuse_MJ": refused_start / KG_PER_MJ,
        "would_first_refuse_at_s": heat_after_refusal_would_start,
        "counting_the_arrivals_of_the_step_it_would_refuse_kg": refused_with_arrivals,
        "what_leaving_those_arrivals_out_costs_kg": refused_start - refused_with_arrivals,
        "a_rule_with_the_5_percent_cap_would_refuse_kg": refused_cap_start,
        "steps_in_which_the_fire_reads_enough_oxygen_for_a_flame_and_the_rule_would_refuse": fire_sees_flame_but_no_oxygen,
    }
    out["fuel_and_products"] = {
        "fuel_debited_MJ": fuel, "fuel_minus_heat_MJ": fuel - heat_sink, "co_kg": co, "co2_kg": co2, "smoke_kg": smoke,
        "heat_above_the_fuel_of_its_step_MJ": heat_above_fuel, "fuel_above_the_heat_of_its_step_MJ": fuel_above_heat,
        "per_step": {name: _spread(values) for name, values in ratios.items()},
    }
    if flashover_step is not None:
        out["flashover_step"] = flashover_step
    return out


def against_dt(cases: dict, prefix: str) -> dict:
    """The same fire at four time steps: what the step, and the 5 % per step, do to it."""
    table = {}
    for name, item in cases.items():
        if not name.startswith(prefix):
            continue
        table[name.removeprefix(prefix)] = {
            "steps": item["steps"], "heat_MJ": item["heat"]["the_sink_was_asked_to_back_MJ"],
            "backed_MJ": item["heat"]["backed_by_the_debit_MJ"], "not_backed_MJ": item["heat"]["not_backed_MJ"],
            "clipped_kg": item["oxygen"]["clipped_by_the_cap_kg"], "steps_with_a_clip": item["oxygen"]["steps_with_a_clip"],
            "first_clip_at_s": item["oxygen"]["first_clip_at_s"], "fuel_MJ": item["fuel_and_products"]["fuel_debited_MJ"],
            "lowest_inventory_kg": item["oxygen"]["lowest_inventory_kg"],
        }
    return table


# ---------------------------------------------------------------- the house

def _n_o2(volume_m3: float) -> float:
    return (volume_m3 * DENSITY / M_AIR) * M_O2


def evaluate_house(folder: Path, room: str = "0") -> dict:
    """What concerns M3 in a house trace with the mode on: the room that burns, step by step."""
    rows = m2._rows(folder)
    out = {"folder": folder.relative_to(ROOT).as_posix() if folder.is_relative_to(ROOT) else folder.as_posix(),
           "trace_rows": len(rows), "steps": 0, "refused": None}
    requested = applied = clipped = 0.0
    above_kg = above_steps = richer_steps = owing_steps = pending_steps = 0
    largest_owed = largest_pending = largest_share = spent_while_owing = 0.0
    refused_start = 0.0
    lowest_available = float("inf")
    previous = 0.0
    for row in rows:
        if out["refused"] is None and (row.get("failure") or row.get("state") == "rejected"):
            out["refused"] = {"time_s": row["time_s"], "step": row.get("step"), "failure": row.get("failure"),
                              "rejections": row.get("rejections", [])}
        if out["refused"] is not None:
            continue
        out["steps"] += 1
        out["last_time_s"] = float(row["time_s"])
        state = row["rooms"][room]
        selection = row["selections"][room]
        available = float(selection["available_kg"])
        owed = float(row["before"]["owed"].get(room, 0.0))
        due = float(row["before"]["due"].get(room, 0.0))
        largest_owed = max(largest_owed, owed)
        owing_steps += owed > 0.0
        if due > 0.0:
            pending_steps += 1
            largest_pending = max(largest_pending, due)
        if float(state["inventory_kg"]) / _n_o2(float(state["volume_m3"])) > OUTSIDE + 1.0e-12:
            richer_steps += 1
        for operation in row["operations"]:
            if operation["kind"] != "consume" or str(int(operation["room"])) != room:
                continue
            requested += operation["requested_kg"]
            applied += operation["applied_kg"]
            clipped += operation["clipped_kg"]
            lowest_available = min(lowest_available, available)
            largest_share = max(largest_share, operation["requested_kg"] / available if available > 0.0 else float("inf"))
            refused_start += max(0.0, operation["requested_kg"] - available)
            if operation["applied_kg"] > available + 1.0e-12:
                above_kg += operation["applied_kg"] - available
                above_steps += 1
            if owed > 0.0:
                spent_while_owing += operation["applied_kg"]
        previous = float(row["time_s"])
    del previous
    out["whole"] = out["refused"] is None and out["steps"] == len(rows)
    out["room_that_burns"] = {
        "requested_kg": requested, "applied_kg": applied, "clipped_by_the_cap_kg": clipped,
        "heat_not_backed_MJ": clipped / KG_PER_MJ,
        "steps_in_which_it_is_richer_than_the_outside": int(richer_steps),
        "steps_in_which_it_owes_in_transit": int(owing_steps), "largest_obligation_kg": largest_owed,
        "steps_with_a_positive_arrival_due": int(pending_steps), "largest_arrival_due_kg": largest_pending,
        "debited_while_it_owed_kg": spent_while_owing,
        "lowest_available_when_it_debits_kg": lowest_available if requested else None,
        "largest_share_of_the_available_asked_in_a_step": largest_share,
        "debited_above_the_available_kg": above_kg, "steps_debited_above_the_available": int(above_steps),
        "a_rule_without_cap_would_refuse_kg": refused_start,
    }
    return out


def launch_stress() -> Path:
    """`o2_stress_cap`, unchanged, with the mode raised through the engine overrides of the diagnostic runner."""
    scenario = copy.deepcopy(optd.cases()[STRESS])
    scenario["engine_overrides"][batch.SWITCH] = False
    scenario["engine_overrides"][m2.SWITCH] = True
    baseline.TIMEOUT_S = 3600
    before = set((ROOT / "runs").glob(STRESS_LABEL + "_*"))
    error = ""
    try:
        baseline.run(case_scenarios={STRESS: scenario}, output_label=STRESS_LABEL, report_schema=SCHEMA + "_stress",
                     extra_runner_args=[m2.TRACE_ARG])
    except RuntimeError as exc:
        # With the mode on a refused run does not reach its end: that is a result, kept below.
        error = str(exc)
    created = sorted(set((ROOT / "runs").glob(STRESS_LABEL + "_*")) - before)
    if len(created) != 1 or not (created[0] / STRESS / m2.TRACE).is_file():
        raise RuntimeError(f"{STRESS}: no trace was written: {error}")
    (created[0] / STRESS / "launch_error.txt").write_text(error, encoding="utf-8")
    return created[0] / STRESS


def _latest(pattern: str) -> Path | None:
    found = sorted((ROOT / "runs").glob(pattern))
    return found[-1].parent if found else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=Path, required=True, help="folder for the rows of the fixture, outside the repository")
    parser.add_argument("--from-rows", action="store_true", help="evaluate rows already written; launch nothing")
    parser.add_argument("--skip-stress", action="store_true", help="do not launch o2_stress_cap")
    args = parser.parse_args()
    untouched = engine_untouched()
    if not all(untouched.values()):
        raise RuntimeError(f"an engine file differs from {ENGINE_OF}: this diagnosis is of that engine: {untouched}")
    rows = args.rows.resolve()
    payload = json.loads((rows / "summaries.json").read_text(encoding="utf-8")) if args.from_rows else launch_fixture(rows)
    cases = {name: evaluate_case(_rows(rows, name), summary) for name, summary in payload["cases"].items()}
    record = {
        "schema": SCHEMA, "head": _git("rev-parse", "--short=8", "HEAD").decode().strip(),
        "scope": "diagnosis for the contract of stage M3 of the oxygen authority: what the engine does today, with the room "
                 "oxygen inventory on, when the heat it accepts is and is not backed by the oxygen its owner can debit. "
                 "Nothing is implemented, nothing under sim/ is changed and no trace is corrected",
        "engine": {"commit": ENGINE_OF, "files_equal_to_that_commit": untouched,
                   "sha256": {relative: hashlib.sha256((ROOT / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
                              for relative in ENGINE_FILES}},
        "fixture": {"path": FIXTURE, "sha256": hashlib.sha256((ROOT / FIXTURE).read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
                    "judges": False, "returncode": payload["returncode"], "script_errors": payload["script_errors"]},
        "constants": {"oxygen_kg_per_MJ": KG_PER_MJ, "cap_fraction_per_step": CAP, "flame_limit_mole_fraction": FLAME_LIMIT,
                      "what_0.076_is": "the coefficient the engine uses today, taken as its contract; not a calorimetric measurement"},
        "controls": cases, "two_rooms_against_the_time_step": against_dt(cases, "stress dt "),
        "small_room_against_the_time_step": against_dt(cases, "small room dt "),
    }
    house = {}
    for case in HOUSE_CASES:
        folder = _latest(f"g3_o2_venting_house_on_*/{case}/{m2.TRACE}")
        house[case] = evaluate_house(folder) if folder else {"not_found": True}
        if folder:
            house[case]["evidence"] = "run of stage M2-V, read again: the engine files are those of this tree"
    record["house"] = house
    if args.skip_stress:
        stress_folder = _latest(f"{STRESS_LABEL}_*/{STRESS}/{m2.TRACE}")
    else:
        stress_folder = launch_stress()
    if stress_folder is None:
        record["stress"] = {"run": False, "why": "not launched in this invocation and no earlier run found"}
    else:
        stress = evaluate_house(stress_folder)
        stress["run"] = True
        stress["launch_error"] = (stress_folder / "launch_error.txt").read_text(encoding="utf-8") \
            if (stress_folder / "launch_error.txt").is_file() else ""
        scenario = json.loads((stress_folder / "scenario.json").read_text(encoding="utf-8"))
        stress["switch_in_the_scenario"] = scenario["engine_overrides"].get(m2.SWITCH, False)
        stress["step_s"] = scenario.get("run_step_s")
        stress["fire"] = m2._fire(m2._rows(stress_folder)[:max(1, stress["steps"])], "0")
        record["stress"] = stress
    saved = ROOT / RECORD
    saved.write_bytes((json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    for name, item in cases.items():
        print(f"{name}: steps {item['steps']} heat {item['heat']['the_sink_was_asked_to_back_MJ']:.2f} MJ not backed "
              f"{item['heat']['not_backed_MJ']:.3f} MJ failure {item['failure'] or 'none'}")
    for case, item in house.items():
        print(case, "whole", item.get("whole"), "clipped", item.get("room_that_burns", {}).get("clipped_by_the_cap_kg"))
    print(STRESS, json.dumps({key: record["stress"].get(key) for key in ("run", "whole", "steps", "refused")}))
    print(saved.relative_to(ROOT).as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
