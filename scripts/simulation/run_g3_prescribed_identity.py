"""Compare full linear-mode API traces before/after, including fingerprints."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--budget-v1", action="store_true")
    args = parser.parse_args()
    model = ROOT / "sim/fire/PrescribedFuelReleaseModel.gd"
    assets = [ROOT / "tests/fixtures/g3_prescribed_release_identity.gd",
              ROOT / "tests/fixtures/g3_mass_material_profile_synthetic.json"]
    prefix = "G3_LINEAR_IDENTITY"
    if args.budget_v1:
        model = ROOT / "sim/fire/FuelMassBudgetModel.gd"
        assets = [ROOT / "tests/fixtures/g3_budget_v1_identity.gd"]
        prefix = "G3_BUDGET_V1_IDENTITY"
    original = {path: path.read_bytes() for path in [model, *assets]}
    previous = args.before.read_bytes()
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot not found")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    family = "budget_v1" if args.budget_v1 else "linear"
    evidence = ROOT / "runs" / f"g3_{family}_identity_{stamp}"
    evidence.mkdir(parents=True, exist_ok=False)
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    traces = []
    for name, source in [("before", previous), ("after", original[model])]:
        project = evidence / name
        for path, raw in original.items():
            destination = project / path.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source if path == model else raw)
        (project / "project.godot").write_text('config_version=5\n', encoding="utf-8")
        result = godot_monitored_launch.run(
            [str(godot), "--headless", "--path", str(project), "--script",
             str(project / assets[0].relative_to(ROOT))],
            timeout_s=120, environment=os.environ.copy())
        (project / "stdout.log").write_text(result.stdout, encoding="utf-8")
        (project / "stderr.log").write_text(result.stderr, encoding="utf-8")
        (project / "health.json").write_text(json.dumps(result.health, indent=2), encoding="utf-8")
        if not result.launched or result.faults or result.returncode != 0:
            raise RuntimeError(f"{name}: unhealthy identity run {result.faults}")
        matches = [line for line in result.stdout.splitlines() if line.startswith(prefix + " ")]
        if len(matches) != 1:
            raise RuntimeError("missing/ambiguous full API trace")
        traces.append(matches[0].encode("utf-8"))
    intact = all(path.read_bytes() == raw for path, raw in original.items())
    report = {family + "_trace_byte_identical": traces[0] == traces[1],
              "originals_intact": intact,
              "before_model_sha256": hashlib.sha256(previous).hexdigest(),
              "after_model_sha256": hashlib.sha256(original[model]).hexdigest(),
              "trace_sha256": [hashlib.sha256(trace).hexdigest() for trace in traces]}
    (evidence / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))
    if not intact or traces[0] != traces[1]:
        raise RuntimeError("linear API trace changed or working sources not intact")


if __name__ == "__main__":
    main()
