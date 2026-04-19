extends RefCounted
class_name GasExchangeSystem

var o2_nominal: float = 0.209
var window_leakage_area_m2: float = 0.005
var pressure_vent_threshold_pa: float = 2.0
var ach_infiltration: float = 0.5
var postfire_cleanup_hot_stop_c: float = 90.0
var postfire_cleanup_cool_full_c: float = 35.0
var postfire_cleanup_pressure_stop_pa: float = 0.8
var postfire_cleanup_pressure_full_pa: float = 0.10
var smoke_settling_base_per_s: float = 0.0
var smoke_settling_bonus_per_s: float = 0.0
var co_postfire_purge_base_per_s: float = 0.0
var co_postfire_purge_bonus_per_s: float = 0.0


func configure(settings: Dictionary) -> void:
	o2_nominal = float(settings.get("o2_nominal", o2_nominal))
	window_leakage_area_m2 = float(settings.get("window_leakage_area_m2", window_leakage_area_m2))
	pressure_vent_threshold_pa = float(settings.get("pressure_vent_threshold_pa", pressure_vent_threshold_pa))
	ach_infiltration = float(settings.get("ach_infiltration", ach_infiltration))
	postfire_cleanup_hot_stop_c = float(settings.get("postfire_cleanup_hot_stop_c", postfire_cleanup_hot_stop_c))
	postfire_cleanup_cool_full_c = float(settings.get("postfire_cleanup_cool_full_c", postfire_cleanup_cool_full_c))
	postfire_cleanup_pressure_stop_pa = float(settings.get("postfire_cleanup_pressure_stop_pa", postfire_cleanup_pressure_stop_pa))
	postfire_cleanup_pressure_full_pa = float(settings.get("postfire_cleanup_pressure_full_pa", postfire_cleanup_pressure_full_pa))
	smoke_settling_base_per_s = float(settings.get("smoke_settling_base_per_s", smoke_settling_base_per_s))
	smoke_settling_bonus_per_s = float(settings.get("smoke_settling_bonus_per_s", smoke_settling_bonus_per_s))
	co_postfire_purge_base_per_s = float(settings.get("co_postfire_purge_base_per_s", co_postfire_purge_base_per_s))
	co_postfire_purge_bonus_per_s = float(settings.get("co_postfire_purge_bonus_per_s", co_postfire_purge_bonus_per_s))


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
				total_leakage_m2 += window_leakage_area_m2

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

		room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_out_kg)
		result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + smoke_out_kg

		_call_room_fraction(remove_upper_layer_fraction_callable, room, frac_out)
		room.co_kg = maxf(0.0, room.co_kg * (1.0 - frac_out))
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
	var air_density_kg_m3_s: float = 1.2
	var incident_active: bool = _has_any_active_fire(building)
	var ambient_c: float = building.outside_temp_c

	var smoke_delta_kg: Dictionary = {}
	var co_delta_kg: Dictionary = {}
	var o2_delta_kg: Dictionary = {}

	for room_id in building.get_rooms().keys():
		smoke_delta_kg[int(room_id)] = 0.0
		co_delta_kg[int(room_id)] = 0.0
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
			if vented_kg > 0.0:
				smoke_delta_kg[room_out.id] -= vented_kg
				result["smoke_vented_kg"] = float(result.get("smoke_vented_kg", 0.0)) + vented_kg

				if room_out.smoke_kg > 0.001:
					var vent_frac: float = minf(1.0, vented_kg / room_out.smoke_kg)
					co_delta_kg[room_out.id] -= vent_frac * room_out.co_kg
					_call_room_fraction(remove_upper_layer_fraction_callable, room_out, vent_frac)
					_call_room_dt(sync_room_upper_layer_callable, room_out, dt)

			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		var transfers: Array[Dictionary] = smoke_model.compute_room_transfers(room_a, room_b, op, dt)
		for transfer in transfers:
			var from_id: int = int(transfer.get("from", -1))
			var to_id: int = int(transfer.get("to", -1))
			var kg: float = float(transfer.get("kg", 0.0))
			if from_id == -1 or to_id == -1 or kg <= 0.0:
				continue

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

		var max_allowed: float = room.smoke_kg * 0.60 * dt
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

		smoke_delta_kg[from_id] -= kg
		smoke_delta_kg[to_id] += kg

		var source: RoomModel = building.get_room(from_id)
		var target: RoomModel = building.get_room(to_id)
		if source == null or target == null:
			continue

		var flow_ratio: float = kg / (target.smoke_kg + kg + 0.1)
		if source.smoke_kg > 0.001 and source.upper_gas_kg > 0.001:
			var transfer_frac: float = minf(1.0, kg / source.smoke_kg)
			var gas_moved_kg: float = minf(
				source.upper_gas_kg * transfer_frac,
				maxf(0.01, source.upper_gas_kg * 0.07)
			)
			var transferred_temp_c: float = _call_transfer_temp(
				compute_interroom_transfer_temp_callable,
				source,
				target,
				transfer_frac,
				ambient_c
			)
			var energy_moved_kj: float = gas_moved_kg * maxf(0.0, transferred_temp_c - ambient_c)
			energy_moved_kj = minf(energy_moved_kj, source.upper_energy_kj)

			source.upper_gas_kg = maxf(0.0, source.upper_gas_kg - gas_moved_kg)
			source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - energy_moved_kj)
			target.upper_gas_kg += gas_moved_kg
			target.upper_energy_kj += energy_moved_kj

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

		if source.smoke_kg > 0.001:
			var co_moved: float = minf(kg / source.smoke_kg, 1.0) * source.co_kg
			co_delta_kg[from_id] -= co_moved
			co_delta_kg[to_id] += co_moved

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

		var ach_rate: float = ach_infiltration / 3600.0
		var co_removed: float = room.co_kg * ach_rate * dt
		room.co_kg = maxf(0.0, room.co_kg - co_removed)

		var smoke_concentration: float = room.smoke_kg / (room_volume_m3_s * air_density_kg_m3_s)
		var smoke_removed: float = room_volume_m3_s * air_density_kg_m3_s * smoke_concentration * ach_rate * dt
		room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_removed)

		var cleanup_factor: float = _compute_postfire_cleanup_factor(room, incident_active)
		if cleanup_factor > 0.0:
			var smoke_settling_rate: float = smoke_settling_base_per_s + smoke_settling_bonus_per_s * cleanup_factor
			var deposited_smoke_kg: float = minf(room.smoke_kg, room.smoke_kg * smoke_settling_rate * dt)
			room.smoke_kg = maxf(0.0, room.smoke_kg - deposited_smoke_kg)
			result["smoke_deposited_kg"] = float(result.get("smoke_deposited_kg", 0.0)) + deposited_smoke_kg

			var co_purge_rate: float = co_postfire_purge_base_per_s + co_postfire_purge_bonus_per_s * cleanup_factor
			var purged_co_kg: float = minf(room.co_kg, room.co_kg * co_purge_rate * dt)
			room.co_kg = maxf(0.0, room.co_kg - purged_co_kg)

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		_call_room_dt(sync_room_upper_layer_callable, room, dt)

	return result


func _compute_postfire_cleanup_factor(room: RoomModel, incident_active: bool) -> float:
	if room == null or incident_active:
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
