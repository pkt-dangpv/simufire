extends RefCounted
class_name PressureNetworkTransportSystem

# ============================================================
# F2.2C: INTEGRACION AUTORITATIVA DE LA RED DE PRESION
# ------------------------------------------------------------
# NO es un solver. Es el adaptador entre el motor y
# `Phase3CoupledPressureSolver` (F2.2B), que a su vez usa
# `CompartmentPressureEquations` (F2.2A) como evaluador
# autoritativo. Aqui no se repite ninguna ecuacion: no hay
# Bernoulli, ni plano neutro, ni sentido de flujo inferido, ni
# recorte de presiones propio.
#
# Se ejecuta SOLO con `pressure_network_solver_enabled = true`.
# Con el interruptor apagado el motor recorre la ruta historica
# y este sistema no se construye ni se ejecuta.
#
# El paso se hace en seis operaciones separadas y comprobables:
#   1. build_snapshot            estado inmutable de partida
#   2. build_solver_input        entrada canonica del solver
#   3. solve                     una sola llamada a F2.2B
#   4. build_transport_transaction   deltas, sin tocar salas
#   5. validate_transaction      todo o nada
#   6. commit_transaction        aplicacion atomica
#
# Politica de fallo: si algo falla, NO se aplica nada y NO hay
# vuelta atras silenciosa a la ruta historica. El motor recibe
# el diagnostico y se detiene.
#
# Convenciones (identicas a F2.2A y F2.2B):
#   - presion manometrica respecto al exterior, referencia en el
#     suelo de cada recinto, con signo;
#   - masa kg, energia sensible kJ, entalpia kW, presion Pa,
#     temperatura K, cotas m absolutas;
#   - positivo = entra en el recinto y en la zona.
#
# LIMITACIONES declaradas (ver §16 del documento de diseno):
#   - el humo, el HCl, la acroleina y el formaldehido solo tienen
#     masa GLOBAL en RoomModel: se transportan con hipotesis de
#     MEZCLA COMPLETA del recinto, que es la semantica que ya usaba
#     la ruta historica de purga por aire;
#   - PPV no esta representada como fuente ni contorno: con el
#     interruptor encendido se rechaza de forma explicita;
#   - F2.2D1: una puerta interior CERRADA puede aportar rendijas ELA
#     (fuga fria), y solo eso, y solo con `closed_door_leakage_enabled`;
#     sin ese interruptor sigue siendo estanca, como en F2.2C. La
#     deformacion prescrita (D2) y el vidrio (D3) siguen sin conectar.
# ============================================================

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
## F2.2D1: la puerta cerrada se describe aqui, no se calcula aqui.
const LeakageAdapterScript = preload("res://sim/core/ClosedDoorLeakageNetworkAdapter.gd")

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const ZONES: Array[String] = [ZONE_UPPER, ZONE_LOWER]
const EXTERIOR_ROOM_ID: String = "outside"

const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0

## Especies con masa total y masa de capa superior en RoomModel.
const ZONAL_SPECIES: Array[String] = ["co", "co2", "hcn"]
## Magnitudes que solo existen como masa global: mezcla completa.
const GLOBAL_SPECIES: Array[String] = ["smoke", "hcl", "acrolein", "formaldehyde"]

const MASS_EPS_KG: float = 1.0e-12
## Residuo de redondeo que se corrige de forma determinista al cerrar.
const NEGATIVE_TOLERANCE_KG: float = 1.0e-9
const CONSERVATION_TOLERANCE_KG: float = 1.0e-6
const CONSERVATION_TOLERANCE_KJ: float = 1.0e-3

var _solver = SolverScript.new()
var last_result: Dictionary = {}
## F2.2D1: cuantas veces se ha APLICADO la transaccion. La invariante de F2.2C
## es que la red es dueña unica y se aplica una sola vez por paso del motor;
## este contador la hace comprobable desde fuera.
var commit_count: int = 0


## F2.2D1: la fuga fria de puerta cerrada solo se anade cuando el escenario la
## pide expresamente. Falso por defecto y gobernado por el motor.
var closed_door_leakage_enabled: bool = false


