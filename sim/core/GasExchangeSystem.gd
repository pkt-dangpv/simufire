extends RefCounted
class_name GasExchangeSystem

const LayerInterfaceModel = preload("res://sim/core/LayerInterfaceModel.gd")

# ============================================================
# GAS EXCHANGE SYSTEM
# ------------------------------------------------------------
# Gestiona el transporte de gases (humo, CO, CO2) y
# la presión entre habitaciones y con el exterior:
# - step_pressure_venting: venting boyante por aperturas
# - step_smoke: generación, transporte y deposición de humo
# - Purga post-incendio de CO/CO2/humo al reventilarse
# - Transporte retardado interior (pendientes en cola)
# ============================================================

var o2_nominal: float = 0.209
var window_leakage_area_m2: float = 0.005
var pressure_vent_threshold_pa: float = 2.0
var ach_infiltration: float = 0.5
var interior_transport_enabled: bool = true
var interior_transport_speed_m_s: float = 0.20
var interior_transport_min_distance_m: float = 0.50
var postfire_cleanup_hot_stop_c: float = 90.0
var postfire_cleanup_cool_full_c: float = 35.0
var postfire_cleanup_pressure_stop_pa: float = 0.8
var postfire_cleanup_pressure_full_pa: float = 0.10
var smoke_settling_base_per_s: float = 0.00004
var smoke_settling_bonus_per_s: float = 0.00018
var co_postfire_purge_base_per_s: float = 0.0
var co_postfire_purge_bonus_per_s: float = 0.0
var outside_open_species_purge_base_per_s: float = 0.0
var outside_open_species_purge_bonus_per_s: float = 0.0
var outside_open_species_temp_start_c: float = 60.0
var outside_open_species_temp_full_c: float = 220.0
var outside_open_species_pressure_ref_pa: float = 4.0
var outside_open_species_upper_bias: float = 0.80
var background_species_exchange_kg_s_m2: float = 0.035
var background_o2_exchange_multiplier: float = 0.0
var background_species_path_multiplier_max: float = 3.00
var background_species_max_fraction_closed: float = 0.010
var background_species_max_fraction_open: float = 0.040
var flow_path_direct_fire_vent_reduction: float = 0.0
var flow_path_direct_fire_min_vent_fraction: float = 0.0
var flow_path_interior_pull_boost: float = 0.0
var flow_path_interior_pull_max_multiplier: float = 1.0
var flow_path_remote_decay_per_door: float = 0.60
var flow_path_remote_max_doors: int = 4
# Efecto chimenea (stack effect): incremento de presión en salas de plantas
# superiores (floor_level_z_m > 0) por el gradiente térmico vertical.
# ΔP_stack = ρ_ext × g × floor_level_z_m × (1 - T_ext / T_upper)
# Referencia: SFPE Handbook, 5ª ed. §9.1 — stack effect in buildings.
var stack_effect_enabled: bool = true
# Efecto del viento en aperturas exteriores.
# ΔP_viento = ½ × ρ × v² × Cp, donde Cp depende del ángulo entre la
# dirección del viento y la normal exterior de la cara (wall_side).
# Barlovento: Cp ≈ +0.6 × cos (presión positiva, dificulta el venteo).
# Sotavento: Cp ≈ −0.4 × |cos| (succión, facilita el venteo).
# Referencia: EN 1991-1-4 §7.2 — wind pressure coefficients.
var wind_effect_enabled: bool = true
# Deformación de puerta por temperatura: cuando la capa superior de la sala
# adyacente supera door_deform_temp_start_c, el marco de madera se deforma y
# crea un gap efectivo adicional (thermal_gap_fraction en OpeningModel).
# Solo aplica a puertas interiores (type == DOOR). Simula la realidad de que
# incluso una puerta cerrada pierde hermeticidad a altas temperaturas.
# Referencia: NFPA 80, SFPE Handbook §2.9 — door gap under fire conditions.
var door_deform_enabled: bool = true
var door_deform_temp_start_c: float = 150.0  # temperatura a la que empieza la deformación
var door_deform_temp_full_c: float = 350.0   # temperatura con gap máximo
var door_deform_max_gap: float = 0.04        # fracción máxima de apertura adicional (4 %)
# Fracción del área de la abertura exterior que actúa como entrada de aire fresco.
# Asume plano neutro a mid-height por defecto (0.5). En salas muy calientes el
# plano neutro sube y la fracción de entrada efectiva baja (<0.5).
var natural_vent_inlet_fraction: float = 0.5
# SF-AUD-010: cuando true, la ventilación natural exterior usa plano neutro
# calculado por densidad (SFPE §3.2) en lugar de natural_vent_inlet_fraction fijo.
var vent_bernoulli_enabled: bool = true
# Multiplicador sobre el caudal Bernoulli calculado — solo para mutation testing (M-VENT).
var vent_bernoulli_flow_multiplier: float = 1.0
# Carry de O2 con el parcel caliente en transporte de humo inter-sala.
# 0.0 = deshabilitado (default; baselines sin cambio).
var o2_smoke_carry_coeff: float = 0.0
# Coeficiente de contraflujo de O2 en transporte de humo inter-sala (doorway).
# Controla cuánto O2 se intercambia entre salas cuando pasa humo por la apertura.
# 0.18 = valor histórico. Reducir para ralentizar la dilución de O2 en salas remotas.
var doorway_o2_counterflow_coeff: float = 0.18
var two_zone_opening_flow_enabled: bool = false
# Phase 3+ F2.0: ledger acumulativo de flujos de masa zonal (parcels/background).
# Solo instrumentación pasiva; sin efecto físico. Default false = no-op.
var phase3_zone_diagnostics_enabled: bool = false
# Phase 3: modelo de presión termodinámica — ODE campo paralelo.
# Cuando false (default): no-op, no toca room.pressure_pa_therm ni room.overpressure_pa.
# Cuando true: integra dP/dt = (gamma-1)/V * Q_conv - Cd*A_eff/V * P_atm * sqrt(2P/rho)
# usando room.hrr_kw como fuente de calor convectiva.
var phase3_thermodynamic_pressure_enabled: bool = false
# Opt-in M3/M4: cuando true, pressure_pa_therm pasa a ser la presión usada por
# los flujos. Default false mantiene la presión de boyanza/stack heredada.
var phase3_pressure_canonical_enabled: bool = false
# En modo canónico, una red interior abierta comparte presión termodinámica.
# Esto evita saltos no físicos sala-a-sala dentro de un mismo volumen conectado.
var phase3_pressure_component_equalization_enabled: bool = true
# Área efectiva de infiltración [m²]. 0.0 = derivar de ach_infiltration (ver fórmula).
var phase3_leak_area_m2: float = 0.0
# Fracción convectiva del HRR para la ODE de presión.
# CFAST/SFPE standard: 0.70 convectivo (chi_rad=0.30 radiativo).
# Valor 0.70 cierra gap HVAC-1 ~15-25% (era 0.65: subestimaba P_ss ~16%).
# Este parámetro es independiente de hrr_chi_rad_normal (que calibra T_upper en SF).
var phase3_chi_conv: float = 0.70
var _pending_interior_deliveries: Array[Dictionary] = []
var _inflight_species_kg: Dictionary = {}


func configure(settings: Dictionary) -> void:
	o2_nominal = float(settings.get("o2_nominal", o2_nominal))
	window_leakage_area_m2 = float(settings.get("window_leakage_area_m2", window_leakage_area_m2))
	pressure_vent_threshold_pa = float(settings.get("pressure_vent_threshold_pa", pressure_vent_threshold_pa))
	ach_infiltration = float(settings.get("ach_infiltration", ach_infiltration))
	interior_transport_enabled = bool(settings.get("interior_transport_enabled", interior_transport_enabled))
	interior_transport_speed_m_s = float(settings.get("interior_transport_speed_m_s", interior_transport_speed_m_s))
	interior_transport_min_distance_m = float(settings.get("interior_transport_min_distance_m", interior_transport_min_distance_m))
	postfire_cleanup_hot_stop_c = float(settings.get("postfire_cleanup_hot_stop_c", postfire_cleanup_hot_stop_c))
	postfire_cleanup_cool_full_c = float(settings.get("postfire_cleanup_cool_full_c", postfire_cleanup_cool_full_c))
	postfire_cleanup_pressure_stop_pa = float(settings.get("postfire_cleanup_pressure_stop_pa", postfire_cleanup_pressure_stop_pa))
	postfire_cleanup_pressure_full_pa = float(settings.get("postfire_cleanup_pressure_full_pa", postfire_cleanup_pressure_full_pa))
	smoke_settling_base_per_s = float(settings.get("smoke_settling_base_per_s", smoke_settling_base_per_s))
	smoke_settling_bonus_per_s = float(settings.get("smoke_settling_bonus_per_s", smoke_settling_bonus_per_s))
	co_postfire_purge_base_per_s = float(settings.get("co_postfire_purge_base_per_s", co_postfire_purge_base_per_s))
	co_postfire_purge_bonus_per_s = float(settings.get("co_postfire_purge_bonus_per_s", co_postfire_purge_bonus_per_s))
	outside_open_species_purge_base_per_s = float(
		settings.get("outside_open_species_purge_base_per_s", outside_open_species_purge_base_per_s)
	)
	outside_open_species_purge_bonus_per_s = float(
		settings.get("outside_open_species_purge_bonus_per_s", outside_open_species_purge_bonus_per_s)
	)
	outside_open_species_temp_start_c = float(
		settings.get("outside_open_species_temp_start_c", outside_open_species_temp_start_c)
	)
	outside_open_species_temp_full_c = float(
		settings.get("outside_open_species_temp_full_c", outside_open_species_temp_full_c)
	)
	outside_open_species_pressure_ref_pa = float(
		settings.get("outside_open_species_pressure_ref_pa", outside_open_species_pressure_ref_pa)
	)
	outside_open_species_upper_bias = float(
		settings.get("outside_open_species_upper_bias", outside_open_species_upper_bias)
	)
	background_species_exchange_kg_s_m2 = float(
		settings.get("background_species_exchange_kg_s_m2", background_species_exchange_kg_s_m2)
	)
	background_o2_exchange_multiplier = float(
		settings.get("background_o2_exchange_multiplier", background_o2_exchange_multiplier)
	)
	background_species_path_multiplier_max = float(
		settings.get("background_species_path_multiplier_max", background_species_path_multiplier_max)
	)
	background_species_max_fraction_closed = float(
		settings.get("background_species_max_fraction_closed", background_species_max_fraction_closed)
	)
	background_species_max_fraction_open = float(
		settings.get("background_species_max_fraction_open", background_species_max_fraction_open)
	)
	flow_path_direct_fire_vent_reduction = float(
		settings.get("flow_path_direct_fire_vent_reduction", flow_path_direct_fire_vent_reduction)
	)
	flow_path_direct_fire_min_vent_fraction = float(
		settings.get("flow_path_direct_fire_min_vent_fraction", flow_path_direct_fire_min_vent_fraction)
	)
	flow_path_interior_pull_boost = float(
		settings.get("flow_path_interior_pull_boost", flow_path_interior_pull_boost)
	)
	flow_path_interior_pull_max_multiplier = float(
		settings.get("flow_path_interior_pull_max_multiplier", flow_path_interior_pull_max_multiplier)
	)
	flow_path_remote_decay_per_door = float(
		settings.get("flow_path_remote_decay_per_door", flow_path_remote_decay_per_door)
	)
	flow_path_remote_max_doors = int(
		settings.get("flow_path_remote_max_doors", flow_path_remote_max_doors)
	)
	stack_effect_enabled = bool(settings.get("stack_effect_enabled", stack_effect_enabled))
	wind_effect_enabled = bool(settings.get("wind_effect_enabled", wind_effect_enabled))
	door_deform_enabled = bool(settings.get("door_deform_enabled", door_deform_enabled))
	door_deform_temp_start_c = float(settings.get("door_deform_temp_start_c", door_deform_temp_start_c))
	door_deform_temp_full_c = float(settings.get("door_deform_temp_full_c", door_deform_temp_full_c))
	door_deform_max_gap = float(settings.get("door_deform_max_gap", door_deform_max_gap))
	natural_vent_inlet_fraction = float(settings.get("natural_vent_inlet_fraction", natural_vent_inlet_fraction))
	vent_bernoulli_enabled = bool(settings.get("vent_bernoulli_enabled", vent_bernoulli_enabled))
	vent_bernoulli_flow_multiplier = float(settings.get("vent_bernoulli_flow_multiplier", vent_bernoulli_flow_multiplier))
	o2_smoke_carry_coeff = float(settings.get("o2_smoke_carry_coeff", o2_smoke_carry_coeff))
	doorway_o2_counterflow_coeff = float(settings.get("doorway_o2_counterflow_coeff", doorway_o2_counterflow_coeff))
	two_zone_opening_flow_enabled = bool(settings.get("two_zone_opening_flow_enabled", two_zone_opening_flow_enabled))
	phase3_zone_diagnostics_enabled = bool(settings.get("phase3_zone_diagnostics_enabled", phase3_zone_diagnostics_enabled))
	phase3_thermodynamic_pressure_enabled = bool(
		settings.get("phase3_thermodynamic_pressure_enabled", phase3_thermodynamic_pressure_enabled)
	)
	phase3_pressure_canonical_enabled = bool(
		settings.get("phase3_pressure_canonical_enabled", phase3_pressure_canonical_enabled)
	)
	phase3_pressure_component_equalization_enabled = bool(
		settings.get(
			"phase3_pressure_component_equalization_enabled",
			phase3_pressure_component_equalization_enabled
		)
	)
	phase3_leak_area_m2 = float(settings.get("phase3_leak_area_m2", phase3_leak_area_m2))
	phase3_chi_conv = float(settings.get("phase3_chi_conv", phase3_chi_conv))


func step_thermodynamic_pressure(building: BuildingModel, dt: float) -> void:
	## Phase 3 — ODE de presión termodinámica (campo room.pressure_pa_therm).
	## Default no-op cuando phase3_thermodynamic_pressure_enabled = false.
	## Solo modifica room.overpressure_pa si phase3_pressure_canonical_enabled = true.
	if not phase3_thermodynamic_pressure_enabled:
		return
	if building == null:
		return
	const GAMMA: float = 1.4
	const P_ATM: float = 101325.0
	const RHO_AMB: float = 1.2
	const CD: float = 0.61
	const P_REF_ACH: float = 50.0  # Pa de referencia para derivar A_eff de ACH (blower door)
	for room in building.get_rooms().values():
		if room == null:
			continue
		var V: float = room.volume_m3()
		if V <= 0.0:
			continue
		# Área efectiva de infiltración
		var a_eff: float = phase3_leak_area_m2
		if a_eff <= 0.0:
			# Derivar de ach_infiltration: Q(P_ref) = ACH*V/3600 = Cd*A*sqrt(2*P_ref/rho)
			var q_ref_m3s: float = ach_infiltration * V / 3600.0
			a_eff = q_ref_m3s / (CD * sqrt(2.0 * P_REF_ACH / RHO_AMB))
		# Sumar áreas de TODAS las aperturas abiertas conectadas a esta sala.
		# Las interiores abiertas son vías de alivio de presión hacia salas adyacentes
		# (que eventualmente conectan al exterior). Sin este canal, salas con dinteles
		# abiertos acumulan 100k+ Pa porque el único sumidero era la infiltración ACH.
		for op in building.get_openings():
			if op.a != room.id and op.b != room.id:
				continue
			var _frac_pv: float = op.open_fraction_smooth if op.is_exterior_opening() else op.open_fraction
			if _frac_pv > 0.001:
				a_eff += op.width_m * op.height_m * _frac_pv
		# ODE fuente: Q_conv = HRR * phase3_chi_conv * 1000 W
		var q_conv_w: float = room.hrr_kw * phase3_chi_conv * 1000.0
		var dp_source: float = (GAMMA - 1.0) * q_conv_w / V
		# ODE sumidero: flujo de infiltración Bernoulli
		var p: float = room.pressure_pa_therm
		var dp_leak: float = 0.0
		if p > 0.0:
			dp_leak = CD * a_eff / V * P_ATM * sqrt(2.0 * p / RHO_AMB)
		room.pressure_pa_therm = maxf(0.0, p + (dp_source - dp_leak) * dt)
	if phase3_pressure_canonical_enabled:
		if phase3_pressure_component_equalization_enabled:
			_equalize_thermodynamic_pressure_components(building)
		else:
			_promote_thermodynamic_pressure_to_overpressure(building)


func _promote_thermodynamic_pressure_to_overpressure(building: BuildingModel) -> void:
	if building == null:
		return
	for room in building.get_rooms().values():
		if room == null:
			continue
		room.overpressure_pa = room.pressure_pa_therm


func _equalize_thermodynamic_pressure_components(building: BuildingModel) -> void:
	if building == null:
		return
	var visited: Dictionary = {}
	for raw_room_id in building.get_rooms().keys():
		var start_id: int = int(raw_room_id)
		if visited.has(start_id):
			continue
		var component_ids: Array = []
		var pending_ids: Array = [start_id]
		visited[start_id] = true
		while not pending_ids.is_empty():
			var room_id: int = int(pending_ids.pop_back())
			component_ids.append(room_id)
			for op in building.get_openings():
				if op == null or op.is_exterior_opening():
					continue
				if op.effective_open_fraction() <= 0.001:
					continue
				var next_id: int = BuildingModel.OUTSIDE_ID
				if op.a == room_id:
					next_id = int(op.b)
				elif op.b == room_id:
					next_id = int(op.a)
				else:
					continue
				if not building.get_rooms().has(next_id) or visited.has(next_id):
					continue
				visited[next_id] = true
				pending_ids.append(next_id)

		var pressure_volume_sum: float = 0.0
		var volume_sum: float = 0.0
		for component_room_id in component_ids:
			var component_room: RoomModel = building.get_room(int(component_room_id))
			if component_room == null:
				continue
			var volume_m3: float = maxf(0.001, component_room.volume_m3())
			pressure_volume_sum += component_room.pressure_pa_therm * volume_m3
			volume_sum += volume_m3
		if volume_sum <= 0.0:
			continue
		var component_pressure_pa: float = pressure_volume_sum / volume_sum
		for component_room_id in component_ids:
			var room_to_update: RoomModel = building.get_room(int(component_room_id))
			if room_to_update == null:
				continue
			room_to_update.pressure_pa_therm = component_pressure_pa
			room_to_update.overpressure_pa = component_pressure_pa


