#!/usr/bin/env python3
"""P1R5 fail-closed mutation campaign for required reference checks."""

from __future__ import annotations

import argparse
import contextlib
import csv
import ctypes
import datetime
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from ctypes import wintypes
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
REPORTS_DIR = ROOT / "sim/validation/reports"
REFERENCE_REPORT = REPORTS_DIR / "reference_checks.json"
AUDITOR_PATH = ROOT / "scripts/simulation/audit_mutation_trust.py"
VALIDATOR_PATH = ROOT / "scripts/simulation/validate_reference_cases.py"

MUTATION_MANIFEST: dict[str, dict[str, Any]] = {
    "M-HRR": {"case": "v2_sealed_room_o2_depletion", "checks": ["v2_sealed_room_o2_depletion_room_0_peak_hrr_kw", "v2_sealed_room_o2_depletion_time_room_0_o2_below_13pct_s", "v2_sealed_room_o2_depletion_time_room_0_o2_below_18pct_s"]},
    "M-ENTR": {"case": "cfast_single_room_closed", "checks": ["cfast_closed_t210_temp_upper_c", "cfast_closed_t300_temp_upper_c", "cfast_closed_rmse_temp_upper_c"]},
    "M-O2EXT": {"case": "v2_sealed_room_o2_depletion", "checks": ["v2_sealed_room_o2_depletion_room_0_final_o2", "v2_sealed_room_o2_depletion_time_room_0_o2_below_13pct_s", "v2_sealed_room_o2_depletion_time_room_0_o2_below_18pct_s"]},
    "M-YCO": {"case": "v4_co_remote_rooms", "checks": ["v4_co_remote_rooms_room_1_peak_co_upper_ppm", "v4_co_remote_rooms_room_2_peak_co_upper_ppm", "v4_co_remote_rooms_time_room_1_co_upper_above_1200_s", "v4_co_remote_rooms_time_room_2_co_upper_above_200_s"]},
    "M-YHCN": {"case": "pu_sofa_fec_incapacitation", "checks": ["pu_sofa_fec_incapacitation_room_0_peak_hcn_upper_ppm"]},
    "M-WALL": {"case": "cfast_single_room_closed", "checks": ["cfast_closed_t210_temp_upper_c", "cfast_closed_t300_temp_upper_c", "cfast_closed_rmse_temp_upper_c"]},
    "M-VENT": {"case": "cfast_pool_fire_open", "checks": ["cfast_pool_t60_o2", "cfast_pool_t120_o2", "cfast_pool_t300_o2", "cfast_pool_rmse_temp_upper_c"]},
    "M-PRES": {"case": "cfast_single_room_closed", "checks": ["cfast_closed_t120_pressure_pa"]},
}

_GODOT_CANDIDATES = (
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
)
_FORBIDDEN_LOG_PATTERNS = {
    "SCRIPT ERROR": re.compile(r"(?im)^\s*SCRIPT ERROR\b"),
    "Parse Error": re.compile(r"(?im)^\s*(?:SCRIPT )?ERROR:.*Parse Error\b|^\s*Parse Error\b"),
    "ERROR:": re.compile(r"(?im)^\s*ERROR:"),
    "Segmentation fault": re.compile(r"(?i)\bSegmentation fault\b"),
    "crash": re.compile(r"(?i)\b(?:Godot|engine|process)\s+crash(?:ed|ing)?\b|^\s*CRASH(?:ED)?\b", re.MULTILINE),
}
_RUNTIME_HEALTH_CONTRACT = "windows-window-process-exit-v2"
_POST_EXIT_OBSERVATION_S = 2.0
_WINDOW_POLL_S = 0.2
_PROCESS_SAMPLE_S = 1.0
_EXPECTED_GODOT_VERSION = "4.7.1.stable.official.a13da4feb"
_SEM_FAILCRITICALERRORS = 0x0001
_SEM_NOGPFAULTERRORBOX = 0x0002
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_SYNCHRONIZE = 0x00100000
_STILL_ACTIVE = 259
_STATUS_ACCESS_VIOLATION = 0xC0000005


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _find_godot(requested: str | None) -> Path:
    candidates = [Path(requested)] if requested else []
    if os.environ.get("GODOT_EXE"):
        candidates.append(Path(os.environ["GODOT_EXE"]))
    candidates.extend(_GODOT_CANDIDATES)
    for candidate in candidates:
        if candidate.is_file():
            if "console" not in candidate.name.lower():
                raise RuntimeError(f"Godot executable is not the console build: {candidate}")
            return candidate.resolve()
    raise RuntimeError("Godot 4.7.1 console executable not found")


