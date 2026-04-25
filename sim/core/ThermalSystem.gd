extends RefCounted
class_name ThermalSystem

# ============================================================
# THERMAL SYSTEM
# ------------------------------------------------------------
# Responsabilidad:
# - cálculos de temperatura (capa superior/inferior)
# - gradientes térmicos y perfiles de temperatura
# - gestión de la capa de gases calientes (upper_gas_kg, upper_energy_kj)
# - isotermas y capas de tenabilidad (layer_150c)
# - flujo boyante convectivo entre habitaciones
# - funciones auxiliares térmicas (densidad, plume, etc.)
# ============================================================

# Dependencias externas
var _building: BuildingModel
var _smoke_model: SmokeModel

# Parámetros térmicos
var upper_to_lower_loss_rate: float = 0.025
var upper_to_ambient_loss_rate: float = 0.008
var lower_layer_warming_rate: float = 0.012
var wall_absorption_rate: float = 0.003
var max_upper_temp_c: float = 900.0
var doorway_heat_exchange_coeff: float = 0.26
var smoke_heat_mix_coeff: float = 0.025
var retained_hot_layer_temp_start_c: float = 100.0
var retained_hot_layer_temp_full_c: float = 350.0
var retained_hot_layer_o2_start: float = 0.18
var retained_hot_layer_o2_full: float = 0.10
var retained_hot_layer_max_fraction: float = 0.85
var outside_open_loss_area_fraction: float = 0.12
var outside_open_ambient_loss_multiplier: float = 16.0
var outside_open_wall_absorption_multiplier: float = 0.80
var outside_open_upper_mix_rate: float = 0.0
var outside_open_background_heat_exchange_kg_s_m2: float = 0.030
var outside_open_background_heat_max_fraction_per_step: float = 0.020
var outside_open_background_heat_carry_factor: float = 0.42

# Gradiente térmico
var thermal_gradient_min_band_m: float = 0.20
var thermal_gradient_max_band_m: float = 0.70
var thermal_gradient_band_fraction: float = 0.35

# Banda de enfriamiento del suelo
var floor_cooling_band_fraction: float = 0.24
var floor_cooling_band_max_m: float = 0.35
var survival_temp_threshold_c: float = 150.0

# Relajación de capa 150°C
var layer_150c_relax_down_per_s: float = 0.35
var layer_150c_relax_up_per_s: float = 0.03

# Plume
var plume_fill_depth_coeff: float = 0.60
var plume_fill_response_s: float = 12.0
var plume_fill_max_fraction: float = 0.85

# Relajación de capa
var layer_relax_down: float = 0.18
var layer_relax_up: float = 0.015

# Flujo en aberturas interiores
var doorway_o2_min_band_m: float = 0.25
var doorway_o2_smoke_weight: float = 0.35
var doorway_o2_pressure_weight: float = 0.65
var pressure_spill_ref_delta_pa: float = 8.0
var interior_spill_start_layer_m: float = 2.0

# FED (ISO 13571) — componentes asfixiantes disponibles en el modelo
var fed_hypoxia_enabled: bool = true
var fed_hypoxia_a: float = 8.13
var fed_hypoxia_b: float = 0.54


func set_references(building: BuildingModel, smoke_model: SmokeModel) -> void:
	_building = building
	_smoke_model = smoke_model


func configure(settings: Dictionary) -> void:
	upper_to_lower_loss_rate = float(settings.get("upper_to_lower_loss_rate", upper_to_lower_loss_rate))
	upper_to_ambient_loss_rate = float(settings.get("upper_to_ambient_loss_rate", upper_to_ambient_loss_rate))
	lower_layer_warming_rate = float(settings.get("lower_layer_warming_rate", lower_layer_warming_rate))
	wall_absorption_rate = float(settings.get("wall_absorption_rate", wall_absorption_rate))
	max_upper_temp_c = float(settings.get("max_upper_temp_c", max_upper_temp_c))
	doorway_heat_exchange_coeff = float(settings.get("doorway_heat_exchange_coeff", doorway_heat_exchange_coeff))
	smoke_heat_mix_coeff = float(settings.get("smoke_heat_mix_coeff", smoke_heat_mix_coeff))
	retained_hot_layer_temp_start_c = float(
		settings.get("retained_hot_layer_temp_start_c", retained_hot_layer_temp_start_c)
	)
	retained_hot_layer_temp_full_c = float(
		settings.get("retained_hot_layer_temp_full_c", retained_hot_layer_temp_full_c)
	)
	retained_hot_layer_o2_start = float(
		settings.get("retained_hot_layer_o2_start", retained_hot_layer_o2_start)
	)
	retained_hot_layer_o2_full = float(
		settings.get("retained_hot_layer_o2_full", retained_hot_layer_o2_full)
	)
	retained_hot_layer_max_fraction = float(
		settings.get("retained_hot_layer_max_fraction", retained_hot_layer_max_fraction)
	)
	outside_open_loss_area_fraction = float(
		settings.get("outside_open_loss_area_fraction", outside_open_loss_area_fraction)
	)
	outside_open_ambient_loss_multiplier = float(
		settings.get(
			"outside_open_ambient_loss_multiplier",
			outside_open_ambient_loss_multiplier
		)
	)
	outside_open_wall_absorption_multiplier = float(
		settings.get(
			"outside_open_wall_absorption_multiplier",
			outside_open_wall_absorption_multiplier
		)
	)
	outside_open_upper_mix_rate = float(
		settings.get("outside_open_upper_mix_rate", outside_open_upper_mix_rate)
	)
	outside_open_background_heat_exchange_kg_s_m2 = float(
		settings.get(
			"outside_open_background_heat_exchange_kg_s_m2",
			outside_open_background_heat_exchange_kg_s_m2
		)
	)
	outside_open_background_heat_max_fraction_per_step = float(
		settings.get(
			"outside_open_background_heat_max_fraction_per_step",
			outside_open_background_heat_max_fraction_per_step
		)
	)
	outside_open_background_heat_carry_factor = float(
		settings.get(
			"outside_open_background_heat_carry_factor",
			outside_open_background_heat_carry_factor
		)
	)
	thermal_gradient_min_band_m = float(settings.get("thermal_gradient_min_band_m", thermal_gradient_min_band_m))
	thermal_gradient_max_band_m = float(settings.get("thermal_gradient_max_band_m", thermal_gradient_max_band_m))
	thermal_gradient_band_fraction = float(settings.get("thermal_gradient_band_fraction", thermal_gradient_band_fraction))
	floor_cooling_band_fraction = float(settings.get("floor_cooling_band_fraction", floor_cooling_band_fraction))
	floor_cooling_band_max_m = float(settings.get("floor_cooling_band_max_m", floor_cooling_band_max_m))
	survival_temp_threshold_c = float(settings.get("survival_temp_threshold_c", survival_temp_threshold_c))
	layer_150c_relax_down_per_s = float(settings.get("layer_150c_relax_down_per_s", layer_150c_relax_down_per_s))
	layer_150c_relax_up_per_s = float(settings.get("layer_150c_relax_up_per_s", layer_150c_relax_up_per_s))
	plume_fill_depth_coeff = float(settings.get("plume_fill_depth_coeff", plume_fill_depth_coeff))
	plume_fill_response_s = float(settings.get("plume_fill_response_s", plume_fill_response_s))
	plume_fill_max_fraction = float(settings.get("plume_fill_max_fraction", plume_fill_max_fraction))
	layer_relax_down = float(settings.get("layer_relax_down", layer_relax_down))
	layer_relax_up = float(settings.get("layer_relax_up", layer_relax_up))
	doorway_o2_min_band_m = float(settings.get("doorway_o2_min_band_m", doorway_o2_min_band_m))
	doorway_o2_smoke_weight = float(settings.get("doorway_o2_smoke_weight", doorway_o2_smoke_weight))
	doorway_o2_pressure_weight = float(settings.get("doorway_o2_pressure_weight", doorway_o2_pressure_weight))
	pressure_spill_ref_delta_pa = float(settings.get("pressure_spill_ref_delta_pa", pressure_spill_ref_delta_pa))
	interior_spill_start_layer_m = float(settings.get("interior_spill_start_layer_m", interior_spill_start_layer_m))
	fed_hypoxia_enabled = bool(settings.get("fed_hypoxia_enabled", fed_hypoxia_enabled))
	fed_hypoxia_a = float(settings.get("fed_hypoxia_a", fed_hypoxia_a))
	fed_hypoxia_b = float(settings.get("fed_hypoxia_b", fed_hypoxia_b))


