#!/usr/bin/env python3
"""Offline design audit: how the prescribed object HRR source could meet the engine.

Design and feasibility only. It reads the engine as text, the audited series of one
run and the published readings, and computes identities and counterexamples. It adds
no physics, launches nothing, and derives neither fuel mass nor species.

What it pins: the engine facts the design rests on (if one moves, the design must be
read again), what the existing fire route would do to a curve that is declared
reproduced, which oxygen demand the calorimetry supports, and what the run measured
about radiation.

    python -m scripts.simulation.audit_g3_object_hrr_coupling --check
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics

from scripts.simulation import audit_g3_object_fire_source as selection
from scripts.simulation import build_g3_object_hrr_source as builder

ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs" / "validation" / "G3_OBJECT_HRR_COUPLING_INPUTS_2026-10-08.json"
SAVED = ROOT / "docs" / "validation" / "G3_OBJECT_HRR_COUPLING_AUDIT_2026-10-08.json"
MODULE = "sim/fire/PrescribedObjectHrrSource.gd"
SCHEMA = "g3_object_hrr_coupling_design_audit_v1"
HRR = "Heat Release Rate (kW)"
RADIANT = "Radiant Heat Flux (kW/m^2)"
FLOW = "Exhaust Mass Flow Rate (kg/s)"
PRODUCT_FOLDERS = ("sim", "editor", "view", "ui", "scenes", "tools")
OBSERVABLES = (
    "energy_delivered_per_step", "applied_power_unfiltered", "oxygen_debit_per_accepted_energy",
    "oxygen_limited_response", "regime_validity_indicator", "convective_radiative_split",
    "radiation_to_surfaces", "fuel_mass", "species_and_smoke", "fed_and_svv",
    "other_objects_in_the_same_room", "flashover_spread_suppression", "engine_restore",
    "external_validation_of_temperatures", "product_activation",
)


class Refusal(ValueError):
    """What the design does not allow, said out loud instead of filled with a number."""


def load_inputs(path: Path = INPUT) -> dict:
    record = json.loads(path.read_text(encoding="utf-8"))
    if record.get("run") != "Test016" or record.get("reserved_runs_not_used") != ["Test021"]:
        raise Refusal("the design reads one run and keeps its repetition reserved")
    return record


# ---------------------------------------------------------------- the engine, as text

def _text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8").replace("\r\n", "\n")


def engine_route(record: dict) -> dict:
    """Every engine fact the design rests on, checked against the source text."""
    anchors = []
    for item in record["engine"]["anchors"]:
        found = _text(item["file"]).count(item["needle"])
        if found != item["count"]:
            raise Refusal("engine moved under the design: %s found %d, expected %d"
                          % (item["id"], found, item["count"]))
        anchors.append({"id": item["id"], "file": item["file"], "role": item["role"], "holds": True})
    order = record["engine"]["step_order"]
    body = _text(order["file"])
    position = body.index(order["after"])
    for needle in order["in_order"]:
        following = body.find(needle, position)
        if following < 0:
            raise Refusal("step order moved under the design at: %s" % needle)
        position = following + len(needle)
    consumers = []
    for folder in PRODUCT_FOLDERS:
        for path in sorted((ROOT / folder).rglob("*")):
            if path.suffix not in (".gd", ".tscn", ".tres", ".cfg") or path.as_posix().endswith(MODULE):
                continue
            if "PrescribedObjectHrrSource" in path.read_text(encoding="utf-8", errors="replace"):
                consumers.append(path.relative_to(ROOT).as_posix())
    return {"anchors": anchors, "step_order_holds": True, "step_order": order["in_order"],
            "consumers_of_the_isolated_module": consumers}


# ---------------------------------------------------------------- the audited table

def source_table() -> dict:
    """Times and values of the committed source, and the trapezoid prefix of its energy."""
    fixture = json.loads(builder.FIXTURE.read_text(encoding="utf-8"))
    if fixture["source"]["run_id"] != "Test016" or fixture["reserved_runs_not_used"] != ["Test021"]:
        raise Refusal("the committed source is not the selected run")
    times = [float(item["time_s"]) for item in fixture["source"]["samples"]]
    values = [float(item["hrr_kw"]) for item in fixture["source"]["samples"]]
    prefix = [0.0]
    for index in range(1, len(times)):
        prefix.append(prefix[-1] + 0.5 * (values[index - 1] + values[index]) * (times[index] - times[index - 1]))
    return {"times": times, "values": values, "prefix_kj": prefix,
            "identity": fixture["expected_identity"], "oracle_total_kj": fixture["oracle"]["total_energy_kj"]}


def value_at(table: dict, time_s: float) -> float:
    times, values = table["times"], table["values"]
    if time_s < times[0] or time_s > times[-1]:
        raise Refusal("outside the support: the source ends, it is not held or extended")
    low = min(int(math.floor(time_s)), len(times) - 2)
    share = (time_s - times[low]) / (times[low + 1] - times[low])
    return values[low] + share * (values[low + 1] - values[low])


def time_of_energy(table: dict, energy_kj: float) -> float | None:
    """First instant at which the cumulative energy reaches a value; None if it never does."""
    prefix, times, values = table["prefix_kj"], table["times"], table["values"]
    if energy_kj > prefix[-1]:
        return None
    for index in range(1, len(times)):
        if prefix[index] >= energy_kj:
            left, right, need = values[index - 1], values[index], energy_kj - prefix[index - 1]
            slope = right - left
            if abs(slope) < 1.0e-12:
                step = need / left if left > 0.0 else 0.0
            else:
                step = (-left + math.sqrt(max(0.0, left * left + 2.0 * slope * need))) / slope
            return times[index - 1] + min(max(step, 0.0), 1.0)
    return times[-1]


# ---------------------------------------------------------------- counterexample: the filter

def legacy_filter(table: dict, dt: float, rise_tau_s: float, fall_tau_s: float) -> dict:
    """The applied power if the table were only the TARGET of the existing room fire.

    Same rule as CombustionSystem._smooth_state_value. Nothing else of the route is
    imitated: no oxygen factor, cap, feedback or fuel scale. It is the most favourable
    reading of that route, and it still does not return the curve.
    """
    end = table["times"][-1]
    steps = int(round(end / dt))
    current = peak = energy = worst = 0.0
    peak_time = 0.0
    for index in range(1, steps + 1):
        now = index * dt
        target = value_at(table, min(now, end))
        tau = rise_tau_s if target >= current else fall_tau_s
        current += (target - current) * (1.0 - math.exp(-dt / tau))
        energy += current * dt
        worst = max(worst, abs(current - target))
        if current > peak:
            peak, peak_time = current, now
    table_peak = max(table["values"])
    return {"dt_s": dt, "rise_tau_s": rise_tau_s, "fall_tau_s": fall_tau_s,
            "peak_kw": peak, "peak_over_table": peak / table_peak,
            "peak_delay_s": peak_time - table["times"][table["values"].index(table_peak)],
            "energy_in_the_support_kj": energy,
            "energy_minus_table_kj": energy - table["prefix_kj"][-1],
            "power_left_at_the_end_kw": current,
            "energy_still_in_the_filter_kj": current * fall_tau_s,
            "largest_gap_to_the_table_kw": worst}


# ---------------------------------------------------------------- oxygen

def fuel_mass_kg(_energy_kj: float) -> float:
    raise Refusal("fuel mass is not energy over a heat of combustion: this run has no numeric mass series")


def species_kg(_energy_kj: float, _species: str) -> float:
    raise Refusal("no species from a generic yield: this run has whole-test totals in open air only")


def oxygen(record: dict, series: dict, table: dict, test: dict) -> dict:
    """Which oxygen demand the run supports, and how far two published readings are apart."""
    declared, published = record["declared_for_the_counterexamples"], record["published"]["heat_per_kg_oxygen"]
    start, end = int(test["events"]["ignition_s"]), int(test["events"]["fire_out_s"])
    energy_kj = table["prefix_kj"][-1]
    heat = published["tn2303_MJ_kg"] * 1000.0
    calorimetric_kg = energy_kj / heat
    duct = selection.species_net_kg(series, "o2", start, end)
    engine_kg = energy_kj / 1000.0 * declared["engine_oxygen_kg_per_MJ"]
    # Approximate reconstruction of the calorimeter's own balance (depletion factor with
    # CO2 and CO, expansion factor), for the two ends of a declared humidity band.
    ambient = {name: statistics.mean(v for _t, v in selection.window(series, column, -60, -1))
               for name, (column, _m, _s) in selection.SPECIES.items()}
    flow = dict(selection.window(series, FLOW, start, end))
    columns = {name: dict(selection.window(series, column, start, end))
               for name, (column, _m, _s) in selection.SPECIES.items()}
    measured = dict(selection.window(series, HRR, start, end))
    alpha, heat_co = declared["expansion_factor"], declared["heat_per_kg_oxygen_from_co_MJ_kg"] * 1000.0
    band = []
    for humidity in declared["humidity_band_volume_fraction"]:
        consumed, rebuilt, signed, from_co = 0.0, 0.0, 0.0, 0.0
        previous = None
        for second in range(start, end + 1):
            o2, co2, co = columns["o2"][second], columns["co2"][second], columns["co"][second]
            depletion = (ambient["o2"] * (1.0 - co2 - co) - o2 * (1.0 - ambient["co2"])) \
                / (ambient["o2"] * (1.0 - o2 - co2 - co))
            base = flow[second] / (1.0 + depletion * (alpha - 1.0)) \
                * (32.0 / selection.M_AIR) * (1.0 - humidity) * ambient["o2"]
            carbon_monoxide = (heat_co - heat) * (1.0 - depletion) / 2.0 * co / o2 * base
            point = (depletion * base, heat * depletion * base - carbon_monoxide, measured[second], carbon_monoxide)
            if previous is not None:
                consumed += 0.5 * (previous[0] + point[0])
                rebuilt += 0.5 * (previous[1] + point[1])
                signed += 0.5 * (previous[2] + point[2])
                from_co += 0.5 * (previous[3] + point[3])
            previous = point
        band.append({"ambient_humidity_volume_fraction": humidity, "oxygen_consumed_kg": consumed,
                     "rebuilt_heat_over_published_series": rebuilt / signed,
                     "carbon_monoxide_term_over_rebuilt_heat": from_co / rebuilt})
    return {
        "basis": "an equivalent demand prescribed by the bench: energy over the constant the calorimeter "
                 "assumes for a generic fuel. It is not the oxygen measured in the duct, not an exact "
                 "inversion of the heat equation and not a stoichiometry of this chair",
        "what_the_relation_assumes": [
            "the heat released per kg of oxygen is the generic 13.1 MJ/kg, which was not measured on this chair",
            "complete combustion: the heat equation subtracts a carbon monoxide term that the ratio ignores",
            "the expansion factor and the ambient humidity the calorimeter assumed, which the CSV does not carry",
        ],
        "heat_per_kg_oxygen_MJ_kg": published["tn2303_MJ_kg"],
        "kg_per_MJ": 1000.0 / heat,
        "relative_standard_deviation_tn2077": published["tn2077_standard_deviation_MJ_kg"] / published["tn2077_MJ_kg"],
        "relative_half_width_tn2303": published["tn2303_plus_minus_MJ_kg"] / published["tn2303_MJ_kg"],
        "demand_whole_run_kg": calorimetric_kg,
        "peak_demand_kg_s": max(table["values"]) / heat,
        "engine_constant_kg_per_MJ": declared["engine_oxygen_kg_per_MJ"],
        "engine_constant_as_MJ_kg": 1.0 / declared["engine_oxygen_kg_per_MJ"],
        "engine_demand_whole_run_kg": engine_kg,
        "engine_over_calorimetric": engine_kg / calorimetric_kg,
        "engine_constant_inside_one_standard_deviation":
            abs(engine_kg / calorimetric_kg - 1.0) <= published["tn2077_standard_deviation_MJ_kg"] / published["tn2077_MJ_kg"],
        "fcd_total_oxygen_rule_kg": duct["kg"],
        "fcd_rule_over_calorimetric": duct["kg"] / calorimetric_kg,
        "fcd_rule_is_not_the_demand": "the database total leaves out the expansion and the depletion terms of "
                                      "the heat equation; it is a duct reading, lower than the oxygen consumed",
        "approximate_reconstruction": band,
        "approximate_reconstruction_is": "calculated with assumed humidity and expansion; a consistency check, not an input",
    }


def sealed_room_windows(record: dict, table: dict, kg_per_kj: float) -> list[dict]:
    """How long a closed room of a given volume stays near its initial oxygen number."""
    declared = record["declared_for_the_counterexamples"]
    total = table["prefix_kj"][-1]
    rows = []
    for volume in declared["sealed_volumes_m3"]:
        air_kg = declared["air_density_kg_m3"] * volume
        inventory_kg = air_kg * declared["engine_oxygen_number_ambient"]
        row = {"volume_m3": volume, "air_kg": air_kg, "oxygen_inventory_engine_convention_kg": inventory_kg,
               "whole_run_demand_over_inventory": total * kg_per_kj / inventory_kg, "bands": []}
        for drop in declared["oxygen_drop_bands"]:
            energy = drop * air_kg / kg_per_kj
            when = time_of_energy(table, energy)
            row["bands"].append({"oxygen_number_drop": drop, "energy_until_then_kj": min(energy, total),
                                 "share_of_the_run": min(energy, total) / total,
                                 "time_s": when, "reached_inside_the_run": when is not None})
        rows.append(row)
    return rows


# ---------------------------------------------------------------- radiation

def radiation(record: dict, series: dict, table: dict, test: dict) -> dict:
    """What the run measured about radiation, rebuilt from the series and the printed table."""
    published, declared = record["published"], record["declared_for_the_counterexamples"]
    start, end = int(test["events"]["ignition_s"]), int(test["events"]["fire_out_s"])
    flux = selection.window(series, RADIANT, start, end)
    heat = dict(selection.window(series, HRR, start, end))
    radius = published["heat_flux_gauges_tests_1_to_20"]["HF"]["R_cm"] / 100.0
    sphere = 4.0 * math.pi * radius * radius
    rebuilt = sum(0.5 * (flux[i][1] + flux[i + 1][1]) for i in range(len(flux) - 1)) * sphere
    gauges = published["radiated_energy_test016_kJ"]
    mean = statistics.mean(gauges.values())
    total_kj = published["total_heat_released_MJ"] * 1000.0
    fraction = mean / total_kj
    printed = published["radiative_fraction_test016"]
    relative = published["radiative_fraction_expanded_uncertainty_fraction"]
    cases = declared["radiative_fraction_cases"]
    if abs(cases["published_low"] - printed * (1.0 - relative)) > 1.0e-12 \
            or abs(cases["published_high"] - printed * (1.0 + relative)) > 1.0e-12 \
            or cases["published_whole_test_open_air"] != printed:
        raise Refusal("the declared radiative cases are not the published value and its uncertainty")
    instant = sorted(sphere * flux[i][1] / heat[flux[i][0]] for i in range(len(flux)) if heat[flux[i][0]] > 50.0)
    peak_second = max(heat, key=heat.get)
    energy = table["prefix_kj"][-1]
    splits = {}
    for name, chi in cases.items():
        splits[name] = {"radiative_fraction": chi, "to_the_gas_kj": energy * (1.0 - chi),
                        "radiated_kj": energy * chi,
                        "radiated_and_deposited_nowhere_by_default_kj": energy * chi}
    return {
        "series_gauge": "HF", "series_gauge_radius_m": radius,
        "radiated_energy_from_the_series_kj": rebuilt,
        "radiated_energy_printed_kj": gauges["HF"],
        "series_over_printed": rebuilt / gauges["HF"],
        "mean_of_five_gauges_kj": mean,
        "lowest_and_highest_gauge_over_heat": [min(gauges.values()) / total_kj, max(gauges.values()) / total_kj],
        "fraction_from_the_printed_table": fraction,
        "fraction_printed": printed,
        "fraction_reproduced": round(fraction, 2) == printed,
        "printed_denominator_mass_times_13_1_would_give": mean / (published["mass_lost_kg"] * 13100.0),
        "denominator_that_reproduces_the_table": "total heat released by calorimetry",
        "expanded_uncertainty_fraction": relative,
        "one_gauge_instantaneous_fraction_above_50_kw": {
            "samples": len(instant), "p10": instant[len(instant) // 10],
            "median": statistics.median(instant), "p90": instant[9 * len(instant) // 10],
            "at_the_peak": sphere * dict(flux)[peak_second] / heat[peak_second],
            "what_it_is": "one gauge, point source, calculated here; not a published series of the fraction",
        },
        "energy_split_of_the_table": splits,
        "what_the_fraction_is": published["radiative_fraction_caveat"],
        "what_the_engine_asks_for": "the share of the room power that does not heat the gas; with the default "
                                    "wall fraction of zero that share is deposited nowhere",
    }


# ---------------------------------------------------------------- gates

def decide(facts: dict) -> dict:
    """One decision per observable. A GO in one never approves another."""
    route, oxygen_facts, radiative = facts["engine_route"], facts["oxygen"], facts["radiation"]
    worst_filter = min(item["peak_over_table"] for item in facts["legacy_filter"])
    out = {name: "NO-GO" for name in OBSERVABLES}
    if not route["consumers_of_the_isolated_module"] and route["step_order_holds"]:
        out["energy_delivered_per_step"] = "GO_design_only_as_a_thermal_source_alone_in_its_room"
    if worst_filter < 1.0:
        out["applied_power_unfiltered"] = "GO_design_only_outside_the_room_fire_route"
    if oxygen_facts["engine_constant_inside_one_standard_deviation"]:
        out["oxygen_debit_per_accepted_energy"] = "GO_design_only_as_a_prescribed_equivalent_demand"
    out["oxygen_limited_response"] = "NO-GO_as_a_model_conservation_cap_only"
    out["regime_validity_indicator"] = "GO_design_only_as_a_declared_hypothesis_not_a_validated_limit"
    if radiative["fraction_reproduced"]:
        out["convective_radiative_split"] = "GO_partial_open_air_whole_test_value_with_its_uncertainty"
    out["radiation_to_surfaces"] = "NO-GO_not_measured_in_an_enclosure"
    out["fuel_mass"] = "NO-GO_no_numeric_mass_series"
    out["species_and_smoke"] = "NO-GO_whole_test_open_air_totals_only"
    out["fed_and_svv"] = "NO-GO"
    out["other_objects_in_the_same_room"] = "NO-GO_one_fire_per_room"
    out["flashover_spread_suppression"] = "NO-GO_excluded_from_the_first_case"
    out["engine_restore"] = "NO-GO_the_engine_has_no_state_restore"
    out["external_validation_of_temperatures"] = "NO-GO_the_run_has_no_enclosure"
    out["product_activation"] = "NO-GO"
    return out


# ---------------------------------------------------------------- audit

def audit(record: dict | None = None) -> dict:
    record = load_inputs() if record is None else record
    inputs = selection.load_record()
    test = inputs["tests"][record["run"]]
    if selection.use_for_fit(inputs["candidates"][0], record["run"]) != record["run"]:
        raise Refusal("the selected run cannot be used")
    series = selection.load_fcd_series(test)
    table = source_table()
    declared = record["declared_for_the_counterexamples"]
    if abs(table["prefix_kj"][-1] - table["oracle_total_kj"]) > 1.0e-6:
        raise Refusal("the table energy is not the audited one")
    facts = {
        "schema": SCHEMA,
        "scope": "design and feasibility; no engine physics, no fuel mass, no species",
        "run": record["run"], "reserved_runs_not_used": record["reserved_runs_not_used"],
        "engine_read_at_commit": record["engine_read_at_commit"],
        "source_identity": table["identity"],
        "table_energy_kj": table["prefix_kj"][-1],
        "table_peak_kw": max(table["values"]),
        "engine_route": engine_route(record),
        "legacy_filter": [legacy_filter(table, dt, rise, declared["filter_fall_tau_s"])
                          for rise in declared["filter_rise_tau_s"] for dt in declared["filter_steps_s"]],
        "oxygen": oxygen(record, series, table, test),
        "radiation": radiation(record, series, table, test),
    }
    facts["sealed_room_windows"] = sealed_room_windows(record, table, facts["oxygen"]["kg_per_MJ"] / 1000.0)
    facts["refused"] = {}
    for name, call in (("fuel_mass_from_energy", lambda: fuel_mass_kg(facts["table_energy_kj"])),
                       ("species_from_a_generic_yield", lambda: species_kg(facts["table_energy_kj"], "co"))):
        try:
            call()
            raise AssertionError(name + " must refuse")
        except Refusal as refusal:
            facts["refused"][name] = str(refusal)
    facts["decisions"] = decide(facts)
    return _rounded(facts)


def _rounded(value, digits: int = 9):
    if isinstance(value, float):
        return round(value, digits)
    if isinstance(value, dict):
        return {key: _rounded(item, digits) for key, item in value.items()}
    if isinstance(value, list):
        return [_rounded(item, digits) for item in value]
    return value


def render(facts: dict) -> str:
    return json.dumps(facts, indent=1, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render(audit())
    if args.write:
        SAVED.write_bytes(text.encode("utf-8"))
    if args.check:
        same = SAVED.exists() and SAVED.read_bytes().replace(b"\r\n", b"\n").decode("utf-8") == text
        print(json.dumps({"matches_saved_audit": same}))
        return 0 if same else 1
    if not args.write:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
