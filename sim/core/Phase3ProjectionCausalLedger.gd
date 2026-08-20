extends RefCounted

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
## and energy-without-mass checks. It is ZoneFireSolver's own epsilon, not a new
## tunable: see ZoneFireSolver.ZONE_MASS_EPS_KG.
const ZONE_MASS_EPS_KG: float = 1.0e-6

## A stage delta below this is not treated as material activity. Derived, not
## fitted: doubles carry ~1e-16 relative precision and a per-step stage sum
## chains a handful of operations, so 1e-12 kg is orders above the arithmetic
## noise and far below anything physical.
const MATERIAL_ACTIVITY_EPS: float = 1.0e-12

var enabled: bool = false

var _totals: Dictionary = {}
var _by_cause: Dictionary = {}
var _rooms: Dictionary = {}
var _timesteps: int = 0
var _room_steps: int = 0
var _static_gaps: Dictionary = {}
var _active_gaps: Dictionary = {}
var _unavailable: Dictionary = {}


func clear() -> void:
	_totals.clear()
	_by_cause.clear()
	_rooms.clear()
	_static_gaps.clear()
	_active_gaps.clear()
	_unavailable.clear()
	_timesteps = 0
	_room_steps = 0


func _bump(key: String, amount: float) -> void:
	_totals[key] = float(_totals.get(key, 0.0)) + amount


func _bump_int(key: String, amount: int) -> void:
	_totals[key] = int(_totals.get(key, 0)) + amount


func _room(room_id: int) -> Dictionary:
	var key: String = str(room_id)
	if not _rooms.has(key):
		_rooms[key] = {
			"room_id": room_id,
			"projection_call_count_total": 0,
			"projection_calls_per_room_step_max": 0,
			"room_steps_with_multiple_projection_calls_total": 0,
			# Signed net cancels opposite corrections; gross absolute does not.
			# Gross is projection CHURN, never a physical contribution.
			"upper_mass_correction_signed_net_kg_total": 0.0,
			"upper_mass_correction_gross_absolute_kg_total": 0.0,
			"lower_mass_correction_signed_net_kg_total": 0.0,
			"lower_mass_correction_gross_absolute_kg_total": 0.0,
			"upper_energy_correction_signed_net_kj_total": 0.0,
			"upper_energy_correction_gross_absolute_kj_total": 0.0,
			"lower_energy_correction_signed_net_kj_total": 0.0,
			"lower_energy_correction_gross_absolute_kj_total": 0.0,
			"thermal_cap_requested_kj_total": 0.0,
			"thermal_cap_accepted_kj_total": 0.0,
			"thermal_cap_rejected_kj_total": 0.0,
			"thermal_cap_bind_count_total": 0,
			"upper_zone_birth_count_total": 0,
			"upper_zone_death_count_total": 0,
			"energy_without_mass_count_total": 0,
			"nonfinite_state_count_total": 0,
		}
	return _rooms[key]


