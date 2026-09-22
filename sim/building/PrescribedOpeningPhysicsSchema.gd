extends RefCounted

## F2.2D4A: contrato PERSISTENTE de la fisica prescrita de puertas y vidrio.
##
## Esta clase es el unico propietario del ESQUEMA con el que un escenario guarda
## y carga lo que hoy solo existia en memoria:
##
##   - D1, fuga fria: `leakage_class` y `leakage_area_override_m2` (ya se
##     persistian desde el 2026-09-18; aqui solo se documentan como parte del
##     mismo contrato, no se vuelven a normalizar);
##   - D2, deformacion prescrita: `deformation_tracks`;
##   - D3, vidrio prescrito: `glazing_panels` (carpinteria + historia de estados
##     por hoja) y `glazing_spatial` (instantaneas de regiones desprendidas).
##
## Lo que esta clase NO hace, y no debe hacer nunca:
##
##   - no calcula caudal, presion, area de flujo ni transporte;
##   - no reimplementa la ley de rendijas, la geometria multicapa, la seleccion
##     temporal, la validacion de integridad, la formula de viento ni el
##     aplicador atomico: DELEGA en los modelos puros y en el adaptador D3;
##   - no enciende `closed_door_leakage_enabled`,
##     `closed_door_deformation_enabled` ni `glazing_fallout_enabled`, que
##     siguen naciendo apagados en `SimulationEngine`. Guardar y cargar mueve
##     DATOS, nunca interruptores;
##   - no conoce la vista ni los mandos del editor. D4B decidira esa capa.
##
## ## Version del esquema, defaults y migracion
##
## `prescribed_physics_schema` vale hoy 1 y vive dentro de cada entrada de
## `openings_data`. Reglas:
##
##   - **Default = ausencia = fisica desactivada.** Un escenario sin ninguna de
##     las tres listas se comporta exactamente como antes de D4A, y al volver a
##     guardarlo no gana ni una clave: un escenario antiguo conserva su
##     identidad byte a byte.
##   - Una lista presente pero VACIA equivale a ausente y se borra al
##     normalizar, por la misma razon.
##   - La clave de version se escribe SOLO cuando sobrevive al menos una lista
##     no vacia, y se borra cuando no sobrevive ninguna.
##   - Una version declarada se conserva tal cual: `normalize()` nunca la
##     reescribe. Una version desconocida se RECHAZA en la validacion; no se
##     degrada en silencio.
##   - Datos declarados sin la clave de version se RECHAZAN: el escenario esta
##     fuera del contrato y no se adivina cual era.
##
## ## Carpinteria frente a estado operativo
##
## `open_fraction` (y `glass_broken`, y el heredado `thermal_gap_fraction`) son
## ESTADO OPERATIVO: los cambia el jugador o el motor. Todo lo que gobierna esta
## clase es CARPINTERIA: describe como esta hecha la hoja, no si alguien la ha
## abierto. Abrir o cerrar una puerta no borra su clase de fuga, sus pistas de
## deformacion ni sus paños. Es la misma regla que D1 ya aplicaba a
## `leakage_class`, extendida a D2 y D3.
##
## ## Claves desconocidas
##
## Politica documentada y deliberada:
##
##   - las claves DESCONOCIDAS de una abertura, de una pista, de un paño, de una
##     hoja o de una region se CONSERVAN tal cual (procedencia; es lo que ya
##     hacian los modelos puros con `metadata`);
##   - los VALORES de un enumerado conocido (`leakage_class`, `glass_type`,
##     `state`, `location`) se rechazan si no pertenecen al enumerado;
##   - una clave conocida con el TIPO equivocado se rechaza.
##
## ## Representabilidad numerica (defecto encontrado en D4A)
##
## `JSON.stringify` de Godot 4.7.1 escribe los dobles con 15 cifras
## significativas y ademas lleva a `0.0` las magnitudes muy pequeñas. Medido:
## `1/3`, `e`, `0.30000000000000004` y `1e-300` NO sobreviven al viaje, y el
## texto no es estable hasta la SEGUNDA escritura.
##
## Como una historia prescrita no se puede redondear en silencio, el contrato
## RECHAZA cualquier numero que el formato no represente exactamente, en vez de
## guardarlo mutilado. Con esa puerta cerrada, ida y vuelta es exacta y el
## fichero es estable byte a byte desde la primera escritura.
##
## ## Enteros: el fichero solo tiene un tipo numerico (segundo defecto de D4A)
##
## `JSON.parse_string` devuelve TODO numero como `float`: un `2` escrito en el
## fichero vuelve como `2.0`. `GlazingIntegrityModel` exige `TYPE_INT` en
## `leaf_count` y en el `index` de cada hoja, y `GlazingOpeningGeometryModel`
## rechaza un indice real, asi que SIN esta clase una declaracion de D3 no
## sobrevive a un viaje por el fichero: se guarda bien y se rechaza al volver.
##
## `decode()` restituye el tipo entero de los campos que el esquema declara
## enteros, y SOLO cuando el valor es exactamente entero: un `2.5` se deja como
## esta para que el modelo puro lo rechace con su propio mensaje. Esto no es
## reparar un escenario malformado, es descodificar el formato: el fichero no
## distingue `2` de `2.0` y el esquema si sabe cual de los dos queria decir.
##
## Efecto colateral necesario: `normalize()` descodifica, de modo que la
## siguiente escritura vuelve a poner `2` y no `2.0`, y el fichero es estable
## desde la primera vuelta.
##
## ## Esquema 2 (F2.2D4B1): perfiles del catalogo
##
## El esquema 2 anade dos claves OPCIONALES por abertura, `leakage_profile`
## (fuga fria de D1) y `frame_leakage_profile` (fuga de marco exterior de R3).
## Cada una tiene la forma:
##
##     {"profile_id": <texto>, "profile_version": <entero>, "effective": {...}}
##
## **La decision de diseno, escrita antes de programarla:** se guardan LAS DOS
## cosas, la referencia versionada y una COPIA CONGELADA de los parametros
## efectivos, y la copia congelada es la AUTORITATIVA para la fisica. La razon
## es que las dos por separado fallan:
##
##   - solo el identificador haria que reeditar el catalogo cambiase la fisica
##     de un escenario ya guardado;
##   - solo la copia congelada perderia la trazabilidad de que perfil, y de que
##     version, produjo esos numeros.
##
## Con las dos, cargar resuelve la referencia contra el catalogo y COMPARA: si
## el par `(profile_id, profile_version)` ya no existe, o existe y sus
## parametros no coinciden con la copia congelada, la carga FALLA de forma
## explicita. No se recalibra nada en silencio y no se acepta una copia
## manipulada. Como `(profile_id, version)` es inmutable por contrato, anadir
## perfiles o versiones nuevas nunca afecta a un escenario antiguo.
##
## Un perfil `blocked` no puede aparecer en un escenario: no produce
## configuracion. Un perfil sin parametros tampoco. Y un perfil de una
## categoria que no encaja con la abertura -la fuga de marco de R3 en un tabique
## interior, por ejemplo- se rechaza: la regla de compatibilidad la pone el
## catalogo, leida de los adaptadores del motor, y no se duplica aqui.
##
## ## Esquema 3 (F2.2D4B2A): deformacion y vidrio con procedencia
##
## El esquema 3 anade otras dos ranuras opcionales, `deformation_profile` y
## `glazing_profile`, con la MISMA forma que las dos de D4B1.
##
## La diferencia importa: en D4B1 el perfil aportaba el NUMERO que el motor
## consume -la ELA de la rendija, el area del marco-. En estas dos no aporta
## ninguno, porque D2 y D3 son PRESCRIPCION: las magnitudes las escribe quien
## monta el escenario, en `deformation_tracks`, `glazing_panels` y
## `glazing_spatial`. Lo que el perfil aporta es la PROCEDENCIA: con que
## ensayo, en que dominio y con que estado de evidencia hay que leer esa
## prescripcion. Por eso su ranura no declara parametro obligatorio, y aun asi
## la copia congelada tiene que coincidir con el catalogo entera.
##
## **Migracion 1 -> 3 y 2 -> 3, explicitas.** La marca sube al minimo que exige
## el contenido y nunca baja: sin perfiles se queda en 1, con perfiles de D4B1
## en 2 y con perfiles de deformacion o vidrio en 3. Un escenario de esquema 1
## o 2 sigue cargando tal cual, y si no declara nada nuevo se vuelve a guardar
## con su marca de siempre, sin ganar ni una clave. Ninguna migracion enciende
## fisica: solo mueve el numero de version.
##
## **Migracion 1 -> 2, explicita.** Un escenario del esquema 1 sigue siendo
## valido y, si no declara perfiles, se vuelve a guardar como 1: no gana ni una
## clave. La marca sube a 2 SOLO cuando el contenido lo exige, es decir cuando
## hay algun perfil declarado, y nunca baja. Una version declarada por encima
## de `SCHEMA_VERSION` se rechaza.

