"""Authoritative pressure network integration (phase F2.2C): contract tests.

The adapter `sim/core/PressureNetworkTransportSystem.gd` runs inside the real
simulation step, behind the single flag `pressure_network_solver_enabled`, which
is off by default. With the flag off the engine walks the historical path
untouched; with it on there is one owner of pressure and one owner of the
transport through openings.
"""

from __future__ import annotations

import os
from pathlib import Path
import re

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
ADAPTER_PATH = ROOT / "sim" / "core" / "PressureNetworkTransportSystem.gd"
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
OXYGEN = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
ADAPTER = ADAPTER_PATH.read_text(encoding="utf-8")
ADAPTER_CODE = "\n".join(
    line for line in ADAPTER.splitlines() if not line.lstrip().startswith("#")
)
VALIDATOR = "res://tools/validate_pressure_network_integration.gd"
PASS_TOKEN = "PRESSURE NETWORK INTEGRATION VALIDATION PASS"

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)

FLAG = "pressure_network_solver_enabled"
GATE = "authoritative_transport_enabled"


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def test_single_flag_is_declared_off_by_default():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    assert ENGINE.count(f"@export var {FLAG}") == 1
    # No auxiliary flags for mass, energy, oxygen, smoke or species.
    for forbidden in ("pressure_network_mass", "pressure_network_species",
                      "pressure_network_o2", "pressure_network_energy"):
        assert forbidden not in ENGINE, forbidden
    auditor = (ROOT / "scripts/simulation/audit_default_off_flags.py").read_text(encoding="utf-8")
    assert f'"{FLAG}"' in auditor
    # F2.2D1, R3, D2 y D3 anaden cuatro capacidades vivas:
    # 77 -> 78 -> 79 -> 80 -> 81.
    assert "EXPECTED_DECLARATION_COUNT = 81" in auditor


