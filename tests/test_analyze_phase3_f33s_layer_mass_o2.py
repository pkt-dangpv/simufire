"""Tests for the passive F3.3s layer-mass/interface/O2 audit."""

from __future__ import annotations

import pytest

from scripts.simulation import analyze_phase3_f33s_layer_mass_o2 as audit


def _owner_row(family: str, *, upper_in=0, upper_out=0, lower_in=0, lower_out=0):
    prefix = f"phase3_shadow_mass_residence_{family}_"
    return {
        prefix + "upper_in_kg_total": str(upper_in),
        prefix + "upper_out_kg_total": str(upper_out),
        prefix + "lower_in_kg_total": str(lower_in),
        prefix + "lower_out_kg_total": str(lower_out),
    }


def test_residence_family_net_preserves_zone_and_room_signs():
    row = _owner_row(
        "plume", upper_in=4, upper_out=1, lower_in=2, lower_out=8
    )
    result = audit.residence_family_net(row, "plume")
    assert result == {
        "upper_kg": 3.0,
        "lower_kg": -6.0,
        "room_kg": -3.0,
        "gross_kg": 15.0,
    }


def test_plume_geometry_uses_far_field_before_flame_crossing():
    result = audit.plume_geometry(
        hrr_kw=10,
        interface_m=2.0,
        room_height_m=2.4,
        fire_diameter_m=0.6,
        convective_fraction=0.3,
    )
    assert result["branch"] == "far_field"
    assert result["flame_reaches_interface"] is False
    assert result["z_eff_m"] > 0.1


def test_plume_geometry_clamps_when_flame_reaches_interface():
    result = audit.plume_geometry(
        hrr_kw=300,
        interface_m=1.0,
        room_height_m=2.4,
        fire_diameter_m=0.6,
        convective_fraction=0.3,
    )
    assert result["branch"] == "interface_clamp"
    assert result["flame_reaches_interface"] is True
    assert result["z_eff_m"] == pytest.approx(0.1)


def test_plume_geometry_uses_room_confined_branch():
    result = audit.plume_geometry(
        hrr_kw=2000,
        interface_m=0.5,
        room_height_m=2.4,
        fire_diameter_m=0.6,
        convective_fraction=0.3,
    )
    assert result["branch"] == "confined_room"
    assert result["z_eff_m"] == pytest.approx(2.4)


def test_mass_threshold_uses_larger_absolute_or_relative_limit():
    assert audit.exceeds_mass_threshold(1.1, 5.0)
    assert not audit.exceeds_mass_threshold(1.1, 20.0)
    assert audit.exceeds_mass_threshold(2.1, 20.0)


def test_first_checkpoint_is_time_ordered():
    snapshots = {
        "20": {"bad": True},
        "10": {"bad": False},
        "30": {"bad": True},
    }
    assert audit.first_checkpoint(snapshots, "bad") == 20
    assert audit.first_checkpoint(snapshots, "missing") is None


def test_causal_verdict_selects_plume_before_o2():
    snapshots = {
        "10": {
            "mass_or_interface_diverged": True,
            "o2_diverged": False,
            "flame_reaches_interface": False,
            "near_interface_pinch": False,
            "cfast_flame_reaches_interface": False,
            "mass_ledger_pass": True,
            "projection_net_kg": 0.0,
            "doorway_gross_kg": 0.2,
            "plume_cumulative_shortfall_kg": 2.0,
            "upper_mass_error_kg": -3.0,
        },
        "20": {
            "mass_or_interface_diverged": True,
            "o2_diverged": True,
            "flame_reaches_interface": True,
            "near_interface_pinch": True,
            "cfast_flame_reaches_interface": True,
            "mass_ledger_pass": True,
            "projection_net_kg": 0.0,
            "doorway_gross_kg": 0.4,
            "plume_cumulative_shortfall_kg": 3.0,
            "upper_mass_error_kg": -4.0,
        },
    }
    verdict = audit.causal_verdict(snapshots)
    assert verdict["primary_owner"] == "plume_request_source_path"
    assert verdict["first_mass_or_interface_divergence_s"] == 10
    assert verdict["first_o2_divergence_s"] == 20
    assert verdict["first_flame_interface_crossing_s"] == 20
    assert verdict["first_near_interface_pinch_s"] == 20
    assert verdict["first_cfast_flame_interface_crossing_s"] == 20
    assert verdict["o2_is_downstream"] is True
    assert verdict["projection_is_primary"] is False


def test_causal_verdict_refuses_unclosed_ledger():
    snapshots = {
        "10": {
            "mass_or_interface_diverged": True,
            "o2_diverged": False,
            "flame_reaches_interface": False,
            "near_interface_pinch": False,
            "cfast_flame_reaches_interface": False,
            "mass_ledger_pass": False,
            "projection_net_kg": 0.0,
            "doorway_gross_kg": 0.1,
            "plume_cumulative_shortfall_kg": 3.0,
            "upper_mass_error_kg": -4.0,
        }
    }
    assert (
        audit.causal_verdict(snapshots)["primary_owner"]
        == "unresolved_mass_owner"
    )


def test_empty_checkpoint_sequence_is_rejected_before_file_reads():
    with pytest.raises(ValueError, match="at least one checkpoint"):
        audit.build_audit(
            candidate_csv=None,
            manifest_path=None,
            cfast_zone_path=None,
            cfast_compartments_path=None,
            cfast_masses_path=None,
            checkpoints=(),
        )
