extends RefCounted
class_name Phase3ZoneMassSystem

# F3.0: transaccion two-zone en sombra. Este componente nunca escribe RoomModel.

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const EXTERIOR_ID: int = -1
const TRANSIT_SPECIES: Array[String] = ["co", "co2", "hcn"]
const SEMANTIC_QUANTITY_BITS: Dictionary = {
	"gas_mass": 1,
	"enthalpy": 2,
	"o2": 4,
	"co": 8,
	"co2": 16,
	"hcn": 32,
}

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
var _vertical_net_species_kg: Dictionary = {}
var _vertical_directed_species_kg: Dictionary = {}
var _immediate_transfer_count: int = 0
var _immediate_rejected_kg_total: float = 0.0
var _immediate_debited_species_kg_step: Dictionary = {}
var _immediate_credited_species_kg_step: Dictionary = {}
var _vertical_transfer_count: int = 0
var _vertical_rejected_kg_total: float = 0.0
var _vertical_opposed_zone_direction_count: int = 0
var _vertical_debited_species_kg_step: Dictionary = {}
var _vertical_credited_species_kg_step: Dictionary = {}
var _exterior_purge_requested_species_kg: Dictionary = {}
var _exterior_purge_upper_species_kg: Dictionary = {}
var _exterior_purge_applied_species_kg: Dictionary = {}
var _exterior_purge_rejected_species_kg: Dictionary = {}
var _exterior_purge_mechanism_species_kg: Dictionary = {}
var _exterior_purge_event_ids: Dictionary = {}
var _exterior_purge_event_count: int = 0
var _exterior_purge_duplicate_event_count: int = 0
var _thermal_species_requested_kg: Dictionary = {}
var _thermal_species_source_upper_kg: Dictionary = {}
var _thermal_species_destination_upper_kg: Dictionary = {}
var _thermal_species_applied_kg: Dictionary = {}
var _thermal_species_rejected_kg: Dictionary = {}
var _thermal_species_mechanism_kg: Dictionary = {}
var _thermal_species_event_ids: Dictionary = {}
var _thermal_species_event_count: int = 0
var _thermal_species_duplicate_event_count: int = 0
var _semantic_claims: Dictionary = {}
var _semantic_claim_count: int = 0
var _semantic_unknown_connection_count: int = 0


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
	_vertical_net_species_kg.clear()
	_vertical_directed_species_kg.clear()
	_immediate_transfer_count = 0
	_immediate_rejected_kg_total = 0.0
	_vertical_transfer_count = 0
	_vertical_rejected_kg_total = 0.0
	_vertical_opposed_zone_direction_count = 0
	_exterior_purge_requested_species_kg.clear()
	_exterior_purge_upper_species_kg.clear()
	_exterior_purge_applied_species_kg.clear()
	_exterior_purge_rejected_species_kg.clear()
	_exterior_purge_mechanism_species_kg.clear()
	_exterior_purge_event_count = 0
	_exterior_purge_duplicate_event_count = 0
	_thermal_species_requested_kg.clear()
	_thermal_species_source_upper_kg.clear()
	_thermal_species_destination_upper_kg.clear()
	_thermal_species_applied_kg.clear()
	_thermal_species_rejected_kg.clear()
	_thermal_species_mechanism_kg.clear()
	_thermal_species_event_count = 0
	_thermal_species_duplicate_event_count = 0


