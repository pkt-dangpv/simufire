"""Multi-storey pressure datum in the authoritative network (phase F2.2C-R1).

A building is not flat. Until this phase the network carried a single exterior
pressure and used it as the zero of every room's gauge, whatever its height, and
it fed a stairwell hole into the Bernoulli vane model anchored at one room's
floor. Both are fixed here.

What these tests protect:
  - one owner of the atmospheric column, `ExteriorPressureProfile`;
  - `outside.reference_z_m`, absent meaning 0 m so historical cases are intact;
  - a room's gauge is measured against the exterior at ITS OWN floor;
  - the reference mass of the equation of state is the local one;
  - two rooms on different storeys are compared at the same absolute height;
  - a floor/ceiling hole is its own element class, not a vane;
  - no profile is ever evaluated outside its own room;
  - a zone with no gas never donates.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "sim/core/ExteriorPressureProfile.gd").read_text(encoding="utf-8")
SHAFT = (ROOT / "sim/core/VerticalShaftFlowModel.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
TRANSPORT = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(encoding="utf-8")
EQUATIONS = (ROOT / "sim/core/CompartmentPressureEquations.gd").read_text(encoding="utf-8")

VALIDATOR = "res://tools/validate_multistorey_pressure_datum.gd"
PASS_TOKEN = "MULTISTOREY PRESSURE DATUM VALIDATION PASS"

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


SOLVER_CODE = _code(SOLVER)
TRANSPORT_CODE = _code(TRANSPORT)
PROFILE_CODE = _code(PROFILE)
SHAFT_CODE = _code(SHAFT)


# ------------------------------------------------------- one atmospheric column

def test_the_hydrostatic_column_has_a_single_owner():
    """La formula de la columna se escribe UNA vez. Copiarla en cada sistema es
    exactamente lo que produjo el defecto que esta fase corrige."""
    assert "static func pressure_at(" in PROFILE
    assert "- float(resolved[\"density_kg_m3\"]) * GRAVITY_M_S2" in PROFILE
    assert "ExteriorPressureProfileScript.pressure_at(" in SOLVER_CODE
    # Y el solver no vuelve a escribir la columna atmosferica por su cuenta.
    for forbidden in ("* GRAVITY_M_S2 * (z_m - ", "exterior_pressure_abs_pa - "):
        assert forbidden not in SOLVER_CODE, forbidden


def test_the_reference_height_defaults_to_zero():
    """Sin `reference_z_m` la cota es 0 m, que es lo que valia implicitamente
    antes de que el campo existiera: los casos historicos quedan intactos."""
    resolve = _function(PROFILE_CODE, "resolve")
    assert 'float(state.get("reference_z_m", 0.0))' in resolve
    prepare = _function(SOLVER_CODE, "_prepare_network")
    assert 'float(outside.get("reference_z_m", 0.0))' in prepare
    assert '"exterior_reference_z_m": exterior_reference_z_m,' in prepare


def test_the_profile_refuses_an_unusable_boundary():
    resolve = _function(PROFILE_CODE, "resolve")
    for message in ("pressure_abs_pa must be finite and > 0",
                    "reference_temp_k must be finite and > 0",
                    "reference_z_m must be finite",
                    "density_kg_m3 must be finite and > 0"):
        assert message in resolve, message
    pressure_at = _function(PROFILE_CODE, "pressure_at")
    # Una columna que llevara la presion a cero o menos no es un estado fisico.
    assert "pressure_pa <= 0.0" in pressure_at
    assert "return NAN" in pressure_at


# --------------------------------------------------------- the gauge is local

def test_the_reference_mass_uses_the_local_exterior_pressure():
    """El cero de la manometrica de un recinto es el exterior de SU suelo. Con
    la presion de la cota de referencia para todas las plantas, un recinto
    elevado en equilibrio publicaba -rho*g*z."""
    derive = _function(SOLVER_CODE, "_derive_room")
    assert "ExteriorPressureProfileScript.pressure_at(" in derive
    assert "local_exterior_pressure_pa * volume_m3" in derive
    assert "exterior_pressure_abs_pa * volume_m3" not in derive


def test_the_published_absolute_pressure_is_local_too():
    finish = _function(SOLVER_CODE, "_finish_network")
    assert 'context["rooms"][room_key]["exterior_pressure_abs_pa"]' in finish
    # Y el evaluador de compartimento recibe el contorno de CADA sala.
    assert "outside_state[\"pressure_abs_pa\"] = float(" in finish
    assert "outside_template" in finish


def test_two_storeys_are_compared_at_the_same_height():
    """Con la manometrica referida al exterior local, la diferencia de gauges ya
    no es la diferencia de presiones absolutas: falta la diferencia entre los
    dos exteriores locales. Ese termino vale 0 en una sola planta."""
    offset = _function(SOLVER_CODE, "_datum_offset_pa")
    assert "datum_a_pa - datum_b_pa" in offset
    hydrostatic = _function(SOLVER_CODE, "_hydrostatic_offset_pa")
    assert "_datum_offset_pa(side_a, side_b)" in hydrostatic


# ------------------------------------------------------ the floor/ceiling hole

def test_a_vertical_hole_is_its_own_element_class():
    assert 'FLOW_MODEL_VERTICAL_SHAFT: String = "vertical_shaft"' in SOLVER
    assert "_build_shaft_element(" in SOLVER_CODE
    assert "_integrate_shaft(" in SOLVER_CODE
    # El adaptador lo reconoce por el campo que ya existia en el modelo.
    snapshot = _function(TRANSPORT_CODE, "build_snapshot")
    assert "opening.is_vertical" in snapshot
    assert "_shaft_element(" in snapshot


def test_the_shaft_law_lives_in_its_own_pure_model():
    assert "static func compute_flows(" in SHAFT
    assert "VerticalShaftFlowModelScript.compute_flows(" in SOLVER_CODE
    integrate = _function(SOLVER_CODE, "_integrate_shaft")
    # La ley no se copia en el solver.
    for forbidden in ("sqrt(2.0 * GRAVITY", "0.61"):
        assert forbidden not in integrate, forbidden


def test_buoyancy_decides_the_exchange_not_temperature():
    """Con gases de distinta composicion la temperatura sola mentiria: manda la
    densidad. Y si lo de abajo pesa mas, la estratificacion es estable y no hay
    intercambio."""
    flows = _function(SHAFT_CODE, "compute_flows")
    assert "var density_difference: float = rho_above_kg_m3 - rho_below_kg_m3" in flows
    assert "if density_difference > DENSITY_EPS_KG_M3:" in flows
    assert "temp" not in flows.lower()


def test_the_exchange_is_a_swap_and_not_a_net_flow():
    flows = _function(SHAFT_CODE, "compute_flows")
    assert 'result["exchange_mass_up_kg_s"] = exchange_kg_s' in flows
    assert 'result["exchange_mass_down_kg_s"] = exchange_kg_s' in flows


def test_a_shaft_cannot_face_the_exterior():
    """Un hueco entre plantas es cosa de dos recintos; contra el exterior no
    significa nada y se rechaza en vez de inventarse una losa al aire."""
    prepare = _function(SOLVER_CODE, "_prepare_network")
    assert "is a vertical shaft and cannot face the exterior" in prepare
    element = _function(TRANSPORT_CODE, "_shaft_element")
    assert "EXTERIOR_ROOM_ID" in element


# ------------------------------------------- no profile outside its own room

def test_each_side_is_evaluated_inside_its_own_room():
    """El defecto que descarto el 34 % de los pasos del portal: el vano quedaba
    por debajo del suelo del recinto de arriba y su perfil se extrapolaba metros
    fuera de la losa."""
    build = _function(SOLVER_CODE, "_build_shaft_element")
    assert "ceiling_below_z_m" in build
    assert "floor_above_z_m" in build
    assert "return {\"valid\": false}" in build
    integrate = _function(SOLVER_CODE, "_integrate_shaft")
    assert "_column_mass_per_area(side_below, ceiling_below_z_m)" in integrate
    assert "_density_at(side_above, floor_above_z_m)" in integrate


def test_the_slab_thickness_is_carried_when_storeys_are_not_contiguous():
    integrate = _function(SOLVER_CODE, "_integrate_shaft")
    assert "shaft_column_pa" in integrate
    assert 'float(opening["slab_thickness_m"])' in integrate


# ------------------------------------------------- an empty zone never donates

def test_a_degenerate_zone_is_never_the_donor():
    """La etiqueta de zona en un borde la decidia un empate de coma flotante y
    podia elegir la zona vacia. El gas esta donde esta la masa."""
    zone_at = _function(SOLVER_CODE, "_zone_at")
    assert "upper_degenerate" in zone_at
    assert "lower_degenerate" in zone_at
    assert "_geometric_zone_at(" in zone_at


def test_a_donation_is_split_by_what_each_zone_holds():
    """Ni se inventa masa ni se recorta caudal: se reparte el mismo caudal entre
    las dos zonas segun lo que cada una puede entregar en el paso."""
    split = _function(SOLVER_CODE, "_split_donation_by_inventory")
    assert "minf(mass_kg, maxf(0.0, available_preferred))" in split
    assert "var remainder: float = mass_kg - from_preferred" in split
    integrate = _function(SOLVER_CODE, "_integrate_shaft")
    assert "_split_donation_by_inventory(" in integrate


def test_the_exterior_is_a_reservoir_that_never_runs_out():
    side = _function(SOLVER_CODE, "_side_profile")
    assert '"upper_gas_kg": INF,' in side
    assert '"lower_gas_kg": INF,' in side


# ------------------------------------------- convergence is not negotiable

def test_the_canonical_tolerances_are_the_declared_ones():
    """Son constantes globales justificadas por la precision doble, nunca un
    knob por caso. Subirlas para que un escenario dificil 'pase' es la forma mas
    facil de fingir que la red converge."""
    assert "const DEFAULT_PRESSURE_TOLERANCE_PA: float = 1.0e-6" in SOLVER
    assert "const DEFAULT_MASS_TOLERANCE_KG: float = 1.0e-9" in SOLVER
    assert "const DEFAULT_ENERGY_TOLERANCE_KJ: float = 1.0e-6" in SOLVER


def test_every_convergence_criterion_is_checked():
    """Convergencia fisica: todos los criterios a la vez. Quitar cualquiera de
    ellos deja pasar un estado que no cierra."""
    finish = _function(SOLVER_CODE, "_finish_network")
    for reason in ("compartment_equations_rejected_candidate",
                   "pressure_closure_above_tolerance",
                   "mass_residual_above_tolerance",
                   "energy_residual_above_tolerance"):
        assert f'reasons.append("{reason}")' in finish, reason
    # Y cada uno esta guardado por su propia comparacion con su tolerancia.
    assert "if max_pressure_residual_pa > pressure_tolerance_pa:" in finish
    assert "if max_mass_residual_kg > mass_tolerance_kg:" in finish
    assert "if max_energy_residual_kj > energy_tolerance_kj:" in finish


def test_interior_wind_is_refused_twice():
    """El viento es una propiedad del nodo exterior. Una abertura interior no
    tiene lado exterior, asi que no puede llevarlo. Lo rechazan la entrada
    canonica y el constructor del elemento, de forma independiente."""
    prepare = _function(SOLVER_CODE, "_prepare_network")
    assert "is interior and cannot carry wind" in prepare
    build = _function(SOLVER_CODE, "_build_opening")
    assert "exterior_gauge_pa != 0.0 and not room_a_key.is_empty()" in build


def test_a_same_storey_hole_is_not_a_shaft():
    """Dos recintos de la misma planta no tienen losa entre ellos: declarar ahi
    un hueco de suelo/techo no significa nada y no entra en la red."""
    element = _function(TRANSPORT_CODE, "_shaft_element")
    assert "if absf(floor_a_z_m - floor_b_z_m) <= 1.0e-9:" in element
    assert "return {}" in element
    build = _function(SOLVER_CODE, "_build_shaft_element")
    assert "if absf(floor_a_z_m - floor_b_z_m) <= 1.0e-9:" in build


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
