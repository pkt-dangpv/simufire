extends RefCounted

## F2.2-R3: convierte una abertura EXTERIOR cerrada en un elemento de fuga de
## envolvente para la red autoritativa de presion.
##
## No resuelve presion, no calcula caudal, no toca salas, no toca
## `open_fraction`, no aplica transporte y no conoce el editor ni la vista.
## Describe geometria, area y procedencia: la ley la integra el solver.
##
## NO ES LA RENDIJA DE D1, y la diferencia importa:
##
##   | concepto   | D1 puerta cerrada        | R3 envolvente exterior     |
##   |------------|--------------------------|----------------------------|
##   | ley        | potencia, |dp|^0,65      | orificio, sqrt(|dp|)       |
##   | area       | ELA a 4 Pa (NIST)        | area de orificio geometrica|
##   | Cd         | 1,0 por convenio de ELA  | 0,61, factor aparte        |
##   | reparto    | 40/47/13 por bandas      | uniforme por el hueco      |
##   | contra     | otro recinto             | el exterior                |
##
## Mezclarlas seria un error fisico: una ELA ya lleva el coeficiente dentro por
## definicion, y un area de orificio no.
##
## Procedencia del area y del coeficiente: son los de la purga historica de
## `GasExchangeSystem.step_pressure_venting`, que aplicaba
## `0.61 * window_leakage_area_m2 * sqrt(2*dp/rho)`. El 0,61 va SEPARADO del
## area en esa ruta y tambien en el bloque shadow de `Phase3ZoneMassSystem`
## (`EXTERIOR_DISCHARGE_COEFF`), asi que los 0,005 m2 son area geometrica y no
## llevan el coeficiente incorporado. R3 conserva esa convencion; calibrarla es
## D4, no esta fase.
##
## Lo que R3 NO hereda de la ruta historica:
##   - `flow_path_factor`, que reducia el area segun `hrr_kw` y la existencia de
##     un camino exterior remoto. Era una heuristica para emular caminos de
##     flujo que la red resuelve de verdad;
##   - la direccion unica de salida (`maxf(0.0, overpressure - dp_wind)`): aqui
##     el flujo entra, sale y puede hacer las dos cosas a la vez por altura.

const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")

## Coeficiente de descarga del orificio. Es el historico, y va SEPARADO del
## area: el area declarada es geometrica.
const DISCHARGE_COEFF: float = 0.61
## Procedencia, para que el diagnostico distinga esta fuga de un vano abierto.
const PROVENANCE: String = "exterior_envelope_leakage"
## Prefijo propio del identificador: no colisiona con `op_` ni con `crack_`.
const ID_PREFIX: String = "env_"


## ¿Esta abertura aporta fuga de envolvente en este paso?
##
## Un `HOLE` nunca: `is_closed()` ya devuelve falso para el, porque un hueco sin
## carpinteria no se cierra. Una abertura interior tampoco: su fuga es D1.
static func provides_leakage(opening, outside_id: int, leak_area_m2: float) -> bool:
	if opening == null:
		return false
	if int(opening.type) == OpeningModelScript.Type.HOLE:
		return false
	if int(opening.a) != outside_id and int(opening.b) != outside_id:
		return false
	if not opening.is_closed():
		return false
	return is_finite(leak_area_m2) and leak_area_m2 > 0.0


## Elemento de fuga para el solver, o {} si esta abertura no aporta.
##
## Se expresa como abertura grande con una fraccion abierta EQUIVALENTE, no
## porque sea una ventana entreabierta, sino porque asi la integra el mismo
## `_integrate_opening` que ya reparte por bandas, aplica el perfil hidrostatico
## y suma el viento una sola vez. Copiar la ley de Bernoulli en un segundo sitio
## seria crear un dueño paralelo de la misma fisica.
##
## La equivalencia es exacta, no aproximada: el solver integra
## `Cd * width * open_fraction * dz` a lo largo del hueco, y
## `lintel_height_m() = sill_m + height_m`, de modo que el area total integrada
## vale `width * open_fraction * height`. Con
## `open_fraction = area / (width * height)` sale `area`, exactamente.
static func build_leakage_element(
	opening,
	outside_id: int,
	floor_z_m: float,
	room_a_key: String,
	room_b_key: String,
	leak_area_m2: float
) -> Dictionary:
	if not provides_leakage(opening, outside_id, leak_area_m2):
		return {}
	var width_m: float = float(opening.width_m)
	var height_m: float = float(opening.height_m)
	if not is_finite(width_m) or not is_finite(height_m):
		return {}
	var geometric_area_m2: float = width_m * height_m
	if geometric_area_m2 <= 0.0:
		return {}
	# Una fuga mayor que el propio hueco no es una fuga: es un agujero. Se
	# rechaza en vez de recortarla en silencio, que dejaria el area declarada y
	# la aplicada diciendo cosas distintas.
	if leak_area_m2 > geometric_area_m2:
		return {}
	var open_fraction: float = leak_area_m2 / geometric_area_m2
	return {
		# Identificador estable y propio: dos ventanas iguales entre el mismo
		# recinto y el exterior no colisionan, porque el indice las separa.
		"opening_id": "%s%d" % [ID_PREFIX, int(opening.opening_index)],
		"room_a_id": room_a_key,
		"room_b_id": room_b_key,
		"bottom_z_m": floor_z_m + float(opening.sill_m),
		"top_z_m": floor_z_m + float(opening.lintel_height_m()),
		"width_m": width_m,
		"open_fraction": open_fraction,
		"discharge_coeff": DISCHARGE_COEFF,
		# Metadatos de procedencia. El solver no los lee: estan para que el
		# diagnostico pueda separar una fuga de envolvente de un vano abierto.
		"provenance": PROVENANCE,
		"leak_area_m2": leak_area_m2,
		"geometric_area_m2": geometric_area_m2,
		"opening_type": int(opening.type),
		"wall_side": String(opening.wall_side),
	}
