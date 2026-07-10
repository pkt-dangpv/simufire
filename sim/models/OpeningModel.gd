extends RefCounted

enum Type { DOOR, WINDOW }

var a: int            # room id
var b: int            # room id, o -1 = exterior
var type: int = Type.DOOR

var width_m: float = 0.9
var height_m: float = 2.0
var sill_m: float = 0.0           # para ventanas (altura del alféizar)
var open_fraction: float = 1.0    # 0..1

# Coeficiente de "derrame" (tunable)
var spill_coeff: float = 0.65

func _init(_a:int, _b:int, _type:int, _w:float, _h:float, _open:float=1.0, _sill:float=0.0) -> void:
	a = _a
	b = _b
	type = _type
	width_m = _w
	height_m = _h
	open_fraction = clampf(_open, 0.0, 1.0)
	sill_m = _sill

func lintel_height_m() -> float:
	return sill_m + height_m
