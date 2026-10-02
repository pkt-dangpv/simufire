"""check_product.py and run_scenario.py reach Godot only through the monitor.

Both scripts used to call ``subprocess.run`` on Godot; a check_product run
inside a sandbox left native error popups that were later charged to healthy
runs (2026-09-29). These tests pin the replacement without starting Godot:

* real monitor loop, with a harmless Python child standing in for Godot and
  the window/process scans scripted (``monitor`` fixture);
* the whole ``check_product.main`` table, with the monitor itself faked
  (``product`` fixture), so every Godot check it declares is accounted for.

In both, a Godot command that reaches ``subprocess`` by any other road raises.
"""

from __future__ import annotations

import ast
import contextlib
import ctypes
import importlib.util
import io
import json
import re
import subprocess
import sys
from ctypes import wintypes
from pathlib import Path
from types import SimpleNamespace

import pytest

from scripts import godot_monitored_launch
from tools import mutation_audit


ROOT = Path(__file__).resolve().parents[1]
CHECK_PATH = ROOT / "scripts" / "check_product.py"
RUNNER_PATH = ROOT / "scripts" / "run_scenario.py"
LAUNCH_PATH = ROOT / "scripts" / "godot_monitored_launch.py"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECK = _load("simufire_check_product_monitored", CHECK_PATH)
RUNNER = _load("simufire_run_scenario_monitored", RUNNER_PATH)

TITLE = "Godot_v4.7.1-stable_win64.exe - Error de la aplicación"
SLEEPER = "import time; time.sleep(120)"
QUIET = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
TOKEN = "FAKE PRODUCT CHECK VALIDATION PASS"
SCRIPT = "res://tools/validate_fake.gd"
SCENE = "res://tools/validate_fake.tscn"
STRAY = {"image_name": "Godot_v4.7.1-stable_win64.exe", "pid": 4242}
ALL_PASS = "ALL PRODUCT CHECKS PASS"


def _fake_godot_files(tmp_path: Path) -> tuple[Path, Path]:
    console = tmp_path / "Godot_fake_win64_console.exe"
    engine = tmp_path / "Godot_fake_win64.exe"
    console.write_text("", encoding="utf-8")
    engine.write_text("", encoding="utf-8")
    return console, engine


def _argument(command: list[str], name: str) -> str:
    return next(item.split("=", 1)[1] for item in command if item.startswith(name + "="))


def _run_scenario_artifacts(command: list[str]) -> dict[str, str]:
    """What tools/run_scenario_headless.tscn leaves behind for this command."""
    scenario = _argument(command, "--run-scenario")
    duration = float(_argument(command, "--duration"))
    manifest = {
        "schema_version": "simufire_run_scenario_manifest_v1",
        "status": "completed",
        "run_token": _argument(command, "--run-token"),
        "runner_entrypoint": RUNNER._RUNNER_SCENE,
        "scenario_path": scenario,
        "duration_s": duration,
        "sim_time_s": duration,
    }
    return {
        "summary.json": json.dumps({"schema_version": "simufire_technical_summary_v1"}),
        "events.json": "[]",
        "sim_log.txt": "ok\n",
        "sim_log.csv": "time_s\n1.0\n",
        "run_manifest.json": json.dumps(manifest),
    }


# ---------------------------------------------------------------------------
# Real monitor loop, fake Godot child
# ---------------------------------------------------------------------------

