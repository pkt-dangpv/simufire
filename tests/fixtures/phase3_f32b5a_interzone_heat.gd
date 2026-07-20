extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


func _init() -> void:
	_test_hot_upper_moves_heat_conservatively()
	_test_equal_and_inverted_zones_request_zero()
	_test_tiny_zone_is_safe()
	_test_equilibrium_cap_prevents_crossing()
	_test_many_steps_conserve_energy()
	_test_atomic_apply_and_duplicate_rejection()
	_test_atomic_limit_after_prior_energy_loss()
	print("PHASE3_F32B5A_INTERZONE_HEAT_PASS")
	quit(0)


func _test_hot_upper_moves_heat_conservatively() -> void:
	var thermal = _make_thermal()
	var preview: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
		_input(10.0, 5.0, 800.0, 0.0), 1.0
	)
	_assert_true(float(preview["sensible_enthalpy_kj"]) > 0.0, "hot upper request")
	_assert_true(
		float(preview["capacity_candidate_kj"]) < float(preview["legacy_candidate_kj"]),
		"reduced capacity candidate"
	)
	_assert_close(float(preview["direction_code"]), 1.0, "upper to lower direction")


func _test_equal_and_inverted_zones_request_zero() -> void:
	var thermal = _make_thermal()
	var equal: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
		_input(10.0, 5.0, 500.0, 250.0), 1.0
	)
	_assert_close(float(equal["sensible_enthalpy_kj"]), 0.0, "equal temperature")
	_assert_close(float(equal["direction_code"]), 0.0, "equal direction")
	var inverted: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
		_input(10.0, 5.0, 300.0, 400.0), 1.0
	)
	_assert_close(float(inverted["sensible_enthalpy_kj"]), 0.0, "inverted temperature")
	_assert_close(float(inverted["direction_code"]), -1.0, "blocked inversion")


func _test_tiny_zone_is_safe() -> void:
	var thermal = _make_thermal()
	for masses in [[1.0e-12, 5.0], [10.0, 1.0e-12]]:
		var preview: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
			_input(float(masses[0]), float(masses[1]), 100.0, 0.0), 1.0
		)
		_assert_close(float(preview["sensible_enthalpy_kj"]), 0.0, "tiny zone")


func _test_equilibrium_cap_prevents_crossing() -> void:
	var thermal = _make_thermal()
	thermal.upper_to_lower_loss_rate = 100.0
	thermal.lower_layer_warming_rate = 0.0
	var preview: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
		_input(10.0, 5.0, 800.0, 0.0), 1.0
	)
	var moved_kj: float = float(preview["sensible_enthalpy_kj"])
	_assert_close(moved_kj, float(preview["equilibrium_limit_kj"]), "equilibrium cap")
	var upper_after_c: float = 20.0 + (800.0 - moved_kj) / 10.0
	var lower_after_c: float = 20.0 + moved_kj / 5.0
	_assert_close(upper_after_c, lower_after_c, "no temperature crossing")
	_assert_close((800.0 - moved_kj) + moved_kj, 800.0, "energy conservation")


func _test_many_steps_conserve_energy() -> void:
	var thermal = _make_thermal()
	var upper_energy_kj: float = 800.0
	var lower_energy_kj: float = 0.0
	for _step in range(500):
		var preview: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
			_input(10.0, 5.0, upper_energy_kj, lower_energy_kj), 0.1
		)
		var moved_kj: float = float(preview["sensible_enthalpy_kj"])
		upper_energy_kj -= moved_kj
		lower_energy_kj += moved_kj
		_assert_true(upper_energy_kj >= -1.0e-9, "non-negative upper energy")
		_assert_true(
			20.0 + upper_energy_kj / 10.0 + 1.0e-9 >= 20.0 + lower_energy_kj / 5.0,
			"no oscillation"
		)
	_assert_close(upper_energy_kj + lower_energy_kj, 800.0, "many-step energy")


