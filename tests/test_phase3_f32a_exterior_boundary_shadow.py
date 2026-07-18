"""Structural checks for F3.2a passive canonical exterior boundary bundles."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_exterior_pressure_pre_pa",
    "phase3_shadow_exterior_requested_gas_kg",
    "phase3_shadow_exterior_requested_energy_kj",
    "phase3_shadow_exterior_requested_o2_kg",
    "phase3_shadow_exterior_requested_species_kg",
    "phase3_shadow_exterior_accepted_gas_kg",
    "phase3_shadow_exterior_accepted_energy_kj",
    "phase3_shadow_exterior_accepted_o2_kg",
    "phase3_shadow_exterior_accepted_species_kg",
    "phase3_shadow_exterior_post_upper_o2_kg",
    "phase3_shadow_exterior_post_lower_o2_kg",
    "phase3_shadow_exterior_post_upper_o2_fraction",
    "phase3_shadow_exterior_post_lower_o2_fraction",
    "phase3_shadow_exterior_rejected_gas_kg",
    "phase3_shadow_exterior_rejected_energy_kj",
    "phase3_shadow_exterior_rejected_o2_kg",
    "phase3_shadow_exterior_rejected_species_kg",
    "phase3_shadow_exterior_direction",
    "phase3_shadow_exterior_source_zone_code",
    "phase3_shadow_exterior_event_count",
    "phase3_shadow_exterior_legacy_pressure_suppressed_event_count",
    "phase3_shadow_exterior_accepted_fraction",
    "phase3_shadow_exterior_duplicate_owner_flag",
    "phase3_shadow_exterior_mass_residual_kg",
    "phase3_shadow_exterior_energy_residual_kj",
    "phase3_shadow_exterior_o2_residual_kg",
    "phase3_shadow_exterior_species_residual_kg",
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_opt_in_and_exported_without_authority():
    assert "@export var phase3_canonical_exterior_boundary_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_exterior_boundary_shadow_enabled"' in STATE
    assert "phase3_canonical_exterior_boundary_authority" not in ENGINE
    assert "phase3_f32a_authority" not in ENGINE.lower()


def test_contract_is_registered_from_pre_step_snapshot_before_legacy_physics():
    step = _function(ENGINE, "step")
    begin = step.index("phase3_zone_mass_system.begin_step(building)")
    queue = step.index("queue_canonical_exterior_boundary_requests(")
    fire = step.index("_step_pool_fires(")
    assert begin < queue < fire


def test_exterior_bundle_is_resolved_after_internal_shadow_transactions():
    finalize = _function(SYSTEM, "finalize_step")
    internal = finalize.index("for raw_transaction in _transactions:")
    exterior = finalize.index("_apply_canonical_exterior_boundary_requests(")
    diagnostics = finalize.index("var inflight_transit_species:")
    assert internal < exterior < diagnostics


def test_queue_uses_canonical_snapshot_and_thermodynamic_closure():
    body = _function(SYSTEM, "_apply_canonical_exterior_boundary_requests")
    assert "shadow[room_key]" in body
    assert "derive_canonical_thermodynamic_state(" in body
    assert 'thermo.get("pressure_gauge_pa"' in body
    assert 'thermo.get("interface_m"' in body


def test_queue_does_not_write_legacy_room_state():
    body = _function(SYSTEM, "_apply_canonical_exterior_boundary_requests")
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", body)
    assert "RoomModel" not in body


def test_opening_area_is_split_by_canonical_interface():
    body = _function(SYSTEM, "_canonical_exterior_area_by_zone")
    assert "lower_span_m" in body
    assert "upper_span_m" in body
    assert "interface_m" in body
    assert "closed_leakage_area_m2" in body
    assert "op.is_exterior_opening()" in body


def test_pressure_flow_uses_bernoulli_and_direction_is_signed():
    body = _function(SYSTEM, "_apply_canonical_exterior_boundary_requests")
    assert "discharge_coeff * area_m2" in body
    assert "sqrt(2.0 * absf(pressure_gauge_pa)" in body
    assert "var outflow: bool = pressure_gauge_pa > 0.0" in body
    assert "source_room_id = room_id" in body
    assert "destination_room_id = EXTERIOR_ID" in body


def test_bundle_carries_gas_energy_o2_and_all_species_together():
    body = _function(SYSTEM, "_apply_canonical_exterior_boundary_requests")
    for token in (
        "requested_mass_kg",
        "energy_kj",
        "o2_kg",
        "species_kg",
        "make_atomic_route(",
        "make_atomic_bundle(",
    ):
        assert token in body
    assert '"kind": "canonical_exterior_boundary"' in body


def test_all_routes_share_atomic_inventory_fraction():
    apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
    assert "var accepted_fraction: float" in apply_bundle
    assert "_apply_atomic_route(shadow, route, accepted_fraction)" in apply_bundle
    result = _function(SYSTEM, "_record_atomic_bundle_result")
    assert 'result_kind == "canonical_exterior_boundary"' in result
    assert 'record["accepted_fraction"] = accepted' in result


def test_only_legacy_pressure_purge_is_suppressed_in_shadow():
    body = _function(SYSTEM, "suppress_legacy_pressure_purge_event")
    assert 'String(event.get("mechanism", "")) != "pressure_venting"' in body
    for mechanism in (
        "smoke_vent",
        "natural_ventilation",
        "ach_infiltration",
        "outside_open_species_purge",
        "postfire_species_purge",
        "ppv_inlet",
        "ppv_exhaust",
    ):
        assert mechanism not in body


def test_suppression_is_effective_only_inside_canonical_shadow_collection():
    collect = _function(ENGINE, "_phase3_shadow_collect_exterior_purge_events")
    assert "phase3_canonical_exterior_boundary_shadow_enabled" in collect
    assert "suppress_legacy_pressure_purge_event(event)" in collect
    step = _function(ENGINE, "step")
    assert "if phase3_canonical_zone_shadow_enabled:" in step


def test_csv_fields_are_separately_gated_and_unique():
    assert "if phase3_canonical_exterior_boundary_shadow_enabled:" in LOG
    for field in FIELDS:
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_parent_canonical_shadow():
    assert '"--phase3-canonical-exterior-shadow"' in RUNNER
    exterior_block = RUNNER.split("if args.phase3_canonical_exterior_shadow:", 1)[1]
    assert 'cmd.append("--phase3-canonical-shadow")' in exterior_block
    assert 'cmd.append("--phase3-canonical-exterior-shadow")' in exterior_block
    assert "engine.phase3_canonical_zone_shadow_enabled = true" in HEADLESS
    assert "engine.phase3_canonical_exterior_boundary_shadow_enabled = true" in HEADLESS


def test_f32a_uses_immediate_atomic_bundle_not_delayed_parcel():
    body = _function(SYSTEM, "_apply_canonical_exterior_boundary_requests")
    assert "add_atomic_bundle(bundle)" in body
    assert "apply_species_transit_event" not in body
    assert "delayed_parcel" not in body


def test_f31e_thermodynamic_contract_remains_present():
    closure = _function(SYSTEM, "derive_canonical_thermodynamic_state")
    assert "pressure_abs_pa" in closure
    assert "volume_closure_error_m3" in closure
    assert "canonical_transaction_closure_flag" in closure