# ============================================================
# STEP PRINCIPAL DE TEMPERATURA
# ============================================================

func step(building: BuildingModel, dt: float, hooks: Dictionary = {}) -> void:
	var _outside_open_path_factor_callable: Callable = hooks.get(
		"outside_open_path_factor_callable", Callable()
	)
	var ambient_c: float = ambient_temp_c()

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var target_upper_mass_kg: float = estimate_target_upper_gas_mass_kg(room)
		if target_upper_mass_kg > room.upper_gas_kg:
			var mass_gain_kg: float = (target_upper_mass_kg - room.upper_gas_kg) * clampf(
				dt / maxf(1.0, plume_fill_response_s),
				0.0,
				1.0
			)
			room.upper_gas_kg += mass_gain_kg
			room.upper_energy_kj += mass_gain_kg * maxf(0.0, room.temp_lower_c - ambient_c)

		var upper_heat_capture_fraction: float = lerpf(
			0.18,
			0.35,
			clampf(inverse_lerp(0.06, 0.12, room.o2), 0.0, 1.0)
		)
		room.upper_energy_kj += room.hrr_kw * upper_heat_capture_fraction * dt
		sync_room_upper_layer(room, dt)

		var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
		var outside_open_factor: float = estimate_room_outside_open_factor(room)
		var lower_transfer_rate: float = upper_to_lower_loss_rate + lower_layer_warming_rate
		lower_transfer_rate += _compute_room_vertical_mix_bonus(room)
		var energy_to_lower_kj: float = room.upper_gas_kg * delta_ul * lower_transfer_rate * dt
		var energy_to_ambient_kj: float = room.upper_gas_kg \
				* maxf(0.0, room.temp_upper_c - ambient_c) \
				* upper_to_ambient_loss_rate \
				* (1.0 + outside_open_ambient_loss_multiplier * outside_open_factor) \
				* dt
		var wall_absorption_kj: float = room.upper_gas_kg \
				* maxf(0.0, room.temp_upper_c - ambient_c) \
				* wall_absorption_rate \
				* (1.0 + outside_open_wall_absorption_multiplier * outside_open_factor) \
				* dt

		var requested_upper_loss_kj: float = energy_to_lower_kj + energy_to_ambient_kj + wall_absorption_kj
		if requested_upper_loss_kj > 0.0 and room.upper_energy_kj > 0.0:
			var loss_scale: float = minf(1.0, room.upper_energy_kj / requested_upper_loss_kj)
			energy_to_lower_kj *= loss_scale
			energy_to_ambient_kj *= loss_scale
			wall_absorption_kj *= loss_scale
			room.upper_energy_kj -= energy_to_lower_kj + energy_to_ambient_kj + wall_absorption_kj

		if outside_open_factor > 0.0 and room.upper_gas_kg > 0.0001:
			var upper_temp_excess_factor: float = clampf(
				(room.temp_upper_c - ambient_c) / maxf(50.0, retained_hot_layer_temp_full_c - ambient_c),
				0.0,
				1.0
			)
			var cooling_mix_kg: float = room.upper_gas_kg \
					* outside_open_upper_mix_rate \
					* outside_open_factor \
					* upper_temp_excess_factor \
					* dt
			room.upper_gas_kg += maxf(0.0, cooling_mix_kg)

		var lower_mass_kg: float = maxf(
			1.0,
			gas_density_kg_m3(room.temp_lower_c) * room.floor_area_m2() * maxf(0.2, effective_hot_layer_height_m(room))
		)

		room.temp_lower_c += energy_to_lower_kj / lower_mass_kg
		room.temp_lower_c -= maxf(0.0, room.temp_lower_c - ambient_c) * 0.0085 * dt
		room.temp_lower_c = maxf(ambient_c, room.temp_lower_c)
		sync_room_upper_layer(room, dt)
		update_room_layer_150c(room, dt)
		step_fed(room, dt)

	# --------------------------------------------------------
	# Transferencia convectiva entre habitaciones a través de
	# aperturas interiores abiertas (efecto chimenea bidireccional).
	# Usa la misma fórmula de flujo boyante que _step_oxygen.
	# --------------------------------------------------------
	var g_grav: float = 9.8
	var rho_air: float = 1.2  # kg/m³

	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		var flow_state: Dictionary = build_interior_opening_flow_state(room_a, room_b, op)
		_apply_outside_assisted_background_heat_exchange(
			room_a, room_b, op, dt, ambient_c, _outside_open_path_factor_callable
		)
		if not bool(flow_state.get("active", false)):
			continue

		var hot_room: RoomModel = flow_state.get("hot_room", null)
		var cold_room: RoomModel = flow_state.get("cold_room", null)
		if hot_room == null or cold_room == null:
			continue

		var hot_band_m: float = float(flow_state.get("hot_band_m", 0.0))
		if hot_band_m <= 0.0:
			continue

		var engagement: float = float(flow_state.get("engagement", 0.0))
		var source_temp_c: float = float(flow_state.get("source_temp_c", hot_room.temp_upper_c))
		var t_hot_k: float = source_temp_c + 273.15
		var t_cold_k: float = cold_room.temp_upper_c + 273.15
		var delta_t_k: float = maxf(0.0, t_hot_k - t_cold_k)
		if delta_t_k < 2.0:
			continue

		var area_eff: float = float(flow_state.get("area_eff_m2", 0.0))
		if area_eff <= 0.0:
			continue

		var q_vol: float = 0.65 * 0.5 * area_eff * sqrt(g_grav * hot_band_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5))
		var thermal_engagement: float = clampf(0.14 + engagement * 0.70, 0.14, 1.0)
		var mass_exch: float = q_vol * rho_air * dt * doorway_heat_exchange_coeff * thermal_engagement

		var m_hot_kg: float = maxf(1.0, hot_room.volume_m3() * rho_air)
		var m_cold_kg: float = maxf(1.0, cold_room.volume_m3() * rho_air)

		# Limitar para evitar sobreoscilación: no puede transferirse más calor
		# del que equilibraría ambas habitaciones en un solo paso.
		var max_exch: float = (m_hot_kg * m_cold_kg) / (m_hot_kg + m_cold_kg)
		mass_exch = minf(mass_exch, max_exch)

		var gas_cap_kg: float = minf(
			hot_room.upper_gas_kg,
			maxf(0.06, hot_room.upper_gas_kg * (0.17 + 0.12 * thermal_engagement))
		)
		var gas_moved_kg: float = minf(mass_exch, gas_cap_kg)
		if gas_moved_kg <= 0.0:
			continue

		var energy_moved_kj: float = gas_moved_kg * maxf(0.0, source_temp_c - ambient_c)
		energy_moved_kj = minf(energy_moved_kj, hot_room.upper_energy_kj)

		hot_room.upper_gas_kg -= gas_moved_kg
		hot_room.upper_energy_kj = maxf(0.0, hot_room.upper_energy_kj - energy_moved_kj)

		cold_room.upper_gas_kg += gas_moved_kg
		cold_room.upper_energy_kj += energy_moved_kj

		sync_room_upper_layer(hot_room, dt)
		sync_room_upper_layer(cold_room, dt)
		_apply_post_transfer_vertical_mix(hot_room, dt)
		_apply_post_transfer_vertical_mix(cold_room, dt)
		update_room_layer_150c(hot_room, dt)
		update_room_layer_150c(cold_room, dt)


