"""
tests/test_ui_localization.py — W-05

Product guardrails for SimuFire UI localization.

The app is intentionally Spanish-first. This test checks that the localization
file exists, contains the keys used by the main UI surfaces, and that old
English scene literals do not reappear in visible text fields.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


_REPO_ROOT = Path(__file__).resolve().parent.parent
_I18N_PATH = _REPO_ROOT / "i18n" / "es_ui.json"
_SCENE_FILES = [
    _REPO_ROOT / "scenes" / "MainMenu.tscn",
    _REPO_ROOT / "scenes" / "ScenarioEditorScene.tscn",
    _REPO_ROOT / "scenes" / "SimulationScene.tscn",
]
_VISIBLE_PROPERTY_RE = re.compile(
    r'^\s*(?:text|title|placeholder_text|tooltip_text|item_\d+/text|popup/item_\d+/text)\s*=\s*"([^"]*)"'
)

_REQUIRED_KEYS = {
    "main.subtitle",
    "main.start_simulation",
    "editor.tool.select",
    "editor.tool.room",
    "editor.tool.door",
    "editor.tool.window",
    "editor.tool.object",
    "editor.tool.ignition",
    "editor.tool.delete",
    "editor.file.export_runtime",
    "hud.time",
    "hud.play",
    "hud.pause",
    "hud.shortcut_help",
    "summary.window_title",
}

_FORBIDDEN_SCENE_TEXTS = {
    "TACTICAL FIRE SIMULATOR",
    "Select",
    "Room",
    "Door",
    "Window",
    "Object",
    "Ignite",
    "Delete",
    "Export runtime",
    "2D PLAY",
    "TIME",
}

_FORBIDDEN_DYNAMIC_SNIPPETS = {
    "scenes/MainMenu.gd": [
        '"TACTICAL FIRE SIMULATOR"',
    ],
    "ui/HUDPlaybackLabels.gd": [
        'return "TIME ',
        'return "PLAY"',
    ],
    "ui/hud.gd": [
        'btn_play.text = "PLAY"',
    ],
    "editor/ScenarioEditor.gd": [
        '"3D Select:',
        '"3D Object:',
        "Dibuja habitaciones con Room",
    ],
}


def _load_messages() -> dict[str, str]:
    with _I18N_PATH.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    messages = data.get("messages", {})
    if not isinstance(messages, dict):
        return {}
    return {str(k): str(v) for k, v in messages.items()}


class TestUILocalization(unittest.TestCase):
    def test_localization_file_exists_and_is_spanish(self):
        self.assertTrue(_I18N_PATH.exists(), "Missing i18n/es_ui.json")
        with _I18N_PATH.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data.get("locale"), "es")

    def test_required_ui_keys_are_present(self):
        messages = _load_messages()
        missing = sorted(k for k in _REQUIRED_KEYS if not messages.get(k, "").strip())
        self.assertEqual(missing, [], "Missing localization keys: " + ", ".join(missing))

    def test_no_legacy_english_scene_texts(self):
        hits: list[str] = []
        for path in _SCENE_FILES:
            for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                match = _VISIBLE_PROPERTY_RE.match(line)
                if match and match.group(1) in _FORBIDDEN_SCENE_TEXTS:
                    hits.append(f"{path.relative_to(_REPO_ROOT)}:{line_no}: {match.group(1)!r}")
        self.assertEqual(hits, [], "Legacy English UI text remains:\n" + "\n".join(hits))

    def test_no_legacy_english_dynamic_ui_literals(self):
        hits: list[str] = []
        for rel_path, snippets in _FORBIDDEN_DYNAMIC_SNIPPETS.items():
            text = (_REPO_ROOT / rel_path).read_text(encoding="utf-8")
            for snippet in snippets:
                if snippet in text:
                    hits.append(f"{rel_path}: {snippet}")
        self.assertEqual(hits, [], "Legacy English dynamic UI literals remain:\n" + "\n".join(hits))


if __name__ == "__main__":
    unittest.main(verbosity=2)
