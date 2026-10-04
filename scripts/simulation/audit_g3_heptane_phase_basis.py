"""Offline Hess-cycle audit, NOT a step solver, evaporation law or profile.

The reviewed reference data are manually transcribed; source hashes do not
prove transcription or batch identity. No runtime inputs or heat are emitted.
"""
from __future__ import annotations

import argparse
from decimal import Decimal
import json
from pathlib import Path

from scripts.simulation.audit_g3_measured_mass_candidate import confined_artifact
from scripts.simulation.validate_g3_mass_material_profile import load_profile


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/validation/G3_D1_HEPTANE_PHASE_INPUTS_2026-10-04.json"
VALUES = {
    "liquid_gross_release", "vapour_gross_release", "liquid_net_release",
    "vapour_net_release", "liquid_formation_enthalpy", "vapour_formation_enthalpy",
    "fuel_vaporization_enthalpy", "water_vaporization_enthalpy",
}
KEYS = {
    "schema", "component", "formula", "reference_temperature_k",
    "reference_pressure_pa", "water_product_phase", "reaction_scope",
    "quantity_unit", "molar_mass_g_mol", "rounding_tolerance_kj_mol",
    "values", "reported_uncertainty", "source", "experimental_batch_approval",
    "engine_integration", "production_activation",
}


def number(value, label):
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        raise ValueError(f"{label}: finite numeric value required")
    result = Decimal(str(value))
    if not result.is_finite():
        raise ValueError(f"{label}: nonfinite value")
    return result


def audit(record, root=ROOT):
    if not isinstance(record, dict) or set(record) != KEYS:
        raise ValueError("missing or unsupported fields")
    expected = {
        "schema": "g3_heptane_reference_phase_basis_v1",
        "component": "reference_n_heptane_not_experimental_batch",
        "formula": "C7H16", "water_product_phase": "gas",
        "reaction_scope": "complete_oxidation", "quantity_unit": "kJ/mol",
    }
    for key, value in expected.items():
        if record[key] != value:
            raise ValueError(f"incompatible {key}")
    for key in ["experimental_batch_approval", "engine_integration", "production_activation"]:
        if record[key] is not False:
            raise ValueError(f"{key} must remain false")
    for key, value in [("reference_temperature_k", "298.15"),
                       ("reference_pressure_pa", "100000"),
                       ("rounding_tolerance_kj_mol", "0.005")]:
        if number(record[key], key) != Decimal(value):
            raise ValueError(f"unsupported {key}")
    molar_mass = number(record["molar_mass_g_mol"], "molar_mass_g_mol")
    if molar_mass != Decimal("100.20"):
        raise ValueError("molar mass must retain the reviewed rounded table basis")
    values = record["values"]
    if not isinstance(values, dict) or set(values) != VALUES:
        raise ValueError("missing or unsupported thermochemical values")
    v = {key: number(value, key) for key, value in values.items()}
    for key, value in v.items():
        if "formation" not in key and value <= 0:
            raise ValueError(f"{key}: positive release/cost magnitude required")
    source = record["source"]
    source_keys = {"path", "url", "sha256_raw", "version", "locators", "review"}
    if not isinstance(source, dict) or set(source) != source_keys:
        raise ValueError("missing or unsupported source fields")
    for key in ["path", "url", "sha256_raw", "version", "review"]:
        if not isinstance(source[key], str) or not source[key].strip():
            raise ValueError(f"source {key} required")
    if not source["url"].startswith("https://"):
        raise ValueError("source URL must use HTTPS")
    if not isinstance(source.get("locators"), dict):
        raise ValueError("source and reviewed locators required")
    for key in ["molar_mass", "enthalpy_basis", "formation_and_transition",
                "net_and_gross", "water_transition"]:
        if not isinstance(source["locators"].get(key), str) or not source["locators"][key].strip():
            raise ValueError(f"missing source locator {key}")
    confined_artifact(Path(root), source, text=False)
    uncertainty = record["reported_uncertainty"]
    uncertainty_keys = {"combustion_kj_mol", "fuel_vaporization_kj_mol",
                        "water_vaporization_kj_mol", "interpretation"}
    if not isinstance(uncertainty, dict) or set(uncertainty) != uncertainty_keys:
        raise ValueError("missing or unsupported uncertainty fields")
    if not isinstance(uncertainty.get("interpretation"), str):
        raise ValueError("reported uncertainty interpretation required")
    if not uncertainty["interpretation"].strip():
        raise ValueError("reported uncertainty interpretation required")
    for key in ["combustion_kj_mol", "fuel_vaporization_kj_mol", "water_vaporization_kj_mol"]:
        if number(uncertainty.get(key), key) < 0:
            raise ValueError("negative reported uncertainty")
    latent = v["fuel_vaporization_enthalpy"]
    residuals = {
        "net_phase_cycle": v["vapour_net_release"] - v["liquid_net_release"] - latent,
        "gross_phase_cycle": v["vapour_gross_release"] - v["liquid_gross_release"] - latent,
        "formation_phase_cycle": v["vapour_formation_enthalpy"] - v["liquid_formation_enthalpy"] - latent,
        # C7H16 complete oxidation produces eight mol H2O per mol fuel.
        "liquid_water_basis": v["liquid_gross_release"] - v["liquid_net_release"] - 8 * v["water_vaporization_enthalpy"],
        "vapour_water_basis": v["vapour_gross_release"] - v["vapour_net_release"] - 8 * v["water_vaporization_enthalpy"],
    }
    tolerance = Decimal("0.005")  # Printed-value rounding, NOT experimental uncertainty.
    if any(abs(value) > tolerance for value in residuals.values()):
        raise ValueError("inconsistent phase/water Hess cycle")
    kg_per_mol = molar_mass / 1000
    specific = {key: float(v[key] / kg_per_mol) for key in
                ["liquid_net_release", "vapour_net_release", "fuel_vaporization_enthalpy"]}
    return {
        "schema": record["schema"], "decision": "reference_cycle_consistent_not_batch_or_model_approval",
        "source_sha256_raw": source["sha256_raw"],
        "specific_kj_kg": specific,
        "cycle_residuals_kj_mol": {key: float(value) for key, value in residuals.items()},
        "rounding_tolerance_kj_mol": float(tolerance),
        "experimental_batch_approval": False, "engine_integration": False,
        "production_activation": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, default=INPUT)
    args = parser.parse_args()
    try:
        result = audit(load_profile(args.input))
    except (OSError, ValueError) as exc:
        print(json.dumps({"decision": "rejected", "error": str(exc)}))
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
