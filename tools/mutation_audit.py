#!/usr/bin/env python3
"""P1R5 fail-closed mutation campaign for required reference checks."""

from __future__ import annotations

import argparse
import contextlib
import csv
import ctypes
import datetime
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from ctypes import wintypes
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
REPORTS_DIR = ROOT / "sim/validation/reports"
REFERENCE_REPORT = REPORTS_DIR / "reference_checks.json"
AUDITOR_PATH = ROOT / "scripts/simulation/audit_mutation_trust.py"
VALIDATOR_PATH = ROOT / "scripts/simulation/validate_reference_cases.py"

MUTATION_MANIFEST: dict[str, dict[str, Any]] = {
    "M-HRR": {"case": "v2_sealed_room_o2_depletion", "checks": ["v2_sealed_room_o2_depletion_room_0_peak_hrr_kw", "v2_sealed_room_o2_depletion_time_room_0_o2_below_13pct_s", "v2_sealed_room_o2_depletion_time_room_0_o2_below_18pct_s"]},
    "M-ENTR": {"case": "cfast_single_room_closed", "checks": ["cfast_closed_t210_temp_upper_c", "cfast_closed_t300_temp_upper_c", "cfast_closed_rmse_temp_upper_c"]},
    "M-O2EXT": {"case": "v2_sealed_room_o2_depletion", "checks": ["v2_sealed_room_o2_depletion_room_0_final_o2", "v2_sealed_room_o2_depletion_time_room_0_o2_below_13pct_s", "v2_sealed_room_o2_depletion_time_room_0_o2_below_18pct_s"]},
    "M-YCO": {"case": "v4_co_remote_rooms", "checks": ["v4_co_remote_rooms_room_1_peak_co_upper_ppm", "v4_co_remote_rooms_room_2_peak_co_upper_ppm", "v4_co_remote_rooms_time_room_1_co_upper_above_1200_s", "v4_co_remote_rooms_time_room_2_co_upper_above_200_s"]},
    "M-YHCN": {"case": "pu_sofa_fec_incapacitation", "checks": ["pu_sofa_fec_incapacitation_room_0_peak_hcn_upper_ppm"]},
    "M-WALL": {"case": "cfast_single_room_closed", "checks": ["cfast_closed_t210_temp_upper_c", "cfast_closed_t300_temp_upper_c", "cfast_closed_rmse_temp_upper_c"]},
    "M-VENT": {"case": "cfast_pool_fire_open", "checks": ["cfast_pool_t60_o2", "cfast_pool_t120_o2", "cfast_pool_t300_o2", "cfast_pool_rmse_temp_upper_c"]},
    "M-PRES": {"case": "cfast_single_room_closed", "checks": ["cfast_closed_t120_pressure_pa"]},
}

_GODOT_CANDIDATES = (
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
)
_FORBIDDEN_LOG_PATTERNS = {
    "SCRIPT ERROR": re.compile(r"(?im)^\s*SCRIPT ERROR\b"),
    "Parse Error": re.compile(r"(?im)^\s*(?:SCRIPT )?ERROR:.*Parse Error\b|^\s*Parse Error\b"),
    "ERROR:": re.compile(r"(?im)^\s*ERROR:"),
    "Segmentation fault": re.compile(r"(?i)\bSegmentation fault\b"),
    "crash": re.compile(r"(?i)\b(?:Godot|engine|process)\s+crash(?:ed|ing)?\b|^\s*CRASH(?:ED)?\b", re.MULTILINE),
}
_RUNTIME_HEALTH_CONTRACT = "windows-window-process-exit-v2"
_POST_EXIT_OBSERVATION_S = 2.0
# The engine starts helpers of its own when it exits (cmd.exe /c python for the
# charts; measured 7-35 s on 2026-10-01). They are descendants doing their job,
# not residue: they get this long to finish before being terminated as hung.
_OWNED_DESCENDANT_DRAIN_S = 120.0
_WINDOW_POLL_S = 0.2
_PROCESS_SAMPLE_S = 1.0
_EXPECTED_GODOT_VERSION = "4.7.1.stable.official.a13da4feb"
_SEM_FAILCRITICALERRORS = 0x0001
_SEM_NOGPFAULTERRORBOX = 0x0002
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_SYNCHRONIZE = 0x00100000
_PROCESS_TERMINATE = 0x0001
_PROCESS_SET_QUOTA = 0x0100
_CREATE_SUSPENDED = 0x00000004
_TH32CS_SNAPTHREAD = 0x00000004
_THREAD_SUSPEND_RESUME = 0x0002
_INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
_JOB_BASIC_ACCOUNTING_INFORMATION = 1
_JOB_BASIC_PROCESS_ID_LIST = 3
_JOB_EXTENDED_LIMIT_INFORMATION = 9
_JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
_ERROR_INVALID_PARAMETER = 87
_STILL_ACTIVE = 259
_STATUS_ACCESS_VIOLATION = 0xC0000005


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _find_godot(requested: str | None) -> Path:
    candidates = [Path(requested)] if requested else []
    if os.environ.get("GODOT_EXE"):
        candidates.append(Path(os.environ["GODOT_EXE"]))
    candidates.extend(_GODOT_CANDIDATES)
    for candidate in candidates:
        if candidate.is_file():
            if "console" not in candidate.name.lower():
                raise RuntimeError(f"Godot executable is not the console build: {candidate}")
            return candidate.resolve()
    raise RuntimeError("Godot 4.7.1 console executable not found")


def _godot_processes() -> list[dict[str, Any]]:
    if os.name != "nt":
        return []
    completed = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH", "/FI", "IMAGENAME eq Godot*"],
        capture_output=True, text=True, check=False,
    )
    records: list[dict[str, Any]] = []
    for row in csv.reader(completed.stdout.splitlines()):
        if len(row) < 2 or not row[0].lower().startswith("godot"):
            continue
        try:
            pid = int(row[1])
        except ValueError:
            continue
        records.append({"image_name": row[0], "pid": pid})
    return sorted(records, key=lambda item: (item["image_name"].lower(), item["pid"]))


