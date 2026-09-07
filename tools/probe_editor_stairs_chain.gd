extends SceneTree
## Sonda: encadenar escaleras para subir de planta en planta.
##
## Dibuja como se dibuja: en planta baja una sala y una escalera; sube a la
## primera, dibuja una sala pegada al hueco y otra escalera; y mira que queda.
##
## Ademas exporta el escenario a JSON, para poder correr el incendio despues y
## ver si el humo sube por el hueco de la escalera. Ese es el otro asunto: que el
## hueco entre plantas sea un hueco de verdad y no un techo pintado.
##
##   godot --headless --path . --script res://tools/probe_editor_stairs_chain.gd -- <salida.json>

const Serializer := preload("res://editor/ScenarioSerializer.gd")

const TOOL_ROOM: int = 2
const TOOL_STAIRS: int = 4
const TOOL_OBJECT: int = 8
const TOOL_IGNITION: int = 9

var _editor: Node = null
var _frames: int = 0
var _out_path: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	_editor.editor_data = _blank_scenario()
	_editor.current_floor_index = 0

	print("--- planta baja: salón y escalera")
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.4))
	_draw(TOOL_STAIRS, Vector2(4.0, 0.0), Vector2(6.4, 3.4))
	print("    ", _status())

	print("--- primera planta: una sala pegada al hueco, y otra escalera")
	_editor.current_floor_index = 1
	_editor._sync_floor_controls()
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.4))
	print("    ", _status())
	_draw(TOOL_STAIRS, Vector2(6.4, 0.0), Vector2(8.8, 3.4))
	print("    ", _status())

	print("--- un objeto encendido abajo, para poder simular")
	_editor.current_floor_index = 0
	_editor.current_tool = TOOL_OBJECT
	_editor._handle_press(Vector2(1.5, 1.5))
	_editor.current_tool = TOOL_IGNITION
	_editor._handle_press(Vector2(1.5, 1.5))

	print("--- lo que ha quedado")
	for floor_data in _editor.editor_data.get("floors", []):
		print("    planta %-4s cota %.2f" % [String(floor_data.get("name", "")), float(floor_data.get("level_m", 0.0))])
	for room in _editor.editor_data.get("rooms_data", []):
		print("    sala %2d  %-16s cota %.2f  tipo %s" % [
			int(room.get("id", -1)), String(room.get("name", "")),
			float(room.get("floor_level_z_m", 0.0)), String(room.get("kind", ""))
		])
	var verticals: int = 0
	for opening in _editor.editor_data.get("openings_data", []):
		var op: Dictionary = opening
		var vertical: bool = bool(op.get("is_vertical", false))
		if vertical:
			verticals += 1
		print("    apertura %-6s a=%2d b=%2d %s" % [
			String(op.get("type", "")), int(op.get("a", -1)), int(op.get("b", -1)),
			"VERTICAL (hueco entre plantas)" if vertical else "en pared"
		])
	print("    huecos verticales: %d (uno por escalera)" % verticals)

	if _out_path != "":
		# Por el guardado del propio editor: to_runtime_template() devuelve Rect2 de
		# verdad, y pasarlos por JSON.stringify los convierte en texto
		# ("[P: (0,0), S: (4,3.4)]") que al releer ya no es un rectangulo. La
		# primera version de esta sonda hizo justo eso y el incendio corrio sobre
		# un edificio sin salas.
		if Serializer.save_runtime_template(_out_path, _editor.editor_data):
			print("[probe_stairs_chain] escenario -> %s" % _out_path)
	quit(0)
	return true


func _draw(tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(from_m)
	_editor._handle_release(to_m)


func _status() -> String:
	return _editor._status_label.text if _editor._status_label != null else "-"


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
