"""Typed-text contract of the three older isolated owners (hotfix 2026-10-05).

A number, bool or container where text is expected used to abort the owner with
a script error instead of a structured rejection. The guards are type checks
only: no law, tolerance, accepted input or inherited fingerprint changes.
"""
import hashlib
import json
import os
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/g3_type_guard_contracts.gd"
PREFIX = "G3_TYPE_GUARD_CONTRACTS"
CHECKS = 4013  # Measured on the real fixture; never anticipated.
MUTANTS = 12
TEXT = "[TYPE_STRING, TYPE_STRING_NAME]"
OWNERS = ["PrescribedFuelReleaseModel", "FuelMassBudgetModel", "PrescribedPhaseBudgetController"]

# Measured on the sources BEFORE the fix (48287607); the fix must not move them.
FINGERPRINTS = {
    "provider_measured": "cbd1f791cc39b786e3595628ad42322de48d6ca287c792e1172327a43b04bef6",
    "provider_linear": "9fd3447b9a2b4e4e8b9bff74d552e344ab256f6ad9a66b6b54bfb8b90ebd2638",
    "caller_context": "984727f4f42f79b153618449710bb288026f67fb5fe8e83fee7dd37bb641a0ca",
    "caller_progress": "cbd1f791cc39b786e3595628ad42322de48d6ca287c792e1172327a43b04bef6",
    "sensible_context": "f0d2fcd710d1278575c12768a9b629aca79308e652e69c7c6982d3d6ed256c4e",
}

# Whole-file SHA-256 (LF) before the fix, and the exact guard edits. Undoing the
# edits textually must give back those hashes: nothing else may have changed.
HISTORICAL = {
    "PrescribedFuelReleaseModel": "89a8c5ad8c663c9f417e23381c6cbf0d2c07bc5c56f5ad01ff7dc1ed6e0cd9fc",
    "FuelMassBudgetModel": "8258e2aa9b2bdabe1a126672e04e4d663f34c76cb3b78935d7db9dba1924478f",
    "PrescribedPhaseBudgetController": "ce88db42f1f15325b1ae2a226a10fae01137993f8e4483f8115cd05394750667",
}
CURRENT = {
    "PrescribedFuelReleaseModel": "db58278f2fff141d31148301095d41234f3732a66fa4140f74abfbaff483897d",
    "FuelMassBudgetModel": "7ab01e1628441c048d55a45a512fc85aed8347dbd8140a29c98160e82fcd3f12",
    "PrescribedPhaseBudgetController": "69f74112d52ca77c7c4c3c07987d21747920b970d3e1221fa03464d6170942ed",
}
UNCHANGED = {
    "SensibleEnthalpyModel": "0340a7263591276a3fb210c570d44eba97ce0326b5c90c539be72e29b1672627",
    "PrescribedSensiblePhaseController": "63ea60420fa7a1995195addbc22e1fcfa4c30288b4fbb46174df44b120c01383",
}
GUARD_EDITS = {
    "PrescribedFuelReleaseModel": [
        ('\tif typeof(p.get("fingerprint")) not in ' + TEXT + ' or p.get("fingerprint") != checked["fingerprint"]:\n',
         '\tif p.get("fingerprint") != checked["fingerprint"]:\n'),
        ('\t# Type first: comparing a number, bool or container with text aborts the script.\n', ''),
        ('\t\tif typeof(data.get(key)) not in ' + TEXT + ' or data.get(key) != PROGRAM_LITERALS[key]:\n',
         '\t\tif data.get(key) != PROGRAM_LITERALS[key]:\n'),
        ('\tvar textual: bool = typeof(data.get("interpolation")) in ' + TEXT +
         ' and typeof(data.get("quantity")) in ' + TEXT + '\n', ''),
        ('\tvar linear: bool = textual and data.get(', '\tvar linear: bool = data.get('),
        ('\tvar measured: bool = textual and data.get(', '\tvar measured: bool = data.get('),
    ],
    "FuelMassBudgetModel": [
        ('\tif typeof(m.get("chemical_energy_basis")) not in ' + TEXT +
         ' or m.get("chemical_energy_basis") != "complete_oxidation_net":\n',
         '\tif m.get("chemical_energy_basis") != "complete_oxidation_net":\n'),
        ('\t\tif typeof(m.get(key)) not in ' + TEXT + ' or m.get(key) != required[key]:\n',
         '\t\tif m.get(key) != required[key]:\n'),
    ],
    "PrescribedPhaseBudgetController": [
        ('\tif typeof(c.get("schema")) not in ' + TEXT + ' or c.get("schema") != "g3_prescribed_phase_context_v1":\n',
         '\tif c.get("schema") != "g3_prescribed_phase_context_v1":\n'),
        ('\t# Type first: an aborted check would add no error and let the snapshot through.\n', ''),
        ('\tvar textual: bool = typeof(s.get("schema")) in ' + TEXT +
         ' and typeof(s.get("context_fingerprint")) in ' + TEXT + '\n', ''),
        ('\tif not textual or s.get("schema") != ', '\tif s.get("schema") != '),
    ],
}
# A text comparison of an unvalidated field against a literal or an identity.
TEXT_COMPARISON = re.compile(
    r'\.get\([^()]*\) (?:!=|==) (?:"|PROGRAM_LITERALS\[|required\[|checked\[|_fingerprint\()')
