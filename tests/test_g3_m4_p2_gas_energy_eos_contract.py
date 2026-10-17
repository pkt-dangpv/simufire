"""M4-P2 design witnesses: gas/energy/EOS with a prescribed heater, no fuel.

Offline only: no Godot, no sim/ import, no engine run. The oracle applies the
discrete rule of the contract (section 5.1) and the cases, tolerances and
counterfactuals come from the predeclared plan, whose hash is checked first.
These tests prove design coherence, not engine or fire physics.
"""

import copy
import hashlib
import json
import math
from decimal import Decimal
from pathlib import Path

import pytest

from scripts.simulation import g3_m4_p2_gas_energy_eos_oracle as oracle

ROOT = Path(__file__).resolve().parents[1]
PLAN_PATH = ROOT / "docs" / "validation" / "G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json"
CONTRACT_PATH = ROOT / "docs" / "validation" / "G3_M4_P2_GAS_ENERGY_EOS_CONTRACT_2026-10-17.md"
PLAN_SHA256_LF = "e20814fcbb03bd6ba8e6383c3dac6c3d4aa8069dc426f8a8f1e0346073a32eb5"


def _plan_bytes_lf() -> bytes:
    return PLAN_PATH.read_bytes().replace(b"\r\n", b"\n")


PLAN = json.loads(_plan_bytes_lf().decode("utf-8"))
TOL = PLAN["tolerances"]
EXACT = TOL["exact_relative"]
IDENTITY = TOL["identity_relative"]
FLOOR = TOL["exact_abs_floor"]
CASES = {case["id"]: case for case in PLAN["cases"]}
P_EXT = 101325.0


def gas_of(name: str) -> oracle.Gas:
    props = PLAN["property_sets"][name]
    return oracle.Gas(cp=props["cp"], R=props["R"])


def room_of(gas: oracle.Gas, initial: str) -> dict:
    spec = PLAN["initial_states"][initial]
    geom = PLAN["geometry"][spec["room"]]
    return oracle.make_room(gas, geom["floor_area_m2"], geom["height_m"], spec["p_abs_pa"], spec["layers"])


def close(actual, expected, rel, floor) -> bool:
    actual, expected = float(actual), float(expected)
    return abs(actual - expected) <= max(rel * abs(expected), floor)


def run_heater(gas, initial, heat_kw, t_end, dt, step_fn=None):
    rooms = {"A": room_of(gas, initial)}
    n = round(t_end / dt)
    assert abs(n * dt - t_end) < 1e-9
    step_fn = step_fn or oracle.step
    receipts = []
    for _ in range(n):
        heat = {("A", z): q * dt for z, q in heat_kw.items()}
        rooms, receipt = step_fn(gas, rooms, heat, [], {"T_k": 293.15, "Y_o2": 0.2314})
        receipts.append(receipt)
    return rooms["A"], receipts


def check_identities(gas, room):
    d = oracle.derived(gas, room)
    v_sum = sum(d["layers"][z]["V_m3"] for z in oracle.LAYERS)
    assert close(v_sum, room["volume_m3"], IDENTITY, FLOOR["volume_m3"])
    rt = sum(room["layers"][z]["m"] * gas.R * 1000.0 * d["layers"][z]["T_k"]
             for z in oracle.LAYERS if room["layers"][z]["m"] > 0.0)
    assert close(d["p_abs_pa"] * room["volume_m3"], rt, IDENTITY, FLOOR["pressure_pa"])
    assert -FLOOR["length_m"] <= d["interface_m"] <= room["height_m"] + FLOOR["length_m"]
    return d


# --- plan integrity ---------------------------------------------------------

def test_plan_hash_is_the_predeclared_one():
    assert hashlib.sha256(_plan_bytes_lf()).hexdigest() == PLAN_SHA256_LF
    assert PLAN["status"] == "predeclared_before_any_evaluation"
    assert PLAN_SHA256_LF in CONTRACT_PATH.read_text(encoding="utf-8")


def test_plan_lists_every_case_rejection_and_mutant_of_the_contract():
    assert set(CASES) == {"C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9",
                          "C10a", "C10b", "C10c", "C11", "C13"}
    assert len(PLAN["gd_mutants_for_p2_implementation"]) == 16
    assert len(set(PLAN["gd_mutants_for_p2_implementation"])) == 16
    assert {w["id"] for w in PLAN["counterfactual_witnesses"]} == {"W1", "W2", "W3", "W4", "W5", "W6"}
    assert "layer_depleted_while_pressure_changes" in PLAN["rejections"]