# ============================================================
# FUNCIONES AUXILIARES TÉRMICAS
# ============================================================

func ambient_temp_c() -> float:
	return _building.outside_temp_c if _building != null else 20.0


func gas_density_kg_m3(temp_c: float) -> float:
	var ambient_k: float = ambient_temp_c() + 273.15
	var gas_k: float = maxf(ambient_k, temp_c + 273.15)
	return 1.2 * ambient_k / gas_k


func estimate_target_upper_gas_mass_kg(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var target_depth_m: float = estimate_plume_upper_depth_m(room)
	if target_depth_m <= 0.0:
		return 0.0

	var target_volume_m3: float = room.floor_area_m2() * target_depth_m
	var entrained_temp_c: float = maxf(
		room.temp_lower_c + 60.0,
		minf(room.temp_upper_c, room.temp_lower_c + 180.0)
	)
	return target_volume_m3 * gas_density_kg_m3(entrained_temp_c)


func estimate_retained_hot_layer_depth_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var heat_factor: float = inverse_lerp(
		retained_hot_layer_temp_start_c,
		retained_hot_layer_temp_full_c,
		room.temp_upper_c
	)
	heat_factor = clampf(heat_factor, 0.0, 1.0)
	if heat_factor <= 0.0:
		return 0.0

	var smoke_fill_fraction: float = clampf(
		(room.height_m - _smoke_model.get_visible_smoke_layer_height_m(room)) / maxf(0.1, room.height_m),
		0.0,
		1.0
	)
	var o2_span: float = maxf(0.0001, retained_hot_layer_o2_start - retained_hot_layer_o2_full)
	var o2_factor: float = clampf(
		(retained_hot_layer_o2_start - room.o2) / o2_span,
		0.0,
		1.0
	)
	var support_factor: float = maxf(smoke_fill_fraction, o2_factor)
	if support_factor <= 0.0:
		return 0.0

	return room.height_m * retained_hot_layer_max_fraction * heat_factor * support_factor
	

func estimate_room_outside_open_factor(room: RoomModel) -> float:
	if room == null or _building == null:
		return 0.0

	var total_open_area_m2: float = 0.0
	for op in _building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var connects_outside: bool = (
			(op.a == room.id and op.b == BuildingModel.OUTSIDE_ID)
			or (op.b == room.id and op.a == BuildingModel.OUTSIDE_ID)
		)
		if not connects_outside:
			continue

		total_open_area_m2 += op.width_m * op.height_m * op.open_fraction

	if total_open_area_m2 <= 0.0:
		return 0.0

	var reference_area_m2: float = maxf(0.20, room.floor_area_m2() * outside_open_loss_area_fraction)
	return clampf(total_open_area_m2 / reference_area_m2, 0.0, 1.0)


func _apply_outside_assisted_background_heat_exchange(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	ambient_c: float,
	outside_open_path_factor_callable: Callable = Callable()
) -> void:
	if room_a == null or room_b == null or op == null or dt <= 0.0:
		return
	if outside_open_background_heat_exchange_kg_s_m2 <= 0.0:
		return

	var outside_open_factor: float = maxf(
		estimate_room_outside_open_factor(room_a),
		estimate_room_outside_open_factor(room_b)
	)
	if outside_open_factor <= 0.0:
		# Comprueba si alguna sala está conectada INDIRECTAMENTE al exterior
		# (p.ej. R0–R1 cuando R2 tiene una ventana abierta). El factor de ruta
		# se atenúa para reflejar que la señal llega a través de puertas intermedias.
		var path_a: float = _call_path_factor(outside_open_path_factor_callable, room_a.id)
		var path_b: float = _call_path_factor(outside_open_path_factor_callable, room_b.id)
		outside_open_factor = maxf(path_a, path_b) * 0.30
		if outside_open_factor <= 0.0:
			return

	var source: RoomModel = room_a
	var target: RoomModel = room_b
	if room_b.temp_upper_c > room_a.temp_upper_c:
		source = room_b
		target = room_a

	var source_excess_c: float = maxf(0.0, source.temp_upper_c - ambient_c)
	var target_excess_c: float = maxf(0.0, target.temp_upper_c - ambient_c)
	var delta_excess_c: float = source_excess_c - target_excess_c
	if delta_excess_c <= 1.0:
		return

	var area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_eff_m2 <= 0.0:
		return

	var pressure_drive: float = clampf(
		maxf(room_a.overpressure_pa, room_b.overpressure_pa) / maxf(0.5, pressure_spill_ref_delta_pa * 0.35),
		0.0,
		1.0
	)
	var smoke_drive: float = clampf(
		maxf(room_a.smoke_kg, room_b.smoke_kg) / 0.20,
		0.0,
		1.0
	)
	var heat_drive: float = clampf(delta_excess_c / 120.0, 0.0, 1.0)
	var drive: float = clampf(
		0.22 + 0.35 * pressure_drive + 0.25 * smoke_drive + 0.18 * heat_drive,
		0.0,
		1.0
	)

	var exchange_kg: float = area_eff_m2 \
			* outside_open_background_heat_exchange_kg_s_m2 \
			* outside_open_factor \
			* drive \
			* dt
	var air_mass_limit_kg: float = minf(room_a.volume_m3(), room_b.volume_m3()) * 1.2 \
			* outside_open_background_heat_max_fraction_per_step
	exchange_kg = minf(exchange_kg, air_mass_limit_kg)
	if exchange_kg <= 0.0:
		return

	var carry_intensity: float = clampf(
		outside_open_background_heat_carry_factor * (0.45 + 0.55 * drive),
		0.05,
		0.65
	)
	var transfer_temp_c: float = compute_interroom_transfer_temp_c(
		source,
		target,
		carry_intensity,
		smoke_drive
	)
	var heat_excess_c: float = maxf(0.0, transfer_temp_c - ambient_c)
	if heat_excess_c <= 0.25:
		return

	if source.upper_gas_kg > 0.0001 and source.upper_energy_kj > 0.0001:
		var gas_moved_kg: float = minf(
			exchange_kg,
			maxf(0.01, source.upper_gas_kg * 0.035)
		)
		var source_energy_removed_kj: float = gas_moved_kg * source_excess_c
		source_energy_removed_kj = minf(source_energy_removed_kj, source.upper_energy_kj * 0.08)
		if source_energy_removed_kj > 0.0:
			var energy_moved_kj: float = minf(
				gas_moved_kg * heat_excess_c,
				source_energy_removed_kj * lerpf(0.45, 0.72, clampf(outside_open_factor, 0.0, 1.0))
			)
			if energy_moved_kj > 0.0:
				source.upper_gas_kg = maxf(0.0, source.upper_gas_kg - gas_moved_kg)
				source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - source_energy_removed_kj)
				target.upper_gas_kg = maxf(0.0, target.upper_gas_kg + gas_moved_kg)
				target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + energy_moved_kj)

	var source_bulk_temp_c: float = lerpf(source.temp_lower_c, source.temp_upper_c, 0.18)
	var target_bulk_temp_c: float = target.temp_lower_c
	var bulk_delta_c: float = source_bulk_temp_c - target_bulk_temp_c
	if bulk_delta_c > 0.25:
		var source_air_mass_kg: float = maxf(1.0, source.volume_m3() * 1.2)
		var target_air_mass_kg: float = maxf(1.0, target.volume_m3() * 1.2)
		var bulk_exchange_kg: float = minf(
			exchange_kg,
			source_air_mass_kg * outside_open_background_heat_max_fraction_per_step
		)
		var source_available_kj: float = source_air_mass_kg * maxf(0.0, source_bulk_temp_c - ambient_c)
		var bulk_removed_kj: float = bulk_exchange_kg * bulk_delta_c * lerpf(0.32, 0.55, drive)
		bulk_removed_kj = minf(bulk_removed_kj, source_available_kj * 0.025)
		if bulk_removed_kj > 0.0:
			var bulk_delivered_kj: float = bulk_removed_kj * lerpf(0.35, 0.62, outside_open_factor)
			source.temp_lower_c = maxf(
				ambient_c,
				source.temp_lower_c - bulk_removed_kj / source_air_mass_kg
			)
			if source.upper_gas_kg <= 0.0001:
				source.temp_upper_c = source.temp_lower_c

			target.temp_lower_c += bulk_delivered_kj / target_air_mass_kg
			if target.upper_gas_kg <= 0.0001:
				target.temp_upper_c = maxf(target.temp_upper_c, target.temp_lower_c)

	sync_room_upper_layer(source, dt)
	sync_room_upper_layer(target, dt)


