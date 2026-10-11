"""Object-scale tests as prescribed sources: provenance, reproduction and the confusions refused.

Offline. The oracles are closed forms, values printed on the archived pages or synthetic
series; none depends on a fitted number. Two tests need the local copy of series that are
not redistributed and skip, with that reason, when it is absent.
"""

from __future__ import annotations

import copy
import csv
import hashlib
import json
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_object_fire_source as src
from scripts.simulation import run_g3_object_source_control_mutations as variants

ROOT = Path(__file__).resolve().parents[1]
RECORD = src.load_record()
SAVED = json.loads(src.SAVED.read_text(encoding="utf-8"))
AGGREGATES = json.loads(src.LOCAL_AGGREGATES.read_text(encoding="utf-8"))
NIST_RUNS = ("Test016", "Test021", "Test030", "Test036", "Test041")
CANDIDATES = {item["id"]: item for item in RECORD["candidates"]}
LOCAL = pytest.mark.skipif(
    not src.local_files_present(RECORD),
    reason="needs the local FSRI series, which are not redistributed (see the record for link and hashes)")


def _write_csv(folder: Path, rows: list[dict], header: tuple[str, ...] = tuple(src.FCD_COLUMNS)) -> dict:
    path = folder / "synthetic.csv"
    with path.open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(header)
        for row in rows:
            writer.writerow([row.get(name, 0) for name in src.FCD_COLUMNS])
    return {"run_id": "Synthetic", "version": "FCD_2026", "owner_id": "synthetic_item",
            "csv": {"path": "synthetic.csv", "sha256": hashlib.sha256(path.read_bytes()).hexdigest()},
            "events": {"ignition_s": 0, "fire_out_s": rows[-1]["Time (s)"]}}


def _synthetic(tmp_path, monkeypatch, hrr: list[float], first: int = -2) -> tuple[dict, dict]:
    monkeypatch.setattr(src, "ROOT", tmp_path)
    rows = [{"Time (s)": first + i, "Heat Release Rate (kW)": q, "Exhaust Mass Flow Rate (kg/s)": 2.0,
             "Oxygen (Vol Fr)": 0.2095, "CO2 (Vol Fr)": 0.0004, "CO (Vol Fr)": 0.0} for i, q in enumerate(hrr)]
    test = _write_csv(tmp_path, rows)
    return test, src.load_fcd_series(test)


# ---------------------------------------------------------------- source, rights and record

def test_sources_are_pinned_and_rights_are_recorded_per_source() -> None:
    nist, fsri = RECORD["sources"]["nist_fcd"], RECORD["sources"]["fsri_mapd"]
    for item in nist["files"]:
        assert src.sha256_file(ROOT / item["path"]) == item["sha256"], item["path"]
    assert nist["redistribution"]["verified"] is True
    assert "nist.gov/open/license" in nist["redistribution"]["basis"]
    assert fsri["redistribution"]["verified"] is False
    assert len(fsri["commit"]) == 40 and len(fsri["local_files"]) == 9
    assert all(len(item["sha256"]) == 64 for item in fsri["local_files"])


def test_no_series_without_verified_rights_is_versioned() -> None:
    tracked = [p for p in (ROOT / "docs").rglob("Overstuffed_Sofa*") if p.is_file()]
    assert tracked == []
    assert set(AGGREGATES["runs"]["R1"]) & {"times", "Heat Release Rate", "Load Cell", "samples"} == set()
    assert "not raw data" in AGGREGATES["nature"]


def test_at_most_three_candidates_of_three_different_kinds() -> None:
    assert len(RECORD["candidates"]) == 3
    assert len({item["kind"] for item in RECORD["candidates"]}) == 3
    for item in RECORD["candidates"]:
        assert item["source_run"] not in item["reserved_runs"]
        assert item["approved_chemistry_profiles"] == []
        assert item["source_run_chosen_by"]