def _godot_processes() -> list[dict[str, Any]]:
    if os.name != "nt":
        return []
    completed = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH", "/FI", "IMAGENAME eq Godot*"],
        capture_output=True, text=True, check=False,
    )
    records: list[dict[str, Any]] = []
    for row in csv.reader(completed.stdout.splitlines()):
        if len(row) < 2 or not row[0].lower().startswith("godot"):
            continue
        try:
            pid = int(row[1])
        except ValueError:
            continue
        records.append({"image_name": row[0], "pid": pid})
    return sorted(records, key=lambda item: (item["image_name"].lower(), item["pid"]))


def _is_godot_error_window_title(title: str) -> bool:
    normalized = "".join(
        character
        for character in unicodedata.normalize("NFKD", title)
        if not unicodedata.combining(character)
    ).casefold()
    if "godot" not in normalized:
        return False
    return any(
        marker in normalized
        for marker in (
            "application error",
            "error de la aplicacion",
            "has stopped working",
            "dejo de funcionar",
        )
    )


def _enum_windows_failed(enum_result: int, last_error: int) -> bool:
    return not bool(enum_result) and int(last_error) != 0


def _windows_godot_error_dialogs() -> list[str]:
    if os.name != "nt":
        return []

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    titles: list[str] = []
    callback_errors: list[str] = []
    callback_type = ctypes.WINFUNCTYPE(
        wintypes.BOOL, wintypes.HWND, wintypes.LPARAM, use_last_error=True
    )
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowTextW.restype = ctypes.c_int

    @callback_type
    def collect(hwnd, _lparam):
        try:
            length = user32.GetWindowTextLengthW(hwnd)
            if length <= 0:
                return True
            buffer = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buffer, length + 1)
            if _is_godot_error_window_title(buffer.value):
                titles.append(buffer.value)
            return True
        except Exception as exc:
            callback_errors.append(repr(exc))
            return False

    ctypes.set_last_error(0)
    enum_result = int(user32.EnumWindows(collect, 0))
    last_error = ctypes.get_last_error()
    if callback_errors:
        raise RuntimeError(
            "EnumWindows callback failed: " + "; ".join(callback_errors)
        )
    if _enum_windows_failed(enum_result, last_error):
        raise ctypes.WinError(last_error)
    return sorted(set(titles))


def _terminate_observed_godot_processes(records: list[dict[str, Any]]) -> list[int]:
    terminated: list[int] = []
    if os.name != "nt":
        return terminated
    for pid in sorted({record["pid"] for record in records}):
        completed = subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            capture_output=True,
            text=True,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        if completed.returncode == 0:
            terminated.append(pid)
    return terminated


def _open_process_handle(pid: int) -> int | None:
    if os.name != "nt":
        return None
    handle = ctypes.windll.kernel32.OpenProcess(
        _PROCESS_QUERY_LIMITED_INFORMATION | _SYNCHRONIZE, False, pid
    )
    return int(handle) if handle else None


