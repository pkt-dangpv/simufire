extends RefCounted

## F2.2D4B2A: el controlador con el que el editor CONFIGURA la fisica
## experimental de una abertura.
##
## Es la unica pieza del editor que toca estos datos, y no sabe fisica:
##
##   - la politica de que se puede elegir la pone `OpeningProfileSelection`;
##   - la compatibilidad la pone `OpeningPhysicsProfileCatalog`;
##   - la validacion persistente la pone `PrescribedOpeningPhysicsSchema`, que
##     a su vez delega en los modelos puros de D2 y D3;
##   - la ley de rendija, el orificio, la geometria multicapa y el transporte
##     siguen donde estaban y aqui no se copia ni una linea de ninguno.
##
## ## Configurar no es activar
##
## Ninguna funcion de este fichero:
##
##   - enciende `closed_door_leakage_enabled`, `closed_door_deformation_enabled`,
##     `glazing_fallout_enabled`, `exterior_envelope_leakage_enabled` ni
##     `pressure_network_solver_enabled`;
##   - toca `open_fraction`, `glass_broken` ni `thermal_gap_fraction`;
##   - deforma una puerta ni rompe un vidrio;
##   - añade un elemento a la red.
##
## Guardar un perfil escribe una referencia versionada y una copia congelada de
## sus parametros. Nada mas.
##
## ## Devolucion
##
## Toda operacion devuelve `{ok, errors, opening}`. Cuando no sale bien, la
## abertura vuelve SIN TOCAR: no hay estados a medias.

const Catalog = preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")
const Selection = preload("res://sim/building/OpeningProfileSelection.gd")
const Schema = preload("res://sim/building/PrescribedOpeningPhysicsSchema.gd")

## Familias de prescripcion que el editor sabe editar, y la clave del escenario
## donde vive cada una. No se inventa ninguna: son las tres de D4A.
const TRACK_FAMILY: String = "deformation_track"
const PANEL_FAMILY: String = "glazing_panel"
const REGION_FAMILY: String = "glazing_region"

## Posiciones de hueco que admite `ClosedDoorDeformationModel`. Se nombran aqui
## solo para ofrecerlas en el desplegable; quien las valida es el modelo puro.
const TRACK_LOCATIONS: Array[String] = ["bottom", "top", "hinge_side", "latch_side"]
## Estados de hoja que admite `GlazingIntegrityModel`, en su orden de contrato.
const GLAZING_STATES: Array[String] = [
	"INTACT", "CRACKED", "PARTIAL_FALLOUT", "OPEN",
]
## Tipos de vidrio que admite `GlazingIntegrityModel`. Se ofrecen; quien los
## valida es el modelo puro.
const GLASS_TYPES: Array[String] = ["annealed", "toughened", "laminated", "other"]

## Lo que el editor sabe añadir a la prescripcion, en el orden del desplegable.
## Cada uno dice que campos usa, para que el panel enseñe solo esos.
const ENTRY_DEFORMATION_POINT: int = 0
const ENTRY_GLAZING_PANEL: int = 1
const ENTRY_LEAF_EVENT: int = 2
const ENTRY_SPATIAL_REGION: int = 3
const ENTRY_KINDS: Array[Dictionary] = [
	{
		"index": ENTRY_DEFORMATION_POINT,
		"label": "Instante de deformación prescrita",
		"fields": ["id", "location", "z_m", "time_s", "additional_ela_m2"],
	},
	{
		"index": ENTRY_GLAZING_PANEL,
		"label": "Paño de vidrio",
		"fields": ["id", "glass", "x_m", "z_m", "width_m", "height_m", "leaf_count"],
	},
	{
		"index": ENTRY_LEAF_EVENT,
		"label": "Estado prescrito de una hoja",
		"fields": ["id", "child_id", "time_s", "state", "fallout_percent"],
	},
	{
		"index": ENTRY_SPATIAL_REGION,
		"label": "Región desprendida de una hoja",
		"fields": ["id", "child_id", "time_s", "x_m", "z_m", "width_m", "height_m"],
	},
]

