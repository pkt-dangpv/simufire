extends SceneTree

## F2.2D3: integracion del desprendimiento prescrito de vidrio en la red.
##
##   <godot> --headless --path . --script \
##       res://tools/validate_glazing_fallout_network.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const SimulationEngineScript := preload("res://sim/core/SimulationEngine.gd")
const TransportScript := preload("res://sim/core/PressureNetworkTransportSystem.gd")
const Adapter := preload("res://sim/core/GlazingFalloutNetworkAdapter.gd")
const WindModel := preload("res://sim/core/ExteriorWindPressureModel.gd")

const HEIGHT_M: float = 2.5
const T_REF_K: float = 293.15
const DT_S: float = 0.0833333333333333
const TOL: float = 1.0e-9

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_test_01_default_off_and_exact_identity()
	_test_02_states_and_absolute_geometry()
	_test_03_multilayer_intersection()
	_test_04_invalid_contracts_fail_closed()
	_test_05_operational_opening_is_exclusive()
	_test_06_coexists_with_frame_leakage()
	_test_07_atomic_transport_and_species()
	_test_08_exterior_wind_at_rectangle_height()
	_test_09_nonfinite_time_fails_closed()
	_test_10_engine_wires_d3_at_simulation_time()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("GLAZING FALLOUT NETWORK VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("GLAZING FALLOUT NETWORK VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	return absf(actual - expected) <= tol * maxf(1.0, absf(expected))


func _leaf(leaf_id: String, index: int, partial_time_s: float = 10.0,
		open_time_s: float = 20.0) -> Dictionary:
	return {
		"id": leaf_id,
		"index": index,
		"events": [
			{"time_s": 0.0, "state": "CRACKED", "fallout_fraction": 0.0},
			{"time_s": partial_time_s, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.5},
			{"time_s": open_time_s, "state": "OPEN", "fallout_fraction": 1.0},
		],
	}


func _panel(panel_id: String = "pane", host_x_m: float = 0.10,
		leaf_count: int = 1) -> Dictionary:
	var leaves: Array = []
	for index in range(leaf_count):
		leaves.append(_leaf("leaf_%d" % index, index))
	return {
		"id": panel_id,
		"host_x_m": host_x_m,
		"width_m": 0.60,
		"height_m": 1.00,
		"sill_z_m": 0.50,
		"glass_type": "annealed",
		"thickness_m": 0.006,
		"leaf_count": leaf_count,
		"leaf_spacing_m": 0.0 if leaf_count == 1 else 0.012,
		"frame_material": "wood",
		"edge_protection_depth_m": 0.01,
		"leaves": leaves,
	}


func _regions_for_half(leaf_count: int, aligned: bool = true) -> Array:
	var leaves: Array = []
	for index in range(leaf_count):
		var z_m: float = 0.0 if aligned or index == 0 else 0.5
		leaves.append({
			"id": "leaf_%d" % index,
			"index": index,
			"regions": [{
				"id": "missing_%d" % index,
				"x_m": 0.0, "z_m": z_m, "width_m": 0.60, "height_m": 0.50,
			}],
		})
	return leaves


func _empty_leaves(leaf_count: int) -> Array:
	var leaves: Array = []
	for index in range(leaf_count):
		leaves.append({"id": "leaf_%d" % index, "index": index, "regions": []})
	return leaves


func _spatial(panel_id: String = "pane", leaf_count: int = 1,
		aligned: bool = true) -> Dictionary:
	return {
		"panel_id": panel_id,
		"snapshots": [
			{"time_s": 0.0, "leaves": _empty_leaves(leaf_count)},
			{"time_s": 10.0, "leaves": _regions_for_half(leaf_count, aligned)},
			{"time_s": 20.0, "leaves": _empty_leaves(leaf_count)},
		],
	}


func _building(exterior: bool = false, open_fraction: float = 0.0,
		kind: String = "window", floor_z_m: float = 0.0) -> BuildingModel:
	var rooms: Array = [{
		"id": 0, "name": "R0", "kind": "salon", "floor_level_z_m": floor_z_m,
		"height_m": HEIGHT_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
		"fuel_objects": [], "rotation_deg": 0.0,
	}]
	var rects: Dictionary = {"0": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}}
	var b_id: int = BuildingModel.OUTSIDE_ID
	if not exterior:
		b_id = 1
		rooms.append({
			"id": 1, "name": "R1", "kind": "salon", "floor_level_z_m": floor_z_m,
			"height_m": HEIGHT_M, "fuel_energy_MJ": 0.0, "max_hrr_kw": 0.0,
			"fuel_objects": [], "rotation_deg": 0.0,
		})
		rects["1"] = {"x": 5.0, "y": 0.0, "w": 5.0, "h": 4.0}
	var template: Dictionary = {
		"building_type": "house",
		"floors": [{"level_m": floor_z_m, "name": "R"}],
		"rooms_data": rooms,
		"room_rect_m": rects,
		"openings_data": [{
			"a": 0, "b": b_id, "type": kind, "open_fraction": open_fraction,
			"width_m": 1.20, "height_m": 2.00, "sill_m": 0.20,
			"wall": "right", "offset_m": 2.0, "offset_is_fraction": false,
		}],
	}
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)
	_seed(building.get_room(0), 12.0, 493.15, 40.0, 298.15)
	if not exterior:
		_seed(building.get_room(1), 0.0, T_REF_K, 72.0, T_REF_K)
	return building


