"""The monitor terminates what it launched, and nothing else.

Until 2026-10-01 the cleanup of ``mutation_audit._run_monitored`` ran
``taskkill`` on every process whose image name started with ``Godot``: an
editor opened while a check was running would have been killed as "residue".
Ownership is now a Windows job object holding the launched process and its
descendants; a name is only a reason to look at a process, never to kill it.

No Godot is involved. Harmless Python children stand in for the launched
process and its descendants, and a live process owned by the test stands in
for somebody else's Godot: the name scan is scripted to report its pid. The
scripted scan never returns a pid this file did not create.
"""

from __future__ import annotations

import ctypes
import os
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path
from types import SimpleNamespace

import pytest

from scripts import godot_monitored_launch
from tools import mutation_audit


pytestmark = pytest.mark.skipif(os.name != "nt", reason="process ownership uses a Windows job object")

TITLE = "Godot_v4.7.1-stable_win64.exe - Error de la aplicación"
SLEEPER = "import time; time.sleep(120)"
QUIET = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}


def _pid_alive(pid: int) -> bool:
    handle, _error = mutation_audit._open_process_handle(pid)
    if handle is None:
        return False
    kernel32 = ctypes.windll.kernel32
    try:
        code = wintypes.DWORD()
        kernel32.GetExitCodeProcess(wintypes.HANDLE(handle), ctypes.byref(code))
        return code.value == mutation_audit._STILL_ACTIVE
    finally:
        kernel32.CloseHandle(wintypes.HANDLE(handle))


def _child_with_descendant(marker: Path, *, share_output: bool, then: str) -> str:
    """Launched process: starts a long-lived descendant, records its pid, then ``then``."""
    handles = "" if share_output else ", stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL"
    return (
        "import pathlib, subprocess, sys, time\n"
        f"descendant = subprocess.Popen([sys.executable, '-c', {SLEEPER!r}]{handles})\n"
        f"pathlib.Path({str(marker)!r}).write_text(str(descendant.pid), encoding='utf-8')\n"
        f"{then}\n"
    )


@pytest.fixture(autouse=True)
def scans(monkeypatch):
    """Scripted window and name scans, so no real Godot can enter these tests."""
    state = SimpleNamespace(dialogs=lambda: [], godot=lambda: [])
    monkeypatch.setattr(mutation_audit, "_windows_godot_error_dialogs", lambda: state.dialogs())
    monkeypatch.setattr(mutation_audit, "_godot_processes", lambda: state.godot())
    monkeypatch.setattr(mutation_audit, "_POST_EXIT_OBSERVATION_S", 0.6)
    monkeypatch.setattr(mutation_audit, "_OWNED_DESCENDANT_DRAIN_S", 2.0)
    monkeypatch.delenv(godot_monitored_launch.HEALTH_LOG_ENV, raising=False)
    monkeypatch.delenv(godot_monitored_launch.MIN_AVAILABLE_GIB_ENV, raising=False)
    return state


@pytest.fixture
def foreign_godot():
    """A live process of this test that the name scan can report as someone else's Godot."""
    process = subprocess.Popen([sys.executable, "-c", SLEEPER], **QUIET)
    record = {"image_name": "Godot_v4.7.1-stable_win64.exe", "pid": process.pid}
    yield SimpleNamespace(process=process, pid=process.pid, record=record)
    process.kill()
    process.wait()


def _appears_after_launch(monkeypatch, scans, foreign_godot) -> None:
    real_start = mutation_audit._start_without_windows_error_ui

    def start(command, environment):
        started = real_start(command, environment)
        scans.godot = lambda: [dict(foreign_godot.record)]
        return started

    monkeypatch.setattr(mutation_audit, "_start_without_windows_error_ui", start)


def _pids(records) -> list[int]:
    return [record["pid"] for record in records]


def test_clean_run_terminates_nothing_and_owns_its_launched_process():
    completed, health = mutation_audit._run_monitored([sys.executable, "-c", "print('ok')"], 30)
    assert completed.returncode == 0 and "ok" in completed.stdout
    assert health["process_ownership"] == "job-object"
    assert health["residual_godot_processes"] == [] and health["cleanup_terminated_pids"] == []
    assert health["foreign_godot_processes"] == []
    assert [item["exit_code"] for item in health["observed_godot_processes"]] == [0]
    assert mutation_audit._runtime_health_errors(health) == []


