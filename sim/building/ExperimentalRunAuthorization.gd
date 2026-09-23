extends RefCounted

## F2.2D4B2B: contrato de AUTORIZACION de una ejecucion experimental.
##
## Este fichero es el unico propietario de la segunda de las tres decisiones que
## D4B mantiene separadas:
##
##   1. **perfil configurado en una abertura** -> `PrescribedOpeningPhysicsSchema`
##      y `OpeningPhysicsEditor`. Es un DATO. No enciende nada.
##   2. **autorizacion de UNA ejecucion experimental concreta** -> este fichero.
##      Es un consentimiento explicito, por escenario y por familia de fisica.
##   3. **aptitud para activacion normal del producto** -> `product_activation`
##      en el catalogo. Sigue siendo `false` en los quince perfiles, y D4B2B
##      NO la toca.
##
## La segunda no implica la tercera. Autorizar una corrida experimental no
## convierte ningun perfil en apto para una vivienda, y este modulo se niega a
## escribirlo asi: el informe que produce dice, con esas palabras, que la
## corrida no es una validacion residencial.
##
## ## Lo que este modulo NO hace, y no debe hacer nunca
##
##   - no calcula caudal, presion, area de flujo, viento ni transporte;
##   - no reimplementa la ley de rendijas de D1, la de orificio de R3, la
##     geometria multicapa de D3 ni el aplicador atomico;
##   - no valida la persistencia de un perfil: eso es
##     `PrescribedOpeningPhysicsSchema`, y aqui se le DELEGA entera;
##   - no decide compatibilidad por su cuenta: se la pregunta al catalogo;
##   - no cambia `product_activation`, ni un escenario distribuido, ni un
##     valor por defecto;
##   - no predice cuando se deforma una puerta ni cuando cae un vidrio: D2 y D3
##     siguen siendo historias PRESCRITAS.
##
## ## Donde vive la autorizacion
##
## En el escenario, en una unica clave de primer nivel,
## `experimental_physics_authorization`, que viaja en la plantilla runtime hasta
## `BuildingModel` y de ahi a `SimulationEngine`. Vive ahi y no en un ajuste de
## la aplicacion por tres razones:
##
##   - se autoriza UN escenario, no la instalacion: abrir otro plano no hereda
##     el permiso;
##   - viaja con el fichero, asi que el informe de ejecucion puede decir que se
##     autorizo exactamente, y reproducir la corrida es reabrir el mismo
##     fichero;
##   - se revoca borrando la clave, que es una operacion que el editor puede
##     deshacer como cualquier otra edicion.
##
## ## Como se revoca
##
## Tres caminos, y los tres devuelven el escenario a OFF entero:
##
##   1. **explicito**: el editor quita la autorizacion (`revoke`), la clave
##      desaparece y el escenario vuelve a ser byte a byte el de antes;
##   2. **por caducidad**: la autorizacion lleva la huella SHA-256 de lo que se
##      autorizo. Si despues se cambia un perfil, una prescripcion o una
##      abertura participante, la huella deja de coincidir y la autorizacion se
##      RECHAZA. No se re-autoriza sola y no se activa una fisica distinta de la
##      que se leyo;
##   3. **por invalidez**: un perfil bloqueado, desconocido, incompatible, con
##      version no publicada o con la copia congelada alterada impide la
##      ejecucion experimental entera.
##
## Un rechazo no es un apagado silencioso: `resolve()` devuelve los errores,
## `ScenarioSerializer.validate_scenario()` los enseña antes de lanzar y el
## motor se niega a simular en vez de correr a medias.
##
## ## Que NO basta para activar fisica
##
## Cargar un escenario, seleccionar un perfil en el desplegable, guardar el
## fichero o previsualizarlo en el editor. Ninguna de esas cuatro cosas escribe
## esta clave. Solo la escribe `grant()`, y solo con las cuatro confirmaciones
## textuales completas.
##
## ## Reproducibilidad
##
## La copia congelada del escenario MANDA sobre el catalogo. Esa regla es de
## D4B1 y aqui no se relaja: si el catalogo publicase manana otra version, el
## escenario ya guardado sigue resolviendo su par `(profile_id, version)`
## exacto, y si ese par dejase de existir la carga falla en vez de recalibrar.
## La huella de la autorizacion se calcula sobre la copia congelada del
## escenario, nunca sobre el catalogo vivo.

