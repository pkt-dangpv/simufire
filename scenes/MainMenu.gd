extends Control
class_name MainMenu

# ============================================================
# MAIN MENU
# ------------------------------------------------------------
# Punto de entrada del proyecto.
# - Modo validación: redirige directamente a SimulationScene.
# - Modo normal: menú definido INTEGRAMENTE en MainMenu.tscn.
#   Este script solo conecta señales, localiza textos y rellena
#   el contenido dinámico (presets de plantilla, opciones guardadas).
#   Regla del proyecto: nada de Controls estáticos creados por código
#   (ver docs/AUDITORIA_UI_CODIGO_2026-07-16.md).
# ============================================================

const SIM_SCENE_PATH: String = "res://scenes/SimulationScene.tscn"
const EDITOR_SCENE_PATH: String = "res://scenes/ScenarioEditorScene.tscn"
const RUNTIME_TEMPLATE_PATH: String = "user://last_editor_runtime_template.json"
const STARTUP_OPTIONS_PATH: String = "user://startup_sim_options.json"
const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")
const SimuFireThemeScript = preload("res://ui/SimuFireTheme.gd")
const UILocalizationScript = preload("res://ui/UILocalization.gd")
const WindRoseScript = preload("res://ui/WindRose.gd")
const ScenarioCardScene = preload("res://ui/ScenarioCard.tscn")
## Los ocho mandos viven detras de "Retocar", en un panel modal aparte del VBox
## de la portada. El camino se escribe una vez.
const TWEAK_ROWS: String = "TweakCenter/TweakPanel/Pad/Rows/"
## La configuracion del PROGRAMA -idioma y calidad- vive en su propio panel
## modal, aparte de los ajustes de la SIMULACION: una es de la maquina y de
## quien la usa, la otra del caso que se simula.
const SETTINGS_ROWS: String = "SettingsCenter/SettingsPanel/Pad/Rows/"
const AppSettingsScript = preload("res://ui/AppSettings.gd")
const GraphicsQualityScript = preload("res://ui/GraphicsQuality.gd")

var _template_builder = BuildingTemplateScript.new()
## La lista de escenarios sustituye al desplegable de plantilla: la portada
## ensena de que va cada uno sin tener que abrirlo.
var _scenario_list: VBoxContainer = null
var _scenario_cards: Array[Button] = []
var _scenario_group: ButtonGroup = ButtonGroup.new()
var _selected_preset_index: int = 0
var _summary_label: Label = null
var _tweak_dim: Control = null
var _tweak_center: Control = null
var _settings_dim: Control = null
var _settings_center: Control = null
var _locale_option: OptionButton = null
var _settings_locale_option: OptionButton = null
var _quality_option: OptionButton = null
var _hvac_option: OptionButton = null
var _lighting_option: OptionButton = null
var _interior_lights_option: OptionButton = null
var _glass_break_option: OptionButton = null
var _visibility_option: OptionButton = null
var _building_type_option: OptionButton = null
var _apartment_floor_spin: SpinBox = null
var _total_floors_spin: SpinBox = null
var _wind_dir_option: OptionButton = null
var _wind_speed_spin: SpinBox = null
var _preset_ids: Array[String] = []
var _hvac_modes: Array[String] = ["none", "off", "on"]
var _lighting_modes: Array[String] = ["Dia", "Noche"]
var _glass_break_modes: Array[int] = [0, 1, 2]
var _building_type_modes: Array[String] = ["single_family", "apartment"]


func _ready() -> void:
	UILocalizationScript.ensure_loaded()
	if _is_validation_mode():
		_open_validation_scene_next_frame()
		return
	_fit_window_to_screen()
	GraphicsQualityScript.apply_to_viewport(get_viewport(), AppSettingsScript.quality())
	RenderingServer.set_default_clear_color(SimuFireThemeScript.BG)
	if not _bind_existing_ui():
		push_error("MainMenu: faltan nodos en MainMenu.tscn — la escena es la fuente de verdad de este menu")
		return
	_localize_texts()
	# Diferido: el tamaño real del viewport solo está listo tras el primer layout.
	_fit_main_menu_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_main_menu_layout()


