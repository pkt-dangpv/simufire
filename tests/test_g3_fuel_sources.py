"""Static G3 fuel-source inventory must fail closed and preserve ambiguity."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/simulation/audit_g3_fuel_sources.py"
spec = importlib.util.spec_from_file_location("audit_g3_fuel_sources", SCRIPT)
assert spec is not None and spec.loader is not None
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def _scenario(tmp_path: Path, rooms: list[dict]) -> Path:
    path = tmp_path / "sample.json"
    path.write_text(json.dumps({"rooms_data": rooms}), encoding="utf-8")
    return path


def _room(room_id: int, energy: float, power: float, objects: list[dict]) -> dict:
    return {
        "id": room_id, "name": f"Room {room_id}",
        "fuel_energy_MJ": energy, "max_hrr_kw": power,
        "fuel_objects": objects,
    }


def _object(object_id: str, energy: float, power: float, room_id: int = 0) -> dict:
    return {
        "id": object_id, "room_id": room_id,
        "fuel_energy_MJ": energy, "max_hrr_kw": power,
    }


def test_distributed_inventory_is_pinned_and_does_not_infer_hidden_fuel() -> None:
    report = audit.audit_directory(ROOT / "scenarios")
    assert report["summary"] == {
        "scenario_count": 14,
        "room_count": 109,
        "room_positive_energy_count": 107,
        "rooms_with_objects_count": 36,
        "rooms_energy_mismatch_count": 23,
        "rooms_shape_mismatch_count": 23,
        "preset_count": 10,
        "presets_without_objects_count": 7,
    }
    apartment = next(s for s in report["scenarios"] if s["file"] == "compact_apartment_reference.json")
    salon = next(r for r in apartment["rooms"] if r["room_name"] == "Salon cocina")
    assert salon["declared_room_energy_MJ"] == 4300
    assert salon["object_energy_MJ"] == 2620
    assert salon["source_ownership"] == "unclassified"
    assert salon["shape"] == "both_mismatch_unclassified"
    objects = [
        obj
        for scenario in report["scenarios"]
        for room in scenario["rooms"]
        for obj in room["objects"]
    ]
    assert len(objects) == 107
    assert sum(obj["has_co_yield"] for obj in objects) == 107
    assert sum(obj["has_co2_yield"] for obj in objects) == 0
    assert sum(obj["has_hcn_yield"] for obj in objects) == 0


def test_equal_totals_are_not_treated_as_proven_mirror(tmp_path: Path) -> None:
    _scenario(tmp_path, [_room(0, 100, 50, [_object("sofa", 100, 50)])])
    room = audit.audit_directory(tmp_path)["scenarios"][0]["rooms"][0]
    assert room["shape"] == "both_equal_unclassified"
    assert room["source_ownership"] == "unclassified"


def test_empty_room_and_cold_extra_object_are_distinct(tmp_path: Path) -> None:
    _scenario(tmp_path, [
        _room(0, 0, 0, []),
        _room(1, 0, 0, [_object("sofa", 100, 50, 1), _object("chair", 20, 10, 1)]),
    ])
    rooms = audit.audit_directory(tmp_path)["scenarios"][0]["rooms"]
    assert rooms[0]["shape"] == "empty_declared"
    assert rooms[1]["shape"] == "objects_only"
    assert rooms[1]["object_energy_MJ"] == 120


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), -1, "100", True])
def test_bad_fuel_values_fail_closed(tmp_path: Path, bad: object) -> None:
    _scenario(tmp_path, [_room(0, 0, 0, [_object("sofa", bad, 50)])])
    with pytest.raises(ValueError, match="fuel_energy_MJ"):
        audit.audit_directory(tmp_path)


def test_object_room_mismatch_fails_closed(tmp_path: Path) -> None:
    _scenario(tmp_path, [_room(0, 0, 0, [_object("sofa", 100, 50, 1)])])
    with pytest.raises(ValueError, match="room_id does not match"):
        audit.audit_directory(tmp_path)


def test_duplicate_room_id_fails_closed(tmp_path: Path) -> None:
    _scenario(tmp_path, [_room(0, 0, 0, []), _room(0, 0, 0, [])])
    with pytest.raises(ValueError, match="duplicate room id"):
        audit.audit_directory(tmp_path)
