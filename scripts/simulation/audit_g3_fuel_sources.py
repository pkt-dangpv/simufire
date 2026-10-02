#!/usr/bin/env python3
"""Inventory declared room and object fuel sources without changing scenarios.

This is a static G3 diagnostic, not a combustion model. Equal room/object
totals are *not* proof that one mirrors the other, and a difference is *not*
proof of hidden fuel. Every positive source remains unclassified until its
provenance is recorded explicitly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SCENARIOS = ROOT / "scenarios"
ENERGY_TOL_MJ = 0.01
POWER_TOL_KW = 0.01


def _number(record: dict, field: str, where: str) -> float:
    raw = record.get(field, 0.0)
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        raise ValueError(f"{where}: {field} must be a nonnegative number")
    value = float(raw)
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{where}: {field} must be finite and nonnegative")
    return value


def _room_inventory(room: dict, scenario: str) -> dict:
    if not isinstance(room, dict):
        raise ValueError(f"{scenario}: room must be an object")
    room_id = room.get("id")
    if isinstance(room_id, bool) or not isinstance(room_id, int):
        raise ValueError(f"{scenario}: room id must be an integer")
    where = f"{scenario}: room {room_id}"
    room_mj = _number(room, "fuel_energy_MJ", where)
    room_kw = _number(room, "max_hrr_kw", where)
    raw_objects = room.get("fuel_objects", [])
    if not isinstance(raw_objects, list):
        raise ValueError(f"{where}: fuel_objects must be a list")

    objects = []
    seen_ids = set()
    for index, obj in enumerate(raw_objects):
        if not isinstance(obj, dict):
            raise ValueError(f"{where}: fuel object {index} must be an object")
        object_id = obj.get("id")
        if not isinstance(object_id, str) or not object_id:
            raise ValueError(f"{where}: fuel object {index} needs a nonempty id")
        if object_id in seen_ids:
            raise ValueError(f"{where}: duplicate fuel object id {object_id}")
        seen_ids.add(object_id)
        object_where = f"{where}: object {object_id}"
        declared_room_id = obj.get("room_id", room_id)
        if declared_room_id != room_id:
            raise ValueError(f"{object_where}: room_id does not match owner room")
        objects.append({
            "id": object_id,
            "kind": str(obj.get("kind", "")),
            "fuel_energy_MJ": _number(obj, "fuel_energy_MJ", object_where),
            "max_hrr_kw": _number(obj, "max_hrr_kw", object_where),
            "has_co_yield": "co_yield_kg_per_MJ" in obj,
            "has_co2_yield": "co2_yield_kg_per_MJ" in obj,
            "has_hcn_yield": "hcn_yield_kg_per_MJ" in obj,
        })

    object_mj = sum(obj["fuel_energy_MJ"] for obj in objects)
    object_kw = sum(obj["max_hrr_kw"] for obj in objects)
    if not objects:
        shape = "room_only_unattributed" if room_mj or room_kw else "empty_declared"
    elif not room_mj and not room_kw:
        shape = "objects_only"
    elif abs(room_mj - object_mj) <= ENERGY_TOL_MJ and abs(room_kw - object_kw) <= POWER_TOL_KW:
        shape = "both_equal_unclassified"
    else:
        shape = "both_mismatch_unclassified"
    return {
        "room_id": room_id,
        "room_name": str(room.get("name", "")),
        "declared_room_energy_MJ": room_mj,
        "declared_room_max_hrr_kw": room_kw,
        "object_energy_MJ": object_mj,
        "object_max_hrr_kw": object_kw,
        "energy_difference_MJ": room_mj - object_mj,
        "power_difference_kw": room_kw - object_kw,
        "object_count": len(objects),
        "shape": shape,
        "source_ownership": "unclassified" if room_mj or room_kw or objects else "none_declared",
        "objects": objects,
    }


def audit_directory(directory: Path) -> dict:
    paths = sorted(directory.glob("*.json"))
    if not paths:
        raise ValueError(f"{directory}: no scenario JSON files")
    scenarios = []
    for path in paths:
        raw = path.read_bytes()
        data = json.loads(raw)
        if not isinstance(data, dict) or not isinstance(data.get("rooms_data"), list):
            raise ValueError(f"{path}: expected rooms_data list")
        rooms = [_room_inventory(room, path.name) for room in data["rooms_data"]]
        room_ids = [room["room_id"] for room in rooms]
        if len(set(room_ids)) != len(room_ids):
            raise ValueError(f"{path}: duplicate room id")
        scenarios.append({
            "file": path.name,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "rooms": rooms,
        })
    all_rooms = [room for scenario in scenarios for room in scenario["rooms"]]
    presets = [scenario for scenario in scenarios if scenario["file"].startswith("preset_")]
    return {
        "schema": "g3_fuel_source_inventory_v1",
        "summary": {
            "scenario_count": len(scenarios),
            "room_count": len(all_rooms),
            "room_positive_energy_count": sum(room["declared_room_energy_MJ"] > 0 for room in all_rooms),
            "rooms_with_objects_count": sum(room["object_count"] > 0 for room in all_rooms),
            "rooms_energy_mismatch_count": sum(
                room["object_count"] > 0
                and abs(room["energy_difference_MJ"]) > ENERGY_TOL_MJ
                for room in all_rooms
            ),
            "rooms_shape_mismatch_count": sum(
                room["shape"] == "both_mismatch_unclassified" for room in all_rooms
            ),
            "preset_count": len(presets),
            "presets_without_objects_count": sum(
                all(room["object_count"] == 0 for room in scenario["rooms"])
                for scenario in presets
            ),
        },
        "scenarios": scenarios,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenarios", type=Path, default=DEFAULT_SCENARIOS)
    parser.add_argument("--json", action="store_true", help="Print complete deterministic JSON inventory")
    args = parser.parse_args()
    report = audit_directory(args.scenarios)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(json.dumps(report["summary"], ensure_ascii=False, sort_keys=True))
        for scenario in report["scenarios"]:
            for room in scenario["rooms"]:
                if room["shape"] == "both_mismatch_unclassified":
                    print(
                        f"{scenario['file']} room={room['room_id']} "
                        f"MJ={room['declared_room_energy_MJ']:g}/{room['object_energy_MJ']:g} "
                        f"kW={room['declared_room_max_hrr_kw']:g}/{room['object_max_hrr_kw']:g}"
                    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
