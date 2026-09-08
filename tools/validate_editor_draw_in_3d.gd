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
		print("[validate_editor_draw_in_3d] PASS: se dibuja arrastrando sobre el suelo de la vista 3D")
		get_tree().quit(0)
		return
	print("[validate_editor_draw_in_3d] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
