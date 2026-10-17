from pathlib import Path
import re
import sys
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import project_paths  # noqa: E402
GODOT_471 = "Godot_v4.7.1-stable_win64_console.exe"
GODOT_463 = "Godot_v4.6.3-stable_win64_console.exe"


def _active_runner_files() -> list[Path]:
    files: list[Path] = []
    for base in (ROOT / "scripts", ROOT / "sim" / "validation", ROOT / "tools"):
        for suffix in ("*.py", "*.ps1"):
            files.extend(base.rglob(suffix))
    return sorted(set(files))


def test_active_runners_do_not_default_to_godot_463() -> None:
    stale = [
        path.relative_to(ROOT).as_posix()
        for path in _active_runner_files()
        if GODOT_463 in path.read_text(encoding="utf-8-sig")
    ]
    assert stale == []


PRIMARY_PYTHON = (ROOT / "scripts" / "run_scenario.py", ROOT / "scripts" / "check_product.py")
PRIMARY_POWERSHELL = (
    ROOT / "sim" / "validation" / "run_case.ps1",
    ROOT / "sim" / "validation" / "run_all_cases.ps1",
    ROOT / "sim" / "validation" / "run_reference_checks.ps1",
)
# A drive-qualified path to a Godot build: machine-specific (AGENTS.md, ADR 0006).
MACHINE_GODOT_PATH = re.compile(r"[A-Za-z]:[\\/][^\"'\n]*Godot", re.IGNORECASE)


def test_primary_runners_default_to_godot_471() -> None:
    # Since 4b88c57e (ADR 0006) the 4.7.1 default lives in the shared portable
    # resolver, not in a per-runner path: each primary runner must delegate to it.
    for path in PRIMARY_PYTHON:
        text = path.read_text(encoding="utf-8-sig")
        name = path.relative_to(ROOT).as_posix()
        assert "from scripts.project_paths import godot_candidates" in text, name
        assert "_GODOT_CANDIDATES = godot_candidates()" in text, name
        assert not MACHINE_GODOT_PATH.search(text), name
    for path in PRIMARY_POWERSHELL:
        text = path.read_text(encoding="utf-8-sig")
        name = path.relative_to(ROOT).as_posix()
        assert '. (Join-Path $PSScriptRoot "..\\..\\scripts\\project_paths.ps1")' in text, name
        assert "return Resolve-SimuFireGodot -RequestedPath $RequestedPath" in text, name
        assert not MACHINE_GODOT_PATH.search(text), name


def test_shared_resolver_selects_godot_471_console_from_the_machine_desktop(tmp_path) -> None:
    desktop = tmp_path / "Escritorio con espacios ñ"
    desktop.mkdir()
    for name in (GODOT_463, "Godot_v4.7.1-stable_win64.exe", GODOT_471, "Godot_v4.8-stable_win64_console.exe"):
        (desktop / name).touch()
    with mock.patch.object(project_paths, "desktop_directories", return_value=[desktop]), \
            mock.patch.object(project_paths.shutil, "which", return_value=None):
        candidates = project_paths.godot_candidates()
    assert candidates[0].name == GODOT_471
    assert candidates.index(desktop / GODOT_463) > candidates.index(desktop / "Godot_v4.7.1-stable_win64.exe")


def test_powershell_resolver_ranks_471_then_console_and_has_no_machine_path() -> None:
    text = (ROOT / "scripts" / "project_paths.ps1").read_text(encoding="utf-8-sig")
    ranking = re.search(r"Sort-Object (.+?)\n\s*@\{Expression = \{ \$_\.Name -match \"console\" \}; Descending = \$true\}",
                        text, re.DOTALL)
    assert ranking and '$_.Name -match "v4.7.1-stable"' in ranking.group(1)
    assert "$env:GODOT_EXE" in text and "Get-Command $name -CommandType Application" in text
    assert not MACHINE_GODOT_PATH.search(text)


def test_project_declares_godot_47_feature() -> None:
    project = (ROOT / "project.godot").read_text(encoding="utf-8-sig")
    assert 'config/features=PackedStringArray("4.7", "GL Compatibility")' in project
