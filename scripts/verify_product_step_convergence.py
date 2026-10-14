"""Predeclared exploratory time-step screen; never changes physical baselines."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment

FIXTURE = "tests/fixtures/product_step_convergence.gd"
# Absolute floor + relative tolerance. Screening only, not calibrated physical
# acceptance criteria; fixed before collecting any trace on this machine.
TOLERANCES = {
    "hrr_kw": (5.0, .02), "temp_upper_c": (5.0, .02),
    "temp_lower_c": (5.0, .02), "smoke_kg": (.002, .05),
    "co_upper_ppm": (20.0, .05), "o2_upper": (.002, 0.0),
    "o2_lower": (.002, 0.0), "smoke_layer_m": (.05, .02),
    "upper_energy_kj": (100.0, .05), "lower_energy_kj": (100.0, .05),
    "released_heat_kj": (50.0, .02),
}


def source_hashes():
    paths = subprocess.check_output(["git", "ls-files", "sim"], cwd=ROOT,
                                    text=True).splitlines()
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}


def compare(reference, candidate):
    assert reference["fields"] == candidate["fields"], "different field ordering"
    checked, failed = 0, 0
    worst = {}
    for expected, actual in zip(reference["samples"], candidate["samples"], strict=True):
        assert expected["time_s"] == actual["time_s"]
        assert expected["rooms"].keys() == actual["rooms"].keys()
        for room, values in expected["rooms"].items():
            for field, ref, value in zip(reference["fields"], values,
                                         actual["rooms"][room], strict=True):
                floor, relative = TOLERANCES[field]
                if not math.isfinite(ref) or not math.isfinite(value):
                    raise ValueError("non-finite comparison value")
                tolerance = floor + relative * abs(ref)
                difference = abs(value - ref)
                ratio = difference / tolerance
                checked += 1
                failed += ratio > 1.0
                if field not in worst or ratio > worst[field]["tolerance_ratio"]:
                    worst[field] = {"tolerance_ratio": ratio, "difference": difference,
                                    "reference": ref, "candidate": value,
                                    "room": room, "time_s": expected["time_s"]}
    return {"checked": checked, "failed": failed, "passed": failed == 0, "worst": worst}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--duration", type=int, default=180)
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists() or work.is_relative_to(ROOT) or not sys.flags.utf8_mode:
        raise RuntimeError("Use UTF-8 and a new external evidence directory")
    prepare_environment(work)
    sources = source_hashes()
    plan = {"duration_s": args.duration, "denominators": [60, 12, 30, 40],
            "scenarios": ["open", "close_reopen"], "repeat_reference": True,
            "absolute_plus_relative_tolerances": TOLERANCES,
            "scope": "new exploratory screen; not the original laptop fixture or experimental validation",
            "sim_sources_sha256": sources,
            "fixture_sha256": hashlib.sha256((ROOT / FIXTURE).read_bytes()).hexdigest(),
            "launcher_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (work / "plan.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")
    results, comparisons, deterministic = [], {}, {}
    for scenario in plan["scenarios"]:
        traces = {}
        for label, denominator in [("reference", 60), ("step12", 12),
                                    ("step30", 30), ("step40", 40), ("repeat", 60)]:
            folder = work / f"{scenario}_{label}"
            folder.mkdir()
            path = folder / "trace.json"
            result = godot_monitored_launch.run(
                [run_scenario._find_godot(), "--headless", "--path", ROOT,
                 "--log-file", folder / "godot.log",
                 "--script", ROOT / FIXTURE, "--", f"--step-denominator={denominator}",
                 f"--door-schedule={scenario}", f"--duration-s={args.duration}",
                 f"--evidence-out={path}"], timeout_s=600, environment=os.environ.copy())
            (folder / "stdout.log").write_text(result.stdout, encoding="utf-8")
            (folder / "stderr.log").write_text(result.stderr, encoding="utf-8")
            (folder / "health.json").write_text(json.dumps(result.health, indent=2), encoding="utf-8")
            if (not result.launched or result.returncode != 0 or result.faults or result.preexisting
                    or any(s in result.stdout + result.stderr for s in
                           ("SCRIPT ERROR", "Parse Error", "ERROR:"))):
                raise RuntimeError(f"Invalid {scenario}/{label}: {result.returncode}, {result.faults}, {result.stderr[-1000:]}")
            trace = json.loads(path.read_text(encoding="utf-8"))
            assert trace["finite_values"] and trace["clock_ok"]
            assert len(trace["samples"]) == args.duration
            traces[label] = trace
            results.append({"scenario": scenario, "label": label, "dt_s": 1 / denominator,
                            "wall_s": trace["wall_s"], "path": str(path)})
            print(json.dumps(results[-1]), flush=True)
        deterministic[scenario] = traces["reference"]["samples"] == traces["repeat"]["samples"]
        if not deterministic[scenario]:
            raise RuntimeError(f"Reference is not repeatable: {scenario}")
        comparisons[scenario] = {label: compare(traces["reference"], traces[label])
                                 for label in ("step12", "step30", "step40")}
        print(json.dumps({"scenario": scenario, "screen": {
            label: {key: value for key, value in record.items() if key != "worst"}
            for label, record in comparisons[scenario].items()}}), flush=True)
    assert source_hashes() == sources, "Physical source files changed during screening"
    report = {"execution_passed": True, "physical_sources_unchanged": True,
              "reference_deterministic": deterministic, "runs": results,
              "comparisons": comparisons, "plan": "plan.json"}
    (work / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(work / "result.json"), "execution_passed": True}), flush=True)


if __name__ == "__main__":
    main()