const Catalog = preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")
const Schema = preload("res://sim/building/PrescribedOpeningPhysicsSchema.gd")
## Solo por su constante de dominio de presion. No se usa ni una funcion de
## caudal de este adaptador: el limite se ENSEÑA en el consentimiento, no se
## aplica aqui.
const LeakageAdapter = preload("res://sim/core/ClosedDoorLeakageNetworkAdapter.gd")

## Clave de primer nivel del escenario. Ausencia = ninguna autorizacion = OFF.
const AUTHORIZATION_KEY: String = "experimental_physics_authorization"
## Version del contrato de autorizacion. Una version desconocida se rechaza; no
## se degrada en silencio, igual que en el esquema de la fisica prescrita.
const AUTHORIZATION_VERSION: int = 1

const VERSION_FIELD: String = "authorization_version"
const FAMILIES_FIELD: String = "families"
const ACKNOWLEDGED_FIELD: String = "acknowledged"
const EXPERIMENTAL_FIELD: String = "experimental_profiles_confirmed"
const DIGEST_FIELD: String = "scenario_digest"
const FIELDS: Array[String] = [
	VERSION_FIELD, FAMILIES_FIELD, ACKNOWLEDGED_FIELD,
	EXPERIMENTAL_FIELD, DIGEST_FIELD,
]

# ------------------------------------------------------------
# Familias de fisica
# ------------------------------------------------------------

## Las cuatro familias, en orden estable. Son exactamente las cuatro que ya
## tenian interruptor: D1, R3, D2 y D3. No se inventa ninguna.
const FAMILY_DOOR_LEAKAGE: String = "door_leakage"
const FAMILY_FRAME_LEAKAGE: String = "frame_leakage"
const FAMILY_DEFORMATION: String = "deformation"
const FAMILY_GLAZING: String = "glazing"
const FAMILIES: Array[String] = [
	FAMILY_DOOR_LEAKAGE, FAMILY_FRAME_LEAKAGE, FAMILY_DEFORMATION, FAMILY_GLAZING,
]

## Interruptor de `SimulationEngine` que gobierna cada familia. Este es el unico
## sitio donde se escribe esa correspondencia; el motor la lee de aqui.
const FAMILY_SWITCH: Dictionary = {
	FAMILY_DOOR_LEAKAGE: "closed_door_leakage_enabled",
	FAMILY_FRAME_LEAKAGE: "exterior_envelope_leakage_enabled",
	FAMILY_DEFORMATION: "closed_door_deformation_enabled",
	FAMILY_GLAZING: "glazing_fallout_enabled",
}

## Dependencia comun de las cuatro. No es una eleccion de este modulo: el motor
## ya rechazaba las cuatro sin ella desde D1, D2, D3 y R3, y aqui se exige ANTES
## de simular en vez de descubrirse en el primer paso.
const REQUIRED_DEPENDENCY: String = "pressure_network_solver_enabled"

## Ranura de perfil del esquema que justifica cada familia.
const FAMILY_PROFILE_SLOT: Dictionary = {
	FAMILY_DOOR_LEAKAGE: Schema.LEAKAGE_PROFILE_KEY,
	FAMILY_FRAME_LEAKAGE: Schema.FRAME_PROFILE_KEY,
	FAMILY_DEFORMATION: Schema.DEFORMATION_PROFILE_KEY,
	FAMILY_GLAZING: Schema.GLAZING_PROFILE_KEY,
}

## Claves de la abertura que cada familia CONSUME. Entran en la huella porque
## cambiar una cambia la fisica que se autorizo.
const FAMILY_PAYLOAD_KEYS: Dictionary = {
	FAMILY_DOOR_LEAKAGE: ["leakage_class", "leakage_area_override_m2"],
	FAMILY_FRAME_LEAKAGE: [],
	FAMILY_DEFORMATION: [Schema.DEFORMATION_KEY],
	FAMILY_GLAZING: [Schema.PANELS_KEY, Schema.SPATIAL_KEY],
}

## Las dos familias que son PRESCRIPCION: el escenario dice cuando pasa, el
## motor no lo predice. Se nombran en el consentimiento con esas palabras.
const PRESCRIBED_FAMILIES: Array[String] = [FAMILY_DEFORMATION, FAMILY_GLAZING]

## Nombre legible de cada familia, para el consentimiento y el informe.
const FAMILY_TITLE: Dictionary = {
	FAMILY_DOOR_LEAKAGE: "D1 · fuga fría de puerta cerrada",
	FAMILY_FRAME_LEAKAGE: "R3 · fuga de marco de ventana exterior",
	FAMILY_DEFORMATION: "D2 · deformación prescrita de puerta cerrada",
	FAMILY_GLAZING: "D3 · desprendimiento prescrito de vidrio",
}

