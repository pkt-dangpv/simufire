extends RefCounted

## M4-P2 PURE gas/energy/EOS authority with prescribed heat. NO simulation consumer.
## Contract: docs/validation/G3_M4_P2_GAS_ENERGY_EOS_CONTRACT_2026-10-17.md, section 5.1.
## Inert calorically perfect gas: R and cp are explicit book inputs, cv = cp - R.
## Conserved per layer: gas kg, ABSOLUTE internal energy kJ (u = cv*T, zero at 0 K)
## and O2 kg. Pressure, temperatures, layer volumes and interface are derived.
## No flow law, fuel, reaction, walls, radiation or hydrostatics. Inputs never
## mutate; the caller adopts a complete proposal or none of it.

const DetMath = preload("res://sim/core/DetMath.gd")

const BASIS: String = "physical_gas_energy_eos_v1"
const BOOK_KEYS: Array[String] = ["generation", "step", "revision", "basis", "gas",
	"reference_temp_k", "exterior_pressure_abs_pa", "rooms", "seen"]
const GAS_KEYS: Array[String] = ["cp_kj_kg_k", "R_kj_kg_k"]
const ROOM_KEYS: Array[String] = ["floor_area_m2", "height_m",
	"m_upper", "m_lower", "U_upper", "U_lower", "O_upper", "O_lower"]
const GEOMETRY_KEYS: Array[String] = ["floor_area_m2", "height_m"]
const EVENT_KEYS: Array[String] = ["id", "cause", "generation", "step", "revision", "basis",
	"expected_gas", "expected_rooms", "packets", "heat"]
const PACKET_KEYS: Array[String] = ["id", "kind", "source", "target", "gas_kg", "boundary"]
const HEAT_KEYS: Array[String] = ["id", "target", "energy_kj"]
const ENDPOINT_KEYS: Array[String] = ["room", "zone"]
const BOUNDARY_KEYS: Array[String] = ["Y", "T_k"]
const ZONES: Array[String] = ["upper", "lower"]
## |r - 1| below this evaluates phi(r) by its series; truncation < 1e-24.
const PHI_SERIES_THRESHOLD: float = 1.0e-4


## cp, R, cv, gamma and k = R/cp of a VALID book. R never depends on the scenario.
static func gas_properties(book: Dictionary) -> Dictionary:
	var cp: float = float(book["gas"]["cp_kj_kg_k"])
	var R: float = float(book["gas"]["R_kj_kg_k"])
	var cv: float = cp - R
	return {"cp": cp, "R": R, "cv": cv, "gamma": cp / cv, "k": R / cp}


## (r - r^k)/(r - 1); phi(1) = 1 - k = 1/gamma.
static func phi(r: float, k: float) -> float:
	var eps: float = r - 1.0
	if absf(eps) >= PHI_SERIES_THRESHOLD:
		return (r - DetMath.pow(r, k)) / eps
	# r^k = sum C(k,n) eps^n  ->  phi = (1-k) - sum_{n>=2} C(k,n) eps^(n-1)
	var total: float = 1.0 - k
	var coeff: float = k
	var eps_power: float = 1.0
	for n: int in range(2, 7):
		coeff *= (k - float(n) + 1.0) / float(n)
		eps_power *= eps
		total -= coeff * eps_power
	return total


static func validate(book: Variant) -> String:
	if not _keys(book, BOOK_KEYS):
		return "book_schema"
	for key: String in ["generation", "step", "revision"]:
		if not _whole(book[key]):
			return "book_context"
	if book["basis"] != BASIS:
		return "book_basis"
	var gas_reason: String = _gas_reason(book["gas"])
	if not gas_reason.is_empty():
		return gas_reason
	for key: String in ["reference_temp_k", "exterior_pressure_abs_pa"]:
		if not _number(book[key]):
			return "non_finite_or_bool_number"
		if float(book[key]) <= 0.0:
			return "book_reference"
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


