"""M2-T diagnosis and scope gate. Never modifies sim/ or baseline reports.

Launches the declared controls and the two unmodified house cases sequentially
through existing monitors. A low-memory/preexisting-process refusal is a failure
of execution, never evidence about physics. --plan-only launches nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import math
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import g3_m2t_transport_contract as model  # noqa: E402
from scripts.simulation import run_g3_o2_venting_house as house  # noqa: E402

BASE = "920affb7"
FIXTURE = "tests/fixtures/g3_o2_transport_gate.gd"
PREFIX = "G3_O2_TRANSPORT_GATE "
SCHEMA = "g3_o2_transport_scope_gate_v1"


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def normalized_sha(data: bytes) -> str:
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def source_inventory() -> dict:
    entries = []
    for entry in git("ls-tree", "-rz", BASE, "--", "sim/", "tools/run_scenario_headless.gd").split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        _mode, kind, oid = metadata.split()
        if kind != b"blob":
            raise RuntimeError("source is not a blob")
        entries.append((path.decode("utf-8"), oid))
    # One Git process, not one process per file. Preserve the raw blob lengths.
    process = subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT,
                             input=b"\n".join(oid for _, oid in entries) + b"\n",
                             capture_output=True, check=True)
    position = 0
    sources = {}
    for path, oid in entries:
        end = process.stdout.index(b"\n", position)
        actual_oid, kind, size = process.stdout[position:end].split()
        if actual_oid != oid or kind != b"blob":
            raise RuntimeError("unexpected batch blob")
        position = end + 1
        blob = process.stdout[position:position + int(size)]
        position += int(size) + 1
        sha = normalized_sha((ROOT / path).read_bytes())
        sources[path] = {"normalized_sha256": sha, "same_as_base": sha == normalized_sha(blob)}
    if set(sources) != set(git("ls-files", "sim/", "tools/run_scenario_headless.gd").decode().splitlines()):
        raise RuntimeError("tracked source set changed")
    return sources


def analyze_trace(folder: Path) -> dict:
    """Bounded-memory reanalysis of a published trace, NOT a fresh launch."""
    path = folder / "o2_inventory_trace.jsonl"
    rooms: dict = {}
    steps = 0
    max_balance = 0.0
    last_time = 0.0
    trace_sha = hashlib.sha256()
    conversion = 1.2 * 0.031998 / 0.0289647
    with path.open("rb") as handle:
        for raw in handle:
            trace_sha.update(raw)
            row = json.loads(raw)
            if row["failure"] or row["state"] == "rejected":
                raise RuntimeError("published trace contains a refused step")
            steps += 1
            last_time = float(row["time_s"])
            before = sum(float(value) for value in row["before"]["inventory_kg"].values()) + float(row["before"]["transit_kg"])
            after = sum(float(value["inventory_kg"]) for value in row["rooms"].values()) + float(row["transit_kg"])
            exterior = sum(float(op["in_kg"]) - float(op["out_kg"]) for op in row["operations"] if op["kind"] == "outside")
            consumed = sum(float(op["applied_kg"]) for op in row["operations"] if op["kind"] == "consume")
            max_balance = max(max_balance, abs(after - before - exterior + consumed))
            for key, state in row["rooms"].items():
                scale = float(state["volume_m3"]) * conversion
                fraction = float(state["inventory_kg"]) / scale
                effective = (float(state["inventory_kg"]) + float(row.get("transit_to", {}).get(key, 0.0))) / scale
                item = rooms.setdefault(key, {"max_x": 0.0, "max_effective_x": 0.0, "rich_steps": 0, "first_rich": None})
                item["max_x"] = max(item["max_x"], fraction)
                item["max_effective_x"] = max(item["max_effective_x"], effective)
                if fraction > 0.209 + 1.0e-12:
                    item["rich_steps"] += 1
                    if item["first_rich"] is None:
                        item["first_rich"] = {"t": last_time, "x": fraction,
                                              "signed_transit_to_room_kg": row.get("transit_to", {}).get(key, 0.0),
                                              "operations": row["operations"]}
    if steps != 10800 or not math.isclose(last_time, 900.0, abs_tol=1.0e-7):
        raise RuntimeError("published house trace is not the complete 900 s case")
    if max_balance > 1.0e-9:
        raise RuntimeError("published trace does not conserve oxygen")
    return {"evidence_kind": "published trace reanalyzed; not rerun", "folder": folder.relative_to(ROOT).as_posix(),
            "trace_sha256": trace_sha.hexdigest(), "steps": steps, "last_time_s": last_time,
            "max_building_balance_kg": max_balance, "rooms": rooms}


def prepare_environment(work: Path) -> None:
    if work.is_relative_to(ROOT):
        raise ValueError("work must be outside the checkout")
    work.mkdir(parents=True, exist_ok=True)
    for name in ("APPDATA", "TEMP", "TMP"):
        path = work / name.lower()
        path.mkdir(exist_ok=True)
        os.environ[name] = str(path)
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    os.environ[godot_monitored_launch.HEALTH_LOG_ENV] = str(work / "godot.health.jsonl")
    os.environ["G3_O2_M3_DIAGNOSIS_OUT"] = str(work)
    os.environ["SIMUFIRE_GODOT_RUNTIME_ROOT"] = str(work / "runtime")


def controls(work: Path) -> dict:
    executable = run_scenario._find_godot()
    if executable is None:
        raise RuntimeError("Godot unavailable")
    result = godot_monitored_launch.run(
        [executable, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
        timeout_s=1200, environment=os.environ.copy(),
    )
    (work / "controls.stdout.log").write_text(result.stdout, encoding="utf-8")
    (work / "controls.stderr.log").write_text(result.stderr, encoding="utf-8")
    if not result.launched or result.returncode != 0 or result.faults or result.preexisting:
        raise RuntimeError(f"unhealthy controls: rc={result.returncode}, faults={result.faults}, preexisting={result.preexisting}")
    text = result.stdout + result.stderr
    if "SCRIPT ERROR" in text or "Parse Error" in text:
        raise RuntimeError("controls contain a script error")
    lines = [line for line in result.stdout.splitlines() if line.startswith(PREFIX)]
    if len(lines) != 1:
        raise RuntimeError("controls did not emit exactly one terminal record")
    return {"payload": json.loads(lines[0][len(PREFIX):]), "returncode": result.returncode,
            "health": result.health, "script_errors": 0}


def verified_health(work: Path) -> list[dict]:
    records = [json.loads(line) for line in (work / "godot.health.jsonl").read_text(encoding="utf-8").splitlines()]
    if not records:
        raise RuntimeError("no monitored launch health")
    for record in records:
        if not record["launched"] or record["returncode"] != 0 or record["faults"] or record["preexisting"]:
            raise RuntimeError("a refused or unhealthy launch cannot close this gate")
        health = record["health"]
        if health["cleanup_terminated_pids"]:
            raise RuntimeError("monitor had to terminate processes")
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--offline-only", action="store_true", help="reanalyse published evidence, launch nothing")
    args = parser.parse_args()
    if args.plan_only:
        print(json.dumps({"base": BASE, "fixture": FIXTURE, "houses": list(house.CASES),
                          "minimum_available_gib": 6, "sim_changed": False}, indent=2))
        return 0
    if args.offline_only:
        if args.out is None:
            parser.error("--out required for --offline-only")
        sources = source_inventory()
        if not all(item["same_as_base"] for item in sources.values()):
            raise RuntimeError("engine changed; published evidence cannot describe it")
        published_path = ROOT / "docs/validation/G3_O2_M3_CONTRACT_DIAGNOSIS_2026-10-11.json"
        published = json.loads(published_path.read_text(encoding="utf-8"))
        houses = {name: analyze_trace(ROOT / published["house"][name]["folder"]) for name in house.CASES}
        record = {
            "schema": SCHEMA, "base": BASE, "implemented": False,
            "decision": "NO-GO for the direct replacements evaluated; a delay/carrier-base decision is required",
            "sources": sources, "sources_unchanged": True,
            "houses": houses, "offline_counterexamples": model.json_values(model.counterexamples()),
            "reused_debt_control": {"record": published_path.relative_to(ROOT).as_posix(),
                                  "normalized_sha256": normalized_sha(published_path.read_bytes()),
                                  "case": published["controls"]["obligation with the door closed"]},
            "fresh_godot_launches": 0, "launch_health": [],
        }
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"offline record: {args.out}; {len(sources)} sources match {BASE}; Godot launches: 0")
        return 0
    if args.work is None or args.out is None:
        parser.error("--work and --out required unless --plan-only")
    work = args.work.resolve()
    prepare_environment(work)
    before = source_inventory()
    if not all(item["same_as_base"] for item in before.values()):
        raise RuntimeError("engine differs from the base; cannot reuse the stated contract")
    # Fail before a launch, rather than interpreting a launch refusal as physics.
    preexisting = godot_monitored_launch.preexisting_godot_state()
    fault = godot_monitored_launch.memory_gate_fault()
    if preexisting or fault:
        raise RuntimeError(f"preflight refuses execution: {preexisting or fault}")
    measured = controls(work)
    cases = {}
    for name in house.CASES:
        # Existing safe baseline also checks memory and native/process health.
        folder = house.launch(name, "on")
        cases[name] = house.evaluate(folder, None)
        if not cases[name]["whole"] or not cases[name]["budget"]["closes_in_every_step"]:
            raise RuntimeError(f"{name} not whole/conservative")
    after = source_inventory()
    if before != after:
        raise RuntimeError("measured sources changed during diagnosis")
    health = verified_health(work)
    record = {
        "schema": SCHEMA, "base": BASE, "implemented": False,
        "decision": "NO-GO within the current scope; preserve delay or carrier-base authority needs a new decision",
        "sources": before, "sources_unchanged": True,
        "controls": measured, "houses": cases,
        "offline_counterexamples": model.json_values(model.counterexamples()),
        "launch_health": health,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"record: {args.out}; monitored launches: {len(health)}; sim unchanged")
    for name, case in cases.items():
        print(name, case["budget"]["steps"], case["last_time_s"], "s; no correction implemented")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
