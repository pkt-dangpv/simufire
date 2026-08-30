extends RefCounted

## H3.2b3: read-only shadow comparison of legacy projection against the H3.2b2
## pure primitive.
##
## It measures what the legacy path rewrites. It never changes what the legacy
## path writes. The primitive's output is computed, compared and discarded: it is
## never applied, never written to a RoomModel, never used as a fallback and
## never allowed to reach a physics decision.
##
## IT ADDS NO INSTRUMENTATION. `ZoneFireSolver.project_room_state()` already
## emits, per call, a single trace event carrying the `cause`, the `room_id`, the
## ambient temperature, and both the `pre` snapshot taken at entry and the `post`
## snapshot taken after the rewrite (`ZoneFireSolver.gd:291-300`). That one event
## is the single point that sees pre-state and post-state under the same cause,
## so no new hook inside the solver is needed and H3.2b1's instrumentation is not
## duplicated: `get_projection_trace_events()` returns a duplicate and does not
## consume, so both ledgers read the same events independently.
##
## GEOMETRY IS NOT IN THE TRACE. `_projection_state()` carries inventories,
## temperatures and the layer height, but no floor area and no room height. The
## caller therefore supplies geometry per room. That is sound because room
## geometry is assigned once at construction (`sim/BuildingModel.gd:641-643`) and
## is never mutated during a run, so the values resolved when this accumulator
## runs are the values that were in force during the call.
##
## THE COMPARISON.
##     A  pre-state   = the trace's `pre`: M_upper, E_upper, M_lower, E_lower,
##                      plus the room's geometry and the ambient temperature.
##     B  residual    = Phase3ResidualProjection.derive(A). The primitive returns
##                      M and E bit-identical to A, so B's inventories ARE A's.
##     C  legacy post = the trace's `post`, what the engine actually wrote.
## Every divergence below is therefore B versus C, and because B's inventories
## equal A's, the inventory divergence IS the legacy rewrite, seen from the other
## side. Both directions are exported explicitly so the sign convention can never
## be guessed:
##     legacy_rewrite      = post - pre      (what legacy changed)
##     residual_vs_legacy  = pre  - post     (residual minus legacy, since
##                                            residual == pre for M and E)
##
## PRESSURE LABELLING. Legacy projection has no pressure. It stores none and
## computes none: it scales a fixed reference density by an ambient/zone
## temperature ratio (`ZoneFireSolver.gd:257`, `:275`). Nothing here may be called
## "legacy pressure". Two pressures are exported and they are different things:
##   * `canonical_pressure_pre_pa`  -- the H3.2b2 equation of state applied to the
##     PRE-state. This is the primitive's own pressure and is a genuine output of
##     model B.
##   * `canonical_pressure_from_legacy_post_pa` -- the same H3.2b2 equation of
##     state applied to the LEGACY POST inventory. It is a recomputation, NOT a
##     pressure legacy produced. It is never fed back into the primitive, never
##     used as an input, and never used to close a residual.
##
## GROSS IS NOT A PHYSICAL CONTRIBUTION. As in H3.2b1, `gross_absolute` measures
## the volume of rewriting, `signed_net` measures what survives cancellation, and
## the two are never collapsed. A net of exactly zero is reported as such rather
## than divided by.
##
## ZONE PRESENCE. The primitive's predicate is `M > 0`. The legacy projection's
## is `M > ZoneFireSolver.ZONE_MASS_EPS_KG` (1.0e-4), and the engine as a whole
## carries seven different predicates. H3.2b3 does NOT choose a canonical one. It
## reports the mismatch count against the legacy projection predicate it is
## actually comparing, and records that choosing one is a blocker for H3.2b6. A
## mismatch is a definitional disagreement, never evidence of lost mass.
##
## ZONE TRANSITIONS. The runtime birth/death counters are known to be blind
## (H3.2b1a measured them missing at least 29 real births). This phase does not
## repair them, does not gate on them, and does not present their zeros as
## evidence of absence.

const ResidualProjectionScript = preload("res://sim/core/Phase3ResidualProjection.gd")
const TraceRecordScript = preload("res://sim/core/Phase3ProjectionTraceRecord.gd")

## The legacy projection's own presence predicate, mirrored from
## `ZoneFireSolver.ZONE_MASS_EPS_KG`. This is the predicate being compared; it is
## not a proposal for a canonical one.
const LEGACY_ZONE_MASS_EPS_KG: float = 1.0e-4

## Telemetry this accumulator does not own. Fails closed rather than reporting
## zeros, exactly as the H3.2b1 ledger does.
const REASON_TRACE_UNAVAILABLE: String = "projection_trace_unavailable"
const REASON_GEOMETRY_UNAVAILABLE: String = "room_geometry_unavailable"

