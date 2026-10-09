#!/usr/bin/env python3
"""Causal diagnosis of the two oxygen limits of the Test016 thermal coupling bench.

It launches one diagnostic fixture through the monitored launcher and evaluates
hypotheses that are written in this file BEFORE anything runs. Each one says what it
discriminates, what would confirm it and what would refute it. A control that makes a
symptom disappear is recorded as that and nothing more.

The fixture reads the oxygen probe the engine already carries for the G3 ledger and the
room state. Nothing here is physics, and no number of two overlapping oxygen
representations is ever added to another.

    python scripts/simulation/run_g3_object_hrr_oxygen_diagnosis.py --label before
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402

FIXTURE = "tests/fixtures/g3_object_hrr_oxygen_writes_diagnosis.gd"
PREFIX = "G3_OBJECT_HRR_OXYGEN_DIAGNOSIS"
SCHEMA = "g3_object_hrr_oxygen_diagnosis_v1"
SOURCES = ("sim/fire/PrescribedThermalSourceCoupling.gd", "sim/core/SimulationEngine.gd",
           "sim/core/OxygenExchangeSystem.gd", FIXTURE)
KG_PER_MJ = 0.076
ENERGY_KJ = 115093.655
REL = 1.0e-9

# Written before any run. `confirms` and `refutes` are the two outcomes; the predicate
# is `HYPOTHESES[name]["test"]`, evaluated on the recorded cases and never edited to fit.
HYPOTHESES: dict[str, dict] = {
    "A1_upper_write_is_the_full_demand_because_the_sink_never_learns_of_two_zones": {
        "discriminates": "which branch of the upper-layer sink runs in the open bench room, and why",
        "confirms": "every powered step takes the branch full_thornton, the probe says the sink does not see two "
                    "zones, and with that flag set in the oxygen system alone every step takes displacement",
        "refutes": "another branch, or the same branch with the flag set",
    },
    "A2_upper_and_room_numbers_overlap_and_are_not_a_partition": {
        "discriminates": "whether the second write debits an independent inventory",
        "confirms": "its mass base is the room air mass times a geometric fraction, the same room air the first "
                    "debit already used, and the room number is not kept equal to the weighted layers",
        "refutes": "disjoint bases whose weighted numbers always return the room number",
    },
    "A3_upper_write_does_not_reach_the_room_inventory_or_the_energy": {
        "discriminates": "whether the second write feeds back into the contracted debit or the accepted energy",
        "confirms": "with the other branch the room oxygen number and the applied power are identical bit by bit "
                    "over the whole run, and so are the accepted energy and the contracted debit",
        "refutes": "any difference in the room number, the power or the accepted energy",
    },
    "A4_upper_write_reaches_the_regime_indicator_through_the_lower_number": {
        "discriminates": "whether the second write can change when the bench leaves its regime",
        "confirms": "the lowest upper and lower numbers differ between the two branches",
        "refutes": "the same lower number with both branches",
    },
    "A5_the_all_sinks_counter_is_a_sum_of_overlapping_writes": {
        "discriminates": "what the kilograms published as a second debit measure",
        "confirms": "all-sinks minus primary equals what the upper sink applied; in the open room it equals the "
                    "contracted debit itself, so the sum is twice one consumption",
        "refutes": "a counter that matches an independent state change",
    },
    "A6_requested_applied_and_state_change_are_three_numbers": {
        "discriminates": "whether what a sink asks, what it applies and what its number shows can differ",
        "confirms": "they are reported apart and their differences, if any, are explained by a cap or a clamp",
        "refutes": "an unexplained difference",
    },
    "B1_no_source_and_zero_energy_are_the_same_engine": {
        "discriminates": "whether the source has any oxygen channel other than the room power",
        "confirms": "six numbers per step identical bit by bit over 120 steps",
        "refutes": "any difference",
    },
    "B2_in_a_sealed_room_the_sink_takes_another_route_after_the_power_was_written": {
        "discriminates": "which route ran at the rejected step and on which numbers",
        "confirms": "plume_lower route, nothing applied to the room inventory, a write on the lower number and "
                    "one on the upper number, and the room number recomposed from the layers",
        "refutes": "the room-inventory route, or no write at all",
    },
    "B3_a_rejected_step_leaves_no_trace_of_the_source": {
        "discriminates": "whether a rejected interval changes the room beside its twin without source",
        "confirms": "every oxygen number identical to the twin at every step, no heat, nothing accepted",
        "refutes": "any step whose numbers differ from the twin",
    },
    "B4_the_trace_scales_with_the_energy_of_the_rejected_interval": {
        "discriminates": "whether what is left behind is the debit of the first interval",
        "confirms": "the plume debit of step 0 equals the energy of that interval times the coefficient, for two steps",
        "refutes": "a trace unrelated to that energy",
    },
    "B5_after_leaving_the_regime_by_a_rule_nothing_is_debited": {
        "discriminates": "whether an exit decided before the power is written leaves a debit",
        "confirms": "from the exit step on every sink counter is zero, also after the oxygen is restored",
        "refutes": "any debit after the exit",
    },
}


# What each run must show, written before the run it judges. The predicates above are the
# same for both labels. `before` is the bench as published in 1a39332a: everything holds
# except B3, which is the defect. `after` is the corrected bench, which rejects the interval
# before any write: B3 must hold, and B2 and B4, which describe the trace of the rejected
# step, must be refuted by the outcome their own text names ("no write at all").
EXPECTED: dict[str, dict[str, bool]] = {
    "before": {name: not name.startswith("B3_") for name in HYPOTHESES},
    "after": {name: not (name.startswith("B2_") or name.startswith("B4_")) for name in HYPOTHESES},
}


def _close(a: float, b: float, rel: float = REL) -> bool:
    return abs(a - b) <= rel * max(abs(a), abs(b), 1.0e-300) or abs(a - b) <= 1.0e-15


def evaluate(cases: dict) -> dict:
    """Every hypothesis against the recorded cases. No number is fitted and none is added to another."""
    out = {}
    open25, open10, other = cases["open_dt_2.5"], cases["open_dt_1.0"], cases["open_dt_2.5_other_upper_branch"]
    sealed25, sealed10 = cases["sealed_dt_2.5"], cases["sealed_dt_1.0"]
    crack, twin = cases["crack_and_recovery"], cases["no_source_against_zero_energy"]
    contracted = ENERGY_KJ / 1000.0 * KG_PER_MJ

    branches, other_branches = open25["totals"]["upper_number_branches"], other["totals"]["upper_number_branches"]
    saw_two_zones = [row["sink_sees_two_zones"] for row in open25["window"]]
    out["A1_upper_write_is_the_full_demand_because_the_sink_never_learns_of_two_zones"] = {
        "holds": set(branches) == {"full_thornton"} and not any(saw_two_zones) and set(other_branches) == {"displacement"},
        "branches": branches, "branches_with_the_flag_set": other_branches, "sink_saw_two_zones": saw_two_zones,
        "second_over_first_with_the_flag_set": other["totals"]["upper_number_requested_kg"] / other["totals"]["room_inventory_requested_kg"],
    }

    bases = [(row["sinks"].get("upper", {}).get("mass_base_kg"), row["air_mass_kg"] * row["upper_frac"],
              row["sinks"].get("bulk", {}).get("mass_base_kg"), row["air_mass_kg"]) for row in open25["window"]
             if "upper" in row["sinks"] and "bulk" in row["sinks"]]
    out["A2_upper_and_room_numbers_overlap_and_are_not_a_partition"] = {
        "holds": bool(bases) and all(_close(a, b) and _close(c, d) for a, b, c, d in bases)
                 and abs(open25["totals"]["largest_room_number_minus_weighted_layers"]) > 1.0e-6,
        "upper_base_is_room_air_times_a_geometric_fraction": [[a, b] for a, b, _c, _d in bases],
        "room_base_is_the_whole_room_air": [[c, d] for _a, _b, c, d in bases],
        "largest_room_number_minus_weighted_layers": open25["totals"]["largest_room_number_minus_weighted_layers"],
    }

    out["A3_upper_write_does_not_reach_the_room_inventory_or_the_energy"] = {
        "holds": open25["room_o2_sha256"] == other["room_o2_sha256"] and open25["power_sha256"] == other["power_sha256"]
                 and open25["accepted_kj"] == other["accepted_kj"]
                 and open25["bench_oxygen_debited_kg"] == other["bench_oxygen_debited_kg"],
        "room_number_series_identical": open25["room_o2_sha256"] == other["room_o2_sha256"],
        "power_series_identical": open25["power_sha256"] == other["power_sha256"],
        "accepted_kj": [open25["accepted_kj"], other["accepted_kj"]],
        "contracted_debit_kg": [open25["bench_oxygen_debited_kg"], other["bench_oxygen_debited_kg"]],
    }

    out["A4_upper_write_reaches_the_regime_indicator_through_the_lower_number"] = {
        "holds": open25["totals"]["lowest_o2_lower"] != other["totals"]["lowest_o2_lower"]
                 and open25["totals"]["lowest_o2_upper"] != other["totals"]["lowest_o2_upper"],
        "lowest_upper_number": [open25["totals"]["lowest_o2_upper"], other["totals"]["lowest_o2_upper"]],
        "lowest_lower_number": [open25["totals"]["lowest_o2_lower"], other["totals"]["lowest_o2_lower"]],
        "lowest_room_number": [open25["totals"]["lowest_o2"], other["totals"]["lowest_o2"]],
        "lower_number_drained_towards_the_upper": [open25["totals"]["lower_number_drained_towards_the_upper_fraction_sum"],
                                                   other["totals"]["lower_number_drained_towards_the_upper_fraction_sum"]],
    }

    rows = {}
    for name, case in (("open_dt_2.5", open25), ("open_dt_1.0", open10), ("open_dt_2.5_other_upper_branch", other)):
        totals = case["totals"]
        rows[name] = {
            "all_sinks_minus_primary_kg": totals["accumulator_all_sinks_kg"] - totals["accumulator_primary_kg"],
            "upper_number_applied_kg": totals["upper_number_applied_kg"],
            "contracted_debit_kg": totals["accumulator_room_inventory_kg"],
            "all_sinks_over_contracted": totals["accumulator_all_sinks_kg"] / totals["accumulator_room_inventory_kg"],
        }
    out["A5_the_all_sinks_counter_is_a_sum_of_overlapping_writes"] = {
        "holds": all(_close(item["all_sinks_minus_primary_kg"], item["upper_number_applied_kg"], 1.0e-9) for item in rows.values())
                 and _close(rows["open_dt_2.5"]["upper_number_applied_kg"], contracted, 1.0e-9)
                 and _close(rows["open_dt_2.5"]["all_sinks_over_contracted"], 2.0, 1.0e-9),
        "by_case": rows, "one_consumption_kg": contracted,
    }

    triples = {}
    explained = True
    for name, case in (("open_dt_2.5", open25), ("open_dt_1.0", open10), ("open_dt_2.5_other_upper_branch", other)):
        totals = case["totals"]
        triples[name] = {
            "room_inventory": [totals["room_inventory_requested_kg"], totals["room_inventory_applied_kg"],
                               totals["room_inventory_mass_change_at_the_write_kg"], totals["room_inventory_steps_capped"]],
            "upper_number": [totals["upper_number_requested_kg"], totals["upper_number_applied_kg"],
                             totals["upper_number_state_change_on_its_base_kg"], totals["upper_number_steps_capped"]],
        }
        for requested, applied, shown, capped in triples[name].values():
            if capped == 0 and not (_close(requested, applied, 1.0e-9) and _close(applied, shown, 1.0e-6)):
                explained = False
    out["A6_requested_applied_and_state_change_are_three_numbers"] = {
        "holds": explained, "requested_applied_shown_capped_steps": triples,
        "what_it_means": "kg of the upper number are kg on the upper base; they are listed beside the room "
                         "inventory, never added to it",
    }

    out["B1_no_source_and_zero_energy_are_the_same_engine"] = {
        "holds": twin["differing"] == 0 and twin["zero_energy_accepted_kj"] == 0.0,
        "differing_numbers": twin["differing"], "first_difference": twin["first_difference"],
    }

    first = {name: case["rows"][0] for name, case in (("sealed_dt_2.5", sealed25), ("sealed_dt_1.0", sealed10))}
    out["B2_in_a_sealed_room_the_sink_takes_another_route_after_the_power_was_written"] = {
        "holds": all(row["plume_lower_mode"] is True and "bulk" not in row["sinks"] and "plume_lower" in row["sinks"]
                     and row["consumed_room_inventory_step_kg"] == 0.0 for row in first.values()),
        "step_0": {name: {"plume_lower_route": row["plume_lower_mode"], "sinks": sorted(row["sinks"]),
                          "room_inventory_debit_kg": row["consumed_room_inventory_step_kg"],
                          "lower_number_write_kg": row["sinks"].get("plume_lower", {}).get("applied_kg"),
                          "upper_number_write_kg": row["sinks"].get("upper", {}).get("applied_kg"),
                          "upper_branch": row["sinks"].get("upper", {}).get("branch"),
                          "bench_state_after": row["bench_state"], "power_after_kw": row["power_kw"]}
                   for name, row in first.items()},
    }

    out["B3_a_rejected_step_leaves_no_trace_of_the_source"] = {
        "holds": all(case["steps_whose_oxygen_numbers_differ_from_the_twin"] == 0 and case["accepted_kj"] == 0.0
                     and case["to_the_gas_kj"] == 0.0 for case in (sealed25, sealed10)),
        "steps_that_differ_from_the_twin": {"sealed_dt_2.5": sealed25["steps_whose_oxygen_numbers_differ_from_the_twin"],
                                            "sealed_dt_1.0": sealed10["steps_whose_oxygen_numbers_differ_from_the_twin"]},
        "of_steps": sealed25["steps"],
        "gap_at_step_0": {name: case["rows"][0]["minus_the_twin_without_source"] for name, case in
                          (("sealed_dt_2.5", sealed25), ("sealed_dt_1.0", sealed10))},
        "gap_at_the_last_step": {name: case["rows"][-1]["minus_the_twin_without_source"] for name, case in
                                 (("sealed_dt_2.5", sealed25), ("sealed_dt_1.0", sealed10))},
        "bench_reports_debited_without_heat_kg": [sealed25["bench_reports_debited_without_heat_kg"],
                                                  sealed10["bench_reports_debited_without_heat_kg"]],
    }

    # Energy of the first interval, from the committed table and by hand: whole trapezoids, then a part of one.
    table = [item["hrr_kw"] for item in json.loads(
        (ROOT / "tests/fixtures/g3_object_hrr_source_test016.json").read_text(encoding="utf-8"))["source"]["samples"][:4]]
    at_2_5 = table[2] + 0.5 * (table[3] - table[2])
    first_interval_kj = {"sealed_dt_2.5": 0.5 * (table[0] + table[1]) + 0.5 * (table[1] + table[2]) + 0.5 * (table[2] + at_2_5) * 0.5,
                         "sealed_dt_1.0": 0.5 * (table[0] + table[1])}
    scale = {}
    for name, row in first.items():
        wrote = row["sinks"].get("plume_lower", {}).get("applied_kg", 0.0)
        scale[name] = {"lower_number_write_kg": wrote, "first_interval_energy_times_coefficient_kg":
                       first_interval_kj[name] / 1000.0 * KG_PER_MJ}
    out["B4_the_trace_scales_with_the_energy_of_the_rejected_interval"] = {
        "holds": all(item["lower_number_write_kg"] == 0.0 or _close(
            item["lower_number_write_kg"], item["first_interval_energy_times_coefficient_kg"], 1.0e-9) for item in scale.values())
                 and any(item["lower_number_write_kg"] > 0.0 for item in scale.values()),
        "by_step": scale,
    }

    out["B5_after_leaving_the_regime_by_a_rule_nothing_is_debited"] = {
        "holds": crack["from_the_exit_step_on"]["accumulator_all_sinks_kg"] == 0.0
                 and crack["after_the_oxygen_was_restored"]["accumulator_all_sinks_kg"] == 0.0
                 and crack["accepted_kj"] == crack["accepted_kj_after_recovery"]
                 and crack["state_after_recovery"] == "outside_declared_regime",
        "exit": crack["exit"], "debited_from_the_exit_on_kg": crack["from_the_exit_step_on"]["accumulator_all_sinks_kg"],
        "debited_after_the_recovery_kg": crack["after_the_oxygen_was_restored"]["accumulator_all_sinks_kg"],
        "state_after_recovery": crack["state_after_recovery"],
    }
    return out


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def _head() -> str:
    return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", choices=("before", "after"))
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    plan = {name: {key: item[key] for key in ("discriminates", "confirms", "refutes")} for name, item in HYPOTHESES.items()}
    if args.plan_only:
        print(json.dumps({"hypotheses": plan, "executed": False}, indent=1))
        return 0
    if args.label is None:
        parser.error("--label is required to run")
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    run = godot_monitored_launch.run([godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
                                     timeout_s=900, environment=os.environ.copy())
    if not run.launched or run.faults or run.preexisting:
        raise RuntimeError(f"not a healthy run: {run.faults or run.preexisting}")
    if "SCRIPT ERROR" in run.stdout + run.stderr or "Parse Error" in run.stdout + run.stderr:
        raise RuntimeError("script error in the diagnostic fixture:\n" + run.stderr[:2000])
    line = next(line for line in run.stdout.splitlines() if line.startswith(PREFIX + " {"))
    payload = json.loads(line.split(" ", 1)[1])
    if run.returncode != 0 or payload["notes"]:
        raise RuntimeError(f"the diagnostic fixture did not complete: {payload['notes']}")
    verdicts = evaluate(payload["cases"])
    for name in verdicts:
        verdicts[name] = {**plan[name], **verdicts[name]}
    holds = {name: bool(item["holds"]) for name, item in verdicts.items()}
    record = {
        "schema": SCHEMA, "label": args.label, "head": _head(),
        "expected": EXPECTED[args.label], "as_expected": holds == EXPECTED[args.label],
        "scope": "what the engine writes to its oxygen numbers around the bench; diagnosis, not acceptance",
        "sources_sha256": {relative: _sha(ROOT / relative) for relative in SOURCES},
        "hypotheses": verdicts,
        "cases": payload["cases"],
    }
    saved = ROOT / "docs" / "validation" / f"G3_OBJECT_HRR_OXYGEN_DIAGNOSIS_{args.label.upper()}_2026-10-09.json"
    saved.write_bytes((json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    print(json.dumps({name: item["holds"] for name, item in verdicts.items()}, indent=1))
    print(saved.relative_to(ROOT).as_posix())
    return 0 if record["as_expected"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
