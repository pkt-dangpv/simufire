"""Actual isolated GDScript owner; no engine activation or experimental fit."""
import json
import os
from pathlib import Path

import pytest

from scripts import godot_monitored_launch
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim/fire/PrescribedPhaseBudgetController.gd"


def test_actual_atomic_phase_controller():
    godot = Path(os.environ.get("GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script",
                           ROOT / "tests/fixtures/g3_atomic_phase_controller.gd"],
                          timeout_s=120, allowed_exit_codes=(0,))
    payload = json.loads(next(line.split(" ", 1)[1] for line in completed.stdout.splitlines()
                              if line.startswith("G3_ATOMIC_PHASE_CONTROLLER {")))
    assert payload["failures"] == []
    assert payload["groups"] == [f"A{i:02}" for i in range(1, 21)]
    assert payload["checks"] == 361
    assert "G3_ATOMIC_PHASE_CONTROLLER_PASS" in completed.stdout


def test_controller_reuses_physics_owners_not_their_laws():
    source = MODEL.read_text(encoding="utf-8")
    assert "Release.propose(" in source and "Release.acknowledge(" in source
    assert "Budget.propose_phase_reference(" in source
    for forbidden in ["_oxygen_required", "_integral(", "oxidized * c", "8.0 / 3.0",
                      "solid_fuel_kg", "FileAccess", "@export", "await ", "SimulationEngine"]:
        if forbidden == "SimulationEngine":
            assert source.count(forbidden) == 1  # Scope comment only.
        else:
            assert forbidden not in source


def test_existing_model_and_provider_remain_frozen():
    import hashlib
    pins = {
        "PrescribedFuelReleaseModel.gd": "89a8c5ad8c663c9f417e23381c6cbf0d2c07bc5c56f5ad01ff7dc1ed6e0cd9fc",
    }
    for name, checksum in pins.items():
        raw = (ROOT / "sim/fire" / name).read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.sha256(raw).hexdigest() == checksum
    from tests.test_g3_sensible_phase_budget import test_old_budget_functions_remain_byte_frozen
    test_old_budget_functions_remain_byte_frozen()


def test_controller_is_not_loaded_by_product():
    assert "PrescribedPhaseBudgetController" not in (ROOT / "project.godot").read_text(encoding="utf-8")
    for directory in ["sim", "editor", "ui", "view", "scenes", "scenarios", "tools"]:
        for path in (ROOT / directory).rglob("*"):
            if path != MODEL and path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json"}:
                assert "PrescribedPhaseBudgetController" not in path.read_text(encoding="utf-8")


@pytest.mark.parametrize("name", [f"C{i:02}" for i in range(1, 19)])
def test_predeclared_mutation_has_one_real_source_anchor(name):
    from scripts.simulation.run_g3_atomic_phase_mutations import MUTATIONS, changed_source
    matches = [patch for key, patch in MUTATIONS.items() if key.startswith(name + "_")]
    assert len(matches) == 1
    source = MODEL.read_text(encoding="utf-8")
    assert changed_source(source, *matches[0]) != source


@pytest.mark.parametrize("failure", ["Parse Error", "SCRIPT ERROR", "missing_marker", "wrong_exit"])
def test_mutation_classifier_never_counts_infrastructure_errors_as_kills(failure):
    from scripts.simulation.run_g3_atomic_phase_mutations import PREFIX, classify
    stdout = PREFIX + " " + json.dumps({"failures": ["behavioral failure"]})
    stderr, exitcode = "", 1
    if failure == "missing_marker":
        stdout = ""
    elif failure == "wrong_exit":
        exitcode = -1
    else:
        stderr = failure
    with pytest.raises(RuntimeError):
        classify(stdout, stderr, exitcode, PREFIX)
