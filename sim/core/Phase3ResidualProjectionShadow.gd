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

## The legacy projection's own presence predicate, mirrored from
## `ZoneFireSolver.ZONE_MASS_EPS_KG`. This is the predicate being compared; it is
## not a proposal for a canonical one.
const LEGACY_ZONE_MASS_EPS_KG: float = 1.0e-4

## Telemetry this accumulator does not own. Fails closed rather than reporting
## zeros, exactly as the H3.2b1 ledger does.
const REASON_TRACE_UNAVAILABLE: String = "projection_trace_unavailable"
const REASON_GEOMETRY_UNAVAILABLE: String = "room_geometry_unavailable"

var enabled: bool = false

var _totals: Dictionary = {}
var _by_cause: Dictionary = {}
var _rooms: Dictionary = {}
var _invalid_reasons: Dictionary = {}
var _unavailable: Dictionary = {}
var _timesteps: int = 0


func clear() -> void:
	_totals.clear()
	_by_cause.clear()
	_rooms.clear()
	_invalid_reasons.clear()
	_unavailable.clear()
	_timesteps = 0


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
	for key in [
		"timesteps_total",
		"call_count_total",
		"primitive_valid_count_total",
		"primitive_invalid_count_total",
		"presence_predicate_mismatch_total",
		"presence_predicate_mismatch_upper_total",
		"presence_predicate_mismatch_lower_total",
		"residual_vs_legacy_upper_temp_comparable_count_total",
		"residual_vs_legacy_lower_temp_comparable_count_total",
		"canonical_pressure_pre_sample_count_total",
		"canonical_pressure_from_legacy_post_sample_count_total",
		"canonical_pressure_from_legacy_post_invalid_count_total",
	]:
		if not _totals.has(key):
			_totals[key] = 0


func _bump(key: String, amount: float) -> void:
	_totals[key] = float(_totals.get(key, 0.0)) + amount


func _bump_int(key: String, amount: int) -> void:
	_totals[key] = int(_totals.get(key, 0)) + amount


func _new_divergence_block() -> Dictionary:
	return {
		"call_count_total": 0,
		"primitive_valid_count_total": 0,
		"primitive_invalid_count_total": 0,
		# What legacy rewrote: post - pre.
		"legacy_rewrite_upper_mass_signed_net_kg_total": 0.0,
		"legacy_rewrite_upper_mass_gross_absolute_kg_total": 0.0,
		"legacy_rewrite_lower_mass_signed_net_kg_total": 0.0,
		"legacy_rewrite_lower_mass_gross_absolute_kg_total": 0.0,
		"legacy_rewrite_upper_energy_signed_net_kj_total": 0.0,
		"legacy_rewrite_upper_energy_gross_absolute_kj_total": 0.0,
		"legacy_rewrite_lower_energy_signed_net_kj_total": 0.0,
		"legacy_rewrite_lower_energy_gross_absolute_kj_total": 0.0,
		# Residual minus legacy, per quantity.
		"residual_vs_legacy_upper_mass_signed_net_kg_total": 0.0,
		"residual_vs_legacy_upper_mass_gross_absolute_kg_total": 0.0,
		"residual_vs_legacy_upper_mass_max_absolute_kg": 0.0,
		"residual_vs_legacy_lower_mass_signed_net_kg_total": 0.0,
		"residual_vs_legacy_lower_mass_gross_absolute_kg_total": 0.0,
		"residual_vs_legacy_lower_mass_max_absolute_kg": 0.0,
		"residual_vs_legacy_upper_energy_signed_net_kj_total": 0.0,
		"residual_vs_legacy_upper_energy_gross_absolute_kj_total": 0.0,
		"residual_vs_legacy_upper_energy_max_absolute_kj": 0.0,
		"residual_vs_legacy_lower_energy_signed_net_kj_total": 0.0,
		"residual_vs_legacy_lower_energy_gross_absolute_kj_total": 0.0,
		"residual_vs_legacy_lower_energy_max_absolute_kj": 0.0,
		# Interface and volumes.
		"residual_vs_legacy_interface_signed_net_m_total": 0.0,
		"residual_vs_legacy_interface_gross_absolute_m_total": 0.0,
		"residual_vs_legacy_interface_max_absolute_m": 0.0,
		"residual_vs_legacy_upper_volume_signed_net_m3_total": 0.0,
		"residual_vs_legacy_upper_volume_gross_absolute_m3_total": 0.0,
		"residual_vs_legacy_upper_volume_max_absolute_m3": 0.0,
		"residual_vs_legacy_lower_volume_signed_net_m3_total": 0.0,
		"residual_vs_legacy_lower_volume_gross_absolute_m3_total": 0.0,
		"residual_vs_legacy_lower_volume_max_absolute_m3": 0.0,
		# Temperatures, only where the zone exists in BOTH models.
		"residual_vs_legacy_upper_temp_signed_net_k_total": 0.0,
		"residual_vs_legacy_upper_temp_gross_absolute_k_total": 0.0,
		"residual_vs_legacy_upper_temp_max_absolute_k": 0.0,
		"residual_vs_legacy_upper_temp_comparable_count_total": 0,
		"residual_vs_legacy_lower_temp_signed_net_k_total": 0.0,
		"residual_vs_legacy_lower_temp_gross_absolute_k_total": 0.0,
		"residual_vs_legacy_lower_temp_max_absolute_k": 0.0,
		"residual_vs_legacy_lower_temp_comparable_count_total": 0,
		# Presence disagreement against the legacy projection predicate.
		"presence_predicate_mismatch_upper_total": 0,
		"presence_predicate_mismatch_lower_total": 0,
		"presence_predicate_mismatch_total": 0,
	}