enum BlockMetric {
	CALL_COUNT,
	PRIMITIVE_VALID_COUNT,
	PRIMITIVE_INVALID_COUNT,
	LEGACY_UPPER_MASS_SIGNED,
	LEGACY_UPPER_MASS_GROSS,
	LEGACY_LOWER_MASS_SIGNED,
	LEGACY_LOWER_MASS_GROSS,
	LEGACY_UPPER_ENERGY_SIGNED,
	LEGACY_UPPER_ENERGY_GROSS,
	LEGACY_LOWER_ENERGY_SIGNED,
	LEGACY_LOWER_ENERGY_GROSS,
	RESIDUAL_UPPER_MASS_SIGNED,
	RESIDUAL_UPPER_MASS_GROSS,
	RESIDUAL_UPPER_MASS_MAX,
	RESIDUAL_LOWER_MASS_SIGNED,
	RESIDUAL_LOWER_MASS_GROSS,
	RESIDUAL_LOWER_MASS_MAX,
	RESIDUAL_UPPER_ENERGY_SIGNED,
	RESIDUAL_UPPER_ENERGY_GROSS,
	RESIDUAL_UPPER_ENERGY_MAX,
	RESIDUAL_LOWER_ENERGY_SIGNED,
	RESIDUAL_LOWER_ENERGY_GROSS,
	RESIDUAL_LOWER_ENERGY_MAX,
	RESIDUAL_INTERFACE_SIGNED,
	RESIDUAL_INTERFACE_GROSS,
	RESIDUAL_INTERFACE_MAX,
	RESIDUAL_UPPER_VOLUME_SIGNED,
	RESIDUAL_UPPER_VOLUME_GROSS,
	RESIDUAL_UPPER_VOLUME_MAX,
	RESIDUAL_LOWER_VOLUME_SIGNED,
	RESIDUAL_LOWER_VOLUME_GROSS,
	RESIDUAL_LOWER_VOLUME_MAX,
	RESIDUAL_UPPER_TEMP_SIGNED,
	RESIDUAL_UPPER_TEMP_GROSS,
	RESIDUAL_UPPER_TEMP_MAX,
	RESIDUAL_UPPER_TEMP_COUNT,
	RESIDUAL_LOWER_TEMP_SIGNED,
	RESIDUAL_LOWER_TEMP_GROSS,
	RESIDUAL_LOWER_TEMP_MAX,
	RESIDUAL_LOWER_TEMP_COUNT,
	PRESENCE_MISMATCH_UPPER,
	PRESENCE_MISMATCH_LOWER,
	PRESENCE_MISMATCH_TOTAL,
	SIZE,
}

enum DeriveCache {
	UPPER_MASS_KG,
	UPPER_ENERGY_KJ,
	LOWER_MASS_KG,
	LOWER_ENERGY_KJ,
	FLOOR_AREA_M2,
	ROOM_HEIGHT_M,
	AMBIENT_C,
	RESULT,
	SIZE,
}

enum TotalMetric {
	TIMESTEPS,
	CALL_COUNT,
	PRIMITIVE_VALID_COUNT,
	PRIMITIVE_INVALID_COUNT,
	PRESENCE_MISMATCH_TOTAL,
	PRESENCE_MISMATCH_UPPER,
	PRESENCE_MISMATCH_LOWER,
	UPPER_TEMP_COMPARABLE_COUNT,
	LOWER_TEMP_COMPARABLE_COUNT,
	CANONICAL_PRE_PRESSURE_SUM,
	CANONICAL_PRE_PRESSURE_SAMPLE_COUNT,
	CANONICAL_PRE_PRESSURE_MIN,
	CANONICAL_PRE_PRESSURE_MAX,
	CANONICAL_POST_PRESSURE_SUM,
	CANONICAL_POST_PRESSURE_SAMPLE_COUNT,
	CANONICAL_POST_PRESSURE_INVALID_COUNT,
	CANONICAL_POST_PRESSURE_MIN,
	CANONICAL_POST_PRESSURE_MAX,
	SIZE,
}

var enabled: bool = false

var _totals: Array = []
var _by_cause: Dictionary = {}
var _rooms: Dictionary = {}
var _invalid_reasons: Dictionary = {}
var _unavailable: Dictionary = {}
var _timesteps: int = 0
var _derive_cache_by_room: Dictionary = {}
var _canonical_pre_pressure_has_sample: bool = false
var _canonical_post_pressure_has_sample: bool = false


func clear() -> void:
	_totals.clear()
	_by_cause.clear()
	_rooms.clear()
	_invalid_reasons.clear()
	_unavailable.clear()
	_derive_cache_by_room.clear()
	_timesteps = 0
	_canonical_pre_pressure_has_sample = false
	_canonical_post_pressure_has_sample = false


func record_unavailable(reason: String) -> void:
	## Never cleared by later observation.
	if not enabled:
		return
	_unavailable[reason] = true


func data_available() -> bool:
	return _unavailable.is_empty()


func _ensure_totals() -> void:
	## Every counter this accumulator can report exists from the first step, so
	## a zero is always an explicit measured zero and never an absent key that a
	## reader has to interpret. Absence and zero must not look alike.
	if _totals.size() == TotalMetric.SIZE:
		return
	_totals.resize(TotalMetric.SIZE)
	_totals.fill(0.0)
	for index in [
		TotalMetric.TIMESTEPS,
		TotalMetric.CALL_COUNT,
		TotalMetric.PRIMITIVE_VALID_COUNT,
		TotalMetric.PRIMITIVE_INVALID_COUNT,
		TotalMetric.PRESENCE_MISMATCH_TOTAL,
		TotalMetric.PRESENCE_MISMATCH_UPPER,
		TotalMetric.PRESENCE_MISMATCH_LOWER,
		TotalMetric.UPPER_TEMP_COMPARABLE_COUNT,
		TotalMetric.LOWER_TEMP_COMPARABLE_COUNT,
		TotalMetric.CANONICAL_PRE_PRESSURE_SAMPLE_COUNT,
		TotalMetric.CANONICAL_POST_PRESSURE_SAMPLE_COUNT,
		TotalMetric.CANONICAL_POST_PRESSURE_INVALID_COUNT,
	]:
		_totals[index] = 0