func _reset_step_state() -> void:
	_snapshots.clear()
	_requests.clear()
	_request_ids.clear()
	_duplicate_owner_count = 0
	_results.clear()
	_immediate_debited_species_kg_step.clear()
	_immediate_credited_species_kg_step.clear()
	_vertical_debited_species_kg_step.clear()
	_vertical_credited_species_kg_step.clear()
	_exterior_purge_event_ids.clear()
	_thermal_species_event_ids.clear()
	_semantic_claims.clear()
	_semantic_claim_count = 0
	_semantic_unknown_connection_count = 0


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
			_register_split_species_claims(
				event,
				"GasExchangeSystem",
				"delayed_parcel",
				"interior_opening",
				created_species,
				created_upper_species
			)
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
	_register_event_species_claims(
		event,
		"GasExchangeSystem",
		_semantic_transport_family(cause),
		"vertical_opening" if _is_vertical_species_cause(cause) else "interior_opening",
		total_species
	)
	match cause:
		"background_species_exchange":
			_add_transit_species(_immediate_background_species_kg, total_species)
		"doorway_species_counterflow":
			_add_transit_species(_immediate_counterflow_species_kg, total_species)
		"vertical_species_net_exchange":
			_add_transit_species(_vertical_net_species_kg, total_species)
			_vertical_transfer_count += 1
			if bool(event.get("opposed_zone_direction", false)):
				_vertical_opposed_zone_direction_count += 1
		"vertical_species_directed_exchange":
			_add_transit_species(_vertical_directed_species_kg, total_species)
			_vertical_transfer_count += 1
	_immediate_transfer_count += 1
	if event.has("source_zone") and event.has("destination_zone"):
		add_request(make_request(
			request_id,
			cause,
			int(event.get("source_room_id", EXTERIOR_ID)),
			int(event.get("destination_room_id", EXTERIOR_ID)),
			String(event.get("source_zone", ZONE_UPPER)),
			String(event.get("destination_zone", ZONE_UPPER)),
			0.0,
			0.0,
			0.0,
			total_species
		))
	else:
		var upper_species: Dictionary = _bounded_upper_transit_species(
			event.get("upper_species_kg", {}), total_species
		)
		_add_transit_zone_requests(
			request_id,
			cause,
			int(event.get("source_room_id", EXTERIOR_ID)),
			int(event.get("destination_room_id", EXTERIOR_ID)),
			total_species,
			upper_species
		)


func apply_exterior_purge_event(event: Dictionary) -> void:
	var event_id: String = String(event.get("event_id", ""))
	var mechanism: String = String(event.get("mechanism", ""))
	if event_id.is_empty() or mechanism.is_empty():
		return
	if _exterior_purge_event_ids.has(event_id):
		_exterior_purge_duplicate_event_count += 1
		_duplicate_owner_count += 1
		return
	_exterior_purge_event_ids[event_id] = true
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	if _sum_transit_species(total_species) <= 0.0:
		return
	var upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("upper_species_kg", {}), total_species
	)
	_register_split_species_claims(
		event,
		"GasExchangeSystem",
		"exterior_purge",
		"exterior_opening",
		total_species,
		upper_species
	)
	_exterior_purge_event_count += 1
	_add_transit_species(_exterior_purge_requested_species_kg, total_species)
	_add_transit_species(_exterior_purge_upper_species_kg, upper_species)
	if not _exterior_purge_mechanism_species_kg.has(mechanism):
		_exterior_purge_mechanism_species_kg[mechanism] = {}
	var mechanism_species: Dictionary = _exterior_purge_mechanism_species_kg[mechanism]
	_add_transit_species(mechanism_species, total_species)
	_exterior_purge_mechanism_species_kg[mechanism] = mechanism_species
	_add_transit_zone_requests(
		event_id,
		"exterior_species_purge:" + mechanism,
		int(event.get("source_room_id", EXTERIOR_ID)),
		EXTERIOR_ID,
		total_species,
		upper_species
	)


