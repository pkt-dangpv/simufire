"""Single monitored Godot launch point for check_product.py and run_scenario.py.

Both scripts used to call ``subprocess.run`` on Godot. A native crash on that
path leaves a Windows hard-error popup that nobody watches, and the popup is
later attributed to healthy runs (2026-09-29, see
``docs/validation/G3_GODOT_NATIVE_POPUP_DIAGNOSIS_2026-09-29.md``). Every launch
now goes through ``tools.mutation_audit._run_monitored``: no window, Windows
error UI suppressed, popup scan during the run, residual-process check after it.

The monitor only terminates the process it launched and its descendants (a
Windows job object). A Godot it did not start - an open editor - is never
touched. It still makes a run ambiguous: an error popup is matched by title
and cannot be attributed to a process, and the editor competes for memory. So
a launch is refused while a popup or a Godot process predates it, reported as
pre-existing; and a foreign Godot that appears during a run is reported as a
fault of that run (contamination), without terminating it.

Environment (inherited by child Python processes, so nested launches follow):

* ``SIMUFIRE_GODOT_HEALTH_LOG``: file path; one JSON line per launch request.
* ``SIMUFIRE_GODOT_MIN_AVAILABLE_GIB``: refuse a launch while less physical
  memory than this is available. Unset means no memory gate: nothing here
  imposes the 6 GiB operating threshold of the monitored suites by default.
"""

from __future__ import annotations

import ctypes
import dataclasses
import json
import os
import sys
from pathlib import Path
from typing import Any, Sequence

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools import mutation_audit  # noqa: E402

HEALTH_LOG_ENV = "SIMUFIRE_GODOT_HEALTH_LOG"
MIN_AVAILABLE_GIB_ENV = "SIMUFIRE_GODOT_MIN_AVAILABLE_GIB"


class _MemoryStatus(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
        ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
        ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


def _available_gib() -> float:
    if os.name != "nt":
        raise OSError("available memory can only be measured on Windows")
    state = _MemoryStatus()
    state.dwLength = ctypes.sizeof(state)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(state)):
        raise OSError("GlobalMemoryStatusEx failed")
    return state.ullAvailPhys / (1024 ** 3)


def memory_gate_fault() -> str:
    """Why the opt-in memory gate refuses a launch right now ('' if it does not)."""
    requested = os.environ.get(MIN_AVAILABLE_GIB_ENV)
    if not requested:
        return ""
    try:
        minimum = float(requested)
        available = _available_gib()
    except (OSError, ValueError) as exc:
        return f"memory gate {MIN_AVAILABLE_GIB_ENV}={requested!r} cannot be evaluated: {exc}"
    if available < minimum:
        return (
            f"memory gate: {available:.2f} GiB available, "
            f"{MIN_AVAILABLE_GIB_ENV}={minimum:g} required"
        )
    return ""


@dataclasses.dataclass(frozen=True)
class MonitoredGodotRun:
    """Outcome of one launch request.

    ``preexisting`` lists state that predates the launch (nothing was started).
    ``faults`` lists what went wrong with the run itself, whatever exit code
    the caller expects: a popup, a timeout, residue, a native crash, or Godot
    not starting at all.
    """

    launched: bool
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool
    preexisting: tuple[str, ...]
    faults: tuple[str, ...]
    health: dict[str, Any] | None


def preexisting_godot_state() -> list[str]:
    """Popups and Godot processes that exist right now, before any launch."""
    found: list[str] = []
    dialogs = mutation_audit._windows_godot_error_dialogs()
    if dialogs:
        found.append(
            "pre-existing Godot error dialog; it belongs to an earlier process. "
            "Accept it and check Event Viewer > System > Event ID 26 for its "
            f"origin: {dialogs}"
        )
    processes = mutation_audit._godot_processes()
    if processes:
        found.append(
            "pre-existing Godot processes (left untouched); an error dialog "
            f"could not be attributed with them running: {processes}"
        )
    return found


