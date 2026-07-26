from pathlib import Path

import pytest

from scripts.simulation import analyze_phase3_f33v3c_exterior_leakage as audit


ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / "runs" / "phase3_f33v3a" / "180_on" / "sim_log.csv"
MANIFEST = (
    ROOT / "runs" / "phase3_f33v3a" / "180_on" / "run_manifest.json"
)


def test_cfast_geometry_matches_source_contract():
    result = audit.parse_cfast_compartment_leak_geometry(
        audit.CFAST_DIR / "cfast_corridor_chain.in"
    )
    assert result["wall_leak_area_m2"] == pytest.approx(0.007344)
    assert result["floor_leak_area_m2"] == pytest.approx(0.00104)
    assert result["total_leak_area_m2"] == pytest.approx(0.008384)
    assert result["wall_leak_sill_m"] == pytest.approx(0.12)
    assert result["wall_leak_soffit_m"] == pytest.approx(2.28)
    assert result["discharge_coefficient"] == pytest.approx(0.7)


def test_cfast_output_exposes_layer_specific_leakage():
    rows = audit.read_cfast_leak_layer_rows(
        audit.CFAST_DIR / "cfast_corridor_chain.out"
    )
    row10 = audit.row_at(rows, 10, "time_s")
    assert row10["room_upper_out_kg_s"] == pytest.approx(0.0001142)
    assert row10["room_lower_out_kg_s"] == pytest.approx(0.004997)
    assert row10["room_upper_in_kg_s"] == 0.0
    assert row10["room_lower_in_kg_s"] == 0.0


def test_cfast_layer_integration_reconstructs_net_spreadsheet_flow():
    rows = audit.read_cfast_leak_layer_rows(
        audit.CFAST_DIR / "cfast_corridor_chain.out"
    )
    upper = audit.integrate_net_layer_flow(rows, 180, "upper")
    lower = audit.integrate_net_layer_flow(rows, 180, "lower")
    assert upper == pytest.approx(4.827972, abs=1.0e-6)
    assert lower == pytest.approx(5.005455, abs=1.0e-6)
    assert upper + lower == pytest.approx(9.833427, abs=1.0e-6)


@pytest.mark.skipif(
    not CANDIDATE.exists() or not MANIFEST.exists(),
    reason="scratch candidate absent",
)
def test_real_candidate_assigns_deficit_to_lower_exterior_flow():
    result = audit.build_audit(
        candidate_csv=CANDIDATE,
        manifest_path=MANIFEST,
        cfast_input_path=audit.CFAST_DIR / "cfast_corridor_chain.in",
        cfast_output_path=audit.CFAST_DIR / "cfast_corridor_chain.out",
        cfast_compartments_path=(
            audit.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
        ),
    )
    verdict = result["verdict"]
    assert verdict["upper_net_out_deficit_kg"] == pytest.approx(
        1.263128, abs=1.0e-5
    )
    assert verdict["lower_net_out_deficit_kg"] == pytest.approx(
        3.649057, abs=1.0e-5
    )
    assert verdict["lower_share_of_total_deficit"] == pytest.approx(
        0.74286, abs=1.0e-4
    )
    assert verdict["primary_layer_owner"] == "lower_exterior_net_outflow"


@pytest.mark.skipif(
    not CANDIDATE.exists() or not MANIFEST.exists(),
    reason="scratch candidate absent",
)
def test_pressure_sign_mismatch_blocks_area_only_experiment():
    result = audit.build_audit(
        candidate_csv=CANDIDATE,
        manifest_path=MANIFEST,
        cfast_input_path=audit.CFAST_DIR / "cfast_corridor_chain.in",
        cfast_output_path=audit.CFAST_DIR / "cfast_corridor_chain.out",
        cfast_compartments_path=(
            audit.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
        ),
    )
    verdict = result["verdict"]
    assert verdict["pressure_sign_mismatch_checkpoints"] == [
        120,
        130,
        140,
        180,
    ]
    assert not verdict["topology_equivalent"]
    assert not verdict["area_only_experiment_allowed"]