## Si la ventana es más grande que la zona útil de la pantalla (barra de tareas
## y de título incluidas), la encoge para que no se salga del monitor, y la
## centra. Solo reduce, nunca agranda. No toca fullscreen/maximizado.
func _fit_window_to_screen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		return
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var title_allowance: int = 40  # hueco para la barra de título de la ventana
	var win_size: Vector2i = DisplayServer.window_get_size()
	# Si ya cabe, no tocar nada (respeta ventana embebida en el editor, etc.).
	if win_size.x <= usable.size.x and win_size.y <= usable.size.y - title_allowance:
		return
	var target := Vector2i(
		mini(win_size.x, usable.size.x),
		mini(win_size.y, usable.size.y - title_allowance))
	if target != win_size:
		DisplayServer.window_set_size(target)
	# Centrar en la zona útil, dejando el hueco de la barra de título arriba.
	var final_size: Vector2i = DisplayServer.window_get_size()
	var pos := Vector2i(
		usable.position.x + (usable.size.x - final_size.x) / 2,
		usable.position.y + title_allowance / 2 \
			+ (usable.size.y - title_allowance - final_size.y) / 2)
	DisplayServer.window_set_position(pos)


func _open_validation_scene_next_frame() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file(SIM_SCENE_PATH)


func _bind_existing_ui() -> bool:
	var btn_new := get_node_or_null("Center/VBox/ActionsRow/BtnNewSim") as Button
	var btn_tweak := get_node_or_null("Center/VBox/ActionsRow/BtnTweak") as Button
	var btn_editor := get_node_or_null("Center/VBox/SecondaryRow/BtnEditor") as Button
	var btn_quit := get_node_or_null("Center/VBox/SecondaryRow/BtnQuit") as Button
	var btn_tweak_close := get_node_or_null(TWEAK_ROWS + "BtnTweakClose") as Button
	if btn_new == null or btn_tweak == null or btn_editor == null or btn_quit == null 			or btn_tweak_close == null:
		return false
	_connect_once(btn_new.pressed, _on_new_sim_pressed)
	_connect_once(btn_tweak.pressed, _on_tweak_pressed)
	_connect_once(btn_editor.pressed, _on_editor_pressed)
	_connect_once(btn_quit.pressed, _on_quit_pressed)
	_connect_once(btn_tweak_close.pressed, _on_tweak_close_pressed)

	_scenario_list = get_node_or_null("Center/VBox/ScenarioScroll/ScenarioList") as VBoxContainer
	_summary_label = get_node_or_null("Center/VBox/Summary") as Label
	_tweak_dim = get_node_or_null("TweakDim") as Control
	_tweak_center = get_node_or_null("TweakCenter") as Control
	if _scenario_list == null or _summary_label == null 			or _tweak_dim == null or _tweak_center == null:
		return false

	_building_type_option = get_node_or_null(TWEAK_ROWS + "BuildingTypeRow/Option") as OptionButton
	_apartment_floor_spin = get_node_or_null(TWEAK_ROWS + "ApartmentFloorRow/Spin") as SpinBox
	_total_floors_spin = get_node_or_null(TWEAK_ROWS + "TotalFloorsRow/Spin") as SpinBox
	_wind_dir_option = get_node_or_null(TWEAK_ROWS + "WindDirRow/Option") as OptionButton
	_wind_speed_spin = get_node_or_null(TWEAK_ROWS + "WindSpeedRow/Spin") as SpinBox
	_hvac_option = get_node_or_null(TWEAK_ROWS + "HvacRow/Option") as OptionButton
	_lighting_option = get_node_or_null(TWEAK_ROWS + "LightingRow/Option") as OptionButton
	_interior_lights_option = get_node_or_null(TWEAK_ROWS + "InteriorLightsRow/Option") as OptionButton
	_glass_break_option = get_node_or_null(TWEAK_ROWS + "GlassBreakRow/Option") as OptionButton
	_visibility_option = get_node_or_null(TWEAK_ROWS + "VisibilityRow/Option") as OptionButton
	if _building_type_option == null or _apartment_floor_spin == null 			or _hvac_option == null or _lighting_option == null or _glass_break_option == null 			or _interior_lights_option == null or _visibility_option == null:
		return false

	# Patron del proyecto: la escena se guarda VISIBLE -para poder componer el
	# panel dentro de Godot- y es el codigo quien lo esconde al arrancar.
	_tweak_dim.visible = false
	_tweak_center.visible = false

	_bind_settings_panel()
	_populate_scenario_cards()
	_populate_building_type_option()
	_populate_apartment_floor_spin()
	_populate_total_floors_spin()
	_populate_wind_controls()
	_populate_hvac_option()
	_populate_lighting_option()
	_populate_interior_lights_option()
	_populate_glass_break_option()
	_populate_visibility_option()
	_connect_once(_building_type_option.item_selected, _on_building_type_selected)
	# Cualquier mando que cambie reescribe el resumen de la portada: es lo que
	# permite tener los ajustes escondidos sin que se olvide lo que valen.
	for opt in [_building_type_option, _hvac_option, _lighting_option,
			_interior_lights_option, _glass_break_option, _visibility_option]:
		_connect_once((opt as OptionButton).item_selected, _on_any_option_changed)
	_connect_once(_apartment_floor_spin.value_changed, _on_apartment_floor_changed)
	_connect_once(_total_floors_spin.value_changed, _on_total_floors_changed)
	_connect_once(_wind_speed_spin.value_changed, _on_any_option_changed)
	_connect_once(_wind_dir_option.item_selected, _on_any_option_changed)
	_sync_apartment_floor_visibility()
	_update_summary()
	return true


