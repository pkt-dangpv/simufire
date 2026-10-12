"""M4-A1 structure/runner protections; runtime is judged by the actual GD fixture."""
from dataclasses import asdict
import copy
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.simulation import run_g3_o2_m4_partition as runner
from scripts.simulation import run_g3_o2_m4_partition_mutations as mutations
from scripts.simulation import run_g3_o2_m4_closure as closure


def _payload():
    state = runner.oracle.Partition(7, 1, 10, 30)
    result = runner.oracle.mix(state, .5)
    sample = {"operation": "mix", "input": asdict(state), "argument": .5,
              "after": asdict(result.after), "receipt": asdict(result)}
    return {"iterations": 10000, "maximum_total_gap_kg": 0,
            "samples": [copy.deepcopy(sample) for _ in range(18)]}


def test_independent_runner_accepts_reference_but_not_physical_validation():
    assert runner.audit_samples(_payload()) == {
        "samples": 18, "independent_budget": True, "physical_validation": False}


@pytest.mark.parametrize("defect", ["missing", "iterations", "drift", "state", "receipt", "cause", "unknown"])
def test_independent_runner_refuses_corrupted_fixture_payload(defect):
    payload = _payload()
    if defect == "missing":
        payload["samples"].pop()
    elif defect == "iterations":
        payload["iterations"] = 9999
    elif defect == "drift":
        payload["maximum_total_gap_kg"] = .01
    elif defect == "state":
        payload["samples"][0]["after"]["upper_kg"] += .01
    elif defect == "receipt":
        payload["samples"][0]["receipt"]["lower_delta_kg"] = 0
    elif defect == "cause":
        payload["samples"][0]["receipt"]["cause"] = "unowned"
    else:
        payload["samples"][0]["operation"] = "unknown"
    with pytest.raises(RuntimeError):
        runner.audit_samples(payload)


def test_pure_module_has_no_runtime_owner_or_activation():
    relative = mutations.MODEL
    source = (ROOT / relative).read_text(encoding="utf-8")
    for token in ("class_name ", "@export", "preload(", "load(", "RoomModel", "SimulationEngine"):
        # Comments declare limits; only code is scanned here.
        code = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
        assert token not in code
    consumers = []
    for path in (ROOT / "sim").rglob("*.gd"):
        if path == ROOT / relative:
            continue
        if "OxygenReferencePartition.gd" in path.read_text(encoding="utf-8"):
            consumers.append(path)
    assert consumers == []


def test_mutations_have_unique_current_anchors_and_named_assertions():
    source = (ROOT / mutations.MODEL).read_text(encoding="utf-8")
    fixture = (ROOT / runner.FIXTURE).read_text(encoding="utf-8")
    assert len(mutations.MUTATIONS) == 14
    for relative, old, new, description, expected in mutations.MUTATIONS.values():
        assert relative == mutations.MODEL and source.count(old) == 1
        assert old != new and description and expected
        # Composed _audit labels are checked in runtime, other labels are literals.
        if expected not in fixture:
            assert expected in {"mix P3 lower", "budget P1 room"} or (
                expected.endswith(" rejected") and expected.removesuffix(" rejected") in fixture)


def test_runner_uses_safe_monitor_and_unchanged_owned_mutation_harness():
    source = (ROOT / "scripts/simulation/run_g3_o2_m4_partition.py").read_text(encoding="utf-8")
    assert "godot_monitored_launch.run(" in source and "prepare_environment(work)" in source
    assert "harness.classify(" in source and "audit_samples(payload)" in source
    assert "subprocess.Popen" not in source
    mutation_source = (ROOT / "scripts/simulation/run_g3_o2_m4_partition_mutations.py").read_text(encoding="utf-8")
    assert "harness.execute(" in mutation_source and "integration=False" in mutation_source


@pytest.mark.parametrize("state", [(0, 0, 1e308, 1e308), (7, 1, 10, -30)])
def test_python_oracle_also_refuses_nonfinite_aggregate_or_invalid_base(state):
    with pytest.raises(ValueError):
        runner.oracle.Partition(*state)


