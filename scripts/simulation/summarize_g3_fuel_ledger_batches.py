#!/usr/bin/env python3
"""Summarise G3-3 ledger batches (before / ledger / off / on) into one JSON.

Read-only over ignored ``runs/`` folders. For every phase and case it records
the SHA-256 of the physics artifacts, monitor health, the G3-1 behaviour
contract (C1-C9, from the legacy v2 ledger) and, when present, the G3-3 v3
ledger summary with numerical closure and the explicit_owned contract.

    python scripts/simulation/summarize_g3_fuel_ledger_batches.py \
        --before runs/... --ledger runs/... [--off runs/... --on runs/...] --out docs/...json
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation.analyze_g3_fuel_ledger import (  # noqa: E402
    closure_failures, explicit_owned_failures, load, summarize,
)
from scripts.simulation.analyze_g3_fuel_ownership import analyze, contract_violations  # noqa: E402
from scripts.simulation.run_g3_fuel_ownership_matrix import declared_inventory  # noqa: E402


PHYSICS_ARTIFACTS = ("sim_log.csv", "events.json", "co_inventory_trace.jsonl",
                     "fuel_source_ledger.jsonl", "fuel_object_state_snapshot.json")
LEDGER_FIELDS = (
    "steps", "mode", "switch_on", "consumed_MJ", "released_MJ", "solid_released_MJ",
    "pool_released_MJ", "solid_release_without_consumption_MJ", "owners_MJ",
    "allocated_MJ", "discarded_MJ", "unowned_MJ", "room_load_MJ",
    "allocated_to_inactive_MJ", "max_step_fire_residual_MJ",
    "max_step_partition_residual_MJ", "max_step_negative_object_residual_MJ",
    "cumulative_object_closure_MJ", "cumulative_fire_closure_MJ",
    "max_hrr_requested_kw", "max_hrr_applied_kw", "max_solid_hrr_over_active_cap_kw",
    "objects_over_own_cap", "objects_initial_MJ", "objects_final_MJ",
)


def _sha(path: Path) -> str | None:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def summarize_phase(run_root: Path) -> dict:
    report = json.loads((run_root / "report.json").read_text(encoding="utf-8"))
    cases, results, declared = {}, {}, {}
    for case in report["cases"]:
        name = case["name"]
        out = run_root / name
        health = json.loads((out / "monitor.health.json").read_text(encoding="utf-8"))
        results[name] = analyze(out / "fuel_source_ledger.jsonl")
        declared[name] = declared_inventory(json.loads((out / "scenario.json").read_text(encoding="utf-8")))
        entry = {
            "scenario_sha256": case["scenario_sha256"],
            "artifact_sha256": {name_: _sha(out / name_) for name_ in PHYSICS_ARTIFACTS},
            "health": {key: health.get(key) for key in (
                "timed_out", "error_dialogs", "residual_godot_processes", "process_quiescent")},
            "csv_last_time_s": case["metrics"]["last_time_s"],
            "csv_max_hrr_kw": case["metrics"]["max_hrr_kw"],
            "csv_final_co_generated_kg_total": case["metrics"]["final_co_generated_kg_total"],
            "csv_final_smoke_generated_kg_total": case["metrics"]["final_smoke_generated_kg_total"],
            "csv_final_fuel_consumed_MJ_total": case["metrics"]["final_fuel_consumed_MJ_total"],
        }
        ledger_path = out / "g3_fuel_ledger_v3.jsonl"
        if ledger_path.exists():
            summary = summarize(load(ledger_path))
            entry["ledger_v3"] = {key: summary.get(key) for key in LEDGER_FIELDS}
            entry["ledger_v3"]["species"] = summary.get("species")
            entry["ledger_closure_failures"] = closure_failures(summary) if summary["steps"] else []
            entry["explicit_owned_failures"] = explicit_owned_failures(summary) \
                if summary["steps"] and "explicit_owned" in summary["mode"] else None
            entry["ownership_contract_on_ledger"] = explicit_owned_failures(summary) \
                if summary["steps"] and summary.get("owners_MJ") else []
        cases[name] = entry
    # C6 on this batch's names: the cold chair burns nothing, so any change in
    # generated CO/smoke versus the single sofa comes from yield weighting.
    chemistry = None
    single, cold = cases.get("single_object"), cases.get("sofa_plus_cold_chair")
    if single and cold and single.get("ledger_v3", {}).get("consumed_MJ"):
        ls, lc = single["ledger_v3"], cold["ledger_v3"]
        chemistry = {
            "consumed_ratio_cold_over_single": lc["consumed_MJ"] / ls["consumed_MJ"],
            "co_ratio_cold_over_single": lc["species"]["co_kg"]["total"] / ls["species"]["co_kg"]["total"],
            "smoke_ratio_cold_over_single": lc["species"]["smoke_kg"]["total"] / ls["species"]["smoke_kg"]["total"],
        }
    return {
        "run": run_root.name,
        "cases": cases,
        "behaviour_contract_C1_C9": contract_violations(results, declared),
        "c6_cold_chair_chemistry": chemistry,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for phase in ("before", "ledger", "off", "on"):
        parser.add_argument(f"--{phase}", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    phases = {phase: summarize_phase(getattr(args, phase))
              for phase in ("before", "ledger", "off", "on") if getattr(args, phase)}
    identity = {}
    base = phases.get("before")
    for phase, data in phases.items():
        if phase in ("before", "on") or base is None:
            continue
        identity[f"before_vs_{phase}"] = {
            case: all(data["cases"][case]["artifact_sha256"][a] == base["cases"][case]["artifact_sha256"][a]
                      for a in PHYSICS_ARTIFACTS)
            for case in base["cases"]
        }
    payload = {"schema": "g3_fuel_ledger_batches_v1", "phases": phases, "byte_identity": identity}
    args.out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(identity, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
