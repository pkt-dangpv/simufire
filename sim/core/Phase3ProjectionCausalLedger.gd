extends RefCounted

const TraceRecordScript = preload("res://sim/core/Phase3ProjectionTraceRecord.gd")

## H3.2b1: passive causal accumulator for two-zone projection.
##
## It instruments NOTHING itself. `ZoneFireSolver` already emits a full per-call
## projection trace (`get_projection_trace_events()`, populated at
## `ZoneFireSolver.gd:293`) carrying `pre`, `ensured`, `pre_geometry` and `post`
## snapshots plus the cap and lower-reconstruction deltas. This ledger only
## ACCUMULATES what that trace already reports, so `project_room_state` is not
## instrumented twice.
##
## Everything it exports is a cumulative `*_total`, because the committed cases
## log every 10 s while the engine steps far more often. Differencing a sub-step
## delta against an interval row is an error this programme has already made
## twice; cumulative accumulators are immune to it.
##
## It observes. It never repairs a state, never creates a sink, never governs
## physics, and never writes to a RoomModel.
##
## UNITS (corrected 2026-08-19). A "room-step" is one room within one physical
## timestep. A "timestep" is one call to `accumulate_step`, which the engine
## makes exactly once per `step(dt)`. Both boundaries are known, so both are
## measured and named unambiguously. An earlier issue reported a room-step count
## as if it were a timestep count.
##
## SIGN CONVENTION. Every term is a signed contribution to the state delta:
##     candidate_physical_residual = dState - sum(physical owners)
##     closure_inclusive_residual  = dState - sum(physical owners)
##                                          - sum(numerical corrections)
## so, identically:
##     candidate_physical_residual - closure_inclusive_residual
##         = sum(numerical corrections)
## That identity is a contract to verify, never an expectation about magnitude.

## Physical owner stages. `reconcile` and `projection_clamp` are NOT here: they
## are numerical closure, and counting them as attribution is exactly what makes
## the engine's own residual unable to fail.
const PHYSICAL_STAGES: Array[String] = [
	"oxygen_exchange", "combustion", "thermal", "suppression",
	"gas_exchange", "hvac", "other",
]
const CLOSURE_STAGES: Array[String] = ["reconcile", "projection_clamp"]

## STATIC instrumentation gaps: owners whose coverage is known to be absent or
## partial from reading the code. A static gap describes COVERAGE, not activity.
## It never means the path ran.
const STATIC_GAP_HVAC_UNOWNED: String = "hvac_mass_energy_unowned"
const STATIC_GAP_OTHER_CATCHALL: String = "other_stage_is_catchall"
const STATIC_GAP_SUPPRESSION_LOWER_DEAD: String = "suppression_lower_write_dead"
const STATIC_GAP_EXTERIOR_NOT_ZONAL: String = "exterior_removal_not_zonal"

## ACTIVE gaps: a static gap that has been OBSERVED to carry material activity in
## this run. Only these can invalidate a residual on evidence rather than on
## suspicion. A static gap with no observed activity leaves the residual
## structurally uncertain but not observably contaminated.
const ACTIVE_GAP_SUFFIX: String = "_observed_active"

## Telemetry this accumulator does not own. If either source is off the totals
## would be zero, and a zero meaning "not measured" is indistinguishable from a
## zero meaning "no correction". It therefore fails closed and says so.
const REASON_TRACE_UNAVAILABLE: String = "projection_trace_unavailable"
const REASON_ZONE_DIAG_UNAVAILABLE: String = "zone_stage_attribution_unavailable"

## A zone holding less mass than this is treated as absent for the birth/death
## and energy-without-mass checks.
##
## PROVENANCE CORRECTED 2026-08-21 (H3.2b1b). The comment here used to read "it is
## ZoneFireSolver's own epsilon, see ZoneFireSolver.ZONE_MASS_EPS_KG". That
## misattributed it: `ZoneFireSolver.ZONE_MASS_EPS_KG` is **1.0e-4**, while this
## constant is **1.0e-6**. They are two different thresholds belonging to two
## different components, and the value below has always been this ledger's own.
## The distinction matters because H3.2b1a's "at least 29 births" figure was
## produced with THIS threshold, so the H3.2b1b acceptance gate is tied to the
## `ledger` predicate and not to the `projection` one. Choosing a single canonical
## predicate remains a blocker owned by H3.2b6; see
## `sim/core/Phase3ZoneTransitionLedger.gd`, which reports four at once.
const ZONE_MASS_EPS_KG: float = 1.0e-6