func reset() -> void:
	_pending_interior_deliveries.clear()
	_inflight_species_kg.clear()


func get_pending_carbon_kg() -> float:
	var total_c_kg: float = 0.0
	for raw_entry in _pending_interior_deliveries:
		var entry: Dictionary = raw_entry
		total_c_kg += maxf(0.0, float(entry.get("co_kg", 0.0))) * (12.0 / 28.0) \
				+ maxf(0.0, float(entry.get("co2_kg", 0.0))) * (12.0 / 44.0) \
				+ maxf(0.0, float(entry.get("hcn_kg", 0.0))) * (12.0 / 27.0) \
				+ maxf(0.0, float(entry.get("smoke_kg", 0.0))) * 0.87
	return total_c_kg


# SF-S0: humo en tránsito inter-sala (removido de origen, aún no entregado al destino).
func get_smoke_in_transit_kg() -> float:
	var total: float = 0.0
	for raw_entry in _pending_interior_deliveries:
		total += maxf(0.0, float(raw_entry.get("smoke_kg", 0.0)))
	return total


func step_pressure_venting(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"smoke_vented_kg": 0.0
	}
	if building == null:
		return result

	var remove_upper_layer_fraction_callable: Callable = hooks.get("remove_upper_layer_fraction_callable", Callable())
	var sync_room_upper_layer_callable: Callable = hooks.get("sync_room_upper_layer_callable", Callable())
	var g: float = 9.81
	var rho_ext: float = 1.2
	var t_ext_k: float = building.outside_temp_c + 273.15
	var use_canonical_pressure: bool = phase3_thermodynamic_pressure_enabled \
			and phase3_pressure_canonical_enabled

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var t_upper_k: float = room.temp_upper_c + 273.15

		# Presión de boyanza por gas caliente en la zona superior. La altura de
		# referencia para flujos viene del modelo canónico de interfaces, no de
		# una capa visible ni de una fórmula local del subsistema.
		var flow_interface_m: float = LayerInterfaceModel.get_flow_interface_height_m(
			room,
			null,
			building.outside_temp_c
		)
		var h_smoke_m: float = maxf(0.0, room.height_m - flow_interface_m)
		var dp_buoyancy: float = rho_ext * g * h_smoke_m * maxf(0.0, 1.0 - t_ext_k / t_upper_k)
		var dp_stack: float = 0.0
		if stack_effect_enabled and room.floor_level_z_m > 0.01:
			dp_stack = rho_ext * g * room.floor_level_z_m * maxf(0.0, 1.0 - t_ext_k / t_upper_k)
		if use_canonical_pressure:
			room.overpressure_pa = maxf(0.0, room.pressure_pa_therm)
		else:
			var tau_s: float = 5.0
			room.overpressure_pa += (dp_buoyancy + dp_stack - room.overpressure_pa) * minf(1.0, dt / tau_s)
			room.overpressure_pa = maxf(0.0, room.overpressure_pa)

		if room.overpressure_pa < pressure_vent_threshold_pa:
			continue

		var rho_hot: float = rho_ext * t_ext_k / t_upper_k
		var flow_path_factor: float = _compute_flow_path_direct_exterior_vent_fraction(building, room)
		if flow_path_factor <= 0.0:
			continue

		# Iteración por apertura: cada una puede tener un ΔP_viento diferente
		# según la orientación de su cara (wall_side) y la dirección del viento.
		var total_q_out_m3s: float = 0.0
		for op in building.get_openings():
			var connects_outside: bool = (
				(op.a == room.id and op.b == BuildingModel.OUTSIDE_ID) or
				(op.b == room.id and op.a == BuildingModel.OUTSIDE_ID)
			)
			if not connects_outside:
				continue
			# Presión de viento en esta apertura (barlovento > 0, sotavento < 0).
			# eff_press = presión neta que impulsa el flujo de salida.
			var dp_wind: float = _compute_wind_dp_pa(op, building)
			var eff_press: float = maxf(0.0, room.overpressure_pa - dp_wind)
			if eff_press < pressure_vent_threshold_pa:
				continue
			# Si la abertura está abierta, usa el área efectiva real en lugar
			# del área de infiltración. Un ventana/puerta abierta alivia
			# la presión mucho más rápido que las fugas de marco.
			var area_m2: float
			if op.open_fraction_smooth > 0.001:
				area_m2 = op.width_m * op.height_m * op.open_fraction_smooth
			else:
				if use_canonical_pressure:
					continue
				area_m2 = window_leakage_area_m2
			area_m2 *= flow_path_factor
			var v_op: float = sqrt(2.0 * eff_press / maxf(0.05, rho_hot))
			total_q_out_m3s += 0.61 * area_m2 * v_op

		if total_q_out_m3s <= 0.0:
			continue
		var q_out_m3s: float = total_q_out_m3s
		var smoke_out_kg: float = q_out_m3s * rho_hot * dt
		# 1.5A: acumular flujo másico de salida por venteo de presión [kg/s]
		room.mdot_vent_kg_s += q_out_m3s * rho_hot

		smoke_out_kg = minf(smoke_out_kg, room.smoke_kg * 0.15)
		if smoke_out_kg <= 0.0:
			continue

		var frac_out: float = smoke_out_kg / maxf(0.001, room.smoke_kg)
		# CO/CO2 son gases disueltos en el aire: la fracción que sale es proporcional
		# al volumen de aire purgado, no a la fracción de partículas de humo.
		# Usar frac_out (basado en humo) sobreestima masivamente la purga gaseosa
		# cuando la sala tiene poco humo relativo a CO2 generado.
		var room_vol_m3: float = maxf(1.0, room.volume_m3())
		var air_frac_out: float = clampf(q_out_m3s * dt / room_vol_m3, 0.0, 0.10)

		room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_out_kg)
		_record_smoke_vented(room, smoke_out_kg)
		result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + smoke_out_kg

		_call_room_fraction(remove_upper_layer_fraction_callable, room, frac_out)
		if two_zone_opening_flow_enabled:
			_purge_upper_species_to_exterior_direct(room, air_frac_out, smoke_out_kg)
		else:
			# SF-CBAL: registrar carbono que sale por venteo de presión ANTES de restar.
			room.c_exited_kg += room.co_kg * air_frac_out * (12.0 / 28.0) \
					+ room.co2_kg * air_frac_out * (12.0 / 44.0) \
					+ room.hcn_kg * air_frac_out * (12.0 / 27.0) \
					+ smoke_out_kg * 0.87
			room.co_exterior_removed_kg_total += room.co_kg * air_frac_out
			room.co_kg = maxf(0.0, room.co_kg * (1.0 - air_frac_out))
			room.co_upper_kg = maxf(0.0, room.co_upper_kg * (1.0 - air_frac_out))
			room.co2_kg = maxf(0.0, room.co2_kg * (1.0 - air_frac_out))
			room.co2_upper_kg = maxf(0.0, room.co2_upper_kg * (1.0 - air_frac_out))
			room.hcn_kg = maxf(0.0, room.hcn_kg * (1.0 - air_frac_out))
			room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg * (1.0 - air_frac_out))
			room.hcl_kg = maxf(0.0, room.hcl_kg * (1.0 - air_frac_out))
			room.acrolein_kg = maxf(0.0, room.acrolein_kg * (1.0 - air_frac_out))
			room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg * (1.0 - air_frac_out))
		_call_room_dt(sync_room_upper_layer_callable, room, dt)

		room.overpressure_pa = maxf(0.0, room.overpressure_pa * (1.0 - frac_out * 0.9))
		if use_canonical_pressure:
			room.pressure_pa_therm = room.overpressure_pa

		var air_in_kg: float = smoke_out_kg * 0.40
		var room_mass_kg: float = maxf(1.0, room.volume_m3()) * rho_ext
		var _pv_o2_before: float = room.o2
		room.o2 = clampf(
			(room.o2 * room_mass_kg + building.outside_o2 * air_in_kg) / (room_mass_kg + air_in_kg),
			0.0,
			o2_nominal
		)
		# SF-O1A: exterior neto por pressure_venting (dilución con aire exterior).
		var _pv_o2_delta: float = (room.o2 - _pv_o2_before) * room_mass_kg
		room.o2_exterior_net_kg_step += _pv_o2_delta
		room.o2_exterior_net_kg_total += _pv_o2_delta

	if use_canonical_pressure and phase3_pressure_component_equalization_enabled:
		_equalize_thermodynamic_pressure_components(building)
	return result


