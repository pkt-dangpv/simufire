extends RefCounted
class_name CombustionSystem

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")

# ============================================================
# COMBUSTION SYSTEM
# ------------------------------------------------------------
# Punto de entrada para migrar desde "un fuego por sala" a
# "muchos objetos combustibles por sala".
#
# Por ahora:
# - gestiona el inventario de objetos combustibles
# - crea proxies de compatibilidad cuando la sala aún usa el
#   modelo heredado fuel_energy_MJ / max_hrr_kw
# - expone agregados útiles al engine
# ============================================================

func ensure_room_fuel_objects(room: RoomModel) -> void:
	if room == null:
		return

	if room.fuel_objects == null:
		room.fuel_objects = []

	if not room.fuel_objects.is_empty():
		return

	if room.fuel_energy_MJ <= 0.0 and room.max_hrr_kw <= 0.0:
		return

	var proxy = FuelObjectModelScript.new()
	proxy.configure_from_legacy_room(room)
	room.fuel_objects.append(proxy)


func bootstrap_building(building: BuildingModel) -> void:
	if building == null:
		return

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		ensure_room_fuel_objects(room)


func create_legacy_room_fire(room: RoomModel, defaults: Dictionary) -> FireModel:
	if room == null:
		return null

	ensure_room_fuel_objects(room)

	var fire: FireModel = FireModelScript.new()
	fire.growth_alpha_kw_s2 = float(defaults.get("growth_alpha_kw_s2", fire.growth_alpha_kw_s2))
	fire.secondary_hrr_gain_kw = float(defaults.get("secondary_hrr_gain_kw", fire.secondary_hrr_gain_kw))
	fire.flashover_hrr_multiplier = float(defaults.get("flashover_hrr_multiplier", fire.flashover_hrr_multiplier))
	fire.flashover_min_hrr_kw = float(defaults.get("flashover_min_hrr_kw", fire.flashover_min_hrr_kw))
	fire.o2_nominal = float(defaults.get("o2_nominal", fire.o2_nominal))
	fire.o2_min_for_flame = float(defaults.get("o2_min_for_flame", fire.o2_min_for_flame))
	fire.smoke_yield_kg_per_MJ = float(defaults.get("smoke_yield_kg_per_MJ", fire.smoke_yield_kg_per_MJ))
	fire.o2_consumption_kg_per_MJ = float(defaults.get("o2_consumption_kg_per_MJ", fire.o2_consumption_kg_per_MJ))
	fire.max_hrr_kw = _resolve_room_max_hrr_kw(
		room,
		float(defaults.get("max_hrr_kw", fire.max_hrr_kw))
	)
	fire.fuel_energy_MJ = _resolve_room_fuel_energy_MJ(
		room,
		float(defaults.get("fuel_energy_MJ", fire.fuel_energy_MJ))
	)
	fire.remaining_fuel_MJ = fire.fuel_energy_MJ

	_sync_legacy_proxy_from_fire(room, fire, 0.0, false)
	return fire


