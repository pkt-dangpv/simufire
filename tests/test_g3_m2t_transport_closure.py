"""Final wrapper safety; mocks and harmless Python children, never Godot."""

import re
import subprocess
import ast
from pathlib import Path
import sys

import pytest

from scripts.simulation import run_g3_o2_transport_closure as closure


def stub(monkeypatch, *, code=0, child_code=0, **changes):
    health = {"timed_out": False, "error_dialogs": [], "residual_godot_processes": [],
              "process_quiescent": True, "foreign_godot_processes": [],
              "cleanup_terminated_pids": [], "process_handle_capture_failures": [],
              "windows_error_ui_suppressed": True,
              "post_exit_observation_s": 2.1,
              "observed_godot_processes": [{"exit_code": child_code}]}
    health.update(changes)
    monkeypatch.setattr(closure.godot_monitored_launch, "memory_gate_fault", lambda: None)
    monkeypatch.setattr(closure.godot_monitored_launch, "preexisting_godot_state", lambda: [])
    monkeypatch.setattr(closure.godot_monitored_launch, "_available_gib", lambda: 7.0)
    monkeypatch.setattr(closure.mutation_audit, "_run_monitored",
                        lambda *args: (subprocess.CompletedProcess(["mock"], code, "output", ""), health))


def test_expected_negative_child_is_not_mistaken_for_a_native_crash(tmp_path, monkeypatch):
    stub(monkeypatch, child_code=1)
    result = closure.monitored("global", ["mock"], tmp_path, 1)
    assert result["errors"] == []
    assert result["returncode"] == 0


@pytest.mark.parametrize("changes", [
    {"code": 1}, {"child_code": None}, {"child_code": 0xC0000005}, {"child_code": -1073741819},
    {"timed_out": True}, {"error_dialogs": ["mock dialog"]},
    {"foreign_godot_processes": [{"pid": 123}]}, {"cleanup_terminated_pids": [123]},
    {"residual_godot_processes": [{"pid": 123}]}, {"process_quiescent": False},
    {"process_handle_capture_failures": [{"pid": 123}]},
    {"post_exit_observation_s": 0.0},
])
def test_failure_health_never_closes_a_stage(tmp_path, monkeypatch, changes):
    stub(monkeypatch, **changes)
    with pytest.raises(RuntimeError):
        closure.monitored("global", ["mock"], tmp_path, 1)
    assert (tmp_path / "global.failure.json").exists()


def test_memory_refusal_launches_nothing(tmp_path, monkeypatch):
    stub(monkeypatch)
    monkeypatch.setattr(closure.godot_monitored_launch, "memory_gate_fault", lambda: "less than 6 GiB")
    monkeypatch.setattr(closure.mutation_audit, "_run_monitored", lambda *args: pytest.fail("must not launch"))
    with pytest.raises(RuntimeError, match="preflight"):
        closure.monitored("global", ["mock"], tmp_path, 1)


@pytest.mark.skipif(sys.platform != "win32", reason="Windows locale guard")
def test_locale_mode_is_rejected_before_any_reference_or_godot_launch(tmp_path):
    script = Path(closure.__file__)
    result = subprocess.run([
        sys.executable, "-X", "utf8=0", str(script), "--work", str(tmp_path / "work"),
        "--out", str(tmp_path / "out.json"), "--mutations", str(tmp_path / "unused.json"),
    ], capture_output=True, text=True, encoding="utf-8", cwd=closure.ROOT, timeout=20)
    assert result.returncode != 0
    assert "python -X utf8" in result.stderr
    assert not (tmp_path / "out.json").exists()


