"""M2-T live acceptance and houses, sequential through the owned-process monitor.

Never relaxes the 6-GiB preflight. --fixture-only runs the judged fixture only.
No reference regeneration, commit or push is implicit in this runner.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import run_g3_o2_transport_gate as gate  # noqa: E402
from scripts.simulation import run_g3_o2_venting_house as house  # noqa: E402

FIXTURE = "tests/fixtures/g3_o2_transport_acceptance.gd"
PREFIX = "G3_O2_TRANSPORT "


def acceptance(work: Path, expect_failure: bool = False) -> dict:
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    run = godot_monitored_launch.run(
        [godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
        timeout_s=1200, environment=os.environ.copy(),
    )
    (work / "acceptance.stdout.log").write_text(run.stdout, encoding="utf-8")
    (work / "acceptance.stderr.log").write_text(run.stderr, encoding="utf-8")
    expected_exit = 1 if expect_failure else 0
    if not run.launched or run.returncode != expected_exit or run.faults or run.preexisting:
        raise RuntimeError(f"fixture not healthy/green: {run.returncode}; {run.faults}; {run.stderr[-2000:]}")
    if "SCRIPT ERROR" in run.stdout + run.stderr or "Parse Error" in run.stdout + run.stderr:
        raise RuntimeError("fixture has script/parse errors")
    lines = [line for line in run.stdout.splitlines() if line.startswith(PREFIX)]
    if len(lines) != 1:
        raise RuntimeError("fixture missing unique terminal payload")
    payload = json.loads(lines[0][len(PREFIX):])
    if payload["checks"] <= 0 or (payload["failure_count"] > 0) != expect_failure:
        raise RuntimeError("fixture not accepted")
    payload["returncode"] = run.returncode
    payload["health"] = run.health
    return payload


def compare_base(work: Path) -> dict:
    """Same fixture, earlier engine: valid assertion failures, never script errors."""
    paths = ("sim/core/RoomOxygenInventory.gd", "sim/core/OxygenExchangeSystem.gd")
    originals = {path: (ROOT / path).read_bytes() for path in paths}
    before = {path: gate.git("show", f"{gate.BASE}:{path}") for path in paths}
    evidence = work / "before"
    evidence.mkdir(exist_ok=False)
    health_env = godot_monitored_launch.HEALTH_LOG_ENV
    previous_log = os.environ[health_env]
    os.environ[health_env] = str(evidence / "godot.health.jsonl")
    try:
        for path, raw in before.items():
            (ROOT / path).write_bytes(raw)
        result = acceptance(evidence, expect_failure=True)
    finally:
        for path, raw in originals.items():
            (ROOT / path).write_bytes(raw)
        os.environ[health_env] = previous_log
        if any((ROOT / path).read_bytes() != raw for path, raw in originals.items()):
            raise RuntimeError("baseline control failed to restore original bytes")
    result["base"] = gate.BASE
    result["restored_byte_for_byte"] = True
    result["sources_before_sha256"] = {path: gate.normalized_sha(raw) for path, raw in before.items()}
    result["sources_restored_sha256"] = {path: gate.normalized_sha(raw) for path, raw in originals.items()}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--fixture-only", action="store_true")
    parser.add_argument("--compare-base", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    gate.prepare_environment(work)
    preexisting = godot_monitored_launch.preexisting_godot_state()
    fault = godot_monitored_launch.memory_gate_fault()
    if preexisting or fault:
        raise RuntimeError(f"preflight refuses execution: {preexisting or fault}")
    sources = gate.source_inventory()
    earlier = compare_base(work) if args.compare_base else None
    if earlier:
        print(f"base fixture: {earlier['failure_count']} failed checks, no script errors; restored", flush=True)
    fixture = acceptance(work)
    print(f"fixture: {fixture['checks']} checks, 0 failures", flush=True)
    cases = {}
    if not args.fixture_only:
        for name in house.CASES:
            folder = house.launch(name, "on")
            evaluated = house.evaluate(folder, None)
            trace = gate.analyze_trace(folder)
            trace["evidence_kind"] = "fresh monitored house run; per-step trace independently reanalyzed"
            budget = evaluated["budget"]
            if not evaluated["whole"] or not budget["closes_in_every_step"]:
                raise RuntimeError(f"{name} incomplete/nonconservative")
            if budget["largest_number_of_entries"] != 0 or budget["delayed_exchanges"] != 0:
                raise RuntimeError(f"{name} still dispatches future obligations")
            if any(room["rich_steps"] for room in trace["rooms"].values()):
                raise RuntimeError(f"{name} still enriches above initial/outside composition")
            health = json.loads((folder / "monitor.health.json").read_text(encoding="utf-8"))
            faults = godot_monitored_launch.infrastructure_faults(health)
            if faults or health.get("cleanup_terminated_pids") != []:
                raise RuntimeError(f"{name} unhealthy: {faults}")
            cases[name] = {"evaluation": evaluated, "trace": trace, "health": health}
            print(f"{name}: 10800 steps, no obligations/enrichment; closes", flush=True)
    if gate.source_inventory() != sources:
        raise RuntimeError("engine source changed during measurement")
    record = {
        "schema": "g3_o2_transport_m2t_acceptance_v1", "base": gate.BASE,
        "implemented": True, "product_activation": False,
        "scope": "immediate symmetric O2 on reference gas; other species delays unchanged",
        "sources": sources, "before": earlier, "fixture": fixture, "houses": cases,
        "launch_health": gate.verified_health(work),
        "harness_sha256_lf": {path: hashlib.sha256(
            (ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for path in (FIXTURE, "scripts/simulation/run_g3_o2_transport.py",
                         "scripts/simulation/run_g3_fuel_baseline.py")},
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"record: {args.out}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
