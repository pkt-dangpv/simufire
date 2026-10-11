"""Guardrails for the research-only NIST furniture summary, not engine yields."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

from scripts.simulation.audit_g3_nist_fcd_csv import audit
from scripts.simulation.reconstruct_g3_nist_fcd_co import reconstruct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/validation/G3_NIST_FCD_FURNITURE_SUMMARY_2026-09-27.json"
RECONCILIATION = ROOT / "docs/validation/G3_NIST_TN2303_FCD_RECONCILIATION_2026-09-28.json"


def _by_id() -> dict[str, dict]:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert data["status"] == "research_only_not_engine_calibration"
    assert data["report_process_script"] == "NFRL_Report_8.7.1"
    assert data["time_series"]["status"] == "four_csvs_imported_not_calibrated"
    tests = {item["id"]: item for item in data["tests"]}
    assert len(tests) == len(data["tests"]) == 4
    return tests


def test_four_raw_csvs_and_reconstructed_totals_are_pinned() -> None:
    tests = _by_id()
    for test_id, item in tests.items():
        csv_meta = item["csv"]
        raw = audit(test_id)
        assert csv_meta["status"] == "imported_raw"
        assert csv_meta["sha256"] == raw["sha256"]
        assert csv_meta["path"] == raw["source"]
        assert csv_meta["rows"] == raw["rows"]
        assert csv_meta["time_range_s"] == raw["time_range_s"]
        assert csv_meta["fire_out_sample_s"] == raw["fire_out_sample_s"]
        assert csv_meta["peak_hrr_kW"] == raw["peak_hrr_kW"]
        assert csv_meta["peak_hrr_time_s"] == raw["peak_hrr_time_s"]
        assert csv_meta["hrr_integral_ignition_to_fire_out_MJ"] == raw["hrr_integral_ignition_to_fire_out_MJ"]
        assert csv_meta["co_observable"] == "dry_exhaust_volume_fraction"
        assert len(raw["missing_cells"]) == (0 if test_id == "Test018" else 2)
        _, candidate = reconstruct(-60, test_id)
        _, sensitivity = reconstruct(-120, test_id)
        assert csv_meta["co_mass_candidate_total_kg"] == candidate["total_net_co_exhaust_kg"]
        assert csv_meta["co_mass_120s_background_sensitivity_total_kg"] == sensitivity["total_net_co_exhaust_kg"]
        assert candidate["instantaneous_co_yield_status"] == "not_derived"
        assert candidate["nfrl_report_8_7_1_ambient_window_status"] == "not_verified"
    assert tests["Test029"]["csv"]["co_mass_rate_status"] == "research_only_reconstruction_candidate"
    assert tests["Test030"]["csv"]["co_mass_rate_status"] == "research_only_reconstruction_candidate"
    assert tests["Test028"]["csv"]["co_mass_rate_status"] == "mixed_specimen_diagnostic_only"
    assert tests["Test018"]["csv"]["co_mass_rate_status"] == "below_detection_pilot_contaminated_not_calibratable"
    assert tests["Test029"]["csv"]["ambient_window_in_nfrl_report_8_7_1_verified"] is False
    assert tests["Test029"]["csv"]["specimen_mass_loss_rate_status"] == "not_in_csv"


def test_test029_co_exhaust_reconstruction_is_provisional_and_integral_closes() -> None:
    rows, candidate = reconstruct(-60)
    _, sensitivity = reconstruct(-120)
    assert len(rows) == candidate["samples"] == 2081
    assert rows[0]["time_s"] == 0
    assert rows[-1]["time_s"] == 2080
    assert math.isclose(candidate["ambient_co_vol_frac"], 3.8e-7, rel_tol=1e-12)
    assert math.isclose(candidate["total_net_co_exhaust_kg"], 1.389648162101458, abs_tol=1e-9)
    assert math.isclose(sensitivity["total_net_co_exhaust_kg"], 1.390204022256359, abs_tol=1e-9)
    assert candidate["peak_net_co_exhaust_rate_time_s"] == 373
    assert candidate["net_co_exhaust_kg_by_period"]["1200_2080_s"] > 0.7
    assert candidate["negative_rate_samples"] == 38
    # Published yield uncertainty is 0.00096 kg/kg at 95%; this comparison
    # tests plausibility, not identity with the unpublished processing script.
    published_co_kg = _by_id()["Test029"]["net_specimen_mass_lost_kg"] * 0.02671
    published_uncertainty_kg = 52.116 * 0.00096
    assert abs(candidate["total_net_co_exhaust_kg"] - published_co_kg) < published_uncertainty_kg
    assert candidate["instantaneous_co_yield_status"] == "not_derived"
    assert candidate["nfrl_report_8_7_1_ambient_window_status"] == "not_verified"


def test_other_exhaust_totals_match_their_own_summary_without_promoting_mixed_fuels() -> None:
    tests = _by_id()
    for test_id in ("Test030", "Test028"):
        item = tests[test_id]
        _, candidate = reconstruct(-60, test_id)
        published_kg = item["net_specimen_mass_lost_kg"] * item["yield_kg_per_kg"]["co"]
        uncertainty_kg = item["net_specimen_mass_lost_kg"] * item["co_yield_Uc_kg_per_kg"]
        assert abs(candidate["total_net_co_exhaust_kg"] - published_kg) < uncertainty_kg
    assert reconstruct(-60, "Test028")[1]["attribution"] == "carpet_plus_pillows_not_carpet_only"
    table = reconstruct(-60, "Test018")[1]
    assert table["attribution"] == "pilot_contaminated_below_detection_not_calibratable"
    assert tests["Test018"]["yield_kg_per_kg"]["co"] is None


def test_fcd_sofa_source_values_and_units_are_pinned() -> None:
    tests = _by_id()
    expected = {
        "Test029": (52.116, 811.0, 15.56, 0.02671, 0.00096),
        "Test030": (77.888, 1426.0, 18.3, 0.0306, 0.0011),
    }
    for test_id, (mass, heat, hoc, co_yield, uncertainty) in expected.items():
        item = tests[test_id]
        assert item["source_url"].endswith("/" + test_id.lower())
        assert item["net_specimen_mass_lost_kg"] == mass
        assert item["total_heat_released_MJ"] == heat
        assert item["effective_heat_of_combustion_MJ_per_kg"] == hoc
        assert item["yield_kg_per_kg"]["co"] == co_yield
        assert item["co_yield_Uc_kg_per_kg"] == uncertainty
        assert item["yield_kg_per_kg"]["hcn"] is None
        assert item["use"] == "open_air_whole_specimen_candidate_only"
        # The rounded NIST summary quantities need not multiply exactly.
        assert math.isclose(heat / mass, hoc, rel_tol=0.005)


def test_mixed_carpet_and_nonburning_table_cannot_be_calibrated_as_objects() -> None:
    tests = _by_id()
    carpet = tests["Test028"]
    assert carpet["attribution"] == "mixed_fuels_cannot_isolate_carpet"
    assert carpet["use"] == "whole_mixed_specimen_validation_only"
    assert carpet["yield_kg_per_kg"]["co"] == 0.01175
    assert carpet["net_specimen_mass_lost_kg"] == 3.313

    table = tests["Test018"]
    assert table["use"] == "not_calibratable_below_detection"
    assert table["net_specimen_mass_lost_kg"] is None
    assert table["effective_heat_of_combustion_MJ_per_kg"] is None
    assert all(value is None for value in table["yield_kg_per_kg"].values())
    assert table["gas_burner_total_heat_released_MJ"] == 1.0


def test_only_same_test_mass_and_yield_may_form_integrated_co_total() -> None:
    tests = _by_id()
    expected_kg = {"Test029": 1.39201836, "Test030": 2.3833728, "Test028": 0.03892775}
    for test_id, expected in expected_kg.items():
        item = tests[test_id]
        derived = item["net_specimen_mass_lost_kg"] * item["yield_kg_per_kg"]["co"]
        assert math.isclose(derived, expected, rel_tol=1e-12)
    assert tests["Test018"]["yield_kg_per_kg"]["co"] is None


def test_2025_report_is_kept_separate_from_2026_fcd_and_mlr_scope() -> None:
    report = json.loads(RECONCILIATION.read_text(encoding="utf-8"))
    assert report["status"] == "research_only_not_engine_calibration"
    assert report["transient_mass_loss_scope"].startswith("Tests 1-24 only")
    pdf = ROOT / report["source_pdf"]
    assert hashlib.sha256(pdf.read_bytes()).hexdigest() == report["source_sha256"]
    old = {record["test_id"]: record for record in report["records"]}
    current = _by_id()
    assert set(old) == set(current)
    for test_id in ("Test029", "Test030"):
        assert old[test_id]["mass_lost_kg"] == current[test_id]["net_specimen_mass_lost_kg"]
        assert old[test_id]["thr_MJ"] == current[test_id]["total_heat_released_MJ"]
        assert old[test_id]["co_yield_kg_per_kg"] > current[test_id]["yield_kg_per_kg"]["co"]
        assert old[test_id]["hcn_yield_kg_per_kg"] > 0
        assert current[test_id]["yield_kg_per_kg"]["hcn"] is None
    assert old["Test029"]["co_yield_kg_per_kg"] == 0.030
    assert old["Test030"]["co_yield_kg_per_kg"] == 0.033
    assert old["Test028"]["co_yield_Uc_kg_per_kg"] == 0.040  # As printed in TN 2303.
    assert old["Test028"]["attribution"] == "carpet_plus_two_pillows_not_carpet_only"
    assert old["Test018"]["mass_lost_kg"] == 0.042
    assert current["Test018"]["yield_kg_per_kg"]["co"] is None
