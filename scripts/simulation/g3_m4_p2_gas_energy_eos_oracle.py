"""M4-P2 independent oracle: inert calorically perfect gas, rigid rooms, two layers.

Pure Python reference for docs/validation/G3_M4_P2_GAS_ENERGY_EOS_CONTRACT_2026-10-17.md.
NOT an engine model: no Godot, no sim/ import, no flow law, no fuel. It applies
the discrete rule of contract section 5.1 in double precision and gives the
closed-form analytic solutions in Decimal, so a future GD module can be audited
without calling it.

State (basis physical_gas_energy_eos_v1), per room: volume_m3, floor_area_m2,
height_m and layers {"upper"|"lower": {"m": kg, "U": kJ absolute (u = cv*T), "O": kg O2}}.
"""

from __future__ import annotations

import copy
import math
from dataclasses import dataclass
from decimal import Decimal, localcontext

LAYERS = ("upper", "lower")
DECIMAL_DIGITS = 50
# |r - 1| below this uses the series of phi(r); the truncation error is < 1e-24.
PHI_SERIES_THRESHOLD = 1.0e-4


class Rejection(Exception):
    """A step the contract rejects; carries the named reason."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class Gas:
    cp: float
    R: float

    def __post_init__(self) -> None:
        for value in (self.cp, self.R):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                raise Rejection("non_finite_or_bool_number")
        if self.R <= 0.0:
            raise Rejection("R_not_positive")
        if self.cp <= self.R:
            raise Rejection("cp_not_greater_than_R")

    @property
    def cv(self) -> float:
        return self.cp - self.R

    @property
    def gamma(self) -> float:
        return self.cp / self.cv

    @property
    def k(self) -> float:
        return self.R / self.cp


def phi(r: float, k: float) -> float:
    """(r - r^k)/(r - 1), with phi(1) = 1 - k = 1/gamma."""
    eps = r - 1.0
    if abs(eps) >= PHI_SERIES_THRESHOLD:
        return (r - r ** k) / eps
    # r^k = sum C(k,n) eps^n  ->  phi = (1-k) - sum_{n>=2} C(k,n) eps^(n-1)
    total = 1.0 - k
    coeff = k
    for n in range(2, 7):
        coeff *= (k - n + 1) / n
        total -= coeff * eps ** (n - 1)
    return total


def _check_number(value, *, non_negative: bool = False) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise Rejection("non_finite_or_bool_number")
    if non_negative and value < 0.0:
        raise Rejection("negative_value")


def make_room(gas: Gas, floor_area_m2: float, height_m: float, p_abs_pa: float,
              layers: dict, y_o2: float = 0.2314) -> dict:
    """Room at a common pressure from per-layer {T_k, volume_m3}; T_k None = absent layer."""
    room = {
        "floor_area_m2": float(floor_area_m2),
        "height_m": float(height_m),
        "volume_m3": float(floor_area_m2) * float(height_m),
        "layers": {},
    }
    for z in LAYERS:
        spec = layers.get(z, {"T_k": None, "volume_m3": 0.0})
        if spec["T_k"] is None or spec["volume_m3"] == 0.0:
            room["layers"][z] = {"m": 0.0, "U": 0.0, "O": 0.0}
            continue
        m = p_abs_pa * spec["volume_m3"] / (gas.R * 1000.0 * spec["T_k"])
        room["layers"][z] = {"m": m, "U": m * gas.cv * spec["T_k"], "O": m * y_o2}
    return room


def validate_room(gas: Gas, room: dict) -> None:
    for key in ("floor_area_m2", "height_m", "volume_m3"):
        _check_number(room[key])
        if room[key] <= 0.0:
            raise Rejection("non_positive_volume")
    for z in LAYERS:
        layer = room["layers"][z]
        for key in ("m", "U", "O"):
            _check_number(layer[key])
        if layer["m"] < 0.0:
            raise Rejection("negative_mass")
        if layer["U"] < 0.0:
            raise Rejection("negative_internal_energy")
        if layer["m"] == 0.0 and layer["U"] != 0.0:
            raise Rejection("energy_without_mass")
        if layer["m"] > 0.0 and layer["U"] == 0.0:
            raise Rejection("mass_without_energy")
        if layer["O"] < 0.0 or layer["O"] > layer["m"]:
            raise Rejection("o2_out_of_range")


def derived(gas: Gas, room: dict) -> dict:
    """Pressure, temperatures, volumes and interface; never stored as state."""
    u_room = sum(room["layers"][z]["U"] for z in LAYERS)
    v = room["volume_m3"]
    p_abs = (gas.gamma - 1.0) * u_room / v * 1000.0  # kJ/m3 -> Pa
    out = {"p_abs_pa": p_abs, "U_room_kj": u_room, "layers": {}}
    for z in LAYERS:
        layer = room["layers"][z]
        if layer["m"] == 0.0:
            out["layers"][z] = {"T_k": None, "V_m3": 0.0, "H_kj": 0.0, "Y_o2": None}
            continue
        out["layers"][z] = {
            "T_k": layer["U"] / (layer["m"] * gas.cv),
            "V_m3": v * layer["U"] / u_room,
            "H_kj": gas.gamma * layer["U"],
            "Y_o2": layer["O"] / layer["m"],
        }
    out["interface_m"] = out["layers"]["lower"]["V_m3"] / room["floor_area_m2"]
    return out


def step(gas: Gas, rooms: dict, heat_kj: dict, parcels: list, exterior: dict) -> tuple[dict, dict]:
    """One event under contract section 5.1.

    heat_kj: {(room, layer): kJ over the step, signed}.
    parcels: [{"id", "kind": transfer|boundary_in|boundary_out, "from": (room, layer),
               "to": (room, layer), "q": kg}] with donations from the snapshot.
    exterior: {"T_k", "Y_o2"}.
    Returns (new rooms, receipt) or raises Rejection.
    """
    for room in rooms.values():
        validate_room(gas, room)
    _check_number(exterior["T_k"])
    if exterior["T_k"] <= 0.0:
        raise Rejection("non_positive_exterior_temperature")
    _check_number(exterior["Y_o2"])
    if not 0.0 <= exterior["Y_o2"] <= 1.0:
        raise Rejection("exterior_o2_fraction_out_of_range")

    seen = set()
    out_mass = {}
    in_mass = {}
    in_enthalpy = {}
    out_enthalpy = {}
    o2_delta = {}
    room_external = {rid: 0.0 for rid in rooms}
    boundary = {"mass_in": 0.0, "mass_out": 0.0, "H_in": 0.0, "H_out": 0.0}
    for (rid, z), q_heat in heat_kj.items():
        _check_number(q_heat)
        room_external[rid] += q_heat
    for parcel in parcels:
        if parcel["id"] in seen:
            raise Rejection("duplicate_event_or_parcel")
        seen.add(parcel["id"])
        q = parcel["q"]
        _check_number(q, non_negative=True)
        kind = parcel["kind"]
        if kind in ("transfer", "boundary_out"):
            src = parcel["from"]
            donor = rooms[src[0]]["layers"][src[1]]
            if donor["m"] == 0.0 and q > 0.0:
                raise Rejection("overdraft_of_donor")
            h_q = q * gas.gamma * donor["U"] / donor["m"] if q > 0.0 else 0.0
            o_q = q * donor["O"] / donor["m"] if q > 0.0 else 0.0
            out_mass[src] = out_mass.get(src, 0.0) + q
            out_enthalpy[src] = out_enthalpy.get(src, 0.0) + h_q
            o2_delta[src] = o2_delta.get(src, 0.0) - o_q
        else:
            h_q = q * gas.cp * exterior["T_k"]
            o_q = q * exterior["Y_o2"]
        if kind in ("transfer", "boundary_in"):
            dst = parcel["to"]
            in_mass[dst] = in_mass.get(dst, 0.0) + q
            in_enthalpy[dst] = in_enthalpy.get(dst, 0.0) + h_q
            o2_delta[dst] = o2_delta.get(dst, 0.0) + o_q
        if kind == "transfer" and parcel["from"][0] != parcel["to"][0]:
            room_external[parcel["from"][0]] -= h_q
            room_external[parcel["to"][0]] += h_q
        elif kind == "boundary_in":
            room_external[parcel["to"][0]] += h_q
            boundary["mass_in"] += q
            boundary["H_in"] += h_q
        elif kind == "boundary_out":
            room_external[parcel["from"][0]] -= h_q
            boundary["mass_out"] += q
            boundary["H_out"] += h_q
    # Donations come from the snapshot only: same-step inflow never finances outflow.
    for key, q_out in out_mass.items():
        if q_out > rooms[key[0]]["layers"][key[1]]["m"]:
            raise Rejection("overdraft_of_donor")

    new_rooms = copy.deepcopy(rooms)
    work = {}
    for rid, room in rooms.items():
        u0 = sum(room["layers"][z]["U"] for z in LAYERS)
        u1 = u0 + room_external[rid]
        if u1 <= 0.0:
            raise Rejection("room_energy_non_positive_after_step")
        r = u1 / u0
        for z in LAYERS:
            key = (rid, z)
            layer = room["layers"][z]
            q_heat = heat_kj.get(key, 0.0)
            q_out = out_mass.get(key, 0.0)
            m1 = layer["m"] - q_out + in_mass.get(key, 0.0)
            if m1 == 0.0 and q_heat != 0.0:
                raise Rejection("heat_into_absent_layer_without_mass")
            gained = q_heat + in_enthalpy.get(key, 0.0)
            if layer["m"] > 0.0:
                retained = (layer["m"] - q_out) / layer["m"]
            else:
                retained = 1.0
            if r == 1.0:
                u_z1 = layer["U"] * retained + gained / gas.gamma
            else:
                if layer["m"] > 0.0 and retained == 0.0:
                    raise Rejection("layer_depleted_while_pressure_changes")
                f = phi(r, gas.k)
                lost = out_enthalpy.get(key, 0.0)
                u_z1 = r ** gas.k * layer["U"] + f * (gained - lost)
            if m1 == 0.0:
                if u_z1 != 0.0:
                    raise Rejection("layer_depleted_while_pressure_changes")
            elif u_z1 <= 0.0:
                raise Rejection("layer_energy_negative_after_step")
            new_layer = new_rooms[rid]["layers"][z]
            new_layer["m"] = m1
            new_layer["U"] = u_z1
            new_layer["O"] = layer["O"] + o2_delta.get(key, 0.0)
            a_z = gained - out_enthalpy.get(key, 0.0)
            work[key] = u_z1 - layer["U"] - a_z
    receipt = {
        "room_external_kj": room_external,
        "work_kj": work,
        "boundary": boundary,
        "heat_kj": dict(heat_kj),
    }
    return new_rooms, receipt


# ---------------------------------------------------------------------------
# Closed-form analytic solutions (Decimal, contract section 8)
# ---------------------------------------------------------------------------

def _d(value) -> Decimal:
    return Decimal(value) if not isinstance(value, Decimal) else value


def analytic_sealed_two_layer(gas: Gas, u_layers0: dict, a_kw: dict, t_s, volume_m3) -> dict:
    """C1-C3: U_z(t) = s^k U_z0 + (a_z/a)(U - U0 s^k), s = U/U0, constant rates."""
    with localcontext() as ctx:
        ctx.prec = DECIMAL_DIGITS
        cp, R = _d(gas.cp), _d(gas.R)
        k = R / cp
        gm1 = R / (cp - R)
        u0 = sum(_d(u_layers0[z]) for z in LAYERS)
        a_total = sum(_d(a_kw.get(z, 0.0)) for z in LAYERS)
        u1 = u0 + a_total * _d(t_s)
        s_k = (u1 / u0) ** k
        out = {"U_room": u1, "p_abs_pa": gm1 * u1 / _d(volume_m3) * 1000}
        for z in LAYERS:
            if a_total == 0:
                raise ValueError("use analytic_zero_net_exchange for a = 0")
            out[z] = s_k * _d(u_layers0[z]) + _d(a_kw.get(z, 0.0)) / a_total * (u1 - u0 * s_k)
        return out


def analytic_zero_net_exchange(gas: Gas, u_layers0: dict, a_kw: dict, t_s) -> dict:
    """C5: total U constant, p constant, U_z changes by a_z t / gamma."""
    with localcontext() as ctx:
        ctx.prec = DECIMAL_DIGITS
        cp, R = _d(gas.cp), _d(gas.R)
        gamma = cp / (cp - R)
        return {z: _d(u_layers0[z]) + _d(a_kw.get(z, 0.0)) * _d(t_s) / gamma for z in LAYERS}


def analytic_isobaric_vented_temperature(gas: Gas, t0_k, q_kw, p_pa, volume_m3, t_s) -> Decimal:
    """C7: T = T0 exp((gamma-1) Q t / (gamma p V)) = T0 exp(R Q t / (cp p V))."""
    with localcontext() as ctx:
        ctx.prec = DECIMAL_DIGITS
        x = _d(gas.R) * _d(q_kw) * _d(t_s) / (_d(gas.cp) * _d(p_pa) / 1000 * _d(volume_m3))
        return _d(t0_k) * x.exp()


def analytic_blowdown_temperature(gas: Gas, t0_k, mass_ratio) -> Decimal:
    """C9: rigid adiabatic blowdown, T = T0 (m/m0)^(gamma-1)."""
    with localcontext() as ctx:
        ctx.prec = DECIMAL_DIGITS
        gm1 = _d(gas.R) / (_d(gas.cp) - _d(gas.R))
        return _d(t0_k) * _d(mass_ratio) ** gm1


def legacy_gas_constant(reference_temp_k: float) -> float:
    """Current engine R = 101325/(1.2 T_ref), kJ/(kg K): scenario dependent (W3)."""
    return 101325.0 / (1.2 * reference_temp_k) / 1000.0
