extends RefCounted
class_name ObjectLibrary

## El catalogo de muebles del editor: lo que se puede soltar en un plano.
##
## Antes esto era un `match` de 250 lineas con catorce ramas, una por mueble, y
## por eso el catalogo cubria **14 de los 38 arquetipos que el visor sabe
## dibujar**: no se podia amueblar un bano ni una cocina, ni poner una silla,
## una lampara, una planta o una mesilla (hallazgo D-2). Anadir uno costaba
## veinte lineas, asi que no se anadia.
##
## Ahora es una tabla. Cada fila trae lo que hace falta para las dos cosas que
## un objeto es a la vez:
##
##  - **carga de fuego** para el motor -energia, HRR maximo, temperatura e
##    irradiancia de ignicion, y los rendimientos de humo y CO-,
##  - **un mueble** para la vista -su medida en planta y su arquetipo-.
##
## Sobre las cifras de fuego, con toda la honestidad: **son estimaciones de
## ingenieria, no medidas de laboratorio**. Las catorce que ya existian se
## conservan intactas, y las veinticuatro nuevas se han escalado a partir de
## ellas por clase de material y por masa combustible -tapizado, madera, colchon,
## electrodomestico, sanitario, plastico-, manteniendo las relaciones que ya
## habia: un tapizado prende antes (~300 C) y da mas humo (0,012 kg/MJ) que la
## madera (~330 C y 0,008), un plastico da el triple de humo y CO, y un sanitario
## de porcelana practicamente no arde. El dia que haya ensayos, esta tabla es el
## sitio donde meterlos.
##
## Cada fila lleva ademas su `visual_archetype` escrito. No se deja que lo
## adivine el clasificador por el nombre: la leccion del `bathroom_cabinet` fue
## que **un modelo que no alcanza nadie es indistinguible de uno que no existe**,
## y aqui el editor sabe exactamente lo que esta poniendo.

## Rendimiento de O2 por MJ. Es el mismo para todo: sale de la quimica de la
## combustion, no del mueble.
const O2_KG_PER_MJ: float = 0.076

