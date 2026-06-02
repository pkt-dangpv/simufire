extends RefCounted
class_name UILocalization

const DEFAULT_LOCALE: String = "es"
const UI_TEXT_PATH: String = "res://i18n/es_ui.json"

static var _loaded: bool = false
static var _messages: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_messages.clear()
	TranslationServer.set_locale(DEFAULT_LOCALE)
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
