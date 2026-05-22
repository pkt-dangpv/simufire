#!/usr/bin/env python3
"""Print key CFAST CSV values for quick validation diagnostics."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


DEFAULT_CASES = (
    "cfast_long_burnout_3600s",
    "cfast_window_break_t180",
    "cfast_door_close_midfire",
)

KEY_TIMES_S = (0, 60, 120, 180, 240, 300, 420, 600, 900, 1800, 3570)
KEY_FIELDS = (
    "Time",
    "ULT_1",
    "LLT_1",
    "HGT_1",
    "HRR_1",
    "LLCO_1",
    "ULCO2_1",
    "LLO2_1",
    "PRS_1",
    "ULT_2",
    "LLT_2",
    "LLO2_2",
)


def read_cfast(path: Path) -> tuple[list[str], list[list[float | None]]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if len(rows) < 5:
        raise ValueError(f"CFAST CSV is too short: {path}")

    headers = rows[0]
    data: list[list[float | None]] = []
    for row_number, row in enumerate(rows[4:], start=5):
        if not row:
            continue
        try:
            data.append([float(cell) if cell.strip() else None for cell in row])
        except ValueError as exc:
            raise ValueError(f"invalid numeric value at row {row_number}: {path}") from exc
    return headers, data


def print_case(case_name: str, cfast_dir: Path) -> None:
    path = cfast_dir / f"{case_name}_compartments.csv"
    headers, data = read_cfast(path)
    index = {header: i for i, header in enumerate(headers)}

    print(f"\n=== {case_name} ===")
    print(f"Columns: {headers[:15]}")
    last_t = -100.0
    for row in data:
        if not row:
            continue
        t = row[0]
        if t is None or not any(abs(t - key_time) < 1.0 for key_time in KEY_TIMES_S):
            continue
        if abs(t - last_t) < 0.5:
            continue
        last_t = t
        values = {
            field: (row[index[field]] if field in index and index[field] < len(row) else None)
            for field in KEY_FIELDS
        }
        formatted = ", ".join(f"{key}={value:.2f}" for key, value in values.items() if value is not None)
        print(f"  t={t:.0f}: {formatted}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", nargs="*", default=list(DEFAULT_CASES), help="Case names without _compartments.csv")
    parser.add_argument(
        "--cfast-dir",
        default=Path(__file__).resolve().parent,
        type=Path,
        help="Directory containing CFAST *_compartments.csv files",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    failed = False
    for case_name in args.cases:
        try:
            print_case(case_name, args.cfast_dir)
        except (OSError, ValueError) as exc:
            failed = True
            print(f"Error processing {case_name}: {exc}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
