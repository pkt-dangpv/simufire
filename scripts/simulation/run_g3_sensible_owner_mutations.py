"""Isolated mutants of the sensible atomic owner; working sources never edited.

Every control/mutant runs the real GDScript fixture in its own project copy,
through the safe monitor, with at least 6 GiB available. Only a behavioral
fixture failure with exit 1 is a kill. A parse error, a script error, a missing
resource, a timeout or a monitor fault is recorded as invalid, never as a kill.
The campaign continues after a survivor so each one can be reviewed, and fails.
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
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source, classify  # noqa: E402

MODEL = ROOT / "sim/fire/PrescribedSensiblePhaseController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_sensible_phase_controller.gd"
# The ledger preloads the real adapter since the composition phase (2026-10-06).
DEPENDENCIES = [ROOT / "sim/fire/FuelMassBudgetModel.gd", ROOT / "sim/fire/PrescribedFuelReleaseModel.gd",
                ROOT / "sim/fire/SensibleEnthalpyModel.gd", ROOT / "sim/fire/HeptaneRealCpProfiles.gd"]
PREFIX = "G3_SENSIBLE_PHASE_CONTROLLER"
# Anchors re-pointed on 2026-10-06: the owner reads its names and its ledger entry
# through `_label` and `_ledger`. Each mutant injects the same defect as before.
_FINGERPRINT = "return (_label(\"version\") + _serialize(context)).sha256_text()"
_SEED_AUDIT = ("var checked: Dictionary = _ledger("
               "_seed_phase(canonical), _idle(), canonical[\"material\"])")
# A structurally complete aggregate written BEFORE the ledger validates the seed.
_EARLY_WRITE = ("_context = canonical\n\t_owned = {\"schema\": SNAPSHOT_SCHEMA, "
                "\"context_fingerprint\": _fingerprint(canonical), \"generation\": 0, "
                "\"physical_time_s\": 0.0, \"progress\": initialized[\"candidate\"].duplicate(true), "
                "\"phase\": _seed_phase(canonical), \"totals\": {}}\n\t")
_NUMBER_GUARD = "if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:\n\t\terrors.append(label + \" must be a finite number"


def _unbound(member: str) -> str:
    return ("var reduced: Dictionary = context.duplicate(true)\n\t" + member +
            "\n\treturn (VERSION + _serialize(reduced)).sha256_text()")


MUTATIONS = {
    "O01_restore_drops_sensible_history": (
        "var candidate: Dictionary = saved.duplicate(true)",
        "var candidate: Dictionary = saved.duplicate(true)\n\tcandidate[\"phase\"][\"liquid_sensible_kj\"] = 0.0"
        "\n\tcandidate[\"phase\"][\"vapour_sensible_kj\"] = 0.0"),
    "O02_only_progress_committed": (
        "_owned = proposal[\"candidate\"].duplicate(true)",
        "_owned[\"progress\"] = proposal[\"candidate\"][\"progress\"].duplicate(true)"),
    "O03_only_phase_committed": (
        "_owned = proposal[\"candidate\"].duplicate(true)",
        "_owned[\"phase\"] = proposal[\"candidate\"][\"phase\"].duplicate(true)"),
    "O04_ack_requested_not_accepted": (
        "source_end, ledger[\"accepted_release_kg\"])", "source_end, demand[\"release_kg\"])"),
    "O05_ignore_generation_identity": ("and value == _owned[\"generation\"]", "and true"),
    "O06_restore_saved_generation": (
        "candidate[\"generation\"] = int(_owned[\"generation\"]) + 1\n",
        "candidate[\"generation\"] = int(saved[\"generation\"])\n"),
    "O07_restore_generation_overflow": (
        "if int(_owned[\"generation\"]) == MAX_GENERATION:", "if false:"),
    "O08_profiles_not_bound": (_FINGERPRINT, _unbound(
        "reduced[\"material\"].erase(\"liquid_profile\")\n\treduced[\"material\"].erase(\"vapour_profile\")")),
    "O09_reference_material_not_bound": (
        _FINGERPRINT, _unbound("reduced[\"material\"].erase(\"reference_material\")")),
    "O10_seed_not_bound": (_FINGERPRINT, _unbound("reduced.erase(\"seed\")")),
    "O11_attribution_not_bound": (_FINGERPRINT, _unbound("reduced.erase(\"attribution\")")),
    "O12_program_not_bound": (_FINGERPRINT, _unbound("reduced.erase(\"program\")")),
    "O13_keys_not_sorted": ("keys.sort()", "pass"),
    "O14_numbers_not_canonical": (
        "var canonical: Dictionary = _canonical(c)", "var canonical: Dictionary = c.duplicate(true)"),
    "O15_decimal_text_instead_of_bits": (
        "return \"f64:\" + PackedFloat64Array([number]).to_byte_array().hex_encode()",
        "return \"f64:\" + str(number)"),
    "O16_snapshot_context_identity_unchecked": (
        "_literal(s.get(\"context_fingerprint\"), _fingerprint(context), \"snapshot/context identity\", errors)",
        "pass"),
    "O17_heating_counted_twice": (
        "\"heating_liquid_kj\": heated_liquid, \"heating_vapour_kj\": heated_vapour,",
        "\"heating_liquid_kj\": 2.0 * heated_liquid, \"heating_vapour_kj\": heated_vapour,"),
    "O18_heating_not_passed_to_ledger": (
        "\"heat_liquid_kj\": heat_liquid, \"heat_vapour_kj\": heat_vapour,",
        "\"heat_liquid_kj\": 0.0, \"heat_vapour_kj\": heat_vapour,"),
    "O19_borrow_deposited_heat": (
        "var before: Dictionary = _owned[\"phase\"].duplicate(true)",
        "var before: Dictionary = _owned[\"phase\"].duplicate(true)"
        "\n\tbefore[\"thermal_budget_kj\"] += maxf(0.0, float(before[\"deposited_heat_kj\"]))"),
    "O20_reemit_rejected_prefix": (
        "\"dt_s\": physical_dt, \"release_kg\": demand[\"release_kg\"], \"oxidation_kg\": oxidation,",
        "\"dt_s\": physical_dt, \"release_kg\": demand[\"release_kg\"] + float(_owned[\"progress\"][\"rejected_kg\"]),"
        " \"oxidation_kg\": oxidation,"),
    "O21_source_dt_as_physical_dt": ("\"dt_s\": physical_dt, ", "\"dt_s\": demand[\"dt_s\"], "),
    "O22_no_oxidation_after_source_end": (
        "\"oxidation_kg\": oxidation,", "\"oxidation_kg\": 0.0 if demand[\"dt_s\"] == 0.0 else oxidation,"),
    "O23_source_extrapolation": (
        "var source_end: float = minf(end, _domain_end(_context))", "var source_end: float = end"),
    "O24_snapshot_alias": ("return _owned.duplicate(true)", "return _owned"),
    "O25_approve_product": (
        "\"engine_integration\": false, \"production_activation\": false,",
        "\"engine_integration\": false, \"production_activation\": true,"),
    "O26_thermal_identities_omitted": (
        "# Thermal history is owned, not derived: sums against the seed, per account.",
        "return audit # mutant: thermal identities omitted"),
    "O27_generation_advances_at_zero_dt": ("+ (1 if physical_dt > 0.0 else 0)", "+ 1"),
    "O28_emission_temperature_ignored": (
        "\"emitted_vapour_temperature_k\": emitted_k,",
        "\"emitted_vapour_temperature_k\": Budget.SensibleProperties.REFERENCE_K,"),
    "O29_external_candidate_written": (
        "func commit_step(request: Variant, expected_generation: Variant) -> Dictionary:\n",
        "func commit_step(request: Variant, expected_generation: Variant) -> Dictionary:\n"
        "\tif typeof(request) == TYPE_DICTIONARY and typeof(request.get(\"phase\")) == TYPE_DICTIONARY"
        " and not _owned.is_empty():\n\t\t_owned[\"phase\"] = request[\"phase\"].duplicate(true)\n"),
    "O30_modeled_component_unbound": (
        "if a[\"modeled_component_id\"] != material[\"component_id\"]:", "if false:"),
    "O31_oxidized_sensible_not_accumulated": (
        "\"emitted_vapour_sensible_kj\", \"oxidized_sensible_kj\", \"chemical_oxidation_heat_kj\"]:",
        "\"emitted_vapour_sensible_kj\", \"chemical_oxidation_heat_kj\"]:"),
    "O32_initialization_not_atomic": (
        _SEED_AUDIT, _EARLY_WRITE + _SEED_AUDIT),
    "O33_clock_agreement_omitted": (
        "if float(progress[\"time_s\"]) != minf(physical_time, _domain_end(context)):", "if false:"),
    "O34_seed_sensible_ignored": (
        "\"liquid_sensible_kj\": float(context[\"seed\"][\"initial_liquid_sensible_kj\"]), \"vapour_sensible_kj\": 0.0}",
        "\"liquid_sensible_kj\": 0.0, \"vapour_sensible_kj\": 0.0}"),
    "O35_phase_initial_mass_unchecked": ("if float(phase[\"initial_fuel_mass_kg\"]) != mass:", "if false:"),
    "O36_product_recomposition_omitted": (
        "_compare(t[\"co2_kg\"], chemistry[\"products_kg\"][\"co2\"], false, \"cumulative CO2\", errors)", "pass"),
    "O37_request_schema_unchecked": (
        "_literal(r.get(\"schema\"), _label(\"request\"), \"request schema\", errors)", "pass"),
    "O38_seed_schema_unchecked": (
        "_literal(seed.get(\"schema\"), _label(\"seed\"), \"seed schema\", errors)", "pass"),
    "O39_snapshot_schema_unchecked": (
        "_literal(s.get(\"schema\"), _label(\"snapshot\"), \"snapshot schema\", errors)", "pass"),
    "O40_bool_admitted_as_number": (
        _NUMBER_GUARD, _NUMBER_GUARD.replace("[TYPE_INT, TYPE_FLOAT]", "[TYPE_INT, TYPE_FLOAT, TYPE_BOOL]")),
}


def prepared_variants(source: str) -> dict[str, str]:
    return {name: changed_source(source, *patch) for name, patch in MUTATIONS.items()}


def verdict_of(stdout: str, stderr: str, returncode: int) -> tuple[str, dict, str]:
    """pass / killed, or invalid with the reason. Never promotes a fault to a kill."""
    try:
        verdict, payload = classify(stdout, stderr, returncode, PREFIX)
    except (RuntimeError, ValueError) as exc:
        return "invalid", {}, str(exc)
    return verdict, payload, ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--only", action="append", default=[], help="run the control and these mutants")
    args = parser.parse_args()
    paths = [MODEL, FIXTURE, *DEPENDENCIES]
    originals = {path: path.read_bytes() for path in paths}
    source = originals[MODEL].decode("utf-8")
    variants = prepared_variants(source)
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    unknown = [name for name in args.only if name not in variants]
    if unknown:
        raise ValueError(f"unknown mutants: {unknown}")
    if args.only:
        variants = {name: variants[name] for name in args.only}
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / ("g3_sensible_owner_mutations_" +
                               datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
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
                'config_version=5\n[application]\nconfig/name="Isolated sensible owner"\n', encoding="utf-8")
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
                verdict, payload, reason = verdict_of(run.stdout, run.stderr, run.returncode)
            expected = "pass" if name == "control" else "killed"
            results.append({"name": name, "verdict": verdict, "expected": expected, "reason": reason,
                            "checks": payload.get("checks"), "failures": payload.get("failures", []),
                            "source_sha256": hashlib.sha256(candidate.encode("utf-8")).hexdigest()})
            print(json.dumps({"name": name, "verdict": verdict, "reason": reason,
                              "failures": len(payload.get("failures", []))}), flush=True)
            if name == "control" and verdict != "pass":
                raise RuntimeError("control is not green; no mutant verdict is meaningful")
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        mutants = [item for item in results if item["name"] != "control"]
        summary = {
            "results": results, "originals_intact": intact,
            "control": next((item["verdict"] for item in results if item["name"] == "control"), None),
            "declared": len(variants), "executed": len(mutants),
            "killed": sum(item["verdict"] == "killed" for item in mutants),
            "survivors": [item["name"] for item in mutants if item["verdict"] == "pass"],
            "invalid": [item["name"] for item in mutants if item["verdict"] == "invalid"],
            "original_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for path, raw in originals.items()},
        }
        (evidence / "results.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps({key: summary[key] for key in ["control", "declared", "executed", "killed",
                                                        "survivors", "invalid", "originals_intact"]}), flush=True)
        if not intact:
            raise RuntimeError("working sources changed")
    return 0 if summary["killed"] == summary["declared"] == summary["executed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
