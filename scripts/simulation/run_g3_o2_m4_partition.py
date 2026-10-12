"""Run M4-A1 only, through the existing safe monitor, then audit in Python.

The Python oracle is a declared synthetic reference partition, not physics.
No live engine, fire, product switch, source calibration or CO/FED is judged.
"""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import g3_m4_partition_contract as oracle  # noqa: E402
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness  # noqa: E402
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment  # noqa: E402

FIXTURE = "tests/fixtures/g3_o2_m4_partition.gd"
MODEL = "sim/core/OxygenReferencePartition.gd"
PREFIX = "G3_O2_M4_PARTITION"


def audit_samples(payload):
    if payload.get("iterations") != 10000 or payload.get("maximum_total_gap_kg") != 0:
        raise RuntimeError("deterministic sequence incomplete or total drifts")
    samples = payload.get("samples")
    if not isinstance(samples, list) or len(samples) != 18:
        raise RuntimeError("cross-language samples incomplete")
    for index, sample in enumerate(samples):
        before = oracle.Partition(**sample["input"])
        operation, argument = sample["operation"], sample["argument"]
        if operation == "remap":
            expected = oracle.remap(before, argument)
        elif operation == "mix":
            expected = oracle.mix(before, argument)
        elif operation == "budget":
            expected = oracle.budget(before, *argument, "imposed_budget")
        else:
            raise RuntimeError("unknown sample operation")
        after = oracle.Partition(**sample["after"])
        for field in before.__dataclass_fields__:
            if abs(getattr(after, field) - getattr(expected.after, field)) > oracle.TOL_KG:
                raise RuntimeError(f"sample {index} disagrees with Python: {field}")
        receipt = sample["receipt"]
        if receipt["before"] != sample["input"] or receipt["after"] != sample["after"]:
            raise RuntimeError("sample receipt snapshots disagree")
        observed = oracle.Receipt(before, after, receipt["cause"], receipt["upper_delta_kg"],
                                  receipt["lower_delta_kg"], receipt["room_delta_kg"])
        if oracle.broken_invariants(observed):
            raise RuntimeError(f"sample {index} fails its independent budget")
        if observed.cause != expected.cause:
            raise RuntimeError("sample cause differs from declared operation")
    return {"samples": len(samples), "independent_budget": True, "physical_validation": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    prepare_environment(work)
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    result = godot_monitored_launch.run(
        [godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
        timeout_s=180, environment=os.environ.copy(),
    )
    (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
    (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
    (work / "health.json").write_text(json.dumps(result.health, indent=2), encoding="utf-8")
    if not result.launched or result.faults or result.preexisting:
        raise RuntimeError(f"monitor refuses fixture: {result.faults or result.preexisting}")
    verdict, payload = harness.classify(result.stdout, result.stderr, result.returncode, PREFIX)
    if verdict != "pass":
        raise RuntimeError(f"fixture not accepted: {payload}")
    independent = audit_samples(payload)
    record = {"state": "passed", "fixture": payload, "oracle": independent,
              "health": result.health, "model_sha256_raw": harness.sha((ROOT / MODEL).read_bytes()),
              "fixture_sha256_raw": harness.sha((ROOT / FIXTURE).read_bytes()),
              "oracle_sha256_raw": harness.sha((ROOT / "scripts/simulation/g3_m4_partition_contract.py").read_bytes())}
    (work / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps({"state": "passed", "checks": payload["checks"], "oracle": independent,
                      "work": str(work), "health": result.health}))


if __name__ == "__main__":
    main()
