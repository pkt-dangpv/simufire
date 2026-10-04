"""Isolated sensible-ledger mutants, with strict behavioral-kill classification."""
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
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source, classify  # noqa: E402

MODEL = ROOT / 'sim/fire/FuelMassBudgetModel.gd'
FIXTURE = ROOT / 'tests/fixtures/g3_sensible_phase_budget.gd'
PREFIX = 'G3_SENSIBLE_PHASE_BUDGET'
MUTATIONS = {
    'L01_free_heating': ('var available_budget: float = budget - heating',
                       'var available_budget: float = budget'),
    'L02_reference_cost_only': ('cost_per_kg = latent + emitted_specific - sl_specific',
                              'cost_per_kg = latent'),
    'L03_wrong_liquid_sign': ('cost_per_kg = latent + emitted_specific - sl_specific',
                            'cost_per_kg = latent + emitted_specific + sl_specific'),
    'L04_drop_emitted_sensible': ('var mixed_sensible: float = heated_sv + transferred * emitted_specific',
                                 'var mixed_sensible: float = heated_sv'),
    'L05_average_specific_not_enthalpy': (
        'var mixed_specific: float = mixed_sensible / mixed_mass if mixed_mass > 0.0 else 0.0',
        'var mixed_specific: float = (heated_sv / vapour + emitted_specific) * 0.5 if vapour > 0.0 else emitted_specific'),
    'L06_remove_all_vapour_sensible': ('var oxidized_sensible: float = oxidized * mixed_specific',
                                     'var oxidized_sensible: float = mixed_sensible'),
    'L07_drop_sensible_delivery': ('var deposited_increment: float = chemical_heat + oxidized_sensible',
                                 'var deposited_increment: float = chemical_heat'),
    'L08_borrow_Q_for_release': (
        '"thermal_budgeted", available_budget, cost_per_kg)',
        '"thermal_budgeted", available_budget + maxf(0.0, float(n["deposited_heat_kj"])), cost_per_kg)'),
    'L09_bypass_O2_cap': (
        'liquid, vapour, oxygen, oxygen_per_kg, "thermal_budgeted", available_budget, cost_per_kg)',
        'liquid, vapour, oxygen + 1e6, oxygen_per_kg, "thermal_budgeted", available_budget, cost_per_kg)'),
    'L10_drop_liquid_heat': ('var heated_sl: float = sl + heat_l', 'var heated_sl: float = sl'),
    'L11_drop_vapour_heat': ('var heated_sv: float = sv + heat_v', 'var heated_sv: float = sv'),
    'L12_absent_phase_loses_S': ('if sensible != 0.0:', 'if false:'),
    'L13_ignore_support': (
        'or sensible < lower or sensible > upper:', 'or false:'),
    'L14_allow_bool_numbers': (
        'if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:',
        'if typeof(value) not in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:'),
    'L15_ignore_state_binding': (
        'if errors.is_empty() and s["component_id"] != m["component_id"]:', 'if false:'),
    'L16_ignore_profile_binding': (
        '_sensible_literal(profiles[key], "component_id", m["component_id"], errors)',
        'pass # mutant: profile binding omitted'),
    'L17_ignore_state_schema': (
        '_sensible_literal(s, "schema", "g3_phase_sensible_state_v1", errors)',
        'pass # mutant: version validation omitted'),
    'L18_ignore_material_schema': (
        '_sensible_literal(m, "schema", "g3_phase_sensible_material_v1", errors)',
        'pass # mutant: version validation omitted'),
    'L19_erase_tiny_phase': ('if mass == 0.0:', 'if mass < 1e-12:'),
    'L20_zero_step_heats': (
        'var heat_l: float = n["heat_liquid_kj"] if n["dt_s"] > 0.0 else 0.0',
        'var heat_l: float = n["heat_liquid_kj"]'),
    'L21_clamp_signed_delivery': (
        'var deposited_increment: float = chemical_heat + oxidized_sensible',
        'var deposited_increment: float = maxf(0.0, chemical_heat + oxidized_sensible)'),
    'L22_approve_product': (
        '"physical_approval": false, "integration_enabled": false, "product_activation": false,',
        '"physical_approval": false, "integration_enabled": false, "product_activation": true,'),
    'L23_admit_reported_deficit_overflow': (
        'if not _finite(release_deficit):', 'if false:'),
}


def prepared_variants(source: str) -> dict[str, str]:
    return {name: changed_source(source, *patch) for name, patch in MUTATIONS.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan-only', action='store_true')
    args = parser.parse_args()
    paths = [MODEL, FIXTURE, ROOT / 'sim/fire/SensibleEnthalpyModel.gd']
    originals = {path: path.read_bytes() for path in paths}
    source = originals[MODEL].decode('utf-8')
    variants = prepared_variants(source)
    if args.plan_only:
        print(json.dumps({'mutations_prepared': list(variants), 'executed': False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError('Godot unavailable')
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = '6'
    evidence = ROOT / 'runs' / ('g3_sensible_phase_mutations_' +
                               datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    evidence.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        for name, candidate in {'control': source, **variants}.items():
            project = evidence / name
            for path, raw in originals.items():
                target = project / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(candidate.encode('utf-8') if path == MODEL else raw)
            (project / 'project.godot').write_text(
                'config_version=5\n[application]\nconfig/name="Isolated sensible ledger"\n', encoding='utf-8')
            run = godot_monitored_launch.run(
                [godot, '--headless', '--path', project, '--script', project / FIXTURE.relative_to(ROOT)],
                timeout_s=120, environment=os.environ.copy())
            for filename, content in [('health.json', json.dumps(run.health, indent=2)),
                                      ('stdout.log', run.stdout), ('stderr.log', run.stderr)]:
                (project / filename).write_text(content, encoding='utf-8')
            if not run.launched or run.faults or run.preexisting:
                raise RuntimeError(f'{name}: monitor failure {run.faults or run.preexisting}')
            verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
            results.append({'name': name, 'verdict': verdict, 'fixture': payload})
            print(json.dumps({'name': name, 'verdict': verdict}), flush=True)
            if verdict != ('pass' if name == 'control' else 'killed'):
                raise RuntimeError(f'{name}: failed control or surviving mutant')
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        (evidence / 'results.json').write_text(json.dumps({
            'results': results, 'originals_intact': intact,
            'original_sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for p, raw in originals.items()},
        }, indent=2), encoding='utf-8')
        if not intact:
            raise RuntimeError('working sources changed')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
