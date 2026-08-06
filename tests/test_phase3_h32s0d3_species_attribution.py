"""Structural contracts for the H3.2-S0d3 species/O2 attribution measurement."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
WRAPPER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32s0d3_species_attribution.gd"
).read_text(encoding="utf-8")

FLAG = "phase3_species_attribution_diagnostics_enabled"


def test_flag_is_explicit_and_default_off():
    assert f"var {FLAG}: bool = false" in GAS
    assert f"@export var {FLAG}: bool = false" in ENGINE
    configure = ENGINE.split("gas_exchange_system.configure({", 1)[1].split("})", 1)[0]
    assert f'"{FLAG}": \\' in configure or f'"{FLAG}":' in configure


def test_off_gate_precedes_every_record():
    for func_name in ("_record_species_attribution(", "_record_species_attribution_o2("):
        body = GAS.split(f"func {func_name}", 1)[1].split("\nfunc ", 1)[0]
        statements = [
            line.strip()
            for line in body.splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        guard = next(line for line in statements if line.startswith("if "))
        assert guard == f"if not {FLAG}:"


def test_measurement_never_distributes_a_clamped_deficit():
    body = GAS.split("func _record_species_attribution(", 1)[1].split("\nfunc ", 1)[0]
    for forbidden in (
        "proportional", "fifo", "priority", "share_kg", "split_kg", "weight",
    ):
        assert forbidden not in body.lower()
    # Only aggregate counters and totals may be written.
    assert "clamp_bound_count" in body
    assert "max_clamp_deficit_kg" in body
    assert "requested_kg_total" in body
    assert "accepted_kg_total" in body


def test_zone_identity_is_declared_not_inferred():
    block = GAS.split("const SPECIES_ZONE_IDENTITY: Dictionary = {", 1)[1].split("}", 1)[0]
    for species, identity in (
        ("o2", "bulk_only"),
        ("smoke", "bulk_only"),
        ("hcl", "bulk_only"),
        ("acrolein", "bulk_only"),
        ("formaldehyde", "bulk_only"),
        ("co", "bulk_and_upper"),
        ("co2", "bulk_and_upper"),
        ("hcn", "bulk_and_upper"),
        ("co_upper", "upper_zone"),
        ("co2_upper", "upper_zone"),
        ("hcn_upper", "upper_zone"),
    ):
        assert f'"{species}": "{identity}"' in block, species


def test_o2_records_both_clamp_bounds():
    body = GAS.split("func _record_species_attribution_o2(", 1)[1].split("\nfunc ", 1)[0]
    assert "clamp_bound_count" in body
    assert "clamp_high_bound_count" in body
    assert "o2_nominal" in body
    # O2 is a bulk fraction: the measurement must not assign it a zone.
    assert '"upper"' not in body and '"lower"' not in body


def test_measurement_sits_at_the_single_application_site():
    body = GAS.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
    assert body.count("_record_species_attribution_o2(") == 1
    assert body.count("_record_species_attribution(") == 10
    # Every record must precede the mutation it measures.
    assert body.index("_record_species_attribution_o2(") < body.index(
        "room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)"
    )
    assert body.index('_record_species_attribution(\n\t\t\t"smoke"') < body.index(
        "room.smoke_kg = maxf(0.0, room.smoke_kg + float(smoke_delta_kg[int(room_id)]))"
    )


def test_no_post_state_reconstruction_and_no_legacy_transport_input():
    body = GAS.split("func _record_species_attribution(", 1)[1].split("\nfunc ", 1)[0]
    for forbidden in ("post_state", "legacy_interior", "stage_delta", "co_net_transport"):
        assert forbidden not in body


def test_export_is_opt_in_and_outside_the_csv():
    assert 'summary["phase3_species_attribution"]' in ENGINE
    gate = ENGINE.split('summary["phase3_species_attribution"]', 1)[0]
    assert gate.rstrip().endswith(f"if {FLAG}:")
    assert "phase3_species_attribution" not in (
        ROOT / "sim/core/SimulationLogWriter.gd"
    ).read_text(encoding="utf-8")
    assert "phase3_species_attribution" not in (
        ROOT / "sim/core/SimulationStateBuilder.gd"
    ).read_text(encoding="utf-8")


def test_reset_clears_the_measurement():
    body = GAS.split("func reset(", 1)[1].split("func begin_phase3_shadow_step(", 1)[0]
    assert "_phase3_species_attribution.clear()" in body


def test_summary_export_is_a_deep_copy():
    body = GAS.split("func get_phase3_species_attribution_summary(", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    assert "duplicate(true)" in body


def test_fixture_does_not_treat_threshold_metadata_as_a_species():
    # S0d5b added this summary-level header. Godot can still exit zero after an
    # Invalid access in a fixture, so pin the explicit metadata branch here.
    assert 'if String(species) == "material_eps_kg":' in FIXTURE
    assert 'entry.has("max_clamp_deficit_kg")' in FIXTURE


def test_cli_wiring_is_complete():
    assert '"--phase3-species-attribution-diagnostics"' in RUNNER
    assert f"engine.{FLAG} = true" in RUNNER
    assert '"--phase3-species-attribution-diagnostics"' in WRAPPER
    assert "args.phase3_species_attribution_diagnostics" in WRAPPER


def test_no_official_case_enables_the_measurement():
    for path in (ROOT / "sim/validation/cases").glob("*.json"):
        assert FLAG not in path.read_text(encoding="utf-8"), path.name


def test_telemetry_never_governs_gas_physics():
    for line in GAS.splitlines():
        if re.search(r"\b(if|elif|while)\b", line) and FLAG in line:
            assert f"if not {FLAG}:" in line


def test_no_integrator_and_no_authority():
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()
    solver = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
    assert "phase3_species_attribution" not in solver
    hvac = (ROOT / "sim/core/HVACSystem.gd").read_text(encoding="utf-8")
    assert "phase3_species_attribution" not in hvac


def test_fixture_covers_every_decision_branch():
    assert "if _failed:" in FIXTURE
    block = FIXTURE.split("if _failed:", 1)[1].split(
        "PHASE3_H32S0D3_SPECIES_ATTRIBUTION_PASS", 1
    )[0]
    assert "quit(1)" in block and "return" in block
    for label in (
        "diagnostics flag defaults false",
        "accepted equals requested when the clamp is slack",
        "accepted differs from requested when the clamp bites",
        "no invented per-owner share",
        "no proportional split",
        "one high-bound clamp",
        "O2 has no zone identity",
        "is bulk only",
        "carries an upper split",
        "real step measured CO",
        "export is pure",
        "export is deterministic",
    ):
        assert label in FIXTURE, label
    assert "step_smoke(" in FIXTURE