def test_own_helper_that_finishes_in_time_is_waited_for_and_is_not_a_fault(monkeypatch, tmp_path):
    """The engine starts chart helpers when it exits: they finish their work, nothing is killed."""
    monkeypatch.setattr(mutation_audit, "_OWNED_DESCENDANT_DRAIN_S", 30.0)
    done = tmp_path / "helper_done.txt"
    helper = f"import pathlib, time; time.sleep(3); pathlib.Path({str(done)!r}).write_text('done', encoding='utf-8')"
    child = (
        "import subprocess, sys\n"
        f"subprocess.Popen([sys.executable, '-c', {helper!r}], "
        "stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
        "print('launched')\n"
    )
    completed, health = mutation_audit._run_monitored([sys.executable, "-c", child], 30)

    assert completed.returncode == 0 and "launched" in completed.stdout
    assert done.read_text(encoding="utf-8") == "done"  # it was allowed to finish
    assert health["residual_godot_processes"] == [] and health["cleanup_terminated_pids"] == []
    assert health["process_quiescent"] is True and health["timed_out"] is False
    assert 1.5 <= health["owned_descendant_wait_s"] < 20.0
    assert health["owned_process_total"] >= 2
    assert mutation_audit._runtime_health_errors(health) == []


def test_own_descendant_left_running_is_terminated_and_reported(tmp_path):
    marker = tmp_path / "descendant.pid"
    child = _child_with_descendant(marker, share_output=False, then="print('done')")
    completed, health = mutation_audit._run_monitored([sys.executable, "-c", child], 30)
    descendant = int(marker.read_text(encoding="utf-8"))

    assert completed.returncode == 0 and "done" in completed.stdout
    assert health["timed_out"] is False
    assert descendant in _pids(health["residual_godot_processes"])
    assert descendant in health["cleanup_terminated_pids"]
    assert health["process_quiescent"] is False
    assert not _pid_alive(descendant)
    assert any("residual" in error for error in mutation_audit._runtime_health_errors(health))


def test_own_descendant_holding_the_output_does_not_wait_for_the_timeout(tmp_path):
    marker = tmp_path / "descendant.pid"
    child = _child_with_descendant(marker, share_output=True, then="print('done', flush=True)")
    started = time.monotonic()
    completed, health = mutation_audit._run_monitored([sys.executable, "-c", child], 40)
    elapsed = time.monotonic() - started
    descendant = int(marker.read_text(encoding="utf-8"))

    assert elapsed < 20 and health["timed_out"] is False
    assert completed.returncode == 0 and "done" in completed.stdout
    assert descendant in _pids(health["residual_godot_processes"])
    assert descendant in health["cleanup_terminated_pids"]
    assert not _pid_alive(descendant)


def test_foreign_godot_that_appears_after_launch_survives_and_contaminates(
    monkeypatch, scans, foreign_godot
):
    _appears_after_launch(monkeypatch, scans, foreign_godot)
    completed, health = mutation_audit._run_monitored(
        [sys.executable, "-c", "import time; time.sleep(1.5); print('ok')"], 30
    )

    assert foreign_godot.process.poll() is None and _pid_alive(foreign_godot.pid)
    assert completed.returncode == 0
    assert _pids(health["foreign_godot_processes"]) == [foreign_godot.pid]
    assert foreign_godot.pid not in _pids(health["observed_godot_processes"])
    assert health["residual_godot_processes"] == [] and health["cleanup_terminated_pids"] == []
    assert health["process_quiescent"] is True
    errors = mutation_audit._runtime_health_errors(health)
    assert len(errors) == 1 and "foreign" in errors[0] and "contaminated" in errors[0]


def test_new_dialog_fails_the_run_and_kills_only_the_owned_tree(
    monkeypatch, scans, foreign_godot, tmp_path
):
    marker = tmp_path / "descendant.pid"
    _appears_after_launch(monkeypatch, scans, foreign_godot)
    scans.dialogs = lambda: [TITLE] if marker.exists() else []  # clean before the launch
    child = _child_with_descendant(marker, share_output=False, then="time.sleep(120)")
    completed, health = mutation_audit._run_monitored([sys.executable, "-c", child], 60)
    descendant = int(marker.read_text(encoding="utf-8"))

    assert health["error_dialogs"] == [TITLE] and health["timed_out"] is False
    assert completed.returncode == 1  # terminated by the monitor
    assert any("popup detected" in error for error in mutation_audit._runtime_health_errors(health))
    assert not _pid_alive(descendant)
    assert descendant in health["cleanup_terminated_pids"]
    assert foreign_godot.process.poll() is None and _pid_alive(foreign_godot.pid)
    assert foreign_godot.pid not in health["cleanup_terminated_pids"]
    assert _pids(health["foreign_godot_processes"]) == [foreign_godot.pid]


