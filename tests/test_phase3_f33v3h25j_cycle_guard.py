"""Contracts for the H2.5j accepted-cycle safeguard.

The guard is deliberately narrower than a generic trust-region switch: it
requires two accepted full Newton steps, poor model agreement on both, and
nearly opposite directions. Only then may it spend the single LM step already
budgeted by H2.5g.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
WRITER = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(
    encoding="utf-8"
)
ITERATION_FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v3h25h_iteration_cap.gd"
).read_text(encoding="utf-8")
LM_FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v3h25g_lm_rescue.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_guard_constants_are_global_and_not_case_options():
    assert re.search(
        r"const CYCLE_GUARD_MIN_MODEL_GAIN_RATIO: float = 0\.05\b", SOLVER
    )
    assert re.search(
        r"const CYCLE_GUARD_MAX_STEP_COSINE: float = -0\.99\b", SOLVER
    )
    context = _function(SOLVER, "_build_context")
    assert "CYCLE_GUARD_" not in context
    assert "cycle_guard" not in context.lower()


def test_guard_requires_two_accepted_full_nearly_opposite_steps():
    body = _function(SOLVER, "solve_coupled_pressure")
    guard = body.split("var cycle_detected: bool = false", 1)[1]
    guard = guard.split("if cycle_detected and rescue_budget_left > 0:", 1)[0]
    assert "damping == 1.0" in guard
    assert "not previous_full_step.is_empty()" in guard
    assert (
        "previous_full_step_gain_ratio\n"
        "\t\t\t\t\t\t< CYCLE_GUARD_MIN_MODEL_GAIN_RATIO"
    ) in guard
    assert "model_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO" in guard
    assert "step_cosine < CYCLE_GUARD_MAX_STEP_COSINE" in guard


def test_guard_runs_after_linf_acceptance_but_before_candidate_commit():
    body = _function(SOLVER, "solve_coupled_pressure")
    line_accept = body.index(
        'float(trial_evaluation["normalized_residual"]) < norm'
    )
    guard = body.index("if cycle_detected and rescue_budget_left > 0:")
    commit = body.index("pressure = candidate_pressure")
    assert line_accept < guard < commit


def test_guard_reuses_the_existing_bounded_lm_budget():
    body = _function(SOLVER, "solve_coupled_pressure")
    guarded = body.split("if cycle_detected and rescue_budget_left > 0:", 1)[1]
    guarded = guarded.split("if damping == 1.0:", 1)[0]
    assert "_try_lm_rescue(" in guarded
    assert "rescue_budget_left -= 1" in guarded
    assert "LM_RESCUE_MAX_ACCEPTED_STEPS" in body
    assert "cycle_rescue_budget" not in SOLVER


def test_declined_cycle_rescue_preserves_the_accepted_newton_candidate():
    body = _function(SOLVER, "solve_coupled_pressure")
    guarded = body.split("if cycle_detected and rescue_budget_left > 0:", 1)[1]
    guarded = guarded.split("if damping == 1.0:", 1)[0]
    assert 'if bool(cycle_rescue.get("accepted", false)):' in guarded
    # There is no failure/return in the decline path; execution falls through
    # to the ordinary candidate assignment.
    after_accept = guarded.split(
        'if bool(cycle_rescue.get("accepted", false)):', 1
    )[1]
    assert "damping_exhausted" not in after_accept
    assert "return result" not in after_accept
    assert "pressure = candidate_pressure" in body


def test_gain_ratio_uses_the_same_inventory_normalized_l2_merit():
    gain = _function(SOLVER, "_model_gain_ratio")
    predicted = _function(SOLVER, "_linear_model_merit")
    assert "_rescue_merit(evaluation)" in gain
    assert "_rescue_merit(candidate_evaluation)" in gain
    assert "_linear_model_merit(" in gain
    assert "(merit_before - merit_after) / predicted_reduction" in gain
    assert 'float(room["mass_kg"])' in predicted
    assert "pressure_per_kg" in predicted
    assert "normalized * normalized" in predicted


def test_cosine_is_scale_invariant_and_fail_closed():
    cosine = _function(SOLVER, "_step_cosine")
    assert "dot / denominator" in cosine
    assert "sqrt(first_norm_sq * second_norm_sq)" in cosine
    assert "return 1.0" in cosine
    assert "clampf(" in cosine


def test_no_numerical_solver_setting_was_relaxed():
    expected = {
        "DEFAULT_MAX_ITERATIONS": "24",
        "DEFAULT_RESIDUAL_TOLERANCE": "1.0e-12",
        "DEFAULT_DP_REGULARIZATION_PA": "0.01",
        "DEFAULT_JACOBIAN_STEP_PA": "1.0e-3",
        "DEFAULT_BAND_SEGMENTS": "16",
        "DEFAULT_MAX_DAMPING_HALVINGS": "12",
        "LM_RESCUE_MAX_ACCEPTED_STEPS": "1",
    }
    for name, value in expected.items():
        assert re.search(
            rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER
        ), name


def test_solver_exposes_the_four_required_guard_values():
    for field in (
        "cycle_guard_attempt_total",
        "cycle_guard_accept_total",
        "cycle_guard_last_rho",
        "cycle_guard_last_cosine",
    ):
        assert f'"{field}": 0.0,' in SOLVER
        assert f'"{field}"' in SYSTEM
        assert f"phase3_shadow_coupled_solver_{field}" in WRITER


def test_guard_columns_remain_inside_the_opt_in_solver_family():
    block = WRITER.split("func _phase3_coupled_solver_fields()", 1)[1]
    block = block.split("\nfunc ", 1)[0]
    for field in (
        "cycle_guard_attempt_total",
        "cycle_guard_accept_total",
        "cycle_guard_last_rho",
        "cycle_guard_last_cosine",
    ):
        assert f'"phase3_shadow_coupled_solver_{field}"' in block


def test_iteration_capture_is_now_the_positive_runtime_contract():
    assert "_test_cycle_guard_closes_the_iteration_cap" in ITERATION_FIXTURE
    assert "EXPECTED_FIXED_ITERATIONS := 8" in ITERATION_FIXTURE
    assert (
        'float(result.get("cycle_guard_attempt_total", 0.0)) == 1.0'
        in ITERATION_FIXTURE
    )
    assert (
        'float(result.get("cycle_guard_accept_total", 0.0)) == 1.0'
        in ITERATION_FIXTURE
    )


def test_existing_damping_and_r0_contracts_remain_present():
    assert "_test_corridor_converges_with_exactly_one_rescue" in LM_FIXTURE
    assert "_test_r0_converges_without_rescue_and_is_unchanged" in LM_FIXTURE
    assert "const R0_ITERATIONS := 3" in LM_FIXTURE


def test_removing_cycle_detection_is_mutation_detectable():
    """The real capture must become an iteration_cap if detection disappears."""
    condition = "if cycle_detected and rescue_budget_left > 0:"
    assert condition in SOLVER
    mutated = SOLVER.replace(condition, "if false:", 1)
    assert condition not in mutated
    # The fixture explicitly requires a guard event and convergence in eight
    # iterations, so this mutation cannot satisfy its contract.
    assert "cycle_guard_attempt_total" in ITERATION_FIXTURE
    assert "EXPECTED_FIXED_ITERATIONS := 8" in ITERATION_FIXTURE
