"""Run isolated M4-P1 through the unchanged safe monitor; audit each sample."""

import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario
from scripts.simulation import audit_g3_m4_physical_parcels as audit
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment

MODEL = "sim/core/PhysicalGasOxygenParcelModel.gd"
FIXTURE = "tests/fixtures/g3_o2_m4_physical_parcels.gd"
PREFIX = "G3_O2_M4_PHYSICAL_PARCELS"
AUDITOR = "scripts/simulation/audit_g3_m4_physical_parcels.py"


def current_hashes():
    return {p: harness.sha((ROOT / p).read_bytes()) for p in (MODEL, FIXTURE, AUDITOR)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    prepare_environment(work)
    record = {"schema": "g3_m4_physical_parcels_v1", "state": "in_progress",
              "integration_validated": False, "physical_flow_validation": False,
              "source_sha256_raw": current_hashes()}
    try:
        godot = run_scenario._find_godot()
        if godot is None:
            raise RuntimeError("Godot unavailable")
        result = godot_monitored_launch.run(
            [godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
            timeout_s=180, environment=os.environ.copy(),
        )
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        record["health"] = result.health
        if not result.launched or result.faults or result.preexisting:
            raise RuntimeError(f"monitor refused: {result.faults or result.preexisting}")
        verdict, payload = harness.classify(result.stdout, result.stderr, result.returncode, PREFIX)
        if verdict != "pass":
            raise RuntimeError(f"fixture not accepted: {payload['failures']}")
        record["fixture"] = payload
        record["audit"] = audit.audit_payload(payload)
        if current_hashes() != record["source_sha256_raw"]:
            raise RuntimeError("sources changed during fixture")
        record["state"] = "passed"
    except Exception as exc:
        record.update(state="failed", error=str(exc))
        raise
    finally:
        (work / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
        print(json.dumps({"state": record["state"], "work": str(work),
                          "checks": record.get("fixture", {}).get("checks")}), flush=True)


if __name__ == "__main__":
    main()
