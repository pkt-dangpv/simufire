from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33f1_destination_routing.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_candidate_defaults_off_at_every_public_entrypoint():
    for function_name in (
        "preview_canonical_interior_opening",
        "preview_canonical_interior_pressure_flow",
        "queue_canonical_interior_opening_requests",
    ):
        body = _function(SYSTEM, function_name)
        signature = body.split(") ->", 1)[0]
        assert "source_preserving_destination_enabled: bool = false" in signature


def test_candidate_is_not_wired_to_engine_or_runners_after_runtime_no_go():
    runtime_flag = "phase3_source_preserving_destination_routing_enabled"
    assert runtime_flag not in ENGINE
    assert runtime_flag not in RUNNER
    assert runtime_flag not in HEADLESS


def test_destination_selector_preserves_source_only_when_enabled():
    body = _function(SYSTEM, "_canonical_interior_destination_zone")
    assert "if source_preserving_destination_enabled:" in body
    assert "return source_zone" in body
    assert "return _canonical_zone_at_height(destination_canonical, height_m)" in body


def test_interval_flow_uses_one_shared_destination_selector():
    body = _function(SYSTEM, "_canonical_interior_interval_flow")
    assert body.count("_canonical_interior_destination_zone(") == 1
    assert "source_preserving_destination_enabled" in body
    assert "source_density_kg_m3" in body


def test_opening_and_pressure_previews_propagate_same_contract():
    opening = _function(SYSTEM, "preview_canonical_interior_opening")
    pressure = _function(SYSTEM, "preview_canonical_interior_pressure_flow")
    assert "source_preserving_destination_enabled" in opening
    assert "source_preserving_destination_enabled" in pressure
    assert "_integrate_canonical_interior_opening" in opening
    assert "_integrate_canonical_interior_opening" in pressure


def test_network_queue_propagates_contract_to_both_route_families():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "preview_canonical_interior_opening(" in body
    assert "preview_canonical_interior_pressure_flow(" in body
    assert "direct_source_preserving" in body
    assert "source_preserving_destination_enabled" in body
    assert body.count("add_atomic_bundle(bundle)") == 1


def test_candidate_does_not_change_flow_or_payload_formulas():
    interval = _function(SYSTEM, "_canonical_interior_interval_flow")
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "discharge_coeff * width_m * open_fraction" in interval
    assert 'source_state.get(source_zone + "_energy_kj"' in queue
    assert 'source_state.get(source_zone + "_o2_kg"' in queue
    assert "for species_name in PARCEL_SPECIES" in queue


def test_runtime_fixture_covers_binding_contracts():
    assert "PHASE3_F33F1_DESTINATION_ROUTING_PASS" in FIXTURE
    for test_name in (
        "_test_lower_source_renews_lower_receiver",
        "_test_upper_source_remains_upper",
        "_test_disabled_matches_existing_routing",
        "_test_gross_opening_flow_is_invariant",
        "_test_pressure_routes_share_contract",
        "_test_empty_destination_zone_is_created_conservatively",
        "_test_atomic_bundle_conserves_all_quantities",
        "_test_opening_order_is_equivalent",
    ):
        assert test_name in FIXTURE
