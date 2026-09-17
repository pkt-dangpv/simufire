extends RefCounted

## Integridad PRESCRITA de panos acristalados: modelo puro (fase 3A).
##
## Fase 3A de docs/PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md. No esta conectado al
## motor ni al editor, no lee escenarios, no guarda estado, no modifica sus
## entradas y no usa aleatoriedad. Solo describe, hoja a hoja, el estado de
## integridad y la fraccion de material desprendida que prescribe quien llama.
##
## Lo que NO hace esta fase: no convierte el dano en aberturas, no da area,
## caudal, sentido ni diferencia de presion, no transporta nada y no toca la
## fraccion de apertura operativa ni el hueco termico del motor. No lee
## temperaturas ni calcula roturas: tipo de vidrio, espesor, marco y borde
## protegido se validan y se conservan como procedencia, sin efecto automatico
## (Skelly et al. 1990, Peng et al. 2024 y Wang et al. 2007 muestran que
## importan, pero no dan una calibracion universal).
##
## Estados de cada hoja: INTACT -> CRACKED -> PARTIAL_FALLOUT -> OPEN
##   - INTACT: hoja integra, fraccion desprendida 0.
##   - CRACKED: agrietada pero presente, fraccion 0. Una grieta NO ventila.
##   - PARTIAL_FALLOUT: falta una parte, 0 < fraccion < 1.
##   - OPEN: perdida completa normalizada, fraccion 1.
##
## Historia prescrita de cada hoja (eventos {time_s, state, fallout_fraction}):
##   - tiempos finitos, >= 0 y estrictamente crecientes;
##   - antes del primer evento la hoja esta INTACT con fraccion 0;
##   - en el instante de un evento entra en vigor su estado; entre eventos y
##     despues del ultimo se mantiene el ultimo estado, SIN interpolar;
##   - sin saltos: cada evento avanza como mucho un estado. El primero puede ser
##     INTACT o CRACKED. Solo PARTIAL_FALLOUT puede repetirse, con fraccion que
##     no disminuye; el vidrio no se regenera y no se retrocede de estado.
##
## Multicapa: cada hoja tiene su propia historia. Una fraccion por hoja no dice
## donde falta el material, asi que este modelo NO deduce ningun camino libre ni
## ventilacion a partir de minimos, maximos, productos o medias de fracciones.
## La coincidencia espacial entre hojas es de la fase 3B (regiones explicitas).
##
## Panel: {id, width_m, height_m, sill_z_m, glass_type, thickness_m,
##         leaf_count, leaf_spacing_m, frame_material, edge_protection_depth_m,
##         leaves, metadata?}
##   - glass_type: `annealed`, `toughened`, `laminated` u `other`; `other`
##     exige `metadata.glass_type_description` (texto no vacio).
##   - leaf_count y el `index` de cada hoja son enteros (TYPE_INT).
##   - leaf_spacing_m >= 0; con una sola hoja tiene que ser 0.
##   - edge_protection_depth_m >= 0 y 2*profundidad < min(ancho, alto).
## Hoja: {id, index, events, metadata?}, con indices 0..leaf_count-1 unicos.

const STATE_INTACT: String = "INTACT"
const STATE_CRACKED: String = "CRACKED"
const STATE_PARTIAL_FALLOUT: String = "PARTIAL_FALLOUT"
const STATE_OPEN: String = "OPEN"
const STATES: Array[String] = [STATE_INTACT, STATE_CRACKED, STATE_PARTIAL_FALLOUT, STATE_OPEN]

const GLASS_ANNEALED: String = "annealed"
const GLASS_TOUGHENED: String = "toughened"
const GLASS_LAMINATED: String = "laminated"
const GLASS_OTHER: String = "other"
const GLASS_TYPES: Array[String] = [GLASS_ANNEALED, GLASS_TOUGHENED, GLASS_LAMINATED, GLASS_OTHER]
const OTHER_DESCRIPTION_KEY: String = "glass_type_description"

const SOURCE_PRESCRIBED: String = "prescribed"

const PANEL_KEYS: Array[String] = [
	"id", "width_m", "height_m", "sill_z_m", "glass_type", "thickness_m",
	"leaf_count", "leaf_spacing_m", "frame_material", "edge_protection_depth_m", "leaves",
]
const LEAF_KEYS: Array[String] = ["id", "index", "events"]
const EVENT_KEYS: Array[String] = ["time_s", "state", "fallout_fraction"]


