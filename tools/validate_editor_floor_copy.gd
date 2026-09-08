extends Node
## Guardia: al crear una planta se elige entre vacía y copia de la actual.
##
## Antes no había elección: "+ Planta" creaba una planta vacía -solo con el hueco
## de escalera, que sube solo- y punto. En un bloque de viviendas eso obliga a
## redibujar cada planta entera; en un unifamiliar, en cambio, las plantas son
## distintas y copiar estorbaría. Por eso se pregunta.
##
## Lo que se vigila aquí:
##
##  1. El botón PREGUNTA cuando hay algo que copiar, y no crea nada hasta que se
##     conteste. Si la planta está vacía no pregunta: crea y ya.
##  2. La copia sube lo CONSTRUIDO: salas, pasillos, sus puertas y ventanas, el
##     mobiliario y los detectores.
##  3. La copia NO sube personas: víctimas ni inicio en primera persona.
##  4. La escalera no se duplica: la de arriba ya existe, y las puertas que daban
##     a la escalera abajo dan a la escalera de arriba.
##  5. Nada de ids repetidos: dos salas u objetos con el mismo id rompen el
##     escenario al exportarlo.
##
## Uso: godot --headless --path . tools/validate_editor_floor_copy.tscn

const TOOL_ROOM: int = 2
const TOOL_CORRIDOR: int = 3
const TOOL_STAIRS: int = 4
const TOOL_OBJECT: int = 8
const TOOL_PLAYER_START: int = 10
const TOOL_DETECTOR: int = 12
const TOOL_VICTIM: int = 13

const Serializer := preload("res://editor/ScenarioSerializer.gd")
const StairPlanRules := preload("res://editor/StairPlanRules.gd")

var _failures: Array[String] = []
var _editor: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	add_child(_editor)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Con la planta vacía no se pregunta: se crea y ya.
	_blank()
	var floors_before: int = _floors()
	_editor._add_floor_pressed()
	_expect(_floors() == floors_before + 1, "en una planta vacía, + Planta debería crear sin preguntar")
	_expect(not _dialog_visible(), "no hay nada que copiar y aun así pregunta")

	# 2. Con la planta dibujada, pregunta y NO crea hasta que se conteste.
	_build_ground_floor()
	floors_before = _floors()
	_editor._add_floor_pressed()
	_expect(_dialog_visible(), "+ Planta no pregunta si copiar, teniendo una planta dibujada")
	_expect(_floors() == floors_before, "+ Planta crea la planta antes de que se conteste")
	var dialog := _editor.get_node_or_null("CanvasLayer/NewFloorDialog") as ConfirmationDialog
	if dialog != null:
		dialog.hide()

	# 3. La copia: lo construido sube, las personas no.
	_build_ground_floor()
	_editor.current_floor_index = 0
	var source_level_m: float = _editor._current_floor_level_m()
	var source_rooms: int = _rooms_on(source_level_m)
	var source_openings: int = _openings_on(source_level_m)
	var source_objects: int = _objects_on(source_level_m)
	_expect(source_rooms >= 4, "la planta de partida debería tener al menos 4 salas, tiene %d" % source_rooms)
	_expect(_victims_on(source_level_m) == 1, "la planta de partida debería tener una víctima")

	_editor._create_floor(true)
	var new_level_m: float = _editor._current_floor_level_m()
	_expect(new_level_m > source_level_m + 0.5, "la planta nueva no está por encima (%.2f sobre %.2f)" % [new_level_m, source_level_m])
	_expect(_rooms_on(new_level_m) == source_rooms,
		"la copia deja %d salas donde la de partida tiene %d" % [_rooms_on(new_level_m), source_rooms])
	_expect(_openings_on(new_level_m) == source_openings,
		"la copia deja %d aperturas donde la de partida tiene %d" % [_openings_on(new_level_m), source_openings])
	_expect(_objects_on(new_level_m) == source_objects,
		"la copia deja %d objetos donde la de partida tiene %d" % [_objects_on(new_level_m), source_objects])
	_expect(_detectors_on(new_level_m) == 1, "el detector no sube con su sala (%d arriba)" % _detectors_on(new_level_m))
	_expect(_victims_on(new_level_m) == 0, "la víctima se ha duplicado en la planta copiada: es una persona, no obra")
	_expect(not _player_start_on(new_level_m), "el inicio FP se ha copiado a la planta nueva")
	_expect(_victims_on(source_level_m) == 1, "la copia se ha llevado la víctima de la planta de abajo")

	# 4. Una sola escalera por planta, y con su hueco.
	_expect(_stairs_on(new_level_m) == 1,
		"la planta copiada tiene %d escaleras: la de arriba ya existía y no debe duplicarse" % _stairs_on(new_level_m))
	# Un hueco vertical por pareja de plantas, y ninguno repetido: lo que la copia
	# no debe hacer es perforar dos veces el mismo forjado.
	var repeated_voids: PackedStringArray = _repeated_vertical_openings()
	_expect(repeated_voids.is_empty(), "huecos verticales repetidos: %s" % ", ".join(repeated_voids))
	_expect(_vertical_openings_touching(new_level_m) == 1,
		"la planta copiada debería tener un hueco vertical con la de abajo, tiene %d" % _vertical_openings_touching(new_level_m))
	_expect(_stair_has_access(new_level_m),
		"la escalera de la planta copiada queda tapiada: sin ninguna puerta desde las salas nuevas")

	# 5. Ids: ninguno repetido, y el escenario sigue siendo exportable.
	var repeated: PackedStringArray = _repeated_ids()
	_expect(repeated.is_empty(), "ids repetidos tras copiar: %s" % ", ".join(repeated))
	var errors: Array = Serializer.validate_scenario(_editor.editor_data)
	_expect(errors.is_empty(), "el escenario copiado no valida: %s" % str(errors))

	# 6. Y la planta vacía sigue saliendo vacía.
	_build_ground_floor()
	_editor.current_floor_index = 0
	_editor._create_floor(false)
	var empty_level_m: float = _editor._current_floor_level_m()
	_expect(_rooms_on(empty_level_m) == _stairs_on(empty_level_m),
		"la planta 'vacía' trae salas: %d, y solo debería tener el hueco de escalera" % _rooms_on(empty_level_m))

	remove_child(_editor)
	_editor.free()
	_editor = null
	_finish()