def _is_godot_error_window_title(title: str) -> bool:
    normalized = "".join(
        character
        for character in unicodedata.normalize("NFKD", title)
        if not unicodedata.combining(character)
    ).casefold()
    if "godot" not in normalized:
        return False
    return any(
        marker in normalized
        for marker in (
            "application error",
            "error de la aplicacion",
            "has stopped working",
            "dejo de funcionar",
        )
    )


def _enum_windows_failed(enum_result: int, last_error: int) -> bool:
    return not bool(enum_result) and int(last_error) != 0


def _windows_godot_error_dialogs() -> list[str]:
    if os.name != "nt":
        return []

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    titles: list[str] = []
    callback_errors: list[str] = []
    callback_type = ctypes.WINFUNCTYPE(
        wintypes.BOOL, wintypes.HWND, wintypes.LPARAM, use_last_error=True
    )
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowTextW.restype = ctypes.c_int

    @callback_type
    def collect(hwnd, _lparam):
        try:
            length = user32.GetWindowTextLengthW(hwnd)
            if length <= 0:
                return True
            buffer = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buffer, length + 1)
            if _is_godot_error_window_title(buffer.value):
                titles.append(buffer.value)
            return True
        except Exception as exc:
            callback_errors.append(repr(exc))
            return False

    ctypes.set_last_error(0)
    enum_result = int(user32.EnumWindows(collect, 0))
    last_error = ctypes.get_last_error()
    if callback_errors:
        raise RuntimeError(
            "EnumWindows callback failed: " + "; ".join(callback_errors)
        )
    if _enum_windows_failed(enum_result, last_error):
        raise ctypes.WinError(last_error)
    return sorted(set(titles))


class _JobLimits(ctypes.Structure):
    """JOBOBJECT_EXTENDED_LIMIT_INFORMATION."""

    class _Basic(ctypes.Structure):
        _fields_ = [
            ("PerProcessUserTimeLimit", ctypes.c_int64),
            ("PerJobUserTimeLimit", ctypes.c_int64),
            ("LimitFlags", wintypes.DWORD),
            ("MinimumWorkingSetSize", ctypes.c_size_t),
            ("MaximumWorkingSetSize", ctypes.c_size_t),
            ("ActiveProcessLimit", wintypes.DWORD),
            ("Affinity", ctypes.c_size_t),
            ("PriorityClass", wintypes.DWORD),
            ("SchedulingClass", wintypes.DWORD),
        ]

    _fields_ = [
        ("BasicLimitInformation", _Basic),
        ("IoInfo", ctypes.c_uint64 * 6),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


class _JobAccounting(ctypes.Structure):
    """JOBOBJECT_BASIC_ACCOUNTING_INFORMATION."""

    _fields_ = [
        ("Times", ctypes.c_int64 * 4),
        ("TotalPageFaultCount", wintypes.DWORD),
        ("TotalProcesses", wintypes.DWORD),
        ("ActiveProcesses", wintypes.DWORD),
        ("TotalTerminatedProcesses", wintypes.DWORD),
    ]


class _JobProcessIds(ctypes.Structure):
    """JOBOBJECT_BASIC_PROCESS_ID_LIST with room for 1024 ids."""

    _fields_ = [
        ("NumberOfAssignedProcesses", wintypes.DWORD),
        ("NumberOfProcessIdsInList", wintypes.DWORD),
        ("ProcessIdList", ctypes.c_size_t * 1024),
    ]


class _ThreadEntry(ctypes.Structure):
    """THREADENTRY32."""

    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ThreadID", wintypes.DWORD),
        ("th32OwnerProcessID", wintypes.DWORD),
        ("tpBasePri", wintypes.LONG),
        ("tpDeltaPri", wintypes.LONG),
        ("dwFlags", wintypes.DWORD),
    ]


def _job_api():
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    handle, dword, bool_ = wintypes.HANDLE, wintypes.DWORD, wintypes.BOOL
    for name, restype, argtypes in (
        ("CreateJobObjectW", handle, [ctypes.c_void_p, wintypes.LPCWSTR]),
        ("SetInformationJobObject", bool_, [handle, ctypes.c_int, ctypes.c_void_p, dword]),
        ("QueryInformationJobObject", bool_, [handle, ctypes.c_int, ctypes.c_void_p, dword, ctypes.c_void_p]),
        ("AssignProcessToJobObject", bool_, [handle, handle]),
        ("TerminateJobObject", bool_, [handle, wintypes.UINT]),
        ("OpenProcess", handle, [dword, bool_, dword]),
        ("QueryFullProcessImageNameW", bool_, [handle, dword, wintypes.LPWSTR, ctypes.POINTER(dword)]),
        ("CreateToolhelp32Snapshot", handle, [dword, dword]),
        ("Thread32First", bool_, [handle, ctypes.POINTER(_ThreadEntry)]),
        ("Thread32Next", bool_, [handle, ctypes.POINTER(_ThreadEntry)]),
        ("OpenThread", handle, [dword, bool_, dword]),
        ("ResumeThread", dword, [handle]),
        ("CloseHandle", bool_, [handle]),
    ):
        function = getattr(kernel32, name)
        function.restype, function.argtypes = restype, argtypes
    return kernel32


def _resume_process(api, pid: int) -> int:
    """Resume a process created suspended; return how many threads were reached.

    A process created suspended has exactly one thread, and it cannot go away.
    One that is already running (a stand-in in the tests) is left as it is:
    its threads may end between the snapshot and the open, and are skipped.
    """
    snapshot = api.CreateToolhelp32Snapshot(_TH32CS_SNAPTHREAD, 0)
    if snapshot in (None, _INVALID_HANDLE_VALUE):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        entry = _ThreadEntry()
        entry.dwSize = ctypes.sizeof(entry)
        resumed = 0
        more = api.Thread32First(snapshot, ctypes.byref(entry))
        while more:
            if entry.th32OwnerProcessID == pid:
                thread = api.OpenThread(_THREAD_SUSPEND_RESUME, False, entry.th32ThreadID)
                if thread:
                    try:
                        if api.ResumeThread(thread) != 0xFFFFFFFF:
                            resumed += 1
                    finally:
                        api.CloseHandle(thread)
            more = api.Thread32Next(snapshot, ctypes.byref(entry))
        return resumed
    finally:
        api.CloseHandle(snapshot)


