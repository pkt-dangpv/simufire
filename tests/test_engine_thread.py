"""Motor en un hilo trabajador (Main.gd + view/BuildingViewMirror.gd).

Arranca Godot (headless, monitorizado) con tests/fixtures/engine_thread_probe.gd:
la escena del producto jugada por su propio bucle con `--engine-thread=on`
frente al motor avanzado directamente, y una vez sin el argumento.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import tempfile

import pytest

ROOT = Path(__file__).resolve().parents[1]
import sys  # noqa: E402

sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch  # noqa: E402
from scripts.project_paths import find_godot  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "engine_thread_probe.gd"
VIEW_READERS = ("Visualizer", "Visualizer3D", "HUD", "Minimap2D", "FirstPersonController")


def _launch(extra: list[str]) -> dict:
    godot = find_godot()
    if godot is None:
        pytest.skip("Godot no encontrado (GODOT_EXE, PATH o escritorio)")
    with tempfile.TemporaryDirectory(prefix="simufire_engine_thread_") as work:
        work_path = Path(work)
        environment = os.environ.copy()
        for name in ("APPDATA", "TEMP", "TMP"):
            path = work_path / name.lower()
            path.mkdir()
            environment[name] = str(path)
        out_path = work_path / "out.json"
        result = godot_monitored_launch.run(
            [godot, "--headless", "--path", ROOT, "--script", FIXTURE, "--",
             f"--out={out_path}", *extra],
            timeout_s=600, environment=environment)
        text = result.stdout + result.stderr
        assert result.launched and result.returncode == 0 and not result.faults, (
            result.returncode, result.faults, result.preexisting)
        assert "SCRIPT ERROR" not in text and "Parse Error" not in text, text[-2000:]
        assert "lee el edificio del motor" not in text, text[-2000:]
        return json.loads(out_path.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def threaded() -> dict:
    return _launch(["--engine-thread=on", "--steps=240"])


def test_headless_without_the_argument_keeps_the_engine_on_the_main_thread():
    default = _launch(["--default"])["default"]
    assert default == {"engine_threaded": False, "views_read_engine_building": True}


def test_every_view_reads_the_mirror_not_the_engine_building(threaded):
    run = threaded["threaded"]
    assert run["engine_threaded"] and run["mirror_is_separate"]
    assert run["views_bound"] == {name: True for name in VIEW_READERS}


def test_mirror_equals_the_engine_building_and_shares_no_container(threaded):
    assert threaded["threaded"]["mirror_mismatches"] == []


def test_threaded_play_matches_the_engine_stepped_directly(threaded):
    run = threaded["threaded"]
    # La puerta la cambia una vista con un paso en marcha: entra en el siguiente.
    assert run["door"] >= 0 and run["door_after_step"] > 0
    assert run["threaded_steps"] >= 240
    assert run["identical_to_direct_engine"], run["state_sha256"]


def test_speed_change_waits_for_the_running_step(threaded):
    run = threaded["threaded"]
    assert run["speed_after_step"] > 0
    assert run["speed_kept_during_step"] and run["speed_shown_during_step"]
    assert run["speed_applied"]


def test_leaving_the_scene_waits_for_the_running_step_and_frees_the_mirror(threaded):
    assert threaded["exit"] == {
        "step_was_running": True, "task_finished_on_exit": True, "mirror_freed": True}


def test_play_refreshes_use_the_state_exported_on_the_engine_thread(threaded):
    views = threaded["views"]
    assert views["published_checks"] > 0
    assert views["published_state_matches_engine"]


def test_first_person_and_hud_refresh_on_different_ticks(threaded):
    views = threaded["views"]
    assert views["fp_refreshes"] >= 20 and views["hud_refreshes"] >= 20
    assert views["fp_and_hud_same_tick"] == 0
    assert views["hud_gets_the_fp_state"]


def test_views_keep_refreshing_when_the_engine_steps_every_tick(threaded):
    """A x5 o más el motor avanza en cada tick: las vistas no esperan un tick libre."""
    views = threaded["views"]
    assert views["fast_fp_refreshes"] >= 10 and views["fast_hud_refreshes"] >= 10


def test_minimap_follows_the_player_every_frame_and_redraws_furniture_only_on_change(threaded):
    views = threaded["views"]
    assert views["marker_follows_player"]
    assert views["structure_keys_during_play"] == 1
    assert views["window_found"] and views["broken_glass_redraws_structure"]


def test_views_never_look_up_the_engine_building_by_themselves():
    """Las vistas reciben su edificio de Main; buscarlo en la escena saltaría la copia."""
    lookups = {}
    for path in [*(ROOT / "view").rglob("*.gd"), *(ROOT / "ui").rglob("*.gd")]:
        text = path.read_text(encoding="utf-8")
        found = re.findall(r'get_node(?:_or_null)?\("[^"]*BuildingModel"\)', text)
        if found:
            lookups[path.relative_to(ROOT).as_posix()] = found
    # Solo el respaldo de los dos visores cuando nadie les ha dado edificio
    # (escenas sueltas del editor); Main se lo da antes de que lo usen.
    assert set(lookups) <= {"view/2d/Visualizer.gd", "view/3d/Visualizer3D.gd"}, lookups
