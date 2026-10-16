"""Offline structural checks. Native dispatch control and real FPS are separate."""

import re

from scripts.verify_fp_live_charts import FIXTURE, MUTATIONS, ROOT


def body(name):
    text = (ROOT / "Main.gd").read_text(encoding="utf-8")
    after = text.split(f"func {name}(", 1)[1]
    return re.split(r"\n(?=\S)", after, maxsplit=1)[0].rstrip()


def test_fp_guard_precedes_export_accumulation_and_chart_sampling():
    text = body("_sample_live_charts")
    guard = "if first_person_enabled or _live_overlay == null or engine == null:"
    assert guard in text
    assert text.index(guard) < text.index("_live_sample_accum_s += delta")
    assert text.index(guard) < text.index("engine.get_state()")
    assert guard + "\n\t\treturn" in text


def test_shared_view_sync_covers_both_view_switches():
    assert "_sync_live_charts()" in body("_sync_view_mode")
    for method in ("_set_3d_view_enabled", "_set_first_person_enabled"):
        assert "_sync_view_mode()" in body(method)
    assert "first_person_enabled = false" in body("_set_3d_view_enabled")


def test_chart_policy_preserves_preference_without_recursive_button_signals():
    text = body("_sync_live_charts")
    assert "_live_charts_requested_visible and not first_person_enabled" in text
    assert "Node.PROCESS_MODE_DISABLED" in text
    assert "Node.PROCESS_MODE_INHERIT" in text
    assert "_live_charts_button.visible = not first_person_enabled" in text
    assert "set_pressed_no_signal(_live_charts_requested_visible)" in text
    assert "_live_sample_accum_s = 0.0" in text
    assert "_live_charts_requested_visible =" not in text
    toggle = body("_on_live_charts_toggled")
    assert "_live_charts_requested_visible = pressed" in toggle
    assert "_sync_live_charts()" in toggle
    assert "_sync_live_charts()" in body("_setup_live_charts")


def test_main_simulation_dispatch_steps_once_per_reference_step():
    text = body("_physics_process")
    assert text.startswith(
        "delta: float) -> void:\n"
        "\tif _engine_threaded:\n\t\t_physics_process_threaded(delta)\n\t\treturn\n"
        "\tif playback_paused or engine == null:\n\t\treturn\n")
    # With the engine on a worker thread: same accumulation, one step per
    # dispatch, charts sampled with the wall time of that step when it ends.
    threaded = body("_physics_process_threaded")
    assert threaded.count("WorkerThreadPool.add_task(") == 1
    assert "_sim_step_accum_s += delta * engine.time_scale" in threaded
    assert "_sim_step_accum_real_s += delta" in threaded
    assert "\tengine.step(step_delta)\n" in body("_run_engine_task")
    assert "\t_sample_live_charts(_engine_task_elapsed_real_s)\n" in body("_finish_engine_task")
    # Engine receives accumulated simulated time divided by the current speed;
    # charts retain the actual elapsed wall time across speed changes.
    assert text.count("engine.step(") == 1
    assert "\tengine.step(step_delta)\n" in text
    assert "\t_sample_live_charts(elapsed_real_s)\n" in text
    assert "_sim_step_accum_s += delta * engine.time_scale" in text
    assert "_sim_step_accum_real_s += delta" in text
    main = (ROOT / "Main.gd").read_text(encoding="utf-8")
    assert "const SIM_STEP_S: float = 1.0 / 12.0\n" in main
    due = body("_is_sim_step_due")
    assert "if engine.sim_fixed_dt > 0.0:\n\t\treturn true" in due
    assert "_sim_step_accum_s + ahead_s * engine.time_scale >= SIM_STEP_S - SIM_STEP_EPSILON_S" in due


def test_native_control_uses_real_chart_and_inherited_dispatch_not_physics_evidence():
    text = (ROOT / FIXTURE).read_text(encoding="utf-8")
    assert len(re.findall(r"^\tcheck\(", text, re.MULTILINE)) == 26
    assert 'extends "res://Main.gd"' in text
    assert "main.LiveChartsOverlayScene.instantiate()" in text
    assert "main._physics_process(1.0 / 60.0)" in text
    for label in ("no chart state exports in FP", "no hidden history growth in FP",
                  "child processing suspended in FP", "restore user hidden preference",
                  "one engine dispatch per reference step in FP", "no catch-up sample on return"):
        assert label in text


def test_native_launcher_uses_unmodified_monitor_and_external_environment():
    text = (ROOT / "scripts/verify_fp_live_charts.py").read_text(encoding="utf-8")
    assert "prepare_environment(work)" in text
    assert "godot_monitored_launch.run(" in text
    assert "result.faults or result.preexisting" in text
    assert '"SCRIPT ERROR", "Parse Error", "ERROR:"' in text
    assert 'payload["checks"] != 26' in text
    assert "work.is_relative_to(ROOT)" in text


def test_mutants_have_unique_real_anchors_and_named_native_failures():
    fixture = (ROOT / FIXTURE).read_text(encoding="utf-8")
    assert len(MUTATIONS) == 5
    for path, old, new, defect, expected in MUTATIONS.values():
        assert (ROOT / path).read_text(encoding="utf-8").count(old) == 1
        assert old != new and defect and expected in fixture
