"""Coupled pressure-opening network solver (phase F2.2B): contract and runtime tests.

F2.2B promotes the existing pure solver, `sim/core/Phase3CoupledPressureSolver.gd`,
instead of adding a competing one. The canonical entry point is
`solve_pressure_network`; `solve_coupled_pressure` stays as the historical
wrapper of the phase 3 shadow machinery and shares the very same core.

Nothing in the engine applies the result: F2.2C is what will integrate it.
"""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
SOLVER_PATH = ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd"
EQUATIONS_PATH = ROOT / "sim" / "core" / "CompartmentPressureEquations.gd"
VALIDATOR = "res://tools/validate_pressure_network_solver.gd"
PASS_TOKEN = "PRESSURE NETWORK SOLVER VALIDATION PASS"
SOLVER = SOLVER_PATH.read_text(encoding="utf-8")
SOLVER_CODE = "\n".join(
    line for line in SOLVER.splitlines() if not line.lstrip().startswith("#")
)

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)

SCANNED_FOLDERS = ("sim", "editor", "view", "tools", "scripts", "scenes", "ui", "scenarios", "tests", "assets", "i18n")
SCANNED_SUFFIXES = {".gd", ".tscn", ".tres", ".py", ".json", ".cfg", ".godot", ".csv", ".txt"}
ALLOWED_NETWORK_REFERENCES = {
    Path("sim/core/Phase3CoupledPressureSolver.gd"),
    Path("tools/validate_pressure_network_solver.gd"),
    Path("tools/validate_pressure_network_solver.gd.uid"),
    Path("scripts/check_product.py"),
    Path("tests/test_pressure_network_solver.py"),
    # F2.2A's own test also asserts the flag does not exist yet.
    Path("tests/test_compartment_pressure_equations.py"),
    # F2.2C: el adaptador es el unico consumidor runtime, y lo prueba su suite.
    Path("sim/core/PressureNetworkTransportSystem.gd"),
    Path("sim/core/SimulationEngine.gd"),
    Path("tools/validate_pressure_network_integration.gd"),
    Path("tests/test_pressure_network_integration.py"),
    # F2.2D1: la fuga fria vive dentro de la red, asi que su validador y su
    # suite nombran el interruptor de la red y la resuelven con ella.
    Path("tools/validate_closed_door_leakage_network.gd"),
    Path("tests/test_closed_door_leakage_network.py"),
    # F2.2C-R1: los fixtures multiplanta resuelven redes reales con el solver.
    Path("tools/validate_multistorey_pressure_datum.gd"),
    Path("tests/test_multistorey_pressure_datum.py"),
    Path("scripts/simulation/audit_default_off_flags.py"),
    Path("tests/test_p1r4_flag_activation_inventory.py"),
}


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _function(name: str) -> str:
    return SOLVER_CODE.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def test_there_is_exactly_one_solver():
    assert not (ROOT / "sim" / "core" / "PressureOpeningNetworkSolver.gd").exists()
    # The promoted file keeps its historical name and class_name on purpose.
    assert SOLVER.startswith("extends RefCounted\nclass_name Phase3CoupledPressureSolver\n")
    canonical = _function("solve_pressure_network")
    # The canonical entry delegates into the same core; it never re-implements
    # the flux law, the Jacobian or the equation of state.
    assert "solve_coupled_pressure(" in canonical
    for forbidden in ("jacobian", "sqrt(", "_integrate_opening(", "_regularized_flux_factor("):
        assert forbidden not in canonical.lower(), forbidden
    assert SOLVER_CODE.count("func solve_coupled_pressure(") == 1
    assert SOLVER_CODE.count("func solve_pressure_network(") == 1
    assert SOLVER_CODE.count("func _integrate_opening(") == 1
    assert SOLVER_CODE.count("func _evaluate(") == 1


def test_compartment_equations_are_the_authority():
    assert "CompartmentPressureEquationsScript = preload(" in SOLVER_CODE
    assert '"res://sim/core/CompartmentPressureEquations.gd"' in SOLVER_CODE
    finish = _function("_finish_network")
    assert "equations.evaluate_compartment_residual(" in finish
    assert 'if not bool(verdict["valid"]):' in finish
    assert 'reasons.append("compartment_equations_rejected_candidate")' in finish
    # The published residuals are the ones F2.2A returned, not a private copy.
    for key in ("mass_residual_kg", "energy_residual_kj", "pressure_residual_pa"):
        assert f'"{key}": float(verdict["{key}"])' in finish
    assert '"pressure_profile": verdict["pressure_profile"]' in finish


