extends RefCounted

## Geometria del camino libre por desprendimiento de vidrio: modelo puro
## (fase 3B de docs/PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md).
##
## Recibe una instantanea YA evaluada por la fase 3A (integridad prescrita:
## panel, hojas, estado y fraccion desprendida) y, aparte, las regiones
## desprendidas de cada hoja. Devuelve los rectangulos del camino libre real a
## traves de TODAS las hojas. No reevalua historias, no carga otros modelos, no
## guarda estado, no modifica sus entradas y no usa aleatoriedad. No es un
## caudal: no hay presion, sentido, velocidad, masa ni transporte, y no toca la
## fraccion de apertura operativa ni el hueco termico del motor.
##
## Principio: camino_libre = huecos_hoja_0 ∩ huecos_hoja_1 ∩ ... ∩ huecos_hoja_n.
##   - INTACT y CRACKED no tienen hueco: bloquean todo el panel.
##   - OPEN es el panel completo (se normaliza aqui; no admite regiones).
##   - PARTIAL_FALLOUT deja libre solo la union de sus regiones.
## Nunca se sustituye la interseccion por minimos, maximos, productos o medias
## de fracciones.
##
## Primera version: hojas rectangulares, alineadas y coextensivas con el panel;
## regiones rectangulares alineadas con los ejes.
##
## Coordenadas: locales respecto a la esquina inferior izquierda del pano,
## 0 <= x <= ancho y 0 <= z <= alto. Cota global = sill_z_m del panel + z local.
##
## Entrada espacial: {panel_id, leaves: [{id, index, regions: [{id, x_m, z_m,
## width_m, height_m, metadata?}]}]}, con exactamente una entrada por hoja de la
## instantanea (mismo id y mismo indice). Las regiones se validan sin recortes ni
## desplazamientos: fuera del panel, dimensiones no positivas o no finitas, ids
## vacios o repetidos dentro de la hoja se rechazan.
##
## Identificadores: "vacio" e "identidad" son cosas distintas.
##   - Contenido: un id tiene que ser String o StringName y no puede quedarse
##     vacio al quitarle los espacios exteriores. strip_edges() se usa SOLO para
##     esa comprobacion (_is_blank_identifier).
##   - Identidad: el id real es el texto ORIGINAL. No se recorta, no se
##     normaliza, no se cambia de caja. Se compara caracter a caracter y se
##     devuelve exactamente igual en panel_id, en leaf_union_areas_m2, en
##     contributors y en los mensajes de error.
##   - Por tanto "pane_a" y " pane_a " son paneles distintos, "leaf_0" y
##     " leaf_0 " son hojas distintas, y "Leaf_0" no es "leaf_0". Si la
##     instantanea 3A trae " leaf_0 ", la entrada espacial tiene que traer
##     exactamente " leaf_0 ".
##   - Los ids de region siguen la misma regla: identidad exacta, tambien para
##     detectar repetidos dentro de la hoja y como procedencia.
##   - Excepcion deliberada: los ids de hoja REPETIDOS de la instantanea se
##     detectan sobre el texto recortado, porque la fase 3A ya rechaza dos hojas
##     que solo se diferencien en espacios exteriores. Asi una instantanea
##     fraudulenta no cuela por 3B.
##
## Conservacion: en PARTIAL_FALLOUT la union de las regiones (sin doble conteo
## de solapes) tiene que valer area_panel * fallout_fraction con una tolerancia
## de FRACTION_TOLERANCE en fraccion, y estar estrictamente entre 0 y el area
## del panel. La geometria es la fuente; la fraccion es el guardarrail. Nada se
## escala para forzar la coincidencia.
##
## Algoritmo (exacto, sin rasterizar): los bordes x y z de todas las regiones y
## del panel forman una rejilla. Cada celda pertenece al hueco de una hoja si una
## de sus regiones la contiene entera, y al camino libre si esta en el hueco de
## todas las hojas. Las celdas libres se fusionan de forma determinista: primero
## tramos horizontales de celdas contiguas con la misma procedencia, luego, de
## abajo arriba, tramos verticales con el mismo intervalo x y la misma
## procedencia. Nunca se fusiona a traves de una celda no libre. Los rectangulos
## salen ordenados por (z, x, ancho, alto) y numerados en ese orden.

