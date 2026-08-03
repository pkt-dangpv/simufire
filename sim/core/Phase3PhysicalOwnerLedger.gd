extends RefCounted
class_name Phase3PhysicalOwnerLedger

## H3.2-S0a: pure physical-owner event contract.
##
## This file deliberately has no runtime call site, flag, persistent step state
## or dependency on engine/building/room classes. It validates and aggregates
## caller-owned dictionaries without mutating them. Production mutation-site
## wiring belongs to H3.2-S0b/S0c.

const CLASS_LOCAL_SOURCE: String = "local_source"
const CLASS_EXTERIOR_BOUNDARY: String = "exterior_boundary"
const CLASS_INTERIOR_TRANSPORT: String = "interior_transport"
const CLASS_INTERZONE_REDISTRIBUTION: String = "interzone_redistribution"
const CLASS_DELAYED_PARCEL: String = "delayed_parcel"
const CLASS_NUMERICAL_CORRECTION: String = "numerical_correction"

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const EXTERIOR_ID: int = -1
const CONSERVATION_EPSILON: float = 1.0e-12

const VALID_CLASSIFICATIONS: Array[String] = [
	CLASS_LOCAL_SOURCE,
	CLASS_EXTERIOR_BOUNDARY,
	CLASS_INTERIOR_TRANSPORT,
	CLASS_INTERZONE_REDISTRIBUTION,
	CLASS_DELAYED_PARCEL,
	CLASS_NUMERICAL_CORRECTION,
]
const VALID_ZONES: Array[String] = [ZONE_UPPER, ZONE_LOWER]
const VALID_PARCEL_LIFECYCLES: Array[String] = [
	"created", "delivered", "cancelled", "inflight",
]


static func make_event(
		event_id: String,
		owner: String,
		classification: String,
		room_id: int,
		source_room_id: int = EXTERIOR_ID,
		destination_room_id: int = EXTERIOR_ID,
		source_zone: String = "",
		destination_zone: String = "",
		upper_mass_delta_kg: float = 0.0,
		lower_mass_delta_kg: float = 0.0,
		upper_energy_delta_kj: float = 0.0,
		lower_energy_delta_kj: float = 0.0,
		counterparty_mass_delta_kg: float = 0.0,
		counterparty_energy_delta_kj: float = 0.0,
		metadata: Dictionary = {}
	) -> Dictionary:
	return {
		"event_id": event_id,
		"owner": owner,
		"classification": classification,
		"room_id": room_id,
		"source_room_id": source_room_id,
		"destination_room_id": destination_room_id,
		"source_zone": source_zone,
		"destination_zone": destination_zone,
		"upper_mass_delta_kg": upper_mass_delta_kg,
		"lower_mass_delta_kg": lower_mass_delta_kg,
		"upper_energy_delta_kj": upper_energy_delta_kj,
		"lower_energy_delta_kj": lower_energy_delta_kj,
		"counterparty_mass_delta_kg": counterparty_mass_delta_kg,
		"counterparty_energy_delta_kj": counterparty_energy_delta_kj,
		"metadata": metadata.duplicate(true),
	}


static func validate_event(event: Dictionary) -> Dictionary:
	var common_reason: String = _validate_common(event)
	if not common_reason.is_empty():
		return _validation(false, common_reason)
	var classification: String = String(event["classification"])
	match classification:
		CLASS_LOCAL_SOURCE:
			return _validate_local_source(event)
		CLASS_EXTERIOR_BOUNDARY:
			return _validate_exterior_boundary(event)
		CLASS_INTERIOR_TRANSPORT:
			return _validate_interior_transport(event)
		CLASS_INTERZONE_REDISTRIBUTION:
			return _validate_interzone_redistribution(event)
		CLASS_DELAYED_PARCEL:
			return _validate_delayed_parcel(event)
		CLASS_NUMERICAL_CORRECTION:
			return _validate_numerical_correction(event)
	return _validation(false, "unknown_classification")


