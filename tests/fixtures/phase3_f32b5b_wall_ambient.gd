extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


func _init() -> void:
	_test_hot_gas_heats_wall()
	_test_hot_wall_heats_gas()
	_test_equal_temperatures_are_quiet()
	_test_equilibrium_bound()
	_test_many_steps_conserve_gas_wall_energy()
	_test_upper_and_lower_exchange_together()
	_test_atomic_apply_and_duplicate_rejection()
	_test_prior_loss_limits_atomic_acceptance()
	print("PHASE3_F32B5B_WALL_AMBIENT_PASS")
	quit(0)


func _test_hot_gas_heats_wall() -> void:
	var preview: Dictionary = _preview(800.0, 100.0, 0.0, 1.0)
	_assert_true(float(preview["upper_wall_requested_kj"]) > 0.0, "upper heats wall")
	_assert_true(float(preview["lower_wall_requested_kj"]) > 0.0, "lower heats wall")


func _test_hot_wall_heats_gas() -> void:
	var preview: Dictionary = _preview(100.0, 0.0, 6000.0, 1.0)
	_assert_true(float(preview["upper_wall_requested_kj"]) < 0.0, "wall heats upper")
	_assert_true(float(preview["lower_wall_requested_kj"]) < 0.0, "wall heats lower")


func _test_equal_temperatures_are_quiet() -> void:
	var preview: Dictionary = _preview(100.0, 50.0, 1000.0, 1.0)
	_assert_close(float(preview["upper_wall_requested_kj"]), 0.0, "equal upper wall")
	_assert_close(float(preview["lower_wall_requested_kj"]), 0.0, "equal lower wall")
	_assert_close(float(preview["upper_ambient_requested_kj"]), 0.0, "ambient disabled")


func _test_equilibrium_bound() -> void:
	var context: Dictionary = _context()
	context["wall_absorption_rate_per_s"] = 1000.0
	var preview: Dictionary = _make_thermal().preview_phase3_canonical_wall_ambient_flux(
		_input(10.0, 5.0, 800.0, 0.0), _wall(0.0), context, 1.0
	)
	var upper_q: float = float(preview["upper_wall_requested_kj"])
	var lower_q: float = float(preview["lower_wall_requested_kj"])
	var wall_after_c: float = 20.0 + (upper_q + lower_q) / 100.0
	var equilibrium_c: float = float(preview["equilibrium_temp_c"])
	_assert_true(wall_after_c <= equilibrium_c + 1.0e-8, "wall no crossing")
	_assert_true(20.0 + (800.0 - upper_q) / 10.0 >= equilibrium_c - 1.0e-8, "upper no crossing")


func _test_many_steps_conserve_gas_wall_energy() -> void:
	var thermal = _make_thermal()
	var upper_kj: float = 800.0
	var lower_kj: float = 0.0
	var wall_kj: float = 0.0
	var initial_total_kj: float = upper_kj + lower_kj + wall_kj
	for _step in range(500):
		var preview: Dictionary = thermal.preview_phase3_canonical_wall_ambient_flux(
			_input(10.0, 5.0, upper_kj, lower_kj), _wall(wall_kj), _context(), 0.1
		)
		var upper_wall_kj: float = float(preview["upper_wall_requested_kj"])
		var lower_wall_kj: float = float(preview["lower_wall_requested_kj"])
		upper_kj -= upper_wall_kj
		lower_kj -= lower_wall_kj
		wall_kj += upper_wall_kj + lower_wall_kj
		_assert_true(upper_kj >= -1.0e-8 and lower_kj >= -1.0e-8, "gas non-negative")
		_assert_true(wall_kj >= -1.0e-8, "wall non-negative")
	_assert_close(upper_kj + lower_kj + wall_kj, initial_total_kj, "many-step closure")


func _test_upper_and_lower_exchange_together() -> void:
	var preview: Dictionary = _preview(800.0, 0.0, 1000.0, 1.0)
	_assert_true(float(preview["upper_wall_requested_kj"]) > 0.0, "upper absorbs")
	_assert_true(float(preview["lower_wall_requested_kj"]) < 0.0, "wall emits lower")


