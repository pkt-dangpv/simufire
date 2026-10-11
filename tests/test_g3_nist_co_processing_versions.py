"""Pins the TN 2303 (2025) vs FCD 2026 CO comparison; no cause is promoted."""

from __future__ import annotations

import functools
import json
from pathlib import Path

from scripts.simulation.audit_g3_nist_fcd_csv import CASES
from scripts.simulation.compare_g3_nist_co_processing import (
    HYPOTHESES,
    archived_pages,
    evaluate,
    load_source,
)


ROOT = Path(__file__).resolve().parents[1]
RECONCILIATION = ROOT / "docs/validation/G3_NIST_TN2303_FCD_RECONCILIATION_2026-09-28.json"
DISCREPANT = [
    "Test022", "Test027", "Test029", "Test030", "Test033", "Test034", "Test035",
    "Test036", "Test038", "Test039", "Test040", "Test045", "Test047",
]


@functools.lru_cache(maxsize=1)
def _report() -> dict:
    return evaluate(load_source())


def _records() -> dict[str, dict]:
    return {record["test_id"]: record for record in load_source()["tests"]}


def test_all_48_sources_are_pinned_and_match_archived_pages() -> None:
    data = load_source()
    assert data["status"] == "research_only_cause_not_demonstrated_not_engine_calibration"
    assert data["acceptance_criteria"]["declared_before_evaluation"] is True
    pages = archived_pages(data)
    assert sorted(pages) == [f"Test{n:03d}" for n in range(1, 49)]
    for record in data["tests"]:
        page = pages[record["test_id"]]
        assert page["report_process_script"] == "NFRL_Report_8.7.1"
        assert page["last_updated"] == "April 7, 2026"
        for key, value in record["fcd2026"].items():
            assert page[key] == value, (record["test_id"], key)
        assert record["csv"]["ignition_s"] == page["ignition_s"] == 0
        assert record["csv"]["fire_out_s"] == page["fire_out_s"]
        assert (ROOT / record["csv"]["path"]).is_file()


def test_previously_imported_csvs_keep_their_audited_hashes() -> None:
    records = _records()
    for test_id, config in CASES.items():
        assert records[test_id]["csv"]["sha256"] == config["sha256"]
        assert records[test_id]["csv"]["fire_out_s"] == config["fire_out_s"]


def test_tn2025_transcription_agrees_with_the_earlier_reconciliation() -> None:
    earlier = {
        item["test_id"]: item
        for item in json.loads(RECONCILIATION.read_text(encoding="utf-8"))["records"]
    }
    records = _records()
    for test_id, item in earlier.items():
        old = records[test_id]["tn2025"]
        assert old["mass_lost_kg"] == item["mass_lost_kg"]
        assert old["thr_MJ"] == item["thr_MJ"]
        assert float(old["co_yield_printed"]) == item["co_yield_kg_per_kg"]
        assert float(old["co_yield_Uc_printed"]) == item["co_yield_Uc_kg_per_kg"]
    # Below-detection or igniter-only entries stay non-numeric, never zero.
    assert records["Test014"]["tn2025"]["co_yield_printed"] is None
    assert records["Test042"]["tn2025"]["mass_lost_kg"] == "igniter_only_A"
    assert records["Test018"]["fcd2026"]["co_yield_kg_per_kg"] == "below detection limit"
    assert records["Test048"]["fcd2026"]["co_yield_Uc_kg_per_kg"] is None


def test_documented_guide_method_reproduces_the_2026_summaries() -> None:
    report = _report()
    assert len(report["comparison_set"]) == 43
    guide = report["hypotheses"]["H0_guide_bg60_ignition_to_fire_out"]
    missing = sorted(set(report["comparison_set"]) - set(guide["fcd2026_within_Uc"]))
    assert missing == ["Test021"]
    # The 60 s and 120 s ambient windows are not distinguishable at Uc level.
    assert len(report["hypotheses"]["H3_bg120_ignition_to_fire_out"]["fcd2026_within_Uc"]) == 43


def test_version_differences_are_pinned_without_inventing_a_cause() -> None:
    report = _report()
    assert report["status"] == "research_only_cause_not_demonstrated"
    assert report["discrepant_tests"] == DISCREPANT
    assert report["mass_changed_tests"] == ["Test031", "Test035", "Test038"]
    records = _records()
    for test_id in report["comparison_set"]:
        old, new = records[test_id]["tn2025"]["thr_MJ"], records[test_id]["fcd2026"]["thr_MJ"]
        # TN prints some THR to whole MJ (24.8 -> 25.0); no THR was reprocessed.
        assert abs(old - new) <= max(0.5, 0.005 * old), test_id


def test_end_of_file_window_is_only_the_most_compatible_candidate() -> None:
    report = _report()
    results = report["hypotheses"]
    assert set(results) == set(HYPOTHESES)
    best = results["H1_bg60_ignition_to_end_of_file"]["tn2025_matches_on_discrepant"]
    assert best == [t for t in DISCREPANT if t not in ("Test039", "Test045", "Test047")]
    for name, item in results.items():
        if name != "H1_bg60_ignition_to_end_of_file":
            assert len(item["tn2025_matches_on_discrepant"]) <= 3, name
        # No tested treatment reproduces every printed 2025 value.
        assert len(item["tn2025_matches"]) < len(report["comparison_set"]), name
    # Moving the fire-out marker would also have changed THR in Test029,
    # which both versions print as 811 MJ: that variant is contradicted.
    windows = report["hrr_windows_MJ"]["Test029"]
    assert windows["after_fire_out_MJ"] > 20.0
    assert abs(windows["ignition_to_fire_out_MJ"] - 811.0) < 0.5