## Comprueba un panel. Devuelve {valid, errors}.
static func validate_panel(panel: Variant) -> Dictionary:
	var errors: Array[String] = []
	_validate_panel_into(panel, errors)
	return {"valid": errors.is_empty(), "errors": errors}


## Estado de un panel en `time_s`. Devuelve {valid, errors, time_s, panel,
## leaves, damage_summary}. `leaves` va ordenado por indice.
static func evaluate_panel(panel: Variant, time_s: float) -> Dictionary:
	var errors: Array[String] = []
	if not _is_finite(time_s) or time_s < 0.0:
		errors.append("time_s must be finite and >= 0")
	_validate_panel_into(panel, errors)
	if not errors.is_empty():
		return _invalid_panel_result(errors, time_s)

	var leaves: Array = []
	for leaf in panel["leaves"]:
		leaves.append(_evaluate_leaf(leaf, time_s))
	leaves.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["index"]) < int(right["index"]))

	return {
		"valid": true,
		"errors": errors,
		"time_s": time_s,
		"panel": _panel_description(panel),
		"leaves": leaves,
		"damage_summary": _damage_summary(leaves),
	}


## Estado de varios paneles en `time_s`, ordenados por id. Devuelve
## {valid, errors, time_s, panels}.
static func evaluate_panels(panels: Array, time_s: float) -> Dictionary:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var results: Array = []
	for panel in panels:
		var result: Dictionary = evaluate_panel(panel, time_s)
		if not bool(result["valid"]):
			errors.append_array(result["errors"])
			continue
		var panel_id: String = String(result["panel"]["id"])
		if seen.has(panel_id):
			errors.append("duplicate panel id '%s'" % panel_id)
			continue
		seen[panel_id] = true
		results.append(result)
	if not errors.is_empty():
		return {"valid": false, "errors": errors, "time_s": time_s, "panels": []}
	results.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["panel"]["id"]) < String(right["panel"]["id"]))
	return {"valid": true, "errors": errors, "time_s": time_s, "panels": results}


## Estado prescrito de una hoja ya validada en `time_s`.
static func _evaluate_leaf(leaf: Dictionary, time_s: float) -> Dictionary:
	var state: String = STATE_INTACT
	var fraction: float = 0.0
	var event_index: int = -1
	var event_time: Variant = null
	var events: Array = leaf["events"]
	for index in range(events.size()):
		var event: Dictionary = events[index]
		if float(event["time_s"]) > time_s:
			break
		state = String(event["state"])
		fraction = float(event["fallout_fraction"])
		event_index = index
		event_time = float(event["time_s"])
	var metadata: Dictionary = {}
	if leaf.has("metadata"):
		metadata = Dictionary(leaf["metadata"]).duplicate(true)
	return {
		"id": String(leaf["id"]),
		"index": int(leaf["index"]),
		"state": state,
		"fallout_fraction": fraction,
		"source": SOURCE_PRESCRIBED,
		"event_index": event_index,
		"event_time_s": event_time,
		"metadata": metadata,
	}


## Solo diagnostico: cuantas hojas hay en cada estado. No suma ni combina
## fracciones: eso no describe ninguna ventilacion.
static func _damage_summary(leaves: Array) -> Dictionary:
	var counts: Dictionary = {}
	for state in STATES:
		counts[state] = 0
	for leaf in leaves:
		counts[String(leaf["state"])] = int(counts[String(leaf["state"])]) + 1
	return {"diagnostic_only": true, "leaf_count_by_state": counts}


static func _panel_description(panel: Dictionary) -> Dictionary:
	var metadata: Dictionary = {}
	if panel.has("metadata"):
		metadata = Dictionary(panel["metadata"]).duplicate(true)
	return {
		"id": String(panel["id"]),
		"width_m": float(panel["width_m"]),
		"height_m": float(panel["height_m"]),
		"sill_z_m": float(panel["sill_z_m"]),
		"glass_type": String(panel["glass_type"]),
		"thickness_m": float(panel["thickness_m"]),
		"leaf_count": int(panel["leaf_count"]),
		"leaf_spacing_m": float(panel["leaf_spacing_m"]),
		"frame_material": String(panel["frame_material"]),
		"edge_protection_depth_m": float(panel["edge_protection_depth_m"]),
		"metadata": metadata,
	}


