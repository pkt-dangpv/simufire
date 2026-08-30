"""CaseRunner must fail closed when the validation report cannot be written."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
CASE_RUNNER_PATH = ROOT / "sim" / "validation" / "CaseRunner.gd"
SOURCE = CASE_RUNNER_PATH.read_text(encoding="utf-8")

GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
    Path(r"F:\OneDrive\Escritorio\Godot_v4.7.1-stable_win64_console.exe"),
)


def _func(source: str, name: str) -> str:
    return source.split("func %s(" % name, 1)[1].split("\nfunc ", 1)[0]


def _godot_exe() -> Path | None:
    for candidate in GODOT_CANDIDATES:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def test_report_write_failure_is_fail_closed_contract():
    assert "func _write_json_file(path: String, data: Dictionary) -> bool:" in SOURCE

    finalize = _func(SOURCE, "_finalize_validation_run")
    guard_index = finalize.index("if not _write_json_file(_output_path, report):")
    saved_index = finalize.index('print("[Validation] Reporte guardado')
    failure_block = finalize[guard_index:saved_index]

    assert guard_index < saved_index
    assert "get_tree().quit(1)" in failure_block
    assert "return" in failure_block

    writer = _func(SOURCE, "_write_json_file")
    open_failure = writer.split("if file == null:", 1)[1].split(
        "file.store_string", 1
    )[0]
    assert "push_error(" in open_failure
    assert "return false" in open_failure
    assert "return true" in writer


def test_report_write_failure_exits_nonzero_without_success_claim(tmp_path):
    godot = _godot_exe()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")

    bad_output = tmp_path / "report_path_is_directory.json"
    bad_output.mkdir()

    completed = run_godot(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--",
            "--validation-case",
            "carbon_balance_creation",
            "--validation-output",
            str(bad_output),
        ],
        timeout_s=90,
    )
    output = completed.stdout + completed.stderr

    assert completed.returncode != 0, output
    assert "CaseRunner: no se pudo escribir" in output
    assert "[Validation] Reporte guardado" not in output
    assert "[Validation] Baseline PASS" not in output