class _OwnedProcessTree:
    """The launched process and its descendants: the only thing the monitor kills.

    On Windows the launched process is placed in a job object before it runs.
    The kernel adds every descendant to the job, so membership identifies them
    without matching names or parent ids, and terminating the job cannot reach
    a process this monitor did not start. A Godot that someone else opens
    while a run is in progress is never a member. Closing the job (also when
    this Python process dies) terminates whatever is left in it.
    """

    def __init__(self, process: subprocess.Popen[str]) -> None:
        self._process = process
        self._api = None
        self._job = None
        self._terminated = False
        if os.name != "nt":
            return
        api = _job_api()
        job = api.CreateJobObjectW(None, None)
        if not job:
            raise ctypes.WinError(ctypes.get_last_error())
        root = None
        try:
            limits = _JobLimits()
            limits.BasicLimitInformation.LimitFlags = _JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if not api.SetInformationJobObject(
                job, _JOB_EXTENDED_LIMIT_INFORMATION, ctypes.byref(limits), ctypes.sizeof(limits)
            ):
                raise ctypes.WinError(ctypes.get_last_error())
            root = api.OpenProcess(_PROCESS_SET_QUOTA | _PROCESS_TERMINATE, False, process.pid)
            if not root:
                raise ctypes.WinError(ctypes.get_last_error())
            if not api.AssignProcessToJobObject(job, root):
                raise ctypes.WinError(ctypes.get_last_error())
            if not _resume_process(api, process.pid) and process.poll() is None:
                raise OSError(f"process {process.pid} could not be resumed")
        except OSError:
            api.CloseHandle(job)
            raise
        finally:
            if root:
                api.CloseHandle(root)
        self._api, self._job = api, job

    def member_pids(self) -> list[int]:
        """Pids of the owned processes that are still alive."""
        if self._job is None:
            return [self._process.pid] if self._process.poll() is None and not self._terminated else []
        ids = _JobProcessIds()
        if not self._api.QueryInformationJobObject(
            self._job, _JOB_BASIC_PROCESS_ID_LIST, ctypes.byref(ids), ctypes.sizeof(ids), None
        ):
            raise ctypes.WinError(ctypes.get_last_error())
        return sorted(int(ids.ProcessIdList[i]) for i in range(ids.NumberOfProcessIdsInList))

    def members(self) -> list[dict[str, Any]]:
        return [{"image_name": self._image_name(pid), "pid": pid} for pid in self.member_pids()]

    def total_processes(self) -> int | None:
        """Every process that was ever in the tree, short-lived ones included."""
        if self._job is None:
            return None
        accounting = _JobAccounting()
        if not self._api.QueryInformationJobObject(
            self._job, _JOB_BASIC_ACCOUNTING_INFORMATION,
            ctypes.byref(accounting), ctypes.sizeof(accounting), None,
        ):
            raise ctypes.WinError(ctypes.get_last_error())
        return int(accounting.TotalProcesses)

    def terminate(self) -> list[int]:
        """Terminate the owned processes that are alive; return their pids."""
        alive = self.member_pids()
        if self._job is None:
            if alive:
                self._process.kill()
                self._terminated = True
            return alive
        if not alive:
            return []
        if not self._api.TerminateJobObject(self._job, 1):
            raise ctypes.WinError(ctypes.get_last_error())
        deadline = time.monotonic() + 5.0
        while self.member_pids() and time.monotonic() < deadline:
            time.sleep(0.05)
        return alive

    def close(self) -> None:
        if self._job is not None:
            self._api.CloseHandle(self._job)
            self._job = None

    def _image_name(self, pid: int) -> str:
        if pid == self._process.pid:
            return Path(str(self._process.args[0])).name
        if self._job is None:
            return ""
        handle = self._api.OpenProcess(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return ""
        try:
            size = wintypes.DWORD(1024)
            buffer = ctypes.create_unicode_buffer(size.value)
            if not self._api.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
                return ""
            return Path(buffer.value).name
        finally:
            self._api.CloseHandle(handle)


def _open_process_handle(pid: int) -> tuple[int | None, int]:
    if os.name != "nt":
        return None, 0
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    ctypes.set_last_error(0)
    handle = kernel32.OpenProcess(
        _PROCESS_QUERY_LIMITED_INFORMATION | _SYNCHRONIZE, False, pid
    )
    if handle:
        return int(handle), 0
    return None, int(ctypes.get_last_error())


def _sample_godot_processes(
    observed: dict[tuple[str, int], dict[str, Any]],
    handles: dict[int, int],
    capture_races: dict[tuple[str, int], dict[str, Any]],
    capture_failures: dict[tuple[str, int], dict[str, Any]],
) -> list[dict[str, Any]]:
    current = _godot_processes()
    for record in current:
        key = (record["image_name"], record["pid"])
        if record["pid"] in handles:
            observed[key] = record
            continue
        handle, open_error = _open_process_handle(record["pid"])
        if handle is None:
            capture = {
                **record,
                "open_process_error": open_error,
                "capture_status": (
                    "exited_before_handle_capture"
                    if open_error == _ERROR_INVALID_PARAMETER
                    else "open_process_failed"
                ),
            }
            if open_error == _ERROR_INVALID_PARAMETER:
                capture_races[key] = capture
            else:
                capture_failures[key] = capture
            continue
        handles[record["pid"]] = handle
        observed[key] = record
        capture_races.pop(key, None)
        capture_failures.pop(key, None)
    return current


def _collect_process_exit_codes(
    observed: dict[tuple[str, int], dict[str, Any]], handles: dict[int, int]
) -> list[dict[str, Any]]:
    if os.name != "nt":
        return list(observed.values())
    kernel32 = ctypes.windll.kernel32
    records: list[dict[str, Any]] = []
    try:
        for record in observed.values():
            item = dict(record)
            handle = handles.get(record["pid"])
            exit_code = ctypes.c_ulong()
            if handle:
                kernel32.WaitForSingleObject(handle, 5000)
                if kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                    item["exit_code"] = (
                        None if exit_code.value == _STILL_ACTIVE else exit_code.value
                    )
                else:
                    item["exit_code"] = None
            else:
                item["exit_code"] = None
            records.append(item)
    finally:
        for handle in handles.values():
            kernel32.CloseHandle(handle)
    return sorted(records, key=lambda item: (item["image_name"].lower(), item["pid"]))


def _resolve_monitored_executable(executable: Path) -> tuple[Path, bool]:
    """Bypass Godot's Windows console wrapper for monitored launches.

    The small ``*_console.exe`` binary starts the GUI-subsystem sibling. Native
    failures in that child can surface an application-error dialog independently
    of ``CREATE_NO_WINDOW`` on the wrapper. Launching the sibling directly keeps
    the same engine and arguments under the existing process/window supervisor.
    """
    executable = Path(executable)
    suffix = "_console.exe"
    if os.name != "nt" or not executable.name.lower().endswith(suffix):
        return executable, False
    engine = executable.with_name(executable.name[: -len(suffix)] + ".exe")
    if not engine.is_file():
        raise FileNotFoundError(
            f"Godot GUI sibling missing for monitored console wrapper: {engine}"
        )
    return engine, True


def _start_without_windows_error_ui(
    command: list[str], environment: dict[str, str] | None
) -> tuple[subprocess.Popen[str], bool]:
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    if os.name != "nt":
        return (
            subprocess.Popen(
                command,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=environment,
                creationflags=creationflags,
            ),
            False,
        )

    kernel32 = ctypes.windll.kernel32
    requested_mode = _SEM_FAILCRITICALERRORS | _SEM_NOGPFAULTERRORBOX
    previous_mode = kernel32.SetErrorMode(requested_mode)
    kernel32.SetErrorMode(previous_mode | requested_mode)
    try:
        # Suspended: _OwnedProcessTree puts it in its job before it can run
        # or spawn anything, then resumes it.
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
            creationflags=creationflags | _CREATE_SUSPENDED,
        )
    finally:
        kernel32.SetErrorMode(previous_mode)
    return process, True