## Derived view only: never written back as state.
static func observables(book: Variant) -> Dictionary:
	var reason: String = validate(book)
	if not reason.is_empty():
		return _refuse(reason)
	var gas: Dictionary = gas_properties(book)
	var rooms: Dictionary = {}
	for room_id: String in book["rooms"]:
		var room: Dictionary = book["rooms"][room_id]
		var area: float = float(room["floor_area_m2"])
		var volume: float = area * float(room["height_m"])
		var u_room: float = float(room["U_upper"]) + float(room["U_lower"])
		var p_abs: float = (float(gas["gamma"]) - 1.0) * u_room / volume * 1000.0
		var layers: Dictionary = {}
		for zone: String in ZONES:
			var m: float = float(room["m_" + zone])
			var u: float = float(room["U_" + zone])
			if m == 0.0:
				layers[zone] = {"T_k": null, "V_m3": 0.0, "H_kj": 0.0, "Y_o2": null, "E_sensible_kj": 0.0}
				continue
			layers[zone] = {
				"T_k": u / (m * float(gas["cv"])),
				"V_m3": volume * u / u_room,
				"H_kj": float(gas["gamma"]) * u,
				"Y_o2": float(room["O_" + zone]) / m,
				"E_sensible_kj": float(gas["gamma"]) * u - m * float(gas["cp"]) * float(book["reference_temp_k"]),
			}
		rooms[room_id] = {"p_abs_pa": p_abs,
			"p_gauge_pa": p_abs - float(book["exterior_pressure_abs_pa"]),
			"U_room_kj": u_room, "volume_m3": volume,
			"interface_m": float(layers["lower"]["V_m3"]) / area, "layers": layers}
	return {"valid": true, "gas": gas, "rooms": rooms}


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
			return _refuse("stale_context_or_revision")
	if book["seen"].has(event["id"]):
		return _refuse("duplicate_event_or_parcel")
	if event["expected_gas"] != book["gas"]:
		return _refuse("property_set_changed_within_run")
	var expected: Variant = event["expected_rooms"]
	if typeof(expected) != TYPE_DICTIONARY or expected.size() != book["rooms"].size():
		return _refuse("stale_context_or_revision")
	for room_id: String in book["rooms"]:
		if not expected.has(room_id) or typeof(expected[room_id]) != TYPE_DICTIONARY:
			return _refuse("stale_context_or_revision")
		for key: String in GEOMETRY_KEYS:
			if expected[room_id].get(key) != book["rooms"][room_id][key]:
				return _refuse("geometry_changed_within_run")
	if expected != book["rooms"]:
		return _refuse("stale_context_or_revision")
	if typeof(event["packets"]) != TYPE_ARRAY or typeof(event["heat"]) != TYPE_ARRAY:
		return _refuse("event_actions")
	if event["packets"].is_empty() and event["heat"].is_empty():
		return _refuse("event_empty")
	var gas: Dictionary = gas_properties(book)
	var gamma: float = float(gas["gamma"])
	var acc: Dictionary = {}
	var external: Dictionary = {}
	for room_id: String in book["rooms"]:
		external[room_id] = 0.0
		acc[room_id] = {}
		for zone: String in ZONES:
			acc[room_id][zone] = {"heat_kj": 0.0, "in_kg": 0.0, "out_kg": 0.0,
				"in_h_kj": 0.0, "out_h_kj": 0.0, "dO_kg": 0.0, "in_O_kg": 0.0}
	var boundary: Dictionary = {"mass_in_kg": 0.0, "mass_out_kg": 0.0, "H_in_kj": 0.0,
		"H_out_kj": 0.0, "O_in_kg": 0.0, "O_out_kg": 0.0}
	var unique: Dictionary = {}
	var heats: Array[Dictionary] = []
	# Heat first, then parcels: the oracle's summation order.
	for heat: Variant in event["heat"]:
		if not _keys(heat, HEAT_KEYS) or not _text(heat["id"]):
			return _refuse("heat_schema")
		if unique.has(heat["id"]):
			return _refuse("duplicate_event_or_parcel")
		unique[heat["id"]] = true
		if not _endpoint(heat["target"], book):
			return _refuse("heat_target")
		if not _number(heat["energy_kj"]):
			return _refuse("non_finite_or_bool_number")
		var target: Dictionary = heat["target"]
		acc[target["room"]][target["zone"]]["heat_kj"] += float(heat["energy_kj"])
		external[target["room"]] += float(heat["energy_kj"])
		heats.append({"id": heat["id"], "target": target.duplicate(true), "energy_kj": float(heat["energy_kj"])})
	var parcels: Array[Dictionary] = []
	for packet: Variant in event["packets"]:
		if not _keys(packet, PACKET_KEYS) or not _text(packet["id"]):
			return _refuse("packet_schema")
		if unique.has(packet["id"]):
			return _refuse("duplicate_event_or_parcel")
		unique[packet["id"]] = true
		if not _number(packet["gas_kg"]):
			return _refuse("non_finite_or_bool_number")
		if float(packet["gas_kg"]) < 0.0:
			return _refuse("negative_mass")
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
		var carried_h: float = 0.0
		var carried_o: float = 0.0
		if source != null:
			var donor: Dictionary = book["rooms"][source["room"]]
			var zone: String = source["zone"]
			var donor_mass: float = float(donor["m_" + zone])
			if donor_mass == 0.0 and q > 0.0:
				return _refuse("overdraft_of_donor")
			if q > 0.0:
				# Enthalpy h = cp*T = gamma*u of the SNAPSHOT donor, never the candidate.
				carried_h = q * gamma * float(donor["U_" + zone]) / donor_mass
				carried_o = q * float(donor["O_" + zone]) / donor_mass
		else:
			var outside: Dictionary = packet["boundary"]
			if not _number(outside["T_k"]) or not _number(outside["Y"]):
				return _refuse("non_finite_or_bool_number")
			if float(outside["T_k"]) <= 0.0:
				return _refuse("non_positive_exterior_temperature")
			if float(outside["Y"]) < 0.0 or float(outside["Y"]) > 1.0:
				return _refuse("exterior_o2_fraction_out_of_range")
			carried_h = q * float(gas["cp"]) * float(outside["T_k"])
			carried_o = q * float(outside["Y"])
		if not is_finite(carried_h) or not is_finite(carried_o):
			return _refuse("aggregate_overflow")
		if source != null:
			var debit: Dictionary = acc[source["room"]][source["zone"]]
			debit["out_kg"] += q
			debit["out_h_kj"] += carried_h
			debit["dO_kg"] -= carried_o
		if target != null:
			var credit: Dictionary = acc[target["room"]][target["zone"]]
			credit["in_kg"] += q
			credit["in_h_kj"] += carried_h
			credit["dO_kg"] += carried_o
			credit["in_O_kg"] += carried_o
		if kind == "transfer" and source["room"] != target["room"]:
			external[source["room"]] -= carried_h
			external[target["room"]] += carried_h
		elif kind == "boundary_in":
			external[target["room"]] += carried_h
			boundary["mass_in_kg"] += q
			boundary["H_in_kj"] += carried_h
			boundary["O_in_kg"] += carried_o
		elif kind == "boundary_out":
			external[source["room"]] -= carried_h
			boundary["mass_out_kg"] += q
			boundary["H_out_kj"] += carried_h
			boundary["O_out_kg"] += carried_o
		parcels.append({"id": packet["id"], "kind": kind,
			"source": source.duplicate(true) if source != null else null,
			"target": target.duplicate(true) if target != null else null,
			"gas_kg": q, "enthalpy_kj": carried_h, "oxygen_kg": carried_o})
	# Gross donations from the snapshot: no arrival of this event finances an exit.
	for room_id: String in book["rooms"]:
		for zone: String in ZONES:
			var row: Dictionary = acc[room_id][zone]
			for field: String in row:
				if not is_finite(float(row[field])):
					return _refuse("aggregate_overflow")
			var mass: float = float(book["rooms"][room_id]["m_" + zone])
			if float(row["out_kg"]) > mass:
				if float(row["out_kg"]) <= mass + float(row["in_kg"]):
					return _refuse("inflow_financing_outflow")
				return _refuse("overdraft_of_donor")
	var after: Dictionary = book.duplicate(true)
	var room_rows: Dictionary = {}
	var k: float = float(gas["k"])
	for room_id: String in book["rooms"]:
		var room: Dictionary = book["rooms"][room_id]
		var u0: float = float(room["U_upper"]) + float(room["U_lower"])
		var u1: float = u0 + float(external[room_id])
		if not is_finite(u1) or u1 <= 0.0:
			return _refuse("room_energy_non_positive_after_step")
		var r: float = u1 / u0
		var rk: float = 1.0 if r == 1.0 else DetMath.pow(r, k)
		var f: float = 1.0 / gamma if r == 1.0 else phi(r, k)
		var layer_rows: Dictionary = {}
		for zone: String in ZONES:
			var row: Dictionary = acc[room_id][zone]
			var m0: float = float(room["m_" + zone])
			var u_z0: float = float(room["U_" + zone])
			var heat_kj: float = float(row["heat_kj"])
			var out_kg: float = float(row["out_kg"])
			var m1: float = m0 - out_kg + float(row["in_kg"])
			if m1 == 0.0 and heat_kj != 0.0:
				return _refuse("heat_into_absent_layer_without_mass")
			var gained: float = heat_kj + float(row["in_h_kj"])
			var lost: float = float(row["out_h_kj"])
			var retained: float = (m0 - out_kg) / m0 if m0 > 0.0 else 1.0
			var u_z1: float
			if r == 1.0:
				# Isobaric step: outflow leaves the intensive state; exact zero on depletion.
				u_z1 = u_z0 * retained + gained / gamma
			else:
				if m0 > 0.0 and retained == 0.0:
					return _refuse("layer_depleted_while_pressure_changes")
				u_z1 = rk * u_z0 + f * (gained - lost)
			if m1 == 0.0:
				if u_z1 != 0.0:
					return _refuse("layer_depleted_while_pressure_changes")
			elif not is_finite(u_z1) or u_z1 <= 0.0:
				return _refuse("layer_energy_negative_after_step")
			var candidate: Dictionary = after["rooms"][room_id]
			candidate["m_" + zone] = m1
			candidate["U_" + zone] = u_z1
			var o_z1: float = float(room["O_" + zone]) + float(row["dO_kg"])
			if m0 > 0.0 and retained == 0.0:
				# Fully drained (reachable only with r == 1): all its O2 left with the gas.
				# (q*O)/m can miss O by an ulp, so keep the exact zero that m and U have.
				o_z1 = float(row["in_O_kg"])
			candidate["O_" + zone] = o_z1
			var a_z: float = gained - lost
			layer_rows[zone] = {"heat_kj": heat_kj, "in_kg": float(row["in_kg"]), "out_kg": out_kg,
				"in_h_kj": float(row["in_h_kj"]), "out_h_kj": lost, "dO_kg": float(row["dO_kg"]),
				"A_kj": a_z, "W_kj": u_z1 - u_z0 - a_z}
		room_rows[room_id] = {"U0_kj": u0, "U1_kj": u1, "external_kj": float(external[room_id]),
			"r": r, "r_pow_k": rk, "phi": f, "layers": layer_rows}
	after["revision"] = int(book["revision"]) + 1
	after["seen"].append(event["id"])
	reason = validate(after)
	if not reason.is_empty():
		return _refuse("candidate:" + reason)
	return {"valid": true, "book": after.duplicate(true),
		"receipt": {"before": book.duplicate(true), "after": after.duplicate(true),
			"event": event.duplicate(true), "parcels": parcels.duplicate(true),
			"heat": heats.duplicate(true), "rooms": room_rows.duplicate(true),
			"boundary": boundary.duplicate(true)}}


