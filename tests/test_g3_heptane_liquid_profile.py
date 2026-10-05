"""Offline controls of the liquid conversion; no GDScript or engine mutant is claimed.

Expected values were fixed before the auditor existed: printed source rows and
an independent calculation with least-squares polynomials (global quartic in
temperature, quadratic in pressure) on the archived NIST data file.
"""
import copy
import hashlib
import json
import math

import pytest

from scripts.simulation import audit_g3_heptane_liquid_profile as liquid
from scripts.simulation import audit_g3_heptane_real_profile as real


def record():
    return liquid.load_profile(liquid.INPUT)


@pytest.fixture(scope="module")
def ctx():
    return liquid.context()


@pytest.fixture(scope="module")
def saved():
    return liquid.audit()


def preview():
    return liquid.contract_preview()


def test_saved_audit_reproduces_and_promotes_nothing(saved):
    assert saved == liquid.load_profile(liquid.SAVED)
    assert saved["decision"] == {
        "liquid": "GO_partial_isobaric_cp_at_100_kPa_native_280_to_371.139_K_by_justified_conversion",
        "gas": "GO_partial_unchanged_conditional_on_declared_assumptions",
        "joint_adapter": "GO_partial_design_only_same_real_schema_family",
        "current_synthetic_contract": "NO_GO_by_design_requires_versioned_real_schema",
        "net_heat_budget_B": "NO_GO_separate_gate",
    }
    for key in ["csat_accepted_as_cp_substitute", "adapter_implemented_in_sim",
                "gas_assumptions_verified_at_origin", "gas_range_extended",
                "volumetric_article_inspected", "physical_benchmark_approval",
                "engine_integration", "production_activation"]:
        assert saved[key] is False


# Quadratic in pressure through the lowest points of each isotherm (numpy fit).
@pytest.mark.parametrize("isotherm,density,tolerance", [
    (273.15, 700.685, 0.002), (293.15, 683.987, 0.002), (353.15, 631.037, 0.002),
    (373.15, 611.934, 0.02), (393.15, 591.721, 0.03),   # extrapolated about 1 MPa
])
def test_isobaric_density_at_the_reference_pressure(ctx, isotherm, density, tolerance):
    value = liquid.density(ctx, isotherm, 100000)
    assert float(value) == pytest.approx(density, abs=tolerance)


def test_volumetric_data_set_is_the_reviewed_one(ctx, saved):
    assert sorted(float(t) for t in ctx["isotherms"]) == [
        233.15, 253.15, 273.15, 293.15, 313.15, 333.15, 353.15, 373.15, 393.15]
    assert sum(len(points) for points in ctx["isotherms"].values()) == 151
    assert saved["volumetric"]["extrapolated_isotherms_k"] == [373.15, 393.15]
    assert saved["volumetric"]["sample_purity_mol_percent"] == 99.3


def test_independent_archived_measurements_agree_with_the_volumetric_data(saved):
    volumetric = saved["volumetric"]
    # Brooks 1940: -0.000849 g/(ml*K) between 20 and 25 degC; two densities good to
    # a few 1e-5 g/ml over 5 K cannot fix the slope better than about 1 percent.
    assert volumetric["density_slope_22_5_c_kg_m3_k"] == pytest.approx(-0.84591, abs=0.002)
    assert abs(volumetric["density_slope_ratio_to_brooks"] - 1) <= 0.01
    # The absolute density does differ; it is reported, not tuned away.
    assert volumetric["density_20_c_minus_brooks_percent"] == pytest.approx(0.045, abs=0.005)
    # Osborne and Ginnings 1947: (dH/dT)sat - Csat = 0.0004 J/(g*K), two columns
    # printed to 0.0001 J/(g*K).
    assert volumetric["v_dp_dt_22_5_c_j_mol_k"] == pytest.approx(0.04024, abs=0.0005)
    assert volumetric["v_dp_dt_22_5_c_j_mol_k"] == pytest.approx(0.0401, abs=0.01)


def test_saturation_pressure_and_boiling_point(ctx):
    pressure, slope = liquid.saturation(ctx, 298.16)
    assert float(pressure) == pytest.approx(6095.3, abs=0.1)
    assert float(slope) == pytest.approx(304.2, abs=0.1)
    boiling = liquid.boiling_native(ctx)
    assert float(boiling) == pytest.approx(371.1392, abs=1e-4)
    assert float(liquid.saturation(ctx, float(boiling))[0]) == pytest.approx(100000, abs=1e-3)
    assert float(real.source_to_its90(ctx["gas_review"], float(boiling))) == pytest.approx(
        371.1029, abs=float(real.LABEL_ABS_TOL_K))


