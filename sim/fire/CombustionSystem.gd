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

	# Si ya existe un proxy, no crear otro.
	if _get_legacy_room_proxy(room) != null:
		return

	if room.fuel_energy_MJ <= 0.0 and room.max_hrr_kw <= 0.0 and get_room_total_remaining_fuel_MJ(room) <= 0.0:
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
	_mark_room_ignition_object(room)

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
		room.pyrolysis_kw = 0.0
		room.burned_hrr_kw = 0.0
		room.unburned_generation_kw = 0.0
		room.flame_hrr_target_kw = 0.0
		room.smolder_hrr_target_kw = 0.0
		room.pool_release_hrr_target_kw = 0.0
		room.smoke_prod_kg_s = 0.0
		room.fire_smoldering = false
		_sync_legacy_proxy_idle(room)
		return false

	var fire: FireModel = room.fire
	var ambient_c: float = float(context.get("ambient_c", 20.0))
	var early_opening_signal: float = clampf(
		maxf(
			maxf(float(context.get("outside_open_factor", 0.0)), float(context.get("outside_open_path_factor", 0.0))),
			maxf(0.0, float(context.get("window_open_max", 0.0)))
		),
		0.0,
		1.0
	)
	var full_hrr_o2: float = lerpf(
		fire.o2_nominal,
		float(context.get("fire_o2_full_hrr_open", fire.o2_nominal)),
		early_opening_signal
	)
	# SF-1B: si fire_o2_upper_for_flame=true, usar o2_upper y umbral separado.
	var use_o2_upper: bool = bool(context.get("fire_o2_upper_for_flame", false))
	var o2_min_ref: float = float(context.get("fire_o2_upper_min_for_flame", fire.o2_min_for_flame)) \
			if use_o2_upper else fire.o2_min_for_flame
	# SF-2B: blend opt-in para capear HRR por O2 de capa superior.
	# 0.0 = sin cambio; 1.0 = effective_o2 = min(room.o2, room.o2_upper).
	var o2_upper_hrr_blend: float = clampf(float(context.get("fire_o2_upper_hrr_blend", 0.0)), 0.0, 1.0)
	# Phase 2C: opt-in para que el fuego use o2_lower (zona baja reabastecida por HVAC low-supply).
	# Default false = no-op. Activar solo en benchmark HVAC low-supply/high-return.
	var use_o2_lower: bool = bool(context.get("fire_o2_lower_for_flame", false))
	var o2_ref: float
	if use_o2_upper:
		o2_ref = room.o2_upper
	elif use_o2_lower:
		o2_ref = room.o2_lower
	else:
		o2_ref = lerpf(room.o2, minf(room.o2, room.o2_upper), o2_upper_hrr_blend)
	full_hrr_o2 = maxf(o2_min_ref + 0.001, full_hrr_o2)
	var raw_o2_factor: float = _compute_o2_factor(o2_ref, full_hrr_o2, o2_min_ref)
	var use_fds_extinction: bool = bool(context.get("fire_fds_extinction_enabled", false))
	var extinction_o2_limit: float = _compute_extinction_o2_limit(
		room,
		context,
		ambient_c,
		o2_min_ref
	)
	var extinction_factor: float = raw_o2_factor
	if use_fds_extinction:
		extinction_factor = _compute_extinction_factor(
			o2_ref,
			extinction_o2_limit,
			float(context.get("fire_fds_extinction_transition_width", 0.030))
		)
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

	# Si fire_o2_independent=true, el fuego sigue la curva t2 sin limitacion de O2.
	# Es un modo analitico ideal, no el criterio de extincion oxygen-limited de FDS.
	var o2_independent: bool = bool(context.get("fire_o2_independent", false))

	var o2_factor_target: float = extinction_factor if use_fds_extinction else raw_o2_factor
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

	var flame_possible_factor: float = extinction_factor
	if not use_fds_extinction:
		flame_possible_factor = clampf(
			inverse_lerp(
				o2_min_ref - 0.015,
				o2_min_ref + 0.025,
				o2_ref
			),
			0.0,
			1.0
		)
	var flame_drive: float = room.o2_hrr_factor * flame_possible_factor
	var latent_drive: float = 0.0
	if latent_viable:
		latent_drive = subvent_o2_floor * lerpf(0.35, 1.0, subvent_engagement)
	var pyrolysis_drive: float = maxf(flame_drive, latent_drive)
	var can_flame: bool = flame_drive > 0.08
	if use_fds_extinction and not can_flame and room.temp_upper_c > ambient_c:
		var hot_pyrolysis_floor: float = float(context.get("fire_fds_extinction_pyrolysis_floor", 0.0)) \
				* subvent_engagement \
				* (1.0 - flame_possible_factor)
		pyrolysis_drive = maxf(pyrolysis_drive, hot_pyrolysis_floor)

	if o2_independent:
		# Fuego prescrito: ignora limitacion O2, HRR sigue curva t2 sin restriccion.
		pyrolysis_drive = 1.0
		can_flame = true
		room.o2_hrr_factor = 1.0
	if can_flame or latent_viable:
		var fire_time_gain_factor: float = clampf(
			maxf(0.15 if latent_viable else 0.0, pyrolysis_drive),
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
	var feedback_o2_engagement: float = room.o2_hrr_factor if use_fds_extinction else clampf(
		inverse_lerp(
			o2_min_ref - 0.005,
			o2_min_ref + 0.035,
			o2_ref
		),
		0.0,
		1.0
	)
	rad_feedback = lerpf(1.0, rad_feedback, feedback_o2_engagement)
	ideal_hrr_kw *= rad_feedback

	var smolder_fraction: float = float(context.get("fire_smolder_hrr_fraction", 0.10))
	var latent_cap_basis_kw: float = minf(fire.max_hrr_kw, maxf(previous_hrr_kw, ideal_hrr_kw))
	var extinction_hrr_kw: float = float(context.get("fire_extinction_hrr_kw", 0.0))
	if not can_flame and latent_viable:
		var dormant_decay: float = clampf(
			inverse_lerp(45.0, 120.0, room.fire_dormant_time_s),
			0.0,
			1.0
		)
		latent_cap_basis_kw = lerpf(
			latent_cap_basis_kw,
			maxf(previous_hrr_kw, extinction_hrr_kw * 0.5),
			dormant_decay
		)
	var latent_cap_scale: float = lerpf(
		float(context.get("fire_latent_hrr_cap_min_fraction", 0.15)),
		float(context.get("fire_latent_hrr_cap_max_fraction", 1.0)),
		subvent_engagement
	)
	var residual_smolder_cap_kw: float = maxf(
		extinction_hrr_kw * 0.25,
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
		maxf(pyrolysis_drive, pyrolysis_floor_fraction),
		0.0,
		1.0
	)
	var solid_pyrolysis_kw: float = ideal_hrr_kw * solid_pyrolysis_fraction
	var fresh_flame_target_kw: float = 0.0
	if can_flame:
		fresh_flame_target_kw = minf(
			solid_pyrolysis_kw,
			ideal_hrr_kw * clampf(flame_drive, 0.0, 1.0)
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
	if not can_flame and latent_viable:
		# En fase latente no seguimos cargando la bolsa de gases retenidos.
		retained_generation_kw = 0.0

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

	var local_opening_signal: float = maxf(
		float(context.get("outside_open_factor", 0.0)),
		maxf(0.0, float(context.get("window_open_max", 0.0)))
	)
	var opening_signal: float = clampf(
		maxf(local_opening_signal, float(context.get("outside_open_path_factor", 0.0))),
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
	# Temporizador de re-armado del backdraft
	if room.backdraft_cooldown_s > 0.0:
		room.backdraft_cooldown_s = maxf(0.0, room.backdraft_cooldown_s - dt)
	if room.retained_unburned_MJ > 0.001 and opening_signal > 0.01:
		var release_drive: float = room.ventilation_response_factor * maxf(0.15, oxygen_recovery_signal)

		# ── LFL/UFL: comprobar que la mezcla gas/aire está en rango inflamable ──────
		# SF-AUD-013: masa de gas no quemado → volumen a densidad del gas de pirólisis.
		# Fracción volumétrica = vol_gas / vol_compartimento.
		# LFL ≈ 2% y UFL ≈ 20% para gas de pirólisis subventilado (CO/HC mix).
		var fuel_heat_kj_kg: float = float(context.get("fire_backdraft_fuel_heat_kj_kg", 10000.0))
		var fuel_density: float = maxf(0.1, float(context.get("fire_backdraft_fuel_gas_density", 0.8)))
		var fuel_kg: float = room.retained_unburned_MJ * 1000.0 / maxf(1.0, fuel_heat_kj_kg)
		var fuel_vol_m3: float = fuel_kg / fuel_density
		var room_vol: float = maxf(0.1, room.volume_m3())
		var fuel_vol_frac: float = fuel_vol_m3 / room_vol
		room.unburned_gas_vol_frac = fuel_vol_frac
		var lfl: float = float(context.get("fire_backdraft_lfl", 0.02))
		var ufl: float = float(context.get("fire_backdraft_ufl", 0.20))
		var mixture_flammable: bool = fuel_vol_frac >= lfl and fuel_vol_frac <= ufl

		var backdraft_ready: bool = room.retained_unburned_MJ \
				>= float(context.get("fire_backdraft_pool_threshold_MJ", 8.0)) \
				and room.o2 <= float(context.get("fire_backdraft_o2_max", 0.13)) \
				and room.temp_upper_c >= float(context.get("fire_backdraft_temp_min_c", 180.0)) \
				and opening_signal > 0.08 \
				and mixture_flammable
		if backdraft_ready:
			release_drive *= float(context.get("fire_backdraft_release_boost", 1.35))
			# Disparo del evento backdraft: acumulación de inquémados + entrada súbita de O2
			if not room.backdraft_active and room.backdraft_cooldown_s <= 0.0:
				room.backdraft_triggered = true
				room.backdraft_time_s = room.fire_time_s
				room.backdraft_active = true
				room.backdraft_phase_time_s = 0.0
				room.backdraft_cooldown_s = float(context.get("fire_backdraft_cooldown_s", 180.0))
				# Sobrepresión de deflagración instantánea — SF-AUD-013.
				# La combustión explosiva del gas acumulado genera una onda de
				# sobrepresión (ref: NFPA 921 §23; NIST backdraft experiments).
				var def_pa: float = float(context.get(
					"fire_backdraft_deflagration_overpressure_pa", 500.0
				))
				room.overpressure_pa += def_pa

		# M7: solo liberar pool cuando hay suficiente O₂ para quemar.
		# Con O₂ < umbral de backdraft, el pool acumula gas sin quemar hasta que
		# una apertura introduce O₂ y dispara el backdraft.
		var o2_allows_pool_burn: bool = room.o2 >= float(context.get("fire_backdraft_o2_max", 0.13))
		if o2_allows_pool_burn:
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
	room.pyrolysis_kw = maxf(0.0, solid_pyrolysis_kw)
	room.unburned_generation_kw = maxf(0.0, retained_generation_kw)
	room.flame_hrr_target_kw = maxf(0.0, fresh_flame_target_kw)
	room.smolder_hrr_target_kw = maxf(0.0, smolder_target_kw)
	room.pool_release_hrr_target_kw = maxf(0.0, pool_release_target_kw)
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
	room.burned_hrr_kw = maxf(0.0, room.hrr_kw)

	# Backdraft: fase explosiva — pico de HRR con envolvente sinusoidal.
	# Gottuk (1992): backdraft genera picos de HRR 3-6× el máximo pre-extinción en <15 s.
	if room.backdraft_active:
		room.backdraft_phase_time_s += dt
		var bd_duration: float = float(context.get("fire_backdraft_duration_s", 12.0))
		if room.backdraft_phase_time_s >= bd_duration:
			room.backdraft_active = false
		else:
			var bd_progress: float = room.backdraft_phase_time_s / bd_duration
			var bd_envelope: float = sin(bd_progress * PI)  # 0→1→0 en [0, dur]
			var bd_hrr_kw: float = fire.max_hrr_kw \
					* float(context.get("fire_backdraft_hrr_multiplier", 4.0)) \
					* bd_envelope
			room.hrr_kw = maxf(room.hrr_kw, bd_hrr_kw)
			room.hrr_target_kw = maxf(room.hrr_target_kw, bd_hrr_kw)
			room.burned_hrr_kw = maxf(0.0, room.hrr_kw)

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

	# Backdraft: consume retained fuel explosivamente (bypass del límite pool_release_max_fraction)
	if room.backdraft_active and room.retained_unburned_MJ > 0.0:
		var bd_consume_MJ: float = minf(
			room.retained_unburned_MJ,
			room.hrr_kw * dt / 1000.0 * 0.60
		)
		room.retained_unburned_MJ = maxf(0.0, room.retained_unburned_MJ - bd_consume_MJ)

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

	var base_smoke_yield_kg_per_MJ: float = _resolve_room_smoke_yield_kg_per_MJ(
		room,
		fire.smoke_yield_kg_per_MJ
	)
	var smoke_yield_kg_per_MJ: float = lerpf(
		base_smoke_yield_kg_per_MJ * float(context.get("fire_smoke_yield_low_o2_multiplier", 1.0)),
		base_smoke_yield_kg_per_MJ,
		room.o2_hrr_factor
	)
	if not can_flame:
		smoke_yield_kg_per_MJ *= float(context.get("fire_smolder_smoke_multiplier", 1.0))

	var smoke_basis_MJ: float = smoke_basis_kw * dt / 1000.0
	var heat_release_MJ: float = room.hrr_kw * dt / 1000.0
	room.smoke_prod_kg_s = _compute_smoke_production_kg_s(smoke_basis_kw, smoke_yield_kg_per_MJ)
	# SF-AUD-008: fracción de smoke_kg que es soot ópticamente activo (K_m = 8700 m²/kg).
	room.soot_fraction = _resolve_room_soot_fraction(room, 1.0)
	# SF-AUD-015: fracción radiativa bien ventilada por combustible (-1.0 = usar global del motor).
	room.chi_rad_normal = _resolve_room_chi_rad_normal(room, -1.0)

	var latent_timeout_s: float = float(
		context.get("fire_latent_extinction_delay_s", context.get("fire_extinction_delay_s", 0.0))
	)
	if not can_flame \
			and latent_viable \
			and room.fire_dormant_time_s >= latent_timeout_s:
		if room.retained_unburned_MJ < 0.5 or room.hrr_kw <= extinction_hrr_kw:
			return _extinguish_room_fire(room, fire)

	var extinction_delay_s: float = float(context.get("fire_extinction_delay_s", 0.0))
	if not can_flame \
			and not latent_viable \
			and room.fire_dormant_time_s >= extinction_delay_s:
		return _extinguish_room_fire(room, fire)

	var starvation_factor: float = extinction_factor if use_fds_extinction else raw_o2_factor
	var oxygen_starved: bool = room.fire_time_s > 60.0 \
			and starvation_factor <= float(context.get("fire_starvation_o2_factor", 0.0)) \
			and room.retained_unburned_MJ < 0.5
	var heat_release_collapsed: bool = room.hrr_target_kw <= extinction_hrr_kw * 0.25
	if not (not can_flame and latent_viable) \
			and (room.hrr_kw < extinction_hrr_kw or oxygen_starved or heat_release_collapsed) \
			and room.fire_time_s > 60.0:
		room.fire_low_hrr_time_s += dt
		if room.fire_low_hrr_time_s >= extinction_delay_s:
			return _extinguish_room_fire(room, fire)
	else:
		room.fire_low_hrr_time_s = 0.0

	var combustion_completion_factor: float = clampf(
		fresh_flame_target_kw / maxf(0.001, solid_pyrolysis_kw),
		0.0,
		1.0
	)
	# Equivalence ratio φ: cuantas veces mas combustible se gasifica del que puede
	# quemarse estequiometricamente con el O2 disponible.
	# φ=1 → combustion completa (bien ventilado).
	# φ>1 → subventilado → CO y soot aumentan drasticamente.
	# Para smoldering (sin llama): φ fijo alto para reproducir emision de CO elevada.
	# Referencia: Beyler (1986) SFPE; Gottuk & Roby, SFPE Handbook §3.4;
	# Pitts, NIST TN 1603 (especies en fuegos ISO 9705 subventilados).
	var phi: float
	if can_flame:
		# φ = razón de combustible disponible / capacidad de combustión con O2 actual.
		# Usar o2_hrr_factor (suavizado, 0-1 según O2 disponible) como proxy:
		# φ=1 cuando O2=nominal (bien ventilado), φ→10 cuando O2→o2_min_for_flame.
		# Beyler (1986): CO aumenta exponencialmente cuando φ>1 (subventilado).
		phi = clampf(1.0 / maxf(0.01, room.o2_hrr_factor), 1.0, 10.0)
	else:
		# Smoldering: combustion muy incompleta, phi efectiva alta
		phi = float(context.get("fire_smolder_phi", 4.0))
	var co_base_yield: float = _resolve_room_co_yield_kg_per_MJ(
		room,
		float(context.get("co_base_yield_kg_per_MJ", 0.0))
	)
	var co_max_yield: float = float(context.get("co_max_yield_kg_per_MJ", 0.0))
	# CO yield sube exponencialmente con phi para phi > 1.
	# y_CO = y_CO_base * exp(k * (phi - 1)), con k = fire_co_phi_rate.
	# k=2.0 → ~7x a phi=2, ~55x a phi=3, capeado en co_max_yield.
	var k_phi_co: float = float(context.get("fire_co_phi_rate", 2.0))
	var co_yield: float = clampf(
		co_base_yield * exp(k_phi_co * (phi - 1.0)),
		co_base_yield,
		co_max_yield
	)
	# Phase 2: CO vent-limited via o2_upper (Beyler 1986, NIST TN 1603).
	# Cuando el O2 de la zona superior cae bajo el umbral, la combustión en la
	# interfaz upper/lower genera CO masivamente (fuego subventilado real).
	# El engagement es suave: 0 % a o2_upper=threshold, 100 % a o2_upper=threshold/2.
	var co_vent_threshold: float = float(context.get("fire_co_vent_limited_o2_threshold", 0.12))
	var co_vent_multiplier: float = float(context.get("fire_co_vent_limited_multiplier", 1.0))
	if can_flame and co_vent_multiplier > 1.0 and room.o2_upper < co_vent_threshold:
		var vent_engagement: float = clampf(
			inverse_lerp(co_vent_threshold, co_vent_threshold * 0.5, room.o2_upper),
			0.0,
			1.0
		)
		co_yield = lerpf(co_yield, co_yield * co_vent_multiplier, vent_engagement)
		co_yield = minf(co_yield, co_max_yield * co_vent_multiplier)
	if not can_flame and latent_viable:
		co_yield *= float(context.get("fire_latent_co_yield_multiplier", 1.0))
	# Permite fijar un yield constante desde el caso (ej. para comparación CFAST que
	# usa CO_YIELD fijo por kg de combustible sin escalar con la relación de equivalencia).
	var co_yield_force: float = float(context.get("fire_co_yield_force_kg_per_MJ", -1.0))
	if co_yield_force >= 0.0:
		co_yield = co_yield_force
	var retained_co_basis_kw: float = retained_generation_kw \
			* float(context.get("fire_retained_co_fraction", 0.08))
	var pool_co_basis_kw: float = actual_pool_burn_kw \
			* float(context.get("fire_pool_co_fraction", 0.40))
	var co_basis_kw: float = actual_solid_burn_kw + pool_co_basis_kw + retained_co_basis_kw
	if not can_flame and latent_viable:
		co_basis_kw = maxf(co_basis_kw, smolder_target_kw * 0.75 + retained_co_basis_kw)
	var co_basis_MJ: float = co_basis_kw * dt / 1000.0
	var generated_co_kg: float = co_yield * co_basis_MJ
	# room.co_kg / co_upper_kg se añaden más abajo, tras el balance de C (SF-AUD-032).

	# HCN yield: tambien aumenta con phi (mas combustion incompleta = mas HCN).
	# SF-AUD-006: el yield base se resuelve por combustible segun su contenido de N.
	# Madera ~0.00004, PU flexible ~0.001-0.004, Nylon ~0.003-0.010 kg/MJ (ISO 19706).
	var hcn_global_base: float = float(context.get("hcn_base_yield_kg_per_MJ", 0.0))
	var hcn_base_yield: float = _resolve_room_hcn_base_yield_kg_per_MJ(room, hcn_global_base)
	# El maximo escala proporcionalmente: si un objeto N-rico tiene base 25x mayor,
	# su maximo tambien es 25x mayor (mantiene la relacion base/max = 1/6.25).
	var hcn_global_max: float = float(context.get("hcn_max_yield_kg_per_MJ", 0.0))
	var hcn_max_yield: float = maxf(
		hcn_global_max,
		hcn_base_yield * (hcn_global_max / maxf(hcn_global_base, 0.000001))
	)
	# HCN se acumula en generated_hcn_kg y se aplica DESPUÉS del balance de C (SF-AUD-032).
	var generated_hcn_kg: float = 0.0
	if hcn_base_yield > 0.0:
		var hcn_yield: float = clampf(
			hcn_base_yield * exp(k_phi_co * (phi - 1.0)),
			hcn_base_yield,
			hcn_max_yield
		)
		generated_hcn_kg = hcn_yield * co_basis_MJ

	# HCl, acroleína, formaldehído — SF-AUD-018 (FEC irritantes, ISO 13571 §A.3).
	# Default yield = 0.0 → retrocompatible. Solo activos si el combustible tiene Cl / es PU/madera.
	# HCl: solo materiales con Cl (PVC). No aumenta con phi (no es producto de combustion incompleta).
	var hcl_yield: float = _resolve_room_irritant_yield_kg_per_MJ(room, "hcl_yield_kg_per_MJ", 0.0)
	if hcl_yield > 0.0:
		room.hcl_kg += hcl_yield * co_basis_MJ
	# Acroleína y formaldehído aumentan con combustión incompleta (phi > 1), como CO.
	var acrolein_yield: float = _resolve_room_irritant_yield_kg_per_MJ(room, "acrolein_yield_kg_per_MJ", 0.0)
	if acrolein_yield > 0.0:
		var acrolein_yield_eff: float = clampf(
			acrolein_yield * exp(k_phi_co * (phi - 1.0) * 0.7),
			acrolein_yield,
			acrolein_yield * 4.0
		)
		room.acrolein_kg += acrolein_yield_eff * co_basis_MJ
	var formaldehyde_yield: float = _resolve_room_irritant_yield_kg_per_MJ(room, "formaldehyde_yield_kg_per_MJ", 0.0)
	if formaldehyde_yield > 0.0:
		var formaldehyde_yield_eff: float = clampf(
			formaldehyde_yield * exp(k_phi_co * (phi - 1.0) * 0.5),
			formaldehyde_yield,
			formaldehyde_yield * 3.0
		)
		room.formaldehyde_kg += formaldehyde_yield_eff * co_basis_MJ

	# CO2 decrece a medida que mas carbono va a CO en lugar de CO2.
	# Balance aproximado de carbono: a phi=3, ~40% del carbono forma CO en vez de CO2.
	# Lineal: y_CO2 = lerp(co2_min, co2_base, max(0, 1 - (phi-1)/co2_phi_decay_rate)).
	# co2_phi_decay_rate=2.5 → y_CO2 llega al minimo en phi=3.5 (Pitts, NIST TN 1603).
	# SF-AUD-005: co2_base puede ser por combustible (co2_yield_kg_per_MJ en FuelObjectModel).
	# co2_min escala proporcionalmente al base para mantener la relacion min/base constante.
	var co2_base_global: float = float(context.get("co2_base_yield_kg_per_MJ", 0.0831))
	var co2_base: float = _resolve_room_co2_yield_kg_per_MJ(room, co2_base_global)
	var co2_min_global: float = float(context.get("co2_min_yield_kg_per_MJ", 0.0594))
	var co2_min: float = co2_base * (co2_min_global / maxf(0.0001, co2_base_global))
	var co2_phi_t: float = clampf(1.0 - (phi - 1.0) / float(context.get("co2_phi_decay_rate", 2.5)), 0.0, 1.0)
	var co2_yield: float = lerpf(co2_min, co2_base, co2_phi_t)
	var generated_co2_kg: float = co2_yield * maxf(heat_release_MJ, smoke_basis_MJ * 0.60)

	# SF-AUD-032: balance elemental de carbono.
	# El total de C en productos gaseosos (CO + CO₂ + HCN) no puede superar el C
	# disponible en el combustible sólido quemado en este paso.
	# Referencia: NFPA 921 §5.5; SFPE Handbook Table 3.4-1; Pitts NIST TN 1603.
	# fuel_c_kg_per_MJ ≈ carbono disponible por MJ liberado (madera=0.027, PU=0.024).
	# Nota: el carbono en soot/humo se contabiliza por separado en SmokeModel; aquí
	# se conservan las especies gaseosas principales que forman el gas tóxico de capas.
	var c_per_MJ: float = float(context.get("fuel_c_kg_per_MJ", 0.027))
	var c_avail_kg: float = solid_fuel_demand_MJ * c_per_MJ
	var c_in_co: float = generated_co_kg * (12.0 / 28.0)
	var c_in_co2: float = generated_co2_kg * (12.0 / 44.0)
	var c_in_hcn: float = generated_hcn_kg * (12.0 / 27.0)
	var c_total: float = c_in_co + c_in_co2 + c_in_hcn
	var c_in_soot: float = room.smoke_prod_kg_s * dt * 0.87
	# SF-CBAL: registrar el exceso real solicitado por los yields ANTES del clamp.
	room.c_preclamp_excess_kg += maxf(0.0, c_total + c_in_soot - c_avail_kg)
	if c_avail_kg > 0.0 and c_total > c_avail_kg:
		var c_scale: float = c_avail_kg / c_total
		generated_co_kg *= c_scale
		generated_co2_kg *= c_scale
		generated_hcn_kg *= c_scale
	# Fracción de carbono POST-clamp (diagnóstico SF-AUD-032).
	# Siempre ≤ 1.0; confirma que la conservación se cumple paso a paso.
	if c_avail_kg > 0.0:
		var c_produced: float = generated_co_kg * (12.0 / 28.0) \
				+ generated_co2_kg * (12.0 / 44.0) \
				+ generated_hcn_kg * (12.0 / 27.0)
		room.c_balance_frac = c_produced / c_avail_kg
	else:
		room.c_balance_frac = 0.0

	# SF-CBAL: la fuente canónica es el carbono consumido del combustible PRE-clamp.
	# La fracción no representada por especies se mantiene como producto no modelado.
	var c_products_postclamp: float = generated_co_kg * (12.0 / 28.0) \
			+ generated_co2_kg * (12.0 / 44.0) \
			+ generated_hcn_kg * (12.0 / 27.0) \
			+ c_in_soot
	room.c_burned_total_kg += c_avail_kg
	room.c_untracked_products_kg += maxf(0.0, c_avail_kg - c_products_postclamp)
	room.c_postclamp_excess_kg += maxf(0.0, c_products_postclamp - c_avail_kg)

	# Phase 2G — término fuente CO zona lower en generación (experimental, default OFF).
	# Cuando flag ON: una fracción de generated_co_kg se asigna al lower implícito;
	# co_kg total no cambia — sólo co_upper_kg recibe (1 - fracción) * generated_co_kg.
	var _p2g_upper_frac: float = 1.0
	if bool(context.get("phase2g_co_lower_source_enabled", false)):
		var _p2g_frac: float = float(context.get("phase2g_co_lower_source_fraction", 0.0))
		var _p2g_guard: String = String(context.get("phase2g_co_lower_source_guard", "fire_room_only"))
		var _p2g_apply: bool = false
		match _p2g_guard:
			"only_when_hot_layer_above_1_8m":
				_p2g_apply = float(context.get("hot_layer_interface_m", 2.5)) > 1.8
			_: # "fire_room_only" y "all_rooms_with_fire" — siempre aplica en sala con fuego
				_p2g_apply = true
		if _p2g_apply:
			_p2g_upper_frac = 1.0 - clampf(_p2g_frac, 0.0, 1.0)
	room.co_kg += generated_co_kg
	room.co_upper_kg += generated_co_kg * _p2g_upper_frac
	room.co2_kg += generated_co2_kg
	room.co2_upper_kg += generated_co2_kg  # generado en capa superior (2026-05-17)
	room.hcn_kg += generated_hcn_kg
	room.hcn_upper_kg += generated_hcn_kg  # generado en capa superior (2026-05-17)

	fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ - solid_fuel_demand_MJ)
	_sync_explicit_objects_from_active_fire(
		room,
		actual_solid_burn_kw,
		solid_fuel_demand_MJ,
		can_flame,
		dt,
		context
	)

	_sync_legacy_proxy_from_fire(room, fire, room.hrr_kw, can_flame)

	# Actualizar flag de smoldering para UI y exportación.
	# "smoldering" = fuego latente activo (sin llama) con emisión de humo/CO visible.
	room.fire_smoldering = (not can_flame) and latent_viable and (room.hrr_kw > 0.5)

	if fire.remaining_fuel_MJ <= 0.0 and room.retained_unburned_MJ <= 0.01:
		return _extinguish_room_fire(room, fire, true)

	if room.fire_time_s >= float(context.get("fire_max_active_s", 0.0)) \
			and room.retained_unburned_MJ <= 0.5:
		return _extinguish_room_fire(room, fire)

	return true


func is_any_object_autoignite_ready(room: RoomModel) -> bool:
	if room == null:
		return false
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if bool(obj.autoignite_ready):
			return true
	return false


func get_room_total_remaining_fuel_MJ(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var total_MJ: float = 0.0
	var ignore_legacy_proxy: bool = _has_explicit_fuel_objects(room)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if ignore_legacy_proxy and _is_legacy_room_proxy(obj):
			continue
		total_MJ += maxf(0.0, obj.remaining_fuel_MJ)
	return total_MJ


func get_room_total_max_hrr_kw(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var total_kw: float = 0.0
	var ignore_legacy_proxy: bool = _has_explicit_fuel_objects(room)
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if ignore_legacy_proxy and _is_legacy_room_proxy(obj):
			continue
		total_kw += maxf(0.0, obj.max_hrr_kw)
	return total_kw


func get_room_legacy_proxy_remaining_fuel_MJ(room: RoomModel) -> float:
	var proxy = _get_legacy_room_proxy(room)
	if proxy == null:
		return 0.0
	return maxf(0.0, proxy.remaining_fuel_MJ)


func get_room_active_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.PYROLYZING or obj.state == FuelObjectModelScript.State.FLAMING:
			count += 1
	return count


func get_room_heating_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.HEATING:
			count += 1
	return count


func get_room_pyrolyzing_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.PYROLYZING:
			count += 1
	return count


func get_room_flaming_object_count(room: RoomModel) -> int:
	if room == null:
		return 0

	var count: int = 0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.state == FuelObjectModelScript.State.FLAMING:
			count += 1
	return count


func get_room_passive_surface_temp_c(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return obj.surface_temp_c if obj != null else 0.0


func get_room_passive_flux_kw_m2(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return obj.incident_heat_flux_kw_m2 if obj != null else 0.0


func get_room_passive_ignition_flux_kw_m2(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return obj.ignition_flux_kw_m2 if obj != null else 18.0


func is_room_passive_autoignite_ready(room: RoomModel) -> bool:
	return is_any_object_autoignite_ready(room)


func generalize_room_combustion_after_flashover(room: RoomModel) -> void:
	if room == null or not _has_explicit_fuel_objects(room):
		return

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		obj.state = FuelObjectModelScript.State.FLAMING
		obj.surface_temp_c = maxf(obj.surface_temp_c, obj.ignition_temp_c + 80.0)
		obj.exposure_s = maxf(obj.exposure_s, 90.0)
		obj.autoignite_ready = false
		if String(obj.ignited_by_object_id).is_empty():
			obj.ignited_by_object_id = "flashover"


func get_room_dominant_fuel_object_id(room: RoomModel) -> String:
	var obj = _get_dominant_fuel_object(room)
	return String(obj.id) if obj != null else ""


func get_room_dominant_fuel_object_name(room: RoomModel) -> String:
	var obj = _get_dominant_fuel_object(room)
	return String(obj.name) if obj != null else ""


func get_room_dominant_fuel_object_state(room: RoomModel) -> String:
	var obj = _get_dominant_fuel_object(room)
	return fuel_object_state_to_string(int(obj.state)) if obj != null else "none"


func get_room_dominant_fuel_object_exposure_s(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return float(obj.exposure_s) if obj != null else 0.0


func get_room_dominant_fuel_object_remaining_MJ(room: RoomModel) -> float:
	var obj = _get_dominant_fuel_object(room)
	return maxf(0.0, obj.remaining_fuel_MJ) if obj != null else 0.0


func fuel_object_state_to_string(state: int) -> String:
	match state:
		FuelObjectModelScript.State.COLD:
			return "cold"
		FuelObjectModelScript.State.HEATING:
			return "heating"
		FuelObjectModelScript.State.PYROLYZING:
			return "pyrolyzing"
		FuelObjectModelScript.State.FLAMING:
			return "flaming"
		FuelObjectModelScript.State.DECAYING:
			return "decaying"
		FuelObjectModelScript.State.BURNED_OUT:
			return "burned_out"
		_:
			return "unknown"


func update_passive_room_fuel(
	room: RoomModel,
	dt: float,
	ambient_c: float,
	context: Dictionary = {}
) -> bool:
	if room == null:
		return false

	if room.fire != null:
		return false

	ensure_room_fuel_objects(room)
	var any_autoignite_ready: bool = false
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if _update_passive_fuel_object(room, obj, dt, ambient_c, context):
			any_autoignite_ready = true

	return any_autoignite_ready


func _update_passive_fuel_object(
	room: RoomModel,
	obj,
	dt: float,
	ambient_c: float,
	context: Dictionary = {}
) -> bool:
	if obj == null:
		return false

	if obj.remaining_fuel_MJ <= 0.001:
		obj.state = FuelObjectModelScript.State.BURNED_OUT
		obj.hrr_kw = 0.0
		obj.incident_heat_flux_kw_m2 = 0.0
		obj.autoignite_ready = false
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
	var smoke_layer_depth_m: float = maxf(0.0, room.height_m - clampf(room.h_layer_m, 0.0, room.height_m))
	var smoke_volume_m3: float = maxf(0.1, room.floor_area_m2() * maxf(0.1, smoke_layer_depth_m))
	var smoke_density_signal: float = clampf(room.smoke_kg / maxf(0.02, smoke_volume_m3 * 0.08), 0.0, 1.0)
	var smoke_radiation_factor: float = maxf(smoke_fill_fraction, smoke_density_signal)
	var coupled_fill_fraction: float = maxf(hot_fill_fraction, smoke_fill_fraction)
	var object_height_factor: float = clampf(
		inverse_lerp(0.0, maxf(0.1, room.height_m), float(obj.elevation_m)),
		0.0,
		1.0
	)
	var upper_influence: float = clampf(
		0.10 + 0.72 * coupled_fill_fraction + 0.12 * object_height_factor,
		0.12,
		0.90
	)
	var upper_target_surface_temp_c: float = lerpf(
		room.temp_lower_c,
		room.temp_upper_c,
		upper_influence
	)
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
		obj.surface_temp_c,
		0.82
	) * clampf(0.08 + 0.60 * hot_fill_fraction + 0.28 * smoke_radiation_factor, 0.08, 0.96)
	var doorway_radiation_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		opening_gas_temp_c,
		obj.surface_temp_c,
		0.70
	) * opening_engagement * 0.85
	var layer_convective_flux_kw_m2: float = maxf(0.0, room.temp_upper_c - obj.surface_temp_c) \
			* 0.006 \
			* coupled_fill_fraction
	var doorway_convective_flux_kw_m2: float = maxf(0.0, opening_gas_temp_c - obj.surface_temp_c) \
			* lerpf(0.0, 0.018, opening_engagement)
	var flame_bonus_flux_kw_m2: float = minf(
		6.0,
		adjacent_source_hrr_kw * 0.0008 * opening_engagement
	)
	# Radiación directa desde sala adyacente en llamas — independiente del flujo convectivo.
	# Cubre la fase temprana cuando la capa caliente no ha alcanzado el dintel todavía.
	var adjacent_fire_temp_c: float = maxf(
		room.temp_lower_c,
		float(context.get("adjacent_fire_temp_c", 0.0))
	)
	var adjacent_rad_engagement: float = clampf(
		float(context.get("adjacent_rad_engagement", 0.0)), 0.0, 0.50
	)
	var direct_fire_rad_flux_kw_m2: float = _estimate_radiative_flux_kw_m2(
		adjacent_fire_temp_c, obj.surface_temp_c, 0.80
	) * adjacent_rad_engagement
	obj.incident_heat_flux_kw_m2 = upper_radiation_flux_kw_m2 \
			+ doorway_radiation_flux_kw_m2 \
			+ layer_convective_flux_kw_m2 \
			+ doorway_convective_flux_kw_m2 \
			+ flame_bonus_flux_kw_m2 \
			+ direct_fire_rad_flux_kw_m2

	var flux_ratio: float = clampf(
		obj.incident_heat_flux_kw_m2 / maxf(1.0, obj.ignition_flux_kw_m2),
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
	var exposed_area_factor: float = clampf(
		maxf(0.1, float(obj.exposed_area_m2)) / maxf(0.1, float(obj.footprint_m2)),
		0.35,
		2.0
	)
	var heating_rate: float = clampf(dt / maxf(5.0, lerpf(210.0, 35.0, flux_ratio)) * sqrt(exposed_area_factor), 0.0, 1.0)
	var cooling_rate: float = clampf(dt / 240.0, 0.0, 1.0)
	if target_surface_temp_c >= obj.surface_temp_c:
		obj.surface_temp_c = lerpf(obj.surface_temp_c, target_surface_temp_c, heating_rate)
	else:
		obj.surface_temp_c = lerpf(obj.surface_temp_c, target_surface_temp_c, cooling_rate)

	var heating_threshold_c: float = ambient_c + 35.0
	var pyrolysis_threshold_c: float = obj.ignition_temp_c - 45.0
	var heating_flux_threshold_kw_m2: float = obj.ignition_flux_kw_m2 * 0.30
	var pyrolysis_flux_threshold_kw_m2: float = obj.ignition_flux_kw_m2 * 0.70

	var thermal_signal: float = clampf(
		inverse_lerp(heating_threshold_c, obj.ignition_temp_c, obj.surface_temp_c),
		0.0,
		1.0
	)
	var flux_signal: float = clampf(
		inverse_lerp(heating_flux_threshold_kw_m2, obj.ignition_flux_kw_m2, obj.incident_heat_flux_kw_m2),
		0.0,
		1.0
	)
	var preheat_signal: float = maxf(thermal_signal, flux_signal)

	if preheat_signal > 0.0:
		obj.exposure_s += dt * lerpf(0.35, 1.35, preheat_signal)
	else:
		obj.exposure_s = maxf(0.0, obj.exposure_s - dt * 1.5)

	var pyrolysis_ready: bool = (
		obj.surface_temp_c >= pyrolysis_threshold_c
		or obj.incident_heat_flux_kw_m2 >= pyrolysis_flux_threshold_kw_m2
	) and obj.exposure_s >= 30.0
	var autoignite_ready: bool = obj.exposure_s >= 75.0 and (
		obj.surface_temp_c >= obj.ignition_temp_c
		or (
			pyrolysis_ready
			and obj.incident_heat_flux_kw_m2 >= obj.ignition_flux_kw_m2
		)
	)
	obj.autoignite_ready = autoignite_ready

	if pyrolysis_ready:
		obj.state = FuelObjectModelScript.State.PYROLYZING
	elif obj.surface_temp_c >= heating_threshold_c \
			or obj.incident_heat_flux_kw_m2 >= heating_flux_threshold_kw_m2:
		obj.state = FuelObjectModelScript.State.HEATING
	else:
		obj.state = FuelObjectModelScript.State.COLD

	obj.hrr_kw = 0.0
	obj.t_ignition_s = -1.0

	# SF-AUD-016: MLR física (Tewarson): ṁ = (q_inc − q_crit) × A_eff / ΔHg; hrr = ṁ × ΔHc.
	# Solo activa cuando ΔHg y ΔHc están configurados explícitamente (> 0); sentinel -1.0 = modelo heredado.
	if obj.state == FuelObjectModelScript.State.PYROLYZING \
			and float(obj.heat_of_gasification_kj_kg) > 0.0 \
			and float(obj.heat_of_combustion_kj_kg) > 0.0:
		# SF-AUD-034: LOI — si O2 de sala < LOI, el material no puede arder en aire empobrecido.
		if float(obj.loi_fraction) > 0.0 and room.o2 < float(obj.loi_fraction):
			obj.state = FuelObjectModelScript.State.HEATING
			obj.hrr_kw = 0.0
			return false
		# SF-AUD-034: char layer — atenúa el flujo efectivo mediante resistencia térmica.
		# R_char [m²K/kW] = char_thickness / k_char; factor adimensional = R_char × h_ref (0.025 kW/m²K).
		var q_inc_eff_kw_m2: float = obj.incident_heat_flux_kw_m2
		if float(obj.char_thickness_m) > 0.0 and float(obj.k_char_kw_m_k) > 0.0:
			var R_char: float = float(obj.char_thickness_m) / maxf(1.0e-9, float(obj.k_char_kw_m_k))
			q_inc_eff_kw_m2 = obj.incident_heat_flux_kw_m2 / maxf(1.0, 1.0 + R_char * 0.025)
		var q_net_kw_m2: float = maxf(0.0,
			q_inc_eff_kw_m2 - float(obj.critical_heat_flux_kw_m2))
		var A_eff_m2: float = maxf(0.0,
			float(obj.exposed_area_m2) if float(obj.exposed_area_m2) > 0.001
			else float(obj.footprint_m2) * 0.5)
		# ṁ [kg/s] = q_net [kW/m²] × A [m²] / ΔHg [kJ/kg]
		var mlr_kg_s: float = q_net_kw_m2 * A_eff_m2 / float(obj.heat_of_gasification_kj_kg)
		# hrr [kW] = ṁ [kg/s] × ΔHc [kJ/kg]; acotado por 35% del max_hrr_kw en fase pre-ignición
		obj.hrr_kw = clampf(mlr_kg_s * float(obj.heat_of_combustion_kj_kg),
			0.0, maxf(0.0, float(obj.max_hrr_kw)) * 0.35)
		# Auto-extinción: si el flujo cae bajo el 70% del umbral crítico, la combustión no es sostenible
		if obj.incident_heat_flux_kw_m2 < float(obj.critical_heat_flux_kw_m2) * 0.70:
			obj.state = FuelObjectModelScript.State.HEATING
			obj.hrr_kw = 0.0

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


func _compute_extinction_o2_limit(
	room: RoomModel,
	context: Dictionary,
	ambient_c: float,
	fallback_min_o2: float
) -> float:
	if not bool(context.get("fire_fds_extinction_enabled", false)):
		return fallback_min_o2
	if room == null:
		return fallback_min_o2

	var ambient_limit: float = float(context.get("fire_fds_extinction_o2_limit_ambient", 0.135))
	var ambient_ref_c: float = float(context.get("fire_fds_extinction_ambient_c", ambient_c))
	var hot_gas_c: float = maxf(
		ambient_ref_c + 1.0,
		float(context.get("fire_fds_extinction_hot_gas_c", 900.0))
	)
	var hot_floor: float = clampf(
		float(context.get("fire_fds_extinction_hot_o2_floor", 0.105)),
		0.0,
		ambient_limit
	)
	var gas_temp_c: float = maxf(room.temp_upper_c, ambient_c)
	var hot_fraction: float = clampf(
		(gas_temp_c - ambient_ref_c) / maxf(1.0, hot_gas_c - ambient_ref_c),
		0.0,
		1.0
	)

	return clampf(
		lerpf(ambient_limit, hot_floor, hot_fraction),
		0.0,
		float(context.get("o2_nominal", 0.209))
	)


func _compute_extinction_factor(o2: float, o2_limit: float, transition_width: float) -> float:
	var width: float = maxf(0.001, transition_width)
	return clampf((o2 - o2_limit) / width, 0.0, 1.0)


func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float:
	var hrr_MJ_s: float = maxf(0.0, hrr_kw) / 1000.0
	return hrr_MJ_s * maxf(0.0, smoke_yield_kg_per_MJ)


func _resolve_room_smoke_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.smoke_yield_kg_per_MJ))
		if object_yield <= 0.0:
			continue

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return weighted_yield / total_weight


func _resolve_room_co_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.co_yield_kg_per_MJ))
		if object_yield <= 0.0:
			continue

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return weighted_yield / total_weight


func _resolve_room_soot_fraction(room: RoomModel, fallback_fraction: float) -> float:
	# SF-AUD-008: fracción soot ponderada por HRR de objetos activos.
	# Determina qué parte de smoke_kg es ópticamente activa (K_m = 8700 m²/kg).
	# Retrocompatible: objetos sin soot_fraction propio (= 1.0) conservan visibilidad original.
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_fraction

	var weighted_frac: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_frac += clampf(float(obj.soot_fraction), 0.0, 1.0) * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_fraction

	return clampf(weighted_frac / total_weight, 0.0, 1.0)


func _resolve_room_co2_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	# SF-AUD-005: CO₂ yield base ponderado por HRR de objetos activos.
	# Sentinel -1.0 en el objeto = excluir de la ponderación (usa fallback global).
	# Retrocompatible: si ningún objeto define co2_yield_kg_per_MJ > 0, devuelve fallback.
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = float(obj.co2_yield_kg_per_MJ)
		if object_yield < 0.0:
			continue  # sentinel: no contribuye a la media ponderada

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return maxf(0.0, weighted_yield / total_weight)


func _resolve_room_chi_rad_normal(room: RoomModel, fallback: float) -> float:
	# SF-AUD-015: fracción radiativa (φ=1, bien ventilado) ponderada por HRR de objetos activos.
	# Sentinel -1.0 en el objeto = excluir de la ponderación (usa global del motor).
	# Retrocompatible: si ningún objeto define chi_rad_normal ≥ 0, devuelve fallback (-1.0).
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback

	var weighted_frac: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var frac: float = float(obj.chi_rad_normal)
		if frac < 0.0:
			continue  # sentinel: no contribuye

		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_frac += clampf(frac, 0.0, 1.0) * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback

	return clampf(weighted_frac / total_weight, 0.0, 1.0)


func _resolve_room_hcn_base_yield_kg_per_MJ(room: RoomModel, fallback_yield: float) -> float:
	# SF-AUD-006: yield de HCN ponderado por HRR de objetos activos.
	# Solo usa objetos con hcn_yield_kg_per_MJ definido (> 0).
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback_yield

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.hcn_yield_kg_per_MJ))
		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback_yield

	return weighted_yield / total_weight


func _resolve_room_irritant_yield_kg_per_MJ(room: RoomModel, field: String, fallback: float) -> float:
	# SF-AUD-018: yield ponderado para HCl/acroleína/formaldehído. Mismo patron que HCN.
	if room == null or not _has_explicit_fuel_objects(room):
		return fallback

	var weighted_yield: float = 0.0
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var object_yield: float = maxf(0.0, float(obj.get(field)))
		var preheat_fraction: float = clampf(_fuel_object_preheat_score(obj) / 8.0, 0.0, 1.0)
		var weight: float = maxf(1.0, obj.max_hrr_kw) * lerpf(0.35, 1.0, preheat_fraction)
		if bool(obj.is_primary_ignition_source):
			weight *= 1.40
		if obj.state == FuelObjectModelScript.State.FLAMING:
			weight *= 1.35
		elif obj.state == FuelObjectModelScript.State.PYROLYZING:
			weight *= 1.20

		weighted_yield += object_yield * weight
		total_weight += weight

	if total_weight <= 0.000001:
		return fallback

	return weighted_yield / total_weight


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

	var upper_hold_c: float = float(context.get("fire_latent_hold_upper_temp_c", ambient_c))
	var lower_hold_c: float = float(context.get("fire_latent_hold_lower_temp_c", ambient_c))
	var thermal_hold: bool = room.temp_upper_c >= upper_hold_c or room.temp_lower_c >= lower_hold_c
	if not thermal_hold:
		return false

	var latent_o2_floor: float = minf(
		fire.o2_min_for_flame,
		maxf(0.02, fire.o2_min_for_flame * 0.25)
	)
	if room.o2 < latent_o2_floor:
		return false

	# El pool retenido necesita O2 significativamente por encima del mínimo de llama
	# para sostener combustión latente/smoldering. Si O2 está apenas por encima del
	# umbral (ej. equilibrio ACH), la infiltración mantiene el fuego zombi vivo.
	# fire_latent_o2_viable_margin = margen mínimo por encima del umbral efectivo.
	var latent_o2_viable_margin: float = float(context.get("fire_latent_o2_viable_margin", 0.008))
	var latent_o2_limit: float = _compute_extinction_o2_limit(
		room,
		context,
		ambient_c,
		fire.o2_min_for_flame
	)
	if room.o2 < latent_o2_limit + latent_o2_viable_margin:
		return false

	if room.retained_unburned_MJ >= 1.0:
		return true

	if fire.remaining_fuel_MJ <= float(context.get("fire_latent_min_remaining_fuel_MJ", 25.0)):
		return false

	# Extinción por dormancia prolongada: si la llama está ausente durante más de
	# 2× el timeout de extinción latente Y el HRR está por debajo de 3× el umbral
	# de extinción, dejar de sostener la fase latente. Esto evita el fuego zombi
	# en salas con mucho combustible pero O2 agotado (ej. pasillo tras flashover).
	var latent_timeout_s: float = float(
		context.get("fire_latent_extinction_delay_s", float(context.get("fire_extinction_delay_s", 0.0)))
	)
	var extinction_hrr_kw: float = float(context.get("fire_extinction_hrr_kw", 0.0))
	if latent_timeout_s > 0.0 \
			and room.fire_dormant_time_s >= latent_timeout_s * 2.0 \
			and extinction_hrr_kw > 0.0 \
			and room.hrr_kw <= extinction_hrr_kw * 3.0:
		return false

	return true


func _extinguish_room_fire(room: RoomModel, fire: FireModel, burned_out: bool = false) -> bool:
	if room == null:
		return false

	if burned_out:
		_mark_legacy_proxy_burned_out(room)
	elif fire != null:
		_sync_legacy_proxy_from_fire(room, fire, 0.0, false)

	room.hrr_kw = 0.0
	room.hrr_target_kw = 0.0
	room.pyrolysis_kw = 0.0
	room.burned_hrr_kw = 0.0
	room.unburned_generation_kw = 0.0
	room.flame_hrr_target_kw = 0.0
	room.smolder_hrr_target_kw = 0.0
	room.pool_release_hrr_target_kw = 0.0
	room.smoke_prod_kg_s = 0.0
	room.fire = null
	room.fire_low_hrr_time_s = 0.0
	room.fire_dormant_time_s = 0.0
	if burned_out:
		room.retained_unburned_MJ = 0.0
	return false


func _mark_room_ignition_object(room: RoomModel) -> void:
	if room == null or not _has_explicit_fuel_objects(room):
		return

	var ignition_object = _select_room_ignition_object(room)
	if ignition_object == null:
		return

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		obj.hrr_kw = 0.0
		obj.autoignite_ready = false
		if obj == ignition_object:
			obj.is_primary_ignition_source = true
			obj.state = FuelObjectModelScript.State.FLAMING
			obj.surface_temp_c = maxf(obj.surface_temp_c, obj.ignition_temp_c + 35.0)
			obj.exposure_s = maxf(obj.exposure_s, 75.0)
			obj.ignited_by_object_id = String(obj.id)


func _select_room_ignition_object(room: RoomModel):
	var best_obj = null
	var best_score: float = -1.0e20

	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue
		if obj.remaining_fuel_MJ <= 0.001:
			continue

		var score: float = _fuel_object_preheat_score(obj)
		if bool(obj.is_primary_ignition_source):
			score += 8.0
		if bool(obj.autoignite_ready):
			score += 12.0
		if obj.state == FuelObjectModelScript.State.PYROLYZING:
			score += 6.0
		elif obj.state == FuelObjectModelScript.State.HEATING:
			score += 3.0
		score += 2.0 / maxf(1.0, obj.ignition_flux_kw_m2)
		score += 1.0 / maxf(1.0, obj.ignition_temp_c)

		if score > best_score:
			best_score = score
			best_obj = obj

	return best_obj


func _apply_intraroom_object_radiation(room: RoomModel, context: Dictionary) -> void:
	# Point-source radiation model: burning objects irradiate nearby non-burning
	# objects, causing sequential ignition based on geometry (position_m).
	# q'' = Σ(hrr_src * view_factor_coeff / max(falloff_m², dist²))
	# Reference: Drysdale "Introduction to Fire Dynamics", point source model.
	if room == null or not _has_explicit_fuel_objects(room):
		return
	if not bool(context.get("fire_intraroom_spread_enabled", true)):
		return

	var view_factor_coeff: float = float(context.get("fire_intraroom_view_factor", 0.10))
	var falloff_m2: float = float(context.get("fire_intraroom_falloff_m", 1.0)) \
			* float(context.get("fire_intraroom_falloff_m", 1.0))

	# Collect FLAMING source objects (need hrr > 1 kW to contribute).
	var sources: Array = []
	for src_obj in room.fuel_objects:
		if _should_skip_object_for_room(room, src_obj):
			continue
		if src_obj.remaining_fuel_MJ <= 0.001 or float(src_obj.hrr_kw) < 1.0:
			continue
		if int(src_obj.state) == FuelObjectModelScript.State.FLAMING:
			sources.append({
				"pos": Vector2(float(src_obj.position_m.x), float(src_obj.position_m.y)),
				"hrr_kw": float(src_obj.hrr_kw)
			})

	if sources.is_empty():
		return

	# Apply radiation flux to non-burning target objects.
	for tgt_obj in room.fuel_objects:
		if _should_skip_object_for_room(room, tgt_obj):
			continue
		if tgt_obj.remaining_fuel_MJ <= 0.001:
			continue
		var tgt_state: int = int(tgt_obj.state)
		if tgt_state == FuelObjectModelScript.State.FLAMING \
				or tgt_state == FuelObjectModelScript.State.BURNED_OUT:
			continue

		var tgt_pos: Vector2 = Vector2(float(tgt_obj.position_m.x), float(tgt_obj.position_m.y))
		var total_flux_kw_m2: float = 0.0
		for src in sources:
			var dist_sq: float = tgt_pos.distance_squared_to(src["pos"])
			total_flux_kw_m2 += float(src["hrr_kw"]) * view_factor_coeff \
					/ maxf(falloff_m2, dist_sq)

		if total_flux_kw_m2 < 0.5:
			continue

		# Store 55% of computed radiation as incident flux (view factor, orientation).
		tgt_obj.incident_heat_flux_kw_m2 = maxf(
			float(tgt_obj.incident_heat_flux_kw_m2), total_flux_kw_m2 * 0.55
		)

		# Advance state to PYROLYZING when flux reaches 70% of ignition threshold
		# and the object has been exposed for at least 15 s.
		var ign_flux: float = maxf(8.0, float(tgt_obj.ignition_flux_kw_m2))
		if total_flux_kw_m2 >= ign_flux * 0.70 \
				and tgt_state != FuelObjectModelScript.State.PYROLYZING \
				and float(tgt_obj.exposure_s) >= 15.0:
			tgt_obj.state = FuelObjectModelScript.State.PYROLYZING

		# Mark autoignite_ready: PYROLYZING + full flux + 60 s exposure.
		# The main loop in _sync_explicit_objects_from_active_fire reads and then
		# clears this flag via was_autoignite_ready, so the object becomes a burn
		# candidate in the same timestep.
		if total_flux_kw_m2 >= ign_flux \
				and tgt_state == FuelObjectModelScript.State.PYROLYZING \
				and float(tgt_obj.exposure_s) >= 60.0:
			tgt_obj.autoignite_ready = true


func _sync_explicit_objects_from_active_fire(
	room: RoomModel,
	actual_solid_burn_kw: float,
	solid_fuel_demand_MJ: float,
	can_flame: bool,
	dt: float,
	context: Dictionary = {}
) -> void:
	if room == null or not _has_explicit_fuel_objects(room):
		return

	# Intra-room object-to-object radiation: burning objects irradiate nearby
	# non-burning objects, accelerating sequential ignition based on geometry.
	_apply_intraroom_object_radiation(room, context)

	var candidates: Array = []
	var total_weight: float = 0.0
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue

		# Save before clearing — preserves radiation-triggered flag from above.
		var was_autoignite_ready: bool = bool(obj.autoignite_ready)
		obj.autoignite_ready = false
		if obj.remaining_fuel_MJ <= 0.001:
			obj.remaining_fuel_MJ = 0.0
			obj.hrr_kw = 0.0
			obj.state = FuelObjectModelScript.State.BURNED_OUT
			continue

		var active_target_temp_c: float = maxf(room.temp_upper_c, obj.ignition_temp_c + 80.0)
		var heat_blend: float = clampf(dt / 60.0, 0.0, 1.0)
		obj.surface_temp_c = lerpf(obj.surface_temp_c, active_target_temp_c, heat_blend)
		obj.incident_heat_flux_kw_m2 = maxf(
			obj.incident_heat_flux_kw_m2,
			_estimate_radiative_flux_kw_m2(room.temp_upper_c, obj.surface_temp_c, 0.85)
		)

		var preheat_score: float = _fuel_object_preheat_score(obj)
		var active_burn_candidate: bool = room.flashover_triggered \
				or bool(obj.is_primary_ignition_source) \
				or was_autoignite_ready \
				or obj.state == FuelObjectModelScript.State.FLAMING \
				or obj.state == FuelObjectModelScript.State.PYROLYZING \
				or preheat_score >= 6.0
		if not active_burn_candidate:
			obj.hrr_kw = 0.0
			if obj.remaining_fuel_MJ <= 0.001:
				obj.state = FuelObjectModelScript.State.BURNED_OUT
			elif obj.surface_temp_c >= obj.ignition_temp_c - 45.0:
				obj.state = FuelObjectModelScript.State.PYROLYZING
			elif obj.surface_temp_c >= room.temp_lower_c + 35.0:
				obj.state = FuelObjectModelScript.State.HEATING
			continue

		# SF-AUD-004: si el objeto tiene su propia curva t², registrar ignición y calcular
		# su HRR ideal independiente. Esto permite que objetos encendidos en distintos
		# momentos crezcan según su propio alpha, en vez de compartir el alpha global.
		# SF-AUD-033: también registrar ignición si el objeto tiene curva HRR tabulada.
		if obj.state == FuelObjectModelScript.State.FLAMING:
			if float(obj.alpha_kw_s2) > 0.0 or not obj.hrr_curve.is_empty():
				if float(obj.t_ignition_s) < 0.0:
					obj.t_ignition_s = room.fire_time_s
		var weight: float
		if float(obj.alpha_kw_s2) > 0.0 and float(obj.t_ignition_s) >= 0.0:
			# Peso = HRR ideal del objeto en su propio tiempo t² desde su ignición.
			var t_obj: float = maxf(0.0, room.fire_time_s - float(obj.t_ignition_s))
			var obj_ideal_kw: float = float(obj.alpha_kw_s2) * t_obj * t_obj
			if float(obj.max_hrr_kw) > 0.0:
				obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
			weight = maxf(0.01, obj_ideal_kw)
		elif not obj.hrr_curve.is_empty() and float(obj.t_ignition_s) >= 0.0:
			# SF-AUD-033: curva HRR tabulada — interpolación lineal por tramos.
			var t_obj: float = maxf(0.0, room.fire_time_s - float(obj.t_ignition_s))
			var obj_ideal_kw: float = _interp_hrr_curve(obj.hrr_curve, t_obj)
			if float(obj.max_hrr_kw) > 0.0:
				obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
			weight = maxf(0.01, obj_ideal_kw)
		elif float(obj.heat_of_gasification_kj_kg) > 0.0 \
				and float(obj.heat_of_combustion_kj_kg) > 0.0 \
				and obj.state == FuelObjectModelScript.State.FLAMING:
			# SF-AUD-016: MLR-based weight cuando no hay curva t² propia.
			# Peso = HRR instantáneo por pirólisis física: ṁ × ΔHc.
			var q_net_kw_m2: float = maxf(0.0,
				obj.incident_heat_flux_kw_m2 - float(obj.critical_heat_flux_kw_m2))
			var A_eff_m2: float = maxf(0.01,
				float(obj.exposed_area_m2) if float(obj.exposed_area_m2) > 0.001
				else float(obj.footprint_m2) * 0.5)
			var mlr_kg_s: float = q_net_kw_m2 * A_eff_m2 / float(obj.heat_of_gasification_kj_kg)
			var obj_ideal_kw: float = mlr_kg_s * float(obj.heat_of_combustion_kj_kg)
			if float(obj.max_hrr_kw) > 0.0:
				obj_ideal_kw = minf(obj_ideal_kw, float(obj.max_hrr_kw))
			weight = maxf(0.01, obj_ideal_kw)
		else:
			weight = maxf(1.0, obj.max_hrr_kw) * (0.35 + 0.65 * preheat_score / 8.0)
			if bool(obj.is_primary_ignition_source):
				weight *= 1.40
			if obj.state == FuelObjectModelScript.State.FLAMING:
				weight *= 1.35
			elif obj.state == FuelObjectModelScript.State.PYROLYZING:
				weight *= 1.20
			weight = maxf(0.01, weight)

		candidates.append({
			"obj": obj,
			"weight": weight,
			"burn_MJ": 0.0
		})
		total_weight += weight

	if candidates.is_empty():
		return

	if solid_fuel_demand_MJ <= 0.000001 or actual_solid_burn_kw <= 0.000001:
		for index in range(candidates.size()):
			var idle_obj = candidates[index]["obj"]
			idle_obj.hrr_kw = 0.0
			if idle_obj.state == FuelObjectModelScript.State.FLAMING:
				idle_obj.state = FuelObjectModelScript.State.DECAYING
		return

	var consumed_MJ: float = 0.0
	for index in range(candidates.size()):
		var entry: Dictionary = candidates[index]
		var obj = entry["obj"]
		var share_MJ: float = solid_fuel_demand_MJ * float(entry["weight"]) / maxf(0.001, total_weight)
		share_MJ = minf(maxf(0.0, share_MJ), obj.remaining_fuel_MJ)
		obj.remaining_fuel_MJ = maxf(0.0, obj.remaining_fuel_MJ - share_MJ)
		entry["burn_MJ"] = share_MJ
		candidates[index] = entry
		consumed_MJ += share_MJ

	var leftover_MJ: float = maxf(0.0, solid_fuel_demand_MJ - consumed_MJ)
	if leftover_MJ > 0.000001:
		var remaining_capacity_MJ: float = 0.0
		for entry in candidates:
			var capacity_obj = entry["obj"]
			remaining_capacity_MJ += maxf(0.0, capacity_obj.remaining_fuel_MJ)
		if remaining_capacity_MJ > 0.000001:
			for index in range(candidates.size()):
				var entry: Dictionary = candidates[index]
				var obj = entry["obj"]
				var extra_MJ: float = leftover_MJ * maxf(0.0, obj.remaining_fuel_MJ) / remaining_capacity_MJ
				extra_MJ = minf(extra_MJ, obj.remaining_fuel_MJ)
				obj.remaining_fuel_MJ = maxf(0.0, obj.remaining_fuel_MJ - extra_MJ)
				entry["burn_MJ"] = float(entry["burn_MJ"]) + extra_MJ
				candidates[index] = entry
				consumed_MJ += extra_MJ

	for entry in candidates:
		var obj = entry["obj"]
		var burn_MJ: float = float(entry["burn_MJ"])
		if burn_MJ > 0.000001 and consumed_MJ > 0.000001:
			obj.hrr_kw = actual_solid_burn_kw * burn_MJ / consumed_MJ
			# SF-AUD-034: LOI — si O2_sala < LOI, la llama se apaga por falta de oxígeno.
			if float(obj.loi_fraction) > 0.0 and room.o2 < float(obj.loi_fraction):
				obj.state = FuelObjectModelScript.State.DECAYING
				obj.hrr_kw = 0.0
			else:
				obj.state = FuelObjectModelScript.State.FLAMING if can_flame else FuelObjectModelScript.State.DECAYING
				obj.exposure_s = maxf(obj.exposure_s, 75.0)
				# SF-AUD-034: char growth — acumular espesor de char proporcional a masa quemada.
				if float(obj.char_growth_rate_m_per_kg) > 0.0 and float(obj.heat_of_combustion_kj_kg) > 0.0:
					var mass_kg: float = burn_MJ * 1000.0 / maxf(1.0, float(obj.heat_of_combustion_kj_kg))
					obj.char_thickness_m = maxf(0.0, float(obj.char_thickness_m) + float(obj.char_growth_rate_m_per_kg) * mass_kg)
		else:
			obj.hrr_kw = 0.0
			if obj.remaining_fuel_MJ <= 0.001:
				obj.state = FuelObjectModelScript.State.BURNED_OUT
			elif obj.surface_temp_c >= obj.ignition_temp_c - 45.0:
				obj.state = FuelObjectModelScript.State.PYROLYZING
			elif obj.surface_temp_c >= room.temp_lower_c + 35.0:
				obj.state = FuelObjectModelScript.State.HEATING


func _get_dominant_fuel_object(room: RoomModel):
	if room == null:
		return null

	var best_obj = null
	var best_score: float = -1.0e20
	for obj in room.fuel_objects:
		if _should_skip_object_for_room(room, obj):
			continue

		var score: float = _fuel_object_preheat_score(obj)
		if score > best_score:
			best_score = score
			best_obj = obj

	return best_obj


func _fuel_object_preheat_score(obj) -> float:
	if obj == null:
		return -1.0e20

	var state_score: float = 0.0
	match int(obj.state):
		FuelObjectModelScript.State.HEATING:
			state_score = 2.0
		FuelObjectModelScript.State.PYROLYZING:
			state_score = 5.0
		FuelObjectModelScript.State.FLAMING:
			state_score = 7.0
		FuelObjectModelScript.State.DECAYING:
			state_score = 1.0
		FuelObjectModelScript.State.BURNED_OUT:
			state_score = -6.0
		_:
			state_score = 0.0

	var thermal_signal: float = clampf(
		inverse_lerp(obj.ignition_temp_c - 75.0, obj.ignition_temp_c, obj.surface_temp_c),
		0.0,
		1.0
	)
	var flux_signal: float = clampf(
		obj.incident_heat_flux_kw_m2 / maxf(1.0, obj.ignition_flux_kw_m2),
		0.0,
		1.5
	)
	var exposure_signal: float = clampf(obj.exposure_s / 75.0, 0.0, 1.5)
	var hrr_signal: float = clampf(obj.hrr_kw / maxf(1.0, obj.max_hrr_kw), 0.0, 1.0)
	var ready_bonus: float = 3.0 if bool(obj.autoignite_ready) else 0.0
	return state_score + ready_bonus + maxf(thermal_signal, flux_signal) * 2.0 + exposure_signal + hrr_signal


func _get_legacy_room_proxy(room: RoomModel):
	if room == null or room.fuel_objects.is_empty():
		return null

	for obj in room.fuel_objects:
		if _is_legacy_room_proxy(obj):
			return obj

	return null


func _has_explicit_fuel_objects(room: RoomModel) -> bool:
	if room == null or room.fuel_objects.is_empty():
		return false

	for obj in room.fuel_objects:
		if obj != null and not _is_legacy_room_proxy(obj):
			return true

	return false


func _is_legacy_room_proxy(obj) -> bool:
	return obj != null and String(obj.id).begins_with("room_proxy_")


func _should_skip_object_for_room(room: RoomModel, obj) -> bool:
	if obj == null:
		return true
	return _has_explicit_fuel_objects(room) and _is_legacy_room_proxy(obj)


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


# ============================================================
# SF-AUD-033: CURVA HRR TABULADA — interpolación lineal
# ============================================================
# Interpola linealmente la curva [[t0, h0], [t1, h1], ...] en t_s.
# t_s es el tiempo desde la ignición del objeto (no el tiempo global).
# Fuera del rango: se extrapola con el valor del extremo más cercano.
func _interp_hrr_curve(curve: Array, t_s: float) -> float:
	var n: int = curve.size()
	if n == 0:
		return 0.0
	var first_entry: Variant = curve[0]
	if typeof(first_entry) != TYPE_ARRAY or (first_entry as Array).size() < 2:
		return 0.0
	var t0: float = float((first_entry as Array)[0])
	var h0: float = float((first_entry as Array)[1])
	if t_s <= t0:
		return maxf(0.0, h0)
	var last_entry: Variant = curve[n - 1]
	if typeof(last_entry) != TYPE_ARRAY or (last_entry as Array).size() < 2:
		return 0.0
	var t_last: float = float((last_entry as Array)[0])
	var h_last: float = float((last_entry as Array)[1])
	if t_s >= t_last:
		return maxf(0.0, h_last)
	for i: int in range(n - 1):
		var entry_a: Variant = curve[i]
		var entry_b: Variant = curve[i + 1]
		if typeof(entry_a) != TYPE_ARRAY or (entry_a as Array).size() < 2:
			continue
		if typeof(entry_b) != TYPE_ARRAY or (entry_b as Array).size() < 2:
			continue
		var ta: float = float((entry_a as Array)[0])
		var tb: float = float((entry_b as Array)[0])
		if t_s >= ta and t_s <= tb:
			var ha: float = float((entry_a as Array)[1])
			var hb: float = float((entry_b as Array)[1])
			var alpha: float = (t_s - ta) / maxf(0.0001, tb - ta)
			return maxf(0.0, lerpf(ha, hb, alpha))
	return maxf(0.0, h_last)
