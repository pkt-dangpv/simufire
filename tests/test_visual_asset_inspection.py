"""The artefact inspector records the live pipeline without rewriting assets."""
import hashlib
import json
import os
import tempfile
from pathlib import Path

from scripts import godot_monitored_launch, run_scenario

ROOT = Path(__file__).resolve().parents[1]


def _monitored(arguments, expected_error=None):
    godot = run_scenario._find_godot()
    assert godot is not None
    with tempfile.TemporaryDirectory(prefix="simufire-art-inspection-") as temp:
        environment = os.environ.copy()
        environment.update({"APPDATA": temp, "TEMP": temp, "TMP": temp,
                            "SIMUFIRE_GODOT_MIN_AVAILABLE_GIB": "6"})
        result = godot_monitored_launch.run(
            [godot, "--headless", "--path", ROOT, *arguments],
            timeout_s=90, environment=environment)
    assert result.launched and not result.preexisting and not result.faults, result
    assert not result.timed_out
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "SCRIPT ERROR" not in output and "Parse Error" not in output, output
    error_lines = [line.strip() for line in output.splitlines() if "ERROR:" in line]
    assert error_lines == ([] if expected_error is None else [expected_error]), output
    return output


def _asset_hashes():
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (ROOT / "assets/fp").rglob("*")
            if path.is_file() and path.suffix in {".tscn", ".glb"}}


def test_inspector_is_read_only_and_observes_real_transform_rules():
    before = _asset_hashes()
    output = _monitored(["--script", "res://tests/fixtures/visual_asset_inspection.gd"])
    rows = [line.removeprefix("VISUAL_INSPECTION_TEST_RESULT ")
            for line in output.splitlines() if line.startswith("VISUAL_INSPECTION_TEST_RESULT ")]
    assert len(rows) == 1, output
    payload = json.loads(rows[0])
    assert payload["checks"] == 41 and payload["errors"] == [], payload
    assert _asset_hashes() == before


def test_whole_catalog_can_be_inspected_without_rewriting_assets():
    before = _asset_hashes()
    output = _monitored(["--script", "res://tools/inspect_visual_assets.gd"])
    rows = [json.loads(line.removeprefix("VISUAL_ASSET_REPORT "))
            for line in output.splitlines() if line.startswith("VISUAL_ASSET_REPORT ")]
    assert len(rows) >= 30, output
    assert len({row["archetype"] for row in rows}) == len(rows)
    for row in rows:
        assert row["errors"] == [], row
        assert len(row["authored_bounds_m"]["size"]) == 3
        assert all(size > 0 for size in row["achieved_size_m"]), row
        assert row["runtime_instances"], row
    assert _asset_hashes() == before


def test_art_workbench_starts_without_fire_engine_or_asset_writes():
    before = _asset_hashes()
    output = _monitored(["res://tools/preview_visual_asset.tscn", "--quit-after", "3"])
    assert "VISUAL_ASSET_WORKBENCH_READY" in output, output
    source = (ROOT / "tools/preview_visual_asset.gd").read_text(encoding="utf-8")
    assert "SimulationEngine" not in source and "BuildingModel" not in source
    assert _asset_hashes() == before


def test_rejected_modular_asset_is_not_drawn_or_counted_as_success():
    before = _asset_hashes()
    output = _monitored(
        ["--script", "res://tests/fixtures/visual_asset_inspection.gd", "--", "--invalid-tiled-control"],
        expected_error="ERROR: FurnitureAssetLoader: modo de transformacion desconocido: invalid_metadata_type")
    rows = [line.removeprefix("VISUAL_REJECTION_TEST_RESULT ") for line in output.splitlines()
            if line.startswith("VISUAL_REJECTION_TEST_RESULT ")]
    assert len(rows) == 1, output
    payload = json.loads(rows[0])
    assert payload["checks"] == 3 and payload["errors"] == [], payload
    assert _asset_hashes() == before
