from pathlib import Path

import pytest

from scripts.simulation import analyze_phase3_f33v3f2_cap_ledger as audit


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "runs" / "phase3_f33v3f2" / "180_cap_ledger"
CFAST = ROOT / "sim" / "validation" / "cfast"


def test_cap_intervals_uses_cumulative_deltas():
    rows = [
        {
            "time_s": "10",
            f"{audit.PREFIX}cap_count_total": "2",
            f"{audit.PREFIX}cap_positive_count_total": "2",
            f"{audit.PREFIX}cap_negative_count_total": "0",
            f"{audit.PREFIX}cap_rejected_abs_kg_total": "0.3",
        },
        {
            "time_s": "20",
            f"{audit.PREFIX}cap_count_total": "5",
            f"{audit.PREFIX}cap_positive_count_total": "3",
            f"{audit.PREFIX}cap_negative_count_total": "2",
            f"{audit.PREFIX}cap_rejected_abs_kg_total": "1.0",
        },
    ]
    intervals = audit.cap_intervals(rows)
    assert intervals[0]["cap_count_total"] == 2
    assert intervals[1]["cap_count_total"] == 3
    assert intervals[1]["cap_rejected_abs_kg_total"] == pytest.approx(0.7)


@pytest.mark.skipif(
    not (RUN / "sim_log.csv").exists(),
    reason="scratch F3.3v3f2 cap-ledger run absent",
)
def test_real_cap_ledger_closes_and_identifies_directional_bias():
    result = audit.build_audit(
        sim_csv=RUN / "sim_log.csv",
        cfast_zone_path=CFAST / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            CFAST / "cfast_corridor_chain_compartments.csv"
        ),
    )
    metrics = result["metrics"]
    verdict = result["verdict"]
    assert metrics["cap_count"] == 79
    assert metrics["positive_cap_count"] == 44
    assert metrics["negative_cap_count"] == 35
    assert metrics["requested_share_of_cfast"] == pytest.approx(
        0.8735, abs=0.001
    )
    assert metrics["accepted_share_of_cfast"] == pytest.approx(
        0.4451, abs=0.001
    )
    assert verdict["cap_count_closes"]
    assert verdict["accepted_reconstruction_closes"]
    assert verdict["posthoc_cap_reverses_capped_integral"]
    assert not verdict["static_same_pressure_normalization_is_sufficient"]
