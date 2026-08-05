"""Structural contracts for the H3.2-S0d5a experimental CO zonal transport fix."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d5a_co_zonal_transport.gd"
).read_text(encoding="utf-8")

FLAG = "phase3_co_zonal_transport_consistency_enabled"


def test_flag_is_explicit_and_default_off():
    assert f"var {FLAG}: bool = false" in GAS
    assert f"@export var {FLAG}: bool = false" in ENGINE
    assert ENGINE.count(f"@export var {FLAG}") == 1


def test_flag_governs_exactly_two_sites():
    conditioned = [
        line.strip()
        for line in GAS.splitlines()
        if re.search(r"\b(if|elif|while)\b", line) and FLAG in line
    ]
    assert len(conditioned) == 2
    for line in conditioned:
        assert line == f"if {FLAG}:"


def test_source_debit_is_symmetric_when_enabled():
    body = GAS.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
    assert "co_delta_kg[from_id] -= co_moved_kg" in body
    block = body.split("co_delta_kg[from_id] -= co_moved_kg", 1)[1][:600]
    assert f"if {FLAG}:" in block
    assert "co_upper_delta_kg[from_id] -= co_moved_kg" in block
    # The corrected debit uses the same accepted amount, not a second cap.
    assert "co_upper_delta_kg[from_id] -= co_moved_kg * " not in block


def test_refund_drops_the_second_upper_cap_when_enabled():
    body = GAS.split("func _release_pending_interior_deliveries(", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    assert "co_src_room.co_upper_kg += co_refund_kg" in body
    # The legacy branch must survive untouched for OFF.
    assert "co_src_room.co_upper_kg = minf(" in body
    assert f"if {FLAG}:" in body


def test_only_co_is_touched():
    body = GAS.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
    for forbidden in (
        f"if {FLAG}:\n\t\t\t\tco2_upper_delta_kg",
        f"if {FLAG}:\n\t\t\t\thcn_upper_delta_kg",
    ):
        assert forbidden not in body
    # CO2 and HCN keep their legacy symmetric debits, unconditioned.
    assert "co2_upper_delta_kg[from_id] -= co2_upper_moved_kg" in body
    assert "hcn_upper_delta_kg[from_id] -= hcn_upper_moved_kg" in body


def test_final_upper_clamp_is_untouched():
    for line in (
        "room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)",
        "room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)",
        "room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)",
    ):
        assert line in GAS
    clamp_block = GAS.split("_record_zonal_guard(\"co\"", 1)[1][:400]
    assert FLAG not in clamp_block


def test_transport_order_is_unchanged():
    body = GAS.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
    assert body.index("co_delta_kg[from_id] -= co_moved_kg") < body.index(
        "co2_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.co2_kg"
    )
    assert "co_moved_kg = minf(\n\t\t\t\tminf(kg / source.smoke_kg, 1.0) * source.co_upper_kg,\n\t\t\t\tsource.co_kg\n\t\t\t)" in body


def test_no_official_case_enables_the_experiment():
    for path in (ROOT / "sim/validation/cases").glob("*.json"):
        assert FLAG not in path.read_text(encoding="utf-8"), path.name


def test_cli_wiring_is_complete():
    assert '"--phase3-co-zonal-transport-consistency"' in RUNNER
    assert f"engine.{FLAG} = true" in RUNNER
    assert '"--phase3-co-zonal-transport-consistency"' in WRAPPER
    assert "args.phase3_co_zonal_transport_consistency" in WRAPPER


def test_untouched_subsystems():
    for name in (
        "sim/core/Phase3CoupledPressureSolver.gd",
        "sim/core/HVACSystem.gd",
        "sim/core/OxygenExchangeSystem.gd",
        "sim/core/SimulationLogWriter.gd",
        "sim/core/SimulationStateBuilder.gd",
    ):
        assert FLAG not in (ROOT / name).read_text(encoding="utf-8"), name
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()


def test_telemetry_flags_are_independent_of_the_correction():
    body = GAS.split("func _record_zonal_guard(", 1)[1].split("\nfunc ", 1)[0]
    assert FLAG not in body
    body = GAS.split("func _record_species_attribution(", 1)[1].split("\nfunc ", 1)[0]
    assert FLAG not in body


def test_fixture_covers_the_mandatory_contracts():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0D5A_CO_ZONAL_TRANSPORT_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    for label in (
        "CO zonal flag defaults false",
        "OFF leaves the source upper stock untouched",
        "OFF pushes the entire debit onto the derived lower stock",
        "ON debits bulk and upper with the same accepted amount",
        "the source derived lower stock is invariant",
        "source upper stays non-negative",
        "ON keeps upper at or below bulk in the corrected path",
        "refund credits bulk and upper equally in a clean state",
        "ON refunds bulk and upper equally even from a violated state",
        "OFF caps the upper refund separately from a violated state",
        "cancellation creates no bulk CO",
        "is unchanged by the CO experiment",
    ):
        assert label in FIXTURE, label
    assert "step_smoke(" in FIXTURE
    assert "_release_pending_interior_deliveries(" in FIXTURE