func _new_divergence_block() -> Array:
	var block: Array = []
	block.resize(BlockMetric.SIZE)
	block.fill(0.0)
	for index in [
		BlockMetric.CALL_COUNT,
		BlockMetric.PRIMITIVE_VALID_COUNT,
		BlockMetric.PRIMITIVE_INVALID_COUNT,
		BlockMetric.RESIDUAL_UPPER_TEMP_COUNT,
		BlockMetric.RESIDUAL_LOWER_TEMP_COUNT,
		BlockMetric.PRESENCE_MISMATCH_UPPER,
		BlockMetric.PRESENCE_MISMATCH_LOWER,
		BlockMetric.PRESENCE_MISMATCH_TOTAL,
	]:
		block[index] = 0
	return block


func _room(room_id: int) -> Array:
	var key: String = str(room_id)
	if not _rooms.has(key):
		_rooms[key] = _new_divergence_block()
	return _rooms[key]


func _cause(cause: String) -> Array:
	if not _by_cause.has(cause):
		_by_cause[cause] = _new_divergence_block()
	return _by_cause[cause]


func _accumulate_signed_gross_max(
	first: Array, second: Array,
	signed_index: int, gross_index: int, max_index: int, value: float
) -> void:
	var magnitude: float = absf(value)
	first[signed_index] = float(first[signed_index]) + value
	first[gross_index] = float(first[gross_index]) + magnitude
	second[signed_index] = float(second[signed_index]) + value
	second[gross_index] = float(second[gross_index]) + magnitude
	if max_index >= 0:
		first[max_index] = maxf(float(first[max_index]), magnitude)
		second[max_index] = maxf(float(second[max_index]), magnitude)


func _derive_cached(
	room_id: int,
	upper_mass_kg: float,
	upper_energy_kj: float,
	lower_mass_kg: float,
	lower_energy_kj: float,
	floor_area_m2: float,
	room_height_m: float,
	ambient_c: float
) -> Array:
	## The primitive is pure. Reuse only a bit-identical input tuple for the same
	## room; there is deliberately no approximate comparison or quantization.
	## A single-entry cache is enough for the common post(N) == pre(N+1) chain
	## while keeping memory bounded independently of run length.
	var cached: Array = _derive_cache_by_room.get(room_id, [])
	if cached.size() == DeriveCache.SIZE \
			and float(cached[DeriveCache.UPPER_MASS_KG]) == upper_mass_kg \
			and float(cached[DeriveCache.UPPER_ENERGY_KJ]) == upper_energy_kj \
			and float(cached[DeriveCache.LOWER_MASS_KG]) == lower_mass_kg \
			and float(cached[DeriveCache.LOWER_ENERGY_KJ]) == lower_energy_kj \
			and float(cached[DeriveCache.FLOOR_AREA_M2]) == floor_area_m2 \
			and float(cached[DeriveCache.ROOM_HEIGHT_M]) == room_height_m \
			and float(cached[DeriveCache.AMBIENT_C]) == ambient_c:
		return cached[DeriveCache.RESULT]
	var result: Array = ResidualProjectionScript.derive_observables(
		upper_mass_kg, upper_energy_kj, lower_mass_kg, lower_energy_kj,
		floor_area_m2, room_height_m, ambient_c
	)
	_derive_cache_by_room[room_id] = [
		upper_mass_kg, upper_energy_kj, lower_mass_kg, lower_energy_kj,
		floor_area_m2, room_height_m, ambient_c, result,
	]
	return result


func accumulate_step(trace_events: Array, geometry_by_room: Dictionary) -> void:
	## `trace_events` is one physical timestep of the existing projection trace.
	## `geometry_by_room` maps a room id (as String) to
	## {"floor_area_m2": float, "room_height_m": float}. Both are read-only
	## inputs; nothing here is written back to either.
	if not enabled:
		return
	begin_step()
	for raw in trace_events:
		var event: Array = raw if raw is Array \
			else TraceRecordScript.from_dictionary(raw)
		accumulate_event(event, geometry_by_room)


func begin_step() -> void:
	if not enabled:
		return
	_ensure_totals()
	_timesteps += 1
	_totals[TotalMetric.TIMESTEPS] = int(_totals[TotalMetric.TIMESTEPS]) + 1