## Paso completo. Devuelve {applied, valid, errors, failure_reason, solution,
## transaction, diagnostics}. No aplica nada si algo falla.
func step(building, dt_s: float, outside_override: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _new_result()
	if building == null:
		result["failure_reason"] = "no_building"
		result["errors"] = ["the network needs a building"]
		last_result = result
		return result

	var snapshot: Dictionary = build_snapshot(building, outside_override, dt_s)
	if not bool(snapshot["valid"]):
		result["failure_reason"] = "invalid_snapshot"
		result["errors"] = snapshot["errors"]
		last_result = result
		return result

	var solver_input: Dictionary = build_solver_input(snapshot, dt_s)
	if not bool(solver_input["valid"]):
		result["failure_reason"] = "invalid_solver_input"
		result["errors"] = solver_input["errors"]
		last_result = result
		return result

	var solution: Dictionary = solve(solver_input)
	result["solution"] = solution
	if not bool(solution.get("converged", false)) or not bool(solution.get("valid", false)):
		result["failure_reason"] = "solver_%s" % String(solution.get("failure_reason", "failed"))
		result["errors"] = solution.get("errors", ["the pressure network did not converge"])
		last_result = result
		return result

	var transaction: Dictionary = build_transport_transaction(snapshot, solution, dt_s)
	result["transaction"] = transaction
	if not bool(transaction["valid"]):
		result["failure_reason"] = "invalid_transaction"
		result["errors"] = transaction["errors"]
		last_result = result
		return result

	var verdict: Dictionary = validate_transaction(snapshot, transaction)
	if not bool(verdict["valid"]):
		result["failure_reason"] = "transaction_rejected"
		result["errors"] = verdict["errors"]
		result["diagnostics"] = verdict
		last_result = result
		return result

	var commit: Dictionary = commit_transaction(building, snapshot, transaction, solution)
	if bool(commit["applied"]):
		commit_count += 1
	result["applied"] = bool(commit["applied"])
	result["valid"] = bool(commit["applied"])
	result["diagnostics"] = commit
	if not bool(commit["applied"]):
		result["failure_reason"] = String(commit.get("failure_reason", "commit_failed"))
		result["errors"] = commit.get("errors", [])
	last_result = result
	return result


# ------------------------------------------------------------
# 1. snapshot
# ------------------------------------------------------------

## Estado inmutable de partida. Todo lo que la transaccion lea sale de aqui:
## ninguna sala se consulta despues de empezar a calcular transferencias.
func build_snapshot(building, outside_override: Dictionary = {}, dt_s: float = 0.0) -> Dictionary:
	var errors: Array[String] = []
	var rooms: Dictionary = {}
	var order: Array[String] = []
	for raw_room_id in building.get_rooms().keys():
		var room = building.get_room(raw_room_id)
		if room == null:
			continue
		var room_id: String = str(int(raw_room_id))
		var upper_gas_kg: float = float(room.upper_gas_kg)
		var lower_gas_kg: float = float(room.lower_gas_kg)
		var total_gas_kg: float = upper_gas_kg + lower_gas_kg
		if total_gas_kg <= MASS_EPS_KG:
			errors.append("room %s has no zone inventory; the canonical two-zone state is required" % room_id)
			continue
		var entry: Dictionary = {
			"room_id": room_id,
			"engine_room_id": int(raw_room_id),
			"floor_z_m": float(room.floor_level_z_m),
			"floor_area_m2": float(room.floor_area_m2()),
			"height_m": float(room.height_m),
			"volume_m3": float(room.volume_m3()),
			"upper_gas_kg": upper_gas_kg,
			"lower_gas_kg": lower_gas_kg,
			"upper_energy_kj": float(room.upper_energy_kj),
			"lower_energy_kj": float(room.lower_energy_kj),
			"o2_upper": float(room.o2_upper),
			"o2_lower": float(room.o2_lower),
			"o2": float(room.o2),
		}
		# O2 como masa por zona, con la misma convencion fraccion-masa que ya
		# usa el motor. Al cerrar se vuelve a derivar la fraccion.
		entry["o2_mass_upper_kg"] = float(room.o2_upper) * upper_gas_kg
		entry["o2_mass_lower_kg"] = float(room.o2_lower) * lower_gas_kg
		for species in ZONAL_SPECIES:
			var total_kg: float = float(room.get("%s_kg" % species))
			var upper_kg: float = float(room.get("%s_upper_kg" % species))
			upper_kg = clampf(upper_kg, 0.0, maxf(0.0, total_kg))
			entry["%s_upper_kg" % species] = upper_kg
			entry["%s_lower_kg" % species] = maxf(0.0, total_kg - upper_kg)
			entry["%s_total_kg" % species] = maxf(0.0, total_kg)
		for species in GLOBAL_SPECIES:
			entry["%s_total_kg" % species] = maxf(0.0, float(room.get("%s_kg" % species)))
		rooms[room_id] = entry
		order.append(room_id)
	order.sort()

	var openings: Array = []
	var cracks: Array = []
	for opening in building.get_openings():
		if opening == null:
			continue
		var a_id: int = int(opening.a)
		var b_id: int = int(opening.b)
		var outside_id: int = BuildingModel.OUTSIDE_ID
		var a_key: String = EXTERIOR_ROOM_ID if a_id == outside_id else str(a_id)
		var b_key: String = EXTERIOR_ROOM_ID if b_id == outside_id else str(b_id)
		if a_key != EXTERIOR_ROOM_ID and not rooms.has(a_key):
			continue
		if b_key != EXTERIOR_ROOM_ID and not rooms.has(b_key):
			continue
		# F2.2D1: la fraccion OPERATIVA, sin `thermal_gap_fraction`. F2.2C usaba
		# `effective_open_fraction()`, que suma la deformacion termica heredada y
		# podia meter una puerta cerrada en la red como abertura grande. La
		# deformacion prescrita llega en D2, por sus propios segmentos.
		var open_fraction: float = 1.0 if int(opening.type) == OpeningModel.Type.HOLE \
				else float(opening.open_fraction)
		if opening.is_closed() or open_fraction <= 0.001:
			# Puerta cerrada: solo puede aportar rendijas ELA, nunca una abertura
			# grande, y solo si la capacidad esta encendida.
			var crack: Dictionary = _crack_element(opening, a_key, b_key, rooms, dt_s)
			if not crack.is_empty():
				cracks.append(crack)
			continue
		var anchor_floor_z_m: float = 0.0
		if a_key != EXTERIOR_ROOM_ID:
			anchor_floor_z_m = float(rooms[a_key]["floor_z_m"])
		elif b_key != EXTERIOR_ROOM_ID:
			anchor_floor_z_m = float(rooms[b_key]["floor_z_m"])
		openings.append({
			# Identificador canonico: el indice de la abertura en el edificio.
			# Unico, estable, determinista y trazable; dos puertas iguales entre
			# las mismas salas ya no colisionan.
			"opening_id": "op_%d" % int(opening.opening_index),
			"room_a_id": a_key,
			"room_b_id": b_key,
			"bottom_z_m": anchor_floor_z_m + float(opening.sill_m),
			"top_z_m": anchor_floor_z_m + float(opening.lintel_height_m()),
			"width_m": float(opening.width_m),
			"open_fraction": clampf(open_fraction, 0.0, 1.0),
			"discharge_coeff": 0.61,
		})
	openings.append_array(cracks)
	openings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["opening_id"]) < String(right["opening_id"]))

	var reference_temp_k: float = float(building.outside_temp_c) + 273.15
	var outside: Dictionary = {
		"pressure_abs_pa": AIR_PRESSURE_REF_PA,
		"temp_k": reference_temp_k,
		"reference_temp_k": reference_temp_k,
		"o2": float(building.outside_o2),
	}
	for key in outside_override.keys():
		outside[key] = outside_override[key]
	if rooms.is_empty() and errors.is_empty():
		errors.append("the network needs at least one room with zone inventory")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"rooms": rooms,
		"room_order": order,
		"openings": openings,
		"outside": outside,
	}


