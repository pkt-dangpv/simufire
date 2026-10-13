"""UI-only native control, through the existing safe Godot monitor."""

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

FIXTURE = "tests/fixtures/fp_live_charts.gd"
PREFIX = "FP_LIVE_CHARTS "
SOURCES = ("Main.gd", FIXTURE, "ui/charts/LiveChartsOverlay.gd",
           "ui/charts/InteractiveLineChart.gd", "scripts/verify_fp_live_charts.py")
MUTATIONS = {
    "F01_hidden_sampling": (
        "Main.gd", "if first_person_enabled or _live_overlay == null or engine == null:",
        "if _live_overlay == null or engine == null:",
        "hidden chart keeps exporting state", "no chart state exports in FP"),
    "F02_still_visible": (
        "Main.gd", "_live_charts_requested_visible and not first_person_enabled",
        "_live_charts_requested_visible", "chart still rendered in FP", "hidden in FP"),
    "F03_child_processing": (
        "Main.gd", "_live_overlay.process_mode = Node.PROCESS_MODE_DISABLED",
        "_live_overlay.process_mode = Node.PROCESS_MODE_INHERIT",
        "hidden chart subtree keeps processing", "child processing suspended in FP"),
    "F04_lost_preference": (
        "Main.gd", "func _sync_live_charts() -> void:",
        "func _sync_live_charts() -> void:\n\t_live_charts_requested_visible = true",
        "view switch loses the user's OFF preference", "restore user hidden preference"),
    "F05_missing_mode_sync": (
        "Main.gd", "func _sync_view_mode() -> void:\n\t_sync_live_charts()",
        "func _sync_view_mode() -> void:",
        "FP transition bypasses chart policy", "hidden in FP"),
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
        originals, variants = harness.machinery.prepared(MUTATIONS, ("Main.gd",))
        declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
        try:
            harness.execute(work, originals, variants, declared, fixture=FIXTURE,
                            prefix=PREFIX.rstrip(), schema="fp_live_charts_mutations_v1",
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
        if payload["failure_count"] or payload["failures"] or payload["checks"] != 26:
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
