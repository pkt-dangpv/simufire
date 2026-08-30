extends RefCounted

## H3.2-S0d6: passive ledger of O2 acceptance, shared by every subsystem that
## mutates O2 state.
##
## O2 room state is three INDEPENDENT fractions -- o2, o2_upper, o2_lower -- with
## no invariant tying them together (RoomModel.gd:48: "Variable persistente; NO
## derivada de o2"), written by five subsystems that use inconsistent mass bases.
## This ledger records what each mutation site requested and what it accepted, in
## the native unit, and refuses to publish a kilogram unless that same site both
## capped and applied against the same mass base.
##
## It observes. It never repairs, never splits a deficit between owners, never
## reconstructs an accepted amount as `post - pre` and never derives one from HRR.

## Why a record may not carry attributable kilograms.
const REASON_COMPLETE: String = "complete"
const REASON_AMBIGUOUS_MASS_BASE: String = "unit_not_mass_ambiguous_base"
const REASON_NO_ZONAL_INVARIANT: String = "no_zonal_invariant"
const REASON_AGGREGATE_MULTI_OWNER: String = "aggregate_clamp_multi_owner"
const REASON_SINK_TRUNCATED: String = "sink_truncated_unowned"
## Fail-closed marker: two different reason codes reached the same owner/zone key.
## Never passed in by a caller; only the ledger sets it.
const REASON_CONFLICT: String = "reason_code_conflict"

const VALID_REASONS: Array[String] = [
	REASON_COMPLETE,
	REASON_AMBIGUOUS_MASS_BASE,
	REASON_NO_ZONAL_INVARIANT,
	REASON_AGGREGATE_MULTI_OWNER,
	REASON_SINK_TRUNCATED,
]

## Material threshold, DERIVED, in units of FRACTION -- not kilograms. It is not
## inherited from any species: CO/CO2/HCN thresholds are masses, a different
## physical quantity.
## Upper bound, anchored on FED sensitivity rather than a rounded ppm: from
## ThermalSystem.gd the hypoxia FED accumulates dt_min*exp(-a + b*deficit) with
## b = fed_hypoxia_b = 0.54 and the deficit expressed in percentage points, so
## dFED/FED = b*100*d(fraction) = 54*d(fraction). A 1 % change in FED_hypoxia is
## 1.85e-4 of fraction.
## Lower bound: the fraction lives near 0.209, so double-precision noise is about
## 2e-17 per operation; accumulated over one step it is bounded by 1e-14.
## The geometric mean of the two bounds is 1.36e-9; 1.0e-9 is taken: 1e5 above the
## noise and 1.85e5 below a 1 % FED move. It only separates populations in the
## report; it governs no physics and no acceptance.
const MATERIAL_EPS_FRACTION: float = 1.0e-9

## Bounded detail sample. The accumulators are fixed-size and keep full coverage.
const SAMPLE_MAX: int = 256

enum EntryField {
	OWNER,
	ZONE,
	REASON_CODE,
	COMPLETENESS,
	KG_AVAILABLE,
	APPLICATIONS,
	STRICT_COUNT,
	MATERIAL_COUNT,
	CONFLICT_COUNT,
	REQUESTED_FRACTION_TOTAL,
	ACCEPTED_FRACTION_TOTAL,
	CORRECTION_FRACTION_ABS,
	CORRECTION_FRACTION_SIGNED,
	MAX_CORRECTION_FRACTION,
	ACCEPTED_KG_TOTAL,
	ROOMS,
	SIZE,
}

var enabled: bool = false

## Experimental flag state at measurement time. Set once by the owning component
## instead of being rebuilt per call: `record` runs in hot per-room, per-step
## loops and a dictionary allocation per call is not affordable.
var flags: Dictionary = {}

var _totals: Dictionary = {}
var _samples: Array[Dictionary] = []
var _overflow: int = 0
var _step: int = 0
var _last_owner: String = ""
var _last_zone: String = ""
var _last_entry: Array = []


func clear() -> void:
	_totals.clear()
	_samples.clear()
	_last_owner = ""
	_last_zone = ""
	_last_entry.clear()
	_overflow = 0
	_step = 0


func begin_step() -> void:
	_step += 1


func set_step(value: int) -> void:
	## Lets a component share the step index owned by another one, so a single
	## tick is one step number across every subsystem.
	_step = value


func get_step() -> int:
	return _step


