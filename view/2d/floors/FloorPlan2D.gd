extends RefCounted
class_name FloorPlan2D

const FLOOR_MATCH_TOLERANCE_M: float = 0.05


static func collect_floor_levels(building: BuildingModel) -> Array[float]:
	var levels: Array[float] = []
	if building == null:
		return levels
	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(int(room_id))
		if room == null:
			continue
		_add_unique_level(levels, room.floor_level_z_m)
	levels.sort()
	return levels


static func clamp_floor_index(index: int, levels: Array[float]) -> int:
	return clampi(index, 0, maxi(0, levels.size() - 1))


static func selected_floor_level(levels: Array[float], selected_index: int) -> float:
	if levels.is_empty():
		return 0.0
	return float(levels[clamp_floor_index(selected_index, levels)])


static func room_floor_level(building: BuildingModel, room_id: int) -> float:
	if building == null:
		return 0.0
	var room: RoomModel = building.get_room(room_id)
	return room.floor_level_z_m if room != null else 0.0


static func is_room_visible(building: BuildingModel, levels: Array[float], selected_index: int, room_id: int) -> bool:
	if levels.size() <= 1:
		return true
	return absf(room_floor_level(building, room_id) - selected_floor_level(levels, selected_index)) < FLOOR_MATCH_TOLERANCE_M


static func is_opening_visible(
	building: BuildingModel,
	rects_m: Dictionary,
	levels: Array[float],
	selected_index: int,
	opening_index: int
) -> bool:
	if building == null:
		return false
	var op: OpeningModel = building.get_opening_at(opening_index)
	if op == null:
		return false
	var a_visible: bool = op.a != BuildingModel.OUTSIDE_ID and rects_m.has(op.a) and is_room_visible(building, levels, selected_index, op.a)
	var b_visible: bool = op.b != BuildingModel.OUTSIDE_ID and rects_m.has(op.b) and is_room_visible(building, levels, selected_index, op.b)
	if op.a == BuildingModel.OUTSIDE_ID:
		return b_visible
	if op.b == BuildingModel.OUTSIDE_ID:
		return a_visible
	return a_visible and b_visible


static func selector_button_rect(index: int, origin_px: Vector2, size_px: Vector2, gap_px: float) -> Rect2:
	return Rect2(
		origin_px + Vector2((size_px.x + gap_px) * float(index), 0.0),
		size_px
	)


static func floor_label(index: int) -> String:
	if index <= 0:
		return "PB"
	return "P%d" % index


static func selector_hit_index(local_pos: Vector2, levels: Array[float], origin_px: Vector2, size_px: Vector2, gap_px: float) -> int:
	for i in range(levels.size()):
		if selector_button_rect(i, origin_px, size_px, gap_px).has_point(local_pos):
			return i
	return -1


static func _add_unique_level(levels: Array[float], level_m: float) -> void:
	for existing in levels:
		if absf(float(existing) - level_m) < FLOOR_MATCH_TOLERANCE_M:
			return
	levels.append(level_m)
