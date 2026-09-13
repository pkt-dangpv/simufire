class_name FPUrbanTypology
extends RefCounted

## Que TIPO de edificio hay en la calle, segun lo alto que tenga que ser.
##
## El problema que resuelve. El decorado urbano se construia con una sola
## receta -portales de trece metros, fondo de diez, cornisa y balcones- y se le
## pasaba la altura. Mientras la altura fue de quince metros aquello era una
## manzana. Cuando la altura pasa a salir de la planta en la que vive el
## jugador (N-4), la misma receta a 140 m dibuja lapices: **un edificio de 60
## plantas no es uno de 6 estirado**, tiene otras piezas.
##
## Tres tramos, con la frontera puesta donde cambia el tipo de verdad:
##
##  - **manzana** (hasta 20 plantas). Calle entre medianeras: portales
##    estrechos, bajo comercial, balcones, ventanas de hueco. Es lo que ya
##    habia.
##  - **torre** (21 a 50). Bloque exento: menos piezas y mas anchas, podio de
##    dos plantas, ventana corrida por planta -bandas- y un retranqueo arriba.
##    Los balcones desaparecen: a esa altura no se leen y multiplican nodos.
##  - **rascacielos** (51 a 80). Podio ancho, dos retranqueos, banda de vidrio
##    continua, coronacion y antena con baliza de noche.
##
## Dentro de cada tramo los numeros se INTERPOLAN. Sin eso, 21 plantas y 49 se
## dibujarian igual y el salto se veria en el borde.
##
## Y una razon que no es de estilo: estos volumenes son los que **tapan el
## fondo**. Mientras la vista termine en un telon de skyline, desde una planta
## alta se ve el telon. Si lo que hay delante llega a la altura del ojo y cierra
## el hueco, el telon deja de importar.

const TIER_BLOCK: String = "manzana"
const TIER_TOWER: String = "torre"
const TIER_SKYSCRAPER: String = "rascacielos"

## Ventanas de hueco, una cajita por ventana. Solo en la manzana: a partir de
## veinte plantas son miles de nodos y ademas no es lo que se construye.
const WINDOWS_PUNCHED: String = "hueco"
## Banda corrida por planta. Un nodo por planta y modulo, y es lo que de verdad
## tiene una torre.
const WINDOWS_RIBBON: String = "banda"

## Fronteras de tramo, en plantas.
const TOWER_FLOORS: int = 20
const SKYSCRAPER_FLOORS: int = 50


## Ficha del tipo que le toca a una fachada de `floors` plantas.
##
## `pitch_m` es la altura de planta, que ya viene medida del edificio del
## jugador: la calle se construye con la misma, o los forjados de enfrente no
## caen a la altura de los nuestros.
static func for_floors(floors: int, pitch_m: float) -> Dictionary:
	var n: int = maxi(1, floors)
	if n <= TOWER_FLOORS:
		return _block(_progress(n, 1, TOWER_FLOORS), pitch_m)
	if n <= SKYSCRAPER_FLOORS:
		return _tower(_progress(n, TOWER_FLOORS + 1, SKYSCRAPER_FLOORS), pitch_m)
	return _skyscraper(_progress(n, SKYSCRAPER_FLOORS + 1, 80), pitch_m)


## Cuanto se ha avanzado dentro del tramo, de 0 a 1.
static func _progress(n: int, first: int, last: int) -> float:
	if last <= first:
		return 0.0
	return clampf(float(n - first) / float(last - first), 0.0, 1.0)


