"""Contracts for the H2.7 iteration-budget diagnosis.

H2.6 handed this phase a blocker phrased as a budget problem. H2.7 showed the
premise was wrong: the cap is above P99 and the large-network failures are an
undetected period-2 orbit. These tests pin the evidence that supports that
reversal, and pin the harnesses as diagnostics that cannot leak into the
shipped solver.
"""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER_PATH = ROOT / "sim/core/Phase3CoupledPressureSolver.gd"
SOLVER = SOLVER_PATH.read_text(encoding="utf-8")
DATA = ROOT / "tests/fixtures/data"
DIAG = ROOT / "tools/diagnostics"
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v3h27_large_network_captures.gd"
).read_text(encoding="utf-8")
DOC = (
    ROOT / "docs/validation/PHASE3_F33V3H27_ITERATION_BUDGET_DESIGN.md"
).read_text(encoding="utf-8")

HARNESSES = (
    "phase3_h27_budget_anatomy.gd",
    "phase3_h27_stall_anatomy.gd",
    "phase3_h27_policy_probe.gd",
)

CAPTURES = {
    "coupled_solver_iteration_cap_two_floor_stairwell": ("iteration_cap", 11, 24),
    "coupled_solver_iteration_cap_two_storey_smoke": ("iteration_cap", 11, 24),
    "coupled_solver_iteration_cap_three_bed_apartment": ("iteration_cap", 7, 24),
    "coupled_solver_iteration_cap_flashover_simple_house": ("iteration_cap", 6, 24),
    "coupled_solver_damping_exhausted_uk_bungalow": ("damping_exhausted", 5, 12),
}


def _load(stem: str) -> dict:
    return json.loads((DATA / f"{stem}.json").read_text(encoding="utf-8"))


# -------------------------------------------------------------------
# the captures are versioned, exact, and free of volatile data
# -------------------------------------------------------------------

def test_all_five_captures_are_versioned():
    for stem in CAPTURES:
        assert (DATA / f"{stem}.json").exists(), stem


def test_captures_record_schema_selector_and_outcome():
    for stem, (reason, rooms, iterations) in CAPTURES.items():
        data = _load(stem)
        assert data["schema_version"] == "simufire_coupled_solver_failure_v1"
        assert data["requested_failure_mode"] == reason
        assert data["observed_failure"]["limiting_reason"] == reason
        assert data["observed_failure"]["converged"] is False
        assert len(data["input"]["rooms"]) == rooms
        assert int(float(data["observed_failure"]["iterations"]["d"])) == iterations


def test_captures_keep_exact_ieee754_representation():
    """`d` alone would be lossy in principle; `x` is what makes replay exact."""
    for stem in CAPTURES:
        data = _load(stem)
        leaf = data["input"]["openings"][0]["width_m"]
        assert set(leaf) == {"d", "x"}
        assert len(leaf["x"]) == 16
        import struct
        packed = bytes.fromhex(leaf["x"])
        assert struct.unpack("<d", packed)[0] == float(leaf["d"])


def test_captures_carry_no_absolute_paths_or_timestamps():
    for stem in CAPTURES:
        raw = (DATA / f"{stem}.json").read_text(encoding="utf-8")
        assert "C:\\" not in raw and "/Users/" not in raw
        assert not re.search(r"20\d\d-\d\d-\d\dT", raw)
        # The step index must be an opaque integer, not a time.
        assert isinstance(_load(stem)["persistent_step_index"], int)


def test_capture_names_say_which_mode_they_pin():
    for stem, (reason, _, _) in CAPTURES.items():
        assert reason in stem, stem


# -------------------------------------------------------------------
# the fixture pins the four orbits and the one that is not an orbit
# -------------------------------------------------------------------

def test_fixture_separates_the_orbits_from_the_damping_case():
    """H2.8 closed the four orbits, so the table now records what they COST
    before the detector was widened. The damping case must still be absent from
    it: no budget ever closed that one."""
    assert "PRE_H28_BUDGET" in FIXTURE
    for stem in CAPTURES:
        assert stem in FIXTURE, stem
    budget = FIXTURE.split("const PRE_H28_BUDGET := {", 1)[1].split("}", 1)[0]
    assert "coupled_solver_damping_exhausted_uk_bungalow" not in budget
    assert budget.count("coupled_solver_iteration_cap_") == 4


def test_fixture_asserts_the_damping_case_is_budget_immune():
    assert "_check_damping_case_is_not_a_budget_problem" in FIXTURE
    assert "for budget in [24, 64, 256]" in FIXTURE
    assert "stays damping_exhausted at budget" in FIXTURE


def test_fixture_keeps_the_recorded_history_as_provenance():
    """The captures record the trajectory the solver took WHEN CAPTURED. H2.8
    no longer takes it, so replaying against it would compare to a path the
    detector now avoids. The record is kept and checked for wellformedness and
    self-consistency rather than replayed - or quietly dropped."""
    assert "PRE-H2.8 artifact" in FIXTURE
    assert "recorded history is present" in FIXTURE
    assert "recorded outcome matches the selector it was taken with" in FIXTURE


