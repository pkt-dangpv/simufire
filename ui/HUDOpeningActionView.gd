extends RefCounted
class_name HUDOpeningActionView

const UILocalizationScript = preload("res://ui/UILocalization.gd")
## Esqueleto del panel editable en scenes/OpeningActionPanel.tscn; aqui
## solo se instancia y se anaden los botones dinamicos (uno por paso).
const OpeningActionPanelScene: PackedScene = preload("res://ui/OpeningActionPanel.tscn")
const DEFAULT_PANEL_SIZE: Vector2 = Vector2(310.0, 92.0)
const VIEWPORT_MARGIN_PX: float = 8.0
const BOTTOM_RESERVED_PX: float = 118.0


static func create(parent: Control, steps: Array[float], pressed_callback: Callable) -> Dictionary:
	var panel := OpeningActionPanelScene.instantiate() as PanelContainer
	parent.add_child(panel)

	var title := panel.get_node("Margin/Rows/Title") as Label
	title.text = UILocalizationScript.t("hud.opening", "Apertura")

	var row := panel.get_node("Margin/Rows/ButtonsRow") as HBoxContainer
	var buttons: Array[Button] = []
	for step in steps:
		var button := Button.new()
		button.custom_minimum_size = Vector2(52.0, 30.0)
		button.toggle_mode = true
		button.text = "%d%%" % int(round(step * 100.0))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pressed_callback.bind(step))
		row.add_child(button)
		buttons.append(button)

	return {
		"panel": panel,
		"title": title,
		"buttons": buttons
	}


static func update(title: Label, buttons: Array[Button], steps: Array[float], title_text: String, open_fraction: float) -> void:
	if title != null:
		title.text = title_text
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		if button == null:
			continue
		if i >= steps.size():
			button.set_pressed_no_signal(false)
			continue
		button.set_pressed_no_signal(absf(open_fraction - float(steps[i])) < 0.01)


static func position_panel(panel: PanelContainer, screen_pos: Vector2, viewport_size: Vector2) -> void:
	if panel == null:
		return
	var desired_size: Vector2 = panel.get_combined_minimum_size()
	if desired_size.x <= 0.0 or desired_size.y <= 0.0:
		desired_size = DEFAULT_PANEL_SIZE
	var pos: Vector2 = screen_pos + Vector2(14.0, 14.0)
	if pos.x + desired_size.x > viewport_size.x - VIEWPORT_MARGIN_PX:
		pos.x = screen_pos.x - desired_size.x - 14.0
	if pos.y + desired_size.y > viewport_size.y - BOTTOM_RESERVED_PX:
		pos.y = screen_pos.y - desired_size.y - 14.0
	pos.x = clampf(pos.x, VIEWPORT_MARGIN_PX, maxf(VIEWPORT_MARGIN_PX, viewport_size.x - desired_size.x - VIEWPORT_MARGIN_PX))
	pos.y = clampf(pos.y, VIEWPORT_MARGIN_PX, maxf(VIEWPORT_MARGIN_PX, viewport_size.y - desired_size.y - BOTTOM_RESERVED_PX))
	panel.position = pos
	panel.size = desired_size
