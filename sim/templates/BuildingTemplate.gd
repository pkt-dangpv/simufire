extends RefCounted

# ============================================================
# BUILDING TEMPLATE
# ------------------------------------------------------------
# Fábrica de planos de edificio para la simulación.
# Cada método devuelve un Dictionary con las claves:
#   "rooms": Array[Dictionary] con datos de habitaciones
#   "openings": Array[Dictionary] con datos de aperturas
# Plantillas disponibles:
#   create_simple_house()            – 6 habitaciones residencial
#   create_ghanekar_bedroom_hallway()– 10 habitaciones (Ghanekar)
# ============================================================

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
		"max_hrr_kw": 3000.0,
		"fuel_objects": [
			{"id": "salon_sofa", "name": "Sofá", "kind": "mobiliario_tapizado",
				"position_m": {"x": 0.2, "y": 1.4}, "size_m": {"x": 2.2, "y": 0.9},
				"footprint_m2": 2.0, "exposed_area_m2": 3.5, "elevation_m": 0.4,
				"fuel_energy_MJ": 700.0, "max_hrr_kw": 400.0,
				"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.012, "co_yield_kg_per_MJ": 0.0004},
			{"id": "salon_libreria", "name": "Librería", "kind": "mobiliario_madera",
				"position_m": {"x": 4.5, "y": 0.2}, "size_m": {"x": 0.4, "y": 2.4},
				"footprint_m2": 1.0, "exposed_area_m2": 2.0, "elevation_m": 0.0,
				"fuel_energy_MJ": 1200.0, "max_hrr_kw": 300.0,
				"ignition_temp_c": 290.0, "ignition_flux_kw_m2": 14.0,
				"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
			{"id": "salon_textiles", "name": "Alfombra y textiles", "kind": "textiles",
				"position_m": {"x": 0.2, "y": 3.1}, "size_m": {"x": 2.0, "y": 0.7},
				"footprint_m2": 3.0, "exposed_area_m2": 3.0, "elevation_m": 0.05,
				"fuel_energy_MJ": 500.0, "max_hrr_kw": 350.0,
				"ignition_temp_c": 275.0, "ignition_flux_kw_m2": 13.0,
				"smoke_yield_kg_per_MJ": 0.015, "co_yield_kg_per_MJ": 0.0005},
			{"id": "salon_mesa", "name": "Mesa y TV", "kind": "mobiliario_mixto",
				"position_m": {"x": 1.0, "y": 0.3}, "size_m": {"x": 1.5, "y": 0.9},
				"footprint_m2": 1.5, "exposed_area_m2": 2.0, "elevation_m": 0.7,
				"fuel_energy_MJ": 300.0, "max_hrr_kw": 200.0,
				"ignition_temp_c": 330.0, "ignition_flux_kw_m2": 18.0,
				"smoke_yield_kg_per_MJ": 0.018, "co_yield_kg_per_MJ": 0.0006},
			{"id": "salon_resto", "name": "Resto mobiliario", "kind": "mobiliario_madera",
				"position_m": {"x": 2.5, "y": 1.3}, "size_m": {"x": 1.8, "y": 2.0},
				"footprint_m2": 4.0, "exposed_area_m2": 5.0, "elevation_m": 0.5,
				"fuel_energy_MJ": 3300.0, "max_hrr_kw": 2000.0,
				"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
		]
	})

	rooms_data.append({
		"id": 1,
		"name": "Pasillo",
		"kind": "pasillo",
		"rect": r_pasillo,
		"height_m": 2.4,
		"fuel_energy_MJ": 800.0,
		"max_hrr_kw": 600.0,
		"fuel_objects": [
			{"id": "pasillo_textiles", "name": "Alfombra pasillo", "kind": "textiles",
				"position_m": {"x": 0.1, "y": 2.5}, "size_m": {"x": 1.3, "y": 1.2},
				"footprint_m2": 1.5, "exposed_area_m2": 1.5, "elevation_m": 0.05,
				"fuel_energy_MJ": 200.0, "max_hrr_kw": 100.0,
				"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
				"smoke_yield_kg_per_MJ": 0.014, "co_yield_kg_per_MJ": 0.0004},
			{"id": "pasillo_mueble", "name": "Mueble recibidor", "kind": "mobiliario_madera",
				"position_m": {"x": 0.1, "y": 0.3}, "size_m": {"x": 0.7, "y": 0.7},
				"footprint_m2": 0.5, "exposed_area_m2": 1.0, "elevation_m": 0.8,
				"fuel_energy_MJ": 200.0, "max_hrr_kw": 100.0,
				"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
			{"id": "pasillo_resto", "name": "Resto carga pasillo", "kind": "mobiliario_madera",
				"position_m": {"x": 0.1, "y": 4.2}, "size_m": {"x": 1.3, "y": 2.5},
				"footprint_m2": 2.0, "exposed_area_m2": 2.0, "elevation_m": 0.5,
				"fuel_energy_MJ": 400.0, "max_hrr_kw": 400.0,
				"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
		]
	})

	rooms_data.append({
		"id": 2,
		"name": "Dormitorio1",
		"kind": "dormitorio",
		"rect": r_dorm1,
		"height_m": 2.4,
		"fuel_energy_MJ": 3500.0,
		"max_hrr_kw": 2000.0,
		"fuel_objects": [
			{"id": "dorm1_cama", "name": "Cama", "kind": "mobiliario_tapizado",
				"position_m": {"x": 0.2, "y": 0.3}, "size_m": {"x": 1.8, "y": 1.0},
				"footprint_m2": 2.0, "exposed_area_m2": 3.0, "elevation_m": 0.5,
				"fuel_energy_MJ": 900.0, "max_hrr_kw": 500.0,
				"ignition_temp_c": 295.0, "ignition_flux_kw_m2": 15.0,
				"smoke_yield_kg_per_MJ": 0.013, "co_yield_kg_per_MJ": 0.0004},
			{"id": "dorm1_armario", "name": "Armario", "kind": "mobiliario_madera",
				"position_m": {"x": 3.1, "y": 0.2}, "size_m": {"x": 0.35, "y": 2.0},
				"footprint_m2": 1.0, "exposed_area_m2": 2.2, "elevation_m": 0.0,
				"fuel_energy_MJ": 800.0, "max_hrr_kw": 350.0,
				"ignition_temp_c": 300.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
			{"id": "dorm1_textiles", "name": "Textiles y cortinas", "kind": "textiles",
				"position_m": {"x": 0.2, "y": 2.1}, "size_m": {"x": 1.8, "y": 0.7},
				"footprint_m2": 2.0, "exposed_area_m2": 2.5, "elevation_m": 0.3,
				"fuel_energy_MJ": 400.0, "max_hrr_kw": 200.0,
				"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
				"smoke_yield_kg_per_MJ": 0.016, "co_yield_kg_per_MJ": 0.0005},
			{"id": "dorm1_resto", "name": "Resto mobiliario", "kind": "mobiliario_madera",
				"position_m": {"x": 2.1, "y": 1.4}, "size_m": {"x": 0.9, "y": 1.5},
				"footprint_m2": 2.0, "exposed_area_m2": 2.5, "elevation_m": 0.5,
				"fuel_energy_MJ": 1400.0, "max_hrr_kw": 1000.0,
				"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
		]
	})

	rooms_data.append({
		"id": 3,
		"name": "Dormitorio2",
		"kind": "dormitorio",
		"rect": r_dorm2,
		"height_m": 2.4,
		"fuel_energy_MJ": 2500.0,
		"max_hrr_kw": 1800.0,
		"fuel_objects": [
			{"id": "dorm2_cama", "name": "Cama", "kind": "mobiliario_tapizado",
				"position_m": {"x": 0.2, "y": 0.4}, "size_m": {"x": 1.4, "y": 0.9},
				"footprint_m2": 1.5, "exposed_area_m2": 2.5, "elevation_m": 0.5,
				"fuel_energy_MJ": 700.0, "max_hrr_kw": 400.0,
				"ignition_temp_c": 295.0, "ignition_flux_kw_m2": 15.0,
				"smoke_yield_kg_per_MJ": 0.013, "co_yield_kg_per_MJ": 0.0004},
			{"id": "dorm2_armario", "name": "Armario", "kind": "mobiliario_madera",
				"position_m": {"x": 3.1, "y": 0.2}, "size_m": {"x": 0.35, "y": 1.6},
				"footprint_m2": 0.8, "exposed_area_m2": 1.8, "elevation_m": 0.0,
				"fuel_energy_MJ": 600.0, "max_hrr_kw": 250.0,
				"ignition_temp_c": 300.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
			{"id": "dorm2_textiles", "name": "Textiles", "kind": "textiles",
				"position_m": {"x": 0.2, "y": 1.5}, "size_m": {"x": 1.3, "y": 0.4},
				"footprint_m2": 1.5, "exposed_area_m2": 2.0, "elevation_m": 0.3,
				"fuel_energy_MJ": 300.0, "max_hrr_kw": 150.0,
				"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
				"smoke_yield_kg_per_MJ": 0.016, "co_yield_kg_per_MJ": 0.0005},
			{"id": "dorm2_resto", "name": "Resto mobiliario", "kind": "mobiliario_madera",
				"position_m": {"x": 1.7, "y": 0.3}, "size_m": {"x": 1.3, "y": 1.5},
				"footprint_m2": 1.5, "exposed_area_m2": 2.0, "elevation_m": 0.5,
				"fuel_energy_MJ": 900.0, "max_hrr_kw": 800.0,
				"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
		]
	})

	rooms_data.append({
		"id": 4,
		"name": "Cocina",
		"kind": "cocina",
		"rect": r_cocina,
		"height_m": 2.4,
		"fuel_energy_MJ": 3500.0,
		"max_hrr_kw": 2500.0,
		"fuel_objects": [
			{"id": "cocina_muebles", "name": "Muebles cocina", "kind": "mobiliario_madera",
				"position_m": {"x": 0.2, "y": 0.2}, "size_m": {"x": 1.8, "y": 1.1},
				"footprint_m2": 2.0, "exposed_area_m2": 3.0, "elevation_m": 0.8,
				"fuel_energy_MJ": 1000.0, "max_hrr_kw": 500.0,
				"ignition_temp_c": 285.0, "ignition_flux_kw_m2": 14.0,
				"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00028},
			{"id": "cocina_grasa", "name": "Grasa y aceites", "kind": "liquido_combustible",
				"position_m": {"x": 2.2, "y": 0.2}, "size_m": {"x": 0.7, "y": 0.7},
				"footprint_m2": 0.5, "exposed_area_m2": 0.5, "elevation_m": 0.9,
				"fuel_energy_MJ": 600.0, "max_hrr_kw": 800.0,
				"ignition_temp_c": 260.0, "ignition_flux_kw_m2": 11.0,
				"smoke_yield_kg_per_MJ": 0.022, "co_yield_kg_per_MJ": 0.0007},
			{"id": "cocina_textiles", "name": "Textiles cocina", "kind": "textiles",
				"position_m": {"x": 0.2, "y": 1.5}, "size_m": {"x": 1.0, "y": 1.2},
				"footprint_m2": 1.0, "exposed_area_m2": 1.0, "elevation_m": 0.5,
				"fuel_energy_MJ": 300.0, "max_hrr_kw": 200.0,
				"ignition_temp_c": 280.0, "ignition_flux_kw_m2": 13.0,
				"smoke_yield_kg_per_MJ": 0.014, "co_yield_kg_per_MJ": 0.0004},
			{"id": "cocina_resto", "name": "Resto carga cocina", "kind": "mobiliario_mixto",
				"position_m": {"x": 3.1, "y": 0.4}, "size_m": {"x": 1.7, "y": 2.2},
				"footprint_m2": 3.0, "exposed_area_m2": 3.5, "elevation_m": 0.7,
				"fuel_energy_MJ": 1600.0, "max_hrr_kw": 1500.0,
				"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.012, "co_yield_kg_per_MJ": 0.00035}
		]
	})

	rooms_data.append({
		"id": 5,
		"name": "Bano",
		"kind": "bano",
		"rect": r_bano,
		"height_m": 2.4,
		"fuel_energy_MJ": 400.0,
		"max_hrr_kw": 400.0,
		"fuel_objects": [
			{"id": "bano_plasticos", "name": "Plásticos y WC", "kind": "plasticos",
				"position_m": {"x": 1.2, "y": 0.5}, "size_m": {"x": 0.8, "y": 1.2},
				"footprint_m2": 1.0, "exposed_area_m2": 1.5, "elevation_m": 0.8,
				"fuel_energy_MJ": 200.0, "max_hrr_kw": 150.0,
				"ignition_temp_c": 350.0, "ignition_flux_kw_m2": 20.0,
				"smoke_yield_kg_per_MJ": 0.025, "co_yield_kg_per_MJ": 0.0009},
			{"id": "bano_textiles", "name": "Textiles baño", "kind": "textiles",
				"position_m": {"x": 0.2, "y": 0.3}, "size_m": {"x": 0.9, "y": 0.9},
				"footprint_m2": 1.0, "exposed_area_m2": 1.0, "elevation_m": 0.5,
				"fuel_energy_MJ": 100.0, "max_hrr_kw": 80.0,
				"ignition_temp_c": 275.0, "ignition_flux_kw_m2": 13.0,
				"smoke_yield_kg_per_MJ": 0.014, "co_yield_kg_per_MJ": 0.0004},
			{"id": "bano_resto", "name": "Resto carga baño", "kind": "mobiliario_madera",
				"position_m": {"x": 2.2, "y": 0.4}, "size_m": {"x": 1.0, "y": 1.0},
				"footprint_m2": 1.0, "exposed_area_m2": 1.0, "elevation_m": 0.7,
				"fuel_energy_MJ": 100.0, "max_hrr_kw": 200.0,
				"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
		]
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
		"max_hrr_kw": 2600.0,
		"fuel_objects": [
			{"id": "ghanekar_bed_mattress", "name": "Bed mattress", "kind": "mobiliario_tapizado",
				"footprint_m2": 2.0, "exposed_area_m2": 3.2, "elevation_m": 0.45,
				"fuel_energy_MJ": 900.0, "max_hrr_kw": 650.0,
				"ignition_temp_c": 295.0, "ignition_flux_kw_m2": 15.0,
				"smoke_yield_kg_per_MJ": 0.026, "co_yield_kg_per_MJ": 0.00110},
			{"id": "ghanekar_bedding_textiles", "name": "Bedding and textiles", "kind": "textiles",
				"footprint_m2": 1.6, "exposed_area_m2": 2.4, "elevation_m": 0.55,
				"fuel_energy_MJ": 350.0, "max_hrr_kw": 450.0,
				"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
				"smoke_yield_kg_per_MJ": 0.024, "co_yield_kg_per_MJ": 0.00120},
			{"id": "ghanekar_wardrobe_wood", "name": "Wardrobe and wood furniture", "kind": "mobiliario_madera",
				"footprint_m2": 1.2, "exposed_area_m2": 2.4, "elevation_m": 0.0,
				"fuel_energy_MJ": 700.0, "max_hrr_kw": 300.0,
				"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.010, "co_yield_kg_per_MJ": 0.00030},
			{"id": "ghanekar_mixed_contents", "name": "Mixed contents and plastics", "kind": "mobiliario_mixto",
				"footprint_m2": 1.6, "exposed_area_m2": 2.2, "elevation_m": 0.6,
				"fuel_energy_MJ": 500.0, "max_hrr_kw": 350.0,
				"ignition_temp_c": 320.0, "ignition_flux_kw_m2": 18.0,
				"smoke_yield_kg_per_MJ": 0.032, "co_yield_kg_per_MJ": 0.00160},
			{"id": "ghanekar_remaining_load", "name": "Remaining bedroom load", "kind": "mobiliario_mixto",
				"footprint_m2": 3.0, "exposed_area_m2": 3.6, "elevation_m": 0.5,
				"fuel_energy_MJ": 1750.0, "max_hrr_kw": 850.0,
				"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
				"smoke_yield_kg_per_MJ": 0.016, "co_yield_kg_per_MJ": 0.00075}
		]
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
		"width_m": 3.2,
		"height_m": 2.45,
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
