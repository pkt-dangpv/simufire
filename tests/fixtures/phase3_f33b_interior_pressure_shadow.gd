extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_signed_preview_direction()
	_test_equal_pressure_is_quiet()
	_test_network_relaxation_prevents_crossing()
	_test_atomic_network_conserves_inventory()
	_test_opening_order_is_equivalent()
	_test_disabled_is_identical_to_f33a()
	_test_vertical_opening_is_excluded()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33B_INTERIOR_PRESSURE_SHADOW_PASS")
		quit(0)


func _test_signed_preview_direction() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var high: Dictionary = _pressure_input(120.0)
	var low: Dictionary = _pressure_input(0.0)
	var forward: Dictionary = system.preview_canonical_interior_pressure_flow(
		high, low, _opening_geometry(), 0.61, 0.1
	)
	var reverse: Dictionary = system.preview_canonical_interior_pressure_flow(
		low, high, _opening_geometry(), 0.61, 0.1
	)
	_assert_true(bool(forward.get("valid", false)), "forward preview valid")
	_assert_true(float(forward.get("signed_net_a_to_b_kg", 0.0)) > 0.0, "high flows to low")
	_assert_true(float(reverse.get("signed_net_a_to_b_kg", 0.0)) < 0.0, "reverse pressure reverses flow")
	_assert_true(not forward.get("routes", []).is_empty(), "forward routes exist")
	for route in forward.get("routes", []):
		_assert_true(String(route.get("source_side", "")) == "a", "forward route source")
	for route in reverse.get("routes", []):
		_assert_true(String(route.get("source_side", "")) == "b", "reverse route source")


func _test_equal_pressure_is_quiet() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var input: Dictionary = _pressure_input(25.0)
	var preview: Dictionary = system.preview_canonical_interior_pressure_flow(
		input, input.duplicate(true), _opening_geometry(), 0.61, 0.1
	)
	_assert_true(bool(preview.get("valid", false)), "equal pressure preview valid")
	_assert_close(float(preview.get("signed_net_a_to_b_kg", -1.0)), 0.0, "equal pressure net")
	_assert_true(preview.get("routes", []).is_empty(), "equal pressure routes empty")


