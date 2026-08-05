extends SceneTree

## H3.2-S0d5a2 fixture: causal trace of the first CO `upper > bulk` crossing.
##
## The trace observes writers; it never repairs, never attributes by stage
## difference and never promotes a strict floating-point crossing to a material
## violation.

const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_default_off_records_nothing()
	_test_first_crossing_is_captured_once()
	_test_valid_state_produces_no_finding()
	_test_inherited_violation_is_not_a_new_creation()
	_test_resolution_is_visible()
	_test_writer_is_mandatory_and_carried()
	_test_material_threshold_separates_noise()
	_test_sample_cap_is_bounded()
	_test_export_is_pure_and_deterministic()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D5A2_CO_VIOLATION_TRACE_PASS")
	quit(0)


func _test_default_off_records_nothing() -> void:
	var gas = GasExchangeSystemScript.new()
	_expect(
		not gas.phase3_co_first_violation_trace_enabled,
		"trace flag defaults false"
	)
	var room = _room(0, 1.0, 2.0)
	gas._co_trace("probe", room)
	var trace: Dictionary = gas.get_phase3_co_violation_trace()
	_expect(trace["by_writer"].is_empty(), "OFF records no writer")
	_expect(trace["first_events"].is_empty(), "OFF records no sample")


func _test_first_crossing_is_captured_once() -> void:
	var gas = _gas()
	var room = _room(0, 1.0, 0.4)
	gas._co_trace("writer_a", room)
	room.co_upper_kg = 1.5
	gas._co_trace("writer_b", room)
	# Still invalid: a second observation must not count as a new creation.
	gas._co_trace("writer_c", room)
	var trace: Dictionary = gas.get_phase3_co_violation_trace()
	var by_writer: Dictionary = trace["by_writer"]
	_expect(int(by_writer["writer_b"]["new_violations"]) == 1, "writer_b creates once")
	_expect(int(by_writer["writer_c"]["new_violations"]) == 0, "writer_c creates nothing")
	_expect(int(by_writer["writer_c"]["inherited"]) == 1, "writer_c inherits")
	_expect(trace["first_events"].size() == 1, "one sample for one crossing")
	var sample: Dictionary = trace["first_events"][0]
	_expect(String(sample["writer"]) == "writer_b", "sample names the creating writer")
	_expect(int(sample["room_id"]) == 0, "sample names the room")
	_expect(absf(float(sample["excess_kg"]) - 0.5) <= 1.0e-12, "sample carries the excess")


func _test_valid_state_produces_no_finding() -> void:
	var gas = _gas()
	var room = _room(0, 2.0, 0.5)
	gas._co_trace("writer_a", room)
	gas._co_trace("writer_b", room)
	var trace: Dictionary = gas.get_phase3_co_violation_trace()
	for writer in trace["by_writer"].keys():
		_expect(
			int(trace["by_writer"][writer]["new_violations"]) == 0,
			"valid state yields no finding for %s" % writer
		)
	_expect(trace["first_events"].is_empty(), "valid state yields no sample")


func _test_inherited_violation_is_not_a_new_creation() -> void:
	var gas = _gas()
	var room = _room(0, 1.0, 2.0)
	# The very first observation already sees an invalid state: it is a
	# creation relative to the trace's own baseline, and every later observation
	# of the same unbroken run must be inherited, never a second creation.
	gas._co_trace("entry_point", room)
	gas._co_trace("next_writer", room)
	gas._co_trace("another_writer", room)
	var by_writer: Dictionary = gas.get_phase3_co_violation_trace()["by_writer"]
	_expect(int(by_writer["entry_point"]["new_violations"]) == 1, "baseline crossing counted once")
	_expect(int(by_writer["next_writer"]["new_violations"]) == 0, "no double creation")
	_expect(int(by_writer["next_writer"]["inherited"]) == 1, "inheritance is explicit")
	_expect(int(by_writer["another_writer"]["inherited"]) == 1, "inheritance keeps counting")


