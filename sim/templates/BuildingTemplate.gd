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

func get_preset_definitions() -> Array[Dictionary]:
	return [
		{
			"id": "simple_house",
			"name": "Casa simple",
			"description": "Vivienda de 6 estancias con pasillo central."
		},
		{
			"id": "compact_apartment",
			"name": "Piso 1 dormitorio",
			"description": "Piso pequeno con salon-cocina, dormitorio y bano."
		},
		{
			"id": "two_bed_apartment",
			"name": "Piso 2 dormitorios",
			"description": "Piso familiar compacto con distribuidor central. ~80-90 m2."
		},
		{
			"id": "three_bed_apartment",
			"name": "Piso 3 dormitorios",
			"description": "Piso familiar de tres dormitorios y dos banos. ~105-115 m2."
		},
		{
			"id": "row_house_ground_floor",
			"name": "Adosado planta baja",
			"description": "Adosado espanol tipico planta baja: vestibulo-escalera, salon delantera, cocina-comedor trasera con salida a jardin, despacho, aseo y trastero. ~68 m2."
		},
		{
			"id": "ranch_family_house",
			"name": "Ranch 3 dormitorios",
			"description": "Vivienda de una planta con zona de dia y ala de dormitorios. ~125-135 m2."
		},
		{
			"id": "ghanekar_bedroom_hallway",
			"name": "Ghanekar ranch HVAC",
			"description": "Proyeccion ranch de dormitorio-pasillo para transporte HVAC."
		},
		{
			"id": "uk_bungalow",
			"name": "Bungalow anglosajón",
			"description": "Bungalow UK/US: estructura de madera, moqueta, papel pintado. Carga de fuego alta (~88 m²)."
		},
		{
			"id": "piso_mediterraneo",
			"name": "Piso mediterráneo",
			"description": "Piso español 3 dormitorios: ladrillo, gres, yeso. Baño en suite. Carga de fuego menor (~103 m²)."
		}
	]


func create_by_name(preset_name: String) -> Dictionary:
	match preset_name:
		"compact_apartment":
			return create_compact_apartment()
		"two_bed_apartment":
			return create_two_bed_apartment()
		"three_bed_apartment":
			return create_three_bed_apartment()
		"row_house_ground_floor":
			return create_row_house_ground_floor()
		"ranch_family_house":
			return create_ranch_family_house()
		"ghanekar_bedroom_hallway":
			return create_ghanekar_ranch_hvac()
		"uk_bungalow":
			return create_uk_bungalow()
		"piso_mediterraneo":
			return create_piso_mediterraneo()
		_:
			return create_simple_house()


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

	_apply_simple_house_furniture_layout(rooms_data)

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
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[{"room_id": 1, "flow_fraction": 1.0, "height_fraction": 0.92}],
			[
				{"room_id": 0, "flow_fraction": 1.2, "height_fraction": 0.92},
				{"room_id": 2, "flow_fraction": 0.8, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.7, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.8, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.35, "height_fraction": 0.92}
			],
			0.24,
			0.016
		)
	}