@pytest.mark.parametrize("native,first,second", [
    (280, 0.00646, -0.01551), (298.16, 0.01670, -0.01882), (330, 0.06693, -0.02375),
    (350, 0.14048, -0.02047), (370, 0.27362, -0.00183),
])
def test_conversion_terms_match_the_independent_polynomial_calculation(ctx, native, first, second):
    result = liquid.conversion(ctx, native)
    assert float(result["first_term_j_mol_k"]) == pytest.approx(
        first, rel=float(liquid.FIRST_DERIVATIVE_REL_TOL))
    assert float(result["second_term_j_mol_k"]) == pytest.approx(
        second, rel=float(liquid.SECOND_DERIVATIVE_REL_TOL))
    assert float(result["cp_minus_csat_j_mol_k"]) == pytest.approx(
        first + second, abs=float(liquid.CONVERSION_ABS_TOL))


def test_conversion_is_small_signed_and_not_a_relabelling(ctx, saved):
    rows = {row["native_k"]: row for row in saved["conversion"]["rows"]}
    assert rows[280]["cp_minus_csat_j_mol_k"] < 0 < rows[310]["cp_minus_csat_j_mol_k"]
    assert rows[298.16]["cp_minus_csat_j_mol_k"] == pytest.approx(-0.00212, abs=0.002)
    top = saved["conversion"]["rows"][-1]
    assert top["native_k"] == pytest.approx(371.1392, abs=1e-4)
    assert top["second_term_j_mol_k"] == pytest.approx(0.0, abs=1e-9)
    assert top["cp_minus_csat_j_mol_k"] == pytest.approx(0.28366, abs=0.003)
    assert saved["conversion"]["max_abs_cp_minus_csat_j_mol_k"] <= 0.29
    assert saved["conversion"]["max_abs_percent_of_csat"] <= 0.12
    assert saved["conversion"]["first_derivative_method_spread_max"] <= 0.01
    assert saved["conversion"]["second_derivative_method_spread_max"] <= 0.25
    assert saved["conversion"]["exactness"] == "exact_identity_with_approximate_inputs"


def test_saturation_enthalpy_closes_with_measured_volumes(saved):
    closure = saved["closure"]
    # Simpson on the printed Csat rows; printed H column 69810 - 52596 J/mol.
    assert closure["csat_simpson_298_16_to_370_j_mol"] == pytest.approx(17199.9364, abs=1e-3)
    assert closure["printed_delta_h_sat_j_mol"] == 17214
    assert closure["v_dp_measured_volume_j_mol"] == pytest.approx(14.2522, abs=0.15)
    assert abs(closure["saturation_residual_j_mol"]) <= closure["closure_abs_tol_j_mol"] == 1.6
    # The source's empirical equation 12 gave 13.3424: a real 0.9 J/mol difference.
    assert closure["v_dp_measured_minus_equation_12_j_mol"] == pytest.approx(0.91, abs=0.15)


def test_converted_cp_integrates_to_the_isobaric_enthalpy_increment(saved):
    closure = saved["closure"]
    assert closure["pressure_step_298_16_j_mol"] == pytest.approx(8.6903, abs=0.1)
    assert closure["pressure_step_370_j_mol"] == pytest.approx(0.2236, abs=0.01)
    assert closure["cp_simpson_298_16_to_370_j_mol"] == pytest.approx(17205.72, abs=0.1)
    assert closure["isobaric_delta_h_from_printed_rows_j_mol"] == pytest.approx(17205.53, abs=0.15)
    assert abs(closure["isobaric_residual_j_mol"]) <= closure["closure_abs_tol_j_mol"]
    # Integrating Csat as if it were Cp at 100 kPa would miss by the pressure steps.
    assert closure["csat_as_cp_error_j_mol"] == pytest.approx(-5.6, abs=0.3)