class PreexistingGodotErrorDialog(RuntimeError):
    """A Godot error popup was already open before this launch.

    Windows hard-error popups outlive the process that raised them until
    someone accepts them. The window scan matches by title, so a stale popup
    would be attributed to the next, healthy run and kill it (exit 1). The
    launcher refuses to start instead; detection during a run is unchanged.
    """


def _require_no_preexisting_error_dialogs() -> None:
    dialogs = _windows_godot_error_dialogs()
    if dialogs:
        raise PreexistingGodotErrorDialog(
            "Godot error dialog already open before launch; it belongs to an "
            "earlier process and would be misattributed to this run. Accept it "
            "and check Event Viewer > System > Event ID 26 for its origin "
            f"before relaunching: {dialogs}"
        )


def _run_monitored(
    command: list[str], timeout_s: int, environment: dict[str, str] | None = None
) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
    _require_no_preexisting_error_dialogs()
    requested_executable = Path(command[0])
    launched_executable, console_wrapper_bypassed = \
        _resolve_monitored_executable(requested_executable)
    launch_command = list(command)
    launch_command[0] = str(launched_executable)
    started = time.monotonic()
    started_at = datetime.datetime.now(datetime.UTC)
    observed: dict[tuple[str, int], dict[str, Any]] = {}
    handles: dict[int, int] = {}
    capture_races: dict[tuple[str, int], dict[str, Any]] = {}
    capture_failures: dict[tuple[str, int], dict[str, Any]] = {}
    dialogs: set[str] = set()
    timed_out = False
    terminated_pids: list[int] = []
    residual: list[dict[str, Any]] = []
    next_process_sample = 0.0
    process, windows_error_ui_suppressed = _start_without_windows_error_ui(
        launch_command, environment
    )
    try:
        tree = _OwnedProcessTree(process)
    except OSError:
        # Without ownership nothing could be cleaned up safely: do not run.
        process.kill()
        process.communicate()
        raise
    owned_pids: set[int] = {process.pid}

    def sample() -> None:
        # Names only say what to look at. Ownership comes from the job, read
        # on both sides of the name scan so a new descendant is not missed.
        owned_pids.update(tree.member_pids())
        _sample_godot_processes(observed, handles, capture_races, capture_failures)
        owned_pids.update(tree.member_pids())

    stdout = ""
    stderr = ""
    root_exited_at: float | None = None
    try:
        while True:
            dialogs.update(_windows_godot_error_dialogs())
            now = time.monotonic()
            if now >= next_process_sample or dialogs:
                sample()
                next_process_sample = now + _PROCESS_SAMPLE_S
            if dialogs:
                terminated_pids.extend(tree.terminate())
                stdout, stderr = process.communicate()
                break
            remaining = timeout_s - (now - started)
            if remaining <= 0:
                timed_out = True
                sample()
                terminated_pids.extend(tree.terminate())
                stdout, stderr = process.communicate()
                break
            if process.poll() is not None:
                # The launched process is gone but its output is still open:
                # a descendant holds it. Give it the drain time, no more.
                if root_exited_at is None:
                    root_exited_at = now
                elif now - root_exited_at >= _OWNED_DESCENDANT_DRAIN_S:
                    sample()
                    residual = tree.members()
                    terminated_pids.extend(tree.terminate())
                    stdout, stderr = process.communicate()
                    break
            try:
                stdout, stderr = process.communicate(
                    timeout=min(_WINDOW_POLL_S, remaining)
                )
                break
            except subprocess.TimeoutExpired:
                continue

        post_exit_started = time.monotonic()
        post_exit_deadline = post_exit_started + _POST_EXIT_OBSERVATION_S
        drain_deadline = (root_exited_at or post_exit_started) + _OWNED_DESCENDANT_DRAIN_S
        descendants_last_seen = post_exit_started
        while True:
            now = time.monotonic()
            descendants = bool(tree.member_pids())
            if descendants:
                descendants_last_seen = now
            # Past the fixed window, keep waiting only for owned descendants
            # that are still working, and only while nothing has gone wrong.
            if now >= post_exit_deadline and not (
                descendants and now < drain_deadline and not dialogs and not residual
            ):
                break
            dialogs.update(_windows_godot_error_dialogs())
            if now < post_exit_deadline or now >= next_process_sample:
                sample()
                next_process_sample = now + _PROCESS_SAMPLE_S
            time.sleep(_WINDOW_POLL_S)

        dialogs.update(_windows_godot_error_dialogs())
        if not residual:
            # Owned processes still alive after the drain time: hung. Only
            # these are terminated; a Godot seen by name that is not in the
            # tree is not.
            residual = tree.members()
            terminated_pids.extend(tree.terminate())
        owned_process_total = tree.total_processes()
    finally:
        tree.close()
    observed_with_exit = _collect_process_exit_codes(observed, handles)
    owned = [item for item in observed_with_exit if item["pid"] in owned_pids]
    foreign = [item for item in observed_with_exit if item["pid"] not in owned_pids]
    if all(item["pid"] != process.pid for item in owned):
        owned.append({
            "image_name": launched_executable.name,
            "pid": process.pid,
            "exit_code": process.returncode,
        })
    health = {
        "contract": _RUNTIME_HEALTH_CONTRACT,
        "requested_executable": str(requested_executable),
        "launched_executable": str(launched_executable),
        "console_wrapper_bypassed": console_wrapper_bypassed,
        "windows_error_ui_suppressed": windows_error_ui_suppressed,
        "started_at_utc": started_at.isoformat(),
        "ended_at_utc": datetime.datetime.now(datetime.UTC).isoformat(),
        "wrapper_exit_code": process.returncode,
        "timed_out": timed_out,
        "error_dialogs": sorted(dialogs),
        "process_ownership": "job-object" if os.name == "nt" else "launched-process-only",
        "owned_process_total": owned_process_total,
        "owned_descendant_wait_s": round(descendants_last_seen - post_exit_started, 3),
        "observed_godot_processes": sorted(
            owned, key=lambda item: (item["image_name"].lower(), item["pid"])
        ),
        "foreign_godot_processes": foreign,
        "process_handle_capture_races": sorted(
            capture_races.values(),
            key=lambda item: (item["image_name"].lower(), item["pid"]),
        ),
        "process_handle_capture_failures": sorted(
            capture_failures.values(),
            key=lambda item: (item["image_name"].lower(), item["pid"]),
        ),
        "residual_godot_processes": residual,
        "process_quiescent": not residual,
        "cleanup_terminated_pids": sorted(set(terminated_pids)),
        "post_exit_observation_s": round(time.monotonic() - post_exit_started, 3),
    }
    return subprocess.CompletedProcess(
        command, process.returncode, stdout, stderr
    ), health


