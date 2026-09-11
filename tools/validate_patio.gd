extends SceneTree
## Guardarrail de la herramienta de PATIO.
##
## Un patio de luces no es una sala: es un conducto vertical que atraviesa todas
## las plantas del edificio y remata abierto al cielo. Lo que se comprueba es
## justo eso, porque es lo que el motor necesita para hacer la fisica y lo que
## se pierde si alguien toca el encadenado:
##
##  1. **Una zona por planta**, todas con el mismo rectangulo.
##  2. **Encadenadas** con huecos verticales entre plantas consecutivas.
##  3. **Una boca**, y solo una: la zona de arriba abierta al exterior.
##  4. **No se conecta solo con las salas vecinas.** Un pasillo y una escalera si
##     -existen para conectar-, pero a un patio se da con una ventana, y donde va
##     esa ventana lo decide quien dibuja.
##  5. **Un patio diminuto no se crea**: por debajo de metro y medio de lado es un
##     conducto de instalaciones, ni ventila ni se asoma nadie.
##
## Medido antes de escribir la herramienta: con esta representacion el motor ya
## hace la fisica del patio sin tocar nada (docs/PROMPT_MOTOR_PATIO.md).
##
##   <godot> --headless --path . --script res://tools/validate_patio.gd

const TOOL_PATIO: int = 14
const TOOL_ROOM: int = 1
const OUTSIDE_ID: int = -1

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
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


## Tres plantas y una sala en la baja, para poder comprobar que el patio NO se
## conecta solo con ella.
func _tres_plantas() -> void:
	_editor.adopt_scenario_data({
		"floors": [
			{"name": "R", "level_m": 0.0},
			{"name": "R+1", "level_m": 2.9},
			{"name": "R+2", "level_m": 5.8},
		],
		"exterior_walls": [],
		"room_rect_m": {"1": {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}},
		"rooms_data": [{
			"id": 1, "name": "Cocina", "kind": "cocina", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": 0.0, "fuel_objects": [],
		}],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {}, "ignition_room_id": 1,
	}, 0)


func _patios() -> Array:
	var out: Array = []
	for raw in _editor.editor_data.get("rooms_data", []):
		if typeof(raw) == TYPE_DICTIONARY and String(Dictionary(raw).get("kind", "")) == "patio":
			out.append(raw)
	return out


