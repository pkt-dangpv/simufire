extends SceneTree

const Layout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const Loader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")
const Building := preload("res://sim/BuildingModel.gd")
const Templates := preload("res://sim/templates/BuildingTemplate.gd")
const Read := preload("res://view/ViewScenarioRead.gd")
const Overview := preload("res://view/3d/Visualizer3D.gd")
const FP := preload("res://view/fp/FirstPersonController.gd")
const Mini := preload("res://ui/Minimap2D.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _equal(a: Variant, b: Variant) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)


func _objects() -> Array:
	return [{"id": "chair", "name": "Chair", "visual_archetype": "chair",
		"size_m": Vector2(0.5, 0.5), "position_m": Vector2(1.0, 1.0),
		"rotation_deg": 12.0, "visual_pose_locked": true, "state": "cold",
		"remaining_fuel_MJ": 10.0, "hrr_kw": 0.0, "nested": {"list": [1]}}]


func _assert_current(building: BuildingModel, room_id: int, rect: Rect2, raw: Array, fill: bool, label: String) -> Array:
	var input: Array = raw.duplicate(true)
	var actual: Array = Layout.normalize_room(building, room_id, rect, raw, fill)
	var expected: Array = Layout.normalize_room_uncached(building, room_id, rect, raw, fill)
	check(_equal(actual, expected), "identity " + label)
	check(_equal(raw, input), "input unchanged " + label)
	return actual


func _check_specs() -> void:
	Layout.invalidate_all()
	var model: BuildingModel = Building.new()
	check(model.load_template_data(Templates.new().create_product_preset("simple_house")), "spec model loaded")
	var rect := Rect2(Vector2.ZERO, Vector2(4.0, 4.0))
	var raw: Array = [null, {}, {"id": "room_proxy_1"}] + _objects()
	raw[3].erase("visual_archetype")
	var before: int = int(Layout.cache_stats()["spec_misses"])
	var actual: Array = Layout._prepare_specs_cached(model, 0, rect, raw, true)
	check(_equal(actual, Layout._prepare_specs(model, 0, rect, raw, true)), "spec cold identity")
	check(int(Layout.cache_stats()["spec_misses"]) == before + 1, "spec cold computes once")
	var hits: int = int(Layout.cache_stats()["spec_hits"])
	for iteration: int in range(24):
		for field: String in Layout.DYNAMIC_FIELDS:
			if iteration % 2:
				raw[3][field] = "flaming" if field == "state" else float(iteration)
			else:
				raw[3].erase(field)
		var input: PackedByteArray = var_to_bytes(raw)
		actual = Layout._prepare_specs_cached(model, 0, rect, raw, true)
		check(_equal(actual, Layout._prepare_specs(model, 0, rect, raw, true)), "spec dynamic current")
		check(var_to_bytes(raw) == input, "spec input unchanged")
		check(int(Layout.cache_stats()["spec_misses"]) == before + 1, "spec warm reuse")
	check(int(Layout.cache_stats()["spec_hits"]) == hits + 24, "spec hits counted")
	# Both real-object nested data and generated decoration must be independent.
	actual[0]["nested"]["list"].append(99)
	actual[-1]["name"] = "poison"
	actual = Layout._prepare_specs_cached(model, 0, rect, raw, true)
	check(_equal(actual, Layout._prepare_specs(model, 0, rect, raw, true)), "spec copies isolated")
	for field: String in ["name", "kind", "visual_furniture_fill"]:
		var room: RoomModel = model.get_room(0)
		var old_value: Variant = room.get(field)
		room.set(field, not bool(old_value) if field == "visual_furniture_fill" else "Bedroom")
		var previous: int = int(Layout.cache_stats()["spec_misses"])
		actual = Layout._prepare_specs_cached(model, 0, rect, raw, true)
		check(_equal(actual, Layout._prepare_specs(model, 0, rect, raw, true)), "spec metadata identity")
		check(int(Layout.cache_stats()["spec_misses"]) == previous + 1, "spec metadata invalidation")
		room.set(field, old_value)
	# Order, additions, unknown fields, dimensions, and fill policy are exact inputs.
	for change: String in ["rect", "fill", "unknown", "order", "addition", "removal"]:
		Layout._prepare_specs_cached(model, 0, rect, raw, true)
		var changed: Array = raw.duplicate(true)
		var bounds: Rect2 = rect
		var fill: bool = true
		match change:
			"rect": bounds.size.x += 0.2
			"fill": fill = false
			"unknown": changed[3]["new_field"] = {"list": [1, 2]}
			"order": changed.reverse()
			"addition": changed.append({"id": "extra", "kind": "sofa", "name": "Sofa"})
			"removal": changed.pop_back()
		var previous: int = int(Layout.cache_stats()["spec_misses"])
		actual = Layout._prepare_specs_cached(model, 0, bounds, changed, fill)
		check(_equal(actual, Layout._prepare_specs(model, 0, bounds, changed, fill)), "spec changed input identity")
		check(int(Layout.cache_stats()["spec_misses"]) == previous + 1, "spec changed input invalidation")
	var replacement: BuildingModel = Building.new()
	check(replacement.load_template_data(Templates.new().create_product_preset("simple_house")), "spec replacement loaded")
	var previous: int = int(Layout.cache_stats()["spec_misses"])
	Layout._prepare_specs_cached(replacement, 0, rect, raw, true)
	check(int(Layout.cache_stats()["spec_misses"]) == previous + 1, "spec owner isolation")
	model.free()
	replacement.free()
	check(int(Layout.cache_stats()["spec_entries"]) == 0, "spec dead owners pruned")
	for index: int in range(Layout.MAX_CACHED_ROOMS + 2):
		Layout._prepare_specs_cached(null, index, rect, raw, false)
	check(int(Layout.cache_stats()["spec_entries"]) <= Layout.MAX_CACHED_ROOMS, "spec bounded cache")
	Layout.invalidate_all()
	check(int(Layout.cache_stats()["spec_entries"]) == 0, "spec explicit invalidation")


func _run() -> void:
	_check_specs()
	Layout.invalidate_all()
	var rect := Rect2(Vector2.ZERO, Vector2(4.0, 4.0))
	var raw: Array = _objects()
	_assert_current(null, 1, rect, raw, false, "cold")
	var misses: int = int(Layout.cache_stats()["misses"])
	for index: int in range(24):
		raw[0]["state"] = "flaming" if index % 2 else "burned_out"
		raw[0]["hrr_kw"] = float(index) * 2.0
		raw[0]["remaining_fuel_MJ"] = 10.0 - float(index) * 0.2
		raw[0]["temp_c"] = float(index) * 20.0
		raw[0]["surface_temp_c"] = float(index) * 15.0
		raw[0]["temperature_c"] = float(index) * 10.0
		raw[0]["incident_heat_flux_kw_m2"] = float(index) * 0.25
		raw[0]["t_ignition_s"] = float(index) / 60.0
		raw[0]["is_primary_ignition_source"] = bool(index % 2)
		var result: Array = _assert_current(null, 1, rect, raw, false, "dynamic")
		check(result[0]["state"] == raw[0]["state"], "fresh dynamic state")
		check(result[0]["hrr_kw"] == raw[0]["hrr_kw"], "fresh dynamic HRR")
		check(result[0]["remaining_fuel_MJ"] == raw[0]["remaining_fuel_MJ"], "fresh dynamic fuel")
		check(int(Layout.cache_stats()["misses"]) == misses, "warm reuse")
	var result: Array = Layout.normalize_room(null, 1, rect, raw, false)
	result[0]["position_m"] = Vector2(99.0, 99.0)
	result[0]["nested"]["list"].append(99)
	_assert_current(null, 1, rect, raw, false, "returned copy isolated")
	for field: String in ["position_m", "size_m", "rotation_deg", "visual_pose_locked", "visual_only", "visual_archetype", "name", "nested"]:
		var changed: Array = raw.duplicate(true)
		match field:
			"position_m": changed[0][field] = Vector2(2.0, 2.0)
			"size_m": changed[0][field] = Vector2(0.7, 0.6)
			"rotation_deg": changed[0][field] = 37.0
			"visual_pose_locked": changed[0][field] = false
			"visual_only": changed[0][field] = true
			"visual_archetype": changed[0][field] = "table"
			"name": changed[0][field] = "New name"
			"nested": changed[0][field]["list"].append(2)
		var previous: int = int(Layout.cache_stats()["misses"])
		_assert_current(null, 1, rect, changed, false, "static " + field)
		check(int(Layout.cache_stats()["misses"]) == previous + 1, "static invalidation " + field)
	_assert_current(null, 1, Rect2(Vector2(1.0, 1.0), Vector2(5.0, 4.0)), raw, false, "rect")
	var reordered: Array = raw.duplicate(true)
	var second: Dictionary = raw[0].duplicate(true)
	second["id"] = "second"
	second["position_m"] = Vector2(2.5, 2.5)
	second["state"] = "heating"
	reordered.append(second)
	_assert_current(null, 1, rect, reordered, false, "addition")
	reordered.reverse()
	_assert_current(null, 1, rect, reordered, false, "order")
	_assert_current(null, 1, rect, raw, false, "removal")
	raw[0].erase("temp_c")
	_assert_current(null, 1, rect, raw, false, "dynamic field removed")
	var building: BuildingModel = Building.new()
	check(building.load_template_data(Templates.new().create_product_preset("simple_house")), "product loaded")
	var room_rect: Rect2 = building.get_room_rects_m()[0]
	var objects: Array = Read.fuel_object_snapshots(building.get_room(0))
	var mini := Mini.new()
	mini.building = building
	# Alternate the real caller schemas, not repeated calls from one view.
	var full: Array = objects.duplicate(true)
	for object: Dictionary in full:
		object["alpha_kw_s2"] = -1.0
		object["critical_heat_flux_kw_m2"] = 12.5
		object["heat_of_gasification_kj_kg"] = -1.0
	Layout.normalize_room(building, 0, room_rect, full, true)
	var alternating_misses: int = int(Layout.cache_stats()["misses"])
	for index: int in range(24):
		full[0]["hrr_kw"] = float(index)
		full[0]["remaining_fuel_MJ"] = 10.0 - float(index) * 0.1
		mini.set_state({"0": {"fuel_objects": full}})
		var mini_raw: Array = mini._fuel_objects_for_layout(0, building.get_room(0))
		check(_equal(mini_raw, full), "minimap full snapshots")
		_assert_current(building, 0, room_rect, full, true, "main alternating")
		_assert_current(building, 0, room_rect, mini_raw, true, "minimap alternating")
		check(int(Layout.cache_stats()["misses"]) == alternating_misses, "minimap shares warm layout")
		mini_raw[0]["name"] = "poison"
		check(full[0]["name"] != "poison", "minimap snapshot isolated")
	mini.state = {}
	var fallback: Array = mini._fuel_objects_for_layout(0, building.get_room(0))
	check(not fallback.is_empty(), "minimap model fallback")
	mini.state = {"0": {"fuel_objects": []}}
	check(mini._fuel_objects_for_layout(0, building.get_room(0)).is_empty(), "minimap empty authoritative snapshot")
	mini.free()
	_assert_current(building, 0, room_rect, objects, true, "product")
	var before_door: int = int(Layout.cache_stats()["misses"])
	for op in building.get_openings():
		op.open_fraction = 1.0 - op.open_fraction
	_assert_current(building, 0, room_rect, objects, true, "opening fractions")
	check(int(Layout.cache_stats()["misses"]) == before_door, "opening fractions reuse")
	var op: OpeningModel = building.get_opening_at(0)
	op.width_m += 0.25
	var before_geometry: int = int(Layout.cache_stats()["misses"])
	_assert_current(building, 0, room_rect, objects, true, "opening geometry")
	check(int(Layout.cache_stats()["misses"]) == before_geometry + 1, "door geometry invalidation")
	building.get_room(0).visual_furniture_fill = false
	_assert_current(building, 0, room_rect, objects, true, "fill policy")
	_assert_current(building, 0, room_rect, objects, false, "fill off")
	Layout.invalidate_all()
	_assert_current(building, 0, room_rect, objects, false, "owner")
	building.free()
	check(int(Layout.cache_stats()["entries"]) == 0, "released owner pruned")
	var replacement: BuildingModel = Building.new()
	check(replacement.load_template_data(Templates.new().create_product_preset("simple_house")), "replacement loaded")
	_assert_current(replacement, 0, replacement.get_room_rects_m()[0], objects, false, "new building")
	replacement.free()
	# Authored geometry and generated issue arrays must survive without alias.
	var authored: Array = [{"id": "authored", "visual_archetype": "authored_meter_reference",
		"position_m": Vector2(-1.0, -1.0), "size_m": Vector2(0.3, 0.3), "rotation_deg": 37.0}]
	var authored_out: Array = _assert_current(null, 2, rect, authored, false, "authored transform")
	check(not authored_out[0]["visual_placement_issues"].is_empty(), "authored placement issue")
	authored_out[0]["visual_placement_issues"].append("poison")
	_assert_current(null, 2, rect, authored, false, "pose patch isolated")
	var packed := load(Loader.model_path("authored_meter_reference")) as PackedScene
	var before_resource: int = int(Layout.cache_stats()["misses"])
	packed.emit_changed()
	check(int(Layout.cache_stats()["spec_entries"]) == 0, "spec asset invalidation")
	check(Loader._native_size_cache.is_empty(), "native sizes invalidated")
	_assert_current(null, 2, rect, authored, false, "asset changed")
	check(int(Layout.cache_stats()["misses"]) == before_resource + 1, "asset signal invalidation")
	Layout.invalidate_all()
	for index: int in range(Layout.MAX_CACHED_ROOMS + 2):
		Layout.normalize_room(null, index, rect, _objects(), false)
	check(int(Layout.cache_stats()["entries"]) <= Layout.MAX_CACHED_ROOMS, "bounded cache")
	var live: BuildingModel = Building.new()
	check(live.load_template_data(Templates.new().create_product_preset("simple_house")), "rebuild model")
	var overview = Overview.new()
	overview.building = live
	root.add_child(overview)
	await process_frame
	Loader._native_size_cache["authored_meter_reference"] = Vector3(99.0, 99.0, 99.0)
	overview.rebuild_from_building()
	check(Loader._native_size_cache.get("authored_meter_reference", Vector3.ZERO) != Vector3(99.0, 99.0, 99.0), "overview rebuild invalidates")
	overview.queue_free()
	await process_frame
	var fp = FP.new()
	fp.exterior_context_enabled = false
	root.add_child(fp)
	await process_frame
	fp.setup(live)
	Loader._native_size_cache["authored_meter_reference"] = Vector3(99.0, 99.0, 99.0)
	fp.rebuild_from_building()
	check(Loader._native_size_cache.get("authored_meter_reference", Vector3.ZERO) != Vector3(99.0, 99.0, 99.0), "fp rebuild invalidates")
	fp.queue_free()
	await process_frame
	live.free()
	# Product parity across all distributed homes, not just one synthetic chair.
	for preset in Templates.new().get_preset_definitions():
		var model: BuildingModel = Building.new()
		check(model.load_template_data(Templates.new().create_product_preset(String(preset["id"]))), "catalogue loaded")
		for room_id: Variant in model.get_rooms():
			var bounds: Rect2 = model.get_room_rects_m()[room_id]
			var snapshots: Array = Read.fuel_object_snapshots(model.get_room(int(room_id)))
			_assert_current(model, int(room_id), bounds, snapshots, true, "catalogue cold")
			_assert_current(model, int(room_id), bounds, snapshots, true, "catalogue warm")
		model.free()
	print("FURNITURE_LAYOUT_CACHE " + JSON.stringify({"checks": checks, "failures": failures,
		"failure_count": failures.size(), "stats": Layout.cache_stats()}))
	quit(0 if failures.is_empty() else 1)