## F2.2D1: rendijas de una puerta cerrada, si la capacidad esta encendida. El
## adaptador decide si la puerta aporta fuga; aqui solo se traslada al contrato
## de la red y se le pone el identificador canonico.
func _crack_element(opening, a_key: String, b_key: String, rooms: Dictionary,
		dt_s: float) -> Dictionary:
	if not closed_door_leakage_enabled:
		return {}
	if a_key == EXTERIOR_ROOM_ID or b_key == EXTERIOR_ROOM_ID:
		return {}
	if not rooms.has(a_key) or not rooms.has(b_key):
		return {}
	var floor_z_m: float = float(rooms[a_key]["floor_z_m"])
	var element: Dictionary = LeakageAdapterScript.build_crack_element(
		opening, BuildingModel.OUTSIDE_ID, floor_z_m, a_key, b_key, dt_s
	)
	if element.is_empty():
		return {}
	return {
		"opening_id": "crack_%d" % int(opening.opening_index),
		"room_a_id": a_key,
		"room_b_id": b_key,
		"flow_model": "ela_crack",
		"crack_segments": element["crack_segments"],
		"ela_reference_pressure_pa": float(element["ela_reference_pressure_pa"]),
		"flow_exponent": float(element["flow_exponent"]),
		"zero_pressure_regularization_pa": float(element["zero_pressure_regularization_pa"]),
		"pressure_domain_max_pa": float(element["pressure_domain_max_pa"]),
		"provenance": String(element["provenance"]),
		"leakage_class": String(element["leakage_class"]),
		"resolved_ela_m2": float(element["resolved_ela_m2"]),
		# El solver exige estos campos en toda conexion; una rendija no tiene
		# vano, asi que se declaran neutros y no se usan.
		"width_m": 1.0,
		"open_fraction": 1.0,
		"discharge_coeff": 1.0,
		"bottom_z_m": float(element["crack_segments"][0]["z_m"]),
		"top_z_m": float(element["crack_segments"][element["crack_segments"].size() - 1]["z_m"]),
	}


