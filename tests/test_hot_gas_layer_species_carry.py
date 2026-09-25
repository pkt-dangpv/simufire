"""Ruta normal (red de presion OFF): la parcela de gas caliente lleva las
especies de SU capa.

`ThermalSystem._transfer_hot_gas_contaminants()` mueve gas de la capa alta de
la sala caliente a la capa alta de la fria. CO y HCN salian de la capa alta del
origen; el CO2 se dimensionaba sobre el total y la parte no alta se restaba de
la capa BAJA del origen sin gas de esa capa que la llevase (6,713 kg en 300 s de
`preset_simple_house`). Detalle en
docs/validation/RUTA_NORMAL_CO2_ACARREO_CAPA_2026-09-25.md.

Estaticas: fijan la regla en la funcion. Dinamica: el validador Godot, que
falla con el codigo anterior (H1 y H2) y pasa con el arreglo.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot

ROOT = Path(__file__).resolve().parents[1]
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
VALIDATOR_PATH = ROOT / "tools/validate_hot_gas_layer_species_carry.gd"
VALIDATOR = "res://tools/validate_hot_gas_layer_species_carry.gd"
PASS_TOKEN = "HOT GAS LAYER SPECIES CARRY VALIDATION PASS"
CHECK_PRODUCT = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def test_co2_leaves_the_upper_layer_like_co_and_hcn():
    carry = _function(THERMAL, "_transfer_hot_gas_contaminants")
    # Las tres especies por capa se dimensionan sobre su capa alta disponible.
    assert "var co_upper_available_kg: float = clampf(source.co_upper_kg, 0.0, source.co_kg)" in carry
    assert "var co2_upper_available_kg: float = clampf(source.co2_upper_kg, 0.0, source.co2_kg)" in carry
    assert "var hcn_upper_available_kg: float = clampf(source.hcn_upper_kg, 0.0, source.hcn_kg)" in carry
    assert ("var co2_moved_kg: float = minf(source.co2_kg, "
            "co2_upper_available_kg * upper_fraction_moved * carry)") in carry
    # Ni el total de la sala ni un reparto proporcional: eso restaba la capa baja.
    assert "source.co2_kg * upper_fraction_moved" not in carry
    assert "src_upper_frac" not in carry
    assert "var co2_source_upper_kg: float = co2_moved_kg" in carry
    # El limitador de concentracion de F0 sigue igual.
    assert "co2_moved_kg = minf(co2_moved_kg, co2_headroom_kg)" in carry


def test_the_parcel_is_upper_layer_gas():
    step = _function(THERMAL, "step")
    assert "hot_room.upper_gas_kg = maxf(0.0, hot_room.upper_gas_kg - gas_moved_kg)" in step
    assert "cold_room.upper_gas_kg = maxf(0.0, cold_room.upper_gas_kg + gas_moved_kg)" in step


def test_the_validator_is_registered():
    source = VALIDATOR_PATH.read_text(encoding="utf-8")
    for case in ("_h1_function_keeps_the_source_lower_layer", "_h1c_upper_only_control",
                 "_h2_product_route"):
        assert f"\t{case}()" in source, case
    assert 'const SCENARIO := "res://scenarios/preset_simple_house.json"' in source
    assert VALIDATOR in CHECK_PRODUCT
    assert PASS_TOKEN in CHECK_PRODUCT


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def test_validator_passes():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR],
        timeout_s=600, allowed_exit_codes=(0,),
    )
    output = (completed.stdout or "") + (completed.stderr or "")
    assert PASS_TOKEN in output
    assert "SCRIPT ERROR" not in output
    assert "Parse Error" not in output
