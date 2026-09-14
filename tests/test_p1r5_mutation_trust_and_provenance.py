"""P1R5 contracts for mutation trust and reference provenance."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
AUDITOR_PATH = ROOT / "scripts/simulation/audit_mutation_trust.py"
MUTATION_RUNNER_PATH = ROOT / "tools/mutation_audit.py"
REFERENCE_REPORT = ROOT / "sim/validation/reports/reference_checks.json"
MUTATION_REPORT = ROOT / "tools/reports/mutation_results.json"
CASE_RUNNER = ROOT / "sim/validation/CaseRunner.gd"
CREDIBILITY_REPORTER = ROOT / "tools/credibility_report.py"
VALIDATOR_PATH = ROOT / "scripts/simulation/validate_reference_cases.py"


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


def _load_validator():
    module_name = "validate_reference_cases_mutation_contract"
    spec = importlib.util.spec_from_file_location(
        module_name, VALIDATOR_PATH
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def test_current_mutation_report_is_complete_and_non_vacuous():
    auditor = _load_auditor()
    report = json.loads(MUTATION_REPORT.read_text(encoding="utf-8"))
    reference = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
    errors = auditor.validate_mutation_report(
        report, expected_required_count=reference["required_count"]
    )

    assert errors == []
    assert report["killed_count"] == report["total_mutants"] == 8
    assert report["worktree_clean"] is True
    assert len(report["source_commit"]) == 40
    assert len(report["source_tree_oid"]) == 40
    assert len(report["reference_report_sha256"]) == 64
    assert len(report["required_check_names_sha256"]) == 64


def test_mutation_overlay_uses_current_contract_and_explicit_evidence_mode():
    runner_source = MUTATION_RUNNER_PATH.read_text(encoding="utf-8")
    validator_source = (
        ROOT / "scripts/simulation/validate_reference_cases.py"
    ).read_text(encoding="utf-8")

    assert "len(checks) != 530" not in runner_source
    assert "verify_gap_evidence: bool = True" in validator_source
    assert (
        "_apply_gap_dispositions(\n"
        "        all_checks, verify_evidence=verify_gap_evidence\n"
        "    )"
    ) in validator_source
    assert (
        'source_tree_oid = _git_output("rev-parse", f"{source_commit}^{{tree}}")'
        in runner_source
    )


@pytest.fixture
def overlay_evaluation(tmp_path, monkeypatch):
    runner = _load_mutation_runner()
    validator = _load_validator()
    reports = tmp_path / "canonical"
    reports.mkdir()
    report = reports / "case.json"
    report.write_text('{"actual": 2.0}', encoding="utf-8")
    validator.REPORTS_DIR = reports
    evidence = validator._artifact_record(report)
    check = validator.Check("gap", 2.0, maximum=1.0, required=False)
    validator._GAP_DISPOSITIONS = {"gap": {"disposition": "VERIFIED_MODEL_LIMITATION"}}
    validator._GAP_DISPOSITION_EVIDENCE = {
        "gap": {**check.to_dict(), "source_artifacts": [evidence]}
    }

    def evaluate(argv, *, verify_gap_evidence=True):
        path = validator.REPORTS_DIR / "case.json"
        actual = json.loads(path.read_text(encoding="utf-8"))["actual"]
        check = validator.Check(
            "gap", actual, maximum=1.0, required=False,
            provenance={"artifacts": [validator._artifact_record(path)]},
        )
        validator._apply_gap_dispositions([check], verify_evidence=verify_gap_evidence)
        (validator.REPORTS_DIR / "reference_checks.json").write_text(
            json.dumps({"checks": [check.to_dict()]}), encoding="utf-8"
        )
        return 0

    validator.main = evaluate
    monkeypatch.setattr(runner, "REPORTS_DIR", reports)
    monkeypatch.setattr(runner, "_load_module", lambda *args: validator)
    overlay = tmp_path / "campaign" / "controls" / "case"
    overlay.mkdir(parents=True)
    (overlay / "case.json").write_bytes(report.read_bytes())
    return runner, overlay, evidence


def test_control_overlay_accepts_identical_bytes_at_temporary_path(overlay_evaluation):
    runner, overlay, evidence = overlay_evaluation
    checks = runner._evaluate_with_overlay(overlay, "case", 1)
    assert checks["gap"]["provenance"]["artifacts"] == [evidence]


@pytest.mark.parametrize(
    ("payload", "reason"),
    [
        ('{"actual": 3.0}', "stale gap evidence"),
        ('{ "actual": 2.0 }', "stale gap source artifacts"),
        ('{"actual": 0.5}', "no longer a failing non-gating check"),
    ],
)
def test_control_overlay_rejects_stale_or_passing_gap(overlay_evaluation, payload, reason):
    runner, overlay, _ = overlay_evaluation
    (overlay / "case.json").write_text(payload, encoding="utf-8")
    with pytest.raises(ValueError, match=reason):
        runner._evaluate_with_overlay(overlay, "case", 1)


def test_mutant_evaluation_limits_bypass_to_mutated_side(tmp_path, monkeypatch):
    runner = _load_mutation_runner()
    calls = []
    monkeypatch.setattr(runner, "MUTATION_MANIFEST", {"test": {"case": "case", "checks": ["check"]}})

    def evaluate(path, case, count, **kwargs):
        mutated = kwargs.get("mutated", False)
        calls.append((path.name, mutated))
        return {"check": {"actual": 0 if mutated else 1, "pass": not mutated}}

    monkeypatch.setattr(runner, "_evaluate_with_overlay", evaluate)
    result = runner._evaluate_mutant(
        "test", tmp_path / "control", tmp_path / "mutant", [], {"check": {"required": True}}
    )
    assert calls == [("control", False), ("mutant", True)]
    assert result["killed"] is True
    assert result["negative_control_pass"] is True


@pytest.mark.parametrize("actual", [3.0, 0.5])
def test_explicit_mutant_overlay_allows_changed_optional_gap(overlay_evaluation, actual):
    runner, overlay, _ = overlay_evaluation
    (overlay / "case.json").write_text(json.dumps({"actual": actual}), encoding="utf-8")
    checks = runner._evaluate_with_overlay(overlay, "case", 1, mutated=True)
    assert checks["gap"]["actual"] == actual
    assert checks["gap"]["required"] is False
    assert checks["gap"]["pass"] is (actual <= 1.0)
    assert ("disposition" in checks["gap"]) is (actual > 1.0)


def test_gap_evidence_bypass_is_explicit_and_canonical_mode_stays_strict(
    monkeypatch,
):
    validator = _load_validator()
    check = validator.Check(
        name="mutation_only_gap",
        actual=2.0,
        maximum=1.0,
        required=False,
        provenance={"artifacts": ["mutated.json"]},
    )
    monkeypatch.setattr(
        validator,
        "_GAP_DISPOSITIONS",
        {"mutation_only_gap": {"disposition": "VERIFIED_MODEL_LIMITATION"}},
    )
    monkeypatch.setattr(
        validator,
        "_GAP_DISPOSITION_EVIDENCE",
        {
            "mutation_only_gap": {
                **check.to_dict(),
                "actual": 3.0,
                "source_artifacts": ["canonical.json"],
            }
        },
    )

    with pytest.raises(ValueError, match="stale gap evidence"):
        validator._apply_gap_dispositions([check])

    validator._apply_gap_dispositions([check], verify_evidence=False)
    assert check.disposition == "VERIFIED_MODEL_LIMITATION"


def test_mutation_overlay_omits_only_non_gating_gaps_that_become_passing(
    monkeypatch,
):
    validator = _load_validator()
    passing_gap = validator.Check(
        name="mutation_only_passing_gap",
        actual=0.5,
        maximum=1.0,
        required=False,
    )
    monkeypatch.setattr(
        validator,
        "_GAP_DISPOSITIONS",
        {
            "mutation_only_passing_gap": {
                "disposition": "VERIFIED_MODEL_LIMITATION"
            }
        },
    )
    monkeypatch.setattr(
        validator,
        "_GAP_DISPOSITION_EVIDENCE",
        {"mutation_only_passing_gap": passing_gap.to_dict()},
    )

    with pytest.raises(
        ValueError, match="no longer a failing non-gating check"
    ):
        validator._apply_gap_dispositions([passing_gap])

    validator._apply_gap_dispositions(
        [passing_gap], verify_evidence=False
    )
    assert passing_gap.disposition is None

    passing_gap.required = True
    with pytest.raises(
        ValueError, match="no longer a failing non-gating check"
    ):
        validator._apply_gap_dispositions(
            [passing_gap], verify_evidence=False
        )


def test_vacuous_stale_mutation_report_is_rejected():
    auditor = _load_auditor()
    report = json.loads(MUTATION_REPORT.read_text(encoding="utf-8"))
    reference = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
    report["baseline_required_checks"] = 381
    report["mutants"] = {
        "M-HRR": {**auditor.example_valid_mutation_result(), "required_checks_evaluated": 0}
    }
    errors = auditor.validate_mutation_report(
        report, expected_required_count=reference["required_count"]
    )

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


def test_process_that_exits_before_handle_capture_is_recorded_as_a_race(monkeypatch):
    runner = _load_mutation_runner()
    process = {
        "image_name": "Godot_v4.7.1-stable_win64_console.exe",
        "pid": 6636,
    }
    monkeypatch.setattr(runner, "_godot_processes", lambda: [process])
    monkeypatch.setattr(
        runner,
        "_open_process_handle",
        lambda _pid: (None, runner._ERROR_INVALID_PARAMETER),
    )
    observed = {}
    handles = {}
    capture_races = {}
    capture_failures = {}

    current = runner._sample_godot_processes(
        observed, handles, capture_races, capture_failures
    )

    assert current == [process]
    assert observed == {}
    assert handles == {}
    assert capture_failures == {}
    assert capture_races == {
        (process["image_name"], process["pid"]): {
            **process,
            "open_process_error": runner._ERROR_INVALID_PARAMETER,
            "capture_status": "exited_before_handle_capture",
        }
    }


def test_open_process_handle_preserves_the_windows_error_code():
    runner = _load_mutation_runner()

    handle, error = runner._open_process_handle(0)

    assert handle is None
    assert error == runner._ERROR_INVALID_PARAMETER


def test_process_handle_access_failure_remains_fail_closed():
    runner = _load_mutation_runner()
    health = {
        "contract": "windows-window-process-exit-v2",
        "windows_error_ui_suppressed": True,
        "wrapper_exit_code": 0,
        "timed_out": False,
        "error_dialogs": [],
        "observed_godot_processes": [],
        "process_handle_capture_races": [],
        "process_handle_capture_failures": [
            {
                "image_name": "Godot_v4.7.1-stable_win64.exe",
                "pid": 1234,
                "open_process_error": 5,
                "capture_status": "open_process_failed",
            }
        ],
        "residual_godot_processes": [],
        "process_quiescent": True,
        "post_exit_observation_s": 2.0,
    }

    errors = runner._runtime_health_errors(health)

    assert any("handle capture failed" in error.lower() for error in errors)


def test_shared_launcher_rejects_process_handle_capture_failure():
    from tests import godot_runtime_launcher

    health = {
        "console_wrapper_bypassed": True,
        "windows_error_ui_suppressed": True,
        "wrapper_exit_code": 0,
        "timed_out": False,
        "error_dialogs": [],
        "observed_godot_processes": [],
        "process_handle_capture_races": [],
        "process_handle_capture_failures": [
            {
                "image_name": "Godot_v4.7.1-stable_win64.exe",
                "pid": 1234,
                "open_process_error": 5,
                "capture_status": "open_process_failed",
            }
        ],
        "residual_godot_processes": [],
        "process_quiescent": True,
    }

    errors = godot_runtime_launcher._health_errors(health, {0})

    assert any("handle capture failed" in error.lower() for error in errors)


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
    assert len(required) == 346

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
    ("name", "expected", "tolerance", "passed", "disposition"),
    [
        ("ghanekar_far_hall_o2_response_time_s", 198.0, 30.0, False,
         "VERIFIED_MODEL_LIMITATION"),
        ("ghanekar_kitchen_far_hall_fed_0_3_s", 546.0, 515.0, True, None),
        ("ghanekar_kitchen_far_hall_fed_1_0_s", 812.75, 126.0, True, None),
    ],
)
def test_ghanekar_demotions_have_current_truthful_disposition(
    name, expected, tolerance, passed, disposition
):
    report = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
    check = next(item for item in report["checks"] if item["name"] == name)

    assert check["required"] is False
    assert check["pass"] is passed
    assert check["expected"] == expected
    assert check["tolerance"] == tolerance
    assert check.get("disposition") == disposition
    assert "PROVISIONAL" not in check["note"].upper()
