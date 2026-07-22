extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_hot_jet_uses_full_poreh_entrainment()
	_test_cool_jet_uses_quarter_poreh_entrainment()
	_test_same_zone_and_wrong_temperature_are_inactive()
	_test_poreh_scaling_contract()
	_test_atomic_receiver_route_conserves_all_payloads()
	_test_slab_decomposition_preserves_aggregates()
	_test_network_pair_is_conservative_and_order_independent()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33G_DOORWAY_JET_ENTRAINMENT_PASS")
		quit(0)


func _test_hot_jet_uses_full_poreh_entrainment() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var source: Dictionary = _thermo_input(180.0, 20.0, 0.40)
	var receiver: Dictionary = _thermo_input(80.0, 20.0, 1.20)
	var preview: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		source, receiver, "upper", 0.50, 0.70, 0.0, 2.0, 0.9, 0.5, 0.1
	)
	_assert_true(bool(preview.get("valid", false)), "hot preview valid")
	_assert_true(bool(preview.get("active", false)), "hot preview active")
	_assert_equal(String(preview.get("mixing_kind", "")), "hot_jet_lower_to_upper", "hot kind")
	_assert_equal(String(preview.get("entrained_source_zone", "")), "lower", "hot source")
	_assert_equal(String(preview.get("entrained_destination_zone", "")), "upper", "hot destination")
	_assert_close(float(preview.get("mixing_factor", 0.0)), 1.0, "hot factor")
	_assert_close(float(preview.get("mixing_depth_m", 0.0)), 0.8, "hot depth")
	_assert_close(
		float(preview.get("entrainment_rate_kg_s", 0.0)),
		0.38571602466724386,
		"hot Poreh rate"
	)


func _test_cool_jet_uses_quarter_poreh_entrainment() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var source: Dictionary = _thermo_input(30.0, 20.0, 1.20)
	var receiver: Dictionary = _thermo_input(120.0, 20.0, 0.40)
	var preview: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		source, receiver, "lower", 0.60, 0.80, 0.0, 2.0, 0.9, 0.5, 0.1
	)
	_assert_true(bool(preview.get("active", false)), "cool preview active")
	_assert_equal(String(preview.get("mixing_kind", "")), "cool_jet_upper_to_lower", "cool kind")
	_assert_equal(String(preview.get("entrained_source_zone", "")), "upper", "cool source")
	_assert_equal(String(preview.get("entrained_destination_zone", "")), "lower", "cool destination")
	_assert_close(float(preview.get("mixing_factor", 0.0)), 0.25, "cool factor")
	_assert_close(
		float(preview.get("entrainment_rate_kg_s", 0.0)),
		0.09063379521952009,
		"cool Poreh rate"
	)


func _test_same_zone_and_wrong_temperature_are_inactive() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var hot: Dictionary = _thermo_input(180.0, 20.0, 0.40)
	var low_interface: Dictionary = _thermo_input(80.0, 20.0, 0.30)
	var same_zone: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		hot, low_interface, "upper", 0.50, 0.70, 0.0, 2.0, 0.9, 0.5, 0.1
	)
	_assert_true(bool(same_zone.get("valid", false)), "same-zone preview valid")
	_assert_true(not bool(same_zone.get("active", true)), "same-zone inactive")
	var cold_source: Dictionary = _thermo_input(20.0, 20.0, 0.40)
	var warm_lower: Dictionary = _thermo_input(80.0, 40.0, 1.20)
	var wrong_gradient: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		cold_source, warm_lower, "upper", 0.50, 0.70, 0.0, 2.0, 0.9, 0.5, 0.1
	)
	_assert_true(bool(wrong_gradient.get("valid", false)), "gradient preview valid")
	_assert_true(not bool(wrong_gradient.get("active", true)), "wrong gradient inactive")


func _test_poreh_scaling_contract() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var source: Dictionary = _thermo_input(180.0, 20.0, 0.40)
	var receiver: Dictionary = _thermo_input(80.0, 20.0, 1.20)
	var baseline: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		source, receiver, "upper", 0.50, 0.70, 0.0, 2.0, 0.9, 0.5, 0.1
	)
	var mass_scaled: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		source, receiver, "upper", 0.50, 0.70, 0.0, 2.0, 0.9, 4.0, 0.1
	)
	var width_scaled: Dictionary = system.preview_canonical_doorway_jet_entrainment(
		source, receiver, "upper", 0.50, 0.70, 0.0, 2.0, 7.2, 0.5, 0.1
	)
	_assert_close(
		float(mass_scaled["entrainment_rate_kg_s"]),
		2.0 * float(baseline["entrainment_rate_kg_s"]),
		"cube-root source-flow scaling"
	)
	_assert_close(
		float(width_scaled["entrainment_rate_kg_s"]),
		4.0 * float(baseline["entrainment_rate_kg_s"]),
		"two-thirds width scaling"
	)


