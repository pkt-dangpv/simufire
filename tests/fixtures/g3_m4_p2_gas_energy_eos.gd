extends SceneTree

## M4-P2 isolated gas/energy/EOS fixture: imposed heat and parcels only, no engine.
## Cases, dt values and tolerances come from the predeclared plan JSON; nothing
## here may widen them. Receipts and final books are emitted for the independent
## Python oracle (scripts/simulation/audit_g3_m4_p2_gas_energy_eos.py).
const Model = preload("res://sim/core/PhysicalGasEnergyEosModel.gd")
const DetMath = preload("res://sim/core/DetMath.gd")
const PLAN_PATH: String = "res://docs/validation/G3_M4_P2_GAS_ENERGY_EOS_PLAN_2026-10-17.json"
const PREFIX: String = "G3_M4_P2_GAS_ENERGY_EOS"
const P_EXT: float = 101325.0
const T_AMB: float = 293.15
const Y_AIR: float = 0.2314

var plan: Dictionary = {}
var cases: Dictionary = {}
var exact: float = 0.0
var ident: float = 0.0
var floor_m: float = 0.0
var floor_e: float = 0.0
var floor_p: float = 0.0
var floor_t: float = 0.0
var floor_v: float = 0.0
var checks: int = 0
var failed_checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var rejections: Array[Dictionary] = []
var finals: Array[Dictionary] = []
var convergence: Dictionary = {}
var last_receipt: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed_checks += 1
		if not failures.has(label):
			failures.append(label)


func _close(actual: Variant, expected: Variant, rel: float, abs_floor: float) -> bool:
	if not (typeof(actual) in [TYPE_FLOAT, TYPE_INT]) or not (typeof(expected) in [TYPE_FLOAT, TYPE_INT]):
		return false
	var a: float = float(actual)
	var e: float = float(expected)
	return is_finite(a) and is_finite(e) and absf(a - e) <= maxf(rel * absf(e), abs_floor)


func _props(gas: Dictionary) -> Dictionary:
	var cp: float = float(gas["cp_kj_kg_k"])
	var r_gas: float = float(gas["R_kj_kg_k"])
	return {"cp": cp, "R": r_gas, "cv": cp - r_gas, "gamma": cp / (cp - r_gas), "k": r_gas / cp}


func _gas(name: String) -> Dictionary:
	var props: Dictionary = plan["property_sets"][name]
	return {"cp_kj_kg_k": float(props["cp"]), "R_kj_kg_k": float(props["R"])}


func _room(gas: Dictionary, initial: String) -> Dictionary:
	var spec: Dictionary = plan["initial_states"][initial]
	var geometry: Dictionary = plan["geometry"][spec["room"]]
	var props: Dictionary = _props(gas)
	var room: Dictionary = {"floor_area_m2": float(geometry["floor_area_m2"]), "height_m": float(geometry["height_m"])}
	for zone: String in Model.ZONES:
		var layer: Variant = spec["layers"].get(zone)
		if layer == null or layer["T_k"] == null or float(layer["volume_m3"]) == 0.0:
			room["m_" + zone] = 0.0
			room["U_" + zone] = 0.0
			room["O_" + zone] = 0.0
			continue
		var t_k: float = float(layer["T_k"])
		var m: float = float(spec["p_abs_pa"]) * float(layer["volume_m3"]) / (float(props["R"]) * 1000.0 * t_k)
		room["m_" + zone] = m
		room["U_" + zone] = m * float(props["cv"]) * t_k
		room["O_" + zone] = m * Y_AIR
	return room


func _book(gas: Dictionary, rooms: Dictionary, t_ref: float = T_AMB) -> Dictionary:
	return {"generation": 1, "step": 0, "revision": 0, "basis": Model.BASIS, "gas": gas.duplicate(true),
		"reference_temp_k": t_ref, "exterior_pressure_abs_pa": P_EXT, "rooms": rooms, "seen": []}


func _event(book: Dictionary, id: String, packets: Array, heat: Array = []) -> Dictionary:
	return {"id": id, "cause": "imposed_control", "generation": book["generation"], "step": book["step"],
		"revision": book["revision"], "basis": book["basis"], "expected_gas": book["gas"].duplicate(true),
		"expected_rooms": book["rooms"].duplicate(true), "packets": packets, "heat": heat}


func _end(room: String, zone: String) -> Dictionary:
	return {"room": room, "zone": zone}


func _heat(id: String, room: String, zone: String, energy_kj: Variant) -> Dictionary:
	return {"id": id, "target": _end(room, zone), "energy_kj": energy_kj}


func _transfer(id: String, sr: String, sz: String, tr: String, tz: String, q: Variant) -> Dictionary:
	return {"id": id, "kind": "transfer", "source": _end(sr, sz), "target": _end(tr, tz), "gas_kg": q, "boundary": null}


func _out(id: String, sr: String, sz: String, q: Variant) -> Dictionary:
	return {"id": id, "kind": "boundary_out", "source": _end(sr, sz), "target": null, "gas_kg": q, "boundary": null}


func _in(id: String, tr: String, tz: String, q: Variant, t_k: Variant = T_AMB, y: Variant = Y_AIR) -> Dictionary:
	return {"id": id, "kind": "boundary_in", "source": null, "target": _end(tr, tz), "gas_kg": q,
		"boundary": {"Y": y, "T_k": t_k}}


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


## Accept, audit independently, optionally keep the receipt for the oracle.
func _apply(book: Dictionary, event: Dictionary, label: String, sample: bool = false) -> Dictionary:
	var result: Dictionary = Model.propose(book, event)
	_check(bool(result.get("valid", false)), label + " accepted")
	if not bool(result.get("valid", false)):
		return {}
	_audit_receipt(result)
	last_receipt = result["receipt"]
	if sample:
		samples.append({"name": label, "receipt": result["receipt"].duplicate(true)})
	return result["book"]


