#!/usr/bin/env python3
"""Record of stage M2 of the oxygen authority: one selection per room and step.

Each launch goes through the monitored launcher, one Godot at a time:

1. BEFORE M2. The tracked engine files this stage changes are put back, byte for byte,
   to the commit before it; the acceptance fixture of M2 runs; the files are restored
   and verified. The fixture must reach its end with failed checks and no script error:
   on that engine the fire reads a layer number while the sink debits the room, the
   consumption is declared twice and a sealed room that burns is refused.
2. ACCEPTANCE. The fixture of M2 on the working tree, whole. It must pass.
3. STAGE M1 AGAIN. The acceptance fixture of M1 on the working tree. It must pass.
4. HISTORICAL ROUTE. The diagnosis published on 2026-10-09 measured again with the
   switch off and compared figure by figure with its published record.
5. What was run elsewhere is read: the two mutation suites and the house cases.

    python scripts/simulation/run_g3_o2_selection.py \
        --selection-mutations runs/g3_o2_selection_mutations_<stamp>/results.json \
        --inventory-mutations runs/g3_o2_room_inventory_mutations_<stamp>/results.json \
        --house <file written by run_g3_o2_selection_house.py>

``--plan-only`` prints what would run and launches nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402

SCHEMA = "g3_o2_selection_m2_record_v1"
RECORD = "docs/validation/G3_O2_SELECTION_M2_2026-10-10.json"
FIXTURE = "tests/fixtures/g3_o2_selection.gd"
PREFIX = "G3_O2_SELECTION"
INVENTORY_FIXTURE = "tests/fixtures/g3_o2_room_inventory.gd"
INVENTORY_PREFIX = "G3_O2_ROOM_INVENTORY"
# The commit before this stage: stage M1, with its room inventory and no selection.
BEFORE_M2 = "718061f7"
# Tracked engine files this stage changes.
CHANGED_BY_M2 = ("sim/fire/CombustionSystem.gd", "sim/core/OxygenExchangeSystem.gd",
                 "sim/core/RoomOxygenInventory.gd", "sim/core/SimulationEngine.gd")
SOURCES = CHANGED_BY_M2 + ("sim/building/RoomModel.gd", "sim/core/GasExchangeSystem.gd", "tools/run_scenario_headless.gd",
                           FIXTURE, INVENTORY_FIXTURE)
# Left as they were, by content.
UNTOUCHED = ("sim/fire/PrescribedObjectHrrSource.gd", "sim/fire/PrescribedThermalSourceCoupling.gd",
             "sim/building/RoomModel.gd", "sim/core/GasExchangeSystem.gd")
DIAGNOSIS_RUNNER = "scripts/simulation/run_g3_o2_authority_diagnosis.py"
DIAGNOSIS_RECORD = "docs/validation/G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json"
M1_RECORD = "docs/validation/G3_O2_ROOM_INVENTORY_M1_2026-10-10.json"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def _git(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def _launch(fixture: str, prefix: str) -> dict:
    """One launch of a judging fixture; what it printed and how it ended."""
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    run = godot_monitored_launch.run([godot, "--headless", "--path", ROOT, "--script", ROOT / fixture],
                                     timeout_s=1200, environment=os.environ.copy())
    if not run.launched or run.faults or run.preexisting:
        raise RuntimeError(f"not a healthy run: {run.faults or run.preexisting}")
    text = (run.stdout or "") + (run.stderr or "")
    line = next((line for line in (run.stdout or "").splitlines() if line.startswith(prefix + " {")), None)
    if line is None:
        raise RuntimeError("the fixture did not reach its end:\n" + text[-3000:])
    payload = json.loads(line.split(" ", 1)[1])
    return {
        "fixture": fixture, "returncode": run.returncode, "pass_marker": prefix + "_PASS" in (run.stdout or ""),
        "script_errors": text.count("SCRIPT ERROR") + text.count("Parse Error"),
        "checks": payload["checks"], "failure_count": payload["failure_count"],
        "failures_by_group": payload["failures_by_group"], "groups": payload["groups"],
        "first_failures": payload["failures"][:30], "observations": payload["observations"],
    }


def before_m2() -> dict:
    """The fixture of M2 on the engine of the commit before this stage. Restores and verifies."""
    current = {relative: (ROOT / relative).read_bytes() for relative in CHANGED_BY_M2}
    earlier = {relative: _git("show", f"{BEFORE_M2}:{relative}") for relative in CHANGED_BY_M2}
    try:
        for relative, data in earlier.items():
            (ROOT / relative).write_bytes(data)
        result = _launch(FIXTURE, PREFIX)
    finally:
        for relative, data in current.items():
            (ROOT / relative).write_bytes(data)
            if (ROOT / relative).read_bytes() != data:
                raise RuntimeError(f"{relative} not restored byte for byte")
    observations = result.pop("observations")
    result["engine"] = f"tracked engine files of {BEFORE_M2}, byte for byte"
    result["engine_sha256"] = {relative: _sha(data) for relative, data in earlier.items()}
    result["restored_byte_for_byte"] = True
    # What that engine did in the case the stage is about, as the fixture measured it.
    fire = observations.get("real_fire", {})
    result["the_defect_measured"] = {
        "steps": fire.get("steps"), "steps_in_which_the_fire_read_the_inventory": fire.get("fire_reads_the_inventory"),
        "steps_in_which_the_lower_number_was_another_number": fire.get("lower_number_apart"),
        "of_those_the_fire_read_the_lower_number_in": fire.get("fire_reads_the_lower_number"),
        "debit_of_the_inventory_kg": fire.get("consumed_kg"),
    }
    result["effect_measured"] = {key: value for key, value in observations.items() if key.startswith("effect ")}
    return result


def historical_route() -> dict:
    """The published diagnosis measured again on this tree, switch off, against its record."""
    spec = importlib.util.spec_from_file_location("diagnosis", ROOT / DIAGNOSIS_RUNNER)
    diagnosis = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diagnosis)
    published = json.loads((ROOT / DIAGNOSIS_RECORD).read_text(encoding="utf-8"))["hypotheses"]
    measured = diagnosis.evaluate(diagnosis.run_fixture()["cases"])
    compared, differing = [], {}
    for name, verdict in measured.items():
        if name not in published or not verdict.get("exercised", True):
            continue
        compared.append(name)
        for key in ("holds", "claims", "evidence"):
            if json.dumps(verdict.get(key), sort_keys=True) != json.dumps(published[name].get(key), sort_keys=True):
                differing.setdefault(name, []).append(key)
    return {"what": "the diagnosis of 2026-10-09 measured again on this tree with the switch off",
            "published_record": DIAGNOSIS_RECORD, "published_record_rewritten": False,
            "hypotheses_compared": sorted(compared), "identical_figure_by_figure": not differing, "differing": differing}


def mutations(results: Path) -> dict:
    summary = json.loads(results.read_text(encoding="utf-8"))
    keep = ("name", "verdict", "reason", "file", "defect", "expected_in", "declared_with_the_plan", "seen_where_expected",
            "checks", "failed_checks", "groups_with_failures", "mutant_sha256")
    return {
        "evidence": results.parent.relative_to(ROOT).as_posix() if results.is_relative_to(ROOT) else results.parent.as_posix(),
        **{key: summary[key] for key in ("control", "control_checks", "declared", "executed", "killed", "killed_where_expected",
                                         "survivors", "invalid", "killed_elsewhere", "originals_intact",
                                         "launches_refused_by_the_memory_gate_and_repeated")},
        "results": [{key: item.get(key) for key in keep} for item in summary["results"]],
    }


def against_stage_m1(acceptance: dict) -> dict:
    """The same 120 s of the two-room fire: historical route, stage M1 and stage M2."""
    m1 = json.loads((ROOT / M1_RECORD).read_text(encoding="utf-8"))["acceptance"]["observations"]["real_fire_dt_0.25"]
    m2 = acceptance["observations"]["real_fire"]
    diagnosis = json.loads((ROOT / DIAGNOSIS_RECORD).read_text(encoding="utf-8"))["hypotheses"]
    historical = diagnosis["H12_fire_and_sink_use_different_deposits"]["evidence"]
    return {
        "what": "two rooms closed to the outside, door open, a 700 kW sofa, 120 s at 0.25 s",
        "historical_route": {"from": DIAGNOSIS_RECORD, "evidence": {key: value for key, value in historical.items()
                                                                    if isinstance(value, (int, float, str, bool))}},
        "stage_m1": {"from": M1_RECORD, "heat_MJ": m1["heat_MJ"], "debit_kg": m1["consumed_kg"],
                     "largest_transit_kg": m1["largest_transit_kg"]},
        "stage_m2": {"heat_MJ": m2["heat_MJ"], "debit_kg": m2["consumed_kg"], "largest_transit_kg": m2["largest_transit_kg"],
                     "peak_kw": m2["peak_kw"], "lowest_oxygen_the_fire_read": m2["lowest_oxygen_the_fire_read"]},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--selection-mutations", type=Path, help="results.json of run_g3_o2_selection_mutations.py")
    parser.add_argument("--inventory-mutations", type=Path, help="results.json of run_g3_o2_room_inventory_mutations.py")
    parser.add_argument("--house", type=Path, help="file written by run_g3_o2_selection_house.py")
    args = parser.parse_args()
    if args.plan_only:
        print(json.dumps({"executed": False, "before_m2": BEFORE_M2, "restored_from_git": list(CHANGED_BY_M2),
                          "fixtures": [FIXTURE, INVENTORY_FIXTURE], "record": RECORD}, indent=1))
        return 0
    combustion_before = _git("show", f"{BEFORE_M2}:sim/fire/CombustionSystem.gd")
    record = {
        "schema": SCHEMA, "head": _git("rev-parse", "--short=8", "HEAD").decode().strip(),
        "scope": "stage M2 of the oxygen authority: one oxygen selection per room and step, shared by the fire and the "
                 "sink, on the room inventory of stage M1, behind the same switch, off by default; conservation, "
                 "ownership and the measured effect on the fire; no heat fitted to the oxygen (M3), no zonal split (M4), "
                 "no CO, FED or SVV",
        "sources_sha256": {relative: _sha((ROOT / relative).read_bytes()) for relative in SOURCES},
        "combustion_system": {
            "why": "frozen by hash through stage M1; lifted for stage M2 only, for the point where the fire selects its oxygen",
            "sha256_before": hashlib.sha256(combustion_before).hexdigest(), "before_is_the_commit": BEFORE_M2,
            "sha256_after": hashlib.sha256((ROOT / "sim/fire/CombustionSystem.gd").read_bytes()).hexdigest(),
        },
        "untouched_sha256": {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() for relative in UNTOUCHED},
        "untouched_equal_to_before_m2": {
            relative: (ROOT / relative).read_bytes().replace(b"\r\n", b"\n") == _git("show", f"{BEFORE_M2}:{relative}").replace(b"\r\n", b"\n")
            for relative in UNTOUCHED},
        "budget_gap_accepted_kg": 1.0e-9,
    }
    record["before_m2"] = before_m2()
    record["acceptance"] = _launch(FIXTURE, PREFIX)
    record["stage_m1_again"] = _launch(INVENTORY_FIXTURE, INVENTORY_PREFIX)
    record["historical_route"] = historical_route()
    record["against_stage_m1"] = against_stage_m1(record["acceptance"])
    if args.selection_mutations:
        record["selection_mutations"] = mutations(args.selection_mutations.resolve())
    if args.inventory_mutations:
        record["inventory_mutations"] = mutations(args.inventory_mutations.resolve())
    if args.house:
        record["house"] = json.loads(args.house.read_text(encoding="utf-8"))
    saved = ROOT / RECORD
    saved.write_bytes((json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    for name in ("before_m2", "acceptance", "stage_m1_again"):
        item = record[name]
        print(f"{name}: checks {item['checks']} failed {item['failure_count']} script errors {item['script_errors']} pass {item['pass_marker']}")
    print("historical route identical:", record["historical_route"]["identical_figure_by_figure"], record["historical_route"]["differing"])
    print(saved.relative_to(ROOT).as_posix())
    green = all(record[name]["failure_count"] == 0 and record[name]["pass_marker"] for name in ("acceptance", "stage_m1_again"))
    return 0 if green and record["historical_route"]["identical_figure_by_figure"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