## El catalogo, en el orden en el que se enseña: por estancia, que es como se
## amuebla una casa. `x`/`y` son la huella en planta; `alto` es la elevacion del
## foco de fuego sobre el suelo, no la altura del mueble -esa la pone
## `FurnitureDimensions`, que es quien manda en la vista-.
const CATALOG: Dictionary = {
	# ─────────────────────────── Salon ───────────────────────────
	"sofa": {"nombre": "Sofá", "arquetipo": "sofa", "x": 2.00, "y": 0.90,
		"huella": 1.80, "expuesta": 2.50, "alto": 0.00,
		"MJ": 500.0, "kW": 1000.0, "Tign": 320.0, "flujo": 18.0, "humo": 0.012, "co": 0.0004},
	"lounge_sofa_long": {"nombre": "Sofá rinconera", "arquetipo": "lounge_sofa_long", "x": 2.80, "y": 1.60,
		"huella": 3.30, "expuesta": 4.20, "alto": 0.35,
		"MJ": 750.0, "kW": 1400.0, "Tign": 320.0, "flujo": 18.0, "humo": 0.012, "co": 0.0004},
	"armchair": {"nombre": "Sillón", "arquetipo": "armchair", "x": 0.85, "y": 0.85,
		"huella": 0.72, "expuesta": 1.40, "alto": 0.35,
		"MJ": 360.0, "kW": 650.0, "Tign": 310.0, "flujo": 16.0, "humo": 0.012, "co": 0.0004},
	"coffee_table": {"nombre": "Mesa de centro", "arquetipo": "coffee_table", "x": 1.05, "y": 0.58,
		"huella": 0.61, "expuesta": 1.00, "alto": 0.40,
		"MJ": 140.0, "kW": 180.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.008, "co": 0.00025},
	"tv_stand": {"nombre": "Mueble de TV", "arquetipo": "tv_stand", "x": 1.50, "y": 0.35,
		"huella": 0.53, "expuesta": 1.10, "alto": 0.35,
		"MJ": 360.0, "kW": 240.0, "Tign": 305.0, "flujo": 16.0, "humo": 0.008, "co": 0.00025},
	"bookcase": {"nombre": "Librería", "arquetipo": "bookcase", "x": 0.40, "y": 1.35,
		"huella": 0.54, "expuesta": 1.80, "alto": 0.00,
		"MJ": 650.0, "kW": 320.0, "Tign": 300.0, "flujo": 16.0, "humo": 0.008, "co": 0.00025},
	"rug": {"nombre": "Alfombra", "arquetipo": "rug", "x": 1.80, "y": 1.05,
		"huella": 1.89, "expuesta": 1.89, "alto": 0.03,
		"MJ": 220.0, "kW": 150.0, "Tign": 275.0, "flujo": 13.0, "humo": 0.015, "co": 0.0005},
	"curtain": {"nombre": "Cortina", "arquetipo": "curtain", "x": 1.20, "y": 0.12,
		"huella": 0.15, "expuesta": 2.00, "alto": 1.40,
		"MJ": 120.0, "kW": 350.0, "Tign": 270.0, "flujo": 12.0, "humo": 0.016, "co": 0.0005},
	"lamp_floor": {"nombre": "Lámpara de pie", "arquetipo": "lamp_floor", "x": 0.35, "y": 0.35,
		"huella": 0.12, "expuesta": 0.40, "alto": 0.80,
		"MJ": 25.0, "kW": 60.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.012, "co": 0.0004},
	"plant": {"nombre": "Planta", "arquetipo": "plant", "x": 0.50, "y": 0.50,
		"huella": 0.25, "expuesta": 0.70, "alto": 0.30,
		"MJ": 20.0, "kW": 50.0, "Tign": 300.0, "flujo": 14.0, "humo": 0.010, "co": 0.0004},

	# ─────────────────────────── Comedor ─────────────────────────
	"table": {"nombre": "Mesa", "arquetipo": "table", "x": 1.20, "y": 0.75,
		"huella": 0.90, "expuesta": 1.60, "alto": 0.70,
		"MJ": 180.0, "kW": 250.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.008, "co": 0.00025},
	"chair": {"nombre": "Silla", "arquetipo": "chair", "x": 0.45, "y": 0.50,
		"huella": 0.23, "expuesta": 0.70, "alto": 0.45,
		"MJ": 60.0, "kW": 120.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.008, "co": 0.00025},
	"bench": {"nombre": "Banco", "arquetipo": "bench", "x": 1.20, "y": 0.40,
		"huella": 0.48, "expuesta": 0.90, "alto": 0.40,
		"MJ": 120.0, "kW": 150.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.008, "co": 0.00025},

	# ─────────────────────────── Dormitorio ──────────────────────
	"bed": {"nombre": "Cama de matrimonio", "arquetipo": "bed", "x": 2.00, "y": 1.40,
		"huella": 2.80, "expuesta": 3.50, "alto": 0.45,
		"MJ": 900.0, "kW": 1200.0, "Tign": 295.0, "flujo": 15.0, "humo": 0.013, "co": 0.0004},
	"bed_single": {"nombre": "Cama individual", "arquetipo": "bed_single", "x": 1.90, "y": 0.90,
		"huella": 1.71, "expuesta": 2.30, "alto": 0.45,
		"MJ": 550.0, "kW": 900.0, "Tign": 295.0, "flujo": 15.0, "humo": 0.013, "co": 0.0004},
	"bed_bunk": {"nombre": "Litera", "arquetipo": "bed_bunk", "x": 1.90, "y": 0.90,
		"huella": 1.71, "expuesta": 4.10, "alto": 0.45,
		"MJ": 950.0, "kW": 1300.0, "Tign": 295.0, "flujo": 15.0, "humo": 0.013, "co": 0.0004},
	"side_table": {"nombre": "Mesilla", "arquetipo": "side_table", "x": 0.45, "y": 0.40,
		"huella": 0.18, "expuesta": 0.50, "alto": 0.50,
		"MJ": 45.0, "kW": 80.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.008, "co": 0.00025},
	"lamp_table": {"nombre": "Lámpara de mesa", "arquetipo": "lamp_table", "x": 0.25, "y": 0.25,
		"huella": 0.06, "expuesta": 0.20, "alto": 0.60,
		"MJ": 12.0, "kW": 40.0, "Tign": 330.0, "flujo": 18.0, "humo": 0.012, "co": 0.0004},
	"wardrobe": {"nombre": "Armario", "arquetipo": "wardrobe", "x": 0.45, "y": 1.60,
		"huella": 0.72, "expuesta": 2.40, "alto": 0.00,
		"MJ": 800.0, "kW": 700.0, "Tign": 300.0, "flujo": 16.0, "humo": 0.008, "co": 0.00025},
	"dresser": {"nombre": "Cómoda", "arquetipo": "dresser", "x": 0.90, "y": 0.45,
		"huella": 0.41, "expuesta": 1.00, "alto": 0.45,
		"MJ": 420.0, "kW": 360.0, "Tign": 305.0, "flujo": 16.0, "humo": 0.009, "co": 0.00025},
	"desk": {"nombre": "Escritorio", "arquetipo": "desk", "x": 1.15, "y": 0.55,
		"huella": 0.63, "expuesta": 1.20, "alto": 0.72,
		"MJ": 260.0, "kW": 260.0, "Tign": 320.0, "flujo": 17.0, "humo": 0.009, "co": 0.00025},
	"chair_desk": {"nombre": "Silla de escritorio", "arquetipo": "chair_desk", "x": 0.60, "y": 0.60,
		"huella": 0.36, "expuesta": 0.90, "alto": 0.45,
		"MJ": 120.0, "kW": 300.0, "Tign": 300.0, "flujo": 16.0, "humo": 0.020, "co": 0.0007},

	# ─────────────────────────── Cocina ──────────────────────────
	"kitchen_unit": {"nombre": "Encimera", "arquetipo": "kitchen_unit", "x": 2.00, "y": 0.60,
		"huella": 1.20, "expuesta": 2.40, "alto": 0.80,
		"MJ": 1000.0, "kW": 900.0, "Tign": 285.0, "flujo": 14.0, "humo": 0.009, "co": 0.00028},
	"kitchen_fridge": {"nombre": "Frigorífico", "arquetipo": "kitchen_fridge", "x": 0.65, "y": 0.60,
		"huella": 0.39, "expuesta": 2.20, "alto": 0.90,
		"MJ": 250.0, "kW": 350.0, "Tign": 350.0, "flujo": 22.0, "humo": 0.030, "co": 0.0012},
	"kitchen_stove": {"nombre": "Cocina", "arquetipo": "kitchen_stove", "x": 0.60, "y": 0.60,
		"huella": 0.36, "expuesta": 1.00, "alto": 0.85,
		"MJ": 60.0, "kW": 150.0, "Tign": 400.0, "flujo": 25.0, "humo": 0.010, "co": 0.0004},
	"kitchen_sink": {"nombre": "Fregadero", "arquetipo": "kitchen_sink", "x": 0.60, "y": 0.60,
		"huella": 0.36, "expuesta": 0.80, "alto": 0.85,
		"MJ": 30.0, "kW": 60.0, "Tign": 400.0, "flujo": 25.0, "humo": 0.008, "co": 0.0003},
	"washer": {"nombre": "Lavadora", "arquetipo": "washer", "x": 0.60, "y": 0.60,
		"huella": 0.36, "expuesta": 1.20, "alto": 0.40,
		"MJ": 180.0, "kW": 250.0, "Tign": 360.0, "flujo": 22.0, "humo": 0.022, "co": 0.0009},
	"dryer": {"nombre": "Secadora", "arquetipo": "dryer", "x": 0.60, "y": 0.60,
		"huella": 0.36, "expuesta": 1.20, "alto": 0.40,
		"MJ": 180.0, "kW": 250.0, "Tign": 360.0, "flujo": 22.0, "humo": 0.022, "co": 0.0009},

	# ─────────────────────────── Bano ────────────────────────────
	"bathtub": {"nombre": "Bañera", "arquetipo": "bathtub", "x": 1.70, "y": 0.75,
		"huella": 1.28, "expuesta": 2.00, "alto": 0.30,
		"MJ": 120.0, "kW": 250.0, "Tign": 350.0, "flujo": 20.0, "humo": 0.028, "co": 0.0010},
	"shower": {"nombre": "Ducha", "arquetipo": "shower", "x": 0.90, "y": 0.90,
		"huella": 0.81, "expuesta": 2.60, "alto": 1.00,
		"MJ": 90.0, "kW": 200.0, "Tign": 350.0, "flujo": 20.0, "humo": 0.026, "co": 0.0010},
	"toilet": {"nombre": "Inodoro", "arquetipo": "toilet", "x": 0.70, "y": 0.38,
		"huella": 0.27, "expuesta": 0.60, "alto": 0.30,
		"MJ": 15.0, "kW": 40.0, "Tign": 420.0, "flujo": 28.0, "humo": 0.006, "co": 0.0002},
	"sink": {"nombre": "Lavabo", "arquetipo": "sink", "x": 0.60, "y": 0.45,
		"huella": 0.27, "expuesta": 0.60, "alto": 0.80,
		"MJ": 15.0, "kW": 40.0, "Tign": 420.0, "flujo": 28.0, "humo": 0.006, "co": 0.0002},
	"bathroom_cabinet": {"nombre": "Mueble de baño", "arquetipo": "bathroom_cabinet", "x": 0.60, "y": 0.20,
		"huella": 0.12, "expuesta": 0.70, "alto": 0.85,
		"MJ": 90.0, "kW": 120.0, "Tign": 320.0, "flujo": 17.0, "humo": 0.009, "co": 0.0003},

	# ─────────────────────────── Trastero y varios ───────────────
	"storage": {"nombre": "Estantería de trastero", "arquetipo": "storage", "x": 0.90, "y": 0.40,
		"huella": 0.36, "expuesta": 1.60, "alto": 0.00,
		"MJ": 500.0, "kW": 400.0, "Tign": 305.0, "flujo": 16.0, "humo": 0.010, "co": 0.0003},
	"clutter": {"nombre": "Cajas amontonadas", "arquetipo": "clutter", "x": 0.80, "y": 0.60,
		"huella": 0.48, "expuesta": 1.40, "alto": 0.30,
		"MJ": 300.0, "kW": 450.0, "Tign": 300.0, "flujo": 15.0, "humo": 0.014, "co": 0.0005},
	"textile_pile": {"nombre": "Montón de ropa", "arquetipo": "textile_pile", "x": 0.80, "y": 0.60,
		"huella": 0.48, "expuesta": 1.10, "alto": 0.15,
		"MJ": 200.0, "kW": 300.0, "Tign": 270.0, "flujo": 12.0, "humo": 0.016, "co": 0.0006},
	"plastic_bin": {"nombre": "Cubo de plástico", "arquetipo": "containers", "x": 0.40, "y": 0.40,
		"huella": 0.16, "expuesta": 0.45, "alto": 0.25,
		"MJ": 80.0, "kW": 100.0, "Tign": 350.0, "flujo": 20.0, "humo": 0.025, "co": 0.0009},
	"pool": {"nombre": "Derrame inflamable", "arquetipo": "pool", "x": 0.80, "y": 0.60,
		"huella": 0.48, "expuesta": 0.48, "alto": 0.02,
		"MJ": 350.0, "kW": 900.0, "Tign": 250.0, "flujo": 10.0, "humo": 0.035, "co": 0.0015},
}


