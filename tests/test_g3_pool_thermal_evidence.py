"""Offline measurement/attribution tests, not a runtime calibration."""
import copy
import hashlib
import json
import math

import pytest

from scripts.simulation import audit_g3_pool_thermal_evidence as thermal


def record():
    return thermal.load_profile(thermal.INPUT)


def inventory():
    path = thermal.ROOT / record()["artifacts"]["inventory"]["path"]
    return json.loads(path.read_text(encoding="utf-8"))


def boundary_text():
    path = thermal.ROOT / record()["artifacts"]["boundary_csv"]["path"]
    return path.read_text(encoding="utf-8")


def test_saved_audit_is_reproducible_and_not_a_liquid_heat_budget():
    result = thermal.audit()
    assert result == thermal.load_profile(thermal.SAVED)
    assert result["decision"] == "GO_independent_gauge_observables_NO_GO_liquid_net_budget"
    assert result["profile_sample_count"] == 11
    assert result["profile_repeat_per_location"] == 1
    assert result["profile_sd_kw_m2"] is None
    assert result["independent_of_mass_loss_inversion"] is True
    gauge = result["gauge_profile_diagnostic"]
    assert gauge["axisymmetric_piecewise_linear_gauge_power_kw"] == pytest.approx(
        1.2414317529925425, rel=0, abs=1e-14)
    assert gauge["covered_area_fraction"] == pytest.approx(0.9933665191333428)
    assert gauge["liquid_net_B_kj"] is None
    assert gauge["integrated_uncertainty_kw"] is None
    assert gauge["edge_extrapolation"] is False
    for key in ["liquid_cp_T_identified", "sensible_energy_identified",
                "physical_benchmark_approval", "engine_integration", "production_activation"]:
        assert result[key] is False


def test_conflicts_and_other_sources_are_not_silently_resolved():
    result = thermal.audit()
    assert result["surface_temperature_conflict"]["table12_c"] == 65
    assert result["surface_temperature_conflict"]["table13_c"] is None
    assert result["surface_temperature_conflict"]["accepted_heptane_temperature_k"] is None
    assert result["height_conflict"]["section3_8_above_surface_m"] == 0.003
    assert result["height_conflict"]["tableF38_above_surface_m"] == 0.013
    assert result["height_conflict"]["accepted_comparison_height_m"] is None
    assert result["tn_table2_ideal_hrr_kw"] == 106.6
    assert result["boundary_csv"]["hrr_kw"] == 112.6
    assert result["cross_source_hrr_substitution"] is False
    assert result["boundary_csv"]["kind"] == "constant_boundary_NOT_transient_measurement"


@pytest.mark.parametrize("field,value", [
    ("schema", "other"), ("revision", "master"), ("retrieved_at", "tomorrow"),
])
def test_other_revision_cannot_inherit_semantic_review(field, value):
    source = record()
    source[field] = value
    with pytest.raises(ValueError, match="unreviewed"):
        thermal.audit(source)


@pytest.mark.parametrize("field,value", [
    ("pool_diameter_m", 0.003), ("fuel_supply", "closed_inventory"),
    ("cooling", "none"), ("tn_table2_ideal_hrr_kw", 112.6),
    ("independently_observed_liquid_net_B_kj", 0),
    ("liquid_cp_T_identified", True), ("engine_integration", True),
    ("production_activation", True),
])
def test_semantic_changes_and_false_approvals_are_rejected(field, value):
    source = record()
    source["review"][field] = value
    with pytest.raises(ValueError, match="semantics"):
        thermal.audit(source)


def test_review_digest_does_not_trust_the_same_mutable_input_as_its_oracle(monkeypatch):
    source = record()
    source["review"]["production_activation"] = True
    monkeypatch.setattr(thermal, "load_profile", lambda p: copy.deepcopy(source))
    with pytest.raises(ValueError, match="semantics"):
        thermal.audit()


def test_null_repeat_uncertainty_cannot_be_converted_to_exact_zero():
    source = record()
    source["review"]["heptane_flux_rows"][0][3] = 0
    with pytest.raises(ValueError, match="semantics"):
        thermal.audit(source)


@pytest.mark.parametrize("field,value", [
    ("path", "../outside.pdf"), ("sha256_raw", "0" * 64),
    ("url", "https://example.com/other.pdf"),
])
def test_artifact_identity_and_source_are_pinned(field, value):
    source = record()
    source["artifacts"]["report"][field] = value
    with pytest.raises(ValueError, match="artifact"):
        thermal.audit(source)


def test_missing_license_is_rejected():
    source = record()
    del source["artifacts"]["license"]
    with pytest.raises(ValueError, match="artifacts"):
        thermal.audit(source)


