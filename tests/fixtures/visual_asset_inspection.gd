extends SceneTree

const Inspection := preload("res://view/3d/furniture/FurnitureAssetInspection.gd")
const Loader := preload("res://view/3d/furniture/FurnitureAssetLoader.gd")
const Contract := preload("res://view/3d/furniture/VisualAssetContract.gd")
const Layout := preload("res://view/furniture/FurnitureRoomLayout.gd")
const FP := preload("res://view/fp/FirstPersonController.gd")
const Overview := preload("res://view/3d/Visualizer3D.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _run() -> void:
	if "--invalid-tiled-control" in OS.get_cmdline_user_args():
		_check_rejected_tiled_contract()
		print("VISUAL_REJECTION_TEST_RESULT " + JSON.stringify({"checks": checks, "errors": failures}))
		quit(0 if failures.is_empty() else 1)
		return
	# Controles asimetricos: distinguen un giro de un cambio de proporcion.
	var fit: Dictionary = Loader._scale_for(Vector3(1.0, 1.0, 2.0), Vector3(4.0, 3.0, 2.0), true)
	check(is_equal_approx(float(fit["yaw"]), PI * 0.5), "long-axis rule adds 90 degrees")
	check(Vector3(fit["scale"]).is_equal_approx(Vector3(2.0, 3.0, 2.0)), "exact-fit scales by axis")
	var encoded: Dictionary = Inspection._transform(
		Transform3D(Basis(Vector3.UP, float(fit["yaw"])).scaled(Vector3(fit["scale"])), Vector3(2.0, 0.0, 1.0)))
	check(absf(float(encoded["rotation_deg"][1]) - 90.0) < 0.001, "report preserves rotation")
	check(encoded["origin"] == [2.0, 0.0, 1.0], "report preserves offset")
	check(encoded["scale"] == [2.0, 3.0, 2.0], "report preserves unequal scale")
	var nested := Node3D.new()
	var pivot := Node3D.new()
	pivot.position = Vector3(3.0, 2.0, 1.0)
	nested.add_child(pivot)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 4.0, 6.0)
	mesh.mesh = box
	pivot.add_child(mesh)
	var before: Transform3D = pivot.transform
	var bounds: AABB = Loader._get_combined_aabb(nested)
	check(bounds.position.is_equal_approx(Vector3(2.0, 0.0, -2.0)), "nested transforms measured")
	check(bounds.size.is_equal_approx(box.size), "nested size measured")
	check(pivot.transform == before, "measuring does not mutate author transform")
	nested.free()
	var report: Dictionary = Inspection.inspect("sofa", Vector2(2.1, 0.9))
	check(Array(report["errors"]).is_empty(), "real sofa can be inspected")
	check(String(report["scope"]) == "asset_loader_only_not_room_placement", "scope declared")
	check(not Array(report["runtime_instances"]).is_empty(), "real runtime transform captured")
	check(report.has("authored_bounds_m") and report.has("drawn_bounds_m"), "both bounds reported")
	_check_authored_contract()
	print("VISUAL_INSPECTION_TEST_RESULT " + JSON.stringify({"checks": checks, "errors": failures}))
	quit(0 if failures.is_empty() else 1)


func _check_rejected_tiled_contract() -> void:
	var source := Node3D.new()
	source.set_meta(Contract.KEY, 7)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	mesh.owner = source
	var packed := PackedScene.new()
	check(packed.pack(source) == OK, "invalid metadata control packs successfully")
	source.free()
	var parent := Node3D.new()
	var size: Vector3 = Loader._build_tiled(parent, packed, "kitchen_unit", "kitchen_unit",
		Vector3(1.8, 0.9, 0.6), 1.0)
	check(size == Vector3.ZERO, "rejected module is not counted as built")
	check(parent.get_child_count() == 0, "rejected module leaves no visible children")
	parent.free()


