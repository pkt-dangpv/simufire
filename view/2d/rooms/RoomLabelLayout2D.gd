extends RefCounted
class_name RoomLabelLayout2D


static func pick_detail(
	content_rect: Rect2,
	tiny_threshold_px: Vector2,
	compact_threshold_px: Vector2,
	medium_threshold_px: Vector2
) -> String:
	if content_rect.size.x < tiny_threshold_px.x or content_rect.size.y < tiny_threshold_px.y:
		return "tiny"
	if content_rect.size.x < compact_threshold_px.x or content_rect.size.y < compact_threshold_px.y:
		return "compact"
	if content_rect.size.x < medium_threshold_px.x or content_rect.size.y < medium_threshold_px.y:
		return "medium"
	return "full"


static func bottom_reserved_px(show_hrr_bar: bool, hrr_bar_height_px: float, hrr_bar_margin_px: float) -> float:
	if not show_hrr_bar:
		return 2.0
	return hrr_bar_height_px + hrr_bar_margin_px + 4.0


static func fit_lines(
	content_rect: Rect2,
	lines: Array[String],
	flashover_triggered: bool,
	label_offset: Vector2,
	line_height_px: float,
	padding_px: float,
	bottom_reserved_px_value: float
) -> Array[String]:
	var usable_height_px: float = (
		content_rect.size.y
		- label_offset.y
		- bottom_reserved_px_value
		+ padding_px
		+ 2.0
	)
	var max_lines: int = int(floor(usable_height_px / maxf(1.0, line_height_px)))
	if max_lines <= 0:
		return []
	if lines.size() <= max_lines:
		return lines

	var trimmed: Array[String] = []
	var kept_count: int = mini(max_lines, lines.size())
	for i in range(kept_count):
		trimmed.append(lines[i])

	if kept_count >= 2:
		if flashover_triggered:
			trimmed[kept_count - 1] = "FLASHOVER"
		elif lines.size() > kept_count:
			trimmed[kept_count - 1] = "..."

	return trimmed
