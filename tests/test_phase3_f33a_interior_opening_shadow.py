from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (ROOT / "tests/fixtures/phase3_f33a_interior_opening_shadow.gd").read_text(
    encoding="utf-8"
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_canonical_interior_opening_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_interior_opening_shadow_enabled"' in STATE
    assert "phase3_canonical_interior_opening_authority" not in ENGINE


def test_preview_is_pure_and_uses_canonical_zones():
    body = _function(SYSTEM, "preview_canonical_interior_opening")
    assert "RoomModel" not in body
    assert "room." not in body
    assert "_canonical_zone_densities" in body
    assert "_integrate_canonical_interior_opening" in body


def test_all_openings_are_evaluated_before_one_network_bundle():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "descriptors.sort_custom" in body
    assert '"f33a_interior_network"' in body
    assert body.count("add_atomic_bundle(bundle)") == 1
    assert '"canonical_interior_opening_network"' in body


def test_network_bundle_caps_combined_source_zone_demands():
    atomic = _function(SYSTEM, "_apply_atomic_bundle")
    assert 'var demand_key: String = "%d|%s"' in atomic
    assert 'demand["gas_mass_kg"]' in atomic
    assert "_add_parcel_species(demand_species" in atomic


def test_payload_uses_source_zone_concentration_for_all_species():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert 'source_state.get(source_zone + "_gas_kg"' in body
    assert 'source_state.get(source_zone + "_energy_kj"' in body
    assert 'source_state.get(source_zone + "_o2_kg"' in body
    assert "for species_name in PARCEL_SPECIES" in body


def test_vertical_and_exterior_openings_are_excluded():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "op.is_exterior_opening()" in body
    assert "op.is_vertical" in body
    assert '"vertical"' in body


def test_legacy_horizontal_shadow_events_are_suppressed_only_in_shadow():
    for collector in (
        "_phase3_shadow_collect_thermal_species_events",
        "_phase3_shadow_collect_doorway_species_requests",
        "_phase3_shadow_collect_parcel_species_events",
        "_phase3_shadow_collect_immediate_species_events",
    ):
        body = _function(ENGINE, collector)
        assert "phase3_canonical_interior_opening_shadow_enabled" in body
        assert "_phase3_shadow_event_is_horizontal_interior_opening" in body
    helper = _function(ENGINE, "_phase3_shadow_event_is_horizontal_interior_opening")
    assert "op.is_vertical" in helper
    assert "op.is_exterior_opening()" in helper
    assert "op.open_fraction <= 0.0" in helper


def test_csv_schema_is_opt_in_and_complete():
    assert "var phase3_canonical_interior_opening_shadow_enabled: bool = false" in LOG
    assert "if phase3_canonical_interior_opening_shadow_enabled:" in LOG
    for field in (
        "phase3_shadow_interior_accepted_out_gas_kg_step",
        "phase3_shadow_interior_accepted_in_energy_kj_step",
        "phase3_shadow_interior_accepted_out_o2_kg_step",
        "phase3_shadow_interior_accepted_in_species_kg_step",
        "phase3_shadow_interior_mass_residual_kg",
        "phase3_shadow_interior_duplicate_owner_flag",
    ):
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_complete_prior_shadow_stack():
    block = RUNNER.split("if args.phase3_canonical_interior_opening_shadow:", 1)[1]
    for flag in (
        "--phase3-canonical-shadow",
        "--phase3-canonical-exterior-shadow",
        "--phase3-canonical-persistence-shadow",
        "--phase3-canonical-combustion-shadow",
        "--phase3-canonical-pressure-relaxation-shadow",
        "--phase3-canonical-plume-shadow",
        "--phase3-canonical-interzone-heat-shadow",
        "--phase3-canonical-wall-ambient-shadow",
        "--phase3-canonical-exterior-counterflow-shadow",
        "--phase3-canonical-post-opening-coupling-shadow",
        "--phase3-canonical-interior-opening-shadow",
    ):
        assert flag in block
    assert "engine.phase3_canonical_interior_opening_shadow_enabled = true" in HEADLESS


def test_headless_runner_reasserts_artifact_paths_after_case_overrides():
    override_pos = HEADLESS.index("_apply_engine_overrides(engine")
    log_pos = HEADLESS.index(
        'engine.log_file_path = _out_dir.path_join("sim_log.txt")', override_pos
    )
    csv_pos = HEADLESS.index(
        'engine.csv_log_file_path = _out_dir.path_join("sim_log.csv")', override_pos
    )
    assert override_pos < log_pos < csv_pos


def test_runtime_fixture_covers_order_and_conservation_contracts():
    assert "PHASE3_F33A_INTERIOR_OPENING_SHADOW_PASS" in FIXTURE
    for test_name in (
        "_test_equal_rooms_are_quiet",
        "_test_hot_room_has_bidirectional_exchange",
        "_test_one_zone_receiver_is_valid",
        "_test_atomic_transport_conserves_every_quantity",
        "_test_inventory_cap_is_global",
        "_test_reversed_opening_order_is_equivalent",
        "_test_vertical_opening_is_not_claimed",
    ):
        assert test_name in FIXTURE
