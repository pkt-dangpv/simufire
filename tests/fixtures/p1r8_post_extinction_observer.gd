extends RefCounted

const INSUFFICIENT_POST_EXTINCTION_WINDOW := "INSUFFICIENT_POST_EXTINCTION_WINDOW"
const MISSING_ROOM := "MISSING_ROOM"
const NONFINITE_VALUE := "NONFINITE_VALUE"
const NON_MONOTONIC_SAMPLE := "NON_MONOTONIC_SAMPLE"
const NON_MONOTONIC_COUNTER := "NON_MONOTONIC_COUNTER"
const NO_INCIDENT := "NO_INCIDENT"
const NO_EXTINCTION := "NO_EXTINCTION"
const INCOMPLETE_END := "INCOMPLETE_END"
const MALFORMED_SAMPLE := "MALFORMED_SAMPLE"

const _GLOBAL_SMOKE_FIELDS := [
	"smoke_generated_total_kg",
	"smoke_vented_total_kg",
	"smoke_deposited_total_kg",
]
const _SMOKE_TRANSIT_FIELD := "smoke_in_transit_kg"
const _ROOM_NUMERIC_FIELDS := ["hrr_kw", "temp_upper_c", "smoke_kg"]

var _expected_room_ids: Array[int] = []
var _invalid_reason: String = ""
var _sample_count: int = 0
var _last_tick: int = -1
var _last_time_s: float = -1.0
var _incident_seen: bool = false
var _extinction_tick = null
var _extinction_time_s = null
var _post_extinction_sample_count: int = 0
var _previous_any_fire: bool = false
var _previous_temps: Dictionary = {}
var _reignition_events: Array[Dictionary] = []
var _max_positive_temp_step_c: Dictionary = {}
var _cumulative_positive_temp_rise_c: Dictionary = {}
var _initial_smoke_stock_kg: float = 0.0
var _initial_smoke_in_transit_kg: float = 0.0
var _initial_smoke_counters: Dictionary = {}
var _latest_smoke_stock_kg: float = 0.0
var _latest_smoke_in_transit_kg: float = 0.0
var _latest_smoke_counters: Dictionary = {}


func _init(expected_room_ids: Array[int]) -> void:
	_expected_room_ids = expected_room_ids.duplicate()
	_expected_room_ids.sort()
	if _expected_room_ids.is_empty():
		_invalid_reason = MALFORMED_SAMPLE


func observe(state: Dictionary) -> bool:
	if not _invalid_reason.is_empty():
		return false
	if not state.has("tick_index") or not state.has("sim_time_s"):
		return _invalidate(MALFORMED_SAMPLE)
	if typeof(state["tick_index"]) != TYPE_INT or not _finite_number(state["sim_time_s"]):
		return _invalidate(MALFORMED_SAMPLE)

	var tick: int = int(state["tick_index"])
	var time_s: float = float(state["sim_time_s"])
	if _sample_count > 0 and (tick <= _last_tick or time_s <= _last_time_s):
		return _invalidate(NON_MONOTONIC_SAMPLE)

	var rooms: Dictionary = {}
	var smoke_stock_kg: float = 0.0
	var any_fire: bool = false
	for room_id in _expected_room_ids:
		var key: String = str(room_id)
		if not state.has(key) or typeof(state[key]) != TYPE_DICTIONARY:
			return _invalidate(MISSING_ROOM)
		var room: Dictionary = state[key]
		if not room.has("has_fire") or typeof(room["has_fire"]) != TYPE_BOOL:
			return _invalidate(MALFORMED_SAMPLE)
		for field in _ROOM_NUMERIC_FIELDS:
			if not room.has(field):
				return _invalidate(MALFORMED_SAMPLE)
			if not _finite_number(room[field]):
				return _invalidate(NONFINITE_VALUE)
		rooms[room_id] = room
		any_fire = any_fire or bool(room["has_fire"])
		smoke_stock_kg += float(room["smoke_kg"])

	var counters: Dictionary = {}
	for field in _GLOBAL_SMOKE_FIELDS:
		if not state.has(field):
			return _invalidate(MALFORMED_SAMPLE)
		if not _finite_number(state[field]):
			return _invalidate(NONFINITE_VALUE)
		counters[field] = float(state[field])
		if _sample_count > 0 and counters[field] < float(_latest_smoke_counters[field]):
			return _invalidate(NON_MONOTONIC_COUNTER)
	if not state.has(_SMOKE_TRANSIT_FIELD):
		return _invalidate(MALFORMED_SAMPLE)
	if not _finite_number(state[_SMOKE_TRANSIT_FIELD]):
		return _invalidate(NONFINITE_VALUE)
	var smoke_in_transit_kg: float = float(state[_SMOKE_TRANSIT_FIELD])
	if smoke_in_transit_kg < 0.0:
		return _invalidate(MALFORMED_SAMPLE)

	if _sample_count == 0:
		_initial_smoke_stock_kg = smoke_stock_kg
		_initial_smoke_in_transit_kg = smoke_in_transit_kg
		_initial_smoke_counters = counters.duplicate()
	if any_fire:
		_incident_seen = true

	if _incident_seen and _extinction_tick == null and not any_fire:
		_extinction_tick = tick
		_extinction_time_s = time_s
		for room_id in _expected_room_ids:
			_previous_temps[room_id] = float(rooms[room_id]["temp_upper_c"])
			_max_positive_temp_step_c[room_id] = 0.0
			_cumulative_positive_temp_rise_c[room_id] = 0.0
	elif _extinction_tick != null:
		_post_extinction_sample_count += 1
		if any_fire and not _previous_any_fire:
			_reignition_events.append({"tick_index": tick, "sim_time_s": time_s})
		for room_id in _expected_room_ids:
			var current_temp_c: float = float(rooms[room_id]["temp_upper_c"])
			var previous_temp_c: float = float(_previous_temps[room_id])
			var positive_rise_c: float = maxf(0.0, current_temp_c - previous_temp_c)
			_max_positive_temp_step_c[room_id] = maxf(
				float(_max_positive_temp_step_c[room_id]), positive_rise_c
			)
			_cumulative_positive_temp_rise_c[room_id] = (
				float(_cumulative_positive_temp_rise_c[room_id]) + positive_rise_c
			)
			_previous_temps[room_id] = current_temp_c

	_latest_smoke_stock_kg = smoke_stock_kg
	_latest_smoke_in_transit_kg = smoke_in_transit_kg
	_latest_smoke_counters = counters.duplicate()
	_previous_any_fire = any_fire
	_last_tick = tick
	_last_time_s = time_s
	_sample_count += 1
	return true


