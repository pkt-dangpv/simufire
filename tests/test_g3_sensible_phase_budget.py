"""Independent predeclared balances and the actual isolated GDScript ledger."""

from decimal import Decimal as D
import hashlib
import json
import os
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "G3_SENSIBLE_PHASE_BUDGET"
ORACLES = {"hot_cost": 98., "hot_liquid_sensible": 108.,
           "hot_vapour_sensible": 20., "hot_q": 2010., "hot_budget": 872.,
           "hot_total": 24110., "cold_cost": 102.5, "cold_q": 1997.5,
           "cold_liquid_sensible": -45., "cold_vapour_sensible": -5.}


def test_predeclared_independent_enthalpy_oracles():
    # Closed-form constant Cp and rational stoichiometry, not the .gd algorithm.
    r, b = D('.1'), D('.1')
    cost = r * (1000 + 100 - 120)
    assert cost == D(str(ORACLES['hot_cost']))
    assert D('.9') * 120 == D(str(ORACLES['hot_liquid_sensible']))
    assert D('.2') * (30 / D('.3')) == D(str(ORACLES['hot_vapour_sensible']))
    assert b * (20000 + 30 / D('.3')) == D(str(ORACLES['hot_q']))
    assert 1000 - 30 - cost == D(str(ORACLES['hot_budget']))
    assert 23000 + 110 + 1000 == D(str(ORACLES['hot_total']))
    assert 21100 + 128 + 872 + 2010 == D(str(ORACLES['hot_total']))
    assert r * (1000 - 25 + 50) == D(str(ORACLES['cold_cost']))
    assert b * (20000 - 25) == D(str(ORACLES['cold_q']))
    assert D('.9') * -50 == D(str(ORACLES['cold_liquid_sensible']))
    assert D('.2') * -25 == D(str(ORACLES['cold_vapour_sensible']))


def test_actual_sensible_ledger_l01_l20():
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot
    godot = Path(os.environ.get(
        'GODOT_EXE', r'C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe'))
    if not godot.exists():
        pytest.skip('Godot unavailable')
    if os.name == 'nt':
        assert godot_monitored_launch._available_gib() >= 6.
    run = run_godot([godot, '--headless', '--path', ROOT, '--script',
                     ROOT / 'tests/fixtures/g3_sensible_phase_budget.gd'],
                    timeout_s=120, allowed_exit_codes=(0,))
    payload = json.loads(next(line.split(' ', 1)[1] for line in run.stdout.splitlines()
                              if line.startswith(PREFIX + ' {')))
    assert payload['groups'] == [f'L{i:02}' for i in range(1, 21)]
    assert payload['failures'] == []
    assert payload['checks'] == 915
    assert payload['observations'] == pytest.approx(ORACLES, rel=1e-12, abs=1e-9)
    assert PREFIX + '_PASS' in run.stdout


def test_old_budget_functions_remain_byte_frozen():
    source = (ROOT / 'sim/fire/FuelMassBudgetModel.gd').read_text(encoding='utf-8')
    constants = source[source.index('const MASS_ABS_TOL_KG'):source.index('const SensibleProperties')].rstrip()
    assert hashlib.sha256(constants.encode()).hexdigest() == (
        '1af95199e6cf9a44f3d681db3e173f3f4df41a06c490cfa271327d788bf4448c')
    # 2026-10-05 type-guard hotfix: 'propose' and 'propose_phase_reference' each
    # gained one typeof guard on a text comparison. Their previous pins and the
    # proof that nothing else changed live in test_g3_type_guard_contracts.py.
    pins = {
        'propose': 'f33942b37955085056461a7615ec0317b6aec3f9e7abce97a00430d67294d131',
        'propose_phase_reference': '8e0d764e11bb6d565269c827f5ed91c785817e71e7960d334513406722da9992',
        '_oxygen_required': '7d16d87986cb916b1a77c7abcc985fa88e529872faa19ed42a533d94b36f4660',
        '_accepted_masses': '786337f4c82a9d6c4049890833476d2052f932673a958abcd26e3409dc4093d3',
        '_oxidation_quantities': '9138cfde22e685a7db337775eb68de706b3eac9720298bb419a935dfe430c929',
        '_mass_element_balance': '5f2b4c8da3aabcd5c77c97ed3d06f4107137ac44a987f8c9fe95db379e7069c9',
        '_dictionary': '45187d2686ce17ce7cb9fbd6cb012df8ec55d7754411c18ad948425ee0c2cc52',
        '_nonnegative': '7e19f5e85e093e0eaba6a8732e6476c5d375ae815fadd57190479d99304b0f8b',
        '_finite': 'd8e3afcab47f23c5c7c184cf1a7a4ccdcd4c2bfa144c1d108397191e931489f4',
        '_check_balance': 'cedef0f05c72d0ee899774cccd9102adc05ff46c580575063f247752e70cbe2a',
        '_rejected': 'a708c162e6f5252d47f92b0f762ad025f7a3a6676096981de98ba1d2f9d64300',
    }
    for name, expected in pins.items():
        match = re.search(r'^static func ' + name +
                          r'\([\s\S]*?(?=\n\n\n(?:##[^\n]*\n)*static func |\Z)', source, re.M)
        assert match, name
        # The original final function had its EOF newline; appending an API
        # makes that byte a separator. Preserve it in the baseline comparison.
        body = match.group() + ('\n' if name == '_rejected' else '')
        assert hashlib.sha256(body.encode()).hexdigest() == expected, name


def test_new_api_reuses_canonical_owners_without_runtime_caller():
    path = ROOT / 'sim/fire/FuelMassBudgetModel.gd'
    source = path.read_text(encoding='utf-8')
    new = source.split('static func propose_phase_sensible(', 1)[1]
    for call in ['SensibleProperties.evaluate(', 'propose_phase_reference(',
                 '_accepted_masses(', '_oxidation_quantities(', '_mass_element_balance(']:
        assert call in new
    # The versioned sensible owner is the single, still unintegrated, caller;
    # its own contract forbids loading it from any product resource.
    isolated = {path, ROOT / 'sim/fire/PrescribedSensiblePhaseController.gd'}
    for folder in ['sim', 'editor', 'ui', 'view', 'scenarios', 'scenes', 'tools']:
        for candidate in (ROOT / folder).rglob('*'):
            if candidate.is_file() and candidate not in isolated and candidate.suffix in {'.gd', '.json', '.tscn'}:
                assert 'propose_phase_sensible' not in candidate.read_text(encoding='utf-8')
    # No additional simulation switch; only the false approval field may end in _enabled.
    assert set(re.findall(r'\b[a-z_]+_enabled\b', new)) == {'integration_enabled'}


def test_isolated_mutation_projects_copy_the_canonical_cp_dependency():
    from scripts.simulation import run_g3_prescribed_release_mutations as release
    assert ROOT / 'sim/fire/SensibleEnthalpyModel.gd' in release.ASSETS
    for name in ['run_g3_fuel_mass_budget_mutations.py', 'run_g3_atomic_phase_mutations.py']:
        assert 'sim/fire/SensibleEnthalpyModel.gd' in (
            ROOT / 'scripts/simulation' / name).read_text(encoding='utf-8')


def test_predeclared_sensible_ledger_mutants():
    from scripts.simulation.run_g3_sensible_phase_mutations import prepared_variants
    source = (ROOT / 'sim/fire/FuelMassBudgetModel.gd').read_text(encoding='utf-8')
    variants = prepared_variants(source)
    assert len(variants) == 23
    assert all(value != source for value in variants.values())