# --- exact class: sealed heater cases ----------------------------------------

@pytest.mark.parametrize("props", ["engine_equivalent_293_15", "cfast_tn1889"])
@pytest.mark.parametrize("case_id", ["C1", "C2", "C3"])
def test_sealed_heater_matches_closed_form_at_every_step_size(case_id, props):
    case = CASES[case_id]
    gas = gas_of(props)
    room0 = room_of(gas, case["initial"])
    u0 = {z: room0["layers"][z]["U"] for z in oracle.LAYERS}
    expected = oracle.analytic_sealed_two_layer(gas, u0, case["heat_kw"], case["t_end_s"], room0["volume_m3"])
    finals = []
    for dt in case["dt_s"]:
        room, receipts = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], dt)
        d = check_identities(gas, room)
        for z in oracle.LAYERS:
            assert room["layers"][z]["m"] == room0["layers"][z]["m"]  # bitwise
            assert close(room["layers"][z]["U"], expected[z], EXACT, FLOOR["energy_kj"]), (z, dt)
        assert close(d["p_abs_pa"], expected["p_abs_pa"], EXACT, FLOOR["pressure_pa"])
        for receipt in receipts:
            w = receipt["work_kj"]
            assert abs(w[("A", "upper")] + w[("A", "lower")]) <= IDENTITY * float(expected["U_room"]) + FLOOR["energy_kj"]
        finals.append(room)
    for z in oracle.LAYERS:
        values = [r["layers"][z]["U"] for r in finals]
        assert max(values) - min(values) <= TOL["step_independence_relative"] * abs(values[0]) + FLOOR["energy_kj"]


def test_c1_pressure_rise_is_first_law_not_isobaric():
    case = CASES["C1"]
    gas = gas_of("engine_equivalent_293_15")
    room, _ = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], 1.0)
    dp = oracle.derived(gas, room)["p_abs_pa"] - P_EXT
    q_kj = case["heat_kw"]["lower"] * case["t_end_s"]
    assert close(dp, (gas.gamma - 1.0) * q_kj / room["volume_m3"] * 1000.0, EXACT, FLOOR["pressure_pa"])
    t1 = oracle.derived(gas, room)["layers"]["lower"]["T_k"]
    assert close(t1 - 293.15, q_kj / (room["layers"]["lower"]["m"] * gas.cv), 1e-9, FLOOR["temperature_k"])


def test_c2_lower_layer_is_compressed_isentropically_and_receives_work():
    case = CASES["C2"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    d0 = oracle.derived(gas, room0)
    room, receipts = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], 1.0)
    d1 = check_identities(gas, room)
    theta0 = d0["layers"]["lower"]["T_k"] * (P_EXT / d0["p_abs_pa"]) ** gas.k
    theta1 = d1["layers"]["lower"]["T_k"] * (P_EXT / d1["p_abs_pa"]) ** gas.k
    assert close(theta1, theta0, EXACT, FLOOR["temperature_k"])
    assert all(r["work_kj"][("A", "lower")] > 0.0 for r in receipts)
    assert d1["interface_m"] < d0["interface_m"]  # lower layer compressed


def test_c4_cooling_gives_negative_gauge_pressure_without_clipping():
    case = CASES["C4"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    u0 = {z: room0["layers"][z]["U"] for z in oracle.LAYERS}
    expected = oracle.analytic_sealed_two_layer(gas, u0, case["heat_kw"], case["t_end_s"], room0["volume_m3"])
    for dt in case["dt_s"]:
        room, _ = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], dt)
        p = oracle.derived(gas, room)["p_abs_pa"]
        assert p - P_EXT < -1000.0
        assert close(p, expected["p_abs_pa"], EXACT, FLOOR["pressure_pa"])


def test_c5_zero_net_internal_heat_moves_enthalpy_at_constant_pressure():
    case = CASES["C5"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    p0 = oracle.derived(gas, room0)["p_abs_pa"]
    u0 = {z: room0["layers"][z]["U"] for z in oracle.LAYERS}
    expected = oracle.analytic_zero_net_exchange(gas, u0, case["heat_kw"], case["t_end_s"])
    for dt in case["dt_s"]:
        room, _ = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], dt)
        assert close(oracle.derived(gas, room)["p_abs_pa"], p0, EXACT, FLOOR["pressure_pa"])
        for z in oracle.LAYERS:
            assert close(room["layers"][z]["U"], expected[z], EXACT, FLOOR["energy_kj"])
            dh = gas.gamma * (room["layers"][z]["U"] - u0[z])
            assert close(dh, case["heat_kw"][z] * case["t_end_s"], 1e-9, FLOOR["energy_kj"])


