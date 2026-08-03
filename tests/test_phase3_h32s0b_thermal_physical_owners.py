"""Structural contracts for passive H3.2-S0b thermal owner events."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (ROOT / "tests/fixtures/phase3_h32s0b_thermal_physical_owners.gd").read_text(encoding="utf-8")


def test_flag_is_default_off_and_wired_to_thermal_only():
    assert "@export var phase3_physical_owner_ledger_enabled: bool = false" in ENGINE
    assert "var phase3_physical_owner_ledger_enabled: bool = false" in THERMAL
    assert '"phase3_physical_owner_ledger_enabled": phase3_physical_owner_ledger_enabled' in ENGINE
    assert "gas_exchange_system.configure" in ENGINE


def test_off_gate_precedes_event_construction():
    body = THERMAL.split("func _record_phase3_physical_owner_event(", 1)[1]
    body = body.split("func _record_phase3_interzone(", 1)[0]
    assert "if not phase3_physical_owner_ledger_enabled" in body
    assert body.index("if not phase3_physical_owner_ledger_enabled") < body.index("make_event(")


def test_step_local_reset_is_before_room_loop():
    body = THERMAL.split("func step(", 1)[1].split("func _step_radiation_openings", 1)[0]
    reset = body.index("_phase3_physical_owner_events.clear()")
    loop = body.index("for room_id in building.get_rooms().keys()")
    assert reset < loop
    assert "_phase3_physical_owner_sequence = 0" in body[:loop]


def test_only_explicit_accepted_values_feed_events():
    for required in (
        "convective_energy_kj",
        "radiative_loss_kj",
        "energy_to_lower_kj",
        "energy_to_ambient_kj",
        "wall_absorption_kj",
        "wall_emission_kj",
        "lower_decay_kj",
        "lower_fresh_air_cooling_kj",
        "mix_energy_kj",
    ):
        assert required in THERMAL
    for forbidden in ("post_state - pre_state", "legacy_interior", "stage_delta"):
        assert forbidden not in THERMAL


def test_existing_projection_and_canonical_doorway_are_not_reemitted():
    for forbidden_owner in (
        '"project_room_state"',
        '"canonical_doorway_upper"',
        '"canonical_doorway_lower"',
        '"doorway_thermal_counterflow"',
    ):
        assert forbidden_owner not in re.findall(
            r"_record_phase3_physical_owner_event\((.*?)\)", THERMAL, re.S
        )


def test_source_classes_are_explicit():
    assert "CLASS_LOCAL_SOURCE" in THERMAL
    assert "CLASS_EXTERIOR_BOUNDARY" in THERMAL
    assert "CLASS_INTERIOR_TRANSPORT" in THERMAL
    assert "CLASS_INTERZONE_REDISTRIBUTION" in THERMAL


def test_outside_assisted_transport_splits_delivery_and_loss():
    assert '"thermal_outside_assisted_upper_transport"' in THERMAL
    assert '"thermal_outside_assisted_transport_loss"' in THERMAL
    assert "source_energy_removed_kj - energy_moved_kj" in THERMAL
    assert '"thermal_outside_assisted_lower_transport"' in THERMAL
    assert '"thermal_outside_assisted_lower_loss"' in THERMAL


def test_surface_storage_counterpart_is_visible_metadata():
    assert THERMAL.count('"surface_storage_energy_delta_kj"') >= 4


def test_no_csv_writer_or_state_schema_change():
    assert "phase3_physical_owner" not in (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
    assert "phase3_physical_owner" not in (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")


def test_cli_wiring_is_complete():
    assert '"--phase3-physical-owner-ledger"' in WRAPPER
    assert '"--phase3-physical-owner-ledger"' in RUNNER
    assert "engine.phase3_physical_owner_ledger_enabled = true" in RUNNER


def test_fixture_is_fail_closed_and_exercises_real_mutations():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split("PHASE3_H32S0B_THERMAL_PHYSICAL_OWNERS_PASS", 1)[0]
    assert "quit(1)" in block and "return" in block
    assert "_apply_post_transfer_vertical_mix" in FIXTURE
    assert "_ensure_minimal_upper_gas" in FIXTURE


def test_telemetry_never_governs_thermal_physics():
    for line in THERMAL.splitlines():
        if re.search(r"\b(if|elif|while)\b", line) and "phase3_physical_owner" in line:
            assert "if not phase3_physical_owner_ledger_enabled" in line
