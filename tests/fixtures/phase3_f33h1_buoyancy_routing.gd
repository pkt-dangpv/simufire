extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_exact_cfast_tanhsmooth_contract()
	_test_interval_uses_temperature_not_geometry_or_source_identity()
	_test_opening_and_pressure_preserve_total_flow()
	_test_atomic_direct_and_poreh_bundles_remain_separate()
	_test_opening_order_is_equivalent()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33H1_BUOYANCY_ROUTING_PASS")
		quit(0)


func _test_exact_cfast_tanhsmooth_contract() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var cold: Dictionary = system.preview_cfast_buoyancy_destination_split(
		19.0, 100.0, 20.0
	)
	var midpoint: Dictionary = system.preview_cfast_buoyancy_destination_split(
		60.0, 100.0, 20.0
	)
	var hot: Dictionary = system.preview_cfast_buoyancy_destination_split(
		101.0, 100.0, 20.0
	)
	_assert_close(float(cold["lower"]), 1.0, "cold lower")
	_assert_close(float(cold["upper"]), 0.0, "cold upper")
	_assert_close(float(midpoint["lower"]), 0.5, "mid lower")
	_assert_close(float(midpoint["upper"]), 0.5, "mid upper")
	_assert_close(float(hot["lower"]), 0.0, "hot lower")
	_assert_close(float(hot["upper"]), 1.0, "hot upper")
	var inverted: Dictionary = system.preview_cfast_buoyancy_destination_split(
		20.0, 20.0, 100.0
	)
	_assert_close(float(inverted["lower"]), 0.5, "inverted lower clamp")
	_assert_close(float(inverted["upper"]), 0.5, "inverted upper clamp")


func _test_interval_uses_temperature_not_geometry_or_source_identity() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var source: Dictionary = _thermo_input(120.0, 60.0, 1.20)
	var receiver: Dictionary = _thermo_input(100.0, 20.0, 0.10)
	var source_density: Dictionary = system._canonical_zone_densities(source)
	var receiver_density: Dictionary = system._canonical_zone_densities(receiver)
	var interval: Dictionary = system._canonical_interior_interval_flow(
		source, receiver, source_density, receiver_density,
		0.20, 0.40, 4.0, 4.0, 1.0, 1.0, 0.61, false, true
	)
	_assert_equal(String(interval["source_zone"]), "lower", "geometric source")
	_assert_equal(
		String(interval["geometric_destination_zone"]), "upper", "geometric receiver"
	)
	_assert_close(float(interval["source_temp_c"]), 60.0, "slab source temperature")
	var fractions: Dictionary = interval["destination_fractions"]
	_assert_close(float(fractions["lower"]), 0.5, "thermal lower split")
	_assert_close(float(fractions["upper"]), 0.5, "thermal upper split")
	var routes: Dictionary = {}
	system._accumulate_canonical_interior_route(routes, interval)
	var total: float = 0.0
	for value in routes.values():
		total += float(value)
	_assert_close(total, float(interval["mass_flow_kg_s"]), "split preserves slab mass")
	_assert_true(routes.has("a|lower|b|lower"), "lower route exists")
	_assert_true(routes.has("a|lower|b|upper"), "upper route exists")


func _test_opening_and_pressure_preserve_total_flow() -> void:
	var system = Phase3ZoneMassSystemScript.new()
	var hot: Dictionary = _thermo_input(180.0, 30.0, 0.45)
	var cool: Dictionary = _thermo_input(80.0, 20.0, 1.20)
	var geometry: Dictionary = _opening_geometry()
	var legacy: Dictionary = system.preview_canonical_interior_opening(
		hot, cool, geometry, 0.61, 0.10
	)
	var candidate: Dictionary = system.preview_canonical_interior_opening(
		hot, cool, geometry, 0.61, 0.10, 64, false, true
	)
	for field_name in [
		"gross_a_to_b_kg", "gross_b_to_a_kg", "net_a_to_b_kg",
		"exchange_kg", "neutral_plane_m", "neutral_pressure_offset_pa",
	]:
		_assert_close(
			float(candidate[field_name]), float(legacy[field_name]),
			"opening invariant " + field_name
		)
	_assert_close(
		_sum_route_mass(candidate["routes"]),
		float(candidate["gross_a_to_b_kg"]) + float(candidate["gross_b_to_a_kg"]),
		"opening split route total"
	)
	hot["pressure_gauge_pa"] = 120.0
	cool["pressure_gauge_pa"] = 0.0
	var pressure_legacy: Dictionary = system.preview_canonical_interior_pressure_flow(
		hot, cool, geometry, 0.61, 0.10
	)
	var pressure_candidate: Dictionary = system.preview_canonical_interior_pressure_flow(
		hot, cool, geometry, 0.61, 0.10, false, true
	)
	_assert_close(
		float(pressure_candidate["signed_net_a_to_b_kg"]),
		float(pressure_legacy["signed_net_a_to_b_kg"]),
		"pressure signed flow invariant"
	)
	_assert_close(
		_sum_route_mass(pressure_candidate["routes"]),
		absf(float(pressure_candidate["signed_net_a_to_b_kg"])),
		"pressure split route total"
	)


