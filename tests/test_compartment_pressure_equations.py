"""Compartment pressure equations (phase F2.2A): pure model contract and runtime tests.

The model only evaluates the local mass, energy and state equations of one
compartment for a candidate state and candidate opening fluxes. It solves
nothing, and nothing in the engine, the editor, the view or the scenarios loads
it.
"""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim" / "core" / "CompartmentPressureEquations.gd"
VALIDATOR = "res://tools/validate_compartment_pressure_equations.gd"
PASS_TOKEN = "COMPARTMENT PRESSURE EQUATIONS VALIDATION PASS"
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
    Path("sim/core/CompartmentPressureEquations.gd"),
    Path("sim/core/CompartmentPressureEquations.gd.uid"),
    Path("tools/validate_compartment_pressure_equations.gd"),
    Path("tools/validate_compartment_pressure_equations.gd.uid"),
    Path("scripts/check_product.py"),
    Path("tests/test_compartment_pressure_equations.py"),
    # F2.2B loads the equations as its authoritative evaluator. That is a pure
    # model calling a pure model, not engine integration.
    Path("sim/core/Phase3CoupledPressureSolver.gd"),
    Path("tools/validate_pressure_network_solver.gd"),
    Path("tests/test_pressure_network_solver.py"),
    Path("tests/test_phase3_f33v3h1_coupled_pressure_solver.py"),
}
SCANNED_FOLDERS = ("sim", "editor", "view", "tools", "scripts", "scenes", "ui", "scenarios", "tests", "assets", "i18n")
SCANNED_SUFFIXES = {".gd", ".tscn", ".tres", ".py", ".json", ".cfg", ".godot", ".csv", ".txt"}
# F2.2C will connect the solver; until then these owners must stay untouched.
NON_INTEGRATION_OWNERS = (
    "sim/core/SimulationEngine.gd",
    "sim/core/GasExchangeSystem.gd",
    "sim/core/OxygenExchangeSystem.gd",
    "sim/core/ThermalSystem.gd",
    "sim/core/Phase3ZoneMassSystem.gd",
    "sim/core/SimulationStateBuilder.gd",
    "sim/building/RoomModel.gd",
    "sim/BuildingModel.gd",
)


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
        "ThermalSystem", "Phase3", "rand", "seed",
    ):
        assert forbidden not in MODEL_CODE, forbidden


def test_model_is_not_a_solver():
    # No iteration, no convergence, no flow law: that is F2.2B.
    for forbidden in (
        "while ", "converge", "iterat", "damping", "jacobian", "newton", "tolerance_pa",
        "sqrt(", "discharge", "bernoulli", "neutral", "open_fraction", "thermal_gap",
    ):
        assert forbidden not in MODEL_CODE.lower(), forbidden
    main = _static_function("evaluate_compartment_residual")
    assert "for flux in fluxes:" in main  # only a sum over the given fluxes
    assert "mass_flow_kg_s" in main and "enthalpy_flow_kw" in main
    # The only loops are bounded passes over zones and inputs.
    assert main.count("for ") <= 3


def test_pressure_sign_is_never_clamped():
    for forbidden in ("maxf(0.0, gauge", "maxf(0.0, candidate", "absf(gauge", "clampf(gauge"):
        assert forbidden not in MODEL_CODE, forbidden
    thermo = _static_function("_thermodynamic_state")
    # The gauge pressure is the affine EOS, with no floor applied.
    assert "var gauge_pressure_pa: float = gas_constant * (" in thermo
    assert "(total_mass_kg - reference_mass_kg) * reference_temp_k" in thermo
    assert "+ total_energy_kj / AIR_CP_KJ_KG_K" in thermo
    assert "maxf(0.0" not in thermo.replace("maxf(0.0, upper_density", "").replace("maxf(0.0, lower_density", "")
    main = _static_function("evaluate_compartment_residual")
    assert 'errors.append("candidate gauge pressure implies a non-positive absolute pressure")' in main


