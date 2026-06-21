#!/usr/bin/env python3
"""Check ILV layer-coupling coherence in exported SimuFire CSV logs.

This is a diagnostic guardrail for the FP/ILV issue found on 2026-06-21:
high HRR or fuel-controlled regime while the upper layer is oxygen-starved and
the lower layer remains fresh. It does not run the simulator by itself; pass it
an exported sim_log.csv from scripts/run_scenario.py or the in-app graphs export.
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path


VENTILATION_LIMITED_REGIMES = {
    "VENTILATION_STRESSED",
    "VENTILATION_CONTROLLED_BURNING",
    "VENTILATION_INDUCED_GROWTH",
    "ILV_LATENT",
    "BACKDRAFT_RISK",
    "BACKDRAFT_EVENT",
}

FUEL_CONTROLLED_REGIMES = {
    "FUEL_CONTROLLED",
    "FULLY_DEVELOPED",
}


@dataclass(frozen=True)
class Finding:
    time_s: float
    room_id: str
    kind: str
    hrr_kw: float
    regime: str
    o2_upper: float
    o2_lower: float
    o2_hrr_factor: float
    visibility_m: float

    def format(self) -> str:
        return (
            f"t={self.time_s:.1f}s room={self.room_id} {self.kind}: "
            f"hrr={self.hrr_kw:.1f}kW regime={self.regime} "
            f"o2_upper={self.o2_upper * 100.0:.2f}% "
            f"o2_lower={self.o2_lower * 100.0:.2f}% "
            f"o2_hrr_factor={self.o2_hrr_factor:.3f} "
            f"visibility={self.visibility_m:.2f}m"
        )


def _float(row: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(row.get(key, default))
    except (TypeError, ValueError):
        return default


def find_ilv_layer_coherence_issues(
    rows: list[dict[str, str]],
    *,
    room_id: str | None = None,
    min_hrr_kw: float = 100.0,
    critical_o2_upper: float = 0.05,
    fresh_o2_lower: float = 0.15,
    high_o2_hrr_factor: float = 0.75,
) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        rid = row.get("room_id", "")
        if room_id is not None and rid != room_id:
            continue

        hrr_kw = _float(row, "hrr_kw")
        if hrr_kw < min_hrr_kw:
            continue

        regime = row.get("combustion_regime", "").strip()
        o2_upper = _float(row, "o2_upper", _float(row, "o2", 0.209))
        o2_lower = _float(row, "o2_lower", _float(row, "o2", 0.209))
        o2_hrr_factor = _float(row, "o2_hrr_factor", 1.0)
        visibility_m = _float(row, "visibility_m", 30.0)
        time_s = _float(row, "time_s")

        if o2_upper > critical_o2_upper:
            continue

        if regime in FUEL_CONTROLLED_REGIMES:
            findings.append(Finding(
                time_s,
                rid,
                "upper-O2-critical-but-regime-fuel-controlled",
                hrr_kw,
                regime,
                o2_upper,
                o2_lower,
                o2_hrr_factor,
                visibility_m,
            ))
            continue

        if o2_lower >= fresh_o2_lower and o2_hrr_factor >= high_o2_hrr_factor:
            findings.append(Finding(
                time_s,
                rid,
                "upper-O2-critical-but-HRR-throttle-high",
                hrr_kw,
                regime,
                o2_upper,
                o2_lower,
                o2_hrr_factor,
                visibility_m,
            ))

    return findings


def load_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect ILV layer-coupling incoherence in a SimuFire sim_log.csv."
    )
    parser.add_argument("csv", help="Path to sim_log.csv or validation CSV.")
    parser.add_argument("--room-id", default=None, help="Optional room_id filter.")
    parser.add_argument("--min-hrr-kw", type=float, default=100.0)
    parser.add_argument("--critical-o2-upper", type=float, default=0.05)
    parser.add_argument("--fresh-o2-lower", type=float, default=0.15)
    parser.add_argument("--high-o2-hrr-factor", type=float, default=0.75)
    parser.add_argument("--max-print", type=int, default=20)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"ERROR: CSV not found: {csv_path}", file=sys.stderr)
        return 2

    rows = load_rows(csv_path)
    findings = find_ilv_layer_coherence_issues(
        rows,
        room_id=args.room_id,
        min_hrr_kw=args.min_hrr_kw,
        critical_o2_upper=args.critical_o2_upper,
        fresh_o2_lower=args.fresh_o2_lower,
        high_o2_hrr_factor=args.high_o2_hrr_factor,
    )

    if not findings:
        scope = f"room_id={args.room_id}" if args.room_id is not None else "all rooms"
        print(f"ILV layer coherence PASS ({scope}, rows={len(rows)})")
        return 0

    print(f"ILV layer coherence FAIL: {len(findings)} suspicious row(s)")
    for finding in findings[:max(0, args.max_print)]:
        print("  " + finding.format())
    if len(findings) > args.max_print:
        print(f"  ... {len(findings) - args.max_print} more")
    return 1


if __name__ == "__main__":
    sys.exit(main())