def test_negative_controls_compare_history_not_iteration_count():
    """Iteration count is insensitive here: the orbit length is robust to a
    one percent edit, so an earlier count-based control was vacuous."""
    assert "_same_history" in FIXTURE
    block = FIXTURE.split("func _check_negative_controls", 1)[1]
    block = block.split("\nfunc ", 1)[0]
    for mutation in ('"round"', '"opening"', '"source"'):
        assert mutation in block, mutation
    assert "must not reproduce the residual history" in block


def test_rounding_control_actually_discards_precision():
    """`d` carries 17 digits and round-trips exactly, so reading it is not a
    rounding control. The fixture must truncate instead."""
    assert "_to_significant" in FIXTURE
    assert "_to_significant(value, 6)" in FIXTURE
    assert "round-trips a double exactly" in FIXTURE


def test_fixture_is_fail_closed():
    assert "_failed = true" in FIXTURE
    assert FIXTURE.index("if _failed:") < FIXTURE.index(
        "PHASE3_F33V3H27_LARGE_NETWORK_CAPTURES_PASS"
    )


# -------------------------------------------------------------------
# harnesses are diagnostics only
# -------------------------------------------------------------------

def test_harnesses_exist_and_are_read_only_to_the_simulation():
    for name in HARNESSES:
        source = (DIAG / name).read_text(encoding="utf-8")
        assert "extends SceneTree" in source
        assert "SimulationEngine" not in source
        assert "BuildingModel" not in source
        assert "run_scenario" not in source


def test_harnesses_never_touch_the_shipped_cap():
    """Comments may name the constant - saying you do not touch it is good
    documentation. Only executable lines are checked."""
    for name in HARNESSES:
        source = (DIAG / name).read_text(encoding="utf-8")
        code = "\n".join(
            line for line in source.splitlines()
            if not line.lstrip().startswith("#")
        )
        assert "DEFAULT_MAX_ITERATIONS" not in code, name
        # A raised budget may only travel through the per-call option.
        if "max_iterations" in code:
            assert '"max_iterations":' in code, name
    assert re.search(r"const DEFAULT_MAX_ITERATIONS: int = 24\b", SOLVER)


def test_harnesses_write_only_under_runs():
    for name in HARNESSES:
        source = (DIAG / name).read_text(encoding="utf-8")
        for match in re.finditer(r'OUT_PATH := "([^"]+)"', source):
            assert match.group(1).startswith("res://runs/"), name


def test_harnesses_read_only_committed_captures():
    """H2.5l-A had to be withdrawn for measuring on mutable scratch cases."""
    for name in HARNESSES:
        source = (DIAG / name).read_text(encoding="utf-8")
        assert "scratch" not in source.lower()


def test_policy_probe_isolates_the_predicate_it_varies():
    source = (DIAG / "phase3_h27_policy_probe.gd").read_text(encoding="utf-8")
    assert "func _detect(" in source
    body = source.split("func _detect(", 1)[1].split("\nfunc ", 1)[0]
    # P2 reuses the shipped thresholds; it introduces no new constant.
    assert "0.05" in body and "-0.99" in body
    assert "minf(previous_gain, gain) < 0.05" in body
    numbers = set(re.findall(r"(?<![\w.])\d+\.\d+", body))
    assert numbers <= {"0.05", "0.99"}, numbers


# -------------------------------------------------------------------
# the reversal is recorded, with its evidence
# -------------------------------------------------------------------

def test_document_states_the_cap_is_not_the_cause():
    assert "not the defect" in DOC
    assert "NO-GO for any iteration-budget policy" in DOC


def test_document_records_the_distribution_and_the_absent_correlation():
    assert "P99" in DOC
    assert "5016" in DOC
    assert "refuted" in DOC


def test_document_keeps_uk_bungalow_as_a_separate_mode():
    assert "uk_bungalow" in DOC
    assert "damping_exhausted" in DOC
    assert "separate" in DOC.lower() or "distinct" in DOC.lower()


def test_document_defers_p2_to_a_later_phase():
    assert "H2.8" in DOC
    assert "NOT applied" in DOC or "not applied" in DOC


def test_no_solver_constant_moved():
    expected = {
        "DEFAULT_MAX_ITERATIONS": "24",
        "DEFAULT_RESIDUAL_TOLERANCE": "1.0e-12",
        "CYCLE_GUARD_MIN_MODEL_GAIN_RATIO": "0.05",
        "CYCLE_GUARD_MAX_STEP_COSINE": "-0.99",
        "CYCLE_ANALYTIC_HALF_STEP": "0.5",
        "LM_RESCUE_MAX_ACCEPTED_STEPS": "1",
    }
    for name, value in expected.items():
        assert re.search(
            rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER
        ), name


def test_p2_was_implemented_in_h28_as_this_phase_recommended():
    """H2.7 recommended P2 and deferred it. H2.8 implemented exactly that: the
    minimum of the same pair against the same threshold, with every geometric
    condition untouched."""
    body = SOLVER.split("func solve_coupled_pressure(", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    assert "cycle_min_gain_ratio = minf(" in body
    assert "previous_full_step_gain_ratio" in body
    assert "model_gain_ratio" in body
    # The conjunction this phase diagnosed as unfirable must be gone.
    predicate = body.split("cycle_detected = (", 1)[1].split(")", 1)[0]
    assert "and model_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO" \
        not in predicate
    assert "cycle_min_gain_ratio < CYCLE_GUARD_MIN_MODEL_GAIN_RATIO" in predicate
