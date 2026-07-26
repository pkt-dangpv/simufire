extends SceneTree

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


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
	assert(float(result["supported_flag"]) == 1.0)
	assert(absf(float(result["allocated_debit_MJ"]) - 5.0) < 1.0e-8)
	assert(absf(float(result["allocation_residual_MJ"])) < 1.0e-8)
	assert(absf(float(result["pre_fuel_MJ"]) - 15.0) < 1.0e-8)
	assert(absf(float(result["proposed_fuel_MJ"]) - 10.0) < 1.0e-8)
	var proposed: Array = result["proposed_ledger"]
	assert(String(proposed[0]["id"]) == "a")
	assert(float(proposed[0]["remaining_fuel_MJ"]) == 0.0)
	assert(absf(float(proposed[1]["remaining_fuel_MJ"]) - 5.0) < 1.0e-8)
	assert(float(proposed[2]["remaining_fuel_MJ"]) == 5.0)
	assert(float(result["exhausted_count"]) == 1.0)

	var duplicate: Dictionary = combustion.evaluate_phase3_canonical_fuel_object_sync(
		[
			{"id": "x", "remaining_fuel_MJ": 1.0, "eligible_flag": true,
				"allocation_weight": 1.0},
			{"id": "x", "remaining_fuel_MJ": 1.0, "eligible_flag": true,
				"allocation_weight": 1.0},
		],
		1.0
	)
	assert(float(duplicate["supported_flag"]) == 0.0)
	assert(float(duplicate["rejection_mask"]) == 8.0)

	var zero: Dictionary = combustion.evaluate_phase3_canonical_fuel_object_sync(
		ledger, 0.0
	)
	assert(float(zero["supported_flag"]) == 1.0)
	assert(absf(float(zero["pre_fuel_MJ"]) - float(zero["proposed_fuel_MJ"])) < 1.0e-8)

	var zone_system = Phase3ZoneMassSystemScript.new()
	var committed: Array = zone_system._interpolate_fuel_object_ledger(
		ledger, proposed, 0.25
	)
	assert(String(committed[0]["id"]) == "a")
	assert(absf(float(committed[0]["remaining_fuel_MJ"]) - 0.75) < 1.0e-8)
	assert(absf(float(committed[1]["remaining_fuel_MJ"]) - 8.0) < 1.0e-8)
	assert(float(committed[2]["remaining_fuel_MJ"]) == 5.0)
	print("PHASE3_F33V2C_FUEL_OBJECT_SYNC_PASS")
	quit()
