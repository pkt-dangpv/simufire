extends RefCounted
class_name ScenarioSerializer

const DEFAULT_VERSION: int = 1


static func save_scenario(path: String, scenario_data: Dictionary) -> bool:
	var normalized: Dictionary = normalize_editor_data(scenario_data)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ScenarioSerializer: no se pudo escribir %s" % path)
		return false

	file.store_string(JSON.stringify(normalized, "\t"))
	file.close()
	return true


static func save_runtime_template(path: String, editor_data: Dictionary) -> bool:
	var runtime_json: Dictionary = to_runtime_json_data(editor_data)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ScenarioSerializer: no se pudo escribir %s" % path)
		return false

	file.store_string(JSON.stringify(runtime_json, "\t"))
	file.close()
	return true


static func load_scenario(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ScenarioSerializer: no se pudo leer %s" % path)
		return {}

	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ScenarioSerializer: JSON invalido en %s" % path)
		return {}

	return normalize_editor_data(parsed)


static func to_runtime_template(editor_data: Dictionary) -> Dictionary:
	var data: Dictionary = normalize_editor_data(editor_data)
	var runtime_rects: Dictionary[int, Rect2] = {}
	var raw_rects: Dictionary = data.get("room_rect_m", {})
	for key in raw_rects.keys():
		runtime_rects[int(key)] = rect2_from_data(raw_rects[key])

	var rooms_data: Array = []
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) != TYPE_DICTIONARY:
			continue

		var room: Dictionary = Dictionary(raw_room).duplicate(true)
		var room_id: int = int(room.get("id", -1))
		var fuel_objects: Array = []
		for raw_obj in room.get("fuel_objects", []):
			if typeof(raw_obj) != TYPE_DICTIONARY:
				continue
			var obj: Dictionary = Dictionary(raw_obj).duplicate(true)
			obj["room_id"] = int(obj.get("room_id", room_id))
			obj["position_m"] = vector2_from_data(obj.get("position_m", Vector2.ZERO))
			obj["size_m"] = vector2_from_data(obj.get("size_m", Vector2.ONE))
			fuel_objects.append(obj)
		room["fuel_objects"] = fuel_objects
		rooms_data.append(room)

	var openings_data: Array = []
	for raw_opening in data.get("openings_data", []):
		if typeof(raw_opening) == TYPE_DICTIONARY:
			openings_data.append(Dictionary(raw_opening).duplicate(true))

	return {
		"outside_temp_c": float(data.get("outside_temp_c", 20.0)),
		"outside_o2": float(data.get("outside_o2", 0.209)),
		"building_type": String(data.get("building_type", "single_family")),
		"apartment_floor_number": int(data.get("apartment_floor_number", 1)),
		"floors": Array(data.get("floors", [])).duplicate(true),
		"player_start": Dictionary(data.get("player_start", {})).duplicate(true),
		"exterior_walls": Array(data.get("exterior_walls", [])).duplicate(true),
		"room_rect_m": runtime_rects,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_mode": String(data.get("hvac_mode", "none")),
		"hvac_data": Dictionary(data.get("hvac_data", {})).duplicate(true),
		"detectors": Array(data.get("detectors", [])).duplicate(true),
		"victims": Array(data.get("victims", [])).duplicate(true)
	}


static func to_runtime_json_data(editor_data: Dictionary) -> Dictionary:
	var data: Dictionary = normalize_editor_data(editor_data)
	return {
		"outside_temp_c": float(data.get("outside_temp_c", 20.0)),
		"outside_o2": float(data.get("outside_o2", 0.209)),
		"building_type": String(data.get("building_type", "single_family")),
		"apartment_floor_number": int(data.get("apartment_floor_number", 1)),
		"stop_time_s": float(data.get("stop_time_s", 0.0)),
		"floors": Array(data.get("floors", [])).duplicate(true),
		"player_start": Dictionary(data.get("player_start", {})).duplicate(true),
		"exterior_walls": Array(data.get("exterior_walls", [])).duplicate(true),
		"room_rect_m": Dictionary(data.get("room_rect_m", {})).duplicate(true),
		"rooms_data": Array(data.get("rooms_data", [])).duplicate(true),
		"openings_data": Array(data.get("openings_data", [])).duplicate(true),
		"hvac_mode": String(data.get("hvac_mode", "none")),
		"hvac_data": Dictionary(data.get("hvac_data", {})).duplicate(true),
		"detectors": Array(data.get("detectors", [])).duplicate(true),
		"victims": Array(data.get("victims", [])).duplicate(true)
	}


