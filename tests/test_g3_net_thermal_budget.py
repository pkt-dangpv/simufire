"""Offline gate of the net thermal budget of the liquid fuel, B.

Hand oracles and negative controls of scripts/simulation/audit_g3_net_thermal_budget.py.
They are Python controls of an offline audit, not mutations of the engine, and
nothing here starts Godot. The hand values were worked out from the printed
tables before the auditor was run.
"""
import copy
import hashlib
import inspect
import json
import math
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_net_thermal_budget as budget

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def record():
    return budget.load_profile(budget.INPUT)


@pytest.fixture(scope="module")
def props():
    return budget.properties()


@pytest.fixture(scope="module")
def result():
    return budget.audit()


def _sandia(record, props, edit=None):
    candidate = copy.deepcopy(record["candidates"]["sandia_2m"])
    if edit:
        edit(candidate)
    return budget.sandia(candidate, props, record["criteria"])


# --- the saved result and the decisions ---------------------------------------

def test_saved_audit_is_reproduced(result):
    saved = json.loads(budget.SAVED.read_text(encoding="utf-8"))
    assert saved == json.loads(json.dumps(result))


def test_decisions_are_separate_and_no_approval_is_granted(result):
    assert result["decisions"] == {
        "benchmark_eligibility": "GO_partial_stationary_open_pool_2m_heptane",
        "net_B_identifiability": "GO_partial_bounded_stationary_rate_NO_GO_point_value",
        "balance_scope": "stationary_mean_only_NO_GO_transient",
        "thermal_prediction": "NO_GO",
        "emission_prediction": "NO_GO",
        "second_condition_consistent_at_loose_level": False,
        "second_condition_strict": False,
    }
    for flag in ["predictive_thermal_input_approval", "predictive_emission_approval", "engine_integration",
                 "production_activation", "co_fed_approval"]:
        assert result[flag] is False
    assert result["selected"] == "sandia_2m" and result["second_condition"] == "nist_030m"
    assert "no approved property profile" in result["rejected"]["nist_alcohols_030m"]


def test_definition_says_what_B_is_not(record):
    definition = record["definition"]
    for excluded in ["heat_release_rate", "chemical_heat_of_oxidation", "flux_to_a_sensor",
                     "latent_heat_inferred_from_mass_loss", "enthalpy_carried_by_feed_or_vapour"]:
        assert excluded in definition["excludes"]
    assert definition["control_volume"].startswith("liquid phase only, open system at constant pressure")
    assert "is not heating" in definition["ledger_mapping"]["double_counting_guard"]


# --- hand oracles --------------------------------------------------------------

def test_ring_average_matches_hand_arithmetic(result):
    run = result["sandia_2m"]["tests"]["SNL011"]
    # (32.1+31.9)/2, (31.3+33.5)/2, 33.3, (29.2+28.9)/2, (27.0+26.8)/2, (26.0+23.9)/2
    assert run["ring_mean_kw_m2"] == pytest.approx([32.0, 32.4, 33.3, 29.05, 26.9, 24.95], abs=1e-12)
    assert run["pan_average_kw_m2"] == pytest.approx(178.6 / 6, abs=1e-12)
    assert result["sandia_2m"]["area_m2"] == pytest.approx(math.pi, abs=1e-12)
    assert run["gauge_power_kw"] == pytest.approx(178.6 / 6 * math.pi, abs=1e-9)
    # Reflection bounded between 0 and 10 % of what the gauge reads.
    assert run["independent_kw_range"] == pytest.approx([0.9 * run["gauge_power_kw"], run["gauge_power_kw"]])


