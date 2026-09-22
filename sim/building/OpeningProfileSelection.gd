extends RefCounted

## F2.2D4B2A: politica de SELECCION y PRESENTACION de los perfiles del catalogo.
##
## Es lo que el editor enseña y lo que el editor puede dejar elegir. Vive aqui,
## junto al catalogo, y no en `editor/`, para que la interfaz no acabe con su
## propia copia de los estados de evidencia, de los dominios ni de las reglas de
## compatibilidad. El editor pinta filas; no decide cual se puede elegir.
##
## Lo que este modulo NO hace:
##
##   - no calcula caudal, presion, area de flujo ni transporte;
##   - no valida la persistencia: eso es `PrescribedOpeningPhysicsSchema`;
##   - no decide compatibilidad por su cuenta: se la pregunta al catalogo, que
##     la tiene leida de los adaptadores del motor;
##   - no enciende nada. Elegir un perfil es escribir un dato.
##
## ## Politica de seleccion
##
## | evidencia       | se ve | se elige | condicion                          |
## |-----------------|-------|----------|------------------------------------|
## | `validated`     | si    | si       | con aviso de que su dominio de ensayo no cubre una vivienda |
## | `derived`       | si    | si       | identificado como derivado de un calculo reproducible |
## | `research_only` | si    | si       | solo con el modo experimental confirmado |
## | `blocked`       | si    | **no**   | se enseña para explicar que falta  |
##
## A eso se suman dos motivos de bloqueo que no dependen de la evidencia: que la
## categoria no encaje con la abertura, y que el perfil no produzca
## configuracion (sin parametros no hay nada que congelar).
##
## ## Nada de color solo
##
## Cada fila lleva su estado en TEXTO (`evidence_label`), su aptitud de producto
## en texto (`product_label`) y, cuando no se puede elegir, el motivo en texto
## (`disabled_reason`). El color, si la interfaz lo usa, es un refuerzo.
##
## ## Vocabulario prohibido
##
## Ninguna etiqueta de este modulo dice "seguro", "realista", "estandar
## residencial" ni "calibrado": el catalogo no autoriza ninguna de las cuatro.

const Catalog = preload("res://sim/building/OpeningPhysicsProfileCatalog.gd")

## Fila que representa "esta abertura no lleva perfil". Es la opcion por
## defecto y siempre es seleccionable.
const NO_PROFILE_ID: String = ""

## Etiqueta de estado, en texto y en castellano, para cada evidencia.
const EVIDENCE_LABEL: Dictionary = {
	"validated": "MEDIDO — ensayo específico dentro de su dominio",
	"derived": "DERIVADO — cálculo reproducible desde datos medidos",
	"research_only": "EXPERIMENTAL — provisional o extrapolado",
	"blocked": "BLOQUEADO — sin evidencia o con evidencia contradictoria",
}

## Aviso que acompaña a cada estado. El de `validated` es el importante: un
## ensayo solido no convierte su dominio en una vivienda.
const EVIDENCE_NOTE: Dictionary = {
	"validated": "Medido en su ensayo, pero su dominio experimental no cubre una vivienda: no vale para activación residencial.",
	"derived": "Derivado de datos medidos con una transformación escrita; no es una medición directa.",
	"research_only": "Solo para investigación. Exige confirmar el modo experimental.",
	"blocked": "No se puede elegir. Se enseña para dejar claro qué evidencia falta.",
}

const PRODUCT_LABEL_OFF: String = "No apto para activación en vivienda (product_activation = false)"
const PRODUCT_LABEL_ON: String = "Declarado apto para activación de producto"

## Lo que el editor enseña siempre que hay configuración guardada.
const CONFIGURED_NOT_ACTIVE_TEXT: String = \
	"Configuración experimental guardada; física no activada en simulación normal."


