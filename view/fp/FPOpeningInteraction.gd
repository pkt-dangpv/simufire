extends RefCounted


static func next_fraction(current: float, steps: Array[float]) -> float:
	if steps.is_empty():
		return 1.0 if current <= 0.0 else 0.0

	var closest_idx: int = 0
	var min_dist: float = INF
	for i in range(steps.size()):
		var d: float = absf(current - steps[i])
		if d < min_dist:
			min_dist = d
			closest_idx = i
	return steps[(closest_idx + 1) % steps.size()]


static func prompt_text(is_door: bool, current_fraction: float, next_fraction_value: float) -> String:
	var kind: String = "puerta" if is_door else "ventana"
	var curr_pct: int = int(round(current_fraction * 100.0))
	var next_pct: int = int(round(next_fraction_value * 100.0))
	var action: String = "cerrar" if next_fraction_value < current_fraction else "abrir"
	return "F: %s %s (%d%% → %d%%)" % [
		action,
		kind,
		curr_pct,
		next_pct
	]
