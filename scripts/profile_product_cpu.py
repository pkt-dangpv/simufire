"""Profile real Casa simple callbacks headlessly; never report this as FPS.

Uses a fresh external runtime, copied startup options and the unchanged owned
Godot monitor. Does not change production scripts, physical dt or visual quality.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment

FIXTURE = "tests/fixtures/product_cpu_profile.gd"
PREFIX = "PRODUCT_CPU_PROFILE "


def summary(values):
    if not values or any(type(x) not in (int, float) or not math.isfinite(x) or x < 0 for x in values):
        raise ValueError("invalid timing samples")
    ordered = sorted(values)
    return {"calls": len(values), "median_ms": statistics.median(values) / 1000,
            "p95_ms": ordered[math.ceil(.95 * len(values)) - 1] / 1000,
            "max_ms": max(values) / 1000, "mean_ms": statistics.mean(values) / 1000}


def inventory():
    paths = subprocess.check_output(
        ["git", "ls-files", "Main.gd", "sim", "view", "ui", "scenes", "project.godot", "scenarios"],
        cwd=ROOT, text=True).splitlines()
    paths.extend((FIXTURE, "scripts/profile_product_cpu.py"))
    return {p: hashlib.sha256((ROOT / p).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for p in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--options", type=Path, required=True)
    parser.add_argument("--view", choices=("2d", "3d", "fp"), required=True)
    args = parser.parse_args()
    if not sys.flags.utf8_mode:
        raise RuntimeError("use python -X utf8")
    work = args.work.resolve()
    if work.exists():
        raise RuntimeError("use a new external work directory")
    original = args.options.read_bytes()
    options = json.loads(original)
    if options.get("template_name") != "simple_house":
        raise RuntimeError("not Casa simple")
    sources = inventory()
    prepare_environment(work)
    os.environ.update(PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    userdata = Path(os.environ["APPDATA"]) / "Godot/app_userdata/SimuFire"
    userdata.mkdir(parents=True, exist_ok=True)
    (userdata / "startup_sim_options.json").write_bytes(original)
    record = {"schema": "product_cpu_profile_v1", "state": "in_progress", "view": args.view,
              "startup_options": options, "source_hashes_lf": sources,
              "rendered_fps_measured": False, "gpu_measured": False}
    output = work / "result.json"
    output.write_text(json.dumps(record, indent=2), encoding="utf-8")
    try:
        executable = run_scenario._find_godot()
        if executable is None:
            raise RuntimeError("Godot unavailable")
        result = godot_monitored_launch.run(
            [executable, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE,
             "--", "--profile-view=" + args.view], timeout_s=300, environment=os.environ.copy())
        record["health"] = result.health
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        if not result.launched or result.returncode != 0 or result.faults or result.preexisting:
            raise RuntimeError(f"unhealthy launch: {result.returncode}, {result.faults}, {result.preexisting}")
        if any(s in result.stdout + result.stderr for s in ("SCRIPT ERROR", "Parse Error")):
            raise RuntimeError("script error is not performance evidence")
        lines = [s for s in result.stdout.splitlines() if s.startswith(PREFIX)]
        if len(lines) != 1:
            raise RuntimeError("missing unique terminal profile")
        payload = json.loads(lines[0][len(PREFIX):])
        if payload["errors"] or payload["display_server"] != "headless" or payload["view"] != args.view:
            raise RuntimeError("invalid diagnostic scope or controls")
        if payload["rendered_fps_measured"] or payload["gpu_measured"]:
            raise RuntimeError("headless is not rendered performance")
        record["profile"] = payload
        record["timings"] = {name: summary(values) for name, values in payload["measurements_us"].items()}
        if inventory() != sources or args.options.read_bytes() != original:
            raise RuntimeError("source or original user options changed")
        record["state"] = "passed"
    except Exception as exc:
        record.update(state="failed", error=str(exc))
        raise
    finally:
        output.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({"state": record["state"], "record": str(output),
                          "timings": record.get("timings", {})}), flush=True)


if __name__ == "__main__":
    main()
