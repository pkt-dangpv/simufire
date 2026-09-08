extends Node
## Guardia: una escalera dibujada en el editor se puede subir en primera persona.
##
## La suite ya tenia guardias de escalera, pero probaban el RELLANO del bloque de
## pisos, que se construye solo. Nadie probaba el camino de una persona: dibujar
## la escalera con la herramienta, exportar y entrar en primera persona. Y ahi
## habia dos fallos que el usuario vio en cuanto lo uso:
##
##  1. La escalera nacia TAPIADA. El hueco vertical une las dos plantas, pero
##     nadie abria el paso a la sala de al lado: en el plano parecia conectada
##     -las salas se tocan- y en primera persona era un tabique.
##  2. El hueco nacia SIN PAREDES, asi que el descansillo era una repisa en el
##     vacio: un paso de lado y te caias a la planta de abajo.
##
## La guardia dibuja con la herramienta, exporta como hace "Iniciar simulacion",
## monta el mundo FP y SUBE: primer tramo, cruce del descansillo y segundo
## tramo. Si al final el jugador no esta en la planta de arriba, falla.
##
## OJO al montarla: el editor tiene su propia vista previa 3D y vive en el mismo
## espacio fisico que el mundo FP. Con los dos a la vez el jugador choca con
## paredes del previo y parece un fallo de la escalera; por eso el editor se
## libera antes de construir el mundo.
##
## Uso: godot --headless --path . tools/validate_editor_stairs_climbable.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")

## Herramientas del editor, por su numero en el enum Tool.
const TOOL_ROOM: int = 1
const StairPlanRules := preload("res://editor/StairPlanRules.gd")
const TOOL_STAIRS: int = 3
const TOOL_OBJECT: int = 7
const TOOL_IGNITION: int = 8

const UPPER_LEVEL_M: float = 2.90
const STEP_S: float = 1.0 / 60.0

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	var editor: Node = packed.instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Se dibuja como se dibuja: una sala, una escalera pegada a ella, y un
	#    objeto encendido para que el escenario sea exportable.
	editor.editor_data = _blank_scenario()
	editor.current_floor_index = 0
	editor.current_tool = TOOL_ROOM
	editor._handle_press(Vector2(0.0, 0.0))
	editor._handle_release(Vector2(4.0, 3.0))
	editor.current_tool = TOOL_STAIRS
	editor._handle_press(Vector2(4.0, 0.0))
	editor._handle_release(Vector2(6.4, 3.4))
	editor.current_tool = TOOL_OBJECT
	editor._handle_press(Vector2(1.5, 1.5))
	editor.current_tool = TOOL_IGNITION
	editor._handle_press(Vector2(1.5, 1.5))

	var rooms: Array = editor.editor_data.get("rooms_data", [])
	_expect(rooms.size() == 3, "dibujar sala + escalera deberia dejar 3 salas, hay %d" % rooms.size())
	var access_openings: int = 0
	var vertical_openings: int = 0
	for opening in editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		if bool(Dictionary(opening).get("is_vertical", false)):
			vertical_openings += 1
		else:
			access_openings += 1
	_expect(vertical_openings == 1, "falta el hueco vertical entre plantas (hay %d)" % vertical_openings)
	_expect(access_openings >= 1, "la escalera se dibuja tapiada: sin paso a ninguna habitación")

	# 2. Se exporta y se monta el modelo, como al iniciar la simulacion.
	var runtime: Dictionary = Serializer.to_runtime_template(editor.editor_data)
	var building: BuildingModel = BuildingModelScript.new()
	if not building.load_template_data(runtime):
		_expect(false, "BuildingModel rechaza el escenario exportado")
		_finish(editor, building, null)
		return

	# El editor se va ANTES del mundo FP: su vista previa 3D comparte espacio
	# fisico y el jugador chocaria con paredes que no son las del escenario.
	remove_child(editor)
	editor.free()
	editor = null
	await get_tree().process_frame

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "ValidateEditorStairsClimbable"
	fp.exterior_context_enabled = false
	fp.show_fp_detectors = false
	fp.show_fp_victims = false
	add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	await get_tree().physics_frame

	var world := fp.get_node_or_null("FirstPersonWorld")
	if world == null:
		_expect(false, "no se construye el mundo en primera persona")
		_finish(null, building, fp)
		return

	# 3. Se sube.
	var stair_room: RoomModel = null
	for key in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(key))
		if room != null and BuildingLevels.is_stairwell(room) and room.floor_level_z_m < 0.1:
			stair_room = room
			break
	if stair_room == null:
		_expect(false, "no hay hueco de escalera en la planta baja")
		_finish(null, building, fp)
		return

	var rect: Rect2 = building.get_room_rects_m().get(stair_room.id, Rect2())
	var dir: Vector2 = BuildingLevels.stair_run_direction(stair_room)
	var along_size: float = rect.size.y if absf(dir.y) > absf(dir.x) else rect.size.x
	var across: Vector2 = Vector2(dir.y, dir.x).abs()
	var across_size: float = rect.size.x if absf(dir.y) > absf(dir.x) else rect.size.y
	# Se entra por el pie de la escalera, en el carril del primer tramo.
	var entry_2d: Vector2 = rect.get_center() - dir * (along_size * 0.5 - 0.35) + across * (across_size * 0.25)
	var final_y: float = await _climb(fp, entry_2d, dir, across)

	_expect(final_y > UPPER_LEVEL_M - 0.40, "no se llega a la planta de arriba: se acaba en y=%.2f y la planta esta a %.2f" % [final_y, UPPER_LEVEL_M])
	_expect(final_y > -1.0, "el jugador se cae por el hueco de la escalera: acaba en y=%.2f" % final_y)

	await _check_chaining()

	_finish(null, building, fp)


