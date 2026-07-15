"""Audit validation CSVs and technical run packages without changing them.

The audit answers a narrow question: are the stored artifacts complete and
structurally trustworthy? It does not claim that a same-stem validation JSON
and CSV came from the same execution; those artifacts have historically been
produced by different runners.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPORTS = REPO_ROOT / "sim" / "validation" / "reports"
DEFAULT_CASES = REPO_ROOT / "sim" / "validation" / "cases"
DEFAULT_RUNS = REPO_ROOT / "runs"
REQUIRED_COLUMNS = {"time_s", "room_id"}
TEXT_COLUMNS = {"room_name", "fire_o2_mode_used", "combustion_regime"}
RUN_FILES = {
    "summary.json",
    "events.json",
    "sim_log.txt",
    "sim_log.csv",
    "run_manifest.json",
}


def _load_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _case_number(case: dict[str, Any], key: str) -> float | None:
    value = case.get(key)
    if value is None:
        value = case.get("engine_overrides", {}).get(key)
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def audit_csv(
    csv_path: Path,
    case_path: Path | None = None,
    report_path: Path | None = None,
) -> dict[str, Any]:
    critical: list[str] = []
    warnings: list[str] = []
    info: list[str] = []
    result: dict[str, Any] = {
        "name": csv_path.stem,
        "path": str(csv_path),
        "critical": critical,
        "warnings": warnings,
        "info": info,
    }
    try:
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            raw_rows = list(reader)
    except (OSError, StopIteration, csv.Error) as exc:
        critical.append(f"cannot read CSV: {exc}")
        result["status"] = "FAIL"
        return result

    if len(header) != len(set(header)):
        critical.append("header contains duplicate columns")
    missing = sorted(REQUIRED_COLUMNS - set(header))
    if missing:
        critical.append(f"missing required columns: {', '.join(missing)}")
    if not raw_rows:
        critical.append("CSV has no data rows")
    bad_width = sum(1 for row in raw_rows if len(row) != len(header))
    if bad_width:
        critical.append(f"{bad_width} row(s) have a different width than the header")
    if critical:
        result.update({"rows": len(raw_rows), "columns": len(header), "status": "FAIL"})
        return result

    time_index = header.index("time_s")
    room_index = header.index("room_id")
    numeric_indexes = [index for index, name in enumerate(header) if name not in TEXT_COLUMNS]
    snapshots: dict[float, list[int]] = defaultdict(list)
    seen: set[tuple[float, int]] = set()
    duplicates = 0
    nonfinite = 0
    parse_errors = 0
    order_errors = 0
    previous_time = -math.inf

    for row in raw_rows:
        try:
            time_s = float(row[time_index])
            room_id = int(float(row[room_index]))
        except (TypeError, ValueError):
            parse_errors += 1
            continue
        if time_s < previous_time - 1e-8:
            order_errors += 1
        previous_time = time_s
        key = (time_s, room_id)
        duplicates += int(key in seen)
        seen.add(key)
        snapshots[time_s].append(room_id)
        for index in numeric_indexes:
            if index >= len(row) or row[index] == "":
                continue
            try:
                if not math.isfinite(float(row[index])):
                    nonfinite += 1
            except ValueError:
                parse_errors += 1

    if parse_errors:
        critical.append(f"{parse_errors} numeric value(s) could not be parsed")
    if nonfinite:
        critical.append(f"{nonfinite} non-finite numeric value(s)")
    if duplicates:
        critical.append(f"{duplicates} duplicate (time_s, room_id) row(s)")
    if order_errors:
        critical.append(f"{order_errors} backwards time transition(s)")

    times = sorted(snapshots)
    room_sets = [set(snapshots[time_s]) for time_s in times]
    canonical_rooms = room_sets[0] if room_sets else set()
    incomplete = sum(1 for rooms in room_sets if rooms != canonical_rooms)
    repeated_rooms = sum(
        1 for time_s in times if len(snapshots[time_s]) != len(set(snapshots[time_s]))
    )
    if incomplete:
        critical.append(f"{incomplete} snapshot(s) have an inconsistent room set")
    if repeated_rooms:
        critical.append(f"{repeated_rooms} snapshot(s) repeat a room")

    modal_interval = None
    interval_distribution: dict[str, int] = {}
    if len(times) > 1:
        deltas = [round(times[index] - times[index - 1], 6) for index in range(1, len(times))]
        counts = Counter(deltas)
        modal_interval = counts.most_common(1)[0][0]
        interval_distribution = {f"{key:g}": value for key, value in sorted(counts.items())}

    case_exists = bool(case_path and case_path.exists())
    case = _load_json(case_path) if case_exists and case_path is not None else None
    if case_exists and case is None:
        critical.append("matching case JSON is malformed")
    if case is None:
        if not case_exists:
            info.append("no matching case JSON; treated as a diagnostic/legacy CSV")
    else:
        duration_s = _case_number(case, "duration_s")
        log_interval_s = _case_number(case, "log_interval_s")
        if duration_s is not None and times:
            final_tolerance = max(0.15, (log_interval_s or 1.0) * 0.03)
            if abs(times[-1] - duration_s) > final_tolerance:
                critical.append(
                    f"final time {times[-1]:g}s differs from case duration {duration_s:g}s"
                )
        if log_interval_s is not None and modal_interval is not None:
            interval_tolerance = max(0.15, log_interval_s * 0.03)
            if abs(modal_interval - log_interval_s) > interval_tolerance:
                critical.append(
                    f"modal interval {modal_interval:g}s differs from configured "
                    f"{log_interval_s:g}s"
                )
            if duration_s is not None:
                expected_snapshots = int(round(duration_s / log_interval_s)) + 1
                if len(times) != expected_snapshots:
                    critical.append(
                        f"has {len(times)} snapshots; expected {expected_snapshots}"
                    )

    report_exists = bool(report_path and report_path.exists())
    report = _load_json(report_path) if report_exists and report_path is not None else None
    if report_exists and report is None:
        critical.append("same-stem report JSON is malformed")
    if report is not None and times:
        try:
            report_time = float(report.get("sim_time_s"))
        except (TypeError, ValueError):
            report_time = None
        if report_time is not None and abs(report_time - times[-1]) > max(0.15, (modal_interval or 1.0) * 0.03):
            warnings.append(
                f"same-stem report ends at {report_time:g}s while CSV ends at {times[-1]:g}s"
            )
        info.append("same-stem CSV/JSON values are not assumed to share run provenance")

    result.update(
        {
            "rows": len(raw_rows),
            "columns": len(header),
            "snapshots": len(times),
            "rooms": len(canonical_rooms),
            "first_time_s": times[0] if times else None,
            "final_time_s": times[-1] if times else None,
            "modal_interval_s": modal_interval,
            "interval_distribution": interval_distribution,
            "status": "FAIL" if critical else ("WARN" if warnings else "PASS"),
        }
    )
    return result


def audit_run_packages(runs_root: Path) -> dict[str, Any]:
    candidates: set[Path] = set()
    if runs_root.exists():
        for path in runs_root.rglob("*"):
            if path.is_file() and path.name in RUN_FILES:
                candidates.add(path.parent)

    complete = 0
    partial: list[dict[str, Any]] = []
    malformed: list[dict[str, str]] = []
    for directory in sorted(candidates):
        names = {path.name for path in directory.iterdir() if path.is_file()}
        missing = sorted(RUN_FILES - names)
        if missing:
            partial.append({"path": str(directory), "missing": missing})
            continue
        manifest = _load_json(directory / "run_manifest.json")
        summary = _load_json(directory / "summary.json")
        if manifest is None or manifest.get("schema_version") != "simufire_run_scenario_manifest_v1":
            malformed.append({"path": str(directory), "reason": "invalid run_manifest.json"})
            continue
        if summary is None or summary.get("schema_version") != "simufire_technical_summary_v1":
            malformed.append({"path": str(directory), "reason": "invalid summary.json"})
            continue
        run_csv = audit_csv(directory / "sim_log.csv")
        if run_csv["critical"]:
            malformed.append({"path": str(directory), "reason": "; ".join(run_csv["critical"])})
            continue
        complete += 1
    return {
        "packages": len(candidates),
        "complete": complete,
        "partial": partial,
        "malformed": malformed,
    }


def run_audit(reports: Path, cases: Path, runs: Path) -> dict[str, Any]:
    csv_results = []
    for csv_path in sorted(reports.glob("*.csv")):
        csv_results.append(
            audit_csv(
                csv_path,
                cases / f"{csv_path.stem}.json",
                reports / f"{csv_path.stem}.json",
            )
        )
    return {
        "csv": csv_results,
        "runs": audit_run_packages(runs),
        "summary": {
            "csv_files": len(csv_results),
            "csv_rows": sum(result.get("rows", 0) for result in csv_results),
            "csv_pass": sum(result["status"] == "PASS" for result in csv_results),
            "csv_warn": sum(result["status"] == "WARN" for result in csv_results),
            "csv_fail": sum(result["status"] == "FAIL" for result in csv_results),
        },
    }


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, default=DEFAULT_REPORTS)
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--runs", type=Path, default=DEFAULT_RUNS)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    result = run_audit(args.reports, args.cases, args.runs)
    summary = result["summary"]
    print(
        "Artifact integrity: "
        f"CSV {summary['csv_pass']} PASS / {summary['csv_warn']} WARN / "
        f"{summary['csv_fail']} FAIL "
        f"({summary['csv_files']} files, {summary['csv_rows']} rows)"
    )
    packages = result["runs"]
    print(
        "Run packages: "
        f"{packages['complete']} complete / {len(packages['partial'])} partial / "
        f"{len(packages['malformed'])} malformed"
    )
    for csv_result in result["csv"]:
        if csv_result["status"] != "PASS":
            details = csv_result["critical"] + csv_result["warnings"]
            print(f"  [{csv_result['status']}] {csv_result['name']}: {'; '.join(details)}")
    for package in packages["partial"]:
        print(f"  [FAIL] partial package {package['path']}: missing {', '.join(package['missing'])}")
    for package in packages["malformed"]:
        print(f"  [FAIL] malformed package {package['path']}: {package['reason']}")

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2), encoding="utf-8")

    has_failures = bool(
        summary["csv_fail"] or packages["partial"] or packages["malformed"]
    )
    return 1 if has_failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
