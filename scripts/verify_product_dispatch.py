"""Run native dispatch controls through the project's unchanged safe monitor."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness

FIXTURE = "tests/fixtures/product_dispatch_contract.gd"
PREFIX = "PRODUCT_DISPATCH_CONTRACT "
MUTATIONS = {
    "D01_past_time_rescaled": (
        "Main.gd", "_sim_step_accum_s += delta * engine.time_scale",
        "_sim_step_accum_s += delta",
        "past callbacks lose their own speed", "one_to_twenty_pending: exact 0.40 s"),
    "D02_speed_applied_twice": (
        "Main.gd", "_sim_step_accum_s / engine.time_scale",
        "_sim_step_accum_s * 1.0",
        "engine scales already scaled seconds again", "one_to_twenty_pending: no simulated time invented"),
    "D03_pending_time_discarded": (
        "Main.gd", "_sim_step_accum_s += delta * engine.time_scale",
        "_sim_step_accum_s = delta * engine.time_scale",
        "pending callbacks are discarded before dispatch", "one_to_twenty_pending: exact 0.40 s"),
    "D04_chart_uses_effective_delta": (
        "Main.gd", "_sample_live_charts(elapsed_real_s)",
        "_sample_live_charts(step_delta)",
        "speed changes distort the chart wall clock", "one_to_twenty_pending: chart cadence preserves wall time"),
    "D05_fixed_step_batched": (
        "Main.gd", "if engine.sim_fixed_dt > 0.0:\n\t\treturn true",
        "if engine.sim_fixed_dt > 0.0:\n\t\treturn false",
        "fixed-step callbacks are dropped", "fixed_0.25: fixed-step contract"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--mutations", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists() or work.is_relative_to(ROOT) or not sys.flags.utf8_mode:
        raise RuntimeError("Use UTF-8 and a new external work directory")
    sources = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
               for p in ("Main.gd", "sim/core/SimulationEngine.gd", FIXTURE)}
    if args.mutations:
        # The shared mutation machinery validates all anchors, admits one native
        # launch at a time, rejects infrastructure errors, and restores raw bytes.
        originals, variants = harness.machinery.prepared(MUTATIONS, ("Main.gd",))
        declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
        harness.execute(work, originals, variants, declared, fixture=FIXTURE,
                        prefix=PREFIX.rstrip(), schema="product_dispatch_mutations_v1",
                        integration=True)
        return 0
    prepare_environment(work)
    result = godot_monitored_launch.run(
        [run_scenario._find_godot(), "--headless", "--path", ROOT,
         "--script", ROOT / FIXTURE], timeout_s=180, environment=os.environ.copy())
    (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
    (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
    lines = [line[len(PREFIX):] for line in result.stdout.splitlines()
             if line.startswith(PREFIX)]
    payload = json.loads(lines[0]) if len(lines) == 1 else None
    infrastructure_ok = (result.launched and not result.faults and not result.preexisting
                         and not any(marker in result.stdout + result.stderr
                                     for marker in ("SCRIPT ERROR", "Parse Error", "ERROR:")))
    passed = (infrastructure_ok and result.returncode == 0 and payload is not None
              and payload["checks"] > 1000 and payload["failure_count"] == 0)
    report = {"passed": passed, "infrastructure_ok": infrastructure_ok,
              "returncode": result.returncode, "health": result.health,
              "faults": result.faults, "preexisting": result.preexisting,
              "control": payload, "sources_sha256": sources}
    (work / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"passed": passed, "infrastructure_ok": infrastructure_ok,
                      "control": payload, "report": str(work / "result.json")}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
