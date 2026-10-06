"""Predeclared GDScript mutations of the real n-heptane Cp adapter, run in Godot.

Each variant is written to an isolated copy of the five scripts the fixture
loads; the working sources are never edited. Three families: the adapter code,
its approved content, and the shared integral of the synthetic helper. A kill
is a fixture that ran to the end and reported failed checks; a parse or script
error is an invalid run, not a kill.
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
from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify  # noqa: E402

ADAPTER = ROOT / "sim/fire/HeptaneRealCpProfiles.gd"
HELPER = ROOT / "sim/fire/SensibleEnthalpyModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_heptane_real_cp.gd"
SUPPORT = [ROOT / "sim/fire/FuelMassBudgetModel.gd",
           ROOT / "sim/fire/PrescribedSensiblePhaseController.gd",
           ROOT / "sim/fire/PrescribedFuelReleaseModel.gd"]
PREFIX = "G3_HEPTANE_REAL_CP"
FLAGS = ('"physical_approval": false, "integration_enabled": false, "product_activation": false,\n'
         '\t\t"ledger_composition_approval": false}')
# name: (file, old, new, occurrences)
MUTATIONS = {
    "A01_content_binding_skipped": (ADAPTER, '\t_same(profile, APPROVED[schema], "profile", errors)\n', "", 1),
    "A02_integer_accepted_for_float": (
        ADAPTER, "if typeof(value) != typeof(expected):",
        "if typeof(value) != typeof(expected) and not (typeof(value) == TYPE_INT "
        "and typeof(expected) == TYPE_FLOAT):", 1),
    "A03_extra_keys_allowed": (ADAPTER, "\t\t\t\tif not expected.has(key):", "\t\t\t\tif false:", 1),
    "A04_missing_keys_allowed": (
        ADAPTER, '\t\t\t\t\terrors.append(path + ": missing key " + key)', "\t\t\t\t\tpass", 1),
    "A05_arrays_not_compared": (
        ADAPTER, '\t\t\t\t_same(value[index], expected[index], path + "[" + str(index) + "]", errors)',
        "\t\t\t\tpass", 1),
    "A06_float_tolerance": (
        ADAPTER, "if is_nan(value) or value != expected:",
        "if is_nan(value) or absf(value - expected) > 1.0e-6:", 1),
    "A07_nan_content_accepted": (
        ADAPTER, "if is_nan(value) or value != expected:", "if value != expected and not is_nan(value):", 1),
    "A08_labels_not_compared": (ADAPTER, "\t\t_:\n\t\t\tif value != expected:", "\t\t_:\n\t\t\tif false:", 1),
    "A09_interval_sign_inverted": (
        ADAPTER, 'second["specific_sensible_enthalpy_kj_kg"] - first["specific_sensible_enthalpy_kj_kg"]',
        'first["specific_sensible_enthalpy_kj_kg"] - second["specific_sensible_enthalpy_kj_kg"]', 1),
    "A10_interval_by_endpoint_cp": (
        ADAPTER, 'second["specific_sensible_enthalpy_kj_kg"] - first["specific_sensible_enthalpy_kj_kg"]',
        'second["cp_kj_kg_k"] * (end - start)', 1),
    "A11_limits_of_end_point_only": (
        ADAPTER, "_described(approved, low, high)", "_described(approved, temperature, temperature)", 1),
    "A12_interval_limits_of_end_only": (
        ADAPTER, "_described(approved, minf(start, end), maxf(start, end))", "_described(approved, end, end)", 1),
    "A13_every_tier_always": (
        ADAPTER, "if minf(end, high) - maxf(start, low) > 0.0 or (low == high and start <= low and low <= end):",
        "if true:", 1),
    "A14_reference_left_out_of_interval": (
        ADAPTER, "var low: float = minf(Canonical.REFERENCE_K, temperature)", "var low: float = temperature", 1),
    "A15_total_uncertainty_claimed": (
        ADAPTER, '"total_uncertainty_quantified": false,', '"total_uncertainty_quantified": true,', 1),
    "A16_declared_limits_dropped": (
        ADAPTER, '"declared_errors": approved["declared_errors"],', '"declared_errors": {},', 1),
    "A17_approved_constant_aliased": (
        ADAPTER, "return _success(APPROVED[schema].duplicate(true))", "return _success(APPROVED[schema])", 1),
    "A18_validated_profile_aliased": (
        ADAPTER, "return _success(profile.duplicate(true))", "return _success(profile)", 1),
    "A19_physical_approval": (ADAPTER, FLAGS, FLAGS.replace('"physical_approval": false', '"physical_approval": true'), 2),
    "A20_integration_enabled": (
        ADAPTER, FLAGS, FLAGS.replace('"integration_enabled": false', '"integration_enabled": true'), 2),
    "A21_product_activation": (
        ADAPTER, FLAGS, FLAGS.replace('"product_activation": false', '"product_activation": true'), 2),
    "A22_ledger_composition_approval": (
        ADAPTER, FLAGS, FLAGS.replace('"ledger_composition_approval": false', '"ledger_composition_approval": true'), 2),
    "A23_synthetic_scope": (
        ADAPTER, 'const SCOPE: String = "real_primary_source_property_isolated_not_fire_validation"',
        'const SCOPE: String = "synthetic_isobaric_property_not_material_calibration"', 1),
    "A24_boolean_query": (
        ADAPTER, "return typeof(value) in [TYPE_INT, TYPE_FLOAT] and",
        "return typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] and", 1),
    "A25_nan_query": (ADAPTER, " and not is_nan(float(value))", "", 1),
    "A26_infinite_query": (ADAPTER, " and not is_inf(float(value))", "", 1),
    "D01_molar_mass_of_the_engine": (ADAPTER, '"molar_mass_g_mol": 100.2,', '"molar_mass_g_mol": 100.0,', 2),
    "D02_scale_label": (
        ADAPTER, '"temperature_scale": "ITS-90_kelvin",', '"temperature_scale": "synthetic_kelvin",', 2),
    "D03_reference_pressure": (ADAPTER, '"reference_pressure_pa": 100000.0,', '"reference_pressure_pa": 101325.0,', 2),
    "D04_reference_temperature": (
        ADAPTER, '"reference_temperature_k": 298.15,', '"reference_temperature_k": 298.16,', 2),
    "D05_phase_label": (ADAPTER, '"phase": "liquid",', '"phase": "gas",', 1),
    "D06_caloric_model": (ADAPTER, '"caloric_model": "ideal_gas",', '"caloric_model": "real_gas",', 1),
    "D07_pressure_path": (
        ADAPTER, '"pressure_path": "constant_pressure",', '"pressure_path": "saturation_curve",', 2),
    "D08_evidence_upgraded": (
        ADAPTER, '"evidence_kind": "assumption_adopted_by_source_for_vapour_pressure_consistency",',
        '"evidence_kind": "measurement",', 1),
    "D09_absent_uncertainty_filled": (
        ADAPTER, '"source_error_statement_above_360_k_percent": null,',
        '"source_error_statement_above_360_k_percent": 0.1,', 1),
    "D10_gas_assumptions_verified": (
        ADAPTER, '"molar_mass_and_scale_verified_at_origin": false,',
        '"molar_mass_and_scale_verified_at_origin": true,', 1),
    "D11_scale_declared_exact": (
        ADAPTER, '"scale_conversion_kind": "approximate_on_smoothed_values",', '"scale_conversion_kind": "exact",', 2),
    "D12_top_tier_reclassified": (
        ADAPTER, '"evidence_kind": "interpolation_towards_a_row_beyond_the_adjusted_table",',
        '"evidence_kind": "tabulated_Csat_of_the_source_converted_to_Cp_here",', 1),
    "D13_fire_validated": (
        ADAPTER, '"calibration_status": "primary_source_property_not_fire_validation",',
        '"calibration_status": "fire_validated",', 2),
    "D14_synthetic_provenance": (ADAPTER, '"provenance": "primary:sha256:', '"provenance": "synthetic:sha256:', 2),
    "D15_real_gas_applied": (ADAPTER, '"real_gas_departure_applied": false,', '"real_gas_departure_applied": true,', 1),
    "H01_sign_lost": (
        HELPER, "var signed_integral: float = -integral if temperature < REFERENCE_K else integral",
        "var signed_integral: float = integral", 1),
    "H02_reference_not_subtracted": (
        HELPER, "var lower: float = minf(REFERENCE_K, temperature)", "var lower: float = minf(minimum, temperature)", 1),
    "H03_end_point_cp_instead_of_integral": (
        HELPER, "var signed_integral: float = -integral if temperature < REFERENCE_K else integral",
        "var signed_integral: float = query_cp * (temperature - REFERENCE_K)", 1),
    "H04_partial_interval_omitted": (HELPER, "if b <= a:", "if b <= a or a != t0 or b != t1:", 1),
    "H05_intermediate_intervals_omitted": (HELPER, "integral += area", "integral += area if index == 0 else 0.0", 1),
    "H06_clamped_instead_of_rejected": (
        HELPER, "if temperature < minimum or temperature > maximum:",
        "temperature = clampf(temperature, minimum, maximum)\n\tif temperature < minimum or temperature > maximum:", 1),
    "H07_latent_heat_added": (
        HELPER, '"specific_sensible_enthalpy_kj_kg": signed_integral,',
        '"specific_sensible_enthalpy_kj_kg": signed_integral + 300.0,', 1),
    "H08_overflow_accepted": (HELPER, "if not _number(area) or not _number(integral):", "if false:", 1),
    "H09_synthetic_schema_not_checked": (
        HELPER, "for key: String in FIXED:", 'for key: String in FIXED:\n\t\tif key == "schema":\n\t\t\tcontinue', 1),
}


def _sample_line(sample):
    return '{"temperature_k": %r, "cp_kj_kg_k": %r},' % (sample["temperature_k"], sample["cp_kj_kg_k"])


def data_mutations():
    """Content mutants whose text depends on the approved numbers themselves."""
    from scripts.simulation import build_g3_heptane_real_cp_profiles as build

    content = build.approved_content()
    expected = build.expectations()
    liquid = content["g3_real_liquid_isobaric_cp_v1"]["samples"]
    gas = content["g3_real_ideal_gas_cp_v1"]["samples"]
    csat = dict(liquid[8], cp_kj_kg_k=expected["liquid"]["csat_only_cp_kj_kg_k"][8])
    return {
        "D16_csat_left_unconverted": (ADAPTER, _sample_line(liquid[8]), _sample_line(csat), 1),
        "D17_joule_kilojoule_slip": (
            ADAPTER, _sample_line(gas[8]), _sample_line(dict(gas[8], cp_kj_kg_k=gas[8]["cp_kj_kg_k"] * 1000.0)), 1),
        "D18_knot_removed": (ADAPTER, "\t\t\t" + _sample_line(liquid[9]) + "\n", "", 1),
        "D19_native_label_kept": (ADAPTER, _sample_line(liquid[0]), _sample_line(dict(liquid[0], temperature_k=280.0)), 1),
        "D20_support_extended": (ADAPTER, _sample_line(gas[-1]), _sample_line(dict(gas[-1], temperature_k=480.0)), 1),
    }


def prepared_variants(sources: dict[Path, str]) -> dict[str, tuple[Path, str]]:
    variants = {}
    for name, (path, old, new, occurrences) in {**MUTATIONS, **data_mutations()}.items():
        if sources[path].count(old) != occurrences:
            raise ValueError(f"{name}: anchor found {sources[path].count(old)} times, expected {occurrences}")
        mutated = sources[path].replace(old, new)
        if mutated == sources[path]:
            raise ValueError(f"{name}: mutation changes nothing")
        variants[name] = (path, mutated)
    return variants


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    files = [ADAPTER, HELPER, FIXTURE, *SUPPORT]
    originals = {path: path.read_bytes() for path in files}
    sources = {path: originals[path].decode("utf-8") for path in [ADAPTER, HELPER]}
    variants = prepared_variants(sources)
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot missing")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / (
        "g3_heptane_real_cp_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
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
                'config_version=5\n[application]\nconfig/name="Isolated real Cp adapter"\n', encoding="utf-8")
            run = godot_monitored_launch.run(
                [godot, "--headless", "--path", project, "--script", project / FIXTURE.relative_to(ROOT)],
                timeout_s=180, environment=os.environ.copy())
            (project / "health.json").write_text(json.dumps(run.health, indent=2), encoding="utf-8")
            (project / "stdout.log").write_text(run.stdout, encoding="utf-8")
            (project / "stderr.log").write_text(run.stderr, encoding="utf-8")
            if not run.launched or run.faults or run.preexisting:
                raise RuntimeError(f"{name}: monitor failure {run.faults or run.preexisting}")
            try:
                verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
            except RuntimeError as exc:
                # A parse or script error is never a kill; the campaign goes on to report it.
                verdict, payload = "invalid", {"checks": 0, "failures": [str(exc)]}
            results.append({"name": name, "verdict": verdict, "checks": payload["checks"],
                            "failed_checks": len(payload["failures"]), "first_failures": payload["failures"][:3]})
            print(json.dumps({"name": name, "verdict": verdict, "failed_checks": len(payload["failures"])}),
                  flush=True)
            if name == "control" and verdict != "pass":
                raise RuntimeError("control does not pass")
        unresolved = [r["name"] for r in results if r["name"] != "control" and r["verdict"] != "killed"]
        if unresolved:
            raise RuntimeError("surviving or invalid mutants: " + ", ".join(unresolved))
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        (evidence / "results.json").write_text(json.dumps({
            "results": results, "originals_intact": intact,
            "original_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for path, raw in originals.items()},
        }, indent=2), encoding="utf-8")
        if not intact:
            raise RuntimeError("working sources altered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
