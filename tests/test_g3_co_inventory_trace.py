"""G3 inventory observations are opt-in and leave scenario defaults unchanged."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "scripts/run_scenario.py"
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
SPEC = importlib.util.spec_from_file_location("simufire_g3_run_scenario", RUNNER_PATH)
assert SPEC and SPEC.loader
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def test_inventory_trace_and_fire_o2_override_are_opt_in():
    args = RUNNER._parse_args(["scenario.json"])
    assert args.co_inventory_trace is False
    assert args.fire_o2_mode is None
    explicit = RUNNER._parse_args([
        "scenario.json", "--co-inventory-trace", "--fire-o2-mode", "upper"
    ])
    assert explicit.co_inventory_trace is True
    assert explicit.fire_o2_mode == "upper"


def test_headless_runner_samples_only_when_requested():
    assert 'if not bool(_cli_args.get("co_inventory_trace", false)):' in HEADLESS
    assert 'elif arg == "--co-inventory-trace":' in HEADLESS
    assert 'elif arg.begins_with("--fire-o2-mode="):' in HEADLESS
    assert 'if _cli_args.has("fire_o2_mode"):' in HEADLESS
    assert '"co_lower_mass_ppm": thermal.compute_co_lower_ppm_mass(room)' in HEADLESS
    assert '"co_lower_legacy_ppm": thermal.compute_co_lower_ppm(room)' in HEADLESS
    assert '"co_upper_raw_kg": room.co_upper_kg' in HEADLESS
    assert '"lower_gas_kg": room.lower_gas_kg' in HEADLESS
