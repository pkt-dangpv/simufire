extends SceneTree
## Sonda: cuanto mide el paso en el codo de un pasillo.
##
## El pasillo se dibuja por tramos y los tramos se unen solos con un hueco. La
## duda es el codo: dos tramos perpendiculares comparten solo la esquina, y el
## hueco sale del solape geometrico. Si ese solape es medio metro, el paso es de
## medio metro aunque el pasillo mida 1,20.
##
##   godot --headless --path . --script res://tools/probe_corridor_corner.gd

const TOOL_ROOM: int = 2
const TOOL_CORRIDOR: int = 3

var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	print("ancho de pasillo configurado: %.2f m" % _editor.corridor_width_m)

	print("")
	print("=== A. una L de un solo trazo")
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 4.0))
	_dump()

	print("")
	print("=== B. dos tramos sueltos que hacen un giro")
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 0.0))
	_draw(TOOL_CORRIDOR, Vector2(6.0, 0.0), Vector2(6.0, 5.0))
	_dump()

	print("")
	print("=== C. tres tramos en U")
	_reset()
	_draw(TOOL_CORRIDOR, Vector2(0.0, 0.0), Vector2(6.0, 0.0))
	_draw(TOOL_CORRIDOR, Vector2(6.0, 0.0), Vector2(6.0, 5.0))
	_draw(TOOL_CORRIDOR, Vector2(6.0, 5.0), Vector2(0.0, 5.0))
	_dump()

	print("")
	print("=== D. un pasillo pegado a dos habitaciones")
	_reset()
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.0))
	_draw(TOOL_ROOM, Vector2(0.0, 4.2), Vector2(4.0, 7.2))
	_draw(TOOL_CORRIDOR, Vector2(0.2, 3.0), Vector2(3.8, 3.0))
	_dump()

	quit(0)
	return true


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


func _dump() -> void:
	for room in _editor.editor_data.get("rooms_data", []):
		var rect: Rect2 = _editor._get_room_rect(int(room.get("id", -1)))
		print("  sala %2d %-24s rect %5.2f,%5.2f  %4.2f x %4.2f" % [
			int(room.get("id", -1)), String(room.get("name", "")),
			rect.position.x, rect.position.y, rect.size.x, rect.size.y
		])
	var openings: Array = _editor.editor_data.get("openings_data", [])
	if openings.is_empty():
		print("  (sin pasos: las piezas no se han unido)")
	for op in openings:
		print("  paso %-6s a=%2d b=%2d pared %-6s offset %.2f  ANCHO %.2f m%s" % [
			String(op.get("type", "")), int(op.get("a", -1)), int(op.get("b", -1)),
			String(op.get("wall", "")), float(op.get("offset_m", 0.0)),
			float(op.get("width_m", 0.0)),
			"   <-- MAS ESTRECHO QUE EL PASILLO" if float(op.get("width_m", 0.0)) < _editor.corridor_width_m - 0.15 else ""
		])
	print("  estado: %s" % (_editor._status_label.text if _editor._status_label != null else "-"))
