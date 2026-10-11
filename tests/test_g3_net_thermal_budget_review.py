"""Revision of 2026-10-07 of the gate of the net thermal budget of the fuel, B.

The gate of 2026-10-06 called B a bounded stationary rate. That is withdrawn:
its band was the gauge reading times a reflection range and bounded none of
the other terms between the gauge plane and the liquid. These are offline
controls of the revision, not mutations of the engine; nothing starts Godot.
The hand values were worked out from the printed sources before the auditor
was extended.
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
    return budget.load_profile(budget.REVIEW_INPUT)


@pytest.fixture(scope="module")
def result():
    return budget.review()


@pytest.fixture(scope="module")
def history():
    return budget.audit()


def _repinned(monkeypatch, changed):
    digest = hashlib.sha256(json.dumps(changed, sort_keys=True, allow_nan=False).encode("utf-8")).hexdigest()
    monkeypatch.setattr(budget, "REVISION_SHA256", digest)
    return changed


# --- the revised decision and the history it keeps -------------------------------

def test_saved_results_are_reproduced_and_history_is_kept(result, history):
    assert json.loads(budget.REVIEW_SAVED.read_text(encoding="utf-8")) == json.loads(json.dumps(result))
    # The audit of 2026-10-06 is not rewritten: it still reproduces, with its superseded verdict.
    assert json.loads(budget.SAVED.read_text(encoding="utf-8")) == json.loads(json.dumps(history))
    assert history["decisions"]["net_B_identifiability"] == budget.SUPERSEDED_VERDICT


def test_seven_separate_decisions(result):
    assert result["decisions"] == {
        "sandia_as_contrast": "GO_partial_gauge_plane_flux_and_mass_rate_as_documented_observables",
        "gauge_plane_heat": "GO_partial_measured_observable_without_combined_uncertainty",
        "net_B": "NO_GO_not_identified",
        "stationary_balance": "NO_GO_inconclusive_residual_does_not_identify_its_components",
        "transient_balance": "NO_GO",
        "thermal_prediction": "NO_GO",
        "emission_prediction": "NO_GO",
        "previous_net_B_verdict": "GO_partial_bounded_stationary_rate_NO_GO_point_value",
        "previous_net_B_verdict_status": "withdrawn",
    }
    for flag in ["predictive_thermal_input_approval", "predictive_emission_approval", "engine_integration",
                 "production_activation", "co_fed_approval"]:
        assert result[flag] is False


def test_four_objects_are_kept_apart(result, history):
    assert set(result["objects"]) == {"gauge_plane_reading", "conditional_band", "net_B", "demand"}
    for name, run in result["runs"].items():
        old = history["sandia_2m"]["tests"][name]
        assert run["gauge_plane_reading_kw"] == old["gauge_power_kw"]
        assert run["conditional_band_is_net_B"] is False
        assert run["net_B_kw"] is None and run["net_B_kw_range"] is None
        assert run["scenarios_are_identified_intervals"] is False
        assert run["residual_identifies_components"] is False
        assert run["demand_uses_mass"] is True and run["demand_kw_range"] == old["demand_kw_range"]
        low, high = run["conditional_band_kw"]
        assert low < high < run["gauge_plane_reading_kw"]
    assert sorted(result["runs"]) == ["SNL011", "SNL012", "SNL029"]
    # The residual is the revised band minus the demand; zero lies inside it in every run.
    residual = result["runs"]["SNL011"]["residual_band_minus_demand_kw_range"]
    band, demand = result["runs"]["SNL011"]["conditional_band_kw"], result["runs"]["SNL011"]["demand_kw_range"]
    assert residual == pytest.approx([band[0] - demand[1], band[1] - demand[0]])
    assert residual == pytest.approx([-5.86, 6.48], abs=0.02)
    assert all(run["residual_band_minus_demand_kw_range"][0] < 0 < run["residual_band_minus_demand_kw_range"][1]
               for run in result["runs"].values())


# --- hand oracles ------------------------------------------------------------------

def test_hand_values(result):
    run = result["runs"]["SNL011"]
    reading = 178.6 / 6 * math.pi                         # 93.515 kW, from the printed gauges
    assert run["gauge_plane_reading_kw"] == pytest.approx(reading, abs=1e-9)
    assert run["conditional_band_kw"] == pytest.approx([0.90 * reading, 0.98 * reading], abs=1e-9)
    # Black body at 371 K, 1.0743 kW/m2 (printed 1.1); pan bottom 0.2 to 2 kW/m2; area pi m2.
    emission = 5.670374419e-8 * 371.0 ** 4 / 1000.0
    assert result["emission_bound_kw_m2"] == pytest.approx(emission, abs=1e-12)
    assert emission == pytest.approx(1.0743, abs=1e-4)
    assert result["emission_at_measured_surface_kw_m2"] == pytest.approx(0.9226, abs=1e-4)
    # Expectation corrected after the first run: the scenario subtracts the bound as the record
    # writes it, 1.0743 kW/m2, not the unrounded black-body value. The two differ by 0.00014 kW
    # over the pan; the auditor separately requires them to agree within 0.00005 kW/m2.
    bound = 1.0743
    lower = 0.90 * reading - bound * math.pi - 2.0 * math.pi
    upper = 0.98 * reading - 0.2 * math.pi
    assert run["scenario_if_gauge_plane_equals_surface_kw"] == pytest.approx([lower, upper], abs=1e-9)
    assert run["scenario_if_gauge_plane_equals_surface_kw"] == pytest.approx([74.5, 91.0], abs=0.05)
    explored = [0.70 * 0.90 * reading - bound * math.pi - 2.0 * math.pi, 1.30 * 0.98 * reading - 0.2 * math.pi]
    assert run["scenario_with_laboratory_exploration_kw"] == pytest.approx(explored, abs=1e-9)
    assert run["scenario_with_laboratory_exploration_kw"] == pytest.approx([49.3, 118.5], abs=0.05)
    # Liquid of 45 to 55 mm over pi m2 at 683.68 kg/m3, warming 0.2 to 0.5 K/min.
    storage = run["storage_estimate"]
    assert storage["liquid_mass_kg_range"] == pytest.approx([math.pi * 0.045 * 683.68, math.pi * 0.055 * 683.68])
    assert storage["storage_kw_range"] == pytest.approx([0.73, 2.24], abs=0.02)
    assert result["storage_scale_correction_factor_range"] == pytest.approx([45 / 19, 55 / 19], abs=1e-9)
    # Table 10 of the assessment report: 0.046 and 0.035 against 0.061 kg/m2s, printed -25 / -43 %.
    assert result["laboratory_balance_relative_gap"] == pytest.approx([0.046 / 0.061 - 1, 0.035 / 0.061 - 1])
    assert [round(100 * v) for v in result["laboratory_balance_relative_gap"]] == [-25, -43]


# --- a sensor band is not promoted to B --------------------------------------------

def test_unbounded_frontier_terms_block_the_identification(result, record):
    assert result["frontier_terms_blocking_identification"] == [
        "gauge_plane_to_surface", "gauge_to_surface_convection", "pan_bottom_and_ground_loss",
        "rim_conduction", "surface_reflection"]
    assert result["frontier_term_class"]["surface_emission"] == "bounded"
    assert "transmission_through_the_liquid" not in result["frontier_terms_acting"]
    assert budget.review_decisions(["gauge_plane_to_surface"], False)["net_B"] == "NO_GO_not_identified"
    assert budget.review_decisions(["rim_conduction"], True)["net_B"] == "NO_GO_not_identified"
    # Only an empty list of blocking terms identifies B.
    assert budget.review_decisions([], True)["net_B"] == "GO_partial_bounded"
    terms = copy.deepcopy(record["frontier_terms"])
    del terms["gauge_plane_to_surface"]
    with pytest.raises(ValueError, match="gauge plane to the liquid surface"):
        budget.frontier_status(terms)
    terms = copy.deepcopy(record["frontier_terms"])
    terms["surface_reflection"]["class"] = "identified"
    with pytest.raises(ValueError, match="no recognised class"):
        budget.frontier_status(terms)


def test_reclassifying_without_evidence_is_rejected(record):
    for name in ["gauge_plane_to_surface", "pan_bottom_and_ground_loss", "surface_reflection"]:
        changed = copy.deepcopy(record)
        changed["frontier_terms"][name]["class"] = "bounded"
        with pytest.raises(ValueError, match="unreviewed evidence"):
            budget.review(changed)
    # Even with every class relabelled, the rule needs ALL of them: one left unknown still blocks.
    terms = copy.deepcopy(record["frontier_terms"])
    for name in terms:
        if name != "gauge_to_surface_convection":
            terms[name]["class"] = "bounded"
    assert budget.frontier_status(terms)[2] == ["gauge_to_surface_convection"]


def test_unknown_is_null_never_zero(result, record):
    assert result["total_uncertainty_of_B"] is None
    assert result["strict_criterion_fraction"] is None
    assert result["mass_rate_uncertainty_fraction"] is None
    for name in ["gauge_plane_to_surface", "gauge_to_surface_convection"]:
        assert record["frontier_terms"][name]["range_fraction_of_reading"] is None
    assert record["frontier_terms"]["rim_conduction"]["range_kw_m2"] is None
    with pytest.raises(ValueError, match="not zero"):
        budget.rss(0.03, result["mass_rate_uncertainty_fraction"])
    changed = copy.deepcopy(record)
    changed["frontier_terms"]["gauge_plane_to_surface"]["range_fraction_of_reading"] = [0.0, 0.0]
    with pytest.raises(ValueError, match="unreviewed evidence"):
        budget.review(changed)
    # A scenario that sets the unknown terms to zero says so and is not an identified interval.
    assert all(run["scenarios_are_identified_intervals"] is False for run in result["runs"].values())


def test_contrast_threshold_is_not_identifiability(result, history):
    assert history["sandia_2m"]["loose_closure_every_run"] is True
    assert result["decisions"]["net_B"] == "NO_GO_not_identified"
    assert result["loose_threshold_role"] == "contrast_between_two_estimates_only"
    names = set(inspect.signature(budget.review_decisions).parameters)
    assert names == {"blocking", "strict_available"}          # no closure, no residual, no threshold
    assert budget.review_decisions(["x"], True) == {**budget.review_decisions(["x"], False)}


# --- independence of the heat received from the mass --------------------------------

def test_the_input_is_never_inferred_from_the_mass(result, record):
    names = set(inspect.signature(budget.conditional_net_range).parameters)
    assert names == {"reading_kw", "area_m2", "terms", "gauge_exploration"}
    assert not {"mass", "mass_rate", "demand", "residual"} & names
    terms = record["frontier_terms"]
    assert budget.conditional_net_range(100.0, 1.0, terms) == pytest.approx(
        [100.0 * 0.90 - 1.0743 - 2.0, 100.0 * 0.98 - 0.2], abs=1e-3)
    for run in result["runs"].values():
        assert run["residual_identifies_components"] is False
    source = inspect.getsource(budget.conditional_net_range)
    assert "demand" not in source and "burn_rate" not in source


def test_runs_geometries_and_windows_are_not_mixed(result, history):
    readings = [run["gauge_plane_reading_kw"] for run in result["runs"].values()]
    assert len(set(readings)) == 3
    for name, run in result["runs"].items():
        assert run["scenario_if_gauge_plane_equals_surface_kw"][1] < run["gauge_plane_reading_kw"]
    # The 0.30 m pool and the evaporation study are alternatives, never rows of this balance.
    assert result["alternatives_examined"] == ["beji_2021_cacc", "nist_030m", "sandia_one_foot_tests"]
    assert not {"nist_030m", "beji_2021_cacc", "SNL030"} & set(result["runs"])
    assert history["sandia_2m"]["tests"]["SNL030"]["in_balance"] is False


# --- storage is a demand term, not a loss at the boundary ---------------------------

def test_storage_is_not_a_frontier_loss(result, record, monkeypatch):
    for run in result["runs"].values():
        storage = run["storage_estimate"]
        assert storage["side"] == "demand" and storage["is_a_bound"] is False and storage["solids_included"] is False
        low, high = run["demand_plus_storage_kw_range"]
        assert low == pytest.approx(run["demand_kw_range"][0] + storage["storage_kw_range"][0])
        assert high == pytest.approx(run["demand_kw_range"][1] + storage["storage_kw_range"][1])
    # It never enters the estimate of the heat received.
    assert "storage" not in inspect.getsource(budget.conditional_net_range)
    assert "liquid_storage_growth" not in record["frontier_terms"]
    changed = copy.deepcopy(record)
    changed["demand_terms"]["liquid_storage_growth"]["side"] = "frontier"
    with pytest.raises(ValueError, match="placed at the boundary"):
        budget.review(_repinned(monkeypatch, changed))


def test_storage_arithmetic_and_signs(record):
    props = budget.properties()
    term = copy.deepcopy(record["demand_terms"]["liquid_storage_growth"])
    base = budget.storage_estimate_kw(props, math.pi, term, 306.15)
    term["bottom_thermocouple_rate_k_per_min"] = [0.4, 1.0]
    assert budget.storage_estimate_kw(props, math.pi, term, 306.15)["storage_kw_range"] == pytest.approx(
        [2 * base["storage_kw_range"][0], 2 * base["storage_kw_range"][1]])
    term["bottom_thermocouple_rate_k_per_min"] = [-0.1, 0.5]
    with pytest.raises(ValueError, match="nonnegative"):
        budget.storage_estimate_kw(props, math.pi, term, 306.15)
    with pytest.raises(ValueError, match="outside"):
        budget.storage_estimate_kw(props, math.pi, record["demand_terms"]["liquid_storage_growth"], 372.0)


# --- uncertainty kinds, signs and double counting ------------------------------------

def test_uncertainty_of_another_fuel_is_not_transferred(result, record):
    assert "JP8" in record["demand_terms"]["mass_rate"]["uncertainty_note"]
    assert result["mass_rate_uncertainty_fraction"] is None
    kinds = record["uncertainty_kinds"]
    assert set(kinds) == {"experimental", "between_runs", "model_error", "assumption_interval", "sensitivity",
                          "acceptance_criterion", "combinable", "total_uncertainty_of_B"}
    assert "gauge exploration of 30 percent" in kinds["assumption_interval"]
    assert not any("30" in item for item in kinds["experimental"])
    assert kinds["acceptance_criterion"] == ["20 percent contrast threshold"]
    exploration = record["frontier_terms"]["gauge_plane_to_surface"]
    assert "not an uncertainty of B" in exploration["laboratory_exploration_kind"]


def test_signs_and_single_counting_of_frontier_terms(record):
    terms = copy.deepcopy(record["frontier_terms"])
    base = budget.conditional_net_range(100.0, 1.0, terms)
    assert base[0] < base[1] < 100.0
    terms["pan_bottom_and_ground_loss"]["range_kw_m2"] = [0.2, 4.0]
    assert budget.conditional_net_range(100.0, 1.0, terms)[0] == pytest.approx(base[0] - 2.0)
    assert budget.conditional_net_range(100.0, 1.0, terms)[1] == pytest.approx(base[1])
    terms = copy.deepcopy(record["frontier_terms"])
    terms["surface_reflection"]["range_fraction_of_reading"] = [0.02, 0.20]
    assert budget.conditional_net_range(100.0, 1.0, terms)[0] == pytest.approx(base[0] - 10.0)
    wide = budget.conditional_net_range(100.0, 1.0, record["frontier_terms"], 0.30)
    assert wide[0] < base[0] and wide[1] > base[1]
    # The emission is subtracted once: the bound is the black-body value, not twice it.
    assert base[0] == pytest.approx(100.0 * 0.90 - budget.blackbody_kw_m2(371.0) - 2.0, abs=1e-4)
    for bad in [0.0, -5.0, float("nan"), True, None]:
        with pytest.raises(ValueError):
            budget.blackbody_kw_m2(bad)


# --- provenance, corrections and alternatives ----------------------------------------

def test_record_sources_and_corrections_are_bound(record):
    digest = hashlib.sha256(json.dumps(record, sort_keys=True, allow_nan=False).encode("utf-8")).hexdigest()
    assert digest == budget.REVISION_SHA256
    assert record["revises"]["record_sha256"] == budget.REVIEW_SHA256
    for name, size in [("sandia_2011", 10652080), ("luketa_2010", 973671)]:
        raw = (ROOT / record["sources"][name]["path"]).read_bytes()
        assert len(raw) == size and hashlib.sha256(raw).hexdigest() == record["sources"][name]["sha256_raw"]
    assert "further dissemination unlimited" in record["sources"]["luketa_2010"]["rights"]
    assert record["sources"]["spectra_2009"]["obtained"] is False
    for name in ["spectra_2009", "beji_2021"]:
        assert record["sources"][name]["archived"] is False and "path" not in record["sources"][name]
    assert record["search"]["raw_data"]["found"] is False
    assert "does not show the data do not exist" in record["search"]["raw_data"]["note"]
    assert "No author was contacted" in record["search"]["request_not_sent"]
    items = [item["item"] for item in record["corrections_to_2026_10_06"]]
    assert items == ["liquid inventory", "vapour superheat", "reflection range", "gauge height",
                     "strict criterion", "loose criterion"]
    assert all({"was", "is", "locator", "effect"} <= set(item) for item in record["corrections_to_2026_10_06"])


@pytest.mark.parametrize("path, value", [
    (("frontier_terms", "pan_bottom_and_ground_loss", "range_kw_m2"), [0.0, 0.0]),
    (("frontier_terms", "pan_bottom_and_ground_loss", "is_a_measured_bound"), True),
    (("frontier_terms", "surface_reflection", "upper_end_is_a_bound"), True),
    (("frontier_terms", "gauge_plane_to_surface", "laboratory_exploration_fraction"), 0.03),
    (("demand_terms", "mass_rate", "uncertainty_fraction"), 0.019),
    (("demand_terms", "liquid_storage_growth", "fuel_depth_m"), [0.019, 0.019]),
    (("laboratory_balance_for_heptane", "calculated_mass_flux_eq17_kg_m2_s"), 0.061),
    (("uncertainty_kinds", "total_uncertainty_of_B"), 0.20),
    (("sources", "luketa_2010", "sha256_raw"), "0" * 64),
    (("sources", "spectra_2009", "obtained"), True),
    (("revises", "withdrawn_verdict"), "none"),
    (("review", "predictive_thermal_input_approval"), True),
    (("review", "co_fed_approval"), True),
])
def test_altered_revision_record_is_rejected(record, path, value):
    changed = copy.deepcopy(record)
    holder = changed
    for key in path[:-1]:
        holder = holder[key]
    assert holder[path[-1]] != value
    holder[path[-1]] = value
    with pytest.raises(ValueError, match="unreviewed evidence"):
        budget.review(changed)


def test_promoted_approval_or_wrong_target_is_rejected_beyond_the_hash(record, monkeypatch):
    changed = copy.deepcopy(record)
    changed["review"]["predictive_emission_approval"] = True
    with pytest.raises(ValueError, match="approval was promoted"):
        budget.review(_repinned(monkeypatch, changed))
    changed = copy.deepcopy(record)
    changed["revises"]["record_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="does not point at the record"):
        budget.review(_repinned(monkeypatch, changed))
    changed = copy.deepcopy(record)
    changed["frontier_terms"]["surface_emission"]["bound_kw_m2"] = [0.0, 0.5]
    with pytest.raises(ValueError, match="black-body value"):
        budget.review(_repinned(monkeypatch, changed))
    changed = copy.deepcopy(record)
    changed["sources"]["luketa_2010"]["sha256_raw"] = "0" * 64
    with pytest.raises(ValueError, match="artifact content mismatch"):
        budget.review(_repinned(monkeypatch, changed))


def test_alternative_is_classified_as_what_it_is(record):
    cone = record["alternatives"]["beji_2021_cacc"]
    assert cone["kind"] == "controlled evaporation without flame, transient"
    assert "does not yet identify the net heat at the surface" in cone["assessment"]
    assert "39 to 46 percent" in cone["limits"]
    assert len(record["alternatives"]) <= 3
    assert "not located" in record["alternatives"]["sandia_one_foot_tests"]["assessment"]


def test_revision_is_offline():
    source = Path(budget.__file__).read_text(encoding="utf-8")
    for forbidden in ["subprocess", "sim/fire", "res://", "write_text", "write_bytes", "requests", "urllib"]:
        assert forbidden not in source
    assert "WITHDRAWN" in source and "kept as history" in source