func _audit_receipt(result: Dictionary) -> void:
	var receipt: Dictionary = result["receipt"]
	var before: Dictionary = receipt["before"]
	var after: Dictionary = receipt["after"]
	var event: Dictionary = receipt["event"]
	var gas: Dictionary = _props(before["gas"])
	_check(_same(result["book"], after), "receipt matches")
	_check(int(after["revision"]) == int(before["revision"]) + 1, "revision")
	_check(after["seen"].has(event["id"]), "seen")
	var ext: Dictionary = {}
	var d_mass: Dictionary = {}
	var d_oxygen: Dictionary = {}
	for room_id: String in before["rooms"]:
		ext[room_id] = 0.0
		for zone: String in Model.ZONES:
			d_mass[room_id + "/" + zone] = 0.0
			d_oxygen[room_id + "/" + zone] = 0.0
	var heat_total: float = 0.0
	for heat: Dictionary in event["heat"]:
		ext[heat["target"]["room"]] += float(heat["energy_kj"])
		heat_total += float(heat["energy_kj"])
	var h_in: float = 0.0
	var h_out: float = 0.0
	for parcel: Dictionary in receipt["parcels"]:
		var q: float = float(parcel["gas_kg"])
		var expected_h: float = 0.0
		var expected_o: float = 0.0
		if parcel["source"] != null:
			var donor: Dictionary = before["rooms"][parcel["source"]["room"]]
			var zone: String = parcel["source"]["zone"]
			var mass: float = float(donor["m_" + zone])
			if mass > 0.0:
				expected_h = q * float(gas["gamma"]) * float(donor["U_" + zone]) / mass
				expected_o = q * float(donor["O_" + zone]) / mass
			d_mass[parcel["source"]["room"] + "/" + zone] -= q
			d_oxygen[parcel["source"]["room"] + "/" + zone] -= expected_o
		else:
			for imposed: Dictionary in event["packets"]:
				if imposed["id"] == parcel["id"]:
					expected_h = q * float(gas["cp"]) * float(imposed["boundary"]["T_k"])
					expected_o = q * float(imposed["boundary"]["Y"])
		if parcel["target"] != null:
			d_mass[parcel["target"]["room"] + "/" + parcel["target"]["zone"]] += q
			d_oxygen[parcel["target"]["room"] + "/" + parcel["target"]["zone"]] += expected_o
		_check(_close(parcel["enthalpy_kj"], expected_h, ident, floor_e), "parcel snapshot enthalpy")
		_check(_close(parcel["oxygen_kg"], expected_o, ident, floor_m), "parcel snapshot oxygen")
		if parcel["kind"] == "transfer" and parcel["source"]["room"] != parcel["target"]["room"]:
			ext[parcel["source"]["room"]] -= expected_h
			ext[parcel["target"]["room"]] += expected_h
		elif parcel["kind"] == "boundary_in":
			ext[parcel["target"]["room"]] += expected_h
			h_in += expected_h
		elif parcel["kind"] == "boundary_out":
			ext[parcel["source"]["room"]] -= expected_h
			h_out += expected_h
	var du_building: float = 0.0
	var u_building: float = 0.0
	for room_id: String in before["rooms"]:
		var r0: Dictionary = before["rooms"][room_id]
		var r1: Dictionary = after["rooms"][room_id]
		var u0: float = float(r0["U_upper"]) + float(r0["U_lower"])
		var u1: float = float(r1["U_upper"]) + float(r1["U_lower"])
		u_building += u0
		du_building += u1 - u0
		var scale: float = ident * u0 + floor_e
		_check(absf((u1 - u0) - float(ext[room_id])) <= scale, "energy closure")
		var rows: Dictionary = receipt["rooms"][room_id]["layers"]
		_check(absf(float(rows["upper"]["W_kj"]) + float(rows["lower"]["W_kj"])) <= scale, "work antisymmetric")
		for zone: String in Model.ZONES:
			var key: String = room_id + "/" + zone
			_check(absf(float(r1["m_" + zone]) - float(r0["m_" + zone]) - float(d_mass[key]))
				<= ident * (float(r0["m_upper"]) + float(r0["m_lower"])) + floor_m, "paired gas")
			_check(absf(float(r1["O_" + zone]) - float(r0["O_" + zone]) - float(d_oxygen[key]))
				<= ident * (float(r0["O_upper"]) + float(r0["O_lower"])) + floor_m, "paired oxygen")
	var receipt_in: float = float(receipt["boundary"]["H_in_kj"])
	var receipt_out: float = float(receipt["boundary"]["H_out_kj"])
	var tolerance: float = ident * u_building + floor_e
	_check(absf(du_building - (heat_total + receipt_in - receipt_out)) <= tolerance, "building balance")
	_check(absf(receipt_in - h_in) <= tolerance and absf(receipt_out - h_out) <= tolerance, "building balance")
	_check_identities(after)


## Independent EOS identities on the candidate book.
func _check_identities(book: Dictionary) -> void:
	var gas: Dictionary = _props(book["gas"])
	var obs: Dictionary = Model.observables(book)
	_check(bool(obs.get("valid", false)), "observables valid")
	if not bool(obs.get("valid", false)):
		return
	for room_id: String in book["rooms"]:
		var room: Dictionary = book["rooms"][room_id]
		var view: Dictionary = obs["rooms"][room_id]
		var volume: float = float(room["floor_area_m2"]) * float(room["height_m"])
		var u_room: float = float(room["U_upper"]) + float(room["U_lower"])
		var p_fix: float = (float(gas["gamma"]) - 1.0) * u_room / volume * 1000.0
		_check(_close(view["p_abs_pa"], p_fix, ident, floor_p), "EOS pressure")
		var v_sum: float = 0.0
		var rt: float = 0.0
		for zone: String in Model.ZONES:
			var m: float = float(room["m_" + zone])
			var layer: Dictionary = view["layers"][zone]
			v_sum += float(layer["V_m3"])
			if m > 0.0:
				var t_fix: float = float(room["U_" + zone]) / (m * float(gas["cv"]))
				_check(_close(layer["T_k"], t_fix, ident, floor_t), "EOS temperature")
				rt += m * float(gas["R"]) * 1000.0 * t_fix
			else:
				_check(layer["T_k"] == null and float(layer["V_m3"]) == 0.0, "EOS absent layer")
		_check(_close(v_sum, volume, ident, floor_v), "EOS volume closure")
		_check(_close(p_fix * volume, rt, ident, floor_p), "EOS identity")
		var interface: float = float(view["interface_m"])
		_check(interface >= -floor_v and interface <= float(room["height_m"]) + floor_v, "EOS interface")