# --- exact class: parcels -----------------------------------------------------

def run_parcels(gas, rooms, parcel_rates, t_end, dt, heat_kw=None):
    n = round(t_end / dt)
    receipts = []
    for i in range(n):
        parcels = []
        for j, p in enumerate(parcel_rates):
            parcel = {"id": f"{i}-{j}", "kind": p["kind"], "q": p["rate"] * dt}
            if "from" in p:
                parcel["from"] = p["from"]
            if "to" in p:
                parcel["to"] = p["to"]
            parcels.append(parcel)
        heat = {key: q * dt for key, q in (heat_kw or {}).items()}
        rooms, receipt = oracle.step(gas, rooms, heat, parcels, {"T_k": 293.15, "Y_o2": 0.2314})
        receipts.append(receipt)
    return rooms, receipts


def test_c6_plume_is_isobaric_adiabatic_mixing():
    case = CASES["C6"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    d0 = oracle.derived(gas, room0)
    rate = case["parcels_kg_s"][0]["rate"]
    q_tot = rate * case["t_end_s"]
    up0 = room0["layers"]["upper"]
    t_mix = (up0["m"] * d0["layers"]["upper"]["T_k"] + q_tot * 293.15) / (up0["m"] + q_tot)
    o_upper = up0["O"] + q_tot * room0["layers"]["lower"]["O"] / room0["layers"]["lower"]["m"]
    for dt in case["dt_s"]:
        rooms, _ = run_parcels(gas, {"A": copy.deepcopy(room0)},
                               [{"kind": "transfer", "from": ("A", "lower"), "to": ("A", "upper"), "rate": rate}],
                               case["t_end_s"], dt)
        d = check_identities(gas, rooms["A"])
        assert close(d["p_abs_pa"], d0["p_abs_pa"], EXACT, FLOOR["pressure_pa"])
        assert close(d["layers"]["lower"]["T_k"], 293.15, EXACT, FLOOR["temperature_k"])
        assert close(d["layers"]["upper"]["T_k"], t_mix, EXACT, FLOOR["temperature_k"])
        assert close(rooms["A"]["layers"]["upper"]["O"], o_upper, EXACT, FLOOR["mass_kg"])


def test_c8_adiabatic_filling_heats_the_gas_above_the_exterior():
    case = CASES["C8"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    p = case["parcels_kg_s"][0]
    q_tot = p["rate"] * case["t_end_s"]
    u_exp = room0["layers"]["lower"]["U"] + q_tot * gas.cp * p["T_ext_k"]
    m_exp = room0["layers"]["lower"]["m"] + q_tot
    for dt in case["dt_s"]:
        rooms, _ = run_parcels(gas, {"A": copy.deepcopy(room0)},
                               [{"kind": "boundary_in", "to": ("A", "lower"), "rate": p["rate"]}],
                               case["t_end_s"], dt)
        layer = rooms["A"]["layers"]["lower"]
        assert close(layer["U"], u_exp, EXACT, FLOOR["energy_kj"])
        assert close(layer["m"], m_exp, EXACT, FLOOR["mass_kg"])
        assert oracle.derived(gas, rooms["A"])["layers"]["lower"]["T_k"] > p["T_ext_k"] + 1.0


def test_c10a_upper_layer_birth_from_plume_parcel():
    case = CASES["C10a"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    assert room0["layers"]["upper"]["m"] == 0.0
    rate = case["parcels_kg_s"][0]["rate"]
    for dt in case["dt_s"]:
        rooms, _ = run_parcels(gas, {"A": copy.deepcopy(room0)},
                               [{"kind": "transfer", "from": ("A", "lower"), "to": ("A", "upper"), "rate": rate}],
                               case["t_end_s"], dt)
        d = check_identities(gas, rooms["A"])
        assert close(d["p_abs_pa"], P_EXT, EXACT, FLOOR["pressure_pa"])
        assert close(d["layers"]["upper"]["T_k"], 293.15, EXACT, FLOOR["temperature_k"])


def test_c10b_full_depletion_at_constant_pressure_leaves_exact_zero():
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, CASES["C10b"]["initial"])
    p0 = oracle.derived(gas, room0)["p_abs_pa"]
    parcel = {"id": "all", "kind": "transfer", "from": ("A", "lower"), "to": ("A", "upper"),
              "q": room0["layers"]["lower"]["m"]}
    rooms, _ = oracle.step(gas, {"A": room0}, {}, [parcel], {"T_k": 293.15, "Y_o2": 0.2314})
    lower = rooms["A"]["layers"]["lower"]
    assert lower == {"m": 0.0, "U": 0.0, "O": 0.0}
    d = check_identities(gas, rooms["A"])
    assert d["layers"]["lower"]["T_k"] is None
    assert close(d["p_abs_pa"], p0, EXACT, FLOOR["pressure_pa"])


def test_c10c_depletion_with_pressure_change_is_rejected_without_state_change():
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, CASES["C10c"]["initial"])
    rooms = {"A": room0}
    snapshot = copy.deepcopy(rooms)
    parcel = {"id": "all", "kind": "transfer", "from": ("A", "lower"), "to": ("A", "upper"),
              "q": room0["layers"]["lower"]["m"]}
    with pytest.raises(oracle.Rejection) as err:
        oracle.step(gas, rooms, {("A", "upper"): 10.0}, [parcel], {"T_k": 293.15, "Y_o2": 0.2314})
    assert err.value.reason == CASES["C10c"]["expected"].split(":", 1)[1]
    assert rooms == snapshot


def test_c10c_depleted_and_refilled_layer_is_still_rejected_when_pressure_changes():
    # Contract 5.1: the first-order residual would hide inside the new mass.
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, CASES["C10c"]["initial"])
    rooms = {"A": room0}
    snapshot = copy.deepcopy(rooms)
    parcels = [{"id": "all", "kind": "transfer", "from": ("A", "lower"), "to": ("A", "upper"),
                "q": room0["layers"]["lower"]["m"]},
               {"id": "refill", "kind": "boundary_in", "to": ("A", "lower"), "q": 1.0}]
    with pytest.raises(oracle.Rejection) as err:
        oracle.step(gas, rooms, {("A", "upper"): 10.0}, parcels, {"T_k": 293.15, "Y_o2": 0.2314})
    assert err.value.reason == "layer_depleted_while_pressure_changes"
    assert rooms == snapshot


