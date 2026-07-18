from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
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


def test_primary_runners_default_to_godot_471() -> None:
    primary = (
        ROOT / "scripts" / "run_scenario.py",
        ROOT / "scripts" / "check_product.py",
        ROOT / "sim" / "validation" / "run_case.ps1",
        ROOT / "sim" / "validation" / "run_all_cases.ps1",
        ROOT / "sim" / "validation" / "run_reference_checks.ps1",
    )
    for path in primary:
        text = path.read_text(encoding="utf-8-sig")
        assert GODOT_471 in text, path.relative_to(ROOT).as_posix()


def test_project_declares_godot_47_feature() -> None:
    project = (ROOT / "project.godot").read_text(encoding="utf-8-sig")
    assert 'config/features=PackedStringArray("4.7", "GL Compatibility")' in project