def infrastructure_faults(health: dict[str, Any]) -> list[str]:
    """Faults of the run itself, independent of the exit code a caller accepts."""
    faults: list[str] = []
    if os.name == "nt" and health.get("windows_error_ui_suppressed") is not True:
        faults.append("Windows application-error UI was not suppressed")
    if health.get("timed_out") is not False:
        faults.append("Godot run timed out")
    if health.get("error_dialogs") != []:
        faults.append(
            f"new Godot error dialog during this run: {health.get('error_dialogs')}"
        )
    if health.get("residual_godot_processes") != []:
        faults.append(
            "residual Godot processes after the run: "
            f"{health.get('residual_godot_processes')}"
        )
    if health.get("process_quiescent") is not True:
        faults.append("Godot process state did not become quiescent")
    if health.get("foreign_godot_processes", []) != []:
        faults.append(
            "foreign Godot processes appeared during this run (not terminated); "
            f"the run is contaminated: {health.get('foreign_godot_processes')}"
        )
    observed = health.get("observed_godot_processes")
    if not isinstance(observed, list):
        faults.append("observed Godot process inventory is missing")
    else:
        for process in observed:
            exit_code = process.get("exit_code") if isinstance(process, dict) else None
            if exit_code is None:
                faults.append(f"observed Godot exit code is missing: {process}")
            elif exit_code == mutation_audit._STATUS_ACCESS_VIOLATION:
                faults.append(f"Godot access violation 0x{exit_code:08X}: {process}")
    capture_failures = health.get("process_handle_capture_failures", [])
    if not isinstance(capture_failures, list):
        faults.append("process handle capture failure inventory is malformed")
    elif capture_failures:
        faults.append(f"Godot process handle capture failed: {capture_failures}")
    observed_s = health.get("post_exit_observation_s")
    if (
        not isinstance(observed_s, (int, float))
        or observed_s < mutation_audit._POST_EXIT_OBSERVATION_S
    ):
        faults.append("post-exit observation window is incomplete")
    return faults


def _append_health_log(command: list[str], result: MonitoredGodotRun) -> None:
    path = os.environ.get(HEALTH_LOG_ENV)
    if not path:
        return
    record = {
        "command": command,
        "launched": result.launched,
        "returncode": result.returncode,
        "timed_out": result.timed_out,
        "preexisting": list(result.preexisting),
        "faults": list(result.faults),
        "health": result.health,
    }
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=True) + "\n")


def _not_launched(
    command: list[str], *, preexisting: Sequence[str] = (), faults: Sequence[str] = ()
) -> MonitoredGodotRun:
    result = MonitoredGodotRun(
        launched=False, returncode=1, stdout="", stderr="", timed_out=False,
        preexisting=tuple(preexisting), faults=tuple(faults), health=None,
    )
    _append_health_log(command, result)
    return result


def run(
    command: list[str | Path],
    timeout_s: int,
    environment: dict[str, str] | None = None,
) -> MonitoredGodotRun:
    """Run one Godot command under the monitor. Never raises for a bad run."""
    argv = [str(argument) for argument in command]
    preexisting = preexisting_godot_state()
    if preexisting:
        return _not_launched(argv, preexisting=preexisting)
    short_of_memory = memory_gate_fault()
    if short_of_memory:
        return _not_launched(argv, faults=[short_of_memory])
    try:
        completed, health = mutation_audit._run_monitored(argv, timeout_s, environment)
    except mutation_audit.PreexistingGodotErrorDialog as exc:
        # Opened between the scan above and the monitor's own.
        return _not_launched(argv, preexisting=[f"pre-existing Godot error dialog: {exc}"])
    except OSError as exc:
        return _not_launched(argv, faults=[f"Godot could not be started: {exc}"])
    result = MonitoredGodotRun(
        launched=True,
        returncode=completed.returncode,
        stdout=completed.stdout or "",
        stderr=completed.stderr or "",
        timed_out=health.get("timed_out") is not False,
        preexisting=(),
        faults=tuple(infrastructure_faults(health)),
        health=health,
    )
    _append_health_log(argv, result)
    return result