def test_c11_gas_constant_does_not_depend_on_the_scenario():
    gas = gas_of("engine_equivalent_293_15")
    for ambient in CASES["C11"]["ambient_k"]:
        room = oracle.make_room(gas, 20.0, 2.5, P_EXT, {"lower": {"T_k": ambient, "volume_m3": 50.0}})
        assert oracle.derived(gas, room)["layers"]["lower"]["T_k"] == pytest.approx(ambient, rel=1e-14)
    assert gas.R == PLAN["property_sets"]["engine_equivalent_293_15"]["R"]
    legacy = [oracle.legacy_gas_constant(t) for t in CASES["C11"]["ambient_k"]]
    assert (max(legacy) - min(legacy)) / legacy[1] > 0.03  # W3: the legacy R moves


def test_c13_building_balances_close_each_step():
    case = CASES["C13"]
    gas = gas_of("engine_equivalent_293_15")
    rooms0 = {"A": room_of(gas, "two_layer_hot_upper"), "B": room_of(gas, "room_B_ambient")}
    rate = case["parcels_kg_s"][0]["rate"]
    for dt in case["dt_s"]:
        rooms = copy.deepcopy(rooms0)
        n = round(case["t_end_s"] / dt)
        for i in range(n):
            m_before = sum(r["layers"][z]["m"] for r in rooms.values() for z in oracle.LAYERS)
            u_before = sum(r["layers"][z]["U"] for r in rooms.values() for z in oracle.LAYERS)
            rooms, receipt = oracle.step(
                gas, rooms, {("A", "upper"): 10.0 * dt},
                [{"id": f"t{i}", "kind": "transfer", "from": ("A", "upper"), "to": ("B", "lower"), "q": rate * dt}],
                {"T_k": 293.15, "Y_o2": 0.2314})
            m_after = sum(r["layers"][z]["m"] for r in rooms.values() for z in oracle.LAYERS)
            u_after = sum(r["layers"][z]["U"] for r in rooms.values() for z in oracle.LAYERS)
            assert close(m_after, m_before, IDENTITY, FLOOR["mass_kg"])
            assert close(u_after - u_before, 10.0 * dt, IDENTITY * u_before / (10.0 * dt), FLOOR["energy_kj"])
            ext = receipt["room_external_kj"]
            assert close(ext["A"] + ext["B"], 10.0 * dt, IDENTITY * u_before / (10.0 * dt), FLOOR["energy_kj"])
            for room in rooms.values():
                check_identities(gas, room)


