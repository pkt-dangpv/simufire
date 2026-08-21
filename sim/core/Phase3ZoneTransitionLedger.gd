extends RefCounted

## H3.2b1b: persistent zone transition ledger.
##
## It repairs a structural blindness in `Phase3ProjectionCausalLedger`, whose
## birth/death counters compare the `pre` and `post` snapshots of a SINGLE
## `project_room_state` call. Projection never creates upper mass, so the
## 0 -> present step happens outside the call and both snapshots already show the
## new regime. H3.2b1a measured the consequence: zero births reported against at
## least twenty-nine real ones.
##
## This ledger instead compares PERSISTENT room state across a boundary between
## two observations.
##
## STEP GRANULARITY IS PRIMARY. The observer is seeded before the first physical
## timestep and thereafter reads the same quantity at the same point at the end
## of every step, so the boundary is known exactly and never drifts.
##
## CALL GRANULARITY IS A NARROWER BOUND ONLY. It compares the `post` of a room's
## previous projection call against the `pre` of that room's next call, which is
## precisely the window in which some other subsystem wrote.
##
## NEITHER IS GROUND TRUTH. A regime that changes and changes back between two
## observations is invisible at that granularity: the step counter misses
## oscillation inside a step, and the call counter misses oscillation between two
## consecutive calls for the same room. Both are LOWER BOUNDS.
##
## NO CAUSE ATTRIBUTION, EVER. A transition seen at a call boundary was produced
## between the calls, by whatever wrote in that window -- not by the projection
## whose `pre` closes the interval. There is deliberately no per-cause breakdown
## anywhere in this file.
##
## A SEED IS NEVER A TRANSITION. The first observation of a room is classified
## once as initially present or initially absent. Counting it as a birth would
## inflate every room, since every room in the committed corpus starts one-zone.
##
## ROOM-SET CHANGES ARE THEIR OWN OUTCOME. A room that appears is `room_added`,
## not a birth; one that disappears is `room_removed`, not a death. Fabricating a
## transition out of a room-set change would invent a zone transition that never
## happened.
##
## FOUR PREDICATES, NONE AUTHORITATIVE. The codebase has no shared definition of
## an absent zone. Every counter set is emitted under four named predicates at
## once, and choosing one remains a blocker owned by H3.2b6.
##
## It observes. It writes no state, governs no physics, adds no CSV column, and
## does not depend on the H3.2b3 shadow, on the H3.2b2 primitive, or on the zone
## diagnostics.

## Presence predicates, reported simultaneously. NONE of these is authoritative;
## the divergence between them is the evidence H3.2b6 needs in order to choose.
const PREDICATE_STRICT_POSITIVE: String = "strict_positive"
const PREDICATE_LEDGER: String = "ledger"
const PREDICATE_PROJECTION: String = "projection"
const PREDICATE_FED_GATE: String = "fed_gate"

## Thresholds, each mirrored from the place that actually uses it.
##   strict_positive : Phase3ResidualProjection, the H3.2b2 primitive (M > 0)
##   ledger          : Phase3ProjectionCausalLedger.ZONE_MASS_EPS_KG
##   projection      : ZoneFireSolver.ZONE_MASS_EPS_KG
##   fed_gate        : ThermalSystem.gd:4553, the FED hypoxia gate
const PREDICATE_THRESHOLDS_KG: Dictionary = {
	PREDICATE_STRICT_POSITIVE: 0.0,
	PREDICATE_LEDGER: 1.0e-6,
	PREDICATE_PROJECTION: 1.0e-4,
	PREDICATE_FED_GATE: 0.1,
}

const GRANULARITY_STEP: String = "step"
const GRANULARITY_CALL: String = "call"

## Telemetry this ledger does not own. Call granularity needs the per-call trace;
## without it that half is declared ABSENT rather than reported as zero.
const REASON_TRACE_UNAVAILABLE: String = "projection_trace_unavailable"
const REASON_NOT_SEEDED: String = "observer_not_seeded_before_first_step"

var enabled: bool = false

var _totals: Dictionary = {}
var _by_room: Dictionary = {}
var _unavailable: Dictionary = {}
var _seeded: bool = false
var _steps_observed: int = 0
var _rooms_seeded: int = 0

## Last observed presence per predicate, per granularity, per room.
##   _last_step_presence[predicate][room_key] -> bool
##   _last_call_presence[predicate][room_key] -> bool
var _last_step_presence: Dictionary = {}
var _last_call_presence: Dictionary = {}


func clear() -> void:
	_totals.clear()
	_by_room.clear()
	_unavailable.clear()
	_last_step_presence.clear()
	_last_call_presence.clear()
	_seeded = false
	_steps_observed = 0
	_rooms_seeded = 0


func record_unavailable(reason: String) -> void:
	## Never cleared by later observation.
	if not enabled:
		return
	_unavailable[reason] = true


func data_available() -> bool:
	return _unavailable.is_empty()


func is_seeded() -> bool:
	return _seeded


