#!/usr/bin/env python3
"""Compare LayerInterfaceModel physical regression artifacts.

This audit tool compares before/after CSV time series when available and falls
back to CaseRunner JSON reports for legacy cases that did not export CSV. It
also runs structural checks for the canonical layer/interface contract so that
architectural regressions are visible even when final metrics look unchanged.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import io
import json
import math
import re
import subprocess
from bisect import bisect_left
from pathlib import Path
from typing import Any


DEFAULT_CASES = [
    "layer_interface_single_room_window",
    "cfast_r0_window_360",
    "living_room_hallway",
    "v4_co_remote_rooms",
]

AUDIT_FIELDS = [
    "hrr_kw",
    "o2",
    "o2_upper",
    "o2_lower",
    "co_ppm",
    "co2_ppm",
    "hcn_ppm",
    "visible_smoke_layer_m",
    "thermal_layer_m",
    "flow_interface_m",
    "layer_150c_m",
    "visibility_m",
    "fed",
    "temp_upper_c",
    "temp_lower_c",
]

TARGET_TIMES_S = [60.0, 120.0, 180.0]

RELATIVE_FLOORS = {
    "hrr_kw": 1.0,
    "o2": 0.001,
    "o2_upper": 0.001,
    "o2_lower": 0.001,
    "co_ppm": 1.0,
    "co2_ppm": 1.0,
    "hcn_ppm": 0.1,
    "visible_smoke_layer_m": 0.01,
    "thermal_layer_m": 0.01,
    "flow_interface_m": 0.01,
    "layer_150c_m": 0.01,
    "visibility_m": 0.1,
    "fed": 0.001,
    "temp_upper_c": 1.0,
    "temp_lower_c": 1.0,
}

WARNING_LIMITS = {
    "hrr_kw": {"metric": "max_rel_delta", "threshold": 0.05, "label": "HRR > 5%"},
    "o2": {"metric": "max_abs_delta", "threshold": 0.01, "label": "O2 > 0.01 abs"},
    "o2_upper": {"metric": "max_abs_delta", "threshold": 0.01, "label": "O2 upper > 0.01 abs"},
    "o2_lower": {"metric": "max_abs_delta", "threshold": 0.01, "label": "O2 lower > 0.01 abs"},
    "co_ppm": {"metric": "max_rel_delta", "threshold": 0.10, "label": "CO > 10%"},
    "co2_ppm": {"metric": "max_rel_delta", "threshold": 0.10, "label": "CO2 > 10%"},
    "hcn_ppm": {"metric": "max_rel_delta", "threshold": 0.10, "label": "HCN > 10%"},
    "fed": {"metric": "max_rel_delta", "threshold": 0.10, "label": "FED > 10%"},
    "visibility_m": {"metric": "max_rel_delta", "threshold": 0.15, "label": "Visibility > 15%"},
}

REPORT_KEYS = {
    "hrr_kw": {"peak": "peak_hrr_kw", "final": "final_hrr_kw"},
    "o2": {"final": "final_o2"},
    "o2_upper": {"min": "min_o2_upper", "final": "final_o2_upper"},
    "o2_lower": {"final": "final_o2_lower"},
    "co_ppm": {"peak": "peak_co_ppm", "final": "final_co_ppm"},
    "co2_ppm": {"peak": "peak_co2_ppm", "final": "final_co2_ppm"},
    "hcn_ppm": {"peak": "peak_hcn_ppm", "final": "final_hcn_ppm"},
    "visible_smoke_layer_m": {
        "min": "min_visible_smoke_layer_m",
        "final": "final_visible_smoke_layer_m",
    },
    "thermal_layer_m": {"min": "min_thermal_layer_m", "final": "final_thermal_layer_m"},
    "flow_interface_m": {"min": "min_flow_interface_m", "final": "final_flow_interface_m"},
    "layer_150c_m": {"min": "min_l150_m", "final": "final_layer_150c_m"},
    "visibility_m": {"min": "min_visibility_m", "final": "final_visibility_m"},
    "fed": {"peak": "max_fed", "final": "final_fed"},
    "temp_upper_c": {"peak": "peak_temp_upper_c", "final": "final_temp_upper_raw_c"},
    "temp_lower_c": {"final": "final_temp_at_0_9m_c"},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare LayerInterfaceModel before/after regression artifacts."
    )
    parser.add_argument("--repo-root", default=".", help="Repository root. Defaults to cwd.")
    parser.add_argument("--before-dir", default="", help="Directory with before JSON/CSV artifacts.")
    parser.add_argument("--after-dir", default="sim/validation/reports", help="Directory with after JSON/CSV artifacts.")
    parser.add_argument(
        "--before-git-ref",
        default="",
        help="Git ref used as before source for tracked reports, e.g. HEAD.",
    )
    parser.add_argument("--case", action="append", default=[], help="Case name. Can be repeated.")
    parser.add_argument("--cases", default="", help="Comma-separated case names.")
    parser.add_argument(
        "--out-md",
        default="docs/LAYER_INTERFACE_REGRESSION_AUDIT.md",
        help="Markdown report output path.",
    )
    parser.add_argument(
        "--out-json",
        default="sim/validation/reports/layer_interface_regression/audit.json",
        help="Machine-readable JSON output path.",
    )
    parser.add_argument(
        "--skip-structural-checks",
        action="store_true",
        help="Only compare artifacts; do not inspect source-code contracts.",
    )
    parser.add_argument(
        "--strict-exit",
        action="store_true",
        help="Exit 1 when conclusion is FAIL; default is report-only exit 0.",
    )
    return parser.parse_args()


def normalize_cases(args: argparse.Namespace) -> list[str]:
    cases = list(args.case)
    if args.cases.strip():
        cases.extend(part.strip() for part in args.cases.split(",") if part.strip())
    if not cases:
        cases = list(DEFAULT_CASES)
    seen: set[str] = set()
    result: list[str] = []
    for case in cases:
        if case and case not in seen:
            result.append(case)
            seen.add(case)
    return result


def read_json_file(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return None


def read_git_text(repo_root: Path, ref: str, rel_path: str) -> str | None:
    if not ref:
        return None
    proc = subprocess.run(
        ["git", "show", f"{ref}:{rel_path.replace(chr(92), '/')}"],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return proc.stdout


def load_json_artifact(repo_root: Path, directory: Path | None, case: str, git_ref: str = "") -> dict[str, Any] | None:
    if directory is not None:
        json_path = directory / f"{case}.json"
        report = read_json_file(json_path)
        if report is not None:
            return report
    if git_ref:
        text = read_git_text(repo_root, git_ref, f"sim/validation/reports/{case}.json")
        if text:
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return None
    return None


def parse_csv_text(text: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    reader = csv.DictReader(io.StringIO(text))
    for raw in reader:
        row: dict[str, Any] = {}
        for key, value in raw.items():
            if key is None:
                continue
            if value is None:
                row[key] = None
                continue
            value = value.strip()
            if key in {"room_name"}:
                row[key] = value
            else:
                row[key] = safe_float(value)
        rows.append(row)
    return rows


def load_csv_artifact(repo_root: Path, directory: Path | None, case: str, git_ref: str = "") -> list[dict[str, Any]] | None:
    if directory is not None:
        csv_path = directory / f"{case}.csv"
        if csv_path.exists():
            try:
                return parse_csv_text(csv_path.read_text(encoding="utf-8-sig"))
            except OSError:
                return None
    if git_ref:
        text = read_git_text(repo_root, git_ref, f"sim/validation/reports/{case}.csv")
        if text:
            return parse_csv_text(text)
    return None


def safe_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(result) or math.isinf(result):
        return None
    return result


def rel_delta(before: float, after: float, field: str) -> float:
    floor = RELATIVE_FLOORS.get(field, 1e-9)
    return abs(after - before) / max(abs(before), floor)


def group_csv_by_room(rows: list[dict[str, Any]] | None) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    if not rows:
        return grouped
    for row in rows:
        room_id = row.get("room_id")
        if room_id is None:
            continue
        room_key = str(int(room_id)) if isinstance(room_id, float) and room_id.is_integer() else str(room_id)
        grouped.setdefault(room_key, []).append(row)
    for room_rows in grouped.values():
        room_rows.sort(key=lambda item: float(item.get("time_s") or 0.0))
    return grouped


def series_for_field(rows: list[dict[str, Any]], field: str) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    for row in rows:
        t = safe_float(row.get("time_s"))
        v = safe_float(row.get(field))
        if t is None or v is None:
            continue
        result.append((t, v))
    return result


def nearest_value(series: list[tuple[float, float]], target_s: float) -> tuple[float, float] | None:
    if not series:
        return None
    times = [item[0] for item in series]
    index = bisect_left(times, target_s)
    candidates: list[tuple[float, float]] = []
    if index < len(series):
        candidates.append(series[index])
    if index > 0:
        candidates.append(series[index - 1])
    if not candidates:
        return None
    return min(candidates, key=lambda item: abs(item[0] - target_s))


def median_step_s(series: list[tuple[float, float]]) -> float:
    if len(series) < 2:
        return 1.0
    steps = sorted(
        abs(series[i][0] - series[i - 1][0])
        for i in range(1, len(series))
        if abs(series[i][0] - series[i - 1][0]) > 1e-9
    )
    if not steps:
        return 1.0
    return steps[len(steps) // 2]


def compare_csv_series(
    before_rows: list[dict[str, Any]],
    after_rows: list[dict[str, Any]],
    field: str,
) -> dict[str, Any] | None:
    before_series = series_for_field(before_rows, field)
    after_series = series_for_field(after_rows, field)
    if not before_series or not after_series:
        return None

    tolerance_s = max(0.5, median_step_s(before_series), median_step_s(after_series)) * 0.51
    pairs: list[tuple[float, float, float]] = []
    for t_before, v_before in before_series:
        match = nearest_value(after_series, t_before)
        if match is None:
            continue
        t_after, v_after = match
        if abs(t_after - t_before) <= tolerance_s:
            pairs.append((t_before, v_before, v_after))

    if not pairs:
        return None

    abs_deltas = [abs(after - before) for _, before, after in pairs]
    rel_deltas = [rel_delta(before, after, field) for _, before, after in pairs]
    target_deltas: dict[str, float | None] = {}
    for target_s in TARGET_TIMES_S:
        before_at = nearest_value(before_series, target_s)
        after_at = nearest_value(after_series, target_s)
        if before_at is None or after_at is None:
            target_deltas[f"delta_at_{int(target_s)}s"] = None
        else:
            target_deltas[f"delta_at_{int(target_s)}s"] = after_at[1] - before_at[1]

    peak_before_t, peak_before_v = max(before_series, key=lambda item: item[1])
    peak_after_t, peak_after_v = max(after_series, key=lambda item: item[1])
    return {
        "source": "csv",
        "sample_count": len(pairs),
        "max_abs_delta": max(abs_deltas),
        "max_rel_delta": max(rel_deltas),
        **target_deltas,
        "peak_value_before": peak_before_v,
        "peak_value_after": peak_after_v,
        "peak_time_before": peak_before_t,
        "peak_time_after": peak_after_t,
    }


def discover_report_room_ids(report: dict[str, Any] | None) -> list[str]:
    if not report:
        return []
    metrics = report.get("metrics", {})
    room_ids: set[str] = set()
    for key in metrics.keys():
        match = re.match(r"room_(\d+)_(?:final|peak|max|min)_", str(key))
        if match:
            room_ids.add(match.group(1))
    return sorted(room_ids, key=lambda item: int(item))


def compare_report_metrics(
    before_report: dict[str, Any],
    after_report: dict[str, Any],
    room_id: str,
    field: str,
) -> dict[str, Any] | None:
    key_map = REPORT_KEYS.get(field, {})
    before_metrics = before_report.get("metrics", {})
    after_metrics = after_report.get("metrics", {})
    samples: list[dict[str, Any]] = []
    for role, suffix in key_map.items():
        metric_key = f"room_{room_id}_{suffix}"
        before_value = safe_float(before_metrics.get(metric_key))
        after_value = safe_float(after_metrics.get(metric_key))
        if before_value is None or after_value is None:
            continue
        samples.append(
            {
                "role": role,
                "metric_key": metric_key,
                "before": before_value,
                "after": after_value,
                "abs_delta": abs(after_value - before_value),
                "rel_delta": rel_delta(before_value, after_value, field),
            }
        )

    if not samples:
        return None

    peak_sample = next(
        (sample for sample in samples if sample["role"] in {"peak", "max", "min"}),
        samples[0],
    )
    return {
        "source": "json_report",
        "sample_count": len(samples),
        "max_abs_delta": max(sample["abs_delta"] for sample in samples),
        "max_rel_delta": max(sample["rel_delta"] for sample in samples),
        "delta_at_60s": None,
        "delta_at_120s": None,
        "delta_at_180s": None,
        "peak_value_before": peak_sample["before"],
        "peak_value_after": peak_sample["after"],
        "peak_time_before": None,
        "peak_time_after": None,
        "report_samples": samples,
    }


def compare_case(case: str, before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    before_csv = before.get("csv")
    after_csv = after.get("csv")
    before_report = before.get("json")
    after_report = after.get("json")
    rooms: dict[str, dict[str, Any]] = {}
    warnings: list[dict[str, Any]] = []

    csv_before_rooms = group_csv_by_room(before_csv)
    csv_after_rooms = group_csv_by_room(after_csv)
    room_ids = sorted(
        set(csv_before_rooms.keys())
        | set(csv_after_rooms.keys())
        | set(discover_report_room_ids(before_report))
        | set(discover_report_room_ids(after_report)),
        key=lambda item: int(item) if item.isdigit() else item,
    )

    for room_id in room_ids:
        field_results: dict[str, Any] = {}
        for field in AUDIT_FIELDS:
            metric = None
            if room_id in csv_before_rooms and room_id in csv_after_rooms:
                metric = compare_csv_series(csv_before_rooms[room_id], csv_after_rooms[room_id], field)
            if metric is None and before_report is not None and after_report is not None:
                metric = compare_report_metrics(before_report, after_report, room_id, field)
            if metric is None:
                continue
            field_results[field] = metric
            warning = warning_for_metric(case, room_id, field, metric)
            if warning is not None:
                warnings.append(warning)
        if field_results:
            rooms[room_id] = field_results

    warnings.extend(flow_thermal_divergence_warnings(case, after_csv))
    artifact_notes = artifact_status_notes(before, after)
    return {
        "case": case,
        "artifact_notes": artifact_notes,
        "rooms": rooms,
        "warnings": warnings,
        "has_csv_comparison": bool(csv_before_rooms and csv_after_rooms),
        "has_report_comparison": before_report is not None and after_report is not None,
    }


def artifact_status_notes(before: dict[str, Any], after: dict[str, Any]) -> list[str]:
    notes: list[str] = []
    if before.get("json") is None and before.get("csv") is None:
        notes.append("before artifact missing")
    if after.get("json") is None and after.get("csv") is None:
        notes.append("after artifact missing")
    if before.get("csv") is None or after.get("csv") is None:
        notes.append("csv pair unavailable; JSON report fallback used where possible")
    return notes


def warning_for_metric(case: str, room_id: str, field: str, metric: dict[str, Any]) -> dict[str, Any] | None:
    rule = WARNING_LIMITS.get(field)
    if not rule:
        return None
    value = metric.get(str(rule["metric"]))
    if value is None:
        return None
    threshold = float(rule["threshold"])
    if float(value) <= threshold:
        return None
    return {
        "severity": "WARNING",
        "case": case,
        "room_id": room_id,
        "field": field,
        "metric": rule["metric"],
        "value": value,
        "threshold": threshold,
        "message": f"{rule['label']} in room {room_id}: {value:.6g} > {threshold:.6g}",
    }


def flow_thermal_divergence_warnings(case: str, rows: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    grouped = group_csv_by_room(rows)
    warnings: list[dict[str, Any]] = []
    for room_id, room_rows in grouped.items():
        last_time: float | None = None
        active_run_s = 0.0
        max_run_s = 0.0
        for row in room_rows:
            time_s = safe_float(row.get("time_s"))
            hrr_kw = safe_float(row.get("hrr_kw")) or 0.0
            flow_m = safe_float(row.get("flow_interface_m"))
            thermal_m = safe_float(row.get("thermal_layer_m"))
            if time_s is None or flow_m is None or thermal_m is None:
                continue
            dt_s = 0.0 if last_time is None else max(0.0, time_s - last_time)
            if hrr_kw > 100.0 and abs(flow_m - thermal_m) > 1.0:
                active_run_s += dt_s
                max_run_s = max(max_run_s, active_run_s)
            else:
                active_run_s = 0.0
            last_time = time_s
        if max_run_s > 30.0:
            warnings.append(
                {
                    "severity": "WARNING",
                    "case": case,
                    "room_id": room_id,
                    "field": "flow_interface_m",
                    "metric": "flow_vs_thermal_divergence_duration_s",
                    "value": max_run_s,
                    "threshold": 30.0,
                    "message": (
                        "flow_interface_m and thermal_layer_m diverge by >1m for "
                        f"{max_run_s:.1f}s while HRR > 100 kW in room {room_id}"
                    ),
                }
            )
    return warnings


def run_structural_checks(repo_root: Path) -> list[dict[str, Any]]:
    def read(rel: str) -> str:
        return (repo_root / rel).read_text(encoding="utf-8")

    checks: list[dict[str, Any]] = []
    layer = read("sim/core/LayerInterfaceModel.gd")
    smoke = read("sim/smoke/SmokeModel.gd")
    gas = read("sim/core/GasExchangeSystem.gd")
    oxygen = read("sim/core/OxygenExchangeSystem.gd")
    hvac = read("sim/core/HVACSystem.gd")
    thermal = read("sim/core/ThermalSystem.gd")
    state = read("sim/core/SimulationStateBuilder.gd")
    log_writer = read("sim/core/SimulationLogWriter.gd")

    checks.append(
        structural_check(
            "canonical_layer_model_exports_four_functions",
            all(
                token in layer
                for token in [
                    "get_visible_smoke_layer_height_m",
                    "get_thermal_layer_height_m",
                    "get_flow_interface_height_m",
                    "get_breathing_zone_exposure_factor",
                ]
            ),
            "LayerInterfaceModel exposes visible, thermal, flow and breathing-zone helpers.",
        )
    )
    checks.append(
        structural_check(
            "visibility_uses_visible_smoke_layer",
            "estimate_visibility_for_layer_m(room, visible_smoke_layer_m)" in state
            and "estimate_visibility_for_layer_m(room, thermal_layer_m)" not in state,
            "SimulationStateBuilder computes visibility from visible_smoke_layer_m, not thermal_layer_m.",
        )
    )
    checks.append(
        structural_check(
            "csv_exports_canonical_layer_fields",
            all(
                token in log_writer
                for token in [
                    "visible_smoke_layer_m",
                    "thermal_layer_m",
                    "flow_interface_m",
                    "layer_150c_m",
                ]
            ),
            "CSV header and rows export visible, thermal, flow and 150C layer heights.",
        )
    )
    checks.append(
        structural_check(
            "gas_exchange_exterior_uses_flow_interface_helper",
            "LayerInterfaceModel.get_exterior_opening_hot_outflow_height_m" in gas,
            "Exterior gas exchange obtains hot outflow height through LayerInterfaceModel.",
        )
    )
    height_body = function_body(gas, "_height_is_in_upper_zone")
    checks.append(
        structural_check(
            "gas_exchange_zone_routing_uses_flow_interface",
            "LayerInterfaceModel.get_flow_interface_height_m" in height_body
            and "room.thermal_layer_m" not in height_body
            and "room.h_layer_m" not in height_body,
            "Gas exchange upper/lower routing uses canonical flow_interface_m.",
        )
    )
    checks.append(
        structural_check(
            "smoke_spill_uses_flow_interface",
            "func get_spill_layer_height_m(room: RoomModel) -> float:" in smoke
            and "LayerInterfaceModel.get_flow_interface_height_m(room, self, 20.0)" in smoke,
            "Smoke spill path is bridged through the canonical flow interface.",
        )
    )
    checks.append(
        structural_check(
            "oxygen_and_hvac_use_flow_interface",
            "LayerInterfaceModel.get_flow_interface_height_m" in oxygen
            and "LayerInterfaceModel.get_flow_interface_height_m" in hvac,
            "O2/HVAC flow routing resolves room interfaces through LayerInterfaceModel.",
        )
    )
    thermal_flow_body = function_body(thermal, "build_interior_opening_flow_state")
    checks.append(
        structural_check(
            "interior_opening_flow_state_uses_flow_interface",
            "flow_interface_height_m(hot_room)" in thermal_flow_body
            and "var h_thermal_np: float = flow_interface_m" in thermal_flow_body,
            "Interior opening flow state centralizes neutral-plane derivation from flow_interface_m.",
        )
    )
    local_neutral = find_forbidden_local_neutral(repo_root)
    checks.append(
        structural_check(
            "no_local_neutral_f_reintroduced",
            not local_neutral,
            "No local _neutral_f/_alpha_b-style interface calculation was found outside central flow helpers.",
            evidence=local_neutral,
        )
    )
    fed_body = function_body(thermal, "step_fed")
    fed_height_ok = (
        ("room.layer_150c_m" in fed_body or "room.thermal_layer_m" in fed_body or "LayerInterfaceModel" in fed_body)
        and "room.h_layer_m < fed_upper_layer_threshold_m" not in fed_body
    )
    checks.append(
        structural_check(
            "fed_thermal_exposure_uses_thermal_layer_or_150c",
            fed_height_ok,
            "FED thermal exposure should be based on thermal_layer_m/layer_150c_m rather than legacy h_layer_m.",
            evidence=[] if fed_height_ok else ["ThermalSystem.step_fed still gates in_upper_layer with room.h_layer_m."],
        )
    )
    return checks


def structural_check(name: str, passed: bool, detail: str, evidence: list[str] | None = None) -> dict[str, Any]:
    return {
        "name": name,
        "severity": "PASS" if passed else "FAIL",
        "pass": passed,
        "detail": detail,
        "evidence": evidence or [],
    }


def function_body(source: str, name: str) -> str:
    marker = f"func {name}"
    if marker not in source:
        return ""
    return source.split(marker, 1)[1].split("\nfunc ", 1)[0]


def find_forbidden_local_neutral(repo_root: Path) -> list[str]:
    forbidden: list[str] = []
    allowed_files = {
        str((repo_root / "sim/core/LayerInterfaceModel.gd").resolve()),
        str((repo_root / "sim/core/ThermalSystem.gd").resolve()),
    }
    patterns = ("_neutral_f", "var _alpha_b")
    for path in (repo_root / "sim").rglob("*.gd"):
        resolved = str(path.resolve())
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if resolved in allowed_files:
            continue
        for line_no, line in enumerate(text.splitlines(), start=1):
            if any(pattern in line for pattern in patterns):
                forbidden.append(f"{path.relative_to(repo_root)}:{line_no}: {line.strip()}")
    return forbidden


def load_case_artifacts(
    repo_root: Path,
    case: str,
    before_dir: Path | None,
    after_dir: Path | None,
    before_git_ref: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    before = {
        "json": load_json_artifact(repo_root, before_dir, case, before_git_ref),
        "csv": load_csv_artifact(repo_root, before_dir, case, before_git_ref),
    }
    after = {
        "json": load_json_artifact(repo_root, after_dir, case, ""),
        "csv": load_csv_artifact(repo_root, after_dir, case, ""),
    }
    return before, after


def conclusion_for(case_results: list[dict[str, Any]], structural_checks: list[dict[str, Any]]) -> str:
    if any(not check.get("pass", False) for check in structural_checks):
        return "FAIL"
    if any(result.get("artifact_notes") for result in case_results):
        return "PASS_WITH_WARNINGS"
    if any(result.get("warnings") for result in case_results):
        return "PASS_WITH_WARNINGS"
    return "PASS"


def build_audit(
    repo_root: Path,
    cases: list[str],
    before_dir: Path | None,
    after_dir: Path | None,
    before_git_ref: str,
    include_structural_checks: bool = True,
) -> dict[str, Any]:
    case_results: list[dict[str, Any]] = []
    for case in cases:
        before, after = load_case_artifacts(repo_root, case, before_dir, after_dir, before_git_ref)
        case_results.append(compare_case(case, before, after))

    structural_checks = run_structural_checks(repo_root) if include_structural_checks else []
    conclusion = conclusion_for(case_results, structural_checks)
    return {
        "generated_at_utc": _dt.datetime.now(_dt.UTC).isoformat(timespec="seconds"),
        "repo_root": str(repo_root),
        "before_dir": str(before_dir) if before_dir is not None else None,
        "after_dir": str(after_dir) if after_dir is not None else None,
        "before_git_ref": before_git_ref or None,
        "cases_requested": cases,
        "conclusion": conclusion,
        "case_results": case_results,
        "structural_checks": structural_checks,
    }


def write_outputs(audit: dict[str, Any], out_json: Path, out_md: Path) -> None:
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(audit, indent=2, sort_keys=True), encoding="utf-8")
    out_md.write_text(render_markdown(audit), encoding="utf-8")


def render_markdown(audit: dict[str, Any]) -> str:
    conclusion = audit.get("conclusion", "UNKNOWN")
    lines: list[str] = []
    lines.append("# Layer Interface Regression Audit")
    lines.append("")
    lines.append("## Resumen ejecutivo")
    lines.append("")
    lines.append(f"- Resultado: **{conclusion}**")
    lines.append(f"- Generado: `{audit.get('generated_at_utc')}`")
    lines.append("- Alcance: comparación before/after de HRR, especies, FED, visibilidad, temperaturas y alturas de capa.")
    lines.append("- Nota: que `visible_smoke_layer_m`, `thermal_layer_m` y `flow_interface_m` sean distintos no es un fallo; son magnitudes físicas distintas.")
    lines.append("")
    lines.append("## Casos ejecutados / comparados")
    lines.append("")
    lines.append("| Caso | CSV pair | JSON pair | Notas | Warnings |")
    lines.append("|---|---:|---:|---|---:|")
    for result in audit.get("case_results", []):
        notes = "; ".join(result.get("artifact_notes", [])) or "-"
        lines.append(
            "| {case} | {csv_pair} | {json_pair} | {notes} | {warnings} |".format(
                case=result.get("case"),
                csv_pair="yes" if result.get("has_csv_comparison") else "no",
                json_pair="yes" if result.get("has_report_comparison") else "no",
                notes=notes,
                warnings=len(result.get("warnings", [])),
            )
        )
    lines.append("")
    lines.append("## Warnings detectados")
    lines.append("")
    warnings = [warning for result in audit.get("case_results", []) for warning in result.get("warnings", [])]
    if warnings:
        lines.append("| Caso | Sala | Campo | Métrica | Valor | Umbral | Mensaje |")
        lines.append("|---|---:|---|---|---:|---:|---|")
        for warning in warnings:
            lines.append(
                "| {case} | {room} | {field} | {metric} | {value} | {threshold} | {message} |".format(
                    case=warning.get("case", ""),
                    room=warning.get("room_id", ""),
                    field=warning.get("field", ""),
                    metric=warning.get("metric", ""),
                    value=format_number(warning.get("value")),
                    threshold=format_number(warning.get("threshold")),
                    message=str(warning.get("message", "")).replace("|", "\\|"),
                )
            )
    else:
        lines.append("No se detectaron warnings numéricos con los artefactos disponibles.")
    lines.append("")
    lines.append("## Diferencias principales")
    lines.append("")
    top_rows = top_delta_rows(audit, limit=30)
    if top_rows:
        lines.append("| Caso | Sala | Campo | Fuente | max abs | max rel | Δ60s | Δ120s | Δ180s | pico before | pico after |")
        lines.append("|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for row in top_rows:
            lines.append(
                "| {case} | {room} | {field} | {source} | {abs_delta} | {rel_delta} | {d60} | {d120} | {d180} | {peak_before} | {peak_after} |".format(
                    case=row["case"],
                    room=row["room_id"],
                    field=row["field"],
                    source=row["source"],
                    abs_delta=format_number(row["max_abs_delta"]),
                    rel_delta=format_number(row["max_rel_delta"]),
                    d60=format_number(row.get("delta_at_60s")),
                    d120=format_number(row.get("delta_at_120s")),
                    d180=format_number(row.get("delta_at_180s")),
                    peak_before=format_number(row.get("peak_value_before")),
                    peak_after=format_number(row.get("peak_value_after")),
                )
            )
    else:
        lines.append("No hay pares before/after suficientes para calcular deltas.")
    lines.append("")
    lines.append("## Checks estructurales")
    lines.append("")
    structural = audit.get("structural_checks", [])
    if structural:
        lines.append("| Check | Resultado | Detalle | Evidencia |")
        lines.append("|---|---|---|---|")
        for check in structural:
            evidence = "<br>".join(str(item).replace("|", "\\|") for item in check.get("evidence", [])) or "-"
            lines.append(
                "| {name} | {status} | {detail} | {evidence} |".format(
                    name=check.get("name", ""),
                    status=check.get("severity", ""),
                    detail=str(check.get("detail", "")).replace("|", "\\|"),
                    evidence=evidence,
                )
            )
    else:
        lines.append("Checks estructurales desactivados para esta ejecución.")
    lines.append("")
    lines.append("## Conclusión")
    lines.append("")
    if conclusion == "PASS":
        lines.append("PASS: no se han detectado cambios físicos significativos ni regresiones estructurales con los artefactos disponibles.")
    elif conclusion == "PASS_WITH_WARNINGS":
        lines.append("PASS_WITH_WARNINGS: la arquitectura queda auditable, pero hay warnings numéricos o artefactos incompletos que deben revisarse antes de cerrar baseline.")
    else:
        lines.append("FAIL: al menos un contrato estructural de capas/interfaces no se cumple. No se han aplicado correcciones físicas automáticas en esta auditoría.")
    lines.append("")
    lines.append("## Recomendaciones siguientes")
    lines.append("")
    lines.append("- Generar pares CSV before/after para los cuatro casos si se necesita comparar `delta_at_60s/120s/180s` con máxima precisión.")
    lines.append("- Revisar cualquier FAIL estructural antes de rebaselinear tolerancias físicas.")
    lines.append("- Mantener separados los cambios de arquitectura y la recalibración de HRR/O2/FED/CO para que las causas sean trazables.")
    lines.append("")
    return "\n".join(lines)


def top_delta_rows(audit: dict[str, Any], limit: int = 30) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for result in audit.get("case_results", []):
        case = result.get("case", "")
        for room_id, fields in result.get("rooms", {}).items():
            for field, metric in fields.items():
                rows.append(
                    {
                        "case": case,
                        "room_id": room_id,
                        "field": field,
                        "source": metric.get("source", ""),
                        "max_abs_delta": metric.get("max_abs_delta"),
                        "max_rel_delta": metric.get("max_rel_delta"),
                        "delta_at_60s": metric.get("delta_at_60s"),
                        "delta_at_120s": metric.get("delta_at_120s"),
                        "delta_at_180s": metric.get("delta_at_180s"),
                        "peak_value_before": metric.get("peak_value_before"),
                        "peak_value_after": metric.get("peak_value_after"),
                    }
                )
    rows.sort(
        key=lambda item: (
            safe_sort_value(item.get("max_rel_delta")),
            safe_sort_value(item.get("max_abs_delta")),
        ),
        reverse=True,
    )
    return rows[:limit]


def safe_sort_value(value: Any) -> float:
    numeric = safe_float(value)
    return numeric if numeric is not None else -1.0


def format_number(value: Any) -> str:
    numeric = safe_float(value)
    if numeric is None:
        return "-"
    if abs(numeric) >= 1000.0:
        return f"{numeric:.3g}"
    if abs(numeric) >= 10.0:
        return f"{numeric:.4g}"
    if abs(numeric) >= 1.0:
        return f"{numeric:.4f}"
    return f"{numeric:.6f}"


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    before_dir = (repo_root / args.before_dir).resolve() if args.before_dir else None
    after_dir = (repo_root / args.after_dir).resolve() if args.after_dir else None
    cases = normalize_cases(args)

    audit = build_audit(
        repo_root=repo_root,
        cases=cases,
        before_dir=before_dir,
        after_dir=after_dir,
        before_git_ref=args.before_git_ref,
        include_structural_checks=not args.skip_structural_checks,
    )
    write_outputs(audit, repo_root / args.out_json, repo_root / args.out_md)
    print(f"[layer-interface-regression] conclusion={audit['conclusion']}")
    print(f"[layer-interface-regression] markdown={repo_root / args.out_md}")
    print(f"[layer-interface-regression] json={repo_root / args.out_json}")
    if args.strict_exit and audit["conclusion"] == "FAIL":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