def test_timeout_kills_only_the_owned_tree(monkeypatch, scans, foreign_godot, tmp_path):
    marker = tmp_path / "descendant.pid"
    _appears_after_launch(monkeypatch, scans, foreign_godot)
    child = _child_with_descendant(marker, share_output=True, then="time.sleep(120)")
    completed, health = mutation_audit._run_monitored([sys.executable, "-c", child], 3)
    descendant = int(marker.read_text(encoding="utf-8"))

    assert health["timed_out"] is True and completed.returncode == 1
    assert not _pid_alive(descendant)
    assert descendant in health["cleanup_terminated_pids"]
    assert foreign_godot.process.poll() is None and _pid_alive(foreign_godot.pid)
    assert foreign_godot.pid not in health["cleanup_terminated_pids"]


def test_prior_dialog_blocks_the_launch_and_touches_nothing(monkeypatch, scans, foreign_godot):
    scans.dialogs = lambda: [TITLE]
    scans.godot = lambda: [dict(foreign_godot.record)]

    def must_not_start(*_args, **_kwargs):
        raise AssertionError("a process was started behind a prior popup")

    monkeypatch.setattr(mutation_audit, "_start_without_windows_error_ui", must_not_start)
    with pytest.raises(mutation_audit.PreexistingGodotErrorDialog):
        mutation_audit._run_monitored([sys.executable, "-c", "pass"], 10)
    assert foreign_godot.process.poll() is None and _pid_alive(foreign_godot.pid)


def test_prior_godot_blocks_the_launcher_and_is_left_untouched(monkeypatch, scans, foreign_godot):
    scans.godot = lambda: [dict(foreign_godot.record)]

    def must_not_start(*_args, **_kwargs):
        raise AssertionError("a process was started with a Godot already running")

    monkeypatch.setattr(mutation_audit, "_start_without_windows_error_ui", must_not_start)
    result = godot_monitored_launch.run([sys.executable, "-c", "pass"], 10)

    assert result.launched is False and result.health is None
    assert len(result.preexisting) == 1 and str(foreign_godot.pid) in result.preexisting[0]
    assert foreign_godot.process.poll() is None and _pid_alive(foreign_godot.pid)


def test_launcher_reports_a_foreign_godot_as_a_fault_of_the_run(monkeypatch, scans, foreign_godot):
    _appears_after_launch(monkeypatch, scans, foreign_godot)
    result = godot_monitored_launch.run(
        [sys.executable, "-c", "import time; time.sleep(1.5); print('ok')"], 30
    )

    assert result.launched is True and result.returncode == 0 and result.preexisting == ()
    assert len(result.faults) == 1 and "foreign Godot processes appeared" in result.faults[0]
    assert foreign_godot.process.poll() is None and _pid_alive(foreign_godot.pid)


def test_nothing_runs_when_ownership_cannot_be_established(monkeypatch, tmp_path):
    marker = tmp_path / "ran.txt"

    def no_job(self, process):
        time.sleep(1.5)  # long enough for a child that was not suspended to run
        raise OSError("job objects unavailable")

    monkeypatch.setattr(mutation_audit._OwnedProcessTree, "__init__", no_job)
    child = f"import pathlib; pathlib.Path({str(marker)!r}).write_text('ran', encoding='utf-8')"
    with pytest.raises(OSError, match="job objects unavailable"):
        mutation_audit._run_monitored([sys.executable, "-c", child], 10)
    assert not marker.exists()  # created suspended, killed before it ran

    result = godot_monitored_launch.run([sys.executable, "-c", child], 10)
    assert result.launched is False and "could not be started" in result.faults[0]
    assert not marker.exists()


def test_the_test_launcher_rejects_a_run_with_a_foreign_godot():
    from tests.godot_runtime_launcher import _health_errors

    health = {
        "console_wrapper_bypassed": True, "windows_error_ui_suppressed": True,
        "wrapper_exit_code": 0, "timed_out": False, "error_dialogs": [],
        "observed_godot_processes": [], "residual_godot_processes": [],
        "process_quiescent": True,
    }
    assert _health_errors(health, {0}) == []
    health["foreign_godot_processes"] = [{"image_name": "Godot_v4.7.1-stable_win64.exe", "pid": 1}]
    errors = _health_errors(health, {0})
    assert len(errors) == 1 and "foreign Godot processes" in errors[0]


def test_the_monitor_has_no_way_to_kill_by_name():
    source = Path(mutation_audit.__file__).read_text(encoding="utf-8")
    assert "taskkill" not in source
    assert not hasattr(mutation_audit, "_terminate_observed_godot_processes")
    monitored = source[source.index("def _run_monitored("):source.index("def _runtime_health_errors(")]
    # The one direct kill left is of the process it just created, when it cannot own it.
    assert monitored.count(".kill()") == 1
    assert monitored.index("process.kill()") < monitored.index("owned_pids: set[int]")
    assert "tree.terminate()" in monitored