def test_canonical_state_and_units():
    assert "const AIR_PRESSURE_REF_PA: float = 101325.0" in MODEL_CODE
    assert "const AIR_DENSITY_REF_KG_M3: float = 1.2" in MODEL_CODE
    assert "const AIR_CP_KJ_KG_K: float = 1.0" in MODEL_CODE
    assert "const GRAVITY_M_S2: float = 9.81" in MODEL_CODE
    main = _static_function("evaluate_compartment_residual")
    assert "var gas_constant: float = AIR_PRESSURE_REF_PA / (AIR_DENSITY_REF_KG_M3 * reference_temp_k)" in main
    thermo = _static_function("_thermodynamic_state")
    # Kelvin only: temperatures come from energy over mass, never from Celsius.
    assert "upper_temp_k += upper_energy_kj / (upper_mass_kg * AIR_CP_KJ_KG_K)" in thermo
    assert "lower_temp_k += lower_energy_kj / (lower_mass_kg * AIR_CP_KJ_KG_K)" in thermo
    assert "_c\"" not in MODEL_CODE and "temp_c" not in MODEL_CODE
    assert 'errors.append("candidate_state implies a zone temperature <= 0 K")' in thermo
    # Interface and zone volumes are derived, never inputs.
    assert "var interface_m: float = clampf(lower_volume_m3 / floor_area_m2, 0.0, height_m)" in thermo
    assert "declared_interface_height_m" not in _static_function("_thermodynamic_state")


def test_residuals_use_dt_and_the_documented_sign_convention():
    main = _static_function("evaluate_compartment_residual")
    assert "var mass_residual: float = (float(candidate[mass_key]) - float(previous[mass_key])) - dt * mass_in_kg_s" in main
    assert "var energy_residual: float = (float(candidate[energy_key]) - float(previous[energy_key])) - dt * enthalpy_in_kw" in main
    assert 'var mass_in_kg_s: float = float(source_terms["%s_mass_kg_s" % zone]) + float(flux_mass[zone])' in main
    assert 'var enthalpy_in_kw: float = float(source_terms["%s_enthalpy_kw" % zone]) + float(flux_enthalpy[zone])' in main
    assert "var pressure_residual_pa: float = candidate_gauge_pa - float(thermo[\"gauge_pressure_pa\"])" in main
    # kJ and kW never swap: the only energy accumulator is kJ.
    assert "energy_residual_kw" not in MODEL_CODE
    assert MODEL_CODE.count("energy_residual_kj") >= 2


def test_profile_is_hydrostatic_from_the_floor():
    profile = _static_function("_pressure_profile")
    assert "var interface_pressure_pa: float = gauge_floor_pa - lower_density * GRAVITY_M_S2 * interface_m" in profile
    assert "- upper_density * GRAVITY_M_S2 * (height_m - interface_m)" in profile
    assert '"z_m": floor_z_m,' in profile
    assert '"z_m": floor_z_m + interface_m,' in profile
    assert '"z_m": floor_z_m + height_m,' in profile
    assert '"zone_above": ZONE_LOWER' in profile and '"zone_above": ZONE_UPPER' in profile


def test_fluxes_are_order_independent_and_unique():
    fluxes = _static_function("_validated_fluxes")
    assert 'var key_text: String = "%s|%s|%s" % [opening_id, segment_id, zone]' in fluxes
    assert "if seen.has(key_text):" in fluxes
    assert 'return String(left["sort_key"]) < String(right["sort_key"]))' in fluxes


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
            if "CompartmentPressureEquations" in text or "compartment_pressure_equations" in text:
                offenders.append(str(relative))
    assert offenders == []
    project = (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")
    assert "CompartmentPressureEquations" not in project
    for owner in NON_INTEGRATION_OWNERS:
        text = (ROOT / owner).read_text(encoding="utf-8", errors="ignore")
        assert "CompartmentPressureEquations" not in text, owner
        assert "compartment_pressure" not in text.lower(), owner
    for folder in ("scenarios", "sim/validation/cases"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*.json"):
            text = path.read_text(encoding="utf-8", errors="ignore")
            assert "compartment_pressure" not in text.lower(), str(path)
            assert "pressure_network_solver_enabled" not in text, str(path)


def test_no_new_engine_flag_was_added():
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "pressure_network_solver_enabled" not in engine
    # The legacy phase 3 flags stay exactly as they are until F2.2C.
    assert "@export var phase3_thermodynamic_pressure_enabled: bool = true" in engine
    assert "@export var phase3_pressure_canonical_enabled: bool = false" in engine


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