def test_demand_matches_an_estimate_from_handbook_values(result):
    """About 329 kJ/kg of vaporisation at 357 K plus 2.37 kJ/(kg K) over 51 K of liquid."""
    run = result["sandia_2m"]["tests"]["SNL011"]
    assert run["feed_temperature_k"] == 306.15 and run["surface_temperature_k"] == 357.15
    assert run["demand_kj_kg"] == pytest.approx(329.0 + 2.37 * 51.0, rel=0.015)
    assert run["demand_kw"] == pytest.approx(0.1935 * run["demand_kj_kg"], rel=1e-12)
    low, high = run["demand_kj_kg_range"]
    assert low < run["demand_kj_kg"] < high and high - low == pytest.approx(25.0, abs=1.5)


def test_second_condition_matches_hand_arithmetic(result):
    nist = result["nist_030m"]
    gauge = 1.2414317529925425                      # integral of 2026-10-04, unchanged
    assert nist["gauge_power_kw"] == gauge
    assert nist["published_q_fuel_kw"] == pytest.approx(0.010 * 116, abs=1e-12)
    area = math.pi * 0.1505 ** 2
    losses = (0.04 + 0.03) * 1.16
    expected = [gauge * (1 - 0.08 * 0.80) - losses + 0.3 * area, gauge * (1 - 0.05 * 0.80) - losses + 0.3 * area]
    assert nist["independent_kw_range"] == pytest.approx(expected, abs=1e-12)
    assert nist["independent_kw_range"] == pytest.approx([1.1021, 1.1319], abs=2e-4)
    assert nist["storage_growth_kw"] == pytest.approx(0.04 * 1.16, abs=1e-12)
    assert nist["channels_from_one_run"] is False and nist["surface_temperature_accepted_k"] is None
    # With real properties it does not close: the independent side falls 5 to 21 % short.
    assert nist["closure"]["relative_gap_range"] == pytest.approx([-0.209, -0.049], abs=2e-3)
    assert nist["closure"]["strict_closure"] is False and nist["closure"]["loose_closure"] is False


def test_closure_of_the_selected_benchmark(result):
    selected = result["sandia_2m"]
    assert selected["tests_in_balance"] == ["SNL011", "SNL012", "SNL029"]
    assert selected["strict_fraction"] == pytest.approx(math.hypot(0.03, 0.019), abs=1e-12)
    worst = [selected["tests"][name]["closure"]["worst_relative_gap"] for name in selected["tests_in_balance"]]
    assert worst == pytest.approx([0.098, 0.118, 0.125], abs=2e-3)
    assert selected["loose_closure_every_run"] is True and selected["strict_closure_every_run"] is False
    # Zero lies inside the interval of the unknown block in every run: nothing forces a sign.
    for name in selected["tests_in_balance"]:
        low, high = selected["tests"][name]["unknown_block_kw_range"]
        assert low < 0 < high
    assert selected["unknown_terms"] == ["container_and_ground_losses", "gauge_to_surface_convective_difference",
                                         "liquid_storage_growth", "vapour_dome_absorption_below_the_gauge"]
    assert selected["total_uncertainty_quantified"] is False and selected["combined_gauge_uncertainty"] is None


def test_heat_flux_does_not_track_the_mass_rate_between_runs(result):
    """The run without glass beads burns 6 % less with the same heat flux: no B/L rule follows."""
    tracking = result["sandia_2m"]["run_to_run"]
    assert tracking["SNL012"]["heat_flux_change"] == pytest.approx(0.063, abs=2e-3)
    assert tracking["SNL012"]["mass_rate_change"] == pytest.approx(201.0 / 193.5 - 1, abs=1e-12)
    assert tracking["SNL029"]["heat_flux_change"] == pytest.approx(-0.005, abs=2e-3)
    assert tracking["SNL029"]["mass_rate_change"] == pytest.approx(181.3 / 193.5 - 1, abs=1e-12)
    assert abs(tracking["SNL029"]["heat_flux_change"]) < 0.1 * abs(tracking["SNL029"]["mass_rate_change"])


