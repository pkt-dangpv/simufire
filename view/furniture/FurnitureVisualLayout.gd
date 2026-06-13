extends RefCounted


static func normalize_spec(room_id: int, room_name: String, room_kind: String, room_size: Vector2, spec: Dictionary) -> Dictionary:
	var result: Dictionary = spec.duplicate(true)
	if bool(result.get("visual_pose_locked", false)):
		return result
	var tokens: String = _tokens(result.get("id", ""), result.get("name", ""), result.get("kind", ""))
	var room_tokens: String = ("%s %s" % [room_name, room_kind]).to_lower()

	if room_tokens.contains("pasillo") or room_tokens.contains("hall"):
		return _hallway_spec(room_size, result, tokens)
	if room_tokens.contains("bano") or room_tokens.contains("baño") or room_tokens.contains("bath"):
		return _bathroom_spec(room_size, result, tokens)
	if room_tokens.contains("cocina") or room_tokens.contains("kitchen"):
		return _kitchen_spec(room_size, result, tokens)
	if room_tokens.contains("salon") or room_tokens.contains("salón") or room_tokens.contains("living") or room_id == 0:
		return _living_room_spec(room_size, result, tokens)
	return result


static func _hallway_spec(room_size: Vector2, spec: Dictionary, tokens: String) -> Dictionary:
	var w: float = maxf(0.1, room_size.x)
	var d: float = maxf(0.1, room_size.y)
	if _has_any(tokens, ["alfombra", "rug", "textil", "runner"]):
		_set_pose(spec, Vector2(w * 0.5 - 0.24, 0.48), Vector2(0.48, maxf(0.80, d - 1.22)), 0.0, "rug")
		return spec
	if _has_any(tokens, ["consola", "mueble", "zapatero", "dresser", "storage"]):
		var side_x: float = 0.08 if not tokens.contains("zapatero") else maxf(0.08, w - 0.32)
		_set_pose(spec, Vector2(side_x, clampf(d - 1.20, 0.55, d - 0.92)), Vector2(0.24, 0.74), 0.0, "console")
		return spec
	if _has_any(tokens, ["caja", "box", "clutter"]):
		_set_pose(spec, Vector2(0.12, maxf(0.42, d - 0.58)), Vector2(0.28, 0.28), 0.0, "clutter")
		return spec
	spec["visual_hidden"] = true
	return spec


static func _bathroom_spec(room_size: Vector2, spec: Dictionary, tokens: String) -> Dictionary:
	var w: float = maxf(0.1, room_size.x)
	var d: float = maxf(0.1, room_size.y)
	if _has_any(tokens, ["toalla", "textil", "pano", "paño", "towel"]):
		_set_pose(spec, Vector2(maxf(0.18, w - 0.62), 0.24), Vector2(0.40, minf(0.82, d * 0.42)), 0.0, "textile_pile")
		return spec
	if _has_any(tokens, ["cubo", "plastic", "plastico", "plástico", "bin"]):
		_set_pose(spec, Vector2(0.22, maxf(0.18, d - 0.56)), Vector2(0.34, 0.34), 0.0, "plastic_bin")
		return spec
	if _has_any(tokens, ["lavabo", "mueble lavabo", "vanity", "sink", "resto"]):
		spec["visual_hidden"] = true
		return spec
	spec["visual_hidden"] = true
	return spec


static func _kitchen_spec(room_size: Vector2, spec: Dictionary, tokens: String) -> Dictionary:
	var w: float = maxf(0.1, room_size.x)
	var d: float = maxf(0.1, room_size.y)
	if _has_any(tokens, ["encimera", "muebles cocina", "counter", "kitchen_unit"]):
		_set_pose(spec, Vector2(0.24, 0.20), Vector2(minf(maxf(1.60, w - 1.45), 3.35), 0.62), 0.0, "kitchen_unit")
		return spec
	if _has_any(tokens, ["columna", "despensa", "wardrobe"]):
		_set_pose(spec, Vector2(clampf(w - 1.10, 0.80, w - 0.68), 0.20), Vector2(0.62, 0.62), 0.0, "wardrobe")
		return spec
	if _has_any(tokens, ["grasa", "aceite", "pool", "liquido", "líquido"]):
		_set_pose(spec, Vector2(minf(w - 0.80, 2.05), 0.32), Vector2(0.42, 0.42), 0.0, "pool")
		return spec
	if _has_any(tokens, ["mesa", "table"]):
		_set_pose(spec, Vector2(0.42, maxf(0.70, d - 0.98)), Vector2(1.05, 0.70), 0.0, "table")
		return spec
	if _has_any(tokens, ["pano", "paño", "textil", "toalla"]):
		_set_pose(spec, Vector2(0.62, maxf(0.78, d - 0.62)), Vector2(0.52, 0.30), 0.0, "textile_pile")
		return spec
	if _has_any(tokens, ["carro", "auxiliar", "resto", "clutter"]):
		_set_pose(spec, Vector2(clampf(w - 1.20, 1.80, w - 0.70), 1.05), Vector2(0.52, 0.48), 0.0, "clutter")
		return spec
	return spec