## A stage delta below this is not treated as material activity. Derived, not
## fitted: doubles carry ~1e-16 relative precision and a per-step stage sum
## chains a handful of operations, so 1e-12 kg is orders above the arithmetic
## noise and far below anything physical.
const MATERIAL_ACTIVITY_EPS: float = 1.0e-12

enum CausalRoomMetric {
	ROOM_ID,
	PROJECTION_CALL_COUNT,
	PROJECTION_CALLS_PER_ROOM_STEP_MAX,
	ROOM_STEPS_WITH_MULTIPLE_CALLS,
	UPPER_MASS_SIGNED,
	UPPER_MASS_GROSS,
	LOWER_MASS_SIGNED,
	LOWER_MASS_GROSS,
	UPPER_ENERGY_SIGNED,
	UPPER_ENERGY_GROSS,
	LOWER_ENERGY_SIGNED,
	LOWER_ENERGY_GROSS,
	THERMAL_CAP_REQUESTED,
	THERMAL_CAP_ACCEPTED,
	THERMAL_CAP_REJECTED,
	THERMAL_CAP_BIND_COUNT,
	UPPER_ZONE_BIRTH_COUNT,
	UPPER_ZONE_DEATH_COUNT,
	WITHIN_CALL_UPPER_ZONE_BIRTH_COUNT,
	WITHIN_CALL_UPPER_ZONE_DEATH_COUNT,
	ENERGY_WITHOUT_MASS_COUNT,
	NONFINITE_STATE_COUNT,
	SIZE,
}

enum CausalCauseMetric {
	CALL_COUNT,
	MASS_GROSS,
	MASS_SIGNED,
	ENERGY_GROSS,
	ENERGY_SIGNED,
	SIZE,
}

var enabled: bool = false

var _totals: Dictionary = {}
var _by_cause: Dictionary = {}
var _rooms: Dictionary = {}
var _timesteps: int = 0
var _room_steps: int = 0
var _static_gaps: Dictionary = {}
var _active_gaps: Dictionary = {}
var _unavailable: Dictionary = {}
var _calls_by_room_step: Dictionary = {}


func clear() -> void:
	_totals.clear()
	_by_cause.clear()
	_rooms.clear()
	_static_gaps.clear()
	_active_gaps.clear()
	_unavailable.clear()
	_calls_by_room_step.clear()
	_timesteps = 0
	_room_steps = 0


func _bump(key: String, amount: float) -> void:
	_totals[key] = float(_totals.get(key, 0.0)) + amount


func _bump_int(key: String, amount: int) -> void:
	_totals[key] = int(_totals.get(key, 0)) + amount


func _room(room_id: int) -> Array:
	var key: String = str(room_id)
	if not _rooms.has(key):
		var block: Array = []
		block.resize(CausalRoomMetric.SIZE)
		block.fill(0.0)
		block[CausalRoomMetric.ROOM_ID] = room_id
		for index in [
			CausalRoomMetric.PROJECTION_CALL_COUNT,
			CausalRoomMetric.PROJECTION_CALLS_PER_ROOM_STEP_MAX,
			CausalRoomMetric.ROOM_STEPS_WITH_MULTIPLE_CALLS,
			CausalRoomMetric.THERMAL_CAP_BIND_COUNT,
			CausalRoomMetric.UPPER_ZONE_BIRTH_COUNT,
			CausalRoomMetric.UPPER_ZONE_DEATH_COUNT,
			CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_BIRTH_COUNT,
			CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_DEATH_COUNT,
			CausalRoomMetric.ENERGY_WITHOUT_MASS_COUNT,
			CausalRoomMetric.NONFINITE_STATE_COUNT,
		]:
			block[index] = 0
		_rooms[key] = block
	return _rooms[key]


