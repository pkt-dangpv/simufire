extends SceneTree
## Guardarrail D-6: las sondas montan el escenario por el CAMINO REAL.
##
## El hallazgo: `capture_editor_plan.gd` asignaba `editor_data` a mano y se
## saltaba `_sync_floor_controls()`, asi que todas sus fotos salian con
## «Salas: 0» habiendo tres salas dibujadas, y con el mensaje de estado de otra
## accion mientras se arrastraba una sala. Estuve a punto de dar el contador por
## roto y no lo estaba: **una sonda que miente en un detalle obliga a verificar
## todo lo que enseña**, que es lo contrario de para lo que esta.
##
## No era una sonda: eran 21 herramientas inyectando el diccionario a mano, cada
## una reproduciendo el trozo del camino que recordo quien la escribio. Y dentro
## del propio editor la secuencia estaba tres veces, divergida.
##
## Ahora hay un solo sitio -`ScenarioEditor.adopt_scenario_data()`- y esta regla
## es lo que impide que vuelvan a salir copias: si una herramienta asigna
## `editor_data` directamente, esto falla y dice cual.
##
## Lo que se prohibe es **sustituir el diccionario entero**, que es adoptar un
## escenario. Quedan fuera a proposito dos cosas que no son eso:
##
##   - **Leerlo** (`editor.editor_data.get(...)`), que es como comprueba su
##     resultado la mitad de los guardarrailes.
##   - **Tocar una clave** (`editor.editor_data["rooms_data"] = ...`), que es
##     modificar un escenario ya adoptado, no montar uno.
##
##   <godot> --headless --path . --script res://tools/validate_probe_paths.gd

const TOOLS_DIR: String = "res://tools"
## Sustituir el diccionario entero: `x.editor_data = ...`, no `x.editor_data[k] = ...`.
const WRITE_PATTERN: String = "\\.editor_data\\s*=[^=]"

var _failures: PackedStringArray = PackedStringArray()
var _checked: int = 0
var _editor: Node = null
var _frames: int = 0


func _initialize() -> void:
	_check_editor_has_the_single_path()
	_check_no_tool_writes_editor_data()
	# La parte de comportamiento necesita el editor montado, y eso pide
	# fotogramas: sigue en _process().
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	_check_the_counter_tells_the_truth()
	_check_adopt_is_not_restore()
	_report()
	quit(1 if _failures.size() > 0 else 0)
	return true


## El sintoma que abrio D-6, medido: tres salas dibujadas y el editor diciendo
## «Salas: 0». Es lo que separa «la funcion existe» de «la funcion sirve».
func _check_the_counter_tells_the_truth() -> void:
	_checked += 1
	_editor.adopt_scenario_data(_three_room_scenario(), 0)
	var label: Object = _editor._floor_status_label
	if label == null:
		_fail("el editor no tiene rotulo de estado de planta: no se puede comprobar el contador")
		return
	var text: String = String(label.get("text"))
	if not text.contains("Salas: 3"):
		_fail("el contador de la planta dice «%s» con 3 salas dibujadas" % text)
	# Y la planta que se pide es la que se edita, no la que hubiera antes.
	_editor.adopt_scenario_data(_three_room_scenario(), 1)
	if int(_editor.current_floor_index) != 1:
		_fail("se pidio la planta 1 y el editor quedo en la %d" % int(_editor.current_floor_index))
	# En la planta de arriba no hay ninguna sala: el contador tambien tiene que
	# decirlo, o estaria contando el escenario entero en vez de la planta.
	var upper: String = String(_editor._floor_status_label.get("text"))
	if not upper.contains("Salas: 0"):
		_fail("en la planta alta, vacia, el contador dice «%s»" % upper)


## Adoptar no es restaurar.
##
## Traer datos de FUERA bloquea la pose visual del mobiliario: dice «esto lo
## coloco quien escribio el fichero, no lo recoloques». Restaurar una instantanea
## del historial NO trae nada de fuera -es un estado propio de esta sesion- y
## deshacer tiene que devolverlo **tal cual**: si le añade banderas, deshacer deja
## de ser deshacer.
## Se prueba **por el camino real**: deshacer de verdad, no llamando a mano a
## `adopt_scenario_data(..., false)`. La primera version de esta regla hacia lo
## segundo y no cazaba la mutacion, porque no pasaba por `_apply_history_snapshot`
## -que es justo donde vive la decision-. Una regla que no pasa por el camino
## real es D-6 otra vez, esta vez en el guardarrail.
func _check_adopt_is_not_restore() -> void:
	_checked += 1
	# Adoptar datos de fuera: bloquea.
	_editor.adopt_scenario_data(_scenario_with_loose_furniture(), 0)
	if not _first_object_is_locked():
		_fail("adoptar un escenario de fuera NO bloqueo la pose visual del mueble")

	# Un estado interno con el mueble suelto, una accion encima, y deshacer.
	_editor.adopt_scenario_data(_scenario_with_loose_furniture(), 0, false)
	if _first_object_is_locked():
		_fail("adopt_scenario_data(..., false) bloqueo igualmente: el parametro no hace nada")
		return
	_editor._push_undo_snapshot("prueba")
	_editor._update_room_fields(1, {"name": "Otro nombre"})
	_editor._undo_last_action()
	if _first_object_is_locked():
		_fail("deshacer bloqueo una pose que no venia bloqueada: deshacer ya no devuelve el estado que habia")
	if String(Dictionary(Array(_editor.editor_data.get("rooms_data", []))[0]).get("name", "")) != "Salon":
		_fail("deshacer no devolvio el nombre de la sala: la instantanea no se aplico")


