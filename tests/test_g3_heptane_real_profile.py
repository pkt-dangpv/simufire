"""Offline eligibility controls; no GDScript adapter or engine mutant is claimed.

Expected values were fixed before the auditor existed: printed source rows and
an independent hand/scratch calculation on the printed scale tables.
"""
import copy
import hashlib
import math

import pytest

from scripts.simulation import audit_g3_heptane_real_profile as real


def record():
    return real.load_profile(real.INPUT)


def preview():
    return real.contract_preview()


def knot(candidate, index):
    return candidate["samples"][index]


def test_saved_audit_reproduces_and_promotes_nothing():
    result = real.audit()
    assert result == real.load_profile(real.SAVED)
    assert result["decision"] == {
        "gas": "GO_partial_ideal_gas_native_298.16_to_470_K",
        "liquid": "NO_GO_isobaric_profile_native_Csat_only",
        "current_synthetic_contract": "NO_GO_by_design_requires_versioned_real_schema",
        "net_heat_budget_B": "NO_GO_separate_gate",
    }
    for key in ["adapter_implemented_in_sim", "engine_integration", "production_activation",
                "physical_benchmark_approval", "real_gas_correction_applied",
                "liquid_isobaric_profile_approval"]:
        assert result[key] is False


# Printed scale tables, linear interpolation, done outside the auditor.
@pytest.mark.parametrize("native,its90", [
    (298.16, 298.13550), (300, 299.97474), (310, 309.97086),
    (370, 369.96363), (420, 419.97364), (470, 469.99163),
])
def test_scale_labels_match_independent_table_calculation(native, its90):
    review = record()["review"]
    assert float(real.source_to_its90(review, native)) == pytest.approx(
        its90, abs=float(real.LABEL_ABS_TOL_K))


def test_subtracting_one_hundredth_kelvin_is_not_the_scale_conversion():
    review = record()["review"]
    label = float(real.source_to_its90(review, 298.16))
    assert abs(label - 298.15) > 20 * float(real.LABEL_ABS_TOL_K)
    assert abs(float(real.source_to_its90(review, 370)) - 369.99) > 0.02


@pytest.mark.parametrize("native,factor", [
    (298.16, 1.000392), (300, 1.000388), (330, 1.000182),
    (370, 0.999880), (420, 0.999737), (470, 0.999657),
])
def test_scale_factor_matches_independent_table_calculation(native, factor):
    review = record()["review"]
    assert float(real.its90_scale_factor(review, native)) == pytest.approx(
        factor, abs=float(real.SCALE_FACTOR_ABS_TOL))


def test_printed_scale_table_and_equation_agree_within_print_resolution():
    result = real.audit()["scale"]
    assert result["mu_rows_checked"] == 37
    assert result["mu_max_abs_residual_k"] <= 0.0001
    assert result["dmu_max_abs_residual"] <= 0.00002


def test_gas_native_values_follow_the_printed_source():
    prior = real.prior_review()
    review = record()["review"]
    assert float(real.gas_cp_native(prior, review, 370)) == pytest.approx(197.28, abs=1e-9)
    assert float(real.gas_cp_native(prior, review, 420)) == pytest.approx(219.19, abs=0.02)
    assert float(real.gas_cp_native(prior, review, 470)) == pytest.approx(239.94, abs=0.02)
    # Printed H column: 124131 - 89219 and 124131 - 102231 J/mol.
    assert float(real.gas_delta_native(prior, review, 298.16, 470)) == pytest.approx(34912, abs=2)
    assert float(real.gas_delta_native(prior, review, 370, 470)) == pytest.approx(21900, abs=2)
    # Exact rational integration of the printed coefficients.
    assert float(real.gas_delta_native(prior, review, 370, 470)) == pytest.approx(21899.7816, abs=1e-6)
    assert float(real.gas_delta_native(prior, review, 298.16, 370)) == pytest.approx(13011.889539, abs=1e-6)


