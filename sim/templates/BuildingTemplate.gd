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
	# fuel_energy_MJ: carga de combustible total (área × densidad de carga térmica)
	# max_hrr_kw:     tasa máxima de liberación de calor físicamente posible en la sala
	#
	# Valores de referencia (EN 1991-1-2 / SFPE):
	#   Salón   20m² × 300 MJ/m² = 6000 MJ  — muebles tapizados, madera, textiles
	#   Pasillo 11m² ×  75 MJ/m² =  800 MJ  — poco combustible
	#   Dormit. 10m² × 350 MJ/m² = 3500 MJ  — camas, armarios, textiles
	#   Cocina  15m² × 230 MJ/m² = 3500 MJ  — menos madera, grasa acelera
	#   Baño     7m² ×  55 MJ/m² =  400 MJ  — casi solo plásticos

	rooms_data.append({
		"id": 0,
		"name": "Salon",
		"kind": "salon",
		"rect": r_salon,
		"height_m": 2.4,
		"fuel_energy_MJ": 6000.0,
		"max_hrr_kw": 3000.0
	})

	rooms_data.append({
		"id": 1,
		"name": "Pasillo",
		"kind": "pasillo",
		"rect": r_pasillo,
		"height_m": 2.4,
		"fuel_energy_MJ": 800.0,
		"max_hrr_kw": 600.0
	})

	rooms_data.append({
		"id": 2,
		"name": "Dormitorio1",
		"kind": "dormitorio",
		"rect": r_dorm1,
		"height_m": 2.4,
		"fuel_energy_MJ": 3500.0,
		"max_hrr_kw": 2000.0
	})

	rooms_data.append({
		"id": 3,
		"name": "Dormitorio2",
		"kind": "dormitorio",
		"rect": r_dorm2,
		"height_m": 2.4,
		"fuel_energy_MJ": 2500.0,
		"max_hrr_kw": 1800.0
	})

	rooms_data.append({
		"id": 4,
		"name": "Cocina",
		"kind": "cocina",
		"rect": r_cocina,
		"height_m": 2.4,
		"fuel_energy_MJ": 3500.0,
		"max_hrr_kw": 2500.0
	})

	rooms_data.append({
		"id": 5,
		"name": "Bano",
		"kind": "bano",
		"rect": r_bano,
		"height_m": 2.4,
		"fuel_energy_MJ": 400.0,
		"max_hrr_kw": 400.0
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
	# PUERTA ENTRADA PRINCIPAL
	# ----------------------------
	# Pasillo r_pasillo = Rect2(5.0, 0.0, 1.5, 7.0)
	# La pared "bottom" del pasillo es el acceso al exterior (entry)
	openings_data.append({
		"a": 1,
		"b": -1,
		"type": "door",
		"width_m": 0.9,
		"height_m": 2.1,
		"open_fraction": 0.0,
		"wall": "bottom"
	}) # puerta principal pasillo -> exterior

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
		"sill_m": 0.8,
		"wall": "top"
	}) # salon

	openings_data.append({
		"a": 4,
		"b": -1,
		"type": "window",
		"width_m": 1.2,
		"height_m": 1.0,
		"open_fraction": 0.0,
		"sill_m": 1.0,
		"wall": "bottom"
	}) # cocina

	openings_data.append({
		"a": 2,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 0.9,
		"wall": "right"
	}) # dorm1

	openings_data.append({
		"a": 3,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 0.9,
		"wall": "right"
	}) # dorm2

	openings_data.append({
		"a": 5,
		"b": -1,
		"type": "window",
		"width_m": 0.6,
		"height_m": 0.6,
		"open_fraction": 0.0,
		"sill_m": 1.4,
		"wall": "bottom"
	}) # baño

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data
	}


