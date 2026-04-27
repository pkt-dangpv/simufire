extends Node2D
class_name EditorGrid

@export var pixels_per_meter: float = 64.0
@export var grid_m: float = 0.25
@export var major_every: int = 4
@export var extent_m: float = 80.0

var minor_color: Color = Color(0.20, 0.24, 0.28, 0.35)
var major_color: Color = Color(0.30, 0.36, 0.42, 0.55)
var axis_color: Color = Color(0.75, 0.84, 0.92, 0.45)


func _draw() -> void:
	var step_px: float = maxf(4.0, grid_m * pixels_per_meter)
	var max_px: float = extent_m * pixels_per_meter
	var line_index: int = int(-extent_m / grid_m)
	var x: float = -max_px

	while x <= max_px:
		var color: Color = major_color if line_index % major_every == 0 else minor_color
		if absf(x) <= 0.001:
			color = axis_color
		draw_line(Vector2(x, -max_px), Vector2(x, max_px), color, 1.0)
		x += step_px
		line_index += 1

	line_index = int(-extent_m / grid_m)
	var y: float = -max_px
	while y <= max_px:
		var color: Color = major_color if line_index % major_every == 0 else minor_color
		if absf(y) <= 0.001:
			color = axis_color
		draw_line(Vector2(-max_px, y), Vector2(max_px, y), color, 1.0)
		y += step_px
		line_index += 1