func _predicates() -> Array:
	return [PREDICATE_STRICT_POSITIVE, PREDICATE_LEDGER,
			PREDICATE_PROJECTION, PREDICATE_FED_GATE]


func _present(upper_mass_kg: float, predicate: String) -> bool:
	return upper_mass_kg > float(PREDICATE_THRESHOLDS_KG[predicate])


func _counter_block() -> Dictionary:
	## Every counter exists from the start, so a reported zero is a measured zero
	## and never a missing key a reader has to interpret.
	return {
		# Seeding. These count ROOMS, not boundaries, and are never summed with
		# the transition classes below.
		"initial_present": 0,
		"initial_absent": 0,
		# Transition classes. These count OBSERVED BOUNDARIES.
		"birth": 0,
		"death": 0,
		"stable_present": 0,
		"stable_absent": 0,
		# Room-set changes. Counted as boundaries, never as birth or death.
		"room_added": 0,
		"room_removed": 0,
	}


func _bucket(granularity: String, predicate: String) -> Dictionary:
	var key: String = "%s:%s" % [granularity, predicate]
	if not _totals.has(key):
		_totals[key] = _counter_block()
	return _totals[key]


func _room_bucket(room_key: String, granularity: String, predicate: String) -> Dictionary:
	if not _by_room.has(room_key):
		_by_room[room_key] = {}
	var per_room: Dictionary = _by_room[room_key]
	var key: String = "%s:%s" % [granularity, predicate]
	if not per_room.has(key):
		per_room[key] = _counter_block()
	return per_room[key]


func _bump(granularity: String, predicate: String, room_key: String, field: String) -> void:
	var total: Dictionary = _bucket(granularity, predicate)
	total[field] = int(total[field]) + 1
	var per_room: Dictionary = _room_bucket(room_key, granularity, predicate)
	per_room[field] = int(per_room[field]) + 1


# --------------------------------------------------------------------------
# Seeding
# --------------------------------------------------------------------------

func seed(upper_mass_by_room: Dictionary) -> void:
	## Called ONCE, before the first physical timestep. Establishes the
	## predecessor every later boundary is measured against.
	##
	## A seed is a classification, never a transition. Without it the first
	## observation would either be discarded -- losing a real transition in step
	## one -- or counted as a birth from nothing, which would inflate every room
	## because every room in the committed corpus starts one-zone.
	if not enabled or _seeded:
		return
	_seeded = true
	_rooms_seeded = upper_mass_by_room.size()
	for predicate in _predicates():
		_last_step_presence[predicate] = {}
		_last_call_presence[predicate] = {}
		for room_key in upper_mass_by_room.keys():
			var present: bool = _present(float(upper_mass_by_room[room_key]), predicate)
			_last_step_presence[predicate][room_key] = present
			# Call granularity shares the same seed: the first call boundary is
			# measured against the same initial state.
			_last_call_presence[predicate][room_key] = present
			_bump(GRANULARITY_STEP, predicate, String(room_key),
				"initial_present" if present else "initial_absent")


# --------------------------------------------------------------------------
# Step granularity: the primary observation
# --------------------------------------------------------------------------

func observe_step(upper_mass_by_room: Dictionary) -> void:
	## Called once per `SimulationEngine.step()`, at the same point every time so
	## the boundary never drifts.
	if not enabled:
		return
	if not _seeded:
		# Observing without a predecessor cannot be classified. Fail closed
		# rather than invent a first transition.
		record_unavailable(REASON_NOT_SEEDED)
		return
	_steps_observed += 1
	for predicate in _predicates():
		_classify_boundary(GRANULARITY_STEP, predicate,
			_last_step_presence[predicate], upper_mass_by_room)


# --------------------------------------------------------------------------
# Call granularity: a narrower bound, never a cause attribution
# --------------------------------------------------------------------------

func observe_calls(trace_events: Array) -> void:
	## One physical timestep of the existing projection trace. For each room, the
	## boundary compared is the `post` of its previous call against the `pre` of
	## its next call -- the window in which some other subsystem wrote.
	##
	## No cause is recorded anywhere here, because the transition was not caused
	## by the projection that closes the interval.
	if not enabled or not _seeded:
		return
	for raw in trace_events:
		var event: Dictionary = raw
		var room_key: String = str(int(event.get("room_id", -1)))
		var pre: Dictionary = event.get("pre", {})
		var post: Dictionary = event.get("post", {})
		var pre_mass: float = float(pre.get("upper_gas_kg", 0.0))
		var post_mass: float = float(post.get("upper_gas_kg", 0.0))
		for predicate in _predicates():
			var last: Dictionary = _last_call_presence[predicate]
			var pre_present: bool = _present(pre_mass, predicate)
			if not last.has(room_key):
				# A room seen for the first time at call granularity: a room-set
				# change, not a birth.
				_bump(GRANULARITY_CALL, predicate, room_key, "room_added")
			else:
				_classify_pair(GRANULARITY_CALL, predicate, room_key,
					bool(last[room_key]), pre_present)
			# The interval closes at this call's `post`, which becomes the
			# predecessor for the next call's `pre`.
			last[room_key] = _present(post_mass, predicate)


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------