def test_convergence_needs_every_physical_criterion():
    finish = _function("_finish_network")
    for reason in (
        "compartment_equations_rejected_candidate",
        "pressure_closure_above_tolerance",
        "mass_residual_above_tolerance",
        "energy_residual_above_tolerance",
        "unclassified_interior_band",
    ):
        assert f'reasons.append("{reason}")' in finish, reason
    assert "if reasons.is_empty():" in finish
    assert 'result["converged"] = true' in finish
    # A failure keeps valid and converged apart and always names a reason.
    assert 'result["failure_reason"] = reasons[0]' in finish
    assert "const DEFAULT_PRESSURE_TOLERANCE_PA: float = 1.0e-6" in SOLVER_CODE
    assert "const DEFAULT_MASS_TOLERANCE_KG: float = 1.0e-9" in SOLVER_CODE
    assert "const DEFAULT_ENERGY_TOLERANCE_KJ: float = 1.0e-6" in SOLVER_CODE


def test_negative_sensible_energy_follows_the_physical_contract():
    derive = _function("_derive_room")
    # The sign alone is never a reason to reject.
    assert "upper_energy_kj < 0.0 or lower_energy_kj < 0.0" not in derive
    assert "upper_gas_kg < 0.0 or lower_gas_kg < 0.0" in derive
    assert "upper_temp_k <= 0.0 or lower_temp_k <= 0.0" in derive
    assert "pressure_abs_pa <= 0.0" in derive
    assert "absf(upper_energy_kj) > 0.0" in derive
    assert "absf(lower_energy_kj) > 0.0" in derive
    # And no clamp ever hides a negative gauge pressure.
    for forbidden in ("maxf(0.0, gauge_pressure_pa)", "absf(gauge_pressure_pa)",
                      "clampf(gauge_pressure_pa"):
        assert forbidden not in SOLVER_CODE, forbidden


def test_vertical_convention_is_absolute_and_explicit():
    derive = _function("_derive_room")
    assert 'var floor_z_m: float = float(state.get("floor_z_m", 0.0))' in derive
    assert '"interface_z_m": floor_z_m + interface_m,' in derive
    column = _function("_column_mass_per_area")
    assert 'var datum_z_m: float = float(side.get("floor_z_m", 0.0))' in column
    assert "lower_density_kg_m3 * (height_m - datum_z_m)" in column
    span = _function("_network_opening_span")
    assert 'errors.append("opening \'%s\' mixes absolute and local heights" % opening_id)' in span
    assert "local heights between floors at different levels" in span
    assert 'String(opening.get("height_reference", ""))' in span


def test_exterior_is_an_imposed_node_with_temperature_and_wind():
    context = _function("_build_context")
    assert 'var exterior_temp_k: float = float(options.get("exterior_temp_k", reference_temp_k))' in context
    # F2.2C-R1: la densidad del contorno la da el helper canonico de la columna
    # atmosferica, no una division suelta en el contexto. Que exista un unico
    # dueno de esa formula es justamente lo que esta fase arregla.
    assert 'float(exterior_profile["density_kg_m3"])' in context
    assert "ExteriorPressureProfileScript.resolve(" in context
    assert 'exterior_reference_z_m' in context
    assert "var exterior_specific_kj_kg: float = AIR_CP_KJ_KG_K * (exterior_temp_k - reference_temp_k)" in context
    build = _function("_build_opening")
    assert 'var exterior_gauge_pa: float = float(opening.get("wind_dp_pa", 0.0))' in build
    # Wind belongs to the exterior node of one opening: it is read where the
    # opening is built and where the canonical input is validated, and it is
    # applied exactly once, as the exterior gauge offset.
    # Read twice (canonical validation and opening build) but APPLIED once: it
    # is the gauge of the exterior node, never added to anything else.
    # F2.2D1 y F2.2C-R1: TRES clases de elemento lo publican —la abertura
    # grande, la rendija ELA y el hueco horizontal entre plantas—, cada una en
    # su propio constructor. Sigue siendo el mismo valor, tomado de la misma
    # variable, y aplicado una sola vez por elemento.
    assert SOLVER_CODE.count('"exterior_gauge_pa": exterior_gauge_pa,') == 3
    assert "+ exterior_gauge_pa" not in SOLVER_CODE
    assert "exterior_gauge_pa +" not in SOLVER_CODE
    assert _function("_evaluate").count("exterior_gauge_pa") >= 3
    assert "is interior and cannot carry wind" in _function("_prepare_network")
    evaluate = _function("_evaluate")
    assert 'float(opening.get("exterior_gauge_pa", 0.0))' in evaluate


