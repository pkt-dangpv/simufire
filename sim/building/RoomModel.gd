extends RefCounted
class_name RoomModel

# ============================================================
# ROOM MODEL
# ------------------------------------------------------------
# Estado de una habitación individual.
# Guarda:
# - geometría básica
# - estado térmico
# - estado de gases/humo
# - referencia al fuego si existe
# ============================================================

var id: int = -1
var name: String = ""
var kind: String = ""

# Geometría
var width_m: float = 0.0
var length_m: float = 0.0
var height_m: float = 2.5

# Estado térmico
var temp_upper_c: float = 20.0
var temp_lower_c: float = 20.0

# Gases / oxígeno
var o2: float = 0.209

# Humo
var smoke_kg: float = 0.0
var smoke_prod_kg_s: float = 0.0
var h_layer_m: float = 2.5

# Capa superior de gases calientes
var upper_gas_kg: float = 0.0
var upper_energy_kj: float = 0.0

# Monóxido de carbono — masa en la sala (kg)
# Se convierte a ppm en SimulationEngine para exposición y log.
var co_kg: float = 0.0

# Carga de combustible y límite de HRR — se asignan desde la plantilla según kind
# fuel_energy_MJ: energía total disponible. 0.0 = usa el valor por defecto del engine.
# max_hrr_kw: tasa máxima de liberación de calor. 0.0 = usa el valor por defecto del engine.
var fuel_energy_MJ: float = 0.0
var max_hrr_kw: float = 0.0

# Fuego
var fire: FireModel = null
var fire_time_s: float = 0.0
var hrr_kw: float = 0.0
var fire_low_hrr_time_s: float = 0.0  # contador de tiempo en agonía (HRR bajo sostenido)

# Presión de la capa superior respecto al exterior
# Sube por boyantez del gas caliente; baja al ventilar por fuga de ventanas.
var overpressure_pa: float = 0.0

# Eventos
var flashover_triggered: bool = false

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

func floor_area_m2() -> float:
	return width_m * length_m

func volume_m3() -> float:
	return width_m * length_m * height_m
	
