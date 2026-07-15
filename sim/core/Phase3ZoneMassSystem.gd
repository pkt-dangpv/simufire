extends RefCounted
class_name Phase3ZoneMassSystem

# F3.0: transaccion two-zone en sombra. Este componente nunca escribe RoomModel.

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const EXTERIOR_ID: int = -1
const TRANSIT_SPECIES: Array[String] = ["co", "co2", "hcn"]

var _snapshots: Dictionary = {}
var _requests: Array[Dictionary] = []
var _request_ids: Dictionary = {}
var _duplicate_owner_count: int = 0
var _results: Dictionary = {}
var _species_transit_reservoir: Dictionary = {}
var _species_transit_created_kg: Dictionary = {}
var _species_transit_delivered_kg: Dictionary = {}
var _species_transit_refunded_kg: Dictionary = {}
var _species_transit_cancelled_kg: Dictionary = {}
var _species_transit_orphan_delivery_count: int = 0
var _species_transit_duplicate_id_count: int = 0
var _species_transit_negative_balance_count: int = 0
var _immediate_background_species_kg: Dictionary = {}
var _immediate_counterflow_species_kg: Dictionary = {}
var _immediate_transfer_count: int = 0
var _immediate_rejected_kg_total: float = 0.0
var _immediate_debited_species_kg_step: Dictionary = {}
var _immediate_credited_species_kg_step: Dictionary = {}


func reset() -> void:
	_reset_step_state()
	_species_transit_reservoir.clear()
	_species_transit_created_kg.clear()
	_species_transit_delivered_kg.clear()
	_species_transit_refunded_kg.clear()
	_species_transit_cancelled_kg.clear()
	_species_transit_orphan_delivery_count = 0
	_species_transit_duplicate_id_count = 0
	_species_transit_negative_balance_count = 0
	_immediate_background_species_kg.clear()
	_immediate_counterflow_species_kg.clear()
	_immediate_transfer_count = 0
	_immediate_rejected_kg_total = 0.0


func _reset_step_state() -> void:
	_snapshots.clear()
	_requests.clear()
	_request_ids.clear()
	_duplicate_owner_count = 0
	_results.clear()
	_immediate_debited_species_kg_step.clear()
	_immediate_credited_species_kg_step.clear()


func begin_step(building) -> void:
	_reset_step_state()
	if building == null:
		return
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue
		_snapshots[str(room_id)] = _snapshot_room(room)


func apply_species_transit_event(event: Dictionary) -> void:
	var event_name: String = String(event.get("event", ""))
	var parcel_id: String = String(event.get("parcel_id", ""))
	if parcel_id.is_empty():
		_species_transit_orphan_delivery_count += 1
		return
	match event_name:
		"created":
			if _species_transit_reservoir.has(parcel_id):
				_species_transit_duplicate_id_count += 1
				return
			var created_species: Dictionary = _transit_species(event.get("species_kg", {}))
			var created_upper_species: Dictionary = _bounded_upper_transit_species(
				event.get("upper_species_kg", {}), created_species
			)
			_species_transit_reservoir[parcel_id] = {
				"source_room_id": int(event.get("source_room_id", EXTERIOR_ID)),
				"destination_room_id": int(event.get("destination_room_id", EXTERIOR_ID)),
				"species_kg": created_species.duplicate(true),
				"upper_species_kg": created_upper_species.duplicate(true),
			}
			_add_transit_species(_species_transit_created_kg, created_species)
			_add_transit_zone_requests(
				parcel_id + ":carve",
				"delayed_species_parcel_carve",
				int(event.get("source_room_id", EXTERIOR_ID)),
				EXTERIOR_ID,
				created_species,
				created_upper_species
			)
		"resolved":
			var delivered_species: Dictionary = _transit_species(
				event.get("delivered_species_kg", {})
			)
			var refunded_species: Dictionary = _transit_species(
				event.get("refunded_species_kg", {})
			)
			var delivered_upper_species: Dictionary = _bounded_upper_transit_species(
				event.get("delivered_upper_species_kg", {}), delivered_species
			)
			var refunded_upper_species: Dictionary = _bounded_upper_transit_species(
				event.get("refunded_upper_species_kg", {}), refunded_species
			)
			_add_transit_species(_species_transit_delivered_kg, delivered_species)
			_add_transit_species(_species_transit_refunded_kg, refunded_species)
			if not _species_transit_reservoir.has(parcel_id):
				_species_transit_orphan_delivery_count += 1
				return
			var stored: Dictionary = _species_transit_reservoir[parcel_id]
			var stored_species: Dictionary = stored.get("species_kg", {})
			for species_name in TRANSIT_SPECIES:
				var resolved_kg: float = float(delivered_species.get(species_name, 0.0)) \
						+ float(refunded_species.get(species_name, 0.0))
				if resolved_kg > float(stored_species.get(species_name, 0.0)) + 1.0e-9:
					_species_transit_negative_balance_count += 1
			_add_transit_zone_requests(
				parcel_id + ":delivery",
				"delayed_species_parcel_delivery",
				EXTERIOR_ID,
				int(event.get("destination_room_id", EXTERIOR_ID)),
				delivered_species,
				delivered_upper_species
			)
			_add_transit_zone_requests(
				parcel_id + ":refund",
				"delayed_species_parcel_refund",
				EXTERIOR_ID,
				int(event.get("source_room_id", EXTERIOR_ID)),
				refunded_species,
				refunded_upper_species
			)
			_species_transit_reservoir.erase(parcel_id)
		"cancelled":
			var cancelled_species: Dictionary = _transit_species(event.get("species_kg", {}))
			_add_transit_species(_species_transit_cancelled_kg, cancelled_species)
			if not _species_transit_reservoir.has(parcel_id):
				_species_transit_orphan_delivery_count += 1
				return
			var stored_cancelled: Dictionary = _species_transit_reservoir[parcel_id]
			var stored_cancelled_species: Dictionary = stored_cancelled.get("species_kg", {})
			for species_name in TRANSIT_SPECIES:
				if float(cancelled_species.get(species_name, 0.0)) \
						> float(stored_cancelled_species.get(species_name, 0.0)) + 1.0e-9:
					_species_transit_negative_balance_count += 1
			_species_transit_reservoir.erase(parcel_id)
		_:
			_species_transit_orphan_delivery_count += 1