func step_room_fire(room: RoomModel, dt: float, context: Dictionary) -> bool:
	if room == null:
		return false

	if room.fire == null:
		room.hrr_kw = 0.0
		room.smoke_prod_kg_s = 0.0
		_sync_legacy_proxy_idle(room)
		return false

	var fire: FireModel = room.fire
	var ambient_c: float = float(context.get("ambient_c", 20.0))
	var o2_factor: float = _compute_o2_factor(room.o2, fire.o2_nominal, fire.o2_min_for_flame)
	var can_flame: bool = room.o2 > fire.o2_min_for_flame

	if can_flame:
		room.fire_time_s += dt

	var hrr_target_kw: float = fire.compute_hrr_kw(room.fire_time_s)
	var fuel_fraction: float = fire.remaining_fuel_MJ / maxf(0.001, fire.fuel_energy_MJ)
	var decay_factor: float = 1.0
	if fuel_fraction < 0.15:
		decay_factor = fuel_fraction / 0.15

	var hrr_kw: float = hrr_target_kw * decay_factor
	var thermal_feedback_coeff: float = float(context.get("thermal_feedback_coeff", 0.0))
	var thermal_feedback_max: float = float(context.get("thermal_feedback_max", 1.0))
	var rad_feedback: float = 1.0 + thermal_feedback_coeff \
			* maxf(0.0, room.temp_upper_c - ambient_c) / 500.0
	rad_feedback = minf(rad_feedback, thermal_feedback_max)
	hrr_kw *= rad_feedback

	room.hrr_kw = hrr_kw * o2_factor

	var kawagoe_limit_kw: float = float(context.get("kawagoe_limit_kw", 0.0))
	if kawagoe_limit_kw > 0.0:
		room.hrr_kw = minf(room.hrr_kw, kawagoe_limit_kw)
	if not can_flame:
		room.hrr_kw = 0.0

	var smoke_basis_multiplier: float = lerpf(
		1.0 + float(context.get("fire_smoke_basis_min_fraction", 0.0)),
		1.0,
		sqrt(o2_factor)
	)
	var smoke_basis_kw: float = room.hrr_kw * smoke_basis_multiplier
	if not can_flame:
		var smolder_fraction: float = float(context.get("fire_smolder_hrr_fraction", 0.10))
		var residual_smolder_cap_kw: float = maxf(
			float(context.get("fire_extinction_hrr_kw", 0.0)),
			fire.max_hrr_kw * smolder_fraction * 0.15
		)
		smoke_basis_kw = minf(
			hrr_kw * smolder_fraction,
			residual_smolder_cap_kw
		)

	var smoke_yield_kg_per_MJ: float = lerpf(
		fire.smoke_yield_kg_per_MJ * float(context.get("fire_smoke_yield_low_o2_multiplier", 1.0)),
		fire.smoke_yield_kg_per_MJ,
		o2_factor
	)
	if not can_flame:
		smoke_yield_kg_per_MJ *= float(context.get("fire_smolder_smoke_multiplier", 1.0))

	var smoke_basis_MJ: float = smoke_basis_kw * dt / 1000.0
	var pyrolysis_consumption_MJ: float = smoke_basis_MJ * 0.35
	var heat_release_MJ: float = room.hrr_kw * dt / 1000.0
	var fuel_demand_MJ: float = maxf(heat_release_MJ, pyrolysis_consumption_MJ)
	var available_fuel_MJ: float = maxf(0.0, fire.remaining_fuel_MJ)
	var fuel_scale: float = 1.0
	if fuel_demand_MJ > 0.000001:
		fuel_scale = minf(1.0, available_fuel_MJ / fuel_demand_MJ)

	room.hrr_kw *= fuel_scale
	smoke_basis_kw *= fuel_scale
	heat_release_MJ = room.hrr_kw * dt / 1000.0
	smoke_basis_MJ = smoke_basis_kw * dt / 1000.0
	pyrolysis_consumption_MJ = smoke_basis_MJ * 0.35
	room.smoke_prod_kg_s = _compute_smoke_production_kg_s(smoke_basis_kw, smoke_yield_kg_per_MJ)

	var oxygen_starved: bool = room.fire_time_s > 60.0 \
			and o2_factor <= float(context.get("fire_starvation_o2_factor", 0.0))
	if (room.hrr_kw < float(context.get("fire_extinction_hrr_kw", 0.0)) or oxygen_starved) \
			and room.fire_time_s > 60.0:
		room.fire_low_hrr_time_s += dt
		if room.fire_low_hrr_time_s >= float(context.get("fire_extinction_delay_s", 0.0)):
			_sync_legacy_proxy_from_fire(room, fire, 0.0, false)
			room.hrr_kw = 0.0
			room.smoke_prod_kg_s = 0.0
			room.fire = null
			room.fire_low_hrr_time_s = 0.0
			return false
	else:
		room.fire_low_hrr_time_s = 0.0

	var co_yield: float = lerpf(
		float(context.get("co_max_yield_kg_per_MJ", 0.0)),
		float(context.get("co_base_yield_kg_per_MJ", 0.0)),
		o2_factor
	)
	var co_basis_MJ: float = maxf(heat_release_MJ, pyrolysis_consumption_MJ)
	room.co_kg += co_yield * co_basis_MJ

	var fuel_consumed_MJ: float = maxf(heat_release_MJ, pyrolysis_consumption_MJ)
	fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ - fuel_consumed_MJ)

	_sync_legacy_proxy_from_fire(room, fire, room.hrr_kw, can_flame)

	if fire.remaining_fuel_MJ <= 0.0:
		_mark_legacy_proxy_burned_out(room)
		room.hrr_kw = 0.0
		room.smoke_prod_kg_s = 0.0
		room.fire = null
		return false

	if room.fire_time_s >= float(context.get("fire_max_active_s", 0.0)):
		_sync_legacy_proxy_from_fire(room, fire, 0.0, false)
		room.hrr_kw = 0.0
		room.smoke_prod_kg_s = 0.0
		room.fire = null
		return false

	return true