func accumulate_event(event: Array, geometry_by_room: Dictionary) -> void:
	if enabled:
		var room_id: int = int(event[TraceRecordScript.Field.ROOM_ID])
		var cause: String = String(event[TraceRecordScript.Field.CAUSE])
		var room_block: Array = _room(room_id)
		var cause_block: Array = _cause(cause)

		room_block[BlockMetric.CALL_COUNT] = int(room_block[BlockMetric.CALL_COUNT]) + 1
		cause_block[BlockMetric.CALL_COUNT] = int(cause_block[BlockMetric.CALL_COUNT]) + 1
		_totals[TotalMetric.CALL_COUNT] = int(_totals[TotalMetric.CALL_COUNT]) + 1

		var geometry: Dictionary = geometry_by_room.get(str(room_id), {})
		if geometry.is_empty():
			record_unavailable(REASON_GEOMETRY_UNAVAILABLE)
			return
		var floor_area_m2: float = float(geometry.get("floor_area_m2", 0.0))
		var room_height_m: float = float(geometry.get("room_height_m", 0.0))

		var ambient_c: float = float(event[TraceRecordScript.Field.AMBIENT_C])

		var pre_upper_mass: float = float(event[TraceRecordScript.Field.PRE_UPPER_GAS_KG])
		var pre_upper_energy: float = float(event[TraceRecordScript.Field.PRE_UPPER_ENERGY_KJ])
		var pre_lower_mass: float = float(event[TraceRecordScript.Field.PRE_LOWER_GAS_KG])
		var pre_lower_energy: float = float(event[TraceRecordScript.Field.PRE_LOWER_ENERGY_KJ])
		var post_upper_mass: float = float(event[TraceRecordScript.Field.POST_UPPER_GAS_KG])
		var post_upper_energy: float = float(event[TraceRecordScript.Field.POST_UPPER_ENERGY_KJ])
		var post_lower_mass: float = float(event[TraceRecordScript.Field.POST_LOWER_GAS_KG])
		var post_lower_energy: float = float(event[TraceRecordScript.Field.POST_LOWER_ENERGY_KJ])

		# What legacy rewrote, always recorded, whether or not the primitive
		# could evaluate this state.
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.LEGACY_UPPER_MASS_SIGNED,
			BlockMetric.LEGACY_UPPER_MASS_GROSS, -1,
			post_upper_mass - pre_upper_mass)
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.LEGACY_LOWER_MASS_SIGNED,
			BlockMetric.LEGACY_LOWER_MASS_GROSS, -1,
			post_lower_mass - pre_lower_mass)
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.LEGACY_UPPER_ENERGY_SIGNED,
			BlockMetric.LEGACY_UPPER_ENERGY_GROSS, -1,
			post_upper_energy - pre_upper_energy)
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.LEGACY_LOWER_ENERGY_SIGNED,
			BlockMetric.LEGACY_LOWER_ENERGY_GROSS, -1,
			post_lower_energy - pre_lower_energy)

		var residual: Array = _derive_cached(
			room_id,
			pre_upper_mass, pre_upper_energy, pre_lower_mass, pre_lower_energy,
			floor_area_m2, room_height_m, ambient_c)

		if not bool(residual[ResidualProjectionScript.Observable.VALID]):
			# Fail closed. The legacy state is untouched, the invalid case is
			# counted with its reason, and NOTHING is substituted for it.
			room_block[BlockMetric.PRIMITIVE_INVALID_COUNT] = \
					int(room_block[BlockMetric.PRIMITIVE_INVALID_COUNT]) + 1
			cause_block[BlockMetric.PRIMITIVE_INVALID_COUNT] = \
					int(cause_block[BlockMetric.PRIMITIVE_INVALID_COUNT]) + 1
			_totals[TotalMetric.PRIMITIVE_INVALID_COUNT] = \
					int(_totals[TotalMetric.PRIMITIVE_INVALID_COUNT]) + 1
			var reason: String = String(residual[ResidualProjectionScript.Observable.REASON])
			_invalid_reasons[reason] = int(_invalid_reasons.get(reason, 0)) + 1
			return

		room_block[BlockMetric.PRIMITIVE_VALID_COUNT] = \
				int(room_block[BlockMetric.PRIMITIVE_VALID_COUNT]) + 1
		cause_block[BlockMetric.PRIMITIVE_VALID_COUNT] = \
				int(cause_block[BlockMetric.PRIMITIVE_VALID_COUNT]) + 1
		_totals[TotalMetric.PRIMITIVE_VALID_COUNT] = \
				int(_totals[TotalMetric.PRIMITIVE_VALID_COUNT]) + 1

		# Inventory divergence. The primitive returns M and E bit-identical to
		# the pre-state, so this IS the legacy rewrite with the opposite sign.
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_UPPER_MASS_SIGNED,
			BlockMetric.RESIDUAL_UPPER_MASS_GROSS,
			BlockMetric.RESIDUAL_UPPER_MASS_MAX,
			pre_upper_mass - post_upper_mass)
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_LOWER_MASS_SIGNED,
			BlockMetric.RESIDUAL_LOWER_MASS_GROSS,
			BlockMetric.RESIDUAL_LOWER_MASS_MAX,
			pre_lower_mass - post_lower_mass)
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_UPPER_ENERGY_SIGNED,
			BlockMetric.RESIDUAL_UPPER_ENERGY_GROSS,
			BlockMetric.RESIDUAL_UPPER_ENERGY_MAX,
			pre_upper_energy - post_upper_energy)
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_LOWER_ENERGY_SIGNED,
			BlockMetric.RESIDUAL_LOWER_ENERGY_GROSS,
			BlockMetric.RESIDUAL_LOWER_ENERGY_MAX,
			pre_lower_energy - post_lower_energy)

		# Interface: the primitive's boundary against the layer height legacy
		# actually stored.
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_INTERFACE_SIGNED,
			BlockMetric.RESIDUAL_INTERFACE_GROSS,
			BlockMetric.RESIDUAL_INTERFACE_MAX,
			float(residual[ResidualProjectionScript.Observable.INTERFACE_HEIGHT_M])
			- float(event[TraceRecordScript.Field.POST_THERMAL_LAYER_M]))

		# Volumes: legacy computes and stores its own in the trace event.
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_UPPER_VOLUME_SIGNED,
			BlockMetric.RESIDUAL_UPPER_VOLUME_GROSS,
			BlockMetric.RESIDUAL_UPPER_VOLUME_MAX,
			float(residual[ResidualProjectionScript.Observable.UPPER_VOLUME_M3])
			- float(event[TraceRecordScript.Field.UPPER_VOLUME_M3]))
		_accumulate_signed_gross_max(room_block, cause_block,
			BlockMetric.RESIDUAL_LOWER_VOLUME_SIGNED,
			BlockMetric.RESIDUAL_LOWER_VOLUME_GROSS,
			BlockMetric.RESIDUAL_LOWER_VOLUME_MAX,
			float(residual[ResidualProjectionScript.Observable.LOWER_VOLUME_M3])
			- float(event[TraceRecordScript.Field.LOWER_VOLUME_M3]))

		_compare_zone_temperature(room_block, cause_block, "upper",
			bool(residual[ResidualProjectionScript.Observable.UPPER_PRESENT]),
			float(residual[ResidualProjectionScript.Observable.UPPER_TEMP_K]),
			post_upper_mass, float(event[TraceRecordScript.Field.POST_TEMP_UPPER_C]))
		_compare_zone_temperature(room_block, cause_block, "lower",
			bool(residual[ResidualProjectionScript.Observable.LOWER_PRESENT]),
			float(residual[ResidualProjectionScript.Observable.LOWER_TEMP_K]),
			post_lower_mass, float(event[TraceRecordScript.Field.POST_TEMP_LOWER_C]))

		_compare_presence(room_block, cause_block, "upper",
			bool(residual[ResidualProjectionScript.Observable.UPPER_PRESENT]), post_upper_mass)
		_compare_presence(room_block, cause_block, "lower",
			bool(residual[ResidualProjectionScript.Observable.LOWER_PRESENT]), post_lower_mass)

		# Canonical pressure of the PRE-state: a genuine output of the primitive.
		var pre_pressure_pa: float = float(
			residual[ResidualProjectionScript.Observable.PRESSURE_ABS_PA])
		_totals[TotalMetric.CANONICAL_PRE_PRESSURE_SUM] = \
				float(_totals[TotalMetric.CANONICAL_PRE_PRESSURE_SUM]) + pre_pressure_pa
		_totals[TotalMetric.CANONICAL_PRE_PRESSURE_SAMPLE_COUNT] = \
				int(_totals[TotalMetric.CANONICAL_PRE_PRESSURE_SAMPLE_COUNT]) + 1
		if _canonical_pre_pressure_has_sample:
			_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MIN] = minf(
				float(_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MIN]), pre_pressure_pa)
			_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MAX] = maxf(
				float(_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MAX]), pre_pressure_pa)
		else:
			_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MIN] = pre_pressure_pa
			_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MAX] = pre_pressure_pa
			_canonical_pre_pressure_has_sample = true

		var post_residual: Array = _derive_cached(
			room_id,
			post_upper_mass, post_upper_energy, post_lower_mass, post_lower_energy,
			floor_area_m2, room_height_m, ambient_c)
		_accumulate_canonical_pressure_from_legacy_post(post_residual)


