extends RefCounted
class_name LayerInterfaceModel

# ============================================================
# LAYER / INTERFACE MODEL
# ------------------------------------------------------------
# Fuente canónica para distinguir alturas que antes se mezclaban:
# - h_visible_smoke_layer_m: interfaz óptica para visualización/visibilidad.
# - h_thermal_layer_m: interfaz energética para temperatura/FED térmico.
# - h_flow_interface_m: interfaz/plano de referencia para flujos.
#
# Mantiene compatibilidad con h_layer_m y thermal_layer_m: esos campos siguen
# existiendo, pero los subsistemas nuevos deben pedir aquí la altura semántica
# que necesitan.
# ============================================================


static func get_visible_smoke_layer_height_m(
	room: RoomModel,
	smoke_model: SmokeModel,
	ambient_c: float = 20.0
) -> float:
	# Capa visible: solo representa carga óptica de humo/hollín. No debe gobernar
	# flujos de gases salvo en modelos explícitamente ópticos.
	if room == null:
		return 0.0
	if smoke_model != null:
		return clampf(smoke_model.get_visible_smoke_layer_height_m(room), 0.0, room.height_m)
	if room.h_layer_m >= 0.0 and room.h_layer_m <= room.height_m:
		return clampf(room.h_layer_m, 0.0, room.height_m)
	return _estimate_visible_layer_from_smoke_mass(room, ambient_c)


static func get_thermal_layer_height_m(room: RoomModel, ambient_c: float = 20.0) -> float:
	# Capa térmica: representa la división energética upper/lower. El estado
	# persistido room.thermal_layer_m ya se actualiza desde upper_gas_kg /
	# upper_energy_kj en ThermalSystem/ZoneFireSolver; si está fuera de rango,
	# reconstruimos desde masa de gas superior como fallback conservador.
	if room == null:
		return 0.0
	if room.thermal_layer_m >= 0.0 and room.thermal_layer_m <= room.height_m:
		return clampf(room.thermal_layer_m, 0.0, room.height_m)
	return _estimate_thermal_layer_from_upper_gas(room, ambient_c)


static func get_flow_interface_height_m(
	room: RoomModel,
	smoke_model: SmokeModel,
	ambient_c: float = 20.0
) -> float:
	# Interfaz de flujo: referencia canónica para puertas, ventanas, derrame,
	# ventilación natural y routing de especies/O2. Cuando SmokeModel está
	# disponible, conserva su capa efectiva de derrame legacy como semántica de
	# flujo centralizada. Sin SmokeModel, sigue a la capa térmica: el gas caliente
	# limpio también fluye, y una capa óptica baja no inventa presión por sí sola.
	if room == null:
		return 0.0
	if smoke_model != null and smoke_model.has_method("get_effective_smoke_spill_layer_height_m"):
		return clampf(smoke_model.get_effective_smoke_spill_layer_height_m(room), 0.0, room.height_m)
	return get_thermal_layer_height_m(room, ambient_c)


static func get_breathing_zone_exposure_factor(
	room: RoomModel,
	breathing_height_m: float,
	ambient_c: float = 20.0
) -> float:
	# Factor simple 0..1 para exposición de la zona de respiración al estrato
	# caliente. 0 = respiración claramente en capa baja; 1 = claramente en capa
	# superior; transición suave de 20 cm alrededor de la interfaz térmica.
	if room == null:
		return 0.0
	var interface_m: float = get_thermal_layer_height_m(room, ambient_c)
	var z_m: float = clampf(breathing_height_m, 0.0, room.height_m)
	return clampf(inverse_lerp(interface_m - 0.10, interface_m + 0.10, z_m), 0.0, 1.0)


static func get_exterior_opening_hot_outflow_height_m(
	room: RoomModel,
	op: OpeningModel,
	smoke_model: SmokeModel,
	ambient_c: float = 20.0
) -> float:
	# Altura de la franja superior de una abertura exterior que queda por encima
	# de h_flow_interface_m. GasExchangeSystem usa esto para no recalcular un
	# plano neutro local desconectado del modelo de capas.
	if room == null or op == null:
		return 0.0
	var flow_interface_m: float = get_flow_interface_height_m(room, smoke_model, ambient_c)
	var sill_m: float = op.sill_m
	var lintel_m: float = op.lintel_height_m()
	return clampf(lintel_m - maxf(sill_m, flow_interface_m), 0.0, op.height_m)


static func _estimate_visible_layer_from_smoke_mass(room: RoomModel, ambient_c: float) -> float:
	if room == null:
		return 0.0
	if room.smoke_kg <= 0.000001:
		return room.height_m
	var smoke_density_kg_m3: float = 0.18
	var floor_area_m2: float = maxf(0.01, room.floor_area_m2())
	var effective_smoke_temp_c: float = lerpf(room.temp_lower_c, room.temp_upper_c, 0.45)
	var temp_expansion: float = maxf(1.0, (effective_smoke_temp_c + 273.15) / maxf(1.0, ambient_c + 273.15))
	var smoke_volume_m3: float = room.smoke_kg / smoke_density_kg_m3 * temp_expansion
	return clampf(room.height_m - smoke_volume_m3 / floor_area_m2, 0.0, room.height_m)


static func _estimate_thermal_layer_from_upper_gas(room: RoomModel, ambient_c: float) -> float:
	if room == null:
		return 0.0
	if room.upper_gas_kg <= 0.000001:
		return room.height_m
	var ambient_k: float = ambient_c + 273.15
	var upper_k: float = maxf(ambient_k + 1.0, room.temp_upper_c + 273.15)
	var rho_upper: float = 1.2 * ambient_k / upper_k
	var hot_volume_m3: float = room.upper_gas_kg / maxf(0.05, rho_upper)
	var hot_depth_m: float = hot_volume_m3 / maxf(0.01, room.floor_area_m2())
	return clampf(room.height_m - hot_depth_m, 0.0, room.height_m)
