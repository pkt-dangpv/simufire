#!/usr/bin/env python3
"""G3-0 topology controls under the existing monitored baseline runner.

These are diagnostic controls, not a validation against measured CO or a
proposal to enable zonal FED. They leave sim/core and sim/fire unchanged.
"""

from __future__ import annotations

import copy
import csv
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_fuel_baseline as baseline


CASES = (
    "door_closed",
    "door_open",
    "door_then_window",
    "two_storey_open",
)
SAMPLE_TIMES_S = (0.0, 30.0, 60.0, 90.0)


def case_data(name: str) -> dict:
    if name not in CASES:
        raise ValueError(f"unknown G3 topology control {name}")
    data = copy.deepcopy(baseline.case_data("sofa_mirrored"))
    data["engine_overrides"].update({
        "interior_transport_enabled": True,
        "two_zone_opening_flow_enabled": True,
    })
    if name == "two_storey_open":
        data["template"] = "two_storey_house"
        data["watch_room_ids"] = [0, 1, 2, 6, 7]
    else:
        data["watch_room_ids"] = [0, 1]
        # Keep the salon-pasillo path as the only interior route.
        data["opening_overrides"] = [
            {"a": a, "b": 1, "type": "door", "open_fraction": 0.0}
            for a in (4, 2, 3, 5)
        ]
        if name != "door_open":
            data["opening_overrides"].append(
                {"a": 0, "b": 1, "type": "door", "open_fraction": 0.0}
            )
        if name == "door_then_window":
            data["opening_events"] = [
                {"time_s": 30.0, "a": 0, "b": 1, "type": "door", "action": "open"},
                {"time_s": 60.0, "a": 0, "b": -1, "type": "window", "action": "open"},
            ]
    return data


def topology_metrics(out_dir: Path) -> dict:
    path = out_dir / "sim_log.csv"
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    by_room: dict[int, list[dict]] = {}
    fields = (
        "time_s", "co_kg", "co_generated_kg_total", "co_net_transport_kg_total",
        "co_exterior_removed_kg_total", "co_ppm", "co_upper_ppm",
        "co_lower_ppm", "smoke_kg", "fuel_consumed_MJ_total", "hrr_kw",
    )
    for row in rows:
        room_id = int(row["room_id"])
        if any(row.get(field, "") == "" for field in fields):
            raise ValueError(f"{path}: incomplete row for room {room_id}")
        if any(not math.isfinite(float(row[field])) for field in fields):
            raise ValueError(f"{path}: non-finite row for room {room_id}")
        by_room.setdefault(room_id, []).append(row)
    if not by_room or 0 not in by_room:
        raise ValueError(f"{path}: missing source room")
    samples = {}
    for room_id, room_rows in sorted(by_room.items()):
        previous_time = -1.0
        for row in room_rows:
            current_time = float(row["time_s"])
            if current_time <= previous_time:
                raise ValueError(f"{path}: non-monotonic time in room {room_id}")
            previous_time = current_time
        chosen = []
        for target in SAMPLE_TIMES_S:
            row = min(room_rows, key=lambda item: abs(float(item["time_s"]) - target))
            if abs(float(row["time_s"]) - target) > 0.2:
                raise ValueError(f"{path}: room {room_id} missing sample near {target}")
            chosen.append({field: float(row[field]) for field in fields})
        samples[str(room_id)] = chosen
    final = [values[-1] for values in samples.values()]
    transit_path = out_dir / "species_inflight_snapshot.json"
    transit = json.loads(transit_path.read_text(encoding="utf-8"))
    if transit.get("schema_version") != "g3_species_inflight_v1":
        raise ValueError(f"{transit_path}: schema mismatch")
    pending_co = float(transit["pending_co_kg"])
    destination_co = float(transit["destination_inflight_co_kg"])
    if not math.isfinite(pending_co) or pending_co < 0.0:
        raise ValueError(f"{transit_path}: invalid pending CO")
    if abs(pending_co - destination_co) > 1e-9:
        raise ValueError(f"{transit_path}: parcel and destination CO ledgers disagree")
    generated = sum(row["co_generated_kg_total"] for row in final)
    inventory = sum(row["co_kg"] for row in final)
    exterior = sum(row["co_exterior_removed_kg_total"] for row in final)
    # CSV rounds each room to 1e-8 kg, so allow up to 2e-7 kg for 13 rooms.
    if abs(generated - inventory - exterior - pending_co) > 2e-7:
        raise ValueError(f"{out_dir}: global CO budget does not close with parcels")
    return {
        "sample_times_requested_s": list(SAMPLE_TIMES_S),
        "rooms": samples,
        "final_sum_co_inventory_kg": inventory,
        "final_sum_co_generated_kg": generated,
        "final_sum_co_exterior_removed_kg": exterior,
        "final_species_inflight": transit,
        "global_co_balance_residual_kg": generated - inventory - exterior - pending_co,
    }


def run() -> int:
    return baseline.run(
        case_scenarios={name: case_data(name) for name in CASES},
        output_label="g3_transport_topology_baseline",
        report_schema="g3_transport_topology_baseline_v1",
        case_extra_metrics=topology_metrics,
        capture_species_inflight=True,
    )


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 TOPOLOGY BASELINE FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