# --- convergence class --------------------------------------------------------

def run_c7(gas, dt, t_end, q_kw):
    rooms = {"A": room_of(gas, "one_layer_ambient")}
    v = rooms["A"]["volume_m3"]
    u_target = P_EXT * v / 1000.0 / (gas.gamma - 1.0)
    for i in range(round(t_end / dt)):
        layer = rooms["A"]["layers"]["lower"]
        h0 = gas.gamma * layer["U"] / layer["m"]
        q = (layer["U"] + q_kw * dt - u_target) / h0  # harness-side isobaric relief
        u_before = layer["U"]
        rooms, receipt = oracle.step(gas, rooms, {("A", "lower"): q_kw * dt},
                                     [{"id": f"r{i}", "kind": "boundary_out", "from": ("A", "lower"), "q": q}],
                                     {"T_k": 293.15, "Y_o2": 0.2314})
        d = oracle.derived(gas, rooms["A"])
        assert close(d["p_abs_pa"], P_EXT, IDENTITY, FLOOR["pressure_pa"])
        du = rooms["A"]["layers"]["lower"]["U"] - u_before
        assert abs(du - (q_kw * dt - receipt["boundary"]["H_out"])) <= IDENTITY * u_before + FLOOR["energy_kj"]
    return oracle.derived(gas, rooms["A"])["layers"]["lower"]["T_k"]


def run_c9(gas, dt, t_end, frac_rate, debit_internal_energy=False):
    rooms = {"A": room_of(gas, "one_layer_ambient")}
    m0 = rooms["A"]["layers"]["lower"]["m"]
    for i in range(round(t_end / dt)):
        q = frac_rate * m0 * dt
        if debit_internal_energy:  # W6 counterfactual: outflow takes u, not h
            layer = rooms["A"]["layers"]["lower"]
            u_spec = layer["U"] / layer["m"]
            layer = {"m": layer["m"] - q, "U": layer["U"] - q * u_spec, "O": layer["O"]}
            rooms = {"A": {**rooms["A"], "layers": {"upper": rooms["A"]["layers"]["upper"], "lower": layer}}}
            continue
        u_before = rooms["A"]["layers"]["lower"]["U"]
        rooms, receipt = oracle.step(gas, rooms, {},
                                     [{"id": f"b{i}", "kind": "boundary_out", "from": ("A", "lower"), "q": q}],
                                     {"T_k": 293.15, "Y_o2": 0.2314})
        du = rooms["A"]["layers"]["lower"]["U"] - u_before
        assert abs(du + receipt["boundary"]["H_out"]) <= IDENTITY * u_before + FLOOR["energy_kj"]
    layer = rooms["A"]["layers"]["lower"]
    return layer["U"] / (layer["m"] * gas.cv), layer["m"] / m0


def observed_orders(errors):
    return [math.log2(errors[i] / errors[i + 1]) for i in range(len(errors) - 1)]


def test_c7_vented_heater_converges_first_order_to_the_exponential():
    case = CASES["C7"]
    gas = gas_of("engine_equivalent_293_15")
    q_kw = case["heat_kw"]["lower"]
    exact = float(oracle.analytic_isobaric_vented_temperature(gas, 293.15, q_kw, P_EXT, 50.0, case["t_end_s"]))
    errors = [abs(run_c7(gas, dt, case["t_end_s"], q_kw) - exact) / exact for dt in case["dt_s"]]
    assert all(errors[i] > errors[i + 1] for i in range(len(errors) - 1))
    lo, hi = TOL["convergence_order_band"]
    assert all(lo <= p <= hi for p in observed_orders(errors)), observed_orders(errors)