def _sample_godot_processes(
    observed: dict[tuple[str, int], dict[str, Any]], handles: dict[int, int]
) -> list[dict[str, Any]]:
    current = _godot_processes()
    for record in current:
        observed[(record["image_name"], record["pid"])] = record
        if record["pid"] not in handles:
            handle = _open_process_handle(record["pid"])
            if handle is not None:
                handles[record["pid"]] = handle
    return current


def _collect_process_exit_codes(
    observed: dict[tuple[str, int], dict[str, Any]], handles: dict[int, int]
) -> list[dict[str, Any]]:
    if os.name != "nt":
        return list(observed.values())
    kernel32 = ctypes.windll.kernel32
    records: list[dict[str, Any]] = []
    try:
        for record in observed.values():
            item = dict(record)
            handle = handles.get(record["pid"])
            exit_code = ctypes.c_ulong()
            if handle:
                kernel32.WaitForSingleObject(handle, 5000)
                if kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                    item["exit_code"] = (
                        None if exit_code.value == _STILL_ACTIVE else exit_code.value
                    )
                else:
                    item["exit_code"] = None
            else:
                item["exit_code"] = None
            records.append(item)
    finally:
        for handle in handles.values():
            kernel32.CloseHandle(handle)
    return sorted(records, key=lambda item: (item["image_name"].lower(), item["pid"]))


def _resolve_monitored_executable(executable: Path) -> tuple[Path, bool]:
    """Bypass Godot's Windows console wrapper for monitored launches.

    The small ``*_console.exe`` binary starts the GUI-subsystem sibling. Native
    failures in that child can surface an application-error dialog independently
    of ``CREATE_NO_WINDOW`` on the wrapper. Launching the sibling directly keeps
    the same engine and arguments under the existing process/window supervisor.
    """
    executable = Path(executable)
    suffix = "_console.exe"
    if os.name != "nt" or not executable.name.lower().endswith(suffix):
        return executable, False
    engine = executable.with_name(executable.name[: -len(suffix)] + ".exe")
    if not engine.is_file():
        raise FileNotFoundError(
            f"Godot GUI sibling missing for monitored console wrapper: {engine}"
        )
    return engine, True


def _start_without_windows_error_ui(
    command: list[str], environment: dict[str, str] | None
) -> tuple[subprocess.Popen[str], bool]:
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    if os.name != "nt":
        return (
            subprocess.Popen(
                command,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=environment,
                creationflags=creationflags,
            ),
            False,
        )

    kernel32 = ctypes.windll.kernel32
    requested_mode = _SEM_FAILCRITICALERRORS | _SEM_NOGPFAULTERRORBOX
    previous_mode = kernel32.SetErrorMode(requested_mode)
    kernel32.SetErrorMode(previous_mode | requested_mode)
    try:
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
            creationflags=creationflags,
        )
    finally:
        kernel32.SetErrorMode(previous_mode)
    return process, True


