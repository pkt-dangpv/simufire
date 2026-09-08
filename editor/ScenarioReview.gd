extends RefCounted
## La revisión del escenario antes de arrancar: lo que se puede ejecutar pero no
## tiene sentido.
##
## `ScenarioSerializer.validate_scenario()` ya mira que los datos estén bien
## formados -que cada sala tenga rectángulo, altura positiva, y que las aperturas
## apunten a salas que existen- y eso impide ejecutar. Aquí se mira otra cosa: un
## escenario perfectamente válido que al correrlo no enseña nada.
##
## Los casos son de fuego, no de programación:
##
##  - Una sala sin ninguna puerta, ventana ni hueco es una caja sellada: el humo
##    ni entra ni sale, y esa habitación se queda igual toda la simulación.
##  - Sin foco de ignición no arde nada... salvo que el exportador elige la sala 0
##    por su cuenta (ScenarioSerializer._resolve_ignition_room_id), así que el
##    incendio empieza en un sitio que nadie ha elegido.
##  - Un edificio sin ninguna abertura al exterior consume su oxígeno y el fuego
##    se apaga solo: sale una simulación en la que no pasa casi nada.
##  - Una planta sin comunicación vertical con las demás no recibe humo por la
##    escalera y no se puede llegar andando.
##  - Dos salas que se pisan son dos zonas repartiéndose el mismo aire: el modelo
##    cuenta ese volumen dos veces.
##
## Ninguno impide arrancar: son avisos, y el usuario decide. Lo que no puede
## seguir pasando es que no se digan.

const OUTSIDE_ID: int = -1
## Dos salas que solo se rozan no se pisan: hay que solaparse de verdad.
const OVERLAP_TOLERANCE_M: float = 0.05
## Dos plantas son la misma si están a la misma cota, con el margen de siempre.
const SAME_LEVEL_M: float = 0.05


## Devuelve una lista de avisos, cada uno {"text": String, "room_id": int}.
## Vacía significa que el escenario, además de válido, tiene sentido.
static func review(data: Dictionary) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	var rooms: Array[Dictionary] = _rooms(data)
	if rooms.is_empty():
		warnings.append(_warning("El escenario no tiene ninguna habitación."))
		return warnings
	_check_sealed_rooms(data, rooms, warnings)
	_check_ignition(data, rooms, warnings)
	_check_outside_openings(data, warnings)
	_check_floor_links(data, rooms, warnings)
	_check_overlaps(data, rooms, warnings)
	_check_player_start(data, rooms, warnings)
	return warnings


# ── Las comprobaciones ──────────────────────────────────────────────────────

## Una sala sin ninguna abertura no participa en el incendio.
static func _check_sealed_rooms(data: Dictionary, rooms: Array[Dictionary], warnings: Array[Dictionary]) -> void:
	var touched: Dictionary = {}
	for opening in _openings(data):
		touched[int(opening.get("a", -99))] = true
		touched[int(opening.get("b", -99))] = true
	for room in rooms:
		var room_id: int = int(room.get("id", -1))
		if touched.has(room_id):
			continue
		warnings.append(_warning(
			"%s no tiene ninguna puerta, ventana ni hueco: el humo no puede entrar ni salir." % _room_label(data, room),
			room_id))


## Sin foco elegido, el exportador se queda con la sala 0 por su cuenta.
static func _check_ignition(data: Dictionary, rooms: Array[Dictionary], warnings: Array[Dictionary]) -> void:
	var ignition_room: Dictionary = {}
	for room in rooms:
		for raw_obj in Array(room.get("fuel_objects", [])):
			if typeof(raw_obj) == TYPE_DICTIONARY and bool(Dictionary(raw_obj).get("is_primary_ignition_source", false)):
				ignition_room = room
				break
		if not ignition_room.is_empty():
			break
	if ignition_room.is_empty():
		var declared_id: int = int(data.get("ignition_room_id", -1))
		for room in rooms:
			if int(room.get("id", -1)) == declared_id:
				ignition_room = room
				break
	if ignition_room.is_empty():
		warnings.append(_warning(
			"No hay foco de ignición: el incendio empezará donde decida el exportador, no donde quieras. Marca un objeto con la herramienta Ignición."))
		return
	# Y si lo hay, que tenga algo que arder.
	var fuel_mj: float = float(ignition_room.get("fuel_energy_MJ", 0.0))
	for raw_obj in Array(ignition_room.get("fuel_objects", [])):
		if typeof(raw_obj) == TYPE_DICTIONARY:
			fuel_mj += float(Dictionary(raw_obj).get("fuel_energy_MJ", 0.0))
	if fuel_mj <= 0.0:
		warnings.append(_warning(
			"%s es el origen del incendio y no tiene nada que arder: 0 MJ de carga de fuego." % _room_label(data, ignition_room),
			int(ignition_room.get("id", -1))))


## Un edificio hermético se queda sin oxígeno y el fuego se apaga solo.
static func _check_outside_openings(data: Dictionary, warnings: Array[Dictionary]) -> void:
	for opening in _openings(data):
		if int(opening.get("b", OUTSIDE_ID)) == OUTSIDE_ID or int(opening.get("a", OUTSIDE_ID)) == OUTSIDE_ID:
			return
	warnings.append(_warning(
		"Ninguna abertura da al exterior: el edificio es hermético, se queda sin oxígeno y el fuego se apagará solo. Pon al menos una ventana o una puerta exterior."))


