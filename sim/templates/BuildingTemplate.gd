extends RefCounted

func create_simple_house() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	# ----------------------------
	# PLANO SIMPLE Y COHERENTE
	# ----------------------------
	var r_salon   := Rect2(0.0, 0.0, 5.0, 4.0)
	var r_pasillo := Rect2(5.0, 0.0, 1.5, 7.0)
	var r_dorm1   := Rect2(6.5, 0.0, 3.5, 3.0)
	var r_dorm2   := Rect2(6.5, 3.0, 3.5, 2.0)
	var r_bano    := Rect2(6.5, 5.0, 3.5, 2.0)
	var r_cocina  := Rect2(0.0, 4.0, 5.0, 3.0)

	# ----------------------------
	# RECTANGULOS PARA VISUALIZER
	# ----------------------------
	room_rect_m[0] = r_salon
	room_rect_m[1] = r_pasillo
	room_rect_m[2] = r_dorm1
	room_rect_m[3] = r_dorm2
	room_rect_m[4] = r_cocina
	room_rect_m[5] = r_bano

	# ----------------------------
	# ROOMS
	# ----------------------------
	rooms_data.append({
		"id": 0,
		"name": "Salon",
		"kind": "salon",
		"rect": r_salon,
		"height_m": 2.4
	})

	rooms_data.append({
		"id": 1,
		"name": "Pasillo",
		"kind": "pasillo",
		"rect": r_pasillo,
		"height_m": 2.4
	})

	rooms_data.append({
		"id": 2,
		"name": "Dormitorio1",
		"kind": "dormitorio",
		"rect": r_dorm1,
		"height_m": 2.4
	})

	rooms_data.append({
		"id": 3,
		"name": "Dormitorio2",
		"kind": "dormitorio",
		"rect": r_dorm2,
		"height_m": 2.4
	})

	rooms_data.append({
		"id": 4,
		"name": "Cocina",
		"kind": "cocina",
		"rect": r_cocina,
		"height_m": 2.4
	})

	rooms_data.append({
		"id": 5,
		"name": "Bano",
		"kind": "bano",
		"rect": r_bano,
		"height_m": 2.4
	})

	# ----------------------------
	# PUERTAS INTERIORES
	# ----------------------------
	openings_data.append({
		"a": 0,
		"b": 1,
		"type": "door",
		"width_m": 0.9,
		"height_m": 2.0,
		"open_fraction": 1.0
	}) # salon -> pasillo

	openings_data.append({
		"a": 4,
		"b": 1,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 1.0
	}) # cocina -> pasillo

	openings_data.append({
		"a": 2,
		"b": 1,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 1.0
	}) # dorm1 -> pasillo

	openings_data.append({
		"a": 3,
		"b": 1,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 1.0
	}) # dorm2 -> pasillo

	openings_data.append({
		"a": 5,
		"b": 1,
		"type": "door",
		"width_m": 0.7,
		"height_m": 2.0,
		"open_fraction": 1.0
	}) # baño -> pasillo

	# ----------------------------
	# VENTANAS EXTERIORES
	# ----------------------------
	openings_data.append({
		"a": 0,
		"b": -1,
		"type": "window",
		"width_m": 2.0,
		"height_m": 1.2,
		"open_fraction": 0.0,
		"sill_m": 1.0
	}) # salon

	openings_data.append({
		"a": 4,
		"b": -1,
		"type": "window",
		"width_m": 1.2,
		"height_m": 1.0,
		"open_fraction": 0.0,
		"sill_m": 1.0
	}) # cocina

	openings_data.append({
		"a": 2,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 1.0
	}) # dorm1

	openings_data.append({
		"a": 3,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 1.0
	}) # dorm2

	openings_data.append({
		"a": 5,
		"b": -1,
		"type": "window",
		"width_m": 0.6,
		"height_m": 0.6,
		"open_fraction": 0.0,
		"sill_m": 1.4
	}) # baño

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data
	}