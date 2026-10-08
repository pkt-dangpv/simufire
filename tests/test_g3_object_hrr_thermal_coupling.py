"""Thermal coupling bench of the prescribed HRR source: oracle, contract and the real engine.

A diagnostic bench: energy and an equivalent oxygen debit of one room. It validates no
temperature, no combustion of the furniture, no CO, FED or SVV.

The offline tests pin the independent oracle and the two corrections recorded before any
coupled run (what a finite step returns, and what the oxygen debit is). The engine test
launches Godot through the monitor and judges the bench again outside GDScript.
"""

from __future__ import annotations

import bisect
import json
import math
import os
from pathlib import Path

import pytest

from scripts.simulation import build_g3_object_hrr_coupling_oracle as oracle_builder
from scripts.simulation import build_g3_object_hrr_source as source_builder

ROOT = Path(__file__).resolve().parents[1]
ORACLE = json.loads(oracle_builder.ORACLE.read_text(encoding="ascii"))
SOURCE = json.loads(source_builder.FIXTURE.read_text(encoding="utf-8"))
TIMES = [float(item["time_s"]) for item in SOURCE["source"]["samples"]]
VALUES = [float(item["hrr_kw"]) for item in SOURCE["source"]["samples"]]
ENERGY_KJ = 115093.655
DESIGN = ROOT / "docs" / "validation" / "G3_OBJECT_HRR_SOURCE_COUPLING_DESIGN_2026-10-08.md"
FROZEN = {
    "sim/fire/PrescribedObjectHrrSource.gd": "f8a39d8312a6ef0117ea37eeec3df7fb7858f212d6c32539ac3d41e850d6c3c4",
    "tests/fixtures/g3_object_hrr_source_test016.json": "13d7cd65a34186a57564f6de6db670b768e0815a18fb3b5b0c6d382e12a07b57",
}


def _prefix() -> list[float]:
    out = [0.0]
    for index in range(1, len(TIMES)):
        out.append(out[-1] + 0.5 * (VALUES[index - 1] + VALUES[index]) * (TIMES[index] - TIMES[index - 1]))
    return out


PREFIX = _prefix()


def _cumulative(time_s: float) -> float:
    """Energy from the ignition, by another route than the builder: prefix sums and one partial trapezoid."""
    low = min(bisect.bisect_right(TIMES, time_s) - 1, len(TIMES) - 2)
    span = time_s - TIMES[low]
    slope = (VALUES[low + 1] - VALUES[low]) / (TIMES[low + 1] - TIMES[low])
    return PREFIX[low] + span * (VALUES[low] + 0.5 * slope * span)


def _near(actual: float, expected: float) -> bool:
    tolerance = ORACLE["numerical_tolerance"]
    return abs(actual - expected) <= tolerance["abs_kj"] + tolerance["rel"] * max(abs(actual), abs(expected))


# ---------------------------------------------------------------- frozen inputs and oracle