func _seed(room, upper_kg: float, upper_temp_k: float,
		lower_kg: float, lower_temp_k: float) -> void:
	room.upper_gas_kg = upper_kg
	room.lower_gas_kg = lower_kg
	room.upper_energy_kj = upper_kg * (upper_temp_k - T_REF_K)
	room.lower_energy_kj = lower_kg * (lower_temp_k - T_REF_K)


func _declare(opening, panel: Dictionary = {}, spatial: Dictionary = {}) -> void:
	opening.glazing_panels = [_panel()] if panel.is_empty() else [panel]
	opening.glazing_spatial = [_spatial()] if spatial.is_empty() else [spatial]


func _system(enabled: bool = true):
	var system = TransportScript.new()
	system.glazing_fallout_enabled = enabled
	return system


func _glazing(snapshot: Dictionary) -> Array:
	var found: Array = []
	for raw in snapshot.get("openings", []):
		var element: Dictionary = raw
		if String(element.get("provenance", "")) == Adapter.PROVENANCE \
				or String(element.get("opening_id", "")).begins_with("glazing_"):
			found.append(element)
	return found


func _total_mass(building: BuildingModel) -> float:
	var total: float = 0.0
	for room in building.get_rooms().values():
		total += float(room.upper_gas_kg) + float(room.lower_gas_kg)
	return total


func _total_energy(building: BuildingModel) -> float:
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


func _free(building: BuildingModel) -> void:
	building.free()


func _test_01_default_off_and_exact_identity() -> void:
	var system = TransportScript.new()
	_check(not bool(system.glazing_fallout_enabled), "01 D3 defaults OFF")
	var building: BuildingModel = _building()
	var before: Dictionary = system.build_snapshot(building, {}, DT_S, 10.0)
	_declare(building.get_openings()[0])
	var after: Dictionary = system.build_snapshot(building, {}, DT_S, 10.0)
	var diffs: Array[String] = []
	_exact_diffs(before, after, "snapshot", diffs)
	_check(diffs.is_empty(), "01 declarations are byte-invisible with D3 OFF (%s)" % [diffs])
	_free(building)


func _test_02_states_and_absolute_geometry() -> void:
	var building: BuildingModel = _building(false, 0.0, "window", 6.0)
	_declare(building.get_openings()[0])
	var cracked: Dictionary = _system().build_snapshot(building, {}, DT_S, 0.0)
	_check(_glazing(cracked).is_empty(), "02 CRACKED glass vents nothing")
	var partial: Array = _glazing(_system().build_snapshot(building, {}, DT_S, 10.0))
	_check(partial.size() == 1, "02 partial fallout creates one rectangle")
	if partial.size() == 1:
		var element: Dictionary = partial[0]
		_check(String(element["opening_id"]) == "glazing_0_000_000",
				"02 rectangle keeps a stable network id")
		_check(String(element["flow_model"]) == "large_opening",
				"02 rectangle delegates to the canonical large-opening law")
		_check(_close(float(element["discharge_coeff"]), 0.61),
				"02 rectangle keeps the inherited Cd")
		_check(_close(float(element["open_fraction"]), 1.0),
				"02 free rectangle is fully open")
		_check(_close(float(element["width_m"]), 0.60), "02 rectangle keeps its width")
		_check(_close(float(element["top_z_m"]) - float(element["bottom_z_m"]), 0.50),
				"02 rectangle keeps its height")
		_check(_close(float(element["bottom_z_m"]), 6.0 + 0.20 + 0.50),
				"02 local sill becomes absolute exactly once")
	var opened: Array = _glazing(_system().build_snapshot(building, {}, DT_S, 20.0))
	_check(opened.size() == 1 and _close(float(opened[0]["width_m"]), 0.60)
			and _close(float(opened[0]["top_z_m"]) - float(opened[0]["bottom_z_m"]), 1.0),
			"02 OPEN glass exposes the full panel")
	_free(building)