func _compare_zone_temperature(
	first: Array, second: Array,
	zone: String, residual_present: bool, residual_temp_k: float,
	legacy_post_mass_kg: float, legacy_post_temp_c: float
) -> void:
	## Compared ONLY where the zone exists in both models. Where it does not,
	## nothing is compared and nothing is counted -- an absent zone has no
	## temperature in the primitive, and legacy's stored temperature for a zone
	## it considers absent is not a comparable quantity.
	if not residual_present:
		return
	if legacy_post_mass_kg <= LEGACY_ZONE_MASS_EPS_KG:
		return
	var legacy_temp_k: float = legacy_post_temp_c + 273.15
	var signed_index: int = BlockMetric.RESIDUAL_UPPER_TEMP_SIGNED \
		if zone == "upper" else BlockMetric.RESIDUAL_LOWER_TEMP_SIGNED
	var gross_index: int = BlockMetric.RESIDUAL_UPPER_TEMP_GROSS \
		if zone == "upper" else BlockMetric.RESIDUAL_LOWER_TEMP_GROSS
	var max_index: int = BlockMetric.RESIDUAL_UPPER_TEMP_MAX \
		if zone == "upper" else BlockMetric.RESIDUAL_LOWER_TEMP_MAX
	var count_index: int = BlockMetric.RESIDUAL_UPPER_TEMP_COUNT \
		if zone == "upper" else BlockMetric.RESIDUAL_LOWER_TEMP_COUNT
	_accumulate_signed_gross_max(
		first, second, signed_index, gross_index, max_index,
		residual_temp_k - legacy_temp_k)
	var total_count_index: int = TotalMetric.UPPER_TEMP_COMPARABLE_COUNT \
		if zone == "upper" else TotalMetric.LOWER_TEMP_COMPARABLE_COUNT
	first[count_index] = int(first[count_index]) + 1
	second[count_index] = int(second[count_index]) + 1
	_totals[total_count_index] = int(_totals[total_count_index]) + 1


