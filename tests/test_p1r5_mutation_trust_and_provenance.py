"""P1R5 contracts for mutation trust and reference provenance."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
AUDITOR_PATH = ROOT / "scripts/simulation/audit_mutation_trust.py"
MUTATION_RUNNER_PATH = ROOT / "tools/mutation_audit.py"
REFERENCE_REPORT = ROOT / "sim/validation/reports/reference_checks.json"
MUTATION_REPORT = ROOT / "tools/reports/mutation_results.json"
CASE_RUNNER = ROOT / "sim/validation/CaseRunner.gd"
CREDIBILITY_REPORTER = ROOT / "tools/credibility_report.py"


def _load_auditor():
    assert AUDITOR_PATH.is_file(), "P1R5 mutation auditor is missing"
    spec = importlib.util.spec_from_file_location("audit_mutation_trust", AUDITOR_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_mutation_runner():
    spec = importlib.util.spec_from_file_location("mutation_audit", MUTATION_RUNNER_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_current_mutation_report_is_complete_and_non_vacuous():
    auditor = _load_auditor()
    report = json.loads(MUTATION_REPORT.read_text(encoding="utf-8"))
    errors = auditor.validate_mutation_report(report, expected_required_count=350)

    assert errors == []
    assert report["killed_count"] == report["total_mutants"] == 8


def test_vacuous_stale_mutation_report_is_rejected():
    auditor = _load_auditor()
    report = json.loads(MUTATION_REPORT.read_text(encoding="utf-8"))
    report["baseline_required_checks"] = 381
    report["mutants"] = {
        "M-HRR": {**auditor.example_valid_mutation_result(), "required_checks_evaluated": 0}
    }
    errors = auditor.validate_mutation_report(report, expected_required_count=350)

    assert any("required_checks_evaluated" in error for error in errors)
    assert any("mutants" in error for error in errors)
    assert any("baseline_required_checks" in error for error in errors)


@pytest.mark.parametrize(
    ("mutation", "fragment"),
    [
        ({"required_checks_evaluated": 0}, "required_checks_evaluated"),
        ({"reports": []}, "reports"),
        ({"input_fresh": False}, "fresh"),
        ({"evaluated_check_names": ["a", "a"]}, "duplicate"),
        ({"manifest_complete": False}, "manifest"),
        ({"negative_control_pass": False}, "negative control"),
    ],
)
def test_mutation_result_validation_fails_closed(mutation, fragment):
    auditor = _load_auditor()
    valid = auditor.example_valid_mutation_result()
    valid.update(mutation)
    errors = auditor.validate_mutation_result("M-HRR", valid)
    assert any(fragment in error.lower() for error in errors)


def test_wrapper_exit_zero_with_child_error_popup_is_rejected():
    auditor = _load_auditor()
    valid = auditor.example_valid_mutation_result()
    valid["reports"][0]["runtime_health"] = {
        "wrapper_exit_code": 0,
        "error_dialogs": [
            "Godot_v4.7.1-stable_win64.exe - Error de la aplicacion"
        ],
        "residual_godot_processes": [],
        "process_quiescent": True,
    }

    errors = auditor.validate_mutation_result("M-HRR", valid)

    assert any("popup" in error.lower() or "dialog" in error.lower() for error in errors)


@pytest.mark.parametrize(
    "title",
    [
        "Godot_v4.7.1-stable_win64.exe - Error de la aplicacion",
        "Godot_v4.7.1-stable_win64.exe - Application Error",
    ],
)
def test_godot_application_error_window_titles_are_detected(title):
    runner = _load_mutation_runner()

    assert runner._is_godot_error_window_title(title)


def test_enum_windows_zero_without_last_error_is_not_a_win32_failure():
    runner = _load_mutation_runner()

    assert not runner._enum_windows_failed(0, 0)
    assert runner._enum_windows_failed(0, 5)
    assert not runner._enum_windows_failed(1, 5)


def test_crash_word_inside_an_evidence_path_is_not_a_log_failure():
    runner = _load_mutation_runner()
    log = (
        "[Validation] Reporte guardado en "
        "C:/simufire/runs/p1r5_crash_aware_campaign/report.json"
    )

    assert runner._forbidden_log_markers(log) == []


def test_explicit_engine_crash_log_message_is_rejected():
    runner = _load_mutation_runner()

    assert "crash" in runner._forbidden_log_markers("Godot engine crashed unexpectedly")


def test_child_access_violation_is_rejected_even_when_wrapper_exits_zero():
    runner = _load_mutation_runner()
    health = {
        "contract": "windows-window-process-exit-v2",
        "windows_error_ui_suppressed": True,
        "wrapper_exit_code": 0,
        "timed_out": False,
        "error_dialogs": [],
        "observed_godot_processes": [
            {
                "image_name": "Godot_v4.7.1-stable_win64.exe",
                "pid": 1234,
                "exit_code": 0xC0000005,
            }
        ],
        "residual_godot_processes": [],
        "process_quiescent": True,
        "post_exit_observation_s": 2.0,
    }

    errors = runner._runtime_health_errors(health)

    assert any("access violation" in error.lower() for error in errors)


def test_monitored_launch_bypasses_the_windows_console_wrapper(tmp_path):
    runner = _load_mutation_runner()
    console = tmp_path / "Godot_v4.7.1-stable_win64_console.exe"
    engine = tmp_path / "Godot_v4.7.1-stable_win64.exe"
    console.write_bytes(b"wrapper")
    engine.write_bytes(b"engine")

    resolved, bypassed = runner._resolve_monitored_executable(console)

    assert resolved == engine
    assert bypassed is True


def test_monitored_launch_keeps_a_non_wrapper_executable(tmp_path):
    runner = _load_mutation_runner()
    engine = tmp_path / "Godot_v4.7.1-stable_win64.exe"
    engine.write_bytes(b"engine")

    resolved, bypassed = runner._resolve_monitored_executable(engine)

    assert resolved == engine
    assert bypassed is False


def test_case_command_uses_captured_output_instead_of_godot_log_file(tmp_path):
    runner = _load_mutation_runner()
    command = runner._build_case_command(
        Path("Godot_v4.7.1-stable_win64_console.exe"),
        "example_case",
        tmp_path / "example_case.json",
        tmp_path / "example_case.log",
        None,
    )

    assert "--headless" in command
    assert "--log-file" not in command


def test_every_required_reference_check_has_explicit_machine_provenance():
    report = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
    required = [check for check in report["checks"] if check["required"]]
    assert len(required) == 350

    for check in required:
        provenance = check.get("provenance")
        assert isinstance(provenance, dict), check["name"]
        assert provenance.get("case"), check["name"]
        assert provenance.get("source"), check["name"]
        assert provenance.get("measurement_layer"), check["name"]
        artifacts = provenance.get("artifacts")
        assert isinstance(artifacts, list) and artifacts, check["name"]
        for artifact in artifacts:
            assert artifact.get("path"), check["name"]
            assert artifact.get("bytes", -1) >= 0, check["name"]
            assert len(artifact.get("sha256", "")) == 64, check["name"]


def test_required_reference_check_names_are_unique():
    report = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
    names = [check["name"] for check in report["checks"] if check["required"]]
    assert len(names) == len(set(names))


def test_mutation_campaign_can_isolate_the_simulation_timeseries_log():
    source = CASE_RUNNER.read_text(encoding="utf-8")
    assert "--validation-simulation-log=" in source
    assert 'engine.log_file_path = String(_cli_args["validation_simulation_log"])' in source


def test_credibility_report_reads_the_authoritative_mutation_report():
    source = CREDIBILITY_REPORTER.read_text(encoding="utf-8")
    assert 'MUTATION_JSON = ROOT / "tools/reports/mutation_results.json"' in source


@pytest.mark.parametrize(
    ("name", "expected", "tolerance"),
    [
        ("ghanekar_far_hall_o2_response_time_s", 198.0, 30.0),
        ("ghanekar_kitchen_far_hall_fed_0_3_s", 546.0, 515.0),
        ("ghanekar_kitchen_far_hall_fed_1_0_s", 812.75, 126.0),
    ],
)
def test_ghanekar_demotions_have_final_truthful_disposition(name, expected, tolerance):
    report = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
    check = next(item for item in report["checks"] if item["name"] == name)

    assert check["required"] is False
    assert check["pass"] is False
    assert check["expected"] == expected
    assert check["tolerance"] == tolerance
    assert check.get("disposition") == "VERIFIED_MODEL_LIMITATION"
    assert "PROVISIONAL" not in check["note"].upper()