func _check_authored_contract() -> void:
	var kind: String = "authored_meter_reference"
	var native := Vector3(1.2, 1.0, 0.4)
	check(Loader.uses_authored_transform(kind), "wrapper opts in to authored metres")
	check(not Loader.uses_authored_transform("sofa"), "legacy sofa not silently migrated")
	var packed := load(Loader.model_path(kind)) as PackedScene
	var instance := packed.instantiate() as Node3D
	var bounds: AABB = Loader._get_combined_aabb(instance)
	check(Contract.validate_authored(instance, bounds).is_empty(), "valid authored wrapper")
	instance.position.x = 1.0
	check(Contract.validate_authored(instance, bounds).has("authored_root_must_be_identity"), "root transform rejected")
	instance.position = Vector3.ZERO
	check(Contract.validate_authored(instance, AABB(Vector3.ZERO, native)).has(
		"authored_pivot_must_be_floor_center"), "bad pivot rejected, not recentered")
	instance.set_meta("simufire_front_axis", "+x")
	check(Contract.validate_authored(instance, bounds).has("authored_front_axis_must_be_declared_minus_z"),
		"unknown front rejected, not guessed from longest axis")
	instance.set_meta("simufire_front_axis", 7)
	check(Contract.validate_authored(instance, bounds).has("authored_front_axis_must_be_declared_minus_z"),
		"bad front metadata rejected without script error")
	instance.set_meta(Contract.KEY, 7)
	check(Contract.mode_of(instance) == Contract.INVALID, "bad transform mode type rejected")
	instance.free()
	for target in [Vector3(5.0, 8.0, 0.1), Vector3(0.1, 0.2, 5.0)]:
		var authored := packed.instantiate() as Node3D
		var size: Vector3 = Loader._fit_instance(authored, target, 2.0, true)
		check(size.is_equal_approx(native), "target footprint does not resize authored asset")
		check(authored.transform == Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3.ZERO),
			"only view unit conversion, no yaw or reanchor")
		authored.free()
		check(Loader.resolved_size_m(kind, target).is_equal_approx(native), "planner uses authored size")
	var source: Dictionary = {"id": "manual_probe", "visual_archetype": kind,
		"size_m": Vector2(3.0, 0.5), "position_m": Vector2(2.0, 2.0), "rotation_deg": 37.0}
	var before: Dictionary = source.duplicate(true)
	var result: Array = Layout.layout_room(Vector2(0.4, 0.4), [], [source])
	check(result.size() == 1, "manual asset not hidden when it does not fit")
	var visual: Dictionary = result[0]
	check(Vector2(visual["size_m"]).is_equal_approx(Vector2(native.x, native.z)), "layout uses native footprint")
	check(is_equal_approx(float(visual["rotation_deg"]), 37.0), "layout preserves requested yaw")
	check((Vector2(visual["position_m"]) + Vector2(visual["size_m"]) * 0.5).is_equal_approx(
		Vector2(3.5, 2.25)), "layout preserves source centre, not top-left of fire footprint")
	check(bool(visual["visual_pose_locked"]), "both views bypass second clamp")
	check(Array(visual["visual_placement_issues"]).has("outside_room"), "asset that does not fit is reported")
	check(source == before, "layout does not mutate fire object specification")
	var blocked: Dictionary = source.duplicate(true)
	blocked["position_m"] = Vector2(2.0, 0.2) - Vector2(blocked["size_m"]) * 0.5
	var blocked_result: Array = Layout.layout_room(Vector2(8.0, 8.0),
		[{"side": "top", "center": 2.0, "width_m": 0.9}], [blocked])
	check(Array(blocked_result[0]["visual_placement_issues"]).has("door_clearance_conflict"),
		"door clearance conflict reported without moving authored asset")
	_check_authored_views(source)


func _check_authored_views(source: Dictionary) -> void:
	# Consumidores reales con estado sintetico, sin construir un incendio.
	var state: Dictionary = {"fuel_objects": [source], "floor_level_z_m": 0.0}
	var rect := Rect2(Vector2.ZERO, Vector2(8.0, 8.0))
	var fp: FirstPersonController = FP.new()
	var fp_root := Node3D.new()
	var fp_item: Dictionary = {"root": fp_root, "rect": rect, "fuel_obj_nodes": {}}
	fp._state = {"0": state}
	fp._update_fp_room_furniture(0, fp_item)
	var fp_node: Node3D = fp_item["fuel_obj_nodes"]["manual_probe"]
	var overview: Visualizer3D = Overview.new()
	overview.meters_to_units = 2.0
	var overview_root := Node3D.new()
	var overview_item: Dictionary = {"fuel_objects_root": overview_root,
		"room_id": 0, "floor_level_m": 0.0, "fuel_obj_nodes": {}}
	overview._update_room_fuel_objects_3d(overview_item, state, rect)
	var overview_node: Node3D = overview_item["fuel_obj_nodes"]["manual_probe"]
	check(fp_node.position.is_equal_approx(Vector3(3.5, 0.0, 2.25)), "FP preserves source centre")
	check((overview_node.position / 2.0).is_equal_approx(fp_node.position), "overview and FP same centre in metres")
	check(is_equal_approx(fp_node.rotation_degrees.y, 37.0)
		and is_equal_approx(overview_node.rotation_degrees.y, 37.0), "both consumers preserve yaw")
	var fp_asset := fp_node.get_node("Asset_authored_meter_reference") as Node3D
	var overview_asset := overview_node.get_node("Asset_authored_meter_reference") as Node3D
	check(fp_asset.transform == Transform3D.IDENTITY, "FP applies no hidden asset transform")
	check(overview_asset.transform == Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3.ZERO),
		"overview applies only view unit conversion")
	var fp_before: Transform3D = fp_node.transform
	var overview_before: Transform3D = overview_node.transform
	state["fuel_objects"][0]["state"] = "charred"
	fp._update_fp_room_furniture(0, fp_item)
	overview._update_room_fuel_objects_3d(overview_item, state, rect)
	check(fp_node.transform == fp_before and overview_node.transform == overview_before,
		"state update does not change placement")
	check(fp_node.has_meta("visual_placement_issues") and overview_node.has_meta("visual_placement_issues"),
		"both views expose placement diagnostics")
	# Mantener materiales vivos tambien en el test de consumidores headless.
	var keepalive: Array[Material] = []
	Inspection._keep_materials(fp_root, keepalive)
	Inspection._keep_materials(overview_root, keepalive)
	fp_root.free()
	overview_root.free()
	fp.free()
	overview.free()
	keepalive.clear()
