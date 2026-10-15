"""Machine-local tool discovery and relocation of a checkout."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import project_paths


class ProjectPathsTests(unittest.TestCase):
    def test_explicit_path_wins_over_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            explicit = Path(directory) / "explicit.exe"
            explicit.touch()
            with mock.patch.dict(os.environ, {"GODOT_EXE": "missing-environment-tool"}):
                self.assertEqual(project_paths.find_godot(str(explicit)), explicit.resolve())

    def test_invalid_explicit_path_does_not_launch_another_tool(self):
        with mock.patch("scripts.project_paths.shutil.which", return_value=None):
            with self.assertRaises(FileNotFoundError):
                project_paths.find_godot("missing-explicit-tool.exe")

    def test_environment_can_select_a_path_command(self):
        with mock.patch.dict(os.environ, {"GODOT_EXE": "my-godot"}), \
                mock.patch("scripts.project_paths.shutil.which", return_value="selected/godot.exe"):
            self.assertEqual(project_paths.find_godot(), Path("selected/godot.exe"))

    def test_no_installation_returns_none(self):
        with mock.patch.dict(os.environ, {"GODOT_EXE": ""}), \
                mock.patch("scripts.project_paths.godot_candidates", return_value=[]):
            self.assertIsNone(project_paths.find_godot())

    def test_desktop_candidates_follow_machine_directory_and_prefer_console(self):
        with tempfile.TemporaryDirectory() as directory:
            desktop = Path(directory) / "Desktop on another drive"
            desktop.mkdir()
            for name in ["Godot_v4.7.1-stable_win64_console.exe", "Godot_v4.7.1-stable_win64.exe",
                         "Godot_v4.8-stable_win64_console.exe", "unrelated.exe"]:
                (desktop / name).touch()
            with mock.patch("scripts.project_paths.desktop_directories", return_value=[desktop]), \
                    mock.patch("scripts.project_paths.shutil.which", return_value=None):
                candidates = project_paths.godot_candidates()
            self.assertEqual(candidates[0].name, "Godot_v4.7.1-stable_win64_console.exe")
            self.assertEqual(len(candidates), 3)

    def test_checkout_root_follows_module_location_from_unrelated_cwd(self):
        with tempfile.TemporaryDirectory(prefix="simufire relocation ") as directory:
            checkout = Path(directory) / "new checkout"
            (checkout / "scripts").mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/project_paths.py", checkout / "scripts/project_paths.py")
            code = ("import sys,json;sys.path.insert(0,sys.argv[1]);"
                    "from scripts.project_paths import REPO_ROOT;print(json.dumps(str(REPO_ROOT)))")
            result = subprocess.run([sys.executable, "-B", "-c", code, str(checkout)],
                                    cwd=directory, capture_output=True, text=True, check=True)
            self.assertEqual(Path(json.loads(result.stdout)), checkout.resolve())

    def test_all_migrated_launchers_compute_the_actual_repo_parent(self):
        import ast
        for folder in ("scripts", "tools", "sim/validation"):
            for path in (ROOT / folder).rglob("*.py"):
                if "__pycache__" in path.parts:
                    continue
                text = path.read_text(encoding="utf-8-sig")
                if "_tool_repo_root =" not in text:
                    continue
                namespace = {"Path": Path, "__file__": str(path)}
                assignment = next(n for n in ast.parse(text).body if isinstance(n, ast.Assign)
                                  and any(isinstance(t, ast.Name) and t.id == "_tool_repo_root" for t in n.targets))
                value = eval(compile(ast.Expression(assignment.value), str(path), "eval"), namespace)
                with self.subTest(path=str(path.relative_to(ROOT))):
                    self.assertEqual(value, ROOT)


if __name__ == "__main__":
    unittest.main()
