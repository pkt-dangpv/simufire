extends SceneTree
## Sonda de EQUIVALENCIA de la familia de conductos verticales del editor:
## escalera, patio y portal (D-1, §22 de la auditoria del editor).
##
## Antes de mover sus mutaciones a `ScenarioDocument` se fotografia el escenario
## que dejan en el editor una bateria fija de gestos; despues del corte se vuelve
## a fotografiar y se compara byte a byte. Solo sirve si cubre lo que se mueve:
##
##   - escalera dibujada con la herramienta, y otra encadenada encima,
##   - redimensionar y girar una escalera (arrastra sus tramos y su hueco),
##   - copiar las escaleras de una planta a otra,
##   - patio,
##   - portal con puertas de vivienda, y redimensionarlo,
##   - y deshacer / rehacer entre medias, que es lo que se rompe sin avisar.
##
## Escribe un JSON con una instantanea por paso, claves ordenadas.
##
##   <godot> --headless --path . --script res://tools/probe_vertical_family.gd -- <salida.json>

const TOOL_STAIRS: int = 3
const TOOL_PATIO: int = 14
const TOOL_PORTAL: int = 15

var _editor: Node = null
var _frames: int = 0
var _pasos: Array = []


func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)


func _foto(nombre: String) -> void:
	_pasos.append({"paso": nombre, "escenario": _editor.editor_data.duplicate(true)})


func _arrastra(tool_id: int, desde: Vector2, hasta: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(desde)
	_editor._handle_release(hasta)


func _id_por_nombre(nombre: String) -> int:
	for raw in _editor.editor_data.get("rooms_data", []):
		if String(Dictionary(raw).get("name", "")) == nombre:
			return int(Dictionary(raw).get("id", -1))
	return -1


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var rects: Dictionary = {}
	var rooms: Array = []
	var ops: Array = []
	for p in range(3):
		var id: int = p + 1
		rects[str(id)] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rooms.append({"id": id, "name": "Vivienda %d" % p, "kind": "salon", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": 2.9 * p, "fuel_objects": []})
		ops.append({"a": id, "b": -1, "type": "door", "wall": "right", "offset_m": 0.5,
			"offset_is_fraction": true, "width_m": 0.92, "height_m": 2.05, "sill_m": 0.0, "open_fraction": 1.0})
	_editor.adopt_scenario_data({
		"building_type": "apartment", "apartment_floor_number": 0,
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": 2.9}, {"name": "R+2", "level_m": 5.8}],
		"exterior_walls": [], "room_rect_m": rects, "rooms_data": rooms, "openings_data": ops,
		"detectors": [], "victims": [], "player_start": {}, "ignition_room_id": 1,
	}, 0)
	_foto("00_inicio")

	# Escalera pegada a la vivienda de la baja, subiendo hacia abajo.
	_editor.current_floor_index = 0
	_arrastra(TOOL_STAIRS, Vector2(-3.0, 0.0), Vector2(0.0, 4.0))
	_foto("01_escalera")
	# Otra encadenada desde la planta de arriba: crea planta si hace falta.
	_editor.current_floor_index = 1
	_arrastra(TOOL_STAIRS, Vector2(-3.0, 0.0), Vector2(0.0, 4.0))
	_foto("02_escalera_encadenada")

	var escalera: int = _id_por_nombre("Escalera R")
	_editor._set_room_rect(escalera, Rect2(Vector2(-3.5, 0.0), Vector2(3.5, 4.5)))
	_foto("03_escalera_redimensionada")
	_editor._set_room_rotation(escalera, 90.0)
	_foto("04_escalera_girada")
	_editor._copy_stairs_from_level_to_level(2.9, 5.8)
	_foto("05_escaleras_copiadas")

	_editor.current_floor_index = 0
	_arrastra(TOOL_PATIO, Vector2(0.0, 4.0), Vector2(2.5, 6.5))
	_foto("06_patio")

	_arrastra(TOOL_PORTAL, Vector2(5.0, 0.0), Vector2(9.25, 3.0))
	_foto("07_portal")
	var portal: int = _id_por_nombre("Portal R+1")
	_editor._set_room_rect(portal, Rect2(Vector2(5.0, 0.0), Vector2(4.5, 3.5)))
	_foto("08_portal_redimensionado")
	_editor._set_room_rotation(portal, 90.0)
	_foto("09_portal_no_se_gira")

	_editor._undo_last_action()
	_foto("10_deshacer")
	_editor._undo_last_action()
	_foto("11_deshacer_otra")
	_editor._redo_last_action()
	_foto("12_rehacer")
	_editor._redo_last_action()
	_foto("13_rehacer_otra")

	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://probe_vertical_family.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_pasos, "  ", true))
	f.close()
	print("[probe_vertical_family] %d pasos -> %s" % [_pasos.size(), out])
	quit(0)
	return true