# ------------------------------------------------------------
# Consentimiento
# ------------------------------------------------------------

## Las cuatro frases que el usuario tiene que haber visto y confirmado. Se
## guardan VERBATIM en el escenario: si mañana se cambia el texto, una
## autorizacion antigua deja de coincidir y se rechaza, que es lo que debe pasar
## cuando lo que se consintio ya no es lo que se dice.
const ACK_EXPERIMENTAL: String = \
	"Simulación experimental; parámetros no validados para una vivienda."
const ACK_FAMILIES: String = \
	"He leído las familias de física que se activan y sus valores efectivos congelados."
const ACK_LIMITS: String = \
	"He leído las limitaciones aplicables, incluido el dominio de presión del ensayo."
const ACK_PRESCRIBED: String = \
	"La deformación y el desprendimiento de vidrio son historias prescritas: " \
	+ "el motor no predice cuándo ocurren."
const REQUIRED_ACKNOWLEDGEMENTS: Array[String] = [
	ACK_EXPERIMENTAL, ACK_FAMILIES, ACK_LIMITS, ACK_PRESCRIBED,
]

## Lo que el informe de ejecucion dice de si mismo. Una corrida experimental no
## es una validacion, y menos aun una validacion residencial.
const NOT_A_VALIDATION_TEXT: String = \
	"Ejecución experimental autorizada a mano. No es una validación física ni " \
	+ "residencial: ningún perfil está declarado apto para activación de producto."

## El limite de presion del ensayo de rendija, tal cual lo publica el adaptador.
## Aqui solo se enseña.
const PRESSURE_DOMAIN_MAX_PA: float = LeakageAdapter.PRESSURE_DOMAIN_MAX_PA


# ------------------------------------------------------------
# Lectura
# ------------------------------------------------------------

## ¿Este escenario trae una autorizacion? Un bloque vacio es exactamente "no".
static func declares(scenario_data: Dictionary) -> bool:
	var block: Variant = scenario_data.get(AUTHORIZATION_KEY, null)
	return typeof(block) == TYPE_DICTIONARY and not Dictionary(block).is_empty()


## Aberturas que justifican una familia, por indice ascendente.
##
## Participa la abertura que declara el perfil de esa familia o los datos que esa
## familia consume. Una familia sin ninguna abertura participante no se puede
## autorizar: encenderia fisica sin nada detras.
static func participants(scenario_data: Dictionary, family: String) -> Array[int]:
	var out: Array[int] = []
	if not FAMILIES.has(family):
		return out
	var openings: Array = Array(scenario_data.get("openings_data", []))
	for index in range(openings.size()):
		if typeof(openings[index]) != TYPE_DICTIONARY:
			continue
		if _participates(Dictionary(openings[index]), family):
			out.append(index)
	return out


static func _participates(opening: Dictionary, family: String) -> bool:
	return not _family_fields(opening, family).is_empty()


## Lo que una abertura aporta a una familia, ya descodificado y sin defaults.
##
## Es la MISMA funcion que decide si una abertura participa y la que alimenta la
## huella, a proposito: lo que justifica autorizar una familia es exactamente lo
## que queda congelado en el permiso, y no puede haber un tercer criterio.
##
## Dos cosas se dejan fuera, y las dos por la misma razon -que el normalizador
## del escenario las rellena sola, de modo que incluirlas haria que la huella
## dependiera de si el escenario se ha normalizado o no-:
##
##   - una clave ausente;
##   - un valor por defecto que no configura nada: una lista vacia y la clase de
##     fuga `none`, que es la que trae toda puerta recien dibujada.
static func _family_fields(opening: Dictionary, family: String) -> Dictionary:
	var fields: Dictionary = {}
	if not FAMILIES.has(family):
		return fields
	# Se descodifica primero: el fichero no distingue `2` de `2.0`, y una huella
	# que cambiase al pasar por el fichero no serviria de nada.
	var decoded: Dictionary = opening.duplicate(true)
	Schema.normalize(decoded)
	var slot: String = String(FAMILY_PROFILE_SLOT[family])
	var profile: Variant = decoded.get(slot, null)
	if typeof(profile) == TYPE_DICTIONARY and not Dictionary(profile).is_empty():
		fields[slot] = profile
	for raw_key in Array(FAMILY_PAYLOAD_KEYS[family]):
		var key: String = String(raw_key)
		if not decoded.has(key):
			continue
		var value: Variant = decoded[key]
		if typeof(value) == TYPE_ARRAY:
			if not Array(value).is_empty():
				fields[key] = value
		elif key == "leakage_class":
			if String(value).strip_edges().to_lower() != "none":
				fields[key] = String(value).strip_edges().to_lower()
		else:
			fields[key] = value
	return fields


