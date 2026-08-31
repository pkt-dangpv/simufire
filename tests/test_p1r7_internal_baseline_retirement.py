"""P1R7 stale internal baselines must be retired narrowly and fail closed."""

from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot
from scripts.simulation import audit_validation_freshness as freshness


ROOT = Path(__file__).resolve().parents[1]
CASE_RUNNER = ROOT / "sim" / "validation" / "CaseRunner.gd"
DISPOSITIONS = ROOT / "sim" / "validation" / "baseline_gate_dispositions.json"
BASELINES = ROOT / "sim" / "validation" / "baselines"
FIXTURE = ROOT / "tests" / "fixtures" / "p1r7_internal_baseline_retirement.gd"
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)

EXPECTED = {
    "cfast_two_floor_stairwell": {
        "baseline_sha256": "c59f2c80360e68f761285d61cc2095f258987af43b113f4169f74a0fcb654f08",
        "failing_checks": [
            "room_upper_floor_vs_lower_floor_pressure_delta_pa",
        ],
    },
    "cfast_multi_fuel_couch_tv": {
        "baseline_sha256": "f9a3a5f5d26834769627ef3077ea72d3cea6a646eb291a3eb8587f072a3a5519",
        "failing_checks": [
            "peak_temp_upper_c_global",
            "room_0_final_smoke_kg",
            "room_0_final_temp_upper_raw_c",
        ],
    },
}


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def test_retirement_registry_is_exact_and_preserves_historical_contracts():
    registry = json.loads(DISPOSITIONS.read_text(encoding="utf-8"))

    assert registry["schema_version"] == 1
    assert set(registry) == {"schema_version", "dispositions"}
    assert set(registry["dispositions"]) == set(EXPECTED)

    for case_name, expected in EXPECTED.items():
        entry = registry["dispositions"][case_name]
        assert entry["finding_id"] == "A14-P1-001"
        assert entry["classification"] == "STALE_INTERNAL_REGRESSION_ARTIFACT"
        assert entry["status"] == "RETIRED_FROM_AUTHORITY_EVIDENCE"
        assert entry["exit_behavior"] == "NON_BLOCKING_PRESERVE_FAILURE"
        assert entry["record_preserved"] is True
        assert entry["runtime_authority"] == "NO-GO"
        assert entry["baseline_sha256"] == expected["baseline_sha256"]
        assert entry["expected_failing_checks"] == expected["failing_checks"]
        assert entry["historical_green_commit"] == "9c07bcdb1fe038e21ba3f6f6222e6c0f51565d0c"
        assert entry["review_commit"] == "be3352208e9ef78407e224400c3e75afa1e2b318"

        baseline_bytes = (BASELINES / f"{case_name}.json").read_bytes()
        assert hashlib.sha256(baseline_bytes).hexdigest() == expected["baseline_sha256"]


def test_case_runner_retirement_is_bound_to_hash_and_exact_failure_set():
    source = CASE_RUNNER.read_text(encoding="utf-8")
    resolver = _function(source, "_load_baseline_gate_disposition")

    assert 'BASELINE_GATE_DISPOSITIONS_PATH' in source
    assert 'FileAccess.get_sha256(baseline_path).to_lower()' in resolver
    assert 'FileAccess.get_sha256(report_path).to_lower()' in resolver
    assert 'entry.get("current_report_sha256", "")' in resolver
    assert 'expected_failing_checks.sort()' in resolver
    assert 'actual_failing_checks.sort()' in resolver
    assert 'expected_failing_checks != actual_failing_checks' in resolver
    assert 'String(entry.get("finding_id", "")) != "A14-P1-001"' in resolver
    assert 'String(entry.get("runtime_authority", "")) != "NO-GO"' in resolver
    assert 'bool(entry.get("record_preserved", false))' in resolver
    assert 'return {}' in resolver


def test_case_runner_preserves_failure_and_only_changes_exit_gate():
    source = CASE_RUNNER.read_text(encoding="utf-8")
    finalize = _function(source, "_finalize_validation_run")

    assert 'report["baseline"] = _compare_against_baseline' in finalize
    assert 'var all_pass: bool = bool(baseline_result.get("all_pass", false))' in finalize
    assert 'var disposition: Dictionary = _load_baseline_gate_disposition(' in finalize
    assert 'Baseline FAIL (retired from authority evidence by %s; checks preserved)' in finalize
    assert 'exit_code = 2' in finalize
    assert 'baseline_result["all_pass"] = true' not in finalize
    assert 'report["baseline"] = {}' not in finalize


def test_no_generic_case_runner_bypass_is_introduced():
    source = CASE_RUNNER.read_text(encoding="utf-8").lower()

    assert "validation_allow_baseline_failure" not in source
    assert "allow_baseline_failure" not in source
    assert '"*"' not in json.loads(DISPOSITIONS.read_text(encoding="utf-8"))["dispositions"]


def test_godot_runtime_disposition_is_fail_closed():
    godot = next(
        (candidate for candidate in GODOT_CANDIDATES if candidate and candidate.exists()),
        None,
    )
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")

    completed = run_godot(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(FIXTURE),
        ],
        timeout_s=60,
        allowed_exit_codes=(0,),
    )
    output = completed.stdout + completed.stderr
    assert "P1R7_INTERNAL_BASELINE_RETIREMENT_PASS" in output


def test_freshness_audit_classifies_only_exact_dispositions_as_retired():
    reports = {}
    baselines = {}
    for case_name in EXPECTED:
        report_path = ROOT / "sim" / "validation" / "reports" / f"{case_name}.json"
        baseline_path = BASELINES / f"{case_name}.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        disposition = freshness.get_baseline_gate_disposition(
            case_name,
            baseline_path,
            report_path,
            report["baseline"],
        )
        assert disposition is not None
        reports[case_name] = report_path
        baselines[case_name] = baseline_path

        changed = copy.deepcopy(report["baseline"])
        passing_name = next(
            name for name, check in changed["checks"].items() if check["pass"]
        )
        changed["checks"][passing_name]["pass"] = False
        assert freshness.get_baseline_gate_disposition(
            case_name,
            baseline_path,
            report_path,
            changed,
        ) is None

        changed_report = copy.deepcopy(report)
        failing_name = next(
            name for name, check in changed_report["baseline"]["checks"].items()
            if check["pass"] is False
        )
        changed_report["baseline"]["checks"][failing_name]["actual"] = 1e99
        changed_path = report_path.with_name(f"{case_name}.p1r8-mutated.json")
        changed_path.write_text(json.dumps(changed_report), encoding="utf-8")
        try:
            assert freshness.get_baseline_gate_disposition(
                case_name,
                baseline_path,
                changed_path,
                changed_report["baseline"],
            ) is None
        finally:
            changed_path.unlink()

    issues = []
    freshness.check_baseline_all_pass(reports, baselines, issues)
    assert [(issue.level, issue.category, issue.name) for issue in issues] == [
        (freshness.INFO, "baseline_retired", "cfast_multi_fuel_couch_tv"),
        (freshness.INFO, "baseline_retired", "cfast_two_floor_stairwell"),
    ]
