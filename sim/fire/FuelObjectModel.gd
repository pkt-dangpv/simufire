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


func configure_from_legacy_room(room: RoomModel) -> void:
	if room == null:
		return

	id = "room_proxy_%d" % room.id
	name = "%s (proxy)" % room.name
	kind = room.kind
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


func has_remaining_fuel() -> bool:
	return remaining_fuel_MJ > 0.001


func can_ignite() -> bool:
	return has_remaining_fuel() and state != State.BURNED_OUT


func remaining_fraction() -> float:
	if fuel_energy_MJ <= 0.0:
		return 0.0
	return clampf(remaining_fuel_MJ / fuel_energy_MJ, 0.0, 1.0)