@pytest.mark.parametrize("test_id", NIST_RUNS)
def test_the_record_repeats_the_archived_page_and_not_a_transcription(test_id: str) -> None:
    test, page = RECORD["tests"][test_id], src.fcd_page(test_id)
    assert page["test_id"] == test_id
    assert page["report_process_script"] == test["page"]["report_process_script"] == "NFRL_Report_8.7.1"
    assert test["specimen"]["fcd_description"] == page["info"]["description"]
    assert test["mass"]["lost_kg"] == src.as_number(src.page_value(page, "results", "Net Specimen Mass"))
    assert test["mass"]["initial_kg"] == src.as_number(src.page_value(page, "inputs", "Initial Specimen Mass"))
    assert test["events"]["ignition_s"] == src.event_time_s(page, "Ignition")
    assert test["events"]["fire_out_s"] == src.event_time_s(page, "Fire Out", last=True)
    # initial and final masses are printed to 0.01 kg, the mass lost to 0.001 kg
    assert test["mass"]["lost_kg"] == pytest.approx(test["mass"]["initial_kg"] - test["mass"]["final_kg"], abs=0.011)


def test_conflicts_of_the_sources_are_recorded_and_not_resolved() -> None:
    chair = RECORD["tests"]["Test016"]
    assert "hard-plastic" in chair["specimen"]["tn2303_description"]
    assert "particle board" in chair["specimen"]["fcd_description"]
    assert "Not resolved" in chair["specimen"]["conflict"]
    assert CANDIDATES["C1"]["composition"]["class"] == "unknown"
    assert RECORD["tests"]["Test041"]["mass"]["initial_conflict_kg"] == pytest.approx(0.2)
    second = RECORD["tests"]["Test021"]["igniter"]
    assert second["power_W"] * second["duration_s"] / 1000.0 == pytest.approx(15.36)
    assert second["energy_kJ"] == 14.4 and "Not resolved" in second["notes"]


@pytest.mark.parametrize("test_id", ("Test016", "Test030", "Test036", "Test041"))
def test_printed_igniter_energy_is_power_times_duration(test_id: str) -> None:
    igniter = RECORD["tests"][test_id]["igniter"]
    energy = igniter["power_W"] * igniter["duration_s"] / 1000.0
    assert energy == pytest.approx(igniter["energy_kJ"], rel=igniter["energy_uc_percent"] / 100.0)


# ---------------------------------------------------------------- absent, unknown, below detection, zero

@pytest.mark.parametrize("printed, state", [
    ("below detection limit", "below_detection"), ("Not measured", "absent"), ("-", "absent"),
    ("NaN", "absent"), ("0", "zero"), ("", "unknown"), (None, "unknown"), ("2,994", "value"), ("n/a", "unknown")])
def test_a_printed_cell_keeps_its_state(printed, state: str) -> None:
    assert src.reading(printed)["state"] == state
    assert state in src.STATES


def test_only_a_value_or_a_measured_zero_is_a_number() -> None:
    assert src.as_number(src.reading("2,994")) == 2994.0
    assert src.as_number(src.reading("0")) == 0.0
    for printed in ("below detection limit", "Not measured", "", None):
        with pytest.raises(src.Refusal, match="cannot stand for zero"):
            src.as_number(src.reading(printed))


def test_the_archived_pages_hold_the_four_states() -> None:
    table, chair, repeat = src.fcd_page("Test018"), src.fcd_page("Test016"), src.fcd_page("Test021")
    assert src.page_value(table, "results", "CO Yield")["state"] == "below_detection"
    with pytest.raises(src.Refusal, match="below_detection"):
        src.as_number(src.page_value(table, "results", "CO Yield"), "CO yield")
    assert src.page_value(chair, "results", "Heat Release Quality Confirmation")["state"] == "absent"
    assert src.page_value(repeat, "results", "Gas Burner Total Heat Released")["state"] == "zero"
    assert src.page_value(chair, "results", "CO Yield")["state"] == "value"
    assert src.page_value(chair, "results", "Gas Burner Total Heat Released")["uc"] is None


def test_a_missing_sample_is_refused_and_not_integrated_as_zero() -> None:
    series = src.load_fcd_series(RECORD["tests"]["Test021"])
    last = series["times"][-1]
    assert series["absent"]["Heat Release Rate (kW)"] == [last]
    with pytest.raises(src.Refusal, match="absent is not zero"):
        src.integral_MJ(series, 0, last)
    assert src.integral_MJ(series, 0, RECORD["tests"]["Test021"]["events"]["fire_out_s"]) == pytest.approx(96.0643, abs=1e-3)


def test_a_comparison_without_published_uncertainty_is_refused() -> None:
    printed = src.page_value(src.fcd_page("Test016"), "results", "Gas Burner Total Heat Released")
    with pytest.raises(src.Refusal, match="no published uncertainty"):
        src.within(3.0, printed)


