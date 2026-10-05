"""Sensitivity of the offline heptane controls: Python mutants of the auditor.

These are NOT engine mutants and no Godot process is started. Each case edits
an in-memory copy of the offline auditor, loads it under the auditor's module
name in a fresh interpreter and expects the focal tests to fail. The saved
snapshot test is deselected, so a kill comes from an expectation fixed
independently of the auditor output. The file on disk is never modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
MODULE = "scripts.simulation.audit_g3_heptane_real_profile"
TARGET = ROOT / "scripts/simulation/audit_g3_heptane_real_profile.py"
TESTS = "tests/test_g3_heptane_real_profile.py"
SNAPSHOT = TESTS + "::test_saved_audit_reproduces_and_promotes_nothing"
BOOT = """
import importlib, sys, types
name, real_path, source_path = sys.argv[1:4]
package = importlib.import_module(name.rpartition(".")[0])
module = types.ModuleType(name)
module.__file__ = real_path
module.__package__ = package.__name__
try:
    exec(compile(open(source_path, encoding="utf-8").read(), real_path, "exec"), module.__dict__)
except BaseException as exc:
    print("INVALID_MUTANT", repr(exc))
    raise SystemExit(70)
sys.modules[name] = module
setattr(package, name.rpartition(".")[2], module)
import pytest
raise SystemExit(pytest.main(sys.argv[4:]))
"""
MUTANTS = [
    ("scale_factor_dropped", "(cp_native * factor / molar_mass)", "(cp_native / molar_mass)"),
    ("engine_nominal_molar_mass", "(cp_native * factor / molar_mass)",
     "(cp_native * factor / Decimal(100))"),
    ("joule_kilojoule_slip", "(cp_native * factor / molar_mass)",
     "(cp_native * factor / molar_mass / 1000)"),
    ("only_kelvin_offset_applied", "    return t90\n\n\ndef its90_scale_factor",
     "    return t48\n\n\ndef its90_scale_factor"),
    ("its90_step_skipped", "    return t90\n\n\ndef its90_scale_factor",
     "    return t68\n\n\ndef its90_scale_factor"),
    ("offset_sign_inverted", 'number(t_native, "native temperature") - (',
     'number(t_native, "native temperature") + ('),
    ("enthalpy_sign_lost", "return -integral if temperature < reference_k else integral",
     "return integral"),
    ("equation_22_extrapolated_below_join", "    if t <= anchor:\n        return (number(prior",
     "    if t < 0:\n        return (number(prior"),
    ("gas_support_not_enforced",
     '    if not low <= t <= high:\n        raise ValueError("outside reviewed gas support; '
     'no extrapolation")\n    anchor = number(prior["gas_cp_anchor_temperature_k"], "anchor")\n'
     "    if t <= anchor:",
     '    anchor = number(prior["gas_cp_anchor_temperature_k"], "anchor")\n    if t <= anchor:'),
    ("review_hash_not_checked", "hashlib.sha256(encoded).hexdigest() != REVIEW_SHA", "False"),
    ("source_identity_not_checked", 'record["sources"] != SOURCES', "False"),
    ("source_bytes_not_checked", "        _confined_once(root, source)\n", "        pass\n"),
    ("prior_identity_not_checked", 'record["prior_review"] != PRIOR', "False"),
    ("liquid_phase_accepted", 'if candidate["phase"] != "gas":', "if False:"),
    ("reference_state_not_checked",
     '(candidate["reference_temperature_k"] != REFERENCE_K\n'
     '            or candidate["reference_pressure_pa"] != REFERENCE_PA)', "False"),
    ("molar_mass_label_not_checked",
     'candidate["molar_mass_g_mol"] != expected["molar_mass_g_mol"]', "False"),
    ("provenance_not_checked", 'candidate["provenance"] != expected["provenance"]', "False"),
    ("basis_tolerance_one_percent", "rel_tol=1e-9, abs_tol=0.0", "rel_tol=1e-2, abs_tol=0.0"),
    ("label_tolerance_one_kelvin", "        if gap <= 1e-6:", "        if gap <= 1.0:"),
    ("extrapolation_window_removed",
     '            raise ValueError("extrapolation outside the reviewed support")',
     "            used.append(nearest)"),
    ("discretization_not_checked",
     "    if _native_interpolation_error(prior, review, native_points) > CP_INTERPOLATION_ABS_TOL:",
     "    if False:"),
    ("declared_limits_not_checked", "        if candidate[key] != expected[key]:", "        if False:"),
    ("witness_not_checked", "    if not matches or not wanted[0]", "    if False and not wanted[0]"),
    ("nonfinite_samples_accepted",
     '        if not _finite(sample["temperature_k"]) or not _finite(sample["cp_kj_kg_k"]):',
     "        if False:"),
    ("v_dp_term_ignored", "    v_dp = _vdp(review, top)[0] - _vdp(review, reference)[0]",
     "    v_dp = Decimal(0)"),
    ("liquid_molar_volume_per_kilogram", "    volume = molar_mass / rho25",
     "    volume = 1000 / rho25"),
    ("equation_12_derivative_sign", "(b1 - 3 * b3 * (tc - t) ** 2)", "(b1 + 3 * b3 * (tc - t) ** 2)"),
    ("synthetic_helper_not_pinned",
     "_sha_lf(Path(root).resolve() / SYNTHETIC_HELPER) != SYNTHETIC_HELPER_SHA_LF", "False"),
]
# A survivor is reported as such; none is excused in advance.
EXPECTED_SURVIVORS = {}


def run_case(source, basetemp, name):
    with tempfile.TemporaryDirectory() as folder:
        mutant = Path(folder) / "mutant.py"
        mutant.write_text(source, encoding="utf-8", newline="\n")
        command = [sys.executable, "-c", BOOT, MODULE, str(TARGET), str(mutant), TESTS, "-q",
                   "--color=no", "-p", "no:cacheprovider", "--deselect", SNAPSHOT,
                   "--basetemp", str(Path(basetemp) / name)]
        done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=600)
    tail = [line for line in done.stdout.splitlines() if line.strip()][-1:] or [""]
    failed = sorted({line.split(" ")[1].split("::")[1].split("[")[0]
                     for line in done.stdout.splitlines()
                     if line.startswith(("FAILED ", "ERROR "))})
    return done.returncode, tail[0], failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--basetemp", type=Path, required=True,
                        help="new directory outside the repository")
    args = parser.parse_args()
    if args.basetemp.resolve().is_relative_to(ROOT):
        parser.error("basetemp must be outside the repository")
    args.basetemp.mkdir(parents=True, exist_ok=False)
    original = TARGET.read_text(encoding="utf-8")
    before = hashlib.sha256(TARGET.read_bytes()).hexdigest()
    code, tail, _ = run_case(original, args.basetemp, "baseline")
    cases = []
    if code != 0:
        print(json.dumps({"valid": False, "error": "baseline does not pass", "tail": tail}))
        return 2
    for name, old, new in MUTANTS:
        if original.count(old) != 1:
            cases.append({"mutant": name, "outcome": "invalid", "detail": "anchor not unique"})
            continue
        code, tail, failed = run_case(original.replace(old, new), args.basetemp, name)
        outcome = {0: "survived", 1: "killed"}.get(code, "invalid")
        if outcome == "survived" and name in EXPECTED_SURVIVORS:
            outcome = "survived_as_declared"
        cases.append({"mutant": name, "outcome": outcome, "failing_tests": failed,
                      "detail": EXPECTED_SURVIVORS.get(name, tail)})
    counts = {key: sum(case["outcome"] == key for case in cases)
              for key in ["killed", "survived", "survived_as_declared", "invalid"]}
    unchanged = hashlib.sha256(TARGET.read_bytes()).hexdigest() == before
    report = {"kind": "offline_python_mutants_of_the_auditor_NOT_engine_mutants",
              "snapshot_test_deselected": True, "auditor_file_unchanged": unchanged,
              "total": len(cases), **counts, "cases": cases}
    print(json.dumps(report, indent=2))
    return 0 if unchanged and not counts["survived"] and not counts["invalid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
