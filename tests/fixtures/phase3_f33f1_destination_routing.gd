extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_lower_source_renews_lower_receiver()
	_test_upper_source_remains_upper()
	_test_disabled_matches_existing_routing()
	_test_gross_opening_flow_is_invariant()
	_test_pressure_routes_share_contract()
	_test_empty_destination_zone_is_created_conservatively()
	_test_atomic_bundle_conserves_all_quantities()
	_test_opening_order_is_equivalent()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33F1_DESTINATION_ROUTING_PASS")
		quit(0)


func _test_lower_source_renews_lower_receiver() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var receiver: Dictionary = _thermo_input(120.0, 20.0, 0.10)
	var source: Dictionary = _thermo_input(35.0, 20.0, 1.20)
	var densities_receiver: Dictionary = system._canonical_zone_densities(receiver)
	var densities_source: Dictionary = system._canonical_zone_densities(source)
	var legacy: Dictionary = system._canonical_interior_interval_flow(
		receiver, source, densities_receiver, densities_source,
		0.20, 0.40, -4.0, -4.0, 1.0, 1.0, 0.61, false
	)
	var candidate: Dictionary = system._canonical_interior_interval_flow(
		receiver, source, densities_receiver, densities_source,
		0.20, 0.40, -4.0, -4.0, 1.0, 1.0, 0.61, true
	)
	_assert_route(legacy, "b", "lower", "a", "upper", "legacy lower geometry")
	_assert_route(candidate, "b", "lower", "a", "lower", "candidate lower renewal")
	_assert_close(
		float(candidate.get("mass_flow_kg_s", 0.0)),
		float(legacy.get("mass_flow_kg_s", -1.0)),
		"lower route flow invariant"
	)


func _test_upper_source_remains_upper() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var source: Dictionary = _thermo_input(180.0, 20.0, 0.20)
	var receiver: Dictionary = _thermo_input(35.0, 20.0, 1.20)
	var densities_source: Dictionary = system._canonical_zone_densities(source)
	var densities_receiver: Dictionary = system._canonical_zone_densities(receiver)
	var legacy: Dictionary = system._canonical_interior_interval_flow(
		source, receiver, densities_source, densities_receiver,
		0.40, 0.60, 4.0, 4.0, 1.0, 1.0, 0.61, false
	)
	var candidate: Dictionary = system._canonical_interior_interval_flow(
		source, receiver, densities_source, densities_receiver,
		0.40, 0.60, 4.0, 4.0, 1.0, 1.0, 0.61, true
	)
	_assert_route(legacy, "a", "upper", "b", "lower", "legacy upper geometry")
	_assert_route(candidate, "a", "upper", "b", "upper", "candidate upper identity")
	_assert_close(
		float(candidate.get("mass_flow_kg_s", 0.0)),
		float(legacy.get("mass_flow_kg_s", -1.0)),
		"upper route flow invariant"
	)


func _test_disabled_matches_existing_routing() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var hot: Dictionary = _thermo_input(180.0, 20.0, 0.65)
	var cold: Dictionary = _thermo_input(20.0, 20.0, 1.35)
	var opening_implicit: Dictionary = system.preview_canonical_interior_opening(
		hot, cold, _opening_geometry(), 0.61, 0.10
	)
	var opening_explicit: Dictionary = system.preview_canonical_interior_opening(
		hot, cold, _opening_geometry(), 0.61, 0.10, 64, false
	)
	_assert_true(opening_implicit == opening_explicit, "opening default OFF exact")
	hot["pressure_gauge_pa"] = 120.0
	cold["pressure_gauge_pa"] = 0.0
	var pressure_implicit: Dictionary = system.preview_canonical_interior_pressure_flow(
		hot, cold, _opening_geometry(), 0.61, 0.10
	)
	var pressure_explicit: Dictionary = system.preview_canonical_interior_pressure_flow(
		hot, cold, _opening_geometry(), 0.61, 0.10, false
	)
	_assert_true(pressure_implicit == pressure_explicit, "pressure default OFF exact")


func _test_gross_opening_flow_is_invariant() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var hot: Dictionary = _thermo_input(180.0, 20.0, 0.65)
	var cold: Dictionary = _thermo_input(20.0, 20.0, 1.35)
	var legacy: Dictionary = system.preview_canonical_interior_opening(
		hot, cold, _opening_geometry(), 0.61, 0.10, 64, false
	)
	var candidate: Dictionary = system.preview_canonical_interior_opening(
		hot, cold, _opening_geometry(), 0.61, 0.10, 64, true
	)
	for field_name in [
		"gross_a_to_b_kg", "gross_b_to_a_kg", "net_a_to_b_kg",
		"exchange_kg", "neutral_plane_m", "neutral_pressure_offset_pa",
	]:
		_assert_close(
			float(candidate.get(field_name, 0.0)),
			float(legacy.get(field_name, 0.0)),
			"opening invariant " + field_name
		)
	_assert_source_preserving_routes(candidate.get("routes", []), "opening routes")


