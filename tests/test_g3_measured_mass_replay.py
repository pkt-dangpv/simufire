"""Measured mass replay checks, not material/CO calibration."""

import json
import os
from decimal import Decimal
from pathlib import Path

import pytest

from scripts import godot_monitored_launch
from scripts.simulation import build_g3_measured_mass_replay as builder
from scripts.simulation import audit_g3_measured_mass_candidate as audit
from scripts.simulation import run_g3_prescribed_release_mutations as mutations
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/g3_isohept9_measured_replay.json"


def test_build_is_repeatable_and_observations_are_exact_source_values():
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert builder.build() == fixture == builder.build()
    rows = audit.read_mass_rows((ROOT / audit.audit()["source_path"]).read_text(encoding="utf-8"))
    measured = [(t, m) for t, m in rows if 0 <= t <= 500]
    assert fixture["observations"] == [
        {"time_s": float(t), "mass_kg": float(m)} for t, m in measured]
    assert fixture["program"]["initial_mass_kg"] == 19.665829  # not nominal 20
    assert fixture["program"]["samples"][-1] == {"time_s": 500, "rate_kg_s": 0}
    assert len(fixture["program"]["samples"]) == 101
    assert fixture["scientific_approval"] is False
    assert fixture["engine_integration"] is False
    assert fixture["production_activation"] is False
    assert "material" not in fixture and "heat" not in fixture


def test_decimal_intervals_conserve_each_measured_decrement():
    fixture = builder.build()
    nodes = fixture["observations"]
    for a, b, sample in zip(nodes, nodes[1:], fixture["program"]["samples"]):
        dt = Decimal(str(b["time_s"])) - Decimal(str(a["time_s"]))
        rate = Decimal(str(sample["rate_kg_s"]))
        decrement = Decimal(str(a["mass_kg"])) - Decimal(str(b["mass_kg"]))
        assert abs(rate * dt - decrement) <= Decimal("1e-16")


@pytest.mark.parametrize("rows", [
    [(0, 1), (5, 1.01)],  # no clamping of measured gain
    [(0, 1), (5, -0.01)],
    [(0, 1), (0, 0)],
    [(1, 1), (5, 0)],
    [(0, 1), (5, float("nan"))],
    [(0, 1)],
])
def test_invalid_trace_requires_new_review_not_automatic_repair(rows):
    with pytest.raises(ValueError):
        builder.rates_from_rows(rows)


def test_interval_means_are_not_linear_nodes():
    samples = builder.rates_from_rows([(0, 1), (5, .9), (10, .7)])
    assert samples == [{"time_s": 0, "rate_kg_s": .02},
                       {"time_s": 5, "rate_kg_s": .04},
                       {"time_s": 10, "rate_kg_s": 0}]
    assert sum(5 * s["rate_kg_s"] for s in samples[:-1]) == pytest.approx(.3)
    trapezoid = sum(2.5 * (a["rate_kg_s"] + b["rate_kg_s"])
                    for a, b in zip(samples, samples[1:]))
    assert trapezoid == pytest.approx(.25)  # detects the wrong temporal rule


def test_measured_mutation_plan_has_unique_anchors_and_preserves_original():
    raw = mutations.MODEL.read_bytes()
    assert len(mutations.MEASURED_MUTATIONS) == 11
    for old, new in mutations.MEASURED_MUTATIONS.values():
        assert mutations.changed_source(raw.decode("utf-8"), old, new) != raw.decode("utf-8")
    assert mutations.MODEL.read_bytes() == raw


def test_actual_gdscript_measured_replay():
    godot = Path(os.environ.get("GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0, "Godot requires >=6 GiB"
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script",
                           ROOT / "tests/fixtures/g3_measured_mass_replay.gd"],
                          timeout_s=120, allowed_exit_codes=(0,))
    line = next(line for line in completed.stdout.splitlines()
                if line.startswith("G3_MEASURED_MASS_REPLAY {"))
    result = json.loads(line.split(" ", 1)[1])
    assert result["failures"] == []
    assert result["checks"] == 2459
    assert result["max_mass_error_kg"] <= 1e-9
    assert "G3_MEASURED_MASS_REPLAY_PASS" in completed.stdout
    for campaign in result["campaigns"].values():
        assert campaign["remaining_kg"] == pytest.approx(.306292, abs=1e-9)
        assert campaign["progress"]["scheduled_kg"] == pytest.approx(19.359537, abs=1e-9)
