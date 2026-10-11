"""Exact counterexamples for the M2-T transport gate; NOT an engine model.

All examples use fractions and a normalized reference-gas content of one.
Oxygen is expressed as M/(M_O2/M_air), so its conserved quantity is x*C.
No engine constants, implementation, or measured trace are used here.
"""

from __future__ import annotations

from fractions import Fraction as F


def immediate_exchange(a: F, b: F, gas: F, ca: F = F(1), cb: F = F(1)) -> tuple[F, F]:
    """Same reference gas crosses both ways; the update is a convex mixing."""
    if not (0 <= gas <= min(ca, cb)):
        raise ValueError("gas exchange exceeds a reference content")
    delta = gas * (b - a)
    return a + delta / ca, b - delta / cb


def historical_dispatch(a: F, b: F, gas: F) -> dict[str, F]:
    """A gets the difference now; B owes it later. This is the old contract."""
    delta = gas * (b - a)
    return {"a": a + delta, "b": b, "transit": -delta, "b_available": b - max(F(0), delta)}


def positive_parcels(a: F, b: F, gas: F) -> dict[str, F]:
    """Debit both full parcels now; hold the denominator fixed until arrival."""
    return {"a": a * (1 - gas), "b": b * (1 - gas), "to_a": b * gas, "to_b": a * gas}


def dilute(held: F, outside: F, entering_gas: F) -> F:
    """Declared M2-V dilution, normalized reference content one."""
    return (held + outside * entering_gas) / (1 + entering_gas)


def net_only_dispatch(rich: F, poor: F, gas: F) -> dict[str, F]:
    """Another candidate: remove only the excess from the rich room now."""
    excess = gas * (rich - poor)
    return {"rich": rich - excess, "poor": poor, "transit": excess}


def counterexamples() -> dict[str, dict[str, F]]:
    air = F(209, 1000)
    gas = F(1, 25)  # 4 % of the reference content, not a stress-sized parcel.
    old = historical_dispatch(F(1, 10), air, gas)
    # Either end can be the poor room: the thermal hot/cold label is not composition.
    reverse = historical_dispatch(air, F(1, 10), gas)
    equal = positive_parcels(air, air, gas)
    # Other supported operations can occupy a capacity created at dispatch.
    parcels = positive_parcels(F(1, 10), air, gas)
    diluted = dilute(parcels["a"], air, F(100))
    net = net_only_dispatch(air, F(1, 10), gas)
    diluted_net = dilute(net["poor"], air, F(100))
    # A deferred paired transaction must protect its future outgoing oxygen.
    # Twenty overlapping 4 %-content exchanges reserve 80 % of the oxygen,
    # while the concentration of the still-held inventory remains high.
    reserved = 20 * gas * air
    spent = F(1, 10) * air
    return {
        "historical_credit_and_debt": {
            **old, "initial_total": F(1, 10) + air,
            "total_with_transit": old["a"] + old["b"] + old["transit"],
            "concentration_available_disagreement": old["b"] - old["b_available"],
        },
        "historical_reverse_signed_dispatch": {
            **reverse, "initial_max": air, "excess": reverse["a"] - air,
        },
        "positive_parcels_break_equilibrium": {
            **equal, "initial_fraction": air, "fraction_drop": air - equal["a"],
            "total_with_transit": equal["a"] + equal["b"] + equal["to_a"] + equal["to_b"],
            "fraction_with_carrier_state": equal["a"] / (1 - gas),
        },
        "positive_parcels_after_dilution": {
            "initial_max": air, "before_arrival": diluted,
            "arriving": parcels["to_a"], "after_arrival": diluted + parcels["to_a"],
            "excess": diluted + parcels["to_a"] - air,
            "entering_gas": F(100),
        },
        "net_only_after_dilution": {
            "initial_max": air, "before_arrival": diluted_net,
            "arriving": net["transit"], "after_arrival": diluted_net + net["transit"],
            "excess": diluted_net + net["transit"] - air,
            "entering_gas": F(100),
        },
        "deferred_pair_needs_protected_reservation": {
            "initial": air, "reserved": reserved, "spent_before_delivery": spent,
            "inventory_at_delivery": air - spent,
            "available_before_spending": air - reserved,
            "second_spend": F(1, 4) * air,
            "inventory_after_second_spend": air * F(3, 4),
            "inventory_after_second_spend_and_outgoing": air * F(3, 4) - reserved,
        },
        "immediate_control": dict(zip(("a", "b"), immediate_exchange(F(1, 10), air, gas))),
    }


def json_values(value):
    """Keep both the exact rational and a human-readable decimal."""
    if isinstance(value, F):
        return {"exact": str(value), "decimal": float(value)}
    if isinstance(value, dict):
        return {key: json_values(item) for key, item in value.items()}
    raise TypeError(type(value).__name__)
