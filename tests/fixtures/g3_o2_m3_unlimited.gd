extends "res://tests/fixtures/g3_o2_m3_diagnosis.gd"

## Compare real unbounded engine steps against M2-T, not an offline oracle.
## Reuses the unchanged diagnostic setup: a 700-kW / 1100-MJ synthetic sofa.
## A 30-s horizon is predeclared to exclude flashover and end-of-fuel changes.


func _run() -> void:
	var failures: Array[String] = []
	var checks: int = 0
	var rows_dir: String = OS.get_environment("G3_O2_M3_DIAGNOSIS_OUT")
	for dt: float in [2.0, 1.0, 0.5, 0.25]:
		var world: Dictionary = _world({"rooms": 2, "door": true, "dt": dt, "fire": SOFA})
		var engine = world["engine"]
		var room = world["rooms"][0]
		var file = FileAccess.open(rows_dir.path_join("unlimited_%s.jsonl" % str(dt)), FileAccess.WRITE)
		if file == null:
			failures.append("external row file unavailable")
			continue
		for index: int in range(int(round(30.0 / dt))):
			engine.step(dt)
			checks += 3
			if not engine.o2_room_inventory_failure.is_empty():
				failures.append("unlimited engine rejects a tick")
			if room.flashover_triggered:
				failures.append("control no longer excludes flashover")
			var selection: Dictionary = engine.get_o2_room_inventory_report().get("selections", {}).get(0, {})
			if float(selection.get("accepted_fraction", 1.0)) != 1.0:
				failures.append("control no longer excludes O2 limitation")
			var row: Dictionary = {"t": engine.sim_time_s}
			for field: String in ["hrr_kw", "hrr_kj_total", "fuel_consumed_MJ_total", "retained_unburned_MJ",
					"smoke_prod_kg_s", "smoke_generated_kg_total", "co_kg", "co2_kg", "hcn_kg",
					"o2_inventory_kg", "o2_consumed_fire_kg_total", "temp_upper_c", "temp_lower_c"]:
				row[field] = room.get(field)
			row["remaining_fuel_MJ"] = room.fire.remaining_fuel_MJ if room.fire != null else 0.0
			row["object_power_kw"] = room.fuel_objects[0].hrr_kw
			file.store_line(JSON.stringify(row, "", true, true))
		file.close()
		engine.free()
		world["building"].free()
	print("G3_O2_M3_UNLIMITED " + JSON.stringify({"checks": checks,
		"failure_count": failures.size(), "failures": failures}, "", true, true))
	quit(0 if failures.is_empty() else 1)
