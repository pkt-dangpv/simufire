"""Actual isolated GDScript budget and its non-integration boundary."""

import json
import os
from pathlib import Path

import pytest

from scripts import godot_monitored_launch
from scripts.simulation import run_g3_fuel_mass_budget_mutations as mutations
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim/fire/FuelMassBudgetModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_fuel_mass_budget.gd"


def test_analytical_controls_on_actual_gdscript():
    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"
    ))
    if not godot.exists():
        pytest.skip("Godot executable not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0, "Godot needs >= 6 GiB available"
    completed = run_godot(
        [godot, "--headless", "--path", ROOT, "--script", FIXTURE],
        timeout_s=120, allowed_exit_codes=(0,),
    )
    assert "G3_FUEL_MASS_BUDGET_PASS" in completed.stdout
    line = next(line for line in completed.stdout.splitlines()
                if line.startswith("G3_FUEL_MASS_BUDGET {"))
    report = json.loads(line.split(" ", 1)[1])
    assert report["failures"] == []
    assert report["groups"] == 39
    assert report["checks"] == 271


def test_kernel_is_not_integrated_or_loaded_by_product():
    assert "FuelMassBudgetModel" not in (ROOT / "project.godot").read_text(encoding="utf-8")
    isolated = {MODEL, ROOT / "sim/fire/PrescribedPhaseBudgetController.gd",
                ROOT / "sim/fire/PrescribedSensiblePhaseController.gd"}
    for folder in ("sim", "editor", "ui", "view", "scenes", "scenarios", "tools"):
        for path in (ROOT / folder).rglob("*"):
            # The two isolated owners are the only consumers, not product wiring.
            # Each owner contract checks that no product resource loads it.
            if path in isolated or not path.is_file() or path.suffix not in {
                ".gd", ".tscn", ".tres", ".json"
            }:
                continue
            assert "FuelMassBudgetModel" not in path.read_text(
                encoding="utf-8", errors="replace"
            ), path.relative_to(ROOT)


def test_kernel_has_no_engine_objects_io_or_legacy_energy_conversion():
    source = MODEL.read_text(encoding="utf-8")
    code = "\n".join(line for line in source.splitlines()
                     if not line.lstrip().startswith("#"))
    for forbidden in (
        "RoomModel", "FuelObjectModel", "SimulationEngine", "FileAccess",
        "ResourceLoader", "@export", "rand",
        "fuel_energy_MJ", "remaining_fuel_MJ", "g3_unburned", "retained_unburned",
    ):
        assert forbidden not in code, forbidden
    assert code.count('preload(') == 1
    assert 'preload("res://sim/fire/SensibleEnthalpyModel.gd")' in code
    # No dynamic loading or runtime dependency; this is the pure Cp owner only.
    assert 'load(' not in code.replace('preload(', '')
    assert "static func propose(" in code


def test_mutation_anchors_are_unique_and_never_edit_working_source():
    before = MODEL.read_bytes()
    source = before.decode("utf-8")
    for old, new in mutations.MUTATIONS.values():
        changed = mutations.changed_source(source, old, new)
        assert changed != source
    assert MODEL.read_bytes() == before


@pytest.mark.parametrize("source", ["", "anchor anchor"])
def test_ambiguous_or_missing_mutation_anchor_is_rejected(source):
    with pytest.raises(ValueError):
        mutations.changed_source(source, "anchor", "new")


@pytest.mark.parametrize("stdout,stderr,code", [
    ("", "Parse Error", 1),
    ('G3_FUEL_MASS_BUDGET {"failures":["x"]}', "SCRIPT ERROR", 1),
    ('G3_FUEL_MASS_BUDGET {"failures":[]}', "", 1),
    ('G3_FUEL_MASS_BUDGET {"failures":["x"]}', "", 0),
])
def test_syntax_runtime_or_inconsistent_exit_is_not_a_killed_mutant(stdout, stderr, code):
    with pytest.raises(RuntimeError):
        mutations.classify(stdout, stderr, code)


def test_only_asserted_valid_fixture_failure_counts_as_a_kill():
    output = 'G3_FUEL_MASS_BUDGET {"failures":["missing solid debit"]}'
    assert mutations.classify(output, "", 1)[0] == "killed"
    control = 'G3_FUEL_MASS_BUDGET {"failures":[]}\nG3_FUEL_MASS_BUDGET_PASS'
    assert mutations.classify(control, "", 0)[0] == "pass"