func apply_thermal_species_event(event: Dictionary) -> void:
	var event_id: String = String(event.get("event_id", ""))
	var mechanism: String = String(event.get("mechanism", ""))
	if event_id.is_empty() or mechanism.is_empty():
		return
	if _thermal_species_event_ids.has(event_id):
		_thermal_species_duplicate_event_count += 1
		_duplicate_owner_count += 1
		return
	_thermal_species_event_ids[event_id] = true
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	if _sum_transit_species(total_species) <= 0.0:
		return
	var source_upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("source_upper_species_kg", {}), total_species
	)
	var destination_upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("destination_upper_species_kg", {}), total_species
	)
	_register_thermal_species_claims(
		event,
		total_species,
		source_upper_species,
		destination_upper_species
	)
	_thermal_species_event_count += 1
	_add_transit_species(_thermal_species_requested_kg, total_species)
	_add_transit_species(_thermal_species_source_upper_kg, source_upper_species)
	_add_transit_species(_thermal_species_destination_upper_kg, destination_upper_species)
	if not _thermal_species_mechanism_kg.has(mechanism):
		_thermal_species_mechanism_kg[mechanism] = {}
	var mechanism_species: Dictionary = _thermal_species_mechanism_kg[mechanism]
	_add_transit_species(mechanism_species, total_species)
	_thermal_species_mechanism_kg[mechanism] = mechanism_species
	_add_thermal_species_route_requests(
		event_id,
		"thermal_species_transport:" + mechanism,
		int(event.get("source_room_id", EXTERIOR_ID)),
		int(event.get("destination_room_id", EXTERIOR_ID)),
		total_species,
		source_upper_species,
		destination_upper_species
	)


func _is_immediate_species_cause(cause: String) -> bool:
	return cause == "background_species_exchange" \
			or cause == "doorway_species_counterflow" \
			or cause == "vertical_species_net_exchange" \
			or cause == "vertical_species_directed_exchange"


func _is_exterior_purge_cause(cause: String) -> bool:
	return cause.begins_with("exterior_species_purge:")


func _is_thermal_species_cause(cause: String) -> bool:
	return cause.begins_with("thermal_species_transport:")


func _is_vertical_species_cause(cause: String) -> bool:
	return cause == "vertical_species_net_exchange" \
			or cause == "vertical_species_directed_exchange"


func register_semantic_claim(claim: Dictionary) -> void:
	var connection_id: String = String(claim.get("connection_id", ""))
	var producer: String = String(claim.get("producer", ""))
	var quantity: String = String(claim.get("quantity", ""))
	var amount: float = maxf(0.0, float(claim.get("amount", 0.0)))
	if producer.is_empty() or not SEMANTIC_QUANTITY_BITS.has(quantity) or amount <= 0.0:
		return
	if connection_id.is_empty():
		_semantic_unknown_connection_count += 1
		return
	var key: String = "%s|%d|%d|%s|%s|%s" % [
		connection_id,
		int(claim.get("source_room_id", EXTERIOR_ID)),
		int(claim.get("destination_room_id", EXTERIOR_ID)),
		String(claim.get("source_zone", ZONE_UPPER)),
		String(claim.get("destination_zone", ZONE_UPPER)),
		quantity,
	]
	var record: Dictionary = _semantic_claims.get(key, {
		"quantity": quantity,
		"producers": {},
		"mechanisms": {},
	})
	var producers: Dictionary = record.get("producers", {})
	producers[producer] = float(producers.get(producer, 0.0)) + amount
	record["producers"] = producers
	var mechanisms: Dictionary = record.get("mechanisms", {})
	var mechanism: String = String(claim.get("transport_family", ""))
	var boundary_kind: String = String(claim.get("boundary_kind", ""))
	if not mechanism.is_empty():
		mechanisms[producer + ":" + mechanism + ":" + boundary_kind] = true
	record["mechanisms"] = mechanisms
	_semantic_claims[key] = record
	_semantic_claim_count += 1


func register_semantic_species_claim(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String
	) -> void:
	var total_species: Dictionary = _transit_species(event.get("species_kg", {}))
	_register_event_species_claims(
		event, producer, transport_family, boundary_kind, total_species
	)