GUARDED_LINES = {"PrescribedFuelReleaseModel": 4, "FuelMassBudgetModel": 2, "PrescribedPhaseBudgetController": 2}


def _source(name: str) -> str:
    return (ROOT / f"sim/fire/{name}.gd").read_bytes().replace(b"\r\n", b"\n").decode("utf-8")


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def test_actual_type_guard_contracts_t01_t12():
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot
    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", FIXTURE],
                          timeout_s=180, allowed_exit_codes=(0,))
    output = (completed.stdout or "") + (completed.stderr or "")
    # The contract itself: a mistyped field is rejected, it never aborts a script.
    assert "SCRIPT ERROR" not in output and "Parse Error" not in output
    payload = json.loads(next(line.split(" ", 1)[1] for line in completed.stdout.splitlines()
                              if line.startswith(PREFIX + " {")))
    assert payload["failures"] == []
    assert payload["groups"] == [f"T{i:02}" for i in range(1, 13)]
    assert payload["checks"] == CHECKS
    assert payload["observations"] == FINGERPRINTS
    assert PREFIX + "_PASS" in completed.stdout


@pytest.mark.parametrize("name", OWNERS)
def test_only_the_type_guards_changed(name):
    source = _source(name)
    reverted = source
    if name == "PrescribedPhaseBudgetController":
        # The explicit positive verdict (later fix) sits on top of these guards:
        # its own module pins the current bytes and undoes it down to this hash.
        from tests.test_g3_reference_caller_positive_verdict import undo_verdict_edits
        reverted = undo_verdict_edits(source)
    assert _sha(reverted) == CURRENT[name]
    for guarded, original in GUARD_EDITS[name]:
        assert reverted.count(guarded) == 1, guarded
        reverted = reverted.replace(guarded, original, 1)
    # Undoing the guards reproduces the bytes that were frozen before the fix.
    assert _sha(reverted) == HISTORICAL[name]


@pytest.mark.parametrize("name, expected", sorted(UNCHANGED.items()))
def test_modules_outside_the_fix_remain_frozen(name, expected):
    assert _sha(_source(name)) == expected


@pytest.mark.parametrize("name", OWNERS)
def test_every_text_comparison_is_type_guarded(name):
    guarded = 0
    for line in _source(name).splitlines():
        if TEXT_COMPARISON.search(line):
            assert "typeof(" in line or "textual" in line, line.strip()
            guarded += 1
    # A new comparison must be reviewed here, not slip in unguarded.
    assert guarded == GUARDED_LINES[name]