def _runtime_health_errors(health: Any) -> list[str]:
    if not isinstance(health, dict):
        return ["runtime health record is missing"]
    errors: list[str] = []
    if health.get("contract") != _RUNTIME_HEALTH_CONTRACT:
        errors.append("runtime health contract is missing or unsupported")
    if os.name == "nt" and health.get("windows_error_ui_suppressed") is not True:
        errors.append("Windows application-error UI was not suppressed")
    if health.get("wrapper_exit_code") not in (0, 2):
        errors.append(f"Godot wrapper exited {health.get('wrapper_exit_code')}")
    if health.get("timed_out") is not False:
        errors.append("Godot run timed out")
    if health.get("error_dialogs") != []:
        errors.append(f"Godot application-error popup detected: {health.get('error_dialogs')}")
    if health.get("residual_godot_processes") != []:
        errors.append(
            f"residual Godot processes detected: {health.get('residual_godot_processes')}"
        )
    if health.get("foreign_godot_processes", []) != []:
        errors.append(
            "foreign Godot processes seen during the run (not terminated); the "
            f"run is contaminated: {health.get('foreign_godot_processes')}"
        )
    if health.get("process_quiescent") is not True:
        errors.append("Godot process state did not become quiescent")
    observed = health.get("observed_godot_processes")
    if not isinstance(observed, list):
        errors.append("observed Godot process inventory is missing")
    else:
        for process in observed:
            exit_code = process.get("exit_code") if isinstance(process, dict) else None
            if exit_code is None:
                errors.append("observed Godot child exit code is missing")
            elif exit_code == _STATUS_ACCESS_VIOLATION:
                errors.append(
                    f"Godot child access violation 0x{exit_code:08X}: {process}"
                )
            elif exit_code not in (0, 2):
                errors.append(f"Godot child exited 0x{exit_code:08X}: {process}")
    capture_races = health.get("process_handle_capture_races", [])
    if not isinstance(capture_races, list):
        errors.append("process handle capture race inventory is malformed")
    capture_failures = health.get("process_handle_capture_failures", [])
    if not isinstance(capture_failures, list):
        errors.append("process handle capture failure inventory is malformed")
    elif capture_failures:
        errors.append(f"Godot process handle capture failed: {capture_failures}")
    observed_s = health.get("post_exit_observation_s")
    if not isinstance(observed_s, (int, float)) or observed_s < _POST_EXIT_OBSERVATION_S:
        errors.append("post-exit observation window is incomplete")
    return errors


def _forbidden_log_markers(log_text: str) -> list[str]:
    return [
        marker
        for marker, pattern in _FORBIDDEN_LOG_PATTERNS.items()
        if pattern.search(log_text)
    ]


def _git_output(*args: str) -> str:
    completed = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed: {completed.stderr.strip()}"
        )
    return completed.stdout.strip()