const DeformationModel = preload("res://sim/core/ClosedDoorDeformationModel.gd")
const GlazingAdapter = preload("res://sim/core/GlazingFalloutNetworkAdapter.gd")
const ProfileCatalog = preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")

## Version del sub-esquema por abertura. Subirla es un cambio de contrato y
## exige actualizar la politica de migracion de la cabecera y los documentos.
## 1 = F2.2D4A (fisica prescrita); 2 = F2.2D4B1 (perfiles de fuga);
## 3 = F2.2D4B2A (perfiles de deformacion y de vidrio).
const SCHEMA_VERSION: int = 3
## Version minima que sigue siendo valida al cargar. Un escenario de D4A se
## carga y se vuelve a guardar como 1 mientras no declare perfiles.
const MIN_SCHEMA_VERSION: int = 1
const SCHEMA_KEY: String = "prescribed_physics_schema"

const DEFORMATION_KEY: String = "deformation_tracks"
const PANELS_KEY: String = "glazing_panels"
const SPATIAL_KEY: String = "glazing_spatial"

## F2.2D4B1: referencias al catalogo. Aparecieron en el esquema 2.
const LEAKAGE_PROFILE_KEY: String = "leakage_profile"
const FRAME_PROFILE_KEY: String = "frame_leakage_profile"
## F2.2D4B2A: procedencia de la prescripcion. Aparecieron en el esquema 3.
const DEFORMATION_PROFILE_KEY: String = "deformation_profile"
const GLAZING_PROFILE_KEY: String = "glazing_profile"
const PROFILE_KEYS: Array[String] = [
	LEAKAGE_PROFILE_KEY, FRAME_PROFILE_KEY,
	DEFORMATION_PROFILE_KEY, GLAZING_PROFILE_KEY,
]
## Ranuras que existen ya en el esquema 2. Las demas exigen el 3.
const SCHEMA_2_PROFILE_KEYS: Array[String] = [LEAKAGE_PROFILE_KEY, FRAME_PROFILE_KEY]
## Categoria del catalogo que admite cada ranura. Una fuga de marco en la
## ranura de la puerta es un error, no una conversion.
const PROFILE_SLOT_CATEGORY: Dictionary = {
	LEAKAGE_PROFILE_KEY: "door_leakage",
	FRAME_PROFILE_KEY: "frame_leakage",
	DEFORMATION_PROFILE_KEY: "deformation",
	GLAZING_PROFILE_KEY: "glazing",
}
## Parametro que cada ranura congela y entrega al motor. Cadena vacia = la
## ranura no aporta ningun numero al motor y solo guarda procedencia: es el
## caso de D2 y D3, donde las magnitudes las prescribe el escenario.
const PROFILE_SLOT_PARAMETER: Dictionary = {
	LEAKAGE_PROFILE_KEY: "ela_m2",
	FRAME_PROFILE_KEY: "leak_area_m2",
	DEFORMATION_PROFILE_KEY: "",
	GLAZING_PROFILE_KEY: "",
}
const PROFILE_ID_KEY: String = "profile_id"
const PROFILE_VERSION_KEY: String = "profile_version"
const PROFILE_EFFECTIVE_KEY: String = "effective"

