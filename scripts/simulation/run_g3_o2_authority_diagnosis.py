"""Oxygen authority: what each oxygen number of the engine does. DIAGNOSIS, not acceptance.

Runs ``tests/fixtures/g3_o2_authority_diagnosis.gd`` under the safe monitor, reads the
existing switch-off identity run of the house cases if one is given, evaluates the
hypotheses below and writes a record. The hypotheses and what was predicted for each
were written BEFORE the first run; a hypothesis that does not come out as predicted is
recorded as such and is a finding, not something to tune.

It changes no engine file. Kilogram figures here are of three kinds and are never added
to one another: ``ref`` is a number of the engine times the constant mass every writer of
the room number uses (volume x 1.2 kg/m3), ``layers_ref`` is the two layer numbers on the
geometric shares of that same mass, and ``layers_gas`` is the two layer numbers on the
layer gas masses (the convention of the pressure network).

    python scripts/simulation/run_g3_o2_authority_diagnosis.py --plan-only
    python scripts/simulation/run_g3_o2_authority_diagnosis.py --identity-run runs/<off identity run>
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402

FIXTURE = "tests/fixtures/g3_o2_authority_diagnosis.gd"
PREFIX = "G3_O2_AUTHORITY_DIAGNOSIS"
SCHEMA = "g3_o2_authority_diagnosis_v1"
RECORD = "docs/validation/G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json"
SOURCES = ("sim/core/OxygenExchangeSystem.gd", "sim/core/SimulationEngine.gd", "sim/core/ZoneFireSolver.gd",
           "sim/core/ThermalSystem.gd", "sim/core/GasExchangeSystem.gd", "sim/core/PressureNetworkTransportSystem.gd",
           "sim/fire/CombustionSystem.gd", "sim/building/RoomModel.gd", FIXTURE)
KG_PER_MJ = 0.076
AMBIENT = 0.209
ROUNDING_KG = 1.0e-9

# Molar masses, g/mol: O2 from the IUPAC standard atomic weight of oxygen (15.999 x 2);
# dry air, 28.9647, as in the ICAO/US Standard Atmosphere. Dry air is an assumption: the
# engine has no humidity and no composition of its gas.
M_O2 = 31.998
M_DRY_AIR = 28.9647

# Written before any run. `predicted` is what was expected of `statement`.
HYPOTHESES = {
    "H01_rest": {
        "statement": "A sealed room with no fire keeps its three oxygen numbers bit for bit, its gas mass and "
                     "every oxygen accumulator at zero.", "predicted": True,
        "decides": "whether the engine has a writer that acts with nothing to do"},
    "H02_heating_changes_the_gas_base_not_the_numbers": {
        "statement": "Product route, a sealed hot room with no fire: the three oxygen numbers do not change, the "
                     "gas mass of the room falls and is booked at the boundary, and so the layer numbers on the "
                     "layer gas masses lose 0.209 kg per kg of gas with no oxygen writer having acted.",
        "predicted": True,
        "decides": "E1, product route: the layer gas masses are rewritten, so they cannot be the base of an inventory"},
    "H03_network_keeps_the_gas_base": {
        "statement": "Diagnostic mode with the pressure network, the same hot room: gas mass, the three numbers "
                     "and the layer numbers on the layer gas masses all stay.", "predicted": True,
        "decides": "E1, network mode: the gas mass is state there"},
    "H04_controlled_demand_closes_on_the_room_number": {
        "statement": "Two rooms closed to the outside, a known power in one: the room numbers on their constant "
                     "base, plus what is in transit, fall by exactly the debit of the room inventory, at every "
                     "step; that debit is 0.076 kg/MJ of the accepted heat; the second write on the upper number "
                     "is at least half as large again and reaches neither; and the two layer numbers do not add "
                     "up to the room number.", "predicted": True,
        "decides": "whether the room number is today a closed ledger on the route the bench uses"},
    "H05_interior_transport_conserves_the_room_numbers": {
        "statement": "Two rooms closed to the outside, no fire, one poorer: the sum of the room numbers on their "
                     "base (plus transit) is conserved at every step, their difference never grows, the transport "
                     "accumulators cancel, and the layer numbers follow with a lag instead of being transported.",
        "predicted": True,
        "decides": "whether interior transport is conservative, and of which number"},
    "H06_exterior_exchange_is_the_declared_one": {
        "statement": "One room open to the outside, no fire, no temperature difference: the room number changes "
                     "only by the infiltration law, x += (ACH/3600) dt (0.209 - x), and the change is the "
                     "exterior accumulator.", "predicted": True,
        "decides": "whether an exterior exchange with a known balance closes"},
    "H07_closed_door_stops_the_transport": {
        "statement": "The transport case with the door closed, open and closed: with the door closed neither "
                     "room number changes at all, from the first closed step; the sum is conserved throughout.",
        "predicted": True,
        "decides": "opening and closing"},
    "H08_layer_mixing_is_a_relaxation_not_an_exchange": {
        "statement": "One sealed room, no fire, two layers with different numbers: the room number does not move, "
                     "the upper number rises and the lower falls towards it, and the layer numbers on their "
                     "shares change by more than a gram with every accumulator at zero.", "predicted": True,
        "decides": "whether mixing between layers conserves anything"},
    "H09_collapse_rewrites_both_layers": {
        "statement": "One sealed room, no fire, an upper layer that takes more than 85 % of the height: in one "
                     "step both layer numbers become the room number exactly, a jump of more than 1 kg on their "
                     "shares with every accumulator at zero.", "predicted": True,
        "decides": "what a collapsed layer does to the layer numbers"},
    "H10_two_step_sizes": {
        "statement": "With half the step the closures of H04 and H06 hold as well and the debit of the room "
                     "inventory is the same; the final room number is not the same.", "predicted": True,
        "decides": "which properties depend on the step"},
    "H11_reset_and_reuse": {
        "statement": "After reset_simulation on the same engine nothing is in transit or reserved, the numbers "
                     "are 0.209, the accumulators are zero, and the same run gives the same numbers bit for bit.",
        "predicted": True,
        "decides": "life cycle"},
    "H12_fire_and_sink_use_different_deposits": {
        "statement": "A real room fire with the door to a second room open: the sink debits the room inventory "
                     "in every burning step while the fire reads a layer number that differs from the room "
                     "number by more than 0.001; the second write is at least half the debit and drives the upper "
                     "number below half of the room number; the room numbers still close on debit plus exterior.",
        "predicted": True,
        "decides": "O2-1 and O2-4 on the current engine"},
    "H13_house_cases_already_run": {
        "statement": "House cases of the switch-off identity run. Door closed (o2_closed): the room inventory is "
                     "not debited and the room number changes by more than 1 kg that no accumulator explains. "
                     "Door reopened at 300 s (o2_reopen_300): from then on the room inventory is debited, the "
                     "second write is at least half of it, the fire reads the lower number while the sink debits "
                     "the room, and the house closes within 0.01 kg. Stress (o2_stress_cap): the heat accepted "
                     "asks for more than 1 kg of oxygen above what was debited.", "predicted": True,
        "decides": "U13, O2-1, O2-4 and O2-3 on product geometry"},
    "H14_network_mode_has_no_oxygen_inventory_either": {
        "statement": "Diagnostic mode with the pressure network, the controlled demand: gas mass is conserved, "
                     "the room number is rewritten from the layers at every step, and the layer numbers on the "
                     "layer gas masses do not fall by the debit of the room inventory (more than 1 % apart).",
        "predicted": True,
        "decides": "E1, network mode: conserved gas mass is not an oxygen inventory"},
    # Added after the first launch showed that the bench does not arm with the pressure
    # network, and before the case it speaks of was run.
    "H15_network_mode_with_a_real_fire": {
        "statement": "Diagnostic mode with the pressure network, the real fire of H12: the gas mass of the two rooms "
                     "is conserved, the room number is rewritten from the layer numbers at every step, and the layer "
                     "numbers on the layer gas masses do not fall by the primary debit less the exterior exchange "
                     "(more than 1 % of the debit apart).", "predicted": True,
        "decides": "E1, network mode, with the question H14 could not ask"},
}


# ---------------------------------------------------------------- reading rows

def _room(rows: list, room: int, key: str) -> list:
    return [float(row[room][key]) for row in rows]


def _total(sample: list, key: str) -> float:
    return sum(float(row[key]) for row in sample)


def _span(values: list) -> float:
    return max(values) - min(values) if values else 0.0


def _accumulators_zero(rows: list) -> bool:
    keys = ("debit_room_inventory_kg", "debit_primary_kg", "debits_declared_kg", "exterior_kg", "transport_kg", "zone_sync_kg")
    return all(float(row[key]) == 0.0 for sample in rows for row in sample for key in keys)


def _closure(start: list, rows: list, with_exterior: bool = False) -> float:
    """Largest gap, in kg on the constant base, between the room numbers (plus transit) and the debit."""
    first = _total(start, "ref_kg")
    worst = 0.0
    for sample in rows:
        expected = first - _total(sample, "debit_room_inventory_kg") + _total(start, "debit_room_inventory_kg")
        if with_exterior:
            expected += _total(sample, "exterior_kg") - _total(start, "exterior_kg")
        worst = max(worst, abs(_total(sample, "ref_kg") + _total(sample, "in_transit_kg") - expected))
    return worst


# ---------------------------------------------------------------- evaluation

def _verdict(claims: dict, evidence: dict, exercised: bool = True) -> dict:
    """A hypothesis holds when every one of its claims does; each claim is kept apart."""
    return {"holds": bool(all(claims.values())) if exercised else None, "exercised": exercised,
            "claims": {name: bool(value) for name, value in claims.items()}, "evidence": evidence}


def _largest_accumulator(rows: list) -> float:
    keys = ("debit_room_inventory_kg", "debit_primary_kg", "debits_declared_kg", "exterior_kg", "transport_kg", "zone_sync_kg")
    return max(abs(float(row[key])) for sample in rows for row in sample for key in keys)


def _gas(sample: list) -> float:
    return sum(float(row["upper_gas_kg"]) + float(row["lower_gas_kg"]) for row in sample)


def evaluate(cases: dict) -> dict:
    out: dict = {}

    case = cases["rest"]
    start, rows = case["start"], case["rows"]
    numbers = {key: sorted(set(_room(rows, 0, key))) for key in ("o2", "o2_upper", "o2_lower")}
    gas = [_gas(row) for row in [start] + rows]
    out["H01_rest"] = _verdict({
        "three_numbers_bit_for_bit": all(values == [AMBIENT] for values in numbers.values()),
        "gas_mass_kept": _span(gas) <= ROUNDING_KG,
        "nothing_booked_at_the_boundary": all(row[0]["boundary_gas_kg"] == 0.0 for row in rows),
        "accumulators_exactly_zero": _accumulators_zero(rows),
    }, {"distinct_values": numbers, "gas_kg": [gas[0], gas[-1]], "gas_span_kg": _span(gas),
        "largest_accumulator_kg": _largest_accumulator(rows), "writers": case["writers"], "steps": len(rows)})

    case = cases["heated"]
    start, rows = case["start"], case["rows"]
    unchanged = all(row[0][key] == start[0][key] for row in rows for key in ("o2", "o2_upper", "o2_lower"))
    gas = [_gas(row) for row in [start] + rows]
    gas_change = gas[-1] - gas[0]
    kg_change = rows[-1][0]["layers_gas_kg"] - start[0]["layers_gas_kg"]
    out["H02_heating_changes_the_gas_base_not_the_numbers"] = _verdict({
        "three_numbers_unchanged": unchanged,
        "gas_mass_falls": gas_change < -0.1,
        "booked_at_the_boundary_as_a_loss": rows[-1][0]["boundary_gas_kg"] < 0.0,
        "layer_numbers_on_gas_lose_0.209_per_kg_of_gas": abs(kg_change - AMBIENT * gas_change) <= ROUNDING_KG,
        "accumulators_exactly_zero": _accumulators_zero(rows),
    }, {"gas_kg": [gas[0], min(gas), gas[-1]], "gas_change_kg": gas_change,
        "boundary_gas_kg": [rows[0][0]["boundary_gas_kg"], rows[-1][0]["boundary_gas_kg"]],
        "layer_numbers_on_gas_change_kg": kg_change, "expected_from_gas_alone_kg": AMBIENT * gas_change,
        "largest_change_on_gas_kg": min(row[0]["layers_gas_kg"] for row in rows) - start[0]["layers_gas_kg"],
        "largest_accumulator_kg": _largest_accumulator(rows),
        "temp_upper_c": [rows[0][0]["temp_upper_c"], rows[-1][0]["temp_upper_c"]], "writers": case["writers"], "steps": len(rows)})

    case = cases["heated_network_on"]
    start, rows = case["start"], case["rows"]
    gas = [_gas(row) for row in [start] + rows]
    drift = max(abs(row[0][key] - start[0][key]) for row in rows for key in ("o2", "o2_upper", "o2_lower"))
    kg = [row[0]["layers_gas_kg"] for row in [start] + rows]
    out["H03_network_keeps_the_gas_base"] = _verdict({
        "gas_mass_kept": _span(gas) <= ROUNDING_KG,
        "nothing_booked_at_the_boundary": max(abs(row[0]["boundary_gas_kg"]) for row in rows) <= 1.0e-12,
        "three_numbers_kept": drift <= 1.0e-12,
        "layer_numbers_on_gas_kept": _span(kg) <= ROUNDING_KG,
    }, {"gas_kg": [gas[0], min(gas), gas[-1]], "gas_span_kg": _span(gas),
        "largest_boundary_gas_kg": max(abs(row[0]["boundary_gas_kg"]) for row in rows), "largest_number_drift": drift,
        "layer_numbers_on_gas_span_kg": _span(kg), "largest_overpressure_pa": max(row[0]["overpressure_pa"] for row in rows),
        "writers": case["writers"], "steps": len(rows)})

    out["H04_controlled_demand_closes_on_the_room_number"] = _controlled(cases["controlled_demand_dt_0.5"])

    case = cases["transport"]
    start, rows = case["start"], case["rows"]
    gaps = [abs(row[0]["o2"] - row[1]["o2"]) for row in [start] + rows]
    cancel = max(abs(_total(row, "transport_kg") + _total(row, "in_transit_kg")) for row in rows)
    own = max(abs(row[index]["ref_kg"] - start[index]["ref_kg"] - row[index]["transport_kg"]) for row in rows for index in (0, 1))
    # Room by room: summed over the two rooms the lags cancel, which is what the first
    # version of this line measured (corrected after the second launch; the claim is the same).
    lag = max(abs(row[index]["layers_ref_kg"] - row[index]["ref_kg"]) for row in rows for index in (0, 1))
    out["H05_interior_transport_conserves_the_room_numbers"] = _verdict({
        "sum_conserved_at_every_step": _closure(start, rows) <= ROUNDING_KG,
        "difference_never_grows": all(later <= earlier for earlier, later in zip(gaps, gaps[1:])),
        "transport_accumulators_cancel": cancel <= ROUNDING_KG,
        "each_room_changes_by_its_accumulator": own <= ROUNDING_KG,
        "layer_numbers_lag_the_room_numbers": lag > 1.0e-4,
    }, {"largest_closure_gap_kg": _closure(start, rows), "difference": [gaps[0], gaps[-1]],
        "transport_accumulators_plus_transit_kg": cancel, "room_change_minus_its_accumulator_kg": own,
        "largest_layers_minus_room_kg_in_one_room": lag,
        "numbers_of_the_poorer_room_after_one_step": [rows[0][1]["o2"], rows[0][1]["o2_upper"], rows[0][1]["o2_lower"]],
        "room_changes_kg": [rows[-1][index]["ref_kg"] - start[index]["ref_kg"] for index in (0, 1)],
        "gas_kg": [_gas(start), _gas(rows[-1])],
        "largest_in_transit_kg": max(abs(row[index]["in_transit_kg"]) for row in rows for index in (0, 1)),
        "one_sub_step_alone": cases["transport_one_sub_step_alone"], "writers": case["writers"], "steps": len(rows)})

    out["H06_exterior_exchange_is_the_declared_one"] = _exterior(cases["exterior_dt_0.5"], cases.get("exterior_one_sub_step_alone"))

    case = cases["open_and_close"]
    start, rows = case["start"], case["rows"]
    changes: dict = {}
    for phase in case["phases"]:
        first, count = int(phase["first_row"]), int(phase["steps"])
        reference = rows[first - 1] if first > 0 else start
        changes[phase["name"]] = sum(1 for row in rows[first:first + count] for index in (0, 1) if row[index]["o2"] != reference[index]["o2"])
    total = [_total(row, "ref_kg") + _total(row, "in_transit_kg") for row in [start] + rows]
    out["H07_closed_door_stops_the_transport"] = _verdict({
        "nothing_changes_while_closed_at_first": changes["closed"] == 0,
        "something_changes_while_open": changes["open"] > 0,
        "nothing_changes_once_closed_again": changes["closed_again"] == 0,
        "sum_conserved_throughout": _span(total) <= ROUNDING_KG,
    }, {"rows_that_changed_a_room_number": changes, "sum_span_kg": _span(total),
        "room_numbers_start": [start[0]["o2"], start[1]["o2"]], "room_numbers_end": [rows[-1][0]["o2"], rows[-1][1]["o2"]],
        "writers": case["writers"]})

    case = cases["two_layers"]
    start, rows = case["start"], case["rows"]
    upper, lower = [start[0]["o2_upper"]] + _room(rows, 0, "o2_upper"), [start[0]["o2_lower"]] + _room(rows, 0, "o2_lower")
    layers_change = rows[-1][0]["layers_ref_kg"] - rows[0][0]["layers_ref_kg"]
    out["H08_layer_mixing_is_a_relaxation_not_an_exchange"] = _verdict({
        "room_number_does_not_move": all(row[0]["o2"] == start[0]["o2"] for row in rows),
        "upper_number_rises_towards_it": all(b >= a for a, b in zip(upper, upper[1:])) and upper[-1] > upper[0],
        "lower_number_falls_towards_it": all(b <= a for a, b in zip(lower, lower[1:])) and lower[-1] < lower[0],
        "layers_on_shares_change_by_more_than_a_gram": abs(layers_change) > 1.0e-3,
        "accumulators_exactly_zero": _accumulators_zero(rows),
    }, {"room_number": [start[0]["o2"], rows[-1][0]["o2"]], "upper_number": [upper[0], upper[-1]], "lower_number": [lower[0], lower[-1]],
        "layers_on_shares_kg": [rows[0][0]["layers_ref_kg"], rows[-1][0]["layers_ref_kg"]], "room_number_on_base_kg": rows[-1][0]["ref_kg"],
        "layers_on_shares_change_kg": layers_change, "upper_share": [rows[0][0]["upper_share"], rows[-1][0]["upper_share"]],
        "largest_accumulator_kg": _largest_accumulator(rows), "one_sub_step_alone": cases["two_layers_one_sub_step_alone"],
        "writers": case["writers"], "steps": len(rows)})

    case = cases["collapse"]
    start, rows = case["start"], case["rows"]
    step = next((index for index, row in enumerate(rows) if row[0]["o2_upper"] == row[0]["o2"] == row[0]["o2_lower"]), None)
    jump = None if step is None else rows[step][0]["layers_ref_kg"] - (rows[step - 1][0] if step > 0 else start[0])["layers_ref_kg"]
    lowest_share = min(1.0 - row[0]["upper_share"] for row in rows)
    out["H09_collapse_rewrites_both_layers"] = _verdict({
        "both_layers_become_the_room_number_in_one_step": step is not None,
        "jump_of_more_than_1_kg_on_their_shares": jump is not None and jump > 1.0,
        "accumulators_exactly_zero": _accumulators_zero(rows),
    }, {"step_where_both_layers_equal_the_room": step, "jump_on_shares_kg": jump, "lowest_lower_share": lowest_share,
        "lower_share_by_step": [1.0 - row[0]["upper_share"] for row in rows[:6]],
        "numbers_start": [start[0]["o2"], start[0]["o2_upper"], start[0]["o2_lower"]],
        "numbers_after_first_step": [rows[0][0]["o2"], rows[0][0]["o2_upper"], rows[0][0]["o2_lower"]],
        "numbers_end": [rows[-1][0]["o2"], rows[-1][0]["o2_upper"], rows[-1][0]["o2_lower"]],
        "largest_accumulator_kg": _largest_accumulator(rows), "writers": case["writers"]}, exercised=lowest_share < 0.15)

    fine, coarse = _controlled(cases["controlled_demand_dt_0.25"]), out["H04_controlled_demand_closes_on_the_room_number"]
    fine_exterior, coarse_exterior = _exterior(cases["exterior_dt_0.25"], None), out["H06_exterior_exchange_is_the_declared_one"]
    debits = [coarse["evidence"]["debit_room_inventory_kg"], fine["evidence"]["debit_room_inventory_kg"]]
    out["H10_two_step_sizes"] = _verdict({
        "controlled_demand_closes_with_half_the_step": fine["claims"]["room_numbers_close_on_the_debit_at_every_step"],
        "exterior_exchange_holds_with_half_the_step": bool(fine_exterior["holds"]),
        "same_debit_of_the_room_inventory": debits[0] > 0.0 and abs(debits[0] - debits[1]) <= 1.0e-9 * debits[0],
        "final_room_number_differs": abs(fine["evidence"]["final_room_number"] - coarse["evidence"]["final_room_number"]) > 1.0e-9,
    }, {"closure_gap_kg": [coarse["evidence"]["largest_closure_gap_kg"], fine["evidence"]["largest_closure_gap_kg"]],
        "exterior_half_step": fine_exterior["evidence"], "exterior_half_step_claims": fine_exterior["claims"],
        "debit_room_inventory_kg": debits,
        "final_room_number": [coarse["evidence"]["final_room_number"], fine["evidence"]["final_room_number"]],
        "final_upper_number": [coarse["evidence"]["final_upper_number"], fine["evidence"]["final_upper_number"]],
        "final_room_number_exterior": [coarse_exterior["evidence"]["final_room_number"], fine_exterior["evidence"]["final_room_number"]],
        "second_write_kg": [coarse["evidence"]["second_write_kg"], fine["evidence"]["second_write_kg"]]},
        exercised=debits[0] > 0.0)

    case = cases["reset_and_reuse"]
    clean = all(row[key] == AMBIENT for row in case["after_reset"] for key in ("o2", "o2_upper", "o2_lower")) \
        and _accumulators_zero([case["after_reset"]]) and all(row["in_transit_kg"] == 0.0 for row in case["after_reset"])
    out["H11_reset_and_reuse"] = _verdict({
        "nothing_in_transit_or_reserved": case["in_transit_entries_after_reset"] == 0 and case["reserved_entries_after_reset"] == 0,
        "numbers_and_accumulators_clean": clean,
        "same_run_bit_for_bit": case["first_digest"] == case["second_digest"],
    }, {key: case[key] for key in ("in_transit_entries_before_reset", "reserved_entries_before_reset",
                                    "in_transit_entries_after_reset", "reserved_entries_after_reset", "first_digest",
                                    "second_digest", "largest_in_transit_first_run_kg", "bench_state_second_run")}
        | {"debit_room_inventory_kg": [case["first_last"][0]["debit_room_inventory_kg"], case["second_last"][0]["debit_room_inventory_kg"]],
           "something_was_in_transit_at_some_step": case["largest_in_transit_first_run_kg"] > 0.0,
           "something_was_in_transit_at_the_reset": case["in_transit_entries_before_reset"] > 0},
        exercised=case["first_last"][0]["debit_room_inventory_kg"] > 0.0)

    out["H12_fire_and_sink_use_different_deposits"] = _real_fire(cases["real_fire"])

    case = cases["controlled_demand_network_on"]
    out["H14_network_mode_has_no_oxygen_inventory_either"] = _verdict(
        {"exercised_with_the_bench": False},
        {"bench_state": case["bench"].get("state"), "bench_failure": case["bench"].get("failure"),
         "debit_room_inventory_kg": _total(case["rows"][-1], "debit_room_inventory_kg"),
         "why": "the diagnostic bench does not arm with the pressure network; the same question is asked of a real fire in H15"},
        exercised=_total(case["rows"][-1], "debit_room_inventory_kg") > 0.0)

    case = cases["real_fire_network_on"]
    start, rows = case["start"], case["rows"]
    gas = [_gas(row) for row in [start] + rows]
    primary = _total(rows[-1], "debit_primary_kg")
    exterior = _total(rows[-1], "exterior_kg")
    kg_change = _total(rows[-1], "layers_gas_kg") - _total(start, "layers_gas_kg")
    rewritten = max(abs(row[index]["o2"] - row[index]["layers_gas_kg"] / (row[index]["upper_gas_kg"] + row[index]["lower_gas_kg"]))
                    for row in rows for index in (0, 1))
    unexplained = kg_change - (-primary + exterior)
    out["H15_network_mode_with_a_real_fire"] = _verdict({
        "gas_mass_conserved": _span(gas) <= ROUNDING_KG,
        "room_number_rewritten_from_the_layers": rewritten <= 1.0e-12,
        "layer_numbers_on_gas_do_not_follow_the_debit": abs(unexplained) > 0.01 * primary,
    }, {"gas_kg": [gas[0], min(gas), max(gas), gas[-1]], "gas_span_kg": _span(gas),
        "room_number_minus_layers_on_gas": rewritten, "debit_primary_kg": primary,
        "debit_room_inventory_kg": _total(rows[-1], "debit_room_inventory_kg"),
        "second_write_kg": _total(rows[-1], "debits_declared_kg") - primary, "exterior_kg": exterior,
        "layer_numbers_on_gas_change_kg": kg_change, "unexplained_kg": unexplained,
        "unexplained_over_debit": unexplained / primary if primary > 0.0 else None,
        "room_numbers_on_base_change_kg": _total(rows[-1], "ref_kg") - _total(start, "ref_kg"),
        "heat_accepted_MJ": rows[-1][0]["heat_kj"] / 1000.0, "lowest_upper_number": min(_room(rows, 0, "o2_upper")),
        "lowest_room_number": min(_room(rows, 0, "o2")), "writers": case["writers"]}, exercised=primary > 0.0)
    return out


def _controlled(case: dict) -> dict:
    start, rows, bench = case["start"], case["rows"], case["bench"]
    accepted_mj = float(bench.get("totals", {}).get("accepted_kj", 0.0)) / 1000.0
    debit = rows[-1][0]["debit_room_inventory_kg"]
    second = rows[-1][0]["debits_declared_kg"] - debit
    gap = _closure(start, rows)
    return _verdict({
        "bench_delivered": bench.get("state") != "failed" and accepted_mj > 0.0,
        "room_numbers_close_on_the_debit_at_every_step": debit > 0.0 and gap <= ROUNDING_KG,
        "debit_is_0.076_kg_per_MJ_of_accepted_heat": debit > 0.0 and abs(debit - KG_PER_MJ * accepted_mj) <= 1.0e-9 * debit,
        "second_write_at_least_half_the_debit": debit > 0.0 and second >= 0.5 * debit,
        "layer_numbers_do_not_add_up_to_the_room_number": abs(rows[-1][0]["layers_ref_kg"] - rows[-1][0]["ref_kg"]) > 1.0e-3,
    }, {"bench_state": bench.get("state"), "bench_failure": bench.get("failure"), "accepted_MJ": accepted_mj,
        "debit_room_inventory_kg": debit, "debit_expected_kg": KG_PER_MJ * accepted_mj, "largest_closure_gap_kg": gap,
        "second_write_kg": second, "layers_minus_room_kg": rows[-1][0]["layers_ref_kg"] - rows[-1][0]["ref_kg"],
        "room_numbers_on_base_change_kg": _total(rows[-1], "ref_kg") - _total(start, "ref_kg"),
        "final_room_number": rows[-1][0]["o2"], "final_upper_number": rows[-1][0]["o2_upper"],
        "final_lower_number": rows[-1][0]["o2_lower"], "final_room_number_other_room": rows[-1][1]["o2"],
        "largest_in_transit_kg": max(abs(row[index]["in_transit_kg"]) for row in rows for index in (0, 1)),
        "gas_kg": [_gas(start), min(_gas(row) for row in rows), _gas(rows[-1])],
        "writers": case["writers"], "steps": len(rows)}, exercised=bench.get("state") != "failed" or accepted_mj > 0.0)


def _exterior(case: dict, alone) -> dict:
    start, rows, setup = case["start"], case["rows"], case["setup"]
    rate = float(setup["engine"]["ach_infiltration"]) / 3600.0 * float(setup["dt_s"])
    own = max(abs(row[0]["ref_kg"] - start[0]["ref_kg"] - row[0]["exterior_kg"]) for row in rows)
    value, law = start[0]["o2"], 0.0
    for row in rows:
        value = value + rate * (AMBIENT - value)
        law = max(law, abs(row[0]["o2"] - value))
    return _verdict({
        "room_changes_by_the_exterior_accumulator": own <= ROUNDING_KG,
        "follows_the_infiltration_law": law <= 1.0e-12,
    }, {"room_change_kg": rows[-1][0]["ref_kg"] - start[0]["ref_kg"], "exterior_accumulator_kg": rows[-1][0]["exterior_kg"],
        "room_change_minus_exterior_accumulator_kg": own, "largest_gap_to_the_infiltration_law": law,
        "final_room_number": rows[-1][0]["o2"], "law_final": value,
        "final_layer_numbers": [rows[-1][0]["o2_upper"], rows[-1][0]["o2_lower"]],
        "one_sub_step_alone": alone, "writers": case["writers"], "steps": len(rows)})


def _real_fire(case: dict) -> dict:
    start, rows = case["start"], case["rows"]
    burning = [row for row in rows if row[0]["power_kw"] > 0.0]
    debit = rows[-1][0]["debit_room_inventory_kg"]
    primary = rows[-1][0]["debit_primary_kg"]
    second = rows[-1][0]["debits_declared_kg"] - debit
    apart = [row for row in burning if str(row[0]["fire_deposit"]).startswith("plume") and abs(row[0]["fire_reads"] - row[0]["o2"]) > 1.0e-3]
    lowest_upper, lowest_room = min(_room(rows, 0, "o2_upper")), min(_room(rows, 0, "o2"))
    gap = _closure(start, rows, with_exterior=True)
    return _verdict({
        "sink_debits_the_room_inventory": debit > 0.0 and abs(primary - debit) <= 1.0e-9 * debit,
        "fire_reads_a_layer_number_apart_from_the_room_number": len(apart) > 0,
        "second_write_at_least_half_the_debit": debit > 0.0 and second >= 0.5 * debit,
        "upper_number_driven_below_half_the_room_number": lowest_upper < 0.5 * lowest_room,
        "room_numbers_close_on_debit_plus_exterior": gap <= 1.0e-6,
    }, {"burning_steps": len(burning), "steps_with_fire_reading_a_layer_apart_from_the_room": len(apart),
        "largest_fire_reads_minus_room_number": max((row[0]["fire_reads"] - row[0]["o2"] for row in burning), default=0.0),
        "fire_deposits_seen": sorted({str(row[0]["fire_deposit"]) for row in burning}),
        "debit_room_inventory_kg": debit, "debit_primary_kg": primary, "second_write_kg": second,
        "heat_accepted_MJ": rows[-1][0]["heat_kj"] / 1000.0,
        "debit_per_MJ": debit / max(1.0e-12, rows[-1][0]["heat_kj"] / 1000.0),
        "lowest_upper_number": lowest_upper, "lowest_room_number": lowest_room,
        "lowest_lower_number": min(_room(rows, 0, "o2_lower")),
        "largest_transport_accumulators_plus_transit_kg":
            max(abs(_total(row, "transport_kg") + _total(row, "in_transit_kg")) for row in rows),
        "transport_accumulators_at_the_end_kg": _total(rows[-1], "transport_kg"),
        "in_transit_at_the_end_kg": _total(rows[-1], "in_transit_kg"),
        "largest_closure_gap_kg": gap, "closure_gap_at_the_end_kg":
            _total(rows[-1], "ref_kg") + _total(rows[-1], "in_transit_kg")
            - (_total(start, "ref_kg") - _total(rows[-1], "debit_room_inventory_kg") + _total(rows[-1], "exterior_kg")),
        "exterior_kg": _total(rows[-1], "exterior_kg"),
        "largest_in_transit_kg": max(abs(row[index]["in_transit_kg"]) for row in rows for index in (0, 1)),
        "gas_kg": [_gas(start), min(_gas(row) for row in rows), _gas(rows[-1])],
        "boundary_gas_kg": [rows[-1][index]["boundary_gas_kg"] for index in (0, 1)],
        "layer_numbers_on_gas_change_kg": _total(rows[-1], "layers_gas_kg") - _total(start, "layers_gas_kg"),
        "peak_power_kw": max(_room(rows, 0, "power_kw")), "writers": case["writers"]}, exercised=bool(burning))


# ---------------------------------------------------------------- house cases already run

def _house(run: Path, case: str) -> list:
    with (run / case / "sim_log.csv").open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def _at(rows: list, room: str, time_s: float) -> dict:
    return min((row for row in rows if row["room_id"] == room), key=lambda row: abs(float(row["time_s"]) - time_s))


def existing_runs(run: Path) -> dict:
    """Aggregates of the house cases of an existing switch-off identity run (logged every second)."""
    evidence: dict = {"source_run": run.name}
    closed = _house(run, "o2_closed")
    first, last = _at(closed, "0", 0.0), _at(closed, "0", 1.0e9)
    base = float(first["air_mass_kg"])
    change = base * (float(last["o2"]) - float(first["o2"]))
    explained = -float(last["o2_consumed_bulk_kg_total"]) + float(last["o2_exterior_net_kg_total"]) + float(last["o2_net_transport_kg_total"])
    evidence["o2_closed"] = {
        "base_kg": base, "debit_room_inventory_kg": float(last["o2_consumed_bulk_kg_total"]),
        "debit_primary_kg": float(last["o2_consumed_fire_kg_total"]), "debits_declared_kg": float(last["o2_consumed_kg_total_all"]),
        "room_number_change_kg": change, "explained_by_accumulators_kg": explained, "unexplained_kg": change - explained,
        "zone_sync_kg": float(last["o2_zone_sync_kg_total"]), "heat_accepted_MJ": float(last["hrr_kj_total"]) / 1000.0,
        "final_numbers": [float(last["o2"]), float(last["o2_upper"]), float(last["o2_lower"])]}
    reopen = _house(run, "o2_reopen_300")
    rooms = sorted({row["room_id"] for row in reopen})
    at300, end = _at(reopen, "0", 300.0), _at(reopen, "0", 1.0e9)
    debit = float(end["o2_consumed_bulk_kg_total"]) - float(at300["o2_consumed_bulk_kg_total"])
    primary = float(end["o2_consumed_fire_kg_total"]) - float(at300["o2_consumed_fire_kg_total"])
    declared = float(end["o2_consumed_kg_total_all"]) - float(at300["o2_consumed_kg_total_all"])
    apart = [row for row in reopen if row["room_id"] == "0" and float(row["time_s"]) > 300.0 and row["fire_o2_mode_used"] == "plume_lower"
             and float(row["o2_consumed_bulk_kg_step"]) > 0.0 and float(row["o2_lower"]) - float(row["o2"]) > 1.0e-3]
    house_change = sum(float(_at(reopen, room, 1.0e9)["air_mass_kg"]) * (float(_at(reopen, room, 1.0e9)["o2"]) - float(_at(reopen, room, 300.0)["o2"]))
                       for room in rooms)
    house_exterior = sum(float(_at(reopen, room, 1.0e9)["o2_exterior_net_kg_total"]) - float(_at(reopen, room, 300.0)["o2_exterior_net_kg_total"])
                         for room in rooms)
    per_room = []
    for room in rooms:
        a, b = _at(reopen, room, 300.0), _at(reopen, room, 1.0e9)
        moved = float(b["air_mass_kg"]) * (float(b["o2"]) - float(a["o2"]))
        booked = sum(sign * (float(b[key]) - float(a[key])) for sign, key in (
            (-1.0, "o2_consumed_bulk_kg_total"), (1.0, "o2_exterior_net_kg_total"), (1.0, "o2_net_transport_kg_total")))
        per_room.append(moved - booked)
    house_transport = sum(float(_at(reopen, room, 1.0e9)["o2_net_transport_kg_total"]) - float(_at(reopen, room, 300.0)["o2_net_transport_kg_total"])
                          for room in rooms)
    evidence["o2_reopen_300"] = {
        "after_300_s": {"debit_room_inventory_kg": debit, "debit_primary_kg": primary, "second_write_kg": declared - primary,
                        "seconds_with_fire_reading_the_lower_number_and_sink_debiting_the_room": len(apart),
                        "largest_lower_minus_room_number": max((float(row["o2_lower"]) - float(row["o2"]) for row in apart), default=0.0),
                        "house_room_numbers_change_kg": house_change, "house_exterior_kg": house_exterior,
                        "house_closure_gap_kg": house_change - (-debit + house_exterior),
                        "largest_room_change_minus_its_own_accumulators_kg": max(abs(value) for value in per_room),
                        "house_transport_accumulators_kg": house_transport,
                        "note": "every room closes on its own accumulators; the house gap is the transport accumulators "
                                "not cancelling, which is what oxygen in transit between rooms looks like; the log "
                                "does not record what is in transit, so here it is consistent with it, not measured"},
        "lowest_upper_number": min(float(row["o2_upper"]) for row in reopen if row["room_id"] == "0"), "rooms": len(rooms)}
    stress = _house(run, "o2_stress_cap")
    end = _at(stress, "0", 1.0e9)
    asked = KG_PER_MJ * float(end["hrr_kj_total"]) / 1000.0
    evidence["o2_stress_cap"] = {
        "heat_accepted_MJ": float(end["hrr_kj_total"]) / 1000.0, "oxygen_asked_by_that_heat_kg": asked,
        "debit_primary_kg": float(end["o2_consumed_fire_kg_total"]), "debit_room_inventory_kg": float(end["o2_consumed_bulk_kg_total"]),
        "never_debited_kg": asked - float(end["o2_consumed_fire_kg_total"]),
        "lowest_room_number": min(float(row["o2"]) for row in stress if row["room_id"] == "0")}
    closed_e, reopen_e, stress_e = evidence["o2_closed"], evidence["o2_reopen_300"]["after_300_s"], evidence["o2_stress_cap"]
    return _verdict({
        "door_closed_room_inventory_not_debited": closed_e["debit_room_inventory_kg"] < 1.0e-6 and closed_e["debit_primary_kg"] > 1.0,
        "door_closed_room_number_changes_unexplained": abs(closed_e["unexplained_kg"]) > 1.0 and closed_e["zone_sync_kg"] == 0.0,
        "reopened_room_inventory_debited": reopen_e["debit_room_inventory_kg"] > 1.0,
        "reopened_second_write_at_least_half": reopen_e["second_write_kg"] >= 0.5 * reopen_e["debit_room_inventory_kg"],
        "reopened_fire_reads_lower_while_sink_debits_room":
            reopen_e["seconds_with_fire_reading_the_lower_number_and_sink_debiting_the_room"] > 0,
        "reopened_house_closes_within_0.01_kg": abs(reopen_e["house_closure_gap_kg"]) <= 0.01,
        "stress_heat_asks_more_than_was_debited": stress_e["never_debited_kg"] > 1.0,
    }, evidence)


def basis() -> dict:
    """Arithmetic of the two fractions, no engine involved. Dry air is the stated assumption."""
    mass_fraction = AMBIENT * M_O2 / M_DRY_AIR
    return {
        "mole_fraction_of_the_engine_at_start": AMBIENT, "molar_mass_o2_g_mol": M_O2, "molar_mass_dry_air_g_mol": M_DRY_AIR,
        "mass_fraction_that_corresponds": mass_fraction, "ratio_mass_over_mole_fraction": M_O2 / M_DRY_AIR,
        "kg_o2_per_m3_the_engine_holds": AMBIENT * 1.2, "kg_o2_per_m3_of_dry_air_at_1.2_kg_m3": mass_fraction * 1.2,
        "inventory_short_by_fraction": 1.0 - M_DRY_AIR / M_O2,
        "assumption": "dry air of molar mass 28.9647 g/mol; the engine carries no humidity and no composition of its gas, "
                      "so the molar mass of a burnt mixture is unknown to it",
    }


# ---------------------------------------------------------------- main

def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def _head() -> str:
    return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def run_fixture() -> dict:
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    run = godot_monitored_launch.run([godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
                                     timeout_s=1200, environment=os.environ.copy())
    if not run.launched or run.faults or run.preexisting:
        raise RuntimeError(f"not a healthy run: {run.faults or run.preexisting}")
    if "SCRIPT ERROR" in run.stdout + run.stderr or "Parse Error" in run.stdout + run.stderr:
        raise RuntimeError("script error in the diagnostic fixture:\n" + (run.stdout + run.stderr)[-3000:])
    line = next((line for line in run.stdout.splitlines() if line.startswith(PREFIX + " {")), None)
    if line is None or run.returncode != 0:
        raise RuntimeError("the diagnostic fixture did not complete:\n" + (run.stdout + run.stderr)[-3000:])
    return json.loads(line.split(" ", 1)[1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--identity-run", type=Path, help="existing switch-off identity run with the house cases")
    parser.add_argument("--raw", type=Path, help="where to keep the raw rows of the fixture (outside the repository)")
    parser.add_argument("--from-raw", type=Path, help="evaluate rows kept by an earlier run instead of launching Godot")
    args = parser.parse_args()
    plan = {name: dict(item) for name, item in HYPOTHESES.items()}
    if args.plan_only:
        print(json.dumps({"hypotheses": plan, "executed": False}, indent=1))
        return 0
    payload = json.loads(args.from_raw.read_text(encoding="utf-8")) if args.from_raw else run_fixture()
    if args.raw and not args.from_raw:
        args.raw.write_text(json.dumps(payload), encoding="utf-8")
    verdicts = evaluate(payload["cases"])
    if args.identity_run:
        verdicts["H13_house_cases_already_run"] = existing_runs(args.identity_run)
    else:
        verdicts["H13_house_cases_already_run"] = _verdict({}, {"why": "no identity run was given"}, exercised=False)
    hypotheses = {name: {**plan[name], **verdicts[name]} for name in HYPOTHESES}
    as_predicted = {name: item["holds"] == item["predicted"] for name, item in hypotheses.items()}
    record = {
        "schema": SCHEMA, "head": _head(),
        "scope": "what each oxygen number of the engine does; diagnosis, not acceptance; no engine file changed",
        "kilograms": "three kinds, never added: `ref` (a number x volume x 1.2 kg/m3), `layers_ref` (layer numbers on "
                     "geometric shares of that base) and `layers_gas` (layer numbers on the layer gas masses)",
        "sources_sha256": {relative: _sha(ROOT / relative) for relative in SOURCES},
        "fixture_notes": payload["notes"],
        "launches": {
            "count": 3,
            "first": "discarded whole: the fixture loaded its rooms before the building entered the tree, the building "
                     "then loaded the product preset over them, and what ran was the product house",
            "second": "the bench of the controlled-demand cases was armed but its clock never started, because the "
                      "fixture did not raise the ignition event of the engine: H04, H10 and H11 were not exercised; "
                      "the cases without a bench gave the figures of the third launch",
            "third": "this record",
            "what_changed_between_launches": "the fixture (load order, the ignition event, the ledger of writers and "
                                             "the sub-steps alone). No hypothesis was changed. H15 was added after the "
                                             "first launch and before its case ran. The evaluation of one claim of H05 "
                                             "was corrected after the second: it summed two rooms whose lags cancel.",
        },
        "as_predicted": as_predicted, "all_as_predicted": all(as_predicted.values()),
        "not_as_predicted": sorted(name for name, same in as_predicted.items() if not same),
        "basis_of_the_fraction": basis(),
        "hypotheses": hypotheses,
        "setups": {name: case["setup"] for name, case in payload["cases"].items() if "setup" in case},
    }
    saved = ROOT / RECORD
    saved.write_bytes((json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    for name, item in hypotheses.items():
        failed = sorted(claim for claim, value in item.get("claims", {}).items() if not value)
        print(f"{name}: holds={item['holds']} exercised={item.get('exercised')} claims not met={failed}")
    print("not as predicted:", record["not_as_predicted"])
    print(saved.relative_to(ROOT).as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
