"""Independent analytical oracles and real GDScript property fixture."""

from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "G3_SENSIBLE_ENTHALPY"
ORACLES = {
    "constant_below": -50.0,
    "constant_reference": 0.0,
    "constant_above": 100.0,
    "linear_below": -46.875,
    "linear_above": 53.125,
    "piecewise_partial": 168.75,
    "piecewise_end": 225.0,
}


def test_oracles_predeclared_from_analytic_antiderivatives():
    # Closed-form polynomials, not a copy of the production segment integrator.
    def affine_primitive(delta):
        delta = Decimal(delta)
        return 2 * delta + Decimal("0.005") * delta * delta

    assert Decimal("2") * -25 == Decimal(str(ORACLES["constant_below"]))
    assert Decimal("2") * 0 == Decimal(str(ORACLES["constant_reference"]))
    assert Decimal("2") * 50 == Decimal(str(ORACLES["constant_above"]))
    assert affine_primitive(-25) == Decimal(str(ORACLES["linear_below"]))
    assert affine_primitive(25) == Decimal(str(ORACLES["linear_above"]))
    # First ramp primitive x + .02*x^2; second 3*y - .01*y^2.
    first = Decimal(50) + Decimal(".02") * 50**2
    assert first + 3 * 25 - Decimal(".01") * 25**2 == Decimal("168.75")
    assert first + 3 * 50 - Decimal(".01") * 50**2 == Decimal("225")


def test_real_gdscript_s01_s20():
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot

    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable unavailable")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot(
        [godot, "--headless", "--path", ROOT, "--script",
         ROOT / "tests/fixtures/g3_sensible_enthalpy.gd"],
        timeout_s=120, allowed_exit_codes=(0,),
    )
    lines = [line for line in completed.stdout.splitlines()
             if line.startswith(PREFIX + " {")]
    assert lines, completed.stdout + completed.stderr
    payload = json.loads(lines[-1].split(" ", 1)[1])
    assert payload["failures"] == []
    assert payload["groups"] == [f"S{i:02}" for i in range(1, 21)]
    assert payload["checks"] == 342
    assert PREFIX + "_PASS" in completed.stdout
    assert payload["observations"] == pytest.approx(ORACLES, abs=1e-9, rel=1e-12)


def test_property_helper_has_no_runtime_owner_or_activation():
    path = ROOT / "sim/fire/SensibleEnthalpyModel.gd"
    source = path.read_text(encoding="utf-8")
    assert source.startswith("extends RefCounted\n")
    assert not re.search(r"^var\s", source, re.M)
    for forbidden in ["@export", "preload(", "FileAccess", "SimulationEngine",
                      "fuel_energy_MJ"]:
        assert forbidden not in source
    # Only the false report field is permitted, never a simulation switch.
    assert set(re.findall(r"\b[a-z_]+_enabled\b", source)) == {"integration_enabled"}
    assert source.count("integral += area") == 1
    references = []
    for folder in [ROOT / "sim", ROOT / "editor", ROOT / "ui"]:
        for candidate in folder.rglob("*.gd"):
            if candidate != path and "SensibleEnthalpyModel" in candidate.read_text(encoding="utf-8"):
                references.append(str(candidate))
    # Authorized next phase: only the existing, isolated mass owner may consume Cp.
    assert references == [str(ROOT / "sim/fire/FuelMassBudgetModel.gd")]


@pytest.mark.parametrize("name, expected", [
    ("PrescribedFuelReleaseModel", "db58278f2fff141d31148301095d41234f3732a66fa4140f74abfbaff483897d"),
    ("PrescribedPhaseBudgetController", "41e6e36768eb386f5b9c6f9e9cb5b1e002227526cfef5d013926f8a595e4e6c6"),
])
def test_reference_provider_and_controller_remain_frozen(name, expected):
    raw = (ROOT / f"sim/fire/{name}.gd").read_bytes().replace(b"\r\n", b"\n")
    assert hashlib.sha256(raw).hexdigest() == expected


def test_extended_budget_keeps_old_functions_frozen():
    from tests.test_g3_sensible_phase_budget import test_old_budget_functions_remain_byte_frozen
    test_old_budget_functions_remain_byte_frozen()


def test_predeclared_mutation_anchors():
    from scripts.simulation.run_g3_sensible_enthalpy_mutations import prepared_variants

    source = (ROOT / "sim/fire/SensibleEnthalpyModel.gd").read_text(encoding="utf-8")
    variants = prepared_variants(source)
    assert len(variants) == 19
    assert all(mutant != source for mutant in variants.values())


@pytest.mark.parametrize("stdout, stderr, code", [
    ("", "", 1), (PREFIX + ' {"failures":["wrong"]}', "Parse Error", 1),
    (PREFIX + ' {"failures":["wrong"]}', "SCRIPT ERROR", 1),
    (PREFIX + ' {"failures":["wrong"]}', "", -1),
])
def test_infrastructure_errors_are_not_killed_mutants(stdout, stderr, code):
    from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify

    with pytest.raises(RuntimeError):
        classify(stdout, stderr, code, PREFIX)
