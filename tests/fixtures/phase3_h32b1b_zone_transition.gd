extends SceneTree

## H3.2b1b fixture: persistent zone transition ledger.
##
## It preloads the ledger and the engine (so a parse error in either fails HERE)
## and nothing else. The ledger takes plain dictionaries of room mass, which is
## exactly why it cannot write state.

const LedgerScript = preload("res://sim/core/Phase3ZoneTransitionLedger.gd")
const SimulationEngineScript = preload("res://sim/core/SimulationEngine.gd")

const EXPECTED_TESTS: int = 11

## Above `fed_gate` (0.1), so present under all four predicates.
const BIG: float = 5.0
## Between `ledger` (1e-6) and `projection` (1e-4): present to strict_positive
## and ledger, absent to projection and fed_gate.
const TINY: float = 5.0e-5
const ABSENT: float = 0.0

var _failed: bool = false
var _completed: Array[String] = []


func _done(label: String) -> void:
	_completed.append(label)


func _init() -> void:
	_test_off_is_a_no_op()
	_test_seed_is_classified_and_is_never_a_transition()
	_test_birth_is_seen_across_a_step_boundary()
	_test_death_is_seen_across_a_step_boundary()
	_test_stable_present_and_stable_absent()
	_test_within_step_oscillation_is_merged_at_step_granularity()
	_test_call_granularity_narrows_the_bound_and_names_no_cause()
	_test_predicates_diverge_and_none_is_authoritative()
	_test_room_added_and_removed_are_not_births_or_deaths()
	_test_cardinality_identities_hold()
	_test_negative_control_and_fail_closed()
	if _completed.size() != EXPECTED_TESTS:
		push_error("H3.2b1b ABORTED: %d/%d completed; ran %s"
			% [_completed.size(), EXPECTED_TESTS, str(_completed)])
		quit(1)
		return
	if _failed:
		quit(1)
		return
	print("PHASE3_H32B1B_ZONE_TRANSITION_PASS")
	quit(0)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _ledger(on: bool = true):
	var l = LedgerScript.new()
	l.enabled = on
	return l


func _snap(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in values.keys():
		out[str(key)] = float(values[key])
	return out


func _step_block(summary: Dictionary, predicate: String) -> Dictionary:
	return summary["totals"]["step:%s" % predicate]


func _call_block(summary: Dictionary, predicate: String) -> Dictionary:
	return summary["totals"]["call:%s" % predicate]


func _event(room_id: int, pre_mass: float, post_mass: float) -> Dictionary:
	return {
		"room_id": room_id,
		"cause": "final_clamp_active",
		"pre": {"upper_gas_kg": pre_mass},
		"post": {"upper_gas_kg": post_mass},
	}


# --------------------------------------------------------------------------
# OFF
# --------------------------------------------------------------------------

func _test_off_is_a_no_op() -> void:
	var l = _ledger(false)
	l.seed(_snap({0: ABSENT}))
	l.observe_step(_snap({0: BIG}))
	l.observe_calls([_event(0, ABSENT, BIG)])
	_expect(l.summary().is_empty(), "with the flag off the summary does not exist")
	_expect(not l.is_seeded(), "and nothing was seeded")
	# Turning it on afterwards starts from nothing.
	l.enabled = true
	_expect(int(l.summary()["steps_observed"]) == 0,
		"no step was recorded while it was off")
	_done("off_no_op")


# --------------------------------------------------------------------------
# Seeding
# --------------------------------------------------------------------------

func _test_seed_is_classified_and_is_never_a_transition() -> void:
	var l = _ledger()
	l.seed(_snap({0: ABSENT, 1: BIG}))
	_expect(l.is_seeded(), "the ledger reports itself seeded")
	var s: Dictionary = l.summary()
	var block: Dictionary = _step_block(s, LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["initial_absent"]) == 1, "one room started absent")
	_expect(int(block["initial_present"]) == 1, "one room started present")
	for field in ["birth", "death", "stable_present", "stable_absent",
			"room_added", "room_removed"]:
		_expect(int(block[field]) == 0,
			"the seed produced no transition of any kind: %s" % field)
	_expect(int(s["rooms_seeded"]) == 2, "two rooms were seeded")
	_expect(int(s["steps_observed"]) == 0, "and no step has been observed yet")
	# Seeding twice must not double count.
	l.seed(_snap({0: ABSENT, 1: BIG}))
	_expect(int(_step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)["initial_absent"]) == 1,
		"seeding is idempotent")
	_done("seed_classified")


# --------------------------------------------------------------------------
# Transitions across a step boundary
# --------------------------------------------------------------------------

func _test_birth_is_seen_across_a_step_boundary() -> void:
	## The case the old within-call counter could never witness.
	var l = _ledger()
	l.seed(_snap({0: ABSENT}))
	l.observe_step(_snap({0: BIG}))
	var block: Dictionary = _step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["birth"]) == 1, "absent -> present across a step is a birth")
	_expect(int(block["death"]) == 0, "and not a death")
	_expect(int(block["stable_absent"]) == 0, "and not stable absence")
	_done("birth")


