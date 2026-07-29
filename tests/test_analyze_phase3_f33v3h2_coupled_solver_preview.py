from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3h2_coupled_solver_preview as audit,
)


ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = ROOT / "runs" / "phase3_f33v3h2"
P = audit.PREFIX


def test_isolation_accepts_only_new_coupled_solver_columns():
    off = [{"time_s": "1", "room_id": "0", "upper_temp_c": "20"}]
    on = [{**off[0], f"{P}iterations": "4"}]
    result = audit.compare_columns(off, on)
    assert result["shared_value_difference_count"] == 0
    assert result["new_column_count"] == 1
    assert result["new_columns_all_coupled_solver"]
    assert result["missing_on_columns"] == []


def test_isolation_reports_a_changed_shared_value():
    result = audit.compare_columns(
        [{"time_s": "1", "upper_temp_c": "20"}],
        [{"time_s": "1", "upper_temp_c": "21"}],
    )
    assert result["shared_value_difference_count"] == 1
    assert result["first_difference"]["field"] == "upper_temp_c"


def test_isolation_rejects_a_foreign_new_column():
    result = audit.compare_columns(
        [{"time_s": "1"}], [{"time_s": "1", "phase3_shadow_other": "1"}]
    )
    assert not result["new_columns_all_coupled_solver"]


def test_isolation_rejects_a_dropped_column():
    result = audit.compare_columns(
        [{"time_s": "1", "legacy": "2"}], [{"time_s": "1"}]
    )
    assert result["missing_on_columns"] == ["legacy"]


def _row(**totals: str) -> dict[str, str]:
    row = {"time_s": "60.0", "room_id": "0", f"{P}enabled_flag": "1.0"}
    defaults = {
        "step_count": "100", "converged_step_count": "100",
        "failed_step_count": "0", "iteration_cap_step_count": "0",
        "damping_exhausted_step_count": "0", "max_iterations": "6",
        "max_normalized_residual": "0.0",
        "counterflow_violation_count": "0",
        "regularization_active_count": "10",
        "max_abs_coupled_vs_legacy_pressure_delta_pa": "1.0",
        "max_abs_net_mass_difference_kg": "0.01",
    }
    defaults.update(totals)
    for key, value in defaults.items():
        row[f"{P}{key}_total"] = value
    row.update({
        f"{P}cycle_guard_attempt_total": "0",
        f"{P}cycle_guard_accept_total": "0",
        f"{P}cycle_guard_last_rho": "0",
        f"{P}cycle_guard_last_cosine": "0",
    })
    return row


def test_behaviour_reports_the_convergence_rate_and_failure_split():
    result = audit.solver_behaviour(
        [_row(step_count="100", converged_step_count="80",
              failed_step_count="20", iteration_cap_step_count="12",
              damping_exhausted_step_count="8")],
        60.0,
    )
    assert result["convergence_rate"] == pytest.approx(0.8)
    assert result["iteration_cap_step_count"] == 12
    assert result["damping_exhausted_step_count"] == 8


def test_behaviour_reports_cycle_guard_telemetry():
    row = _row()
    row.update({
        f"{P}cycle_guard_attempt_total": "7",
        f"{P}cycle_guard_accept_total": "6",
        f"{P}cycle_guard_last_rho": "0.031",
        f"{P}cycle_guard_last_cosine": "-0.999",
    })
    result = audit.solver_behaviour([row], 60.0)
    assert result["cycle_guard_attempt_total"] == 7
    assert result["cycle_guard_accept_total"] == 6
    assert result["cycle_guard_last_rho"] == pytest.approx(0.031)
    assert result["cycle_guard_last_cosine"] == pytest.approx(-0.999)


def test_residual_and_counterflow_are_gated_but_convergence_rate_is_not():
    # H2 measures the convergence rate rather than gating on it; the solver's
    # own promises are what must hold.
    for key in ("converged_steps_close_their_residual", "no_counterflow_violation"):
        assert key in audit.REQUIRED_VERDICTS
    assert "converges_every_step" not in audit.REQUIRED_VERDICTS


@pytest.mark.skipif(
    not (RUN_ROOT / "060_on" / "sim_log.csv").exists(),
    reason="scratch F3.3v3h2 run absent",
)
def test_real_preview_is_isolated_and_keeps_its_invariants():
    result = audit.build_audit(
        off_csv=RUN_ROOT / "060_off" / "sim_log.csv",
        on_csv=RUN_ROOT / "060_on" / "sim_log.csv",
        checkpoint_s=60.0,
        room_id=0,
    )
    for key in audit.REQUIRED_VERDICTS:
        assert result["verdict"][key], key
    assert not result["verdict"]["runtime_authority_ready"]
    behaviour = result["solver_behaviour"]
    # measured limits of this phase, recorded so a regression is visible
    assert behaviour["failed_step_count"] > 0
    assert behaviour["max_normalized_residual"] == 0.0
    assert behaviour["counterflow_violation_count"] == 0.0
