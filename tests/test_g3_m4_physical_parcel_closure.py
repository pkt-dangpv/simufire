"""Offline guards of P1 native-evidence binding; these mocks are NOT proof."""

import copy
from pathlib import Path

import pytest

from scripts.simulation import run_g3_o2_m4_physical_parcel_closure as closure


def evidence(monkeypatch):
    # Receipt mathematics is tested separately; isolate stage admission here.
    monkeypatch.setattr(closure.audit, "audit_payload", lambda payload: {"mocked": True})
    health = {"windows_error_ui_suppressed": True, "timed_out": False, "error_dialogs": [],
              "residual_godot_processes": [], "foreign_godot_processes": [], "process_quiescent": True,
              "observed_godot_processes": [], "post_exit_observation_s": 2.5,
              "cleanup_terminated_pids": []}
    current = {closure.pure.MODEL: "m", closure.pure.FIXTURE: "f", closure.pure.AUDITOR: "a"}
    control = {"state": "passed", "source_sha256_raw": copy.deepcopy(current),
               "integration_validated": False, "physical_flow_validation": False,
               "fixture": {}, "health": copy.deepcopy(health)}
    declared = closure.mutants.harness.machinery.plan(
        closure.mutants.MUTATIONS, tuple(closure.mutants.MUTATIONS))
    variants = {name: (closure.pure.MODEL, name) for name in closure.mutants.MUTATIONS}
    monkeypatch.setattr(closure.mutants.harness.machinery, "prepared", lambda *args: ({}, variants))
    results = [{"name": "control", "verdict": "pass", "health": copy.deepcopy(health)}]
    results += [{"name": name, "verdict": "killed", "seen_where_expected": True,
                 "expected_in": declared[name]["expected_in"],
                 "failures": [declared[name]["expected_in"] + " mocked"],
                 "mutant_sha256": closure.mutants.harness.sha(name.encode()),
                 "health": copy.deepcopy(health)} for name in closure.mutants.MUTATIONS]
    campaign = {"error": None, "integration_validated": False, "declared": 20, "executed": 20,
                "killed_where_expected": 20, "originals_intact": True, "all_sources_restored": True,
                "source_sha256_raw": copy.deepcopy(current), "sha256_before": {closure.pure.MODEL: "m"},
                "sha256_after": {closure.pure.MODEL: "m"}, "results": results, "plan": declared}
    return control, campaign, current


def test_prerequisites_accept_complete_bound_control_and_campaign(monkeypatch):
    closure.prerequisites(*evidence(monkeypatch))


@pytest.mark.parametrize("defect", ["source", "scope", "state", "incomplete", "coverage", "survivor",
                                   "restoration", "fixture_stale", "campaign_error", "control_failure",
                                   "timeout", "dialog", "residual", "foreign", "cleanup",
                                   "plan", "variant", "assertion", "physical_scope"])
def test_prerequisites_refuse_incomplete_or_unhealthy_evidence(monkeypatch, defect):
    control, campaign, current = evidence(monkeypatch)
    if defect == "source":
        current[closure.pure.MODEL] = "changed"
    elif defect == "scope":
        control["integration_validated"] = True
    elif defect == "state":
        control["state"] = "failed"
    elif defect == "incomplete":
        campaign["executed"] = 19
    elif defect == "coverage":
        campaign["results"][-1]["name"] = "not_declared"
    elif defect == "survivor":
        campaign["results"][-1]["verdict"] = "pass"
    elif defect == "restoration":
        campaign["sha256_after"][closure.pure.MODEL] = "wrong"
    elif defect == "fixture_stale":
        campaign["source_sha256_raw"][closure.pure.FIXTURE] = "wrong"
    elif defect == "campaign_error":
        campaign["error"] = "aborted"
    elif defect == "control_failure":
        campaign["results"][0]["verdict"] = "killed"
    elif defect == "plan":
        campaign["plan"] = {}
    elif defect == "variant":
        campaign["results"][-1]["mutant_sha256"] = "wrong"
    elif defect == "assertion":
        campaign["results"][-1]["failures"] = ["some other failure"]
    elif defect == "physical_scope":
        control["physical_flow_validation"] = True
    elif defect == "timeout":
        control["health"]["timed_out"] = True
    else:
        key = {"dialog": "error_dialogs", "residual": "residual_godot_processes",
               "foreign": "foreign_godot_processes", "cleanup": "cleanup_terminated_pids"}[defect]
        campaign["results"][-1]["health"][key] = ["bad"]
    with pytest.raises(RuntimeError):
        closure.prerequisites(control, campaign, current)


def test_mutants_are_real_unique_anchors_with_named_fixture_checks():
    root = Path(__file__).resolve().parents[1]
    source = (root / closure.pure.MODEL).read_text(encoding="utf-8")
    fixture = (root / closure.pure.FIXTURE).read_text(encoding="utf-8")
    for path, old, new, defect, expected in closure.mutants.MUTATIONS.values():
        assert path == closure.pure.MODEL and source.count(old) == 1
        assert old != new and defect and expected in fixture


def test_source_inventory_includes_pure_model_before_and_after_staging(tmp_path, monkeypatch):
    monkeypatch.setattr(closure, "ROOT", tmp_path)
    paths = ["sim/core/Existing.gd", closure.pure.MODEL]
    for path in paths:
        target = tmp_path / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"same\r\nbytes\r\n")
    monkeypatch.setattr(closure.gate, "git", lambda *args: paths[0].encode())
    before = closure.source_inventory()
    monkeypatch.setattr(closure.gate, "git", lambda *args: "\n".join(paths).encode())
    assert closure.source_inventory() == before
    (tmp_path / closure.pure.MODEL).write_bytes(b"same\nbytes\n")
    assert closure.source_inventory() == before
    (tmp_path / closure.pure.MODEL).write_bytes(b"changed\n")
    assert closure.source_inventory() != before