@pytest.mark.parametrize("parent_utf8_mode", ["0", "1"])
def test_utf8_monitor_captures_the_smart_quote_that_broke_cp1252(parent_utf8_mode):
    code = (
        "import os,sys; from tools import mutation_audit as monitor; "
        "environment=dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8'); "
        "result,health=monitor._run_monitored([sys.executable,'-c',"
        "\"print('\\u201c\\u201d')\"],30,environment); "
        "assert result.returncode==0 and result.stdout=='\\u201c\\u201d\\n'; "
        "assert not health['timed_out'] and not health['error_dialogs']; "
        "assert health['process_quiescent'] and not health['cleanup_terminated_pids']; "
        "assert not health['process_handle_capture_failures'] and not health['foreign_godot_processes']; "
        "print('UTF8_CAPTURE_PASS')"
    )
    result = subprocess.run([sys.executable, "-X", f"utf8={parent_utf8_mode}", "-c", code],
                            capture_output=True, text=True, encoding="utf-8",
                            cwd=closure.ROOT, timeout=40)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.strip() == "UTF8_CAPTURE_PASS"


@pytest.mark.skipif(sys.platform != "win32", reason="Windows native process inventory")
def test_native_tasklist_inventory_does_not_inherit_pythons_utf8_decoder(monkeypatch):
    observed = {}

    def tasklist(command, **options):
        observed.update(options)
        return subprocess.CompletedProcess(command, 0, '"Godot_fake.exe","123","Console","1","100 K"\n', "")

    monkeypatch.setattr(closure.mutation_audit.subprocess, "run", tasklist)
    assert closure.mutation_audit._godot_processes() == [{"image_name": "Godot_fake.exe", "pid": 123}]
    assert observed["encoding"] == "oem"


def test_shared_monitor_changes_only_the_three_declared_decoders():
    path = Path(closure.mutation_audit.__file__)
    old = subprocess.check_output(["git", "show", "920affb7:tools/mutation_audit.py"], cwd=closure.ROOT)
    before = ast.parse(old.decode("utf-8"))
    after = ast.parse(path.read_text(encoding="utf-8"))
    seen = []
    for function in after.body:
        if not isinstance(function, ast.FunctionDef) or function.name not in {
                "_godot_processes", "_start_without_windows_error_ui"}:
            continue
        for node in ast.walk(function):
            if isinstance(node, ast.Call):
                for keyword in list(node.keywords):
                    if keyword.arg == "encoding":
                        seen.append(keyword.value.value)
                        node.keywords.remove(keyword)
    assert sorted(seen) == ["oem", "utf-8", "utf-8"]
    # 4b88c57e (ADR 0006) replaced the two machine-specific Godot paths by the shared
    # portable discovery. Only that block may differ, and only in exactly this form.
    before_discovery, before_rest = _split_godot_discovery(before)
    after_discovery, after_rest = _split_godot_discovery(after)
    assert [ast.dump(node) for node in after_discovery] == [ast.dump(node) for node in ast.parse(PORTABLE_DISCOVERY).body]
    assert len(before_discovery) == 1 and [
        node.args[0].value for node in ast.walk(before_discovery[0]) if isinstance(node, ast.Call)
    ] == ["C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe",
          "F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"]
    assert not any(isinstance(node, ast.Constant) and isinstance(node.value, str)
                   and re.match(r"[A-Za-z]:[\\/]", node.value) for node in ast.walk(after))
    assert ast.dump(after_rest) == ast.dump(before_rest), "ownership, cleanup, deadlines and severity must stay frozen"


PORTABLE_DISCOVERY = """
_tool_repo_root = Path(__file__).resolve().parents[1]
if str(_tool_repo_root) not in sys.path:
    sys.path.insert(0, str(_tool_repo_root))
from scripts.project_paths import godot_candidates

_GODOT_CANDIDATES = godot_candidates()
"""


def _split_godot_discovery(module):
    """Godot discovery statements, and the module without them."""
    names = {"_GODOT_CANDIDATES", "_tool_repo_root"}
    discovery, rest = [], []
    for node in module.body:
        assigned = {target.id for target in getattr(node, "targets", []) if isinstance(target, ast.Name)}
        guarded = isinstance(node, ast.If) and "_tool_repo_root" in ast.dump(node.test)
        imported = isinstance(node, ast.ImportFrom) and node.module == "scripts.project_paths"
        (discovery if assigned & names or guarded or imported else rest).append(node)
    return discovery, ast.Module(body=rest, type_ignores=[])
