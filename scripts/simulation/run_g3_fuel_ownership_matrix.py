#!/usr/bin/env python3
"""Monitored G3-1 closure batch: minimal cases that separate fuel ownership.

Diagnostic only. Every synthetic case shares geometry, ignition, ventilation
and engine overrides with the G3-0 controls; only room 0's declared room
load and explicit objects change. Energies are small (1-6 MJ) so that
exhaustion happens inside 90 s; they are not furniture data.

The two ``ambiguous_real_*`` cases copy the distributed
``scenarios/compact_apartment_reference.json`` into ``runs/`` (the
distributed file is never written). The counterfactual equalises the CO and
smoke yields of the three non-primary salon objects to the sofa's values: if
those objects never burn, any change in room CO/smoke is attribution from
inactive objects.

Runs one Godot process at a time through ``run_g3_fuel_baseline.run`` and its
native monitor, memory gate and output validation.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation.analyze_g3_fuel_ownership import analyze, classify, contract_violations  # noqa: E402


REAL_SOURCE = ROOT / "scenarios/compact_apartment_reference.json"
REAL_PRIMARY_ID = "compact_sofa"


def _object(object_id: str, energy_mj: float, max_kw: float, co_yield: float,
            smoke_yield: float, primary: bool, *, cold: bool = False,
            x: float = 0.2) -> dict:
    obj = copy.deepcopy(baseline._sofa())
    obj.update({
        "id": object_id, "name": object_id,
        "position_m": {"x": x, "y": 1.4},
        "fuel_energy_MJ": energy_mj, "remaining_fuel_MJ": energy_mj,
        "max_hrr_kw": max_kw, "co_yield_kg_per_MJ": co_yield,
        "smoke_yield_kg_per_MJ": smoke_yield,
        "is_primary_ignition_source": primary,
    })
    if cold:
        cold_chair = baseline._unignited_chair()
        for key in ("kind", "position_m", "size_m", "footprint_m2", "exposed_area_m2",
                    "elevation_m", "ignition_temp_c", "ignition_flux_kw_m2"):
            obj[key] = copy.deepcopy(cold_chair[key])
    return obj


def _synthetic(room_mj: float, room_kw: float, objects: list[dict]) -> dict:
    data = copy.deepcopy(baseline.case_data("room_only"))
    room = data["room_overrides"][0]
    room["fuel_energy_MJ"] = room_mj
    room["max_hrr_kw"] = room_kw
    room["fuel_objects"] = objects
    return data


def _real(equalise_cold_yields: bool) -> dict:
    data = json.loads(REAL_SOURCE.read_text(encoding="utf-8"))
    data.update({
        "duration_s": baseline.DURATION_S,
        "ignite_on_start": True,
        "watch_room_ids": [0],
        "log_interval_s": 1.0,
    })
    if equalise_cold_yields:
        room = next(r for r in data["rooms_data"] if int(r["id"]) == 0)
        primary = next(o for o in room["fuel_objects"] if o["id"] == REAL_PRIMARY_ID)
        for obj in room["fuel_objects"]:
            if obj["id"] != REAL_PRIMARY_ID:
                obj["co_yield_kg_per_MJ"] = primary["co_yield_kg_per_MJ"]
                obj["smoke_yield_kg_per_MJ"] = primary["smoke_yield_kg_per_MJ"]
    return data


def cases() -> dict[str, dict]:
    sofa = lambda mj, kw, co=0.0004, smoke=0.012, oid="g3_sofa", x=0.2: _object(  # noqa: E731
        oid, mj, kw, co, smoke, True, x=x)
    return {
        "empty_room": _synthetic(0.0, 0.0, []),
        "single_object": _synthetic(0.0, 0.0, [sofa(3.0, 100.0)]),
        "two_objects_burning": _synthetic(0.0, 0.0, [
            sofa(3.0, 50.0, oid="g3_sofa_a"),
            sofa(3.0, 50.0, co=0.004, smoke=0.008, oid="g3_sofa_b", x=3.0),
        ]),
        "second_object_cold": _synthetic(0.0, 0.0, [
            sofa(3.0, 100.0),
            _object("g3_cold_chair", 3.0, 100.0, 0.004, 0.008, False, cold=True),
        ]),
        "object_exhausted_room_residual": _synthetic(3.0, 100.0, [sofa(1.0, 100.0)]),
        "room_below_objects": _synthetic(1.0, 100.0, [sofa(3.0, 100.0)]),
        "explicit_room_aggregate": _synthetic(3.0, 100.0, []),
        "ambiguous_real_compact_salon": _real(False),
        "ambiguous_real_compact_salon_cold_yields_equalised": _real(True),
    }


def _extra(out_dir: Path) -> dict:
    result = analyze(out_dir / "fuel_source_ledger.jsonl")
    return {"ownership": result, "findings": classify(result)}


def declared_inventory(scenario: dict) -> dict:
    """Room 0 declared load and per-object HRR caps, from either format."""
    if "rooms_data" in scenario:
        room = next(r for r in scenario["rooms_data"] if int(r["id"]) == 0)
    else:
        room = scenario["room_overrides"][0]
    return {
        "room_MJ": float(room.get("fuel_energy_MJ", 0.0)),
        "room_max_hrr_kw": float(room.get("max_hrr_kw", 0.0)),
        "object_energy_MJ": {o["id"]: float(o["fuel_energy_MJ"]) for o in room.get("fuel_objects", [])},
        "object_max_hrr_kw": {o["id"]: float(o["max_hrr_kw"]) for o in room.get("fuel_objects", [])},
    }


SUMMARY_FIELDS = (
    "steps", "has_explicit_objects", "last_consuming_time_s",
    "max_hrr_kw", "room_consumed_MJ", "explicit_burn_MJ", "net_gap_MJ",
    "unowned_MJ", "first_unowned_time_s", "inventory_excess_MJ",
    "remaining_in_explicit_objects_MJ", "co_generated_kg", "co_generated_unowned_kg",
    "smoke_generated_kg", "smoke_generated_unowned_kg", "nominal_explicit_co_kg",
    "max_object_hrr_excess_over_room_kw", "inactive_objects",
)


def summarize(run_root: Path) -> dict:
    report = json.loads((run_root / "report.json").read_text(encoding="utf-8"))
    results, declared, cases_out = {}, {}, []
    for case in report["cases"]:
        name = case["name"]
        out_dir = run_root / name
        health = json.loads((out_dir / "monitor.health.json").read_text(encoding="utf-8"))
        result = analyze(out_dir / "fuel_source_ledger.jsonl")
        results[name] = result
        declared[name] = declared_inventory(json.loads((out_dir / "scenario.json").read_text(encoding="utf-8")))
        cases_out.append({
            "name": name,
            "scenario_sha256": case["scenario_sha256"],
            "declared": declared[name],
            "health": {key: health.get(key) for key in (
                "timed_out", "error_dialogs", "residual_godot_processes", "process_quiescent")},
            "csv_last_time_s": case["metrics"]["last_time_s"],
            "result": {key: result[key] for key in SUMMARY_FIELDS},
            "objects": {oid: {k: state[k] for k in (
                "burn_MJ", "max_hrr_kw", "initial_remaining_MJ", "final_remaining_MJ",
                "final_state", "exhausted_time_s")} for oid, state in result["objects"].items()},
        })
    return {
        "schema": "g3_fuel_ownership_dynamic_summary_v1",
        "run": run_root.name,
        "contract_rel_tolerance": 0.01,
        "cases": cases_out,
        "contract_violations": contract_violations(results, declared),
    }


def run() -> int:
    return baseline.run(
        case_scenarios=cases(),
        output_label="g3_fuel_ownership_matrix",
        report_schema="g3_fuel_ownership_matrix_v1",
        case_extra_metrics=_extra,
    )


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--summarize":
        print(json.dumps(summarize(Path(sys.argv[2])), ensure_ascii=False, indent=2))
        raise SystemExit(0)
    try:
        raise SystemExit(run())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 OWNERSHIP MATRIX FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