func apply_immediate_species_event(event: Dictionary) -> void:
	var request_id: String = String(event.get("request_id", ""))
	var cause: String = String(event.get("cause", ""))
	if request_id.is_empty() or not _is_immediate_species_cause(cause):
		return
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	if _sum_transit_species(total_species) <= 0.0:
		return
	var upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("upper_species_kg", {}), total_species
	)
	if cause == "background_species_exchange":
		_add_transit_species(_immediate_background_species_kg, total_species)
	else:
		_add_transit_species(_immediate_counterflow_species_kg, total_species)
	_immediate_transfer_count += 1
	_add_transit_zone_requests(
		request_id,
		cause,
		int(event.get("source_room_id", EXTERIOR_ID)),
		int(event.get("destination_room_id", EXTERIOR_ID)),
		total_species,
		upper_species
	)


func _is_immediate_species_cause(cause: String) -> bool:
	return cause == "background_species_exchange" \
			or cause == "doorway_species_counterflow"


func _transit_species(raw_species) -> Dictionary:
	var species: Dictionary = raw_species if typeof(raw_species) == TYPE_DICTIONARY else {}
	var filtered: Dictionary = {}
	for species_name in TRANSIT_SPECIES:
		filtered[species_name] = maxf(0.0, float(species.get(species_name, 0.0)))
	return filtered


func _bounded_upper_transit_species(raw_upper, total_species: Dictionary) -> Dictionary:
	var upper: Dictionary = _transit_species(raw_upper)
	for species_name in TRANSIT_SPECIES:
		upper[species_name] = minf(
			float(upper.get(species_name, 0.0)),
			float(total_species.get(species_name, 0.0))
		)
	return upper


func _lower_transit_species(total_species: Dictionary, upper_species: Dictionary) -> Dictionary:
	var lower: Dictionary = {}
	for species_name in TRANSIT_SPECIES:
		lower[species_name] = maxf(
			0.0,
			float(total_species.get(species_name, 0.0))
					- float(upper_species.get(species_name, 0.0))
		)
	return lower


func _add_transit_zone_requests(
	request_id_prefix: String,
	cause: String,
	source_room_id: int,
	destination_room_id: int,
	total_species: Dictionary,
	upper_species: Dictionary
	) -> void:
	var lower_species: Dictionary = _lower_transit_species(total_species, upper_species)
	_add_transit_zone_request(
		request_id_prefix + ":upper",
		cause,
		source_room_id,
		destination_room_id,
		ZONE_UPPER,
		upper_species
	)
	_add_transit_zone_request(
		request_id_prefix + ":lower",
		cause,
		source_room_id,
		destination_room_id,
		ZONE_LOWER,
		lower_species
	)


