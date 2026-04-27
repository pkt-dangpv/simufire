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
		"room_rect_m": runtime_rects,
		"rooms_data": rooms_data,
		"openings_data": openings_data
	}


static func to_runtime_json_data(editor_data: Dictionary) -> Dictionary:
	var data: Dictionary = normalize_editor_data(editor_data)
	return {
		"outside_temp_c": float(data.get("outside_temp_c", 20.0)),
		"outside_o2": float(data.get("outside_o2", 0.209)),
		"stop_time_s": float(data.get("stop_time_s", 0.0)),
		"room_rect_m": Dictionary(data.get("room_rect_m", {})).duplicate(true),
		"rooms_data": Array(data.get("rooms_data", [])).duplicate(true),
		"openings_data": Array(data.get("openings_data", [])).duplicate(true)
	}


static func normalize_editor_data(raw_data: Dictionary) -> Dictionary:
	var data: Dictionary = raw_data.duplicate(true)
	data["version"] = int(data.get("version", DEFAULT_VERSION))
	data["outside_temp_c"] = float(data.get("outside_temp_c", 20.0))
	data["outside_o2"] = float(data.get("outside_o2", 0.209))
	data["stop_time_s"] = float(data.get("stop_time_s", 0.0))

	var rects: Dictionary = {}
	var raw_rects: Dictionary = data.get("room_rect_m", {})
	for key in raw_rects.keys():
		rects[str(key)] = rect_to_data(rect2_from_data(raw_rects[key]))
	data["room_rect_m"] = rects

	var rooms: Array = []
	for raw_room in data.get("rooms_data", []):
		if typeof(raw_room) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = Dictionary(raw_room).duplicate(true)
		room["id"] = int(room.get("id", rooms.size()))
		room["name"] = String(room.get("name", "Room %d" % int(room["id"])))
		room["kind"] = String(room.get("kind", "generic"))
		room["height_m"] = float(room.get("height_m", 2.7))
		room["fuel_energy_MJ"] = float(room.get("fuel_energy_MJ", 0.0))
		room["max_hrr_kw"] = float(room.get("max_hrr_kw", 0.0))
		var objects: Array = []
		for raw_obj in room.get("fuel_objects", []):
			if typeof(raw_obj) == TYPE_DICTIONARY:
				objects.append(normalize_fuel_object(Dictionary(raw_obj), int(room["id"])))
		room["fuel_objects"] = objects
		rooms.append(room)
	data["rooms_data"] = rooms

	var openings: Array = []
	for raw_opening in data.get("openings_data", []):
		if typeof(raw_opening) == TYPE_DICTIONARY:
			openings.append(normalize_opening(Dictionary(raw_opening)))
	data["openings_data"] = openings
	return data


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
	opening["type"] = String(opening.get("type", "door"))
	opening["wall"] = String(opening.get("wall", "")).to_lower()
	opening["offset_m"] = float(opening.get("offset_m", 0.5))
	opening["width_m"] = float(opening.get("width_m", 0.9))
	opening["height_m"] = float(opening.get("height_m", 2.0))
	opening["sill_m"] = float(opening.get("sill_m", 0.0))
	opening["open_fraction"] = clampf(float(opening.get("open_fraction", 1.0)), 0.0, 1.0)
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
