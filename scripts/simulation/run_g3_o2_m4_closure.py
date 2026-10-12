"""One M4-A1 closure stage under the unchanged safe monitor. Never activates product.

Requires actual fixture/mutant records bound to the pure module and fixture.
Runtime of M3 must still match its published evidence. All temporary directories
and logs are external; no reference acceptance based only on a final banner.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch  # noqa: E402
from scripts.simulation import run_g3_o2_m4_partition as pure  # noqa: E402
from scripts.simulation import run_g3_o2_transport_closure as safe  # noqa: E402
from scripts.simulation import run_g3_o2_transport_gate as gate  # noqa: E402


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_inventory():
    """Current content, including the pure addition before AND after Git add.

    The inherited M2-T inventory pins a historical tracked set: it cannot
    include a newly committed module. M4 owns this additive snapshot; historical
    gates stay unchanged. Pure.MODEL is explicit even when still untracked.
    """
    paths = set(gate.git("ls-files", "sim/", "tools/run_scenario_headless.gd").decode().splitlines())
    paths.add(pure.MODEL)
    return {path: hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for path in sorted(paths)}


def prerequisites(control, mutations, current):
    if (control.get("state") != "passed" or control["model_sha256_raw"] != current["model"]
            or control["fixture_sha256_raw"] != current["fixture"]
            or control["oracle_sha256_raw"] != current["oracle"]):
        raise RuntimeError("control no longer binds current pure sources")
    if (control["fixture"].get("checks") != 160304 or control["fixture"].get("failure_count") != 0
            or control["fixture"].get("failures") != []):
        raise RuntimeError("control did not complete its declared checks")
    pure.audit_samples(control["fixture"])
    if (mutations.get("error") is not None or mutations.get("integration_validated") is not False
            or mutations.get("declared") != 14 or mutations.get("executed") != 14
            or mutations.get("killed_where_expected") != 14 or not mutations.get("originals_intact")
            or mutations["sha256_before"] != mutations["sha256_after"]
            or mutations["sha256_after"] != {pure.MODEL: current["model"]}
            or mutations["fixture_sha256_before"] != current["fixture"]
            or mutations["fixture_sha256_after"] != current["fixture"]):
        raise RuntimeError("falsification no longer binds current pure sources")
    results = mutations.get("results", [])
    if len(results) != 15 or results[0]["verdict"] != "pass":
        raise RuntimeError("falsification control incomplete")
    for item in results:
        health = item["health"]
        if godot_monitored_launch.infrastructure_faults(health) or health.get("cleanup_terminated_pids") != []:
            raise RuntimeError("unhealthy mutation control or mutant")
        if item["name"] != "control" and (item["verdict"] != "killed" or not item["seen_where_expected"]):
            raise RuntimeError("mutation did not die at its declared assertion")
    if (godot_monitored_launch.infrastructure_faults(control["health"])
            or control["health"].get("cleanup_terminated_pids") != []):
        raise RuntimeError("fixture health not accepted")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("reference", "product", "guardrails", "global"))
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--control", required=True, type=Path)
    parser.add_argument("--mutations", required=True, type=Path)
    args = parser.parse_args()
    if not sys.flags.utf8_mode:
        raise RuntimeError("use python -X utf8")
    os.environ.update({"PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8"})
    work = args.work.resolve()
    gate.prepare_environment(work)
    os.environ["SIMUFIRE_GODOT_TEST_APPDATA"] = str(work / "appdata")
    os.chdir(ROOT)
    current = {"model": sha(ROOT / pure.MODEL), "fixture": sha(ROOT / pure.FIXTURE),
               "oracle": sha(ROOT / "scripts/simulation/g3_m4_partition_contract.py")}
    control = json.loads(args.control.read_text(encoding="utf-8"))
    mutations = json.loads(args.mutations.read_text(encoding="utf-8"))
    prerequisites(control, mutations, current)
    evidence = json.loads((ROOT / "docs/validation/G3_O2_M3_CURRENT_TECHNICAL_EVIDENCE_2026-10-11.json")
                          .read_text(encoding="utf-8"))
    for path, expected in evidence["sources_sha256_lf"].items():
        if hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest() != expected:
            raise RuntimeError("M3 runtime changed: " + path)
    tracked = source_inventory()
    uids = safe.preserved_files()
    stashes = gate.git("stash", "list", "--format=%H").decode().splitlines()
    before_corpus = safe.corpus()
    before_reference = json.loads((ROOT / safe.REFERENCE).read_text(encoding="utf-8"))
    record = {"schema": "g3_m4a1_closure_stage_v1", "state": "in_progress", "stage": args.stage,
              "pure_sha256_raw": current, "tracked_sources": tracked,
              "preserved_uid_sha256": uids, "stashes": stashes}
    commands = {
        "reference": ([sys.executable, "scripts/simulation/run_reference_suite_monitored.py"], 7200),
        "product": ([sys.executable, "scripts/check_product.py"], 2400),
        "guardrails": ([sys.executable, "scripts/simulation/validation_guardrails.py"], 300),
        "global": ([sys.executable, "-m", "pytest", "tests", "-q", "-p", "no:cacheprovider",
                    "--basetemp", str(work / "pytest-global")], 3600),
    }
    safe.emit(work / "result.json", record)
    try:
        command, timeout = commands[args.stage]
        record["execution"] = safe.monitored(args.stage, command, work, timeout)
        if args.stage == "reference":
            after_corpus = safe.corpus()
            changed = sorted(path for path in before_corpus.keys() | after_corpus.keys()
                             if before_corpus.get(path) != after_corpus.get(path))
            after_reference = json.loads((ROOT / safe.REFERENCE).read_text(encoding="utf-8"))
            strip_time = lambda value: {key: val for key, val in value.items() if key != "generated_at"}
            if (changed != [safe.REFERENCE] or strip_time(before_reference) != strip_time(after_reference)
                    or (after_reference["required_count"], after_reference["failed_required_count"],
                        after_reference["known_gap_count"]) != (346, 0, 78)):
                raise RuntimeError(f"reference changed beyond its timestamp: {changed}")
            record["corpus"] = {"raw_before": before_corpus, "raw_after": after_corpus,
                                "files": len(before_corpus), "identical_files": len(before_corpus) - 1,
                                "changed_paths": changed, "only_generated_at_changed": True,
                                "required": 346, "failed_required": 0, "gaps": 78}
        after_tracked = source_inventory()
        if set(tracked) != set(after_tracked) or any(
                value != after_tracked[path] for path, value in tracked.items() if path != safe.REFERENCE):
            raise RuntimeError("runtime sources changed during closure")
        if current != {"model": sha(ROOT / pure.MODEL), "fixture": sha(ROOT / pure.FIXTURE),
                       "oracle": sha(ROOT / "scripts/simulation/g3_m4_partition_contract.py")}:
            raise RuntimeError("pure sources changed during closure")
        if safe.preserved_files() != uids or gate.git("stash", "list", "--format=%H").decode().splitlines() != stashes:
            raise RuntimeError("unrelated UID or stashes changed")
        record["state"] = "passed"
    except Exception as exc:
        record["state"] = "failed"
        record["error"] = str(exc)
        raise
    finally:
        safe.emit(work / "result.json", record)
        print(f"M4-A1 {args.stage}: {record['state']}; {work}", flush=True)


if __name__ == "__main__":
    main()