func _cause(cause: String) -> Array:
	if not _by_cause.has(cause):
		var block: Array = []
		block.resize(CausalCauseMetric.SIZE)
		block.fill(0.0)
		block[CausalCauseMetric.CALL_COUNT] = 0
		_by_cause[cause] = block
	return _by_cause[cause]


func record_unavailable(reason: String) -> void:
	## Marks a telemetry dependency as absent. Never cleared by observation.
	if not enabled:
		return
	_unavailable[reason] = true


func record_static_gap(reason: String) -> void:
	## Declares an owner whose coverage is known to be absent or partial. This
	## describes COVERAGE only: it never implies the path executed.
	if not enabled:
		return
	_static_gaps[reason] = true


func _record_active_gap(reason: String) -> void:
	## Only called when the corresponding writer was OBSERVED to move material
	## mass or energy this step. Suspicion is never enough.
	_active_gaps[reason] = int(_active_gaps.get(reason, 0)) + 1


func data_available() -> bool:
	return _unavailable.is_empty()


func accumulate_step(trace_events: Array, zone_diag: Dictionary) -> void:
	## `trace_events` is one physical timestep of the existing projection trace.
	## `zone_diag` is one physical timestep of the existing per-stage attribution.
	## Both are read-only inputs; nothing here is written back.
	if not enabled:
		return
	begin_step()
	for raw in trace_events:
		var event: Array = raw if raw is Array else TraceRecordScript.from_dictionary(raw)
		accumulate_event(event)
	finish_step(zone_diag)


func begin_step() -> void:
	if not enabled:
		return
	_timesteps += 1
	_bump_int("timesteps_total", 1)
	_calls_by_room_step.clear()


