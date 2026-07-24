"""Tests for the Phase 3 F3.3m source-correspondence analyzer."""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "simulation"))

from analyze_phase3_f33m_source_correspondence import (
    add_windows,
    aggregate_sim_connection,
    cfast_tanhsmooth_upper_fraction,
    integrate_cfast_connection,
    read_cfast_zone,
)


def _cfast_row(time_s, flow, temp_k=313.15):
    row = {
        "Time": str(time_s),
        "ULT_1": "100",
        "LLT_1": "20",
        "ULT_2": "80",
        "LLT_2": "20",
    }
    for slab in range(1, 11):
        row[f"HSLABF_1_{slab}"] = str(flow if slab == 1 else 0.0)
        row[f"HSLABT_1_{slab}"] = str(temp_k)
    return row


def test_cfast_tanhsmooth_saturates_at_receiver_layers():
    assert cfast_tanhsmooth_upper_fraction(10.0, 100.0, 20.0) == 0.0
    assert cfast_tanhsmooth_upper_fraction(120.0, 100.0, 20.0) == 1.0


def test_integrate_cfast_positive_direction_mass_and_enthalpy():
    rows = [_cfast_row(0, 1.0), _cfast_row(10, 1.0)]
    result = integrate_cfast_connection(
        rows,
        checkpoint_s=10,
        vent=1,
        sign=1,
        destination_compartment=2,
    )
    assert result["mass_kg"] == pytest.approx(10.0)
    assert result["enthalpy_kj"] == pytest.approx(200.0)
    assert result["source_temp_c"] == pytest.approx(40.0)


def test_integrate_cfast_reverse_direction_uses_negative_flow():
    rows = [_cfast_row(0, -0.5), _cfast_row(10, -0.5)]
    result = integrate_cfast_connection(
        rows,
        checkpoint_s=10,
        vent=1,
        sign=-1,
        destination_compartment=1,
    )
    assert result["mass_kg"] == pytest.approx(5.0)


def test_aggregate_sim_connection_separates_families_and_routes():
    records = [
        {
            "opening_id": 0,
            "source_room_id": 0,
            "destination_room_id": 1,
            "family": "interior_opening",
            "accepted_mass_kg": 2.0,
            "accepted_enthalpy_kj": 80.0,
            "source_upper_mass_kg": 1.5,
            "source_lower_mass_kg": 0.5,
            "destination_upper_mass_kg": 0.25,
            "destination_lower_mass_kg": 1.75,
            "accepted_route_count": 3,
        },
        {
            "opening_id": 0,
            "source_room_id": 0,
            "destination_room_id": 1,
            "family": "interior_pressure",
            "accepted_mass_kg": 1.0,
            "accepted_enthalpy_kj": 10.0,
            "source_upper_mass_kg": 0.0,
            "source_lower_mass_kg": 1.0,
            "destination_upper_mass_kg": 0.0,
            "destination_lower_mass_kg": 1.0,
            "accepted_route_count": 2,
        },
        {
            "opening_id": 2,
            "source_room_id": 0,
            "destination_room_id": 1,
            "family": "interior_opening",
            "accepted_mass_kg": 100.0,
        },
    ]
    result = aggregate_sim_connection(
        records, opening_id=0, source_room_id=0, destination_room_id=1
    )
    assert result["mass_kg"] == pytest.approx(3.0)
    assert result["enthalpy_kj"] == pytest.approx(90.0)
    assert result["families_kg"]["interior_opening"] == pytest.approx(2.0)
    assert result["families_kg"]["interior_pressure"] == pytest.approx(1.0)
    assert result["source_upper_fraction"] == pytest.approx(0.5)
    assert result["destination_upper_fraction"] == pytest.approx(1.0 / 12.0)
    assert result["route_count"] == 5


def test_add_windows_subtracts_cumulative_routes():
    checkpoints = [
        {
            "checkpoint_s": 60,
            "sim": {"routes": {"0->1": {"mass_kg": 2, "enthalpy_kj": 20}}},
            "cfast": {
                "routes": {"0->1": {"mass_kg": 3, "enthalpy_kj": 30}}
            },
        },
        {
            "checkpoint_s": 120,
            "sim": {"routes": {"0->1": {"mass_kg": 5, "enthalpy_kj": 80}}},
            "cfast": {
                "routes": {"0->1": {"mass_kg": 7, "enthalpy_kj": 100}}
            },
        },
    ]
    windows = add_windows(checkpoints)
    assert windows[0]["sim_routes"]["0->1"]["mass_kg"] == pytest.approx(2.0)
    assert windows[1]["sim_routes"]["0->1"]["mass_kg"] == pytest.approx(3.0)
    assert windows[1]["sim_routes"]["0->1"]["enthalpy_kj"] == pytest.approx(
        60.0
    )


def test_committed_cfast_reverse_route_reconstructs_f33i():
    rows = read_cfast_zone(
        ROOT / "sim/validation/cfast/cfast_corridor_chain_zone.csv"
    )
    result = integrate_cfast_connection(
        rows,
        checkpoint_s=180,
        vent=1,
        sign=-1,
        destination_compartment=1,
    )
    assert result["mass_kg"] == pytest.approx(69.44193552, abs=1e-6)
    assert result["enthalpy_kj"] == pytest.approx(1459.09797265, abs=1e-6)
    assert result["destination_upper_kg"] == pytest.approx(
        3.66218629, abs=1e-6
    )
