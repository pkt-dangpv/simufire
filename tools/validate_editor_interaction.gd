extends SceneTree
## Guardarrail del COMPORTAMIENTO del editor al colocar cosas. Son tres
## peticiones del usuario del 2026-09-10, y las tres se pueden comprobar sin
## mirar:
##
##  1. **Colocada una cosa, se vuelve a Seleccion.** Antes la herramienta se
##     quedaba puesta y el siguiente clic ponia otra sin querer. Solo cuando se
##     ha creado algo: si el clic no valia, la herramienta sigue puesta.
##  2. **El balcon se dibuja como una sala**: a lo largo del muro el ancho, y
##     perpendicular el vuelo, recortado al maximo del voladizo. Un clic corto
##     sigue dando la balconera de medidas corrientes.
##  3. **La ficha de la sala va con la sala al girarla.** Se colgaba de la
##     esquina del rectangulo SIN girar, asi que al girar se quedaba fuera de
##     la estancia.
##  4. **D-4: el 3D en vivo encuadra el edificio** por muchas salas que tenga.
##     Se encuadraba copiando la camara del visor 3D grande, que no se mueve:
##     medido, a partir de 16 salas se salian 7 de las 8 esquinas.
##
##   <godot> --headless --path . --script res://tools/validate_editor_interaction.gd


## Tool.ROOM del editor. El enum es suyo y no se exporta, asi que se copia el
## numero, como hacen los demas guardarrailes que manejan el editor.
const TOOL_ROOM: int = 1

var _editor: Node = null
var _frames: int = 0
var _fails: int = 0

func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)

func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1

## Una rejilla de salas sueltas, para probar con planos grandes.
func _rejilla_de_salas(filas: int, columnas: int) -> void:
	_editor.adopt_scenario_data({
		"floors": [{"name": "R", "level_m": 0.0}],
		"exterior_walls": [], "room_rect_m": {}, "rooms_data": [],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": -1,
	}, 0)
	_editor.current_tool = TOOL_ROOM
	for f in range(filas):
		for c in range(columnas):
			var x: float = c * 4.5
			var y: float = f * 4.0
			_editor._handle_press(Vector2(x, y))
			_editor._handle_release(Vector2(x + 4.0, y + 3.5))


## Cuantas de las ocho esquinas de la caja del edificio caen FUERA del visor.
func _esquinas_fuera_del_visor() -> int:
	var cam: Camera3D = _editor._preview_3d_camera
	var vp: SubViewport = _editor._preview_3d_viewport
	if cam == null or vp == null:
		_eq("hay camara y visor en el panel del 3D en vivo", false, true)
		return 0
	var bounds: Rect2 = _editor.call("_current_floor_bounds_m")
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return 0
	var size := Vector2(vp.size)
	var origin: Vector2 = -(bounds.position + bounds.size * 0.5)
	var fuera: int = 0
	for sx in [0.0, 1.0]:
		for sz in [0.0, 1.0]:
			for h in [0.0, 2.7]:
				var punto := Vector3(
					bounds.position.x + bounds.size.x * float(sx) + origin.x,
					float(h),
					bounds.position.y + bounds.size.y * float(sz) + origin.y
				)
				if cam.is_position_behind(punto):
					fuera += 1
					continue
				var px: Vector2 = cam.unproject_position(punto)
				if px.x < 0.0 or px.y < 0.0 or px.x > size.x or px.y > size.y:
					fuera += 1
	return fuera