## Categorias que esta abertura admite, en el orden estable del catalogo.
static func categories_for(opening_data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for category in Catalog.PERSISTABLE_CATEGORIES:
		if Catalog.category_applies_to(String(category), opening_data):
			out.append(String(category))
	return out


## Filas ofrecidas para una categoria y una abertura concretas.
##
## La primera es siempre "sin perfil". Despues van TODOS los perfiles de la
## categoria, en el orden del catalogo, incluidos los bloqueados y los que no
## encajan: se enseñan para explicar, con `selectable = false` y su motivo.
static func rows_for(
	opening_data: Dictionary, category: String, experimental_confirmed: bool
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [{
		"versioned_id": NO_PROFILE_ID,
		"profile_id": NO_PROFILE_ID,
		"version": 0,
		"title": "Sin perfil",
		"evidence": "",
		"evidence_label": "SIN PERFIL — la abertura no declara física experimental",
		"evidence_note": "Es la opción por defecto y la que traen todos los escenarios.",
		"product_activation": false,
		"product_label": "",
		"selectable": true,
		"requires_experimental": false,
		"disabled_reason": "",
		"domain_text": "",
		"source_text": "",
		"warnings": [],
		"effective_text": "",
	}]
	for raw_profile in Catalog.PROFILES:
		var profile: Dictionary = raw_profile
		if String(profile["category"]) != category:
			continue
		rows.append(describe(profile, opening_data, experimental_confirmed))
	return rows


## La ficha de un perfil: lo que el editor enseña y lo que le deja hacer.
static func describe(
	profile: Dictionary, opening_data: Dictionary, experimental_confirmed: bool
) -> Dictionary:
	var evidence: String = String(profile["evidence"])
	var category: String = String(profile["category"])
	var requires_experimental: bool = evidence == Catalog.EVIDENCE_RESEARCH_ONLY
	var reason: String = ""
	if evidence == Catalog.EVIDENCE_BLOCKED:
		reason = "perfil bloqueado: %s" % String(EVIDENCE_NOTE[evidence])
	elif not Catalog.can_produce_configuration(profile):
		reason = "el perfil no declara parámetros, así que no hay nada que congelar"
	elif not Catalog.category_applies_to(category, opening_data):
		reason = "no encaja con esta abertura: %s" % Catalog.incompatibility_reason(
			category, opening_data
		)
	elif requires_experimental and not experimental_confirmed:
		reason = "exige confirmar antes el modo experimental"
	return {
		"versioned_id": Catalog.versioned_id(
			String(profile["profile_id"]), int(profile["version"])
		),
		"profile_id": String(profile["profile_id"]),
		"version": int(profile["version"]),
		"title": String(profile["title"]),
		"evidence": evidence,
		"evidence_label": String(EVIDENCE_LABEL.get(evidence, evidence)),
		"evidence_note": String(EVIDENCE_NOTE.get(evidence, "")),
		"product_activation": bool(profile["product_activation"]),
		"product_label": PRODUCT_LABEL_ON if bool(profile["product_activation"]) \
				else PRODUCT_LABEL_OFF,
		"selectable": reason.is_empty(),
		"requires_experimental": requires_experimental,
		"disabled_reason": reason,
		"domain_text": domain_text(profile),
		"source_text": source_text(profile),
		"warnings": Array(profile["warnings"]).duplicate(true),
		"effective_text": effective_text(profile),
	}


## Ficha de un perfil por identidad versionada, o {} si no existe.
static func describe_id(
	profile_id: String, version: int, opening_data: Dictionary,
	experimental_confirmed: bool
) -> Dictionary:
	var profile: Dictionary = Catalog.find(profile_id, version)
	if profile.is_empty():
		return {}
	return describe(profile, opening_data, experimental_confirmed)


## Dominio declarado, en una linea legible. Se escribe tal cual lo publica el
## catalogo: aqui no se redondea ni se resume un rango a un valor.
static func domain_text(profile: Dictionary) -> String:
	var domain: Dictionary = profile.get("domain", {})
	if domain.is_empty():
		return "Sin dominio declarado."
	var pieces: PackedStringArray = []
	for key in domain.keys():
		pieces.append("%s: %s" % [String(key), str(domain[key])])
	return " · ".join(pieces)


## Fuente resumida: la primera referencia, con su localizador.
static func source_text(profile: Dictionary) -> String:
	var references: Array = profile.get("references", [])
	if references.is_empty():
		return "Sin fuente declarada."
	var first: Dictionary = references[0]
	var text: String = "%s — %s" % [String(first["source"]), String(first["locator"])]
	if references.size() > 1:
		text += " (y %d referencia(s) más)" % (references.size() - 1)
	return text


## Parametros efectivos congelados, con su unidad. Ninguno sin unidad: el
## catalogo ya lo exige, y aqui se enseña.
static func effective_text(profile: Dictionary) -> String:
	var parameters: Dictionary = profile.get("parameters", {})
	if parameters.is_empty():
		return "Sin parámetros efectivos."
	var units: Dictionary = profile.get("units", {})
	var pieces: PackedStringArray = []
	for key in parameters.keys():
		pieces.append("%s = %s [%s]" % [
			String(key), str(parameters[key]), String(units.get(key, "sin unidad"))
		])
	return " · ".join(pieces)