func _compare_presence(
	first: Array, second: Array,
	zone: String, residual_present: bool, legacy_post_mass_kg: float
) -> void:
	## The primitive says present when M > 0. The legacy projection says present
	## when M > 1.0e-4. A disagreement is a DEFINITIONAL mismatch between two
	## predicates, never evidence that mass was lost.
	var legacy_present: bool = legacy_post_mass_kg > LEGACY_ZONE_MASS_EPS_KG
	if residual_present == legacy_present:
		return
	var mismatch_index: int = BlockMetric.PRESENCE_MISMATCH_UPPER \
		if zone == "upper" else BlockMetric.PRESENCE_MISMATCH_LOWER
	var total_mismatch_index: int = TotalMetric.PRESENCE_MISMATCH_UPPER \
		if zone == "upper" else TotalMetric.PRESENCE_MISMATCH_LOWER
	first[mismatch_index] = int(first[mismatch_index]) + 1
	first[BlockMetric.PRESENCE_MISMATCH_TOTAL] = \
			int(first[BlockMetric.PRESENCE_MISMATCH_TOTAL]) + 1
	second[mismatch_index] = int(second[mismatch_index]) + 1
	second[BlockMetric.PRESENCE_MISMATCH_TOTAL] = \
			int(second[BlockMetric.PRESENCE_MISMATCH_TOTAL]) + 1
	_totals[total_mismatch_index] = int(_totals[total_mismatch_index]) + 1
	_totals[TotalMetric.PRESENCE_MISMATCH_TOTAL] = \
			int(_totals[TotalMetric.PRESENCE_MISMATCH_TOTAL]) + 1


func _accumulate_canonical_pressure_from_legacy_post(recomputed: Array) -> void:
	## The H3.2b2 equation of state applied to the LEGACY POST inventory. This is
	## a recomputation for reporting only. Legacy produced no pressure, so this
	## must never be called a legacy pressure. It is not fed back into the
	## primitive, is not used as an input anywhere, and is not used to close any
	## residual.
	if not bool(recomputed[ResidualProjectionScript.Observable.VALID]):
		_totals[TotalMetric.CANONICAL_POST_PRESSURE_INVALID_COUNT] = int(
			_totals[TotalMetric.CANONICAL_POST_PRESSURE_INVALID_COUNT]) + 1
		return
	var value: float = float(recomputed[ResidualProjectionScript.Observable.PRESSURE_ABS_PA])
	_totals[TotalMetric.CANONICAL_POST_PRESSURE_SUM] = \
			float(_totals[TotalMetric.CANONICAL_POST_PRESSURE_SUM]) + value
	_totals[TotalMetric.CANONICAL_POST_PRESSURE_SAMPLE_COUNT] = \
			int(_totals[TotalMetric.CANONICAL_POST_PRESSURE_SAMPLE_COUNT]) + 1
	if _canonical_post_pressure_has_sample:
		_totals[TotalMetric.CANONICAL_POST_PRESSURE_MIN] = minf(
			float(_totals[TotalMetric.CANONICAL_POST_PRESSURE_MIN]), value)
		_totals[TotalMetric.CANONICAL_POST_PRESSURE_MAX] = maxf(
			float(_totals[TotalMetric.CANONICAL_POST_PRESSURE_MAX]), value)
	else:
		_totals[TotalMetric.CANONICAL_POST_PRESSURE_MIN] = value
		_totals[TotalMetric.CANONICAL_POST_PRESSURE_MAX] = value
		_canonical_post_pressure_has_sample = true


func _net_status(signed_total: float, gross_total: float) -> Dictionary:
	## A net of exactly zero is reported as such rather than divided by. Gross is
	## projection churn, never a physical contribution.
	if signed_total == 0.0:
		return {
			"status": "net_exactly_zero",
			"gross_absolute": gross_total,
			"gross_over_net": null,
		}
	return {
		"status": "defined",
		"gross_absolute": gross_total,
		"gross_over_net": gross_total / absf(signed_total),
	}