func step_smoke(building: BuildingModel, smoke_model: SmokeModel, dt: float, hooks: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"smoke_generated_kg": 0.0,
		"smoke_vented_kg": 0.0,
		"smoke_deposited_kg": 0.0
	}
	if building == null or smoke_model == null:
		return result

	var remove_upper_layer_fraction_callable: Callable = hooks.get("remove_upper_layer_fraction_callable", Callable())
	var sync_room_upper_layer_callable: Callable = hooks.get("sync_room_upper_layer_callable", Callable())
	var compute_interroom_transfer_temp_callable: Callable = hooks.get("compute_interroom_transfer_temp_callable", Callable())
	var outside_open_path_factor_callable: Callable = hooks.get("outside_open_path_factor_callable", Callable())
	var opening_flow_cache: Dictionary = hooks.get("opening_flow_cache", {})
	var air_density_kg_m3_s: float = 1.2
	var incident_active: bool = _has_any_active_fire(building)
	var ambient_c: float = building.outside_temp_c

	_release_pending_interior_deliveries(building, dt, sync_room_upper_layer_callable)

	var smoke_delta_kg: Dictionary = {}
	var co_delta_kg: Dictionary = {}
	var co_upper_delta_kg: Dictionary = {}
	var co2_delta_kg: Dictionary = {}
	var co2_upper_delta_kg: Dictionary = {}
	var hcn_delta_kg: Dictionary = {}
	var hcn_upper_delta_kg: Dictionary = {}
	var hcl_delta_kg: Dictionary = {}
	var acrolein_delta_kg: Dictionary = {}
	var formaldehyde_delta_kg: Dictionary = {}
	var o2_delta_kg: Dictionary = {}

	for room_id in building.get_rooms().keys():
		smoke_delta_kg[int(room_id)] = 0.0
		co_delta_kg[int(room_id)] = 0.0
		co_upper_delta_kg[int(room_id)] = 0.0
		co2_delta_kg[int(room_id)] = 0.0
		co2_upper_delta_kg[int(room_id)] = 0.0
		hcn_delta_kg[int(room_id)] = 0.0
		hcn_upper_delta_kg[int(room_id)] = 0.0
		hcl_delta_kg[int(room_id)] = 0.0
		acrolein_delta_kg[int(room_id)] = 0.0
		formaldehyde_delta_kg[int(room_id)] = 0.0
		o2_delta_kg[int(room_id)] = 0.0

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var generated_kg: float = smoke_model.add_generated_smoke(room, dt)
		result["smoke_generated_kg"] = float(result.get("smoke_generated_kg", 0.0)) + generated_kg
		_record_smoke_generated(room, generated_kg)
		smoke_delta_kg[int(room_id)] += generated_kg

	# Actualiza thermal_gap_fraction en puertas interiores calientes.
	_step_door_deform(building)

	var room_transfers: Array[Dictionary] = []
	for op in building.get_openings():
		if op.effective_open_fraction() <= 0.0:
			continue

		var room_out: RoomModel = null
		if op.a != BuildingModel.OUTSIDE_ID and op.b == BuildingModel.OUTSIDE_ID:
			room_out = building.get_room(op.a)
		elif op.b != BuildingModel.OUTSIDE_ID and op.a == BuildingModel.OUTSIDE_ID:
			room_out = building.get_room(op.b)

		if room_out != null:
			var vented_kg: float = smoke_model.compute_outside_vented_kg(room_out, op, dt)
			vented_kg *= _compute_flow_path_direct_exterior_vent_fraction(building, room_out)
			if vented_kg > 0.0:
				smoke_delta_kg[room_out.id] -= vented_kg
				result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + vented_kg
				_record_smoke_vented(room_out, vented_kg)
				# El hollín sale aunque la masa restante sea demasiado baja para arrastrar especies.
				room_out.c_exited_kg += vented_kg * 0.87

				if room_out.smoke_kg > 0.001:
					var vent_frac: float = minf(1.0, vented_kg / room_out.smoke_kg)
					if two_zone_opening_flow_enabled:
						_queue_upper_species_to_exterior(
							room_out,
							vent_frac,
							0.0,
							smoke_delta_kg,
							co_delta_kg,
							co_upper_delta_kg,
							co2_delta_kg,
							co2_upper_delta_kg,
							hcn_delta_kg,
							hcn_upper_delta_kg,
							hcl_delta_kg,
							acrolein_delta_kg,
							formaldehyde_delta_kg
						)
					else:
						co_delta_kg[room_out.id] -= vent_frac * room_out.co_kg
						co_upper_delta_kg[room_out.id] -= vent_frac * room_out.co_upper_kg
						co2_delta_kg[room_out.id] -= vent_frac * room_out.co2_kg
						co2_upper_delta_kg[room_out.id] -= vent_frac * room_out.co2_upper_kg
						hcn_delta_kg[room_out.id] -= vent_frac * room_out.hcn_kg
						hcn_upper_delta_kg[room_out.id] -= vent_frac * room_out.hcn_upper_kg
						hcl_delta_kg[room_out.id] -= vent_frac * room_out.hcl_kg
						acrolein_delta_kg[room_out.id] -= vent_frac * room_out.acrolein_kg
						formaldehyde_delta_kg[room_out.id] -= vent_frac * room_out.formaldehyde_kg
						# SF-CBAL: carbono que sale por venteo con flujo de humo.
						room_out.c_exited_kg += vent_frac * room_out.co_kg * (12.0 / 28.0) \
								+ vent_frac * room_out.co2_kg * (12.0 / 44.0) \
								+ vent_frac * room_out.hcn_kg * (12.0 / 27.0)
					# Gas térmico: usa fracción volumétrica real, no la fracción de humo.
					var rho_upper: float = maxf(0.05, air_density_kg_m3_s * 293.15 / maxf(50.0, room_out.temp_upper_c + 273.15))
					var vol_frac: float = clampf(vented_kg / (rho_upper * maxf(1.0, room_out.volume_m3())), 0.0, 0.15)
					_call_room_fraction(remove_upper_layer_fraction_callable, room_out, vol_frac)
					_call_room_dt(sync_room_upper_layer_callable, room_out, dt)

				# Inyección de O2: cuando el humo sale por la ventana, entra aire fresco.
				# Mismo mecanismo que el venteo por presión pero activado por flujo de humo.
				var air_in_kg: float = vented_kg * 0.40
				if air_in_kg > 0.0 and building.outside_o2 > 0.0:
					o2_delta_kg[room_out.id] += (building.outside_o2 - room_out.o2) * air_in_kg

			# Ventilación natural bidireccional por ventana exterior abierta.
			# El aire caliente sale por la mitad superior de la abertura (flotabilidad
			# térmica) y entra aire fresco por la mitad inferior. Este mecanismo opera
			# con independencia del flujo de humo y es el canal principal de reposición
			# de O2 y dilución de gases cuando hay una abertura exterior abierta.
			var nat_area_m2: float = op.width_m * op.height_m * op.open_fraction_smooth
			if nat_area_m2 > 0.0:
				var delta_t: float = maxf(0.0, room_out.temp_upper_c - building.outside_temp_c)
				var t_room_k: float = room_out.temp_upper_c + 273.15
				var t_amb_k: float = building.outside_temp_c + 273.15
				var fresh_air_kg: float
				if vent_bernoulli_enabled:
					# SF-AUD-010: la franja exterior superior usa h_flow_interface_m
					# canónica. Evita que la ventilación natural invente su propio
					# plano neutro aislado de la capa térmica/flujo del resto del motor.
					var _h_upper_e: float = LayerInterfaceModel.get_exterior_opening_hot_outflow_height_m(
						room_out,
						op,
						smoke_model,
						building.outside_temp_c
					)
					var _dT_e: float = maxf(0.0, t_room_k - t_amb_k)
					var _q_upper_e: float = 0.0
					if _h_upper_e > 0.001 and _dT_e > 0.5:
						var _T_ref_e: float = (t_room_k + t_amb_k) * 0.5
						_q_upper_e = 0.61 * op.width_m * op.open_fraction_smooth \
								* (2.0 / 3.0) * pow(_h_upper_e, 1.5) \
								* sqrt(2.0 * 9.81 * _dT_e / _T_ref_e)
					# Masa entrante: conservación ḟ_in = ḟ_out (ρ_hot × Q_out = ρ_cold × Q_in)
					var _rho_hot_e: float = 353.0 / maxf(50.0, t_room_k)
					var _rho_amb_e: float = 353.0 / maxf(50.0, t_amb_k)
					var _q_lower_e: float = _q_upper_e * _rho_hot_e / maxf(0.001, _rho_amb_e)
					fresh_air_kg = _q_lower_e * _rho_amb_e * dt
				else:
					# Comportamiento heredado: velocidad de flotabilidad + viento mínimo
					var h_eff_m: float = op.height_m * 0.5
					var v_buoy_m_s: float = 0.0
					if delta_t > 0.5:
						v_buoy_m_s = sqrt(2.0 * 9.81 * h_eff_m * delta_t / t_room_k)
					var v_nat_m_s: float = maxf(0.30, v_buoy_m_s)
					# La fracción inferior de la abertura es la entrada de aire fresco (Cd≈0.61).
					# natural_vent_inlet_fraction=0.5 asume plano neutro a mid-height.
					fresh_air_kg = 0.61 * (nat_area_m2 * natural_vent_inlet_fraction) * v_nat_m_s * air_density_kg_m3_s * dt
				var room_mass_kg: float = maxf(1.0, room_out.volume_m3()) * air_density_kg_m3_s
				fresh_air_kg *= vent_bernoulli_flow_multiplier
				fresh_air_kg = minf(fresh_air_kg, room_mass_kg * 0.30)
				if fresh_air_kg > 0.0:
					# 1.5A: acumular flujo másico de ventilación natural [kg/s]
					room_out.mdot_vent_kg_s += fresh_air_kg / maxf(0.001, dt)
					# O2: el aire fresco eleva el O2 de la sala hacia el nivel exterior
					o2_delta_kg[room_out.id] += (building.outside_o2 - room_out.o2) * fresh_air_kg
					# Purga de especies: el aire caliente sale por la mitad superior,
					# diluyendo humo/CO/CO2 en proporción al caudal de intercambio
					var purge_frac: float = clampf(fresh_air_kg / room_mass_kg, 0.0, 0.30)
					purge_frac *= _compute_flow_path_direct_exterior_vent_fraction(building, room_out)
					var smoke_purge_kg: float = room_out.smoke_kg * purge_frac
					# SF-S0: contabilizar humo purgado por ventilación natural en acumulador global.
					result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + smoke_purge_kg
					_record_smoke_vented(room_out, smoke_purge_kg)
					if two_zone_opening_flow_enabled:
						_queue_upper_species_to_exterior(
							room_out,
							purge_frac,
							smoke_purge_kg,
							smoke_delta_kg,
							co_delta_kg,
							co_upper_delta_kg,
							co2_delta_kg,
							co2_upper_delta_kg,
							hcn_delta_kg,
							hcn_upper_delta_kg,
							hcl_delta_kg,
							acrolein_delta_kg,
							formaldehyde_delta_kg
						)
					else:
						smoke_delta_kg[room_out.id] -= smoke_purge_kg
						co_delta_kg[room_out.id] -= room_out.co_kg * purge_frac
						co_upper_delta_kg[room_out.id] -= room_out.co_upper_kg * purge_frac
						co2_delta_kg[room_out.id] -= room_out.co2_kg * purge_frac
						co2_upper_delta_kg[room_out.id] -= room_out.co2_upper_kg * purge_frac
						hcn_delta_kg[room_out.id] -= room_out.hcn_kg * purge_frac
						hcn_upper_delta_kg[room_out.id] -= room_out.hcn_upper_kg * purge_frac
						# SF-CBAL: carbono que sale por purga de ventilación natural.
						room_out.c_exited_kg += room_out.co_kg * purge_frac * (12.0 / 28.0) \
								+ room_out.co2_kg * purge_frac * (12.0 / 44.0) \
								+ room_out.hcn_kg * purge_frac * (12.0 / 27.0) \
								+ smoke_purge_kg * 0.87

			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		_apply_background_species_exchange(
			building,
			room_a,
			room_b,
			op,
			dt,
			smoke_delta_kg,
			co_delta_kg,
			co_upper_delta_kg,
			co2_delta_kg,
			co2_upper_delta_kg,
			hcn_delta_kg,
			hcn_upper_delta_kg,
			hcl_delta_kg,
			acrolein_delta_kg,
			formaldehyde_delta_kg,
			o2_delta_kg,
			outside_open_path_factor_callable,
			opening_flow_cache
		)

		var transfers: Array[Dictionary] = smoke_model.compute_room_transfers(room_a, room_b, op, dt)
		for transfer in transfers:
			var from_id: int = int(transfer.get("from", -1))
			var to_id: int = int(transfer.get("to", -1))
			var kg: float = float(transfer.get("kg", 0.0))
			if from_id == -1 or to_id == -1 or kg <= 0.0:
				continue

			var source_room: RoomModel = building.get_room(from_id)
			var target_room: RoomModel = building.get_room(to_id)
			kg *= _compute_flow_path_interior_pull_multiplier(building, source_room, target_room)

			room_transfers.append({
				"from": from_id,
				"to": to_id,
				"kg": kg
			})

	var outgoing: Dictionary = {}
	for transfer in room_transfers:
		var from_id: int = int(transfer["from"])
		if not outgoing.has(from_id):
			outgoing[from_id] = []
		outgoing[from_id].append(transfer)

	for from_id in outgoing.keys():
		var room: RoomModel = building.get_room(int(from_id))
		if room == null:
			continue

		var total_requested: float = 0.0
		for transfer in outgoing[from_id]:
			total_requested += float(transfer["kg"])

		var max_allowed: float = room.smoke_kg * 0.60
		if total_requested > max_allowed and total_requested > 0.0:
			var scale: float = max_allowed / total_requested
			for transfer in outgoing[from_id]:
				transfer["kg"] = float(transfer["kg"]) * scale

	for transfer in room_transfers:
		var from_id: int = int(transfer["from"])
		var to_id: int = int(transfer["to"])
		var kg: float = float(transfer["kg"])
		if kg <= 0.0:
			continue

		var source: RoomModel = building.get_room(from_id)
		var target: RoomModel = building.get_room(to_id)
		if source == null or target == null:
			continue

		smoke_delta_kg[from_id] -= kg
		_record_smoke_net_transport(source, null, kg)

		var flow_ratio: float = kg / (target.smoke_kg + kg + 0.1)
		var travel_delay_s: float = _estimate_interior_transport_delay_s(building, from_id, to_id)
		var use_transport_delay: bool = interior_transport_enabled and travel_delay_s > 0.000001
		var delayed_upper_carry_fraction: float = 0.85
		var moved_upper_gas_kg: float = 0.0
		var moved_upper_energy_kj: float = 0.0
		if source.smoke_kg > 0.001 and source.upper_gas_kg > 0.001:
			var transfer_frac: float = minf(1.0, kg / source.smoke_kg)
			moved_upper_gas_kg = minf(
				source.upper_gas_kg * transfer_frac * 1.50,
				maxf(0.03, source.upper_gas_kg * 0.24)
			)
			var transferred_temp_c: float = _call_transfer_temp(
				compute_interroom_transfer_temp_callable,
				source,
				target,
				transfer_frac,
				ambient_c
			)
			moved_upper_energy_kj = moved_upper_gas_kg * maxf(0.0, transferred_temp_c - ambient_c)
			moved_upper_energy_kj = minf(moved_upper_energy_kj, source.upper_energy_kj)
			if use_transport_delay:
				moved_upper_gas_kg *= delayed_upper_carry_fraction
				moved_upper_energy_kj *= delayed_upper_carry_fraction

			# Conservación de masa: no transferir más gas del que realmente tiene la fuente.
			# moved_upper_gas_kg puede superar source.upper_gas_kg cuando éste es pequeño
			# (< ~0.02 kg) debido al multiplicador ×1.50 y al piso maxf(0.03, ...).
			# Sin este cap, source se recorta a 0 pero target recibe el valor completo.
			moved_upper_gas_kg = minf(moved_upper_gas_kg, source.upper_gas_kg)
			moved_upper_energy_kj = minf(moved_upper_energy_kj, source.upper_energy_kj)

			source.upper_gas_kg -= moved_upper_gas_kg
			source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - moved_upper_energy_kj)
			if phase3_zone_diagnostics_enabled:
				source.phase3_diag_zone_parcel_upper_out_kg_total += moved_upper_gas_kg

		var co_moved_kg: float = 0.0
		var co2_moved_kg: float = 0.0
		var co2_upper_moved_kg: float = 0.0
		var hcn_moved_kg: float = 0.0
		var hcn_upper_moved_kg: float = 0.0
		var hcl_moved_kg: float = 0.0
		var acrolein_moved_kg: float = 0.0
		var formaldehyde_moved_kg: float = 0.0
		if source.smoke_kg > 0.001:
			# Masas de aire fuente/destino compartidas por todos los limitadores de
			# concentración (1.2 kg/m³, consistente con compute_*_ppm). CO₂ reutiliza
			# estos valores con nombres propios para no modificar ese bloque (F0).
			var spec_src_air_kg: float = maxf(0.1, source.volume_m3()) * air_density_kg_m3_s
			var spec_tgt_air_kg: float = maxf(0.1, target.volume_m3()) * air_density_kg_m3_s
			# G1: masa ya en vuelo hacia este destino, para no sobre-otorgar headroom.
			var _ifl_to: Dictionary = _inflight_species_kg.get(to_id, {}) as Dictionary
			co_moved_kg = minf(
				minf(kg / source.smoke_kg, 1.0) * source.co_upper_kg,
				source.co_kg
			)
			# Specie pumping fix: limitar CO al headroom de concentración fuente→receptor.
			# El parcel lleva co_kg == co_upper_kg, así que capar co_moved_kg capa ambos.
			co_moved_kg = minf(co_moved_kg, maxf(
				0.0,
				source.co_kg / spec_src_air_kg * spec_tgt_air_kg
					- maxf(0.0, target.co_kg + float(co_delta_kg[to_id])
						+ float(_ifl_to.get("co", 0.0)))
			))
			co_delta_kg[from_id] -= co_moved_kg
			co2_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.co2_kg
			# F0 Plan B: cota de equilibrio por concentración. El proxy de fracción de
			# humo satura a 1.0 cuando source.smoke_kg es pequeño y exporta casi todo
			# el stock de CO2 cada tick, acumulando >100% vol en salas hub (PHY-P1).
			# El receptor no puede quedar por encima de la concentración de la fuente
			# por este movimiento. Masas de aire a densidad ambiente (1.2 kg/m³),
			# consistente con compute_co2_ppm.
			var co2_src_air_kg: float = maxf(0.1, source.volume_m3()) * air_density_kg_m3_s
			var co2_tgt_air_kg: float = maxf(0.1, target.volume_m3()) * air_density_kg_m3_s
			var co2_tgt_stock_kg: float = maxf(0.0, target.co2_kg + float(co2_delta_kg[to_id])
				+ float(_ifl_to.get("co2", 0.0)))
			var co2_headroom_kg: float = maxf(
				0.0,
				source.co2_kg / co2_src_air_kg * co2_tgt_air_kg - co2_tgt_stock_kg
			)
			var co2_cut_ratio: float = 1.0
			if co2_moved_kg > co2_headroom_kg and co2_moved_kg > 0.000001:
				co2_cut_ratio = co2_headroom_kg / co2_moved_kg
				co2_moved_kg = co2_headroom_kg
			co2_delta_kg[from_id] -= co2_moved_kg
			co2_upper_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.co2_upper_kg * co2_cut_ratio
			co2_upper_delta_kg[from_id] -= co2_upper_moved_kg
			hcn_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcn_kg
			# Specie pumping fix: limitar HCN al headroom; cut_ratio para upper proporcional.
			var hcn_cut_ratio: float = 1.0
			var hcn_headroom_kg: float = maxf(
				0.0,
				source.hcn_kg / spec_src_air_kg * spec_tgt_air_kg
					- maxf(0.0, target.hcn_kg + float(hcn_delta_kg[to_id])
						+ float(_ifl_to.get("hcn", 0.0)))
			)
			if hcn_moved_kg > hcn_headroom_kg and hcn_moved_kg > 0.000001:
				hcn_cut_ratio = hcn_headroom_kg / hcn_moved_kg
				hcn_moved_kg = hcn_headroom_kg
			hcn_delta_kg[from_id] -= hcn_moved_kg
			hcn_upper_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcn_upper_kg * hcn_cut_ratio
			hcn_upper_delta_kg[from_id] -= hcn_upper_moved_kg
			hcl_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcl_kg
			# Specie pumping fix: limitar HCl al headroom (bulk-only, sin upper).
			hcl_moved_kg = minf(hcl_moved_kg, maxf(
				0.0,
				source.hcl_kg / spec_src_air_kg * spec_tgt_air_kg
					- maxf(0.0, target.hcl_kg + float(hcl_delta_kg[to_id])
						+ float(_ifl_to.get("hcl", 0.0)))
			))
			hcl_delta_kg[from_id] -= hcl_moved_kg
			acrolein_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.acrolein_kg
			acrolein_moved_kg = minf(acrolein_moved_kg, maxf(
				0.0,
				source.acrolein_kg / spec_src_air_kg * spec_tgt_air_kg
					- maxf(0.0, target.acrolein_kg + float(acrolein_delta_kg[to_id])
						+ float(_ifl_to.get("acrolein", 0.0)))
			))
			acrolein_delta_kg[from_id] -= acrolein_moved_kg
			formaldehyde_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.formaldehyde_kg
			formaldehyde_moved_kg = minf(formaldehyde_moved_kg, maxf(
				0.0,
				source.formaldehyde_kg / spec_src_air_kg * spec_tgt_air_kg
					- maxf(0.0, target.formaldehyde_kg + float(formaldehyde_delta_kg[to_id])
						+ float(_ifl_to.get("formaldehyde", 0.0)))
			))
			formaldehyde_delta_kg[from_id] -= formaldehyde_moved_kg

		# O2 carry bidireccional con el parcel de gas caliente.
		# Usa transfer_frac × upper_gas_kg sin floor: transporte proporcional real.
		# Net = (source.o2 - target.o2) × gas_parcel × coeff.
		# Con coeff=0.0 (default) no hay carry y los baselines no cambian.
		var o2_carry_kg: float = 0.0
		if o2_smoke_carry_coeff > 0.0 and source.upper_gas_kg > 0.001 and source.smoke_kg > 0.001:
			var frac_moved: float = minf(1.0, kg / source.smoke_kg)
			var gas_parcel_kg: float = source.upper_gas_kg * frac_moved
			var o2_net: float = (source.o2 - target.o2) * gas_parcel_kg * o2_smoke_carry_coeff
			o2_carry_kg = clampf(
				o2_net,
				-target.o2 * gas_parcel_kg * o2_smoke_carry_coeff,
				source.o2 * gas_parcel_kg * o2_smoke_carry_coeff
			)
			o2_delta_kg[from_id] -= o2_carry_kg

		if use_transport_delay:
			_pending_interior_deliveries.append({
				"from": from_id,
				"target": to_id,
				"delay_s": travel_delay_s,
				"smoke_kg": kg,
				"co_kg": co_moved_kg,
				"co_upper_kg": co_moved_kg,
				"co2_kg": co2_moved_kg,
				"co2_upper_kg": co2_upper_moved_kg,
				"hcn_kg": hcn_moved_kg,
				"hcn_upper_kg": hcn_upper_moved_kg,
				"hcl_kg": hcl_moved_kg,
				"acrolein_kg": acrolein_moved_kg,
				"formaldehyde_kg": formaldehyde_moved_kg,
				"upper_gas_kg": moved_upper_gas_kg,
				"upper_energy_kj": moved_upper_energy_kj,
				"o2_kg": o2_carry_kg
			})
			# G1: registrar masa en vuelo hacia este destino.
			if not _inflight_species_kg.has(to_id):
				_inflight_species_kg[to_id] = {}
			var _ifl_new: Dictionary = _inflight_species_kg[to_id]
			_ifl_new["co2"] = float(_ifl_new.get("co2", 0.0)) + co2_moved_kg
			_ifl_new["co2_upper"] = float(_ifl_new.get("co2_upper", 0.0)) + co2_upper_moved_kg
			_ifl_new["co"] = float(_ifl_new.get("co", 0.0)) + co_moved_kg
			_ifl_new["hcn"] = float(_ifl_new.get("hcn", 0.0)) + hcn_moved_kg
			_ifl_new["hcn_upper"] = float(_ifl_new.get("hcn_upper", 0.0)) + hcn_upper_moved_kg
			_ifl_new["hcl"] = float(_ifl_new.get("hcl", 0.0)) + hcl_moved_kg
			_ifl_new["acrolein"] = float(_ifl_new.get("acrolein", 0.0)) + acrolein_moved_kg
			_ifl_new["formaldehyde"] = float(_ifl_new.get("formaldehyde", 0.0)) + formaldehyde_moved_kg
		else:
			smoke_delta_kg[to_id] += kg
			_record_smoke_net_transport(null, target, kg)
			co_delta_kg[to_id] += co_moved_kg
			co_upper_delta_kg[to_id] += co_moved_kg
			co2_delta_kg[to_id] += co2_moved_kg
			co2_upper_delta_kg[to_id] += co2_upper_moved_kg
			hcn_delta_kg[to_id] += hcn_moved_kg
			hcn_upper_delta_kg[to_id] += hcn_upper_moved_kg
			target.upper_gas_kg += moved_upper_gas_kg
			target.upper_energy_kj += moved_upper_energy_kj
			o2_delta_kg[to_id] += o2_carry_kg

			# O2 counterflow: cuando el humo pasa de sala A a B sin delay,
			# la corriente de retorno transporta O2 bidireccional en el dintel.
			# (Con delay activo, OxygenExchangeSystem maneja el intercambio de O2.)
			var o2_mix_factor: float = doorway_o2_counterflow_coeff * flow_ratio
			if o2_mix_factor > 0.0:
				var source_air_mass_kg: float = maxf(0.1, source.volume_m3()) * air_density_kg_m3_s
				var target_air_mass_kg: float = maxf(0.1, target.volume_m3()) * air_density_kg_m3_s
				var exchange_air_mass_kg: float = minf(source_air_mass_kg, target_air_mass_kg) * clampf(o2_mix_factor, 0.0, 1.0)

				if exchange_air_mass_kg > 0.0:
					var source_o2_out_kg: float = source.o2 * exchange_air_mass_kg
					var target_o2_out_kg: float = target.o2 * exchange_air_mass_kg
					o2_delta_kg[from_id] += target_o2_out_kg - source_o2_out_kg
					o2_delta_kg[to_id] += source_o2_out_kg - target_o2_out_kg

					var source_co_total_kg: float = maxf(0.0, source.co_kg + float(co_delta_kg[from_id]))
					var target_co_total_kg: float = maxf(0.0, target.co_kg + float(co_delta_kg[to_id]))
					var source_co_out_kg: float = source_co_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_co_out_kg: float = target_co_total_kg / target_air_mass_kg * exchange_air_mass_kg
					co_delta_kg[from_id] += target_co_out_kg - source_co_out_kg
					co_delta_kg[to_id] += source_co_out_kg - target_co_out_kg

					var source_co_upper_total_kg: float = maxf(
						0.0,
						source.co_upper_kg + float(co_upper_delta_kg[from_id])
					)
					var target_co_upper_total_kg: float = maxf(
						0.0,
						target.co_upper_kg + float(co_upper_delta_kg[to_id])
					)
					var source_upper_share: float = 0.0
					if source_co_total_kg > 0.000001:
						source_upper_share = source_co_upper_total_kg / source_co_total_kg
					var target_upper_share: float = 0.0
					if target_co_total_kg > 0.000001:
						target_upper_share = target_co_upper_total_kg / target_co_total_kg
					var source_co_upper_out_kg: float = source_co_out_kg * clampf(source_upper_share, 0.0, 1.0)
					var target_co_upper_out_kg: float = target_co_out_kg * clampf(target_upper_share, 0.0, 1.0)
					co_upper_delta_kg[from_id] += target_co_upper_out_kg - source_co_upper_out_kg
					co_upper_delta_kg[to_id] += source_co_upper_out_kg - target_co_upper_out_kg

					var source_co2_total_kg: float = maxf(0.0, source.co2_kg + float(co2_delta_kg[from_id]))
					var target_co2_total_kg: float = maxf(0.0, target.co2_kg + float(co2_delta_kg[to_id]))
					var source_co2_out_kg: float = source_co2_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_co2_out_kg: float = target_co2_total_kg / target_air_mass_kg * exchange_air_mass_kg
					co2_delta_kg[from_id] += target_co2_out_kg - source_co2_out_kg
					co2_delta_kg[to_id] += source_co2_out_kg - target_co2_out_kg

					var source_co2_upper_total_kg: float = maxf(0.0, source.co2_upper_kg + float(co2_upper_delta_kg[from_id]))
					var target_co2_upper_total_kg: float = maxf(0.0, target.co2_upper_kg + float(co2_upper_delta_kg[to_id]))
					var source_co2_upper_share: float = 0.0
					if source_co2_total_kg > 0.000001:
						source_co2_upper_share = source_co2_upper_total_kg / source_co2_total_kg
					var target_co2_upper_share: float = 0.0
					if target_co2_total_kg > 0.000001:
						target_co2_upper_share = target_co2_upper_total_kg / target_co2_total_kg
					var source_co2_upper_out_kg: float = source_co2_out_kg * clampf(source_co2_upper_share, 0.0, 1.0)
					var target_co2_upper_out_kg: float = target_co2_out_kg * clampf(target_co2_upper_share, 0.0, 1.0)
					co2_upper_delta_kg[from_id] += target_co2_upper_out_kg - source_co2_upper_out_kg
					co2_upper_delta_kg[to_id] += source_co2_upper_out_kg - target_co2_upper_out_kg

					var source_hcn_total_kg: float = maxf(0.0, source.hcn_kg + float(hcn_delta_kg[from_id]))
					var target_hcn_total_kg: float = maxf(0.0, target.hcn_kg + float(hcn_delta_kg[to_id]))
					var source_hcn_out_kg: float = source_hcn_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_hcn_out_kg: float = target_hcn_total_kg / target_air_mass_kg * exchange_air_mass_kg
					hcn_delta_kg[from_id] += target_hcn_out_kg - source_hcn_out_kg
					hcn_delta_kg[to_id] += source_hcn_out_kg - target_hcn_out_kg

					var source_hcn_upper_total_kg: float = maxf(0.0, source.hcn_upper_kg + float(hcn_upper_delta_kg[from_id]))
					var target_hcn_upper_total_kg: float = maxf(0.0, target.hcn_upper_kg + float(hcn_upper_delta_kg[to_id]))
					var source_hcn_upper_share: float = 0.0
					if source_hcn_total_kg > 0.000001:
						source_hcn_upper_share = source_hcn_upper_total_kg / source_hcn_total_kg
					var target_hcn_upper_share: float = 0.0
					if target_hcn_total_kg > 0.000001:
						target_hcn_upper_share = target_hcn_upper_total_kg / target_hcn_total_kg
					var source_hcn_upper_out_kg: float = source_hcn_out_kg * clampf(source_hcn_upper_share, 0.0, 1.0)
					var target_hcn_upper_out_kg: float = target_hcn_out_kg * clampf(target_hcn_upper_share, 0.0, 1.0)
					hcn_upper_delta_kg[from_id] += target_hcn_upper_out_kg - source_hcn_upper_out_kg
					hcn_upper_delta_kg[to_id] += source_hcn_upper_out_kg - target_hcn_upper_out_kg

					var source_hcl_total_kg: float = maxf(0.0, source.hcl_kg + float(hcl_delta_kg[from_id]))
					var target_hcl_total_kg: float = maxf(0.0, target.hcl_kg + float(hcl_delta_kg[to_id]))
					var source_hcl_out_kg: float = source_hcl_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_hcl_out_kg: float = target_hcl_total_kg / target_air_mass_kg * exchange_air_mass_kg
					hcl_delta_kg[from_id] += target_hcl_out_kg - source_hcl_out_kg
					hcl_delta_kg[to_id] += source_hcl_out_kg - target_hcl_out_kg

					var source_acrolein_total_kg: float = maxf(0.0, source.acrolein_kg + float(acrolein_delta_kg[from_id]))
					var target_acrolein_total_kg: float = maxf(0.0, target.acrolein_kg + float(acrolein_delta_kg[to_id]))
					var source_acrolein_out_kg: float = source_acrolein_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_acrolein_out_kg: float = target_acrolein_total_kg / target_air_mass_kg * exchange_air_mass_kg
					acrolein_delta_kg[from_id] += target_acrolein_out_kg - source_acrolein_out_kg
					acrolein_delta_kg[to_id] += source_acrolein_out_kg - target_acrolein_out_kg

					var source_formaldehyde_total_kg: float = maxf(0.0, source.formaldehyde_kg + float(formaldehyde_delta_kg[from_id]))
					var target_formaldehyde_total_kg: float = maxf(0.0, target.formaldehyde_kg + float(formaldehyde_delta_kg[to_id]))
					var source_formaldehyde_out_kg: float = source_formaldehyde_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_formaldehyde_out_kg: float = target_formaldehyde_total_kg / target_air_mass_kg * exchange_air_mass_kg
					formaldehyde_delta_kg[from_id] += target_formaldehyde_out_kg - source_formaldehyde_out_kg
					formaldehyde_delta_kg[to_id] += source_formaldehyde_out_kg - target_formaldehyde_out_kg

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var room_volume_m3_s: float = maxf(0.1, room.volume_m3())
		var room_air_mass_kg: float = room_volume_m3_s * air_density_kg_m3_s
		var _ges_o2_delta: float = float(o2_delta_kg[int(room_id)])
		var room_o2_mass_kg: float = room.o2 * room_air_mass_kg + _ges_o2_delta
		room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)
		# SF-O1A: transporte inter-sala por background + two-zone species exchange (GasExchangeSystem).
		room.o2_net_transport_kg_step += _ges_o2_delta
		room.o2_net_transport_kg_total += _ges_o2_delta

		room.smoke_kg = maxf(0.0, room.smoke_kg + float(smoke_delta_kg[int(room_id)]))
		room.co_net_transport_kg_step = float(co_delta_kg[int(room_id)])
		var _co_pre_transport: float = room.co_kg
		room.co_kg = maxf(0.0, room.co_kg + float(co_delta_kg[int(room_id)]))
		# Acumular el delta REAL (post-clamp) para que D1 no falle cuando la ventilación
		# intenta extraer más CO del disponible (maxf clamp en co_delta_kg).
		room.co_net_transport_kg_total += room.co_kg - _co_pre_transport
		room.co_upper_kg = maxf(0.0, room.co_upper_kg + float(co_upper_delta_kg[int(room_id)]))
		room.co2_kg = maxf(0.0, room.co2_kg + float(co2_delta_kg[int(room_id)]))
		room.co2_upper_kg = maxf(0.0, room.co2_upper_kg + float(co2_upper_delta_kg[int(room_id)]))
		room.hcn_kg = maxf(0.0, room.hcn_kg + float(hcn_delta_kg[int(room_id)]))
		room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg + float(hcn_upper_delta_kg[int(room_id)]))
		room.hcl_kg = maxf(0.0, room.hcl_kg + float(hcl_delta_kg[int(room_id)]))
		room.acrolein_kg = maxf(0.0, room.acrolein_kg + float(acrolein_delta_kg[int(room_id)]))
		room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg + float(formaldehyde_delta_kg[int(room_id)]))

		var ach_rate: float = ach_infiltration / 3600.0
		var co_removed: float = minf(room.co_kg, room.co_kg * ach_rate * dt)
		var co_remove_fraction: float = 0.0
		if room.co_kg > 0.000001:
			co_remove_fraction = co_removed / room.co_kg
		room.co_exterior_removed_kg_total += co_removed
		room.co_kg = maxf(0.0, room.co_kg - co_removed)
		room.co_upper_kg = maxf(0.0, room.co_upper_kg * (1.0 - clampf(co_remove_fraction, 0.0, 1.0)))
		var co2_removed: float = minf(room.co2_kg, room.co2_kg * ach_rate * dt)
		var co2_remove_fraction: float = 0.0
		if room.co2_kg > 0.000001:
			co2_remove_fraction = co2_removed / room.co2_kg
		room.co2_kg = maxf(0.0, room.co2_kg - co2_removed)
		room.co2_upper_kg = maxf(0.0, room.co2_upper_kg * (1.0 - clampf(co2_remove_fraction, 0.0, 1.0)))
		var hcn_removed: float = minf(room.hcn_kg, room.hcn_kg * ach_rate * dt)
		var hcn_remove_fraction: float = 0.0
		if room.hcn_kg > 0.000001:
			hcn_remove_fraction = hcn_removed / room.hcn_kg
		room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_removed)
		room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg * (1.0 - clampf(hcn_remove_fraction, 0.0, 1.0)))
		var hcl_removed: float = room.hcl_kg * ach_rate * dt
		room.hcl_kg = maxf(0.0, room.hcl_kg - hcl_removed)
		var acrolein_removed: float = room.acrolein_kg * ach_rate * dt
		room.acrolein_kg = maxf(0.0, room.acrolein_kg - acrolein_removed)
		var formaldehyde_removed: float = room.formaldehyde_kg * ach_rate * dt
		room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg - formaldehyde_removed)
		# NOTA: la recuperación de O2 por ACH la gestiona OxygenExchangeSystem.step().
		# No se duplica aquí para evitar doble aplicación por step.

		var smoke_concentration: float = room.smoke_kg / (room_volume_m3_s * air_density_kg_m3_s)
		var smoke_ach_efficiency: float = 1.0
		if not incident_active:
			# El ACH representa bien el barrido de especies gaseosas, pero el humo
			# post-incendio queda menos perfectamente mezclado y se purga algo mas
			# despacio que CO/CO2 por simple infiltracion.
			smoke_ach_efficiency = 0.70
		var smoke_removed: float = minf(room.smoke_kg, room_volume_m3_s \
				* air_density_kg_m3_s \
				* smoke_concentration \
				* ach_rate \
				* dt \
				* smoke_ach_efficiency)
		room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_removed)
		_record_smoke_vented(room, smoke_removed)
		# SF-S0: contabilizar extracción ACH en el acumulador de ventilación global.
		result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + smoke_removed
		# SF-CBAL: la infiltración ACH sustituye aire interior por aire exterior.
		room.c_exited_kg += co_removed * (12.0 / 28.0) \
				+ co2_removed * (12.0 / 44.0) \
				+ hcn_removed * (12.0 / 27.0) \
				+ smoke_removed * 0.87

		var open_species_purge_fraction: float = _compute_outside_species_purge_fraction(building, room, dt)
		if open_species_purge_fraction > 0.0:
			var upper_bias: float = clampf(outside_open_species_upper_bias, 0.0, 1.0)
			var co_upper_kg: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
			var co_lower_kg: float = maxf(0.0, room.co_kg - co_upper_kg)
			var co_upper_removed_kg: float = co_upper_kg * open_species_purge_fraction
			var co_lower_removed_kg: float = co_lower_kg * open_species_purge_fraction * (1.0 - upper_bias) * 0.55
			room.co_upper_kg = maxf(0.0, co_upper_kg - co_upper_removed_kg)
			room.co_exterior_removed_kg_total += co_upper_removed_kg + co_lower_removed_kg
			room.co_kg = maxf(0.0, room.co_kg - co_upper_removed_kg - co_lower_removed_kg)

			var co2_removed_kg: float = room.co2_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.co2_kg = maxf(0.0, room.co2_kg - co2_removed_kg)
			room.co2_upper_kg = maxf(0.0, room.co2_upper_kg - room.co2_upper_kg \
					* open_species_purge_fraction * lerpf(0.40, 0.75, upper_bias))
			var hcn_removed_kg: float = room.hcn_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_removed_kg)
			room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg - room.hcn_upper_kg \
					* open_species_purge_fraction * lerpf(0.40, 0.75, upper_bias))
			var hcl_removed_kg: float = room.hcl_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.hcl_kg = maxf(0.0, room.hcl_kg - hcl_removed_kg)
			var acrolein_removed_kg: float = room.acrolein_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.acrolein_kg = maxf(0.0, room.acrolein_kg - acrolein_removed_kg)
			var formaldehyde_removed_kg: float = room.formaldehyde_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg - formaldehyde_removed_kg)
			# SF-CBAL: carbono que sale por purga exterior de especies (outside_open_species_purge).
			room.c_exited_kg += (co_upper_removed_kg + co_lower_removed_kg) * (12.0 / 28.0) \
					+ co2_removed_kg * (12.0 / 44.0) \
					+ hcn_removed_kg * (12.0 / 27.0)

		var cleanup_factor: float = _compute_postfire_cleanup_factor(room)
		if cleanup_factor > 0.0:
			# Durante un incendio activo las salas secundarias (sin fuego) NO
			# deben sedimentar al ritmo post-incendio completo: el humo sigue
			# caliente y en suspensión. Solo se aplica la tasa base.
			# El bonus de limpieza post-incendio solo aplica cuando ya no hay
			# ningún foco activo en el edificio.
			var smoke_settling_rate: float = smoke_settling_base_per_s
			if not incident_active:
				smoke_settling_rate += smoke_settling_bonus_per_s * cleanup_factor
			var deposited_smoke_kg: float = minf(room.smoke_kg, room.smoke_kg * smoke_settling_rate * dt)
			room.smoke_kg = maxf(0.0, room.smoke_kg - deposited_smoke_kg)
			_record_smoke_deposited(room, deposited_smoke_kg)
			result["smoke_deposited_kg"] = float(result.get("smoke_deposited_kg", 0.0)) + deposited_smoke_kg
			# SF-CBAL: hollín depositado en paredes (carbono que sale de la fase gaseosa).
			room.c_deposited_kg += deposited_smoke_kg * 0.87

			# Igual para CO/CO2: purga post-incendio solo cuando el fuego está extinto.
			var co_purge_rate: float = 0.0
			if not incident_active:
				co_purge_rate = co_postfire_purge_base_per_s + co_postfire_purge_bonus_per_s * cleanup_factor
			var purged_co_kg: float = minf(room.co_kg, room.co_kg * co_purge_rate * dt)
			var purge_co_fraction: float = 0.0
			if room.co_kg > 0.000001:
				purge_co_fraction = purged_co_kg / room.co_kg
			room.co_exterior_removed_kg_total += purged_co_kg
			room.co_kg = maxf(0.0, room.co_kg - purged_co_kg)
			room.co_upper_kg = maxf(0.0, room.co_upper_kg * (1.0 - clampf(purge_co_fraction, 0.0, 1.0)))

			var purged_co2_kg: float = minf(room.co2_kg, room.co2_kg * co_purge_rate * dt)
			room.co2_kg = maxf(0.0, room.co2_kg - purged_co2_kg)
			room.co2_upper_kg = maxf(0.0, room.co2_upper_kg * (1.0 - clampf(purge_co_fraction, 0.0, 1.0)))
			var purged_hcn_kg: float = minf(room.hcn_kg, room.hcn_kg * co_purge_rate * dt)
			room.hcn_kg = maxf(0.0, room.hcn_kg - purged_hcn_kg)
			room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg * (1.0 - clampf(purge_co_fraction, 0.0, 1.0)))
			# SF-CBAL: carbono que sale por purga post-incendio (CO/CO₂/HCN → exterior).
			if co_purge_rate > 0.0:
				room.c_exited_kg += purged_co_kg * (12.0 / 28.0) \
						+ purged_co2_kg * (12.0 / 44.0) \
						+ purged_hcn_kg * (12.0 / 27.0)
			var purged_hcl_kg: float = minf(room.hcl_kg, room.hcl_kg * co_purge_rate * dt)
			room.hcl_kg = maxf(0.0, room.hcl_kg - purged_hcl_kg)
			var purged_acrolein_kg: float = minf(room.acrolein_kg, room.acrolein_kg * co_purge_rate * dt)
			room.acrolein_kg = maxf(0.0, room.acrolein_kg - purged_acrolein_kg)
			var purged_formaldehyde_kg: float = minf(room.formaldehyde_kg, room.formaldehyde_kg * co_purge_rate * dt)
			room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg - purged_formaldehyde_kg)

		room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)
		room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
		room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		_call_room_dt(sync_room_upper_layer_callable, room, dt)

	return result


