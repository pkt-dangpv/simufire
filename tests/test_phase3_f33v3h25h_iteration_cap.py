"""Contracts for the F3.3v3h2.5h iteration_cap capture and its mode selector.

After H2.5g, `iteration_cap` is the dominant remaining failure mode - 217 at
120 s against 11 `damping_exhausted` - and had never been captured, because the
instrumentation records only the first failure per run. H2.5h adds an opt-in
selector so a specific mode can be waited for.

The selector is instrumentation. It chooses what gets written to disk and can
never influence what the solver computes; these tests pin that.
"""
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "tests" / "fixtures" / "data"
CAPTURE = DATA / "coupled_solver_iteration_cap_corridor_chain.json"
CORRIDOR = DATA / "coupled_solver_failure_corridor_chain.json"
R0 = DATA / "coupled_solver_failure_r0_window_360.json"
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(
    encoding="utf-8"
)
HEADLESS = (ROOT / "tools" / "run_scenario_headless.gd").read_text(
    encoding="utf-8"
)
RUNNER = (ROOT / "scripts" / "run_scenario.py").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT / "tests" / "fixtures" / "phase3_f33v3h25h_iteration_cap.gd"
).read_text(encoding="utf-8")


def _decode(leaf) -> float:
    assert isinstance(leaf, dict) and "x" in leaf, leaf
    return struct.unpack("<d", bytes.fromhex(leaf["x"]))[0]


def _capture() -> dict:
    return json.loads(CAPTURE.read_text(encoding="utf-8"))