@pytest.fixture
def monitor(tmp_path, monkeypatch):
    console, engine = _fake_godot_files(tmp_path)
    real_popen = subprocess.Popen
    state = SimpleNamespace(
        console=console, engine=engine, process=None, spawned=[],
        child=lambda _command: f"print({TOKEN!r})",
        dialogs=lambda: [], processes=lambda: [],
    )

    def exited() -> bool:
        return state.process is not None and state.process.poll() is not None

    state.exited = exited

    def spawn(command, _environment):
        state.spawned.append(list(command))
        state.process = real_popen(
            [sys.executable, "-c", state.child(command)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        return state.process, True

    class GuardedPopen(real_popen):
        def __init__(self, args, *rest, **kwargs):
            argv = args if isinstance(args, (list, tuple)) else [args]
            if Path(str(argv[0])).name in (console.name, engine.name):
                raise AssertionError(f"Godot launched outside the monitor: {argv}")
            super().__init__(args, *rest, **kwargs)

    monkeypatch.delenv(godot_monitored_launch.HEALTH_LOG_ENV, raising=False)
    monkeypatch.setattr(subprocess, "Popen", GuardedPopen)
    monkeypatch.setattr(mutation_audit, "_start_without_windows_error_ui", spawn)
    monkeypatch.setattr(mutation_audit, "_windows_godot_error_dialogs", lambda: state.dialogs())
    monkeypatch.setattr(mutation_audit, "_godot_processes", lambda: state.processes())
    monkeypatch.setattr(mutation_audit, "_POST_EXIT_OBSERVATION_S", 0.4)
    monkeypatch.setattr(mutation_audit, "_OWNED_DESCENDANT_DRAIN_S", 1.5)
    monkeypatch.delenv(godot_monitored_launch.MIN_AVAILABLE_GIB_ENV, raising=False)
    monkeypatch.setattr(CHECK, "_find_godot", lambda: console)
    return state


@pytest.fixture
def stray():
    """A live process of this test, reported by the name scan as someone else's Godot."""
    process = subprocess.Popen([sys.executable, "-c", SLEEPER], **QUIET)
    record = {"image_name": "Godot_v4.7.1-stable_win64.exe", "pid": process.pid}
    yield SimpleNamespace(process=process, pid=process.pid, record=record)
    process.kill()
    process.wait()


def _spawns_descendant(marker: Path, token: str) -> str:
    """Fake Godot that leaves a descendant running, prints the token and exits 0."""
    return (
        "import pathlib, subprocess, sys\n"
        f"descendant = subprocess.Popen([sys.executable, '-c', {SLEEPER!r}], "
        "stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
        f"pathlib.Path({str(marker)!r}).write_text(str(descendant.pid), encoding='utf-8')\n"
        f"print({token!r})\n"
    )


def _pid_alive(pid: int) -> bool:
    handle, _error = mutation_audit._open_process_handle(pid)
    if handle is None:
        return False
    try:
        code = wintypes.DWORD()
        ctypes.windll.kernel32.GetExitCodeProcess(wintypes.HANDLE(handle), ctypes.byref(code))
        return code.value == mutation_audit._STILL_ACTIVE
    finally:
        ctypes.windll.kernel32.CloseHandle(wintypes.HANDLE(handle))


def test_the_guard_rejects_a_direct_godot_launch(monitor):
    with pytest.raises(AssertionError, match="outside the monitor"):
        subprocess.run([str(monitor.console), "--version"], capture_output=True)


def test_clean_run_keeps_the_expected_result(monitor):
    assert CHECK._run_godot_script(SCRIPT, TOKEN) == (0, 1, 0, "")
    assert CHECK._run_godot_scene(SCENE, TOKEN) == (0, 1, 0, "")
    prefix = [str(monitor.engine), "--headless", "--path", str(ROOT)]
    assert monitor.spawned == [prefix + ["--script", SCRIPT], prefix + [SCENE]]


def test_prior_popup_blocks_the_launch_and_is_reported_as_prior(monitor):
    monitor.dialogs = lambda: [TITLE]
    code, count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    assert (code, count, fails) == (1, 1, 1)
    assert "PREVIO" in diagnostic and TITLE in diagnostic and SCRIPT in diagnostic
    assert "ESTA ejecucion" not in diagnostic
    assert monitor.spawned == []


def test_prior_godot_process_blocks_the_launch_and_is_not_killed(monitor, stray):
    monitor.processes = lambda: [stray.record]
    code, _count, fails, diagnostic = CHECK._run_godot_scene(SCENE, TOKEN)
    assert (code, fails) == (1, 1)
    assert "PREVIO" in diagnostic and str(stray.pid) in diagnostic
    assert monitor.spawned == []
    assert stray.process.poll() is None and _pid_alive(stray.pid)


def test_new_popup_during_the_run_fails_the_check(monitor):
    scans = {"n": 0}

    def dialogs():
        scans["n"] += 1
        return [] if scans["n"] <= 2 else [TITLE]  # both pre-launch scans are clean

    monitor.dialogs = dialogs
    monitor.child = lambda _c: f"import time; print({TOKEN!r}, flush=True); time.sleep(60)"
    code, _count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    assert code != 0 and fails == 1
    assert "ESTA ejecucion" in diagnostic and "new Godot error dialog" in diagnostic
    assert "PREVIO" not in diagnostic
    assert monitor.exited()  # the monitor killed it


def test_popup_after_a_clean_exit_with_the_token_is_not_a_pass(monitor):
    monitor.dialogs = lambda: [TITLE] if monitor.exited() else []
    code, _count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    assert monitor.process.returncode == 0 and TOKEN in diagnostic
    assert code != 0 and fails == 1
    assert "new Godot error dialog" in diagnostic


def test_process_failure_fails_the_check_and_keeps_its_exit_code(monitor):
    monitor.child = lambda _c: f"import sys; print({TOKEN!r}); sys.exit(3)"
    code, _count, fails, diagnostic = CHECK._run_godot_scene(SCENE, TOKEN)
    assert (code, fails) == (3, 1)
    assert TOKEN in diagnostic


def test_timeout_is_not_a_pass(monitor):
    monitor.child = lambda _c: f"import time; print({TOKEN!r}, flush=True); time.sleep(60)"
    code, _count, fails, diagnostic = CHECK._run_godot_scene(SCENE, TOKEN, timeout_s=1)
    assert code != 0 and fails == 1
    assert diagnostic.startswith("se paso del limite de 1 s (%s)" % SCENE)
    assert monitor.exited()


def test_own_descendant_left_after_a_clean_exit_is_cleaned_and_is_not_a_pass(monitor, tmp_path):
    marker = tmp_path / "descendant.pid"
    monitor.child = lambda _c: _spawns_descendant(marker, TOKEN)
    code, _count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    descendant = int(marker.read_text(encoding="utf-8"))
    assert monitor.process.returncode == 0 and TOKEN in diagnostic
    assert code != 0 and fails == 1
    assert "residual Godot processes" in diagnostic and str(descendant) in diagnostic
    assert not _pid_alive(descendant)


def test_foreign_godot_during_the_run_is_not_a_pass_and_is_not_killed(monitor, stray):
    monitor.processes = lambda: [stray.record] if monitor.process is not None else []
    monitor.child = lambda _c: f"import time; time.sleep(1.5); print({TOKEN!r})"
    code, _count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    assert monitor.process.returncode == 0 and TOKEN in diagnostic
    assert code != 0 and fails == 1
    assert "ESTA ejecucion" in diagnostic and "foreign Godot processes appeared" in diagnostic
    assert "PREVIO" not in diagnostic
    assert stray.process.poll() is None and _pid_alive(stray.pid)


def test_memory_gate_is_opt_in_and_applies_to_each_launch(monitor, monkeypatch):
    def not_measured():
        raise AssertionError("memory read without the gate being requested")

    monkeypatch.setattr(godot_monitored_launch, "_available_gib", not_measured)
    assert CHECK._run_godot_script(SCRIPT, TOKEN) == (0, 1, 0, "")

    monkeypatch.setenv(godot_monitored_launch.MIN_AVAILABLE_GIB_ENV, "6")
    monkeypatch.setattr(godot_monitored_launch, "_available_gib", lambda: 7.25)
    assert CHECK._run_godot_script(SCRIPT, TOKEN) == (0, 1, 0, "")
    assert len(monitor.spawned) == 2

    monkeypatch.setattr(godot_monitored_launch, "_available_gib", lambda: 5.5)
    code, _count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    assert (code, fails) == (1, 1)
    assert "no se pudo lanzar Godot" in diagnostic and "5.50 GiB available" in diagnostic
    assert "PREVIO" not in diagnostic

    monkeypatch.setenv(godot_monitored_launch.MIN_AVAILABLE_GIB_ENV, "seis")
    assert CHECK._run_godot_script(SCRIPT, TOKEN)[:3] == (1, 1, 1)
    assert len(monitor.spawned) == 2


def test_exit_zero_without_the_token_or_with_a_compile_error_is_not_a_pass(monitor):
    monitor.child = lambda _c: "print('nothing checked')"
    assert CHECK._run_godot_script(SCRIPT, TOKEN)[:3] == (1, 1, 1)
    monitor.child = lambda _c: f"print('SCRIPT ERROR: Parse Error: bad'); print({TOKEN!r})"
    code, _count, fails, diagnostic = CHECK._run_godot_script(SCRIPT, TOKEN)
    assert (code, fails) == (1, 1) and "no compila" in diagnostic


def _run_scenario_child(command: list[str]) -> str:
    out_dir = _argument(command, "--out-dir")
    files = _run_scenario_artifacts(command)
    marker = "RUN_SCENARIO PASS token=" + _argument(command, "--run-token")
    return (
        "import pathlib\n"
        f"out = pathlib.Path({out_dir!r})\n"
        f"for name, text in {files!r}.items():\n"
        "    (out / name).write_text(text, encoding='utf-8')\n"
        f"print({marker!r})\n"
    )


def _run_scenario_main(monitor, tmp_path: Path) -> int:
    scenario = tmp_path / "case.json"
    scenario.write_text('{"duration_s": 1.0}', encoding="utf-8")
    monitor.child = _run_scenario_child
    return RUNNER.main([
        str(scenario), "--out-dir", str(tmp_path / "out"),
        "--godot", str(monitor.console), "--duration", "1", "--timeout", "30",
    ])


def test_run_scenario_launches_through_the_monitor(monitor, tmp_path, capsys):
    assert _run_scenario_main(monitor, tmp_path) == 0
    assert "[run_scenario] PASS" in capsys.readouterr().out
    assert len(monitor.spawned) == 1
    command = monitor.spawned[0]
    assert command[0] == str(monitor.engine)
    assert RUNNER._RUNNER_SCENE in command and "--headless" in command
    health = json.loads((tmp_path / "out" / "monitor.health.json").read_text(encoding="utf-8"))
    assert health["contract"] == mutation_audit._RUNTIME_HEALTH_CONTRACT
    assert health["error_dialogs"] == [] and health["timed_out"] is False


def test_run_scenario_refuses_to_launch_behind_a_prior_popup(monitor, tmp_path, capsys):
    monitor.dialogs = lambda: [TITLE]
    assert _run_scenario_main(monitor, tmp_path) == 1
    error = capsys.readouterr().err
    assert "Godot was not launched" in error and "pre-existing Godot error dialog" in error
    assert monitor.spawned == []


def test_run_scenario_fails_on_a_popup_from_its_own_run(monitor, tmp_path, capsys):
    monitor.dialogs = lambda: [TITLE] if monitor.exited() else []
    assert _run_scenario_main(monitor, tmp_path) == 1
    captured = capsys.readouterr()
    assert "monitor: new Godot error dialog" in captured.err
    assert "[run_scenario] PASS" not in captured.out


def test_run_scenario_timeout_and_foreign_godot_are_failures(monitor, stray, tmp_path, capsys):
    scenario = tmp_path / "case.json"
    scenario.write_text('{"duration_s": 1.0}', encoding="utf-8")
    monitor.child = lambda _c: "import time; time.sleep(60)"
    arguments = [str(scenario), "--out-dir", str(tmp_path / "out"),
                 "--godot", str(monitor.console), "--duration", "1"]
    assert RUNNER.main(arguments + ["--timeout", "1"]) == 1
    assert "timed out after 1s" in capsys.readouterr().err

    monitor.process = None
    monitor.processes = lambda: [stray.record] if monitor.process is not None else []
    assert _run_scenario_main(monitor, tmp_path) == 1
    assert "monitor: foreign Godot processes appeared" in capsys.readouterr().err
    assert stray.process.poll() is None and _pid_alive(stray.pid)


def test_health_log_records_launched_and_refused_requests(monitor, tmp_path, monkeypatch):
    log = tmp_path / "health.jsonl"
    monkeypatch.setenv(godot_monitored_launch.HEALTH_LOG_ENV, str(log))
    CHECK._run_godot_script(SCRIPT, TOKEN)
    monitor.dialogs = lambda: [TITLE]
    CHECK._run_godot_script(SCRIPT, TOKEN)
    first, second = (json.loads(line) for line in log.read_text(encoding="utf-8").splitlines())
    assert first["launched"] is True and first["faults"] == [] and first["returncode"] == 0
    assert first["command"][-2:] == ["--script", SCRIPT]
    assert second["launched"] is False and second["health"] is None
    assert TITLE in second["preexisting"][0]


# ---------------------------------------------------------------------------
# infrastructure_faults: what the monitor's health record means here
# ---------------------------------------------------------------------------

def _healthy() -> dict:
    return {
        "contract": mutation_audit._RUNTIME_HEALTH_CONTRACT,
        "windows_error_ui_suppressed": True,
        "timed_out": False,
        "error_dialogs": [],
        "residual_godot_processes": [],
        "foreign_godot_processes": [],
        "process_quiescent": True,
        "observed_godot_processes": [
            {"image_name": "Godot_fake_win64.exe", "pid": 1, "exit_code": 0}
        ],
        "process_handle_capture_races": [],
        "process_handle_capture_failures": [],
        "post_exit_observation_s": mutation_audit._POST_EXIT_OBSERVATION_S,
    }


def test_a_healthy_record_has_no_faults_whatever_the_exit_code():
    health = _healthy()
    assert godot_monitored_launch.infrastructure_faults(health) == []
    health["observed_godot_processes"][0]["exit_code"] = 1  # a failed check, not a fault
    assert godot_monitored_launch.infrastructure_faults(health) == []


@pytest.mark.parametrize(
    ("change", "expected"),
    [
        ({"timed_out": True}, "timed out"),
        ({"error_dialogs": [TITLE]}, "new Godot error dialog"),
        ({"residual_godot_processes": [STRAY]}, "residual Godot processes"),
        ({"foreign_godot_processes": [STRAY]}, "foreign Godot processes appeared"),
        ({"process_quiescent": False}, "quiescent"),
        ({"observed_godot_processes": [{**STRAY, "exit_code": 0xC0000005}]}, "access violation"),
        ({"observed_godot_processes": [{**STRAY, "exit_code": None}]}, "exit code is missing"),
        ({"observed_godot_processes": None}, "inventory is missing"),
        ({"process_handle_capture_failures": [STRAY]}, "handle capture failed"),
        ({"post_exit_observation_s": 0.1}, "observation window"),
    ],
)
def test_each_unhealthy_field_is_a_fault(change, expected):
    faults = godot_monitored_launch.infrastructure_faults({**_healthy(), **change})
    assert len(faults) == 1 and expected in faults[0]


# ---------------------------------------------------------------------------
# check_product.main end to end, monitor faked
# ---------------------------------------------------------------------------

def _godot_checks_in_main() -> list[tuple[str, str, str, int]]:
    """(function, target, token, timeout) of every Godot check main() declares."""
    tree = ast.parse(CHECK_PATH.read_text(encoding="utf-8"))
    main = next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "main"
    )
    found = []
    for node in ast.walk(main):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in ("_run_godot_scene", "_run_godot_script")
        ):
            target, token = (ast.literal_eval(argument) for argument in node.args[:2])
            timeout = next(
                (ast.literal_eval(keyword.value) for keyword in node.keywords
                 if keyword.arg == "timeout_s"),
                CHECK._GODOT_TIMEOUT_S,
            )
            found.append((node.lineno, node.func.id, target, token, timeout))
    return [item[1:] for item in sorted(found)]


