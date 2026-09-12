extends SceneTree
## Guardarrail de la VISTA del portal, sobre el mundo de primera persona ya
## construido y con el portal dibujado por la herramienta del editor.
##
## Lo que las fotos de `tools/capture_portal.gd` ensenaron que fallaba, fijado:
##
##  1. **Al salir del piso se pisa suelo.** La escalera ocupaba la zona entera y
##     la puerta daba contra los tramos; en las plantas de arriba no habia
##     forjado ninguno delante de la puerta.
##  2. **Los tramos van en la parte de la escalera**, no encima del rellano, y el
##     hueco del forjado tampoco lo pisa.
##  3. **La caja esta cerrada por arriba**: la ultima zona lleva techo, y las de
##     en medio no, que es por donde sube la escalera.
##  4. **Cada rellano tiene su luz.** Sin ella el portal era negro.
##
##   <godot> --headless --path . --script res://tools/validate_portal_view.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const TOOL_PORTAL: int = 15
const PLANTA_H: float = 2.9

var _frames: int = 0
var _fails: int = 0
var _editor: Node = null


func _initialize() -> void:
	_editor = (load("res://scenes/ScenarioEditorScene.tscn") as PackedScene).instantiate()
	root.add_child(_editor)


func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	# Tres plantas, vivienda de 5 x 4 con la puerta en su pared derecha (y = 2), y
	# un portal de 4 x 3 pegado a ella: rellano a la izquierda del portal.
	var rects: Dictionary = {}
	var rooms: Array = []
	var ops: Array = []
	for p in range(3):
		var id: int = p + 1
		rects[str(id)] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rooms.append({"id": id, "name": "Vivienda %d" % p, "kind": "salon", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": PLANTA_H * p, "fuel_objects": []})
		ops.append({"a": id, "b": -1, "type": "door", "wall": "right", "offset_m": 0.5,
			"offset_is_fraction": true, "width_m": 0.92, "height_m": 2.05, "sill_m": 0.0, "open_fraction": 1.0})
	_editor.adopt_scenario_data({
		"building_type": "apartment", "apartment_floor_number": 0,
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": PLANTA_H}, {"name": "R+2", "level_m": PLANTA_H * 2.0}],
		"exterior_walls": [], "room_rect_m": rects, "rooms_data": rooms, "openings_data": ops,
		"detectors": [], "victims": [], "player_start": {}, "ignition_room_id": 1,
	}, 0)
	# Arrastrado en diagonal y "hacia abajo": la subida guardada NO mira a la
	# puerta. La vista tiene que ordenar el portal por las puertas, no por el gesto.
	_editor.current_tool = TOOL_PORTAL
	_editor._handle_press(Vector2(5.0, 0.0))
	_editor._handle_release(Vector2(9.0, 3.0))

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(Serializer.to_runtime_template(_editor.editor_data.duplicate(true)))
	var zonas: Array = []
	for rid in building.get_rooms().keys():
		if BuildingLevels.is_portal(building.get_room(rid)):
			zonas.append(building.get_room(rid))
	zonas.sort_custom(func(x, y): return x.floor_level_z_m < y.floor_level_z_m)
	_eq("tres zonas de portal", zonas.size(), 3)
	if zonas.size() != 3:
		return _fin(building)

	var host := Node3D.new()
	root.add_child(host)
	var fp: FirstPersonController = FirstPersonControllerScript.new()
	host.add_child(fp)
	fp.setup(building)
	fp.set_active(true)

	var nodos: Dictionary = {}
	var pend: Array = [host]
	while not pend.is_empty():
		var n: Node = pend.pop_back()
		for c in n.get_children():
			pend.append(c)
		nodos[String(n.name)] = n

	var layout: Dictionary = PortalGeometry.layout(building, zonas[1])
	_eq("el rellano va en la pared de las puertas", String(layout.get("landing_side", "")), "left")
	var landing: Rect2 = Rect2(layout["landing_rect"])
	var stair: Rect2 = Rect2(layout["stair_rect"])

	# ── 1. Delante de la puerta del piso hay suelo, en todas las plantas ──
	var delante := Vector2(5.45, 2.0)
	var sin_suelo: Array[String] = []
	for z in zonas:
		if not _hay_suelo_en(nodos, fp, z, delante):
			sin_suelo.append("%.1f" % z.floor_level_z_m)
	_eq("delante de la puerta del piso se pisa suelo en todas las plantas", ",".join(sin_suelo), "")

	# ── 2. Los tramos no invaden el rellano, y el hueco tampoco ──
	var tramos: Array = []
	for nombre in nodos.keys():
		if String(nombre).begins_with("StairFlight") or String(nombre).begins_with("StairStep"):
			tramos.append(nodos[nombre])
	_eq("hay tramos de escalera", tramos.size() > 0, true)
	var invaden: int = 0
	for t in tramos:
		var p: Vector3 = (t as Node3D).global_position
		var plano := Vector2(p.x - fp._to_world(Vector3.ZERO).x, p.z - fp._to_world(Vector3.ZERO).z)
		if landing.grow(-0.05).has_point(plano):
			invaden += 1
	_eq("ningun tramo cae sobre el rellano", invaden, 0)
	var huecos: Array[Rect2] = BuildingLevels.vertical_stair_voids(building, zonas[1].floor_level_z_m, true)
	var hueco_en_rellano: bool = false
	for h in huecos:
		if h.intersects(landing.grow(-0.02)):
			hueco_en_rellano = true
	_eq("el hueco del forjado no pisa el rellano", hueco_en_rellano, false)
	_eq("y cae dentro de la parte de la escalera", huecos.size() == 1 and stair.grow(0.02).encloses(huecos[0]), true)

	# ── 3. Cerrado por arriba ──
	var techos: Array[String] = []
	for z in zonas:
		if _hay(nodos, "Ceiling_%d" % z.id) or _hay(nodos, "CeilingPart_%d_" % z.id):
			techos.append("%.1f" % z.floor_level_z_m)
	_eq("solo la ultima zona lleva techo", ",".join(techos), "5.8")

	# ── 4. Luz en cada rellano ──
	var luces: int = 0
	for z in zonas:
		if nodos.has("PortalLight_%d" % z.id):
			luces += 1
	_eq("cada rellano tiene su luz", luces, 3)

	host.queue_free()
	return _fin(building)


## ¿Hay alguna losa de la zona `z` bajo ese punto del plano?
func _hay_suelo_en(nodos: Dictionary, fp: FirstPersonController, z: RoomModel, punto: Vector2) -> bool:
	var origen: Vector3 = fp._to_world(Vector3.ZERO, 0.0)
	for nombre in nodos.keys():
		var body := nodos[nombre] as StaticBody3D
		if body == null:
			continue
		for c in body.get_children():
			var mi := c as MeshInstance3D
			if mi == null or not String(mi.name).begins_with("FloorMesh") or mi.mesh == null:
				continue
			var caja: AABB = mi.global_transform * mi.mesh.get_aabb()
			if absf(caja.end.y - z.floor_level_z_m) > 0.05:
				continue
			var x: float = punto.x + origen.x
			var zz: float = punto.y + origen.z
			if x >= caja.position.x and x <= caja.end.x and zz >= caja.position.z and zz <= caja.end.z:
				return true
	return false


func _hay(nodos: Dictionary, prefijo: String) -> bool:
	for nombre in nodos.keys():
		if String(nombre) == prefijo or String(nombre).begins_with(prefijo):
			return true
	return false


func _fin(building: BuildingModel) -> bool:
	building.free()
	if _fails == 0:
		print("[validate_portal_view] PASS")
	else:
		push_error("[validate_portal_view] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