def test_sensitivities_and_property_checks(result):
    s, checks = result["sensitivities"], result["property_checks"]
    assert s["demand_change_per_k_of_feed_temperature"] == pytest.approx(-0.0050, abs=2e-4)
    assert s["demand_change_per_k_of_surface_temperature"] == pytest.approx(0.0042, abs=2e-4)
    # 3.1416 m2 x 0.019 m x 683.68 kg/m3
    assert s["liquid_inventory_above_baffle_kg"] == pytest.approx(math.pi * 0.019 * 683.68, rel=1e-9)
    assert s["storage_kw_per_k_per_minute_over_gauge_power"] == pytest.approx(0.0165, abs=5e-4)
    # Superheating the vapour to the end of the gas support alone takes half of what the gauges read.
    assert s["vapour_superheat_to_gas_support_end_over_gauge_power"] == pytest.approx(0.50, abs=0.01)
    assert s["deficit_at_independent_upper_bound_kw"] == 0.0 and 3.0 < s["deficit_at_independent_lower_bound_kw"] < 4.0
    assert checks["latent_basis_gap_kj_kg"] == pytest.approx(7.25, abs=0.01)
    assert checks["latent_basis_gap_over_demand"] == pytest.approx(0.016, abs=1e-3)
    assert checks["control_volume_at_the_gauge_plane_200_c"].startswith("refused")
    assert checks["liquid_pv_work_per_k_over_cp"] < 1e-4 and checks["mass_basis_relevant_to_B"] is False


# --- units, signs and double counting ------------------------------------------

def test_unit_slips_are_detected(record, props):
    assert budget.watts_to_kilowatts(1500.0) == 1.5 and budget.grams_to_kilograms(193.5) == 0.1935
    assert budget.celsius_to_kelvin(84) == 357.15
    with pytest.raises(ValueError, match="percentage"):
        budget.fraction(3, "uncertainty")            # 3 % typed as 3
    with pytest.raises(ValueError, match="percentage"):
        budget.rss(0.03, 1.9)
    base = _sandia(record, props)

    def kilograms(candidate):                        # kg/s typed where g/s is declared
        for test in candidate["tests"].values():
            if test["burn_rate_g_s"] is not None:
                test["burn_rate_g_s"] /= 1000.0
    with pytest.raises(ValueError, match="disagree"):
        _sandia(record, props, kilograms)

    def watts(candidate):                            # W/m2 typed where kW/m2 is declared
        for test in candidate["tests"].values():
            test["gauge_kw_m2"] = [None if v is None else v * 1000.0 for v in test["gauge_kw_m2"]]
    with pytest.raises(ValueError, match="printed ring means"):
        _sandia(record, props, watts)
    # A rate multiplied by its window is an accumulated energy; as a rate it is off by hundreds.
    run = base["tests"]["SNL011"]
    accumulated = run["gauge_power_kw"] * 5.5 * 60.0
    gap = budget.closure([accumulated, accumulated], run["demand_kw_range"], base["strict_fraction"], 0.20)
    assert gap["loose_closure"] is False and gap["worst_relative_gap"] > 300
    joules = budget.demand_rate_kw(193.5, run["demand_kj_kg"] * 1000.0)   # J/kg typed where kJ/kg is declared
    assert budget.closure(run["independent_kw_range"], [joules, joules], 0.0355, 0.20)["loose_closure"] is False


def test_signs(props):
    base = budget.demand_per_kg(props, 357.15, 306.15)
    assert budget.demand_per_kg(props, 357.15, 296.15) > base      # colder feed costs more
    assert budget.demand_per_kg(props, 367.15, 306.15) > base      # hotter vapour costs more
    assert budget.enthalpy(props["liquid"], 290.0, "t") < 0 < budget.enthalpy(props["liquid"], 310.0, "t")
    # A loss lowers the independent estimate and a gain raises it; never the other way.
    assert budget.independent_rate_kw(100.0, 0.0, [5.0]) == 95.0
    assert budget.independent_rate_kw(100.0, 0.0, [], [5.0]) == 105.0
    assert budget.independent_rate_kw(100.0, 0.1) == pytest.approx(90.0)
    gap = budget.closure([90.0, 90.0], [100.0, 100.0], 0.05, 0.20)
    assert gap["worst_relative_gap"] == pytest.approx(-0.10) and gap["strict_closure"] is False