func _add_transit_zone_request(
	request_id: String,
	cause: String,
	source_room_id: int,
	destination_room_id: int,
	zone_name: String,
	species: Dictionary
	) -> void:
	if _sum_transit_species(species) <= 0.0:
		return
	add_request(make_request(
		request_id,
		cause,
		source_room_id,
		destination_room_id,
		zone_name,
		zone_name,
		0.0,
		0.0,
		0.0,
		species
	))


func _add_transit_species(target: Dictionary, species: Dictionary) -> void:
	for species_name in TRANSIT_SPECIES:
		target[species_name] = float(target.get(species_name, 0.0)) \
				+ float(species.get(species_name, 0.0))


func _sum_transit_species(species: Dictionary) -> float:
	var total_kg: float = 0.0
	for species_name in TRANSIT_SPECIES:
		total_kg += float(species.get(species_name, 0.0))
	return total_kg


func _inflight_transit_species() -> Dictionary:
	var inflight: Dictionary = {}
	for raw_record in _species_transit_reservoir.values():
		var record: Dictionary = raw_record
		_add_transit_species(inflight, record.get("species_kg", {}))
	return inflight


func _species_transit_conservation_residual_kg() -> float:
	return _sum_transit_species(_species_transit_created_kg) \
			- _sum_transit_species(_species_transit_delivered_kg) \
			- _sum_transit_species(_species_transit_refunded_kg) \
			- _sum_transit_species(_species_transit_cancelled_kg) \
			- _sum_transit_species(_inflight_transit_species())


