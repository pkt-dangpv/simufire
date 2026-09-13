extends SceneTree
## Guardarrail del idioma y de la configuracion del programa.
##
## Decision del usuario del 2026-09-10: **traduccion nativa de Godot**. El
## castellano de la escena hace de clave y `Control` traduce solo su `text` y
## su `tooltip_text`; anadir un idioma es anadir `i18n/<codigo>_strings.json`.
## Lo que se vigila aqui es que ese mecanismo siga en pie:
##
##  1. **El castellano se ve en castellano.** Es la trampa que costo la tarde:
##     sin una tabla propia para "es", `TranslationServer` no encuentra
##     traduccion, cae al idioma de reserva -el ingles- y el programa arranca
##     en castellano ensenandose en ingles.
##  2. **El ingles se ve en ingles**, y se vuelve del uno al otro sin recargar.
##  3. **El idioma elegido se guarda** y es el de la proxima vez.
##  4. **Las tres calidades existen y son distintas** en lo que cuesta.
##
##   <godot> --headless --path . --script res://tools/validate_localization.gd

const UILocalizationScript = preload("res://ui/UILocalization.gd")
const AppSettingsScript = preload("res://ui/AppSettings.gd")
const GraphicsQualityScript = preload("res://ui/GraphicsQuality.gd")

## Textos del menu que tienen que cambiar de idioma, con lo que deben decir.
const ESPERADO: Dictionary = {
	"Center/VBox/Subtitle": ["SIMULADOR TÁCTICO DE INCENDIOS", "TACTICAL FIRE SIMULATOR"],
	"Center/VBox/ActionsRow/BtnNewSim": ["EMPEZAR", "START"],
	"Center/VBox/SecondaryRow/BtnEditor": ["EDITOR DE VIVIENDA", "DWELLING EDITOR"],
	"Center/VBox/SecondaryRow/BtnQuit": ["SALIR", "QUIT"],
	"SettingsCenter/SettingsPanel/Pad/Rows/SettingsTitle": ["CONFIGURACIÓN", "SETTINGS"],
	"SettingsCenter/SettingsPanel/Pad/Rows/LanguageRow/LanguageLabel": ["IDIOMA", "LANGUAGE"],
	"SettingsCenter/SettingsPanel/Pad/Rows/QualityRow/QualityLabel": ["CALIDAD GRÁFICA", "GRAPHICS QUALITY"],
}

var _menu: Node = null
var _frames: int = 0
var _fails: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/MainMenu.tscn") as PackedScene
	_menu = packed.instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	var recordado: String = UILocalizationScript.current_locale()

	# 1 y 2: cada idioma se ve en el suyo.
	for i in range(2):
		var code: String = ["es", "en"][i]
		UILocalizationScript.set_locale(code)
		for path in ESPERADO.keys():
			var node = _menu.get_node_or_null(String(path))
			if node == null:
				_fail("falta %s en MainMenu.tscn" % String(path))
				continue
			var visto: String = tr(String(node.text))
			var quiere: String = String(Array(ESPERADO[path])[i])
			if visto != quiere:
				_fail("en '%s', %s dice «%s» y deberia decir «%s»" % [
					code, String(node.name), visto, quiere])

	# 2b: los textos que se ARMAN en codigo tambien cambian de idioma. Son los
	# ~160 mensajes del editor, envueltos en `tr()`: si alguien anade uno sin
	# envolver, o el mecanismo se rompe, la pista de herramienta lo canta.
	var editor_packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	var editor: Node = editor_packed.instantiate()
	root.add_child(editor)
	for i in range(2):
		var code: String = ["es", "en"][i]
		UILocalizationScript.set_locale(code)
		var hint: String = String(editor.call("_tool_hint", 6))
		var quiere: String = ["Ventana: pulsa", "Window: click"][i]
		if not hint.begins_with(quiere):
			_fail("en '%s' la pista de la ventana dice «%s» y deberia empezar por «%s»" % [
				code, hint, quiere])
		# El formato tiene que sobrevivir a la traduccion: la pista nombra la
		# planta, y si el `%s` se pierde al traducir sale un texto roto.
		if hint.contains("%s"):
			_fail("en '%s' la pista no sustituyo la planta: «%s»" % [code, hint])
	root.remove_child(editor)
	editor.free()

	# 3: el idioma se guarda.
	UILocalizationScript.set_locale("en")
	if AppSettingsScript.locale() != "en":
		_fail("el idioma elegido no se guarda: %s" % AppSettingsScript.locale())
	UILocalizationScript.set_locale("es")
	if AppSettingsScript.locale() != "es":
		_fail("volver al castellano no se guarda")

	# Un idioma que no existe no puede dejar el programa sin idioma.
	UILocalizationScript.set_locale("xx")
	if AppSettingsScript.locale() != "es":
		_fail("un idioma inexistente deberia caer al castellano, y quedo en %s" % AppSettingsScript.locale())

	# 4: las tres calidades, y que de verdad se distingan.
	var perfiles: Array = []
	for level in AppSettingsScript.QUALITY_ORDER:
		perfiles.append(GraphicsQualityScript.profile(level))
	if float(perfiles[0].get("render_scale", 1.0)) >= float(perfiles[2].get("render_scale", 1.0)):
		_fail("la calidad baja no baja la escala de render")
	if bool(perfiles[0].get("shadows_enabled", true)):
		_fail("la calidad baja deberia apagar las sombras del sol")
	if int(perfiles[0].get("city_back_blocks", 5)) >= int(perfiles[2].get("city_back_blocks", 5)):
		_fail("la calidad baja no aligera el decorado de la calle")
	AppSettingsScript.set_quality("bajo")
	if AppSettingsScript.quality() != "bajo":
		_fail("la calidad elegida no se guarda")
	AppSettingsScript.set_quality("disparatada")
	if AppSettingsScript.quality() != AppSettingsScript.DEFAULT_QUALITY:
		_fail("una calidad inexistente deberia caer a la de por defecto")

	# Se deja como estaba: este guardarrail no cambia los ajustes de nadie.
	AppSettingsScript.set_quality(AppSettingsScript.DEFAULT_QUALITY)
	UILocalizationScript.set_locale(recordado)

	if _fails == 0:
		print("[validate_localization] PASS")
	else:
		push_error("[validate_localization] FAILED")
	quit(0 if _fails == 0 else 1)
	return true


func _fail(message: String) -> void:
	_fails += 1
	push_error("- " + message)