## Manzana entre medianeras. Lo que ya habia, ahora con los numeros escritos.
static func _block(t: float, pitch_m: float) -> Dictionary:
	return {
		"tier": TIER_BLOCK,
		# Un portal de manzana ronda los ocho metros -es lo que venia haciendo
		# el decorado, con cinco modulos por fachada- y se ensancha conforme el
		# edificio sube, pero sigue siendo un portal.
		"module_span_m": lerpf(8.5, 16.0, t),
		"module_count_max": 8,
		"depth_m": lerpf(6.6, 13.0, t),
		# Multiplica a `city_facade_depth_m` para el FONDO DEL FRENTE. Ojo con
		# confundirlo con `depth_m`, que es el fondo de las manzanas del resto
		# de la calle: el frente es una lamina fina y detras van los bloques.
		# Poniendole el fondo de manzana, los modulos de los extremos cruzaban
		# la calzada perpendicular y el filtro los descartaba: la calle se
		# quedaba corta y se le veia el final.
		"facade_depth_factor": 1.0,
		# Variacion de altura entre portales: es lo que hace que una manzana no
		# parezca un muro. En una torre no la queremos.
		"height_variation": lerpf(0.18, 0.10, t),
		"windows": WINDOWS_PUNCHED,
		"window_columns": 4,
		"balconies": true,
		"shopfronts": true,
		"podium_floors": 0,
		"podium_overhang_m": 0.0,
		# Retranqueos: [fraccion de altura donde ocurre, cuanto se estrecha].
		"setbacks": [],
		"crown": "cornisa",
		"antenna": false,
		# La fila de atras SIEMPRE se levanta por encima de la de delante, y esa
		# es toda su razon de ser: como los vecinos de enfrente miden lo mismo
		# que nosotros, su cubierta cae justo a la altura del ojo y entre ella y
		# el horizonte queda una banda de domo de cielo -el fondo gris que da
		# problemas al mirar desde arriba-. Lo que la tapa es esta fila.
		#
		# Lo que cambia por tramo es CUANTO se levanta: en una manzana puede
		# casi doblar la altura, en un rascacielos no -1,9 x 230 m son 437 m de
		# teloncito-.
		"back_row_base": 1.05,
		"back_row_gain": 0.85,
		"back_row_span_factor": 3.0,
		"pitch_m": pitch_m,
	}


## Bloque exento. Menos piezas, mas anchas y mas hondas, con podio y un
## retranqueo alto. La proporcion manda: a 40 plantas, trece metros de frente
## serian un lapiz de 1:9.
static func _tower(t: float, pitch_m: float) -> Dictionary:
	return {
		"tier": TIER_TOWER,
		"module_span_m": lerpf(24.0, 34.0, t),
		"module_count_max": 4,
		"depth_m": lerpf(18.0, 26.0, t),
		"facade_depth_factor": lerpf(2.6, 3.6, t),
		"height_variation": lerpf(0.10, 0.06, t),
		"windows": WINDOWS_RIBBON,
		"window_columns": 0,
		"balconies": false,
		"shopfronts": true,
		"podium_floors": 2,
		"podium_overhang_m": lerpf(0.45, 0.65, t),
		"setbacks": [[lerpf(0.78, 0.70, t), 0.16]],
		"crown": "remate",
		"antenna": false,
		"back_row_base": 1.04,
		"back_row_gain": 0.13,
		"back_row_span_factor": 3.8,
		"pitch_m": pitch_m,
	}


## Rascacielos: podio ancho, dos retranqueos y coronacion. La huella tiene que
## crecer de verdad -un edificio de 70 plantas sobre 20 m de lado no se
## sostiene ni de mentira-.
static func _skyscraper(t: float, pitch_m: float) -> Dictionary:
	return {
		"tier": TIER_SKYSCRAPER,
		"module_span_m": lerpf(40.0, 54.0, t),
		"module_count_max": 3,
		"depth_m": lerpf(30.0, 40.0, t),
		"facade_depth_factor": lerpf(4.2, 5.4, t),
		"height_variation": 0.05,
		"windows": WINDOWS_RIBBON,
		"window_columns": 0,
		"balconies": false,
		"shopfronts": true,
		"podium_floors": 5,
		"podium_overhang_m": lerpf(0.70, 0.95, t),
		"setbacks": [[0.42, 0.14], [lerpf(0.72, 0.66, t), 0.16]],
		"crown": "corona",
		"antenna": true,
		"back_row_base": 1.04,
		"back_row_gain": 0.10,
		# Cuanto mas lejos queda la fila, mas ancha tiene que ser para que dos
		# orientaciones contiguas se solapen y no dejen una cuna de cielo.
		"back_row_span_factor": 5.0,
		"pitch_m": pitch_m,
	}
