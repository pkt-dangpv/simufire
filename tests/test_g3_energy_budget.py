"""Pure numerical contracts for the G3 energy-budget diagnostic."""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts/simulation"
sys.path.insert(0, str(SCRIPTS))
PATH = SCRIPTS / "analyze_g3_energy_budget.py"
SPEC = importlib.util.spec_from_file_location("analyze_g3_energy_budget", PATH)
assert SPEC and SPEC.loader
budget = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(budget)


def _row(**changes):
    row = {
        "time_s": 1.0,
        "dt_s": 1.0,
        "consumed_MJ": 0.10,
        "pyrolysis_kw": 100.0,
        "flame_target_kw": 80.0,
        "smolder_target_kw": 0.0,
        "actual_solid_burn_kw": 50.0,
        "actual_pool_burn_kw": 0.0,
        "pool_generation_MJ": 0.01,
        "pool_before_MJ": 0.0,
        "pool_after_MJ": 0.01,
    }
    row.update(changes)
    return row


def test_unreleased_energy_separates_target_and_smoothing() -> None:
    result = budget.step_budget(_row())
    assert result["solid_unreleased_MJ"] == pytest.approx(0.04)
    assert result["target_gap_MJ"] == pytest.approx(0.01)
    assert result["smoothing_gap_MJ"] == pytest.approx(0.03)
    assert result["decomposition_residual_MJ"] == pytest.approx(0.0)
    assert result["pyrolysis_debit_residual_MJ"] == pytest.approx(0.0)
    assert result["pool_other_reduction_MJ"] == pytest.approx(0.0)


def test_legacy_heat_tail_is_a_negative_smoothing_gap() -> None:
    result = budget.step_budget(
        _row(
            consumed_MJ=0.0,
            pyrolysis_kw=0.0,
            flame_target_kw=0.0,
            actual_solid_burn_kw=20.0,
            pool_generation_MJ=0.0,
            pool_after_MJ=0.0,
        )
    )
    assert result["smoothing_gap_MJ"] == pytest.approx(-0.02)
    assert result["solid_unreleased_MJ"] == pytest.approx(-0.02)


def test_bad_step_and_nonfinite_data_fail_closed() -> None:
    with pytest.raises(ValueError, match="dt_s"):
        budget.step_budget(_row(dt_s=0.0))
    with pytest.raises(ValueError, match="nonfinite"):
        budget.step_budget(_row(consumed_MJ=float("nan")))
    missing = _row()
    del missing["pyrolysis_kw"]
    with pytest.raises(ValueError, match="positive fuel debit"):
        budget.step_budget(missing)


def test_summary_preserves_signed_gaps() -> None:
    result = budget.summarize([
        _row(),
        _row(
            time_s=2.0,
            consumed_MJ=0.0,
            pyrolysis_kw=0.0,
            flame_target_kw=0.0,
            actual_solid_burn_kw=20.0,
            pool_generation_MJ=0.0,
            pool_before_MJ=0.01,
            pool_after_MJ=0.01,
        ),
    ])
    assert result["steps"] == 2
    assert result["solid_unreleased_MJ"] == pytest.approx(0.02)
    assert result["peak_negative_smoothing_gap_MJ"] == pytest.approx(-0.02)


def _filter_rows(targets_kw, *, dt, rise_tau, fall_tau, clamp_to_target=False):
    rows, applied = [], 0.0
    for index, target in enumerate(targets_kw):
        tau = rise_tau if target > applied else fall_tau
        filtered = applied + (target - applied) * (1.0 - math.exp(-dt / tau))
        applied_now = min(filtered, target) if clamp_to_target else filtered
        rows.append({
            "time_s": (index + 1) * dt, "dt_s": dt, "hrr_requested_kw": target,
            "hrr_applied_kw": applied_now, "actual_pool_burn_kw": 0.0,
            "switch_on": clamp_to_target,
        })
        applied = applied_now
    return rows


def test_filter_attribution_matches_closed_form_for_step_fire() -> None:
    dt, rise, fall = 1.0 / 12.0, 10.8, 20.0
    targets = [100.0] * 12 * 200 + [0.0] * 12 * 600
    legacy = budget.filter_attribution(
        _filter_rows(targets, dt=dt, rise_tau=rise, fall_tau=fall),
        rise_tau_s=rise, fall_tau_s=fall,
    )
    peak = legacy["peak_applied_kw"]
    assert legacy["max_abs_legacy_filter_error_kw"] == 0.0
    assert legacy["clamp_removed_MJ"] == 0.0
    assert legacy["rise_lag_MJ"] == pytest.approx(legacy["rise_tau_eff_s"] * peak / 1000.0)
    assert legacy["fall_excess_MJ"] == pytest.approx(
        -legacy["fall_tau_eff_s"] * (peak - legacy["final_applied_kw"]) / 1000.0
    )
    # Legacy creates (tau_f - tau_r) * peak of heat that no fuel paid for.
    created = -(legacy["rise_lag_MJ"] + legacy["fall_excess_MJ"])
    assert created == pytest.approx(
        (legacy["fall_tau_eff_s"] - legacy["rise_tau_eff_s"]) * peak / 1000.0, rel=1e-6
    )


def test_filter_attribution_clamped_branch_loses_only_the_rise_lag() -> None:
    dt, rise, fall = 1.0 / 12.0, 10.8, 20.0
    targets = [100.0] * 12 * 200 + [0.0] * 12 * 600
    clamped = budget.filter_attribution(
        _filter_rows(targets, dt=dt, rise_tau=rise, fall_tau=fall, clamp_to_target=True),
        rise_tau_s=rise, fall_tau_s=fall,
    )
    assert clamped["fall_excess_MJ"] + clamped["clamp_removed_MJ"] == pytest.approx(0.0)
    assert clamped["rise_lag_MJ"] == pytest.approx(
        clamped["rise_tau_eff_s"] * clamped["peak_applied_kw"] / 1000.0
    )


def test_filter_attribution_rejects_bad_constants() -> None:
    with pytest.raises(ValueError, match="positive"):
        budget.filter_attribution([_row()], rise_tau_s=0.0, fall_tau_s=20.0)
