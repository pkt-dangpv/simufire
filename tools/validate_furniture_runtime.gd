extends Node

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const BuildingTemplateScript := preload("res://sim/templates/BuildingTemplate.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const SimulationStateBuilderScript := preload("res://sim/core/SimulationStateBuilder.gd")
const Visualizer3DScript := preload("res://view/3d/Visualizer3D.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var editor_data: Dictionary = _make_moved_simple_house()
	var runtime_json: Dictionary = Serializer.to_runtime_json_data(editor_data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime_json))
	_expect(typeof(parsed) == TYPE_DICTIONARY, "runtime JSON did not round-trip")
	if typeof(parsed) != TYPE_DICTIONARY:
		_finish()
		return

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Dictionary(parsed))

	var moved_obj = _find_room_object(building, 0, "salon_sofa")
	_expect(moved_obj != null, "moved sofa was not loaded into BuildingModel")
	if moved_obj != null:
		_expect_close((moved_obj as FuelObjectModel).position_m.x, 2.40, 0.01, "BuildingModel lost moved object x")
		_expect_close((moved_obj as FuelObjectModel).position_m.y, 0.40, 0.01, "BuildingModel lost moved object y")
		_expect_close((moved_obj as FuelObjectModel).rotation_deg, 33.0, 0.01, "BuildingModel lost moved object rotation")
		_expect(bool((moved_obj as FuelObjectModel).visual_pose_locked), "BuildingModel lost visual_pose_locked")

	var state_builder = SimulationStateBuilderScript.new()
	var state: Dictionary = state_builder.build_state({
		"building": building,
		"sim_time_s": 0.0,
		"hvac": building.build_hvac_summary()
	})
	var room_state: Dictionary = Dictionary(state.get("0", {}))
	var state_obj: Dictionary = _find_snapshot_object(Array(room_state.get("fuel_objects", [])), "salon_sofa")
	_expect(not state_obj.is_empty(), "SimulationStateBuilder did not export moved sofa")
	if not state_obj.is_empty():
		_expect(bool(state_obj.get("visual_pose_locked", false)), "SimulationStateBuilder lost visual_pose_locked")
		_expect_close(_vec2_from_variant(state_obj.get("position_m", Vector2.ZERO)).x, 2.40, 0.01, "SimulationStateBuilder lost object x")

	var visualizer: Visualizer3D = Visualizer3DScript.new()
	visualizer.name = "FurnitureRuntimeVisualizer"
	visualizer.building = building
	_add_visualizer_children(visualizer)
	add_child(visualizer)
	await get_tree().process_frame
	visualizer.rebuild_from_building()
	visualizer.set_state({})
	await get_tree().process_frame

	var fuel_root := visualizer.get_node_or_null("Atmosphere/FuelObjects_00") as Node3D
	_expect(fuel_root != null, "Visualizer3D did not create room fuel root")
	var node := _find_fuel_node(fuel_root, "salon_sofa")
	_expect(node != null, "Visualizer3D did not render furniture with empty editor state")
	if node != null:
		_expect_close(float(node.get_meta("size_x_m", 0.0)), 0.90, 0.01, "Visualizer3D lost sofa width")
		_expect_close(float(node.rotation_degrees.y), 33.0, 0.01, "Visualizer3D lost sofa rotation")
		var origin_offset_m: Vector2 = _origin_offset_for_building(building)
		var expected_x: float = 2.40 + 0.90 * 0.5 + origin_offset_m.x
		var expected_z: float = 0.40 + 2.35 * 0.5 + origin_offset_m.y
		_expect_close(node.position.x, expected_x, 0.05, "Visualizer3D did not preserve moved sofa x")
		_expect_close(node.position.z, expected_z, 0.05, "Visualizer3D did not preserve moved sofa z")

	visualizer.set_active(true, false, false, true)
	visualizer.set_state({})
	await get_tree().process_frame
	if fuel_root != null:
		_expect(fuel_root.visible, "Furniture hidden in first-person overlay")

	remove_child(visualizer)
	visualizer.free()
	building.free()
	_finish()


func _make_moved_simple_house() -> Dictionary:
	var builder = BuildingTemplateScript.new()
	var data: Dictionary = Serializer.normalize_editor_data(builder.create_by_name("simple_house"))
	var rooms: Array = data.get("rooms_data", [])
	for i in range(rooms.size()):
		if typeof(rooms[i]) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = rooms[i]
		if int(room.get("id", -1)) != 0:
			continue
		var objects: Array = room.get("fuel_objects", [])
		for j in range(objects.size()):
			if typeof(objects[j]) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = objects[j]
			if String(obj.get("id", "")) != "salon_sofa":
				continue
			obj["position_m"] = {"x": 2.40, "y": 0.40}
			obj["size_m"] = {"x": 0.90, "y": 2.35}
			obj["rotation_deg"] = 33.0
			obj["visual_pose_locked"] = true
			objects[j] = obj
			room["fuel_objects"] = objects
			rooms[i] = room
			data["rooms_data"] = rooms
			return Serializer.normalize_editor_data(data)
	return data


func _add_visualizer_children(visualizer: Node3D) -> void:
	for node_name in ["Rooms", "Openings", "Atmosphere", "Labels"]:
		var container := Node3D.new()
		container.name = node_name
		visualizer.add_child(container)
	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	visualizer.add_child(camera_rig)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.0, 13.0)
	camera_rig.add_child(camera)


func _find_room_object(building: BuildingModel, room_id: int, object_id: String):
	var room: RoomModel = building.get_room(room_id)
	if room == null:
		return null
	for obj in room.fuel_objects:
		if obj != null and String(obj.id) == object_id:
			return obj
	return null


func _find_snapshot_object(objects: Array, object_id: String) -> Dictionary:
	for raw in objects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = raw
		if String(obj.get("id", "")) == object_id:
			return obj
	return {}


func _find_fuel_node(root: Node, object_id: String) -> Node3D:
	if root == null:
		return null
	for child in root.get_children():
		var node := child as Node3D
		if node != null and String(node.get_meta("object_id", "")) == object_id:
			return node
	return null


func _vec2_from_variant(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	return Vector2.ZERO


func _origin_offset_for_building(building: BuildingModel) -> Vector2:
	var rects: Dictionary = building.get_room_rects_m()
	var first: bool = true
	var bounds := Rect2()
	for value in rects.values():
		var rect := Rect2(value)
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	if first:
		return Vector2.ZERO
	return -(bounds.position + bounds.size * 0.5)


func _finish() -> void:
	if _failures.is_empty():
		print("FURNITURE RUNTIME VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("FURNITURE RUNTIME VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%.4f expected=%.4f)" % [message, actual, expected])
