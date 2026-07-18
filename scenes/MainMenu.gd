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

var _template_builder = BuildingTemplateScript.new()
var _template_option: OptionButton = null
var _hvac_option: OptionButton = null
var _lighting_option: OptionButton = null
var _interior_lights_option: OptionButton = null
var _glass_break_option: OptionButton = null
var _visibility_option: OptionButton = null
var _building_type_option: OptionButton = null
var _apartment_floor_spin: SpinBox = null
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
	RenderingServer.set_default_clear_color(SimuFireThemeScript.BG)
	if not _bind_existing_ui():
		push_error("MainMenu: faltan nodos en MainMenu.tscn — la escena es la fuente de verdad de este menu")
		return
	_localize_texts()
	_fit_main_menu_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_main_menu_layout()


func _open_validation_scene_next_frame() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file(SIM_SCENE_PATH)


func _bind_existing_ui() -> bool:
	var btn_new := get_node_or_null("Center/VBox/BtnNewSim") as Button
	var btn_editor := get_node_or_null("Center/VBox/BtnEditor") as Button
	var btn_quit := get_node_or_null("Center/VBox/BtnQuit") as Button
	if btn_new == null or btn_editor == null or btn_quit == null:
		return false
	_connect_once(btn_new.pressed, _on_new_sim_pressed)
	_connect_once(btn_editor.pressed, _on_editor_pressed)
	_connect_once(btn_quit.pressed, _on_quit_pressed)

	_template_option = get_node_or_null("Center/VBox/PresetRow/Option") as OptionButton
	_building_type_option = get_node_or_null("Center/VBox/BuildingTypeRow/Option") as OptionButton
	_apartment_floor_spin = get_node_or_null("Center/VBox/ApartmentFloorRow/Spin") as SpinBox
	_hvac_option = get_node_or_null("Center/VBox/HvacRow/Option") as OptionButton
	_lighting_option = get_node_or_null("Center/VBox/LightingRow/Option") as OptionButton
	_interior_lights_option = get_node_or_null("Center/VBox/InteriorLightsRow/Option") as OptionButton
	_glass_break_option = get_node_or_null("Center/VBox/GlassBreakRow/Option") as OptionButton
	_visibility_option = get_node_or_null("Center/VBox/VisibilityRow/Option") as OptionButton
	if _template_option == null or _building_type_option == null or _apartment_floor_spin == null \
			or _hvac_option == null or _lighting_option == null or _glass_break_option == null \
			or _interior_lights_option == null or _visibility_option == null:
		return false

	_populate_template_option()
	_populate_building_type_option()
	_populate_apartment_floor_spin()
	_populate_hvac_option()
	_populate_lighting_option()
	_populate_interior_lights_option()
	_populate_glass_break_option()
	_populate_visibility_option()
	_connect_once(_building_type_option.item_selected, _on_building_type_selected)
	_sync_apartment_floor_visibility()
	return true


func _connect_once(target_signal: Signal, target_callable: Callable) -> void:
	if not target_signal.is_connected(target_callable):
		target_signal.connect(target_callable)


func _ui_text(key: String, fallback: String) -> String:
	return UILocalizationScript.t(key, fallback)


func _localize_texts() -> void:
	_set_label_text("Center/VBox/Subtitle", _ui_text("main.subtitle", "SIMULADOR TACTICO DE INCENDIOS"))
	_set_label_text("Center/VBox/PresetRow/PresetLabel", _ui_text("main.template", "Plantilla").to_upper())
	_set_label_text("Center/VBox/BuildingTypeRow/BuildingTypeLabel", _ui_text("main.building_type", "Exterior").to_upper())
	_set_label_text("Center/VBox/ApartmentFloorRow/ApartmentFloorLabel", _ui_text("main.apartment_floor", "Planta piso").to_upper())
	_set_label_text("Center/VBox/LightingRow/LightingLabel", _ui_text("main.lighting", "Iluminacion").to_upper())
	_set_label_text("Center/VBox/InteriorLightsRow/InteriorLightsLabel", _ui_text("main.interior_lights", "Luces int.").to_upper())
	_set_label_text("Center/VBox/GlassBreakRow/GlassBreakLabel", _ui_text("main.glass_break", "Cristales").to_upper())
	_set_label_text("Center/VBox/VisibilityRow/VisibilityLabel", _ui_text("main.visibility", "Visibilidad").to_upper())
	_set_button_text("Center/VBox/BtnNewSim", _ui_text("main.start_simulation", "INICIAR SIMULACION"))
	_set_button_text("Center/VBox/BtnEditor", _ui_text("main.open_editor", "EDITOR DE VIVIENDA"))
	_set_button_text("Center/VBox/BtnQuit", _ui_text("main.quit", "SALIR"))


func _set_label_text(path: String, value: String) -> void:
	var label := get_node_or_null(path) as Label
	if label != null:
		label.text = value


func _set_button_text(path: String, value: String) -> void:
	var button := get_node_or_null(path) as Button
	if button != null:
		button.text = value.to_upper()


func _fit_main_menu_layout() -> void:
	var vbox := get_node_or_null("Center/VBox") as VBoxContainer
	if vbox == null:
		return
	var viewport_h: float = get_viewport_rect().size.y
	var compact: bool = viewport_h < 820.0
	var tight: bool = viewport_h < 700.0
	vbox.add_theme_constant_override("separation", 6 if tight else (8 if compact else 10))
	var logo := vbox.get_node_or_null("Logo") as TextureRect
	if logo != null:
		var logo_h: float = 285.0
		if compact:
			logo_h = 220.0
		if tight:
			logo_h = 160.0
		logo.custom_minimum_size = Vector2(430.0, logo_h)
	for child in vbox.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2(420.0, 40.0 if tight else 44.0)
		elif child is HBoxContainer:
			for row_child in child.get_children():
				if row_child is OptionButton or row_child is SpinBox:
					(row_child as Control).custom_minimum_size = Vector2(250.0, 30.0 if tight else 32.0)


func _populate_template_option() -> void:
	if _template_option == null:
		return

	var presets: Array[Dictionary] = _template_builder.get_preset_definitions()
	_preset_ids.clear()
	_template_option.clear()
	for preset in presets:
		var preset_id: String = String(preset.get("id", "simple_house"))
		_preset_ids.append(preset_id)
	for i in range(presets.size()):
		var preset: Dictionary = presets[i]
		var preset_id: String = _preset_ids[i]
		_template_option.add_item(String(preset.get("name", preset_id)), i)

	var saved: Dictionary = _load_startup_options()
	var selected_id: String = String(saved.get("template_name", "simple_house"))
	var selected_index: int = maxi(0, _preset_ids.find(selected_id))
	if _template_option.get_item_count() > 0:
		_template_option.select(clampi(selected_index, 0, _template_option.get_item_count() - 1))


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
	_apartment_floor_spin.value = int(saved.get("apartment_floor_number", 1))


func _on_building_type_selected(_index: int) -> void:
	_sync_apartment_floor_visibility()


func _sync_apartment_floor_visibility() -> void:
	if _apartment_floor_spin == null:
		return
	var row := _apartment_floor_spin.get_parent() as Control
	if row != null:
		row.visible = _building_type_option != null and _building_type_option.selected == 1


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
	if _template_option != null and not _preset_ids.is_empty():
		var idx: int = clampi(_template_option.selected, 0, _preset_ids.size() - 1)
		selected_template_id = _preset_ids[idx]

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
		selected_apartment_floor = int(round(_apartment_floor_spin.value))

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
