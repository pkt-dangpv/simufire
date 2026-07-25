"""Tests for the passive F3.3r2d source and routing attribution."""

from __future__ import annotations

import pytest

from scripts.simulation import (
    analyze_phase3_f33r2d_source_routing as audit,
)


def test_surface_weights_close_and_follow_interface():
    low_interface = audit.surface_weights(0, 0.5)
    high_interface = audit.surface_weights(0, 1.8)
    assert sum(low_interface.values()) == pytest.approx(1.0)
    assert sum(high_interface.values()) == pytest.approx(1.0)
    assert low_interface["upper_wall"] > high_interface["upper_wall"]
    assert low_interface["lower_wall"] < high_interface["lower_wall"]


def test_counterfactual_routes_cumulative_increments_without_creation():
    rows = [
        {
            "time_s": "0",
            "room_id": "0",
            "phase3_shadow_multisurface_cumulative_fire_radiation_kj": "0",
        },
        {
            "time_s": "10",
            "room_id": "0",
            "phase3_shadow_multisurface_cumulative_fire_radiation_kj": "40",
        },
        {
            "time_s": "20",
            "room_id": "0",
            "phase3_shadow_multisurface_cumulative_fire_radiation_kj": "100",
        },
    ]
    routed = audit.counterfactual_routing(
        rows,
        room_id=0,
        checkpoint_s=20,
        interface_at=lambda _time: 1.2,
    )
    assert sum(routed.values()) == pytest.approx(100.0)


def test_source_decomposition_closes_and_identifies_decision_rejection():
    result = audit.source_decomposition(
        cfast_radiation_kj=140,
        requested_kj=130,
        pre_atomic_kj=100,
        decision_rejected_kj=30,
        atomic_rejected_kj=5,
        routed_kj=95,
    )
    assert result["cfast_shortfall_kj"] == pytest.approx(45)
    assert result["decomposition_residual_kj"] == pytest.approx(0)
    assert result["dominant_cause"] == "decision_rejection"


def test_source_decomposition_can_identify_upstream_trajectory():
    result = audit.source_decomposition(
        cfast_radiation_kj=140,
        requested_kj=80,
        pre_atomic_kj=75,
        decision_rejected_kj=5,
        atomic_rejected_kj=0,
        routed_kj=75,
    )
    assert result["dominant_cause"] == "upstream_source_trajectory"


def test_counterfactual_rejects_missing_room():
    with pytest.raises(ValueError, match="room 0 has no rows"):
        audit.counterfactual_routing(
            [],
            room_id=0,
            checkpoint_s=180,
            interface_at=lambda _time: 1.0,
        )


def test_empty_checkpoint_sequence_is_rejected_before_reading_files():
    with pytest.raises(ValueError, match="at least one checkpoint"):
        audit.build_audit(
            off_csv=None,
            candidate_csv=None,
            checkpoints=iter(()),
        )