func _compute_postfire_cleanup_factor(room: RoomModel) -> float:
	if room == null:
		return 0.0
	if room.fire != null or room.hrr_kw > 0.0:
		return 0.0
	if room.smoke_kg <= 0.000001 and room.co_kg <= 0.000001:
		return 0.0

	var temp_span_c: float = maxf(1.0, postfire_cleanup_hot_stop_c - postfire_cleanup_cool_full_c)
	var temp_factor: float = 1.0 - clampf(
		(room.temp_upper_c - postfire_cleanup_cool_full_c) / temp_span_c,
		0.0,
		1.0
	)

	var pressure_span_pa: float = maxf(0.01, postfire_cleanup_pressure_stop_pa - postfire_cleanup_pressure_full_pa)
	var pressure_factor: float = 1.0 - clampf(
		(room.overpressure_pa - postfire_cleanup_pressure_full_pa) / pressure_span_pa,
		0.0,
		1.0
	)

	return clampf(temp_factor * pressure_factor, 0.0, 1.0)


func _release_pending_interior_deliveries(
	building: BuildingModel,
	dt: float,
	sync_room_upper_layer_callable: Callable
) -> void:
	if building == null or _pending_interior_deliveries.is_empty():
		return

	var remaining: Array[Dictionary] = []
	var touched_rooms: Dictionary = {}

	for raw_entry in _pending_interior_deliveries:
		var entry: Dictionary = raw_entry
		entry["delay_s"] = maxf(0.0, float(entry.get("delay_s", 0.0)) - dt)
		if float(entry.get("delay_s", 0.0)) > 0.000001:
			remaining.append(entry)
			continue

		var target_id: int = int(entry.get("target", -1))
		# G1: parcel deja la cola — restar del ledger in-flight (entregado o descartado).
		if _inflight_species_kg.has(target_id):
			var _ifl: Dictionary = _inflight_species_kg[target_id]
			_ifl["co2"] = maxf(0.0, float(_ifl.get("co2", 0.0)) - float(entry.get("co2_kg", 0.0)))
			_ifl["co2_upper"] = maxf(0.0, float(_ifl.get("co2_upper", 0.0)) - float(entry.get("co2_upper_kg", 0.0)))
			_ifl["co"] = maxf(0.0, float(_ifl.get("co", 0.0)) - float(entry.get("co_kg", 0.0)))
			_ifl["hcn"] = maxf(0.0, float(_ifl.get("hcn", 0.0)) - float(entry.get("hcn_kg", 0.0)))
			_ifl["hcn_upper"] = maxf(0.0, float(_ifl.get("hcn_upper", 0.0)) - float(entry.get("hcn_upper_kg", 0.0)))
			_ifl["hcl"] = maxf(0.0, float(_ifl.get("hcl", 0.0)) - float(entry.get("hcl_kg", 0.0)))
			_ifl["acrolein"] = maxf(0.0, float(_ifl.get("acrolein", 0.0)) - float(entry.get("acrolein_kg", 0.0)))
			_ifl["formaldehyde"] = maxf(0.0, float(_ifl.get("formaldehyde", 0.0)) - float(entry.get("formaldehyde_kg", 0.0)))
		var target: RoomModel = building.get_room(target_id)
		if target == null:
			continue

		var delivered_smoke_kg: float = float(entry.get("smoke_kg", 0.0))
		target.smoke_kg = maxf(0.0, target.smoke_kg + delivered_smoke_kg)
		_record_smoke_net_transport(null, target, delivered_smoke_kg)
		# Specie pumping fix: cota de concentración para CO en la entrega diferida.
		# El headroom calculado al enviar no cuenta los parcels en vuelo; el receptor
		# puede haber superado ya la concentración de la fuente cuando llega el parcel.
		# El refund suma a co_net_transport_kg_total de la fuente para que D1 cierre.
		var co_parcel_kg: float = float(entry.get("co_kg", 0.0))
		var co_upper_parcel_kg: float = float(entry.get("co_upper_kg", 0.0))
		if co_parcel_kg > 0.0:
			var co_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
			if co_src_room != null:
				var co_tgt_air_kg: float = maxf(0.1, target.volume_m3()) * 1.2
				var co_src_air_kg: float = maxf(0.1, co_src_room.volume_m3()) * 1.2
				var co_headroom_kg: float = maxf(
					0.0,
					co_src_room.co_kg / co_src_air_kg * co_tgt_air_kg - target.co_kg
				)
				if co_parcel_kg > co_headroom_kg:
					var co_cut: float = co_headroom_kg / co_parcel_kg
					var co_refund_kg: float = co_parcel_kg - co_headroom_kg
					co_src_room.co_kg += co_refund_kg
					co_src_room.co_net_transport_kg_total += co_refund_kg
					co_src_room.co_upper_kg = minf(
						co_src_room.co_upper_kg + co_upper_parcel_kg * (1.0 - co_cut),
						co_src_room.co_kg
					)
					co_parcel_kg = co_headroom_kg
					co_upper_parcel_kg *= co_cut
		var _co_pre_delivery: float = target.co_kg
		target.co_kg = maxf(0.0, target.co_kg + co_parcel_kg)
		target.co_net_transport_kg_total += target.co_kg - _co_pre_delivery
		target.co_upper_kg = maxf(0.0, target.co_upper_kg + co_upper_parcel_kg)
		# F0 Plan B: cota de equilibrio también en la entrega diferida. El headroom
		# calculado al enviar no cuenta los parcels aún en vuelo, así que salas hub
		# con delays largos acumulan por encima de la concentración de la fuente.
		# El excedente se devuelve a la sala origen (conservación de masa).
		var co2_parcel_kg: float = float(entry.get("co2_kg", 0.0))
		var co2_upper_parcel_kg: float = float(entry.get("co2_upper_kg", 0.0))
		if co2_parcel_kg > 0.0:
			var co2_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
			if co2_src_room != null:
				var co2_tgt_air_kg: float = maxf(0.1, target.volume_m3()) * 1.2
				var co2_src_air_kg: float = maxf(0.1, co2_src_room.volume_m3()) * 1.2
				var co2_headroom_kg: float = maxf(
					0.0,
					co2_src_room.co2_kg / co2_src_air_kg * co2_tgt_air_kg - target.co2_kg
				)
				if co2_parcel_kg > co2_headroom_kg:
					var co2_cut: float = co2_headroom_kg / co2_parcel_kg
					var co2_refund_kg: float = co2_parcel_kg - co2_headroom_kg
					co2_src_room.co2_kg += co2_refund_kg
					co2_src_room.co2_upper_kg = minf(
						co2_src_room.co2_upper_kg + co2_upper_parcel_kg * (1.0 - co2_cut),
						co2_src_room.co2_kg
					)
					co2_parcel_kg = co2_headroom_kg
					co2_upper_parcel_kg *= co2_cut
		target.co2_kg = maxf(0.0, target.co2_kg + co2_parcel_kg)
		target.co2_upper_kg = maxf(0.0, target.co2_upper_kg + co2_upper_parcel_kg)
		# Specie pumping fix: HCN, HCl, acroleína y formaldehído — mismo patrón refund.
		var hcn_parcel_kg: float = float(entry.get("hcn_kg", 0.0))
		var hcn_upper_parcel_kg: float = float(entry.get("hcn_upper_kg", 0.0))
		if hcn_parcel_kg > 0.0:
			var hcn_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
			if hcn_src_room != null:
				var hcn_headroom_kg: float = maxf(
					0.0,
					hcn_src_room.hcn_kg / (maxf(0.1, hcn_src_room.volume_m3()) * 1.2)
						* (maxf(0.1, target.volume_m3()) * 1.2) - target.hcn_kg
				)
				if hcn_parcel_kg > hcn_headroom_kg:
					var hcn_cut: float = hcn_headroom_kg / hcn_parcel_kg
					hcn_src_room.hcn_kg += hcn_parcel_kg - hcn_headroom_kg
					hcn_src_room.hcn_upper_kg = minf(
						hcn_src_room.hcn_upper_kg + hcn_upper_parcel_kg * (1.0 - hcn_cut),
						hcn_src_room.hcn_kg
					)
					hcn_parcel_kg = hcn_headroom_kg
					hcn_upper_parcel_kg *= hcn_cut
		target.hcn_kg = maxf(0.0, target.hcn_kg + hcn_parcel_kg)
		target.hcn_upper_kg = maxf(0.0, target.hcn_upper_kg + hcn_upper_parcel_kg)
		var hcl_parcel_kg: float = float(entry.get("hcl_kg", 0.0))
		if hcl_parcel_kg > 0.0:
			var hcl_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
			if hcl_src_room != null:
				var hcl_headroom_kg: float = maxf(
					0.0,
					hcl_src_room.hcl_kg / (maxf(0.1, hcl_src_room.volume_m3()) * 1.2)
						* (maxf(0.1, target.volume_m3()) * 1.2) - target.hcl_kg
				)
				if hcl_parcel_kg > hcl_headroom_kg:
					hcl_src_room.hcl_kg += hcl_parcel_kg - hcl_headroom_kg
					hcl_parcel_kg = hcl_headroom_kg
		target.hcl_kg = maxf(0.0, target.hcl_kg + hcl_parcel_kg)
		var acrolein_parcel_kg: float = float(entry.get("acrolein_kg", 0.0))
		if acrolein_parcel_kg > 0.0:
			var acrolein_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
			if acrolein_src_room != null:
				var acrolein_headroom_kg: float = maxf(
					0.0,
					acrolein_src_room.acrolein_kg / (maxf(0.1, acrolein_src_room.volume_m3()) * 1.2)
						* (maxf(0.1, target.volume_m3()) * 1.2) - target.acrolein_kg
				)
				if acrolein_parcel_kg > acrolein_headroom_kg:
					acrolein_src_room.acrolein_kg += acrolein_parcel_kg - acrolein_headroom_kg
					acrolein_parcel_kg = acrolein_headroom_kg
		target.acrolein_kg = maxf(0.0, target.acrolein_kg + acrolein_parcel_kg)
		var formaldehyde_parcel_kg: float = float(entry.get("formaldehyde_kg", 0.0))
		if formaldehyde_parcel_kg > 0.0:
			var formaldehyde_src_room: RoomModel = building.get_room(int(entry.get("from", -1)))
			if formaldehyde_src_room != null:
				var formaldehyde_headroom_kg: float = maxf(
					0.0,
					formaldehyde_src_room.formaldehyde_kg / (maxf(0.1, formaldehyde_src_room.volume_m3()) * 1.2)
						* (maxf(0.1, target.volume_m3()) * 1.2) - target.formaldehyde_kg
				)
				if formaldehyde_parcel_kg > formaldehyde_headroom_kg:
					formaldehyde_src_room.formaldehyde_kg += formaldehyde_parcel_kg - formaldehyde_headroom_kg
					formaldehyde_parcel_kg = formaldehyde_headroom_kg
		target.formaldehyde_kg = maxf(0.0, target.formaldehyde_kg + formaldehyde_parcel_kg)
		target.upper_gas_kg = maxf(0.0, target.upper_gas_kg + float(entry.get("upper_gas_kg", 0.0)))
		target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + float(entry.get("upper_energy_kj", 0.0)))
		if phase3_zone_diagnostics_enabled:
			target.phase3_diag_zone_parcel_upper_in_kg_total += maxf(0.0, float(entry.get("upper_gas_kg", 0.0)))
		var o2_delivery_kg: float = float(entry.get("o2_kg", 0.0))
		if o2_delivery_kg != 0.0:
			var target_air_mass_kg: float = maxf(0.1, target.volume_m3()) * 1.2
			target.o2 = clampf(
				(target.o2 * target_air_mass_kg + o2_delivery_kg) / target_air_mass_kg,
				0.0,
				o2_nominal
			)
		target.co_upper_kg = clampf(target.co_upper_kg, 0.0, target.co_kg)
		target.co2_upper_kg = clampf(target.co2_upper_kg, 0.0, target.co2_kg)
		target.hcn_upper_kg = clampf(target.hcn_upper_kg, 0.0, target.hcn_kg)
		touched_rooms[target_id] = true

	_pending_interior_deliveries = remaining

	for room_id in touched_rooms.keys():
		var room: RoomModel = building.get_room(int(room_id))
		if room == null:
			continue
		_call_room_dt(sync_room_upper_layer_callable, room, dt)


