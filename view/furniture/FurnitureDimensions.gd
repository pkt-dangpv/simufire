extends RefCounted

## Dimensiones REALES del mobiliario, en metros.
##
## Por que existe este fichero. Un objeto del escenario declara `size_m`, y ese
## numero lo eligio el modelo de fuego: es la huella que arde, emparejada con
## `footprint_m2` y `exposed_area_m2`. No es el tamano del mueble. Usarlo como
## tamano visual es lo que producia camas de 1,45 m de largo y encimeras
## convertidas en un cubo de 1,46 m: cosas que al lado de un jugador de 1,80 m
## se leen como una casa de munecas.
##
## Aqui viven las medidas de verdad, las que tiene el mueble en una vivienda.
## El escenario sigue mandando en DOS cosas -donde esta la pieza y cuanto mide
## en su dimension libre, cuando la tiene- pero no puede encoger una cama por
## debajo de lo que mide una cama.
##
## Cada arquetipo declara:
##   long_m   dimension dominante en horizontal
##   deep_m   la otra horizontal
##   high_m   altura, que es la que juzga la camara
##   long_min_m / long_max_m  recorrido admisible de la dimension libre; si
##                            valen 0 la pieza tiene una talla fija y el hueco
##                            del escenario no la mueve
##   free_plan  la pieza no tiene talla propia en planta -alfombras, derrames,
##              montones- y toma la del escenario tal cual
##   wall       la pieza se apoya de espaldas a un paramento
##   floor      la pieza es rasante y otras cosas pueden ponerse encima
##
## Las medidas salen de mobiliario domestico corriente: cama de matrimonio
## 1,50 x 2,00; individual 0,90 x 1,90; armario de 0,60 de fondo y 2,05 de alto;
## encimera de cocina a 0,90 de alto y 0,60 de fondo; inodoro 0,38 x 0,70.

## Un arquetipo que no este en la tabla no tiene medidas propias que imponer:
## se queda con lo que diga el escenario. Es el unico caso en que `free_plan`
## vale por defecto -y tiene que estar SEPARADO de los valores de relleno de
## abajo, porque si se fusiona sobre cada ficha todas heredan free_plan y la
## tabla entera deja de aplicarse-.
const UNKNOWN_SPEC: Dictionary = {
	"long_m": 0.60, "deep_m": 0.50, "high_m": 0.45,
	"long_min_m": 0.0, "long_max_m": 0.0,
	"free_plan": true, "wall": false, "floor": false,
}

## Relleno de las claves que una ficha no declara.
const DEFAULT_SPEC: Dictionary = {
	"long_m": 0.60, "deep_m": 0.50, "high_m": 0.45,
	"long_min_m": 0.0, "long_max_m": 0.0,
	"free_plan": false, "wall": false, "floor": false,
}

const SPECS: Dictionary = {
	# --- Descanso ---
	"bed": {"long_m": 2.00, "deep_m": 1.50, "high_m": 0.55, "wall": true},
	"bed_single": {"long_m": 1.90, "deep_m": 0.90, "high_m": 0.55, "wall": true},
	"bed_bunk": {"long_m": 1.90, "deep_m": 0.90, "high_m": 1.65, "wall": true},

	# --- Asientos ---
	"sofa": {"long_m": 2.10, "deep_m": 0.90, "high_m": 0.85,
		"long_min_m": 1.60, "long_max_m": 3.20, "wall": true},
	"lounge_sofa_long": {"long_m": 2.80, "deep_m": 1.60, "high_m": 0.85,
		"long_min_m": 2.20, "long_max_m": 3.60, "wall": true},
	"armchair": {"long_m": 0.85, "deep_m": 0.85, "high_m": 0.95},
	"bench": {"long_m": 1.20, "deep_m": 0.40, "high_m": 0.45,
		"long_min_m": 0.80, "long_max_m": 1.80, "wall": true},
	"chair": {"long_m": 0.45, "deep_m": 0.50, "high_m": 0.90},
	"chair_desk": {"long_m": 0.60, "deep_m": 0.60, "high_m": 1.00},

	# --- Mesas ---
	"table": {"long_m": 1.40, "deep_m": 0.85, "high_m": 0.75,
		"long_min_m": 1.00, "long_max_m": 2.20},
	"coffee_table": {"long_m": 1.10, "deep_m": 0.60, "high_m": 0.42,
		"long_min_m": 0.80, "long_max_m": 1.40},
	"desk": {"long_m": 1.20, "deep_m": 0.60, "high_m": 0.75,
		"long_min_m": 0.90, "long_max_m": 1.80, "wall": true},
	"side_table": {"long_m": 0.45, "deep_m": 0.40, "high_m": 0.55},

	# --- Almacenaje ---
	"wardrobe": {"long_m": 1.20, "deep_m": 0.60, "high_m": 2.05,
		"long_min_m": 0.80, "long_max_m": 2.40, "wall": true},
	"dresser": {"long_m": 1.00, "deep_m": 0.45, "high_m": 0.80,
		"long_min_m": 0.70, "long_max_m": 1.60, "wall": true},
	"bookcase": {"long_m": 0.80, "deep_m": 0.30, "high_m": 1.80,
		"long_min_m": 0.60, "long_max_m": 1.80, "wall": true},
	"storage": {"long_m": 0.90, "deep_m": 0.40, "high_m": 1.60,
		"long_min_m": 0.60, "long_max_m": 1.60, "wall": true},
	"tv_stand": {"long_m": 1.40, "deep_m": 0.40, "high_m": 0.50,
		"long_min_m": 1.00, "long_max_m": 2.00, "wall": true},

	# --- Cocina ---
	# La encimera es el unico mueble que se REPITE: un frente de cocina son
	# modulos de 0,60 puestos en fila, no un mueble estirado.
	"kitchen_unit": {"long_m": 1.80, "deep_m": 0.60, "high_m": 0.90,
		"long_min_m": 0.60, "long_max_m": 4.20, "wall": true, "tiled": true},
	"kitchen_fridge": {"long_m": 0.65, "deep_m": 0.60, "high_m": 1.80, "wall": true},
	"kitchen_stove": {"long_m": 0.60, "deep_m": 0.60, "high_m": 0.90, "wall": true},
	"kitchen_sink": {"long_m": 0.60, "deep_m": 0.60, "high_m": 0.90, "wall": true},
	"washer": {"long_m": 0.60, "deep_m": 0.60, "high_m": 0.85, "wall": true},
	"dryer": {"long_m": 0.60, "deep_m": 0.60, "high_m": 0.85, "wall": true},

	# --- Bano ---
	"bathtub": {"long_m": 1.70, "deep_m": 0.75, "high_m": 0.60, "wall": true},
	"shower": {"long_m": 0.90, "deep_m": 0.90, "high_m": 2.00, "wall": true},
	"toilet": {"long_m": 0.70, "deep_m": 0.38, "high_m": 0.80, "wall": true},
	"sink": {"long_m": 0.60, "deep_m": 0.45, "high_m": 0.90, "wall": true},
	"bathroom_cabinet": {"long_m": 0.60, "deep_m": 0.20, "high_m": 0.70, "wall": true},

	# --- Iluminacion y decoracion ---
	"lamp_floor": {"long_m": 0.35, "deep_m": 0.35, "high_m": 1.60},
	"lamp_table": {"long_m": 0.25, "deep_m": 0.25, "high_m": 0.45},
	"plant": {"long_m": 0.50, "deep_m": 0.50, "high_m": 1.10},

	# --- Cosas sin talla propia: el escenario manda en planta ---
	"curtain": {"long_m": 1.40, "deep_m": 0.12, "high_m": 2.10,
		"long_min_m": 0.80, "long_max_m": 3.00, "wall": true, "exact": true},
	"rug": {"high_m": 0.02, "free_plan": true, "floor": true},
	"pool": {"high_m": 0.03, "free_plan": true, "floor": true},
	"textile_pile": {"high_m": 0.30, "free_plan": true},
	"containers": {"high_m": 0.55, "free_plan": true},
	"clutter": {"high_m": 0.45, "free_plan": true},
}

