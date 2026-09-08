extends Node
## Guardia: los pasillos se dibujan por donde el usuario los dibuja.
##
## El trazo del raton es el EJE del pasillo, no su borde, y de ahi salian dos
## fallos que el usuario encontro a mano ("el sistema de pasillos es bastante
## malo... ni siquiera me deja hacer descansillos"):
##
##  1. Al GIRAR, el tramo nuevo sobresalia media anchura por detras de la
##     esquina, asi que los dos tramos solo compartian ese resto: un pasillo de
##     1,20 m dejaba un paso de 0,50 m en el codo. Un giro tiene que ser tan
##     ancho como el pasillo, o no es un giro: es un agujero.
##  2. Dibujando por la JUNTA entre dos habitaciones -que es justo donde va un
##     pasillo-, el eje caia dentro de una de ellas, el recorte se comia el tramo
##     entero y el editor contestaba "cae entero dentro de otra habitación".
##
## Se mide con las cuatro formas que se dibujan de verdad: recto, L de un trazo,
## giro de dos tramos, U de tres y pasillo entre dos habitaciones.
##
## Uso: godot --headless --path . tools/validate_editor_corridors.tscn

const TOOL_ROOM: int = 1
const TOOL_CORRIDOR: int = 2
## El hueco deja 10 cm de margen contra las esquinas del paramento
## (_max_opening_width_for_shared), asi que un paso "de ancho completo" es el
## ancho del pasillo menos ese margen.
const WALL_MARGIN_M: float = 0.15

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

	var width_m: float = float(_editor.corridor_width_m)
	var full_pass_m: float = width_m - WALL_MARGIN_M

	# 1. Un tramo recto sigue siendo un tramo recto.
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 0.0))
	_expect(_rooms() == 1, "un trazo recto deberia dejar un tramo, hay %d" % _rooms())

	# 2. La L de un solo trazo: dos tramos unidos por un paso de ancho completo.
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 4.0))
	_expect(_rooms() == 2, "la L deberia dejar dos tramos, hay %d" % _rooms())
	_expect_passage("L de un trazo", full_pass_m)

	# 3. El giro dibujado como dos tramos: es el caso que fallaba.
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 0.0))
	_draw(TOOL_CORRIDOR, Vector2(6.0, 0.0), Vector2(6.0, 5.0))
	_expect(_rooms() == 2, "el giro deberia dejar dos tramos, hay %d" % _rooms())
	_expect_passage("giro de dos tramos", full_pass_m)
	_expect_square_corner("giro de dos tramos", width_m)

	# 4. La U de tres tramos: dos codos, los dos de ancho completo.
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 0.0))
	_draw(TOOL_CORRIDOR, Vector2(6.0, 0.0), Vector2(6.0, 5.0))
	_draw(TOOL_CORRIDOR, Vector2(6.0, 5.0), Vector2(0.0, 5.0))
	_expect(_rooms() == 3, "la U deberia dejar tres tramos, hay %d" % _rooms())
	var passages: Array[float] = _passage_widths()
	_expect(passages.size() == 2, "la U deberia tener dos codos abiertos, tiene %d" % passages.size())
	for width in passages:
		_expect(width >= full_pass_m,
			"un codo de la U mide %.2f m y el pasillo %.2f m" % [width, width_m])

	# 5. El pasillo entre dos habitaciones, dibujado por su junta: antes se
	#    negaba a existir.
	_reset()
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.0))
	_draw(TOOL_ROOM, Vector2(0.0, 4.2), Vector2(4.0, 7.2))
	_draw(TOOL_CORRIDOR, Vector2(0.2, 3.0), Vector2(3.8, 3.0))
	_expect(_rooms() == 3, "el pasillo entre las dos salas no se crea (%d salas)" % _rooms())
	var corridor_rect: Rect2 = _last_corridor_rect()
	_expect(corridor_rect.size.y > 0.0, "no hay tramo de pasillo que medir")
	if corridor_rect.size.y > 0.0:
		# Tiene que caber en el hueco (y 3,00 a 4,20) sin pisar ninguna sala.
		_expect(corridor_rect.position.y >= 2.99 and corridor_rect.end.y <= 4.21,
			"el pasillo no se mete en el hueco entre las salas: %s" % str(corridor_rect))
	var neighbours: Array[int] = _passage_neighbours()
	_expect(neighbours.size() == 2,
		"el pasillo deberia abrir paso a las dos habitaciones, abre a %d" % neighbours.size())
	for width in _passage_widths():
		_expect(width >= full_pass_m,
			"el paso a una habitación mide %.2f m y el pasillo %.2f m" % [width, width_m])

	remove_child(_editor)
	_editor.free()
	_editor = null
	_finish()


