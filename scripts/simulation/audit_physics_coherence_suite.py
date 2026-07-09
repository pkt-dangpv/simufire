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
# never raise exit code 1 — but only within their declared ENVELOPE:
# a dict of {rule_id: max_count}.  A finding whose rule is not in the
# envelope, or whose per-rule count exceeds its max, flips the case to
# FAIL: a CTRL absorbs only what it was registered to absorb; anything
# else is a regression on top of the known defect.
#
# Max counts carry ~25% headroom over the counts measured at registration,
# so CSV-regeneration jitter does not flap the gate; a real regression
# (new rule, or counts well beyond the known mechanism) still trips it.
#
# Add a new entry here in the same commit that creates the control case.
# Update an envelope only as a deliberate change to the control, never to
# silence an unexplained increase.
# ---------------------------------------------------------------------------

KNOWN_INTENTIONAL_CONTROLS: dict[str, dict[str, int] | None] = {
    # A3 zombie CTRL: exposes FULLY_DEVELOPED at o2_upper≈0 via the ILV
    # lower-O2 reference bug (motor issue, not a validation defect).
    # Zombie without M4: 2 A3 FAILs t≈290-295s; D2PRE M1 collateral; O2E1
    # Thornton divergence during depletion.
    # (measured 2026-07-06: A3:2, D2PRE:563, O2E1:16)
    "v1_backdraft_accumulation": {"A3": 4, "D2PRE": 700, "O2E1": 24},
    # M4 active: pool-release D2 bursts post-backdraft; D2PRE M1 collateral.
    # The historical A3 zombie FAILs were eliminated by M5 — A3 is
    # deliberately NOT in this envelope; if it reappears, the case FAILs.
    # (measured 2026-07-06: D2:9, D2PRE:545)
    "v1_m4_pool_release": {"D2": 15, "D2PRE": 680},
    # A3/O2E1 CTRL: sealed multi-floor building, all external windows closed,
    # fire room depletes O2 after t≈400s.  A3 (regime mismatch) and O2E1
    # (Thornton divergence) are expected consequences of extreme O2 depletion
    # in a fully sealed configuration — same root cause as v1_backdraft_accumulation.
    # Purpose of this case is S1 C-S1-3 (multi-floor inter-room smoke transport
    # coverage); S1 is clean throughout.  Added as CTRL 2026-06-30.
    # D2PRE: M1/Plan-B tracer-vs-mass divergence exposed after CSV regen with
    # specie pumping fix (2026-07-07); same family as flashover_simple_house.
    # (measured 2026-07-06: A3:4, O2E1:20; remeasured 2026-07-07: A3:4, D2PRE:305, O2E1:20)
    "cfast_two_floor_stairwell": {"A3": 8, "D2PRE": 380, "O2E1": 30},
    # Single-room sealed diagnostic CTRLs: designed to run to total O2 depletion.
    # A3 (FULLY_DEVELOPED at final tick o2_upper≈0.09%) is expected — these cases
    # model sealed combustion to exhaustion by design.  D2PRE is M1/Plan-B
    # tracer-vs-mass collateral, same root cause as cfast_slow_growth_sealed.
    # Both cases use identical parameters; A3:2 and D2PRE:248 measured post-specie-fix
    # regen 2026-07-07.
    # G1 (2026-07-08): in-flight species ledger delivers CO2 to rooms faster; CO2_upper
    # now exceeds the 1000 ppm D2 activation threshold during the CO-rich early phase
    # (t=270–300s rooms 3,5), exposing a physically real CO-dominant period — D2:15.
    # S0 artifact retired 2026-07-09: _last_written_time_s guard in SimulationLogWriter
    # prevents the double-log at the final tick; CSV now emits 6 rows at t=300.0 s (not 12).
    # (measured 2026-07-09: A3:1, D2:13, D2PRE:235)
    "fuel_balance_diag_sealed": {"A3": 2, "D2PRE": 310, "D2": 15},
    "o2_stoich_diag_sealed": {"A3": 2, "D2PRE": 310, "D2": 15},
    # D2 pool-release CTRL: M4 ventilation throttle (fire_o2_upper_throttle_enabled)
    # causes cyclical ILV_LATENT → pool-release oscillations throughout t=225–600s.
    # retained_unburned_MJ accumulates to 0.12–0.17 MJ per cycle; pool combustion
    # produces CO bursts that push CO/CO₂ ratio to 0.51–0.62 (threshold 0.50).
    # D2 WARNs are a direct, expected consequence of the M4 mechanism under test.
    # Also has D2PRE WARNs (M1 o2_scale double-throttle).  Added as CTRL 2026-06-30.
    # (measured 2026-07-06: D2:13, D2PRE:421)
    "v5_m4_ventilation_throttle": {"D2": 20, "D2PRE": 530},
    # D2 + D2PRE reference CTRL: created in Plan A Fase A1 to demonstrate that D2 fires
    # in deep VC with mixed/synthetic fuel yields (co_base=0.004 kg/MJ, co_max=0.10 kg/MJ,
    # 16× SFPE wood FC).  D2 WARN starts at t=710s (ratio=0.512) and escalates to 2.14 at
    # t=1800s — intentional by design; this is the canonical D2 reference case.
    # D2PRE WARNs in rooms 0, 1, 4 are collateral M1 o2_scale (same root cause as
    # cfast_slow_growth_sealed).  Added as CTRL 2026-06-30.
    # (measured 2026-07-06: D2:114, D2PRE:74)
    "wood_vc_reference": {"D2": 145, "D2PRE": 95},
    # cfast_slow_growth_sealed CTRL (re-measured 2026-07-09 with fire_o2_mode=upper):
    # fire_o2_mode="upper" added to engine_overrides so run_scenario_headless applies
    # the same mode declared by validation_fire_o2_mode.  Upper mode concentrates O2
    # consumption in the hot upper layer, producing more pronounced CO2 stratification
    # and higher co2_upper_ppm_mass vs co2_upper_ppm(tracer) — hence higher D2PRE.
    # D2PRE WARNs are M1/tracer-vs-mass collateral (same root cause as fuel_balance).
    # (measured 2026-07-09: D2PRE:162)
    "cfast_slow_growth_sealed": {"D2PRE": 200},
    # HVAC species-instrumentation gap CTRL (coverage expansion 2026-07-06):
    # HVACSystem.gd extracts smoke/CO from rooms (smoke_exhausted_kg, CO via
    # return sampling) WITHOUT contributing to the balance accumulators
    # (co_exterior_removed_kg_total etc.), so D1/S1 residuals appear in the
    # HVAC-served fire room.  Same root cause O1 already documents and skips
    # (hvac_exists rows, HvacSystem.gd line 302).  Pending motor session:
    # instrument HVAC species accumulators, then remove this CTRL.
    # (measured 2026-07-06: D1:58, S1:36, D2PRE:1 — all room 0 except D2PRE)
    # (remeasured 2026-07-09 with declared upper mode: D1:58, S1:39, D2PRE:28, O2E1:21)
    # D2PRE increase: upper mode changes CO2 tracer-vs-mass dynamics (M1 collateral).
    # O2E1: upper zone O2 depletes to <7% at t>400s; OES 5%-cap limits delta_o2_fire
    # below Thornton expectation — same structural family as cfast_two_floor_stairwell.
    "cfast_hvac_residential": {"D1": 70, "S1": 45, "D2PRE": 35, "O2E1": 25},
    # ILV-zombie family CTRL (coverage expansion 2026-07-06): multi-room CO
    # transport case, sealed-ish without M4.  A3 (zombie regime) + O2E1
    # (Thornton mismatch while zombie burns without O2 accounting) + D2PRE
    # (M1 multi-room, largest corpus count: 6 rooms × 700 s).  E1:2 is float
    # noise (residual 2.1e-06 MJ ≈ 2 J vs tol 1e-06 MJ), not fuel physics.
    # NOTE: PHY-P1 bulk-CO2 >100% FIXED (F0 Plan B, 2026-07-07) — CO2 limiter
    # applied in GES doorway, GES delayed delivery, and ThermalSystem.  CO2
    # readings now plausible.  D2 WARNs (CO/CO2 ratio 0.58-0.72, 55 rows) were
    # CO concentration-pumping artifact; FIXED by specie pumping fix (2026-07-07)
    # — CO headroom limiter in GES doorway/delivery and ThermalSystem.  D2→0.
    # (measured post-F0 2026-07-07: A3:12, D2:55, D2PRE:~2929, E1:2, O2E1:190)
    # (measured post-specie-fix 2026-07-07: A3:12, D2:0, D2PRE:2996, E1:2, O2E1:190)
    "v4_co_remote_rooms": {"A3": 16, "D2PRE": 3500, "E1": 4, "O2E1": 240},
    # ILV-zombie family CTRL (coverage expansion 2026-07-06): post-flashover
    # FULLY_DEVELOPED at o2_upper=0.09% (A3, room 0, t=152-242s) with the
    # matching Thornton mismatch (O2E1, t=180-280s) and M1 D2PRE collateral.
    # Same lower-O2 reference bug; case runs without M4.
    # (measured 2026-07-06: A3:91, D2PRE:894, O2E1:101)
    "flashover_simple_house": {"A3": 115, "D2PRE": 1100, "O2E1": 130},
    # M1-family CTRL (coverage expansion 2026-07-06): 9-room two-storey smoke
    # transport case.  O2E1 only in the LAST 2 steps of the sim (t=299-300s,
    # residual 0.04-0.10 kg) — primary O2 accumulator under-counts vs Thornton
    # while M1 throttles the tracer (same Plan B family); D2PRE is the M1
    # multi-room divergence.  S1 (multi-floor smoke) is clean throughout —
    # that coverage is the purpose of this case.
    # (measured 2026-07-06: D2PRE:880, O2E1:2)
    "two_storey_smoke": {"D2PRE": 1100, "O2E1": 4},
    # ILV-zombie family CTRL (coverage expansion 2026-07-06): suppression →
    # reburn cycle ends in deep O2 depletion without M4; brief A3 zombie
    # window plus M1 D2PRE collateral.
    # (measured 2026-07-06: A3:4, D2PRE:2635)
    "v8_suppression_reburn": {"A3": 6, "D2PRE": 3200},
    # ILV-zombie + material-CO CTRL (coverage expansion 2026-07-06): PVC
    # curtain fuel objects — D2 (ratio 0.53-0.55, room 1, t=424-431s) is the
    # material CO yield under VC burst, same class as wood_vc_reference.
    # A3/O2E1/D2PRE are the ILV/M1 family (no M4).
    # (measured 2026-07-06: A3:10, D2:8, D2PRE:2399, O2E1:164)
    "pvc_curtain_hcl_release": {"A3": 14, "D2": 12, "D2PRE": 2900, "O2E1": 200},
    # ILV-zombie + material-CO CTRL (coverage expansion 2026-07-06): PU foam
    # sofa — D2 (ratio 0.58, room 1) is the material CO yield, same class as
    # wood_vc_reference.  A3/O2E1/D2PRE are the ILV/M1 family (no M4).
    # E1:1 is a DISCRETE INVENTORY WRITE-OFF at t=650s: solid_fuel_remaining
    # snaps down 2200.15 MJ to equal fuel_remaining after extinction (the two
    # fuel inventories diverged during the burn and reconcile without any
    # consumption accumulator entry).  Motor accounting item to diagnose —
    # same class as the HVAC species-instrumentation gap.
    # (measured 2026-07-06: A3:13, D2:8, D2PRE:3445, E1:1, O2E1:164)
    "victim_fed_incapacitation": {"A3": 17, "D2": 12, "D2PRE": 4200, "E1": 2, "O2E1": 200},
}


