"""Isolated mutants that reinstall the text type-guard omissions of the older owners.

The defect under test IS a script error: a number, bool or container compared
with text aborts the owner instead of being rejected. A mutant that removes a
guard therefore produces a script error by construction, and the generic
classifier (which never counts a script error) cannot judge it. This campaign
uses its own, narrower rule. A mutant is killed only when ALL of this holds:

* the fixture ran to its end and printed its report (no parse error, no timeout,
  no monitor fault);
* it exited 1 with behavioral failures, including the failure the mutant declares;
* every script error is located in the owner file that was mutated - never in
  the fixture and never in another module - and when there are script errors
  at least one is the operand-type error of the reinstalled comparison.

Anything else is invalid, never a kill. ``--reproduce`` runs the same fixture
against the sources of the commit that preceded the fix.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source  # noqa: E402

PROVIDER = ROOT / "sim/fire/PrescribedFuelReleaseModel.gd"
KERNEL = ROOT / "sim/fire/FuelMassBudgetModel.gd"
CALLER = ROOT / "sim/fire/PrescribedPhaseBudgetController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_type_guard_contracts.gd"
ASSETS = [PROVIDER, KERNEL, CALLER, ROOT / "sim/fire/SensibleEnthalpyModel.gd",
          ROOT / "sim/fire/PrescribedSensiblePhaseController.gd", FIXTURE]
PREFIX = "G3_TYPE_GUARD_CONTRACTS"
PREFIX_COMMIT = "482876079a990035b1eed1ec2696ba4590f3f399"
OWNERS = "res://sim/fire/"
TEXT = "[TYPE_STRING, TYPE_STRING_NAME]"
_LITERALS = "if typeof(data.get(key)) not in " + TEXT + " or data.get(key) != PROGRAM_LITERALS[key]:"
_PAIR = ("var textual: bool = typeof(data.get(\"interpolation\")) in " + TEXT +
         " and typeof(data.get(\"quantity\")) in " + TEXT)
_IDENTITY = ("if typeof(p.get(\"fingerprint\")) not in " + TEXT +
             " or p.get(\"fingerprint\") != checked[\"fingerprint\"]:")
_BASIS = ("if typeof(m.get(\"chemical_energy_basis\")) not in " + TEXT +
          " or m.get(\"chemical_energy_basis\") != \"complete_oxidation_net\":")
_REFERENCE = "if typeof(m.get(key)) not in " + TEXT + " or m.get(key) != required[key]:"
_CONTEXT = ("if typeof(c.get(\"schema\")) not in " + TEXT +
            " or c.get(\"schema\") != \"g3_prescribed_phase_context_v1\":")
_SNAPSHOT = ("var textual: bool = typeof(s.get(\"schema\")) in " + TEXT +
             " and typeof(s.get(\"context_fingerprint\")) in " + TEXT)

# name: (owner file, anchor, replacement, failure label the mutant must cause)
MUTATIONS = {
    "G01_provider_literals_unguarded": (
        PROVIDER, _LITERALS, "if data.get(key) != PROGRAM_LITERALS[key]:", "provider initial mode structured"),
    "G02_provider_pair_unguarded": (
        PROVIDER, _PAIR, "var textual: bool = true", "provider initial interpolation structured"),
    "G03_provider_pair_quantity_unguarded": (
        PROVIDER, _PAIR, "var textual: bool = typeof(data.get(\"interpolation\")) in " + TEXT,
        "provider initial quantity structured"),
    "G04_provider_identity_unguarded": (
        PROVIDER, _IDENTITY, "if p.get(\"fingerprint\") != checked[\"fingerprint\"]:",
        "provider propose fingerprint type structured"),
    "G05_kernel_basis_unguarded": (
        KERNEL, _BASIS, "if m.get(\"chemical_energy_basis\") != \"complete_oxidation_net\":",
        "kernel chemical_energy_basis structured"),
    "G06_reference_literals_unguarded": (
        KERNEL, _REFERENCE, "if m.get(key) != required[key]:", "reference schema structured"),
    "G07_caller_context_unguarded": (
        CALLER, _CONTEXT, "if c.get(\"schema\") != \"g3_prescribed_phase_context_v1\":",
        "caller initialize schema structured"),
    "G08_caller_snapshot_unguarded": (
        CALLER, _SNAPSHOT, "var textual: bool = true", "forged snapshot behind mistyped schema no write"),
    "G09_caller_snapshot_fingerprint_unguarded": (
        CALLER, _SNAPSHOT, "var textual: bool = typeof(s.get(\"schema\")) in " + TEXT,
        "caller restore context_fingerprint structured"),
    "G10_provider_literals_coerced": (
        PROVIDER, _LITERALS, "if str(data.get(key)) != PROGRAM_LITERALS[key]:", "provider impostor mode structured"),
    "G11_reference_literals_coerced": (
        KERNEL, _REFERENCE, "if str(m.get(key)) != required[key]:", "reference impostor schema structured"),
    "G12_caller_context_coerced": (
        CALLER, _CONTEXT, "if str(c.get(\"schema\")) != \"g3_prescribed_phase_context_v1\":",
        "caller impostor context schema structured"),
}
ERROR_BLOCK = re.compile(r"SCRIPT ERROR: (?P<message>[^\n]*)\r?\n\s+at: (?P<function>\S+) \((?P<file>res://[^:)]+):(?P<line>\d+)\)")


def prepared_variants(sources: dict[Path, str]) -> dict[str, dict[Path, str]]:
    variants = {}
    for name, (owner, anchor, replacement, _label) in MUTATIONS.items():
        variants[name] = {**sources, owner: changed_source(sources[owner], anchor, replacement)}
    return variants


def script_errors(text: str) -> list[dict[str, str]]:
    return [match.groupdict() for match in ERROR_BLOCK.finditer(text)]


def resource(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def verdict_of(stdout: str, stderr: str, returncode: int, expected_label: str = "",
               owners: tuple[str, ...] = ()) -> tuple[str, dict, str]:
    """pass / killed, or invalid with its reason. See the module docstring.

    ``owners`` are the only ``res://`` files in which a script error may occur.
    """
    text = stdout + "\n" + stderr
    lines = [line for line in stdout.splitlines() if line.startswith(PREFIX + " {")]
    if not lines:
        return "invalid", {}, "fixture report absent"
    if "Parse Error" in text:
        return "invalid", {}, "parse error"
    try:
        payload = json.loads(lines[-1].split(" ", 1)[1])
    except ValueError:
        return "invalid", {}, "fixture report is not JSON"
    errors = script_errors(text)
    if text.count("SCRIPT ERROR") != len(errors):
        return "invalid", {}, "script error that could not be located"
    outside = sorted({error["file"] for error in errors
                      if not error["file"].startswith(OWNERS) or (owners and error["file"] not in owners)})
    if outside:
        return "invalid", {}, f"script error outside the mutated owner: {outside}"
    failures = payload.get("failures", [])
    if returncode == 0 and not failures and not errors and PREFIX + "_PASS" in stdout:
        return "pass", payload, ""
    if returncode != 1 or not failures:
        return "invalid", {}, f"inconsistent termination: exit {returncode}, {len(failures)} failures"
    if errors and not any(error["message"].startswith("Invalid operands") for error in errors):
        return "invalid", {}, "script errors without the operand-type error under test"
    if expected_label and not any(expected_label in failure for failure in failures):
        return "invalid", {}, f"died without the declared failure: {expected_label}"
    return "killed", payload, f"{len(errors)} script errors, all in the mutated owner"


def _prefix_sources() -> dict[Path, bytes]:
    out = {}
    for path in ASSETS:
        if path == FIXTURE:
            out[path] = path.read_bytes()
            continue
        shown = subprocess.run(["git", "-C", str(ROOT), "show", f"{PREFIX_COMMIT}:{path.relative_to(ROOT).as_posix()}"],
                               capture_output=True, check=True)
        out[path] = shown.stdout
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--reproduce", action="store_true", help="also run the pre-fix sources of PREFIX_COMMIT")
    args = parser.parse_args()
    originals = {path: path.read_bytes() for path in ASSETS}
    sources = {path: raw.decode("utf-8") for path, raw in originals.items()}
    variants = prepared_variants(sources)
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / ("g3_type_guard_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    fixed = (resource(PROVIDER), resource(KERNEL), resource(CALLER))
    runs: dict[str, tuple[dict[Path, bytes], str, str, tuple[str, ...]]] = {
        "control": (originals, "pass", "", ())}
    if args.reproduce:
        runs["reproduction_before_fix"] = (_prefix_sources(), "killed", "structured valid=false", fixed)
    for name, changed in variants.items():
        runs[name] = ({path: text.encode("utf-8") for path, text in changed.items()}, "killed",
                      MUTATIONS[name][3], (resource(MUTATIONS[name][0]),))
    results = []
    try:
        for name, (files, expected, label, owners) in runs.items():
            project = evidence / name
            for path, raw in files.items():
                target = project / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="Isolated type guards"\n', encoding="utf-8")
            run = godot_monitored_launch.run(
                [godot, "--headless", "--path", project, "--script", project / FIXTURE.relative_to(ROOT)],
                timeout_s=180, environment=os.environ.copy())
            for filename, content in [("health.json", json.dumps(run.health, indent=2)),
                                      ("stdout.log", run.stdout), ("stderr.log", run.stderr)]:
                (project / filename).write_text(content, encoding="utf-8")
            if not run.launched:
                raise RuntimeError(f"{name}: not launched: {run.faults or run.preexisting}")
            if run.faults or run.preexisting:
                verdict, payload, reason = "invalid", {}, f"monitor: {run.faults or run.preexisting}"
            else:
                verdict, payload, reason = verdict_of(run.stdout, run.stderr, run.returncode, label, owners)
            errors = script_errors(run.stdout + "\n" + run.stderr)
            results.append({
                "name": name, "verdict": verdict, "expected": expected, "reason": reason,
                "checks": payload.get("checks"), "failures": len(payload.get("failures", [])),
                "first_failures": payload.get("failures", [])[:5], "declared_failure": label,
                "script_errors": len(errors),
                "script_error_sites": sorted({f"{e['file']}:{e['line']}" for e in errors}),
            })
            print(json.dumps({key: results[-1][key] for key in
                              ["name", "verdict", "reason", "failures", "script_errors"]}), flush=True)
            if name == "control" and verdict != "pass":
                raise RuntimeError("control is not green; no mutant verdict is meaningful")
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        mutants = [item for item in results if item["name"].startswith("G")]
        summary = {
            "results": results, "originals_intact": intact,
            "control": next((item["verdict"] for item in results if item["name"] == "control"), None),
            "reproduction": next((item["verdict"] for item in results
                                  if item["name"] == "reproduction_before_fix"), None),
            "declared": len(variants), "executed": len(mutants),
            "killed": sum(item["verdict"] == "killed" for item in mutants),
            "survivors": [item["name"] for item in mutants if item["verdict"] == "pass"],
            "invalid": [item["name"] for item in mutants if item["verdict"] == "invalid"],
            "original_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for path, raw in originals.items()},
        }
        (evidence / "results.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps({key: summary[key] for key in ["control", "reproduction", "declared", "executed",
                                                        "killed", "survivors", "invalid", "originals_intact"]}),
              flush=True)
        if not intact:
            raise RuntimeError("working sources changed")
    reproduced = not args.reproduce or summary["reproduction"] == "killed"
    return 0 if summary["killed"] == summary["declared"] == summary["executed"] and reproduced else 1


if __name__ == "__main__":
    raise SystemExit(main())
