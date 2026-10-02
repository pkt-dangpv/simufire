#!/usr/bin/env python3
"""Monitored, opt-in G3 baseline: room load versus explicit fuel objects.

Writes only ignored run artifacts. Does not change the engine, reference
reports, distributed scenarios, or the scientific gate. One Godot run at a
time; aborts on native/process-health failures or low available memory.
"""

from __future__ import annotations

import csv
import ctypes
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import sys
from typing import Callable


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import run_scenario  # noqa: E402
from tools import mutation_audit  # noqa: E402


DURATION_S = 90.0
MIN_AVAILABLE_GIB = 6.0
TIMEOUT_S = 180


class _MemoryStatus(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
        ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
        ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


def available_gib() -> float:
    if os.name != "nt":
        raise RuntimeError("G3 monitored baseline currently requires Windows memory gate")
    state = _MemoryStatus()
    state.dwLength = ctypes.sizeof(state)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(state)):
        raise RuntimeError("GlobalMemoryStatusEx failed")
    return state.ullAvailPhys / (1024 ** 3)


def _sofa() -> dict:
    return {
        "id": "g3_sofa", "name": "G3 sofa", "kind": "mobiliario_tapizado",
        "room_id": 0, "position_m": {"x": 0.2, "y": 1.4},
        "size_m": {"x": 2.2, "y": 0.9}, "footprint_m2": 2.0,
        "exposed_area_m2": 3.5, "elevation_m": 0.4,
        "fuel_energy_MJ": 200.0, "remaining_fuel_MJ": 200.0,
        "max_hrr_kw": 100.0, "ignition_temp_c": 310.0,
        "ignition_flux_kw_m2": 16.0, "smoke_yield_kg_per_MJ": 0.012,
        "co_yield_kg_per_MJ": 0.0004, "is_primary_ignition_source": True,
    }


def _unignited_chair() -> dict:
    return {
        "id": "g3_unignited_chair", "name": "G3 non-igniting test chair",
        "kind": "mobiliario_madera", "room_id": 0,
        "position_m": {"x": 5.0, "y": 3.5}, "size_m": {"x": 0.7, "y": 0.7},
        "footprint_m2": 0.5, "exposed_area_m2": 1.0, "elevation_m": 0.0,
        "fuel_energy_MJ": 200.0, "remaining_fuel_MJ": 200.0,
        "max_hrr_kw": 100.0, "ignition_temp_c": 2000.0,
        "ignition_flux_kw_m2": 1000.0, "smoke_yield_kg_per_MJ": 0.008,
        "co_yield_kg_per_MJ": 0.004, "is_primary_ignition_source": False,
    }


def case_data(name: str) -> dict:
    if name not in CASES:
        raise ValueError(f"unknown G3 control {name}")
    room_mj, room_kw, objects = CASES[name]
    return {
        "template": "simple_house",
        "duration_s": DURATION_S,
        "ignite_on_start": True,
        "ignition_room_id": 0,
        "watch_room_ids": [0],
        "log_interval_s": 1.0,
        "room_overrides": [{
            "id": 0, "fuel_energy_MJ": room_mj,
            "max_hrr_kw": room_kw, "fuel_objects": objects,
        }],
        "engine_overrides": {
            "fire_spread_enabled": False,
            "glass_auto_break_enabled": False,
            "interior_transport_enabled": False,
            "two_zone_opening_flow_enabled": False,
            "fire_alpha_kw_s2": 0.05,
            "fire_secondary_hrr_gain_kw": 0.0,
        },
    }


CASES = {
    "room_only": (200.0, 100.0, []),
    "sofa_mirrored": (200.0, 100.0, [_sofa()]),
    "sofa_plus_unignited_chair": (200.0, 100.0, [_sofa(), _unignited_chair()]),
    "sofa_objects_only": (0.0, 0.0, [_sofa()]),
    "empty_ignition_room": (0.0, 0.0, []),
}