func accumulate_event(event: Array) -> void:
	if not enabled:
		return
	var room_id: int = int(event[TraceRecordScript.Field.ROOM_ID])
	var cause: String = String(event[TraceRecordScript.Field.CAUSE])
	var room: Array = _room(room_id)
	var by_cause: Array = _cause(cause)

	room[CausalRoomMetric.PROJECTION_CALL_COUNT] = \
			int(room[CausalRoomMetric.PROJECTION_CALL_COUNT]) + 1
	by_cause[CausalCauseMetric.CALL_COUNT] = \
			int(by_cause[CausalCauseMetric.CALL_COUNT]) + 1
	_bump_int("projection_call_count_total", 1)
	var room_key: String = str(room_id)
	_calls_by_room_step[room_key] = int(_calls_by_room_step.get(room_key, 0)) + 1

	var upper_cap_mass: float = float(
		event[TraceRecordScript.Field.UPPER_CAP_MASS_DELTA_KG])
	var lower_proj_mass: float = float(
		event[TraceRecordScript.Field.LOWER_PROJECTION_MASS_DELTA_KG])
	var upper_cap_energy: float = float(
		event[TraceRecordScript.Field.UPPER_CAP_ENERGY_DELTA_KJ])
	var lower_proj_energy: float = float(
		event[TraceRecordScript.Field.LOWER_PROJECTION_ENERGY_DELTA_KJ])
	room[CausalRoomMetric.UPPER_MASS_SIGNED] = \
			float(room[CausalRoomMetric.UPPER_MASS_SIGNED]) + upper_cap_mass
	room[CausalRoomMetric.UPPER_MASS_GROSS] = \
			float(room[CausalRoomMetric.UPPER_MASS_GROSS]) + absf(upper_cap_mass)
	room[CausalRoomMetric.LOWER_MASS_SIGNED] = \
			float(room[CausalRoomMetric.LOWER_MASS_SIGNED]) + lower_proj_mass
	room[CausalRoomMetric.LOWER_MASS_GROSS] = \
			float(room[CausalRoomMetric.LOWER_MASS_GROSS]) + absf(lower_proj_mass)
	room[CausalRoomMetric.UPPER_ENERGY_SIGNED] = \
			float(room[CausalRoomMetric.UPPER_ENERGY_SIGNED]) + upper_cap_energy
	room[CausalRoomMetric.UPPER_ENERGY_GROSS] = \
			float(room[CausalRoomMetric.UPPER_ENERGY_GROSS]) + absf(upper_cap_energy)
	room[CausalRoomMetric.LOWER_ENERGY_SIGNED] = \
			float(room[CausalRoomMetric.LOWER_ENERGY_SIGNED]) + lower_proj_energy
	room[CausalRoomMetric.LOWER_ENERGY_GROSS] = \
			float(room[CausalRoomMetric.LOWER_ENERGY_GROSS]) + absf(lower_proj_energy)

	var total_mass: float = float(event[TraceRecordScript.Field.TOTAL_MASS_DELTA_KG])
	var total_energy: float = float(event[TraceRecordScript.Field.TOTAL_ENERGY_DELTA_KJ])
	by_cause[CausalCauseMetric.MASS_SIGNED] = \
			float(by_cause[CausalCauseMetric.MASS_SIGNED]) + total_mass
	by_cause[CausalCauseMetric.MASS_GROSS] = \
			float(by_cause[CausalCauseMetric.MASS_GROSS]) + absf(total_mass)
	by_cause[CausalCauseMetric.ENERGY_SIGNED] = \
			float(by_cause[CausalCauseMetric.ENERGY_SIGNED]) + total_energy
	by_cause[CausalCauseMetric.ENERGY_GROSS] = \
			float(by_cause[CausalCauseMetric.ENERGY_GROSS]) + absf(total_energy)

	var requested_kj: float = float(
		event[TraceRecordScript.Field.UPPER_ENERGY_BEFORE_CAP_KJ])
	var accepted_kj: float = requested_kj + upper_cap_energy
	var rejected_kj: float = requested_kj - accepted_kj
	room[CausalRoomMetric.THERMAL_CAP_REQUESTED] = \
			float(room[CausalRoomMetric.THERMAL_CAP_REQUESTED]) + requested_kj
	room[CausalRoomMetric.THERMAL_CAP_ACCEPTED] = \
			float(room[CausalRoomMetric.THERMAL_CAP_ACCEPTED]) + accepted_kj
	room[CausalRoomMetric.THERMAL_CAP_REJECTED] = \
			float(room[CausalRoomMetric.THERMAL_CAP_REJECTED]) + rejected_kj
	if absf(rejected_kj) > 0.0:
		room[CausalRoomMetric.THERMAL_CAP_BIND_COUNT] = \
				int(room[CausalRoomMetric.THERMAL_CAP_BIND_COUNT]) + 1

	_scan_invalid_states(room, event)
	_scan_zone_transition(room, event)


func _finish_call_multiplicity() -> void:
	# Per-room-step multiplicity. A room-step is one room in one timestep.
	var calls_this_timestep: int = 0
	for rk in _calls_by_room_step.keys():
		var n: int = int(_calls_by_room_step[rk])
		calls_this_timestep += n
		_room_steps += 1
		_bump_int("room_steps_total", 1)
		var room2: Array = _rooms[rk]
		room2[CausalRoomMetric.PROJECTION_CALLS_PER_ROOM_STEP_MAX] = maxi(
			int(room2[CausalRoomMetric.PROJECTION_CALLS_PER_ROOM_STEP_MAX]), n
		)
		if n > 1:
			room2[CausalRoomMetric.ROOM_STEPS_WITH_MULTIPLE_CALLS] = \
					int(room2[CausalRoomMetric.ROOM_STEPS_WITH_MULTIPLE_CALLS]) + 1
			_bump_int("room_steps_with_multiple_projection_calls_total", 1)
		_totals["projection_calls_per_room_step_max"] = maxi(
			int(_totals.get("projection_calls_per_room_step_max", 0)), n
		)

	# Per physical timestep. The boundary is known -- this function is called
	# exactly once per engine step -- so these are measured, not approximated.
	_totals["projection_calls_per_timestep_max"] = maxi(
		int(_totals.get("projection_calls_per_timestep_max", 0)), calls_this_timestep
	)
	if calls_this_timestep > 1:
		_bump_int("timesteps_with_multiple_projection_calls_total", 1)
	if calls_this_timestep > 0:
		_bump_int("timesteps_with_any_projection_call_total", 1)


