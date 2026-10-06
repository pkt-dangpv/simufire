"""Real GDScript adapter of the approved n-heptane Cp profiles.

The Godot fixtures execute the GDScript. Their expectations are generated in
Python from the offline auditors, and the hand values below come from printed
source increments; none is taken from the adapter under test.
"""
import hashlib
import json
import os
from pathlib import Path
import re

import pytest

from scripts.simulation import audit_g3_heptane_liquid_profile as liquid
from scripts.simulation import audit_g3_heptane_real_profile as real
from scripts.simulation import build_g3_heptane_real_cp_profiles as build

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "sim/fire/HeptaneRealCpProfiles.gd"
HELPER = ROOT / "sim/fire/SensibleEnthalpyModel.gd"
PREFIX = "G3_HEPTANE_REAL_CP"
# Digest of 933 synthetic validations and evaluations, bit for bit, captured
# with the helper of commit 628393d8 before its loop was extracted.
SYNTHETIC_IDENTITY = {"cases": 933, "valid": 565, "rejected": 368,
                      "sha256": "521425c77676e4523471a3070aa651b840144bd0cee51d37e542aec9fad950a8"}
FROZEN = {
    "FuelMassBudgetModel": "7ab01e1628441c048d55a45a512fc85aed8347dbd8140a29c98160e82fcd3f12",
    "PrescribedFuelReleaseModel": "db58278f2fff141d31148301095d41234f3732a66fa4140f74abfbaff483897d",
    "PrescribedPhaseBudgetController": "41e6e36768eb386f5b9c6f9e9cb5b1e002227526cfef5d013926f8a595e4e6c6",
    "PrescribedSensiblePhaseController": "63ea60420fa7a1995195addbc22e1fcfa4c30288b4fbb46174df44b120c01383",
}


def _run(fixture, prefix, allowed=(0,)):
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot

    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable unavailable")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", ROOT / fixture],
                          timeout_s=180, allowed_exit_codes=allowed)
    assert "SCRIPT ERROR" not in completed.stdout + completed.stderr
    assert "Parse Error" not in completed.stdout + completed.stderr
    lines = [line for line in completed.stdout.splitlines() if line.startswith(prefix + " {")]
    assert lines, completed.stdout + completed.stderr
    return json.loads(lines[-1].split(" ", 1)[1]), completed.stdout


def test_generated_blocks_come_from_the_reviewed_auditors():
    assert build.stale() == []
    content = build.approved_content()
    assert list(content) == ["g3_real_liquid_isobaric_cp_v1", "g3_real_ideal_gas_cp_v1"]
    assert len(content["g3_real_liquid_isobaric_cp_v1"]["samples"]) == 14
    assert len(content["g3_real_ideal_gas_cp_v1"]["samples"]) == 19
    # The same previews pass the offline contracts of their own gates.
    assert liquid.check_candidate(liquid.contract_preview())["valid"] is True
    assert real.check_candidate(real.contract_preview())["valid"] is True


def test_approved_content_keeps_its_limits_and_absent_uncertainty():
    content = build.approved_content()
    liq = content["g3_real_liquid_isobaric_cp_v1"]
    gas = content["g3_real_ideal_gas_cp_v1"]
    for profile in (liq, gas):
        assert profile["molar_mass_g_mol"] == 100.2
        assert profile["reference_temperature_k"] == 298.15 and profile["reference_pressure_pa"] == 100000.0
        assert profile["temperature_scale"] == "ITS-90_kelvin"
        assert profile["declared_errors"]["scale_conversion_kind"] == "approximate_on_smoothed_values"
        assert profile["declared_errors"]["fire_validation"] is False
        assert all(isinstance(s["cp_kj_kg_k"], float) for s in profile["samples"])
    assert liq["declared_errors"]["source_error_statement_above_360_k_percent"] is None
    assert liq["declared_errors"]["volumetric_article_inspected"] is False
    assert gas["declared_errors"]["source_accuracy_statement"] is None
    assert gas["declared_errors"]["scale_approximation_residual_percent"] is None
    assert gas["declared_errors"]["molar_mass_and_scale_verified_at_origin"] is False
    assert gas["declared_errors"]["real_gas_departure_applied"] is False
    assert [tier["evidence_kind"] for tier in gas["evidence_tiers"]] == [
        "assumption_adopted_by_source_for_vapour_pressure_consistency",
        "fitted_correlation_of_cited_flow_calorimetry_extrapolated_to_zero_pressure",
        "extrapolation_tabulated_by_source"]
    assert liq["evidence_tiers"][-1]["evidence_kind"] == (
        "interpolation_towards_a_row_beyond_the_adjusted_table")
    # The copyrighted 1994 re-evaluation is not the profile.
    jpcrd = liquid.load_profile(liquid.INPUT)["review"]["contrast_jpcrd_1994"]["table_4_rows"]
    printed = {round(row[2] / 100.20404, 6) for row in jpcrd} | {round(row[2] / 100.2, 6) for row in jpcrd}
    assert not printed & {round(sample["cp_kj_kg_k"], 6) for sample in liq["samples"]}


