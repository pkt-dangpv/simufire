"""Product homes are independent of frozen scientific builders and fixtures."""
import hashlib
import json
import re
from pathlib import Path

import pytest

from scripts.simulation.audit_playable_homes import audit, shared_side

ROOT = Path(__file__).resolve().parents[1]
HOMES = sorted((ROOT / "scenarios/playable").glob("preset_*.json"))


@pytest.mark.parametrize("path", HOMES, ids=lambda p: p.stem)
def test_playable_topology_and_door_envelopes(path):
    assert audit(json.loads(path.read_text(encoding="utf-8"))) == []


def test_ten_homes_are_available():
    assert len(HOMES) == 10


@pytest.mark.parametrize("path", HOMES, ids=lambda p: p.stem)
def test_furnishing_adds_no_combustion_inventory(path):
    product = json.loads(path.read_text(encoding="utf-8"))
    historical = json.loads((ROOT / "scenarios" / path.name).read_text(encoding="utf-8"))
    old_rooms = {r["id"]: r for r in historical["rooms_data"]}
    for room in product["rooms_data"]:
        assert room["visual_furniture_fill"] is True
        assert room["fuel_objects"] == old_rooms[room["id"]]["fuel_objects"]
        assert room["fuel_energy_MJ"] == old_rooms[room["id"]]["fuel_energy_MJ"]
        assert room["max_hrr_kw"] == old_rooms[room["id"]]["max_hrr_kw"]
    assert not product.get("experimental_physics_authorization")


def test_product_route_never_uses_the_scientific_builder():
    source = (ROOT / "sim/templates/BuildingTemplate.gd").read_text(encoding="utf-8")
    body = re.search(r"func create_product_preset\(.*?(?=\nfunc )", source, re.S)[0]
    assert "create_by_name(" not in body
    assert "res://scenarios/playable/preset_%s.json" in body
    assert "typeof(parsed) != TYPE_DICTIONARY" in body
    assert "return {}" in body  # no silent fallback to a scientific house
    exporter = (ROOT / "tools/export_presets_to_scenarios.gd").read_text(encoding="utf-8")
    assert 'const OUT_DIR := "res://scenarios/playable"' in exporter


def test_historical_sources_are_pinned():
    pins = json.loads((ROOT / "tests/fixtures/playable_homes_historical_pins.json").read_text())
    for path, digest in pins["files"].items():
        source = (ROOT / path).read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.sha256(source).hexdigest() == digest, path
    source = (ROOT / "sim/templates/BuildingTemplate.gd").read_text(encoding="utf-8")
    functions = re.findall(r"^func (\w+).*?(?=^func |\Z)", source, re.M | re.S)
    for name in functions:
        if name == "create_product_preset":
            continue
        body = re.search(r"^func " + name + r"\b.*?(?=^func |\Z)", source, re.M | re.S)[0]
        assert hashlib.sha256(body.encode()).hexdigest() == pins["functions"][name], name


def test_the_data_auditor_rejects_a_door_without_a_shared_wall():
    data = json.loads((ROOT / "scenarios/playable/preset_row_house_ground_floor.json").read_text())
    data["openings_data"][0]["b"] = 6
    assert any("no shared wall" in error for error in audit(data))


def test_the_data_auditor_rejects_an_exterior_door_in_a_partition():
    data = json.loads((ROOT / "scenarios/playable/preset_ranch_family_house.json").read_text())
    data["openings_data"][9]["a"] = 3
    assert any("exterior opening faces" in error for error in audit(data))


def test_the_data_auditor_rejects_a_missing_wall_and_conflicting_sweeps():
    data = json.loads((ROOT / "scenarios/playable/preset_two_bed_apartment.json").read_text())
    for op in data["openings_data"]:
        op["wall"] = "" if op["b"] != -1 else op["wall"]
        op["swing_direction"] = "in"
    errors = audit(data)
    assert any("inconsistent wall" in error for error in errors)
    assert any("overlapping sweep" in error for error in errors)


def test_the_data_auditor_rejects_a_shaft_larger_than_the_floor():
    data = json.loads((ROOT / "scenarios/playable/preset_two_storey_house.json").read_text())
    next(o for o in data["openings_data"] if o.get("is_vertical"))["height_m"] = 10
    assert any("shaft larger" in error for error in audit(data))


def test_the_two_storey_staircase_has_matching_switchback_and_access():
    data = json.loads((ROOT / "scenarios/playable/preset_two_storey_house.json").read_text())
    rooms = {r["id"]: r for r in data["rooms_data"]}
    for room_id in (2, 6):
        assert rooms[room_id]["stair_turn_mode"] == "switchback"
        assert rooms[room_id]["stair_turn_degrees"] == 180
        assert rooms[room_id]["stair_flight_count"] == 2
    accesses = [o for o in data["openings_data"] if o["type"] == "hole" and not o.get("is_vertical")]
    assert [o["offset_m"] for o in accesses] == [0.12, 0.12]


def test_shared_side_does_not_treat_a_corner_as_a_door_wall():
    assert shared_side({"x": 0, "y": 0, "w": 1, "h": 1},
                       {"x": 1, "y": 1, "w": 1, "h": 1}) is None
