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

var enabled: bool = false

## Experimental flag state at measurement time. Set once by the owning component
## instead of being rebuilt per call: `record` runs in hot per-room, per-step
## loops and a dictionary allocation per call is not affordable.
var flags: Dictionary = {}

var _totals: Dictionary = {}
var _samples: Array[Dictionary] = []
var _overflow: int = 0
var _step: int = 0


func clear() -> void:
	_totals.clear()
	_samples.clear()
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


func summary(extra_flags: Dictionary = {}) -> Dictionary:
	## Opt-in export. With nothing observed the result is completely empty, so an
	## OFF run adds no key at all -- not even the threshold header.
	var out: Dictionary = {}
	if _totals.is_empty() and _samples.is_empty():
		return out
	out["totals"] = _totals.duplicate(true)
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
		var src: Dictionary = _totals[key]
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


func sample_overflow() -> int:
	return _overflow


func _entry(owner: String, zone: String, reason: String) -> Dictionary:
	var key: String = "%s|%s" % [owner, zone]
	if not _totals.has(key):
		var known: bool = VALID_REASONS.has(reason)
		_totals[key] = {
			"owner": owner,
			"zone": zone,
			"reason_code": reason if known else REASON_CONFLICT,
			# An unknown reason code is treated as incomplete, never as complete.
			"completeness": known and reason == REASON_COMPLETE,
			"kg_available": known and reason == REASON_COMPLETE,
			"material_eps_fraction": MATERIAL_EPS_FRACTION,
			"unit": "fraction",
			"applications": 0,
			"strict_count": 0,
			"material_count": 0,
			"conflict_count": 0,
			"requested_fraction_total": 0.0,
			"accepted_fraction_total": 0.0,
			"correction_fraction_abs": 0.0,
			"correction_fraction_signed": 0.0,
			"max_correction_fraction": 0.0,
			"accepted_kg_total": 0.0,
			"rooms": [],
		}
		return _totals[key]
	var entry: Dictionary = _totals[key]
	# Fail-closed: a second, different reason for the same owner and zone means
	# the key does not describe one homogeneous population. Downgrade rather than
	# let the first reason stand and keep publishing kilograms.
	if String(entry["reason_code"]) != reason:
		entry["reason_code"] = REASON_CONFLICT
		entry["completeness"] = false
		entry["kg_available"] = false
		entry["conflict_count"] = int(entry["conflict_count"]) + 1
		entry["accepted_kg_total"] = 0.0
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
	var entry: Dictionary = _entry(owner, zone, reason)
	entry["applications"] = int(entry["applications"]) + 1
	entry["requested_fraction_total"] = \
			float(entry["requested_fraction_total"]) + (requested_fraction - pre_fraction)
	entry["accepted_fraction_total"] = \
			float(entry["accepted_fraction_total"]) + (accepted_fraction - pre_fraction)
	var correction: float = accepted_fraction - requested_fraction
	var magnitude: float = absf(correction)
	var strict_bound: bool = correction != 0.0
	var material_bound: bool = magnitude > MATERIAL_EPS_FRACTION
	var complete: bool = bool(entry["kg_available"]) and not is_nan(mass_base_kg)
	if complete:
		entry["accepted_kg_total"] = float(entry["accepted_kg_total"]) \
				+ (accepted_fraction - pre_fraction) * mass_base_kg
	if strict_bound:
		entry["strict_count"] = int(entry["strict_count"]) + 1
		entry["correction_fraction_abs"] = \
				float(entry["correction_fraction_abs"]) + magnitude
		entry["correction_fraction_signed"] = \
				float(entry["correction_fraction_signed"]) + correction
		entry["max_correction_fraction"] = maxf(
			float(entry["max_correction_fraction"]), magnitude
		)
		if material_bound:
			entry["material_count"] = int(entry["material_count"]) + 1
		if room != null and not Array(entry["rooms"]).has(room.id):
			entry["rooms"].append(room.id)
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
		"reason_code": String(entry["reason_code"]),
		"completeness": complete,
		"flags": flags,
	})
