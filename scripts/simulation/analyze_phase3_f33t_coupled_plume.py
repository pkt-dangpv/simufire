#!/usr/bin/env python3
"""Evaluate the F3.3t coupled-plume 0-180 s STOP gate."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import analyze_phase3_f33r2c_correspondence as f33r2c
from scripts.simulation import analyze_phase3_f33s_layer_mass_o2 as f33s


CHECKPOINTS = tuple(range(10, 181, 10))
LEDGER_TOLERANCE = 1.0e-6
RESIDUAL_COLUMNS = (
    "phase3_shadow_combustion_o2_residual_kg",
    "phase3_shadow_combustion_energy_residual_kj",
    "phase3_shadow_combustion_species_residual_kg",
    "phase3_shadow_combustion_radiative_route_residual_kj",
    "phase3_shadow_combustion_fire_partition_residual_kj",
    "phase3_shadow_mass_residence_upper_residual_kg",
    "phase3_shadow_mass_residence_lower_residual_kg",
    "phase3_shadow_mass_residence_room_residual_kg",
    "phase3_shadow_mass_residence_building_residual_kg",
    "phase3_shadow_multisurface_cumulative_energy_residual_kj",
    "phase3_shadow_multisurface_cumulative_solver_residual_kj",
)


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def _rmse(values: list[float]) -> float:
    if not values:
        raise ValueError("cannot calculate RMSE for an empty series")
    return math.sqrt(sum(value * value for value in values) / len(values))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _sim_rows(path: Path) -> list[dict[str, str]]:
    return f33r2c.read_rows(path)


def _sim_room_rows(
    rows: list[dict[str, str]], room_id: int = 0
) -> dict[int, dict[str, str]]:
    return {
        round(_number(row.get("time_s"))): row
        for row in rows
        if int(_number(row.get("room_id"), -1.0)) == room_id
    }


def _checkpoint_errors(
    audit: dict[str, Any],
    sim_by_time: dict[int, dict[str, str]],
    cfast_zone_rows: list[dict[str, str]],
    checkpoints: tuple[int, ...] = CHECKPOINTS,
) -> dict[str, list[float]]:
    errors = {
        "upper_mass_kg": [],
        "lower_mass_kg": [],
        "interface_m": [],
        "upper_temp_c": [],
        "lower_temp_c": [],
        "upper_o2_fraction": [],
        "lower_o2_fraction": [],
        "hrr_kw": [],
        "plume_rate_kg_s": [],
    }
    for checkpoint in checkpoints:
        item = audit["checkpoints"][str(checkpoint)]
        sim_row = sim_by_time[checkpoint]
        cfast_row = f33m._row_at(cfast_zone_rows, checkpoint)
        errors["upper_mass_kg"].append(_number(item["upper_mass_error_kg"]))
        errors["lower_mass_kg"].append(_number(item["lower_mass_error_kg"]))
        errors["interface_m"].append(_number(item["interface_error_m"]))
        errors["upper_temp_c"].append(
            _number(sim_row.get("phase3_shadow_thermo_temp_upper_c"))
            - _number(cfast_row.get("ULT_1"))
        )
        errors["lower_temp_c"].append(
            _number(sim_row.get("phase3_shadow_thermo_temp_lower_c"))
            - _number(cfast_row.get("LLT_1"))
        )
        errors["upper_o2_fraction"].append(
            _number(
                sim_row.get(
                    "phase3_shadow_persistent_post_upper_o2_fraction"
                )
            )
            - _number(item["cfast_upper_o2_fraction"])
        )
        errors["lower_o2_fraction"].append(
            _number(
                sim_row.get(
                    "phase3_shadow_persistent_post_lower_o2_fraction"
                )
            )
            - _number(item["cfast_lower_o2_fraction"])
        )
        errors["hrr_kw"].append(
            _number(item["sim_accepted_hrr_kw"])
            - _number(item["cfast_hrr_kw"])
        )
        errors["plume_rate_kg_s"].append(
            _number(item["accepted_plume_rate_kg_s"])
            - _number(item["cfast_plume_rate_kg_s"])
        )
    return errors


def _max_residuals(rows: list[dict[str, str]]) -> dict[str, float]:
    return {
        column: max(abs(_number(row.get(column))) for row in rows)
        for column in RESIDUAL_COLUMNS
    }


def build_report(
    off_csv: Path,
    on_csv: Path,
    off_manifest: Path,
    on_manifest: Path,
    cfast_zone: Path,
    cfast_compartments: Path,
    cfast_masses: Path,
    baseline_csv: Path | None = None,
    checkpoints: tuple[int, ...] = CHECKPOINTS,
) -> dict[str, Any]:
    off_audit = f33s.build_audit(
        candidate_csv=off_csv,
        manifest_path=off_manifest,
        cfast_zone_path=cfast_zone,
        cfast_compartments_path=cfast_compartments,
        cfast_masses_path=cfast_masses,
        checkpoints=checkpoints,
    )
    on_audit = f33s.build_audit(
        candidate_csv=on_csv,
        manifest_path=on_manifest,
        cfast_zone_path=cfast_zone,
        cfast_compartments_path=cfast_compartments,
        cfast_masses_path=cfast_masses,
        checkpoints=checkpoints,
    )
    off_rows = _sim_rows(off_csv)
    on_rows = _sim_rows(on_csv)
    cfast_zone_rows = f33m.read_cfast_zone(cfast_zone)
    off_errors = _checkpoint_errors(
        off_audit, _sim_room_rows(off_rows), cfast_zone_rows, checkpoints
    )
    on_errors = _checkpoint_errors(
        on_audit, _sim_room_rows(on_rows), cfast_zone_rows, checkpoints
    )
    metrics: dict[str, dict[str, float | bool]] = {}
    for name in off_errors:
        off_rmse = _rmse(off_errors[name])
        on_rmse = _rmse(on_errors[name])
        metrics[name] = {
            "off_rmse": off_rmse,
            "on_rmse": on_rmse,
            "improvement_fraction": (
                1.0 - on_rmse / off_rmse if off_rmse > 0.0 else 0.0
            ),
            "improved": on_rmse < off_rmse,
            "off_final_error": off_errors[name][-1],
            "on_final_error": on_errors[name][-1],
        }
    residuals = _max_residuals(on_rows)
    ledger_pass = max(residuals.values(), default=0.0) <= LEDGER_TOLERANCE
    off_exact = (
        _sha256(off_csv) == _sha256(baseline_csv)
        if baseline_csv is not None
        else None
    )
    all_metrics_improved = all(
        bool(metric["improved"]) for metric in metrics.values()
    )
    return {
        "off_csv": str(off_csv),
        "on_csv": str(on_csv),
        "baseline_csv": str(baseline_csv) if baseline_csv else None,
        "off_byte_identical_to_baseline": off_exact,
        "metrics": metrics,
        "max_residuals": residuals,
        "ledger_tolerance": LEDGER_TOLERANCE,
        "ledger_pass": ledger_pass,
        "all_metrics_improved": all_metrics_improved,
        "stop_gate_pass": (
            all_metrics_improved
            and ledger_pass
            and off_exact is not False
        ),
        "runtime_authority": "NO-GO",
        "group_c_retirement": "NO-GO",
    }


def print_report(report: dict[str, Any]) -> None:
    print("F3.3t coupled-plume STOP gate")
    print("metric                 OFF RMSE     ON RMSE   improvement")
    for name, metric in report["metrics"].items():
        print(
            f"{name:22s} "
            f"{metric['off_rmse']:10.4f} "
            f"{metric['on_rmse']:11.4f} "
            f"{100.0 * metric['improvement_fraction']:10.1f}%"
        )
    print(
        "OFF byte-identical:",
        report["off_byte_identical_to_baseline"],
    )
    print("ledger pass:", report["ledger_pass"])
    print("STOP gate:", "PASS" if report["stop_gate_pass"] else "FAIL")
    print("runtime authority: NO-GO")
    print("Group C retirement: NO-GO")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    run_dir = ROOT / "runs" / "phase3_f33t"
    cfast_dir = ROOT / "sim" / "validation" / "cfast"
    parser.add_argument(
        "--off-csv", type=Path, default=run_dir / "180_off" / "sim_log.csv"
    )
    parser.add_argument(
        "--on-csv", type=Path, default=run_dir / "180_on" / "sim_log.csv"
    )
    parser.add_argument(
        "--off-manifest",
        type=Path,
        default=run_dir / "180_off" / "run_manifest.json",
    )
    parser.add_argument(
        "--on-manifest",
        type=Path,
        default=run_dir / "180_on" / "run_manifest.json",
    )
    parser.add_argument(
        "--baseline-csv",
        type=Path,
        default=ROOT
        / "runs"
        / "phase3_f33r2d"
        / "180_corridor_cfast"
        / "sim_log.csv",
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
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    report = build_report(
        args.off_csv,
        args.on_csv,
        args.off_manifest,
        args.on_manifest,
        args.cfast_zone,
        args.cfast_compartments,
        args.cfast_masses,
        args.baseline_csv,
    )
    print_report(report)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0 if report["stop_gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
