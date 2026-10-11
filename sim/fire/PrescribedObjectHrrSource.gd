extends RefCounted

## Isolated replay of ONE measured heat release run of ONE object, whole, as it
## was tested in open air. NOT a fire model, not a prediction, and not connected
## to the engine, the room fire, any gas balance, transport, editor or product.
## The table is a measured input: this owner returns it and integrates it.
## Outside the approved support every request is refused; nothing is
## extrapolated, held or clipped here. Negative samples are refused: clipping
## calorimeter noise belongs to the offline importer, which declares it.
## Mass, species, composition and radiative fraction are unknown and stay null.
## Proposing is pure. Confirming counts an interval once and advances the clock
## even when part of its energy was rejected. Rejected energy is recorded,
## never queued or recovered, and no physical cause is attached to it.
## No I/O, no engine type, no node: the only state is the validated table and
## this owner's own clock and counters, replaced as one value or not at all.
const VERSION: String = "prescribed_object_hrr_source_v1"
const SOURCE_SCHEMA: String = "g3_prescribed_object_hrr_source_v1"
const PROPOSAL_SCHEMA: String = "g3_prescribed_object_hrr_proposal_v1"
const SNAPSHOT_SCHEMA: String = "g3_prescribed_object_hrr_snapshot_v1"
const SCOPE: String = "isolated_replay_of_one_measured_open_air_run_not_prediction"
## Declared conversion: one kilowatt during one second is one kilojoule.
const KJ_PER_KW_S: float = 1.0
## Numerical tolerances of the counters. They are not experimental uncertainty.
const ENERGY_ABS_TOL_KJ: float = 1.0e-9
const REL_TOL: float = 1.0e-12
const SOURCE_KEYS: Array[String] = [
	"schema", "owner_id", "run_id", "quantity", "time_unit", "hrr_unit", "energy_unit",
	"time_origin", "interpolation", "outside_support", "negative_samples", "regime",
	"provenance", "unknown", "samples",
]
const SOURCE_LITERALS: Dictionary = {
	"schema": SOURCE_SCHEMA, "quantity": "measured_calorimetric_hrr", "time_unit": "s",
	"hrr_unit": "kW", "energy_unit": "kJ", "time_origin": "documented_ignition_event",
	"interpolation": "piecewise_linear", "outside_support": "reject", "regime": "open_air_as_tested",
}
## What the importer did with negative readings. Either way none reaches this owner.
const NEGATIVE_DECLARATIONS: Array[String] = ["none_in_source", "clipped_to_zero_offline"]
const PROVENANCE_KEYS: Array[String] = [
	"dataset", "dataset_version", "license", "source_file", "source_sha256", "source_column",
	"support_events", "importer", "table_fingerprint",
]
const DIGEST_KEYS: Array[String] = ["source_sha256", "table_fingerprint"]
const UNKNOWN_KEYS: Array[String] = ["mass_loss_rate", "species_yields", "composition", "radiative_fraction"]
const SAMPLE_KEYS: Array[String] = ["time_s", "hrr_kw"]
const PROPOSAL_KEYS: Array[String] = [
	"schema", "owner_id", "run_id", "source_fingerprint", "generation",
	"start_time_s", "end_time_s", "dt_s", "energy_kj",
]
const SNAPSHOT_KEYS: Array[String] = [
	"schema", "owner_id", "run_id", "source_fingerprint", "generation",
	"time_s", "scheduled_kj", "accepted_kj", "rejected_kj",
]
var _source: Dictionary = {}
var _fingerprint: String = ""
var _times: PackedFloat64Array = PackedFloat64Array()
var _hrr: PackedFloat64Array = PackedFloat64Array()
var _prefix_kj: PackedFloat64Array = PackedFloat64Array()
var _state: Dictionary = {}


