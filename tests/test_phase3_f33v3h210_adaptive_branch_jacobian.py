"""Structural contracts for H2.10 adaptive unilateral Jacobian recovery."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOLVER = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
ZONE = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
WRITER = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v3h210_adaptive_branch_jacobian.gd"
).read_text(encoding="utf-8")
DOC = (
    ROOT / "docs/validation/PHASE3_F33V3H210_ADAPTIVE_BRANCH_JACOBIAN.md"
).read_text(encoding="utf-8")


def _function(name: str) -> str:
    body = SOLVER.split(f"func {name}", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_adaptive_authority_is_fail_only_and_precedes_lm():
    loop = SOLVER.split("while not converged", 1)[1].split("var model_gain_ratio", 1)[0]
    failed = loop.split("if not accepted:", 1)[1]
    assert failed.index("_try_adaptive_branch_jacobian_recovery") < failed.index(
        "_try_lm_rescue"
    )
    assert "_try_adaptive_branch_jacobian_recovery" not in loop.split(
        "if not accepted:", 1
    )[0]


def test_successful_forward_jacobian_block_is_unchanged_in_shape():
    loop = SOLVER.split("while not converged", 1)[1].split("if not accepted:", 1)[0]
    assert "perturbed[column] = perturbed[column] + jacobian_step_pa" in loop
    assert 'float(forward["residual"][row_index])' in loop
    assert 'float(evaluation["residual"][row_index])' in loop


def test_recovery_uses_both_unilateral_sides_not_central_difference():
    body = _function("_build_branch_preserving_jacobian")
    assert "forward_pressure[column]" in body
    assert "backward_pressure[column]" in body
    assert "use_backward" in body
    assert "/ (2.0 * step_pa)" not in body


def test_branch_comparison_is_categorical_and_lexicographic():
    rank = _function("_branch_change_rank")
    compare = _function("_branch_rank_less")
    for token in (
        "donor_changes",
        "neutral_changes",
        "regularization_changes",
        "delta_p_pa",
        "neutral_plane_inside",
        "regularization_active_count",
    ):
        assert token in rank
    assert "for index in range" in compare
    assert not re.search(r"score\s*[+*]=", rank)


def test_tie_preserves_forward_bias():
    body = _function("_build_branch_preserving_jacobian")
    assert "_branch_rank_less(backward_rank, forward_rank)" in body
    assert 'sides.append(1)' in body


def test_width_refinement_uses_existing_budget_and_halving_only():
    body = _function("_try_adaptive_branch_jacobian_recovery")
    assert "range(max_halvings + 1)" in body
    assert "step_pa *= 0.5" in body
    assert "options.get(" not in body


def test_two_consecutive_widths_and_same_sides_are_required():
    body = _function("_try_adaptive_branch_jacobian_recovery")
    assert "not previous_candidate.is_empty()" in body
    assert "sides == previous_sides" in body
    accept = body.split('outcome["accepted"] = true', 1)[0]
    assert "sides == previous_sides" in accept


def test_adaptive_acceptance_is_strict_linf_decrease():
    body = _function("_try_strict_linf_candidate")
    assert 'float(trial_evaluation["normalized_residual"]) < norm' in body
    executable = body.split("## One bounded Levenberg", 1)[0]
    assert "_rescue_merit" not in executable


def test_recovery_never_declares_convergence_itself():
    body = _function("_try_adaptive_branch_jacobian_recovery")
    assert '"converged"' not in body
    callsite = SOLVER.split(
        "_try_adaptive_branch_jacobian_recovery", 1
    )[1].split("# FAIL-ONLY RECOVERY", 1)[0]
    assert "converged = norm <= tolerance" in callsite


def test_existing_numerical_constants_are_unchanged():
    for token in (
        "const DEFAULT_MAX_ITERATIONS: int = 24",
        "const DEFAULT_RESIDUAL_TOLERANCE: float = 1.0e-12",
        "const DEFAULT_DP_REGULARIZATION_PA: float = 0.01",
        "const DEFAULT_JACOBIAN_STEP_PA: float = 1.0e-3",
        "const LM_RESCUE_MAX_ACCEPTED_STEPS: int = 1",
        "const CYCLE_ANALYTIC_HALF_STEP: float = 0.5",
    ):
        assert token in SOLVER


def test_no_new_adaptive_option_or_per_case_knob():
    assert "adaptive_jacobian" not in SOLVER.split("func _build_context", 1)[1]
    body = _function("_try_adaptive_branch_jacobian_recovery")
    assert "options.get(" not in body


def test_telemetry_fields_are_wired_consistently():
    fields = (
        "attempt_total",
        "accept_total",
        "columns_forward_total",
        "columns_backward_total",
        "columns_reduced_total",
        "branch_crossing_avoided_total",
        "derivative_consistency_fail_total",
        "min_effective_step_pa",
    )
    for field in fields:
        token = f"adaptive_jacobian_{field}"
        assert token in SOLVER
        assert token in ZONE
        assert f"phase3_shadow_coupled_solver_{token}" in WRITER


def test_telemetry_does_not_govern_solver_decisions():
    for line in SOLVER.splitlines():
        stripped = line.strip()
        if stripped.startswith(("if ", "elif ", "while ")):
            assert "adaptive_jacobian_" not in stripped


def test_fixture_pins_all_nine_exact_captures_and_189_states():
    capture_table = FIXTURE.split("const CAPTURES := [", 1)[1].split("]", 1)[0]
    assert capture_table.count('"coupled_solver_') == 9
    assert "for variant in range(21)" in FIXTURE
    assert "H210_NEIGHBOURHOOD %d/189" in FIXTURE


def test_fixture_adds_parallel_opening_c8_contract():
    assert "_test_parallel_openings_c8" in FIXTURE
    assert '"opening_id": 100' in FIXTURE
    assert '"opening_id": 101' in FIXTURE
    assert "C8 preserves both openings" in FIXTURE
    assert "C8 conserves interior mass" in FIXTURE


def test_fixture_requires_uk_adaptive_authority_without_lm():
    uk = FIXTURE.split(
        'if name == "coupled_solver_damping_exhausted_uk_bungalow":', 1
    )[1].split("\n\n", 1)[0]
    assert 'adaptive_jacobian_accept_total' in uk
    assert 'rescue_accepted' in uk


def test_design_states_the_gate_status_explicitly():
    """The document must say where the phase gates stand, not leave it implicit.

    This assertion was written while H2.10 was still a design phase with a
    pending STOP gate, and required the document to say H2 was open and H3
    blocked. The gate has since passed, so the required wording is the approved
    verdict instead: H2 closes as numerical readiness for the passive solver,
    H3 becomes unblocked, and closing H2 grants no authority by itself.
    """
    assert "H2 is closed as numerical readiness for the passive coupled pressure" in DOC
    assert "H3 is unblocked" in DOC
    assert "H3 has not started" in DOC
    assert "grants no" in DOC and "runtime authority" in DOC
    # The pre-gate constraint is retained as the record of how it was run.
    assert "No H2.10 commit or push is allowed before this gate is reported" in DOC


def test_design_requires_runtime_and_identity_gates():
    for token in (
        "ten committed runtime topology cases",
        "OFF byte identity",
        "zero converged-to-failed solves",
        "shared-root delta bound",
        "LM-use delta",
    ):
        assert token in DOC