## Idioma y calidad: el selector rapido de la esquina y el panel completo.
##
## Los dos selectores de idioma mandan a lo mismo, asi que se sincronizan entre
## si: cambiar en uno y que el otro siga diciendo lo de antes seria mentir.
func _bind_settings_panel() -> void:
	_settings_dim = get_node_or_null("SettingsDim") as Control
	_settings_center = get_node_or_null("SettingsCenter") as Control
	_locale_option = get_node_or_null("TopRightRow/LocaleOption") as OptionButton
	_settings_locale_option = get_node_or_null(SETTINGS_ROWS + "LanguageRow/Option") as OptionButton
	_quality_option = get_node_or_null(SETTINGS_ROWS + "QualityRow/Option") as OptionButton
	var btn_settings := get_node_or_null("TopRightRow/BtnSettings") as Button
	var btn_close := get_node_or_null(SETTINGS_ROWS + "BtnSettingsClose") as Button
	if _settings_dim == null or _settings_center == null:
		push_error("MainMenu: falta el panel de configuracion en MainMenu.tscn")
		return
	# Como el de Retocar: la escena lo guarda visible para poder componerlo, y
	# lo esconde el codigo.
	_settings_dim.visible = false
	_settings_center.visible = false

	for option in [_locale_option, _settings_locale_option]:
		if option == null:
			continue
		option.clear()
		for entry in UILocalizationScript.AVAILABLE_LOCALES:
			option.add_item(String(entry.get("name", "?")))
		option.select(UILocalizationScript.locale_index(UILocalizationScript.current_locale()))
		_connect_once(option.item_selected, _on_locale_selected)

	if _quality_option != null:
		_quality_option.clear()
		for level in AppSettingsScript.QUALITY_ORDER:
			_quality_option.add_item(AppSettingsScript.quality_label(level))
		_quality_option.select(AppSettingsScript.QUALITY_ORDER.find(AppSettingsScript.quality()))
		_connect_once(_quality_option.item_selected, _on_quality_selected)

	if btn_settings != null:
		_connect_once(btn_settings.pressed, _on_settings_pressed)
	if btn_close != null:
		_connect_once(btn_close.pressed, _on_settings_close_pressed)


func _on_locale_selected(index: int) -> void:
	var locales: Array[Dictionary] = UILocalizationScript.AVAILABLE_LOCALES
	if index < 0 or index >= locales.size():
		return
	UILocalizationScript.set_locale(String(locales[index].get("code", "es")))
	for option in [_locale_option, _settings_locale_option]:
		if option != null and option.selected != index:
			option.select(index)
	# El resumen de la portada se arma en codigo: hay que rehacerlo a mano.
	_update_summary()


func _on_quality_selected(index: int) -> void:
	if index < 0 or index >= AppSettingsScript.QUALITY_ORDER.size():
		return
	AppSettingsScript.set_quality(AppSettingsScript.QUALITY_ORDER[index])
	GraphicsQualityScript.apply_to_viewport(get_viewport(), AppSettingsScript.quality())


func _on_settings_pressed() -> void:
	_set_settings_shown(true)


func _on_settings_close_pressed() -> void:
	_set_settings_shown(false)


func _set_settings_shown(shown: bool) -> void:
	if _settings_dim != null:
		_settings_dim.visible = shown
	if _settings_center != null:
		_settings_center.visible = shown
	if not shown:
		return
	# Al abrir se releen los dos mandos del idioma y el de la calidad: si algo
	# los cambio por otro camino, el panel tiene que decir la verdad.
	_sync_settings_controls()
	if _settings_locale_option != null:
		_settings_locale_option.grab_focus()