def test_scale_conversion_changes_the_quantity_not_only_the_labels(saved):
    scale = saved["scale"]
    rows = {row["its90_k"]: row for row in scale["same_numerical_temperature_rows"]}
    # Hand value at 310 K: Csat(310.029)*1.000377 - 229.27 = +0.098 J/(mol*K), +0.042 %.
    assert rows[310]["this_gate_percent"] == pytest.approx(0.042, abs=0.005)
    assert rows[310]["jpcrd_percent"] == 0.04
    # Labels alone would give only +0.005 %: the quantity itself moves.
    assert rows[310]["labels_only_percent"] == pytest.approx(0.005, abs=0.002)
    assert scale["kind"] == "approximate_on_smoothed_values"
    assert scale["exact_conversion_needs"] == "raw_heat_and_initial_and_final_temperatures"
    # Hand value 0.056 at 370 K against a deviation printed to 0.01 %.
    assert scale["max_abs_difference_to_jpcrd_percent"] <= 0.07
    assert scale["max_abs_difference_to_jpcrd_percent"] == pytest.approx(0.056, abs=0.006)


def test_contrast_with_the_published_its90_evaluation_stays_within_its_uncertainty(saved):
    contrast = saved["contrast_jpcrd_1994"]
    assert contrast["archived"] is False
    assert len(contrast["rows"]) == 4
    for row in contrast["rows"]:
        assert abs(row["csat_percent"]) <= 0.1
        assert abs(row["cp_at_saturation_percent"]) <= 0.1
    # Their Cp - Csat is the difference of two columns fitted and rounded separately.
    for row in contrast["rows"]:
        assert abs(row["first_term_minus_jpcrd_difference_j_mol_k"]) <= 0.03
    assert contrast["bureau_of_mines_minus_nbs_max_percent"] == pytest.approx(0.09, abs=0.01)
    assert contrast["evidence_kind"] == (
        "critical_evaluation_of_the_same_primary_data_not_an_independent_measurement")


def test_preview_units_range_and_reference(ctx):
    candidate = preview()
    samples = candidate["samples"]
    assert len(samples) == 14
    assert samples[0]["temperature_k"] == pytest.approx(279.9855, abs=0.0006)
    assert samples[-1]["temperature_k"] == pytest.approx(371.1029, abs=0.0006)
    assert samples[0]["temperature_k"] < 298.15 < samples[-1]["temperature_k"]
    # 224.7379 J/(mol*K) at the 298.16 K row, over 100.20 g/mol, times the scale factor.
    factor = float(real.its90_scale_factor(ctx["gas_review"], 298.16))
    assert samples[4]["cp_kj_kg_k"] / factor == pytest.approx(224.7379 / 100.20, abs=1e-4)
    assert candidate["phase"] == "liquid" and candidate["caloric_model"] == "declared_liquid"
    assert candidate["pressure_path"] == "constant_pressure"
    assert candidate["reference_pressure_pa"] == 100000.0
    assert candidate["quantity_unit"] == "kJ/(kg*K)" and candidate["molar_mass_g_mol"] == 100.20
    assert candidate["schema"] == "g3_real_liquid_isobaric_cp_v1"
    low = real.canonical_enthalpy(samples, samples[0]["temperature_k"])
    high = real.canonical_enthalpy(samples, samples[-1]["temperature_k"])
    assert low < 0 < high


def test_canonical_integral_keeps_the_isobaric_enthalpy_increment(saved):
    closure = saved["closure"]
    # Piecewise-linear integral on the ITS-90 knots, same states as the printed rows.
    assert closure["canonical_delta_h_298_16_to_370_j_mol"] == pytest.approx(17205.53, abs=4.2)
    # Trapezoid over a convex curve: +0.83 J/mol, known no better than the declared
    # 1e-4 of the scale factor on 17 206 J/mol.
    assert closure["canonical_minus_simpson_j_mol"] == pytest.approx(0.83, abs=1.8)
    assert saved["discretization"]["cp_interpolation_bound_j_mol_k"] <= 0.025


def test_untouched_preview_passes_its_own_contract():
    assert liquid.check_candidate(preview())["valid"] is True


def scaled(candidate, factor):
    for sample in candidate["samples"]:
        sample["cp_kj_kg_k"] *= factor


def replaced(candidate, values):
    for sample, value in zip(candidate["samples"], values):
        sample["cp_kj_kg_k"] = value


def shifted(candidate, offset):
    for sample, label in zip(candidate["samples"], NATIVE):
        sample["temperature_k"] = label + offset


NATIVE = [280, 285, 290, 295, 298.16, 300, 310, 320, 330, 340, 350, 360, 370, 371.1392]
CSAT = [218.23, 219.97, 221.75, 223.57, 224.74, 225.44, 229.27, 233.25, 237.38, 241.67,
        246.09, 250.63, 255.30, 255.847]