func _apply_simple_house_furniture_layout(rooms_data: Array) -> void:
	# Layout visual de la plantilla residencial: piezas con proporciones domesticas,
	# despejando recorridos y evitando grandes bloques genericos en mitad de sala.
	rooms_data[0]["fuel_objects"] = [
		{"id": "salon_sofa", "name": "Sofa 3 plazas", "kind": "mobiliario_tapizado", "room_id": 0,
			"position_m": {"x": 0.30, "y": 1.20}, "size_m": {"x": 0.90, "y": 2.35}, "rotation_deg": 90.0,
			"footprint_m2": 2.1, "exposed_area_m2": 3.6, "elevation_m": 0.38,
			"fuel_energy_MJ": 1100.0, "max_hrr_kw": 700.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.012, "co_yield_kg_per_MJ": 0.0004},
		{"id": "salon_mesa_centro", "name": "Mesa centro", "kind": "mobiliario_madera", "room_id": 0,
			"position_m": {"x": 1.90, "y": 1.85}, "size_m": {"x": 1.15, "y": 0.65},
			"footprint_m2": 0.75, "exposed_area_m2": 1.4, "elevation_m": 0.45,
			"fuel_energy_MJ": 280.0, "max_hrr_kw": 220.0,
			"ignition_temp_c": 330.0, "ignition_flux_kw_m2": 18.0,
			"smoke_yield_kg_per_MJ": 0.018, "co_yield_kg_per_MJ": 0.0006},
		{"id": "salon_mueble_tv", "name": "Mueble TV", "kind": "mobiliario_madera", "room_id": 0,
			"position_m": {"x": 4.45, "y": 0.95}, "size_m": {"x": 0.35, "y": 1.45}, "rotation_deg": -90.0,
			"footprint_m2": 0.6, "exposed_area_m2": 1.4, "elevation_m": 0.35,
			"fuel_energy_MJ": 520.0, "max_hrr_kw": 260.0,
			"ignition_temp_c": 290.0, "ignition_flux_kw_m2": 14.0,
			"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
		{"id": "salon_libreria", "name": "Libreria", "kind": "mobiliario_madera", "room_id": 0,
			"position_m": {"x": 2.85, "y": 3.55}, "size_m": {"x": 1.20, "y": 0.35}, "rotation_deg": 180.0,
			"footprint_m2": 0.55, "exposed_area_m2": 1.8, "elevation_m": 0.0,
			"fuel_energy_MJ": 1300.0, "max_hrr_kw": 350.0,
			"ignition_temp_c": 290.0, "ignition_flux_kw_m2": 14.0,
			"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
		{"id": "salon_alfombra", "name": "Alfombra salon", "kind": "textiles", "room_id": 0,
			"position_m": {"x": 1.20, "y": 1.45}, "size_m": {"x": 2.30, "y": 1.35},
			"footprint_m2": 3.1, "exposed_area_m2": 3.1, "elevation_m": 0.03,
			"fuel_energy_MJ": 520.0, "max_hrr_kw": 330.0,
			"ignition_temp_c": 275.0, "ignition_flux_kw_m2": 13.0,
			"smoke_yield_kg_per_MJ": 0.015, "co_yield_kg_per_MJ": 0.0005},
		{"id": "salon_butaca", "name": "Sillon auxiliar", "kind": "mobiliario_tapizado", "room_id": 0,
			"position_m": {"x": 3.45, "y": 2.55}, "size_m": {"x": 0.80, "y": 0.85}, "rotation_deg": -35.0,
			"footprint_m2": 0.7, "exposed_area_m2": 1.4, "elevation_m": 0.35,
			"fuel_energy_MJ": 580.0, "max_hrr_kw": 360.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.012, "co_yield_kg_per_MJ": 0.0004},
		{"id": "salon_aparador", "name": "Aparador bajo", "kind": "mobiliario_madera", "room_id": 0,
			"position_m": {"x": 3.75, "y": 0.30}, "size_m": {"x": 0.90, "y": 0.35},
			"footprint_m2": 0.55, "exposed_area_m2": 1.5, "elevation_m": 0.35,
			"fuel_energy_MJ": 1700.0, "max_hrr_kw": 780.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
	]

	rooms_data[1]["fuel_objects"] = [
		{"id": "pasillo_alfombra", "name": "Alfombra pasillo", "kind": "textiles", "room_id": 1,
			"position_m": {"x": 0.45, "y": 0.80}, "size_m": {"x": 0.60, "y": 5.30},
			"footprint_m2": 4.35, "exposed_area_m2": 4.0, "elevation_m": 0.02,
			"fuel_energy_MJ": 260.0, "max_hrr_kw": 120.0,
			"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
			"smoke_yield_kg_per_MJ": 0.014, "co_yield_kg_per_MJ": 0.0004},
		{"id": "pasillo_consola", "name": "Consola recibidor", "kind": "mobiliario_madera", "room_id": 1,
			"position_m": {"x": 0.07, "y": 0.35}, "size_m": {"x": 0.28, "y": 0.80}, "rotation_deg": 90.0,
			"footprint_m2": 0.4, "exposed_area_m2": 0.8, "elevation_m": 0.75,
			"fuel_energy_MJ": 220.0, "max_hrr_kw": 130.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
		{"id": "pasillo_zapatero", "name": "Zapatero bajo", "kind": "mobiliario_madera", "room_id": 1,
			"position_m": {"x": 1.14, "y": 5.45}, "size_m": {"x": 0.28, "y": 0.80}, "rotation_deg": -90.0,
			"footprint_m2": 0.4, "exposed_area_m2": 0.8, "elevation_m": 0.35,
			"fuel_energy_MJ": 180.0, "max_hrr_kw": 120.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
		{"id": "pasillo_caja", "name": "Caja pequena", "kind": "mobiliario_mixto", "room_id": 1,
			"position_m": {"x": 0.16, "y": 6.35}, "size_m": {"x": 0.32, "y": 0.30},
			"footprint_m2": 0.16, "exposed_area_m2": 0.45, "elevation_m": 0.20,
			"fuel_energy_MJ": 140.0, "max_hrr_kw": 230.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
	]

	rooms_data[2]["fuel_objects"] = [
		{"id": "dorm1_cama", "name": "Cama matrimonio", "kind": "mobiliario_tapizado", "room_id": 2,
			"position_m": {"x": 0.35, "y": 1.15}, "size_m": {"x": 1.50, "y": 1.75},
			"footprint_m2": 2.9, "exposed_area_m2": 3.8, "elevation_m": 0.45,
			"fuel_energy_MJ": 1100.0, "max_hrr_kw": 650.0,
			"ignition_temp_c": 295.0, "ignition_flux_kw_m2": 15.0,
			"smoke_yield_kg_per_MJ": 0.013, "co_yield_kg_per_MJ": 0.0004},
		{"id": "dorm1_armario", "name": "Armario", "kind": "mobiliario_madera", "room_id": 2,
			"position_m": {"x": 1.95, "y": 0.25}, "size_m": {"x": 1.25, "y": 0.40},
			"footprint_m2": 0.75, "exposed_area_m2": 2.2, "elevation_m": 0.0,
			"fuel_energy_MJ": 850.0, "max_hrr_kw": 350.0,
			"ignition_temp_c": 300.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
		{"id": "dorm1_alfombra", "name": "Alfombra dormitorio", "kind": "textiles", "room_id": 2,
			"position_m": {"x": 1.80, "y": 2.05}, "size_m": {"x": 1.20, "y": 0.62},
			"footprint_m2": 0.94, "exposed_area_m2": 0.94, "elevation_m": 0.03,
			"fuel_energy_MJ": 250.0, "max_hrr_kw": 140.0,
			"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
			"smoke_yield_kg_per_MJ": 0.016, "co_yield_kg_per_MJ": 0.0005},
		{"id": "dorm1_cortinas", "name": "Cortinas", "kind": "textiles", "room_id": 2,
			"position_m": {"x": 1.45, "y": 0.02}, "size_m": {"x": 1.10, "y": 0.12},
			"footprint_m2": 0.13, "exposed_area_m2": 1.2, "elevation_m": 0.70,
			"fuel_energy_MJ": 250.0, "max_hrr_kw": 150.0,
			"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
			"smoke_yield_kg_per_MJ": 0.016, "co_yield_kg_per_MJ": 0.0005},
		{"id": "dorm1_comoda", "name": "Comoda", "kind": "mobiliario_madera", "room_id": 2,
			"position_m": {"x": 2.15, "y": 2.32}, "size_m": {"x": 0.95, "y": 0.42}, "rotation_deg": 180.0,
			"footprint_m2": 0.47, "exposed_area_m2": 1.1, "elevation_m": 0.45,
			"fuel_energy_MJ": 650.0, "max_hrr_kw": 360.0,
			"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025},
		{"id": "dorm1_mesilla", "name": "Mesilla", "kind": "mobiliario_madera", "room_id": 2,
			"position_m": {"x": 1.95, "y": 1.25}, "size_m": {"x": 0.42, "y": 0.42},
			"footprint_m2": 0.2, "exposed_area_m2": 0.6, "elevation_m": 0.40,
			"fuel_energy_MJ": 400.0, "max_hrr_kw": 350.0,
			"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
	]

	rooms_data[3]["fuel_objects"] = [
		{"id": "dorm2_cama", "name": "Cama individual", "kind": "mobiliario_tapizado", "room_id": 3,
			"position_m": {"x": 0.25, "y": 0.55}, "size_m": {"x": 0.90, "y": 1.35},
			"footprint_m2": 1.7, "exposed_area_m2": 2.7, "elevation_m": 0.45,
			"fuel_energy_MJ": 850.0, "max_hrr_kw": 480.0,
			"ignition_temp_c": 295.0, "ignition_flux_kw_m2": 15.0,
			"smoke_yield_kg_per_MJ": 0.013, "co_yield_kg_per_MJ": 0.0004},
		{"id": "dorm2_armario", "name": "Armario", "kind": "mobiliario_madera", "room_id": 3,
			"position_m": {"x": 2.15, "y": 0.18}, "size_m": {"x": 1.05, "y": 0.38},
			"footprint_m2": 0.52, "exposed_area_m2": 1.7, "elevation_m": 0.0,
			"fuel_energy_MJ": 600.0, "max_hrr_kw": 250.0,
			"ignition_temp_c": 300.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.008, "co_yield_kg_per_MJ": 0.00025},
		{"id": "dorm2_escritorio", "name": "Mesa escritorio", "kind": "mobiliario_madera", "room_id": 3,
			"position_m": {"x": 1.55, "y": 1.35}, "size_m": {"x": 1.05, "y": 0.45}, "rotation_deg": 180.0,
			"footprint_m2": 0.47, "exposed_area_m2": 1.0, "elevation_m": 0.70,
			"fuel_energy_MJ": 350.0, "max_hrr_kw": 220.0,
			"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025},
		{"id": "dorm2_alfombra", "name": "Alfombra dormitorio", "kind": "textiles", "room_id": 3,
			"position_m": {"x": 0.45, "y": 1.42}, "size_m": {"x": 1.00, "y": 0.40},
			"footprint_m2": 0.4, "exposed_area_m2": 0.4, "elevation_m": 0.03,
			"fuel_energy_MJ": 180.0, "max_hrr_kw": 100.0,
			"ignition_temp_c": 270.0, "ignition_flux_kw_m2": 12.0,
			"smoke_yield_kg_per_MJ": 0.016, "co_yield_kg_per_MJ": 0.0005},
		{"id": "dorm2_cajonera", "name": "Cajonera", "kind": "mobiliario_madera", "room_id": 3,
			"position_m": {"x": 1.35, "y": 0.28}, "size_m": {"x": 0.55, "y": 0.42},
			"footprint_m2": 0.25, "exposed_area_m2": 0.7, "elevation_m": 0.45,
			"fuel_energy_MJ": 520.0, "max_hrr_kw": 750.0,
			"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
	]

	rooms_data[4]["fuel_objects"] = [
		{"id": "cocina_encimera", "name": "Encimera y bajos", "kind": "mobiliario_madera", "room_id": 4,
			"position_m": {"x": 0.25, "y": 0.20}, "size_m": {"x": 3.15, "y": 0.65},
			"footprint_m2": 2.05, "exposed_area_m2": 3.2, "elevation_m": 0.80,
			"fuel_energy_MJ": 1100.0, "max_hrr_kw": 550.0,
			"ignition_temp_c": 285.0, "ignition_flux_kw_m2": 14.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00028},
		{"id": "cocina_columna", "name": "Columna despensa", "kind": "mobiliario_madera", "room_id": 4,
			"position_m": {"x": 4.05, "y": 0.20}, "size_m": {"x": 0.65, "y": 0.65},
			"footprint_m2": 0.42, "exposed_area_m2": 1.5, "elevation_m": 0.0,
			"fuel_energy_MJ": 550.0, "max_hrr_kw": 250.0,
			"ignition_temp_c": 285.0, "ignition_flux_kw_m2": 14.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00028},
		{"id": "cocina_grasa", "name": "Grasa y aceites", "kind": "liquido_combustible", "room_id": 4,
			"position_m": {"x": 2.05, "y": 0.35}, "size_m": {"x": 0.45, "y": 0.45},
			"footprint_m2": 0.2, "exposed_area_m2": 0.3, "elevation_m": 0.90,
			"fuel_energy_MJ": 600.0, "max_hrr_kw": 800.0,
			"ignition_temp_c": 260.0, "ignition_flux_kw_m2": 11.0,
			"smoke_yield_kg_per_MJ": 0.022, "co_yield_kg_per_MJ": 0.0007},
		{"id": "cocina_mesa", "name": "Mesa cocina", "kind": "mobiliario_madera", "room_id": 4,
			"position_m": {"x": 3.20, "y": 1.65}, "size_m": {"x": 1.15, "y": 0.75},
			"footprint_m2": 0.86, "exposed_area_m2": 1.4, "elevation_m": 0.70,
			"fuel_energy_MJ": 450.0, "max_hrr_kw": 300.0,
			"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.012, "co_yield_kg_per_MJ": 0.00035},
		{"id": "cocina_textiles", "name": "Panos cocina", "kind": "textiles", "room_id": 4,
			"position_m": {"x": 0.55, "y": 2.35}, "size_m": {"x": 0.65, "y": 0.38},
			"footprint_m2": 0.25, "exposed_area_m2": 0.5, "elevation_m": 0.25,
			"fuel_energy_MJ": 220.0, "max_hrr_kw": 140.0,
			"ignition_temp_c": 280.0, "ignition_flux_kw_m2": 13.0,
			"smoke_yield_kg_per_MJ": 0.014, "co_yield_kg_per_MJ": 0.0004},
		{"id": "cocina_auxiliar", "name": "Carro auxiliar", "kind": "mobiliario_mixto", "room_id": 4,
			"position_m": {"x": 2.30, "y": 2.10}, "size_m": {"x": 0.60, "y": 0.55},
			"footprint_m2": 0.33, "exposed_area_m2": 0.8, "elevation_m": 0.55,
			"fuel_energy_MJ": 580.0, "max_hrr_kw": 460.0,
			"ignition_temp_c": 305.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.012, "co_yield_kg_per_MJ": 0.00035}
	]

	rooms_data[5]["fuel_objects"] = [
		{"id": "bano_plasticos", "name": "Cubo y plasticos", "kind": "plasticos", "room_id": 5,
			"position_m": {"x": 0.35, "y": 0.35}, "size_m": {"x": 0.45, "y": 0.55},
			"footprint_m2": 0.25, "exposed_area_m2": 0.6, "elevation_m": 0.25,
			"fuel_energy_MJ": 120.0, "max_hrr_kw": 100.0,
			"ignition_temp_c": 350.0, "ignition_flux_kw_m2": 20.0,
			"smoke_yield_kg_per_MJ": 0.025, "co_yield_kg_per_MJ": 0.0009},
		{"id": "bano_textiles", "name": "Toallas", "kind": "textiles", "room_id": 5,
			"position_m": {"x": 2.45, "y": 0.25}, "size_m": {"x": 0.55, "y": 0.90},
			"footprint_m2": 0.5, "exposed_area_m2": 0.8, "elevation_m": 0.45,
			"fuel_energy_MJ": 130.0, "max_hrr_kw": 100.0,
			"ignition_temp_c": 275.0, "ignition_flux_kw_m2": 13.0,
			"smoke_yield_kg_per_MJ": 0.014, "co_yield_kg_per_MJ": 0.0004},
		{"id": "bano_mueble_lavabo", "name": "Mueble lavabo", "kind": "mobiliario_madera", "room_id": 5,
			"position_m": {"x": 1.35, "y": 1.25}, "size_m": {"x": 0.80, "y": 0.45},
			"footprint_m2": 0.36, "exposed_area_m2": 0.75, "elevation_m": 0.45,
			"fuel_energy_MJ": 150.0, "max_hrr_kw": 200.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.009, "co_yield_kg_per_MJ": 0.00025}
	]


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
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[
				{"room_id": 1, "flow_fraction": 0.9, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.8, "height_fraction": 0.92}
			],
			[
				{"room_id": 0, "flow_fraction": 1.0, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 7, "flow_fraction": 0.70, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 1.0, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.55, "height_fraction": 0.92}
			],
			0.34,
			0.022
		)
	}


func create_compact_apartment() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_living := Rect2(0.0, 0.0, 5.2, 4.1)
	var r_hall := Rect2(5.2, 0.0, 1.4, 4.1)
	var r_bedroom := Rect2(6.6, 0.0, 3.4, 3.1)
	var r_bath := Rect2(6.6, 3.1, 3.4, 1.9)
	var r_utility := Rect2(0.0, 4.1, 5.2, 1.4)

	room_rect_m[0] = r_living
	room_rect_m[1] = r_hall
	room_rect_m[2] = r_bedroom
	room_rect_m[3] = r_bath
	room_rect_m[4] = r_utility

	rooms_data.append(_make_room(0, "Salon-cocina", "salon", r_living, 2.5, 5200.0, 2600.0))
	rooms_data.append(_make_room(1, "Distribuidor", "pasillo", r_hall, 2.5, 450.0, 280.0))
	rooms_data.append(_make_room(2, "Dormitorio", "dormitorio", r_bedroom, 2.5, 3300.0, 1900.0))
	rooms_data.append(_make_room(3, "Bano", "bano", r_bath, 2.5, 260.0, 180.0))
	rooms_data.append(_make_room(4, "Lavadero", "cocina", r_utility, 2.5, 900.0, 700.0))

	openings_data.append(_make_opening(0, 1, "door", 0.9, 2.05, 1.0))
	openings_data.append(_make_opening(1, 2, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(1, 3, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_opening(0, 4, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_exterior_opening(1, "door", 0.9, 2.05, 0.0, 0.0, "bottom"))
	openings_data.append(_make_exterior_opening(0, "window", 2.2, 1.15, 0.0, 0.85, "top"))
	openings_data.append(_make_exterior_opening(2, "window", 1.4, 1.10, 0.0, 0.90, "right"))
	openings_data.append(_make_exterior_opening(4, "window", 0.8, 0.8, 0.0, 1.2, "bottom"))

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[{"room_id": 1, "flow_fraction": 1.0, "height_fraction": 0.90}],
			[
				{"room_id": 0, "flow_fraction": 1.15, "height_fraction": 0.92},
				{"room_id": 2, "flow_fraction": 0.85, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.30, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.45, "height_fraction": 0.92}
			],
			0.18,
			0.010
		)
	}


func create_two_bed_apartment() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_living := Rect2(0.0, 0.0, 4.8, 4.4)
	var r_kitchen := Rect2(0.0, 4.4, 3.0, 2.8)
	var r_entry := Rect2(4.8, 0.0, 1.5, 2.4)
	var r_hall := Rect2(4.8, 2.4, 1.5, 4.8)
	var r_bed_primary := Rect2(6.3, 0.0, 3.8, 3.5)
	var r_bed_secondary := Rect2(6.3, 3.5, 3.4, 3.2)
	var r_bath := Rect2(3.0, 4.4, 1.8, 2.2)
	var r_storage := Rect2(9.7, 3.5, 1.4, 2.0)

	room_rect_m[0] = r_living
	room_rect_m[1] = r_entry
	room_rect_m[2] = r_hall
	room_rect_m[3] = r_kitchen
	room_rect_m[4] = r_bed_primary
	room_rect_m[5] = r_bed_secondary
	room_rect_m[6] = r_bath
	room_rect_m[7] = r_storage

	rooms_data.append(_make_room(0, "Salon-comedor", "salon", r_living, 2.5, 6200.0, 3200.0))
	rooms_data.append(_make_room(1, "Recibidor", "pasillo", r_entry, 2.5, 300.0, 180.0))
	rooms_data.append(_make_room(2, "Pasillo", "pasillo", r_hall, 2.5, 450.0, 260.0))
	rooms_data.append(_make_room(3, "Cocina", "cocina", r_kitchen, 2.5, 2800.0, 1800.0))
	rooms_data.append(_make_room(4, "Dormitorio principal", "dormitorio", r_bed_primary, 2.5, 3600.0, 2100.0))
	rooms_data.append(_make_room(5, "Dormitorio 2", "dormitorio", r_bed_secondary, 2.5, 2800.0, 1700.0))
	rooms_data.append(_make_room(6, "Bano", "bano", r_bath, 2.5, 260.0, 180.0))
	rooms_data.append(_make_room(7, "Armario", "almacen", r_storage, 2.5, 700.0, 450.0))

	openings_data.append(_make_opening(1, 0, "door", 1.0, 2.1, 1.0))
	openings_data.append(_make_opening(1, 2, "door", 0.9, 2.1, 1.0))
	openings_data.append(_make_opening(0, 3, "door", 0.9, 2.05, 1.0))
	openings_data.append(_make_opening(2, 4, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(2, 5, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(2, 6, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_opening(5, 7, "door", 0.6, 2.0, 0.0))
	openings_data.append(_make_exterior_opening(1, "door", 0.95, 2.1, 0.0, 0.0, "top"))
	openings_data.append(_make_exterior_opening(0, "window", 2.4, 1.2, 0.0, 0.85, "left"))
	openings_data.append(_make_exterior_opening(3, "window", 1.2, 1.0, 0.0, 1.0, "bottom"))
	openings_data.append(_make_exterior_opening(4, "window", 1.6, 1.1, 0.0, 0.9, "right"))
	openings_data.append(_make_exterior_opening(5, "window", 1.4, 1.1, 0.0, 0.9, "right"))

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[{"room_id": 2, "flow_fraction": 1.0, "height_fraction": 0.90}],
			[
				{"room_id": 0, "flow_fraction": 1.1, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.55, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.85, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.30, "height_fraction": 0.92}
			],
			0.25,
			0.016
		)
	}


func create_three_bed_apartment() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_living := Rect2(0.0, 0.0, 5.2, 4.5)
	var r_kitchen := Rect2(0.0, 4.5, 3.3, 3.0)
	var r_entry := Rect2(5.2, 0.0, 1.5, 2.5)
	var r_hall := Rect2(5.2, 2.5, 1.5, 5.8)
	var r_primary := Rect2(6.7, 0.0, 3.9, 3.6)
	var r_bed2 := Rect2(6.7, 3.6, 3.3, 3.0)
	var r_bed3 := Rect2(6.7, 6.6, 3.3, 3.0)
	var r_bath := Rect2(3.3, 4.5, 1.9, 2.2)
	var r_wc := Rect2(3.3, 6.7, 1.9, 1.6)

	room_rect_m[0] = r_living
	room_rect_m[1] = r_entry
	room_rect_m[2] = r_hall
	room_rect_m[3] = r_kitchen
	room_rect_m[4] = r_primary
	room_rect_m[5] = r_bed2
	room_rect_m[6] = r_bed3
	room_rect_m[7] = r_bath
	room_rect_m[8] = r_wc

	rooms_data.append(_make_room(0, "Salon-comedor", "salon", r_living, 2.5, 7200.0, 3400.0))
	rooms_data.append(_make_room(1, "Recibidor", "pasillo", r_entry, 2.5, 320.0, 200.0))
	rooms_data.append(_make_room(2, "Pasillo", "pasillo", r_hall, 2.5, 520.0, 300.0))
	rooms_data.append(_make_room(3, "Cocina", "cocina", r_kitchen, 2.5, 3200.0, 2200.0))
	rooms_data.append(_make_room(4, "Dormitorio principal", "dormitorio", r_primary, 2.5, 3800.0, 2200.0))
	rooms_data.append(_make_room(5, "Dormitorio 2", "dormitorio", r_bed2, 2.5, 3000.0, 1800.0))
	rooms_data.append(_make_room(6, "Dormitorio 3", "dormitorio", r_bed3, 2.5, 2800.0, 1700.0))
	rooms_data.append(_make_room(7, "Bano", "bano", r_bath, 2.5, 300.0, 200.0))
	rooms_data.append(_make_room(8, "Aseo", "bano", r_wc, 2.5, 200.0, 150.0))

	openings_data.append(_make_opening(1, 0, "door", 1.0, 2.1, 1.0))
	openings_data.append(_make_opening(1, 2, "door", 0.9, 2.1, 1.0))
	openings_data.append(_make_opening(0, 3, "door", 0.9, 2.05, 1.0))
	openings_data.append(_make_opening(2, 4, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(2, 5, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(2, 6, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(2, 7, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_opening(2, 8, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_exterior_opening(1, "door", 0.95, 2.1, 0.0, 0.0, "top"))
	openings_data.append(_make_exterior_opening(0, "window", 2.6, 1.2, 0.0, 0.85, "left"))
	openings_data.append(_make_exterior_opening(3, "window", 1.2, 1.0, 0.0, 1.0, "bottom"))
	openings_data.append(_make_exterior_opening(4, "window", 1.6, 1.1, 0.0, 0.9, "right"))
	openings_data.append(_make_exterior_opening(5, "window", 1.4, 1.1, 0.0, 0.9, "right"))
	openings_data.append(_make_exterior_opening(6, "window", 1.4, 1.1, 0.0, 0.9, "right"))

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[{"room_id": 2, "flow_fraction": 1.0, "height_fraction": 0.90}],
			[
				{"room_id": 0, "flow_fraction": 1.2, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.55, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.85, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 7, "flow_fraction": 0.30, "height_fraction": 0.92}
			],
			0.32,
			0.020
		)
	}


func create_row_house_ground_floor() -> Dictionary:
	# -------------------------------------------------------------------
	# Adosado español típico – planta baja
	# Huella total: ~8.5 m (ancho) × 8.0 m (fondo) ≈ 68 m²
	# Orientación: fachada delantera = y=0 (calle); trasera = y=8.0 (jardín)
	#
	# Distribución:
	#   [Vestibulo+Escalera] 2.7×4.0  – fachada delantera lateral, entrada principal
	#   [Salon]              5.8×4.0  – fachada delantera, ventana a calle
	#   [Pasillo interior]   2.7×2.0  – distribuidor central planta baja
	#   [Despacho/estudio]   2.7×2.0  – pieza interior (posible dormitorio-0)
	#   [Cocina-comedor]     5.8×4.0  – fachada trasera, puerta a jardín + ventana
	#   [Aseo]               1.8×2.0  – junto a cocina, interior
	#   [Trastero]           1.8×2.0  – junto a escalera, interior
	# -------------------------------------------------------------------
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	# Anchura total 8.5 m, fachada 8.0 m de fondo
	var r_entry    := Rect2(0.0, 0.0, 2.7, 4.0)   # vestíbulo + caja escalera
	var r_living   := Rect2(2.7, 0.0, 5.8, 4.0)   # salón (fachada delantera)
	var r_hall     := Rect2(0.0, 4.0, 2.7, 2.0)   # pasillo distribuidor interior
	var r_office   := Rect2(2.7, 4.0, 2.7, 2.0)   # despacho / pieza polivalente
	var r_kitchen  := Rect2(2.7, 6.0, 5.8, 2.0)   # cocina-comedor (trasera)
	var r_bath     := Rect2(0.0, 6.0, 1.8, 2.0)   # aseo
	var r_storage  := Rect2(1.8, 6.0, 0.9, 2.0)   # trastero / lavadero

	room_rect_m[0] = r_entry
	room_rect_m[1] = r_living
	room_rect_m[2] = r_hall
	room_rect_m[3] = r_office
	room_rect_m[4] = r_kitchen
	room_rect_m[5] = r_bath
	room_rect_m[6] = r_storage

	# Altura libre en adosado español moderno
	var H: float = 2.60

	# Cargas de combustible (EN 1991-1-2):
	#   salón 23m² × 300 MJ/m² ≈ 6900 MJ  | cocina 11.6m² × 220 MJ/m² ≈ 2550 MJ
	#   despacho 5.4m² × 280 MJ/m² ≈ 1500 MJ | vestíbulo 10.8m² × 80 MJ/m² ≈ 860 MJ
	rooms_data.append(_make_room(0, "Vestibulo-Escalera", "pasillo",  r_entry,   H, 860.0,  500.0))
	rooms_data.append(_make_room(1, "Salon",              "salon",    r_living,  H, 6900.0, 3500.0))
	rooms_data.append(_make_room(2, "Pasillo",            "pasillo",  r_hall,    H, 320.0,  180.0))
	rooms_data.append(_make_room(3, "Despacho",           "dormitorio", r_office, H, 1500.0, 900.0))
	rooms_data.append(_make_room(4, "Cocina-comedor",     "cocina",   r_kitchen, H, 2550.0, 2200.0))
	rooms_data.append(_make_room(5, "Aseo",               "bano",     r_bath,    H, 200.0,  150.0))
	rooms_data.append(_make_room(6, "Trastero",           "almacen",  r_storage, H, 900.0,  600.0))

	# --- puertas interiores ---
	openings_data.append(_make_opening(0, 2, "door", 0.9, 2.1, 1.0))  # vestíbulo → pasillo
	openings_data.append(_make_opening(1, 2, "door", 1.0, 2.1, 1.0))  # salón → pasillo (pto unión)
	openings_data.append(_make_opening(2, 3, "door", 0.8, 2.0, 1.0))  # pasillo → despacho
	openings_data.append(_make_opening(2, 4, "door", 0.9, 2.1, 1.0))  # pasillo → cocina
	openings_data.append(_make_opening(2, 5, "door", 0.7, 2.0, 0.0))  # pasillo → aseo
	openings_data.append(_make_opening(0, 6, "door", 0.7, 2.0, 0.0))  # vestíbulo → trastero

	# --- apertura exterior: puerta principal (fachada delantera vestíbulo, wall top = y=0) ---
	openings_data.append(_make_exterior_opening(0, "door", 0.95, 2.1, 0.0, 0.0, "top"))

	# --- ventana salón (fachada delantera, wall top = y=0) ---
	openings_data.append(_make_exterior_opening(1, "window", 2.6, 1.2, 0.0, 0.85, "top"))

	# --- puerta trasera cocina a jardín (wall bottom = y max) ---
	openings_data.append(_make_exterior_opening(4, "door", 0.9, 2.1, 0.0, 0.0, "bottom"))

	# --- ventana cocina (fachada trasera) ---
	openings_data.append(_make_exterior_opening(4, "window", 1.4, 1.0, 0.0, 1.0, "bottom"))

	# --- ventana despacho (lateral) ---
	openings_data.append(_make_exterior_opening(3, "window", 1.2, 1.0, 0.0, 0.9, "right"))

	# --- ventana aseo (fachada trasera, pequeña y alta) ---
	openings_data.append(_make_exterior_opening(5, "window", 0.6, 0.6, 0.0, 1.5, "bottom"))

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[
				{"room_id": 0, "flow_fraction": 0.8, "height_fraction": 0.90},
				{"room_id": 2, "flow_fraction": 0.6, "height_fraction": 0.90}
			],
			[
				{"room_id": 1, "flow_fraction": 1.3, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.7, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 1.0, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.20, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.30, "height_fraction": 0.92}
			],
			0.24,
			0.016
		)
	}


func create_ranch_family_house() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_living := Rect2(0.0, 0.0, 5.6, 4.6)
	var r_kitchen := Rect2(0.0, 4.6, 3.8, 3.4)
	var r_dining := Rect2(3.8, 4.6, 3.0, 3.4)
	var r_hall := Rect2(5.6, 0.8, 1.5, 7.2)
	var r_primary := Rect2(7.1, 0.0, 4.1, 3.7)
	var r_bed2 := Rect2(7.1, 3.7, 3.5, 3.1)
	var r_bed3 := Rect2(7.1, 6.8, 3.5, 3.1)
	var r_bath := Rect2(5.6, 8.0, 2.0, 2.1)
	var r_laundry := Rect2(3.8, 8.0, 1.8, 2.1)

	room_rect_m[0] = r_living
	room_rect_m[1] = r_hall
	room_rect_m[2] = r_kitchen
	room_rect_m[3] = r_dining
	room_rect_m[4] = r_primary
	room_rect_m[5] = r_bed2
	room_rect_m[6] = r_bed3
	room_rect_m[7] = r_bath
	room_rect_m[8] = r_laundry

	rooms_data.append(_make_room(0, "Salon", "salon", r_living, 2.55, 7600.0, 3600.0))
	rooms_data.append(_make_room(1, "Pasillo dormitorios", "pasillo", r_hall, 2.55, 650.0, 350.0))
	rooms_data.append(_make_room(2, "Cocina", "cocina", r_kitchen, 2.55, 3600.0, 2300.0))
	rooms_data.append(_make_room(3, "Comedor", "salon", r_dining, 2.55, 2200.0, 1300.0))
	rooms_data.append(_make_room(4, "Dormitorio principal", "dormitorio", r_primary, 2.55, 3900.0, 2200.0))
	rooms_data.append(_make_room(5, "Dormitorio 2", "dormitorio", r_bed2, 2.55, 3000.0, 1800.0))
	rooms_data.append(_make_room(6, "Dormitorio 3", "dormitorio", r_bed3, 2.55, 3000.0, 1800.0))
	rooms_data.append(_make_room(7, "Bano", "bano", r_bath, 2.55, 300.0, 200.0))
	rooms_data.append(_make_room(8, "Lavadero", "almacen", r_laundry, 2.55, 900.0, 600.0))

	openings_data.append(_make_opening(0, 1, "door", 1.1, 2.1, 1.0))
	openings_data.append(_make_opening(0, 2, "door", 1.0, 2.1, 1.0))
	openings_data.append(_make_opening(2, 3, "door", 1.4, 2.2, 1.0))
	openings_data.append(_make_opening(1, 4, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(1, 5, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(1, 6, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(1, 7, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_opening(3, 8, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_exterior_opening(0, "door", 0.95, 2.1, 0.0, 0.0, "top"))
	openings_data.append(_make_exterior_opening(3, "door", 0.95, 2.1, 0.0, 0.0, "bottom"))
	openings_data.append(_make_exterior_opening(0, "window", 2.4, 1.2, 0.0, 0.8, "left"))
	openings_data.append(_make_exterior_opening(2, "window", 1.4, 1.0, 0.0, 1.0, "bottom"))
	openings_data.append(_make_exterior_opening(4, "window", 1.8, 1.1, 0.0, 0.9, "right"))
	openings_data.append(_make_exterior_opening(5, "window", 1.4, 1.1, 0.0, 0.9, "right"))
	openings_data.append(_make_exterior_opening(6, "window", 1.4, 1.1, 0.0, 0.9, "right"))

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[
				{"room_id": 1, "flow_fraction": 0.9, "height_fraction": 0.90},
				{"room_id": 0, "flow_fraction": 0.7, "height_fraction": 0.90}
			],
			[
				{"room_id": 0, "flow_fraction": 1.1, "height_fraction": 0.92},
				{"room_id": 2, "flow_fraction": 0.65, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.85, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.75, "height_fraction": 0.92},
				{"room_id": 7, "flow_fraction": 0.30, "height_fraction": 0.92}
			],
			0.36,
			0.024
		)
	}


func create_ghanekar_ranch_hvac() -> Dictionary:
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_bedroom_fire := Rect2(0.0, 0.0, 3.8, 3.5)
	var r_hall_near := Rect2(3.8, 0.8, 1.4, 3.6)
	var r_hall_far := Rect2(3.8, 4.4, 1.4, 4.0)
	var r_living := Rect2(5.2, 0.0, 5.5, 4.5)
	var r_kitchen := Rect2(5.2, 4.5, 3.8, 3.3)
	var r_bedroom_2 := Rect2(0.0, 3.5, 3.8, 3.0)
	var r_bedroom_3 := Rect2(0.0, 6.5, 3.8, 3.2)
	var r_primary := Rect2(9.0, 4.5, 3.8, 3.6)
	var r_bath := Rect2(5.2, 7.8, 2.2, 2.0)
	var r_laundry := Rect2(7.4, 7.8, 1.6, 2.0)

	room_rect_m[0] = r_bedroom_fire
	room_rect_m[1] = r_hall_near
	room_rect_m[2] = r_hall_far
	room_rect_m[3] = r_living
	room_rect_m[4] = r_kitchen
	room_rect_m[5] = r_bedroom_2
	room_rect_m[6] = r_bedroom_3
	room_rect_m[7] = r_primary
	room_rect_m[8] = r_bath
	room_rect_m[9] = r_laundry

	rooms_data.append(_make_room(0, "Bedroom4_Fire", "dormitorio", r_bedroom_fire, 2.45, 4200.0, 2600.0))
	rooms_data[0]["fuel_objects"] = [
		{"id": "ghanekar_bed_mattress", "name": "Bed mattress", "kind": "mobiliario_tapizado",
			"position_m": {"x": 0.5, "y": 0.7}, "size_m": {"x": 2.0, "y": 1.4},
			"footprint_m2": 2.8, "exposed_area_m2": 3.5, "elevation_m": 0.45,
			"fuel_energy_MJ": 900.0, "max_hrr_kw": 650.0,
			"ignition_temp_c": 295.0, "ignition_flux_kw_m2": 15.0,
			"smoke_yield_kg_per_MJ": 0.026, "co_yield_kg_per_MJ": 0.00110},
		{"id": "ghanekar_room_contents", "name": "Mixed bedroom contents", "kind": "mobiliario_mixto",
			"position_m": {"x": 2.4, "y": 1.2}, "size_m": {"x": 1.0, "y": 1.8},
			"footprint_m2": 1.8, "exposed_area_m2": 2.6, "elevation_m": 0.45,
			"fuel_energy_MJ": 3300.0, "max_hrr_kw": 1950.0,
			"ignition_temp_c": 310.0, "ignition_flux_kw_m2": 16.0,
			"smoke_yield_kg_per_MJ": 0.018, "co_yield_kg_per_MJ": 0.00085}
	]
	rooms_data.append(_make_room(1, "Hallway_Near", "pasillo", r_hall_near, 2.45, 420.0, 240.0))
	rooms_data.append(_make_room(2, "Hallway_Far", "pasillo", r_hall_far, 2.45, 520.0, 280.0))
	rooms_data.append(_make_room(3, "Living_Dining", "salon", r_living, 2.45, 7200.0, 3200.0))
	rooms_data.append(_make_room(4, "Kitchen", "cocina", r_kitchen, 2.45, 3800.0, 2200.0))
	rooms_data.append(_make_room(5, "Bedroom2", "dormitorio", r_bedroom_2, 2.45, 3200.0, 1800.0))
	rooms_data.append(_make_room(6, "Bedroom3", "dormitorio", r_bedroom_3, 2.45, 3200.0, 1800.0))
	rooms_data.append(_make_room(7, "Bedroom1", "dormitorio", r_primary, 2.45, 3600.0, 1900.0))
	rooms_data.append(_make_room(8, "Bath", "bano", r_bath, 2.45, 300.0, 200.0))
	rooms_data.append(_make_room(9, "Laundry", "almacen", r_laundry, 2.45, 650.0, 400.0))

	openings_data.append(_make_opening(0, 1, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(5, 1, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(6, 2, "door", 0.8, 2.0, 1.0))
	openings_data.append(_make_opening(1, 2, "door", 1.2, 2.1, 1.0))
	openings_data.append(_make_opening(1, 3, "door", 1.1, 2.1, 1.0))
	openings_data.append(_make_opening(2, 4, "door", 1.0, 2.1, 1.0))
	openings_data.append(_make_opening(3, 4, "door", 1.8, 2.2, 1.0))
	openings_data.append(_make_opening(4, 7, "door", 0.8, 2.0, 0.0))
	openings_data.append(_make_opening(4, 8, "door", 0.7, 2.0, 0.0))
	openings_data.append(_make_opening(8, 9, "door", 0.6, 2.0, 0.0))
	openings_data.append(_make_exterior_opening(0, "window", 1.8, 0.7, 1.0, 0.9, "left"))
	openings_data.append(_make_exterior_opening(3, "door", 0.95, 2.0, 1.0, 0.0, "right"))
	openings_data.append(_make_exterior_opening(3, "window", 2.4, 1.2, 0.0, 0.8, "top"))
	openings_data.append(_make_exterior_opening(4, "window", 1.2, 1.0, 0.0, 1.0, "bottom"))
	openings_data.append(_make_exterior_opening(5, "window", 1.4, 1.1, 0.0, 0.9, "left"))
	openings_data.append(_make_exterior_opening(6, "window", 1.4, 1.1, 0.0, 0.9, "left"))
	openings_data.append(_make_exterior_opening(7, "window", 1.6, 1.1, 0.0, 0.9, "right"))

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
		[
			{"room_id": 1, "flow_fraction": 0.85, "height_fraction": 0.90},
			{"room_id": 3, "flow_fraction": 0.75, "height_fraction": 0.90}
		],
		[
			{"room_id": 0, "flow_fraction": 1.0, "height_fraction": 0.92},
			{"room_id": 2, "flow_fraction": 0.55, "height_fraction": 0.92},
			{"room_id": 3, "flow_fraction": 1.0, "height_fraction": 0.92},
			{"room_id": 4, "flow_fraction": 0.80, "height_fraction": 0.92},
			{"room_id": 6, "flow_fraction": 0.75, "height_fraction": 0.92},
			{"room_id": 7, "flow_fraction": 0.25, "height_fraction": 0.92}
		],
		0.34,
		0.022
		)
	}


# ============================================================
# UK BUNGALOW – Anglo-Saxon timber-frame construction
# ============================================================
func create_uk_bungalow() -> Dictionary:
	# -------------------------------------------------------
	# Bungalow anglosajón (UK/US) – ~88 m²
	# Sistema constructivo: timber frame, plasterboard, moqueta
	# en salón y dormitorios, linóleo en cocina y baños.
	# Carga de fuego elevada: moqueta (+130 MJ/m²), papel pintado
	# (+25 MJ/m²), madera estructura (+40 MJ/m²) vs mampostería.
	#
	# Layout (central horizontal corridor):
	#     0     6.0   10.0
	#  0  +------+-----+     ← fachada delantera (calle)
	#     | Lounge|Kitch|     y=0..4.0
	#  4.0+----------+--+
	#     |  Hallway    |     y=4.0..5.0
	#  5.0+----+--+-----+
	#     |MBed|Bt|Bed2 |     y=5.0..9.0
	#  8.0+-+--+  |     |
	#     |En|  |  |     |
	#  9.0+-+--+--+-----+
	# -------------------------------------------------------
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_lounge  := Rect2(0.0, 0.0, 6.0, 4.0)   # 24.0 m²  - Lounge/living-dining
	var r_kitchen := Rect2(6.0, 0.0, 4.0, 4.0)   # 16.0 m²  - Kitchen-diner
	var r_hall    := Rect2(0.0, 4.0, 10.0, 1.0)  # 10.0 m²  - Hallway
	var r_mbed    := Rect2(0.0, 5.0, 4.0, 3.0)   # 12.0 m²  - Master bedroom
	var r_bath    := Rect2(4.0, 5.0, 2.0, 4.0)   #  8.0 m²  - Family bathroom
	var r_bed2    := Rect2(6.0, 5.0, 4.0, 4.0)   # 16.0 m²  - Bedroom 2
	var r_ensuite := Rect2(0.0, 8.0, 2.0, 1.0)   #  2.0 m²  - En-suite (off master bed)

	room_rect_m[0] = r_lounge
	room_rect_m[1] = r_kitchen
	room_rect_m[2] = r_hall
	room_rect_m[3] = r_mbed
	room_rect_m[4] = r_bath
	room_rect_m[5] = r_bed2
	room_rect_m[6] = r_ensuite

	var H: float = 2.40  # Timber-frame ceiling height (UK standard)
	rooms_data.append(_make_room(0, "Lounge",         "salon",      r_lounge,  H, 10500.0, 3500.0))
	rooms_data.append(_make_room(1, "Kitchen-diner",  "cocina",     r_kitchen, H,  3800.0, 2500.0))
	rooms_data.append(_make_room(2, "Hallway",         "pasillo",    r_hall,    H,  1200.0,  400.0))
	rooms_data.append(_make_room(3, "Master bedroom",  "dormitorio", r_mbed,    H,  5200.0, 1500.0))
	rooms_data.append(_make_room(4, "Bathroom",        "bano",       r_bath,    H,   400.0,  200.0))
	rooms_data.append(_make_room(5, "Bedroom 2",       "dormitorio", r_bed2,    H,  6800.0, 2000.0))
	rooms_data.append(_make_room(6, "En-suite",        "bano",       r_ensuite, H,   200.0,  100.0))

	# Interior doors (corridor detection in Visualizer ensures arc swings into room)
	openings_data.append(_make_opening(0, 2, "door", 1.0, 2.0, 1.0))  # lounge → hall
	openings_data.append(_make_opening(1, 2, "door", 0.9, 2.0, 1.0))  # kitchen → hall
	openings_data.append(_make_opening(3, 2, "door", 0.8, 2.0, 1.0))  # mbed → hall
	openings_data.append(_make_opening(4, 2, "door", 0.7, 2.0, 0.0))  # bath → hall
	openings_data.append(_make_opening(5, 2, "door", 0.8, 2.0, 1.0))  # bed2 → hall
	openings_data.append(_make_opening(6, 3, "door", 0.7, 2.0, 0.0))  # ensuite ↔ mbed
	openings_data.append(_make_opening(0, 1, "door", 0.9, 2.0, 1.0))  # lounge ↔ kitchen

	# Exterior: front door on lounge top wall (y=0 = street facade)
	openings_data.append(_make_exterior_opening(0, "door",   0.90, 2.1, 0.0, 0.0, "top"))
	# Windows
	openings_data.append(_make_exterior_opening(0, "window", 2.50, 1.2, 0.0, 0.8, "top"))    # lounge front
	openings_data.append(_make_exterior_opening(1, "window", 1.50, 1.0, 0.0, 0.9, "right"))  # kitchen right
	openings_data.append(_make_exterior_opening(3, "window", 1.40, 1.1, 0.0, 0.9, "left"))   # mbed left
	openings_data.append(_make_exterior_opening(5, "window", 1.40, 1.1, 0.0, 0.9, "right"))  # bed2 right
	openings_data.append(_make_exterior_opening(4, "window", 0.60, 0.6, 0.0, 1.5, "bottom")) # bath rear
	openings_data.append(_make_exterior_opening(6, "window", 0.40, 0.4, 0.0, 1.6, "left"))   # ensuite left

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[{"room_id": 2, "flow_fraction": 1.0, "height_fraction": 0.90}],
			[
				{"room_id": 0, "flow_fraction": 1.2, "height_fraction": 0.92},
				{"room_id": 1, "flow_fraction": 0.8, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.6, "height_fraction": 0.92},
				{"room_id": 5, "flow_fraction": 0.7, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.2, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.1, "height_fraction": 0.92}
			],
			0.28,
			0.018
		)
	}


# ============================================================
# PISO MEDITERRÁNEO – Construcción de obra (ladrillo + yeso)
# ============================================================
func create_piso_mediterraneo() -> Dictionary:
	# -------------------------------------------------------
	# Piso español 3 dormitorios – ~103 m²
	# Sistema constructivo: ladrillo, forjado de hormigón,
	# revoco de yeso, suelo de gres porcelánico.
	# Sin moqueta, sin papel pintado → carga de fuego menor
	# que vivienda anglosajona de estructura de madera.
	# Dormitorio principal con baño en suite.
	#
	# Layout:
	#   Fachada norte (y=0): salón + recibidor + dormitorio principal
	#   Distribuidor vertical (x=5.2..6.7): conecta todas las estancias
	#   Zona sur (y≥4.5): cocina, baños, dormitorios 2 y 3
	# -------------------------------------------------------
	var room_rect_m: Dictionary = {}
	var rooms_data: Array[Dictionary] = []
	var openings_data: Array[Dictionary] = []

	var r_salon    := Rect2(0.0, 0.0, 5.2, 4.5)   # 23.4 m²  - Salón-comedor (fachada norte)
	var r_recibi   := Rect2(5.2, 0.0, 1.5, 2.5)   #  3.75 m² - Recibidor / Entrada
	var r_distrib  := Rect2(5.2, 2.5, 1.5, 7.2)   # 10.8 m²  - Distribuidor / Pasillo
	var r_cocina   := Rect2(0.0, 4.5, 3.5, 3.0)   # 10.5 m²  - Cocina (fachada sur)
	var r_dorm1    := Rect2(6.7, 0.0, 3.9, 3.6)   # 15.2 m²  - Dormitorio principal
	var r_bsuite   := Rect2(6.7, 3.6, 3.9, 1.4)   #  5.5 m²  - Baño suite
	var r_dorm2    := Rect2(6.7, 5.0, 3.9, 2.3)   #  9.0 m²  - Dormitorio 2
	var r_dorm3    := Rect2(6.7, 7.3, 3.9, 2.4)   #  9.4 m²  - Dormitorio 3
	var r_bano     := Rect2(3.5, 4.5, 1.7, 2.3)   #  3.9 m²  - Baño principal
	var r_aseo     := Rect2(3.5, 6.8, 1.7, 1.2)   #  2.0 m²  - Aseo / WC

	room_rect_m[0] = r_salon
	room_rect_m[1] = r_recibi
	room_rect_m[2] = r_distrib
	room_rect_m[3] = r_cocina
	room_rect_m[4] = r_dorm1
	room_rect_m[5] = r_bsuite
	room_rect_m[6] = r_dorm2
	room_rect_m[7] = r_dorm3
	room_rect_m[8] = r_bano
	room_rect_m[9] = r_aseo

	var H: float = 2.60  # Altura libre típica piso español (ladrillo)
	# Cargas de fuego: suelo cerámico, yeso pintado, sin moqueta ni papel pintado
	rooms_data.append(_make_room(0, "Salon-comedor",        "salon",      r_salon,   H, 7000.0, 3400.0))
	rooms_data.append(_make_room(1, "Recibidor",            "pasillo",    r_recibi,  H,  280.0,  180.0))
	rooms_data.append(_make_room(2, "Distribuidor",         "pasillo",    r_distrib, H,  480.0,  280.0))
	rooms_data.append(_make_room(3, "Cocina",               "cocina",     r_cocina,  H, 2900.0, 2100.0))
	rooms_data.append(_make_room(4, "Dormitorio principal", "dormitorio", r_dorm1,   H, 3500.0, 2000.0))
	rooms_data.append(_make_room(5, "Bano suite",           "bano",       r_bsuite,  H,  180.0,  120.0))
	rooms_data.append(_make_room(6, "Dormitorio 2",         "dormitorio", r_dorm2,   H, 2100.0, 1500.0))
	rooms_data.append(_make_room(7, "Dormitorio 3",         "dormitorio", r_dorm3,   H, 2200.0, 1500.0))
	rooms_data.append(_make_room(8, "Bano",                 "bano",       r_bano,    H,  250.0,  180.0))
	rooms_data.append(_make_room(9, "Aseo",                 "bano",       r_aseo,    H,  150.0,  100.0))

	# Puertas interiores
	openings_data.append(_make_opening(1, 0, "door", 1.0, 2.1, 1.0))   # recibidor → salon
	openings_data.append(_make_opening(1, 2, "door", 0.9, 2.1, 1.0))   # recibidor ↔ distribuidor
	openings_data.append(_make_opening(0, 2, "door", 0.9, 2.05, 1.0))  # salon → distribuidor
	openings_data.append(_make_opening(0, 3, "door", 0.8, 2.0, 1.0))   # salon → cocina
	openings_data.append(_make_opening(4, 2, "door", 0.8, 2.0, 1.0))   # dorm1 → distribuidor
	openings_data.append(_make_opening(4, 5, "door", 0.7, 2.0, 0.0))   # dorm1 → bano suite
	openings_data.append(_make_opening(6, 2, "door", 0.8, 2.0, 1.0))   # dorm2 → distribuidor
	openings_data.append(_make_opening(7, 2, "door", 0.8, 2.0, 1.0))   # dorm3 → distribuidor
	openings_data.append(_make_opening(8, 2, "door", 0.7, 2.0, 0.0))   # bano → distribuidor
	openings_data.append(_make_opening(9, 2, "door", 0.7, 2.0, 0.0))   # aseo → distribuidor

	# Puerta de entrada principal (recibidor, fachada norte y=0)
	openings_data.append(_make_exterior_opening(1, "door",   0.90, 2.1, 0.0, 0.0,  "top"))
	# Ventanas
	openings_data.append(_make_exterior_opening(0, "window", 2.50, 1.2, 0.0, 0.85, "top"))    # salon fachada norte
	openings_data.append(_make_exterior_opening(3, "window", 1.20, 1.0, 0.0, 1.00, "bottom")) # cocina fachada sur
	openings_data.append(_make_exterior_opening(4, "window", 1.40, 1.1, 0.0, 0.90, "right"))  # dorm1 lateral
	openings_data.append(_make_exterior_opening(5, "window", 0.40, 0.4, 0.0, 1.50, "right"))  # bano suite
	openings_data.append(_make_exterior_opening(6, "window", 1.40, 1.1, 0.0, 0.90, "right"))  # dorm2
	openings_data.append(_make_exterior_opening(7, "window", 1.40, 1.1, 0.0, 0.90, "right"))  # dorm3
	openings_data.append(_make_exterior_opening(9, "window", 0.50, 0.5, 0.0, 1.50, "bottom")) # aseo

	return {
		"room_rect_m": room_rect_m,
		"rooms_data": rooms_data,
		"openings_data": openings_data,
		"hvac_data": _make_residential_hvac_data(
			[{"room_id": 2, "flow_fraction": 1.0, "height_fraction": 0.90}],
			[
				{"room_id": 0, "flow_fraction": 1.2, "height_fraction": 0.92},
				{"room_id": 3, "flow_fraction": 0.6, "height_fraction": 0.92},
				{"room_id": 4, "flow_fraction": 0.8, "height_fraction": 0.92},
				{"room_id": 6, "flow_fraction": 0.7, "height_fraction": 0.92},
				{"room_id": 7, "flow_fraction": 0.7, "height_fraction": 0.92},
				{"room_id": 8, "flow_fraction": 0.2, "height_fraction": 0.92},
				{"room_id": 9, "flow_fraction": 0.2, "height_fraction": 0.92}
			],
			0.30,
			0.018
		)
	}


func _make_room(
	id: int,
	room_name: String,
	kind_name: String,
	rect: Rect2,
	height_m: float,
	fuel_energy_MJ: float,
	max_hrr_kw: float
) -> Dictionary:
	return {
		"id": id,
		"name": room_name,
		"kind": kind_name,
		"rect": rect,
		"height_m": height_m,
		"fuel_energy_MJ": fuel_energy_MJ,
		"max_hrr_kw": max_hrr_kw
	}


func _make_opening(a: int, b: int, type_name: String, width_m: float, height_m: float, open_fraction: float) -> Dictionary:
	return {
		"a": a,
		"b": b,
		"type": type_name,
		"width_m": width_m,
		"height_m": height_m,
		"open_fraction": open_fraction
	}


func _make_exterior_opening(
	room_id: int,
	type_name: String,
	width_m: float,
	height_m: float,
	open_fraction: float,
	sill_m: float,
	wall: String
) -> Dictionary:
	var opening: Dictionary = _make_opening(room_id, -1, type_name, width_m, height_m, open_fraction)
	opening["sill_m"] = sill_m
	opening["wall"] = wall
	return opening


func _make_residential_hvac_data(
	returns: Array,
	supplies: Array,
	fan_flow_m3_s: float,
	off_passive_flow_m3_s: float
) -> Dictionary:
	return {
		"exists": false,
		"on": false,
		"fan_flow_m3_s": fan_flow_m3_s,
		"off_passive_flow_m3_s": off_passive_flow_m3_s,
		"outside_air_fraction": 0.08,
		"smoke_filter_penetration": 0.72,
		"species_filter_penetration": 0.95,
		"condition_supply_air": false,
		"supply_temp_c": 20.0,
		"conditioning_strength": 0.45,
		"returns": returns,
		"supplies": supplies
	}
