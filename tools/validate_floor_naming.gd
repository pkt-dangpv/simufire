extends SceneTree
## Validacion: la convencion de plantas es R / R+1 en todas partes, y un escenario
## guardado con la convencion vieja (PB / P1) se relee con la nueva.
##
##   godot --headless --path . --script res://tools/validate_floor_naming.gd

func _initialize() -> void:
	var fails: int = 0
	fails += _eq("label(0)", FloorNaming.label(0), "R")
	fails += _eq("label(1)", FloorNaming.label(1), "R+1")
	fails += _eq("label(7)", FloorNaming.label(7), "R+7")
	fails += _eq("label(-3)", FloorNaming.label(-3), "R")
	fails += _eq("label_for_level(0.0)", FloorNaming.label_for_level(0.0), "R")
	fails += _eq("label_for_level(2.9)", FloorNaming.label_for_level(2.9), "R+1")
	fails += _eq("label_for_level(8.7)", FloorNaming.label_for_level(8.7), "R+3")
	fails += _eq("migra PB", FloorNaming.migrated_name("PB", 0), "R")
	fails += _eq("migra P2", FloorNaming.migrated_name("P2", 2), "R+2")
	fails += _eq("respeta nombre propio", FloorNaming.migrated_name("Buhardilla", 3), "Buhardilla")
	fails += _eq("FloorPlan2D.floor_label(2)", FloorPlan2D.floor_label(2), "R+2")

	# Un escenario con la convencion vieja, tal como esta guardado en disco.
	var viejo: Dictionary = {
		"floors": [
			{"name": "PB", "level_m": 0.0},
			{"name": "P1", "level_m": 2.9},
			{"name": "Buhardilla", "level_m": 5.8},
		],
		"rooms_data": [],
	}
	var normalizado: Array = ScenarioSerializer.normalize_floors(viejo.get("floors", []), [])
	var nombres: Array = []
	for raw in normalizado:
		nombres.append(String(Dictionary(raw).get("name", "")))
	fails += _eq("escenario viejo relabelado", str(nombres), '["R", "R+1", "Buhardilla"]')

	if fails == 0:
		print("[validate_floor_naming] PASS")
	else:
		print("[validate_floor_naming] FAIL: %d comprobacion(es)" % fails)
	quit(0 if fails == 0 else 1)


func _eq(que: String, got: Variant, want: Variant) -> int:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
		return 0
	print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
	return 1