func _test_resolution_is_visible() -> void:
	var gas = _gas()
	var room = _room(0, 1.0, 2.0)
	gas._co_trace("breaker", room)
	room.co_upper_kg = 0.5
	gas._co_trace("clamp", room)
	var by_writer: Dictionary = gas.get_phase3_co_violation_trace()["by_writer"]
	_expect(int(by_writer["clamp"]["resolved"]) == 1, "resolution is counted")
	_expect(int(by_writer["clamp"]["new_violations"]) == 0, "resolution is not a creation")
	# A later crossing after a resolution must be a new creation again.
	room.co_upper_kg = 3.0
	gas._co_trace("breaker_again", room)
	var after: Dictionary = gas.get_phase3_co_violation_trace()["by_writer"]
	_expect(
		int(after["breaker_again"]["new_violations"]) == 1,
		"a crossing after a resolution counts again"
	)


func _test_writer_is_mandatory_and_carried() -> void:
	var gas = _gas()
	var room = _room(3, 1.0, 2.0)
	gas._co_trace("named_writer", room, {"opening_index": 7})
	var sample: Dictionary = gas.get_phase3_co_violation_trace()["first_events"][0]
	_expect(String(sample["writer"]) == "named_writer", "writer is carried")
	_expect(int(sample["opening_index"]) == 7, "caller context is carried")
	_expect(sample.has("step"), "step is carried")
	_expect(sample.has("post_co_kg") and sample.has("post_co_upper_kg"), "post state carried")


func _test_material_threshold_separates_noise() -> void:
	var gas = GasExchangeSystemScript.new()
	gas.phase3_species_attribution_diagnostics_enabled = true
	# Floating-point scale excess: strict violation, not material.
	gas._record_zonal_guard("co", 1.0, 1.0 + 1.0e-15)
	# Material excess.
	gas._record_zonal_guard("co", 1.0, 1.0 + 1.0e-5)
	var entry: Dictionary = gas.get_phase3_species_attribution_summary()["co"]
	_expect(
		int(entry["zonal_guard_upper_over_bulk_count"]) == 2,
		"both crossings counted strictly"
	)
	_expect(
		int(entry["zonal_guard_material_over_bulk_count"]) == 1,
		"only the material crossing passes the threshold"
	)
	_expect(
		int(entry["zonal_guard_zero_headroom_count"]) == 2,
		"zero headroom is counted separately"
	)
	# The threshold must never suppress the strict count: both stay visible.
	_expect(
		int(entry["zonal_guard_upper_over_bulk_count"])
			>= int(entry["zonal_guard_material_over_bulk_count"]),
		"the strict population is never hidden"
	)


func _test_sample_cap_is_bounded() -> void:
	var gas = _gas()
	for index in range(gas.CO_TRACE_MAX_SAMPLES + 20):
		var room = _room(index, 1.0, 2.0)
		gas._co_trace("bulk_breaker", room)
	var trace: Dictionary = gas.get_phase3_co_violation_trace()
	_expect(
		trace["first_events"].size() == gas.CO_TRACE_MAX_SAMPLES,
		"sample list is capped"
	)
	_expect(
		int(trace["by_writer"]["bulk_breaker"]["new_violations"])
			== gas.CO_TRACE_MAX_SAMPLES + 20,
		"counters are not capped by the sample cap"
	)


func _test_export_is_pure_and_deterministic() -> void:
	var gas = _gas()
	var room = _room(0, 1.0, 2.0)
	gas._co_trace("writer", room)
	var first: String = JSON.stringify(gas.get_phase3_co_violation_trace())
	var mutated: Dictionary = gas.get_phase3_co_violation_trace()
	mutated.clear()
	_expect(
		JSON.stringify(gas.get_phase3_co_violation_trace()) == first,
		"export is pure"
	)
	var gas_b = _gas()
	var room_b = _room(0, 1.0, 2.0)
	gas_b._co_trace("writer", room_b)
	_expect(
		JSON.stringify(gas_b.get_phase3_co_violation_trace()) == first,
		"export is deterministic"
	)


func _gas():
	var gas = GasExchangeSystemScript.new()
	gas.phase3_co_first_violation_trace_enabled = true
	return gas


func _room(room_id: int, co_kg: float, co_upper_kg: float):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.co_kg = co_kg
	room.co_upper_kg = co_upper_kg
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0d5a2 ASSERTION FAILED: %s" % label)
