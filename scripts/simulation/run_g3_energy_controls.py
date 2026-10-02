#!/usr/bin/env python3
"""Monitored Gate B energy controls: ventilated sofa and O2-limited room.

Long (600-900 s) diagnostic stimuli, not furniture data. Reuses the G3-3
launcher (one Godot process at a time, >= 6 GiB free before every case,
pre-existing error dialogs refuse the launch, fresh-output validation) and
the passive ledger v3.

    python scripts/simulation/run_g3_energy_controls.py --phase on --tag pre
"""

from __future__ import annotations

import argparse
import copy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402


VENT_DURATION_S = 600.0
O2_DURATION_S = 900.0
TIMEOUT_S = 900
PHASES = {"off": False, "on": True}

# Geometry and O2 settings of sim/validation/cases/v7_underventilated_co_peak.json
# (door 0-1 closed), with the room load replaced by one explicit object and
# no secondary ignition. time_scale is a GUI setting and is not copied.
_V7_OVERRIDES = {
    "fire_spread_enabled": False,
    "glass_auto_break_enabled": False,
    "fire_alpha_kw_s2": 0.04,
    "fire_o2_min_for_flame": 0.10,
    "fire_secondary_hrr_gain_kw": 0.0,
    "fire_latent_o2_viable_margin": 0.008,
    "fire_extinction_delay_s": 240.0,
    "fire_latent_extinction_delay_s": 300.0,
}


def _vent(case: str, *, step_s: float | None = None) -> dict:
    data = batch.cases()[case]
    data["duration_s"] = VENT_DURATION_S
    if step_s is not None:
        data["run_step_s"] = step_s
    return data


def _o2(*, reopen_s: float | None = None, step_s: float | None = None) -> dict:
    sofa = batch._object("g3_sofa", 120.0, 600.0)
    data = {
        "template": "simple_house",
        "duration_s": O2_DURATION_S,
        "ignite_on_start": True,
        "ignition_room_id": 0,
        "watch_room_ids": [0],
        "log_interval_s": 1.0,
        "opening_overrides": [{"a": 0, "b": 1, "type": "door", "open_fraction": 0.0}],
        "room_overrides": [{
            "id": 0, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0, "fuel_objects": [sofa],
        }],
        "engine_overrides": copy.deepcopy(_V7_OVERRIDES),
    }
    if reopen_s is not None:
        data["opening_events"] = [
            {"time_s": reopen_s, "a": 0, "b": 1, "type": "door", "open_fraction": 1.0}
        ]
    if step_s is not None:
        data["run_step_s"] = step_s
    return data


def cases() -> dict[str, dict]:
    return {
        "sofa_vent": _vent("single_object"),
        "sofa_vent_dt24": _vent("single_object", step_s=1.0 / 24.0),
        "two_active_vent": _vent("two_active_objects"),
        "low_power_vent": _vent("low_power_object"),
        "o2_closed": _o2(),
        "o2_closed_dt24": _o2(step_s=1.0 / 24.0),
        "o2_reopen_300": _o2(reopen_s=300.0),
        "o2_reopen_700": _o2(reopen_s=700.0),
    }


def run(phase: str, tag: str, selected: list[str] | None) -> int:
    scenarios = cases()
    if selected:
        unknown = sorted(set(selected) - scenarios.keys())
        if unknown:
            raise ValueError(f"unknown energy controls: {unknown}")
        scenarios = {name: scenarios[name] for name in selected}
    for data in scenarios.values():
        data["engine_overrides"][batch.SWITCH] = PHASES[phase]
    baseline.TIMEOUT_S = TIMEOUT_S
    return baseline.run(
        case_scenarios=scenarios,
        output_label=f"g3_energy_{tag}_{phase}",
        report_schema=f"g3_energy_controls_{tag}_{phase}_v1",
        extra_runner_args=[batch.LEDGER_ARG],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=sorted(PHASES), required=True)
    parser.add_argument("--tag", required=True, help="engine state label, e.g. pre or optd")
    parser.add_argument("--case", action="append", dest="cases")
    args = parser.parse_args()
    try:
        raise SystemExit(run(args.phase, args.tag, args.cases))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 ENERGY CONTROLS FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