def _walk(node, path=""):
    if isinstance(node, dict):
        if "x" in node and "d" in node:
            yield path, node
            return
        for key, value in node.items():
            yield from _walk(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _walk(value, f"{path}[{index}]")


# ---------------------------------------------------------------------------
# the capture
# ---------------------------------------------------------------------------

def test_capture_exists_and_shares_the_v1_schema():
    assert CAPTURE.exists()
    data = _capture()
    assert data["schema_version"] == "simufire_coupled_solver_failure_v1"
    for other in (CORRIDOR, R0):
        assert json.loads(other.read_text(encoding="utf-8"))["schema_version"] \
            == data["schema_version"]


def test_capture_is_an_iteration_cap_and_says_it_was_requested():
    data = _capture()
    observed = data["observed_failure"]
    assert observed["converged"] is False
    assert observed["limiting_reason"] == "iteration_cap"
    assert data.get("requested_failure_mode") == "iteration_cap"
    # it sat on the cap exactly
    assert _decode(observed["iterations"]) == float(
        data["solver_defaults"]["max_iterations"]
    )


def test_every_numeric_leaf_is_bit_exact_and_readable():
    leaves = list(_walk(_capture()))
    assert leaves
    for path, leaf in leaves:
        assert len(leaf["x"]) == 16, path
        exact = _decode(leaf)
        readable = float(leaf["d"])
        assert abs(exact - readable) / max(abs(exact), 1e-300) < 1e-8, path


def test_capture_carries_every_solver_input_and_option():
    data = _capture()
    for key in ("rooms", "openings", "sources", "dt", "reference_temp_c"):
        assert key in data["input"], key
    for key in (
        "residual_tolerance", "max_iterations", "dp_regularization_pa",
        "jacobian_step_pa", "band_segments", "max_damping_halvings",
    ):
        assert key in data["solver_defaults"], key


def test_the_three_captures_record_three_different_modes():
    modes = {
        p.name: json.loads(p.read_text(encoding="utf-8"))["observed_failure"][
            "limiting_reason"
        ]
        for p in (CORRIDOR, R0, CAPTURE)
    }
    assert modes[CAPTURE.name] == "iteration_cap"
    assert modes[CORRIDOR.name] == "damping_exhausted"
    assert modes[R0.name] == "damping_exhausted"


# ---------------------------------------------------------------------------
# the anatomy - recorded so a future phase cannot "fix" this by raising the cap
# ---------------------------------------------------------------------------

def test_residual_falls_monotonically_and_far_too_slowly():
    history = [_decode(x) for x in _capture()["observed_failure"]["residual_history"]]
    assert len(history) >= 3
    assert all(history[i + 1] < history[i] for i in range(len(history) - 1))
    # cut off well outside tolerance, but most of the residual already gone
    assert history[-1] > 1e-12
    assert history[-1] / history[0] < 0.1


def test_capture_records_the_cap_it_hit():
    data = _capture()
    assert _decode(data["observed_failure"]["iterations"]) == float(
        data["solver_defaults"]["max_iterations"]
    )


def test_fixture_measures_the_cap_rather_than_arguing_about_it():
    """The corrected contract.

    An earlier draft extrapolated the first 24 iterations' linear rate and
    concluded a bigger cap was pointless. That was wrong by a factor of about
    forty: the rate does not persist, and the same input converges in 26
    iterations given room. The fixture now measures that instead of asserting
    an extrapolation, and the late-run failures need 108.
    """
    assert "_test_a_larger_budget_converges_the_same_input" in FIXTURE
    assert "_replay_with_iteration_cap" in FIXTURE
    # and it must not have become an argument for raising the shipped cap
    assert "DEFAULT_MAX_ITERATIONS" not in FIXTURE


# ---------------------------------------------------------------------------
# the selector is instrumentation, and fails loudly
# ---------------------------------------------------------------------------

def test_selector_exists_and_defaults_to_the_original_behaviour():
    assert 'var coupled_pressure_solver_capture_failure_mode: String = ""' in SYSTEM
    assert (
        '@export var phase3_coupled_pressure_solver_capture_failure_mode: String = ""'
        in ENGINE
    )
    assert "--phase3-coupled-pressure-solver-capture-mode=" in HEADLESS
    assert "--phase3-coupled-pressure-solver-capture-mode" in RUNNER


def test_unknown_mode_disables_capture_loudly():
    body = SYSTEM.split(
        "func configure_coupled_pressure_solver_capture(", 1
    )[1].split("\nfunc ", 1)[0]
    assert "push_error(" in body
    assert "Capture DISABLED." in body
    assert 'coupled_pressure_solver_capture_path = ""' in body
    # no silent degradation
    assert "push_warning(" not in body


def test_mode_filter_is_applied_before_the_latch():
    """A skipped failure must leave the capture armed.

    Latching first would record the very mode we were told to ignore and then
    refuse every later one, which is the bug this ordering exists to avoid.
    """
    body = SYSTEM.split(
        "func _capture_coupled_pressure_solver_failure(", 1
    )[1].split("\nfunc ", 1)[0]
    filter_at = body.index("coupled_pressure_solver_capture_failure_mode.is_empty()")
    latch_at = body.index("_coupled_pressure_solver_captured = true")
    assert filter_at < latch_at


def test_selector_only_accepts_real_limiting_reasons():
    modes = SYSTEM.split("CAPTURE_SELECTABLE_FAILURE_MODES: Array[String] = [", 1)[1]
    modes = modes.split("]", 1)[0]
    for mode in ("iteration_cap", "damping_exhausted"):
        assert f'"{mode}"' in modes, mode
        # every selectable mode must be a reason the solver can actually emit
        assert f'"{mode}"' in SOLVER, mode


def test_capture_records_which_mode_was_requested():
    body = SYSTEM.split(
        "func _capture_coupled_pressure_solver_failure(", 1
    )[1].split("\nfunc ", 1)[0]
    assert '"requested_failure_mode": coupled_pressure_solver_capture_failure_mode' \
        in body


def test_capture_still_writes_only_once_and_touches_no_state():
    body = SYSTEM.split(
        "func _capture_coupled_pressure_solver_failure(", 1
    )[1].split("\nfunc ", 1)[0]
    assert body.index("_coupled_pressure_solver_captured = true") \
        < body.index("FileAccess.open(")
    for forbidden in (
        "_snapshots[", "_results[", "add_atomic_bundle", "make_atomic_route",
        "network_routes", "_persistent_zone_state",
    ):
        assert forbidden not in body, forbidden


# ---------------------------------------------------------------------------
# the solver was not touched
# ---------------------------------------------------------------------------

def test_solver_was_not_modified_by_this_phase():
    # H2.5h is instrumentation only. The cap, the LM budget and the whole
    # numerical configuration must be exactly what H2.5g shipped.
    for constant, value in (
        ("DEFAULT_MAX_ITERATIONS", "24"),
        ("DEFAULT_RESIDUAL_TOLERANCE", "1.0e-12"),
        ("DEFAULT_JACOBIAN_STEP_PA", "1.0e-3"),
        ("DEFAULT_DP_REGULARIZATION_PA", "0.01"),
        ("DEFAULT_BAND_SEGMENTS", "16"),
        ("DEFAULT_MAX_DAMPING_HALVINGS", "12"),
        ("LM_RESCUE_MAX_ACCEPTED_STEPS", "1"),
    ):
        assert f"const {constant}: " in SOLVER and value in SOLVER.split(
            f"const {constant}: ", 1
        )[1].split("\n", 1)[0], constant
    # and the capture selector must not have leaked into the solver at all
    for forbidden in ("capture_failure_mode", "requested_failure_mode"):
        assert forbidden not in SOLVER, forbidden


# ---------------------------------------------------------------------------
# the fixture
# ---------------------------------------------------------------------------

def test_fixture_replays_without_a_scenario_and_asserts_the_failure():
    assert "PHASE3_F33V3H25H_ITERATION_CAP_PASS" in FIXTURE
    for absent in ("SimulationEngine", "BuildingModel", "run_scenario"):
        assert absent not in FIXTURE, absent
    assert "Phase3CoupledPressureSolver.gd" in FIXTURE
    assert 'not bool(result["converged"]),' in FIXTURE
    assert "quit(1)\n\t\treturn" in FIXTURE


def test_fixture_asserts_the_lm_recovery_is_not_involved():
    # the recovery exists only for the damping dead end; an iteration_cap must
    # never reach it, and the fixture says so
    assert 'float(result.get("rescue_attempted", 0.0)) == 0.0' in FIXTURE


def test_invalid_selector_is_reported_once_not_every_tick():
    """The engine re-applies configuration on every log tick.

    Reporting per call produced a wall of identical errors, and resetting the
    latch per call silently defeated "capture the first failure" - the artifact
    became the first failure after the LAST reconfigure. Both are fixed by
    remembering the last selector seen.
    """
    body = SYSTEM.split(
        "func configure_coupled_pressure_solver_capture(", 1
    )[1].split("\nfunc ", 1)[0]
    assert "_coupled_pressure_solver_capture_mode_seen" in body
    assert "var changed: bool = requested != _coupled_pressure_solver_capture_mode_seen" in body
    # the error and the latch reset are both gated on the value having changed
    assert body.count("if changed:") == 2
    assert 'var _coupled_pressure_solver_capture_mode_seen: String = ""' in SYSTEM


def test_python_runner_rejects_unknown_modes_before_launching_godot():
    assert "_CAPTURE_FAILURE_MODES" in RUNNER
    assert "raise SystemExit(" in RUNNER.split("_CAPTURE_FAILURE_MODES", 2)[2]
    for mode in ("iteration_cap", "damping_exhausted"):
        assert f'"{mode}"' in RUNNER, mode


def test_python_and_gdscript_mode_lists_agree():
    gd = SYSTEM.split("CAPTURE_SELECTABLE_FAILURE_MODES: Array[String] = [", 1)[1]
    gd = set(m.strip().strip('",') for m in gd.split("]", 1)[0].split(",") if m.strip())
    py_block = RUNNER.split("_CAPTURE_FAILURE_MODES = frozenset(", 1)[1]
    py_block = py_block.split(")", 1)[0]
    py = set(
        token.strip().strip('"{}\n ')
        for token in py_block.split(",")
        if token.strip().strip('"{}\n ')
    )
    assert gd == py, (gd, py)
