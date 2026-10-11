extends SceneTree

# G3 diagnostic flame target (design section 13): evaluates the pure helper of
# CombustionSystem on a grid and prints one JSON line. The assertions live in
# tests/test_g3_diag_flame_target.py.

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")


func _init() -> void:
	var threshold: float = CombustionSystemScript.G3_DIAG_CAN_FLAME_DRIVE
	var rows: Array = []
	for ideal_kw in [600.0, 350.0, 37.5]:
		for smolder_kw in [0.0, 1.08, 6.48]:
			for window in [0.0, 0.002, 0.01]:
				for jump_fraction in [0.0, 0.25, 1.0 / 3.0, 1.0]:
					for offset in [
						-0.02, -1e-9, 0.0, 1e-12, 1e-9, 1e-6, 0.0005, 0.001, 0.0019999,
						0.002, 0.005, 0.0099999, 0.01, 0.0100001, 0.02, 0.5,
					]:
						var drive: float = threshold + offset
						var original_kw: float = ideal_kw * clampf(drive, 0.0, 1.0)
						rows.append([
							ideal_kw, smolder_kw, window, jump_fraction, offset, original_kw,
							CombustionSystemScript.g3_diag_flame_target_kw(
								original_kw, ideal_kw, drive, smolder_kw, window, jump_fraction
							),
						])
	print("G3_DIAG_FLAME_TARGET " + JSON.stringify({
		"threshold": threshold,
		"window_key": CombustionSystemScript.G3_DIAG_FLAME_TARGET_WINDOW,
		"jump_key": CombustionSystemScript.G3_DIAG_FLAME_TARGET_JUMP_FRACTION,
		"rows": rows,
	}, "", false, true))
	quit(0)
