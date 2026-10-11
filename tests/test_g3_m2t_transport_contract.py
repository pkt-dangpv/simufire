"""Counterexamples for M2-T. No Godot launch and no engine mutation."""

from fractions import Fraction as F

import pytest

from scripts.simulation import g3_m2t_transport_contract as model


def test_signed_transit_closes_but_selection_and_availability_disagree():
    case = model.counterexamples()["historical_credit_and_debt"]
    assert case["total_with_transit"] == case["initial_total"]
    assert case["transit"] < 0
    assert case["concentration_available_disagreement"] > 0


def test_hot_is_not_always_the_oxygen_poor_room():
    case = model.counterexamples()["historical_reverse_signed_dispatch"]
    assert case["excess"] < 0
    # Multiple outstanding credits, not this single operation, cause the house excess.


def test_full_positive_parcels_conserve_oxygen_but_break_equal_concentration():
    case = model.counterexamples()["positive_parcels_break_equilibrium"]
    assert case["total_with_transit"] == 2 * case["initial_fraction"]
    assert case["fraction_drop"] > 0
    assert case["a"] == case["b"] < case["initial_fraction"]
    assert case["fraction_with_carrier_state"] == case["initial_fraction"]


@pytest.mark.parametrize("name", ["positive_parcels_after_dilution", "net_only_after_dilution"])
def test_positive_transit_can_enrich_after_another_supported_operation(name):
    case = model.counterexamples()[name]
    assert case["before_arrival"] < case["initial_max"]
    assert case["arriving"] > 0
    assert case["after_arrival"] > case["initial_max"]
    assert case["excess"] > 0


def test_holding_a_future_debit_requires_a_guard_in_the_sink():
    case = model.counterexamples()["deferred_pair_needs_protected_reservation"]
    assert case["second_spend"] < case["initial"]
    assert case["second_spend"] > case["available_before_spending"]
    assert case["inventory_after_second_spend_and_outgoing"] < 0


@pytest.mark.parametrize("ca, cb", [(F(1), F(1)), (F(1), F(2)), (F(3), F(1))])
@pytest.mark.parametrize("a, b", [(F(209, 1000), F(209, 1000)), (F(1, 10), F(209, 1000)), (F(3, 10), F(1, 10))])
@pytest.mark.parametrize("share", [F(0), F(1, 25), F(1)])
def test_immediate_control_is_conservative_and_convex_without_a_ceiling(ca, cb, a, b, share):
    after_a, after_b = model.immediate_exchange(a, b, min(ca, cb) * share, ca, cb)
    assert ca * after_a + cb * after_b == ca * a + cb * b
    assert min(a, b) <= after_a <= max(a, b)
    assert min(a, b) <= after_b <= max(a, b)


def test_invalid_exchange_is_rejected_not_clipped():
    with pytest.raises(ValueError, match="reference content"):
        model.immediate_exchange(F(1, 10), F(209, 1000), F(2))


def test_output_keeps_exact_values():
    value = model.json_values({"value": F(1, 25)})
    assert value["value"] == {"exact": "1/25", "decimal": 0.04}
