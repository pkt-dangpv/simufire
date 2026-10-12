"""Bounded historical assertion format, not relaxed native/script classification."""
import json
from pathlib import Path

import pytest

from scripts.simulation import run_g3_o2_m3_venting_mutations as runner


def sample():
    return {"checks": 138, "failure_count": 10, "failures_by_group": {"V05": 10},
            "failures": [f"V05 assertion {index}" for index in range(8)]}


def output(payload):
    return "G3_O2_VENTING " + json.dumps(payload)


def test_bounded_messages_require_reconciled_full_counts():
    verdict, payload = runner.classify_bounded_assertions(output(sample()), "", 1, "G3_O2_VENTING")
    assert verdict == "killed" and payload["failure_count"] == 10
    payload = {"checks": 138, "failure_count": 0, "failures_by_group": {}, "failures": []}
    assert runner.classify_bounded_assertions(output(payload), "", 0, "G3_O2_VENTING")[0] == "pass"


@pytest.mark.parametrize("defect", ["count", "group", "messages", "negative", "type", "script", "native"])
def test_inconsistent_or_unhealthy_terminations_remain_invalid(defect):
    payload, stderr, exit_code = sample(), "", 1
    if defect == "count":
        payload["failure_count"] = 9
    elif defect == "group":
        payload["failures_by_group"] = {"V03": 10}
    elif defect == "messages":
        payload["failures"].pop()
    elif defect == "negative":
        payload["failures_by_group"] = {"V05": -10}
    elif defect == "type":
        payload["failure_count"] = "10"
    elif defect == "script":
        stderr = "SCRIPT ERROR"
    elif defect == "native":
        exit_code = 0xC0000005
    with pytest.raises(RuntimeError):
        runner.classify_bounded_assertions(output(payload), stderr, exit_code, "G3_O2_VENTING")


def test_transit_control_is_explicitly_diagnostic_and_graph_suppression_follows_reset():
    root = Path(__file__).resolve().parents[1]
    text = (root / runner.FIXTURE).read_text(encoding="utf-8")
    assert "super._two_steps_and_a_neighbour()" in text
    assert "synthetic_venting_regression" in text and "diagnostic transit was actually queued" in text
    assert text.index("super._world(") < text.index(".suppress_exit_graphs()")
