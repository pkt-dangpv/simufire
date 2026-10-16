extends SceneTree

## Sonda de sim/core/DetMath.gd para tests/test_det_math.py.
## Lee entradas (bits hex) de --in=<json>, escribe en --out=<json> los bits de
## DetMath en el hilo principal y en un hilo trabajador, y el coste medio por
## llamada de DetMath y de la función de Godot equivalente.
const DetMath := preload("res://sim/core/DetMath.gd")
const BENCH_CALLS: int = 20000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var in_path: String = ""
	var out_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--in="):
			in_path = arg.trim_prefix("--in=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(in_path))
	var main_bits: Dictionary = _evaluate(cases)
	var holder: Dictionary = {}
	var task: int = WorkerThreadPool.add_task(func() -> void:
		holder["bits"] = _evaluate(cases), true, "det_math_probe")
	WorkerThreadPool.wait_for_task_completion(task)
	var out: Dictionary = {
		"main": main_bits,
		"worker_identical": var_to_bytes(holder["bits"]) == var_to_bytes(main_bits),
		"worker": holder["bits"],
		"bench_ns": _bench(),
	}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	quit(0)


func _f(hex: String) -> float:
	var bytes: PackedByteArray = hex.hex_decode()
	bytes.reverse()
	return bytes.decode_double(0)


func _h(x: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, x)
	bytes.reverse()
	return bytes.hex_encode()


func _evaluate(cases: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in cases:
		var results: Array[String] = []
		for args: Array in cases[name]:
			var a: float = _f(args[0])
			var b: float = _f(args[1]) if args.size() > 1 else 0.0
			var c: float = _f(args[2]) if args.size() > 2 else 0.0
			var r: float
			match name:
				"exp":
					r = DetMath.exp(a)
				"log":
					r = DetMath.log(a)
				"pow":
					r = DetMath.pow(a, b)
				"sin":
					r = DetMath.sin(a)
				"cos":
					r = DetMath.cos(a)
				"tanh":
					r = DetMath.tanh(a)
				"lerpf":
					r = DetMath.lerpf(a, b, c)
				"lerpf_godot":
					r = lerpf(a, b, c)
				"inverse_lerp":
					r = DetMath.inverse_lerp(a, b, c)
				"inverse_lerp_godot":
					r = inverse_lerp(a, b, c)
			results.append(_h(r))
		out[name] = results
	return out


func _bench() -> Dictionary:
	var out: Dictionary = {}
	var acc: float = 0.0
	var started: int
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += exp(0.001 * float(i % 997) - 0.4)
	out["exp_godot"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += DetMath.exp(0.001 * float(i % 997) - 0.4)
	out["exp"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += pow(300.0 + float(i % 997), 1.0 / 3.0)
	out["pow_godot"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += DetMath.pow(300.0 + float(i % 997), 1.0 / 3.0)
	out["pow"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += DetMath.pow(300.0 + float(i % 997), 4.0)
	out["pow_y4"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += lerpf(1.0, 2.0, 0.001 * float(i % 997))
	out["lerpf_godot"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += DetMath.lerpf(1.0, 2.0, 0.001 * float(i % 997))
	out["lerpf"] = _ns(started)
	started = Time.get_ticks_usec()
	for i: int in range(BENCH_CALLS):
		acc += 0.001 * float(i % 997) - 0.4
	out["loop_overhead"] = _ns(started)
	out["_sink"] = acc
	return out


func _ns(started: int) -> float:
	return float(Time.get_ticks_usec() - started) * 1000.0 / float(BENCH_CALLS)