## Una pieza libre en planta no puede ser mas pequena que esto ni mas grande
## que el hueco que le da el escenario.
const MIN_FREE_PLAN_M: float = 0.20


static func spec_for(archetype: String) -> Dictionary:
	if not SPECS.has(archetype):
		return UNKNOWN_SPEC.duplicate()
	var result: Dictionary = DEFAULT_SPEC.duplicate()
	result.merge(Dictionary(SPECS[archetype]), true)
	return result


## Caja real de la pieza en su marco LOCAL: x e z en planta, y la altura.
##
## El hueco del escenario decide dos cosas y solo dos: que eje es el largo
## -para respetar como oriento la pieza quien monto el escenario- y, si el
## arquetipo tiene dimension libre, cuanto mide dentro de su recorrido.
static func target_size_m(archetype: String, slot_m: Vector2) -> Vector3:
	var spec: Dictionary = spec_for(archetype)
	var high_m: float = float(spec.get("high_m", 0.45))
	var slot_long: float = maxf(slot_m.x, slot_m.y)
	var slot_short: float = minf(slot_m.x, slot_m.y)
	var x_is_long: bool = slot_m.x >= slot_m.y

	if bool(spec.get("free_plan", false)):
		var free_long: float = maxf(MIN_FREE_PLAN_M, slot_long)
		var free_short: float = maxf(MIN_FREE_PLAN_M, slot_short)
		if x_is_long:
			return Vector3(free_long, high_m, free_short)
		return Vector3(free_short, high_m, free_long)

	var long_m: float = float(spec.get("long_m", 0.60))
	var long_min: float = float(spec.get("long_min_m", 0.0))
	var long_max: float = float(spec.get("long_max_m", 0.0))
	if long_min > 0.0 and long_max >= long_min and slot_long > 0.0:
		long_m = clampf(slot_long, long_min, long_max)
	var deep_m: float = float(spec.get("deep_m", 0.50))

	if x_is_long:
		return Vector3(long_m, high_m, deep_m)
	return Vector3(deep_m, high_m, long_m)


static func height_m(archetype: String) -> float:
	return float(spec_for(archetype).get("high_m", 0.45))


## Piezas que en una vivienda van de espaldas a un paramento.
static func is_wall_hugging(archetype: String) -> bool:
	return bool(spec_for(archetype).get("wall", false))


## Piezas rasantes: otra cosa puede estar encima sin que sea un error.
static func is_floor_level(archetype: String) -> bool:
	return bool(spec_for(archetype).get("floor", false))


## Piezas que se construyen repitiendo un modulo en vez de estirando uno.
static func is_tiled(archetype: String) -> bool:
	return bool(spec_for(archetype).get("tiled", false))


## Piezas sin forma rigida -alfombras, derrames, montones, cortinas-. No hay
## proporciones que conservar, asi que se llevan a su caja sin el limite de
## deformacion. Con el puesto, una alfombra de 2,30 x 1,35 salia de 3,09 x 1,81:
## el grosor de una lamina es tan pequeno que su factor de escala dominaba el
## calculo y arrastraba a los otros dos ejes.
static func fits_exactly(archetype: String) -> bool:
	var spec: Dictionary = spec_for(archetype)
	return bool(spec.get("exact", false)) or bool(spec.get("free_plan", false))