# ------------------------------------------------------------
# 2. entrada del solver
# ------------------------------------------------------------

## Entrada canonica de F2.2B. Las fuentes son NULAS a proposito: la combustion
## y el calentamiento ya estan incorporados al snapshot, y volver a declararlos
## los contaria dos veces (§15 del documento de diseno).
func build_solver_input(snapshot: Dictionary, dt_s: float) -> Dictionary:
	if not is_finite(dt_s) or dt_s <= 0.0:
		return {"valid": false, "errors": ["dt_s must be finite and > 0"]}
	var rooms: Array = []
	for room_id in snapshot["room_order"]:
		var room: Dictionary = snapshot["rooms"][room_id]
		rooms.append({
			"room_id": room_id,
			"floor_z_m": float(room["floor_z_m"]),
			"floor_area_m2": float(room["floor_area_m2"]),
			"height_m": float(room["height_m"]),
			"upper_gas_kg": float(room["upper_gas_kg"]),
			"lower_gas_kg": float(room["lower_gas_kg"]),
			"upper_energy_kj": float(room["upper_energy_kj"]),
			"lower_energy_kj": float(room["lower_energy_kj"]),
		})
	return {
		"valid": true,
		"errors": [],
		"rooms": rooms,
		"openings": snapshot["openings"].duplicate(true),
		"outside": {
			"pressure_abs_pa": float(snapshot["outside"]["pressure_abs_pa"]),
			"temp_k": float(snapshot["outside"]["temp_k"]),
			"reference_temp_k": float(snapshot["outside"]["reference_temp_k"]),
		},
		"sources": {},
		"dt_s": dt_s,
	}


# ------------------------------------------------------------
# 3. solve
# ------------------------------------------------------------

## Una sola llamada al solver canonico. Aqui no se decide nada.
func solve(solver_input: Dictionary) -> Dictionary:
	return _solver.solve_pressure_network(
		solver_input["rooms"], solver_input["openings"], solver_input["outside"],
		solver_input["sources"], float(solver_input["dt_s"])
	)


# ------------------------------------------------------------
# 4. transaccion
# ------------------------------------------------------------

