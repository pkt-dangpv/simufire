"""Cold closed-door leakage inside the authoritative network (phase F2.2D1).

A closed interior door is never perfectly sealed: it leaks through the gaps at
the bottom, the sides and the lintel. F2.2D1 puts that leakage inside the same
pressure network that already owns the large openings, as ELA cracks obeying the
NIST power law, and behind one flag that is off by default and depends on the
network flag.

What these tests protect:
  - one crack law, in `ClosedDoorLeakageModel`, shared by the pure model and the
    solver: no second copy and no second discharge coefficient;
  - an ELA crack is never integrated as a Bernoulli opening;
  - exclusivity: a door is either a large opening or a set of cracks;
  - `thermal_gap_fraction` (prescribed deformation, phase D2) does not leak into
    the operational fraction the network reads;
  - stable, unique opening identifiers;
  - the flag is off by default, it is not turned on by any shipped scenario, and
    asking for leakage without the network is an explicit failure.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
MODEL = (ROOT / "sim/core/ClosedDoorLeakageModel.gd").read_text(encoding="utf-8")
ADAPTER_PATH = ROOT / "sim" / "core" / "ClosedDoorLeakageNetworkAdapter.gd"
ADAPTER = ADAPTER_PATH.read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
TRANSPORT = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
OPENING = (ROOT / "sim/building/OpeningModel.gd").read_text(encoding="utf-8")
BUILDING = (ROOT / "sim/BuildingModel.gd").read_text(encoding="utf-8")
SERIALIZER = (ROOT / "editor/ScenarioSerializer.gd").read_text(encoding="utf-8")

VALIDATOR = "res://tools/validate_closed_door_leakage_network.gd"
PASS_TOKEN = "CLOSED DOOR LEAKAGE NETWORK VALIDATION PASS"
FLAG = "closed_door_leakage_enabled"
NETWORK_FLAG = "pressure_network_solver_enabled"

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _code(source: str) -> str:
    return "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


ADAPTER_CODE = _code(ADAPTER)
SOLVER_CODE = _code(SOLVER)
TRANSPORT_CODE = _code(TRANSPORT)


# --------------------------------------------------------------- one crack law

def test_the_crack_law_lives_in_one_place():
    """El solver no reimplementa la ley: llama al mismo ayudante que el modelo
    puro. Dos copias se separarian en cuanto una se corrigiera."""
    assert "static func compute_segment_flow_from_dp(" in MODEL
    assert "ClosedDoorLeakageModelScript.compute_segment_flow_from_dp(" in SOLVER_CODE
    crack = _function(SOLVER_CODE, "_integrate_crack")
    # Ni exponentes, ni raices, ni coeficientes de descarga dentro del solver.
    for forbidden in ("pow(", "sqrt(", "0.65", "discharge"):
        assert forbidden not in crack, forbidden


def test_the_pure_model_uses_the_same_helper_as_the_solver():
    flows = _function(_code(MODEL), "compute_flows")
    assert "compute_segment_flow_from_dp(" in flows
    # Y la ley vive encerrada en ese ayudante: las dos unicas potencias del
    # modelo (la del caudal y la del empalme de regularizacion) estan dentro.
    helper = _function(_code(MODEL), "compute_segment_flow_from_dp")
    assert _code(MODEL).count("pow(") == helper.count("pow(") == 2


def test_the_ela_convention_is_a_unit_discharge_coefficient_at_4_pa():
    """La definicion de ELA (NIST TN 1887r1) ya lleva dentro la descarga: si se
    volviera a multiplicar por 0,61 el area declarada dejaria de significar lo
    que mide el ensayo."""
    assert "NIST_ELA_REFERENCE_PRESSURE_PA" in MODEL
    assert "4.0" in MODEL
    helper = _function(_code(MODEL), "compute_segment_flow_from_dp")
    assert "discharge" not in helper
    assert "0.61" not in helper


def test_the_exponent_is_the_crack_one_and_not_the_orifice_one():
    assert "PROVISIONAL_FLOW_EXPONENT_CANDIDATE" in MODEL
    assert "0.65" in MODEL
    crack_build = _function(SOLVER_CODE, "_build_crack_element")
    assert "PROVISIONAL_FLOW_EXPONENT_CANDIDATE" in crack_build


# ------------------------------------------------- heterogeneous solver network

def test_the_solver_dispatches_by_flow_model():
    evaluate = _function(SOLVER_CODE, "_evaluate")
    assert "FLOW_MODEL_ELA_CRACK" in evaluate
    assert "_integrate_crack(" in evaluate
    assert "_integrate_opening(" in evaluate


def test_an_unknown_flow_model_is_rejected_and_never_guessed():
    prepare = _function(SOLVER_CODE, "_prepare_network")
    assert "FLOW_MODEL_ELA_CRACK" in prepare
    assert "FLOW_MODEL_LARGE_OPENING" in prepare
    # Un `flow_model` que no se reconoce para la entrada, no se trata como
    # abertura grande "por si acaso".
    assert "has an unknown flow_model" in prepare
    assert "errors.append(" in prepare


def test_a_crack_never_faces_the_exterior_in_d1():
    """La fuga exterior (envolvente) no es D1: una rendija contra el exterior se
    rechaza en vez de inventarse una infiltracion de fachada."""
    crack_element = _function(TRANSPORT_CODE, "_crack_element")
    assert "EXTERIOR_ROOM_ID" in crack_element
    assert "return {}" in crack_element
    provides = _function(ADAPTER_CODE, "provides_leakage")
    assert "outside_id" in provides


def test_the_engine_calls_the_transport_once_per_step():
    """La invariante de F2.2C es un solo dueno y una sola aplicacion por paso.
    `commit_count` la deja comprobable desde fuera, y el motor solo tiene un
    sitio desde el que llamar al transporte."""
    engine_code = _code(ENGINE)
    assert engine_code.count("_step_pressure_network_transport(dt)") == 1
    assert "var commit_count: int = 0" in TRANSPORT
    step = _function(TRANSPORT_CODE, "step")
    assert "commit_count += 1" in step
    # Solo cuenta lo que de verdad se aplico.
    assert 'if bool(commit["applied"]):\n\t\tcommit_count += 1' in TRANSPORT_CODE


def test_a_crack_never_reaches_the_bernoulli_integrator():
    """La red es heterogenea: si un elemento de rendija cayera en la ruta de
    abertura grande, antes reventaba leyendo `coefficient`. Ahora se rechaza."""
    integrate = _function(SOLVER_CODE, "_integrate_opening")
    assert "FLOW_MODEL_LARGE_OPENING" in integrate
    assert 'return {"valid": false}' in integrate
    head = integrate[:integrate.index("FLOW_MODEL_LARGE_OPENING")]
    # El rechazo va lo primero, antes de leer ningun campo de abertura grande.
    assert "coefficient" not in head


def test_the_crack_element_is_integrated_inside_the_newton_residual():
    """La rendija no se aplica despues de resolver: participa en el residuo, asi
    que su caudal y la presion que lo produce son consistentes."""
    evaluate = _function(SOLVER_CODE, "_evaluate")
    assert "_integrate_crack(" in evaluate
    # `_evaluate` es lo que la iteracion de Newton llama, no un paso posterior.
    assert "_evaluate(" in _function(SOLVER_CODE, "solve_pressure_network") \
        or "_evaluate(" in SOLVER_CODE


def test_a_crack_reports_its_own_diagnostics():
    crack = _function(SOLVER_CODE, "_integrate_crack")
    for key in ("domain_exceeded_count", "max_abs_dp_pa", "regularization_active_count"):
        assert key in crack, key


def test_the_crack_diagnostics_reach_the_consumer():
    """Un diagnostico que se queda dentro del solver no sirve de nada: la ΔP de
    la rendija y el dominio excedido tienen que salir en la solucion publicada,
    y solo para la rendija, para que una abertura grande siga igual que en
    F2.2C."""
    published = _function(SOLVER_CODE, "_network_openings")
    assert 'if connection.has("flow_model"):' in published
    for key in ("flow_model", "domain_exceeded_count", "max_abs_dp_pa"):
        assert f'published["{key}"]' in published, key
    # Se anaden DESPUES del diccionario comun, nunca dentro de el.
    assert published.index("openings_out.append({") < published.index('if connection.has("flow_model"):')


def test_the_experimental_domain_is_recorded_and_never_clamped():
    """50 Pa es donde acaban los ensayos, no donde acaba la fisica: pasarse se
    anota, pero el caudal no se recorta (eso falsearia la masa transportada)."""
    assert "PRESSURE_DOMAIN_MAX_PA" in ADAPTER
    helper = _function(_code(MODEL), "compute_segment_flow_from_dp")
    assert "domain_exceeded" in helper
    assert "clamp" not in helper.lower()


# ------------------------------------------------------- open/closed exclusivity

def test_the_network_reads_the_operational_fraction_without_deformation():
    """`effective_open_fraction()` suma `thermal_gap_fraction`, que es la
    deformacion prescrita de la fase D2. Si la red lo leyera, una puerta cerrada
    y caliente entraria como abertura grande de Bernoulli."""
    snapshot = _function(TRANSPORT_CODE, "build_snapshot")
    assert "effective_open_fraction()" not in snapshot
    assert "float(opening.open_fraction)" in snapshot
    assert "thermal_gap_fraction" not in TRANSPORT_CODE


def test_effective_open_fraction_still_exists_for_its_historical_owners():
    """No se borra el concepto: D2 lo necesita, y las rutas historicas siguen
    usandolo. Solo deja de gobernar la red autoritativa."""
    assert "func effective_open_fraction(" in OPENING
    assert "thermal_gap_fraction" in OPENING


def test_a_hole_is_never_a_crack():
    provides = _function(ADAPTER_CODE, "provides_leakage")
    assert "OpeningModel.Type.DOOR" in provides
    snapshot = _function(TRANSPORT_CODE, "build_snapshot")
    assert "OpeningModel.Type.HOLE" in snapshot


def test_a_door_with_no_declared_class_stays_sealed():
    """Ningun escenario historico gana fuga sin pedirla."""
    assert 'var leakage_class: String = "none"' in OPENING
    assert "var leakage_area_override_m2: float = -1.0" in OPENING
    resolved = _function(ADAPTER_CODE, "resolved_ela_m2")
    assert "class_ela_m2" in resolved


def test_the_override_wins_over_the_class():
    resolved = _function(ADAPTER_CODE, "resolved_ela_m2")
    assert resolved.index("override_m2") < resolved.index("class_ela_m2")


def test_the_ela_table_is_not_copied_into_the_adapter():
    assert "PLANNED_CLASS_ELA_M2" in ADAPTER
    for forbidden in ("0.0012", "0.0021", "12.0", "21.0"):
        assert forbidden not in ADAPTER_CODE, forbidden


# --------------------------------------------------------------- identifiers

def test_opening_identifiers_are_unique_and_stable():
    """Dos puertas iguales entre las mismas salas colisionaban con el
    identificador de F2.2C (`op_<a>_<b>_<tipo>`): la segunda pisaba a la
    primera. El indice de la abertura es unico por construccion."""
    snapshot = _function(TRANSPORT_CODE, "build_snapshot")
    assert '"op_%d" % int(opening.opening_index)' in snapshot
    assert '"op_%d_%d_%d"' not in TRANSPORT_CODE
    crack = _function(TRANSPORT_CODE, "_crack_element")
    assert '"crack_%d" % int(opening.opening_index)' in crack


def test_the_building_assigns_the_canonical_index():
    assert "op.opening_index = openings.size()" in BUILDING


# --------------------------------------------------------------------- the flag

def test_the_flag_is_declared_once_and_off_by_default():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    assert ENGINE.count(f"@export var {FLAG}") == 1


def test_leakage_without_the_network_is_an_explicit_failure():
    """Ni se ignora en silencio ni enciende el solver por detras."""
    assert "closed_door_leakage_requires_pressure_network" in ENGINE
    assert "push_error(" in ENGINE
    engine_code = _code(ENGINE)
    assert f"if {FLAG} and not {NETWORK_FLAG}:" in engine_code


def test_the_adapter_only_runs_with_both_flags_on():
    engine_code = _code(ENGINE)
    assert f"{FLAG} and {NETWORK_FLAG}" in engine_code


def test_no_shipped_scenario_turns_the_flag_on():
    hits = []
    for pattern in ("*.tres", "*.tscn", "*.json", "*.cfg"):
        for path in ROOT.rglob(pattern):
            if any(part in {".git", "runs", "sim_out", "reports"} for part in path.parts):
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            if f"{FLAG} = true" in text or f'"{FLAG}": true' in text:
                hits.append(str(path.relative_to(ROOT)))
    assert hits == [], hits


# ------------------------------------------------------- scenario round trip

def test_the_scenario_rejects_an_unknown_class_and_an_invalid_override():
    assert "unknown leakage_class" in BUILDING
    assert "leakage_area_override_m2 must be finite and >= 0" in BUILDING


def test_opening_and_closing_a_door_keeps_its_leakage_class():
    """La clase es una propiedad de la carpinteria, no del estado operativo."""
    assert 'opening["leakage_class"] = leakage_class' in SERIALIZER
    assert "is_known_class(leakage_class)" in SERIALIZER
    normalize = SERIALIZER.split('opening["leakage_class"]', 1)[0]
    assert "open_fraction" in normalize


# --------------------------------------------------------------- the validator

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
