class_name StairGeometry
extends RefCounted


static func long_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.x if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.y


static func cross_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.y if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.x


static func ramp_width_m(rect: Rect2, stair_dir: Vector2 = Vector2.DOWN) -> float:
	var cross_span: float = cross_span_m(rect, stair_dir)
	return minf(maxf(0.82, cross_span * 0.50), maxf(0.82, cross_span - 0.96))


static func top_landing_depth_m(rect: Rect2, stair_dir: Vector2 = Vector2.DOWN) -> float:
	return clampf(long_span_m(rect, stair_dir) * 0.22, 0.72, 1.05)


static func point_along_run(rect: Rect2, stair_dir: Vector2, distance_from_entry_m: float) -> Vector2:
	var center: Vector2 = rect.get_center()
	if absf(stair_dir.x) > absf(stair_dir.y):
		var entry_x: float = rect.position.x if stair_dir.x > 0.0 else rect.position.x + rect.size.x
		return Vector2(entry_x + stair_dir.x * distance_from_entry_m, center.y)
	var entry_y: float = rect.position.y if stair_dir.y > 0.0 else rect.position.y + rect.size.y
	return Vector2(center.x, entry_y + stair_dir.y * distance_from_entry_m)


static func vertical_void_rect(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Rect2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	if turn_degrees >= 179.0:
		var gap_m: float = 0.18
		var cross: float = cross_span_m(rect, stair_dir)
		var flight_width_m: float = clampf((cross - gap_m) * 0.5, 0.72, 1.05)
		var shaft_width_m: float = minf(cross, flight_width_m * 2.0 + gap_m + 0.18)
		if absf(stair_dir.x) > absf(stair_dir.y):
			return Rect2(Vector2(rect.position.x, rect.get_center().y - shaft_width_m * 0.5), Vector2(rect.size.x, shaft_width_m))
		return Rect2(Vector2(rect.get_center().x - shaft_width_m * 0.5, rect.position.y), Vector2(shaft_width_m, rect.size.y))
	var width_m: float = minf(ramp_width_m(rect, stair_dir), maxf(0.2, cross_span_m(rect, stair_dir) - 0.2))
	var run_m: float = minf(
		maxf(0.80, long_span_m(rect, stair_dir) - top_landing_depth_m(rect, stair_dir) - 0.22),
		maxf(0.2, long_span_m(rect, stair_dir) - 0.2)
	)
	var start_margin_m: float = 0.22
	if absf(stair_dir.x) > absf(stair_dir.y):
		var x_m: float = rect.position.x + start_margin_m if stair_dir.x > 0.0 else rect.position.x + rect.size.x - start_margin_m - run_m
		return Rect2(Vector2(x_m, rect.get_center().y - width_m * 0.5), Vector2(run_m, width_m))
	var y_m: float = rect.position.y + start_margin_m if stair_dir.y > 0.0 else rect.position.y + rect.size.y - start_margin_m - run_m
	return Rect2(Vector2(rect.get_center().x - width_m * 0.5, y_m), Vector2(width_m, run_m))


static func subtract_rect(rect: Rect2, void_rect: Rect2) -> Array[Rect2]:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or void_rect.size.x <= 0.0 or void_rect.size.y <= 0.0:
		return [rect]
	if not rect.intersects(void_rect, true):
		return [rect]
	var cut: Rect2 = rect.intersection(void_rect)
	if cut.size.x <= 0.001 or cut.size.y <= 0.001:
		return [rect]
	var pieces: Array[Rect2] = []
	var rect_end: Vector2 = rect.position + rect.size
	var cut_end: Vector2 = cut.position + cut.size
	if cut.position.y > rect.position.y + 0.001:
		pieces.append(Rect2(rect.position, Vector2(rect.size.x, cut.position.y - rect.position.y)))
	if cut_end.y < rect_end.y - 0.001:
		pieces.append(Rect2(Vector2(rect.position.x, cut_end.y), Vector2(rect.size.x, rect_end.y - cut_end.y)))
	if cut.position.x > rect.position.x + 0.001:
		pieces.append(Rect2(Vector2(rect.position.x, cut.position.y), Vector2(cut.position.x - rect.position.x, cut.size.y)))
	if cut_end.x < rect_end.x - 0.001:
		pieces.append(Rect2(Vector2(cut_end.x, cut.position.y), Vector2(rect_end.x - cut_end.x, cut.size.y)))
	return pieces


static func split_rect_by_voids(rect: Rect2, voids: Array[Rect2]) -> Array[Rect2]:
	var slabs: Array[Rect2] = [rect]
	for void_rect in voids:
		var next: Array[Rect2] = []
		for slab in slabs:
			for piece in subtract_rect(slab, void_rect):
				if piece.size.x >= 0.08 and piece.size.y >= 0.08:
					next.append(piece)
		slabs = next
	return slabs
