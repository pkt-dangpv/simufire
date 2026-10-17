"""Independent audit of M4-P2 GD payloads with the Python oracle; never calls GD.

Recomputes every sampled receipt from its snapshot with
g3_m4_p2_gas_energy_eos_oracle.step, replays every oracle-expressible rejection,
checks final books against the Decimal closed forms and recomputes the C7/C9
convergence errors with the oracle. Tolerances come from the predeclared plan,
whose SHA-256 (LF text) is verified first. Naming differences are the ones
recorded in G3_M4_P2_GD_IMPLEMENTATION_2026-10-17.md section 1 (D1, D2).
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

from scripts.simulation import g3_m4_p2_gas_energy_eos_oracle as oracle

ROOT = Path(__file__).resolve().parents[2]
PLAN_PATH = ROOT / "docs" / "validation" / "G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json"
PLAN_SHA256_LF = "e20814fcbb03bd6ba8e6383c3dac6c3d4aa8069dc426f8a8f1e0346073a32eb5"
DEFAULT_EXTERIOR = {"T_k": 293.15, "Y_o2": 0.2314}
# D1/D2: one rejection class, two spellings.
REASON_CLASS = {"negative_value": "negative_mass", "inflow_financing_outflow": "overdraft_of_donor"}
REQUIRED_SAMPLE_CASES = ("C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10a", "C10b", "C13", "parcel snapshot")


def plan_bytes_lf() -> bytes:
    return PLAN_PATH.read_bytes().replace(b"\r\n", b"\n")


def load_plan() -> dict:
    data = plan_bytes_lf()
    if hashlib.sha256(data).hexdigest() != PLAN_SHA256_LF:
        raise RuntimeError("plan changed after it was predeclared")
    return json.loads(data.decode("utf-8"))


def _fail(message: str) -> None:
    raise RuntimeError(message)


def gas_of(book: dict) -> oracle.Gas:
    return oracle.Gas(cp=book["gas"]["cp_kj_kg_k"], R=book["gas"]["R_kj_kg_k"])


def to_rooms(book: dict) -> dict:
    rooms = {}
    for rid, room in book["rooms"].items():
        rooms[rid] = {
            "floor_area_m2": room["floor_area_m2"], "height_m": room["height_m"],
            "volume_m3": room["floor_area_m2"] * room["height_m"],
            "layers": {z: {"m": room["m_" + z], "U": room["U_" + z], "O": room["O_" + z]} for z in oracle.LAYERS},
        }
    return rooms


def to_inputs(event: dict) -> tuple[dict, list, dict]:
    heat: dict = {}
    for item in event["heat"]:
        key = (item["target"]["room"], item["target"]["zone"])
        heat[key] = heat.get(key, 0.0) + item["energy_kj"]  # D7: GD sums, oracle keys
    parcels = []
    exteriors = set()
    for packet in event["packets"]:
        parcel = {"id": packet["id"], "kind": packet["kind"], "q": packet["gas_kg"]}
        if packet["source"] is not None:
            parcel["from"] = (packet["source"]["room"], packet["source"]["zone"])
        if packet["target"] is not None:
            parcel["to"] = (packet["target"]["room"], packet["target"]["zone"])
        if packet["boundary"] is not None:
            exteriors.add((packet["boundary"]["T_k"], packet["boundary"]["Y"]))
        parcels.append(parcel)
    if len(exteriors) > 1:
        _fail("D6: the oracle takes one exterior per step")
    exterior = dict(DEFAULT_EXTERIOR)
    if exteriors:
        t_k, y = exteriors.pop()
        exterior = {"T_k": t_k, "Y_o2": y}
    return heat, parcels, exterior


def _within(actual: float, expected: float, rel: float, scale: float, floor: float) -> bool:
    return math.isfinite(actual) and abs(actual - expected) <= rel * abs(scale) + floor


def audit_receipt(receipt: dict, plan: dict) -> float:
    """Oracle recomputation of one accepted GD step; returns max relative difference."""
    tol = plan["tolerances"]
    rel, floors = tol["identity_relative"], tol["exact_abs_floor"]
    before, after = receipt["before"], receipt["after"]
    gas = gas_of(before)
    heat, parcels, exterior = to_inputs(receipt["event"])
    rooms, oracle_receipt = oracle.step(gas, to_rooms(before), heat, parcels, exterior)
    worst = 0.0
    for rid, room in rooms.items():
        u_scale = sum(room["layers"][z]["U"] for z in oracle.LAYERS)
        m_scale = sum(room["layers"][z]["m"] for z in oracle.LAYERS)
        for z in oracle.LAYERS:
            got = after["rooms"][rid]
            for field, scale, floor in (("U", u_scale, floors["energy_kj"]), ("m", m_scale, floors["mass_kg"]),
                                        ("O", m_scale, floors["mass_kg"])):
                expected = room["layers"][z][field]
                actual = got[f"{field}_{z}"]
                if not _within(actual, expected, rel, scale, floor):
                    _fail(f"oracle mismatch {rid}/{z}/{field}: GD {actual!r} oracle {expected!r}")
                if scale:
                    worst = max(worst, abs(actual - expected) / abs(scale))
            work = receipt["rooms"][rid]["layers"][z]["W_kj"]
            if not _within(work, oracle_receipt["work_kj"][(rid, z)], rel, u_scale, floors["energy_kj"]):
                _fail(f"oracle work mismatch {rid}/{z}")
    building_u = sum(sum(r["layers"][z]["U"] for z in oracle.LAYERS) for r in to_rooms(before).values())
    for gd_key, oracle_key in (("H_in_kj", "H_in"), ("H_out_kj", "H_out"),
                               ("mass_in_kg", "mass_in"), ("mass_out_kg", "mass_out")):
        if not _within(receipt["boundary"][gd_key], oracle_receipt["boundary"][oracle_key], rel, building_u,
                       floors["energy_kj"]):
            _fail(f"oracle boundary mismatch {gd_key}")
    return worst


def audit_rejection(item: dict) -> None:
    gas = gas_of(item["book"])
    heat, parcels, exterior = to_inputs(item["event"])
    try:
        oracle.step(gas, to_rooms(item["book"]), heat, parcels, exterior)
    except oracle.Rejection as exc:
        got = REASON_CLASS.get(exc.reason, exc.reason)
        want = REASON_CLASS.get(item["reason"], item["reason"])
        if got != want:
            _fail(f"rejection class differs for {item['name']}: GD {item['reason']} oracle {exc.reason}")
        return
    _fail(f"oracle accepted what GD rejected: {item['name']}")


def audit_finals(finals: list, plan: dict) -> int:
    cases = {case["id"]: case for case in plan["cases"]}
    tol = plan["tolerances"]
    exact, floors = tol["exact_relative"], tol["exact_abs_floor"]
    required = set()
    for cid in ("C1", "C2", "C3", "C4", "C5"):
        for props in cases[cid].get("property_sets", ["engine_equivalent_293_15"]):
            for dt in cases[cid]["dt_s"]:
                required.add((cid, props, dt))
    for cid in ("C6", "C8"):
        for dt in cases[cid]["dt_s"]:
            required.add((cid, "engine_equivalent_293_15", dt))
    seen = set()
    for item in finals:
        cid, props = item["case"], item["props"]
        # Godot's full-precision JSON prints 1/60 with 16 digits (2-3 ulp off):
        # identify the plan dt, never compare physics through this key.
        dt = _plan_dt(item["dt"], cases[cid].get("dt_s", []))
        seen.add((cid, props, dt))
        case = cases[cid]
        gas = gas_of(item["initial"])
        room0, room1 = item["initial"]["rooms"]["A"], item["final"]["rooms"]["A"]
        u0 = {z: room0["U_" + z] for z in oracle.LAYERS}
        volume = room0["floor_area_m2"] * room0["height_m"]
        if cid in ("C1", "C2", "C3", "C4"):
            expected = oracle.analytic_sealed_two_layer(gas, u0, case["heat_kw"], case["t_end_s"], volume)
        elif cid == "C5":
            expected = oracle.analytic_zero_net_exchange(gas, u0, case["heat_kw"], case["t_end_s"])
        elif cid == "C6":
            q = case["parcels_kg_s"][0]["rate"] * case["t_end_s"]
            t_u0 = room0["U_upper"] / (room0["m_upper"] * gas.cv)
            t_mix = (room0["m_upper"] * t_u0 + q * 293.15) / (room0["m_upper"] + q)
            expected = {"upper": (room0["m_upper"] + q) * gas.cv * t_mix,
                        "lower": (room0["m_lower"] - q) * gas.cv * 293.15}
        elif cid == "C8":
            inflow = case["parcels_kg_s"][0]
            expected = {"upper": 0.0, "lower": room0["U_lower"]
                        + inflow["rate"] * case["t_end_s"] * gas.cp * inflow["T_ext_k"]}
        else:
            continue
        for z in oracle.LAYERS:
            if not _within(room1["U_" + z], float(expected[z]), exact, float(expected[z]), floors["energy_kj"]):
                _fail(f"analytic mismatch {cid}/{props}/dt={dt}/{z}: {room1['U_' + z]!r} vs {expected[z]}")
    missing = required - seen
    if missing:
        _fail(f"finals missing: {sorted(missing)}")
    return len(finals)


def _plan_dt(value: float, planned: list) -> float:
    matches = [dt for dt in planned if abs(dt - value) <= 1e-12 * dt]
    if len(matches) != 1:
        _fail(f"dt={value!r} is not one of the planned steps {planned}")
    return matches[0]


def _oracle_c7_c9(plan: dict) -> dict:
    cases = {case["id"]: case for case in plan["cases"]}
    props = plan["property_sets"]["engine_equivalent_293_15"]
    gas = oracle.Gas(cp=props["cp"], R=props["R"])
    out = {"C7": {}, "C9": {}}
    c7 = cases["C7"]
    q_kw = c7["heat_kw"]["lower"]
    exact7 = float(oracle.analytic_isobaric_vented_temperature(gas, 293.15, q_kw, 101325.0, 50.0, c7["t_end_s"]))
    for dt in c7["dt_s"] + c7["report_dt_s"]:
        rooms = {"A": oracle.make_room(gas, 20.0, 2.5, 101325.0, {"lower": {"T_k": 293.15, "volume_m3": 50.0}})}
        u_target = 101325.0 * 50.0 / 1000.0 / (gas.gamma - 1.0)
        for i in range(round(c7["t_end_s"] / dt)):
            layer = rooms["A"]["layers"]["lower"]
            q = (layer["U"] + q_kw * dt - u_target) / (gas.gamma * layer["U"] / layer["m"])
            rooms, _ = oracle.step(gas, rooms, {("A", "lower"): q_kw * dt},
                                   [{"id": f"r{i}", "kind": "boundary_out", "from": ("A", "lower"), "q": q}],
                                   DEFAULT_EXTERIOR)
        t_final = oracle.derived(gas, rooms["A"])["layers"]["lower"]["T_k"]
        out["C7"][dt] = (abs(t_final - exact7) / exact7, t_final)
    c9 = cases["C9"]
    frac = c9["parcels_kg_s"][0]["rate_fraction_of_m0_per_s"]
    for dt in c9["dt_s"] + c9["report_dt_s"]:
        rooms = {"A": oracle.make_room(gas, 20.0, 2.5, 101325.0, {"lower": {"T_k": 293.15, "volume_m3": 50.0}})}
        m0 = rooms["A"]["layers"]["lower"]["m"]
        for i in range(round(c9["t_end_s"] / dt)):
            rooms, _ = oracle.step(gas, rooms, {}, [{"id": f"b{i}", "kind": "boundary_out", "from": ("A", "lower"),
                                                     "q": frac * m0 * dt}], DEFAULT_EXTERIOR)
        layer = rooms["A"]["layers"]["lower"]
        t_final = layer["U"] / (layer["m"] * gas.cv)
        exact9 = float(oracle.analytic_blowdown_temperature(gas, 293.15, layer["m"] / m0))
        out["C9"][dt] = (abs(t_final - exact9) / exact9, t_final)
    return out


def audit_convergence(convergence: dict, plan: dict) -> dict:
    cases = {case["id"]: case for case in plan["cases"]}
    tol = plan["tolerances"]
    lo, hi = tol["convergence_order_band"]
    reference = _oracle_c7_c9(plan)
    for cid in ("C7", "C9"):
        gd = convergence[cid]["rel_err"]
        series = [gd[_gd_key(dt, gd)] for dt in cases[cid]["dt_s"]]
        orders = [math.log2(series[i] / series[i + 1]) for i in range(len(series) - 1)]
        if any(not lo <= p <= hi for p in orders) or any(series[i] <= series[i + 1] for i in range(len(series) - 1)):
            _fail(f"{cid} order outside the predeclared band: {orders}")
        for dt in cases[cid]["dt_s"] + cases[cid]["report_dt_s"]:
            mine, t_oracle = reference[cid][dt]
            theirs = gd[_gd_key(dt, gd)]
            t_gd = convergence[cid]["T_final_k"][_gd_key(dt, convergence[cid]["T_final_k"])]
            # Same scheme: the final temperatures must agree on the plan's exact class.
            if not _within(t_gd, t_oracle, tol["exact_relative"], t_oracle, tol["exact_abs_floor"]["temperature_k"]):
                _fail(f"{cid} dt={dt}: GD T {t_gd!r} vs oracle {t_oracle!r} (errors {theirs!r}, {mine!r})")
    return {cid: {dt: err for dt, (err, _) in table.items()} for cid, table in reference.items()}


def _gd_key(dt: float, table: dict) -> str:
    matches = [key for key in table if abs(float(key) - dt) <= 1e-12 * dt]
    if len(matches) != 1:
        _fail(f"convergence key for dt={dt} not unique in {sorted(table)}")
    return matches[0]


def audit_payload(payload: dict, plan: dict | None = None) -> dict:
    plan = load_plan() if plan is None else plan
    if type(payload.get("checks")) is not int or payload["checks"] <= 0:
        _fail("no positive checks")
    if payload.get("failure_count") != 0 or payload.get("failures") != []:
        _fail("fixture reported failures")
    samples = payload.get("samples") or []
    for cid in REQUIRED_SAMPLE_CASES:
        if not any(s["name"] == cid or s["name"].startswith(cid + " ") for s in samples):
            _fail(f"no receipt sample for {cid}")
    worst = max(audit_receipt(s["receipt"], plan) for s in samples)
    rejections = payload.get("rejections") or []
    if len(rejections) < 10:
        _fail("too few oracle-auditable rejections")
    for item in rejections:
        audit_rejection(item)
    finals = audit_finals(payload.get("finals") or [], plan)
    reference = audit_convergence(payload.get("convergence") or {}, plan)
    return {"receipts": len(samples), "max_relative_difference_vs_oracle": worst,
            "rejections": len(rejections), "finals": finals,
            "oracle_convergence": {cid: {str(k): v for k, v in table.items()} for cid, table in reference.items()}}