func _room(room_id: int) -> Dictionary:
	var key: String = str(room_id)
	if not _rooms.has(key):
		var block: Dictionary = _new_divergence_block()
		block["room_id"] = room_id
		_rooms[key] = block
	return _rooms[key]


func _cause(cause: String) -> Dictionary:
	if not _by_cause.has(cause):
		var block: Dictionary = _new_divergence_block()
		block["cause"] = cause
		_by_cause[cause] = block
	return _by_cause[cause]


func _accumulate_signed_gross_max(
	blocks: Array, prefix: String, unit: String, value: float
) -> void:
	for raw in blocks:
		var block: Dictionary = raw
		var signed_key: String = "%s_signed_net_%s_total" % [prefix, unit]
		var gross_key: String = "%s_gross_absolute_%s_total" % [prefix, unit]
		var max_key: String = "%s_max_absolute_%s" % [prefix, unit]
		block[signed_key] = float(block[signed_key]) + value
		block[gross_key] = float(block[gross_key]) + absf(value)
		if block.has(max_key):
			block[max_key] = maxf(float(block[max_key]), absf(value))


func accumulate_step(trace_events: Array, geometry_by_room: Dictionary) -> void:
	## `trace_events` is one physical timestep of the existing projection trace.
	## `geometry_by_room` maps a room id (as String) to
	## {"floor_area_m2": float, "room_height_m": float}. Both are read-only
	## inputs; nothing here is written back to either.
	if not enabled:
		return
	_ensure_totals()
	_timesteps += 1
	_bump_int("timesteps_total", 1)

	for raw in trace_events:
		var event: Dictionary = raw
		var room_id: int = int(event.get("room_id", -1))
		var cause: String = String(event.get("cause", "unspecified"))
		var room_block: Dictionary = _room(room_id)
		var cause_block: Dictionary = _cause(cause)
		var blocks: Array = [room_block, cause_block]

		room_block["call_count_total"] = int(room_block["call_count_total"]) + 1
		cause_block["call_count_total"] = int(cause_block["call_count_total"]) + 1
		_bump_int("call_count_total", 1)

		var geometry: Dictionary = geometry_by_room.get(str(room_id), {})
		if geometry.is_empty():
			record_unavailable(REASON_GEOMETRY_UNAVAILABLE)
			continue
		var floor_area_m2: float = float(geometry.get("floor_area_m2", 0.0))
		var room_height_m: float = float(geometry.get("room_height_m", 0.0))

		var pre: Dictionary = event.get("pre", {})
		var post: Dictionary = event.get("post", {})
		var ambient_c: float = float(event.get("ambient_c", 0.0))

		var pre_upper_mass: float = float(pre.get("upper_gas_kg", 0.0))
		var pre_upper_energy: float = float(pre.get("upper_energy_kj", 0.0))
		var pre_lower_mass: float = float(pre.get("lower_gas_kg", 0.0))
		var pre_lower_energy: float = float(pre.get("lower_energy_kj", 0.0))
		var post_upper_mass: float = float(post.get("upper_gas_kg", 0.0))
		var post_upper_energy: float = float(post.get("upper_energy_kj", 0.0))
		var post_lower_mass: float = float(post.get("lower_gas_kg", 0.0))
		var post_lower_energy: float = float(post.get("lower_energy_kj", 0.0))

		# What legacy rewrote, always recorded, whether or not the primitive
		# could evaluate this state.
		_accumulate_signed_gross_max(blocks, "legacy_rewrite_upper_mass", "kg",
			post_upper_mass - pre_upper_mass)
		_accumulate_signed_gross_max(blocks, "legacy_rewrite_lower_mass", "kg",
			post_lower_mass - pre_lower_mass)
		_accumulate_signed_gross_max(blocks, "legacy_rewrite_upper_energy", "kj",
			post_upper_energy - pre_upper_energy)
		_accumulate_signed_gross_max(blocks, "legacy_rewrite_lower_energy", "kj",
			post_lower_energy - pre_lower_energy)

		var residual: Dictionary = ResidualProjectionScript.derive(
			pre_upper_mass, pre_upper_energy, pre_lower_mass, pre_lower_energy,
			floor_area_m2, room_height_m, ambient_c)

		if not bool(residual.get("valid", false)):
			# Fail closed. The legacy state is untouched, the invalid case is
			# counted with its reason, and NOTHING is substituted for it.
			room_block["primitive_invalid_count_total"] = \
					int(room_block["primitive_invalid_count_total"]) + 1
			cause_block["primitive_invalid_count_total"] = \
					int(cause_block["primitive_invalid_count_total"]) + 1
			_bump_int("primitive_invalid_count_total", 1)
			var reason: String = String(residual.get("reason_code", "unspecified"))
			_invalid_reasons[reason] = int(_invalid_reasons.get(reason, 0)) + 1
			continue

		room_block["primitive_valid_count_total"] = \
				int(room_block["primitive_valid_count_total"]) + 1
		cause_block["primitive_valid_count_total"] = \
				int(cause_block["primitive_valid_count_total"]) + 1
		_bump_int("primitive_valid_count_total", 1)

		var residual_upper: Dictionary = residual.get("upper", {})
		var residual_lower: Dictionary = residual.get("lower", {})

		# Inventory divergence. The primitive returns M and E bit-identical to
		# the pre-state, so this IS the legacy rewrite with the opposite sign.
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_upper_mass", "kg",
			float(residual_upper.get("mass_kg", 0.0)) - post_upper_mass)
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_lower_mass", "kg",
			float(residual_lower.get("mass_kg", 0.0)) - post_lower_mass)
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_upper_energy", "kj",
			float(residual_upper.get("energy_kj", 0.0)) - post_upper_energy)
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_lower_energy", "kj",
			float(residual_lower.get("energy_kj", 0.0)) - post_lower_energy)

		# Interface: the primitive's boundary against the layer height legacy
		# actually stored.
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_interface", "m",
			float(residual.get("interface_height_m", 0.0))
			- float(post.get("thermal_layer_m", 0.0)))

		# Volumes: legacy computes and stores its own in the trace event.
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_upper_volume", "m3",
			float(residual_upper.get("volume_m3", 0.0))
			- float(event.get("upper_volume_m3", 0.0)))
		_accumulate_signed_gross_max(blocks, "residual_vs_legacy_lower_volume", "m3",
			float(residual_lower.get("volume_m3", 0.0))
			- float(event.get("lower_volume_m3", 0.0)))

		_compare_zone_temperature(blocks, "upper", residual_upper,
			post_upper_mass, float(post.get("temp_upper_c", 0.0)))
		_compare_zone_temperature(blocks, "lower", residual_lower,
			post_lower_mass, float(post.get("temp_lower_c", 0.0)))

		_compare_presence(blocks, "upper", residual_upper, post_upper_mass)
		_compare_presence(blocks, "lower", residual_lower, post_lower_mass)

		# Canonical pressure of the PRE-state: a genuine output of the primitive.
		_bump("canonical_pressure_pre_pa_sum", float(residual.get("pressure_abs_pa", 0.0)))
		_bump_int("canonical_pressure_pre_sample_count_total", 1)
		_track_extremes("canonical_pressure_pre_pa",
			float(residual.get("pressure_abs_pa", 0.0)))

		_accumulate_canonical_pressure_from_legacy_post(
			post_upper_mass, post_upper_energy, post_lower_mass, post_lower_energy,
			floor_area_m2, room_height_m, ambient_c)