def test_storage_and_latent_are_counted_once(props):
    per_kg = budget.demand_per_kg(props, 357.15, 306.15)
    latent = props["latent_kj_kg"]
    gas = budget.enthalpy(props["gas"], 357.15, "t")
    liquid = budget.enthalpy(props["liquid"], 306.15, "t")
    assert per_kg == pytest.approx(latent + gas - liquid, abs=1e-12)
    # Heating the feed to the surface temperature is already inside: adding it again is a double count.
    feed_heating = budget.enthalpy(props["liquid"], 357.15, "t") - liquid
    assert feed_heating > 100.0
    assert budget.demand_rate_kw(193.5, per_kg) == pytest.approx(0.1935 * per_kg)
    assert budget.demand_rate_kw(193.5, per_kg, 2.0) == pytest.approx(0.1935 * per_kg + 2.0)
    doubled = budget.demand_rate_kw(193.5, per_kg + feed_heating)
    assert doubled / budget.demand_rate_kw(193.5, per_kg) > 1.25
    assert budget.demand_rate_kw(193.5, per_kg + latent) / budget.demand_rate_kw(193.5, per_kg) > 1.8


# --- what a sensor reads is not what the liquid absorbs -------------------------

def test_gauge_reading_is_never_reported_as_B(result):
    text = json.dumps(result)
    for forbidden in ["liquid_net_B_kj", "\"B_kj\"", "thermal_budget_kj", "B_from_gauge"]:
        assert forbidden not in text
    selected = result["sandia_2m"]
    for run in selected["tests"].values():
        assert run["independent_uses_mass"] is False
    assert result["decisions"]["net_B_identifiability"].endswith("NO_GO_point_value")
    assert selected["term_status"]["gauge_heat_flux"] == "measured"
    assert selected["term_status"]["vapour_dome_absorption_below_the_gauge"] == "unknown"


def test_relabelling_unknown_terms_does_not_approve_a_point_value(record, props):
    def relabel(candidate):
        for name, text in candidate["term_status"].items():
            if text.startswith("unknown"):
                candidate["term_status"][name] = "measured " + text
    relabelled = _sandia(record, props, relabel)
    assert relabelled["unknown_terms"] == []
    second = budget.nist(record["candidates"]["nist_030m"], props, record["criteria"], 1.2414317529925425)
    # Strict closure still fails, so the verdict cannot become a point value.
    assert budget.decisions(relabelled, second)["net_B_identifiability"] == (
        "GO_partial_bounded_stationary_rate_NO_GO_point_value")
    changed = copy.deepcopy(record)
    relabel(changed["candidates"]["sandia_2m"])
    with pytest.raises(ValueError, match="unreviewed values"):
        budget.audit(changed)


# --- spatial support, synchronisation and mixing of runs ------------------------

def test_area_integral_needs_support(record, props):
    def dead_ring(candidate):
        candidate["tests"]["SNL011"]["gauge_kw_m2"][11] = None      # ring 3 loses its only working gauge
    with pytest.raises(ValueError, match="no working gauge"):
        _sandia(record, props, dead_ring)

    def missing_ring(candidate):
        candidate["rings"]["gauges_by_ring"] = candidate["rings"]["gauges_by_ring"][:5]
    with pytest.raises(ValueError, match="do not cover the pan"):
        _sandia(record, props, missing_ring)

    def negative(candidate):
        candidate["tests"]["SNL011"]["gauge_kw_m2"][0] = -29.2
    with pytest.raises(ValueError, match="negative heat flux|printed ring means"):
        _sandia(record, props, negative)
    assert budget.ring_average([10.0, None, 30.0], [[1, 2], [3]]) == ([10.0, 30.0], 20.0)