func _reject(book: Variant, event: Variant, reason: String, label: String, for_oracle: bool = false) -> void:
	var book_before: Variant = book.duplicate(true) if typeof(book) == TYPE_DICTIONARY else book
	var event_before: Variant = event.duplicate(true) if typeof(event) == TYPE_DICTIONARY else event
	var result: Dictionary = Model.propose(book, event)
	_check(not bool(result.get("valid", true)), label + " rejected")
	_check(String(result.get("reason", "")) == reason, label + " reason " + reason)
	_check(not result.has("book") and not result.has("receipt"), label + " no proposal")
	_check(_same(book, book_before) and _same(event, event_before), label + " unchanged")
	if for_oracle:
		rejections.append({"name": label, "reason": reason, "book": book_before, "event": event_before})


# --- sealed heater cases ------------------------------------------------------

func _closed_form(gas: Dictionary, u_layers: Dictionary, a_kw: Dictionary, t_s: float) -> Dictionary:
	var props: Dictionary = _props(gas)
	var u0: float = float(u_layers["upper"]) + float(u_layers["lower"])
	var a_total: float = float(a_kw.get("upper", 0.0)) + float(a_kw.get("lower", 0.0))
	var u1: float = u0 + a_total * t_s
	var s_k: float = DetMath.pow(u1 / u0, float(props["k"]))
	var out: Dictionary = {"U": u1}
	for zone: String in Model.ZONES:
		out[zone] = s_k * float(u_layers[zone]) + float(a_kw.get(zone, 0.0)) / a_total * (u1 - u0 * s_k)
	return out


func _run_heater(case_id: String, props_name: String, initial: String, heat_kw: Dictionary,
		t_end: float, dt: float) -> Dictionary:
	var gas: Dictionary = _gas(props_name)
	var book: Dictionary = _book(gas, {"A": _room(gas, initial)})
	var start: Dictionary = book.duplicate(true)
	var n: int = int(round(t_end / dt))
	_check(absf(float(n) * dt - t_end) < 1.0e-9, case_id + " step count")
	var label: String = "%s %s dt=%s" % [case_id, props_name, str(dt)]
	for i: int in range(n):
		var heat: Array = []
		for zone: String in heat_kw:
			heat.append(_heat("h%d_%s" % [i, zone], "A", zone, float(heat_kw[zone]) * dt))
		book = _apply(book, _event(book, "e%d" % i, [], heat), label, i == 0 or i == n - 1)
		if book.is_empty():
			return {}
	finals.append({"case": case_id, "props": props_name, "dt": dt, "initial": start, "final": book})
	return {"initial": start, "final": book}


func _sealed_cases() -> void:
	for case_id: String in ["C1", "C2", "C3"]:
		var case: Dictionary = cases[case_id]
		for props_name: String in case["property_sets"]:
			var gas: Dictionary = _gas(props_name)
			var props: Dictionary = _props(gas)
			var room0: Dictionary = _room(gas, case["initial"])
			var u0: Dictionary = {"upper": room0["U_upper"], "lower": room0["U_lower"]}
			var expected: Dictionary = _closed_form(gas, u0, case["heat_kw"], float(case["t_end_s"]))
			var volume: float = float(room0["floor_area_m2"]) * float(room0["height_m"])
			var p_expected: float = (float(props["gamma"]) - 1.0) * float(expected["U"]) / volume * 1000.0
			var kept: Array[Dictionary] = []
			for dt: Variant in case["dt_s"]:
				var run: Dictionary = _run_heater(case_id, props_name, case["initial"], case["heat_kw"],
					float(case["t_end_s"]), float(dt))
				if run.is_empty():
					continue
				var room: Dictionary = run["final"]["rooms"]["A"]
				var view: Dictionary = Model.observables(run["final"])["rooms"]["A"]
				for zone: String in Model.ZONES:
					_check(float(room["m_" + zone]) == float(room0["m_" + zone]), case_id + " mass bitwise")
					_check(_close(room["U_" + zone], expected[zone], exact, floor_e), case_id + " U")
					if float(room0["m_" + zone]) > 0.0:
						var t_z: float = float(expected[zone]) / (float(room0["m_" + zone]) * float(props["cv"]))
						_check(_close(view["layers"][zone]["T_k"], t_z, exact, floor_t), case_id + " T_z")
						var v_z: float = volume * float(expected[zone]) / float(expected["U"])
						_check(_close(view["layers"][zone]["V_m3"], v_z, exact, floor_v), case_id + " V_z")
				var v_lower: float = volume * float(expected["lower"]) / float(expected["U"])
				_check(_close(view["interface_m"], v_lower / float(room0["floor_area_m2"]), exact, floor_v), case_id + " interface")
				_check(_close(view["p_abs_pa"], p_expected, exact, floor_p), case_id + " p")
				if case_id == "C1":
					var t_expected: float = T_AMB + float(case["heat_kw"]["lower"]) * float(case["t_end_s"]) \
						/ (float(room0["m_lower"]) * float(props["cv"]))
					_check(_close(view["layers"]["lower"]["T_k"], t_expected, exact, floor_t), "C1 T")
				if case_id == "C2":
					var view0: Dictionary = Model.observables(run["initial"])["rooms"]["A"]
					var theta0: float = float(view0["layers"]["lower"]["T_k"]) \
						* DetMath.pow(P_EXT / float(view0["p_abs_pa"]), float(props["k"]))
					var theta1: float = float(view["layers"]["lower"]["T_k"]) \
						* DetMath.pow(P_EXT / float(view["p_abs_pa"]), float(props["k"]))
					_check(_close(theta1, theta0, exact, floor_t), "C2 isentrope")
					_check(float(room["U_lower"]) > float(room0["U_lower"]), "C2 work lower positive")
					_check(float(view["interface_m"]) < float(view0["interface_m"]), "C2 interface")
				kept.append(room)
			for zone: String in Model.ZONES:
				for room: Dictionary in kept:
					_check(_close(room["U_" + zone], kept[0]["U_" + zone], float(plan["tolerances"]["step_independence_relative"]),
						floor_e), case_id + " step independence")