func finalize(expected_final_tick: int, expected_final_time_s: float) -> Dictionary:
	if not _invalid_reason.is_empty():
		return _invalid(_invalid_reason)
	if not _incident_seen:
		return _invalid(NO_INCIDENT)
	if _extinction_tick == null:
		return _invalid(NO_EXTINCTION)
	if _post_extinction_sample_count < 1:
		return _invalid(INSUFFICIENT_POST_EXTINCTION_WINDOW)
	if _last_tick != expected_final_tick or not is_equal_approx(_last_time_s, expected_final_time_s):
		return _invalid(INCOMPLETE_END)

	var inventory_delta_kg: float = (
		_latest_smoke_stock_kg + _latest_smoke_in_transit_kg
		- _initial_smoke_stock_kg - _initial_smoke_in_transit_kg
	)
	var generated_delta_kg: float = (
		float(_latest_smoke_counters["smoke_generated_total_kg"])
		- float(_initial_smoke_counters["smoke_generated_total_kg"])
	)
	var vented_delta_kg: float = (
		float(_latest_smoke_counters["smoke_vented_total_kg"])
		- float(_initial_smoke_counters["smoke_vented_total_kg"])
	)
	var deposited_delta_kg: float = (
		float(_latest_smoke_counters["smoke_deposited_total_kg"])
		- float(_initial_smoke_counters["smoke_deposited_total_kg"])
	)
	return {
		"valid": true,
		"reason": null,
		"sample_count": _sample_count,
		"post_extinction_sample_count": _post_extinction_sample_count,
		"extinction_tick": _extinction_tick,
		"extinction_time_s": _extinction_time_s,
		"reignition_events": _reignition_events.duplicate(true),
		"all_room_smoke_stock_kg": _latest_smoke_stock_kg,
		"smoke_in_transit_kg": _latest_smoke_in_transit_kg,
		"smoke_accounting_residual_kg": (
			inventory_delta_kg + vented_delta_kg + deposited_delta_kg - generated_delta_kg
		),
		"max_positive_temp_step_c": _max_positive_temp_step_c.duplicate(true),
		"cumulative_positive_temp_rise_c": _cumulative_positive_temp_rise_c.duplicate(true),
	}


func _finite_number(value) -> bool:
	var kind: int = typeof(value)
	return (kind == TYPE_INT or kind == TYPE_FLOAT) and is_finite(float(value))


func _invalidate(reason: String) -> bool:
	_invalid_reason = reason
	return false


func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