func _classify_boundary(
	granularity: String, predicate: String,
	last: Dictionary, upper_mass_by_room: Dictionary
) -> void:
	for room_key in upper_mass_by_room.keys():
		var key: String = String(room_key)
		var present: bool = _present(float(upper_mass_by_room[room_key]), predicate)
		if not last.has(key):
			# The room did not exist at the previous boundary. That is a
			# room-set change, never a birth.
			_bump(granularity, predicate, key, "room_added")
		else:
			_classify_pair(granularity, predicate, key, bool(last[key]), present)
		last[key] = present
	# A room that existed at the previous boundary and is now gone.
	for key in last.keys():
		if upper_mass_by_room.has(key):
			continue
		_bump(granularity, predicate, String(key), "room_removed")
		last.erase(key)


func _classify_pair(
	granularity: String, predicate: String, room_key: String,
	was_present: bool, is_present: bool
) -> void:
	if was_present and is_present:
		_bump(granularity, predicate, room_key, "stable_present")
	elif not was_present and not is_present:
		_bump(granularity, predicate, room_key, "stable_absent")
	elif is_present:
		_bump(granularity, predicate, room_key, "birth")
	else:
		_bump(granularity, predicate, room_key, "death")


# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

func _cardinality(granularity: String, predicate: String) -> Dictionary:
	## Two identities over two different populations, never summed together.
	var block: Dictionary = _bucket(granularity, predicate)
	var seeded: int = int(block["initial_present"]) + int(block["initial_absent"])
	var boundaries: int = (
		int(block["birth"]) + int(block["death"])
		+ int(block["stable_present"]) + int(block["stable_absent"])
		+ int(block["room_added"]) + int(block["room_removed"])
	)
	var out: Dictionary = {
		"initial_sum": seeded,
		"rooms_seeded": _rooms_seeded if granularity == GRANULARITY_STEP else 0,
		"initial_matches_rooms_seeded": (
			seeded == _rooms_seeded if granularity == GRANULARITY_STEP else null
		),
		"transition_observations": boundaries,
	}
	if granularity == GRANULARITY_STEP:
		# With a constant room set the boundary count reduces to rooms x steps.
		# That reduction is asserted only when the room set really was constant.
		var constant_room_set: bool = (
			int(block["room_added"]) == 0 and int(block["room_removed"]) == 0
		)
		out["room_set_constant"] = constant_room_set
		out["rooms_times_steps"] = _rooms_seeded * _steps_observed
		out["matches_rooms_times_steps"] = (
			boundaries == _rooms_seeded * _steps_observed if constant_room_set else null
		)
	return out


func summary() -> Dictionary:
	if not enabled:
		return {}
	var unavailable: Array[String] = []
	for reason in _unavailable.keys():
		unavailable.append(String(reason))
	unavailable.sort()

	var cardinality: Dictionary = {}
	for granularity in [GRANULARITY_STEP, GRANULARITY_CALL]:
		for predicate in _predicates():
			cardinality["%s:%s" % [granularity, predicate]] = \
					_cardinality(granularity, predicate)

	return {
		"seeded": _seeded,
		"rooms_seeded": _rooms_seeded,
		"steps_observed": _steps_observed,
		"data_available": unavailable.is_empty(),
		"unavailable_reason_codes": unavailable,
		"predicate_thresholds_kg": PREDICATE_THRESHOLDS_KG.duplicate(true),
		"authoritative_predicate": null,
		"predicate_note":
			"four presence predicates are reported simultaneously and NONE is"
			+ " authoritative. Choosing one is a blocker owned by H3.2b6.",
		"granularity_note":
			"step granularity is PRIMARY: the boundary is one engine step and is"
			+ " known exactly. call granularity is a strictly NARROWER BOUND"
			+ " only, comparing the previous call's post against the next call's"
			+ " pre for the same room. BOTH can miss a regime that changes and"
			+ " changes back between two observations, so both are lower bounds"
			+ " and neither is ground truth",
		"cause_attribution_note":
			"a transition observed at a call boundary was produced BETWEEN the"
			+ " calls by whatever wrote in that window, not by the projection"
			+ " that closes the interval, so no per-cause breakdown exists here",
		"seed_note":
			"a seed is a classification, never a transition. initial_present and"
			+ " initial_absent count ROOMS and are never summed with the"
			+ " transition classes, which count OBSERVED BOUNDARIES",
		"room_set_note":
			"a room appearing is room_added and one disappearing is"
			+ " room_removed. Neither is ever counted as a birth or a death:"
			+ " fabricating one would invent a zone transition that never happened",
		"cardinality": cardinality,
		"totals": _totals.duplicate(true),
		"by_room": _by_room.duplicate(true),
	}
