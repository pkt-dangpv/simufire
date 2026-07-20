extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_equal_ambient_is_quiet()
	_test_hot_upper_produces_bidirectional_exchange()
	_test_gauge_pressure_does_not_own_counterflow_net()
	_test_atomic_routes_conserve_room_mass()
	_test_inventory_cap_is_atomic()
	_test_pressure_relief_and_counterflow_have_separate_owners()
	_test_duplicate_bundle_is_reported()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F32B6_EXTERIOR_COUNTERFLOW_PASS")
		quit(0)


func _test_equal_ambient_is_quiet() -> void:
	var preview: Dictionary = _system().preview_canonical_exterior_counterflow(
		_thermo_input(20.0, 20.0, 0.9), _opening_geometry(), 20.0, 0.61, 1.0
	)
	_assert_true(bool(preview["valid"]), "ambient preview valid")
	_assert_close(float(preview["exchange_kg"]), 0.0, "ambient exchange")


func _test_hot_upper_produces_bidirectional_exchange() -> void:
	var preview: Dictionary = _system().preview_canonical_exterior_counterflow(
		_thermo_input(200.0, 20.0, 0.9), _opening_geometry(), 20.0, 0.61, 1.0
	)
	_assert_true(float(preview["gross_upper_out_kg_s"]) > 0.0, "hot upper out")
	_assert_true(float(preview["gross_lower_in_kg_s"]) > 0.0, "fresh lower in")
	_assert_true(float(preview["exchange_kg_s"]) > 0.0, "compensated exchange")
	_assert_true(
		float(preview["neutral_plane_m"]) > 0.9 \
				and float(preview["neutral_plane_m"]) < 2.1,
		"neutral plane in opening"
	)
	_assert_close(float(preview["hydrostatic_net_kg_s"]), 0.0, "hydrostatic net", 1.0e-7)


func _test_gauge_pressure_does_not_own_counterflow_net() -> void:
	var positive: Dictionary = _thermo_input(200.0, 20.0, 0.9)
	positive["pressure_gauge_pa"] = 100.0
	var negative: Dictionary = positive.duplicate(true)
	negative["pressure_gauge_pa"] = -100.0
	var system = _system()
	var flow_positive: Dictionary = system.preview_canonical_exterior_counterflow(
		positive, _opening_geometry(), 20.0, 0.61, 1.0
	)
	var flow_negative: Dictionary = system.preview_canonical_exterior_counterflow(
		negative, _opening_geometry(), 20.0, 0.61, 1.0
	)
	_assert_close(
		float(flow_positive["exchange_kg"]),
		float(flow_negative["exchange_kg"]),
		"gauge-independent gross exchange"
	)


func _test_atomic_routes_conserve_room_mass() -> void:
	var pair: Dictionary = _building_room(200.0, 1.0)
	var building = pair["building"]
	var system = _system()
	system.begin_step(building, true)
	var before: Dictionary = system.get_canonical_thermodynamic_input(pair["room"], 20.0)
	system.queue_canonical_exterior_counterflow_requests(building, 1.0, 20.0, 0.209)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results()["0"]
	var before_mass: float = float(before["upper_gas_kg"]) + float(before["lower_gas_kg"])
	var after_mass: float = float(result["phase3_shadow_upper_gas_kg"]) \
			+ float(result["phase3_shadow_lower_gas_kg"])
	_assert_close(after_mass, before_mass, "counterflow room mass")
	_assert_true(
		float(result["phase3_shadow_counterflow_accepted_exchange_kg_step"]) > 0.0,
		"counterflow accepted"
	)
	_assert_close(
		float(result["phase3_shadow_counterflow_mass_residual_kg"]), 0.0,
		"counterflow mass residual"
	)
	_assert_true(
		float(result["phase3_shadow_exterior_post_lower_o2_kg"]) > float(before["lower_o2_kg"]),
		"fresh O2 reaches lower"
	)
	building.free()


func _test_inventory_cap_is_atomic() -> void:
	var pair: Dictionary = _building_room(500.0, 1.0)
	var building = pair["building"]
	var system = _system()
	system.begin_step(building, true)
	system.queue_canonical_exterior_counterflow_requests(building, 1000.0, 20.0, 0.209)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results()["0"]
	_assert_true(
		float(result["phase3_shadow_counterflow_accepted_fraction"]) < 1.0,
		"inventory limits common fraction"
	)
	_assert_true(float(result["phase3_shadow_upper_gas_kg"]) >= -1.0e-9, "upper nonnegative")
	_assert_close(
		float(result["phase3_shadow_counterflow_mass_residual_kg"]), 0.0,
		"limited exchange mass residual"
	)
	building.free()