func _register_event_species_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		total_species: Dictionary
	) -> void:
	if event.has("source_zone") and event.has("destination_zone"):
		_register_species_map_claims(
			event,
			producer,
			transport_family,
			boundary_kind,
			String(event.get("source_zone", ZONE_UPPER)),
			String(event.get("destination_zone", ZONE_UPPER)),
			total_species
		)
		return
	var upper_species: Dictionary = _bounded_upper_transit_species(
		event.get("upper_species_kg", {}), total_species
	)
	_register_split_species_claims(
		event, producer, transport_family, boundary_kind, total_species, upper_species
	)


func _register_split_species_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		total_species: Dictionary,
		upper_species: Dictionary
	) -> void:
	_register_species_map_claims(
		event,
		producer,
		transport_family,
		boundary_kind,
		ZONE_UPPER,
		ZONE_UPPER,
		upper_species
	)
	_register_species_map_claims(
		event,
		producer,
		transport_family,
		boundary_kind,
		ZONE_LOWER,
		ZONE_LOWER,
		_lower_transit_species(total_species, upper_species)
	)


func _register_thermal_species_claims(
		event: Dictionary,
		total_species: Dictionary,
		source_upper_species: Dictionary,
		destination_upper_species: Dictionary
	) -> void:
	var routes: Dictionary = {
		"upper_upper": {},
		"upper_lower": {},
		"lower_upper": {},
		"lower_lower": {},
	}
	for species_name in TRANSIT_SPECIES:
		var total_kg: float = float(total_species.get(species_name, 0.0))
		var source_upper_kg: float = float(source_upper_species.get(species_name, 0.0))
		var destination_upper_kg: float = float(
			destination_upper_species.get(species_name, 0.0)
		)
		var upper_upper_kg: float = minf(source_upper_kg, destination_upper_kg)
		routes["upper_upper"][species_name] = upper_upper_kg
		routes["upper_lower"][species_name] = maxf(0.0, source_upper_kg - upper_upper_kg)
		routes["lower_upper"][species_name] = maxf(0.0, destination_upper_kg - upper_upper_kg)
		routes["lower_lower"][species_name] = maxf(
			0.0,
			total_kg - float(routes["upper_upper"][species_name])
					- float(routes["upper_lower"][species_name])
					- float(routes["lower_upper"][species_name])
		)
	for route_name in routes.keys():
		var route_parts: PackedStringArray = String(route_name).split("_")
		_register_species_map_claims(
			event,
			"ThermalSystem",
			"thermal_carry",
			"interlayer" if String(event.get("mechanism", "")) == "co_interlayer_mixing" \
					else "interior_opening",
			String(route_parts[0]),
			String(route_parts[1]),
			routes[route_name]
		)


func _register_species_map_claims(
		event: Dictionary,
		producer: String,
		transport_family: String,
		boundary_kind: String,
		source_zone: String,
		destination_zone: String,
		species: Dictionary
	) -> void:
	var connection_id: String = String(event.get("connection_id", ""))
	for species_name in TRANSIT_SPECIES:
		var mass_kg: float = maxf(0.0, float(species.get(species_name, 0.0)))
		if mass_kg <= 0.0:
			continue
		register_semantic_claim({
			"connection_id": connection_id,
			"producer": producer,
			"transport_family": transport_family,
			"boundary_kind": boundary_kind,
			"source_room_id": int(event.get("source_room_id", EXTERIOR_ID)),
			"destination_room_id": int(event.get("destination_room_id", EXTERIOR_ID)),
			"source_zone": source_zone,
			"destination_zone": destination_zone,
			"quantity": species_name,
			"amount": mass_kg,
		})


func _semantic_transport_family(cause: String) -> String:
	match cause:
		"background_species_exchange":
			return "background_exchange"
		"doorway_species_counterflow":
			return "doorway_bulk"
		"vertical_species_net_exchange", "vertical_species_directed_exchange":
			return "vertical_flow"
	return cause