func _estimate_interior_transport_delay_s(building: BuildingModel, from_id: int, to_id: int) -> float:
	if building == null or not interior_transport_enabled:
		return 0.0

	var distance_m: float = maxf(
		interior_transport_min_distance_m,
		building.estimate_room_connection_length_m(from_id, to_id)
	)
	return distance_m / maxf(0.05, interior_transport_speed_m_s)


func _apply_background_species_exchange(
	building: BuildingModel,
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	smoke_delta_kg: Dictionary,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	co2_upper_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary = {},
	hcn_upper_delta_kg: Dictionary = {},
	hcl_delta_kg: Dictionary = {},
	acrolein_delta_kg: Dictionary = {},
	formaldehyde_delta_kg: Dictionary = {},
	o2_delta_kg: Dictionary = {},
	outside_open_path_factor_callable: Callable = Callable(),
	opening_flow_cache: Dictionary = {}
) -> void:
	if building == null or room_a == null or room_b == null or op == null or dt <= 0.0:
		return

	var area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.effective_open_fraction())
	if area_eff_m2 <= 0.0:
		return

	if two_zone_opening_flow_enabled and _apply_two_zone_opening_species_exchange(
		room_a,
		room_b,
		op,
		dt,
		opening_flow_cache,
		smoke_delta_kg,
		co_delta_kg,
		co_upper_delta_kg,
		co2_delta_kg,
		co2_upper_delta_kg,
		hcn_delta_kg,
		hcn_upper_delta_kg,
		hcl_delta_kg,
		acrolein_delta_kg,
		formaldehyde_delta_kg,
		o2_delta_kg
	):
		return

	var air_density_kg_m3: float = 1.2

	# SF-R7: Para aperturas verticales (hueco de suelo/techo), el intercambio está
	# impulsado por flotabilidad (efecto chimenea), no por difusión de fondo.
	# Q = Cd · A · sqrt(2 · g · H_z · ΔT / T_cold)  [SFPE §3.2, chimney effect]
	if op.is_vertical:
		var _g_ve: float = 9.81
		var _cd_ve: float = 0.61
		# Determinar sala inferior (lower) y superior (upper)
		var _lower_r: RoomModel = room_a if room_a.floor_level_z_m <= room_b.floor_level_z_m else room_b
		var _upper_r: RoomModel = room_b if _lower_r == room_a else room_a
		var _H_z_ve: float = maxf(0.5, _upper_r.floor_level_z_m - _lower_r.floor_level_z_m)
		if _H_z_ve < 0.1:
			_H_z_ve = maxf(0.5, _lower_r.height_m)
		var _T_low_k: float = maxf(293.0, _lower_r.temp_upper_c + 273.15)
		var _T_high_k: float = maxf(293.0, _upper_r.temp_upper_c + 273.15)
		var _dT_ve: float = maxf(0.0, _T_low_k - _T_high_k)
		if _dT_ve < 1.0:
			# Temperaturas casi iguales: usar difusión mínima de fondo
			var _mass_ve: float = minf(
				maxf(0.1, _lower_r.volume_m3()),
				maxf(0.1, _upper_r.volume_m3())
			) * air_density_kg_m3 * 0.02 * dt
			_apply_species_net_exchange(room_a, room_b, _mass_ve,
				smoke_delta_kg, co_delta_kg, co_upper_delta_kg,
				co2_delta_kg, hcn_delta_kg, hcl_delta_kg,
				acrolein_delta_kg, formaldehyde_delta_kg, o2_delta_kg)
			return
		# Caudal volumétrico de gas caliente ascendente
		var _q_up_m3s: float = _cd_ve * area_eff_m2 * sqrt(2.0 * _g_ve * _H_z_ve * _dT_ve / _T_high_k)
		var _rho_low: float = 353.0 / maxf(50.0, _T_low_k)
		var _rho_high: float = 353.0 / maxf(50.0, _T_high_k)
		# Masa intercambiada: gas caliente sube (lower→upper), aire frío baja (upper→lower)
		# Neto: humo/gases calientes se transfieren de lower a upper
		var _mass_up_kg: float = minf(_q_up_m3s * _rho_low * dt, maxf(0.1, _lower_r.volume_m3()) * _rho_low * 0.30)
		var _mass_down_kg: float = minf(_q_up_m3s * _rho_high * dt, maxf(0.1, _upper_r.volume_m3()) * _rho_high * 0.30)
		# Intercambio neto de especies: lower→upper (humo, CO, CO2, etc.) y upper→lower (O2 fresco)
		var _mass_lower_ke: float = maxf(0.1, _lower_r.volume_m3()) * air_density_kg_m3
		var _mass_upper_ke: float = maxf(0.1, _upper_r.volume_m3()) * air_density_kg_m3
		# Transferencia ascendente (species from lower to upper)
		_apply_directed_species_exchange(_lower_r, _upper_r, _mass_up_kg, _mass_lower_ke,
			smoke_delta_kg, co_delta_kg, co_upper_delta_kg,
			co2_delta_kg, hcn_delta_kg, hcl_delta_kg,
			acrolein_delta_kg, formaldehyde_delta_kg, o2_delta_kg)
		# Transferencia descendente (fresh air from upper to lower — primarily O2)
		if _mass_down_kg > 0.0:
			var _o2_net: float = (_upper_r.o2 - _lower_r.o2) * _mass_down_kg / maxf(_mass_upper_ke, 0.001)
			if o2_delta_kg.has(int(_lower_r.id)):
				o2_delta_kg[int(_lower_r.id)] += _o2_net * _mass_down_kg
				o2_delta_kg[int(_upper_r.id)] -= _o2_net * _mass_down_kg
		return

	var mass_a_kg: float = maxf(0.1, room_a.volume_m3()) * air_density_kg_m3
	var mass_b_kg: float = maxf(0.1, room_b.volume_m3()) * air_density_kg_m3
	var outside_open_factor: float = maxf(
		_estimate_room_outside_open_factor(building, room_a),
		_estimate_room_outside_open_factor(building, room_b)
	)
	if outside_open_factor <= 0.0:
		# Comprueba la ruta indirecta al exterior (efecto chimenea a través de
		# puertas intermedias). El factor se atenúa para no duplicar el canal
		# directo, y es 0 si no existe ninguna ruta ventilada.
		var path_a: float = _call_room_id_float(outside_open_path_factor_callable, room_a.id, 0.0)
		var path_b: float = _call_room_id_float(outside_open_path_factor_callable, room_b.id, 0.0)
		outside_open_factor = maxf(path_a, path_b) * 0.25
		# Si no hay ruta al exterior, permitir difusión mínima entre salas interiores
		# conectadas (ej. CO, humo, CO2). Física real: incluso en edificio cerrado hay
		# mezcla turbulenta por gradientes de temperatura/presión a través de la puerta.
		# outside_open_factor queda en 0.0 → background_drive será 0.25 (mínimo), lo que
		# activa el intercambio a tasa reducida sin la atenuación extra del exterior.

	# Boost de difusión por presencia de humo: el humo acumulado genera gradientes
	# de presión/flotabilidad que incrementan el intercambio incluso sin apertura exterior.
	# Referencia: 50 g/m³ de humo (visible) ≈ señal significativa de presión diferencial.
	var smoke_conc_signal: float = maxf(
		room_a.smoke_kg / maxf(0.1, room_a.volume_m3()),
		room_b.smoke_kg / maxf(0.1, room_b.volume_m3())
	)
	var smoke_drive: float = clampf(smoke_conc_signal / 0.050, 0.0, 0.65)
	var background_drive: float = maxf(
		0.25,
		maxf(
			clampf(maxf(room_a.overpressure_pa, room_b.overpressure_pa) / 1.5, 0.0, 1.0),
			maxf(
				clampf(outside_open_factor * 0.85, 0.0, 1.0),
				smoke_drive
			)
		)
	)
	var exchange_air_kg: float = area_eff_m2 \
			* maxf(0.0, background_species_exchange_kg_s_m2) \
			* background_drive \
			* dt
	exchange_air_kg *= lerpf(
		1.0,
		maxf(1.0, background_species_path_multiplier_max),
		clampf(outside_open_factor, 0.0, 1.0)
	)
	var max_exchange_kg: float = minf(mass_a_kg, mass_b_kg) * lerpf(
		clampf(background_species_max_fraction_closed, 0.0, 0.50),
		clampf(background_species_max_fraction_open, 0.0, 0.50),
		clampf(outside_open_factor, 0.0, 1.0)
	)
	exchange_air_kg = minf(exchange_air_kg, max_exchange_kg)
	if exchange_air_kg <= 0.0:
		return

	var net_smoke_a_to_b: float = (
		room_a.smoke_kg / mass_a_kg - room_b.smoke_kg / mass_b_kg
	) * exchange_air_kg
	smoke_delta_kg[room_a.id] -= net_smoke_a_to_b
	smoke_delta_kg[room_b.id] += net_smoke_a_to_b
	if net_smoke_a_to_b >= 0.0:
		_record_smoke_net_transport(room_a, room_b, net_smoke_a_to_b)
	else:
		_record_smoke_net_transport(room_b, room_a, -net_smoke_a_to_b)

	var net_co_a_to_b: float = (
		room_a.co_kg / mass_a_kg - room_b.co_kg / mass_b_kg
	) * exchange_air_kg
	co_delta_kg[room_a.id] -= net_co_a_to_b
	co_delta_kg[room_b.id] += net_co_a_to_b

	var net_co_upper_a_to_b: float = 0.0
	if net_co_a_to_b > 0.0 and room_a.co_kg > 0.000001:
		net_co_upper_a_to_b = net_co_a_to_b * clampf(room_a.co_upper_kg / room_a.co_kg, 0.0, 1.0)
	elif net_co_a_to_b < 0.0 and room_b.co_kg > 0.000001:
		net_co_upper_a_to_b = net_co_a_to_b * clampf(room_b.co_upper_kg / room_b.co_kg, 0.0, 1.0)
	co_upper_delta_kg[room_a.id] -= net_co_upper_a_to_b
	co_upper_delta_kg[room_b.id] += net_co_upper_a_to_b

	var net_co2_a_to_b: float = (
		room_a.co2_kg / mass_a_kg - room_b.co2_kg / mass_b_kg
	) * exchange_air_kg
	co2_delta_kg[room_a.id] -= net_co2_a_to_b
	co2_delta_kg[room_b.id] += net_co2_a_to_b

	if not hcn_delta_kg.is_empty():
		var net_hcn_a_to_b: float = (
			room_a.hcn_kg / mass_a_kg - room_b.hcn_kg / mass_b_kg
		) * exchange_air_kg
		hcn_delta_kg[room_a.id] -= net_hcn_a_to_b
		hcn_delta_kg[room_b.id] += net_hcn_a_to_b

	if not hcl_delta_kg.is_empty():
		var net_hcl_a_to_b: float = (
			room_a.hcl_kg / mass_a_kg - room_b.hcl_kg / mass_b_kg
		) * exchange_air_kg
		hcl_delta_kg[room_a.id] -= net_hcl_a_to_b
		hcl_delta_kg[room_b.id] += net_hcl_a_to_b

	if not acrolein_delta_kg.is_empty():
		var net_acrolein_a_to_b: float = (
			room_a.acrolein_kg / mass_a_kg - room_b.acrolein_kg / mass_b_kg
		) * exchange_air_kg
		acrolein_delta_kg[room_a.id] -= net_acrolein_a_to_b
		acrolein_delta_kg[room_b.id] += net_acrolein_a_to_b

	if not formaldehyde_delta_kg.is_empty():
		var net_formaldehyde_a_to_b: float = (
			room_a.formaldehyde_kg / mass_a_kg - room_b.formaldehyde_kg / mass_b_kg
		) * exchange_air_kg
		formaldehyde_delta_kg[room_a.id] -= net_formaldehyde_a_to_b
		formaldehyde_delta_kg[room_b.id] += net_formaldehyde_a_to_b

	# O2: intercambio por gradiente de concentración entre salas conectadas.
	# El O2 fluye de la sala con más O2 hacia la sala con menos O2 (difusión).
	if not o2_delta_kg.is_empty():
		var net_o2_a_to_b: float = (room_a.o2 - room_b.o2) * exchange_air_kg * maxf(0.0, background_o2_exchange_multiplier)
		o2_delta_kg[room_a.id] -= net_o2_a_to_b
		o2_delta_kg[room_b.id] += net_o2_a_to_b

	# Acople entálpico: el intercambio de fondo también transporta energía térmica.
	# La energía fluye de la sala más caliente a la más fría, proporcional al
	# caudal de intercambio y al exceso de temperatura de la zona superior.
	# Esto evita el "humo frío": humo acumulado sin energía térmica asociada.
	var hot_room_bg: RoomModel = room_a if room_a.temp_upper_c >= room_b.temp_upper_c else room_b
	var cold_room_bg: RoomModel = room_b if room_a.temp_upper_c >= room_b.temp_upper_c else room_a
	var bg_delta_t: float = hot_room_bg.temp_upper_c - cold_room_bg.temp_upper_c
	if bg_delta_t > 1.0 and hot_room_bg.upper_gas_kg > 0.0001 and hot_room_bg.upper_energy_kj > 0.0001:
		var hot_mass: float = maxf(0.1, hot_room_bg.volume_m3()) * air_density_kg_m3
		var exchange_frac: float = minf(1.0, exchange_air_kg / hot_mass)
		var gas_moved_bg: float = hot_room_bg.upper_gas_kg * exchange_frac
		gas_moved_bg = minf(gas_moved_bg, hot_room_bg.upper_gas_kg * 0.15)
		var energy_moved_bg: float = gas_moved_bg * maxf(0.0, hot_room_bg.temp_upper_c - building.outside_temp_c)
		energy_moved_bg = minf(energy_moved_bg, hot_room_bg.upper_energy_kj * 0.15)
		if energy_moved_bg > 0.0:
			hot_room_bg.upper_gas_kg = maxf(0.0, hot_room_bg.upper_gas_kg - gas_moved_bg)
			hot_room_bg.upper_energy_kj = maxf(0.0, hot_room_bg.upper_energy_kj - energy_moved_bg)
			cold_room_bg.upper_gas_kg += gas_moved_bg
			cold_room_bg.upper_energy_kj += energy_moved_bg
			if phase3_zone_diagnostics_enabled:
				hot_room_bg.phase3_diag_zone_doorway_upper_out_kg_total += gas_moved_bg
				cold_room_bg.phase3_diag_zone_doorway_upper_in_kg_total += gas_moved_bg