## Construye los deltas SIN tocar ninguna sala. Todo se lee del snapshot, de
## modo que el estado ya modificado de un recinto nunca es el origen de la
## siguiente abertura.
func build_transport_transaction(snapshot: Dictionary, solution: Dictionary,
		dt_s: float) -> Dictionary:
	var errors: Array[String] = []
	var totals: Dictionary = {}
	for room_id in snapshot["room_order"]:
		totals[room_id] = {}
		for zone in ZONES:
			totals[room_id][zone] = 0.0
	if not is_finite(dt_s) or dt_s <= 0.0:
		errors.append("dt_s must be finite and > 0")
		return {"valid": false, "errors": errors, "rooms": {}, "routes": []}

	# Paso 1: pedir cada ruta desde el snapshot.
	var routes: Array = []
	for raw_opening in solution["openings"]:
		var opening: Dictionary = raw_opening
		for raw_segment in opening["segments"]:
			var segment: Dictionary = raw_segment
			var source_room_id: String = String(segment["source_room_id"])
			var destination_room_id: String = String(segment["destination_room_id"])
			var source_zone: String = String(segment["source_zone"])
			var destination_zone: String = String(segment["destination_zone"])
			var mass_kg: float = float(segment["mass_flow_kg_s"]) * dt_s
			var energy_kj: float = float(segment["enthalpy_flow_kw"]) * dt_s
			if not is_finite(mass_kg) or not is_finite(energy_kj):
				errors.append("segment %s of opening %s is not finite" % [
					segment["segment_id"], opening["opening_id"]])
				continue
			if mass_kg < 0.0:
				errors.append("segment %s of opening %s carries negative mass" % [
					segment["segment_id"], opening["opening_id"]])
				continue
			var bundle: Dictionary = _bundle_for_source(
				snapshot, source_room_id, source_zone, mass_kg, energy_kj, errors
			)
			routes.append({
				"opening_id": String(opening["opening_id"]),
				"segment_id": String(segment["segment_id"]),
				"source_room_id": source_room_id,
				"source_zone": source_zone,
				"destination_room_id": destination_room_id,
				"destination_zone": destination_zone,
				"bundle": bundle,
			})
			if source_room_id != EXTERIOR_ROOM_ID:
				totals[source_room_id][source_zone] = float(totals[source_room_id][source_zone]) \
						+ mass_kg
	if not errors.is_empty():
		return {"valid": false, "errors": errors, "rooms": {}, "routes": []}

	# Paso 2: escalar colectivamente las salidas de cada (recinto, zona) que
	# pidan mas masa de la que hay. El factor es del grupo, no de la ruta, asi
	# que el resultado no depende del orden de enumeracion.
	var scale: Dictionary = {}
	for room_id in snapshot["room_order"]:
		scale[room_id] = {}
		for zone in ZONES:
			var available_kg: float = float(snapshot["rooms"][room_id]["%s_gas_kg" % zone])
			var wanted_kg: float = float(totals[room_id][zone])
			var factor: float = 1.0
			if wanted_kg > available_kg and wanted_kg > MASS_EPS_KG:
				factor = maxf(0.0, available_kg / wanted_kg)
			scale[room_id][zone] = factor

	# Paso 3: acumular deltas por (recinto, zona).
	var deltas: Dictionary = {}
	for room_id in snapshot["room_order"]:
		deltas[room_id] = {}
		for zone in ZONES:
			deltas[room_id][zone] = _empty_bundle()
	var applied_routes: Array = []
	for route in routes:
		var factor: float = 1.0
		if String(route["source_room_id"]) != EXTERIOR_ROOM_ID:
			factor = float(scale[route["source_room_id"]][route["source_zone"]])
		var bundle: Dictionary = _scaled_bundle(route["bundle"], factor)
		if String(route["source_room_id"]) != EXTERIOR_ROOM_ID:
			_add_bundle(deltas[route["source_room_id"]][route["source_zone"]], bundle, -1.0)
		if String(route["destination_room_id"]) != EXTERIOR_ROOM_ID:
			var destination_zone: String = String(route["destination_zone"])
			if destination_zone.is_empty():
				destination_zone = ZONE_LOWER
			_add_bundle(deltas[route["destination_room_id"]][destination_zone], bundle, 1.0)
		var applied: Dictionary = route.duplicate(true)
		applied["bundle"] = bundle
		applied["scale"] = factor
		applied_routes.append(applied)

	return {
		"valid": true,
		"errors": errors,
		"dt_s": dt_s,
		"rooms": deltas,
		"routes": applied_routes,
		"scale": scale,
	}


