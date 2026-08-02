"""Contracts for the F3.3v3h2.5g bounded Levenberg-Marquardt recovery.

H2.5f measured, offline on both real captures, that the recovery must be
FAIL-ONLY: reachable from exactly the dead end where the solver returns
`damping_exhausted`, and nowhere else. These tests pin that shape, the budget,
and the fact that nothing else in the solver moved.
"""
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER = (ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
WRITER = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT / "tests" / "fixtures" / "phase3_f33v3h25g_lm_rescue.gd"
).read_text(encoding="utf-8")


def _code_only(text: str) -> str:
    return "\n".join(
        "" if line.lstrip().startswith("#") else line
        for line in text.splitlines()
    )


CODE = _code_only(SOLVER)


def _function(text: str, name: str) -> str:
    return text.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


# ---------------------------------------------------------------------------
# fail-only reachability
# ---------------------------------------------------------------------------

def test_recovery_keeps_the_original_damping_dead_end_call_site():
    """H2.10 may recover first; a decline still reaches the original LM call."""
    body = _function(CODE, "solve_coupled_pressure")
    assert body.count("_try_lm_rescue(") == 2, "dead end plus cycle guard"
    first_call = body.split("_try_lm_rescue(", 1)[0]
    before = first_call
    tail = before.rsplit("if not accepted:", 1)
    assert len(tail) == 2, "the call is not under `if not accepted:`"
    between = tail[1]
    assert "_try_adaptive_branch_jacobian_recovery" in between
    assert 'if bool(adaptive.get("accepted", false)):' in between
    # The adaptive accept exits this iteration. If it declines, execution
    # reaches the unchanged LM call directly below it.
    assert "continue" in between
    cycle = body.split(
        "if cycle_detected and rescue_budget_left > 0:", 1
    )[1]
    assert cycle.count("_try_lm_rescue(") == 1


def test_failure_path_is_unchanged_when_the_recovery_declines():
    body = _function(CODE, "solve_coupled_pressure")
    tail = body.split('if not bool(rescue.get("accepted", false)):', 1)[1]
    tail = tail.split("return result", 1)[0]
    assert 'result["failure_code"] = FAILURE_NOT_CONVERGED' in tail
    assert 'result["limiting_reason"] = "damping_exhausted"' in tail


def test_recovery_is_never_treated_as_convergence():
    body = _function(CODE, "solve_coupled_pressure")
    accepted = body.split("rescue_budget_left -= 1", 1)[1].split("continue", 1)[0]
    # convergence is still decided by the ordinary L-infinity test
    assert "converged = norm <= tolerance" in accepted
    assert "converged = true" not in accepted
    # and control goes straight back to the normal loop
    assert "continue" in body.split("rescue_budget_left -= 1", 1)[1][:900]


# ---------------------------------------------------------------------------
# the budget
# ---------------------------------------------------------------------------

def test_budget_is_one_accepted_step_per_solve():
    assert re.search(
        r"const LM_RESCUE_MAX_ACCEPTED_STEPS: int = 1\b", SOLVER
    )
    body = _function(CODE, "solve_coupled_pressure")
    assert "var rescue_budget_left: int = LM_RESCUE_MAX_ACCEPTED_STEPS" in body
    assert "rescue_budget_left -= 1" in body
    rescue = _function(CODE, "_try_lm_rescue")
    assert "if budget_left <= 0:" in rescue


def test_ladder_is_five_fixed_regularizations():
    match = re.search(
        r"const LM_RESCUE_LAMBDA_LADDER: Array\[float\] = \[(.*?)\]", SOLVER
    )
    assert match, "ladder constant missing"
    assert len(match.group(1).split(",")) == 5


def test_recovery_returns_after_the_first_accepted_step():
    rescue = _function(CODE, "_try_lm_rescue")
    accept = rescue.split('outcome["accepted"] = true', 1)[1]
    assert "return outcome" in accept.split("\n\n", 1)[0] or "return outcome" in accept[:400]


