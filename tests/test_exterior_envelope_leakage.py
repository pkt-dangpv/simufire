"""F2.2-R3: contratos estructurales de la fuga de envolvente exterior cerrada.

Estos tests no miran comentarios: fijan estructura y comportamiento. Lo que
protegen es el reparto de responsabilidades, que es justo lo que se rompe
callando cuando alguien "arregla" algo deprisa:

  - la fuga es un ELEMENTO de la red, no un paso posterior al solver;
  - la ley es de ORIFICIO, no la de potencia de la rendija D1;
  - el area es GEOMETRICA y el Cd va aparte;
  - el viento y el perfil exterior tienen un unico dueno cada uno;
  - la purga historica no puede volver a la vida en paralelo.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ADAPTER = ROOT / "sim/core/ExteriorEnvelopeLeakageAdapter.gd"
WIND = ROOT / "sim/core/ExteriorWindPressureModel.gd"
TRANSPORT = ROOT / "sim/core/PressureNetworkTransportSystem.gd"
ENGINE = ROOT / "sim/core/SimulationEngine.gd"
GAS = ROOT / "sim/core/GasExchangeSystem.gd"
VALIDATOR = ROOT / "tools/validate_exterior_envelope_leakage.gd"

ADAPTER_SRC = ADAPTER.read_text(encoding="utf-8")
WIND_SRC = WIND.read_text(encoding="utf-8")
TRANSPORT_SRC = TRANSPORT.read_text(encoding="utf-8")
ENGINE_SRC = ENGINE.read_text(encoding="utf-8")
GAS_SRC = GAS.read_text(encoding="utf-8")

FLAG = "exterior_envelope_leakage_enabled"


def _code_only(source: str) -> str:
    """El fuente sin comentarios.

    Hace falta porque estos contratos se documentan EN el fichero: la cabecera
    del modelo de viento explica por que no usa `Vector2`, y la del adaptador
    por que no hereda `flow_path_factor`. Buscar la palabra a secas daria
    positivo sobre la propia explicacion.
    """
    lines = []
    for line in source.splitlines():
        if line.lstrip().startswith("#"):
            continue
        lines.append(line.split("  #")[0])
    return "\n".join(lines)


# --------------------------------------------------------------------------
# 1. El interruptor
# --------------------------------------------------------------------------

def test_the_flag_is_declared_once_boolean_and_off_by_default():
    declarations = re.findall(
        rf"^@export var {FLAG}: bool = (\w+)$", ENGINE_SRC, re.M)
    assert declarations == ["false"], declarations


def test_the_flag_requires_the_authoritative_network():
    """Pedir R3 sin la red es un error explicito, no un silencio.

    Y no puede encender la red por detras para taparlo: eso convertiria una
    configuracion invalida en una activacion silenciosa de fisica.
    """
    assert f"if {FLAG} and not pressure_network_solver_enabled:" in ENGINE_SRC
    assert "exterior_envelope_leakage_requires_pressure_network" in ENGINE_SRC
    # La dependencia se comprueba, nunca se "resuelve" encendiendo la red.
    # F2.2D4B2B: el motor escribe el solver en UN solo sitio, y no en secreto.
    #
    # Hasta D4B2A ningun camino lo encendia y la regla era que el texto no
    # apareciese. Luego aparecio una ruta -la autorizacion experimental- y la
    # regla paso a exigir que fuese la unica. El hotfix del ciclo de vida anade
    # la otra mitad: la autorizacion tambien tiene que RETIRAR lo que anadio, y
    # hacerlo sin pisar la configuracion de otro propietario.
    #
    # Por eso ya no se busca la constante `= true`: las cinco se escriben por
    # nombre en un unico `match`, y lo que se vigila es el ciclo completo.
    assert ENGINE_SRC.count("pressure_network_solver_enabled = true") == 0
    assert ENGINE_SRC.count("pressure_network_solver_enabled = value") == 1
    _writer = ENGINE_SRC.split(
        "func _write_experimental_switch(switch_name: String, value: bool) -> void:", 1
    )[1].split("\nfunc ", 1)[0]
    assert "pressure_network_solver_enabled = value" in _writer
    _activation = ENGINE_SRC.split(
        "func _apply_experimental_physics_authorization() -> void:", 1
    )[1].split("\nfunc ", 1)[0]
    assert "ExperimentalAuthorizationScript.REQUIRED_DEPENDENCY" in _activation
    # Dentro de esta funcion la retirada ocurre ANTES de cualquier retorno
    # temprano, que es lo que impide que revocar y reiniciar el mismo motor deje
    # encendida la corrida anterior. Las dos guardas de `reset_simulation`
    # -sin edificio, o motor no listo- tambien retiran, por su propia llamada a
    # `_discard_experimental_physics_authorization()`; lo comprueba el grupo 20
    # del validador de D4B2B.
    assert _activation.index("_discard_experimental_physics_authorization()") < (
        _activation.index("if building == null:")
    )
    # Y los dos retornos tempranos de `reset_simulation` retiran por su cuenta.
    _reset = ENGINE_SRC.split("func reset_simulation(", 1)[1].split("\nfunc ", 1)[0]
    _guard = _reset.index("if building == null or not is_ready_for_validation():")
    _discard = _reset.index("_discard_experimental_physics_authorization()")
    _apply = _reset.index("_apply_experimental_physics_authorization()")
    assert _guard < _discard < _apply
    # Y solo se retira lo que la autorizacion escribio, comparando el valor
    # actual contra el que dejo puesto: sin esto, reiniciar borraria
    # configuraciones ajenas. La comparacion detecta un CAMBIO DE VALOR, no quien
    # escribio: otro propietario que reescriba el mismo valor es
    # indistinguible. Segundo limite conocido de 23.9.1.
    _release = ENGINE_SRC.split(
        "func _release_experimental_switches() -> void:", 1
    )[1].split("\nfunc ", 1)[0]
    assert "_experimental_owned_switches" in _release
    assert 'owned["previous"]' in _release
    assert 'owned["applied"]' in _release
    assert "_experimental_owned_switches.clear()" in _release
    # Se resuelve en los dos sitios, no solo al nacer.
    assert "_apply_experimental_physics_authorization()" in ENGINE_SRC.split(
        "func reset_simulation(", 1
    )[1].split("\nfunc ", 1)[0]


def test_the_flag_reaches_the_transport_system_gated_by_the_network():
    pattern = (rf"pressure_network_transport_system\.{FLAG} = \\\s*\n"
               rf"\s*{FLAG} and pressure_network_solver_enabled")
    assert re.search(pattern, ENGINE_SRC), "el wiring debe ir conjugado con la red"


def test_r3_does_not_depend_on_the_closed_door_leakage_flag():
    """D1 y R3 son mecanismos distintos sobre aberturas distintas."""
    wiring = re.findall(rf".*{FLAG}.*", ENGINE_SRC)
    for line in wiring:
        assert "closed_door_leakage_enabled" not in line, line


# --------------------------------------------------------------------------
# 2. El adaptador es puro
# --------------------------------------------------------------------------

def test_the_adapter_mutates_nothing():
    """Describe geometria y procedencia. No resuelve ni escribe estado."""
    forbidden = [
        "room.", "RoomModel", "BuildingModel.new", "queue_free",
        "set_open_fraction", "overpressure_pa", "get_node", "$",
    ]
    for token in forbidden:
        assert token not in ADAPTER_SRC, f"el adaptador no puede tocar {token}"


def test_the_adapter_keeps_cd_separate_from_the_area():
    """0,005 m2 es area GEOMETRICA; el 0,61 se aplica aparte.

    Si alguien multiplicase el area por el Cd, el area declarada y la aplicada
    dirian cosas distintas y el coeficiente acabaria aplicado dos veces cuando
    el solver haga lo suyo.
    """
    assert "const DISCHARGE_COEFF: float = 0.61" in ADAPTER_SRC
    assert '"discharge_coeff": DISCHARGE_COEFF,' in ADAPTER_SRC
    # El area que se publica no lleva el coeficiente dentro.
    assert "leak_area_m2 * DISCHARGE_COEFF" not in ADAPTER_SRC
    assert "DISCHARGE_COEFF * leak_area_m2" not in ADAPTER_SRC


def test_the_orifice_law_is_not_the_power_law_of_the_door_crack():
    """R3 es Bernoulli; D1 es |dp|^0,65. Mezclarlas es un error fisico."""
    for source in (ADAPTER_SRC, WIND_SRC):
        assert "0.65" not in source
        assert "PROVISIONAL_FLOW_EXPONENT" not in source
        assert "ela_reference_pressure_pa" not in source
        assert "NIST_ELA" not in source


def test_the_equivalent_fraction_integrates_to_the_declared_area():
    """La equivalencia con la abertura grande tiene que ser exacta.

    El solver integra `Cd * width * open_fraction * dz` y el hueco mide
    `height_m`, luego `open_fraction = area / (width * height)` devuelve el area
    declarada. Si alguien cambia el denominador, deja de ser exacta.
    """
    assert "var open_fraction: float = leak_area_m2 / geometric_area_m2" in ADAPTER_SRC
    assert "var geometric_area_m2: float = width_m * height_m" in ADAPTER_SRC


def test_an_area_larger_than_the_opening_is_rejected_not_clamped():
    assert "if leak_area_m2 > geometric_area_m2:" in ADAPTER_SRC
    assert "clampf(leak_area_m2" not in ADAPTER_SRC
    assert "minf(leak_area_m2" not in ADAPTER_SRC


def test_holes_interiors_and_open_openings_get_no_envelope_leak():
    assert "if int(opening.type) == OpeningModelScript.Type.HOLE:" in ADAPTER_SRC
    assert "if int(opening.a) != outside_id and int(opening.b) != outside_id:" in ADAPTER_SRC
    assert "if not opening.is_closed():" in ADAPTER_SRC


def test_identifiers_are_unique_per_opening():
    """Dos ventanas iguales entre el mismo recinto y el exterior no colisionan."""
    assert 'const ID_PREFIX: String = "env_"' in ADAPTER_SRC
    assert '"%s%d" % [ID_PREFIX, int(opening.opening_index)]' in ADAPTER_SRC


def test_the_element_carries_its_provenance():
    assert 'const PROVENANCE: String = "exterior_envelope_leakage"' in ADAPTER_SRC
    assert '"provenance": PROVENANCE,' in ADAPTER_SRC


# --------------------------------------------------------------------------
# 3. Dentro del solver, no despues
# --------------------------------------------------------------------------

def test_the_leak_is_built_into_the_snapshot_not_applied_afterwards():
    """El elemento entra por `build_snapshot`, que es lo que ve el residuo.

    Si se aplicara despues del solve no participaria en Newton, y la presion
    publicada no seria la del recinto con su fuga.
    """
    assert "envelopes.append(envelope)" in TRANSPORT_SRC
    assert "openings.append_array(envelopes)" in TRANSPORT_SRC
    # Y no hay un segundo camino de transporte para esto.
    assert "_apply_envelope" not in TRANSPORT_SRC
    assert "envelope_transport" not in TRANSPORT_SRC


def test_the_transport_system_does_not_reimplement_bernoulli():
    """Una sola ley en el motor: la del solver."""
    envelope_block = TRANSPORT_SRC[TRANSPORT_SRC.index("func _envelope_element"):]
    envelope_block = envelope_block[:envelope_block.index("\nfunc _crack_element")]
    assert "sqrt(" not in envelope_block
    assert "pow(" not in envelope_block


def test_the_orientation_is_resolved_for_either_side():
    """OUTSIDE puede venir como `a` o como `b`; el interior se busca en los dos."""
    assert "if a_key == EXTERIOR_ROOM_ID and b_key != EXTERIOR_ROOM_ID:" in TRANSPORT_SRC
    assert "elif b_key == EXTERIOR_ROOM_ID and a_key != EXTERIOR_ROOM_ID:" in TRANSPORT_SRC


# --------------------------------------------------------------------------
# 4. Viento y referencia exterior: un dueno cada uno
# --------------------------------------------------------------------------

def test_the_wind_formula_has_a_single_owner():
    """`GasExchangeSystem` delega; no conserva su copia de la formula."""
    assert "ExteriorWindPressureModelScript.wind_dp_pa(" in GAS_SRC
    # La formula historica ya no vive alli.
    assert "0.5 * 1.2 * v * v * cp" not in GAS_SRC
    assert "cp = 0.6 * cos_inc" not in GAS_SRC
    # Y el modelo la tiene entera.
    assert "const CP_WINDWARD: float = 0.6" in WIND_SRC
    assert "const CP_LEEWARD: float = 0.4" in WIND_SRC


def test_the_wind_model_avoids_vector2_to_stay_bit_identical():
    """`Vector2` guarda `real_t` de 32 bits y romperia la identidad con OFF.

    Medido al extraer el modelo: 80 de 160 combinaciones diferian bit a bit
    cuando el producto escalar pasaba por `Vector2.dot`. La diferencia era de
    ~1e-6 Pa, fisicamente nada, pero la ruta historica tiene que ser identica.
    """
    code = _code_only(WIND_SRC)
    assert "Vector2" not in code
    assert ".dot(" not in code


def test_each_exterior_path_applies_wind_exactly_once_to_its_own_element():
    """R3 y D3 tienen elementos distintos y mutuamente exclusivos.

    Cada ruta fija una sola vez el termino de viento, mientras que la formula
    sigue teniendo un unico propietario en ``ExteriorWindPressureModel``.
    """
    assignments = re.findall(r'element\["wind_dp_pa"\] = ', TRANSPORT_SRC)
    assert len(assignments) == 2, assignments
    assert TRANSPORT_SRC.count(
        "_envelope_wind_dp_pa(opening, floor_z_m, building)"
    ) == 1
    assert TRANSPORT_SRC.count(
        'element["wind_dp_pa"] = _glazing_wind_dp_pa('
    ) == 1

    envelope_block = TRANSPORT_SRC.split("func _envelope_element", 1)[1]
    envelope_block = envelope_block.split("\nfunc ", 1)[0]
    glazing_build = TRANSPORT_SRC.split(
        "if glazing_fallout_enabled and GlazingAdapterScript.has_declaration(opening):",
        1,
    )[1].split("# F2.2D1:", 1)[0]
    assert envelope_block.count('element["wind_dp_pa"] = ') == 1
    assert glazing_build.count('element["wind_dp_pa"] = ') == 1


def test_the_exterior_reference_datum_is_propagated():
    """F2.2C-R1.1: sin esto, un recinto elevado inventa rho*g*z de sobrepresion."""
    assert '"reference_z_m": float(snapshot["outside"].get("reference_z_m", 0.0)),' \
        in TRANSPORT_SRC


def test_the_flow_path_heuristic_is_not_inherited():
    """`flow_path_factor` reducia el area segun `hrr_kw`. Es una heuristica de
    la ruta historica para emular caminos de flujo que la red ya resuelve."""
    assert "flow_path_factor" not in _code_only(ADAPTER_SRC)
    envelope_block = TRANSPORT_SRC[TRANSPORT_SRC.index("func _envelope_element"):]
    envelope_block = envelope_block[:envelope_block.index("\nfunc _crack_element")]
    assert "flow_path" not in _code_only(envelope_block)


# --------------------------------------------------------------------------
# 5. Un solo propietario del estado
# --------------------------------------------------------------------------

def test_the_historical_purge_stays_off_under_the_authoritative_network():
    """`step_pressure_venting` sale antes de tocar nada con la red encendida."""
    block = GAS_SRC[GAS_SRC.index("func step_pressure_venting"):]
    block = block[:6000]
    assert "if authoritative_transport_enabled:\n\t\treturn result" in block
    assert "gas_exchange_system.authoritative_transport_enabled = pressure_network_solver_enabled" \
        in ENGINE_SRC


def test_the_validator_exists_and_is_registered_in_the_product_check():
    assert VALIDATOR.exists()
    check = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")
    assert "validate_exterior_envelope_leakage.gd" in check
    assert "EXTERIOR ENVELOPE LEAKAGE VALIDATION PASS" in check