def csat_only(candidate):
    review = record()
    prior = real.load_profile(real.INPUT)["review"]
    for sample, native, value in zip(candidate["samples"], NATIVE, CSAT):
        factor = float(real.its90_scale_factor(prior, native))
        sample["cp_kj_kg_k"] = value * factor / 100.20
    assert review["review"]["approvals"]["csat_accepted_as_cp_substitute"] is False


@pytest.mark.parametrize("mutate,message", [
    (lambda c: scaled(c, 1000.0), "basis"),
    (lambda c: scaled(c, 0.001), "basis"),
    (lambda c: scaled(c, 100.20), "basis"),
    (lambda c: scaled(c, 100.20 / 100.0), "basis"),
    (lambda c: scaled(c, 100.20 / 100.20404), "basis"),             # molar mass of the evaluation
    (csat_only, "basis"),                                           # Csat left unconverted
    (lambda c: replaced(c, [1.65] * 14), "basis"),                  # a gas-like constant
    (lambda c: c.__setitem__("molar_mass_g_mol", 100.20404), "molar mass"),
    (lambda c: c.__setitem__("quantity_unit", "J/(mol*K)"), "unit"),
    (lambda c: c.__setitem__("phase", "gas"), "phase"),
    (lambda c: c.__setitem__("caloric_model", "ideal_gas"), "caloric"),
    (lambda c: c.__setitem__("pressure_path", "saturation_curve"), "pressure_path"),
    (lambda c: c.__setitem__("quantity", "saturation_heat_capacity"), "quantity"),
    (lambda c: c.__setitem__("temperature_scale", "synthetic_kelvin"), "scale"),
    (lambda c: shifted(c, 0.0), "mapping"),
    (lambda c: shifted(c, -0.01), "mapping"),
    (lambda c: c.__setitem__("reference_temperature_k", 298.16), "reference"),
    (lambda c: c.__setitem__("reference_pressure_pa", 101325.0), "reference"),
    (lambda c: c["samples"].append({"temperature_k": 380.0, "cp_kj_kg_k": 2.6}), "extrapolation"),
    (lambda c: c["samples"].insert(0, {"temperature_k": 270.0, "cp_kj_kg_k": 2.14}), "extrapolation"),
    (lambda c: c.__setitem__("samples", c["samples"][5:]), "reference outside"),
    (lambda c: c.__setitem__("samples", [c["samples"][0], c["samples"][4], c["samples"][-1]]),
     "discretization"),
    (lambda c: c.__setitem__("samples", list(reversed(c["samples"]))), "increasing"),
    (lambda c: scaled(c, -1.0), "positive"),
    (lambda c: c["samples"][3].__setitem__("cp_kj_kg_k", float("nan")), "finite"),
    (lambda c: c["samples"][3].__setitem__("cp_kj_kg_k", float("inf")), "finite"),
    (lambda c: c["samples"][3].__setitem__("temperature_k", True), "finite"),
    (lambda c: c["samples"][3].__setitem__("cp_kj_kg_k", "2.2"), "finite"),
    (lambda c: c["samples"][3].__setitem__("extra", 1.0), "sample"),
    (lambda c: c.__setitem__("schema", "g3_synthetic_isobaric_cp_v1"), "schema"),
    (lambda c: c.__setitem__("schema", "g3_real_ideal_gas_cp_v1"), "schema"),
    (lambda c: c.__setitem__("provenance", "synthetic:relabelled"), "provenance"),
    (lambda c: c.__setitem__("calibration_status", "fire_validated"), "calibration"),
    (lambda c: c.__setitem__("unreviewed", 1), "field"),
    (lambda c: c.pop("evidence_tiers"), "field"),
    (lambda c: c["declared_errors"].__setitem__("conversion_abs_j_mol_k", 0.0), "limits"),
    (lambda c: c["declared_errors"].__setitem__("source_error_statement_above_360_k_percent", 0.1),
     "limits"),                                                     # absent uncertainty filled in
    (lambda c: c["declared_errors"].__setitem__("volumetric_article_inspected", True), "limits"),
    (lambda c: c["evidence_tiers"][-1].__setitem__("evidence_kind", "measurement"), "limits"),
    (lambda c: c.__setitem__("native_support_k", [182.6, 480]), "limits"),
    (lambda c: c["witnesses"][0].__setitem__(
        "specific_sensible_enthalpy_kj_kg",
        abs(c["witnesses"][0]["specific_sensible_enthalpy_kj_kg"])), "witness"),
    (lambda c: c.__setitem__("witnesses", c["witnesses"][1:]), "witness"),
])
def test_candidate_negative_controls_are_rejected_with_their_reason(mutate, message):
    candidate = preview()
    mutate(candidate)
    with pytest.raises(ValueError, match=message):
        liquid.check_candidate(candidate)


