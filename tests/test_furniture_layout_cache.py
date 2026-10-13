"""Offline admission checks; native control/mutants are separate evidence."""

from pathlib import Path

from scripts.verify_furniture_layout_cache import MUTATIONS, ROOT, FIXTURE


def test_each_mutant_has_one_real_anchor_and_named_native_assertion():
    fixture = (ROOT / FIXTURE).read_text(encoding="utf-8")
    assert len(MUTATIONS) == 19
    for path, old, new, defect, expected in MUTATIONS.values():
        assert (ROOT / path).read_text(encoding="utf-8").count(old) == 1
        assert old != new and defect
        # Identity labels are assembled by the oracle helper, not one literal.
        assert expected in fixture or (
            expected.startswith("identity ") and expected.removeprefix("identity ") in fixture
            and '"identity " + label' in fixture)


def test_spec_cache_does_not_freeze_real_objects_or_replace_uncached_oracle():
    text = (ROOT / "view/furniture/FurnitureVisualLayout.gd").read_text(encoding="utf-8")
    assert 'raw_objects[entry["indices"][index]].duplicate(true)' in text
    assert 'current.append_array(entry["props"].duplicate(true))' in text
    assert "var_to_bytes([rect, furnish_empty, room_metadata, geometry])" in text
    assert "for cache: Dictionary in [_room_cache, _spec_cache]:" in text
    oracle = text.split("static func normalize_room_uncached(", 1)[1].split("\n\n", 1)[0]
    assert "_prepare_specs(" in oracle and "_prepare_specs_cached(" not in oracle


def test_dynamic_exclusions_are_not_placement_reads():
    sources = "\n".join((ROOT / p).read_text(encoding="utf-8") for p in (
        "view/furniture/FurnitureRoomLayout.gd", "view/furniture/FurnitureRoomGrammar.gd",
        "view/3d/furniture/FurnitureVisualClassifier.gd"))
    for key in ("state", "hrr_kw", "remaining_fuel_MJ", "temp_c", "surface_temp_c", "temperature_c",
                "incident_heat_flux_kw_m2", "t_ignition_s", "is_primary_ignition_source"):
        assert f'get("{key}"' not in sources
        assert f'["{key}"]' not in sources


def test_placement_algorithm_remains_the_published_uncached_oracle():
    import hashlib
    path = ROOT / "view/furniture/FurnitureRoomLayout.gd"
    assert hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == (
        "1eaca2d11c52a267eb72a00b971ec1393796242667cba3d4cc05564a1ce91f60")


def test_hidden_overview_furniture_is_not_normalized():
    text = (ROOT / "view/3d/Visualizer3D.gd").read_text(encoding="utf-8")
    body = text.split("func _update_room_fuel_objects_3d(", 1)[1].split("\n\nfunc ", 1)[0]
    assert body.index("if not show_fuel_objects_3d:") < body.index("FurnitureVisualLayout.normalize_room(")
    assert body.index("if _first_person_overlay and not show_fuel_objects_in_first_person:") < body.index(
        "FurnitureVisualLayout.normalize_room(")
