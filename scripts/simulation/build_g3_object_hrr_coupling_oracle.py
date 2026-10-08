#!/usr/bin/env python3
"""Independent oracle of the thermal coupling bench of the prescribed HRR source.

Offline. For every declared time step it walks the support exactly as an engine with a
fixed step does (the clock is the sum of the steps in double precision, the last
interval is cut at the end of the support) and integrates the audited table of the
run with exact rational arithmetic. Nothing here comes from the engine or from the
isolated owner: it shares the table with them and nothing else.

What a finite step can and cannot return is part of the oracle. The power applied in
a step is the energy of its interval over the whole step, so its maximum over a run is
NOT the instantaneous peak of the table; a synthetic triangle shows it in closed form.

It is a bookkeeping oracle of a diagnostic bench: energy and an equivalent oxygen
debit. It says nothing about fuel mass, species, temperatures or the furniture.

    python -m scripts.simulation.build_g3_object_hrr_coupling_oracle --check
"""

from __future__ import annotations

import argparse
from fractions import Fraction
import json
from pathlib import Path

from scripts.simulation import audit_g3_object_fire_source as audit
from scripts.simulation import build_g3_object_hrr_source as builder

ROOT = Path(__file__).resolve().parents[2]
ORACLE = ROOT / "tests" / "fixtures" / "g3_object_hrr_thermal_coupling_oracle.json"
SCHEMA = "g3_object_hrr_thermal_coupling_oracle_v1"
# Declared before any coupled run. 1.0 falls on the nodes, 0.7 is not a binary number and
# does not divide the support, 2.5 spans several nodes and does not divide it either.
STEPS_S = (1.0, 0.7, 2.5)
# The coefficient of the bench is the one the engine sink already uses; it is not fitted.
OXYGEN_KG_PER_MJ = 0.076
RADIATIVE_FRACTIONS = (
    {"value": 0.35, "class": "assumed", "what": "engine default, also the CFAST default"},
    {"value": 0.52, "class": "open_air_whole_test_estimate", "what": "NIST TN 2303 Table 7, Test016"},
    {"value": 0.4264, "class": "sensitivity", "what": "published value minus its expanded uncertainty"},
    {"value": 0.6136, "class": "sensitivity", "what": "published value plus its expanded uncertainty"},
)
TRIANGLE = ((0, 0), (10, 100), (20, 0))
TRIANGLE_STEPS_S = (4.0, 1.0, 0.5)


def run_nodes() -> tuple[list[Fraction], dict]:
    """The clipped column of the run as exact decimals, and the committed source fixture."""
    record = audit.load_record()
    _candidate, test = builder.selected_test(record)
    nodes = [max(Fraction(0), Fraction(value)) for _t, value in builder.decimal_window(test)]
    fixture = json.loads(builder.FIXTURE.read_text(encoding="utf-8"))
    if [Fraction(float(v)) for v in nodes] != [Fraction(s["hrr_kw"]) for s in fixture["source"]["samples"]]:
        raise audit.Refusal("the committed source is not the clipped column of the CSV")
    if fixture["reserved_runs_not_used"] != ["Test021"] or fixture["source"]["run_id"] != "Test016":
        raise audit.Refusal("the committed source is not the selected run")
    return nodes, fixture


def walk(nodes: list[Fraction], dt: float) -> dict:
    """Step ends as a fixed-step engine reaches them, and the exact energy of each interval."""
    if not dt > 0.0:
        raise audit.Refusal("a step must last")
    last = float(len(nodes) - 1)
    ends, energies = [], []
    clock = 0.0
    while clock < last:
        end = min(clock + dt, last)  # the same double the owner is asked for
        energies.append(builder.exact_energy(nodes, Fraction(clock), Fraction(end)))
        ends.append(end)
        clock = end
    return {"ends": ends, "energies": energies}


def step_oracle(nodes: list[Fraction], dt: float) -> dict:
    steps = walk(nodes, dt)
    energies, ends = steps["energies"], steps["ends"]
    powers = [energy / Fraction(dt) for energy in energies]  # over the WHOLE step, also the last one
    top = max(range(len(powers)), key=lambda index: (powers[index], -index))
    peak_time = max(range(len(nodes)), key=lambda index: (nodes[index], -index))
    holder = next(index for index, end in enumerate(ends) if end >= peak_time)
    last_span = Fraction(ends[-1]) - (Fraction(ends[-2]) if len(ends) > 1 else Fraction(0))
    return {
        "dt_s": dt,
        "steps": len(ends),
        "divides_the_support": last_span == Fraction(dt),
        "last_interval_s": float(last_span),
        "end_of_the_last_step_s": ends[-1],
        "total_kj": float(sum(energies)),
        "largest_step_power_kw": float(powers[top]),
        "largest_step_index": top,
        "largest_step_interval_s": [ends[top - 1] if top else 0.0, ends[top]],
        "step_holding_the_instantaneous_peak": holder,
        "power_of_that_step_kw": float(powers[holder]),
        "largest_step_power_minus_instantaneous_peak_kw": float(powers[top] - max(nodes)),
        "last_step_power_kw": float(powers[-1]),
        "last_step_energy_kj": float(energies[-1]),
        "step_energy_kj": [float(energy) for energy in energies],
    }


