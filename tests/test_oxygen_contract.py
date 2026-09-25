"""O2-A: contrato de consumo de oxígeno. Pruebas que FALLAN con el estado actual.

Estas pruebas no cambian física. Definen, en forma ejecutable, lo que el motor
debería cumplir por **conservación y disponibilidad**, no por parecerse a FDS.
El diagnóstico que las motiva está en
`docs/validation/DIAGNOSTICO_O2_CASA_SIMPLE_2026-09-24.md`.

Dos familias:

* **Estáticas** — leen el código. Se ejecutan siempre, no necesitan Godot.
* **Sobre traza** — leen el `sim_log.csv` de una corrida. Se saltan si no se
  apunta a una con `SIMUFIRE_O2_RUN_DIR=<carpeta con sim_log.csv>`, de modo que
  la suite no depende de tener una corrida a mano.

Las pruebas que hoy fallan llevan `xfail(strict=True)`: si alguien arregla el
defecto sin quitar la marca, la suite avisa de que la marca sobra. Ninguna
tolerancia es arbitraria; todas se justifican en `TOLERANCIAS`.
"""

from __future__ import annotations

import csv
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
COMBUSTION = ROOT / "sim/fire/CombustionSystem.gd"
OXYGEN = ROOT / "sim/core/OxygenExchangeSystem.gd"

# ---------------------------------------------------------------------------
# TOLERANCIAS — medidas, no elegidas
#
# En la corrida `fds_simple_house_default` las cinco salas que NO arden cierran
# su balance de O2 con un residual maximo de 1,31e-4 kg sobre inventarios de
# 4,2 a 9,0 kg, es decir 2,1e-5 en relativo. Ese es el suelo numerico observable
# del registro (float32 en CSV, 3120 pasos acumulados).
#
# Se toma un orden de magnitud por encima de ese suelo:
#   - absoluto : 1e-3 kg
#   - relativo : 1e-4 del inventario inicial de O2 de la sala
# y se admite el mayor de los dos. Con esos valores, las cinco salas sanas pasan
# con holgura y el Salon falla por un factor de ~7e4.
# ---------------------------------------------------------------------------
TOL_ABS_KG = 1.0e-3
TOL_REL = 1.0e-4

# Calor de combustion efectivo: el contrato no fija su valor, solo exige que el
# calor aceptado y el combustible consumido describan la misma masa quemada.
# 5 % cubre el redondeo del registro y el desfase de un paso entre ambos
# acumuladores (dt = 1/12 s sobre 260 s).
TOL_FUEL_HEAT_REL = 0.05

_RUN_DIR = os.environ.get("SIMUFIRE_O2_RUN_DIR", "")
_needs_run = pytest.mark.skipif(
    not _RUN_DIR or not (Path(_RUN_DIR) / "sim_log.csv").is_file(),
    reason="define SIMUFIRE_O2_RUN_DIR con una carpeta que contenga sim_log.csv",
)


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _rooms() -> dict[str, list[dict[str, str]]]:
    per: dict[str, list[dict[str, str]]] = {}
    with (Path(_RUN_DIR) / "sim_log.csv").open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            per.setdefault(row["room_name"], []).append(row)
    return per


def _tol(initial_o2_kg: float) -> float:
    return max(TOL_ABS_KG, TOL_REL * initial_o2_kg)


# ---------------------------------------------------------------------------
# 1. Estáticas — el depósito que se lee y el que se descuenta
# ---------------------------------------------------------------------------

def test_the_limiter_reads_the_lower_layer_when_the_plume_is_below_the_interface():
    """Punto de partida: esto es lo que hace hoy `CombustionSystem`, y está bien.

    Si esta prueba deja de pasar, las dos siguientes hablan de otra cosa.
    """
    source = _source(COMBUSTION)
    assert 'mode = "plume_lower"' in source
    marker = source.index('mode = "plume_lower"')
    window = source[marker - 400:marker]
    assert "o2_ref = room.o2_lower" in window, (
        "el modo plume_lower debe leer room.o2_lower")


