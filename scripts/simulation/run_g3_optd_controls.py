#!/usr/bin/env python3
"""Monitored Gate B option-D controls: the 8 energy controls plus the O2 stress case.

Same launcher as the energy controls (one Godot process at a time, >= 6 GiB
free before every case, pre-existing error dialogs refuse the launch,
fresh-output validation, ledger v3). Diagnostic stimuli, not furniture data.

``o2_stress_cap`` was fixed on 2026-09-30 BEFORE any option-D engine change
(design section 9.1): the ventilated Salon (door 0-1 open -> bulk O2 path,
OxygenExchangeSystem cap = 5 % of the room O2 mass per step), one 300 MJ /
3000 kW object, ultra-fast growth and a 2 s step, so the per-step Thornton
debit can exceed the cap while the filter lag R is positive. It must not be
changed after it has been measured.

    python scripts/simulation/run_g3_optd_controls.py --phase on --tag pre
"""

from __future__ import annotations

import argparse
import copy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_energy_controls as energy  # noqa: E402
from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402


STRESS_DURATION_S = 600.0
STRESS_STEP_S = 2.0


def _stress() -> dict:
    obj = batch._object("g3_stress_object", 300.0, 3000.0)
    return {
        "template": "simple_house",
        "duration_s": STRESS_DURATION_S,
        "run_step_s": STRESS_STEP_S,
        "ignite_on_start": True,
        "ignition_room_id": 0,
        "watch_room_ids": [0],
        "log_interval_s": STRESS_STEP_S,
        "room_overrides": [{
            "id": 0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [obj],
        }],
        "engine_overrides": {
            "fire_spread_enabled": False,
            "glass_auto_break_enabled": False,
            "fire_alpha_kw_s2": 0.188,
            "fire_secondary_hrr_gain_kw": 0.0,
        },
    }


def cases() -> dict[str, dict]:
    selected = energy.cases()
    selected["o2_stress_cap"] = _stress()
    return selected


def run(phase: str, tag: str, selected: list[str] | None) -> int:
    scenarios = cases()
    if selected:
        unknown = sorted(set(selected) - scenarios.keys())
        if unknown:
            raise ValueError(f"unknown option-D controls: {unknown}")
        scenarios = {name: scenarios[name] for name in selected}
    for data in scenarios.values():
        data["engine_overrides"][batch.SWITCH] = energy.PHASES[phase]
    baseline.TIMEOUT_S = energy.TIMEOUT_S
    return baseline.run(
        case_scenarios=copy.deepcopy(scenarios),
        output_label=f"g3_optd_{tag}_{phase}",
        report_schema=f"g3_optd_controls_{tag}_{phase}_v1",
        extra_runner_args=[batch.LEDGER_ARG],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=sorted(energy.PHASES), required=True)
    parser.add_argument("--tag", required=True, help="engine state label: pre or optd")
    parser.add_argument("--case", action="append", dest="cases")
    args = parser.parse_args()
    try:
        raise SystemExit(run(args.phase, args.tag, args.cases))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 OPTD CONTROLS FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
