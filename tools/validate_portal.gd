extends SceneTree
## Guardarrail de la herramienta de PORTAL.
##
## El rellano de un bloque de pisos solo existia en la vista: en el modelo la
## puerta de la vivienda daba al ambiente y el humo que salia por ella se iba a
## la calle. Con el portal como recinto -una zona de escalera por planta,
## encadenadas, y la puerta de cada vivienda dando a la suya- el motor hace la
## fisica sin tocarlo (docs/PROMPT_MOTOR_PORTAL.md). Lo que se comprueba es lo que
## se pierde si alguien toca eso:
##
##  1. **Una zona por planta**, de escalera y llamada «Portal …».
##  2. **Encadenadas** por el ojo, y **cerrada por arriba**: ningun hueco al cielo.
##  3. **La puerta de la vivienda da al rellano**, y sin moverse de sitio.
##  4. **Una balconera no se reconecta** aunque caiga sobre el portal.
##  5. **El zaguan** tiene una puerta a la calle, cerrada, abajo, y no contra la
##     vivienda.
##  6. **No abre huecos solo**, ni al dibujarlo ni al dibujar despues una sala
##     pegada: al portal se pasa por una puerta.
##  7. **Un portal diminuto no se crea.**
##  8. **En la vista**, la puerta del piso ya es interior y la del zaguan es de
##     calle: echa penacho la que da a la calle, no la del piso.
##
##   <godot> --headless --path . --script res://tools/validate_portal.gd

