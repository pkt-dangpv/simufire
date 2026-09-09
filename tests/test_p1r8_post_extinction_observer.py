from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
OBSERVER = ROOT / "tests/fixtures/p1r8_post_extinction_observer.gd"
FIXTURE = ROOT / "tests/fixtures/p1r8_post_extinction_observer_contract.gd"
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot() -> Path | None:
    return next(
        (path for path in GODOT_CANDIDATES if path is not None and path.exists()),
        None,
    )


def test_observer_contract_is_present_and_fail_closed() -> None:
    assert OBSERVER.is_file(), "post-extinction observer is not implemented"
    assert FIXTURE.is_file(), "post-extinction runtime contract is not implemented"
    source = OBSERVER.read_text(encoding="utf-8")
    for contract in (
        "INSUFFICIENT_POST_EXTINCTION_WINDOW",
        "MISSING_ROOM",
        "NONFINITE_VALUE",
        "NON_MONOTONIC_SAMPLE",
        "NON_MONOTONIC_COUNTER",
        "reignition_events",
        "all_room_smoke_stock_kg",
        "smoke_in_transit_kg",
        "smoke_accounting_residual_kg",
    ):
        assert contract in source
    assert "room_state.get(field, 0.0)" not in source


def test_observer_synthetic_runtime_contract() -> None:
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
    assert "P1R8_POST_EXTINCTION_OBSERVER_PASS" in output