func _entry_dictionary(entry: Array) -> Dictionary:
	return {
		"owner": String(entry[EntryField.OWNER]),
		"zone": String(entry[EntryField.ZONE]),
		"reason_code": String(entry[EntryField.REASON_CODE]),
		"completeness": bool(entry[EntryField.COMPLETENESS]),
		"kg_available": bool(entry[EntryField.KG_AVAILABLE]),
		"material_eps_fraction": MATERIAL_EPS_FRACTION,
		"unit": "fraction",
		"applications": int(entry[EntryField.APPLICATIONS]),
		"strict_count": int(entry[EntryField.STRICT_COUNT]),
		"material_count": int(entry[EntryField.MATERIAL_COUNT]),
		"conflict_count": int(entry[EntryField.CONFLICT_COUNT]),
		"requested_fraction_total": float(entry[EntryField.REQUESTED_FRACTION_TOTAL]),
		"accepted_fraction_total": float(entry[EntryField.ACCEPTED_FRACTION_TOTAL]),
		"correction_fraction_abs": float(entry[EntryField.CORRECTION_FRACTION_ABS]),
		"correction_fraction_signed": float(entry[EntryField.CORRECTION_FRACTION_SIGNED]),
		"max_correction_fraction": float(entry[EntryField.MAX_CORRECTION_FRACTION]),
		"accepted_kg_total": float(entry[EntryField.ACCEPTED_KG_TOTAL]),
		"rooms": Array(entry[EntryField.ROOMS]).duplicate(),
	}


func _totals_dictionary() -> Dictionary:
	var totals: Dictionary = {}
	for key in _totals.keys():
		totals[key] = _entry_dictionary(_totals[key])
	return totals


func summary(extra_flags: Dictionary = {}) -> Dictionary:
	## Opt-in export. With nothing observed the result is completely empty, so an
	## OFF run adds no key at all -- not even the threshold header.
	var out: Dictionary = {}
	if _totals.is_empty() and _samples.is_empty():
		return out
	out["totals"] = _totals_dictionary()
	out["samples"] = _samples.duplicate(true)
	out["sample_limit"] = SAMPLE_MAX
	out["sample_overflow"] = _overflow
	out["material_eps_fraction"] = MATERIAL_EPS_FRACTION
	out["unit"] = "fraction"
	var merged: Dictionary = flags.duplicate(true)
	merged.merge(extra_flags, true)
	out["flags"] = merged
	return out


func merge_totals_into(target: Dictionary) -> void:
	## Combines this ledger's accumulators into a shared table. Used only to build
	## the engine-level export; it never feeds a physical source.
	for key in _totals.keys():
		var src: Dictionary = _entry_dictionary(_totals[key])
		if not target.has(key):
			target[key] = src.duplicate(true)
			continue
		var dst: Dictionary = target[key]
		for counter in [
			"applications", "strict_count", "material_count", "conflict_count",
		]:
			dst[counter] = int(dst.get(counter, 0)) + int(src.get(counter, 0))
		for total in [
			"requested_fraction_total", "accepted_fraction_total",
			"correction_fraction_abs", "correction_fraction_signed",
			"accepted_kg_total",
		]:
			dst[total] = float(dst.get(total, 0.0)) + float(src.get(total, 0.0))
		dst["max_correction_fraction"] = maxf(
			float(dst.get("max_correction_fraction", 0.0)),
			float(src.get("max_correction_fraction", 0.0))
		)
		# Completeness is conjunctive: one incomplete contribution makes the
		# merged row incomplete.
		if String(dst.get("reason_code", "")) != String(src.get("reason_code", "")):
			dst["reason_code"] = REASON_CONFLICT
			dst["completeness"] = false
			dst["kg_available"] = false
		else:
			dst["completeness"] = bool(dst.get("completeness", false)) \
					and bool(src.get("completeness", false))
			dst["kg_available"] = bool(dst.get("kg_available", false)) \
					and bool(src.get("kg_available", false))
		for room_id in Array(src.get("rooms", [])):
			if not Array(dst["rooms"]).has(room_id):
				dst["rooms"].append(room_id)


func samples() -> Array:
	return _samples.duplicate(true)


func peek_samples() -> Array:
	## Internal read-only view used while assembling the final engine summary.
	## Callers must not retain or mutate it; `samples()` remains the defensive
	## public API. JSON serialization observes the same values either way.
	return _samples


func sample_overflow() -> int:
	return _overflow


