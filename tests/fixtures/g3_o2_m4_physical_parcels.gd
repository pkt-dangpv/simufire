extends SceneTree

## Imposed parcels only. No engine, gas flow solver, reaction or exposure.
const Model = preload("res://sim/core/PhysicalGasOxygenParcelModel.gd")
var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _near(actual: float, expected: float, label: String) -> void:
	_check(is_finite(actual) and is_finite(expected) and absf(actual - expected) <= 1.0e-9, label)


func _book() -> Dictionary:
	return {"generation": 3, "step": 7, "revision": 0, "reference_temp_k": 300.0,
		"basis": "physical_gas_mass_v1", "seen": [], "rooms": {
			"a": {"m_upper": 10.0, "m_lower": 20.0, "E_upper": 100.0, "E_lower": 400.0, "O_total": 5.0, "O_upper": 1.0},
			"b": {"m_upper": 4.0, "m_lower": 16.0, "E_upper": 40.0, "E_lower": 160.0, "O_total": 4.0, "O_upper": 0.8}}}


func _end(room: String, zone: String) -> Variant:
	return {"room": room, "zone": zone} if not room.is_empty() else null


func _parcel(id: String, a: String, az: String, b: String, bz: String, q: Variant) -> Dictionary:
	return {"id": id, "kind": "boundary_in" if a.is_empty() else ("boundary_out" if b.is_empty() else "transfer"),
		"source": _end(a, az), "target": _end(b, bz), "gas_kg": q,
		"boundary": {"Y": 0.2, "e_kj_kg": 10.0} if a.is_empty() else null}


func _event(book: Dictionary, id: String, packets: Array, heat: Array = []) -> Dictionary:
	return {"id": id, "cause": "imposed_control", "generation": book.generation,
		"step": book.step, "revision": book.revision, "basis": book.basis,
		"expected_rooms": book.rooms.duplicate(true), "packets": packets, "heat": heat}


func _reject(book: Dictionary, event: Variant, label: String) -> void:
	var before: Dictionary = book.duplicate(true)
	var original_event: Variant = event.duplicate(true) if typeof(event) == TYPE_DICTIONARY else event
	var result: Dictionary = Model.propose(book, event)
	_check(not bool(result.get("valid", true)), label + " rejected")
	_check(not result.has("book") and not result.has("receipt"), label + " no proposal")
	_check(_same(book, before) and _same(event, original_event), label + " unchanged")


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_FLOAT and is_nan(float(a)):
		return is_nan(float(b))
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i: int in range(a.size()):
			if not _same(a[i], b[i]):
				return false
		return true
	return a == b


func _audit(result: Dictionary, label: String, sample: bool = true) -> bool:
	_check(bool(result.get("valid", false)), label + " accepted")
	if not bool(result.get("valid", false)):
		return false
	var receipt: Dictionary = result.receipt
	_check(result.book == receipt.after, label + " receipt matches")
	_near(float(receipt.after.revision), float(receipt.before.revision) + 1.0, label + " revision")
	_check(receipt.after.seen.has(receipt.event.id), label + " seen")
	for parcel: Dictionary in receipt.parcels:
		var expected_o: float = 0.0
		var expected_e: float = 0.0
		if parcel.source == null:
			for imposed: Dictionary in receipt.event.packets:
				if imposed.id == parcel.id:
					expected_o = float(parcel.gas_kg) * float(imposed.boundary.Y)
					expected_e = float(parcel.gas_kg) * float(imposed.boundary.e_kj_kg)
		else:
			var donor: Dictionary = receipt.before.rooms[parcel.source.room]
			var zone: String = parcel.source.zone
			var oxygen: float = float(donor.O_upper) if zone == "upper" else float(donor.O_total) - float(donor.O_upper)
			var mass: float = float(donor["m_" + zone])
			if mass > 0.0:
				expected_o = float(parcel.gas_kg) * oxygen / mass
				expected_e = float(parcel.gas_kg) * float(donor["E_" + zone]) / mass
		_near(parcel.oxygen_kg, expected_o, "donor oxygen")
		_near(parcel.energy_kj, expected_e, "donor energy")
	for room_id: String in receipt.before.rooms:
		var before: Dictionary = receipt.before.rooms[room_id]
		var after: Dictionary = receipt.after.rooms[room_id]
		for zone: String in ["upper", "lower"]:
			var expected: Array[float] = [0.0, 0.0, 0.0]
			for parcel: Dictionary in receipt.parcels:
				for endpoint: String in ["source", "target"]:
					var end: Variant = parcel[endpoint]
					if end != null and end.room == room_id and end.zone == zone:
						var sign: float = -1.0 if endpoint == "source" else 1.0
						expected[0] += sign * float(parcel.gas_kg)
						expected[1] += sign * float(parcel.oxygen_kg)
						expected[2] += sign * float(parcel.energy_kj)
			for heat: Dictionary in receipt.event.heat:
				if heat.target.room == room_id and heat.target.zone == zone:
					expected[2] += float(heat.energy_kj)
			var o_before: float = float(before.O_upper) if zone == "upper" else float(before.O_total) - float(before.O_upper)
			var o_after: float = float(after.O_upper) if zone == "upper" else float(after.O_total) - float(after.O_upper)
			_near(float(after["m_" + zone]) - float(before["m_" + zone]), expected[0], "paired gas")
			_near(o_after - o_before, expected[1], "paired oxygen")
			_near(float(after["E_" + zone]) - float(before["E_" + zone]), expected[2], "paired energy")
	if sample:
		samples.append({"name": label, "receipt": receipt.duplicate(true), "observables": Model.observables(result.book)})
	return true