func _c4_c5() -> void:
	var gas: Dictionary = _gas("engine_equivalent_293_15")
	var props: Dictionary = _props(gas)
	var c4: Dictionary = cases["C4"]
	var room0: Dictionary = _room(gas, c4["initial"])
	var expected: Dictionary = _closed_form(gas, {"upper": room0["U_upper"], "lower": room0["U_lower"]},
		c4["heat_kw"], float(c4["t_end_s"]))
	var p_expected: float = (float(props["gamma"]) - 1.0) * float(expected["U"]) / 50.0 * 1000.0
	for dt: Variant in c4["dt_s"]:
		var run: Dictionary = _run_heater("C4", "engine_equivalent_293_15", c4["initial"], c4["heat_kw"],
			float(c4["t_end_s"]), float(dt))
		if run.is_empty():
			continue
		var view: Dictionary = Model.observables(run["final"])["rooms"]["A"]
		_check(_close(run["final"]["rooms"]["A"]["U_lower"], expected["lower"], exact, floor_e), "C4 U")
		_check(_close(view["layers"]["lower"]["T_k"], float(expected["lower"]) / (float(room0["m_lower"]) * float(props["cv"])),
			exact, floor_t), "C4 T")
		_check(_close(view["p_abs_pa"], p_expected, exact, floor_p), "C4 p")
		_check(float(view["p_gauge_pa"]) < -1000.0, "C4 gauge negative")
	var c5: Dictionary = cases["C5"]
	room0 = _room(gas, c5["initial"])
	var p0: float = (float(props["gamma"]) - 1.0) * (float(room0["U_upper"]) + float(room0["U_lower"])) / 50.0 * 1000.0
	var kept5: Array[Dictionary] = []
	for dt: Variant in c5["dt_s"]:
		var run: Dictionary = _run_heater("C5", "engine_equivalent_293_15", c5["initial"], c5["heat_kw"],
			float(c5["t_end_s"]), float(dt))
		if run.is_empty():
			continue
		var room: Dictionary = run["final"]["rooms"]["A"]
		_check(_close(Model.observables(run["final"])["rooms"]["A"]["p_abs_pa"], p0, exact, floor_p), "C5 p")
		for zone: String in Model.ZONES:
			var a_t: float = float(c5["heat_kw"][zone]) * float(c5["t_end_s"])
			_check(_close(room["U_" + zone], float(room0["U_" + zone]) + a_t / float(props["gamma"]), exact, floor_e), "C5 U")
			var h_z: float = float(props["gamma"]) * float(room["U_" + zone])
			_check(_close(h_z, float(props["gamma"]) * float(room0["U_" + zone]) + a_t, exact, floor_e), "C5 H")
		kept5.append(room)
	_step_independence("C5", kept5, ["U_upper", "U_lower"])


func _step_independence(case_id: String, kept: Array[Dictionary], fields: Array) -> void:
	_check(kept.size() >= 2, case_id + " step independence")
	for room: Dictionary in kept:
		for field: String in fields:
			_check(_close(room[field], kept[0][field], float(plan["tolerances"]["step_independence_relative"]),
				floor_m if field.begins_with("m_") or field.begins_with("O_") else floor_e), case_id + " step independence")


# --- parcels -----------------------------------------------------------------

func _run_parcels(_case_id: String, book: Dictionary, make: Callable, n: int, sample_label: String) -> Dictionary:
	for i: int in range(n):
		book = _apply(book, make.call(book, i), sample_label, i == 0 or i == n - 1)
		if book.is_empty():
			return {}
	return book