const TOOL_ROOM: int = 1
const TOOL_PORTAL: int = 15
const OUTSIDE_ID: int = -1

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const ScenarioWalls := preload("res://editor/ScenarioWalls.gd")
const OpeningKinds := preload("res://view/geometry/OpeningKinds.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

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


## Tres plantas con la misma vivienda. La puerta de entrada esta en su pared
## derecha, que es donde se dibujara el portal. En la R+2 esa puerta es una
## balconera: tiene que quedarse dando a la calle.
##
##   ids 1, 2, 3   vivienda en R, R+1, R+2
##   aperturas 0-2 la de la pared derecha de cada planta
##   apertura 3    una ventana de la R a la calle, que no se toca
func _edificio() -> void:
	var rects: Dictionary = {}
	var rooms: Array = []
	var openings: Array = []
	for p in range(3):
		var id: int = p + 1
		rects[str(id)] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rooms.append({
			"id": id, "name": "Vivienda %d" % p, "kind": "salon", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": 2.9 * p, "fuel_objects": [],
		})
		var door: Dictionary = {
			"a": id, "b": OUTSIDE_ID, "type": "door", "wall": "right",
			"offset_m": 0.5, "offset_is_fraction": true,
			"width_m": 0.92, "height_m": 2.05, "sill_m": 0.0, "open_fraction": 1.0,
		}
		if p == 2:
			door["width_m"] = 1.40
			door["has_balcony"] = true
			door["balcony_depth_m"] = 1.20
			door["balcony_parapet_m"] = 1.10
		openings.append(door)
	openings.append({
		"a": 1, "b": OUTSIDE_ID, "type": "window", "wall": "left",
		"offset_m": 0.5, "offset_is_fraction": true,
		"width_m": 1.30, "height_m": 1.10, "sill_m": 0.90, "open_fraction": 1.0,
	})
	_editor.adopt_scenario_data({
		"building_type": "apartment", "apartment_floor_number": 0,
		"floors": [
			{"name": "R", "level_m": 0.0},
			{"name": "R+1", "level_m": 2.9},
			{"name": "R+2", "level_m": 5.8},
		],
		"exterior_walls": [], "room_rect_m": rects, "rooms_data": rooms,
		"openings_data": openings, "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": 1,
	}, 0)


func _portales() -> Array:
	var out: Array = []
	for raw in _editor.editor_data.get("rooms_data", []):
		if typeof(raw) == TYPE_DICTIONARY and String(Dictionary(raw).get("name", "")).begins_with("Portal"):
			out.append(raw)
	out.sort_custom(func(x, y): return float(x.get("floor_level_z_m", 0.0)) < float(y.get("floor_level_z_m", 0.0)))
	return out


func _dibujar_portal() -> void:
	# 3 x 3 pegado a la pared derecha de la vivienda, subiendo hacia abajo.
	_editor.current_tool = TOOL_PORTAL
	_editor._handle_press(Vector2(5.0, 0.5))
	_editor._handle_release(Vector2(8.0, 3.5))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	_edificio()
	var data0: Dictionary = _editor.editor_data
	# Sin portal dibujado la vista SI pone su rellano de decorado: sin esto, que
	# despues no aparezca no probaria nada.
	var sin_portal: BuildingModel = BuildingModelScript.new()
	sin_portal.load_template_data(Serializer.to_runtime_template(data0.duplicate(true)))
	_eq("sin portal, la vista pone su rellano de decorado", _nodos_de_rellano(sin_portal) > 0, true)
	sin_portal.free()
	var antes: Array = []
	for i in range(3):
		antes.append(ScenarioWalls.opening_segment_m(data0, Dictionary(data0["openings_data"][i]).duplicate()))
	_dibujar_portal()
	var data: Dictionary = _editor.editor_data
	var ops: Array = data.get("openings_data", [])

	# ── 1. Una zona por planta ──
	var zonas: Array = _portales()
	_eq("una zona de portal por planta", zonas.size(), 3)
	var cotas: Array = zonas.map(func(z): return "%.1f" % float(z.get("floor_level_z_m", -1.0)))
	_eq("y una en cada cota", ",".join(cotas), "0.0,2.9,5.8")
	var tipos: Array = zonas.map(func(z): return String(z.get("kind", "")))
	_eq("todas de escalera, que es con lo que se midio", ",".join(tipos), "escalera,escalera,escalera")
	var ids: Array = zonas.map(func(z): return int(z.get("id", -1)))

	# ── 2. Encadenado y cerrado por arriba ──
	var verticales: Array = []
	var al_cielo: int = 0
	for raw in ops:
		var op: Dictionary = raw
		if not bool(op.get("is_vertical", false)):
			continue
		if int(op.get("b", 0)) == OUTSIDE_ID or int(op.get("a", 0)) == OUTSIDE_ID:
			al_cielo += 1
		else:
			verticales.append("%d-%d" % [int(op["a"]), int(op["b"])])
	verticales.sort()
	_eq("el ojo encadena las plantas seguidas", ",".join(verticales), "%d-%d,%d-%d" % [ids[0], ids[1], ids[1], ids[2]])
	_eq("y la caja esta cerrada por arriba", al_cielo, 0)
	# El ojo es el paso libre, no la huella de la escalera: con la huella entera
	# (2,46 x 3,0 m) la planta alta se clava en el tope de 900 C del motor.
	_eq("el ojo es de 1,40 x 1,40, no la huella de los tramos", _ojos(ids), "1.40x1.40,1.40x1.40")
	# Y no crece al estirar el portal: redimensionar recalcula el hueco de una
	# escalera, y el del portal tiene que quedarse como esta.
	_editor._set_room_rect(ids[1], Rect2(Vector2(5.0, 0.5), Vector2(4.0, 5.0)))
	_eq("ni al estirar el portal", _ojos(ids), "1.40x1.40,1.40x1.40")
	_editor._set_room_rect(ids[1], Rect2(Vector2(5.0, 0.5), Vector2(3.0, 3.0)))

	# ── 3. La puerta del piso da al rellano, en el mismo sitio ──
	for p in range(2):
		var op: Dictionary = ops[p]
		_eq("R+%d: la puerta de la vivienda da a su rellano" % p, int(op.get("b", 0)), ids[p])
		var despues: PackedVector2Array = ScenarioWalls.opening_segment_m(data, op)
		var movida: float = despues[0].distance_to(antes[p][0]) + despues[1].distance_to(antes[p][1])
		_eq("R+%d: y no se ha movido de sitio" % p, movida < 0.01, true)

	# ── 4. La balconera no ──
	_eq("la balconera sigue dando a la calle", int(Dictionary(ops[2]).get("b", 0)), OUTSIDE_ID)
	_eq("y la ventana tambien", int(Dictionary(ops[3]).get("b", 0)), OUTSIDE_ID)

	# ── 5. El zaguan ──
	var zaguanes: Array = []
	for raw in ops:
		var op: Dictionary = raw
		if bool(op.get("is_vertical", false)) or String(op.get("type", "")) != "door":
			continue
		if ids.has(int(op.get("a", -1))) and int(op.get("b", 0)) == OUTSIDE_ID:
			zaguanes.append(op)
	_eq("una sola puerta del portal a la calle", zaguanes.size(), 1)
	if zaguanes.size() == 1:
		var z: Dictionary = zaguanes[0]
		_eq("en la planta baja", int(z.get("a", -1)), ids[0])
		_eq("cerrada", float(z.get("open_fraction", 1.0)), 0.0)
		_eq("de frente, no contra la vivienda", String(z.get("wall", "")), "right")

	# ── 6. No abre huecos solo ──
	_eq("no se abre ningun hueco de paso", _huecos_de_paso(), 0)
	_editor.current_tool = TOOL_ROOM
	_editor._handle_press(Vector2(5.0, 3.5))
	_editor._handle_release(Vector2(8.0, 6.0))
	_eq("ni al dibujar una sala pegada despues", _huecos_de_paso(), 0)

	# ── 8. En la vista: la del piso es interior y la del zaguan es de calle ──
	_comprobar_vista(ids)

	# ── 7. Un portal diminuto no se crea ──
	_edificio()
	_editor.current_tool = TOOL_PORTAL
	_editor._handle_press(Vector2(5.0, 0.5))
	_editor._handle_release(Vector2(6.5, 2.0))
	_eq("un portal de 1,5 m no se crea", _portales().size(), 0)

	if _fails == 0:
		print("[validate_portal] PASS")
	else:
		push_error("[validate_portal] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


## Medidas de los huecos verticales entre zonas del portal.
func _ojos(ids: Array) -> String:
	var out: Array[String] = []
	for raw in _editor.editor_data.get("openings_data", []):
		var op: Dictionary = raw
		if bool(op.get("is_vertical", false)) and ids.has(int(op.get("a", -1))) and ids.has(int(op.get("b", -1))):
			out.append("%.2fx%.2f" % [float(op.get("width_m", 0.0)), float(op.get("height_m", 0.0))])
	return ",".join(out)


func _huecos_de_paso() -> int:
	var n: int = 0
	for raw in _editor.editor_data.get("openings_data", []):
		var op: Dictionary = raw
		if String(op.get("type", "")) == "hole" and not bool(op.get("is_vertical", false)):
			n += 1
	return n


## Por el camino real: el editor no le da `editor_data` al modelo, le da el
## template de ejecucion.
func _comprobar_vista(ids: Array) -> void:
	var data: Dictionary = _editor.editor_data.duplicate(true)
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Serializer.to_runtime_template(data))
	var del_piso: String = ""
	var del_zaguan: String = ""
	for raw in building.get_openings():
		var op := raw as OpeningModel
		if op == null or op.is_vertical or op.type != OpeningModel.Type.DOOR:
			continue
		if op.a == 1 or op.b == 1:
			del_piso = OpeningKinds.of(building, op)
		elif (op.a == int(ids[0]) and op.b == OUTSIDE_ID) or (op.b == int(ids[0]) and op.a == OUTSIDE_ID):
			del_zaguan = OpeningKinds.of(building, op)
	_eq("en la vista, la puerta del piso ya es interior", del_piso, OpeningKinds.INTERIOR)
	_eq("y la del zaguan da a la calle", del_zaguan, OpeningKinds.STREET_DOOR)
	# El rellano ya es el portal: delante del zaguan no se planta otro de
	# decorado, con su escalera, su ascensor y sus puertas de vecinos a la calle.
	_eq("la primera persona no planta un rellano de decorado", _nodos_de_rellano(building), 0)
	building.free()


## Nodos del rellano de DECORADO que construye la primera persona.
func _nodos_de_rellano(building: BuildingModel) -> int:
	var host := Node3D.new()
	root.add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	fp.setup(building)
	fp.set_active(true)
	var n: int = 0
	var pend: Array = [host]
	while not pend.is_empty():
		var node: Node = pend.pop_back()
		for c in node.get_children():
			pend.append(c)
		if String(node.name).begins_with("LandingFloor"):
			n += 1
	host.queue_free()
	return n