GODOT_CHECKS = _godot_checks_in_main()
FIRST_SCRIPT = next(target for function, target, _, _ in GODOT_CHECKS if function == "_run_godot_script")
LAST_SCENE = [target for function, target, _, _ in GODOT_CHECKS if function == "_run_godot_scene"][-1]
NESTED = RUNNER._RUNNER_SCENE


@pytest.fixture
def product(tmp_path, monkeypatch):
    console, _engine = _fake_godot_files(tmp_path)
    tokens = {target: token for _function, target, token, _timeout in GODOT_CHECKS}
    state = SimpleNamespace(
        console=console, calls=[], python=[], inject={}, open_dialogs=[], processes=[],
        processes_after_last_launch=[],
    )

    def run_monitored(command, timeout_s, _environment=None):
        if state.open_dialogs:
            raise mutation_audit.PreexistingGodotErrorDialog(str(state.open_dialogs))
        target = next(item for item in command if item.startswith("res://"))
        state.calls.append((target, list(command), timeout_s))
        health, code = _healthy(), 0
        if target == NESTED:
            out_dir = Path(_argument(command, "--out-dir"))
            for name, text in _run_scenario_artifacts(command).items():
                (out_dir / name).write_text(text, encoding="utf-8")
            output = "RUN_SCENARIO PASS token=" + _argument(command, "--run-token") + "\n"
            state.processes = list(state.processes_after_last_launch)
        else:
            output = tokens[target] + "\n"
        fault = state.inject.get(target)
        if fault == "popup":
            health["error_dialogs"], code, output = [TITLE], 1, ""
            state.open_dialogs = [TITLE]
        elif fault == "popup_after_clean_exit":
            health["error_dialogs"] = [TITLE]
            state.open_dialogs = [TITLE]
        elif fault == "timeout":
            health["timed_out"], code, output = True, 1, ""
        elif fault == "residual_after_clean_exit":
            health["residual_godot_processes"] = [STRAY]
            health["process_quiescent"] = False
        elif fault == "foreign_after_clean_exit":
            health["foreign_godot_processes"] = [STRAY]
        elif fault == "crash":
            health["observed_godot_processes"][0]["exit_code"] = 0xC0000005
            code, output = 0xC0000005, ""
        elif fault == "exit_zero_without_token":
            output = "nothing checked\n"
        elif fault == "exit_zero_compile_error":
            output = "SCRIPT ERROR: Parse Error: bad\n" + output
        else:
            assert fault is None, fault
        return subprocess.CompletedProcess(command, code, output, ""), health

    def python_only(command, **_kwargs):
        """Stands in for subprocess.run inside check_product: Python children only."""
        assert command[0] == sys.executable, f"not a Python child: {command}"
        script = Path(command[1])
        state.python.append(script.name)
        if script == RUNNER_PATH:
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = RUNNER.main(list(command[2:]))
            return subprocess.CompletedProcess(command, code, stdout.getvalue(), stderr.getvalue())
        if script.parent.name == "tests":
            return subprocess.CompletedProcess(command, 0, "", "Ran 3 tests in 0.001s\n\nOK\n")
        assert script.name == "check_gdscript_style.py", script
        return subprocess.CompletedProcess(command, 0, "[check_gdscript_style] PASS\n", "")

    monkeypatch.delenv(godot_monitored_launch.HEALTH_LOG_ENV, raising=False)
    monkeypatch.delenv(godot_monitored_launch.MIN_AVAILABLE_GIB_ENV, raising=False)
    monkeypatch.setattr(mutation_audit, "_run_monitored", run_monitored)
    monkeypatch.setattr(mutation_audit, "_windows_godot_error_dialogs", lambda: list(state.open_dialogs))
    monkeypatch.setattr(mutation_audit, "_godot_processes", lambda: list(state.processes))
    monkeypatch.setattr(CHECK.subprocess, "run", python_only)
    monkeypatch.setattr(CHECK, "_find_godot", lambda: console)
    monkeypatch.setattr(RUNNER, "_find_godot", lambda _explicit=None: console)
    return state


