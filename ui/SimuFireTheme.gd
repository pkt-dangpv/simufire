extends RefCounted
class_name SimuFireTheme

const LOGO_PATH: String = "res://assets/ui/simufire_logo_editor.png"
const FONT_PATH: String = "res://assets/fonts/bahnschrift.ttf"

const BG: Color = Color(0.00, 0.01, 0.01, 1.0)
const PANEL: Color = Color(0.02, 0.05, 0.07, 0.94)
const PANEL_DARK: Color = Color(0.00, 0.02, 0.03, 0.98)
const FIELD: Color = Color(0.03, 0.07, 0.09, 0.96)
const BORDER: Color = Color(0.18, 0.22, 0.25, 0.92)
const ORANGE: Color = Color(1.00, 0.25, 0.00, 1.0)
const BLUE: Color = Color(0.00, 0.70, 0.88, 0.98)
const GREEN: Color = Color(0.55, 1.00, 0.36, 0.98)
const YELLOW: Color = Color(1.00, 0.78, 0.00, 0.98)
const TEXT: Color = Color(0.90, 0.94, 0.96, 0.98)
const MUTED: Color = Color(0.49, 0.55, 0.60, 0.92)


static func body_font() -> Font:
	var project_font := load(FONT_PATH) as FontFile
	if project_font != null:
		return project_font
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Roboto Condensed", "Bahnschrift", "Segoe UI", "Arial Narrow", "Arial"])
	font.font_weight = 500
	font.font_stretch = 92
	return font


static func title_font() -> Font:
	var project_font := load(FONT_PATH) as FontFile
	if project_font != null:
		return project_font
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift SemiBold Condensed", "Agency FB", "Roboto Condensed", "Arial Narrow", "Arial"])
	font.font_weight = 700
	font.font_stretch = 82
	return font


static func build_theme() -> Theme:
	var theme := Theme.new()
	var body := body_font()
	var title := title_font()
	for type_name in ["Label", "Button", "LineEdit", "OptionButton", "SpinBox", "PopupMenu", "CheckBox", "Tree", "ItemList"]:
		theme.set_font("font", type_name, body)
	theme.set_font("font", "Button", title)
	theme.set_font("font", "OptionButton", title)

	theme.set_font_size("font_size", "Label", 12)
	theme.set_font_size("font_size", "Button", 12)
	theme.set_font_size("font_size", "LineEdit", 12)
	theme.set_font_size("font_size", "OptionButton", 12)
	theme.set_font_size("font_size", "SpinBox", 12)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", ORANGE)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color(0.34, 0.38, 0.42, 0.72))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", ORANGE)
	theme.set_color("font_color", "OptionButton", TEXT)

	var panel_box := stylebox(PANEL, BORDER, 1, 0, Vector2(12.0, 12.0))
	var field_box := stylebox(FIELD, BORDER, 1, 0, Vector2(8.0, 6.0))
	var field_focus_box := stylebox(FIELD, BLUE, 1, 0, Vector2(8.0, 6.0))
	var button_box := stylebox(PANEL_DARK, BORDER, 1, 0, Vector2(12.0, 8.0))
	var button_hover_box := stylebox(Color(0.04, 0.10, 0.12, 0.98), BLUE, 1, 0, Vector2(12.0, 8.0))
	var button_pressed_box := stylebox(Color(0.16, 0.05, 0.01, 0.98), ORANGE, 1, 0, Vector2(12.0, 8.0))
	var button_disabled_box := stylebox(Color(0.03, 0.04, 0.05, 0.82), Color(0.10, 0.12, 0.14, 0.80), 1, 0, Vector2(12.0, 8.0))

	theme.set_stylebox("panel", "PanelContainer", panel_box)
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, button_box)
		theme.set_stylebox("hover", type_name, button_hover_box)
		theme.set_stylebox("pressed", type_name, button_pressed_box)
		theme.set_stylebox("focus", type_name, stylebox(Color(0.04, 0.08, 0.10, 0.58), BLUE, 1, 0, Vector2(12.0, 8.0)))
		theme.set_stylebox("disabled", type_name, button_disabled_box)
	for type_name in ["LineEdit", "SpinBox"]:
		theme.set_stylebox("normal", type_name, field_box)
		theme.set_stylebox("focus", type_name, field_focus_box)
		theme.set_stylebox("read_only", type_name, stylebox(Color(0.02, 0.03, 0.04, 0.85), BORDER, 1, 0, Vector2(8.0, 6.0)))

	var separator := StyleBoxLine.new()
	separator.color = Color(0.18, 0.22, 0.25, 0.72)
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	return theme


static func stylebox(bg: Color, border: Color, border_width: int, radius: int, margin: Vector2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_right = radius
	box.corner_radius_bottom_left = radius
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	return box


static func apply_control_tree(root: Node, headings_orange: bool = true) -> void:
	if root is PanelContainer:
		(root as PanelContainer).add_theme_stylebox_override("panel", stylebox(PANEL, BORDER, 1, 0, Vector2(12.0, 12.0)))
	if root is Label:
		var label := root as Label
		label.add_theme_font_override("font", body_font())
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", TEXT)
		if headings_orange and _looks_like_heading(label):
			label.text = label.text.to_upper()
			label.add_theme_font_override("font", title_font())
			label.add_theme_color_override("font_color", ORANGE)
	if root is Button:
		var button := root as Button
		button.text = button.text.to_upper()
		button.add_theme_font_override("font", title_font())
		button.add_theme_font_size_override("font_size", 12)
	if root is OptionButton:
		var option := root as OptionButton
		option.add_theme_font_override("font", title_font())
		option.add_theme_font_size_override("font_size", 12)
	for child in root.get_children():
		apply_control_tree(child, headings_orange)


static func _looks_like_heading(label: Label) -> bool:
	var n: String = label.name.to_lower()
	return n.ends_with("title") or n.contains("label")
