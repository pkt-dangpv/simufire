extends RefCounted
class_name OpeningModel

# ============================================================
# OPENING MODEL
# ------------------------------------------------------------
# Representa una apertura (puerta o ventana) entre dos salas
# o entre una sala y el exterior (b == OUTSIDE_ID).
# - open_fraction: 0.0 = cerrado, 1.0 = totalmente abierto
# - sill_m: altura del alféizar desde el suelo (ventanas)
# - lintel_height_m(): altura total = sill_m + height_m
# ============================================================

enum Type { DOOR, WINDOW, HOLE }

const EPSILON: float = 0.001
const WINDOW_FULL_OPEN_THRESHOLD: float = 0.5

# --- Limites del balcon (N-1) ---
#
# Viven aqui porque los usan tres sitios que tienen que decir lo mismo: el
# serializador al normalizar el dato, el editor al ofrecer los mandos y la
# vista al construir la losa. Repartidos, bastaba tocar uno para que el editor
# dejase pedir algo que la vista no construye.
const BALCONY_MIN_DEPTH_M: float = 0.40
## Vuelo maximo. Un balcon de vivienda es una losa en voladizo, y a partir de
## unos dos metros deja de sostenerse como tal: pide vigas de canto, jabalcones
## o pilares hasta la calle, que es otra cosa y no un balcon. Los balcones
## espanoles corrientes vuelan entre 0,90 y 1,50 m.
const BALCONY_MAX_DEPTH_M: float = 2.00
## Regla de predimensionado del voladizo: el canto de la losa no baja de la
## decima parte del vuelo. Es lo que impide que un balcon de dos metros se
## dibuje con el mismo canto de 18 cm que uno de ochenta centimetros y se lea
## como una plancha de papel.
const BALCONY_MIN_DEPTH_TO_THICKNESS: float = 10.0
## Antepecho. El CTE DB-SUA 1 pide 1,10 m por encima de 6 m de desnivel y
## 0,90 m por debajo; el minimo de aqui deja sitio a los dos casos.
const BALCONY_MIN_PARAPET_M: float = 0.60
const BALCONY_MAX_PARAPET_M: float = 1.60
## Cuanto mas ancha que el hueco es una losa sin ancho declarado.
const BALCONY_DEFAULT_MARGIN_M: float = 0.80

var a: int            # room id
var b: int            # room id, o -1 = exterior
var type: int = Type.DOOR

var width_m: float = 0.9
var height_m: float = 2.0
var sill_m: float = 0.0           # para ventanas (altura del alféizar)
var open_fraction: float = 1.0    # 0..1
var opening_index: int = -1
var wall_side: String = ""
var offset_m: float = 0.5
var offset_is_fraction: bool = true
var swing_direction: String = "in"
var hinge_side: String = "left"
var glass_broken: bool = false

# N-1: balcon colgado de esta abertura. Es DECORADO y solo lo mira la vista:
# la losa no es transitable y el motor no lo lee. Un balcon no cambia el hueco
# -sigue siendo la misma puerta o ventana, con su ancho, su alto y su alfeizar-,
# cambia lo que hay al otro lado, y eso el modelo de fuego no lo representa.
# Solo tiene sentido en una abertura exterior y no vertical.
var has_balcony: bool = false
# Ancho de la losa. 0 = se deriva del ancho del hueco (ver `balcony_span_m`).
var balcony_width_m: float = 0.0
# Vuelo: cuanto sale la losa de la fachada. Ver BALCONY_MAX_DEPTH_M.
var balcony_depth_m: float = 1.20
# Antepecho. 1,10 m es el minimo del CTE DB-SUA 1 para desniveles de mas de
# 6 m, que es cualquier balcon a partir de la tercera planta.
var balcony_parapet_m: float = 1.10

# Fracción de apertura efectiva adicional por deformación térmica del marco.
# Calculada cada paso por GasExchangeSystem según la temp. de la sala adyacente.
# NO se persiste en JSON; solo aplica a puertas interiores (type == DOOR).
var thermal_gap_fraction: float = 0.0

# SF-R7: Apertura vertical (hueco de suelo/techo entre plantas).
# Cuando is_vertical=true, el flujo está impulsado por flotabilidad térmica
# (efecto chimenea) en lugar de por Bernoulli horizontal con plano neutro.
# Ejemplo: hueco de escalera que conecta PB con P1.
var is_vertical: bool = false