func _test_atomic_direct_and_poreh_bundles_remain_separate() -> void:
	var result: Dictionary = _run_network(false)
	_assert_true(result["direct_bundle"], "direct bundle exists")
	_assert_true(result["poreh_bundle"], "Poreh bundle exists")
	_assert_true(int(result["direct_route_count"]) > 0, "direct routes exist")
	_assert_true(int(result["poreh_route_count"]) > 0, "Poreh routes exist")
	for quantity in ["mass", "energy", "o2", "species"]:
		_assert_close(
			float(result["after"][quantity]), float(result["before"][quantity]),
			"building conserves " + quantity
		)


func _test_opening_order_is_equivalent() -> void:
	var normal: Dictionary = _run_network(false)
	var reversed: Dictionary = _run_network(true)
	for room_key in normal["state"].keys():
		var normal_room: Dictionary = normal["state"][room_key]
		var reversed_room: Dictionary = reversed["state"][room_key]
		for field_name in [
			"upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
			"upper_o2_kg", "lower_o2_kg",
		]:
			_assert_close(
				float(normal_room[field_name]), float(reversed_room[field_name]),
				"order %s room %s" % [field_name, room_key], 1.0e-10
			)


func _run_network(reverse_openings: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_room(0, 180.0, 20.0, 0.45, 0.10),
		1: _make_room(1, 70.0, 20.0, 0.90, 0.17),
		2: _make_room(2, 25.0, 20.0, 1.35, 0.205),
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
		building, 0.10, 20.0, 0.61, true, false, true, true
	)
	var direct_bundle: bool = false
	var poreh_bundle: bool = false
	var direct_route_count: int = 0
	var poreh_route_count: int = 0
	for bundle in system._atomic_bundles:
		var bundle_id: String = String(bundle.get("bundle_id", ""))
		if bundle_id == "f33a_interior_network":
			direct_bundle = true
			direct_route_count += bundle.get("routes", []).size()
			for route in bundle.get("routes", []):
				_assert_true(
					String(route.get("cause", "")) != "canonical_doorway_jet_entrainment",
					"direct bundle excludes Poreh"
				)
		elif bundle_id == "f33g_doorway_jet_network":
			poreh_bundle = true
			poreh_route_count += bundle.get("routes", []).size()
			for route in bundle.get("routes", []):
				_assert_equal(
					String(route.get("cause", "")),
					"canonical_doorway_jet_entrainment",
					"Poreh bundle owns only mixing"
				)
	system.finalize_step(building, 20.0)
	var state: Dictionary = system._persistent_zone_state.duplicate(true)
	var result: Dictionary = {
		"before": before,
		"after": _building_totals(state),
		"state": state,
		"direct_bundle": direct_bundle,
		"poreh_bundle": poreh_bundle,
		"direct_route_count": direct_route_count,
		"poreh_route_count": poreh_route_count,
	}
	building.free()
	return result


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
	result["reference_temp_c"] = 20.0
	return result


func _opening_geometry() -> Dictionary:
	return {"bottom_m": 0.0, "top_m": 2.0, "width_m": 0.9, "open_fraction": 1.0}


func _building_totals(states: Dictionary) -> Dictionary:
	var totals: Dictionary = {"mass": 0.0, "energy": 0.0, "o2": 0.0, "species": 0.0}
	for state in states.values():
		totals["mass"] += float(state.get("upper_gas_kg", 0.0)) \
				+ float(state.get("lower_gas_kg", 0.0))
		totals["energy"] += float(state.get("upper_energy_kj", 0.0)) \
				+ float(state.get("lower_energy_kj", 0.0))
		totals["o2"] += float(state.get("upper_o2_kg", 0.0)) \
				+ float(state.get("lower_o2_kg", 0.0))
		for zone_name in ["upper", "lower"]:
			for value in state.get(zone_name + "_species_kg", {}).values():
				totals["species"] += float(value)
	return totals


func _sum_route_mass(routes: Array) -> float:
	var total: float = 0.0
	for route in routes:
		total += float(route.get("gas_mass_kg", 0.0))
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
