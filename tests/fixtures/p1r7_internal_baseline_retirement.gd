extends SceneTree

const CaseRunnerScript = preload("res://sim/validation/CaseRunner.gd")

var _failed: bool = false


func _init() -> void:
	var runner = CaseRunnerScript.new()
	var stairwell_result: Dictionary = {
		"all_pass": false,
		"checks": {
			"room_upper_floor_vs_lower_floor_pressure_delta_pa": {"pass": false},
			"room_6_final_smoke_kg": {"pass": true},
		}
	}
	var valid: Dictionary = runner._load_baseline_gate_disposition(
		"cfast_two_floor_stairwell",
		"res://sim/validation/baselines/cfast_two_floor_stairwell.json",
		stairwell_result
	)
	_assert(not valid.is_empty(), "exact stairwell disposition is accepted")

	var changed_failure_set: Dictionary = stairwell_result.duplicate(true)
	changed_failure_set["checks"]["room_6_final_smoke_kg"]["pass"] = false
	_assert(
		runner._load_baseline_gate_disposition(
			"cfast_two_floor_stairwell",
			"res://sim/validation/baselines/cfast_two_floor_stairwell.json",
			changed_failure_set
		).is_empty(),
		"an extra failing check is rejected"
	)

	var no_failures: Dictionary = stairwell_result.duplicate(true)
	no_failures["checks"]["room_upper_floor_vs_lower_floor_pressure_delta_pa"]["pass"] = true
	_assert(
		runner._load_baseline_gate_disposition(
			"cfast_two_floor_stairwell",
			"res://sim/validation/baselines/cfast_two_floor_stairwell.json",
			no_failures
		).is_empty(),
		"an empty failing set is rejected"
	)

	var altered_baseline_path := "user://p1r7_altered_baseline.json"
	var altered_baseline := FileAccess.open(altered_baseline_path, FileAccess.WRITE)
	_assert(altered_baseline != null, "altered baseline fixture is writable")
	if altered_baseline != null:
		altered_baseline.store_string("{}")
		altered_baseline.close()
		_assert(
			runner._load_baseline_gate_disposition(
				"cfast_two_floor_stairwell",
				altered_baseline_path,
				stairwell_result
			).is_empty(),
			"a baseline hash mismatch is rejected"
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(altered_baseline_path))

	_assert(
		runner._load_baseline_gate_disposition(
			"unknown_case",
			"res://sim/validation/baselines/cfast_two_floor_stairwell.json",
			stairwell_result
		).is_empty(),
		"an unknown case is rejected"
	)

	runner.free()
	if _failed:
		quit(1)
		return
	print("P1R7_INTERNAL_BASELINE_RETIREMENT_PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("P1R7 internal baseline retirement: %s" % message)