def test_changed_source_bytes_are_rejected_by_shared_verifier(tmp_path):
    path = tmp_path / "data.csv"
    path.write_text("different", encoding="utf-8")
    with pytest.raises(ValueError, match="content mismatch"):
        thermal.confined_artifact(tmp_path, {"path": "data.csv", "sha256_lf": "0" * 64}, text=True)


def test_radial_constant_flux_uses_disk_area_not_radius_or_diameter():
    result = thermal.integrate_gauge_profile([[0, 10], [0.2, 10]], 0.2)
    assert result["axisymmetric_piecewise_linear_gauge_power_kw"] == pytest.approx(10 * math.pi * 0.2**2)
    assert result["covered_area_fraction"] == 1


def test_linear_profile_integral_is_exact_in_radial_geometry():
    result = thermal.integrate_gauge_profile([[0, 0], [0.2, 0.2]], 0.2)
    assert result["axisymmetric_piecewise_linear_gauge_power_kw"] == pytest.approx(2 * math.pi * 0.2**3 / 3)


def test_inserting_a_collinear_sample_does_not_change_the_integral():
    a = thermal.integrate_gauge_profile([[0, 3], [0.2, 7]], 0.2)
    b = thermal.integrate_gauge_profile([[0, 3], [0.1, 5], [0.2, 7]], 0.2)
    assert a["axisymmetric_piecewise_linear_gauge_power_kw"] == pytest.approx(
        b["axisymmetric_piecewise_linear_gauge_power_kw"], rel=0, abs=1e-15)


def test_partial_support_is_not_extrapolated_to_the_full_pool():
    result = thermal.integrate_gauge_profile([[0, 10], [0.1, 10]], 0.2)
    assert result["covered_area_fraction"] == 0.25
    assert result["axisymmetric_piecewise_linear_gauge_power_kw"] == pytest.approx(10 * math.pi * 0.1**2)


@pytest.mark.parametrize("rows,radius", [
    ([[0.1, 10], [0.2, 10]], 0.2), ([[0, 10], [0, 11]], 0.2),
    ([[0, 10], [0.2, 10], [0.1, 10]], 0.2), ([[0, -1], [0.1, 10]], 0.2),
    ([[0, 10], [0.3, 10]], 0.2), ([[False, 10], [0.1, 10]], 0.2),
    ([[0, math.nan], [0.1, 10]], 0.2), ([[0, 10], [math.inf, 10]], 0.2),
    ([[0, 10]], 0.2), ([[0, 10], [0.1, 10]], 0),
    ([[0, 10], [0.1, 10]], True), ([[0, 10], [0.1, 10]], 10**1000),
    ([[0, 1e308], [1e308, 1e308]], 1e308),
])
def test_invalid_profiles_fail_without_clipping_or_silent_fallback(rows, radius):
    with pytest.raises(ValueError):
        thermal.integrate_gauge_profile(rows, radius)


@pytest.mark.parametrize("old,new", [
    ("kg/s/m2", "g/s/m2"), ("Time,HRR", "Time,Time"),
    ("600,112.6", "600,106.6"), ("600,112.6", "0,112.6"),
    ("0.00253", "NaN"), ("0.00253", "-1"), ("0.00253", "0"),
    ("0.31", "1.31"),
])
def test_changed_boundary_contract_is_not_a_measured_transient(old, new):
    with pytest.raises(ValueError):
        thermal.inspect_boundary_csv(boundary_text().replace(old, new))


@pytest.mark.parametrize("change", ["duplicate", "new_heptane", "wrong_revision", "computational"])
def test_inventory_changes_require_review(change):
    records = inventory()
    if change == "duplicate":
        records.append(copy.deepcopy(records[0]))
    elif change == "new_heptane":
        name = "Heptane_Surface_Temperature.csv"
        records.append({"name": name, "type": "file", "path": thermal.EXPERIMENTS + name,
                        "download_url": thermal.REMOTE + thermal.EXPERIMENTS + name})
    elif change == "wrong_revision":
        records[0]["download_url"] = records[0]["download_url"].replace(thermal.REVISION, "master")
    else:
        records[0]["path"] = "Computational_Results/result.csv"
    with pytest.raises(ValueError):
        thermal.inspect_inventory(records)


def test_offline_audit_does_not_mutate_inputs_engine_or_reports():
    paths = [thermal.INPUT, *(thermal.ROOT / p for p, _ in thermal.ARTIFACTS.values()),
             *(thermal.ROOT / p for p in ["sim/fire/FuelMassBudgetModel.gd",
               "sim/fire/PrescribedFuelReleaseModel.gd", "sim/fire/PrescribedPhaseBudgetController.gd",
               "sim/validation/reports/reference_checks.json"])]
    before = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
    source = record()
    original = copy.deepcopy(source)
    thermal.audit(source)
    assert source == original
    assert before == [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