func _sync_settings_controls() -> void:
	var locale_index: int = UILocalizationScript.locale_index(UILocalizationScript.current_locale())
	for option in [_locale_option, _settings_locale_option]:
		if option != null and option.selected != locale_index:
			option.select(locale_index)
	if _quality_option != null:
		var quality_index: int = AppSettingsScript.QUALITY_ORDER.find(AppSettingsScript.quality())
		if quality_index >= 0 and _quality_option.selected != quality_index:
			_quality_option.select(quality_index)


func _connect_once(target_signal: Signal, target_callable: Callable) -> void:
	if not target_signal.is_connected(target_callable):
		target_signal.connect(target_callable)


func _ui_text(key: String, fallback: String) -> String:
	return UILocalizationScript.t(key, fallback)


func _localize_texts() -> void:
	_set_label_text("Center/VBox/Subtitle", _ui_text("main.subtitle", "SIMULADOR TACTICO DE INCENDIOS"))
	_set_label_text("Center/VBox/ScenarioLabel", _ui_text("main.scenario", "Escenario").to_upper())
	_set_label_text(TWEAK_ROWS + "TweakTitle", _ui_text("main.tweak_title", "Ajustes de la simulacion").to_upper())
	_set_label_text(TWEAK_ROWS + "BuildingTypeRow/BuildingTypeLabel", _ui_text("main.building_type", "Exterior").to_upper())
	_set_label_text(TWEAK_ROWS + "ApartmentFloorRow/ApartmentFloorLabel", _ui_text("main.apartment_floor", "Planta").to_upper())
	_set_label_text(TWEAK_ROWS + "TotalFloorsRow/TotalFloorsLabel", _ui_text("main.total_floors", "De un total de").to_upper())
	_set_label_text(TWEAK_ROWS + "WindDirRow/WindDirLabel", _ui_text("main.wind_direction", "Viento del").to_upper())
	_set_label_text(TWEAK_ROWS + "WindSpeedRow/WindSpeedLabel", _ui_text("main.wind_speed", "Velocidad").to_upper())
	_set_label_text(TWEAK_ROWS + "HvacRow/HvacLabel", _ui_text("main.hvac", "HVAC").to_upper())
	_set_label_text(TWEAK_ROWS + "LightingRow/LightingLabel", _ui_text("main.lighting", "Iluminacion").to_upper())
	_set_label_text(TWEAK_ROWS + "InteriorLightsRow/InteriorLightsLabel", _ui_text("main.interior_lights", "Luces int.").to_upper())
	_set_label_text(TWEAK_ROWS + "GlassBreakRow/GlassBreakLabel", _ui_text("main.glass_break", "Cristales").to_upper())
	_set_label_text(TWEAK_ROWS + "VisibilityRow/VisibilityLabel", _ui_text("main.visibility", "Visibilidad").to_upper())
	_set_button_text("Center/VBox/ActionsRow/BtnNewSim", _ui_text("main.start_simulation", "EMPEZAR"))
	_set_button_text("Center/VBox/ActionsRow/BtnTweak", _ui_text("main.tweak", "Retocar..."))
	_set_button_text("Center/VBox/SecondaryRow/BtnEditor", _ui_text("main.open_editor", "EDITOR DE VIVIENDA"))
	_set_button_text("Center/VBox/SecondaryRow/BtnQuit", _ui_text("main.quit", "SALIR"))
	_set_button_text(TWEAK_ROWS + "BtnTweakClose", _ui_text("main.tweak_done", "Listo"))


func _set_label_text(path: String, value: String) -> void:
	var label := get_node_or_null(path) as Label
	if label != null:
		label.text = value


func _set_button_text(path: String, value: String) -> void:
	var button := get_node_or_null(path) as Button
	if button != null:
		button.text = value.to_upper()