def test_main_declares_godot_checks_of_both_kinds():
    functions = {function for function, _, _, _ in GODOT_CHECKS}
    assert functions == {"_run_godot_scene", "_run_godot_script"}
    assert len({target for _, target, _, _ in GODOT_CHECKS}) == len(GODOT_CHECKS)


def test_clean_main_passes_and_every_godot_launch_is_monitored(product, capsys):
    assert CHECK.main() == 0
    output = capsys.readouterr().out
    assert ALL_PASS in output and "PREVIO" not in output

    prefix = [str(product.console), "--headless", "--path", str(ROOT)]
    expected = [
        (target, prefix + (["--script", target] if function == "_run_godot_script" else [target]), timeout)
        for function, target, _token, timeout in GODOT_CHECKS
    ]
    assert product.calls[:-1] == expected
    nested_target, nested_command, nested_timeout = product.calls[-1]
    assert nested_target == NESTED and nested_command[0] == str(product.console)
    assert nested_timeout == CHECK._RUN_SCENARIO_GODOT_TIMEOUT_S
    # The outer limit covers the inner one plus the monitor's wait for the engine's helpers.
    assert CHECK._RUN_SCENARIO_TIMEOUT_S >= (
        CHECK._RUN_SCENARIO_GODOT_TIMEOUT_S + mutation_audit._OWNED_DESCENDANT_DRAIN_S
    )
    assert product.python[-1] == "run_scenario.py"


