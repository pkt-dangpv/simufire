#!/usr/bin/env python3
"""Fail-closed validation for SimuFire mutation audit reports."""

from __future__ import annotations

from typing import Any


EXPECTED_MUTANTS = {
    "M-HRR",
    "M-ENTR",
    "M-O2EXT",
    "M-YCO",
    "M-YHCN",
    "M-WALL",
    "M-VENT",
    "M-PRES",
}


def example_valid_mutation_result() -> dict[str, Any]:
    """Return the smallest structurally valid result used by contract tests."""
    return {
        "killed": True,
        "required_checks_evaluated": 1,
        "evaluated_check_names": ["example_required_check"],
        "new_failed_check_names": ["example_required_check"],
        "reports": [
            {
                "case": "example_case",
                "baseline_path": "baseline/example_case.json",
                "mutant_path": "mutant/example_case.json",
                "runtime_health": {
                    "contract": "windows-window-process-exit-v2",
                    "windows_error_ui_suppressed": True,
                    "started_at_utc": "2026-01-01T00:00:00+00:00",
                    "ended_at_utc": "2026-01-01T00:00:01+00:00",
                    "wrapper_exit_code": 0,
                    "timed_out": False,
                    "error_dialogs": [],
                    "observed_godot_processes": [
                        {
                            "image_name": "Godot_v4.7.1-stable_win64.exe",
                            "pid": 1,
                            "exit_code": 0,
                        }
                    ],
                    "residual_godot_processes": [],
                    "process_quiescent": True,
                    "post_exit_observation_s": 2.0,
                    "godot_executable": "Godot_v4.7.1-stable_win64_console.exe",
                    "godot_version": "4.7.1.stable.official.a13da4feb",
                    "source_commit": "0" * 40,
                    "case_path": "sim/validation/cases/example_case.json",
                    "case_blob_oid": "0" * 40,
                    "case_sha256": "0" * 64,
                    "command": ["Godot", "--headless"],
                },
            }
        ],
        "input_fresh": True,
        "manifest_complete": True,
        "negative_control_pass": True,
    }


def validate_mutation_result(mutant_id: str, result: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(result, dict):
        return [f"{mutant_id}: result must be an object"]

    evaluated = result.get("required_checks_evaluated")
    if not isinstance(evaluated, int) or isinstance(evaluated, bool) or evaluated <= 0:
        errors.append(f"{mutant_id}: required_checks_evaluated must be > 0")

    reports = result.get("reports")
    if not isinstance(reports, list) or not reports:
        errors.append(f"{mutant_id}: reports must be a non-empty list")
    else:
        for item in reports:
            if not isinstance(item, dict) or not item.get("case"):
                errors.append(f"{mutant_id}: reports contain an incomplete entry")
                continue
            health = item.get("runtime_health")
            if not isinstance(health, dict):
                errors.append(f"{mutant_id}: runtime health record is missing")
                continue
            if health.get("contract") != "windows-window-process-exit-v2":
                errors.append(f"{mutant_id}: runtime health contract is unsupported")
            if health.get("windows_error_ui_suppressed") is not True:
                errors.append(f"{mutant_id}: Windows error UI was not suppressed")
            if health.get("wrapper_exit_code") not in (0, 2):
                errors.append(f"{mutant_id}: Godot wrapper exit is invalid")
            if health.get("timed_out") is not False:
                errors.append(f"{mutant_id}: runtime timed out")
            if health.get("error_dialogs") != []:
                errors.append(f"{mutant_id}: runtime error dialog or popup detected")
            if health.get("residual_godot_processes") != []:
                errors.append(f"{mutant_id}: residual Godot process detected")
            if health.get("process_quiescent") is not True:
                errors.append(f"{mutant_id}: Godot process state is not quiescent")
            observed = health.get("observed_godot_processes")
            if not isinstance(observed, list) or not observed:
                errors.append(f"{mutant_id}: observed Godot processes are missing")
            else:
                for process in observed:
                    exit_code = (
                        process.get("exit_code") if isinstance(process, dict) else None
                    )
                    if exit_code is None:
                        errors.append(f"{mutant_id}: Godot child exit code is missing")
                    elif exit_code not in (0, 2):
                        errors.append(
                            f"{mutant_id}: Godot child exited 0x{exit_code:08X}"
                        )
            observed_s = health.get("post_exit_observation_s")
            if not isinstance(observed_s, (int, float)) or observed_s < 2.0:
                errors.append(f"{mutant_id}: post-exit observation is incomplete")
            for field in (
                "started_at_utc",
                "ended_at_utc",
                "godot_executable",
                "godot_version",
                "source_commit",
                "case_path",
                "case_blob_oid",
                "case_sha256",
                "command",
            ):
                if not health.get(field):
                    errors.append(f"{mutant_id}: runtime provenance missing {field}")

    if result.get("input_fresh") is not True:
        errors.append(f"{mutant_id}: inputs are not fresh")
    if result.get("manifest_complete") is not True:
        errors.append(f"{mutant_id}: manifest is missing or truncated")
    if result.get("negative_control_pass") is not True:
        errors.append(f"{mutant_id}: negative control did not pass")

    names = result.get("evaluated_check_names")
    if not isinstance(names, list) or not names:
        errors.append(f"{mutant_id}: evaluated check names are missing")
    elif len(names) != len(set(names)):
        errors.append(f"{mutant_id}: duplicate evaluated check names")
    elif isinstance(evaluated, int) and evaluated != len(names):
        errors.append(f"{mutant_id}: required_checks_evaluated disagrees with names")

    new_failures = result.get("new_failed_check_names")
    if not isinstance(new_failures, list) or not new_failures:
        errors.append(f"{mutant_id}: mutant has no new required-check failure")
    elif len(new_failures) != len(set(new_failures)):
        errors.append(f"{mutant_id}: duplicate new failed check names")

    if result.get("killed") is not True:
        errors.append(f"{mutant_id}: mutant survived")
    return errors


def validate_mutation_report(report: Any, expected_required_count: int) -> list[str]:
    if not isinstance(report, dict):
        return ["mutation report must be an object"]

    errors: list[str] = []
    if report.get("baseline_required_checks") != expected_required_count:
        errors.append(
            "baseline_required_checks does not match the frozen reference contract"
        )

    mutants = report.get("mutants")
    if not isinstance(mutants, dict):
        return [*errors, "mutants must be an object"]
    mutant_ids = set(mutants)
    if mutant_ids != EXPECTED_MUTANTS:
        missing = sorted(EXPECTED_MUTANTS - mutant_ids)
        extra = sorted(mutant_ids - EXPECTED_MUTANTS)
        errors.append(f"mutants set mismatch; missing={missing}, extra={extra}")

    for mutant_id in sorted(EXPECTED_MUTANTS & mutant_ids):
        errors.extend(validate_mutation_result(mutant_id, mutants[mutant_id]))

    if report.get("manifest_complete") is not True:
        errors.append("top-level manifest is missing or truncated")
    return errors