const STATE_INTACT: String = "INTACT"
const STATE_CRACKED: String = "CRACKED"
const STATE_PARTIAL_FALLOUT: String = "PARTIAL_FALLOUT"
const STATE_OPEN: String = "OPEN"
const STATES: Array[String] = [STATE_INTACT, STATE_CRACKED, STATE_PARTIAL_FALLOUT, STATE_OPEN]

const SOURCE: String = "glazing_fallout"
const RECTANGLE_ID_PREFIX: String = "fallout_path_"

## Tolerancia en fraccion para contrastar la union geometrica de una hoja con
## su fallout_fraction prescrita. Solo se usa en esa comprobacion.
const FRACTION_TOLERANCE: float = 1.0e-9


## Camino libre de un panel. Devuelve {valid, errors, panel_id, panel_width_m,
## panel_height_m, panel_sill_z_m, panel_area_m2, rectangles, open_area_m2,
## leaf_union_areas_m2}.
static func compute_open_geometry(integrity_snapshot: Variant, spatial: Variant) -> Dictionary:
	var errors: Array[String] = []
	var panel: Dictionary = _validated_panel(integrity_snapshot, errors)
	if not errors.is_empty():
		return _invalid_result(errors)
	var leaves: Array = _validated_leaves(integrity_snapshot, errors)
	if not errors.is_empty():
		return _invalid_result(errors)
	var holes: Dictionary = _validated_spatial(spatial, panel, leaves, errors)
	if not errors.is_empty():
		return _invalid_result(errors)

	var width: float = float(panel["width_m"])
	var height: float = float(panel["height_m"])
	var panel_area: float = width * height

	# Rejilla exacta con todos los bordes.
	var xs: Array = [0.0, width]
	var zs: Array = [0.0, height]
	for leaf in leaves:
		for region in holes[String(leaf["id"])]:
			xs.append(float(region["x_m"]))
			xs.append(float(region["x_m"]) + float(region["width_m"]))
			zs.append(float(region["z_m"]))
			zs.append(float(region["z_m"]) + float(region["height_m"]))
	xs = _sorted_unique(xs)
	zs = _sorted_unique(zs)

	# Cobertura de cada celda por hoja.
	var leaf_unions: Array = []
	var coverage: Dictionary = {}
	for leaf in leaves:
		var leaf_id: String = String(leaf["id"])
		var state: String = String(leaf["state"])
		var union_area: float = 0.0
		var cells: Dictionary = {}
		for j in range(zs.size() - 1):
			for i in range(xs.size() - 1):
				var covering: Array = _covering_regions(state, holes[leaf_id], xs[i], xs[i + 1], zs[j], zs[j + 1])
				if covering.is_empty() and state != STATE_OPEN:
					continue
				cells[Vector2i(i, j)] = covering
				union_area += (float(xs[i + 1]) - float(xs[i])) * (float(zs[j + 1]) - float(zs[j]))
		coverage[leaf_id] = cells
		var geometric_fraction: float = union_area / panel_area
		var prescribed: float = float(leaf["fallout_fraction"])
		if state == STATE_PARTIAL_FALLOUT:
			if union_area <= 0.0 or union_area >= panel_area:
				errors.append("leaf '%s' partial fallout union must be > 0 and < the panel area" % leaf_id)
			elif absf(geometric_fraction - prescribed) > FRACTION_TOLERANCE:
				errors.append("leaf '%s' regions cover %.12f of the panel but fallout_fraction is %.12f" % [
					leaf_id, geometric_fraction, prescribed])
		leaf_unions.append({
			"leaf_id": leaf_id,
			"leaf_index": int(leaf["index"]),
			"state": state,
			"union_area_m2": union_area,
			"geometric_fallout_fraction": geometric_fraction,
			"prescribed_fallout_fraction": prescribed,
		})
	if not errors.is_empty():
		return _invalid_result(errors)

	# Celdas libres: en el hueco de todas las hojas.
	var free_cells: Dictionary = {}
	for j in range(zs.size() - 1):
		for i in range(xs.size() - 1):
			var key: Vector2i = Vector2i(i, j)
			var contributors: Array = []
			var free: bool = true
			for leaf in leaves:
				var cells: Dictionary = coverage[String(leaf["id"])]
				if not cells.has(key):
					free = false
					break
				contributors.append({
					"leaf_id": String(leaf["id"]),
					"leaf_index": int(leaf["index"]),
					"leaf_state": String(leaf["state"]),
					"region_ids": cells[key].duplicate(),
				})
			if free:
				free_cells[key] = contributors

	var rectangles: Array = _merge_cells(free_cells, xs, zs)
	var sill: float = float(panel["sill_z_m"])
	rectangles.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _rectangle_before(left, right))
	var open_area: float = 0.0
	for index in range(rectangles.size()):
		var rectangle: Dictionary = rectangles[index]
		rectangle["id"] = "%s%03d" % [RECTANGLE_ID_PREFIX, index]
		rectangle["global_sill_z_m"] = sill + float(rectangle["local_z_m"])
		rectangle["area_m2"] = float(rectangle["width_m"]) * float(rectangle["height_m"])
		rectangle["source"] = SOURCE
		open_area += float(rectangle["area_m2"])

	return {
		"valid": true,
		"errors": errors,
		"panel_id": _exact_text(panel["id"]),
		"panel_width_m": width,
		"panel_height_m": height,
		"panel_sill_z_m": sill,
		"panel_area_m2": panel_area,
		"rectangles": rectangles,
		"open_area_m2": open_area,
		"leaf_union_areas_m2": leaf_unions,
	}


