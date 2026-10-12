extends SceneTree

## Synthetic M4-A1 only. No SimulationEngine, RoomModel or fire is instantiated.
const PartitionModel = preload("res://sim/core/OxygenReferencePartition.gd")
var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _near(a: float, b: float, label: String) -> void:
	_check(is_finite(a) and is_finite(b) and absf(a - b) <= 1.0e-9, label)


func _initial() -> Dictionary:
	return {"total_kg": 7.0, "upper_kg": 1.0, "upper_base_kg": 10.0, "lower_base_kg": 30.0}


func _audit(result: Dictionary, label: String) -> bool:
	_check(bool(result.get("valid", false)), label + " accepted")
	if not bool(result.get("valid", false)):
		return false
	var r: Dictionary = result["receipt"]
	var before: Dictionary = r["before"]
	var after: Dictionary = r["after"]
	_near(after.total_kg - before.total_kg, r.room_delta_kg, label + " P1 room")
	_near(after.upper_kg - before.upper_kg, r.upper_delta_kg, label + " P2 upper")
	_near((after.total_kg - after.upper_kg) - (before.total_kg - before.upper_kg),
		r.lower_delta_kg, label + " P3 lower")
	_near(r.upper_delta_kg + r.lower_delta_kg, r.room_delta_kg, label + " P4 pair")
	_near(after.upper_base_kg + after.lower_base_kg,
		before.upper_base_kg + before.lower_base_kg, label + " P6 base")
	if r.cause == "interface_remap" or r.cause == "imposed_mixing":
		_check(after.total_kg == before.total_kg, label + " P5 exact total")
	_check(result.state == after, label + " receipt matches state")
	return true


func _rejected(result: Dictionary, before: Dictionary, snapshot: Dictionary, label: String) -> void:
	_check(not bool(result.get("valid", true)), label + " rejected")
	_check(not result.has("state") and not result.has("receipt"), label + " no candidate state")
	_check(before == snapshot, label + " input unchanged")


func _sample(operation: String, input: Dictionary, argument: Variant, result: Dictionary) -> void:
	if bool(result.get("valid", false)):
		samples.append({"operation": operation, "input": input.duplicate(true),
			"argument": argument, "after": result.state, "receipt": result.receipt})


