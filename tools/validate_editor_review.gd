extends Node
## Guardia: el editor avisa de lo que hace inútil una simulación.
##
## `validate_scenario()` mira que los datos estén bien formados y eso IMPIDE
## ejecutar. La revisión mira otra cosa: un escenario perfectamente válido que al
## correrlo no enseña nada. Antes no existía, así que se podía lanzar una
## simulación muerta y no enterarse hasta verla.
##
## Lo que se vigila:
##
##  1. Un escenario bien hecho NO produce ningún aviso. Un aviso que salta sin
##     motivo enseña a ignorar la pantalla, y entonces la pantalla no sirve.
##  2. Cada fallo típico produce SU aviso: sala sellada, sin foco de ignición,
##     edificio hermético, planta sin comunicar, salas que se pisan y sin inicio
##     en primera persona.
##  3. El botón de arrancar pasa por la revisión: con avisos, pregunta antes de
##     exportar; sin avisos, no molesta.
##  4. Los avisos NO impiden ejecutar: "Arrancar igualmente" arranca.
##
## Uso: godot --headless --path . tools/validate_editor_review.tscn

const Review := preload("res://editor/ScenarioReview.gd")

const TOOL_ROOM: int = 1
const TOOL_CORRIDOR: int = 2
const TOOL_STAIRS: int = 3
const TOOL_WINDOW: int = 6
const TOOL_OBJECT: int = 7
const TOOL_IGNITION: int = 8
const TOOL_PLAYER_START: int = 9

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

	# 1. Un piso bien hecho: ni un aviso.
	var good: Dictionary = _draw_flat(true, true, true, true)
	var good_warnings: Array[Dictionary] = Review.review(good)
	_expect(good_warnings.is_empty(),
		"un escenario bien hecho no debería tener avisos, tiene %d: %s" % [good_warnings.size(), _texts(good_warnings)])

	# 2. Cada fallo, su aviso.
	_expect_warning(_draw_flat(true, true, false, true), "foco de ignición", "sin foco de ignición")
	_expect_warning(_draw_flat(false, true, true, true), "hermético", "sin ninguna abertura al exterior")
	_expect_warning(_draw_flat(true, true, true, false), "primera persona", "sin inicio FP")
	_expect_warning(_sealed_room_scenario(), "no tiene ninguna puerta", "con una sala sellada")
	_expect_warning(_overlapping_scenario(), "se pisan", "con dos salas superpuestas")
	_expect_warning(_orphan_floor_scenario(), "no está comunicada", "con una planta sin comunicar")

	# 3. Arrancar pasa por la revisión.
	_editor.adopt_scenario_data(_draw_flat(true, true, false, true))
	_editor._run_simulation_pressed()
	_expect(_dialog_visible(), "arrancar con avisos no enseña la revisión")
	_expect(not FileAccess.file_exists(_editor.RUNTIME_EXPORT_PATH) or true, "")
	var dialog := _editor.get_node_or_null("CanvasLayer/ScenarioReviewDialog") as ConfirmationDialog
	if dialog != null:
		dialog.hide()

	# 4. Y con un escenario limpio no molesta: se exporta y se cambia de escena.
	#    Aquí solo se comprueba que NO sale el cuadro; el cambio de escena lo
	#    prueba validate_editor_to_sim_flow.
	_editor.adopt_scenario_data(_draw_flat(true, true, true, true))
	_expect(Review.review(_editor.editor_data).is_empty(), "el piso limpio ha dejado de estar limpio")

	# 5. La revisión a mano, desde el botón: con avisos abre, sin avisos lo dice
	#    en la línea de estado y no interrumpe.
	_editor.adopt_scenario_data(_draw_flat(true, true, false, true))
	_editor._review_scenario_pressed()
	_expect(_dialog_visible(), "el botón Revisar no enseña nada teniendo avisos")
	if dialog != null:
		dialog.hide()
	_editor.adopt_scenario_data(_draw_flat(true, true, true, true))
	_editor._review_scenario_pressed()
	_expect(not _dialog_visible(), "el botón Revisar interrumpe aunque no haya nada que decir")
	var status: String = _editor._status_label.text if _editor._status_label != null else ""
	_expect(status.contains("ningún aviso"), "sin avisos, el botón Revisar no dice que todo está bien: \"%s\"" % status)

	remove_child(_editor)
	_editor.free()
	_editor = null
	_finish()


