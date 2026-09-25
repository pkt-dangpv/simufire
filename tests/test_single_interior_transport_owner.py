"""P3: un unico propietario del gas que cruza una abertura interior.

Con `pressure_network_solver_enabled = true`, la red de presion mueve masa,
entalpia y especies por cada abertura en los dos sentidos. ThermalSystem volvia
a aplicar la salida de la capa caliente por la misma abertura
(`canonical_doorway_upper`), y su siembra de capa alta por radiacion creaba masa
que, con la red, nada reconcilia. Detalle y libro por abertura en
docs/validation/E1_O2_BASE_DE_MASA_2026-09-25.md §7.

Estaticas: fijan donde vive cada guarda. Dinamica: el validador Godot, que falla
con el segundo propietario reintroducido (mutacion M1), con la siembra sin
donante (M2) y con la siembra que mueve gas sin sus especies ni su O2 (M3), y
pasa con la red apagada byte a byte igual que antes.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot

ROOT = Path(__file__).resolve().parents[1]
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
VALIDATOR_PATH = ROOT / "tools/validate_single_interior_transport_owner.gd"
VALIDATOR = "res://tools/validate_single_interior_transport_owner.gd"
PASS_TOKEN = "SINGLE INTERIOR TRANSPORT OWNER VALIDATION PASS"
CHECK_PRODUCT = (ROOT / "scripts/check_product.py").read_text(encoding="utf-8")

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def _interior_opening_loop() -> str:
    step = _function(THERMAL, "step")
    start = step.index("for op in building.get_openings():")
    return step[start:step.index("_flush_contaminant_deltas(building)", start)]


def test_the_network_owns_the_gas_that_crosses_an_interior_opening():
    loop = _interior_opening_loop()
    guard = "if authoritative_transport_enabled:\n\t\t\tcontinue"
    assert guard in loop, "ThermalSystem must leave interior gas transport to the network"
    at = loop.index(guard)
    # Todo lo que mueve gas por la abertura va DESPUES de la guarda.
    for mover in ("_apply_doorway_thermal_counterflow(",
                  "hot_room.upper_gas_kg = maxf(0.0, hot_room.upper_gas_kg - gas_moved_kg)",
                  "_transfer_hot_gas_contaminants(",
                  "_apply_canonical_doorway_exchange("):
        assert mover in loop, mover
        assert loop.index(mover) > at, f"{mover} escapes the network guard"
    # Y el calor sin gas va ANTES: no se pierde con la red encendida. Los dos
    # intercambios de fondo ya se apartan solos de la red (F2.2C).
    for heat_only in ("_apply_stairwell_heat_bridge(",
                      "_apply_interior_background_heat_exchange(",
                      "_apply_outside_assisted_background_heat_exchange("):
        assert loop.index(heat_only) < at, f"{heat_only} must stay outside the guard"


def test_radiation_through_openings_keeps_its_heat_and_seeds_without_creating_mass():
    radiation = _function(THERMAL, "_step_radiation_openings")
    # La radiacion es calor sin gas: ninguna guarda de red la apaga.
    assert "authoritative_transport_enabled:\n\t\t\tcontinue" not in radiation
    assert "src.upper_energy_kj = maxf(0.0, src.upper_energy_kj - energy_kj)" in radiation
    # Con la red, la capa minima sale de la capa baja de la misma sala.
    seeded = "if tgt.upper_gas_kg <= 0.0001 and authoritative_transport_enabled:\n" \
             "\t\t\t# P3:"
    assert seeded in radiation
    branch = radiation[radiation.index(seeded):radiation.index("elif tgt.upper_gas_kg <= 0.0001:")]
    assert "_seed_upper_layer_as_one_packet(tgt, ambient_c)" in branch
    assert "tgt.upper_gas_kg =" not in branch
    # El seed conservativo del solver de zonas es el que usa ese helper.
    minimal = _function(THERMAL, "_ensure_minimal_upper_gas")
    assert "_zone_fire_solver.transfer_lower_to_upper(" in minimal


def test_the_radiation_seed_moves_one_packet_of_lower_gas():
    """P3b: masa, entalpia, especies zonales y O2 describen el MISMO paquete.

    La regla es la de la red (`_bundle_for_source`): especie zonal por fraccion
    de masa de la zona donante, O2 como fraccion por capa. Las especies que
    solo existen como total de sala no se tocan.
    """
    packet = _function(THERMAL, "_seed_upper_layer_as_one_packet")
    assert "_ensure_minimal_upper_gas(room, ambient_c)" in packet
    # Lo que dono de verdad la capa baja, no lo que se pidio.
    assert "var moved_kg: float = lower_before_kg - maxf(0.0, room.lower_gas_kg)" in packet
    assert "var share: float = clampf(moved_kg / lower_before_kg, 0.0, 1.0)" in packet
    assert 'for species in ["co", "co2", "hcn"]:' in packet
    assert "upper_kg + (total_kg - upper_kg) * share" in packet
    # Ningun total de sala cambia: solo la parte alta.
    assert 'room.set("%s_kg" % species' not in packet
    code = "\n".join(l for l in packet.splitlines() if not l.lstrip().startswith("#"))
    for global_species in ("smoke_kg", "hcl_kg", "acrolein_kg", "formaldehyde_kg"):
        assert global_species not in code, global_species
    assert "room.o2_upper = (room.o2_upper * upper_before_kg + room.o2_lower * moved_kg) / upper_after_kg" in packet
    assert "room.o2_lower =" not in packet
    network = (ROOT / "sim/core/PressureNetworkTransportSystem.gd").read_text(encoding="utf-8")
    bundle = network.split("func _bundle_for_source(", 1)[1].split("\nfunc ", 1)[0]
    assert "var zone_fraction: float = mass_kg / zone_mass_kg" in bundle


def test_the_validator_pins_the_off_route_and_is_registered():
    source = VALIDATOR_PATH.read_text(encoding="utf-8")
    assert 'const OFF_FINGERPRINT: String = "__PENDING__"' not in source
    # Re-fijada por la fase "ruta normal": el acarreo de gas caliente ya no saca
    # CO2 de la capa baja del origen (P3 la habia fijado en 4f375edf...).
    assert 'const OFF_FINGERPRINT: String = "a5ec9b8d' in source
    for case in ("_o1_open_door_on", "_o2_vertical_hole_on", "_o3_closed_door_on",
                 "_o4_open_door_off", "_o5_radiation_seed_on",
                 "_o6_ordinary_scenario_switches", "_o7_no_radiation_control_on"):
        assert f"\t{case}()" in source, case
    assert "\t_o5b_seed_is_one_packet()" in source
    for scenario in ("compact_apartment_reference", "preset_simple_house",
                     "long_hallway_reference", "preset_two_storey_house",
                     "two_storey_reference"):
        assert f'"{scenario}"' in source, scenario
    assert VALIDATOR in CHECK_PRODUCT
    assert PASS_TOKEN in CHECK_PRODUCT


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def test_validator_passes():
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", VALIDATOR],
        timeout_s=600, allowed_exit_codes=(0,),
    )
    output = (completed.stdout or "") + (completed.stderr or "")
    assert PASS_TOKEN in output
    assert "SCRIPT ERROR" not in output
    assert "Parse Error" not in output