func _test_pressure_routes_share_contract() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var high: Dictionary = _thermo_input(180.0, 20.0, 0.45)
	var low: Dictionary = _thermo_input(20.0, 20.0, 1.35)
	high["pressure_gauge_pa"] = 120.0
	low["pressure_gauge_pa"] = 0.0
	var legacy: Dictionary = system.preview_canonical_interior_pressure_flow(
		high, low, _opening_geometry(), 0.61, 0.10, false
	)
	var candidate: Dictionary = system.preview_canonical_interior_pressure_flow(
		high, low, _opening_geometry(), 0.61, 0.10, true
	)
	_assert_close(
		float(candidate.get("signed_net_a_to_b_kg", 0.0)),
		float(legacy.get("signed_net_a_to_b_kg", 0.0)),
		"pressure flow invariant"
	)
	_assert_true(not candidate.get("routes", []).is_empty(), "pressure routes exist")
	_assert_source_preserving_routes(candidate.get("routes", []), "pressure routes")


func _test_empty_destination_zone_is_created_conservatively() -> void:
	var building = _make_two_room_building(true)
	var receiver = building.get_room(1)
	_assert_close(receiver.upper_gas_kg, 0.0, "receiver starts without upper")
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(
		building, 0.10, 20.0, 0.61, false, true
	)
	system.finalize_step(building, 20.0)
	var receiver_result: Dictionary = system.get_results()["1"]
	_assert_true(
		float(receiver_result.get("phase3_shadow_upper_gas_kg", 0.0)) > 0.0,
		"upper destination created"
	)
	_assert_close(
		float(receiver_result.get("phase3_shadow_interior_mass_residual_kg", 1.0)),
		0.0,
		"one-zone mass residual"
	)
	building.free()


func _test_atomic_bundle_conserves_all_quantities() -> void:
	var building = _make_two_room_building(false)
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var before: Dictionary = _building_inventory(system, building)
	system.queue_canonical_interior_opening_requests(
		building, 0.10, 20.0, 0.61, true, true
	)
	system.finalize_step(building, 20.0)
	var after: Dictionary = _result_inventory(system.get_results())
	for quantity in ["mass", "energy", "o2"]:
		_assert_close(float(after[quantity]), float(before[quantity]), "conserve " + quantity)
	for room_key in system.get_results().keys():
		var result: Dictionary = system.get_results()[room_key]
		for residual_field in [
			"phase3_shadow_interior_mass_residual_kg",
			"phase3_shadow_interior_energy_residual_kj",
			"phase3_shadow_interior_o2_residual_kg",
			"phase3_shadow_interior_species_residual_kg",
			"phase3_shadow_interior_pressure_mass_residual_kg",
			"phase3_shadow_interior_pressure_energy_residual_kj",
			"phase3_shadow_interior_pressure_o2_residual_kg",
			"phase3_shadow_interior_pressure_species_residual_kg",
		]:
			_assert_close(float(result.get(residual_field, 1.0)), 0.0, residual_field)
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
			"phase3_shadow_exterior_post_upper_o2_kg",
			"phase3_shadow_exterior_post_lower_o2_kg",
			"phase3_shadow_interior_net_mass_kg_step",
			"phase3_shadow_interior_pressure_net_mass_kg_step",
		]:
			_assert_close(
				float(normal[room_key].get(field_name, 0.0)),
				float(reversed[room_key].get(field_name, 0.0)),
				"order %s room %s" % [field_name, room_key],
				1.0e-10
			)


func _run_three_room_network(reverse_openings: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_room(0, 180.0, 20.0, 0.45, 0.10),
		1: _make_room(1, 55.0, 20.0, 0.85, 0.18),
		2: _make_room(2, 20.0, 20.0, 1.35, 0.209),
	}
	var op_0 = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	op_0.opening_index = 10
	var op_1 = OpeningModelScript.new(1, 2, 0, 0.9, 2.0, 1.0, 0.0)
	op_1.opening_index = 20
	building.openings = [op_1, op_0] if reverse_openings else [op_0, op_1]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.queue_canonical_interior_opening_requests(
		building, 0.10, 20.0, 0.61, true, true
	)
	system.finalize_step(building, 20.0)
	var results: Dictionary = system.get_results().duplicate(true)
	building.free()
	return results


func _make_two_room_building(receiver_one_zone: bool):
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var source = _make_room(0, 180.0, 20.0, 0.45, 0.10)
	var receiver = _make_room(1, 20.0, 20.0, 2.40 if receiver_one_zone else 1.35, 0.209)
	building.rooms = {0: source, 1: receiver}
	var opening = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	opening.opening_index = 7
	building.openings = [opening]
	return building


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


func _assert_route(
		route: Dictionary,
		source_side: String,
		source_zone: String,
		destination_side: String,
		destination_zone: String,
		label: String
	) -> void:
	_assert_true(String(route.get("source_side", "")) == source_side, label + " source side")
	_assert_true(
		String(route.get("route_key", "")) == "%s|%s|%s|%s" % [
			source_side, source_zone, destination_side, destination_zone
		],
		label + " route key"
	)


func _assert_source_preserving_routes(routes: Array, label: String) -> void:
	for route in routes:
		_assert_true(
			String(route.get("source_zone", "")) == String(route.get("destination_zone", "")),
			label + " source identity"
		)


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