func finish_step(zone_diag: Dictionary) -> void:
	if not enabled:
		return
	_finish_call_multiplicity()

	_accumulate_residuals(zone_diag)


func accumulate_step_compact(
		trace_events: Array,
		zone_step: Dictionary,
		zone_start: Dictionary,
		zone_finish: Dictionary
	) -> void:
	## Engine-only hot path. The trace accumulation remains the public, tested
	## implementation above; an empty legacy attribution avoids serializing the
	## same stage arrays merely to read them back immediately.
	if not enabled:
		return
	begin_step()
	for raw in trace_events:
		var event: Array = raw if raw is Array else TraceRecordScript.from_dictionary(raw)
		accumulate_event(event)
	finish_step_compact(zone_step, zone_start, zone_finish)


func finish_step_compact(
		zone_step: Dictionary,
		zone_start: Dictionary,
		zone_finish: Dictionary
	) -> void:
	if not enabled:
		return
	_finish_call_multiplicity()
	_accumulate_residuals_compact(zone_step, zone_start, zone_finish)


func _scan_invalid_states(room: Array, ev: Array) -> void:
	## Fail-closed observation. Energy without mass is an INVALID state: it is
	## counted and reported, the state is NOT mutated and no sink is created.
	for fields in [
		[TraceRecordScript.Field.POST_UPPER_GAS_KG,
			TraceRecordScript.Field.POST_UPPER_ENERGY_KJ],
		[TraceRecordScript.Field.POST_LOWER_GAS_KG,
			TraceRecordScript.Field.POST_LOWER_ENERGY_KJ],
	]:
		var m: float = float(ev[int(fields[0])])
		var e: float = float(ev[int(fields[1])])
		if not is_finite(m) or not is_finite(e):
			room[CausalRoomMetric.NONFINITE_STATE_COUNT] = \
					int(room[CausalRoomMetric.NONFINITE_STATE_COUNT]) + 1
			continue
		if m <= ZONE_MASS_EPS_KG and absf(e) > 0.0:
			room[CausalRoomMetric.ENERGY_WITHOUT_MASS_COUNT] = \
					int(room[CausalRoomMetric.ENERGY_WITHOUT_MASS_COUNT]) + 1


func _scan_zone_transition(room: Array, ev: Array) -> void:
	var before: float = float(ev[TraceRecordScript.Field.PRE_UPPER_GAS_KG])
	var after: float = float(ev[TraceRecordScript.Field.POST_UPPER_GAS_KG])
	if before <= ZONE_MASS_EPS_KG and after > ZONE_MASS_EPS_KG:
		room[CausalRoomMetric.UPPER_ZONE_BIRTH_COUNT] = \
				int(room[CausalRoomMetric.UPPER_ZONE_BIRTH_COUNT]) + 1
		room[CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_BIRTH_COUNT] = \
				int(room[CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_BIRTH_COUNT]) + 1
	elif before > ZONE_MASS_EPS_KG and after <= ZONE_MASS_EPS_KG:
		room[CausalRoomMetric.UPPER_ZONE_DEATH_COUNT] = \
				int(room[CausalRoomMetric.UPPER_ZONE_DEATH_COUNT]) + 1
		room[CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_DEATH_COUNT] = \
				int(room[CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_DEATH_COUNT]) + 1


