extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

const SPECIES: Array[String] = [
	"smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"
]

var _failed: bool = false


func _init() -> void:
	_test_exact_linear_pressure_integral()
	_test_equal_rooms_are_quiet()
	_test_hot_room_has_bidirectional_exchange()
	_test_one_zone_receiver_is_valid()
	_test_atomic_transport_conserves_every_quantity()
	_test_inventory_cap_is_global()
	_test_reversed_opening_order_is_equivalent()
	_test_vertical_opening_is_not_claimed()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33A_INTERIOR_OPENING_SHADOW_PASS")
		quit(0)


func _test_exact_linear_pressure_integral() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	_assert_close(
		system._integral_sqrt_abs_linear(0.0, 4.0, 1.0),
		4.0 / 3.0,
		"linear pressure integral"
	)
	_assert_close(
		system._integral_sqrt_abs_linear(-4.0, 4.0, 1.0),
		4.0 / 3.0,
		"zero-crossing pressure integral"
	)


func _test_equal_rooms_are_quiet() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var input_a: Dictionary = _thermo_input(20.0, 20.0, 1.2)
	var input_b: Dictionary = input_a.duplicate(true)
	var preview: Dictionary = system.preview_canonical_interior_opening(
		input_a, input_b, _opening_geometry(), 0.61, 1.0
	)
	_assert_true(bool(preview.get("valid", false)), "equal preview valid")
	_assert_close(float(preview.get("exchange_kg", -1.0)), 0.0, "equal exchange")


func _test_hot_room_has_bidirectional_exchange() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var preview: Dictionary = system.preview_canonical_interior_opening(
		_thermo_input(180.0, 20.0, 1.0),
		_thermo_input(20.0, 20.0, 1.2),
		_opening_geometry(),
		0.61,
		1.0
	)
	_assert_true(float(preview.get("gross_a_to_b_kg", 0.0)) > 0.0, "hot upper out")
	_assert_true(float(preview.get("gross_b_to_a_kg", 0.0)) > 0.0, "cold lower return")
	_assert_close(
		float(preview.get("gross_a_to_b_kg", 0.0)),
		float(preview.get("gross_b_to_a_kg", 0.0)),
		"opening antisymmetry",
		1.0e-7
	)
	var has_upper_out: bool = false
	var has_lower_return: bool = false
	for route in preview.get("routes", []):
		has_upper_out = has_upper_out or (
			String(route.get("source_side", "")) == "a"
			and String(route.get("source_zone", "")) == "upper"
		)
		has_lower_return = has_lower_return or (
			String(route.get("source_side", "")) == "b"
			and String(route.get("source_zone", "")) == "lower"
		)
	_assert_true(has_upper_out, "upper route exists")
	_assert_true(has_lower_return, "lower route exists")


func _test_one_zone_receiver_is_valid() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var receiver: Dictionary = _thermo_input(20.0, 20.0, 2.4)
	receiver["upper_gas_kg"] = 0.0
	receiver["upper_volume_m3"] = 0.0
	receiver["lower_volume_m3"] = 48.0
	var preview: Dictionary = system.preview_canonical_interior_opening(
		_thermo_input(180.0, 20.0, 1.0),
		receiver,
		_opening_geometry(),
		0.61,
		1.0
	)
	_assert_true(bool(preview.get("valid", false)), "one-zone receiver preview valid")
	_assert_true(
		float(preview.get("exchange_kg", 0.0)) > 0.0,
		"one-zone receiver exchanges mass"
	)