## Adapta el menu a la altura real de la ventana.
##
## Antes esta funcion tenia que encoger el logo, los botones Y las once filas de
## mandos hasta que cupieran, porque el menu pedia 719 px en una ventana de 720.
## Ahora los mandos viven detras de "Retocar" y solo quedan dos cosas elasticas:
## el logo y la altura de la lista de escenarios. Lo que se recorta es la lista,
## que ademas tiene barra, asi que nada deja de ser alcanzable.
func _fit_main_menu_layout() -> void:
	var vbox := get_node_or_null("Center/VBox") as VBoxContainer
	if vbox == null:
		return
	vbox.scale = Vector2.ONE
	var center := get_node_or_null("Center") as Control
	var viewport_h: float = get_viewport_rect().size.y
	if center != null and center.size.y > 1.0:
		viewport_h = center.size.y

	var logo := vbox.get_node_or_null("Logo") as TextureRect
	var scroll := vbox.get_node_or_null("ScenarioScroll") as ScrollContainer
	# Ojo con lo que se mide: el stretch del proyecto da una altura LOGICA que
	# no baja de 720 aunque la ventana sea mas baja -a 1000x650 el viewport 2D
	# es 1280x832-. Por eso el caso peor real es 720, y los dos escalones de
	# abajo son la red por si algun dia cambia el modo de stretch.
	var logo_h: float = 150.0
	var list_h: float = 214.0
	if viewport_h < 820.0:
		logo_h = 120.0
	if viewport_h < 700.0:
		logo_h = 92.0
		list_h = 160.0
	if viewport_h < 600.0:
		logo_h = 70.0
		list_h = 106.0
	if logo != null:
		logo.custom_minimum_size = Vector2(430.0, logo_h)
	if scroll != null:
		scroll.custom_minimum_size = Vector2(430.0, list_h)

	# Ultimo recurso: si aun no cabe, lo que cede es la lista, nunca los botones.
	var over: float = vbox.get_combined_minimum_size().y - viewport_h * 0.98
	if over > 0.0 and scroll != null:
		scroll.custom_minimum_size = Vector2(430.0, maxf(50.0, list_h - over))


## Una ficha por escenario, con su nombre y de que va.
##
## El texto sale de get_preset_definitions(), que ya trae "name" y
## "description": no se inventa aqui ninguna descripcion. Las fichas se crean
## por codigo porque son CONTENIDO, no cromo -la regla del proyecto prohibe
## Controls estaticos por codigo, y por eso la ficha es una escena,
## ui/ScenarioCard.tscn, igual que HudCard.tscn-.
func _populate_scenario_cards() -> void:
	if _scenario_list == null:
		return
	for child in _scenario_list.get_children():
		child.queue_free()
	_scenario_cards.clear()

	var presets: Array[Dictionary] = _template_builder.get_preset_definitions()
	_preset_ids.clear()
	for preset in presets:
		_preset_ids.append(String(preset.get("id", "simple_house")))

	var saved: Dictionary = _load_startup_options()
	var selected_id: String = String(saved.get("template_name", "simple_house"))
	_selected_preset_index = maxi(0, _preset_ids.find(selected_id))

	for i in range(presets.size()):
		var preset: Dictionary = presets[i]
		var card := ScenarioCardScene.instantiate() as Button
		card.name = "Card%d" % i
		card.button_group = _scenario_group
		var name_label := card.get_node_or_null("Box/Name") as Label
		var desc_label := card.get_node_or_null("Box/Desc") as Label
		if name_label != null:
			name_label.text = String(preset.get("name", _preset_ids[i]))
		if desc_label != null:
			desc_label.text = String(preset.get("description", ""))
		card.tooltip_text = String(preset.get("description", ""))
		card.set_meta("preset_index", i)
		card.toggled.connect(_on_scenario_card_toggled.bind(i))
		_scenario_list.add_child(card)
		_scenario_cards.append(card)

	if _selected_preset_index < _scenario_cards.size():
		_scenario_cards[_selected_preset_index].button_pressed = true


func _on_scenario_card_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		return
	_selected_preset_index = index
	_update_summary()


