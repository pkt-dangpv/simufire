extends RefCounted
class_name CombustionSystem

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")

# ============================================================
# COMBUSTION SYSTEM
# ------------------------------------------------------------
# Punto de entrada para migrar desde "un fuego por sala" a
# "muchos objetos combustibles por sala".
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
		room.hrr_target_kw = 0.0
		room.smoke_prod_kg_s = 0.0
		_sync_legacy_proxy_idle(room)
		return false

	var fire: FireModel = room.fire
	var ambient_c: float = float(context.get("ambient_c", 20.0))
	var raw_o2_factor: float = _compute_o2_factor(room.o2, fire.o2_nominal, fire.o2_min_for_flame)
	var previous_hrr_kw: float = room.hrr_kw

	var smoke_fill_fraction: float = clampf(
		(room.height_m - clampf(room.h_layer_m, 0.0, room.height_m)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var subvent_temp_factor: float = inverse_lerp(
		float(context.get("fire_subvent_temp_start_c", ambient_c)),
		float(context.get("fire_subvent_temp_full_c", ambient_c)),
		room.temp_upper_c
	)
	var subvent_fill_factor: float = inverse_lerp(
		float(context.get("fire_subvent_fill_start_fraction", 0.0)),
		float(context.get("fire_subvent_fill_full_fraction", 1.0)),
		smoke_fill_fraction
	)
	var subvent_engagement: float = clampf(maxf(subvent_temp_factor, subvent_fill_factor), 0.0, 1.0)
	var subvent_o2_floor: float = float(context.get("fire_subvent_o2_floor", 0.0)) \
			* clampf(subvent_temp_factor, 0.0, 1.0) \
			* clampf(subvent_fill_factor, 0.0, 1.0)
	var latent_enabled: bool = bool(context.get("fire_latent_enabled", true))
	var latent_viable: bool = latent_enabled and _can_sustain_latent_fire(
		room,
		fire,
		context,
		ambient_c
	)

	var o2_factor_target: float = raw_o2_factor
	if room.fire_time_s > 45.0:
		o2_factor_target = maxf(o2_factor_target, subvent_o2_floor)
	room.o2_hrr_factor = _smooth_state_value(
		room.o2_hrr_factor,
		o2_factor_target,
		dt,
		float(context.get("fire_o2_hrr_rise_tau_s", 14.0)),
		float(context.get("fire_o2_hrr_fall_tau_s", 32.0))
	)
	room.o2_hrr_factor = clampf(room.o2_hrr_factor, 0.0, 1.0)

	var flame_possible_factor: float = clampf(
		inverse_lerp(
			fire.o2_min_for_flame - 0.015,
			fire.o2_min_for_flame + 0.025,
			room.o2
		),
		0.0,
		1.0
	)
	var flaming_drive: float = room.o2_hrr_factor * flame_possible_factor
	if latent_viable:
		flaming_drive = maxf(
			flaming_drive,
			subvent_o2_floor * lerpf(0.35, 1.0, subvent_engagement)
		)
	var can_flame: bool = flaming_drive > 0.08
	if can_flame or latent_viable:
		var fire_time_gain_factor: float = clampf(
			maxf(0.15 if latent_viable else 0.0, flaming_drive),
			0.0,
			1.0
		)
		room.fire_time_s += dt * fire_time_gain_factor
		if can_flame:
			room.fire_dormant_time_s = 0.0
			room.fire_o2_extinguished = false
		else:
			room.fire_dormant_time_s += dt
	else:
		room.fire_dormant_time_s += dt

	var ideal_hrr_kw: float = fire.compute_hrr_kw(room.fire_time_s)
	var fuel_fraction: float = fire.remaining_fuel_MJ / maxf(0.001, fire.fuel_energy_MJ)
	var decay_factor: float = 1.0
	if fuel_fraction < 0.15:
		decay_factor = fuel_fraction / 0.15

	ideal_hrr_kw *= decay_factor
	var thermal_feedback_coeff: float = float(context.get("thermal_feedback_coeff", 0.0))
	var thermal_feedback_max: float = float(context.get("thermal_feedback_max", 1.0))
	var rad_feedback: float = 1.0 + thermal_feedback_coeff \
			* maxf(0.0, room.temp_upper_c - ambient_c) / 500.0
	rad_feedback = minf(rad_feedback, thermal_feedback_max)
	var feedback_o2_engagement: float = clampf(
		inverse_lerp(
			fire.o2_min_for_flame - 0.005,
			fire.o2_min_for_flame + 0.035,
			room.o2
		),
		0.0,
		1.0
	)
	rad_feedback = lerpf(1.0, rad_feedback, feedback_o2_engagement)
	ideal_hrr_kw *= rad_feedback

	var smolder_fraction: float = float(context.get("fire_smolder_hrr_fraction", 0.10))
	var latent_cap_basis_kw: float = minf(fire.max_hrr_kw, maxf(previous_hrr_kw, ideal_hrr_kw))
	var latent_cap_scale: float = lerpf(
		float(context.get("fire_latent_hrr_cap_min_fraction", 0.15)),
		float(context.get("fire_latent_hrr_cap_max_fraction", 1.0)),
		subvent_engagement
	)
	var residual_smolder_cap_kw: float = maxf(
		float(context.get("fire_extinction_hrr_kw", 0.0)),
		latent_cap_basis_kw * smolder_fraction * latent_cap_scale
	)

	var pyrolysis_floor_fraction: float = 0.0
	if latent_viable:
		pyrolysis_floor_fraction = lerpf(
			float(context.get("fire_subvent_pyrolysis_min_fraction", 0.20)),
			float(context.get("fire_subvent_pyrolysis_max_fraction", 0.40)),
			subvent_engagement
		)
	var solid_pyrolysis_fraction: float = clampf(
		maxf(flaming_drive, pyrolysis_floor_fraction),
		0.0,
		1.0
	)
	var solid_pyrolysis_kw: float = ideal_hrr_kw * solid_pyrolysis_fraction
	var fresh_flame_target_kw: float = minf(
		solid_pyrolysis_kw,
		ideal_hrr_kw * clampf(flaming_drive, 0.0, 1.0)
	)
	var smolder_target_kw: float = 0.0
	if not can_flame:
		if latent_viable:
			smolder_target_kw = minf(
				residual_smolder_cap_kw,
				solid_pyrolysis_kw * smolder_fraction * lerpf(0.40, 1.0, subvent_engagement)
			)
		else:
			smolder_target_kw = 0.0
	var retained_generation_kw: float = maxf(
		0.0,
		solid_pyrolysis_kw - fresh_flame_target_kw - smolder_target_kw
	) * float(context.get("fire_unburned_generation_fraction", 0.30))

	var available_fuel_MJ: float = maxf(0.0, fire.remaining_fuel_MJ)
	var solid_fuel_demand_MJ: float = solid_pyrolysis_kw * dt / 1000.0
	var solid_fuel_scale: float = 1.0
	if solid_fuel_demand_MJ > 0.000001:
		solid_fuel_scale = minf(1.0, available_fuel_MJ / solid_fuel_demand_MJ)
	solid_pyrolysis_kw *= solid_fuel_scale
	fresh_flame_target_kw *= solid_fuel_scale
	smolder_target_kw *= solid_fuel_scale
	retained_generation_kw *= solid_fuel_scale
	solid_fuel_demand_MJ = solid_pyrolysis_kw * dt / 1000.0

	var pool_capacity_MJ: float = maxf(
		0.0,
		room.floor_area_m2() * float(context.get("fire_unburned_capacity_MJ_per_m2", 1.20))
	)
	room.retained_unburned_MJ = minf(
		pool_capacity_MJ,
		maxf(0.0, room.retained_unburned_MJ + retained_generation_kw * dt / 1000.0)
	)

	var opening_signal: float = clampf(
		maxf(
			float(context.get("outside_open_factor", 0.0)),
			maxf(0.0, float(context.get("window_open_max", 0.0)))
		),
		0.0,
		1.0
	)
	var temp_signal: float = clampf(
		inverse_lerp(
			float(context.get("fire_vent_response_temp_start_c", 140.0)),
			float(context.get("fire_vent_response_temp_full_c", 300.0)),
			room.temp_upper_c
		),
		0.0,
		1.0
	)
	var pool_signal: float = clampf(
		room.retained_unburned_MJ / maxf(1.0, pool_capacity_MJ * 0.35),
		0.0,
		1.0
	)
	var oxygen_recovery_signal: float = clampf(
		inverse_lerp(0.10, 0.45, room.o2_hrr_factor),
		0.0,
		1.0
	)
	var vent_response_target: float = opening_signal \
			* temp_signal \
			* maxf(pool_signal, oxygen_recovery_signal * 0.40)
	room.ventilation_response_factor = _smooth_state_value(
		room.ventilation_response_factor,
		vent_response_target,
		dt,
		float(context.get("fire_vent_response_rise_tau_s", 10.0)),
		float(context.get("fire_vent_response_fall_tau_s", 30.0))
	)
	room.ventilation_response_factor = clampf(room.ventilation_response_factor, 0.0, 1.0)

	var pool_release_target_kw: float = 0.0
	if room.retained_unburned_MJ > 0.001 and opening_signal > 0.01:
		var release_drive: float = room.ventilation_response_factor * maxf(0.15, oxygen_recovery_signal)
		var backdraft_ready: bool = room.retained_unburned_MJ \
				>= float(context.get("fire_backdraft_pool_threshold_MJ", 8.0)) \
				and room.o2 <= float(context.get("fire_backdraft_o2_max", 0.13)) \
				and room.temp_upper_c >= float(context.get("fire_backdraft_temp_min_c", 180.0)) \
				and opening_signal > 0.08
		if backdraft_ready:
			release_drive *= float(context.get("fire_backdraft_release_boost", 1.35))

		var release_tau_s: float = lerpf(
			float(context.get("fire_pool_release_tau_slow_s", 180.0)),
			float(context.get("fire_pool_release_tau_fast_s", 18.0)),
			room.ventilation_response_factor
		)
		var pool_release_cap_kw: float = fire.max_hrr_kw \
				* float(context.get("fire_pool_release_max_fraction", 0.18)) \
				* lerpf(0.55, 1.0, opening_signal)
		pool_release_target_kw = minf(
			room.retained_unburned_MJ * 1000.0 / maxf(1.0, release_tau_s),
			pool_release_cap_kw
		) * clampf(release_drive, 0.0, 2.0)

	var kawagoe_limit_kw: float = float(context.get("kawagoe_limit_kw", 0.0))
	room.hrr_target_kw = fresh_flame_target_kw + smolder_target_kw + pool_release_target_kw
	if not latent_viable and not can_flame and room.o2_hrr_factor < 0.02:
		room.hrr_target_kw = 0.0
	if kawagoe_limit_kw > 0.0:
		room.hrr_target_kw = minf(room.hrr_target_kw, kawagoe_limit_kw)
	room.hrr_target_kw = maxf(0.0, room.hrr_target_kw)

	var hrr_rise_tau_s: float = lerpf(
		float(context.get("fire_hrr_rise_tau_s", 6.0)) * 1.8,
		float(context.get("fire_hrr_rise_tau_s", 6.0)),
		room.ventilation_response_factor
	)
	room.hrr_kw = _smooth_state_value(
		previous_hrr_kw,
		room.hrr_target_kw,
		dt,
		hrr_rise_tau_s,
		float(context.get("fire_hrr_fall_tau_s", 20.0))
	)
	if not latent_viable \
			and room.hrr_target_kw <= 0.0 \
			and room.hrr_kw < float(context.get("fire_extinction_hrr_kw", 0.0)) * 0.25:
		room.hrr_kw = 0.0

	var total_target_kw: float = maxf(
		0.0001,
		fresh_flame_target_kw + smolder_target_kw + pool_release_target_kw
	)
	var actual_pool_burn_kw: float = room.hrr_kw * pool_release_target_kw / total_target_kw
	actual_pool_burn_kw = minf(actual_pool_burn_kw, room.retained_unburned_MJ * 1000.0 / maxf(0.001, dt))
	var actual_solid_burn_kw: float = maxf(0.0, room.hrr_kw - actual_pool_burn_kw)
	room.retained_unburned_MJ = maxf(
		0.0,
		room.retained_unburned_MJ - actual_pool_burn_kw * dt / 1000.0
	)
	room.retained_unburned_MJ = maxf(
		0.0,
		room.retained_unburned_MJ - room.retained_unburned_MJ \
			* float(context.get("fire_unburned_decay_per_s", 0.0)) \
			* (1.0 + opening_signal * 1.5 + (1.0 - temp_signal) * 0.5) \
			* dt
	)

	var smoke_basis_multiplier: float = lerpf(
		1.0 + float(context.get("fire_smoke_basis_min_fraction", 0.0)),
		1.0,
		sqrt(room.o2_hrr_factor)
	)
	var retained_smoke_basis_kw: float = retained_generation_kw \
			* float(context.get("fire_retained_smoke_fraction", 0.38))
	var pool_smoke_basis_kw: float = actual_pool_burn_kw \
			* float(context.get("fire_pool_smoke_fraction", 0.42))
	var smoke_basis_kw: float = maxf(
		actual_solid_burn_kw,
		(fresh_flame_target_kw + smolder_target_kw) * smoke_basis_multiplier
	)
	smoke_basis_kw += retained_smoke_basis_kw + pool_smoke_basis_kw
	if not can_flame:
		if latent_viable:
			smoke_basis_kw = maxf(smoke_basis_kw, smolder_target_kw + retained_smoke_basis_kw)
		else:
			smoke_basis_kw = 0.0

	var smoke_yield_kg_per_MJ: float = lerpf(
		fire.smoke_yield_kg_per_MJ * float(context.get("fire_smoke_yield_low_o2_multiplier", 1.0)),
		fire.smoke_yield_kg_per_MJ,
		room.o2_hrr_factor
	)
	if not can_flame:
		smoke_yield_kg_per_MJ *= float(context.get("fire_smolder_smoke_multiplier", 1.0))

	var smoke_basis_MJ: float = smoke_basis_kw * dt / 1000.0
	var heat_release_MJ: float = room.hrr_kw * dt / 1000.0
	room.smoke_prod_kg_s = _compute_smoke_production_kg_s(smoke_basis_kw, smoke_yield_kg_per_MJ)

	var latent_timeout_s: float = float(
		context.get("fire_latent_extinction_delay_s", context.get("fire_extinction_delay_s", 0.0))
	)
	if not can_flame \
			and latent_viable \
			and room.fire_dormant_time_s >= latent_timeout_s \
			and room.retained_unburned_MJ < 0.5:
		return _extinguish_room_fire(room, fire)

	var oxygen_starved: bool = room.fire_time_s > 60.0 \
			and raw_o2_factor <= float(context.get("fire_starvation_o2_factor", 0.0)) \
			and room.retained_unburned_MJ < 0.5
	if not (not can_flame and latent_viable) \
			and (room.hrr_kw < float(context.get("fire_extinction_hrr_kw", 0.0)) or oxygen_starved) \
			and room.fire_time_s > 60.0:
		room.fire_low_hrr_time_s += dt
		if room.fire_low_hrr_time_s >= float(context.get("fire_extinction_delay_s", 0.0)):
			return _extinguish_room_fire(room, fire)
	else:
		room.fire_low_hrr_time_s = 0.0

	var combustion_completion_factor: float = clampf(
		fresh_flame_target_kw / maxf(0.001, solid_pyrolysis_kw),
		0.0,
		1.0
	)
	var combustion_quality: float = clampf(
		0.55 * room.o2_hrr_factor + 0.45 * combustion_completion_factor,
		0.0,
		1.0
	)
	var co_base_yield: float = float(context.get("co_base_yield_kg_per_MJ", 0.0))
	var co_max_yield: float = float(context.get("co_max_yield_kg_per_MJ", 0.0))
	var co_low_quality_yield: float = minf(
		co_base_yield * float(context.get("fire_co_low_quality_yield_multiplier", 8.0)),
		co_max_yield * float(context.get("fire_co_max_effective_fraction", 0.22))
	)
	var co_yield: float = lerpf(
		co_low_quality_yield,
		co_base_yield,
		sqrt(combustion_quality)
	)
	if not can_flame and latent_viable:
		co_yield *= float(context.get("fire_latent_co_yield_multiplier", 1.0))
	var retained_co_basis_kw: float = retained_generation_kw \
			* float(context.get("fire_retained_co_fraction", 0.08))
	var pool_co_basis_kw: float = actual_pool_burn_kw \
			* float(context.get("fire_pool_co_fraction", 0.40))
	var co_basis_kw: float = actual_solid_burn_kw + pool_co_basis_kw + retained_co_basis_kw
	if not can_flame and latent_viable:
		co_basis_kw = maxf(co_basis_kw, smolder_target_kw * 0.75 + retained_co_basis_kw)
	var co_basis_MJ: float = co_basis_kw * dt / 1000.0
	var generated_co_kg: float = co_yield * co_basis_MJ
	room.co_kg += generated_co_kg
	room.co_upper_kg += generated_co_kg

	var co2_yield: float = lerpf(
		float(context.get("co2_min_yield_kg_per_MJ", 0.0594)),
		float(context.get("co2_base_yield_kg_per_MJ", 0.0831)),
		room.o2_hrr_factor
	)
	room.co2_kg += co2_yield * maxf(heat_release_MJ, smoke_basis_MJ * 0.60)

	fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ - solid_fuel_demand_MJ)

	_sync_legacy_proxy_from_fire(room, fire, room.hrr_kw, can_flame)

	if fire.remaining_fuel_MJ <= 0.0 and room.retained_unburned_MJ <= 0.01:
		return _extinguish_room_fire(room, fire, true)

	if room.fire_time_s >= float(context.get("fire_max_active_s", 0.0)) \
			and room.retained_unburned_MJ <= 0.5:
		return _extinguish_room_fire(room, fire)

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


func get_room_heating_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if obj.state == FuelObjectModelScript.State.HEATING:
			count += 1
	return count


func get_room_pyrolyzing_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if obj.state == FuelObjectModelScript.State.PYROLYZING:
			count += 1
	return count


func get_room_passive_surface_temp_c(room: RoomModel) -> float:
	var proxy = _get_legacy_room_proxy(room)
	return proxy.surface_temp_c if proxy != null else 0.0


func get_room_passive_flux_kw_m2(room: RoomModel) -> float:
	var proxy = _get_legacy_room_proxy(room)
	return proxy.incident_heat_flux_kw_m2 if proxy != null else 0.0


func get_room_passive_ignition_flux_kw_m2(room: RoomModel) -> float:
	var proxy = _get_legacy_room_proxy(room)
	return proxy.ignition_flux_kw_m2 if proxy != null else 18.0


func is_room_passive_autoignite_ready(room: RoomModel) -> bool:
	var proxy = _get_legacy_room_proxy(room)
	return bool(proxy.autoignite_ready) if proxy != null else false


func update_passive_room_fuel(
	room: RoomModel,
	dt: float,
	ambient_c: float,
	context: Dictionary = {}
) -> bool:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return false

	if room.fire != null:
		return false

	if proxy.remaining_fuel_MJ <= 0.001:
		proxy.state = FuelObjectModelScript.State.BURNED_OUT
		proxy.hrr_kw = 0.0
		proxy.incident_heat_flux_kw_m2 = 0.0
		proxy.autoignite_ready = false
		return false

	var hot_fill_fraction: float = clampf(
		(room.height_m - clampf(room.thermal_layer_m, 0.0, room.height_m)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var smoke_fill_fraction: float = clampf(
		(room.height_m - clampf(room.h_layer_m, 0.0, room.height_m)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var coupled_fill_fraction: float = maxf(hot_fill_fraction, smoke_fill_fraction)
	var upper_influence: float = clampf(
		0.12 + 0.78 * coupled_fill_fraction,
		0.12,
		0.90
	)
	var upper_target_surface_temp_c: float = lerpf(room.temp_lower_c, room.temp_upper_c, upper_influence)
	var opening_gas_temp_c: float = maxf(
		room.temp_lower_c,
		float(context.get("opening_gas_temp_c", room.temp_lower_c))
	)
	var opening_engagement: float = clampf(
		float(context.get("opening_engagement", 0.0)),
		0.0,
		1.0
	)
	var adjacent_source_hrr_kw: float = maxf(
		0.0,
		float(context.get("adjacent_source_hrr_kw", 0.0))
	)
	var upper_radiation_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		room.temp_upper_c,
		proxy.surface_temp_c,
		0.82
	) * clampf(0.08 + 0.82 * coupled_fill_fraction, 0.08, 0.90)
	var doorway_radiation_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		opening_gas_temp_c,
		proxy.surface_temp_c,
		0.70
	) * opening_engagement * 0.85
	var layer_convective_flux_kw_m2: float = maxf(0.0, room.temp_upper_c - proxy.surface_temp_c) \
			* 0.006 \
			* coupled_fill_fraction
	var doorway_convective_flux_kw_m2: float = maxf(0.0, opening_gas_temp_c - proxy.surface_temp_c) \
			* lerpf(0.0, 0.018, opening_engagement)
	var flame_bonus_flux_kw_m2: float = minf(
		6.0,
		adjacent_source_hrr_kw * 0.0008 * opening_engagement
	)
	proxy.incident_heat_flux_kw_m2 = upper_radiation_flux_kw_m2 \
			+ doorway_radiation_flux_kw_m2 \
			+ layer_convective_flux_kw_m2 \
			+ doorway_convective_flux_kw_m2 \
			+ flame_bonus_flux_kw_m2

	var flux_ratio: float = clampf(
		proxy.incident_heat_flux_kw_m2 / maxf(1.0, proxy.ignition_flux_kw_m2),
		0.0,
		1.25
	)
	var opening_target_surface_temp_c: float = lerpf(
		upper_target_surface_temp_c,
		maxf(upper_target_surface_temp_c, opening_gas_temp_c),
		opening_engagement
	)
	var target_surface_temp_c: float = lerpf(
		upper_target_surface_temp_c,
		opening_target_surface_temp_c,
		clampf(0.25 + 0.55 * flux_ratio, 0.0, 1.0)
	)
	var heating_rate: float = clampf(dt / lerpf(180.0, 35.0, flux_ratio), 0.0, 1.0)
	var cooling_rate: float = clampf(dt / 240.0, 0.0, 1.0)
	if target_surface_temp_c >= proxy.surface_temp_c:
		proxy.surface_temp_c = lerpf(proxy.surface_temp_c, target_surface_temp_c, heating_rate)
	else:
		proxy.surface_temp_c = lerpf(proxy.surface_temp_c, target_surface_temp_c, cooling_rate)

	var heating_threshold_c: float = ambient_c + 35.0
	var pyrolysis_threshold_c: float = proxy.ignition_temp_c - 45.0
	var heating_flux_threshold_kw_m2: float = proxy.ignition_flux_kw_m2 * 0.30
	var pyrolysis_flux_threshold_kw_m2: float = proxy.ignition_flux_kw_m2 * 0.70

	var thermal_signal: float = clampf(
		inverse_lerp(heating_threshold_c, proxy.ignition_temp_c, proxy.surface_temp_c),
		0.0,
		1.0
	)
	var flux_signal: float = clampf(
		inverse_lerp(heating_flux_threshold_kw_m2, proxy.ignition_flux_kw_m2, proxy.incident_heat_flux_kw_m2),
		0.0,
		1.0
	)
	var preheat_signal: float = maxf(thermal_signal, flux_signal)

	if preheat_signal > 0.0:
		proxy.exposure_s += dt * lerpf(0.35, 1.35, preheat_signal)
	else:
		proxy.exposure_s = maxf(0.0, proxy.exposure_s - dt * 1.5)

	var pyrolysis_ready: bool = (
		proxy.surface_temp_c >= pyrolysis_threshold_c
		or proxy.incident_heat_flux_kw_m2 >= pyrolysis_flux_threshold_kw_m2
	) and proxy.exposure_s >= 30.0
	var autoignite_ready: bool = proxy.exposure_s >= 75.0 and (
		proxy.surface_temp_c >= proxy.ignition_temp_c
		or (
			proxy.surface_temp_c >= pyrolysis_threshold_c
			and proxy.incident_heat_flux_kw_m2 >= proxy.ignition_flux_kw_m2
		)
	)
	proxy.autoignite_ready = autoignite_ready

	if pyrolysis_ready:
		proxy.state = FuelObjectModelScript.State.PYROLYZING
	elif proxy.surface_temp_c >= heating_threshold_c \
			or proxy.incident_heat_flux_kw_m2 >= heating_flux_threshold_kw_m2:
		proxy.state = FuelObjectModelScript.State.HEATING
	else:
		proxy.state = FuelObjectModelScript.State.COLD

	proxy.hrr_kw = 0.0
	return autoignite_ready


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


func _smooth_state_value(
	current: float,
	target: float,
	dt: float,
	rise_tau_s: float,
	fall_tau_s: float
) -> float:
	var tau_s: float = rise_tau_s if target >= current else fall_tau_s
	if tau_s <= 0.000001:
		return target
	var blend: float = clampf(1.0 - exp(-dt / tau_s), 0.0, 1.0)
	return lerpf(current, target, blend)


func _estimate_radiative_flux_kw_m2(
	emitter_temp_c: float,
	receiver_temp_c: float,
	emissivity: float = 0.80
) -> float:
	var emitter_k: float = maxf(_celsius_to_kelvin(receiver_temp_c), _celsius_to_kelvin(emitter_temp_c))
	var receiver_k: float = _celsius_to_kelvin(receiver_temp_c)
	var sigma_kw_m2_k4: float = 5.670374419e-11
	return maxf(
		0.0,
		emissivity * sigma_kw_m2_k4 * (pow(emitter_k, 4.0) - pow(receiver_k, 4.0))
	)


func _celsius_to_kelvin(temp_c: float) -> float:
	return temp_c + 273.15


func _can_sustain_latent_fire(
	room: RoomModel,
	fire: FireModel,
	context: Dictionary,
	ambient_c: float
) -> bool:
	if room == null or fire == null:
		return false

	if room.retained_unburned_MJ >= 1.0:
		return true

	if fire.remaining_fuel_MJ <= float(context.get("fire_latent_min_remaining_fuel_MJ", 25.0)):
		return false

	var upper_hold_c: float = float(context.get("fire_latent_hold_upper_temp_c", ambient_c))
	var lower_hold_c: float = float(context.get("fire_latent_hold_lower_temp_c", ambient_c))
	return room.temp_upper_c >= upper_hold_c or room.temp_lower_c >= lower_hold_c


func _extinguish_room_fire(room: RoomModel, fire: FireModel, burned_out: bool = false) -> bool:
	if room == null:
		return false

	if burned_out:
		_mark_legacy_proxy_burned_out(room)
	elif fire != null:
		_sync_legacy_proxy_from_fire(room, fire, 0.0, false)

	room.hrr_kw = 0.0
	room.hrr_target_kw = 0.0
	room.smoke_prod_kg_s = 0.0
	room.fire = null
	room.fire_low_hrr_time_s = 0.0
	room.fire_dormant_time_s = 0.0
	if burned_out:
		room.retained_unburned_MJ = 0.0
	return false


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
	proxy.incident_heat_flux_kw_m2 = 0.0
	proxy.autoignite_ready = false
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
	proxy.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ + room.retained_unburned_MJ)
	proxy.hrr_kw = maxf(0.0, hrr_kw)
	proxy.incident_heat_flux_kw_m2 = 0.0
	proxy.autoignite_ready = false

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
	proxy.incident_heat_flux_kw_m2 = 0.0
	proxy.autoignite_ready = false
	proxy.state = FuelObjectModelScript.State.BURNED_OUT