def _run_monitored(
    command: list[str], timeout_s: int, environment: dict[str, str] | None = None
) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
    requested_executable = Path(command[0])
    launched_executable, console_wrapper_bypassed = \
        _resolve_monitored_executable(requested_executable)
    launch_command = list(command)
    launch_command[0] = str(launched_executable)
    started = time.monotonic()
    started_at = datetime.datetime.now(datetime.UTC)
    observed: dict[tuple[str, int], dict[str, Any]] = {}
    handles: dict[int, int] = {}
    dialogs: set[str] = set()
    timed_out = False
    terminated_pids: list[int] = []
    next_process_sample = 0.0
    process, windows_error_ui_suppressed = _start_without_windows_error_ui(
        launch_command, environment
    )

    stdout = ""
    stderr = ""
    while True:
        dialogs.update(_windows_godot_error_dialogs())
        now = time.monotonic()
        if now >= next_process_sample or dialogs:
            _sample_godot_processes(observed, handles)
            next_process_sample = now + _PROCESS_SAMPLE_S
        if dialogs:
            if process.poll() is None:
                process.kill()
            terminated_pids.extend(
                _terminate_observed_godot_processes(list(observed.values()))
            )
            stdout, stderr = process.communicate()
            break
        remaining = timeout_s - (now - started)
        if remaining <= 0:
            timed_out = True
            if process.poll() is None:
                process.kill()
            _sample_godot_processes(observed, handles)
            terminated_pids.extend(
                _terminate_observed_godot_processes(list(observed.values()))
            )
            stdout, stderr = process.communicate()
            break
        try:
            stdout, stderr = process.communicate(
                timeout=min(_WINDOW_POLL_S, remaining)
            )
            break
        except subprocess.TimeoutExpired:
            continue

    post_exit_started = time.monotonic()
    post_exit_deadline = post_exit_started + _POST_EXIT_OBSERVATION_S
    while time.monotonic() < post_exit_deadline:
        dialogs.update(_windows_godot_error_dialogs())
        _sample_godot_processes(observed, handles)
        time.sleep(_WINDOW_POLL_S)

    residual = _godot_processes()
    dialogs.update(_windows_godot_error_dialogs())
    if residual:
        terminated_pids.extend(_terminate_observed_godot_processes(residual))
    observed_with_exit = _collect_process_exit_codes(observed, handles)
    health = {
        "contract": _RUNTIME_HEALTH_CONTRACT,
        "requested_executable": str(requested_executable),
        "launched_executable": str(launched_executable),
        "console_wrapper_bypassed": console_wrapper_bypassed,
        "windows_error_ui_suppressed": windows_error_ui_suppressed,
        "started_at_utc": started_at.isoformat(),
        "ended_at_utc": datetime.datetime.now(datetime.UTC).isoformat(),
        "wrapper_exit_code": process.returncode,
        "timed_out": timed_out,
        "error_dialogs": sorted(dialogs),
        "observed_godot_processes": observed_with_exit,
        "residual_godot_processes": residual,
        "process_quiescent": not residual,
        "cleanup_terminated_pids": sorted(set(terminated_pids)),
        "post_exit_observation_s": round(time.monotonic() - post_exit_started, 3),
    }
    return subprocess.CompletedProcess(
        command, process.returncode, stdout, stderr
    ), health


def _runtime_health_errors(health: Any) -> list[str]:
    if not isinstance(health, dict):
        return ["runtime health record is missing"]
    errors: list[str] = []
    if health.get("contract") != _RUNTIME_HEALTH_CONTRACT:
        errors.append("runtime health contract is missing or unsupported")
    if os.name == "nt" and health.get("windows_error_ui_suppressed") is not True:
        errors.append("Windows application-error UI was not suppressed")
    if health.get("wrapper_exit_code") not in (0, 2):
        errors.append(f"Godot wrapper exited {health.get('wrapper_exit_code')}")
    if health.get("timed_out") is not False:
        errors.append("Godot run timed out")
    if health.get("error_dialogs") != []:
        errors.append(f"Godot application-error popup detected: {health.get('error_dialogs')}")
    if health.get("residual_godot_processes") != []:
        errors.append(
            f"residual Godot processes detected: {health.get('residual_godot_processes')}"
        )
    if health.get("process_quiescent") is not True:
        errors.append("Godot process state did not become quiescent")
    observed = health.get("observed_godot_processes")
    if not isinstance(observed, list):
        errors.append("observed Godot process inventory is missing")
    else:
        for process in observed:
            exit_code = process.get("exit_code") if isinstance(process, dict) else None
            if exit_code is None:
                errors.append("observed Godot child exit code is missing")
            elif exit_code == _STATUS_ACCESS_VIOLATION:
                errors.append(
                    f"Godot child access violation 0x{exit_code:08X}: {process}"
                )
            elif exit_code not in (0, 2):
                errors.append(f"Godot child exited 0x{exit_code:08X}: {process}")
    observed_s = health.get("post_exit_observation_s")
    if not isinstance(observed_s, (int, float)) or observed_s < _POST_EXIT_OBSERVATION_S:
        errors.append("post-exit observation window is incomplete")
    return errors


