extends SceneTree

const Templates := preload("res://sim/templates/BuildingTemplate.gd")
const Building := preload("res://sim/BuildingModel.gd")
const FP := preload("res://view/fp/FirstPersonController.gd")
const Overview := preload("res://view/3d/Visualizer3D.gd")
const Layout := preload("res://view/furniture/FurnitureVisualLayout.gd")
const Read := preload("res://view/ViewScenarioRead.gd")
const FurnitureValidator := preload("res://tools/validate_furniture_layout.gd")
const Serializer := preload("res://editor/ScenarioSerializer.gd")

var errors: Array[String] = []
var checks: int = 0
var homes: int = 0
var visible_pieces: int = 0
var decorative_pieces: int = 0
var injected_outside: bool = false


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		errors.append(label)


func _run() -> void:
	for preset in Templates.new().get_preset_definitions():
		var name: String = String(preset["id"])
		var data: Dictionary = Templates.new().create_product_preset(name)
		check(not data.is_empty(), name + ": product source")
		data = Serializer.to_runtime_json_data(Serializer.normalize_editor_data(data))
		for room_data in data["rooms_data"]:
			check(bool(room_data.get("visual_furniture_fill", false)), name + ": visual policy survives serialization")
		var building: BuildingModel = Building.new()
		if not building.load_template_data(data):
			check(false, name + ": model rejected product")
			building.free()
			continue
		homes += 1
		var fp: FirstPersonController = FP.new()
		fp.exterior_context_enabled = false
		fp.show_fp_detectors = false
		fp.show_fp_victims = false
		root.add_child(fp)
		await process_frame
		fp.setup(building)
		await physics_frame
		var overview: Visualizer3D = Overview.new()
		var measurement := FurnitureValidator.new()
		for room_id in building.rooms:
			var room: RoomModel = building.get_room(room_id)
			check(room.visual_furniture_fill, name + ": visual policy loaded")
			var rect: Rect2 = building.room_rect_m[room_id]
			var pieces: Array = Layout.normalize_room(building, room_id, rect,
				Read.fuel_object_snapshots(room, true), true)
			if room.kind in ["salon", "dormitorio", "cocina"] and rect.get_area() >= 2.0:
				check(not pieces.is_empty(), name + ": furnished room %d" % room_id)
			var boxes: Array[AABB] = []
			var item: Dictionary = fp._furniture_nodes_by_room[room_id]
			var nodes: Dictionary = item["fuel_obj_nodes"]
			var room_min: Vector2 = rect.position + fp._origin_offset_m
			for piece in pieces:
				var id: String = String(piece["id"])
				check(nodes.has(id), name + ": planned piece actually built " + id)
				if not nodes.has(id):
					continue
				if not injected_outside and "--acceptance-control=outside" in OS.get_cmdline_user_args():
					nodes[id].position.x += 100.0
					injected_outside = true
				visible_pieces += 1
				if bool(piece.get("visual_only", false)):
					decorative_pieces += 1
					check(not piece.has("fuel_energy_MJ"), name + ": decoration has no energy")
				# size_m es el destino del cargador, no su caja conseguida. Medir
				# las mallas reales con el mismo helper del guardarrail historico.
				var bounds: AABB = measurement._world_aabb(nodes[id])
				check(bounds.size != Vector3.ZERO, name + ": piece has visible mesh " + id)
				var box := Rect2(Vector2(bounds.position.x, bounds.position.z) - room_min,
					Vector2(bounds.size.x, bounds.size.z))
				check(box.position.x >= -0.02 and box.position.y >= -0.02
					and box.end.x <= rect.size.x + 0.02 and box.end.y <= rect.size.y + 0.02,
					name + ": drawn furniture within room " + id + " " + str(box))
				check(bounds.end.y <= room.floor_level_z_m + room.height_m - 0.02,
					name + ": drawn furniture below ceiling " + id)
				if bounds.end.y - room.floor_level_z_m <= 0.12:
					continue
				for previous in boxes:
					var previous_box := Rect2(Vector2(previous.position.x, previous.position.z) - room_min,
						Vector2(previous.size.x, previous.size.z))
					var vertical: float = minf(bounds.end.y, previous.end.y) - maxf(bounds.position.y, previous.position.y)
					check(vertical < 0.05 or box.intersection(previous_box).get_area() <= 0.01,
						name + ": nonoverlapping drawn furniture " + id)
				boxes.append(bounds)
		for index in range(building.openings.size()):
			var op: OpeningModel = building.get_opening_at(index)
			if op.type != OpeningModel.Type.DOOR:
				continue
			var info: Dictionary = fp._opening_info(index)
			check(not info.is_empty(), name + ": door has a real wall %d" % index)
			if info.is_empty():
				continue
			var tangent: Vector3 = info["tangent"]
			check(tangent == Vector3.RIGHT or tangent == Vector3.BACK,
				name + ": canonical hinge tangent")
			var normal: Vector3 = info["normal"]
			if op.swing_direction == "out":
				normal = -normal
			var overview_normal: Vector2 = overview._door_swing_normal_xz(op,
				absf(tangent.x) > absf(tangent.z))
			check(Vector2(normal.x, normal.z).is_equal_approx(overview_normal),
				name + ": matching FP/overview swing")
			building.set_opening_fraction(index, 0.0)
			fp._update_opening_panel(index)
			building.set_opening_fraction(index, 1.0)
			fp._update_opening_panel(index)
		if name == "two_storey_house":
			var world: Node3D = fp._world_root
			check(world.get_node_or_null("StairFlightA") != null, "two_storey: first flight built")
			check(world.get_node_or_null("StairFlightB") != null, "two_storey: return flight built")
			check(world.get_node_or_null("StairSwitchbackLanding") != null, "two_storey: landing built")
		measurement.free()
		overview.free()
		fp.free()
		building.free()
		await process_frame
	check(homes == 10, "all ten playable homes loaded")
	print("PLAYABLE_HOMES_RESULT " + JSON.stringify({"homes": homes, "checks": checks,
		"visible_pieces": visible_pieces, "decorative_pieces": decorative_pieces,
		"injected_outside": injected_outside, "errors": errors}))
	quit(0 if errors.is_empty() else 1)
