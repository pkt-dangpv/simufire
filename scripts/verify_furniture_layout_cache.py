"""Native cache control/mutations, with the existing owned-process monitor."""

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

LAYOUT = "view/furniture/FurnitureVisualLayout.gd"
LOADER = "view/3d/furniture/FurnitureAssetLoader.gd"
OVERVIEW = "view/3d/Visualizer3D.gd"
FP = "view/fp/FirstPersonController.gd"
FIXTURE = "tests/fixtures/furniture_layout_cache.gd"
PREFIX = "FURNITURE_LAYOUT_CACHE"
SOURCES = (LAYOUT, LOADER, OVERVIEW, FP, FIXTURE, "scripts/verify_furniture_layout_cache.py")

MUTATIONS = {
    "C01_no_reuse": (LAYOUT, 'if _room_cache.has(slot) and _room_cache[slot]["key"] == key:',
                     "if false:", "no cache reuse", "warm reuse"),
    "C02_pose_key": (LAYOUT, 'for field: String in DYNAMIC_FIELDS:\n\t\t\tspec.erase(field)',
                    'for field: String in DYNAMIC_FIELDS:\n\t\t\tspec.erase(field)\n\t\tspec.erase("position_m")',
                    "pose omitted from key", "static invalidation "),
    "C03_door_key": (LAYOUT, "var_to_bytes([rect, doors, geometry, _asset_tokens(specs)])",
                    "var_to_bytes([rect, [], geometry, _asset_tokens(specs)])",
                    "door bands omitted", "door geometry invalidation"),
    "C04_frozen_state": (LAYOUT, 'var current: Dictionary = specs[index].duplicate(true)',
                        'var current: Dictionary = specs[index].duplicate(true)\n\t\tcurrent["state"] = "cold"',
                        "stale combustion state", "fresh dynamic state"),
    "C05_patch_alias": (LAYOUT, "return value.duplicate(true) if value is Array or value is Dictionary else value",
                       "return value", "returned pose patches alias cache", "identity pose patch isolated"),
    "C06_asset_signal": (LAYOUT, "_asset_invalidator = func(): invalidate_all()",
                         "_asset_invalidator = func(): pass", "asset signal ignored", "asset signal invalidation"),
    "C07_dead_owner": (LAYOUT, "if owner != null and owner.get_ref() == null:", "if false:",
                       "dead owners retained", "released owner pruned"),
    "C08_bound": (LAYOUT, "if not _room_cache.has(slot) and _room_cache.size() >= MAX_CACHED_ROOMS:",
                  "if false:", "unbounded room cache", "bounded cache"),
    "C09_native_sizes": (LOADER, "\t_native_size_cache.clear()", "\tpass",
                         "native size cache not reset", "native sizes invalidated"),
    "C10_overview_rebuild": (OVERVIEW, "\tFurnitureVisualLayout.invalidate_all()", "\tpass",
                            "overview rebuild ignores cache", "overview rebuild invalidates"),
    "C11_fp_rebuild": (FP, "\tFurnitureVisualLayout.invalidate_all()", "\tpass",
                      "FP rebuild ignores cache", "fp rebuild invalidates"),
}


def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in SOURCES}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--mutations", action="store_true")
    args = parser.parse_args()
    if not sys.flags.utf8_mode:
        raise RuntimeError("use python -X utf8")
    work = args.work.resolve()
    if work.exists():
        raise RuntimeError("use a new external work directory")
    before = hashes()
    if args.mutations:
        originals, variants = harness.machinery.prepared(MUTATIONS, (LAYOUT, LOADER, OVERVIEW, FP))
        declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
        try:
            harness.execute(work, originals, variants, declared, fixture=FIXTURE,
                            prefix=PREFIX, schema="furniture_layout_cache_mutations_v1", integration=True)
        finally:
            if hashes() != before:
                raise RuntimeError("mutations did not restore exact source bytes")
        return
    prepare_environment(work)
    os.environ.update(PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    record = {"schema": "furniture_layout_cache_control_v1", "state": "in_progress",
              "sources_sha256_raw": before, "physics_changed": False}
    try:
        executable = run_scenario._find_godot()
        if executable is None:
            raise RuntimeError("Godot unavailable")
        result = godot_monitored_launch.run(
            [executable, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
            timeout_s=300, environment=os.environ.copy())
        record["health"] = result.health
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        if not result.launched or result.returncode != 0 or result.faults or result.preexisting:
            raise RuntimeError(f"unhealthy fixture: {result.returncode}, {result.faults}, {result.preexisting}")
        verdict, payload = harness.classify(result.stdout, result.stderr, result.returncode, PREFIX)
        if verdict != "pass" or "ERROR:" in result.stdout + result.stderr:
            raise RuntimeError(f"fixture not accepted: {payload}")
        record["fixture"] = payload
        if hashes() != before:
            raise RuntimeError("sources changed during control")
        record["state"] = "passed"
    except Exception as exc:
        record.update(state="failed", error=str(exc))
        raise
    finally:
        (work / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
        print(json.dumps({"state": record["state"], "checks": record.get("fixture", {}).get("checks"),
                          "record": str(work / "result.json")}), flush=True)


if __name__ == "__main__":
    main()