# ── Escenario ───────────────────────────────────────────────────────────────
func _blank() -> void:
	_editor.editor_data = {
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1
	}
	_editor.current_floor_index = 0


## Una planta baja de verdad: dos estancias, un pasillo, una escalera, mobiliario,
## un detector, una víctima y el inicio en primera persona.
func _build_ground_floor() -> void:
	_blank()
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.0))
	_draw(TOOL_ROOM, Vector2(0.0, 4.2), Vector2(4.0, 7.2))
	_draw(TOOL_CORRIDOR, Vector2(0.2, 3.0), Vector2(3.8, 3.0))
	_draw(TOOL_STAIRS, Vector2(4.2, 0.0), Vector2(6.6, 3.4))
	_click(TOOL_OBJECT, Vector2(1.5, 1.5))
	_click(TOOL_OBJECT, Vector2(2.5, 5.5))
	_click(TOOL_DETECTOR, Vector2(2.0, 3.6))
	_click(TOOL_VICTIM, Vector2(1.0, 5.0))
	_click(TOOL_PLAYER_START, Vector2(3.0, 1.0))
	_editor.current_floor_index = 0


func _draw(tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(from_m)
	_editor._handle_release(to_m)


func _click(tool_id: int, pos_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(pos_m)


# ── Cuentas ─────────────────────────────────────────────────────────────────
func _floors() -> int:
	return Array(_editor.editor_data.get("floors", [])).size()


func _dialog_visible() -> bool:
	var dialog := _editor.get_node_or_null("CanvasLayer/NewFloorDialog") as ConfirmationDialog
	return dialog != null and dialog.visible


func _on_level(room: Dictionary, level_m: float) -> bool:
	return absf(float(room.get("floor_level_z_m", 0.0)) - level_m) < 0.05


func _rooms_on(level_m: float) -> int:
	var count: int = 0
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and _on_level(room, level_m):
			count += 1
	return count


func _stairs_on(level_m: float) -> int:
	var count: int = 0
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if _on_level(room, level_m) and StairPlanRules.is_stair_room(room):
			count += 1
	return count


func _objects_on(level_m: float) -> int:
	var count: int = 0
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and _on_level(room, level_m):
			count += Array(Dictionary(room).get("fuel_objects", [])).size()
	return count


func _openings_on(level_m: float) -> int:
	var count: int = 0
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = opening
		if bool(op.get("is_vertical", false)):
			continue
		if absf(_editor._room_id_floor_level(int(op.get("a", -1))) - level_m) < 0.05:
			count += 1
	return count


func _vertical_openings() -> int:
	var count: int = 0
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) == TYPE_DICTIONARY and bool(Dictionary(opening).get("is_vertical", false)):
			count += 1
	return count


## Los huecos verticales que llegan a esa planta.
func _vertical_openings_touching(level_m: float) -> int:
	var count: int = 0
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = opening
		if not bool(op.get("is_vertical", false)):
			continue
		var a_level: float = _editor._room_id_floor_level(int(op.get("a", -1)))
		var b_level: float = _editor._room_id_floor_level(int(op.get("b", -1)))
		if absf(a_level - level_m) < 0.05 or absf(b_level - level_m) < 0.05:
			count += 1
	return count


## Dos huecos verticales entre las mismas dos salas: el forjado abierto dos veces.
func _repeated_vertical_openings() -> PackedStringArray:
	var seen: Dictionary = {}
	var repeated := PackedStringArray()
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = opening
		if not bool(op.get("is_vertical", false)):
			continue
		var a_id: int = int(op.get("a", -1))
		var b_id: int = int(op.get("b", -1))
		var key: String = "%d-%d" % [mini(a_id, b_id), maxi(a_id, b_id)]
		if seen.has(key):
			repeated.append(key)
		seen[key] = true
	return repeated


func _detectors_on(level_m: float) -> int:
	var count: int = 0
	for detector in _editor.editor_data.get("detectors", []):
		if typeof(detector) != TYPE_DICTIONARY:
			continue
		if absf(_editor._room_id_floor_level(int(Dictionary(detector).get("room_id", -1))) - level_m) < 0.05:
			count += 1
	return count


func _victims_on(level_m: float) -> int:
	var count: int = 0
	for victim in _editor.editor_data.get("victims", []):
		if typeof(victim) != TYPE_DICTIONARY:
			continue
		if absf(_editor._room_id_floor_level(int(Dictionary(victim).get("room_id", -1))) - level_m) < 0.05:
			count += 1
	return count


func _player_start_on(level_m: float) -> bool:
	var start: Dictionary = _editor.editor_data.get("player_start", {})
	if not start.has("room_id"):
		return false
	return absf(_editor._room_id_floor_level(int(start.get("room_id", -1))) - level_m) < 0.05


## Si la escalera de esa planta tiene por dónde entrar desde las salas de al lado.
func _stair_has_access(level_m: float) -> bool:
	var stair_ids: Dictionary = {}
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if _on_level(room, level_m) and StairPlanRules.is_stair_room(room):
			stair_ids[int(Dictionary(room).get("id", -1))] = true
	if stair_ids.is_empty():
		return false
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = opening
		if bool(op.get("is_vertical", false)):
			continue
		if stair_ids.has(int(op.get("a", -1))) or stair_ids.has(int(op.get("b", -1))):
			return true
	return false


func _repeated_ids() -> PackedStringArray:
	var repeated := PackedStringArray()
	var room_ids: Dictionary = {}
	var object_ids: Dictionary = {}
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		var room_id: int = int(room_dict.get("id", -1))
		if room_ids.has(room_id):
			repeated.append("sala %d" % room_id)
		room_ids[room_id] = true
		for obj in Array(room_dict.get("fuel_objects", [])):
			if typeof(obj) != TYPE_DICTIONARY:
				continue
			var object_id: String = String(Dictionary(obj).get("id", ""))
			if object_ids.has(object_id):
				repeated.append("objeto %s" % object_id)
			object_ids[object_id] = true
	var detector_ids: Dictionary = {}
	for detector in _editor.editor_data.get("detectors", []):
		if typeof(detector) != TYPE_DICTIONARY:
			continue
		var detector_id: String = String(Dictionary(detector).get("id", ""))
		if detector_ids.has(detector_id):
			repeated.append("detector %s" % detector_id)
		detector_ids[detector_id] = true
	return repeated


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[validate_editor_floor_copy] PASS: la planta nueva se elige vacía o copiada, y la copia sube obra pero no personas")
		get_tree().quit(0)
		return
	print("[validate_editor_floor_copy] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
