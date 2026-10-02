#!/usr/bin/env python3
"""Mutation audit of the explicit_objects fix (G3): each mutant must be caught.

Every mutant re-introduces one original defect in the ON path of
``sim/fire/CombustionSystem.gd`` by exact text replacement, runs the case
that exposes it (switch ON, ledger v3), checks the expected clause fails,
and restores the original bytes (SHA-256 verified) before the next mutant,
also after an error. One Godot at a time through the monitored runner.

    python scripts/simulation/run_g3_fuel_ownership_mutations.py
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402
from scripts.simulation.analyze_g3_fuel_ledger import (  # noqa: E402
    closure_failures, explicit_owned_failures, load, summarize,
)


TARGET = ROOT / "sim/fire/CombustionSystem.gd"
MUTANTS = {
    "M1_inactive_object_counted": {
        "old": "\treturn room.flashover_triggered \\\n\t\t\tor bool(obj.is_primary_ignition_source) \\\n\t\t\tor bool(obj.autoignite_ready) \\",
        "new": "\treturn true or room.flashover_triggered \\\n\t\t\tor bool(obj.is_primary_ignition_source) \\\n\t\t\tor bool(obj.autoignite_ready) \\",
        "case": "sofa_plus_cold_chair",
        # Independent oracle: the chair cannot ignite, so it must keep 3 MJ.
        "detects": lambda s: s["objects_final_MJ"]["g3_cold_chair"] < 3.0 - 1.0e-9,
        "clause": "cold chair keeps its 3.0 MJ (C7)",
    },
    "M2_no_object_power_cap": {
        "old": "\t\t\tvar obj_cap_kw: float = maxf(0.0, float(obj.max_hrr_kw))",
        "new": "\t\t\tvar obj_cap_kw: float = 1000.0",
        "case": "low_power_object",
        "detects": lambda s: "O4_power_cap" in explicit_owned_failures(s),
        "clause": "O4_power_cap",
    },
    "M3_heat_release_not_bounded_by_pyrolysis": {
        "old": "actual_solid_burn_kw = minf(actual_solid_burn_kw, minf(solid_pyrolysis_kw, g3_power_cap_kw))",
        "new": "actual_solid_burn_kw = minf(actual_solid_burn_kw, g3_power_cap_kw)",
        "case": "single_object",
        "detects": lambda s: "O5_heat_without_fuel_owner" in explicit_owned_failures(s),
        "clause": "O5_heat_without_fuel_owner",
    },
    "M4_tiny_demand_not_debited": {
        "old": "\tvar burns: Array = _g3_waterfill(solid_fuel_demand_MJ, weights, caps_MJ)",
        "new": "\tvar burns: Array = _g3_waterfill(solid_fuel_demand_MJ if solid_fuel_demand_MJ > 0.000001 else 0.0, weights, caps_MJ)",
        "case": "single_object",
        "detects": lambda s: "O1_unowned_MJ" in explicit_owned_failures(s),
        "clause": "O1_unowned_MJ",
    },
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    original = TARGET.read_bytes()
    original_sha = _sha(original)
    scenarios = batch.scenarios_for("on")
    results = {}
    try:
        for mutant_id, spec in MUTANTS.items():
            text = original.decode("utf-8")
            if text.count(spec["old"]) != 1:
                raise RuntimeError(f"{mutant_id}: mutation anchor not found exactly once")
            TARGET.write_bytes(text.replace(spec["old"], spec["new"]).encode("utf-8"))
            try:
                code = baseline.run(
                    case_scenarios={spec["case"]: scenarios[spec["case"]]},
                    output_label=f"g3_mutant_{mutant_id}",
                    report_schema="g3_fuel_ownership_mutant_v1",
                    extra_runner_args=[batch.LEDGER_ARG],
                )
            finally:
                TARGET.write_bytes(original)
                if _sha(TARGET.read_bytes()) != original_sha:
                    raise RuntimeError(f"{mutant_id}: restore failed")
            run_root = sorted((ROOT / "runs").glob(f"g3_mutant_{mutant_id}_*"))[-1]
            summary = summarize(load(run_root / spec["case"] / "g3_fuel_ledger_v3.jsonl"))
            results[mutant_id] = {
                "run": run_root.name,
                "case": spec["case"],
                "runner_exit": code,
                "clause": spec["clause"],
                "detected": bool(spec["detects"](summary)),
                "explicit_owned_failures": explicit_owned_failures(summary),
                "closure_failures": closure_failures(summary),
            }
            print(json.dumps({mutant_id: results[mutant_id]}), flush=True)
    finally:
        if _sha(TARGET.read_bytes()) != original_sha:
            TARGET.write_bytes(original)
    print(json.dumps({"restored_sha256": _sha(TARGET.read_bytes()), "original_sha256": original_sha,
                      "all_detected": all(r["detected"] for r in results.values())}))
    return 0 if results and all(r["detected"] for r in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
