"""Offline check of historical gas calorimetry, not a runtime heat model.

No conversion of temperature scale, saturation path, reference enthalpy,
mass basis or energy into engine input is performed. Liquid Csat is not Cp.
The small polynomial calculation compares printed equations and tables;
it is not an independent experimental validation of those correlations.
"""
from __future__ import annotations

from decimal import Decimal
import hashlib
import json
from pathlib import Path

from scripts.simulation.audit_g3_heptane_phase_basis import number
from scripts.simulation.audit_g3_measured_mass_candidate import confined_artifact
from scripts.simulation.validate_g3_mass_material_profile import load_profile


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/validation/G3_D1_HEPTANE_SENSIBLE_INPUTS_2026-10-04.json"
SAVED = ROOT / "docs/validation/G3_D1_HEPTANE_SENSIBLE_AUDIT_2026-10-04.json"
SOURCE = "docs/literature/NIST/NBS_Heptane_Calorimetric_Properties_1954.pdf"
SOURCE_URL = "https://nvlpubs.nist.gov/nistpubs/jres/53/jresv53n3p139_A1b.pdf"
SOURCE_SHA = "40138b0b81980477244431bd66c9b55adb775edbaf3d4e218f4f2d7b434bd3f9"
REVIEW_SHA = "90796b89974e0e39dab58e04e8d84ffe4d716d53e098c546ad592e0a5d0f0a90"
# Printed Cp has two decimals, H whole joules and coefficients are rounded.
# Predeclared consistency bounds, NOT experimental uncertainties or sim tolerances.
CP_PRINT_ABS_TOL = Decimal("0.02")
H_PRINT_ABS_TOL = Decimal("2")


def linear_gas_delta(review, start_k, end_k):
    """Equation 23 only, signed J/mol difference on its native scale/path."""
    start = number(start_k, "start_k")
    end = number(end_k, "end_k")
    low, high = (number(v, "range_k") for v in review["gas_linear_equation_range_k"])
    if not low <= start <= high or not low <= end <= high:
        raise ValueError("outside equation 23 domain; no extrapolation")
    anchor_t = number(review["gas_cp_anchor_temperature_k"], "anchor_temperature")
    anchor_cp = number(review["gas_cp_anchor_j_mol_k"], "anchor_cp")
    slope = number(review["gas_cp_slope_j_mol_k2"], "slope")
    cp_start = anchor_cp + slope * (start - anchor_t)
    cp_end = anchor_cp + slope * (end - anchor_t)
    if cp_start <= 0 or cp_end <= 0:
        raise ValueError("nonpositive Cp in reviewed linear domain")
    delta = (cp_start + cp_end) * (end - start) / 2
    if not delta.is_finite():
        raise ValueError("nonfinite gas enthalpy difference")
    return delta


def audit(record=None, root=ROOT):
    root = Path(root).resolve()
    if record is None:
        record = load_profile(root / INPUT.relative_to(ROOT))
    if (not isinstance(record, dict) or set(record) != {"schema", "source", "review"}
            or record["schema"] != "g3_heptane_sensible_source_review_v1"):
        raise ValueError("unreviewed sensible source/schema")
    source = record["source"]
    if source != {"path": SOURCE, "url": SOURCE_URL, "sha256_raw": SOURCE_SHA}:
        raise ValueError("unreviewed source identity")
    confined_artifact(root, source, text=False)
    reviewed = json.dumps(record["review"], sort_keys=True, allow_nan=False).encode("utf-8")
    if hashlib.sha256(reviewed).hexdigest() != REVIEW_SHA:
        raise ValueError("unreviewed semantics, units or approvals")
    review = record["review"]
    ref = review["native_reference_temperature_k"]
    ref_h = number(review["gas_table_rows"][0][2], "native reference H")
    anchor_t = number(review["gas_cp_anchor_temperature_k"], "anchor T")
    anchor_cp = number(review["gas_cp_anchor_j_mol_k"], "anchor Cp")
    slope = number(review["gas_cp_slope_j_mol_k2"], "slope")
    checks = []
    for temperature, cp, enthalpy in review["gas_table_rows"]:
        t = number(temperature, "table T")
        predicted_cp = anchor_cp + slope * (t - anchor_t)
        cp_residual = predicted_cp - number(cp, "table Cp")
        h_residual = linear_gas_delta(review, ref, temperature) - (number(enthalpy, "table H") - ref_h)
        if abs(cp_residual) > CP_PRINT_ABS_TOL or abs(h_residual) > H_PRINT_ABS_TOL:
            raise ValueError("printed gas equation/table inconsistent")
        checks.append({"temperature_k": temperature, "cp_residual_j_mol_k": float(cp_residual),
                       "delta_h_residual_j_mol": float(h_residual)})
    a, b, c = (number(v, "high equation coefficient")
               for v in review["gas_high_equation_coefficients"])
    join_difference = anchor_cp - (a + b * anchor_t + c * anchor_t * anchor_t)
    return {
        "schema": "g3_heptane_sensible_source_audit_v1",
        "decision": "GO_synthetic_enthalpy_contract_NO_GO_automatic_material_profile",
        "source_sha256_raw": SOURCE_SHA,
        "gas_comparison_kind": "printed_equation_vs_derived_table_NOT_fire_experiment",
        "gas_native_reference_temperature_k": review["native_reference_temperature_k"],
        "gas_comparison_rows": checks,
        "gas_delta_h_298_16_to_370_j_mol": float(linear_gas_delta(review, 298.16, 370)),
        "gas_equation_join_cp_difference_j_mol_k": float(join_difference),
        "gas_equation_join_forced_continuous": False,
        "liquid_quantity": review["liquid_quantity"],
        "liquid_enthalpy_requires_V_dP_term": True,
        "liquid_fixed_pressure_profile_approval": False,
        "source_temperature_scale_conversion": None,
        "source_to_canonical_reference_adapter": None,
        "mol_to_kg_conversion_performed": False,
        "physical_benchmark_approval": False,
        "engine_integration": False,
        "production_activation": False,
    }


def main():
    try:
        result = audit()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"decision": "rejected", "error": str(exc)}))
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
