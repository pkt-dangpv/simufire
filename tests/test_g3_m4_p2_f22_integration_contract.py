"""Predeclared witnesses of the M4-P2 -> F2.2 integration contract; offline, no Godot."""

import hashlib
import json
from pathlib import Path

import pytest

from scripts.simulation import g3_m4_p2_f22_integration_oracle as io
from scripts.simulation import g3_m4_p2_gas_energy_eos_oracle as p2

ROOT = Path(__file__).resolve().parents[1]
PLAN_PATH = ROOT / "docs" / "validation" / "G3_M4_P2_F22_INTEGRATION_PLAN_2026-10-17.json"
PLAN_SHA256_LF = "5e8a59d63afcf3951ad49b2d2d19a4a61b5277c56e84bb7a61a5ed5370def873"
M4P2_PLAN = ROOT / "docs" / "validation" / "G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json"
DATA = PLAN_PATH.read_bytes().replace(b"\r\n", b"\n")
PLAN = json.loads(DATA.decode("utf-8"))
TOL = PLAN["tolerances"]
PROPS = PLAN["property_set_values"]["engine_equivalent_293_15"]
GAS = p2.Gas(cp=PROPS["cp"], R=PROPS["R"])
V, T_REF, P_EXT = 50.0, 293.15, 101325.0


def close(actual, expected, rel, floor=0.0):
    return abs(actual - expected) <= rel * abs(expected) + floor


def test_plan_is_the_predeclared_one_and_reuses_the_m4p2_plan():
    assert hashlib.sha256(DATA).hexdigest() == PLAN_SHA256_LF
    m4p2 = M4P2_PLAN.read_bytes().replace(b"\r\n", b"\n")
    assert hashlib.sha256(m4p2).hexdigest() == PLAN["m4p2_plan_sha256_lf"]
    assert json.loads(m4p2)["property_sets"]["engine_equivalent_293_15"]["R"] == PROPS["R"]
    assert PLAN["switch"]["default"] is False and PLAN["switch"]["requires"] == "pressure_network_solver_enabled"
    assert [w["id"] for w in PLAN["witnesses"]] == ["WI1", "WI2", "WI3", "WI4", "WI5", "WI6"]


@pytest.mark.parametrize("heat, parcels", [
    (10.0, []), (-5.0, []), (0.0, [(0.1, 300.0)]), (0.0, [(-0.2, 450.0)]),
    (5.0, [(0.1, 263.15), (-0.05, 400.0)]),
])
def test_wi1_first_law_is_gamma_times_the_f22_increment(heat, parcels):
    ratio = io.m4p2_dp_pa(GAS, heat, parcels, V) / io.f22_dp_pa(GAS, heat, parcels, V, T_REF)
    assert close(ratio, GAS.gamma, TOL["first_step_ratio_relative"])


def test_wi1_f22_eos_is_the_ideal_gas_identity():
    room = p2.make_room(GAS, 20.0, 2.5, P_EXT, {"upper": {"T_k": 400.0, "volume_m3": 20.0},
                                               "lower": {"T_k": T_REF, "volume_m3": 30.0}})
    mass = sum(room["layers"][z]["m"] for z in p2.LAYERS)
    energy = sum(io.e_from_u(GAS, room["layers"][z]["m"], room["layers"][z]["U"], T_REF) for z in p2.LAYERS)
    assert close(io.f22_pressure_abs_pa(GAS, mass, energy, V, T_REF), P_EXT, TOL["receipt_identity_relative"])


def test_wi2_leaky_room_starts_gamma_slow_and_reaches_the_same_quasi_steady_pressure():
    common = dict(volume_m3=V, t0_k=T_REF, p_ext_pa=P_EXT, heat_kw=10.0, leak_area_m2=5e-3,
                  t_end_s=30.0, dt_s=1e-3)
    m4p2 = io.leaky_room_history(GAS, "m4p2", **common)
    f22 = io.leaky_room_history(GAS, "f22", **common)
    assert close(m4p2[1][1] / f22[1][1], GAS.gamma, 0.01)
    assert close(m4p2[-1][1] / f22[-1][1], 1.0, TOL["quasi_steady_relative"])
    assert m4p2[-1][1] > 10.0


