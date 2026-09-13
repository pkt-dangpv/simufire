extends SceneTree
## Guardarrail del DUEÑO del escenario (D-1, §22 de la auditoria del editor).
##
## `ScenarioDocument` es el unico que deberia escribir el escenario. Mientras la
## mudanza va por familias, esto fija lo que ya esta hecho y no deja retroceder:
##
##  1. **Cada accion de una familia mudada es UNA transaccion.** Se deshace con un
##     solo Ctrl+Z y el escenario queda byte a byte como estaba; rehacer lo deja
##     byte a byte como quedo. Es la garantia que no da una comparacion de
##     entrada y salida: el §21.3 cuenta como deshacer dejo de devolver el estado
##     tal cual y nadie se entero.
##  2. **Las envolturas del editor de esa familia no escriben el diccionario.** Leen
##     y enseñan; escribe el documento.
##  3. **Trinquete**: las escrituras directas a `editor_data` fuera del documento no
##     pueden crecer. Cada familia que se muda baja el limite.
##
##   <godot> --headless --path . --script res://tools/validate_scenario_document.gd

const TOOL_ROOM: int = 1
const TOOL_CORRIDOR: int = 2
const TOOL_STAIRS: int = 3
const TOOL_PATIO: int = 14
const TOOL_PORTAL: int = 15

## Escrituras directas a `editor_data` que quedan en `editor/` fuera del documento.
## Solo puede bajar: 64 al mudar la familia de conductos verticales, 50 al mudar
## la de plantas y 46 al mudar la de aperturas (2026-09-13).
const LIMITE_ESCRITURAS: int = 46

## Las envolturas de la familia de conductos verticales.
const ENVOLTURAS_MUDADAS: Array[String] = [
	"_create_room_at_level", "_create_patio_from_rect", "_create_portal_from_rect",
	"_create_stairs_from_rect", "_open_passages_to_neighbours", "_set_stair_turn_mode_for_room",
	"_set_stair_turn_degrees_for_room", "_next_floor_index_above", "_add_floor_at_level",
	"_copy_stairs_from_level_to_level", "_sync_linked_stair_rects",
	"_apply_stair_rotation_to_linked_rooms", "_sync_vertical_stair_openings",
	"_floor_name_for_level", "_update_room_fields", "_add_opening", "_ensure_floor_data",
	# Plantas (segunda familia).
	"_create_floor", "_delete_floor_pressed", "_on_floor_level_changed", "_set_room_rect",
	# Aperturas (tercera familia).
	"_open_passages_to_circulation", "_delete_opening", "_apply_opening_properties",
	"_create_balcony_door_from_drag", "_create_balcony_door_at", "_create_door_at",
	"_create_hole_at", "_create_window_at",
]

var _editor: Node = null
var _frames: int = 0
var _fails: int = 0


func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)


func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1


