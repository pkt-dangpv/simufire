"""M3 regressions and unchanged houses, sequential existing safe launchers.

No commit or push, no product activation, no adjustment of scenarios on refusal.
Every stage writes its terminal record externally; failures remain failures.
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
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import run_g3_o2_transport_gate as gate  # noqa: E402
from scripts.simulation import run_g3_o2_transport_closure as closure  # noqa: E402
from scripts.simulation import run_g3_o2_venting_house as house  # noqa: E402
from scripts.simulation import run_g3_balance_identity as identity  # noqa: E402
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness  # noqa: E402

BASE = "28f74c4da5f40077d5e4685575bc29bc5e23b68c"
FILES = ("sim/fire/CombustionSystem.gd", "sim/core/RoomOxygenInventory.gd",
         "sim/core/OxygenExchangeSystem.gd", "sim/core/SimulationEngine.gd")


def sources():
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in FILES}


def verified_case_health(folder):
    """Baseline/house subprocesses save their own outer monitor, not a shared log."""
    health = json.loads((folder / "monitor.health.json").read_text(encoding="utf-8"))
    faults = godot_monitored_launch.infrastructure_faults(health)
    if faults or health.get("cleanup_terminated_pids") != [] or health.get("wrapper_exit_code") != 0:
        raise RuntimeError(f"case not healthy: {folder}: {faults}")
    children = health.get("observed_godot_processes", [])
    if not children or any(item.get("exit_code") != 0 for item in children):
        raise RuntimeError(f"missing or unsuccessful Godot child: {folder}")
    output = "".join((folder / name).read_text(encoding="utf-8")
                     for name in ("monitor.stdout.log", "monitor.stderr.log"))
    if "SCRIPT ERROR" in output or "Parse Error" in output:
        raise RuntimeError(f"case contains script errors: {folder}")
    return health


def heat_budget(path):
    """Independent step-by-step heat/debit check; never repairs a trace.

    These declared sofa cases use 0.076 kg/MJ. The value is an oracle here,
    not read back from the owner whose accounting is being checked.
    """
    previous = {}
    largest_gap = 0.0
    limited = reservations = steps = 0
    heat_total = consumed_total = 0.0
    with path.open(encoding="utf-8") as handle:
        for raw in handle:
            row = json.loads(raw)
            if row.get("failure") or row.get("state") != "armed":
                raise RuntimeError("M3 heat trace contains a rejected step")
            steps += 1
            accepted, debited = {}, {}
            for op in row["operations"]:
                room = str(op.get("room"))
                if op["kind"] == "combustion_reservation":
                    if room in accepted:
                        raise RuntimeError("two combustion reservations for one room/tick")
                    fraction = float(op["fraction"])
                    backed = float(op["accepted_heat_MJ"]) * 0.076
                    reserve = float(op["reserved_kg"])
                    proposal = float(op["requested_kg"])
                    if (not all(math.isfinite(v) for v in (fraction, backed, reserve, proposal))
                            or not 0.0 <= fraction <= 1.0 or min(backed, reserve, proposal) < 0.0
                            or abs(backed - reserve) > 1e-9
                            or abs(proposal * fraction - reserve) > 1e-9):
                        raise RuntimeError("invalid or incoherent combustion reservation")
                    selection = row["selections"][room]
                    if (op["selection_id"] != selection["id"]
                            or reserve > float(selection["available_kg"]) + 1e-9):
                        raise RuntimeError("reservation spends another selection or unavailable O2")
                    accepted[room] = reserve
                    reservations += 1
                    limited += int(fraction < 1.0)
                elif op["kind"] == "consume":
                    if room in debited or op["cause"] != "accepted_combustion":
                        raise RuntimeError("duplicate debit or historical sink bypass")
                    debited[room] = float(op["applied_kg"])
                    if float(op["clipped_kg"]) != 0.0:
                        raise RuntimeError("a late cap clipped accepted combustion")
            if accepted.keys() != debited.keys():
                raise RuntimeError("combustion reservation not settled")
            for room, state in row["rooms"].items():
                heat = float(state["heat_kj"])
                delta_MJ = (heat - previous.get(room, 0.0)) / 1000.0
                previous[room] = heat
                used = debited.get(room, 0.0)
                gap = max(abs(delta_MJ * 0.076 - used), abs(accepted.get(room, 0.0) - used))
                if (not all(math.isfinite(v) for v in (delta_MJ, used, gap))
                        or min(delta_MJ, used) < 0.0 or gap > 1e-9):
                    raise RuntimeError(f"heat not exactly backed at step {steps}, room {room}: {gap}")
                largest_gap = max(largest_gap, gap)
                heat_total += delta_MJ
                consumed_total += used
    if not steps:
        raise RuntimeError("empty heat trace")
    return {"steps": steps, "reservations": reservations, "limited_steps": limited,
            "heat_MJ": heat_total, "consumed_kg": consumed_total,
            "largest_step_gap_kg": largest_gap, "no_late_clipping": True}


def unlimited(work):
    """One unchanged fixture on M2-T and current M3; restores all four files."""
    originals = {path: (ROOT / path).read_bytes() for path in FILES}
    before = sources()
    reports = {}
    hashes = {}
    for variant in ("base", "current"):
        folder = work / variant
        folder.mkdir()
        os.environ["G3_O2_M3_DIAGNOSIS_OUT"] = str(folder)
        try:
            if variant == "base":
                for path in FILES:
                    (ROOT / path).write_bytes(gate.git("show", f"{BASE}:{path}"))
            run = godot_monitored_launch.run(
                [run_scenario._find_godot(), "--headless", "--path", ROOT,
                 "--script", ROOT / "tests/fixtures/g3_o2_m3_unlimited.gd"],
                timeout_s=600, environment=os.environ.copy())
        finally:
            for path, raw in originals.items():
                (ROOT / path).write_bytes(raw)
            if sources() != before:
                raise RuntimeError("baseline source restoration failed")
        (folder / "stdout.log").write_text(run.stdout, encoding="utf-8")
        (folder / "stderr.log").write_text(run.stderr, encoding="utf-8")
        (folder / "health.json").write_text(json.dumps(run.health, indent=2), encoding="utf-8")
        if not run.launched or run.faults or run.preexisting:
            raise RuntimeError(f"unlimited {variant}: {run.faults or run.preexisting}")
        verdict, payload = harness.classify(run.stdout, run.stderr, run.returncode, "G3_O2_M3_UNLIMITED")
        reports[variant] = {"verdict": verdict, "payload": payload, "health": run.health}
        if verdict != "pass":
            raise RuntimeError(f"unlimited {variant} control not accepted: {payload}")
        hashes[variant] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in folder.glob("unlimited_*.jsonl")}
    if len(hashes["base"]) != 4 or hashes["base"] != hashes["current"]:
        raise RuntimeError(f"unlimited controls differ: {hashes}")
    return {"base": BASE, "restored_byte_for_byte": sources() == before,
            "runs": reports, "row_sha256": hashes, "identical_controls": 4}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("off", "houses", "unlimited"), required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--reference", type=Path, help="complete M2-T OFF identity run")
    parser.add_argument("--existing-off", type=Path,
                        help="verify a complete OFF run again without launching Godot")
    parser.add_argument("--resume-record", type=Path,
                        help="original terminal record binding an existing OFF run to engine bytes")
    args = parser.parse_args()
    work = args.work.resolve()
    gate.prepare_environment(work)
    before = sources()
    record = {"schema": "g3_m3_checks_v1", "stage": args.stage, "state": "in_progress",
              "sources_sha256_raw": before, "product_activation": False}
    try:
        if args.stage == "off":
            if args.reference is None:
                raise ValueError("OFF needs --reference")
            runs = set((ROOT / "runs").glob("g3_balance_identity_off_ledgeroff_*"))
            existing = args.existing_off.resolve() if args.existing_off else None
            if existing is not None:
                if args.resume_record is None:
                    raise ValueError("existing OFF verification needs its original --resume-record")
                prior = json.loads(args.resume_record.read_text(encoding="utf-8"))
                if (prior.get("stage") != "off" or prior.get("sources_sha256_raw") != before
                        or Path(prior["identity"]["run"]).resolve() != existing):
                    raise RuntimeError("existing OFF record does not bind current engine/run")
                record["original_wrapper_state"] = prior["state"]
                record["original_wrapper_error"] = prior.get("error")
            if identity.run("off", False, args.reference.resolve(), None, existing) != 0:
                raise RuntimeError("OFF identity changed")
            if existing is None:
                created = set((ROOT / "runs").glob("g3_balance_identity_off_ledgeroff_*")) - runs
                if len(created) != 1:
                    raise RuntimeError("OFF output ambiguous")
                existing = created.pop()
            record["identity"] = json.loads((existing / "identity_report.json").read_text(encoding="utf-8"))
            if record["identity"]["total_cases"] != 9:
                raise RuntimeError("not all nine OFF controls ran")
            record["launch_health"] = {name: verified_case_health(existing / name)
                                      for name in record["identity"]["cases"]}
            record["verification_only"] = args.existing_off is not None
        elif args.stage == "houses":
            record["houses"] = {}
            for name in house.CASES:
                folder = house.launch(name, "on")
                evaluated = house.evaluate(folder, None, sink_policy="accepted")
                record["houses"][name] = evaluated
                closure.emit(work / "result.json", record)
                if not evaluated["whole"] or evaluated["budget"]["steps"] != 10800:
                    raise RuntimeError(f"{name}: refused/incomplete; do not simplify")
                if not evaluated["budget"]["closes_in_every_step"]:
                    raise RuntimeError(f"{name}: O2 balance does not close")
                record["houses"][name]["trace"] = gate.analyze_trace(folder)
                record["houses"][name]["heat_budget"] = heat_budget(folder / "o2_inventory_trace.jsonl")
                record["houses"][name]["health"] = verified_case_health(folder)
                if (evaluated["budget"]["largest_number_of_entries"] != 0
                        or evaluated["budget"]["delayed_exchanges"] != 0
                        or any(room["rich_steps"] for room in record["houses"][name]["trace"]["rooms"].values())
                        or not evaluated["contracts"]["c1"] or not evaluated["contracts"]["c2"]
                        or evaluated["venting"]["worst_operation_kg"] > 1e-12
                        or evaluated["venting"]["more_than_one_event_of_a_room_in_a_step"] != 0):
                    raise RuntimeError(f"{name}: M2-T/venting/C1/C2 regression")
                print(f"{name}: whole, O2 conservative", flush=True)
        else:
            record["unlimited"] = unlimited(work)
            record["launch_health"] = gate.verified_health(work)
        if sources() != before:
            raise RuntimeError("sources changed during verification")
        record["state"] = "passed"
    except Exception as exc:
        record["state"] = "failed"
        record["error"] = str(exc)
        raise
    finally:
        closure.emit(work / "result.json", record)
        print(f"M3 {args.stage}: {record['state']}; {work}", flush=True)


if __name__ == "__main__":
    main()