static func normalize_editor_data(raw_data: Dictionary) -> Dictionary:
	var data: Dictionary = raw_data.duplicate(true)
	data["version"] = int(data.get("version", DEFAULT_VERSION))
	data["outside_temp_c"] = float(data.get("outside_temp_c", 20.0))
	data["outside_o2"] = float(data.get("outside_o2", 0.209))
	var building_type: String = String(data.get("building_type", "single_family")).to_lower()
	if building_type != "apartment":
		building_type = "single_family"
	data["building_type"] = building_type
	data["apartment_floor_number"] = int(data.get("apartment_floor_number", 1))
	data["stop_time_s"] = float(data.get("stop_time_s", 0.0))
	var hvac_mode: String = String(data.get("hvac_mode", "none")).to_lower()
	if hvac_mode != "off" and hvac_mode != "on":
		hvac_mode = "none"
	data["hvac_mode"] = hvac_mode
	var hvac_data: Dictionary = {}
	if typeof(data.get("hvac_data", {})) == TYPE_DICTIONARY:
		hvac_data = Dictionary(data.get("hvac_data", {})).duplicate(true)
	hvac_data["exists"] = hvac_mode != "none"
	hvac_data["on"] = hvac_mode == "on"
	hvac_data["mode"] = hvac_mode
	data["hvac_data"] = hvac_data

	var rects: Dictionary = {}
	var raw_rects: Dictionary = data.get("room_rect_m", {})
	for key in raw_rects.keys():
		rects[str(key)] = rect_to_data(rect2_from_data(raw_rects[key]))
	data["room_rect_m"] = rects

	var room_floor_levels: Array = []
	var rooms: Array = []
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = Dictionary(raw_room).duplicate(true)
		room["id"] = int(room.get("id", rooms.size()))
		room["name"] = String(room.get("name", "Room %d" % int(room["id"])))
		room["kind"] = String(room.get("kind", "generic"))
		room["rotation_deg"] = float(room.get("rotation_deg", 0.0))
		room["stair_run_direction_m"] = vector_to_data(vector2_from_data(room.get("stair_run_direction_m", Vector2(0.0, 1.0))))
		room["stair_has_walls"] = bool(room.get("stair_has_walls", false))
		room["stair_has_railings"] = bool(room.get("stair_has_railings", true))
		room["stair_turn_degrees"] = float(room.get("stair_turn_degrees", 0.0))
		room["stair_flight_count"] = maxi(1, int(room.get("stair_flight_count", 1)))
		room["height_m"] = float(room.get("height_m", 2.7))
		room["floor_level_z_m"] = float(room.get("floor_level_z_m", 0.0))
		room_floor_levels.append(room["floor_level_z_m"])
		room["fuel_energy_MJ"] = float(room.get("fuel_energy_MJ", 0.0))
		room["max_hrr_kw"] = float(room.get("max_hrr_kw", 0.0))
		var objects: Array = []
		for raw_obj in room.get("fuel_objects", []):
			if typeof(raw_obj) == TYPE_DICTIONARY:
				objects.append(normalize_fuel_object(Dictionary(raw_obj), int(room["id"])))
		room["fuel_objects"] = objects
		rooms.append(room)
	data["rooms_data"] = rooms
	data["floors"] = normalize_floors(data.get("floors", []), room_floor_levels)

	var openings: Array = []
	for raw_opening in data.get("openings_data", []):
		if typeof(raw_opening) == TYPE_DICTIONARY:
			openings.append(normalize_opening(Dictionary(raw_opening)))
	data["openings_data"] = openings

	var exterior_walls: Array = []
	for raw_wall in data.get("exterior_walls", []):
		if typeof(raw_wall) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = Dictionary(raw_wall).duplicate(true)
		wall["a"] = vector_to_data(vector2_from_data(wall.get("a", Vector2.ZERO)))
		wall["b"] = vector_to_data(vector2_from_data(wall.get("b", Vector2.ZERO)))
		wall["thickness_m"] = maxf(0.05, float(wall.get("thickness_m", 0.16)))
		exterior_walls.append(wall)
	data["exterior_walls"] = exterior_walls

	var detectors: Array = []
	for raw_det in data.get("detectors", []):
		if typeof(raw_det) == TYPE_DICTIONARY:
			var det: Dictionary = Dictionary(raw_det).duplicate(true)
			det["id"] = String(det.get("id", ""))
			det["room_id"] = int(det.get("room_id", -1))
			det["type"] = String(det.get("type", "smoke"))
			det["threshold"] = float(det.get("threshold", 0.025))
			det["x_m"] = float(det.get("x_m", 0.0))
			det["y_m"] = float(det.get("y_m", 0.0))
			detectors.append(det)
	data["detectors"] = detectors

	var victims: Array = []
	for raw_vic in data.get("victims", []):
		if typeof(raw_vic) == TYPE_DICTIONARY:
			var vic: Dictionary = Dictionary(raw_vic).duplicate(true)
			vic["id"] = String(vic.get("id", ""))
			vic["room_id"] = int(vic.get("room_id", -1))
			vic["name"] = String(vic.get("name", ""))
			vic["x_m"] = float(vic.get("x_m", 0.0))
			vic["y_m"] = float(vic.get("y_m", 0.0))
			vic["height_m"] = float(vic.get("height_m", 0.9))
			victims.append(vic)
	data["victims"] = victims

	var player_start: Dictionary = {}
	if typeof(data.get("player_start", {})) == TYPE_DICTIONARY:
		var raw_start: Dictionary = Dictionary(data.get("player_start", {})).duplicate(true)
		if raw_start.has("room_id"):
			player_start["room_id"] = int(raw_start.get("room_id", -1))
			player_start["position_m"] = vector_to_data(vector2_from_data(raw_start.get("position_m", Vector2.ZERO)))
			player_start["floor_level_z_m"] = float(raw_start.get("floor_level_z_m", 0.0))
			player_start["yaw_deg"] = float(raw_start.get("yaw_deg", 0.0))
	data["player_start"] = player_start

	return data