## Las tres listas del esquema, en orden estable. `leakage_class` y
## `leakage_area_override_m2` NO estan aqui: los normaliza y valida D1 desde el
## 2026-09-18 y este modulo no los toca para no crear un segundo propietario.
const PAYLOAD_KEYS: Array[String] = [DEFORMATION_KEY, PANELS_KEY, SPATIAL_KEY]

## Campos que el esquema declara ENTEROS. Es la lista cerrada que `decode()`
## restituye tras pasar por el fichero. No hay ninguno en las pistas de D2.
const PANEL_INT_KEY: String = "leaf_count"
const LEAF_INT_KEY: String = "index"

## Tipos que el fichero representa de forma nativa. Cualquier otro (Vector2,
## objetos, callables) no es dato de escenario y se rechaza.
const JSON_NATIVE_TYPES: Array[int] = [
	TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
	TYPE_STRING_NAME, TYPE_ARRAY, TYPE_DICTIONARY,
]


## ¿Esta abertura trae datos de D4A? Una lista vacia no cuenta: es lo mismo que
## no traer nada.
static func declares(opening_data: Dictionary) -> bool:
	for key in PAYLOAD_KEYS:
		var value: Variant = opening_data.get(key, null)
		if typeof(value) == TYPE_ARRAY and not Array(value).is_empty():
			return true
	for key in PROFILE_KEYS:
		var profile: Variant = opening_data.get(key, null)
		if typeof(profile) == TYPE_DICTIONARY and not Dictionary(profile).is_empty():
			return true
	return false


## Version minima de esquema que EXIGE el contenido de esta abertura. Es lo que
## convierte la migracion en una regla y no en una costumbre.
static func required_schema_version(opening_data: Dictionary) -> int:
	var required: int = MIN_SCHEMA_VERSION
	for key in PROFILE_KEYS:
		var profile: Variant = opening_data.get(key, null)
		if typeof(profile) != TYPE_DICTIONARY or Dictionary(profile).is_empty():
			continue
		required = maxi(required, 2 if SCHEMA_2_PROFILE_KEYS.has(key) else 3)
	return required


