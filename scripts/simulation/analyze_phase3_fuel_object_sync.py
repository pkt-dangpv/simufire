#!/usr/bin/env python3
"""Audit F3.3v2c per-object fuel synchronization."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


PREFIX = "phase3_shadow_fuel_object_sync_"
FIELDS = [
    "active_flag", "supported_flag", "rejection_mask", "object_count",
    "identity_signature", "eligible_count", "pre_fuel_MJ",
    "proposed_fuel_MJ", "committed_fuel_MJ", "requested_debit_MJ",
    "allocated_debit_MJ", "committed_debit_MJ",
    "allocation_residual_MJ", "atomic_residual_MJ",
    "aggregate_residual_MJ", "exhausted_count", "minimum_remaining_MJ",
    "live_fuel_MJ", "live_delta_MJ", "seed_residual_MJ",
]
RESIDUALS = [
    "allocation_residual_MJ", "atomic_residual_MJ",
    "aggregate_residual_MJ", "seed_residual_MJ",
]
LEGACY_PYROLYSIS_DEBIT_FIELD = "fuel_consumed_MJ_step"


def _read(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def analyze(
    baseline_path: Path,
    candidate_path: Path,
    tolerance: float = 1.0e-7,
) -> dict[str, Any]:
    baseline_fields, baseline = _read(baseline_path)
    candidate_fields, candidate = _read(candidate_path)
    missing = [PREFIX + field for field in FIELDS if PREFIX + field not in candidate_fields]
    legacy_fields = [
        field for field in baseline_fields if not field.startswith("phase3_shadow_")
    ]
    row_match = len(baseline) == len(candidate)
    legacy_diffs = 0
    if row_match:
        legacy_diffs = sum(
            left.get(field, "") != right.get(field, "")
            for left, right in zip(baseline, candidate, strict=True)
            for field in legacy_fields
        )
    active = [
        row for row in candidate
        if float(row.get(PREFIX + "active_flag", 0.0) or 0.0) > 0.5
    ]
    signatures = {
        float(row[PREFIX + "identity_signature"]) for row in active
    } if active and not missing else set()
    max_residuals = {
        field: max(
            (abs(float(row[PREFIX + field])) for row in active), default=0.0
        )
        for field in RESIDUALS
        if PREFIX + field in candidate_fields
    }
    max_live_delta = max(
        (abs(float(row[PREFIX + "live_delta_MJ"])) for row in active),
        default=0.0,
    ) if PREFIX + "live_delta_MJ" in candidate_fields else float("inf")
    source_fields_available = (
        LEGACY_PYROLYSIS_DEBIT_FIELD in candidate_fields
        and PREFIX + "requested_debit_MJ" in candidate_fields
    )
    legacy_minus_canonical_debits = [
        float(row[LEGACY_PYROLYSIS_DEBIT_FIELD])
        - float(row[PREFIX + "requested_debit_MJ"])
        for row in active
    ] if source_fields_available else []
    max_abs_source_debit_delta = max(
        (abs(value) for value in legacy_minus_canonical_debits),
        default=0.0,
    )
    source_mismatch_rows = sum(
        abs(value) > tolerance for value in legacy_minus_canonical_debits
    )
    eligible_counts = {
        float(row[PREFIX + "eligible_count"]) for row in active
    } if active and not missing else set()
    shadow_closed = (
        not missing
        and row_match
        and legacy_diffs == 0
        and bool(active)
        and len(signatures) == 1
        and all(float(row[PREFIX + "supported_flag"]) > 0.5 for row in active)
        and all(float(row[PREFIX + "rejection_mask"]) == 0.0 for row in active)
        and all(value <= tolerance for value in max_residuals.values())
    )
    runtime_ready = shadow_closed and max_live_delta <= tolerance
    allocator_exonerated = (
        shadow_closed
        and bool(eligible_counts)
        and max(eligible_counts) <= 1.0
        and max_live_delta > tolerance
        and source_mismatch_rows > 0
    )
    fuel_semantics_split_required = (
        shadow_closed
        and max_live_delta > tolerance
        and source_mismatch_rows > 0
    )
    if runtime_ready:
        diagnosis = "correspondence_closed"
    elif allocator_exonerated:
        diagnosis = "aggregate_source_term_mismatch"
    elif not source_fields_available:
        diagnosis = "insufficient_source_fields"
    elif source_mismatch_rows > 0:
        diagnosis = "aggregate_source_term_mismatch"
    else:
        diagnosis = "per_object_correspondence_unresolved"
    return {
        "pass": shadow_closed,
        "shadow_closed": shadow_closed,
        "runtime_authority_ready": runtime_ready,
        "group_c_retirement_ready": False,
        "diagnosis": diagnosis,
        "per_object_allocator_exonerated": allocator_exonerated,
        "fuel_semantics_split_required": fuel_semantics_split_required,
        "baseline_rows": len(baseline),
        "candidate_rows": len(candidate),
        "legacy_field_count": len(legacy_fields),
        "legacy_differences": legacy_diffs,
        "active_rows": len(active),
        "identity_signature_count": len(signatures),
        "object_count_values": sorted({
            float(row[PREFIX + "object_count"]) for row in active
        }) if active and not missing else [],
        "eligible_count_values": sorted(eligible_counts),
        "missing_fields": missing,
        "max_abs_residuals": max_residuals,
        "max_abs_live_delta_MJ": max_live_delta,
        "source_fields_available": source_fields_available,
        "source_mismatch_rows": source_mismatch_rows,
        "max_abs_legacy_minus_canonical_debit_MJ": (
            max_abs_source_debit_delta
        ),
        "max_legacy_minus_canonical_debit_MJ": max(
            legacy_minus_canonical_debits, default=0.0
        ),
        "tolerance": tolerance,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--tolerance", type=float, default=1.0e-7)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    result = analyze(args.baseline, args.candidate, args.tolerance)
    text = json.dumps(result, indent=2, sort_keys=True)
    print(text)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(text + "\n", encoding="utf-8")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
