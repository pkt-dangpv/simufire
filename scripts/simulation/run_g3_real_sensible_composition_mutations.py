"""Predeclared GDScript mutations of the real sensible composition, run in Godot.

Each variant is written to an isolated copy of the six scripts the composition
loads and of its fixture; the working sources are never edited. Four families:
L the shared ledger core, B the inherited owner, C the composition owner, and
F controls that move a number of the oracle block to show the fixture reads it.
A kill is a fixture that ran to the end and reported failed checks. A parse
error, a script error, a timeout or a monitor fault is recorded as invalid,
never as a kill. The campaign goes on after a survivor so each can be
reviewed, and fails unless every declared mutant is killed.
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
from scripts.simulation import build_g3_real_sensible_composition as build  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify  # noqa: E402

FIRE = ROOT / "sim/fire"
LEDGER = FIRE / "FuelMassBudgetModel.gd"
BASE = FIRE / "PrescribedSensiblePhaseController.gd"
OWNER = FIRE / "PrescribedRealSensiblePhaseController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_real_sensible_composition.gd"
TARGETS = [LEDGER, BASE, OWNER, FIXTURE]
ASSETS = [LEDGER, BASE, OWNER, FIRE / "PrescribedFuelReleaseModel.gd", FIRE / "SensibleEnthalpyModel.gd",
          FIRE / "HeptaneRealCpProfiles.gd", FIXTURE]
PREFIX = "G3_REAL_SENSIBLE_COMPOSITION"
_FINGERPRINT = 'return (_label("version") + _serialize(context)).sha256_text()'
_GATE = "func _admits(value: Variant, context: Dictionary, errors: Array[String]) -> bool:\n\tvar reported"
_EVIDENCE = 'proposal["step"]["emitted_vapour_evidence"] = {'
_RESTORED = ('var candidate: Dictionary = saved.duplicate(true)\n'
             '\tcandidate["generation"] = int(_owned["generation"]) + 1')
_PREVIEWED = 'return {"valid": true, "errors": [], "candidate": candidate, "step": step, "report": _report()}'
_EMISSION = ('var emission: Dictionary = properties.evaluate(profiles["vapour_profile"], '
             'n["emitted_vapour_temperature_k"])')


def _unbound(member: str) -> str:
    return ("var reduced: Dictionary = context.duplicate(true)\n\t" + member +
            '\n\treturn (_label("version") + _serialize(reduced)).sha256_text()')


# name: (file, old, new)
MUTATIONS = {
    # --- L: the shared ledger core, judged with the real contract ------------------
    "L01_support_ignored": (LEDGER, "or sensible < lower or sensible > upper:", "or false:"),
    "L02_real_contract_reads_the_synthetic_provider": (
        LEDGER, 'var properties: GDScript = RealProperties if contract["real_properties"] else SensibleProperties',
        "var properties: GDScript = SensibleProperties"),
    "L03_synthetic_contract_reads_the_real_provider": (
        LEDGER, 'var properties: GDScript = RealProperties if contract["real_properties"] else SensibleProperties',
        "var properties: GDScript = RealProperties"),
    "L04_emission_clipped_into_the_support": (
        LEDGER, _EMISSION,
        'var emission: Dictionary = properties.evaluate(profiles["vapour_profile"], clampf('
        'n["emitted_vapour_temperature_k"], profiles["vapour_profile"]["samples"][0]["temperature_k"], '
        'profiles["vapour_profile"]["samples"][-1]["temperature_k"]))'),
    "L05_release_ignores_sensible": (
        LEDGER, "cost_per_kg = latent + emitted_specific - sl_specific", "cost_per_kg = latent"),
    "L06_mixing_drops_the_emitted_sensible": (
        LEDGER, "var mixed_sensible: float = heated_sv + transferred * emitted_specific",
        "var mixed_sensible: float = heated_sv"),
    "L07_mixing_averages_instead_of_adding_enthalpy": (
        LEDGER, "var mixed_specific: float = mixed_sensible / mixed_mass if mixed_mass > 0.0 else 0.0",
        "var mixed_specific: float = (heated_sv / vapour + emitted_specific) * 0.5 if vapour > 0.0 "
        "else emitted_specific"),
    "L08_oxidation_delivers_no_sensible": (
        LEDGER, "var deposited_increment: float = chemical_heat + oxidized_sensible",
        "var deposited_increment: float = chemical_heat"),
    "L09_oxidized_vapour_keeps_its_sensible": (
        LEDGER, "var oxidized_sensible: float = oxidized * mixed_specific", "var oxidized_sensible: float = 0.0"),
    "L10_Q_finances_the_release": (
        LEDGER, '"thermal_budgeted", available_budget, cost_per_kg)',
        '"thermal_budgeted", available_budget + maxf(0.0, float(n["deposited_heat_kj"])), cost_per_kg)'),
    "L11_Q_added_to_B": (
        LEDGER, 'var budget: float = n["thermal_budget_kj"]',
        'var budget: float = n["thermal_budget_kj"] + maxf(0.0, float(n["deposited_heat_kj"]))'),
    "L12_heating_that_does_not_fit_is_dropped": (
        LEDGER, 'if not _finite(heating) or heating > budget:\n\t\treturn _sensible_rejected(contract, '
                '["prescribed heating exceeds independent B or overflows"])',
        "if not _finite(heating) or heating > budget:\n\t\theat_l = 0.0\n\t\theat_v = 0.0\n\t\theating = 0.0"),
    "L13_oxidation_before_release": (
        LEDGER, "minf(oxidation_requested, minf(released + transferred, oxygen / oxygen_per_kg))",
        "minf(oxidation_requested, minf(released, oxygen / oxygen_per_kg))"),
    "L14_zero_step_heats": (
        LEDGER, 'var heat_l: float = n["heat_liquid_kj"] if n["dt_s"] > 0.0 else 0.0',
        'var heat_l: float = n["heat_liquid_kj"]'),
    "L15_signed_delivery_clamped": (
        LEDGER, "var deposited_increment: float = chemical_heat + oxidized_sensible",
        "var deposited_increment: float = chemical_heat + maxf(0.0, oxidized_sensible)"),
    "L16_negative_liquid_enthalpy_clamped": (
        LEDGER, "var sl_specific: float = heated_sl / liquid if liquid > 0.0 else 0.0",
        "var sl_specific: float = maxf(0.0, heated_sl / liquid) if liquid > 0.0 else 0.0"),
    "L17_new_loss_of_vapour_sensible": (
        LEDGER, '"vapour_sensible_kj": (mixed_mass - oxidized) * mixed_specific}',
        '"vapour_sensible_kj": (mixed_mass - oxidized) * mixed_specific * 0.99}'),
    "L18_profile_component_not_bound": (
        LEDGER, '_sensible_literal(profiles[key], "component_id", m["component_id"], errors)',
        "pass # mutant: profile binding omitted"),
    "L19_profile_phase_not_bound": (
        LEDGER, '_sensible_literal(profiles[key], "phase", "liquid" if key == "liquid_profile" else "gas", errors)',
        "pass # mutant: phase binding omitted"),
    "L20_state_schema_unchecked": (
        LEDGER, '_sensible_literal(s, "schema", contract["state_schema"], errors)', "pass # mutant"),
    "L21_material_schema_unchecked": (
        LEDGER, '_sensible_literal(m, "schema", contract["material_schema"], errors)', "pass # mutant"),
    "L22_real_scope_relabelled": (
        LEDGER, '"scope": "real_limited_properties_declared_chemistry_synthetic_budget_not_fire_validation",',
        '"scope": "validated_real_heptane_fire",'),
    "L23_integration_enabled": (
        LEDGER, '"physical_approval": false, "integration_enabled": false, "product_activation": false,\n'
                '\t\t"accepted_release_kg"',
        '"physical_approval": false, "integration_enabled": true, "product_activation": false,\n'
        '\t\t"accepted_release_kg"'),
    "L24_absent_phase_keeps_sensible": (LEDGER, "if sensible != 0.0:", "if false:"),
    # --- B: the inherited owner, judged through the composition --------------------
    "B01_initialize_ignores_the_gate": (
        BASE, "\tif not _admits(candidate, canonical, errors):\n\t\treturn _failure(errors)\n",
        "\t_admits(candidate, canonical, errors)\n\tif not errors.is_empty():\n\t\treturn _failure(errors)\n"),
    "B02_preview_ignores_the_gate_of_the_confirmed_state": (
        BASE, "if not current or not errors.is_empty():", "if not errors.is_empty():"),
    "B03_preview_ignores_the_gate_of_the_candidate": (
        BASE, "\tif not _admits(candidate, _context, errors):\n\t\treturn _failure(errors)\n",
        "\t_admits(candidate, _context, errors)\n\tif not errors.is_empty():\n\t\treturn _failure(errors)\n"),
    "B04_restore_ignores_the_gate_of_the_confirmed_state": (
        BASE, "if not current or not requested:", "if not requested:"),
    # Narrow on purpose: with no check at all a malformed snapshot is written and the
    # owner aborts, which is an invalid run. This is the old rule, absence of errors.
    "B05_restore_decides_on_the_saved_state_by_absence_of_errors": (
        BASE, "if not current or not requested:", "if not current or not errors.is_empty():"),
    "B06_restore_drops_the_sensible_history": (
        BASE, "var candidate: Dictionary = saved.duplicate(true)",
        'var candidate: Dictionary = saved.duplicate(true)\n\tcandidate["phase"]["liquid_sensible_kj"] = 0.0'
        '\n\tcandidate["phase"]["vapour_sensible_kj"] = 0.0'),
    "B07_restore_rebuilds_the_history_from_mass": (
        BASE, _RESTORED,
        'var candidate: Dictionary = saved.duplicate(true)\n'
        '\tif candidate["phase"]["liquid_fuel_kg"] == _owned["phase"]["liquid_fuel_kg"]:\n'
        '\t\tcandidate["phase"] = _owned["phase"].duplicate(true)\n'
        '\t\tcandidate["totals"] = _owned["totals"].duplicate(true)\n'
        '\tcandidate["generation"] = int(_owned["generation"]) + 1'),
    "B08_only_the_phase_is_committed": (
        BASE, '_owned = proposal["candidate"].duplicate(true)',
        '_owned["phase"] = proposal["candidate"]["phase"].duplicate(true)'),
    "B09_thermal_identities_omitted": (
        BASE, "# Thermal history is owned, not derived: sums against the seed, per account.",
        "return audit # mutant: thermal identities omitted"),
    "B10_preview_writes": (BASE, _PREVIEWED, "_owned = candidate.duplicate(true)\n\t" + _PREVIEWED),
    "B11_snapshot_alias": (BASE, "return _owned.duplicate(true)", "return _owned"),
    "B12_context_not_copied": (
        BASE, "var canonical: Dictionary = _canonical(c)", "var canonical: Dictionary = c"),
    "B13_profiles_not_bound": (BASE, _FINGERPRINT, _unbound(
        'reduced["material"].erase("liquid_profile")\n\treduced["material"].erase("vapour_profile")')),
    "B14_seed_not_bound": (BASE, _FINGERPRINT, _unbound('reduced.erase("seed")')),
    "B15_program_not_bound": (BASE, _FINGERPRINT, _unbound('reduced.erase("program")')),
    "B16_reference_material_not_bound": (
        BASE, _FINGERPRINT, _unbound('reduced["material"].erase("reference_material")')),
    "B17_attribution_not_bound": (BASE, _FINGERPRINT, _unbound('reduced.erase("attribution")')),
    "B18_snapshot_identity_unchecked": (
        BASE, '_literal(s.get("context_fingerprint"), _fingerprint(context), "snapshot/context identity", errors)',
        "pass"),
    "B19_bool_not_serialised": (BASE, 'return "true" if value else "false"', 'return "bool"'),
    "B20_null_serialised_as_zero": (
        BASE, 'TYPE_NIL:\n\t\t\treturn "null"', 'TYPE_NIL:\n\t\t\treturn "f64:0000000000000000"'),
    "B21_decimal_text_instead_of_bits": (
        BASE, 'return "f64:" + PackedFloat64Array([number]).to_byte_array().hex_encode()',
        'return "f64:" + str(number)'),
    "B22_budget_kind_unchecked": (
        BASE, '_literal(seed.get("energy_boundary_kind"), BOUNDARY_KIND, "initial energy boundary", errors)', "pass"),
    "B23_declared_emission_unchecked": (
        BASE, 'if a["rule"] != "same_declared_component" or a["status"] != "synthetic_declared_emission" '
              'or a["modeled_component_id"] != a["input_component_id"]:', "if false:"),
    "B24_report_relabels_the_budget": (
        BASE, 'result["energy_boundary_kind"] = _context["seed"]["energy_boundary_kind"]',
        'result["energy_boundary_kind"] = "measured_independent_budget"'),
    "B25_predictive_evaporation_approved": (
        BASE, '"scientific_approval": false, "predictive_evaporation_approval": false,',
        '"scientific_approval": false, "predictive_evaporation_approval": true,'),
    "B26_product_activated": (
        BASE, '"engine_integration": false, "production_activation": false,',
        '"engine_integration": true, "production_activation": true,'),
    "B27_source_extrapolation": (
        BASE, "var source_end: float = minf(end, _domain_end(_context))", "var source_end: float = end"),
    "B28_generation_advances_at_zero_dt": (BASE, "+ (1 if physical_dt > 0.0 else 0)", "+ 1"),
    "B29_acknowledges_requested_not_accepted": (
        BASE, 'source_end, ledger["accepted_release_kg"])', 'source_end, demand["release_kg"])'),
    "B30_heating_not_passed_to_the_ledger": (
        BASE, '"heat_liquid_kj": heat_liquid, "heat_vapour_kj": heat_vapour,',
        '"heat_liquid_kj": 0.0, "heat_vapour_kj": heat_vapour,'),
    "B31_borrows_deposited_heat": (
        BASE, 'var before: Dictionary = _owned["phase"].duplicate(true)',
        'var before: Dictionary = _owned["phase"].duplicate(true)'
        '\n\tbefore["thermal_budget_kj"] += maxf(0.0, float(before["deposited_heat_kj"]))'),
    "B32_emission_temperature_ignored": (
        BASE, '"emitted_vapour_temperature_k": emitted_k,',
        '"emitted_vapour_temperature_k": Budget.SensibleProperties.REFERENCE_K,'),
    "B33_source_dt_as_physical_dt": (BASE, '"dt_s": physical_dt, ', '"dt_s": demand["dt_s"], '),
    "B34_clock_agreement_omitted": (
        BASE, 'if float(progress["time_s"]) != minf(physical_time, _domain_end(context)):', "if false:"),
    "B35_request_schema_unchecked": (
        BASE, '_literal(r.get("schema"), _label("request"), "request schema", errors)', "pass"),
    "B36_seed_schema_unchecked": (
        BASE, '_literal(seed.get("schema"), _label("seed"), "seed schema", errors)', "pass"),
    "B37_snapshot_schema_unchecked": (
        BASE, '_literal(s.get("schema"), _label("snapshot"), "snapshot schema", errors)', "pass"),
    "B38_context_schema_unchecked": (
        BASE, '_literal(c.get("schema"), _label("context"), "context schema", errors)', "pass"),
    "B39_oxidized_sensible_not_accumulated": (
        BASE, '"emitted_vapour_sensible_kj", "oxidized_sensible_kj", "chemical_oxidation_heat_kj"]:',
        '"emitted_vapour_sensible_kj", "chemical_oxidation_heat_kj"]:'),
    # --- C: the composition owner ---------------------------------------------------
    "C01_positive_verdict_not_required": (
        OWNER, "if errors.size() == reported and _positive(audit):", "if errors.size() == reported:"),
    "C02_truthy_verdict_accepted": (
        OWNER, 'return (typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL\n'
               '\t\tand result["valid"])',
        'return (typeof(result) == TYPE_DICTIONARY and result.get("valid") != null\n'
        '\t\tand str(result["valid"]) in ["true", "1"])'),
    "C03_gate_override_removed": (OWNER, _GATE, _GATE.replace("func _admits(", "func _admits_unused(")),
    "C04_unconfirmed_preview_reaches_the_write": (
        OWNER, 'return (_positive(proposal) and typeof(proposal.get("candidate")) == TYPE_DICTIONARY',
        'return (typeof(proposal.get("candidate")) == TYPE_DICTIONARY'),
    "C05_commit_hands_back_an_unconfirmed_preview": (
        OWNER, ' or (result["valid"] and typeof(result.get("no_op")) != TYPE_BOOL):', ":"),
    "C06_composition_calls_the_synthetic_entry": (
        OWNER, "return Budget.propose_phase_sensible_real(state, request, material)",
        "return Budget.propose_phase_sensible(state, request, material)"),
    "C07_phase_state_keeps_the_synthetic_name": (
        OWNER, '"phase": "g3_phase_real_sensible_state_v1",', '"phase": "g3_phase_sensible_state_v1",'),
    "C08_context_keeps_the_synthetic_name": (
        OWNER, '"context": "g3_prescribed_real_sensible_context_v1",',
        '"context": "g3_prescribed_sensible_context_v1",'),
    "C09_identity_keeps_the_synthetic_version": (
        OWNER, '"version": "prescribed_real_sensible_phase_controller_v1",',
        '"version": "prescribed_sensible_phase_controller_v1",'),
    "C10_emission_evidence_dropped": (
        OWNER, '"evidence_tiers": emitted["candidate"]["evidence_tiers"],', '"evidence_tiers": [],'),
    "C11_every_evidence_class_claimed": (
        OWNER, "if minf(last, high) - maxf(first, low) > 0.0 or (low == high and first <= low and low <= last):",
        "if true:"),
    "C12_declared_errors_dropped": (
        OWNER, 'evidence["declared_errors"] = profile["declared_errors"].duplicate(true)',
        'evidence["declared_errors"] = {}'),
    "C13_budget_relabelled_as_measured": (
        OWNER, '"thermal_budget": BOUNDARY_KIND,', '"thermal_budget": "measured_heat_flux",'),
    "C14_chemistry_relabelled_as_calibration": (
        OWNER, '"chemistry_and_latent_heat": "declared_prototype_reference_nominal_CHO_not_heptane_calibration",',
        '"chemistry_and_latent_heat": "real_heptane_calibration",'),
    "C15_release_relabelled_as_predicted": (
        OWNER, '"release_program": "prescribed_input_not_predicted_evaporation",',
        '"release_program": "predicted_evaporation",'),
    "C16_properties_relabelled_as_validated": (
        OWNER, '"property_evidence": "real_limited_primary_source_property",',
        '"property_evidence": "validated_fire_property",'),
    "C17_mass_bases_declared_reconciled": (
        OWNER, '"mass_bases_reconciled": false,', '"mass_bases_reconciled": true,'),
    "C18_total_uncertainty_claimed": (
        OWNER, '"total_uncertainty_quantified": false,', '"total_uncertainty_quantified": true,'),
    "C19_temperature_declared_inferred": (
        OWNER, '"temperature_inferred": false,', '"temperature_inferred": true,'),
    "C20_co_fed_approved": (OWNER, 'result["co_fed_approval"] = false', 'result["co_fed_approval"] = true'),
    "C21_fire_validation_approved": (
        OWNER, 'result["fire_validation_approval"] = false', 'result["fire_validation_approval"] = true'),
    "C22_prescribed_temperature_presented_as_predicted": (
        OWNER, '"temperature_is_prescribed_not_predicted": true,',
        '"temperature_is_prescribed_not_predicted": false,'),
    "C23_composition_preview_writes": (
        OWNER, _EVIDENCE, '_owned = proposal["candidate"].duplicate(true)\n\t' + _EVIDENCE),
    "C24_scope_relabelled": (
        OWNER, '"scope": "isolated_real_property_composition_prescribed_release_synthetic_budget_'
               'not_fire_validation",', '"scope": "validated_real_heptane_fire",'),
    "C25_silent_refusal": (
        OWNER, "\tif errors.is_empty():\n\t\treturn super._failure(", "\tif false:\n\t\treturn super._failure("),
    "C26_molar_mass_replaced_by_the_nominal_one": (
        OWNER, 'evidence["molar_mass_g_mol"] = profile["molar_mass_g_mol"]', 'evidence["molar_mass_g_mol"] = 100.0'),
    "C27_emission_evidence_of_another_temperature": (
        OWNER, 'request["emitted_vapour_temperature_k"])\n\tif not _positive(emitted):',
        'Real.Canonical.REFERENCE_K)\n\tif not _positive(emitted):'),
}


def oracle_controls() -> dict:
    """Controls of the fixture: one number of the oracle block moved by one part in a million."""
    expected = build.expectations()
    main = expected["sequences"]["main"]["steps"]
    capped = expected["sequences"]["budget_limited"]["steps"]
    chosen = {
        "F01_oracle_analytic_cost_moved": (
            "release_cost_kj_kg", expected["analytic"]["steps"][0]["release_cost_kj_kg"]),
        "F02_oracle_budget_moved": ("thermal_budget_kj", main[0]["phase"]["thermal_budget_kj"]),
        "F03_oracle_mixed_enthalpy_moved": ("mixed_specific_kj_kg", main[1]["step"]["mixed_specific_kj_kg"]),
        "F04_oracle_capped_release_moved": ("accepted_release_kg", capped[0]["step"]["accepted_release_kg"]),
    }
    return {name: (FIXTURE, '"%s": %r,' % (key, value), '"%s": %r,' % (key, value * (1.0 + 1.0e-6)))
            for name, (key, value) in chosen.items()}


DECLARED = len(MUTATIONS) + 4


def prepared_variants(sources: dict[Path, str]) -> dict[str, tuple[Path, str]]:
    variants = {}
    for name, (path, old, new) in {**MUTATIONS, **oracle_controls()}.items():
        if sources[path].count(old) != 1:
            raise ValueError(f"{name}: anchor found {sources[path].count(old)} times, expected 1")
        variants[name] = (path, sources[path].replace(old, new))
        if variants[name][1] == sources[path]:
            raise ValueError(f"{name}: mutation changes nothing")
    return variants


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--only", action="append", default=[], help="run the control and these mutants")
    args = parser.parse_args()
    originals = {path: path.read_bytes() for path in ASSETS}
    variants = prepared_variants({path: originals[path].decode("utf-8") for path in TARGETS})
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
    evidence = ROOT / "runs" / ("g3_real_sensible_composition_mutations_" +
                               datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        for name, (changed, text) in {"control": (None, ""), **variants}.items():
            project = evidence / name
            for path, raw in originals.items():
                target = project / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(text.encode("utf-8") if path == changed else raw)
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="Isolated real sensible composition"\n',
                encoding="utf-8")
            run = godot_monitored_launch.run(
                [godot, "--headless", "--path", project, "--script", project / FIXTURE.relative_to(ROOT)],
                timeout_s=300, environment=os.environ.copy())
            for filename, content in [("health.json", json.dumps(run.health, indent=2)),
                                      ("stdout.log", run.stdout), ("stderr.log", run.stderr)]:
                (project / filename).write_text(content, encoding="utf-8")
            if not run.launched:
                raise RuntimeError(f"{name}: not launched: {run.faults or run.preexisting}")
            payload, reason = {}, ""
            if run.faults or run.preexisting:
                verdict, reason = "invalid", f"monitor: {run.faults or run.preexisting}"
            else:
                try:
                    verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
                except (RuntimeError, ValueError) as exc:
                    verdict, reason = "invalid", str(exc)
            results.append({"name": name, "verdict": verdict, "reason": reason, "checks": payload.get("checks"),
                            "failed_checks": len(payload.get("failures", [])),
                            "first_failures": payload.get("failures", [])[:3],
                            "source_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest() if changed else None})
            print(json.dumps({"name": name, "verdict": verdict, "reason": reason,
                              "failed_checks": len(payload.get("failures", []))}), flush=True)
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
