from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
GAS_EXCHANGE = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
FIXTURE = ROOT / "tests/fixtures/p1r_v3_global_extinction_gate.gd"
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot() -> Path | None:
    return next(
        (path for path in GODOT_CANDIDATES if path is not None and path.exists()),
        None,
    )


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_species_redistribution_requires_global_extinction() -> None:
    predicate = _function(THERMAL, "_is_building_post_extinction")
    assert "for room_id in _building.get_rooms().keys():" in predicate
    assert "candidate.hrr_kw > 0.1 or candidate.fire != null" in predicate
    assert THERMAL.count(
        "var fire_inactive: bool = _is_building_post_extinction()"
    ) == 2
    assert "room.hrr_kw <= 0.1 and room.fire == null" not in THERMAL


def test_smoke_settling_is_not_enabled_by_co_alone() -> None:
    cleanup = GAS_EXCHANGE.split(
        "\t\tvar cleanup_factor: float = _compute_postfire_cleanup_factor(room)", 1
    )[1].split("\n\t\t\t# Igual para CO/CO2:", 1)[0]
    smoke_guard = "\n\t\t\tif room.smoke_kg > 0.000001:"
    deposition = "\n\t\t\t\tvar deposited_smoke_kg: float = minf("
    assert smoke_guard in cleanup
    assert deposition in cleanup
    assert cleanup.index(smoke_guard) < cleanup.index(deposition)


def test_shared_launcher_isolates_writable_appdata(monkeypatch: pytest.MonkeyPatch) -> None:
    from tests import godot_runtime_launcher

    observed: dict[str, Path] = {}

    def fake_run(command, timeout_s, environment=None):
        assert environment is not None
        appdata = Path(environment["APPDATA"])
        assert appdata.is_dir()
        observed["appdata"] = appdata
        return subprocess.CompletedProcess(command, 0, "", ""), {
            "console_wrapper_bypassed": True,
            "windows_error_ui_suppressed": True,
            "wrapper_exit_code": 0,
            "timed_out": False,
            "error_dialogs": [],
            "observed_godot_processes": [],
            "process_handle_capture_races": [],
            "process_handle_capture_failures": [],
            "residual_godot_processes": [],
            "process_quiescent": True,
        }

    monkeypatch.setattr(godot_runtime_launcher.mutation_audit, "_godot_processes", lambda: [])
    monkeypatch.setattr(godot_runtime_launcher.mutation_audit, "_run_monitored", fake_run)
    godot_runtime_launcher.run_godot(
        ["godot", "--version"], timeout_s=5, allowed_exit_codes=(0,)
    )
    assert "appdata" in observed
    assert observed["appdata"].is_dir()
    assert observed["appdata"].name == "godot_test_appdata"


def test_global_extinction_gate_runtime() -> None:
    if "func _is_building_post_extinction(" not in THERMAL:
        pytest.skip("runtime gate is exercised only after the structural contract exists")
    godot = _godot()
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
        allowed_exit_codes=(0, 1),
    )
    output = completed.stdout + completed.stderr
    assert completed.returncode == 0, output
    assert "P1R_V3_GLOBAL_EXTINCTION_GATE_PASS" in output
