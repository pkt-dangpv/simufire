"""Run the isolated M4-P2 GD fixture through the safe monitor and audit it with the oracle."""

import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import audit_g3_m4_p2_gas_energy_eos as audit  # noqa: E402
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness  # noqa: E402
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment  # noqa: E402

MODEL = "sim/core/PhysicalGasEnergyEosModel.gd"
FIXTURE = "tests/fixtures/g3_m4_p2_gas_energy_eos.gd"
PREFIX = "G3_M4_P2_GAS_ENERGY_EOS"
AUDITOR = "scripts/simulation/audit_g3_m4_p2_gas_energy_eos.py"
ORACLE = "scripts/simulation/g3_m4_p2_gas_energy_eos_oracle.py"
PLAN = "docs/validation/G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json"
TIMEOUT_S = 900


def current_hashes():
    return {p: harness.sha((ROOT / p).read_bytes()) for p in (MODEL, FIXTURE, AUDITOR, ORACLE, PLAN)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    prepare_environment(work)
    plan = audit.load_plan()  # refuses a plan that changed after predeclaration
    record = {"schema": "g3_m4_p2_gas_energy_eos_v1", "state": "in_progress",
              "integration_validated": False, "product_properties_chosen": False,
              "engine_timestep_sensitivity_resolved": False,
              "source_sha256_raw": current_hashes()}
    try:
        godot = run_scenario._find_godot()
        if godot is None:
            raise RuntimeError("Godot unavailable")
        result = godot_monitored_launch.run(
            [godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
            timeout_s=TIMEOUT_S, environment=os.environ.copy(),
        )
        (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
        record["health"] = result.health
        if not result.launched or result.faults or result.preexisting:
            raise RuntimeError(f"monitor refused: {result.faults or result.preexisting}")
        verdict, payload = harness.classify(result.stdout, result.stderr, result.returncode, PREFIX)
        if verdict != "pass":
            raise RuntimeError(f"fixture not accepted: {payload['failures']}")
        record["fixture"] = {k: v for k, v in payload.items() if k not in ("samples", "rejections", "finals")}
        (work / "payload.json").write_text(json.dumps(payload), encoding="utf-8")
        record["audit"] = audit.audit_payload(payload, plan)
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