func _test_pressure_relief_and_counterflow_have_separate_owners() -> void:
	var pair: Dictionary = _building_room(200.0, 1.03)
	var building = pair["building"]
	var system = _system()
	system.begin_step(building, true)
	system.queue_canonical_exterior_boundary_requests(
		building, 0.1, 20.0, 0.209, 0.005, 0.0, 0.61, true
	)
	system.queue_canonical_exterior_counterflow_requests(building, 0.1, 20.0, 0.209)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results()["0"]
	_assert_true(
		float(result["phase3_shadow_counterflow_accepted_exchange_kg_step"]) > 0.0,
		"gross exchange owner active"
	)
	_assert_true(
		float(result["phase3_shadow_counterflow_pressure_relief_kg_step"]) > 0.0,
		"net pressure owner active"
	)
	_assert_close(
		float(result["phase3_shadow_counterflow_mass_residual_kg"]), 0.0,
		"combined owners no counterflow net"
	)
	_assert_close(
		float(result["phase3_shadow_counterflow_duplicate_owner_flag"]), 0.0,
		"owners are distinct"
	)
	building.free()


func _test_duplicate_bundle_is_reported() -> void:
	var pair: Dictionary = _building_room(200.0, 1.0)
	var building = pair["building"]
	var system = _system()
	system.begin_step(building, true)
	system.queue_canonical_exterior_counterflow_requests(building, 0.1, 20.0, 0.209)
	system.queue_canonical_exterior_counterflow_requests(building, 0.1, 20.0, 0.209)
	system.finalize_step(building, 20.0)
	_assert_close(
		float(system.get_results()["0"]["phase3_shadow_counterflow_duplicate_owner_flag"]),
		1.0,
		"duplicate counterflow owner"
	)
	building.free()


func _thermo_input(upper_temp_c: float, lower_temp_c: float, interface_m: float) -> Dictionary:
	var system = _system()
	var room_volume_m3: float = 48.0
	var floor_area_m2: float = 20.0
	var lower_volume_m3: float = floor_area_m2 * interface_m
	var upper_volume_m3: float = room_volume_m3 - lower_volume_m3
	var reference_k: float = 293.15
	var upper_mass_kg: float = 1.2 * reference_k / (upper_temp_c + 273.15) * upper_volume_m3
	var lower_mass_kg: float = 1.2 * reference_k / (lower_temp_c + 273.15) * lower_volume_m3
	var result: Dictionary = system.derive_canonical_thermodynamic_state(
		upper_mass_kg,
		lower_mass_kg,
		upper_mass_kg * (upper_temp_c - 20.0),
		lower_mass_kg * (lower_temp_c - 20.0),
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
		"bottom_m": 0.9,
		"top_m": 2.1,
		"width_m": 1.0,
		"open_fraction": 1.0,
		"room_height_m": 2.4,
	}


func _building_room(upper_temp_c: float, mass_scale: float) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	var input: Dictionary = _thermo_input(upper_temp_c, 20.0, 0.9)
	room.upper_gas_kg = float(input["upper_gas_kg"]) * mass_scale
	room.lower_gas_kg = float(input["lower_gas_kg"]) * mass_scale
	room.upper_energy_kj = room.upper_gas_kg * (upper_temp_c - 20.0)
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.10
	room.o2_lower = 0.209
	room.co_upper_kg = 0.1
	room.co_kg = 0.1
	building.rooms = {0: room}
	var opening = OpeningModelScript.new(0, BuildingModelScript.OUTSIDE_ID, 1, 1.0, 1.2, 1.0, 0.9)
	opening.opening_index = 0
	opening.open_fraction_smooth = 1.0
	building.openings = [opening]
	return {"building": building, "room": room}


func _system():
	return Phase3ZoneMassSystemScript.new()


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(actual: float, expected: float, label: String, tolerance: float = 1.0e-8) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %s got %s" % [label, str(expected), str(actual)])
		_failed = true
