extends RefCounted
class_name HVACSystem

# ============================================================
# HVAC SYSTEM
# ------------------------------------------------------------
# Transporte simplificado por red HVAC residencial:
# - none: no hay red instalada (BuildingModel.hvac_exists = false)
# - off: registros/ductos existen y permiten una mezcla pasiva debil
# - on: ventilador activo, retorno -> mezcla -> suministro
#
# No sustituye a infiltracion ACH ni a puertas/ventanas. Es un camino
# adicional de calor, O2, humo y especies por conductos.
# ============================================================

const AIR_DENSITY_KG_M3: float = 1.20
const AIR_CP_KJ_KG_K: float = 1.00

var max_fraction_forced_per_step: float = 0.10
var max_fraction_passive_per_step: float = 0.025
var smoke_filter_penetration: float = 0.75
var species_filter_penetration: float = 0.95
var high_return_smoke_capture_cap: float = 5.0


func reset() -> void:
	pass


func step(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"active": false,
		"transported_air_kg": 0.0,
		"smoke_exhausted_kg": 0.0,
		"smoke_recirculated_kg": 0.0,
		"c_exhausted_kg": 0.0
	}
	if building == null or dt <= 0.0:
		return result
	if not building.is_hvac_available():
		return result

	var hvac: Dictionary = building.get_hvac_data()
	if hvac.is_empty():
		return result

	var is_on: bool = building.is_hvac_on()
	var flow_m3_s: float = float(hvac.get("fan_flow_m3_s", 0.0)) if is_on else float(hvac.get("off_passive_flow_m3_s", 0.0))
	if flow_m3_s <= 0.000001:
		return result

	result["active"] = is_on
	var return_vents: Array = _collect_valid_vents(building, hvac.get("returns", []))
	var supply_vents: Array = _collect_valid_vents(building, hvac.get("supplies", []))
	if return_vents.is_empty() or supply_vents.is_empty():
		return result

	var max_room_fraction: float = max_fraction_forced_per_step if is_on else max_fraction_passive_per_step
	var outside_air_fraction: float = clampf(float(hvac.get("outside_air_fraction", 0.0)) if is_on else 0.0, 0.0, 1.0)
	var exhaust_fraction: float = outside_air_fraction
	var effective_return_flow_m3_s: float = flow_m3_s

	var return_sample: Dictionary = _extract_return_air(
		building,
		return_vents,
		effective_return_flow_m3_s,
		dt,
		max_room_fraction,
		hooks
	)
	var returned_air_kg: float = float(return_sample.get("air_kg", 0.0))
	if returned_air_kg <= 0.000001:
		return result

	var recirculated_fraction: float = maxf(0.0, 1.0 - exhaust_fraction)
	var smoke_from_returns_kg: float = float(return_sample.get("smoke_kg", 0.0))
	result["transported_air_kg"] = returned_air_kg
	result["smoke_exhausted_kg"] = smoke_from_returns_kg * exhaust_fraction
	var c_from_returns_kg: float = float(return_sample.get("co_kg", 0.0)) * (12.0 / 28.0) \
			+ float(return_sample.get("co2_kg", 0.0)) * (12.0 / 44.0) \
			+ float(return_sample.get("hcn_kg", 0.0)) * (12.0 / 27.0) \
			+ smoke_from_returns_kg * 0.87

	var supply_mix: Dictionary = {
		"o2": lerpf(float(return_sample.get("o2", building.outside_o2)), building.outside_o2, outside_air_fraction),
		# Fase 2B: co2_upper del supply = mezcla entre retorno y exterior (0.0004 mol fraction).
		"co2_upper": lerpf(float(return_sample.get("co2_upper", 0.0004)), 0.0004, outside_air_fraction),
		"temp_c": _compute_supply_temp_c(building, hvac, return_sample, outside_air_fraction, is_on),
		"smoke_kg_per_kg_air": (
			smoke_from_returns_kg
			* recirculated_fraction
			* clampf(float(hvac.get("smoke_filter_penetration", smoke_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg,
		"co_kg_per_kg_air": (
			float(return_sample.get("co_kg", 0.0))
			* recirculated_fraction
			* clampf(float(hvac.get("species_filter_penetration", species_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg,
		"co_upper_kg_per_kg_air": (
			float(return_sample.get("co_upper_kg", 0.0))
			* recirculated_fraction
			* clampf(float(hvac.get("species_filter_penetration", species_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg,
		"co2_kg_per_kg_air": (
			float(return_sample.get("co2_kg", 0.0))
			* recirculated_fraction
			* clampf(float(hvac.get("species_filter_penetration", species_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg,
		"co2_upper_kg_per_kg_air": (
			float(return_sample.get("co2_upper_kg", 0.0))
			* recirculated_fraction
			* clampf(float(hvac.get("species_filter_penetration", species_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg,
		"hcn_kg_per_kg_air": (
			float(return_sample.get("hcn_kg", 0.0))
			* recirculated_fraction
			* clampf(float(hvac.get("species_filter_penetration", species_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg,
		"hcn_upper_kg_per_kg_air": (
			float(return_sample.get("hcn_upper_kg", 0.0))
			* recirculated_fraction
			* clampf(float(hvac.get("species_filter_penetration", species_filter_penetration)), 0.0, 1.0)
		) / returned_air_kg
	}

	var supply_result: Dictionary = _supply_air(
		building,
		supply_vents,
		flow_m3_s,
		dt,
		max_room_fraction,
		supply_mix,
		hooks
	)
	result["smoke_recirculated_kg"] = float(supply_result.get("smoke_recirculated_kg", 0.0))
	# SF-CBAL: todo carbono retirado que no vuelve por supply sale o queda en filtros.
	result["c_exhausted_kg"] = maxf(
		0.0,
		c_from_returns_kg - float(supply_result.get("c_supplied_kg", 0.0))
	)
	_sync_touched_rooms(building, return_sample.get("touched_room_ids", []), hooks, dt)
	_sync_touched_rooms(building, _collect_vent_room_ids(supply_vents), hooks, dt)
	return result


func _extract_return_air(
	building: BuildingModel,
	return_vents: Array,
	total_flow_m3_s: float,
	dt: float,
	max_room_fraction: float,
	hooks: Dictionary
) -> Dictionary:
	var sample: Dictionary = {
		"air_kg": 0.0,
		"temp_weighted_c_kg": 0.0,
		"o2_weighted_kg": 0.0,
		"smoke_kg": 0.0,
		"co_kg": 0.0,
		"co_upper_kg": 0.0,
		"co2_kg": 0.0,
		"co2_upper_kg": 0.0,
		"hcn_kg": 0.0,
		"hcn_upper_kg": 0.0,
		"co2_upper_weighted_kg": 0.0,  # Fase 2B: fracción molar CO₂ zona alta × kg aire
		"touched_room_ids": []
	}
	var total_weight: float = _sum_vent_weights(return_vents)
	if total_weight <= 0.0:
		return sample

	for vent in return_vents:
		var room_id: int = int(vent.get("room_id", -1))
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var flow_m3_s: float = _resolve_vent_flow_m3_s(vent, total_flow_m3_s, total_weight)
		var air_kg: float = flow_m3_s * AIR_DENSITY_KG_M3 * dt
		if air_kg <= 0.000001:
			continue

		var room_air_kg: float = maxf(1.0, room.volume_m3() * AIR_DENSITY_KG_M3)
		var air_fraction: float = clampf(air_kg / room_air_kg, 0.0, max_room_fraction)
		air_kg = room_air_kg * air_fraction
		if air_kg <= 0.000001:
			continue

		var vent_height_m: float = _vent_height_m(room, vent)
		var sample_temp_c: float = _estimate_temp_at_height(room, vent_height_m, hooks)
		var hot_layer_m: float = _effective_hot_layer_height(room, hooks)
		var upper_sample_factor: float = _upper_sampling_factor(room, vent_height_m, hot_layer_m)
		var use_two_zone_hvac: bool = bool(hooks.get("two_zone_opening_flow_enabled", false))
		var sample_upper_zone: bool = vent_height_m >= hot_layer_m

		var smoke_removed_kg: float = _remove_smoke_from_room(room, air_fraction, upper_sample_factor)
		var species_removed: Dictionary = _remove_species_from_room(
			room,
			air_fraction,
			upper_sample_factor,
			use_two_zone_hvac,
			sample_upper_zone
		)
		_remove_heat_from_return(room, air_fraction, upper_sample_factor, hooks)

		sample["air_kg"] = float(sample["air_kg"]) + air_kg
		sample["temp_weighted_c_kg"] = float(sample["temp_weighted_c_kg"]) + sample_temp_c * air_kg
		sample["o2_weighted_kg"] = float(sample["o2_weighted_kg"]) + room.o2 * air_kg
		sample["co2_upper_weighted_kg"] = float(sample.get("co2_upper_weighted_kg", 0.0)) + room.co2_upper * air_kg
		sample["smoke_kg"] = float(sample["smoke_kg"]) + smoke_removed_kg
		sample["co_kg"] = float(sample["co_kg"]) + float(species_removed.get("co_kg", 0.0))
		sample["co_upper_kg"] = float(sample["co_upper_kg"]) + float(species_removed.get("co_upper_kg", 0.0))
		sample["co2_kg"] = float(sample["co2_kg"]) + float(species_removed.get("co2_kg", 0.0))
		sample["co2_upper_kg"] = float(sample["co2_upper_kg"]) + float(species_removed.get("co2_upper_kg", 0.0))
		sample["hcn_kg"] = float(sample["hcn_kg"]) + float(species_removed.get("hcn_kg", 0.0))
		sample["hcn_upper_kg"] = float(sample["hcn_upper_kg"]) + float(species_removed.get("hcn_upper_kg", 0.0))
		_append_unique_int(sample["touched_room_ids"], room_id)

	var total_air_kg: float = float(sample.get("air_kg", 0.0))
	if total_air_kg > 0.000001:
		sample["temp_c"] = float(sample.get("temp_weighted_c_kg", 0.0)) / total_air_kg
		sample["o2"] = float(sample.get("o2_weighted_kg", 0.0)) / total_air_kg
		sample["co2_upper"] = float(sample.get("co2_upper_weighted_kg", 0.0)) / total_air_kg
	else:
		sample["temp_c"] = building.outside_temp_c
		sample["o2"] = building.outside_o2
		sample["co2_upper"] = 0.0004

	return sample


func _supply_air(
	building: BuildingModel,
	supply_vents: Array,
	total_flow_m3_s: float,
	dt: float,
	max_room_fraction: float,
	supply_mix: Dictionary,
	hooks: Dictionary
) -> Dictionary:
	var result: Dictionary = {
		"smoke_recirculated_kg": 0.0,
		"c_supplied_kg": 0.0
	}
	var total_weight: float = _sum_vent_weights(supply_vents)
	if total_weight <= 0.0:
		return result

	var recirculated_smoke_kg: float = 0.0
	var c_supplied_kg: float = 0.0
	for vent in supply_vents:
		var room_id: int = int(vent.get("room_id", -1))
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var flow_m3_s: float = _resolve_vent_flow_m3_s(vent, total_flow_m3_s, total_weight)
		var air_kg: float = flow_m3_s * AIR_DENSITY_KG_M3 * dt
		var room_air_kg: float = maxf(1.0, room.volume_m3() * AIR_DENSITY_KG_M3)
		var air_fraction: float = clampf(air_kg / room_air_kg, 0.0, max_room_fraction)
		air_kg = room_air_kg * air_fraction
		if air_kg <= 0.000001:
			continue

		var smoke_added_kg: float = maxf(0.0, float(supply_mix.get("smoke_kg_per_kg_air", 0.0)) * air_kg)
		var co_added_kg: float = maxf(0.0, float(supply_mix.get("co_kg_per_kg_air", 0.0)) * air_kg)
		var co_upper_added_kg: float = maxf(0.0, float(supply_mix.get("co_upper_kg_per_kg_air", 0.0)) * air_kg)
		var co2_added_kg: float = maxf(0.0, float(supply_mix.get("co2_kg_per_kg_air", 0.0)) * air_kg)
		var co2_upper_added_kg: float = maxf(0.0, float(supply_mix.get("co2_upper_kg_per_kg_air", 0.0)) * air_kg)
		var hcn_added_kg: float = maxf(0.0, float(supply_mix.get("hcn_kg_per_kg_air", 0.0)) * air_kg)
		var hcn_upper_added_kg: float = maxf(0.0, float(supply_mix.get("hcn_upper_kg_per_kg_air", 0.0)) * air_kg)
		var use_two_zone_hvac: bool = bool(hooks.get("two_zone_opening_flow_enabled", false))
		var vent_height_m: float = _vent_height_m(room, vent)
		var hot_layer_m: float = _effective_hot_layer_height(room, hooks)
		var high_supply: bool = vent_height_m >= hot_layer_m

		room.smoke_kg += smoke_added_kg
		room.co_kg += co_added_kg
		room.co2_kg += co2_added_kg
		room.hcn_kg += hcn_added_kg
		if use_two_zone_hvac:
			if high_supply:
				room.co_upper_kg = clampf(room.co_upper_kg + co_added_kg, 0.0, room.co_kg)
				room.co2_upper_kg = clampf(room.co2_upper_kg + co2_added_kg, 0.0, room.co2_kg)
				room.hcn_upper_kg = clampf(room.hcn_upper_kg + hcn_added_kg, 0.0, room.hcn_kg)
		else:
			room.co_upper_kg = clampf(room.co_upper_kg + co_upper_added_kg, 0.0, room.co_kg)
			room.co2_upper_kg = clampf(room.co2_upper_kg + co2_upper_added_kg, 0.0, room.co2_kg)
			room.hcn_upper_kg = clampf(room.hcn_upper_kg + hcn_upper_added_kg, 0.0, room.hcn_kg)
		room.o2 = lerpf(room.o2, clampf(float(supply_mix.get("o2", building.outside_o2)), 0.0, building.outside_o2), air_fraction)
		var supply_o2: float = clampf(float(supply_mix.get("o2", building.outside_o2)), 0.0, building.outside_o2)
		if use_two_zone_hvac:
			if high_supply:
				room.o2_upper = clampf(lerpf(room.o2_upper, supply_o2, air_fraction), 0.0, building.outside_o2)
			else:
				room.o2_lower = clampf(lerpf(room.o2_lower, supply_o2, air_fraction), room.o2, building.outside_o2)
		# Phase 2H Exp 2H.2: suministro HVAC en zona baja (height_fraction < 0.5) repone o2_lower.
		# Físicamente: el aire fresco inyectado a baja altura refresca directamente la capa inferior.
		# Invariante o2_lower ≥ room.o2 preservada por clampf con room.o2 como floor.
		elif bool(hooks.get("phase2h_o2_doorway_two_zone_enabled", false)):
			if float(vent.get("height_fraction", 1.0)) < 0.5:
				room.o2_lower = clampf(lerpf(room.o2_lower, supply_o2, air_fraction), room.o2, building.outside_o2)
		# Fase 2B: diluir co2_upper con el CO₂ del aire suministrado (0.0004 si es 100% exterior).
		var supply_co2_upper: float = float(supply_mix.get("co2_upper", 0.0004))
		room.co2_upper = clampf(lerpf(room.co2_upper, supply_co2_upper, air_fraction), 0.0, 0.30)
		_apply_supply_heat(room, vent, air_kg, float(supply_mix.get("temp_c", building.outside_temp_c)), hooks)
		recirculated_smoke_kg += smoke_added_kg
		c_supplied_kg += co_added_kg * (12.0 / 28.0) \
				+ co2_added_kg * (12.0 / 44.0) \
				+ hcn_added_kg * (12.0 / 27.0) \
				+ smoke_added_kg * 0.87

	result["smoke_recirculated_kg"] = recirculated_smoke_kg
	result["c_supplied_kg"] = c_supplied_kg
	return result


func _compute_supply_temp_c(
	building: BuildingModel,
	hvac: Dictionary,
	return_sample: Dictionary,
	outside_air_fraction: float,
	is_on: bool
) -> float:
	var recirc_temp_c: float = float(return_sample.get("temp_c", building.outside_temp_c))
	var mixed_temp_c: float = lerpf(recirc_temp_c, building.outside_temp_c, outside_air_fraction)
	if not is_on:
		return mixed_temp_c

	if not bool(hvac.get("condition_supply_air", false)):
		return mixed_temp_c

	var target_c: float = float(hvac.get("supply_temp_c", mixed_temp_c))
	var strength: float = clampf(float(hvac.get("conditioning_strength", 0.60)), 0.0, 1.0)
	return lerpf(mixed_temp_c, target_c, strength)


func _remove_smoke_from_room(room: RoomModel, air_fraction: float, upper_sample_factor: float) -> float:
	if room == null or room.smoke_kg <= 0.0:
		return 0.0
	var capture: float = clampf(air_fraction * upper_sample_factor, 0.0, 0.35)
	var removed_kg: float = minf(room.smoke_kg, room.smoke_kg * capture)
	room.smoke_kg = maxf(0.0, room.smoke_kg - removed_kg)
	return removed_kg


func _remove_species_from_room(
	room: RoomModel,
	air_fraction: float,
	upper_sample_factor: float,
	two_zone_hvac_enabled: bool = false,
	sample_upper_zone: bool = false
) -> Dictionary:
	var removed: Dictionary = {
		"co_kg": 0.0,
		"co_upper_kg": 0.0,
		"co2_kg": 0.0,
		"co2_upper_kg": 0.0,
		"hcn_kg": 0.0,
		"hcn_upper_kg": 0.0
	}
	if room == null:
		return removed

	if two_zone_hvac_enabled:
		var zone_fraction: float = clampf(air_fraction, 0.0, 0.30)
		if sample_upper_zone:
			zone_fraction = clampf(air_fraction * upper_sample_factor, 0.0, 0.30)

			var co_upper_available_tz: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
			var co_upper_removed: float = minf(co_upper_available_tz, co_upper_available_tz * zone_fraction)
			room.co_upper_kg = maxf(0.0, co_upper_available_tz - co_upper_removed)
			room.co_kg = maxf(0.0, room.co_kg - co_upper_removed)

			var co2_upper_available_tz: float = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
			var co2_upper_removed: float = minf(co2_upper_available_tz, co2_upper_available_tz * zone_fraction)
			room.co2_upper_kg = maxf(0.0, co2_upper_available_tz - co2_upper_removed)
			room.co2_kg = maxf(0.0, room.co2_kg - co2_upper_removed)

			var hcn_upper_available_tz: float = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
			var hcn_upper_removed: float = minf(hcn_upper_available_tz, hcn_upper_available_tz * zone_fraction)
			room.hcn_upper_kg = maxf(0.0, hcn_upper_available_tz - hcn_upper_removed)
			room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_upper_removed)

			removed["co_kg"] = co_upper_removed
			removed["co_upper_kg"] = co_upper_removed
			removed["co2_kg"] = co2_upper_removed
			removed["co2_upper_kg"] = co2_upper_removed
			removed["hcn_kg"] = hcn_upper_removed
			removed["hcn_upper_kg"] = hcn_upper_removed
		else:
			zone_fraction = clampf(zone_fraction, 0.0, 0.20)

			var co_upper_available_tz: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
			var co_lower_removed: float = maxf(0.0, room.co_kg - co_upper_available_tz) * zone_fraction
			room.co_kg = maxf(0.0, room.co_kg - co_lower_removed)

			var co2_upper_available_tz: float = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
			var co2_lower_removed: float = maxf(0.0, room.co2_kg - co2_upper_available_tz) * zone_fraction
			room.co2_kg = maxf(0.0, room.co2_kg - co2_lower_removed)

			var hcn_upper_available_tz: float = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
			var hcn_lower_removed: float = maxf(0.0, room.hcn_kg - hcn_upper_available_tz) * zone_fraction
			room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_lower_removed)

			removed["co_kg"] = co_lower_removed
			removed["co2_kg"] = co2_lower_removed
			removed["hcn_kg"] = hcn_lower_removed

		room.hcl_kg = maxf(0.0, room.hcl_kg * (1.0 - zone_fraction))
		room.acrolein_kg = maxf(0.0, room.acrolein_kg * (1.0 - zone_fraction))
		room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg * (1.0 - zone_fraction))
		return removed

	var upper_bias: float = clampf(inverse_lerp(1.0, high_return_smoke_capture_cap, upper_sample_factor), 0.0, 1.0)
	var upper_fraction: float = clampf(air_fraction * lerpf(1.0, 2.2, upper_bias), 0.0, 0.30)
	var lower_fraction: float = clampf(air_fraction * lerpf(1.0, 0.45, upper_bias), 0.0, 0.20)

	var co_upper_available: float = clampf(room.co_upper_kg, 0.0, room.co_kg)
	var co_lower_available: float = maxf(0.0, room.co_kg - co_upper_available)
	var co_upper_removed: float = minf(co_upper_available, co_upper_available * upper_fraction)
	var co_lower_removed: float = minf(co_lower_available, co_lower_available * lower_fraction)
	room.co_upper_kg = maxf(0.0, co_upper_available - co_upper_removed)
	room.co_kg = maxf(0.0, room.co_kg - co_upper_removed - co_lower_removed)

	var well_mixed_fraction: float = clampf(air_fraction * lerpf(1.0, 1.35, upper_bias), 0.0, 0.22)
	var co2_removed: float = minf(room.co2_kg, room.co2_kg * well_mixed_fraction)
	var hcn_removed: float = minf(room.hcn_kg, room.hcn_kg * well_mixed_fraction)
	var hcl_removed: float = minf(room.hcl_kg, room.hcl_kg * well_mixed_fraction)
	var acrolein_removed: float = minf(room.acrolein_kg, room.acrolein_kg * well_mixed_fraction)
	var formaldehyde_removed: float = minf(room.formaldehyde_kg, room.formaldehyde_kg * well_mixed_fraction)
	room.co2_kg = maxf(0.0, room.co2_kg - co2_removed)
	room.hcn_kg = maxf(0.0, room.hcn_kg - hcn_removed)
	room.hcl_kg = maxf(0.0, room.hcl_kg - hcl_removed)
	room.acrolein_kg = maxf(0.0, room.acrolein_kg - acrolein_removed)
	room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg - formaldehyde_removed)

	removed["co_kg"] = co_upper_removed + co_lower_removed
	removed["co_upper_kg"] = co_upper_removed
	removed["co2_kg"] = co2_removed
	removed["hcn_kg"] = hcn_removed
	return removed


func _remove_heat_from_return(room: RoomModel, air_fraction: float, upper_sample_factor: float, hooks: Dictionary) -> void:
	if room == null:
		return
	if upper_sample_factor <= 1.0:
		return
	var remove_upper_layer_fraction_callable: Callable = hooks.get("remove_upper_layer_fraction_callable", Callable())
	if not remove_upper_layer_fraction_callable.is_valid():
		return
	var layer_fraction: float = clampf(air_fraction * inverse_lerp(1.0, high_return_smoke_capture_cap, upper_sample_factor), 0.0, 0.12)
	if layer_fraction > 0.0:
		remove_upper_layer_fraction_callable.call(room, layer_fraction)


func _apply_supply_heat(room: RoomModel, vent: Dictionary, air_kg: float, supply_temp_c: float, hooks: Dictionary) -> void:
	if room == null or air_kg <= 0.0:
		return

	var room_air_kg: float = maxf(1.0, room.volume_m3() * AIR_DENSITY_KG_M3)
	var mix_fraction: float = clampf(air_kg / room_air_kg, 0.0, 0.12)
	var vent_height_m: float = _vent_height_m(room, vent)
	var hot_layer_m: float = _effective_hot_layer_height(room, hooks)
	var high_supply: bool = vent_height_m >= hot_layer_m
	var ambient_c: float = 20.0
	var ambient_callable: Callable = hooks.get("ambient_temp_callable", Callable())
	if ambient_callable.is_valid():
		ambient_c = float(ambient_callable.call())

	if high_supply and (room.upper_gas_kg > 0.0 or supply_temp_c > room.temp_lower_c + 4.0):
		var upper_air_kg: float = maxf(room.upper_gas_kg, air_kg)
		var thermal_mix: float = clampf(air_kg / maxf(1.0, upper_air_kg + air_kg), 0.0, 0.35)
		var target_upper_c: float = lerpf(room.temp_upper_c, supply_temp_c, thermal_mix)
		room.temp_upper_c = maxf(room.temp_lower_c, target_upper_c)
		room.temp_upper_raw_c = maxf(room.temp_upper_raw_c, room.temp_upper_c)
		room.upper_gas_kg = maxf(room.upper_gas_kg, air_kg * 0.35)
		room.upper_energy_kj = maxf(0.0, room.upper_gas_kg * maxf(0.0, room.temp_upper_c - ambient_c) * AIR_CP_KJ_KG_K)
	else:
		room.temp_lower_c = lerpf(room.temp_lower_c, supply_temp_c, mix_fraction * 0.65)
		if room.temp_upper_c < room.temp_lower_c:
			room.temp_upper_c = room.temp_lower_c


func _upper_sampling_factor(room: RoomModel, vent_height_m: float, hot_layer_m: float) -> float:
	if room == null:
		return 1.0
	if vent_height_m < hot_layer_m:
		return 0.25
	var upper_depth_m: float = maxf(0.08, room.height_m - hot_layer_m)
	var upper_volume_m3: float = maxf(0.10, room.floor_area_m2() * upper_depth_m)
	var whole_volume_m3: float = maxf(0.10, room.volume_m3())
	return clampf(whole_volume_m3 / upper_volume_m3, 1.0, high_return_smoke_capture_cap)


func _collect_valid_vents(building: BuildingModel, raw_vents: Variant) -> Array:
	var result: Array = []
	if typeof(raw_vents) != TYPE_ARRAY:
		return result
	for entry in raw_vents:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var vent: Dictionary = Dictionary(entry)
		var room_id: int = int(vent.get("room_id", -1))
		if building.get_room(room_id) == null:
			continue
		result.append(vent)
	return result


func _sum_vent_weights(vents: Array) -> float:
	var total: float = 0.0
	for vent in vents:
		if typeof(vent) != TYPE_DICTIONARY:
			continue
		total += maxf(0.0, float(Dictionary(vent).get("flow_fraction", 1.0)))
	return total


func _resolve_vent_flow_m3_s(vent: Dictionary, total_flow_m3_s: float, total_weight: float) -> float:
	if vent.has("flow_m3_s"):
		return maxf(0.0, float(vent.get("flow_m3_s", 0.0)))
	var weight: float = maxf(0.0, float(vent.get("flow_fraction", 1.0)))
	return total_flow_m3_s * weight / maxf(0.0001, total_weight)


func _vent_height_m(room: RoomModel, vent: Dictionary) -> float:
	if room == null:
		return 0.0
	if vent.has("height_m"):
		return clampf(float(vent.get("height_m", room.height_m * 0.92)), 0.0, room.height_m)
	var fraction: float = clampf(float(vent.get("height_fraction", 0.92)), 0.0, 1.0)
	return room.height_m * fraction


func _estimate_temp_at_height(room: RoomModel, height_m: float, hooks: Dictionary) -> float:
	var estimate_temp_callable: Callable = hooks.get("estimate_temperature_callable", Callable())
	if estimate_temp_callable.is_valid():
		return float(estimate_temp_callable.call(room, height_m))
	return room.temp_upper_c if height_m >= room.thermal_layer_m else room.temp_lower_c


func _effective_hot_layer_height(room: RoomModel, hooks: Dictionary) -> float:
	var effective_hot_layer_callable: Callable = hooks.get("effective_hot_layer_height_callable", Callable())
	if effective_hot_layer_callable.is_valid():
		return clampf(float(effective_hot_layer_callable.call(room)), 0.0, room.height_m)
	return clampf(room.thermal_layer_m, 0.0, room.height_m)


func _sync_touched_rooms(building: BuildingModel, room_ids: Array, hooks: Dictionary, dt: float) -> void:
	var sync_callable: Callable = hooks.get("sync_room_upper_layer_callable", Callable())
	if not sync_callable.is_valid():
		return
	var touched: Array[int] = []
	for raw_id in room_ids:
		var room_id: int = int(raw_id)
		if touched.has(room_id):
			continue
		touched.append(room_id)
		var room: RoomModel = building.get_room(room_id)
		if room != null:
			sync_callable.call(room, dt)


func _collect_vent_room_ids(vents: Array) -> Array:
	var ids: Array = []
	for vent in vents:
		if typeof(vent) != TYPE_DICTIONARY:
			continue
		_append_unique_int(ids, int(Dictionary(vent).get("room_id", -1)))
	return ids


func _append_unique_int(values: Array, value: int) -> void:
	if value < 0:
		return
	if values.has(value):
		return
	values.append(value)
