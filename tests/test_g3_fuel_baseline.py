"""G3 baseline controls are paired and fail before launching on low memory."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/simulation/run_g3_fuel_baseline.py"
spec = importlib.util.spec_from_file_location("g3_fuel_baseline", SCRIPT)
assert spec is not None and spec.loader is not None
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


def test_five_controls_change_only_the_declared_fuel_source() -> None:
    cases = {name: baseline.case_data(name) for name in baseline.CASES}
    room = {name: case["room_overrides"][0] for name, case in cases.items()}
    assert len(cases) == 5
    assert all(case["engine_overrides"] == cases["room_only"]["engine_overrides"] for case in cases.values())
    assert all(case["duration_s"] == baseline.DURATION_S for case in cases.values())
    assert room["room_only"]["fuel_energy_MJ"] == 200
    assert room["room_only"]["fuel_objects"] == []
    assert room["sofa_mirrored"]["fuel_energy_MJ"] == 200
    assert len(room["sofa_mirrored"]["fuel_objects"]) == 1
    assert room["sofa_plus_unignited_chair"]["fuel_energy_MJ"] == 200
    assert room["sofa_plus_unignited_chair"]["fuel_objects"][0] == room["sofa_mirrored"]["fuel_objects"][0]
    chair = room["sofa_plus_unignited_chair"]["fuel_objects"][1]
    assert chair["is_primary_ignition_source"] is False
    assert chair["ignition_temp_c"] == 2000
    assert room["sofa_objects_only"]["fuel_energy_MJ"] == 0
    assert len(room["sofa_objects_only"]["fuel_objects"]) == 1
    assert room["empty_ignition_room"]["fuel_energy_MJ"] == 0
    assert room["empty_ignition_room"]["fuel_objects"] == []


def test_unknown_control_fails_closed() -> None:
    with pytest.raises(ValueError, match="unknown G3 control"):
        baseline.case_data("not_a_control")


def test_low_memory_stops_before_creating_run_artifacts(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(baseline.run_scenario, "_find_godot", lambda: Path("fake_godot.exe"))
    monkeypatch.setattr(baseline.mutation_audit, "_godot_processes", lambda: [])
    monkeypatch.setattr(baseline, "available_gib", lambda: 5.84)
    with pytest.raises(RuntimeError, match="less than 6 GiB free"):
        baseline.run()


def _ledger_row(time_s: float, room_id: int = 0) -> dict:
    return {
        "schema_version": "g3_fuel_source_step_v2",
        "time_s": time_s, "room_id": room_id,
        "room_fuel_consumed_delta_MJ": 0.5,
        "explicit_object_burn_delta_MJ": 0.5,
        "proxy_burn_delta_MJ": 0.5,
        "nominal_explicit_co_from_burn_kg": 0.0002,
        "room_co_generated_delta_kg": 0.0003,
        "room_co_inventory_delta_kg": 0.0001,
        "room_co2_kg_delta": 0.0,
        "room_hcn_kg_delta": 0.0,
        "room_smoke_generated_kg_total_delta": 0.01,
        "room_smoke_kg_delta": 0.01,
        "room_o2_consumed_kg_total_all_delta": 0.02,
        "room_o2_consumed_fire_kg_total_delta": 0.02,
        "room_co_balance_residual_kg": 0.0,
        "room_smoke_balance_residual_kg": 0.0,
        "objects": [{"id": "sofa", "burn_MJ": 0.5, "hrr_after_kw": 50.0}],
    }


def test_ledger_sums_room_zero_without_counting_other_rooms(tmp_path: Path) -> None:
    path = tmp_path / "fuel_source_ledger.jsonl"
    rows = [_ledger_row(0.1), _ledger_row(0.1, room_id=1), _ledger_row(0.2)]
    path.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")
    result = baseline._room0_ledger_metrics(path)
    assert result["steps"] == 2
    assert result["room_fuel_consumed_MJ"] == 1.0
    assert result["room_co_generated_kg"] == pytest.approx(0.0006)
    assert result["smoke_generated_kg"] == pytest.approx(0.02)
    assert result["o2_consumed_all_kg"] == pytest.approx(0.04)
    assert result["max_abs_smoke_balance_residual_kg"] == 0.0
    assert result["object_burn_MJ"] == {"sofa": 1.0}
    assert result["object_max_hrr_kw"] == {"sofa": 50.0}
    assert result["object_max_abs_burn_step_MJ"] == {"sofa": 0.5}
    assert result["object_step_count"] == {"sofa": 2}


def test_ledger_rejects_nonmonotonic_room_time(tmp_path: Path) -> None:
    path = tmp_path / "fuel_source_ledger.jsonl"
    path.write_text(
        "\n".join(json.dumps(_ledger_row(0.1)) for _ in range(2)), encoding="utf-8"
    )
    with pytest.raises(ValueError, match="non-monotonic"):
        baseline._room0_ledger_metrics(path)


def test_ledger_does_not_hide_offsetting_object_burn(tmp_path: Path) -> None:
    path = tmp_path / "fuel_source_ledger.jsonl"
    first = _ledger_row(0.1)
    second = _ledger_row(0.2)
    second["objects"][0]["burn_MJ"] = -0.5
    path.write_text(
        "\n".join(json.dumps(row) for row in (first, second)), encoding="utf-8"
    )
    result = baseline._room0_ledger_metrics(path)
    assert result["object_burn_MJ"]["sofa"] == 0.0
    assert result["object_max_abs_burn_step_MJ"]["sofa"] == 0.5