static func aggregate_events(events: Array) -> Dictionary:
	var result: Dictionary = _new_aggregate()
	var copies: Array[Dictionary] = []
	var id_counts: Dictionary = {}
	for raw_event in events:
		if not raw_event is Dictionary:
			result["invalid_event_count"] += 1
			result["errors"].append({"event_id": "", "reason": "event_not_dictionary"})
			continue
		var event: Dictionary = Dictionary(raw_event).duplicate(true)
		copies.append(event)
		var event_id: String = String(event.get("event_id", ""))
		id_counts[event_id] = int(id_counts.get(event_id, 0)) + 1
	copies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("event_id", "")) < String(b.get("event_id", ""))
	)
	var duplicate_ids: Dictionary = {}
	for event_id in id_counts.keys():
		var count: int = int(id_counts[event_id])
		if count > 1:
			duplicate_ids[event_id] = true
			result["duplicate_event_count"] += count - 1
	for event in copies:
		var event_id: String = String(event.get("event_id", ""))
		if duplicate_ids.has(event_id):
			result["invalid_event_count"] += 1
			result["errors"].append({"event_id": event_id, "reason": "duplicate_event_id"})
			continue
		var validation: Dictionary = validate_event(event)
		if not bool(validation["valid"]):
			result["invalid_event_count"] += 1
			result["errors"].append({
				"event_id": event_id,
				"reason": String(validation["reason"]),
			})
			continue
		result["valid_event_count"] += 1
		_aggregate_valid_event(result, event)
	result["valid"] = int(result["invalid_event_count"]) == 0 \
			and int(result["duplicate_event_count"]) == 0
	var conservation: Dictionary = building_conservation(copies, duplicate_ids)
	result["interior_transport_mass_residual_kg"] = conservation[
		"interior_transport_mass_residual_kg"
	]
	result["interior_transport_energy_residual_kj"] = conservation[
		"interior_transport_energy_residual_kj"
	]
	result["interzone_mass_residual_kg"] = conservation[
		"interzone_mass_residual_kg"
	]
	result["interzone_energy_residual_kj"] = conservation[
		"interzone_energy_residual_kj"
	]
	return result


static func physical_source_for_room(events: Array, room_id: int) -> Dictionary:
	var result: Dictionary = _new_zone_totals()
	if room_id < 0:
		return result
	var aggregate: Dictionary = aggregate_events(events)
	if not bool(aggregate.get("valid", false)):
		return result
	var room_key: String = str(room_id)
	var sources: Dictionary = aggregate.get("physical_source_by_room", {})
	if sources.has(room_key):
		return Dictionary(sources[room_key]).duplicate(true)
	return result


static func building_conservation(
		events: Array,
		known_duplicate_ids: Dictionary = {}
	) -> Dictionary:
	var interior_mass: float = 0.0
	var interior_energy: float = 0.0
	var interzone_mass: float = 0.0
	var interzone_energy: float = 0.0
	var id_counts: Dictionary = {}
	if known_duplicate_ids.is_empty():
		for raw_event in events:
			if raw_event is Dictionary:
				var event_id: String = String(raw_event.get("event_id", ""))
				id_counts[event_id] = int(id_counts.get(event_id, 0)) + 1
	for raw_event in events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var event_id: String = String(event.get("event_id", ""))
		if known_duplicate_ids.has(event_id) \
				or (not id_counts.is_empty() and int(id_counts.get(event_id, 0)) > 1):
			continue
		if not bool(validate_event(event)["valid"]):
			continue
		var classification: String = String(event["classification"])
		var mass: float = _room_mass_delta(event)
		var energy: float = _room_energy_delta(event)
		if classification == CLASS_INTERIOR_TRANSPORT:
			interior_mass += mass + float(event["counterparty_mass_delta_kg"])
			interior_energy += energy + float(event["counterparty_energy_delta_kj"])
		elif classification == CLASS_INTERZONE_REDISTRIBUTION:
			interzone_mass += mass
			interzone_energy += energy
	return {
		"interior_transport_mass_residual_kg": interior_mass,
		"interior_transport_energy_residual_kj": interior_energy,
		"interzone_mass_residual_kg": interzone_mass,
		"interzone_energy_residual_kj": interzone_energy,
		"interior_transport_conserved": absf(interior_mass) <= CONSERVATION_EPSILON \
				and absf(interior_energy) <= CONSERVATION_EPSILON,
		"interzone_conserved": absf(interzone_mass) <= CONSERVATION_EPSILON \
				and absf(interzone_energy) <= CONSERVATION_EPSILON,
	}