## Lo que cada estado significa para la ventilacion, en texto para el editor.
## No es una regla nueva: es la de D3, escrita para que se lea en pantalla.
const GLAZING_STATE_NOTE: Dictionary = {
	"INTACT": "Hoja entera. No ventila.",
	"CRACKED": "Agrietada pero presente. NO crea área de ventilación.",
	"PARTIAL_FALLOUT": "Se ha perdido parte del vidrio. Ventila solo la geometría libre real a través de todas las hojas.",
	"OPEN": "Paño desprendido entero.",
}


## Ficha completa de la abertura para el panel: que perfiles se ofrecen por
## categoria, cual esta puesto y que dice la prescripcion que ya tiene.
static func inspect(opening_data: Dictionary, experimental_confirmed: bool) -> Dictionary:
	var categories: Array[String] = Selection.categories_for(opening_data)
	var slots: Array[Dictionary] = []
	for slot in Schema.PROFILE_KEYS:
		var category: String = String(Schema.PROFILE_SLOT_CATEGORY[slot])
		if not categories.has(category):
			continue
		var selected: Dictionary = {}
		var block: Variant = opening_data.get(slot, null)
		if typeof(block) == TYPE_DICTIONARY and not Dictionary(block).is_empty():
			var entry: Dictionary = block
			selected = Selection.describe_id(
				String(entry.get(Schema.PROFILE_ID_KEY, "")),
				int(entry.get(Schema.PROFILE_VERSION_KEY, 0)),
				opening_data, experimental_confirmed
			)
			if selected.is_empty():
				selected = {
					"versioned_id": "%s@%d" % [
						String(entry.get(Schema.PROFILE_ID_KEY, "")),
						int(entry.get(Schema.PROFILE_VERSION_KEY, 0)),
					],
					"title": "Perfil desconocido para este catálogo",
					"evidence_label": "DESCONOCIDO — el catálogo no publica esta versión",
					"disabled_reason": "el escenario nombra un perfil que este catálogo no tiene",
				}
		slots.append({
			"slot": slot,
			"category": category,
			"rows": Selection.rows_for(opening_data, category, experimental_confirmed),
			"selected": selected,
			"selected_id": String(selected.get("versioned_id", Selection.NO_PROFILE_ID)),
		})
	return {
		"slots": slots,
		"prescription": describe_prescription(opening_data),
		"configured": Schema.declares(opening_data),
		"status_text": Selection.CONFIGURED_NOT_ACTIVE_TEXT if Schema.declares(opening_data) \
				else "Esta abertura no declara física experimental.",
		"schema_version": Schema.required_schema_version(opening_data),
	}


