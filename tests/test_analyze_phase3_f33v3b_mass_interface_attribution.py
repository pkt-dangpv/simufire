from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3b_mass_interface_attribution as audit,
)


ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / "runs" / "phase3_f33v3a" / "180_on" / "sim_log.csv"


def test_integrate_cfast_column_uses_trapezoids():
    rows = [
        {"Time": "0", "flow": "0"},
        {"Time": "10", "flow": "2"},
        {"Time": "20", "flow": "2"},
    ]
    assert audit.integrate_cfast_column(rows, 10, "flow") == pytest.approx(10.0)
    assert audit.integrate_cfast_column(rows, 20, "flow") == pytest.approx(30.0)


def test_integrate_cfast_column_rejects_missing_checkpoint():
    rows = [
        {"Time": "0", "flow": "0"},
        {"Time": "20", "flow": "2"},
    ]
    with pytest.raises(ValueError, match="checkpoint 10s"):
        audit.integrate_cfast_column(rows, 10, "flow")


def test_checkpoint_decomposition_keeps_internal_plume_out_of_room_mass(
    monkeypatch,
):
    row = {
        "phase3_shadow_mass_residence_initial_upper_kg": "20",
        "phase3_shadow_mass_residence_initial_lower_kg": "40",
        "phase3_shadow_mass_residence_observed_upper_kg": "20",
        "phase3_shadow_mass_residence_observed_lower_kg": "35",
        "phase3_shadow_mass_residence_upper_residual_kg": "0",
        "phase3_shadow_mass_residence_lower_residual_kg": "0",
        "phase3_shadow_mass_residence_room_residual_kg": "0",
    }
    for family in audit.f33s.MASS_FAMILIES:
        prefix = f"phase3_shadow_mass_residence_{family}_"
        for suffix in (
            "upper_in_kg_total",
            "upper_out_kg_total",
            "lower_in_kg_total",
            "lower_out_kg_total",
        ):
            row[prefix + suffix] = "0"
    row["phase3_shadow_mass_residence_plume_upper_in_kg_total"] = "7"
    row["phase3_shadow_mass_residence_plume_lower_out_kg_total"] = "7"
    row["phase3_shadow_mass_residence_exterior_upper_out_kg_total"] = "3"
    row[
        "phase3_shadow_mass_residence_interior_pressure_lower_out_kg_total"
    ] = "2"

    monkeypatch.setattr(
        audit.f33m,
        "integrate_scalar",
        lambda _rows, _checkpoint, column: 2.0
        if column == "PYROL_1"
        else 5.0,
    )
    monkeypatch.setattr(
        audit,
        "integrate_cfast_column",
        lambda _rows, _checkpoint, _column: 4.0,
    )
    result = audit.attribute_checkpoint(
        checkpoint_s=10,
        sim_row=row,
        cfast_initial_room={"upper_mass_kg": 20, "lower_mass_kg": 40},
        cfast_checkpoint={
            "rooms": {
                "0": {"upper_mass_kg": 20, "lower_mass_kg": 30}
            },
            "routes": {
                "0->1": {"mass_kg": 10},
                "1->0": {"mass_kg": 6},
            },
        },
        cfast_compartment_rows=[],
        cfast_vent_rows=[],
    )
    assert result["observed_total_mass_error_kg"] == pytest.approx(5.0)
    assert result["predicted_total_mass_error_kg"] == pytest.approx(5.0)
    assert result["plume_transfer_error_kg"] == pytest.approx(2.0)
    assert result["projection_net_mass_kg"] == pytest.approx(0.0)


@pytest.mark.skipif(not CANDIDATE.exists(), reason="scratch candidate absent")
def test_real_corridor_mass_decomposition_closes():
    result = audit.build_audit(
        candidate_csv=CANDIDATE,
        cfast_zone_path=audit.CFAST_DIR / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            audit.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
        ),
        cfast_vents_path=audit.CFAST_DIR / "cfast_corridor_chain_vents.csv",
    )
    final = result["checkpoints"]["180"]
    assert final["observed_total_mass_error_kg"] == pytest.approx(
        3.9613813, abs=1.0e-5
    )
    assert abs(final["decomposition_residual_kg"]) < 0.05
    assert result["verdict"]["mass_decomposition_closes"]
    assert result["verdict"]["source_ledgers_close"]


@pytest.mark.skipif(not CANDIDATE.exists(), reason="scratch candidate absent")
def test_real_corridor_owner_order_is_explicit():
    result = audit.build_audit(
        candidate_csv=CANDIDATE,
        cfast_zone_path=audit.CFAST_DIR / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            audit.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
        ),
        cfast_vents_path=audit.CFAST_DIR / "cfast_corridor_chain_vents.csv",
    )
    final = result["checkpoints"]["180"]
    assert final["exterior_net_outflow_deficit_kg"] > 4.8
    assert 0.8 < final["doorway_net_outflow_deficit_kg"] < 1.1
    assert final["combustion_gas_source_bias_kg"] < -2.0
    assert result["verdict"]["primary_positive_mass_error_owner"] == (
        "exterior_boundary_net_outflow"
    )
    assert result["verdict"]["combustion_gas_source_missing"]


@pytest.mark.skipif(not CANDIDATE.exists(), reason="scratch candidate absent")
def test_plume_and_projection_are_not_net_mass_owners():
    result = audit.build_audit(
        candidate_csv=CANDIDATE,
        cfast_zone_path=audit.CFAST_DIR / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            audit.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
        ),
        cfast_vents_path=audit.CFAST_DIR / "cfast_corridor_chain_vents.csv",
    )
    final = result["checkpoints"]["180"]
    assert final["plume_transfer_error_kg"] > 10.0
    assert final["projection_net_mass_kg"] == pytest.approx(0.0, abs=1.0e-8)
    assert not result["verdict"]["plume_is_net_mass_owner"]
    assert not result["verdict"]["projection_is_primary"]
    assert not result["verdict"]["interface_partition_resolved"]