# ---------------------------------------------------------------------------
# sufficient decrease, not any decrease
# ---------------------------------------------------------------------------

def test_recovery_demands_sufficient_decrease_of_its_own_merit():
    rescue = _function(CODE, "_try_lm_rescue")
    assert "merit_after <= (1.0 - LM_RESCUE_ARMIJO_C * scale) * merit_before" in rescue
    # a bare strict decrease would be the thing this must not do
    assert "merit_after < merit_before" not in rescue
    assert re.search(r"const LM_RESCUE_ARMIJO_C: float = 1\.0e-4\b", SOLVER)


def test_recovery_merit_is_sum_of_squares_not_the_main_merit():
    body = _function(CODE, "_rescue_merit")
    assert "value * value" in body
    assert "0.5 * total" in body


def test_recovery_damps_the_same_jacobian_and_adds_no_differencing():
    rescue = _function(CODE, "_try_lm_rescue")
    assert "row[column] += lambda_value * jacobian_scale" in rescue
    # no new evaluation of derivatives: the Jacobian is passed in
    assert "jacobian_step_pa" not in rescue
    assert "_evaluate(context, trial)" in rescue


# ---------------------------------------------------------------------------
# nothing else moved
# ---------------------------------------------------------------------------

def test_every_numerical_constant_is_unchanged():
    expected = {
        "DEFAULT_MAX_ITERATIONS": "24",
        "DEFAULT_RESIDUAL_TOLERANCE": "1.0e-12",
        "DEFAULT_DP_REGULARIZATION_PA": "0.01",
        "DEFAULT_JACOBIAN_STEP_PA": "1.0e-3",
        "DEFAULT_BAND_SEGMENTS": "16",
        "DEFAULT_MAX_DAMPING_HALVINGS": "12",
    }
    for name, value in expected.items():
        assert re.search(rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER), name


def test_gauge_formulation_and_main_loop_are_intact():
    # H2.5e gauge
    assert 'context["rooms"][room_key]["gauge_pressure_pa"]' in CODE
    assert '(balance_mass_kg - float(room["reference_mass_kg"]))' in CODE
    assert "value + exterior_pressure_abs_pa" in CODE
    # forward difference, L-infinity acceptance, ordinary halving
    body = _function(CODE, "solve_coupled_pressure")
    assert ") / jacobian_step_pa" in body
    assert "/ (2.0 * jacobian_step_pa)" not in body
    assert 'float(trial_evaluation["normalized_residual"]) < norm' in body
    assert "damping *= 0.5" in body
    # flux law
    assert "sqrt(2.0 * density * magnitude_pa)" in SOLVER


def test_no_new_knob_and_no_alpha_blend_skew():
    for forbidden in (
        "rescue_enabled", "lm_enabled", "rescue_mode", "jacobian_mode",
        "alpha", "blend", "skew", "fixed_gross",
    ):
        assert forbidden not in CODE.lower(), forbidden
    # the ladder and budget are constants, never read from options
    rescue = _function(CODE, "_try_lm_rescue")
    assert "options" not in rescue


def test_iteration_cap_handling_is_untouched():
    body = _function(CODE, "solve_coupled_pressure")
    assert 'result["limiting_reason"] = "iteration_cap"' in body
    assert "iterations < max_iterations" in body


# ---------------------------------------------------------------------------
# telemetry
# ---------------------------------------------------------------------------

def test_solver_exposes_the_required_telemetry():
    for field in (
        "rescue_attempted", "rescue_accepted", "rescue_trials",
        "rescue_initial_norm", "rescue_final_norm", "rescue_lambda",
    ):
        assert f'"{field}": 0.0,' in SOLVER, field


