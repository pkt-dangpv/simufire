extends SceneTree
## Sonda: dibujar VARIAS cosas seguidas en la vista 3D.
##
## El usuario lo dijo asi: "he podido poner una habitacion pero no mas, no me
## deja. los muros exteriores no se puede".
##
## La diferencia con la guardia que ya habia es COMO llega el clic: alli se
## llamaba a _unhandled_input() del editor a mano, y asi nunca pasa por el visor
## 3D. Aqui se empuja por el viewport, que es el camino de verdad: el visor mira
## el evento antes que el editor porque cuelga de el.
##
##   godot --headless --path . --script res://tools/probe_draw_3d_chain.gd

const TOOL_ROOM: int = 1
const MODE_3D: int = 1

var _editor: Node = null
var _frames: int = 0
var _step: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	match _step:
		0:
			_editor.editor_data = {
				"floors": [{"name": "PB", "level_m": 0.0}],
				"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
				"openings_data": [], "detectors": [], "victims": [],
				"player_start": {}, "ignition_room_id": -1
			}
			_editor.current_floor_index = 0
			_editor._set_editor_view_mode(MODE_3D)
			print("modo 3D, plano vacío")
		1:
			print("")
			print("=== 1ª sala")
			_drag(TOOL_ROOM, Vector2(0.42, 0.52), Vector2(0.58, 0.70))
			_report()
		2:
			print("")
			print("=== 2ª sala, al lado de la primera")
			_drag(TOOL_ROOM, Vector2(0.60, 0.52), Vector2(0.76, 0.70))
			_report()
		3:
			print("")
			print("=== 3ª sala, encima de donde ya hay algo")
			_drag(TOOL_ROOM, Vector2(0.46, 0.56), Vector2(0.56, 0.66))
			_report()
		_:
			quit(0)
			return true
	_step += 1
	_frames = 0
	return false


## Un arrastre de verdad: por el viewport, como el raton.
func _drag(tool_id: int, from_f: Vector2, to_f: Vector2) -> void:
	# Por _set_tool, que es lo que hace el boton de la barra: cambiar la variable
	# a pelo se salta lo que el editor le dice al visor.
	_editor._set_tool(tool_id)
	var size: Vector2 = _editor.get_viewport().get_visible_rect().size
	_push_button(size * from_f, true)
	_push_motion(size * to_f)
	_push_button(size * to_f, false)


func _push_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	_editor.get_viewport().push_input(event, true)


func _push_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	_editor.get_viewport().push_input(event, true)


func _report() -> void:
	var rooms: Array = _editor.editor_data.get("rooms_data", [])
	print("  salas: %d" % rooms.size())
	for room in rooms:
		var rect: Rect2 = _editor._get_room_rect(int(room.get("id", -1)))
		print("    sala %2d %-12s %5.2f,%5.2f  %4.2f x %4.2f" % [
			int(room.get("id", -1)), String(room.get("name", "")),
			rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	print("  estado: %s" % (_editor._status_label.text if _editor._status_label != null else "-"))
