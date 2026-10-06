"""Isolated mutants of the reference caller's acceptance decision.

The caller accepts a state only on an explicit positive verdict of its
validator. Every mutant here reinstalls a way of accepting without one, and is
judged by the strict generic classifier: only a behavioral fixture failure with
exit 1 is a kill; a parse error, a script error, a timeout or a monitor fault
is invalid.

Two extra runs are not mutants and never count as kills:

``--reproduce``      the sources of the commit before the fix, with a validator
                     double that reports nothing: they accept and write.
``--abort-control``  the fixed sources with a validator double that REALLY
                     aborts. It must pass, and the only script errors allowed
                     are the ones it provokes, on its own marked line.
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
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source, classify  # noqa: E402

MODEL = ROOT / "sim/fire/PrescribedPhaseBudgetController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_reference_caller_positive_verdict.gd"
ABORT_FIXTURE = ROOT / "tests/fixtures/g3_reference_caller_abort_control.gd"
DEPENDENCIES = [ROOT / "sim/fire/PrescribedFuelReleaseModel.gd", ROOT / "sim/fire/FuelMassBudgetModel.gd",
                ROOT / "sim/fire/SensibleEnthalpyModel.gd",
                ROOT / "sim/fire/HeptaneRealCpProfiles.gd"]  # preloaded by the ledger since 2026-10-06
PREFIX = "G3_REFERENCE_CALLER_POSITIVE_VERDICT"
ABORT_PREFIX = "G3_REFERENCE_CALLER_ABORT_CONTROL"
REPRODUCTION_PREFIX = "G3_POSITIVE_VERDICT_REPRODUCTION"
PREFIX_COMMIT = "089e35bf61dd2567bff7690e758431eacd93d794"
ABORT_MARK = "# ABORT LINE"
_HELPER = "\tif typeof(verdict) == TYPE_BOOL and verdict and errors.size() == reported:\n"
_INITIALIZE = "\tif not _accepted(candidate, c, errors):\n\t\treturn _failure(errors)\n"
_CURRENT = "\tvar current: bool = _accepted(_owned, _context, errors)\n\tvar end: float = "
_CANDIDATE = "\tif not _accepted(candidate, _context, errors):\n\t\treturn _failure(errors)\n"
_RESTORE_CURRENT = "\tvar current: bool = _accepted(_owned, _context, errors)\n\tvar requested: bool = "
_RESTORE_REQUESTED = "\tvar requested: bool = _accepted(saved, _context, errors)\n"
_RESTORE_DECISION = "\tif not current or not requested:\n\t\treturn _failure(errors)\n"
_PREVIEW_RESULT = ("\tif typeof(proposal.get(\"valid\")) != TYPE_BOOL or typeof(proposal.get(\"candidate\")) != "
                   "TYPE_DICTIONARY or typeof(proposal.get(\"step\")) != TYPE_DICTIONARY:\n")
_STRUCTURAL_EXIT = "\tif errors.size() != reported:\n\t\treturn false\n\tvar source: Dictionary = "
_SOURCE_EXIT = "\t\terrors.append(\"invalid source progress\")\n\t\treturn false\n"
_FINAL = "\treturn errors.size() == reported\n\n\n## An empty error list is not acceptance"

MUTATIONS = {
    "V01_helper_decides_by_empty_errors": (_HELPER, "\tif errors.size() == reported:\n"),
    "V02_helper_ignores_reported_errors": (_HELPER, "\tif typeof(verdict) == TYPE_BOOL and verdict:\n"),
    "V03_initialize_decides_by_empty_errors": (
        _INITIALIZE, "\t_check_owned(candidate, c, errors)\n\tif not errors.is_empty():\n\t\treturn _failure(errors)\n"),
    "V04_initialize_writes_after_rejection": (
        _INITIALIZE, "\tif not _accepted(candidate, c, errors):\n\t\t_context = c.duplicate(true)\n"
                     "\t\t_owned = candidate.duplicate(true)\n\t\treturn _failure(errors)\n"),
    "V05_preview_current_decides_by_empty_errors": (
        _CURRENT, "\t_check_owned(_owned, _context, errors)\n\tvar current: bool = true\n\tvar end: float = "),
    "V06_preview_current_state_not_validated": (_CURRENT, "\tvar current: bool = true\n\tvar end: float = "),
    "V07_preview_candidate_decides_by_empty_errors": (
        _CANDIDATE, "\t_check_owned(candidate, _context, errors)\n\tif not errors.is_empty():\n"
                    "\t\treturn _failure(errors)\n"),
    "V08_preview_candidate_not_validated": (_CANDIDATE, "\tif false:\n\t\treturn _failure(errors)\n"),
    "V09_restore_current_decides_by_empty_errors": (
        _RESTORE_CURRENT, "\t_check_owned(_owned, _context, errors)\n\tvar current: bool = true\n"
                          "\tvar requested: bool = "),
    "V10_restore_requested_decides_by_empty_errors": (
        _RESTORE_REQUESTED, "\t_check_owned(saved, _context, errors)\n\tvar requested: bool = errors.is_empty()\n"),
    "V11_restore_requested_not_validated": (_RESTORE_REQUESTED, "\tvar requested: bool = true\n"),
    "V12_restore_writes_after_rejection": (
        _RESTORE_DECISION, "\tif not current or not requested:\n\t\tif typeof(saved) == TYPE_DICTIONARY:\n"
                           "\t\t\t_owned = saved.duplicate(true)\n\t\treturn _failure(errors)\n"),
    "V13_commit_ignores_preview_verdict": (
        _PREVIEW_RESULT, "\tif typeof(proposal.get(\"candidate\")) != TYPE_DICTIONARY or "
                         "typeof(proposal.get(\"step\")) != TYPE_DICTIONARY:\n"),
    "V14_validator_confirms_before_coherence_checks": (
        _STRUCTURAL_EXIT, "\tif errors.size() != reported:\n\t\treturn false\n"
                          "\tif reported >= 0:\n\t\treturn true\n\tvar source: Dictionary = "),
    "V15_validator_final_verdict_unconditional": (_FINAL, _FINAL.replace("errors.size() == reported", "true")),
    "V16_validator_source_exit_positive": (
        _SOURCE_EXIT, "\t\terrors.append(\"invalid source progress\")\n\t\treturn true\n"),
    "V17_validator_structural_exit_positive": (
        _STRUCTURAL_EXIT, "\tif errors.size() != reported:\n\t\treturn true\n\tvar source: Dictionary = "),
}

# Runs only against the pre-fix sources, whose validator returned nothing (void).
REPRODUCTION_FIXTURE = '''extends SceneTree

## Reproduction on the sources BEFORE the fix. The validator double reports no
## error and confirms nothing; the previous decision took that as acceptance.
var _out: Dictionary = {}


class Silent extends "res://sim/fire/PrescribedPhaseBudgetController.gd":
	var calls: int = 0


	func _check_owned(_value: Variant, _context: Dictionary, _errors: Array[String]) -> void:
		calls += 1


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_done")


func _context() -> Dictionary:
	return {"schema": "g3_prescribed_phase_context_v1",
		"program": {"profile_id": "synthetic_constant", "component_id": "synthetic_observed_reservoir",
			"initial_mass_kg": 1.0, "mode": "prescribed", "quantity": "measured_reservoir_depletion",
			"unit": "kg/s", "time_origin": "synthetic_zero", "outside_domain": "reject",
			"interpolation": "piecewise_constant_left",
			"samples": [{"time_s": 0.0, "rate_kg_s": 0.1}, {"time_s": 2.0, "rate_kg_s": 0.0}]},
		"material": {"schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid", "vapour_phase": "gas",
			"reference_temperature_k": 298.15, "reference_pressure_pa": 100000.0, "water_product_phase": "gas",
			"atom_mass_basis": "nominal_C12_H1_O16", "chemical_energy_basis": "complete_oxidation_net",
			"mass_fractions": {"C": 0.75, "H": 0.25, "O": 0.0}, "liquid_heat_kj_kg": 19000.0,
			"vapour_heat_kj_kg": 20000.0, "phase_enthalpy_kj_kg": 1000.0, "provenance": "synthetic:not_heptane"},
		"attribution": {"input_component_id": "synthetic_observed_reservoir", "modeled_component_id": "synthetic_component",
			"input_quantity": "measured_reservoir_depletion", "rule": "all_depletion_as_reference_vapour",
			"status": "conditional_not_measured_emission", "provenance": "synthetic:no_experimental_approval"},
		"seed": {"initial_o2_kg": 10.0, "initial_thermal_budget_kj": 1000.0,
			"energy_boundary_kind": "synthetic_independent_initial_budget",
			"energy_boundary_provenance": "synthetic:independent_seed"}}


func _run() -> void:
	var owner: RefCounted = Silent.new()
	_out["initialize_valid"] = owner.initialize(_context()).get("valid")
	_out["commit_valid"] = owner.commit_step(1.0, 0.1, 0).get("valid")
	_out["budget_before"] = owner.snapshot()["phase"]["thermal_budget_kj"]
	_out["liquid_before"] = owner.snapshot()["phase"]["liquid_fuel_kg"]
	var forged: Dictionary = owner.snapshot()
	forged["phase"]["thermal_budget_kj"] = 5000.0
	forged["phase"]["liquid_fuel_kg"] = 0.25
	_out["restore_forged_valid"] = owner.restore(forged, 1).get("valid")
	_out["budget_after"] = owner.snapshot()["phase"]["thermal_budget_kj"]
	_out["liquid_after"] = owner.snapshot()["phase"]["liquid_fuel_kg"]
	_out["validator_calls"] = owner.calls
	_out["completed"] = true


func _done() -> void:
	print("G3_POSITIVE_VERDICT_REPRODUCTION " + JSON.stringify(_out))
	quit(0)
'''
ERROR_BLOCK = re.compile(r"SCRIPT ERROR: (?P<message>[^\n]*)\r?\n\s+at: (?P<function>\S+) \((?P<file>res://[^:)]+):(?P<line>\d+)\)")


def prepared_variants(source: str) -> dict[str, str]:
    return {name: changed_source(source, *patch) for name, patch in MUTATIONS.items()}


def verdict_of(stdout: str, stderr: str, returncode: int) -> tuple[str, dict, str]:
    """Strict: pass / killed, or invalid with its reason. A script error is never a kill."""
    try:
        verdict, payload = classify(stdout, stderr, returncode, PREFIX)
    except (RuntimeError, ValueError) as exc:
        return "invalid", {}, str(exc)
    return verdict, payload, ""


def _report(stdout: str, prefix: str) -> dict | None:
    lines = [line for line in stdout.splitlines() if line.startswith(prefix + " {")]
    if not lines:
        return None
    try:
        return json.loads(lines[-1].split(" ", 1)[1])
    except ValueError:
        return None


def reproduction_verdict(stdout: str, stderr: str, returncode: int) -> tuple[str, dict, str]:
    """reproduced only if the pre-fix owner ran cleanly and accepted and wrote the forged state."""
    text = stdout + "\n" + stderr
    payload = _report(stdout, REPRODUCTION_PREFIX)
    if payload is None or "Parse Error" in text or "SCRIPT ERROR" in text or returncode != 0:
        return "invalid", {}, "reproduction did not run cleanly"
    wrote = (payload.get("completed") is True and payload.get("initialize_valid") is True
             and payload.get("commit_valid") is True and payload.get("restore_forged_valid") is True
             and payload.get("budget_before") == 900.0 and payload.get("budget_after") == 5000.0
             and payload.get("liquid_after") == 0.25)
    return ("reproduced", payload, "") if wrote else ("not_reproduced", payload, "the forged state was not written")


def abort_control_verdict(stdout: str, stderr: str, returncode: int, abort_line: int) -> tuple[str, dict, str]:
    """pass only if the control passed AND its only script errors are the provoked ones."""
    text = stdout + "\n" + stderr
    payload = _report(stdout, ABORT_PREFIX)
    if payload is None or "Parse Error" in text:
        return "invalid", {}, "abort control report absent or parse error"
    if returncode != 0 or payload.get("failures") or ABORT_PREFIX + "_PASS" not in stdout:
        return "failed", payload, f"exit {returncode}, failures {payload.get('failures')}"
    errors = [match.groupdict() for match in ERROR_BLOCK.finditer(text)]
    expected = "res://" + ABORT_FIXTURE.relative_to(ROOT).as_posix()
    if text.count("SCRIPT ERROR") != len(errors):
        return "invalid", payload, "script error that could not be located"
    foreign = [e for e in errors if e["file"] != expected or int(e["line"]) != abort_line
               or not e["message"].startswith("Invalid operands")]
    if foreign:
        return "invalid", payload, f"script error that the control did not provoke: {foreign[:2]}"
    if not errors or len(errors) != payload.get("provoked_aborts"):
        return "invalid", payload, f"{len(errors)} script errors for {payload.get('provoked_aborts')} provoked aborts"
    return "pass", payload, f"{len(errors)} provoked aborts, all on the marked line"


def _abort_line() -> int:
    lines = ABORT_FIXTURE.read_text(encoding="utf-8").splitlines()
    marked = [index + 1 for index, line in enumerate(lines) if ABORT_MARK in line]
    if len(marked) != 1:
        raise RuntimeError("the abort control must mark exactly one abort line")
    return marked[0]


def _launch(godot, project: Path, files: dict[str, bytes], script: str):
    for rel, raw in files.items():
        target = project / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Isolated positive verdict"\n', encoding="utf-8")
    run = godot_monitored_launch.run([godot, "--headless", "--path", project, "--script", project / script],
                                     timeout_s=180, environment=os.environ.copy())
    for filename, content in [("health.json", json.dumps(run.health, indent=2)),
                              ("stdout.log", run.stdout), ("stderr.log", run.stderr)]:
        (project / filename).write_text(content, encoding="utf-8")
    return run


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--reproduce", action="store_true")
    parser.add_argument("--abort-control", action="store_true")
    args = parser.parse_args()
    paths = [MODEL, FIXTURE, ABORT_FIXTURE, *DEPENDENCIES]
    originals = {path: path.read_bytes() for path in paths}
    source = originals[MODEL].decode("utf-8")
    variants = prepared_variants(source)
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / ("g3_positive_verdict_mutations_" +
                               datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    base = {path.relative_to(ROOT).as_posix(): raw for path, raw in originals.items() if path != ABORT_FIXTURE}
    model_rel, fixture_rel = MODEL.relative_to(ROOT).as_posix(), FIXTURE.relative_to(ROOT).as_posix()
    results = []
    extra: dict[str, str | None] = {"reproduction": None, "abort_control": None}

    def record(name: str, run, verdict: str, payload: dict, reason: str, expected: str) -> None:
        results.append({"name": name, "verdict": verdict, "expected": expected, "reason": reason,
                        "checks": payload.get("checks"), "failures": payload.get("failures", []),
                        "report": payload if name in ("reproduction_before_fix", "abort_control") else None,
                        "script_errors": (run.stdout + run.stderr).count("SCRIPT ERROR")})
        print(json.dumps({"name": name, "verdict": verdict, "reason": reason,
                          "failures": len(payload.get("failures", []) or [])}), flush=True)

    try:
        for name, candidate in {"control": source, **variants}.items():
            run = _launch(godot, evidence / name, {**base, model_rel: candidate.encode("utf-8")}, fixture_rel)
            if not run.launched:
                raise RuntimeError(f"{name}: not launched: {run.faults or run.preexisting}")
            if run.faults or run.preexisting:
                verdict, payload, reason = "invalid", {}, f"monitor: {run.faults or run.preexisting}"
            else:
                verdict, payload, reason = verdict_of(run.stdout, run.stderr, run.returncode)
            record(name, run, verdict, payload, reason, "pass" if name == "control" else "killed")
            if name == "control" and verdict != "pass":
                raise RuntimeError("control is not green; no mutant verdict is meaningful")
        if args.reproduce:
            files = {}
            for path in [MODEL, *DEPENDENCIES]:
                rel = path.relative_to(ROOT).as_posix()
                files[rel] = subprocess.run(["git", "-C", str(ROOT), "show", f"{PREFIX_COMMIT}:{rel}"],
                                            capture_output=True, check=True).stdout
            script = "tests/fixtures/g3_positive_verdict_reproduction.gd"
            files[script] = REPRODUCTION_FIXTURE.encode("utf-8")
            run = _launch(godot, evidence / "reproduction_before_fix", files, script)
            verdict, payload, reason = (("invalid", {}, f"monitor: {run.faults or run.preexisting}")
                                        if not run.launched or run.faults or run.preexisting
                                        else reproduction_verdict(run.stdout, run.stderr, run.returncode))
            extra["reproduction"] = verdict
            record("reproduction_before_fix", run, verdict, payload, reason, "reproduced")
        if args.abort_control:
            script = ABORT_FIXTURE.relative_to(ROOT).as_posix()
            run = _launch(godot, evidence / "abort_control", {**base, script: originals[ABORT_FIXTURE]}, script)
            verdict, payload, reason = (("invalid", {}, f"monitor: {run.faults or run.preexisting}")
                                        if not run.launched or run.faults or run.preexisting
                                        else abort_control_verdict(run.stdout, run.stderr, run.returncode, _abort_line()))
            extra["abort_control"] = verdict
            record("abort_control", run, verdict, payload, reason, "pass")
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        mutants = [item for item in results if item["name"].startswith("V")]
        summary = {
            "results": results, "originals_intact": intact,
            "control": next((item["verdict"] for item in results if item["name"] == "control"), None),
            **extra, "declared": len(variants), "executed": len(mutants),
            "killed": sum(item["verdict"] == "killed" for item in mutants),
            "survivors": [item["name"] for item in mutants if item["verdict"] == "pass"],
            "invalid": [item["name"] for item in mutants if item["verdict"] == "invalid"],
            "original_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for path, raw in originals.items()},
        }
        (evidence / "results.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps({key: summary[key] for key in ["control", "reproduction", "abort_control", "declared",
                                                        "executed", "killed", "survivors", "invalid",
                                                        "originals_intact"]}), flush=True)
        if not intact:
            raise RuntimeError("working sources changed")
    green = summary["killed"] == summary["declared"] == summary["executed"]
    green = green and (not args.reproduce or extra["reproduction"] == "reproduced")
    green = green and (not args.abort_control or extra["abort_control"] == "pass")
    return 0 if green else 1


if __name__ == "__main__":
    raise SystemExit(main())
