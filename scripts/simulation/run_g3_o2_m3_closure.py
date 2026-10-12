"""One M3 closure stage at a time, using the established owned-process monitor.

Requires completed unchanged house controls and current technical evidence.
No publication or product activation. Writes partial and terminal records outside
the checkout; never lowers the memory gate or launches Godot directly.
"""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import run_g3_o2_m3_checks as checks  # noqa: E402
from scripts.simulation import run_g3_o2_transport_closure as closure  # noqa: E402
from scripts.simulation import run_g3_o2_transport_gate as gate  # noqa: E402

REFERENCE = closure.REFERENCE
EVIDENCE = "docs/validation/G3_O2_M3_CURRENT_TECHNICAL_EVIDENCE_2026-10-11.json"


def require_prerequisites(evidence, houses, current):
    if evidence["sources_sha256_raw"] != current or houses["sources_sha256_raw"] != current:
        raise RuntimeError("prerequisite evidence does not bind current engine bytes")
    for name in ("integration", "owner"):
        campaign = evidence["campaigns"][name]
        if (campaign["declared"] != 14 or campaign["executed"] != 14
                or campaign["killed_where_expected"] != 14 or not campaign["originals_intact"]
                or campaign["sources_before"] != campaign["sources_after"]):
            raise RuntimeError(f"invalid {name} falsification")
    if (evidence["off"]["identical_cases"] != 9 or evidence["off"]["total_cases"] != 9
            or evidence["off"]["clean_launches"] != 9
            or evidence["unlimited"]["identical_controls"] != 4):
        raise RuntimeError("identity controls incomplete")
    if houses["stage"] != "houses" or houses["state"] != "passed":
        raise RuntimeError("house campaign not accepted")
    if set(houses["houses"]) != {"o2_closed", "o2_reopen_300"}:
        raise RuntimeError("house cases changed")
    for name, case in houses["houses"].items():
        if (not case["whole"] or case["budget"]["steps"] != 10800
                or not case["budget"]["closes_in_every_step"]
                or case["heat_budget"]["steps"] != 10800
                or case["heat_budget"]["largest_step_gap_kg"] > 1e-9
                or not case["heat_budget"]["no_late_clipping"]):
            raise RuntimeError(f"house acceptance incomplete: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("reference", "product", "guardrails", "global"))
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--houses", required=True, type=Path)
    args = parser.parse_args()
    if not sys.flags.utf8_mode:
        raise RuntimeError("use python -X utf8")
    os.environ.update({"PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8"})
    work = args.work.resolve()
    gate.prepare_environment(work)
    os.environ["SIMUFIRE_GODOT_TEST_APPDATA"] = str(work / "appdata")
    os.chdir(ROOT)
    current = checks.sources()
    evidence = json.loads((ROOT / EVIDENCE).read_text(encoding="utf-8"))
    houses = json.loads(args.houses.read_text(encoding="utf-8"))
    require_prerequisites(evidence, houses, current)
    tracked = gate.source_inventory()
    uids = closure.preserved_files()
    stashes = gate.git("stash", "list", "--format=%H").decode().splitlines()
    record = {"schema": "g3_m3_closure_stage_v1", "stage": args.stage,
              "state": "in_progress", "sources_sha256_raw": current,
              "tracked_sources": tracked, "preserved_uid_sha256": uids, "stashes": stashes}
    before_corpus = closure.corpus()
    before_reference = json.loads((ROOT / REFERENCE).read_text(encoding="utf-8"))
    commands = {
        "reference": ([sys.executable, "scripts/simulation/run_reference_suite_monitored.py"], 7200),
        "product": ([sys.executable, "scripts/check_product.py"], 2400),
        "guardrails": ([sys.executable, "scripts/simulation/validation_guardrails.py", "--json", REFERENCE], 300),
        "global": ([sys.executable, "-m", "pytest", "tests", "-q", "-p", "no:cacheprovider",
                    "--basetemp", str(work / "pytest-global")], 3600),
    }
    closure.emit(work / "result.json", record)
    try:
        command, timeout = commands[args.stage]
        record["execution"] = closure.monitored(args.stage, command, work, timeout)
        if args.stage == "reference":
            after_corpus = closure.corpus()
            changed = sorted(path for path in before_corpus.keys() | after_corpus.keys()
                             if before_corpus.get(path) != after_corpus.get(path))
            after_reference = json.loads((ROOT / REFERENCE).read_text(encoding="utf-8"))
            without_time = lambda value: {key: val for key, val in value.items() if key != "generated_at"}
            if (changed != [REFERENCE] or without_time(before_reference) != without_time(after_reference)
                    or (after_reference["required_count"], after_reference["failed_required_count"],
                        after_reference["known_gap_count"]) != (346, 0, 78)):
                raise RuntimeError(f"reference changed beyond its timestamp: {changed}")
            record["corpus"] = {"raw_before": before_corpus, "raw_after": after_corpus,
                                "files": len(before_corpus), "identical_files": len(before_corpus) - 1,
                                "changed_paths": changed, "only_generated_at_changed": True,
                                "required": 346, "failed_required": 0, "gaps": 78}
        after_tracked = gate.source_inventory()
        if (checks.sources() != current or set(tracked) != set(after_tracked)
                or any(value != after_tracked[path] for path, value in tracked.items() if path != REFERENCE)):
            raise RuntimeError("engine/input sources changed during closure")
        if closure.preserved_files() != uids or gate.git("stash", "list", "--format=%H").decode().splitlines() != stashes:
            raise RuntimeError("unrelated UID files or stashes changed")
        record["state"] = "passed"
    except Exception as exc:
        record["state"] = "failed"
        record["error"] = str(exc)
        raise
    finally:
        closure.emit(work / "result.json", record)
        print(f"M3 {args.stage}: {record['state']}; {work}", flush=True)


if __name__ == "__main__":
    main()
