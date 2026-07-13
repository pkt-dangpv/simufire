extends RefCounted
class_name Phase3ZoneMassSystem

# F3.0: transaccion two-zone en sombra. Este componente nunca escribe RoomModel.

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const EXTERIOR_ID: int = -1

var _snapshots: Dictionary = {}
var _requests: Array[Dictionary] = []
var _request_ids: Dictionary = {}
var _duplicate_owner_count: int = 0
var _results: Dictionary = {}


func reset() -> void:
	_snapshots.clear()
	_requests.clear()
	_request_ids.clear()
	_duplicate_owner_count = 0
	_results.clear()


func begin_step(building) -> void:
	reset()
	if building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		_snapshots[str(room_id)] = _snapshot_room(room)


func make_request(
		request_id: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		gas_mass_kg: float,
		sensible_enthalpy_kj: float,
		o2_kg: float = 0.0,
		species_kg: Dictionary = {}
	) -> Dictionary:
	return {
		"request_id": request_id,
		"cause": cause,
		"source_room_id": source_room_id,
		"destination_room_id": destination_room_id,
		"source_zone": source_zone,
		"destination_zone": destination_zone,
		"gas_mass_kg": maxf(0.0, gas_mass_kg),
		"sensible_enthalpy_kj": maxf(0.0, sensible_enthalpy_kj),
		"o2_kg": maxf(0.0, o2_kg),
		"species_kg": species_kg.duplicate(true),
	}


func add_request(request: Dictionary) -> bool:
	var request_id: String = String(request.get("request_id", ""))
	var cause: String = String(request.get("cause", ""))
	if request_id.is_empty() or cause.is_empty():
		return false
	if _request_ids.has(request_id):
		_duplicate_owner_count += 1
		return false
	_request_ids[request_id] = true
	_requests.append(request.duplicate(true))
	return true


func finalize_step(building) -> void:
	_results.clear()
	var shadow: Dictionary = _snapshots.duplicate(true)
	var rejected_by_room: Dictionary = {}
	var rejected_combustion_o2_by_room: Dictionary = {}
	for request in _requests:
		_apply_request(shadow, request, rejected_by_room, rejected_combustion_o2_by_room)
	if building == null:
		return
	for room_key in shadow.keys():
		var room_id: int = int(room_key)
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		var state: Dictionary = shadow[room_key]
		var legacy_mass_kg: float = room.zone_total_mass_kg()
		var legacy_energy_kj: float = room.zone_total_energy_kj()
		var mass_residual_kg: float = _state_mass(state) - legacy_mass_kg
		var energy_residual_kj: float = _state_energy(state) - legacy_energy_kj
		var upper_mass_residual_kg: float = float(state.get("upper_gas_kg", 0.0)) \
				- maxf(0.0, room.upper_gas_kg)
		var lower_mass_residual_kg: float = float(state.get("lower_gas_kg", 0.0)) \
				- maxf(0.0, room.lower_gas_kg)
		var upper_energy_residual_kj: float = float(state.get("upper_energy_kj", 0.0)) \
				- maxf(0.0, room.upper_energy_kj)
		var lower_energy_residual_kj: float = float(state.get("lower_energy_kj", 0.0)) \
				- maxf(0.0, room.lower_energy_kj)
		_results[room_key] = {
			"phase3_shadow_upper_gas_kg": float(state.get("upper_gas_kg", 0.0)),
			"phase3_shadow_lower_gas_kg": float(state.get("lower_gas_kg", 0.0)),
			"phase3_shadow_upper_energy_kj": float(state.get("upper_energy_kj", 0.0)),
			"phase3_shadow_lower_energy_kj": float(state.get("lower_energy_kj", 0.0)),
			"phase3_shadow_mass_residual_kg": mass_residual_kg,
			"phase3_shadow_energy_residual_kj": energy_residual_kj,
			"phase3_shadow_upper_mass_residual_kg": upper_mass_residual_kg,
			"phase3_shadow_lower_mass_residual_kg": lower_mass_residual_kg,
			"phase3_shadow_upper_energy_residual_kj": upper_energy_residual_kj,
			"phase3_shadow_lower_energy_residual_kj": lower_energy_residual_kj,
			"phase3_shadow_request_count": _count_room_requests(room_id),
			"phase3_shadow_plume_mass_request_kg": _sum_room_cause_mass(
				room_id, "plume_entrainment"
			),
			"phase3_shadow_combustion_energy_request_kj": _sum_room_cause_energy(
				room_id, "combustion_convective_heat"
			),
			"phase3_shadow_combustion_o2_request_kg": _sum_room_cause_prefix_o2(
				room_id, "combustion_o2_"
			),
			"phase3_shadow_combustion_o2_rejected_kg": float(
				rejected_combustion_o2_by_room.get(room_key, 0.0)
			),
			"phase3_shadow_combustion_co_request_kg": _sum_room_cause_species(
				room_id, "combustion_species_source", "co"
			),
			"phase3_shadow_combustion_co2_request_kg": _sum_room_cause_species(
				room_id, "combustion_species_source", "co2"
			),
			"phase3_shadow_combustion_hcn_request_kg": _sum_room_cause_species(
				room_id, "combustion_species_source", "hcn"
			),
			# Combustion species originate in the exterior reservoir, so inventory
			# limiting cannot reject them. Keep the field explicit for future caps.
			"phase3_shadow_combustion_species_rejected_kg": 0.0,
			# Bit mask: energy=1, O2=2, species=4. Bulk O2 remains unowned.
			"phase3_shadow_combustion_owned_mask": _combustion_owned_mask(room_id),
			"phase3_shadow_owned_cause_count": _count_room_causes(room_id),
			"phase3_shadow_rejected_mass_kg": float(rejected_by_room.get(room_key, 0.0)),
			"phase3_shadow_duplicate_owner_flag": 1.0 if _duplicate_owner_count > 0 else 0.0,
			"phase3_shadow_zero_o2_flame_flag": 1.0 \
					if room.hrr_kw > 0.5 and (
						room.fire_o2_ref < room.fire_o2_min_ref or room.o2_upper < 0.05
					) else 0.0,
			"phase3_shadow_needs_flux_owner_flag": 1.0 \
					if absf(mass_residual_kg) > 1.0e-6 or absf(energy_residual_kj) > 1.0e-4 else 0.0,
		}


