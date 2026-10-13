extends RefCounted

## M4-P1 PURE imposed physical gas/O2 parcels. NO simulation consumer.
## Gas kg, O2 kg, sensible kJ above ONE common imposed reference temperature.
## No flow/EOS/interface/reaction/fuel/selection/rates or reference-base remap.
## Inputs never mutate; caller adopts a complete proposal or none of it.

const BASIS: String = "physical_gas_mass_v1"
const BOOK_KEYS: Array[String] = ["generation", "step", "revision", "reference_temp_k", "basis", "rooms", "seen"]
const ROOM_KEYS: Array[String] = ["m_upper", "m_lower", "E_upper", "E_lower", "O_total", "O_upper"]
const EVENT_KEYS: Array[String] = ["id", "cause", "generation", "step", "revision", "basis", "expected_rooms", "packets", "heat"]
const PACKET_KEYS: Array[String] = ["id", "kind", "source", "target", "gas_kg", "boundary"]
const HEAT_KEYS: Array[String] = ["id", "target", "energy_kj"]
const ENDPOINT_KEYS: Array[String] = ["room", "zone"]
const BOUNDARY_KEYS: Array[String] = ["Y", "e_kj_kg"]
const ZONES: Array[String] = ["upper", "lower"]


static func validate(book: Variant) -> String:
	if not _keys(book, BOOK_KEYS):
		return "book_schema"
	for key: String in ["generation", "step", "revision"]:
		if not _whole(book[key]):
			return "book_context"
	if book["basis"] != BASIS or not _number(book["reference_temp_k"]) or float(book["reference_temp_k"]) <= 0.0:
		return "book_basis"
	if typeof(book["rooms"]) != TYPE_DICTIONARY or book["rooms"].is_empty():
		return "book_rooms"
	for room_id: Variant in book["rooms"]:
		if not _text(room_id):
			return "room_id"
		var reason: String = _room_reason(book["rooms"][room_id])
		if not reason.is_empty():
			return reason
	if typeof(book["seen"]) != TYPE_ARRAY:
		return "book_seen"
	var unique: Dictionary = {}
	for event_id: Variant in book["seen"]:
		if not _text(event_id) or unique.has(event_id):
			return "book_seen"
		unique[event_id] = true
	return ""


static func observables(book: Variant) -> Dictionary:
	var reason: String = validate(book)
	if not reason.is_empty():
		return _refuse(reason)
	var rooms: Dictionary = {}
	for room_id: String in book["rooms"]:
		var room: Dictionary = book["rooms"][room_id]
		var zones: Dictionary = {}
		for zone: String in ZONES:
			var mass: float = float(room["m_" + zone])
			zones[zone] = _oxygen(room, zone) / mass if mass > 0.0 else null
		rooms[room_id] = zones
	return {"valid": true, "units": "oxygen_mass_fraction", "rooms": rooms}


