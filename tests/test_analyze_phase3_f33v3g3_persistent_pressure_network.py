from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3g3_persistent_pressure_network as audit,
)


ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = ROOT / "runs" / "phase3_f33v3g3"
CFAST = ROOT / "sim" / "validation" / "cfast"
PREFIX = audit.PREFIX
GAUGE = "phase3_shadow_thermo_pressure_gauge_pa"
REQUESTED = "phase3_shadow_fixed_gross_pressure_requested_net_out_kg_total"


def test_shadow_columns_may_change_but_live_columns_may_not():
    off = [{"time_s": "1", "room_id": "0", "upper_temp_c": "20",
            "phase3_shadow_upper_gas_kg": "1.0"}]
    on = [{**off[0], "phase3_shadow_upper_gas_kg": "1.5",
           f"{PREFIX}alpha_accepted": "0.5"}]
    result = audit.compare_live_columns(off, on)
    assert result["live_value_difference_count"] == 0
    assert result["shadow_value_difference_count"] == 1
    assert result["changed_shadow_column_count"] == 1
    assert result["new_columns_all_persistent"]


def test_a_changed_live_column_is_reported():
    result = audit.compare_live_columns(
        [{"time_s": "1", "room_id": "0", "upper_temp_c": "20"}],
        [{"time_s": "1", "room_id": "0", "upper_temp_c": "21"}],
    )
    assert result["live_value_difference_count"] == 1
    assert result["first_live_difference"]["field"] == "upper_temp_c"


def test_a_non_persistent_new_column_is_rejected():
    result = audit.compare_live_columns(
        [{"time_s": "1", "room_id": "0"}],
        [{"time_s": "1", "room_id": "0", "phase3_shadow_other": "1"}],
    )
    assert not result["new_columns_all_persistent"]


def _divergence_rows(baseline: list[float], candidate: list[float]):
    off, on = [], []
    for index, (base_pa, candidate_pa) in enumerate(zip(baseline, candidate)):
        stamp = str(10.0 * (index + 1))
        off.append({"time_s": stamp, "room_id": "0", GAUGE: str(base_pa),
                    REQUESTED: "1.0"})
        on.append({"time_s": stamp, "room_id": "0", GAUGE: str(candidate_pa),
                   REQUESTED: "2.0"})
    return off, on


def test_pressure_divergence_tracks_the_worst_gauge_ratio():
    off, on = _divergence_rows([1.0, 2.0, 4.0], [1.0, 4.0, 20.0])
    result = audit.pressure_divergence(off, on, 30.0)
    assert result["max_gauge_ratio"] == pytest.approx(5.0)
    assert result["final_candidate_gauge_pa"] == pytest.approx(20.0)
    assert result["requested_growth_vs_baseline"] == pytest.approx(2.0)


def test_pressure_divergence_is_flat_when_the_candidate_matches_baseline():
    off, on = _divergence_rows([1.0, 2.0, 4.0], [1.0, 2.0, 4.0])
    result = audit.pressure_divergence(off, on, 30.0)
    assert result["max_gauge_ratio"] == pytest.approx(1.0)


def test_cfast_envelope_is_gated_to_the_final_stage_only():
    assert audit.FINAL_CHECKPOINT_S == 180
    for key in audit.FINAL_STAGE_VERDICTS:
        assert key not in audit.REQUIRED_VERDICTS
    assert "no_pressure_runaway" in audit.REQUIRED_VERDICTS
    assert "no_monotonic_request_growth" in audit.REQUIRED_VERDICTS
    assert "no_prediction_runaway" in audit.REQUIRED_VERDICTS
    assert "live_columns_identical" in audit.REQUIRED_VERDICTS


@pytest.mark.skipif(
    not (RUN_ROOT / "030_on" / "sim_log.csv").exists(),
    reason="scratch F3.3v3g3 stage-1 run absent",
)
def test_real_stage_one_isolates_live_state_but_fails_on_feedback():
    result = audit.build_audit(
        off_csv=RUN_ROOT / "030_off" / "sim_log.csv",
        on_csv=RUN_ROOT / "030_on" / "sim_log.csv",
        cfast_zone_path=CFAST / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            CFAST / "cfast_corridor_chain_compartments.csv"
        ),
        checkpoint_s=30,
    )
    verdict = result["verdict"]
    # the mechanism is clean
    assert verdict["live_columns_identical"]
    assert verdict["only_persistent_columns_added"]
    assert verdict["mass_closure_ok"]
    assert verdict["energy_closure_ok"]
    assert verdict["o2_closure_ok"]
    assert verdict["species_closure_ok"]
    assert verdict["bundle_applies_the_requested_fraction"]
    assert verdict["no_unexpected_zone_collapse"]
    assert verdict["eos_always_valid"]
    assert verdict["no_live_isolation_violation"]
    # the physics is not
    assert not verdict["stage_pass"]
    assert not verdict["no_pressure_runaway"]
    assert not verdict["no_monotonic_request_growth"]
    assert result["pressure_divergence"]["max_gauge_ratio"] > 5.0