func _run() -> void:
	var initial: Dictionary = _initial()
	var declared: Dictionary = PartitionModel.make_state(7.0, 1.0, 10.0, 30.0)
	_check(bool(declared.get("valid", false)), "initial accepted")
	for bad: Variant in [true, "1", null, NAN, INF, -INF]:
		var malformed: Dictionary = _initial()
		malformed["total_kg"] = bad
		_check(not PartitionModel.validate(malformed).is_empty(), "invalid state number")
		_rejected(PartitionModel.mix(malformed, 0.5), initial, _initial(), "invalid operation state")
	for fields: Array in [[-1.0, 0.0, 10.0, 30.0], [1.0, 2.0, 10.0, 30.0],
			[1.0, -1.0e-12, 10.0, 30.0], [7.0, 1.0, 0.0, 40.0], [7.0, 1.0, 10.0, 0.0],
			[41.0, 10.0, 10.0, 30.0], [0.0, 0.0, 0.0, 0.0], [7.0, 1.0, -10.0, 50.0],
			[0.0, 0.0, 1.0e308, 1.0e308]]:
		var bad_state: Dictionary = PartitionModel.make_state(fields[0], fields[1], fields[2], fields[3])
		_check(not bool(bad_state.get("valid", true)), "invalid state range rejected")
	_check(not PartitionModel.validate(null).is_empty(), "null state refused")
	_check(not PartitionModel.validate([]).is_empty(), "array state refused")
	_check(not PartitionModel.validate({}).is_empty(), "missing state fields refused")
	var extra: Dictionary = initial.duplicate(true)
	extra["lower_kg"] = 6.0
	_check(not PartitionModel.validate(extra).is_empty(), "second lower authority refused")

	var bases: Array[float] = [0.0, 5.0, 10.0, 20.0, 30.0, 40.0]
	var answers: Array[float] = [0.0, 0.5, 1.0, 3.0, 5.0, 7.0]
	for i: int in range(bases.size()):
		var remapped: Dictionary = PartitionModel.remap(initial, bases[i])
		if _audit(remapped, "remap"):
			_near(remapped.state.upper_kg, answers[i], "analytic remap donor")
			_sample("remap", initial, bases[i], remapped)
	_check(initial == _initial(), "remap input immutable")

	for alpha: float in [0.0, 0.5, 1.0]:
		var mixed: Dictionary = PartitionModel.mix(initial, alpha)
		if _audit(mixed, "mix"):
			_near(mixed.state.upper_kg, 1.0 + alpha * 0.75, "analytic mix target")
			_sample("mix", initial, alpha, mixed)
	var reverse: Dictionary = {"total_kg": 7.0, "upper_kg": 3.0,
		"upper_base_kg": 10.0, "lower_base_kg": 30.0}
	var reversed: Dictionary = PartitionModel.mix(reverse, 0.5)
	if _audit(reversed, "reverse mix"):
		_near(reversed.state.upper_kg, 2.375, "mix donates in both directions")
		_sample("mix", reverse, 0.5, reversed)
	_check(initial == _initial(), "mix input immutable")

	for pair: Array in [[0.0, -0.076], [0.1, -0.1], [0.03, 0.07]]:
		var adjusted: Dictionary = PartitionModel.budget(initial, pair[0], pair[1], "imposed_budget")
		if _audit(adjusted, "budget"):
			_near(adjusted.state.total_kg, 7.0 + pair[0] + pair[1], "budget total once")
			_near(adjusted.state.upper_kg, 1.0 + pair[0], "budget upper once")
			_sample("budget", initial, pair, adjusted)
	_check(initial == _initial(), "budget input immutable")

	for bad: Variant in [true, "1", null, NAN, INF, -INF]:
		_rejected(PartitionModel.remap(initial, bad), initial, _initial(), "remap bad number")
		_rejected(PartitionModel.mix(initial, bad), initial, _initial(), "mix bad number")
		_rejected(PartitionModel.budget(initial, bad, 0.0, "bad"), initial, _initial(), "budget bad number")
	for bad: float in [-1.0, 41.0]:
		_rejected(PartitionModel.remap(initial, bad), initial, _initial(), "remap outside base")
	for bad: float in [-0.01, 1.01]:
		_rejected(PartitionModel.mix(initial, bad), initial, _initial(), "mix outside unit interval")
	for pair: Array in [[0.0, -7.0], [-2.0, 0.0], [10.0, 0.0], [0.0, 25.0]]:
		_rejected(PartitionModel.budget(initial, pair[0], pair[1], "bad"),
			initial, _initial(), "budget cannot clip overdraft or overflow")
	for cause: Variant in ["", " ", null, true, 12]:
		_rejected(PartitionModel.budget(initial, 0.0, 0.0, cause),
			initial, _initial(), "budget invalid cause")

	for fraction: float in [0.0, 1.0]:
		var absent: Dictionary = {"total_kg": 7.0, "upper_kg": 7.0 * fraction,
			"upper_base_kg": 40.0 * fraction, "lower_base_kg": 40.0 * (1.0 - fraction)}
		var observed: Dictionary = PartitionModel.observables(absent)
		_check(bool(observed.get("valid", false)), "absent observables accepted")
		_check(observed.get("upper" if fraction == 0.0 else "lower", -1) == null,
			"absent zone is null not zero or epsilon")
		var absent_mix: Dictionary = PartitionModel.mix(absent, 1.0)
		if _audit(absent_mix, "absent mix"):
			_check(absent_mix.state == absent, "absent mixing changes nothing")
			_sample("mix", absent, 1.0, absent_mix)
		var born: Dictionary = PartitionModel.remap(absent, 10.0)
		if _audit(born, "born"):
			_near(born.state.upper_kg, 1.75, "birth from the existing donor")
			_sample("remap", absent, 10.0, born)

	var rich: Dictionary = {"total_kg": 12.0, "upper_kg": 6.0,
		"upper_base_kg": 10.0, "lower_base_kg": 30.0}
	var rich_result: Dictionary = PartitionModel.mix(rich, 0.0)
	if _audit(rich_result, "rich"):
		_near(rich_result.state.upper_kg, 6.0, "no ambient ceiling")
		_sample("mix", rich, 0.0, rich_result)

	var sequence: Dictionary = _initial()
	var max_gap: float = 0.0
	var iterations: int = 0
	if failures.is_empty():
		for index: int in range(10000):
			var new_base: float = 0.01 + float((index * 37) % 999) * 39.98 / 998.0
			var moved: Dictionary = PartitionModel.remap(sequence, new_base)
			if not _audit(moved, "sequence remap"):
				break
			var fraction: float = float((index * 17) % 100) / 100.0
			var combined: Dictionary = PartitionModel.mix(moved.state, fraction)
			if not _audit(combined, "sequence mix"):
				break
			sequence = combined.state
			iterations += 1
			max_gap = maxf(max_gap, absf(float(sequence.total_kg) - 7.0))
			if not failures.is_empty():
				break
		_check(iterations == 10000, "complete deterministic sequence")
		_near(max_gap, 0.0, "no cumulative oxygen drift")

	# Returned dictionaries are snapshots, not aliases of the input or each other.
	var alias_input: Dictionary = _initial()
	var alias_result: Dictionary = PartitionModel.mix(alias_input, 0.5)
	if bool(alias_result.get("valid", false)):
		alias_result.state["upper_kg"] = 0.0
		_check(alias_input == _initial(), "result cannot mutate input")
		_near(alias_result.receipt.after.upper_kg, 1.375, "receipt after snapshot isolated")
	print("G3_O2_M4_PARTITION " + JSON.stringify({"checks": checks,
		"failure_count": failures.size(), "failures": failures, "samples": samples,
		"iterations": iterations, "maximum_total_gap_kg": max_gap}))
	quit(0 if failures.is_empty() else 1)