func get_results() -> Dictionary:
	return _results.duplicate(true)


func get_request_count() -> int:
	return _requests.size()


func _snapshot_room(room: RoomModel) -> Dictionary:
	return {
		"upper_gas_kg": maxf(0.0, room.upper_gas_kg),
		"lower_gas_kg": maxf(0.0, room.lower_gas_kg),
		"upper_energy_kj": maxf(0.0, room.upper_energy_kj),
		"lower_energy_kj": maxf(0.0, room.lower_energy_kj),
		"upper_o2_kg": maxf(0.0, room.upper_gas_kg * room.o2_upper),
		"lower_o2_kg": maxf(0.0, room.lower_gas_kg * room.o2_lower),
		"upper_species_kg": {
			"co": maxf(0.0, room.co_upper_kg),
			"co2": maxf(0.0, room.co2_upper_kg),
			"hcn": maxf(0.0, room.hcn_upper_kg),
		},
		"lower_species_kg": {
			"co": maxf(0.0, room.co_kg - room.co_upper_kg),
			"co2": maxf(0.0, room.co2_kg - room.co2_upper_kg),
			"hcn": maxf(0.0, room.hcn_kg - room.hcn_upper_kg),
		},
	}


func _apply_request(
		shadow: Dictionary,
		request: Dictionary,
		rejected_by_room: Dictionary,
		rejected_combustion_o2_by_room: Dictionary
	) -> void:
	var source_id: int = int(request.get("source_room_id", EXTERIOR_ID))
	var destination_id: int = int(request.get("destination_room_id", EXTERIOR_ID))
	var source_zone: String = String(request.get("source_zone", ZONE_UPPER))
	var destination_zone: String = String(request.get("destination_zone", ZONE_UPPER))
	var requested_mass_kg: float = maxf(0.0, float(request.get("gas_mass_kg", 0.0)))
	var accepted_fraction: float = 1.0
	if source_id != EXTERIOR_ID:
		var source_key: String = str(source_id)
		var source: Dictionary = shadow.get(source_key, {})
		var available_kg: float = float(source.get(source_zone + "_gas_kg", 0.0))
		if requested_mass_kg > 0.0:
			accepted_fraction = minf(1.0, available_kg / requested_mass_kg)
		var requested_o2_kg: float = maxf(0.0, float(request.get("o2_kg", 0.0)))
		if requested_o2_kg > 0.0:
			accepted_fraction = minf(accepted_fraction,
					float(source.get(source_zone + "_o2_kg", 0.0)) / requested_o2_kg)
		var requested_species: Dictionary = request.get("species_kg", {})
		var source_species: Dictionary = source.get(source_zone + "_species_kg", {})
		for species_name in requested_species.keys():
			var requested_species_kg: float = maxf(0.0, float(requested_species[species_name]))
			if requested_species_kg > 0.0:
				accepted_fraction = minf(accepted_fraction,
						float(source_species.get(species_name, 0.0)) / requested_species_kg)
		accepted_fraction = clampf(accepted_fraction, 0.0, 1.0)
		var accepted_mass_kg: float = requested_mass_kg * accepted_fraction
		source[source_zone + "_gas_kg"] = maxf(0.0, available_kg - accepted_mass_kg)
		source[source_zone + "_energy_kj"] = maxf(0.0,
			float(source.get(source_zone + "_energy_kj", 0.0))
			- float(request.get("sensible_enthalpy_kj", 0.0)) * accepted_fraction)
		source[source_zone + "_o2_kg"] = maxf(0.0,
			float(source.get(source_zone + "_o2_kg", 0.0)) - requested_o2_kg * accepted_fraction)
		for species_name in requested_species.keys():
			source_species[species_name] = maxf(0.0,
					float(source_species.get(species_name, 0.0))
					- float(requested_species[species_name]) * accepted_fraction)
		source[source_zone + "_species_kg"] = source_species
		shadow[source_key] = source
		if accepted_fraction < 1.0:
			rejected_by_room[source_key] = float(rejected_by_room.get(source_key, 0.0)) \
					+ requested_mass_kg * (1.0 - accepted_fraction)
			if String(request.get("cause", "")).begins_with("combustion_o2_"):
				rejected_combustion_o2_by_room[source_key] = float(
					rejected_combustion_o2_by_room.get(source_key, 0.0)
				) + requested_o2_kg * (1.0 - accepted_fraction)
	if destination_id != EXTERIOR_ID:
		var destination_key: String = str(destination_id)
		var destination: Dictionary = shadow.get(destination_key, {})
		var moved_mass_kg: float = requested_mass_kg * accepted_fraction
		destination[destination_zone + "_gas_kg"] = \
				float(destination.get(destination_zone + "_gas_kg", 0.0)) + moved_mass_kg
		destination[destination_zone + "_energy_kj"] = \
				float(destination.get(destination_zone + "_energy_kj", 0.0)) \
				+ float(request.get("sensible_enthalpy_kj", 0.0)) * accepted_fraction
		destination[destination_zone + "_o2_kg"] = \
				float(destination.get(destination_zone + "_o2_kg", 0.0)) \
				+ float(request.get("o2_kg", 0.0)) * accepted_fraction
		var destination_species: Dictionary = destination.get(destination_zone + "_species_kg", {})
		var moved_species: Dictionary = request.get("species_kg", {})
		for species_name in moved_species.keys():
			destination_species[species_name] = float(destination_species.get(species_name, 0.0)) \
					+ maxf(0.0, float(moved_species[species_name])) * accepted_fraction
		destination[destination_zone + "_species_kg"] = destination_species
		shadow[destination_key] = destination