def test_gas_and_liquid_previews_belong_to_one_family_but_do_not_cross():
    gas, liq = real.contract_preview(), preview()
    assert set(gas) == set(liq)
    for shared in ["reference_temperature_k", "reference_pressure_pa", "temperature_scale",
                   "quantity", "quantity_unit", "interpolation", "pressure_path",
                   "molar_mass_g_mol", "calibration_status"]:
        assert gas[shared] == liq[shared]
    with pytest.raises(ValueError):
        liquid.check_candidate(gas)
    with pytest.raises(ValueError):
        real.check_candidate(liq)
    conflicts = real.synthetic_schema_conflicts(liq)
    assert conflicts["schema"] == ["g3_real_liquid_isobaric_cp_v1", "g3_synthetic_isobaric_cp_v1"]
    assert "caloric_model" not in conflicts and "pressure_path" not in conflicts


def test_joint_support_and_phase_change_basis(saved):
    joint = saved["joint"]
    assert joint["liquid_its90_support_k"] == pytest.approx([279.9855, 371.1029], abs=0.0006)
    assert joint["gas_its90_support_k"] == pytest.approx([298.1355, 469.9916], abs=0.0006)
    assert joint["emission_window_its90_k"] == pytest.approx([298.1355, 371.1029], abs=0.0006)
    assert joint["vaporization_basis"] == "NIST_TN_2126_upd1_at_298.15_K_not_recomputed_here"
    assert joint["ledger_scope_labels_still_synthetic"] is True


def test_gas_assumed_range_against_the_government_correlation(saved):
    gas = saved["gas_review"]
    rows = {row["temperature_k"]: row for row in gas["contrast_rows"]}
    # 39.48, 39.67 and 50.35 cal/(K*mol) times 4.184; equations 23 and 22 of RP2526.
    assert rows[298.15]["correlated_cp_j_mol_k"] == pytest.approx(165.18432, abs=1e-5)
    assert rows[298.15]["correlated_minus_source_j_mol_k"] == pytest.approx(0.218, abs=0.002)
    assert rows[298.15]["percent"] == pytest.approx(0.132, abs=0.002)
    # Extrapolating equation 22 instead: 163.7672 against 165.1843 J/(mol*K).
    assert gas["equation_22_extrapolated_minus_correlated_percent"] == pytest.approx(-0.858, abs=0.002)
    assert rows[300]["correlated_minus_source_j_mol_k"] == pytest.approx(0.185, abs=0.002)
    assert rows[400]["correlated_minus_source_j_mol_k"] == pytest.approx(0.097, abs=0.002)
    # 12.52 - 8.02 kcal/mol against the source's 300 -> 400 K integral, 18826.38 J/mol.
    assert gas["delta_h_300_to_400_correlated_j_mol"] == pytest.approx(18828.0, abs=1e-6)
    assert gas["delta_h_300_to_400_source_j_mol"] == pytest.approx(18826.38, abs=0.01)
    assert gas["contrast_kind"] == "correlated_values_for_the_ideal_gas_not_measurements"
    assert gas["original_calorimetry_obtained"] is False
    assert gas["scale_and_molar_mass_verified_at_origin"] is False
    assert gas["same_laboratory_molar_mass_relative_difference"] == pytest.approx(2.0e-5, abs=2e-6)
    assert gas["authorized_native_range_k"] == [298.16, 470]


@pytest.mark.parametrize("path,value", [
    (("required_property", "pressure_path"), "saturation_curve"),
    (("required_property", "reference_pressure_pa"), 101325),
    (("relation", "exactness"), "exact"),
    (("volumetric", "original_article_inspected"), True),
    (("volumetric", "data_set_number"), 2),
    (("approvals", "csat_accepted_as_cp_substitute"), True),
    (("approvals", "gas_assumptions_verified_at_origin"), True),
    (("approvals", "engine_integration"), True),
    (("gas_original_calorimetry", "obtained"), True),
    (("contrast_bulletin_666", "calorie_j"), 4.1868),
])
def test_review_semantics_cannot_be_relabelled_together_with_the_data(path, value):
    changed = record()
    changed["review"][path[0]][path[1]] = value
    with pytest.raises(ValueError, match="semantics"):
        liquid.audit(changed)


