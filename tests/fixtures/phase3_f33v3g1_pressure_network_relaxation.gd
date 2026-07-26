extends SceneTree

const SystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

var _failed: bool = false


func _init() -> void:
	var system = SystemScript.new()
	_test_single_connection(system)
	_test_chain(system)
	_test_non_descent(system)
	_test_inventory_bound(system)
	_test_disconnected_independence(system)
	_test_order_independence(system)
	_test_zero_response(system)
	_test_malformed_fails_closed(system)
	if _failed:
		quit(1)
	print("PHASE3_F33V3G1_PRESSURE_NETWORK_RELAXATION_PASS")
	quit(0)


func _test_single_connection(system) -> void:
	var result: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0, "1": 0.0},
		{},
		{"0": -150.0, "1": 150.0},
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	_assert_true(bool(result["valid"]), "single valid")
	_close(float(result["fraction"]), 1.0 / 3.0, "single fraction")
	_close(float(result["objective_post_pa2"]), 0.0, "single objective")


func _test_chain(system) -> void:
	var result: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0, "1": 50.0, "2": 0.0},
		{},
		{"0": -60.0, "1": 0.0, "2": 60.0},
		[
			{"room_a_id": 0, "room_b_id": 1},
			{"room_a_id": 1, "room_b_id": 2},
		]
	)
	_assert_true(bool(result["valid"]), "chain valid")
	_close(float(result["fraction"]), 5.0 / 6.0, "chain fraction")
	_close(float(result["objective_post_pa2"]), 0.0, "chain objective")


func _test_non_descent(system) -> void:
	var result: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0, "1": 0.0},
		{},
		{"0": 10.0, "1": -10.0},
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	_assert_true(bool(result["valid"]), "non-descent valid")
	_close(float(result["fraction"]), 0.0, "non-descent dormant")
	_assert_true(result["limiting_reason"] == "non_descent", "non-descent reason")


func _test_inventory_bound(system) -> void:
	var result: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0, "1": 0.0},
		{},
		{"0": -150.0, "1": 150.0},
		[{"room_a_id": 0, "room_b_id": 1}],
		0.2
	)
	_assert_true(bool(result["valid"]), "inventory valid")
	_close(float(result["fraction"]), 0.2, "inventory fraction")
	_close(float(result["objective_post_pa2"]), 1600.0, "inventory objective")
	_assert_true(result["limiting_reason"] == "inventory", "inventory reason")


func _test_disconnected_independence(system) -> void:
	var first: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0, "1": 0.0},
		{},
		{"0": -150.0, "1": 150.0},
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	var second: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"2": 20.0, "3": 0.0},
		{},
		{"2": -10.0, "3": 10.0},
		[{"room_a_id": 2, "room_b_id": 3}]
	)
	_close(float(first["fraction"]), 1.0 / 3.0, "component one")
	_close(float(second["fraction"]), 1.0, "component two")


func _test_order_independence(system) -> void:
	var pressures: Dictionary = {"0": 100.0, "1": 50.0, "2": 0.0}
	var response: Dictionary = {"0": -60.0, "1": 0.0, "2": 60.0}
	var forward: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		pressures,
		{},
		response,
		[
			{"room_a_id": 0, "room_b_id": 1},
			{"room_a_id": 1, "room_b_id": 2},
		]
	)
	var reverse: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		pressures,
		{},
		response,
		[
			{"room_a_id": 1, "room_b_id": 2},
			{"room_a_id": 0, "room_b_id": 1},
		]
	)
	for field in ["fraction", "objective_pre_pa2", "objective_post_pa2"]:
		_close(float(forward[field]), float(reverse[field]), "order " + field)


func _test_zero_response(system) -> void:
	var result: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0, "1": 0.0},
		{},
		{},
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	_assert_true(bool(result["valid"]), "zero response valid")
	_close(float(result["fraction"]), 0.0, "zero response dormant")
	_assert_true(result["limiting_reason"] == "zero_response", "zero response reason")


func _test_malformed_fails_closed(system) -> void:
	var result: Dictionary = system.compute_fixed_gross_pressure_network_relaxation(
		{"0": 100.0},
		{},
		{},
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	_assert_true(not bool(result["valid"]), "missing room invalid")
	_close(float(result["fraction"]), 0.0, "missing room dormant")


func _close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-8 * maxf(1.0, absf(expected)):
		push_error("%s: got %.12f expected %.12f" % [label, actual, expected])
		_failed = true


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true