static func _validate_common(event: Dictionary) -> String:
	var required: Array[String] = [
		"event_id", "owner", "classification", "room_id", "source_room_id",
		"destination_room_id", "source_zone", "destination_zone",
		"upper_mass_delta_kg", "lower_mass_delta_kg",
		"upper_energy_delta_kj", "lower_energy_delta_kj",
		"counterparty_mass_delta_kg", "counterparty_energy_delta_kj", "metadata",
	]
	for key in required:
		if not event.has(key):
			return "missing_%s" % key
	if String(event["event_id"]).strip_edges().is_empty():
		return "empty_event_id"
	if String(event["owner"]).strip_edges().is_empty():
		return "empty_owner"
	if not VALID_CLASSIFICATIONS.has(String(event["classification"])):
		return "unknown_classification"
	if not event["metadata"] is Dictionary:
		return "metadata_not_dictionary"
	for key in [
		"upper_mass_delta_kg", "lower_mass_delta_kg",
		"upper_energy_delta_kj", "lower_energy_delta_kj",
		"counterparty_mass_delta_kg", "counterparty_energy_delta_kj",
	]:
		if not is_finite(float(event[key])):
			return "non_finite_%s" % key
	for key in ["source_zone", "destination_zone"]:
		var zone: String = String(event[key])
		if not zone.is_empty() and not VALID_ZONES.has(zone):
			return "invalid_%s" % key
	return ""


static func _validate_local_source(event: Dictionary) -> Dictionary:
	if int(event["room_id"]) < 0:
		return _validation(false, "invalid_room_id")
	if int(event["source_room_id"]) != EXTERIOR_ID \
			or int(event["destination_room_id"]) != EXTERIOR_ID:
		return _validation(false, "local_source_has_transport_rooms")
	if not String(event["source_zone"]).is_empty() \
			or not String(event["destination_zone"]).is_empty():
		return _validation(false, "local_source_has_transport_zones")
	if not _counterparty_is_zero(event):
		return _validation(false, "local_source_has_counterparty")
	return _validation(true, "")


static func _validate_exterior_boundary(event: Dictionary) -> Dictionary:
	var room_id: int = int(event["room_id"])
	var source_id: int = int(event["source_room_id"])
	var destination_id: int = int(event["destination_room_id"])
	if room_id < 0:
		return _validation(false, "invalid_room_id")
	var source_is_room: bool = source_id == room_id and destination_id == EXTERIOR_ID
	var destination_is_room: bool = source_id == EXTERIOR_ID and destination_id == room_id
	if source_is_room == destination_is_room:
		return _validation(false, "exterior_boundary_requires_one_interior_side")
	var interior_zone: String = String(
		event["source_zone"] if source_is_room else event["destination_zone"]
	)
	var exterior_zone: String = String(
		event["destination_zone"] if source_is_room else event["source_zone"]
	)
	if not VALID_ZONES.has(interior_zone) or not exterior_zone.is_empty():
		return _validation(false, "invalid_exterior_zone_assignment")
	if not _counterparty_is_zero(event):
		return _validation(false, "exterior_boundary_has_counterparty")
	var direction_sign: float = -1.0 if source_is_room else 1.0
	if direction_sign * _room_mass_delta(event) < -CONSERVATION_EPSILON \
			or direction_sign * _room_energy_delta(event) < -CONSERVATION_EPSILON:
		return _validation(false, "exterior_boundary_sign_mismatch")
	return _validation(true, "")


static func _validate_interior_transport(event: Dictionary) -> Dictionary:
	var room_id: int = int(event["room_id"])
	var source_id: int = int(event["source_room_id"])
	var destination_id: int = int(event["destination_room_id"])
	if room_id < 0 or source_id < 0 or destination_id < 0:
		return _validation(false, "invalid_transport_room_id")
	if room_id != source_id or source_id == destination_id:
		return _validation(false, "invalid_transport_direction")
	if not VALID_ZONES.has(String(event["source_zone"])) \
			or not VALID_ZONES.has(String(event["destination_zone"])):
		return _validation(false, "transport_zones_required")
	if _room_mass_delta(event) > CONSERVATION_EPSILON \
			or _room_energy_delta(event) > CONSERVATION_EPSILON \
			or float(event["counterparty_mass_delta_kg"]) < -CONSERVATION_EPSILON \
			or float(event["counterparty_energy_delta_kj"]) < -CONSERVATION_EPSILON:
		return _validation(false, "interior_transport_sign_mismatch")
	if absf(_room_mass_delta(event) + float(event["counterparty_mass_delta_kg"])) \
			> CONSERVATION_EPSILON:
		return _validation(false, "interior_transport_mass_not_conserved")
	if absf(_room_energy_delta(event) + float(event["counterparty_energy_delta_kj"])) \
			> CONSERVATION_EPSILON:
		return _validation(false, "interior_transport_energy_not_conserved")
	return _validation(true, "")