## Contenido que arrastra una masa de gas que sale de (recinto, zona). Del
## exterior sale la composicion del contorno, nunca una contaminacion inventada.
func _bundle_for_source(snapshot: Dictionary, room_id: String, zone: String,
		mass_kg: float, energy_kj: float, errors: Array[String]) -> Dictionary:
	var bundle: Dictionary = _empty_bundle()
	bundle["mass_kg"] = mass_kg
	bundle["energy_kj"] = energy_kj
	if room_id == EXTERIOR_ROOM_ID:
		bundle["o2_kg"] = float(snapshot["outside"]["o2"]) * mass_kg
		return bundle
	if not snapshot["rooms"].has(room_id):
		errors.append("unknown source room '%s'" % room_id)
		return bundle
	var room: Dictionary = snapshot["rooms"][room_id]
	var zone_key: String = zone if ZONES.has(zone) else ZONE_LOWER
	var zone_mass_kg: float = float(room["%s_gas_kg" % zone_key])
	if zone_mass_kg <= MASS_EPS_KG:
		return bundle
	var zone_fraction: float = mass_kg / zone_mass_kg
	bundle["o2_kg"] = float(room["o2_mass_%s_kg" % zone_key]) * zone_fraction
	for species in ZONAL_SPECIES:
		bundle["%s_kg" % species] = float(room["%s_%s_kg" % [species, zone_key]]) * zone_fraction
		bundle["%s_upper_kg" % species] = bundle["%s_kg" % species] if zone_key == ZONE_UPPER else 0.0
	# Mezcla completa para lo que solo existe como masa global.
	var room_mass_kg: float = float(room["upper_gas_kg"]) + float(room["lower_gas_kg"])
	if room_mass_kg > MASS_EPS_KG:
		var room_fraction: float = mass_kg / room_mass_kg
		for species in GLOBAL_SPECIES:
			bundle["%s_kg" % species] = float(room["%s_total_kg" % species]) * room_fraction
	return bundle


func _empty_bundle() -> Dictionary:
	var bundle: Dictionary = {"mass_kg": 0.0, "energy_kj": 0.0, "o2_kg": 0.0}
	for species in ZONAL_SPECIES:
		bundle["%s_kg" % species] = 0.0
		bundle["%s_upper_kg" % species] = 0.0
	for species in GLOBAL_SPECIES:
		bundle["%s_kg" % species] = 0.0
	return bundle


func _scaled_bundle(bundle: Dictionary, factor: float) -> Dictionary:
	if factor == 1.0:
		return bundle.duplicate(true)
	var scaled: Dictionary = {}
	for key in bundle.keys():
		scaled[key] = float(bundle[key]) * factor
	return scaled


func _add_bundle(target: Dictionary, bundle: Dictionary, sign: float) -> void:
	for key in bundle.keys():
		target[key] = float(target[key]) + sign * float(bundle[key])


# ------------------------------------------------------------
# 5. validacion
# ------------------------------------------------------------

