"""Structural contracts for the H3.2b1 passive projection causal accumulator.

The accumulator instruments nothing itself: `ZoneFireSolver` already emits a
per-call projection trace, and the zone diagnostics already compute a per-stage
attribution. H3.2b1 only accumulates them, so `project_room_state` is never
instrumented twice. These contracts pin that, plus the properties the design
review insisted on:

* energy without mass is counted, never repaired and never routed to a sink;
* the thermal cap is a cause, not a physical destination;
* the two residuals are computed independently and are NOT required to differ;
* the physical residual is only called physical when it is valid; otherwise it
  is a `candidate_incomplete_physical_residual`;
* multiplicity is reported in unambiguous units -- room-steps and timesteps are
  different things and are named as such;
* `gross_absolute` is projection churn, not a physical contribution;
* static instrumentation gaps (coverage) are separate from observed active gaps
  (evidence of a writer actually moving material);
* missing telemetry fails closed instead of reporting zeros, never mutates
  physical state, and never reaches an engine decision.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LEDGER = (ROOT / "sim/core/Phase3ProjectionCausalLedger.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")


def _func(text: str, name: str) -> str:
    return text.split("func %s(" % name, 1)[1].split("\nfunc ", 1)[0]


def _strip_comments(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


def _standalone(name: str, text: str) -> bool:
    """True if `name` appears as a whole identifier, not as a suffix of one."""
    return re.search(r"(?<![A-Za-z0-9_])" + re.escape(name), text) is not None


# --------------------------------------------------------------------------
# Passive, additive, default OFF
# --------------------------------------------------------------------------

def test_flag_is_new_and_defaults_off():
    assert "@export var phase3_projection_causal_diagnostics_enabled: bool = false" in ENGINE
    assert "var enabled: bool = false" in LEDGER


def test_accumulator_is_gated_off_first():
    body = _func(LEDGER, "accumulate_step")
    statements = [
        line.strip() for line in body.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    guard = next(line for line in statements if line.startswith("if "))
    assert guard == "if not enabled:"
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert "if causal_active:" in hook


def test_project_room_state_is_not_instrumented_twice():
    # The ledger must consume the EXISTING trace, not add calls inside the solver.
    assert "peek_projection_trace_records()" in _func(
        ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert "Phase3ProjectionCausalLedger" not in SOLVER
    assert "phase3_projection_causal" not in SOLVER
    # And the trace emission owned by the solver is untouched.
    assert "_projection_trace_records.append(trace_record)" in SOLVER


def test_ledger_writes_no_room_state():
    body = _strip_comments(LEDGER)
    assert not re.search(r"\broom\.\w+ *=[^=]", body)
    assert "RoomModel" not in body
    # The one `room` identifier it uses is its own compact accumulator block.
    assert "func _room(room_id: int) -> Array:" in LEDGER


def test_no_sink_and_no_repair():
    body = _strip_comments(LEDGER).lower()
    for forbidden in ("sink", "repair", "clamp(", "fix_", "correct_state"):
        assert forbidden not in body, forbidden


# --------------------------------------------------------------------------
# Energy without mass fails closed
# --------------------------------------------------------------------------

def test_energy_without_mass_is_counted_not_mutated():
    body = _func(LEDGER, "_scan_invalid_states")
    assert "CausalRoomMetric.ENERGY_WITHOUT_MASS_COUNT" in body
    assert '"energy_without_mass_count_total"' in _func(LEDGER, "_room_dictionary")
    # It reads the post snapshot and writes only its own counters.
    assert not re.search(r"\bpost\[", body)
    assert "= 0.0" not in body        # nothing is zeroed
    stripped = _strip_comments(body)
    assert "sink" not in stripped.lower()


def test_nonfinite_state_is_counted_separately():
    body = _func(LEDGER, "_scan_invalid_states")
    assert "CausalRoomMetric.NONFINITE_STATE_COUNT" in body
    assert '"nonfinite_state_count_total"' in _func(LEDGER, "_room_dictionary")
    assert "is_finite(" in body


# --------------------------------------------------------------------------
# The thermal cap is a cause, not a destination
# --------------------------------------------------------------------------

def test_thermal_cap_records_requested_accepted_rejected():
    body = _func(LEDGER, "accumulate_step")
    for key in ("thermal_cap_requested_kj_total",
                "thermal_cap_accepted_kj_total",
                "thermal_cap_rejected_kj_total",
                "thermal_cap_bind_count_total"):
        assert key in body or key in LEDGER, key


def test_thermal_cap_has_no_physical_destination_field():
    for forbidden in ("thermal_cap_to_walls", "thermal_cap_to_ambient",
                      "thermal_cap_to_water", "thermal_cap_transferred"):
        assert forbidden not in LEDGER, forbidden


# --------------------------------------------------------------------------
# Residuals: independent, related by contract, not required to differ
# --------------------------------------------------------------------------

def test_residuals_are_computed_independently():
    body = _func(LEDGER, "_accumulate_residuals")
    # Each is built from observed minus its own owner sum, never one from the
    # other.
    assert "observed_mass - phys_mass)" in body
    assert "observed_mass - phys_mass - clos_mass" in body
    assert "candidate_physical_residual_mass_kg_total" in body
    assert "closure_inclusive_residual_mass_kg_total" in body


def test_equality_of_residuals_is_never_treated_as_a_failure():
    assert "Equality of the two residuals is a legitimate" in LEDGER
    # No assertion, guard or error path may key on the two being different.
    code = _strip_comments(_func(LEDGER, "_accumulate_residuals"))
    assert "!=" not in code


def test_physical_residual_is_named_candidate_until_it_is_valid():
    # An invalid residual must NOT be presented as a physical residual.
    summary = _func(LEDGER, "summary")
    assert '"physical_residual_label"' in summary
    assert '"candidate_incomplete_physical_residual"' in summary
    # The old unqualified accumulator names are gone entirely.
    for banned in ("residual_physical_mass_kg_total",
                   "residual_physical_energy_kj_total",
                   "residual_closure_mass_kg_total",
                   "residual_closure_energy_kj_total"):
        assert banned not in LEDGER, banned


def test_residual_relation_contract_and_sign_convention_are_exported():
    summary = _func(LEDGER, "summary")
    assert '"residual_relation_contract"' in summary
    assert "candidate_physical_residual - closure_inclusive_residual" in LEDGER
    assert '"sign_convention"' in summary
    assert "signed contribution to the state delta" in LEDGER
    assert '"residual_relation_mass_error_kg"' in summary
    assert '"residual_relation_energy_error_kj"' in summary


def test_numerical_correction_is_kept_as_its_own_observation():
    body = _func(LEDGER, "_accumulate_residuals")
    assert "numerical_correction_mass_kg_total" in body
    assert "numerical_correction_energy_kj_total" in body
    # It is the closure sum itself, not a difference between residuals.
    assert '_bump("numerical_correction_mass_kg_total", clos_mass)' in body


def test_validity_requires_data_no_active_gaps_and_structural_coverage():
    summary = _func(LEDGER, "summary")
    assert ("var valid: bool = available and active_gaps.is_empty() "
            "and structural_coverage") in LEDGER
    assert '"residual_physical_valid": valid,' in summary
    assert '"structural_coverage_complete"' in summary


def test_closure_stages_are_not_counted_as_physical_owners():
    assert 'const CLOSURE_STAGES: Array[String] = ["reconcile", "projection_clamp"]' in LEDGER
    phys = LEDGER.split("const PHYSICAL_STAGES", 1)[1].split("]", 1)[0]
    assert "reconcile" not in phys
    assert "projection_clamp" not in phys


# --------------------------------------------------------------------------
# Completeness: static coverage versus observed activity
# --------------------------------------------------------------------------

def test_static_and_active_gaps_are_separate():
    summary = _func(LEDGER, "summary")
    assert '"static_instrumentation_gap_reason_codes"' in summary
    assert '"observed_active_gap_reason_codes"' in summary
    assert '"observed_active_gap_counts"' in summary
    # A static gap describes coverage; it can never by itself imply activity.
    static_fn = _func(LEDGER, "record_static_gap")
    assert "_static_gaps[reason] = true" in static_fn
    assert "_active_gaps" not in static_fn
    # An active gap is only raised from observed material movement.
    note = _func(LEDGER, "_note_active_gap")
    assert "MATERIAL_ACTIVITY_EPS" in note
    assert "if not material:" in note
    assert "_record_active_gap(" in note


def test_material_activity_threshold_is_derived_not_fitted():
    assert "const MATERIAL_ACTIVITY_EPS: float = 1.0e-12" in LEDGER
    rationale = LEDGER.split("## A stage delta below this", 1)[1].split(
        "const MATERIAL_ACTIVITY_EPS", 1)[0]
    assert "1e-16" in rationale and "noise" in rationale


# --------------------------------------------------------------------------
# Activation: the causal flag alone must actually switch the trace on
# --------------------------------------------------------------------------

def test_the_causal_flag_is_in_the_trace_activation_gate():
    # REPAIRED 2026-08-20. `_sync_auxiliary_services()` reasserts
    # `projection_diagnostics_enabled` from this gate and runs repeatedly during
    # a session, so a flag missing from it has its trace switched back off at
    # every logging point. The causal flag was missing, which made
    # `--phase3-projection-causal-diagnostics` alone accumulate nothing.
    gate = _func(ENGINE, "_phase3_projection_diagnostics_active")
    assert "phase3_projection_causal_diagnostics_enabled" in gate
    assert "phase3_zone_diagnostics_enabled" in gate
    assert "phase3_runtime_ownership_ledger_enabled" in gate
    assert "phase3_residual_projection_shadow_enabled" in gate
    # And the gate really is what drives the solver flag.
    sync = _func(ENGINE, "_sync_auxiliary_services")
    assert ("zone_fire_solver.projection_diagnostics_enabled = "
            "_phase3_projection_diagnostics_active()") in sync


def test_the_causal_flag_still_activates_nothing_else():
    # The repair must not turn a causal user into a zone-diagnostics user (which
    # would change the shared CSV surface) or a shadow user (which would run the
    # primitive on every projection call).
    setter = ENGINE.split(
        "@export var phase3_projection_causal_diagnostics_enabled: bool = false", 1)[1]
    setter = setter.split("var _phase3_projection_causal_ledger", 1)[0]
    assert "phase3_zone_diagnostics_enabled = true" not in setter
    assert "phase3_residual_projection_shadow_enabled = true" not in setter
    assert "phase3_runtime_ownership_ledger_enabled = true" not in setter


def test_the_activation_repair_has_a_runtime_fixture():
    fixture = ROOT / "tests/fixtures/phase3_h32b1_causal_only_activation.gd"
    assert fixture.exists()
    text = fixture.read_text(encoding="utf-8")
    declared = int(re.search(r"const EXPECTED_TESTS: int = (\d+)", text).group(1))
    init_body = text.split("func _init() -> void:", 1)[1].split("\n\n", 1)[0]
    called = re.findall(r"^\t(_test_\w+)\(\)", init_body, re.M)
    assert len(called) == declared, (len(called), declared)
    assert "_completed.size() != EXPECTED_TESTS" in text
    # It must exercise the real solver trace, not a synthetic stand-in.
    assert "project_room_state(" in text
    assert "begin_projection_diagnostics_step()" in text
    # And it must not quietly repair the blind transition counters.
    assert "H3.2b1b" in text
    for forbidden in ("upper_zone_birth_count_total", "upper_zone_death_count_total"):
        assert forbidden not in text, forbidden


def test_static_gaps_are_declared_every_step_as_coverage_only():
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    for reason in ("STATIC_GAP_HVAC_UNOWNED", "STATIC_GAP_OTHER_CATCHALL",
                   "STATIC_GAP_SUPPRESSION_LOWER_DEAD",
                   "STATIC_GAP_EXTERIOR_NOT_ZONAL"):
        assert reason in hook, reason
    # The engine declares coverage. It never declares activity.
    assert "_record_active_gap" not in hook
    assert "record_static_gap" in hook


# --------------------------------------------------------------------------
# Multiplicity: units must be unambiguous
# --------------------------------------------------------------------------

def test_multiplicity_units_are_unambiguous():
    # A room-step is one room within one timestep. An earlier report stated a
    # room-step count as if it were a physical-step count.
    for key in ("projection_call_count_total",
                "projection_calls_per_room_step_max",
                "room_steps_with_multiple_projection_calls_total",
                "room_steps_total", "timesteps_total"):
        assert key in LEDGER, key
    # The ambiguous names must not survive as standalone identifiers.
    for banned in ("projection_calls_per_step_max",
                   "steps_with_multiple_projection_calls_total"):
        assert not _standalone(banned, LEDGER), banned
    cause = _func(LEDGER, "_cause")
    assert "CausalCauseMetric.CALL_COUNT" in cause
    assert '"call_count_total"' in _func(LEDGER, "_cause_dictionary")


def test_per_timestep_metrics_exist_because_the_boundary_is_known():
    # `accumulate_step` is called exactly once per engine step, so the physical
    # timestep boundary IS known and these are measured, not approximated.
    for key in ("projection_calls_per_timestep_max",
                "timesteps_with_multiple_projection_calls_total",
                "timesteps_with_any_projection_call_total"):
        assert key in LEDGER, key
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert "finish_step_compact(" in hook
    # Declared once, invoked from exactly one site, once per tick.
    assert ENGINE.count("_phase3_projection_diagnostics_accumulate_shared()") == 2


def test_signed_net_and_gross_absolute_are_named_distinctly():
    room = _func(LEDGER, "_room_dictionary")
    for zone in ("upper", "lower"):
        for quantity, unit in (("mass", "kg"), ("energy", "kj")):
            for kind in ("signed_net", "gross_absolute"):
                key = f"{zone}_{quantity}_correction_{kind}_{unit}_total"
                assert key in room, key
    cause = _func(LEDGER, "_cause_dictionary")
    for key in ("mass_gross_absolute_kg_total", "mass_signed_net_kg_total",
                "energy_gross_absolute_kj_total", "energy_signed_net_kj_total",
                "call_count_total"):
        assert key in cause, key


def test_gross_is_documented_as_churn_not_a_physical_contribution():
    summary = _func(LEDGER, "summary")
    assert '"gross_absolute_meaning"' in summary
    assert "projection churn" in LEDGER
    assert "NOT a physical contribution and NOT a source" in LEDGER


def test_every_metric_is_cumulative():
    # A per-step scalar may exist inside the function, but nothing exported may
    # be a bare per-step delta: the CSV samples every 10 s.
    summary = _func(LEDGER, "summary")
    room = _func(LEDGER, "_room")
    exported = set(re.findall(r'"(\w+)":', room + summary))
    for key in exported:
        if key.endswith("_step"):
            raise AssertionError("per-step key exported: %s" % key)


# --------------------------------------------------------------------------
# Fail closed on missing telemetry
# --------------------------------------------------------------------------

def test_missing_telemetry_fails_closed_instead_of_reporting_zero():
    assert "const REASON_TRACE_UNAVAILABLE" in LEDGER
    assert "const REASON_ZONE_DIAG_UNAVAILABLE" in LEDGER
    summary = _func(LEDGER, "summary")
    assert '"data_available": available,' in summary
    assert '"unavailable_reason_codes": unavailable,' in summary
    assert "var available: bool = unavailable.is_empty()" in LEDGER
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert "REASON_ZONE_DIAG_UNAVAILABLE" in hook
    assert "if not phase3_zone_diagnostics_enabled:" in hook


def test_unavailability_is_never_cleared_by_later_observation():
    body = _func(LEDGER, "record_unavailable")
    assert "_unavailable[reason] = true" in body
    # Only clear() may reset it, and clear() is the explicit run reset.
    assert LEDGER.count("_unavailable.erase(") == 0


def test_summary_is_empty_when_disabled():
    summary = _func(LEDGER, "summary")
    # _func keeps the tail of the signature line, so skip it.
    lines = [line.strip() for line in summary.splitlines()[1:] if line.strip()]
    assert lines[0] == "if not enabled:"
    assert lines[1] == "return {}"


# --------------------------------------------------------------------------
# Nothing physical was touched
# --------------------------------------------------------------------------

def test_projection_clamp_cap_and_tick_order_are_untouched():
    # The three writes S0d6b0.2a identified must be exactly as they were.
    for line in (
        "room.upper_gas_kg = max_upper_mass_kg",
        "room.lower_gas_kg = maxf(0.0, target_lower_mass_kg)",
        "room.temp_upper_c = minf(room.temp_upper_raw_c, max_upper_temp_c)",
    ):
        assert line in SOLVER, line
    # The accumulation hook runs after the tick, before the carbon check, and
    # adds no stage of its own.
    #
    # UPDATED 2026-08-20 by H3.2b3. The causal accumulator is no longer the last
    # thing before the carbon check: the H3.2b3 shadow accumulator now runs
    # immediately after it. The physics tick order is unchanged -- what this
    # contract exists to protect -- so the assertion is tightened rather than
    # dropped: between the clamp stage and the carbon check there may be passive
    # accumulators and NOTHING else.
    between = ENGINE.split("_phase3_projection_diagnostics_accumulate_shared()\n", 1)[1]
    between = between.split("_check_carbon_balance()", 1)[0]
    allowed = {
        "# Evaluar el estado final del paso, incluyendo cualquier pérdida por clamp."
    }
    for line in between.splitlines():
        stripped = line.strip()
        if stripped:
            assert stripped in allowed, "new stage between clamp and carbon check: %s" % stripped
    hook = _func(ENGINE, "_phase3_projection_diagnostics_accumulate_shared")
    assert "_phase3_projection_causal_ledger.accumulate_event(event)" in hook


def test_no_new_csv_columns():
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "phase3_projection_causal" not in text
        assert "projection_calls_per_room_step_max" not in text
        assert "candidate_physical_residual" not in text


def test_telemetry_never_governs_physics():
    # The ledger is only ever read for reporting; no physics branch may consult
    # it, and no ledger metric may appear in an engine decision.
    for line in ENGINE.splitlines():
        stripped = line.strip()
        if "_phase3_projection_causal_ledger" not in stripped:
            continue
        if stripped.startswith("#"):
            continue
        assert not stripped.startswith("if _phase3_projection_causal_ledger"), stripped
        assert "clampf(" not in stripped, stripped
    for metric in ("candidate_physical_residual_mass_kg_total",
                   "closure_inclusive_residual_mass_kg_total",
                   "projection_calls_per_room_step_max",
                   "observed_active_gap_reason_codes"):
        assert metric not in ENGINE, metric
        assert metric not in SOLVER, metric