## Regiones de la hoja que contienen entera la celda [x0, x1] x [z0, z1],
## ordenadas por id. OPEN cubre todo sin regiones; INTACT y CRACKED nada.
static func _covering_regions(state: String, regions: Array, x0: float, x1: float, z0: float, z1: float) -> Array:
	var covering: Array = []
	if state != STATE_PARTIAL_FALLOUT:
		return covering
	for region in regions:
		var rx: float = float(region["x_m"])
		var rz: float = float(region["z_m"])
		if rx <= x0 and x1 <= rx + float(region["width_m"]) \
				and rz <= z0 and z1 <= rz + float(region["height_m"]):
			covering.append(String(region["id"]))
	covering.sort()
	return covering


## Fusion determinista de celdas libres: tramos horizontales contiguos con la
## misma procedencia y, de abajo arriba, apilado de tramos iguales.
static func _merge_cells(free_cells: Dictionary, xs: Array, zs: Array) -> Array:
	var closed: Array = []
	var active: Dictionary = {}
	for j in range(zs.size() - 1):
		var runs: Array = []
		var i: int = 0
		while i < xs.size() - 1:
			var key: Vector2i = Vector2i(i, j)
			if not free_cells.has(key):
				i += 1
				continue
			var contributors: Array = free_cells[key]
			var signature: String = JSON.stringify(contributors, "", true, true)
			var end: int = i + 1
			while end < xs.size() - 1:
				var next_key: Vector2i = Vector2i(end, j)
				if not free_cells.has(next_key):
					break
				if JSON.stringify(free_cells[next_key], "", true, true) != signature:
					break
				end += 1
			runs.append({"i0": i, "i1": end, "signature": signature, "contributors": contributors})
			i = end
		var next_active: Dictionary = {}
		for run in runs:
			var run_key: String = "%d|%d|%s" % [run["i0"], run["i1"], run["signature"]]
			if active.has(run_key):
				var rectangle: Dictionary = active[run_key]
				rectangle["z1"] = zs[j + 1]
				next_active[run_key] = rectangle
				active.erase(run_key)
			else:
				next_active[run_key] = {
					"x0": xs[run["i0"]],
					"x1": xs[run["i1"]],
					"z0": zs[j],
					"z1": zs[j + 1],
					"contributors": run["contributors"],
				}
		for leftover in active.values():
			closed.append(leftover)
		active = next_active
	for leftover in active.values():
		closed.append(leftover)

	var rectangles: Array = []
	for item in closed:
		rectangles.append({
			"local_x_m": float(item["x0"]),
			"local_z_m": float(item["z0"]),
			"width_m": float(item["x1"]) - float(item["x0"]),
			"height_m": float(item["z1"]) - float(item["z0"]),
			"contributors": _deep_copy(item["contributors"]),
		})
	return rectangles


static func _rectangle_before(left: Dictionary, right: Dictionary) -> bool:
	for key in ["local_z_m", "local_x_m", "width_m", "height_m"]:
		if float(left[key]) != float(right[key]):
			return float(left[key]) < float(right[key])
	return false


