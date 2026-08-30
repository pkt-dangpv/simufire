from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from scripts.simulation.validate_tick_boundary_trace import validate_trace
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim/validation/CaseRunner.gd").read_text(encoding="utf-8")
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot() -> Path | None:
    return next((path for path in GODOT_CANDIDATES if path is not None and path.exists()), None)


def _run_report(godot: Path, output: Path, *, trace: bool) -> dict[str, object]:
    command = [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--",
            "--validation-case",
            "carbon_balance_creation",
            "--validation-duration",
            "0.25",
            "--validation-output",
            str(output),
        ]
    if trace:
        command.append("--validation-p1r2-tick-boundary-trace")
    completed = run_godot(
        command,
        timeout_s=90,
        allowed_exit_codes=(0, 2),
    )
    # The source case owns a 3 s baseline, while this ordering probe stops at
    # 0.25 s. Exit 2 is therefore expected; report creation is the runtime gate.
    assert completed.returncode in (0, 2), completed.stdout + completed.stderr
    assert output.is_file(), completed.stdout + completed.stderr
    return json.loads(output.read_text(encoding="utf-8-sig"))


def test_trace_validator_rejects_post_physics_sync() -> None:
    invalid: list[dict[str, object]] = []
    for tick in range(1, 4):
        events = [
            "tick_begin",
            "auxiliary_sync",
            "post_physics_mutation",
            "log_boundary",
            "auxiliary_sync",
        ]
        if tick == 3:
            events.append("final_snapshot")
        invalid.extend({"tick": tick, "event": event} for event in events)
    assert any("after physics" in failure for failure in validate_trace(invalid))


def test_runtime_trace_has_one_pre_physics_sync_and_is_deterministic(tmp_path: Path) -> None:
    godot = _godot()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    first_report = _run_report(godot, tmp_path / "first.json", trace=True)
    second_report = _run_report(godot, tmp_path / "second.json", trace=True)
    off_report = _run_report(godot, tmp_path / "off.json", trace=False)
    first = first_report["p1r2_tick_boundary_trace"]
    second = second_report["p1r2_tick_boundary_trace"]
    assert first == second
    assert validate_trace(first) == []
    first_report.pop("p1r2_tick_boundary_trace")
    assert first_report == off_report


def test_trace_path_is_explicit_and_default_inactive() -> None:
    assert "@export var _p1r2" not in ENGINE
    assert "--validation-p1r2-tick-boundary-trace" in CASE_RUNNER
    assert 'report["p1r2_tick_boundary_trace"]' in CASE_RUNNER
