"""Structural contracts for the H3.2b3 read-only shadow comparison.

H3.2b3 measures what the legacy projection rewrites. It must never change what
the legacy projection writes. These contracts pin that, plus the properties the
brief required:

* an isolated flag, default off, that does NOT persistently mutate the H3.2b1
  flag -- turning the shadow on must not turn an H3.2b1 user into someone
  running the primitive, nor the reverse;
* no new instrumentation inside `ZoneFireSolver`: the shadow consumes the trace
  that already exists, so H3.2b1 is not duplicated;
* the primitive's output is never applied, never written to a room, never a
  fallback, and no shadow metric reaches a physics decision;
* pressure is labelled honestly -- legacy stores none, so the recomputation from
  the legacy post inventory is named as such and never fed back;
* gross churn and signed net stay separate, with net-exactly-zero explicit;
* the zone-presence predicate is reported, not chosen;
* the blind transition counters are neither repaired nor gated on.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SHADOW_PATH = ROOT / "sim/core/Phase3ResidualProjectionShadow.gd"
FIXTURE_PATH = ROOT / "tests/fixtures/phase3_h32b3_residual_projection_shadow.gd"
SHADOW = SHADOW_PATH.read_text(encoding="utf-8")
FIXTURE = FIXTURE_PATH.read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")


def _strip_comments(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


CODE = _strip_comments(SHADOW)


def _func(text: str, name: str) -> str:
    return text.split("func %s(" % name, 1)[1].split("\nfunc ", 1)[0]


# --------------------------------------------------------------------------
# Flag isolation
# --------------------------------------------------------------------------

def test_flag_is_new_isolated_and_defaults_off():
    assert "@export var phase3_residual_projection_shadow_enabled: bool = false" in ENGINE
    assert "var enabled: bool = false" in SHADOW


def test_the_shadow_flag_never_mutates_the_h32b1_flag():
    setter = ENGINE.split(
        "@export var phase3_residual_projection_shadow_enabled: bool = false", 1)[1]
    setter = setter.split("var _phase3_residual_projection_shadow", 1)[0]
    assert "phase3_projection_causal_diagnostics_enabled" not in setter
    # It enables only the solver's own diagnostic trace.
    assert "zone_fire_solver.projection_diagnostics_enabled = true" in setter


def test_the_h32b1_flag_never_enables_the_shadow():
    setter = ENGINE.split(
        "@export var phase3_projection_causal_diagnostics_enabled: bool = false", 1)[1]
    setter = setter.split("var _phase3_projection_causal_ledger", 1)[0]
    assert "residual_projection_shadow" not in setter


def test_the_shadow_hook_runs_after_the_causal_accumulator():
    # So H3.2b1 keeps its own "trace unavailable on the first step" semantics.
    assert ("_phase3_projection_causal_accumulate()\n"
            "\t_phase3_residual_projection_shadow_accumulate()") in ENGINE
    assert ENGINE.count("_phase3_residual_projection_shadow_accumulate()") == 2


def test_the_shadow_is_gated_off_first():
    hook = _func(ENGINE, "_phase3_residual_projection_shadow_accumulate")
    first = next(line.strip() for line in hook.splitlines()
                 if line.strip().startswith("if "))
    assert first.startswith("if not phase3_residual_projection_shadow_enabled")
    body = _func(SHADOW, "accumulate_step")
    guard = next(line.strip() for line in body.splitlines()
                 if line.strip().startswith("if "))
    assert guard == "if not enabled:"


def test_the_trace_is_cleared_per_step_for_the_shadow_too():
    # Without this the trace events would accumulate across steps and every
    # call would be counted many times over.
    body = _func(ENGINE, "_phase3_projection_diagnostics_active")
    assert "phase3_residual_projection_shadow_enabled" in body


# --------------------------------------------------------------------------
# No duplicated instrumentation
# --------------------------------------------------------------------------

def test_zone_fire_solver_gains_no_shadow_instrumentation():
    # The solver must not learn about the primitive or the shadow at all. The
    # word "shadow" already appears in unrelated pre-existing comments there,
    # so the ban is on the identifiers, not on the English word.
    for forbidden in ("Phase3ResidualProjectionShadow", "Phase3ResidualProjection",
                      "residual_projection"):
        assert forbidden not in SOLVER, forbidden


def test_the_shadow_consumes_the_existing_trace():
    hook = _func(ENGINE, "_phase3_residual_projection_shadow_accumulate")
    assert "zone_fire_solver.get_projection_trace_events()" in hook
    # The trace getter returns a duplicate and does not consume, so H3.2b1 and
    # H3.2b3 can both read it without interfering.
    getter = _func(SOLVER, "get_projection_trace_events")
    assert "_projection_trace_events.duplicate(true)" in getter
    assert "clear()" not in getter


def test_geometry_comes_from_the_building_because_the_trace_lacks_it():
    snapshot = _func(SOLVER, "_projection_state")
    for absent in ("floor_area", "height_m", "volume_m3"):
        assert absent not in snapshot, absent
    helper = _func(ENGINE, "_phase3_residual_projection_shadow_geometry")
    assert "building.get_rooms()" in helper
    assert "floor_area_m2()" in helper
    assert "room.height_m" in helper


# --------------------------------------------------------------------------
# Strictly passive
# --------------------------------------------------------------------------

def test_the_shadow_never_writes_room_state():
    body = CODE
    assert not re.search(r"\broom\.\w+ *=[^=]", body)
    assert "RoomModel" not in body
    assert "BuildingModel" not in body


def test_the_result_is_never_applied_or_used_as_a_fallback():
    for forbidden in ("fallback", "apply", "commit", "write_back", "restore"):
        assert forbidden not in CODE.lower(), forbidden
    assert '"shadow_applied": false' in SHADOW


def test_the_shadow_never_mutates_its_inputs():
    body = _func(SHADOW, "accumulate_step")
    for forbidden in ("event[", "pre[", "post[", "geometry["):
        assert ("%s\"" % forbidden) not in body.replace(" ", ""), forbidden
    # Only reads.
    assert "event.get(" in body and "pre.get(" in body and "post.get(" in body


def test_no_shadow_metric_governs_physics():
    for line in ENGINE.splitlines():
        stripped = line.strip()
        if "_phase3_residual_projection_shadow" not in stripped:
            continue
        if stripped.startswith("#"):
            continue
        assert not stripped.startswith("if _phase3_residual_projection_shadow"), stripped
        assert "clampf(" not in stripped, stripped
    for metric in ("residual_vs_legacy_lower_mass_signed_net_kg_total",
                   "presence_predicate_mismatch_total",
                   "canonical_pressure_from_legacy_post_pa_sum"):
        assert metric not in SOLVER, metric


def test_no_new_csv_column():
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "residual_projection_shadow" not in text
        assert "canonical_pressure_from_legacy_post" not in text


def test_the_summary_block_is_opt_in():
    assert 'summary["phase3_residual_projection_shadow"] = ' in ENGINE
    block = ENGINE.split('summary["phase3_residual_projection_shadow"]', 1)[0]
    assert block.rstrip().endswith(
        "if phase3_residual_projection_shadow_enabled:") or \
        "if phase3_residual_projection_shadow_enabled:" in block.splitlines()[-3]
    summary = _func(SHADOW, "summary")
    lines = [line.strip() for line in summary.splitlines()[1:] if line.strip()]
    assert lines[0] == "if not enabled:"
    assert lines[1] == "return {}"


# --------------------------------------------------------------------------
# Pressure labelling
# --------------------------------------------------------------------------

def test_nothing_is_called_a_legacy_pressure():
    assert "legacy_pressure" not in SHADOW
    # Legacy really does store none: the solver's snapshot has no pressure.
    snapshot = _func(SOLVER, "_projection_state")
    assert "pressure" not in snapshot


def test_the_two_pressures_are_named_distinctly():
    assert "canonical_pressure_pre_pa" in SHADOW
    assert "canonical_pressure_from_legacy_post_pa" in SHADOW
    assert '"pressure_label_note"' in _func(SHADOW, "summary")
    assert "NOT a pressure legacy" in SHADOW


def test_the_recomputation_is_never_fed_back_into_the_primitive():
    body = _func(SHADOW, "_accumulate_canonical_pressure_from_legacy_post")
    # It derives from the legacy post inventory and only records extremes/sums.
    assert "ResidualProjectionScript.derive(" in body
    assert "canonical_pressure_from_legacy_post_pa_sum" in body
    # Its result never becomes an input to the pre-state comparison.
    accumulate = _func(SHADOW, "accumulate_step")
    idx = accumulate.find("_accumulate_canonical_pressure_from_legacy_post(")
    assert idx != -1
    assert "canonical_pressure_from_legacy_post" not in accumulate[:idx]
    assert "never used as an input" in SHADOW or "not fed back" in SHADOW


def test_the_primitive_input_is_the_pre_state():
    body = _func(SHADOW, "accumulate_step")
    call = body.split("ResidualProjectionScript.derive(", 1)[1].split(")", 1)[0]
    for token in ("pre_upper_mass", "pre_upper_energy",
                  "pre_lower_mass", "pre_lower_energy"):
        assert token in call, token
    for forbidden in ("post_upper_mass", "post_lower_mass"):
        assert forbidden not in call, forbidden


# --------------------------------------------------------------------------
# Gross versus signed
# --------------------------------------------------------------------------

def test_gross_and_signed_are_kept_separate():
    block = _func(SHADOW, "_new_divergence_block")
    for quantity in ("residual_vs_legacy_upper_mass", "residual_vs_legacy_lower_mass",
                     "legacy_rewrite_upper_mass", "legacy_rewrite_lower_mass"):
        assert "%s_signed_net_kg_total" % quantity in block, quantity
        assert "%s_gross_absolute_kg_total" % quantity in block, quantity
    for quantity in ("residual_vs_legacy_upper_mass", "residual_vs_legacy_lower_mass"):
        assert "%s_max_absolute_kg" % quantity in block, quantity


def test_net_exactly_zero_is_explicit_and_never_divided_by():
    body = _func(SHADOW, "_net_status")
    assert "if signed_total == 0.0:" in body
    assert '"status": "net_exactly_zero"' in body
    assert '"gross_over_net": null' in body
    assert "gross_total / absf(signed_total)" in body


def test_gross_is_documented_as_churn():
    assert '"gross_absolute_meaning"' in _func(SHADOW, "summary")
    assert "NOT a physical contribution" in SHADOW


def test_both_directions_of_the_inventory_delta_are_exported():
    block = _func(SHADOW, "_new_divergence_block")
    assert "legacy_rewrite_lower_mass_signed_net_kg_total" in block
    assert "residual_vs_legacy_lower_mass_signed_net_kg_total" in block
    assert "legacy_rewrite      = post - pre" in SHADOW
    assert "residual_vs_legacy  = pre  - post" in SHADOW


# --------------------------------------------------------------------------
# Presence predicate: reported, not chosen
# --------------------------------------------------------------------------

def test_the_legacy_predicate_is_mirrored_not_invented():
    assert "const LEGACY_ZONE_MASS_EPS_KG: float = 1.0e-4" in SHADOW
    assert "const ZONE_MASS_EPS_KG: float = 0.0001" in SOLVER


def test_a_mismatch_is_counted_and_not_called_a_loss():
    body = _func(SHADOW, "_compare_presence")
    assert "presence_predicate_mismatch_%s_total" in body
    assert "never evidence that mass was lost" in body
    summary = _func(SHADOW, "summary")
    assert '"presence_predicate_note"' in summary
    assert "never evidence of lost mass" in SHADOW
    assert "blocker for H3.2b6" in SHADOW


def test_h32b3_does_not_choose_a_canonical_predicate():
    # No new threshold constant beyond the mirrored legacy one.
    constants = re.findall(r"^const (\w+)", SHADOW, re.M)
    for name in constants:
        assert name in {"LEGACY_ZONE_MASS_EPS_KG", "REASON_TRACE_UNAVAILABLE",
                        "REASON_GEOMETRY_UNAVAILABLE", "ResidualProjectionScript"}, name


def test_temperature_is_compared_only_where_both_models_have_the_zone():
    body = _func(SHADOW, "_compare_zone_temperature")
    assert 'if not bool(residual_zone.get("present", false)):' in body
    assert "if legacy_post_mass_kg <= LEGACY_ZONE_MASS_EPS_KG:" in body
    assert body.count("return") >= 2


# --------------------------------------------------------------------------
# Transitions stay untouched
# --------------------------------------------------------------------------

def test_the_blind_transition_counters_are_neither_repaired_nor_gated_on():
    # The shadow must not carry a transition counter of its own, and must not
    # read the engine's blind ones. Naming them in the note that says they are
    # unusable is required, not forbidden.
    block = _func(SHADOW, "_new_divergence_block")
    for forbidden in ("birth", "death", "transition"):
        assert forbidden not in block.lower(), forbidden
    accumulate = _func(SHADOW, "accumulate_step")
    for forbidden in ("birth", "death"):
        assert forbidden not in accumulate.lower(), forbidden
    assert '"transition_counter_note"' in _func(SHADOW, "summary")
    assert "known blind" in SHADOW
    assert "neither repaired" in SHADOW
    assert "H3.2b1a" in SHADOW


# --------------------------------------------------------------------------
# Fail closed
# --------------------------------------------------------------------------

def test_missing_telemetry_fails_closed():
    assert "const REASON_TRACE_UNAVAILABLE" in SHADOW
    assert "const REASON_GEOMETRY_UNAVAILABLE" in SHADOW
    summary = _func(SHADOW, "summary")
    assert '"data_available": unavailable.is_empty(),' in summary
    assert '"unavailable_reason_codes": unavailable,' in summary


def test_an_invalid_primitive_is_counted_and_nothing_is_substituted():
    body = _func(SHADOW, "accumulate_step")
    invalid = body.split('if not bool(residual.get("valid", false)):', 1)[1]
    invalid = invalid.split("room_block[\"primitive_valid_count_total\"]", 1)[0]
    assert "primitive_invalid_count_total" in invalid
    assert "_invalid_reasons[reason]" in invalid
    assert "continue" in invalid
    # No divergence is fabricated for a state that could not be evaluated.
    assert "residual_vs_legacy" not in invalid


def test_absent_and_zero_never_look_alike():
    # Every counter exists from the first step, so a zero is a measured zero
    # rather than a missing key a reader has to interpret.
    body = _func(SHADOW, "_ensure_totals")
    for key in ("primitive_invalid_count_total",
                "presence_predicate_mismatch_total",
                "canonical_pressure_from_legacy_post_invalid_count_total",
                "residual_vs_legacy_upper_temp_comparable_count_total"):
        assert key in body, key
    assert "Absence and zero must not look alike" in SHADOW
    assert "_ensure_totals()" in _func(SHADOW, "accumulate_step")


def test_every_exported_metric_is_cumulative():
    block = _func(SHADOW, "_new_divergence_block")
    exported = set(re.findall(r'"(\w+)":', block))
    for key in exported:
        if key.endswith("_step"):
            raise AssertionError("per-step key exported: %s" % key)


# --------------------------------------------------------------------------
# The fixture
# --------------------------------------------------------------------------

def test_fixture_expected_count_matches_the_tests_it_runs():
    declared = int(re.search(r"const EXPECTED_TESTS: int = (\d+)", FIXTURE).group(1))
    init_body = FIXTURE.split("func _init() -> void:", 1)[1].split("\n\n", 1)[0]
    called = re.findall(r"^\t(_test_\w+)\(\)", init_body, re.M)
    assert len(called) == declared, (len(called), declared)
    assert len(set(called)) == len(called)
    for name in called:
        assert "func %s(" % name in FIXTURE, name


def test_fixture_fails_closed():
    assert "_completed.size() != EXPECTED_TESTS" in FIXTURE
    assert "quit(1)" in FIXTURE
    assert "if _failed:" in FIXTURE


def test_fixture_covers_every_mandated_case():
    for name in ("_test_off_does_not_invoke_the_primitive",
                 "_test_legacy_and_residual_coincide",
                 "_test_legacy_rewrites_lower_mass_is_measured",
                 "_test_upper_absent",
                 "_test_lower_absent",
                 "_test_invalid_primitive_fails_closed_and_is_counted",
                 "_test_cause_is_preserved",
                 "_test_gross_and_signed_are_separated",
                 "_test_pressure_labels_are_correct",
                 "_test_presence_mismatch_is_visible",
                 "_test_shadow_writes_no_state",
                 "_test_negative_control_applying_the_result_would_be_detected"):
        assert "func %s(" % name in FIXTURE, name


def test_fixture_negative_control_shows_the_check_can_fail():
    body = FIXTURE.split(
        "func _test_negative_control_applying_the_result_would_be_detected", 1)[1]
    body = body.split("\nfunc ", 1)[0]
    assert "divergence != 0.0" in body
    assert "had the residual been applied, the divergence would read zero" in body


def test_fixture_touches_no_engine_or_room():
    preloads = re.findall(r'preload\("([^"]+)"\)', FIXTURE)
    assert set(preloads) == {
        "res://sim/core/Phase3ResidualProjectionShadow.gd",
        "res://sim/core/Phase3ResidualProjection.gd",
    }, preloads


# --------------------------------------------------------------------------
# Runner wiring
# --------------------------------------------------------------------------

def test_the_runner_exposes_the_flag():
    runner = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
    assert '"--phase3-residual-projection-shadow"' in runner
    headless = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
    assert 'parsed["phase3_residual_projection_shadow"] = true' in headless
    assert "engine.phase3_residual_projection_shadow_enabled = true" in headless


def test_zone_fire_solver_has_no_h32b3_specific_coupling():
    assert "Phase3ResidualProjectionShadow" not in SOLVER
    assert "phase3_residual_projection_shadow" not in SOLVER
    assert "projection_diagnostics_enabled" in SOLVER
