"""Supplementary structure checks, never substitutes for the real engine fixture."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def function(path, name):
    source = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(rf"^func {name}\(.*?(?=^func |^static func |\Z)", source, re.M | re.S)
    assert match
    return match.group()


def test_fire_keeps_candidates_local_until_reservation_then_scales_extensives():
    source = function("sim/fire/CombustionSystem.gd", "step_room_fire")
    assert source.index("reserve_combustion(") < source.index("room.hrr_kw = proposed_hrr_kw * accepted_fraction")
    assert "room.smoke_prod_kg_s = proposed_smoke_kg_s * accepted_fraction" in source
    assert "(proposed_pool_MJ - pool_before_MJ) * accepted_fraction" in source
    for token in ("generated_co_kg", "generated_co2_kg", "generated_hcn_kg", "solid_fuel_demand_MJ"):
        assert f"{token} *= accepted_fraction" in source
    assert source.index("generated_co_kg *= accepted_fraction") < source.index("_apply_species_generation_result(room,")
    assert "if not m3_acceptance and fire.remaining_fuel_MJ <= 0.0" in source
    assert "actual_solid_burn_kw * accepted_fraction," in source


def test_sink_settles_exactly_and_historical_cap_stays_in_legacy_branch():
    source = function("sim/core/OxygenExchangeSystem.gd", "_step_owned_room_inventory")
    current, historical = source.split("elif room.hrr_kw > 0.0:", 1)
    assert "consume_reserved_combustion(" in current
    assert "minf(" not in current
    assert "FIRE_SINK_BULK_CAP_FRACTION" in historical


def test_flashover_schedules_the_boost_instead_of_mutating_accepted_heat():
    source = function("sim/core/SimulationEngine.gd", "_try_trigger_flashover")
    assert "schedule_flashover_proposal(room, boosted_hrr_kw)" in source
    assert 'else:\n\t\t\troom.hrr_kw *= room.fire.flashover_hrr_multiplier' in source
    fire = function("sim/fire/CombustionSystem.gd", "step_room_fire")
    assert fire.index("take_flashover_proposal_kw(room)") < fire.index("reserve_combustion(")


def test_discard_removes_pending_power_and_mode_is_not_a_new_engine_switch():
    source = function("sim/core/RoomOxygenInventory.gd", "discard")
    assert "_next_flashover_power_kw.clear()" in source
    assert "_next_flashover_step.clear()" in source
    environment = function("sim/core/SimulationEngine.gd", "_o2_room_inventory_environment")
    assert '"combustion_acceptance_enabled": o2_room_inventory_enabled' in environment
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "var m3_combustion_enabled" not in engine


def test_fixture_covers_supported_scope_and_final_tick():
    fixture = (ROOT / "tests/fixtures/g3_o2_m3_integration.gd").read_text(encoding="utf-8")
    for label in ("last accepted fuel tick not erased", "refusal writes no pool",
                  "flashover cannot mutate accepted power", "live sink has no five percent cap",
                  "zero acceptance consumes no fuel", "rejected engine stops before upper heat"):
        assert label in fixture
    assert 'const Engine =' not in fixture  # Native Godot class name, parse error.
    assert 'var final_fire = world.room.fire' in fixture
    assert '_near(final_fire.remaining_fuel_MJ, 0.0,' in fixture