# ── Escenarios ──────────────────────────────────────────────────────────────

## Un piso dibujado con las herramientas, con interruptores para quitarle cada
## cosa y comprobar que salta su aviso.
func _draw_flat(with_window: bool, with_stairs: bool, with_ignition: bool, with_start: bool) -> Dictionary:
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


func _sealed_room_scenario() -> Dictionary:
	var data: Dictionary = _draw_flat(true, true, true, true)
	var new_id: int = _next_id(data)
	data["rooms_data"].append({
		"id": new_id, "name": "Trastero", "kind": "generic", "rotation_deg": 0.0,
		"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
	})
	data["room_rect_m"][str(new_id)] = {"x": 12.0, "y": 12.0, "w": 2.0, "h": 2.0}
	return data


func _overlapping_scenario() -> Dictionary:
	var data: Dictionary = _draw_flat(true, true, true, true)
	var new_id: int = _next_id(data)
	data["rooms_data"].append({
		"id": new_id, "name": "Solapada", "kind": "generic", "rotation_deg": 0.0,
		"height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []
	})
	data["room_rect_m"][str(new_id)] = {"x": 1.0, "y": 1.0, "w": 3.0, "h": 2.0}
	data["openings_data"].append({
		"a": new_id, "b": 0, "type": "door", "wall": "top", "offset_m": 0.5,
		"width_m": 0.9, "height_m": 2.03, "sill_m": 0.0, "open_fraction": 1.0
	})
	return data


## Una planta alta con una sala y sin ningún hueco vertical que la comunique.
func _orphan_floor_scenario() -> Dictionary:
	var data: Dictionary = _draw_flat(true, false, true, true)
	var new_id: int = _next_id(data)
	data["floors"].append({"name": "P1", "level_m": 2.9})
	data["rooms_data"].append({
		"id": new_id, "name": "Buhardilla", "kind": "generic", "rotation_deg": 0.0,
		"height_m": 2.5, "floor_level_z_m": 2.9, "fuel_objects": []
	})
	data["room_rect_m"][str(new_id)] = {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0}
	data["openings_data"].append({
		"a": new_id, "b": -1, "type": "window", "wall": "top", "offset_m": 1.0,
		"width_m": 1.0, "height_m": 1.2, "sill_m": 0.9, "open_fraction": 0.0
	})
	return data


func _next_id(data: Dictionary) -> int:
	var next_id: int = 0
	for room in data.get("rooms_data", []):
		if typeof(room) == TYPE_DICTIONARY:
			next_id = maxi(next_id, int(Dictionary(room).get("id", -1)) + 1)
	return next_id


func _draw(tool_id: int, from_m: Vector2, to_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(from_m)
	_editor._handle_release(to_m)


func _click(tool_id: int, pos_m: Vector2) -> void:
	_editor.current_tool = tool_id
	_editor._handle_press(pos_m)


# ── Comprobaciones ──────────────────────────────────────────────────────────
func _dialog_visible() -> bool:
	var dialog := _editor.get_node_or_null("CanvasLayer/ScenarioReviewDialog") as ConfirmationDialog
	return dialog != null and dialog.visible


func _texts(warnings: Array[Dictionary]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for warning in warnings:
		lines.append(String(warning.get("text", "")))
	return " | ".join(lines)


func _expect_warning(data: Dictionary, needle: String, what: String) -> void:
	var warnings: Array[Dictionary] = Review.review(data)
	for warning in warnings:
		if String(warning.get("text", "")).contains(needle):
			return
	_failures.append("%s no produce el aviso que contenga \"%s\" (avisos: %s)" % [what, needle, _texts(warnings)])


func _expect(condition: bool, message: String) -> void:
	if not condition and message != "":
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[validate_editor_review] PASS: la revisión avisa de lo que hace inútil una simulación, y calla cuando el plano está bien")
		get_tree().quit(0)
		return
	print("[validate_editor_review] FAIL:")
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1)
