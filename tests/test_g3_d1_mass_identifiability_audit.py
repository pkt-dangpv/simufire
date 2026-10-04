"""Static diagnostic tests: no Godot, no inferred fuel mass."""

import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "g3_d1_audit", ROOT / "scripts/simulation/audit_g3_d1_mass_identifiability.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def test_declarations_cover_rooms_and_overrides_without_counting_other_ids():
    value = {
        "rooms_data": [{"id": 1, "fuel_objects": [{"id": "sofa"}]}],
        "room_overrides": [{"fuel_objects": [{"id": "panel"}]}],
        "template": "simple_house",
    }
    found = list(audit.declarations(value))
    assert {obj["id"] for _, obj in found} == {"sofa", "panel"}
    assert len(found) == 2  # no inferred objects from the named template


@pytest.mark.parametrize("bad", [None, {}, [None]])
def test_invalid_declarations_fail_explicitly(bad):
    with pytest.raises(ValueError):
        list(audit.declarations({"fuel_objects": bad}))


def test_field_presence_is_not_a_mass_conversion(tmp_path):
    path = tmp_path / "case.json"
    path.write_text(json.dumps({"fuel_objects": [{
        "id": "wood", "fuel_energy_MJ": 100,
        "heat_of_combustion_kj_kg": 17500,
    }]}), encoding="utf-8")
    report = audit.audit_paths([path], tmp_path)
    assert report["declared_object_count"] == 1
    assert report["field_presence_counts"]["initial_fuel_mass_kg"] == 0
    assert report["field_presence_counts"]["heat_of_combustion_basis"] == 0
    assert "inferred_mass_kg" not in report["files"][0]["objects"][0]


def test_content_change_is_detected_and_output_is_repeatable(tmp_path):
    path = tmp_path / "case.json"
    path.write_text('{"fuel_objects": []}', encoding="utf-8")
    before = audit.audit_paths([path], tmp_path)
    assert before == audit.audit_paths([path], tmp_path)
    path.write_text('{"fuel_objects": [{"id": "new"}]}', encoding="utf-8")
    after = audit.audit_paths([path], tmp_path)
    assert before["files"][0]["sha256_raw"] != after["files"][0]["sha256_raw"]
    assert after["declared_object_count"] == 1
