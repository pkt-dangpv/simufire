"""Real-window paused/play/paused diagnosis, through the unchanged safe monitor."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.profile_product_cpu import inventory, summary
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment

FIXTURE = "tests/fixtures/product_render_profile.gd"
PREFIX = "PRODUCT_RENDER_PROFILE "


def source_inventory():
    values = inventory()
    for path in (FIXTURE, "tests/fixtures/fp_furniture_freeze_probe.gd", "scripts/profile_product_render.py"):
        values[path] = hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    return values


def phase_summary(phase, playing):
    frames = phase["frames"]
    if (not phase["window_visible"] or phase["window_minimized"] or not frames
            or phase["wall_s"] < 7.9 or not any(f["draw_calls"] > 0 for f in frames)):
        raise ValueError("not a complete visible rendered phase")
    intervals = [f["interval_us"] for f in frames]
    if any(x <= 0 for x in intervals):
        raise ValueError("invalid frame intervals")
    callbacks = phase["physics_callbacks"]
    delta = sum(s[2] for s in callbacks)
    simulated = phase["sim_end_s"] - phase["sim_start_s"]
    # Main dispatches one engine step per accumulated reference step (1/12 s),
    # so the clock may trail the callbacks by less than one step at a phase edge.
    if abs(delta - simulated) >= 1 / 12 + 1e-8:
        raise ValueError("callback delta and simulation clock disagree")
    if playing != bool(callbacks) or (not playing and simulated != 0):
        raise ValueError("paused/playing callback isolation broken")
    result = {
        "frames": len(frames), "mean_fps": 1e6 * len(intervals) / sum(intervals),
        "frame_interval": summary(intervals),
        "main_cpu_per_frame": summary([f["main_us"] for f in frames]),
        "physics_steps_per_frame_max": max(f["physics_steps"] for f in frames),
        "draw_calls_median": sorted(f["draw_calls"] for f in frames)[len(frames) // 2],
        "wall_s": phase["wall_s"], "simulated_s": simulated,
        "cache_hits_delta": phase["cache_after"]["hits"] - phase["cache_before"]["hits"],
        "cache_misses_delta": phase["cache_after"]["misses"] - phase["cache_before"]["misses"],
    }
    if all("probe_us" in f for f in frames):
        result["diagnostic_cpu_per_frame"] = summary([f["probe_us"] for f in frames])
    for label in ("render_cpu_ms", "render_gpu_ms", "render_setup_ms"):
        values = [f[label] for f in frames]
        if any(not math.isfinite(v) or v < 0 for v in values):
            raise ValueError("invalid render timer")
        # Unsupported/zero render counters are UNKNOWN, never proof of free GPU.
        result[label] = summary([v * 1000 for v in values]) if any(v > 0 for v in values) else None
    if callbacks:
        result["main_callback"] = summary([s[0] for s in callbacks])
        # Older saved profiles have three entries and predate this marker.
        # New profiles explicitly distinguish engine dispatches from view ticks.
        steps = [s[1] for s in callbacks if len(s) < 4 or s[3]]
        result["engine_dispatches"] = len(steps)
        result["engine_step"] = summary(steps) if steps else None
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--options", type=Path, required=True)
    parser.add_argument("--view", choices=("3d", "fp"), required=True)
    parser.add_argument("--hide-minimap", action="store_true", help="diagnostic causal control only")
    parser.add_argument("--freeze-fp-furniture", action="store_true", help="diagnostic stale visuals control only")
    parser.add_argument("--hide-overview-furniture", action="store_true", help="diagnostic duplicate owner control")
    args = parser.parse_args()
    if args.freeze_fp_furniture and (args.view != "fp" or args.hide_minimap):
        raise RuntimeError("furniture control requires FP and no other intervention")
    if args.hide_overview_furniture and (
            args.view != "fp" or args.hide_minimap or args.freeze_fp_furniture):
        raise RuntimeError("overview furniture control requires FP and no other intervention")
    if not sys.flags.utf8_mode:
        raise RuntimeError("use python -X utf8")
    work = args.work.resolve()
    if work.exists():
        raise RuntimeError("use a new external work directory")
    original = args.options.read_bytes()
    options = json.loads(original)
    if options.get("template_name") != "simple_house":
        raise RuntimeError("requires Casa simple options")
    sources = source_inventory()
    prepare_environment(work)
    os.environ.update(PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    userdata = Path(os.environ["APPDATA"]) / "Godot/app_userdata/SimuFire"
    userdata.mkdir(parents=True, exist_ok=True)
    (userdata / "startup_sim_options.json").write_bytes(original)
    record = {"state": "in_progress", "schema": "product_render_profile_v1",
              "view": args.view, "options": options, "sources_lf_sha256": sources}
    try:
        executable = run_scenario._find_godot()
        if executable is None:
            raise RuntimeError("Godot unavailable")
        command = [executable, "--path", ROOT, "--script", ROOT / FIXTURE,
                   "--", "--profile-view=" + args.view]
        if args.hide_minimap:
            command.append("--hide-minimap")
        if args.freeze_fp_furniture:
            command.append("--freeze-fp-furniture")
        if args.hide_overview_furniture:
            command.append("--hide-overview-furniture")
        result = godot_monitored_launch.run(command, timeout_s=120, environment=os.environ.copy())
        record["health"] = result.health
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        if not result.launched or result.returncode != 0 or result.faults or result.preexisting:
            raise RuntimeError(f"unhealthy launch: {result.returncode}, {result.faults}, {result.preexisting}")
        if any(t in result.stdout + result.stderr for t in ("SCRIPT ERROR", "Parse Error", "ERROR:")):
            raise RuntimeError("script/render errors invalidate timing evidence")
        lines = [s for s in result.stdout.splitlines() if s.startswith(PREFIX)]
        if len(lines) != 1:
            raise RuntimeError("missing unique terminal profile")
        payload = json.loads(lines[0][len(PREFIX):])
        if payload["display_server"] == "headless" or payload["view"] != args.view:
            raise RuntimeError("not the requested real renderer")
        quality_changed = args.hide_minimap or args.freeze_fp_furniture or args.hide_overview_furniture
        if (payload["hide_minimap"] != args.hide_minimap
                or payload["freeze_fp_furniture"] != args.freeze_fp_furniture
                or payload["hide_overview_furniture"] != args.hide_overview_furniture
                or payload["quality_changed"] != quality_changed):
            raise RuntimeError("wrong causal control scope")
        record["profile"] = payload
        record["summaries"] = {key: phase_summary(value, key == "playing")
                               for key, value in payload["phases"].items()}
        if source_inventory() != sources or args.options.read_bytes() != original:
            raise RuntimeError("sources or original options changed")
        record["state"] = "passed"
    except Exception as exc:
        record.update(state="failed", error=str(exc))
        raise
    finally:
        (work / "result.json").write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({"state": record["state"], "record": str(work / "result.json"),
                          "summaries": record.get("summaries", {})}), flush=True)


if __name__ == "__main__":
    main()
