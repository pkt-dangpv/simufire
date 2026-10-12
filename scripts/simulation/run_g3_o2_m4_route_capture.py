"""M4-B2 fixture-only passive observation; no live partition or physical calibration.

Sequential paired real engine worlds, existing safe monitor and external logs.
Only tick_summary owns aggregate budgets; container/leaf rows are NOT summed.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.simulation.audit_g3_m4_layer_writers import inventory
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment
from scripts.simulation.run_g3_o2_m3_reservation_mutations import classify

FIXTURE = "tests/fixtures/g3_o2_m4_route_capture.gd"
PREFIX = "G3_M4_ROUTE_CAPTURE"
CASES = ("sealed", "one_door", "two_doors", "closed_window")
KAPPA = .031998 / .0289647


def _number(value):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise RuntimeError("nonfinite or untyped quantity in capture")
    return value


def _amount(value):
    number = _number(value)
    if number < 0:
        raise RuntimeError("negative accepted amount in capture")
    return number


def analyze_rows(rows, expected_ticks=240):
    routes, ids, summaries, openings = {}, set(), [], set()
    max_conversion_gap = max_tick_gap = 0.0
    plume_gas = interior_gas = dilution_gas = consumed = 0.0
    interface_changes = 0
    for row in rows:
        if row["route"] == "tick_summary":
            summaries.append(row)
            before = sum(_number(r["o2_inventory_kg"]) for r in row["before"])
            after = sum(_number(r["o2_inventory_kg"]) for r in row["after"])
            exterior = used = 0.0
            for op in row["owner_operations"]:
                if op["kind"] == "outside":
                    exterior += _number(op["in_kg"]) - _number(op["out_kg"])
                elif op["kind"] == "consume":
                    used += _number(op["applied_kg"])
            consumed += used
            max_tick_gap = max(max_tick_gap, abs(after - before - exterior + used))
            continue
        key = row["event_id"]
        if key in ids:
            raise RuntimeError("duplicate observation event identity")
        ids.add(key)
        routes[row["route"]] = routes.get(row["route"], 0) + 1
        if row["route"] in ("interior_background", "interior_active"):
            index = row["opening_index"]
            if type(index) is not int or index < 0:
                raise RuntimeError("interior observation has no real opening index")
            openings.add(index)
            q = _amount(row["data"]["accepted_reference_gas_kg"])
            interior_gas += q
            previous = {r["id"]: r for r in row["before"]}
            ops = [op for op in row["owner_operations"] if op["kind"] == "interior"]
            if len(ops) != 1 or ops[0]["law"] != "symmetric_reference_gas_immediate":
                raise RuntimeError("interior callback lacks its single canonical operation")
            op = ops[0]
            if abs(_number(op["gas_kg"]) - q) > 1e-9:
                raise RuntimeError("callback/owner accepted gas disagree")
            for room, amount in ((op["donor"], op["to_receiver_kg"]), (op["receiver"], op["to_donor_kg"])):
                expected = _number(previous[room]["room_reference_fraction"]) * q * KAPPA
                max_conversion_gap = max(max_conversion_gap, abs(_amount(amount) - expected))
        elif row["route"] == "zone_apply":
            transfer = row["data"]["transfer"]
            moved = _amount(transfer["mass_kg"])
            before, after = row["before"][0], row["after"][0]
            if (abs(after["upper_gas_kg_not_reference_base"]
                    - before["upper_gas_kg_not_reference_base"] - moved) > 1e-9
                    or abs(after["lower_gas_kg_not_reference_base"]
                           - before["lower_gas_kg_not_reference_base"] + moved) > 1e-9
                    or after["o2_inventory_kg"] != before["o2_inventory_kg"]):
                raise RuntimeError("physical zone packet changes another quantity or has no paired donor")
            if row["mechanism"] == "thermal_plume":
                plume_gas += moved
        elif row["route"] == "pressure_venting":
            previous = {r["id"]: r for r in row["before"]}
            for op in row["owner_operations"]:
                if op["kind"] != "outside" or op["cause"] != "pressure_venting":
                    continue
                q = _amount(op["gas_kg"])
                dilution_gas += q
                room = previous[op["room"]]
                base = _amount(room["volume_m3"]) * 1.2 * KAPPA
                incoming = _amount(row["data"]["outside_fraction"]) * q * KAPPA
                mixture = (room["o2_inventory_kg"] + incoming) / (base + q * KAPPA)
                outgoing = mixture * q * KAPPA
                max_conversion_gap = max(max_conversion_gap,
                                         abs(_amount(op["in_kg"]) - incoming),
                                         abs(_amount(op["out_kg"]) - outgoing))
        elif row["route"] == "thermal_sync":
            interface_changes += sum(a["thermal_interface_m"] != b["thermal_interface_m"]
                                     for a, b in zip(row["after"], row["before"], strict=True))
    if [r["tick"] for r in summaries] != list(range(expected_ticks)):
        raise RuntimeError("capture missing or duplicating tick summaries")
    if max(max_conversion_gap, max_tick_gap) > 1e-9:
        raise RuntimeError("captured reference law/budget mismatch")
    return {"events": len(ids), "ticks": len(summaries), "routes": routes,
            "opening_indices": sorted(openings), "physical_plume_gas_kg": plume_gas,
            "interior_reference_gas_kg": interior_gas, "dilution_reference_gas_kg": dilution_gas,
            "consumed_o2_kg": consumed, "interface_change_calls": interface_changes,
            "max_reference_conversion_gap_kg": max_conversion_gap, "max_tick_o2_gap_kg": max_tick_gap,
            "precap_interior_request_observed": False, "zonal_o2_donor_observed": False,
            "live_adapter_eligible": False}


def analyze_folder(work):
    result = {}
    for name in CASES:
        path = work / (name + ".jsonl")
        with path.open(encoding="utf-8") as handle:
            result[name] = analyze_rows((json.loads(line) for line in handle),
                                       expected_ticks=1200 if name == "closed_window" else 240)
        result[name]["rows_sha256_raw"] = hashlib.sha256(path.read_bytes()).hexdigest()
    if result["sealed"]["interior_reference_gas_kg"] != 0 or result["sealed"]["dilution_reference_gas_kg"] != 0:
        raise RuntimeError("negative control invented interior or vent flow")
    if result["one_door"]["opening_indices"] != [0] or result["two_doors"]["opening_indices"] != [0, 1]:
        raise RuntimeError("real doorway identity controls incomplete")
    if result["closed_window"]["dilution_reference_gas_kg"] <= 0:
        raise RuntimeError("window case did not exercise M2-V; do not declare its gate complete")
    return result


def hashes():
    paths = (FIXTURE, "tests/fixtures/g3_o2_m3_diagnosis.gd", "scripts/simulation/run_g3_o2_m4_route_capture.py")
    return {p: hashlib.sha256((ROOT / p).read_bytes().replace(b"\r\n", b"\n")).hexdigest() for p in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    prepare_environment(work)
    environment = os.environ.copy()
    environment["G3_M4_ROUTE_OUT"] = str(work)
    before, gd_before = hashes(), inventory()["gd_inventory_lf_sha256"]
    record = {"state": "in_progress", "sources_lf_sha256": before,
              "engine_inventory_lf_sha256": gd_before, "physical_validation": False,
              "live_adapter_implemented": False, "product_activation": False}
    try:
        result = godot_monitored_launch.run(
            [run_scenario._find_godot(), "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
            timeout_s=240, environment=environment)
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        record["health"] = result.health
        if not result.launched or result.faults or result.preexisting:
            raise RuntimeError(f"monitor refused or unhealthy: {result.faults or result.preexisting}")
        verdict, payload = classify(result.stdout, result.stderr, result.returncode, PREFIX)
        record["fixture"] = payload
        if verdict != "pass":
            raise RuntimeError(f"fixture not accepted: {payload}")
        record["cases"] = analyze_folder(work)
        if hashes() != before or inventory()["gd_inventory_lf_sha256"] != gd_before:
            raise RuntimeError("observation changed its bound sources")
        record["state"] = "passed"
    except Exception as error:
        record["state"] = "failed"
        record["error"] = f"{type(error).__name__}: {error}"
    (work / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps(record, ensure_ascii=False))
    return 0 if record["state"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