## La prescripcion ya guardada, aplanada en filas para el listado del editor.
##
## Solo lectura: conserva el orden de la historia y no reordena nada. Cada fila
## lleva su `path`, la ruta exacta al dato, que es lo que despues usa
## `remove_entry` para quitar justo eso y no lo de al lado.
static func describe_prescription(opening_data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var tracks: Array = Array(opening_data.get(Schema.DEFORMATION_KEY, []))
	for track_index in range(tracks.size()):
		if typeof(tracks[track_index]) != TYPE_DICTIONARY:
			continue
		var track: Dictionary = tracks[track_index]
		rows.append({
			"family": TRACK_FAMILY,
			"depth": 0,
			"id": String(track.get("id", "")),
			"path": [Schema.DEFORMATION_KEY, track_index],
			"text": "Deformación · %s · %s" % [
				String(track.get("id", "")), String(track.get("location", ""))
			],
			"detail": "cota %s m" % str(track.get("z_m", 0.0)),
		})
		var points: Array = Array(track.get("points", []))
		for point_index in range(points.size()):
			if typeof(points[point_index]) != TYPE_ARRAY:
				continue
			var point: Array = points[point_index]
			if point.size() < 2:
				continue
			rows.append({
				"family": TRACK_FAMILY,
				"depth": 1,
				"id": String(track.get("id", "")),
				"path": [Schema.DEFORMATION_KEY, track_index, point_index],
				"text": "t = %s s" % str(point[0]),
				"detail": "ELA adicional = %s m²" % str(point[1]),
			})
	var panels: Array = Array(opening_data.get(Schema.PANELS_KEY, []))
	for panel_index in range(panels.size()):
		if typeof(panels[panel_index]) != TYPE_DICTIONARY:
			continue
		var panel: Dictionary = panels[panel_index]
		rows.append({
			"family": PANEL_FAMILY,
			"depth": 0,
			"id": String(panel.get("id", "")),
			"path": [Schema.PANELS_KEY, panel_index],
			"text": "Paño · %s · %s" % [
				String(panel.get("id", "")), String(panel.get("glass_type", ""))
			],
			"detail": "%s x %s m en x = %s m, alféizar %s m · %s hoja(s)" % [
				str(panel.get("width_m", 0.0)), str(panel.get("height_m", 0.0)),
				str(panel.get("host_x_m", 0.0)), str(panel.get("sill_z_m", 0.0)),
				str(panel.get("leaf_count", 0)),
			],
		})
		var leaves: Array = Array(panel.get("leaves", []))
		for leaf_index in range(leaves.size()):
			if typeof(leaves[leaf_index]) != TYPE_DICTIONARY:
				continue
			var leaf: Dictionary = leaves[leaf_index]
			rows.append({
				"family": PANEL_FAMILY,
				"depth": 1,
				"id": String(leaf.get("id", "")),
				"path": [Schema.PANELS_KEY, panel_index, leaf_index],
				"text": "Hoja %s · índice %s" % [
					String(leaf.get("id", "")), str(leaf.get("index", 0))
				],
				"detail": "",
			})
			var events: Array = Array(leaf.get("events", []))
			for event_index in range(events.size()):
				if typeof(events[event_index]) != TYPE_DICTIONARY:
					continue
				var event: Dictionary = events[event_index]
				var state: String = String(event.get("state", ""))
				rows.append({
					"family": PANEL_FAMILY,
					"depth": 2,
					"id": String(leaf.get("id", "")),
					"path": [Schema.PANELS_KEY, panel_index, leaf_index, event_index],
					"text": "t = %s s · %s" % [str(event.get("time_s", 0.0)), state],
					"detail": "%s (fracción %s)" % [
						String(GLAZING_STATE_NOTE.get(state, "")),
						str(event.get("fallout_fraction", 0.0)),
					],
				})
	var spatials: Array = Array(opening_data.get(Schema.SPATIAL_KEY, []))
	for spatial_index in range(spatials.size()):
		if typeof(spatials[spatial_index]) != TYPE_DICTIONARY:
			continue
		var spatial: Dictionary = spatials[spatial_index]
		rows.append({
			"family": REGION_FAMILY,
			"depth": 0,
			"id": String(spatial.get("panel_id", "")),
			"path": [Schema.SPATIAL_KEY, spatial_index],
			"text": "Regiones del paño %s" % String(spatial.get("panel_id", "")),
			"detail": "",
		})
		var snapshots: Array = Array(spatial.get("snapshots", []))
		for snapshot_index in range(snapshots.size()):
			if typeof(snapshots[snapshot_index]) != TYPE_DICTIONARY:
				continue
			var snapshot: Dictionary = snapshots[snapshot_index]
			rows.append({
				"family": REGION_FAMILY,
				"depth": 1,
				"id": String(spatial.get("panel_id", "")),
				"path": [Schema.SPATIAL_KEY, spatial_index, snapshot_index],
				"text": "t = %s s" % str(snapshot.get("time_s", 0.0)),
				"detail": "",
			})
			var snapshot_leaves: Array = Array(snapshot.get("leaves", []))
			for leaf_index in range(snapshot_leaves.size()):
				if typeof(snapshot_leaves[leaf_index]) != TYPE_DICTIONARY:
					continue
				var leaf: Dictionary = snapshot_leaves[leaf_index]
				var regions: Array = Array(leaf.get("regions", []))
				for region_index in range(regions.size()):
					if typeof(regions[region_index]) != TYPE_DICTIONARY:
						continue
					var region: Dictionary = regions[region_index]
					rows.append({
						"family": REGION_FAMILY,
						"depth": 2,
						"id": String(region.get("id", "")),
						"path": [
							Schema.SPATIAL_KEY, spatial_index, snapshot_index,
							leaf_index, region_index,
						],
						"text": "Hoja %s · región %s" % [
							String(leaf.get("id", "")), String(region.get("id", ""))
						],
						"detail": "x = %s m, z = %s m, %s x %s m" % [
							str(region.get("x_m", 0.0)), str(region.get("z_m", 0.0)),
							str(region.get("width_m", 0.0)), str(region.get("height_m", 0.0)),
						],
					})
	return rows


## Pone -o quita- el perfil de una ranura. `versioned_id` vacio = sin perfil.
##
## Falla cerrado ante un perfil bloqueado, incompatible, desconocido o que exija
## el modo experimental sin confirmarlo, y NO deja la abertura a medias.
static func set_profile(
	opening_data: Dictionary, slot: String, profile_id: String, version: int,
	experimental_confirmed: bool
) -> Dictionary:
	var errors: Array[String] = []
	if not Schema.PROFILE_KEYS.has(slot):
		errors.append("ranura de perfil desconocida '%s'" % slot)
		return _failure(opening_data, errors)
	var draft: Dictionary = opening_data.duplicate(true)
	if profile_id.strip_edges().is_empty():
		draft.erase(slot)
		return _finish(draft, errors)
	var profile: Dictionary = Catalog.find(profile_id, version)
	if profile.is_empty():
		errors.append("el catálogo no publica '%s' en la versión %d" % [profile_id, version])
		return _failure(opening_data, errors)
	var described: Dictionary = Selection.describe(
		profile, opening_data, experimental_confirmed
	)
	if not bool(described["selectable"]):
		errors.append(String(described["disabled_reason"]))
		return _failure(opening_data, errors)
	if String(profile["category"]) != String(Schema.PROFILE_SLOT_CATEGORY[slot]):
		errors.append("el perfil '%s' no es de la categoría de esta ranura" % profile_id)
		return _failure(opening_data, errors)
	var block: Dictionary = Schema.build_profile_block(profile_id, version)
	if block.is_empty():
		errors.append("el perfil '%s' no puede producir configuración" % profile_id)
		return _failure(opening_data, errors)
	draft[slot] = block
	return _finish(draft, errors)


## Reemplaza la prescripcion de una familia entera. La valida el esquema, que
## delega en los modelos puros: aqui no hay ni una regla copiada.
static func set_prescription(
	opening_data: Dictionary, key: String, value: Array
) -> Dictionary:
	var errors: Array[String] = []
	if not Schema.PAYLOAD_KEYS.has(key):
		errors.append("familia de prescripción desconocida '%s'" % key)
		return _failure(opening_data, errors)
	var draft: Dictionary = opening_data.duplicate(true)
	if value.is_empty():
		draft.erase(key)
	else:
		draft[key] = value.duplicate(true)
	return _finish(draft, errors)


## Cambia el tipo de la abertura y trata la incompatibilidad de forma explicita.
##
## No borra nada en silencio: devuelve que perfiles dejarian de encajar. El
## editor decide si pregunta o si cancela; con `drop_incompatible` a cierto se
## quitan esos perfiles, y la prescripcion se conserva siempre.
static func change_type(
	opening_data: Dictionary, new_type: String, drop_incompatible: bool
) -> Dictionary:
	var draft: Dictionary = opening_data.duplicate(true)
	draft["type"] = new_type
	var conflicting: Array[String] = []
	for slot in Schema.PROFILE_KEYS:
		var block: Variant = draft.get(slot, null)
		if typeof(block) != TYPE_DICTIONARY or Dictionary(block).is_empty():
			continue
		var category: String = String(Schema.PROFILE_SLOT_CATEGORY[slot])
		if Catalog.category_applies_to(category, draft):
			continue
		conflicting.append(slot)
	if not conflicting.is_empty() and not drop_incompatible:
		return {
			"ok": false,
			"errors": ["cambiar a '%s' dejaría sin encaje: %s" % [
				new_type, ", ".join(conflicting)
			]],
			"opening": opening_data.duplicate(true),
			"conflicting_slots": conflicting,
			"needs_confirmation": true,
		}
	for slot in conflicting:
		draft.erase(slot)
	var result: Dictionary = _finish(draft, [] as Array[String])
	result["conflicting_slots"] = conflicting
	result["needs_confirmation"] = false
	return result


## Añade a la prescripcion lo que describe `request`.
##
## Construye el borrador y se lo da al esquema. Si el esquema -o, a traves de
## el, `ClosedDoorDeformationModel` o los dos modelos de vidrio- lo rechaza, la
## abertura vuelve intacta y el motivo viaja en `errors`. El editor no repite
## aqui ni una de esas reglas: un instante repetido, un area negativa, un paño
## fuera del hueco o dos paños solapados los caza quien ya sabia cazarlos.
static func add_entry(opening_data: Dictionary, request: Dictionary) -> Dictionary:
	var kind: int = int(request.get("entry_kind_index", 0))
	var identifier: String = String(request.get("id", "")).strip_edges()
	if identifier.is_empty():
		return _failure(opening_data, ["hace falta un identificador"] as Array[String])
	var draft: Dictionary = opening_data.duplicate(true)
	match kind:
		ENTRY_DEFORMATION_POINT:
			_add_deformation_point(draft, identifier, request)
		ENTRY_GLAZING_PANEL:
			_add_glazing_panel(draft, identifier, request)
		ENTRY_LEAF_EVENT:
			var event_error: String = _add_leaf_event(draft, identifier, request)
			if not event_error.is_empty():
				return _failure(opening_data, [event_error] as Array[String])
		ENTRY_SPATIAL_REGION:
			var region_error: String = _add_spatial_region(draft, identifier, request)
			if not region_error.is_empty():
				return _failure(opening_data, [region_error] as Array[String])
		_:
			return _failure(opening_data, ["tipo de entrada desconocido"] as Array[String])
	return _finish(draft, [] as Array[String])


## Un instante mas en una pista de deformacion. La pista se crea si no estaba;
## el punto se inserta en su sitio para que la historia siga creciendo en el
## tiempo, y si el instante ya existia lo rechaza el modelo puro.
static func _add_deformation_point(
	draft: Dictionary, identifier: String, request: Dictionary
) -> void:
	var tracks: Array = Array(draft.get(Schema.DEFORMATION_KEY, [])).duplicate(true)
	var location: String = _option(TRACK_LOCATIONS, int(request.get("location_index", 0)))
	var time_s: float = float(request.get("time_s", 0.0))
	var area_m2: float = float(request.get("additional_ela_m2", 0.0))
	var found: int = -1
	for index in range(tracks.size()):
		if typeof(tracks[index]) == TYPE_DICTIONARY \
				and String(Dictionary(tracks[index]).get("id", "")) == identifier:
			found = index
	if found < 0:
		tracks.append({
			"id": identifier,
			"location": location,
			"z_m": float(request.get("z_m", 0.0)),
			"points": [[time_s, area_m2]],
		})
	else:
		var track: Dictionary = tracks[found]
		var points: Array = Array(track.get("points", [])).duplicate(true)
		var at: int = points.size()
		for index in range(points.size()):
			if typeof(points[index]) == TYPE_ARRAY \
					and float(Array(points[index])[0]) > time_s:
				at = index
				break
		points.insert(at, [time_s, area_m2])
		track["points"] = points
		tracks[found] = track
	draft[Schema.DEFORMATION_KEY] = tracks


## Un paño nuevo, con sus hojas intactas en el instante cero y su entrada
## espacial vacia. Es el punto de partida valido mas pequeño que D3 acepta.
static func _add_glazing_panel(
	draft: Dictionary, identifier: String, request: Dictionary
) -> void:
	var leaf_count: int = maxi(1, int(request.get("leaf_count", 1)))
	var leaves: Array = []
	var spatial_leaves: Array = []
	for index in range(leaf_count):
		var leaf_id: String = "%s_leaf_%d" % [identifier, index]
		leaves.append({
			"id": leaf_id,
			"index": index,
			"events": [{"time_s": 0.0, "state": "INTACT", "fallout_fraction": 0.0}],
		})
		spatial_leaves.append({"id": leaf_id, "index": index, "regions": []})
	var panels: Array = Array(draft.get(Schema.PANELS_KEY, [])).duplicate(true)
	panels.append({
		"id": identifier,
		"host_x_m": float(request.get("x_m", 0.0)),
		"width_m": float(request.get("width_m", 0.0)),
		"height_m": float(request.get("height_m", 0.0)),
		"sill_z_m": float(request.get("z_m", 0.0)),
		"glass_type": _option(GLASS_TYPES, int(request.get("glass_index", 0))),
		"thickness_m": 0.004,
		"leaf_count": leaf_count,
		"leaf_spacing_m": 0.012 if leaf_count > 1 else 0.0,
		"frame_material": "sin declarar",
		"edge_protection_depth_m": 0.01,
		"leaves": leaves,
	})
	draft[Schema.PANELS_KEY] = panels
	var spatials: Array = Array(draft.get(Schema.SPATIAL_KEY, [])).duplicate(true)
	spatials.append({
		"panel_id": identifier,
		"snapshots": [{"time_s": 0.0, "leaves": spatial_leaves}],
	})
	draft[Schema.SPATIAL_KEY] = spatials


## Un estado prescrito mas en una hoja, insertado en su instante.
static func _add_leaf_event(
	draft: Dictionary, identifier: String, request: Dictionary
) -> String:
	var panels: Array = Array(draft.get(Schema.PANELS_KEY, [])).duplicate(true)
	var leaf_id: String = String(request.get("child_id", "")).strip_edges()
	var time_s: float = float(request.get("time_s", 0.0))
	var state: String = _option(GLAZING_STATES, int(request.get("state_index", 0)))
	var fraction: float = float(request.get("fallout_percent", 0.0)) / 100.0
	for panel_index in range(panels.size()):
		var panel: Dictionary = panels[panel_index]
		if String(panel.get("id", "")) != identifier:
			continue
		var leaves: Array = Array(panel.get("leaves", [])).duplicate(true)
		for leaf_index in range(leaves.size()):
			var leaf: Dictionary = leaves[leaf_index]
			if String(leaf.get("id", "")) != leaf_id:
				continue
			var events: Array = Array(leaf.get("events", [])).duplicate(true)
			var at: int = events.size()
			for index in range(events.size()):
				if float(Dictionary(events[index]).get("time_s", 0.0)) > time_s:
					at = index
					break
			events.insert(at, {
				"time_s": time_s, "state": state, "fallout_fraction": fraction,
			})
			leaf["events"] = events
			leaves[leaf_index] = leaf
			panel["leaves"] = leaves
			panels[panel_index] = panel
			draft[Schema.PANELS_KEY] = panels
			return ""
		return "el paño '%s' no tiene la hoja '%s'" % [identifier, leaf_id]
	return "no hay ningún paño '%s'" % identifier


## Una region desprendida mas. Si el instante no tenia instantanea espacial se
## crea copiando la anterior, para no perder lo que ya estaba desprendido.
static func _add_spatial_region(
	draft: Dictionary, identifier: String, request: Dictionary
) -> String:
	var spatials: Array = Array(draft.get(Schema.SPATIAL_KEY, [])).duplicate(true)
	var leaf_id: String = String(request.get("child_id", "")).strip_edges()
	var time_s: float = float(request.get("time_s", 0.0))
	for spatial_index in range(spatials.size()):
		var spatial: Dictionary = spatials[spatial_index]
		if String(spatial.get("panel_id", "")) != identifier:
			continue
		var snapshots: Array = Array(spatial.get("snapshots", [])).duplicate(true)
		var at: int = -1
		var insert_at: int = snapshots.size()
		for index in range(snapshots.size()):
			var snapshot_time: float = float(Dictionary(snapshots[index]).get("time_s", 0.0))
			if snapshot_time == time_s:
				at = index
			elif snapshot_time > time_s and insert_at == snapshots.size():
				insert_at = index
		if at < 0:
			var source: Dictionary = {}
			if insert_at > 0:
				source = snapshots[insert_at - 1]
			elif not snapshots.is_empty():
				source = snapshots[0]
			var copied: Array = Array(source.get("leaves", [])).duplicate(true)
			snapshots.insert(insert_at, {"time_s": time_s, "leaves": copied})
			at = insert_at
		var snapshot: Dictionary = snapshots[at]
		var leaves: Array = Array(snapshot.get("leaves", [])).duplicate(true)
		for leaf_index in range(leaves.size()):
			var leaf: Dictionary = leaves[leaf_index]
			if String(leaf.get("id", "")) != leaf_id:
				continue
			var regions: Array = Array(leaf.get("regions", [])).duplicate(true)
			regions.append({
				"id": "r%d" % regions.size(),
				"x_m": float(request.get("x_m", 0.0)),
				"z_m": float(request.get("z_m", 0.0)),
				"width_m": float(request.get("width_m", 0.0)),
				"height_m": float(request.get("height_m", 0.0)),
			})
			leaf["regions"] = regions
			leaves[leaf_index] = leaf
			snapshot["leaves"] = leaves
			snapshots[at] = snapshot
			spatial["snapshots"] = snapshots
			spatials[spatial_index] = spatial
			draft[Schema.SPATIAL_KEY] = spatials
			return ""
		return "la instantánea de '%s' no tiene la hoja '%s'" % [identifier, leaf_id]
	return "no hay entrada espacial para el paño '%s'" % identifier


## Quita de la prescripcion lo que señale `path`, la ruta que lleva cada fila
## del listado. Quitar un paño se lleva tambien su entrada espacial: dejar una
## sin la otra es justo lo que D3 rechaza.
static func remove_entry(opening_data: Dictionary, path: Array) -> Dictionary:
	if path.is_empty():
		return _failure(opening_data, ["no hay nada seleccionado"] as Array[String])
	var draft: Dictionary = opening_data.duplicate(true)
	var key: String = String(path[0])
	if not Schema.PAYLOAD_KEYS.has(key):
		return _failure(opening_data, ["ruta desconocida"] as Array[String])
	var root: Array = Array(draft.get(key, [])).duplicate(true)
	if path.size() < 2 or int(path[1]) >= root.size():
		return _failure(opening_data, ["la selección ya no existe"] as Array[String])
	var removed_panel_id: String = ""
	if path.size() == 2:
		if key == Schema.PANELS_KEY:
			removed_panel_id = String(Dictionary(root[int(path[1])]).get("id", ""))
		root.remove_at(int(path[1]))
	else:
		root[int(path[1])] = _remove_nested(root[int(path[1])], key, path)
	if root.is_empty():
		draft.erase(key)
	else:
		draft[key] = root
	if not removed_panel_id.is_empty():
		var spatials: Array = Array(draft.get(Schema.SPATIAL_KEY, [])).duplicate(true)
		var kept: Array = []
		for entry in spatials:
			if String(Dictionary(entry).get("panel_id", "")) != removed_panel_id:
				kept.append(entry)
		if kept.is_empty():
			draft.erase(Schema.SPATIAL_KEY)
		else:
			draft[Schema.SPATIAL_KEY] = kept
	return _finish(draft, [] as Array[String])


static func _remove_nested(container: Variant, key: String, path: Array) -> Variant:
	var node: Dictionary = container
	if key == Schema.DEFORMATION_KEY:
		var points: Array = Array(node.get("points", [])).duplicate(true)
		if int(path[2]) < points.size():
			points.remove_at(int(path[2]))
		node["points"] = points
		return node
	if key == Schema.PANELS_KEY:
		var leaves: Array = Array(node.get("leaves", [])).duplicate(true)
		if int(path[2]) >= leaves.size():
			return node
		if path.size() == 3:
			leaves.remove_at(int(path[2]))
		else:
			var leaf: Dictionary = leaves[int(path[2])]
			var events: Array = Array(leaf.get("events", [])).duplicate(true)
			if int(path[3]) < events.size():
				events.remove_at(int(path[3]))
			leaf["events"] = events
			leaves[int(path[2])] = leaf
		node["leaves"] = leaves
		return node
	var snapshots: Array = Array(node.get("snapshots", [])).duplicate(true)
	if int(path[2]) >= snapshots.size():
		return node
	if path.size() == 3:
		snapshots.remove_at(int(path[2]))
	else:
		var snapshot: Dictionary = snapshots[int(path[2])]
		var snapshot_leaves: Array = Array(snapshot.get("leaves", [])).duplicate(true)
		if int(path[3]) < snapshot_leaves.size():
			var leaf: Dictionary = snapshot_leaves[int(path[3])]
			var regions: Array = Array(leaf.get("regions", [])).duplicate(true)
			if int(path[4]) < regions.size():
				regions.remove_at(int(path[4]))
			leaf["regions"] = regions
			snapshot_leaves[int(path[3])] = leaf
		snapshot["leaves"] = snapshot_leaves
		snapshots[int(path[2])] = snapshot
	node["snapshots"] = snapshots
	return node


static func _option(names: Array[String], index: int) -> String:
	if index < 0 or index >= names.size():
		return names[0]
	return names[index]


## Normaliza y valida el borrador. Si el esquema lo rechaza, no se aplica nada.
static func _finish(draft: Dictionary, errors: Array[String]) -> Dictionary:
	Schema.normalize(draft)
	errors.append_array(Schema.validate(draft, 0))
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "opening": {}}
	return {"ok": true, "errors": errors, "opening": draft}


static func _failure(opening_data: Dictionary, errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors, "opening": opening_data.duplicate(true)}