def test_c9_blowdown_converges_first_order_to_the_isentrope():
    case = CASES["C9"]
    gas = gas_of("engine_equivalent_293_15")
    frac = case["parcels_kg_s"][0]["rate_fraction_of_m0_per_s"]
    errors = []
    for dt in case["dt_s"]:
        t_end_k, ratio = run_c9(gas, dt, case["t_end_s"], frac)
        exact = float(oracle.analytic_blowdown_temperature(gas, 293.15, ratio))
        errors.append(abs(t_end_k - exact) / exact)
    assert all(errors[i] > errors[i + 1] for i in range(len(errors) - 1))
    lo, hi = TOL["convergence_order_band"]
    assert all(lo <= p <= hi for p in observed_orders(errors)), observed_orders(errors)


# --- rejections ---------------------------------------------------------------

@pytest.mark.parametrize("cp, R, reason", [
    (0.28, 0.288, "cp_not_greater_than_R"),
    (1.0, 0.0, "R_not_positive"),
    (float("nan"), 0.288, "non_finite_or_bool_number"),
    (True, 0.288, "non_finite_or_bool_number"),
])
def test_invalid_gas_properties_are_rejected(cp, R, reason):
    with pytest.raises(oracle.Rejection) as err:
        oracle.Gas(cp=cp, R=R)
    assert err.value.reason == reason


def _base():
    gas = gas_of("engine_equivalent_293_15")
    return gas, {"A": room_of(gas, "two_layer_hot_upper")}


@pytest.mark.parametrize("mutate, heat, parcels, reason", [
    (lambda r: r["A"]["layers"]["lower"].update(U=-1.0), {}, [], "negative_internal_energy"),
    (lambda r: r["A"]["layers"]["lower"].update(m=0.0), {}, [], "energy_without_mass"),
    (None, {}, [{"id": "x", "kind": "boundary_out", "from": ("A", "lower"), "q": 1e9}], "overdraft_of_donor"),
    (None, {}, [{"id": "x", "kind": "boundary_in", "to": ("A", "lower"), "q": 1.0},
                {"id": "x", "kind": "boundary_in", "to": ("A", "lower"), "q": 1.0}], "duplicate_event_or_parcel"),
    (None, {("A", "upper"): -1e9}, [], "room_energy_non_positive_after_step"),
])
def test_invalid_steps_are_rejected_without_touching_the_input(mutate, heat, parcels, reason):
    gas, rooms = _base()
    if mutate:
        mutate(rooms)
    snapshot = copy.deepcopy(rooms)
    with pytest.raises(oracle.Rejection) as err:
        oracle.step(gas, rooms, heat, parcels, {"T_k": 293.15, "Y_o2": 0.2314})
    assert err.value.reason == reason
    assert rooms == snapshot


def test_inflow_in_the_same_step_cannot_finance_an_outflow():
    gas, rooms = _base()
    m_lower = rooms["A"]["layers"]["lower"]["m"]
    parcels = [{"id": "in", "kind": "boundary_in", "to": ("A", "lower"), "q": 5.0},
               {"id": "out", "kind": "boundary_out", "from": ("A", "lower"), "q": m_lower + 1.0}]
    with pytest.raises(oracle.Rejection) as err:
        oracle.step(gas, rooms, {}, parcels, {"T_k": 293.15, "Y_o2": 0.2314})
    assert err.value.reason == "overdraft_of_donor"


# --- counterfactual witnesses (each must fail its case) -----------------------

def test_w1_enthalpy_without_vdp_divides_the_sealed_rise_by_gamma():
    gas = gas_of("engine_equivalent_293_15")
    case = CASES["C1"]
    room0 = room_of(gas, case["initial"])
    m = room0["layers"]["lower"]["m"]
    q_kj = case["heat_kw"]["lower"] * case["t_end_s"]
    # F2.2A: E_sensible += Q ; p = (R/V)(M T_ref + E/cp) ; T = T_ref + E/(m cp)
    dp_f22 = gas.R * 1000.0 / room0["volume_m3"] * (q_kj / gas.cp)
    dt_f22 = q_kj / (m * gas.cp)
    room, _ = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], 1.0)
    d = oracle.derived(gas, room)
    dp_ok = d["p_abs_pa"] - P_EXT
    dt_ok = d["layers"]["lower"]["T_k"] - 293.15
    assert not close(dp_f22, dp_ok, EXACT, FLOOR["pressure_pa"])
    assert dp_ok / dp_f22 == pytest.approx(gas.gamma, rel=1e-12)
    assert dt_ok / dt_f22 == pytest.approx(gas.gamma, rel=1e-9)


