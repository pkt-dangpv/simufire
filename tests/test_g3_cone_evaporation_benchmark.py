"""Offline controls of the flameless n-heptane cone evaporation test as a benchmark.

Nothing here starts Godot or touches sim/. The controls use closed-form or
synthetic oracles that do not depend on the digitised curves: they say what
the auditor must refuse, not what the data should show. The
section "what the data show" is different in kind: it pins findings read off
the audit afterwards, so that a later change cannot move them unnoticed. The
digitised series is not in the repository; the two tests that need the local
copy of the article or of the series skip when it is absent and say so.
"""
import copy
import json
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_cone_evaporation_benchmark as cone
from scripts.simulation import audit_g3_net_thermal_budget as net
from scripts.simulation import digitise_g3_cone_benchmark_figures as digitiser

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def record():
    return json.loads(cone.INPUT.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def aggregates():
    return json.loads(cone.AGGREGATES.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def result():
    return cone.audit()


@pytest.fixture(scope="module")
def props():
    return net.properties()


# --- source and rights -----------------------------------------------------------------------

def test_the_reviewed_document_is_pinned_and_not_archived(record):
    source = record["source"]
    assert source["document_sha256"] == digitiser.PDF_SHA256
    assert source["archived_in_repository"] is False
    assert not list((ROOT / "docs" / "literature").rglob("*Beji*"))
    assert not list((ROOT / "docs" / "literature").rglob("*103317*"))


def test_the_search_for_public_data_says_not_located_and_not_absent(record):
    public = record["source"]["public_data"]
    assert public["raw_series_located"] is False
    assert "not located" in public["status"] and "unknown" in public["status"]
    assert len(public["searched"]) >= 6


def test_the_digitised_series_is_not_published(record, aggregates):
    assert record["digitisation"]["series_published"] is False
    assert "curves" not in aggregates
    for run in aggregates["runs"].values():
        for key in ("upper", "lower"):
            if run[key]:
                assert len(run[key]["readings"]) <= 5
        assert len(run["mass"]["accumulated_at"]) <= 4
    tracked = (ROOT / "runs" / "literature_local").relative_to(ROOT).as_posix()
    assert tracked.startswith("runs/")


def test_the_aggregates_belong_to_the_digitisation_named_by_the_record(record, aggregates):
    assert aggregates["series_sha256"] == record["digitisation"]["series_sha256"]
    assert aggregates["document_sha256"] == record["source"]["document_sha256"]


# --- matrix of tests -------------------------------------------------------------------------

def test_every_item_of_the_set_up_carries_one_of_the_five_classes(record):
    items = list(cone.walk_classified(record["setup"]))
    assert len(items) >= 35
    for path, item in items:
        assert item["class"] in cone.CLASSES, path


def test_what_the_paper_does_not_give_is_null_and_unknown(record):
    setup = record["setup"]
    for item in (setup["charge"]["initial_mass_per_run"], setup["pan"]["temperature"],
                 setup["irradiation"]["reading_and_uncertainty_of_the_check"],
                 setup["irradiation"]["irradiation_during_the_test"],
                 setup["atmosphere"]["fuel_vapour_concentration"], setup["atmosphere"]["pressure"],
                 setup["thermocouples"]["type_and_uncertainty"], setup["thermocouples"]["surface_temperature"],
                 setup["balance"]["area_used_for_the_rate"]):
        assert item["value"] is None and item["class"] == "unknown"


def test_the_twelve_tests_of_the_paper_are_listed(record):
    tests = {test["id"]: test for test in record["tests"]}
    assert len(tests) == 12
    assert sum(test["liquid"] == "n-heptane" for test in tests.values()) == 8
    assert tests["H25#4"]["fields"]["extraction_on"]["value"] is False
    assert tests["H25#5"]["fields"]["insulated"]["value"] is False
    assert tests["H25#3"]["fields"]["duct_gas_temperature_c"]["value"] is None
    assert tests["H25#3"]["temperature_curves"] == []
    assert tests["H50#3"]["fields"]["duct_gas_temperature_c"] == {"value": 174.0, "plus_minus": 7.0, "class": "measured"}
    for test in tests.values():
        assert test["fields"]["irradiation"]["class"] == "nominal"


def test_the_corpus_follows_its_prior_criteria_and_nothing_else(record):
    expected = {}
    for test in record["tests"]:
        fields = test["fields"]
        if test["liquid"] == "n-heptane" and fields["extraction_on"]["value"] and fields["insulated"]["value"]:
            expected[test["id"]] = "mass_and_temperature" if test["temperature_curves"] else "mass_only"
    assert {run["run"]: run["role"] for run in record["corpus"]["runs"]} == expected
    assert len(record["corpus"]["criteria_fixed_before_reading_values"]) == 4


def test_the_evaporation_time_quoted_by_the_authors_fixes_the_area_they_used(record):
    """Equation 14 of the paper gives 168 s only with a pool of 0.10 m by 0.10 m."""
    liquid = record["setup"]["liquid_declared"]
    mass = 250.0e-6 * liquid["density_kg_m3"]
    per_kg = liquid["cp_kj_kg_k"] * (liquid["boiling_c"] - 20.0) + liquid["latent_kj_kg"]
    assert mass * per_kg / (50.0 * 0.100 * 0.100) == pytest.approx(168.0, abs=0.5)
    assert mass * per_kg / (50.0 * 0.098 * 0.098) == pytest.approx(174.8, abs=0.5)


# --- control 1: nominal power is not net heat ------------------------------------------------

def test_nominal_irradiation_cannot_be_relabelled_as_net_heat(record, result):
    nominal = {"role": "nominal_irradiation", "value_kw_m2": 50.0}
    assert cone.relabel(nominal, "nominal_irradiation") is nominal
    for role in ("net_heat", "absorbed_heat", "incident_irradiation"):
        with pytest.raises(cone.Refusal):
            cone.relabel(nominal, role)
    assert set(record["objects"]) == {"nominal_irradiation", "incident_irradiation", "net_absorbed_heat", "demand_diagnostic"}
    assert result["decisions"]["incident_irradiation"].startswith("GO_partial")
    assert result["decisions"]["net_absorbed_heat"] == "NO_GO_not_identified"
    assert result["b_net"] == "NO_GO_not_identified"


def test_the_demand_cannot_be_offered_as_a_thermal_input(result):
    for run in result["runs"].values():
        assert run["whole_test"]["role"] == "demand_diagnostic"
        with pytest.raises(cone.Refusal):
            cone.relabel(run["whole_test"], "net_heat")


# --- control 2: incident flux is not absorbed heat -------------------------------------------

def test_incident_irradiation_is_not_absorbed_heat_without_identified_terms(record):
    with pytest.raises(cone.Refusal) as refusal:
        cone.absorbed_from_incident(25.0, record["frontier_terms"])
    assert "attenuation_by_fuel_vapour" in str(refusal.value)
    identified = [{"key": "reflection", "identification": "measured", "factor": 0.92},
                  {"key": "attenuation", "identification": "bounded", "factor": 0.90}]
    assert cone.absorbed_from_incident(25.0, identified) == pytest.approx(20.7)


def test_one_frontier_term_is_bounded_and_nine_block(record, result):
    status = cone.frontier_status(record["frontier_terms"])
    assert status["identified"] is False
    assert len(record["frontier_terms"]) == 10 and len(status["blocking"]) == 9
    assert status["classes"]["surface_emission"] == "bounded"
    assert result["frontier"] == status
    assert net.blackbody_kw_m2(98.5 + 273.15) == pytest.approx(1.08, abs=0.01)


# --- control 3: runs and windows are not mixed -----------------------------------------------

def test_curves_of_different_runs_are_not_synchronous_channels():
    assert cone.same_run({"run": "H50#1"}, {"run": "H50#1"}) == "H50#1"
    with pytest.raises(cone.Refusal):
        cone.same_run({"run": "H50#1"}, {"run": "H50#2"})


def test_a_reading_outside_its_window_is_refused():
    assert cone.inside_window(45.0, (0.0, 45.0)) == 45.0
    with pytest.raises(cone.Refusal):
        cone.inside_window(60.0, (0.0, 45.0))


def test_each_window_uses_the_readings_of_its_own_run(result, aggregates):
    for name, run in result["runs"].items():
        for key, trace_key in (("first", "upper"), ("second", "lower")):
            window = run["windows"][key]
            if window is None:
                continue
            source = aggregates["runs"][name]
            stamp = "%g" % window["ends_s"]
            assert window["lower_thermocouple_c"] == source["lower"]["readings"][stamp]["value_c"]
            assert window["ends_s"] == source[trace_key]["usable_until_s"]
            assert window["ends_s"] <= window["support_ends_s"]
            assert window["ends_s"] <= window["immersion_confirmed_until_s"]


# --- control 4: circular dependence on the mass ----------------------------------------------

def test_a_quantity_built_from_the_mass_cannot_validate_the_mass(result):
    level = {"name": "liquid level", "depends_on": ["mass"]}
    with pytest.raises(cone.Refusal):
        cone.require_independent(level, "mass")
    assert cone.independent_prediction_allowed(level, "temperature")
    for run in result["runs"].values():
        assert "mass" in run["depends_on"]
        assert not cone.independent_prediction_allowed(run, "mass")
        assert not cone.independent_prediction_allowed(run, "temperature")


def test_the_only_geometric_range_free_of_the_mass_is_the_whole_stroke(result):
    free = result["geometry"]["mass_free_range"]
    assert free["depends_on"] == []
    assert free["envelope"] == [pytest.approx(0.557, abs=0.002), pytest.approx(0.911, abs=0.002)]
    assert cone.independent_prediction_allowed(free, "mass")


# --- control 5: a digitisation is not raw data -----------------------------------------------

def test_a_digitised_figure_cannot_be_presented_as_raw_data(aggregates):
    assert cone.present_series_as(aggregates, "digitisation") is aggregates
    for nature in ("raw", "calculated"):
        with pytest.raises(cone.Refusal):
            cone.present_series_as(aggregates, nature)
    with pytest.raises(cone.Refusal):
        cone.series_nature({"nature": "mass recorded every second"})
    with pytest.raises(cone.Refusal):
        cone.series_nature({})


def test_the_audit_refuses_aggregates_of_another_digitisation(record, aggregates):
    other = copy.deepcopy(aggregates)
    other["series_sha256"] = "0" * 64
    with pytest.raises(ValueError):
        cone.audit(record, other)


def test_the_digitisation_declares_what_cannot_be_recovered(record, result):
    digitisation = record["digitisation"]
    assert digitisation["acquisition_rate_recoverable"] is False
    assert digitisation["instrument_uncertainty_recoverable"] is False
    assert "not raw data" in result["nature_of_series"]


# --- control 6: point thermocouples are not a mean temperature -------------------------------

def test_point_temperatures_are_not_a_mean_or_surface_temperature(record, result):
    with pytest.raises(cone.Refusal):
        cone.mean_temperature([26.5, 83.3])
    assert cone.mean_temperature([20.0, 40.0], profile_measured=True) == 30.0
    assert record["setup"]["thermocouples"]["profile_measured"] is False
    for run in result["runs"].values():
        for window in run["windows"].values():
            if window:
                assert window["stored_kind"] == "assumption_interval"
    assert "mean" in result["decisions"]["heating_validation"]


def test_two_thermocouples_do_not_fix_the_stored_energy(result):
    """Prior criterion: the demand must be narrower than the geometric range it would test."""
    widths = []
    for run in result["runs"].values():
        for window in run["windows"].values():
            if window:
                assert window["discriminates_thermal_input"] is False
                assert window["demand_relative_width"] > window["geometric_relative_width"]
                widths.append(window["demand_relative_width"])
    assert len(widths) == 8 and min(widths) > 0.5


# --- control 7: signs and double counting ----------------------------------------------------

def test_storage_of_a_uniform_liquid_is_its_mass_times_its_enthalpy_rise(props):
    rise = net.enthalpy(props["liquid"], 330.0, "T") - net.enthalpy(props["liquid"], 290.0, "T")
    assert rise > 0.0
    bracket = cone.storage_bracket(props, 10.0, [6.0, 19.0], 290.0 - 273.15, 330.0 - 273.15, 330.0 - 273.15, 330.0 - 273.15, 684.0)
    below = 684.0 * 0.006
    # the liquid under the lower thermocouple is the only part the readings do not fix
    assert bracket["kj_m2"][1] == pytest.approx(10.0 * rise)
    assert bracket["kj_m2"][0] == pytest.approx((10.0 - below) * rise)
    assert sum(bracket["layers_kg_m2"].values()) == pytest.approx(10.0)


def test_cooling_is_negative_and_heating_positive(props):
    warm = cone.storage_bracket(props, 2.0, [6.0, 19.0], 20.0, 40.0, None, 40.0, 684.0)["kj_m2"]
    cold = cone.storage_bracket(props, 2.0, [6.0, 19.0], 40.0, 20.0, None, 20.0, 684.0)["kj_m2"]
    assert warm[1] > 0.0 and cold[1] < 0.0 and warm[1] == pytest.approx(-cold[1])


def test_an_empty_pan_stores_nothing_and_the_evaporated_mass_is_counted_once(props, result):
    assert cone.storage_bracket(props, 0.0, [6.0, 19.0], 20.0, 90.0, None, 97.0, 684.0)["kj_m2"] == [0.0, 0.0]
    per_kg = cone.demand_per_kg_range(props, [20.0, 20.0], [90.0, 90.0])
    by_hand = (props["latent_kj_kg"] + net.enthalpy(props["gas"], 363.15, "T") - net.enthalpy(props["liquid"], 293.15, "T"))
    assert per_kg == [pytest.approx(by_hand), pytest.approx(by_hand)]
    for run in result["runs"].values():
        whole = run["whole_test"]
        assert whole["storage_at_end_kj_m2"] == 0.0
        for end in (0, 1):
            by_product = run["mass"]["evaporated_kg_m2"][end] * whole["demand_kj_kg"][end]
            assert whole["demand_kj_m2"][end] == pytest.approx(by_product, rel=1e-6)
        for window in run["windows"].values():
            if window:
                for end in (0, 1):
                    parts = window["stored_kj_m2"][end] + window["emitted_kj_m2"][end]
                    assert window["demand_kj_m2"][end] == pytest.approx(parts, abs=1e-3)
                    whole_mass = window["evaporated_kg_m2"][end] + window["remaining_kg_m2"][1 - end]
                    assert whole_mass == pytest.approx(run["mass"]["evaporated_kg_m2"][1 - end], abs=1e-4)


# --- control 8: units, rates and accumulated mass --------------------------------------------

def test_a_rate_in_grams_accumulates_to_kilograms_per_square_metre():
    assert cone.accumulate([40.0] * 10, 10.0)[-1] == pytest.approx(4.0)
    assert cone.accumulate([0.0, 20.0, 40.0], 15.0) == [pytest.approx(0.0), pytest.approx(0.3), pytest.approx(0.9)]
    with pytest.raises(cone.Refusal):
        cone.accumulate([40.0], 0.0)


def test_a_missing_reading_is_not_accumulated_as_zero():
    with pytest.raises(cone.Refusal):
        cone.accumulate([40.0, None, 40.0], 15.0)


def test_a_rate_is_not_derived_from_accumulated_mass_without_a_declared_method():
    accumulated = cone.accumulate([10.0, 30.0, 20.0], 15.0)
    with pytest.raises(cone.Refusal):
        cone.rate_from_accumulated(accumulated, 15.0)
    back = cone.rate_from_accumulated(accumulated, 15.0, smoothing="difference of consecutive 15 s blocks, no smoothing")
    assert back["rates_g_m2_s"] == [pytest.approx(10.0), pytest.approx(30.0), pytest.approx(20.0)]


def test_the_accumulated_mass_is_kept_with_its_three_readings(aggregates):
    for run in aggregates["runs"].values():
        mass = run["mass"]
        assert mass["total_kg_m2"] == pytest.approx(mass["main_kg_m2"] + mass["tail_kg_m2"], abs=1e-5)
        for row in mass["accumulated_at"].values():
            assert row["block_starts_at_marker"] <= row["block_ends_at_marker"]
            assert row["reading_half_width"] > 0.0


# --- control 9: an absent uncertainty is not zero --------------------------------------------

def test_an_absent_uncertainty_keeps_the_total_absent(result, record):
    assert cone.combined_uncertainty([0.03, None]) is None
    assert cone.combined_uncertainty([0.03, 0.04]) == pytest.approx(0.05)
    assert result["uncertainty"]["instrument"] is None
    assert result["uncertainty"]["combined"] is None
    assert len(record["contract"]["uncertainties_absent"]) >= 5


# --- control 10: no extrapolation of properties ----------------------------------------------

def test_the_boiling_point_lies_outside_the_liquid_support(result, props):
    support = result["support"]
    assert support["boiling_point_inside_liquid_support"] is False
    assert support["initial_temperature_inside_liquid_support"] is True
    with pytest.raises(ValueError):
        net.enthalpy(props["liquid"], 98.5 + 273.15, "boiling point")


def test_the_storage_is_not_evaluated_at_the_boiling_point(props):
    with pytest.raises(ValueError):
        cone.storage_bracket(props, 5.0, [6.0, 19.0], 20.0, 90.0, None, 98.5, 684.0)


def test_the_vapour_is_not_evaluated_below_the_gas_support(props):
    with pytest.raises(ValueError):
        cone.demand_per_kg_range(props, [15.0, 19.0], [20.0, 98.5])
    low, high = cone.demand_per_kg_range(props, [15.0, 30.0], [25.0, 98.5])
    assert low == pytest.approx(354.5, abs=0.5) and high == pytest.approx(521.2, abs=0.5)


def test_no_window_reaches_past_the_support_and_no_reading_is_clipped(result, record, aggregates):
    limit = record["support"]["liquid_upper_k"] - 273.15
    for name, run in result["runs"].items():
        for window in run["windows"].values():
            if window:
                assert window["lower_thermocouple_c"] < limit
                if window["upper_thermocouple_c"] is not None:
                    assert window["upper_thermocouple_c"] < limit
        for key in ("upper", "lower"):
            trace = aggregates["runs"][name][key]
            if trace:
                # the plateau is reported as read, above the support, never moved onto its edge
                assert trace["highest_near_boiling_c"] > limit


def test_the_support_ends_a_trace_before_its_reading_range_leaves_it():
    """Synthetic trace: 97.5 with a half width of 0.8 is already outside a limit of 97.95."""
    curve = {"readings": [{"t_s": 15.0 * k, "value": value, "half_width": 0.8, "status": "read"}
                          for k, value in enumerate([20.0, 60.0, 97.5, 99.0, 100.0, 140.0])]}
    trace = cone.temperature_aggregates(curve, 97.95)
    assert trace["last_inside_support_s"] == 15.0
    assert trace["plateau_s"] == [30.0, 60.0]
    assert trace["highest_near_boiling_c"] == 100.0
    assert trace["first_marker_after_plateau_s"] == 75.0


def test_immersion_is_confirmed_only_while_the_mass_keeps_the_surface_above():
    """Synthetic run: 10 kg/m2 at 1000 kg/m3 is 10 mm; 1 kg/m2 leaves every block of 100 s."""
    readings = [{"t_s": 100.0 * k, "value": 0.0 if k == 0 or k > 10 else 10.0, "half_width": 0.0, "status": "read"}
                for k in range(13)]
    table = cone.mass_table({"readings": readings}, 100.0)
    assert table["end_of_fall_s"] == 1100.0 and table["central"][-1] == pytest.approx(10.0)
    # a thermocouple at 6 mm with a margin of 1 mm needs 7 mm of liquid: three blocks may go
    assert cone.immersion_confirmed_until(table, 6.0, 1.0, 1000.0) == 300.0
    assert cone.immersion_confirmed_until(table, 12.0, 1.0, 1000.0) is None


# --- control 11: one decision does not approve another ---------------------------------------

def _facts(result, **changes):
    facts = copy.deepcopy(result["facts"])
    facts.update(changes)
    return facts


def test_the_five_decisions_are_separate(result):
    assert set(result["decisions"]) == set(cone.DECISIONS)
    assert result["decisions"] == {
        "observables_eligibility": "GO_partial_digitised_mass_and_two_point_temperatures",
        "incident_irradiation": "GO_partial_nominal_set_point_and_calculated_geometric_range",
        "net_absorbed_heat": "NO_GO_not_identified",
        "heating_validation": "GO_partial_lower_point_temperature_inside_support_NO_GO_energy_mean_and_surface_temperature",
        "emission_validation": "NO_GO_no_independent_thermal_input",
    }
    assert result["sim_implementation"] == "not_authorised"
    assert result["co_fed"] == "OFF_NO_GO"


def test_approving_the_heating_does_not_approve_the_emission(result):
    base = cone.decide(result["facts"])
    heated = cone.decide(_facts(result, temperature_profile_measured=True, frontier_identified=True))
    assert heated["heating_validation"] == "GO"
    assert heated["emission_validation"] == base["emission_validation"] == "NO_GO_no_independent_thermal_input"


def test_measuring_the_irradiation_does_not_identify_the_net_heat(result):
    base = cone.decide(result["facts"])
    measured = cone.decide(_facts(result, in_test_irradiation_measured=True))
    assert measured["incident_irradiation"] == "GO"
    for key in cone.DECISIONS:
        if key != "incident_irradiation":
            assert measured[key] == base[key]


def test_identifying_the_net_heat_alone_does_not_approve_heating_or_emission(result):
    identified = cone.decide(_facts(result, frontier_identified=True))
    assert identified["net_absorbed_heat"] == "GO"
    assert identified["heating_validation"].startswith("GO_partial")
    assert identified["emission_validation"].startswith("NO_GO")


# --- geometry --------------------------------------------------------------------------------

CONE = {"base_radius_mm": 80.0, "top_radius_mm": 40.0, "height_mm": 68.0}


def test_configuration_factors_by_hand():
    assert cone.disc_factor(1.0, 1.0, 0.0) == pytest.approx(0.5)
    by_hand = 6400.0 / (1600.0 + 6400.0) - 1600.0 / (108.0 ** 2 + 1600.0)
    assert cone.frustum_factor(40.0, 0.0, CONE) == pytest.approx(by_hand)
    assert cone.frustum_factor(40.0, 1.0e-6, CONE) == pytest.approx(cone.frustum_factor(40.0, 0.0, CONE), abs=1e-6)
    assert cone.frustum_factor(65.0, 0.0, CONE) < cone.frustum_factor(40.0, 0.0, CONE)
    assert cone.frustum_factor(40.0, 49.0, CONE) < cone.frustum_factor(40.0, 0.0, CONE)


def test_the_quadrature_agrees_with_the_closed_form_and_the_rim_only_removes():
    analytic = cone.area_average_factor(40.0, 98.0, CONE)
    assert cone.hemisphere_factor(15.0, 98.0, CONE, 25.0, rim=False) == pytest.approx(analytic, abs=0.002)
    screened = cone.hemisphere_factor(15.0, 98.0, CONE, 25.0, rim=True)
    assert screened < analytic
    # with the liquid flush with the rim nothing is screened
    flush = cone.hemisphere_factor(0.0, 98.0, CONE, 40.0, rim=False)
    assert cone.hemisphere_factor(0.0, 98.0, CONE, 40.0, rim=True) == pytest.approx(flush)


def test_the_printed_view_factors_are_not_an_area_average(result):
    geometry = result["geometry"]
    assert geometry["authors"] == {"start": 0.95, "end": 0.7, "ratio": pytest.approx(0.7368, abs=1e-4)}
    assert geometry["area_average"]["start"] == pytest.approx(0.911, abs=0.002)
    assert geometry["area_average"]["end"] == pytest.approx(0.670, abs=0.002)
    assert geometry["authors_values_reproduced_by_area_average"] is False
    assert geometry["authors_values_reproduced_by_line_average"] is False
    assert geometry["authors_ratio_reproduced"] is True
    assert geometry["quadrature_error"] < 0.001


def test_the_rim_lowers_the_calculated_irradiation_further(result):
    rows = result["geometry"]["by_side_mm"]["98"]
    assert rows["initial_nominal"]["area_average_with_rim"] == pytest.approx(0.838, abs=0.002)
    assert rows["empty"]["area_average_with_rim"] == pytest.approx(0.557, abs=0.002)
    for row in rows.values():
        assert row["area_average_with_rim"] < row["area_average_open"] < row["centre"] <= 1.0


def test_the_pan_holds_a_large_share_of_the_heat_capacity(result):
    pan = result["pan"]
    assert pan["bottom_kj_m2_k"] == pytest.approx(8000.0 * 0.4 * 0.0021)
    assert pan["pan_over_liquid"] == pytest.approx(0.44, abs=0.01)


# --- what the data show ----------------------------------------------------------------------

def test_the_digitisation_recovers_the_two_printed_peaks_and_the_boiling_line(result):
    check = result["digitisation_check"]
    assert check["digitised_peaks_g_m2_s"]["25"] == pytest.approx(48.0, abs=1.0)
    assert check["digitised_peaks_g_m2_s"]["50"] == pytest.approx(86.0, abs=1.0)
    assert check["boiling_line_read_c"] == [pytest.approx(98.5, abs=0.5)]


def test_the_repetitions_do_not_evaporate_the_same_mass(result):
    low, high = result["repeatability"]["evaporated_main_kg_m2"]
    assert low == pytest.approx(13.95, abs=0.05) and high == pytest.approx(16.08, abs=0.05)
    assert result["repeatability"]["evaporated_mass_spread_between_runs"] == pytest.approx(0.153, abs=0.005)
    assert result["repeatability"]["initial_mass_reported"] is False


def test_the_lower_thermocouple_is_usable_in_every_run_and_the_upper_in_three(result):
    usable = result["usable_temperature_stretch_s"]
    assert usable["lower"] == {"H25#1": 345.0, "H25#2": 315.0, "H50#1": 180.0, "H50#2": 180.0, "H50#3": 165.0}
    assert usable["upper"] == {"H25#1": 90.0, "H25#2": None, "H50#1": 45.0, "H50#2": 30.0, "H50#3": None}


def test_the_whole_test_demand_is_a_fraction_of_the_nominal_irradiation(result):
    for level, low, high in (("25", 0.40, 0.71), ("50", 0.39, 0.66)):
        summary = result["by_irradiation_level"][level]
        assert summary["whole_test_over_nominal"] == [pytest.approx(low, abs=0.01), pytest.approx(high, abs=0.01)]
        assert summary["any_window_discriminates"] is False
    for run in result["runs"].values():
        low, high = run["whole_test"]["over_geometric_incident"]
        assert low < 1.0 < high  # the calculated incident range neither excludes nor proves full absorption


def test_the_peak_comparison_of_the_paper_is_reproduced_and_does_not_discriminate(result):
    peak = result["peak_discrepancy"]
    assert [row["printed_reproduced"] for row in peak["rows"]] == [True, True]
    assert peak["rows"][0]["deviation"]["nominal"] == pytest.approx(-0.395, abs=0.002)
    assert peak["rows"][1]["deviation"]["nominal"] == pytest.approx(-0.458, abs=0.002)
    assert peak["rows"][0]["deviation"]["area_average_with_rim"] > 0.0 > peak["rows"][0]["deviation"]["authors_factor"]
    assert peak["residual_changes_sign_with_geometry"] == {"25": True, "50": True}
    assert peak["discriminates_energy_from_transfer"] is False
    statuses = " ".join(cause["status"] for cause in peak["causes"])
    assert "proposed" in statuses and "not measured" in statuses and "a fit, not a measurement" in statuses


def test_the_thermocouple_plateau_is_not_a_level_marker(result):
    gaps = [run["thermocouples"]["lower"]["leaves_plateau_minus_end_of_fall_s"] for name, run in result["runs"].items()
            if name.startswith("H25") and "lower" in run["thermocouples"]]
    assert gaps == [-30.0, 15.0]
    assert result["by_irradiation_level"]["25"]["lower_highest_near_boiling_c"] > 105.0


# --- saved results and local recomputation ---------------------------------------------------

def test_the_saved_audit_is_the_audit(result):
    assert result == json.loads(cone.SAVED.read_text(encoding="utf-8"))


def test_the_aggregates_are_recomputed_from_the_local_digitisation(record, aggregates):
    series = digitiser.load_series()
    if series is None:
        pytest.skip("no local digitisation in this checkout: the aggregates were not recomputed")
    assert cone.aggregates_from_series(series, record) == aggregates


def test_the_local_document_gives_the_digitisation_named_by_the_record(record):
    if not digitiser.LOCAL_PDF.is_file():
        pytest.skip("no local copy of the article in this checkout: the figures were not digitised again")
    assert digitiser.digitise(digitiser.LOCAL_PDF)["series_sha256"] == record["digitisation"]["series_sha256"]


# --- digitiser on a synthetic figure ---------------------------------------------------------

PANEL = {"frame": [20, 260, 20, 260], "axes": [0.0, 150.0, 0.0, 100.0]}


def _canvas():
    numpy = pytest.importorskip("numpy")
    pixels = numpy.full((300, 300, 3), 255, dtype=int)
    for k in range(20, 261):
        pixels[20, k] = pixels[260, k] = pixels[k, 20] = pixels[k, 260] = (38, 38, 38)
    return pixels


def _draw(pixels, marker, colour, column, row):
    for dy, dx in digitiser.template(marker):
        pixels[row + dy, column + dx] = colour


def test_the_digitiser_reads_a_marker_where_it_was_drawn():
    pixels = _canvas()
    rows = {0.0: 200, 15.0: 180, 30.0: 150, 45.0: 151, 60.0: 90}
    for time, row in rows.items():
        _draw(pixels, "plus", (0, 0, 255), round(digitiser.to_column(PANEL, time)), row)
    assert digitiser.frame_is_drawn(pixels, PANEL["frame"])
    readings = digitiser.read_curve(pixels, PANEL, "blue", "plus", 60.0)
    assert [reading["status"] for reading in readings] == ["read"] * 5
    for reading in readings:
        assert reading["value"] == pytest.approx(digitiser.to_value(PANEL, rows[reading["t_s"]]), abs=1.5 * 100.0 / 240.0)
        assert reading["half_width"] == pytest.approx(1.5 * 100.0 / 240.0, abs=1e-3)


def test_a_marker_hidden_under_another_curve_is_reported_as_a_range_not_as_a_point():
    pixels = _canvas()
    column = round(digitiser.to_column(PANEL, 15.0))
    _draw(pixels, "plus", (0, 0, 255), column, 120)
    _draw(pixels, "star", (255, 0, 255), column, 120)
    reading = digitiser.read_curve(pixels, PANEL, "blue", "plus", 15.0)[1]
    assert reading["status"] == "hidden_under_other_curve"
    assert reading["half_width"] >= 1.5 * 100.0 / 240.0
    assert abs(reading["value"] - digitiser.to_value(PANEL, 120)) <= reading["half_width"]


def test_a_marker_that_is_nowhere_is_not_invented():
    pixels = _canvas()
    reading = digitiser.read_curve(pixels, PANEL, "red", "circle", 0.0)[0]
    assert reading["status"] == "not_found" and reading["value"] is None


def test_the_digitiser_refuses_a_document_that_is_not_the_reviewed_one(tmp_path):
    other = tmp_path / "other.pdf"
    other.write_bytes(b"%PDF-1.4 not the article")
    with pytest.raises(ValueError):
        digitiser.load_figures(other)


def test_the_fingerprint_of_a_series_changes_with_one_reading():
    body = {"curves": [{"run": "H50#1", "panel": "figure_4b", "readings": [{"t_s": 15.0, "value": 20.7, "status": "read"}]}]}
    first = digitiser.series_sha256(body)
    body["curves"][0]["readings"][0]["value"] = 20.8
    assert digitiser.series_sha256(body) != first


def test_every_control_variant_still_finds_the_rule_it_rewrites():
    from scripts.simulation import run_g3_cone_benchmark_control_mutations as variants
    source = variants.SOURCE.read_text(encoding="utf-8")
    assert len(variants.VARIANTS) == 20
    assert len({name for name, _old, _new in variants.VARIANTS}) == 20
    for name, old, new in variants.VARIANTS:
        assert source.count(old) == 1, name
        assert old != new, name


def test_the_auditor_holds_no_solver_and_no_fit():
    import inspect
    source = inspect.getsource(cone)
    for word in ("minimize", "curve_fit", "least_squares", "odeint", "solve_ivp"):
        assert word not in source
    assert "SimulationEngine" not in source and "res://" not in source
