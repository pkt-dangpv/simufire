"""Actual GDScript prescribed provider, isolated from product."""

import json
import os
from pathlib import Path

import pytest

from scripts import godot_monitored_launch
from scripts.simulation import run_g3_prescribed_release_mutations as mutations
from scripts.simulation import validate_g3_mass_material_profile as profiles
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim/fire/PrescribedFuelReleaseModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_prescribed_fuel_release.gd"
PROFILE = ROOT / "tests/fixtures/g3_mass_material_profile_synthetic.json"


def test_actual_gdscript_provider_and_budget_joint_controls():
    godot = Path(os.environ.get("GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0, "Godot requires >=6 GiB"
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", FIXTURE],
                          timeout_s=120, allowed_exit_codes=(0,))
    line = next(line for line in completed.stdout.splitlines() if line.startswith("G3_PRESCRIBED_RELEASE {"))
    report = json.loads(line.split(" ", 1)[1])
    assert report["failures"] == [] and "G3_PRESCRIBED_RELEASE_PASS" in completed.stdout
    assert report["checks"] == 247 and report["groups"] == 83
    expected = profiles.prepare_prescribed_program(profiles.load_profile(PROFILE))
    assert report["program"] == expected["program"]


def test_provider_is_not_loaded_by_product_and_has_no_engine_or_io():
    source = MODEL.read_text(encoding="utf-8")
    for forbidden in ("FileAccess", "load(", "preload(", "SimulationEngine", "RoomModel", "FuelObjectModel"):
        assert forbidden not in source
    isolated = {MODEL, ROOT / "sim/fire/PrescribedPhaseBudgetController.gd"}
    for folder in ("sim", "editor", "ui", "view", "scenarios", "scenes", "tools"):
        for path in (ROOT / folder).rglob("*"):
            # Only the unintegrated atomic caller may compose this provider.
            if path not in isolated and path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json"}:
                assert "PrescribedFuelReleaseModel" not in path.read_text(encoding="utf-8")
    assert "PrescribedFuelReleaseModel" not in (ROOT / "project.godot").read_text(encoding="utf-8")


def test_adapter_preserves_eligibility_and_has_no_aliases_or_heat_inference():
    data = profiles.load_profile(PROFILE)
    output = profiles.prepare_prescribed_program(data)
    assert output["decision"] == "synthetic_contract_complete"
    assert not output["scientific_approval"] and not output["engine_integration"]
    before = output["program"]
    data["material"]["chemical_heat"]["value"] *= 2
    assert profiles.prepare_prescribed_program(data)["program"] == before
    output["program"]["samples"][1]["rate_kg_s"] = 999
    assert data["release"]["samples"][1]["rate_kg_s"] == 0.1
    data["initial_mass"]["unit"] = "MJ"
    assert profiles.prepare_prescribed_program(data)["program"] == {}


def test_mutation_anchors_are_unique_and_valid_changes_never_touch_source():
    raw = MODEL.read_bytes()
    assert len(mutations.MUTATIONS) == 11
    for anchor, replacement in mutations.MUTATIONS.values():
        assert mutations.changed_source(raw.decode("utf-8"), anchor, replacement) != raw.decode("utf-8")
    assert MODEL.read_bytes() == raw


@pytest.mark.parametrize("stdout,stderr,code", [
    ("Parse Error", "", 1), ("G3_PRESCRIBED_RELEASE {}", "SCRIPT ERROR", 1),
    ('G3_PRESCRIBED_RELEASE {"failures":[]}', "", 1),
    ('G3_PRESCRIBED_RELEASE {"failures":["x"]}', "", 0),
])
def test_syntax_runtime_or_inconsistent_exit_never_counts_as_mutant_kill(stdout, stderr, code):
    with pytest.raises(RuntimeError):
        mutations.classify(stdout, stderr, code)


def test_valid_assertion_failure_is_a_kill():
    assert mutations.classify('G3_PRESCRIBED_RELEASE {"failures":["domain"]}', "", 1)[0] == "killed"