def test_channels_must_belong_to_one_run(record, props, result):
    assert result["sandia_2m"]["tests"]["SNL030"]["in_balance"] is False
    assert "demand_kw" not in result["sandia_2m"]["tests"]["SNL030"]

    def mass_without_window(candidate):
        candidate["tests"]["SNL011"]["valid_window_min"] = None
    with pytest.raises(ValueError, match="without its window"):
        _sandia(record, props, mass_without_window)

    def mass_of_another_run(candidate):                # the flux of SNL011 with the mass of SNL029
        candidate["tests"]["SNL011"]["burn_rate_g_s"] = candidate["tests"]["SNL029"]["burn_rate_g_s"]
    with pytest.raises(ValueError, match="disagree"):
        _sandia(record, props, mass_of_another_run)

    def flux_of_another_run(candidate):                # the gauges of SNL012 under the label SNL011
        candidate["tests"]["SNL011"]["gauge_kw_m2"] = list(candidate["tests"]["SNL012"]["gauge_kw_m2"])
    with pytest.raises(ValueError, match="printed ring means"):
        _sandia(record, props, flux_of_another_run)


# --- no circular use of the mass loss -------------------------------------------

def test_independent_estimate_takes_no_mass(record, props):
    names = set(inspect.signature(budget.independent_rate_kw).parameters)
    assert names == {"gauge_kw", "reflected_fraction", "subtract_kw", "add_kw"}
    assert not {"mass", "mass_rate", "burn_rate", "residual", "demand"} & names
    base = _sandia(record, props)

    def double_mass(candidate):
        for test in candidate["tests"].values():
            if test["burn_rate_g_s"] is not None:
                test["burn_rate_g_s"] *= 2.0
                test["regression_g_m2_s"] *= 2.0
    doubled = _sandia(record, props, double_mass)
    for name in base["tests_in_balance"]:
        assert doubled["tests"][name]["independent_kw_range"] == base["tests"][name]["independent_kw_range"]
        assert doubled["tests"][name]["demand_kw"] == pytest.approx(2 * base["tests"][name]["demand_kw"])
    assert doubled["loose_closure_every_run"] is False


def test_second_condition_declares_its_mass_derived_normalisation(result):
    assert result["nist_030m"]["independent_uses_mass"] is False
    assert result["nist_030m"]["independent_uses_ratio_to_mass_derived_quantity"] is True
    assert result["nist_030m"]["term_status"]["burner_loss"] == "measured"
    assert result["nist_030m"]["term_status"]["surface_temperature"] == "assumed"


# --- uncertainty, provenance and property support --------------------------------

def test_absent_uncertainty_is_not_zero(record, props):
    with pytest.raises(ValueError, match="not zero"):
        budget.rss(0.03, None)
    uncertainty = record["candidates"]["sandia_2m"]["uncertainty"]
    assert uncertainty["gauge_combined_for_fuel_surface"] is None
    assert record["candidates"]["sandia_2m"]["reflectance"]["hemispherical_total"] is None

    def no_mass_uncertainty(candidate):
        candidate["uncertainty"]["mass_rate_fraction_example"] = None
    with pytest.raises(ValueError, match="not zero"):
        _sandia(record, props, no_mass_uncertainty)
    changed = copy.deepcopy(record)
    changed["candidates"]["sandia_2m"]["uncertainty"]["gauge_combined_for_fuel_surface"] = 0.0
    with pytest.raises(ValueError, match="unreviewed values"):
        budget.audit(changed)


