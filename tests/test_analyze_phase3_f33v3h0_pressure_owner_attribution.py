from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3h0_pressure_owner_attribution as audit,
)


ROOT = Path(__file__).resolve().parents[1]
RUN_CSV = ROOT / "runs" / "phase3_f33v3h0" / "180_owners" / "sim_log.csv"


def test_owner_pressure_delta_matches_the_canonical_eos_constants():
    # p = (R/V) * (M*T_ref + E/cp) with R = P_ref / (rho_ref * T_ref)
    reference_temp_c = 20.0
    reference_temp_k = reference_temp_c + 273.15
    gas_constant = audit.AIR_PRESSURE_REF_PA / (
        audit.AIR_DENSITY_REF_KG_M3 * reference_temp_k
    )
    volume_m3 = 50.0
    assert audit.owner_pressure_delta_pa(
        1.0, 0.0, volume_m3, reference_temp_c
    ) == pytest.approx(gas_constant * reference_temp_k / volume_m3)
    assert audit.owner_pressure_delta_pa(
        0.0, 1.0, volume_m3, reference_temp_c
    ) == pytest.approx(gas_constant / (volume_m3 * audit.AIR_CP_KJ_KG_K))


def test_owner_pressure_delta_is_additive_with_no_cross_terms():
    # exact superposition is the premise the F3.3v3h0 design rests on
    a = audit.owner_pressure_delta_pa(2.0, 30.0, 40.0, 20.0)
    b = audit.owner_pressure_delta_pa(-0.5, -12.0, 40.0, 20.0)
    both = audit.owner_pressure_delta_pa(1.5, 18.0, 40.0, 20.0)
    assert a + b == pytest.approx(both)


def _row(**families: tuple[float, float]) -> dict[str, str]:
    row = {"time_s": "0.0", "room_id": "0", "volume_m3": "50.0",
           "phase3_shadow_thermo_pressure_gauge_pa": "0.0"}
    for family in audit.FAMILIES:
        mass_kg, energy_kj = families.get(family, (0.0, 0.0))
        row[f"phase3_shadow_mass_residence_{family}_upper_in_kg_total"] = str(mass_kg)
        row[f"phase3_shadow_mass_residence_{family}_upper_out_kg_total"] = "0.0"
        row[f"phase3_shadow_enthalpy_{family}_upper_in_kj_total"] = str(energy_kj)
        row[f"phase3_shadow_enthalpy_{family}_upper_out_kj_total"] = "0.0"
    return row


def test_family_totals_net_in_against_out_across_both_zones():
    row = _row(combustion=(3.0, 60.0))
    row["phase3_shadow_mass_residence_combustion_lower_out_kg_total"] = "1.0"
    row["phase3_shadow_enthalpy_combustion_lower_out_kj_total"] = "10.0"
    assert audit.family_totals(row, "combustion") == (2.0, 50.0)


def test_attribution_detects_an_unclosed_ledger():
    first = _row()
    second = _row(combustion=(1.0, 0.0))
    second["time_s"] = "1.0"
    # the exported gauge pressure disagrees with the attributed sum
    second["phase3_shadow_thermo_pressure_gauge_pa"] = "999.0"
    result = audit.attribute_room([first, second], 0, 20.0)
    assert result["worst_closure_residual_pa"] > audit.CLOSURE_TOLERANCE_PA


def test_intra_room_families_are_declared_pressure_neutral():
    assert set(audit.INTRA_ROOM_FAMILIES) == {"plume", "interzone"}
    for family in audit.INTRA_ROOM_FAMILIES:
        assert family in audit.FAMILIES


@pytest.mark.skipif(
    not RUN_CSV.exists(), reason="scratch F3.3v3h0 owner run absent"
)
def test_real_run_confirms_the_design_premises():
    result = audit.build_audit(
        csv_path=RUN_CSV, room_ids=[0, 1, 2], reference_temp_c=20.0
    )
    verdict = result["verdict"]
    for key in audit.REQUIRED_VERDICTS:
        assert verdict[key], key
    summary = result["summary"]
    # owners cancel by orders of magnitude: a subset solve cannot be correct
    assert summary["min_cancellation_ratio"] > 100.0
    # plume and inter-zone heat move no room-total mass or energy at all
    assert summary["worst_intra_room_abs_delta_pa"] == 0.0
    # the multisurface gas/surface exchange is still an unlabeled owner
    assert not verdict["no_material_unlabeled_owner"]
    assert summary["peak_unlabeled_other_delta_pa"] > 1000.0
