"""Static supplementary guards; the judged GDScript fixture is required too.

These tests launch no Godot and do not prove runtime acceptance or M3 closure.
"""
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / "sim/core/RoomOxygenInventory.gd"
FIXTURE = ROOT / "tests/fixtures/g3_o2_m3_reservation.gd"
RUNNER = ROOT / "scripts/simulation/run_g3_o2_m3_reservation.py"


def function(name):
    source = OWNER.read_text(encoding="utf-8")
    match = re.search(rf"^func {name}\(.*?(?=^func |^static func |\Z)", source, re.M | re.S)
    assert match is not None
    return match.group()


def test_reservation_is_not_a_mass_commit():
    source = function("reserve_combustion")
    assert "_commit(" not in source
    assert "_apply_consumption(" not in source
    assert 'float(current["available_kg"])' in source
    assert 'float(current["inventory_kg"])' in source
    assert 'current["reserved"] = true' in source
    assert "combustion_already_reserved" in source
    assert "inventory_changed_before_combustion_acceptance" in source


def test_settlement_has_no_cap_and_uses_canonical_committer():
    source = function("consume_reserved_combustion")
    assert "minf(" not in source
    assert "FIRE_SINK_BULK_CAP_FRACTION" not in source
    assert "heat_changed_after_combustion_acceptance" in source
    assert "reserved_oxygen_no_longer_available" in source
    assert '_apply_consumption(room, current, reserved_kg, reserved_kg,' in source
    assert "unreserved_fire_debit" in function("consume")


@pytest.mark.parametrize("name", [
    "exchange_with_outside", "_dilution_error", "exchange_reference_gas_between_rooms",
    "exchange_between_rooms", "_deliver",
])
def test_every_outgoing_operation_checks_the_reservation_before_commit(name):
    source = function(name)
    assert "_reservation_error(" in source
    if "_commit(" in source:
        assert source.index("_reservation_error(") < source.index("_commit(")


def test_new_step_cannot_silently_drop_an_outstanding_reservation():
    source = function("begin_step")
    assert source.index("audit_combustion_reservations()") < source.index("_selections.clear()")
    assert "combustion_reservation_not_debited" in function("audit_combustion_reservations")


def test_reset_releases_both_reservations_and_mode():
    source = function("discard")
    assert "_selections.clear()" in source
    assert "_combustion_acceptance_enabled = false" in source


def test_dilution_still_has_one_canonical_arithmetic_path():
    assert "_outside_dilution_terms(" in function("_dilution_error")
    assert "_outside_dilution_terms(" in function("dilute_with_outside")
    assert "mixture_mole_fraction: float =" not in function("_dilution_error")


@pytest.mark.parametrize("label", [
    "reserve moves no oxygen", "no sink cap", "one reservation only", "one debit only",
    "invalid settlement atomic", "opening next step cannot discard outstanding reservation",
    "all negative obligations deducted", "other room unchanged on refusal",
])
def test_fixture_judges_each_declared_contract(label):
    assert label in FIXTURE.read_text(encoding="utf-8")


def test_runner_uses_existing_monitor_and_checks_payload_and_errors():
    source = RUNNER.read_text(encoding="utf-8")
    assert "prepare_environment(work)" in source
    assert "godot_monitored_launch.run(" in source
    assert "result.faults" in source and "result.preexisting" in source
    assert "SCRIPT ERROR" in source and "Parse Error" in source
    assert 'payload["failure_count"]' in source
    assert "subprocess.run(" not in source


def test_fixture_building_exposes_both_owner_lookup_methods():
    source = FIXTURE.read_text(encoding="utf-8")
    assert "func get_rooms()" in source
    assert "func get_room(room_id: int)" in source