func remove_upper_layer_fraction(room: RoomModel, fraction: float) -> void:
	if room == null:
		return

	var frac: float = clampf(fraction, 0.0, 1.0)
	if frac <= 0.0:
		return

	room.upper_gas_kg *= (1.0 - frac)
	room.upper_energy_kj *= (1.0 - frac)


func reset_thermal_layer(room: RoomModel) -> void:
	if room == null:
		return

	room.thermal_layer_m = room.height_m


func estimate_thermal_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	if room.upper_gas_kg <= 0.000001:
		return room.height_m

	var hot_gas_density_kg_m3: float = gas_density_kg_m3(room.temp_upper_c)
	var hot_gas_volume_m3: float = room.upper_gas_kg / maxf(0.05, hot_gas_density_kg_m3)
	var hot_depth_m: float = hot_gas_volume_m3 / maxf(0.01, room.floor_area_m2())
	return clampf(room.height_m - hot_depth_m, 0.0, room.height_m)


func compute_interroom_transfer_temp_c(
	source: RoomModel,
	target: RoomModel,
	intensity: float,
	smoke_coupling: float = 0.0
) -> float:
	if source == null:
		return ambient_temp_c()

	var transfer_intensity: float = clampf(intensity, 0.0, 1.0)
	var smoke_weight: float = clampf(smoke_coupling, 0.0, 1.0)
	var thermal_only_upper_weight: float = clampf(0.18 + 0.38 * transfer_intensity, 0.18, 0.60)
	var smoke_loaded_upper_weight: float = clampf(0.18 + 0.50 * transfer_intensity, 0.18, 0.78)
	var upper_weight: float = lerpf(thermal_only_upper_weight, smoke_loaded_upper_weight, smoke_weight)
	var source_mix_temp_c: float = lerpf(source.temp_lower_c, source.temp_upper_c, upper_weight)
	var target_lower_c: float = target.temp_lower_c if target != null else ambient_temp_c()
	var thermal_only_carry_factor: float = clampf(
		0.16 + 0.33 * transfer_intensity + smoke_heat_mix_coeff * 3.0,
		0.18,
		0.58
	)
	var smoke_loaded_carry_factor: float = clampf(
		0.18 + 0.45 * transfer_intensity + smoke_heat_mix_coeff * 4.0,
		0.18,
		0.72
	)
	var carry_factor: float = lerpf(thermal_only_carry_factor, smoke_loaded_carry_factor, smoke_weight)
	return lerpf(target_lower_c, source_mix_temp_c, carry_factor)


