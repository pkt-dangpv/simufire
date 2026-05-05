extends RefCounted
class_name GasExchangeSystem

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
var background_species_path_multiplier_max: float = 3.00
var background_species_max_fraction_closed: float = 0.010
var background_species_max_fraction_open: float = 0.040
var flow_path_direct_fire_vent_reduction: float = 0.70
var flow_path_direct_fire_min_vent_fraction: float = 0.25
var flow_path_interior_pull_boost: float = 1.50
var flow_path_interior_pull_max_multiplier: float = 3.00
var flow_path_remote_decay_per_door: float = 0.60
var flow_path_remote_max_doors: int = 4
var _pending_interior_deliveries: Array[Dictionary] = []


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


func reset() -> void:
	_pending_interior_deliveries.clear()


func step_pressure_venting(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"smoke_vented_kg": 0.0
	}
	if building == null:
		return result

	var effective_hot_layer_callable: Callable = hooks.get("effective_hot_layer_height_callable", Callable())
	var remove_upper_layer_fraction_callable: Callable = hooks.get("remove_upper_layer_fraction_callable", Callable())
	var sync_room_upper_layer_callable: Callable = hooks.get("sync_room_upper_layer_callable", Callable())
	var g: float = 9.81
	var rho_ext: float = 1.2
	var t_ext_k: float = building.outside_temp_c + 273.15

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var t_upper_k: float = room.temp_upper_c + 273.15
		var effective_hot_layer_m: float = _call_room_float(
			effective_hot_layer_callable,
			room,
			clampf(room.thermal_layer_m, 0.0, room.height_m)
		)
		var h_smoke_m: float = maxf(0.0, room.height_m - effective_hot_layer_m)
		var dp_buoyancy: float = rho_ext * g * h_smoke_m * maxf(0.0, 1.0 - t_ext_k / t_upper_k)

		var tau_s: float = 5.0
		room.overpressure_pa += (dp_buoyancy - room.overpressure_pa) * minf(1.0, dt / tau_s)
		room.overpressure_pa = maxf(0.0, room.overpressure_pa)

		if room.overpressure_pa < pressure_vent_threshold_pa:
			continue

		var total_leakage_m2: float = 0.0
		for op in building.get_openings():
			var connects_outside: bool = (
				(op.a == room.id and op.b == BuildingModel.OUTSIDE_ID) or
				(op.b == room.id and op.a == BuildingModel.OUTSIDE_ID)
			)
			if connects_outside:
				# Si la abertura está abierta, usa el área efectiva real en lugar
				# del área de infiltración. Un ventana/puerta abierta alivia
				# la presión mucho más rápido que las fugas de marco.
				if op.open_fraction > 0.001:
					total_leakage_m2 += op.width_m * op.height_m * op.open_fraction
				else:
					total_leakage_m2 += window_leakage_area_m2

		if total_leakage_m2 <= 0.0:
			continue
		total_leakage_m2 *= _compute_flow_path_direct_exterior_vent_fraction(building, room)
		if total_leakage_m2 <= 0.0:
			continue

		var rho_hot: float = rho_ext * t_ext_k / t_upper_k
		var v_out: float = sqrt(2.0 * room.overpressure_pa / maxf(0.05, rho_hot))
		var q_out_m3s: float = 0.61 * total_leakage_m2 * v_out
		var smoke_out_kg: float = q_out_m3s * rho_hot * dt

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
		result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + smoke_out_kg

		_call_room_fraction(remove_upper_layer_fraction_callable, room, frac_out)
		room.co_kg = maxf(0.0, room.co_kg * (1.0 - air_frac_out))
		room.co_upper_kg = maxf(0.0, room.co_upper_kg * (1.0 - air_frac_out))
		room.co2_kg = maxf(0.0, room.co2_kg * (1.0 - air_frac_out))
		room.hcn_kg = maxf(0.0, room.hcn_kg * (1.0 - air_frac_out))
		_call_room_dt(sync_room_upper_layer_callable, room, dt)

		room.overpressure_pa = maxf(0.0, room.overpressure_pa * (1.0 - frac_out * 0.9))

		var air_in_kg: float = smoke_out_kg * 0.40
		var room_mass_kg: float = maxf(1.0, room.volume_m3()) * rho_ext
		room.o2 = clampf(
			(room.o2 * room_mass_kg + building.outside_o2 * air_in_kg) / (room_mass_kg + air_in_kg),
			0.0,
			o2_nominal
		)

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
	var air_density_kg_m3_s: float = 1.2
	var incident_active: bool = _has_any_active_fire(building)
	var ambient_c: float = building.outside_temp_c

	_release_pending_interior_deliveries(building, dt, sync_room_upper_layer_callable)

	var smoke_delta_kg: Dictionary = {}
	var co_delta_kg: Dictionary = {}
	var co_upper_delta_kg: Dictionary = {}
	var co2_delta_kg: Dictionary = {}
	var hcn_delta_kg: Dictionary = {}
	var o2_delta_kg: Dictionary = {}

	for room_id in building.get_rooms().keys():
		smoke_delta_kg[int(room_id)] = 0.0
		co_delta_kg[int(room_id)] = 0.0
		co_upper_delta_kg[int(room_id)] = 0.0
		co2_delta_kg[int(room_id)] = 0.0
		hcn_delta_kg[int(room_id)] = 0.0
		o2_delta_kg[int(room_id)] = 0.0

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var generated_kg: float = smoke_model.add_generated_smoke(room, dt)
		result["smoke_generated_kg"] = float(result.get("smoke_generated_kg", 0.0)) + generated_kg
		smoke_delta_kg[int(room_id)] += generated_kg

	var room_transfers: Array[Dictionary] = []
	for op in building.get_openings():
		if op.open_fraction <= 0.0:
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

				if room_out.smoke_kg > 0.001:
					var vent_frac: float = minf(1.0, vented_kg / room_out.smoke_kg)
					co_delta_kg[room_out.id] -= vent_frac * room_out.co_kg
					co_upper_delta_kg[room_out.id] -= vent_frac * room_out.co_upper_kg
					co2_delta_kg[room_out.id] -= vent_frac * room_out.co2_kg
					hcn_delta_kg[room_out.id] -= vent_frac * room_out.hcn_kg
					_call_room_fraction(remove_upper_layer_fraction_callable, room_out, vent_frac)
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
			var nat_area_m2: float = op.width_m * op.height_m * op.open_fraction
			if nat_area_m2 > 0.0:
				# Velocidad de flotabilidad térmica: v = sqrt(2·g·h_eff·|ΔT|/T_room)
				var h_eff_m: float = op.height_m * 0.5
				var delta_t: float = maxf(0.0, room_out.temp_upper_c - building.outside_temp_c)
				var t_room_k: float = room_out.temp_upper_c + 273.15
				var v_buoy_m_s: float = 0.0
				if delta_t > 0.5:
					v_buoy_m_s = sqrt(2.0 * 9.81 * h_eff_m * delta_t / t_room_k)
				# Velocidad mínima por viento: siempre presente con ventana abierta al exterior
				var v_nat_m_s: float = maxf(0.30, v_buoy_m_s)
				# La mitad inferior de la abertura es la entrada de aire fresco (Cd≈0.61)
				var fresh_air_kg: float = 0.61 * (nat_area_m2 * 0.5) * v_nat_m_s * air_density_kg_m3_s * dt
				var room_mass_kg: float = maxf(1.0, room_out.volume_m3()) * air_density_kg_m3_s
				fresh_air_kg = minf(fresh_air_kg, room_mass_kg * 0.30)
				if fresh_air_kg > 0.0:
					# O2: el aire fresco eleva el O2 de la sala hacia el nivel exterior
					o2_delta_kg[room_out.id] += (building.outside_o2 - room_out.o2) * fresh_air_kg
					# Purga de especies: el aire caliente sale por la mitad superior,
					# diluyendo humo/CO/CO2 en proporción al caudal de intercambio
					var purge_frac: float = clampf(fresh_air_kg / room_mass_kg, 0.0, 0.30)
					purge_frac *= _compute_flow_path_direct_exterior_vent_fraction(building, room_out)
					smoke_delta_kg[room_out.id] -= room_out.smoke_kg * purge_frac
					co_delta_kg[room_out.id] -= room_out.co_kg * purge_frac
					co_upper_delta_kg[room_out.id] -= room_out.co_upper_kg * purge_frac
					co2_delta_kg[room_out.id] -= room_out.co2_kg * purge_frac

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
			hcn_delta_kg,
			o2_delta_kg,
			outside_open_path_factor_callable
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

			source.upper_gas_kg = maxf(0.0, source.upper_gas_kg - moved_upper_gas_kg)
			source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - moved_upper_energy_kj)

		var co_moved_kg: float = 0.0
		var co2_moved_kg: float = 0.0
		var hcn_moved_kg: float = 0.0
		if source.smoke_kg > 0.001:
			co_moved_kg = minf(
				minf(kg / source.smoke_kg, 1.0) * source.co_upper_kg,
				source.co_kg
			)
			co_delta_kg[from_id] -= co_moved_kg
			co2_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.co2_kg
			co2_delta_kg[from_id] -= co2_moved_kg
			hcn_moved_kg = minf(kg / source.smoke_kg, 1.0) * source.hcn_kg
			hcn_delta_kg[from_id] -= hcn_moved_kg

		if use_transport_delay:
			_pending_interior_deliveries.append({
				"target": to_id,
				"delay_s": travel_delay_s,
				"smoke_kg": kg,
				"co_kg": co_moved_kg,
				"co_upper_kg": co_moved_kg,
				"co2_kg": co2_moved_kg,
				"hcn_kg": hcn_moved_kg,
				"upper_gas_kg": moved_upper_gas_kg,
				"upper_energy_kj": moved_upper_energy_kj
			})
		else:
			smoke_delta_kg[to_id] += kg
			co_delta_kg[to_id] += co_moved_kg
			co_upper_delta_kg[to_id] += co_moved_kg
			co2_delta_kg[to_id] += co2_moved_kg
			hcn_delta_kg[to_id] += hcn_moved_kg
			target.upper_gas_kg += moved_upper_gas_kg
			target.upper_energy_kj += moved_upper_energy_kj

			var o2_mix_factor: float = 0.08 * flow_ratio
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

					var source_hcn_total_kg: float = maxf(0.0, source.hcn_kg + float(hcn_delta_kg[from_id]))
					var target_hcn_total_kg: float = maxf(0.0, target.hcn_kg + float(hcn_delta_kg[to_id]))
					var source_hcn_out_kg: float = source_hcn_total_kg / source_air_mass_kg * exchange_air_mass_kg
					var target_hcn_out_kg: float = target_hcn_total_kg / target_air_mass_kg * exchange_air_mass_kg
					hcn_delta_kg[from_id] += target_hcn_out_kg - source_hcn_out_kg
					hcn_delta_kg[to_id] += source_hcn_out_kg - target_hcn_out_kg

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var room_volume_m3_s: float = maxf(0.1, room.volume_m3())
		var room_air_mass_kg: float = room_volume_m3_s * air_density_kg_m3_s
		var room_o2_mass_kg: float = room.o2 * room_air_mass_kg + float(o2_delta_kg[int(room_id)])
		room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)

		room.smoke_kg = maxf(0.0, room.smoke_kg + float(smoke_delta_kg[int(room_id)]))
		room.co_kg = maxf(0.0, room.co_kg + float(co_delta_kg[int(room_id)]))
		room.co_upper_kg = maxf(0.0, room.co_upper_kg + float(co_upper_delta_kg[int(room_id)]))
		room.co2_kg = maxf(0.0, room.co2_kg + float(co2_delta_kg[int(room_id)]))
		room.hcn_kg = maxf(0.0, room.hcn_kg + float(hcn_delta_kg[int(room_id)]))

		var ach_rate: float = ach_infiltration / 3600.0
		var co_removed: float = room.co_kg * ach_rate * dt
		var co_remove_fraction: float = 0.0
		if room.co_kg > 0.000001:
			co_remove_fraction = co_removed / room.co_kg
		room.co_kg = maxf(0.0, room.co_kg - co_removed)
		room.co_upper_kg = maxf(0.0, room.co_upper_kg * (1.0 - clampf(co_remove_fraction, 0.0, 1.0)))
		var co2_removed: float = room.co2_kg * ach_rate * dt
		room.co2_kg = maxf(0.0, room.co2_kg - co2_removed)
		var hcn_removed: float = room.hcn_kg * ach_rate * dt
		room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_removed)
		# NOTA: la recuperación de O2 por ACH la gestiona OxygenExchangeSystem.step().
		# No se duplica aquí para evitar doble aplicación por step.

		var smoke_concentration: float = room.smoke_kg / (room_volume_m3_s * air_density_kg_m3_s)
		var smoke_ach_efficiency: float = 1.0
		if not incident_active:
			# El ACH representa bien el barrido de especies gaseosas, pero el humo
			# post-incendio queda menos perfectamente mezclado y se purga algo mas
			# despacio que CO/CO2 por simple infiltracion.
			smoke_ach_efficiency = 0.70
		var smoke_removed: float = room_volume_m3_s \
				* air_density_kg_m3_s \
				* smoke_concentration \
				* ach_rate \
				* dt \
				* smoke_ach_efficiency
		room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_removed)

		var open_species_purge_fraction: float = _compute_outside_species_purge_fraction(building, room, dt)
		if open_species_purge_fraction > 0.0:
			var upper_bias: float = clampf(outside_open_species_upper_bias, 0.0, 1.0)
			var co_upper_kg: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
			var co_lower_kg: float = maxf(0.0, room.co_kg - co_upper_kg)
			var co_upper_removed_kg: float = co_upper_kg * open_species_purge_fraction
			var co_lower_removed_kg: float = co_lower_kg * open_species_purge_fraction * (1.0 - upper_bias) * 0.55
			room.co_upper_kg = maxf(0.0, co_upper_kg - co_upper_removed_kg)
			room.co_kg = maxf(0.0, room.co_kg - co_upper_removed_kg - co_lower_removed_kg)

			var co2_removed_kg: float = room.co2_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.co2_kg = maxf(0.0, room.co2_kg - co2_removed_kg)
			var hcn_removed_kg: float = room.hcn_kg \
					* open_species_purge_fraction \
					* lerpf(0.40, 0.75, upper_bias)
			room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_removed_kg)

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
			result["smoke_deposited_kg"] = float(result.get("smoke_deposited_kg", 0.0)) + deposited_smoke_kg

			# Igual para CO/CO2: purga post-incendio solo cuando el fuego está extinto.
			var co_purge_rate: float = 0.0
			if not incident_active:
				co_purge_rate = co_postfire_purge_base_per_s + co_postfire_purge_bonus_per_s * cleanup_factor
			var purged_co_kg: float = minf(room.co_kg, room.co_kg * co_purge_rate * dt)
			var purge_co_fraction: float = 0.0
			if room.co_kg > 0.000001:
				purge_co_fraction = purged_co_kg / room.co_kg
			room.co_kg = maxf(0.0, room.co_kg - purged_co_kg)
			room.co_upper_kg = maxf(0.0, room.co_upper_kg * (1.0 - clampf(purge_co_fraction, 0.0, 1.0)))

			var purged_co2_kg: float = minf(room.co2_kg, room.co2_kg * co_purge_rate * dt)
			room.co2_kg = maxf(0.0, room.co2_kg - purged_co2_kg)
			var purged_hcn_kg: float = minf(room.hcn_kg, room.hcn_kg * co_purge_rate * dt)
			room.hcn_kg = maxf(0.0, room.hcn_kg - purged_hcn_kg)

		room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)

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
		var target: RoomModel = building.get_room(target_id)
		if target == null:
			continue

		target.smoke_kg = maxf(0.0, target.smoke_kg + float(entry.get("smoke_kg", 0.0)))
		target.co_kg = maxf(0.0, target.co_kg + float(entry.get("co_kg", 0.0)))
		target.co_upper_kg = maxf(0.0, target.co_upper_kg + float(entry.get("co_upper_kg", 0.0)))
		target.co2_kg = maxf(0.0, target.co2_kg + float(entry.get("co2_kg", 0.0)))
		target.hcn_kg = maxf(0.0, target.hcn_kg + float(entry.get("hcn_kg", 0.0)))
		target.upper_gas_kg = maxf(0.0, target.upper_gas_kg + float(entry.get("upper_gas_kg", 0.0)))
		target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + float(entry.get("upper_energy_kj", 0.0)))
		target.co_upper_kg = clampf(target.co_upper_kg, 0.0, target.co_kg)
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
	hcn_delta_kg: Dictionary = {},
	o2_delta_kg: Dictionary = {},
	outside_open_path_factor_callable: Callable = Callable()
) -> void:
	if building == null or room_a == null or room_b == null or op == null or dt <= 0.0:
		return

	var area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if area_eff_m2 <= 0.0:
		return

	var air_density_kg_m3: float = 1.2
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

	var background_drive: float = maxf(
		0.25,
		maxf(
			clampf(maxf(room_a.overpressure_pa, room_b.overpressure_pa) / 1.5, 0.0, 1.0),
			clampf(outside_open_factor * 0.85, 0.0, 1.0)
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

	# O2: intercambio por gradiente de concentración entre salas conectadas.
	# El O2 fluye de la sala con más O2 hacia la sala con menos O2 (difusión).
	if not o2_delta_kg.is_empty():
		var net_o2_a_to_b: float = (room_a.o2 - room_b.o2) * exchange_air_kg
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
