#!/usr/bin/env python3
"""Record of stage M2-V of the oxygen authority: pressure venting as an operation of the
owner of the room oxygen inventory.

Each launch goes through the monitored launcher, one Godot at a time:

1. BEFORE M2-V. The tracked engine files this stage changes are put back, byte for byte,
   to the commit before it; the acceptance fixture of the stage runs; the files are
   restored and verified. The fixture must reach its end with failed checks and no
   script error: on that engine the first venting event with a quantity refuses the run.
2. ACCEPTANCE. The fixture of the stage on the working tree, whole. It must pass.
3. STAGES M1 AND M2 AGAIN. Their acceptance fixtures on the working tree. They must pass.
4. HISTORICAL ROUTE. The diagnosis published on 2026-10-09 measured again with the
   switch off and compared figure by figure with its published record.
5. What was run elsewhere is read: the three mutation suites and the house cases.

    python scripts/simulation/run_g3_o2_venting.py \
        --venting-mutations runs/g3_o2_venting_mutations_<stamp>/results.json \
        --selection-mutations runs/g3_o2_selection_mutations_<stamp>/results.json \
        --inventory-mutations runs/g3_o2_room_inventory_mutations_<stamp>/results.json \
        --house <file written by run_g3_o2_venting_house.py>
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_o2_selection as m2  # noqa: E402

SCHEMA = "g3_o2_pressure_venting_m2v_record_v1"
RECORD = "docs/validation/G3_O2_PRESSURE_VENTING_M2V_2026-10-10.json"
FIXTURE = "tests/fixtures/g3_o2_venting.gd"
PREFIX = "G3_O2_VENTING"
# The commit before this stage: stage M2, where pressure venting is a refused route.
BEFORE_M2V = "461fa9c0"
# Tracked engine files this stage changes.
CHANGED_BY_M2V = ("sim/core/GasExchangeSystem.gd", "sim/core/RoomOxygenInventory.gd")
SOURCES = CHANGED_BY_M2V + ("sim/core/OxygenExchangeSystem.gd", "sim/core/SimulationEngine.gd", "sim/fire/CombustionSystem.gd",
                            "sim/building/RoomModel.gd", "tools/run_scenario_headless.gd",
                            FIXTURE, m2.FIXTURE, m2.INVENTORY_FIXTURE)
# Left as they were, by content.
UNTOUCHED = ("sim/fire/PrescribedObjectHrrSource.gd", "sim/fire/PrescribedThermalSourceCoupling.gd", "sim/fire/CombustionSystem.gd",
             "sim/core/OxygenExchangeSystem.gd", "sim/core/SimulationEngine.gd", "sim/building/RoomModel.gd")


def before_m2v() -> dict:
    """The fixture of the stage on the engine of the commit before it. Restores and verifies."""
    current = {relative: (ROOT / relative).read_bytes() for relative in CHANGED_BY_M2V}
    earlier = {relative: m2._git("show", f"{BEFORE_M2V}:{relative}") for relative in CHANGED_BY_M2V}
    try:
        for relative, data in earlier.items():
            (ROOT / relative).write_bytes(data)
        result = m2._launch(FIXTURE, PREFIX)
    finally:
        for relative, data in current.items():
            (ROOT / relative).write_bytes(data)
            if (ROOT / relative).read_bytes() != data:
                raise RuntimeError(f"{relative} not restored byte for byte")
    observations = result.pop("observations")
    result["engine"] = f"tracked engine files of {BEFORE_M2V}, byte for byte"
    result["engine_sha256"] = {relative: m2._sha(data) for relative, data in earlier.items()}
    result["restored_byte_for_byte"] = True
    room = observations.get("room_that_vents", {})
    result["the_defect_measured"] = {
        "steps_asked": room.get("steps"), "steps_before_the_run_was_refused": room.get("steps_before_a_refusal"),
        "venting_operations": room.get("events"),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--venting-mutations", type=Path, help="results.json of run_g3_o2_venting_mutations.py")
    parser.add_argument("--selection-mutations", type=Path, help="results.json of run_g3_o2_selection_mutations.py")
    parser.add_argument("--inventory-mutations", type=Path, help="results.json of run_g3_o2_room_inventory_mutations.py")
    parser.add_argument("--house", type=Path, help="file written by run_g3_o2_venting_house.py")
    args = parser.parse_args()
    record = {
        "schema": SCHEMA, "head": m2._git("rev-parse", "--short=8", "HEAD").decode().strip(),
        "scope": "stage M2-V of the oxygen authority: the dilution of pressure venting as one operation of the owner of the "
                 "room oxygen inventory, with an entry and an exit, behind the same switch, off by default; conservation, "
                 "ownership, the whole house cases and the cause of the historical gap; an equivalent dilution on the "
                 "reference content of the room, not a conservation of the mass of gas; no heat fitted to the oxygen (M3), "
                 "no zonal split (M4), no CO, FED or SVV",
        "sources_sha256": {relative: m2._sha((ROOT / relative).read_bytes()) for relative in SOURCES},
        "untouched_sha256": {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() for relative in UNTOUCHED},
        "untouched_equal_to_before_m2v": {
            relative: (ROOT / relative).read_bytes().replace(b"\r\n", b"\n")
            == m2._git("show", f"{BEFORE_M2V}:{relative}").replace(b"\r\n", b"\n") for relative in UNTOUCHED},
        "budget_gap_accepted_kg": 1.0e-9,
    }
    record["before_m2v"] = before_m2v()
    record["acceptance"] = m2._launch(FIXTURE, PREFIX)
    record["stage_m1_again"] = m2._launch(m2.INVENTORY_FIXTURE, m2.INVENTORY_PREFIX)
    record["stage_m2_again"] = m2._launch(m2.FIXTURE, m2.PREFIX)
    for name in ("stage_m1_again", "stage_m2_again"):
        record[name].pop("observations")
    record["historical_route"] = m2.historical_route()
    for name, path in (("venting_mutations", args.venting_mutations), ("selection_mutations", args.selection_mutations),
                       ("inventory_mutations", args.inventory_mutations)):
        if path:
            record[name] = m2.mutations(path.resolve())
    if args.house:
        record["house"] = json.loads(args.house.read_text(encoding="utf-8"))
    saved = ROOT / RECORD
    saved.write_bytes((json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    for name in ("before_m2v", "acceptance", "stage_m1_again", "stage_m2_again"):
        item = record[name]
        print(f"{name}: checks {item['checks']} failed {item['failure_count']} script errors {item['script_errors']} pass {item['pass_marker']}")
    print("historical route identical:", record["historical_route"]["identical_figure_by_figure"], record["historical_route"]["differing"])
    print(saved.relative_to(ROOT).as_posix())
    green = all(record[name]["failure_count"] == 0 and record[name]["pass_marker"]
                for name in ("acceptance", "stage_m1_again", "stage_m2_again"))
    return 0 if green and record["historical_route"]["identical_figure_by_figure"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