func _count_room_requests(room_id: int) -> int:
	var count: int = 0
	for request in _requests:
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			count += 1
	return count


func _count_room_causes(room_id: int) -> int:
	var causes: Dictionary = {}
	for request in _requests:
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			causes[String(request.get("cause", ""))] = true
	return causes.size()


func _room_has_cause(room_id: int, cause: String) -> bool:
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			return true
	return false


func _room_has_cause_prefix(room_id: int, cause_prefix: String) -> bool:
	for request in _requests:
		if not String(request.get("cause", "")).begins_with(cause_prefix):
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			return true
	return false


func _combustion_owned_mask(room_id: int) -> float:
	var mask: int = 0
	if _room_has_cause(room_id, "combustion_convective_heat"):
		mask |= 1
	if _room_has_cause_prefix(room_id, "combustion_o2_"):
		mask |= 2
	if _room_has_cause(room_id, "combustion_species_source"):
		mask |= 4
	return float(mask)


func _sum_room_cause_mass(room_id: int, cause: String) -> float:
	var total_kg: float = 0.0
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			total_kg += maxf(0.0, float(request.get("gas_mass_kg", 0.0)))
	return total_kg


func _sum_room_cause_energy(room_id: int, cause: String) -> float:
	var total_kj: float = 0.0
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			total_kj += maxf(0.0, float(request.get("sensible_enthalpy_kj", 0.0)))
	return total_kj


func _sum_room_cause_prefix_o2(room_id: int, cause_prefix: String) -> float:
	var total_kg: float = 0.0
	for request in _requests:
		if not String(request.get("cause", "")).begins_with(cause_prefix):
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) == room_id \
				or int(request.get("destination_room_id", EXTERIOR_ID)) == room_id:
			total_kg += maxf(0.0, float(request.get("o2_kg", 0.0)))
	return total_kg


func _sum_room_cause_species(room_id: int, cause: String, species_name: String) -> float:
	var total_kg: float = 0.0
	for request in _requests:
		if String(request.get("cause", "")) != cause:
			continue
		if int(request.get("source_room_id", EXTERIOR_ID)) != room_id \
				and int(request.get("destination_room_id", EXTERIOR_ID)) != room_id:
			continue
		var species: Dictionary = request.get("species_kg", {})
		total_kg += maxf(0.0, float(species.get(species_name, 0.0)))
	return total_kg


func _state_mass(state: Dictionary) -> float:
	return float(state.get("upper_gas_kg", 0.0)) + float(state.get("lower_gas_kg", 0.0))


func _state_energy(state: Dictionary) -> float:
	return float(state.get("upper_energy_kj", 0.0)) + float(state.get("lower_energy_kj", 0.0))