def test_weight_of_the_assumed_range_is_reported_not_hidden():
    gas = real.audit()["gas"]
    # Equation 23 is the tangent of equation 22 at 370 K: the difference is
    # c*(T-370)^2 plus the 0.002236 step, so -1.199 J/(mol*K) at 298.16 K and
    # c*71.84^3/3 + 0.002236*71.84 = -28.62 J/mol over the assumed range.
    spread = gas["assumed_range_model_form_spread"][0]
    assert spread["equation_22_minus_23_j_mol_k"] == pytest.approx(-1.1991, abs=2e-4)
    assert gas["assumed_range_delta_h_equation_22_minus_23_j_mol"] == pytest.approx(-28.62, abs=0.01)
    assert gas["assumed_range_delta_h_spread_percent"] == pytest.approx(-0.220, abs=0.001)
    # Printed observed pressure coefficient 4.81 over the ideal 198.70 J/(mol*K).
    departure = {row["temperature_k"]: row for row in gas["real_gas_departure_not_applied"]}
    assert departure[373.15]["percent_of_ideal_cp_per_atm"] == pytest.approx(2.42, abs=0.01)
    assert gas["covers_flame_temperatures"] is False


def test_gas_enthalpy_difference_is_signed_and_additive():
    prior = real.prior_review()
    review = record()["review"]
    forward = real.gas_delta_native(prior, review, 320, 440)
    assert real.gas_delta_native(prior, review, 440, 320) == -forward
    assert forward == (real.gas_delta_native(prior, review, 320, 370)
                       + real.gas_delta_native(prior, review, 370, 440))
    assert forward > 0


@pytest.mark.parametrize("temperature", [288, 298.15, 470.01, 500, 1000])
def test_gas_outside_reviewed_support_is_rejected_not_extrapolated(temperature):
    with pytest.raises(ValueError, match="support"):
        real.gas_cp_native(real.prior_review(), record()["review"], temperature)


def test_preview_units_molar_mass_and_scale_factor():
    candidate = preview()
    review = record()["review"]
    assert len(candidate["samples"]) == 19
    # 164.9664, 197.28 and 239.938 J/(mol*K) divided by 100.20 g/mol.
    for index, native, cp_native in [(0, 298.16, 1.646370938), (8, 370, 1.968862275),
                                     (18, 470, 2.394592774)]:
        factor = float(real.its90_scale_factor(review, native))
        assert knot(candidate, index)["cp_kj_kg_k"] / factor == pytest.approx(cp_native, rel=1e-9)
    assert knot(candidate, 8)["cp_kj_kg_k"] == pytest.approx(1.968862275 * 0.999880, rel=1e-4)
    # The engine nominal 100.0 g/mol or a mol/kg slip would not pass these bounds.
    assert abs(knot(candidate, 8)["cp_kj_kg_k"] - 1.9728) > 0.003
    assert candidate["molar_mass_g_mol"] == 100.20
    assert candidate["quantity_unit"] == "kJ/(kg*K)"
    assert candidate["temperature_scale"] == "ITS-90_kelvin"


def test_canonical_integral_preserves_printed_enthalpy_increments():
    candidate = preview()
    samples = candidate["samples"]
    low = real.canonical_enthalpy(samples, knot(candidate, 0)["temperature_k"])
    middle = real.canonical_enthalpy(samples, knot(candidate, 8)["temperature_k"])
    high = real.canonical_enthalpy(samples, knot(candidate, 18)["temperature_k"])
    # Printed H differences in J/mol over 100.20 g/mol, plus the declared budget.
    assert high - low == pytest.approx(34912 / 100.20, abs=0.06)
    assert high - middle == pytest.approx(21900 / 100.20, abs=0.05)
    assert middle - low == pytest.approx(13012 / 100.20, abs=0.035)
    # Zero of enthalpy moved to 298.15 K ITS-90: about 164.97 J/(mol*K) * 0.0145 K,
    # known no better than the declared 0.6 mK of the labels.
    assert low == pytest.approx(-2.392 / 100.20, abs=1e-3)
    assert low < 0 < middle < high


def test_declared_discretization_bound_holds_and_coarse_table_breaks_it():
    result = real.audit()["gas"]
    assert result["cp_interpolation_max_abs_j_mol_k"] <= 0.007
    # Analytic: h^2*|f''|/8 = 0.005814 for 10 K knots of equation 22, plus half of
    # the 0.002236 step the source leaves between equations 23 and 22 at 370 K.
    assert result["cp_interpolation_max_abs_j_mol_k"] == pytest.approx(0.006932, abs=1e-6)
    candidate = preview()
    candidate["samples"] = [knot(candidate, 0), knot(candidate, 8), knot(candidate, 18)]
    with pytest.raises(ValueError, match="discretization"):
        real.check_candidate(candidate)