func _compare_zone_temperature(
	blocks: Array, zone: String, residual_zone: Dictionary,
	legacy_post_mass_kg: float, legacy_post_temp_c: float
) -> void:
	## Compared ONLY where the zone exists in both models. Where it does not,
	## nothing is compared and nothing is counted -- an absent zone has no
	## temperature in the primitive, and legacy's stored temperature for a zone
	## it considers absent is not a comparable quantity.
	if not bool(residual_zone.get("present", false)):
		return
	if legacy_post_mass_kg <= LEGACY_ZONE_MASS_EPS_KG:
		return
	var legacy_temp_k: float = legacy_post_temp_c + 273.15
	var residual_temp_k: float = float(residual_zone.get("temperature_k", 0.0))
	_accumulate_signed_gross_max(blocks,
		"residual_vs_legacy_%s_temp" % zone, "k", residual_temp_k - legacy_temp_k)
	var count_key: String = "residual_vs_legacy_%s_temp_comparable_count_total" % zone
	for raw in blocks:
		var block: Dictionary = raw
		block[count_key] = int(block[count_key]) + 1
	_bump_int(count_key, 1)


func _compare_presence(
	blocks: Array, zone: String, residual_zone: Dictionary, legacy_post_mass_kg: float
) -> void:
	## The primitive says present when M > 0. The legacy projection says present
	## when M > 1.0e-4. A disagreement is a DEFINITIONAL mismatch between two
	## predicates, never evidence that mass was lost.
	var residual_present: bool = bool(residual_zone.get("present", false))
	var legacy_present: bool = legacy_post_mass_kg > LEGACY_ZONE_MASS_EPS_KG
	if residual_present == legacy_present:
		return
	var key: String = "presence_predicate_mismatch_%s_total" % zone
	for raw in blocks:
		var block: Dictionary = raw
		block[key] = int(block[key]) + 1
		block["presence_predicate_mismatch_total"] = \
				int(block["presence_predicate_mismatch_total"]) + 1
	_bump_int(key, 1)
	_bump_int("presence_predicate_mismatch_total", 1)