def _room0_metrics(path: Path) -> dict:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = [row for row in csv.DictReader(handle) if row.get("room_id") == "0"]
    if not rows:
        raise ValueError(f"{path}: no room 0 CSV rows")
    required = (
        "time_s", "hrr_kw", "co_generated_kg_total", "co_kg",
        "fuel_consumed_MJ_total", "fuel_remaining_MJ", "co_ppm",
        "smoke_kg", "smoke_generated_kg_total",
        "o2_consumed_kg_total_all", "o2_consumed_fire_kg_total",
    )
    for field in required:
        if any(field not in row or row[field] == "" for row in rows):
            raise ValueError(f"{path}: missing {field}")
    last = rows[-1]
    return {
        "snapshots": len(rows),
        "last_time_s": float(last["time_s"]),
        "max_hrr_kw": max(float(row["hrr_kw"]) for row in rows),
        "final_co_generated_kg_total": float(last["co_generated_kg_total"]),
        "final_co_inventory_kg": float(last["co_kg"]),
        "final_co_ppm": float(last["co_ppm"]),
        "final_fuel_consumed_MJ_total": float(last["fuel_consumed_MJ_total"]),
        "final_fuel_remaining_MJ": float(last["fuel_remaining_MJ"]),
        "final_smoke_kg": float(last["smoke_kg"]),
        "final_smoke_generated_kg_total": float(last["smoke_generated_kg_total"]),
        "final_o2_consumed_kg_total_all": float(last["o2_consumed_kg_total_all"]),
        "final_o2_consumed_fire_kg_total": float(last["o2_consumed_fire_kg_total"]),
    }


