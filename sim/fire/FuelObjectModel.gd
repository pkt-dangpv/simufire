extends RefCounted
class_name FuelObjectModel

# ============================================================
# FUEL OBJECT MODEL
# ------------------------------------------------------------
# Representa un combustible individual dentro de una sala.
# El motor podrá evaluar muchos objetos por recinto en lugar
# de asumir un único combustible monolítico por habitación.
# ============================================================

enum State {
	COLD,
	HEATING,
	PYROLYZING,
	FLAMING,
	DECAYING,
	BURNED_OUT
}

var id: String = ""
var name: String = ""
var kind: String = ""

# Ubicacion estructural para editores/visualizadores 2D.
var room_id: int = -1
var position_m: Vector2 = Vector2.ZERO
var size_m: Vector2 = Vector2.ONE
var rotation_deg: float = 0.0

# Geometría / exposición simplificadas
var footprint_m2: float = 0.0
var exposed_area_m2: float = 0.0
var elevation_m: float = 0.0

# Combustible
var fuel_energy_MJ: float = 0.0
var remaining_fuel_MJ: float = 0.0
var max_hrr_kw: float = 0.0
var ignition_temp_c: float = 320.0
var ignition_flux_kw_m2: float = 18.0

# Producción / consumo
var smoke_yield_kg_per_MJ: float = 0.00375
var co_yield_kg_per_MJ: float = 0.00025
# HCN yield (kg/MJ). Depende del contenido de nitrogeno del combustible (SF-AUD-006).
# Madera/celulosa (~0.1% N): 0.00004  |  PU flexible (~5% N): 0.0010-0.0040
# Nylon (~12% N): 0.0030-0.0100      |  ISO 19706:2007 Tabla 1.
# 0.00004 = default residencial conservador (mezcla con predominio de celulosa).
var hcn_yield_kg_per_MJ: float = 0.00004
# Irritantes (SF-AUD-018) — yields en kg/MJ. Default 0.0 = sin contenido de Cl/irritante.
# HCl: PVC ~0.024 kg/MJ (Levin 1996); madera ~0 (sin Cl). IC50 sensory = 900 ppm.
# Acroleína: madera ~0.00002; poliuretano ~0.000025; IC50 sensory = 4 ppm.
# Formaldehído: madera ~0.000015; poliuretano ~0.00002; IC50 sensory = 250 ppm.
var hcl_yield_kg_per_MJ: float = 0.0
var acrolein_yield_kg_per_MJ: float = 0.0
var formaldehyde_yield_kg_per_MJ: float = 0.0
var o2_consumption_kg_per_MJ: float = 0.076

# Estado dinámico
var state: int = State.COLD
var surface_temp_c: float = 20.0
var incident_heat_flux_kw_m2: float = 0.0
var exposure_s: float = 0.0
var hrr_kw: float = 0.0
var autoignite_ready: bool = false
var ignited_by_object_id: String = ""
var is_primary_ignition_source: bool = false

# Fuego de charco (pool fire) — solo activo si pool_spread_rate_m2_s > 0.
# El área del charco crece a la tasa indicada hasta pool_max_area_m2 (0 = sin límite,
# se usa el área del suelo de la sala). La potencia calórica es:
#   HRR = pool_hrr_kw_m2 * pool_area_m2  (kW)
var pool_area_m2: float = 0.0           # área inicial / actual del charco (m²)
var pool_initial_area_m2: float = 0.0   # área inicial para reset
var pool_spread_rate_m2_s: float = 0.0  # tasa de expansión (m²/s); 0 = no es pool fire
var pool_hrr_kw_m2: float = 1000.0     # intensidad de quemado por área (kW/m²)
var pool_max_area_m2: float = 0.0       # límite de área (0 = usar suelo de la sala)


func configure_from_legacy_room(room: RoomModel) -> void:
	if room == null:
		return

	id = "room_proxy_%d" % room.id
	name = "%s (proxy)" % room.name
	kind = room.kind
	room_id = room.id
	position_m = Vector2.ZERO
	size_m = Vector2(maxf(0.1, room.width_m), maxf(0.1, room.length_m))
	rotation_deg = 0.0
	fuel_energy_MJ = maxf(0.0, room.fuel_energy_MJ)
	remaining_fuel_MJ = fuel_energy_MJ
	max_hrr_kw = maxf(0.0, room.max_hrr_kw)
	footprint_m2 = room.floor_area_m2()
	exposed_area_m2 = footprint_m2
	ignition_temp_c = 320.0
	ignition_flux_kw_m2 = 18.0


func reset_dynamic_state(ambient_temp_c: float = 20.0) -> void:
	remaining_fuel_MJ = fuel_energy_MJ
	state = State.COLD
	surface_temp_c = ambient_temp_c
	incident_heat_flux_kw_m2 = 0.0
	exposure_s = 0.0
	hrr_kw = 0.0
	autoignite_ready = false
	ignited_by_object_id = ""
	pool_area_m2 = pool_initial_area_m2


func has_remaining_fuel() -> bool:
	return remaining_fuel_MJ > 0.001


func can_ignite() -> bool:
	return has_remaining_fuel() and state != State.BURNED_OUT


func remaining_fraction() -> float:
	if fuel_energy_MJ <= 0.0:
		return 0.0
	return clampf(remaining_fuel_MJ / fuel_energy_MJ, 0.0, 1.0)
