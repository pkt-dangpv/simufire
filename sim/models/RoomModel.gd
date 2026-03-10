extends RefCounted
class_name RoomModel

var id: int
var name: String
var kind: String

var volume_m3: float
var height_m: float
var floor_area_m2: float

var flashover_triggered: bool = false
var pre_flashover: bool = false

# Estado 2 capas (simplificado)
var h_layer_m: float = 1.8
var temp_upper_c: float = 60.0
var temp_lower_c: float = 20.0
var o2: float = 0.209

# Humo como "masa equivalente" (no química completa aún)
var smoke_mass_kg: float = 0.0

# Fuego (puedes enchufar tu FireModel actual aquí luego)
var hrr_kw: float = 0.0

func _init(_id:int, _name:String, _kind:String, _volume:float, _height:float) -> void:
	id = _id
	name = _name
	kind = _kind
	volume_m3 = _volume
	height_m = _height
	floor_area_m2 = volume_m3 / height_m

func upper_thickness_m() -> float:
	return maxf(0.0, height_m - h_layer_m)

func clamp_state() -> void:
	h_layer_m = clampf(h_layer_m, 0.2, height_m)
	o2 = clampf(o2, 0.10, 0.209)
	temp_upper_c = maxf(temp_upper_c, temp_lower_c)

func add_upper_smoke(dm_kg: float) -> void:
	smoke_mass_kg = maxf(0.0, smoke_mass_kg + dm_kg)

func add_upper_energy(dE_kJ: float) -> void:
	# Modelo muy simple: energía -> subida de Tupper
	# Ajustable: "capacidad térmica efectiva" del upper (kJ/°C)
	var cap_kJ_per_C := 300.0  # tuning
	temp_upper_c += dE_kJ / cap_kJ_per_C