static func normalize_floors(raw_floors: Variant, room_levels: Array = []) -> Array:
	var floors: Array = []
	if typeof(raw_floors) == TYPE_ARRAY:
		var raw_array: Array = raw_floors
		for i in range(raw_array.size()):
			if typeof(raw_array[i]) != TYPE_DICTIONARY:
				continue
			var raw: Dictionary = raw_array[i]
			var level_m: float = float(raw.get("level_m", 0.0 if floors.is_empty() else floors.size() * 2.9))
			if _floor_level_exists(floors, level_m):
				continue
			var fallback_name: String = "PB" if floors.is_empty() else "P%d" % floors.size()
			floors.append({
				"name": String(raw.get("name", fallback_name)),
				"level_m": level_m
			})
	for raw_level in room_levels:
		var level_m: float = float(raw_level)
		if not _floor_level_exists(floors, level_m):
			floors.append({
				"name": "PB" if floors.is_empty() else "P%d" % floors.size(),
				"level_m": level_m
			})
	if floors.is_empty():
		floors.append({"name": "PB", "level_m": 0.0})
	floors.sort_custom(func(a, b): return float(a.get("level_m", 0.0)) < float(b.get("level_m", 0.0)))
	for i in range(floors.size()):
		var floor: Dictionary = floors[i]
		if String(floor.get("name", "")).strip_edges() == "":
			floor["name"] = "PB" if i == 0 else "P%d" % i
		floors[i] = floor
	return floors


static func _floor_level_exists(floors: Array, level_m: float) -> bool:
	for raw_floor in floors:
		if typeof(raw_floor) == TYPE_DICTIONARY and absf(float(raw_floor.get("level_m", 0.0)) - level_m) < 0.05:
			return true
	return false