def _forbidden_log_markers(log_text: str) -> list[str]:
    return [
        marker
        for marker, pattern in _FORBIDDEN_LOG_PATTERNS.items()
        if pattern.search(log_text)
    ]


def _git_output(*args: str) -> str:
    completed = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed: {completed.stderr.strip()}"
        )
    return completed.stdout.strip()


def _verify_godot_version(godot: Path) -> tuple[str, dict[str, Any]]:
    completed, health = _run_monitored([str(godot), "--version"], 30)
    errors = _runtime_health_errors(health)
    version = completed.stdout.strip()
    if errors:
        raise RuntimeError("Godot version probe invalid: " + "; ".join(errors))
    if version != _EXPECTED_GODOT_VERSION:
        raise RuntimeError(
            f"Godot version mismatch: expected {_EXPECTED_GODOT_VERSION}, got {version!r}"
        )
    return version, health


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _build_case_command(
    godot: Path,
    case_name: str,
    report_path: Path,
    simulation_log_path: Path,
    mutant_id: str | None,
) -> list[str]:
    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        "--",
        f"--validation-case={case_name}",
        f"--validation-output={report_path}",
        f"--validation-simulation-log={simulation_log_path}",
    ]
    if mutant_id:
        command.append(f"--validation-mutate={mutant_id}")
    return command


def _run_case(
    godot: Path,
    godot_version: str,
    source_commit: str,
    case_name: str,
    destination: Path,
    mutant_id: str | None,
    timeout_s: int,
) -> dict[str, Any]:
    destination.mkdir(parents=True, exist_ok=True)
    report_path = destination / f"{case_name}.json"
    engine_log_path = destination / f"{case_name}.godot.log"
    log_path = destination / f"{case_name}.log"
    health_path = destination / f"{case_name}.runtime_health.json"
    appdata_path = destination / "appdata"
    appdata_path.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["APPDATA"] = str(appdata_path)
    command = _build_case_command(
        godot, case_name, report_path, log_path, mutant_id
    )
    case_path = ROOT / "sim/validation/cases" / f"{case_name}.json"
    case_blob_oid = _git_output("hash-object", str(case_path))
    started_wall = datetime.datetime.now(datetime.UTC)
    started = time.monotonic()
    completed, runtime_health = _run_monitored(command, timeout_s, environment)
    elapsed = time.monotonic() - started
    captured_log = completed.stdout
    if completed.stderr:
        captured_log += (
            "\n" if captured_log and not captured_log.endswith("\n") else ""
        ) + "[stderr]\n" + completed.stderr
    engine_log_path.write_text(captured_log, encoding="utf-8")
    runtime_health.update(
        {
            "godot_executable": str(godot),
            "godot_version": godot_version,
            "source_commit": source_commit,
            "case_path": case_path.relative_to(ROOT).as_posix(),
            "case_blob_oid": case_blob_oid,
            "case_sha256": _sha256(case_path),
            "command": command,
            "appdata": str(appdata_path),
            "stdout_bytes": len(completed.stdout.encode("utf-8")),
            "stdout_sha256": hashlib.sha256(completed.stdout.encode("utf-8")).hexdigest(),
            "stderr_bytes": len(completed.stderr.encode("utf-8")),
            "stderr_sha256": hashlib.sha256(completed.stderr.encode("utf-8")).hexdigest(),
        }
    )
    health_path.write_text(
        json.dumps(runtime_health, indent=2) + "\n", encoding="utf-8"
    )
    health_errors = _runtime_health_errors(runtime_health)
    if health_errors:
        raise RuntimeError(
            f"{case_name}/{mutant_id or 'CONTROL'} invalid runtime health: "
            + "; ".join(health_errors)
        )
    if completed.returncode not in (0, 2):
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} exited {completed.returncode}")
    needs_timeseries = case_name.startswith("cfast_")
    if not report_path.is_file() or not engine_log_path.is_file() or (needs_timeseries and not log_path.is_file()):
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} missing report or log")
    if report_path.stat().st_mtime < started_wall.timestamp() - 2:
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} produced a stale report")
    data = json.loads(report_path.read_text(encoding="utf-8"))
    if data.get("case") != case_name:
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} report case mismatch")
    evidence_log_path = log_path if log_path.is_file() else engine_log_path
    log_text = evidence_log_path.read_text(encoding="utf-8", errors="replace") + engine_log_path.read_text(encoding="utf-8", errors="replace")
    markers = _forbidden_log_markers(log_text)
    if markers:
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} forbidden log markers: {markers}")
    return {
        "case": case_name, "mutant": mutant_id, "command": command,
        "elapsed_s": round(elapsed, 3), "exit_code": completed.returncode,
        "report_path": report_path.as_posix(), "report_bytes": report_path.stat().st_size,
        "report_sha256": _sha256(report_path), "log_path": evidence_log_path.as_posix(),
        "log_bytes": evidence_log_path.stat().st_size, "log_sha256": _sha256(evidence_log_path),
        "engine_log_path": engine_log_path.as_posix(), "engine_log_bytes": engine_log_path.stat().st_size,
        "engine_log_sha256": _sha256(engine_log_path),
        "runtime_health_path": health_path.as_posix(),
        "runtime_health_bytes": health_path.stat().st_size,
        "runtime_health_sha256": _sha256(health_path),
        "runtime_health": runtime_health,
    }