static func _validate_interzone_redistribution(event: Dictionary) -> Dictionary:
	var room_id: int = int(event["room_id"])
	if room_id < 0 or int(event["source_room_id"]) != room_id \
			or int(event["destination_room_id"]) != room_id:
		return _validation(false, "interzone_requires_one_room")
	if not VALID_ZONES.has(String(event["source_zone"])) \
			or not VALID_ZONES.has(String(event["destination_zone"])) \
			or String(event["source_zone"]) == String(event["destination_zone"]):
		return _validation(false, "interzone_requires_opposite_zones")
	if not _counterparty_is_zero(event):
		return _validation(false, "interzone_has_counterparty")
	var source_zone: String = String(event["source_zone"])
	var destination_zone: String = String(event["destination_zone"])
	if _zone_mass_delta(event, source_zone) > CONSERVATION_EPSILON \
			or _zone_energy_delta(event, source_zone) > CONSERVATION_EPSILON \
			or _zone_mass_delta(event, destination_zone) < -CONSERVATION_EPSILON \
			or _zone_energy_delta(event, destination_zone) < -CONSERVATION_EPSILON:
		return _validation(false, "interzone_direction_sign_mismatch")
	if absf(_room_mass_delta(event)) > CONSERVATION_EPSILON:
		return _validation(false, "interzone_mass_not_conserved")
	if absf(_room_energy_delta(event)) > CONSERVATION_EPSILON:
		return _validation(false, "interzone_energy_not_conserved")
	return _validation(true, "")


static func _validate_delayed_parcel(event: Dictionary) -> Dictionary:
	var metadata: Dictionary = event["metadata"]
	if String(metadata.get("parcel_id", "")).strip_edges().is_empty():
		return _validation(false, "parcel_id_required")
	if not VALID_PARCEL_LIFECYCLES.has(String(metadata.get("lifecycle", ""))):
		return _validation(false, "invalid_parcel_lifecycle")
	if int(event["room_id"]) < 0:
		return _validation(false, "invalid_room_id")
	var source_id: int = int(event["source_room_id"])
	var destination_id: int = int(event["destination_room_id"])
	if source_id < 0 or destination_id < 0 or source_id == destination_id:
		return _validation(false, "invalid_parcel_rooms")
	if not VALID_ZONES.has(String(event["source_zone"])) \
			or not VALID_ZONES.has(String(event["destination_zone"])):
		return _validation(false, "parcel_zones_required")
	return _validation(true, "")


static func _validate_numerical_correction(event: Dictionary) -> Dictionary:
	if int(event["room_id"]) < 0:
		return _validation(false, "invalid_room_id")
	if not _counterparty_is_zero(event):
		return _validation(false, "numerical_correction_has_counterparty")
	if int(event["source_room_id"]) != EXTERIOR_ID \
			or int(event["destination_room_id"]) != EXTERIOR_ID \
			or not String(event["source_zone"]).is_empty() \
			or not String(event["destination_zone"]).is_empty():
		return _validation(false, "numerical_correction_has_transport_identity")
	return _validation(true, "")


static func _aggregate_valid_event(result: Dictionary, event: Dictionary) -> void:
	var classification: String = String(event["classification"])
	var classification_totals: Dictionary = result["totals_by_classification"]
	var totals: Dictionary = classification_totals[classification]
	var mass_delta: float = _room_mass_delta(event)
	var energy_delta: float = _room_energy_delta(event)
	if classification == CLASS_INTERIOR_TRANSPORT:
		mass_delta += float(event["counterparty_mass_delta_kg"])
		energy_delta += float(event["counterparty_energy_delta_kj"])
	totals["event_count"] += 1
	totals["mass_delta_kg"] += mass_delta
	totals["energy_delta_kj"] += energy_delta
	classification_totals[classification] = totals
	result["totals_by_classification"] = classification_totals
	_add_primary_room_delta(result, event)
	if classification == CLASS_INTERIOR_TRANSPORT:
		_add_counterparty_room_delta(result, event)
	if classification == CLASS_LOCAL_SOURCE \
			or classification == CLASS_EXTERIOR_BOUNDARY:
		var room_key: String = str(int(event["room_id"]))
		var sources: Dictionary = result["physical_source_by_room"]
		var source: Dictionary = sources.get(room_key, _new_zone_totals())
		_accumulate_zone_totals(source, event)
		sources[room_key] = source
		result["physical_source_by_room"] = sources