def test_expectations_are_python_oracles_not_adapter_output():
    expected = build.expectations()
    content = build.approved_content()
    for phase, schema in [("liquid", "g3_real_liquid_isobaric_cp_v1"), ("gas", "g3_real_ideal_gas_cp_v1")]:
        samples = content[schema]["samples"]
        assert expected[phase]["support"] == [samples[0]["temperature_k"], samples[-1]["temperature_k"]]
        assert len(expected[phase]["points"]) >= 2 * len(samples) + 4
        for temperature, _, enthalpy in expected[phase]["points"]:
            assert enthalpy == real.canonical_enthalpy(samples, temperature)
    # Printed gas H column: 124131 - 89219 J/mol between the outer knots, over 100.20 g/mol.
    gas = {point[0]: point[2] for point in expected["gas"]["points"]}
    low, high = expected["gas"]["support"]
    assert gas[high] - gas[low] == pytest.approx(34912 / 100.20, abs=0.06)
    assert len(expected["liquid"]["csat_only_cp_kj_kg_k"]) == 14


def test_real_gdscript_r01_r10():
    payload, stdout = _run("tests/fixtures/g3_heptane_real_cp.gd", PREFIX)
    assert payload["failures"] == []
    assert payload["groups"] == [f"R{i:02}" for i in range(1, 11)]
    assert payload["checks"] == CHECKS
    assert PREFIX + "_PASS" in stdout
    seen = payload["observations"]
    content = build.approved_content()
    liq = content["g3_real_liquid_isobaric_cp_v1"]["samples"]
    gas = content["g3_real_ideal_gas_cp_v1"]["samples"]
    oracle = {
        "liquid_first_h": real.canonical_enthalpy(liq, liq[0]["temperature_k"]),
        "liquid_last_h": real.canonical_enthalpy(liq, liq[-1]["temperature_k"]),
        "gas_first_h": real.canonical_enthalpy(gas, gas[0]["temperature_k"]),
        "gas_last_h": real.canonical_enthalpy(gas, gas[-1]["temperature_k"]),
        "liquid_minimum_k": liq[0]["temperature_k"], "liquid_maximum_k": liq[-1]["temperature_k"],
        "gas_minimum_k": gas[0]["temperature_k"], "gas_maximum_k": gas[-1]["temperature_k"],
    }
    for key, value in oracle.items():
        assert seen[key] == pytest.approx(value, abs=1e-9, rel=1e-12), key
    assert seen["liquid_full_change"] == pytest.approx(
        oracle["liquid_last_h"] - oracle["liquid_first_h"], abs=1e-9, rel=1e-12)
    assert seen["gas_full_change"] == pytest.approx(
        oracle["gas_last_h"] - oracle["gas_first_h"], abs=1e-9, rel=1e-12)
    # Hand values from printed source rows, independent of both implementations.
    # Gas: printed H(470) - H(298.16) = 34912 J/mol; the reference sits 0.0145 K above
    # the first knot, about 2.39 J/mol.
    assert seen["gas_full_change"] == pytest.approx(34912 / 100.20, abs=0.06)
    assert seen["gas_last_h"] == pytest.approx((34912 - 2.39) / 100.20, abs=0.06)
    assert seen["gas_first_h"] == pytest.approx(-2.39 / 100.20, abs=1e-3)
    # Liquid: isobaric increment 298.16 -> 370 K deduced from the printed H column,
    # 17205.5 J/mol, plus 1.139 K to the boiling point at about 2.553 kJ/(kg*K), minus
    # the 0.0145 K below the reference at 2.244: 171.71 + 2.91 - 0.03 kJ/kg.
    assert seen["liquid_last_h"] == pytest.approx(174.59, abs=0.05)
    assert seen["liquid_first_h"] < 0 < seen["liquid_last_h"]
    assert seen["liquid_reference_cp"] == pytest.approx(224.74 / 100.20, abs=2e-3)
    assert seen["gas_reference_cp"] == pytest.approx(164.97 / 100.20, abs=2e-3)


