extends RefCounted
class_name AppSettings

## Ajustes del programa que sobreviven al cierre: el idioma y la calidad
## grafica.
##
## Viven en `user://simufire.cfg`, que en Windows cae en
## `%APPDATA%/Godot/app_userdata/SimuFire/`. Se guardan al cambiarlos, no al
## salir: si el programa se cierra mal, el idioma elegido sigue elegido.
##
## No es el sitio de los ajustes del ESCENARIO -viento, plantas, HVAC-, que son
## del caso que se simula y viajan con el. Aqui solo va lo que es de la maquina
## y de quien la usa.

const SETTINGS_PATH: String = "user://simufire.cfg"
const SECTION: String = "app"

## Calidades, de menos a mas. El nombre es lo que se guarda en el fichero.
const QUALITY_LOW: String = "bajo"
const QUALITY_MEDIUM: String = "medio"
const QUALITY_HIGH: String = "alto"
const QUALITY_ORDER: Array[String] = [QUALITY_LOW, QUALITY_MEDIUM, QUALITY_HIGH]

const DEFAULT_LOCALE: String = "es"
const DEFAULT_QUALITY: String = QUALITY_HIGH

static var _config: ConfigFile = null


static func _ensure_loaded() -> void:
	if _config != null:
		return
	_config = ConfigFile.new()
	# Que no exista es lo normal la primera vez: se queda con los valores por
	# defecto y se escribe en cuanto se cambie algo.
	_config.load(SETTINGS_PATH)


## `_read`/`_write` y no `_get`/`_set`: esos dos nombres son de `Object` y
## redefinirlos con otra firma rompe el script entero.
static func _read(key: String, fallback: Variant) -> Variant:
	_ensure_loaded()
	return _config.get_value(SECTION, key, fallback)


static func _write(key: String, value: Variant) -> void:
	_ensure_loaded()
	_config.set_value(SECTION, key, value)
	var err: Error = _config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("AppSettings: no se pudo guardar %s (error %d)" % [SETTINGS_PATH, err])


## Idioma elegido, en codigo de dos letras.
static func locale() -> String:
	return String(_read("locale", DEFAULT_LOCALE))


static func set_locale(code: String) -> void:
	_write("locale", code)


## Calidad grafica: uno de QUALITY_ORDER.
static func quality() -> String:
	var value: String = String(_read("quality", DEFAULT_QUALITY))
	return value if QUALITY_ORDER.has(value) else DEFAULT_QUALITY


static func set_quality(level: String) -> void:
	_write("quality", level if QUALITY_ORDER.has(level) else DEFAULT_QUALITY)


## Nombre visible de una calidad. Se traduce como cualquier otro texto.
static func quality_label(level: String) -> String:
	match level:
		QUALITY_LOW:
			return "Bajo"
		QUALITY_MEDIUM:
			return "Medio"
	return "Alto"