def _require_godot_quiet_period(
    quiet_s: float = 15.0, timeout_s: float = 120.0
) -> None:
    started = time.monotonic()
    quiet_started = None
    last_seen: list[dict[str, Any]] = []
    while True:
        current = _godot_processes()
        now = time.monotonic()
        if current:
            last_seen = current
            quiet_started = None
        else:
            if quiet_started is None:
                quiet_started = now
            if now - quiet_started >= quiet_s:
                return
        if now - started >= timeout_s:
            raise RuntimeError(
                "Godot process state did not remain quiet for "
                f"{quiet_s:.1f}s before launch; last observed: {last_seen}"
            )
        time.sleep(_WINDOW_POLL_S)


def _verify_godot_version(godot: Path) -> tuple[str, dict[str, Any]]:
    _require_godot_quiet_period()
    completed, health = _run_monitored([str(godot), "--version"], 30)
    errors = _runtime_health_errors(health)
    version = completed.stdout.strip()
    if errors:
        raise RuntimeError("Godot version probe invalid: " + "; ".join(errors))
    if version != _EXPECTED_GODOT_VERSION:
        raise RuntimeError(
            f"Godot version mismatch: expected {_EXPECTED_GODOT_VERSION}, got {version!r}"
        )
    return version, health


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _build_case_command(
    godot: Path,
    case_name: str,
    report_path: Path,
    simulation_log_path: Path,
    mutant_id: str | None,
) -> list[str]:
    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        "--",
        f"--validation-case={case_name}",
        f"--validation-output={report_path}",
        f"--validation-simulation-log={simulation_log_path}",
    ]
    if mutant_id:
        command.append(f"--validation-mutate={mutant_id}")
    return command


def _run_case(
    godot: Path,
    godot_version: str,
    source_commit: str,
    case_name: str,
    destination: Path,
    mutant_id: str | None,
    timeout_s: int,
) -> dict[str, Any]:
    destination.mkdir(parents=True, exist_ok=True)
    report_path = destination / f"{case_name}.json"
    engine_log_path = destination / f"{case_name}.godot.log"
    log_path = destination / f"{case_name}.log"
    health_path = destination / f"{case_name}.runtime_health.json"
    appdata_path = destination / "appdata"
    appdata_path.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["APPDATA"] = str(appdata_path)
    command = _build_case_command(
        godot, case_name, report_path, log_path, mutant_id
    )
    case_path = ROOT / "sim/validation/cases" / f"{case_name}.json"
    case_blob_oid = _git_output("hash-object", str(case_path))
    started_wall = datetime.datetime.now(datetime.UTC)
    started = time.monotonic()
    completed, runtime_health = _run_monitored(command, timeout_s, environment)
    elapsed = time.monotonic() - started
    captured_log = completed.stdout
    if completed.stderr:
        captured_log += (
            "\n" if captured_log and not captured_log.endswith("\n") else ""
        ) + "[stderr]\n" + completed.stderr
    engine_log_path.write_text(captured_log, encoding="utf-8")
    runtime_health.update(
        {
            "godot_executable": str(godot),
            "godot_version": godot_version,
            "source_commit": source_commit,
            "case_path": case_path.relative_to(ROOT).as_posix(),
            "case_blob_oid": case_blob_oid,
            "case_sha256": _sha256(case_path),
            "command": command,
            "appdata": str(appdata_path),
            "stdout_bytes": len(completed.stdout.encode("utf-8")),
            "stdout_sha256": hashlib.sha256(completed.stdout.encode("utf-8")).hexdigest(),
            "stderr_bytes": len(completed.stderr.encode("utf-8")),
            "stderr_sha256": hashlib.sha256(completed.stderr.encode("utf-8")).hexdigest(),
        }
    )
    health_path.write_text(
        json.dumps(runtime_health, indent=2) + "\n", encoding="utf-8"
    )
    health_errors = _runtime_health_errors(runtime_health)
    if health_errors:
        raise RuntimeError(
            f"{case_name}/{mutant_id or 'CONTROL'} invalid runtime health: "
            + "; ".join(health_errors)
        )
    if completed.returncode not in (0, 2):
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} exited {completed.returncode}")
    needs_timeseries = case_name.startswith("cfast_")
    if not report_path.is_file() or not engine_log_path.is_file() or (needs_timeseries and not log_path.is_file()):
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} missing report or log")
    if report_path.stat().st_mtime < started_wall.timestamp() - 2:
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} produced a stale report")
    data = json.loads(report_path.read_text(encoding="utf-8"))
    if data.get("case") != case_name:
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} report case mismatch")
    evidence_log_path = log_path if log_path.is_file() else engine_log_path
    log_text = evidence_log_path.read_text(encoding="utf-8", errors="replace") + engine_log_path.read_text(encoding="utf-8", errors="replace")
    markers = _forbidden_log_markers(log_text)
    if markers:
        raise RuntimeError(f"{case_name}/{mutant_id or 'CONTROL'} forbidden log markers: {markers}")
    return {
        "case": case_name, "mutant": mutant_id, "command": command,
        "elapsed_s": round(elapsed, 3), "exit_code": completed.returncode,
        "report_path": report_path.as_posix(), "report_bytes": report_path.stat().st_size,
        "report_sha256": _sha256(report_path), "log_path": evidence_log_path.as_posix(),
        "log_bytes": evidence_log_path.stat().st_size, "log_sha256": _sha256(evidence_log_path),
        "engine_log_path": engine_log_path.as_posix(), "engine_log_bytes": engine_log_path.stat().st_size,
        "engine_log_sha256": _sha256(engine_log_path),
        "runtime_health_path": health_path.as_posix(),
        "runtime_health_bytes": health_path.stat().st_size,
        "runtime_health_sha256": _sha256(health_path),
        "runtime_health": runtime_health,
    }