func _entry(owner: String, zone: String, reason: String) -> Array:
	var entry: Array = []
	if owner == _last_owner and zone == _last_zone and not _last_entry.is_empty():
		entry = _last_entry
	else:
		var key: String = "%s|%s" % [owner, zone]
		if _totals.has(key):
			entry = _totals[key]
		else:
			var known: bool = VALID_REASONS.has(reason)
			entry.resize(EntryField.SIZE)
			entry.fill(0.0)
			entry[EntryField.OWNER] = owner
			entry[EntryField.ZONE] = zone
			entry[EntryField.REASON_CODE] = reason if known else REASON_CONFLICT
			entry[EntryField.COMPLETENESS] = known and reason == REASON_COMPLETE
			entry[EntryField.KG_AVAILABLE] = known and reason == REASON_COMPLETE
			for index in [
				EntryField.APPLICATIONS, EntryField.STRICT_COUNT,
				EntryField.MATERIAL_COUNT, EntryField.CONFLICT_COUNT,
			]:
				entry[index] = 0
			entry[EntryField.ROOMS] = []
			_totals[key] = entry
		_last_owner = owner
		_last_zone = zone
		_last_entry = entry
	# Conflict checking still runs on cache hits; caching never weakens the
	# fail-closed reason contract.
	if String(entry[EntryField.REASON_CODE]) != reason:
		entry[EntryField.REASON_CODE] = REASON_CONFLICT
		entry[EntryField.COMPLETENESS] = false
		entry[EntryField.KG_AVAILABLE] = false
		entry[EntryField.CONFLICT_COUNT] = int(entry[EntryField.CONFLICT_COUNT]) + 1
		entry[EntryField.ACCEPTED_KG_TOTAL] = 0.0
	return entry


func record(
		owner: String,
		zone: String,
		room,
		pre_fraction: float,
		requested_fraction: float,
		accepted_fraction: float,
		reason: String,
		mass_base_kg: float = NAN,
		mass_base_kind: String = "none"
	) -> void:
	## `requested_fraction` must be the pre-clamp value the site itself computed.
	## Passing a reconstruction would defeat the whole measurement.
	if not enabled:
		return
	var entry: Array = _entry(owner, zone, reason)
	entry[EntryField.APPLICATIONS] = int(entry[EntryField.APPLICATIONS]) + 1
	entry[EntryField.REQUESTED_FRACTION_TOTAL] = \
			float(entry[EntryField.REQUESTED_FRACTION_TOTAL]) \
			+ (requested_fraction - pre_fraction)
	entry[EntryField.ACCEPTED_FRACTION_TOTAL] = \
			float(entry[EntryField.ACCEPTED_FRACTION_TOTAL]) \
			+ (accepted_fraction - pre_fraction)
	var correction: float = accepted_fraction - requested_fraction
	var magnitude: float = absf(correction)
	var strict_bound: bool = correction != 0.0
	var material_bound: bool = magnitude > MATERIAL_EPS_FRACTION
	var complete: bool = bool(entry[EntryField.KG_AVAILABLE]) and not is_nan(mass_base_kg)
	if complete:
		entry[EntryField.ACCEPTED_KG_TOTAL] = \
				float(entry[EntryField.ACCEPTED_KG_TOTAL]) \
				+ (accepted_fraction - pre_fraction) * mass_base_kg
	if strict_bound:
		entry[EntryField.STRICT_COUNT] = int(entry[EntryField.STRICT_COUNT]) + 1
		entry[EntryField.CORRECTION_FRACTION_ABS] = \
				float(entry[EntryField.CORRECTION_FRACTION_ABS]) + magnitude
		entry[EntryField.CORRECTION_FRACTION_SIGNED] = \
				float(entry[EntryField.CORRECTION_FRACTION_SIGNED]) + correction
		entry[EntryField.MAX_CORRECTION_FRACTION] = maxf(
			float(entry[EntryField.MAX_CORRECTION_FRACTION]), magnitude
		)
		if material_bound:
			entry[EntryField.MATERIAL_COUNT] = int(entry[EntryField.MATERIAL_COUNT]) + 1
		if room != null and not Array(entry[EntryField.ROOMS]).has(room.id):
			entry[EntryField.ROOMS].append(room.id)
	_totals["%s|%s" % [owner, zone]] = entry
	if not strict_bound:
		return
	if _samples.size() >= SAMPLE_MAX:
		_overflow += 1
		return
	_samples.append({
		"step": _step,
		"room_id": room.id if room != null else -1,
		"owner": owner,
		"zone": zone,
		"unit": "fraction",
		"pre_fraction": pre_fraction,
		"requested_fraction": requested_fraction,
		"accepted_fraction": accepted_fraction,
		"correction_fraction": correction,
		"rejected_fraction": requested_fraction - accepted_fraction,
		"accepted_kg": (accepted_fraction - pre_fraction) * mass_base_kg if complete else null,
		"mass_base_kg": mass_base_kg if complete else null,
		"mass_base_kind": mass_base_kind,
		"strict_bound": strict_bound,
		"material_bound": material_bound,
		"material_eps_fraction": MATERIAL_EPS_FRACTION,
		"reason_code": String(entry[EntryField.REASON_CODE]),
		"completeness": complete,
		"flags": flags,
	})