func _accumulate_residuals(zone_diag: Dictionary) -> void:
	## Both residuals are computed INDEPENDENTLY from the same per-step export,
	## never one from the other. Equality of the two residuals is a legitimate
	## outcome and is NOT treated as an instrumentation failure.
	##
	## The physical one is named CANDIDATE because it is only a conservation
	## measurement when every owner is present. When an owner is missing, the
	## number IS the missing owner rather than a residual.
	for room_key in zone_diag.keys():
		var d: Dictionary = zone_diag[room_key]
		var observed_mass: float = float(d.get("observed_mass_delta_kg", 0.0))
		var observed_energy: float = float(d.get("observed_energy_delta_kj", 0.0))
		var phys_mass: float = 0.0
		var phys_energy: float = 0.0
		for stage in PHYSICAL_STAGES:
			var sm: float = float(d.get(stage + "_mass_delta_kg_step", 0.0))
			var se: float = float(d.get(stage + "_energy_delta_kj_step", 0.0))
			phys_mass += sm
			phys_energy += se
			_note_active_gap(stage, sm, se)
		var clos_mass: float = 0.0
		var clos_energy: float = 0.0
		for stage in CLOSURE_STAGES:
			clos_mass += float(d.get(stage + "_mass_delta_kg_step", 0.0))
			clos_energy += float(d.get(stage + "_energy_delta_kj_step", 0.0))
		_bump("candidate_physical_residual_mass_kg_total", observed_mass - phys_mass)
		_bump("candidate_physical_residual_mass_gross_absolute_kg_total",
			absf(observed_mass - phys_mass))
		_bump("closure_inclusive_residual_mass_kg_total",
			observed_mass - phys_mass - clos_mass)
		_bump("candidate_physical_residual_energy_kj_total",
			observed_energy - phys_energy)
		_bump("closure_inclusive_residual_energy_kj_total",
			observed_energy - phys_energy - clos_energy)
		_bump("numerical_correction_mass_kg_total", clos_mass)
		_bump("numerical_correction_energy_kj_total", clos_energy)


func _accumulate_residuals_compact(
		zone_step: Dictionary,
		zone_start: Dictionary,
		zone_finish: Dictionary
	) -> void:
	## Compact layout owned by SimulationEngine:
	## state[0:2] = total mass/energy; step contains nine [mass, energy]
	## stage pairs in PHYSICAL_STAGES + CLOSURE_STAGES order.
	for room_key in zone_finish.keys():
		var finish: Array = zone_finish.get(room_key, [])
		var start: Array = zone_start.get(room_key, finish)
		if finish.size() < 2 or start.size() < 2:
			continue
		var step: Array = zone_step.get(room_key, [])
		var observed_mass: float = float(finish[0]) - float(start[0])
		var observed_energy: float = float(finish[1]) - float(start[1])
		var phys_mass: float = 0.0
		var phys_energy: float = 0.0
		for stage_index in range(PHYSICAL_STAGES.size()):
			var offset: int = stage_index * 2
			var stage_mass: float = float(step[offset]) if step.size() == 18 else 0.0
			var stage_energy: float = float(step[offset + 1]) if step.size() == 18 else 0.0
			phys_mass += stage_mass
			phys_energy += stage_energy
			_note_active_gap(PHYSICAL_STAGES[stage_index], stage_mass, stage_energy)
		var clos_mass: float = 0.0
		var clos_energy: float = 0.0
		for closure_index in range(CLOSURE_STAGES.size()):
			var offset: int = (PHYSICAL_STAGES.size() + closure_index) * 2
			if step.size() == 18:
				clos_mass += float(step[offset])
				clos_energy += float(step[offset + 1])
		_bump("candidate_physical_residual_mass_kg_total", observed_mass - phys_mass)
		_bump("candidate_physical_residual_mass_gross_absolute_kg_total",
			absf(observed_mass - phys_mass))
		_bump("closure_inclusive_residual_mass_kg_total",
			observed_mass - phys_mass - clos_mass)
		_bump("candidate_physical_residual_energy_kj_total",
			observed_energy - phys_energy)
		_bump("closure_inclusive_residual_energy_kj_total",
			observed_energy - phys_energy - clos_energy)
		_bump("numerical_correction_mass_kg_total", clos_mass)
		_bump("numerical_correction_energy_kj_total", clos_energy)


