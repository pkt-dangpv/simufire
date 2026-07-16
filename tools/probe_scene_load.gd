extends SceneTree
## Smoke: comprueba que las escenas principales cargan e instancian sin
## errores de parseo ni recursos rotos (no ejecuta la simulacion).
## Uso: godot --headless --path . --script res://tools/probe_scene_load.gd

const SCENES: Array[String] = [
	"res://scenes/MainMenu.tscn",
	"res://ui/GraphsWindow.tscn",
	"res://ui/TechnicalSummaryWindow.tscn",
]


func _initialize() -> void:
	var failures: int = 0
	for path in SCENES:
		var packed := load(path) as PackedScene
		if packed == null:
			print("[probe_scene_load] FAIL: no carga ", path)
			failures += 1
			continue
		var instance := packed.instantiate()
		if instance == null:
			print("[probe_scene_load] FAIL: no instancia ", path)
			failures += 1
			continue
		instance.free()
		print("[probe_scene_load] OK ", path)
	# SimulationScene: solo parseo/carga (instanciarla arrancaria el motor).
	var sim := load("res://scenes/SimulationScene.tscn") as PackedScene
	if sim == null:
		print("[probe_scene_load] FAIL: no carga res://scenes/SimulationScene.tscn")
		failures += 1
	else:
		print("[probe_scene_load] OK res://scenes/SimulationScene.tscn (load)")
	quit(0 if failures == 0 else 1)