def _record_existing(case_name: str, destination: Path, mutant_id: str | None = None) -> dict[str, Any] | None:
    report_path = destination / f"{case_name}.json"
    engine_log_path = destination / f"{case_name}.godot.log"
    simulation_log_path = destination / f"{case_name}.log"
    health_path = destination / f"{case_name}.runtime_health.json"
    needs_timeseries = case_name.startswith("cfast_")
    if not report_path.is_file() or not engine_log_path.is_file() or not health_path.is_file():
        return None
    if needs_timeseries and not simulation_log_path.is_file():
        return None
    data = json.loads(report_path.read_text(encoding="utf-8"))
    if data.get("case") != case_name:
        raise RuntimeError(f"{case_name}: resumed report case mismatch")
    evidence_log_path = simulation_log_path if simulation_log_path.is_file() else engine_log_path
    runtime_health = json.loads(health_path.read_text(encoding="utf-8"))
    health_errors = _runtime_health_errors(runtime_health)
    if health_errors:
        raise RuntimeError(
            f"{case_name}: reused runtime health is invalid: " + "; ".join(health_errors)
        )
    return {
        "case": case_name, "mutant": mutant_id, "command": ["REUSED_EXACT_BYTE_RUN"],
        "elapsed_s": 0.0, "exit_code": 0, "reused": True,
        "report_path": report_path.as_posix(), "report_bytes": report_path.stat().st_size,
        "report_sha256": _sha256(report_path), "log_path": evidence_log_path.as_posix(),
        "log_bytes": evidence_log_path.stat().st_size, "log_sha256": _sha256(evidence_log_path),
        "engine_log_path": engine_log_path.as_posix(), "engine_log_bytes": engine_log_path.stat().st_size,
        "engine_log_sha256": _sha256(engine_log_path),
        "runtime_health_path": health_path.as_posix(),
        "runtime_health_bytes": health_path.stat().st_size,
        "runtime_health_sha256": _sha256(health_path),
        "runtime_health": runtime_health,
    }


