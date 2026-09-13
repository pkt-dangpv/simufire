extends SceneTree
## Guardarrail del HUMO DEL PATIO visto desde fuera.
##
## El humo de primera persona es de camara: tine lo que se ve desde la sala en la
## que esta el jugador. Eso deja el patio **limpio al mirarlo por la ventana**,
## que es justo donde un patio tiene que leerse como una chimenea. El conducto
## lleva por eso lo unico que se dibuja como volumen.
##
## Lo que se fija aqui:
##
##  1. **Hay un segmento por zona de patio**, y solo en el patio. Si apareciera
##     en las viviendas, el mundo entero se veria a traves de una gasa.
##  2. **Un conducto limpio no dibuja nada.** Sin esto queda un velo gris
##     permanente que nadie relacionaria con el humo.
##  3. **Se opaca con el humo de SU zona.** Es lo que hace que el frente suba
##     planta a planta en vez de encenderse el conducto entero a la vez.
##  4. **Cuelga del techo, no del suelo**: ocupa lo que hay entre la interfase y
##     el techo de su zona. Un humo que crece desde el suelo es la capa al reves.
##  5. **No toca los paramentos.** Dos superficies en el mismo plano parpadean:
##     es la clase de fallo del X-8.
##
##   <godot> --headless --path . --script res://tools/validate_patio_smoke.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

const PATIO_LADO_M: float = 2.5
const PLANTA_H: float = 2.9

var _frames: int = 0
var _fails: int = 0
var _fp: FirstPersonController = null


func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1


## Tres plantas: vivienda + zona de patio en cada una, encadenadas.
func _escenario() -> Dictionary:
	var rooms: Array = []
	var rects: Dictionary = {}
	var ops: Array = []
	for p in range(3):
		var z: float = float(p) * PLANTA_H
		var viv: int = 10 * p + 1
		var pat: int = 10 * p + 2
		rooms.append({
			"id": viv, "name": "Vivienda %d" % p, "kind": "salon", "rotation_deg": 0.0,
			"height_m": 2.5, "floor_level_z_m": z, "fuel_objects": [],
		})
		rooms.append({
			"id": pat, "name": "Patio %d" % p, "kind": "patio", "rotation_deg": 0.0,
			"height_m": PLANTA_H, "floor_level_z_m": z, "fuel_objects": [],
		})
		rects[str(viv)] = {"x": 0.0, "y": 0.0, "w": 5.0, "h": 4.0}
		rects[str(pat)] = {"x": 5.0, "y": 0.0, "w": PATIO_LADO_M, "h": PATIO_LADO_M}
		if p + 1 < 3:
			ops.append({
				"a": pat, "b": 10 * (p + 1) + 2, "type": "hole", "wall": "",
				"offset_m": 0.0, "offset_is_fraction": true, "width_m": PATIO_LADO_M,
				"height_m": PATIO_LADO_M, "sill_m": 0.0, "open_fraction": 1.0,
				"is_vertical": true, "swing_direction": "in", "hinge_side": "left",
			})
	return {
		"version": 1, "building_type": "apartment", "apartment_floor_number": 0,
		"exterior_walls": [],
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": PLANTA_H},
			{"name": "R+2", "level_m": PLANTA_H * 2.0}],
		"room_rect_m": rects, "rooms_data": rooms, "openings_data": ops,
		"detectors": [], "victims": [],
		"player_start": {"room_id": 1, "x_m": 2.0, "y_m": 2.0}, "ignition_room_id": 1,
	}


## El estado de una sala llena de humo hasta `layer_m` del suelo.
func _humo(layer_m: float, visibilidad_m: float) -> Dictionary:
	return {
		"visibility_m": visibilidad_m,
		"smoke_kg": 3.0,
		"visible_smoke_layer_m": layer_m,
		"combustion_regime": "WELL_VENTILATED",
		"o2_upper": 0.19,
		"hrr_kw": 0.0,
	}