def test_no_distributed_scenario_turns_the_flag_on():
    offenders = []
    for folder in ("scenarios", "sim/validation/cases", "sim/templates", "editor"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in {".json", ".gd", ".tscn", ".tres"}:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            # F2.2D4B2A: en un `.gd` se mira el CODIGO, no la documentacion. El
            # controlador que configura la fisica experimental nombra los
            # interruptores en su cabecera justamente para dejar escrito que no
            # los toca, y castigar esa frase empujaria a no escribirla.
            if path.suffix == ".gd":
                text = "\n".join(
                    line for line in text.splitlines() if not line.lstrip().startswith("#")
                )
            if FLAG in text:
                offenders.append(str(path.relative_to(ROOT)))
    assert offenders == []


def test_the_engine_runs_the_network_before_any_historical_transport():
    step = _function(ENGINE, "_step_gas_exchange")
    assert f"if {FLAG}:" in step
    assert "_step_pressure_network_transport(dt)" in step
    # The network runs before the historical venting call.
    assert step.index("_step_pressure_network_transport") < step.index("step_pressure_venting")
    assert f"gas_exchange_system.{GATE} = {FLAG}" in ENGINE
    assert f"oxygen_exchange_system.{GATE} = {FLAG}" in ENGINE
    assert f"thermal_system.{GATE} = {FLAG}" in ENGINE
    assert f'"{GATE}": {FLAG},' in ENGINE


def test_failure_is_explicit_and_never_falls_back():
    body = _function(ENGINE, "_step_pressure_network_transport")
    assert 'pressure_network_failure = String(result["failure_reason"])' in body
    assert "push_error(" in body
    # No historical re-run, no silent retry.
    for forbidden in ("step_pressure_venting", "step_thermodynamic_pressure", "fallback"):
        assert forbidden not in body, forbidden


def test_every_historical_owner_is_gated():
    # pressure
    assert f"if {GATE}:\n\t\treturn" in _function(GAS, "step_thermodynamic_pressure")
    assert f"if {GATE}:\n\t\treturn result" in _function(GAS, "step_pressure_venting")
    assert f'if {GATE}:\n\t\treturn {{"ppv_unsupported": _ppv_would_act(building)}}' in GAS
    assert f"if phase3a_pressure_ode_enabled and not {GATE}:" in THERMAL
    assert f'if not bool(context.get("{GATE}", false)):' in COMBUSTION
    # opening transport
    assert f"if {GATE}:\n\t\t\tcontinue" in _function(GAS, "step_smoke")
    assert f"if {GATE}:\n\t\t\tcontinue" in _function(OXYGEN, "step")
    assert f"if {GATE}:\n\t\treturn 0.0" in _function(GAS, "_compute_postfire_cleanup_factor")
    assert f"if {GATE}:\n\t\treturn" in _function(THERMAL, "_apply_outside_assisted_background_heat_exchange")
    assert f"if {GATE}:\n\t\treturn" in _function(THERMAL, "_apply_interior_background_heat_exchange")
    # the gate itself defaults to false everywhere
    for source in (GAS, OXYGEN, THERMAL):
        assert f"var {GATE}: bool = false" in source


def test_the_adapter_is_not_a_second_solver():
    for forbidden in ("sqrt(", "bernoulli", "jacobian", "newton", "while ",
                      "open_fraction_smooth", "maxf(0.0, gauge"):
        assert forbidden not in ADAPTER_CODE.lower(), forbidden
    assert "solve_pressure_network(" in ADAPTER_CODE
    assert ADAPTER_CODE.count("solve_pressure_network(") == 1
    for operation in ("build_snapshot", "build_solver_input", "solve",
                      "build_transport_transaction", "validate_transaction",
                      "commit_transaction"):
        assert f"func {operation}(" in ADAPTER_CODE, operation


def test_the_step_validates_before_it_commits():
    step = _function(ADAPTER_CODE, "step")
    assert "var verdict: Dictionary = validate_transaction(snapshot, transaction)" in step
    assert 'if not bool(verdict["valid"]):' in step
    # The rejection returns before commit_transaction is ever reached.
    assert step.index('if not bool(verdict["valid"]):') < step.index("commit_transaction(")
    assert 'result["failure_reason"] = "transaction_rejected"' in step


def test_the_transaction_is_atomic_and_reads_only_the_snapshot():
    build = _function(ADAPTER_CODE, "build_transport_transaction")
    commit = _function(ADAPTER_CODE, "commit_transaction")
    # Nothing is written while transfers are still being computed.
    assert "building" not in build
    # The final state of every room is computed before the first write.
    assert commit.index("final_states[room_id] = final_state") < commit.index("room.upper_gas_kg =")
    assert 'return {"applied": false, "failure_reason": "impossible_final_state"' in commit
    assert "var room = building.get_room(" in commit


def test_transported_state_covers_mass_energy_oxygen_smoke_and_species():
    assert 'const ZONAL_SPECIES: Array[String] = ["co", "co2", "hcn"]' in ADAPTER_CODE
    assert 'const GLOBAL_SPECIES: Array[String] = ["smoke", "hcl", "acrolein", "formaldehyde"]' in ADAPTER_CODE
    bundle = _function(ADAPTER_CODE, "_bundle_for_source")
    assert 'bundle["o2_kg"]' in bundle
    # Zonal species travel from the real source zone; global-only magnitudes use
    # the documented well-mixed assumption.
    assert 'float(room["%s_%s_kg" % [species, zone_key]]) * zone_fraction' in bundle
    assert "var room_fraction: float = mass_kg / room_mass_kg" in bundle
    commit = _function(ADAPTER_CODE, "commit_transaction")
    assert "room.o2_upper = _fraction(" in commit
    assert "room.o2 = _fraction(" in commit
    assert 'room.set("%s_upper_kg" % species, upper_kg)' in commit
    assert 'room.set("%s_kg" % species, upper_kg + lower_kg)' in commit


def test_canonical_pressure_has_one_owner_and_keeps_its_sign():
    commit = _function(ADAPTER_CODE, "commit_transaction")
    assert "room.overpressure_pa = gauge_pressure_pa" in commit
    assert "room.pressure_pa_therm = gauge_pressure_pa" in commit
    for forbidden in ("maxf(0.0, gauge_pressure_pa)", "absf(gauge_pressure_pa)"):
        assert forbidden not in ADAPTER_CODE, forbidden


def test_closed_doors_are_sealed_unless_d1_or_d2_is_enabled():
    """D1 aporta fuga fria y D2 huecos prescritos, siempre como rendijas.
    Sin ninguna de las dos capacidades, el comportamiento sigue siendo
    exactamente el de F2.2C."""
    snapshot = _function(ADAPTER_CODE, "build_snapshot")
    assert "if opening.is_closed() or open_fraction <= 0.001:" in snapshot
    assert "_crack_element(" in snapshot
    assert "continue" in snapshot
    crack = _function(ADAPTER_CODE, "_crack_element")
    guard = "if not closed_door_leakage_enabled and not closed_door_deformation_enabled:"
    assert guard in crack
    assert crack.index(guard) < crack.index("build_crack_element")
    # Una puerta cerrada nunca entra ademas como abertura grande.
    assert "cracks.append(crack)" in snapshot
    assert snapshot.index("cracks.append(crack)") < snapshot.index("openings.append({")
    # El adaptador sigue sin ser un modelo: describe la carpinteria, no calcula
    # la ley. D2 entra por un adaptador puro; el vidrio sigue fuera (D3).
    for forbidden in ("ClosedDoorDeformation" + "Model", "GlazingIntegrity" + "Model",
                      "GlazingOpeningGeometry" + "Model", "thermal_gap_fraction",
                      "pow(", "sqrt("):
        assert forbidden.lower() not in ADAPTER_CODE.lower(), forbidden


def test_collective_limiting_is_per_source_zone_and_order_independent():
    build = _function(ADAPTER_CODE, "build_transport_transaction")
    assert "factor = maxf(0.0, available_kg / wanted_kg)" in build
    assert "scale[room_id][zone] = factor" in build
    # The scale is decided before any delta is accumulated.
    assert build.index("scale[room_id][zone] = factor") < build.index("var applied_routes: Array = []")


def _run_validator():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    command = [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR]
    return run_godot(command, timeout_s=900, allowed_exit_codes=(0,))


def test_validator_passes():
    completed = _run_validator()
    output = (completed.stdout or "") + (completed.stderr or "")
    assert PASS_TOKEN in output
    assert "SCRIPT ERROR" not in output
    assert "Parse Error" not in output
