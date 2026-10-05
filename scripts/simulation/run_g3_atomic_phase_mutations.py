"""Isolated real-GDScript transaction mutations; working sources never edited."""
from __future__ import annotations

import datetime
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source, classify  # noqa: E402

MODEL = ROOT / "sim/fire/PrescribedPhaseBudgetController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_atomic_phase_controller.gd"
PREFIX = "G3_ATOMIC_PHASE_CONTROLLER"
MUTATIONS = {
    "C01_advance_before_validation": (
        'var proposal: Dictionary = preview_step(end_time_s, oxidation_requested_kg)',
        '_owned["generation"] += 1\n\tvar proposal: Dictionary = preview_step(end_time_s, oxidation_requested_kg)'),
    "C02_only_progress_committed": (
        '_owned = proposal["candidate"].duplicate(true)',
        '_owned["progress"] = proposal["candidate"]["progress"].duplicate(true)'),
    "C03_only_phase_committed": (
        '_owned = proposal["candidate"].duplicate(true)',
        '_owned["phase"] = proposal["candidate"]["phase"].duplicate(true)'),
    "C04_ack_requested_not_accepted": (
        'source_end, phase["accepted_release_kg"])', 'source_end, demand["release_kg"])'),
    "C05_ack_oxidized_not_released": (
        'source_end, phase["accepted_release_kg"])', 'source_end, phase["accepted_oxidation_kg"])'),
    "C06_ignore_generation_identity": (
        'and value == _owned["generation"]', 'and true'),
    "C07_foreign_candidate_partial_write": (
        'func commit_step(end_time_s: Variant, oxidation_requested_kg: Variant, expected_generation: Variant) -> Dictionary:\n',
        'func commit_step(end_time_s: Variant, oxidation_requested_kg: Variant, expected_generation: Variant) -> Dictionary:\n\tif typeof(end_time_s) == TYPE_DICTIONARY:\n\t\t_owned["phase"] = end_time_s.duplicate(true)\n'),
    "C08_omit_coupled_history_validation": (
        'var source: Dictionary = Release.propose(context["program"], progress, progress["time_s"])',
        'return true # mutant: typed but decoupled snapshots admitted\n\tvar source: Dictionary = Release.propose(context["program"], progress, progress["time_s"])'),
    "C09_material_seed_not_bound": (
        'return (VERSION + JSON.stringify(context, "", true, true)).sha256_text()',
        'var reduced: Dictionary = context.duplicate(true)\n\treduced.erase("material")\n\treduced.erase("seed")\n\treturn (VERSION + JSON.stringify(reduced, "", true, true)).sha256_text()'),
    "C10_borrow_deposited_heat": (
        'var phase_input: Dictionary = _owned["phase"].duplicate(true)',
        'var phase_input: Dictionary = _owned["phase"].duplicate(true)\n\tphase_input["thermal_budget_kj"] += phase_input["deposited_heat_kj"]'),
    "C11_reemit_rejected_prefix": (
        'var phase_input: Dictionary = _owned["phase"].duplicate(true)',
        'demand["release_kg"] += float(_owned["progress"]["rejected_kg"])\n\tvar phase_input: Dictionary = _owned["phase"].duplicate(true)'),
    "C12_drop_accumulated_product": (
        'candidate["totals"]["co2_kg"] += float(phase["products_kg"]["co2"])',
        'candidate["totals"]["co2_kg"] += 0.0'),
    "C13_restore_old_generation": (
        'candidate["generation"] = int(_owned["generation"]) + 1',
        'candidate["generation"] = int(saved["generation"])'),
    "C14_source_dt_as_physical_dt": (
        '_request(physical_dt, demand["release_kg"], oxidation)',
        '_request(demand["dt_s"], demand["release_kg"], oxidation)'),
    "C15_no_oxidation_after_source_end": (
        '_request(physical_dt, demand["release_kg"], oxidation)',
        '_request(physical_dt, demand["release_kg"], 0.0 if demand["dt_s"] == 0.0 else oxidation)'),
    "C16_source_extrapolation": (
        'var source_end: float = minf(end, _domain_end(_context))', 'var source_end: float = end'),
    "C17_snapshot_alias": ('return _owned.duplicate(true)', 'return _owned'),
    "C18_approve_product": ('"engine_integration": false', '"engine_integration": true'),
}


def main():
    paths = [MODEL, FIXTURE, ROOT / "sim/fire/FuelMassBudgetModel.gd",
             ROOT / "sim/fire/PrescribedFuelReleaseModel.gd", ROOT / "sim/fire/SensibleEnthalpyModel.gd"]
    originals = {p: p.read_bytes() for p in paths}
    source = originals[MODEL].decode("utf-8")
    variants = {name: changed_source(source, *patch) for name, patch in MUTATIONS.items()}
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot missing")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / ("g3_atomic_phase_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        for name, candidate in {"control": source, **variants}.items():
            project = evidence / name
            for path, raw in originals.items():
                target = project / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(candidate.encode("utf-8") if path == MODEL else raw)
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="D1 isolated atomic ledger"\n',
                encoding="utf-8")
            run = godot_monitored_launch.run([godot, "--headless", "--path", project,
                                             "--script", project / FIXTURE.relative_to(ROOT)],
                                            timeout_s=120, environment=os.environ.copy())
            (project / "health.json").write_text(json.dumps(run.health, indent=2), encoding="utf-8")
            (project / "stdout.log").write_text(run.stdout, encoding="utf-8")
            (project / "stderr.log").write_text(run.stderr, encoding="utf-8")
            if not run.launched or run.faults or run.preexisting:
                raise RuntimeError(f"{name}: monitor failure {run.faults or run.preexisting}")
            verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
            results.append({"name": name, "verdict": verdict, "fixture": payload})
            print(json.dumps({"name": name, "verdict": verdict}), flush=True)
            expected = "pass" if name == "control" else "killed"
            if verdict != expected:
                raise RuntimeError(f"{name}: failed control or surviving mutant")
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        (evidence / "results.json").write_text(json.dumps({
            "results": results, "originals_intact": intact,
            "original_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for p, raw in originals.items()},
        }, indent=2), encoding="utf-8")
        if not intact:
            raise RuntimeError("working sources altered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