@pytest.mark.parametrize("path, value", [
    (("candidates", "sandia_2m", "tests", "SNL011", "burn_rate_g_s"), 193.6),
    (("candidates", "sandia_2m", "tests", "SNL029", "gauge_kw_m2"),
     [27.0, None, 27.4, 22.9, 28.9, 27.1, 31.3, 22.7, 34.1, 33.8, 33.7, 33.3]),
    (("candidates", "sandia_2m", "surface_temperature_c"), 98.4),
    (("candidates", "sandia_2m", "tests_locator"), "Table 1"),
    (("candidates", "sandia_2m", "term_status", "container_and_ground_losses"), "demonstrably null"),
    (("candidates", "nist_030m", "minor_terms_over_q_fuel", "burner_loss"), 0.0),
    (("candidates", "nist_030m", "surface_temperature_k"), 371.102911),
    (("sources", "sandia_2011", "sha256_raw"), "0" * 64),
    (("sources", "hamins_1994", "archived"), True),
    (("criteria", "loose_closure_fraction"), 0.5),
    (("review", "predictive_thermal_input_approval"), True),
    (("review", "predictive_emission_approval"), True),
    (("review", "selected"), "nist_030m"),
    (("definition", "excludes"), []),
])
def test_altered_data_provenance_criteria_or_approval_is_rejected(record, path, value):
    changed = copy.deepcopy(record)
    holder = changed
    for key in path[:-1]:
        holder = holder[key]
    assert holder[path[-1]] != value
    holder[path[-1]] = value
    with pytest.raises(ValueError, match="unreviewed values"):
        budget.audit(changed)


def test_source_bytes_are_bound_not_only_the_record(record, monkeypatch):
    changed = copy.deepcopy(record)
    changed["sources"]["sandia_2011"]["sha256_raw"] = "0" * 64
    digest = hashlib.sha256(json.dumps(changed, sort_keys=True, allow_nan=False).encode("utf-8")).hexdigest()
    monkeypatch.setattr(budget, "REVIEW_SHA256", digest)
    with pytest.raises(ValueError, match="artifact content mismatch"):
        budget.audit(changed)


def test_record_hash_and_archived_source(record):
    digest = hashlib.sha256(json.dumps(record, sort_keys=True, allow_nan=False).encode("utf-8")).hexdigest()
    assert digest == budget.REVIEW_SHA256
    source = record["sources"]["sandia_2011"]
    raw = (ROOT / source["path"]).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == source["sha256_raw"] and len(raw) == 10652080
    assert "further dissemination unlimited" in source["rights"]
    # Sources whose redistribution is not clear are linked, not archived.
    for name in ["hamins_1994", "kim_2019"]:
        assert record["sources"][name]["archived"] is False and "path" not in record["sources"][name]


@pytest.mark.parametrize("phase, temperature", [
    ("gas", 473.15), ("gas", 469.991582), ("gas", 298.13), ("liquid", 372.0), ("liquid", 371.102912),
    ("liquid", 279.98), ("liquid", float("nan")), ("gas", float("inf")),
])
def test_properties_are_never_extrapolated(props, phase, temperature):
    with pytest.raises(ValueError):
        budget.enthalpy(props[phase], temperature, "control")


def test_properties_at_the_ends_of_their_support(props):
    for phase in ["liquid", "gas"]:
        samples = props[phase]
        for end in [samples[0]["temperature_k"], samples[-1]["temperature_k"]]:
            assert math.isfinite(budget.enthalpy(samples, end, "end"))
    with pytest.raises(ValueError, match="outside the approved support"):
        budget.demand_per_kg(props, 473.15, 306.15)       # vapour at the gauge plane
    with pytest.raises(ValueError, match="outside the approved support"):
        budget.demand_per_kg(props, 357.15, 372.0)        # liquid above its own support


@pytest.mark.parametrize("value", [True, "1", None, float("nan"), float("inf"), [1.0]])
def test_numbers_are_strict(value):
    with pytest.raises(ValueError):
        budget.number(value, "control")


def test_auditor_is_offline_and_touches_no_engine():
    source = Path(budget.__file__).read_text(encoding="utf-8")
    for forbidden in ["godot", "subprocess", "sim/fire", "res://", "write_text", "write_bytes", "open(", "requests",
                      "urllib"]:
        assert forbidden not in source.replace("starts\nGodot", "").replace("Godot, reads", ""), forbidden
    assert "Nothing here starts" in source
