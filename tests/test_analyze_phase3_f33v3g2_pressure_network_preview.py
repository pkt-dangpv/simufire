from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3g2_pressure_network_preview as audit,
)


ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = ROOT / "runs" / "phase3_f33v3g2"
CFAST = ROOT / "sim" / "validation" / "cfast"
PREFIX = audit.PREFIX


def test_compare_shared_columns_detects_exact_noop():
    off = [{"time_s": "1", "room_id": "0", "legacy": "2"}]
    on = [{**off[0], f"{PREFIX}alpha_accepted": "0.5"}]
    result = audit.compare_shared_columns(off, on)
    assert result["shared_value_difference_count"] == 0
    assert result["new_column_count"] == 1
    assert result["new_columns_all_pressure_network"]
    assert result["missing_off_columns"] == []


def test_compare_shared_columns_reports_first_difference():
    result = audit.compare_shared_columns(
        [{"time_s": "1", "legacy": "2"}],
        [{"time_s": "1", "legacy": "3"}],
    )
    assert result["shared_value_difference_count"] == 1
    assert result["first_difference"]["field"] == "legacy"


def test_compare_shared_columns_rejects_a_non_prefixed_new_column():
    result = audit.compare_shared_columns(
        [{"time_s": "1"}],
        [{"time_s": "1", "upper_temp_c": "20"}],
    )
    assert not result["new_columns_all_pressure_network"]


def _row(**overrides: str) -> dict[str, str]:
    row = {
        "time_s": "10.0",
        "room_id": "0",
        f"{PREFIX}enabled_flag": "1.0",
        f"{PREFIX}valid_flag": "1.0",
        f"{PREFIX}objective_pre_pa2": "100.0",
        f"{PREFIX}objective_post_pa2": "10.0",
        f"{PREFIX}negative_quantity_count": "0.0",
        f"{PREFIX}predicted_collapse_count_step": "0.0",
        f"{PREFIX}predicted_min_upper_gas_kg": "1.0",
        f"{PREFIX}predicted_min_lower_gas_kg": "2.0",
        f"{PREFIX}limiting_reason_code": "1.0",
        f"{PREFIX}alpha_optimal": "0.5",
        f"{PREFIX}alpha_crossing": "1.0",
        f"{PREFIX}alpha_inventory": "1.0",
        f"{PREFIX}alpha_accepted": "0.5",
    }
    for field in (
        "gross_mass_residual_kg",
        "mass_residual_kg",
        "energy_residual_kj",
        "o2_residual_kg",
        "species_residual_kg",
    ):
        row[f"{PREFIX}{field}"] = "0.0"
    row.update(overrides)
    return row


def test_step_contract_flags_an_increasing_objective():
    clean = audit.step_contract([_row()])
    assert clean["objective_increase_count"] == 0
    assert clean["limiting_reason_counts"] == {"optimal": 1}
    dirty = audit.step_contract(
        [_row(**{f"{PREFIX}objective_post_pa2": "101.0"})]
    )
    assert dirty["objective_increase_count"] == 1
    assert dirty["worst_objective_increase_pa2"] == pytest.approx(1.0)


def test_step_contract_ignores_rows_where_the_preview_is_off():
    result = audit.step_contract([_row(**{f"{PREFIX}enabled_flag": "0.0"})])
    assert result["active_step_row_count"] == 0


def test_step_contract_flags_a_predicted_collapse():
    result = audit.step_contract(
        [_row(**{f"{PREFIX}predicted_collapse_count_step": "1.0"})]
    )
    assert result["predicted_collapse_step_row_count"] == 1


@pytest.mark.skipif(
    not (RUN_ROOT / "180_on" / "sim_log.csv").exists(),
    reason="scratch F3.3v3g2 run absent",
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
    for key in audit.REQUIRED_VERDICTS:
        assert result["verdict"][key], key
    assert not result["verdict"]["runtime_authority_ready"]