## Normaliza en sitio la parte D4A de UNA abertura ya duplicada.
##
## No redondea, no reordena, no rellena y no repara: solo decide que claves
## sobreviven, para que un escenario antiguo no gane campos y uno nuevo declare
## su version. Los datos malformados se conservan intactos y los rechaza
## `validate()`, que es quien falla de forma explicita.
static func normalize(opening: Dictionary) -> void:
	for key in PAYLOAD_KEYS:
		if not opening.has(key):
			continue
		var value: Variant = opening[key]
		# Una lista vacia es exactamente "sin datos": se borra para que guardar
		# un escenario antiguo no le añada claves que no tenia.
		if typeof(value) == TYPE_ARRAY and Array(value).is_empty():
			opening.erase(key)
			continue
		# Restituye el tipo entero que el fichero no sabe distinguir. Los
		# valores no cambian: solo deja de escribirse `2.0` donde iba un `2`.
		opening[key] = _decoded(key, value)
	for key in PROFILE_KEYS:
		if not opening.has(key):
			continue
		var profile: Variant = opening[key]
		# Un bloque de perfil vacio es exactamente "sin perfil".
		if typeof(profile) == TYPE_DICTIONARY and Dictionary(profile).is_empty():
			opening.erase(key)
			continue
		opening[key] = _decoded(key, profile)
	if not declares(opening):
		# Sin carga util, la marca de version sobra. Nunca se deja colgada.
		opening.erase(SCHEMA_KEY)
		return
	var required: int = required_schema_version(opening)
	if not opening.has(SCHEMA_KEY):
		opening[SCHEMA_KEY] = required
		return
	# La marca de version tambien vuelve del fichero como `1.0`. Se le restituye
	# el tipo sin tocar el valor: una version fraccionaria se deja intacta y la
	# rechaza `validate()`.
	var declared: Variant = _as_integer(opening[SCHEMA_KEY])
	# Migracion 1 -> 2: la marca SUBE cuando el contenido lo exige, y nunca
	# baja. Es la unica escritura que este modulo hace sobre la version, y no
	# toca ni un dato. Una version ya suficiente se conserva tal cual, de modo
	# que un escenario de D4A sin perfiles se vuelve a guardar como 1.
	if typeof(declared) == TYPE_INT and int(declared) < required:
		declared = required
	opening[SCHEMA_KEY] = declared


## Valida la parte D4A de una abertura. Devuelve los errores, ya prefijados con
## el indice de la abertura. Lista vacia = contrato cumplido.
static func validate(opening_data: Dictionary, index: int) -> Array[String]:
	var errors: Array[String] = []
	var prefix: String = "openings_data[%d]" % index
	var has_any_key: bool = opening_data.has(SCHEMA_KEY)
	for key in PAYLOAD_KEYS:
		if opening_data.has(key):
			has_any_key = true
			if typeof(opening_data[key]) != TYPE_ARRAY:
				errors.append("%s: %s debe ser un array" % [prefix, key])
	for key in PROFILE_KEYS:
		if opening_data.has(key):
			has_any_key = true
			if typeof(opening_data[key]) != TYPE_DICTIONARY:
				errors.append("%s: %s debe ser un diccionario" % [prefix, key])
	if not has_any_key:
		return errors
	if not errors.is_empty():
		return errors

	var has_payload: bool = declares(opening_data)
	if opening_data.has(SCHEMA_KEY):
		var raw_version: Variant = opening_data[SCHEMA_KEY]
		if typeof(raw_version) != TYPE_INT and typeof(raw_version) != TYPE_FLOAT:
			errors.append("%s: %s debe ser un entero" % [prefix, SCHEMA_KEY])
			return errors
		var version: int = int(raw_version)
		if float(raw_version) != float(version):
			errors.append("%s: %s debe ser un entero" % [prefix, SCHEMA_KEY])
			return errors
		if version < MIN_SCHEMA_VERSION or version > SCHEMA_VERSION:
			errors.append("%s: %s %d no esta soportado (admitidos %d a %d)" % [
				prefix, SCHEMA_KEY, version, MIN_SCHEMA_VERSION, SCHEMA_VERSION
			])
			return errors
		var required: int = required_schema_version(opening_data)
		if version < required:
			errors.append("%s: %s %d es insuficiente para su contenido (exige %d)" % [
				prefix, SCHEMA_KEY, version, required
			])
			return errors
		if not has_payload:
			errors.append("%s: %s sin datos prescritos declarados" % [prefix, SCHEMA_KEY])
			return errors
	elif has_payload:
		errors.append("%s: la fisica prescrita exige declarar %s" % [prefix, SCHEMA_KEY])
		return errors
	else:
		# Solo listas vacias y sin version: equivale a no declarar nada.
		return errors

	# Se valida la carga DESCODIFICADA, que es la que vera el motor: el fichero
	# no distingue `2` de `2.0` y el esquema sabe cual de los dos es.
	var decoded: Dictionary = opening_data.duplicate(true)
	for key in PAYLOAD_KEYS + PROFILE_KEYS:
		if decoded.has(key):
			decoded[key] = _decoded(key, decoded[key])
			_check_json_stable(decoded[key], "%s.%s" % [prefix, key], errors)
	if not errors.is_empty():
		return errors

	_validate_deformation(decoded, prefix, errors)
	_validate_glazing(decoded, prefix, errors)
	_validate_profiles(decoded, prefix, errors)
	return errors


