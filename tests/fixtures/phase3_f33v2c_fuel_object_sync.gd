extends SceneTree

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


var _failed: bool = false


func _init() -> void:
	var combustion = CombustionSystemScript.new()
	var ledger: Array = [
		{"id": "b", "remaining_fuel_MJ": 9.0, "eligible_flag": true,
			"allocation_weight": 1.0},
		{"id": "a", "remaining_fuel_MJ": 1.0, "eligible_flag": true,
			"allocation_weight": 9.0},
		{"id": "cold", "remaining_fuel_MJ": 5.0, "eligible_flag": false,
			"allocation_weight": 100.0},
	]
	var result: Dictionary = combustion.evaluate_phase3_canonical_fuel_object_sync(
		ledger, 5.0
	)
	_assert_true(float(result["supported_flag"]) == 1.0, "float(result['supported_flag']) == 1.0")
	_assert_true(absf(float(result["allocated_debit_MJ"]) - 5.0) < 1.0e-8, "absf(float(result['allocated_debit_MJ']) - 5.0) < 1.0e-8")
	_assert_true(absf(float(result["allocation_residual_MJ"])) < 1.0e-8, "absf(float(result['allocation_residual_MJ'])) < 1.0e-8")
	_assert_true(absf(float(result["pre_fuel_MJ"]) - 15.0) < 1.0e-8, "absf(float(result['pre_fuel_MJ']) - 15.0) < 1.0e-8")
	_assert_true(absf(float(result["proposed_fuel_MJ"]) - 10.0) < 1.0e-8, "absf(float(result['proposed_fuel_MJ']) - 10.0) < 1.0e-8")
	var proposed: Array = result["proposed_ledger"]
	_assert_true(String(proposed[0]["id"]) == "a", "String(proposed[0]['id']) == 'a'")
	_assert_true(float(proposed[0]["remaining_fuel_MJ"]) == 0.0, "float(proposed[0]['remaining_fuel_MJ']) == 0.0")
	_assert_true(absf(float(proposed[1]["remaining_fuel_MJ"]) - 5.0) < 1.0e-8, "absf(float(proposed[1]['remaining_fuel_MJ']) - 5.0) < 1.0e-8")
	_assert_true(float(proposed[2]["remaining_fuel_MJ"]) == 5.0, "float(proposed[2]['remaining_fuel_MJ']) == 5.0")
	_assert_true(float(result["exhausted_count"]) == 1.0, "float(result['exhausted_count']) == 1.0")

	var duplicate: Dictionary = combustion.evaluate_phase3_canonical_fuel_object_sync(
		[
			{"id": "x", "remaining_fuel_MJ": 1.0, "eligible_flag": true,
				"allocation_weight": 1.0},
			{"id": "x", "remaining_fuel_MJ": 1.0, "eligible_flag": true,
				"allocation_weight": 1.0},
		],
		1.0
	)
	_assert_true(float(duplicate["supported_flag"]) == 0.0, "float(duplicate['supported_flag']) == 0.0")
	_assert_true(float(duplicate["rejection_mask"]) == 8.0, "float(duplicate['rejection_mask']) == 8.0")

	var zero: Dictionary = combustion.evaluate_phase3_canonical_fuel_object_sync(
		ledger, 0.0
	)
	_assert_true(float(zero["supported_flag"]) == 1.0, "float(zero['supported_flag']) == 1.0")
	_assert_true(absf(float(zero["pre_fuel_MJ"]) - float(zero["proposed_fuel_MJ"])) < 1.0e-8, "absf(float(zero['pre_fuel_MJ']) - float(zero['proposed_fuel_MJ'])) < 1.0e-8")

	var zone_system = Phase3ZoneMassSystemScript.new()
	var committed: Array = zone_system._interpolate_fuel_object_ledger(
		ledger, proposed, 0.25
	)
	_assert_true(String(committed[0]["id"]) == "a", "String(committed[0]['id']) == 'a'")
	_assert_true(absf(float(committed[0]["remaining_fuel_MJ"]) - 0.75) < 1.0e-8, "absf(float(committed[0]['remaining_fuel_MJ']) - 0.75) < 1.0e-8")
	_assert_true(absf(float(committed[1]["remaining_fuel_MJ"]) - 8.0) < 1.0e-8, "absf(float(committed[1]['remaining_fuel_MJ']) - 8.0) < 1.0e-8")
	_assert_true(float(committed[2]["remaining_fuel_MJ"]) == 5.0, "float(committed[2]['remaining_fuel_MJ']) == 5.0")
	# `quit()` only requests a shutdown, so execution continues. Return
	# explicitly or the PASS marker below would still be printed.
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V2C_FUEL_OBJECT_SYNC_PASS")
	quit(0)


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true
