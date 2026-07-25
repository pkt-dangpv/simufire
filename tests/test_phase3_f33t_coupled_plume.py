from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_coupled_plume_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_coupled_plume_shadow_enabled"' in STATE


def test_engine_requires_canonical_plume_and_multisurface_stack():
    collector = _function(ENGINE, "_phase3_shadow_collect_thermal_requests")
    assert "if phase3_canonical_plume_shadow_enabled and building != null:" in collector
    assert "phase3_coupled_plume_shadow_enabled" in collector
    assert "and _phase3_canonical_multisurface_active()" in collector
    assert "preview_phase3_coupled_plume_flux" in collector
    assert "preview_phase3_canonical_plume_flux" in collector


def test_complete_heskestad_uses_accepted_combustion_contract():
    preview = _function(THERMAL, "preview_phase3_coupled_plume_flux")
    assert 'combustion_transaction.get("accepted_hrr_kw"' in preview
    assert 'combustion_transaction.get("effective_chi_rad"' in preview
    assert "accepted_hrr_kw * (1.0 - effective_chi_rad)" in preview
    assert "-1.02 * plume_fire_diameter_m" in preview
    assert "0.083 * pow(accepted_hrr_kw, 0.4)" in preview
    assert "0.071 * 0.026 * qc_kw * dt" in preview
    assert '"o2_decision_applied": true' in preview


def test_finalize_bypasses_only_the_second_plume_scale():
    finalize = _function(SYSTEM, "finalize_canonical_combustion_bundle")
    assert 'plume_flux.get("o2_decision_applied", false)' in finalize
    assert "var heat_scale" in finalize
    assert "requested_heat_kj * heat_scale" in finalize
    assert "requested_plume_mass_kg * plume_scale" in finalize


def test_runtime_fixture_covers_equations_caps_and_scaling():
    source = (ROOT / "tests/fixtures/phase3_f33t_coupled_plume.gd").read_text(
        encoding="utf-8"
    )
    assert "PHASE3_F33T_COUPLED_PLUME_PASS" in source
    assert "_test_complete_heskestad_contract" in source
    assert "_test_lower_inventory_cap" in source
    assert "_test_transaction_getter_is_read_only" in source
    assert "_test_o2_decision_is_not_applied_twice" in source