## F2.2D4B1: resuelve cada referencia de perfil contra el catalogo y compara la
## copia congelada. Aqui no se calcula ninguna fisica: se comprueba que lo que
## el escenario dice que uso sigue siendo exactamente lo que el catalogo dice.
static func _validate_profiles(
	opening_data: Dictionary, prefix: String, errors: Array[String]
) -> void:
	for key in PROFILE_KEYS:
		if not opening_data.has(key):
			continue
		var block: Dictionary = opening_data[key]
		var label: String = "%s.%s" % [prefix, key]
		var profile_id: String = String(block.get(PROFILE_ID_KEY, ""))
		if profile_id.strip_edges().is_empty():
			errors.append("%s: %s vacio" % [label, PROFILE_ID_KEY])
			continue
		if typeof(block.get(PROFILE_VERSION_KEY, null)) != TYPE_INT:
			errors.append("%s: %s debe ser un entero" % [label, PROFILE_VERSION_KEY])
			continue
		var version: int = int(block[PROFILE_VERSION_KEY])
		if not ProfileCatalog.has_profile_id(profile_id):
			errors.append("%s: perfil desconocido '%s'" % [label, profile_id])
			continue
		var profile: Dictionary = ProfileCatalog.find(profile_id, version)
		if profile.is_empty():
			errors.append("%s: el perfil '%s' no tiene la version %d (disponibles %s)" % [
				label, profile_id, version, str(ProfileCatalog.versions_of(profile_id))
			])
			continue
		if String(profile["category"]) != String(PROFILE_SLOT_CATEGORY[key]):
			errors.append("%s: el perfil '%s' es de categoria '%s' y esta ranura exige '%s'" % [
				label, profile_id, String(profile["category"]),
				String(PROFILE_SLOT_CATEGORY[key])
			])
			continue
		if not ProfileCatalog.can_produce_configuration(profile):
			errors.append("%s: el perfil '%s' no puede producir configuracion (evidencia '%s')" % [
				label, profile_id, String(profile["evidence"])
			])
			continue
		# F2.2D4B2A: la categoria tiene que encajar con ESTA abertura. La regla
		# la pone el catalogo, leida de los adaptadores del motor; cambiar el
		# tipo de una abertura con perfil deja de cargar en vez de arrastrar
		# una carpinteria que ya no significa nada.
		var category: String = String(profile["category"])
		if not ProfileCatalog.category_applies_to(category, opening_data):
			errors.append("%s: el perfil '%s' no encaja con esta abertura: %s" % [
				label, profile_id,
				ProfileCatalog.incompatibility_reason(category, opening_data)
			])
			continue
		if typeof(block.get(PROFILE_EFFECTIVE_KEY, null)) != TYPE_DICTIONARY:
			errors.append("%s: falta la copia congelada '%s'" % [label, PROFILE_EFFECTIVE_KEY])
			continue
		_compare_frozen_parameters(
			Dictionary(block[PROFILE_EFFECTIVE_KEY]), Dictionary(profile["parameters"]),
			String(PROFILE_SLOT_PARAMETER[key]), label, errors
		)


## La copia congelada del escenario contra los parametros del catalogo. Tiene
## que coincidir EXACTAMENTE: una diferencia no se corrige, se rechaza.
static func _compare_frozen_parameters(
	frozen: Dictionary, catalog: Dictionary, required_parameter: String,
	label: String, errors: Array[String]
) -> void:
	# Una ranura sin parametro obligatorio no aporta numero al motor; aun asi su
	# copia congelada tiene que coincidir entera con el catalogo.
	if not required_parameter.is_empty() and not frozen.has(required_parameter):
		errors.append("%s: la copia congelada no trae '%s'" % [label, required_parameter])
	for key in frozen.keys():
		var name: String = String(key)
		if not catalog.has(name):
			errors.append("%s: la copia congelada trae '%s', que el catalogo no declara" % [
				label, name
			])
			continue
		if typeof(frozen[name]) != typeof(catalog[name]) or frozen[name] != catalog[name]:
			errors.append(
				"%s: '%s' congelado (%s) no coincide con el catalogo (%s); "
				% [label, name, JSON.stringify(frozen[name]), JSON.stringify(catalog[name])]
				+ "una version publicada no cambia nunca, asi que esto es una alteracion"
			)
	for key in catalog.keys():
		if not frozen.has(String(key)):
			errors.append("%s: la copia congelada omite el parametro '%s'" % [label, String(key)])


## Vuelca los datos ya validados en una `OpeningModel`. Copia profunda: el
## escenario y la abertura no comparten memoria, asi que el motor no puede
## reescribir el escenario cargado por accidente.
##
## Cargar NO enciende nada: los tres interruptores viven en `SimulationEngine`,
## nacen apagados y son los unicos que deciden si esta fisica se consume.
static func apply_to_opening(opening_data: Dictionary, opening: OpeningModel) -> void:
	if opening == null:
		return
	opening.deformation_tracks = _duplicated_array(opening_data, DEFORMATION_KEY)
	opening.glazing_panels = _duplicated_array(opening_data, PANELS_KEY)
	opening.glazing_spatial = _duplicated_array(opening_data, SPATIAL_KEY)
	_apply_profiles(opening_data, opening)