static func normalize_fuel_object(raw_obj: Dictionary, fallback_room_id: int) -> Dictionary:
	var obj: Dictionary = raw_obj.duplicate(true)
	obj["id"] = String(obj.get("id", "obj"))
	obj["name"] = String(obj.get("name", obj["id"]))
	obj["kind"] = String(obj.get("kind", "generic"))
	obj["room_id"] = int(obj.get("room_id", fallback_room_id))
	obj["position_m"] = vector_to_data(vector2_from_data(obj.get("position_m", Vector2.ZERO)))
	obj["size_m"] = vector_to_data(vector2_from_data(obj.get("size_m", Vector2.ONE)))
	obj["rotation_deg"] = float(obj.get("rotation_deg", 0.0))
	obj["footprint_m2"] = float(obj.get("footprint_m2", 1.0))
	obj["exposed_area_m2"] = float(obj.get("exposed_area_m2", obj["footprint_m2"]))
	obj["elevation_m"] = float(obj.get("elevation_m", 0.0))
	obj["fuel_energy_MJ"] = float(obj.get("fuel_energy_MJ", 100.0))
	obj["remaining_fuel_MJ"] = float(obj.get("remaining_fuel_MJ", obj["fuel_energy_MJ"]))
	obj["max_hrr_kw"] = float(obj.get("max_hrr_kw", 300.0))
	obj["ignition_temp_c"] = float(obj.get("ignition_temp_c", 330.0))
	obj["ignition_flux_kw_m2"] = float(obj.get("ignition_flux_kw_m2", 18.0))
	obj["smoke_yield_kg_per_MJ"] = float(obj.get("smoke_yield_kg_per_MJ", 0.00375))
	obj["co_yield_kg_per_MJ"] = float(obj.get("co_yield_kg_per_MJ", 0.00025))
	obj["o2_consumption_kg_per_MJ"] = float(obj.get("o2_consumption_kg_per_MJ", 0.076))
	obj["is_primary_ignition_source"] = bool(obj.get("is_primary_ignition_source", false))
	return obj


static func normalize_opening(raw_opening: Dictionary) -> Dictionary:
	var opening: Dictionary = raw_opening.duplicate(true)
	opening["a"] = int(opening.get("a", 0))
	opening["b"] = int(opening.get("b", -1))
	var type_name: String = String(opening.get("type", "door")).strip_edges().to_lower()
	if type_name != "door" and type_name != "window" and type_name != "hole":
		type_name = "door"
	opening["type"] = type_name
	opening["wall"] = String(opening.get("wall", "")).to_lower()
	opening["offset_m"] = float(opening.get("offset_m", 0.5))
	opening["offset_is_fraction"] = bool(opening.get("offset_is_fraction", true))
	opening["width_m"] = float(opening.get("width_m", 0.9))
	opening["height_m"] = float(opening.get("height_m", 2.0))
	opening["sill_m"] = float(opening.get("sill_m", 0.0))
	opening["open_fraction"] = clampf(float(opening.get("open_fraction", 1.0)), 0.0, 1.0)
	var swing_direction: String = String(opening.get("swing_direction", "in")).strip_edges().to_lower()
	opening["swing_direction"] = "out" if swing_direction == "out" else "in"
	var hinge_side: String = String(opening.get("hinge_side", "left")).strip_edges().to_lower()
	opening["hinge_side"] = "right" if hinge_side == "right" else "left"
	if type_name == "hole":
		opening["sill_m"] = 0.0
		opening["open_fraction"] = 1.0
	if opening.has("is_vertical"):
		opening["is_vertical"] = bool(opening["is_vertical"])
	return opening


static func rect2_from_data(value: Variant) -> Rect2:
	if typeof(value) == TYPE_RECT2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Rect2(
			float(data.get("x", 0.0)),
			float(data.get("y", 0.0)),
			float(data.get("w", data.get("width", 0.0))),
			float(data.get("h", data.get("height", 0.0)))
		)
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 4:
			return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


static func vector2_from_data(value: Variant) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


static func rect_to_data(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


static func vector_to_data(vector: Vector2) -> Dictionary:
	return {"x": vector.x, "y": vector.y}
