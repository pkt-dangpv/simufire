"""Analyzer of the engine balance observables (``g3_balance_v1``). No Godot.

A synthetic step is built here with its own arithmetic, following the rules
the engine records, so that it closes in fuel, pool, species, oxygen and
tracer. Each test then changes one thing and requires the finding that names
it. Requested, applied and inventory values are separate fields on purpose: a
test that only copies the same number into two fields must NOT pass as
conservation.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
import re
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "simulation"))

import analyze_g3_balance_ledger as bal  # noqa: E402

DT = 1.0 / 12.0
RATE = 0.076
C_PER_MJ = 0.027
AIR, UPPER_AIR, LOWER_AIR = 57.6, 20.0, 37.6
FIXTURE = ROOT / "tests" / "fixtures" / "g3_balance_v1_sample.jsonl"
SIM_FILES = ("sim/fire/CombustionSystem.gd", "sim/core/OxygenExchangeSystem.gd", "sim/core/SimulationEngine.gd")


def make_row(*, time_s=10.0, solid_kw=40.0, target_kw=50.0, pyrolysis_kw=60.0, pool_before=1.0,
             pool_burn_kw=0.0, smoke_yield=0.012, co_yield=0.001, co2_yield=0.08, carbon_per_MJ=C_PER_MJ,
             state=None) -> dict:
    """One flaming, O2-limited step of a sealed room that closes everywhere."""
    generation_kw = 0.30 * max(0.0, pyrolysis_kw - target_kw)
    consumed = pyrolysis_kw * DT / 1000.0
    heat_MJ = (solid_kw + pool_burn_kw) * DT / 1000.0
    # pool
    capacity = 24.0
    after_credit = min(capacity, pool_before + generation_kw * DT / 1000.0)
    after_burn = max(0.0, after_credit - pool_burn_kw * DT / 1000.0)
    opening, temp = 0.0, 0.5
    after_decay = max(0.0, after_burn - after_burn * 0.0025 * (1.0 + 1.5 * opening + 0.5 * (1.0 - temp)) * DT)
    # species
    multiplier = 1.1
    retained_smoke, pool_smoke = 0.38 * generation_kw, 0.42 * pool_burn_kw
    smoke_basis = max(solid_kw, target_kw * multiplier) + retained_smoke + pool_smoke
    smoke_kg = smoke_basis / 1000.0 * smoke_yield * DT
    retained_co, pool_co = 0.08 * generation_kw, 0.40 * pool_burn_kw
    co_basis = solid_kw + pool_co + retained_co
    co_req = co_yield * co_basis * DT / 1000.0
    hcn_yield = 4e-5
    hcn_req = hcn_yield * co_basis * DT / 1000.0
    smoke_term = 0.60 * smoke_basis * DT / 1000.0
    co2_req = co2_yield * max(heat_MJ, smoke_term)
    c_available = carbon_per_MJ * consumed
    c_requested = co_req * 12 / 28 + co2_req * 12 / 44 + hcn_req * 12 / 27
    acts = c_available > 0.0 and c_requested > c_available
    scale = c_available / c_requested if acts else 1.0
    co_app, co2_app, hcn_app = co_req * scale, co2_req * scale, hcn_req * scale
    # oxygen: sealed room, plume route for the fire and the upper displacement sink
    hrr = solid_kw + pool_burn_kw
    o2_lower, o2_upper, o2_bulk = 0.15, 0.10, 0.13
    plume_req = hrr / 1000.0 * RATE * DT
    plume_cap = LOWER_AIR * o2_lower * 0.05
    plume_app = min(plume_req, plume_cap)
    upper_req = hrr / 1000.0 * RATE * DT * 0.09
    upper_cap = UPPER_AIR * o2_upper * 0.20
    upper_app = min(upper_req, upper_cap)
    ach = 1e-6
    bulk_unclamped = (o2_bulk * AIR + ach) / AIR
    # tracer
    tracer_before, tracer_yield, o2_scale = 0.05, 0.0831, o2_upper / 0.209
    produced = hrr / 1000.0 * tracer_yield * DT * o2_scale
    delta = produced * 29.0 / (UPPER_AIR * 44.0)
    tracer_ach = -1e-9
    tracer_after = min(0.30, max(0.0004, tracer_before + delta + tracer_ach))

    base = state or {
        "pool_MJ": pool_before, "o2": o2_bulk, "o2_upper": o2_upper, "o2_lower": o2_lower,
        "co2_upper_tracer": tracer_before, "co_kg": 0.2, "co_upper_kg": 0.15, "co2_kg": 3.0,
        "co2_upper_kg": 2.5, "hcn_kg": 0.01, "hcn_upper_kg": 0.008, "hcl_kg": 0.0, "acrolein_kg": 0.0,
        "formaldehyde_kg": 0.0, "smoke_kg": 1.0, "hrr_kw": hrr, "fuel_consumed_MJ_total": 50.0,
        "hrr_kj_total": 40000.0,
    }
    before = dict(base)
    inventory_before = {key: before[key] for key in
                        ("co_kg", "co_upper_kg", "co2_kg", "co2_upper_kg", "hcn_kg", "hcn_upper_kg")}
    inventory_after = dict(inventory_before)
    for name, amount in (("co", co_app), ("co2", co2_app), ("hcn", hcn_app)):
        inventory_after[f"{name}_kg"] += amount
        inventory_after[f"{name}_upper_kg"] += amount
    after = dict(before)
    after.update(inventory_after)
    after.update({
        "pool_MJ": after_decay, "o2": bulk_unclamped,
        "o2_upper": o2_upper - upper_app / UPPER_AIR, "o2_lower": o2_lower - plume_app / LOWER_AIR,
        "co2_upper_tracer": tracer_after, "smoke_kg": before["smoke_kg"] + smoke_kg,
        "fuel_consumed_MJ_total": before["fuel_consumed_MJ_total"] + consumed,
        "hrr_kj_total": before["hrr_kj_total"] + heat_MJ * 1000.0,
        "step": {
            "smoke_generated_kg": smoke_kg, "smoke_vented_kg": 0.0, "smoke_deposited_kg": 0.0,
            "smoke_net_transport_kg": 0.0, "co_generated_kg": co_app, "co2_generated_kg": co2_app,
            "hcn_generated_kg": hcn_app, "o2_consumed_all_kg": plume_app + upper_app,
            "o2_consumed_bulk_kg": 0.0, "o2_consumed_fire_kg": plume_app, "o2_exterior_net_kg": ach,
            "o2_net_transport_kg": 0.0, "o2_zone_sync_kg": 0.0, "fuel_consumed_MJ": consumed,
        },
    })
    return {
        "schema_version": "g3_fuel_ledger_v3", "bal_schema": bal.SCHEMA, "room_id": 0, "time_s": time_s,
        "dt_s": DT, "fire_present_before": True, "ownership_mode": "explicit_owned",
        "consumed_MJ": consumed, "hrr_applied_kw": hrr,
        "objects": [{"id": "sofa", "is_proxy": False, "remaining_before_MJ": 80.0,
                     "remaining_after_MJ": 80.0 - consumed}],
        "bal_state_before": before, "bal_state_after": after,
        "bal_fuel": {
            "can_flame": True, "latent_viable": False, "o2_extinguished": False, "flame_drive": 0.5,
            "o2_hrr_factor": 0.5, "pyrolysis_MJ": consumed, "flame_target_MJ": target_kw * DT / 1000.0,
            "smolder_target_MJ": 0.0, "pool_generation_MJ": generation_kw * DT / 1000.0,
            "unburned_generation_fraction": 0.30,
            "unburned_without_inventory_MJ": (pyrolysis_kw - target_kw - generation_kw) * DT / 1000.0,
            "physical_inventory": False, "solid_heat_MJ": solid_kw * DT / 1000.0,
            "pool_heat_MJ": pool_burn_kw * DT / 1000.0, "release_from_R_MJ": 0.0,
        },
        "bal_pool": {
            "before_MJ": pool_before, "credit_requested_MJ": generation_kw * DT / 1000.0,
            "capacity_MJ": capacity, "after_credit_MJ": after_credit,
            "burn_requested_MJ": pool_burn_kw * DT / 1000.0, "after_burn_MJ": after_burn,
            "decay_per_s": 0.0025, "opening_signal": opening, "temp_signal": temp,
            "after_decay_MJ": after_decay, "backdraft_active": False, "backdraft_hrr_kw": hrr,
            "after_backdraft_MJ": after_decay,
        },
        "bal_species": {
            "committed": True,
            "smoke": {"solid_heat_term_kw": solid_kw, "flame_target_kw": target_kw, "smolder_target_kw": 0.0,
                      "basis_multiplier": multiplier, "retained_term_kw": retained_smoke,
                      "pool_term_kw": pool_smoke, "basis_kw": smoke_basis, "yield_base_kg_per_MJ": smoke_yield,
                      "yield_kg_per_MJ": smoke_yield, "requested_kg": smoke_kg},
            "co": {"solid_heat_term_kw": solid_kw, "pool_term_kw": pool_co, "retained_term_kw": retained_co,
                   "smolder_target_kw": 0.0, "basis_kw": co_basis, "phi": 2.0, "yield_base_kg_per_MJ": 0.0004,
                   "yield_kg_per_MJ": co_yield, "requested_kg": co_req, "applied_kg": co_app,
                   "applied_upper_kg": co_app},
            "hcn": {"basis_kw": co_basis, "yield_base_kg_per_MJ": 4e-5, "yield_kg_per_MJ": hcn_yield,
                    "requested_kg": hcn_req, "applied_kg": hcn_app},
            "co2": {"heat_term_MJ": heat_MJ, "smoke_basis_term_MJ": smoke_term, "yield_base_kg_per_MJ": 0.0831,
                    "yield_min_kg_per_MJ": 0.0594, "yield_kg_per_MJ": co2_yield, "requested_kg": co2_req,
                    "applied_kg": co2_app},
            "carbon_clamp": {"c_kg_per_MJ": carbon_per_MJ, "fuel_debit_MJ": consumed, "release_from_R_MJ": 0.0,
                             "c_available_kg": c_available, "c_clamp_kg": c_available,
                             "c_requested_gas_kg": c_requested, "c_in_soot_kg": 0.87 * smoke_kg,
                             "soot_inside_clamp": False, "applied": acts, "scale": scale},
            "irritants": {"basis_kw": co_basis, "hcl_before_kg": 0.0, "hcl_after_kg": 0.0,
                          "hcl_yield_kg_per_MJ": 0.0, "acrolein_before_kg": 0.0, "acrolein_after_kg": 0.0,
                          "acrolein_yield_kg_per_MJ": 0.0, "formaldehyde_before_kg": 0.0,
                          "formaldehyde_after_kg": 0.0, "formaldehyde_yield_kg_per_MJ": 0.0},
            "inventory_before": inventory_before, "inventory_after": inventory_after,
        },
        "bal_o2": {
            "hrr_kw": hrr, "o2_kg_per_MJ": RATE, "air_mass_kg": AIR, "upper_air_mass_kg": UPPER_AIR,
            "lower_air_mass_kg": LOWER_AIR, "o2_nominal": 0.209, "o2_before": o2_bulk,
            "o2_upper_before": o2_upper, "o2_lower_before": o2_lower,
            "sinks": {
                "upper": {"zone": "upper", "branch": "displacement", "displacement_frac": 0.09,
                          "requested_kg": upper_req, "cap_kg": upper_cap, "applied_kg": upper_app,
                          "fraction_before": o2_upper, "fraction_after": o2_upper - upper_app / UPPER_AIR,
                          "mass_base_kg": UPPER_AIR},
                "plume_lower": {"zone": "lower", "depletion_fraction": 1.0, "requested_kg": plume_req,
                                "cap_kg": plume_cap, "cap_mass_base_kg": LOWER_AIR, "applied_kg": plume_app,
                                "fraction_before": o2_lower, "fraction_after": o2_lower - plume_app / LOWER_AIR,
                                "mass_base_kg": LOWER_AIR},
            },
            "bulk_ach_kg": ach, "bulk_fraction_before_write": o2_bulk, "bulk_fraction_unclamped": bulk_unclamped,
            "bulk_fraction_after_write": bulk_unclamped, "fire_primary_kg": plume_app,
            "phase2b_upper_active": False, "plume_lower_mode": True, "o2_after": bulk_unclamped,
            "o2_upper_after": o2_upper - upper_app / UPPER_AIR, "o2_lower_after": o2_lower - plume_app / LOWER_AIR,
        },
        "bal_co2_tracer": {
            "branch": "production", "fraction_before": tracer_before, "hrr_kw": hrr, "mass_base_kg": UPPER_AIR,
            "room_co2_kg": 3.0, "room_co2_upper_kg": 2.5, "subc_boost_active": False,
            "yield_kg_per_MJ": tracer_yield, "o2_scale": o2_scale, "produced_kg": produced,
            "delta_fraction": delta, "ach_delta_fraction": tracer_ach,
            "fraction_before_clamp": tracer_before + delta + tracer_ach, "fraction_after": tracer_after,
        },
    }


def analyze(*rows: dict) -> dict:
    return bal.analyze_rows(iter(rows))


def codes(*rows: dict) -> set[str]:
    return {finding["code"] for finding in analyze(*rows)["findings"]}


# ------------------------------------------------------------------ the closing step

def test_the_closing_step_has_no_finding():
    report = analyze(make_row())
    assert report["findings"] == []
    assert report["counts"]["steps"] == 1


def test_the_closing_step_with_the_carbon_clamp_acting_has_no_finding():
    row = make_row(carbon_per_MJ=0.005)
    assert row["bal_species"]["carbon_clamp"]["applied"] is True
    report = analyze(row)
    assert report["findings"] == []
    assert report["counts"]["carbon_clamp_steps"] == 1
    assert report["terms"]["carbon_clamp_removed_kg"] > 0.0


def test_the_closing_step_with_a_truncated_o2_debit_has_no_finding_and_declares_it():
    row = make_row(solid_kw=60000.0, target_kw=60000.0, pyrolysis_kw=60000.0)
    sink = row["bal_o2"]["sinks"]["plume_lower"]
    assert sink["applied_kg"] < sink["requested_kg"]
    report = analyze(row)
    assert report["findings"] == []
    assert report["terms"]["o2_fire_truncated_kg"] == pytest.approx(sink["requested_kg"] - sink["applied_kg"])
    assert report["counts"]["o2_truncated_steps_plume_lower"] == 1


# -------------------------------------------- the four mutations the brief asks for

def _pool_loss_without_record(row):
    row["bal_state_after"]["pool_MJ"] -= 0.001


def _carbon_scale_not_recorded(row):
    clamp = row["bal_species"]["carbon_clamp"]
    assert clamp["applied"] is True
    clamp["applied"], clamp["scale"] = False, 1.0


def _o2_truncated_without_declaring(row):
    sink = row["bal_o2"]["sinks"]["plume_lower"]
    sink["applied_kg"] *= 0.5
    sink["fraction_after"] = sink["fraction_before"] - sink["applied_kg"] / sink["mass_base_kg"]
    row["bal_o2"]["o2_lower_after"] = sink["fraction_after"]
    row["bal_o2"]["fire_primary_kg"] = sink["applied_kg"]
    step = row["bal_state_after"]["step"]
    step["o2_consumed_fire_kg"] = sink["applied_kg"]
    step["o2_consumed_all_kg"] = sink["applied_kg"] + row["bal_o2"]["sinks"]["upper"]["applied_kg"]


def _co_on_the_wrong_basis(row):
    co = row["bal_species"]["co"]
    co["basis_kw"] = 50.0 + co["pool_term_kw"] + co["retained_term_kw"]
    co["requested_kg"] = co["yield_kg_per_MJ"] * co["basis_kw"] * DT / 1000.0


def _smoke_on_the_wrong_basis(row):
    smoke = row["bal_species"]["smoke"]
    smoke["basis_kw"] = smoke["solid_heat_term_kw"]
    smoke["requested_kg"] = smoke["basis_kw"] / 1000.0 * smoke["yield_kg_per_MJ"] * DT


REQUIRED = [
    ("baja del depósito omitida", {}, _pool_loss_without_record, "P_unrecorded_change"),
    ("escala de carbono no registrada", {"carbon_per_MJ": 0.005}, _carbon_scale_not_recorded,
     "S_carbon_scale_unrecorded"),
    ("O2 truncado sin declarar", {}, _o2_truncated_without_declaring, "O_truncation_undeclared"),
    ("base del CO equivocada", {}, _co_on_the_wrong_basis, "S_co_basis_rule"),
    ("base del humo equivocada", {}, _smoke_on_the_wrong_basis, "S_smoke_basis_rule"),
]


@pytest.mark.parametrize("label,options,mutate,code", REQUIRED, ids=[item[0] for item in REQUIRED])
def test_required_mutation_is_named(label, options, mutate, code):
    row = make_row(**options)
    assert analyze(row)["findings"] == []
    mutate(row)
    assert code in codes(row), label


# --------------------------------------------------------- one term, one named finding

def _set(path, value):
    def mutate(row):
        target = row
        for key in path[:-1]:
            target = target[key]
        target[path[-1]] = value(target[path[-1]]) if callable(value) else value
    return mutate


ONE_TERM = [
    ("object debit", _set(("objects", 0, "remaining_after_MJ"), lambda v: v + 1e-4), "F_debit_inventory"),
    ("fuel counter", _set(("bal_state_after", "fuel_consumed_MJ_total"), lambda v: v + 1e-4), "F_debit_counter"),
    ("pyrolysis without debit", _set(("bal_fuel", "pyrolysis_MJ"), lambda v: v * 1.5), "F_pyrolysis_without_debit"),
    ("pool generation rule", _set(("bal_fuel", "pool_generation_MJ"), lambda v: v * 2.0), "F_generation_rule"),
    ("U wrongly derived", _set(("bal_fuel", "unburned_without_inventory_MJ"), lambda v: v * 0.5), "F_U_definition"),
    ("U presented as inventory", _set(("bal_fuel", "physical_inventory"), True), "F_U_definition"),
    ("heat split", _set(("bal_fuel", "solid_heat_MJ"), lambda v: v * 0.9), "F_heat_split"),
    ("heat counter", _set(("bal_state_after", "hrr_kj_total"), lambda v: v + 1.0), "F_heat_counter"),
    ("pool entry", _set(("bal_pool", "before_MJ"), lambda v: v + 0.01), "P_entry_continuity"),
    ("pool credit", _set(("bal_pool", "after_credit_MJ"), lambda v: v - 1e-5), "P_credit_write"),
    ("pool decay", _set(("bal_pool", "decay_per_s"), 0.01), "P_decay_write"),
    ("pool backdraft", _set(("bal_pool", "backdraft_active"), True), "P_backdraft_write"),
    ("smoke request", _set(("bal_species", "smoke", "requested_kg"), lambda v: v * 1.2), "S_smoke_request"),
    ("smoke not added", _set(("bal_state_after", "step", "smoke_generated_kg"), 0.0), "S_smoke_not_applied"),
    ("CO request", _set(("bal_species", "co", "requested_kg"), lambda v: v * 1.2), "S_co_request"),
    ("HCN request", _set(("bal_species", "hcn", "requested_kg"), lambda v: v * 1.2), "S_hcn_request"),
    ("CO2 request", _set(("bal_species", "co2", "requested_kg"), lambda v: v * 1.2), "S_co2_request"),
    ("CO2 heat term", _set(("bal_species", "co2", "heat_term_MJ"), lambda v: v * 1.2), "S_co2_terms"),
    ("carbon available", _set(("bal_species", "carbon_clamp", "c_available_kg"), lambda v: v * 2.0),
     "S_carbon_available"),
    ("carbon scale rule", _set(("bal_species", "carbon_clamp", "scale"), 0.5), "S_carbon_scale_rule"),
    ("species counter", _set(("bal_state_after", "step", "co_generated_kg"), 0.0), "S_generated_counter"),
    ("O2 request", _set(("bal_o2", "sinks", "plume_lower", "requested_kg"), lambda v: v * 2.0), "O_request"),
    ("O2 heat seen", _set(("bal_o2", "hrr_kw"), 0.0), "O_heat_seen"),
    ("O2 primary", _set(("bal_o2", "fire_primary_kg"), 0.0), "O_primary"),
    ("O2 counters", _set(("bal_state_after", "step", "o2_consumed_all_kg"), 0.0), "O_counters"),
    ("tracer production", _set(("bal_co2_tracer", "produced_kg"), lambda v: v * 2.0), "T_production"),
    ("tracer chain", _set(("bal_co2_tracer", "fraction_after"), lambda v: v + 1e-4), "T_chain"),
    ("missing block", lambda row: row.pop("bal_pool"), "X_missing_block"),
]


@pytest.mark.parametrize("label,mutate,code", ONE_TERM, ids=[item[0] for item in ONE_TERM])
def test_changing_one_term_raises_the_finding_that_names_it(label, mutate, code):
    row = make_row()
    mutate(row)
    assert code in codes(row), label


# ------------------------- copied fields are not conservation: inventory must move

def test_applied_equal_to_requested_does_not_prove_the_species_inventory_moved():
    row = make_row()
    species = row["bal_species"]
    assert species["co"]["applied_kg"] == species["co"]["requested_kg"]
    species["inventory_after"]["co_kg"] = species["inventory_before"]["co_kg"]
    assert "S_inventory_write" in codes(row)


def test_applied_o2_does_not_prove_the_zone_inventory_moved():
    row = make_row()
    sink = row["bal_o2"]["sinks"]["plume_lower"]
    sink["fraction_after"] = sink["fraction_before"]
    report = analyze(row)
    assert "O_inventory" in {f["code"] for f in report["findings"]}
    assert report["terms"]["o2_fire_applied_kg"] > report["terms"]["o2_fire_inventory_change_kg"]


def test_a_zone_fraction_lowered_with_the_room_mass_is_named():
    row = make_row()
    sink = row["bal_o2"]["sinks"]["plume_lower"]
    sink["mass_base_kg"] = AIR
    sink["fraction_after"] = sink["fraction_before"] - sink["applied_kg"] / AIR
    report = analyze(row)
    finding = next(f for f in report["findings"] if f["code"] == "O_zone_mass_base")
    assert finding["details"] == ["plume_lower"]
    assert finding["amount"] == pytest.approx(sink["applied_kg"] * (1.0 - LOWER_AIR / AIR))
    assert report["terms"]["o2_fire_zone_mass_change_kg"] == pytest.approx(sink["applied_kg"] * LOWER_AIR / AIR)
    assert "O_inventory" not in {f["code"] for f in report["findings"]}


def test_room_loop_o2_mass_drops_are_reported_in_both_representations():
    terms = analyze(make_row())["terms"]
    sinks = terms["o2_fire_applied_kg"] + terms["o2_non_fire_applied_kg"]
    assert terms["o2_room_loop_zonal_mass_drop_kg"] == pytest.approx(sinks)
    assert terms["o2_room_loop_bulk_mass_drop_kg"] == pytest.approx(-terms["o2_bulk_ach_kg"])


def test_upper_zone_species_write_is_checked_separately():
    row = make_row()
    row["bal_species"]["inventory_after"]["co2_upper_kg"] = row["bal_species"]["inventory_before"]["co2_upper_kg"]
    finding = next(f for f in analyze(row)["findings"] if f["code"] == "S_inventory_write")
    assert finding["details"] == ["co2 zona superior"]


# ---------------------------------------------------------------------- pool losses

def test_each_pool_loss_lands_in_its_own_term():
    row = make_row(pool_burn_kw=5.0)
    terms = analyze(row)["terms"]
    pool = row["bal_pool"]
    assert terms["pool_loss_burn_MJ"] == pytest.approx(5.0 * DT / 1000.0)
    assert terms["pool_loss_decay_MJ"] == pytest.approx(pool["after_burn_MJ"] - pool["after_decay_MJ"])
    assert terms["pool_loss_cap_MJ"] == pytest.approx(0.0, abs=1e-15)
    assert terms["pool_loss_backdraft_MJ"] == 0.0
    assert terms["pool_closure_MJ"] == pytest.approx(0.0, abs=1e-12)


def test_capacity_truncation_is_a_loss_of_its_own():
    row = make_row(pool_before=23.9999999)
    pool = row["bal_pool"]
    assert pool["after_credit_MJ"] == pool["capacity_MJ"]
    report = analyze(row)
    assert report["findings"] == []
    assert report["terms"]["pool_loss_cap_MJ"] > 0.0
    assert report["terms"]["pool_credit_applied_MJ"] < report["terms"]["pool_credit_requested_MJ"]


def test_suppression_and_burnout_are_separate_pool_losses():
    row = make_row()
    start = row["bal_pool"]["after_backdraft_MJ"]
    row["bal_suppression"] = {"hrr_factor": 0.5, "pool_before_MJ": start,
                              "pool_after_MJ": start * (0.30 + 0.70 * 0.5), "hrr_before_kw": 40.0,
                              "hrr_after_kw": 20.0, "water_l": 1.0}
    row["bal_state_after"]["pool_MJ"] = row["bal_suppression"]["pool_after_MJ"]
    report = analyze(row)
    assert "P_suppression_write" not in {f["code"] for f in report["findings"]}
    assert report["terms"]["pool_loss_suppression_MJ"] == pytest.approx(start * 0.35)

    burned = make_row()
    burned["bal_extinction"] = {"burned_out": True, "pool_before_MJ": burned["bal_pool"]["after_backdraft_MJ"]}
    burned["bal_state_after"]["pool_MJ"] = 0.0
    terms = analyze(burned)["terms"]
    assert terms["pool_loss_burnout_reset_MJ"] == pytest.approx(burned["bal_pool"]["after_backdraft_MJ"])
    assert "pool_loss_unrecorded_MJ" not in terms


def test_a_suppression_factor_that_does_not_explain_the_loss_is_named():
    row = make_row()
    start = row["bal_pool"]["after_backdraft_MJ"]
    row["bal_suppression"] = {"hrr_factor": 0.5, "pool_before_MJ": start, "pool_after_MJ": start * 0.1}
    row["bal_state_after"]["pool_MJ"] = start * 0.1
    assert "P_suppression_write" in codes(row)


def test_a_pool_left_without_fire_is_counted_as_held_not_as_lost():
    row = make_row()
    for block in ("bal_fuel", "bal_pool", "bal_species"):
        row.pop(block)
    row["fire_present_before"] = False
    row["consumed_MJ"] = row["hrr_applied_kw"] = 0.0
    row["objects"] = []
    after, before = row["bal_state_after"], row["bal_state_before"]
    after["pool_MJ"] = before["pool_MJ"]
    after["fuel_consumed_MJ_total"] = before["fuel_consumed_MJ_total"]
    row["bal_o2"]["hrr_kw"] = 0.0
    row["bal_o2"]["sinks"] = {}
    row["bal_o2"]["fire_primary_kg"] = 0.0
    after["step"]["o2_consumed_all_kg"] = after["step"]["o2_consumed_fire_kg"] = 0.0
    report = analyze(row)
    assert report["counts"]["pool_positive_without_fire_steps"] == 1
    assert report["terms"]["pool_held_without_fire_MJ_s"] == pytest.approx(before["pool_MJ"] * DT)
    assert not {f["code"] for f in report["findings"]} & {"P_unrecorded_change", "X_missing_block"}


def test_a_pool_change_between_steps_has_an_unknown_owner():
    first = make_row(time_s=1.0)
    state = {key: value for key, value in first["bal_state_after"].items() if key != "step"}
    second = make_row(time_s=1.0 + DT, pool_before=state["pool_MJ"] - 0.002, state=dict(state))
    second["bal_state_before"]["pool_MJ"] = state["pool_MJ"] - 0.002
    report = analyze(first, second)
    finding = next(f for f in report["findings"] if f["code"] == "P_between_steps")
    assert finding["owner"].startswith("desconocido")
    assert finding["amount"] == pytest.approx(-0.002)


# ----------------------------------------------------------------------- U and carbon

def test_u_is_reported_without_inventory_and_never_as_a_resolved_loss():
    row = make_row()
    report = analyze(row)
    expected = (60.0 - 50.0) * 0.70 * DT / 1000.0
    assert report["U_without_inventory"]["MJ"] == pytest.approx(expected)
    assert report["U_without_inventory"]["physical_inventory"] is False
    assert report["terms"]["U_while_flaming_MJ"] == pytest.approx(expected)
    assert not any("loss" in name and "U" in name for name in report["terms"])


def test_soot_carbon_is_counted_outside_the_clamp():
    report = analyze(make_row(carbon_per_MJ=0.005))
    terms = report["terms"]
    assert terms["carbon_in_gases_kg"] == pytest.approx(terms["carbon_available_kg"])
    assert terms["carbon_products_minus_fuel_kg"] == pytest.approx(terms["carbon_in_soot_added_kg"])
    assert terms["carbon_products_minus_fuel_kg"] > 0.0


def test_smoke_and_co2_requested_above_the_heat_are_measured():
    terms = analyze(make_row(solid_kw=10.0, target_kw=50.0, pyrolysis_kw=50.0))["terms"]
    assert terms["smoke_requested_above_heat_kg"] > terms["smoke_requested_on_heat_kg"]
    assert terms["co2_requested_above_heat_kg"] > 0.0
    assert terms["smoke_basis_above_heat_MJ"] == pytest.approx((50.0 * 1.1 - 10.0) * DT / 1000.0)


def test_the_two_co2_accounts_are_compared_not_reconciled():
    terms = analyze(make_row())["terms"]
    assert terms["co2_tracer_produced_kg"] > 0.0
    assert terms["co2_tracer_minus_mass_applied_kg"] == pytest.approx(
        terms["co2_tracer_produced_kg"] - terms["co2_applied_kg"])
    assert terms["co2_two_accounts_largest_gap_kg"] != 0.0


def test_non_fire_o2_sink_is_kept_apart_from_the_fire_debit():
    terms = analyze(make_row())["terms"]
    assert terms["o2_non_fire_applied_kg"] == pytest.approx(0.09 * terms["o2_fire_applied_kg"])
    assert terms["o2_fire_debit_minus_thornton_kg"] == pytest.approx(0.0, abs=1e-15)


def test_early_extinction_shows_heat_and_smoke_that_were_cancelled():
    row = make_row()
    row["bal_species"] = {"committed": False, "smoke": row["bal_species"]["smoke"]}
    row["bal_extinction"] = {"burned_out": False, "pool_before_MJ": row["bal_pool"]["after_backdraft_MJ"]}
    row["consumed_MJ"] = 0.0
    row["objects"][0]["remaining_after_MJ"] = 80.0
    after = row["bal_state_after"]
    after["fuel_consumed_MJ_total"] = row["bal_state_before"]["fuel_consumed_MJ_total"]
    after["hrr_kj_total"] = row["bal_state_before"]["hrr_kj_total"]
    after["step"]["smoke_generated_kg"] = 0.0
    row["bal_o2"]["hrr_kw"] = 0.0
    row["bal_o2"]["sinks"] = {}
    row["bal_o2"]["fire_primary_kg"] = 0.0
    after["step"]["o2_consumed_all_kg"] = after["step"]["o2_consumed_fire_kg"] = 0.0
    report = analyze(row)
    found = {f["code"]: f for f in report["findings"]}
    for code in ("F_pyrolysis_without_debit", "F_heat_counter", "S_smoke_not_applied", "O_heat_seen"):
        assert found[code]["details"] == ["extinción"], code
    assert report["counts"]["species_uncommitted_steps"] == 1


def test_tolerances_are_fixed_in_the_analyzer():
    assert (bal.ABS_TOL, bal.REL_TOL) == (1e-12, 1e-9)


def test_every_finding_has_unit_owner_and_text():
    for code, (unit, owner, text) in bal.FINDINGS.items():
        assert unit and owner and text, code
    report = analyze(make_row())
    assert report["schema"] == "g3_balance_v1"


def test_case_reader_streams_one_room(tmp_path):
    rows = [make_row(time_s=1.0), dict(make_row(time_s=1.0), room_id=1)]
    ledger = tmp_path / bal.LEDGER
    ledger.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
    assert bal.analyze_case(tmp_path, 0)["counts"]["steps"] == 1
    assert bal.main(["--case", f"x={tmp_path}", "--out", str(tmp_path / "out")]) == 0
    assert json.loads((tmp_path / "out" / "balance_ledger.json").read_text(encoding="utf-8"))["x"]["findings"] == []


# -------------------------------------------------------- engine rows kept as fixture

@pytest.mark.skipif(not FIXTURE.exists(), reason="fixture of engine rows not generated yet")
def test_real_engine_rows_follow_the_schema():
    rows = [json.loads(line) for line in FIXTURE.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert len(rows) >= 4
    for row in rows:
        assert row["bal_schema"] == bal.SCHEMA
        for block in ("bal_state_before", "bal_state_after", "bal_o2", "bal_co2_tracer"):
            assert block in row
        if row["fire_present_before"]:
            assert row["bal_fuel"]["physical_inventory"] is False
            if row["bal_species"]["committed"]:
                assert row["bal_species"]["carbon_clamp"]["soot_inside_clamp"] is False
            else:
                assert "bal_extinction" in row and "co" not in row["bal_species"]
    book = bal.Book()
    for row in rows:
        bal.check_row(None, row, book)
    write_checks = {"P_credit_write", "P_burn_write", "P_decay_write", "S_inventory_write",
                    "S_carbon_scale_unrecorded", "O_truncation_undeclared", "O_inventory", "S_co_basis_rule",
                    "S_smoke_basis_rule", "T_production", "T_chain", "X_missing_block"}
    assert not write_checks & set(book.findings)
    # What the engine really does, measured on its own rows: the plume route lowers the
    # lower-zone fraction with the whole-room air mass, and the extinction step cancels heat.
    assert book.findings["O_zone_mass_base"]["details"] == ["plume_lower"]
    assert book.findings["O_heat_seen"]["details"] == ["extinción"]
    assert book.counts["species_uncommitted_steps"] == 1
    assert book.counts["o2_truncated_steps_upper"] == 1


# ------------------------------------------------- the instrumentation only reads

GUARDS = ("if g3_fuel_ledger_enabled", "if g3_probe != null", "if combustion_system.g3_fuel_ledger_enabled",
          "if not g3_fuel_ledger_enabled")
STATE_WRITE = re.compile(r"^\s*(room|fire|obj|building|op|proxy)\b[\w.\[\]\"]*\s*(?:[-+*/]?=)(?!=)")


def _guarded_lines(text: str):
    lines = text.split("\n")
    index = 0
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if stripped.startswith(GUARDS) and stripped.endswith(":") and not stripped.startswith("if not"):
            indent = len(line) - len(line.lstrip("\t"))
            index += 1
            while index < len(lines):
                body = lines[index]
                if body.strip() and len(body) - len(body.lstrip("\t")) <= indent:
                    break
                yield index + 1, body
                index += 1
            continue
        index += 1


@pytest.mark.parametrize("relative", SIM_FILES)
def test_guarded_instrumentation_never_writes_simulation_state(relative):
    text = (ROOT / relative).read_text(encoding="utf-8")
    guarded = list(_guarded_lines(text))
    assert guarded, relative
    offenders = [(number, body.strip()) for number, body in guarded if STATE_WRITE.match(body)]
    assert offenders == []


def test_balance_helpers_only_read_the_room():
    text = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
    for name in ("_g3_balance_room_state", "_g3_balance_gas_inventory", "_g3_balance_room_step_counters"):
        body = text.split(f"func {name}(")[1].split("\nfunc ")[0]
        assert not any(STATE_WRITE.match(line) for line in body.split("\n")), name


def test_no_new_switch_the_ledger_flag_is_reused_and_off_by_default():
    combustion = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
    assert "var g3_fuel_ledger_enabled: bool = false\n" in combustion
    for relative in SIM_FILES:
        text = (ROOT / relative).read_text(encoding="utf-8")
        assert not re.search(r"@export var \w*g3_bal\w*", text), relative
        assert not re.search(r"^var \w*balance\w*_enabled", text, flags=re.MULTILINE), relative
    oes = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
    assert 'var g3_probe = hooks.get("g3_balance_probe", null)' in oes
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert engine.count('oxygen_hooks["g3_balance_probe"] = {}') == 1
    assert "\tif combustion_system.g3_fuel_ledger_enabled:\n\t\toxygen_hooks[\"g3_balance_probe\"] = {}\n" in engine


def test_only_the_headless_runner_flag_turns_the_ledger_on():
    users = []
    for path in list((ROOT / "sim").rglob("*.gd")) + list((ROOT / "tools").glob("*.gd")) \
            + list((ROOT / "editor").rglob("*.gd")) + list((ROOT / "ui").rglob("*.gd")):
        if "g3_fuel_ledger_enabled = true" in path.read_text(encoding="utf-8"):
            users.append(path.relative_to(ROOT).as_posix())
    assert users == ["tools/run_scenario_headless.gd"]
    runner = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
    assert 'if not bool(_cli_args.get("g3_fuel_ledger_v3", false)):\n\t\treturn true' in runner


def test_no_scenario_or_template_carries_the_balance_blocks():
    for folder in ("scenarios", "sim/validation"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*.json"):
            assert "g3_balance" not in path.read_text(encoding="utf-8", errors="ignore"), path


def test_copy_of_a_row_is_independent():
    row = make_row()
    clone = copy.deepcopy(row)
    _pool_loss_without_record(clone)
    assert analyze(row)["findings"] == []