func _canon() -> String:
	return JSON.stringify(_editor.editor_data, "", true)


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

	# ── 1. Una accion, un deshacer ──
	# La escalera pegada a la vivienda abre ademas el paso a ella: es el caso que
	# guardaba una instantanea de mas y pedia dos Ctrl+Z.
	_accion("escalera con paso a la vivienda", 0, TOOL_STAIRS, Vector2(-3.0, 0.0), Vector2(0.0, 4.0))
	_accion("escalera encadenada arriba", 1, TOOL_STAIRS, Vector2(-3.0, 0.0), Vector2(0.0, 4.0))
	_accion("patio", 0, TOOL_PATIO, Vector2(0.0, 4.0), Vector2(2.5, 6.5))
	_accion("portal", 0, TOOL_PORTAL, Vector2(5.0, 0.0), Vector2(9.25, 3.0))
	# La familia de plantas: copiar una planta, cambiarle la cota y borrarla.
	_accion_llamada("planta nueva copiando la baja", 0, func(): _editor._create_floor(true))
	_accion_llamada("cambiar la cota de la planta nueva", 3, func(): _editor._on_floor_level_changed(9.25))
	_accion_llamada("borrar la planta nueva", 3, func(): _editor._delete_floor_pressed())
	# La familia de aperturas. La fachada de arriba de la vivienda baja (y = 0)
	# esta libre: la escalera, el patio y el portal quedan a los otros lados.
	_accion_llamada("ventana en la fachada", 0, func(): _editor._create_window_at(Vector2(2.5, 0.0)))
	_accion_llamada("balconera arrastrada", 0, func(): _editor._create_balcony_door_from_drag(Vector2(0.5, 0.0), Vector2(4.0, -1.0)))
	_accion_llamada("borrar una apertura", 0, func(): _editor._delete_opening(Array(_editor.editor_data.get("openings_data", [])).size() - 1))
	# Un pasillo pegado a la vivienda abre paso a ella, y una sala pegada al
	# pasillo abre paso al pasillo: los dos casos en que la herramienta añade
	# aberturas por su cuenta en mitad de la accion.
	_accion("pasillo pegado a la vivienda", 0, TOOL_CORRIDOR, Vector2(0.0, -0.6), Vector2(5.0, -0.6))
	var pasillo := _rect_del_pasillo()
	_accion("sala pegada al pasillo", 0, TOOL_ROOM, pasillo.position - Vector2(0.0, 3.0), Vector2(pasillo.end.x, pasillo.position.y))
	# Editar la ficha: el hueco que acaba de abrirse hacia el pasillo pasa a puerta.
	_accion_llamada("editar una apertura desde la ficha", 0, func(): _editar_ultima_apertura_a_puerta())

	# ── 2 y 3. Quien escribe ──
	_comprobar_escrituras()

	if _fails == 0:
		print("[validate_scenario_document] PASS")
	else:
		push_error("[validate_scenario_document] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _accion(nombre: String, planta: int, tool_id: int, desde: Vector2, hasta: Vector2) -> void:
	_editor.current_floor_index = planta
	var antes: String = _canon()
	_editor.current_tool = tool_id
	_editor._handle_press(desde)
	_editor._handle_release(hasta)
	var despues: String = _canon()
	_eq("%s: cambia el escenario" % nombre, despues != antes, true)
	_editor._undo_last_action()
	_eq("%s: UN deshacer lo deja como estaba" % nombre, _canon() == antes, true)
	_editor._redo_last_action()
	_eq("%s: y rehacer, como quedo" % nombre, _canon() == despues, true)


## La ultima apertura, convertida en puerta por el camino de la ficha, como lo
## hace `validate_corridors`.
func _editar_ultima_apertura_a_puerta() -> void:
	var ops: Array = _editor.editor_data.get("openings_data", [])
	var index: int = ops.size() - 1
	_editor.selected_opening_index = index
	_editor._props.show({"opening": ops[index], "opening_type_label": "Hueco",
		"opening_max_width_m": 3.0, "opening_max_offset_m": 10.0,
		"opening_accepts_balcony": false, "opening_balcony_max_width_m": 3.0})
	_editor._props._opening_type_option.select(0)
	_editor._apply_opening_properties()


## El rectangulo del pasillo de la planta baja que acaba de dibujarse.
func _rect_del_pasillo() -> Rect2:
	for raw in _editor.editor_data.get("rooms_data", []):
		var room: Dictionary = raw
		if _editor._is_corridor_room(room) and absf(float(room.get("floor_level_z_m", 0.0))) < 0.05:
			return _editor._get_room_rect(int(room.get("id", -1)))
	return Rect2(Vector2(0.0, -1.2), Vector2(5.0, 1.2))


## Lo mismo que `_accion`, para las acciones que no se dibujan arrastrando.
func _accion_llamada(nombre: String, planta: int, gesto: Callable) -> void:
	_editor.current_floor_index = planta
	var antes: String = _canon()
	gesto.call()
	var despues: String = _canon()
	_eq("%s: cambia el escenario" % nombre, despues != antes, true)
	_editor._undo_last_action()
	_eq("%s: UN deshacer lo deja como estaba" % nombre, _canon() == antes, true)
	_editor._redo_last_action()
	_eq("%s: y rehacer, como quedo" % nombre, _canon() == despues, true)


func _comprobar_escrituras() -> void:
	var escritura := RegEx.new()
	escritura.compile("editor_data\\[[^\\]]+\\]\\s*=[^=]|^\\s*editor_data\\s*=[^=]")
	var total: int = 0
	var dir := DirAccess.open("res://editor")
	for fichero in dir.get_files():
		if not fichero.ends_with(".gd") or fichero == "ScenarioDocument.gd":
			continue
		var texto: String = FileAccess.get_file_as_string("res://editor/%s" % fichero)
		for linea in texto.split("\n"):
			if not linea.strip_edges().begins_with("#") and escritura.search(linea) != null:
				total += 1
	print("  escrituras directas a editor_data fuera del documento: %d" % total)
	_eq("no crecen (limite %d)" % LIMITE_ESCRITURAS, total <= LIMITE_ESCRITURAS, true)

	var editor_texto: String = FileAccess.get_file_as_string("res://editor/ScenarioEditor.gd")
	var sucias: Array[String] = []
	for nombre in ENVOLTURAS_MUDADAS:
		var cuerpo: String = _cuerpo(editor_texto, nombre)
		if cuerpo == "":
			sucias.append("%s (no esta)" % nombre)
			continue
		if escritura.search(cuerpo) != null or cuerpo.contains(".append(") or cuerpo.contains("openings[") or cuerpo.contains("rooms[") :
			sucias.append(nombre)
	_eq("las envolturas de la familia mudada no escriben", ",".join(sucias), "")


## El cuerpo de una funcion de nivel superior, hasta la siguiente declaracion.
func _cuerpo(texto: String, nombre: String) -> String:
	var inicio: int = texto.find("\nfunc %s(" % nombre)
	if inicio < 0:
		return ""
	var lineas: PackedStringArray = texto.substr(inicio + 1).split("\n")
	var out: PackedStringArray = [lineas[0]]
	for i in range(1, lineas.size()):
		var l: String = lineas[i]
		if l != "" and not l.begins_with("\t") and not l.begins_with(" "):
			break
		out.append(l)
	return "\n".join(out)
