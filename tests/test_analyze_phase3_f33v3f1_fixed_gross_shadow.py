import csv
from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3f1_fixed_gross_shadow as audit,
)


ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = ROOT / "runs" / "phase3_f33v3f1"
CFAST = ROOT / "sim" / "validation" / "cfast"


def test_compare_shared_columns_detects_exact_noop():
    off = [{"time_s": "1", "room_id": "0", "legacy": "2"}]
    on = [{**off[0], "phase3_shadow_fixed_gross_x": "3"}]
    result = audit.compare_shared_columns(off, on)
    assert result["shared_value_difference_count"] == 0
    assert result["new_columns"] == ["phase3_shadow_fixed_gross_x"]


def test_compare_shared_columns_reports_first_difference():
    result = audit.compare_shared_columns(
        [{"time_s": "1", "legacy": "2"}],
        [{"time_s": "1", "legacy": "3"}],
    )
    assert result["shared_value_difference_count"] == 1
    assert result["first_difference"]["field"] == "legacy"


def test_final_room_row_selects_requested_checkpoint():
    rows = [
        {"time_s": "10", "room_id": "0"},
        {"time_s": "20", "room_id": "0"},
        {"time_s": "20", "room_id": "1"},
    ]
    assert audit.final_room_row(rows, 0, 20)["time_s"] == "20"
    with pytest.raises(ValueError):
        audit.final_room_row(rows, 2, 20)


@pytest.mark.skipif(
    not (RUN_ROOT / "180_on" / "sim_log.csv").exists(),
    reason="scratch F3.3v3f1 run absent",
)
def test_real_stop_gate_is_noop_closed_and_close_to_cfast():
    result = audit.build_audit(
        off_csv=RUN_ROOT / "180_off" / "sim_log.csv",
        on_csv=RUN_ROOT / "180_on" / "sim_log.csv",
        cfast_zone_path=CFAST / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            CFAST / "cfast_corridor_chain_compartments.csv"
        ),
    )
    verdict = result["verdict"]
    assert verdict["off_on_shared_values_identical"]
    assert verdict["closure_ok"]
    assert verdict["gross_mass_within_3pct"]
    assert verdict["net_enthalpy_within_1pct"]
    assert not verdict["runtime_authority_ready"]
