"""Prescribed closed-door deformation: pure model contract and runtime tests.

Phase 2 of docs/PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md: localized additional
ELA prescribed over time and combined with the cold leakage segments. F2.2D2
integrates it through one adapter; the pure model remains stateless.
"""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim" / "core" / "ClosedDoorDeformationModel.gd"
VALIDATOR = "res://tools/validate_closed_door_deformation_model.gd"
PASS_TOKEN = "CLOSED DOOR DEFORMATION MODEL VALIDATION PASS"
MODEL_SOURCE = MODEL.read_text(encoding="utf-8")
# Code without comment lines: the documentation may name what the code avoids.
MODEL_CODE = "\n".join(
    line for line in MODEL_SOURCE.splitlines() if not line.lstrip().startswith("#")
)

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)

# The only files allowed to mention the deformation model while it is not integrated.
ALLOWED_REFERENCES = {
    Path("sim/core/ClosedDoorDeformationModel.gd"),
    Path("sim/core/ClosedDoorDeformationNetworkAdapter.gd"),
    Path("sim/core/PressureNetworkTransportSystem.gd"),
    Path("sim/core/SimulationEngine.gd"),
    Path("tools/validate_closed_door_deformation_model.gd"),
    Path("tools/validate_closed_door_deformation_network.gd"),
    Path("scripts/check_product.py"),
    Path("scripts/simulation/audit_default_off_flags.py"),
    # F2.2D4A (2026-09-22): el contrato persistente valida las pistas con
    # ESTE modelo en vez de copiar sus reglas, y su validador nombra el
    # interruptor de D2 para probar que guardar y cargar no lo enciende.
    # Ninguno de los dos ejecuta la deformacion: solo la guarda y la lee.
    Path("sim/building/PrescribedOpeningPhysicsSchema.gd"),
    Path("tools/validate_prescribed_physics_persistence.gd"),
    # F2.2D4B1 (2026-09-22): el catalogo trazable NOMBRA este modelo en la
    # procedencia de sus perfiles -de donde sale cada numero y con que
    # limites- y su validador comprueba ese gate. Ninguno de los dos ejecuta
    # el modelo ni crea una segunda ruta de fisica.
    Path("sim/building/OpeningPhysicsProfileCatalog.gd"),
    Path("tools/validate_opening_physics_profiles.gd"),
}


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _static_function(name: str) -> str:
    return MODEL_CODE.split(f"static func {name}(", 1)[1].split("\nstatic func ", 1)[0]


def test_model_is_pure_and_not_globally_registered():
    assert MODEL_SOURCE.startswith("extends RefCounted\n")
    assert "class_name" not in MODEL_CODE
    assert re.search(r"^var ", MODEL_CODE, re.MULTILINE) is None
    assert re.search(r"^func ", MODEL_CODE, re.MULTILINE) is None
    for forbidden in (
        "@export",
        "get_tree",
        "Node",
        "BuildingModel",
        "RoomModel",
        "OpeningModel",
        "ScenarioSerializer",
        "SimulationEngine",
        "GasExchangeSystem",
        "FileAccess",
        "OS.",
        "randf",
        "randi",
        "Time.",
    ):
        assert forbidden not in MODEL_CODE, forbidden


def test_model_never_touches_door_state_or_temperature():
    for forbidden in (
        "open_fraction",
        "thermal_gap_fraction",
        "temperature",
        "temp_",
        "_c\"",
        "door_deform",
    ):
        assert forbidden not in MODEL_CODE, forbidden
    # Only these keys of a track are read; everything else is ignored.
    read_keys = set(re.findall(r'track\["([a-z_]+)"\]', MODEL_CODE))
    assert read_keys == {"id", "location", "z_m", "points", "metadata"}, read_keys
    assert 'track.get(' not in MODEL_CODE


