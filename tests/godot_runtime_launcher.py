"""Shared fail-closed launcher for Godot runtime tests on Windows."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
from typing import Collection

from tools import mutation_audit


_ACCESS_VIOLATION = 0xC0000005


def _health_errors(
    health: dict[str, object], allowed_exit_codes: Collection[int] | None
) -> list[str]:
    errors: list[str] = []
    if os.name == "nt":
        if health.get("console_wrapper_bypassed") is not True:
            errors.append("Godot console wrapper was not bypassed")
        if health.get("windows_error_ui_suppressed") is not True:
            errors.append("Windows application-error UI was not suppressed")
    if health.get("timed_out") is not False:
        errors.append("Godot run timed out")
    if health.get("error_dialogs") != []:
        errors.append(f"Godot popup detected: {health.get('error_dialogs')}")
    if health.get("residual_godot_processes") != []:
        errors.append(
            f"residual Godot processes: {health.get('residual_godot_processes')}"
        )
    if health.get("process_quiescent") is not True:
        errors.append("Godot process state did not become quiescent")

    wrapper_exit = health.get("wrapper_exit_code")
    if allowed_exit_codes is not None and wrapper_exit not in allowed_exit_codes:
        errors.append(f"Godot exited {wrapper_exit}, expected {sorted(allowed_exit_codes)}")
    observed = health.get("observed_godot_processes")
    if not isinstance(observed, list):
        errors.append("observed Godot process inventory is missing")
    else:
        for process in observed:
            exit_code = process.get("exit_code") if isinstance(process, dict) else None
            if exit_code is None:
                errors.append(f"observed Godot exit code is missing: {process}")
            elif exit_code == _ACCESS_VIOLATION:
                errors.append(f"Godot access violation: {process}")
            elif allowed_exit_codes is not None and exit_code not in allowed_exit_codes:
                errors.append(
                    f"Godot child exited {exit_code}, expected "
                    f"{sorted(allowed_exit_codes)}: {process}"
                )
    capture_races = health.get("process_handle_capture_races", [])
    if not isinstance(capture_races, list):
        errors.append("process handle capture race inventory is malformed")
    capture_failures = health.get("process_handle_capture_failures", [])
    if not isinstance(capture_failures, list):
        errors.append("process handle capture failure inventory is malformed")
    elif capture_failures:
        errors.append(f"Godot process handle capture failed: {capture_failures}")
    return errors


def run_godot(
    command: list[str | Path],
    *,
    timeout_s: int,
    allowed_exit_codes: Collection[int] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run one Godot command without windows and fail on infrastructure faults."""
    preexisting = mutation_audit._godot_processes()
    if preexisting:
        raise AssertionError(f"pre-existing Godot processes: {preexisting}")

    appdata_path = mutation_audit.ROOT / "runs/godot_test_appdata"
    appdata_path.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["APPDATA"] = str(appdata_path)
    completed, health = mutation_audit._run_monitored(
        [str(argument) for argument in command], timeout_s, environment
    )
    errors = _health_errors(health, allowed_exit_codes)
    if errors:
        raise AssertionError(
            "Godot runtime health failure:\n"
            + "\n".join(f"- {error}" for error in errors)
            + "\n"
            + json.dumps(health, ensure_ascii=True, indent=2, sort_keys=True)
        )
    return completed
