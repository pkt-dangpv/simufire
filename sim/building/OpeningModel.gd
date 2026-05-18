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

# Fracción de apertura efectiva adicional por deformación térmica del marco.
# Calculada cada paso por GasExchangeSystem según la temp. de la sala adyacente.
# NO se persiste en JSON; solo aplica a puertas interiores (type == DOOR).
var thermal_gap_fraction: float = 0.0

# SF-R7: Apertura vertical (hueco de suelo/techo entre plantas).
# Cuando is_vertical=true, el flujo está impulsado por flotabilidad térmica
# (efecto chimenea) en lugar de por Bernoulli horizontal con plano neutro.
# Ejemplo: hueco de escalera que conecta PB con P1.
var is_vertical: bool = false

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


func lintel_height_m() -> float:
	return sill_m + height_m


func is_exterior_opening() -> bool:
	return a == BuildingModel.OUTSIDE_ID or b == BuildingModel.OUTSIDE_ID


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
		if is_closed():
			return "CERRADA"
		if is_fully_open():
			return "ABIERTA"
		return "ROTA"

	if is_closed():
		return "CERRADA"
	if is_fully_open():
		return "ABIERTA"
	return "ENTREABIERTA"