## El resumen de la portada: lo que valen ahora mismo los mandos escondidos.
##
## Existe porque esconder los ajustes solo es aceptable si desde fuera se ve en
## que estado estan. Sin esta linea, "Retocar" seria una caja negra.
func _update_summary() -> void:
	if _summary_label == null:
		return
	var partes: Array[String] = []

	if _building_type_option != null:
		if _building_type_option.selected == 1:
			var planta: int = 1
			if _apartment_floor_spin != null:
				planta = int(round(_apartment_floor_spin.value))
			# 0 es la baja y los negativos son sotanos: decirlo con numero
			# ("planta 0", "planta -2") no se entiende de un vistazo.
			var totales: int = planta + 1
			if _total_floors_spin != null:
				totales = maxi(planta + 1, int(round(_total_floors_spin.value)))
			# La convencion es la del 2026-09-10: la rasante es R y encima
			# R+1, R+2. El resumen decia «planta 15 de 20» y el resto del
			# programa «R+15»; dos formas de decir lo mismo en la misma
			# pantalla es una de mas.
			partes.append(tr("piso, %s de %d plantas") % [FloorNaming.label(planta), totales])
		else:
			partes.append("casa unifamiliar")

	if _wind_speed_spin != null and _wind_dir_option != null:
		var rumbo: float = WindRoseScript.degrees_for_index(_wind_dir_option.selected)
		partes.append(WindRoseScript.summary_text(_wind_speed_spin.value, rumbo))
	if _lighting_option != null:
		partes.append("de dia" if _lighting_option.selected == 0 else "de noche")
	if _interior_lights_option != null:
		partes.append("luces encendidas" if _interior_lights_option.selected == 0 else "luces apagadas")
	if _hvac_option != null:
		match _hvac_option.selected:
			1: partes.append("HVAC parado")
			2: partes.append("HVAC en marcha")
			_: partes.append("sin HVAC")
	if _glass_break_option != null:
		match _glass_break_option.selected:
			1: partes.append("cristales por temperatura")
			2: partes.append("cristales probabilistico")
			_: partes.append("cristales sin rotura")
	if _visibility_option != null and _visibility_option.selected == 1:
		partes.append("humo solo en el HUD")

	_summary_label.text = " · ".join(partes)


func _on_any_option_changed(_value) -> void:
	_sync_apartment_floor_visibility()
	_update_summary()


func _on_tweak_pressed() -> void:
	_set_tweak_visible(true)


func _on_tweak_close_pressed() -> void:
	_set_tweak_visible(false)


func _set_tweak_visible(shown: bool) -> void:
	if _tweak_dim != null:
		_tweak_dim.visible = shown
	if _tweak_center != null:
		_tweak_center.visible = shown
	if shown:
		var first := get_node_or_null(TWEAK_ROWS + "BuildingTypeRow/Option") as Control
		if first != null:
			first.grab_focus()
	else:
		_update_summary()
		var btn := get_node_or_null("Center/VBox/ActionsRow/BtnTweak") as Control
		if btn != null:
			btn.grab_focus()


## Escape cierra los ajustes, que es lo que espera cualquiera.
func _unhandled_input(event: InputEvent) -> void:
	if _tweak_center == null or not _tweak_center.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_set_tweak_visible(false)
		get_viewport().set_input_as_handled()


## Los dos mandos del viento. La rosa la pone `WindRose`, que es la que sabe
## que los grados del motor son "de donde VIENE" y no "hacia donde va".
func _populate_wind_controls() -> void:
	if _wind_dir_option == null or _wind_speed_spin == null:
		return
	if _wind_dir_option.item_count == 0:
		for punto in WindRoseScript.POINTS:
			_wind_dir_option.add_item(String(punto["nombre"]))
	var saved: Dictionary = _load_startup_options()
	_wind_speed_spin.max_value = WindRoseScript.MAX_SPEED_M_S
	_wind_speed_spin.step = WindRoseScript.SPEED_STEP_M_S
	_wind_speed_spin.value = clampf(float(saved.get("wind_speed_m_s", 0.0)), 0.0, WindRoseScript.MAX_SPEED_M_S)
	_wind_dir_option.select(WindRoseScript.index_for_degrees(float(saved.get("wind_direction_deg", 0.0))))


func _populate_hvac_option() -> void:
	if _hvac_option == null:
		return

	if _hvac_option.get_item_count() == 0:
		_hvac_option.add_item(_ui_text("main.hvac.none", "Sin HVAC"), 0)
		_hvac_option.add_item(_ui_text("main.hvac.off", "HVAC instalado OFF"), 1)
		_hvac_option.add_item(_ui_text("main.hvac.on", "HVAC instalado ON"), 2)
	var saved: Dictionary = _load_startup_options()
	var selected_mode: String = String(saved.get("hvac_mode", "none"))
	var selected_index: int = maxi(0, _hvac_modes.find(selected_mode))
	if _hvac_option.get_item_count() > 0:
		_hvac_option.select(clampi(selected_index, 0, _hvac_option.get_item_count() - 1))