func _apply_two_zone_opening_species_exchange(
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel,
	dt: float,
	opening_flow_cache: Dictionary,
	smoke_delta_kg: Dictionary,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	co2_upper_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary,
	hcn_upper_delta_kg: Dictionary,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary,
	o2_delta_kg: Dictionary
) -> bool:
	if room_a == null or room_b == null or op == null or dt <= 0.0:
		return false

	var flow_state: Dictionary = _get_cached_opening_flow_state(op, opening_flow_cache)
	if not bool(flow_state.get("active", false)):
		return false

	var hot_room: RoomModel = flow_state.get("hot_room", null)
	var cold_room: RoomModel = flow_state.get("cold_room", null)
	if hot_room == null or cold_room == null:
		return false

	var upper_mass_kg: float = _zone_air_mass_kg(hot_room, true)
	var lower_mass_kg: float = _zone_air_mass_kg(cold_room, false)
	var upper_exchange_kg: float = minf(
		maxf(0.0, float(flow_state.get("bernoulli_upper_kg_s", 0.0)) * dt),
		upper_mass_kg * 0.30
	)
	var lower_exchange_kg: float = minf(
		maxf(0.0, float(flow_state.get("bernoulli_lower_kg_s", 0.0)) * dt),
		lower_mass_kg * 0.30
	)
	if upper_exchange_kg <= 0.0 and lower_exchange_kg <= 0.0:
		return false

	if upper_exchange_kg > 0.0:
		var upper_route: Dictionary = _resolve_opening_segment_route(hot_room, cold_room, op, flow_state, true)
		var upper_source_is_upper: bool = bool(upper_route.get("from_upper", true))
		var upper_target_is_upper: bool = bool(upper_route.get("to_upper", true))
		var upper_fraction: float = clampf(
			upper_exchange_kg / maxf(0.001, _zone_air_mass_kg(hot_room, upper_source_is_upper)),
			0.0,
			0.30
		)
		if upper_source_is_upper:
			_move_upper_zone_species(
				hot_room,
				cold_room,
				upper_fraction,
				upper_exchange_kg,
				upper_target_is_upper,
				smoke_delta_kg,
				co_delta_kg,
				co_upper_delta_kg,
				co2_delta_kg,
				co2_upper_delta_kg,
				hcn_delta_kg,
				hcn_upper_delta_kg,
				hcl_delta_kg,
				acrolein_delta_kg,
				formaldehyde_delta_kg,
				o2_delta_kg
			)
		else:
			_move_lower_zone_species(
				hot_room,
				cold_room,
				upper_fraction,
				upper_exchange_kg,
				upper_target_is_upper,
				co_delta_kg,
				co_upper_delta_kg,
				co2_delta_kg,
				co2_upper_delta_kg,
				hcn_delta_kg,
				hcn_upper_delta_kg,
				hcl_delta_kg,
				acrolein_delta_kg,
				formaldehyde_delta_kg,
				o2_delta_kg
			)
		_record_two_zone_opening_flow(hot_room, cold_room, upper_source_is_upper, upper_target_is_upper, upper_exchange_kg)

	if lower_exchange_kg > 0.0:
		var lower_route: Dictionary = _resolve_opening_segment_route(cold_room, hot_room, op, flow_state, false)
		var lower_source_is_upper: bool = bool(lower_route.get("from_upper", false))
		var lower_target_is_upper: bool = bool(lower_route.get("to_upper", false))
		var lower_fraction: float = clampf(
			lower_exchange_kg / maxf(0.001, _zone_air_mass_kg(cold_room, lower_source_is_upper)),
			0.0,
			0.30
		)
		if lower_source_is_upper:
			_move_upper_zone_species(
				cold_room,
				hot_room,
				lower_fraction,
				lower_exchange_kg,
				lower_target_is_upper,
				smoke_delta_kg,
				co_delta_kg,
				co_upper_delta_kg,
				co2_delta_kg,
				co2_upper_delta_kg,
				hcn_delta_kg,
				hcn_upper_delta_kg,
				hcl_delta_kg,
				acrolein_delta_kg,
				formaldehyde_delta_kg,
				o2_delta_kg
			)
		else:
			_move_lower_zone_species(
				cold_room,
				hot_room,
				lower_fraction,
				lower_exchange_kg,
				lower_target_is_upper,
				co_delta_kg,
				co_upper_delta_kg,
				co2_delta_kg,
				co2_upper_delta_kg,
				hcn_delta_kg,
				hcn_upper_delta_kg,
				hcl_delta_kg,
				acrolein_delta_kg,
				formaldehyde_delta_kg,
				o2_delta_kg
			)
		_record_two_zone_opening_flow(cold_room, hot_room, lower_source_is_upper, lower_target_is_upper, lower_exchange_kg)

	return true


func _get_cached_opening_flow_state(op: OpeningModel, opening_flow_cache: Dictionary) -> Dictionary:
	if op != null and opening_flow_cache.has(op):
		return opening_flow_cache[op]
	return {}


func _zone_air_mass_kg(room: RoomModel, upper_zone: bool) -> float:
	if room == null:
		return 0.1
	if upper_zone:
		if room.upper_gas_kg > 0.001:
			return maxf(0.1, room.upper_gas_kg)
		return maxf(0.1, room.upper_volume_m3() * 1.2)
	if room.lower_gas_kg > 0.001:
		return maxf(0.1, room.lower_gas_kg)
	return maxf(0.1, room.lower_volume_m3() * 1.2)


func _resolve_opening_segment_route(
	from_r: RoomModel,
	to_r: RoomModel,
	op: OpeningModel,
	flow_state: Dictionary,
	upper_segment: bool
) -> Dictionary:
	var from_mid_m: float = _opening_segment_midpoint_m(from_r, to_r, op, flow_state, upper_segment)
	var to_mid_m: float = _opening_segment_midpoint_m(to_r, from_r, op, flow_state, upper_segment)
	return {
		"from_upper": _height_is_in_upper_zone(from_r, from_mid_m),
		"to_upper": _height_is_in_upper_zone(to_r, to_mid_m),
		"from_mid_m": from_mid_m,
		"to_mid_m": to_mid_m
	}


func _opening_segment_midpoint_m(
	room: RoomModel,
	other_room: RoomModel,
	op: OpeningModel,
	flow_state: Dictionary,
	upper_segment: bool
) -> float:
	if room == null or op == null:
		return 0.0
	if op.is_vertical:
		if other_room != null and room.floor_level_z_m > other_room.floor_level_z_m + 0.01:
			return 0.0
		return room.height_m

	var neutral_pf: float = clampf(float(flow_state.get("neutral_plane_f", 0.5)), 0.0, 1.0)
	var segment_h_m: float
	if upper_segment:
		segment_h_m = clampf(neutral_pf * op.height_m, 0.0, op.height_m)
		return clampf(op.sill_m + op.height_m - segment_h_m * 0.5, 0.0, room.height_m)
	segment_h_m = clampf((1.0 - neutral_pf) * op.height_m, 0.0, op.height_m)
	return clampf(op.sill_m + segment_h_m * 0.5, 0.0, room.height_m)


func _height_is_in_upper_zone(room: RoomModel, height_m: float) -> bool:
	if room == null:
		return false
	var interface_m: float = LayerInterfaceModel.get_flow_interface_height_m(room, null, 20.0)
	var upper_depth_m: float = maxf(0.0, room.height_m - interface_m)
	if upper_depth_m <= 0.02 and room.upper_gas_kg <= 0.001:
		return false
	return height_m >= interface_m


func _record_two_zone_opening_flow(
	from_r: RoomModel,
	to_r: RoomModel,
	from_upper: bool,
	to_upper: bool,
	mass_kg: float
) -> void:
	if from_r == null or to_r == null or mass_kg <= 0.0:
		return
	if from_upper:
		from_r.two_zone_opening_upper_out_kg += mass_kg
	else:
		from_r.two_zone_opening_lower_out_kg += mass_kg
	if to_upper:
		to_r.two_zone_opening_upper_in_kg += mass_kg
	else:
		to_r.two_zone_opening_lower_in_kg += mass_kg


func _purge_upper_species_to_exterior_direct(room: RoomModel, fraction: float, smoke_removed_kg: float) -> void:
	if room == null:
		return
	var frac: float = clampf(fraction, 0.0, 0.30)
	var co_removed_kg: float = minf(clampf(room.co_upper_kg, 0.0, room.co_kg), room.co_upper_kg * frac)
	room.co_upper_kg = maxf(0.0, room.co_upper_kg - co_removed_kg)
	room.co_exterior_removed_kg_total += co_removed_kg
	room.co_kg = maxf(0.0, room.co_kg - co_removed_kg)

	var co2_removed_kg: float = minf(clampf(room.co2_upper_kg, 0.0, room.co2_kg), room.co2_upper_kg * frac)
	room.co2_upper_kg = maxf(0.0, room.co2_upper_kg - co2_removed_kg)
	room.co2_kg = maxf(0.0, room.co2_kg - co2_removed_kg)

	var hcn_removed_kg: float = minf(clampf(room.hcn_upper_kg, 0.0, room.hcn_kg), room.hcn_upper_kg * frac)
	room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg - hcn_removed_kg)
	room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_removed_kg)

	room.hcl_kg = maxf(0.0, room.hcl_kg * (1.0 - frac))
	room.acrolein_kg = maxf(0.0, room.acrolein_kg * (1.0 - frac))
	room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg * (1.0 - frac))
	room.c_exited_kg += co_removed_kg * (12.0 / 28.0) \
			+ co2_removed_kg * (12.0 / 44.0) \
			+ hcn_removed_kg * (12.0 / 27.0) \
			+ maxf(0.0, smoke_removed_kg) * 0.87