static func propose(book: Variant, event: Variant) -> Dictionary:
	var reason: String = validate(book)
	if not reason.is_empty():
		return _refuse(reason)
	if not _keys(event, EVENT_KEYS) or not _text(event["id"]) or not _text(event["cause"]):
		return _refuse("event_schema")
	if event["basis"] != BASIS:
		return _refuse("event_basis")
	for key: String in ["generation", "step", "revision"]:
		if not _whole(event[key]) or event[key] != book[key]:
			return _refuse("event_context")
	if book["seen"].has(event["id"]):
		return _refuse("event_duplicate")
	if event["expected_rooms"] != book["rooms"]:
		return _refuse("event_stale_rooms")
	if typeof(event["packets"]) != TYPE_ARRAY or typeof(event["heat"]) != TYPE_ARRAY:
		return _refuse("event_actions")
	if event["packets"].is_empty() and event["heat"].is_empty():
		return _refuse("event_empty")
	var changes: Dictionary = {}
	for room_id: String in book["rooms"]:
		changes[room_id] = {}
		for zone: String in ZONES:
			changes[room_id][zone] = {"mass": 0.0, "oxygen": 0.0, "energy": 0.0,
				"donated_mass": 0.0, "donated_oxygen": 0.0, "donated_energy": 0.0}
	var unique: Dictionary = {}
	var parcels: Array[Dictionary] = []
	for packet: Variant in event["packets"]:
		if not _keys(packet, PACKET_KEYS) or not _text(packet["id"]) or unique.has(packet["id"]):
			return _refuse("packet_schema_or_duplicate")
		unique[packet["id"]] = true
		if not _amount(packet["gas_kg"]):
			return _refuse("packet_amount")
		var source: Variant = packet["source"]
		var target: Variant = packet["target"]
		var kind: Variant = packet["kind"]
		if kind == "transfer":
			if not _endpoint(source, book) or not _endpoint(target, book) or source == target or packet["boundary"] != null:
				return _refuse("packet_endpoints")
		elif kind == "boundary_out":
			if not _endpoint(source, book) or target != null or packet["boundary"] != null:
				return _refuse("packet_endpoints")
		elif kind == "boundary_in":
			if source != null or not _endpoint(target, book) or not _keys(packet["boundary"], BOUNDARY_KEYS):
				return _refuse("packet_endpoints")
		else:
			return _refuse("packet_kind")
		var q: float = float(packet["gas_kg"])
		var carried_oxygen: float = 0.0
		var carried_energy: float = 0.0
		if source != null:
			var donor: Dictionary = book["rooms"][source["room"]]
			var zone: String = source["zone"]
			var donor_mass: float = float(donor["m_" + zone])
			if donor_mass == 0.0 and q > 0.0:
				return _refuse("absent_donor")
			if donor_mass > 0.0:
				carried_oxygen = q * (_oxygen(donor, zone) / donor_mass)
				carried_energy = q * (float(donor["E_" + zone]) / donor_mass)
		else:
			var boundary: Dictionary = packet["boundary"]
			if not _amount(boundary["Y"]) or float(boundary["Y"]) > 1.0 or not _amount(boundary["e_kj_kg"]):
				return _refuse("boundary_composition")
			carried_oxygen = q * float(boundary["Y"])
			carried_energy = q * float(boundary["e_kj_kg"])
		if not is_finite(carried_oxygen) or not is_finite(carried_energy):
			return _refuse("packet_overflow")
		if source != null:
			var debit: Dictionary = changes[source["room"]][source["zone"]]
			debit["mass"] -= q
			debit["oxygen"] -= carried_oxygen
			debit["energy"] -= carried_energy
			debit["donated_mass"] += q
			debit["donated_oxygen"] += carried_oxygen
			debit["donated_energy"] += carried_energy
		if target != null:
			var credit: Dictionary = changes[target["room"]][target["zone"]]
			credit["mass"] += q
			credit["oxygen"] += carried_oxygen
			credit["energy"] += carried_energy
		parcels.append({"id": packet["id"], "kind": kind, "source": source,
			"target": target, "gas_kg": q, "oxygen_kg": carried_oxygen, "energy_kj": carried_energy})
	for heat: Variant in event["heat"]:
		if not _keys(heat, HEAT_KEYS) or not _text(heat["id"]) or unique.has(heat["id"]):
			return _refuse("heat_schema_or_duplicate")
		unique[heat["id"]] = true
		if not _endpoint(heat["target"], book) or not _number(heat["energy_kj"]):
			return _refuse("heat_target_or_amount")
		var target: Dictionary = heat["target"]
		var delta: Dictionary = changes[target["room"]][target["zone"]]
		delta["energy"] += float(heat["energy_kj"])
		delta["donated_energy"] += maxf(0.0, -float(heat["energy_kj"]))
	# Gross donations, NOT net deltas: no arrival finances an outgoing parcel.
	for room_id: String in book["rooms"]:
		var room: Dictionary = book["rooms"][room_id]
		for zone: String in ZONES:
			var delta: Dictionary = changes[room_id][zone]
			for field: String in delta:
				if not is_finite(float(delta[field])):
					return _refuse("aggregate_overflow")
			if float(delta["donated_mass"]) > float(room["m_" + zone]):
				return _refuse("gross_mass_overdraft")
			if float(delta["donated_oxygen"]) > _oxygen(room, zone):
				return _refuse("gross_oxygen_overdraft")
			if float(delta["donated_energy"]) > float(room["E_" + zone]):
				return _refuse("gross_energy_overdraft")
	var after: Dictionary = book.duplicate(true)
	for room_id: String in book["rooms"]:
		var before_room: Dictionary = book["rooms"][room_id]
		var candidate: Dictionary = after["rooms"][room_id]
		var lower_oxygen: float = _oxygen(before_room, "lower") + float(changes[room_id]["lower"]["oxygen"])
		for zone: String in ZONES:
			candidate["m_" + zone] = float(before_room["m_" + zone]) + float(changes[room_id][zone]["mass"])
			candidate["E_" + zone] = float(before_room["E_" + zone]) + float(changes[room_id][zone]["energy"])
		candidate["O_upper"] = float(before_room["O_upper"]) + float(changes[room_id]["upper"]["oxygen"])
		candidate["O_total"] = float(candidate["O_upper"]) + lower_oxygen
		# Do not erase a tiny negative lower through cancellation in total.
		if lower_oxygen < 0.0:
			return _refuse("candidate_lower_oxygen")
	after["revision"] = int(book["revision"]) + 1
	after["seen"].append(event["id"])
	reason = validate(after)
	if not reason.is_empty():
		return _refuse("candidate:" + reason)
	return {"valid": true, "book": after.duplicate(true),
		"receipt": {"before": book.duplicate(true), "after": after.duplicate(true),
			"event": event.duplicate(true), "parcels": parcels.duplicate(true), "deltas": changes.duplicate(true)}}


static func _room_reason(room: Variant) -> String:
	if not _keys(room, ROOM_KEYS):
		return "room_schema"
	for field: String in ROOM_KEYS:
		if not _amount(room[field]):
			return "room_amount"
	var upper_oxygen: float = float(room["O_upper"])
	var lower_oxygen: float = float(room["O_total"]) - upper_oxygen
	if lower_oxygen < 0.0:
		return "room_oxygen"
	for zone: String in ZONES:
		var gas: float = float(room["m_" + zone])
		var oxygen: float = upper_oxygen if zone == "upper" else lower_oxygen
		if oxygen > gas:
			return "room_capacity"
		if gas == 0.0 and (oxygen != 0.0 or float(room["E_" + zone]) != 0.0):
			return "room_absent"
	if not is_finite(float(room["m_upper"]) + float(room["m_lower"])):
		return "room_aggregate"
	if not is_finite(float(room["E_upper"]) + float(room["E_lower"])):
		return "room_aggregate"
	return ""


static func _oxygen(room: Dictionary, zone: String) -> float:
	return float(room["O_upper"]) if zone == "upper" else float(room["O_total"]) - float(room["O_upper"])


static func _endpoint(value: Variant, book: Dictionary) -> bool:
	return _keys(value, ENDPOINT_KEYS) and _text(value["room"]) and book["rooms"].has(value["room"]) and ZONES.has(value["zone"])


static func _keys(value: Variant, fields: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()


static func _whole(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _amount(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0


static func _refuse(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
