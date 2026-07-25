#!/usr/bin/env python3
"""Audit the passive F3.3v1 canonical fire proposal STOP gate."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


PREFIX = "phase3_shadow_fire_proposal_"
PROPOSAL_FIELDS = (
    "active_flag",
    "supported_flag",
    "unsupported_reason_mask",
    "age_s",
    "curve_hrr_kw",
    "target_kw",
    "hrr_kw",
    "remaining_fuel_pre_MJ",
    "remaining_fuel_post_MJ",
    "hard_extinction_flag",
    "o2_inventory_cap_kw",
    "ventilation_cap_kw",
    "fuel_cap_kw",
    "decision_fraction",
    "accepted_hrr_kw",
    "requested_o2_kg",
    "accepted_o2_kg",
    "accepted_fuel_MJ",
    "zero_o2_flame_flag",
)
PROPOSAL_COLUMNS = tuple(PREFIX + field for field in PROPOSAL_FIELDS)
NO_FIRE_REASON = 1
EPSILON = 1.0e-8


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def read_csv(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        return rows, list(reader.fieldnames or ())


def compare_shared_values(
    off_rows: list[dict[str, str]],
    on_rows: list[dict[str, str]],
    shared_columns: list[str],
    limit: int = 20,
) -> list[dict[str, Any]]:
    differences: list[dict[str, Any]] = []
    for index, (off_row, on_row) in enumerate(
        zip(off_rows, on_rows, strict=False), start=2
    ):
        for column in shared_columns:
            if off_row.get(column, "") == on_row.get(column, ""):
                continue
            differences.append(
                {
                    "csv_line": index,
                    "column": column,
                    "off": off_row.get(column, ""),
                    "on": on_row.get(column, ""),
                }
            )
            if len(differences) >= limit:
                return differences
    return differences


def _proposal(row: dict[str, str], field: str) -> float:
    return _number(row.get(PREFIX + field))


def _fuel_is_monotonic(rows: list[dict[str, str]]) -> bool:
    values = [_proposal(row, "remaining_fuel_post_MJ") for row in rows]
    return all(
        current <= previous + EPSILON
        for previous, current in zip(values, values[1:], strict=False)
    )


def build_report(
    off_csv: Path,
    on_csv: Path,
    fire_room_id: int = 0,
) -> dict[str, Any]:
    off_rows, off_header = read_csv(off_csv)
    on_rows, on_header = read_csv(on_csv)
    shared_columns = [column for column in off_header if column in on_header]
    extra_columns = [column for column in on_header if column not in off_header]
    missing_columns = [column for column in off_header if column not in on_header]
    differences = compare_shared_values(off_rows, on_rows, shared_columns)

    fire_rows = [
        row
        for row in on_rows
        if int(_number(row.get("room_id"), -1.0)) == fire_room_id
        and _number(row.get("time_s")) > 0.0
    ]
    supported_fire_rows = [
        row for row in fire_rows if _proposal(row, "supported_flag") > 0.5
    ]
    non_fire_rows = [
        row
        for row in on_rows
        if int(_number(row.get("room_id"), -1.0)) != fire_room_id
        and _number(row.get("time_s")) > 0.0
    ]

    all_fire_rows_supported = bool(fire_rows) and (
        len(supported_fire_rows) == len(fire_rows)
    )
    non_fire_rows_explicit = bool(non_fire_rows) and all(
        int(_proposal(row, "unsupported_reason_mask")) & NO_FIRE_REASON
        and _proposal(row, "accepted_hrr_kw") <= EPSILON
        for row in non_fire_rows
    )
    zero_o2_flame_peak = max(
        (_proposal(row, "zero_o2_flame_flag") for row in on_rows),
        default=0.0,
    )
    accepted_above_proposal_peak_kw = max(
        (
            _proposal(row, "accepted_hrr_kw")
            - _proposal(row, "hrr_kw")
            for row in supported_fire_rows
        ),
        default=0.0,
    )
    decision_fraction_in_range = all(
        -EPSILON <= _proposal(row, "decision_fraction") <= 1.0 + EPSILON
        for row in supported_fire_rows
    )
    max_proposal_hrr_kw = max(
        (_proposal(row, "hrr_kw") for row in supported_fire_rows),
        default=0.0,
    )
    max_accepted_hrr_kw = max(
        (_proposal(row, "accepted_hrr_kw") for row in supported_fire_rows),
        default=0.0,
    )
    proposal_reaches_steady_fire = (
        max_proposal_hrr_kw > 0.0
        and max_accepted_hrr_kw >= 0.95 * max_proposal_hrr_kw
    )

    schema_pass = (
        not missing_columns
        and set(extra_columns) == set(PROPOSAL_COLUMNS)
        and len(extra_columns) == len(PROPOSAL_COLUMNS)
    )
    no_op_pass = (
        len(off_rows) == len(on_rows)
        and len(shared_columns) == len(off_header)
        and not differences
    )
    fire_contract_pass = (
        all_fire_rows_supported
        and non_fire_rows_explicit
        and zero_o2_flame_peak <= EPSILON
        and accepted_above_proposal_peak_kw <= EPSILON
        and decision_fraction_in_range
        and _fuel_is_monotonic(supported_fire_rows)
        and proposal_reaches_steady_fire
    )
    return {
        "off_csv": str(off_csv),
        "on_csv": str(on_csv),
        "fire_room_id": fire_room_id,
        "row_count_off": len(off_rows),
        "row_count_on": len(on_rows),
        "column_count_off": len(off_header),
        "column_count_on": len(on_header),
        "shared_column_count": len(shared_columns),
        "extra_columns": extra_columns,
        "missing_columns": missing_columns,
        "shared_value_differences": differences,
        "schema_pass": schema_pass,
        "no_op_pass": no_op_pass,
        "fire_rows": len(fire_rows),
        "supported_fire_rows": len(supported_fire_rows),
        "all_fire_rows_supported": all_fire_rows_supported,
        "non_fire_rows_explicit": non_fire_rows_explicit,
        "fuel_monotonic": _fuel_is_monotonic(supported_fire_rows),
        "decision_fraction_in_range": decision_fraction_in_range,
        "zero_o2_flame_peak": zero_o2_flame_peak,
        "accepted_above_proposal_peak_kw": accepted_above_proposal_peak_kw,
        "max_proposal_hrr_kw": max_proposal_hrr_kw,
        "max_accepted_hrr_kw": max_accepted_hrr_kw,
        "proposal_reaches_steady_fire": proposal_reaches_steady_fire,
        "fire_contract_pass": fire_contract_pass,
        "stop_gate_pass": schema_pass and no_op_pass and fire_contract_pass,
        "runtime_authority": "NO-GO",
        "group_c_retirement": "NO-GO",
    }


def print_report(report: dict[str, Any]) -> None:
    print("F3.3v1 canonical fire proposal STOP gate")
    print(
        "rows OFF/ON:",
        f"{report['row_count_off']}/{report['row_count_on']}",
    )
    print(
        "columns OFF/ON/shared:",
        (
            f"{report['column_count_off']}/"
            f"{report['column_count_on']}/"
            f"{report['shared_column_count']}"
        ),
    )
    print("schema:", "PASS" if report["schema_pass"] else "FAIL")
    print("OFF/ON no-op:", "PASS" if report["no_op_pass"] else "FAIL")
    print(
        "fire support:",
        f"{report['supported_fire_rows']}/{report['fire_rows']}",
    )
    print("fuel monotonic:", report["fuel_monotonic"])
    print("zero-O2 flame peak:", report["zero_o2_flame_peak"])
    print("max proposal HRR:", report["max_proposal_hrr_kw"])
    print("max accepted HRR:", report["max_accepted_hrr_kw"])
    print(
        "STOP gate:",
        "PASS" if report["stop_gate_pass"] else "FAIL",
    )
    print("runtime authority: NO-GO")
    print("Group C retirement: NO-GO")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    run_dir = Path("runs") / "phase3_f33v1"
    parser.add_argument(
        "--off-csv",
        type=Path,
        default=run_dir / "180_off" / "sim_log.csv",
    )
    parser.add_argument(
        "--on-csv",
        type=Path,
        default=run_dir / "180_on_final" / "sim_log.csv",
    )
    parser.add_argument("--fire-room", type=int, default=0)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)

    report = build_report(args.off_csv, args.on_csv, args.fire_room)
    print_report(report)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2) + "\n",
            encoding="utf-8",
        )
    return 0 if report["stop_gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
