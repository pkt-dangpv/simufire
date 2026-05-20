extends Control
class_name MainMenu

# ============================================================
# MAIN MENU
# ------------------------------------------------------------
# Punto de entrada del proyecto.
# - Modo validación: redirige directamente a SimulationScene.
# - Modo normal: muestra 3 botones.
# ============================================================

const SIM_SCENE_PATH: String = "res://scenes/SimulationScene.tscn"
const EDITOR_SCENE_PATH: String = "res://scenes/ScenarioEditorScene.tscn"
const RUNTIME_TEMPLATE_PATH: String = "user://last_editor_runtime_template.json"
const STARTUP_OPTIONS_PATH: String = "user://startup_sim_options.json"
const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd")
const SimuFireThemeScript = preload("res://ui/SimuFireTheme.gd")

var _template_builder = BuildingTemplateScript.new()
var _template_option: OptionButton = null
var _hvac_option: OptionButton = null
var _lighting_option: OptionButton = null
var _building_type_option: OptionButton = null
var _apartment_floor_spin: SpinBox = null
var _preset_ids: Array[String] = []
var _hvac_modes: Array[String] = ["none", "off", "on"]
var _lighting_modes: Array[String] = ["Dia", "Noche"]
var _building_type_modes: Array[String] = ["single_family", "apartment"]


func _ready() -> void:
	if _is_validation_mode():
		_open_validation_scene_next_frame()
		return
	if not _bind_existing_ui():
		_setup_ui()
	else:
		RenderingServer.set_default_clear_color(SimuFireThemeScript.BG)
	_apply_main_menu_visual_style()


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
	_ensure_start_options_ui()
	return true


func _connect_once(target_signal: Signal, target_callable: Callable) -> void:
	if not target_signal.is_connected(target_callable):
		target_signal.connect(target_callable)


func _setup_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.13, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "SimuFire"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Simulador de incendio estructural"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())
	_ensure_start_options_ui(vbox)

	_add_menu_button(vbox, "INICIAR SIMULACION", _on_new_sim_pressed, "BtnNewSim")
	_add_menu_button(vbox, "EDITOR DE VIVIENDA", _on_editor_pressed, "BtnEditor")
	_add_menu_button(vbox, "SALIR", _on_quit_pressed, "BtnQuit")


func _apply_main_menu_visual_style() -> void:
	RenderingServer.set_default_clear_color(SimuFireThemeScript.BG)
	theme = SimuFireThemeScript.build_theme()

	var bg := get_node_or_null("Background") as ColorRect
	if bg == null:
		bg = ColorRect.new()
		bg.name = "Background"
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		move_child(bg, 0)
	bg.color = SimuFireThemeScript.BG

	var vbox := get_node_or_null("Center/VBox") as VBoxContainer
	if vbox == null:
		return
	vbox.custom_minimum_size = Vector2(430.0, 0.0)
	vbox.add_theme_constant_override("separation", 8)

	var title := vbox.get_node_or_null("Title") as Label
	if title != null:
		title.visible = false

	var logo := vbox.get_node_or_null("Logo") as TextureRect
	if logo == null:
		logo = TextureRect.new()
		logo.name = "Logo"
		logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(logo)
		vbox.move_child(logo, 0)
	logo.texture = load(SimuFireThemeScript.LOGO_PATH) as Texture2D

	var subtitle := vbox.get_node_or_null("Subtitle") as Label
	if subtitle != null:
		subtitle.text = "TACTICAL FIRE SIMULATOR"
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.add_theme_font_override("font", SimuFireThemeScript.title_font())
		subtitle.add_theme_font_size_override("font_size", 16)
		subtitle.add_theme_color_override("font_color", SimuFireThemeScript.MUTED)

	var btn_new := get_node_or_null("Center/VBox/BtnNewSim") as Button
	var btn_editor := get_node_or_null("Center/VBox/BtnEditor") as Button
	var btn_quit := get_node_or_null("Center/VBox/BtnQuit") as Button
	if btn_new != null:
		btn_new.text = "INICIAR SIMULACION"
		btn_new.custom_minimum_size = Vector2(420.0, 44.0)
		btn_new.add_theme_stylebox_override("normal", SimuFireThemeScript.stylebox(Color(0.16, 0.05, 0.01, 0.98), SimuFireThemeScript.ORANGE, 1, 0, Vector2(14.0, 9.0)))
		btn_new.add_theme_stylebox_override("hover", SimuFireThemeScript.stylebox(Color(0.24, 0.07, 0.01, 0.98), SimuFireThemeScript.ORANGE, 1, 0, Vector2(14.0, 9.0)))
	if btn_editor != null:
		btn_editor.text = "EDITOR DE VIVIENDA"
		btn_editor.custom_minimum_size = Vector2(420.0, 44.0)
	if btn_quit != null:
		btn_quit.text = "SALIR"
		btn_quit.custom_minimum_size = Vector2(420.0, 44.0)

	SimuFireThemeScript.apply_control_tree(vbox)
	if subtitle != null:
		subtitle.add_theme_font_override("font", SimuFireThemeScript.title_font())
		subtitle.add_theme_font_size_override("font_size", 16)
		subtitle.add_theme_color_override("font_color", SimuFireThemeScript.MUTED)
	_fit_main_menu_layout()


