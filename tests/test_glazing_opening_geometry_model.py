"""Multilayer glazing opening geometry (phase 3B): pure model contract and runtime tests.

The model turns a phase 3A integrity snapshot plus explicit fallen regions per
leaf into the rectangles of the free path through every leaf. It produces
geometry only (no flow), and nothing in the engine, the editor, the view or the
scenarios loads it.
"""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim" / "core" / "GlazingOpeningGeometryModel.gd"
VALIDATOR = "res://tools/validate_glazing_opening_geometry_model.gd"
PASS_TOKEN = "GLAZING OPENING GEOMETRY MODEL VALIDATION PASS"
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
    Path("sim/core/GlazingOpeningGeometryModel.gd"),
    Path("sim/core/GlazingOpeningGeometryModel.gd.uid"),
    Path("tools/validate_glazing_opening_geometry_model.gd"),
    Path("tools/validate_glazing_opening_geometry_model.gd.uid"),
    Path("scripts/check_product.py"),
    Path("tests/test_glazing_opening_geometry_model.py"),
    # The phase 3A isolation test allow-lists the phase 3B validator by path.
    Path("tests/test_glazing_integrity_model.py"),
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
        "ThermalSystem", "GlassFailureSystem", "FireSpreadSystem", "IntegrityModel",
    ):
        assert forbidden not in MODEL_CODE, forbidden


def test_model_has_no_flow_thermal_or_random_physics():
    lowered = MODEL_CODE.lower()
    for forbidden in (
        "temperat", "heat", "flux", "radiat", "pressure", "bernoulli", "flow", "velocity",
        "direction", "mass", "smoke", "oxygen", "species", "sqrt(", "pow(", "exp(", "rand",
        "seed", "noise", "gravity", "discharge", "open_fraction", "thermal_gap", "time_s",
    ):
        assert forbidden not in lowered, forbidden


def test_free_path_is_an_intersection_not_a_fraction_formula():
    main = _static_function("compute_open_geometry")
    # A cell is free only if every leaf covers it.
    assert "if not cells.has(key):\n\t\t\t\t\tfree = false\n\t\t\t\t\tbreak" in main
    assert "if free:\n\t\t\t\tfree_cells[key] = contributors" in main
    # Fractions never build geometry: only the conservation check reads them.
    for forbidden in ("min(", "max(", "minf(", "maxf(", "mini(", "maxi(", "clamp", "lerp", "average", "mean"):
        assert forbidden not in MODEL_CODE, forbidden
    assert main.count('leaf["fallout_fraction"]') == 1
    assert 'var prescribed: float = float(leaf["fallout_fraction"])' in main
    assert re.search(r"prescribed\s*[*/]", MODEL_CODE) is None
    assert re.search(r"fraction\s*\*", MODEL_CODE) is None
    # The open area comes from the rectangles alone.
    assert 'open_area += float(rectangle["area_m2"])' in main
    assert 'rectangle["area_m2"] = float(rectangle["width_m"]) * float(rectangle["height_m"])' in main


def test_leaf_states_map_to_holes():
    covering = _static_function("_covering_regions")
    assert "if state != STATE_PARTIAL_FALLOUT:\n\t\treturn covering" in covering
    assert 'if rx <= x0 and x1 <= rx + float(region["width_m"])' in covering
    assert 'and rz <= z0 and z1 <= rz + float(region["height_m"])' in covering
    main = _static_function("compute_open_geometry")
    # OPEN covers every cell; INTACT and CRACKED none.
    assert "if covering.is_empty() and state != STATE_OPEN:\n\t\t\t\t\tcontinue" in main
    spatial = _static_function("_validated_spatial")
    assert "(state == STATE_INTACT or state == STATE_CRACKED or state == STATE_OPEN) and not Array(entry[\"regions\"]).is_empty()" in spatial
    assert "state == STATE_PARTIAL_FALLOUT and Array(entry[\"regions\"]).is_empty()" in spatial
    fraction = _static_function("_fraction_matches_state")
    assert "if state == STATE_INTACT or state == STATE_CRACKED:\n\t\treturn fraction == 0.0" in fraction


