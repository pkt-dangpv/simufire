#!/usr/bin/env python3
"""Audit the passive F3.3v2 canonical fire-products STOP gate."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


PREFIX = "phase3_shadow_fire_products_"
SPECIES = (
    "smoke",
    "co",
    "co2",
    "hcn",
    "hcl",
    "acrolein",
    "formaldehyde",
)
SCALAR_FIELDS = (
    "active_flag",
    "supported_flag",
    "object_sync_required_flag",
    "profile_object_count",
    "quality_phi",
    "carbon_scale",
    "common_fraction",
    "requested_fuel_MJ",
    "accepted_fuel_MJ",
    "requested_o2_kg",
    "accepted_o2_kg",
    "requested_total_energy_kj",
    "accepted_total_energy_kj",
    "effective_chi_rad",
    "requested_radiative_energy_kj",
    "accepted_radiative_energy_kj",
    "requested_convective_energy_kj",
    "accepted_convective_energy_kj",
    "accepted_plume_driver_hrr_kw",
    "accepted_plume_driver_qc_kw",
    "requested_carbon_available_kg",
    "requested_carbon_products_kg",
    "requested_carbon_untracked_kg",
    "requested_carbon_residual_kg",
    "accepted_carbon_available_kg",
    "accepted_carbon_products_kg",
    "accepted_carbon_untracked_kg",
    "accepted_carbon_residual_kg",
    "fuel_residual_MJ",
    "o2_residual_kg",
    "energy_residual_kj",
    "species_common_fraction_residual_kg",
)
PRODUCT_FIELDS = SCALAR_FIELDS + tuple(
    f"{acceptance}_{species}_kg"
    for acceptance in ("requested", "accepted")
    for species in SPECIES
)
PRODUCT_COLUMNS = tuple(PREFIX + field for field in PRODUCT_FIELDS)
RESIDUAL_FIELDS = (
    "requested_carbon_residual_kg",
    "accepted_carbon_residual_kg",
    "fuel_residual_MJ",
    "o2_residual_kg",
    "energy_residual_kj",
    "species_common_fraction_residual_kg",
)
EPSILON = 1.0e-8


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def _product(row: dict[str, str], field: str) -> float:
    return _number(row.get(PREFIX + field))


def read_csv(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        return rows, list(reader.fieldnames or ())


def compare_shared_values(
    baseline_rows: list[dict[str, str]],
    products_rows: list[dict[str, str]],
    shared_columns: list[str],
    limit: int = 20,
) -> list[dict[str, Any]]:
    differences: list[dict[str, Any]] = []
    for index, (baseline_row, products_row) in enumerate(
        zip(baseline_rows, products_rows, strict=False), start=2
    ):
        for column in shared_columns:
            if baseline_row.get(column, "") == products_row.get(column, ""):
                continue
            differences.append(
                {
                    "csv_line": index,
                    "column": column,
                    "baseline": baseline_row.get(column, ""),
                    "products": products_row.get(column, ""),
                }
            )
            if len(differences) >= limit:
                return differences
    return differences


def _accepted_not_above_requested(rows: list[dict[str, str]]) -> bool:
    paired_fields = (
        ("fuel_MJ", "fuel_MJ"),
        ("o2_kg", "o2_kg"),
        ("total_energy_kj", "total_energy_kj"),
        ("radiative_energy_kj", "radiative_energy_kj"),
        ("convective_energy_kj", "convective_energy_kj"),
        ("carbon_available_kg", "carbon_available_kg"),
        ("carbon_products_kg", "carbon_products_kg"),
        ("carbon_untracked_kg", "carbon_untracked_kg"),
    )
    for row in rows:
        for requested_suffix, accepted_suffix in paired_fields:
            if _product(row, f"accepted_{accepted_suffix}") > (
                _product(row, f"requested_{requested_suffix}") + EPSILON
            ):
                return False
        for species in SPECIES:
            if _product(row, f"accepted_{species}_kg") > (
                _product(row, f"requested_{species}_kg") + EPSILON
            ):
                return False
    return True


def _species_share_common_fraction(rows: list[dict[str, str]]) -> bool:
    for row in rows:
        fraction = _product(row, "common_fraction")
        for species in SPECIES:
            requested = _product(row, f"requested_{species}_kg")
            accepted = _product(row, f"accepted_{species}_kg")
            if abs(accepted - requested * fraction) > EPSILON:
                return False
    return True


def _non_fire_products_are_zero(
    rows: list[dict[str, str]], fire_room_id: int
) -> bool:
    accepted_fields = (
        "accepted_fuel_MJ",
        "accepted_o2_kg",
        "accepted_total_energy_kj",
        "accepted_radiative_energy_kj",
        "accepted_convective_energy_kj",
        "accepted_plume_driver_hrr_kw",
        "accepted_plume_driver_qc_kw",
    ) + tuple(f"accepted_{species}_kg" for species in SPECIES)
    non_fire_rows = [
        row
        for row in rows
        if int(_number(row.get("room_id"), -1.0)) != fire_room_id
        and _number(row.get("time_s")) > 0.0
    ]
    return bool(non_fire_rows) and all(
        _product(row, "active_flag") <= EPSILON
        and all(abs(_product(row, field)) <= EPSILON for field in accepted_fields)
        for row in non_fire_rows
    )


def build_report(
    baseline_csv: Path,
    products_csv: Path,
    fire_room_id: int = 0,
) -> dict[str, Any]:
    baseline_rows, baseline_header = read_csv(baseline_csv)
    products_rows, products_header = read_csv(products_csv)
    shared_columns = [
        column for column in baseline_header if column in products_header
    ]
    extra_columns = [
        column for column in products_header if column not in baseline_header
    ]
    missing_columns = [
        column for column in baseline_header if column not in products_header
    ]
    differences = compare_shared_values(
        baseline_rows, products_rows, shared_columns
    )
    fire_rows = [
        row
        for row in products_rows
        if int(_number(row.get("room_id"), -1.0)) == fire_room_id
        and _number(row.get("time_s")) > 0.0
    ]
    supported_fire_rows = [
        row for row in fire_rows if _product(row, "supported_flag") > 0.5
    ]
    all_fire_rows_supported = bool(fire_rows) and (
        len(supported_fire_rows) == len(fire_rows)
    )
    fractions_in_range = all(
        -EPSILON <= _product(row, "common_fraction") <= 1.0 + EPSILON
        for row in supported_fire_rows
    )
    yields_nonnegative = all(
        _product(row, field) >= -EPSILON
        for row in supported_fire_rows
        for field in PRODUCT_FIELDS
        if not field.endswith("residual_kg")
        and not field.endswith("residual_MJ")
        and not field.endswith("residual_kj")
    )
    accepted_not_above_requested = _accepted_not_above_requested(
        supported_fire_rows
    )
    species_share_common_fraction = _species_share_common_fraction(
        supported_fire_rows
    )
    carbon_bounded = all(
        _product(row, f"{acceptance}_carbon_products_kg")
        <= _product(row, f"{acceptance}_carbon_available_kg") + EPSILON
        for row in supported_fire_rows
        for acceptance in ("requested", "accepted")
    )
    energy_partition_bounded = all(
        _product(row, "accepted_plume_driver_qc_kw")
        <= _product(row, "accepted_plume_driver_hrr_kw") + EPSILON
        for row in supported_fire_rows
    )
    residual_peaks = {
        field: max(
            (abs(_product(row, field)) for row in products_rows),
            default=0.0,
        )
        for field in RESIDUAL_FIELDS
    }
    residuals_close = all(
        peak <= EPSILON for peak in residual_peaks.values()
    )
    object_sync_required = any(
        _product(row, "object_sync_required_flag") > 0.5
        for row in supported_fire_rows
    )
    profile_object_count_peak = max(
        (
            _product(row, "profile_object_count")
            for row in supported_fire_rows
        ),
        default=0.0,
    )

    schema_pass = (
        not missing_columns
        and set(extra_columns) == set(PRODUCT_COLUMNS)
        and len(extra_columns) == len(PRODUCT_COLUMNS)
    )
    no_op_pass = (
        len(baseline_rows) == len(products_rows)
        and len(shared_columns) == len(baseline_header)
        and not differences
    )
    product_contract_pass = (
        all_fire_rows_supported
        and _non_fire_products_are_zero(products_rows, fire_room_id)
        and fractions_in_range
        and yields_nonnegative
        and accepted_not_above_requested
        and species_share_common_fraction
        and carbon_bounded
        and energy_partition_bounded
        and residuals_close
    )
    return {
        "baseline_csv": str(baseline_csv),
        "products_csv": str(products_csv),
        "fire_room_id": fire_room_id,
        "row_count_baseline": len(baseline_rows),
        "row_count_products": len(products_rows),
        "column_count_baseline": len(baseline_header),
        "column_count_products": len(products_header),
        "shared_column_count": len(shared_columns),
        "extra_columns": extra_columns,
        "missing_columns": missing_columns,
        "shared_value_differences": differences,
        "schema_pass": schema_pass,
        "no_op_pass": no_op_pass,
        "fire_rows": len(fire_rows),
        "supported_fire_rows": len(supported_fire_rows),
        "all_fire_rows_supported": all_fire_rows_supported,
        "non_fire_products_zero": _non_fire_products_are_zero(
            products_rows, fire_room_id
        ),
        "fractions_in_range": fractions_in_range,
        "yields_nonnegative": yields_nonnegative,
        "accepted_not_above_requested": accepted_not_above_requested,
        "species_share_common_fraction": species_share_common_fraction,
        "carbon_bounded": carbon_bounded,
        "energy_partition_bounded": energy_partition_bounded,
        "residual_peaks": residual_peaks,
        "residuals_close": residuals_close,
        "object_sync_required": object_sync_required,
        "profile_object_count_peak": profile_object_count_peak,
        "product_contract_pass": product_contract_pass,
        "stop_gate_pass": schema_pass and no_op_pass and product_contract_pass,
        "runtime_authority": "NO-GO",
        "runtime_authority_blocker": (
            "explicit fuel-object synchronization remains unowned"
            if object_sync_required
            else "products remain passive shadow telemetry"
        ),
        "group_c_retirement": "NO-GO",
    }


def print_report(report: dict[str, Any]) -> None:
    print("F3.3v2 canonical fire-products STOP gate")
    print(
        "rows baseline/products:",
        f"{report['row_count_baseline']}/{report['row_count_products']}",
    )
    print(
        "columns baseline/products/shared:",
        (
            f"{report['column_count_baseline']}/"
            f"{report['column_count_products']}/"
            f"{report['shared_column_count']}"
        ),
    )
    print("new product columns:", len(report["extra_columns"]))
    print("schema:", "PASS" if report["schema_pass"] else "FAIL")
    print("legacy no-op:", "PASS" if report["no_op_pass"] else "FAIL")
    print(
        "fire support:",
        f"{report['supported_fire_rows']}/{report['fire_rows']}",
    )
    print("non-fire accepted products zero:", report["non_fire_products_zero"])
    print("common fraction:", report["species_share_common_fraction"])
    print("carbon bounded:", report["carbon_bounded"])
    print("maximum residuals:", report["residual_peaks"])
    print("object sync required:", report["object_sync_required"])
    print("profile object count peak:", report["profile_object_count_peak"])
    print("STOP gate:", "PASS" if report["stop_gate_pass"] else "FAIL")
    print("runtime authority: NO-GO")
    print("Group C retirement: NO-GO")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline-csv",
        type=Path,
        default=Path("runs")
        / "phase3_f33v1"
        / "180_on_final"
        / "sim_log.csv",
    )
    parser.add_argument(
        "--products-csv",
        type=Path,
        default=Path("runs")
        / "phase3_f33v2"
        / "180_on"
        / "sim_log.csv",
    )
    parser.add_argument("--fire-room", type=int, default=0)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)

    report = build_report(
        args.baseline_csv, args.products_csv, args.fire_room
    )
    print_report(report)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2, sort_keys=True),
            encoding="utf-8",
        )
    return 0 if report["stop_gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
