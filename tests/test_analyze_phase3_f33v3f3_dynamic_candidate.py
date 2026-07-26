from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3f3_dynamic_candidate as audit,
)


ROOT = Path(__file__).resolve().parents[1]
BASELINE = (
    ROOT / "runs" / "phase3_f33v3f2" / "180_cap_ledger" / "sim_log.csv"
)
CANDIDATE = (
    ROOT / "runs" / "phase3_f33v3f3" / "180_candidate" / "sim_log.csv"
)


def test_compare_live_values_excludes_shadow_columns():
    fields = ["time_s", "room_id", "live", "phase3_shadow_value"]
    baseline = [
        {
            "time_s": "1",
            "room_id": "0",
            "live": "same",
            "phase3_shadow_value": "1",
        }
    ]
    candidate = [
        {
            "time_s": "1",
            "room_id": "0",
            "live": "same",
            "phase3_shadow_value": "999",
        }
    ]
    result = audit.compare_live_values(
        fields, baseline, fields, candidate
    )
    assert result["rows_align"]
    assert result["shared_live_field_count"] == 3
    assert result["live_value_difference_count"] == 0


def test_compare_live_values_reports_live_difference():
    fields = ["time_s", "room_id", "live"]
    baseline = [{"time_s": "1", "room_id": "0", "live": "before"}]
    candidate = [{"time_s": "1", "room_id": "0", "live": "after"}]
    result = audit.compare_live_values(
        fields, baseline, fields, candidate
    )
    assert result["live_value_difference_count"] == 1
    assert result["first_live_differences"][0]["field"] == "live"


@pytest.mark.skipif(
    not BASELINE.exists() or not CANDIDATE.exists(),
    reason="scratch F3.3v3f3 evidence runs absent",
)
def test_real_candidate_is_isolated_but_unstable():
    result = audit.build_audit(
        baseline_csv=BASELINE,
        candidate_csv=CANDIDATE,
    )
    isolation = result["isolation"]
    baseline = result["baseline"]
    candidate = result["candidate"]
    verdict = result["verdict"]

    assert isolation["baseline_row_count"] == 114
    assert isolation["candidate_row_count"] == 114
    assert isolation["shared_live_field_count"] == 115
    assert isolation["live_value_difference_count"] == 0
    assert baseline["cap_count"] == 79
    assert candidate["cap_count"] == 1676
    assert candidate["positive_cap_count"] == 1676
    assert candidate["negative_cap_count"] == 0
    assert candidate["requested_pressure_net_out_kg"] == pytest.approx(
        804.65884689
    )
    assert candidate["lower_gas_kg"] == pytest.approx(0.0)
    assert verdict["isolation_ok"]
    assert verdict["one_way_pressure_runaway"]
    assert verdict["lower_zone_collapsed"]
    assert not verdict["candidate_stable"]
    assert not verdict["runtime_authority_ready"]
