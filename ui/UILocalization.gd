extends RefCounted
class_name UILocalization

## Idiomas que ofrece el programa. El castellano es el original: sus textos
## estan escritos en la escena y no necesitan tabla.
const AppSettingsScript = preload("res://ui/AppSettings.gd")

const DEFAULT_LOCALE: String = "es"
const UI_TEXT_PATH: String = "res://i18n/es_ui.json"
## Tabla de un idioma: el castellano de la escena es la CLAVE.
##
## Decision del usuario del 2026-09-10: se usa la traduccion nativa de Godot en
## vez de migrar los ~570 textos a claves. `Control` traduce solo su `text` y su
## `tooltip_text` contra el `TranslationServer`, asi que la escena se queda
## escrita en castellano -legible en el editor de Godot, y sigue siendo la
## fuente de verdad- y cambiar de idioma no pide tocar ni un nodo. Lo unico que
## hay que marcar a mano son las frases que se ARMAN en codigo, con `tr()`.
const LOCALE_TABLE_PATH: String = "res://i18n/%s_strings.json"

## Codigo y nombre de cada idioma, en su propio idioma, que es como se eligen.
const AVAILABLE_LOCALES: Array[Dictionary] = [
	{"code": "es", "name": "Español"},
	{"code": "en", "name": "English"},
]

static var _loaded: bool = false
static var _messages: Dictionary = {}
static var _registered_locales: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_messages.clear()
	_register_locale_tables()
	apply_saved_locale()
	if not FileAccess.file_exists(UI_TEXT_PATH):
		push_warning("UILocalization: falta %s" % UI_TEXT_PATH)
		return
	var file := FileAccess.open(UI_TEXT_PATH, FileAccess.READ)
	if file == null:
		push_warning("UILocalization: no se pudo abrir %s" % UI_TEXT_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("UILocalization: JSON invalido en %s" % UI_TEXT_PATH)
		return
	var root: Dictionary = parsed
	var raw_messages: Variant = root.get("messages", {})
	if typeof(raw_messages) != TYPE_DICTIONARY:
		push_warning("UILocalization: falta 'messages' en %s" % UI_TEXT_PATH)
		return
	for raw_key in Dictionary(raw_messages).keys():
		_messages[String(raw_key)] = String(Dictionary(raw_messages)[raw_key])


static func t(key: String, fallback: String = "") -> String:
	ensure_loaded()
	if _messages.has(key):
		return String(_messages[key])
	return fallback if fallback != "" else key


static func fmt(key: String, fallback: String, values: Array) -> String:
	return t(key, fallback) % values


## --- Idioma de la interfaz ---

## Carga en el TranslationServer la tabla de cada idioma que tenga fichero. El
## castellano no lleva tabla: es el original.
static func _register_locale_tables() -> void:
	# El castellano necesita SU tabla, aunque sea la identidad.
	#
	# Sin ella, `TranslationServer` no encuentra traduccion para "es" y cae al
	# idioma de reserva, que es el ingles: el programa arrancaba en castellano
	# y se veia en ingles. Con una tabla que devuelve cada texto tal cual, "es"
	# resuelve y no hay reserva que valga.
	var todas_las_claves: Dictionary = {}
	for entry in AVAILABLE_LOCALES:
		var code: String = String(entry.get("code", ""))
		if code == "" or code == DEFAULT_LOCALE or _registered_locales.has(code):
			continue
		var path: String = LOCALE_TABLE_PATH % code
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("UILocalization: JSON invalido en %s" % path)
			continue
		var translation := Translation.new()
		translation.locale = code
		for source in Dictionary(parsed).keys():
			if String(source).begins_with("_"):
				continue
			var target: String = String(Dictionary(parsed)[source])
			if target == "":
				continue
			translation.add_message(String(source), target)
			todas_las_claves[String(source)] = true
		TranslationServer.add_translation(translation)
		_registered_locales[code] = true

	if not _registered_locales.has(DEFAULT_LOCALE) and not todas_las_claves.is_empty():
		var original := Translation.new()
		original.locale = DEFAULT_LOCALE
		for source in todas_las_claves.keys():
			original.add_message(String(source), String(source))
		TranslationServer.add_translation(original)
		_registered_locales[DEFAULT_LOCALE] = true


## Pone el idioma guardado en los ajustes. Se llama al arrancar cada escena.
static func apply_saved_locale() -> void:
	set_locale(AppSettingsScript.locale())


## Cambia el idioma AHORA y lo deja guardado. Los `Control` de la escena se
## retraducen solos: Godot les manda NOTIFICATION_TRANSLATION_CHANGED.
static func set_locale(code: String) -> void:
	var wanted: String = code if is_available(code) else DEFAULT_LOCALE
	ensure_loaded()
	AppSettingsScript.set_locale(wanted)
	TranslationServer.set_locale(wanted)


static func current_locale() -> String:
	return AppSettingsScript.locale()


static func is_available(code: String) -> bool:
	for entry in AVAILABLE_LOCALES:
		if String(entry.get("code", "")) == code:
			return true
	return false


## Indice de un idioma dentro de AVAILABLE_LOCALES, para los desplegables.
static func locale_index(code: String) -> int:
	for i in range(AVAILABLE_LOCALES.size()):
		if String(AVAILABLE_LOCALES[i].get("code", "")) == code:
			return i
	return 0