def _closure_inputs():
    health = {"windows_error_ui_suppressed": True, "timed_out": False,
              "error_dialogs": [], "residual_godot_processes": [], "process_quiescent": True,
              "observed_godot_processes": [], "post_exit_observation_s": 2.5,
              "cleanup_terminated_pids": []}
    current = {"model": "model", "fixture": "fixture", "oracle": "oracle"}
    payload = _payload()
    payload.update({"checks": 160304, "failure_count": 0, "failures": []})
    control = {"state": "passed", "model_sha256_raw": "model", "fixture_sha256_raw": "fixture",
               "oracle_sha256_raw": "oracle", "fixture": payload, "health": copy.deepcopy(health)}
    campaign = {"error": None, "integration_validated": False, "declared": 14, "executed": 14,
                "killed_where_expected": 14, "originals_intact": True,
                "sha256_before": {runner.MODEL: "model"}, "sha256_after": {runner.MODEL: "model"},
                "fixture_sha256_before": "fixture", "fixture_sha256_after": "fixture",
                "results": [{"name": "control", "verdict": "pass", "health": copy.deepcopy(health)}]}
    for index in range(14):
        campaign["results"].append({"name": str(index), "verdict": "killed",
                                    "seen_where_expected": True, "health": copy.deepcopy(health)})
    return control, campaign, current


def test_closure_requires_actual_pure_proof_not_integration():
    control, campaign, current = _closure_inputs()
    closure.prerequisites(control, campaign, current)


@pytest.mark.parametrize("defect", ["source", "fixture", "oracle", "count", "restoration", "integration",
                                    "survivor", "timeout", "dialog", "residual", "cleanup", "checks"])
def test_closure_refuses_incomplete_or_unhealthy_proof(defect):
    control, campaign, current = _closure_inputs()
    if defect == "source":
        current["model"] = "changed"
    elif defect == "fixture":
        campaign["fixture_sha256_after"] = "changed"
    elif defect == "oracle":
        control["oracle_sha256_raw"] = "changed"
    elif defect == "count":
        campaign["executed"] = 13
    elif defect == "restoration":
        campaign["sha256_after"][runner.MODEL] = "changed"
    elif defect == "integration":
        campaign["integration_validated"] = True
    elif defect == "survivor":
        campaign["results"][-1]["seen_where_expected"] = False
    elif defect == "timeout":
        campaign["results"][-1]["health"]["timed_out"] = True
    elif defect == "dialog":
        control["health"]["error_dialogs"] = ["native"]
    elif defect == "residual":
        control["health"]["residual_godot_processes"] = ["residual"]
    elif defect == "cleanup":
        control["health"]["cleanup_terminated_pids"] = [1]
    else:
        control["fixture"]["checks"] = 0
    with pytest.raises(RuntimeError):
        closure.prerequisites(control, campaign, current)


def test_closure_inventory_is_identical_before_and_after_pure_module_is_tracked(tmp_path, monkeypatch):
    monkeypatch.setattr(closure, "ROOT", tmp_path)
    paths = ["sim/core/Existing.gd", "sim/validation/reports/reference_checks.json", runner.MODEL]
    for path in paths:
        target = tmp_path / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"same\r\ncontent\r\n")
    monkeypatch.setattr(closure.gate, "git", lambda *args: "\n".join(paths[:-1]).encode())
    untracked = closure.source_inventory()
    monkeypatch.setattr(closure.gate, "git", lambda *args: "\n".join(paths).encode())
    tracked = closure.source_inventory()
    assert untracked == tracked
    # Checkout line endings are metadata, actual content changes are not.
    (tmp_path / runner.MODEL).write_bytes(b"same\ncontent\n")
    assert closure.source_inventory() == tracked
    (tmp_path / runner.MODEL).write_bytes(b"different\ncontent\n")
    assert closure.source_inventory()[runner.MODEL] != tracked[runner.MODEL]