func _test_atomic_transport_conserves_every_quantity() -> void:
	var setup: Dictionary = _make_two_room_building(false, false)
	var building = setup["building"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var before: Dictionary = _building_inventory(system, building)
	system.queue_canonical_interior_opening_requests(building, 0.1, 20.0)
	system.finalize_step(building, 20.0)
	var after: Dictionary = _result_inventory(system.get_results())
	_assert_inventory_close(after, before, "atomic conservation")
	for room_key in system.get_results().keys():
		var result: Dictionary = system.get_results()[room_key]
		_assert_close(float(result["phase3_shadow_interior_mass_residual_kg"]), 0.0, "mass residual")
		_assert_close(float(result["phase3_shadow_interior_energy_residual_kj"]), 0.0, "energy residual")
		_assert_close(float(result["phase3_shadow_interior_o2_residual_kg"]), 0.0, "o2 residual")
		_assert_close(float(result["phase3_shadow_interior_species_residual_kg"]), 0.0, "species residual")
		_assert_true(
			float(result["phase3_shadow_interior_accepted_out_species_kg_step"]) > 0.0,
			"seven-species payload moved"
		)
	building.free()


func _test_inventory_cap_is_global() -> void:
	var setup: Dictionary = _make_two_room_building(false, false)
	var building = setup["building"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(building, 1000.0, 20.0)
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results()
	_assert_true(
		float(results["0"]["phase3_shadow_interior_accepted_fraction"]) < 1.0,
		"network inventory cap"
	)
	for room_key in results.keys():
		_assert_true(float(results[room_key]["phase3_shadow_upper_gas_kg"]) >= -1.0e-9, "upper nonnegative")
		_assert_true(float(results[room_key]["phase3_shadow_lower_gas_kg"]) >= -1.0e-9, "lower nonnegative")
	building.free()


func _test_reversed_opening_order_is_equivalent() -> void:
	var normal: Dictionary = _run_three_room_network(false)
	var reversed: Dictionary = _run_three_room_network(true)
	for room_key in normal.keys():
		for field_name in [
			"phase3_shadow_upper_gas_kg",
			"phase3_shadow_lower_gas_kg",
			"phase3_shadow_upper_energy_kj",
			"phase3_shadow_lower_energy_kj",
			"phase3_shadow_exterior_post_upper_o2_kg",
			"phase3_shadow_exterior_post_lower_o2_kg",
			"phase3_shadow_interior_net_mass_kg_step",
			"phase3_shadow_interior_net_energy_kj_step",
			"phase3_shadow_interior_net_o2_kg_step",
			"phase3_shadow_interior_net_species_kg_step",
		]:
			_assert_close(
				float(normal[room_key].get(field_name, 0.0)),
				float(reversed[room_key].get(field_name, 0.0)),
				"reversed %s room %s" % [field_name, room_key],
				1.0e-10
			)


func _test_vertical_opening_is_not_claimed() -> void:
	var setup: Dictionary = _make_two_room_building(false, true)
	var building = setup["building"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(building, 0.1, 20.0)
	system.finalize_step(building, 20.0)
	for room_key in system.get_results().keys():
		var result: Dictionary = system.get_results()[room_key]
		_assert_close(float(result["phase3_shadow_interior_opening_active_flag"]), 0.0, "vertical inactive")
		_assert_close(float(result["phase3_shadow_interior_vertical_skipped_count"]), 1.0, "vertical skipped")
	building.free()


func _run_three_room_network(reverse_openings: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var rooms: Dictionary = {}
	rooms[0] = _make_room(0, 180.0, 20.0, 1.0, 0.10)
	rooms[1] = _make_room(1, 50.0, 20.0, 1.2, 0.18)
	rooms[2] = _make_room(2, 20.0, 20.0, 1.4, 0.209)
	building.rooms = rooms
	var op_0 = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	op_0.opening_index = 10
	var op_1 = OpeningModelScript.new(1, 2, 0, 0.9, 2.0, 1.0, 0.0)
	op_1.opening_index = 20
	building.openings = [op_1, op_0] if reverse_openings else [op_0, op_1]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(building, 0.1, 20.0)
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results()
	building.free()
	return results


func _make_two_room_building(reverse_openings: bool, vertical: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var room_a = _make_room(0, 180.0, 20.0, 1.0, 0.10)
	var room_b = _make_room(1, 20.0, 20.0, 1.2, 0.209)
	if vertical:
		room_b.floor_level_z_m = 3.0
	building.rooms = {0: room_a, 1: room_b}
	var opening = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	opening.opening_index = 7
	opening.is_vertical = vertical
	building.openings = [opening]
	return {"building": building, "room_a": room_a, "room_b": room_b}


func _make_room(
		room_id: int,
		upper_temp_c: float,
		lower_temp_c: float,
		interface_m: float,
		upper_o2: float
	):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	var input: Dictionary = _thermo_input(upper_temp_c, lower_temp_c, interface_m)
	room.upper_gas_kg = float(input["upper_gas_kg"])
	room.lower_gas_kg = float(input["lower_gas_kg"])
	room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, upper_temp_c - 20.0)
	room.lower_energy_kj = room.lower_gas_kg * maxf(0.0, lower_temp_c - 20.0)
	room.o2_upper = upper_o2
	room.o2_lower = 0.209
	room.smoke_kg = 0.07 * float(room_id + 1)
	room.co_upper_kg = 0.010 * float(room_id + 1)
	room.co_kg = room.co_upper_kg + 0.003 * float(room_id + 1)
	room.co2_upper_kg = 0.080 * float(room_id + 1)
	room.co2_kg = room.co2_upper_kg + 0.020 * float(room_id + 1)
	room.hcn_upper_kg = 0.002 * float(room_id + 1)
	room.hcn_kg = room.hcn_upper_kg + 0.001 * float(room_id + 1)
	room.hcl_kg = 0.0011 * float(room_id + 1)
	room.acrolein_kg = 0.0012 * float(room_id + 1)
	room.formaldehyde_kg = 0.0013 * float(room_id + 1)
	return room


func _thermo_input(upper_temp_c: float, lower_temp_c: float, interface_m: float) -> Dictionary:
	var room_volume_m3: float = 48.0
	var floor_area_m2: float = 20.0
	var lower_volume_m3: float = floor_area_m2 * interface_m
	var upper_volume_m3: float = room_volume_m3 - lower_volume_m3
	var reference_k: float = 293.15
	var upper_mass_kg: float = 1.2 * reference_k / (upper_temp_c + 273.15) * upper_volume_m3
	var lower_mass_kg: float = 1.2 * reference_k / (lower_temp_c + 273.15) * lower_volume_m3
	var system = Phase3ZoneMassSystemScript.new()
	var result: Dictionary = system.derive_canonical_thermodynamic_state(
		upper_mass_kg,
		lower_mass_kg,
		upper_mass_kg * maxf(0.0, upper_temp_c - 20.0),
		lower_mass_kg * maxf(0.0, lower_temp_c - 20.0),
		room_volume_m3,
		floor_area_m2,
		2.4,
		20.0
	)
	result["upper_gas_kg"] = upper_mass_kg
	result["lower_gas_kg"] = lower_mass_kg
	result["reference_temp_c"] = 20.0
	return result


func _opening_geometry() -> Dictionary:
	return {
		"bottom_m": 0.0,
		"top_m": 2.0,
		"width_m": 0.9,
		"open_fraction": 1.0,
	}


func _building_inventory(system, building) -> Dictionary:
	var totals: Dictionary = _empty_inventory()
	for room_id in building.rooms.keys():
		var room = building.rooms[room_id]
		var input: Dictionary = system.get_canonical_thermodynamic_input(room, 20.0)
		totals["mass"] += float(input["upper_gas_kg"]) + float(input["lower_gas_kg"])
		totals["energy"] += float(input["upper_energy_kj"]) + float(input["lower_energy_kj"])
		totals["o2"] += float(input["upper_o2_kg"]) + float(input["lower_o2_kg"])
	return totals


func _result_inventory(results: Dictionary) -> Dictionary:
	var totals: Dictionary = _empty_inventory()
	for room_key in results.keys():
		var result: Dictionary = results[room_key]
		totals["mass"] += float(result["phase3_shadow_upper_gas_kg"]) \
				+ float(result["phase3_shadow_lower_gas_kg"])
		totals["energy"] += float(result["phase3_shadow_upper_energy_kj"]) \
				+ float(result["phase3_shadow_lower_energy_kj"])
		totals["o2"] += float(result["phase3_shadow_exterior_post_upper_o2_kg"]) \
				+ float(result["phase3_shadow_exterior_post_lower_o2_kg"])
		# Species conservation is asserted by the network residual because the
		# public result intentionally exports aggregate species telemetry only.
	return totals


func _empty_inventory() -> Dictionary:
	var result: Dictionary = {"mass": 0.0, "energy": 0.0, "o2": 0.0}
	for species_name in SPECIES:
		result[species_name] = 0.0
	return result


func _assert_inventory_close(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for quantity in ["mass", "energy", "o2"]:
		_assert_close(float(actual[quantity]), float(expected[quantity]), "%s %s" % [label, quantity])


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(
		actual: float,
		expected: float,
		label: String,
		tolerance: float = 1.0e-8
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %s got %s" % [label, str(expected), str(actual)])
		_failed = true