func _verticales() -> Array:
	var out: Array = []
	for raw in _editor.editor_data.get("openings_data", []):
		if typeof(raw) == TYPE_DICTIONARY and bool(Dictionary(raw).get("is_vertical", false)):
			out.append(raw)
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	# ── 1. Un patio de 2,5 x 2,5 pegado a la cocina ──
	_tres_plantas()
	_editor.current_tool = TOOL_PATIO
	_editor._handle_press(Vector2(5.0, 0.0))
	_editor._handle_release(Vector2(7.5, 2.5))

	var zonas: Array = _patios()
	_eq("una zona de patio por planta", zonas.size(), 3)
	var niveles: Array = []
	for z in zonas:
		niveles.append("%.1f" % float(Dictionary(z).get("floor_level_z_m", -1.0)))
	niveles.sort()
	_eq("y una en cada cota", ",".join(niveles), "0.0,2.9,5.8")

	var vert: Array = _verticales()
	_eq("huecos verticales: encadenado + boca", vert.size(), 3)
	var bocas: int = 0
	for v in vert:
		if int(Dictionary(v).get("b", 0)) == OUTSIDE_ID:
			bocas += 1
	_eq("y una sola boca al cielo", bocas, 1)

	# La boca es la de ARRIBA del todo, no una cualquiera.
	var cota_max: float = -1.0
	var id_arriba: int = -1
	for z in zonas:
		var lv: float = float(Dictionary(z).get("floor_level_z_m", 0.0))
		if lv > cota_max:
			cota_max = lv
			id_arriba = int(Dictionary(z).get("id", -1))
	var boca_en_arriba: bool = false
	for v in vert:
		if int(Dictionary(v).get("b", 0)) == OUTSIDE_ID and int(Dictionary(v).get("a", -1)) == id_arriba:
			boca_en_arriba = true
	_eq("la boca esta en la planta alta", boca_en_arriba, true)

	# ── 2. NO se conecta solo con la cocina que toca ──
	var horizontales: int = 0
	for raw in _editor.editor_data.get("openings_data", []):
		if typeof(raw) == TYPE_DICTIONARY and not bool(Dictionary(raw).get("is_vertical", false)):
			horizontales += 1
	_eq("no se abre paso solo a la sala vecina", horizontales, 0)

	# ── 3. Un patio diminuto no se crea ──
	_tres_plantas()
	_editor.current_tool = TOOL_PATIO
	_editor._handle_press(Vector2(0.0, 0.0))
	_editor._handle_release(Vector2(0.8, 0.8))
	_eq("un patio de 0,8 m no se crea", _patios().size(), 0)

	# ── 4. La zona no lleva carga de fuego propia ──
	_tres_plantas()
	_editor.current_tool = TOOL_PATIO
	_editor._handle_press(Vector2(5.0, 0.0))
	_editor._handle_release(Vector2(7.5, 2.5))
	var carga: float = 0.0
	for z in _patios():
		carga += float(Dictionary(z).get("fuel_energy_MJ", 0.0))
	_eq("el patio no arde por si mismo", carga, 0.0)

	# ── 5. Y en la VISTA es un pozo, no tres cajas apiladas ──
	_comprobar_pozo()

	# ── 6. Una terraza suelta llamada "patio" NO es un conducto ──
	_comprobar_terraza()

	if _fails == 0:
		print("[validate_patio] PASS")
	else:
		push_error("[validate_patio] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


## El patio, construido en primera persona, tiene que ser un CONDUCTO:
##
##   - suelo **solo en el fondo**; una zona de arriba con forjado convierte el
##     pozo en tres cajas apiladas,
##   - **sin techo** en ninguna zona: desde la ventana se tiene que ver el cielo,
##   - y **sin plafon**, que es lo que cuelga de un techo que no existe.
##
## Se comprueba sobre el escenario que produce la propia herramienta, no sobre
## uno escrito a mano: asi el guardarrail cubre el camino entero, de dibujar a
## construir.
func _comprobar_pozo() -> void:
	# Por el camino real: el editor no le da `editor_data` al motor, le da el
	# template de ejecucion. Pasarle el diccionario crudo carga CERO salas, y el
	# guardarrail habria comprobado un edificio vacio sin enterarse.
	var data: Dictionary = _editor.editor_data.duplicate(true)
	data["building_type"] = "apartment"
	data["apartment_floor_number"] = 1
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Serializer.to_runtime_template(data))

	var ids_patio: Dictionary = {}
	var cota_min: float = 1.0e20
	for rid in building.get_rooms().keys():
		var room: RoomModel = building.get_room(rid)
		if room == null or String(room.kind).to_lower() != "patio":
			continue
		ids_patio[int(rid)] = room.floor_level_z_m
		cota_min = minf(cota_min, room.floor_level_z_m)
	if ids_patio.is_empty():
		print("  FAIL no hay zonas de patio que construir (%d salas en el modelo)" % building.get_rooms().size())
		_fails += 1
		return

	var host := Node3D.new()
	root.add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	fp.setup(building)
	fp.set_active(true)

	var world: Node = host.get_node_or_null("FirstPersonWorld")
	if world == null:
		world = fp
	var vistos: Dictionary = {}
	var pendientes: Array = [world]
	while not pendientes.is_empty():
		var node: Node = pendientes.pop_back()
		for child in node.get_children():
			pendientes.append(child)
		vistos[String(node.name)] = true

	# Una losa entera se llama `Floor_N`; una RECORTADA por un hueco vertical se
	# reparte en `FloorPart_N`. Mirar solo la primera deja pasar la repisa que
	# queda alrededor del pozo, que es justo lo que no puede haber.
	var suelos_arriba: Array[String] = []
	var techos: Array[String] = []
	var plafones: Array[String] = []
	var suelo_fondo: bool = false
	for rid in ids_patio.keys():
		var es_fondo: bool = absf(float(ids_patio[rid]) - cota_min) < 0.05
		if _hay_losa(vistos, "Floor", rid):
			if es_fondo:
				suelo_fondo = true
			else:
				suelos_arriba.append(str(rid))
		if _hay_losa(vistos, "Ceiling", rid):
			techos.append(str(rid))
		if vistos.has("CeilingLight_%d" % rid):
			plafones.append(str(rid))

	# Se imprime siempre: al leerlo se ve de un vistazo si el pozo esta abierto.
	var diag: Array = []
	for rid3 in ids_patio.keys():
		diag.append("%d@%.1f%s" % [rid3, float(ids_patio[rid3]), "+suelo" if _hay_losa(vistos, "Floor", rid3) else ""])
	diag.sort()
	print("  zonas del conducto: %s" % ", ".join(diag))
	_eq("el fondo del patio tiene pavimento", suelo_fondo, true)
	_eq("y las zonas de arriba no llevan forjado", ",".join(suelos_arriba), "")
	_eq("ninguna zona del patio lleva techo", ",".join(techos), "")
	_eq("ni plafon colgado de el", ",".join(plafones), "")

	host.queue_free()
	building.free()