func _parcel_cases() -> void:
	var gas: Dictionary = _gas("engine_equivalent_293_15")
	var props: Dictionary = _props(gas)
	# C6 isobaric plume mixing.
	var c6: Dictionary = cases["C6"]
	var rate: float = float(c6["parcels_kg_s"][0]["rate"])
	var room0: Dictionary = _room(gas, c6["initial"])
	var t_u0: float = float(room0["U_upper"]) / (float(room0["m_upper"]) * float(props["cv"]))
	var q_total: float = rate * float(c6["t_end_s"])
	var t_mix: float = (float(room0["m_upper"]) * t_u0 + q_total * T_AMB) / (float(room0["m_upper"]) + q_total)
	var o_upper: float = float(room0["O_upper"]) + q_total * float(room0["O_lower"]) / float(room0["m_lower"])
	var p0: float = (float(props["gamma"]) - 1.0) * (float(room0["U_upper"]) + float(room0["U_lower"])) / 50.0 * 1000.0
	var kept6: Array[Dictionary] = []
	for dt: Variant in c6["dt_s"]:
		var start: Dictionary = _book(gas, {"A": room0.duplicate(true)})
		var step_q: float = rate * float(dt)
		var make: Callable = func(b: Dictionary, i: int) -> Dictionary:
			return _event(b, "e%d" % i, [_transfer("p%d" % i, "A", "lower", "A", "upper", step_q)])
		var final: Dictionary = _run_parcels("C6", start, make, int(round(float(c6["t_end_s"]) / float(dt))), "C6 dt=%s" % str(dt))
		if final.is_empty():
			continue
		finals.append({"case": "C6", "props": "engine_equivalent_293_15", "dt": float(dt), "initial": start, "final": final})
		var view: Dictionary = Model.observables(final)["rooms"]["A"]
		_check(_close(view["p_abs_pa"], p0, exact, floor_p), "C6 p")
		_check(_close(view["layers"]["lower"]["T_k"], T_AMB, exact, floor_t), "C6 T lower")
		_check(_close(view["layers"]["upper"]["T_k"], t_mix, exact, floor_t), "C6 T upper mixing")
		_check(_close(final["rooms"]["A"]["O_upper"], o_upper, exact, floor_m), "C6 O2")
		kept6.append(final["rooms"]["A"])
	_step_independence("C6", kept6, ["m_upper", "m_lower", "U_upper", "U_lower", "O_upper", "O_lower"])
	# C8 adiabatic filling.
	var c8: Dictionary = cases["C8"]
	var inflow: Dictionary = c8["parcels_kg_s"][0]
	room0 = _room(gas, c8["initial"])
	var q8: float = float(inflow["rate"]) * float(c8["t_end_s"])
	var u_expected: float = float(room0["U_lower"]) + q8 * float(props["cp"]) * float(inflow["T_ext_k"])
	var kept8: Array[Dictionary] = []
	for dt: Variant in c8["dt_s"]:
		var start: Dictionary = _book(gas, {"A": room0.duplicate(true)})
		var step_q: float = float(inflow["rate"]) * float(dt)
		var make: Callable = func(b: Dictionary, i: int) -> Dictionary:
			return _event(b, "e%d" % i, [_in("p%d" % i, "A", "lower", step_q, float(inflow["T_ext_k"]), float(inflow["Y_O2_ext"]))])
		var final: Dictionary = _run_parcels("C8", start, make, int(round(float(c8["t_end_s"]) / float(dt))), "C8 dt=%s" % str(dt))
		if final.is_empty():
			continue
		finals.append({"case": "C8", "props": "engine_equivalent_293_15", "dt": float(dt), "initial": start, "final": final})
		_check(_close(final["rooms"]["A"]["U_lower"], u_expected, exact, floor_e), "C8 U")
		_check(_close(final["rooms"]["A"]["m_lower"], float(room0["m_lower"]) + q8, exact, floor_m), "C8 mass")
		_check(float(Model.observables(final)["rooms"]["A"]["layers"]["lower"]["T_k"]) > float(inflow["T_ext_k"]) + 1.0, "C8 T rises")
		_check(_close(final["rooms"]["A"]["O_lower"], float(room0["O_lower"]) + q8 * float(inflow["Y_O2_ext"]), exact, floor_m), "C8 O2 inflow")
		kept8.append(final["rooms"]["A"])
	_step_independence("C8", kept8, ["m_lower", "U_lower", "O_lower"])
	# C10a birth of the upper layer from a plume parcel.
	var c10a: Dictionary = cases["C10a"]
	room0 = _room(gas, c10a["initial"])
	_check(float(room0["m_upper"]) == 0.0, "C10a absent start")
	for dt: Variant in c10a["dt_s"]:
		var start: Dictionary = _book(gas, {"A": room0.duplicate(true)})
		var step_q: float = float(c10a["parcels_kg_s"][0]["rate"]) * float(dt)
		var make: Callable = func(b: Dictionary, i: int) -> Dictionary:
			return _event(b, "e%d" % i, [_transfer("p%d" % i, "A", "lower", "A", "upper", step_q)])
		var final: Dictionary = _run_parcels("C10a", start, make, int(round(float(c10a["t_end_s"]) / float(dt))), "C10a dt=%s" % str(dt))
		if final.is_empty():
			continue
		var view: Dictionary = Model.observables(final)["rooms"]["A"]
		_check(_close(view["p_abs_pa"], P_EXT, exact, floor_p), "C10a p")
		_check(_close(view["layers"]["upper"]["T_k"], T_AMB, exact, floor_t), "C10a T upper")
	# C10b full depletion at constant pressure: exact zero.
	room0 = _room(gas, cases["C10b"]["initial"])
	var base: Dictionary = _book(gas, {"A": room0})
	var drained: Dictionary = _apply(base, _event(base, "all", [_transfer("all", "A", "lower", "A", "upper", room0["m_lower"])]),
		"C10b", true)
	if not drained.is_empty():
		var lower: Dictionary = {"m": drained["rooms"]["A"]["m_lower"], "U": drained["rooms"]["A"]["U_lower"],
			"O": drained["rooms"]["A"]["O_lower"]}
		_check(float(lower["m"]) == 0.0 and float(lower["U"]) == 0.0 and float(lower["O"]) == 0.0, "C10b exact zero")
		_check(_close(Model.observables(drained)["rooms"]["A"]["p_abs_pa"], Model.observables(base)["rooms"]["A"]["p_abs_pa"],
			exact, floor_p), "C10b p")
	# C10c depletion while the pressure changes, plain and refilled.
	_reject(base, _event(base, "c10c", [_transfer("all", "A", "lower", "A", "upper", room0["m_lower"])],
		[_heat("q", "A", "upper", 10.0)]), "layer_depleted_while_pressure_changes", "C10c", true)
	_reject(base, _event(base, "c10c refill", [_transfer("all", "A", "lower", "A", "upper", room0["m_lower"]),
		_in("refill", "A", "lower", 1.0)], [_heat("q", "A", "upper", 10.0)]),
		"layer_depleted_while_pressure_changes", "C10c refill", true)
	# Two parcels from the same donor carry the SAME snapshot enthalpy per kg.
	var two: Dictionary = _apply(base, _event(base, "two", [_transfer("a", "A", "lower", "A", "upper", 1.0),
		_out("b", "A", "lower", 2.0)]), "parcel snapshot", true)
	if not two.is_empty():
		var receipt_parcels: Array = samples[samples.size() - 1]["receipt"]["parcels"]
		_check(_close(float(receipt_parcels[1]["enthalpy_kj"]) / 2.0, float(receipt_parcels[0]["enthalpy_kj"]), ident, floor_e),
			"parcel snapshot same donor")


# --- convergence --------------------------------------------------------------