func _populate_building_type_option() -> void:
	if _building_type_option == null:
		return
	if _building_type_option.get_item_count() == 0:
		_building_type_option.add_item(_ui_text("main.building.single_family", "Casa unifamiliar"), 0)
		_building_type_option.add_item(_ui_text("main.building.apartment", "Piso"), 1)
	var saved: Dictionary = _load_startup_options()
	var selected_mode: String = String(saved.get("building_type", "single_family")).to_lower()
	var selected_index: int = maxi(0, _building_type_modes.find(selected_mode))
	if _building_type_option.get_item_count() > 0:
		_building_type_option.select(clampi(selected_index, 0, _building_type_option.get_item_count() - 1))


func _populate_apartment_floor_spin() -> void:
	if _apartment_floor_spin == null:
		return
	var saved: Dictionary = _load_startup_options()
	_apartment_floor_spin.value = maxi(0, int(saved.get("apartment_floor_number", 1)))


func _populate_total_floors_spin() -> void:
	if _total_floors_spin == null:
		return
	var saved: Dictionary = _load_startup_options()
	var planta: int = maxi(0, int(saved.get("apartment_floor_number", 1)))
	_total_floors_spin.value = maxi(planta + 1, int(saved.get("building_total_floors", planta + 1)))
	_sync_floor_limits()


## Los dos datos no son independientes: el edificio no puede tener menos
## plantas que la planta en la que se vive. Se cruzan los limites en vez de
## dejar elegir una combinacion imposible y corregirla despues por detras.
func _sync_floor_limits() -> void:
	if _apartment_floor_spin == null or _total_floors_spin == null:
		return
	_total_floors_spin.min_value = _apartment_floor_spin.value + 1.0
	_apartment_floor_spin.max_value = maxf(0.0, _total_floors_spin.max_value - 1.0)


func _on_apartment_floor_changed(_value: float) -> void:
	if _total_floors_spin != null and _total_floors_spin.value < _apartment_floor_spin.value + 1.0:
		_total_floors_spin.value = _apartment_floor_spin.value + 1.0
	_sync_floor_limits()
	_on_any_option_changed(0)


func _on_total_floors_changed(_value: float) -> void:
	_sync_floor_limits()
	_on_any_option_changed(0)


func _on_building_type_selected(_index: int) -> void:
	_sync_apartment_floor_visibility()


func _sync_apartment_floor_visibility() -> void:
	var es_piso: bool = _building_type_option != null and _building_type_option.selected == 1
	for spin in [_apartment_floor_spin, _total_floors_spin]:
		if spin == null:
			continue
		var row := (spin as Control).get_parent() as Control
		if row != null:
			row.visible = es_piso


func _populate_lighting_option() -> void:
	if _lighting_option == null:
		return

	if _lighting_option.get_item_count() == 0:
		_lighting_option.add_item(_ui_text("main.lighting.day", "Dia exterior"), 0)
		_lighting_option.add_item(_ui_text("main.lighting.night", "Noche exterior"), 1)
	var saved: Dictionary = _load_startup_options()
	var selected_mode: String = String(saved.get("exterior_lighting_mode", "Dia"))
	var selected_index: int = maxi(0, _lighting_modes.find(selected_mode))
	if _lighting_option.get_item_count() > 0:
		_lighting_option.select(clampi(selected_index, 0, _lighting_option.get_item_count() - 1))


func _populate_interior_lights_option() -> void:
	if _interior_lights_option == null:
		return

	if _interior_lights_option.get_item_count() == 0:
		_interior_lights_option.add_item(_ui_text("main.interior.on", "Interiores ON"), 0)
		_interior_lights_option.add_item(_ui_text("main.interior.off", "Interiores OFF"), 1)
	var saved: Dictionary = _load_startup_options()
	var enabled: bool = bool(saved.get("interior_lights_on", true))
	_interior_lights_option.select(0 if enabled else 1)


func _populate_glass_break_option() -> void:
	if _glass_break_option == null:
		return

	if _glass_break_option.get_item_count() == 0:
		_glass_break_option.add_item(_ui_text("main.glass.none", "Sin rotura"), 0)
		_glass_break_option.add_item(_ui_text("main.glass.temperature", "Umbral temp."), 1)
		_glass_break_option.add_item(_ui_text("main.glass.probabilistic", "Probabilistica"), 2)
	var saved: Dictionary = _load_startup_options()
	var selected_mode: int = int(saved.get("glass_break_mode", 0))
	var selected_index: int = maxi(0, _glass_break_modes.find(selected_mode))
	if _glass_break_option.get_item_count() > 0:
		_glass_break_option.select(clampi(selected_index, 0, _glass_break_option.get_item_count() - 1))


