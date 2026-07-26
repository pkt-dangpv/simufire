from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v2_fire_products.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_products_flag_is_default_off_and_wired():
    flag = "phase3_canonical_fire_products_shadow_enabled"
    assert f"@export var {flag}: bool = false" in ENGINE
    assert f'"{flag}"' in STATE
    assert "configure_phase3_canonical_fire_products_shadow" in ENGINE
    assert f"var {flag}: bool = false" in LOG


def test_runner_products_flag_enables_proposal_parent():
    cli = "--phase3-canonical-fire-products-shadow"
    assert cli in RUNNER
    assert cli in HEADLESS
    block = RUNNER[RUNNER.index("if args.phase3_canonical_fire_products_shadow") :]
    assert "--phase3-canonical-fire-proposal-shadow" in block


def test_products_solver_is_dictionary_only_and_non_mutating():
    body = _function(
        COMBUSTION, "evaluate_phase3_canonical_fire_products"
    )
    assert "room: RoomModel" not in body
    assert "room." not in body
    assert "legacy_species" not in body
    assert "_apply_species_generation_result" not in body
    assert "requested_species_kg" in body
    assert "accepted_species_kg" in body


def test_products_use_one_common_fraction_and_explicit_residuals():
    body = _function(
        COMBUSTION, "evaluate_phase3_canonical_fire_products"
    )
    assert "_scale_phase3_species(" in body
    assert "common_fraction" in body
    for residual in [
        "fuel_residual_MJ",
        "o2_residual_kg",
        "energy_residual_kj",
        "species_common_fraction_residual_kg",
        "accepted_carbon_residual_kg",
    ]:
        assert residual in body


def test_combustion_quality_excludes_fuel_cap():
    body = _function(
        COMBUSTION, "evaluate_phase3_canonical_fire_products"
    )
    quality_block = body[
        body.index("var quality_fraction: float = 1.0") :
        body.index("var smoke_yield: float")
    ]
    assert 'fire_proposal.get("o2_inventory_cap_kw"' in quality_block
    assert 'fire_proposal.get("ventilation_cap_kw"' in quality_block
    assert 'fire_proposal.get("fuel_cap_kw"' not in quality_block


def test_plume_geometry_remains_outside_products_solver():
    body = _function(
        COMBUSTION, "evaluate_phase3_canonical_fire_products"
    )
    assert "accepted_plume_driver_qc_kw" in body
    assert "0.071" not in body
    assert "z_eff" not in body
    assert "preview_phase3_coupled_plume_flux" not in body


def test_profile_is_frozen_in_persistent_state_and_marks_object_sync():
    snapshot = _function(COMBUSTION, "_snapshot_phase3_fire_product_profile")
    assert "object_sync_required_flag" in snapshot
    assert "_resolve_room_smoke_yield_kg_per_MJ" in snapshot
    assert "_resolve_room_co_yield_kg_per_MJ" in snapshot
    interpolate = _function(SYSTEM, "_interpolate_combustion_state")
    assert "var result: Dictionary = before.duplicate(true)" in interpolate


def test_products_schema_is_independently_gated():
    header = _function(LOG, "_build_csv_header")
    assert "if phase3_canonical_fire_products_shadow_enabled:" in header
    fields = _function(LOG, "_phase3_fire_products_fields")
    for field in [
        "phase3_shadow_fire_products_common_fraction",
        "phase3_shadow_fire_products_accepted_carbon_residual_kg",
        "phase3_shadow_fire_products_accepted_plume_driver_qc_kw",
    ]:
        assert field in fields
    assert 'for acceptance_name in ["requested", "accepted"]' in fields
    assert '"smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"' in fields


def test_runtime_fixture_covers_atomic_products():
    assert "PHASE3_F33V2_FIRE_PRODUCTS_PASS" in FIXTURE
    assert "_test_nominal_products_close" in FIXTURE
    assert "_test_partial_acceptance_uses_one_fraction" in FIXTURE
    assert "_test_fuel_cap_does_not_fake_rich_combustion" in FIXTURE
    assert "_test_zero_o2_stops_every_accepted_product" in FIXTURE
    assert "_test_carbon_cap_is_conservative" in FIXTURE
    assert "_test_explicit_object_profile_stays_shadow_only" in FIXTURE
