"""Fail-closed contracts for the supported headless scenario runner."""

from __future__ import annotations

import importlib.util
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "scripts" / "run_scenario.py"
HEADLESS_PATH = ROOT / "tools" / "run_scenario_headless.gd"

SPEC = importlib.util.spec_from_file_location("simufire_run_scenario", RUNNER_PATH)
assert SPEC and SPEC.loader
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def _write_artifacts(
    out_dir: Path,
    *,
    token: str,
    scenario: Path,
    duration_s: float = 1.0,
    sim_time_s: float = 1.0,
    status: str = "completed",
    entrypoint: str = RUNNER._RUNNER_SCENE,
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "summary.json").write_text(
        json.dumps({"schema_version": "simufire_technical_summary_v1"}),
        encoding="utf-8",
    )
    (out_dir / "events.json").write_text("[]", encoding="utf-8")
    (out_dir / "sim_log.txt").write_text("ok\n", encoding="utf-8")
    (out_dir / "sim_log.csv").write_text("time_s\n1.0\n", encoding="utf-8")
    (out_dir / "run_manifest.json").write_text(
        json.dumps(
            {
                "schema_version": "simufire_run_scenario_manifest_v1",
                "status": status,
                "run_token": token,
                "runner_entrypoint": entrypoint,
                "scenario_path": str(scenario.resolve()),
                "duration_s": duration_s,
                "sim_time_s": sim_time_s,
            }
        ),
        encoding="utf-8",
    )


def _validate(out_dir: Path, scenario: Path, token: str, duration: float = 1.0):
    return RUNNER._validate_outputs(
        out_dir,
        run_token=token,
        scenario=scenario,
        expected_duration_s=duration,
    )


def test_valid_completion_certificate_passes(tmp_path):
    scenario = tmp_path / "case.json"
    scenario.write_text("{}", encoding="utf-8")
    out_dir = tmp_path / "out"
    _write_artifacts(out_dir, token="fresh", scenario=scenario)
    assert _validate(out_dir, scenario, "fresh") == []


def test_stale_manifest_token_fails(tmp_path):
    scenario = tmp_path / "case.json"
    scenario.write_text("{}", encoding="utf-8")
    out_dir = tmp_path / "out"
    _write_artifacts(out_dir, token="old", scenario=scenario)
    assert any("stale" in item for item in _validate(out_dir, scenario, "new"))


def test_truncated_run_fails(tmp_path):
    scenario = tmp_path / "case.json"
    scenario.write_text("{}", encoding="utf-8")
    out_dir = tmp_path / "out"
    _write_artifacts(
        out_dir, token="token", scenario=scenario, duration_s=10.0, sim_time_s=9.0
    )
    assert any("truncated" in item for item in _validate(
        out_dir, scenario, "token", 10.0
    ))


def test_wrong_case_duration_status_and_entrypoint_fail(tmp_path):
    scenario = tmp_path / "case.json"
    other = tmp_path / "other.json"
    scenario.write_text("{}", encoding="utf-8")
    other.write_text("{}", encoding="utf-8")
    out_dir = tmp_path / "out"
    _write_artifacts(
        out_dir,
        token="token",
        scenario=other,
        duration_s=2.0,
        status="running",
        entrypoint="res://wrong.tscn",
    )
    failures = _validate(out_dir, scenario, "token", 1.0)
    assert any("scenario_path" in item for item in failures)
    assert any("duration_s" in item for item in failures)
    assert any("completed" in item for item in failures)
    assert any("runner_entrypoint" in item for item in failures)


def test_missing_required_artifact_fails(tmp_path):
    scenario = tmp_path / "case.json"
    scenario.write_text("{}", encoding="utf-8")
    out_dir = tmp_path / "out"
    _write_artifacts(out_dir, token="token", scenario=scenario)
    (out_dir / "events.json").unlink()
    assert "missing events.json" in _validate(out_dir, scenario, "token")


def test_only_fatal_script_patterns_are_rejected():
    assert RUNNER._fatal_godot_errors("SCRIPT ERROR: Parse Error: bad syntax")
    assert RUNNER._fatal_godot_errors("Can't load the script foo.gd")
    assert RUNNER._fatal_godot_errors("doesn't inherit from SceneTree or MainLoop")
    assert RUNNER._fatal_godot_errors("WARNING: unused variable") == []


def test_runner_uses_scene_and_binds_marker_to_manifest_token():
    python_source = RUNNER_PATH.read_text(encoding="utf-8")
    gd_source = HEADLESS_PATH.read_text(encoding="utf-8")
    assert 'f"--run-token={run_token}"' in python_source
    assert 'f"RUN_SCENARIO PASS token={run_token}"' in python_source
    assert '"run_token": _run_token' in gd_source
    assert '"status": "completed"' in gd_source
    assert '"runner_entrypoint": "res://tools/run_scenario_headless.tscn"' in gd_source
    assert "--script" not in python_source


def test_exit_zero_with_compile_error_and_stale_outputs_fails(
    tmp_path, monkeypatch, capsys
):
    scenario = tmp_path / "case.json"
    scenario.write_text('{"duration_s": 1.0}', encoding="utf-8")
    out_dir = tmp_path / "out"
    _write_artifacts(out_dir, token="old", scenario=scenario)
    fake_godot = tmp_path / "godot.exe"
    fake_godot.write_text("", encoding="utf-8")

    monkeypatch.setattr(RUNNER.secrets, "token_hex", lambda _size: "fresh")
    monkeypatch.setattr(
        RUNNER.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args[0], 0, "SCRIPT ERROR: Parse Error: invalid source\n", ""
        ),
    )

    result = RUNNER.main(
        [
            str(scenario),
            "--out-dir",
            str(out_dir),
            "--godot",
            str(fake_godot),
            "--duration",
            "1",
        ]
    )
    captured = capsys.readouterr()
    assert result == 1
    assert "fatal Godot error" in captured.err
    assert "[run_scenario] summary:" not in captured.out


def test_current_pass_marker_without_matching_token_fails_contract():
    source = RUNNER_PATH.read_text(encoding="utf-8")
    assert 'expected_pass_marker = f"RUN_SCENARIO PASS token={run_token}"' in source
    assert "expected_pass_marker not in combined" in source
    assert 'manifest.get("run_token") != run_token' in source


def test_fatal_errors_are_read_from_the_godot_log_too():
    source = RUNNER_PATH.read_text(encoding="utf-8")
    assert 'diagnostic_output = combined + _load_text(out_dir / "godot.log")' in source
    assert "_fatal_godot_errors(diagnostic_output)" in source
