extends Node

## Guardarrail del rellano del portal: nada puede compartir plano con el suelo.
##
## Dos caras en el mismo plano son la causa clasica de manchas irregulares que
## cambian al mover la camara: el z-buffer no puede decidir cual esta delante y
## el ganador depende del angulo. En el suelo del rellano habia tres piezas asi
## a la vez, y es donde el usuario ve el artefacto:
##
## - `DoorPorch`, la losa de pavimento del portal de entrada, que en un piso se
##   plantaba a la cota EXACTA del suelo del rellano y solapaba 1,80 x 1,70 m
##   justo delante de la puerta de la vivienda.
## - Los dos costados de la caja de escalera de la planta inferior, que
##   remataban en el plano del forjado en vez de en su intrados y cruzaban la
##   losa de lado a lado en una banda de 0,10 x 3,28 m.
##
## Ademas imprime, sin que eso decida nada, de donde viene la luz que hay en el
## suelo del rellano: mas de la mitad entra de fuera atravesando las paredes,
## porque estas omnis no proyectan sombra. Esta escrito aqui porque es el sitio
## donde se mide, pero es una decision de diseno, no un fallo que este test
## pueda arbitrar.
##
##   <godot> --headless --path . res://tools/validate_landing_surfaces.tscn

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const FirstPersonControllerScript := preload("res://view/fp/FirstPersonController.gd")

## Escenario y opciones de arranque de la ultima ejecucion del usuario
## (user://startup_sim_options.json, 2026-09-03): simple_house forzado a piso.
const TEMPLATE_PATH: String = "res://scenarios/preset_simple_house.json"
const BUILDING_TYPE: String = "apartment"
const APARTMENT_FLOOR: int = 1

## Dos caras se consideran coplanarias si sus planos distan menos que esto. Un
## milimetro y medio: por debajo de eso el z-buffer en 24 bits a las distancias
## de esta escena ya no las separa.
const COPLANAR_EPS_M: float = 0.0015

## Solape minimo en las otras dos direcciones para que la coincidencia importe.
const MIN_OVERLAP_M: float = 0.05

## Area de solape coplanario con el suelo del rellano a partir de la cual se
## da por fallado. Dos centimetros cuadrados: cualquier cosa que comparta
## plano con el suelo por el que anda el jugador es un fallo.
const MAX_FLOOR_COPLANAR_AREA_M2: float = 0.02

## Solape a partir del cual dos tabiques del mismo plano se dan por
## duplicados. Cinco centimetros cuadrados: por debajo es el redondeo de un
## encuentro, por encima son dos fabricas para el mismo muro.
const MAX_WALL_OVERLAP_AREA_M2: float = 0.05

var _failures: Array[String] = []

var _boxes: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var template: Dictionary = _load_template()
	if template.is_empty():
		push_error("No se pudo leer " + TEMPLATE_PATH)
		get_tree().quit(1)
		return
	template["building_type"] = BUILDING_TYPE
	template["apartment_floor_number"] = APARTMENT_FLOOR

	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data(template)

	var host := Node3D.new()
	host.name = "ValidateLandingHost"
	get_tree().root.add_child(host)

	var fp: FirstPersonController = FirstPersonControllerScript.new()
	fp.name = "LandingFP"
	host.add_child(fp)
	await get_tree().process_frame
	fp.setup(building)
	fp.set_active(true)
	await get_tree().physics_frame
	await get_tree().process_frame

	var world: Node = host.get_node_or_null("FirstPersonWorld")
	if world == null:
		world = fp
	_collect(world, "")

	print("== SONDA DEL RELLANO ==")
	print("escenario: %s  tipo=%s  planta=%d" % [TEMPLATE_PATH, BUILDING_TYPE, APARTMENT_FLOOR])
	print("cajas recogidas: %d" % _boxes.size())

	var landing: AABB = _landing_volume()
	print("volumen del rellano (mundo): pos=%s  size=%s" % [
		_v(landing.position), _v(landing.size)
	])

	_report_coplanar(landing)
	_report_landing_floor(landing)
	_report_landing_ceiling()
	_report_world_coplanar()
	_report_stacked_walls()
	_report_lights(host, landing)

	print("")
	if _failures.is_empty():
		print("LANDING SURFACES VALIDATION PASS")
		get_tree().quit(0)
		return
	push_error("LANDING SURFACES VALIDATION FAILED")
	for failure in _failures:
		push_error("- " + failure)
	get_tree().quit(1)