def test_transcribed_rows_and_contrast_values_are_pinned_content():
    for edit in [lambda r: r["liquid_rows_below_290"]["rows"][0].__setitem__(1, 218.32),
                 lambda r: r["contrast_jpcrd_1994"]["table_4_rows"][3].__setitem__(2, 255.41),
                 lambda r: r["contrast_bulletin_666"]["cp_rows"][0].__setitem__(1, 39.84)]:
        changed = record()
        edit(changed["review"])
        with pytest.raises(ValueError, match="semantics"):
            liquid.audit(changed)


@pytest.mark.parametrize("name", sorted(liquid.SOURCES))
@pytest.mark.parametrize("field,value", [("path", "../other"), ("url", "https://example.com/x")])
def test_source_identity_is_not_replaceable(name, field, value):
    changed = record()
    changed["sources"][name][field] = value
    with pytest.raises(ValueError, match="identity"):
        liquid.audit(changed)


def test_contrast_identity_and_prior_gate_are_pinned():
    changed = record()
    changed["contrast_not_archived"]["archived"] = True
    with pytest.raises(ValueError, match="identity"):
        liquid.audit(changed)
    changed = record()
    changed["prior_review"]["sha256_lf"] = "0" * 64
    with pytest.raises(ValueError, match="prior"):
        liquid.audit(changed)


def test_altered_data_file_is_rejected(tmp_path):
    source = liquid.SOURCES["volumetric"]
    original = (liquid.ROOT / source["path"]).read_bytes()
    target = tmp_path / source["path"]
    target.parent.mkdir(parents=True)
    target.write_bytes(original.replace(b"683.986", b"683.896"))
    with pytest.raises(ValueError, match="content mismatch"):
        liquid.read_isotherms(tmp_path, record()["review"])


def test_another_compound_or_property_is_not_read_as_heptane_density():
    review = record()["review"]
    payload = json.loads((liquid.ROOT / liquid.SOURCES["volumetric"]["path"]).read_text("utf-8"))
    other = copy.deepcopy(review)
    other["volumetric"]["data_set_number"] = 2                       # n-nonane
    with pytest.raises(ValueError, match="data set"):
        liquid.isotherms_from(payload, other)
    wrong = copy.deepcopy(payload)
    wrong["PureOrMixtureData"][0]["Property"][0]["Property-MethodID"]["PropertyGroup"][
        "VolumetricProp"]["ePropName"] = "Specific volume, m3/kg"
    with pytest.raises(ValueError, match="data set"):
        liquid.isotherms_from(wrong, review)
    wrong = copy.deepcopy(payload)
    wrong["PureOrMixtureData"][0]["NumValues"][0]["PropertyValue"][0]["nPropValue"] = float("nan")
    with pytest.raises(ValueError, match="finite"):
        liquid.isotherms_from(wrong, review)
    wrong = copy.deepcopy(payload)
    wrong["PureOrMixtureData"][0]["NumValues"].pop()
    with pytest.raises(ValueError, match="data set"):
        liquid.isotherms_from(wrong, review)


@pytest.mark.parametrize("native", [270, 279.99, 371.2, 380, 500])
def test_conversion_outside_the_reviewed_range_is_rejected(ctx, native):
    with pytest.raises(ValueError, match="support"):
        liquid.conversion(ctx, native)


def test_pressure_and_temperature_outside_the_data_are_rejected(ctx):
    with pytest.raises(ValueError, match="support"):
        liquid.volume(ctx, 230.0, 100000)
    with pytest.raises(ValueError, match="support"):
        liquid.volume(ctx, 400.0, 100000)
    with pytest.raises(ValueError, match="support"):
        liquid.density(ctx, 293.15, 5.0e6)
    with pytest.raises(ValueError, match="isotherm"):
        liquid.density(ctx, 300.0, 100000)


def test_audit_reads_only_and_leaves_sources_untouched():
    paths = [liquid.INPUT, liquid.SAVED] + [liquid.ROOT / source["path"]
                                             for source in liquid.SOURCES.values()]
    before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
    snapshot = copy.deepcopy(record())
    liquid.audit(snapshot)
    assert snapshot == record()
    assert before == [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]


def test_preview_is_a_design_output_not_an_engine_profile():
    candidate = preview()
    assert candidate["calibration_status"] == "primary_source_property_not_fire_validation"
    assert not candidate["provenance"].startswith("synthetic:")
    assert all(math.isfinite(sample["cp_kj_kg_k"]) for sample in candidate["samples"])
    assert not list((liquid.ROOT / "sim").rglob("*liquid_cp*"))
    assert not list((liquid.ROOT / "sim").rglob("*RealProfile*"))
