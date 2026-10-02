"""Static and parser contracts for the G3-0 topology-only controls."""

from __future__ import annotations

import csv
import json
from pathlib import Path

import pytest

from scripts.simulation import run_g3_transport_baseline as topology


def test_simple_cases_vary_only_declared_opening_schedule() -> None:
    closed = topology.case_data("door_closed")
    opened = topology.case_data("door_open")
    staged = topology.case_data("door_then_window")
    assert {case["template"] for case in (closed, opened, staged)} == {"simple_house"}
    assert all(case["engine_overrides"] == closed["engine_overrides"] for case in (opened, staged))
    assert all(case["room_overrides"] == closed["room_overrides"] for case in (opened, staged))
    assert all(case["watch_room_ids"] == [0, 1] for case in (closed, opened, staged))
    assert closed["engine_overrides"]["fire_spread_enabled"] is False
    assert closed["engine_overrides"]["interior_transport_enabled"] is True
    for case in (closed, opened, staged):
        sealed = {(item["a"], item["b"]) for item in case["opening_overrides"]}
        assert {(4, 1), (2, 1), (3, 1), (5, 1)} <= sealed
    assert (0, 1) in {(item["a"], item["b"]) for item in closed["opening_overrides"]}
    assert (0, 1) not in {(item["a"], item["b"]) for item in opened["opening_overrides"]}
    assert staged["opening_overrides"] == closed["opening_overrides"]
    assert [(event["time_s"], event["type"]) for event in staged["opening_events"]] == [
        (30.0, "door"), (60.0, "window")
    ]


def test_multistorey_case_reuses_same_source_with_open_stair_path() -> None:
    simple = topology.case_data("door_open")
    stacked = topology.case_data("two_storey_open")
    assert stacked["template"] == "two_storey_house"
    assert stacked["room_overrides"] == simple["room_overrides"]
    assert stacked["engine_overrides"] == simple["engine_overrides"]
    assert stacked["watch_room_ids"] == [0, 1, 2, 6, 7]
    assert "opening_events" not in stacked


def test_unknown_case_rejected() -> None:
    with pytest.raises(ValueError, match="unknown G3 topology control"):
        topology.case_data("unlisted")


def test_topology_metrics_require_complete_monotonic_samples(tmp_path: Path) -> None:
    fields = (
        "time_s", "room_id", "co_kg", "co_generated_kg_total",
        "co_net_transport_kg_total", "co_exterior_removed_kg_total",
        "co_ppm", "co_upper_ppm", "co_lower_ppm", "smoke_kg",
        "fuel_consumed_MJ_total", "hrr_kw",
    )
    path = tmp_path / "sim_log.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for time_s in topology.SAMPLE_TIMES_S:
            for room_id in (0, 1):
                row = {field: 0.0 for field in fields}
                row.update({"time_s": time_s, "room_id": room_id, "co_kg": room_id + time_s / 100.0})
                if time_s == 90.0 and room_id == 0:
                    row["co_generated_kg_total"] = 2.8
                writer.writerow(row)
    transit_path = tmp_path / "species_inflight_snapshot.json"
    transit_path.write_text(json.dumps({
        "schema_version": "g3_species_inflight_v1",
        "pending_parcel_count": 0,
        "pending_co_kg": 0.0,
        "destination_inflight_co_kg": 0.0,
        "pending_smoke_kg": 0.0,
    }), encoding="utf-8")
    result = topology.topology_metrics(tmp_path)
    assert sorted(result["rooms"]) == ["0", "1"]
    assert result["rooms"]["1"][-1]["co_kg"] == 1.9
    assert result["final_sum_co_inventory_kg"] == pytest.approx(2.8)
    assert result["global_co_balance_residual_kg"] == pytest.approx(0.0)

    transit = json.loads(transit_path.read_text(encoding="utf-8"))
    transit["destination_inflight_co_kg"] = 0.01
    transit_path.write_text(json.dumps(transit), encoding="utf-8")
    with pytest.raises(ValueError, match="parcel and destination CO ledgers disagree"):
        topology.topology_metrics(tmp_path)
    transit["destination_inflight_co_kg"] = 0.0
    transit["pending_co_kg"] = 0.01
    transit_path.write_text(json.dumps(transit), encoding="utf-8")
    with pytest.raises(ValueError, match="parcel and destination CO ledgers disagree"):
        topology.topology_metrics(tmp_path)
    transit["destination_inflight_co_kg"] = 0.01
    transit_path.write_text(json.dumps(transit), encoding="utf-8")
    with pytest.raises(ValueError, match="global CO budget does not close"):
        topology.topology_metrics(tmp_path)
    transit["pending_co_kg"] = 0.0
    transit["destination_inflight_co_kg"] = 0.0
    transit_path.write_text(json.dumps(transit), encoding="utf-8")

    with path.open("a", encoding="utf-8") as handle:
        handle.write("90.0,1,0,0,0,0,0,0,0,0,0,0\n")
    with pytest.raises(ValueError, match="non-monotonic"):
        topology.topology_metrics(tmp_path)
