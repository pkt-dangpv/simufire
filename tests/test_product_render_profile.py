"""Offline admission/arithmetic only: these tests do not prove real FPS."""

import copy
from pathlib import Path

import pytest

from scripts.profile_product_render import phase_summary

ROOT = Path(__file__).resolve().parents[1]


def phase(playing=False):
    frame = {"interval_us": 20000, "main_us": 5000, "physics_steps": 1,
             "draw_calls": 20, "render_cpu_ms": 2.0, "render_gpu_ms": 3.0,
             "render_setup_ms": 1.0}
    return {"frames": [copy.deepcopy(frame) for _ in range(400)],
            "physics_callbacks": [[5000, 4000, 1 / 60] for _ in range(480)] if playing else [],
            "window_visible": True, "window_minimized": False, "wall_s": 8.0,
            "sim_start_s": 0.0, "sim_end_s": 8.0 if playing else 0.0,
            "cache_before": {"hits": 0, "misses": 0}, "cache_after": {"hits": 1, "misses": 0}}


def test_real_frame_interval_units_and_physics_clock():
    data = phase(True)
    original = copy.deepcopy(data)
    result = phase_summary(data, True)
    assert result["mean_fps"] == 50
    assert result["frame_interval"]["median_ms"] == 20
    assert result["engine_step"]["median_ms"] == 4
    assert data == original


def test_view_only_callbacks_do_not_repeat_the_last_engine_cost():
    data = phase(True)
    for index, sample in enumerate(data["physics_callbacks"]):
        sample.append(index % 5 == 4)
        if not sample[3]:
            sample[1] = 0
    result = phase_summary(data, True)
    assert result["engine_dispatches"] == 96
    assert result["engine_step"]["calls"] == 96
    assert result["engine_step"]["mean_ms"] == 4
    assert result["main_callback"]["calls"] == 480


@pytest.mark.parametrize("defect", ["minimized", "hidden", "no_draw", "short", "clock", "zero_interval"])
def test_non_rendered_or_inconsistent_phases_are_rejected(defect):
    data = phase()
    if defect == "minimized":
        data["window_minimized"] = True
    elif defect == "hidden":
        data["window_visible"] = False
    elif defect == "no_draw":
        for f in data["frames"]:
            f["draw_calls"] = 0
    elif defect == "short":
        data["wall_s"] = 1
    elif defect == "clock":
        data["sim_end_s"] = 1
    else:
        data["frames"][0]["interval_us"] = 0
    with pytest.raises(ValueError):
        phase_summary(data, False)


def test_unsupported_gpu_timer_is_unknown_not_zero_cost():
    data = phase()
    for f in data["frames"]:
        f["render_gpu_ms"] = 0
    assert phase_summary(data, False)["render_gpu_ms"] is None


def test_diagnostic_calls_real_main_once_and_keeps_quality_and_rates():
    text = (ROOT / "tests/fixtures/product_render_profile.gd").read_text(encoding="utf-8")
    assert text.count("main._physics_process(delta)") == 1
    assert "main.set_physics_process(false)" in text
    assert "main.engine.step(" not in text
    assert "Engine.physics_ticks_per_second =" not in text
    assert "Engine.max_physics_steps_per_frame =" not in text
    assert "ProjectSettings.set_setting(" not in text
    assert "RenderingServer.frame_post_draw.connect(" in text
    assert 'await _measure("paused_after")' in text


def test_launcher_has_real_display_safe_monitor_external_runtime():
    text = (ROOT / "scripts/profile_product_render.py").read_text(encoding="utf-8")
    assert "godot_monitored_launch.run(" in text
    assert "prepare_environment(work)" in text
    assert '"--headless"' not in text
    assert "args.options.write" not in text
