#!/usr/bin/env python3
"""Batch ILV layer-coherence audit across all SimuFire CSV reports.

Scans sim/validation/reports/ for CSV logs and runs the same coherence
checks as check_ilv_layer_coherence.py on each file, then prints a
ranked summary of incoherence findings.

Background
----------
The ILV HRR-zombie bug (found 2026-06-21) occurs when two_zone_solver
chooses o2_lower as the combustion throttle reference while o2_upper
collapses to near-zero.  The motor guard fix (M4, flag
``fire_o2_upper_throttle_enabled``) is opt-in per-case (default false).

Two classes of CSV findings are therefore expected in the suite:

* **Real bug (FAIL)**: a case that should have M4 active but doesn't.
  Exit code 1 — needs action.

* **Intentional control (CTRL)**: a case that deliberately runs with
  M4 off to expose the zombie as a reference.  Register it with
  ``--intentional`` so the auditor labels it CTRL and does not raise
  exit 1.  Example: ``fp_ilv_upper_throttle_off`` (258 findings,
  HRR zombie ~1211 kW — the before-M4 baseline).

Do NOT combine M4 (``fire_o2_upper_throttle_enabled``) with
``fire_o2_canonical_enabled`` without an explicit plan: they are
competing mechanisms and can cancel each other.

Usage
-----
  # Audit all existing CSVs:
  python scripts/simulation/audit_ilv_layer_coherence_suite.py

  # Mark a CSV as an intentional control (findings expected, no exit 1):
  python scripts/simulation/audit_ilv_layer_coherence_suite.py \\
      --intentional fp_ilv_upper_throttle_off

  # Multiple controls:
  python scripts/simulation/audit_ilv_layer_coherence_suite.py \\
      --intentional fp_ilv_upper_throttle_off,some_other_control

  # Include a specific extra directory:
  python scripts/simulation/audit_ilv_layer_coherence_suite.py --reports-dir path/to/reports

  # Allow ALL findings without exiting 1 (CI dashboard / info mode):
  python scripts/simulation/audit_ilv_layer_coherence_suite.py --allow-findings

  # Filter to a specific kind of finding:
  python scripts/simulation/audit_ilv_layer_coherence_suite.py --kind HRR-throttle-high

Exit codes
----------
  0  All CSVs passed (or only intentional controls have findings, or --allow-findings)
  1  One or more non-intentional CSVs have coherence findings
  2  Invocation error (bad path, etc.)
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Re-use core logic from single-file checker — same package directory.
_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR))
from check_ilv_layer_coherence import (  # noqa: E402
    Finding,
    find_ilv_layer_coherence_issues,
    load_rows,
)


# ---------------------------------------------------------------------------
# Per-file result
# ---------------------------------------------------------------------------

@dataclass
class FileResult:
    path: Path
    total_rows: int
    rooms: set[str]
    findings: list[Finding]
    error: str | None = None
    intentional: bool = False

    @property
    def name(self) -> str:
        return self.path.stem

    @property
    def finding_count(self) -> int:
        return len(self.findings)

    @property
    def worst_finding(self) -> Finding | None:
        if not self.findings:
            return None
        return max(self.findings, key=lambda f: f.hrr_kw)

    def findings_by_kind(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for f in self.findings:
            counts[f.kind] = counts.get(f.kind, 0) + 1
        return counts


# ---------------------------------------------------------------------------
# Audit logic
# ---------------------------------------------------------------------------

def audit_csv(
    path: Path,
    *,
    min_hrr_kw: float = 100.0,
    critical_o2_upper: float = 0.05,
    fresh_o2_lower: float = 0.15,
    high_o2_hrr_factor: float = 0.75,
    kind_filter: str | None = None,
) -> FileResult:
    """Run coherence analysis on a single CSV; return structured result."""
    try:
        rows = load_rows(path)
    except Exception as exc:
        return FileResult(path=path, total_rows=0, rooms=set(), findings=[], error=str(exc))

    rooms = {r.get("room_id", "?").strip() for r in rows if r.get("room_id")}
    findings = find_ilv_layer_coherence_issues(
        rows,
        min_hrr_kw=min_hrr_kw,
        critical_o2_upper=critical_o2_upper,
        fresh_o2_lower=fresh_o2_lower,
        high_o2_hrr_factor=high_o2_hrr_factor,
    )

    if kind_filter:
        findings = [f for f in findings if kind_filter in f.kind]

    return FileResult(path=path, total_rows=len(rows), rooms=rooms, findings=findings)


def find_csvs(reports_dir: Path, *, exclude_tmp: bool = True) -> list[Path]:
    """Return sorted list of CSV files in *reports_dir*."""
    paths = sorted(reports_dir.glob("*.csv"))
    if exclude_tmp:
        paths = [p for p in paths if not p.stem.startswith("tmp_")]
    return paths


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

_SEP = "-" * 78


def _print_file_result(result: FileResult, *, verbose: bool) -> None:
    if result.error:
        print(f"  ERROR reading {result.name}: {result.error}")
        return

    rooms_str = ",".join(sorted(result.rooms)) if result.rooms else "?"
    if result.finding_count == 0:
        if verbose:
            print(f"  PASS  {result.name:<52} rows={result.total_rows:>5}  rooms={rooms_str}")
        return

    worst = result.worst_finding
    kinds = result.findings_by_kind()
    kind_str = "  ".join(f"{k.split('-')[-1]}:{v}" for k, v in kinds.items())

    if result.intentional:
        label = "CTRL"
        suffix = "  (intentional control -- M4 off reference)"
    else:
        label = "FAIL"
        suffix = ""

    print(
        f"  {label}  {result.name:<52} findings={result.finding_count:>4}  "
        f"rows={result.total_rows:>5}  [{kind_str}]{suffix}"
    )
    if worst:
        print(
            f"        worst: t={worst.time_s:.0f}s  room={worst.room_id}  "
            f"hrr={worst.hrr_kw:.1f}kW  o2_upper={worst.o2_upper * 100:.2f}%  "
            f"o2_lower={worst.o2_lower * 100:.2f}%  "
            f"o2_hrr_factor={worst.o2_hrr_factor:.3f}  regime={worst.regime}"
        )


def _print_top_worst(results: list[FileResult], n: int = 5) -> None:
    failing = [r for r in results if r.finding_count > 0 and not r.error]
    if not failing:
        return
    ranked = sorted(failing, key=lambda r: r.finding_count, reverse=True)
    print(f"\nTop {min(n, len(ranked))} worst files by finding count:")
    print(_SEP)
    for i, r in enumerate(ranked[:n], 1):
        worst = r.worst_finding
        hrr_str = f"max_hrr={worst.hrr_kw:.0f}kW" if worst else ""
        o2_str  = f"min_o2upper={worst.o2_upper * 100:.2f}%" if worst else ""
        print(f"  #{i}  {r.name:<52} findings={r.finding_count:>4}  {hrr_str}  {o2_str}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> argparse.Namespace:
    root = Path(__file__).resolve().parent.parent.parent
    default_reports = root / "sim" / "validation" / "reports"

    parser = argparse.ArgumentParser(
        description="Batch ILV coherence audit across SimuFire CSV reports."
    )
    parser.add_argument(
        "--reports-dir",
        type=Path,
        default=default_reports,
        help="Directory containing CSV report files (default: sim/validation/reports/)",
    )
    parser.add_argument(
        "--allow-findings",
        action="store_true",
        help="Exit 0 even if findings are present (dashboard/CI info mode).",
    )
    parser.add_argument(
        "--include-tmp",
        action="store_true",
        help="Include files whose names start with tmp_.",
    )
    parser.add_argument(
        "--kind",
        default=None,
        metavar="FRAGMENT",
        help="Only report findings whose kind contains FRAGMENT (e.g. HRR-throttle-high).",
    )
    parser.add_argument(
        "--min-hrr-kw", type=float, default=100.0,
        help="Minimum HRR (kW) to flag a row (default: 100).",
    )
    parser.add_argument(
        "--critical-o2-upper", type=float, default=0.05,
        help="o2_upper threshold below which upper zone is critical (default: 0.05).",
    )
    parser.add_argument(
        "--fresh-o2-lower", type=float, default=0.15,
        help="o2_lower threshold above which lower zone is considered fresh (default: 0.15).",
    )
    parser.add_argument(
        "--high-o2-hrr-factor", type=float, default=0.75,
        help="o2_hrr_factor threshold above which throttle is considered high (default: 0.75).",
    )
    parser.add_argument(
        "--intentional",
        default="",
        metavar="STEMS",
        help=(
            "Comma-separated CSV stems whose findings are expected "
            "(intentional controls — M4-off references).  These are labelled "
            "CTRL in the report and do not raise exit code 1.  "
            "Example: --intentional fp_ilv_upper_throttle_off"
        ),
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Also print PASS lines.",
    )
    parser.add_argument(
        "--top-n", type=int, default=5,
        help="Number of worst files to highlight (default: 5).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)

    reports_dir = args.reports_dir
    if not reports_dir.is_dir():
        print(f"ERROR: reports directory not found: {reports_dir}", file=sys.stderr)
        return 2

    intentional_stems: set[str] = {
        s.strip() for s in args.intentional.split(",") if s.strip()
    }

    csv_paths = find_csvs(reports_dir, exclude_tmp=not args.include_tmp)
    if not csv_paths:
        print(f"No CSV files found in {reports_dir}")
        return 0

    print(f"ILV Coherence Suite Audit")
    print(f"Reports dir : {reports_dir}")
    print(f"CSV files   : {len(csv_paths)}")
    if intentional_stems:
        print(f"CTRL stems  : {', '.join(sorted(intentional_stems))}")
    print(_SEP)

    results: list[FileResult] = []
    for path in csv_paths:
        result = audit_csv(
            path,
            min_hrr_kw=args.min_hrr_kw,
            critical_o2_upper=args.critical_o2_upper,
            fresh_o2_lower=args.fresh_o2_lower,
            high_o2_hrr_factor=args.high_o2_hrr_factor,
            kind_filter=args.kind,
        )
        if path.stem in intentional_stems:
            result.intentional = True
        results.append(result)
        _print_file_result(result, verbose=args.verbose)

    # Summary
    clean        = [r for r in results if r.finding_count == 0 and not r.error]
    intentional  = [r for r in results if r.finding_count  > 0 and not r.error and r.intentional]
    dirty        = [r for r in results if r.finding_count  > 0 and not r.error and not r.intentional]
    errors       = [r for r in results if r.error]
    total_findings = sum(r.finding_count for r in dirty)
    total_ctrl     = sum(r.finding_count for r in intentional)

    print(_SEP)
    print(f"SUMMARY: {len(csv_paths)} file(s) audited")
    print(f"  PASS : {len(clean):>3}")
    if intentional:
        print(f"  CTRL : {len(intentional):>3}  ({total_ctrl} findings, expected -- intentional controls)")
    print(f"  FAIL : {len(dirty):>3}  ({total_findings} total findings)")
    if errors:
        print(f"  ERROR: {len(errors):>3}")

    _print_top_worst(results, n=args.top_n)

    if dirty and not args.allow_findings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
