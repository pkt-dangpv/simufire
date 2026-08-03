"""Structural contracts for the mechanical H3.2-M bundle shadow."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
LOGGER = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32m_coupled_bundle_shadow.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_flag_is_default_off_and_requires_the_solver_stack():
    assert "@export var phase3_coupled_interior_bundle_shadow_enabled: bool = false" in ENGINE
    active = _function(ENGINE, "_phase3_coupled_interior_bundle_active")
    assert "_phase3_coupled_pressure_solver_active()" in active
    assert "phase3_coupled_interior_bundle_shadow_enabled" in active


def test_cli_wiring_is_complete_and_additive():
    assert "--phase3-coupled-interior-bundle-shadow" in RUNNER
    assert "--phase3-coupled-interior-bundle-shadow" in HEADLESS
    assert "phase3_coupled_interior_bundle_shadow_enabled = true" in HEADLESS


def test_bundle_uses_existing_atomic_primitives():
    body = _function(SYSTEM, "_record_coupled_interior_bundle_shadow")
    for call in (
        "make_atomic_route(",
        "_tag_connection_route(",
        "make_atomic_bundle(",
        "_evaluate_atomic_bundle_acceptance(",
        "_scaled_atomic_routes(",
    ):
        assert call in body


def test_coupled_bundle_never_enters_or_applies_the_legacy_registry():
    body = _function(SYSTEM, "_record_coupled_interior_bundle_shadow")
    for forbidden in (
        "add_atomic_bundle(",
        "_apply_atomic_bundle(",
        "_apply_atomic_route(",
        "_transactions.append",
        "_atomic_bundle_count",
        "_atomic_route_count",
        "_atomic_min_accepted_fraction",
        "_atomic_rejected_",
    ):
        assert forbidden not in body


def test_comparison_is_explicitly_invalid_not_zero_filled():
    record = _function(SYSTEM, "_new_coupled_interior_bundle_record")
    assert '"source_inputs_independent_flag": 0.0' in record
    assert '"comparison_valid_flag": 0.0' in record
    assert '"post_minus_pre_minus_legacy_interior"' in record
    assert '"circular_legacy_source_reconstruction"' in record
    assert "coupled_vs_legacy" not in _function(
        SYSTEM, "_record_coupled_interior_bundle_shadow"
    )
    summary = _function(SYSTEM, "get_coupled_interior_bundle_summary")
    assert '"source_inputs_independent": false' in summary
    assert '"comparison_valid": false' in summary
    assert "get_coupled_interior_bundle_summary()" in ENGINE


def test_species_and_o2_are_deferred_not_invented():
    body = _function(SYSTEM, "_record_coupled_interior_bundle_shadow")
    route_call = body.split("make_atomic_route(", 1)[1].split(")\n", 1)[0]
    assert "0.0" in route_call
    assert "{}" in route_call


def test_parcels_are_only_read_for_overlap():
    body = _function(SYSTEM, "_record_coupled_parcel_overlap")
    assert "_species_transit_reservoir.values()" in body
    assert not re.search(r"_species_transit_reservoir\s*\[.*\]\s*=", body)
    assert "erase(" not in body and "clear(" not in body


def test_single_global_fraction_scales_all_routes_once():
    body = _function(SYSTEM, "_record_coupled_interior_bundle_shadow")
    assert body.count("_evaluate_atomic_bundle_acceptance(") == 1
    assert body.count("_scaled_atomic_routes(") == 1
    assert '"double_limit_count": 0.0' in _function(
        SYSTEM, "_new_coupled_interior_bundle_record"
    )


def test_inventory_limited_and_shadow_accepted_are_explicitly_separate():
    body = _function(SYSTEM, "_record_coupled_interior_bundle_shadow")
    assert 'record["inventory_limited_mass_kg"]' in body
    assert 'record["inventory_limited_energy_kj"]' in body
    assert 'record["accepted_mass_kg"]' in body
    assert 'record["accepted_energy_kj"]' in body
    assert "inventory_limited_mass_kg" in LOGGER
    assert "inventory_limited_energy_kj" in LOGGER


def test_exact_zero_zonal_buckets_are_observed_but_not_atomic_routes():
    body = _function(SYSTEM, "_record_coupled_interior_bundle_shadow")
    assert "route_mass_kg <= 0.0 and route_energy_kj <= 0.0" in body
    assert 'record["zero_route_skipped_count"]' in body
    assert "THERMO_MASS_EPS_KG" not in body
    assert "zero_route_skipped_count" in LOGGER


def test_cumulative_gate_retains_extrema_not_only_the_last_step():
    body = _function(SYSTEM, "_commit_coupled_interior_bundle_record")
    assert 'cumulative["min_accepted_fraction"] = minf(' in body
    assert 'cumulative["max_abs_mass_conservation_residual_kg"] = maxf(' in body
    assert 'cumulative["max_abs_energy_conservation_residual_kj"] = maxf(' in body
    for field in (
        "min_accepted_fraction",
        "max_abs_mass_conservation_residual_kg",
        "max_abs_energy_conservation_residual_kj",
    ):
        assert field in LOGGER


def test_telemetry_is_opt_in_in_state_and_csv():
    assert "phase3_coupled_interior_bundle_shadow_enabled" in STATE
    assert "configure_phase3_coupled_interior_bundle_shadow" in LOGGER
    assert "if phase3_coupled_interior_bundle_shadow_enabled:" in LOGGER
    assert "_phase3_coupled_bundle_fields()" in LOGGER


def test_fixture_checks_fallback_and_legacy_isolation_fail_closed():
    assert "if _failed:" in FIXTURE and "quit(1)" in FIXTURE
    assert "no copied legacy fallback" in FIXTURE
    assert "legacy bundle count untouched" in FIXTURE
    assert "state untouched" in FIXTURE