func _species_transit_conservation_residual_for(species_name: String) -> float:
	var inflight: Dictionary = _inflight_transit_species()
	return float(_species_transit_created_kg.get(species_name, 0.0)) \
			- float(_species_transit_delivered_kg.get(species_name, 0.0)) \
			- float(_species_transit_refunded_kg.get(species_name, 0.0)) \
			- float(_species_transit_cancelled_kg.get(species_name, 0.0)) \
			- float(inflight.get(species_name, 0.0))


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
	var rejected_doorway_species_by_room: Dictionary = {}
	var rejected_transit_species_by_room: Dictionary = {}
	var rejected_immediate_species_by_room: Dictionary = {}
	for request in _requests:
		_apply_request(
			shadow,
			request,
			rejected_by_room,
			rejected_combustion_o2_by_room,
			rejected_doorway_species_by_room,
			rejected_transit_species_by_room,
			rejected_immediate_species_by_room
		)
	if building == null:
		return
	var inflight_transit_species: Dictionary = _inflight_transit_species()
	var transit_created_total_kg: float = _sum_transit_species(_species_transit_created_kg)
	var transit_delivered_total_kg: float = _sum_transit_species(_species_transit_delivered_kg)
	var transit_refunded_total_kg: float = _sum_transit_species(_species_transit_refunded_kg)
	var transit_cancelled_total_kg: float = _sum_transit_species(_species_transit_cancelled_kg)
	var transit_residual_kg: float = _species_transit_conservation_residual_kg()
	var immediate_co_residual_kg: float = float(
		_immediate_debited_species_kg_step.get("co", 0.0)
	) - float(_immediate_credited_species_kg_step.get("co", 0.0))
	var immediate_co2_residual_kg: float = float(
		_immediate_debited_species_kg_step.get("co2", 0.0)
	) - float(_immediate_credited_species_kg_step.get("co2", 0.0))
	var immediate_hcn_residual_kg: float = float(
		_immediate_debited_species_kg_step.get("hcn", 0.0)
	) - float(_immediate_credited_species_kg_step.get("hcn", 0.0))
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
			"phase3_shadow_doorway_co_request_kg": _sum_room_cause_species(
				room_id, "doorway_species_direct", "co"
			),
			"phase3_shadow_doorway_co2_request_kg": _sum_room_cause_species(
				room_id, "doorway_species_direct", "co2"
			),
			"phase3_shadow_doorway_hcn_request_kg": _sum_room_cause_species(
				room_id, "doorway_species_direct", "hcn"
			),
			"phase3_shadow_doorway_species_rejected_kg": float(
				rejected_doorway_species_by_room.get(room_key, 0.0)
			),
			"phase3_shadow_background_co_kg_total": float(
				_immediate_background_species_kg.get("co", 0.0)
			),
			"phase3_shadow_background_co2_kg_total": float(
				_immediate_background_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_background_hcn_kg_total": float(
				_immediate_background_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_counterflow_co_kg_total": float(
				_immediate_counterflow_species_kg.get("co", 0.0)
			),
			"phase3_shadow_counterflow_co2_kg_total": float(
				_immediate_counterflow_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_counterflow_hcn_kg_total": float(
				_immediate_counterflow_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_immediate_transfer_count": float(_immediate_transfer_count),
			"phase3_shadow_immediate_rejected_kg_total": _immediate_rejected_kg_total,
			"phase3_shadow_immediate_co_residual_kg": immediate_co_residual_kg,
			"phase3_shadow_immediate_co2_residual_kg": immediate_co2_residual_kg,
			"phase3_shadow_immediate_hcn_residual_kg": immediate_hcn_residual_kg,
			"phase3_shadow_species_inflight_co_kg": float(
				inflight_transit_species.get("co", 0.0)
			),
			"phase3_shadow_species_inflight_co2_kg": float(
				inflight_transit_species.get("co2", 0.0)
			),
			"phase3_shadow_species_inflight_hcn_kg": float(
				inflight_transit_species.get("hcn", 0.0)
			),
			"phase3_shadow_species_created_kg_total": transit_created_total_kg,
			"phase3_shadow_species_delivered_kg_total": transit_delivered_total_kg,
			"phase3_shadow_species_refunded_kg_total": transit_refunded_total_kg,
			"phase3_shadow_species_cancelled_kg_total": transit_cancelled_total_kg,
			"phase3_shadow_species_active_parcel_count": float(
				_species_transit_reservoir.size()
			),
			"phase3_shadow_species_orphan_delivery_count": float(
				_species_transit_orphan_delivery_count
			),
			"phase3_shadow_species_duplicate_id_count": float(
				_species_transit_duplicate_id_count
			),
			"phase3_shadow_species_negative_balance_count": float(
				_species_transit_negative_balance_count
			),
			"phase3_shadow_species_conservation_residual_kg": transit_residual_kg,
			"phase3_shadow_species_conservation_residual_co_kg": \
				_species_transit_conservation_residual_for("co"),
			"phase3_shadow_species_conservation_residual_co2_kg": \
				_species_transit_conservation_residual_for("co2"),
			"phase3_shadow_species_conservation_residual_hcn_kg": \
				_species_transit_conservation_residual_for("hcn"),
			"phase3_shadow_species_transit_rejected_kg": float(
				rejected_transit_species_by_room.get(room_key, 0.0)
			),
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
		rejected_combustion_o2_by_room: Dictionary,
		rejected_doorway_species_by_room: Dictionary,
		rejected_transit_species_by_room: Dictionary,
		rejected_immediate_species_by_room: Dictionary
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
			if String(request.get("cause", "")) == "doorway_species_direct":
				var rejected_species_kg: float = 0.0
				for species_name in requested_species.keys():
					rejected_species_kg += maxf(
						0.0, float(requested_species[species_name])
					) * (1.0 - accepted_fraction)
				rejected_doorway_species_by_room[source_key] = float(
					rejected_doorway_species_by_room.get(source_key, 0.0)
				) + rejected_species_kg
			if String(request.get("cause", "")).begins_with("delayed_species_parcel_"):
				var rejected_transit_species_kg: float = 0.0
				for species_name in requested_species.keys():
					rejected_transit_species_kg += maxf(
						0.0, float(requested_species[species_name])
					) * (1.0 - accepted_fraction)
				rejected_transit_species_by_room[source_key] = float(
					rejected_transit_species_by_room.get(source_key, 0.0)
				) + rejected_transit_species_kg
			if _is_immediate_species_cause(String(request.get("cause", ""))):
				var rejected_immediate_kg: float = 0.0
				for species_name in requested_species.keys():
					rejected_immediate_kg += maxf(
						0.0, float(requested_species[species_name])
					) * (1.0 - accepted_fraction)
				rejected_immediate_species_by_room[source_key] = float(
					rejected_immediate_species_by_room.get(source_key, 0.0)
				) + rejected_immediate_kg
				_immediate_rejected_kg_total += rejected_immediate_kg
	if _is_immediate_species_cause(String(request.get("cause", ""))):
		var accepted_immediate_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			accepted_immediate_species[species_name] = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			) * accepted_fraction
		_add_transit_species(_immediate_debited_species_kg_step, accepted_immediate_species)
		_add_transit_species(_immediate_credited_species_kg_step, accepted_immediate_species)
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
