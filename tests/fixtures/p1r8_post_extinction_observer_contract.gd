extends SceneTree

const Observer = preload("res://tests/fixtures/p1r8_post_extinction_observer.gd")

var _failed: bool = false


func _init() -> void:
	_test_last_tick_extinction_is_insufficient()
	_test_missing_room_fails_closed()
	_test_nonfinite_value_fails_closed()
	_test_duplicate_tick_fails_closed()
	_test_unwatched_room_reignition_and_multiple_events()
	_test_small_rises_accumulate_and_room_transfer_conserves_stock()
	_test_in_transit_smoke_is_part_of_inventory()
	_test_counter_changes_remain_visible()
	_test_counter_regression_fails_closed()
	_test_incomplete_end_fails_closed()
	if _failed:
		quit(1)
		return
	print("P1R8_POST_EXTINCTION_OBSERVER_PASS")
	quit(0)


func _state(tick: int, time_s: float, fires: Array[bool], temps: Array[float], smoke: Array[float], generated: float = 0.0, vented: float = 0.0, deposited: float = 0.0, in_transit: float = 0.0) -> Dictionary:
	var result: Dictionary = {
		"tick_index": tick,
		"sim_time_s": time_s,
		"smoke_generated_total_kg": generated,
		"smoke_vented_total_kg": vented,
		"smoke_deposited_total_kg": deposited,
		"smoke_in_transit_kg": in_transit,
	}
	for room_id in range(fires.size()):
		result[str(room_id)] = {
			"has_fire": fires[room_id],
			"hrr_kw": 10.0 if fires[room_id] else 0.0,
			"temp_upper_c": temps[room_id],
			"smoke_kg": smoke[room_id],
		}
	return result


func _test_last_tick_extinction_is_insufficient() -> void:
	var observer = Observer.new([0])
	_expect(observer.observe(_state(0, 0.0, [true], [100.0], [1.0])), "incident sample accepted")
	_expect(observer.observe(_state(1, 1.0, [false], [99.0], [1.0])), "extinction sample accepted")
	var result: Dictionary = observer.finalize(1, 1.0)
	_expect(not result["valid"], "last-tick extinction cannot pass")
	_expect(result["reason"] == Observer.INSUFFICIENT_POST_EXTINCTION_WINDOW, "last-tick reason is explicit")


func _test_missing_room_fails_closed() -> void:
	var observer = Observer.new([0, 1])
	var sample: Dictionary = _state(0, 0.0, [true], [100.0], [1.0])
	_expect(not observer.observe(sample), "missing expected room rejected")
	_expect(observer.finalize(0, 0.0)["reason"] == Observer.MISSING_ROOM, "missing room reason preserved")


func _test_nonfinite_value_fails_closed() -> void:
	var observer = Observer.new([0])
	var sample: Dictionary = _state(0, 0.0, [true], [100.0], [1.0])
	sample["0"]["smoke_kg"] = NAN
	_expect(not observer.observe(sample), "NaN rejected")
	_expect(observer.finalize(0, 0.0)["reason"] == Observer.NONFINITE_VALUE, "NaN reason preserved")


func _test_duplicate_tick_fails_closed() -> void:
	var observer = Observer.new([0])
	_expect(observer.observe(_state(0, 0.0, [true], [100.0], [1.0])), "first ordered sample accepted")
	_expect(not observer.observe(_state(0, 1.0, [true], [99.0], [1.0])), "duplicate tick rejected")
	_expect(observer.finalize(0, 1.0)["reason"] == Observer.NON_MONOTONIC_SAMPLE, "ordering reason preserved")


func _test_unwatched_room_reignition_and_multiple_events() -> void:
	var observer = Observer.new([0, 1, 2])
	_expect(observer.observe(_state(0, 0.0, [true, false, false], [100.0, 30.0, 30.0], [1.0, 0.0, 0.0])), "incident accepted")
	_expect(observer.observe(_state(1, 1.0, [false, false, false], [99.0, 30.0, 30.0], [1.0, 0.0, 0.0])), "extinction accepted")
	_expect(observer.observe(_state(2, 2.0, [false, false, true], [98.0, 30.0, 31.0], [1.0, 0.0, 0.0])), "unwatched reignition accepted")
	_expect(observer.observe(_state(3, 3.0, [false, false, false], [97.0, 30.0, 30.0], [1.0, 0.0, 0.0])), "second extinction accepted")
	_expect(observer.observe(_state(4, 4.0, [false, true, false], [96.0, 31.0, 30.0], [1.0, 0.0, 0.0])), "second reignition accepted")
	var result: Dictionary = observer.finalize(4, 4.0)
	_expect(result["valid"], "complete reignition sequence valid")
	_expect(result["reignition_events"].size() == 2, "two transitions remain two events")