func _block_to_dictionary(block: Array) -> Dictionary:
	return {
		"call_count_total": block[BlockMetric.CALL_COUNT],
		"primitive_valid_count_total": block[BlockMetric.PRIMITIVE_VALID_COUNT],
		"primitive_invalid_count_total": block[BlockMetric.PRIMITIVE_INVALID_COUNT],
		"legacy_rewrite_upper_mass_signed_net_kg_total": block[BlockMetric.LEGACY_UPPER_MASS_SIGNED],
		"legacy_rewrite_upper_mass_gross_absolute_kg_total": block[BlockMetric.LEGACY_UPPER_MASS_GROSS],
		"legacy_rewrite_lower_mass_signed_net_kg_total": block[BlockMetric.LEGACY_LOWER_MASS_SIGNED],
		"legacy_rewrite_lower_mass_gross_absolute_kg_total": block[BlockMetric.LEGACY_LOWER_MASS_GROSS],
		"legacy_rewrite_upper_energy_signed_net_kj_total": block[BlockMetric.LEGACY_UPPER_ENERGY_SIGNED],
		"legacy_rewrite_upper_energy_gross_absolute_kj_total": block[BlockMetric.LEGACY_UPPER_ENERGY_GROSS],
		"legacy_rewrite_lower_energy_signed_net_kj_total": block[BlockMetric.LEGACY_LOWER_ENERGY_SIGNED],
		"legacy_rewrite_lower_energy_gross_absolute_kj_total": block[BlockMetric.LEGACY_LOWER_ENERGY_GROSS],
		"residual_vs_legacy_upper_mass_signed_net_kg_total": block[BlockMetric.RESIDUAL_UPPER_MASS_SIGNED],
		"residual_vs_legacy_upper_mass_gross_absolute_kg_total": block[BlockMetric.RESIDUAL_UPPER_MASS_GROSS],
		"residual_vs_legacy_upper_mass_max_absolute_kg": block[BlockMetric.RESIDUAL_UPPER_MASS_MAX],
		"residual_vs_legacy_lower_mass_signed_net_kg_total": block[BlockMetric.RESIDUAL_LOWER_MASS_SIGNED],
		"residual_vs_legacy_lower_mass_gross_absolute_kg_total": block[BlockMetric.RESIDUAL_LOWER_MASS_GROSS],
		"residual_vs_legacy_lower_mass_max_absolute_kg": block[BlockMetric.RESIDUAL_LOWER_MASS_MAX],
		"residual_vs_legacy_upper_energy_signed_net_kj_total": block[BlockMetric.RESIDUAL_UPPER_ENERGY_SIGNED],
		"residual_vs_legacy_upper_energy_gross_absolute_kj_total": block[BlockMetric.RESIDUAL_UPPER_ENERGY_GROSS],
		"residual_vs_legacy_upper_energy_max_absolute_kj": block[BlockMetric.RESIDUAL_UPPER_ENERGY_MAX],
		"residual_vs_legacy_lower_energy_signed_net_kj_total": block[BlockMetric.RESIDUAL_LOWER_ENERGY_SIGNED],
		"residual_vs_legacy_lower_energy_gross_absolute_kj_total": block[BlockMetric.RESIDUAL_LOWER_ENERGY_GROSS],
		"residual_vs_legacy_lower_energy_max_absolute_kj": block[BlockMetric.RESIDUAL_LOWER_ENERGY_MAX],
		"residual_vs_legacy_interface_signed_net_m_total": block[BlockMetric.RESIDUAL_INTERFACE_SIGNED],
		"residual_vs_legacy_interface_gross_absolute_m_total": block[BlockMetric.RESIDUAL_INTERFACE_GROSS],
		"residual_vs_legacy_interface_max_absolute_m": block[BlockMetric.RESIDUAL_INTERFACE_MAX],
		"residual_vs_legacy_upper_volume_signed_net_m3_total": block[BlockMetric.RESIDUAL_UPPER_VOLUME_SIGNED],
		"residual_vs_legacy_upper_volume_gross_absolute_m3_total": block[BlockMetric.RESIDUAL_UPPER_VOLUME_GROSS],
		"residual_vs_legacy_upper_volume_max_absolute_m3": block[BlockMetric.RESIDUAL_UPPER_VOLUME_MAX],
		"residual_vs_legacy_lower_volume_signed_net_m3_total": block[BlockMetric.RESIDUAL_LOWER_VOLUME_SIGNED],
		"residual_vs_legacy_lower_volume_gross_absolute_m3_total": block[BlockMetric.RESIDUAL_LOWER_VOLUME_GROSS],
		"residual_vs_legacy_lower_volume_max_absolute_m3": block[BlockMetric.RESIDUAL_LOWER_VOLUME_MAX],
		"residual_vs_legacy_upper_temp_signed_net_k_total": block[BlockMetric.RESIDUAL_UPPER_TEMP_SIGNED],
		"residual_vs_legacy_upper_temp_gross_absolute_k_total": block[BlockMetric.RESIDUAL_UPPER_TEMP_GROSS],
		"residual_vs_legacy_upper_temp_max_absolute_k": block[BlockMetric.RESIDUAL_UPPER_TEMP_MAX],
		"residual_vs_legacy_upper_temp_comparable_count_total": block[BlockMetric.RESIDUAL_UPPER_TEMP_COUNT],
		"residual_vs_legacy_lower_temp_signed_net_k_total": block[BlockMetric.RESIDUAL_LOWER_TEMP_SIGNED],
		"residual_vs_legacy_lower_temp_gross_absolute_k_total": block[BlockMetric.RESIDUAL_LOWER_TEMP_GROSS],
		"residual_vs_legacy_lower_temp_max_absolute_k": block[BlockMetric.RESIDUAL_LOWER_TEMP_MAX],
		"residual_vs_legacy_lower_temp_comparable_count_total": block[BlockMetric.RESIDUAL_LOWER_TEMP_COUNT],
		"presence_predicate_mismatch_upper_total": block[BlockMetric.PRESENCE_MISMATCH_UPPER],
		"presence_predicate_mismatch_lower_total": block[BlockMetric.PRESENCE_MISMATCH_LOWER],
		"presence_predicate_mismatch_total": block[BlockMetric.PRESENCE_MISMATCH_TOTAL],
	}