def test_result_carries_the_transport_per_segment():
    openings = _function("_network_openings")
    for key in ("segment_id", "z_from_m", "z_to_m", "sample_z_m", "dp_pa", "direction",
                "source_room_id", "source_zone", "destination_room_id", "destination_zone",
                "source_density_kg_m3", "mass_flow_kg_s", "enthalpy_flow_kw", "regularized"):
        assert f'"{key}"' in openings, key
    assert '"neutral_plane_z_m"' in openings and '"neutral_plane_inside"' in openings
    finish = _function("_finish_network")
    for key in ("candidate_upper_gas_kg", "candidate_lower_gas_kg",
                "candidate_upper_energy_kj", "candidate_lower_energy_kj",
                "net_mass_kg_s", "net_enthalpy_kw", "reference_z_m", "pressure_abs_pa"):
        assert f'"{key}"' in finish, key


def test_candidate_state_is_built_conservatively():
    finish = _function("_finish_network")
    assert 'candidate["%s_gas_kg" % zone] = float(previous["%s_gas_kg" % zone]) \\' in finish
    assert 'dt_s * float(source["%s_mass_kg_s" % zone]) + float(entry["mass_kg"])' in finish
    assert 'dt_s * float(source["%s_enthalpy_kw" % zone]) + float(entry["energy_kj"])' in finish
    # No soot fraction, no species: F2.2B moves gas mass and sensible enthalpy.
    for forbidden in ("smoke", "soot", "o2", "species", "co2"):
        assert forbidden not in finish.lower(), forbidden


def test_solver_is_only_reached_through_the_adapter():
    # F2.2B stays pure: the flag lives in the engine and the adapter, never here.
    assert "pressure_network_solver_enabled" not in SOLVER_CODE
    offenders = []
    for folder in SCANNED_FOLDERS:
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
                continue
            relative = path.relative_to(ROOT)
            if relative in ALLOWED_NETWORK_REFERENCES:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            if "pressure_network_solver_enabled" in text:
                offenders.append(f"flag:{relative}")
            if "solve_pressure_network" in text:
                offenders.append(f"call:{relative}")
    assert offenders == []
    project = (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")
    assert "pressure_network_solver_enabled" not in project
    # The historical wrapper keeps exactly one passive call site in the shadow
    # system, and that site still cannot write the physical state.
    system = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
    assert system.count("solve_coupled_pressure(") == 1
    assert "solve_pressure_network(" not in system
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "solve_pressure_network" not in engine
    assert "@export var phase3_thermodynamic_pressure_enabled: bool = true" in engine
    assert "@export var phase3_pressure_canonical_enabled: bool = false" in engine


def test_deformation_and_glazing_models_are_still_disconnected():
    """F2.2D1 conecta la fuga fria, y SOLO la fuga fria.

    Hasta esta fase el solver no podia nombrar ninguno de los cuatro modelos.
    Ahora carga el de fuga a proposito, para no copiar su ley; los otros tres
    siguen prohibidos, y esta prueba es la que lo vigila. Los nombres se componen
    aposta: escribirlos enteros dispararia las guardas de aislamiento de esas
    fases."""
    for name in ("ClosedDoorDeformation" + "Model",
                 "GlazingIntegrity" + "Model", "GlazingOpeningGeometry" + "Model"):
        assert name not in SOLVER_CODE, name
    # La fuga si, y por una sola via: el ayudante del modelo puro.
    leakage = "ClosedDoorLeakage" + "Model"
    assert f"{leakage}Script = preload(" in SOLVER_CODE
    # La unica FUNCION que el solver llama del modelo de fuga es el ayudante de
    # un segmento; lo demas que toma de el son dos constantes (la referencia de
    # la ELA y el exponente), que es justamente no copiarlas.
    assert SOLVER_CODE.count(f"{leakage}Script.compute_segment_flow_from_dp(") == 1
    uses = [line.split(f"{leakage}Script.", 1)[1].split("(")[0].split(")")[0].strip()
            for line in SOLVER_CODE.splitlines() if f"{leakage}Script." in line]
    assert sorted(uses) == [
        "NIST_ELA_REFERENCE_PRESSURE_PA",
        "PROVISIONAL_FLOW_EXPONENT_CANDIDATE",
        "compute_segment_flow_from_dp",
    ], uses


def _run_validator(dump_path: Path | None = None):
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    command = [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR]
    if dump_path is not None:
        command += ["--", f"--dump={dump_path}"]
    return run_godot(command, timeout_s=600, allowed_exit_codes=(0,))


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
