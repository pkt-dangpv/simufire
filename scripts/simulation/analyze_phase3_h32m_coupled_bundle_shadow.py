#!/usr/bin/env python3
"""Audit H3.2-M coupled-bundle shadow runs against H3.2a artifacts.

The analyzer is read-only. It compares every shared CSV value over the
candidate horizon, requires all added columns to belong to the coupled-bundle
namespace, and audits the non-authoritative bundle ledger exported in the
technical summary.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


PREFIX = "phase3_shadow_coupled_bundle_"
PROVENANCE = "post_minus_pre_minus_legacy_interior"
INVALID_REASON = "circular_legacy_source_reconstruction"


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def _read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def audit_case(baseline_dir: Path, candidate_dir: Path) -> dict[str, Any]:
    base_header, base_all = _read_csv(baseline_dir / "sim_log.csv")
    cand_header, candidate = _read_csv(candidate_dir / "sim_log.csv")
    manifest = _read_json(candidate_dir / "run_manifest.json")
    summary = _read_json(candidate_dir / "summary.json")
    horizon = max((float(row["time_s"]) for row in candidate), default=0.0)
    baseline = [row for row in base_all if float(row["time_s"]) <= horizon + 1e-9]
    shared = [field for field in base_header if field in cand_header]
    added = [field for field in cand_header if field not in base_header]
    first_difference = ""
    difference_count = 0
    if len(baseline) != len(candidate):
        difference_count = 1
        first_difference = f"row_count:{len(baseline)}!={len(candidate)}"
    else:
        for row_index, (base_row, cand_row) in enumerate(zip(baseline, candidate)):
            for field in shared:
                if base_row[field] != cand_row[field]:
                    difference_count += 1
                    if not first_difference:
                        first_difference = (
                            f"row={row_index},field={field},"
                            f"base={base_row[field]},candidate={cand_row[field]}"
                        )
                    break

    bundle = summary.get("phase3_coupled_interior_bundle_shadow", {})
    cumulative = bundle.get("cumulative", {})
    current = bundle.get("current", {})
    completed = (
        manifest.get("status") == "completed"
        and float(manifest.get("sim_time_s", -1.0))
        >= float(manifest.get("duration_s", 0.0)) - 1e-9
    )
    residual_bound = 1e-12
    conservation_ok = (
        abs(float(cumulative.get("max_abs_mass_conservation_residual_kg", 0.0)))
        <= residual_bound
        and abs(float(cumulative.get("max_abs_energy_conservation_residual_kj", 0.0)))
        <= residual_bound
    )
    provenance_ok = (
        bundle.get("source_inputs_independent") is False
        and bundle.get("source_provenance") == PROVENANCE
        and bundle.get("comparison_valid") is False
        and bundle.get("comparison_invalid_reason") == INVALID_REASON
    )
    ledger_ok = all(
        float(cumulative.get(field, 0.0)) == 0.0
        for field in (
            "solver_fallback_count",
            "invalid_zonal_count",
            "duplicate_bundle_count",
            "duplicate_route_count",
            "double_limit_count",
            "counterflow_violation_count",
        )
    )
    accepted_alias_ok = (
        float(current.get("inventory_limited_mass_kg", 0.0))
        == float(current.get("accepted_mass_kg", 0.0))
        and float(current.get("inventory_limited_energy_kj", 0.0))
        == float(current.get("accepted_energy_kj", 0.0))
    )
    passed = all(
        (
            completed,
            difference_count == 0,
            bool(added),
            all(field.startswith(PREFIX) for field in added),
            provenance_ok,
            ledger_ok,
            conservation_ok,
            accepted_alias_ok,
        )
    )
    return {
        "passed": passed,
        "completed": completed,
        "baseline_rows": len(baseline),
        "candidate_rows": len(candidate),
        "shared_columns": len(shared),
        "added_columns": len(added),
        "difference_count": difference_count,
        "first_difference": first_difference,
        "provenance_ok": provenance_ok,
        "ledger_ok": ledger_ok,
        "conservation_ok": conservation_ok,
        "accepted_alias_ok": accepted_alias_ok,
        "steps": float(cumulative.get("step_count", 0.0)),
        "valid_steps": float(cumulative.get("valid_step_count", 0.0)),
        "routes": float(cumulative.get("route_count", 0.0)),
        "parcel_overlap_count": float(cumulative.get("parcel_overlap_count", 0.0)),
        "parcel_overlap_mass_kg": float(cumulative.get("parcel_overlap_mass_kg", 0.0)),
    }


def audit_matrix(baseline_root: Path, candidate_root: Path) -> dict[str, Any]:
    cases: dict[str, Any] = {}
    for candidate_dir in sorted(path for path in candidate_root.iterdir() if path.is_dir()):
        baseline_dir = baseline_root / f"cand_{candidate_dir.name}_on"
        if not baseline_dir.is_dir():
            cases[candidate_dir.name] = {
                "passed": False,
                "first_difference": "baseline_missing",
            }
            continue
        cases[candidate_dir.name] = audit_case(baseline_dir, candidate_dir)
    return {
        "schema_version": "simufire_phase3_h32m_audit_v1",
        "passed": bool(cases) and all(case["passed"] for case in cases.values()),
        "cases": cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline_root", type=Path)
    parser.add_argument("candidate_root", type=Path)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    report = audit_matrix(args.baseline_root, args.candidate_root)
    for name, case in report["cases"].items():
        print(
            f"{name}: {'PASS' if case['passed'] else 'FAIL'} "
            f"rows={case.get('baseline_rows', 0)}/{case.get('candidate_rows', 0)} "
            f"shared={case.get('shared_columns', 0)} "
            f"new={case.get('added_columns', 0)} "
            f"routes={case.get('routes', 0):.0f} "
            f"parcel_overlap={case.get('parcel_overlap_count', 0):.0f}"
        )
        if case.get("first_difference"):
            print(f"  {case['first_difference']}")
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    print("H3.2-M MATRIX PASS" if report["passed"] else "H3.2-M MATRIX FAIL")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