def test_untouched_preview_passes_its_own_contract():
    assert real.check_candidate(preview())["valid"] is True


def scaled(candidate, factor):
    for sample in candidate["samples"]:
        sample["cp_kj_kg_k"] *= factor


def shifted(candidate, native_labels, offset):
    for sample, label in zip(candidate["samples"], native_labels):
        sample["temperature_k"] = label + offset


NATIVE = [298.16, 300, 310, 320, 330, 340, 350, 360, 370, 380, 390, 400, 410, 420,
          430, 440, 450, 460, 470]


@pytest.mark.parametrize("mutate,message", [
    (lambda c: scaled(c, 1000.0), "basis"),                        # J/(kg*K) labelled kJ
    (lambda c: scaled(c, 0.001), "basis"),                         # kJ taken twice
    (lambda c: scaled(c, 100.20), "basis"),                        # molar value left per mole
    (lambda c: scaled(c, 100.20 / 100.0), "basis"),                # engine nominal molar mass
    (lambda c: scaled(c, 100.20 / 100.205), "basis"),              # another atomic-weight table
    (lambda c: scaled(c, 255.30 / 197.28), "basis"),               # liquid Csat values
    (lambda c: c.__setitem__("molar_mass_g_mol", 100.0), "molar mass"),
    (lambda c: c.__setitem__("quantity_unit", "J/(mol*K)"), "unit"),
    (lambda c: c.__setitem__("phase", "liquid"), "Csat"),
    (lambda c: c.__setitem__("caloric_model", "declared_liquid"), "caloric"),
    (lambda c: c.__setitem__("quantity", "saturation_heat_capacity"), "quantity"),
    (lambda c: c.__setitem__("temperature_scale", "synthetic_kelvin"), "scale"),
    (lambda c: shifted(c, NATIVE, 0.0), "mapping"),                # native labels kept
    (lambda c: shifted(c, NATIVE, -0.01), "mapping"),              # only the 273.16 offset
    (lambda c: c.__setitem__("reference_temperature_k", 298.16), "reference"),
    (lambda c: c.__setitem__("reference_pressure_pa", 101325.0), "reference"),
    (lambda c: c["samples"].append({"temperature_k": 480.0, "cp_kj_kg_k": 2.43}), "extrapolation"),
    (lambda c: c["samples"].insert(0, {"temperature_k": 288.0, "cp_kj_kg_k": 1.6}), "extrapolation"),
    (lambda c: c.__setitem__("samples", c["samples"][1:]), "reference outside"),
    (lambda c: c.__setitem__("samples", list(reversed(c["samples"]))), "increasing"),
    (lambda c: scaled(c, -1.0), "positive"),
    (lambda c: c["samples"][3].__setitem__("cp_kj_kg_k", float("nan")), "finite"),
    (lambda c: c["samples"][3].__setitem__("cp_kj_kg_k", float("inf")), "finite"),
    (lambda c: c["samples"][3].__setitem__("temperature_k", True), "finite"),
    (lambda c: c["samples"][3].__setitem__("cp_kj_kg_k", "1.7"), "finite"),
    (lambda c: c["samples"][3].__setitem__("extra", 1.0), "sample"),
    (lambda c: c.__setitem__("schema", "g3_synthetic_isobaric_cp_v1"), "schema"),
    (lambda c: c.__setitem__("provenance", "synthetic:relabelled"), "provenance"),
    (lambda c: c.__setitem__("calibration_status", "fire_validated"), "calibration"),
    (lambda c: c.__setitem__("unreviewed", 1), "field"),
    (lambda c: c.pop("declared_errors"), "field"),
    (lambda c: c["declared_errors"].__setitem__("real_gas_departure_applied", True), "limits"),
    (lambda c: c["evidence_tiers"][0].__setitem__("evidence_kind", "measurement"), "limits"),
    (lambda c: c.__setitem__("native_support_k", [288, 1000]), "limits"),
    (lambda c: c["witnesses"][0].__setitem__(
        "specific_sensible_enthalpy_kj_kg",
        abs(c["witnesses"][0]["specific_sensible_enthalpy_kj_kg"])), "witness"),
    (lambda c: c["witnesses"][-1].__setitem__(
        "specific_sensible_enthalpy_kj_kg",
        -c["witnesses"][-1]["specific_sensible_enthalpy_kj_kg"]), "witness"),
    (lambda c: c.__setitem__("witnesses", c["witnesses"][1:]), "witness"),
])
def test_candidate_negative_controls_are_rejected_with_their_reason(mutate, message):
    candidate = preview()
    mutate(candidate)
    with pytest.raises(ValueError, match=message):
        real.check_candidate(candidate)