## F2.2D4B1: un perfil se aplica resolviendolo al MISMO dato que el motor ya
## entendia, no anadiendo una segunda fuente de fisica.
##
##   - la fuga fria se entrega como el override de ELA explicito que D1 ya lee,
##     de modo que `ClosedDoorLeakageNetworkAdapter` no cambia ni una linea;
##   - la fuga de marco se entrega como area por abertura, que el transporte
##     usa EN LUGAR de la global, nunca sumada a ella.
##
## La referencia versionada se guarda aparte como PROCEDENCIA: ningun camino de
## caudal la lee. Y aplicar un perfil no enciende nada: los interruptores viven
## en `SimulationEngine` y siguen naciendo apagados.
static func _apply_profiles(opening_data: Dictionary, opening: OpeningModel) -> void:
	var leakage: Dictionary = _profile_block(opening_data, LEAKAGE_PROFILE_KEY)
	if not leakage.is_empty():
		opening.leakage_profile_ref = _profile_reference(leakage)
		opening.leakage_area_override_m2 = float(
			Dictionary(leakage[PROFILE_EFFECTIVE_KEY])[PROFILE_SLOT_PARAMETER[LEAKAGE_PROFILE_KEY]]
		)
	var frame: Dictionary = _profile_block(opening_data, FRAME_PROFILE_KEY)
	if not frame.is_empty():
		opening.frame_leakage_profile_ref = _profile_reference(frame)
		opening.frame_leakage_area_m2 = float(
			Dictionary(frame[PROFILE_EFFECTIVE_KEY])[PROFILE_SLOT_PARAMETER[FRAME_PROFILE_KEY]]
		)
	# F2.2D4B2A: estas dos NO aportan ningun numero al motor. Solo dejan escrito
	# con que ensayo hay que leer la prescripcion que ya viaja en
	# `deformation_tracks`, `glazing_panels` y `glazing_spatial`.
	var deformation: Dictionary = _profile_block(opening_data, DEFORMATION_PROFILE_KEY)
	if not deformation.is_empty():
		opening.deformation_profile_ref = _profile_reference(deformation)
	var glazing: Dictionary = _profile_block(opening_data, GLAZING_PROFILE_KEY)
	if not glazing.is_empty():
		opening.glazing_profile_ref = _profile_reference(glazing)


static func _profile_block(opening_data: Dictionary, key: String) -> Dictionary:
	var value: Variant = opening_data.get(key, null)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var block: Dictionary = _decoded(key, Dictionary(value).duplicate(true))
	if typeof(block.get(PROFILE_EFFECTIVE_KEY, null)) != TYPE_DICTIONARY:
		return {}
	# Falla cerrado: sin el parametro que esta ranura necesita no se aplica
	# nada. `validate()` ya lo habra rechazado, y aplicar no es el sitio donde
	# reventar por un dato que no esta.
	var effective: Dictionary = block[PROFILE_EFFECTIVE_KEY]
	var parameter: String = String(PROFILE_SLOT_PARAMETER.get(key, ""))
	# Una ranura de solo procedencia no exige parametro, pero si exige que el
	# bloque nombre un perfil: sin eso no hay nada que anotar.
	if parameter.is_empty():
		if String(block.get(PROFILE_ID_KEY, "")).strip_edges().is_empty():
			return {}
		return block
	if not effective.has(parameter):
		return {}
	var magnitude: Variant = effective[parameter]
	if typeof(magnitude) != TYPE_FLOAT and typeof(magnitude) != TYPE_INT:
		return {}
	if not is_finite(float(magnitude)):
		return {}
	return block


static func _profile_reference(block: Dictionary) -> String:
	return ProfileCatalog.versioned_id(
		String(block.get(PROFILE_ID_KEY, "")), int(block.get(PROFILE_VERSION_KEY, 0))
	)


## Bloque persistente para un perfil del catalogo, con su copia congelada.
## Es el unico sitio donde se construye esa estructura.
static func build_profile_block(profile_id: String, version: int) -> Dictionary:
	var profile: Dictionary = ProfileCatalog.find(profile_id, version)
	if profile.is_empty() or not ProfileCatalog.can_produce_configuration(profile):
		return {}
	return {
		PROFILE_ID_KEY: profile_id,
		PROFILE_VERSION_KEY: version,
		PROFILE_EFFECTIVE_KEY: Dictionary(profile["parameters"]).duplicate(true),
	}


static func _duplicated_array(opening_data: Dictionary, key: String) -> Array:
	var value: Variant = opening_data.get(key, null)
	if typeof(value) != TYPE_ARRAY:
		return []
	return Array(_decoded(key, Array(value).duplicate(true)))


## Descodificacion del formato: restituye el tipo entero de los campos que el
## esquema declara enteros. Ver la cabecera, "Enteros".
##
## Devuelve SIEMPRE una copia: ni el escenario ni la abertura comparten memoria
## con la otra. Un valor que no sea exactamente entero se deja intacto para que
## lo rechace el modelo puro, con su propio mensaje.
static func _decoded(key: String, value: Variant) -> Variant:
	if PROFILE_KEYS.has(key):
		if typeof(value) != TYPE_DICTIONARY:
			return value
		var block: Dictionary = Dictionary(value).duplicate(true)
		if block.has(PROFILE_VERSION_KEY):
			block[PROFILE_VERSION_KEY] = _as_integer(block[PROFILE_VERSION_KEY])
		return block
	if typeof(value) != TYPE_ARRAY:
		return value
	match key:
		PANELS_KEY:
			return _decoded_panels(Array(value))
		SPATIAL_KEY:
			return _decoded_spatial(Array(value))
		_:
			# Las pistas de D2 no declaran ningun entero.
			return Array(value).duplicate(true)