static func _add_primary_room_delta(result: Dictionary, event: Dictionary) -> void:
	var room_id: int = int(event["room_id"])
	if room_id < 0:
		return
	var room_key: String = str(room_id)
	var rooms: Dictionary = result["totals_by_room"]
	var totals: Dictionary = rooms.get(room_key, _new_zone_totals())
	_accumulate_zone_totals(totals, event)
	rooms[room_key] = totals
	result["totals_by_room"] = rooms


static func _add_counterparty_room_delta(result: Dictionary, event: Dictionary) -> void:
	var room_key: String = str(int(event["destination_room_id"]))
	var rooms: Dictionary = result["totals_by_room"]
	var totals: Dictionary = rooms.get(room_key, _new_zone_totals())
	var zone: String = String(event["destination_zone"])
	totals[zone + "_mass_delta_kg"] += float(event["counterparty_mass_delta_kg"])
	totals[zone + "_energy_delta_kj"] += float(event["counterparty_energy_delta_kj"])
	totals["mass_delta_kg"] += float(event["counterparty_mass_delta_kg"])
	totals["energy_delta_kj"] += float(event["counterparty_energy_delta_kj"])
	rooms[room_key] = totals
	result["totals_by_room"] = rooms


static func _accumulate_zone_totals(totals: Dictionary, event: Dictionary) -> void:
	for zone in [ZONE_UPPER, ZONE_LOWER]:
		totals[zone + "_mass_delta_kg"] += float(event[zone + "_mass_delta_kg"])
		totals[zone + "_energy_delta_kj"] += float(event[zone + "_energy_delta_kj"])
	totals["mass_delta_kg"] += _room_mass_delta(event)
	totals["energy_delta_kj"] += _room_energy_delta(event)


static func _new_aggregate() -> Dictionary:
	var classifications: Dictionary = {}
	for classification in VALID_CLASSIFICATIONS:
		classifications[classification] = {
			"event_count": 0,
			"mass_delta_kg": 0.0,
			"energy_delta_kj": 0.0,
		}
	return {
		"valid": true,
		"valid_event_count": 0,
		"invalid_event_count": 0,
		"duplicate_event_count": 0,
		"errors": [],
		"totals_by_classification": classifications,
		"totals_by_room": {},
		"physical_source_by_room": {},
		"interior_transport_mass_residual_kg": 0.0,
		"interior_transport_energy_residual_kj": 0.0,
		"interzone_mass_residual_kg": 0.0,
		"interzone_energy_residual_kj": 0.0,
	}


static func _new_zone_totals() -> Dictionary:
	return {
		"upper_mass_delta_kg": 0.0,
		"lower_mass_delta_kg": 0.0,
		"upper_energy_delta_kj": 0.0,
		"lower_energy_delta_kj": 0.0,
		"mass_delta_kg": 0.0,
		"energy_delta_kj": 0.0,
	}


static func _room_mass_delta(event: Dictionary) -> float:
	return float(event["upper_mass_delta_kg"]) + float(event["lower_mass_delta_kg"])


static func _room_energy_delta(event: Dictionary) -> float:
	return float(event["upper_energy_delta_kj"]) + float(event["lower_energy_delta_kj"])


static func _zone_mass_delta(event: Dictionary, zone: String) -> float:
	return float(event[zone + "_mass_delta_kg"])


static func _zone_energy_delta(event: Dictionary, zone: String) -> float:
	return float(event[zone + "_energy_delta_kj"])


static func _counterparty_is_zero(event: Dictionary) -> bool:
	return float(event["counterparty_mass_delta_kg"]) == 0.0 \
			and float(event["counterparty_energy_delta_kj"]) == 0.0


static func _validation(valid: bool, reason: String) -> Dictionary:
	return {"valid": valid, "reason": reason}