# ---------------------------------------------------------------------------
# Recogida
# ---------------------------------------------------------------------------

func _load_template() -> Dictionary:
	var file := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _collect(node: Node, path: String) -> void:
	var here: String = path + "/" + String(node.name)
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var aabb: AABB = mesh.get_aabb()
		var world_aabb := AABB(
			mesh.global_transform * aabb.position,
			aabb.size * mesh.global_transform.basis.get_scale()
		)
		world_aabb = world_aabb.abs()
		if mesh.is_visible_in_tree():
			_boxes.append({"path": here, "aabb": world_aabb, "visible": true})
	for child in node.get_children():
		_collect(child, here)


## Caja del rellano deducida del propio mundo: se toma la envolvente de todo lo
## que se llama Landing*, que es exactamente lo que construye
## _create_landing_recess.
func _landing_volume() -> AABB:
	var result := AABB()
	var first: bool = true
	for box in _boxes:
		if not String(box["path"]).contains("Landing"):
			continue
		var aabb: AABB = box["aabb"]
		if first:
			result = aabb
			first = false
		else:
			result = result.merge(aabb)
	return result


# ---------------------------------------------------------------------------
# 1. Superficies coplanarias
# ---------------------------------------------------------------------------

func _report_coplanar(landing: AABB) -> void:
	print("")
	print("-- 1. Caras coplanarias que se solapan dentro del rellano --")
	var probe: AABB = landing.grow(0.05)
	var inside: Array[Dictionary] = []
	for box in _boxes:
		var aabb: AABB = box["aabb"]
		if probe.intersects(aabb):
			inside.append(box)
	print("cajas que tocan el rellano: %d" % inside.size())

	var findings: Array[Dictionary] = []
	for i in range(inside.size()):
		for j in range(i + 1, inside.size()):
			var a: Dictionary = inside[i]
			var b: Dictionary = inside[j]
			if _same_parent(String(a["path"]), String(b["path"])):
				continue
			for axis in range(3):
				var hit: Dictionary = _coplanar_on_axis(a["aabb"], b["aabb"], axis)
				if hit.is_empty():
					continue
				findings.append({
					"axis": axis,
					"plane": hit["plane"],
					"area": hit["area"],
					"span": hit["span"],
					"a": a["path"],
					"b": b["path"],
					"a_box": _aabb_text(a["aabb"]),
					"b_box": _aabb_text(b["aabb"]),
				})

	findings.sort_custom(func(x, y): return float(x["area"]) > float(y["area"]))
	if findings.is_empty():
		print("ninguna. No hay superficies coincidentes en esta zona.")
		return
	print("%d pares coplanarios. Los mayores primero:" % findings.size())
	var shown: int = 0
	for f in findings:
		if shown >= 25:
			print("  ... y %d mas" % (findings.size() - shown))
			break
		print("  [%s = %.4f m] area %.2f m2  %s" % [
			["x", "y", "z"][int(f["axis"])], float(f["plane"]), float(f["area"]), String(f["span"])
		])
		print("      A %s  %s" % [f["a"], String(f["a_box"])])
		print("      B %s  %s" % [f["b"], String(f["b_box"])])
		shown += 1


## Devuelve el plano y el area de solape si alguna cara de `a` en el eje `axis`
## cae sobre alguna cara de `b`, y las cajas se solapan en los otros dos ejes.
func _coplanar_on_axis(a: AABB, b: AABB, axis: int) -> Dictionary:
	var a_min: float = a.position[axis]
	var a_max: float = a_min + a.size[axis]
	var b_min: float = b.position[axis]
	var b_max: float = b_min + b.size[axis]

	var plane: float = INF
	for a_face in [a_min, a_max]:
		for b_face in [b_min, b_max]:
			if absf(a_face - b_face) <= COPLANAR_EPS_M:
				plane = a_face
	if is_inf(plane):
		return {}

	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var ou: float = _overlap(a, b, u)
	var ov: float = _overlap(a, b, v)
	if ou < MIN_OVERLAP_M or ov < MIN_OVERLAP_M:
		return {}
	return {
		"plane": plane,
		"area": ou * ov,
		"span": "%s %.2f m x %s %.2f m" % [["x", "y", "z"][u], ou, ["x", "y", "z"][v], ov],
	}


