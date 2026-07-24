from __future__ import annotations

import pytest

from scripts.simulation import analyze_phase3_f33q_boundary_energy as audit


def _sim_checkpoint(
    *,
    stored: float,
    combustion: float,
    opening: float = 0.0,
    pressure: float = 0.0,
    wall: float = 0.0,
    ambient: float = 0.0,
    exterior: float = 0.0,
    counterflow: float = 0.0,
) -> dict:
    families = {family: 0.0 for family in (
        "combustion",
        *audit.DOORWAY_FAMILIES,
        *audit.BOUNDARY_FAMILIES,
        *audit.INTERNAL_FAMILIES,
    )}
    families.update(
        {
            "combustion": combustion,
            "interior_opening": opening,
            "interior_pressure": pressure,
            "wall": wall,
            "ambient": ambient,
            "exterior": exterior,
            "exterior_counterflow": counterflow,
        }
    )
    return {
        "stored_energy_kj": stored,
        "families_net_kj": families,
    }


def _cfast_checkpoint(
    *,
    stored: float,
    source: float,
    outgoing: float = 0.0,
    incoming: float = 0.0,
) -> dict:
    return {
        "r0": {
            "sensible_energy_kj": stored,
            "convective_energy_kj": source,
        },
        "routes": {
            "0->1": {"enthalpy_kj": outgoing},
            "1->0": {"enthalpy_kj": incoming},
        },
    }


def test_family_net_uses_both_zones_and_directions() -> None:
    row = {
        "phase3_shadow_enthalpy_wall_upper_in_kj_total": "2",
        "phase3_shadow_enthalpy_wall_lower_in_kj_total": "3",
        "phase3_shadow_enthalpy_wall_upper_out_kj_total": "7",
        "phase3_shadow_enthalpy_wall_lower_out_kj_total": "11",
    }
    assert audit._family_net_kj(row, "wall") == pytest.approx(-13.0)


def test_build_window_reconstructs_cfast_boundary_sink() -> None:
    result = audit.build_window(
        start_s=0,
        end_s=60,
        sim_current=_sim_checkpoint(
            stored=40,
            combustion=100,
            opening=-10,
            wall=-20,
            ambient=-20,
            exterior=-10,
        ),
        sim_previous=None,
        cfast_current=_cfast_checkpoint(
            stored=30,
            source=100,
            outgoing=25,
            incoming=5,
        ),
        cfast_previous=None,
    )
    assert result["cfast"]["doorway_net_kj"] == pytest.approx(-20.0)
    assert result["cfast"]["inferred_boundary_sink_kj"] == pytest.approx(
        50.0
    )


def test_build_window_reconstructs_shadow_boundary_sink() -> None:
    result = audit.build_window(
        start_s=0,
        end_s=60,
        sim_current=_sim_checkpoint(
            stored=40,
            combustion=100,
            opening=-10,
            wall=-20,
            ambient=-20,
            exterior=-10,
        ),
        sim_previous=None,
        cfast_current=_cfast_checkpoint(stored=40, source=100),
        cfast_previous=None,
    )
    assert result["sim"]["doorway_net_kj"] == pytest.approx(-10.0)
    assert result["sim"]["inferred_boundary_sink_kj"] == pytest.approx(
        50.0
    )
    assert result["sim"]["observed_boundary_sink_kj"] == pytest.approx(
        50.0
    )
    assert result["sim"]["boundary_closure_residual_kj"] == pytest.approx(
        0.0
    )


def test_build_window_uses_cumulative_deltas() -> None:
    previous_sim = _sim_checkpoint(
        stored=40,
        combustion=100,
        wall=-20,
        ambient=-20,
    )
    current_sim = _sim_checkpoint(
        stored=70,
        combustion=180,
        opening=-10,
        wall=-35,
        ambient=-35,
    )
    previous_cfast = _cfast_checkpoint(stored=30, source=100)
    current_cfast = _cfast_checkpoint(
        stored=50,
        source=180,
        outgoing=10,
    )
    result = audit.build_window(
        start_s=60,
        end_s=120,
        sim_current=current_sim,
        sim_previous=previous_sim,
        cfast_current=current_cfast,
        cfast_previous=previous_cfast,
    )
    assert result["sim"]["source_kj"] == pytest.approx(80.0)
    assert result["sim"]["storage_delta_kj"] == pytest.approx(30.0)
    assert result["sim"]["observed_boundary_sink_kj"] == pytest.approx(
        30.0
    )
    assert result["cfast"]["source_kj"] == pytest.approx(80.0)
    assert result["cfast"]["doorway_net_kj"] == pytest.approx(-10.0)
    assert result["cfast"]["storage_delta_kj"] == pytest.approx(20.0)


def test_internal_transfers_are_reported_but_not_boundary_sinks() -> None:
    current = _sim_checkpoint(stored=50, combustion=100, wall=-50)
    current["families_net_kj"]["plume"] = 3.0
    current["families_net_kj"]["interzone"] = -3.0
    result = audit.build_window(
        start_s=0,
        end_s=60,
        sim_current=current,
        sim_previous=None,
        cfast_current=_cfast_checkpoint(stored=50, source=100),
        cfast_previous=None,
    )
    assert result["sim"]["internal_net_kj"] == pytest.approx(0.0)
    assert result["sim"]["observed_boundary_sink_kj"] == pytest.approx(
        50.0
    )


def test_surface_area_contract_matches_r0_geometry() -> None:
    floor = audit.R0_WIDTH_M * audit.R0_LENGTH_M
    enclosure = (
        2.0 * floor
        + 2.0
        * (audit.R0_WIDTH_M + audit.R0_LENGTH_M)
        * audit.R0_HEIGHT_M
    )
    assert floor == pytest.approx(20.0)
    assert enclosure == pytest.approx(83.2)
    assert 2.0 * floor / enclosure == pytest.approx(0.4807692308)
