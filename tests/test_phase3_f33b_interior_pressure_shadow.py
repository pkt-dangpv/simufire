from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (ROOT / "tests/fixtures/phase3_f33b_interior_pressure_shadow.gd").read_text(
    encoding="utf-8"
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_reported():
    assert "@export var phase3_canonical_interior_pressure_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_interior_pressure_shadow_enabled"' in STATE


def test_pressure_preview_is_pure_and_signed():
    body = _function(SYSTEM, "preview_canonical_interior_pressure_flow")
    assert "RoomModel" not in body
    assert 'canonical_a.get("pressure_gauge_pa"' in body
    assert "_integrate_canonical_interior_opening" in body
    assert '"signed_net_a_to_b_kg"' in body


def test_network_uses_one_common_snapshot_and_one_atomic_bundle():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "pressure_routes_raw" in body
    assert "pressure_base_delta_by_room" in body
    assert "compute_interior_network_pressure_relaxation" in body
    assert body.count("add_atomic_bundle(bundle)") == 1
    assert '"f33a_interior_network"' in body


def test_pressure_routes_share_global_inventory_cap():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    append_pos = body.index("network_routes.append(pressure_route)")
    bundle_pos = body.index("make_atomic_bundle(")
    assert append_pos < bundle_pos
    assert '"canonical_interior_pressure"' in body


def test_relaxation_prevents_connected_pressure_crossing():
    body = _function(SYSTEM, "compute_interior_network_pressure_relaxation")
    assert "connection_pairs" in body
    assert "predicted_difference_pa" in body
    assert "pair_fraction" in body
    assert 'result["fraction"]' in body


def test_all_conserved_payloads_are_carried():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "pressure_energy_kj" in body
    assert "pressure_o2_kg" in body
    assert "pressure_species_kg" in body
    assert "for species_name in PARCEL_SPECIES" in body


def test_csv_schema_is_separately_opt_in():
    assert "var phase3_canonical_interior_pressure_shadow_enabled: bool = false" in LOG
    assert "if phase3_canonical_interior_pressure_shadow_enabled:" in LOG
    for field in (
        "phase3_shadow_interior_pressure_net_mass_kg_step",
        "phase3_shadow_interior_pressure_equilibrium_fraction",
        "phase3_shadow_interior_pressure_predicted_post_pa",
        "phase3_shadow_interior_pressure_species_residual_kg",
    ):
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_f33a_and_prior_stack():
    block = RUNNER.split("if args.phase3_canonical_interior_pressure_shadow:", 1)[1]
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
        "--phase3-canonical-interior-pressure-shadow",
    ):
        assert flag in block
    assert "engine.phase3_canonical_interior_pressure_shadow_enabled = true" in HEADLESS


def test_runtime_fixture_covers_core_contracts():
    assert "PHASE3_F33B_INTERIOR_PRESSURE_SHADOW_PASS" in FIXTURE
    for test_name in (
        "_test_signed_preview_direction",
        "_test_equal_pressure_is_quiet",
        "_test_network_relaxation_prevents_crossing",
        "_test_atomic_network_conserves_inventory",
        "_test_opening_order_is_equivalent",
        "_test_disabled_is_identical_to_f33a",
        "_test_vertical_opening_is_excluded",
    ):
        assert test_name in FIXTURE