## Dos piezas del mismo padre (las lenguas de una llama, los peldanos de un
## tramo) comparten planos por construccion y no son el problema.
func _same_parent(a_path: String, b_path: String) -> bool:
	return a_path.get_base_dir() == b_path.get_base_dir()


func _aabb_text(box: AABB) -> String:
	return "x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [
		box.position.x, box.position.x + box.size.x,
		box.position.y, box.position.y + box.size.y,
		box.position.z, box.position.z + box.size.z
	]


func _overlap(a: AABB, b: AABB, axis: int) -> float:
	var lo: float = maxf(a.position[axis], b.position[axis])
	var hi: float = minf(a.position[axis] + a.size[axis], b.position[axis] + b.size[axis])
	return maxf(0.0, hi - lo)


## Todo lo que hay a la cota del suelo del rellano o por debajo, dentro de su
## huella. Es la pregunta directa: que poligonos se generan bajo ese suelo.
func _report_landing_floor(landing: AABB) -> void:
	print("")
	print("-- 1b. Que hay a la cota del suelo del rellano o justo debajo --")
	var pieces: Array[AABB] = []
	for box in _boxes:
		if String(box["path"]).contains("LandingFloor"):
			pieces.append(box["aabb"])
	if pieces.is_empty():
		print("no hay LandingFloor en el mundo")
		return
	var floor_box: AABB = pieces[0]
	for piece in pieces:
		floor_box = floor_box.merge(piece)
	var top_y: float = floor_box.position.y + floor_box.size.y
	print("suelo del rellano: %d losas, envolvente %s, cara superior y=%.4f"
		% [pieces.size(), _aabb_text(floor_box), top_y])
	var hits: Array[String] = []
	for box in _boxes:
		var path: String = String(box["path"])
		# La cupula de cielo es una esfera de 160 m que envuelve la escena: su
		# AABB contiene todo y no comparte plano con nada.
		if path.contains("LandingFloor") or path.contains("SkyDome"):
			continue
		var aabb2: AABB = box["aabb"]
		if aabb2.position.y > top_y - 0.0005:
			continue
		# contra cada losa por separado: el ojo de la escalera es un hueco de
		# verdad, y ahi no hay forjado con el que pelearse
		var ox: float = 0.0
		var oz: float = 0.0
		for piece in pieces:
			var px: float = _overlap(aabb2, piece, 0)
			var pz: float = _overlap(aabb2, piece, 2)
			if px >= MIN_OVERLAP_M and pz >= MIN_OVERLAP_M and px * pz > ox * oz:
				ox = px
				oz = pz
		if ox < MIN_OVERLAP_M or oz < MIN_OVERLAP_M:
			continue
		# Cara superior contra cara superior: las dos miran hacia arriba, que es
		# la condicion para que se peleen por el pixel.
		var gap_m: float = top_y - (aabb2.position.y + aabb2.size.y)
		if absf(gap_m) > COPLANAR_EPS_M and gap_m > 0.02:
			continue
		var coplanar: bool = absf(gap_m) <= COPLANAR_EPS_M
		hits.append("  %-52s huella %.2f x %.2f m   desnivel %.4f m%s\n      %s"
			% [path, ox, oz, gap_m, "   << COPLANARIA" if coplanar else "",
			   _aabb_text(aabb2)])
		if coplanar and ox * oz >= MAX_FLOOR_COPLANAR_AREA_M2:
			_failures.append(
				"%s comparte plano con el suelo del rellano en %.2f m2 (%.2f x %.2f m)"
				% [path, ox * oz, ox, oz]
			)
	if hits.is_empty():
		print("nada solapa por debajo")
	hits.sort()
	for line in hits:
		print(line)


