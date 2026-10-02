"""Monitored launcher: stale Godot popups are refused, fresh ones still fail.

Reproduced on 2026-09-29: hard-error popups left by an earlier crashed Godot
stayed open, the title-based window scan attributed them to every new healthy
run and killed it within ~3 s (TerminateProcess exit 1). The launcher must
refuse to start while such a popup exists, without weakening detection of a
popup that appears during the run. A harmless Python child stands in for
Godot; no real dialog is shown.
"""

from __future__ import annotations

import sys

import pytest

from tests.godot_runtime_launcher import _health_errors
from tools import mutation_audit


TITLE = "Godot_v4.7.1-stable_win64.exe - Error de la aplicación"


def test_a_popup_open_before_launch_refuses_the_launch(monkeypatch):
    monkeypatch.setattr(mutation_audit, "_windows_godot_error_dialogs", lambda: [TITLE])

    def must_not_start(*_args, **_kwargs):
        raise AssertionError("a process was started despite a stale popup")

    monkeypatch.setattr(mutation_audit, "_start_without_windows_error_ui", must_not_start)
    with pytest.raises(mutation_audit.PreexistingGodotErrorDialog, match="Event ID 26"):
        mutation_audit._run_monitored([sys.executable, "-c", "pass"], 10)


def test_a_popup_that_appears_during_the_run_still_fails_it(monkeypatch):
    calls = {"n": 0}

    def scan():
        calls["n"] += 1
        return [] if calls["n"] == 1 else [TITLE]  # clean pre-check, then a popup

    monkeypatch.setattr(mutation_audit, "_windows_godot_error_dialogs", scan)
    completed, health = mutation_audit._run_monitored(
        [sys.executable, "-c", "import time; time.sleep(30)"], 20
    )
    assert health["error_dialogs"] == [TITLE]
    assert health["timed_out"] is False
    assert completed.returncode == 1  # killed by the monitor
    assert any("popup detected" in error for error in _health_errors(health, (0,)))


def test_a_clean_run_is_unaffected(monkeypatch):
    monkeypatch.setattr(mutation_audit, "_windows_godot_error_dialogs", lambda: [])
    completed, health = mutation_audit._run_monitored(
        [sys.executable, "-c", "print('ok')"], 20
    )
    assert completed.returncode == 0
    assert "ok" in completed.stdout
    assert health["error_dialogs"] == []
    assert health["residual_godot_processes"] == []
