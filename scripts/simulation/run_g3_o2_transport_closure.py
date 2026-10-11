"""M2-T final verification, sequentially and with external runtime directories.

Never commits, pushes, lowers the memory gate, or starts unmonitored Godot.
Writes a partial record before each expensive stage so interruptions are honest.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch  # noqa: E402
from scripts.simulation import run_g3_o2_transport_gate as gate  # noqa: E402
from tools import mutation_audit  # noqa: E402

REFERENCE = "sim/validation/reports/reference_checks.json"


def corpus() -> dict:
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted((ROOT / "sim/validation").rglob("*"))
            if path.is_file() and path.suffix in (".json", ".csv", ".md")}


def emit(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")


def preserved_files() -> dict:
    paths = gate.git("ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in paths if path.endswith(".gd.uid")}


def monitored(label: str, command: list[str], work: Path, timeout: int) -> dict:
    fault = godot_monitored_launch.memory_gate_fault()
    existing = godot_monitored_launch.preexisting_godot_state()
    if fault or existing:
        raise RuntimeError(f"{label} preflight: {fault or existing}")
    before = godot_monitored_launch._available_gib()
    start = time.monotonic()
    result, health = mutation_audit._run_monitored(command, timeout, os.environ.copy())
    # Preserve health even if output capture/decoding fails. No invented stdout.
    emit(work / f"{label}.health.json", health)
    if not isinstance(result.stdout, str) or not isinstance(result.stderr, str):
        raise RuntimeError(f"{label}: output capture failed; runtime health preserved separately")
    (work / f"{label}.stdout.log").write_text(result.stdout, encoding="utf-8")
    (work / f"{label}.stderr.log").write_text(result.stderr, encoding="utf-8")
    # Negative fixtures may intentionally exit 1; native exceptions are never valid.
    native = [item for item in health["observed_godot_processes"]
              if item.get("exit_code") is not None and
              (int(item["exit_code"]) < 0 or int(item["exit_code"]) >= 0x80000000)]
    errors = godot_monitored_launch.infrastructure_faults(health)
    if health.get("cleanup_terminated_pids") != []:
        errors.append(f"cleanup terminated processes: {health.get('cleanup_terminated_pids')}")
    if native or result.returncode != 0:
        errors.append(f"exit {result.returncode}, native children {native}")
    item = {"command": command, "returncode": result.returncode, "health": health,
            "available_gib_before": before, "available_gib_after": godot_monitored_launch._available_gib(),
            "wall_s": round(time.monotonic() - start, 2), "errors": errors,
            "stdout_sha256": hashlib.sha256(result.stdout.encode()).hexdigest(),
            "stderr_sha256": hashlib.sha256(result.stderr.encode()).hexdigest(),
            "terminal_output": result.stdout[-4000:]}
    if errors:
        emit(work / f"{label}.failure.json", item)
        raise RuntimeError(f"{label}: {errors}; {result.stdout[-2000:]}; {result.stderr[-2000:]}")
    print(f"{label}: exit 0, healthy; {item['wall_s']} s", flush=True)
    return item


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--mutations", type=Path, required=True)
    parser.add_argument("--reuse-reference", type=Path,
                        help="completed inner reference suite after an outer output-capture failure")
    parser.add_argument("--previous", type=Path, help="original failed closure record; required for reuse")
    args = parser.parse_args()
    if os.name == "nt" and not sys.flags.utf8_mode:
        raise RuntimeError("start this wrapper with python -X utf8; locale decoding is not safe")
    os.environ["PYTHONUTF8"] = "1"
    os.environ["PYTHONIOENCODING"] = "utf-8"
    work = args.work.resolve()
    gate.prepare_environment(work)
    os.environ["SIMUFIRE_GODOT_TEST_APPDATA"] = str(work / "appdata")
    os.chdir(ROOT)
    sources = gate.source_inventory()
    uids = preserved_files()
    stashes = gate.git("stash", "list", "--format=%H").decode().splitlines()
    mutations = json.loads(args.mutations.read_text(encoding="utf-8"))
    if (mutations["executed"] != 12 or mutations["killed_where_expected"] != 12 or
            mutations["survivors"] or mutations["invalid"] or not mutations["originals_intact"] or
            mutations["sha256_before"] != mutations["sha256_after"]):
        raise RuntimeError("mutation evidence not accepted")
    for path, expected in mutations["sha256_after"].items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != expected:
            raise RuntimeError(f"mutation evidence no longer binds current bytes: {path}")
    mutations["health"] = {}
    for result in mutations["results"]:
        folder = args.mutations.parent / result["name"]
        health = json.loads((folder / "health.json").read_text(encoding="utf-8"))
        faults = godot_monitored_launch.infrastructure_faults(health)
        if faults or health.get("cleanup_terminated_pids") != []:
            raise RuntimeError(f"mutant health not accepted: {result['name']}: {faults}")
        mutations["health"][result["name"]] = health
    before_corpus = corpus()
    before_reference = json.loads((ROOT / REFERENCE).read_text(encoding="utf-8"))
    record = {"schema": "g3_o2_transport_m2t_closure_v1", "base": gate.BASE,
              "state": "in_progress", "sources": sources, "mutations": mutations, "stages": {},
              "preserved_uid_sha256": uids, "stashes": stashes}
    record["raw_corpus_before_sha256"] = before_corpus
    stages = (
        ("reference", [sys.executable, "scripts/simulation/run_reference_suite_monitored.py"], 7200),
        ("product", [sys.executable, "scripts/check_product.py"], 2400),
        ("guardrails", [sys.executable, "scripts/simulation/validation_guardrails.py",
                        "--json", REFERENCE], 300),
        ("global", [sys.executable, "-m", "pytest", "tests", "-q", "-p", "no:cacheprovider",
                    "--basetemp", str(work / "pytest-global")], 3600),
    )
    if args.reuse_reference:
        if not args.previous:
            raise RuntimeError("reference reuse needs the original failed record")
        previous = json.loads(args.previous.read_text(encoding="utf-8"))
        emit(work / "previous_capture_failure.json", previous)
        original_sources = previous["sources"]
        if set(sources) != set(original_sources) or any(
                value != original_sources[path] for path, value in sources.items() if path != REFERENCE):
            raise RuntimeError("measured engine/input bytes changed since the completed reference")
        suite = json.loads((args.reuse_reference / "suite_log.json").read_text(encoding="utf-8"))
        runner_path = "scripts/simulation/run_reference_suite_monitored.py"
        if (ROOT / runner_path).read_bytes().replace(b"\r\n", b"\n") != gate.git(
                "show", f"{gate.BASE}:{runner_path}").replace(b"\r\n", b"\n"):
            raise RuntimeError("the measured strict reference runner is no longer the published one")
        expected_cases = subprocess.check_output(
            [sys.executable, "scripts/simulation/validate_reference_cases.py", "--list-runtime-cases"],
            cwd=ROOT, text=True).split()
        if [item["case"] for item in suite["cases"]] != expected_cases or any(
                item["errors"] or item["exit"] not in (0, 2) or not item["fresh_report"]
                for item in suite["cases"]):
            raise RuntimeError("the inner reference suite is incomplete or unhealthy")
        old_reference = json.loads(gate.git("show", f"{gate.BASE}:{REFERENCE}"))
        strip_time = lambda value: {k: v for k, v in value.items() if k != "generated_at"}
        if strip_time(old_reference) != strip_time(before_reference):
            raise RuntimeError("reference changed beyond generated_at")
        changed = [path for path in before_corpus
                   if original_sources[path]["normalized_sha256"] != sources[path]["normalized_sha256"]]
        if changed != [REFERENCE]:
            raise RuntimeError(f"reference corpus content changed: {changed}")
        record["stages"]["reference"] = {
            "reused": True, "cases": suite["cases"],
            "health_origin": "inner per-case strict monitors; outer capture failed before saving health",
            "outer_capture_failure": previous["error"],
            "suite_log_sha256": hashlib.sha256((args.reuse_reference / "suite_log.json").read_bytes()).hexdigest(),
            "runner_sha256_lf": hashlib.sha256((ROOT / "scripts/simulation/run_reference_suite_monitored.py")
                                               .read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
            "guardrails_output": (args.reuse_reference / "guardrails.stdout.log").read_text(encoding="utf-8"),
        }
        record["corpus"] = {"files": len(before_corpus), "identical_files": len(before_corpus) - 1,
                            "changed_paths": changed, "only_generated_at_changed": True,
                            "comparison": "normalized LF hashes from the pre-run source inventory; raw pre-run manifest was not saved",
                            "generated_at_before": old_reference["generated_at"],
                            "generated_at_after": before_reference["generated_at"],
                            "required": before_reference["required_count"],
                            "failed_required": before_reference["failed_required_count"],
                            "gaps": before_reference["known_gap_count"]}
        if (record["corpus"]["required"], record["corpus"]["failed_required"], record["corpus"]["gaps"]) != (346, 0, 78):
            raise RuntimeError("reused reference counts changed")
        stages = stages[1:]
    emit(args.out, record)
    try:
        for label, command, timeout in stages:
            record["running_stage"] = label
            emit(args.out, record)
            record["stages"][label] = monitored(label, command, work, timeout)
            if label == "reference":
                after_corpus = corpus()
                changed = [path for path in before_corpus.keys() | after_corpus.keys()
                           if before_corpus.get(path) != after_corpus.get(path)]
                after_reference = json.loads((ROOT / REFERENCE).read_text(encoding="utf-8"))
                without_time = lambda value: {k: v for k, v in value.items() if k != "generated_at"}
                if changed != [REFERENCE] or without_time(before_reference) != without_time(after_reference):
                    raise RuntimeError(f"reference corpus changed beyond timestamp: {changed}")
                if (after_reference["required_count"], after_reference["failed_required_count"],
                        after_reference["known_gap_count"]) != (346, 0, 78):
                    raise RuntimeError("required/gap counts changed")
                record["corpus"] = {"files": len(before_corpus), "identical_files": len(before_corpus) - 1,
                                    "changed_paths": changed, "only_generated_at_changed": True,
                                    "generated_at_before": before_reference["generated_at"],
                                    "generated_at_after": after_reference["generated_at"],
                                    "required": 346, "failed_required": 0, "gaps": 78}
            after_sources = gate.source_inventory()
            if set(after_sources) != set(sources) or any(
                    value != after_sources[path] for path, value in sources.items() if path != REFERENCE):
                raise RuntimeError("engine source changed during final verification")
            if preserved_files() != uids or gate.git("stash", "list", "--format=%H").decode().splitlines() != stashes:
                raise RuntimeError("unrelated UIDs or stashes changed")
            emit(args.out, record)
        if not re.search(r"\d+ passed", record["stages"]["global"]["terminal_output"]):
            raise RuntimeError("global terminal count absent")
        record["state"] = "passed"
        record.pop("running_stage", None)
        emit(args.out, record)
        return 0
    except Exception as exc:
        record["state"] = "failed"
        record["error"] = str(exc)
        emit(args.out, record)
        raise


if __name__ == "__main__":
    raise SystemExit(main())
