extends SceneTree

## Resource invalidation experiment; headless CPU, never FPS/GPU evidence.
const Scene := preload("res://scenes/SimulationScene.tscn")
const Overlap := preload("res://tests/fixtures/product_furniture_overlap.gd")
const REPEATS: int = 30
var changes: Dictionary = {}
var resources: Array = []
var samples: Dictionary = {}
var phases: Dictionary = {}
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _changed(label: String) -> void:
	changes[label] = int(changes.get(label, 0)) + 1


func _record(label: String, elapsed: int) -> void:
	if not samples.has(label):
		samples[label] = []
	samples[label].append(elapsed)


func _flush_meshes() -> void:
	for item: Dictionary in resources:
		if item["resource"] is BoxMesh:
			item["resource"].get_surface_count()


func _geometry() -> String:
	var data: Array = []
	for item: Dictionary in resources:
		var resource: Resource = item["resource"]
		if resource is BoxMesh:
			data.append([item["label"], resource.size, resource.surface_get_arrays(0)])
		else:
			data.append([item["label"], resource.size])
	return var_to_bytes(data).hex_encode().sha256_text()


func _run() -> void:
	var main = Scene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.playback_paused = true
	main.engine.suppress_exit_graphs()
	main._set_first_person_enabled(true)
	var fp = main.first_person_controller
	fp.set_physics_process(false)
	main.visualizer_3d.set_process(false)
	for index: Variant in fp._opening_nodes:
		var item: Dictionary = fp._opening_nodes[index]
		var mesh := item.get("mesh") as MeshInstance3D
		var shape := item.get("shape") as CollisionShape3D
		if mesh != null and mesh.mesh is BoxMesh:
			resources.append({"label": "mesh_" + str(index), "resource": mesh.mesh})
		if shape != null and shape.shape is BoxShape3D:
			resources.append({"label": "shape_" + str(index), "resource": shape.shape})
	_flush_meshes()
	await process_frame
	for item: Dictionary in resources:
		item["size"] = item["resource"].size
		item["resource"].changed.connect(_changed.bind(item["label"]))
	var geometry_before: String = _geometry()
	var overlap: Dictionary = Overlap.read(main)
	var engine_before: PackedByteArray = var_to_bytes(main.engine.get_state())
	if resources.is_empty():
		errors.append("no opening resources")
	# Prediction: unchanged assignments cause resource invalidations; an exact
	# equality guard removes them, but must still admit a genuinely changed size.
	for phase: String in ["actual_sync", "same_size_writes", "guarded_same_size"]:
		changes.clear()
		for repeat: int in range(REPEATS):
			var start: int = Time.get_ticks_usec()
			if phase == "actual_sync":
				fp._sync_opening_panels()
			else:
				for item: Dictionary in resources:
					if phase != "guarded_same_size" or item["resource"].size != item["size"]:
						item["resource"].size = item["size"]
			_record(phase + "_write_us", Time.get_ticks_usec() - start)
			start = Time.get_ticks_usec()
			_flush_meshes()
			_record(phase + "_flush_us", Time.get_ticks_usec() - start)
			await process_frame
		phases[phase] = {"resource_changes": changes.duplicate(true),
			"geometry_identical": _geometry() == geometry_before}
		if not phases[phase]["geometry_identical"]:
			errors.append(phase + " changed geometry")
	changes.clear()
	var positive_control: Dictionary = {}
	for item: Dictionary in resources:
		if not item["resource"] is BoxMesh:
			continue
		var requested: Vector3 = item["size"] + Vector3(0.01, 0.0, 0.0)
		if item["resource"].size != requested:
			item["resource"].size = requested
		_flush_meshes()
		await process_frame
		positive_control = {"changed": _geometry() != geometry_before,
			"resource_changes": changes.duplicate(true)}
		item["resource"].size = item["size"]
		_flush_meshes()
		await process_frame
		break
	if not positive_control.get("changed", false):
		errors.append("positive size control did not change geometry")
	if _geometry() != geometry_before:
		errors.append("geometry not restored")
	if var_to_bytes(main.engine.get_state()) != engine_before:
		errors.append("diagnosis changed engine state")
	print("PRODUCT_CPU_PROFILE " + JSON.stringify({"view": "fp",
		"display_server": DisplayServer.get_name(), "rendered_fps_measured": false,
		"gpu_measured": false, "resources": resources.size(), "repeats": REPEATS,
		"phases": phases, "positive_control": positive_control,
		"furniture_overlap": overlap,
		"engine_state_unchanged": var_to_bytes(main.engine.get_state()) == engine_before,
		"measurements_us": samples, "errors": errors}))
	for item: Dictionary in resources:
		item["resource"].changed.disconnect(_changed.bind(item["label"]))
	resources.clear()
	main.free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