def test_model_never_computes_flows_or_converts_geometry():
    for forbidden in (
        "preload(",
        "load(",
        "compute_flows",
        "crack_volume",
        "ClosedDoorLeakageModel",
        "sqrt(",
        "pow(",
        "_mm",
        "percent",
        "GRAVITY",
    ):
        assert forbidden not in MODEL_CODE, forbidden
    # The evaluated area comes only from the prescribed points.
    evaluate = _static_function("evaluate_tracks")
    assert '"area_m2": area_at(track["points"], time_s),' in evaluate


def test_documented_contracts_are_explicit():
    assert "const BEFORE_FIRST_POINT_VALUE_M2: float = 0.0" in MODEL_SOURCE
    for location in ("bottom", "top", "hinge_side", "latch_side"):
        assert f'"{location}"' in MODEL_CODE
    combine = _static_function("combine_with_cold")
    assert 'entry["area_m2"] = float(entry["area_m2"]) + area' in combine
    assert "elif area > 0.0:" in combine
    assert "additional_ela_m2" in MODEL_SOURCE
    assert "Prieler" in MODEL_SOURCE


def test_side_ids_require_exactly_two_ascii_digits():
    # is_valid_int() accepts signs such as "-1" or "+1": it must not decide ids.
    assert "is_valid_int" not in MODEL_CODE
    assert "is_valid_float" not in MODEL_CODE
    matcher = _static_function("_id_matches_location")
    assert "_is_two_ascii_digits(track_id.substr(prefix.length()))" in matcher
    digits = _static_function("_is_two_ascii_digits")
    assert "if suffix.length() != 2:" in digits
    assert "if code < 48 or code > 57:" in digits


def test_band_center_validates_its_preconditions():
    assert "side_band_center_z_m" not in MODEL_CODE
    center = _static_function("side_band_center")
    assert "-> Dictionary:" in MODEL_CODE.split("static func side_band_center(", 1)[1].split("\n", 1)[0]
    for guard in (
        "if not _is_finite(sill_z_m):",
        "if not _is_finite(door_height_m) or door_height_m <= 0.0:",
        "if count < 1:",
        "elif band < 0 or band >= count:",
        '"z_m": NAN',
    ):
        assert guard in center, guard
    # The division only happens after every precondition passed.
    assert center.index("if not errors.is_empty():") < center.index("/ float(count)")


def test_model_has_one_explicit_integration_path():
    offenders = []
    for folder in ("sim", "editor", "view", "tools", "scripts", "scenes", "ui"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix not in {".gd", ".tscn", ".tres", ".py", ".json", ".cfg"}:
                continue
            relative = path.relative_to(ROOT)
            if relative in ALLOWED_REFERENCES:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if "ClosedDoorDeformationModel" in text or "closed_door_deformation" in text:
                offenders.append(str(relative))
    assert offenders == []
    adapter = (ROOT / "sim/core/ClosedDoorDeformationNetworkAdapter.gd").read_text(
        encoding="utf-8"
    )
    transport = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(
        encoding="utf-8"
    )
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert 'preload("res://sim/core/ClosedDoorDeformationModel.gd")' in adapter
    assert 'preload("res://sim/core/ClosedDoorDeformationNetworkAdapter.gd")' in transport
    assert "ClosedDoorDeformationModel.gd" not in engine


def _run_validator(dump_path: Path | None = None):
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    command = [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR]
    if dump_path is not None:
        command += ["--", f"--dump={dump_path}"]
    return run_godot(command, timeout_s=300, allowed_exit_codes=(0,))


def test_validator_passes_and_dump_is_byte_identical(tmp_path):
    first = tmp_path / "dump_first.json"
    second = tmp_path / "dump_second.json"
    for completed in (_run_validator(first), _run_validator(second)):
        output = (completed.stdout or "") + (completed.stderr or "")
        assert PASS_TOKEN in output
        assert "SCRIPT ERROR" not in output
        assert "Parse Error" not in output
    assert first.read_bytes() == second.read_bytes()
    assert len(first.read_bytes()) > 1000