func _note_active_gap(stage: String, mass_delta: float, energy_delta: float) -> void:
	## A static gap becomes ACTIVE only when its writer actually moved material
	## mass or energy. Knowing the code exists is never enough.
	var material: bool = absf(mass_delta) > MATERIAL_ACTIVITY_EPS \
			or absf(energy_delta) > MATERIAL_ACTIVITY_EPS
	if not material:
		return
	if stage == "hvac" and _static_gaps.has(STATIC_GAP_HVAC_UNOWNED):
		_record_active_gap(STATIC_GAP_HVAC_UNOWNED + ACTIVE_GAP_SUFFIX)
	elif stage == "other" and _static_gaps.has(STATIC_GAP_OTHER_CATCHALL):
		_record_active_gap(STATIC_GAP_OTHER_CATCHALL + ACTIVE_GAP_SUFFIX)
	elif stage == "suppression" and _static_gaps.has(STATIC_GAP_SUPPRESSION_LOWER_DEAD):
		_record_active_gap(STATIC_GAP_SUPPRESSION_LOWER_DEAD + ACTIVE_GAP_SUFFIX)


func _room_dictionary(block: Array) -> Dictionary:
	return {
		"room_id": int(block[CausalRoomMetric.ROOM_ID]),
		"projection_call_count_total": int(block[CausalRoomMetric.PROJECTION_CALL_COUNT]),
		"projection_calls_per_room_step_max": int(
			block[CausalRoomMetric.PROJECTION_CALLS_PER_ROOM_STEP_MAX]),
		"room_steps_with_multiple_projection_calls_total": int(
			block[CausalRoomMetric.ROOM_STEPS_WITH_MULTIPLE_CALLS]),
		"upper_mass_correction_signed_net_kg_total": float(
			block[CausalRoomMetric.UPPER_MASS_SIGNED]),
		"upper_mass_correction_gross_absolute_kg_total": float(
			block[CausalRoomMetric.UPPER_MASS_GROSS]),
		"lower_mass_correction_signed_net_kg_total": float(
			block[CausalRoomMetric.LOWER_MASS_SIGNED]),
		"lower_mass_correction_gross_absolute_kg_total": float(
			block[CausalRoomMetric.LOWER_MASS_GROSS]),
		"upper_energy_correction_signed_net_kj_total": float(
			block[CausalRoomMetric.UPPER_ENERGY_SIGNED]),
		"upper_energy_correction_gross_absolute_kj_total": float(
			block[CausalRoomMetric.UPPER_ENERGY_GROSS]),
		"lower_energy_correction_signed_net_kj_total": float(
			block[CausalRoomMetric.LOWER_ENERGY_SIGNED]),
		"lower_energy_correction_gross_absolute_kj_total": float(
			block[CausalRoomMetric.LOWER_ENERGY_GROSS]),
		"thermal_cap_requested_kj_total": float(
			block[CausalRoomMetric.THERMAL_CAP_REQUESTED]),
		"thermal_cap_accepted_kj_total": float(
			block[CausalRoomMetric.THERMAL_CAP_ACCEPTED]),
		"thermal_cap_rejected_kj_total": float(
			block[CausalRoomMetric.THERMAL_CAP_REJECTED]),
		"thermal_cap_bind_count_total": int(
			block[CausalRoomMetric.THERMAL_CAP_BIND_COUNT]),
		"upper_zone_birth_count_total": int(
			block[CausalRoomMetric.UPPER_ZONE_BIRTH_COUNT]),
		"upper_zone_death_count_total": int(
			block[CausalRoomMetric.UPPER_ZONE_DEATH_COUNT]),
		"within_projection_call_upper_zone_birth_count_total": int(
			block[CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_BIRTH_COUNT]),
		"within_projection_call_upper_zone_death_count_total": int(
			block[CausalRoomMetric.WITHIN_CALL_UPPER_ZONE_DEATH_COUNT]),
		"energy_without_mass_count_total": int(
			block[CausalRoomMetric.ENERGY_WITHOUT_MASS_COUNT]),
		"nonfinite_state_count_total": int(
			block[CausalRoomMetric.NONFINITE_STATE_COUNT]),
	}