def triangle() -> dict:
    """Closed form: a triangle of peak 100 kW at 10 s read with steps that start at zero."""
    nodes = [Fraction(0)] * 21
    for index in range(21):
        nodes[index] = Fraction(10 * index) if index <= 10 else Fraction(10 * (20 - index))
    rows = []
    for dt in TRIANGLE_STEPS_S:
        steps = walk(nodes, dt)
        powers = [energy / Fraction(dt) for energy in steps["energies"]]
        on_a_step_end = (Fraction(10) / Fraction(dt)).denominator == 1
        # Peak on a step end: the two steps beside it average peak - slope dt / 2.
        # Peak in the middle of a step: that step averages peak - slope dt / 4.
        closed = 100 - Fraction(10) * Fraction(dt) / (2 if on_a_step_end else 4)
        rows.append({"dt_s": dt, "peak_on_a_step_end": on_a_step_end,
                     "largest_step_power_kw": float(max(powers)), "closed_form_kw": float(closed),
                     "total_kj": float(sum(steps["energies"]))})
    return {"table": [list(point) for point in TRIANGLE], "instantaneous_peak_kw": 100.0,
            "why": "a step returns the mean of its interval: with slopes of 10 kW/s the best step is the "
                   "peak minus 5 dt when the peak falls on a step end and minus 2.5 dt when it falls in "
                   "the middle of a step; the energy is the same for every step",
            "steps": rows}


def build() -> dict:
    nodes, fixture = run_nodes()
    total = builder.exact_energy(nodes, Fraction(0), Fraction(len(nodes) - 1))
    peak_time = max(range(len(nodes)), key=lambda index: (nodes[index], -index))
    by_step = {repr(dt): step_oracle(nodes, dt) for dt in STEPS_S}
    for item in by_step.values():
        if abs(Fraction(item["total_kj"]) - total) > Fraction(1, 10 ** 6):
            raise audit.Refusal("a partition does not add up to the table")
    return {
        "schema": SCHEMA,
        "scope": "bookkeeping oracle of a diagnostic coupling bench: energy and an equivalent oxygen debit; "
                 "no fuel mass, no species, no temperatures, not the combustion of the furniture",
        "run": "Test016", "reserved_runs_not_used": ["Test021"],
        "source_identity": fixture["expected_identity"],
        "support_end_s": float(len(nodes) - 1),
        "total_energy_kj": float(total),
        "instantaneous_peak": {"time_s": float(peak_time), "hrr_kw": float(nodes[peak_time])},
        "numerical_tolerance": {"abs_kj": builder.ABS_TOL_KJ, "rel": builder.REL_TOL,
                                "basis": "rounding of double precision; the same as the isolated owner"},
        "oxygen": {
            "kg_per_MJ": OXYGEN_KG_PER_MJ,
            "what_it_is": "equivalent demand prescribed by the bench: accepted energy times the constant the "
                          "engine sink already uses; not a stoichiometry validated for this chair and not a "
                          "reconstruction of the oxygen measured in the duct",
            "whole_run_kg": float(total / 1000 * Fraction(str(OXYGEN_KG_PER_MJ))),
        },
        "radiative_fractions": [
            {**item, "to_the_gas_kj": float(total * (1 - Fraction(str(item["value"])))),
             "radiative_term_kj": float(total * Fraction(str(item["value"])))}
            for item in RADIATIVE_FRACTIONS],
        "radiative_fraction_is": "a datum of the case, never of the source; none is a fraction measured in an enclosure",
        "peak_and_step": {
            "rule": "the power of a step is the energy of its interval over the whole step",
            "consequence": "its maximum over a run depends on the step and is not the instantaneous peak",
            "synthetic_triangle": triangle(),
        },
        "steps": by_step,
    }


def render(oracle: dict) -> str:
    """Deterministic text with one step energy per line."""
    body = json.loads(json.dumps(oracle, allow_nan=False))
    marks = {}
    for name, item in body["steps"].items():
        marks["@@%s@@" % name] = item["step_energy_kj"]
        item["step_energy_kj"] = "@@%s@@" % name
    text = json.dumps(body, indent=1, allow_nan=False)
    for mark, energies in marks.items():
        text = text.replace(json.dumps(mark), "[\n" + ",\n".join(
            "    " + json.dumps(energy, allow_nan=False) for energy in energies) + "\n   ]")
    if not text.isascii() or json.loads(text) != oracle:
        raise ValueError("the rendered oracle does not read back as built")
    return text + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render(build())
    if args.write:
        ORACLE.write_bytes(text.encode("ascii"))
    if args.check:
        same = ORACLE.exists() and ORACLE.read_bytes().replace(b"\r\n", b"\n").decode("ascii") == text
        print(json.dumps({"matches_committed_oracle": same}))
        return 0 if same else 1
    if not args.write:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
