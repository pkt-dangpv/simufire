"""Timing arithmetic and diagnostic isolation; does not launch Godot."""

from pathlib import Path

import pytest

from scripts.profile_product_cpu import summary

ROOT = Path(__file__).resolve().parents[1]


def test_timing_units_and_nearest_rank_percentile():
    values = list(range(1000, 21000, 1000))
    before = values.copy()
    assert summary(values) == {"calls": 20, "median_ms": 10.5,
                              "p95_ms": 19., "max_ms": 20., "mean_ms": 10.5}
    assert values == before


@pytest.mark.parametrize("values", [[], [-1], [True], [float("nan")], [float("inf")]])
def test_invalid_samples_are_not_accepted(values):
    with pytest.raises(ValueError):
        summary(values)


def test_diagnostic_calls_real_scene_and_does_not_reimplement_physics():
    text = (ROOT / "tests/fixtures/product_cpu_profile.gd").read_text(encoding="utf-8")
    assert 'preload("res://scenes/SimulationScene.tscn")' in text
    assert "main._physics_process(DT)" in text
    assert "main.set_physics_process(false)" in text
    assert "main.engine.step(" not in text
    assert '"rendered_fps_measured": false' in text
    assert "frozen visual probes changed engine state" in text
    assert "paused window action advanced physics" in text


def test_launcher_uses_existing_monitor_external_runtime_and_no_user_write():
    text = (ROOT / "scripts/profile_product_cpu.py").read_text(encoding="utf-8")
    assert "godot_monitored_launch.run(" in text
    assert "prepare_environment(work)" in text
    assert "args.options.write" not in text
    assert '"--headless"' in text
    assert '"SCRIPT ERROR"' in text


def test_layout_control_is_diagnostic_and_does_not_disable_product_furniture():
    text = (ROOT / "tests/fixtures/product_cpu_profile.gd").read_text(encoding="utf-8")
    assert "overview._update_room(int(room_id), false)" in text
    assert "Layout.normalize_room(overview.building" in text
    assert "overview.show_fuel_objects_3d = false" not in text
    assert "overview.furnish_empty_rooms = false" not in text


def test_fp_standalone_clock_probes_are_not_claimed_as_frame_budget():
    text = (ROOT / "tests/fixtures/product_cpu_profile.gd").read_text(encoding="utf-8")
    for label, method in (("fp_physics_callback_us", "fp._physics_process(DT)"),
                          ("fp_movement_us", "fp._apply_movement(DT)"),
                          ("fp_animation_us", "fp._animate_fp_fire(DT)"),
                          ("overview_frame_animation_us", "main.visualizer_3d._process(DT)")):
        assert f'_time("{label}", func(): {method})' in text
    assert 'info["standalone_probes_are_inclusive_not_frame_budget"] = true' in text
    assert "main.engine.step(" not in text