def _record_existing(case_name: str, destination: Path, mutant_id: str | None = None) -> dict[str, Any] | None:
    report_path = destination / f"{case_name}.json"
    engine_log_path = destination / f"{case_name}.godot.log"
    simulation_log_path = destination / f"{case_name}.log"
    health_path = destination / f"{case_name}.runtime_health.json"
    needs_timeseries = case_name.startswith("cfast_")
    if not report_path.is_file() or not engine_log_path.is_file() or not health_path.is_file():
        return None
    if needs_timeseries and not simulation_log_path.is_file():
        return None
    data = json.loads(report_path.read_text(encoding="utf-8"))
    if data.get("case") != case_name:
        raise RuntimeError(f"{case_name}: resumed report case mismatch")
    evidence_log_path = simulation_log_path if simulation_log_path.is_file() else engine_log_path
    runtime_health = json.loads(health_path.read_text(encoding="utf-8"))
    health_errors = _runtime_health_errors(runtime_health)
    if health_errors:
        raise RuntimeError(
            f"{case_name}: reused runtime health is invalid: " + "; ".join(health_errors)
        )
    return {
        "case": case_name, "mutant": mutant_id, "command": ["REUSED_EXACT_BYTE_RUN"],
        "elapsed_s": 0.0, "exit_code": 0, "reused": True,
        "report_path": report_path.as_posix(), "report_bytes": report_path.stat().st_size,
        "report_sha256": _sha256(report_path), "log_path": evidence_log_path.as_posix(),
        "log_bytes": evidence_log_path.stat().st_size, "log_sha256": _sha256(evidence_log_path),
        "engine_log_path": engine_log_path.as_posix(), "engine_log_bytes": engine_log_path.stat().st_size,
        "engine_log_sha256": _sha256(engine_log_path),
        "runtime_health_path": health_path.as_posix(),
        "runtime_health_bytes": health_path.stat().st_size,
        "runtime_health_sha256": _sha256(health_path),
        "runtime_health": runtime_health,
    }


def _evaluate_with_overlay(
    overlay: Path, case_name: str, expected_check_count: int, *, mutated: bool = False
) -> dict[str, dict[str, Any]]:
    evaluation_root = overlay.parents[1] / "evaluations"
    evaluation_root.mkdir(parents=True, exist_ok=True)
    evaluation_dir = Path(tempfile.mkdtemp(prefix="simufire_mutation_eval_", dir=evaluation_root))
    try:
        for source in REPORTS_DIR.iterdir():
            if source.is_file() and source.suffix in (".json", ".log"):
                shutil.copyfile(source, evaluation_dir / source.name)
        for suffix in (".json", ".log"):
            source = overlay / f"{case_name}{suffix}"
            if source.is_file():
                shutil.copyfile(source, evaluation_dir / source.name)
        module_name = f"validate_reference_cases_mutation_{time.time_ns()}"
        validator = _load_module(VALIDATOR_PATH, module_name)
        validator.REPORTS_DIR = evaluation_dir
        validator._ARTIFACT_CACHE.clear()
        artifact_record = validator._artifact_record

        def relocated_artifact_record(path: Path) -> dict[str, Any]:
            record = artifact_record(path)
            # Preserve report identity after copying, but hash the evaluated bytes.
            if path.resolve().parent == evaluation_dir.resolve():
                record["path"] = validator._display_path(
                    (REPORTS_DIR / path.name).resolve()
                ).as_posix()
            return record

        validator._artifact_record = relocated_artifact_record
        output = io.StringIO()
        try:
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                exit_code = validator.main([], verify_gap_evidence=not mutated)
        finally:
            sys.modules.pop(module_name, None)
        if exit_code not in (0, 1):
            raise RuntimeError(f"reference evaluator exited {exit_code}: {output.getvalue()}")
        aggregate_path = evaluation_dir / "reference_checks.json"
        if not aggregate_path.is_file():
            raise RuntimeError("reference evaluator did not write an aggregate")
        aggregate = json.loads(aggregate_path.read_text(encoding="utf-8"))
        checks = aggregate.get("checks")
        if not isinstance(checks, list) or len(checks) != expected_check_count:
            raise RuntimeError("reference aggregate is missing or truncated")
        names = [item.get("name") for item in checks]
        if len(names) != len(set(names)):
            raise RuntimeError("reference aggregate contains duplicate check names")
        return {item["name"]: item for item in checks}
    finally:
        shutil.rmtree(evaluation_dir, ignore_errors=True)


