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


func _ready() -> void:
	if _is_validation_mode():
		get_tree().change_scene_to_file(SIM_SCENE_PATH)
		return
	_setup_ui()


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

	_add_menu_button(vbox, "▶  Nueva simulación (plantilla por defecto)", _on_new_sim_pressed)
	_add_menu_button(vbox, "✏  Editor de vivienda", _on_editor_pressed)
	_add_menu_button(vbox, "✗  Salir", _on_quit_pressed)


func _add_menu_button(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320.0, 52.0)
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _on_new_sim_pressed() -> void:
	# Borra la plantilla del editor para que BuildingModel use la plantilla por defecto.
	if FileAccess.file_exists(RUNTIME_TEMPLATE_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove("last_editor_runtime_template.json")
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