func _first_object_is_locked() -> bool:
	var rooms: Array = _editor.editor_data.get("rooms_data", [])
	if rooms.is_empty() or typeof(rooms[0]) != TYPE_DICTIONARY:
		return false
	var objects: Array = Dictionary(rooms[0]).get("fuel_objects", [])
	if objects.is_empty() or typeof(objects[0]) != TYPE_DICTIONARY:
		return false
	return bool(Dictionary(objects[0]).get("visual_pose_locked", false))


## Un piso con un mueble que NO trae la bandera, que es como llega un escenario
## escrito a mano.
func _scenario_with_loose_furniture() -> Dictionary:
	var data: Dictionary = _three_room_scenario()
	var rooms: Array = data["rooms_data"]
	var room: Dictionary = rooms[0]
	room["fuel_objects"] = [{
		"id": "obj_001", "room_id": 1, "name": "sofa", "kind": "sofa",
		"position_m": {"x": 0.5, "y": 0.5}, "size_m": {"x": 2.0, "y": 0.9},
		"rotation_deg": 0.0, "elevation_m": 0.0,
		"fuel_energy_MJ": 260.0, "max_hrr_kw": 900.0,
	}]
	rooms[0] = room
	data["rooms_data"] = rooms
	return data


func _three_room_scenario() -> Dictionary:
	return {
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": 2.7}],
		"exterior_walls": [],
		"room_rect_m": {
			"1": {"x": 0.0, "y": 0.0, "w": 4.0, "h": 3.0},
			"2": {"x": 4.0, "y": 0.0, "w": 3.0, "h": 3.0},
			"3": {"x": 0.0, "y": 3.0, "w": 7.0, "h": 1.4},
		},
		"rooms_data": [
			{"id": 1, "name": "Salon", "kind": "generic", "height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 2, "name": "Cocina", "kind": "generic", "height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 3, "name": "Pasillo", "kind": "pasillo", "height_m": 2.7, "floor_level_z_m": 0.0, "fuel_objects": []},
		],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": 1,
	}


## Que exista el sitio unico, y que los tres caminos del editor pasen por el.
func _check_editor_has_the_single_path() -> void:
	var source: String = _read("res://editor/ScenarioEditor.gd")
	if source == "":
		_fail("no se pudo leer editor/ScenarioEditor.gd")
		return
	_checked += 1
	if not source.contains("func adopt_scenario_data("):
		_fail("editor/ScenarioEditor.gd ya no declara adopt_scenario_data()")
	var calls: int = source.count("adopt_scenario_data(") - 1  # menos la declaracion
	if calls < 3:
		_fail("solo %d llamadas a adopt_scenario_data() en el editor: se esperan al menos 3 (cargar por ruta, cargar de la lista, aplicar instantanea)" % calls)
	# Vaciar el historial NO puede estar dentro de la funcion comun: deshacer y
	# rehacer la llaman, y se borrarian a si mismos.
	var body: String = _function_body(source, "func adopt_scenario_data(")
	# El historial vive en `ScenarioDocument` desde D-1: vale el nombre viejo y el nuevo.
	if body.contains("_undo_stack.clear()") or body.contains("clear_history()"):
		_fail("adopt_scenario_data() vacia el historial: deshacer y rehacer la llaman y se borrarian a si mismos")


func _check_no_tool_writes_editor_data() -> void:
	var regex := RegEx.new()
	regex.compile(WRITE_PATTERN)
	var dir := DirAccess.open(TOOLS_DIR)
	if dir == null:
		_fail("no se pudo abrir %s" % TOOLS_DIR)
		return
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for name in names:
		if not name.ends_with(".gd"):
			continue
		var path: String = "%s/%s" % [TOOLS_DIR, name]
		var source: String = _read(path)
		if source == "":
			continue
		_checked += 1
		var line_no: int = 0
		for line in source.split("\n"):
			line_no += 1
			var clean: String = String(line).strip_edges()
			if clean.begins_with("#"):
				continue
			if regex.search(clean) == null:
				continue
			_fail("%s:%d asigna editor_data a mano; usa editor.adopt_scenario_data(datos, planta)" % [name, line_no])


func _function_body(source: String, header: String) -> String:
	var start: int = source.find(header)
	if start < 0:
		return ""
	var next: int = source.find("\nfunc ", start + header.length())
	return source.substr(start, (next - start) if next > start else -1)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("  ok   %d ficheros: el escenario se monta por adopt_scenario_data()" % _checked)
		print("[validate_probe_paths] PASS")
		return
	for message in _failures:
		print("  FALLO %s" % message)
	print("[validate_probe_paths] FAIL (%d)" % _failures.size())