func _cause_dictionary(cause: String, block: Array) -> Dictionary:
	return {
		"cause": cause,
		"call_count_total": int(block[CausalCauseMetric.CALL_COUNT]),
		"mass_gross_absolute_kg_total": float(block[CausalCauseMetric.MASS_GROSS]),
		"mass_signed_net_kg_total": float(block[CausalCauseMetric.MASS_SIGNED]),
		"energy_gross_absolute_kj_total": float(block[CausalCauseMetric.ENERGY_GROSS]),
		"energy_signed_net_kj_total": float(block[CausalCauseMetric.ENERGY_SIGNED]),
	}


func summary() -> Dictionary:
	if not enabled:
		return {}
	var unavailable: Array[String] = []
	for u in _unavailable.keys():
		unavailable.append(String(u))
	unavailable.sort()
	var static_gaps: Array[String] = []
	for s in _static_gaps.keys():
		static_gaps.append(String(s))
	static_gaps.sort()
	var active_gaps: Array[String] = []
	for a in _active_gaps.keys():
		active_gaps.append(String(a))
	active_gaps.sort()

	var available: bool = unavailable.is_empty()
	# Structural coverage: every declared static gap must have been closed by a
	# real owner, not merely observed to be quiet this run.
	var structural_coverage: bool = static_gaps.is_empty()
	var valid: bool = available and active_gaps.is_empty() and structural_coverage
	var by_room: Dictionary = {}
	for room_key in _rooms.keys():
		by_room[room_key] = _room_dictionary(_rooms[room_key])
	var by_cause: Dictionary = {}
	for cause in _by_cause.keys():
		by_cause[cause] = _cause_dictionary(String(cause), _by_cause[cause])

	var out: Dictionary = {
		# Units, named unambiguously. A room-step is one room in one timestep.
		"timesteps_total": _timesteps,
		"room_steps_total": _room_steps,
		# Fail closed: a missing dependency is reported, never rendered as zero.
		"data_available": available,
		"unavailable_reason_codes": unavailable,
		# Coverage known from reading the code. Describes COVERAGE, not activity.
		"static_instrumentation_gap_reason_codes": static_gaps,
		# Only incremented when the corresponding writer moved material mass or
		# energy in this run.
		"observed_active_gap_reason_codes": active_gaps,
		"observed_active_gap_counts": _active_gaps.duplicate(true),
		"structural_coverage_complete": structural_coverage,
		"residual_physical_valid": valid,
		"physical_residual_label": (
			"physical_residual" if valid else "candidate_incomplete_physical_residual"
		),
		"residual_relation_contract":
			"candidate_physical_residual - closure_inclusive_residual"
			+ " = numerical_correction",
		"sign_convention":
			"every term is a signed contribution to the state delta",
		"deprecated_counter_note":
			"upper_zone_birth_count_total and upper_zone_death_count_total are"
			+ " DEPRECATED aliases kept for compatibility. They compare pre and post"
			+ " within ONE projection call, so they are near-always zero by"
			+ " construction and cannot witness a birth. The counters with meaning"
			+ " live in Phase3ZoneTransitionLedger (H3.2b1b), which compares"
			+ " persistent state across observation boundaries",
		"gross_absolute_meaning":
			"projection churn: the volume of rewriting performed."
			+ " NOT a physical contribution and NOT a source",
		"totals": _totals.duplicate(true),
		"by_cause": by_cause,
		"by_room": by_room,
	}
	var rp_m: float = float(_totals.get("candidate_physical_residual_mass_kg_total", 0.0))
	var rc_m: float = float(_totals.get("closure_inclusive_residual_mass_kg_total", 0.0))
	var nc_m: float = float(_totals.get("numerical_correction_mass_kg_total", 0.0))
	var rp_e: float = float(_totals.get("candidate_physical_residual_energy_kj_total", 0.0))
	var rc_e: float = float(_totals.get("closure_inclusive_residual_energy_kj_total", 0.0))
	var nc_e: float = float(_totals.get("numerical_correction_energy_kj_total", 0.0))
	out["residual_relation_mass_error_kg"] = (rp_m - rc_m) - nc_m
	out["residual_relation_energy_error_kj"] = (rp_e - rc_e) - nc_e
	return out