func _test_death_is_seen_across_a_step_boundary() -> void:
	var l = _ledger()
	l.seed(_snap({0: BIG}))
	l.observe_step(_snap({0: ABSENT}))
	var block: Dictionary = _step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["death"]) == 1, "present -> absent across a step is a death")
	_expect(int(block["birth"]) == 0, "and not a birth")
	_done("death")


func _test_stable_present_and_stable_absent() -> void:
	var l = _ledger()
	l.seed(_snap({0: BIG, 1: ABSENT}))
	l.observe_step(_snap({0: BIG, 1: ABSENT}))
	l.observe_step(_snap({0: BIG, 1: ABSENT}))
	var block: Dictionary = _step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["stable_present"]) == 2, "two stable-present boundaries")
	_expect(int(block["stable_absent"]) == 2, "two stable-absent boundaries")
	_expect(int(block["birth"]) == 0 and int(block["death"]) == 0,
		"and no transition was invented")
	_done("stable")


# --------------------------------------------------------------------------
# Granularity
# --------------------------------------------------------------------------

func _test_within_step_oscillation_is_merged_at_step_granularity() -> void:
	## A room that goes absent -> present -> absent inside one step looks stable
	## at step granularity. That is the documented limitation, not a bug: both
	## granularities are lower bounds.
	var l = _ledger()
	l.seed(_snap({0: ABSENT}))
	# Three calls in the same step. Projection never creates upper mass, so the
	# layer appears BETWEEN call 1 and call 2 (some other subsystem wrote) and is
	# gone again by call 3. Encoding the birth inside a call would test the very
	# thing call granularity deliberately excludes.
	l.observe_calls([
		_event(0, ABSENT, ABSENT),
		_event(0, BIG, BIG),
		_event(0, ABSENT, ABSENT),
	])
	l.observe_step(_snap({0: ABSENT}))
	var step_block: Dictionary = _step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	var call_block: Dictionary = _call_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(step_block["stable_absent"]) == 1,
		"the step boundary sees absent -> absent and reports stability")
	_expect(int(step_block["birth"]) == 0,
		"the step granularity misses the oscillation, as documented")
	_expect(int(call_block["birth"]) == 1,
		"the call granularity catches the birth the step boundary missed")
	_expect(int(call_block["death"]) == 1,
		"and the collapse that followed it")
	_expect(l.summary()["granularity_note"].contains("lower bounds"),
		"and the summary says both are lower bounds")
	_done("oscillation")


func _test_call_granularity_narrows_the_bound_and_names_no_cause() -> void:
	## The boundary compared is the PREVIOUS call's post against the NEXT call's
	## pre, which is the window in which another subsystem wrote.
	var l = _ledger()
	l.seed(_snap({0: ABSENT}))
	# Call 1 leaves the room absent. Between calls, something adds mass, so
	# call 2 arrives with the zone already present.
	l.observe_calls([_event(0, ABSENT, ABSENT), _event(0, BIG, BIG)])
	var block: Dictionary = _call_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["birth"]) == 1,
		"the transition between the two calls is caught")
	# No cause breakdown may exist anywhere.
	var s: Dictionary = l.summary()
	for key in s.keys():
		_expect(not String(key).contains("cause") or String(key).ends_with("_note"),
			"no per-cause breakdown is exported: %s" % key)
	_expect(s["cause_attribution_note"].contains("not by the projection"),
		"and the summary explains why attribution is refused")
	_done("call_granularity")


# --------------------------------------------------------------------------
# Predicates
# --------------------------------------------------------------------------

func _test_predicates_diverge_and_none_is_authoritative() -> void:
	## A zone parked at 5e-5 kg is present to strict_positive and ledger, and
	## absent to projection and fed_gate. The divergence is the point.
	var l = _ledger()
	l.seed(_snap({0: ABSENT}))
	l.observe_step(_snap({0: TINY}))
	var s: Dictionary = l.summary()
	_expect(int(_step_block(s, LedgerScript.PREDICATE_STRICT_POSITIVE)["birth"]) == 1,
		"strict_positive sees a birth at 5e-5 kg")
	_expect(int(_step_block(s, LedgerScript.PREDICATE_LEDGER)["birth"]) == 1,
		"the ledger predicate sees a birth at 5e-5 kg")
	_expect(int(_step_block(s, LedgerScript.PREDICATE_PROJECTION)["birth"]) == 0,
		"the projection predicate does not")
	_expect(int(_step_block(s, LedgerScript.PREDICATE_FED_GATE)["birth"]) == 0,
		"and neither does the FED gate")
	_expect(int(_step_block(s, LedgerScript.PREDICATE_FED_GATE)["stable_absent"]) == 1,
		"which reports stable absence instead")
	_expect(s["authoritative_predicate"] == null,
		"no predicate is declared authoritative")
	_expect(s["predicate_note"].contains("blocker owned by H3.2b6"),
		"and choosing one is recorded as H3.2b6's blocker")
	_expect(s["predicate_thresholds_kg"].size() == 4, "all four are reported")
	_done("predicates")