func _test_atomic_apply_and_duplicate_rejection() -> void:
	var pair: Dictionary = _building_room()
	var building = pair["building"]
	var room = pair["room"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var preview: Dictionary = _make_thermal().preview_phase3_canonical_wall_ambient_flux(
		system.get_canonical_thermodynamic_input(room, 20.0), _wall(0.0), _context(), 1.0
	)
	_assert_true(system.queue_canonical_wall_ambient_transfer(0, preview, {}, "1"), "first wall bundle")
	_assert_true(not system.queue_canonical_wall_ambient_transfer(0, preview, {}, "1"), "duplicate rejected")
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results()["0"]
	var gas_after_kj: float = float(result["phase3_shadow_upper_energy_kj"]) \
			+ float(result["phase3_shadow_lower_energy_kj"])
	var wall_after_kj: float = float(result["phase3_shadow_wall_energy_post_kj"])
	_assert_close(gas_after_kj + wall_after_kj, 900.0, "atomic gas wall closure")
	_assert_close(float(result["phase3_shadow_wall_boundary_residual_kj"]), 0.0, "boundary residual")
	_assert_close(float(result["phase3_shadow_atomic_duplicate_bundle_count"]), 1.0, "duplicate count")
	building.free()


func _test_prior_loss_limits_atomic_acceptance() -> void:
	var pair: Dictionary = _building_room()
	var building = pair["building"]
	var room = pair["room"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	var context: Dictionary = _context()
	context["wall_absorption_rate_per_s"] = 1000.0
	var preview: Dictionary = _make_thermal().preview_phase3_canonical_wall_ambient_flux(
		system.get_canonical_thermodynamic_input(room, 20.0), _wall(0.0), context, 1.0
	)
	system.add_request(system.make_request(
		"prior_upper_loss", "test_prior_upper_loss", 0, -1,
		"upper", "upper", 0.0, 790.0, 0.0, {}
	))
	_assert_true(system.queue_canonical_wall_ambient_transfer(0, preview, {}, "2"), "limited wall bundle")
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results()["0"]
	_assert_true(float(result["phase3_shadow_wall_accepted_fraction"]) < 1.0, "limited fraction")
	_assert_true(float(result["phase3_shadow_upper_energy_kj"]) >= -1.0e-9, "upper non-negative")
	_assert_close(float(result["phase3_shadow_wall_boundary_residual_kj"]), 0.0, "limited closure")
	building.free()


func _preview(upper_kj: float, lower_kj: float, wall_kj: float, dt: float) -> Dictionary:
	return _make_thermal().preview_phase3_canonical_wall_ambient_flux(
		_input(10.0, 5.0, upper_kj, lower_kj), _wall(wall_kj), _context(), dt
	)


func _make_thermal():
	return ThermalSystemScript.new()


func _input(upper_mass: float, lower_mass: float, upper_kj: float, lower_kj: float) -> Dictionary:
	return {
		"valid": true,
		"reference_temp_c": 20.0,
		"upper_gas_kg": upper_mass,
		"lower_gas_kg": lower_mass,
		"upper_energy_kj": upper_kj,
		"lower_energy_kj": lower_kj,
		"temp_upper_c": 20.0 + upper_kj / maxf(upper_mass, 1.0e-12),
		"temp_lower_c": 20.0 + lower_kj / maxf(lower_mass, 1.0e-12),
		"interface_m": 1.2,
	}


func _wall(energy_kj: float) -> Dictionary:
	return {"wall_energy_kj": energy_kj, "reference_temp_c": 20.0}


func _context() -> Dictionary:
	return {
		"valid": true,
		"width_m": 4.0,
		"length_m": 5.0,
		"height_m": 2.4,
		"floor_area_m2": 20.0,
		"wall_area_m2": 40.0,
		"wall_capacity_kj_k": 100.0,
		"wall_conductance_kw_k": 0.0,
		"material_wall_flag": 0.0,
		"wall_absorption_rate_per_s": 0.02,
		"wall_core_decay_per_s": 0.0,
		"upper_ambient_loss_rate_per_s": 0.0,
		"lower_ambient_decay_rate_per_s": 0.0,
		"lower_fresh_air_cooling_rate_per_s": 0.0,
		"outside_open_factor": 0.0,
		"outside_ambient_multiplier": 0.0,
		"outside_wall_multiplier": 0.0,
		"radiative_enabled": false,
		"radiative_start_c": 80.0,
		"radiative_emissivity": 0.9,
		"radiative_area_factor": 1.0,
		"radiative_max_fraction": 0.45,
		"max_upper_temp_c": 900.0,
	}


func _building_room() -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 5.0
	room.upper_energy_kj = 800.0
	room.lower_energy_kj = 100.0
	building.rooms = {0: room}
	return {"building": building, "room": room}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		quit(1)


func _assert_close(actual: float, expected: float, label: String, tolerance: float = 1.0e-8) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %.12g got %.12g" % [label, expected, actual])
		quit(1)