func estimate_thermal_gradient_depth_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var hot_depth_m: float = maxf(0.0, room.height_m - effective_hot_layer_height_m(room))
	var smoke_depth_m: float = maxf(0.0, room.height_m - _smoke_model.get_visible_smoke_layer_height_m(room))
	var ref_depth_m: float = maxf(hot_depth_m, smoke_depth_m * thermal_gradient_band_fraction)
	if ref_depth_m <= 0.000001:
		return 0.0

	var min_span_m: float = maxf(0.50, minf(room.width_m, room.length_m))
	var max_span_m: float = maxf(room.width_m, room.length_m)
	if min_span_m > 0.0 and max_span_m > 0.0:
		var corridor_factor: float = clampf(inverse_lerp(2.0, 4.5, max_span_m / min_span_m), 0.0, 1.0)
		var heat_factor: float = clampf(inverse_lerp(80.0, 180.0, room.temp_upper_c), 0.0, 1.0)
		ref_depth_m *= lerpf(1.0, 0.72, corridor_factor * heat_factor)

	var min_band_m: float = minf(thermal_gradient_min_band_m, room.height_m)
	var smooth_depth_m: float = ref_depth_m
	if min_band_m > 0.000001 and ref_depth_m < min_band_m:
		var blend: float = clampf(ref_depth_m / min_band_m, 0.0, 1.0)
		smooth_depth_m = lerpf(ref_depth_m, min_band_m, blend)

	return clampf(
		smooth_depth_m,
		0.0,
		minf(thermal_gradient_max_band_m, room.height_m)
	)


