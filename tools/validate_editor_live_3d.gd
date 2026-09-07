extends Node
## Guardia: el 3D en vivo se rehace solo mientras se dibuja en planta.
##
## No basta con que el panel se vea: lo que se pide es que refleje lo que acabas
## de dibujar. Aqui se enciende el panel, se dibuja una sala nueva y se dejan
## pasar unos fotogramas; si el mundo 3D no ha crecido, el panel esta enseñando
## una foto vieja y eso es peor que no tenerlo.
##
## Tambien vigila lo que hace util al panel: que NO se rehaga en cada fotograma.
## Rehacer la malla cuesta unos 80 ms con un piso normal (medido en
## tools/probe_editor_3d_cost.gd), asi que se rehace cuando dejas de mover.
##
## Uso: godot --headless --path . tools/validate_editor_live_3d.tscn

const TOOL_ROOM: int = 2
## Margen sobre el retardo del editor (0,25 s), en fotogramas de fisica.
const SETTLE_FRAMES: int = 40

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
	editor._set_preview_3d_enabled(true)
	await get_tree().physics_frame
	_expect(editor._preview_3d_enabled, "el panel del 3D en vivo no se enciende")

	var viewport := editor.get_node_or_null("CanvasLayer/UI/Preview3DPanel/VBox/Preview3DViewportContainer/Preview3DViewport") as SubViewport
	_expect(viewport != null, "falta el SubViewport del panel en la escena")
	if viewport != null:
		_expect(viewport.world_3d == editor.get_viewport().world_3d, "el panel no comparte el mundo 3D del editor: no veria nada")
	var camera := editor.get_node_or_null("CanvasLayer/UI/Preview3DPanel/VBox/Preview3DViewportContainer/Preview3DViewport/Preview3DCamera") as Camera3D
	_expect(camera != null and camera.current, "la camara del panel no esta activa")

	var rooms_before: int = _rooms_in_3d(editor)
	_expect(rooms_before > 0, "el panel no ha construido ni la sala inicial")

	# Se dibuja una sala mas, como se dibuja: arrastrando.
	editor.current_tool = TOOL_ROOM
	editor._handle_press(Vector2(0.0, 4.0))
	editor._handle_release(Vector2(3.0, 7.0))
	_expect(editor._editor_runtime_dirty, "dibujar una sala no marca el 3D para rehacer")

	for i in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	_expect(not editor._editor_runtime_dirty, "el 3D en vivo no se rehace tras dibujar: se queda con la vista vieja")
	var rooms_after: int = _rooms_in_3d(editor)
	_expect(rooms_after > rooms_before, "el 3D en vivo no enseña la sala nueva (%d salas antes, %d despues)" % [rooms_before, rooms_after])

	# Y lo que se pidio: que SIGA al raton mientras se arrastra, sin esperar al
	# antirrebote. Se mueve la sala 0 con el raton y se mira si su suelo 3D se ha
	# movido en el mismo instante.
	editor._select_room(0)
	var before: Vector3 = _room_floor_position(editor, 0)
	# 1 = ObjectMouseMode.MOVE: el gesto de arrastrar la sala entera.
	editor._begin_room_mouse_edit(1, Vector2(2.0, 1.5))
	editor._update_dragged_room_geometry(Vector2(6.0, 4.5))
	var after: Vector3 = _room_floor_position(editor, 0)
	_expect(before != Vector3.INF and after != Vector3.INF, "no se encuentra el suelo 3D de la sala 0")
	_expect(before.distance_to(after) > 0.5, "el 3D no sigue a la sala mientras se arrastra (%s -> %s)" % [str(before), str(after)])
	editor._handle_release(Vector2(6.0, 4.5))

	# Y al pasar a 3D a pantalla completa el panel se aparta solo.
	editor._set_editor_view_mode(1)
	_expect(not editor._preview_3d_enabled, "el panel sigue encendido en la vista 3D, donde sobra")

	remove_child(editor)
	editor.free()
	_finish()


## Donde esta el suelo 3D de una sala. Se relee cada vez: al rehacer la vista los
## nodos son otros.
func _room_floor_position(editor: Node, room_id: int) -> Vector3:
	var visualizer: Node = editor._editor_visualizer_3d
	if visualizer == null:
		return Vector3.INF
	var items: Dictionary = visualizer._room_items
	if not items.has(room_id):
		return Vector3.INF
	var floor_node := Dictionary(items[room_id]).get("floor") as Node3D
	return floor_node.global_position if floor_node != null else Vector3.INF


func _rooms_in_3d(editor: Node) -> int:
	var visualizer: Node = editor._editor_visualizer_3d
	if visualizer == null:
		return 0
	var rooms: Node = visualizer.get_node_or_null("Rooms")
	return rooms.get_child_count() if rooms != null else 0


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
		print("[validate_editor_live_3d] PASS: el panel se enciende, comparte mundo y se rehace al dibujar")
		get_tree().quit(0)
		return
	print("[validate_editor_live_3d] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
