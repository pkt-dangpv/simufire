"""Contracts for H2.5l-B per-solve recurrence ledger.

The ledger classifies each solver invocation by whether it had post-budget
cycle recurrence and, if so, by outcome (converged / iteration_cap /
damping_exhausted). It also tracks the longest consecutive post-budget cycle
streak within a single solve.

Structural invariants:
- streak is observation-only, never governs behaviour;
- each solve adds at most one to any outcome counter;
- outcome classification is mutually exclusive;
- OFF CSV is byte-identical (no new columns visible when shadow is off);
- ON CSV preserves all pre-existing columns;
- deterministic across replays.
"""

import json
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
FIXTURE = (
    ROOT
    / "tests/fixtures"
    / "phase3_f33v3h25lb_per_solve_recurrence_ledger.gd"
).read_text(encoding="utf-8")

SOLVER_FIELD = "post_budget_cycle_streak_max"
CUMULATIVE_FIELDS = (
    "post_budget_cycle_solve_count",
    "post_budget_cycle_converged_solve_count",
    "post_budget_cycle_iteration_cap_solve_count",
    "post_budget_cycle_damping_exhausted_solve_count",
    "post_budget_cycle_streak_max",
)


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


# -------------------------------------------------------------------
# Solver: streak tracking
# -------------------------------------------------------------------

def test_streak_is_inside_observation_block_outside_budget_gate():
    body = _function(SOLVER, "solve_coupled_pressure")
    observe = body.index("if cycle_detected:")
    budget = body.index("if cycle_detected and rescue_budget_left > 0:")
    observation_block = body[observe:budget]
    assert "post_budget_cycle_streak += 1" in observation_block
    assert 'result["post_budget_cycle_streak_max"]' in observation_block


def test_streak_resets_on_all_trajectory_breaks():
    body = _function(SOLVER, "solve_coupled_pressure")
    lines = [line.strip() for line in body.splitlines()]
    clear_count = lines.count("post_budget_cycle_streak = 0")
    assert clear_count >= 4, (
        f"expected at least 4 streak resets (fail-only rescue, cycle rescue, "
        f"damped step, no-cycle), got {clear_count}"
    )


def test_streak_result_field_exists_in_new_result():
    assert f'"{SOLVER_FIELD}": 0.0,' in SOLVER


def test_streak_never_controls_solver_behaviour():
    body = _function(SOLVER, "solve_coupled_pressure")
    for line in body.splitlines():
        if "post_budget_cycle_streak" not in line:
            continue
        assert not re.search(r"\b(if|elif|while)\b", line), line
        assert "converged =" not in line
        assert "accepted =" not in line
        assert "return result" not in line


# -------------------------------------------------------------------
# Zone mass system: per-solve ledger
# -------------------------------------------------------------------

def test_per_solve_classification_is_mutually_exclusive():
    body = _function(SYSTEM, "_record_coupled_pressure_solver_preview")
    ledger = body.split("H2.5l-B per-solve", 1)[1]
    ledger = ledger.split("# Publish cumulative", 1)[0]
    assert "if has_post_budget_cycle:" in ledger
    assert "if converged:" in ledger
    assert 'elif limiting_reason == "iteration_cap":' in ledger
    assert 'elif limiting_reason == "damping_exhausted":' in ledger


def test_each_solve_adds_at_most_one_to_solve_count():
    body = _function(SYSTEM, "_record_coupled_pressure_solver_preview")
    ledger_block = body.split("H2.5l-B per-solve", 1)[1]
    ledger_block = ledger_block.split("# Publish cumulative", 1)[0]
    occurrences = ledger_block.count(
        'cumulative["post_budget_cycle_solve_count"]'
    )
    assert occurrences == 2, (
        f"expected exactly 2 (one read, one write), got {occurrences}"
    )
    assert '+ 1.0' in ledger_block


def test_cumulative_fields_in_record_and_cumulative():
    for field in CUMULATIVE_FIELDS:
        if field == SOLVER_FIELD:
            assert f'"{field}": 0.0,' in SOLVER
        assert f'"{field}"' in SYSTEM


def test_cumulative_fields_exported_to_csv():
    writer_block = _function(WRITER, "_phase3_coupled_solver_fields")
    assert f'"phase3_shadow_coupled_solver_{SOLVER_FIELD}"' in writer_block
    for field in CUMULATIVE_FIELDS:
        total_col = f'"phase3_shadow_coupled_solver_{field}_total"'
        assert total_col in writer_block, f"missing {total_col}"


# -------------------------------------------------------------------
# Mutation detection
# -------------------------------------------------------------------

def test_mutation_streak_inside_budget_gate_is_detectable():
    """Pin the gate that owns the streak, not merely the first one in the file.

    H2.5m introduced a second `if cycle_detected:` block for the analytic half
    step, so this locates the observation gate by its counter.
    """
    body = _function(SOLVER, "solve_coupled_pressure")
    counter = "post_budget_cycle_streak += 1"
    bare = "if cycle_detected:"
    opener = body.rindex(bare, 0, body.index(counter))
    assert not body[opener:].startswith(f"{bare[:-1]} and")
    mutated = (
        body[:opener]
        + "if cycle_detected and rescue_budget_left > 0:"
        + body[opener + len(bare):]
    )
    reopened = mutated.rindex("if cycle_detected", 0, mutated.index(counter))
    assert mutated[reopened:].startswith(
        "if cycle_detected and rescue_budget_left > 0:"
    )
    assert mutated != body


def test_mutation_streak_used_for_convergence_would_fail():
    body = _function(SOLVER, "solve_coupled_pressure")
    for line in body.splitlines():
        if "post_budget_cycle_streak" in line:
            assert "converged" not in line or "converged =" not in line


# -------------------------------------------------------------------
# Fixture
# -------------------------------------------------------------------

def test_fixture_replays_without_engine_or_scenario_authority():
    assert "extends SceneTree" in FIXTURE
    assert "Phase3CoupledPressureSolver.gd" in FIXTURE
    assert "SimulationEngine" not in FIXTURE
    assert "run_scenario" not in FIXTURE
    assert "BuildingModel" not in FIXTURE
    assert "PHASE3_F33V3H25LB_PER_SOLVE_RECURRENCE_LEDGER_PASS" in FIXTURE


def test_fixture_records_the_h25m_regime_change_rather_than_hiding_it():
    """The streak this ledger measures is structurally zero on this capture now.

    H2.5m closes the orbit at the first detection without spending the rescue
    budget, so no post-budget streak can form here (was 21). The ledger
    arithmetic is still asserted; the lost exercise is recorded explicitly.
    """
    assert "H2.5m REGIME CHANGE" in FIXTURE
    assert (
        'float(first.get("post_budget_cycle_streak_max", 0.0)) == 0.0'
        in FIXTURE
    )
    assert (
        'float(first.get("analytic_half_step_accept_total", 0.0)) == 1.0'
        in FIXTURE
    )
    assert "streak cannot exceed total post-budget detections" in FIXTURE
    assert "accepts never exceed attempts" in FIXTURE
    assert "coverage gap" in FIXTURE or "STOP gate" in FIXTURE


def test_fixture_asserts_determinism():
    assert "deterministic post_budget_cycle_streak_max" in FIXTURE


def test_fixture_asserts_streak_bounded_by_total():
    assert "streak cannot exceed total post-budget detections" in FIXTURE


# -------------------------------------------------------------------
# No numerical setting changed
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
    }
    for name, value in expected.items():
        assert re.search(
            rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER
        ), name
    context = _function(SOLVER, "_build_context")
    assert "post_budget_cycle_streak" not in context
