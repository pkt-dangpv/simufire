"""Diagnostic scope and counterfactual identity; native results are separate."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def test_shape_probe_is_exact_parent_method_plus_only_two_size_guards():
    original = read("view/fp/FirstPersonController.gd")
    start = original.index("func _update_opening_panel(index: int) -> void:")
    end = original.index("\n\nfunc _update_smoke_light_attenuation()", start)
    parent = original[start:end].strip()
    probe = read("tests/fixtures/fp_shape_guard_probe.gd")
    body = probe[probe.index("func _update_opening_panel(index: int) -> void:"):].strip()
    assert body.replace("if window_box_shape != null and window_box_shape.size != size:",
                        "if window_box_shape != null:").replace(
        "if box_shape != null and box_shape.size != size:", "if box_shape != null:") == parent
    assert body != parent


def test_shape_clock_uses_180_real_main_ticks_abba_and_checks_engine_identity():
    text = read("tests/fixtures/fp_shape_clock_profile.gd")
    assert text.count("main._physics_process(delta)") == 1
    assert "main.engine.step(" not in text
    assert "main.set_physics_process(false)" in text
    assert '["control0", "guarded0", "guarded1", "control1"]' in text
    assert "const TICKS: int = 180" in text
    assert "counterfactual changed final engine state" in text
    assert "physics_monitor_cached_us" in text
    assert "fp.set_script(Guard)" in text
    assert text.index("fp.set_script(Guard)") < text.index("root.add_child(main)")
    assert "export changed:" in text


def test_geometry_probe_separates_actual_calls_guard_and_positive_control():
    text = read("tests/fixtures/fp_opening_geometry_profile.gd")
    assert "fp._sync_opening_panels()" in text
    assert '["actual_sync", "same_size_writes", "guarded_same_size"]' in text
    assert 'item["resource"].size != item["size"]' in text
    assert "positive size control did not change geometry" in text
    assert "diagnosis changed engine state" in text
    assert '"gpu_measured": false' in text
    assert "Overlap.read(main)" in text


def test_furniture_freeze_is_diagnostic_and_not_a_silent_product_change():
    text = read("tests/fixtures/fp_furniture_freeze_probe.gd")
    assert "var diagnostic_freeze_furniture: bool = false" in text
    assert "super._update_fp_furniture_visuals()" in text
    assert "NOT a proposed production fix or quality parity" in text
    for path in ("Main.gd", "scenes/SimulationScene.tscn"):
        assert "fp_furniture_freeze_probe" not in read(path)
        assert "fp_shape_guard_probe" not in read(path)


def test_real_render_counterfactuals_are_named_disclosed_and_errors_still_reject():
    fixture = read("tests/fixtures/product_render_profile.gd")
    assert '"quality_changed": hide_minimap or freeze_fp_furniture or hide_overview_furniture' in fixture
    assert "Overlap.read(main)" in fixture
    assert "show_fuel_objects_in_first_person = false" in fixture
    assert "main.first_person_controller.diagnostic_freeze_furniture = true" in fixture
    assert fixture.index('await _measure("paused_before")') < fixture.index(
        "main.first_person_controller.diagnostic_freeze_furniture = true")
    runner = read("scripts/profile_product_render.py")
    assert '"SCRIPT ERROR", "Parse Error", "ERROR:"' in runner
    assert "overview furniture control requires FP and no other intervention" in runner


def test_overlap_counts_same_ids_world_position_and_visibility_for_both_owners():
    text = read("tests/fixtures/product_furniture_overlap.gd")
    assert "if not overview_nodes.has(object_id):" in text
    assert "a.global_position.is_equal_approx(b.global_position)" in text
    assert "a.is_visible_in_tree()" in text and "b.is_visible_in_tree()" in text
