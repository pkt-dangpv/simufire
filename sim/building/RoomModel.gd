extends RefCounted
class_name RoomModel

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")

# ============================================================
# ROOM MODEL
# ------------------------------------------------------------
# Estado de una habitacion individual.
# Guarda:
# - geometria basica
# - estado termico
# - estado de gases/humo
# - referencia al fuego si existe
# ============================================================

var id: int = -1
var name: String = ""
var kind: String = ""

# Geometria
var width_m: float = 0.0
var length_m: float = 0.0
var height_m: float = 2.5

# Estado termico
var temp_upper_c: float = 20.0
var temp_upper_raw_c: float = 20.0
var temp_upper_clamped: bool = false
var temp_upper_clamp_time_s: float = 0.0
var temp_upper_clamp_count: int = 0
var temp_lower_c: float = 20.0

# Gases / oxigeno
var o2: float = 0.209

# Humo
var smoke_kg: float = 0.0
var smoke_prod_kg_s: float = 0.0
var h_layer_m: float = 2.5

# Capa superior de gases calientes
var thermal_layer_m: float = 2.5
var upper_gas_kg: float = 0.0
var upper_energy_kj: float = 0.0
var upper_radiative_loss_kw: float = 0.0
var layer_150c_m: float = 2.5

# Monoxido de carbono - masa en la sala (kg)
var co_kg: float = 0.0
var co_upper_kg: float = 0.0

# Dioxido de carbono - masa en la sala (kg)
var co2_kg: float = 0.0

# Cianuro de hidrógeno - masa en la sala (kg)
var hcn_kg: float = 0.0

# FED acumulado (Fractional Effective Dose) - ISO 13571
var fed: float = 0.0

# Supervivencia de Victimas (%)
var svv_pct: float = 100.0
var svv_worst_pct: float = 100.0

# Visibilidad instantánea (Purser) en metros
var visibility_m: float = 30.0

# Carga de combustible y limite de HRR
var fuel_energy_MJ: float = 0.0
var max_hrr_kw: float = 0.0
var fuel_objects: Array = []

# Fuego
var fire: FireModel = null
var fire_time_s: float = 0.0
var hrr_kw: float = 0.0
var hrr_target_kw: float = 0.0
var pyrolysis_kw: float = 0.0
var burned_hrr_kw: float = 0.0
var unburned_generation_kw: float = 0.0
var flame_hrr_target_kw: float = 0.0
var smolder_hrr_target_kw: float = 0.0
var pool_release_hrr_target_kw: float = 0.0
var fire_dormant_time_s: float = 0.0
var fire_low_hrr_time_s: float = 0.0
var fire_o2_extinguished: bool = false
var o2_hrr_factor: float = 1.0
var retained_unburned_MJ: float = 0.0
var ventilation_response_factor: float = 0.0

# Presion de la capa superior respecto al exterior
var overpressure_pa: float = 0.0

# Eventos
var flashover_triggered: bool = false
var flashover_time_s: float = -1.0
var fire_spread_exposure_s: float = 0.0


func floor_area_m2() -> float:
	return width_m * length_m


func volume_m3() -> float:
	return width_m * length_m * height_m


func reset_dynamic_state(ambient_temp_c: float, ambient_o2: float) -> void:
	temp_upper_c = ambient_temp_c
	temp_upper_raw_c = ambient_temp_c
	temp_upper_clamped = false
	temp_upper_clamp_time_s = 0.0
	temp_upper_clamp_count = 0
	temp_lower_c = ambient_temp_c
	o2 = ambient_o2
	smoke_kg = 0.0
	smoke_prod_kg_s = 0.0
	h_layer_m = height_m
	thermal_layer_m = height_m
	upper_gas_kg = 0.0
	upper_energy_kj = 0.0
	upper_radiative_loss_kw = 0.0
	layer_150c_m = height_m
	co_kg = 0.0
	co_upper_kg = 0.0
	co2_kg = 0.0
	hcn_kg = 0.0
	fed = 0.0
	svv_pct = 100.0
	svv_worst_pct = 100.0
	visibility_m = 30.0
	fire = null
	fire_time_s = 0.0
	hrr_kw = 0.0
	hrr_target_kw = 0.0
	pyrolysis_kw = 0.0
	burned_hrr_kw = 0.0
	unburned_generation_kw = 0.0
	flame_hrr_target_kw = 0.0
	smolder_hrr_target_kw = 0.0
	pool_release_hrr_target_kw = 0.0
	fire_dormant_time_s = 0.0
	fire_low_hrr_time_s = 0.0
	fire_o2_extinguished = false
	o2_hrr_factor = 1.0
	retained_unburned_MJ = 0.0
	ventilation_response_factor = 0.0
	overpressure_pa = 0.0
	flashover_triggered = false
	flashover_time_s = -1.0
	fire_spread_exposure_s = 0.0
