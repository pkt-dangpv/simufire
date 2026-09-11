extends SceneTree
## Sonda: que dice la revision sobre escenarios de verdad.
##
## Se pasa por los escenarios que hay en el repo y por cuatro dibujados a mano
## -uno bien hecho y tres con el fallo tipico- para ver si los avisos son utiles
## o solo ruido. Un aviso que salta en un escenario correcto es peor que no
## avisar: enseña a ignorar la pantalla.
##
##   godot --headless --path . --script res://tools/probe_scenario_review.gd

const Review := preload("res://editor/ScenarioReview.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")

const TOOL_ROOM: int = 1
const TOOL_CORRIDOR: int = 2
const TOOL_STAIRS: int = 3
const TOOL_WINDOW: int = 6
const TOOL_OBJECT: int = 7
const TOOL_IGNITION: int = 8
const TOOL_PLAYER_START: int = 9

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

	print("=== escenarios guardados en el repo")
	for path in _repo_scenarios():
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_report(path.get_file(), Serializer.normalize_editor_data(parsed))

	print("")
	print("=== dibujado a mano, BIEN hecho")
	_report("completo", _drawn_scenario(true, true, true, true))

	print("")
	print("=== sin foco de ignición")
	_report("sin ignición", _drawn_scenario(true, true, false, true))

	print("")
	print("=== sin ninguna abertura al exterior")
	_report("hermético", _drawn_scenario(false, true, true, true))

	print("")
	print("=== sin inicio en primera persona")
	_report("sin inicio FP", _drawn_scenario(true, true, true, false))

	print("")
	print("=== una sala suelta, sin puertas, y dos salas que se pisan")
	_report("chapuza", _broken_scenario())

	quit(0)
	return true


func _report(label: String, data: Dictionary) -> void:
	var errors: Array = Serializer.validate_scenario(data)
	var warnings: Array[Dictionary] = Review.review(data)
	print("  %-22s %d sala(s), %d apertura(s) -> %d error(es), %d aviso(s)" % [
		label,
		Array(data.get("rooms_data", [])).size(),
		Array(data.get("openings_data", [])).size(),
		errors.size(), warnings.size()])
	for error in errors:
		print("      ERROR  %s" % str(error))
	for warning in warnings:
		print("      aviso  %s" % String(warning.get("text", "")))


func _repo_scenarios() -> PackedStringArray:
	var found := PackedStringArray()
	for folder in ["res://scenarios", "res://templates", "res://data"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".json"):
				found.append("%s/%s" % [folder, file_name])
	return found


## Un piso dibujado con las herramientas, con interruptores para quitarle cada
## cosa y ver si el aviso correspondiente salta.
func _drawn_scenario(with_window: bool, with_stairs: bool, with_ignition: bool, with_start: bool) -> Dictionary:
	_editor.adopt_scenario_data({
		"floors": [{"name": "PB", "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1
	}, 0)
	_draw(TOOL_ROOM, Vector2(0.0, 0.0), Vector2(4.0, 3.0))
	_draw(TOOL_ROOM, Vector2(0.0, 4.2), Vector2(4.0, 7.2))
	_draw(TOOL_CORRIDOR, Vector2(0.2, 3.0), Vector2(3.8, 3.0))
	if with_stairs:
		_draw(TOOL_STAIRS, Vector2(4.2, 0.0), Vector2(6.6, 3.4))
	if with_window:
		_click(TOOL_WINDOW, Vector2(2.0, 0.0))
	_click(TOOL_OBJECT, Vector2(1.5, 1.5))
	if with_ignition:
		_click(TOOL_IGNITION, Vector2(1.5, 1.5))
	if with_start:
		_click(TOOL_PLAYER_START, Vector2(3.0, 1.0))
	return _editor.editor_data.duplicate(true)


## Lo que sale cuando se dibuja deprisa: una sala aparte que no toca nada y otra
## encima de la primera.
func _broken_scenario() -> Dictionary:
	var data: Dictionary = _drawn_scenario(true, true, true, true)
	var rooms: Array = data["rooms_data"]
	var next_id: int = 0
	for room in rooms:
		next_id = maxi(next_id, int(room.get("id", -1)) + 1)
	rooms.append({
		"id": next_id, "name": "Trastero", "kind": "generic", "rotation_deg": 0.0,
		"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
	})
	data["room_rect_m"][str(next_id)] = {"x": 12.0, "y": 12.0, "w": 2.0, "h": 2.0}
	rooms.append({
		"id": next_id + 1, "name": "Solapada", "kind": "generic", "rotation_deg": 0.0,
		"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
	})
	data["room_rect_m"][str(next_id + 1)] = {"x": 1.0, "y": 1.0, "w": 3.0, "h": 2.0}
	data["openings_data"].append({
		"a": next_id + 1, "b": 0, "type": "door", "wall": "top", "offset_m": 0.5,
		"width_m": 0.9, "height_m": 2.03, "sill_m": 0.0, "open_fraction": 1.0
	})
	data["rooms_data"] = rooms
	return data


func _draw(tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(from_m)
	_editor._handle_release(to_m)


func _click(tool_id: int, pos_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(pos_m)
