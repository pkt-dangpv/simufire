from pathlib import Path

import pytest

from scripts.simulation import (
    analyze_phase3_f33v3e_energy_correspondence as audit,
)


ROOT = Path(__file__).resolve().parents[1]
RUN_DIR = ROOT / "runs" / "phase3_f33v3a" / "180_on"
CFAST = ROOT / "sim" / "validation" / "cfast"


def _real_audit():
    return audit.build_audit(
        sim_run_dir=RUN_DIR,
        cfast_zone_path=CFAST / "cfast_corridor_chain_zone.csv",
        cfast_compartments_path=(
            CFAST / "cfast_corridor_chain_compartments.csv"
        ),
        cfast_output_path=CFAST / "cfast_corridor_chain.out",
    )


@pytest.mark.skipif(
    not (RUN_DIR / "sim_log.csv").exists(),
    reason="scratch candidate absent",
)
def test_energy_budgets_close_for_both_models():
    verdict = _real_audit()["verdict"]
    assert verdict["energy_budgets_close"]
    assert verdict["max_energy_budget_residual_kj"] < 1.0e-3


@pytest.mark.skipif(
    not (RUN_DIR / "sim_log.csv").exists(),
    reason="scratch candidate absent",
)
def test_doorway_is_primary_energy_error_at_first_sign_mismatch():
    result = _real_audit()
    assert result["verdict"]["primary_error_owner_at_120s"] == "doorway_kj"
    errors = result["checkpoints"]["120"]["error_sim_minus_cfast_kj"]
    assert errors["doorway_kj"] == pytest.approx(-217.9, abs=0.2)
    assert errors["surface_kj"] == pytest.approx(-78.7, abs=0.2)


@pytest.mark.skipif(
    not (RUN_DIR / "sim_log.csv").exists(),
    reason="scratch candidate absent",
)
def test_doorway_remains_primary_energy_error_at_180s():
    result = _real_audit()
    verdict = result["verdict"]
    assert verdict["primary_error_owner_at_180s"] == "doorway_kj"
    assert verdict["final_surface_relative_error"] == pytest.approx(
        0.01688, abs=1.0e-4
    )
    assert verdict["final_doorway_relative_error"] == pytest.approx(
        0.12763, abs=1.0e-4
    )


@pytest.mark.skipif(
    not (RUN_DIR / "summary.json").exists(),
    reason="scratch candidate absent",
)
def test_opening_route_alone_matches_cfast_net_enthalpy():
    result = _real_audit()
    direction = result["final_directional_correspondence"]
    assert result["verdict"][
        "interior_opening_only_matches_cfast_enthalpy"
    ]
    assert direction["opening_only_enthalpy_error_kj"] == pytest.approx(
        8.7557, abs=0.02
    )
    assert direction["opening_only_enthalpy_relative_error"] < 0.0015


@pytest.mark.skipif(
    not (RUN_DIR / "summary.json").exists(),
    reason="scratch candidate absent",
)
def test_pressure_route_adds_gross_churn_and_excess_enthalpy():
    direction = _real_audit()["final_directional_correspondence"]
    assert direction["sim_pressure_net_enthalpy_out_kj"] == pytest.approx(
        795.539, abs=0.02
    )
    assert direction["pressure_route_added_gross_mass_kg"] == pytest.approx(
        39.7292, abs=0.002
    )
    assert direction["gross_mass_relative_error"] == pytest.approx(
        0.2561, abs=0.001
    )
    assert direction["opening_only_gross_mass_relative_error"] == pytest.approx(
        -0.0157, abs=0.001
    )


@pytest.mark.skipif(
    not (RUN_DIR / "summary.json").exists(),
    reason="scratch candidate absent",
)
def test_pressure_route_owns_required_net_mass_but_is_additive():
    direction = _real_audit()["final_directional_correspondence"]
    assert abs(direction["sim_opening_net_mass_out_kg"]) < 1.0e-3
    assert direction["pressure_route_net_mass_share_of_cfast"] == pytest.approx(
        0.8735, abs=0.001
    )
    assert direction["fixed_gross_pressure_skew_out_mass_kg"] == pytest.approx(
        75.1249, abs=0.002
    )
    assert direction["fixed_gross_pressure_skew_in_mass_kg"] == pytest.approx(
        68.7565, abs=0.002
    )


@pytest.mark.skipif(
    not (RUN_DIR / "sim_log.csv").exists(),
    reason="scratch candidate absent",
)
def test_verdict_selects_fixed_gross_shadow_experiment():
    verdict = _real_audit()["verdict"]
    assert verdict["additive_pressure_route_is_excess_enthalpy_owner"]
    assert "fixed-gross directional skew" in verdict[
        "next_motor_shadow_experiment"
    ]
