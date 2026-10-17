"""M4-P2 -> F2.2 integration oracle: the two room energy laws side by side.

Pure Python, no Godot, no sim/ import. Reproduces, from the documented F2.2A/B
equations (docs/PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md section 14.1 and
Phase3CoupledPressureSolver residual), how the live network advances a room,
and compares it with the M4-P2 rule (g3_m4_p2_gas_energy_eos_oracle). Used by
the predeclared witnesses of G3_M4_P2_F22_INTEGRATION_CONTRACT_2026-10-17.md.

F2.2 state per zone: m_z kg and E_z kJ, sensible enthalpy above the scenario
T_ref with cp; EOS p = (R/V)(M T_ref + E/cp). Heat Q adds to E; a parcel q
carries q cp (T_donor - T_ref).
"""

from __future__ import annotations

import math

from scripts.simulation import g3_m4_p2_gas_energy_eos_oracle as p2

LEGACY_DENSITY_KG_M3 = 1.2  # RoomModel.reset: lower_gas_kg = V * 1.2


def f22_pressure_abs_pa(gas: p2.Gas, mass_kg: float, energy_kj: float, volume_m3: float, t_ref_k: float) -> float:
    """F2.2A EOS (identity of the ideal gas, written with sensible energy)."""
    return gas.R * 1000.0 * (mass_kg * t_ref_k + energy_kj / gas.cp) / volume_m3


def f22_increment(gas: p2.Gas, heat_kj: float, parcels: list, t_ref_k: float) -> tuple[float, float]:
    """(dM, dE) of one room under F2.2: heat and parcel sensible enthalpies.

    parcels: [(signed q kg, T_k of the carried gas)], positive = enters.
    """
    d_mass = sum(q for q, _ in parcels)
    d_energy = heat_kj + sum(q * gas.cp * (t_k - t_ref_k) for q, t_k in parcels)
    return d_mass, d_energy


def f22_dp_pa(gas: p2.Gas, heat_kj: float, parcels: list, volume_m3: float, t_ref_k: float) -> float:
    d_mass, d_energy = f22_increment(gas, heat_kj, parcels, t_ref_k)
    return gas.R * 1000.0 * (d_mass * t_ref_k + d_energy / gas.cp) / volume_m3


def m4p2_dp_pa(gas: p2.Gas, heat_kj: float, parcels: list, volume_m3: float) -> float:
    """First law of a rigid room: dU = Q + sum h dm with absolute h = cp T."""
    d_u = heat_kj + sum(q * gas.cp * t_k for q, t_k in parcels)
    return (gas.gamma - 1.0) * d_u / volume_m3 * 1000.0


# --- explicit adapter (contract M4-P2 section 7) ---------------------------------

def u_from_e(gas: p2.Gas, mass_kg: float, energy_kj: float, t_ref_k: float) -> float:
    return (energy_kj + mass_kg * gas.cp * t_ref_k) / gas.gamma


def e_from_u(gas: p2.Gas, mass_kg: float, internal_kj: float, t_ref_k: float) -> float:
    return gas.gamma * internal_kj - mass_kg * gas.cp * t_ref_k


def local_enthalpy_kj(gas: p2.Gas, d_mass_kg: float, d_energy_kj: float, t_ref_k: float) -> float:
    """External absolute enthalpy behind a local (dm, dE) pair written by F2.2 owners."""
    return d_energy_kj + d_mass_kg * gas.cp * t_ref_k


def initial_gauge_pa(gas: p2.Gas, volume_m3: float, t_ref_k: float, p_ext_pa: float,
                     density_kg_m3: float = LEGACY_DENSITY_KG_M3) -> float:
    """Gauge pressure of the legacy initial room (rho = 1.2) under a FIXED R."""
    return density_kg_m3 * gas.R * 1000.0 * t_ref_k - p_ext_pa


# --- leaky room: both laws integrated with the same leak and heater ---------------

def leaky_room_history(gas: p2.Gas, law: str, *, volume_m3: float, t0_k: float, p_ext_pa: float,
                       heat_kw: float, leak_area_m2: float, t_end_s: float, dt_s: float,
                       discharge: float = 0.6) -> list[tuple[float, float]]:
    """One well-mixed layer, heater and a quadratic orifice to the exterior.

    Outflow only (the heater pressurizes): q = Cd A sqrt(2 rho dp) dt with the
    snapshot density and temperature. Returns [(t, gauge Pa)].
    """
    m = p_ext_pa * volume_m3 / (gas.R * 1000.0 * t0_k)
    u = m * gas.cv * t0_k
    history = [(0.0, 0.0)]
    for i in range(round(t_end_s / dt_s)):
        t_k = u / (m * gas.cv)
        p_abs = (gas.gamma - 1.0) * u / volume_m3 * 1000.0
        dp = max(0.0, p_abs - p_ext_pa)
        rho = m / volume_m3
        q = discharge * leak_area_m2 * math.sqrt(2.0 * rho * dp) * dt_s
        heat = heat_kw * dt_s
        if law == "m4p2":
            u += heat - q * gas.cp * t_k
        elif law == "f22":
            # F2.2 advances sum m T by (Q/cp + sum q T), i.e. U by 1/gamma of the first law.
            u += (heat - q * gas.cp * t_k) / gas.gamma
        else:
            raise ValueError(law)
        m -= q
        history.append(((i + 1) * dt_s, (gas.gamma - 1.0) * u / volume_m3 * 1000.0 - p_ext_pa))
    return history