def test_the_isolated_owner_and_its_data_are_the_approved_bytes() -> None:
    import hashlib
    for relative, digest in FROZEN.items():
        assert hashlib.sha256((ROOT / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest() == digest, relative
    assert ORACLE["source_identity"] == SOURCE["expected_identity"]
    assert ORACLE["run"] == "Test016" and ORACLE["reserved_runs_not_used"] == ["Test021"]


def test_the_oracle_is_rebuilt_byte_for_byte() -> None:
    text = oracle_builder.render(oracle_builder.build())
    assert text == oracle_builder.ORACLE.read_bytes().replace(b"\r\n", b"\n").decode("ascii")
    assert ORACLE["schema"] == oracle_builder.SCHEMA
    code = Path(oracle_builder.__file__).read_text(encoding="utf-8")
    for word in ("PrescribedObjectHrrSource", "godot", "Godot", "subprocess"):
        assert word not in code, word  # shares the table with the owner and nothing else


def test_the_steps_were_declared_and_one_does_not_divide_the_support() -> None:
    assert oracle_builder.STEPS_S == (1.0, 0.7, 2.5) and set(ORACLE["steps"]) == {"1.0", "0.7", "2.5"}
    assert [ORACLE["steps"][key]["divides_the_support"] for key in ("1.0", "0.7", "2.5")] == [True, False, False]
    assert [ORACLE["steps"][key]["steps"] for key in ("1.0", "0.7", "2.5")] == [3768, 5383, 1508]
    assert ORACLE["steps"]["2.5"]["last_interval_s"] == 0.5
    assert 0.0 < ORACLE["steps"]["0.7"]["last_interval_s"] < 0.7


@pytest.mark.parametrize("key", ["1.0", "0.7", "2.5"])
def test_every_step_energy_is_the_integral_by_another_route(key: str) -> None:
    item = ORACLE["steps"][key]
    dt, clock, total = item["dt_s"], 0.0, 0.0
    assert len(item["step_energy_kj"]) == item["steps"]
    for energy in item["step_energy_kj"]:
        end = min(clock + dt, ORACLE["support_end_s"])
        assert _near(energy, _cumulative(end) - _cumulative(clock)) or abs(
            energy - (_cumulative(end) - _cumulative(clock))) < 1.0e-7  # a difference of two large sums
        total += energy
        clock = end
    assert clock == ORACLE["support_end_s"] == 3768.0
    assert abs(total - ENERGY_KJ) < 1.0e-6 and item["total_kj"] == pytest.approx(ENERGY_KJ, abs=1.0e-9)
    assert item["end_of_the_last_step_s"] == 3768.0


@pytest.mark.parametrize("key", ["1.0", "0.7", "2.5"])
def test_the_last_step_neither_loses_nor_doubles_energy(key: str) -> None:
    item = ORACLE["steps"][key]
    # The last interval may be shorter than the step; its energy is spread over the whole step.
    assert item["last_step_power_kw"] * item["dt_s"] == pytest.approx(item["last_step_energy_kj"], rel=1.0e-12)
    assert item["last_step_energy_kj"] == item["step_energy_kj"][-1]
    if not item["divides_the_support"]:
        mean_over_the_interval = item["last_step_energy_kj"] / item["last_interval_s"]
        assert item["last_step_power_kw"] < mean_over_the_interval


# ---------------------------------------------------------------- peak and finite step

def test_a_finite_step_does_not_return_the_instantaneous_peak_closed_form() -> None:
    triangle = ORACLE["peak_and_step"]["synthetic_triangle"]
    assert triangle["instantaneous_peak_kw"] == 100.0
    by_step = {row["dt_s"]: row for row in triangle["steps"]}
    # Written here by hand: slopes of 10 kW/s around a peak of 100 kW at 10 s.
    assert by_step[4.0]["largest_step_power_kw"] == 90.0 and not by_step[4.0]["peak_on_a_step_end"]
    assert by_step[1.0]["largest_step_power_kw"] == 95.0 and by_step[1.0]["peak_on_a_step_end"]
    assert by_step[0.5]["largest_step_power_kw"] == 97.5 and by_step[0.5]["peak_on_a_step_end"]
    for row in triangle["steps"]:
        assert row["largest_step_power_kw"] == row["closed_form_kw"] < 100.0
        assert row["total_kj"] == 1000.0  # the energy does not depend on the step


def test_the_peak_criterion_is_per_step_and_the_instantaneous_peak_is_the_datum() -> None:
    assert ORACLE["instantaneous_peak"] == {"time_s": 1143.0, "hrr_kw": 621.46}
    assert max(VALUES) == 621.46 and VALUES.index(621.46) == 1143
    for key, item in ORACLE["steps"].items():
        assert item["largest_step_power_kw"] < 621.46, key
        assert item["largest_step_power_minus_instantaneous_peak_kw"] == pytest.approx(
            item["largest_step_power_kw"] - 621.46, abs=1.0e-9)
        low, high = item["largest_step_interval_s"]
        assert item["largest_step_power_kw"] == pytest.approx((_cumulative(high) - _cumulative(low)) / item["dt_s"], rel=1.0e-9)
        # No delay: the step that holds 1143 s is the one where the step power is largest in this run.
        assert item["step_holding_the_instantaneous_peak"] == item["largest_step_index"]
        assert low < 1143.0 <= high or low <= 1143.0 < high
    one = ORACLE["steps"]["1.0"]
    assert one["largest_step_power_kw"] == pytest.approx(0.5 * (VALUES[1142] + VALUES[1143]))
    assert one["largest_step_index"] == 1142
    assert ORACLE["steps"]["2.5"]["largest_step_power_kw"] < ORACLE["steps"]["0.7"]["largest_step_power_kw"]


def test_the_oracle_names_the_largest_step_independently() -> None:
    for key, item in ORACLE["steps"].items():
        powers = [energy / item["dt_s"] for energy in item["step_energy_kj"]]
        assert powers.index(max(powers)) == item["largest_step_index"], key
        assert max(powers) == pytest.approx(item["largest_step_power_kw"], rel=1.0e-12)


# ---------------------------------------------------------------- oxygen and radiation of the bench

def test_the_oxygen_debit_is_a_declared_coefficient_not_a_measurement() -> None:
    oxygen = ORACLE["oxygen"]
    sink = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
    assert oxygen["kg_per_MJ"] == 0.076 == oracle_builder.OXYGEN_KG_PER_MJ
    assert "if room.fire != null else 0.076" in sink  # the constant the engine sink already uses
    assert oxygen["whole_run_kg"] == pytest.approx(ENERGY_KJ / 1000.0 * 0.076, rel=1.0e-12)
    assert "not a stoichiometry" in oxygen["what_it_is"] and "not a" in oxygen["what_it_is"]
    # It is not fitted to the oxygen total of the database (8.168 kg) nor to energy over 13.1 MJ/kg (8.786 kg).
    assert abs(oxygen["whole_run_kg"] - 8.168419518) > 0.5 and abs(oxygen["whole_run_kg"] - ENERGY_KJ / 13100.0) > 0.03


def test_the_radiative_fraction_belongs_to_the_case_and_keeps_its_class() -> None:
    rows = ORACLE["radiative_fractions"]
    assert [row["value"] for row in rows] == [0.35, 0.52, 0.4264, 0.6136]
    assert [row["class"] for row in rows] == ["assumed", "open_air_whole_test_estimate", "sensitivity", "sensitivity"]
    assert rows[2]["value"] == pytest.approx(0.52 * 0.82) and rows[3]["value"] == pytest.approx(0.52 * 1.18)
    for row in rows:
        assert row["to_the_gas_kj"] + row["radiative_term_kj"] == pytest.approx(ENERGY_KJ, abs=1.0e-6)
        assert row["radiative_term_kj"] == pytest.approx(ENERGY_KJ * row["value"], rel=1.0e-12)
    assert "never of the source" in ORACLE["radiative_fraction_is"]
    assert SOURCE["source"]["unknown"]["radiative_fraction"] is None


def test_the_corrections_were_written_in_the_design_before_the_bench() -> None:
    text = DESIGN.read_text(encoding="utf-8")
    for needle in ("Correcciones del 08-10, registradas antes de ejecutar el acoplamiento",
                   "demanda equivalente prescrita", "no es una reconstrucción exacta", "A4a", "A4b", "A4c",
                   "621,125 kW", "621,274 kW", "619,663 kW", "0,076 kg/MJ"):
        assert needle in text, needle
    assert "| A4 | Pico 621,46 kW en el paso que contiene los 1143 s" not in text
