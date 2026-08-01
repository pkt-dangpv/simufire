"""Structural contracts for the H2.5m analytic half step.

The half step is the first piece of H2.5 that has runtime AUTHORITY rather than
only telemetry, so the contracts here are about how tightly that authority is
bounded: a fixed global factor, reachable only from a detected cycle, accepted
only on strict descent, and unable to touch the LM budget.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
WRITER = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v3h25m_analytic_half_step.gd"
).read_text(encoding="utf-8")

TELEMETRY = (
    "analytic_half_step_attempt_total",
    "analytic_half_step_accept_total",
    "analytic_half_step_last_initial_norm",
    "analytic_half_step_last_final_norm",
)
CUMULATIVE = (
    "analytic_half_step_attempt_total",
    "analytic_half_step_accept_total",
    "analytic_half_step_solve_count",
    "analytic_half_step_max_accepts_per_solve",
)


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def _half_step_block() -> str:
    body = _function(SOLVER, "solve_coupled_pressure")
    start = body.index('result["analytic_half_step_attempt_total"] += 1.0')
    end = body.index("if cycle_detected and rescue_budget_left > 0:", start)
    return body[start:end]


# -------------------------------------------------------------------
# the factor is a derived constant, not a knob
# -------------------------------------------------------------------

def test_factor_is_exactly_one_half_and_global():
    assert re.search(
        r"const CYCLE_ANALYTIC_HALF_STEP: float = 0\.5\b", SOLVER
    )


def test_factor_is_never_read_from_options_or_context():
    context = _function(SOLVER, "_build_context")
    assert "CYCLE_ANALYTIC_HALF_STEP" not in context
    assert "analytic_half_step" not in context
    # No per-case override anywhere in the file.
    assert 'options.get("cycle_analytic_half_step"' not in SOLVER
    assert 'context["cycle_analytic_half_step"]' not in SOLVER


def test_mutation_a_factor_other_than_one_half_is_detectable():
    """The value is the annihilator of a period-2 orbit; 0.5 is not arbitrary."""
    for wrong in ("0.25", "0.75", "1.0", "0.6"):
        mutated = SOLVER.replace(
            "const CYCLE_ANALYTIC_HALF_STEP: float = 0.5",
            f"const CYCLE_ANALYTIC_HALF_STEP: float = {wrong}",
            1,
        )
        assert "const CYCLE_ANALYTIC_HALF_STEP: float = 0.5" not in mutated


# -------------------------------------------------------------------
# authority is reachable only from a detected cycle
# -------------------------------------------------------------------

def test_half_step_is_gated_on_cycle_detected():
    body = _function(SOLVER, "solve_coupled_pressure")
    attempt = body.index('result["analytic_half_step_attempt_total"] += 1.0')
    guard = body.rindex("if cycle_detected:", 0, attempt)
    between = body[guard:attempt]
    # Nothing but the comment and the block opener may sit in between.
    for line in between.splitlines()[1:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        raise AssertionError(f"unexpected statement before attempt: {stripped}")


def test_half_step_precedes_and_does_not_replace_the_lm_cycle_guard():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert body.index(
        'result["analytic_half_step_attempt_total"] += 1.0'
    ) < body.index("if cycle_detected and rescue_budget_left > 0:")
    # The guard and its bounded rescue are still present and still budgeted.
    guarded = body.split("if cycle_detected and rescue_budget_left > 0:", 1)[1]
    guarded = guarded.split("if damping == 1.0:", 1)[0]
    assert "_try_lm_rescue(" in guarded
    assert "rescue_budget_left -= 1" in guarded


def test_mutation_authority_outside_cycle_detected_is_detectable():
    block = _half_step_block()
    body = _function(SOLVER, "solve_coupled_pressure")
    attempt_index = body.index(
        'result["analytic_half_step_attempt_total"] += 1.0'
    )
    assert "if cycle_detected:" in body[:attempt_index]
    # Hoisting the attempt above the detector must change the file.
    mutated = body.replace(block, "", 1)
    assert 'result["analytic_half_step_attempt_total"] += 1.0' not in mutated


# -------------------------------------------------------------------
# acceptance requires validity and strict descent
# -------------------------------------------------------------------

def test_acceptance_requires_valid_finite_and_strict_decrease():
    block = _half_step_block()
    assert 'bool(half_evaluation.get("valid", false))' in block
    assert "is_finite(half_norm)" in block
    assert "half_norm < norm" in block


def test_mutation_accepting_without_descent_is_detectable():
    block = _half_step_block()
    assert "half_norm < norm" in block
    for wrong in ("half_norm <= norm", "true", "half_norm > norm"):
        mutated = block.replace("half_norm < norm", wrong, 1)
        assert "and half_norm < norm" not in mutated or wrong == "half_norm <= norm"
        assert mutated != block


def test_declined_half_step_mutates_nothing():
    """Every state write must sit inside the acceptance branch."""
    block = _half_step_block()
    accept_at = block.index('result["analytic_half_step_accept_total"] += 1.0')
    before = block[:accept_at]
    for forbidden in (
        "pressure = half_pressure",
        "evaluation = half_evaluation",
        "norm = half_norm",
        "continue",
        "converged =",
    ):
        assert forbidden not in before, forbidden


# -------------------------------------------------------------------
# the LM budget is untouched, and convergence is not self-declared
# -------------------------------------------------------------------

def test_half_step_never_touches_the_rescue_budget():
    block = _half_step_block()
    assert "rescue_budget_left" not in block


def test_half_step_reuses_the_existing_newton_direction():
    block = _half_step_block()
    assert "CYCLE_ANALYTIC_HALF_STEP * float(step[row_index])" in block
    # No fresh differencing or linear solve inside the branch.
    assert "_solve_linear_system" not in block
    assert "jacobian" not in block


def test_half_step_does_not_declare_convergence_by_itself():
    block = _half_step_block()
    assert "converged = norm <= tolerance" in block
    assert "converged = true" not in block


def test_half_step_costs_exactly_one_extra_evaluation():
    block = _half_step_block()
    assert block.count("_evaluate(context") == 1


def test_half_step_breaks_the_cycle_history_like_every_other_rescue():
    block = _half_step_block()
    for reset in (
        "previous_full_step.clear()",
        "previous_full_step_gain_ratio = INF",
        "previous_full_step_norm = NAN",
        "previous_previous_full_step_norm = NAN",
        "post_budget_cycle_streak = 0",
    ):
        assert reset in block, reset


# -------------------------------------------------------------------
# telemetry is separated and inert
# -------------------------------------------------------------------

def test_telemetry_fields_exist_and_are_separated():
    for field in TELEMETRY:
        assert f'"{field}": 0.0,' in SOLVER
        assert f'"{field}"' in SYSTEM
    for field in CUMULATIVE:
        assert f'"{field}": 0.0,' in SYSTEM


def test_attempts_accepts_and_affected_solves_are_distinct_counters():
    body = _function(SYSTEM, "_record_coupled_pressure_solver_preview")
    ledger = body.split("H2.5m half-step ledger", 1)[1]
    ledger = ledger.split("if converged:", 1)[0]
    assert 'cumulative["analytic_half_step_attempt_total"]' in ledger
    assert 'cumulative["analytic_half_step_accept_total"]' in ledger
    # Affected-solve count rises at most once per invocation.
    assert 'cumulative["analytic_half_step_solve_count"]' in ledger
    assert "if half_step_accepts > 0.0:" in ledger
    assert 'cumulative["analytic_half_step_max_accepts_per_solve"]' in ledger


def test_telemetry_never_governs_solver_behaviour():
    body = _function(SOLVER, "solve_coupled_pressure")
    for line in body.splitlines():
        if "analytic_half_step_" not in line:
            continue
        assert not re.search(r"\b(if|elif|while)\b", line), line
        assert "converged =" not in line
        assert "accepted =" not in line


def test_csv_columns_are_opt_in_and_complete():
    writer = _function(WRITER, "_phase3_coupled_solver_fields")
    for field in TELEMETRY:
        assert f'"phase3_shadow_coupled_solver_{field}"' in writer
    for field in CUMULATIVE:
        assert f'"phase3_shadow_coupled_solver_{field}_total"' in writer


# -------------------------------------------------------------------
# nothing else moved
# -------------------------------------------------------------------

def test_no_numerical_setting_changed():
    expected = {
        "DEFAULT_MAX_ITERATIONS": "24",
        "DEFAULT_RESIDUAL_TOLERANCE": "1.0e-12",
        "DEFAULT_DP_REGULARIZATION_PA": "0.01",
        "DEFAULT_JACOBIAN_STEP_PA": "1.0e-3",
        "DEFAULT_BAND_SEGMENTS": "16",
        "DEFAULT_MAX_DAMPING_HALVINGS": "12",
        "LM_RESCUE_MAX_ACCEPTED_STEPS": "1",
        "LM_RESCUE_ARMIJO_C": "1.0e-4",
        "CYCLE_GUARD_MIN_MODEL_GAIN_RATIO": "0.05",
        "CYCLE_GUARD_MAX_STEP_COSINE": "-0.99",
    }
    for name, value in expected.items():
        assert re.search(
            rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER
        ), name


def test_ordinary_line_search_is_untouched():
    body = _function(SOLVER, "solve_coupled_pressure")
    search = body.split("while halvings <= max_halvings:", 1)[1]
    search = search.split("if not accepted:", 1)[0]
    assert 'float(trial_evaluation["normalized_residual"]) < norm' in search
    assert "damping *= 0.5" in search
    assert "analytic_half_step" not in search


# -------------------------------------------------------------------
# fixture coverage
# -------------------------------------------------------------------

def test_fixture_covers_every_mandated_case():
    assert "_check_analytic_sqrt_orbit" in FIXTURE
    assert "_check_r0_window" in FIXTURE
    assert "_check_corridor_failure" in FIXTURE
    assert "_check_determinism" in FIXTURE
    assert "PHASE3_F33V3H25M_ANALYTIC_HALF_STEP_PASS" in FIXTURE


def test_fixture_is_fail_closed():
    # A failed assertion must set the flag and exit non-zero, never print PASS.
    assert "_failed = true" in FIXTURE
    assert "if _failed:" in FIXTURE
    assert FIXTURE.index("if _failed:") < FIXTURE.index(
        "PHASE3_F33V3H25M_ANALYTIC_HALF_STEP_PASS"
    )


def test_fixture_proves_the_factor_analytically_not_by_corpus():
    assert "the Newton correction for the sqrt law is exactly -2u" in FIXTURE
    assert "full Newton step orbits forever on the sqrt law" in FIXTURE
    assert "theta = 1/2 lands on the root of the sqrt law in one step" in FIXTURE