# ── Utiles ──────────────────────────────────────────────────────────────────
func _reset() -> void:
	_editor.editor_data = {
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1
	}
	_editor.current_floor_index = 0


func _draw(tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(from_m)
	_editor._handle_release(to_m)


func _rooms() -> int:
	return Array(_editor.editor_data.get("rooms_data", [])).size()


func _passage_widths() -> Array[float]:
	var widths: Array[float] = []
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		if bool(Dictionary(opening).get("is_vertical", false)):
			continue
		widths.append(float(Dictionary(opening).get("width_m", 0.0)))
	return widths


## A quien da paso el ultimo pasillo creado, sin repetir.
func _passage_neighbours() -> Array[int]:
	var corridor_ids: Dictionary = {}
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and _editor._is_corridor_room(room):
			corridor_ids[int(Dictionary(room).get("id", -1))] = true
	var neighbours: Array[int] = []
	for opening in _editor.editor_data.get("openings_data", []):
		if typeof(opening) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = opening
		var a: int = int(op.get("a", -1))
		var b: int = int(op.get("b", -1))
		var other: int = b if corridor_ids.has(a) else a
		if not corridor_ids.has(other) and not neighbours.has(other):
			neighbours.append(other)
	return neighbours


func _last_corridor_rect() -> Rect2:
	var rooms: Array = _editor.editor_data.get("rooms_data", [])
	for i in range(rooms.size() - 1, -1, -1):
		if typeof(rooms[i]) == TYPE_DICTIONARY and _editor._is_corridor_room(rooms[i]):
			return _editor._get_room_rect(int(Dictionary(rooms[i]).get("id", -1)))
	return Rect2()


func _expect_passage(label: String, full_pass_m: float) -> void:
	var widths: Array[float] = _passage_widths()
	if widths.is_empty():
		_failures.append("%s: los tramos no se unen con ningún paso" % label)
		return
	var widest: float = 0.0
	for width in widths:
		widest = maxf(widest, width)
	if widest < full_pass_m:
		_failures.append("%s: el paso del codo mide %.2f m, y debería ser el ancho del pasillo" % [label, widest])


## Un codo de verdad: los dos tramos comparten una arista tan larga como el ancho
## del pasillo. Si comparten menos, la esquina se ha quedado en un pico.
func _expect_square_corner(label: String, width_m: float) -> void:
	var rects: Array[Rect2] = []
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY and _editor._is_corridor_room(room):
			rects.append(_editor._get_room_rect(int(Dictionary(room).get("id", -1))))
	if rects.size() != 2:
		return
	var x_overlap: float = minf(rects[0].end.x, rects[1].end.x) - maxf(rects[0].position.x, rects[1].position.x)
	var y_overlap: float = minf(rects[0].end.y, rects[1].end.y) - maxf(rects[0].position.y, rects[1].position.y)
	var shared_m: float = maxf(x_overlap, y_overlap)
	if shared_m < width_m - 0.01:
		_failures.append("%s: los tramos solo comparten %.2f m de los %.2f m del pasillo" % [label, shared_m, width_m])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[validate_editor_corridors] PASS: giros cuadrados y pasillos que caben donde se dibujan")
		get_tree().quit(0)
		return
	print("[validate_editor_corridors] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
