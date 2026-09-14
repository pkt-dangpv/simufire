"""Structural contracts for the H3.2b1b persistent zone transition ledger.

The counters it replaces were structurally blind: they compared `pre` and `post`
inside one projection call, and projection never creates upper mass. These
contracts pin the repair and the honesty constraints around it:

* the observer is seeded before the first physical step, and a seed is never a
  transition;
* two cardinality identities over two different populations, never summed;
* room-set changes are `room_added` / `room_removed`, never births or deaths;
* four presence predicates, none authoritative;
* step granularity primary, call granularity a narrower bound, both lower bounds;
* no cause attribution anywhere at call granularity;
* the historical counter names survive as deprecated aliases;
* passive, cumulative, fail-closed, default OFF, independent of H3.2b3.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LEDGER = (ROOT / "sim/core/Phase3ZoneTransitionLedger.gd").read_text(encoding="utf-8")
FIXTURE = (ROOT / "tests/fixtures/phase3_h32b1b_zone_transition.gd").read_text(
    encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
CAUSAL = (ROOT / "sim/core/Phase3ProjectionCausalLedger.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")


def _strip_comments(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


CODE = _strip_comments(LEDGER)


def _func(text: str, name: str) -> str:
    return text.split("func %s(" % name, 1)[1].split("\nfunc ", 1)[0]


# --------------------------------------------------------------------------
# Flag, default OFF, independence
# --------------------------------------------------------------------------

def test_flag_is_new_and_defaults_off():
    assert ("@export var phase3_zone_transition_diagnostics_enabled: bool = false"
            in ENGINE)
    assert "var enabled: bool = false" in LEDGER


def test_flag_is_registered_in_the_activation_gate():
    # H3.2b3 established what happens to a flag that needs the per-call trace and
    # is missing from this gate: it is reasserted off at every logging point.
    gate = _func(ENGINE, "_phase3_projection_diagnostics_active")
    assert "phase3_zone_transition_diagnostics_enabled" in gate


def test_it_does_not_depend_on_the_shadow_or_the_primitive():
    # Banned in code. The doc comment names them precisely to say it does NOT
    # depend on them, and that statement must survive.
    for forbidden in ("Phase3ResidualProjectionShadow", "Phase3ResidualProjection",
                      "phase3_residual_projection", "phase3_zone_diagnostics"):
        assert forbidden not in CODE, forbidden
    assert "does not depend on the H3.2b3 shadow" in LEDGER
    # The ledger's own event consumer remains independent of every other owner.
    hook = _func(LEDGER, "observe_call")
    assert "residual" not in hook.lower()


def test_off_is_a_no_op():
    for name in ("seed", "observe_step", "observe_calls"):
        body = _func(LEDGER, name)
        guard = next(line.strip() for line in body.splitlines()
                     if line.strip().startswith("if "))
        assert "not enabled" in guard, name
    assert "if enabled and _seeded:" in _func(LEDGER, "observe_call")
    summary = _func(LEDGER, "summary")
    lines = [line.strip() for line in summary.splitlines()[1:] if line.strip()]
    assert lines[0] == "if not enabled:"
    assert lines[1] == "return {}"


# --------------------------------------------------------------------------
# Seeding and the observation point
# --------------------------------------------------------------------------

def test_the_seed_precedes_the_first_step_and_is_idempotent():
    body = _func(LEDGER, "seed")
    assert "if not enabled or _seeded:" in body
    assert "_seeded = true" in body
    seed_hook = _func(ENGINE, "_phase3_zone_transition_seed")
    assert "is_seeded()" in seed_hook
    # It is invoked at the START of the step, before any physics runs, and again
    # defensively from the observer. Seeding only from the observer would place
    # the first seed at the END of step one and lose every transition that
    # happened during it -- which is exactly what the >=29 gate caught.
    assert ENGINE.count("_phase3_zone_transition_seed()") == 3
    step_body = ENGINE.split("_ensure_carbon_balance_initialized()", 1)[1]
    step_body = step_body.split("_phase3_zone_runtime_begin_step_shared()", 1)[0]
    assert "_phase3_zone_transition_seed()" in step_body
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert hook.index("_phase3_zone_transition_seed()") < hook.index("observe_step(")


def test_the_seed_is_taken_before_any_physics_in_the_step():
    # The seeding call must precede every physics stage in step(), not merely
    # precede the observation at the end of it.
    step_index = ENGINE.index(
        "_phase3_zone_transition_seed()\n\t_phase3_zone_runtime_begin_step_shared()")
    for stage in ("_clamp_rooms(", "thermal_system.step(", "_check_carbon_balance()"):
        assert ENGINE.index(stage, step_index) > step_index, stage


def test_a_seed_is_never_a_transition():
    body = _func(LEDGER, "seed")
    assert "CounterField.INITIAL_PRESENT if present else CounterField.INITIAL_ABSENT" in body
    for forbidden in ("CounterField.BIRTH", "CounterField.DEATH",
                      "CounterField.STABLE_PRESENT", "CounterField.STABLE_ABSENT"):
        assert forbidden not in body, forbidden
    assert "never a transition" in LEDGER


def test_observing_without_a_seed_fails_closed():
    body = _func(LEDGER, "observe_step")
    assert "if not _seeded:" in body
    assert "record_unavailable(REASON_NOT_SEEDED)" in body
    assert "const REASON_NOT_SEEDED" in LEDGER


def test_the_observation_point_is_fixed_at_end_of_step():
    assert ENGINE.count("_phase3_projection_diagnostics_accumulate_shared()") == 2
    # It runs in the same place every step, after the other passive accumulators
    # and before the carbon balance check.
    between = ENGINE.split("_phase3_projection_diagnostics_accumulate_shared()\n", 1)[1]
    between = between.split("_check_carbon_balance()", 1)[0]
    assert "_phase3_zone_transition_ledger.observe_step(" in _func(
        ENGINE, "_phase3_projection_diagnostics_accumulate_shared")


# --------------------------------------------------------------------------
# Cardinality: two identities, two populations
# --------------------------------------------------------------------------

def test_initial_and_transition_classes_are_never_summed():
    body = _func(LEDGER, "_cardinality")
    assert "block[CounterField.INITIAL_PRESENT]" in body
    assert "block[CounterField.INITIAL_ABSENT]" in body
    transition_sum = body.split("var boundaries: int = (", 1)[1].split("\n\t)", 1)[0]
    for field in ("BIRTH", "DEATH", "STABLE_PRESENT", "STABLE_ABSENT",
                  "ROOM_ADDED", "ROOM_REMOVED"):
        assert field in transition_sum, field
    for forbidden in ("INITIAL_PRESENT", "INITIAL_ABSENT"):
        assert forbidden not in transition_sum, forbidden
    assert "never summed" in LEDGER


def test_rooms_times_steps_is_asserted_only_when_the_room_set_is_constant():
    body = _func(LEDGER, "_cardinality")
    assert "constant_room_set" in body
    assert "block[CounterField.ROOM_ADDED]" in body
    assert "block[CounterField.ROOM_REMOVED]" in body
    # The reduction is null, not false, when the room set changed.
    assert "if constant_room_set else null" in body


def test_room_set_changes_are_not_births_or_deaths():
    body = _func(LEDGER, "_classify_boundary")
    assert "CounterField.ROOM_ADDED" in body
    assert "CounterField.ROOM_REMOVED" in body
    pair = _func(LEDGER, "_classify_pair")
    for forbidden in ("room_added", "room_removed"):
        assert forbidden not in pair, forbidden
    assert "never a birth" in LEDGER
    assert "never a death" in LEDGER or "not a death" in LEDGER


# --------------------------------------------------------------------------
# Predicates
# --------------------------------------------------------------------------

def test_four_predicates_are_reported_and_none_is_authoritative():
    for name in ("PREDICATE_STRICT_POSITIVE", "PREDICATE_LEDGER",
                 "PREDICATE_PROJECTION", "PREDICATE_FED_GATE"):
        assert "const %s: String" % name in LEDGER, name
    assert '"authoritative_predicate": null,' in _func(LEDGER, "summary")
    assert "blocker owned by H3.2b6" in LEDGER


def test_each_threshold_is_mirrored_from_where_it_is_actually_used():
    assert "PREDICATE_STRICT_POSITIVE: 0.0," in LEDGER
    assert "PREDICATE_LEDGER: 1.0e-6," in LEDGER
    assert "PREDICATE_PROJECTION: 1.0e-4," in LEDGER
    assert "PREDICATE_FED_GATE: 0.1," in LEDGER
    # And those really are the values in the components they name.
    assert "const ZONE_MASS_EPS_KG: float = 1.0e-6" in CAUSAL
    assert "const ZONE_MASS_EPS_KG: float = 0.0001" in SOLVER


def test_the_ledger_threshold_provenance_is_corrected_not_misattributed():
    # The causal ledger's comment used to attribute 1.0e-6 to ZoneFireSolver,
    # whose constant is 1.0e-4. The H3.2b1b gate depends on which is which.
    block = CAUSAL.split("const ZONE_MASS_EPS_KG", 1)[0]
    assert "PROVENANCE CORRECTED" in block
    assert "1.0e-4" in block and "1.0e-6" in block


def test_every_predicate_gets_every_counter():
    body = _func(LEDGER, "_bucket")
    assert "_bucket_index(granularity, predicate)" in body
    block = _func(LEDGER, "_counter_block")
    exported = _func(LEDGER, "_counter_dictionary")
    assert "block.resize(CounterField.SIZE)" in block
    for field in ("initial_present", "initial_absent", "birth", "death",
                  "stable_present", "stable_absent", "room_added", "room_removed"):
        assert '"%s"' % field in exported, field


# --------------------------------------------------------------------------
# Granularity
# --------------------------------------------------------------------------

def test_call_granularity_compares_previous_post_against_next_pre():
    body = _func(LEDGER, "observe_call")
    assert "Field.PRE_UPPER_GAS_KG" in body
    assert "Field.POST_UPPER_GAS_KG" in body
    # The interval closes at this call's post, which becomes the next predecessor.
    assert "last[room_key] = _present(post_mass, predicate)" in body
    assert "pre_present" in body


def test_no_cause_attribution_at_call_granularity():
    body = _func(LEDGER, "observe_call")
    assert "cause" not in _strip_comments(body)
    assert "by_cause" not in LEDGER
    assert '"cause_attribution_note"' in _func(LEDGER, "summary")
    assert "not by the projection" in LEDGER


def test_both_granularities_are_declared_lower_bounds():
    assert '"granularity_note"' in _func(LEDGER, "summary")
    assert "lower bounds" in LEDGER
    assert "neither is ground truth" in LEDGER
    assert "PRIMARY" in LEDGER
    assert "NARROWER BOUND" in LEDGER


def test_call_granularity_declares_absence_when_the_trace_is_missing():
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert "projection_diagnostics_enabled" in hook
    assert "REASON_TRACE_UNAVAILABLE" in hook
    assert "record_unavailable" in hook


# --------------------------------------------------------------------------
# The historical surface survives
# --------------------------------------------------------------------------

def test_the_deprecated_aliases_are_preserved():
    exported = _func(CAUSAL, "_room_dictionary")
    for key in ("upper_zone_birth_count_total", "upper_zone_death_count_total"):
        assert '"%s"' % key in exported, key


def test_the_explicit_twins_exist_alongside_them():
    exported = _func(CAUSAL, "_room_dictionary")
    for key in ("within_projection_call_upper_zone_birth_count_total",
                "within_projection_call_upper_zone_death_count_total"):
        assert '"%s"' % key in exported, key
    assert '"deprecated_counter_note"' in CAUSAL
    assert "DEPRECATED aliases kept for" in CAUSAL


# --------------------------------------------------------------------------
# Passive
# --------------------------------------------------------------------------

def test_the_ledger_writes_no_state():
    assert not re.search(r"\broom\.\w+ *=[^=]", CODE)
    assert "RoomModel" not in CODE
    assert "BuildingModel" not in CODE
    assert CODE.count("preload(") == 1
    assert 'preload("res://sim/core/Phase3ProjectionTraceRecord.gd")' in CODE
    without_schema_preload = CODE.replace(
        'preload("res://sim/core/Phase3ProjectionTraceRecord.gd")', ""
    )
    for forbidden in ("load(\"", "get_node", "get_tree"):
        assert forbidden not in without_schema_preload, forbidden


ALLOWED_LEDGER_BRANCHES = {
    # The idempotent seeding guard. It is control flow over the OBSERVER's own
    # lifecycle, not a physics decision, and it reads no measurement.
    "if _phase3_zone_transition_ledger.is_seeded():",
}


def test_no_metric_governs_physics():
    for line in ENGINE.splitlines():
        stripped = line.strip()
        if "_phase3_zone_transition_ledger" not in stripped:
            continue
        if stripped.startswith("#"):
            continue
        if stripped.startswith("if ") or stripped.startswith("elif "):
            assert stripped in ALLOWED_LEDGER_BRANCHES, stripped
        assert "clampf(" not in stripped, stripped
        # No engine state is ever assigned FROM the ledger.
        assert not re.match(r"^(?!_phase3_zone_transition_ledger)\w+.*=\s*_phase3_zone_transition_ledger",
                            stripped), stripped
    for metric in ("room_added", "stable_absent", "PREDICATE_FED_GATE"):
        assert metric not in SOLVER, metric


def test_no_new_csv_column():
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "zone_transition" not in text
        assert "stable_absent" not in text


def test_the_summary_block_is_opt_in():
    assert 'summary["phase3_zone_transition"] = ' in ENGINE
    assert "if phase3_zone_transition_diagnostics_enabled:" in ENGINE


def test_every_exported_counter_is_cumulative():
    block = _func(LEDGER, "_counter_block")
    for key in re.findall(r'"(\w+)":', block):
        assert not key.endswith("_step"), key


# --------------------------------------------------------------------------
# Runner and fixture
# --------------------------------------------------------------------------

def test_the_runner_exposes_the_flag():
    runner = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
    assert '"--phase3-zone-transition-diagnostics"' in runner
    headless = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
    assert 'parsed["phase3_zone_transition_diagnostics"] = true' in headless
    assert "engine.phase3_zone_transition_diagnostics_enabled = true" in headless


def test_fixture_expected_count_matches_and_fails_closed():
    declared = int(re.search(r"const EXPECTED_TESTS: int = (\d+)", FIXTURE).group(1))
    init_body = FIXTURE.split("func _init() -> void:", 1)[1].split("\n\n", 1)[0]
    called = re.findall(r"^\t(_test_\w+)\(\)", init_body, re.M)
    assert len(called) == declared, (len(called), declared)
    assert len(set(called)) == len(called)
    assert "_completed.size() != EXPECTED_TESTS" in FIXTURE
    assert "if _failed:" in FIXTURE


def test_fixture_covers_every_mandated_case():
    for name in ("_test_off_is_a_no_op",
                 "_test_seed_is_classified_and_is_never_a_transition",
                 "_test_birth_is_seen_across_a_step_boundary",
                 "_test_death_is_seen_across_a_step_boundary",
                 "_test_stable_present_and_stable_absent",
                 "_test_within_step_oscillation_is_merged_at_step_granularity",
                 "_test_predicates_diverge_and_none_is_authoritative",
                 "_test_room_added_and_removed_are_not_births_or_deaths",
                 "_test_cardinality_identities_hold",
                 "_test_negative_control_and_fail_closed"):
        assert "func %s(" % name in FIXTURE, name


def test_fixture_oscillation_case_is_realistic():
    # Projection never creates upper mass, so a realistic oscillation has the
    # layer appear BETWEEN calls. Encoding it inside a call would test the very
    # thing call granularity excludes.
    body = FIXTURE.split(
        "func _test_within_step_oscillation_is_merged_at_step_granularity", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    assert "_event(0, ABSENT, ABSENT)" in body
    assert "_event(0, BIG, BIG)" in body
    assert "BETWEEN call 1 and call 2" in body
