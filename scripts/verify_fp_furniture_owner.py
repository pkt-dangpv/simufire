"""Single FP furniture owner control, via the unchanged owned Godot monitor."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment

FIXTURE = "tests/fixtures/fp_furniture_owner.gd"
PREFIX = "FP_FURNITURE_OWNER "
OVERVIEW = "view/3d/Visualizer3D.gd"
SOURCES = ("Main.gd", OVERVIEW, "view/fp/FirstPersonController.gd", FIXTURE,
           "tools/validate_furniture_runtime.gd", "scenes/SimulationScene.tscn",
           "tests/fixtures/product_furniture_overlap.gd",
           "view/furniture/FurnitureVisualLayout.gd", "scripts/verify_fp_furniture_owner.py")
MUTATIONS = {
    "O01_duplicate_default": (
        OVERVIEW, "@export var show_fuel_objects_in_first_person: bool = false",
        "@export var show_fuel_objects_in_first_person: bool = true",
        "restore duplicated furniture", "product default suppresses duplicate"),
    "O02_hidden_refresh": (
        OVERVIEW, "\tif not show_fuel_objects_in_first_person:\n\t\treturn false\n",
        "", "refresh hidden overview furniture", "skip hidden furniture refresh"),
    "O03_entry_visibility": (
        OVERVIEW,
        "child.visible = show_fuel_objects_3d and (not _first_person_overlay or show_fuel_objects_in_first_person)",
        "child.visible = show_fuel_objects_3d",
        "show duplicate on FP entry", "single visible furniture owner"),
    "O04_refresh_visibility": (
        OVERVIEW,
        "\t\tand (not _first_person_overlay or show_fuel_objects_in_first_person) \\\n",
        "",
        "show duplicate after a state refresh", "single visible furniture owner"),
    "O05_lost_3d_refresh": (
        OVERVIEW,
        "func _should_update_fuel_objects_this_pass() -> bool:\n\tif not _first_person_overlay:\n\t\treturn true",
        "func _should_update_fuel_objects_this_pass() -> bool:\n\tif not _first_person_overlay:\n\t\treturn false",
        "do not resume 3D furniture updates", "3D furniture refresh restored"),
}


def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in SOURCES}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--mutations", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    if not sys.flags.utf8_mode or work.exists() or work.is_relative_to(ROOT):
        raise RuntimeError("use python -X utf8 and a new external directory")
    sources = hashes()
    if args.mutations:
        originals, variants = harness.machinery.prepared(MUTATIONS, (OVERVIEW,))
        declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
        try:
            harness.execute(work, originals, variants, declared, fixture=FIXTURE,
                            prefix=PREFIX.rstrip(), schema="fp_furniture_owner_mutations_v1",
                            integration=True)
        finally:
            if hashes() != sources:
                raise RuntimeError("mutations did not restore exact source bytes")
        return
    prepare_environment(work)
    os.environ.update(PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    record = {"state": "in_progress", "sources_sha256_raw": sources}
    try:
        executable = run_scenario._find_godot()
        if executable is None:
            raise RuntimeError("Godot unavailable")
        result = godot_monitored_launch.run(
            [executable, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
            timeout_s=120, environment=os.environ.copy())
        record["health"] = result.health
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        if not result.launched or result.returncode != 0 or result.faults or result.preexisting:
            raise RuntimeError(f"unhealthy fixture: {result.returncode}, {result.faults}, {result.preexisting}")
        if any(t in result.stdout + result.stderr for t in ("SCRIPT ERROR", "Parse Error", "ERROR:")):
            raise RuntimeError("script errors invalidate the control")
        lines = [s for s in result.stdout.splitlines() if s.startswith(PREFIX)]
        if len(lines) != 1:
            raise RuntimeError("missing unique terminal result")
        payload = json.loads(lines[0][len(PREFIX):])
        if payload["failure_count"] or payload["failures"] or type(payload.get("checks")) is not int or payload["checks"] <= 0:
            raise RuntimeError(f"control failed: {payload}")
        record["control"] = payload
        if hashes() != sources:
            raise RuntimeError("sources changed during control")
        record["state"] = "passed"
    except Exception as exc:
        record.update(state="failed", error=str(exc))
        raise
    finally:
        (work / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
        print(json.dumps({"state": record["state"], "record": str(work / "result.json")}), flush=True)


if __name__ == "__main__":
    main()