def test_current_synthetic_schema_would_reject_the_real_labels():
    candidate = preview()
    conflicts = real.synthetic_schema_conflicts(candidate)
    assert set(conflicts) == {"schema", "temperature_scale", "calibration_status", "provenance",
                              "unexpected_fields"}
    assert conflicts["temperature_scale"] == ["ITS-90_kelvin", "synthetic_kelvin"]
    # Same sample layout: only the label layer differs, not the integral input.
    assert all(set(sample) == {"temperature_k", "cp_kj_kg_k"} for sample in candidate["samples"])
    for shared in ["quantity", "quantity_unit", "interpolation", "pressure_path",
                   "reference_temperature_k", "reference_pressure_pa", "caloric_model"]:
        assert shared not in conflicts


def test_liquid_csat_alone_does_not_reproduce_the_printed_saturation_enthalpy():
    liquid = real.audit()["liquid"]
    # Printed: 69810 - 52596 J/mol; trapezoid of printed Csat: 17200.7656 J/mol.
    assert liquid["printed_delta_h_sat_298_16_to_370_j_mol"] == 17214
    assert liquid["csat_trapezoid_298_16_to_370_j_mol"] == pytest.approx(17200.7656, abs=1e-3)
    assert liquid["gap_without_v_dp_j_mol"] == pytest.approx(13.2344, abs=1e-3)
    assert liquid["gap_without_v_dp_j_mol"] > liquid["closure_abs_tol_j_mol"]
    assert liquid["v_dp_term_298_16_to_370_j_mol"] == pytest.approx(13.3424, abs=1e-3)
    assert abs(liquid["closure_residual_with_v_dp_j_mol"]) <= liquid["closure_abs_tol_j_mol"]
    assert liquid["v_dp_dt_298_16_j_mol_k"] == pytest.approx(0.04225, abs=2e-4)
    assert liquid["v_dp_dt_370_j_mol_k"] == pytest.approx(0.44664, abs=2e-4)


def test_compatibility_verdict_is_tied_to_the_reviewed_helper(tmp_path):
    helper = tmp_path / real.SYNTHETIC_HELPER
    helper.parent.mkdir(parents=True)
    original = (real.ROOT / real.SYNTHETIC_HELPER).read_bytes()
    helper.write_bytes(original + b"# changed")
    with pytest.raises(ValueError, match="helper changed"):
        real.synthetic_schema_conflicts(preview(), root=tmp_path)
    helper.write_bytes(original)
    assert "schema" in real.synthetic_schema_conflicts(preview(), root=tmp_path)


def test_liquid_volumetric_evidence_stops_at_twenty_five_celsius():
    liquid = real.audit()["liquid"]
    assert liquid["molar_volume_25_c_ml_mol"] == pytest.approx(147.4766, abs=1e-3)
    assert liquid["expansivity_20_25_c_per_k"] == pytest.approx(1.245681e-3, rel=1e-5)
    assert liquid["pressure_term_bound_at_298_15_j_mol"] == pytest.approx(13.8487, abs=2e-3)
    assert liquid["volumetric_data_range_c"] == [20, 25]
    assert liquid["missing_for_isobaric_conversion"] == [
        "liquid_molar_volume_273_to_371_K",
        "first_temperature_derivative_of_volume_273_to_371_K",
        "second_temperature_derivative_of_volume_273_to_371_K",
    ]
    assert liquid["isobaric_profile_approval"] is False
    assert liquid["quantity"] == "Csat_heat_capacity_along_the_saturation_curve"


