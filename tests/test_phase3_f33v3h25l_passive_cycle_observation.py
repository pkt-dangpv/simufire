"""Contracts for H2.5l-A passive coupled-solver cycle observation.

Observation may continue after the single LM rescue budget is exhausted.
Authority may not: the new values are telemetry only and cannot alter a Newton
step, acceptance, rescue, convergence or failure mode.
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
CAPTURE = (
    ROOT
    / "tests/fixtures/data"
    / "coupled_solver_iteration_cap_after_rescue_corridor_chain.json"
)
FIXTURE = (
    ROOT
    / "tests/fixtures"
    / "phase3_f33v3h25l_post_budget_cycle_observation.gd"
).read_text(encoding="utf-8")

FIELDS = (
    "cycle_detect_total",
    "cycle_detect_after_budget_total",
    "cycle_contraction_min",
    "cycle_contraction_max",
)


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_observation_is_outside_the_rescue_budget_gate():
    body = _function(SOLVER, "solve_coupled_pressure")
    observe = body.index("if cycle_detected:")
    budget = body.index("if cycle_detected and rescue_budget_left > 0:")
    assert observe < budget
    observation_block = body[observe:budget]
    assert 'result["cycle_detect_total"] += 1.0' in observation_block
    assert "if rescue_budget_left <= 0:" in observation_block
    assert 'result["cycle_detect_after_budget_total"] += 1.0' in observation_block


def test_rescue_authority_remains_inside_the_original_budget_gate():
    body = _function(SOLVER, "solve_coupled_pressure")
    guarded = body.split(
        "if cycle_detected and rescue_budget_left > 0:", 1
    )[1].split("if damping == 1.0:", 1)[0]
    assert "_try_lm_rescue(" in guarded
    assert "rescue_budget_left -= 1" in guarded
    assert 'result["cycle_guard_accept_total"] += 1.0' in guarded
    assert "cycle_detect_after_budget_total" not in guarded


def test_two_step_contraction_uses_k_minus_two_not_the_previous_step():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert "previous_full_step_norm" in body
    assert "previous_previous_full_step_norm" in body
    assert (
        "_step_norm(step) / maxf(\n"
        "\t\t\t\t\tprevious_previous_full_step_norm, 1.0e-300"
    ) in body
    shift = (
        "previous_previous_full_step_norm = previous_full_step_norm\n"
        "\t\t\tprevious_full_step_norm = _step_norm(step)"
    )
    assert shift in body


def test_cycle_history_resets_where_step_continuity_is_broken():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert body.count("previous_full_step.clear()") == 3
    lines = [line.strip() for line in body.splitlines()]
    assert lines.count("previous_full_step_norm = NAN") == 3
    assert lines.count("previous_previous_full_step_norm = NAN") == 3


def test_new_metrics_never_control_solver_behaviour():
    body = _function(SOLVER, "solve_coupled_pressure")
    for field in FIELDS:
        for line in body.splitlines():
            if field not in line:
                continue
            assert not re.search(r"\b(if|elif|while)\b", line), line
            assert "converged =" not in line
            assert "accepted =" not in line
            assert "return result" not in line


def test_mutation_putting_observation_back_behind_budget_is_detectable():
    required = "if cycle_detected:\n"
    assert required in SOLVER
    mutated = SOLVER.replace(
        required,
        "if cycle_detected and rescue_budget_left > 0:\n",
        1,
    )
    body = _function(mutated, "solve_coupled_pressure")
    assert "if cycle_detected:\n" not in body


def test_result_wiring_is_opt_in_and_complete():
    writer_block = _function(WRITER, "_phase3_coupled_solver_fields")
    for field in FIELDS:
        assert f'"{field}": 0.0,' in SOLVER
        assert f'"{field}": 0.0,' in SYSTEM
        assert f'"phase3_shadow_coupled_solver_{field}"' in writer_block
        assert f'"{field}"' in SYSTEM


def test_no_numerical_setting_changed_or_became_configurable():
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
    for field in FIELDS:
        assert field not in context


def test_real_post_budget_capture_is_versioned_with_the_composite_selector():
    data = json.loads(CAPTURE.read_text(encoding="utf-8"))
    assert data["schema_version"] == "simufire_coupled_solver_failure_v1"
    assert data["requested_failure_mode"] == "iteration_cap_after_rescue"
    assert data["observed_failure"]["converged"] is False
    assert data["observed_failure"]["limiting_reason"] == "iteration_cap"
    assert int(float(data["observed_failure"]["iterations"]["d"])) == 24


def test_fixture_replays_without_engine_or_scenario_authority():
    assert "extends SceneTree" in FIXTURE
    assert "Phase3CoupledPressureSolver.gd" in FIXTURE
    assert "SimulationEngine" not in FIXTURE
    assert "run_scenario" not in FIXTURE
    assert "BuildingModel" not in FIXTURE
    assert "PHASE3_F33V3H25L_POST_BUDGET_CYCLE_OBSERVATION_PASS" in FIXTURE


def test_fixture_requires_observation_beyond_the_single_rescue():
    assert (
        'float(first.get("cycle_guard_attempt_total", 0.0)) == 1.0'
        in FIXTURE
    )
    assert (
        'float(first.get("cycle_guard_accept_total", 0.0)) == 1.0'
        in FIXTURE
    )
    assert (
        'float(first.get("cycle_detect_after_budget_total", 0.0)) > 0.0'
        in FIXTURE
    )
    assert (
        'int(first.get("iterations", 0.0)) == 24'
        in FIXTURE
    )