def test_prior_popup_stops_main_before_anything_is_launched(product, capsys):
    product.open_dialogs = [TITLE]
    assert CHECK.main() == 1
    output = capsys.readouterr().out
    assert "PREVIO a esta ejecucion" in output and TITLE in output
    assert ALL_PASS not in output
    assert product.calls == [] and product.python == []


def test_prior_godot_process_stops_main_before_anything_is_launched(product, capsys):
    product.processes = [STRAY]
    assert CHECK.main() == 1
    output = capsys.readouterr().out
    assert "PREVIO a esta ejecucion" in output and "4242" in output
    assert product.calls == [] and product.python == []


def test_popup_from_one_check_fails_it_and_blocks_the_rest_as_prior(product, capsys):
    product.inject = {FIRST_SCRIPT: "popup"}
    assert CHECK.main() == 1
    output = capsys.readouterr().out
    assert ALL_PASS not in output
    assert output.count("fallo de ESTA ejecucion de Godot visto por el monitor") == 1
    assert "new Godot error dialog" in output
    assert "estado PREVIO a este lanzamiento" in output
    assert "restos de Godot al terminar" in output
    # Nothing was started after the popup, nested run included.
    assert product.calls[-1][0] == FIRST_SCRIPT


@pytest.mark.parametrize("target", [FIRST_SCRIPT, LAST_SCENE, NESTED])
@pytest.mark.parametrize(
    "fault",
    [
        "popup", "popup_after_clean_exit", "timeout", "residual_after_clean_exit",
        "foreign_after_clean_exit",
        "crash", "exit_zero_without_token", "exit_zero_compile_error",
    ],
)
def test_no_fault_on_any_route_is_reported_as_pass(product, capsys, target, fault):
    product.inject = {target: fault}
    assert CHECK.main() == 1
    output = capsys.readouterr().out
    assert ALL_PASS not in output and "PRODUCT CHECK(S) FAILED" in output


