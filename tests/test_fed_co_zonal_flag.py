"""G3: CO concentration at the breathing zone is experimental and OFF by default."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
PRODUCT = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")
VALIDATOR = "res://tools/diagnose_fed_zone_selector.gd"


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def test_flag_is_default_off_and_reaches_thermal_system():
    assert "@export var fed_co_zonal_enabled: bool = false" in ENGINE
    assert '"fed_co_zonal_enabled": fed_co_zonal_enabled' in ENGINE
    assert "var fed_co_zonal_enabled: bool = false" in THERMAL
    assert 'fed_co_zonal_enabled = bool(settings.get("fed_co_zonal_enabled", fed_co_zonal_enabled))' in THERMAL


def test_both_fed_paths_use_the_same_experimental_lower_concentration():
    selector = "compute_co_lower_ppm_mass(room) if fed_co_zonal_enabled else compute_co_ppm(room)"
    assert selector in _function(THERMAL, "compute_fed_delta_for_height")
    assert selector in _function(THERMAL, "step_fed")
    lower = _function(THERMAL, "compute_co_lower_ppm_mass")
    assert "co_lower_kg * 29.0e6" in lower
    assert "* strat" not in lower
    assert "if room.upper_gas_kg < 0.1:" in lower


def test_product_guardrail_runs_imposed_concentration_validator():
    assert VALIDATOR in PRODUCT
    assert "G3 FED CO ZONAL VALIDATION PASS" in PRODUCT


def test_imposed_concentrations_in_godot():
    candidates = (
        Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
        Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
        Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
    )
    godot = next((path for path in candidates if path is not None and path.exists()), None)
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR],
        timeout_s=120,
        allowed_exit_codes=(0,),
    )
    output = (completed.stdout or "") + (completed.stderr or "")
    assert "G3 FED CO ZONAL VALIDATION PASS" in output
    assert "SCRIPT ERROR" not in output
    assert "Parse Error" not in output
