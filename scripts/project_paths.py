"""Locate local tools without embedding a user's name or drive in the project."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil

REPO_ROOT = Path(__file__).resolve().parents[1]


def desktop_directories() -> list[Path]:
    directories = [Path.home() / "Desktop", Path.home() / "Escritorio"]
    for name in ("OneDrive", "OneDriveConsumer", "OneDriveCommercial"):
        if os.environ.get(name):
            directories.extend(Path(os.environ[name]) / n for n in ("Desktop", "Escritorio"))
    if os.name == "nt":
        import winreg

        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                               r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as key:
                value, _ = winreg.QueryValueEx(key, "Desktop")
                directories.insert(0, Path(os.path.expandvars(value)))
        except OSError:
            pass
    return list(dict.fromkeys(directories))


def godot_candidates() -> list[Path]:
    """Return tools from this machine's PATH and Desktop, preferring console builds.

    Existing callers keep their explicit argument / GODOT_EXE precedence.
    No executable is launched and no directory is created by discovery.
    """
    candidates = []
    for name in ("godot", "godot4", "godot_console", "godot4_console"):
        if hit := shutil.which(name):
            candidates.append(Path(hit))
    for directory in desktop_directories():
        if directory.is_dir():
            builds = list(directory.glob("Godot*.exe"))
            builds.sort(key=lambda p: ("v4.7.1-stable" in p.stem.lower(), "console" in p.stem.lower(),
                                       tuple(int(n) for n in re.findall(r"\d+", p.stem))), reverse=True)
            candidates.extend(p for p in builds if p.is_file())
    return list(dict.fromkeys(candidates))


def find_godot(requested: str | None = None) -> Path | None:
    """Resolve an explicit tool, GODOT_EXE, then machine-local candidates."""
    for value in (requested, os.environ.get("GODOT_EXE")):
        if value:
            path = Path(value).expanduser()
            if path.is_file():
                return path.resolve()
            if hit := shutil.which(value):
                return Path(hit)
            raise FileNotFoundError(f"Godot no encontrado: {value}")
    return next(iter(godot_candidates()), None)
