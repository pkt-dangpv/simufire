extends RefCounted

## Compact internal storage for the passive per-call projection trace.
## External readers still receive the historical Dictionary schema through
## `to_dictionary`; same-tick diagnostic consumers read these records directly.

enum Field {
	CALL_INDEX,
	CAUSE,
	ROOM_ID,
	AMBIENT_C,
	PRE_UPPER_GAS_KG,
	PRE_LOWER_GAS_KG,
	PRE_UPPER_ENERGY_KJ,
	PRE_LOWER_ENERGY_KJ,
	PRE_THERMAL_LAYER_M,
	PRE_TEMP_UPPER_C,
	PRE_TEMP_LOWER_C,
	ENSURED_UPPER_GAS_KG,
	ENSURED_LOWER_GAS_KG,
	ENSURED_UPPER_ENERGY_KJ,
	ENSURED_LOWER_ENERGY_KJ,
	ENSURED_THERMAL_LAYER_M,
	ENSURED_TEMP_UPPER_C,
	ENSURED_TEMP_LOWER_C,
	PRE_GEOMETRY_UPPER_GAS_KG,
	PRE_GEOMETRY_LOWER_GAS_KG,
	PRE_GEOMETRY_UPPER_ENERGY_KJ,
	PRE_GEOMETRY_LOWER_ENERGY_KJ,
	PRE_GEOMETRY_THERMAL_LAYER_M,
	PRE_GEOMETRY_TEMP_UPPER_C,
	PRE_GEOMETRY_TEMP_LOWER_C,
	POST_UPPER_GAS_KG,
	POST_LOWER_GAS_KG,
	POST_UPPER_ENERGY_KJ,
	POST_LOWER_ENERGY_KJ,
	POST_THERMAL_LAYER_M,
	POST_TEMP_UPPER_C,
	POST_TEMP_LOWER_C,
	UPPER_DENSITY_KG_M3,
	LOWER_DENSITY_KG_M3,
	MAX_UPPER_MASS_KG,
	UPPER_MASS_BEFORE_CAP_KG,
	UPPER_ENERGY_BEFORE_CAP_KJ,
	UPPER_VOLUME_M3,
	LOWER_VOLUME_M3,
	TARGET_LOWER_MASS_KG,
	LOWER_MASS_BEFORE_PROJECTION_KG,
	LOWER_ENERGY_BEFORE_PROJECTION_KJ,
	ENSURE_MASS_DELTA_KG,
	ENSURE_ENERGY_DELTA_KJ,
	TEMPERATURE_PROJECTION_ENERGY_DELTA_KJ,
	UPPER_CAP_MASS_DELTA_KG,
	UPPER_CAP_ENERGY_DELTA_KJ,
	LOWER_PROJECTION_MASS_DELTA_KG,
	LOWER_PROJECTION_ENERGY_DELTA_KJ,
	TOTAL_MASS_DELTA_KG,
	TOTAL_ENERGY_DELTA_KJ,
	SIZE,
}

const STATE_WIDTH: int = 7


static func new_record() -> Array:
	var record: Array = []
	record.resize(Field.SIZE)
	return record


static func capture_state(record: Array, first_field: int, room) -> void:
	record[first_field] = room.upper_gas_kg
	record[first_field + 1] = room.lower_gas_kg
	record[first_field + 2] = room.upper_energy_kj
	record[first_field + 3] = room.lower_energy_kj
	record[first_field + 4] = room.thermal_layer_m
	record[first_field + 5] = room.temp_upper_c
	record[first_field + 6] = room.temp_lower_c


static func state_dictionary(record: Array, first_field: int) -> Dictionary:
	return {
		"upper_gas_kg": record[first_field],
		"lower_gas_kg": record[first_field + 1],
		"upper_energy_kj": record[first_field + 2],
		"lower_energy_kj": record[first_field + 3],
		"thermal_layer_m": record[first_field + 4],
		"temp_upper_c": record[first_field + 5],
		"temp_lower_c": record[first_field + 6],
	}


static func _capture_dictionary_state(
	record: Array, first_field: int, state: Dictionary
) -> void:
	record[first_field] = float(state.get("upper_gas_kg", 0.0))
	record[first_field + 1] = float(state.get("lower_gas_kg", 0.0))
	record[first_field + 2] = float(state.get("upper_energy_kj", 0.0))
	record[first_field + 3] = float(state.get("lower_energy_kj", 0.0))
	record[first_field + 4] = float(state.get("thermal_layer_m", 0.0))
	record[first_field + 5] = float(state.get("temp_upper_c", 0.0))
	record[first_field + 6] = float(state.get("temp_lower_c", 0.0))