## Cada planta con salas tiene que estar unida verticalmente con alguna otra.
static func _check_floor_links(data: Dictionary, rooms: Array[Dictionary], warnings: Array[Dictionary]) -> void:
	var levels: Array[float] = []
	for room in rooms:
		var level_m: float = float(room.get("floor_level_z_m", 0.0))
		var known: bool = false
		for seen in levels:
			if absf(seen - level_m) < SAME_LEVEL_M:
				known = true
				break
		if not known:
			levels.append(level_m)
	if levels.size() < 2:
		return
	var linked_levels: Dictionary = {}
	for opening in _openings(data):
		if not bool(opening.get("is_vertical", false)):
			continue
		for key in ["a", "b"]:
			var level_m: float = _room_level(rooms, int(opening.get(key, -1)))
			if level_m != INF:
				linked_levels[snappedf(level_m, 0.01)] = true
	for level_m in levels:
		var found: bool = false
		for raw_key in linked_levels.keys():
			if absf(float(raw_key) - level_m) < SAME_LEVEL_M:
				found = true
				break
		if not found:
			warnings.append(_warning(
				"La planta %s no está comunicada con ninguna otra: sin hueco de escalera el humo no sube y no se puede llegar andando." % _floor_name(data, level_m)))


## Dos salas de la misma planta que se pisan cuentan dos veces el mismo aire.
static func _check_overlaps(data: Dictionary, rooms: Array[Dictionary], warnings: Array[Dictionary]) -> void:
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var a: Dictionary = rooms[i]
			var b: Dictionary = rooms[j]
			if absf(float(a.get("floor_level_z_m", 0.0)) - float(b.get("floor_level_z_m", 0.0))) >= SAME_LEVEL_M:
				continue
			var rect_a: Rect2 = _rect(data, int(a.get("id", -1)))
			var rect_b: Rect2 = _rect(data, int(b.get("id", -1)))
			if rect_a.size.x <= 0.0 or rect_b.size.x <= 0.0:
				continue
			var overlap: Rect2 = rect_a.intersection(rect_b)
			if overlap.size.x <= OVERLAP_TOLERANCE_M or overlap.size.y <= OVERLAP_TOLERANCE_M:
				continue
			warnings.append(_warning(
				"%s y %s se pisan (%.2f × %.2f m): son dos zonas repartiéndose el mismo aire." % [
					_room_label(data, a), _room_label(data, b), overlap.size.x, overlap.size.y],
				int(a.get("id", -1))))


static func _check_player_start(data: Dictionary, rooms: Array[Dictionary], warnings: Array[Dictionary]) -> void:
	var start: Dictionary = data.get("player_start", {})
	var room_id: int = int(start.get("room_id", -1)) if start.has("room_id") else -1
	if room_id < 0:
		warnings.append(_warning(
			"No hay inicio en primera persona: podrás ver la simulación desde fuera, pero no entrar a recorrerla."))
		return
	if _room_level(rooms, room_id) == INF:
		warnings.append(_warning("El inicio en primera persona apunta a una habitación que ya no existe."))


# ── Utiles ──────────────────────────────────────────────────────────────────
static func _warning(text: String, room_id: int = -1) -> Dictionary:
	return {"text": text, "room_id": room_id}


static func _rooms(data: Dictionary) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	for raw in Array(data.get("rooms_data", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			rooms.append(raw)
	return rooms


static func _openings(data: Dictionary) -> Array[Dictionary]:
	var openings: Array[Dictionary] = []
	for raw in Array(data.get("openings_data", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			openings.append(raw)
	return openings


static func _rect(data: Dictionary, room_id: int) -> Rect2:
	var raw: Variant = Dictionary(data.get("room_rect_m", {})).get(str(room_id), null)
	if typeof(raw) != TYPE_DICTIONARY:
		return Rect2()
	var rect_data: Dictionary = raw
	return Rect2(
		float(rect_data.get("x", 0.0)), float(rect_data.get("y", 0.0)),
		float(rect_data.get("w", 0.0)), float(rect_data.get("h", 0.0)))


static func _room_level(rooms: Array[Dictionary], room_id: int) -> float:
	for room in rooms:
		if int(room.get("id", -1)) == room_id:
			return float(room.get("floor_level_z_m", 0.0))
	return INF


## "«Salón» (PB)": el nombre que se ve en el plano y la planta donde está, que es
## lo que hace falta para ir a arreglarlo.
static func _room_label(data: Dictionary, room: Dictionary) -> String:
	var room_name: String = String(room.get("name", "")).strip_edges()
	if room_name == "":
		room_name = "Habitación %d" % int(room.get("id", -1))
	return "«%s» (%s)" % [room_name, _floor_name(data, float(room.get("floor_level_z_m", 0.0)))]


static func _floor_name(data: Dictionary, level_m: float) -> String:
	for raw in Array(data.get("floors", [])):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var floor_data: Dictionary = raw
		if absf(float(floor_data.get("level_m", 0.0)) - level_m) < SAME_LEVEL_M:
			return String(floor_data.get("name", "planta %.2f m" % level_m))
	return "cota %.2f m" % level_m