# --------------------------------------------------------------------------
# Room-set changes
# --------------------------------------------------------------------------

func _test_room_added_and_removed_are_not_births_or_deaths() -> void:
	var l = _ledger()
	l.seed(_snap({0: BIG}))
	# Room 1 appears holding an upper layer; room 0 stays.
	l.observe_step(_snap({0: BIG, 1: BIG}))
	var block: Dictionary = _step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["room_added"]) == 1, "the new room is room_added")
	_expect(int(block["birth"]) == 0,
		"a room appearing with a layer is NOT a birth")
	# Room 1 disappears again.
	l.observe_step(_snap({0: BIG}))
	block = _step_block(l.summary(), LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["room_removed"]) == 1, "the vanished room is room_removed")
	_expect(int(block["death"]) == 0,
		"a room disappearing is NOT a death")
	_expect(l.summary()["room_set_note"].contains("never"),
		"and the summary says so explicitly")
	_done("room_set")


# --------------------------------------------------------------------------
# Cardinality
# --------------------------------------------------------------------------

func _test_cardinality_identities_hold() -> void:
	## Two identities over two DIFFERENT populations, never summed together.
	var l = _ledger()
	l.seed(_snap({0: ABSENT, 1: BIG, 2: ABSENT}))
	l.observe_step(_snap({0: BIG, 1: BIG, 2: ABSENT}))
	l.observe_step(_snap({0: BIG, 1: ABSENT, 2: ABSENT}))
	l.observe_step(_snap({0: ABSENT, 1: ABSENT, 2: ABSENT}))
	var s: Dictionary = l.summary()
	for predicate in [LedgerScript.PREDICATE_STRICT_POSITIVE,
			LedgerScript.PREDICATE_LEDGER, LedgerScript.PREDICATE_PROJECTION,
			LedgerScript.PREDICATE_FED_GATE]:
		var card: Dictionary = s["cardinality"]["step:%s" % predicate]
		_expect(int(card["initial_sum"]) == 3,
			"initial classes account for the three seeded rooms (%s)" % predicate)
		_expect(bool(card["initial_matches_rooms_seeded"]),
			"and match rooms_seeded exactly (%s)" % predicate)
		_expect(int(card["transition_observations"]) == 9,
			"three rooms over three steps is nine observed boundaries (%s)" % predicate)
		_expect(bool(card["room_set_constant"]),
			"the room set was constant (%s)" % predicate)
		_expect(bool(card["matches_rooms_times_steps"]),
			"so boundaries reduce to rooms x steps (%s)" % predicate)
	# The two populations are never conflated.
	var block: Dictionary = _step_block(s, LedgerScript.PREDICATE_LEDGER)
	_expect(int(block["initial_present"]) + int(block["initial_absent"]) == 3,
		"initial counts rooms")
	_expect(int(block["birth"]) + int(block["death"])
			+ int(block["stable_present"]) + int(block["stable_absent"]) == 9,
		"transition classes count boundaries")
	_expect(s["seed_note"].contains("never summed"),
		"and the summary states they are never summed")
	_done("cardinality")


# --------------------------------------------------------------------------
# Negative control and fail-closed
# --------------------------------------------------------------------------

func _test_negative_control_and_fail_closed() -> void:
	## Observing without a seed cannot be classified, so it fails closed rather
	## than inventing a first transition.
	var unseeded = _ledger()
	unseeded.observe_step(_snap({0: BIG}))
	var s: Dictionary = unseeded.summary()
	_expect(not bool(s["data_available"]),
		"observing before seeding fails closed")
	_expect(s["unavailable_reason_codes"].has(LedgerScript.REASON_NOT_SEEDED),
		"and names the missing seed")
	_expect(int(s["steps_observed"]) == 0, "no boundary was classified")

	# Negative control: the counter must be able to report zero births for a
	# genuinely stable room, or the birth assertions above prove nothing.
	var stable = _ledger()
	stable.seed(_snap({0: BIG}))
	stable.observe_step(_snap({0: BIG}))
	_expect(int(_step_block(stable.summary(), LedgerScript.PREDICATE_LEDGER)["birth"]) == 0,
		"a stable room really does report zero births")

	# And the engine compiles with the flag defaulting off.
	var engine = SimulationEngineScript.new()
	_expect(not engine.phase3_zone_transition_diagnostics_enabled,
		"the engine flag defaults false")
	engine.phase3_zone_transition_diagnostics_enabled = true
	_expect(engine._phase3_projection_diagnostics_active(),
		"and is registered in the trace activation gate")
	_expect(not engine.phase3_residual_projection_shadow_enabled,
		"without turning on the H3.2b3 shadow")
	_expect(not engine.phase3_zone_diagnostics_enabled,
		"or the zone diagnostics")
	engine.free()
	_done("negative_control")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2b1b ASSERTION FAILED: %s" % label)