## Que comparte plano con el techo del rellano, por arriba o por abajo.
func _report_landing_ceiling() -> void:
	print("")
	print("-- 1d. Que hay a la cota del techo del rellano --")
	var pieces: Array[AABB] = []
	for box in _boxes:
		if String(box["path"]).contains("LandingCeiling"):
			pieces.append(box["aabb"])
	if pieces.is_empty():
		print("no hay LandingCeiling en el mundo")
		return
	var ceiling_box: AABB = pieces[0]
	for piece in pieces:
		ceiling_box = ceiling_box.merge(piece)
	var bottom_y: float = ceiling_box.position.y
	var top_y: float = ceiling_box.position.y + ceiling_box.size.y
	print("techo del rellano: %d losas, envolvente %s" % [pieces.size(), _aabb_text(ceiling_box)])
	print("  intrados y=%.4f   trasdos y=%.4f" % [bottom_y, top_y])
	var hits: Array[String] = []
	for box in _boxes:
		var path: String = String(box["path"])
		if path.contains("LandingCeiling") or path.contains("SkyDome"):
			continue
		var aabb2: AABB = box["aabb"]
		var other_bottom: float = aabb2.position.y
		var other_top: float = aabb2.position.y + aabb2.size.y
		# Solo pelean por el pixel dos caras que miran hacia el MISMO lado. Una
		# cara que mira arriba contra otra que mira abajo es un encuentro de dos
		# solidos -un tabique bajo un forjado- y es como se construye siempre.
		var which: String = ""
		var same_facing: bool = false
		if absf(other_bottom - bottom_y) <= COPLANAR_EPS_M:
			which = "intrados contra intrados"
			same_facing = true
		elif absf(other_top - top_y) <= COPLANAR_EPS_M:
			which = "trasdos contra trasdos"
			same_facing = true
		elif absf(other_top - bottom_y) <= COPLANAR_EPS_M:
			which = "apoya bajo el intrados (encuentro)"
		elif absf(other_bottom - top_y) <= COPLANAR_EPS_M:
			which = "apoya sobre el trasdos (encuentro)"
		if which == "":
			continue
		var ox: float = 0.0
		var oz: float = 0.0
		for piece in pieces:
			var px: float = _overlap(aabb2, piece, 0)
			var pz: float = _overlap(aabb2, piece, 2)
			if px >= MIN_OVERLAP_M and pz >= MIN_OVERLAP_M and px * pz > ox * oz:
				ox = px
				oz = pz
		if ox < MIN_OVERLAP_M or oz < MIN_OVERLAP_M:
			continue
		hits.append("  %-46s %-34s %.2f x %.2f m = %.2f m2\n      %s"
			% [path.trim_prefix("/LandingFP/FirstPersonWorld/"), which, ox, oz, ox * oz, _aabb_text(aabb2)])
		if same_facing and ox * oz >= MAX_FLOOR_COPLANAR_AREA_M2:
			_failures.append(
				"%s comparte plano con el techo del rellano (%s) en %.2f m2"
				% [path, which, ox * oz]
			)
	if hits.is_empty():
		print("nada comparte plano con el techo del rellano")
	hits.sort()
	for line in hits:
		print(line)