def test_w2_literal_gamma_fails_c1_with_the_engine_property_set():
    gas = gas_of("engine_equivalent_293_15")
    q_kj = 600.0
    assert not close((1.4 - 1.0) * q_kj / 50.0, (gas.gamma - 1.0) * q_kj / 50.0, EXACT, 1e-9)


def _rescale_step(gas, rooms, heat, parcels, exterior):
    """W4: U_z* = U_z0 + A_z/gamma, then a common factor to reach U1."""
    new = copy.deepcopy(rooms)
    for rid, room in rooms.items():
        u0 = sum(room["layers"][z]["U"] for z in oracle.LAYERS)
        u1 = u0 + sum(q for (r, _), q in heat.items() if r == rid)
        star = {z: room["layers"][z]["U"] + heat.get((rid, z), 0.0) / gas.gamma for z in oracle.LAYERS}
        factor = u1 / sum(star.values())
        for z in oracle.LAYERS:
            new[rid]["layers"][z]["U"] = star[z] * factor
    return new, {"work_kj": {(rid, z): 0.0 for rid in rooms for z in oracle.LAYERS}}


def _uncompressed_step(gas, rooms, heat, parcels, exterior):
    """W5: the passive layer keeps its energy; the heated one takes the rest."""
    new = copy.deepcopy(rooms)
    for rid, room in rooms.items():
        u1 = sum(room["layers"][z]["U"] for z in oracle.LAYERS) + sum(heat.values())
        new[rid]["layers"]["upper"]["U"] = u1 - room["layers"]["lower"]["U"]
    return new, {"work_kj": {(rid, z): 0.0 for rid in rooms for z in oracle.LAYERS}}


def test_w4_proportional_rescale_fails_c2():
    case = CASES["C2"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    u0 = {z: room0["layers"][z]["U"] for z in oracle.LAYERS}
    expected = oracle.analytic_sealed_two_layer(gas, u0, case["heat_kw"], case["t_end_s"], 50.0)
    lowers = []
    for dt in (1.0, 60.0):
        room, _ = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], dt, _rescale_step)
        lowers.append(room["layers"]["lower"]["U"])
        assert not close(room["layers"]["lower"]["U"], expected["lower"], EXACT, FLOOR["energy_kj"])
    assert abs(lowers[0] - lowers[1]) > TOL["step_independence_relative"] * lowers[0]


def test_w5_uncompressed_passive_layer_passes_volume_closure_but_fails_isentrope():
    case = CASES["C2"]
    gas = gas_of("engine_equivalent_293_15")
    room0 = room_of(gas, case["initial"])
    room, _ = run_heater(gas, case["initial"], case["heat_kw"], case["t_end_s"], 1.0, _uncompressed_step)
    check_identities(gas, room)  # closure is an identity: it cannot see the defect
    d0, d1 = oracle.derived(gas, room0), oracle.derived(gas, room)
    theta0 = d0["layers"]["lower"]["T_k"] * (P_EXT / d0["p_abs_pa"]) ** gas.k
    theta1 = d1["layers"]["lower"]["T_k"] * (P_EXT / d1["p_abs_pa"]) ** gas.k
    assert not close(theta1, theta0, EXACT, FLOOR["temperature_k"])


def test_w6_outflow_debiting_internal_energy_fails_c9():
    case = CASES["C9"]
    gas = gas_of("engine_equivalent_293_15")
    frac = case["parcels_kg_s"][0]["rate_fraction_of_m0_per_s"]
    errors = []
    for dt in case["dt_s"]:
        t_end_k, ratio = run_c9(gas, dt, case["t_end_s"], frac, debit_internal_energy=True)
        exact = float(oracle.analytic_blowdown_temperature(gas, 293.15, ratio))
        errors.append(abs(t_end_k - exact) / exact)
    assert min(errors) > 0.05  # stays at the initial temperature: no convergence


def test_oracle_has_no_engine_or_machine_dependency():
    source = (ROOT / "scripts" / "simulation" / "g3_m4_p2_gas_energy_eos_oracle.py").read_text(encoding="utf-8")
    for forbidden in ("import godot", "res://", "subprocess", "C:\\", "F:\\", "sim.core", "open("):
        assert forbidden not in source
    assert Decimal(1)  # Decimal-only analytic references, no third-party packages