static func _validated_panel(snapshot: Variant, errors: Array[String]) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		errors.append("integrity snapshot must be a dictionary")
		return {}
	if not snapshot.has("valid") or typeof(snapshot["valid"]) != TYPE_BOOL or not bool(snapshot["valid"]):
		errors.append("integrity snapshot must be a valid phase 3A result")
		return {}
	if not snapshot.has("panel") or typeof(snapshot["panel"]) != TYPE_DICTIONARY:
		errors.append("integrity snapshot needs a panel description")
		return {}
	var panel: Dictionary = snapshot["panel"]
	for key in ["id", "width_m", "height_m", "sill_z_m"]:
		if not panel.has(key):
			errors.append("snapshot panel is missing '%s'" % key)
	if not errors.is_empty():
		return {}
	if _is_blank_identifier(_exact_text(panel["id"])):
		errors.append("snapshot panel id must be a non-empty string")
	for key in ["width_m", "height_m"]:
		var value: float = _number(panel[key])
		if not _is_finite(value) or value <= 0.0:
			errors.append("snapshot panel %s must be finite and > 0" % key)
	if not _is_finite(_number(panel["sill_z_m"])):
		errors.append("snapshot panel sill_z_m must be finite")
	return panel


static func _validated_leaves(snapshot: Dictionary, errors: Array[String]) -> Array:
	if not snapshot.has("leaves") or typeof(snapshot["leaves"]) != TYPE_ARRAY or Array(snapshot["leaves"]).is_empty():
		errors.append("integrity snapshot needs at least one leaf")
		return []
	var leaves: Array = []
	var ids: Dictionary = {}
	var indices: Dictionary = {}
	for leaf in snapshot["leaves"]:
		if typeof(leaf) != TYPE_DICTIONARY:
			errors.append("snapshot leaves must be dictionaries")
			continue
		var complete: bool = true
		for key in ["id", "index", "state", "fallout_fraction"]:
			if not leaf.has(key):
				errors.append("snapshot leaf is missing '%s'" % key)
				complete = false
		if not complete:
			continue
		var leaf_id: String = _exact_text(leaf["id"])
		# Identidad exacta; los repetidos se miran sobre el texto recortado
		# porque la fase 3A ya los rechaza asi.
		var duplicate_key: String = leaf_id.strip_edges()
		if _is_blank_identifier(leaf_id) or ids.has(duplicate_key):
			errors.append("snapshot leaf ids must be non-empty and unique ('%s')" % leaf["id"])
		ids[duplicate_key] = true
		if typeof(leaf["index"]) != TYPE_INT or indices.has(int(leaf["index"])):
			errors.append("snapshot leaf '%s' needs a unique integer index" % leaf_id)
		else:
			indices[int(leaf["index"])] = true
		var state: String = _exact_text(leaf["state"])
		var fraction: float = _number(leaf["fallout_fraction"])
		if not STATES.has(state):
			errors.append("snapshot leaf '%s' has unknown state '%s'" % [leaf_id, leaf["state"]])
		elif not _is_finite(fraction) or not _fraction_matches_state(state, fraction):
			errors.append("snapshot leaf '%s' state %s does not allow fallout_fraction %s" % [leaf_id, state, leaf["fallout_fraction"]])
		leaves.append({"id": leaf_id, "index": leaf["index"], "state": state, "fallout_fraction": fraction})
	leaves.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["index"]) < int(right["index"]))
	return leaves


## Devuelve {leaf_id: [regiones validadas]} o rellena `errors`.
static func _validated_spatial(spatial: Variant, panel: Dictionary, leaves: Array, errors: Array[String]) -> Dictionary:
	var holes: Dictionary = {}
	if typeof(spatial) != TYPE_DICTIONARY:
		errors.append("spatial input must be a dictionary")
		return holes
	if not spatial.has("panel_id") or _exact_text(spatial["panel_id"]) != _exact_text(panel["id"]):
		errors.append("spatial panel_id must match the snapshot panel id '%s'" % panel["id"])
	if not spatial.has("leaves") or typeof(spatial["leaves"]) != TYPE_ARRAY:
		errors.append("spatial input needs a leaves array")
		return holes
	var by_id: Dictionary = {}
	for leaf in leaves:
		by_id[String(leaf["id"])] = leaf
	var width: float = float(panel["width_m"])
	var height: float = float(panel["height_m"])
	for entry in spatial["leaves"]:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id") or not entry.has("index") or not entry.has("regions"):
			errors.append("each spatial leaf needs id, index and regions")
			continue
		var leaf_id: String = _exact_text(entry["id"])
		if not by_id.has(leaf_id):
			errors.append("spatial leaf '%s' is not in the snapshot" % entry["id"])
			continue
		if holes.has(leaf_id):
			errors.append("spatial leaf '%s' is listed twice" % leaf_id)
			continue
		var leaf: Dictionary = by_id[leaf_id]
		if typeof(entry["index"]) != TYPE_INT or int(entry["index"]) != int(leaf["index"]):
			errors.append("spatial leaf '%s' index does not match the snapshot" % leaf_id)
		if typeof(entry["regions"]) != TYPE_ARRAY:
			errors.append("spatial leaf '%s' regions must be an array" % leaf_id)
			continue
		var regions: Array = []
		var region_ids: Dictionary = {}
		for region in entry["regions"]:
			var checked: Dictionary = _validated_region(region, leaf_id, width, height, region_ids, errors)
			if not checked.is_empty():
				regions.append(checked)
		var state: String = String(leaf["state"])
		if (state == STATE_INTACT or state == STATE_CRACKED or state == STATE_OPEN) and not Array(entry["regions"]).is_empty():
			errors.append("spatial leaf '%s' is %s and admits no regions" % [leaf_id, state])
		if state == STATE_PARTIAL_FALLOUT and Array(entry["regions"]).is_empty():
			errors.append("spatial leaf '%s' is PARTIAL_FALLOUT and needs at least one region" % leaf_id)
		holes[leaf_id] = regions
	for leaf_id in by_id.keys():
		if not holes.has(leaf_id):
			errors.append("spatial input is missing leaf '%s'" % leaf_id)
	return holes