## Caras coplanarias en TODA la vivienda, agrupadas por plano. Informativo:
## sirve para localizar donde mas se pelean dos superficies por el mismo pixel.
func _report_world_coplanar() -> void:
	print("")
	print("-- 1c. Caras coplanarias en toda la vivienda, por plano --")
	var by_plane: Dictionary = {}
	for i in range(_boxes.size()):
		for j in range(i + 1, _boxes.size()):
			var a: Dictionary = _boxes[i]
			var b: Dictionary = _boxes[j]
			if _same_parent(String(a["path"]), String(b["path"])):
				continue
			for axis in range(3):
				var hit: Dictionary = _coplanar_on_axis(a["aabb"], b["aabb"], axis)
				if hit.is_empty() or float(hit["area"]) < 0.10:
					continue
				var key: String = "%s = %.3f" % [["x", "y", "z"][axis], float(hit["plane"])]
				if not by_plane.has(key):
					by_plane[key] = {"area": 0.0, "pairs": []}
				var bucket: Dictionary = by_plane[key]
				bucket["area"] = float(bucket["area"]) + float(hit["area"])
				var pairs: Array = bucket["pairs"]
				pairs.append(float(hit["area"]))
	var planes: Array = by_plane.keys()
	planes.sort_custom(func(x, y): return float(by_plane[x]["area"]) > float(by_plane[y]["area"]))
	print("%d planos con superficies enfrentadas (solape >= 0,10 m2):" % planes.size())
	var shown: int = 0
	for key in planes:
		if shown >= 14:
			print("  ... y %d planos mas" % (planes.size() - shown))
			break
		var bucket: Dictionary = by_plane[key]
		var pairs: Array = bucket["pairs"]
		print("  [%s]  %.2f m2 en %d pares" % [key, float(bucket["area"]), pairs.size()])
		shown += 1


## Dos tabiques no pueden ocupar el mismo sitio.
##
## Cada sala pide sus cuatro lados, asi que una medianera la piden las dos
## salas que la comparten y hace falta quedarse con una sola fabrica. El
## criterio antiguo comparaba la caja entera, y eso solo casa cuando las dos
## salas parten el muro por los mismos sitios: un pasillo no lo hace nunca,
## porque su lado corre a lo largo de varias habitaciones mientras cada
## habitacion corta en su propio borde. Resultado: 13,4 m2 de tabique
## duplicado en el pasillo del piso patron, un solido dentro de otro, con las
## caras peleandose por cada pixel al mover la camara.
##
## Aqui se compara solo entre tabiques PARALELOS Y EN EL MISMO PLANO. Dos
## muros perpendiculares que se cruzan en una esquina comparten volumen y eso
## es correcto; quedan fuera por construccion, porque su eje delgado no
## coincide.
func _report_stacked_walls() -> void:
	print("")
	print("-- 1e. Tabiques que ocupan el mismo sitio --")
	var by_plane: Dictionary = {}
	for box in _boxes:
		if not String(box["path"]).contains("WallMesh"):
			continue
		var aabb: AABB = box["aabb"]
		# el eje delgado es el grosor del tabique
		var thin: int = 0
		for axis in range(3):
			if aabb.size[axis] < aabb.size[thin]:
				thin = axis
		var key: String = "%s|%.3f|%.3f" % [
			["x", "y", "z"][thin], aabb.position[thin], aabb.position[thin] + aabb.size[thin]
		]
		if not by_plane.has(key):
			by_plane[key] = []
		var group: Array = by_plane[key]
		group.append({"path": box["path"], "aabb": aabb, "thin": thin})
	var stacked: int = 0
	for key in by_plane.keys():
		var group: Array = by_plane[key]
		for i in range(group.size()):
			for j in range(i + 1, group.size()):
				var a: Dictionary = group[i]
				var b: Dictionary = group[j]
				var thin: int = int(a["thin"])
				var ou: float = _overlap(a["aabb"], b["aabb"], (thin + 1) % 3)
				var ov: float = _overlap(a["aabb"], b["aabb"], (thin + 2) % 3)
				if ou * ov < MAX_WALL_OVERLAP_AREA_M2:
					continue
				stacked += 1
				_failures.append(
					"tabique duplicado en el plano %s: %.2f m2 entre %s y %s"
					% [key, ou * ov, String(a["path"]).get_base_dir().get_file(), String(b["path"]).get_base_dir().get_file()]
				)
				print("  %.2f m2 en el plano %s" % [ou * ov, key])
				print("      A %s  %s" % [String(a["path"]).trim_prefix("/LandingFP/FirstPersonWorld/"), _aabb_text(a["aabb"])])
				print("      B %s  %s" % [String(b["path"]).trim_prefix("/LandingFP/FirstPersonWorld/"), _aabb_text(b["aabb"])])
	if stacked == 0:
		print("ninguno: cada plano de tabique tiene una sola fabrica")


# ---------------------------------------------------------------------------
# 2. Luces que llegan al rellano
# ---------------------------------------------------------------------------

