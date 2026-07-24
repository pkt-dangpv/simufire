"""Structural contract for the temporary F3.3n flogo runtime experiment."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")

FLAG = "phase3_cfast_buoyancy_destination_shadow_enabled"
CLI = "--phase3-cfast-buoyancy-destination-shadow"


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_candidate_defaults_off_and_is_reported_in_state_context():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    assert f'"{FLAG}"' in ENGINE


def test_engine_changes_only_destination_selector_argument():
    body = _function(ENGINE, "step")
    call = body.split(
        "queue_canonical_interior_opening_requests(", 1
    )[1][:700]
    assert "EXTERIOR_DISCHARGE_COEFF" in call
    assert "phase3_canonical_interior_pressure_shadow_enabled" in call
    assert call.count("false") == 2
    assert FLAG in call


def test_candidate_uses_existing_exact_flogo_path():
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    interval = _function(SYSTEM, "_canonical_interior_interval_flow")
    assert "buoyancy_destination_enabled: bool = false" in queue
    assert "buoyancy_destination_enabled" in interval
    assert "preview_cfast_buoyancy_destination_split(" in interval


def test_cli_implies_full_ledger_stack():
    assert CLI in RUNNER
    block = RUNNER.split(
        "if args.phase3_cfast_buoyancy_destination_shadow:", 1
    )[1]
    for parent in (
        "--phase3-canonical-interior-opening-shadow",
        "--phase3-canonical-interior-pressure-shadow",
        "--phase3-enthalpy-residence-diagnostics",
        "--phase3-mass-residence-diagnostics",
        "--phase3-connection-residence-diagnostics",
    ):
        assert parent in block


def test_headless_parser_and_engine_wiring_are_present():
    assert CLI in HEADLESS
    assert f"engine.{FLAG} = true" in HEADLESS
    assert 'parsed["phase3_cfast_buoyancy_destination_shadow"] = true' in HEADLESS


def test_candidate_does_not_enable_poreh_bundle():
    body = _function(ENGINE, "step")
    call = body.split(
        "queue_canonical_interior_opening_requests(", 1
    )[1][:700]
    # source-preserving and doorway-jet/Poreh parameters remain false.
    assert call.count("false") == 2
