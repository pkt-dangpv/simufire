"""The unequal-inventory gate varies only the declared fuel ownership."""

from __future__ import annotations

import pytest

from scripts.simulation import run_g3_fuel_ownership_gate as gate


def test_four_controls_keep_physics_and_geometry_fixed() -> None:
    cases = {name: gate.case_data(name) for name in gate.CASE_ENERGY_MJ}
    assert len(cases) == 4
    common = cases["room_only_3"]
    for name, case in cases.items():
        assert case["template"] == common["template"]
        assert case["engine_overrides"] == common["engine_overrides"]
        assert case["duration_s"] == common["duration_s"] == 90.0
        assert case["ignition_room_id"] == common["ignition_room_id"] == 0
        room = case["room_overrides"][0]
        room_mj, object_mj = gate.CASE_ENERGY_MJ[name]
        assert room["fuel_energy_MJ"] == room_mj
        assert room["max_hrr_kw"] == (100.0 if room_mj > 0 else 0.0)
        if object_mj is None:
            assert room["fuel_objects"] == []
        else:
            assert len(room["fuel_objects"]) == 1
            obj = room["fuel_objects"][0]
            assert obj["fuel_energy_MJ"] == obj["remaining_fuel_MJ"] == object_mj
            assert obj["max_hrr_kw"] == 100.0


def test_unknown_control_fails_closed() -> None:
    with pytest.raises(ValueError, match="unknown G3 ownership control"):
        gate.case_data("unknown")
