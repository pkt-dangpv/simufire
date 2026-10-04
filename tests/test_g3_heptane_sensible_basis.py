"""Historical source check only; no GDScript implementation is claimed."""
import copy
from decimal import Decimal
import hashlib

import pytest

from scripts.simulation import audit_g3_heptane_sensible_basis as sensible


def source():
    return sensible.load_profile(sensible.INPUT)


def test_saved_source_audit_reproduces_without_physical_promotions():
    result = sensible.audit()
    assert result == sensible.load_profile(sensible.SAVED)
    assert len(result["gas_comparison_rows"]) == 9
    assert result["gas_delta_h_298_16_to_370_j_mol"] == 13011.88953856
    assert result["gas_equation_join_cp_difference_j_mol_k"] == -0.002236
    assert result["liquid_quantity"] == "Csat_not_isobaric_Cp"
    assert result["liquid_enthalpy_requires_V_dP_term"] is True
    for key in ["gas_equation_join_forced_continuous", "mol_to_kg_conversion_performed",
                "liquid_fixed_pressure_profile_approval", "physical_benchmark_approval",
                "engine_integration", "production_activation"]:
        assert result[key] is False
    assert result["source_temperature_scale_conversion"] is None
    assert result["source_to_canonical_reference_adapter"] is None


@pytest.mark.parametrize("field,value", [
    ("native_reference_temperature_k", 298.15), ("gas_standard_pressure_pa", 100000),
    ("native_temperature_scale", "ITS90"), ("gas_cp_unit", "kJ/(kg*K)"),
    ("liquid_quantity", "Cp"), ("liquid_path", "constant_pressure"),
    ("liquid_enthalpy_requires_V_dP_term", False), ("gas_cp_slope_j_mol_k2", 0),
    ("source_to_canonical_reference_adapter", "same"),
    ("source_temperature_scale_conversion", "minus_0.01_K"),
    ("liquid_fixed_pressure_profile_approval", True), ("production_activation", True),
    ("engine_integration", True), ("experimental_batch_approval", True),
])
def test_different_semantics_require_review_not_coherent_relabeling(field, value):
    record = source()
    record["review"][field] = value
    with pytest.raises(ValueError, match="semantics"):
        sensible.audit(record)


def test_mutable_source_is_not_its_own_review_oracle(monkeypatch):
    record = source()
    record["review"]["production_activation"] = True
    monkeypatch.setattr(sensible, "load_profile", lambda _: copy.deepcopy(record))
    with pytest.raises(ValueError, match="semantics"):
        sensible.audit()


@pytest.mark.parametrize("field,value", [
    ("path", "../other.pdf"), ("url", "https://example.com/other"),
    ("sha256_raw", "0" * 64),
])
def test_source_identity_is_not_replaceable(field, value):
    record = source()
    record["source"][field] = value
    with pytest.raises(ValueError, match="identity"):
        sensible.audit(record)


def test_equation_23_is_signed_and_additive_not_clamped():
    review = source()["review"]
    forward = sensible.linear_gas_delta(review, 300, 360)
    assert forward == -sensible.linear_gas_delta(review, 360, 300)
    assert forward == (sensible.linear_gas_delta(review, 300, 330)
                       + sensible.linear_gas_delta(review, 330, 360))
    assert sensible.linear_gas_delta(review, 300, 300) == 0
    assert forward == Decimal("10757.28")


@pytest.mark.parametrize("start,end", [
    (287.99, 300), (300, 370.01), (False, 300), (300, True),
    (float("nan"), 300), (300, float("inf")), ("298.16", 370),
])
def test_equation_check_rejects_nonfinite_types_and_extrapolation(start, end):
    with pytest.raises(ValueError):
        sensible.linear_gas_delta(source()["review"], start, end)


def test_rounded_source_join_is_not_falsely_smoothed():
    result = sensible.audit()
    assert result["gas_equation_join_cp_difference_j_mol_k"] != 0
    assert max(abs(r["cp_residual_j_mol_k"]) for r in result["gas_comparison_rows"]) < 0.02
    assert max(abs(r["delta_h_residual_j_mol"]) for r in result["gas_comparison_rows"]) < 2


def test_source_change_is_rejected_not_detected_only_by_a_stored_number(tmp_path):
    file = tmp_path / "source.pdf"
    file.write_bytes(b"%PDF-wrong-original")
    with pytest.raises(ValueError, match="content mismatch"):
        sensible.confined_artifact(tmp_path, {"path": "source.pdf", "sha256_raw": sensible.SOURCE_SHA},
                                  text=False)


def test_audit_does_not_modify_source_or_existing_gdscript():
    paths = [sensible.INPUT, sensible.ROOT / sensible.SOURCE,
             *(sensible.ROOT / "sim/fire" / name for name in ["FuelMassBudgetModel.gd",
               "PrescribedFuelReleaseModel.gd", "PrescribedPhaseBudgetController.gd"]),
             sensible.ROOT / "sim/validation/reports/reference_checks.json"]
    before = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
    record = source()
    preserved = copy.deepcopy(record)
    sensible.audit(record)
    assert record == preserved
    assert before == [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
