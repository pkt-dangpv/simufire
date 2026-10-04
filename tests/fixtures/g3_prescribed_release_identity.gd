extends SceneTree

const Release = preload("res://sim/fire/PrescribedFuelReleaseModel.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/g3_mass_material_profile_synthetic.json"))
	var program: Dictionary = profile["release"].duplicate(true)
	program.erase("provenance")
	program["profile_id"] = profile["id"]
	program["initial_mass_kg"] = profile["initial_mass"]["value"]
	var initialized: Dictionary = Release.initial_progress(program)
	if not initialized.get("valid", false):
		quit(1)
		return
	var progress: Dictionary = initialized["candidate"]
	var trace: Array = [initialized]
	for end in [0.3, 1.1, 2.7, 5.0, 6.1, 7.7, 9.9, 10.0]:
		var preview: Dictionary = Release.propose(program, progress, end)
		if not preview.get("valid", false):
			quit(1)
			return
		var ack: Dictionary = Release.acknowledge(program, progress, end, float(preview["release_kg"]) * 0.5)
		if not ack.get("valid", false):
			quit(1)
			return
		trace.append({"proposal": preview, "ack": ack})
		progress = ack["candidate"]
	print("G3_LINEAR_IDENTITY " + JSON.stringify(trace, "", true, true))
	quit(0)