# ---------------------------------------------------------------- units, bytes and support

def test_units_are_converted_only_when_declared() -> None:
    assert src.convert(19.05, "min", "time") == pytest.approx(1143.0)
    assert src.convert(128, "W", "power") == pytest.approx(0.128)
    assert src.convert(9677, "g", "mass") == pytest.approx(9.677)
    assert src.convert(9.6, "kJ", "energy") == pytest.approx(0.0096)
    for value, unit, kind in ((1.0, "h", "time"), (1.0, "BTU/s", "power"), (1.0, "lb", "mass"), (1.0, "kW", "energy")):
        with pytest.raises(src.Refusal, match="not a declared"):
            src.convert(value, unit, kind)


def test_a_file_with_another_unit_in_its_header_is_refused(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(src, "ROOT", tmp_path)
    header = tuple(name.replace("Heat Release Rate (kW)", "Heat Release Rate (MW)") for name in src.FCD_COLUMNS)
    test = _write_csv(tmp_path, [{"Time (s)": t} for t in range(-2, 4)], header)
    with pytest.raises(src.Refusal, match="columns or units changed"):
        src.load_fcd_series(test)


def test_changed_bytes_and_a_broken_time_axis_are_refused(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(src, "ROOT", tmp_path)
    test = _write_csv(tmp_path, [{"Time (s)": t} for t in (-2, -1, 0, 1, 3, 4)])
    with pytest.raises(src.Refusal, match="not contiguous"):
        src.load_fcd_series(test)
    test = _write_csv(tmp_path, [{"Time (s)": t} for t in range(-2, 4)])
    test["csv"]["sha256"] = "0" * 64
    with pytest.raises(src.Refusal, match="bytes changed"):
        src.load_fcd_series(test)


def test_a_window_outside_the_support_is_refused(tmp_path, monkeypatch) -> None:
    _test, series = _synthetic(tmp_path, monkeypatch, [0.0, 0.0, 1.0, 2.0, 3.0])
    assert src.integral_MJ(series, 0, 2) == pytest.approx(0.006)
    for start, end in ((-5, 2), (0, 9), (2, 1)):
        with pytest.raises(src.Refusal, match="outside the support"):
            src.integral_MJ(series, start, end)


# ---------------------------------------------------------------- runs and versions

def test_quantities_of_two_runs_or_two_versions_are_not_combined() -> None:
    energy = {"MJ": 115.1, "uc_MJ": 6.4, "run_id": "Test016", "version": "FCD_2026"}
    mass = {"kg": 3.241, "uc_kg": 0.028, "run_id": "Test016", "version": "FCD_2026"}
    heat = src.effective_heat(energy, mass)
    assert heat["MJ_kg"] == pytest.approx(35.51, abs=0.01) and heat["class"] == "calculated"
    assert heat["uc_MJ_kg"] == pytest.approx(35.51 * ((6.4 / 115.1) ** 2 + (0.028 / 3.241) ** 2) ** 0.5, abs=0.01)
    with pytest.raises(src.Refusal, match="run_id"):
        src.effective_heat(energy, dict(mass, run_id="Test021"))
    with pytest.raises(src.Refusal, match="version"):
        src.effective_heat(energy, dict(mass, version="TN2303_2025"))
    with pytest.raises(src.Refusal, match="version"):
        src.effective_heat(energy, {key: value for key, value in mass.items() if key != "version"})


def test_a_table_is_not_built_from_the_series_of_another_run() -> None:
    series = src.load_fcd_series(RECORD["tests"]["Test021"])
    with pytest.raises(src.Refusal, match="run_id"):
        src.prescribed_table(RECORD["tests"]["Test016"], series, "nist_tn2303_stackable_chair_a_as_tested")


# ---------------------------------------------------------------- the prescribed table

def test_the_table_returns_its_samples_and_refuses_outside_its_support(tmp_path, monkeypatch) -> None:
    test, series = _synthetic(tmp_path, monkeypatch, [0.0, 0.0, 0.0, 10.0, 30.0, 20.0, 0.0])
    table = src.prescribed_table(test, series, "synthetic_item")
    assert table["samples"] == [[0.0, 0.0], [1.0, 10.0], [2.0, 30.0], [3.0, 20.0], [4.0, 0.0]]
    assert src.evaluate(table, 2.0) == 30.0
    assert src.evaluate(table, 1.25) == pytest.approx(15.0)
    assert src.evaluate(table, 4.0) == 0.0
    for time_s in (-0.5, 4.5, 1.0e6):
        with pytest.raises(src.Refusal, match="outside the support"):
            src.evaluate(table, time_s)


def test_the_energy_of_the_table_is_the_closed_form(tmp_path, monkeypatch) -> None:
    test, series = _synthetic(tmp_path, monkeypatch, [0.0, 0.0, 0.0, 10.0, 30.0, 20.0, 0.0])
    table = src.prescribed_table(test, series, "synthetic_item")
    assert src.table_energy_MJ(table) == pytest.approx((5.0 + 20.0 + 25.0 + 10.0) / 1000.0)
    assert src.table_energy_MJ(table, 1.5, 2.5) == pytest.approx((0.5 * (20.0 + 30.0) * 0.5 + 0.5 * (30.0 + 25.0) * 0.5) / 1000.0)
    with pytest.raises(src.Refusal, match="outside the support"):
        src.table_energy_MJ(table, 0.0, 5.0)


def test_negative_samples_are_clipped_and_the_bias_is_reported(tmp_path, monkeypatch) -> None:
    test, series = _synthetic(tmp_path, monkeypatch, [0.0, 0.0, -4.0, 10.0, -6.0, 20.0, 0.0])
    table = src.prescribed_table(test, series, "synthetic_item")
    assert min(q for _t, q in table["samples"]) == 0.0
    assert table["signed_sum_MJ"] == pytest.approx(0.020)
    assert table["clip_bias_MJ"] == pytest.approx(0.010)
    assert table["negative_samples_count"] == 2


def test_the_table_carries_heat_release_only() -> None:
    test = RECORD["tests"]["Test016"]
    table = src.prescribed_table(test, src.load_fcd_series(test), test["owner_id"])
    assert table["quantity"] == "measured_calorimetric_hrr" and table["unit"] == "kW"
    assert table["outside_support"] == "reject" and table["interpolation"] == "piecewise_linear"
    forbidden = {"mass", "mass_loss_rate", "initial_mass_kg", "composition", "yields", "co_yield", "heat_of_combustion"}
    assert forbidden & set(table) == set()
    assert table["fingerprint"] == SAVED["selected"]["table_fingerprint"]
    assert table["samples"][0][0] == 0.0 and table["samples"][-1][0] == float(test["events"]["fire_out_s"])


def test_the_fingerprint_follows_every_sample(tmp_path, monkeypatch) -> None:
    test, series = _synthetic(tmp_path, monkeypatch, [0.0, 0.0, 0.0, 10.0, 30.0])
    first = src.prescribed_table(test, series, "synthetic_item")["fingerprint"]
    series["columns"]["Heat Release Rate (kW)"][3] = 10.01
    assert src.prescribed_table(test, series, "synthetic_item")["fingerprint"] != first
    assert src.prescribed_table(test, series, "another_item")["fingerprint"] != first


@pytest.mark.parametrize("test_id", NIST_RUNS)
def test_each_rebuilt_curve_returns_the_peak_time_and_total_of_its_page(test_id: str) -> None:
    rebuilt = SAVED["runs"][test_id]["reproduction"]
    assert rebuilt["peak_inside_uc"] and rebuilt["time_to_peak_inside_uc"] and rebuilt["energy_inside_uc"]
    assert abs(rebuilt["peak_kW"] - rebuilt["peak_printed_kW"]) <= 0.5
    assert abs(rebuilt["signed_sum_MJ"] - rebuilt["thr_printed_MJ"]) <= 0.5
    assert "not validation" in rebuilt["what_it_is"]


def test_the_selected_run_as_published() -> None:
    run = SAVED["runs"]["Test016"]
    assert run["reproduction"]["peak_kW"] == pytest.approx(621.46)
    assert run["reproduction"]["time_to_peak_s"] == 1143.0
    assert run["reproduction"]["signed_sum_MJ"] == pytest.approx(115.0928, abs=1e-3)
    assert run["reproduction"]["clip_bias_MJ"] == pytest.approx(0.0013, abs=2e-4)
    assert run["absent_samples"] == {}
    assert run["igniter_over_thr"] < 1.0e-4
    assert run["igniter_power_over_pre_ignition_noise"] < 1.0
    assert run["energy_timeline_s"]["0.1"] == 1040.0 and run["energy_timeline_s"]["0.5"] == 1183.0


def test_the_clipping_bias_is_small_but_not_the_same_under_both_hoods() -> None:
    small, large = SAVED["runs"]["Test016"]["reproduction"], SAVED["runs"]["Test021"]["reproduction"]
    assert small["clip_bias_over_uc"] < 0.001
    assert 0.1 < large["clip_bias_over_uc"] < 0.2
    assert large["clip_bias_MJ"] == pytest.approx(0.79, abs=0.01)


# ---------------------------------------------------------------- confusions refused

def test_hrr_over_a_heat_of_combustion_is_never_a_measured_mass_loss_rate() -> None:
    rate = src.mass_rate_from_hrr(621.0, 35.5)
    assert rate["class"] == "calculated" and rate["kg_s"] == pytest.approx(621.0 / 35500.0)
    assert "heat release rate" in rate["depends_on"]
    with pytest.raises(src.Refusal, match="cannot be presented as measured"):
        src.present_as(rate, "measured")
    with pytest.raises(src.Refusal, match="not measured"):
        src.require_class(rate, ("measured",), "mass loss rate")
    with pytest.raises(src.Refusal, match="positive"):
        src.mass_rate_from_hrr(621.0, 0.0)


def test_an_integrated_yield_is_not_an_instantaneous_law() -> None:
    printed = {"value": 0.0339, "basis": "ignition to fire out, exhaust duct"}
    with pytest.raises(src.Refusal, match="cannot be evaluated at"):
        src.instantaneous_yield(printed, 1143.0)


def test_the_test_of_a_set_is_not_assigned_to_one_of_its_items() -> None:
    sofa = CANDIDATES["C2"]
    assert src.assign_source(sofa, sofa["owner_id"]) == "Test030"
    with pytest.raises(src.Refusal, match="two A pillows"):
        src.assign_source(sofa, "nist_tn2303_sofa_b_chaise_alone")
    with pytest.raises(src.Refusal, match="another object"):
        src.assign_source(CANDIDATES["C1"], "generic_dining_chair")


@pytest.mark.parametrize("candidate", ("C1", "C2", "C3"))
def test_heptane_chemistry_is_not_used_for_furniture(candidate: str) -> None:
    with pytest.raises(src.Refusal, match="not an approved chemistry"):
        src.chemistry_for(CANDIDATES[candidate], {"material_id": "n_heptane_reference"})


def test_a_reserved_run_is_not_used_to_fit() -> None:
    chair = CANDIDATES["C1"]
    assert src.use_for_fit(chair, "Test016") == "Test016"
    with pytest.raises(src.Refusal, match="reserved for contrast"):
        src.use_for_fit(chair, "Test021")
    with pytest.raises(src.Refusal, match="not a run of"):
        src.use_for_fit(chair, "Test030")


def test_the_input_curve_cannot_also_prove_prediction() -> None:
    chair = CANDIDATES["C1"]
    assert src.external_validation(chair, "Test016", "Test021", fitted_on=["Test016"]) == "Test021"
    with pytest.raises(src.Refusal, match="reproduction, not prediction"):
        src.external_validation(chair, "Test016", "Test016", fitted_on=[])
    with pytest.raises(src.Refusal, match="used to fit"):
        src.external_validation(chair, "Test016", "Test021", fitted_on=["Test016", "Test021"])
    with pytest.raises(src.Refusal, match="not a reserved run"):
        src.external_validation(chair, "Test016", "Test030", fitted_on=[])


# ---------------------------------------------------------------- what the data show

def test_two_runs_of_the_same_chair_differ_beyond_their_uncertainty() -> None:
    contrast = SAVED["candidates"]["C1"]["contrast_with_reserved_runs"]["Test021"]
    assert contrast["peak_kW"]["beyond_combined_uc"] and contrast["thr_MJ"]["beyond_combined_uc"]
    assert contrast["peak_kW"]["relative"] == pytest.approx(0.111, abs=0.001)
    assert contrast["thr_MJ"]["relative"] == pytest.approx(-0.165, abs=0.001)
    assert contrast["time_to_peak_s"]["difference"] == 589.0
    assert contrast["same_curve_within_uncertainty"] is False
    assert "nothing was aligned, scaled or fitted" in contrast["what_it_is"]


def test_the_sofa_set_repeats_its_total_and_not_its_curve() -> None:
    contrasts = SAVED["candidates"]["C2"]["contrast_with_reserved_runs"]
    for run in ("Test036", "Test041"):
        assert contrasts[run]["thr_MJ"]["beyond_combined_uc"] is False
        assert contrasts[run]["peak_kW"]["beyond_combined_uc"] is True
    assert contrasts["Test036"]["peak_kW"]["relative"] == pytest.approx(0.721, abs=0.001)
    assert SAVED["runs"]["Test030"]["energy_after_fire_out_MJ"] == pytest.approx(12.15, abs=0.01)


def test_exhaust_totals_are_rebuilt_inside_uncertainty_with_one_declared_exception() -> None:
    for test_id in NIST_RUNS:
        for name, item in SAVED["runs"][test_id]["species"].items():
            expected = not (test_id == "Test021" and name == "co")
            assert item["inside_uc"] is expected, (test_id, name)
            assert item["basis"] == "whole test, exhaust duct"
    assert SAVED["runs"]["Test021"]["species"]["co"]["yield_kg_kg"] == pytest.approx(0.0310, abs=1e-4)


def test_the_version_change_touches_the_sofa_totals_and_not_the_chair() -> None:
    versions = SAVED["version_consistency"]
    assert [versions[run]["co_yield_inside_rounding"] for run in NIST_RUNS] == [True, True, False, False, True]
    assert all(versions[run]["mass_unchanged"] for run in NIST_RUNS)
    assert all(versions[run]["declared_version"] == "FCD_2026" for run in NIST_RUNS)
    assert "change_unexplained" in SAVED["candidates"]["C2"]["decisions"]["species_emission"]
    assert SAVED["candidates"]["C2"]["decisions"]["prescribed_hrr"].startswith("GO_")


def test_carbon_recovered_in_the_exhaust_is_a_calculation_about_the_mass_lost() -> None:
    assert SAVED["runs"]["Test016"]["carbon_in_co_and_co2_per_kg_lost"] == pytest.approx(0.711, abs=0.001)
    assert SAVED["runs"]["Test030"]["carbon_in_co_and_co2_per_kg_lost"] == pytest.approx(0.480, abs=0.001)
    assert CANDIDATES["C1"]["composition"]["class"] == "unknown"


def test_the_burner_channel_is_recorded_as_unexplained() -> None:
    run = SAVED["runs"]["Test016"]
    assert run["burner_channel_before_ignition_kW"] == pytest.approx(0.711, abs=0.001)
    assert run["pre_ignition_hrr_kW"]["mean"] == pytest.approx(0.121, abs=0.001)
    assert any("burner channel" in item for item in RECORD["unknown_in_every_nist_run"])


def test_effective_heat_is_not_one_number_during_a_run() -> None:
    for name, run in AGGREGATES["runs"].items():
        early = run["windows"]["0.1_to_0.5_of_energy"]["MJ_kg"]
        late = run["windows"]["0.5_to_0.9_of_energy"]["MJ_kg"]
        assert early > late and (early - late) / late > 0.05, name
        assert run["hrr_over_heat_against_load_cell"]["largest_gap_over_mass_lost"] > 0.03, name
    assert AGGREGATES["across_runs"]["energy_MJ"]["relative_spread"] == pytest.approx(0.096, abs=0.001)
    assert AGGREGATES["across_runs"]["mass_lost_kg"]["relative_spread"] < 0.01


def test_mass_rebuilt_from_hrr_matches_the_load_only_when_the_heat_is_constant() -> None:
    times = list(range(-10, 401))
    rate = [0.1 if 0 <= t < 300 else 0.0 for t in times]
    def run(heat_of) -> dict:
        load, mass = [], 50.0
        for r in rate:
            load.append(mass)
            mass -= r
        hrr = [r * heat_of(t) * 1000.0 for t, r in zip(times, rate)]
        return src.analyse_fsri_run({"run_id": "synthetic", "times": times, "Heat Release Rate": hrr, "Load Cell": load})
    constant = run(lambda t: 20.0)
    falling = run(lambda t: 30.0 if t < 150 else 10.0)
    assert abs(constant["hrr_over_heat_against_load_cell"]["largest_gap_kg"]) < 0.3
    assert constant["windows"]["0.1_to_0.5_of_energy"]["MJ_kg"] == pytest.approx(20.0, rel=0.03)
    assert abs(falling["hrr_over_heat_against_load_cell"]["largest_gap_kg"]) > 5.0
    assert falling["windows"]["0.1_to_0.5_of_energy"]["MJ_kg"] > falling["windows"]["0.5_to_0.9_of_energy"]["MJ_kg"]


# ---------------------------------------------------------------- decisions

BASE_FACTS = {
    "hrr_numeric_same_run": True, "redistribution_verified": True, "igniter_documented": True,
    "uncertainty_published": True, "hrr_reproduces_published_totals": True, "inseparable_components": False,
    "mass_series_numeric_same_run": False, "mass_series_in_figure": True, "mass_total_published": True,
    "species_series_numeric_same_run": True, "species_totals_reproduced": True, "species_version_consistent": True,
    "repeats_differ_beyond_uncertainty": True, "reserved_run_available": True,
}


def test_a_go_in_one_observable_approves_no_other() -> None:
    base = src.decide(BASE_FACTS)
    assert base["prescribed_hrr"] == "GO_one_run_open_air"
    assert base["prescribed_mass_loss"].startswith("NO_GO")
    assert base["temporal_species_yield"].startswith("NO_GO")
    assert base["extrapolation"].startswith("NO_GO")
    assert base["energy_and_effective_heat"] == "GO_partial_whole_test_integrals_only"
    with_mass = src.decide(dict(BASE_FACTS, mass_series_numeric_same_run=True))
    assert with_mass["prescribed_hrr"] == base["prescribed_hrr"]
    assert with_mass["species_emission"] == base["species_emission"]
    assert with_mass["extrapolation"] == base["extrapolation"]
    no_species = src.decide(dict(BASE_FACTS, species_series_numeric_same_run=False))
    assert no_species["species_emission"] == "NO_GO_no_species_measured"
    assert no_species["prescribed_hrr"] == base["prescribed_hrr"]


@pytest.mark.parametrize("change, key, expected", [
    ({"redistribution_verified": False}, "prescribed_hrr", "GO_partial_local_only_igniter_and_uncertainty_not_documented"),
    ({"igniter_documented": False}, "prescribed_hrr", "GO_partial_local_only_igniter_and_uncertainty_not_documented"),
    ({"hrr_reproduces_published_totals": False}, "prescribed_hrr", "NO_GO_series_does_not_return_published_totals"),
    ({"inseparable_components": True}, "prescribed_hrr", "GO_one_run_open_air_as_the_whole_set"),
    ({"mass_series_in_figure": False}, "prescribed_mass_loss", "NO_GO_not_measured_in_time_total_is_gravimetric"),
    ({"species_totals_reproduced": False}, "species_emission", "NO_GO_exhaust_totals_not_reproduced"),
    ({"species_version_consistent": False}, "species_emission",
     "GO_partial_exhaust_totals_declared_version_only_change_unexplained"),
    ({"repeats_differ_beyond_uncertainty": False}, "extrapolation", "NO_GO_one_regime_one_item"),
    ({"reserved_run_available": False}, "external_validation", "none_reproduction_only"),
])
def test_each_fact_moves_only_its_own_decision(change: dict, key: str, expected: str) -> None:
    base, moved = src.decide(BASE_FACTS), src.decide(dict(BASE_FACTS, **change))
    assert moved[key] == expected
    assert {name for name in base if base[name] != moved[name]} == {key}


def test_without_a_numeric_series_there_is_neither_a_curve_nor_an_energy_check() -> None:
    moved = src.decide(dict(BASE_FACTS, hrr_numeric_same_run=False))
    assert moved["prescribed_hrr"] == "NO_GO_no_numeric_series"
    assert moved["energy_and_effective_heat"] == "NO_GO"


def test_totals_alone_never_approve_a_yield_in_time() -> None:
    assert src.decide(BASE_FACTS)["temporal_species_yield"].startswith("NO_GO")
    only_mass = src.decide(dict(BASE_FACTS, mass_series_numeric_same_run=True, species_series_numeric_same_run=False))
    assert only_mass["temporal_species_yield"].startswith("NO_GO")
    for candidate in SAVED["candidates"].values():
        assert set(src.OBSERVABLES) <= set(candidate["decisions"])
        assert candidate["decisions"]["temporal_species_yield"].startswith("NO_GO")
        assert candidate["decisions"]["extrapolation"].startswith("NO_GO")


def test_the_saved_decisions() -> None:
    assert SAVED["selected"]["candidate"] == "C1" and SAVED["selected"]["source_run"] == "Test016"
    assert SAVED["candidates"]["C1"]["decisions"] == {
        "prescribed_hrr": "GO_one_run_open_air",
        "prescribed_mass_loss": "NO_GO_figure_only_total_is_gravimetric",
        "energy_and_effective_heat": "GO_partial_whole_test_integrals_only",
        "species_emission": "GO_partial_exhaust_totals_of_CO_CO2_O2",
        "temporal_species_yield": "NO_GO_no_run_has_numeric_mass_and_species_in_time",
        "extrapolation": "NO_GO_repeat_runs_differ_beyond_uncertainty",
        "external_validation": "reserved_run_available_not_used",
    }
    assert SAVED["candidates"]["C3"]["decisions"]["prescribed_hrr"].startswith("GO_partial_local_only")
    assert SAVED["candidates"]["C3"]["decisions"]["species_emission"] == "NO_GO_no_species_measured"
    assert SAVED["standing"] == {"b_net": "NO_GO_closed_on_this_route", "co_fed": "OFF_NO_GO",
                                 "engine_change": "not_authorised_in_this_phase", "predictive_source": "NO_GO"}


def test_the_contract_leaves_everything_but_heat_release_unapproved() -> None:
    contract = RECORD["contract_for_the_next_engine_change"]
    assert contract["status"] == "proposed_not_implemented_not_authorised"
    assert contract["outside_support"].startswith("refused")
    assert set(contract["inputs"]) == {"measured", "calculated", "assumed", "unknown_and_left_null"}
    assert "mass loss rate" in contract["inputs"]["unknown_and_left_null"]
    assert "CO or FED" in contract["not_approved"]
    assert {"mass", "heat across the fuel boundary"} <= set(contract["not_checkable"])
    assert len(contract["why_not_the_existing_contracts"]) == 2


# ---------------------------------------------------------------- saved audit and local dependency

def test_the_saved_audit_is_the_audit_of_the_record() -> None:
    assert SAVED == json.loads(json.dumps(src._rounded(src.audit(copy.deepcopy(RECORD)))))
    assert SAVED["record_sha256"] == hashlib.sha256(src.INPUT.read_bytes()).hexdigest()


def test_without_the_local_copy_the_series_are_refused_by_name(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(src, "LOCAL_FSRI", tmp_path)
    assert src.local_files_present(RECORD) is False
    with pytest.raises(src.Refusal, match="not redistributed and is not present"):
        src.load_fsri_series("R1", RECORD)


def test_a_local_file_that_is_not_the_reviewed_one_is_refused(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(src, "LOCAL_FSRI", tmp_path)
    (tmp_path / "Overstuffed_Sofa_R1.csv").write_text("Time (s),Load Cell,Heat Release Rate,Total Heat Released\n0,1,0,0\n",
                                                      encoding="utf-8")
    with pytest.raises(src.Refusal, match="not the file that was reviewed"):
        src.load_fsri_series("R1", RECORD)


@LOCAL
def test_the_local_series_are_the_reviewed_files() -> None:
    for item in RECORD["sources"]["fsri_mapd"]["local_files"]:
        assert src.sha256_file(src.LOCAL_FSRI / item["filename"]) == item["sha256"], item["filename"]


@LOCAL
def test_the_published_aggregates_are_those_of_the_local_series() -> None:
    assert AGGREGATES == json.loads(json.dumps(src._rounded(src.local_aggregates(RECORD), 6)))


# ---------------------------------------------------------------- the auditor itself

def test_the_auditor_holds_no_engine_no_solver_and_no_fit() -> None:
    source = Path(src.__file__).read_text(encoding="utf-8")
    for word in ("scipy", "curve_fit", "minimize", "least_squares", "godot", "res://", "CombustionSystem"):
        assert word not in source.replace("no Godot", ""), word


def test_every_control_variant_names_one_rule_of_the_auditor() -> None:
    source = Path(src.__file__).read_text(encoding="utf-8")
    names = [name for name, _old, _new in variants.VARIANTS]
    assert len(names) == len(set(names)) >= 20
    for name, old, new in variants.VARIANTS:
        assert source.count(old) == 1, name
        assert old != new, name