func _accumulate_canonical_pressure_from_legacy_post(
	upper_mass_kg: float, upper_energy_kj: float,
	lower_mass_kg: float, lower_energy_kj: float,
	floor_area_m2: float, room_height_m: float, ambient_c: float
) -> void:
	## The H3.2b2 equation of state applied to the LEGACY POST inventory. This is
	## a recomputation for reporting only. Legacy produced no pressure, so this
	## must never be called a legacy pressure. It is not fed back into the
	## primitive, is not used as an input anywhere, and is not used to close any
	## residual.
	var recomputed: Dictionary = ResidualProjectionScript.derive(
		upper_mass_kg, upper_energy_kj, lower_mass_kg, lower_energy_kj,
		floor_area_m2, room_height_m, ambient_c)
	if not bool(recomputed.get("valid", false)):
		_bump_int("canonical_pressure_from_legacy_post_invalid_count_total", 1)
		return
	var value: float = float(recomputed.get("pressure_abs_pa", 0.0))
	_bump("canonical_pressure_from_legacy_post_pa_sum", value)
	_bump_int("canonical_pressure_from_legacy_post_sample_count_total", 1)
	_track_extremes("canonical_pressure_from_legacy_post_pa", value)


func _track_extremes(prefix: String, value: float) -> void:
	var min_key: String = prefix + "_min"
	var max_key: String = prefix + "_max"
	if _totals.has(min_key):
		_totals[min_key] = minf(float(_totals[min_key]), value)
	else:
		_totals[min_key] = value
	if _totals.has(max_key):
		_totals[max_key] = maxf(float(_totals[max_key]), value)
	else:
		_totals[max_key] = value


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


func summary() -> Dictionary:
	if not enabled:
		return {}
	var unavailable: Array[String] = []
	for reason in _unavailable.keys():
		unavailable.append(String(reason))
	unavailable.sort()

	var churn: Dictionary = {}
	for prefix in ["legacy_rewrite_lower_mass", "legacy_rewrite_upper_mass",
			"residual_vs_legacy_lower_mass", "residual_vs_legacy_upper_mass"]:
		var signed_total: float = 0.0
		var gross_total: float = 0.0
		for raw in _rooms.values():
			var block: Dictionary = raw
			signed_total += float(block["%s_signed_net_kg_total" % prefix])
			gross_total += float(block["%s_gross_absolute_kg_total" % prefix])
		churn[prefix] = _net_status(signed_total, gross_total)

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
		"totals": _totals.duplicate(true),
		"by_cause": _by_cause.duplicate(true),
		"by_room": _rooms.duplicate(true),
	}
