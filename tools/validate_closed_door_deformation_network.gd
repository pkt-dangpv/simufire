extends SceneTree

## F2.2D2: deformacion prescrita de puerta cerrada dentro de la red de presion.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_closed_door_deformation_network.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")
const DeformationAdapter := preload("res://sim/core/ClosedDoorDeformationNetworkAdapter.gd")

const T_REF_K: float = 293.15
const HEIGHT_M: float = 2.4
const DOOR_HEIGHT_M: float = 2.0
const FLOOR_AREA_M2: float = 20.0
const AMBIENT_MASS_KG: float = 1.2 * FLOOR_AREA_M2 * HEIGHT_M
const DT_S: float = 0.0833333333333333
const COLD_ELA_M2: float = 0.0021
const TOL: float = 1.0e-9

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_test_01_default_off_and_scope()
	_test_02_off_and_zero_are_exactly_identical()
	_test_03_interpolation_and_combination()
	_test_04_deformation_without_cold_leakage()
	_test_05_local_heights_become_absolute_once()
	_test_06_invalid_tracks_fail_closed()
	_test_07_open_door_excludes_deformation_crack()
	_test_08_legacy_thermal_gap_is_not_d2()
	_test_09_transport_is_atomic_and_conservative()
	_test_10_nonfinite_time_fails_closed()
	_test_11_engine_wires_d2_once_at_simulation_time()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("CLOSED DOOR DEFORMATION NETWORK VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("CLOSED DOOR DEFORMATION NETWORK VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	return absf(actual - expected) <= tol * maxf(1.0, absf(expected))


func _top(points: Array) -> Dictionary:
	return {"id": "top", "location": "top", "z_m": DOOR_HEIGHT_M,
		"points": points, "metadata": {"source": "prescribed_test"}}


func _latch(points: Array) -> Dictionary:
	return {"id": "latch_side_06", "location": "latch_side", "z_m": 1.625,
		"points": points, "metadata": {"source": "prescribed_test"}}


func _tracks() -> Array:
	return [
		_top([[0.0, 0.0], [600.0, 0.0030]]),
		_latch([[0.0, 0.0], [600.0, 0.0010]]),
	]


func _make_building(floor_z_m: float = 0.0) -> BuildingModel:
	var template: Dictionary = {
		"building_type": "house",
		"floors": [{"level_m": floor_z_m, "name": "R"}],
		"rooms_data": [
			{"id": 0, "name": "R0", "kind": "salon", "floor_level_z_m": floor_z_m,
				"height_m": HEIGHT_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": [], "rotation_deg": 0.0},
			{"id": 1, "name": "R1", "kind": "salon", "floor_level_z_m": floor_z_m,
				"height_m": HEIGHT_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
				"fuel_objects": [], "rotation_deg": 0.0},
		],
		"room_rect_m": {
			"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0},
			"1": {"x": 5.0, "y": 0.0, "w": 5.0, "h": 4.0},
		},
		"openings_data": [{
			"a": 0, "b": 1, "type": "door", "open_fraction": 0.0,
			"width_m": 0.9, "height_m": DOOR_HEIGHT_M, "sill_m": 0.0,
			"wall": "right", "offset_m": 2.0, "offset_is_fraction": false,
		}],
	}
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	_seed(building.get_room(0), 12.0, 493.15, 40.0, 298.15)
	_seed(building.get_room(1), 0.0, T_REF_K, AMBIENT_MASS_KG, T_REF_K)
	return building


func _seed(room, upper_kg: float, upper_temp_k: float,
		lower_kg: float, lower_temp_k: float) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_kg * (upper_temp_k - T_REF_K)
	room.lower_energy_kj = lower_kg * (lower_temp_k - T_REF_K)


func _system(cold: bool, deformation: bool):
	var system = TransportScript.new()
	system.closed_door_leakage_enabled = cold
	system.closed_door_deformation_enabled = deformation
	return system


func _snapshot(building: BuildingModel, cold: bool, deformation: bool,
		time_s: float) -> Dictionary:
	return _system(cold, deformation).build_snapshot(building, {}, DT_S, time_s)


func _element(snapshot: Dictionary, element_id: String = "crack_0") -> Dictionary:
	for raw_element in snapshot.get("openings", []):
		var element: Dictionary = raw_element
		if String(element["opening_id"]) == element_id:
			return element
	return {}


func _segment(element: Dictionary, segment_id: String) -> Dictionary:
	for raw_segment in element.get("crack_segments", []):
		var segment: Dictionary = raw_segment
		if String(segment["segment_id"]) == segment_id:
			return segment
	return {}


func _total_mass_kg(building: BuildingModel) -> float:
	var total: float = 0.0
	for room in building.get_rooms().values():
		total += float(room.upper_gas_kg) + float(room.lower_gas_kg)
	return total


func _total_energy_kj(building: BuildingModel) -> float:
	var total: float = 0.0
	for room in building.get_rooms().values():
		total += float(room.upper_energy_kj) + float(room.lower_energy_kj)
	return total


func _exact_diffs(left: Variant, right: Variant, path: String,
		out: Array[String]) -> void:
	if typeof(left) != typeof(right):
		out.append(path + " type")
		return
	match typeof(left):
		TYPE_DICTIONARY:
			var left_keys: Array = (left as Dictionary).keys()
			var right_keys: Array = (right as Dictionary).keys()
			left_keys.sort()
			right_keys.sort()
			if left_keys != right_keys:
				out.append(path + " keys")
				return
			for key in left_keys:
				_exact_diffs(left[key], right[key], "%s/%s" % [path, key], out)
		TYPE_ARRAY:
			if (left as Array).size() != (right as Array).size():
				out.append(path + " size")
				return
			for index in range((left as Array).size()):
				_exact_diffs(left[index], right[index], "%s/%d" % [path, index], out)
		TYPE_FLOAT:
			if float(left) != float(right):
				out.append(path + " value")
		_:
			if left != right:
				out.append(path + " value")


func _free_building(building: BuildingModel) -> void:
	building.free()


func _test_01_default_off_and_scope() -> void:
	var system = TransportScript.new()
	_check(not bool(system.closed_door_deformation_enabled), "01 D2 defaults OFF")
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.deformation_tracks = _tracks()
	_check(DeformationAdapter.provides_deformation(door, BuildingModel.OUTSIDE_ID),
			"01 a closed interior door with tracks provides deformation")
	door.set_open_fraction(1.0)
	_check(not DeformationAdapter.provides_deformation(door, BuildingModel.OUTSIDE_ID),
			"01 an open door never provides a deformation crack")
	_free_building(building)


func _test_02_off_and_zero_are_exactly_identical() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	var no_tracks: Dictionary = _snapshot(building, true, false, 600.0)
	door.deformation_tracks = _tracks()
	var d2_off: Dictionary = _snapshot(building, true, false, 600.0)
	var diffs: Array[String] = []
	_exact_diffs(no_tracks, d2_off, "snapshot", diffs)
	_check(diffs.is_empty(), "02 tracks are invisible with D2 OFF (%s)" % [diffs])
	var zero: Dictionary = _snapshot(building, true, true, 0.0)
	diffs.clear()
	_exact_diffs(_element(d2_off), _element(zero), "crack", diffs)
	_check(diffs.is_empty(), "02 zero deformation is byte-identical to D1 (%s)" % [diffs])
	_free_building(building)


func _test_03_interpolation_and_combination() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	door.deformation_tracks = _tracks()
	var element: Dictionary = _element(_snapshot(building, true, true, 300.0))
	_check(not element.is_empty(), "03 the combined crack exists")
	if element.is_empty():
		_free_building(building)
		return
	_check(_close(float(element["cold_ela_total_m2"]), COLD_ELA_M2),
			"03 the cold ELA is preserved")
	_check(_close(float(element["additional_ela_total_m2"]), 0.0020),
			"03 the prescribed ELA is interpolated")
	_check(_close(float(element["combined_ela_total_m2"]), COLD_ELA_M2 + 0.0020),
			"03 cold and prescribed ELA add once")
	_check(String(element["provenance"]) == "cold_leakage+prescribed_deformation",
			"03 combined provenance is explicit")
	var top: Dictionary = _segment(element, "top")
	var latch: Dictionary = _segment(element, "latch_side_06")
	_check(not top.is_empty() and not latch.is_empty(), "03 top and latch are localized segments")
	if not top.is_empty():
		_check(_close(float(top["additional_area_m2"]), 0.0015),
				"03 top interpolation is correct")
	if not latch.is_empty():
		_check(_close(float(latch["additional_area_m2"]), 0.0005),
				"03 latch interpolation is correct")
	_free_building(building)


func _test_04_deformation_without_cold_leakage() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.deformation_tracks = _tracks()
	var element: Dictionary = _element(_snapshot(building, false, true, 600.0))
	_check(not element.is_empty(), "04 D2 does not require D1")
	if not element.is_empty():
		_check(_close(float(element["cold_ela_total_m2"]), 0.0),
				"04 deformation-only has no cold ELA")
		_check(_close(float(element["additional_ela_total_m2"]), 0.0040),
				"04 deformation-only carries the prescribed ELA")
		_check(String(element["provenance"]) == "prescribed_deformation",
				"04 deformation-only provenance is explicit")
		_check(_close(float(element["resolved_ela_m2"]), 0.0),
				"04 the D1 resolved ELA remains zero")
	_free_building(building)


func _test_05_local_heights_become_absolute_once() -> void:
	var building: BuildingModel = _make_building(6.0)
	var door = building.get_openings()[0]
	door.deformation_tracks = _tracks()
	var element: Dictionary = _element(_snapshot(building, false, true, 600.0))
	var top: Dictionary = _segment(element, "top")
	var latch: Dictionary = _segment(element, "latch_side_06")
	_check(not top.is_empty() and _close(float(top["z_m"]), 8.0),
			"05 top local height is translated once")
	_check(not latch.is_empty() and _close(float(latch["z_m"]), 7.625),
			"05 latch local height is translated once")
	_free_building(building)


func _test_06_invalid_tracks_fail_closed() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.deformation_tracks = [
		{"id": "top", "location": "top", "z_m": 2.0,
			"points": [[0.0, 0.001], [0.0, 0.002]]},
	]
	var snapshot: Dictionary = _snapshot(building, false, true, 10.0)
	_check(not bool(snapshot["valid"]), "06 invalid tracks reject the snapshot")
	_check(not Array(snapshot["errors"]).is_empty(), "06 rejection explains the error")
	_check(Array(snapshot["openings"]).is_empty(), "06 invalid D2 never reaches the solver")
	_free_building(building)


func _test_07_open_door_excludes_deformation_crack() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.deformation_tracks = _tracks()
	door.set_open_fraction(1.0)
	var snapshot: Dictionary = _snapshot(building, false, true, 600.0)
	_check(bool(snapshot["valid"]), "07 an open door remains a valid large opening")
	_check(_element(snapshot, "crack_0").is_empty(), "07 an open door has no D2 crack")
	_check(not _element(snapshot, "op_0").is_empty(), "07 an open door has one large opening")
	_free_building(building)


func _test_08_legacy_thermal_gap_is_not_d2() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.thermal_gap_fraction = 0.75
	var snapshot: Dictionary = _snapshot(building, false, true, 600.0)
	_check(bool(snapshot["valid"]), "08 thermal_gap_fraction does not invalidate D2")
	_check(Array(snapshot["openings"]).is_empty(),
			"08 thermal_gap_fraction does not create a network opening")
	_free_building(building)


func _test_09_transport_is_atomic_and_conservative() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.leakage_class = "interior_tight"
	door.deformation_tracks = _tracks()
	var source = building.get_room(0)
	var receiver = building.get_room(1)
	source.smoke_kg = 0.20
	source.o2_upper = 0.16
	source.o2_lower = 0.18
	var mass_before: float = _total_mass_kg(building)
	var energy_before: float = _total_energy_kj(building)
	var receiver_smoke_before: float = float(receiver.smoke_kg)
	var system = _system(true, true)
	var result: Dictionary = system.step(building, DT_S, {}, 600.0)
	_check(bool(result.get("applied", false)), "09 combined transport applies (%s)"
			% result.get("failure_reason", "?"))
	_check(int(system.commit_count) == 1, "09 the atomic applier commits exactly once")
	_check(_close(_total_mass_kg(building), mass_before, 1.0e-9),
			"09 inter-room D2 conserves total gas mass")
	_check(_close(_total_energy_kj(building), energy_before, 1.0e-9),
			"09 inter-room D2 conserves total gas energy")
	_check(float(receiver.smoke_kg) > receiver_smoke_before,
			"09 D2 transports smoke with the gas")
	if bool(result.get("applied", false)):
		var solved: Dictionary = _element(result["solution"], "crack_0")
		_check(not solved.is_empty(), "09 the solved connection is the D2 crack")
	_free_building(building)


func _test_10_nonfinite_time_fails_closed() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.deformation_tracks = _tracks()
	var snapshot: Dictionary = _snapshot(building, false, true, NAN)
	_check(not bool(snapshot["valid"]), "10 a non-finite deformation time is rejected")
	_check(Array(snapshot["openings"]).is_empty(), "10 invalid time reaches no solver element")
	_free_building(building)


func _test_11_engine_wires_d2_once_at_simulation_time() -> void:
	var building: BuildingModel = _make_building()
	var door = building.get_openings()[0]
	door.deformation_tracks = [
		_top([[0.0, 0.0], [1.0, 0.0010]]),
	]
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.pressure_network_solver_enabled = true
	engine.closed_door_deformation_enabled = true
	engine.suppress_exit_graphs()
	root.add_child(building)
	root.add_child(engine)
	engine.reset_simulation(0, false)
	_seed(building.get_room(0), 12.0, 493.15, 40.0, 298.15)
	_seed(building.get_room(1), 0.0, T_REF_K, AMBIENT_MASS_KG, T_REF_K)
	engine.step(DT_S)
	_check(_close(float(engine.sim_time_s), DT_S, 1.0e-12),
			"11 engine advances the prescribed deformation clock")
	_check(bool(engine.pressure_network_transport_system.closed_door_deformation_enabled),
			"11 engine wires D2 into the transport system")
	_check(int(engine.pressure_network_transport_system.commit_count) == 1,
			"11 engine commits the authoritative transport exactly once")
	_check(bool(engine.pressure_network_last_result.get("applied", false)),
			"11 engine applies D2 through the authoritative network")
	if bool(engine.pressure_network_last_result.get("applied", false)):
		var solved: Dictionary = _element(engine.pressure_network_last_result["solution"], "crack_0")
		_check(not solved.is_empty(), "11 the engine solves one D2 crack element")
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()