def _room0_object_states(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "g3_fuel_object_state_v1":
        raise ValueError(f"{path}: fuel object snapshot schema mismatch")
    rooms = payload.get("rooms")
    if not isinstance(rooms, list):
        raise ValueError(f"{path}: missing room snapshot list")
    room0 = [room for room in rooms if room.get("room_id") == 0]
    if len(room0) != 1 or not isinstance(room0[0].get("objects"), list):
        raise ValueError(f"{path}: missing or duplicated room 0 objects")
    return room0[0]["objects"]


def _room0_ledger_metrics(path: Path) -> dict:
    totals = {
        "room_fuel_consumed_MJ": 0.0,
        "explicit_object_burn_MJ": 0.0,
        "proxy_burn_MJ": 0.0,
        "nominal_explicit_co_kg": 0.0,
        "room_co_generated_kg": 0.0,
        "room_co_inventory_change_kg": 0.0,
        "co2_inventory_change_kg": 0.0,
        "hcn_inventory_change_kg": 0.0,
        "smoke_generated_kg": 0.0,
        "smoke_inventory_change_kg": 0.0,
        "o2_consumed_all_kg": 0.0,
        "o2_consumed_fire_kg": 0.0,
    }
    keys = {
        "room_fuel_consumed_MJ": "room_fuel_consumed_delta_MJ",
        "explicit_object_burn_MJ": "explicit_object_burn_delta_MJ",
        "proxy_burn_MJ": "proxy_burn_delta_MJ",
        "nominal_explicit_co_kg": "nominal_explicit_co_from_burn_kg",
        "room_co_generated_kg": "room_co_generated_delta_kg",
        "room_co_inventory_change_kg": "room_co_inventory_delta_kg",
        "co2_inventory_change_kg": "room_co2_kg_delta",
        "hcn_inventory_change_kg": "room_hcn_kg_delta",
        "smoke_generated_kg": "room_smoke_generated_kg_total_delta",
        "smoke_inventory_change_kg": "room_smoke_kg_delta",
        "o2_consumed_all_kg": "room_o2_consumed_kg_total_all_delta",
        "o2_consumed_fire_kg": "room_o2_consumed_fire_kg_total_delta",
    }
    object_burn: dict[str, float] = {}
    object_max_hrr: dict[str, float] = {}
    object_max_abs_burn_step: dict[str, float] = {}
    object_step_count: dict[str, int] = {}
    max_abs_co_balance_residual_kg = 0.0
    max_abs_smoke_balance_residual_kg = 0.0
    count = 0
    last_time = -1.0
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            row = json.loads(line)
            if row.get("schema_version") != "g3_fuel_source_step_v2":
                raise ValueError(f"{path}:{line_number}: ledger schema mismatch")
            if row.get("room_id") != 0:
                continue
            time_s = float(row["time_s"])
            if not math.isfinite(time_s) or time_s <= last_time:
                raise ValueError(f"{path}:{line_number}: non-monotonic room 0 time")
            last_time = time_s
            count += 1
            for target, source in keys.items():
                value = float(row[source])
                if not math.isfinite(value):
                    raise ValueError(f"{path}:{line_number}: non-finite {source}")
                totals[target] += value
            for field in ("room_co_balance_residual_kg", "room_smoke_balance_residual_kg"):
                value = float(row[field])
                if not math.isfinite(value):
                    raise ValueError(f"{path}:{line_number}: non-finite {field}")
            max_abs_co_balance_residual_kg = max(
                max_abs_co_balance_residual_kg, abs(float(row["room_co_balance_residual_kg"]))
            )
            max_abs_smoke_balance_residual_kg = max(
                max_abs_smoke_balance_residual_kg, abs(float(row["room_smoke_balance_residual_kg"]))
            )
            for obj in row["objects"]:
                object_id = str(obj["id"])
                burn_mj = float(obj["burn_MJ"])
                hrr_kw = float(obj["hrr_after_kw"])
                if not math.isfinite(burn_mj) or not math.isfinite(hrr_kw):
                    raise ValueError(f"{path}:{line_number}: non-finite object state")
                object_burn[object_id] = object_burn.get(object_id, 0.0) + burn_mj
                object_max_hrr[object_id] = max(
                    object_max_hrr.get(object_id, 0.0), hrr_kw
                )
                object_max_abs_burn_step[object_id] = max(
                    object_max_abs_burn_step.get(object_id, 0.0), abs(burn_mj)
                )
                object_step_count[object_id] = object_step_count.get(object_id, 0) + 1
    if count == 0:
        raise ValueError(f"{path}: missing room 0 ledger rows")
    return {
        "steps": count,
        **totals,
        "object_burn_MJ": object_burn,
        "object_max_hrr_kw": object_max_hrr,
        "object_max_abs_burn_step_MJ": object_max_abs_burn_step,
        "object_step_count": object_step_count,
        "max_abs_co_balance_residual_kg": max_abs_co_balance_residual_kg,
        "max_abs_smoke_balance_residual_kg": max_abs_smoke_balance_residual_kg,
    }


def run(
    *,
    case_scenarios: dict[str, dict] | None = None,
    output_label: str = "g3_fuel_source_baseline",
    report_schema: str = "g3_fuel_source_baseline_v1",
    case_extra_metrics: Callable[[Path], dict] | None = None,
    capture_species_inflight: bool = False,
    extra_runner_args: list[str] | None = None,
) -> int:
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot executable not found")
    if mutation_audit._godot_processes():
        raise RuntimeError("pre-existing Godot processes; no baseline launched")
    if available_gib() < MIN_AVAILABLE_GIB:
        raise RuntimeError(f"less than {MIN_AVAILABLE_GIB:g} GiB free; no baseline launched")

    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    root = ROOT / "runs" / f"{output_label}_{stamp}"
    if root.exists():
        raise RuntimeError(f"output already exists: {root}")
    root.mkdir(parents=True)
    appdata = root / "appdata"
    temp = root / "temp"
    appdata.mkdir()
    temp.mkdir()
    environment = os.environ.copy()
    environment.update({"APPDATA": str(appdata), "TEMP": str(temp), "TMP": str(temp)})
    report = {"schema": report_schema, "root": str(root), "cases": []}

    selected_cases = {name: case_data(name) for name in CASES} \
        if case_scenarios is None else case_scenarios
    for name, scenario_data in selected_cases.items():
        if mutation_audit._godot_processes():
            raise RuntimeError("Godot was not quiescent before next case")
        free_gib = available_gib()
        if free_gib < MIN_AVAILABLE_GIB:
            raise RuntimeError(f"memory gate failed before {name}: {free_gib:.2f} GiB")
        out_dir = root / name
        out_dir.mkdir()
        scenario = out_dir / "scenario.json"
        scenario.write_text(json.dumps(scenario_data, ensure_ascii=False, indent=2), encoding="utf-8")
        token = secrets.token_hex(16)
        command = [
            str(godot), "--headless", "--path", str(ROOT),
            "--log-file", str(out_dir / "godot.log"),
            run_scenario._RUNNER_SCENE, "--",
            f"--run-scenario={scenario}", f"--out-dir={out_dir}",
            f"--run-token={token}", "--co-inventory-trace",
            "--fuel-object-state-snapshot", "--fuel-source-ledger",
        ]
        if capture_species_inflight:
            command.append("--species-inflight-snapshot")
        command.extend(extra_runner_args or [])
        completed, health = mutation_audit._run_monitored(command, TIMEOUT_S, environment)
        (out_dir / "monitor.health.json").write_text(
            json.dumps(health, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        (out_dir / "monitor.stdout.log").write_text(completed.stdout or "", encoding="utf-8")
        (out_dir / "monitor.stderr.log").write_text(completed.stderr or "", encoding="utf-8")
        errors = mutation_audit._runtime_health_errors(health)
        if completed.returncode != 0:
            errors.append(f"Godot exit {completed.returncode}")
        if f"RUN_SCENARIO PASS token={token}" not in (completed.stdout or "") + (completed.stderr or ""):
            errors.append("fresh completion marker missing")
        errors.extend(run_scenario._validate_outputs(
            out_dir, run_token=token, scenario=scenario,
            expected_duration_s=float(scenario_data.get("duration_s", DURATION_S)),
        ))
        if errors:
            raise RuntimeError(f"{name}: " + "; ".join(errors))
        object_states = _room0_object_states(out_dir / "fuel_object_state_snapshot.json")
        metrics = _room0_metrics(out_dir / "sim_log.csv")
        ledger = _room0_ledger_metrics(out_dir / "fuel_source_ledger.jsonl")
        if abs(ledger["room_co_generated_kg"] - metrics["final_co_generated_kg_total"]) > 0.000001:
            raise RuntimeError(f"{name}: ledger CO generation does not reconcile with CSV")
        if abs(ledger["room_fuel_consumed_MJ"] - metrics["final_fuel_consumed_MJ_total"]) > 0.000001:
            raise RuntimeError(f"{name}: ledger fuel consumption does not reconcile with CSV")
        reconciled = (
            ("smoke_generated_kg", "final_smoke_generated_kg_total", 0.000001),
            # CSV smoke_kg is printed with four decimals: half an LSB is 5e-5 kg.
            ("smoke_inventory_change_kg", "final_smoke_kg", 0.0000501),
            ("o2_consumed_all_kg", "final_o2_consumed_kg_total_all", 0.000001),
            ("o2_consumed_fire_kg", "final_o2_consumed_fire_kg_total", 0.000001),
        )
        for ledger_field, csv_field, tolerance in reconciled:
            if abs(ledger[ledger_field] - metrics[csv_field]) > tolerance:
                raise RuntimeError(f"{name}: {ledger_field} does not reconcile with CSV")
        if name == "sofa_plus_unignited_chair":
            chair = [obj for obj in object_states if obj.get("id") == "g3_unignited_chair"]
            if len(chair) != 1 or abs(float(chair[0]["remaining_fuel_MJ"]) - 200.0) > 0.001 \
                    or float(chair[0]["hrr_kw"]) > 0.001 \
                    or str(chair[0]["state"]).lower() == "flaming" \
                    or abs(ledger["object_burn_MJ"].get("g3_unignited_chair", 0.0)) > 0.001 \
                    or ledger["object_max_hrr_kw"].get("g3_unignited_chair", 0.0) > 0.001 \
                    or ledger["object_max_abs_burn_step_MJ"].get("g3_unignited_chair", 0.0) > 0.001 \
                    or ledger["object_step_count"].get("g3_unignited_chair", 0) != ledger["steps"]:
                raise RuntimeError("unignited-chair control did not remain non-burning")
        case_report = {
            "name": name,
            "scenario_sha256": hashlib.sha256(scenario.read_bytes()).hexdigest(),
            "available_gib_before": round(free_gib, 3),
            "metrics": metrics,
            "room0_fuel_objects": object_states,
            "room0_fuel_ledger": ledger,
        }
        if case_extra_metrics is not None:
            case_report["extra_metrics"] = case_extra_metrics(out_dir)
        report["cases"].append(case_report)
        (root / "report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(case_report, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 BASELINE FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
