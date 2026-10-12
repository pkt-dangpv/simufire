"""Falsify only the isolated M3 owner, sequentially through the safe monitor.

No integration verdict: every kill must be a named assertion, not a script,
native or infrastructure error. Sources are restored before any next launch.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import run_g3_o2_room_inventory_mutations as machinery  # noqa: E402
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment  # noqa: E402

OWNER = "sim/core/RoomOxygenInventory.gd"
FIXTURE = "tests/fixtures/g3_o2_m3_reservation.gd"
PREFIX = "G3_O2_M3_RESERVATION"


def mutant(old, new, defect, expected):
    return OWNER, old, new, defect, expected


MUTATIONS = {
    "R01_old_five_percent_cap": mutant(
        '\tvar granted_kg: float = minf(requested_kg, float(current["available_kg"]))\n',
        '\tvar granted_kg: float = minf(requested_kg, 0.05 * float(current["available_kg"]))\n',
        "cap acceptance to five percent", "can reserve all available"),
    "R02_caller_forges_availability": mutant(
        '\tvar granted_kg: float = minf(requested_kg, float(current["available_kg"]))\n',
        '\tvar granted_kg: float = minf(requested_kg, float(selection["available_kg"]))\n',
        "trust handed-out fields instead of the canonical selection", "caller cannot forge availability"),
    "R03_positive_arrival_spent": mutant(
        '\tvar granted_kg: float = minf(requested_kg, float(current["available_kg"]))\n',
        '\tvar granted_kg: float = minf(requested_kg, float(current["available_kg"]) + maxf(0.0, in_transit_kg(room.id)))\n',
        "reserve positive oxygen that has not arrived", "positive pending arrival is not available"),
    "R04_obligation_ignored": mutant(
        '\tvar granted_kg: float = minf(requested_kg, float(current["available_kg"]))\n',
        '\tvar granted_kg: float = minf(requested_kg, float(current["inventory_kg"]))\n',
        "ignore outstanding negative diagnostic obligations", "all negative obligations deducted"),
    "R05_duplicate_reservation": mutant(
        '\tif bool(current["reserved"]):\n', '\tif false:\n',
        "allow two reservations on the same selection", "one reservation only"),
    "R06_changed_heat_accepted": mutant(
        '\t\t\t> COMBUSTION_O2_TOLERANCE_KG:\n', '\t\t\t> INF:\n',
        "accept changed heat after reservation", "post-acceptance heat change"),
    "R07_settlement_capped": mutant(
        '\treturn _apply_consumption(room, current, reserved_kg, reserved_kg, "accepted_combustion")\n',
        '\treturn _apply_consumption(room, current, reserved_kg, minf(reserved_kg, room.o2_inventory_kg * 0.05), "accepted_combustion")\n',
        "restore a late debit cap", "inventory exhausted without negative clamp"),
    "R08_mass_commit_omitted": mutant(
        '\tcurrent["debited_kg"] = applied\n\t_commit(room, after_kg)\n',
        '\tcurrent["debited_kg"] = applied\n',
        "report consumption without moving inventory", "exact debit"),
    "R09_unsettled_reservation_discarded": mutant(
        '\t\tif bool(selection.get("reserved", false)) and not bool(selection["debited"]):\n',
        '\t\tif false:\n', "ignore an unsettled reservation", "unsettled reservation cannot close"),
    "R10_outgoing_reservation_unprotected": mutant(
        'if after_kg < float(selection["reserved_kg"]) + owed_kg else ""',
        'if false else ""', "allow an outgoing operation to spend reserved oxygen", "protected outside"),
    "R11_old_sink_bypass": mutant(
        '\tif _combustion_acceptance_enabled:\n\t\treturn _reject_operation("unreserved_fire_debit", {"cause": cause})\n',
        '', "old sink can bypass acceptance", "old debit cannot bypass acceptance"),
    "R12_changed_inventory_accepted": mutant(
        '\tif room.o2_inventory_kg != float(current["inventory_kg"]):\n',
        '\tif false:\n', "accept a stale inventory snapshot", "changed inventory refuses reservation"),
    "R13_changed_coefficient_accepted": mutant(
        'float(coefficient) != float(current["coefficient_kg_per_MJ"])', 'false',
        "ignore changed oxygen coefficient", "coefficient cannot change after acceptance"),
    "R14_other_generation_accepted": mutant(
        '\tif _whole(selection.get("generation")) != _generation:\n', '\tif false:\n',
        "accept the selection from another run", "reject wrong selection generation"),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def classify(stdout, stderr, returncode, prefix=PREFIX):
    if "SCRIPT ERROR" in stdout + stderr or "Parse Error" in stdout + stderr:
        raise RuntimeError("script/parse error is never a valid kill")
    lines = [line[len(prefix) + 1:] for line in stdout.splitlines()
             if line.startswith(prefix + " ")]
    if len(lines) != 1:
        raise RuntimeError("fixture missing unique terminal payload")
    payload = json.loads(lines[0])
    if type(payload.get("checks")) is not int or payload["checks"] <= 0:
        raise RuntimeError("fixture did not perform positive checks")
    failures = payload.get("failures")
    if not isinstance(failures, list) or any(not isinstance(item, str) for item in failures):
        raise RuntimeError("invalid assertion failure list")
    if type(payload.get("failure_count")) is not int or payload["failure_count"] != len(failures):
        raise RuntimeError("failure count contradicts assertions")
    if returncode == 0 and not failures:
        return "pass", payload
    if returncode == 1 and failures:
        return "killed", payload
    raise RuntimeError(f"invalid fixture termination: {returncode}")


def execute(work, originals, variants, declared, *, fixture=FIXTURE, prefix=PREFIX,
            schema="g3_m3_isolated_reservation_mutations_v1", integration=False):
    prepare_environment(work)
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    before = {path: sha(raw) for path, raw in originals.items()}
    results = []
    error = None
    try:
        for name, (relative, text) in {"control": (None, ""), **variants}.items():
            folder = work / name
            folder.mkdir()
            # Refuse before mutation. The monitor repeats this gate at launch.
            fault = godot_monitored_launch.memory_gate_fault()
            foreign = godot_monitored_launch.preexisting_godot_state()
            if fault or foreign:
                raise RuntimeError(f"{name}: preflight refuses execution: {fault or foreign}")
            try:
                if relative:
                    (ROOT / relative).write_bytes(text.encode("utf-8"))
                run = godot_monitored_launch.run(
                    [godot, "--headless", "--path", ROOT, "--script", ROOT / fixture],
                    timeout_s=180, environment=os.environ.copy(),
                )
            finally:
                if relative:
                    (ROOT / relative).write_bytes(originals[relative])
                    if sha((ROOT / relative).read_bytes()) != before[relative]:
                        raise RuntimeError(f"{relative}: SHA-256 restoration failed")
            (folder / "health.json").write_text(json.dumps(run.health, indent=2), encoding="utf-8")
            (folder / "stdout.log").write_text(run.stdout, encoding="utf-8")
            (folder / "stderr.log").write_text(run.stderr, encoding="utf-8")
            if not run.launched or run.faults or run.preexisting:
                raise RuntimeError(f"{name}: invalid infrastructure: {run.faults or run.preexisting}")
            verdict, payload = classify(run.stdout, run.stderr, run.returncode, prefix)
            expected = declared.get(name, {}).get("expected_in")
            failures = payload.get("failures", [])
            where = any(item.startswith(expected) for item in failures) if expected else None
            results.append({"name": name, "verdict": verdict, "checks": payload["checks"],
                            "failed_checks": payload["failure_count"], "expected_in": expected,
                            "seen_where_expected": where, "failures": failures,
                            "health": run.health, "mutant_sha256": sha(text.encode()) if relative else None})
            print(json.dumps({"name": name, "verdict": verdict, "seen_where_expected": where}), flush=True)
            if name == "control" and verdict != "pass":
                raise RuntimeError("control not green; no mutant verdict is meaningful")
            if relative and (verdict != "killed" or not where):
                raise RuntimeError(f"{name}: survived or failed outside its predeclared assertion")
    except Exception as exc:
        error = str(exc)
        raise
    finally:
        for path, raw in originals.items():
            if sha((ROOT / path).read_bytes()) != before[path]:
                (ROOT / path).write_bytes(raw)
        after = {path: sha((ROOT / path).read_bytes()) for path in originals}
        mutants = [item for item in results if item["name"] != "control"]
        summary = {"schema": schema, "integration_validated": integration and error is None,
                   "fixture": fixture, "prefix": prefix,
                   "plan": declared, "results": results, "declared": len(variants),
                   "executed": len(mutants), "killed_where_expected": sum(
                       item["verdict"] == "killed" and item["seen_where_expected"] for item in mutants),
                   "error": error, "sha256_before": before, "sha256_after": after,
                   "originals_intact": before == after}
        (work / "results.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        if before != after:
            raise RuntimeError("original sources not restored")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    originals, variants = machinery.prepared(MUTATIONS, (OWNER,))
    declared = machinery.plan(MUTATIONS, tuple(MUTATIONS))
    if args.plan_only:
        print(json.dumps(declared, indent=2))
        return
    execute(args.work.resolve(), originals, variants, declared)


if __name__ == "__main__":
    main()