func _queue_upper_species_to_exterior(
	room: RoomModel,
	fraction: float,
	smoke_removed_kg: float,
	smoke_delta_kg: Dictionary,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	co2_upper_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary,
	hcn_upper_delta_kg: Dictionary,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary
) -> void:
	if room == null:
		return
	var frac: float = clampf(fraction, 0.0, 0.30)
	var removed_smoke_kg: float = maxf(0.0, smoke_removed_kg)
	_add_delta(smoke_delta_kg, room.id, -removed_smoke_kg)

	var co_removed_kg: float = minf(clampf(room.co_upper_kg, 0.0, room.co_kg), room.co_upper_kg * frac)
	_add_delta(co_delta_kg, room.id, -co_removed_kg)
	_add_delta(co_upper_delta_kg, room.id, -co_removed_kg)

	var co2_removed_kg: float = minf(clampf(room.co2_upper_kg, 0.0, room.co2_kg), room.co2_upper_kg * frac)
	_add_delta(co2_delta_kg, room.id, -co2_removed_kg)
	_add_delta(co2_upper_delta_kg, room.id, -co2_removed_kg)

	var hcn_removed_kg: float = minf(clampf(room.hcn_upper_kg, 0.0, room.hcn_kg), room.hcn_upper_kg * frac)
	_add_delta(hcn_delta_kg, room.id, -hcn_removed_kg)
	_add_delta(hcn_upper_delta_kg, room.id, -hcn_removed_kg)

	_add_delta(hcl_delta_kg, room.id, -room.hcl_kg * frac)
	_add_delta(acrolein_delta_kg, room.id, -room.acrolein_kg * frac)
	_add_delta(formaldehyde_delta_kg, room.id, -room.formaldehyde_kg * frac)
	room.c_exited_kg += co_removed_kg * (12.0 / 28.0) \
			+ co2_removed_kg * (12.0 / 44.0) \
			+ hcn_removed_kg * (12.0 / 27.0) \
			+ removed_smoke_kg * 0.87


func _move_upper_zone_species(
	from_r: RoomModel,
	to_r: RoomModel,
	fraction: float,
	air_mass_kg: float,
	target_upper_zone: bool,
	smoke_delta_kg: Dictionary,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	co2_upper_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary,
	hcn_upper_delta_kg: Dictionary,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary,
	o2_delta_kg: Dictionary
) -> void:
	var frac: float = clampf(fraction, 0.0, 0.30)
	if from_r == null or to_r == null or frac <= 0.0:
		return

	var moved_smoke_kg: float = from_r.smoke_kg * frac
	_add_delta(smoke_delta_kg, from_r.id, -moved_smoke_kg)
	_add_delta(smoke_delta_kg, to_r.id, moved_smoke_kg)
	_record_smoke_net_transport(from_r, to_r, moved_smoke_kg)

	var moved_co_kg: float = minf(clampf(from_r.co_upper_kg, 0.0, from_r.co_kg) * frac, from_r.co_kg)
	_add_delta(co_delta_kg, from_r.id, -moved_co_kg)
	_add_delta(co_delta_kg, to_r.id, moved_co_kg)
	_add_delta(co_upper_delta_kg, from_r.id, -moved_co_kg)
	if target_upper_zone:
		_add_delta(co_upper_delta_kg, to_r.id, moved_co_kg)

	var moved_co2_kg: float = minf(clampf(from_r.co2_upper_kg, 0.0, from_r.co2_kg) * frac, from_r.co2_kg)
	_add_delta(co2_delta_kg, from_r.id, -moved_co2_kg)
	_add_delta(co2_delta_kg, to_r.id, moved_co2_kg)
	_add_delta(co2_upper_delta_kg, from_r.id, -moved_co2_kg)
	if target_upper_zone:
		_add_delta(co2_upper_delta_kg, to_r.id, moved_co2_kg)

	if not hcn_delta_kg.is_empty():
		var moved_hcn_kg: float = minf(clampf(from_r.hcn_upper_kg, 0.0, from_r.hcn_kg) * frac, from_r.hcn_kg)
		_add_delta(hcn_delta_kg, from_r.id, -moved_hcn_kg)
		_add_delta(hcn_delta_kg, to_r.id, moved_hcn_kg)
		_add_delta(hcn_upper_delta_kg, from_r.id, -moved_hcn_kg)
		if target_upper_zone:
			_add_delta(hcn_upper_delta_kg, to_r.id, moved_hcn_kg)

	_move_unlayered_species(
		from_r,
		to_r,
		frac,
		hcl_delta_kg,
		acrolein_delta_kg,
		formaldehyde_delta_kg
	)

	if not o2_delta_kg.is_empty() and background_o2_exchange_multiplier > 0.0:
		var moved_o2_kg: float = from_r.o2_upper * air_mass_kg * background_o2_exchange_multiplier
		_add_delta(o2_delta_kg, from_r.id, -moved_o2_kg)
		_add_delta(o2_delta_kg, to_r.id, moved_o2_kg)


func _move_lower_zone_species(
	from_r: RoomModel,
	to_r: RoomModel,
	fraction: float,
	air_mass_kg: float,
	target_upper_zone: bool,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	co2_upper_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary,
	hcn_upper_delta_kg: Dictionary,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary,
	o2_delta_kg: Dictionary
) -> void:
	var frac: float = clampf(fraction, 0.0, 0.30)
	if from_r == null or to_r == null or frac <= 0.0:
		return

	var moved_co_kg: float = maxf(0.0, from_r.co_kg - clampf(from_r.co_upper_kg, 0.0, from_r.co_kg)) * frac
	_add_delta(co_delta_kg, from_r.id, -moved_co_kg)
	_add_delta(co_delta_kg, to_r.id, moved_co_kg)
	if target_upper_zone:
		_add_delta(co_upper_delta_kg, to_r.id, moved_co_kg)

	var moved_co2_kg: float = maxf(0.0, from_r.co2_kg - clampf(from_r.co2_upper_kg, 0.0, from_r.co2_kg)) * frac
	_add_delta(co2_delta_kg, from_r.id, -moved_co2_kg)
	_add_delta(co2_delta_kg, to_r.id, moved_co2_kg)
	if target_upper_zone:
		_add_delta(co2_upper_delta_kg, to_r.id, moved_co2_kg)

	if not hcn_delta_kg.is_empty():
		var moved_hcn_kg: float = maxf(0.0, from_r.hcn_kg - clampf(from_r.hcn_upper_kg, 0.0, from_r.hcn_kg)) * frac
		_add_delta(hcn_delta_kg, from_r.id, -moved_hcn_kg)
		_add_delta(hcn_delta_kg, to_r.id, moved_hcn_kg)
		if target_upper_zone:
			_add_delta(hcn_upper_delta_kg, to_r.id, moved_hcn_kg)

	_move_unlayered_species(
		from_r,
		to_r,
		frac,
		hcl_delta_kg,
		acrolein_delta_kg,
		formaldehyde_delta_kg
	)

	if not o2_delta_kg.is_empty() and background_o2_exchange_multiplier > 0.0:
		var moved_o2_kg: float = from_r.o2_lower * air_mass_kg * background_o2_exchange_multiplier
		_add_delta(o2_delta_kg, from_r.id, -moved_o2_kg)
		_add_delta(o2_delta_kg, to_r.id, moved_o2_kg)


func _move_unlayered_species(
	from_r: RoomModel,
	to_r: RoomModel,
	fraction: float,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary
) -> void:
	if not hcl_delta_kg.is_empty():
		var moved_hcl_kg: float = from_r.hcl_kg * fraction
		_add_delta(hcl_delta_kg, from_r.id, -moved_hcl_kg)
		_add_delta(hcl_delta_kg, to_r.id, moved_hcl_kg)
	if not acrolein_delta_kg.is_empty():
		var moved_acrolein_kg: float = from_r.acrolein_kg * fraction
		_add_delta(acrolein_delta_kg, from_r.id, -moved_acrolein_kg)
		_add_delta(acrolein_delta_kg, to_r.id, moved_acrolein_kg)
	if not formaldehyde_delta_kg.is_empty():
		var moved_formaldehyde_kg: float = from_r.formaldehyde_kg * fraction
		_add_delta(formaldehyde_delta_kg, from_r.id, -moved_formaldehyde_kg)
		_add_delta(formaldehyde_delta_kg, to_r.id, moved_formaldehyde_kg)


func _add_delta(delta: Dictionary, room_id: int, amount_kg: float) -> void:
	if delta.is_empty() or amount_kg == 0.0:
		return
	delta[room_id] = float(delta.get(room_id, 0.0)) + amount_kg


func _record_smoke_generated(room: RoomModel, amount_kg: float) -> void:
	if room == null or amount_kg <= 0.0:
		return
	room.smoke_generated_kg_step += amount_kg
	room.smoke_generated_kg_total += amount_kg


func _record_smoke_vented(room: RoomModel, amount_kg: float) -> void:
	if room == null or amount_kg <= 0.0:
		return
	room.smoke_vented_kg_step += amount_kg
	room.smoke_vented_kg_total += amount_kg


func _record_smoke_deposited(room: RoomModel, amount_kg: float) -> void:
	if room == null or amount_kg <= 0.0:
		return
	room.smoke_deposited_kg_step += amount_kg
	room.smoke_deposited_kg_total += amount_kg


func _record_smoke_net_transport(from_room: RoomModel, to_room: RoomModel, amount_kg: float) -> void:
	if amount_kg <= 0.0:
		return
	if from_room != null:
		from_room.smoke_net_transport_kg_step -= amount_kg
		from_room.smoke_net_transport_kg_total -= amount_kg
	if to_room != null:
		to_room.smoke_net_transport_kg_step += amount_kg
		to_room.smoke_net_transport_kg_total += amount_kg


func _compute_outside_species_purge_fraction(building: BuildingModel, room: RoomModel, dt: float) -> float:
	if building == null or room == null or dt <= 0.0:
		return 0.0
	if outside_open_species_purge_base_per_s <= 0.0 and outside_open_species_purge_bonus_per_s <= 0.0:
		return 0.0

	var outside_open_factor: float = _estimate_room_outside_open_factor(building, room)
	outside_open_factor *= _compute_flow_path_direct_exterior_vent_fraction(building, room)
	if outside_open_factor <= 0.0:
		return 0.0

	var temp_factor: float = clampf(
		inverse_lerp(
			outside_open_species_temp_start_c,
			outside_open_species_temp_full_c,
			room.temp_upper_c
		),
		0.0,
		1.0
	)
	var pressure_factor: float = clampf(
		room.overpressure_pa / maxf(0.1, outside_open_species_pressure_ref_pa),
		0.0,
		1.0
	)
	var drive: float = maxf(temp_factor, pressure_factor * 0.75)
	var purge_rate_per_s: float = outside_open_species_purge_base_per_s \
			+ outside_open_species_purge_bonus_per_s * outside_open_factor * drive
	return clampf(1.0 - exp(-maxf(0.0, purge_rate_per_s) * dt), 0.0, 0.85)


func _estimate_room_outside_open_factor(building: BuildingModel, room: RoomModel) -> float:
	if building == null or room == null:
		return 0.0

	var total_open_area_m2: float = 0.0
	for op in building.get_openings():
		if op.open_fraction_smooth <= 0.0:
			continue

		var connects_outside: bool = (
			(op.a == room.id and op.b == BuildingModel.OUTSIDE_ID)
			or (op.b == room.id and op.a == BuildingModel.OUTSIDE_ID)
		)
		if not connects_outside:
			continue

		total_open_area_m2 += op.width_m * op.height_m * op.open_fraction_smooth

	if total_open_area_m2 <= 0.0:
		return 0.0

	var reference_area_m2: float = maxf(0.20, room.floor_area_m2() * 0.12)
	return clampf(total_open_area_m2 / reference_area_m2, 0.0, 1.0)


func _compute_flow_path_direct_exterior_vent_fraction(building: BuildingModel, room: RoomModel) -> float:
	if building == null or room == null:
		return 1.0
	if flow_path_direct_fire_vent_reduction <= 0.0:
		return 1.0
	if room.fire == null and room.hrr_kw <= 25.0:
		return 1.0

	var remote_path: float = _estimate_remote_exterior_path_factor(building, room.id, room.id)
	if remote_path <= 0.0:
		return 1.0

	var fire_strength: float = clampf(room.hrr_kw / 700.0, 0.0, 1.0)
	var reduction: float = clampf(flow_path_direct_fire_vent_reduction, 0.0, 0.95) \
			* remote_path \
			* fire_strength
	return clampf(
		1.0 - reduction,
		clampf(flow_path_direct_fire_min_vent_fraction, 0.05, 1.0),
		1.0
	)


func _compute_flow_path_interior_pull_multiplier(
	building: BuildingModel,
	source: RoomModel,
	target: RoomModel
) -> float:
	if building == null or source == null or target == null:
		return 1.0
	if flow_path_interior_pull_boost <= 0.0:
		return 1.0

	var remote_path: float = _estimate_remote_exterior_path_factor(building, target.id, source.id)
	if remote_path <= 0.0:
		return 1.0

	var pressure_drive: float = clampf(
		(source.overpressure_pa - target.overpressure_pa) / maxf(0.5, outside_open_species_pressure_ref_pa),
		0.0,
		1.0
	)
	var temp_drive: float = clampf((source.temp_upper_c - target.temp_upper_c) / 350.0, 0.0, 1.0)
	var hrr_drive: float = 0.0
	if source.fire != null or source.hrr_kw > 0.0:
		hrr_drive = clampf(source.hrr_kw / 1000.0, 0.0, 1.0)

	var drive: float = maxf(maxf(pressure_drive, temp_drive), hrr_drive * 0.75)
	if drive <= 0.0:
		return 1.0

	return clampf(
		1.0 + flow_path_interior_pull_boost * remote_path * drive,
		1.0,
		maxf(1.0, flow_path_interior_pull_max_multiplier)
	)


func _estimate_remote_exterior_path_factor(
	building: BuildingModel,
	start_room_id: int,
	excluded_room_id: int = -999999
) -> float:
	if building == null or building.get_room(start_room_id) == null:
		return 0.0

	var best_path_by_room: Dictionary = {}
	var depth_by_room: Dictionary = {}
	var queue: Array[int] = []
	best_path_by_room[start_room_id] = 1.0
	depth_by_room[start_room_id] = 0
	queue.append(start_room_id)

	var best_factor: float = 0.0
	while not queue.is_empty():
		var current_id: int = int(queue.pop_front())
		var current_room: RoomModel = building.get_room(current_id)
		if current_room == null:
			continue

		var current_path_factor: float = float(best_path_by_room.get(current_id, 0.0))
		var current_depth: int = int(depth_by_room.get(current_id, 0))
		if current_id != excluded_room_id:
			best_factor = maxf(
				best_factor,
				_estimate_room_outside_open_factor(building, current_room) * current_path_factor
			)

		if current_depth >= flow_path_remote_max_doors:
			continue

		for op in building.get_connected_openings(current_id):
			if op == null or op.open_fraction <= 0.0:
				continue
			if op.type != OpeningModel.Type.DOOR:
				continue
			if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
				continue

			var next_id: int = op.b if op.a == current_id else op.a
			if next_id == excluded_room_id:
				continue
			if building.get_room(next_id) == null:
				continue

			var area_factor: float = clampf(
				(op.width_m * op.height_m) / maxf(0.1, 0.8 * 2.0),
				0.35,
				1.25
			)
			var next_path_factor: float = current_path_factor \
					* clampf(op.open_fraction, 0.0, 1.0) \
					* clampf(flow_path_remote_decay_per_door, 0.0, 1.0) \
					* area_factor
			next_path_factor = clampf(next_path_factor, 0.0, 1.0)
			if next_path_factor <= float(best_path_by_room.get(next_id, -1.0)):
				continue

			best_path_by_room[next_id] = next_path_factor
			depth_by_room[next_id] = current_depth + 1
			queue.append(next_id)

	return clampf(best_factor, 0.0, 1.0)


# ============================================================
# DEFORMACIÓN DE PUERTA POR TEMPERATURA
# ============================================================
# Actualiza thermal_gap_fraction para cada puerta interior caliente.
# El gap crece linealmente desde 0% (en door_deform_temp_start_c)
# hasta door_deform_max_gap (en door_deform_temp_full_c).
# Solo aplica cuando la puerta está cerrada o casi cerrada (open_fraction < 0.5);
# puertas abiertas ya dejan pasar el flujo sin necesitar el gap térmico.
func _step_door_deform(building: BuildingModel) -> void:
	if not door_deform_enabled:
		# Limpia cualquier gap residual de pasos anteriores.
		for op in building.get_openings():
			op.thermal_gap_fraction = 0.0
		return

	var temp_range: float = maxf(1.0, door_deform_temp_full_c - door_deform_temp_start_c)

	for op in building.get_openings():
		# Solo puertas interiores cerradas/casi cerradas.
		if op.type != OpeningModel.Type.DOOR:
			op.thermal_gap_fraction = 0.0
			continue
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			op.thermal_gap_fraction = 0.0
			continue
		if op.open_fraction >= 0.5:
			# Puerta abierta: el gap térmico es irrelevante.
			op.thermal_gap_fraction = 0.0
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			op.thermal_gap_fraction = 0.0
			continue

		# La temperatura más alta de los dos lados define la deformación.
		var t_hot: float = maxf(room_a.temp_upper_c, room_b.temp_upper_c)
		var factor: float = clampf(
			(t_hot - door_deform_temp_start_c) / temp_range,
			0.0,
			1.0
		)
		# Las puertas casi cerradas deforman más que las que tienen algo de apertura.
		var closed_factor: float = clampf(1.0 - op.open_fraction * 2.0, 0.0, 1.0)
		op.thermal_gap_fraction = factor * door_deform_max_gap * closed_factor


