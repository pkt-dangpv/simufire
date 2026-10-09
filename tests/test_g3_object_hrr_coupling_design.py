"""Coupling design of the prescribed object HRR source: facts pinned, confusions refused.

Offline, no Godot. The oracles are closed forms, values printed in the cited reports or
the audit of the selection; none comes from the function under test. A test that pins an
engine fact is meant to fail when the engine moves: the design must then be read again.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_object_fire_source as selection
from scripts.simulation import audit_g3_object_hrr_coupling as design

ROOT = Path(__file__).resolve().parents[1]
RECORD = design.load_inputs()
SAVED = json.loads(design.SAVED.read_text(encoding="utf-8"))
SELECTION = json.loads(selection.SAVED.read_text(encoding="utf-8"))["runs"]["Test016"]
TABLE = design.source_table()
ENERGY_KJ = 115093.655
DESIGN_DOC = ROOT / "docs" / "validation" / "G3_OBJECT_HRR_SOURCE_COUPLING_DESIGN_2026-10-08.md"


def _synthetic(points: list[tuple[float, float]]) -> dict:
    times, values = [p[0] for p in points], [p[1] for p in points]
    prefix = [0.0]
    for i in range(1, len(times)):
        prefix.append(prefix[-1] + 0.5 * (values[i - 1] + values[i]) * (times[i] - times[i - 1]))
    return {"times": times, "values": values, "prefix_kj": prefix}


# ---------------------------------------------------------------- record and scope

def test_the_saved_audit_is_what_the_auditor_computes() -> None:
    assert design.render(design.audit()) == design.SAVED.read_bytes().replace(b"\r\n", b"\n").decode("utf-8")
    assert SAVED["schema"] == design.SCHEMA and SAVED["run"] == "Test016"


def test_one_run_is_read_and_its_repetition_stays_reserved(tmp_path) -> None:
    assert RECORD["reserved_runs_not_used"] == ["Test021"] == SAVED["reserved_runs_not_used"]
    text = Path(design.__file__).read_text(encoding="utf-8")
    assert "Test021" in text and text.count('"Test021"') == 2  # only inside the two guards
    for change in ({"run": "Test021"}, {"reserved_runs_not_used": []}, {"run": "Test030"}):
        altered = tmp_path / "inputs.json"
        altered.write_text(json.dumps({**RECORD, **change}), encoding="utf-8")
        with pytest.raises(design.Refusal):
            design.load_inputs(altered)


def test_local_sources_are_the_pinned_bytes() -> None:
    for name in ("tn2303", "tn2077", "fcd_guide"):
        source = RECORD["sources"][name]
        assert hashlib.sha256((ROOT / source["local"]).read_bytes()).hexdigest() == source["sha256"], name
    assert (ROOT / RECORD["sources"]["cfast_reference"]["local"]).exists()
    assert RECORD["sources"]["cfast_code"]["local"].startswith("not archived")


def test_the_auditor_launches_nothing_and_writes_one_file() -> None:
    text = Path(design.__file__).read_text(encoding="utf-8")
    for word in ("subprocess", "godot", "Godot", "os.system", "monitored"):
        assert word not in text, word
    assert text.count("write_bytes") == 1 and "SAVED.write_bytes" in text


# ---------------------------------------------------------------- the engine route

def test_every_engine_fact_of_the_design_holds_in_the_source() -> None:
    route = design.engine_route(RECORD)
    assert len(route["anchors"]) == len(RECORD["engine"]["anchors"]) == 34
    assert all(item["holds"] for item in route["anchors"]) and route["step_order_holds"]
    assert len({item["id"] for item in RECORD["engine"]["anchors"]}) == 34
    assert route == SAVED["engine_route"]


@pytest.mark.parametrize("anchor", ["hrr_is_filtered", "oxygen_sink_keyed_on_room_power",
                                    "radiation_to_walls_default", "run_end_needs_a_fire_object",
                                    "engine_has_no_state_restore", "one_fire_per_room"])
def test_a_moved_engine_fact_stops_the_audit(anchor: str) -> None:
    record = copy.deepcopy(RECORD)
    item = next(entry for entry in record["engine"]["anchors"] if entry["id"] == anchor)
    item["count"] += 1
    with pytest.raises(design.Refusal, match=anchor):
        design.engine_route(record)


def test_a_changed_step_order_stops_the_audit() -> None:
    record = copy.deepcopy(RECORD)
    order = record["engine"]["step_order"]["in_order"]
    fire, thermal = order.index("_step_fire(dt)"), order.index("thermal_system.step(building, dt, {")
    assert fire < order.index("if not pre_hrr_o2_step:") < thermal
    order[fire], order[thermal] = order[thermal], order[fire]
    with pytest.raises(design.Refusal, match="step order"):
        design.engine_route(record)


def test_only_the_diagnostic_bench_consumes_the_isolated_module() -> None:
    route = SAVED["engine_route"]
    assert route["consumers_of_the_isolated_module"] == ["sim/fire/PrescribedThermalSourceCoupling.gd"]
    assert route["unexpected_consumers_of_the_isolated_module"] == []
    assert (ROOT / design.MODULE).exists()
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "@export var g3_prescribed_thermal" not in engine and "preload(\"res://sim/fire/Prescribed" not in engine


def test_the_engine_oxygen_constant_is_read_from_the_engine() -> None:
    declared = RECORD["declared_for_the_counterexamples"]["engine_oxygen_kg_per_MJ"]
    fire = (ROOT / "sim/fire/FireModel.gd").read_text(encoding="utf-8")
    sink = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
    assert "var o2_consumption_kg_per_MJ: float = %s" % declared in fire
    assert "if room.fire != null else %s" % declared in sink


# ---------------------------------------------------------------- the table

def test_the_table_is_the_audited_source() -> None:
    fixture = json.loads(design.builder.FIXTURE.read_text(encoding="utf-8"))
    assert TABLE["identity"] == fixture["expected_identity"] == SAVED["source_identity"]
    assert len(TABLE["times"]) == 3769 and TABLE["times"][0] == 0.0 and TABLE["times"][-1] == 3768.0
    assert TABLE["prefix_kj"][-1] == pytest.approx(ENERGY_KJ, abs=1.0e-6)
    assert SAVED["table_energy_kj"] == pytest.approx(ENERGY_KJ, abs=1.0e-6)
    assert SAVED["table_peak_kw"] == 621.46 == SELECTION["reproduction"]["peak_kW"]


def test_reading_the_table_outside_its_support_is_refused() -> None:
    assert design.value_at(TABLE, 1143.0) == 621.46
    assert design.value_at(TABLE, 0.5) == pytest.approx(0.5 * (TABLE["values"][0] + TABLE["values"][1]))
    for outside in (-0.001, 3768.001, 1.0e6):
        with pytest.raises(design.Refusal):
            design.value_at(TABLE, outside)


def test_time_of_energy_against_closed_forms() -> None:
    ramp = _synthetic([(0.0, 0.0), (1.0, 100.0), (2.0, 200.0)])  # power 100 t, energy 50 t^2
    assert design.time_of_energy(ramp, 50.0) == pytest.approx(1.0)
    assert design.time_of_energy(ramp, 112.5) == pytest.approx(1.5)
    assert design.time_of_energy(ramp, 200.0) == pytest.approx(2.0)
    assert design.time_of_energy(ramp, 200.001) is None
    flat = _synthetic([(0.0, 4.0), (1.0, 4.0), (2.0, 4.0)])
    assert design.time_of_energy(flat, 6.0) == pytest.approx(1.5)


# ---------------------------------------------------------------- the existing route as a target

def test_the_filter_is_the_engine_rule_on_closed_forms() -> None:
    steady = _synthetic([(float(t), 100.0) for t in range(0, 201)])
    result = design.legacy_filter(steady, 0.01, 10.0, 20.0)
    assert result["peak_kw"] == pytest.approx(100.0 * (1.0 - math.exp(-20.0)), rel=1.0e-9)
    # Energy of a first-order rise to a constant: 100 (T - tau (1 - exp(-T / tau))), to the step size.
    assert result["energy_in_the_support_kj"] == pytest.approx(100.0 * (200.0 - 10.0 * (1.0 - math.exp(-20.0))), rel=1.0e-3)
    assert result["energy_still_in_the_filter_kj"] == pytest.approx(result["power_left_at_the_end_kw"] * 20.0)
    assert result["peak_over_table"] < 1.0 and result["largest_gap_to_the_table_kw"] == pytest.approx(
        100.0 * math.exp(-0.001), rel=1.0e-9)  # the first step, where the filter is furthest behind


def test_the_room_fire_route_would_not_return_the_curve() -> None:
    declared = RECORD["declared_for_the_counterexamples"]
    cases = SAVED["legacy_filter"]
    assert len(cases) == len(declared["filter_steps_s"]) * len(declared["filter_rise_tau_s"]) == 6
    for case in cases:
        assert case["fall_tau_s"] == 20.0 and case["rise_tau_s"] in (10.8, 6.0)
        assert 0.90 < case["peak_over_table"] < 0.98, case
        assert case["peak_delay_s"] >= 4.0
        # Faster up than down: the filter rectifies the noise and adds energy.
        assert 5000.0 < case["energy_minus_table_kj"] < 9000.0, case
        assert case["largest_gap_to_the_table_kw"] > 150.0
    slow = [case for case in cases if case["rise_tau_s"] == 10.8]
    assert max(c["energy_minus_table_kj"] for c in slow) - min(c["energy_minus_table_kj"] for c in slow) < 20.0
    # With the faster rise the excess is larger than the expanded uncertainty of the total heat.
    assert min(c["energy_minus_table_kj"] for c in cases if c["rise_tau_s"] == 6.0) > 6400.0


def test_the_rise_time_constants_are_the_engine_ones() -> None:
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    combustion = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
    assert "@export var fire_hrr_rise_tau_s: float = 6.0" in engine
    assert 'float(context.get("fire_hrr_rise_tau_s", 6.0)) * 1.8' in combustion
    assert RECORD["declared_for_the_counterexamples"]["filter_rise_tau_s"] == [pytest.approx(6.0 * 1.8), 6.0]


# ---------------------------------------------------------------- oxygen

def test_the_oxygen_demand_is_a_prescribed_equivalent_not_a_measurement() -> None:
    oxygen = SAVED["oxygen"]
    assert oxygen["heat_per_kg_oxygen_MJ_kg"] == 13.1
    assert oxygen["kg_per_MJ"] == pytest.approx(1.0 / 13.1, abs=1.0e-9)
    assert oxygen["demand_whole_run_kg"] == pytest.approx(ENERGY_KJ / 13100.0, abs=1.0e-8)
    assert oxygen["peak_demand_kg_s"] == pytest.approx(621.46 / 13100.0, abs=1.0e-9)
    assert oxygen["relative_standard_deviation_tn2077"] == pytest.approx(0.35 / 13.1, abs=1.0e-9)
    assert oxygen["relative_half_width_tn2303"] == pytest.approx(0.5 / 13.1, abs=1.0e-9)
    assert "not the oxygen measured" in oxygen["basis"] and "not a stoichiometry" in oxygen["basis"]
    assert len(oxygen["what_the_relation_assumes"]) == 3
    assert SAVED["decisions"]["oxygen_debit_per_accepted_energy"].endswith("prescribed_equivalent_demand")
    # The heat equation carries a carbon monoxide term that energy over a constant leaves out.
    for item in oxygen["approximate_reconstruction"]:
        assert 0.001 < item["carbon_monoxide_term_over_rebuilt_heat"] < 0.005


def test_the_engine_constant_is_the_same_relation_within_its_uncertainty() -> None:
    oxygen = SAVED["oxygen"]
    assert oxygen["engine_over_calorimetric"] == pytest.approx(0.076 * 13.1, abs=1.0e-9)
    assert abs(oxygen["engine_over_calorimetric"] - 1.0) < oxygen["relative_standard_deviation_tn2077"]
    assert oxygen["engine_constant_inside_one_standard_deviation"] is True


def test_the_database_total_of_oxygen_is_not_the_demand() -> None:
    oxygen = SAVED["oxygen"]
    assert oxygen["fcd_total_oxygen_rule_kg"] == pytest.approx(SELECTION["species"]["o2"]["net_kg"], abs=1.0e-8)
    # The two readings are further apart than the uncertainty of the constant: not interchangeable.
    assert 1.0 - oxygen["fcd_rule_over_calorimetric"] > oxygen["relative_half_width_tn2303"]
    low, high = sorted(item["oxygen_consumed_kg"] for item in oxygen["approximate_reconstruction"])
    assert oxygen["fcd_total_oxygen_rule_kg"] < low < high < oxygen["demand_whole_run_kg"]
    for item in oxygen["approximate_reconstruction"]:
        assert 0.95 < item["rebuilt_heat_over_published_series"] < 1.0


def test_no_fuel_mass_and_no_species_are_derived() -> None:
    with pytest.raises(design.Refusal, match="fuel mass"):
        design.fuel_mass_kg(ENERGY_KJ)
    for species in ("co", "co2", "hcn", "soot"):
        with pytest.raises(design.Refusal, match="generic yield"):
            design.species_kg(ENERGY_KJ, species)
    assert set(SAVED["refused"]) == {"fuel_mass_from_energy", "species_from_a_generic_yield"}
    text = json.dumps(SAVED)
    for word in ("mass_loss_rate", "co_yield", "fuel_kg", "pyrolysis_rate"):
        assert word not in text, word


def test_a_closed_room_leaves_the_initial_oxygen_before_the_peak() -> None:
    rows = {row["volume_m3"]: row for row in SAVED["sealed_room_windows"]}
    assert sorted(rows) == [30.0, 60.0, 120.0, 500.0, 2000.0]
    assert rows[30.0]["whole_run_demand_over_inventory"] > 1.0  # cannot hold the oxygen of the whole run
    for volume, row in rows.items():
        assert row["air_kg"] == pytest.approx(1.2 * volume)
        assert row["oxygen_inventory_engine_convention_kg"] == pytest.approx(1.2 * volume * 0.209)
        times = [band["time_s"] for band in row["bands"] if band["reached_inside_the_run"]]
        assert times == sorted(times)
        for band in row["bands"]:
            energy = band["oxygen_number_drop"] * row["air_kg"] * 13100.0
            assert band["share_of_the_run"] == pytest.approx(min(energy, ENERGY_KJ) / ENERGY_KJ, abs=1.0e-8)
    one_point = {volume: next(b for b in row["bands"] if b["oxygen_number_drop"] == 0.01) for volume, row in rows.items()}
    assert one_point[60.0]["time_s"] < 1143.0 and one_point[60.0]["share_of_the_run"] < 0.10
    assert one_point[30.0]["time_s"] < one_point[60.0]["time_s"] < one_point[120.0]["time_s"] < one_point[500.0]["time_s"]
    assert all(not band["reached_inside_the_run"] for band in rows[2000.0]["bands"])


# ---------------------------------------------------------------- radiation

def test_the_radiant_series_returns_the_printed_radiated_energy() -> None:
    radiation = SAVED["radiation"]
    assert radiation["series_gauge_radius_m"] == 3.0
    assert radiation["radiated_energy_printed_kj"] == 53127
    assert abs(radiation["series_over_printed"] - 1.0) < 1.0e-3


def test_the_printed_radiative_fraction_is_reproduced_from_its_table() -> None:
    radiation, published = SAVED["radiation"], RECORD["published"]
    gauges = published["radiated_energy_test016_kJ"]
    assert radiation["mean_of_five_gauges_kj"] == pytest.approx(sum(gauges.values()) / 5.0)
    assert radiation["fraction_from_the_printed_table"] == pytest.approx(sum(gauges.values()) / 5.0 / 115100.0, abs=1.0e-9)
    assert radiation["fraction_reproduced"] is True and radiation["fraction_printed"] == 0.52
    # The denominator as printed in the report (mass lost times 13.1 kJ/g) is not the one of the table.
    assert radiation["printed_denominator_mass_times_13_1_would_give"] > 1.0
    low, high = radiation["lowest_and_highest_gauge_over_heat"]
    assert low < 0.52 < high and high - low > 0.10


def test_the_radiative_fraction_is_a_whole_test_value_not_a_series() -> None:
    instant = SAVED["radiation"]["one_gauge_instantaneous_fraction_above_50_kw"]
    assert instant["p10"] < instant["at_the_peak"] < instant["median"] < instant["p90"] < 0.52
    assert instant["p90"] - instant["p10"] > 0.15
    assert "not a published series" in instant["what_it_is"]


def test_the_energy_split_closes_for_every_declared_fraction() -> None:
    splits = SAVED["radiation"]["energy_split_of_the_table"]
    assert set(splits) == {"engine_default", "published_whole_test_open_air", "published_low", "published_high"}
    assert splits["published_low"]["radiative_fraction"] == pytest.approx(0.52 * 0.82)
    assert splits["published_high"]["radiative_fraction"] == pytest.approx(0.52 * 1.18)
    for item in splits.values():
        assert item["to_the_gas_kj"] + item["radiated_kj"] == pytest.approx(ENERGY_KJ, abs=1.0e-6)
        assert item["radiated_and_deposited_nowhere_by_default_kj"] == item["radiated_kj"]
    assert splits["published_whole_test_open_air"]["radiated_kj"] - splits["engine_default"]["radiated_kj"] \
        == pytest.approx(0.17 * ENERGY_KJ, abs=1.0e-6)


def test_altered_radiation_readings_are_noticed() -> None:
    inputs = selection.load_record()
    test = inputs["tests"]["Test016"]
    series = selection.load_fcd_series(test)
    record = copy.deepcopy(RECORD)
    record["published"]["radiated_energy_test016_kJ"]["HF1"] += 10000
    assert design.radiation(record, series, TABLE, test)["fraction_reproduced"] is False
    record = copy.deepcopy(RECORD)
    record["published"]["heat_flux_gauges_tests_1_to_20"]["HF"]["R_cm"] = 203
    assert design.radiation(record, series, TABLE, test)["series_over_printed"] < 0.5
    record = copy.deepcopy(RECORD)
    record["declared_for_the_counterexamples"]["radiative_fraction_cases"]["published_high"] = 0.60
    with pytest.raises(design.Refusal):
        design.radiation(record, series, TABLE, test)


# ---------------------------------------------------------------- gates

def test_there_is_one_decision_per_observable_and_none_is_a_plain_go() -> None:
    decisions = SAVED["decisions"]
    assert tuple(decisions) == design.OBSERVABLES and len(decisions) == 15
    for name, verdict in decisions.items():
        assert verdict.startswith(("NO-GO", "GO_design_only", "GO_partial")), name
        assert verdict != "GO"
    go = sorted(name for name, verdict in decisions.items() if verdict.startswith("GO"))
    assert go == ["applied_power_unfiltered", "convective_radiative_split", "energy_delivered_per_step",
                  "oxygen_debit_per_accepted_energy", "regime_validity_indicator"]
    for name in ("fuel_mass", "species_and_smoke", "fed_and_svv", "product_activation", "engine_restore",
                 "other_objects_in_the_same_room", "oxygen_limited_response"):
        assert decisions[name].startswith("NO-GO"), name


def test_a_go_does_not_survive_the_loss_of_its_fact() -> None:
    facts = copy.deepcopy(SAVED)
    facts["engine_route"]["unexpected_consumers_of_the_isolated_module"] = ["sim/core/SimulationEngine.gd"]
    assert design.decide(facts)["energy_delivered_per_step"] == "NO-GO"
    facts = copy.deepcopy(SAVED)
    facts["oxygen"]["engine_constant_inside_one_standard_deviation"] = False
    assert design.decide(facts)["oxygen_debit_per_accepted_energy"] == "NO-GO"
    facts = copy.deepcopy(SAVED)
    facts["radiation"]["fraction_reproduced"] = False
    assert design.decide(facts)["convective_radiative_split"] == "NO-GO"
    facts = copy.deepcopy(SAVED)
    for item in facts["legacy_filter"]:
        item["peak_over_table"] = 1.0
    assert design.decide(facts)["applied_power_unfiltered"] == "NO-GO"
    # Losing every fact never turns a NO-GO into a GO.
    for name in ("fuel_mass", "species_and_smoke", "fed_and_svv", "product_activation"):
        assert design.decide(facts)[name].startswith("NO-GO")


def test_the_design_document_states_every_gate() -> None:
    text = DESIGN_DOC.read_text(encoding="utf-8")
    assert "NO-GO" in text and "No autoriza" in text
    for needle in ("G3_OBJECT_HRR_COUPLING_INPUTS_2026-10-08.json", "G3_OBJECT_HRR_COUPLING_AUDIT_2026-10-08.json",
                   "Test021", "0,52", "13,1"):
        assert needle in text, needle
