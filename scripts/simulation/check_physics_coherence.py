#!/usr/bin/env python3
"""Multi-parametric physical-coherence checker for SimuFire CSV logs.

Each rule encodes one invariant that must hold in every valid simulation,
regardless of scenario or configuration.  Rules skip gracefully when the
required columns are absent (older CSV schema).

Rules — first slice
-------------------
B1  Thermal inversion   temp_upper_c must not fall more than 10 °C below
                        temp_lower_c.  The upper (hot) layer is always warmer
                        than the lower (cool) layer in a two-zone model.

C1  FED arithmetic      fed == fed_co + fed_hcn + fed_hypoxia + fed_heat
                        (tolerance 0.001).  FED is defined as the sum of its
                        component integrals; any mismatch is an arithmetic bug.

C2  FED monotonicity    fed must never decrease (per room, ordered by time_s).
                        FED is a cumulative integral of dose — once accumulated,
                        dose cannot be "un-accumulated".

Rules — second slice
--------------------
A2  HRR without fuel    hrr_kw > 20 while fuel_remaining_MJ ≈ 0 and neither
                        fire_smoldering nor fire_latent_active is active.
                        A non-trivial fire cannot sustain itself with no fuel
                        and no latent combustion source.

A3  Regime/O2 mismatch  combustion_regime is FUEL_CONTROLLED or FULLY_DEVELOPED
                        while o2_upper < 0.05.  These regimes require an
                        adequately oxygenated combustion zone; critical upper-
                        layer O2 starvation is physically incompatible.

Usage
-----
  # Check all rules:
  python scripts/simulation/check_physics_coherence.py path/to/sim_log.csv

  # Restrict to specific rules:
  python scripts/simulation/check_physics_coherence.py path/to/sim_log.csv --rules C1,C2

  # Filter to one room:
  python scripts/simulation/check_physics_coherence.py path/to/sim_log.csv --room-id 0

Exit codes
----------
  0  No FAIL findings (WARN findings alone do not raise exit 1)
  1  One or more FAIL findings
  2  Invocation error (CSV not found, etc.)
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


# ---------------------------------------------------------------------------
# Finding
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Finding:
    time_s: float
    room_id: str
    rule_id: str
    severity: str   # "FAIL" | "WARN"
    metric: str
    value: float
    reason: str

    def format(self) -> str:
        return (
            f"t={self.time_s:.1f}s  room={self.room_id}  "
            f"[{self.rule_id}/{self.severity}]  "
            f"{self.metric}={self.value:.4g}  {self.reason}"
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _float(row: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        v = row.get(key, default)
        return float(v) if v not in (None, "", "nan") else default
    except (TypeError, ValueError):
        return default


def _has_cols(headers: set[str], required: set[str]) -> bool:
    return required.issubset(headers)


# ---------------------------------------------------------------------------
# Required columns per rule (used for graceful skip)
# ---------------------------------------------------------------------------

REQUIRED_COLS: dict[str, set[str]] = {
    "A2": {"hrr_kw", "fuel_remaining_MJ", "fire_smoldering", "fire_latent_active"},
    "A3": {"combustion_regime", "o2_upper"},
    "B1": {"temp_upper_c", "temp_lower_c"},
    "C1": {"fed", "fed_co", "fed_hcn", "fed_hypoxia", "fed_heat"},
    "C2": {"fed"},
}

ALL_RULES: tuple[str, ...] = ("A2", "A3", "B1", "C1", "C2")


# ---------------------------------------------------------------------------
# Rule A2 — HRR without fuel
# ---------------------------------------------------------------------------

_A2_HRR_MIN_KW = 20.0
_A2_FUEL_DEPLETED_MJ = 0.001


def _check_a2_hrr_no_fuel(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        hrr = _float(row, "hrr_kw")
        if hrr <= _A2_HRR_MIN_KW:
            continue
        fuel = _float(row, "fuel_remaining_MJ")
        if fuel >= _A2_FUEL_DEPLETED_MJ:
            continue
        smoldering = _float(row, "fire_smoldering")
        latent = _float(row, "fire_latent_active")
        if smoldering != 0.0 or latent != 0.0:
            continue
        findings.append(Finding(
            time_s=_float(row, "time_s"),
            room_id=row.get("room_id", "?").strip(),
            rule_id="A2",
            severity="FAIL",
            metric="hrr_without_fuel_kw",
            value=round(hrr, 3),
            reason=(
                f"hrr_kw={hrr:.1f} with fuel_remaining={fuel:.4f} MJ, "
                f"fire_smoldering=0, fire_latent_active=0"
            ),
        ))
    return findings


# ---------------------------------------------------------------------------
# Rule A3 — Regime/O2 upper mismatch
# ---------------------------------------------------------------------------

_A3_REGIMES_INCOHERENT: frozenset[str] = frozenset({"FUEL_CONTROLLED", "FULLY_DEVELOPED"})
_A3_O2_UPPER_CRITICAL = 0.05


def _check_a3_regime_o2_starvation(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        regime = row.get("combustion_regime", "").strip()
        if regime not in _A3_REGIMES_INCOHERENT:
            continue
        o2_upper = _float(row, "o2_upper", default=0.21)
        if o2_upper < _A3_O2_UPPER_CRITICAL:
            findings.append(Finding(
                time_s=_float(row, "time_s"),
                room_id=row.get("room_id", "?").strip(),
                rule_id="A3",
                severity="FAIL",
                metric="regime_o2_upper_starvation",
                value=round(o2_upper, 5),
                reason=(
                    f"combustion_regime={regime} while o2_upper={o2_upper:.4f} "
                    f"< {_A3_O2_UPPER_CRITICAL} (critical starvation threshold)"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Rule B1 — Thermal inversion
# ---------------------------------------------------------------------------

_B1_THRESHOLD_C = 10.0


def _check_b1_thermal_inversion(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        temp_upper = _float(row, "temp_upper_c")
        temp_lower = _float(row, "temp_lower_c")
        inversion = temp_lower - temp_upper      # positive = upper is colder
        if inversion > _B1_THRESHOLD_C:
            findings.append(Finding(
                time_s=_float(row, "time_s"),
                room_id=row.get("room_id", "?").strip(),
                rule_id="B1",
                severity="FAIL",
                metric="temp_inversion_c",
                value=round(inversion, 3),
                reason=(
                    f"temp_upper={temp_upper:.1f} C is {inversion:.1f} C "
                    f"below temp_lower={temp_lower:.1f} C"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Rule C1 — FED arithmetic
# ---------------------------------------------------------------------------

_C1_TOLERANCE = 0.001


def _check_c1_fed_sum(rows: list[dict[str, str]]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        fed = _float(row, "fed")
        if fed == 0.0:
            continue    # no dose accumulated yet — nothing to verify
        component_sum = (
            _float(row, "fed_co")
            + _float(row, "fed_hcn")
            + _float(row, "fed_hypoxia")
            + _float(row, "fed_heat")
        )
        diff = abs(fed - component_sum)
        if diff > _C1_TOLERANCE:
            findings.append(Finding(
                time_s=_float(row, "time_s"),
                room_id=row.get("room_id", "?").strip(),
                rule_id="C1",
                severity="FAIL",
                metric="fed_sum_error",
                value=round(diff, 6),
                reason=(
                    f"fed={fed:.5f} != "
                    f"fed_co+fed_hcn+fed_hypoxia+fed_heat={component_sum:.5f}"
                ),
            ))
    return findings


# ---------------------------------------------------------------------------
# Rule C2 — FED monotonicity
# ---------------------------------------------------------------------------

_C2_TOLERANCE = 0.0005


def _check_c2_fed_monotone(rows: list[dict[str, str]]) -> list[Finding]:
    by_room: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_room[row.get("room_id", "?").strip()].append(row)

    findings: list[Finding] = []
    for room_id, room_rows in by_room.items():
        room_rows.sort(key=lambda r: _float(r, "time_s"))
        prev_fed = -1.0
        for row in room_rows:
            fed = _float(row, "fed")
            if prev_fed >= 0.0 and fed < prev_fed - _C2_TOLERANCE:
                delta = fed - prev_fed
                findings.append(Finding(
                    time_s=_float(row, "time_s"),
                    room_id=room_id,
                    rule_id="C2",
                    severity="FAIL",
                    metric="fed_decrement",
                    value=round(delta, 6),
                    reason=f"FED decreased {prev_fed:.5f} -> {fed:.5f} (delta={delta:.5f})",
                ))
            prev_fed = fed
    return findings


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def find_physics_coherence_issues(
    rows: list[dict[str, str]],
    *,
    rule_ids: set[str] | None = None,
    room_id: str | None = None,
) -> list[Finding]:
    """Run enabled coherence rules on *rows* and return findings.

    Parameters
    ----------
    rows:
        CSV rows as dicts (from csv.DictReader or load_rows).
    rule_ids:
        Which rules to run.  None means all rules in ALL_RULES.
    room_id:
        If given, restrict analysis to this room.
    """
    if not rows:
        return []

    if room_id is not None:
        rows = [r for r in rows if r.get("room_id", "").strip() == room_id]
        if not rows:
            return []

    headers: set[str] = set(rows[0].keys())
    active: set[str] = set(ALL_RULES) if rule_ids is None else (rule_ids & set(ALL_RULES))

    findings: list[Finding] = []

    if "A2" in active and _has_cols(headers, REQUIRED_COLS["A2"]):
        findings.extend(_check_a2_hrr_no_fuel(rows))
    if "A3" in active and _has_cols(headers, REQUIRED_COLS["A3"]):
        findings.extend(_check_a3_regime_o2_starvation(rows))
    if "B1" in active and _has_cols(headers, REQUIRED_COLS["B1"]):
        findings.extend(_check_b1_thermal_inversion(rows))
    if "C1" in active and _has_cols(headers, REQUIRED_COLS["C1"]):
        findings.extend(_check_c1_fed_sum(rows))
    if "C2" in active and _has_cols(headers, REQUIRED_COLS["C2"]):
        findings.extend(_check_c2_fed_monotone(rows))

    return findings


def load_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check multi-parametric physical coherence in a SimuFire CSV log."
    )
    parser.add_argument("csv", help="Path to sim_log.csv or validation CSV.")
    parser.add_argument("--room-id", default=None, help="Restrict to this room_id.")
    parser.add_argument(
        "--rules",
        default=None,
        metavar="IDS",
        help="Comma-separated rule IDs (default: all).  Example: --rules C1,C2",
    )
    parser.add_argument(
        "--max-print", type=int, default=20,
        help="Max findings to print (default: 20).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"ERROR: CSV not found: {csv_path}", file=sys.stderr)
        return 2

    rule_ids: set[str] | None = None
    if args.rules:
        rule_ids = {r.strip().upper() for r in args.rules.split(",") if r.strip()}

    rows = load_rows(csv_path)
    findings = find_physics_coherence_issues(rows, rule_ids=rule_ids, room_id=args.room_id)

    if not findings:
        scope = f"room_id={args.room_id}" if args.room_id is not None else "all rooms"
        print(f"Physics coherence PASS ({scope}, rows={len(rows)})")
        return 0

    fails = [f for f in findings if f.severity == "FAIL"]
    warns = [f for f in findings if f.severity == "WARN"]
    print(f"Physics coherence: {len(fails)} FAIL, {len(warns)} WARN")
    for finding in findings[:args.max_print]:
        print("  " + finding.format())
    if len(findings) > args.max_print:
        print(f"  ... {len(findings) - args.max_print} more")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