def test_geometry_is_exact_and_regions_are_never_clipped():
    # Exact grid from region edges: no raster, no snapping.
    for forbidden in ("snapped", "round(", "floor(", "ceil(", "resolution", "step_m", "cell_size"):
        assert forbidden not in MODEL_CODE, forbidden
    region = _static_function("_validated_region")
    assert "if x < 0.0 or z < 0.0 or x + w > width or z + h > height:" in region
    assert "if w <= 0.0 or h <= 0.0:" in region
    assert "if region_ids.has(region_id):" in region
    assert "if _is_blank_identifier(region_id):" in region
    main = _static_function("compute_open_geometry")
    assert "if union_area <= 0.0 or union_area >= panel_area:" in main
    assert "absf(geometric_fraction - prescribed) > FRACTION_TOLERANCE" in main


def test_tolerance_is_only_used_for_conservation():
    assert "const FRACTION_TOLERANCE: float = 1.0e-9" in MODEL_CODE
    assert MODEL_CODE.count("FRACTION_TOLERANCE") == 2
    assert "tolerance" not in _static_function("_validated_region").lower()
    assert "TOLERANCE" not in _static_function("_merge_cells")


def test_output_is_canonical():
    merge = _static_function("_merge_cells")
    assert 'if JSON.stringify(free_cells[next_key], "", true, true) != signature:' in merge
    assert 'var run_key: String = "%d|%d|%s" % [run["i0"], run["i1"], run["signature"]]' in merge
    assert '"contributors": _deep_copy(item["contributors"])' in merge
    before = _static_function("_rectangle_before")
    assert 'for key in ["local_z_m", "local_x_m", "width_m", "height_m"]:' in before
    main = _static_function("compute_open_geometry")
    assert 'rectangle["id"] = "%s%03d" % [RECTANGLE_ID_PREFIX, index]' in main
    assert 'rectangle["global_sill_z_m"] = sill + float(rectangle["local_z_m"])' in main
    assert 'const SOURCE: String = "glazing_fallout"' in MODEL_CODE
    assert 'const RECTANGLE_ID_PREFIX: String = "fallout_path_"' in MODEL_CODE
    leaves = _static_function("_validated_leaves")
    assert 'return int(left["index"]) < int(right["index"]))' in leaves
    assert "covering.sort()" in _static_function("_covering_regions")


def test_identifiers_are_matched_and_returned_exactly():
    # Emptiness and identity are different: strip_edges() only answers "is it blank?".
    assert MODEL_CODE.count("strip_edges()") == 2
    blank = _static_function("_is_blank_identifier")
    assert "return text.strip_edges().is_empty()" in blank
    exact = _static_function("_exact_text")
    assert "return String(value)" in exact
    assert "strip_edges" not in exact
    # No trimmed view is ever used to match an identity.
    assert "_text(" not in MODEL_CODE.replace("_exact_text(", "")
    panel = _static_function("_validated_panel")
    assert 'if _is_blank_identifier(_exact_text(panel["id"])):' in panel
    spatial = _static_function("_validated_spatial")
    assert 'if not spatial.has("panel_id") or _exact_text(spatial["panel_id"]) != _exact_text(panel["id"]):' in spatial
    assert 'var leaf_id: String = _exact_text(entry["id"])' in spatial
    leaves = _static_function("_validated_leaves")
    assert 'var leaf_id: String = _exact_text(leaf["id"])' in leaves
    # Only the phase 3A duplicate rule keeps looking at the trimmed text.
    assert 'var duplicate_key: String = leaf_id.strip_edges()' in leaves
    assert "ids.has(duplicate_key)" in leaves
    region = _static_function("_validated_region")
    assert 'var region_id: String = _exact_text(region["id"])' in region
    assert "region_ids.has(region_id)" in region
    # Identity reaches the output untouched.
    main = _static_function("compute_open_geometry")
    assert '"panel_id": _exact_text(panel["id"]),' in main
    assert '"leaf_id": String(leaf["id"]),' in main
    assert '"leaf_id": leaf_id,' in main
    for forbidden in ("to_lower", "to_upper", "nocasecmp", "casecmp", "strip_escapes", "replace(\" \"", "validate_node_name"):
        assert forbidden not in MODEL_CODE, forbidden


def test_model_is_not_integrated_anywhere():
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
            if "GlazingOpeningGeometryModel" in text or "glazing_opening_geometry" in text:
                offenders.append(str(relative))
    assert offenders == []
    project = (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")
    assert "GlazingOpeningGeometryModel" not in project
    assert "glazing_opening_geometry" not in project
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "glazing" not in engine.lower()


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