static func _validated_region(region: Variant, leaf_id: String, width: float, height: float,
		region_ids: Dictionary, errors: Array[String]) -> Dictionary:
	if typeof(region) != TYPE_DICTIONARY:
		errors.append("leaf '%s' regions must be dictionaries" % leaf_id)
		return {}
	for key in ["id", "x_m", "z_m", "width_m", "height_m"]:
		if not region.has(key):
			errors.append("leaf '%s' region is missing '%s'" % [leaf_id, key])
			return {}
	var region_id: String = _exact_text(region["id"])
	var label: String = "leaf '%s' region '%s'" % [leaf_id, region_id]
	if _is_blank_identifier(region_id):
		errors.append("leaf '%s' has a region with an empty id" % leaf_id)
		return {}
	if region_ids.has(region_id):
		errors.append("%s is duplicated" % label)
		return {}
	region_ids[region_id] = true
	if region.has("metadata") and typeof(region["metadata"]) != TYPE_DICTIONARY:
		errors.append("%s metadata must be a dictionary" % label)
		return {}
	var x: float = _number(region["x_m"])
	var z: float = _number(region["z_m"])
	var w: float = _number(region["width_m"])
	var h: float = _number(region["height_m"])
	for value in [x, z, w, h]:
		if not _is_finite(value):
			errors.append("%s needs finite coordinates and sizes" % label)
			return {}
	if w <= 0.0 or h <= 0.0:
		errors.append("%s needs width and height > 0" % label)
		return {}
	if x < 0.0 or z < 0.0 or x + w > width or z + h > height:
		errors.append("%s lies outside the panel" % label)
		return {}
	return {"id": region_id, "x_m": x, "z_m": z, "width_m": w, "height_m": h}


static func _fraction_matches_state(state: String, fraction: float) -> bool:
	if state == STATE_INTACT or state == STATE_CRACKED:
		return fraction == 0.0
	if state == STATE_PARTIAL_FALLOUT:
		return fraction > 0.0 and fraction < 1.0
	return fraction == 1.0


static func _sorted_unique(values: Array) -> Array:
	var ordered: Array = values.duplicate()
	ordered.sort()
	var unique: Array = []
	for value in ordered:
		if unique.is_empty() or float(unique[unique.size() - 1]) != float(value):
			unique.append(float(value))
	return unique


static func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		return Array(value).duplicate(true)
	if typeof(value) == TYPE_DICTIONARY:
		return Dictionary(value).duplicate(true)
	return value


static func _invalid_result(errors: Array) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"panel_id": "",
		"panel_width_m": 0.0,
		"panel_height_m": 0.0,
		"panel_sill_z_m": 0.0,
		"panel_area_m2": 0.0,
		"rectangles": [],
		"open_area_m2": 0.0,
		"leaf_union_areas_m2": [],
	}


## Texto exacto de un valor de texto, sin tocar. "" si no es texto.
static func _exact_text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	return String(value)


## Unico sitio donde se recortan espacios: decidir si un identificador esta
## vacio. Nunca se usa para emparejar identidades.
static func _is_blank_identifier(text: String) -> bool:
	return text.strip_edges().is_empty()


static func _number(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return NAN


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
