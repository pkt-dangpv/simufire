"""Fail-closed inventory contract for P1R4 default-OFF engine controls."""

from __future__ import annotations

import re
from pathlib import Path

from scripts.simulation.audit_default_off_flags import (
    OUT_OF_RUNTIME_SCOPE,
    RUNTIME_ACTIVATIONS,
    static_audit,
)


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "sim/core/SimulationEngine.gd"
FIXTURES = ROOT / "tests/fixtures"
TESTS = ROOT / "tests"

DECLARATION_RE = re.compile(
    r"^@export var (?P<name>[A-Za-z0-9_]+): bool = false:?\s*$", re.MULTILINE
)

# P1R4 covers passive diagnostics and shadow-only observations. Controls that
# change live physics, HVAC, fire growth, case lifecycle, or authority remain
# visible in the inventory but are outside this remediation lane.
RUNTIME_SCOPE_FLAGS = {
    "energy_budget_enabled",
    "conservation_check_enabled",
    "phase3_zone_diagnostics_enabled",
    "phase3_runtime_ownership_ledger_enabled",
    "phase3_physical_owner_ledger_enabled",
    "phase3_species_attribution_diagnostics_enabled",
    "phase3_projection_causal_diagnostics_enabled",
    "phase3_residual_projection_shadow_enabled",
    "phase3_zone_transition_diagnostics_enabled",
    "phase3_o2_attribution_diagnostics_enabled",
    "phase3_co_zonal_transport_consistency_enabled",
    "phase3_co_first_violation_trace_enabled",
    "phase3_co2_zonal_transport_consistency_enabled",
    "phase3_canonical_zone_shadow_enabled",
    "phase3_canonical_exterior_boundary_shadow_enabled",
    "phase3_canonical_persistence_shadow_enabled",
    "phase3_o2_zonal_mass_shadow_enabled",
    "phase3_canonical_combustion_shadow_enabled",
    "phase3_canonical_pressure_relaxation_shadow_enabled",
    "phase3_canonical_plume_shadow_enabled",
    "phase3_canonical_interzone_heat_shadow_enabled",
    "phase3_canonical_wall_ambient_shadow_enabled",
    "phase3_canonical_multisurface_shadow_enabled",
    "phase3_coupled_plume_shadow_enabled",
    "phase3_canonical_fire_proposal_shadow_enabled",
    "phase3_canonical_unfiltered_fire_growth_shadow_enabled",
    "phase3_canonical_fire_products_shadow_enabled",
    "phase3_canonical_fire_products_routing_shadow_enabled",
    "phase3_canonical_fuel_object_sync_shadow_enabled",
    "phase3_canonical_exterior_counterflow_shadow_enabled",
    "phase3_canonical_post_opening_coupling_shadow_enabled",
    "phase3_canonical_interior_opening_shadow_enabled",
    "phase3_canonical_interior_pressure_shadow_enabled",
    "phase3_canonical_fixed_gross_pressure_skew_shadow_enabled",
    "phase3_canonical_fixed_gross_pressure_network_shadow_enabled",
    "phase3_coupled_pressure_solver_shadow_enabled",
    "phase3_coupled_interior_bundle_shadow_enabled",
    "phase3_enthalpy_residence_diagnostics_enabled",
    "phase3_mass_residence_diagnostics_enabled",
    "phase3_connection_residence_diagnostics_enabled",
    "phase3_cfast_buoyancy_destination_shadow_enabled",
}


def _declared_flags() -> set[str]:
    return set(DECLARATION_RE.findall(ENGINE.read_text(encoding="utf-8")))


def _fixture_links() -> dict[str, set[Path]]:
    fixture_sources = {
        path: path.read_text(encoding="utf-8")
        for path in sorted(FIXTURES.glob("*.gd"))
    }
    test_sources = {
        path: path.read_text(encoding="utf-8")
        for path in sorted(TESTS.glob("test_*.py"))
        if path != Path(__file__)
    }
    links: dict[str, set[Path]] = {}
    for flag in RUNTIME_SCOPE_FLAGS:
        linked = {path for path, source in fixture_sources.items() if flag in source}
        for test_path, source in test_sources.items():
            if flag not in source:
                continue
            for fixture_name in re.findall(r"[A-Za-z0-9_.-]+\.gd", source):
                fixture = FIXTURES / fixture_name
                if fixture.is_file():
                    linked.add(fixture)
        links[flag] = linked
    return links


def test_current_engine_inventory_is_complete_and_uniquely_partitioned():
    declared = _declared_flags()
    assert len(declared) == 75
    assert len(RUNTIME_SCOPE_FLAGS) == 41
    assert RUNTIME_SCOPE_FLAGS <= declared
    assert len(declared - RUNTIME_SCOPE_FLAGS) == 34


def test_every_retained_diagnostic_has_a_runtime_fixture_link():
    missing = sorted(flag for flag, paths in _fixture_links().items() if not paths)
    assert missing == []


def test_versioned_auditor_matches_the_independent_partition():
    report = static_audit()
    assert report["pass"], report["errors"]
    assert set(RUNTIME_ACTIVATIONS) == RUNTIME_SCOPE_FLAGS
    assert OUT_OF_RUNTIME_SCOPE == _declared_flags() - RUNTIME_SCOPE_FLAGS
    assert report["declaration_count"] == 75
    assert report["runtime_backed_count"] == 41
    assert report["out_of_runtime_scope_count"] == 34


def test_runtime_evidence_tokens_are_present_in_every_selected_fixture():
    for flag, (fixture_rel, token) in RUNTIME_ACTIVATIONS.items():
        fixture = ROOT / fixture_rel
        assert fixture.is_file(), flag
        assert token in fixture.read_text(encoding="utf-8"), flag