static func from_dictionary(event: Dictionary) -> Array:
	var record: Array = new_record()
	record[Field.CALL_INDEX] = int(event.get("call_index", 0))
	record[Field.CAUSE] = String(event.get("cause", "unspecified"))
	record[Field.ROOM_ID] = int(event.get("room_id", -1))
	record[Field.AMBIENT_C] = float(event.get("ambient_c", 0.0))
	_capture_dictionary_state(record, Field.PRE_UPPER_GAS_KG, event.get("pre", {}))
	_capture_dictionary_state(
		record, Field.ENSURED_UPPER_GAS_KG, event.get("ensured", {}))
	_capture_dictionary_state(
		record, Field.PRE_GEOMETRY_UPPER_GAS_KG, event.get("pre_geometry", {}))
	_capture_dictionary_state(record, Field.POST_UPPER_GAS_KG, event.get("post", {}))
	for item in [
		[Field.UPPER_DENSITY_KG_M3, "upper_density_kg_m3"],
		[Field.LOWER_DENSITY_KG_M3, "lower_density_kg_m3"],
		[Field.MAX_UPPER_MASS_KG, "max_upper_mass_kg"],
		[Field.UPPER_MASS_BEFORE_CAP_KG, "upper_mass_before_cap_kg"],
		[Field.UPPER_ENERGY_BEFORE_CAP_KJ, "upper_energy_before_cap_kj"],
		[Field.UPPER_VOLUME_M3, "upper_volume_m3"],
		[Field.LOWER_VOLUME_M3, "lower_volume_m3"],
		[Field.TARGET_LOWER_MASS_KG, "target_lower_mass_kg"],
		[Field.LOWER_MASS_BEFORE_PROJECTION_KG, "lower_mass_before_projection_kg"],
		[Field.LOWER_ENERGY_BEFORE_PROJECTION_KJ, "lower_energy_before_projection_kj"],
		[Field.ENSURE_MASS_DELTA_KG, "ensure_mass_delta_kg"],
		[Field.ENSURE_ENERGY_DELTA_KJ, "ensure_energy_delta_kj"],
		[Field.TEMPERATURE_PROJECTION_ENERGY_DELTA_KJ,
			"temperature_projection_energy_delta_kj"],
		[Field.UPPER_CAP_MASS_DELTA_KG, "upper_cap_mass_delta_kg"],
		[Field.UPPER_CAP_ENERGY_DELTA_KJ, "upper_cap_energy_delta_kj"],
		[Field.LOWER_PROJECTION_MASS_DELTA_KG, "lower_projection_mass_delta_kg"],
		[Field.LOWER_PROJECTION_ENERGY_DELTA_KJ, "lower_projection_energy_delta_kj"],
		[Field.TOTAL_MASS_DELTA_KG, "total_mass_delta_kg"],
		[Field.TOTAL_ENERGY_DELTA_KJ, "total_energy_delta_kj"],
	]:
		record[int(item[0])] = float(event.get(String(item[1]), 0.0))
	return record


static func to_dictionary(record: Array) -> Dictionary:
	return {
		"call_index": record[Field.CALL_INDEX],
		"cause": record[Field.CAUSE],
		"room_id": record[Field.ROOM_ID],
		"ambient_c": record[Field.AMBIENT_C],
		"pre": state_dictionary(record, Field.PRE_UPPER_GAS_KG),
		"ensured": state_dictionary(record, Field.ENSURED_UPPER_GAS_KG),
		"pre_geometry": state_dictionary(record, Field.PRE_GEOMETRY_UPPER_GAS_KG),
		"post": state_dictionary(record, Field.POST_UPPER_GAS_KG),
		"upper_density_kg_m3": record[Field.UPPER_DENSITY_KG_M3],
		"lower_density_kg_m3": record[Field.LOWER_DENSITY_KG_M3],
		"max_upper_mass_kg": record[Field.MAX_UPPER_MASS_KG],
		"upper_mass_before_cap_kg": record[Field.UPPER_MASS_BEFORE_CAP_KG],
		"upper_energy_before_cap_kj": record[Field.UPPER_ENERGY_BEFORE_CAP_KJ],
		"upper_volume_m3": record[Field.UPPER_VOLUME_M3],
		"lower_volume_m3": record[Field.LOWER_VOLUME_M3],
		"target_lower_mass_kg": record[Field.TARGET_LOWER_MASS_KG],
		"lower_mass_before_projection_kg": record[Field.LOWER_MASS_BEFORE_PROJECTION_KG],
		"lower_energy_before_projection_kj": record[Field.LOWER_ENERGY_BEFORE_PROJECTION_KJ],
		"ensure_mass_delta_kg": record[Field.ENSURE_MASS_DELTA_KG],
		"ensure_energy_delta_kj": record[Field.ENSURE_ENERGY_DELTA_KJ],
		"temperature_projection_energy_delta_kj": \
			record[Field.TEMPERATURE_PROJECTION_ENERGY_DELTA_KJ],
		"upper_cap_mass_delta_kg": record[Field.UPPER_CAP_MASS_DELTA_KG],
		"upper_cap_energy_delta_kj": record[Field.UPPER_CAP_ENERGY_DELTA_KJ],
		"lower_projection_mass_delta_kg": record[Field.LOWER_PROJECTION_MASS_DELTA_KG],
		"lower_projection_energy_delta_kj": record[Field.LOWER_PROJECTION_ENERGY_DELTA_KJ],
		"total_mass_delta_kg": record[Field.TOTAL_MASS_DELTA_KG],
		"total_energy_delta_kj": record[Field.TOTAL_ENERGY_DELTA_KJ],
	}
