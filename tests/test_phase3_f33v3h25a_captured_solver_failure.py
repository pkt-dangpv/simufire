"""Contracts for the captured coupled-solver failure.

F3.3v3h2.5 could not diagnose the 13.6% non-convergence from reconstructed
states: 528 synthetic cases converged 100% of the time. This capture exists so
the real failure can be replayed deterministically, without running a scenario.
"""
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CAPTURE = (
    ROOT / "tests" / "fixtures" / "data"
    / "coupled_solver_failure_corridor_chain.json"
)
FIXTURE = (
    ROOT / "tests" / "fixtures"
    / "phase3_f33v3h25a_captured_solver_failure.gd"
).read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(
    encoding="utf-8"
)
HEADLESS = (ROOT / "tools" / "run_scenario_headless.gd").read_text(
    encoding="utf-8"
)
SOLVER = (ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)


def _decode(leaf) -> float:
    assert isinstance(leaf, dict) and "x" in leaf, leaf
    return struct.unpack("<d", bytes.fromhex(leaf["x"]))[0]


def _capture() -> dict:
    return json.loads(CAPTURE.read_text(encoding="utf-8"))


def _walk_leaves(node, path=""):
    if isinstance(node, dict):
        if "x" in node and "d" in node:
            yield path, node
            return
        for key, value in node.items():
            yield from _walk_leaves(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _walk_leaves(value, f"{path}[{index}]")


def test_capture_exists_and_is_versioned():
    assert CAPTURE.exists(), "capture must be committed as test data"
    assert CAPTURE.stat().st_size > 0
    data = _capture()
    assert data["schema_version"] == "simufire_coupled_solver_failure_v1"


def test_capture_records_a_real_non_converged_solve():
    observed = _capture()["observed_failure"]
    assert observed["converged"] is False
    assert observed["limiting_reason"] in (
        "iteration_cap",
        "damping_exhausted",
        "singular_jacobian",
    ), observed["limiting_reason"]
    assert _decode(observed["failure_code"]) > 0.0
    assert _decode(observed["iterations"]) >= 1.0


def test_capture_carries_every_solver_input():
    data = _capture()["input"]
    for key in ("rooms", "openings", "sources", "dt", "reference_temp_c"):
        assert key in data, key
    assert _decode(data["dt"]) > 0.0
    assert len(data["rooms"]) >= 2
    assert len(data["openings"]) >= 1
    for room in data["rooms"].values():
        for field in (
            "volume_m3", "floor_area_m2", "height_m",
            "upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
        ):
            assert field in room, field
    for source in data["sources"].values():
        assert "mass_kg" in source and "energy_kj" in source


def test_every_numeric_leaf_is_bit_exact_and_readable():
    """The readable decimal is for humans; the hex is what the replay uses.

    Godot's `String.num_scientific` only round-trips about nine significant
    digits, which measurably perturbed the replay before the hex field existed.
    """
    leaves = list(_walk_leaves(_capture()))
    assert leaves, "no encoded numeric leaves found"
    for path, leaf in leaves:
        assert len(leaf["x"]) == 16, f"{path}: not an 8-byte double"
        exact = _decode(leaf)
        readable = float(leaf["d"])
        # the readable form must at least agree to its own precision
        scale = max(abs(exact), 1e-300)
        assert abs(exact - readable) / scale < 1e-8, path


def test_capture_is_reachable_only_through_an_opt_in_path():
    # empty by default, so an unconfigured run never writes a capture
    assert 'var coupled_pressure_solver_capture_path: String = ""' in SYSTEM
    assert (
        '@export var phase3_coupled_pressure_solver_capture_path: String = ""'
        in ENGINE
    )
    assert "--phase3-coupled-pressure-solver-capture=" in HEADLESS
    body = SYSTEM.split(
        "func _capture_coupled_pressure_solver_failure(", 1
    )[1].split("\nfunc ", 1)[0]
    assert "if coupled_pressure_solver_capture_path.is_empty()" in body
    assert "_coupled_pressure_solver_captured = true" in body


def test_capture_writes_only_the_first_failure():
    body = SYSTEM.split(
        "func _capture_coupled_pressure_solver_failure(", 1
    )[1].split("\nfunc ", 1)[0]
    # the guard sets the latch before doing any work, so a second failure is a
    # no-op even if serialisation is slow or fails
    latch = body.index("_coupled_pressure_solver_captured = true")
    write = body.index("FileAccess.open(")
    assert latch < write


def test_capture_does_not_touch_simulation_state():
    body = SYSTEM.split(
        "func _capture_coupled_pressure_solver_failure(", 1
    )[1].split("\nfunc ", 1)[0]
    for forbidden in (
        "_snapshots[", "_results[", "shadow[", "add_atomic_bundle",
        "make_atomic_route", "network_routes", "_persistent_zone_state",
    ):
        assert forbidden not in body, forbidden


def test_solver_is_unchanged_from_h2():
    # H2.5a captures; it does not attempt a fix. The primitive must be
    # untouched so the replay characterises the shipped solver.
    assert "flux_regularization_mode" not in SOLVER
    assert "jacobian_step_mode" not in SOLVER
    assert "seed_pressure_by_room" not in SOLVER


def test_fixture_replays_without_running_a_scenario():
    assert "PHASE3_F33V3H25A_CAPTURED_SOLVER_FAILURE_PASS" in FIXTURE
    for absent in ("SimulationEngine", "BuildingModel", "run_scenario"):
        assert absent not in FIXTURE, absent
    assert "Phase3CoupledPressureSolver.gd" in FIXTURE
    for test_name in (
        "_test_capture_is_well_formed",
        "_test_replay_reproduces_the_recorded_failure",
        "_test_replay_is_deterministic",
        "_test_capture_round_trips_full_precision",
    ):
        assert test_name in FIXTURE, test_name


def test_fixture_asserts_the_failure_still_reproduces():
    # if a future phase fixes convergence this must fail loudly, not pass
    assert 'not bool(result["converged"]),' in FIXTURE
    assert "quit(1)\n\t\treturn" in FIXTURE
