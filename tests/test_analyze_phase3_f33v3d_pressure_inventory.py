from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3d_pressure_inventory as audit,
)


ROOT = Path(__file__).resolve().parents[1]
UNFILTERED = (
    ROOT / "runs" / "phase3_f33v3a" / "180_on" / "sim_log.csv"
)
FILTERED = ROOT / "runs" / "phase3_f33v3" / "180_full" / "sim_log.csv"
CFAST = (
    ROOT
    / "sim"
    / "validation"
    / "cfast"
    / "cfast_corridor_chain_compartments.csv"
)


def test_reference_inventory_is_ambient_pressure():
    pressure = audit.pressure_gauge_from_inventory(48.0 * 1.2, 0.0)
    assert pressure == pytest.approx(0.0, abs=1.0e-9)


def test_mass_and_energy_pressure_contributions_are_linear():
    combined = audit.pressure_delta_from_inventory(0.4, 25.0)
    separate = audit.pressure_delta_from_inventory(
        0.4, 0.0
    ) + audit.pressure_delta_from_inventory(0.0, 25.0)
    assert combined == pytest.approx(separate, abs=1.0e-12)


def _real_audit():
    return audit.build_audit(
        unfiltered_csv=UNFILTERED,
        filtered_csv=FILTERED,
        cfast_compartments_path=CFAST,
    )


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_real_candidates_close_the_pressure_eos():
    result = _real_audit()
    assert result["verdict"]["both_candidates_close_eos"]
    for label in ("unfiltered", "filtered"):
        verdict = result[label]["verdict"]
        assert verdict["max_owner_reconstruction_residual_pa"] < 1.0e-3
        assert verdict["max_observed_eos_residual_pa"] < 1.0e-3


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_other_family_is_exactly_multisurface_exchange():
    result = _real_audit()
    for label in ("unfiltered", "filtered"):
        assert result[label]["verdict"][
            "other_is_exact_multisurface_at_all_checkpoints"
        ]
        final = result[label]["checkpoints"]["180"]
        assert "multisurface" in final["owners"]
        assert "other" not in final["owners"]


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_unfiltered_sign_mismatches_match_exterior_audit():
    result = _real_audit()
    assert result["unfiltered"]["verdict"][
        "pressure_sign_mismatch_checkpoints"
    ] == [120, 130, 140, 180]


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_first_unfiltered_mismatch_is_upstream_of_pressure_corrections():
    first = _real_audit()["unfiltered"]["verdict"][
        "first_pressure_sign_mismatch"
    ]
    assert first["checkpoint_s"] == 120
    assert first["sign_is_negative_before_interior_pressure"]
    assert first["interior_pressure_is_restorative"]
    assert first["exterior_pressure_is_restorative"]
    assert not first["pressure_solver_created_negative_sign"]


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_first_mismatch_owner_order_is_stable_across_candidates():
    result = _real_audit()
    assert result["verdict"]["owner_order_consistent"]
    for label in ("unfiltered", "filtered"):
        first = result[label]["verdict"]["first_pressure_sign_mismatch"]
        assert first["primary_negative_window_owner"] == "multisurface"
        assert (
            first["primary_mass_routing_window_owner"]
            == "interior_opening"
        )


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_first_unfiltered_window_has_measured_near_cancellation():
    snapshot = _real_audit()["unfiltered"]["checkpoints"]["120"]
    owners = snapshot["window_owner_pressure_pa"]
    assert snapshot["reported_window_delta_pa"] == pytest.approx(
        -133.199, abs=0.1
    )
    assert owners["combustion"] == pytest.approx(11701.4, abs=0.2)
    assert owners["multisurface"] == pytest.approx(-7275.8, abs=0.2)
    assert owners["interior_opening"] == pytest.approx(-3489.8, abs=0.2)


@pytest.mark.skipif(
    not UNFILTERED.exists() or not FILTERED.exists(),
    reason="scratch candidates absent",
)
def test_verdict_blocks_pressure_and_leakage_tuning():
    verdict = _real_audit()["verdict"]
    assert verdict[
        "negative_sign_is_upstream_of_pressure_solver_in_both"
    ]
    assert verdict["unfiltered_pressure_corrections_restorative"]
    assert verdict["filtered_pressure_feedback_is_state_sensitive"]
    assert not verdict["pressure_or_leakage_tuning_allowed"]
    assert "multisurface" in verdict["root_cause_class"]
    assert "CFAST" in verdict["next_gate"]
