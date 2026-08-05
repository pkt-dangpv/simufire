"""Structural contracts for the H3.2-S0d5b experimental CO2 zonal transport fix."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d5b_co2_zonal_transport.gd"
).read_text(encoding="utf-8")

FLAG = "phase3_co2_zonal_transport_consistency_enabled"


def test_flag_is_explicit_and_default_off():
    assert f"var {FLAG}: bool = false" in GAS
    assert f"@export var {FLAG}: bool = false" in ENGINE
    assert ENGINE.count(f"@export var {FLAG}") == 1


def test_flag_governs_exactly_the_three_bulk_only_paths():
    conditioned = [
        line.strip()
        for line in GAS.splitlines()
        if re.search(r"\b(if|elif|while)\b", line) and FLAG in line
    ]
    assert len(conditioned) == 3
    for line in conditioned:
        assert line == f"if {FLAG}:"


def test_cap_uses_the_declared_lower_zone_not_an_invented_split():
    helper = GAS.split("func _co2_lower_stock_kg(", 1)[1].split("\nfunc ", 1)[0]
    # Same expression `_move_lower_zone_species` already uses for a lower move.
    assert "room.co2_kg - clampf(room.co2_upper_kg, 0.0, room.co2_kg)" in helper
    cap = GAS.split("func _cap_co2_lower_transfer(", 1)[1].split("\nfunc ", 1)[0]
    assert "_co2_lower_stock_kg(room_a)" in cap
    assert "_co2_lower_stock_kg(room_b)" in cap
    code = "\n".join(
        line for line in cap.splitlines() if not line.strip().startswith(("#", "##"))
    ).lower()
    for forbidden in ("proportional", "geometric", "fraction", "volume", "height", "post"):
        assert forbidden not in code, forbidden


def test_cap_preserves_sign_and_only_reduces():
    cap = GAS.split("func _cap_co2_lower_transfer(", 1)[1].split("\nfunc ", 1)[0]
    assert "minf(net_a_to_b_kg, _co2_lower_stock_kg(room_a))" in cap
    assert "-minf(-net_a_to_b_kg, _co2_lower_stock_kg(room_b))" in cap
    assert "return net_a_to_b_kg" in cap


def test_the_three_paths_are_the_declared_lower_to_lower_ones():
    # Background exchange records zero upper movement for CO2.
    background = GAS.split('"background_species_exchange", room_a, room_b, "co2"', 1)[1][:200]
    assert "net_co2_a_to_b, 0.0," in background
    # Vertical net exchange and vertical directed exchange both label CO2 lower.
    assert '"vertical_species_net_exchange", room_a, room_b, "lower", "co2"' in GAS
    assert '"lower", "lower", "co2", d_co2' in GAS
    # Each is preceded by the guarded cap.
    for anchor in (
        "net_co2_a_to_b = _cap_co2_lower_transfer(net_co2_a_to_b, room_a, room_b)",
        "d_co2 = minf(d_co2, _co2_lower_stock_kg(from_r))",
    ):
        assert anchor in GAS
    assert GAS.count("_cap_co2_lower_transfer(net_co2_a_to_b, room_a, room_b)") == 2


def test_symmetric_co2_paths_are_untouched():
    # Immediate transport, counterflow, two-zone and exterior purges already move
    # bulk and upper together and must not be conditioned by this flag.
    for line in (
        "co2_delta_kg[from_id] -= co2_moved_kg",
        "co2_upper_delta_kg[from_id] -= co2_upper_moved_kg",
        "co2_delta_kg[to_id] += co2_moved_kg",
        "co2_upper_delta_kg[to_id] += co2_upper_moved_kg",
        "co2_upper_delta_kg[from_id] += target_co2_upper_out_kg - source_co2_upper_out_kg",
    ):
        assert line in GAS
        preceding = GAS.split(line, 1)[0].rstrip().splitlines()[-1].strip()
        assert FLAG not in preceding


def test_out_of_scope_species_and_systems_are_untouched():
    for name in (
        "sim/core/Phase3CoupledPressureSolver.gd",
        "sim/core/HVACSystem.gd",
        "sim/core/OxygenExchangeSystem.gd",
        "sim/core/SimulationLogWriter.gd",
        "sim/core/SimulationStateBuilder.gd",
    ):
        assert FLAG not in (ROOT / name).read_text(encoding="utf-8"), name
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()
    # HCN and O2 keep their legacy statements, unconditioned.
    assert "hcn_delta_kg[room_a.id] -= net_hcn_a_to_b" in GAS
    assert "o2_delta_kg[room_a.id] -= net_o2_a_to_b" in GAS
    for line in ("hcn_delta_kg[room_a.id] -= net_hcn_a_to_b",
                 "o2_delta_kg[room_a.id] -= net_o2_a_to_b"):
        preceding = GAS.split(line, 1)[0].rstrip().splitlines()[-1].strip()
        assert FLAG not in preceding


def test_final_clamp_and_co_fix_are_untouched():
    assert "room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)" in GAS
    clamp_block = GAS.split('_record_zonal_guard("co2"', 1)[1][:400]
    assert FLAG not in clamp_block
    # The S0d5a CO experiment must be untouched.
    assert "co_upper_delta_kg[from_id] -= co_moved_kg" in GAS
    assert "phase3_co_zonal_transport_consistency_enabled" in GAS


def test_strict_and_material_counters_both_remain():
    body = GAS.split("func _record_zonal_guard(", 1)[1].split("\nfunc ", 1)[0]
    assert "zonal_guard_upper_over_bulk_count" in body
    assert "zonal_guard_material_over_bulk_count" in body
    assert FLAG not in body


def test_no_official_case_enables_the_experiment():
    for path in (ROOT / "sim/validation/cases").glob("*.json"):
        assert FLAG not in path.read_text(encoding="utf-8"), path.name


def test_cli_wiring_is_complete():
    assert '"--phase3-co2-zonal-transport-consistency"' in RUNNER
    assert f"engine.{FLAG} = true" in RUNNER
    assert '"--phase3-co2-zonal-transport-consistency"' in WRAPPER
    assert "args.phase3_co2_zonal_transport_consistency" in WRAPPER


def test_fixture_covers_the_mandatory_contracts():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0D5B_CO2_ZONAL_TRANSPORT_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    for label in (
        "CO2 zonal flag defaults false",
        "lower stock is bulk minus upper",
        "violated state yields zero lower stock",
        "positive net capped by the source lower stock",
        "negative net capped by b's lower stock, sign kept",
        "a fitting transfer is not altered",
        "OFF drives the source derived lower stock negative",
        "ON moves exactly the available lower stock",
        "bulk CO2 is conserved across the corrected transfer",
        "a lower-to-lower move never touches the upper stock",
        "the derived lower stock never goes negative",
        "ON needs no clamp to keep upper at or below bulk",
        "ON vertical directed move equals the lower stock",
        "is unchanged by the CO2 experiment",
    ):
        assert label in FIXTURE, label
    assert "_apply_background_species_exchange(" in FIXTURE
    assert "_apply_directed_species_exchange(" in FIXTURE