## ¿Hay losa de ese tipo para esa sala, entera o en trozos?
func _hay_losa(vistos: Dictionary, prefijo: String, room_id: int) -> bool:
	if vistos.has("%s_%d" % [prefijo, room_id]):
		return true
	var trozo: String = "%sPart_%d_" % [prefijo, room_id]
	for nombre in vistos.keys():
		if String(nombre).begins_with(trozo):
			return true
	return false


## Un patio a pie de calle y una terraza llamada tambien "patio" en la planta de
## arriba son dos sitios distintos, no un conducto de dos plantas. Lo que los
## separa es el ENCADENADO: sin hueco vertical entre ellos, cada uno es su propio
## fondo y los dos llevan suelo. Con el criterio de "la cota mas baja del
## edificio", la terraza se habria quedado sin suelo y se caeria uno por ella.
func _comprobar_terraza() -> void:
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data({
		"version": 1, "building_type": "apartment", "apartment_floor_number": 0,
		"exterior_walls": [],
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": 2.9}],
		"room_rect_m": {
			"1": {"x": 0.0, "y": 0.0, "w": 3.0, "h": 3.0},
			"2": {"x": 6.0, "y": 0.0, "w": 3.0, "h": 3.0},
		},
		"rooms_data": [
			{"id": 1, "name": "Patio", "kind": "patio", "rotation_deg": 0.0,
				"height_m": 2.9, "floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 2, "name": "Patio alto", "kind": "patio", "rotation_deg": 0.0,
				"height_m": 2.9, "floor_level_z_m": 2.9, "fuel_objects": []},
		],
		"openings_data": [], "detectors": [], "victims": [],
		"player_start": {"room_id": 1, "x_m": 1.0, "y_m": 1.0}, "ignition_room_id": 1,
	})
	var host := Node3D.new()
	root.add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	fp.setup(building)
	fp.set_active(true)

	var vistos: Dictionary = {}
	var pend: Array = [host]
	while not pend.is_empty():
		var node: Node = pend.pop_back()
		for child in node.get_children():
			pend.append(child)
		vistos[String(node.name)] = true

	_eq("sin encadenar, la terraza de arriba conserva su suelo", _hay_losa(vistos, "Floor", 2), true)
	_eq("y la de abajo tambien", _hay_losa(vistos, "Floor", 1), true)

	host.queue_free()
	building.free()
