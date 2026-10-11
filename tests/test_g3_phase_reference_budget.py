"""Actual phase ledger, shared algebra, and unintegrated boundary."""

import json
import os
from pathlib import Path

import pytest

from scripts import godot_monitored_launch
from scripts.simulation import run_g3_fuel_mass_budget_mutations as mutations
from tests.godot_runtime_launcher import run_godot

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim/fire/FuelMassBudgetModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_phase_reference_budget.gd"


def test_actual_phase_reference_analytical_controls():
    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"
    ))
    if not godot.exists():
        pytest.skip("Godot executable not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot(
        [godot, "--headless", "--path", ROOT, "--script", FIXTURE],
        timeout_s=120, allowed_exit_codes=(0,),
    )
    line = next(line for line in completed.stdout.splitlines()
                if line.startswith("G3_PHASE_REFERENCE_BUDGET {"))
    payload = json.loads(line.split(" ", 1)[1])
    assert payload["failures"] == []
    assert payload["checks"] == 502
    assert "G3_PHASE_REFERENCE_BUDGET_PASS" in completed.stdout


def test_phase_api_keeps_a_single_mass_chemistry_owner():
    source = MODEL.read_text(encoding="utf-8")
    assert source.count("(8.0 / 3.0) * c + 8.0 * h - o") == 1
    assert source.count("oxidized * c * (11.0 / 3.0)") == 1
    assert source.count("oxidized * h * 9.0") == 1
    phase = source.split("static func propose_phase_reference(", 1)[1]
    phase = phase.split("static func _oxygen_required(", 1)[0]
    assert "propose(" not in phase
    assert "solid_fuel_kg" not in phase
    assert '_mass_element_balance(' in phase
    assert '_accepted_masses(' in phase
    assert '_oxidation_quantities(' in phase


@pytest.mark.parametrize("name", mutations.PHASE_MUTATIONS)
def test_phase_mutants_have_unique_anchors_and_preserve_working_source(name):
    original = MODEL.read_bytes()
    assert mutations.changed_source(original.decode(), *mutations.PHASE_MUTATIONS[name])
    assert MODEL.read_bytes() == original


@pytest.mark.parametrize("stdout,stderr,code", [
    ("", "Parse Error", 1),
    ('G3_PHASE_REFERENCE_BUDGET {"failures":["x"]}', "SCRIPT ERROR", 1),
    ('G3_PHASE_REFERENCE_BUDGET {"failures":[]}', "", 1),
    ('G3_PHASE_REFERENCE_BUDGET {"failures":["x"]}', "", 0),
])
def test_invalid_phase_mutant_run_is_not_a_kill(stdout, stderr, code):
    with pytest.raises(RuntimeError):
        mutations.classify(stdout, stderr, code, "G3_PHASE_REFERENCE_BUDGET")


def test_valid_phase_failure_counts_as_kill():
    output = 'G3_PHASE_REFERENCE_BUDGET {"failures":["phase energy"]}'
    assert mutations.classify(output, "", 1, "G3_PHASE_REFERENCE_BUDGET")[0] == "killed"