static func get_object_kinds() -> Array[String]:
	var out: Array[String] = []
	for kind in CATALOG.keys():
		out.append(String(kind))
	return out


## El nombre que se enseña en el catálogo. El `kind` es el identificador interno
## y va en inglés porque lo comparten los datos guardados y el motor; lo que lee
## una persona no tiene por qué ser eso.
static func display_name(kind: String) -> String:
	var fila: Dictionary = CATALOG.get(kind, {})
	return String(fila.get("nombre", kind))


## Lo que ocupa en planta, sin fabricar el objeto entero. Lo usa el arrastre para
## enseñar la huella de verdad mientras la llevas al plano.
static func size_m(kind: String) -> Vector2:
	var fila: Dictionary = CATALOG.get(kind, {})
	return Vector2(float(fila.get("x", 1.0)), float(fila.get("y", 1.0)))


## El arquetipo visual de una pieza, sin fabricarla. Lo usa la vista previa del
## catalogo, que ensena el modelo antes de colocar nada.
static func visual_archetype(kind: String) -> String:
	var fila: Dictionary = CATALOG.get(kind, {})
	return String(fila.get("arquetipo", ""))


## A que altura del suelo arranca la pieza. OJO: la columna `alto` de la tabla
## es la ELEVACION -0 en un sofa, 0,95 en un mueble de bano colgado-, no lo que
## mide de arriba abajo. La altura de verdad la sabe `FurnitureDimensions`, que
## es quien dibuja.
static func elevation_m(kind: String) -> float:
	var fila: Dictionary = CATALOG.get(kind, {})
	return float(fila.get("alto", 0.0))


