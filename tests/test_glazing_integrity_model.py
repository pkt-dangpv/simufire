"""Prescribed glazing integrity (phase 3A): pure-model and consumer contracts."""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim" / "core" / "GlazingIntegrityModel.gd"
VALIDATOR = "res://tools/validate_glazing_integrity_model.gd"
PASS_TOKEN = "GLAZING INTEGRITY MODEL VALIDATION PASS"
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

ALLOWED_REFERENCES = {
    Path("sim/core/GlazingIntegrityModel.gd"),
    Path("sim/core/GlazingIntegrityModel.gd.uid"),
    Path("tools/validate_glazing_integrity_model.gd"),
    Path("tools/validate_glazing_integrity_model.gd.uid"),
    Path("scripts/check_product.py"),
    Path("tests/test_glazing_integrity_model.py"),
    # Phase 3B validator: builds its snapshots with this model, still outside the engine.
    Path("tools/validate_glazing_opening_geometry_model.gd"),
    Path("tests/test_glazing_opening_geometry_model.py"),
    # F2.2D3: exact declared integration path. The adapter consumes 3A and 3B;
    # the validator and static suite protect that path.
    Path("sim/core/GlazingFalloutNetworkAdapter.gd"),
    Path("tools/validate_glazing_fallout_network.gd"),
    Path("tests/test_glazing_fallout_network.py"),
    # F2.2D4A: el contrato persistente nombra este modelo en su
    # documentacion y delega en el adaptador de D3 toda la validacion.
    Path("sim/building/PrescribedOpeningPhysicsSchema.gd"),
    # F2.2D4B1 (2026-09-22): el catalogo trazable NOMBRA este modelo en la
    # procedencia de sus perfiles -de donde sale cada numero y con que
    # limites- y su validador comprueba ese gate. Ninguno de los dos ejecuta
    # el modelo ni crea una segunda ruta de fisica.
    Path("sim/building/OpeningPhysicsProfileCatalog.gd"),
}
SCANNED_FOLDERS = ("sim", "editor", "view", "tools", "scripts", "scenes", "ui", "scenarios", "tests", "assets", "i18n")
SCANNED_SUFFIXES = {".gd", ".tscn", ".tres", ".py", ".json", ".cfg", ".godot", ".csv", ".txt"}


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
        "@export", "get_tree", "Node", "preload(", "load(", "FileAccess", "ResourceLoader",
        "OS.", "Time.", "Engine.", "BuildingModel", "RoomModel", "OpeningModel",
        "ScenarioSerializer", "SimulationEngine", "GasExchangeSystem", "OxygenExchangeSystem",
        "ThermalSystem", "GlassFailureSystem", "FireSpreadSystem",
    ):
        assert forbidden not in MODEL_CODE, forbidden


def test_model_has_no_thermal_random_or_flow_physics():
    lowered = MODEL_CODE.lower()
    for forbidden in (
        "temperat", "temp_", "_c\"", "heat", "flux", "radiat", "pressure", "bernoulli",
        "flow", "sqrt(", "pow(", "exp(", "rand", "seed", "noise", "area", "opening",
        "ventilat", "gravity", "break1", "open_fraction", "thermal_gap_fraction",
    ):
        assert forbidden not in lowered, forbidden


def test_state_contract_is_strict():
    assert 'const STATES: Array[String] = [STATE_INTACT, STATE_CRACKED, STATE_PARTIAL_FALLOUT, STATE_OPEN]' in MODEL_CODE
    fraction = _static_function("_fraction_matches_state")
    assert "if state == STATE_INTACT or state == STATE_CRACKED:\n\t\treturn fraction == 0.0" in fraction
    assert "return fraction > 0.0 and fraction < 1.0" in fraction
    assert "return fraction == 1.0" in fraction
    transition = _static_function("_transition_allowed")
    assert "return rank == 0 or rank == 1" in transition
    assert "return STATES[rank] == STATE_PARTIAL_FALLOUT" in transition
    assert "return rank == previous_rank + 1" in transition
    events = _static_function("_validate_events")
    assert "if time_s <= previous_time:" in events
    assert "if fraction < previous_fraction:" in events
    assert "fraction > 1.0" in events and "fraction < 0.0" in events


def test_evaluation_is_a_step_function_without_interpolation():
    leaf = _static_function("_evaluate_leaf")
    assert 'if float(event["time_s"]) > time_s:\n\t\t\tbreak' in leaf
    assert 'fraction = float(event["fallout_fraction"])' in leaf
    for forbidden in ("lerp", "weight", "inverse_lerp", "/ ("):
        assert forbidden not in leaf, forbidden


def test_panel_metadata_is_validated_but_inert():
    validate = _static_function("_validate_panel_into")
    for guard in (
        "width <= 0.0", "height <= 0.0", "thickness <= 0.0", "edge < 0.0",
        "2.0 * edge >= minf(width, height)", 'typeof(panel["leaf_count"]) == TYPE_INT',
        "leaves.size() != int(panel[\"leaf_count\"])", "spacing < 0.0",
        "GLASS_TYPES.has(glass_type)", "OTHER_DESCRIPTION_KEY", 'frame_material',
    ):
        assert guard in validate, guard
    # Type, thickness, frame and edge never reach the evaluated state.
    leaf = _static_function("_evaluate_leaf")
    for word in ("glass_type", "thickness", "frame", "edge", "spacing"):
        assert word not in leaf, word
    summary = _static_function("_damage_summary")
    assert "fallout_fraction" not in summary
    assert '"diagnostic_only": true' in summary


def test_model_has_only_its_declared_consumers():
    offenders = []
    for folder in SCANNED_FOLDERS:
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in SCANNED_SUFFIXES and not path.name.endswith(".gd.uid"):
                continue
            relative = path.relative_to(ROOT)
            if relative in ALLOWED_REFERENCES:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if "GlazingIntegrityModel" in text or "glazing_integrity" in text:
                offenders.append(str(relative))
    assert offenders == []
    project = (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")
    assert "GlazingIntegrityModel" not in project
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "GlazingIntegrityModel" not in engine


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