func _ensure_start_options_ui(parent_override: Control = null) -> void:
	var vbox: Control = parent_override
	if vbox == null:
		vbox = get_node_or_null("Center/VBox") as Control
	if vbox == null:
		return

	var preset_row := vbox.get_node_or_null("PresetRow") as HBoxContainer
	if preset_row == null:
		preset_row = _make_option_row("PresetRow", "Plantilla")
		vbox.add_child(preset_row)
		_move_before_first_button(vbox, preset_row)
	_template_option = preset_row.get_node_or_null("Option") as OptionButton
	_populate_template_option()

	var building_row := vbox.get_node_or_null("BuildingTypeRow") as HBoxContainer
	if building_row == null:
		building_row = _make_option_row("BuildingTypeRow", "Exterior")
		vbox.add_child(building_row)
		_move_before_first_button(vbox, building_row)
	_building_type_option = building_row.get_node_or_null("Option") as OptionButton
	_populate_building_type_option()
	if _building_type_option != null:
		_connect_once(_building_type_option.item_selected, _on_building_type_selected)

	var apartment_floor_row := vbox.get_node_or_null("ApartmentFloorRow") as HBoxContainer
	if apartment_floor_row == null:
		apartment_floor_row = _make_spin_row("ApartmentFloorRow", "Planta piso", -5.0, 80.0, 1.0)
		vbox.add_child(apartment_floor_row)
		_move_before_first_button(vbox, apartment_floor_row)
	_apartment_floor_spin = apartment_floor_row.get_node_or_null("Spin") as SpinBox
	_populate_apartment_floor_spin()
	_sync_apartment_floor_visibility()

	var hvac_row := vbox.get_node_or_null("HvacRow") as HBoxContainer
	if hvac_row == null:
		hvac_row = _make_option_row("HvacRow", "HVAC")
		vbox.add_child(hvac_row)
		_move_before_first_button(vbox, hvac_row)
	_hvac_option = hvac_row.get_node_or_null("Option") as OptionButton
	_populate_hvac_option()

	var lighting_row := vbox.get_node_or_null("LightingRow") as HBoxContainer
	if lighting_row == null:
		lighting_row = _make_option_row("LightingRow", "Iluminacion")
		vbox.add_child(lighting_row)
		_move_before_first_button(vbox, lighting_row)
	_lighting_option = lighting_row.get_node_or_null("Option") as OptionButton
	_populate_lighting_option()
	_fit_main_menu_layout()


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


func _make_option_row(row_name: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.name = row_name.replace("Row", "Label")
	label.custom_minimum_size = Vector2(92.0, 0.0)
	label.text = label_text
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "Option"
	option.custom_minimum_size = Vector2(250.0, 34.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return row


func _make_spin_row(row_name: String, label_text: String, min_value: float, max_value: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.name = row_name.replace("Row", "Label")
	label.custom_minimum_size = Vector2(92.0, 0.0)
	label.text = label_text
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = "Spin"
	spin.custom_minimum_size = Vector2(250.0, 34.0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.rounded = true
	row.add_child(spin)
	return row


func _move_before_first_button(parent: Control, child: Control) -> void:
	for i in range(parent.get_child_count()):
		if parent.get_child(i) is Button:
			parent.move_child(child, i)
			return


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
		_hvac_option.add_item("Sin HVAC", 0)
		_hvac_option.add_item("HVAC instalado OFF", 1)
		_hvac_option.add_item("HVAC instalado ON", 2)
	var saved: Dictionary = _load_startup_options()
	var selected_mode: String = String(saved.get("hvac_mode", "none"))
	var selected_index: int = maxi(0, _hvac_modes.find(selected_mode))
	if _hvac_option.get_item_count() > 0:
		_hvac_option.select(clampi(selected_index, 0, _hvac_option.get_item_count() - 1))


func _populate_building_type_option() -> void:
	if _building_type_option == null:
		return
	if _building_type_option.get_item_count() == 0:
		_building_type_option.add_item("Casa unifamiliar", 0)
		_building_type_option.add_item("Piso", 1)
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
		_lighting_option.add_item("Dia exterior", 0)
		_lighting_option.add_item("Noche exterior", 1)
	var saved: Dictionary = _load_startup_options()
	var selected_mode: String = String(saved.get("exterior_lighting_mode", "Dia"))
	var selected_index: int = maxi(0, _lighting_modes.find(selected_mode))
	if _lighting_option.get_item_count() > 0:
		_lighting_option.select(clampi(selected_index, 0, _lighting_option.get_item_count() - 1))


func _add_menu_button(parent: Control, text: String, callback: Callable, node_name: String = "") -> void:
	var btn := Button.new()
	if not node_name.is_empty():
		btn.name = node_name
	btn.text = text
	btn.custom_minimum_size = Vector2(420.0, 48.0)
	btn.pressed.connect(callback)
	parent.add_child(btn)


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

	var selected_building_type: String = "single_family"
	if _building_type_option != null:
		var building_idx: int = clampi(_building_type_option.selected, 0, _building_type_modes.size() - 1)
		selected_building_type = _building_type_modes[building_idx]

	var selected_apartment_floor: int = 1
	if _apartment_floor_spin != null:
		selected_apartment_floor = int(round(_apartment_floor_spin.value))

	var file := FileAccess.open(STARTUP_OPTIONS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MainMenu: no se pudieron guardar opciones de inicio")
		return
	file.store_string(JSON.stringify({
		"template_name": selected_template_id,
		"building_type": selected_building_type,
		"apartment_floor_number": selected_apartment_floor,
		"hvac_mode": selected_hvac_mode,
		"exterior_lighting_mode": selected_lighting_mode
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