## Validates the whole source and takes ownership of a private copy. One source
## per owner: a second call is refused. A refusal leaves the owner unopened.
func open(source: Variant) -> Dictionary:
	if not _state.is_empty():
		return _refusal(["already opened; use a new owner for another source"])
	var errors: Array[String] = []
	var s: Dictionary = _object(source, SOURCE_KEYS, "source", errors)
	for key: String in SOURCE_LITERALS:
		_literal(s.get(key), SOURCE_LITERALS[key], key, errors)
	if typeof(s.get("negative_samples")) != TYPE_STRING or s["negative_samples"] not in NEGATIVE_DECLARATIONS:
		errors.append("negative_samples must declare what the importer did")
	_text(s.get("owner_id"), "owner_id", errors)
	_text(s.get("run_id"), "run_id", errors)
	var provenance: Dictionary = _object(s.get("provenance"), PROVENANCE_KEYS, "provenance", errors)
	for key: String in PROVENANCE_KEYS:
		_text(provenance.get(key), "provenance." + key, errors)
	for key: String in DIGEST_KEYS:
		if typeof(provenance.get(key)) == TYPE_STRING and not _is_digest(provenance[key]):
			errors.append("provenance." + key + " must be a lowercase SHA-256")
	var unknown: Dictionary = _object(s.get("unknown"), UNKNOWN_KEYS, "unknown", errors)
	for key: String in UNKNOWN_KEYS:
		if typeof(unknown.get(key)) != TYPE_NIL:
			errors.append("unknown." + key + " must stay null: an unknown quantity is not a number, and not zero")
	var times: PackedFloat64Array = PackedFloat64Array()
	var hrr: PackedFloat64Array = PackedFloat64Array()
	var raw: Variant = s.get("samples")
	if typeof(raw) != TYPE_ARRAY or raw.size() < 2:
		errors.append("samples must be an array with at least two points")
	if not errors.is_empty():
		return _refusal(errors)
	for item: Variant in raw:
		var point: Dictionary = _object(item, SAMPLE_KEYS, "sample", errors)
		var time_s: float = _number(point.get("time_s"), "sample time_s", errors)
		var value: float = _number(point.get("hrr_kw"), "sample hrr_kw", errors)
		if not times.is_empty() and time_s <= times[times.size() - 1]:
			errors.append("sample times must strictly increase")
		# One bad sample is enough; a long table must not flood the report.
		if not errors.is_empty():
			return _refusal(errors)
		times.append(time_s)
		hrr.append(value)
	if times[0] != 0.0:
		return _refusal(["the support must start at the documented ignition, time zero; no shift is applied"])
	var prefix: PackedFloat64Array = PackedFloat64Array([0.0])
	for i: int in range(times.size() - 1):
		prefix.append(prefix[i] + _segment_kj(times, hrr, i, times[i], times[i + 1]))
	if not _finite(prefix[prefix.size() - 1]):
		return _refusal(["the energy of the table is not finite"])
	var canonical: Dictionary = _canonical(s)
	_source = canonical
	_fingerprint = (VERSION + _serialize(canonical)).sha256_text()
	_times = times
	_hrr = hrr
	_prefix_kj = prefix
	_state = {"generation": 0, "time_s": 0.0, "scheduled_kj": 0.0, "accepted_kj": 0.0, "rejected_kj": 0.0}
	return {"valid": true, "errors": [], "report": report()}


## What this owner is, what it reads and what it does not know. Empty before open.
func report() -> Dictionary:
	if _state.is_empty():
		return {}
	var unknown: Dictionary = {}
	for key: String in UNKNOWN_KEYS:
		unknown[key] = null
	return {
		"version": VERSION, "scope": SCOPE, "owner_id": _source["owner_id"], "run_id": _source["run_id"],
		"source_fingerprint": _fingerprint, "quantity": _source["quantity"],
		"units": {"time": _source["time_unit"], "hrr": _source["hrr_unit"], "energy": _source["energy_unit"]},
		"kj_per_kw_s": KJ_PER_KW_S, "interpolation": _source["interpolation"],
		"outside_support": _source["outside_support"], "negative_samples": _source["negative_samples"],
		"regime": _source["regime"], "support_s": [_times[0], _support_end()], "samples": _times.size(),
		"table_energy_kj": _prefix_kj[_prefix_kj.size() - 1], "unknown": unknown,
		"rejected_energy": "recorded_not_queued_no_physical_cause_attached",
		"predictive": false, "valid_in_an_enclosure": false, "engine_integration": false,
		"product_activation": false, "co_fed_approval": false, "state": snapshot(),
	}