## Comprueba la transaccion ENTERA antes de tocar nada.
func validate_transaction(snapshot: Dictionary, transaction: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var interior_mass_delta_kg: float = 0.0
	var interior_energy_delta_kj: float = 0.0
	var exterior_mass_kg: float = 0.0
	for route in transaction["routes"]:
		var bundle: Dictionary = route["bundle"]
		for key in bundle.keys():
			if not is_finite(float(bundle[key])):
				errors.append("route %s of %s carries a non-finite %s" % [
					route["segment_id"], route["opening_id"], key])
		if String(route["source_room_id"]) == EXTERIOR_ROOM_ID:
			exterior_mass_kg += float(bundle["mass_kg"])
		if String(route["destination_room_id"]) == EXTERIOR_ROOM_ID:
			exterior_mass_kg -= float(bundle["mass_kg"])
	for room_id in snapshot["room_order"]:
		var room: Dictionary = snapshot["rooms"][room_id]
		for zone in ZONES:
			var delta: Dictionary = transaction["rooms"][room_id][zone]
			var final_mass_kg: float = float(room["%s_gas_kg" % zone]) + float(delta["mass_kg"])
			interior_mass_delta_kg += float(delta["mass_kg"])
			interior_energy_delta_kj += float(delta["energy_kj"])
			if not is_finite(final_mass_kg):
				errors.append("room %s zone %s would end with a non-finite mass" % [room_id, zone])
			elif final_mass_kg < -NEGATIVE_TOLERANCE_KG:
				errors.append("room %s zone %s would end with %.12f kg" % [room_id, zone, final_mass_kg])
			var final_o2_kg: float = float(room["o2_mass_%s_kg" % zone]) + float(delta["o2_kg"])
			if final_o2_kg < -NEGATIVE_TOLERANCE_KG:
				errors.append("room %s zone %s would end with negative O2" % [room_id, zone])
			for species in ZONAL_SPECIES:
				var final_species_kg: float = float(room["%s_%s_kg" % [species, zone]]) \
						+ float(delta["%s_kg" % species])
				if final_species_kg < -NEGATIVE_TOLERANCE_KG:
					errors.append("room %s zone %s would end with negative %s" % [room_id, zone, species])
		for species in GLOBAL_SPECIES:
			var total_delta_kg: float = float(transaction["rooms"][room_id][ZONE_UPPER]["%s_kg" % species]) \
					+ float(transaction["rooms"][room_id][ZONE_LOWER]["%s_kg" % species])
			if float(room["%s_total_kg" % species]) + total_delta_kg < -NEGATIVE_TOLERANCE_KG:
				errors.append("room %s would end with negative %s" % [room_id, species])
	# Conservacion: lo que sale de un recinto entra en otro o en el exterior.
	if absf(interior_mass_delta_kg - exterior_mass_kg) > CONSERVATION_TOLERANCE_KG:
		errors.append("the interior mass balance does not match the exterior exchange (%.9f vs %.9f)" % [
			interior_mass_delta_kg, exterior_mass_kg])
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"interior_mass_delta_kg": interior_mass_delta_kg,
		"interior_energy_delta_kj": interior_energy_delta_kj,
		"exterior_mass_kg": exterior_mass_kg,
	}


# ------------------------------------------------------------
# 6. commit
# ------------------------------------------------------------