func _report_lights(root: Node, landing: AABB) -> void:
	print("")
	print("-- 2. Luces que alcanzan el interior del rellano --")
	var lights: Array[Light3D] = []
	_collect_lights(root, lights)
	print("luces en el mundo: %d" % lights.size())

	var own: Array[String] = []
	var foreign: Array[String] = []
	for light in lights:
		var pos: Vector3 = light.global_position
		var omni := light as OmniLight3D
		var reach_m: float = omni.omni_range if omni != null else 0.0
		var inside_landing: bool = landing.has_point(pos)
		var reaches: bool = inside_landing
		if not reaches and omni != null:
			# distancia del centro de la luz a la caja del rellano
			reaches = _distance_to_aabb(pos, landing) <= reach_m
		if not reaches:
			continue
		var line: String = "  %-38s pos=%s energia=%.2f alcance=%.2f m" % [
			String(light.name), _v(pos), light.light_energy, reach_m
		]
		if inside_landing:
			own.append(line)
		else:
			foreign.append(line + "  dist al rellano=%.2f m" % _distance_to_aabb(pos, landing))

	_report_floor_irradiance(lights, landing)
	print("dentro del rellano (%d):" % own.size())
	for line in own:
		print(line)
	print("fuera, pero con alcance suficiente para entrar (%d):" % foreign.size())
	if foreign.is_empty():
		print("  ninguna")
	for line in foreign:
		print(line)


## Cuanta luz deja cada foco sobre el suelo del rellano. Se muestrea una
## rejilla en la huella del rellano y se suma la atenuacion de Godot para
## omnis: energia * (1 - d/alcance)^atenuacion. No es un fotometro, pero
## ordena las fuentes, que es lo que hace falta para saber que apagar.
func _report_floor_irradiance(lights: Array[Light3D], landing: AABB) -> void:
	var y: float = landing.position.y
	for box in _boxes:
		if String(box["path"]).contains("LandingFloor"):
			var aabb: AABB = box["aabb"]
			y = aabb.position.y + aabb.size.y
			break
	var samples: Array[Vector3] = []
	var steps: int = 6
	for ix in range(steps):
		for iz in range(steps):
			samples.append(Vector3(
				landing.position.x + landing.size.x * (float(ix) + 0.5) / float(steps),
				y + 0.01,
				landing.position.z + landing.size.z * (float(iz) + 0.5) / float(steps)
			))
	var totals: Array[Dictionary] = []
	var grand: float = 0.0
	for light in lights:
		var omni := light as OmniLight3D
		if omni == null:
			continue
		var sum: float = 0.0
		for point in samples:
			var d: float = omni.global_position.distance_to(point)
			if d >= omni.omni_range:
				continue
			sum += omni.light_energy * pow(1.0 - d / omni.omni_range, omni.omni_attenuation)
		if sum <= 0.0:
			continue
		var avg: float = sum / float(samples.size())
		totals.append({"name": String(omni.name), "avg": avg, "pos": omni.global_position})
		grand += avg
	print("")
	print("aporte medio de cada omni sobre el suelo del rellano (y=%.3f, %d muestras):" % [y, samples.size()])
	if grand <= 0.0:
		print("  ninguno")
		return
	totals.sort_custom(func(a, b): return float(a["avg"]) > float(b["avg"]))
	for t in totals:
		print("  %-28s %.4f   (%.1f %% del total)   pos=%s" % [
			String(t["name"]), float(t["avg"]), float(t["avg"]) / grand * 100.0, _v(t["pos"])
		])
	print("  total %.4f" % grand)


func _collect_lights(node: Node, result: Array[Light3D]) -> void:
	var light := node as Light3D
	if light != null:
		result.append(light)
	for child in node.get_children():
		_collect_lights(child, result)


func _distance_to_aabb(point: Vector3, box: AABB) -> float:
	var closest := Vector3(
		clampf(point.x, box.position.x, box.position.x + box.size.x),
		clampf(point.y, box.position.y, box.position.y + box.size.y),
		clampf(point.z, box.position.z, box.position.z + box.size.z)
	)
	return point.distance_to(closest)


func _v(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]
