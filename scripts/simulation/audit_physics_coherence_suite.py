#!/usr/bin/env python3
"""Batch physical-coherence audit across all SimuFire CSV reports.

Runs check_physics_coherence.py rules on every CSV in sim/validation/reports/
and summarises findings by file and severity.

Background
----------
Rules in check_physics_coherence.py encode physical invariants that must hold
in every valid simulation.  The auditor surfaces violations early — before a
broken case can corrupt validated baselines or calibrate downstream metrics
on physically incorrect outputs.

Two categories of CSV findings:

* **Real violation (FAIL)**: a rule is broken by a bug in the motor.
  Exit code 1 — needs action.

* **Intentional control (CTRL)**: a CSV that deliberately breaks a rule
  to document a known defect as a before-fix baseline.  Register the CSV
  stem in ``KNOWN_INTENTIONAL_CONTROLS`` so the auditor labels it CTRL
  and does not raise exit 1.

Rule: when you add a new intentional-control case, add its stem to
``KNOWN_INTENTIONAL_CONTROLS`` in the same commit.

Usage
-----
  # Audit all permanent CSVs:
  python scripts/simulation/audit_physics_coherence_suite.py

  # Verbose (show PASS lines too):
  python scripts/simulation/audit_physics_coherence_suite.py -v

  # Include tmp_ files:
  python scripts/simulation/audit_physics_coherence_suite.py --include-tmp

  # Ad-hoc override for an intentional control:
  python scripts/simulation/audit_physics_coherence_suite.py \\
      --intentional some_control_case

  # Run only specific rules:
  python scripts/simulation/audit_physics_coherence_suite.py --rules C1,C2

  # Allow all findings without exiting 1 (CI dashboard mode):
  python scripts/simulation/audit_physics_coherence_suite.py --allow-findings

Exit codes
----------
  0  All CSVs have 0 FAIL findings (or only intentional controls, or --allow-findings)
  1  One or more non-intentional CSVs have FAIL findings
  2  Invocation error (bad path, etc.)
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR))
from check_physics_coherence import (  # noqa: E402
    Finding,
    find_physics_coherence_issues,
    load_rows,
)


# ---------------------------------------------------------------------------
# Known intentional controls
#
# Stems listed here produce findings by design (e.g. they document a motor
# bug as a before-fix baseline).  They are labelled CTRL, not FAIL, and
# never raise exit code 1.
#
# Add a new entry here in the same commit that creates the control case.
# ---------------------------------------------------------------------------

KNOWN_INTENTIONAL_CONTROLS: frozenset[str] = frozenset({
    # A3 zombie CTRL: both cases expose FULLY_DEVELOPED at o2_upper≈0 via the
    # ILV lower-O2 reference bug (motor issue, not a validation defect).
    # v1_backdraft_accumulation: zombie without M4, 2 A3 FAILs at t≈290-295s
    # v1_m4_pool_release: M4 active but zombie resumes post-backdraft, 8 A3 FAILs t≈365-385/640-650s
    "v1_backdraft_accumulation",
    "v1_m4_pool_release",
})


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
    def fail_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == "FAIL")

    @property
    def warn_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == "WARN")

    @property
    def worst_finding(self) -> Finding | None:
        # First FAIL (earliest by list order), then first WARN
        for f in self.findings:
            if f.severity == "FAIL":
                return f
        return self.findings[0] if self.findings else None

    def findings_by_rule(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for f in self.findings:
            counts[f.rule_id] = counts.get(f.rule_id, 0) + 1
        return counts


# ---------------------------------------------------------------------------
# Audit logic
# ---------------------------------------------------------------------------

def audit_csv(
    path: Path,
    *,
    rule_ids: set[str] | None = None,
) -> FileResult:
    try:
        rows = load_rows(path)
    except Exception as exc:
        return FileResult(path=path, total_rows=0, rooms=set(), findings=[], error=str(exc))

    rooms = {r.get("room_id", "?").strip() for r in rows if r.get("room_id")}
    findings = find_physics_coherence_issues(rows, rule_ids=rule_ids)
    return FileResult(path=path, total_rows=len(rows), rooms=rooms, findings=findings)


def find_csvs(reports_dir: Path, *, exclude_tmp: bool = True) -> list[Path]:
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
        print(f"  ERROR  {result.name}: {result.error}")
        return

    rooms_str = ",".join(sorted(result.rooms)) if result.rooms else "?"
    if result.finding_count == 0:
        if verbose:
            print(
                f"  PASS  {result.name:<52} rows={result.total_rows:>5}  rooms={rooms_str}"
            )
        return

    rule_str = "  ".join(f"{r}:{n}" for r, n in sorted(result.findings_by_rule().items()))
    severity_str = f"{result.fail_count}F/{result.warn_count}W"

    if result.intentional:
        label = "CTRL"
        suffix = "  (intentional control)"
    elif result.fail_count > 0:
        label = "FAIL"
        suffix = ""
    else:
        label = "WARN"
        suffix = ""

    print(
        f"  {label}  {result.name:<52} [{rule_str}]  "
        f"rows={result.total_rows:>5}  {severity_str}{suffix}"
    )
    worst = result.worst_finding
    if worst:
        print(f"        worst: {worst.format()}")


def _print_top_worst(results: list[FileResult], n: int = 5) -> None:
    failing = [r for r in results if r.fail_count > 0 and not r.error]
    if not failing:
        return
    ranked = sorted(failing, key=lambda r: r.fail_count, reverse=True)
    print(f"\nTop {min(n, len(ranked))} files by FAIL count:")
    print(_SEP)
    for i, r in enumerate(ranked[:n], 1):
        worst = r.worst_finding
        detail = f"  {worst.format()}" if worst else ""
        print(f"  #{i}  {r.name:<52} FAIL={r.fail_count}  WARN={r.warn_count}{detail}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> argparse.Namespace:
    root = Path(__file__).resolve().parent.parent.parent
    default_reports = root / "sim" / "validation" / "reports"

    parser = argparse.ArgumentParser(
        description="Batch physical-coherence audit across SimuFire CSV reports."
    )
    parser.add_argument(
        "--reports-dir",
        type=Path,
        default=default_reports,
        help="Directory containing CSV report files (default: sim/validation/reports/).",
    )
    parser.add_argument(
        "--intentional",
        default="",
        metavar="STEMS",
        help=(
            "Comma-separated CSV stems whose FAIL findings are expected.  "
            "Extends KNOWN_INTENTIONAL_CONTROLS.  "
            "Example: --intentional some_control_case"
        ),
    )
    parser.add_argument(
        "--allow-findings",
        action="store_true",
        help="Exit 0 even if FAIL findings are present (CI dashboard / info mode).",
    )
    parser.add_argument(
        "--include-tmp",
        action="store_true",
        help="Include CSV files whose names start with tmp_.",
    )
    parser.add_argument(
        "--rules",
        default=None,
        metavar="IDS",
        help="Comma-separated rule IDs to run (default: all).  Example: --rules C1,C2",
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

    intentional_stems: set[str] = set(KNOWN_INTENTIONAL_CONTROLS) | {
        s.strip() for s in args.intentional.split(",") if s.strip()
    }

    rule_ids: set[str] | None = None
    if args.rules:
        rule_ids = {r.strip().upper() for r in args.rules.split(",") if r.strip()}

    csv_paths = find_csvs(reports_dir, exclude_tmp=not args.include_tmp)
    if not csv_paths:
        print(f"No CSV files found in {reports_dir}")
        return 0

    print("Physics Coherence Suite Audit")
    print(f"Reports dir : {reports_dir}")
    print(f"CSV files   : {len(csv_paths)}")
    print(f"Rules       : {', '.join(rule_ids) if rule_ids else 'all'}")
    if intentional_stems:
        print(f"CTRL stems  : {', '.join(sorted(intentional_stems))}")
    print(_SEP)

    results: list[FileResult] = []
    for path in csv_paths:
        result = audit_csv(path, rule_ids=rule_ids)
        if path.stem in intentional_stems:
            result.intentional = True
        results.append(result)
        _print_file_result(result, verbose=args.verbose)

    # Summary
    clean       = [r for r in results if r.finding_count == 0 and not r.error]
    intentional = [r for r in results if r.finding_count > 0 and not r.error and r.intentional]
    warn_only   = [r for r in results if r.fail_count == 0 and r.warn_count > 0 and not r.error and not r.intentional]
    dirty       = [r for r in results if r.fail_count > 0 and not r.error and not r.intentional]
    errors      = [r for r in results if r.error]

    total_fail = sum(r.fail_count for r in dirty)
    total_warn = sum(r.warn_count for r in warn_only)
    total_ctrl = sum(r.finding_count for r in intentional)

    print(_SEP)
    print(f"SUMMARY: {len(csv_paths)} file(s) audited")
    print(f"  PASS : {len(clean):>3}")
    if intentional:
        print(f"  CTRL : {len(intentional):>3}  ({total_ctrl} findings, expected -- intentional controls)")
    if warn_only:
        print(f"  WARN : {len(warn_only):>3}  ({total_warn} warnings, not gating)")
    print(f"  FAIL : {len(dirty):>3}  ({total_fail} FAIL findings)")
    if errors:
        print(f"  ERROR: {len(errors):>3}")

    _print_top_worst(results, n=args.top_n)

    if dirty and not args.allow_findings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