func _test_atomic_receiver_route_conserves_all_payloads() -> void:
	var building = BuildingModelScript.new()
	var room = _make_room()
	building.rooms = {0: room}
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var before: Dictionary = _state_totals(system._snapshots["0"])
	var preview: Dictionary = {
		"valid": true,
		"active": true,
		"entrained_source_zone": "lower",
		"entrained_destination_zone": "upper",
		"gas_mass_kg": float(system._snapshots["0"]["lower_gas_kg"]) * 1.25,
	}
	var route: Dictionary = system.make_canonical_doorway_jet_entrainment_route(
		"f33g:fixture", 0, preview
	)
	_assert_true(bool(route.get("valid", false)), "atomic route valid")
	_assert_true(int(route.get("source_room_id", -1)) == 0, "atomic source room")
	_assert_true(int(route.get("destination_room_id", -1)) == 0, "atomic destination room")
	_assert_equal(String(route.get("source_zone", "")), "lower", "atomic source zone")
	_assert_equal(String(route.get("destination_zone", "")), "upper", "atomic destination zone")
	_assert_true(system.add_atomic_bundle(system.make_atomic_bundle(
		"f33g:fixture", "canonical_doorway_jet_entrainment", [route]
	)), "atomic bundle queued")
	system.finalize_step(building, 20.0)
	var after: Dictionary = _state_totals(system._persistent_zone_state["0"])
	for quantity in ["mass", "energy", "o2", "species"]:
		_assert_close(float(after[quantity]), float(before[quantity]), "atomic conserve " + quantity)
	_assert_close(
		float(system.get_results()["0"]["phase3_shadow_atomic_min_accepted_fraction"]),
		0.8,
		"one shared inventory cap"
	)
	building.free()


func _test_slab_decomposition_preserves_aggregates() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var hot: Dictionary = _thermo_input(180.0, 20.0, 0.45)
	var cold: Dictionary = _thermo_input(40.0, 20.0, 1.25)
	var geometry: Dictionary = {
		"bottom_m": 0.0, "top_m": 2.0, "width_m": 0.9, "open_fraction": 1.0
	}
	var opening: Dictionary = system.preview_canonical_interior_opening(
		hot, cold, geometry, 0.61, 0.1, 64, true
	)
	_assert_true(not opening.get("slabs", []).is_empty(), "opening slabs exist")
	_assert_close(
		_sum_route_mass(opening.get("routes", [])),
		_sum_slab_mass(opening.get("slabs", [])),
		"opening slab aggregate"
	)
	hot["pressure_gauge_pa"] = 120.0
	cold["pressure_gauge_pa"] = 0.0
	var pressure: Dictionary = system.preview_canonical_interior_pressure_flow(
		hot, cold, geometry, 0.61, 0.1, true
	)
	_assert_true(not pressure.get("slabs", []).is_empty(), "pressure slabs exist")
	_assert_close(
		_sum_route_mass(pressure.get("routes", [])),
		_sum_slab_mass(pressure.get("slabs", [])),
		"pressure slab aggregate"
	)


func _test_network_pair_is_conservative_and_order_independent() -> void:
	var normal: Dictionary = _run_three_room_candidate(false)
	var reversed: Dictionary = _run_three_room_candidate(true)
	_assert_true(float(normal.get("jet_route_count", 0.0)) > 0.0, "network jet routes exist")
	_assert_close(float(normal["bundle_count"]), 2.0, "separate direct and jet bundles")
	for quantity in ["mass", "energy", "o2", "species"]:
		_assert_close(float(normal["before"][quantity]), float(normal["after"][quantity]), "network conserve " + quantity)
	for room_key in normal["state"].keys():
		for field_name in [
			"upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
			"upper_o2_kg", "lower_o2_kg",
		]:
			_assert_close(
				float(normal["state"][room_key].get(field_name, 0.0)),
				float(reversed["state"][room_key].get(field_name, 0.0)),
				"network order %s room %s" % [field_name, room_key]
			)


func _run_three_room_candidate(reverse_openings: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_configured_room(0, 180.0, 20.0, 0.45, 0.10),
		1: _make_configured_room(1, 70.0, 20.0, 0.90, 0.17),
		2: _make_configured_room(2, 25.0, 20.0, 1.35, 0.205),
	}
	var first = OpeningModelScript.new(0, 1, 0, 0.9, 2.0, 1.0, 0.0)
	first.opening_index = 10
	var second = OpeningModelScript.new(1, 2, 0, 0.9, 2.0, 1.0, 0.0)
	second.opening_index = 20
	building.openings = [second, first] if reverse_openings else [first, second]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var before: Dictionary = _building_totals(system._snapshots)
	system.queue_canonical_interior_opening_requests(
		building, 0.1, 20.0, 0.61, true, false, true
	)
	var jet_route_count: int = 0
	for bundle in system._atomic_bundles:
		for route in bundle.get("routes", []):
			if String(route.get("cause", "")) == "canonical_doorway_jet_entrainment":
				jet_route_count += 1
	system.finalize_step(building, 20.0)
	var persistent: Dictionary = system._persistent_zone_state.duplicate(true)
	var result: Dictionary = {
		"before": before,
		"after": _building_totals(persistent),
		"state": persistent,
		"bundle_count": system._atomic_bundle_count,
		"jet_route_count": jet_route_count,
	}
	building.free()
	return result