def _evaluate_mutant(mutant_id: str, control_dir: Path, mutant_dir: Path, run_records: list[dict[str, Any]], canonical: dict[str, dict[str, Any]]) -> dict[str, Any]:
    contract = MUTATION_MANIFEST[mutant_id]
    case_name = contract["case"]
    expected_names = contract["checks"]
    if len(expected_names) != len(set(expected_names)):
        raise RuntimeError(f"{mutant_id}: duplicate names in mutation manifest")
    expected_check_count = len(canonical)
    control = _evaluate_with_overlay(control_dir, case_name, expected_check_count)
    mutated = _evaluate_with_overlay(mutant_dir, case_name, expected_check_count, mutated=True)
    missing = [name for name in expected_names if name not in control or name not in mutated]
    if missing:
        raise RuntimeError(f"{mutant_id}: missing checks: {missing}")
    non_required = [name for name in expected_names if not canonical.get(name, {}).get("required")]
    if non_required:
        raise RuntimeError(f"{mutant_id}: non-required manifest checks: {non_required}")
    negative_control_pass = all(control[name]["pass"] for name in expected_names)
    new_failures = [name for name in expected_names if control[name]["pass"] and not mutated[name]["pass"]]
    records = [record for record in run_records if record["case"] == case_name and record["mutant"] in (None, mutant_id)]
    return {
        "killed": bool(new_failures), "required_checks_evaluated": len(expected_names),
        "evaluated_check_names": expected_names, "new_failed_check_names": new_failures,
        "reports": records,
        "input_fresh": all(record["report_bytes"] > 0 and record["log_bytes"] > 0 for record in records),
        "manifest_complete": len(records) == 2, "negative_control_pass": negative_control_pass,
        "control_values": {name: control[name]["actual"] for name in expected_names},
        "mutant_values": {name: mutated[name]["actual"] for name in expected_names},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--output", type=Path, default=ROOT / "tools/reports/mutation_results.json")
    parser.add_argument("--evidence-dir", type=Path, default=ROOT / "runs/motor_post_audit_p1_remediation_p1r5/mutation_campaign")
    parser.add_argument("--resume", action="store_true", help="Reuse complete exact-byte controls already present in evidence-dir")
    parser.add_argument("--evaluate-only", action="store_true", help="Evaluate a complete existing evidence directory without Godot runs")
    args = parser.parse_args(argv)
    if _godot_processes():
        print("ERROR: residual Godot processes exist before the campaign", file=sys.stderr)
        return 2
    try:
        if _git_output("status", "--porcelain"):
            raise RuntimeError("mutation campaign requires a clean worktree")
        godot = _find_godot(args.godot)
        godot_version, version_probe_health = _verify_godot_version(godot)
        source_commit = _git_output("rev-parse", "HEAD")
        source_tree_oid = _git_output("rev-parse", "HEAD^{tree}")
        canonical_data = json.loads(REFERENCE_REPORT.read_text(encoding="utf-8"))
        canonical_checks = {item["name"]: item for item in canonical_data["checks"]}
        required_count = sum(1 for item in canonical_checks.values() if item["required"])
        if len(canonical_checks) != len(canonical_data["checks"]):
            raise RuntimeError("canonical reference contract contains duplicate check names")
        if required_count != canonical_data.get("required_count"):
            raise RuntimeError("canonical required count disagrees with the check rows")
        if canonical_data.get("failed_required_count") != 0:
            raise RuntimeError("canonical reference contract has failed required checks")
        evidence_dir = args.evidence_dir.resolve()
        if evidence_dir.exists() and not args.resume:
            raise RuntimeError(f"evidence directory already exists: {evidence_dir}")
        control_root, mutant_root = evidence_dir / "controls", evidence_dir / "mutants"
        run_records: list[dict[str, Any]] = []
        for case_name in sorted({item["case"] for item in MUTATION_MANIFEST.values()}):
            existing = _record_existing(case_name, control_root / case_name) if args.resume else None
            if existing is not None:
                run_records.append(existing)
                print(f"CONTROL {case_name}\n  REUSED exact-byte", flush=True)
                continue
            print(f"CONTROL {case_name}", flush=True)
            record = _run_case(
                godot,
                godot_version,
                source_commit,
                case_name,
                control_root / case_name,
                None,
                args.timeout,
            )
            run_records.append(record)
            print(f"  DONE {case_name} {record['elapsed_s']:.3f}s", flush=True)
        for mutant_id, contract in MUTATION_MANIFEST.items():
            case_name = contract["case"]
            existing = _record_existing(case_name, mutant_root / mutant_id, mutant_id) if args.evaluate_only else None
            if existing is not None:
                run_records.append(existing)
                print(f"MUTANT {mutant_id} {case_name}\n  REUSED exact-byte", flush=True)
                continue
            if args.evaluate_only:
                raise RuntimeError(f"missing existing mutant evidence: {mutant_id}/{case_name}")
            print(f"MUTANT {mutant_id} {case_name}", flush=True)
            record = _run_case(
                godot,
                godot_version,
                source_commit,
                case_name,
                mutant_root / mutant_id,
                mutant_id,
                args.timeout,
            )
            run_records.append(record)
            print(f"  DONE {mutant_id} {record['elapsed_s']:.3f}s", flush=True)
        runtime_source_commits = {
            record["runtime_health"].get("source_commit") for record in run_records
        }
        if None in runtime_source_commits or len(runtime_source_commits) != 1:
            raise RuntimeError(
                "runtime evidence does not identify one source commit: "
                f"{sorted(str(item) for item in runtime_source_commits)}"
            )
        runtime_source_commit = runtime_source_commits.pop()
        if not args.evaluate_only and runtime_source_commit != source_commit:
            raise RuntimeError(
                "fresh runtime evidence source commit does not match HEAD: "
                f"{runtime_source_commit} != {source_commit}"
            )
        source_commit = runtime_source_commit
        source_tree_oid = _git_output("rev-parse", f"{source_commit}^{{tree}}")
        results = {mutant_id: _evaluate_mutant(mutant_id, control_root / contract["case"], mutant_root / mutant_id, run_records, canonical_checks) for mutant_id, contract in MUTATION_MANIFEST.items()}
        report = {
            "schema_version": 2, "generated_at": datetime.datetime.now(datetime.UTC).isoformat(),
            "source_commit": source_commit,
            "source_tree_oid": source_tree_oid,
            "worktree_clean": True,
            "reference_report_sha256": _sha256(REFERENCE_REPORT),
            "required_check_names_sha256": hashlib.sha256(
                ("\n".join(sorted(
                    name for name, item in canonical_checks.items() if item["required"]
                )) + "\n").encode("utf-8")
            ).hexdigest(),
            "baseline_required_checks": required_count,
            "manifest_complete": set(results) == set(MUTATION_MANIFEST), "mutants": results,
            "killed_count": sum(1 for result in results.values() if result["killed"]),
            "total_mutants": len(results),
        }
        report["kill_rate_global"] = report["killed_count"] / report["total_mutants"]
        auditor = _load_module(AUDITOR_PATH, "audit_mutation_trust_runtime")
        errors = auditor.validate_mutation_report(report, required_count)
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 1
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        (evidence_dir / "campaign_manifest.json").write_text(
            json.dumps(
                {
                    "source_commit": source_commit,
                    "godot_version": godot_version,
                    "version_probe_health": version_probe_health,
                    "runs": run_records,
                    "mutation_manifest": MUTATION_MANIFEST,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"PASS: {report['killed_count']}/{report['total_mutants']} mutants killed")
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    finally:
        residual = _godot_processes()
        if residual:
            print(f"ERROR: residual Godot processes after campaign: {residual}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