func _test_03_multilayer_intersection() -> void:
	var building: BuildingModel = _building()
	var opening = building.get_openings()[0]
	_declare(opening, _panel("pane", 0.1, 2), _spatial("pane", 2, false))
	var disjoint: Array = _glazing(_system().build_snapshot(building, {}, DT_S, 10.0))
	_check(disjoint.is_empty(), "03 misaligned leaf fallout has no free path")
	opening.glazing_spatial = [_spatial("pane", 2, true)]
	var aligned: Array = _glazing(_system().build_snapshot(building, {}, DT_S, 10.0))
	_check(aligned.size() == 1, "03 aligned leaf fallout creates one path")
	if aligned.size() == 1:
		_check(_close(float(aligned[0]["rectangle_area_m2"]), 0.30),
				"03 intersection area is geometric, not a fraction formula")
	_free(building)


func _test_04_invalid_contracts_fail_closed() -> void:
	var building: BuildingModel = _building()
	var opening = building.get_openings()[0]
	var outside: Dictionary = _panel()
	outside["host_x_m"] = 0.80
	_declare(opening, outside, _spatial())
	var invalid: Dictionary = _system().build_snapshot(building, {}, DT_S, 10.0)
	_check(not bool(invalid["valid"]), "04 a panel outside its host is rejected")
	_check(Array(invalid["openings"]).is_empty(), "04 invalid placement reaches no solver element")
	var direct: Dictionary = Adapter.build_opening_elements(
		opening, BuildingModel.OUTSIDE_ID, 0.0, "0", "1", 10.0
	)
	_check(not bool(direct["valid"]), "04 the adapter itself rejects invalid placement")
	var first: Dictionary = _panel("a", 0.0)
	var second: Dictionary = _panel("b", 0.2)
	opening.glazing_panels = [first, second]
	opening.glazing_spatial = [_spatial("a"), _spatial("b")]
	direct = Adapter.build_opening_elements(
		opening, BuildingModel.OUTSIDE_ID, 0.0, "0", "1", 10.0
	)
	_check(not bool(direct["valid"]), "04 overlapping panels are rejected")
	opening.glazing_panels = [_panel()]
	opening.glazing_spatial = [{
		"panel_id": "pane",
		"snapshots": [{"time_s": 5.0, "leaves": _regions_for_half(1)}],
	}]
	direct = Adapter.build_opening_elements(
		opening, BuildingModel.OUTSIDE_ID, 0.0, "0", "1", 10.0
	)
	_check(not bool(direct["valid"]), "04 spatial history must start at zero")
	_free(building)


func _test_05_operational_opening_is_exclusive() -> void:
	var building: BuildingModel = _building(false, 1.0)
	var opening = building.get_openings()[0]
	_declare(opening)
	var snapshot: Dictionary = _system().build_snapshot(building, {}, DT_S, 10.0)
	_check(bool(snapshot["valid"]), "05 valid glass remains valid while operationally open")
	_check(_glazing(snapshot).is_empty(), "05 operational opening excludes glass elements")
	_check(Array(snapshot["openings"]).size() == 1
			and String(snapshot["openings"][0]["opening_id"]) == "op_0",
			"05 only the full operational opening reaches the solver")
	_check(_close(float(opening.open_fraction), 1.0),
			"05 D3 does not mutate the operational opening state")
	_free(building)


func _test_06_coexists_with_frame_leakage() -> void:
	var building: BuildingModel = _building(false, 0.0, "door")
	var opening = building.get_openings()[0]
	opening.leakage_class = "interior_tight"
	_declare(opening)
	var system = _system()
	system.closed_door_leakage_enabled = true
	var snapshot: Dictionary = system.build_snapshot(building, {}, DT_S, 10.0)
	_check(_glazing(snapshot).size() == 1, "06 glass path exists beside the frame")
	var crack_count: int = 0
	for element in snapshot["openings"]:
		if String(element.get("flow_model", "")) == "ela_crack":
			crack_count += 1
	_check(crack_count == 1, "06 cold frame leakage remains a separate element")
	_free(building)