func _test_small_rises_accumulate_and_room_transfer_conserves_stock() -> void:
	var observer = Observer.new([0, 1])
	_expect(observer.observe(_state(0, 0.0, [true, false], [100.0, 50.0], [1.0, 0.0])), "initial stock accepted")
	_expect(observer.observe(_state(1, 1.0, [false, false], [99.0, 50.0], [0.8, 0.2])), "extinction transfer accepted")
	_expect(observer.observe(_state(2, 2.0, [false, false], [99.0008, 50.0], [0.6, 0.4])), "first small rise accepted")
	_expect(observer.observe(_state(3, 3.0, [false, false], [99.0016, 50.0], [0.5, 0.5])), "second small rise accepted")
	var result: Dictionary = observer.finalize(3, 3.0)
	_expect(result["valid"], "complete transfer sequence valid")
	_expect(is_zero_approx(result["smoke_accounting_residual_kg"]), "room transfer preserves all-room stock")
	_expect(result["max_positive_temp_step_c"][0] < 0.001, "each local rise is below old draft bound")
	_expect(result["cumulative_positive_temp_rise_c"][0] > 0.001, "cumulative warming remains visible")


func _test_in_transit_smoke_is_part_of_inventory() -> void:
	var observer = Observer.new([0, 1])
	_expect(observer.observe(_state(0, 0.0, [true, false], [100.0, 50.0], [1.0, 0.0])), "initial parcel sample accepted")
	_expect(observer.observe(_state(1, 1.0, [false, false], [99.0, 50.0], [0.4, 0.0], 0.0, 0.0, 0.0, 0.6)), "in-flight parcel accepted")
	_expect(observer.observe(_state(2, 2.0, [false, false], [98.0, 50.0], [0.4, 0.6])), "delivered parcel accepted")
	var result: Dictionary = observer.finalize(2, 2.0)
	_expect(result["valid"], "complete parcel sequence valid")
	_expect(is_zero_approx(result["smoke_in_transit_kg"]), "delivered parcel leaves no in-flight stock")
	_expect(is_zero_approx(result["smoke_accounting_residual_kg"]), "parcel delay preserves total smoke inventory")


func _test_incomplete_end_fails_closed() -> void:
	var observer = Observer.new([0])
	_expect(observer.observe(_state(0, 0.0, [true], [100.0], [1.0])), "incident accepted")
	_expect(observer.observe(_state(1, 1.0, [false], [99.0], [1.0])), "extinction accepted")
	_expect(observer.observe(_state(2, 2.0, [false], [98.0], [1.0])), "post sample accepted")
	var result: Dictionary = observer.finalize(3, 3.0)
	_expect(not result["valid"], "truncated sequence rejected")
	_expect(result["reason"] == Observer.INCOMPLETE_END, "truncated reason preserved")


func _test_counter_changes_remain_visible() -> void:
	var observer = Observer.new([0])
	_expect(observer.observe(_state(0, 0.0, [true], [100.0], [1.0])), "initial accounting sample accepted")
	_expect(observer.observe(_state(1, 1.0, [false], [99.0], [1.0])), "accounting extinction accepted")
	_expect(observer.observe(_state(2, 2.0, [false], [98.0], [1.0], 1.0)), "source change accepted")
	var result: Dictionary = observer.finalize(2, 2.0)
	_expect(result["valid"], "complete accounting sequence valid")
	_expect(is_equal_approx(result["smoke_accounting_residual_kg"], -1.0), "unmatched generated smoke remains visible")


func _test_counter_regression_fails_closed() -> void:
	var observer = Observer.new([0])
	_expect(observer.observe(_state(0, 0.0, [true], [100.0], [1.0], 1.0)), "counter baseline accepted")
	_expect(not observer.observe(_state(1, 1.0, [false], [99.0], [1.0], 0.5)), "counter regression rejected")
	_expect(observer.finalize(1, 1.0)["reason"] == Observer.NON_MONOTONIC_COUNTER, "counter regression reason preserved")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("P1R8 post-extinction observer: " + message)
