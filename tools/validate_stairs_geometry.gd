extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FPPresetScript := preload("res://view/fp/FPPreset.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")
const EditorDraw2DScript := preload("res://editor/EditorDraw2D.gd")
const EditorLoadErrorDialogScript := preload("res://editor/EditorLoadErrorDialog.gd")
const ScenarioEditorScript := preload("res://editor/ScenarioEditor.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var straight := await _build_case("straight", Rect2(0.0, 0.0, 1.40, 4.60), Vector2.DOWN, 0.0)
	_validate_model("straight", straight)
	_validate_editor_vertical_opening("straight", straight)
	_validate_first_person("straight", straight)
	_validate_visualizer("straight", straight)
	await _validate_head_clearance("straight", straight)
	_cleanup_case(straight)

	var switchback := await _build_case("switchback", Rect2(0.0, 0.0, 2.40, 5.40), Vector2.DOWN, 180.0)
	_validate_model("switchback", switchback)
	_validate_editor_vertical_opening("switchback", switchback)
	_validate_first_person("switchback", switchback)
	_validate_visualizer("switchback", switchback)
	await _validate_head_clearance("switchback", switchback)
	_cleanup_case(switchback)

	if _failures.is_empty():
		print("STAIR GEOMETRY VALIDATION PASS")
		get_tree().quit(0)
		return

	push_error("STAIR GEOMETRY VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _build_case(case_name: String, rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Dictionary:
	var template := _make_template(rect, stair_dir, turn_degrees)
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)

	var host := Node3D.new()
	host.name = "ValidateStairs_%s" % case_name
	get_tree().root.add_child(host)

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "FirstPersonController_%s" % case_name
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "Visualizer3D_%s" % case_name
	visualizer.building = building
	visualizer.show_room_labels = false
	visualizer.show_smoke_volume = false
	visualizer.show_hrr_columns = false
	visualizer.show_fuel_objects_3d = false
	host.add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	await get_tree().process_frame

	return {
		"name": case_name,
		"template": template,
		"building": building,
		"host": host,
		"fp": fp,
		"visualizer": visualizer,
		"rect": rect,
		"stair_dir": stair_dir,
		"turn_degrees": turn_degrees
	}


func _cleanup_case(ctx: Dictionary) -> void:
	var host := ctx.get("host") as Node
	if host != null:
		host.free()
	var building := ctx.get("building") as Node
	if building != null:
		building.free()


func _make_template(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Dictionary:
	var flight_count := 2 if turn_degrees >= 179.0 else 1
	var opening_width := _stair_ramp_width_m(rect, stair_dir)
	var opening_depth := maxf(0.80, _stair_long_span_m(rect, stair_dir) - _stair_landing_depth_m(rect, stair_dir) - 0.22)
	if turn_degrees >= 179.0:
		opening_width = _stair_cross_span_m(rect, stair_dir)
		opening_depth = _stair_long_span_m(rect, stair_dir)

	return {
		"version": 1,
		"building_type": "single_family",
		"outside_temp_c": 20.0,
		"outside_o2": 0.209,
		"stop_time_s": 0.0,
		"hvac_mode": "none",
		"hvac_data": {"exists": false, "on": false, "mode": "none"},
		"room_rect_m": {
			"0": _rect_to_data(rect),
			"1": _rect_to_data(rect)
		},
		"rooms_data": [
			_make_stair_room(0, "Escalera PB", rect, 0.0, 3.0, stair_dir, turn_degrees, flight_count),
			_make_stair_room(1, "Escalera P1", rect, 3.0, 2.55, stair_dir, turn_degrees, flight_count)
		],
		"openings_data": [
			{
				"a": 0,
				"b": 1,
				"type": "hole",
				"wall": "vertical",
				"offset_m": 0.0,
				"width_m": opening_width,
				"height_m": opening_depth,
				"sill_m": 0.0,
				"open_fraction": 1.0,
				"is_vertical": true
			}
		],
		"player_start": {
			"room_id": 0,
			"position_m": {"x": rect.get_center().x, "y": rect.position.y + 0.35},
			"floor_level_z_m": 0.0,
			"yaw_deg": 0.0
		},
		"detectors": [],
		"victims": [],
		"exterior_walls": []
	}


func _make_stair_room(id: int, room_name: String, rect: Rect2, floor_level_m: float, height_m: float, stair_dir: Vector2, turn_degrees: float, flight_count: int) -> Dictionary:
	return {
		"id": id,
		"name": room_name,
		"kind": "escalera",
		"height_m": height_m,
		"floor_level_z_m": floor_level_m,
		"rotation_deg": 0.0,
		"stair_run_direction_m": {"x": stair_dir.x, "y": stair_dir.y},
		"stair_has_walls": false,
		"stair_has_railings": true,
		"stair_turn_degrees": turn_degrees,
		"stair_flight_count": flight_count,
		"fuel_energy_MJ": 0.0,
		"max_hrr_kw": 0.0,
		"fuel_objects": [],
		"width_m": rect.size.x,
		"length_m": rect.size.y
	}


func _rect_to_data(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y
	}


func _validate_model(case_name: String, ctx: Dictionary) -> void:
	var building: BuildingModel = ctx["building"] as BuildingModel
	_expect(building.get_opening_count() == 1, case_name + ": expected one vertical opening")
	var op: OpeningModel = building.get_opening_at(0) as OpeningModel
	_expect(op != null and op.is_vertical, case_name + ": opening must be marked is_vertical")
	var lower_room: RoomModel = building.get_room(0)
	var upper_room: RoomModel = building.get_room(1)
	_expect(lower_room != null and upper_room != null, case_name + ": expected both stair rooms")
	if lower_room != null:
		_expect(lower_room.stair_has_railings, case_name + ": lower stair room should keep railings enabled")
		_expect(absf(lower_room.stair_turn_degrees - float(ctx["turn_degrees"])) < 0.01, case_name + ": lower stair turn angle mismatch")
	if upper_room != null:
		_expect(absf(upper_room.floor_level_z_m - 3.0) < 0.01, case_name + ": upper stair room should be on P1")


func _validate_editor_vertical_opening(case_name: String, ctx: Dictionary) -> void:
	var editor: ScenarioEditor = ScenarioEditorScript.new()
	editor.editor_data = Dictionary(ctx["template"]).duplicate(true)
	var opening: Dictionary = editor.editor_data["openings_data"][0]
	var hole: Rect2 = editor.call("_vertical_opening_rect", opening)
	var rect: Rect2 = ctx["rect"]
	var turn_degrees := float(ctx["turn_degrees"])
	_expect(hole.size.x > 0.0 and hole.size.y > 0.0, case_name + ": editor vertical opening rect must be non-empty")
	_expect(_rect_contains_rect(rect, hole, 0.02), case_name + ": editor vertical opening must stay inside stair room")
	if turn_degrees >= 179.0:
		_expect(hole.size.y >= rect.size.y - 0.02, case_name + ": switchback opening should cover the full run band")
		_expect(hole.size.x >= minf(rect.size.x, 2.0) - 0.02, case_name + ": switchback opening should cover both flight lanes")
	else:
		_expect(hole.position.y <= rect.position.y + 0.24, case_name + ": straight opening should start near stair entry")
		_expect(hole.size.x < rect.size.x - 0.20, case_name + ": straight opening should be a centered ramp shaft, not the full room")
		_expect(hole.size.y < rect.size.y - 0.20, case_name + ": straight opening should leave upper landing depth")
	editor.free()


func _validate_first_person(case_name: String, ctx: Dictionary) -> void:
	var fp := ctx["fp"] as FirstPersonController
	var world := fp.get_node_or_null("FirstPersonWorld")
	_expect(world != null, case_name + ": FP world must exist")
	if world == null:
		return

	var turn_degrees := float(ctx["turn_degrees"])
	_expect(_find_nodes(world, "Floor_1").is_empty(), case_name + ": FP upper stair room must not keep a full floor slab")
	_expect(_find_nodes(world, "Ceiling_").is_empty(), case_name + ": FP stair rooms must not generate ceiling collision")

	if turn_degrees >= 179.0:
		_expect(_find_nodes(world, "StairSwitchbackLanding").size() >= 1, case_name + ": FP switchback landing missing")
		_expect(_find_nodes(world, "FlightAStep_").size() >= 8, case_name + ": FP switchback first flight steps missing")
		_expect(_find_nodes(world, "FlightBStep_").size() >= 8, case_name + ": FP switchback second flight steps missing")
		var fp_switchback_rails := _find_sloped_meshes(world, "Railing", 0.10)
		_expect(fp_switchback_rails.size() >= 2, case_name + ": FP switchback railings should be sloped on both flights")
	else:
		_expect(_find_nodes(world, "StairRamp").size() >= 2, case_name + ": FP straight ramp body/mesh missing")
		_expect(_find_nodes(world, "StairStep_").size() >= 12, case_name + ": FP straight stair steps missing")
		_expect(_find_nodes(world, "StairTopLanding_1").size() >= 1, case_name + ": FP straight upper landing slab missing")
		var fp_straight_rails := _find_sloped_meshes(world, "StairRailing", 0.10)
		_expect(fp_straight_rails.size() >= 1, case_name + ": FP straight railings should be sloped")


func _validate_visualizer(case_name: String, ctx: Dictionary) -> void:
	var visualizer := ctx["visualizer"] as Visualizer3D
	var rooms := visualizer.get_node_or_null("Rooms")
	_expect(rooms != null, case_name + ": 3D Rooms root must exist")
	if rooms == null:
		return

	var turn_degrees := float(ctx["turn_degrees"])
	if turn_degrees >= 179.0:
		_expect(_find_nodes(rooms, "SwitchbackLanding").size() >= 1, case_name + ": 3D switchback landing missing")
		_expect(_find_nodes(rooms, "FlightAStep_").size() >= 8, case_name + ": 3D switchback first flight missing")
		_expect(_find_nodes(rooms, "FlightBStep_").size() >= 8, case_name + ": 3D switchback second flight missing")
		var v3d_switchback_rails := _find_sloped_meshes(rooms, "Handrail", 0.10)
		_expect(v3d_switchback_rails.size() >= 2, case_name + ": 3D switchback handrails should be sloped on both flights")
		_expect(_find_nodes_exact(rooms, "Step_00").is_empty(), case_name + ": 3D switchback must not fall back to straight stair steps")
	else:
		_expect(_find_nodes(rooms, "Stairs_00").size() >= 1, case_name + ": 3D straight stair root missing")
		_expect(_find_nodes(rooms, "Step_").size() >= 14, case_name + ": 3D straight steps missing")
		_expect(_find_nodes(rooms, "StairTopLanding_1").size() >= 1, case_name + ": 3D straight upper landing visual missing")
		var v3d_straight_rails := _find_sloped_meshes(rooms, "Handrail", 0.10)
		_expect(v3d_straight_rails.size() >= 1, case_name + ": 3D straight handrails should be sloped")


func _validate_head_clearance(case_name: String, ctx: Dictionary) -> void:
	await get_tree().physics_frame
	var fp := ctx["fp"] as FirstPersonController
	var host := ctx["host"] as Node3D
	var rect: Rect2 = ctx["rect"]
	var stair_dir: Vector2 = Vector2(ctx["stair_dir"])
	var turn_degrees := float(ctx["turn_degrees"])
	var samples: Array[Vector3] = []
	if turn_degrees >= 179.0:
		samples = _switchback_head_samples(rect, stair_dir)
	else:
		samples = _straight_head_samples(rect, stair_dir)

	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	var state := host.get_world_3d().direct_space_state
	for i in range(samples.size()):
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = sphere
		params.transform = Transform3D(Basis(), _to_case_world(rect, samples[i]))
		params.exclude = [fp.get_rid()]
		var hits := state.intersect_shape(params, 8)
		_expect(hits.is_empty(), "%s: head-clearance sample %d has obstruction count=%d" % [case_name, i, hits.size()])


func _straight_head_samples(rect: Rect2, stair_dir: Vector2) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var run_m := maxf(0.8, _stair_long_span_m(rect, stair_dir) - 0.22 - _stair_landing_depth_m(rect, stair_dir))
	for t in [0.15, 0.35, 0.55, 0.75, 0.92]:
		var p2 := _stair_point_along_run(rect, stair_dir, 0.22 + run_m * float(t))
		var foot_y := 3.0 * float(t)
		result.append(Vector3(p2.x, foot_y + 1.62, p2.y))
	return result


func _switchback_head_samples(rect: Rect2, stair_dir: Vector2) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var normal := Vector2(-stair_dir.y, stair_dir.x)
	var landing_depth_m := clampf(_stair_long_span_m(rect, stair_dir) * 0.18, 0.70, 0.95)
	var run_m := maxf(0.72, _stair_long_span_m(rect, stair_dir) - 0.22 - landing_depth_m - 0.20)
	var gap_m := 0.18
	var flight_width_m := clampf((_stair_cross_span_m(rect, stair_dir) - gap_m) * 0.5, 0.72, 1.05)
	var lane_offset_m := flight_width_m * 0.5 + gap_m * 0.5
	var landing_distance_m := 0.22 + run_m
	var flight_a_start := _stair_point_along_run(rect, stair_dir, 0.22) - normal * lane_offset_m
	var flight_b_start := _stair_point_along_run(rect, stair_dir, landing_distance_m) + normal * lane_offset_m
	for t in [0.20, 0.50, 0.82]:
		var p_a := flight_a_start + stair_dir * (run_m * float(t))
		result.append(Vector3(p_a.x, 1.50 * float(t) + 1.62, p_a.y))
		var p_b := flight_b_start - stair_dir * (run_m * float(t))
		result.append(Vector3(p_b.x, 1.50 + 1.50 * float(t) + 1.62, p_b.y))
	return result


func _to_case_world(rect: Rect2, pos_m: Vector3) -> Vector3:
	var origin_offset := -(rect.position + rect.size * 0.5)
	return Vector3(pos_m.x + origin_offset.x, pos_m.y, pos_m.z + origin_offset.y)


func _find_nodes(root_node: Node, token: String) -> Array:
	var result: Array = []
	_collect_nodes(root_node, token, result)
	return result


func _find_nodes_exact(root_node: Node, node_name: String) -> Array:
	var result: Array = []
	_collect_nodes_exact(root_node, node_name, result)
	return result


func _collect_nodes(node: Node, token: String, result: Array) -> void:
	if node.name.contains(token):
		result.append(node)
	for child in node.get_children():
		_collect_nodes(child, token, result)


func _collect_nodes_exact(node: Node, node_name: String, result: Array) -> void:
	if node.name == node_name:
		result.append(node)
	for child in node.get_children():
		_collect_nodes_exact(child, node_name, result)


func _find_sloped_meshes(root_node: Node, token: String, min_abs_rotation_x: float) -> Array:
	var candidates := _find_nodes(root_node, token)
	var result: Array = []
	for node in candidates:
		var node3d := node as Node3D
		if node3d == null:
			continue
		if absf(node3d.rotation.x) >= min_abs_rotation_x:
			result.append(node3d)
	return result


func _rect_contains_rect(outer: Rect2, inner: Rect2, tolerance: float) -> bool:
	return inner.position.x >= outer.position.x - tolerance \
		and inner.position.y >= outer.position.y - tolerance \
		and inner.position.x + inner.size.x <= outer.position.x + outer.size.x + tolerance \
		and inner.position.y + inner.size.y <= outer.position.y + outer.size.y + tolerance


func _stair_long_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.x if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.y


func _stair_cross_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.y if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.x


func _stair_ramp_width_m(rect: Rect2, stair_dir: Vector2) -> float:
	var cross_span := _stair_cross_span_m(rect, stair_dir)
	return minf(maxf(0.82, cross_span * 0.50), maxf(0.82, cross_span - 0.96))


func _stair_landing_depth_m(rect: Rect2, stair_dir: Vector2) -> float:
	return clampf(_stair_long_span_m(rect, stair_dir) * 0.22, 0.72, 1.05)


func _stair_point_along_run(rect: Rect2, stair_dir: Vector2, distance_from_entry_m: float) -> Vector2:
	var center := rect.get_center()
	if absf(stair_dir.x) > absf(stair_dir.y):
		var entry_x := rect.position.x if stair_dir.x > 0.0 else rect.position.x + rect.size.x
		return Vector2(entry_x + stair_dir.x * distance_from_entry_m, center.y)
	var entry_y := rect.position.y if stair_dir.y > 0.0 else rect.position.y + rect.size.y
	return Vector2(center.x, entry_y + stair_dir.y * distance_from_entry_m)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