# Fracción suavizada para aperturas exteriores (low-pass sobre open_fraction).
# Evita saltos instantáneos de presión/O₂/humo al abrir/cerrar ventanas/puertas ext.
# -1.0 = no inicializado (SimulationEngine lo fija al primer step).
# Para aperturas interiores, SimulationEngine lo mantiene = open_fraction (sin suavizado).
var open_fraction_smooth: float = -1.0

# Coeficiente de "derrame" (tunable)
var spill_coeff: float = 0.65

# SF-AUD-036: PPV — Positive Pressure Ventilation
# Caudal forzado del ventilador [m³/s]. 0 = sin PPV.
# Ejemplo: ventilador PPV táctico residencial ~2.0-5.0 m³/s.
var ppv_flow_m3_s: float = 0.0
# Presión manométrica del ventilador PPV [Pa]. Sobrepresión que impulsa exhaustión.
# Típico: 50-120 Pa para ventiladores tácticos de bomberos.
var ppv_delta_p_pa: float = 50.0


func _init(_a: int, _b: int, _type: int, _w: float, _h: float, _open: float = 1.0, _sill: float = 0.0) -> void:
	a = _a
	b = _b
	type = _type
	width_m = _w
	height_m = _h
	open_fraction = clampf(_open, 0.0, 1.0)
	sill_m = _sill


func set_open_fraction(value: float) -> void:
	if type == Type.HOLE:
		open_fraction = 1.0
		return
	open_fraction = clampf(value, 0.0, 1.0)


func mark_glass_broken() -> void:
	if type == Type.WINDOW:
		glass_broken = true


func lintel_height_m() -> float:
	return sill_m + height_m


func is_exterior_opening() -> bool:
	return a == BuildingModel.OUTSIDE_ID or b == BuildingModel.OUTSIDE_ID


## Si esta abertura puede llevar balcon colgado. Un hueco entre dos salas no da
## a ninguna fachada, y uno vertical es un hueco de forjado.
func accepts_balcony() -> bool:
	return is_exterior_opening() and not is_vertical


## Canto que le toca a la losa por su vuelo. Un balcon mas largo pide una losa
## mas gruesa; con un canto fijo, el vuelo de dos metros se dibuja como una
## hoja de papel volando.
func balcony_slab_thickness_m(declared_m: float) -> float:
	return maxf(declared_m, balcony_depth_m / BALCONY_MIN_DEPTH_TO_THICKNESS)


## Recorta el ancho de un balcon para que no se salga de la fachada de la que
## cuelga, dada en coordenadas del muro (`u_min`, `u_max`).
##
## Se estrecha CENTRADO en su hueco, nunca se corre de sitio: un balcon
## desplazado respecto de su propia puerta no existe, y en cambio un balcon
## estrecho junto a la esquina del edificio si. La regla vive aqui porque la
## usan dos sitios que saben cosas distintas -el editor conoce el paramento de
## la sala, la vista conoce el lienzo entero- y lo que no puede diferir es la
## regla.
static func balcony_trimmed_span_m(declared_m: float, axis_center_m: float, u_min: float, u_max: float) -> float:
	if u_max <= u_min:
		return declared_m
	var room_m: float = 2.0 * minf(axis_center_m - u_min, u_max - axis_center_m)
	return minf(declared_m, maxf(0.0, room_m))


## Ancho real de la losa del balcon. Sin dato propio, se saca del hueco: un
## balcon algo mas ancho que la puerta, que es lo que se construye.
func balcony_span_m() -> float:
	if balcony_width_m > 0.05:
		return balcony_width_m
	return width_m + BALCONY_DEFAULT_MARGIN_M


func is_closed() -> bool:
	if type == Type.HOLE:
		return false
	return open_fraction <= EPSILON


func effective_open_fraction() -> float:
	if type == Type.HOLE:
		return 1.0
	# Suma la fracción base (decisión del usuario/script) y el gap térmico
	# (deformación del marco por calor). El resultado se acota a [0, 1].
	return clampf(open_fraction + thermal_gap_fraction, 0.0, 1.0)


func is_fully_open() -> bool:
	if type == Type.HOLE:
		return true
	if type == Type.WINDOW:
		return open_fraction >= WINDOW_FULL_OPEN_THRESHOLD
	return open_fraction >= 1.0 - EPSILON


func state_label() -> String:
	if type == Type.HOLE:
		return "ABIERTO"
	if type == Type.WINDOW:
		if glass_broken:
			return "ROTA"
		if is_closed():
			return "CERRADA"
		if is_fully_open():
			return "ABIERTA"
		return "ENTREABIERTA"

	if is_closed():
		return "CERRADA"
	if is_fully_open():
		return "ABIERTA"
	return "ENTREABIERTA"