func _compute_room_vertical_mix_bonus(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var min_span_m: float = maxf(0.50, minf(room.width_m, room.length_m))
	var max_span_m: float = maxf(room.width_m, room.length_m)
	if min_span_m <= 0.0 or max_span_m <= 0.0:
		return 0.0

	var slenderness: float = max_span_m / min_span_m
	if slenderness <= 2.0:
		return 0.0

	var corridor_factor: float = clampf(inverse_lerp(2.0, 4.5, slenderness), 0.0, 1.0)
	var hot_fill_m: float = maxf(0.0, room.height_m - effective_hot_layer_height_m(room))
	var fill_factor: float = clampf(hot_fill_m / maxf(0.35, room.height_m * 0.45), 0.0, 1.0)
	return 0.018 * corridor_factor * fill_factor


func _apply_post_transfer_vertical_mix(room: RoomModel, dt: float) -> void:
	if room == null or dt <= 0.0:
		return

	var mix_rate: float = _compute_room_vertical_mix_bonus(room)
	if mix_rate <= 0.0:
		return

	var delta_ul: float = maxf(0.0, room.temp_upper_c - room.temp_lower_c)
	if delta_ul <= 0.0 or room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		return

	var mix_energy_kj: float = room.upper_gas_kg * delta_ul * mix_rate * 0.45 * dt
	mix_energy_kj = minf(mix_energy_kj, room.upper_energy_kj)
	if mix_energy_kj <= 0.0:
		return

	room.upper_energy_kj -= mix_energy_kj
	var lower_mass_kg: float = maxf(
		1.0,
		gas_density_kg_m3(room.temp_lower_c) * room.floor_area_m2() * maxf(0.2, effective_hot_layer_height_m(room))
	)
	room.temp_lower_c += mix_energy_kj / lower_mass_kg
	sync_room_upper_layer(room, dt)


func estimate_floor_cooling_band_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var ambient_c: float = ambient_temp_c()
	var lower_excess_c: float = maxf(0.0, room.temp_lower_c - ambient_c)
	if lower_excess_c <= 0.5:
		return 0.0

	var lower_layer_height_m: float = clampf(effective_hot_layer_height_m(room), 0.0, room.height_m)
	if lower_layer_height_m <= 0.000001:
		return 0.0

	var activation: float = clampf(
		lower_excess_c / maxf(1.0, survival_temp_threshold_c - ambient_c),
		0.0,
		1.0
	)
	var band_m: float = lower_layer_height_m * floor_cooling_band_fraction * activation
	return clampf(band_m, 0.0, minf(floor_cooling_band_max_m, lower_layer_height_m))


func estimate_temperature_at_height_m(room: RoomModel, height_m: float) -> float:
	if room == null:
		return ambient_temp_c()

	var ambient_c: float = ambient_temp_c()
	var z_m: float = clampf(height_m, 0.0, room.height_m)
	var gradient_depth_m: float = estimate_thermal_gradient_depth_m(room)
	var floor_band_m: float = estimate_floor_cooling_band_m(room)
	if gradient_depth_m <= 0.000001:
		if floor_band_m > 0.000001 and z_m <= floor_band_m:
			var floor_t_no_gradient: float = inverse_lerp(0.0, floor_band_m, z_m)
			return lerpf(ambient_c, room.temp_lower_c, floor_t_no_gradient)
		return room.temp_lower_c

	var gradient_bottom_m: float = clampf(room.height_m - gradient_depth_m, 0.0, room.height_m)
	if floor_band_m > 0.000001 and z_m <= floor_band_m:
		var floor_t: float = inverse_lerp(0.0, floor_band_m, z_m)
		return lerpf(ambient_c, room.temp_lower_c, floor_t)

	if z_m <= gradient_bottom_m:
		return room.temp_lower_c
	if z_m >= room.height_m:
		return room.temp_upper_c

	var t: float = inverse_lerp(gradient_bottom_m, room.height_m, z_m)
	return lerpf(room.temp_lower_c, room.temp_upper_c, t)


func estimate_isotherm_height_m(room: RoomModel, threshold_c: float) -> float:
	if room == null:
		return 0.0

	var ambient_c: float = ambient_temp_c()
	var floor_band_m: float = estimate_floor_cooling_band_m(room)
	if threshold_c <= ambient_c:
		return 0.0
	if threshold_c <= room.temp_lower_c:
		if floor_band_m <= 0.000001 or absf(room.temp_lower_c - ambient_c) <= 0.001:
			return 0.0

		var floor_t: float = clampf(
			(threshold_c - ambient_c) / (room.temp_lower_c - ambient_c),
			0.0,
			1.0
		)
		return clampf(lerpf(0.0, floor_band_m, floor_t), 0.0, room.height_m)
	if threshold_c >= room.temp_upper_c:
		return room.height_m

	var gradient_depth_m: float = estimate_thermal_gradient_depth_m(room)
	if gradient_depth_m <= 0.000001:
		return room.height_m

	var gradient_bottom_m: float = clampf(room.height_m - gradient_depth_m, 0.0, room.height_m)
	if absf(room.temp_upper_c - room.temp_lower_c) <= 0.001:
		return room.height_m

	var t: float = clampf(
		(threshold_c - room.temp_lower_c) / (room.temp_upper_c - room.temp_lower_c),
		0.0,
		1.0
	)
	return clampf(lerpf(gradient_bottom_m, room.height_m, t), 0.0, room.height_m)


func update_room_layer_150c(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var raw_layer_150c_m: float = estimate_isotherm_height_m(room, survival_temp_threshold_c)
	if room.layer_150c_m < 0.0 or room.layer_150c_m > room.height_m + 0.001:
		room.layer_150c_m = raw_layer_150c_m
		return

	if raw_layer_150c_m < room.layer_150c_m:
		var down_t: float = clampf(layer_150c_relax_down_per_s * dt, 0.0, 1.0)
		room.layer_150c_m = lerpf(room.layer_150c_m, raw_layer_150c_m, down_t)
	else:
		var up_t: float = clampf(layer_150c_relax_up_per_s * dt, 0.0, 1.0)
		room.layer_150c_m = lerpf(room.layer_150c_m, raw_layer_150c_m, up_t)

	room.layer_150c_m = clampf(room.layer_150c_m, 0.0, room.height_m)


func compute_co_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	return room.co_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 28.0)


func compute_co_upper_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var upper_gas_mass_kg: float = maxf(0.1, room.upper_gas_kg)
	var co_upper_kg: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
	return co_upper_kg * 29.0e6 / maxf(0.1, upper_gas_mass_kg * 28.0)


func compute_co_lower_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var lower_gas_mass_kg: float = maxf(0.1, room.volume_m3() * 1.2 - room.upper_gas_kg)
	var co_lower_kg: float = maxf(0.0, room.co_kg - clampf(room.co_upper_kg, 0.0, room.co_kg))
	return co_lower_kg * 29.0e6 / maxf(0.1, lower_gas_mass_kg * 28.0)


func compute_co2_ppm(room: RoomModel) -> float:
	if room == null:
		return 0.0

	# Conversión masa CO2 → ppm volumétrico.
	# ppm = (m_co2 / M_co2) / (m_air / M_air) × 1e6
	# M_co2 = 44 g/mol, M_air = 29 g/mol
	return room.co2_kg * 29.0e6 / maxf(0.1, room.volume_m3() * 1.2 * 44.0)


## Paso incremental de FED (Fractional Effective Dose) según ISO 13571.
## Modelo asfixiante implementado:
## - FED_CO: narcosis por CO con factor de hiperventilación por CO2
## - FED_O2: hipoxia por depleción de oxígeno
## FED_total(Δt) = FED_CO(Δt) + FED_O2(Δt)
func step_fed(room: RoomModel, dt: float) -> void:
	if room == null or dt <= 0.0:
		return

	var co_ppm: float = compute_co_ppm(room)
	var co2_ppm: float = compute_co2_ppm(room)

	var dt_min: float = dt / 60.0
	var delta_fed: float = 0.0

	# ISO 13571 Eq. 2-3: dosis incremental por CO, con ajuste por CO2 solo > 2% vol.
	if co_ppm > 0.0:
		var co2_pct: float = co2_ppm / 10000.0
		var v_co2: float = 1.0
		if co2_pct > 2.0:
			v_co2 = exp(0.1903 * co2_pct + 2.0004) / 7.1
		delta_fed += 3.317e-5 * pow(co_ppm, 1.036) * v_co2 * dt_min

	# ISO 13571 (modelo asfixiante): componente de hipoxia por O2.
	if fed_hypoxia_enabled:
		var o2_pct: float = clampf(room.o2 * 100.0, 0.0, 20.9)
		var o2_deficit_pct: float = maxf(0.0, 20.9 - o2_pct)
		if o2_deficit_pct > 0.0:
			var t_crit_min: float = exp(fed_hypoxia_a - fed_hypoxia_b * o2_deficit_pct)
			if t_crit_min > 0.0:
				delta_fed += dt_min / t_crit_min

	room.fed += maxf(0.0, delta_fed)

	# SVV instantánea y peor histórica (monótona no creciente).
	room.svv_pct = _compute_svv_pct_from_room(room)
	room.svv_worst_pct = minf(room.svv_worst_pct, room.svv_pct)


func _compute_svv_pct_from_room(room: RoomModel) -> float:
	if room == null:
		return 100.0

	var height_m: float = maxf(0.1, room.height_m)
	var layer_150c: float = clampf(room.layer_150c_m, 0.0, height_m)
	var fed_val: float = maxf(0.0, room.fed)

	# Criterio térmico (isoterma 150°C, altura desde suelo).
	var thermal_svv: float
	if layer_150c >= 1.8:
		thermal_svv = 1.0
	elif layer_150c >= 0.5:
		thermal_svv = 0.90 + 0.09 * (layer_150c - 0.5) / 1.3
	elif layer_150c > 0.10:
		thermal_svv = 0.05 + 0.85 * ((layer_150c - 0.10) / 0.40)
	else:
		thermal_svv = 0.0

	# Criterio FED (zonas tenabilidad):
	# <=0.1: ALTA, 0.1-0.3: MEDIA, 0.3-1.0: BAJA, >1.0: MÍNIMA hacia 0%.
	var fed_svv: float
	if fed_val <= 0.1:
		fed_svv = 1.0 - 0.01 * (fed_val / 0.1)
	elif fed_val <= 0.3:
		fed_svv = 0.99 - 0.09 * ((fed_val - 0.1) / 0.2)
	elif fed_val < 1.0:
		# BAJA→MÍNIMA: curva convexa potencia 1.5 (ISO 13571: FED=1.0 = incapacitación media)
		var t_fed: float = (fed_val - 0.3) / 0.7
		fed_svv = 0.90 * pow(1.0 - t_fed, 1.5)
	else:
		fed_svv = 0.0

	return clampf(minf(thermal_svv, fed_svv) * 100.0, 0.0, 100.0)


func is_room_quiescent(room: RoomModel) -> bool:
	if room == null:
		return true

	return (
		room.fire == null
		and room.hrr_kw <= 0.01
		and room.overpressure_pa <= 0.05
		and room.smoke_kg <= 0.0005
		and room.upper_gas_kg <= 0.001
		and room.upper_energy_kj <= 0.01
		and absf(room.temp_upper_c - ambient_temp_c()) <= 0.5
	)


func _should_collapse_thermal_layer(room: RoomModel) -> bool:
	if room == null:
		return true

	return (
		room.fire == null
		and room.hrr_kw <= 0.01
		and room.overpressure_pa <= 0.10
		and room.upper_energy_kj <= 0.5
		and absf(room.temp_upper_c - room.temp_lower_c) <= 0.5
		and absf(room.temp_upper_c - ambient_temp_c()) <= 1.0
	)


func _call_path_factor(callable: Callable, room_id: int) -> float:
	if not callable.is_valid():
		return 0.0
	return clampf(float(callable.call(room_id)), 0.0, 1.0)


func sync_room_upper_layer(room: RoomModel, dt: float) -> void:
	if room == null:
		return

	var ambient_c: float = ambient_temp_c()
	room.upper_gas_kg = maxf(0.0, room.upper_gas_kg)
	room.upper_energy_kj = maxf(0.0, room.upper_energy_kj)

	if _should_collapse_thermal_layer(room):
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.co_upper_kg = 0.0
		room.temp_upper_c = room.temp_lower_c
		reset_thermal_layer(room)
		_smoke_model.recompute_layer_from_mass(room, dt)
		return

	if room.upper_gas_kg <= 0.0001 or room.upper_energy_kj <= 0.0001:
		room.upper_gas_kg = 0.0
		room.upper_energy_kj = 0.0
		room.co_upper_kg = 0.0
		room.temp_upper_c = maxf(room.temp_lower_c, ambient_c)
		reset_thermal_layer(room)
		_smoke_model.recompute_layer_from_mass(room, dt)
		return

	room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)
	room.temp_upper_c = ambient_c + room.upper_energy_kj / maxf(0.05, room.upper_gas_kg)
	room.temp_upper_c = clampf(room.temp_upper_c, room.temp_lower_c, max_upper_temp_c)
	room.upper_energy_kj = room.upper_gas_kg * maxf(0.0, room.temp_upper_c - ambient_c)
	var target_thermal_layer_m: float = estimate_thermal_layer_height_m(room)
	if target_thermal_layer_m < room.thermal_layer_m:
		room.thermal_layer_m = lerpf(
			room.thermal_layer_m,
			target_thermal_layer_m,
			clampf(layer_relax_down * dt * 2.0, 0.0, 1.0)
		)
	else:
		room.thermal_layer_m = lerpf(
			room.thermal_layer_m,
			target_thermal_layer_m,
			clampf(layer_relax_up * dt, 0.0, 1.0)
		)
	_smoke_model.recompute_layer_from_mass(room, dt)