@pytest.mark.xfail(strict=True, reason="O2-1: el sumidero se decide con otra condición")
def test_the_sink_gate_ignores_openings_that_the_limiter_also_ignores():
    """O2-1. El limitador elige depósito **solo** por la altura de la interfaz.

    `OxygenExchangeSystem` decide dónde descontar con una condición distinta,
    que además mira las aberturas de la sala. Con una puerta interior abierta
    —el caso residencial normal— las dos decisiones discrepan y el fuego respira
    de un depósito que nadie descuenta.

    El contrato: la condición que encamina el sumidero no puede depender de algo
    que el limitador no mira. Cuando esto se arregle, quítese el xfail.
    """
    source = _source(OXYGEN)
    start = source.index("var plume_lower_mode: bool = (")
    # La condición es una expresión entre paréntesis repartida en varias líneas;
    # termina en la primera línea que sólo contiene el paréntesis de cierre.
    end = source.index("\n\t\t)\n", start)
    gate = source[start:end]
    assert "_estimate_room_interior_open_factor" not in gate, (
        "el sumidero se encamina mirando las puertas interiores; el limitador no "
        "las mira. Ver DIAGNOSTICO_O2_CASA_SIMPLE_2026-09-24.md §5")


@pytest.mark.xfail(strict=True, reason="O2-3: el tope recorta el sumidero sin tocar el HRR")
def test_the_bulk_cap_reduces_the_accepted_combustion_in_the_same_transaction():
    """O2-3. El sumidero bulk se topa al 5 % del O2 de la sala por paso.

    Si el oxígeno disponible limita, debe bajar la combustión aceptada y sus
    productos en la MISMA transacción. Hoy el tope recorta solo el descuento: el
    HRR ya está fijado y no se revisa, así que se acepta combustión cuyo O2 no
    se descuenta de ningún sitio.

    Esto NO se arregla con una deuda contable: el contrato exige menos
    combustión, no un apunte pendiente.
    """
    source = _source(OXYGEN)
    cap = "consumed = minf(consumed, o2_mass_kg * 0.05)"
    assert cap in source, "cambió el tope; revísese esta prueba"
    window = source[source.index(cap):source.index(cap) + 900]
    assert "hrr" in window.lower(), (
        "el tope del 5 % recorta el descuento de O2 sin revisar el HRR aceptado. "
        "Ver DIAGNOSTICO_O2_CASA_SIMPLE_2026-09-24.md §7")


# ---------------------------------------------------------------------------
# 2. Sobre traza — balances con unidades
# ---------------------------------------------------------------------------

@_needs_run
def test_every_room_closes_its_oxygen_balance():
    """Conservación por sala, en kg:

        O2(t_final) == O2(0) - consumido + transporte_neto + exterior_neto + sync_zonal

    Todos los términos son acumuladores del propio motor. Un residual positivo
    significa que la sala acaba con más oxígeno del que su propia contabilidad
    permite.
    """
    failures = []
    for name, rows in _rooms().items():
        first, last = rows[0], rows[-1]
        air = float(last["air_mass_kg"])
        initial = float(first["o2"]) * air
        expected = (
            initial
            - float(last["o2_consumed_kg_total_all"])
            + float(last["o2_net_transport_kg_total"])
            + float(last["o2_exterior_net_kg_total"])
            + float(last["o2_zone_sync_kg_total"])
        )
        residual = float(last["o2"]) * air - expected
        if abs(residual) > _tol(initial):
            failures.append(
                "%s: residual %+.4f kg (tolerancia %.4f kg, inventario inicial %.3f kg)"
                % (name, residual, _tol(initial), initial))
    assert not failures, "\n".join(failures)


@_needs_run
def test_the_oxygen_counted_as_consumed_is_the_oxygen_actually_subtracted():
    """El motor lleva dos contadores del mismo hecho físico.

    `o2_consumed_kg_total_all` es lo que la combustión declara haber consumido;
    `o2_consumed_bulk_kg_total` es lo que la vía bulk descontó de `room.o2`.
    Mientras no exista un inventario autoritativo único, la diferencia entre
    ambos es oxígeno que se quema y no sale de ningún sitio.
    """
    failures = []
    for name, rows in _rooms().items():
        last = rows[-1]
        declared = float(last["o2_consumed_kg_total_all"])
        if declared <= 0.0:
            continue
        subtracted = float(last["o2_consumed_bulk_kg_total"])
        gap = declared - subtracted
        if abs(gap) > _tol(float(rows[0]["o2"]) * float(last["air_mass_kg"])):
            failures.append(
                "%s: declarado %.3f kg, descontado %.3f kg, diferencia %+.3f kg (%.1f %%)"
                % (name, declared, subtracted, gap, 100.0 * gap / declared))
    assert not failures, "\n".join(failures)


