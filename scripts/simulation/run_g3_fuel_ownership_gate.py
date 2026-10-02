#!/usr/bin/env python3
"""Monitored G3 control for unequal room/object fuel inventories.

Diagnostic only: all cases keep the same room, ignition, ventilation, and
nominal 100 kW cap. The four inventories are deliberately artificial, not
furniture data for product or a proposed calibration.
"""

from __future__ import annotations

import copy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_fuel_baseline as baseline


CASE_ENERGY_MJ = {
    "room_only_3": (3.0, None),
    "object_only_3": (0.0, 3.0),
    "room_3_object_1": (3.0, 1.0),
    "room_1_object_3": (1.0, 3.0),
}


def case_data(name: str) -> dict:
    if name not in CASE_ENERGY_MJ:
        raise ValueError(f"unknown G3 ownership control {name}")
    room_mj, object_mj = CASE_ENERGY_MJ[name]
    source = "room_only" if object_mj is None else "sofa_objects_only"
    data = copy.deepcopy(baseline.case_data(source))
    room = data["room_overrides"][0]
    room["fuel_energy_MJ"] = room_mj
    room["max_hrr_kw"] = 100.0 if room_mj > 0.0 else 0.0
    if object_mj is not None:
        obj = room["fuel_objects"][0]
        obj["fuel_energy_MJ"] = object_mj
        obj["remaining_fuel_MJ"] = object_mj
        obj["max_hrr_kw"] = 100.0
    return data


def run() -> int:
    cases = {name: case_data(name) for name in CASE_ENERGY_MJ}
    return baseline.run(
        case_scenarios=cases,
        output_label="g3_fuel_ownership_gate",
        report_schema="g3_fuel_ownership_gate_v1",
    )


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 OWNERSHIP GATE FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