func estimate_plume_upper_depth_m(room: RoomModel) -> float:
	if room == null or room.hrr_kw <= 0.0:
		return 0.0

	var floor_area_m2: float = maxf(1.0, room.floor_area_m2())
	var response: float = 1.0
	if plume_fill_response_s > 0.0:
		response = 1.0 - exp(-room.fire_time_s / plume_fill_response_s)

	# Heurística simple de entrainment para aproximar la masa de gases calientes
	# que alimenta la capa superior en un modelo zonal.
	var depth_m: float = plume_fill_depth_coeff * sqrt(room.hrr_kw) * response / floor_area_m2
	var max_depth_m: float = room.height_m * plume_fill_max_fraction
	return clampf(depth_m, 0.0, max_depth_m)


func effective_hot_layer_height_m(room: RoomModel) -> float:
	if room == null:
		return 0.0

	var plume_layer_m: float = room.height_m - estimate_plume_upper_depth_m(room)
	return clampf(minf(room.thermal_layer_m, plume_layer_m), 0.0, room.height_m)


func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float:
	if room == null:
		return lintel_m

	return minf(lintel_m, clampf(interior_spill_start_layer_m, 0.0, room.height_m))


func build_interior_opening_flow_state(room_a: RoomModel, room_b: RoomModel, op: OpeningModel) -> Dictionary:
	var state: Dictionary = {
		"active": false,
		"hot_room": null,
		"cold_room": null,
		"hot_band_m": 0.0,
		"smoke_band_m": 0.0,
		"h_drive_m": 0.0,
		"area_eff_m2": 0.0,
		"engagement": 0.0,
		"source_temp_c": 0.0,
		"temp_delta_k": 0.0
	}

	if room_a == null or room_b == null or op == null or op.open_fraction <= 0.0:
		return state

	var hot_room: RoomModel
	var cold_room: RoomModel
	if room_a.temp_upper_c > room_b.temp_upper_c:
		hot_room = room_a
		cold_room = room_b
	elif room_b.temp_upper_c > room_a.temp_upper_c:
		hot_room = room_b
		cold_room = room_a
	elif room_a.overpressure_pa >= room_b.overpressure_pa:
		hot_room = room_a
		cold_room = room_b
	else:
		hot_room = room_b
		cold_room = room_a

	var lintel_m: float = op.lintel_height_m()
	var spill_trigger_layer_m: float = _interior_spill_trigger_layer_m(hot_room, lintel_m)
	var hot_band_m: float = maxf(0.0, spill_trigger_layer_m - effective_hot_layer_height_m(hot_room))
	var smoke_band_m: float = maxf(
		0.0,
		spill_trigger_layer_m - _smoke_model.get_visible_smoke_layer_height_m(hot_room)
	)
	var band_ref_m: float = maxf(doorway_o2_min_band_m, op.height_m * 0.24)
	var smoke_factor: float = clampf(smoke_band_m / band_ref_m, 0.0, 1.0)
	var thermal_factor: float = clampf(hot_band_m / band_ref_m, 0.0, 1.0)
	var pressure_factor: float = clampf(
		maxf(0.0, hot_room.overpressure_pa - cold_room.overpressure_pa) / maxf(
			1.0,
			pressure_spill_ref_delta_pa
		),
		0.0,
		1.0
	)
	var band_factor: float = lerpf(thermal_factor, smoke_factor, doorway_o2_smoke_weight)
	var engagement: float = clampf(
		band_factor + pressure_factor * doorway_o2_pressure_weight,
		0.0,
		1.0
	)
	if engagement <= 0.0:
		return state

	var lower_counterflow_m: float = doorway_o2_min_band_m * clampf(0.35 + 0.65 * engagement, 0.0, 1.0)
	var h_drive_m: float = maxf(maxf(lower_counterflow_m, hot_band_m), smoke_band_m * 0.40)
	if h_drive_m <= 0.0:
		return state

	var area_eff_m2: float = op.width_m * minf(h_drive_m, op.height_m) * op.open_fraction
	if area_eff_m2 <= 0.0:
		return state

	var smoke_coupling: float = clampf(
		maxf(smoke_factor, cold_room.smoke_kg / 0.10),
		0.0,
		1.0
	)
	var source_temp_c: float = compute_interroom_transfer_temp_c(
		hot_room,
		cold_room,
		clampf(0.35 + 0.65 * engagement, 0.0, 1.0),
		smoke_coupling
	)
	var sink_temp_c: float = lerpf(cold_room.temp_lower_c, cold_room.temp_upper_c, 0.20)
	var temp_delta_k: float = maxf(0.0, source_temp_c - sink_temp_c)
	if temp_delta_k < 2.0:
		return state

	state["active"] = true
	state["hot_room"] = hot_room
	state["cold_room"] = cold_room
	state["hot_band_m"] = hot_band_m
	state["smoke_band_m"] = smoke_band_m
	state["h_drive_m"] = h_drive_m
	state["area_eff_m2"] = area_eff_m2
	state["engagement"] = engagement
	state["source_temp_c"] = source_temp_c
	state["temp_delta_k"] = temp_delta_k
	return state