func _semantic_conflict_summary() -> Dictionary:
	var conflict_count: int = 0
	var quantity_mask: int = 0
	var conflict_mass_kg: float = 0.0
	var conflict_energy_kj: float = 0.0
	var conflict_o2_kg: float = 0.0
	var conflict_species_kg: float = 0.0
	for record in _semantic_claims.values():
		var producers: Dictionary = record.get("producers", {})
		if producers.size() <= 1:
			continue
		conflict_count += 1
		var quantity: String = String(record.get("quantity", ""))
		quantity_mask |= int(SEMANTIC_QUANTITY_BITS.get(quantity, 0))
		var total: float = 0.0
		var largest: float = 0.0
		for amount in producers.values():
			total += float(amount)
			largest = maxf(largest, float(amount))
		var contested: float = maxf(0.0, total - largest)
		match quantity:
			"gas_mass":
				conflict_mass_kg += contested
			"enthalpy":
				conflict_energy_kj += contested
			"o2":
				conflict_o2_kg += contested
			"co", "co2", "hcn":
				conflict_species_kg += contested
	return {
		"claim_count": _semantic_claim_count,
		"conflict_count": conflict_count,
		"quantity_mask": quantity_mask,
		"conflict_mass_kg": conflict_mass_kg,
		"conflict_energy_kj": conflict_energy_kj,
		"conflict_o2_kg": conflict_o2_kg,
		"conflict_species_kg": conflict_species_kg,
		"unknown_connection_count": _semantic_unknown_connection_count,
	}


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