static func _validate_panel_into(panel: Variant, errors: Array[String]) -> void:
	if typeof(panel) != TYPE_DICTIONARY:
		errors.append("panel must be a dictionary")
		return
	var complete: bool = true
	for key in PANEL_KEYS:
		if not panel.has(key):
			errors.append("panel is missing '%s'" % key)
			complete = false
	if not complete:
		return
	var panel_id: String = _text(panel["id"])
	if panel_id.is_empty():
		errors.append("panel id must be a non-empty string")
		panel_id = "?"
	var label: String = "panel '%s'" % panel_id
	if panel.has("metadata") and typeof(panel["metadata"]) != TYPE_DICTIONARY:
		errors.append("%s metadata must be a dictionary" % label)

	var width: float = _number(panel["width_m"])
	var height: float = _number(panel["height_m"])
	if not _is_finite(width) or width <= 0.0:
		errors.append("%s width_m must be finite and > 0" % label)
	if not _is_finite(height) or height <= 0.0:
		errors.append("%s height_m must be finite and > 0" % label)
	if not _is_finite(_number(panel["sill_z_m"])):
		errors.append("%s sill_z_m must be finite" % label)
	var thickness: float = _number(panel["thickness_m"])
	if not _is_finite(thickness) or thickness <= 0.0:
		errors.append("%s thickness_m must be finite and > 0" % label)

	var glass_type: String = _exact_text(panel["glass_type"])
	if not GLASS_TYPES.has(glass_type):
		errors.append("%s glass_type '%s' must be one of %s" % [label, panel["glass_type"], GLASS_TYPES])
	elif glass_type == GLASS_OTHER:
		var described: bool = panel.has("metadata") and typeof(panel["metadata"]) == TYPE_DICTIONARY \
				and not _text(Dictionary(panel["metadata"]).get(OTHER_DESCRIPTION_KEY, "")).is_empty()
		if not described:
			errors.append("%s glass_type 'other' needs metadata.%s" % [label, OTHER_DESCRIPTION_KEY])
	if _text(panel["frame_material"]).is_empty():
		errors.append("%s frame_material must be a non-empty string" % label)

	var edge: float = _number(panel["edge_protection_depth_m"])
	if not _is_finite(edge) or edge < 0.0:
		errors.append("%s edge_protection_depth_m must be finite and >= 0" % label)
	elif _is_finite(width) and _is_finite(height) and width > 0.0 and height > 0.0 \
			and 2.0 * edge >= minf(width, height):
		errors.append("%s edge_protection_depth_m leaves no exposed glass" % label)

	var leaf_count_ok: bool = typeof(panel["leaf_count"]) == TYPE_INT and int(panel["leaf_count"]) >= 1
	if not leaf_count_ok:
		errors.append("%s leaf_count must be an integer >= 1" % label)
	var spacing: float = _number(panel["leaf_spacing_m"])
	if not _is_finite(spacing) or spacing < 0.0:
		errors.append("%s leaf_spacing_m must be finite and >= 0" % label)
	elif leaf_count_ok and int(panel["leaf_count"]) == 1 and spacing != 0.0:
		errors.append("%s leaf_spacing_m must be 0 for a single leaf" % label)

	if typeof(panel["leaves"]) != TYPE_ARRAY:
		errors.append("%s leaves must be an array" % label)
		return
	var leaves: Array = panel["leaves"]
	if leaf_count_ok and leaves.size() != int(panel["leaf_count"]):
		errors.append("%s declares %d leaves but lists %d" % [label, int(panel["leaf_count"]), leaves.size()])
	var seen_ids: Dictionary = {}
	var seen_indices: Dictionary = {}
	for leaf in leaves:
		_validate_leaf(leaf, label, int(panel["leaf_count"]) if leaf_count_ok else -1, seen_ids, seen_indices, errors)


