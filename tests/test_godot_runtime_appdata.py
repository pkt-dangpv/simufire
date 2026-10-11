"""External runtime APPDATA override; harmless mocked launch, no Godot."""

import importlib.util
from pathlib import Path
import subprocess

import pytest

from scripts.simulation import run_g3_fuel_baseline as baseline


def test_explicit_external_appdata_reaches_the_monitor(tmp_path, monkeypatch):
    path = Path(__file__).with_name("godot_runtime_launcher.py")
    spec = importlib.util.spec_from_file_location("m2t_runtime_appdata_launcher", path)
    launcher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(launcher)
    external = tmp_path / "external-appdata"
    monkeypatch.setenv("SIMUFIRE_GODOT_TEST_APPDATA", str(external))
    monkeypatch.setattr(launcher.mutation_audit, "_godot_processes", lambda: [])
    observed = {}

    def monitored(command, timeout, environment):
        observed.update(environment)
        return subprocess.CompletedProcess(command, 0, "", ""), {}

    monkeypatch.setattr(launcher.mutation_audit, "_run_monitored", monitored)
    monkeypatch.setattr(launcher, "_health_errors", lambda health, allowed: [])
    launcher.run_godot(["harmless-mocked-executable"], timeout_s=1)
    assert external.is_dir()
    assert observed["APPDATA"] == str(external)


def test_baseline_external_runtime_is_selected_without_changing_run_output(tmp_path, monkeypatch):
    project = tmp_path / "checkout"
    monkeypatch.setattr(baseline, "ROOT", project)
    external = tmp_path / "external-runtime"
    monkeypatch.setenv("SIMUFIRE_GODOT_RUNTIME_ROOT", str(external))
    output = project / "runs" / "test-run"
    appdata, temp = baseline.runtime_paths(output)
    assert appdata == external / "test-run" / "appdata"
    assert temp == external / "test-run" / "temp"
    assert not output.exists()


def test_baseline_default_remains_its_isolated_historical_location(tmp_path, monkeypatch):
    monkeypatch.delenv("SIMUFIRE_GODOT_RUNTIME_ROOT", raising=False)
    assert baseline.runtime_paths(tmp_path) == (tmp_path / "appdata", tmp_path / "temp")


def test_requested_external_storage_cannot_be_inside_the_checkout(tmp_path, monkeypatch):
    monkeypatch.setattr(baseline, "ROOT", tmp_path)
    monkeypatch.setenv("SIMUFIRE_GODOT_RUNTIME_ROOT", str(tmp_path / "bad-runtime"))
    with pytest.raises(ValueError, match="outside the checkout"):
        baseline.runtime_paths(tmp_path / "runs" / "test-run")