## Si un punto cae dentro del poligono de cuatro esquinas.
func _dentro(puntos: PackedVector2Array, punto: Vector2) -> bool:
	if puntos.size() != 4:
		return false
	return Geometry2D.is_point_in_polygon(punto, puntos)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	_editor.current_tool = 1
	_editor._handle_press(Vector2(0.0, 0.0))
	_editor._handle_release(Vector2(6.0, 4.0))

	# 1. tras crear, vuelta a Seleccion
	var antes: int = _editor._scenario_element_count()
	_editor.current_tool = 6
	_editor._create_window_at(Vector2(3.0, 0.02))
	_editor._auto_return_to_select(antes)
	_eq("vuelve a Seleccion tras crear", _editor.current_tool, 0)

	# ...y NO vuelve si el clic no valia
	_editor.current_tool = 6
	antes = _editor._scenario_element_count()
	_editor._create_window_at(Vector2(500.0, 500.0))
	_editor._auto_return_to_select(antes)
	_eq("se queda puesta si no creo nada", _editor.current_tool, 6)

	# 2. balcon arrastrado: ancho a lo largo del muro, vuelo recortado
	_editor.current_tool = 13
	_editor._create_balcony_door_from_drag(Vector2(1.0, 0.0), Vector2(4.2, -9.0))
	var ops: Array = _editor.editor_data.get("openings_data", [])
	var op: Dictionary = ops[ops.size() - 1]
	_eq("balcon declarado", op.get("has_balcony", false), true)
	_eq("ancho del arrastre", "%.2f" % float(op.get("balcony_width_m", 0.0)), "3.20")
	_eq("vuelo recortado al maximo", "%.2f" % float(op.get("balcony_depth_m", 0.0)), "2.00")
	_eq("la puerta no crece con el balcon", "%.2f" % float(op.get("width_m", 0.0)), "1.40")

	# 3. un clic sin arrastrar da la balconera corriente
	var n_antes: int = ops.size()
	_editor._create_balcony_door_from_drag(Vector2(5.0, 0.0), Vector2(5.1, 0.0))
	ops = _editor.editor_data.get("openings_data", [])
	_eq("el clic corto tambien crea", ops.size(), n_antes + 1)
	_eq("y con el ancho por defecto", float(Dictionary(ops[ops.size()-1]).get("balcony_width_m", -1.0)), 0.0)

	# 4. la ficha de una sala girada se ancla DENTRO de la sala
	var rooms: Array = _editor.editor_data.get("rooms_data", [])
	var room: Dictionary = rooms[0]
	room["rotation_deg"] = 37.0
	rooms[0] = room
	_editor.editor_data["rooms_data"] = rooms
	var vista: Array = _editor._plan_rooms_view()
	var entrada: Dictionary = vista[0]
	if not entrada.has("label_center_px"):
		print("  FAIL una sala girada no lleva ancla propia para su ficha")
		_fails += 1
	else:
		var ancla_px: Vector2 = entrada["label_center_px"]
		var puntos: PackedVector2Array = entrada.get("points_px", PackedVector2Array())
		_eq("el ancla de la ficha cae dentro de la sala girada", _dentro(puntos, ancla_px), true)
		# Y la esquina del rectangulo sin girar YA no vale: es justo el fallo.
		var esquina_px: Vector2 = Rect2(entrada.get("rect_px", Rect2())).position
		_eq("la esquina sin girar se habria quedado fuera", _dentro(puntos, esquina_px), false)

	# 5. D-4: el 3D en vivo no se sale del fotograma por muchas salas que haya.
	#
	# Se encuadraba copiando la matriz de la camara del visor 3D grande, que no
	# se mueve: a partir de unas 16 salas el edificio se salia. Ahora el
	# encuadre se CALCULA. Se comprueba proyectando las ocho esquinas de la
	# caja del edificio y viendo que caen dentro del visor.
	for caso in [[2, 2], [4, 4], [5, 6]]:
		_rejilla_de_salas(int(caso[0]), int(caso[1]))
		_editor.call("_set_preview_3d_enabled", true)
		_editor.call("_frame_preview_3d")
		var salas: int = Array(_editor.editor_data.get("rooms_data", [])).size()
		var fuera: int = _esquinas_fuera_del_visor()
		_eq("con %d salas el 3D en vivo encuadra el edificio" % salas, fuera, 0)

	print("[validate_editor_interaction] %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
	return true
