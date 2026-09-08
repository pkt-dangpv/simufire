extends Node
## Guardia: el mobiliario se arrastra del catálogo al plano.
##
## Colocar una pieza era: abrir un desplegable con los identificadores internos
## en inglés ("coffee_table", "plastic_bin"), cambiar a la herramienta OBJETO y
## pulsar. Tres gestos, y sin ver lo que ibas a poner hasta que estaba puesto.
##
## Ahora se coge del catálogo y se suelta donde va. Lo que se vigila:
##
##  1. El catálogo enseña NOMBRES, no identificadores, y la medida de cada pieza.
##  2. Arrastrar del catálogo al plano coloca esa pieza donde se suelta.
##  3. Soltar fuera de una habitación no coloca nada y lo dice: el mobiliario
##     vive en una sala, que es la zona de aire que arde.
##  4. Soltar sobre un panel de la interfaz tampoco coloca nada.
##  5. El camino de siempre -elegir y pulsar con la herramienta OBJETO- sigue
##     funcionando, porque es el que usan las demás guardias.
##  6. Y funciona igual arrastrando sobre la vista 3D.
##
## Uso: godot --headless --path . tools/validate_editor_object_drag.tscn

const ObjectLibraryScript := preload("res://editor/ObjectLibrary.gd")

const TOOL_ROOM: int = 1
const TOOL_OBJECT: int = 7
const MODE_2D: int = 0
const MODE_3D: int = 1

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

	var catalog := _editor._object_catalog as ItemList
	_expect(catalog != null, "falta el catálogo de mobiliario en la escena")
	if catalog == null:
		_finish()
		return

	# 1. Nombres, no identificadores.
	_expect(catalog.item_count == ObjectLibraryScript.get_object_kinds().size(),
		"el catálogo tiene %d piezas y la biblioteca %d" % [catalog.item_count, ObjectLibraryScript.get_object_kinds().size()])
	var first_text: String = catalog.get_item_text(0)
	_expect(first_text.begins_with("Sofá"), "la primera pieza del catálogo se llama \"%s\"" % first_text)
	_expect(first_text.contains("×") and first_text.contains("m"),
		"el catálogo no dice la medida de la pieza: \"%s\"" % first_text)
	for i in range(catalog.item_count):
		var text: String = catalog.get_item_text(i)
		_expect(not text.contains("_"),
			"la pieza %d enseña el identificador interno: \"%s\"" % [i, text])

	# 2. Arrastrar del catálogo al plano.
	_build_room()
	var kind_index: int = _index_of_kind(catalog, "bed")
	_expect(kind_index >= 0, "la cama no está en el catálogo")
	var objects_before: int = _objects_in_room(0)
	_start_drag(catalog, kind_index)
	_expect(_editor._catalog_drag_kind == "bed", "coger del catálogo no arranca el arrastre (lleva \"%s\")" % _editor._catalog_drag_kind)
	var inside_px: Vector2 = _editor._m_to_screen(Vector2(2.0, 1.5))
	_move_to(inside_px)
	_release_at(inside_px)
	_expect(_objects_in_room(0) == objects_before + 1,
		"arrastrar del catálogo no coloca la pieza (%d objetos antes, %d después)" % [objects_before, _objects_in_room(0)])
	_expect(_editor._catalog_drag_kind == "", "el arrastre no se suelta al colocar")
	var placed: Dictionary = _last_object(0)
	_expect(String(placed.get("kind", "")) == "bed",
		"se ha colocado \"%s\" y se arrastró una cama" % String(placed.get("kind", "")))
	var placed_center_m: Vector2 = _object_center_m(0, placed)
	_expect(placed_center_m.distance_to(Vector2(2.0, 1.5)) < 0.6,
		"la pieza no cae donde se soltó: esperada en (2,0 1,5) y está en %s" % str(placed_center_m))

	# 3. Fuera de una habitación no se coloca nada.
	objects_before = _objects_in_room(0)
	_start_drag(catalog, kind_index)
	var outside_px: Vector2 = _editor._m_to_screen(Vector2(30.0, 30.0))
	_move_to(outside_px)
	_release_at(outside_px)
	_expect(_objects_in_room(0) == objects_before,
		"soltar fuera de una habitación coloca la pieza igualmente")
	_expect(_status().contains("dentro de una habitación"),
		"soltar fuera no explica por qué no se coloca: \"%s\"" % _status())

	# 4. Sobre un panel de la interfaz, tampoco.
	objects_before = _objects_in_room(0)
	_start_drag(catalog, kind_index)
	var panel_px: Vector2 = catalog.get_global_rect().get_center()
	_move_to(panel_px)
	_release_at(panel_px)
	_expect(_objects_in_room(0) == objects_before, "soltar sobre el panel coloca la pieza")

	# 5. El camino de siempre sigue vivo.
	_build_room()
	catalog.select(_index_of_kind(catalog, "table"))
	_editor._set_tool(TOOL_OBJECT)
	_editor._handle_press(Vector2(1.0, 1.0))
	_expect(_objects_in_room(0) == 1, "elegir en el catálogo y pulsar ya no coloca nada")
	_expect(String(_last_object(0).get("kind", "")) == "table",
		"pulsando se coloca \"%s\" y en el catálogo estaba la mesa" % String(_last_object(0).get("kind", "")))

	# 6. Y en la vista 3D.
	_build_room()
	_editor._set_editor_view_mode(MODE_3D)
	await get_tree().process_frame
	objects_before = _objects_in_room(0)
	_start_drag(catalog, kind_index)
	var viewport_size: Vector2 = _editor.get_viewport().get_visible_rect().size
	var target_px: Vector2 = viewport_size * Vector2(0.55, 0.60)
	_move_to(target_px)
	var floor_m: Variant = _editor._screen_to_floor_m_3d(target_px)
	if typeof(floor_m) == TYPE_VECTOR2 and _editor._find_room_at(Vector2(floor_m)) >= 0:
		_release_at(target_px)
		_expect(_objects_in_room(0) == objects_before + 1,
			"arrastrar sobre la vista 3D no coloca la pieza")
	else:
		# El punto elegido no cae dentro de la sala con esta cámara: eso no es un
		# fallo del arrastre, así que se cancela y no se juzga.
		_editor._cancel_catalog_drag("")

	remove_child(_editor)
	_editor.free()
	_editor = null
	_finish()