func _run() -> void:
	_check(Model.validate(_book()).is_empty(), "base valid")
	var base: Dictionary = _book()
	var plume: Dictionary = Model.propose(base, _event(base, "plume", [_parcel("p", "a", "lower", "a", "upper", 2.0)]))
	if _audit(plume, "plume"):
		_near(plume.book.rooms.a.O_upper, 1.4, "plume analytic upper")
		_near(plume.book.rooms.a.m_lower, 18.0, "plume analytic lower gas")
		_near(plume.book.rooms.a.E_upper, 140.0, "plume analytic energy")
	var heat: Array = [{"id": "heat", "target": _end("a", "upper"), "energy_kj": 3000.0}]
	var warmed: Dictionary = Model.propose(base, _event(base, "warm", [], heat))
	if _audit(warmed, "heat only"):
		_near(warmed.book.rooms.a.O_upper, 1.0, "heat cannot create oxygen")
		_near(warmed.book.rooms.a.m_upper, 10.0, "heat cannot create gas")
	var door: Dictionary = Model.propose(base, _event(base, "door", [
		_parcel("out", "a", "upper", "b", "upper", 2.0),
		_parcel("in", "b", "lower", "a", "lower", 2.0)]))
	if _audit(door, "door"):
		_near(door.book.rooms.a.O_total, 5.2, "door stratified analytic total")
	for kind: String in ["in", "out", "zero", "collapse", "reverse"]:
		var q: float = 20.0 if kind == "collapse" else (0.0 if kind == "zero" else 2.0)
		var source: String = "" if kind == "in" else "a"
		var target: String = "" if kind == "out" else "a"
		var sz: String = "upper" if kind == "reverse" else "lower"
		var tz: String = "lower" if kind == "reverse" else "upper"
		_audit(Model.propose(base, _event(base, kind, [_parcel("p", source, sz, target, tz, q)])), kind)
	var absent: Dictionary = _book()
	absent.rooms.a = {"m_upper": 0.0, "m_lower": 30.0, "E_upper": 0.0, "E_lower": 300.0, "O_total": 6.0, "O_upper": 0.0}
	_check(Model.observables(absent).rooms.a.upper == null, "absent observable")
	_audit(Model.propose(absent, _event(absent, "birth", [_parcel("p", "a", "lower", "a", "upper", 2.0)])), "birth")
	var rich: Dictionary = _book()
	rich.rooms.a.O_upper = 8.0
	rich.rooms.a.O_total = 12.0
	_audit(Model.propose(rich, _event(rich, "rich", [_parcel("p", "a", "upper", "a", "lower", 1.0)])), "rich no ceiling")
	# Multiple donations and incoming credit: EACH individual q fits, gross does not.
	_reject(base, _event(base, "gross", [_parcel("x", "a", "upper", "b", "upper", 6.0),
		_parcel("y", "a", "upper", "b", "lower", 6.0)]), "gross donations")
	_reject(base, _event(base, "credit", [_parcel("in", "", "", "a", "upper", 20.0),
		_parcel("out", "a", "upper", "", "", 11.0)]), "incoming not funding")
	var empty_composition: Dictionary = _book()
	empty_composition.rooms.a.O_upper = 0.0
	empty_composition.rooms.a.O_total = 4.0
	empty_composition.rooms.a.E_upper = 0.0
	# Net candidate remains valid and O2/E caps cannot conceal the missing gas cap.
	_reject(empty_composition, _event(empty_composition, "gas credit", [
		_parcel("in", "", "", "a", "upper", 20.0),
		_parcel("out", "a", "upper", "", "", 11.0)]), "gross gas independent")
	_reject(base, _event(base, "cool", [_parcel("out", "a", "upper", "b", "upper", 6.0)],
		[{"id": "cool", "target": _end("a", "upper"), "energy_kj": -50.0}]), "cooling plus donation")
	_reject(base, _event(base, "warm cool", [], [
		{"id": "warm", "target": _end("a", "upper"), "energy_kj": 100.0},
		{"id": "cool", "target": _end("a", "upper"), "energy_kj": -101.0}]), "heat credit not funding")
	var packet: Dictionary = _parcel("p", "a", "upper", "b", "upper", 1.0)
	for bad: Variant in [true, "1", null, NAN, INF, -INF, -0.000000000001]:
		var wrong: Dictionary = packet.duplicate(true)
		wrong.gas_kg = bad
		_reject(base, _event(base, "badq", [wrong]), "invalid parcel amount")
	for bad: Variant in [true, "1", null, NAN, INF, -INF]:
		var wrong: Dictionary = _book()
		wrong.reference_temp_k = bad
		_check(not Model.validate(wrong).is_empty(), "invalid number")
	var malformed: Array[Dictionary] = []
	for field: String in ["generation", "step", "revision"]:
		var wrong: Dictionary = _event(base, "context", [packet])
		wrong[field] = int(base[field]) + 1
		malformed.append(wrong)
	for event: Dictionary in malformed:
		_reject(base, event, "context mismatch")
	for bad: Variant in [true, 3.0, -1]:
		var wrong: Dictionary = _book()
		wrong.generation = bad
		_check(not Model.validate(wrong).is_empty(), "integer context")
	var stale: Dictionary = _event(base, "stale", [packet])
	stale.expected_rooms.a.O_upper = 0.9
	_reject(base, stale, "stale snapshot")
	var wrong_basis: Dictionary = _event(base, "basis", [packet])
	wrong_basis.basis = "reference_dry_air_v1"
	_reject(base, wrong_basis, "reference basis")
	_reject(base, _event(base, "duplicate contribution", [packet, packet]), "duplicate contribution")
	if bool(plume.get("valid", false)):
		_reject(plume.book, _event(plume.book, "plume", [packet]), "duplicate event")
	var no_donor: Dictionary = packet.duplicate(true)
	no_donor.source.zone = "nonexistent"
	_reject(base, _event(base, "zone", [no_donor]), "invalid endpoint")
	_reject(absent, _event(absent, "absent", [packet]), "absent donor")
	for change: Dictionary in [
		{"m_upper": 1.0, "O_upper": 1.05, "O_total": 5.05},
		{"m_upper": 0.0, "O_upper": 0.0, "O_total": 4.0, "E_upper": 1.0},
		{"m_upper": true}, {"O_upper": -0.000000000001}, {"O_total": 0.5}]:
		var wrong: Dictionary = _book()
		wrong.rooms.a.merge(change, true)
		_check(not Model.validate(wrong).is_empty(), "invalid physical state")
	for value: Variant in [null, [], {}, true]:
		_check(not Model.validate(value).is_empty(), "invalid book schema")
		_reject(base, value, "invalid event schema")
	var invalid_boundary: Dictionary = _parcel("ext", "", "", "a", "lower", 1.0)
	invalid_boundary.boundary.Y = 1.01
	_reject(base, _event(base, "outside", [invalid_boundary]), "outside composition")
	# Proposal and each receipt snapshot are independent copies.
	var isolated: Dictionary = Model.propose(base, _event(base, "alias", [packet]))
	if bool(isolated.get("valid", false)):
		isolated.book.rooms.a.O_upper = 0.0
		_near(isolated.receipt.after.rooms.a.O_upper, 0.9, "receipt isolated")
		isolated.receipt.event.packets[0].source.zone = "lower"
		_check(isolated.receipt.parcels[0].source.zone == "upper", "parcel snapshot isolated")
	_check(base == _book(), "inputs immutable")
	var sequence: Dictionary = _book()
	var iterations: int = 0
	if failures.is_empty():
		for index: int in range(256):
			var event: Dictionary = _event(sequence, "loop_%d" % index, [
				_parcel("u", "a", "lower", "a", "upper", 0.25),
				_parcel("l", "a", "upper", "a", "lower", 0.25)])
			var next: Dictionary = Model.propose(sequence, event)
			if not _audit(next, "sequence", false):
				break
			sequence = next.book
			iterations += 1
			_near(sequence.rooms.a.O_total, 5.0, "sequence oxygen conservation")
			_near(sequence.rooms.a.E_upper + sequence.rooms.a.E_lower, 500.0, "sequence energy conservation")
	_check(iterations == 256, "complete sequence")
	print("G3_O2_M4_PHYSICAL_PARCELS " + JSON.stringify({"checks": checks, "failure_count": failures.size(),
		"failures": failures, "samples": samples, "iterations": iterations}))
	quit(0 if failures.is_empty() else 1)