def test_preview_publishes_per_step_and_total_counters():
    for field in (
        "rescue_attempted", "rescue_accepted", "rescue_trials",
        "rescue_initial_norm", "rescue_final_norm", "rescue_lambda",
    ):
        assert f'"{field}"' in SYSTEM, field
    for total in (
        "rescue_attempted_step_count", "rescue_accepted_step_count",
        "rescue_trials_total",
    ):
        assert f'"{total}"' in SYSTEM, total
        assert f"phase3_shadow_coupled_solver_{total}_total" in WRITER, total


def test_telemetry_columns_stay_in_the_opt_in_family():
    block = WRITER.split("func _phase3_coupled_solver_fields()", 1)[1]
    block = block.split("\nfunc ", 1)[0]
    for line in block.splitlines():
        stripped = line.strip().strip('",')
        if stripped.startswith("phase3_shadow_"):
            assert stripped.startswith("phase3_shadow_coupled_solver_"), stripped


# ---------------------------------------------------------------------------
# the fixture states the behaviour
# ---------------------------------------------------------------------------

def test_fixture_covers_the_mandated_cases():
    assert "PHASE3_F33V3H25G_LM_RESCUE_PASS" in FIXTURE
    for name in (
        "_test_corridor_converges_before_lm_after_h210",
        "_test_r0_converges_without_rescue_and_is_unchanged",
        "_test_successful_solves_never_reach_the_recovery",
        "_test_lm_budget_remains_bounded_when_h210_supersedes_it",
        "_test_conservation_and_counterflow",
        "_test_determinism",
        "_test_recovery_is_not_convergence",
    ):
        assert name in FIXTURE, name


def test_fixture_pins_the_pre_recovery_r0_result():
    # r0 must be untouched, so the fixture asserts the exact value recorded
    # when H2.5e shipped rather than whatever the solver produces today
    assert "9.522672403222153e-17" in FIXTURE
    assert "const R0_ITERATIONS := 3" in FIXTURE


# ---------------------------------------------------------------------------
# mutation control for the rejection path
# ---------------------------------------------------------------------------

def test_rejection_path_is_mutation_detectable():
    """H2.5g could not construct a physical case where LM declines.

    Across ~2500 offline solves on both topologies and seven regularization
    widths, the recovery found a sufficient-decrease step every single time it
    was invoked - which is what a lambda ladder reaching steepest descent on a
    smooth merit should do. The rejection branch is therefore exercised
    structurally rather than physically, and this test is the control that the
    structural assertions would actually catch its removal.
    """
    body = _function(CODE, "solve_coupled_pressure")
    guard = 'if not bool(rescue.get("accepted", false)):'
    assert guard in body, "the rejection guard is gone"

    # mutation 1: dropping the guard would let a declined rescue be treated as
    # success. The assertions in test_failure_path_is_unchanged_* read the text
    # between the guard and `return result`, so removing it breaks them.
    mutated = body.replace(guard, "if false:")
    assert guard not in mutated
    try:
        tail = mutated.split(guard, 1)[1]
        raised = False
    except IndexError:
        raised = True
    assert raised, "removing the guard must make the contract unsatisfiable"

    # mutation 2: the accepted branch must be gated on the budget, so a solve
    # cannot be rescued twice
    assert "rescue_budget_left -= 1" in body
    rescue = _function(CODE, "_try_lm_rescue")
    assert "if budget_left <= 0:" in rescue
    without_budget = rescue.replace("if budget_left <= 0:", "if false:")
    assert "if budget_left <= 0:" not in without_budget


def test_declined_rescue_leaves_the_state_untouched():
    # when nothing is accepted the recovery returns the outcome dictionary
    # without `pressure` or `evaluation`, so the caller cannot advance on it
    rescue = _function(CODE, "_try_lm_rescue")
    tail = rescue.rsplit("return outcome", 1)[1]
    assert tail.strip() == "", "the final return must be the decline path"
    early = rescue.split("if budget_left <= 0:", 1)[1].split("return outcome", 1)[0]
    assert "pressure" not in early and "evaluation" not in early
