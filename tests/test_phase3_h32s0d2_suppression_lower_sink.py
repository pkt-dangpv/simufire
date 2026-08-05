"""Structural contracts for the H3.2-S0d2 experimental suppression lower sink."""

from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d2_suppression_lower_sink.gd"
).read_text(encoding="utf-8")

FLAG = "phase3_suppression_lower_energy_sink_enabled"


def test_flag_is_explicit_and_default_off():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    assert ENGINE.count(f"@export var {FLAG}") == 1


def test_off_gate_is_the_first_statement_of_the_sink():
    body = ENGINE.split("func _apply_suppression_lower_energy_sink(", 1)[1]
    body = body.split("func _apply_suppression_to_room(", 1)[0]
    statements = [
        line.strip()
        for line in body.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    first_guard = next(line for line in statements if line.startswith("if "))
    assert first_guard == f"if not {FLAG}:"


def test_correction_is_confined_to_the_two_zone_regime():
    body = ENGINE.split("func _apply_suppression_lower_energy_sink(", 1)[1]
    body = body.split("func _apply_suppression_to_room(", 1)[0]
    assert "not two_zone_solver_enabled" in body
    assert "zone_fire_solver.ensure_room_state(" in body
    assert "zone_fire_solver.add_lower_energy(" in body
    # The legacy temperature write must stay exactly where it was.
    legacy = ENGINE.split("func _apply_suppression_to_room(", 1)[1].split("\nfunc ", 1)[0]
    assert "room.temp_lower_c = maxf(ambient_c, room.temp_lower_c - lower_drop_c)" in legacy


def test_accepted_is_clipped_and_never_the_request():
    body = ENGINE.split("func _apply_suppression_lower_energy_sink(", 1)[1]
    body = body.split("func _apply_suppression_to_room(", 1)[0]
    assert "var available_lower_energy_kj: float = maxf(0.0, room.lower_energy_kj)" in body
    assert "minf(\n\t\trequested_lower_cooling_kj, available_lower_energy_kj\n\t)" in body
    # The owner delta is measured around the mutation, not taken from the request.
    assert "room.lower_energy_kj - lower_energy_before_kj" in body
    assert "requested_lower_cooling_kj," in body
    assert '"accepted_lower_cooling_kj": accepted_lower_cooling_kj' in body
    assert '"rejected_lower_cooling_kj"' in body


def test_requested_reuses_the_legacy_formula():
    legacy = ENGINE.split("func _apply_suppression_to_room(", 1)[1].split("\nfunc ", 1)[0]
    assert "_apply_suppression_lower_energy_sink(\n\t\troom, water_l, lower_drop_c * lower_mass_kg, ambient_c\n\t)" in legacy
    # No new cooling formula was introduced.
    assert legacy.count("suppression_lower_cooling_fraction") == 1


def test_owner_is_a_signed_local_source():
    body = ENGINE.split("func _apply_suppression_lower_energy_sink(", 1)[1]
    body = body.split("func _apply_suppression_to_room(", 1)[0]
    assert '"suppression_lower_energy_sink"' in body
    assert "Phase3PhysicalOwnerLedgerScript.CLASS_LOCAL_SOURCE" in body
    assert '"mechanism": "suppression_water_spray"' in body
    assert '"steam_storage_kg": room.steam_kg' in body


def test_upper_owner_is_untouched():
    legacy = ENGINE.split("func _apply_suppression_to_room(", 1)[1].split("\nfunc ", 1)[0]
    assert legacy.count('"suppression_upper_energy_sink"') == 1
    assert legacy.count("_record_phase3_physical_owner_engine_event(") == 1


def test_no_official_case_enables_the_experiment():
    for path in (ROOT / "sim/validation/cases").glob("*.json"):
        assert FLAG not in path.read_text(encoding="utf-8"), path.name


def test_case_settings_and_runner_wiring_exist():
    assert '"--phase3-suppression-lower-energy-sink"' in RUNNER
    assert f"engine.{FLAG} = true" in RUNNER
    assert '"--phase3-suppression-lower-energy-sink"' in WRAPPER
    assert "args.phase3_suppression_lower_energy_sink" in WRAPPER
    # engine_overrides is the generic per-case setting channel.
    assert "_apply_engine_overrides(engine, scenario.get(\"engine_overrides\", {}))" in RUNNER


def test_telemetry_never_governs_the_correction():
    # The physics gate is the experimental flag alone; the ledger flag only
    # decides whether the owner event is recorded.
    body = ENGINE.split("func _apply_suppression_lower_energy_sink(", 1)[1]
    body = body.split("func _apply_suppression_to_room(", 1)[0]
    assert "phase3_physical_owner_ledger_enabled" not in body


def test_untouched_subsystems():
    for name in (
        "sim/core/Phase3CoupledPressureSolver.gd",
        "sim/core/HVACSystem.gd",
        "sim/core/SimulationLogWriter.gd",
        "sim/core/SimulationStateBuilder.gd",
    ):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert FLAG not in text
        assert "phase3_physical_owner" not in text
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()


def test_no_expected_or_tolerance_change():
    report = json.loads(
        (ROOT / "sim/validation/reports/reference_checks.json").read_text(encoding="utf-8")
    )
    assert report["required_count"] == 353
    assert report["failed_required_count"] == 6


def test_fixture_covers_the_mandatory_contracts():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0D2_SUPPRESSION_LOWER_SINK_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    for label in (
        "experimental flag defaults false",
        "OFF lower energy identical",
        "ON reduces lower energy",
        "ON lower temperature falls after the sync",
        "accepted never exceeds requested",
        "accepted never exceeds availability",
        "lower energy never negative",
        "no NaN with an empty lower layer",
        "owner records the accepted mutation",
        "upper sink still emitted exactly once",
        "projection is never counted as suppression",
        "legacy temperature invariant",
        "lower id",
    ):
        assert label in FIXTURE, label
    assert "_apply_suppression_to_room" in FIXTURE
