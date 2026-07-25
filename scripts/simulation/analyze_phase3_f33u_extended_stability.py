#!/usr/bin/env python3
"""Evaluate F3.3u coupled-plume stability through the 590 s CFAST horizon."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33r2c_correspondence as f33r2c
from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import analyze_phase3_f33t_coupled_plume as f33t


HORIZONS = (180, 300, 590)
REQUIRED_PROJECTIONS = (
    ("cfast_chain_r0_t180_temp_upper_c", 180, "phase3_shadow_thermo_temp_upper_c"),
    ("cfast_chain_r0_t300_temp_upper_c", 300, "phase3_shadow_thermo_temp_upper_c"),
    ("cfast_chain_r0_t600_temp_upper_c", 600, "phase3_shadow_thermo_temp_upper_c"),
    ("cfast_chain_r0_o2_t600_o2", 600, "phase3_shadow_persistent_post_upper_o2_fraction"),
)


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def _read_reference_checks(path: Path) -> dict[str, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {str(item["name"]): item for item in payload["checks"]}


def _room_rows(path: Path, room_id: int = 0) -> dict[int, dict[str, str]]:
    rows = f33r2c.read_rows(path)
    return {
        round(_number(row.get("time_s"))): row
        for row in rows
        if int(_number(row.get("room_id"), -1.0)) == room_id
    }


def _prefix_equal(
    short_csv: Path, long_csv: Path, horizon_s: int
) -> bool:
    short_rows = f33r2c.read_rows(short_csv)
    long_rows = [
        row
        for row in f33r2c.read_rows(long_csv)
        if _number(row.get("time_s")) <= horizon_s + 1.0e-6
    ]
    return short_rows == long_rows


def _finite_zone_state(rows: dict[int, dict[str, str]]) -> bool:
    fields = (
        "phase3_shadow_upper_gas_kg",
        "phase3_shadow_lower_gas_kg",
        "phase3_shadow_thermo_temp_upper_c",
        "phase3_shadow_thermo_temp_lower_c",
        "phase3_shadow_thermo_interface_m",
        "phase3_shadow_persistent_post_upper_o2_fraction",
        "phase3_shadow_persistent_post_lower_o2_fraction",
    )
    return all(
        math.isfinite(_number(row.get(field)))
        for time_s, row in rows.items()
        if time_s >= 10
        for field in fields
    )


def _zone_minima(rows: dict[int, dict[str, str]]) -> dict[str, float]:
    active = [row for time_s, row in rows.items() if time_s >= 10]
    return {
        "upper_gas_kg": min(
            _number(row.get("phase3_shadow_upper_gas_kg")) for row in active
        ),
        "lower_gas_kg": min(
            _number(row.get("phase3_shadow_lower_gas_kg")) for row in active
        ),
        "upper_o2_fraction": min(
            _number(
                row.get("phase3_shadow_persistent_post_upper_o2_fraction")
            )
            for row in active
        ),
        "lower_o2_fraction": min(
            _number(
                row.get("phase3_shadow_persistent_post_lower_o2_fraction")
            )
            for row in active
        ),
    }


def _required_projection(
    rows: dict[int, dict[str, str]],
    reference_checks: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    projected: dict[str, dict[str, Any]] = {}
    for name, checkpoint, field in REQUIRED_PROJECTIONS:
        check = reference_checks[name]
        actual = _number(rows[checkpoint].get(field))
        expected = _number(check.get("expected"))
        tolerance = _number(check.get("tolerance"))
        projected[name] = {
            "checkpoint_s": checkpoint,
            "field": field,
            "actual": actual,
            "expected": expected,
            "tolerance": tolerance,
            "error": actual - expected,
            "pass": abs(actual - expected) <= tolerance,
        }
    return projected


def _late_hrr_owner(
    rows: dict[int, dict[str, str]],
    cfast_zone_rows: list[dict[str, str]],
    checkpoint_s: int = 590,
) -> dict[str, Any]:
    row = rows[checkpoint_s]
    cfast_row = f33m._row_at(cfast_zone_rows, checkpoint_s)
    legacy_hrr = _number(
        row.get("phase3_shadow_combustion_legacy_hrr_kw")
    )
    accepted_hrr = _number(
        row.get("phase3_shadow_combustion_accepted_hrr_kw")
    )
    canonical_factor = _number(
        row.get("phase3_shadow_combustion_canonical_o2_hrr_factor")
    )
    legacy_factor = _number(
        row.get("phase3_shadow_combustion_legacy_o2_hrr_factor")
    )
    decision_fraction = _number(
        row.get("phase3_shadow_combustion_decision_fraction")
    )
    cfast_hrr = _number(cfast_row.get("HRR_1"))
    proposal_limited_upstream = (
        abs(accepted_hrr - legacy_hrr) <= 1.0e-6
        and decision_fraction >= 0.999
        and canonical_factor > legacy_factor
        and cfast_hrr > accepted_hrr + 1.0
    )
    return {
        "checkpoint_s": checkpoint_s,
        "legacy_proposal_hrr_kw": legacy_hrr,
        "canonical_accepted_hrr_kw": accepted_hrr,
        "cfast_hrr_kw": cfast_hrr,
        "canonical_o2_hrr_factor": canonical_factor,
        "legacy_o2_hrr_factor": legacy_factor,
        "decision_fraction": decision_fraction,
        "proposal_limited_upstream": proposal_limited_upstream,
    }


def build_report(
    off_csv: Path,
    on_csv: Path,
    off_manifest: Path,
    on_manifest: Path,
    off_180_csv: Path,
    on_180_csv: Path,
    off_300_csv: Path,
    on_300_csv: Path,
    cfast_zone: Path,
    cfast_compartments: Path,
    cfast_masses: Path,
    reference_checks_path: Path,
) -> dict[str, Any]:
    horizons: dict[str, Any] = {}
    for horizon in HORIZONS:
        horizons[str(horizon)] = f33t.build_report(
            off_csv=off_csv,
            on_csv=on_csv,
            off_manifest=off_manifest,
            on_manifest=on_manifest,
            cfast_zone=cfast_zone,
            cfast_compartments=cfast_compartments,
            cfast_masses=cfast_masses,
            baseline_csv=None,
            checkpoints=tuple(range(10, horizon + 1, 10)),
        )
    on_rows = _room_rows(on_csv)
    prefix_checks = {
        "off_180": _prefix_equal(off_180_csv, off_csv, 180),
        "on_180": _prefix_equal(on_180_csv, on_csv, 180),
        "off_300": _prefix_equal(off_300_csv, off_csv, 300),
        "on_300": _prefix_equal(on_300_csv, on_csv, 300),
    }
    minima = _zone_minima(on_rows)
    finite = _finite_zone_state(on_rows)
    positive_zones = (
        minima["upper_gas_kg"] > 0.0 and minima["lower_gas_kg"] > 0.0
    )
    reference_checks = _read_reference_checks(reference_checks_path)
    projections = _required_projection(on_rows, reference_checks)
    late_hrr_owner = _late_hrr_owner(
        on_rows, f33m.read_cfast_zone(cfast_zone)
    )
    horizons_pass = all(
        report["all_metrics_improved"] and report["ledger_pass"]
        for report in horizons.values()
    )
    stability_pass = (
        horizons_pass
        and all(prefix_checks.values())
        and finite
        and positive_zones
    )
    return {
        "off_csv": str(off_csv),
        "on_csv": str(on_csv),
        "horizons": horizons,
        "prefix_determinism": prefix_checks,
        "finite_zone_state": finite,
        "positive_zone_inventory": positive_zones,
        "zone_minima": minima,
        "required_projections": projections,
        "late_hrr_owner": late_hrr_owner,
        "all_required_projections_pass": all(
            item["pass"] for item in projections.values()
        ),
        "stability_gate_pass": stability_pass,
        "runtime_authority": "NO-GO",
        "group_c_retirement": "NO-GO",
        "next_owner": "late canonical O2-to-HRR coupling",
    }


def print_report(report: dict[str, Any]) -> None:
    print("F3.3u extended coupled-plume stability gate")
    print("horizon  metrics improved  ledger pass  max residual")
    for horizon, item in report["horizons"].items():
        max_residual = max(item["max_residuals"].values(), default=0.0)
        print(
            f"{horizon:>7s}  "
            f"{str(item['all_metrics_improved']):>16s}  "
            f"{str(item['ledger_pass']):>11s}  "
            f"{max_residual:.3g}"
        )
    print("prefix determinism:", all(report["prefix_determinism"].values()))
    print("finite zone state:", report["finite_zone_state"])
    print("positive zone inventory:", report["positive_zone_inventory"])
    print("required projections:")
    for name, item in report["required_projections"].items():
        verdict = "PASS" if item["pass"] else "FAIL"
        print(
            f"  {verdict:4s} {name}: {item['actual']:.6g} vs "
            f"{item['expected']:.6g} +/- {item['tolerance']:.6g}"
        )
    print(
        "stability gate:",
        "PASS" if report["stability_gate_pass"] else "FAIL",
    )
    owner = report["late_hrr_owner"]
    print(
        "late HRR owner: legacy proposal "
        f"{owner['legacy_proposal_hrr_kw']:.3f} kW, canonical decision "
        f"{owner['decision_fraction']:.3f}, CFAST {owner['cfast_hrr_kw']:.3f} kW"
    )
    print("runtime authority: NO-GO")
    print("Group C retirement: NO-GO")
    print("next owner:", report["next_owner"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    run_dir = ROOT / "runs" / "phase3_f33u"
    f33t_dir = ROOT / "runs" / "phase3_f33t"
    cfast_dir = ROOT / "sim" / "validation" / "cfast"
    parser.add_argument(
        "--off-csv", type=Path, default=run_dir / "600_off" / "sim_log.csv"
    )
    parser.add_argument(
        "--on-csv", type=Path, default=run_dir / "600_on" / "sim_log.csv"
    )
    parser.add_argument(
        "--off-manifest",
        type=Path,
        default=run_dir / "600_off" / "run_manifest.json",
    )
    parser.add_argument(
        "--on-manifest",
        type=Path,
        default=run_dir / "600_on" / "run_manifest.json",
    )
    parser.add_argument(
        "--off-180-csv",
        type=Path,
        default=f33t_dir / "180_off" / "sim_log.csv",
    )
    parser.add_argument(
        "--on-180-csv",
        type=Path,
        default=f33t_dir / "180_on" / "sim_log.csv",
    )
    parser.add_argument(
        "--off-300-csv",
        type=Path,
        default=run_dir / "300_off" / "sim_log.csv",
    )
    parser.add_argument(
        "--on-300-csv",
        type=Path,
        default=run_dir / "300_on" / "sim_log.csv",
    )
    parser.add_argument(
        "--cfast-zone",
        type=Path,
        default=cfast_dir / "cfast_corridor_chain_zone.csv",
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=cfast_dir / "cfast_corridor_chain_compartments.csv",
    )
    parser.add_argument(
        "--cfast-masses",
        type=Path,
        default=cfast_dir / "cfast_corridor_chain_masses.csv",
    )
    parser.add_argument(
        "--reference-checks",
        type=Path,
        default=ROOT / "sim" / "validation" / "reports" / "reference_checks.json",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    report = build_report(
        args.off_csv,
        args.on_csv,
        args.off_manifest,
        args.on_manifest,
        args.off_180_csv,
        args.on_180_csv,
        args.off_300_csv,
        args.on_300_csv,
        args.cfast_zone,
        args.cfast_compartments,
        args.cfast_masses,
        args.reference_checks,
    )
    print_report(report)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0 if report["stability_gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
