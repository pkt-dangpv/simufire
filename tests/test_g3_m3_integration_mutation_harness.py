"""Offline plan and classifier checks; the actual falsation must use Godot."""
import json

import pytest

from scripts.simulation import run_g3_o2_m3_integration_mutations as runner


def test_integration_plan_has_unique_anchors_and_declared_assertions():
    originals, variants = runner.harness.machinery.prepared(
        runner.MUTATIONS, (runner.FIRE, runner.OWNER, runner.ENGINE))
    plan = runner.harness.machinery.plan(runner.MUTATIONS, tuple(runner.MUTATIONS))
    assert len(plan) == len(variants) == 14
    fixture = (runner.harness.ROOT / runner.FIXTURE).read_text(encoding="utf-8")
    for name, (path, variant) in variants.items():
        assert variant.encode() != originals[path]
        expected = plan[name]["expected_in"]
        assert expected in fixture or (
            expected.startswith("common fraction ") and '"common fraction " + field' in fixture
            and f'"{expected.removeprefix("common fraction ")}"' in fixture)
        assert plan[name]["declared_with_the_plan"]


def test_integration_prefix_is_not_confused_with_isolated_owner():
    payload = runner.PREFIX + " " + json.dumps({"checks": 477, "failure_count": 0, "failures": []})
    assert runner.harness.classify(payload, "", 0, runner.PREFIX)[0] == "pass"
    with pytest.raises(RuntimeError):
        runner.harness.classify(payload, "", 0)
