"""F2.2D2: contratos de integracion de deformacion prescrita en la red."""
from __future__ import annotations

import re
import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot

ROOT = Path(__file__).resolve().parent.parent
ENGINE_PATH = ROOT / "sim/core/SimulationEngine.gd"
TRANSPORT_PATH = ROOT / "sim/core/PressureNetworkTransportSystem.gd"
OPENING_PATH = ROOT / "sim/building/OpeningModel.gd"
ADAPTER_PATH = ROOT / "sim/core/ClosedDoorDeformationNetworkAdapter.gd"
MODEL_PATH = ROOT / "sim/core/ClosedDoorDeformationModel.gd"
VALIDATOR = ROOT / "tools/validate_closed_door_deformation_network.gd"

ENGINE = ENGINE_PATH.read_text(encoding="utf-8")
TRANSPORT = TRANSPORT_PATH.read_text(encoding="utf-8")
OPENING = OPENING_PATH.read_text(encoding="utf-8")
ADAPTER = ADAPTER_PATH.read_text(encoding="utf-8")
MODEL = MODEL_PATH.read_text(encoding="utf-8")

FLAG = "closed_door_deformation_enabled"
PASS_TOKEN = "CLOSED DOOR DEFORMATION NETWORK VALIDATION PASS"
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _code_only(source: str) -> str:
    return "\n".join(
        line.split("  #", 1)[0]
        for line in source.splitlines()
        if not line.lstrip().startswith("#")
    )


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def test_flag_is_boolean_off_by_default_and_requires_the_network():
    assert re.findall(rf"^@export var {FLAG}: bool = (\w+)$", ENGINE, re.M) == ["false"]
    assert f"if {FLAG} and not pressure_network_solver_enabled:" in ENGINE
    assert "closed_door_deformation_requires_pressure_network" in ENGINE
    # F2.2D4B2B: el motor enciende el solver en UN solo sitio, y no en secreto.
    # Hasta D4B2A ningun camino lo encendia y la regla era que el texto no
    # apareciese. Ahora existe una ruta -la autorizacion experimental
    # explicita- y lo que se vigila es que sea la unica y que viva dentro de
    # ella, bajo el mapa de interruptores que devuelve el contrato.
    assert ENGINE.count("pressure_network_solver_enabled = true") == 1
    _activation = ENGINE.split(
        "func _apply_experimental_physics_authorization() -> void:", 1
    )[1].split("\nfunc ", 1)[0]
    assert "pressure_network_solver_enabled = true" in _activation
    assert "ExperimentalAuthorizationScript.REQUIRED_DEPENDENCY" in _activation


def test_d2_is_independent_of_d1_but_is_gated_by_the_network():
    assert (
        f"pressure_network_transport_system.{FLAG} = \\\n"
        f"\t\t\t{FLAG} and pressure_network_solver_enabled"
    ) in ENGINE
    wiring = [line for line in ENGINE.splitlines() if FLAG in line]
    assert all("closed_door_leakage_enabled" not in line for line in wiring)


def test_engine_passes_the_authoritative_simulation_time():
    call = re.search(
        r"pressure_network_transport_system\.step\(\s*"
        r"building, dt, \{\}, sim_time_s\s*\)",
        ENGINE,
    )
    assert call, "D2 must evaluate prescribed histories at engine sim_time_s"


def test_runtime_tracks_are_separate_from_thermal_gap_and_operational_opening():
    assert "var deformation_tracks: Array = []" in OPENING
    opening_code = _code_only(OPENING)
    assert "deformation_temperature" not in opening_code
    code = _code_only(ADAPTER)
    assert "thermal_gap_fraction" not in code
    assert "effective_open_fraction" not in code
    assert "set_open_fraction" not in code
    assert "temperature" not in code.lower()


def test_adapter_reuses_the_pure_model_and_the_d1_flow_contract():
    assert 'preload("res://sim/core/ClosedDoorDeformationModel.gd")' in ADAPTER
    assert "DeformationModel.evaluate_tracks(" in ADAPTER
    assert "DeformationModel.combine_with_cold(" in ADAPTER
    assert '"flow_model": "ela_crack"' in ADAPTER
    # No segunda ley de flujo: ni Bernoulli ni potencia viven en el adaptador.
    code = _code_only(ADAPTER)
    assert "sqrt(" not in code
    assert "pow(" not in code
    assert "compute_segment_flow_from_dp" not in code
    assert (
        '"flow_exponent": LeakageModel.PROVISIONAL_FLOW_EXPONENT_CANDIDATE'
        in ADAPTER
    )
    assert (
        '"zero_pressure_regularization_pa": LeakageAdapter.DP_REGULARIZATION_PA'
        in ADAPTER
    )


def test_zero_deformation_returns_the_cold_element_without_repacking_it():
    assert "if additional_m2 <= 0.0:" in ADAPTER
    zero_block = ADAPTER.split("if additional_m2 <= 0.0:", 1)[1].splitlines()[1]
    assert "return cold_element" in zero_block


def test_local_heights_are_translated_in_one_place_only():
    assert 'segment["z_m"] = floor_z_m + float(segment["z_m"])' in ADAPTER
    assert ADAPTER.count('floor_z_m + float(segment["z_m"])') == 1


def test_invalid_prescriptions_fail_the_snapshot_closed():
    assert "DeformationAdapterScript.validate_opening(" in TRANSPORT
    assert 'errors.append("opening %d: %s"' in TRANSPORT
    assert "continue" in TRANSPORT.split("DeformationAdapterScript.validate_opening(", 1)[1]


def test_open_door_and_closed_door_are_mutually_exclusive():
    snapshot = TRANSPORT[TRANSPORT.index("func build_snapshot"):]
    assert snapshot.index("if opening.is_closed()") < snapshot.index('"opening_id": "op_%d"')
    assert "float(opening.open_fraction)" in snapshot
    assert "effective_open_fraction()" not in _code_only(snapshot)


def test_no_distributed_scenario_enables_d2():
    hits: list[str] = []
    for pattern in ("*.tres", "*.tscn", "*.json", "*.cfg"):
        for path in ROOT.rglob(pattern):
            if any(part in {".git", "runs", "sim_out", "reports"} for part in path.parts):
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if f"{FLAG} = true" in text or f'"{FLAG}": true' in text:
                hits.append(str(path.relative_to(ROOT)))
    assert hits == []


def test_no_automatic_temperature_deformation_law_was_added():
    code = _code_only(ADAPTER + "\n" + TRANSPORT)
    for token in ("temp_upper", "temp_lower", "150.0", "350.0", "0.04"):
        assert token not in code
    assert "points" in MODEL and "area_at(" in MODEL


def test_validator_is_registered_in_product_checks():
    check_product = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")
    assert "validate_closed_door_deformation_network.gd" in check_product
    assert PASS_TOKEN in check_product


def test_validator_passes():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", str(VALIDATOR)],
        timeout_s=900,
        allowed_exit_codes=(0,),
    )
    output = (completed.stdout or "") + (completed.stderr or "")
    assert PASS_TOKEN in output
    assert "ERROR:" not in output
    assert "SCRIPT ERROR" not in output
    assert "Parse Error" not in output