func _make_configured_room(
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
	room.smoke_kg = 0.03 * float(room_id + 1)
	room.co_upper_kg = 0.010 * float(room_id + 1)
	room.co_kg = room.co_upper_kg + 0.004 * float(room_id + 1)
	room.co2_upper_kg = 0.080 * float(room_id + 1)
	room.co2_kg = room.co2_upper_kg + 0.020 * float(room_id + 1)
	room.hcn_upper_kg = 0.002 * float(room_id + 1)
	room.hcn_kg = room.hcn_upper_kg + 0.001 * float(room_id + 1)
	room.hcl_kg = 0.001 * float(room_id + 1)
	room.acrolein_kg = 0.0012 * float(room_id + 1)
	room.formaldehyde_kg = 0.0013 * float(room_id + 1)
	return room


func _make_room():
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	var input: Dictionary = _thermo_input(100.0, 25.0, 1.20)
	room.upper_gas_kg = float(input["upper_gas_kg"])
	room.lower_gas_kg = float(input["lower_gas_kg"])
	room.upper_energy_kj = room.upper_gas_kg * 80.0
	room.lower_energy_kj = room.lower_gas_kg * 5.0
	room.o2_upper = 0.15
	room.o2_lower = 0.20
	room.smoke_kg = 0.03
	room.co_upper_kg = 0.010
	room.co_kg = 0.014
	room.co2_upper_kg = 0.080
	room.co2_kg = 0.100
	room.hcn_upper_kg = 0.002
	room.hcn_kg = 0.003
	room.hcl_kg = 0.001
	room.acrolein_kg = 0.0012
	room.formaldehyde_kg = 0.0013
	return room


func _thermo_input(upper_temp_c: float, lower_temp_c: float, interface_m: float) -> Dictionary:
	var volume_m3: float = 48.0
	var area_m2: float = 20.0
	var lower_volume_m3: float = area_m2 * interface_m
	var upper_volume_m3: float = volume_m3 - lower_volume_m3
	var upper_mass_kg: float = 1.2 * 293.15 / (upper_temp_c + 273.15) * upper_volume_m3
	var lower_mass_kg: float = 1.2 * 293.15 / (lower_temp_c + 273.15) * lower_volume_m3
	var system = Phase3ZoneMassSystemScript.new()
	var result: Dictionary = system.derive_canonical_thermodynamic_state(
		upper_mass_kg,
		lower_mass_kg,
		upper_mass_kg * maxf(0.0, upper_temp_c - 20.0),
		lower_mass_kg * maxf(0.0, lower_temp_c - 20.0),
		volume_m3,
		area_m2,
		2.4,
		20.0
	)
	result["upper_gas_kg"] = upper_mass_kg
	result["lower_gas_kg"] = lower_mass_kg
	return result


func _state_totals(state: Dictionary) -> Dictionary:
	var species_total: float = 0.0
	for zone in ["upper", "lower"]:
		for value in state.get(zone + "_species_kg", {}).values():
			species_total += float(value)
	return {
		"mass": float(state.get("upper_gas_kg", 0.0)) + float(state.get("lower_gas_kg", 0.0)),
		"energy": float(state.get("upper_energy_kj", 0.0)) + float(state.get("lower_energy_kj", 0.0)),
		"o2": float(state.get("upper_o2_kg", 0.0)) + float(state.get("lower_o2_kg", 0.0)),
		"species": species_total,
	}


func _building_totals(states: Dictionary) -> Dictionary:
	var totals: Dictionary = {"mass": 0.0, "energy": 0.0, "o2": 0.0, "species": 0.0}
	for state in states.values():
		var room_totals: Dictionary = _state_totals(state)
		for quantity in totals.keys():
			totals[quantity] = float(totals[quantity]) + float(room_totals[quantity])
	return totals


func _sum_route_mass(routes: Array) -> float:
	var total: float = 0.0
	for route in routes:
		total += float(route.get("gas_mass_kg", 0.0))
	return total


func _sum_slab_mass(slabs: Array) -> float:
	var total: float = 0.0
	for slab in slabs:
		total += float(slab.get("gas_mass_kg", 0.0))
	return total


func _assert_equal(actual: String, expected: String, label: String) -> void:
	if actual != expected:
		push_error("%s expected %s got %s" % [label, expected, actual])
		_failed = true


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