func _test_network_relaxation_prevents_crossing() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var result: Dictionary = system.compute_interior_network_pressure_relaxation(
		{"0": 100.0, "1": 0.0},
		{},
		{"0": -150.0, "1": 150.0},
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	_assert_close(float(result.get("fraction", 0.0)), 1.0 / 3.0, "crossing fraction")
	_assert_close(float(result.get("crossing_prevented_count", 0.0)), 1.0, "crossing count")


func _test_atomic_network_conserves_inventory() -> void:
	var building = _make_two_room_building(false, false)
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var before: Dictionary = _building_inventory(system, building)
	system.queue_canonical_interior_opening_requests(building, 0.1, 20.0, 0.61, true)
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results()
	var after: Dictionary = _result_inventory(results)
	for quantity in ["mass", "energy", "o2"]:
		_assert_close(float(after[quantity]), float(before[quantity]), "conserve " + quantity)
	_assert_true(
		float(results["0"].get("phase3_shadow_interior_pressure_net_mass_kg_step", 0.0)) < 0.0,
		"high-pressure room loses mass"
	)
	_assert_true(
		float(results["1"].get("phase3_shadow_interior_pressure_net_mass_kg_step", 0.0)) > 0.0,
		"low-pressure room gains mass"
	)
	for room_key in results.keys():
		for residual_field in [
			"phase3_shadow_interior_pressure_mass_residual_kg",
			"phase3_shadow_interior_pressure_energy_residual_kj",
			"phase3_shadow_interior_pressure_o2_residual_kg",
			"phase3_shadow_interior_pressure_species_residual_kg",
		]:
			_assert_close(float(results[room_key].get(
				residual_field, 1.0
			)), 0.0, residual_field)
	building.free()


func _test_opening_order_is_equivalent() -> void:
	var normal: Dictionary = _run_three_room_network(false)
	var reversed: Dictionary = _run_three_room_network(true)
	for room_key in normal.keys():
		for field_name in [
			"phase3_shadow_upper_gas_kg",
			"phase3_shadow_lower_gas_kg",
			"phase3_shadow_upper_energy_kj",
			"phase3_shadow_lower_energy_kj",
			"phase3_shadow_interior_pressure_net_mass_kg_step",
			"phase3_shadow_interior_pressure_limited_delta_pa",
			"phase3_shadow_interior_pressure_predicted_post_pa",
		]:
			_assert_close(
				float(normal[room_key].get(field_name, 0.0)),
				float(reversed[room_key].get(field_name, 0.0)),
				"order %s room %s" % [field_name, room_key],
				1.0e-10
			)


func _test_disabled_is_identical_to_f33a() -> void:
	var implicit: Dictionary = _run_two_room(false)
	var explicit: Dictionary = _run_two_room(false, false)
	for room_key in implicit.keys():
		for field_name in implicit[room_key].keys():
			var left = implicit[room_key][field_name]
			var right = explicit[room_key].get(field_name)
			if typeof(left) == TYPE_FLOAT or typeof(left) == TYPE_INT:
				_assert_close(float(left), float(right), "disabled %s" % field_name, 1.0e-12)


func _test_vertical_opening_is_excluded() -> void:
	var building = _make_two_room_building(false, true)
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(building, 0.1, 20.0, 0.61, true)
	system.finalize_step(building, 20.0)
	for room_key in system.get_results().keys():
		_assert_close(float(system.get_results()[room_key].get(
			"phase3_shadow_interior_pressure_enabled_flag", 0.0
		)), 0.0, "vertical pressure excluded")
	building.free()


func _run_two_room(enable_pressure: bool, explicit_argument: Variant = null) -> Dictionary:
	var building = _make_two_room_building(false, false)
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	if explicit_argument == null:
		system.queue_canonical_interior_opening_requests(building, 0.1, 20.0, 0.61)
	else:
		system.queue_canonical_interior_opening_requests(
			building, 0.1, 20.0, 0.61, enable_pressure
		)
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results().duplicate(true)
	building.free()
	return results


func _run_three_room_network(reverse_openings: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_room(0, 180.0),
		1: _make_room(1, 55.0),
		2: _make_room(2, 0.0),
	}
	var op_0 = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	op_0.opening_index = 10
	var op_1 = OpeningModelScript.new(1, 2, 0, 0.9, 2.0, 1.0, 0.0)
	op_1.opening_index = 20
	building.openings = [op_1, op_0] if reverse_openings else [op_0, op_1]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(building, 0.1, 20.0, 0.61, true)
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results().duplicate(true)
	building.free()
	return results


func _make_two_room_building(reverse_openings: bool, vertical: bool):
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var room_a = _make_room(0, 120.0)
	var room_b = _make_room(1, 0.0)
	if vertical:
		room_b.floor_level_z_m = 3.0
	building.rooms = {0: room_a, 1: room_b}
	var opening = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	opening.opening_index = 7
	opening.is_vertical = vertical
	building.openings = [opening]
	return building


func _make_room(room_id: int, pressure_gauge_pa: float):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	var input: Dictionary = _pressure_input(pressure_gauge_pa)
	room.upper_gas_kg = float(input["upper_gas_kg"])
	room.lower_gas_kg = float(input["lower_gas_kg"])
	room.upper_energy_kj = 0.0
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.18 if room_id == 0 else 0.209
	room.o2_lower = 0.209
	room.smoke_kg = 0.05 * float(room_id + 1)
	room.co_upper_kg = 0.01 * float(room_id + 1)
	room.co_kg = room.co_upper_kg + 0.002
	room.co2_upper_kg = 0.08 * float(room_id + 1)
	room.co2_kg = room.co2_upper_kg + 0.02
	room.hcn_upper_kg = 0.002 * float(room_id + 1)
	room.hcn_kg = room.hcn_upper_kg + 0.001
	room.hcl_kg = 0.0011 * float(room_id + 1)
	room.acrolein_kg = 0.0012 * float(room_id + 1)
	room.formaldehyde_kg = 0.0013 * float(room_id + 1)
	return room


func _pressure_input(pressure_gauge_pa: float) -> Dictionary:
	var pressure_scale: float = (101325.0 + pressure_gauge_pa) / 101325.0
	var upper_mass_kg: float = 28.8 * pressure_scale
	var lower_mass_kg: float = 28.8 * pressure_scale
	var system = Phase3ZoneMassSystemScript.new()
	var result: Dictionary = system.derive_canonical_thermodynamic_state(
		upper_mass_kg, lower_mass_kg, 0.0, 0.0, 48.0, 20.0, 2.4, 20.0
	)
	result["upper_gas_kg"] = upper_mass_kg
	result["lower_gas_kg"] = lower_mass_kg
	result["reference_temp_c"] = 20.0
	return result


func _opening_geometry() -> Dictionary:
	return {"bottom_m": 0.0, "top_m": 2.0, "width_m": 0.9, "open_fraction": 1.0}


func _building_inventory(system, building) -> Dictionary:
	var totals: Dictionary = {"mass": 0.0, "energy": 0.0, "o2": 0.0}
	for room_id in building.rooms.keys():
		var input: Dictionary = system.get_canonical_thermodynamic_input(
			building.rooms[room_id], 20.0
		)
		totals["mass"] += float(input["upper_gas_kg"]) + float(input["lower_gas_kg"])
		totals["energy"] += float(input["upper_energy_kj"]) + float(input["lower_energy_kj"])
		totals["o2"] += float(input["upper_o2_kg"]) + float(input["lower_o2_kg"])
	return totals


func _result_inventory(results: Dictionary) -> Dictionary:
	var totals: Dictionary = {"mass": 0.0, "energy": 0.0, "o2": 0.0}
	for room_key in results.keys():
		var result: Dictionary = results[room_key]
		totals["mass"] += float(result["phase3_shadow_upper_gas_kg"]) \
				+ float(result["phase3_shadow_lower_gas_kg"])
		totals["energy"] += float(result["phase3_shadow_upper_energy_kj"]) \
				+ float(result["phase3_shadow_lower_energy_kj"])
		totals["o2"] += float(result["phase3_shadow_exterior_post_upper_o2_kg"]) \
				+ float(result["phase3_shadow_exterior_post_lower_o2_kg"])
	return totals


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(actual: float, expected: float, label: String, tolerance: float = 1.0e-8) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %s got %s" % [label, str(expected), str(actual)])
		_failed = true