func _add_thermal_species_route_requests(
		request_id_prefix: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		total_species: Dictionary,
		source_upper_species: Dictionary,
		destination_upper_species: Dictionary
	) -> void:
	var routes: Dictionary = {
		"upper_upper": {},
		"upper_lower": {},
		"lower_upper": {},
		"lower_lower": {},
	}
	for species_name in TRANSIT_SPECIES:
		var total_kg: float = float(total_species.get(species_name, 0.0))
		var source_upper_kg: float = float(source_upper_species.get(species_name, 0.0))
		var destination_upper_kg: float = float(
			destination_upper_species.get(species_name, 0.0)
		)
		var upper_upper_kg: float = minf(source_upper_kg, destination_upper_kg)
		var upper_lower_kg: float = maxf(0.0, source_upper_kg - upper_upper_kg)
		var lower_upper_kg: float = maxf(0.0, destination_upper_kg - upper_upper_kg)
		var lower_lower_kg: float = maxf(
			0.0, total_kg - upper_upper_kg - upper_lower_kg - lower_upper_kg
		)
		routes["upper_upper"][species_name] = upper_upper_kg
		routes["upper_lower"][species_name] = upper_lower_kg
		routes["lower_upper"][species_name] = lower_upper_kg
		routes["lower_lower"][species_name] = lower_lower_kg
	for route_name in routes.keys():
		var route_parts: PackedStringArray = String(route_name).split("_")
		var route_species: Dictionary = routes[route_name]
		if _sum_transit_species(route_species) <= 0.0:
			continue
		add_request(make_request(
			request_id_prefix + ":" + String(route_name),
			cause,
			source_room_id,
			destination_room_id,
			String(route_parts[0]),
			String(route_parts[1]),
			0.0,
			0.0,
			0.0,
			route_species
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


func _exterior_purge_lower_for(species_name: String) -> float:
	return maxf(
		0.0,
		float(_exterior_purge_requested_species_kg.get(species_name, 0.0))
				- float(_exterior_purge_upper_species_kg.get(species_name, 0.0))
	)


func _exterior_purge_residual_for(species_name: String) -> float:
	return float(_exterior_purge_requested_species_kg.get(species_name, 0.0)) \
			- float(_exterior_purge_applied_species_kg.get(species_name, 0.0)) \
			- float(_exterior_purge_rejected_species_kg.get(species_name, 0.0))


func _exterior_purge_mechanism_total(mechanism: String) -> float:
	var species: Dictionary = _exterior_purge_mechanism_species_kg.get(mechanism, {})
	return _sum_transit_species(species)


func _thermal_species_lower_for(species_name: String, upper: Dictionary) -> float:
	return maxf(
		0.0,
		float(_thermal_species_requested_kg.get(species_name, 0.0))
				- float(upper.get(species_name, 0.0))
	)


func _thermal_species_residual_for(species_name: String) -> float:
	return float(_thermal_species_requested_kg.get(species_name, 0.0)) \
			- float(_thermal_species_applied_kg.get(species_name, 0.0)) \
			- float(_thermal_species_rejected_kg.get(species_name, 0.0))


func _thermal_species_mechanism_total(mechanism: String) -> float:
	return _sum_transit_species(_thermal_species_mechanism_kg.get(mechanism, {}))


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
	var vertical_co_residual_kg: float = float(
		_vertical_debited_species_kg_step.get("co", 0.0)
	) - float(_vertical_credited_species_kg_step.get("co", 0.0))
	var vertical_co2_residual_kg: float = float(
		_vertical_debited_species_kg_step.get("co2", 0.0)
	) - float(_vertical_credited_species_kg_step.get("co2", 0.0))
	var vertical_hcn_residual_kg: float = float(
		_vertical_debited_species_kg_step.get("hcn", 0.0)
	) - float(_vertical_credited_species_kg_step.get("hcn", 0.0))
	var semantic_summary: Dictionary = _semantic_conflict_summary()
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
			"phase3_shadow_vertical_net_co_kg_total": float(
				_vertical_net_species_kg.get("co", 0.0)
			),
			"phase3_shadow_vertical_net_co2_kg_total": float(
				_vertical_net_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_vertical_net_hcn_kg_total": float(
				_vertical_net_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_vertical_directed_co_kg_total": float(
				_vertical_directed_species_kg.get("co", 0.0)
			),
			"phase3_shadow_vertical_directed_co2_kg_total": float(
				_vertical_directed_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_vertical_directed_hcn_kg_total": float(
				_vertical_directed_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_vertical_transfer_count": float(_vertical_transfer_count),
			"phase3_shadow_vertical_rejected_kg_total": _vertical_rejected_kg_total,
			"phase3_shadow_vertical_opposed_zone_direction_count": float(
				_vertical_opposed_zone_direction_count
			),
			"phase3_shadow_vertical_co_residual_kg": vertical_co_residual_kg,
			"phase3_shadow_vertical_co2_residual_kg": vertical_co2_residual_kg,
			"phase3_shadow_vertical_hcn_residual_kg": vertical_hcn_residual_kg,
			"phase3_shadow_thermal_co_kg_total": float(
				_thermal_species_requested_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_co2_kg_total": float(
				_thermal_species_requested_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_hcn_kg_total": float(
				_thermal_species_requested_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_source_upper_co_kg_total": float(
				_thermal_species_source_upper_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_source_upper_co2_kg_total": float(
				_thermal_species_source_upper_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_source_upper_hcn_kg_total": float(
				_thermal_species_source_upper_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_source_lower_co_kg_total": _thermal_species_lower_for(
				"co", _thermal_species_source_upper_kg
			),
			"phase3_shadow_thermal_source_lower_co2_kg_total": _thermal_species_lower_for(
				"co2", _thermal_species_source_upper_kg
			),
			"phase3_shadow_thermal_source_lower_hcn_kg_total": _thermal_species_lower_for(
				"hcn", _thermal_species_source_upper_kg
			),
			"phase3_shadow_thermal_destination_upper_co_kg_total": float(
				_thermal_species_destination_upper_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_destination_upper_co2_kg_total": float(
				_thermal_species_destination_upper_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_destination_upper_hcn_kg_total": float(
				_thermal_species_destination_upper_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_destination_lower_co_kg_total": _thermal_species_lower_for(
				"co", _thermal_species_destination_upper_kg
			),
			"phase3_shadow_thermal_destination_lower_co2_kg_total": _thermal_species_lower_for(
				"co2", _thermal_species_destination_upper_kg
			),
			"phase3_shadow_thermal_destination_lower_hcn_kg_total": _thermal_species_lower_for(
				"hcn", _thermal_species_destination_upper_kg
			),
			"phase3_shadow_thermal_applied_co_kg_total": float(
				_thermal_species_applied_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_applied_co2_kg_total": float(
				_thermal_species_applied_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_applied_hcn_kg_total": float(
				_thermal_species_applied_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_rejected_co_kg_total": float(
				_thermal_species_rejected_kg.get("co", 0.0)
			),
			"phase3_shadow_thermal_rejected_co2_kg_total": float(
				_thermal_species_rejected_kg.get("co2", 0.0)
			),
			"phase3_shadow_thermal_rejected_hcn_kg_total": float(
				_thermal_species_rejected_kg.get("hcn", 0.0)
			),
			"phase3_shadow_thermal_event_count": float(_thermal_species_event_count),
			"phase3_shadow_thermal_duplicate_event_count": float(
				_thermal_species_duplicate_event_count
			),
			"phase3_shadow_thermal_co_residual_kg": _thermal_species_residual_for("co"),
			"phase3_shadow_thermal_co2_residual_kg": _thermal_species_residual_for("co2"),
			"phase3_shadow_thermal_hcn_residual_kg": _thermal_species_residual_for("hcn"),
			"phase3_shadow_thermal_doorway_kg_total": _thermal_species_mechanism_total(
				"doorway_hot_gas"
			),
			"phase3_shadow_thermal_outside_background_kg_total": _thermal_species_mechanism_total(
				"outside_assisted_background_heat"
			),
			"phase3_shadow_thermal_interior_background_kg_total": _thermal_species_mechanism_total(
				"interior_background_heat"
			),
			"phase3_shadow_thermal_interlayer_kg_total": _thermal_species_mechanism_total(
				"co_interlayer_mixing"
			),
			"phase3_shadow_purge_co_out_kg_total": float(
				_exterior_purge_requested_species_kg.get("co", 0.0)
			),
			"phase3_shadow_purge_co2_out_kg_total": float(
				_exterior_purge_requested_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_purge_hcn_out_kg_total": float(
				_exterior_purge_requested_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_purge_upper_co_kg_total": float(
				_exterior_purge_upper_species_kg.get("co", 0.0)
			),
			"phase3_shadow_purge_upper_co2_kg_total": float(
				_exterior_purge_upper_species_kg.get("co2", 0.0)
			),
			"phase3_shadow_purge_upper_hcn_kg_total": float(
				_exterior_purge_upper_species_kg.get("hcn", 0.0)
			),
			"phase3_shadow_purge_lower_co_kg_total": _exterior_purge_lower_for("co"),
			"phase3_shadow_purge_lower_co2_kg_total": _exterior_purge_lower_for("co2"),
			"phase3_shadow_purge_lower_hcn_kg_total": _exterior_purge_lower_for("hcn"),
			"phase3_shadow_purge_applied_kg_total": _sum_transit_species(
				_exterior_purge_applied_species_kg
			),
			"phase3_shadow_purge_rejected_kg_total": _sum_transit_species(
				_exterior_purge_rejected_species_kg
			),
			"phase3_shadow_purge_event_count": float(_exterior_purge_event_count),
			"phase3_shadow_purge_duplicate_event_count": float(
				_exterior_purge_duplicate_event_count
			),
			"phase3_shadow_purge_co_residual_kg": _exterior_purge_residual_for("co"),
			"phase3_shadow_purge_co2_residual_kg": _exterior_purge_residual_for("co2"),
			"phase3_shadow_purge_hcn_residual_kg": _exterior_purge_residual_for("hcn"),
			"phase3_shadow_purge_pressure_kg_total": _exterior_purge_mechanism_total(
				"pressure_venting"
			),
			"phase3_shadow_purge_smoke_vent_kg_total": _exterior_purge_mechanism_total(
				"exterior_smoke_vent"
			),
			"phase3_shadow_purge_natural_vent_kg_total": _exterior_purge_mechanism_total(
				"natural_ventilation"
			),
			"phase3_shadow_purge_ach_kg_total": _exterior_purge_mechanism_total(
				"ach_infiltration"
			),
			"phase3_shadow_purge_outside_open_kg_total": _exterior_purge_mechanism_total(
				"outside_open_species_purge"
			),
			"phase3_shadow_purge_postfire_kg_total": _exterior_purge_mechanism_total(
				"postfire_species_purge"
			),
			"phase3_shadow_purge_ppv_inlet_kg_total": _exterior_purge_mechanism_total(
				"ppv_inlet_dilution"
			),
			"phase3_shadow_purge_ppv_exhaust_kg_total": _exterior_purge_mechanism_total(
				"ppv_exhaust"
			),
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
			"phase3_shadow_semantic_claim_count": float(
				semantic_summary.get("claim_count", 0)
			),
			"phase3_shadow_semantic_conflict_count": float(
				semantic_summary.get("conflict_count", 0)
			),
			"phase3_shadow_semantic_conflict_quantity_mask": float(
				semantic_summary.get("quantity_mask", 0)
			),
			"phase3_shadow_semantic_conflict_mass_kg": float(
				semantic_summary.get("conflict_mass_kg", 0.0)
			),
			"phase3_shadow_semantic_conflict_energy_kj": float(
				semantic_summary.get("conflict_energy_kj", 0.0)
			),
			"phase3_shadow_semantic_conflict_o2_kg": float(
				semantic_summary.get("conflict_o2_kg", 0.0)
			),
			"phase3_shadow_semantic_conflict_species_kg": float(
				semantic_summary.get("conflict_species_kg", 0.0)
			),
			"phase3_shadow_semantic_unknown_connection_count": float(
				semantic_summary.get("unknown_connection_count", 0)
			),
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
				if _is_vertical_species_cause(String(request.get("cause", ""))):
					_vertical_rejected_kg_total += rejected_immediate_kg
	var request_cause: String = String(request.get("cause", ""))
	if _is_exterior_purge_cause(request_cause):
		var accepted_purge_species: Dictionary = {}
		var rejected_purge_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			var requested_purge_kg: float = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			)
			accepted_purge_species[species_name] = requested_purge_kg * accepted_fraction
			rejected_purge_species[species_name] = requested_purge_kg * (1.0 - accepted_fraction)
		_add_transit_species(_exterior_purge_applied_species_kg, accepted_purge_species)
		_add_transit_species(_exterior_purge_rejected_species_kg, rejected_purge_species)
	if _is_immediate_species_cause(request_cause):
		var accepted_immediate_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			accepted_immediate_species[species_name] = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			) * accepted_fraction
		_add_transit_species(_immediate_debited_species_kg_step, accepted_immediate_species)
		_add_transit_species(_immediate_credited_species_kg_step, accepted_immediate_species)
		if _is_vertical_species_cause(request_cause):
			_add_transit_species(_vertical_debited_species_kg_step, accepted_immediate_species)
			_add_transit_species(_vertical_credited_species_kg_step, accepted_immediate_species)
	if _is_thermal_species_cause(request_cause):
		var accepted_thermal_species: Dictionary = {}
		var rejected_thermal_species: Dictionary = {}
		for species_name in TRANSIT_SPECIES:
			var requested_thermal_kg: float = maxf(
				0.0, float(request.get("species_kg", {}).get(species_name, 0.0))
			)
			accepted_thermal_species[species_name] = requested_thermal_kg * accepted_fraction
			rejected_thermal_species[species_name] = requested_thermal_kg * (1.0 - accepted_fraction)
		_add_transit_species(_thermal_species_applied_kg, accepted_thermal_species)
		_add_transit_species(_thermal_species_rejected_kg, rejected_thermal_species)
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