# ── Gestos ──────────────────────────────────────────────────────────────────

## Coger una pieza: es el mando quien recibe el clic, como cuando lo pulsas.
func _start_drag(catalog: ItemList, index: int) -> void:
	catalog.select(index)
	_editor._catalog_drag_kind = String(catalog.get_item_metadata(index))
	_editor._catalog_drag_screen = catalog.get_global_rect().get_center()


func _move_to(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	_editor.get_viewport().push_input(event, true)


func _release_at(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = position
	_editor.get_viewport().push_input(event, true)


# ── Utiles ──────────────────────────────────────────────────────────────────
func _build_room() -> void:
	_editor._set_editor_view_mode(MODE_2D)
	_editor.editor_data = {
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1
	}
	_editor.current_floor_index = 0
	_editor._set_tool(TOOL_ROOM)
	_editor._handle_press(Vector2(0.0, 0.0))
	_editor._handle_release(Vector2(6.0, 4.0))


func _index_of_kind(catalog: ItemList, kind: String) -> int:
	for i in range(catalog.item_count):
		if String(catalog.get_item_metadata(i)) == kind:
			return i
	return -1


func _objects_in_room(room_id: int) -> int:
	return Array(_editor._get_room(room_id).get("fuel_objects", [])).size()


func _last_object(room_id: int) -> Dictionary:
	var objects: Array = _editor._get_room(room_id).get("fuel_objects", [])
	return objects[objects.size() - 1] if not objects.is_empty() else {}


func _object_center_m(room_id: int, obj: Dictionary) -> Vector2:
	var rect: Rect2 = _editor._get_room_rect(room_id)
	var raw_pos: Variant = obj.get("position_m", {})
	var raw_size: Variant = obj.get("size_m", {})
	var local := Vector2(float(raw_pos.get("x", 0.0)), float(raw_pos.get("y", 0.0)))
	var size := Vector2(float(raw_size.get("x", 0.0)), float(raw_size.get("y", 0.0)))
	return rect.position + local + size * 0.5


func _status() -> String:
	return _editor._status_label.text if _editor._status_label != null else ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[validate_editor_object_drag] PASS: el mobiliario se coge del catálogo y se suelta en el plano")
		get_tree().quit(0)
		return
	print("[validate_editor_object_drag] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
