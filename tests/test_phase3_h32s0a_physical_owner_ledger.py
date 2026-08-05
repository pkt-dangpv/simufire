"""Structural contracts for the isolated H3.2-S0a owner-event ledger."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LEDGER_PATH = ROOT / "sim/core/Phase3PhysicalOwnerLedger.gd"
FIXTURE_PATH = ROOT / "tests/fixtures/phase3_h32s0a_physical_owner_ledger.gd"
LEDGER = LEDGER_PATH.read_text(encoding="utf-8")
FIXTURE = FIXTURE_PATH.read_text(encoding="utf-8")


def _function(name: str) -> str:
    body = LEDGER.split(f"static func {name}(", 1)[1]
    return body.split("\nstatic func ", 1)[0]


def test_component_is_a_pure_refcounted_library():
    assert LEDGER.startswith("extends RefCounted\nclass_name Phase3PhysicalOwnerLedger")
    for forbidden in (
        "RoomModel",
        "BuildingModel",
        "SimulationEngine",
        "ThermalSystem",
        "GasExchangeSystem",
        "@export",
        "options",
    ):
        assert forbidden not in LEDGER


def test_component_has_only_the_authorized_production_call_sites():
    # S0b authorised ThermalSystem. S0c added GasExchangeSystem plus the
    # export-only combination in SimulationEngine. S0d1 added the suppression
    # owner, still inside SimulationEngine. Nothing else may reference the
    # ledger until the integration gate opens.
    authorised = {
        "sim/core/GasExchangeSystem.gd",
        "sim/core/SimulationEngine.gd",
        "sim/core/ThermalSystem.gd",
        "tests/fixtures/phase3_h32s0c_gas_physical_owners.gd",
        "tests/fixtures/phase3_h32s0d1_suppression_and_seeds.gd",
    }
    references = set()
    for path in ROOT.rglob("*.gd"):
        if path == LEDGER_PATH or path == FIXTURE_PATH:
            continue
        if "Phase3PhysicalOwnerLedger" in path.read_text(encoding="utf-8"):
            references.add(path.relative_to(ROOT).as_posix())
    assert references == authorised


def test_exact_six_classifications_are_pinned():
    expected = {
        "local_source",
        "exterior_boundary",
        "interior_transport",
        "interzone_redistribution",
        "delayed_parcel",
        "numerical_correction",
    }
    constants = set(re.findall(r'CLASS_[A-Z_]+: String = "([^"]+)"', LEDGER))
    assert constants == expected
    block = LEDGER.split("const VALID_CLASSIFICATIONS", 1)[1].split("= [", 1)[1].split("]", 1)[0]
    assert block.count("CLASS_") == 6


def test_public_api_is_complete():
    for name in (
        "make_event",
        "validate_event",
        "aggregate_events",
        "physical_source_for_room",
        "building_conservation",
    ):
        assert f"static func {name}(" in LEDGER


def test_no_legacy_reconstruction_vocabulary_or_state_access():
    lowered = LEDGER.lower()
    for forbidden in (
        "post_state",
        "pre_state",
        "stage_delta",
        "legacy_interior",
        "canonical_interior",
        "upper_gas_kg",
        "lower_gas_kg",
        "upper_energy_kj =",
        "lower_energy_kj =",
    ):
        assert forbidden not in lowered


def test_only_physical_source_classes_feed_source_totals():
    body = _function("_aggregate_valid_event")
    gate = body.split('var room_key: String = str(int(event["room_id"]))', 1)[0]
    assert "CLASS_LOCAL_SOURCE" in gate
    assert "CLASS_EXTERIOR_BOUNDARY" in gate
    for forbidden in (
        "CLASS_INTERIOR_TRANSPORT",
        "CLASS_INTERZONE_REDISTRIBUTION",
        "CLASS_DELAYED_PARCEL",
        "CLASS_NUMERICAL_CORRECTION",
    ):
        assert forbidden not in gate.split("if classification == CLASS_LOCAL_SOURCE", 1)[1]


def test_source_lookup_fails_closed_on_any_invalid_event():
    body = _function("physical_source_for_room")
    assert 'if not bool(aggregate.get("valid", false)):' in body
    assert body.index('if not bool(aggregate.get("valid", false)):') < body.index(
        'var sources: Dictionary = aggregate.get("physical_source_by_room", {})'
    )


def test_duplicate_ids_are_detected_before_valid_event_aggregation():
    body = _function("aggregate_events")
    duplicate_gate = body.index("if duplicate_ids.has(event_id):")
    validation = body.index("var validation: Dictionary = validate_event(event)")
    aggregation = body.index("_aggregate_valid_event(result, event)")
    assert duplicate_gate < validation < aggregation
    assert '"duplicate_event_id"' in body[duplicate_gate:validation]


def test_invalid_events_are_visible_and_never_aggregated():
    body = _function("aggregate_events")
    assert 'result["invalid_event_count"] += 1' in body
    assert 'result["errors"].append' in body
    invalid_branch = body.split("if not bool(validation", 1)[1].split(
        "result[\"valid_event_count\"]", 1
    )[0]
    assert "continue" in invalid_branch


def test_interior_transport_requires_room_and_energy_conservation():
    body = _function("_validate_interior_transport")
    assert "interior_transport_mass_not_conserved" in body
    assert "interior_transport_energy_not_conserved" in body
    assert body.count("CONSERVATION_EPSILON") >= 2


def test_interzone_requires_opposite_zones_and_zero_room_delta():
    body = _function("_validate_interzone_redistribution")
    assert "interzone_requires_opposite_zones" in body
    assert "interzone_mass_not_conserved" in body
    assert "interzone_energy_not_conserved" in body


def test_parcel_lifecycle_is_explicit():
    assert '"created", "delivered", "cancelled", "inflight"' in LEDGER
    body = _function("_validate_delayed_parcel")
    assert 'metadata.get("parcel_id"' in body
    assert 'metadata.get("lifecycle"' in body


def test_non_finite_values_and_invalid_zones_fail_closed():
    body = _function("_validate_common")
    assert "is_finite" in body
    assert "non_finite_%s" in body
    assert "invalid_%s" in body
    assert "clampf(" not in LEDGER


def test_single_global_numeric_epsilon_is_not_configurable():
    assert "const CONSERVATION_EPSILON: float = 1.0e-12" in LEDGER
    assert LEDGER.count("EPSILON") >= 5
    assert "settings" not in LEDGER
    assert "case" not in LEDGER.lower()


def test_aggregation_sorts_owned_copies_and_never_mutates_input():
    body = _function("aggregate_events")
    assert "Dictionary(raw_event).duplicate(true)" in body
    assert "copies.sort_custom" in body
    assert "events.sort" not in body


def test_fixture_is_fail_closed():
    assert "if _failed:" in FIXTURE
    failure_block = FIXTURE.split("if _failed:", 1)[1].split(
        'print("PHASE3_H32S0A_PHYSICAL_OWNER_LEDGER_PASS")', 1
    )[0]
    assert "quit(1)" in failure_block
    assert "return" in failure_block
    assert re.search(r"(?<!_)\bassert\(", FIXTURE) is None


def test_fixture_covers_every_required_semantic_group():
    required = (
        "local source",
        "exterior inflow",
        "exterior outflow",
        "upper to lower",
        "lower to upper",
        "interior upper to lower",
        "counterflow return",
        "parcel created",
        "parcel delivered",
        "numerical correction",
        "duplicate result invalid",
        "unknown classification",
        "non finite",
        "invalid zone",
        "nonconservative transport",
        "nonconservative interzone",
        "transport sign mismatch",
        "invalid aggregate exposes no partial source",
        "aggregation deterministic under input reversal",
        "input events are not mutated",
        "multi-owner aggregate valid",
    )
    for marker in required:
        assert marker in FIXTURE


def test_fixture_proves_non_source_classes_are_excluded():
    assert "interzone excluded from source" in FIXTURE
    assert "interior transport excluded from source" in FIXTURE
    assert "parcel/correction source mass" in FIXTURE
    assert "parcel/correction source energy" in FIXTURE


def test_failure_marker_is_mutation_detectable():
    assert '_assert(bool(aggregate["valid"]), "multi-owner aggregate valid")' in FIXTURE
    mutated = FIXTURE.replace(
        '_assert(bool(aggregate["valid"]), "multi-owner aggregate valid")',
        '_assert(not bool(aggregate["valid"]), "multi-owner aggregate valid")',
        1,
    )
    assert mutated != FIXTURE
    assert '_assert(not bool(aggregate["valid"])' in mutated
