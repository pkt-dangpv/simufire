extends Node
## Guardia: en la vista 3D se dibujan muros y salas, no solo se miran.
##
## El usuario lo pidio asi: "que se puedan construir los muros en 3d en tiempo
## real, que el usuario pueda dibujarlos en 3d". Hasta ahora la vista 3D solo
## dejaba colocar cosas -puertas, objetos, detectores- y las cuatro herramientas
## que trazan geometria estaban "reservadas al modo 2D".
##
## La guardia arrastra con el raton sobre el suelo del 3D y comprueba que sale
## una sala de verdad, con su rectangulo, y que el punto donde se solto manda.
##
## Y las dos cosas que hacen que dibujar en 3D sirva para algo mas que un boceto:
##
##  - La MEDIDA TECLEADA. En perspectiva el raton no es preciso: un mismo gesto
##    da una sala distinta segun el angulo de la camara. Por eso se escribe "4;3"
##    e Intro sin soltar, igual que en planta. La linea de estado lo anunciaba en
##    3D desde el primer dia y no funcionaba: las teclas no llegaban.
##  - Dibujar en una PLANTA ALTA, donde el suelo no esta a cota cero.
##
## Uso: godot --headless --path . tools/validate_editor_draw_in_3d.tscn

const TOOL_SELECT: int = 0
const TOOL_EXTERIOR_WALL: int = 1
const TOOL_ROOM: int = 2
const MODE_3D: int = 1

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

	editor.editor_data = _one_room_scenario()
	editor.current_floor_index = 0
	editor._set_editor_view_mode(MODE_3D)
	await get_tree().process_frame

	# La herramienta de sala ya no esta prohibida en 3D.
	_expect(editor._tool_available_in_current_mode(TOOL_ROOM), "la herramienta Sala sigue prohibida en la vista 3D")
	_expect(editor._tool_available_in_current_mode(TOOL_EXTERIOR_WALL), "la herramienta Exterior sigue prohibida en la vista 3D")

	var rooms_before: int = Array(editor.editor_data.get("rooms_data", [])).size()
	editor.current_tool = TOOL_ROOM

	# Se arrastra sobre el suelo, en pantalla, como haria una persona.
	var viewport_size: Vector2 = editor.get_viewport().get_visible_rect().size
	var from_px: Vector2 = viewport_size * Vector2(0.42, 0.62)
	var to_px: Vector2 = viewport_size * Vector2(0.58, 0.74)
	var start_m: Variant = editor._screen_to_floor_m_3d(from_px)
	var end_m: Variant = editor._screen_to_floor_m_3d(to_px)
	_expect(typeof(start_m) == TYPE_VECTOR2 and typeof(end_m) == TYPE_VECTOR2,
		"la pantalla no se convierte a suelo en 3D: sin eso no se puede dibujar")

	editor._unhandled_input(_mouse(from_px, true))
	_expect(editor.drag != 0, "pulsar sobre el suelo en 3D no empieza a dibujar")
	editor._unhandled_input(_motion(to_px))
	var preview := editor.get_node_or_null("EditorWorld3D/DrawPreview3D")
	_expect(preview != null and (preview as Node3D).visible,
		"no se ve la caja de previsualizacion mientras se traza en 3D")
	editor._unhandled_input(_mouse(to_px, false))

	var rooms_after: int = Array(editor.editor_data.get("rooms_data", [])).size()
	_expect(rooms_after == rooms_before + 1, "arrastrar en 3D no crea la sala (%d salas antes, %d despues)" % [rooms_before, rooms_after])
	if rooms_after == rooms_before + 1 and typeof(start_m) == TYPE_VECTOR2 and typeof(end_m) == TYPE_VECTOR2:
		var new_room: Dictionary = editor.editor_data["rooms_data"][rooms_after - 1]
		var rect: Rect2 = editor._get_room_rect(int(new_room.get("id", -1)))
		var expected := Rect2(Vector2(start_m).min(Vector2(end_m)), (Vector2(end_m) - Vector2(start_m)).abs())
		_expect(rect.size.x > 0.2 and rect.size.y > 0.2, "la sala dibujada en 3D sale sin tamaño: %s" % str(rect))
		# Medio metro de margen: el encaje a las salas vecinas mueve aristas.
		_expect(rect.get_center().distance_to(expected.get_center()) < 0.75,
			"la sala no sale donde se solto el raton: esperada en %s y esta en %s" % [str(expected.get_center()), str(rect.get_center())])
		_expect(not editor._is_corridor_room(new_room), "lo dibujado con la herramienta Sala no deberia ser un pasillo")

	# La medida tecleada: en perspectiva es la unica forma de ser exacto.
	editor.editor_data = _one_room_scenario()
	editor.current_floor_index = 0
	await get_tree().process_frame
	editor.current_tool = TOOL_ROOM
	editor._unhandled_input(_mouse(from_px, true))
	editor._unhandled_input(_motion(to_px))
	for character in ["4", ";", "3"]:
		editor._unhandled_input(_typed(character))
	_expect(editor._typed_measure == "4;3",
		"lo tecleado en 3D no se recoge: se lleva '%s'" % editor._typed_measure)
	editor._unhandled_input(_key(KEY_ENTER))
	var typed_rooms: Array = editor.editor_data.get("rooms_data", [])
	if typed_rooms.size() >= 2:
		var typed_rect: Rect2 = editor._get_room_rect(int(Dictionary(typed_rooms[-1]).get("id", -1)))
		_expect(absf(typed_rect.size.x - 4.0) < 0.01 and absf(typed_rect.size.y - 3.0) < 0.01,
			"la medida escrita en 3D no manda: se pidió 4,00 × 3,00 y salió %.2f × %.2f" % [typed_rect.size.x, typed_rect.size.y])
	else:
		_expect(false, "escribir la medida en 3D no crea la sala")

	# Y en una planta alta, donde el suelo del 3D no esta a cota cero.
	editor.editor_data = _one_room_scenario()
	editor.current_floor_index = 0
	editor._add_floor_pressed()
	editor.current_floor_index = 1
	editor._sync_floor_controls()
	await get_tree().process_frame
	var upper_level_m: float = editor._current_floor_level_m()
	_expect(upper_level_m > 0.5, "la planta alta deberia estar por encima de la baja (cota %.2f)" % upper_level_m)
	# Otro gesto: en perspectiva, un arrastre casi horizontal en pantalla da una
	# franja sin fondo, y a la cota de la planta alta estos pixeles caen asi.
	# Lo que se prueba aqui es la COTA, no la punteria.
	var up_from_px: Vector2 = viewport_size * Vector2(0.44, 0.50)
	var up_to_px: Vector2 = viewport_size * Vector2(0.62, 0.78)
	editor.current_tool = TOOL_ROOM
	editor._unhandled_input(_mouse(up_from_px, true))
	editor._unhandled_input(_motion(up_to_px))
	editor._unhandled_input(_mouse(up_to_px, false))
	var upstairs: int = 0
	for room in editor.editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and absf(float(Dictionary(room).get("floor_level_z_m", 0.0)) - upper_level_m) < 0.05:
			upstairs += 1
	_expect(upstairs == 1, "dibujar en 3D estando en la planta alta deja %d salas alli" % upstairs)

	# El arrastre plano: en perspectiva sale solo, y la negativa tiene que decir
	# como salir de ahi en vez de dejarte mirando "demasiado pequeña".
	editor.current_floor_index = 0
	editor.current_tool = TOOL_ROOM
	editor._handle_press(Vector2(0.0, 0.0))
	editor._handle_release(Vector2(4.0, 0.01))
	var flat_status: String = editor._status_label.text if editor._status_label != null else ""
	_expect(flat_status.contains("escribe la medida") or flat_status.contains("gira la vista"),
		"un arrastre plano en 3D se rechaza sin decir cómo salir: \"%s\"" % flat_status)

	# Y la previsualizacion se recoge al soltar.
	var preview_after := editor.get_node_or_null("EditorWorld3D/DrawPreview3D") as Node3D
	_expect(preview_after == null or not preview_after.visible, "la caja de previsualizacion se queda puesta despues de soltar")

	remove_child(editor)
	editor.free()
	_finish()


func _mouse(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event


func _typed(character: String) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = character.to_upper().unicode_at(0)
	event.unicode = character.unicode_at(0)
	return event


func _key(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	return event


func _one_room_scenario() -> Dictionary:
	return {
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [],
		"room_rect_m": {"0": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0}},
		"rooms_data": [{
			"id": 0, "name": "Salón", "kind": "generic", "rotation_deg": 0.0,
			"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
		}],
		"openings_data": [],
		"detectors": [],
		"victims": [],
		"player_start": {},
		"ignition_room_id": -1
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[validate_editor_draw_in_3d] PASS: se dibuja arrastrando en 3D, con medida escrita y en plantas altas")
		get_tree().quit(0)
		return
	print("[validate_editor_draw_in_3d] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
