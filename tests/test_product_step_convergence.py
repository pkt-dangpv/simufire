"""Comparator behavior with synthetic data; no physical acceptance claim."""

import copy

import pytest

from scripts.verify_product_step_convergence import compare


def trace(value=100.0, *, field="hrr_kw", time=1.0):
    return {"fields": [field], "samples": [
        {"time_s": time, "rooms": {"0": [value], "1": [value]}}]}


def test_screen_counts_each_room_and_preserves_inputs():
    reference, candidate = trace(), trace(108.0)
    original = copy.deepcopy((reference, candidate))
    result = compare(reference, candidate)
    assert result["checked"] == result["failed"] == 2
    assert not result["passed"]
    assert result["worst"]["hrr_kw"]["difference"] == 8.0
    assert result["worst"]["hrr_kw"]["tolerance_ratio"] == pytest.approx(8 / 7)
    assert (reference, candidate) == original


def test_absolute_floor_and_relative_tolerance_include_boundary():
    assert compare(trace(), trace(107.0))["passed"]
    assert not compare(trace(), trace(107.001))["passed"]
    assert compare(trace(0), trace(5))["passed"]
    assert not compare(trace(0), trace(5.01))["passed"]


@pytest.mark.parametrize("defect", ["missing_sample", "wrong_time", "missing_room", "missing_value", "wrong_fields"])
def test_incomparable_traces_are_rejected(defect):
    reference, candidate = trace(), trace()
    if defect == "missing_sample":
        candidate["samples"] = []
    elif defect == "wrong_time":
        candidate["samples"][0]["time_s"] = 2.0
    elif defect == "missing_room":
        del candidate["samples"][0]["rooms"]["1"]
    elif defect == "missing_value":
        candidate["samples"][0]["rooms"]["0"] = []
    else:
        candidate["fields"] = ["temp_upper_c"]
    with pytest.raises((AssertionError, ValueError)):
        compare(reference, candidate)


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -float("inf")])
def test_non_finite_values_cannot_silently_pass(value):
    with pytest.raises(ValueError, match="non-finite"):
        compare(trace(), trace(value))
