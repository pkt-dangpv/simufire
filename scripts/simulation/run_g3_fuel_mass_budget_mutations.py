"""D1 mutations on isolated copies, never on the working engine source.

Every control/mutant uses the same GDScript analytical fixture through the
safe monitor. Refuse launches below 6 GiB. Syntax errors and unhealthy runs
are infrastructure failures, never killed mutants. Keep SHA-256 evidence.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch  # noqa: E402
from scripts import run_scenario  # noqa: E402


MODEL = ROOT / "sim/fire/FuelMassBudgetModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_fuel_mass_budget.gd"
MUTATIONS = {
    "M01_missing_solid_debit": (
        '"solid_fuel_kg": solid - transferred,', '"solid_fuel_kg": solid,'),
    "M02_duplicate_release": (
        '"released_fuel_kg": released + transferred - oxidized,',
        '"released_fuel_kg": released + 2.0 * transferred - oxidized,'),
    "M03_oxidize_without_oxygen": (
        'minf(oxidation_requested, minf(released + transferred, oxygen / oxygen_per_kg))',
        'minf(oxidation_requested, released + transferred)'),
    "M04_heat_without_oxidation": (
        'var oxidation_heat: float = oxidized * heat',
        'var oxidation_heat: float = transferred * heat'),
    "M05_products_ignore_oxidant": (
        'var co2: float = oxidized * c * (11.0 / 3.0)',
        'var co2: float = oxidized * c'),
    "M06_release_without_thermal_budget": (
        'transferred = minf(transferred, thermal_budget / gasification_heat)',
        'transferred = transferred'),
    "M07_drop_release_cost": (
        'var release_cost: float = minf(thermal_budget, transferred * gasification_heat)',
        'var release_cost: float = 0.0'),
    "M08_effective_HOC_as_chemical": (
        'm.get("chemical_energy_basis") != "complete_oxidation_net"',
        'm.get("chemical_energy_basis") not in ["complete_oxidation_net", "measured_effective_HOC"]'),
    "M09_admit_energy_only_inventory": (
        'if typeof(key) != TYPE_STRING or key not in allowed:',
        'if typeof(key) != TYPE_STRING or (key not in allowed and key != "fuel_energy_MJ"):'),
    "M10_zero_step_emits": (
        'if dt_s > 0.0:',
        'if dt_s >= 0.0:'),
}
PHASE_MUTATIONS = {
    "P01_liquid_heat_for_vapour": (
        'var phase_oxidation_heat: float = oxidized * vapour_heat',
        'var phase_oxidation_heat: float = oxidized * liquid_heat'),
    "P02_drop_phase_cost": (
        'var phase_cost: float = minf(budget, transferred * latent)',
        'var phase_cost: float = 0.0'),
    "P03_missing_liquid_debit": (
        '"liquid_fuel_kg": liquid - transferred,', '"liquid_fuel_kg": liquid,'),
    "P04_ignore_oxygen": MUTATIONS["M03_oxidize_without_oxygen"],
    "P05_heat_without_oxidation": (
        'var phase_oxidation_heat: float = oxidized * vapour_heat',
        'var phase_oxidation_heat: float = transferred * vapour_heat'),
    "P06_missing_total_check": (
        '_check_balance(total_before, total_after, ENERGY_ABS_TOL_KJ, "phase total energy", errors)',
        'pass # mutant: no total finite/conservation gate'),
    "P07_borrow_deposited_heat": (
        'oxygen_per_kg, "thermal_budgeted", budget, latent)',
        'oxygen_per_kg, "thermal_budgeted", budget + deposited, latent)'),
    "P08_schema_not_checked": (
        'if typeof(m.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or m.get(key) != required[key]:',
        'if key != "schema" and (typeof(m.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or m.get(key) != required[key]):'),
    "P09_liquid_phase_not_checked": (
        'if typeof(m.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or m.get(key) != required[key]:',
        'if key != "liquid_phase" and (typeof(m.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or m.get(key) != required[key]):'),
    "P10_no_Hess_check": (
        '_check_balance(vapour_heat, liquid_heat + latent, ENERGY_ABS_TOL_KJ, "reference phase enthalpy", errors)',
        'pass # mutant: incompatible phase basis admitted'),
    "P11_zero_step_emits": MUTATIONS["M10_zero_step_emits"],
    "P12_energy_inventory_admitted": MUTATIONS["M09_admit_energy_only_inventory"],
}


def changed_source(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise ValueError(f"mutation anchor must occur once: {old!r}")
    return source.replace(old, new, 1)


def classify(stdout: str, stderr: str, returncode: int,
             prefix: str = "G3_FUEL_MASS_BUDGET") -> tuple[str, dict]:
    lines = [line for line in stdout.splitlines()
             if line.startswith(prefix + " {")]
    if not lines or "Parse Error" in stdout + stderr or "SCRIPT ERROR" in stdout + stderr:
        raise RuntimeError("fixture absent, syntax error, or script runtime error")
    payload = json.loads(lines[-1].split(" ", 1)[1])
    if returncode == 0 and not payload["failures"] and prefix + "_PASS" in stdout:
        return "pass", payload
    if returncode == 1 and payload["failures"]:
        return "killed", payload
    raise RuntimeError(f"invalid fixture termination: {returncode}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--phase-reference", action="store_true")
    args = parser.parse_args()
    original = MODEL.read_bytes()
    source = original.decode("utf-8")
    selected = PHASE_MUTATIONS if args.phase_reference else MUTATIONS
    fixture = ROOT / "tests/fixtures/g3_phase_reference_budget.gd" if args.phase_reference else FIXTURE
    prefix = "G3_PHASE_REFERENCE_BUDGET" if args.phase_reference else "G3_FUEL_MASS_BUDGET"
    variants = {name: changed_source(source, *change) for name, change in selected.items()}
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot executable not found")
    environment = os.environ.copy()
    environment[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    # The launcher's own gate reads os.environ, not just the child environment.
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    family = "phase" if args.phase_reference else "mass"
    evidence = ROOT / "runs" / f"g3_d1_{family}_mutations_{stamp}"
    evidence.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        for name, candidate in {"control": source, **variants}.items():
            project = evidence / name
            model_copy = project / "sim/fire/FuelMassBudgetModel.gd"
            fixture_copy = project / fixture.relative_to(ROOT)
            model_copy.parent.mkdir(parents=True)
            fixture_copy.parent.mkdir(parents=True)
            model_copy.write_text(candidate, encoding="utf-8", newline="\n")
            (project / "sim/fire/SensibleEnthalpyModel.gd").write_bytes(
                (ROOT / "sim/fire/SensibleEnthalpyModel.gd").read_bytes())
            fixture_copy.write_bytes(fixture.read_bytes())
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="D1 isolated budget"\n',
                encoding="utf-8",
            )
            launched = godot_monitored_launch.run(
                [str(godot), "--headless", "--path", str(project), "--script", str(fixture_copy)],
                timeout_s=120, environment=environment,
            )
            (project / "health.json").write_text(
                json.dumps(launched.health, indent=2), encoding="utf-8"
            )
            (project / "stdout.log").write_text(launched.stdout, encoding="utf-8")
            (project / "stderr.log").write_text(launched.stderr, encoding="utf-8")
            if not launched.launched or launched.faults:
                raise RuntimeError(f"{name}: infrastructure fault: {launched.faults}")
            verdict, payload = classify(launched.stdout, launched.stderr, launched.returncode, prefix)
            expected = "pass" if name == "control" else "killed"
            results.append({
                "name": name, "verdict": verdict, "expected": expected,
                "fixture": payload, "source_sha256": hashlib.sha256(model_copy.read_bytes()).hexdigest(),
            })
            print(json.dumps({"name": name, "verdict": verdict}), flush=True)
            if verdict != expected:
                raise RuntimeError(f"{name}: survivor or failed control")
    finally:
        intact = hashlib.sha256(MODEL.read_bytes()).hexdigest() == hashlib.sha256(original).hexdigest()
        (evidence / "results.json").write_text(json.dumps({
            "results": results, "working_source_intact": intact,
            "working_source_sha256": hashlib.sha256(original).hexdigest(),
        }, indent=2), encoding="utf-8")
        if not intact:
            raise RuntimeError("working engine source changed during isolated mutations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