def _evaluate_with_overlay(overlay: Path, case_name: str) -> dict[str, dict[str, Any]]:
    evaluation_root = overlay.parents[1] / "evaluations"
    evaluation_root.mkdir(parents=True, exist_ok=True)
    evaluation_dir = Path(tempfile.mkdtemp(prefix="simufire_mutation_eval_", dir=evaluation_root))
    try:
        for source in REPORTS_DIR.iterdir():
            if source.is_file() and source.suffix in (".json", ".log"):
                shutil.copyfile(source, evaluation_dir / source.name)
        for suffix in (".json", ".log"):
            source = overlay / f"{case_name}{suffix}"
            if source.is_file():
                shutil.copyfile(source, evaluation_dir / source.name)
        module_name = f"validate_reference_cases_mutation_{time.time_ns()}"
        validator = _load_module(VALIDATOR_PATH, module_name)
        validator.REPORTS_DIR = evaluation_dir
        validator._ARTIFACT_CACHE.clear()
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            exit_code = validator.main([])
        sys.modules.pop(module_name, None)
        if exit_code not in (0, 1):
            raise RuntimeError(f"reference evaluator exited {exit_code}: {output.getvalue()}")
        aggregate_path = evaluation_dir / "reference_checks.json"
        if not aggregate_path.is_file():
            raise RuntimeError("reference evaluator did not write an aggregate")
        aggregate = json.loads(aggregate_path.read_text(encoding="utf-8"))
        checks = aggregate.get("checks")
        if not isinstance(checks, list) or len(checks) != 530:
            raise RuntimeError("reference aggregate is missing or truncated")
        names = [item.get("name") for item in checks]
        if len(names) != len(set(names)):
            raise RuntimeError("reference aggregate contains duplicate check names")
        return {item["name"]: item for item in checks}
    finally:
        shutil.rmtree(evaluation_dir, ignore_errors=True)