# ============================================================
# VIENTO — PRESIÓN DE VIENTO EN APERTURAS EXTERIORES
# ============================================================
# Calcula el ΔP que el viento ejerce sobre una apertura exterior.
# Convención meteorológica: wind_direction_deg = ángulo desde donde VIENE
# el viento (0=N, 90=E, 180=S, 270=O).
# En coordenadas 2D del mapa (x derecha, y abajo, "top" = norte):
#   Cp > 0 → barlovento (viento empuja hacia dentro → dificulta venteo)
#   Cp < 0 → sotavento  (succión → facilita venteo)
# Referencia: EN 1991-1-4 §7.2 — coeficientes de presión de viento.
func _compute_wind_dp_pa(op: OpeningModel, building: BuildingModel) -> float:
	if not wind_effect_enabled:
		return 0.0
	var v: float = building.wind_speed_m_s
	if v <= 0.01:
		return 0.0

	# Vector unitario que apunta HACIA el origen del viento (de donde viene).
	# En mapa 2D (y-abajo): N=top→(0,-1), E=right→(+1,0), S=bottom→(0,+1), W=left→(-1,0).
	var dir_rad: float = deg_to_rad(building.wind_direction_deg)
	var wfx: float = sin(dir_rad)   # componente x del vector "from-wind"
	var wfy: float = -cos(dir_rad)  # componente y del vector "from-wind"

	# Normal exterior de la cara (hacia fuera del edificio) según wall_side.
	var nx: float
	var ny: float
	match op.wall_side:
		"top":    nx = 0.0;  ny = -1.0  # cara norte
		"bottom": nx = 0.0;  ny = 1.0   # cara sur
		"left":   nx = -1.0; ny = 0.0   # cara oeste
		"right":  nx = 1.0;  ny = 0.0   # cara este
		_:
			return 0.0  # sin wall_side conocido → sin efecto de viento

	# cos(incidencia) = proyección del viento de origen sobre la normal.
	# Positivo → barlovento; negativo → sotavento.
	var cos_inc: float = nx * wfx + ny * wfy

	# Coeficiente de presión simplificado (Eurocode EN 1991-1-4, valores ref.).
	var cp: float
	if cos_inc >= 0.0:
		cp = 0.6 * cos_inc   # barlovento
	else:
		cp = 0.4 * cos_inc   # sotavento (Cp negativo → succión)

	return 0.5 * 1.2 * v * v * cp


func _has_any_active_fire(building: BuildingModel) -> bool:
	if building == null:
		return false

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room != null and room.fire != null and room.hrr_kw > 0.0:
			return true

	return false


func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room))


func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room_id))


func _call_transfer_temp(
	callable: Callable,
	source: RoomModel,
	target: RoomModel,
	intensity: float,
	default_value: float
) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(source, target, intensity))


func _call_room_fraction(callable: Callable, room: RoomModel, fraction: float) -> void:
	if not callable.is_valid():
		return
	callable.call(room, fraction)


func _call_room_dt(callable: Callable, room: RoomModel, dt: float) -> void:
	if not callable.is_valid():
		return
	callable.call(room, dt)


# ============================================================
# SF-AUD-036: PPV — Positive Pressure Ventilation
# ------------------------------------------------------------
# Para cada apertura exterior con ppv_flow_m3_s > 0, el ventilador PPV
# fuerza un caudal Q_ppv (m³/s) hacia el interior de la sala (sala de entrada).
# Esto crea una sobrepresión que expulsa humo/gases por las demás aberturas
# (exhaustión natural). La sala opuesta a la entrada actúa como escape.
#
# Física simplificada (CFAST MVENT equivalente):
#   - La abertura PPV INTRODUCE aire exterior fresco a caudal Q_ppv.
#   - La sobrepresión resultante ΔP_ppv = ppv_delta_p_pa expulsa gases por
#     todas las demás aberturas exteriores de la sala según Q = Cd·A·√(2·ΔP/ρ).
#   - La purga de humo/especies sigue la proporción volumétrica exhaustida.
# ============================================================
func step_ppv(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"ppv_smoke_purged_kg": 0.0,
		"ppv_fresh_air_injected_kg": 0.0
	}
	if building == null:
		return result

	var remove_upper_layer_fraction_callable: Callable = hooks.get("remove_upper_layer_fraction_callable", Callable())
	var sync_room_upper_layer_callable: Callable = hooks.get("sync_room_upper_layer_callable", Callable())
	var rho_ext: float = 1.20
	var rho_ext_inv: float = 1.0 / rho_ext

	for op in building.get_openings():
		if float(op.ppv_flow_m3_s) <= 0.000001:
			continue
		if op.open_fraction < 0.01:
			continue

		# Determinar la sala de entrada (la sala que recibe el caudal PPV)
		var inlet_room_id: int = -1
		if op.a == BuildingModel.OUTSIDE_ID:
			inlet_room_id = op.b
		elif op.b == BuildingModel.OUTSIDE_ID:
			inlet_room_id = op.a
		else:
			# Apertura interior: PPV no aplica directamente
			continue

		var inlet_room: RoomModel = building.get_room(inlet_room_id)
		if inlet_room == null:
			continue

		var q_ppv_m3s: float = float(op.ppv_flow_m3_s)
		var dp_ppv_pa: float = maxf(0.0, float(op.ppv_delta_p_pa))

		# Paso 1: Inyectar aire fresco exterior en la sala de entrada
		var injected_vol_m3: float = q_ppv_m3s * dt
		var injected_kg: float = injected_vol_m3 * rho_ext
		var room_vol_m3: float = maxf(1.0, inlet_room.volume_m3())

		# Fracción de renovación de la sala (mezcla perfecta, cota de seguridad 0.25)
		var mix_frac: float = clampf(injected_vol_m3 / room_vol_m3, 0.0, 0.25)
		var room_air_mass_kg: float = room_vol_m3 * rho_ext

		# Diluir O2 hacia el nominal
		var _ppv_o2_before: float = inlet_room.o2
		inlet_room.o2 = clampf(
			lerpf(inlet_room.o2, building.outside_o2, mix_frac),
			0.0,
			o2_nominal
		)
		# SF-O1A: exterior neto por inyección PPV.
		var _ppv_o2_delta: float = (inlet_room.o2 - _ppv_o2_before) * room_air_mass_kg
		inlet_room.o2_exterior_net_kg_step += _ppv_o2_delta
		inlet_room.o2_exterior_net_kg_total += _ppv_o2_delta
		# Purgar humo y especies por dilución
		var smoke_purged_inlet: float = inlet_room.smoke_kg * mix_frac
		var co_purged_inlet: float = inlet_room.co_kg * mix_frac
		var co2_purged_inlet: float = inlet_room.co2_kg * mix_frac
		var hcn_purged_inlet: float = inlet_room.hcn_kg * mix_frac
		inlet_room.c_exited_kg += co_purged_inlet * (12.0 / 28.0) \
				+ co2_purged_inlet * (12.0 / 44.0) \
				+ hcn_purged_inlet * (12.0 / 27.0) \
				+ smoke_purged_inlet * 0.87
		inlet_room.smoke_kg = maxf(0.0, inlet_room.smoke_kg - smoke_purged_inlet)
		_record_smoke_vented(inlet_room, smoke_purged_inlet)
		inlet_room.co_kg = maxf(0.0, inlet_room.co_kg * (1.0 - mix_frac))
		inlet_room.co_upper_kg = maxf(0.0, inlet_room.co_upper_kg * (1.0 - mix_frac))
		inlet_room.co2_kg = maxf(0.0, inlet_room.co2_kg * (1.0 - mix_frac))
		inlet_room.hcn_kg = maxf(0.0, inlet_room.hcn_kg * (1.0 - mix_frac))
		inlet_room.hcl_kg = maxf(0.0, inlet_room.hcl_kg * (1.0 - mix_frac))
		inlet_room.acrolein_kg = maxf(0.0, inlet_room.acrolein_kg * (1.0 - mix_frac))
		inlet_room.formaldehyde_kg = maxf(0.0, inlet_room.formaldehyde_kg * (1.0 - mix_frac))
		_call_room_fraction(remove_upper_layer_fraction_callable, inlet_room, mix_frac * 0.5)
		_call_room_dt(sync_room_upper_layer_callable, inlet_room, dt)

		# Paso 2: Sobrepresión PPV en la sala → exhaustión por otras aberturas ext.
		# Elevar overpressure_pa de la sala según la presión del ventilador.
		inlet_room.overpressure_pa = maxf(inlet_room.overpressure_pa, dp_ppv_pa)

		# Paso 3: Flujo forzado de exhaustión por aberturas exteriores de la misma sala
		# (distintas de la abertura PPV de entrada). Simula flow path control.
		var exhaust_q_total_m3s: float = 0.0
		var exhaust_ops: Array = []
		for ex_op in building.get_openings():
			if ex_op.opening_index == op.opening_index:
				continue  # misma abertura PPV
			if ex_op.open_fraction < 0.01:
				continue
			var connects: bool = (
				(ex_op.a == inlet_room_id and ex_op.b == BuildingModel.OUTSIDE_ID) or
				(ex_op.b == inlet_room_id and ex_op.a == BuildingModel.OUTSIDE_ID)
			)
			if not connects:
				continue
			# Caudal de exhaustión por cada apertura: Q = Cd·A·√(2·ΔP/ρ)
			var area_m2: float = ex_op.width_m * ex_op.height_m * ex_op.effective_open_fraction()
			var v_ex: float = sqrt(2.0 * maxf(dp_ppv_pa, 1.0) * rho_ext_inv)
			var q_ex: float = 0.61 * area_m2 * v_ex
			exhaust_q_total_m3s += q_ex
			exhaust_ops.append({"op": ex_op, "q": q_ex})

		if exhaust_q_total_m3s > 0.0:
			var ex_vol_total: float = exhaust_q_total_m3s * dt
			var ex_frac: float = clampf(ex_vol_total / room_vol_m3, 0.0, 0.30)
			var smoke_purged_ex: float = inlet_room.smoke_kg * ex_frac
			var co_purged_ex: float = inlet_room.co_kg * ex_frac
			var co2_purged_ex: float = inlet_room.co2_kg * ex_frac
			var hcn_purged_ex: float = inlet_room.hcn_kg * ex_frac
			inlet_room.c_exited_kg += co_purged_ex * (12.0 / 28.0) \
					+ co2_purged_ex * (12.0 / 44.0) \
					+ hcn_purged_ex * (12.0 / 27.0) \
					+ smoke_purged_ex * 0.87
			inlet_room.smoke_kg = maxf(0.0, inlet_room.smoke_kg - smoke_purged_ex)
			_record_smoke_vented(inlet_room, smoke_purged_ex)
			inlet_room.co_kg = maxf(0.0, inlet_room.co_kg * (1.0 - ex_frac))
			inlet_room.co_upper_kg = maxf(0.0, inlet_room.co_upper_kg * (1.0 - ex_frac))
			inlet_room.co2_kg = maxf(0.0, inlet_room.co2_kg * (1.0 - ex_frac))
			inlet_room.hcn_kg = maxf(0.0, inlet_room.hcn_kg * (1.0 - ex_frac))
			inlet_room.hcl_kg = maxf(0.0, inlet_room.hcl_kg * (1.0 - ex_frac))
			inlet_room.acrolein_kg = maxf(0.0, inlet_room.acrolein_kg * (1.0 - ex_frac))
			inlet_room.formaldehyde_kg = maxf(0.0, inlet_room.formaldehyde_kg * (1.0 - ex_frac))
			_call_room_fraction(remove_upper_layer_fraction_callable, inlet_room, ex_frac)
			_call_room_dt(sync_room_upper_layer_callable, inlet_room, dt)
			result["ppv_smoke_purged_kg"] = float(result.get("ppv_smoke_purged_kg", 0.0)) + smoke_purged_ex

		result["ppv_smoke_purged_kg"] = float(result.get("ppv_smoke_purged_kg", 0.0)) + smoke_purged_inlet
		result["ppv_fresh_air_injected_kg"] = float(result.get("ppv_fresh_air_injected_kg", 0.0)) + injected_kg

	return result


# SF-R7: Intercambio bidireccional neto de especies entre dos salas
# (para aperturas verticales con ΔT pequeño — difusión mínima).
func _apply_species_net_exchange(
	room_a: RoomModel,
	room_b: RoomModel,
	exchange_kg: float,
	smoke_delta_kg: Dictionary,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary,
	o2_delta_kg: Dictionary
) -> void:
	if exchange_kg <= 0.0 or room_a == null or room_b == null:
		return
	var m_a: float = maxf(0.1, room_a.volume_m3()) * 1.2
	var m_b: float = maxf(0.1, room_b.volume_m3()) * 1.2
	var net_smoke_a_to_b: float = (room_a.smoke_kg / maxf(0.001, m_a) - room_b.smoke_kg / maxf(0.001, m_b)) * exchange_kg
	_add_delta(smoke_delta_kg, room_a.id, -net_smoke_a_to_b)
	_add_delta(smoke_delta_kg, room_b.id, net_smoke_a_to_b)
	if net_smoke_a_to_b >= 0.0:
		_record_smoke_net_transport(room_a, room_b, net_smoke_a_to_b)
	else:
		_record_smoke_net_transport(room_b, room_a, -net_smoke_a_to_b)
	_apply_net_pair(room_a.id, room_b.id, room_a.co_kg, room_b.co_kg, m_a, m_b, exchange_kg, co_delta_kg)
	_apply_net_pair(room_a.id, room_b.id, room_a.co_upper_kg, room_b.co_upper_kg, m_a, m_b, exchange_kg, co_upper_delta_kg)
	_apply_net_pair(room_a.id, room_b.id, room_a.co2_kg, room_b.co2_kg, m_a, m_b, exchange_kg, co2_delta_kg)
	if not hcn_delta_kg.is_empty():
		_apply_net_pair(room_a.id, room_b.id, room_a.hcn_kg, room_b.hcn_kg, m_a, m_b, exchange_kg, hcn_delta_kg)


# SF-R7: Transferencia unidireccional (ascendente) de especies de from_r a to_r,
# proporcional a la fracción de masa intercambiada.
func _apply_directed_species_exchange(
	from_r: RoomModel,
	to_r: RoomModel,
	mass_kg: float,
	from_mass_kg: float,
	smoke_delta_kg: Dictionary,
	co_delta_kg: Dictionary,
	co_upper_delta_kg: Dictionary,
	co2_delta_kg: Dictionary,
	hcn_delta_kg: Dictionary,
	hcl_delta_kg: Dictionary,
	acrolein_delta_kg: Dictionary,
	formaldehyde_delta_kg: Dictionary,
	o2_delta_kg: Dictionary
) -> void:
	if mass_kg <= 0.0 or from_r == null or to_r == null:
		return
	var frac: float = clampf(mass_kg / maxf(0.001, from_mass_kg), 0.0, 0.30)
	# Humo y gases tóxicos ascienden con el gas caliente (upper layer driven)
	var d_smoke: float = from_r.smoke_kg * frac
	var d_co: float = from_r.co_kg * frac
	var d_co_up: float = from_r.co_upper_kg * frac
	var d_co2: float = from_r.co2_kg * frac
	var d_hcn: float = from_r.hcn_kg * frac
	var d_hcl: float = from_r.hcl_kg * frac
	var d_acro: float = from_r.acrolein_kg * frac
	var d_form: float = from_r.formaldehyde_kg * frac
	smoke_delta_kg[from_r.id] = float(smoke_delta_kg.get(from_r.id, 0.0)) - d_smoke
	smoke_delta_kg[to_r.id] = float(smoke_delta_kg.get(to_r.id, 0.0)) + d_smoke
	_record_smoke_net_transport(from_r, to_r, d_smoke)
	co_delta_kg[from_r.id] = float(co_delta_kg.get(from_r.id, 0.0)) - d_co
	co_delta_kg[to_r.id] = float(co_delta_kg.get(to_r.id, 0.0)) + d_co
	co_upper_delta_kg[from_r.id] = float(co_upper_delta_kg.get(from_r.id, 0.0)) - d_co_up
	co_upper_delta_kg[to_r.id] = float(co_upper_delta_kg.get(to_r.id, 0.0)) + d_co_up
	co2_delta_kg[from_r.id] = float(co2_delta_kg.get(from_r.id, 0.0)) - d_co2
	co2_delta_kg[to_r.id] = float(co2_delta_kg.get(to_r.id, 0.0)) + d_co2
	if not hcn_delta_kg.is_empty():
		hcn_delta_kg[from_r.id] = float(hcn_delta_kg.get(from_r.id, 0.0)) - d_hcn
		hcn_delta_kg[to_r.id] = float(hcn_delta_kg.get(to_r.id, 0.0)) + d_hcn
	if not hcl_delta_kg.is_empty():
		hcl_delta_kg[from_r.id] = float(hcl_delta_kg.get(from_r.id, 0.0)) - d_hcl
		hcl_delta_kg[to_r.id] = float(hcl_delta_kg.get(to_r.id, 0.0)) + d_hcl
	if not acrolein_delta_kg.is_empty():
		acrolein_delta_kg[from_r.id] = float(acrolein_delta_kg.get(from_r.id, 0.0)) - d_acro
		acrolein_delta_kg[to_r.id] = float(acrolein_delta_kg.get(to_r.id, 0.0)) + d_acro
	if not formaldehyde_delta_kg.is_empty():
		formaldehyde_delta_kg[from_r.id] = float(formaldehyde_delta_kg.get(from_r.id, 0.0)) - d_form
		formaldehyde_delta_kg[to_r.id] = float(formaldehyde_delta_kg.get(to_r.id, 0.0)) + d_form


func _apply_net_pair(
	id_a: int, id_b: int,
	mass_a: float, mass_b: float,
	total_a: float, total_b: float,
	exchange_kg: float,
	delta: Dictionary
) -> void:
	var net: float = (mass_a / maxf(0.001, total_a) - mass_b / maxf(0.001, total_b)) * exchange_kg
	delta[id_a] = float(delta.get(id_a, 0.0)) - net
	delta[id_b] = float(delta.get(id_b, 0.0)) + net
