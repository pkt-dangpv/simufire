"""Offline falsation-harness controls; no Godot launch."""
import json

import pytest

from scripts.simulation import run_g3_o2_m3_reservation_mutations as runner


def payload(failures=(), checks=126):
    return runner.PREFIX + " " + json.dumps({"checks": checks,
        "failure_count": len(failures), "failures": list(failures)})


def test_all_mutations_have_unique_anchors_and_predeclared_assertions():
    original, variants = runner.machinery.prepared(runner.MUTATIONS, (runner.OWNER,))
    plan = runner.machinery.plan(runner.MUTATIONS, tuple(runner.MUTATIONS))
    assert len(plan) == len(variants) == 14
    assert all(item["expected_in"] and item["declared_with_the_plan"] for item in plan.values())
    assert all(text.encode() != original[path] for path, text in variants.values())


def test_normal_control_and_named_assertion_are_classified():
    assert runner.classify(payload(), "", 0)[0] == "pass"
    assert runner.classify(payload(["exact debit"]), "", 1)[0] == "killed"


@pytest.mark.parametrize("stdout,stderr,exit_code", [
    ("", "", 0),
    (payload() + "\n" + payload(), "", 0),
    (payload(), "SCRIPT ERROR: bad fixture", 0),
    ("Parse Error\n" + payload(["exact debit"]), "", 1),
    (payload(["exact debit"]), "", 0),
    (payload(), "", 1),
    (payload(["exact debit"]), "", -1073741819),
    (payload(checks=0), "", 0),
    (payload(checks=True), "", 0),
    (runner.PREFIX + ' {"checks":126,"failures":["failure"],"failure_count":0}', "", 1),
    (runner.PREFIX + ' {"checks":126,"failures":[7],"failure_count":1}', "", 1),
])
def test_infrastructure_script_or_invalid_payload_cannot_count_as_a_kill(stdout, stderr, exit_code):
    with pytest.raises(RuntimeError):
        runner.classify(stdout, stderr, exit_code)


def test_runner_checks_before_mutation_and_restores_before_classification():
    from inspect import getsource
    source = getsource(runner.execute)
    assert source.index("memory_gate_fault()") < source.index('write_bytes(text.encode("utf-8"))')
    assert source.index("write_bytes(originals[relative])") < source.index("classify(run.stdout")
    assert "run.faults or run.preexisting" in source
    assert "originals_intact" in source
    assert "subprocess" not in source


def test_fixture_handles_a_missing_rejection_as_an_assertion_not_a_script_error():
    source = (runner.ROOT / runner.FIXTURE).read_text(encoding="utf-8")
    assert 'not unsettled_rejections.is_empty() and' in source
    assert 'report()["rejections"][-1]' not in source