## Familias que este escenario PODRIA autorizar, en el orden de `FAMILIES`.
static func available_families(scenario_data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for family in FAMILIES:
		if not participants(scenario_data, String(family)).is_empty():
			out.append(String(family))
	return out


# ------------------------------------------------------------
# Huella
# ------------------------------------------------------------

## Huella SHA-256 de EXACTAMENTE lo que se autoriza.
##
## Entra la copia congelada del escenario -perfil, version, parametros efectivos
## y la prescripcion que cada familia consume-, nunca el catalogo vivo. Asi una
## autorizacion sigue siendo valida mientras el escenario no cambie, y deja de
## serlo en cuanto cambia, sin que nadie tenga que acordarse de revocarla.
static func digest(scenario_data: Dictionary, families: Array) -> String:
	var pieces: PackedStringArray = PackedStringArray()
	pieces.append("v%d" % AUTHORIZATION_VERSION)
	var openings: Array = Array(scenario_data.get("openings_data", []))
	for family in FAMILIES:
		var name: String = String(family)
		if not families.has(name):
			continue
		pieces.append("family=" + name)
		for index in participants(scenario_data, name):
			pieces.append("  %d=%s" % [
				index, _canonical(_family_fields(Dictionary(openings[index]), name))
			])
	return "\n".join(pieces).sha256_text()


## Texto canonico de un valor de escenario: claves ordenadas y numeros escritos
## siempre igual. `JSON.stringify` conserva el orden de insercion, que depende
## de como se leyo el fichero, asi que no sirve para una huella.
static func _canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = Dictionary(value).keys()
			var names: Array[String] = []
			for key in keys:
				names.append(String(key))
			names.sort()
			var parts: PackedStringArray = PackedStringArray()
			for name in names:
				parts.append("%s:%s" % [name, _canonical(Dictionary(value)[name])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var items: PackedStringArray = PackedStringArray()
			for item in Array(value):
				items.append(_canonical(item))
			return "[" + ",".join(items) + "]"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return "i%d" % int(value)
		TYPE_FLOAT:
			# El mismo texto con el que el fichero guarda ese numero. No es una
			# aproximacion: el contrato de D4A ya RECHAZA cualquier valor que
			# `JSON.stringify` no represente exacto, asi que para un dato de
			# escenario este texto es el numero.
			return "f" + JSON.stringify(float(value))
		TYPE_NIL:
			return "null"
		_:
			return "s" + String(value)


# ------------------------------------------------------------
# Escritura: la unica forma de autorizar
# ------------------------------------------------------------

## Construye el bloque de autorizacion. Devuelve `{ok, errors, authorization}`.
##
## Es la UNICA funcion que produce una autorizacion valida, y exige las cuatro
## confirmaciones textuales completas. Guardar, cargar, seleccionar o
## previsualizar un perfil no pasa por aqui.
static func grant(
	scenario_data: Dictionary, families: Array, acknowledged: Array,
	experimental_confirmed: bool
) -> Dictionary:
	var errors: Array[String] = []
	var requested: Array[String] = []
	for family in FAMILIES:
		if families.has(String(family)):
			requested.append(String(family))
	for raw in families:
		if not FAMILIES.has(String(raw)):
			errors.append("familia desconocida '%s'" % String(raw))
	if requested.is_empty():
		errors.append("no se ha pedido ninguna familia de física")
	for ack in REQUIRED_ACKNOWLEDGEMENTS:
		if not acknowledged.has(String(ack)):
			errors.append("falta la confirmación: %s" % String(ack))
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "authorization": {}}
	var authorization: Dictionary = {
		VERSION_FIELD: AUTHORIZATION_VERSION,
		FAMILIES_FIELD: requested,
		ACKNOWLEDGED_FIELD: REQUIRED_ACKNOWLEDGEMENTS.duplicate(),
		EXPERIMENTAL_FIELD: experimental_confirmed,
		DIGEST_FIELD: digest(scenario_data, requested),
	}
	# Se comprueba contra el escenario ANTES de devolverlo: una autorizacion que
	# no resolveria no se llega a escribir.
	var candidate: Dictionary = scenario_data.duplicate(true)
	candidate[AUTHORIZATION_KEY] = authorization
	var verdict: Dictionary = resolve(candidate)
	if not bool(verdict["authorized"]):
		return {"ok": false, "errors": verdict["errors"], "authorization": {}}
	return {"ok": true, "errors": [], "authorization": authorization}


## Quita la autorizacion. El escenario vuelve a OFF entero y, si no tenia
## ninguna, no gana ni una clave.
static func revoke(scenario_data: Dictionary) -> void:
	scenario_data.erase(AUTHORIZATION_KEY)


## El bloque con los tipos que el fichero no distingue ya restituidos. Devuelve
## siempre una copia: resolver no modifica el escenario.
static func _decoded_block(block: Dictionary) -> Dictionary:
	var decoded: Dictionary = block.duplicate(true)
	if not decoded.has(VERSION_FIELD):
		return decoded
	var version: Variant = decoded[VERSION_FIELD]
	if typeof(version) != TYPE_FLOAT or not is_finite(float(version)):
		return decoded
	if float(version) == floorf(float(version)):
		decoded[VERSION_FIELD] = int(version)
	return decoded


## Normaliza el bloque en sitio: restituye los tipos que el fichero no
## distingue y borra un bloque vacio. No repara nada: lo malformado sobrevive
## intacto y lo rechaza `validate()`.
static func normalize(scenario_data: Dictionary) -> void:
	if not scenario_data.has(AUTHORIZATION_KEY):
		return
	var raw: Variant = scenario_data[AUTHORIZATION_KEY]
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var block: Dictionary = Dictionary(raw)
	if block.is_empty():
		scenario_data.erase(AUTHORIZATION_KEY)
		return
	# `JSON.parse_string` devuelve todo numero como float: un `1` vuelve `1.0`.
	if block.has(VERSION_FIELD):
		var version: Variant = block[VERSION_FIELD]
		if typeof(version) == TYPE_FLOAT and float(version) == float(int(version)):
			block[VERSION_FIELD] = int(version)
	if block.has(FAMILIES_FIELD) and typeof(block[FAMILIES_FIELD]) == TYPE_ARRAY:
		var ordered: Array[String] = []
		for family in FAMILIES:
			if Array(block[FAMILIES_FIELD]).has(String(family)):
				ordered.append(String(family))
		# Una familia desconocida se CONSERVA para que `validate()` la nombre.
		for raw_family in Array(block[FAMILIES_FIELD]):
			if not FAMILIES.has(String(raw_family)):
				ordered.append(String(raw_family))
		block[FAMILIES_FIELD] = ordered
	scenario_data[AUTHORIZATION_KEY] = block


# ------------------------------------------------------------
# Resolucion
# ------------------------------------------------------------

## Resuelve la autorizacion de un escenario. Es la funcion que decide si esta
## corrida enciende fisica, y la unica.
##
## Devuelve, siempre con las mismas claves:
##
##   declares   -> el escenario trae bloque de autorizacion;
##   authorized -> se puede ejecutar de forma experimental;
##   errors     -> por que no, en texto, en orden determinista;
##   families   -> familias autorizadas;
##   switches   -> interruptores a encender, incluida la dependencia de red;
##   provenance -> perfil, version, parametros efectivos, dominio y advertencias
##                 de cada abertura participante;
##   limits     -> las limitaciones que se enseñaron en el consentimiento.
static func resolve(scenario_data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var families: Array[String] = []
	var provenance: Array[Dictionary] = []
	var limits: Array[String] = []
	var prescribed: Array[String] = []
	var result: Dictionary = {
		"declares": false,
		"authorized": false,
		"errors": errors,
		"families": families,
		"switches": {},
		"provenance": provenance,
		"limits": limits,
		"prescribed_families": prescribed,
		"digest": "",
	}
	if not declares(scenario_data):
		return result
	result["declares"] = true
	var raw: Variant = scenario_data[AUTHORIZATION_KEY]
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s debe ser un diccionario" % AUTHORIZATION_KEY)
		return result
	# Se descodifica el formato antes de mirarlo: `JSON.parse_string` devuelve
	# TODO numero como float, asi que la version vuelve del fichero como `1.0`.
	# Esto no repara un bloque malformado -un `1.5` se deja intacto y se
	# rechaza-, solo deshace lo que el fichero no sabe distinguir. Sin esto, una
	# autorizacion valida dejaria de resolver al pasar por la plantilla runtime,
	# que es justo el camino real.
	var block: Dictionary = _decoded_block(Dictionary(raw))
	for field in FIELDS:
		if not block.has(String(field)):
			errors.append("%s: falta '%s'" % [AUTHORIZATION_KEY, String(field)])
	for key in block.keys():
		if not FIELDS.has(String(key)):
			errors.append("%s: clave desconocida '%s'" % [AUTHORIZATION_KEY, String(key)])
	if not errors.is_empty():
		return result

	if typeof(block[VERSION_FIELD]) != TYPE_INT \
			or int(block[VERSION_FIELD]) != AUTHORIZATION_VERSION:
		errors.append("%s: versión %s no soportada (se admite %d)" % [
			AUTHORIZATION_KEY, str(block[VERSION_FIELD]), AUTHORIZATION_VERSION
		])
		return result
	if typeof(block[EXPERIMENTAL_FIELD]) != TYPE_BOOL:
		errors.append("%s: '%s' debe ser booleano" % [AUTHORIZATION_KEY, EXPERIMENTAL_FIELD])
		return result
	if typeof(block[ACKNOWLEDGED_FIELD]) != TYPE_ARRAY:
		errors.append("%s: '%s' debe ser una lista" % [AUTHORIZATION_KEY, ACKNOWLEDGED_FIELD])
		return result
	for ack in REQUIRED_ACKNOWLEDGEMENTS:
		if not Array(block[ACKNOWLEDGED_FIELD]).has(String(ack)):
			errors.append("%s: falta la confirmación «%s»" % [AUTHORIZATION_KEY, String(ack)])
	if typeof(block[FAMILIES_FIELD]) != TYPE_ARRAY:
		errors.append("%s: '%s' debe ser una lista" % [AUTHORIZATION_KEY, FAMILIES_FIELD])
		return result

	var requested: Array[String] = []
	for raw_family in Array(block[FAMILIES_FIELD]):
		var family: String = String(raw_family)
		if not FAMILIES.has(family):
			errors.append("%s: familia desconocida '%s'" % [AUTHORIZATION_KEY, family])
			continue
		if requested.has(family):
			errors.append("%s: familia repetida '%s'" % [AUTHORIZATION_KEY, family])
			continue
		requested.append(family)
	if requested.is_empty() and errors.is_empty():
		errors.append("%s: no autoriza ninguna familia" % AUTHORIZATION_KEY)
	if not errors.is_empty():
		return result

	# La huella se compara ANTES de mirar los perfiles: si lo autorizado ya no es
	# lo que hay en el escenario, no hay nada que resolver.
	var expected: String = digest(scenario_data, requested)
	if String(block[DIGEST_FIELD]) != expected:
		errors.append(
			"%s: la huella no coincide con el escenario. " % AUTHORIZATION_KEY
			+ "La configuración cambió después de autorizarla, así que la "
			+ "autorización queda revocada y hay que volver a concederla."
		)
		return result
	result["digest"] = expected

	var openings: Array = Array(scenario_data.get("openings_data", []))
	var needs_experimental: bool = false
	for family in requested:
		var indices: Array[int] = participants(scenario_data, family)
		if indices.is_empty():
			errors.append(
				"%s: la familia '%s' no tiene ninguna abertura que la justifique"
				% [AUTHORIZATION_KEY, family]
			)
			continue
		for index in indices:
			var opening: Dictionary = Dictionary(openings[index])
			# La validez del perfil NO se reimplementa: la pone el esquema, que
			# ya rechaza desconocido, version no publicada, categoria que no
			# encaja, bloqueado, sin parametros y copia congelada alterada.
			for message in Schema.validate(opening, index):
				if not errors.has(String(message)):
					errors.append(String(message))
			var entry: Dictionary = _provenance_entry(opening, index, family)
			if entry.is_empty():
				continue
			if String(entry["evidence"]) == Catalog.EVIDENCE_RESEARCH_ONLY:
				needs_experimental = true
			provenance.append(entry)
			for warning in Array(entry["warnings"]):
				var text: String = "%s · %s" % [String(entry["versioned_id"]), String(warning)]
				if not limits.has(text):
					limits.append(text)
	if not errors.is_empty():
		return result

	if needs_experimental and not bool(block[EXPERIMENTAL_FIELD]):
		errors.append(
			"%s: hay perfiles 'research_only' y falta la confirmación experimental"
			% AUTHORIZATION_KEY
		)
		return result

	for family in requested:
		if PRESCRIBED_FAMILIES.has(family):
			prescribed.append(family)
	limits.append(
		"Dominio de presión de la ley de rendija: %s Pa. Fuera de él el caudal se "
		% str(PRESSURE_DOMAIN_MAX_PA)
		+ "marca pero no se recorta."
	)

	var switches: Dictionary = {REQUIRED_DEPENDENCY: true}
	for family in requested:
		switches[String(FAMILY_SWITCH[family])] = true
	result["families"] = requested
	result["switches"] = switches
	result["authorized"] = true
	return result


static func _provenance_entry(opening: Dictionary, index: int, family: String) -> Dictionary:
	var slot: String = String(FAMILY_PROFILE_SLOT[family])
	var raw: Variant = opening.get(slot, null)
	if typeof(raw) != TYPE_DICTIONARY or Dictionary(raw).is_empty():
		# Una familia puede participar solo con su prescripcion, sin perfil: D1
		# con una clase de fuga, D2 con sus pistas. Se deja escrito.
		return {
			"family": family,
			"family_title": String(FAMILY_TITLE[family]),
			"opening_index": index,
			"opening_id": String(opening.get("id", "")),
			"profile_id": "",
			"profile_version": 0,
			"versioned_id": "",
			"evidence": "",
			"product_activation": false,
			"effective": {},
			"units": {},
			"domain": {},
			"warnings": PackedStringArray(),
			"prescribed": PRESCRIBED_FAMILIES.has(family),
		}
	var block: Dictionary = Dictionary(raw)
	var profile_id: String = String(block.get(Schema.PROFILE_ID_KEY, ""))
	var version: int = int(block.get(Schema.PROFILE_VERSION_KEY, 0))
	var profile: Dictionary = Catalog.find(profile_id, version)
	if profile.is_empty():
		return {}
	var effective: Dictionary = {}
	if typeof(block.get(Schema.PROFILE_EFFECTIVE_KEY, null)) == TYPE_DICTIONARY:
		effective = Dictionary(block[Schema.PROFILE_EFFECTIVE_KEY]).duplicate(true)
	var warnings: Array[String] = []
	for warning in Array(profile.get("warnings", [])):
		warnings.append(String(warning))
	return {
		"family": family,
		"family_title": String(FAMILY_TITLE[family]),
		"opening_index": index,
		"opening_id": String(opening.get("id", "")),
		"profile_id": profile_id,
		"profile_version": version,
		"versioned_id": Catalog.versioned_id(profile_id, version),
		"evidence": String(profile["evidence"]),
		"product_activation": bool(profile["product_activation"]),
		"effective": effective,
		"units": Dictionary(profile.get("units", {})).duplicate(true),
		"domain": Dictionary(profile.get("domain", {})).duplicate(true),
		"warnings": warnings,
		"prescribed": PRESCRIBED_FAMILIES.has(family),
	}


## Errores de la autorizacion de este escenario, ya en el formato que usa
## `ScenarioSerializer.validate_scenario()`. Sin bloque, lista vacia.
static func validate(scenario_data: Dictionary) -> Array[String]:
	var empty: Array[String] = []
	if not declares(scenario_data):
		return empty
	var verdict: Dictionary = resolve(scenario_data)
	for message in Array(verdict["errors"]):
		empty.append(String(message))
	return empty


# ------------------------------------------------------------
# Consentimiento e informe
# ------------------------------------------------------------

## Lo que hay que enseñar ANTES de ejecutar, para unas familias pedidas.
##
## No decide nada: describe. El editor lo pinta y el usuario confirma.
static func consent_request(scenario_data: Dictionary, families: Array) -> Dictionary:
	var requested: Array[String] = []
	for family in FAMILIES:
		if families.has(String(family)):
			requested.append(String(family))
	var candidate: Dictionary = scenario_data.duplicate(true)
	candidate[AUTHORIZATION_KEY] = {
		VERSION_FIELD: AUTHORIZATION_VERSION,
		FAMILIES_FIELD: requested,
		ACKNOWLEDGED_FIELD: REQUIRED_ACKNOWLEDGEMENTS.duplicate(),
		EXPERIMENTAL_FIELD: true,
		DIGEST_FIELD: digest(candidate, requested),
	}
	var verdict: Dictionary = resolve(candidate)
	var blocks: Array[Dictionary] = []
	for family in requested:
		var entries: Array[Dictionary] = []
		for raw_entry in Array(verdict["provenance"]):
			var entry: Dictionary = raw_entry
			if String(entry["family"]) == family:
				entries.append(entry)
		blocks.append({
			"family": family,
			"title": String(FAMILY_TITLE[family]),
			"switch": String(FAMILY_SWITCH[family]),
			"prescribed": PRESCRIBED_FAMILIES.has(family),
			"openings": entries,
		})
	return {
		"families": blocks,
		"dependency": REQUIRED_DEPENDENCY,
		"acknowledgements": REQUIRED_ACKNOWLEDGEMENTS.duplicate(),
		"limits": verdict["limits"],
		"errors": verdict["errors"],
		"requires_experimental": _requires_experimental(verdict),
		"pressure_domain_max_pa": PRESSURE_DOMAIN_MAX_PA,
		"not_a_validation": NOT_A_VALIDATION_TEXT,
	}


static func _requires_experimental(verdict: Dictionary) -> bool:
	for raw_entry in Array(verdict["provenance"]):
		if String(Dictionary(raw_entry)["evidence"]) == Catalog.EVIDENCE_RESEARCH_ONLY:
			return true
	return false


## El consentimiento, en texto, tal cual se lee en pantalla. Vive aqui y no en
## el editor para que la interfaz no acabe con su propia version de las cuatro
## frases ni de los valores efectivos.
static func consent_text(request: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(ACK_EXPERIMENTAL)
	lines.append("")
	lines.append(NOT_A_VALIDATION_TEXT)
	lines.append("")
	lines.append("Se solicita encender estos interruptores:")
	lines.append("  • %s (dependencia común de las cuatro familias)" % REQUIRED_DEPENDENCY)
	for raw_block in Array(request.get("families", [])):
		var block: Dictionary = raw_block
		lines.append("  • %s → %s" % [String(block["switch"]), String(block["title"])])
	for raw_block in Array(request.get("families", [])):
		var block2: Dictionary = raw_block
		lines.append("")
		lines.append(String(block2["title"]))
		if bool(block2["prescribed"]):
			lines.append("  " + ACK_PRESCRIBED)
		for raw_entry in Array(block2["openings"]):
			var entry: Dictionary = raw_entry
			var head: String = "  · abertura [%d]" % int(entry["opening_index"])
			if not String(entry["opening_id"]).is_empty():
				head += " «%s»" % String(entry["opening_id"])
			if String(entry["versioned_id"]).is_empty():
				lines.append(head + ": sin perfil; solo la prescripción del escenario")
				continue
			lines.append("%s: %s [%s]" % [
				head, String(entry["versioned_id"]), String(entry["evidence"])
			])
			var effective: Dictionary = entry["effective"]
			if effective.is_empty():
				lines.append("      sin valor efectivo: el perfil solo aporta procedencia")
			else:
				for key in effective.keys():
					lines.append("      %s = %s [%s]" % [
						String(key), str(effective[key]),
						String(Dictionary(entry["units"]).get(key, "sin unidad"))
					])
			for domain_key in Dictionary(entry["domain"]).keys():
				lines.append("      dominio · %s: %s" % [
					String(domain_key), str(Dictionary(entry["domain"])[domain_key])
				])
	var limits: Array = request.get("limits", [])
	if not limits.is_empty():
		lines.append("")
		lines.append("Limitaciones:")
		for limit in limits:
			lines.append("  • " + String(limit))
	return "\n".join(lines)


## Bloque de la salida diagnostica. Determinista: mismas claves, mismo orden.
##
## Lleva la procedencia del perfil, su version, los parametros efectivos, las
## familias encendidas y sitio para las marcas de fuera de dominio, que las
## rellena el motor con lo que mide el solver.
static func activation_report(verdict: Dictionary) -> Dictionary:
	return {
		"authorization_version": AUTHORIZATION_VERSION,
		"declares": bool(verdict["declares"]),
		"authorized": bool(verdict["authorized"]),
		"errors": Array(verdict["errors"]).duplicate(true),
		"families": Array(verdict["families"]).duplicate(true),
		"switches": Dictionary(verdict["switches"]).duplicate(true),
		"dependency": REQUIRED_DEPENDENCY,
		"prescribed_families": Array(verdict["prescribed_families"]).duplicate(true),
		"profiles": Array(verdict["provenance"]).duplicate(true),
		"limits": Array(verdict["limits"]).duplicate(true),
		"scenario_digest": String(verdict["digest"]),
		"product_activation_granted": false,
		"not_a_validation": NOT_A_VALIDATION_TEXT,
		"pressure_domain_max_pa": PRESSURE_DOMAIN_MAX_PA,
		"domain_exceeded": false,
		"domain_exceeded_steps": 0,
		"max_abs_dp_pa": 0.0,
	}


## Informe de una corrida sin autorizacion: el que vale para todo escenario que
## no declara nada. Vacio a proposito, para que la salida de un escenario
## normal no cambie ni un byte.
static func inactive_report() -> Dictionary:
	return {}