func _totals_dictionary() -> Dictionary:
	if _totals.size() != TotalMetric.SIZE:
		return {}
	var result: Dictionary = {
		"timesteps_total": _totals[TotalMetric.TIMESTEPS],
		"call_count_total": _totals[TotalMetric.CALL_COUNT],
		"primitive_valid_count_total": _totals[TotalMetric.PRIMITIVE_VALID_COUNT],
		"primitive_invalid_count_total": _totals[TotalMetric.PRIMITIVE_INVALID_COUNT],
		"presence_predicate_mismatch_total": _totals[TotalMetric.PRESENCE_MISMATCH_TOTAL],
		"presence_predicate_mismatch_upper_total": _totals[TotalMetric.PRESENCE_MISMATCH_UPPER],
		"presence_predicate_mismatch_lower_total": _totals[TotalMetric.PRESENCE_MISMATCH_LOWER],
		"residual_vs_legacy_upper_temp_comparable_count_total": \
				_totals[TotalMetric.UPPER_TEMP_COMPARABLE_COUNT],
		"residual_vs_legacy_lower_temp_comparable_count_total": \
				_totals[TotalMetric.LOWER_TEMP_COMPARABLE_COUNT],
		"canonical_pressure_pre_sample_count_total": \
				_totals[TotalMetric.CANONICAL_PRE_PRESSURE_SAMPLE_COUNT],
		"canonical_pressure_from_legacy_post_sample_count_total": \
				_totals[TotalMetric.CANONICAL_POST_PRESSURE_SAMPLE_COUNT],
		"canonical_pressure_from_legacy_post_invalid_count_total": \
				_totals[TotalMetric.CANONICAL_POST_PRESSURE_INVALID_COUNT],
	}
	if _canonical_pre_pressure_has_sample:
		result["canonical_pressure_pre_pa_sum"] = \
				_totals[TotalMetric.CANONICAL_PRE_PRESSURE_SUM]
		result["canonical_pressure_pre_pa_min"] = \
				_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MIN]
		result["canonical_pressure_pre_pa_max"] = \
				_totals[TotalMetric.CANONICAL_PRE_PRESSURE_MAX]
	if _canonical_post_pressure_has_sample:
		result["canonical_pressure_from_legacy_post_pa_sum"] = \
				_totals[TotalMetric.CANONICAL_POST_PRESSURE_SUM]
		result["canonical_pressure_from_legacy_post_pa_min"] = \
				_totals[TotalMetric.CANONICAL_POST_PRESSURE_MIN]
		result["canonical_pressure_from_legacy_post_pa_max"] = \
				_totals[TotalMetric.CANONICAL_POST_PRESSURE_MAX]
	return result


func summary() -> Dictionary:
	if not enabled:
		return {}
	var unavailable: Array[String] = []
	for reason in _unavailable.keys():
		unavailable.append(String(reason))
	unavailable.sort()

	var churn: Dictionary = {}
	for spec in [
		["legacy_rewrite_lower_mass", BlockMetric.LEGACY_LOWER_MASS_SIGNED,
			BlockMetric.LEGACY_LOWER_MASS_GROSS],
		["legacy_rewrite_upper_mass", BlockMetric.LEGACY_UPPER_MASS_SIGNED,
			BlockMetric.LEGACY_UPPER_MASS_GROSS],
		["residual_vs_legacy_lower_mass", BlockMetric.RESIDUAL_LOWER_MASS_SIGNED,
			BlockMetric.RESIDUAL_LOWER_MASS_GROSS],
		["residual_vs_legacy_upper_mass", BlockMetric.RESIDUAL_UPPER_MASS_SIGNED,
			BlockMetric.RESIDUAL_UPPER_MASS_GROSS],
	]:
		var signed_total: float = 0.0
		var gross_total: float = 0.0
		for raw in _rooms.values():
			var block: Array = raw
			signed_total += float(block[int(spec[1])])
			gross_total += float(block[int(spec[2])])
		churn[String(spec[0])] = _net_status(signed_total, gross_total)

	var by_room: Dictionary = {}
	for room_key in _rooms.keys():
		var room_block: Dictionary = _block_to_dictionary(_rooms[room_key])
		room_block["room_id"] = int(room_key)
		by_room[room_key] = room_block
	var by_cause: Dictionary = {}
	for cause in _by_cause.keys():
		var cause_block: Dictionary = _block_to_dictionary(_by_cause[cause])
		cause_block["cause"] = String(cause)
		by_cause[cause] = cause_block

	return {
		"timesteps_total": _timesteps,
		"data_available": unavailable.is_empty(),
		"unavailable_reason_codes": unavailable,
		"legacy_presence_predicate_kg": LEGACY_ZONE_MASS_EPS_KG,
		"presence_predicate_note":
			"the primitive uses M > 0 and the legacy projection uses"
			+ " M > 1.0e-4; a mismatch is a definitional disagreement between"
			+ " two predicates, never evidence of lost mass. Choosing one"
			+ " canonical predicate is a blocker for H3.2b6",
		"pressure_label_note":
			"legacy projection stores no pressure."
			+ " canonical_pressure_from_legacy_post_pa is the H3.2b2 equation of"
			+ " state applied to the legacy post inventory, NOT a pressure legacy"
			+ " produced, and it is never used as an input or to close a residual",
		"gross_absolute_meaning":
			"projection churn: the volume of rewriting performed."
			+ " NOT a physical contribution and NOT a source",
		"transition_counter_note":
			"the runtime zone birth/death counters are known blind (H3.2b1a"
			+ " measured at least 29 missed births) and are neither repaired,"
			+ " gated on, nor reported here",
		"shadow_applied": false,
		"primitive_invalid_reason_counts": _invalid_reasons.duplicate(true),
		"churn": churn,
		"totals": _totals_dictionary(),
		"by_cause": by_cause,
		"by_room": by_room,
	}
