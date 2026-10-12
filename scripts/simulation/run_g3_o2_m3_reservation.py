"""Run the isolated M3 reservation fixture through the existing safe monitor."""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_o2_transport_gate import prepare_environment  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--integration", action="store_true", help="judge the live fire/sink/engine coupling")
    args = parser.parse_args()
    work = args.work.resolve()
    prepare_environment(work)
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    fixture = ROOT / ("tests/fixtures/g3_o2_m3_integration.gd" if args.integration
                      else "tests/fixtures/g3_o2_m3_reservation.gd")
    result = godot_monitored_launch.run(
        [godot, "--headless", "--path", ROOT, "--script", fixture],
        timeout_s=180, environment=os.environ.copy(),
    )
    (work / "stdout.log").write_text(result.stdout, encoding="utf-8")
    (work / "stderr.log").write_text(result.stderr, encoding="utf-8")
    (work / "health.json").write_text(json.dumps(result.health, indent=2), encoding="utf-8")
    if not result.launched or result.returncode != 0 or result.faults or result.preexisting:
        raise RuntimeError(f"Fixture not accepted: {result.returncode}; {result.faults}; {result.stderr[-3000:]}")
    if "SCRIPT ERROR" in result.stdout + result.stderr or "Parse Error" in result.stdout + result.stderr:
        raise RuntimeError("Script/parse error, never a valid test failure")
    prefix = "G3_O2_M3_INTEGRATION " if args.integration else "G3_O2_M3_RESERVATION "
    lines = [line for line in result.stdout.splitlines() if line.startswith(prefix)]
    if len(lines) != 1:
        raise RuntimeError("Missing unique terminal payload")
    payload = json.loads(lines[0][len(prefix):])
    if payload["failure_count"] or payload["checks"] <= 0:
        raise RuntimeError(f"Fixture failed: {payload}")
    (work / "result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps({"fixture": payload, "work": str(work), "health": result.health}))


if __name__ == "__main__":
    main()
