from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/p1r8_o2_owner_contract.gd"
DISPOSITION = ROOT / "docs/validation/P1R8_O2_OWNER_001_DISPOSITION.md"
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
OXYGEN = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot() -> Path | None:
    return next(
        (path for path in GODOT_CANDIDATES if path is not None and path.exists()),
        None,
    )


def test_legacy_selection_and_debit_split_is_documented_as_a_limitation() -> None:
    disposition = DISPOSITION.read_text(encoding="utf-8")
    assert "O2-OWNER-001" in disposition
    assert "VERIFIED_MODEL_LIMITATION" in disposition
    assert "open interior connection" in disposition
    assert "lower-zone oxygen" in disposition
    assert "bulk oxygen" in disposition
    assert "_estimate_room_interior_open_factor(building, room) <= 0.01" in OXYGEN
    assert 'mode = "plume_lower"' in COMBUSTION
    assert "@export var fire_o2_canonical_enabled: bool = false" in ENGINE
    assert "@export var fire_o2_upper_throttle_enabled: bool = false" in ENGINE


def test_legacy_two_zone_owner_limitation_is_reproduced(tmp_path: Path) -> None:
    godot = _godot()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    result_path = tmp_path / "o2_owner_contract.json"
    completed = run_godot(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            str(FIXTURE),
            "--",
            f"--p1r8-o2-owner-output={result_path}",
        ],
        timeout_s=180,
        allowed_exit_codes=(0, 1),
    )
    assert result_path.is_file(), completed.stdout + completed.stderr
    result = json.loads(result_path.read_text(encoding="utf-8-sig"))
    branches = {row["branch"]: row for row in result["branches"]}
    assert set(branches) == {"open_interior", "sealed"}
    assert branches["sealed"]["selected_owner"] == "lower"
    assert branches["sealed"]["debited_owner"] == "lower"
    assert branches["sealed"]["owner_match"] is True
    assert branches["open_interior"]["selected_owner"] == "lower"
    assert branches["open_interior"]["debited_owner"] == "bulk"
    assert branches["open_interior"]["owner_match"] is False
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert result["passed"] is True
    assert "P1R8_O2_OWNER_LIMITATION_CONFIRMED" in completed.stdout + completed.stderr