func create_ghanekar_bedroom_hallway() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	# Approximate single-story ranch layout inspired by Ghanekar (2026).
	# Key features preserved for validation:
	# - 2.45 m ceilings
	# - fire bedroom with open exterior window
	# - hallway transport path with a distal sensor zone
	# - open front door to exterior
	# - mixed interior door states noted in the paper
	var r_bedroom_fire := Rect2(0.0, 0.0, 4.0, 3.6)
	var r_bedroom_2 := Rect2(0.0, 3.6, 4.0, 3.2)
	var r_bedroom_3 := Rect2(0.0, 6.8, 4.0, 3.2)
	var r_bedroom_1 := Rect2(0.0, 10.0, 4.0, 3.4)
	var r_hall_near := Rect2(4.0, 0.0, 1.6, 6.8)
	var r_hall_far := Rect2(4.0, 6.8, 1.6, 6.6)
	var r_living := Rect2(5.6, 0.0, 8.0, 7.0)
	var r_kitchen := Rect2(5.6, 7.0, 4.5, 4.0)
	var r_bath_1 := Rect2(10.1, 7.0, 3.5, 2.2)
	var r_bath_2 := Rect2(10.1, 9.2, 3.5, 1.8)

	room_rect_m[0] = r_bedroom_fire
	room_rect_m[1] = r_hall_near
	room_rect_m[2] = r_hall_far
	room_rect_m[3] = r_living
	room_rect_m[4] = r_kitchen
	room_rect_m[5] = r_bedroom_2
	room_rect_m[6] = r_bedroom_3
	room_rect_m[7] = r_bedroom_1
	room_rect_m[8] = r_bath_1
	room_rect_m[9] = r_bath_2

	rooms_data.append({
		"id": 0,
		"name": "Bedroom4_Fire",
		"kind": "dormitorio",
		"rect": r_bedroom_fire,
		"height_m": 2.45,
		"fuel_energy_MJ": 4200.0,
		"max_hrr_kw": 2600.0
	})

	rooms_data.append({
		"id": 1,
		"name": "Hallway_Near",
		"kind": "pasillo",
		"rect": r_hall_near,
		"height_m": 2.45,
		"fuel_energy_MJ": 500.0,
		"max_hrr_kw": 250.0
	})

	rooms_data.append({
		"id": 2,
		"name": "Hallway_Far",
		"kind": "pasillo",
		"rect": r_hall_far,
		"height_m": 2.45,
		"fuel_energy_MJ": 500.0,
		"max_hrr_kw": 250.0
	})

	rooms_data.append({
		"id": 3,
		"name": "LivingRoom",
		"kind": "salon",
		"rect": r_living,
		"height_m": 2.45,
		"fuel_energy_MJ": 7200.0,
		"max_hrr_kw": 3200.0
	})

	rooms_data.append({
		"id": 4,
		"name": "Kitchen",
		"kind": "cocina",
		"rect": r_kitchen,
		"height_m": 2.45,
		"fuel_energy_MJ": 3800.0,
		"max_hrr_kw": 2200.0
	})

	rooms_data.append({
		"id": 5,
		"name": "Bedroom2",
		"kind": "dormitorio",
		"rect": r_bedroom_2,
		"height_m": 2.45,
		"fuel_energy_MJ": 3200.0,
		"max_hrr_kw": 1800.0
	})

	rooms_data.append({
		"id": 6,
		"name": "Bedroom3",
		"kind": "dormitorio",
		"rect": r_bedroom_3,
		"height_m": 2.45,
		"fuel_energy_MJ": 3200.0,
		"max_hrr_kw": 1800.0
	})

	rooms_data.append({
		"id": 7,
		"name": "Bedroom1",
		"kind": "dormitorio",
		"rect": r_bedroom_1,
		"height_m": 2.45,
		"fuel_energy_MJ": 3000.0,
		"max_hrr_kw": 1600.0
	})

	rooms_data.append({
		"id": 8,
		"name": "Bath1",
		"kind": "bano",
		"rect": r_bath_1,
		"height_m": 2.45,
		"fuel_energy_MJ": 350.0,
		"max_hrr_kw": 250.0
	})

	rooms_data.append({
		"id": 9,
		"name": "Bath2",
		"kind": "bano",
		"rect": r_bath_2,
		"height_m": 2.45,
		"fuel_energy_MJ": 300.0,
		"max_hrr_kw": 200.0
	})

	openings_data.append({
		"a": 0,
		"b": 1,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 5,
		"b": 1,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 6,
		"b": 2,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 7,
		"b": 2,
		"type": "door",
		"width_m": 0.8,
		"height_m": 2.0,
		"open_fraction": 0.0
	})

	openings_data.append({
		"a": 1,
		"b": 2,
		"type": "door",
		"width_m": 1.1,
		"height_m": 2.1,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 1,
		"b": 3,
		"type": "door",
		"width_m": 1.2,
		"height_m": 2.1,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 2,
		"b": 3,
		"type": "door",
		"width_m": 1.0,
		"height_m": 2.1,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 3,
		"b": 4,
		"type": "door",
		"width_m": 2.2,
		"height_m": 2.3,
		"open_fraction": 1.0
	})

	openings_data.append({
		"a": 4,
		"b": 8,
		"type": "door",
		"width_m": 0.7,
		"height_m": 2.0,
		"open_fraction": 0.0
	})

	openings_data.append({
		"a": 4,
		"b": 9,
		"type": "door",
		"width_m": 0.7,
		"height_m": 2.0,
		"open_fraction": 0.0
	})

	openings_data.append({
		"a": 0,
		"b": -1,
		"type": "window",
		"width_m": 1.8,
		"height_m": 0.6,
		"open_fraction": 1.0,
		"sill_m": 0.9,
		"wall": "left"
	})

	openings_data.append({
		"a": 3,
		"b": -1,
		"type": "door",
		"width_m": 0.9,
		"height_m": 2.0,
		"open_fraction": 1.0,
		"wall": "right"
	})

	openings_data.append({
		"a": 3,
		"b": -1,
		"type": "window",
		"width_m": 2.4,
		"height_m": 1.2,
		"open_fraction": 0.0,
		"sill_m": 0.8,
		"wall": "top"
	})

	openings_data.append({
		"a": 4,
		"b": -1,
		"type": "window",
		"width_m": 0.9,
		"height_m": 0.9,
		"open_fraction": 0.0,
		"sill_m": 1.2,
		"wall": "bottom"
	})

	openings_data.append({
		"a": 5,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 0.9,
		"wall": "left"
	})

	openings_data.append({
		"a": 6,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 0.9,
		"wall": "left"
	})

	openings_data.append({
		"a": 7,
		"b": -1,
		"type": "window",
		"width_m": 1.4,
		"height_m": 1.1,
		"open_fraction": 0.0,
		"sill_m": 0.9,
		"wall": "left"
	})

	openings_data.append({
		"a": 8,
		"b": -1,
		"type": "window",
		"width_m": 0.5,
		"height_m": 0.5,
		"open_fraction": 0.0,
		"sill_m": 1.4,
		"wall": "right"
	})

	openings_data.append({
		"a": 9,
		"b": -1,
		"type": "window",
		"width_m": 0.5,
		"height_m": 0.5,
		"open_fraction": 0.0,
		"sill_m": 1.4,
		"wall": "right"
	})

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data
	}
