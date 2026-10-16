extends SceneTree

## Huella de determinismo del motor (headless). Lanzar con
## `tools/determinism_fingerprint.py`, que fija el escenario y aísla `user://`.
##
## Mide dos cosas comparables entre máquinas, hilos y builds:
##   1. `math`: SHA-256 de las funciones matemáticas sobre una rejilla fija de
##      entradas, en el hilo principal y en un hilo trabajador: `det_*` son las
##      de sim/core/DetMath.gd, que usa el motor y deben coincidir en todas
##      partes; `godot_*` son las de Godot, solo como información.
##   2. `runs`: el escenario de producto avanzado N pasos de referencia (1/12 s);
##      cada `checkpoint_every` pasos, SHA-256 del estado exportado en ese paso y
##      de la cadena de todos los estados hasta él. Con `--worker` repite la
##      corrida con el paso y la exportación en un hilo trabajador.
## Imprime una única línea `DETERMINISM_FINGERPRINT <json>`.
const Scene := preload("res://scenes/SimulationScene.tscn")
const DetMath := preload("res://sim/core/DetMath.gd")
const PREFIX: String = "DETERMINISM_FINGERPRINT "
const STEP_S: float = 1.0 / 12.0
const MATH_SAMPLES: int = 2000

var steps: int = 7200
var checkpoint_every: int = 600
var with_worker: bool = false
var math_results: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="):
			steps = int(arg.trim_prefix("--steps="))
		elif arg.begins_with("--checkpoint-every="):
			checkpoint_every = int(arg.trim_prefix("--checkpoint-every="))
		elif arg == "--worker":
			with_worker = true
	call_deferred("_run")


func _run() -> void:
	var out: Dictionary = {
		"schema": "simufire_determinism_fingerprint_v2",
		"godot_version": Engine.get_version_info(),
		"editor_build": OS.has_feature("editor"),
		"template_build": OS.has_feature("template"),
		"debug_build": OS.is_debug_build(),
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"processor_name": OS.get_processor_name(),
		"processor_count": OS.get_processor_count(),
		"step_s_bytes": var_to_bytes(STEP_S).hex_encode(),
		"steps": steps,
		"checkpoint_every": checkpoint_every,
	}
	_math_probe("main")
	var task: int = WorkerThreadPool.add_task(_math_probe.bind("worker"), true, "fingerprint_math")
	WorkerThreadPool.wait_for_task_completion(task)
	out["math"] = math_results
	out["runs"] = {"main": await _run_scenario(false)}
	if with_worker:
		out["runs"]["worker"] = await _run_scenario(true)
	print(PREFIX + JSON.stringify(out))
	quit(0)


## Rejillas fijas construidas solo con aritmética IEEE (sin literales que el
## analizador pudiera plegar de otra forma), en los rangos que usa el motor.
func _math_probe(label: String) -> void:
	var buffers: Dictionary = {}
	for name: String in ["exp", "pow", "log", "sqrt", "sin", "cos", "tanh", "atan2"]:
		buffers["godot_" + name] = PackedByteArray()
	for name: String in ["exp", "pow", "log", "sin", "cos", "tanh", "lerpf", "inverse_lerp"]:
		buffers["det_" + name] = PackedByteArray()
	for i: int in range(MATH_SAMPLES):
		var u: float = float(i) / float(MATH_SAMPLES - 1)  # [0, 1]
		var x_exp: float = -60.0 + 120.0 * u
		var base: float = 0.001 + 999.999 * u * u
		var expo: float = -3.0 + 6.0 * float((i * 7919) % MATH_SAMPLES) / float(MATH_SAMPLES - 1)
		var x_pos: float = 1.0e-6 + 1.0e4 * u * u * u
		var x_ang: float = -20.0 + 40.0 * u
		buffers["godot_exp"].append_array(var_to_bytes(exp(x_exp)))
		buffers["godot_pow"].append_array(var_to_bytes(pow(base, expo)))
		buffers["godot_log"].append_array(var_to_bytes(log(x_pos)))
		buffers["godot_sqrt"].append_array(var_to_bytes(sqrt(x_pos)))
		buffers["godot_sin"].append_array(var_to_bytes(sin(x_ang)))
		buffers["godot_cos"].append_array(var_to_bytes(cos(x_ang)))
		buffers["godot_tanh"].append_array(var_to_bytes(tanh(x_ang * 0.25)))
		buffers["godot_atan2"].append_array(var_to_bytes(atan2(x_ang, 1.0 + u)))
		buffers["det_exp"].append_array(var_to_bytes(DetMath.exp(x_exp)))
		buffers["det_pow"].append_array(var_to_bytes(DetMath.pow(base, expo)))
		buffers["det_log"].append_array(var_to_bytes(DetMath.log(x_pos)))
		buffers["det_sin"].append_array(var_to_bytes(DetMath.sin(x_ang)))
		buffers["det_cos"].append_array(var_to_bytes(DetMath.cos(x_ang)))
		buffers["det_tanh"].append_array(var_to_bytes(DetMath.tanh(x_ang * 0.25)))
		buffers["det_lerpf"].append_array(var_to_bytes(DetMath.lerpf(x_ang, x_exp, u)))
		buffers["det_inverse_lerp"].append_array(var_to_bytes(DetMath.inverse_lerp(x_ang, x_exp + 61.0, u)))
	var hashes: Dictionary = {}
	for name: String in buffers:
		hashes[name] = _sha256(buffers[name])
	math_results[label] = hashes


func _run_scenario(in_worker: bool) -> Dictionary:
	var main: Node = Scene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.playback_paused = true
	main.engine.suppress_exit_graphs()
	await process_frame
	await process_frame
	var engine: Node = main.engine
	var chain := HashingContext.new()
	chain.start(HashingContext.HASH_SHA256)
	var checkpoints: Array = []
	for i: int in range(steps):
		var holder: Dictionary = {}
		var job: Callable = func() -> void:
			engine.step(STEP_S)
			holder["state"] = engine.get_state()
		if in_worker:
			var task: int = WorkerThreadPool.add_task(job, true, "fingerprint_step")
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			job.call()
		var state_bytes: PackedByteArray = var_to_bytes(holder["state"])
		chain.update(state_bytes)
		if (i + 1) % checkpoint_every == 0 or i == steps - 1:
			var chain_copy: PackedByteArray = _chain_digest(chain)
			checkpoints.append({
				"step": i + 1,
				"sim_time_s": engine.sim_time_s,
				"state_sha256": _sha256(state_bytes),
				"chain_sha256": chain_copy.hex_encode(),
			})
	var result: Dictionary = {
		"checkpoints": checkpoints,
		"final_sim_time_s": engine.sim_time_s,
		"is_finished": engine.is_finished,
	}
	main.free()
	await process_frame
	return result


## HashingContext no se puede copiar: en cada punto de control la cadena se
## cierra y se reabre sembrada con su propio resumen, de modo que el siguiente
## sigue dependiendo de todos los estados anteriores.
func _chain_digest(chain: HashingContext) -> PackedByteArray:
	var digest: PackedByteArray = chain.finish()
	chain.start(HashingContext.HASH_SHA256)
	chain.update(digest)
	return digest


func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
