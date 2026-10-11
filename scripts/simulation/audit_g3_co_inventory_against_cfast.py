#!/usr/bin/env python3
"""Compare raw SimuFire zonal CO inventory with CFAST, without changing gates.

This is a diagnostic comparator, not the 346-check reference validator. It
requires opt-in ``co_inventory_trace.jsonl`` files from ``run_scenario.py`` and
never substitutes the legacy COl heuristic or the room-average CO for lower
zone CO. No tolerance is used to turn model disagreement into a pass.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TRACE_ROOT = ROOT / "runs" / "g3_co_inventory_20260926"
CFAST_ROOT = ROOT / "sim" / "validation" / "cfast"
CO_TO_AIR_MOLAR_MASS_RATIO = 29.0 / 28.0
MASS_EPS_KG = 1.0e-12
PPM_EPS = 1.0e-6

# (SimuFire room id, CFAST compartment suffix, diagnostic times in seconds).
CASE_ROOMS: dict[str, tuple[tuple[int, int, tuple[int, ...]], ...]] = {
    "cfast_single_room_closed": ((0, 1, (120, 240)),),
    "cfast_bedroom_closed_door": ((2, 1, (240, 480)),),
    "cfast_post_flashover_vented": ((0, 1, (180, 240, 300, 360)),),
    "cfast_corridor_chain": (
        (0, 1, (180, 300, 480, 590)),
        (1, 2, (180, 300, 480, 590)),
        (2, 3, (180, 300, 480, 590)),
    ),
    "cfast_two_room_door_open": (
        (0, 1, (120, 240, 360, 480)),
        (1, 2, (120, 240, 360, 480)),
    ),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_trace(path: Path) -> dict[tuple[int, float], dict]:
    """Fail closed on malformed or duplicated raw observations."""
    result: dict[tuple[int, float], dict] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        row = json.loads(line)
        required = (
            "room_id", "time_s", "co_total_kg", "co_upper_raw_kg",
            "co_lower_kg", "co_lower_mass_ppm", "co_lower_legacy_ppm",
            "lower_geometric_kg", "upper_gas_kg", "co_upper_ppm", "hot_layer_m",
        )
        missing = [name for name in required if name not in row]
        if missing:
            raise ValueError(f"{path}:{line_number}: missing {missing}")
        numbers = [float(row[name]) for name in required[1:]]
        if not all(math.isfinite(value) for value in numbers):
            raise ValueError(f"{path}:{line_number}: non-finite observation")
        total = float(row["co_total_kg"])
        upper = float(row["co_upper_raw_kg"])
        lower = float(row["co_lower_kg"])
        if total < -MASS_EPS_KG or upper < -MASS_EPS_KG or upper > total + MASS_EPS_KG:
            raise ValueError(f"{path}:{line_number}: invalid raw CO inventory")
        if abs(lower - max(0.0, total - max(0.0, upper))) > MASS_EPS_KG:
            raise ValueError(f"{path}:{line_number}: lower CO mass is not total minus upper")
        denominator = float(row["lower_geometric_kg"])
        if denominator <= 0:
            raise ValueError(f"{path}:{line_number}: invalid lower gas denominator")
        if float(row["upper_gas_kg"]) < 0.1:
            # The engine defines no lower zone here and returns the room mean.
            # This older trace lacks volume_m3, so its mean cannot be recomputed
            # independently. Verify the branch identity and label it explicitly.
            expected_ppm = float(row["co_lower_legacy_ppm"])
            row["co_representation"] = "room_mean_no_upper_zone"
        else:
            expected_ppm = lower * CO_TO_AIR_MOLAR_MASS_RATIO * 1.0e6 / max(0.1, denominator)
            row["co_representation"] = "raw_lower_inventory"
        if abs(expected_ppm - float(row["co_lower_mass_ppm"])) > max(
            PPM_EPS, abs(expected_ppm) * 1.0e-9
        ):
            raise ValueError(f"{path}:{line_number}: lower ppm does not follow its source")
        key = (int(row["room_id"]), float(row["time_s"]))
        if key in result:
            raise ValueError(f"{path}:{line_number}: duplicate room/time {key}")
        result[key] = row
    if not result:
        raise ValueError(f"{path}: empty trace")
    return result


def load_cfast(path: Path, compartment: int) -> dict[float, dict[str, float]]:
    """Use original LLCO/ULCO molar percentages, never aggregate room CO."""
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = ("Time", f"LLCO_{compartment}", f"ULCO_{compartment}", f"HGT_{compartment}")
        missing = [name for name in required if name not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"{path}: missing CFAST columns {missing}")
        # CFAST writes three metadata rows after the column header.
        for _ in range(3):
            next(reader, None)
        result: dict[float, dict[str, float]] = {}
        for row in reader:
            if not row["Time"]:
                continue
            time_s = float(row["Time"])
            values = {
                "co_lower_ppm": float(row[f"LLCO_{compartment}"]) * 10000.0,
                "co_upper_ppm": float(row[f"ULCO_{compartment}"]) * 10000.0,
                "hot_layer_m": float(row[f"HGT_{compartment}"]),
            }
            if not all(math.isfinite(value) for value in (time_s, *values.values())):
                raise ValueError(f"{path}: non-finite CFAST observation at {time_s}")
            if time_s in result:
                raise ValueError(f"{path}: duplicate CFAST time {time_s}")
            result[time_s] = values
    if not result:
        raise ValueError(f"{path}: empty CFAST series")
    return result


def _nearest_time(times: list[float], target: int, source: str) -> float:
    nearest = min(times, key=lambda time: abs(time - target))
    if abs(nearest - target) > 1.0:
        raise ValueError(f"{source}: no observation within 1 s of t={target}")
    return nearest


def compare_case(case: str, trace_root: Path, cfast_root: Path = CFAST_ROOT) -> dict:
    if case not in CASE_ROOMS:
        raise ValueError(f"unregistered G3 case: {case}")
    trace_path = trace_root / case / "co_inventory_trace.jsonl"
    cfast_path = cfast_root / f"{case}_compartments.csv"
    trace = load_trace(trace_path)
    points: list[dict] = []
    for room_id, compartment, targets in CASE_ROOMS[case]:
        cfast = load_cfast(cfast_path, compartment)
        trace_times = [time for rid, time in trace if rid == room_id]
        if not trace_times:
            raise ValueError(f"{trace_path}: room {room_id} absent")
        for target in targets:
            sim_time = _nearest_time(trace_times, target, f"{case} room {room_id} trace")
            cfast_time = _nearest_time(list(cfast), target, f"{case} compartment {compartment}")
            sf = trace[room_id, sim_time]
            cf = cfast[cfast_time]
            lower_sf = float(sf["co_lower_mass_ppm"])
            points.append({
                "room_id": room_id,
                "cfast_compartment": compartment,
                "target_time_s": target,
                "sim_time_s": sim_time,
                "cfast_time_s": cfast_time,
                "sim_lower_co_mass_ppm": lower_sf,
                "sim_co_representation": sf["co_representation"],
                "cfast_lower_co_ppm": cf["co_lower_ppm"],
                "lower_co_delta_ppm": lower_sf - cf["co_lower_ppm"],
                "sim_upper_co_ppm": float(sf["co_upper_ppm"]),
                "cfast_upper_co_ppm": cf["co_upper_ppm"],
                "sim_interface_m": float(sf["hot_layer_m"]),
                "cfast_interface_m": cf["hot_layer_m"],
            })
    return {
        "case": case,
        "trace_sha256": _sha256(trace_path),
        "cfast_sha256": _sha256(cfast_path),
        "trace_snapshots": len(trace),
        "points": points,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace-root", type=Path, default=DEFAULT_TRACE_ROOT)
    parser.add_argument("--cfast-root", type=Path, default=CFAST_ROOT)
    parser.add_argument("--case", action="append", choices=tuple(CASE_ROOMS))
    args = parser.parse_args()
    cases = args.case or list(CASE_ROOMS)
    report = {
        "contract": "g3-raw-lower-co-cfast-diagnostic-v1",
        "gating": False,
        "source": "raw CO inventory versus CFAST LLCO/ULCO; not human exposure data",
        "cases": [compare_case(case, args.trace_root, args.cfast_root) for case in cases],
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
