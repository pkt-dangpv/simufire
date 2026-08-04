"""Structural contracts for passive H3.2-S0c GasExchangeSystem owner events."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0c_gas_physical_owners.gd"
).read_text(encoding="utf-8")
RUNTIME_FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0c_gas_owner_runtime.gd"
).read_text(encoding="utf-8")

RECORDER_CALLS = re.findall(
    r"_record_phase3_physical_owner_event\((.*?)\n\t*\)", GAS, re.S
)


def test_flag_is_reused_default_off_and_wired_to_gas():
    assert "@export var phase3_physical_owner_ledger_enabled: bool = false" in ENGINE
    assert "var phase3_physical_owner_ledger_enabled: bool = false" in GAS
    assert GAS.count("var phase3_physical_owner_ledger_enabled: bool = false") == 1
    configure_block = ENGINE.split("gas_exchange_system.configure({", 1)[1].split("})", 1)[0]
    assert (
        '"phase3_physical_owner_ledger_enabled": phase3_physical_owner_ledger_enabled'
        in configure_block
    )


def test_off_gate_precedes_event_construction():
    body = GAS.split("func _record_phase3_physical_owner_event(", 1)[1]
    body = body.split("func _assign_phase3_physical_owner_parcel_id(", 1)[0]
    assert "if not phase3_physical_owner_ledger_enabled" in body
    assert body.index("if not phase3_physical_owner_ledger_enabled") < body.index("make_event(")


def test_gas_ids_use_a_distinct_namespace():
    assert '"gas:%06d:%s:r%d"' in GAS
    assert '"thermal:%06d:%s:r%d"' in THERMAL
    assert '"gas:%06d:%s:r%d"' not in THERMAL


def test_step_local_reset_runs_once_per_tick_before_gas_writers():
    body = GAS.split("func begin_phase3_physical_owner_step(", 1)[1]
    body = body.split("func get_phase3_physical_owner_events(", 1)[0]
    assert "_phase3_physical_owner_events.clear()" in body
    assert "_phase3_physical_owner_sequence = 0" in body
    # Parcels cross timesteps, so their identity counter must NOT reset per step.
    assert "_phase3_physical_owner_parcel_sequence = 0" not in body
    step = ENGINE.split("func _step_gas_exchange(", 1)[1].split("func _step_hvac(", 1)[0]
    assert "gas_exchange_system.begin_phase3_physical_owner_step()" in step
    assert step.index("begin_phase3_physical_owner_step()") < step.index(
        "step_pressure_venting"
    )
    assert step.count("begin_phase3_physical_owner_step()") == 1


def test_full_reset_clears_cross_step_parcel_identity():
    body = GAS.split("func reset(", 1)[1].split("func begin_phase3_shadow_step(", 1)[0]
    assert "_phase3_physical_owner_events.clear()" in body
    assert "_phase3_physical_owner_sequence = 0" in body
    assert "_phase3_physical_owner_parcel_sequence = 0" in body


def test_generic_upper_layer_removal_gains_caller_provenance():
    # The S0 audit blocker: `remove_upper_layer_fraction` is a generic callback.
    # Every gas call site must now name its own physical mechanism.
    for owner in (
        '"gas_pressure_vent_upper_removal"',
        '"gas_exterior_smoke_vent_upper_removal"',
        '"gas_ppv_inlet_upper_removal"',
        '"gas_ppv_exhaust_upper_removal"',
    ):
        assert owner in GAS
    assert GAS.count("_call_room_fraction_owned(") == 5
    assert "_call_room_fraction(remove_upper_layer_fraction_callable" not in GAS


def test_exterior_removals_declare_an_explicit_direction():
    body = GAS.split("func _call_room_fraction_owned(", 1)[1].split("\nfunc ", 1)[0]
    assert 'owner_metadata["direction"] = "room_to_exterior"' in body
    assert "CLASS_EXTERIOR_BOUNDARY" in body
    assert 'room.id, -1, "upper", ""' in body


def test_interior_transport_debit_and_credit_share_one_accepted_value():
    assert "-moved_upper_gas_kg, 0.0, -moved_upper_energy_kj, 0.0," in GAS
    assert "moved_upper_gas_kg, moved_upper_energy_kj," in GAS
    assert "-gas_moved_bg, 0.0, -energy_moved_bg, 0.0," in GAS
    assert "gas_moved_bg, energy_moved_bg," in GAS


def test_delayed_parcels_are_never_consummated_transport():
    parcel_body = GAS.split(
        "func _record_phase3_physical_owner_parcel_event(", 1
    )[1].split("\nfunc ", 1)[0]
    assert "CLASS_DELAYED_PARCEL" in parcel_body
    assert "CLASS_INTERIOR_TRANSPORT" not in parcel_body
    for lifecycle in ('"created"', '"delivered"', '"cancelled"'):
        assert lifecycle in GAS
    assert GAS.count("_record_phase3_physical_owner_parcel_event(") == 4


def test_delivery_exposes_refund_conservation():
    assert '"original_species_kg": original_shadow_species_kg' in GAS
    assert '"delivered_species_kg": delivered_shadow_species_kg' in GAS
    assert '"refunded_species_kg": refunded_shadow_species_kg' in GAS
    assert '"parcel_refund_max_residual_kg"' in GAS


def test_existing_ledgers_are_not_reemitted_by_the_owner_ledger():
    joined = "\n".join(RECORDER_CALLS)
    for forbidden_owner in (
        '"doorway_species_direct"',
        '"doorway_species_counterflow"',
        '"background_species_exchange"',
        '"exterior_species_purge"',
        '"project_room_state"',
        '"gas_exchange_sync"',
    ):
        assert forbidden_owner not in joined


def test_projection_sync_is_not_owned_by_gas():
    # sync_room_upper_layer is projection/reconcile: it stays with the existing
    # ZoneFireSolver projection trace and must not become a gas owner event.
    assert "_call_room_dt(sync_room_upper_layer_callable" in GAS
    assert "sync_room_upper_layer_owned" not in GAS


def test_engine_combines_only_for_export_and_stays_fail_closed():
    body = ENGINE.split("func _phase3_physical_owner_events_combined(", 1)[1]
    body = body.split("func _phase3_runtime_ownership_snapshot(", 1)[0]
    assert "thermal_system.get_phase3_physical_owner_events()" in body
    assert "gas_exchange_system.get_phase3_physical_owner_events()" in body
    assert "Phase3PhysicalOwnerLedgerScript.aggregate_events(" in body
    export = ENGINE.split('summary["phase3_physical_owner_ledger"] = {', 1)[1]
    export = export.split("}", 1)[0]
    assert '"events": _phase3_physical_owner_events_combined()' in export
    assert '"summary": _phase3_physical_owner_summary_combined()' in export
    assert '"gas_summary": gas_exchange_system.get_phase3_physical_owner_summary()' in export


def test_no_csv_writer_or_state_schema_change():
    assert "phase3_physical_owner" not in (
        ROOT / "sim/core/SimulationLogWriter.gd"
    ).read_text(encoding="utf-8")
    assert "phase3_physical_owner" not in (
        ROOT / "sim/core/SimulationStateBuilder.gd"
    ).read_text(encoding="utf-8")


def test_coupled_pressure_solver_is_untouched():
    solver = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
    assert "phase3_physical_owner" not in solver
    assert "Phase3PhysicalOwnerLedger" not in solver


def test_no_reconstructed_stage_deltas_in_gas_owners():
    for forbidden in ("post_state - pre_state", "legacy_interior", "stage_delta"):
        assert forbidden not in GAS


def test_telemetry_never_governs_gas_physics():
    for line in GAS.splitlines():
        if re.search(r"\b(if|elif|while)\b", line) and "phase3_physical_owner" in line:
            assert "if not phase3_physical_owner_ledger_enabled" in line


def test_fixture_is_fail_closed_and_drives_real_mutations():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0C_GAS_PHYSICAL_OWNERS_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    assert "_apply_background_species_exchange" in FIXTURE
    assert "_release_pending_interior_deliveries" in FIXTURE
    assert "remove_upper_layer_fraction" in FIXTURE
    assert "duplicate id fails closed" in FIXTURE


def test_runtime_fixture_covers_every_instrumented_gas_family():
    assert "if _failed:" in RUNTIME_FIXTURE
    block = RUNTIME_FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0C_GAS_OWNER_RUNTIME_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    for entrypoint in ("step_pressure_venting", "step_ppv", "step_smoke"):
        assert f"gas.{entrypoint}(" in RUNTIME_FIXTURE
    for owner in (
        '"gas_pressure_vent_upper_removal"',
        '"gas_ppv_inlet_upper_removal"',
        '"gas_ppv_exhaust_upper_removal"',
        '"gas_exterior_smoke_vent_upper_removal"',
        '"gas_background_upper_transport"',
        '"gas_delayed_parcel_upper"',
    ):
        assert owner in RUNTIME_FIXTURE
    assert "parcel created at most once" in RUNTIME_FIXTURE
    assert "parcel delivered at most once" in RUNTIME_FIXTURE
    assert "created minus delivered equals in-flight inventory" in RUNTIME_FIXTURE
    assert "event ids unique across the run" in RUNTIME_FIXTURE


def test_cli_wiring_is_reused_not_duplicated():
    assert '"--phase3-physical-owner-ledger"' in WRAPPER
    assert '"--phase3-physical-owner-ledger"' in RUNNER
    assert RUNNER.count("engine.phase3_physical_owner_ledger_enabled = true") == 1