static func _decoded_panels(panels: Array) -> Array:
	var decoded: Array = []
	for raw_panel in panels:
		if typeof(raw_panel) != TYPE_DICTIONARY:
			decoded.append(raw_panel)
			continue
		var panel: Dictionary = Dictionary(raw_panel).duplicate(true)
		if panel.has(PANEL_INT_KEY):
			panel[PANEL_INT_KEY] = _as_integer(panel[PANEL_INT_KEY])
		if typeof(panel.get("leaves", null)) == TYPE_ARRAY:
			panel["leaves"] = _decoded_leaves(Array(panel["leaves"]))
		decoded.append(panel)
	return decoded


static func _decoded_spatial(spatial: Array) -> Array:
	var decoded: Array = []
	for raw_entry in spatial:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			decoded.append(raw_entry)
			continue
		var entry: Dictionary = Dictionary(raw_entry).duplicate(true)
		if typeof(entry.get("snapshots", null)) != TYPE_ARRAY:
			decoded.append(entry)
			continue
		var snapshots: Array = []
		for raw_snapshot in Array(entry["snapshots"]):
			if typeof(raw_snapshot) != TYPE_DICTIONARY:
				snapshots.append(raw_snapshot)
				continue
			var snapshot: Dictionary = Dictionary(raw_snapshot).duplicate(true)
			if typeof(snapshot.get("leaves", null)) == TYPE_ARRAY:
				snapshot["leaves"] = _decoded_leaves(Array(snapshot["leaves"]))
			snapshots.append(snapshot)
		entry["snapshots"] = snapshots
		decoded.append(entry)
	return decoded


static func _decoded_leaves(leaves: Array) -> Array:
	var decoded: Array = []
	for raw_leaf in leaves:
		if typeof(raw_leaf) != TYPE_DICTIONARY:
			decoded.append(raw_leaf)
			continue
		var leaf: Dictionary = Dictionary(raw_leaf).duplicate(true)
		if leaf.has(LEAF_INT_KEY):
			leaf[LEAF_INT_KEY] = _as_integer(leaf[LEAF_INT_KEY])
		decoded.append(leaf)
	return decoded


## `2.0` era un `2` que paso por el fichero. `2.5` no lo era: se devuelve tal
## cual para que el modelo puro lo rechace en vez de truncarlo en silencio.
static func _as_integer(value: Variant) -> Variant:
	if typeof(value) != TYPE_FLOAT:
		return value
	var number: float = float(value)
	if not is_finite(number) or number != floorf(number) or absf(number) > 9007199254740992.0:
		return value
	return int(number)


## D2: las pistas las valida su modelo puro. Aqui solo se añade lo que el
## fichero puede decir y el modelo puro no ve: de que abertura cuelgan.
##
## La apertura operativa NO se mira. Una puerta guardada abierta conserva su
## deformacion prescrita igual que conserva su clase de fuga; que una pista
## exija puerta cerrada es cosa del paso de simulacion, no del fichero.
static func _validate_deformation(
	opening_data: Dictionary, prefix: String, errors: Array[String]
) -> void:
	var tracks: Array = Array(opening_data.get(DEFORMATION_KEY, []))
	if tracks.is_empty():
		return
	var type_name: String = String(opening_data.get("type", "door")).strip_edges().to_lower()
	if type_name != "door":
		errors.append("%s: %s solo existe en una puerta" % [prefix, DEFORMATION_KEY])
	if _is_exterior(opening_data):
		errors.append("%s: %s exige dos salas interiores" % [prefix, DEFORMATION_KEY])
	var checked: Dictionary = DeformationModel.validate_tracks(tracks)
	for error in checked["errors"]:
		errors.append("%s: %s" % [prefix, String(error)])


## D3: la cadena completa 3A -> 3B -> colocacion la valida el adaptador de D3,
## que es su unico propietario. Aqui se construye una abertura de trabajo con la
## geometria declarada y se pide esa validacion en CADA instante declarado, de
## forma que una historia incoherente -un estado que cambia sin su instantanea
## espacial- se rechace al cargar y no en mitad de una simulacion.
##
## No se emite ni se consume ningun elemento: el resultado se descarta entero.
static func _validate_glazing(
	opening_data: Dictionary, prefix: String, errors: Array[String]
) -> void:
	var panels: Array = Array(opening_data.get(PANELS_KEY, []))
	var spatial: Array = Array(opening_data.get(SPATIAL_KEY, []))
	if panels.is_empty() and spatial.is_empty():
		return
	var width_m: float = float(opening_data.get("width_m", NAN))
	var height_m: float = float(opening_data.get("height_m", NAN))
	if not is_finite(width_m) or width_m <= 0.0 \
			or not is_finite(height_m) or height_m <= 0.0:
		errors.append("%s: el vidrio prescrito exige un hueco anfitrion valido" % prefix)
		return
	var probe = OpeningModel.new(
		int(opening_data.get("a", 0)),
		int(opening_data.get("b", -1)),
		_opening_type(opening_data),
		width_m,
		height_m,
		0.0
	)
	probe.sill_m = float(opening_data.get("sill_m", 0.0))
	probe.opening_index = 0
	probe.glazing_panels = panels
	probe.glazing_spatial = spatial
	for time_s in _declared_times(panels, spatial):
		var checked: Dictionary = GlazingAdapter.build_opening_elements(
			probe, BuildingModel.OUTSIDE_ID, 0.0, "a", "b", time_s
		)
		if bool(checked["valid"]):
			continue
		for error in checked["errors"]:
			var message: String = "%s: vidrio en t=%s s: %s" % [
				prefix, String.num(time_s, 9), String(error)
			]
			if not errors.has(message):
				errors.append(message)


