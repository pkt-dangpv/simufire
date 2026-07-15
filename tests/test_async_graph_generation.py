"""Structural contracts for async graph generation and exit behavior."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
MAIN = (ROOT / "Main.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestAsyncGraphBackend(unittest.TestCase):
    def test_engine_tracks_async_process(self):
        self.assertIn("var _graph_gen_pid: int = -1", ENGINE)
        poll = _function(ENGINE, "poll_graph_generation")
        self.assertIn("OS.is_process_running(_graph_gen_pid)", poll)
        self.assertIn("OS.get_process_exit_code(_graph_gen_pid)", poll)

    def test_manual_stop_uses_nonblocking_mode(self):
        stop = _function(ENGINE, "stop_and_generate_graphs")
        self.assertIn("return _finish_and_launch_graphs(details, graphs_root, false)", stop)
        self.assertNotIn("graphs_root, true", stop)

    def test_async_launcher_uses_create_process(self):
        launch = _function(ENGINE, "_launch_graph_generator")
        self.assertIn("_create_python_process(args)", launch)
        self.assertNotIn("OS.execute", launch)

    def test_stale_latest_marker_is_removed_before_launch(self):
        launch = _function(ENGINE, "_launch_graph_generator")
        self.assertIn("DirAccess.remove_absolute(latest_path)", launch)
        self.assertLess(
            launch.index("DirAccess.remove_absolute(latest_path)"),
            launch.index("_create_python_process(args)"),
        )

    def test_completion_requires_exit_zero_and_real_directory(self):
        complete = _function(ENGINE, "_complete_graph_generation")
        self.assertIn("exit_code == 0", complete)
        self.assertIn("DirAccess.dir_exists_absolute(_last_graphs_dir)", complete)


class TestPythonPreflight(unittest.TestCase):
    def test_preflight_is_cached_and_supports_windows_launcher(self):
        check = _function(ENGINE, "check_python_available")
        self.assertIn("if _python_checked:", check)
        self.assertIn('["/c", "python", "--version"]', check)
        self.assertIn('["/c", "py", "-3", "--version"]', check)

    def test_launcher_refuses_when_python_is_unavailable(self):
        launch = _function(ENGINE, "_launch_graph_generator")
        self.assertIn("if not check_python_available():", launch)
        self.assertIn("return false", launch)

    def test_main_checks_python_outside_validation(self):
        ready = _function(MAIN, "_ready")
        self.assertIn("if not _is_validation_mode():", ready)
        self.assertIn("engine.check_python_available()", ready)
        self.assertIn("_set_python_warning_visible", ready)


class TestExitSuppression(unittest.TestCase):
    def test_engine_exit_respects_suppression(self):
        exit_tree = _function(ENGINE, "_exit_tree")
        self.assertIn("_exit_graphs_suppressed", exit_tree)
        self.assertLess(exit_tree.index("_exit_graphs_suppressed"), exit_tree.index("_finish_and_launch_graphs"))

    def test_exit_without_graphs_suppresses_before_scene_change(self):
        handler = _function(MAIN, "_on_exit_without_graphs_requested")
        self.assertLess(handler.index("engine.suppress_exit_graphs()"), handler.index("change_scene_to_file"))

    def test_return_to_editor_suppresses_before_scene_change(self):
        handler = _function(MAIN, "_on_return_to_editor_requested")
        self.assertLess(handler.index("engine.suppress_exit_graphs()"), handler.index("change_scene_to_file"))


class TestAsyncGraphUi(unittest.TestCase):
    def test_overlay_blocks_input_and_timer_polls_twice_per_second(self):
        setup = _function(MAIN, "_setup_graph_generation_overlay")
        self.assertIn("Control.MOUSE_FILTER_STOP", setup)
        self.assertIn("GRAPH_GENERATION_POLL_INTERVAL_S", setup)
        self.assertIn("_on_graph_generation_poll_timeout", setup)

    def test_poll_has_success_error_and_timeout_paths(self):
        poll = _function(MAIN, "_on_graph_generation_poll_timeout")
        self.assertIn("poll_result == 1", poll)
        self.assertIn("poll_result == 0", poll)
        self.assertIn("GRAPH_GENERATION_MAX_POLLS", poll)
        self.assertIn("_show_graphs_message", poll)

    def test_summary_is_deferred_while_generation_is_pending(self):
        summary = _function(MAIN, "_on_technical_summary_ready")
        self.assertIn("_graph_generation_pending", summary)
        self.assertIn("_pending_technical_summary", summary)


if __name__ == "__main__":
    unittest.main()