## Los segmentos de humo que hay construidos, por sala.
func _segmentos() -> Dictionary:
	var out: Dictionary = {}
	var pend: Array = [_fp]
	while not pend.is_empty():
		var node: Node = pend.pop_back()
		for child in node.get_children():
			pend.append(child)
		var mi := node as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("PatioSmoke_"):
			continue
		out[int(String(mi.name).trim_prefix("PatioSmoke_"))] = mi
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(_escenario())
	var host := Node3D.new()
	root.add_child(host)
	_fp = FirstPersonControllerScript.new()
	host.add_child(_fp)
	_fp.setup(building)
	_fp.set_active(true)

	# ── 1. Un segmento por zona de patio, y solo ahi ──
	var segs: Dictionary = _segmentos()
	var ids: Array = segs.keys()
	ids.sort()
	_eq("un segmento por zona de patio, y solo ahi", ",".join(ids.map(func(i): return str(i))), "2,12,22")

	# ── 2. Conducto limpio: no se dibuja nada ──
	_fp.set_state({})
	var visibles_limpio: int = 0
	for id_limpio in segs.keys():
		if (segs[id_limpio] as MeshInstance3D).visible:
			visibles_limpio += 1
	_eq("con el conducto limpio no se dibuja nada", visibles_limpio, 0)

	# ── 3. El humo llega a la planta baja: solo esa zona se opaca ──
	_fp.set_state({"2": _humo(0.6, 1.5)})
	_eq("humo solo en la zona baja: se ve esa", _visibles(segs), "2")

	# ── 4. Sube: dos zonas, y la de abajo mas opaca que la de arriba ──
	_fp.set_state({"2": _humo(0.6, 1.5), "12": _humo(2.4, 9.0)})
	_eq("y al subir se ven dos", _visibles(segs), "2,12")
	var baja: float = _alpha(segs[2])
	var alta: float = _alpha(segs[12])
	_eq("la de abajo mas opaca que la de arriba", baja > alta, true)

	# ── 5. La zona en la que esta la camara no dibuja su columna ──
	#
	# Asomarse por la ventana mete la cabeza en el conducto. La caja quedaria
	# alrededor del ojo y taparia la pantalla de un gris plano; de ese humo se
	# encarga la niebla de camara, que sabe mirarlo desde dentro.
	_fp._current_room_id = 2
	_fp.set_state({"2": _humo(0.6, 1.5), "12": _humo(2.4, 9.0)})
	_eq("la zona donde esta la camara no se dibuja", _visibles(segs), "12")
	_fp._current_room_id = -1
	_fp.set_state({"2": _humo(0.6, 1.5), "12": _humo(2.4, 9.0)})

	# ── 6. Cuelga del techo, no crece del suelo ──
	#
	# Con la interfase a 0,6 m del suelo de la zona baja, el segmento ocupa de
	# 0,6 a 2,9: su centro queda a 1,75 m y su grosor es de 2,3 m.
	var caja := segs[2] as MeshInstance3D
	var mesh := caja.mesh as BoxMesh
	_eq("grosor = del techo a la interfase", "%.2f" % mesh.size.y, "%.2f" % (PLANTA_H - 0.6))
	_eq("y su centro, a media altura de esa franja", "%.2f" % caja.position.y, "%.2f" % (0.6 + (PLANTA_H - 0.6) * 0.5))

	# ── 7. No toca los paramentos del patio ──
	_eq("deja holgura con las paredes en X", mesh.size.x < PATIO_LADO_M, true)
	_eq("y en Z", mesh.size.z < PATIO_LADO_M, true)

	host.queue_free()
	building.free()

	if _fails == 0:
		print("[validate_patio_smoke] PASS")
	else:
		push_error("[validate_patio_smoke] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


## Que segmentos se estan dibujando ahora mismo.
func _visibles(segs: Dictionary) -> String:
	var out: Array = []
	for id_seg in segs.keys():
		if (segs[id_seg] as MeshInstance3D).visible:
			out.append(int(id_seg))
	out.sort()
	return ",".join(out.map(func(i): return str(i)))


## Opacidad del segmento.
func _alpha(node) -> float:
	var mi := node as MeshInstance3D
	if mi == null:
		return 0.0
	var material := mi.material_override as StandardMaterial3D
	return material.albedo_color.a if material != null else 0.0
