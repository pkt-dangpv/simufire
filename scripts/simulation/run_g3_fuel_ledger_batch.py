#!/usr/bin/env python3
"""Monitored G3-3 batch: decisive fuel-ownership cases, before and after the fix.

The same nine scenarios are run in every phase so outputs can be compared
byte for byte:

* ``before``  - unmodified engine, legacy ledger v2 only;
* ``ledger``  - passive G3-3 ledger v3 on (``--g3-fuel-ledger-v3``), physics OFF;
* ``off``     - after the fix, switch OFF, ledger v3 on;
* ``on``      - switch ``fire_explicit_object_fuel_ownership_enabled`` ON.

Energies are small (1-6 MJ) diagnostic stimuli, not furniture data. One
Godot process at a time through ``run_g3_fuel_baseline.run`` (native
monitor, >= 6 GiB free before every case, fresh-output validation).

    python scripts/simulation/run_g3_fuel_ledger_batch.py --phase before
"""

from __future__ import annotations

import argparse
import copy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402


SWITCH = "fire_explicit_object_fuel_ownership_enabled"
LEDGER_ARG = "--g3-fuel-ledger-v3"
PHASES = {
    "before": {"ledger": False, "switch": None},
    "ledger": {"ledger": True, "switch": None},
    "off": {"ledger": True, "switch": False},
    "on": {"ledger": True, "switch": True},
}


def _object(object_id: str, energy_mj: float, max_kw: float, *, co: float = 0.0004,
            smoke: float = 0.012, primary: bool = True, cold: bool = False,
            x: float = 0.2, kind: str | None = None) -> dict:
    obj = copy.deepcopy(baseline._sofa())
    obj.update({
        "id": object_id, "name": object_id, "position_m": {"x": x, "y": 1.4},
        "fuel_energy_MJ": energy_mj, "remaining_fuel_MJ": energy_mj,
        "max_hrr_kw": max_kw, "co_yield_kg_per_MJ": co,
        "smoke_yield_kg_per_MJ": smoke, "is_primary_ignition_source": primary,
    })
    if kind is not None:
        obj["kind"] = kind
    if cold:
        chair = baseline._unignited_chair()
        for key in ("kind", "position_m", "size_m", "footprint_m2", "exposed_area_m2",
                    "elevation_m", "ignition_temp_c", "ignition_flux_kw_m2"):
            obj[key] = copy.deepcopy(chair[key])
    return obj


def _room(room_mj: float, room_kw: float, objects: list[dict]) -> dict:
    data = copy.deepcopy(baseline.case_data("room_only"))
    room = data["room_overrides"][0]
    room.update({"fuel_energy_MJ": room_mj, "max_hrr_kw": room_kw, "fuel_objects": objects})
    return data


def cases() -> dict[str, dict]:
    return {
        "empty_room": _room(0.0, 0.0, []),
        "single_object": _room(0.0, 0.0, [_object("g3_sofa", 3.0, 100.0)]),
        "sofa_plus_cold_chair": _room(0.0, 0.0, [
            _object("g3_sofa", 3.0, 100.0),
            _object("g3_cold_chair", 3.0, 100.0, co=0.004, smoke=0.008, primary=False, cold=True),
        ]),
        "two_active_objects": _room(0.0, 0.0, [
            _object("g3_sofa_a", 3.0, 50.0),
            _object("g3_sofa_b", 3.0, 50.0, co=0.004, smoke=0.008, x=3.0),
        ]),
        "room_load_above_objects": _room(3.0, 100.0, [_object("g3_sofa", 1.0, 100.0)]),
        "room_load_below_objects": _room(1.0, 100.0, [_object("g3_sofa", 3.0, 100.0)]),
        "low_power_object": _room(0.0, 0.0, [
            _object("g3_sofa", 3.0, 100.0),
            _object("g3_low_power", 3.0, 10.0, x=3.0),
        ]),
        # The explicit_objects way to declare the extra 2 MJ of the
        # room_load_above_objects case: a named aggregate source, not a room total.
        "named_aggregate_source": _room(0.0, 0.0, [
            _object("g3_sofa", 1.0, 100.0),
            _object("g3_named_room_contents", 2.0, 100.0, x=3.0, kind="contenido_agregado"),
        ]),
        "room_aggregate_only": _room(3.0, 100.0, []),
    }


def scenarios_for(phase: str) -> dict[str, dict]:
    spec = PHASES[phase]
    selected = cases()
    if spec["switch"] is not None:
        for data in selected.values():
            data["engine_overrides"][SWITCH] = spec["switch"]
    return selected


def run(phase: str) -> int:
    spec = PHASES[phase]
    return baseline.run(
        case_scenarios=scenarios_for(phase),
        output_label=f"g3_fuel_ledger_{phase}",
        report_schema=f"g3_fuel_ledger_batch_{phase}_v1",
        extra_runner_args=[LEDGER_ARG] if spec["ledger"] else [],
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=sorted(PHASES), required=True)
    args = parser.parse_args()
    try:
        raise SystemExit(run(args.phase))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 LEDGER BATCH FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