def test_godot_left_running_at_the_end_is_not_a_pass(product, capsys):
    product.processes_after_last_launch = [STRAY]
    assert CHECK.main() == 1
    output = capsys.readouterr().out
    assert ALL_PASS not in output
    assert "Sin procesos ni cuadros de Godot al terminar" in output
    assert "restos de Godot al terminar" in output and "4242" in output


def test_outer_run_scenario_timeout_is_a_failed_check_not_a_crash(product, monkeypatch):
    def expire(command, **kwargs):
        raise subprocess.TimeoutExpired(command, kwargs["timeout"])

    monkeypatch.setattr(CHECK.subprocess, "run", expire)
    code, count, fails, diagnostic = CHECK._run_run_scenario_smoke()
    assert (code, count, fails) == (1, 1, 1)
    assert "se paso del limite de %d s" % CHECK._RUN_SCENARIO_TIMEOUT_S in diagnostic


# ---------------------------------------------------------------------------
# Inventory of process launches in the sources
# ---------------------------------------------------------------------------

_LAUNCH_ATTRIBUTES = {"system", "popen", "startfile", "Popen", "call", "check_call", "check_output"}


def _process_launches(path: Path) -> tuple[set[tuple[str, str, str]], set[str], set[str]]:
    """subprocess calls as (function, call, argv[0]); imported modules; other launch APIs."""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    imported: set[str] = set()
    other: set[str] = set()
    total = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imported.add(node.module or "")
        elif isinstance(node, ast.Attribute) and (
            node.attr in _LAUNCH_ATTRIBUTES or re.fullmatch(r"(spawn|exec)[lv]p?e?", node.attr)
        ):
            other.add(node.attr)
        if _is_subprocess_call(node):
            total += 1
    calls: set[tuple[str, str, str]] = set()
    for function in tree.body:
        if not isinstance(function, ast.FunctionDef):
            continue
        for node in ast.walk(function):
            if _is_subprocess_call(node):
                argv = node.args[0]
                head = argv.elts[0] if isinstance(argv, ast.List) else argv
                calls.add((function.name, node.func.attr, ast.unparse(head)))
    assert total == len(calls), "subprocess call outside a top-level function, or duplicated"
    return calls, imported, other


def _is_subprocess_call(node: ast.AST) -> bool:
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "subprocess"
    )


def test_check_product_only_starts_python_through_subprocess():
    calls, _imported, other = _process_launches(CHECK_PATH)
    assert calls == {
        ("_run_python_script", "run", "sys.executable"),
        ("_run_test", "run", "sys.executable"),
        ("_run_run_scenario_smoke", "run", "sys.executable"),
    }
    assert other == set()


def test_run_scenario_and_the_launcher_have_no_process_api_of_their_own():
    for path in (RUNNER_PATH, LAUNCH_PATH):
        calls, imported, other = _process_launches(path)
        assert calls == set() and other == set(), path.name
        assert "subprocess" not in imported, path.name
    assert "mutation_audit._run_monitored(" in LAUNCH_PATH.read_text(encoding="utf-8")
