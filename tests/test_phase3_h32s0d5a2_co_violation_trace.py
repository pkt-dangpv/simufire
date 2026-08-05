"""Structural contracts for the H3.2-S0d5a2 CO first-violation causal trace."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d5a2_co_violation_trace.gd"
).read_text(encoding="utf-8")

FLAG = "phase3_co_first_violation_trace_enabled"


def test_flag_is_explicit_and_default_off():
    assert f"var {FLAG}: bool = false" in GAS
    assert f"@export var {FLAG}: bool = false" in ENGINE


def test_off_gate_is_the_first_statement():
    body = GAS.split("func _co_trace(", 1)[1].split("\nfunc ", 1)[0]
    statements = [
        line.strip()
        for line in body.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    guard = next(line for line in statements if line.startswith("if "))
    assert guard == f"if not {FLAG} or room == null:"


def test_trace_observes_and_never_repairs():
    body = GAS.split("func _co_trace(", 1)[1].split("\nfunc ", 1)[0]
    # It may read room CO but must never assign to it.
    assert "room.co_kg =" not in body
    assert "room.co_upper_kg =" not in body
    assert "clampf(" not in body
    for forbidden in ("proportional", "share", "repair", "fix"):
        assert forbidden not in body.lower()


def test_trace_distinguishes_creation_inheritance_and_resolution():
    body = GAS.split("func _co_trace(", 1)[1].split("\nfunc ", 1)[0]
    for key in ("new_violations", "inherited", "resolved", "observations"):
        assert key in body
    assert "_phase3_co_room_invalid" in body


def test_trace_is_placed_around_every_co_state_writer():
    for writer in (
        '_co_trace("inherited_pre_room_loop"',
        '_co_trace("accumulator_application"',
        '_co_trace("ach_infiltration"',
        '_co_trace("outside_open_species_purge"',
        '_co_trace("postfire_species_purge"',
        '_co_trace("final_upper_clamp"',
        '_co_trace("parcel_delivery"',
        '_co_trace("parcel_delivery_clamp"',
        '_co_trace("parcel_refund"',
        '_co_trace("pressure_vent_species"',
        '_co_trace("ppv_inlet_species"',
    ):
        assert writer in GAS, writer
    # The accumulator observation must follow the accumulator application.
    body = GAS.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
    assert body.index("room.co_kg = maxf(0.0, room.co_kg + float(co_delta_kg[int(room_id)]))") < body.index(
        '_co_trace("accumulator_application"'
    )
    assert body.index('_co_trace("accumulator_application"') < body.index(
        '_co_trace("ach_infiltration"'
    )
    # The final clamp observation must come after the clamp itself.
    assert body.index("room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)") < body.index(
        '_co_trace("final_upper_clamp"'
    )


def test_material_threshold_never_hides_the_strict_population():
    body = GAS.split("func _record_zonal_guard(", 1)[1].split("\nfunc ", 1)[0]
    assert "zonal_guard_upper_over_bulk_count" in body
    assert "zonal_guard_material_over_bulk_count" in body
    assert "zonal_guard_zero_headroom_count" in body
    # S0d5b replaced the hardcoded constant with a per-species lookup so no
    # species can inherit another's threshold. Both counters still coexist.
    assert "_material_eps_for(species)" in body
    eps = GAS.split("func _material_eps_for(", 1)[1].split("\nfunc ", 1)[0]
    assert "ZONAL_GUARD_MATERIAL_EPS_KG" in eps
    assert "ZONAL_GUARD_MATERIAL_EPS_CO2_KG" in eps
    assert "return 0.0" in eps
    # The material counter is nested inside the strict one, never replacing it.
    strict_at = body.index("entry[\"zonal_guard_upper_over_bulk_count\"] = \\")
    material_at = body.index("entry[\"zonal_guard_material_over_bulk_count\"] = \\")
    assert strict_at < material_at
    assert "const ZONAL_GUARD_MATERIAL_EPS_KG: float = 1.0e-9" in GAS


def test_sample_list_is_bounded():
    assert "const CO_TRACE_MAX_SAMPLES: int = 64" in GAS
    body = GAS.split("func _co_trace(", 1)[1].split("\nfunc ", 1)[0]
    assert "_phase3_co_first_events.size() < CO_TRACE_MAX_SAMPLES" in body


def test_export_is_a_deep_copy_and_reset_clears_it():
    body = GAS.split("func get_phase3_co_violation_trace(", 1)[1].split("\nfunc ", 1)[0]
    # S0d5b added the per-species view; every exported container stays a deep copy.
    assert body.count("duplicate(true)") == 3
    assert '"by_writer"' in body and '"by_species"' in body
    reset = GAS.split("func reset(", 1)[1].split("func begin_phase3_shadow_step(", 1)[0]
    for field in (
        "_phase3_co_trace_by_writer.clear()",
        "_phase3_co_room_invalid.clear()",
        "_phase3_co_first_events.clear()",
        "_phase3_co_trace_step = 0",
    ):
        assert field in reset


def test_export_is_opt_in_and_outside_the_csv():
    assert 'summary["phase3_co_violation_trace"]' in ENGINE
    gate = ENGINE.split('summary["phase3_co_violation_trace"]', 1)[0]
    assert gate.rstrip().endswith(f"if {FLAG}:")
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        assert "phase3_co_violation_trace" not in (ROOT / name).read_text(encoding="utf-8")


def test_cli_wiring_is_complete():
    assert '"--phase3-co-first-violation-trace"' in RUNNER
    assert f"engine.{FLAG} = true" in RUNNER
    assert '"--phase3-co-first-violation-trace"' in WRAPPER
    assert "args.phase3_co_first_violation_trace" in WRAPPER


def test_no_official_case_enables_the_trace():
    for path in (ROOT / "sim/validation/cases").glob("*.json"):
        assert FLAG not in path.read_text(encoding="utf-8"), path.name


def test_telemetry_never_governs_physics():
    for line in GAS.splitlines():
        if re.search(r"\b(if|elif|while)\b", line) and FLAG in line:
            assert f"if not {FLAG}" in line


def test_s0d5a_correction_is_unchanged():
    # S0d5a2 is diagnostic only: it must not alter the S0d5a experiment.
    assert "co_upper_delta_kg[from_id] -= co_moved_kg" in GAS
    assert "co_src_room.co_upper_kg += co_refund_kg" in GAS
    assert "co_src_room.co_upper_kg = minf(" in GAS


def test_untouched_subsystems():
    for name in (
        "sim/core/Phase3CoupledPressureSolver.gd",
        "sim/core/HVACSystem.gd",
        "sim/core/OxygenExchangeSystem.gd",
    ):
        assert "_co_trace" not in (ROOT / name).read_text(encoding="utf-8"), name
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()


def test_fixture_covers_the_mandatory_contracts():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0D5A2_CO_VIOLATION_TRACE_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    for label in (
        "trace flag defaults false",
        "one sample for one crossing",
        "sample names the creating writer",
        "valid state yields no finding",
        "no double creation",
        "inheritance is explicit",
        "resolution is counted",
        "a crossing after a resolution counts again",
        "caller context is carried",
        "only the material crossing passes the threshold",
        "the strict population is never hidden",
        "sample list is capped",
        "counters are not capped by the sample cap",
        "export is pure",
        "export is deterministic",
    ):
        assert label in FIXTURE, label