## The measured table at one time since ignition. Outside the support it is refused.
func hrr_kw(time_s: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _opened(errors):
		return _refusal(errors)
	var at: float = _number(time_s, "time_s", errors)
	if errors.is_empty() and at > _support_end():
		errors.append("time is outside the approved support; nothing is extrapolated or held")
	if not errors.is_empty():
		return _refusal(errors)
	return {"valid": true, "errors": [], "time_s": at, "hrr_kw": _value(_segment_of(at), at)}


## Pure. From the committed time to an absolute end time. It delivers nothing
## and counts nothing: only a confirmation does.
func propose(end_time_s: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _opened(errors):
		return _refusal(errors)
	var end: float = _number(end_time_s, "end_time_s", errors)
	if not errors.is_empty():
		return _refusal(errors)
	var start: float = _state["time_s"]
	if end <= start:
		return _refusal(["the interval must have a positive duration after the committed time"])
	if end > _support_end():
		return _refusal(["the interval ends outside the approved support; nothing is extrapolated, held or clipped"])
	var energy: float = _interval_kj(start, end)
	if not _finite(energy) or energy < 0.0 or not _near(float(_state["scheduled_kj"]) + energy, _cumulative_kj(end)):
		return _refusal(["interval and cumulative integrals disagree"])
	return {"valid": true, "errors": [], "proposal": {
		"schema": PROPOSAL_SCHEMA, "owner_id": _source["owner_id"], "run_id": _source["run_id"],
		"source_fingerprint": _fingerprint, "generation": _state["generation"],
		"start_time_s": start, "end_time_s": end, "dt_s": end - start, "energy_kj": energy,
	}}


## Counts one proposed interval, once. The proposal is rebuilt from the current
## state and must match it: one that is stale, already confirmed, altered or
## issued for another owner is refused and nothing changes.
func confirm(proposal: Variant, accepted_energy_kj: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _opened(errors):
		return _refusal(errors)
	var p: Dictionary = _object(proposal, PROPOSAL_KEYS, "proposal", errors)
	if not errors.is_empty():
		return _refusal(errors)
	_literal(p["schema"], PROPOSAL_SCHEMA, "proposal schema", errors)
	if not _is_mine(p):
		errors.append("the proposal belongs to another owner, run or source")
	if not errors.is_empty():
		return _refusal(errors)
	if typeof(p["generation"]) != TYPE_INT or p["generation"] != _state["generation"]:
		return _refusal(["the proposal is stale or already confirmed; ask for a new one"])
	var current: Dictionary = propose(p["end_time_s"])
	if not _positive(current):
		return _refusal(["the proposal cannot be rebuilt: " + str(current.get("errors"))])
	var rebuilt: Dictionary = current["proposal"]
	for key: String in ["start_time_s", "end_time_s", "dt_s", "energy_kj"]:
		if typeof(p[key]) != TYPE_FLOAT or p[key] != rebuilt[key]:
			errors.append("the proposal was altered: " + key)
	var accepted: float = _number(accepted_energy_kj, "accepted_energy_kj", errors)
	var scheduled: float = rebuilt["energy_kj"]
	if accepted > scheduled:
		errors.append("accepted energy exceeds the proposed interval")
	if not errors.is_empty():
		return _refusal(errors)
	var rejected: float = scheduled - accepted
	var candidate: Dictionary = {
		"generation": int(_state["generation"]) + 1, "time_s": float(rebuilt["end_time_s"]),
		"scheduled_kj": _cumulative_kj(rebuilt["end_time_s"]),
		"accepted_kj": float(_state["accepted_kj"]) + accepted,
		"rejected_kj": float(_state["rejected_kj"]) + rejected,
	}
	if not _near(candidate["accepted_kj"] + candidate["rejected_kj"], candidate["scheduled_kj"]):
		return _refusal(["confirmed counters do not close"])
	_state = candidate
	return {"valid": true, "errors": [], "scheduled_this_step_kj": scheduled, "accepted_this_step_kj": accepted,
		"rejected_this_step_kj": rejected, "state": snapshot()}


## The owner's clock and counters, as a value. Empty before open.
func snapshot() -> Dictionary:
	if _state.is_empty():
		return {}
	return {
		"schema": SNAPSHOT_SCHEMA, "owner_id": _source["owner_id"], "run_id": _source["run_id"],
		"source_fingerprint": _fingerprint, "generation": _state["generation"],
		"time_s": _state["time_s"], "scheduled_kj": _state["scheduled_kj"],
		"accepted_kj": _state["accepted_kj"], "rejected_kj": _state["rejected_kj"],
	}


## Explicit rewind or rebuild: replaces clock and counters with a snapshot of
## this same source, here or in a previous owner. Energy counted after the
## snapshot is discarded because the caller asked for it. Every proposal issued
## before, by either lineage, becomes stale.
func restore(saved: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not _opened(errors):
		return _refusal(errors)
	var s: Dictionary = _object(saved, SNAPSHOT_KEYS, "snapshot", errors)
	if not errors.is_empty():
		return _refusal(errors)
	_literal(s["schema"], SNAPSHOT_SCHEMA, "snapshot schema", errors)
	if not _is_mine(s):
		errors.append("the snapshot belongs to another owner, run or source")
	if typeof(s["generation"]) != TYPE_INT or s["generation"] < 0:
		errors.append("snapshot generation must be a non-negative integer")
	var time_s: float = _number(s["time_s"], "snapshot time_s", errors)
	var scheduled: float = _number(s["scheduled_kj"], "snapshot scheduled_kj", errors)
	var accepted: float = _number(s["accepted_kj"], "snapshot accepted_kj", errors)
	var rejected: float = _number(s["rejected_kj"], "snapshot rejected_kj", errors)
	if not errors.is_empty():
		return _refusal(errors)
	if time_s > _support_end():
		return _refusal(["snapshot time is outside the approved support"])
	if not _near(scheduled, _cumulative_kj(time_s)) or not _near(accepted + rejected, scheduled):
		return _refusal(["snapshot counters disagree with the table"])
	_state = {
		"generation": maxi(int(_state["generation"]), int(s["generation"])) + 1, "time_s": time_s,
		"scheduled_kj": _cumulative_kj(time_s), "accepted_kj": accepted, "rejected_kj": rejected,
	}
	return {"valid": true, "errors": [], "state": snapshot()}


## Explicit restart at ignition with empty counters. Earlier proposals become stale.
func reset() -> Dictionary:
	var errors: Array[String] = []
	if not _opened(errors):
		return _refusal(errors)
	_state = {"generation": int(_state["generation"]) + 1, "time_s": 0.0,
		"scheduled_kj": 0.0, "accepted_kj": 0.0, "rejected_kj": 0.0}
	return {"valid": true, "errors": [], "state": snapshot()}


func _opened(errors: Array[String]) -> bool:
	if _state.is_empty():
		errors.append("the source is not open")
	return not _state.is_empty()


func _support_end() -> float:
	return _times[_times.size() - 1]


func _is_mine(record: Dictionary) -> bool:
	return (_same_text(record["owner_id"], _source["owner_id"]) and _same_text(record["run_id"], _source["run_id"])
		and _same_text(record["source_fingerprint"], _fingerprint))


## Index of the segment that holds a time of the support; a node belongs to the one it closes.
func _segment_of(time_s: float) -> int:
	return clampi(_times.bsearch(time_s) - 1, 0, _times.size() - 2)


func _value(segment: int, time_s: float) -> float:
	var a: float = (time_s - _times[segment]) / (_times[segment + 1] - _times[segment])
	return (1.0 - a) * _hrr[segment] + a * _hrr[segment + 1]


## Exact integral of the piecewise linear table between two times of the support.
func _interval_kj(start: float, end: float) -> float:
	var total: float = 0.0
	var segment: int = _segment_of(start)
	while segment < _times.size() - 1 and _times[segment] < end:
		var lo: float = maxf(start, _times[segment])
		var hi: float = minf(end, _times[segment + 1])
		if hi > lo:
			total += _segment_kj(_times, _hrr, segment, lo, hi)
		segment += 1
	return total


## Energy from ignition to a time of the support: whole segments plus the open one.
func _cumulative_kj(time_s: float) -> float:
	var segment: int = _segment_of(time_s)
	return _prefix_kj[segment] + _segment_kj(_times, _hrr, segment, _times[segment], time_s)


## Trapezoid of one linear segment between two of its times. Exact for a line.
static func _segment_kj(times: PackedFloat64Array, hrr: PackedFloat64Array, segment: int, lo: float, hi: float) -> float:
	var t0: float = times[segment]
	var span: float = times[segment + 1] - t0
	var a: float = (lo - t0) / span
	var b: float = (hi - t0) / span
	var left: float = (1.0 - a) * hrr[segment] + a * hrr[segment + 1]
	var right: float = (1.0 - b) * hrr[segment] + b * hrr[segment + 1]
	return KJ_PER_KW_S * (hi - lo) * (0.5 * left + 0.5 * right)


static func _object(value: Variant, keys: Array[String], label: String, errors: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append(label + " must be a dictionary")
		return {}
	if value.size() != keys.size():
		errors.append(label + " has missing or extra fields")
	for key: String in keys:
		if not value.has(key):
			errors.append(label + " is missing " + key)
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			errors.append(label + " has an unsupported key")
	return value


## Finite and not negative. A boolean or a text is not a number.
static func _number(value: Variant, label: String, errors: Array[String]) -> float:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		errors.append(label + " must be a number")
		return 0.0
	var number: float = float(value)
	if not _finite(number) or number < 0.0:
		errors.append(label + " must be finite and not negative")
		return 0.0
	return number


static func _text(value: Variant, label: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or value.strip_edges().is_empty():
		errors.append(label + " must be a nonempty text")


# Type first: comparing a number, a boolean or a container with a text aborts the script.
static func _literal(value: Variant, expected: String, label: String, errors: Array[String]) -> void:
	if not _same_text(value, expected):
		errors.append("unsupported " + label)


static func _same_text(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected


static func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _near(a: float, b: float) -> bool:
	return _finite(a) and _finite(b) and absf(a - b) <= ENERGY_ABS_TOL_KJ + REL_TOL * maxf(absf(a), absf(b))


## An explicit positive verdict. A call that aborted returns an empty value, which is not one.
static func _positive(result: Variant) -> bool:
	return typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result["valid"]


static func _refusal(errors: Array[String]) -> Dictionary:
	return {"valid": false, "errors": errors}


## Deep copy with every number as a 64-bit float, as the table is read.
static func _canonical(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value:
				result[key] = _canonical(value[key])
			return result
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_canonical(item))
			return items
		TYPE_INT:
			return float(value)
	return value


## Identity text of the whole content: sorted keys, numbers bit by bit.
static func _serialize(value: Variant) -> String:
	var parts: PackedStringArray = PackedStringArray()
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			for key: Variant in keys:
				parts.append(JSON.stringify(str(key)) + ":" + _serialize(value[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			for item: Variant in value:
				parts.append(_serialize(item))
			return "[" + ",".join(parts) + "]"
		TYPE_FLOAT:
			var number: float = absf(value) if value == 0.0 else value
			return "f64:" + PackedFloat64Array([number]).to_byte_array().hex_encode()
		TYPE_STRING:
			return JSON.stringify(value)
		TYPE_NIL:
			return "null"
	return "unsupported:" + str(typeof(value))