func _test_07_atomic_transport_and_species() -> void:
	var building: BuildingModel = _building()
	_declare(building.get_openings()[0])
	var source = building.get_room(0)
	var receiver = building.get_room(1)
	# Fuerza una fuente con mayor presion total; el fixture base tiene menos
	# masa en R0 y su gradiente neto apunta en sentido contrario.
	_seed(source, 12.0, 493.15, 60.0, T_REF_K)
	source.smoke_kg = 0.20
	source.o2_upper = 0.16
	source.o2_lower = 0.18
	var mass_before: float = _total_mass(building)
	var energy_before: float = _total_energy(building)
	var smoke_before: float = float(receiver.smoke_kg)
	var system = _system()
	var result: Dictionary = system.step(building, DT_S, {}, 10.0)
	_check(bool(result.get("applied", false)), "07 D3 transport applies (%s)"
			% result.get("failure_reason", "?"))
	_check(int(system.commit_count) == 1, "07 atomic applier commits exactly once")
	_check(_close(_total_mass(building), mass_before, 1.0e-9),
			"07 interior D3 conserves total gas mass")
	_check(_close(_total_energy(building), energy_before, 1.0e-9),
			"07 interior D3 conserves total energy")
	_check(float(receiver.smoke_kg) > smoke_before, "07 D3 transports smoke with gas")
	_free(building)


func _test_08_exterior_wind_at_rectangle_height() -> void:
	var building: BuildingModel = _building(true, 0.0, "window", 6.0)
	_declare(building.get_openings()[0])
	building.wind_speed_m_s = 10.0
	building.wind_direction_deg = 90.0
	building.wind_height_profile_enabled = true
	var system = _system()
	system.wind_effect_enabled = true
	var elements: Array = _glazing(system.build_snapshot(building, {}, DT_S, 10.0))
	_check(elements.size() == 1, "08 exterior glass creates one wind-aware path")
	if elements.size() == 1:
		var element: Dictionary = elements[0]
		var center_z_m: float = float(building.building_base_z_m) \
				+ 0.5 * (float(element["bottom_z_m"]) + float(element["top_z_m"]))
		var speed: float = building.wind_speed_at_height_m_s(center_z_m)
		var expected: float = WindModel.wind_dp_pa("right", 90.0, speed)
		_check(_close(float(element["wind_dp_pa"]), expected, 1.0e-12),
				"08 wind is evaluated once at the rectangle center")
	_free(building)


func _test_09_nonfinite_time_fails_closed() -> void:
	var building: BuildingModel = _building()
	_declare(building.get_openings()[0])
	var snapshot: Dictionary = _system().build_snapshot(building, {}, DT_S, NAN)
	_check(not bool(snapshot["valid"]), "09 non-finite D3 time is rejected")
	_check(Array(snapshot["openings"]).is_empty(), "09 invalid time reaches no solver element")
	_free(building)


func _test_10_engine_wires_d3_at_simulation_time() -> void:
	var building: BuildingModel = _building()
	var panel: Dictionary = _panel()
	panel["leaves"][0]["events"] = [
		{"time_s": 0.0, "state": "CRACKED", "fallout_fraction": 0.0},
		{"time_s": DT_S, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.5},
	]
	var spatial: Dictionary = {
		"panel_id": "pane",
		"snapshots": [
			{"time_s": 0.0, "leaves": _empty_leaves(1)},
			{"time_s": DT_S, "leaves": _regions_for_half(1)},
		],
	}
	_declare(building.get_openings()[0], panel, spatial)
	var engine: SimulationEngine = SimulationEngineScript.new()
	engine.building = building
	engine.auto_ignite_on_ready = false
	engine.auto_finish_on_extinction = false
	engine.enable_logging = false
	engine.enable_csv_log = false
	engine.pressure_network_solver_enabled = true
	engine.glazing_fallout_enabled = true
	engine.suppress_exit_graphs()
	root.add_child(building)
	root.add_child(engine)
	engine.reset_simulation(0, false)
	_seed(building.get_room(0), 12.0, 493.15, 40.0, 298.15)
	_seed(building.get_room(1), 0.0, T_REF_K, 72.0, T_REF_K)
	engine.step(DT_S)
	_check(_close(float(engine.sim_time_s), DT_S, 1.0e-12),
			"10 engine advances the prescribed glazing clock")
	_check(bool(engine.pressure_network_transport_system.glazing_fallout_enabled),
			"10 engine wires D3 into the transport system")
	_check(int(engine.pressure_network_transport_system.commit_count) == 1,
			"10 engine commits D3 transport exactly once")
	_check(bool(engine.pressure_network_last_result.get("applied", false)),
			"10 engine applies D3 through the authoritative network")
	if bool(engine.pressure_network_last_result.get("applied", false)):
		_check(_glazing(engine.pressure_network_last_result["solution"]).size() == 1,
				"10 the engine evaluates D3 at authoritative sim_time")
	root.remove_child(engine)
	root.remove_child(building)
	engine.free()
	building.free()
