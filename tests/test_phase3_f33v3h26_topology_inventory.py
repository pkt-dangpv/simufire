"""Contracts for the H2.6 opening-topology inventory and capture probe.

Both are diagnostics. The inventory decides which topological classes a corpus
covers, so it has to be honest about the difference between the network a
template DECLARES and the network the solver actually SEES once a case's
`opening_overrides` have shut some doors. The probe replays a capture at a
raised iteration budget offline; it must never be mistaken for a change to the
shipped cap.
"""

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "scripts/simulation/inventory_phase3_opening_topology.py"
PROBE_PATH = ROOT / "tools/diagnostics/phase3_h26_capture_probe.gd"
SOLVER = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)
PROBE = PROBE_PATH.read_text(encoding="utf-8")
INVENTORY_SRC = INVENTORY_PATH.read_text(encoding="utf-8")


def _load_inventory():
    spec = importlib.util.spec_from_file_location(
        "h26_inventory", INVENTORY_PATH
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["h26_inventory"] = module
    spec.loader.exec_module(module)
    return module


inv = _load_inventory()


# -------------------------------------------------------------------
# static network vs effective network
# -------------------------------------------------------------------

def test_static_and_effective_are_separate_functions():
    assert hasattr(inv, "classify")
    assert hasattr(inv, "case_effective_graph")


def test_docstring_warns_that_static_is_only_an_upper_bound():
    assert "upper bound" in inv.__doc__.lower()
    assert "opening_overrides" in inv.__doc__


def test_effective_graph_applies_opening_overrides():
    """corridor_chain runs on a star template but solves a three-room chain."""
    result = inv.case_effective_graph(
        inv.CASE_DIR / "cfast_corridor_chain.json"
    )
    assert result["template"] == "simple_house"
    assert result["component_rooms"] == 3
    assert result["component_links"] == 2
    assert result["shape"] == "chain"
    assert "C3_linear_chain" in result["classes"]

    static = inv.classify(
        "simple_house", inv.load(inv.SCENARIO_DIR / "preset_simple_house.json")
    )
    # The template is a star with more rooms; the case is not.
    assert static["rooms"] > result["component_rooms"]
    assert "C4_star" in static["classes"]


def test_effective_graph_detects_components_degrees_cycles_and_exterior():
    loop = inv.case_effective_graph(
        inv.CASE_DIR / "ghanekar_bedroom_hallway.json"
    )
    assert loop["independent_cycles"] >= 1
    assert loop["shape"] == "loop"
    assert loop["exterior_open"] >= 1
    assert loop["max_degree"] >= 2
    assert "C6_interior_loop" in loop["classes"]
    assert "C9_interior_and_exterior" in loop["classes"]

    tree = inv.case_effective_graph(inv.CASE_DIR / "two_storey_smoke.json")
    assert tree["independent_cycles"] == 0
    assert tree["shape"] == "branched_tree"
    assert "C7_multi_floor" in tree["classes"]


def test_closed_openings_are_absent_from_the_effective_graph():
    """An override with open_fraction 0 must remove the edge, not keep it."""
    case = inv.load(inv.CASE_DIR / "cfast_corridor_chain.json")
    shut = [
        o for o in case["opening_overrides"]
        if float(o.get("open_fraction", 0.0)) == 0.0
    ]
    assert shut, "fixture assumption: corridor_chain shuts some doors"
    result = inv.case_effective_graph(
        inv.CASE_DIR / "cfast_corridor_chain.json"
    )
    template = inv.load(inv.SCENARIO_DIR / "preset_simple_house.json")
    assert result["component_links"] < len(
        inv.interior_edges(template["openings_data"])
    )


# -------------------------------------------------------------------
# read-only and deterministic
# -------------------------------------------------------------------

def test_inventory_writes_nothing_unless_asked():
    writes = re.findall(r"\.write_text\(|open\([^)]*['\"]w", INVENTORY_SRC)
    # Every write must be guarded by the explicit --json-out argument.
    for match in re.finditer(r"args\.json_out\.write_text\(", INVENTORY_SRC):
        assert match  # present
    assert len(writes) == INVENTORY_SRC.count("args.json_out.write_text(")


def test_inventory_reads_only_committed_locations():
    assert "sim/validation/cases" in INVENTORY_SRC
    assert "scenarios" in INVENTORY_SRC
    # No scratch or run directories: H2.5l-A was measured on mutable scratch
    # cases and had to be withdrawn. This must not repeat.
    assert "scratch" not in INVENTORY_SRC.lower()
    assert 'Path("runs' not in INVENTORY_SRC


def test_inventory_is_deterministic(tmp_path):
    first, second = tmp_path / "a.json", tmp_path / "b.json"
    for out in (first, second):
        subprocess.run(
            [sys.executable, str(INVENTORY_PATH), "--json-out", str(out)],
            check=True, capture_output=True, cwd=ROOT,
        )
    assert first.read_bytes() == second.read_bytes()


def test_case_mode_is_deterministic(tmp_path):
    cases = ["cfast_corridor_chain", "uk_bungalow_smoke", "two_storey_smoke"]
    first, second = tmp_path / "a.json", tmp_path / "b.json"
    for out in (first, second):
        subprocess.run(
            [sys.executable, str(INVENTORY_PATH), "--cases", *cases,
             "--json-out", str(out)],
            check=True, capture_output=True, cwd=ROOT,
        )
    assert first.read_bytes() == second.read_bytes()


# -------------------------------------------------------------------
# class taxonomy
# -------------------------------------------------------------------

def test_all_fourteen_classes_are_declared():
    keys = set(inv.STATIC_CLASSES) | set(inv.RUNTIME_CLASSES)
    assert len(keys) == 14
    for index in range(1, 15):
        assert any(k.startswith(f"C{index}_") for k in keys), index


def test_runtime_only_classes_are_not_claimed_from_geometry():
    """C11-C14 depend on a particular solve, not on the network."""
    for key in inv.RUNTIME_CLASSES:
        assert key not in inv.STATIC_CLASSES
    static = inv.classify(
        "simple_house", inv.load(inv.SCENARIO_DIR / "preset_simple_house.json")
    )
    for key in inv.RUNTIME_CLASSES:
        assert key not in static["classes"]


def test_parallel_openings_class_has_no_template_and_is_reported_missing():
    """C8 is genuinely absent from the corpus; the inventory must say so."""
    rows = [
        inv.classify(path.stem.replace("preset_", ""), inv.load(path))
        for path in sorted(inv.SCENARIO_DIR.glob("preset_*.json"))
    ]
    union = set()
    for row in rows:
        union |= set(row["classes"])
    assert "C8_parallel_openings" not in union
    assert all(row["parallel_extra"] == 0 for row in rows)


# -------------------------------------------------------------------
# capture probe
# -------------------------------------------------------------------

def test_probe_is_diagnostic_only_and_touches_no_state():
    assert "extends SceneTree" in PROBE
    assert "Phase3CoupledPressureSolver.gd" in PROBE
    # Reads captures; writes nothing at all.
    assert "FileAccess.WRITE" not in PROBE
    assert "SimulationEngine" not in PROBE
    assert "BuildingModel" not in PROBE


def test_probe_raises_the_budget_per_call_and_never_the_shipped_default():
    """The raised cap is an `options` override on one offline replay."""
    assert '"max_iterations": cap' in PROBE
    assert "DEFAULT_MAX_ITERATIONS" not in PROBE
    # The shipped constant is untouched.
    assert re.search(r"const DEFAULT_MAX_ITERATIONS: int = 24\b", SOLVER)


def test_probe_is_fail_closed():
    assert "capture path required" in PROBE
    assert PROBE.count("quit(1)") >= 2
    assert "capture missing: " in PROBE
    # The success token must come after every early exit.
    assert PROBE.index("quit(1)") < PROBE.index("H26_CAPTURE_PROBE_PASS")


def test_probe_reports_the_evidence_the_verdict_rests_on():
    """The multi-floor finding is 'converges at a raised cap', so the probe
    must report convergence, iterations and the cycle/half-step counters."""
    for field in (
        "converged", "iters", "analytic_half_step_attempt_total",
        "analytic_half_step_accept_total", "cycle_detect_total",
    ):
        assert field in PROBE, field
    assert "for cap in [24, raised]" in PROBE