func _test_atomic_apply_and_duplicate_rejection() -> void:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 5.0
	room.upper_energy_kj = 800.0
	room.lower_energy_kj = 0.0
	building.rooms = {0: room}
	var thermal = _make_thermal()
	thermal.upper_to_lower_loss_rate = 100.0
	thermal.lower_layer_warming_rate = 0.0
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building)
	var canonical_input: Dictionary = system.get_canonical_thermodynamic_input(room, 20.0)
	var preview: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
		canonical_input, 1.0
	)
	_assert_true(system.queue_canonical_interzone_heat_transfer(0, preview, "1"), "first bundle")
	_assert_true(
		not system.queue_canonical_interzone_heat_transfer(0, preview, "1"),
		"duplicate bundle rejected"
	)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results().get("0", {})
	var upper_after: float = float(result["phase3_shadow_upper_energy_kj"])
	var lower_after: float = float(result["phase3_shadow_lower_energy_kj"])
	_assert_close(upper_after + lower_after, 800.0, "atomic energy conservation")
	_assert_close(
		float(result["phase3_shadow_interzone_requested_kj"]),
		float(result["phase3_shadow_interzone_accepted_kj"]),
		"atomic accepted"
	)
	_assert_close(float(result["phase3_shadow_interzone_rejected_kj"]), 0.0, "atomic rejected")
	_assert_close(float(result["phase3_shadow_interzone_energy_residual_kj"]), 0.0, "atomic residual")
	_assert_close(float(result["phase3_shadow_atomic_duplicate_bundle_count"]), 1.0, "duplicate count")
	building.free()


func _test_atomic_limit_after_prior_energy_loss() -> void:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 5.0
	room.upper_energy_kj = 800.0
	room.lower_energy_kj = 0.0
	building.rooms = {0: room}
	var thermal = _make_thermal()
	thermal.upper_to_lower_loss_rate = 100.0
	thermal.lower_layer_warming_rate = 0.0
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building)
	var preview: Dictionary = thermal.preview_phase3_canonical_interzone_heat_flux(
		system.get_canonical_thermodynamic_input(room, 20.0), 1.0
	)
	system.add_request(system.make_request(
		"prior_upper_loss", "test_prior_upper_loss", 0, -1,
		"upper", "upper", 0.0, 700.0, 0.0, {}
	))
	_assert_true(system.queue_canonical_interzone_heat_transfer(0, preview, "2"), "limited bundle")
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results().get("0", {})
	_assert_close(float(result["phase3_shadow_interzone_accepted_kj"]), 100.0, "available energy cap")
	_assert_true(float(result["phase3_shadow_interzone_rejected_kj"]) > 0.0, "rejected energy visible")
	_assert_close(float(result["phase3_shadow_upper_energy_kj"]), 0.0, "upper remains non-negative")
	_assert_close(float(result["phase3_shadow_lower_energy_kj"]), 100.0, "only available energy credited")
	_assert_close(float(result["phase3_shadow_interzone_energy_residual_kj"]), 0.0, "limited residual")
	building.free()


func _make_thermal():
	var thermal = ThermalSystemScript.new()
	thermal.upper_to_lower_loss_rate = 0.025
	thermal.lower_layer_warming_rate = 0.012
	thermal.lower_layer_energy_fade_m = 0.5
	return thermal


func _input(
		upper_mass_kg: float,
		lower_mass_kg: float,
		upper_energy_kj: float,
		lower_energy_kj: float
	) -> Dictionary:
	return {
		"valid": true,
		"upper_gas_kg": upper_mass_kg,
		"lower_gas_kg": lower_mass_kg,
		"upper_energy_kj": upper_energy_kj,
		"lower_energy_kj": lower_energy_kj,
		"temp_upper_c": 20.0 + upper_energy_kj / maxf(upper_mass_kg, 1.0e-12),
		"temp_lower_c": 20.0 + lower_energy_kj / maxf(lower_mass_kg, 1.0e-12),
		"interface_m": 0.5,
	}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		quit(1)


func _assert_close(
		actual: float,
		expected: float,
		label: String,
		tolerance: float = 1.0e-8
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %.12g got %.12g" % [label, expected, actual])
		quit(1)