func _orders(errors: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for i: int in range(errors.size() - 1):
		out.append(DetMath.log(errors[i] / errors[i + 1]) / DetMath.log(2.0))
	return out


func _convergence_cases() -> void:
	var gas: Dictionary = _gas("engine_equivalent_293_15")
	var props: Dictionary = _props(gas)
	var band: Array = plan["tolerances"]["convergence_order_band"]
	# C7 vented heater with harness-side isobaric relief.
	var c7: Dictionary = cases["C7"]
	var q_kw: float = float(c7["heat_kw"]["lower"])
	var t_end: float = float(c7["t_end_s"])
	var exact7: float = T_AMB * DetMath.exp(float(props["R"]) * q_kw * t_end
		/ (float(props["cp"]) * P_EXT / 1000.0 * 50.0))
	var errors7: Array[float] = []
	var report7: Dictionary = {}
	var temps7: Dictionary = {}
	for dt: Variant in c7["dt_s"] + c7["report_dt_s"]:
		var book: Dictionary = _book(gas, {"A": _room(gas, c7["initial"])})
		var u_target: float = P_EXT * 50.0 / 1000.0 / (float(props["gamma"]) - 1.0)
		var n: int = int(round(t_end / float(dt)))
		var h_out_total: float = 0.0
		for i: int in range(n):
			var room: Dictionary = book["rooms"]["A"]
			var h0: float = float(props["gamma"]) * float(room["U_lower"]) / float(room["m_lower"])
			var q: float = (float(room["U_lower"]) + q_kw * float(dt) - u_target) / h0
			book = _apply(book, _event(book, "e%d" % i, [_out("r%d" % i, "A", "lower", q)],
				[_heat("h%d" % i, "A", "lower", q_kw * float(dt))]), "C7 dt=%s" % str(dt), i == 0 or i == n - 1)
			if book.is_empty():
				break
			_check(_close(Model.observables(book)["rooms"]["A"]["p_abs_pa"], P_EXT, ident, floor_p), "C7 isobaric")
			_check(_close(book["rooms"]["A"]["U_lower"], u_target, ident, floor_e), "C7 U constant")
			h_out_total += float(last_receipt["boundary"]["H_out_kj"])
		if book.is_empty():
			return
		_check(_close(h_out_total, q_kw * t_end, exact, floor_e), "C7 outflow enthalpy")
		var t_final: float = float(Model.observables(book)["rooms"]["A"]["layers"]["lower"]["T_k"])
		var err: float = absf(t_final - exact7) / exact7
		report7[str(dt)] = err
		temps7[str(dt)] = t_final
		if c7["dt_s"].has(dt):
			errors7.append(err)
	convergence["C7"] = {"T_exact_k": exact7, "rel_err": report7, "T_final_k": temps7, "orders": _orders(errors7)}
	for i: int in range(errors7.size() - 1):
		_check(errors7[i] > errors7[i + 1], "C7 error decreasing")
	for order: float in _orders(errors7):
		_check(order >= float(band[0]) and order <= float(band[1]), "C7 order")
	# C9 adiabatic blowdown.
	var c9: Dictionary = cases["C9"]
	var frac: float = float(c9["parcels_kg_s"][0]["rate_fraction_of_m0_per_s"])
	var errors9: Array[float] = []
	var report9: Dictionary = {}
	var temps9: Dictionary = {}
	for dt: Variant in c9["dt_s"] + c9["report_dt_s"]:
		var book: Dictionary = _book(gas, {"A": _room(gas, c9["initial"])})
		var m0: float = float(book["rooms"]["A"]["m_lower"])
		var q: float = frac * m0 * float(dt)
		var n: int = int(round(float(c9["t_end_s"]) / float(dt)))
		for i: int in range(n):
			book = _apply(book, _event(book, "e%d" % i, [_out("b%d" % i, "A", "lower", q)]),
				"C9 dt=%s" % str(dt), i == 0 or i == n - 1)
			if book.is_empty():
				break
		if book.is_empty():
			return
		var room: Dictionary = book["rooms"]["A"]
		var t_final: float = float(room["U_lower"]) / (float(room["m_lower"]) * float(props["cv"]))
		var exact9: float = T_AMB * DetMath.pow(float(room["m_lower"]) / m0, float(props["gamma"]) - 1.0)
		var err: float = absf(t_final - exact9) / exact9
		report9[str(dt)] = err
		temps9[str(dt)] = t_final
		if c9["dt_s"].has(dt):
			errors9.append(err)
	convergence["C9"] = {"rel_err": report9, "T_final_k": temps9, "orders": _orders(errors9)}
	for i: int in range(errors9.size() - 1):
		_check(errors9[i] > errors9[i + 1], "C9 error decreasing")
	for order: float in _orders(errors9):
		_check(order >= float(band[0]) and order <= float(band[1]), "C9 order")


# --- C11 and C13 ------------------------------------------------------------------

func _c11_c13() -> void:
	var gas: Dictionary = _gas("engine_equivalent_293_15")
	var r_values: Array[float] = []
	var gamma_values: Array[float] = []
	for ambient: Variant in cases["C11"]["ambient_k"]:
		var t_ref: float = float(ambient)
		var room: Dictionary = {"floor_area_m2": 20.0, "height_m": 2.5}
		var props: Dictionary = _props(gas)
		var m: float = P_EXT * 50.0 / (float(props["R"]) * 1000.0 * t_ref)
		room.merge({"m_upper": 0.0, "U_upper": 0.0, "O_upper": 0.0, "m_lower": m,
			"U_lower": m * float(props["cv"]) * t_ref, "O_lower": m * Y_AIR})
		var obs: Dictionary = Model.observables(_book(gas, {"A": room}, t_ref))
		_check(bool(obs.get("valid", false)), "C11 valid")
		if not bool(obs.get("valid", false)):
			continue
		r_values.append(float(obs["gas"]["R"]))
		gamma_values.append(float(obs["gas"]["gamma"]))
		_check(_close(obs["rooms"]["A"]["layers"]["lower"]["T_k"], t_ref, ident, floor_t), "C11 T")
		_check(absf(float(obs["rooms"]["A"]["layers"]["lower"]["E_sensible_kj"])) <= ident * m * t_ref + floor_e, "C11 sensible zero")
	for value: float in r_values:
		_check(value == float(plan["property_sets"]["engine_equivalent_293_15"]["R"]), "C11 R")
	for value: float in gamma_values:
		_check(value == gamma_values[0], "C11 gamma")
	var legacy: Array[float] = []
	for ambient: Variant in cases["C11"]["ambient_k"]:
		legacy.append(P_EXT / (1.2 * float(ambient)) / 1000.0)
	_check((legacy.max() - legacy.min()) / legacy[1] > 0.03, "C11 legacy R varies")
	# C13 two sealed rooms, heater and transfer.
	var c13: Dictionary = cases["C13"]
	var rate: float = float(c13["parcels_kg_s"][0]["rate"])
	var heat_kw: float = float(c13["heat_kw"]["room_A.upper"])
	for dt: Variant in c13["dt_s"]:
		var book: Dictionary = _book(gas, {"A": _room(gas, "two_layer_hot_upper"), "B": _room(gas, "room_B_ambient")})
		var n: int = int(round(float(c13["t_end_s"]) / float(dt)))
		for i: int in range(n):
			var m_before: float = 0.0
			var u_before: float = 0.0
			for room: Dictionary in book["rooms"].values():
				m_before += float(room["m_upper"]) + float(room["m_lower"])
				u_before += float(room["U_upper"]) + float(room["U_lower"])
			book = _apply(book, _event(book, "e%d" % i, [_transfer("t%d" % i, "A", "upper", "B", "lower", rate * float(dt))],
				[_heat("h%d" % i, "A", "upper", heat_kw * float(dt))]), "C13 dt=%s" % str(dt), i == 0 or i == n - 1)
			if book.is_empty():
				break
			var m_after: float = 0.0
			var u_after: float = 0.0
			for room: Dictionary in book["rooms"].values():
				m_after += float(room["m_upper"]) + float(room["m_lower"])
				u_after += float(room["U_upper"]) + float(room["U_lower"])
			_check(absf(m_after - m_before) <= ident * m_before + floor_m, "C13 building mass")
			_check(absf((u_after - u_before) - heat_kw * float(dt)) <= ident * u_before + floor_e, "C13 building energy")


# --- scope of the recorded discrepancies -------------------------------------------

func _scope_cases() -> void:
	var gas: Dictionary = _gas("engine_equivalent_293_15")
	var base: Dictionary = _book(gas, {"A": _room(gas, "two_layer_hot_upper")})
	var plain: Array = [_transfer("p", "A", "lower", "A", "upper", 1.0)]
	# D5: reference_temp_k feeds only the sensible-enthalpy observable, never the state.
	var heated: Dictionary = {}
	for t_ref: float in [283.15, 293.15, 303.15]:
		var book: Dictionary = _book(gas, {"A": _room(gas, "two_layer_hot_upper")}, t_ref)
		var result: Dictionary = Model.propose(book, _event(book, "tref", plain, [_heat("h", "A", "upper", 10.0)]))
		_check(bool(result.get("valid", false)), "D5 T_ref inert")
		if bool(result.get("valid", false)):
			if heated.is_empty():
				heated = result["book"]["rooms"]
			_check(_same(result["book"]["rooms"], heated), "D5 T_ref inert")
	# D6: two exteriors in one event, audited here per parcel (the oracle takes one).
	_apply(base, _event(base, "two exteriors", [_in("cold", "A", "lower", 0.5, 263.15, 0.2314),
		_in("warm", "A", "upper", 0.5, 313.15, 0.21)]), "D6 two exteriors")
	# D7: two heat entries on one layer act as their sum (the oracle keys heat by layer).
	var twice: Dictionary = _apply(base, _event(base, "twice", [], [_heat("h1", "A", "upper", 4.0),
		_heat("h2", "A", "upper", 6.0)]), "D7 heat sum", true)
	var once: Dictionary = _apply(base, _event(base, "once", [], [_heat("h", "A", "upper", 10.0)]), "D7 heat once")
	if not twice.is_empty() and not once.is_empty():
		_check(_same(twice["rooms"], once["rooms"]), "D7 heat sum")
	# F1: full depletion at constant pressure leaves exact zero O2 as well. With m = 36 kg
	# and Y = 0.21, (q*O)/m differs from O by one ulp.
	var room: Dictionary = _room(gas, "two_layer_hot_upper")
	room["O_lower"] = float(room["m_lower"]) * 0.21
	var drain: Dictionary = _book(gas, {"A": room})
	var emptied: Dictionary = _apply(drain, _event(drain, "drain", [_transfer("all", "A", "lower", "A", "upper",
		room["m_lower"])]), "C10b O2 rounding", true)
	if not emptied.is_empty():
		var after: Dictionary = emptied["rooms"]["A"]
		_check(float(after["m_lower"]) == 0.0 and float(after["U_lower"]) == 0.0 and float(after["O_lower"]) == 0.0,
			"C10b O2 rounding exact zero")
		_check(_close(after["O_upper"], float(room["O_upper"]) + float(room["O_lower"]), ident, floor_m),
			"C10b O2 rounding conserved")


# --- rejections, isolation and replay -----------------------------------------------

func _rejection_cases() -> void:
	var gas: Dictionary = _gas("engine_equivalent_293_15")
	var base: Dictionary = _book(gas, {"A": _room(gas, "two_layer_hot_upper")})
	var m_lower: float = float(base["rooms"]["A"]["m_lower"])
	var u_room: float = float(base["rooms"]["A"]["U_upper"]) + float(base["rooms"]["A"]["U_lower"])
	var plain: Array = [_transfer("p", "A", "lower", "A", "upper", 1.0)]
	for bad: Variant in [NAN, INF, true, "1"]:
		var wrong: Dictionary = base.duplicate(true)
		wrong["gas"]["cp_kj_kg_k"] = bad
		_check(Model.validate(wrong) == "non_finite_or_bool_number", "R non_finite_or_bool_number")
		_reject(base, _event(base, "q", [_transfer("p", "A", "lower", "A", "upper", bad)]),
			"non_finite_or_bool_number", "R non_finite_or_bool_number")
	var bad_heat: Dictionary = _event(base, "nan heat", [], [_heat("h", "A", "upper", NAN)])
	_reject(base, bad_heat, "non_finite_or_bool_number", "R non_finite_or_bool_number")
	var gas_cases: Array = [[{"cp_kj_kg_k": 0.28, "R_kj_kg_k": 0.288}, "cp_not_greater_than_R"],
		[{"cp_kj_kg_k": 1.0, "R_kj_kg_k": 0.0}, "R_not_positive"]]
	for item: Array in gas_cases:
		var wrong: Dictionary = base.duplicate(true)
		wrong["gas"] = item[0]
		_check(Model.validate(wrong) == item[1], "R " + String(item[1]))
		_reject(wrong, _event(wrong, "bad gas", plain), item[1], "R " + String(item[1]))
	var state_cases: Array = [[{"m_lower": -1.0}, "negative_mass"], [{"U_lower": -1.0}, "negative_internal_energy"],
		[{"m_lower": 0.0}, "energy_without_mass"], [{"U_lower": 0.0}, "mass_without_energy"],
		[{"floor_area_m2": 0.0}, "non_positive_volume"], [{"O_lower": m_lower * 1.01}, "o2_out_of_range"],
		[{"m_upper": 0.0, "U_upper": 0.0, "O_upper": 0.0, "m_lower": 0.0, "U_lower": 0.0, "O_lower": 0.0}, "room_without_gas"]]
	for item: Array in state_cases:
		var wrong: Dictionary = base.duplicate(true)
		wrong["rooms"]["A"].merge(item[0], true)
		_check(Model.validate(wrong) == item[1], "R " + String(item[1]))
		_reject(wrong, _event(wrong, "bad state", plain), item[1], "R " + String(item[1]))
	_reject(base, _event(base, "neg", [_transfer("p", "A", "lower", "A", "upper", -1.0e-12)]), "negative_mass", "R negative_mass")
	_reject(base, _event(base, "over", [_out("x", "A", "lower", 1.0e9)]), "overdraft_of_donor", "R overdraft_of_donor", true)
	_reject(base, _event(base, "finance", [_in("in", "A", "lower", 5.0), _out("out", "A", "lower", m_lower + 1.0)]),
		"inflow_financing_outflow", "R inflow_financing_outflow", true)
	_reject(base, _event(base, "cold", [_in("in", "A", "lower", 1.0, 0.0)]), "non_positive_exterior_temperature",
		"R non_positive_exterior_temperature", true)
	_reject(base, _event(base, "rich", [_in("in", "A", "lower", 1.0, T_AMB, 1.01)]), "exterior_o2_fraction_out_of_range",
		"R exterior_o2_fraction_out_of_range", true)
	for field: String in ["generation", "step", "revision"]:
		var wrong: Dictionary = _event(base, "ctx", plain)
		wrong[field] = int(base[field]) + 1
		_reject(base, wrong, "stale_context_or_revision", "R stale_context_or_revision")
	var stale: Dictionary = _event(base, "stale", plain)
	stale["expected_rooms"]["A"]["U_upper"] = float(stale["expected_rooms"]["A"]["U_upper"]) * 0.999
	_reject(base, stale, "stale_context_or_revision", "R stale_context_or_revision")
	var moved: Dictionary = _event(base, "moved", plain)
	moved["expected_rooms"]["A"]["height_m"] = 2.6
	_reject(base, moved, "geometry_changed_within_run", "R geometry_changed_within_run")
	var swapped: Dictionary = _event(base, "swapped", plain)
	swapped["expected_gas"]["cp_kj_kg_k"] = 1.012
	_reject(base, swapped, "property_set_changed_within_run", "R property_set_changed_within_run")
	_reject(base, _event(base, "dup", [_transfer("p", "A", "lower", "A", "upper", 1.0),
		_transfer("p", "A", "lower", "A", "upper", 1.0)]), "duplicate_event_or_parcel", "R duplicate_event_or_parcel", true)
	var absent: Dictionary = _book(gas, {"A": _room(gas, "upper_absent")})
	_reject(absent, _event(absent, "absent heat", [], [_heat("h", "A", "upper", 5.0)]),
		"heat_into_absent_layer_without_mass", "R heat_into_absent_layer_without_mass", true)
	_reject(base, _event(base, "freeze", [], [_heat("h", "A", "upper", -2.0 * u_room)]),
		"room_energy_non_positive_after_step", "R room_energy_non_positive_after_step", true)
	_reject(base, _event(base, "cold layer", [], [_heat("h", "A", "upper", -0.9 * u_room)]),
		"layer_energy_negative_after_step", "R layer_energy_negative_after_step", true)
	_reject(base, _event(base, "empty", []), "event_empty", "R event_empty")
	for value: Variant in [null, [], {}, true]:
		_check(not Model.validate(value).is_empty(), "R book_schema")
		_reject(base, value, "event_schema", "R event_schema")
	# Replay: the same event id never applies twice.
	var once: Dictionary = _apply(base, _event(base, "x", plain), "replay first")
	if not once.is_empty():
		_reject(once, _event(once, "x", plain), "duplicate_event_or_parcel", "duplicate event")
	# Proposal, receipt snapshots and returned parcels are independent copies.
	var isolated: Dictionary = Model.propose(base, _event(base, "alias", plain))
	if bool(isolated.get("valid", false)):
		var kept_after: float = float(isolated["receipt"]["after"]["rooms"]["A"]["m_upper"])
		isolated["book"]["rooms"]["A"]["m_upper"] = -5.0
		_check(float(isolated["receipt"]["after"]["rooms"]["A"]["m_upper"]) == kept_after, "receipt isolated")
		isolated["receipt"]["before"]["rooms"]["A"]["m_upper"] = -7.0
		_check(float(base["rooms"]["A"]["m_upper"]) != -7.0, "receipt isolated")
		isolated["receipt"]["event"]["packets"][0]["source"]["zone"] = "upper"
		_check(isolated["receipt"]["parcels"][0]["source"]["zone"] == "lower", "receipt isolated")
	_check(_same(base, _book(gas, {"A": _room(gas, "two_layer_hot_upper")})), "inputs immutable")


func _run() -> void:
	var text: String = FileAccess.get_file_as_string(PLAN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	_check(typeof(parsed) == TYPE_DICTIONARY, "plan readable")
	if typeof(parsed) == TYPE_DICTIONARY:
		plan = parsed
		for case: Dictionary in plan["cases"]:
			cases[case["id"]] = case
		var tolerances: Dictionary = plan["tolerances"]
		exact = float(tolerances["exact_relative"])
		ident = float(tolerances["identity_relative"])
		floor_m = float(tolerances["exact_abs_floor"]["mass_kg"])
		floor_e = float(tolerances["exact_abs_floor"]["energy_kj"])
		floor_p = float(tolerances["exact_abs_floor"]["pressure_pa"])
		floor_t = float(tolerances["exact_abs_floor"]["temperature_k"])
		floor_v = float(tolerances["exact_abs_floor"]["volume_m3"])
		_check(plan["status"] == "predeclared_before_any_evaluation", "plan status")
		_sealed_cases()
		_c4_c5()
		_parcel_cases()
		_convergence_cases()
		_c11_c13()
		_scope_cases()
		_rejection_cases()
	print(PREFIX + " " + JSON.stringify({"checks": checks, "failed_checks": failed_checks,
		"failure_count": failures.size(), "failures": failures, "samples": samples,
		"rejections": rejections, "finals": finals, "convergence": convergence}, "", true, true))
	quit(0 if failures.is_empty() else 1)