func _cause(cause: String) -> Dictionary:
	if not _by_cause.has(cause):
		_by_cause[cause] = {
			"cause": cause,
			"call_count_total": 0,
			# gross_absolute is projection churn: the volume of rewriting this
			# cause performed. It is NOT a physical contribution and NOT a source.
			"mass_gross_absolute_kg_total": 0.0,
			"mass_signed_net_kg_total": 0.0,
			"energy_gross_absolute_kj_total": 0.0,
			"energy_signed_net_kj_total": 0.0,
		}
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
	_timesteps += 1
	_bump_int("timesteps_total", 1)

	var calls_by_room: Dictionary = {}
	for raw in trace_events:
		var ev: Dictionary = raw
		var room_id: int = int(ev.get("room_id", -1))
		var cause: String = String(ev.get("cause", "unspecified"))
		var room: Dictionary = _room(room_id)
		var by_cause: Dictionary = _cause(cause)

		room["projection_call_count_total"] = \
				int(room["projection_call_count_total"]) + 1
		by_cause["call_count_total"] = int(by_cause["call_count_total"]) + 1
		_bump_int("projection_call_count_total", 1)
		var rk: String = str(room_id)
		calls_by_room[rk] = int(calls_by_room.get(rk, 0)) + 1

		var upper_cap_mass: float = float(ev.get("upper_cap_mass_delta_kg", 0.0))
		var lower_proj_mass: float = float(ev.get("lower_projection_mass_delta_kg", 0.0))
		var upper_cap_energy: float = float(ev.get("upper_cap_energy_delta_kj", 0.0))
		var lower_proj_energy: float = float(ev.get("lower_projection_energy_delta_kj", 0.0))
		room["upper_mass_correction_signed_net_kg_total"] = \
				float(room["upper_mass_correction_signed_net_kg_total"]) + upper_cap_mass
		room["upper_mass_correction_gross_absolute_kg_total"] = \
				float(room["upper_mass_correction_gross_absolute_kg_total"]) \
				+ absf(upper_cap_mass)
		room["lower_mass_correction_signed_net_kg_total"] = \
				float(room["lower_mass_correction_signed_net_kg_total"]) + lower_proj_mass
		room["lower_mass_correction_gross_absolute_kg_total"] = \
				float(room["lower_mass_correction_gross_absolute_kg_total"]) \
				+ absf(lower_proj_mass)
		room["upper_energy_correction_signed_net_kj_total"] = \
				float(room["upper_energy_correction_signed_net_kj_total"]) + upper_cap_energy
		room["upper_energy_correction_gross_absolute_kj_total"] = \
				float(room["upper_energy_correction_gross_absolute_kj_total"]) \
				+ absf(upper_cap_energy)
		room["lower_energy_correction_signed_net_kj_total"] = \
				float(room["lower_energy_correction_signed_net_kj_total"]) + lower_proj_energy
		room["lower_energy_correction_gross_absolute_kj_total"] = \
				float(room["lower_energy_correction_gross_absolute_kj_total"]) \
				+ absf(lower_proj_energy)

		var total_mass: float = float(ev.get("total_mass_delta_kg", 0.0))
		var total_energy: float = float(ev.get("total_energy_delta_kj", 0.0))
		by_cause["mass_signed_net_kg_total"] = \
				float(by_cause["mass_signed_net_kg_total"]) + total_mass
		by_cause["mass_gross_absolute_kg_total"] = \
				float(by_cause["mass_gross_absolute_kg_total"]) + absf(total_mass)
		by_cause["energy_signed_net_kj_total"] = \
				float(by_cause["energy_signed_net_kj_total"]) + total_energy
		by_cause["energy_gross_absolute_kj_total"] = \
				float(by_cause["energy_gross_absolute_kj_total"]) + absf(total_energy)

		# Thermal cap: a CAUSE, never a physical destination. Requested is the
		# energy the state carried before the cap; accepted is what survived;
		# rejected is the difference, and it goes nowhere.
		var requested_kj: float = float(ev.get("upper_energy_before_cap_kj", 0.0))
		var accepted_kj: float = requested_kj + upper_cap_energy
		var rejected_kj: float = requested_kj - accepted_kj
		room["thermal_cap_requested_kj_total"] = \
				float(room["thermal_cap_requested_kj_total"]) + requested_kj
		room["thermal_cap_accepted_kj_total"] = \
				float(room["thermal_cap_accepted_kj_total"]) + accepted_kj
		room["thermal_cap_rejected_kj_total"] = \
				float(room["thermal_cap_rejected_kj_total"]) + rejected_kj
		if absf(rejected_kj) > 0.0:
			room["thermal_cap_bind_count_total"] = \
					int(room["thermal_cap_bind_count_total"]) + 1

		_scan_invalid_states(room, ev)
		_scan_zone_transition(room, ev)

	# Per-room-step multiplicity. A room-step is one room in one timestep.
	var calls_this_timestep: int = 0
	for rk in calls_by_room.keys():
		var n: int = int(calls_by_room[rk])
		calls_this_timestep += n
		_room_steps += 1
		_bump_int("room_steps_total", 1)
		var room2: Dictionary = _rooms[rk]
		room2["projection_calls_per_room_step_max"] = maxi(
			int(room2["projection_calls_per_room_step_max"]), n
		)
		if n > 1:
			room2["room_steps_with_multiple_projection_calls_total"] = \
					int(room2["room_steps_with_multiple_projection_calls_total"]) + 1
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

	_accumulate_residuals(zone_diag)


func _scan_invalid_states(room: Dictionary, ev: Dictionary) -> void:
	## Fail-closed observation. Energy without mass is an INVALID state: it is
	## counted and reported, the state is NOT mutated and no sink is created.
	var post: Dictionary = ev.get("post", {})
	for zone in ["upper", "lower"]:
		var m: float = float(post.get("%s_gas_kg" % zone, 0.0))
		var e: float = float(post.get("%s_energy_kj" % zone, 0.0))
		if not is_finite(m) or not is_finite(e):
			room["nonfinite_state_count_total"] = \
					int(room["nonfinite_state_count_total"]) + 1
			continue
		if m <= ZONE_MASS_EPS_KG and absf(e) > 0.0:
			room["energy_without_mass_count_total"] = \
					int(room["energy_without_mass_count_total"]) + 1


func _scan_zone_transition(room: Dictionary, ev: Dictionary) -> void:
	var pre: Dictionary = ev.get("pre", {})
	var post: Dictionary = ev.get("post", {})
	var before: float = float(pre.get("upper_gas_kg", 0.0))
	var after: float = float(post.get("upper_gas_kg", 0.0))
	if before <= ZONE_MASS_EPS_KG and after > ZONE_MASS_EPS_KG:
		room["upper_zone_birth_count_total"] = \
				int(room["upper_zone_birth_count_total"]) + 1
	elif before > ZONE_MASS_EPS_KG and after <= ZONE_MASS_EPS_KG:
		room["upper_zone_death_count_total"] = \
				int(room["upper_zone_death_count_total"]) + 1


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
		"gross_absolute_meaning":
			"projection churn: the volume of rewriting performed."
			+ " NOT a physical contribution and NOT a source",
		"totals": _totals.duplicate(true),
		"by_cause": _by_cause.duplicate(true),
		"by_room": _rooms.duplicate(true),
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