def _evaluate_mutant(mutant_id: str, control_dir: Path, mutant_dir: Path, run_records: list[dict[str, Any]], canonical: dict[str, dict[str, Any]]) -> dict[str, Any]:
    contract = MUTATION_MANIFEST[mutant_id]
    case_name = contract["case"]
    expected_names = contract["checks"]
    if len(expected_names) != len(set(expected_names)):
        raise RuntimeError(f"{mutant_id}: duplicate names in mutation manifest")
    control = _evaluate_with_overlay(control_dir, case_name)
    mutated = _evaluate_with_overlay(mutant_dir, case_name)
    missing = [name for name in expected_names if name not in control or name not in mutated]
    if missing:
        raise RuntimeError(f"{mutant_id}: missing checks: {missing}")
    non_required = [name for name in expected_names if not canonical.get(name, {}).get("required")]
    if non_required:
        raise RuntimeError(f"{mutant_id}: non-required manifest checks: {non_required}")
    negative_control_pass = all(control[name]["pass"] for name in expected_names)
    new_failures = [name for name in expected_names if control[name]["pass"] and not mutated[name]["pass"]]
    records = [record for record in run_records if record["case"] == case_name and record["mutant"] in (None, mutant_id)]
    return {
        "killed": bool(new_failures), "required_checks_evaluated": len(expected_names),
        "evaluated_check_names": expected_names, "new_failed_check_names": new_failures,
        "reports": records,
        "input_fresh": all(record["report_bytes"] > 0 and record["log_bytes"] > 0 for record in records),
        "manifest_complete": len(records) == 2, "negative_control_pass": negative_control_pass,
        "control_values": {name: control[name]["actual"] for name in expected_names},
        "mutant_values": {name: mutated[name]["actual"] for name in expected_names},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--output", type=Path, default=ROOT / "tools/reports/mutation_results.json")
    parser.add_argument("--evidence-dir", type=Path, default=ROOT / "runs/motor_post_audit_p1_remediation_p1r5/mutation_campaign")
    parser.add_argument("--resume", action="store_true", help="Reuse complete exact-byte controls already present in evidence-dir")
    parser.add_argument("--evaluate-only", action="store_true", help="Evaluate a complete existing evidence directory without Godot runs")
    args = parser.parse_args(argv)
    if _godot_processes():
        print("ERROR: residual Godot processes exist before the campaign", file=sys.stderr)
        return 2
    try:
        godot = _find_godot(args.godot)
        godot_version, version_probe_health = _verify_godot_version(godot)
        source_commit = _git_output("rev-parse", "HEAD")
        canonical_data = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
        canonical_checks = {item["name"]: item for item in canonical_data["checks"]}
        required_count = sum(1 for item in canonical_checks.values() if item["required"])
        if required_count != 350 or len(canonical_checks) != 530:
            raise RuntimeError("canonical reference contract is not the frozen 530/350 corpus")
        evidence_dir = args.evidence_dir.resolve()
        if evidence_dir.exists() and not args.resume:
            raise RuntimeError(f"evidence directory already exists: {evidence_dir}")
        control_root, mutant_root = evidence_dir / "controls", evidence_dir / "mutants"
        run_records: list[dict[str, Any]] = []
        for case_name in sorted({item["case"] for item in MUTATION_MANIFEST.values()}):
            existing = _record_existing(case_name, control_root / case_name) if args.resume else None
            if existing is not None:
                run_records.append(existing)
                print(f"CONTROL {case_name}\n  REUSED exact-byte", flush=True)
                continue
            print(f"CONTROL {case_name}", flush=True)
            record = _run_case(
                godot,
                godot_version,
                source_commit,
                case_name,
                control_root / case_name,
                None,
                args.timeout,
            )
            run_records.append(record)
            print(f"  DONE {case_name} {record['elapsed_s']:.3f}s", flush=True)
        for mutant_id, contract in MUTATION_MANIFEST.items():
            case_name = contract["case"]
            existing = _record_existing(case_name, mutant_root / mutant_id, mutant_id) if args.evaluate_only else None
            if existing is not None:
                run_records.append(existing)
                print(f"MUTANT {mutant_id} {case_name}\n  REUSED exact-byte", flush=True)
                continue
            if args.evaluate_only:
                raise RuntimeError(f"missing existing mutant evidence: {mutant_id}/{case_name}")
            print(f"MUTANT {mutant_id} {case_name}", flush=True)
            record = _run_case(
                godot,
                godot_version,
                source_commit,
                case_name,
                mutant_root / mutant_id,
                mutant_id,
                args.timeout,
            )
            run_records.append(record)
            print(f"  DONE {mutant_id} {record['elapsed_s']:.3f}s", flush=True)
        results = {mutant_id: _evaluate_mutant(mutant_id, control_root / contract["case"], mutant_root / mutant_id, run_records, canonical_checks) for mutant_id, contract in MUTATION_MANIFEST.items()}
        report = {
            "schema_version": 2, "generated_at": datetime.datetime.now(datetime.UTC).isoformat(),
            "baseline_required_checks": required_count,
            "manifest_complete": set(results) == set(MUTATION_MANIFEST), "mutants": results,
            "killed_count": sum(1 for result in results.values() if result["killed"]),
            "total_mutants": len(results),
        }
        report["kill_rate_global"] = report["killed_count"] / report["total_mutants"]
        auditor = _load_module(AUDITOR_PATH, "audit_mutation_trust_runtime")
        errors = auditor.validate_mutation_report(report, required_count)
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 1
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        (evidence_dir / "campaign_manifest.json").write_text(
            json.dumps(
                {
                    "source_commit": source_commit,
                    "godot_version": godot_version,
                    "version_probe_health": version_probe_health,
                    "runs": run_records,
                    "mutation_manifest": MUTATION_MANIFEST,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"PASS: {report['killed_count']}/{report['total_mutants']} mutants killed")
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    finally:
        residual = _godot_processes()
        if residual:
            print(f"ERROR: residual Godot processes after campaign: {residual}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