@pytest.mark.parametrize("name", OWNERS)
def test_guards_validate_types_and_never_coerce(name):
    source = _source(name)
    # Text is checked, never produced: no str()/String() of an unvalidated field compared.
    assert re.search(r"(?:str|String)\([a-z]+\.get\([^()]*\)\) (?:!=|==)", source) is None
    assert source.count(TEXT) == {"PrescribedFuelReleaseModel": 4, "FuelMassBudgetModel": 2,
                                  "PrescribedPhaseBudgetController": 3}[name]
    # Same rejection messages as before the fix.
    for message in {"PrescribedFuelReleaseModel": ["progress fingerprint does not match rate program/version",
                                                   "unsupported rate program ",
                                                   "unsupported interpolation/quantity pair"],
                    "FuelMassBudgetModel": ["chemical_energy_basis must be complete_oxidation_net",
                                            "phase_material incompatible "],
                    "PrescribedPhaseBudgetController": ["incompatible context schema",
                                                        "snapshot/context identity mismatch"]}[name]:
        assert source.count('"' + message) == 1


def test_inherited_fingerprints_keep_their_algorithms():
    provider = _source("PrescribedFuelReleaseModel")
    caller = _source("PrescribedPhaseBudgetController")
    assert provider.count('(version + JSON.stringify(data, "", true, true)).sha256_text()') == 1
    assert caller.count('(VERSION + JSON.stringify(context, "", true, true)).sha256_text()') == 1
    for version in ['"prescribed_fuel_release_v1"', '"prescribed_measured_depletion_v1"']:
        assert provider.count(version) == 1
    assert caller.count('"prescribed_phase_controller_v1"') == 1


def test_predeclared_type_guard_mutants_have_one_real_anchor_each():
    from scripts.simulation import run_g3_type_guard_mutations as campaign
    sources = {path: path.read_text(encoding="utf-8") for path in campaign.ASSETS}
    variants = campaign.prepared_variants(sources)
    assert len(variants) == len(campaign.MUTATIONS) == MUTANTS
    assert [name[:3] for name in variants] == [f"G{i:02}" for i in range(1, MUTANTS + 1)]
    fixture = FIXTURE.read_text(encoding="utf-8")
    for name, (owner, _anchor, _replacement, label) in campaign.MUTATIONS.items():
        changed = [path for path in sources if variants[name][path] != sources[path]]
        assert changed == [owner], name
        # The declared failure is a real fixture label, word by word.
        assert label and all(word in fixture for word in label.split()), name
    assert all(path.read_text(encoding="utf-8") == text for path, text in sources.items())
    assert campaign.FIXTURE == FIXTURE and campaign.PREFIX == PREFIX


def _report(failures):
    return PREFIX + " " + json.dumps({"checks": 1, "failures": failures})


def _error(message, location):
    return f"SCRIPT ERROR: {message}\n   at: f ({location})\n   GDScript backtrace (most recent call first):\n"


OPERAND = "Invalid operands 'int' and 'String' in operator '!='."
ACCESS = "Invalid access to property or key 'valid' on a base object of type 'Dictionary'."
OWNER = "res://sim/fire/PrescribedFuelReleaseModel.gd"
OWNER_SITE = OWNER + ":117"
OTHER_OWNER_SITE = "res://sim/fire/FuelMassBudgetModel.gd:167"
LABEL = "provider initial mode structured"


def test_reinstalled_omission_is_killed_only_through_its_own_behaviour():
    from scripts.simulation.run_g3_type_guard_mutations import verdict_of
    failing = _report([LABEL + " valid=false"])
    stderr = _error(OPERAND, OWNER_SITE) + _error(ACCESS, OWNER + ":30")
    assert verdict_of(failing, stderr, 1, LABEL, (OWNER,))[0] == "killed"
    # A coercion mutant fails behaviorally without any script error.
    assert verdict_of(failing, "", 1, LABEL, (OWNER,))[0] == "killed"
    # The same target error in ANOTHER module is foreign to this mutant.
    foreign = verdict_of(failing, stderr + _error(OPERAND, OTHER_OWNER_SITE), 1, LABEL, (OWNER,))
    assert foreign[0] == "invalid" and "outside the mutated owner" in foreign[2]
    assert verdict_of(_report([]) + "\n" + PREFIX + "_PASS", "", 0)[0] == "pass"


