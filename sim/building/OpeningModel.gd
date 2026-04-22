extends RefCounted
class_name OpeningModel

enum Type { DOOR, WINDOW }

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

# Coeficiente de "derrame" (tunable)
var spill_coeff: float = 0.65


func _init(_a: int, _b: int, _type: int, _w: float, _h: float, _open: float = 1.0, _sill: float = 0.0) -> void:
	a = _a
	b = _b
	type = _type
	width_m = _w
	height_m = _h
	open_fraction = clampf(_open, 0.0, 1.0)
	sill_m = _sill


func set_open_fraction(value: float) -> void:
	open_fraction = clampf(value, 0.0, 1.0)


func lintel_height_m() -> float:
	return sill_m + height_m


func is_exterior_opening() -> bool:
	return a == BuildingModel.OUTSIDE_ID or b == BuildingModel.OUTSIDE_ID


func is_closed() -> bool:
	return open_fraction <= EPSILON


func is_fully_open() -> bool:
	if type == Type.WINDOW:
		return open_fraction >= WINDOW_FULL_OPEN_THRESHOLD
	return open_fraction >= 1.0 - EPSILON


func state_label() -> String:
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