func get_room_total_remaining_fuel_MJ(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var total_MJ: float = 0.0
	for obj in room.fuel_objects:
		if obj == null:
			continue
		total_MJ += maxf(0.0, obj.remaining_fuel_MJ)
	return total_MJ


func get_room_total_max_hrr_kw(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var total_kw: float = 0.0
	for obj in room.fuel_objects:
		if obj == null:
			continue
		total_kw += maxf(0.0, obj.max_hrr_kw)
	return total_kw


func get_room_active_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if obj.state == FuelObjectModelScript.State.PYROLYZING or obj.state == FuelObjectModelScript.State.FLAMING:
			count += 1
	return count


func _resolve_room_fuel_energy_MJ(room: RoomModel, fallback_MJ: float) -> float:
	if room == null:
		return fallback_MJ
	if room.fuel_energy_MJ > 0.0:
		return room.fuel_energy_MJ

	var total_remaining_MJ: float = get_room_total_remaining_fuel_MJ(room)
	if total_remaining_MJ > 0.0:
		return total_remaining_MJ

	return fallback_MJ


func _resolve_room_max_hrr_kw(room: RoomModel, fallback_kw: float) -> float:
	if room == null:
		return fallback_kw
	if room.max_hrr_kw > 0.0:
		return room.max_hrr_kw

	var total_max_kw: float = get_room_total_max_hrr_kw(room)
	if total_max_kw > 0.0:
		return total_max_kw

	return fallback_kw


func _compute_o2_factor(o2: float, nominal: float, min_o2: float) -> float:
	if o2 <= min_o2:
		return 0.0

	var o2_ratio: float = (o2 - min_o2) / maxf(0.001, nominal - min_o2)
	return clampf(o2_ratio, 0.0, 1.0)


func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float:
	var hrr_MJ_s: float = maxf(0.0, hrr_kw) / 1000.0
	return hrr_MJ_s * maxf(0.0, smoke_yield_kg_per_MJ)


func _get_legacy_room_proxy(room: RoomModel):
	if room == null or room.fuel_objects.is_empty():
		return null

	if room.fuel_objects.size() != 1:
		return null

	var proxy = room.fuel_objects[0]
	if proxy == null:
		return null
	if not String(proxy.id).begins_with("room_proxy_"):
		return null

	return proxy


func _sync_legacy_proxy_idle(room: RoomModel) -> void:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return

	proxy.hrr_kw = 0.0
	if proxy.remaining_fuel_MJ <= 0.001:
		proxy.state = FuelObjectModelScript.State.BURNED_OUT
	elif room.fire_time_s > 0.0:
		proxy.state = FuelObjectModelScript.State.DECAYING
	else:
		proxy.state = FuelObjectModelScript.State.COLD


func _sync_legacy_proxy_from_fire(room: RoomModel, fire: FireModel, hrr_kw: float, can_flame: bool) -> void:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null or fire == null:
		return

	proxy.max_hrr_kw = fire.max_hrr_kw
	proxy.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ)
	proxy.hrr_kw = maxf(0.0, hrr_kw)

	if proxy.remaining_fuel_MJ <= 0.001:
		proxy.state = FuelObjectModelScript.State.BURNED_OUT
	elif proxy.hrr_kw > 0.01 and can_flame:
		proxy.state = FuelObjectModelScript.State.FLAMING
	elif proxy.hrr_kw > 0.01:
		proxy.state = FuelObjectModelScript.State.DECAYING
	elif room.fire_time_s > 0.0:
		proxy.state = FuelObjectModelScript.State.DECAYING
	else:
		proxy.state = FuelObjectModelScript.State.COLD


func _mark_legacy_proxy_burned_out(room: RoomModel) -> void:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return

	proxy.remaining_fuel_MJ = 0.0
	proxy.hrr_kw = 0.0
	proxy.state = FuelObjectModelScript.State.BURNED_OUT