static func _living_room_spec(room_size: Vector2, spec: Dictionary, tokens: String) -> Dictionary:
	var w: float = maxf(0.1, room_size.x)
	var d: float = maxf(0.1, room_size.y)
	var room_area_m2: float = w * d
	var large_room_t: float = clampf((room_area_m2 - 20.0) / 24.0, 0.0, 1.0)
	if _has_any(tokens, ["sofa", "sofá", "couch"]):
		var sofa_w: float = minf(lerpf(2.35, 3.20, large_room_t), w - 1.10)
		var sofa_d: float = minf(lerpf(0.86, 1.02, large_room_t), d - 1.15)
		_set_pose(spec, Vector2(0.38, clampf(d - sofa_d - 0.42, 1.20, d - sofa_d - 0.16)), Vector2(sofa_w, sofa_d), 0.0, "sofa")
		return spec
	if _has_any(tokens, ["mesa centro", "coffee"]):
		var table_size := Vector2(lerpf(1.10, 1.55, large_room_t), lerpf(0.62, 0.82, large_room_t))
		_set_pose(spec, Vector2(clampf(w * 0.43, 1.35, w - table_size.x - 0.45), clampf(d * 0.48, 1.10, d - table_size.y - 0.58)), table_size, 0.0, "coffee_table")
		return spec
	if _has_any(tokens, ["mueble tv", "tv"]):
		_set_pose(spec, Vector2(0.35, 0.24), Vector2(minf(lerpf(1.55, 2.35, large_room_t), w - 0.90), 0.38), 0.0, "tv_stand")
		return spec
	if _has_any(tokens, ["libreria", "librería", "bookcase", "shelf"]):
		var shelf_w: float = minf(lerpf(1.05, 1.75, large_room_t), w - 0.90)
		_set_pose(spec, Vector2(clampf(w - shelf_w - 0.38, 1.20, w - shelf_w - 0.16), maxf(0.24, d - 0.48)), Vector2(shelf_w, 0.34), 180.0, "bookcase")
		return spec
	if _has_any(tokens, ["alfombra", "rug", "textil"]):
		var rug_size := Vector2(minf(lerpf(2.35, 3.45, large_room_t), w - 1.30), minf(lerpf(1.35, 2.05, large_room_t), d - 1.40))
		_set_pose(spec, Vector2(clampf(w * 0.28, 0.85, w - rug_size.x - 0.45), clampf(d * 0.35, 0.85, d - rug_size.y - 0.35)), rug_size, 0.0, "rug")
		return spec
	if _has_any(tokens, ["sillon", "sillón", "butaca", "armchair"]):
		var armchair_size := Vector2(lerpf(0.72, 0.84, large_room_t), lerpf(0.74, 0.86, large_room_t))
		_set_pose(spec, Vector2(clampf(w - armchair_size.x - 0.48, 1.80, w - armchair_size.x - 0.18), clampf(d - armchair_size.y - 0.48, 1.25, d - armchair_size.y - 0.18)), armchair_size, -25.0, "armchair")
		return spec
	if _has_any(tokens, ["aparador", "dresser", "storage"]):
		_set_pose(spec, Vector2(clampf(w - 1.00, 2.20, w - 0.70), maxf(0.18, d - 0.50)), Vector2(0.66, 0.30), 0.0, "dresser")
		return spec
	return spec


static func _set_pose(spec: Dictionary, pos: Vector2, size: Vector2, rotation_deg: float, visual_kind: String) -> void:
	spec["position_m"] = pos
	spec["size_m"] = size
	spec["rotation_deg"] = rotation_deg
	spec["kind"] = visual_kind
	spec["visual_pose_locked"] = true


static func _tokens(id_value: Variant, name_value: Variant, kind_value: Variant) -> String:
	return ("%s %s %s" % [String(id_value), String(name_value), String(kind_value)]).strip_edges().to_lower()


static func _has_any(tokens: String, words: Array[String]) -> bool:
	for word in words:
		if tokens.contains(word):
			return true
	return false
