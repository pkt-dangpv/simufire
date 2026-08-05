"""Structural contracts for H3.2-S0d1 suppression owner and donor-less seeds."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d1_suppression_and_seeds.gd"
).read_text(encoding="utf-8")


def test_flag_is_reused_and_default_off():
    assert "@export var phase3_physical_owner_ledger_enabled: bool = false" in ENGINE
    assert ENGINE.count("@export var phase3_physical_owner_ledger_enabled") == 1


def test_off_gate_precedes_engine_event_construction():
    body = ENGINE.split("func _record_phase3_physical_owner_engine_event(", 1)[1]
    body = body.split("func get_phase3_physical_owner_engine_events(", 1)[0]
    assert "if not phase3_physical_owner_ledger_enabled" in body
    assert body.index("if not phase3_physical_owner_ledger_enabled") < body.index(
        "make_event("
    )


def test_engine_ids_use_a_distinct_namespace():
    assert '"engine:%06d:%s:r%d"' in ENGINE
    assert '"engine:%06d:%s:r%d"' not in THERMAL
    assert '"engine:%06d:%s:r%d"' not in GAS


def test_engine_accumulator_is_step_local():
    body = ENGINE.split("func _phase3_physical_owner_begin_step(", 1)[1]
    body = body.split("func _record_phase3_physical_owner_engine_event(", 1)[0]
    assert "_phase3_physical_owner_engine_events.clear()" in body
    assert "_phase3_physical_owner_engine_sequence = 0" in body
    step = ENGINE.split("func step(", 1)[1].split("func ignite_room(", 1)[0]
    assert "_phase3_physical_owner_begin_step()" in step
    assert step.index("_phase3_physical_owner_begin_step()") < step.index(
        "_step_suppression(dt)"
    )


def test_suppression_upper_sink_is_an_accepted_local_source():
    body = ENGINE.split("func _apply_suppression_to_room(", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    assert "var suppression_upper_energy_before_kj: float = room.upper_energy_kj" in body
    assert '"suppression_upper_energy_sink"' in body
    assert "Phase3PhysicalOwnerLedgerScript.CLASS_LOCAL_SOURCE" in body
    # The recorded delta is the accepted mutation, measured at this single site.
    assert "room.upper_energy_kj - suppression_upper_energy_before_kj" in body
    assert '"steam_storage_kg": room.steam_kg' in body
    # The event must be emitted after the mutation, before the projection sync.
    assert body.index("room.upper_energy_kj = maxf(0.0, room.upper_energy_kj - upper_loss_kj)") < body.index(
        '"suppression_upper_energy_sink"'
    )
    assert body.index('"suppression_upper_energy_sink"') < body.index(
        'sync_room_upper_layer(room, dt, "suppression_sync")'
    )


def test_no_lower_suppression_owner_is_fabricated():
    # The lower cooling is written as a temperature and discarded by the
    # projection, so there is no accepted lower energy sink to own.
    assert "suppression_lower_energy_sink" not in ENGINE
    assert "suppression_lower_energy_sink" not in THERMAL
    body = ENGINE.split("func _apply_suppression_to_room(", 1)[1].split("\nfunc ", 1)[0]
    assert "room.temp_lower_c = maxf(ambient_c, room.temp_lower_c - lower_drop_c)" in body
    assert body.count("_record_phase3_physical_owner_engine_event(") == 1


def test_donor_less_seeds_are_declared_numerical_corrections():
    for owner in (
        '"thermal_opening_radiation_target_mass_seed"',
        '"thermal_counterflow_minimum_upper_mass"',
    ):
        assert owner in THERMAL
        block = THERMAL.split(owner, 1)[1][:400]
        assert "CLASS_NUMERICAL_CORRECTION" in block
        assert '"donor": "none"' in block
        assert '"reason": "empty_upper_layer_initialisation"' in block


def test_seeds_measure_the_accepted_mutation_not_a_stage_delta():
    assert "tgt.upper_gas_kg - seed_upper_mass_before_kg" in THERMAL
    assert "cold_room.upper_gas_kg - counterflow_seed_before_kg" in THERMAL
    for forbidden in ("post_state - pre_state", "legacy_interior", "stage_delta"):
        assert forbidden not in THERMAL
        assert forbidden not in ENGINE


def test_numerical_corrections_cannot_reach_the_source_vector():
    ledger = (ROOT / "sim/core/Phase3PhysicalOwnerLedger.gd").read_text(encoding="utf-8")
    block = ledger.split("func _aggregate_valid_event(", 1)[1].split("\nstatic func ", 1)[0]
    assert "CLASS_LOCAL_SOURCE" in block and "CLASS_EXTERIOR_BOUNDARY" in block
    assert "CLASS_NUMERICAL_CORRECTION" not in block


def test_projection_ledgers_are_not_reemitted():
    for forbidden in (
        '"project_room_state"',
        '"final_clamp_active"',
        '"suppression_sync"',
        '"two_zone_boundary_energy_kj"',
    ):
        assert forbidden not in re.findall(
            r"_record_phase3_physical_owner_engine_event\((.*?)\n\t\)", ENGINE, re.S
        )


def test_hvac_stays_deferred():
    hvac = (ROOT / "sim/core/HVACSystem.gd").read_text(encoding="utf-8")
    assert "phase3_physical_owner" not in hvac
    assert "Phase3PhysicalOwnerLedger" not in hvac


def test_coupled_pressure_solver_is_untouched():
    solver = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
    assert "phase3_physical_owner" not in solver


def test_no_integrator_was_created():
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()


def test_no_csv_writer_or_state_schema_change():
    assert "phase3_physical_owner" not in (
        ROOT / "sim/core/SimulationLogWriter.gd"
    ).read_text(encoding="utf-8")
    assert "phase3_physical_owner" not in (
        ROOT / "sim/core/SimulationStateBuilder.gd"
    ).read_text(encoding="utf-8")


def test_telemetry_never_governs_engine_physics():
    # Only two branches may read the flag: the recorder's own OFF gate and the
    # technical-summary export gate. Neither is on a physics path.
    export_gate = "if phase3_physical_owner_ledger_enabled:"
    conditioned = [
        line.strip()
        for line in ENGINE.splitlines()
        if re.search(r"\b(if|elif|while)\b", line) and "phase3_physical_owner" in line
    ]
    for line in conditioned:
        assert line.startswith("if not phase3_physical_owner_ledger_enabled") or line == export_gate
    summary = ENGINE.split("func build_technical_summary(", 1)[1].split("\nfunc ", 1)[0]
    assert summary.count(export_gate) == 1
    assert ENGINE.count(export_gate) == 1


def test_fixture_is_fail_closed_and_drives_real_sites():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0D1_SUPPRESSION_AND_SEEDS_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    assert "_apply_suppression_to_room" in FIXTURE
    assert "_step_radiation_openings" in FIXTURE
    assert "_apply_doorway_thermal_counterflow" in FIXTURE
    assert "projection discards the suppression lower temperature write" in FIXTURE
    assert "invalid aggregate exposes no partial source" in FIXTURE