CHECKS = 1417


def test_synthetic_schema_is_bit_identical_before_and_after():
    payload, stdout = _run("tests/fixtures/g3_sensible_enthalpy_identity.gd", "G3_SENSIBLE_IDENTITY")
    assert payload == SYNTHETIC_IDENTITY
    assert "G3_SENSIBLE_IDENTITY_DONE" in stdout


def test_one_integral_shared_by_every_schema():
    helper = HELPER.read_text(encoding="utf-8")
    adapter = ADAPTER.read_text(encoding="utf-8")
    assert helper.count("integral += area") == 1
    assert helper.count("static func integrate(samples: Array, temperature: float) -> Dictionary:") == 1
    assert helper.count("integrate(") == 2          # its definition and the synthetic evaluator
    code = adapter.split("# END GENERATED APPROVED CONTENT")[1]
    assert code.count("Canonical.integrate(") == 3  # one query and the two ends of an interval
    for own_quadrature in ["integral +=", "integral =", "_cp_at", "0.5 *", "range(samples"]:
        assert own_quadrature not in code


def test_adapter_is_isolated_and_approves_nothing():
    source = ADAPTER.read_text(encoding="utf-8")
    assert source.startswith("extends RefCounted\n")
    assert not re.search(r"^var\s", source, re.M)
    assert source.count("preload(") == 1 and 'preload("res://sim/fire/SensibleEnthalpyModel.gd")' in source
    for forbidden in ["@export", "FileAccess", "SimulationEngine", "fuel_energy_MJ", "print(",
                      "FuelMassBudgetModel", "PrescribedSensiblePhaseController", "class_name"]:
        assert forbidden not in source
    assert set(re.findall(r"\b[a-z_]+_enabled\b", source)) == {"integration_enabled"}
    flags = re.findall(r'"(physical_approval|integration_enabled|product_activation|'
                       r'ledger_composition_approval)": (\w+)', source)
    assert len(flags) == 8 and all(value == "false" for _, value in flags)
    public = re.findall(r"^static func ([a-z]\w*)\(", source, re.M)
    assert public == ["approved_profile", "validate_profile", "evaluate", "evaluate_interval"]
    consumers = []
    for folder in ["sim", "editor", "ui", "view", "scenes", "scripts", "tools"]:
        for candidate in (ROOT / folder).rglob("*"):
            if (candidate.suffix in {".gd", ".tscn", ".tres"} and candidate != ADAPTER
                    and "HeptaneRealCpProfiles" in candidate.read_text(encoding="utf-8", errors="replace")):
                consumers.append(candidate.relative_to(ROOT).as_posix())
    assert consumers == []


def test_ledger_and_owners_are_untouched_and_know_no_real_schema():
    for name, expected in FROZEN.items():
        raw = (ROOT / f"sim/fire/{name}.gd").read_bytes().replace(b"\r\n", b"\n")
        assert hashlib.sha256(raw).hexdigest() == expected, name
        assert b"g3_real_" not in raw and b"HeptaneRealCpProfiles" not in raw
    helper = HELPER.read_text(encoding="utf-8")
    assert "g3_real_" not in helper and "ITS-90" not in helper
    assert helper.count('"schema": "g3_synthetic_isobaric_cp_v1"') == 1


def test_predeclared_mutations_cover_code_content_and_shared_integral():
    from scripts.simulation.run_g3_heptane_real_cp_mutations import ADAPTER as A, HELPER as H, prepared_variants

    sources = {A: A.read_text(encoding="utf-8"), H: H.read_text(encoding="utf-8")}
    variants = prepared_variants(sources)
    assert len(variants) == 55
    assert sum(name.startswith("A") for name in variants) == 26
    assert sum(name.startswith("D") for name in variants) == 20
    assert sum(name.startswith("H") for name in variants) == 9
    assert all(text != sources[path] for path, text in variants.values())


@pytest.mark.parametrize("stdout, stderr, code", [
    ("", "", 1), (PREFIX + ' {"failures":["wrong"]}', "Parse Error", 1),
    (PREFIX + ' {"failures":["wrong"]}', "SCRIPT ERROR", 1),
    (PREFIX + ' {"failures":["wrong"]}', "", -1),
])
def test_infrastructure_errors_are_not_killed_mutants(stdout, stderr, code):
    from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify

    with pytest.raises(RuntimeError):
        classify(stdout, stderr, code, PREFIX)
