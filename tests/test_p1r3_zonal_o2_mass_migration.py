"""Fail-first contracts for the default-off P1R3 zonal O2 mass shadow."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/p1r3_zonal_o2_mass_migration.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_structural_default_is_off_and_requires_persistent_shadow():
    assert "@export var phase3_o2_zonal_mass_shadow_enabled: bool = false" in ENGINE
    assert "var o2_zonal_mass_shadow_enabled: bool = false" in SYSTEM
    configure = _function(SYSTEM, "configure_o2_zonal_mass_shadow")
    assert "o2_zonal_mass_shadow_enabled = is_enabled" in configure
    engine_config = _function(ENGINE, "_configure_phase3_o2_zonal_mass_shadow")
    for gate in (
        "phase3_canonical_zone_shadow_enabled",
        "phase3_canonical_persistence_shadow_enabled",
        "phase3_o2_zonal_mass_shadow_enabled",
    ):
        assert gate in engine_config


def test_structural_conversion_contract_uses_molar_mass_ratio():
    assert "const O2_MOLAR_MASS_G_MOL: float = 31.999" in SYSTEM
    assert "const DRY_AIR_MOLAR_MASS_G_MOL: float = 28.9647" in SYSTEM
    to_mass = _function(SYSTEM, "_o2_molar_fraction_to_mass_kg")
    to_view = _function(SYSTEM, "_o2_mass_kg_to_molar_view")
    assert "O2_MOLAR_MASS_G_MOL / DRY_AIR_MOLAR_MASS_G_MOL" in to_mass
    assert "DRY_AIR_MOLAR_MASS_G_MOL / O2_MOLAR_MASS_G_MOL" in to_view
    assert '"known": false' in to_view
    assert '"reason": "zone_gas_mass_absent"' in to_view


def test_structural_snapshot_and_exterior_inputs_use_the_conversion():
    snapshot = _function(SYSTEM, "_snapshot_room")
    assert snapshot.count("_o2_molar_fraction_to_mass_kg(") == 2
    assert "if o2_zonal_mass_shadow_enabled" in snapshot
    counterflow = _function(SYSTEM, "queue_canonical_exterior_counterflow_requests")
    exterior = _function(SYSTEM, "_apply_canonical_exterior_boundary_requests")
    assert "_outside_o2_mass_kg(exchange_kg, outside_o2)" in counterflow
    assert "_outside_o2_mass_kg(requested_mass_kg, outside_o2)" in exterior


def test_structural_lower_mass_owner_is_persistent_and_read_only_to_room_model():
    begin_step = _function(SYSTEM, "begin_step")
    assert "_persistent_zone_state.has(room_key)" in begin_step
    assert "_snapshots[room_key] = persisted" in begin_step
    assert "room.lower_gas_kg =" not in SYSTEM
    assert "room.upper_gas_kg =" not in SYSTEM


def test_structural_fixture_covers_round_trip_unknown_persistence_and_atomicity():
    for marker in (
        "default OFF is legacy-identical",
        "molar-to-mass conversion",
        "mass-to-molar round trip",
        "absent zone is unknown",
        "persistent lower mass ignores legacy rewrite",
        "atomic O2 transfer conserves mass",
        "duplicate bundle is rejected",
        "P1R3_ZONAL_O2_MASS_MIGRATION_PASS",
    ):
        assert marker in FIXTURE
    assert "quit(1)" in FIXTURE