def test_liquid_equation_and_independent_cross_checks():
    liquid = real.audit()["liquid"]
    assert liquid["csat_equation_380_j_mol_k"] == pytest.approx(260.0982, abs=1e-3)
    assert liquid["csat_equation_390_j_mol_k"] == pytest.approx(265.0412, abs=1e-3)
    # Graphically adjusted table prevails below 370 K: 224.74 printed, 224.8592 by equation.
    assert liquid["csat_equation_minus_table_298_16_j_mol_k"] == pytest.approx(0.1192, abs=1e-3)
    assert liquid["vapour_pressure_at_brooks_boiling_point_atm"] == pytest.approx(0.999919, abs=1e-5)
    assert liquid["osborne_ginnings_csat_22_5_c_j_mol_k_unconverted_joule"] == pytest.approx(
        223.8167, abs=1e-3)
    assert liquid["table_csat_interpolated_22_5_c_j_mol_k"] == pytest.approx(223.8144, abs=1e-3)


@pytest.mark.parametrize("path,value", [
    (("liquid", "quantity"), "isobaric_Cp"),
    (("liquid", "path"), "constant_pressure"),
    (("approvals", "liquid_isobaric_profile"), True),
    (("approvals", "engine_integration"), True),
    (("approvals", "real_gas_correction"), True),
    (("molar_mass", "value_g_mol"), 100.0),
    (("temperature", "native_kelvin_offset"), 273.15),
    (("temperature", "native_scale"), "ITS-90"),
    (("gas", "state"), "real gas at 100 kPa"),
    (("energy_unit", "factor"), 1000),
])
def test_review_semantics_cannot_be_relabelled_together_with_the_data(path, value):
    changed = record()
    changed["review"][path[0]][path[1]] = value
    with pytest.raises(ValueError, match="semantics"):
        real.audit(changed)


def test_transcribed_rows_are_pinned_content():
    changed = record()
    changed["review"]["gas"]["table_rows_above_370"][4][1] = 219.91
    with pytest.raises(ValueError, match="semantics"):
        real.audit(changed)
    changed = record()
    changed["review"]["temperature"]["t90_minus_t68_rows"][3][1] = -0.070
    with pytest.raises(ValueError, match="semantics"):
        real.audit(changed)


@pytest.mark.parametrize("name", sorted(real.SOURCES))
@pytest.mark.parametrize("field,value", [
    ("path", "../other.pdf"), ("url", "https://example.com/other"), ("sha256_raw", "0" * 64),
])
def test_source_identity_is_not_replaceable(name, field, value):
    changed = record()
    changed["sources"][name][field] = value
    with pytest.raises(ValueError, match="identity"):
        real.audit(changed)


def test_altered_source_bytes_are_rejected(tmp_path):
    for source in real.SOURCES.values():
        target = tmp_path / source["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"%PDF-1.4 not the reviewed file")
    with pytest.raises(ValueError, match="content mismatch"):
        real.audit(record(), root=tmp_path)


def test_prior_review_record_is_pinned():
    changed = record()
    changed["prior_review"]["sha256_lf"] = "0" * 64
    with pytest.raises(ValueError, match="prior"):
        real.audit(changed)


@pytest.mark.parametrize("text", [
    '{"schema": NaN}', '{"schema": Infinity}', '{"schema": 1, "schema": 2}',
])
def test_nonfinite_constants_and_duplicate_keys_are_rejected_on_load(tmp_path, text):
    path = tmp_path / "record.json"
    path.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError):
        real.load_profile(path)


@pytest.mark.parametrize("changed", [
    None, [], "record", {"schema": "g3_heptane_real_profile_source_review_v1"},
    {"schema": "other", "prior_review": {}, "sources": {}, "review": {}},
])
def test_unknown_record_shapes_are_rejected(changed):
    if changed is None:
        changed = record()
        changed["extra"] = True
    with pytest.raises(ValueError, match="schema"):
        real.audit(changed)


def test_audit_reads_only_and_leaves_sources_untouched():
    paths = [real.INPUT, real.SAVED] + [real.ROOT / source["path"]
                                         for source in real.SOURCES.values()]
    before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
    snapshot = copy.deepcopy(record())
    real.audit(snapshot)
    assert snapshot == record()
    assert before == [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]


def test_preview_is_a_design_output_not_an_engine_profile():
    candidate = preview()
    assert candidate["schema"] == "g3_real_ideal_gas_cp_v1"
    assert candidate["calibration_status"] == "primary_source_property_not_fire_validation"
    assert not candidate["provenance"].startswith("synthetic:")
    assert all(math.isfinite(sample["cp_kj_kg_k"]) for sample in candidate["samples"])
    assert not list((real.ROOT / "sim").rglob("*RealProfile*"))
    assert not list((real.ROOT / "sim").rglob("*real_profile*"))
