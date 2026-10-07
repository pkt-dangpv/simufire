"""Exercise the real product loader, model and built FP geometry under monitor."""
import json
import os
import tempfile
from pathlib import Path

from scripts import godot_monitored_launch, run_scenario

ROOT = Path(__file__).resolve().parents[1]


def _run_acceptance(*controls):
    godot = run_scenario._find_godot()
    assert godot is not None, "Godot is required for the product acceptance check"
    with tempfile.TemporaryDirectory(prefix="simufire-playable-") as temp:
        environment = os.environ.copy()
        environment.update({"APPDATA": temp, "TEMP": temp, "TMP": temp,
                            "SIMUFIRE_GODOT_MIN_AVAILABLE_GIB": "6"})
        result = godot_monitored_launch.run(
            [godot, "--headless", "--path", ROOT,
             "--script", "res://tests/fixtures/playable_homes_runtime.gd", "--", *controls],
            timeout_s=180, environment=environment)
    assert result.launched and not result.preexisting, result
    assert not result.faults and not result.timed_out, result
    output = result.stdout + result.stderr
    assert "ERROR:" not in output and "Parse Error" not in output, output
    rows = [line.split("PLAYABLE_HOMES_RESULT ", 1)[1] for line in output.splitlines()
            if line.startswith("PLAYABLE_HOMES_RESULT ")]
    assert len(rows) == 1, output
    payload = json.loads(rows[0])
    return result.returncode, payload


def test_real_playable_homes_are_furnished_and_views_share_door_conventions():
    code, payload = _run_acceptance()
    assert code == 0, payload
    assert payload["homes"] == 10 and payload["errors"] == [], payload
    assert payload["checks"] >= 300, payload
    assert payload["visible_pieces"] > 100 and payload["decorative_pieces"] > 50, payload
    print("PLAYABLE_ACCEPTANCE_PASS", json.dumps(payload))


def test_acceptance_rejects_an_actually_drawn_piece_outside_its_room():
    code, payload = _run_acceptance("--acceptance-control=outside")
    assert code == 1 and payload["injected_outside"], payload
    assert any("drawn furniture within room" in error for error in payload["errors"]), payload
