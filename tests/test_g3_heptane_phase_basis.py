"""Static source-cycle audit; no Godot, phase model or calibrated emission."""
import copy
from decimal import Decimal
import hashlib

import pytest

from scripts.simulation import audit_g3_heptane_phase_basis as phase


def inputs():
    return phase.load_profile(phase.INPUT)


def test_reviewed_reference_cycle_and_units():
    report = phase.audit(inputs())
    assert report["decision"] == "reference_cycle_consistent_not_batch_or_model_approval"
    assert report["specific_kj_kg"]["liquid_net_release"] == pytest.approx(44559.68063872256)
    assert report["specific_kj_kg"]["vapour_net_release"] == pytest.approx(44925.4491017964)
    assert report["specific_kj_kg"]["fuel_vaporization_enthalpy"] == pytest.approx(365.76846307385)
    assert report["cycle_residuals_kj_mol"]["net_phase_cycle"] == 0
    assert report["cycle_residuals_kj_mol"]["formation_phase_cycle"] == 0
    assert report["cycle_residuals_kj_mol"]["liquid_water_basis"] == pytest.approx(-.002)
    assert all(report[k] is False for k in
               ["experimental_batch_approval", "engine_integration", "production_activation"])


def test_saved_audit_is_reproducible():
    saved = phase.load_profile(phase.ROOT / "docs/validation/G3_D1_HEPTANE_PHASE_AUDIT_2026-10-04.json")
    assert phase.audit(inputs()) == saved


def test_reference_transcription_is_pinned_not_an_unversioned_parameter_fit():
    record = inputs()
    assert record["values"] == {
        "liquid_gross_release": 4816.83, "vapour_gross_release": 4853.48,
        "liquid_net_release": 4464.88, "vapour_net_release": 4501.53,
        "liquid_formation_enthalpy": -224.11, "vapour_formation_enthalpy": -187.46,
        "fuel_vaporization_enthalpy": 36.65, "water_vaporization_enthalpy": 43.994,
    }
    assert record["source"]["sha256_raw"] == "c964ba6afab1f029ed666fb9768fab2e7683b57c3169814d37693c386b6db21a"


@pytest.mark.parametrize("key,value", [
    ("water_product_phase", "liquid"), ("quantity_unit", "MJ/kg"),
    ("reference_temperature_k", 371.55), ("reference_pressure_pa", 101325),
    ("molar_mass_g_mol", .10020), ("rounding_tolerance_kj_mol", .01),
    ("reaction_scope", "partial_oxidation"), ("formula", "C7H8"),
    ("experimental_batch_approval", True), ("production_activation", 0),
    ("engine_integration", True), ("extra", "unreviewed"),
])
def test_incompatible_contract_rejected(key, value):
    record = inputs(); record[key] = value
    with pytest.raises(ValueError):
        phase.audit(record)


@pytest.mark.parametrize("key,value", [
    ("fuel_vaporization_enthalpy", 31.77),  # At boiling, NOT the same reference state.
    ("vapour_net_release", 4464.88),       # Liquid heat mislabelled as gas.
    ("liquid_net_release", 4816.83),       # Gross substituted for net.
    ("liquid_gross_release", -4816.83),    # Wrong positive-release convention.
    ("water_vaporization_enthalpy", 0),
    ("liquid_formation_enthalpy", -225.9), # Mixed independent compilation.
    ("vapour_net_release", True), ("vapour_net_release", float("nan")),
    ("vapour_net_release", float("inf")),
])
def test_hess_cycle_and_numeric_controls(key, value):
    record = inputs(); record["values"][key] = value
    with pytest.raises(ValueError):
        phase.audit(record)


def test_source_hash_and_confinement_are_fail_closed():
    for patch in [{"sha256_raw": "0" * 64}, {"path": "../outside.pdf"},
                  {"path": str(phase.INPUT.resolve())}]:
        record = inputs(); record["source"].update(patch)
        with pytest.raises(ValueError):
            phase.audit(record)


def test_missing_locator_or_uncertainty_rejected():
    for key in ["net_and_gross", "enthalpy_basis"]:
        record = inputs(); del record["source"]["locators"][key]
        with pytest.raises(ValueError):
            phase.audit(record)
    record = inputs(); record["reported_uncertainty"]["interpretation"] = ""
    with pytest.raises(ValueError):
        phase.audit(record)


def test_audit_has_no_input_or_engine_side_effects():
    record = inputs(); before = copy.deepcopy(record)
    paths = [phase.ROOT / "sim/fire/FuelMassBudgetModel.gd",
             phase.ROOT / "sim/fire/PrescribedFuelReleaseModel.gd",
             phase.ROOT / "sim/validation/reports/reference_checks.json"]
    hashes = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
    phase.audit(record)
    assert record == before
    assert [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths] == hashes


@pytest.mark.parametrize("section,key", [
    ("source", "path"), ("source", "sha256_raw"),
    ("reported_uncertainty", "combustion_kj_mol"),
])
def test_incomplete_evidence_is_rejected_without_keyerror(section, key):
    record = inputs(); del record[section][key]
    with pytest.raises(ValueError):
        phase.audit(record)


def test_hess_cycle_does_not_certify_transcription_or_a_batch():
    record = inputs()
    # A coherently shifted combustion dataset still passes the algebra.
    # The pinned transcription test above, not the cycle alone, catches this.
    for key in ["liquid_gross_release", "vapour_gross_release",
                "liquid_net_release", "vapour_net_release"]:
        record["values"][key] += 10
    assert phase.audit(record)["experimental_batch_approval"] is False


def test_reference_ledger_algebra_including_unoxidized_vapour():
    v = {k: Decimal(str(x)) for k, x in inputs()["values"].items()}
    # Symbolic reference bookkeeping, NOT a second step solver or MLR model.
    for released, oxidized in [("0", "0"), (".5", "0"), (".5", ".2"), ("1", "1")]:
        r, b = Decimal(released), Decimal(oxidized)
        budget = Decimal(100)
        before = v["liquid_net_release"] + budget
        remaining_potential = ((1-r) * v["liquid_net_release"]
                               + (r-b) * v["vapour_net_release"])
        thermal = budget - r * v["fuel_vaporization_enthalpy"] + b * v["vapour_net_release"]
        assert remaining_potential + thermal == before
        if r > 0:
            # Paying vaporization while using liquid heat for vapour loses energy.
            wrong = remaining_potential - (r-b) * v["fuel_vaporization_enthalpy"] + thermal - b * v["fuel_vaporization_enthalpy"]
            assert wrong - before == -r * v["fuel_vaporization_enthalpy"]


def test_strict_json_loader_reused(tmp_path):
    for text in ['{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}']:
        path = tmp_path / "invalid.json"; path.write_text(text, encoding="utf-8")
        with pytest.raises(ValueError):
            phase.load_profile(path)
