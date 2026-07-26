#!/usr/bin/env python3
"""Audit F3.3v2b product routing against an F3.3v2 shadow baseline."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


ROUTING_FIELDS = [
    "phase3_shadow_fire_products_routing_active_flag",
    "phase3_shadow_fire_products_routing_atomic_fraction",
    "phase3_shadow_fire_products_routing_effective_fraction",
    "phase3_shadow_fire_products_routing_committed_fuel_MJ",
    "phase3_shadow_fire_products_routing_fuel_residual_MJ",
    "phase3_shadow_fire_products_routing_o2_residual_kg",
    "phase3_shadow_fire_products_routing_species_residual_kg",
    "phase3_shadow_fire_products_routing_convective_residual_kj",
    "phase3_shadow_fire_products_routing_radiative_residual_kj",
    "phase3_shadow_fire_products_routing_total_energy_residual_kj",
    "phase3_shadow_fire_products_routing_coupled_plume_qc_kw",
    "phase3_shadow_fire_products_routing_plume_qc_residual_kw",
]


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def _float(row: dict[str, str], field: str) -> float:
    try:
        return float(row.get(field, 0.0) or 0.0)
    except ValueError:
        return float("nan")


def analyze(
    baseline_path: Path,
    routed_path: Path,
    tolerance: float = 1.0e-7,
) -> dict[str, Any]:
    baseline_fields, baseline_rows = _read_csv(baseline_path)
    routed_fields, routed_rows = _read_csv(routed_path)
    missing = [field for field in ROUTING_FIELDS if field not in routed_fields]
    legacy_fields = [
        field for field in baseline_fields if not field.startswith("phase3_shadow_")
    ]
    row_count_match = len(baseline_rows) == len(routed_rows)
    legacy_mismatches = 0
    first_legacy_mismatch = ""
    if row_count_match:
        for row_index, (baseline, routed) in enumerate(
            zip(baseline_rows, routed_rows, strict=True)
        ):
            for field in legacy_fields:
                if baseline.get(field, "") != routed.get(field, ""):
                    legacy_mismatches += 1
                    if not first_legacy_mismatch:
                        first_legacy_mismatch = f"row={row_index} field={field}"
    else:
        legacy_mismatches = abs(len(baseline_rows) - len(routed_rows))

    active_rows = sum(
        _float(row, ROUTING_FIELDS[0]) > 0.5 for row in routed_rows
    )
    residual_fields = [
        "phase3_shadow_fire_products_routing_fuel_residual_MJ",
        "phase3_shadow_fire_products_routing_o2_residual_kg",
        "phase3_shadow_fire_products_routing_species_residual_kg",
        "phase3_shadow_fire_products_routing_convective_residual_kj",
        "phase3_shadow_fire_products_routing_radiative_residual_kj",
        "phase3_shadow_fire_products_routing_total_energy_residual_kj",
        "phase3_shadow_fire_products_routing_plume_qc_residual_kw",
    ]
    max_abs_residual = {
        field: max((abs(_float(row, field)) for row in routed_rows), default=0.0)
        for field in residual_fields
        if field in routed_fields
    }
    object_sync_rows = sum(
        _float(
            row,
            "phase3_shadow_fire_products_object_sync_required_flag",
        )
        > 0.5
        for row in routed_rows
    )
    residuals_close = all(
        value <= tolerance for value in max_abs_residual.values()
    )
    passed = (
        not missing
        and row_count_match
        and legacy_mismatches == 0
        and active_rows > 0
        and residuals_close
    )
    return {
        "pass": passed,
        "baseline": str(baseline_path),
        "routed": str(routed_path),
        "baseline_rows": len(baseline_rows),
        "routed_rows": len(routed_rows),
        "row_count_match": row_count_match,
        "legacy_field_count": len(legacy_fields),
        "legacy_mismatches": legacy_mismatches,
        "first_legacy_mismatch": first_legacy_mismatch,
        "missing_routing_fields": missing,
        "routing_active_rows": active_rows,
        "object_sync_required_rows": object_sync_rows,
        "max_abs_residuals": max_abs_residual,
        "tolerance": tolerance,
        "runtime_authority_ready": False,
        "group_c_retirement_ready": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("routed", type=Path)
    parser.add_argument("--tolerance", type=float, default=1.0e-7)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    result = analyze(args.baseline, args.routed, args.tolerance)
    text = json.dumps(result, indent=2, sort_keys=True)
    print(text)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(text + "\n", encoding="utf-8")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