func _populate_visibility_option() -> void:
	if _visibility_option == null:
		return
	if _visibility_option.get_item_count() == 0:
		_visibility_option.add_item(_ui_text("main.visibility.on", "Humo reduce visibilidad"), 0)
		_visibility_option.add_item(_ui_text("main.visibility.off", "Sin efecto (solo HUD)"), 1)
	var saved: Dictionary = _load_startup_options()
	var enabled: bool = bool(saved.get("smoke_visibility_representation", true))
	_visibility_option.select(0 if enabled else 1)


func _load_startup_options() -> Dictionary:
	if not FileAccess.file_exists(STARTUP_OPTIONS_PATH):
		return {}
	var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _save_startup_options() -> void:
	var selected_template_id: String = "simple_house"
	if not _preset_ids.is_empty():
		var idx: int = clampi(_selected_preset_index, 0, _preset_ids.size() - 1)
		selected_template_id = _preset_ids[idx]

	var selected_wind_speed: float = 0.0
	if _wind_speed_spin != null:
		selected_wind_speed = clampf(_wind_speed_spin.value, 0.0, WindRoseScript.MAX_SPEED_M_S)
	var selected_wind_direction: float = 0.0
	if _wind_dir_option != null:
		selected_wind_direction = WindRoseScript.degrees_for_index(_wind_dir_option.selected)

	var selected_hvac_mode: String = "none"
	if _hvac_option != null:
		var hvac_idx: int = clampi(_hvac_option.selected, 0, _hvac_modes.size() - 1)
		selected_hvac_mode = _hvac_modes[hvac_idx]

	var selected_lighting_mode: String = "Dia"
	if _lighting_option != null:
		var lighting_idx: int = clampi(_lighting_option.selected, 0, _lighting_modes.size() - 1)
		selected_lighting_mode = _lighting_modes[lighting_idx]

	var selected_interior_lights_on: bool = true
	if _interior_lights_option != null:
		selected_interior_lights_on = _interior_lights_option.selected != 1

	var selected_building_type: String = "single_family"
	if _building_type_option != null:
		var building_idx: int = clampi(_building_type_option.selected, 0, _building_type_modes.size() - 1)
		selected_building_type = _building_type_modes[building_idx]

	var selected_apartment_floor: int = 1
	if _apartment_floor_spin != null:
		selected_apartment_floor = maxi(0, int(round(_apartment_floor_spin.value)))
	var selected_total_floors: int = selected_apartment_floor + 1
	if _total_floors_spin != null:
		selected_total_floors = maxi(selected_apartment_floor + 1, int(round(_total_floors_spin.value)))

	var selected_glass_break_mode: int = 0
	if _glass_break_option != null:
		var glass_idx: int = clampi(_glass_break_option.selected, 0, _glass_break_modes.size() - 1)
		selected_glass_break_mode = _glass_break_modes[glass_idx]

	var selected_visibility_on: bool = true
	if _visibility_option != null:
		selected_visibility_on = _visibility_option.selected != 1

	var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MainMenu: no se pudieron guardar opciones de inicio")
		return
	file.store_string(JSON.stringify({
		"template_name": selected_template_id,
		"building_type": selected_building_type,
		"apartment_floor_number": selected_apartment_floor,
		"building_total_floors": selected_total_floors,
		"wind_speed_m_s": selected_wind_speed,
		"wind_direction_deg": selected_wind_direction,
		"hvac_mode": selected_hvac_mode,
		"exterior_lighting_mode": selected_lighting_mode,
		"interior_lights_on": selected_interior_lights_on,
		"glass_break_mode": selected_glass_break_mode,
		"smoke_visibility_representation": selected_visibility_on
	}, "\t"))
	file.close()


func _on_new_sim_pressed() -> void:
	# Borra la plantilla del editor para que BuildingModel use la plantilla por defecto.
	if FileAccess.file_exists(RUNTIME_TEMPLATE_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove("last_editor_runtime_template.json")
	_save_startup_options()
	get_tree().change_scene_to_file(SIM_SCENE_PATH)


func _on_editor_pressed() -> void:
	get_tree().change_scene_to_file(EDITOR_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _is_validation_mode() -> bool:
	for arg in OS.get_cmdline_user_args():
		var arg_text: String = String(arg)
		if arg_text == "--validation-case" or arg_text.begins_with("--validation-case="):
			return true
	return false