## Encadenar plantas: una escalera sobre otra, cada una con su acceso y su hueco.
##
## Es lo segundo que fallaba: la escalera de arriba nacia tapiada porque el
## acceso automatico solo miraba salas de la misma planta y se saltaba las otras
## escaleras, que es justo lo que tiene al lado al encadenar.
func _check_chaining() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	var editor: Node = packed.instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	editor.editor_data = _blank_scenario()
	editor.current_floor_index = 0
	_draw(editor, TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.4))
	_draw(editor, TOOL_STAIRS, Vector2(4.0, 0.0), Vector2(6.4, 3.4))
	editor.current_floor_index = 1
	_draw(editor, TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.4))
	_draw(editor, TOOL_STAIRS, Vector2(6.4, 0.0), Vector2(8.8, 3.4))

	var floors: Array = editor.editor_data.get("floors", [])
	_expect(floors.size() == 3, "encadenar dos escaleras deberia dejar 3 plantas, hay %d" % floors.size())
	var verticals: int = 0
	var access_by_room: Dictionary = {}
	for opening in editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = opening
		if bool(op.get("is_vertical", false)):
			verticals += 1
			continue
		access_by_room[int(op.get("a", -1))] = true
		access_by_room[int(op.get("b", -1))] = true
	_expect(verticals == 2, "deberia haber un hueco vertical por escalera (hay %d)" % verticals)
	for room in editor.editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var room_dict: Dictionary = room
		if not StairPlanRules.is_stair_room(room_dict):
			continue
		# La escalera de la ultima planta puede quedarse sin nada al lado: alli
		# todavia no hay nada dibujado. Las demas tienen que tener por donde entrar.
		if float(room_dict.get("floor_level_z_m", 0.0)) >= 5.0:
			continue
		var room_id: int = int(room_dict.get("id", -1))
		_expect(access_by_room.has(room_id), "la escalera %d (%s) queda tapiada: sin ningun paso en pared" % [room_id, String(room_dict.get("name", ""))])
	remove_child(editor)
	editor.free()


func _draw(editor: Node, tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	editor.current_tool = tool_id
	editor._handle_press(from_m)
	editor._handle_release(to_m)


## Sube la escalera como se sube: de frente hasta el descansillo, se cruza al
## otro carril -los dos tramos van uno al lado del otro- y se sigue en sentido
## contrario. Devuelve la cota final del jugador.
func _climb(fp: Node, entry_2d: Vector2, dir: Vector2, across: Vector2) -> float:
	fp.set_physics_process(false)
	fp.global_position = fp._to_world(Vector3(entry_2d.x, 0.6, entry_2d.y), 0.0)
	var heading: Vector2 = dir
	for i in range(900):
		if i >= 420 and i < 500:
			heading = -across
		elif i >= 500:
			heading = -dir
		fp.velocity.x = heading.x * 1.6
		fp.velocity.z = heading.y * 1.6
		if fp.is_on_floor():
			fp.velocity.y = -0.05
		else:
			fp.velocity.y -= 9.8 * STEP_S
		fp.move_and_slide()
		await get_tree().physics_frame
	print("[validate_editor_stairs] la subida acaba en y=%.2f" % fp.global_position.y)
	return fp.global_position.y


func _blank_scenario() -> Dictionary:
	return {
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [],
		"room_rect_m": {},
		"rooms_data": [],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"player_start": {},
		"ignition_room_id": -1
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(editor: Node, building: BuildingModel, fp: Node) -> void:
	if fp != null:
		remove_child(fp)
		fp.free()
	if building != null:
		building.free()
	if editor != null:
		remove_child(editor)
		editor.free()
	if _failures.is_empty():
		print("[validate_editor_stairs] PASS: la escalera dibujada tiene acceso y se sube hasta arriba")
		get_tree().quit(0)
		return
	print("[validate_editor_stairs] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