def envelope_violations(
    counts: dict[str, int], envelope: dict[str, int] | None
) -> list[str]:
    """Findings outside a CTRL envelope; empty list = within envelope.

    ``envelope=None`` means unlimited (legacy ad-hoc --intentional stems).
    """
    if envelope is None:
        return []
    violations: list[str] = []
    for rule, n in sorted(counts.items()):
        cap = envelope.get(rule)
        if cap is None:
            violations.append(f"{rule}:{n} (regla no registrada en el envelope)")
        elif n > cap:
            violations.append(f"{rule}:{n} > max {cap}")
    return violations


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
    # CTRL stems whose findings exceed their registered envelope: the case
    # gates (FAIL) even if the excess findings are WARN-severity.
    envelope_breaches: list[str] = field(default_factory=list)

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
    elif result.envelope_breaches:
        label = "FAIL"
        suffix = f"  (CTRL envelope excedido: {'; '.join(result.envelope_breaches)})"
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

    # CLI stems get an unlimited (legacy) envelope; registered stems use theirs.
    intentional_envelopes: dict[str, dict[str, int] | None] = {
        s.strip(): None for s in args.intentional.split(",") if s.strip()
    }
    intentional_envelopes.update(KNOWN_INTENTIONAL_CONTROLS)
    intentional_stems = set(intentional_envelopes)

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
        if path.stem in intentional_stems and result.finding_count > 0:
            breaches = envelope_violations(
                result.findings_by_rule(), intentional_envelopes[path.stem]
            )
            if breaches:
                result.envelope_breaches = breaches
            else:
                result.intentional = True
        results.append(result)
        _print_file_result(result, verbose=args.verbose)

    # Summary.  A CTRL whose findings exceed its envelope counts as dirty
    # even if the excess findings are WARN-severity: the envelope IS the gate.
    clean       = [r for r in results if r.finding_count == 0 and not r.error]
    intentional = [r for r in results if r.finding_count > 0 and not r.error and r.intentional]
    warn_only   = [r for r in results if r.fail_count == 0 and r.warn_count > 0 and not r.error
                   and not r.intentional and not r.envelope_breaches]
    dirty       = [r for r in results if (r.fail_count > 0 or r.envelope_breaches) and not r.error
                   and not r.intentional]
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
    breached = [r for r in dirty if r.envelope_breaches]
    if breached:
        print(f"  CTRL envelope excedido en {len(breached)} caso(s) — regresión sobre control conocido:")
        for r in breached:
            print(f"    {r.name}: {'; '.join(r.envelope_breaches)}")
    if errors:
        print(f"  ERROR: {len(errors):>3}")

    _print_top_worst(results, n=args.top_n)

    if dirty and not args.allow_findings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