static func _validate_leaf(leaf: Variant, panel_label: String, leaf_count: int,
		seen_ids: Dictionary, seen_indices: Dictionary, errors: Array[String]) -> void:
	if typeof(leaf) != TYPE_DICTIONARY:
		errors.append("%s leaves must be dictionaries" % panel_label)
		return
	var complete: bool = true
	for key in LEAF_KEYS:
		if not leaf.has(key):
			errors.append("%s leaf is missing '%s'" % [panel_label, key])
			complete = false
	if not complete:
		return
	var leaf_id: String = _text(leaf["id"])
	var label: String = "%s leaf '%s'" % [panel_label, leaf_id]
	if leaf_id.is_empty():
		errors.append("%s leaf id must be a non-empty string" % panel_label)
	elif seen_ids.has(leaf_id):
		errors.append("%s duplicate leaf id" % label)
	seen_ids[leaf_id] = true
	if typeof(leaf["index"]) != TYPE_INT:
		errors.append("%s index must be an integer" % label)
	else:
		var index: int = int(leaf["index"])
		if leaf_count >= 1 and (index < 0 or index >= leaf_count):
			errors.append("%s index %d is outside [0, %d)" % [label, index, leaf_count])
		elif seen_indices.has(index):
			errors.append("%s duplicate leaf index %d" % [label, index])
		seen_indices[index] = true
	if leaf.has("metadata") and typeof(leaf["metadata"]) != TYPE_DICTIONARY:
		errors.append("%s metadata must be a dictionary" % label)
	_validate_events(leaf["events"], label, errors)


static func _validate_events(events: Variant, label: String, errors: Array[String]) -> void:
	if typeof(events) != TYPE_ARRAY:
		errors.append("%s events must be an array" % label)
		return
	var previous_time: float = -INF
	var previous_rank: int = 0
	var previous_fraction: float = 0.0
	var first: bool = true
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			errors.append("%s events must be dictionaries" % label)
			return
		for key in EVENT_KEYS:
			if not event.has(key):
				errors.append("%s event is missing '%s'" % [label, key])
				return
		var time_s: float = _number(event["time_s"])
		var state: String = _exact_text(event["state"])
		var fraction: float = _number(event["fallout_fraction"])
		if not _is_finite(time_s) or time_s < 0.0:
			errors.append("%s event time must be finite and >= 0" % label)
			return
		if time_s <= previous_time:
			errors.append("%s event times must be strictly increasing (%s after %s)" % [label, time_s, previous_time])
			return
		if not STATES.has(state):
			errors.append("%s unknown state '%s'" % [label, event["state"]])
			return
		if not _is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
			errors.append("%s fallout_fraction must be finite and within [0, 1]" % label)
			return
		if not _fraction_matches_state(state, fraction):
			errors.append("%s state %s does not allow fallout_fraction %s" % [label, state, fraction])
			return
		var rank: int = STATES.find(state)
		if not _transition_allowed(previous_rank, rank, first):
			errors.append("%s transition %s -> %s is not allowed" % [label, STATES[previous_rank], state])
			return
		if fraction < previous_fraction:
			errors.append("%s fallout_fraction may not decrease (%s after %s)" % [label, fraction, previous_fraction])
			return
		previous_time = time_s
		previous_rank = rank
		previous_fraction = fraction
		first = false


static func _fraction_matches_state(state: String, fraction: float) -> bool:
	if state == STATE_INTACT or state == STATE_CRACKED:
		return fraction == 0.0
	if state == STATE_PARTIAL_FALLOUT:
		return fraction > 0.0 and fraction < 1.0
	return fraction == 1.0


## Sin saltos ni retrocesos. Antes del primer evento la hoja esta INTACT; el
## primer evento puede confirmarlo o pasar a CRACKED. Solo PARTIAL_FALLOUT se
## puede repetir.
static func _transition_allowed(previous_rank: int, rank: int, first: bool) -> bool:
	if first:
		return rank == 0 or rank == 1
	if rank == previous_rank:
		return STATES[rank] == STATE_PARTIAL_FALLOUT
	return rank == previous_rank + 1


static func _invalid_panel_result(errors: Array, time_s: float) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"time_s": time_s if _is_finite(time_s) else 0.0,
		"panel": {},
		"leaves": [],
		"damage_summary": {},
	}


## Texto recortado si el valor es un String; vacio si no lo es.
static func _text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	return String(value).strip_edges()


## El texto tal cual si el valor es un String; vacio si no lo es. Para valores
## de un vocabulario cerrado: no se recorta ni se normaliza.
static func _exact_text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	return String(value)


## Numero si el valor es int o float; NAN si no lo es.
static func _number(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return NAN


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