static func create_object(kind: String, id: String, room_id: int, position_m: Vector2) -> Dictionary:
	var base: Dictionary = _base_object(id, room_id, position_m)
	var fila: Dictionary = CATALOG.get(kind, {})
	if fila.is_empty():
		return base
	base.merge({
		"name": String(fila["nombre"]),
		"kind": kind,
		# El arquetipo va escrito, no adivinado: es lo que ata esta pieza a su
		# modelo y a sus medidas reales en la vista.
		"visual_archetype": String(fila["arquetipo"]),
		"size_m": {"x": float(fila["x"]), "y": float(fila["y"])},
		"footprint_m2": float(fila["huella"]),
		"exposed_area_m2": float(fila["expuesta"]),
		"elevation_m": float(fila["alto"]),
		"fuel_energy_MJ": float(fila["MJ"]),
		"remaining_fuel_MJ": float(fila["MJ"]),
		"max_hrr_kw": float(fila["kW"]),
		"ignition_temp_c": float(fila["Tign"]),
		"ignition_flux_kw_m2": float(fila["flujo"]),
		"smoke_yield_kg_per_MJ": float(fila["humo"]),
		"co_yield_kg_per_MJ": float(fila["co"]),
		"o2_consumption_kg_per_MJ": O2_KG_PER_MJ,
	}, true)
	return base


static func _base_object(id: String, room_id: int, position_m: Vector2) -> Dictionary:
	return {
		"id": id,
		"name": "Generic combustible",
		"kind": "generic",
		"room_id": room_id,
		"position_m": {"x": position_m.x, "y": position_m.y},
		"size_m": {"x": 1.0, "y": 1.0},
		"rotation_deg": 0.0,
		"footprint_m2": 1.0,
		"exposed_area_m2": 1.0,
		"elevation_m": 0.0,
		"fuel_energy_MJ": 100.0,
		"remaining_fuel_MJ": 100.0,
		"max_hrr_kw": 300.0,
		"ignition_temp_c": 330.0,
		"ignition_flux_kw_m2": 18.0,
		"smoke_yield_kg_per_MJ": 0.00375,
		"co_yield_kg_per_MJ": 0.00025,
		"o2_consumption_kg_per_MJ": O2_KG_PER_MJ,
		"is_primary_ignition_source": false
	}