def test_wi3_adapter_round_trip_and_local_enthalpy():
    m, t_k = 36.0, 293.15
    u = m * GAS.cv * t_k
    e = io.e_from_u(GAS, m, u, T_REF)
    assert abs(e) <= TOL["energy_abs_floor_kj"] + TOL["receipt_identity_relative"] * u
    assert close(io.u_from_e(GAS, m, e, T_REF), u, TOL["receipt_identity_relative"])
    # heat, inflow at T, outflow at the donor T: absolute enthalpy behind (dm, dE)
    for d_mass, t_parcel, heat in ((0.0, 0.0, 7.0), (0.3, 263.15, 0.0), (-0.4, 400.0, 0.0)):
        d_energy = heat + d_mass * GAS.cp * (t_parcel - T_REF)
        expected = heat + d_mass * GAS.cp * t_parcel
        assert close(io.local_enthalpy_kj(GAS, d_mass, d_energy, T_REF), expected,
                     TOL["receipt_identity_relative"], TOL["energy_abs_floor_kj"])


def test_wi4_legacy_initial_mass_needs_the_fixed_R_inventory():
    for t_ref in (283.15, 303.15):
        assert abs(io.initial_gauge_pa(GAS, V, t_ref, P_EXT)) > 3000.0
        density = P_EXT / (GAS.R * 1000.0 * t_ref)
        assert abs(io.initial_gauge_pa(GAS, V, t_ref, P_EXT, density)) <= TOL["initial_gauge_abs_pa"]
    assert abs(io.initial_gauge_pa(GAS, V, 293.15, P_EXT)) <= TOL["initial_gauge_abs_pa"]


def _two_layer():
    return {"A": p2.make_room(GAS, 20.0, 2.5, P_EXT, {"upper": {"T_k": 400.0, "volume_m3": 20.0},
                                                     "lower": {"T_k": T_REF, "volume_m3": 30.0}})}


def test_wi5_one_step_as_two_events():
    exterior = {"T_k": T_REF, "Y_o2": 0.2314}
    rel = TOL["receipt_identity_relative"]
    whole, _ = p2.step(GAS, _two_layer(), {("A", "upper"): 7.0, ("A", "lower"): 3.0}, [], exterior)
    # Same 7/3 split in both events: exact composition (heater stays dt-independent).
    half, _ = p2.step(GAS, _two_layer(), {("A", "upper"): 3.5, ("A", "lower"): 1.5}, [], exterior)
    half, _ = p2.step(GAS, half, {("A", "upper"): 3.5, ("A", "lower"): 1.5}, [], exterior)
    for z in p2.LAYERS:
        assert close(half["A"]["layers"][z]["U"], whole["A"]["layers"][z]["U"], rel)
    # Different splits per event (local heat, then another owner): room U exact,
    # the layer split differs at first order and is not hidden.
    mixed, _ = p2.step(GAS, _two_layer(), {("A", "upper"): 4.0, ("A", "lower"): 1.0}, [], exterior)
    mixed, _ = p2.step(GAS, mixed, {("A", "upper"): 3.0, ("A", "lower"): 2.0}, [], exterior)
    total = lambda rooms: sum(rooms["A"]["layers"][z]["U"] for z in p2.LAYERS)
    assert close(total(mixed), total(whole), rel)
    split_difference = abs(mixed["A"]["layers"]["upper"]["U"] - whole["A"]["layers"]["upper"]["U"])
    assert split_difference > rel * total(whole)


def test_wi6_collective_scaling_drain_with_heat_is_rejected():
    rooms = _two_layer()
    lower = rooms["A"]["layers"]["lower"]
    wanted = 1.5 * lower["m"]
    factor = lower["m"] / wanted  # F2.2C: collective scale of an overdrawn (room, zone)
    with pytest.raises(p2.Rejection) as caught:
        p2.step(GAS, rooms, {("A", "upper"): 10.0},
                [{"id": "o", "kind": "boundary_out", "from": ("A", "lower"), "q": wanted * factor}],
                {"T_k": T_REF, "Y_o2": 0.2314})
    assert caught.value.reason == "layer_depleted_while_pressure_changes"
