"""Offline scope/anchors; native ownership proof is run by the safe launcher."""

import re

from scripts.verify_fp_furniture_owner import FIXTURE, MUTATIONS, OVERVIEW, ROOT


def body(name):
    text = (ROOT / OVERVIEW).read_text(encoding="utf-8")
    return re.split(r"\n(?=\S)", text.split(f"func {name}(", 1)[1], maxsplit=1)[0]


def test_default_single_owner_and_guard_precedes_throttle():
    text = (ROOT / OVERVIEW).read_text(encoding="utf-8")
    assert "@export var show_fuel_objects_in_first_person: bool = false" in text
    method = body("_should_update_fuel_objects_this_pass")
    assert "if not _first_person_overlay:\n\t\treturn true" in method
    assert "if not show_fuel_objects_in_first_person:\n\t\treturn false" in method
    assert method.index("if not show_fuel_objects_in_first_person") < method.index("Time.get_ticks_msec()")


def test_visibility_is_consistent_on_entry_and_refresh():
    policy = "not _first_person_overlay or show_fuel_objects_in_first_person"
    assert policy in body("_apply_overlay_visibility")
    assert policy in body("_sync_room_fuel_objects_3d_visibility")
    assert "_apply_overlay_visibility()" in body("set_active")


def test_native_control_covers_round_trip_resources_interaction_and_clock():
    text = (ROOT / FIXTURE).read_text(encoding="utf-8")
    for label in ("all 39 logical furniture objects retained", "single visible furniture owner",
                  "FP nodes meshes materials and colliders retained",
                  "hidden overview does not normalize furniture", "3D still normalizes furniture",
                  "FP opening interaction retained", "Play keeps physical clock"):
        assert label in text
    assert "Scene.instantiate()" in text
    assert "_snapshot(child)" in text
    assert "_apply_opening_fraction(0, target)" in text


def test_safe_runner_and_native_mutation_anchors():
    text = (ROOT / "scripts/verify_fp_furniture_owner.py").read_text(encoding="utf-8")
    assert "prepare_environment(work)" in text
    assert "godot_monitored_launch.run(" in text
    assert '"SCRIPT ERROR", "Parse Error", "ERROR:"' in text
    assert "hashes() != sources" in text
    fixture = (ROOT / FIXTURE).read_text(encoding="utf-8")
    assert len(MUTATIONS) == 5
    for path, old, new, defect, expected in MUTATIONS.values():
        assert (ROOT / path).read_text(encoding="utf-8").count(old) == 1
        assert old != new and defect and expected in fixture


def test_product_contract_replaces_duplication_with_default_opt_in_and_restore():
    text = (ROOT / "tools/validate_furniture_runtime.gd").read_text(encoding="utf-8")
    assert '"Furniture hidden in first-person overlay"' not in text
    for label in ("Duplicate furniture enabled by default",
                  "Duplicate furniture visible in first-person overlay",
                  "Hidden duplicate still refreshes", "Explicit standalone furniture opt-in lost",
                  "Furniture not restored outside FP", "Furniture refresh not restored outside FP"):
        assert label in text