## Aplicacion atomica: o se aplica todo o no se aplica nada. La presion
## canonica se publica aqui y ningun sistema posterior puede reescribirla.
func commit_transaction(building, snapshot: Dictionary, transaction: Dictionary,
		solution: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	# Estado final calculado ENTERO antes de escribir la primera sala.
	var final_states: Dictionary = {}
	for room_id in snapshot["room_order"]:
		var room: Dictionary = snapshot["rooms"][room_id]
		var final_state: Dictionary = {}
		var total_mass_kg: float = 0.0
		var total_o2_kg: float = 0.0
		for zone in ZONES:
			var delta: Dictionary = transaction["rooms"][room_id][zone]
			var mass_kg: float = _settled(float(room["%s_gas_kg" % zone]) + float(delta["mass_kg"]))
			var energy_kj: float = float(room["%s_energy_kj" % zone]) + float(delta["energy_kj"])
			var o2_kg: float = _settled(float(room["o2_mass_%s_kg" % zone]) + float(delta["o2_kg"]))
			final_state["%s_gas_kg" % zone] = mass_kg
			final_state["%s_energy_kj" % zone] = energy_kj
			final_state["o2_mass_%s_kg" % zone] = o2_kg
			total_mass_kg += mass_kg
			total_o2_kg += o2_kg
			for species in ZONAL_SPECIES:
				final_state["%s_%s_kg" % [species, zone]] = _settled(
					float(room["%s_%s_kg" % [species, zone]]) + float(delta["%s_kg" % species])
				)
		for species in GLOBAL_SPECIES:
			var delta_kg: float = float(transaction["rooms"][room_id][ZONE_UPPER]["%s_kg" % species]) \
					+ float(transaction["rooms"][room_id][ZONE_LOWER]["%s_kg" % species])
			final_state["%s_total_kg" % species] = _settled(
				float(room["%s_total_kg" % species]) + delta_kg
			)
		if total_mass_kg <= MASS_EPS_KG:
			errors.append("room %s would be left without gas" % room_id)
		final_state["total_gas_kg"] = total_mass_kg
		final_state["total_o2_kg"] = total_o2_kg
		final_states[room_id] = final_state
	if not errors.is_empty():
		return {"applied": false, "failure_reason": "impossible_final_state", "errors": errors}

	var pressure_by_room: Dictionary = {}
	for raw_room in solution["rooms"]:
		var solved_room: Dictionary = raw_room
		if not bool(solved_room["equations_valid"]):
			errors.append("room %s was not accepted by the compartment equations" % solved_room["room_id"])
		pressure_by_room[String(solved_room["room_id"])] = float(solved_room["gauge_pressure_pa"])
	if not errors.is_empty():
		return {"applied": false, "failure_reason": "solution_rejected", "errors": errors}

	# A partir de aqui ya no hay decisiones: solo escritura.
	for room_id in snapshot["room_order"]:
		var room = building.get_room(int(snapshot["rooms"][room_id]["engine_room_id"]))
		if room == null:
			continue
		var final_state: Dictionary = final_states[room_id]
		room.upper_gas_kg = float(final_state["upper_gas_kg"])
		room.lower_gas_kg = float(final_state["lower_gas_kg"])
		room.upper_energy_kj = float(final_state["upper_energy_kj"])
		room.lower_energy_kj = float(final_state["lower_energy_kj"])
		var total_gas_kg: float = float(final_state["total_gas_kg"])
		# Las fracciones de O2 se DERIVAN de las masas finales.
		room.o2_upper = _fraction(float(final_state["o2_mass_upper_kg"]), float(final_state["upper_gas_kg"]))
		room.o2_lower = _fraction(float(final_state["o2_mass_lower_kg"]), float(final_state["lower_gas_kg"]))
		room.o2 = _fraction(float(final_state["total_o2_kg"]), total_gas_kg)
		for species in ZONAL_SPECIES:
			var upper_kg: float = float(final_state["%s_upper_kg" % species])
			var lower_kg: float = float(final_state["%s_lower_kg" % species])
			room.set("%s_upper_kg" % species, upper_kg)
			room.set("%s_kg" % species, upper_kg + lower_kg)
		for species in GLOBAL_SPECIES:
			room.set("%s_kg" % species, float(final_state["%s_total_kg" % species]))
		# Presion canonica: un unico propietario, con signo.
		var gauge_pressure_pa: float = float(pressure_by_room.get(room_id, 0.0))
		room.overpressure_pa = gauge_pressure_pa
		# Espejo de compatibilidad, nunca una segunda fuente.
		room.pressure_pa_therm = gauge_pressure_pa
	return {
		"applied": true,
		"errors": errors,
		"rooms_committed": snapshot["room_order"].size(),
		"routes_applied": transaction["routes"].size(),
		"pressure_by_room": pressure_by_room,
	}


## Corrige un residuo de redondeo negativo de forma determinista. No es un
## clamp amplio: por encima de la tolerancia la transaccion ya se rechazo.
func _settled(value: float) -> float:
	if value < 0.0 and value >= -NEGATIVE_TOLERANCE_KG:
		return 0.0
	return value


func _fraction(mass_kg: float, total_kg: float) -> float:
	if total_kg <= MASS_EPS_KG:
		return 0.0
	return mass_kg / total_kg


func _new_result() -> Dictionary:
	return {
		"applied": false,
		"valid": false,
		"errors": [],
		"failure_reason": "",
		"solution": {},
		"transaction": {},
		"diagnostics": {},
	}