## Instantes declarados por la historia: los de cada instantanea espacial y los
## de cada evento de integridad, mas el origen. Ordenados y sin repetidos, para
## que la validacion sea determinista y no dependa del orden de escritura.
static func _declared_times(panels: Array, spatial: Array) -> Array[float]:
	var seen: Dictionary = {0.0: true}
	for raw_entry in spatial:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var snapshots: Variant = Dictionary(raw_entry).get("snapshots", null)
		if typeof(snapshots) != TYPE_ARRAY:
			continue
		for raw_snapshot in Array(snapshots):
			if typeof(raw_snapshot) != TYPE_DICTIONARY:
				continue
			_collect_time(Dictionary(raw_snapshot).get("time_s", null), seen)
	for raw_panel in panels:
		if typeof(raw_panel) != TYPE_DICTIONARY:
			continue
		var leaves: Variant = Dictionary(raw_panel).get("leaves", null)
		if typeof(leaves) != TYPE_ARRAY:
			continue
		for raw_leaf in Array(leaves):
			if typeof(raw_leaf) != TYPE_DICTIONARY:
				continue
			var events: Variant = Dictionary(raw_leaf).get("events", null)
			if typeof(events) != TYPE_ARRAY:
				continue
			for raw_event in Array(events):
				if typeof(raw_event) != TYPE_DICTIONARY:
					continue
				_collect_time(Dictionary(raw_event).get("time_s", null), seen)
	var times: Array[float] = []
	for key in seen.keys():
		times.append(float(key))
	times.sort()
	return times


static func _collect_time(value: Variant, seen: Dictionary) -> void:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return
	var time_s: float = float(value)
	if not is_finite(time_s) or time_s < 0.0:
		return
	seen[time_s] = true


static func _opening_type(opening_data: Dictionary) -> int:
	match String(opening_data.get("type", "door")).strip_edges().to_lower():
		"window":
			return OpeningModel.Type.WINDOW
		"hole":
			return OpeningModel.Type.HOLE
		_:
			return OpeningModel.Type.DOOR


static func _is_exterior(opening_data: Dictionary) -> bool:
	return int(opening_data.get("a", 0)) == BuildingModel.OUTSIDE_ID \
			or int(opening_data.get("b", BuildingModel.OUTSIDE_ID)) == BuildingModel.OUTSIDE_ID


## Comprueba que el fichero puede devolver EXACTAMENTE lo que se le da.
##
## `JSON.stringify` escribe 15 cifras significativas y hunde a cero lo muy
## pequeño, asi que hay dobles legitimos que no sobreviven. Redondearlos en
## silencio falsificaria una historia prescrita, de modo que se rechazan con el
## valor y la ruta concretos y quien escribe el escenario decide.
static func _check_json_stable(value: Variant, path: String, errors: Array[String]) -> void:
	var type_id: int = typeof(value)
	if not JSON_NATIVE_TYPES.has(type_id):
		errors.append("%s: tipo %d no es representable en el escenario" % [path, type_id])
		return
	if type_id == TYPE_ARRAY:
		var array: Array = value
		for i in range(array.size()):
			_check_json_stable(array[i], "%s[%d]" % [path, i], errors)
		return
	if type_id == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		for key in dictionary.keys():
			if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
				errors.append("%s: las claves del escenario deben ser texto" % path)
				continue
			_check_json_stable(dictionary[key], "%s.%s" % [path, String(key)], errors)
		return
	if type_id != TYPE_INT and type_id != TYPE_FLOAT:
		return
	if type_id == TYPE_FLOAT and not is_finite(float(value)):
		errors.append("%s: un numero no finito no es representable" % path)
		return
	if type_id == TYPE_INT:
		# El fichero guarda el entero como doble y `decode()` le devuelve el
		# tipo, asi que solo hay perdida por encima de 2^53.
		var as_float: float = float(int(value))
		if int(as_float) != int(value):
			errors.append("%s: el entero es demasiado grande para el escenario" % path)
		return
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(value))
	if typeof(round_tripped) != TYPE_FLOAT or float(round_tripped) != float(value):
		errors.append(
			"%s: el valor no sobrevive exactamente al fichero (%s -> %s); "
			% [path, JSON.stringify(value), JSON.stringify(round_tripped)]
			+ "el escenario guarda 15 cifras significativas y no se redondea en silencio"
		)