@pytest.mark.parametrize("stdout, stderr, code, label", [
    ("", "", 1, LABEL),
    (_report([LABEL]), "Parse Error: unexpected token", 1, LABEL),
    (_report([LABEL]), _error(OPERAND, "res://tests/fixtures/g3_type_guard_contracts.gd:10"), 1, LABEL),
    (_report([LABEL]), _error(OPERAND, OWNER_SITE) + _error(OPERAND, "res://tests/fixtures/x.gd:3"), 1, LABEL),
    (_report([LABEL]), "SCRIPT ERROR: something without a location", 1, LABEL),
    (_report([LABEL]), _error(ACCESS, OWNER_SITE), 1, LABEL),
    (_report([LABEL]), _error(OPERAND, OWNER_SITE), 0, LABEL),
    (_report([LABEL]), _error(OPERAND, OWNER_SITE), -1, LABEL),
    (_report([]), _error(OPERAND, OWNER_SITE), 1, LABEL),
    (_report([]) + "\n" + PREFIX + "_PASS", _error(OPERAND, OWNER_SITE), 0, LABEL),
    (_report(["another failure"]), _error(OPERAND, OWNER_SITE), 1, LABEL),
    (PREFIX + " {not json", "", 1, LABEL),
])
def test_infrastructure_or_unrelated_faults_are_never_kills(stdout, stderr, code, label):
    from scripts.simulation.run_g3_type_guard_mutations import verdict_of
    verdict, payload, reason = verdict_of(stdout, stderr, code, label, (OWNER,))
    assert verdict == "invalid" and payload == {} and reason


def test_campaign_confines_each_mutant_to_its_own_owner_file():
    from scripts.simulation import run_g3_type_guard_mutations as campaign
    source = Path(campaign.__file__).read_text(encoding="utf-8")
    assert "(resource(MUTATIONS[name][0]),)" in source
    assert "verdict_of(run.stdout, run.stderr, run.returncode, label, owners)" in source
    assert campaign.resource(campaign.CALLER) == "res://sim/fire/PrescribedPhaseBudgetController.gd"


def test_historical_campaigns_keep_strict_classifiers_and_real_anchors():
    from scripts.simulation import run_g3_atomic_phase_mutations as caller
    from scripts.simulation import run_g3_fuel_mass_budget_mutations as kernel
    from scripts.simulation import run_g3_prescribed_release_mutations as provider
    for stdout, stderr in [(PREFIX + ' {"failures":["x"]}', "SCRIPT ERROR"), ("", "")]:
        with pytest.raises(RuntimeError):
            kernel.classify(stdout, stderr, 1, PREFIX)
    kernel_source = _source("FuelMassBudgetModel")
    provider_source = _source("PrescribedFuelReleaseModel")
    caller_source = _source("PrescribedPhaseBudgetController")
    for family, source, count in [(kernel.MUTATIONS, kernel_source, 10), (kernel.PHASE_MUTATIONS, kernel_source, 12),
                                  (provider.MUTATIONS, provider_source, 11),
                                  (provider.MEASURED_MUTATIONS, provider_source, 11),
                                  (caller.MUTATIONS, caller_source, 18)]:
        assert len(family) == count
        assert all(kernel.changed_source(source, *patch) != source for patch in family.values())
    # The re-anchored mutants still exempt one literal; they do not drop the type guard.
    for patch in [kernel.PHASE_MUTATIONS["P08_schema_not_checked"], provider.MUTATIONS["M05_ignore_rate_unit"]]:
        assert patch[1].startswith("if key != ") and "typeof(" in patch[1]
