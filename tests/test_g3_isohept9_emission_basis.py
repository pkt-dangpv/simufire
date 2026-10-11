"""Offline source/attribution controls, not a second phase solver or Godot test."""
import copy
import hashlib

import pytest

from scripts.simulation import audit_g3_isohept9_emission_basis as basis


def test_saved_audit_is_reproducible_and_not_a_heat_measurement():
    result = basis.audit()
    assert result == basis.phase.load_profile(basis.SAVED)
    assert result["conditional_reference_work"]["measured_pan_decrease_kg"] == 19.359537
    assert result["conditional_reference_work"]["latent_reference_kj_kg"] == pytest.approx(365.76846307385)
    assert result["conditional_reference_work"]["conditional_phase_work_kj"] == pytest.approx(
        7081.1080943113775, rel=0, abs=1e-9)
    assert result["independently_observed_pan_budget_B_kj"] is None
    assert result["observed_liquid_temperature_series"] is None
    assert result["observed_emitted_component_fraction"] is None
    assert result["conditional_reference_work"]["assumption_status"].startswith("declared_")
    for key in ["sensible_energy_identified", "predictive_evaporation_approval",
                "experimental_batch_approval", "engine_integration", "production_activation"]:
        assert result[key] is False


def test_source_revision_and_semantic_review_are_pinned():
    result = basis.audit()
    assert result["source_sha256_lf"] == "66ad9437f81e93750e1d53b7f08b9e5c1068218ec809ed29d308fd9360dccce3"
    assert result["apparatus_report_sha256_raw"] == "7ba8219496f8b52035fd97ed603182782e907034a94593bb51e7382c0cf453f5"
    assert result["phase_reference_sha256_raw"] == "c964ba6afab1f029ed666fb9768fab2e7683b57c3169814d37693c386b6db21a"
    assert result["source_revision"] == "e5de6811036d252b4f9085866f08da66efdda7d3"
    assert result["decision"] == "GO_conditional_reference_diagnostic_NO_GO_predictive_evaporation"


@pytest.mark.parametrize("field,value", [
    ("case_id", "ISOHept5"), ("source_revision", "new_revision"),
    ("source_sha256_lf", "0" * 64),
])
def test_another_experiment_or_revision_cannot_inherit_manual_review(monkeypatch, field, value):
    original = basis.measured.audit

    def altered(*args, **kwargs):
        result = original(*args, **kwargs)
        result[field] = value
        return result

    monkeypatch.setattr(basis.measured, "audit", altered)
    with pytest.raises(ValueError, match="unreviewed"):
        basis.audit()


@pytest.mark.parametrize("column,group", [
    ("THFRFL", "heat_flux_gauge_temperature_not_fuel"),
    ("TSHFRFL", "enclosure_inner_surface_temperature_not_fuel"),
    ("TSXHFRFL", "enclosure_outer_surface_temperature_not_fuel"),
    ("TR30", "room_thermocouple_tree_temperature_not_fuel"),
    ("TFSampPtRh", "gas_sampling_probe_temperature"),
    ("HFRFL", "floor_ceiling_heat_flux_not_pan_net_heat"),
    ("IHRR", "ideal_hrr_derived_from_mass_not_independent"),
    ("HRR2", "exhaust_hrr_not_pan_absorbed_heat"),
    ("Mass1", "pan_load_cell_mass_not_species_analyzer"),
])
def test_different_physical_quantities_are_not_silently_interchangeable(column, group):
    result = basis.audit()
    assert column in result["reviewed_channel_groups"][group]


@pytest.mark.parametrize("alteration", ["duplicate", "missing", "unreviewed", "renamed"])
def test_changed_channel_contract_requires_new_review(alteration):
    header = [name for channels in basis.GROUPS.values() for name in channels]
    if alteration == "duplicate":
        header.append("Mass1")
    elif alteration == "missing":
        header.remove("HFRFL")
    elif alteration == "unreviewed":
        header.append("LiquidTemperature")
    else:
        header[header.index("THFRFL")] = "LiquidTemperature"
    with pytest.raises(ValueError):
        basis.classify_channels(header)


def test_classification_does_not_mutate_header_or_share_writable_groups():
    header = [name for channels in basis.GROUPS.values() for name in channels]
    original = list(header)
    groups_before = copy.deepcopy(basis.GROUPS)
    result = basis.classify_channels(header)
    result["time"].append("invented")
    assert basis.GROUPS == groups_before
    assert header == original


def test_offline_audit_does_not_write_engine_source_data_or_reference():
    paths = [basis.ROOT / name for name in [
        "sim/fire/FuelMassBudgetModel.gd", "sim/fire/PrescribedFuelReleaseModel.gd",
        "sim/validation/reports/reference_checks.json",
        "docs/literature/data/NIST_FSE_2008/ISOHept9.csv",
    ]]
    before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
    basis.audit()
    assert [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths] == before


def test_source_hash_verifier_rejects_wrong_artifact(tmp_path):
    path = tmp_path / "signal.csv"
    path.write_text("Time,Mass1\n0,1\n5,0.5\n", encoding="utf-8")
    with pytest.raises(ValueError, match="content mismatch"):
        basis.measured.confined_artifact(tmp_path, {
            "path": "signal.csv", "sha256_lf": "0" * 64,
        }, text=True)