static func _gas_reason(gas: Variant) -> String:
	if not _keys(gas, GAS_KEYS):
		return "gas_schema"
	for key: String in GAS_KEYS:
		if not _number(gas[key]):
			return "non_finite_or_bool_number"
	var R: float = float(gas["R_kj_kg_k"])
	if R <= 0.0:
		return "R_not_positive"
	if float(gas["cp_kj_kg_k"]) <= R:
		return "cp_not_greater_than_R"
	return ""


static func _room_reason(room: Variant) -> String:
	if not _keys(room, ROOM_KEYS):
		return "room_schema"
	for field: String in ROOM_KEYS:
		if not _number(room[field]):
			return "non_finite_or_bool_number"
	if float(room["floor_area_m2"]) <= 0.0 or float(room["height_m"]) <= 0.0:
		return "non_positive_volume"
	for zone: String in ZONES:
		var m: float = float(room["m_" + zone])
		var u: float = float(room["U_" + zone])
		var o: float = float(room["O_" + zone])
		if m < 0.0:
			return "negative_mass"
		if u < 0.0:
			return "negative_internal_energy"
		if m == 0.0 and u != 0.0:
			return "energy_without_mass"
		if m > 0.0 and u == 0.0:
			return "mass_without_energy"
		if o < 0.0 or o > m:
			return "o2_out_of_range"
	var u_room: float = float(room["U_upper"]) + float(room["U_lower"])
	if not is_finite(u_room) or not is_finite(float(room["m_upper"]) + float(room["m_lower"])):
		return "room_aggregate"
	if u_room <= 0.0:
		return "room_without_gas"
	return ""


static func _endpoint(value: Variant, book: Dictionary) -> bool:
	return _keys(value, ENDPOINT_KEYS) and _text(value["room"]) and book["rooms"].has(value["room"]) \
		and ZONES.has(value["zone"])


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


static func _refuse(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