@_needs_run
def test_the_accepted_heat_and_the_consumed_fuel_describe_the_same_burn():
    """Combustible, calor aceptado y O2 deben describir la misma masa quemada."""
    failures = []
    for name, rows in _rooms().items():
        last = rows[-1]
        fuel_mj = float(last["fuel_consumed_MJ_total"])
        if fuel_mj <= 0.0:
            continue
        heat_mj = float(last["hrr_kj_total"]) / 1000.0
        rel = abs(heat_mj - fuel_mj) / fuel_mj
        if rel > TOL_FUEL_HEAT_REL:
            failures.append(
                "%s: combustible %.1f MJ, calor aceptado %.1f MJ, desvío %.1f %%"
                % (name, fuel_mj, heat_mj, 100.0 * rel))
    assert not failures, "\n".join(failures)


@_needs_run
def test_no_layer_supplies_more_oxygen_than_it_holds_during_the_step():
    """Disponibilidad, no concentración.

    Una capa baja al 20,9 % pero de masa diminuta no puede alimentar el penacho.
    La masa de capa es la que usa el propio sistema de O2 —geométrica, con
    densidad constante de 1,2 kg/m3—, no la del solver térmico: esta prueba
    juzga al sistema con su propia regla.

    Falla si en algún paso el fuego pide a la capa baja más O2 del que esa capa
    contiene al empezar el paso.
    """
    failures = []
    for name, rows in _rooms().items():
        demand_kg = float(rows[-1]["o2_consumed_kg_total_all"])
        if demand_kg <= 0.0:
            continue
        # Lo que ese depósito ha podido contener en toda la corrida: lo que
        # tenía al empezar (sin capa caliente, la capa baja es la sala entera)
        # más lo que de verdad entró en la sala.
        initial_kg = float(rows[0]["o2"]) * float(rows[-1]["air_mass_kg"])
        received_kg = max(0.0, float(rows[-1]["o2_net_transport_kg_total"])) \
            + max(0.0, float(rows[-1]["o2_exterior_net_kg_total"]))
        supply_kg = initial_kg + received_kg
        if demand_kg > supply_kg + _tol(initial_kg):
            failures.append(
                "%s: el fuego declara haber consumido %.3f kg de O2, pero el depósito "
                "sólo ha podido reunir %.3f kg (inicial %.3f + recibido %.3f). "
                "Faltan %.3f kg. Una concentración alta en una capa delgada no es "
                "disponibilidad." % (name, demand_kg, supply_kg, initial_kg,
                                     received_kg, demand_kg - supply_kg))
    assert not failures, "\n".join(failures)


@_needs_run
def test_the_lower_layer_is_never_richer_than_what_feeds_it():
    """O2-2, enunciado sin llamarlo «doble cuenta».

    La capa baja de la sala que arde sólo recibe oxígeno de otras salas por el
    contraflujo del vano. No puede quedar por encima de la concentración de
    cualquiera de las salas que la alimentan: mezclar aire al 14 % no sostiene
    una capa al 20,9 %.

    Se compara contra el máximo de las demás salas, que es la cota superior más
    generosa posible para cualquier mezcla.
    """
    per = _rooms()
    burning = [n for n, rows in per.items()
               if float(rows[-1]["o2_consumed_kg_total_all"]) > 0.0]
    if not burning:
        # Control sin ignición: no hay contraflujo que juzgar. No es un defecto.
        pytest.skip("la corrida no tiene ninguna sala que arda")
    failures = []
    for name in burning:
        rows = per[name]
        others = [n for n in per if n != name]
        worst = None
        for index, row in enumerate(rows):
            if float(row["hrr_kw"]) <= 0.0:
                continue
            ceiling = max(float(per[n][index]["o2"]) for n in others
                          if index < len(per[n]))
            gap = float(row["o2_lower"]) - ceiling
            if gap > TOL_REL and (worst is None or gap > worst[0]):
                worst = (gap, row["time_s"], float(row["o2_lower"]), ceiling)
        if worst is not None:
            failures.append(
                "%s: peor violación en t=%s s — capa baja al %.4f y la sala más rica "
                "que puede alimentarla está al %.4f (exceso %.4f)"
                % (name, worst[1], worst[2], worst[3], worst[0]))
    assert not failures, "\n".join(failures)
