extends SceneTree
## Sonda: que sube y que no al copiar una planta.
##
## Se dibuja una planta baja completa -salon, dormitorio, pasillo, escalera,
## puertas, una ventana, mobiliario, un detector, una victima y el inicio FP- y
## se crea la planta de encima de las dos maneras: vacia y copiada.
##
##   godot --headless --path . --script res://tools/probe_floor_copy.gd

const TOOL_ROOM: int = 1
const TOOL_CORRIDOR: int = 2
const TOOL_STAIRS: int = 3
const TOOL_WINDOW: int = 6
const TOOL_OBJECT: int = 7
const TOOL_PLAYER_START: int = 9
const TOOL_DETECTOR: int = 11
const TOOL_VICTIM: int = 12

var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false

	print("=== planta baja dibujada")
	_build_ground_floor()
	_dump(0.0)

	print("")
	print("=== A. planta nueva VACÍA")
	_editor._create_floor(false)
	_dump(_editor._current_floor_level_m())
	print("  estado: %s" % _status())

	print("")
	print("=== B. planta nueva COPIADA")
	_build_ground_floor()
	_editor.current_floor_index = 0
	_editor._create_floor(true)
	_dump(_editor._current_floor_level_m())
	print("  estado: %s" % _status())

	print("")
	print("=== ids repetidos (lo que rompe un escenario)")
	_report_duplicate_ids()

	quit(0)
	return true


func _build_ground_floor() -> void:
	_editor.adopt_scenario_data({
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1
	}, 0)
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.0))
	_draw(TOOL_ROOM, Vector2(0.0, 4.2), Vector2(4.0, 7.2))
	_draw(TOOL_CORRIDOR, Vector2(0.2, 3.0), Vector2(3.8, 3.0))
	_draw(TOOL_STAIRS, Vector2(4.2, 0.0), Vector2(6.6, 3.4))
	_click(TOOL_WINDOW, Vector2(2.0, 0.0))
	_click(TOOL_OBJECT, Vector2(1.5, 1.5))
	_click(TOOL_OBJECT, Vector2(2.5, 5.5))
	_click(TOOL_DETECTOR, Vector2(2.0, 3.6))
	_click(TOOL_VICTIM, Vector2(1.0, 5.0))
	_click(TOOL_PLAYER_START, Vector2(3.0, 1.0))


func _draw(tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(from_m)
	_editor._handle_release(to_m)


func _click(tool_id: int, pos_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(pos_m)


func _status() -> String:
	return _editor._status_label.text if _editor._status_label != null else "-"


func _dump(level_m: float) -> void:
	var rooms: int = 0
	var objects: int = 0
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if absf(float(room.get("floor_level_z_m", 0.0)) - level_m) >= 0.05:
			continue
		rooms += 1
		var object_names: PackedStringArray = PackedStringArray()
		for obj in Array(room.get("fuel_objects", [])):
			object_names.append("%s/%s" % [String(obj.get("id", "")), String(obj.get("name", ""))])
			objects += 1
		print("  sala %2d %-18s %-9s %s" % [
			int(room.get("id", -1)), String(room.get("name", "")),
			String(room.get("kind", "")), ", ".join(object_names)])
	var openings: int = 0
	var verticals: int = 0
	for op in _editor.editor_data.get("openings_data", []):
		var a_id: int = int(op.get("a", -1))
		if absf(_editor._room_id_floor_level(a_id) - level_m) >= 0.05:
			continue
		if bool(op.get("is_vertical", false)):
			verticals += 1
		else:
			openings += 1
	var detectors: int = 0
	for det in _editor.editor_data.get("detectors", []):
		if absf(_editor._room_id_floor_level(int(det.get("room_id", -1))) - level_m) < 0.05:
			detectors += 1
	var victims: int = 0
	for vic in _editor.editor_data.get("victims", []):
		if absf(_editor._room_id_floor_level(int(vic.get("room_id", -1))) - level_m) < 0.05:
			victims += 1
	var start_here: bool = false
	var start: Dictionary = _editor.editor_data.get("player_start", {})
	if start.has("room_id"):
		start_here = absf(_editor._room_id_floor_level(int(start.get("room_id", -1))) - level_m) < 0.05
	print("  -> %d salas, %d objetos, %d aperturas (+%d verticales), %d detectores, %d víctimas, inicio FP: %s" % [
		rooms, objects, openings, verticals, detectors, victims, "sí" if start_here else "no"])


func _report_duplicate_ids() -> void:
	var room_ids: Dictionary = {}
	var object_ids: Dictionary = {}
	var repeated: PackedStringArray = PackedStringArray()
	for room in _editor.editor_data.get("rooms_data", []):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var rid: int = int(room.get("id", -1))
		if room_ids.has(rid):
			repeated.append("sala %d" % rid)
		room_ids[rid] = true
		for obj in Array(room.get("fuel_objects", [])):
			var oid: String = String(obj.get("id", ""))
			if object_ids.has(oid):
				repeated.append("objeto %s" % oid)
			object_ids[oid] = true
	var detector_ids: Dictionary = {}
	for det in _editor.editor_data.get("detectors", []):
		var did: String = String(det.get("id", ""))
		if detector_ids.has(did):
			repeated.append("detector %s" % did)
		detector_ids[did] = true
	if repeated.is_empty():
		print("  ninguno")
	else:
		print("  REPETIDOS: %s" % ", ".join(repeated))
	var errors: Array = load("res://editor/ScenarioSerializer.gd").validate_scenario(_editor.editor_data)
	print("  validate_scenario: %s" % ("sin errores" if errors.is_empty() else str(errors)))
