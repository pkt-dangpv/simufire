extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


func _init() -> void:
	_test_persistent_o2_survives_legacy_mutation()
	_test_default_path_reseeds_from_legacy()
	_test_reset_clears_persistent_state()
	_test_degenerate_zone_collapse_conserves_inventory()
	print("PHASE3_F32B_PERSISTENT_SHADOW_PASS")
	quit(0)


func _test_persistent_o2_survives_legacy_mutation() -> void:
	var setup: Dictionary = _make_building()
	var building = setup["building"]
	var room = setup["room"]
	var system = Phase3ZoneMassSystemScript.new()

	system.begin_step(building, true)
	system.record_combustion_o2_probe(building)
	system.add_request(system.make_request(
		"o2-step-1", "combustion_o2_upper_sink", 0, -1,
		"upper", "upper", 0.0, 0.0, 0.5
	))
	system.finalize_step(building, 20.0)
	var first: Dictionary = system.get_results().get("0", {})
	_assert_close(_value(first, "phase3_shadow_persistent_step_index"), 1.0, "step 1")
	_assert_close(
		_value(first, "phase3_shadow_persistent_seeded_from_legacy_flag"), 1.0, "seeded"
	)
	_assert_close(
		_value(first, "phase3_shadow_persistent_post_upper_o2_fraction"), 0.15, "step 1 O2"
	)

	room.o2_upper = 0.20
	system.begin_step(building, true)
	system.record_combustion_o2_probe(building)
	system.finalize_step(building, 20.0)
	var second: Dictionary = system.get_results().get("0", {})
	_assert_close(_value(second, "phase3_shadow_persistent_step_index"), 2.0, "step 2")
	_assert_close(
		_value(second, "phase3_shadow_persistent_seeded_from_legacy_flag"), 0.0, "not reseeded"
	)
	_assert_close(
		_value(second, "phase3_shadow_persistent_pre_upper_o2_fraction"), 0.15, "persistent pre O2"
	)
	_assert_close(
		_value(second, "phase3_shadow_persistent_combustion_o2_ref"), 0.15, "canonical fire O2"
	)
	_assert_close(
		_value(second, "phase3_shadow_persistent_legacy_combustion_o2_ref"), 0.20, "legacy fire O2"
	)
	_assert_close(
		_value(second, "phase3_shadow_persistent_combustion_would_limit_flag"), 1.0, "would limit"
	)
	_assert_continuity(second, "persistent")
	_free_setup(setup)


func _test_default_path_reseeds_from_legacy() -> void:
	var setup: Dictionary = _make_building()
	var building = setup["building"]
	var room = setup["room"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, false)
	system.add_request(system.make_request(
		"legacy-o2-step-1", "combustion_o2_upper_sink", 0, -1,
		"upper", "upper", 0.0, 0.0, 0.5
	))
	system.finalize_step(building, 20.0)
	room.o2_upper = 0.20
	system.begin_step(building, false)
	system.finalize_step(building, 20.0)
	var second: Dictionary = system.get_results().get("0", {})
	_assert_close(_value(second, "phase3_shadow_upper_gas_kg"), 10.0, "legacy mass")
	_assert_close(_value(second, "phase3_shadow_persistent_step_index"), 0.0, "no persistent step")
	_free_setup(setup)


func _test_reset_clears_persistent_state() -> void:
	var setup: Dictionary = _make_building()
	var building = setup["building"]
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.add_request(system.make_request(
		"reset-o2-step-1", "combustion_o2_upper_sink", 0, -1,
		"upper", "upper", 0.0, 0.0, 0.5
	))
	system.finalize_step(building, 20.0)
	system.reset()
	system.begin_step(building, true)
	system.record_combustion_o2_probe(building)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results().get("0", {})
	_assert_close(_value(result, "phase3_shadow_persistent_step_index"), 1.0, "reset step")
	_assert_close(
		_value(result, "phase3_shadow_persistent_seeded_from_legacy_flag"), 1.0, "reset seed"
	)
	_assert_close(
		_value(result, "phase3_shadow_persistent_pre_upper_o2_fraction"), 0.20, "reset O2"
	)
	_free_setup(setup)


func _test_degenerate_zone_collapse_conserves_inventory() -> void:
	var setup: Dictionary = _make_building()
	var building = setup["building"]
	var room = setup["room"]
	room.lower_gas_kg = 0.0
	room.lower_energy_kj = 100.0
	room.o2_lower = 0.0
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	system.finalize_step(building, 20.0)
	var result: Dictionary = system.get_results().get("0", {})
	_assert_close(
		_value(result, "phase3_shadow_persistent_zone_collapse_count"), 1.0, "collapse count"
	)
	_assert_close(_value(result, "phase3_shadow_upper_energy_kj"), 1000.0, "merged energy")
	_assert_close(_value(result, "phase3_shadow_lower_energy_kj"), 0.0, "empty lower energy")
	for field_name in [
		"phase3_shadow_persistent_zone_collapse_mass_residual_kg",
		"phase3_shadow_persistent_zone_collapse_energy_residual_kj",
		"phase3_shadow_persistent_zone_collapse_o2_residual_kg",
		"phase3_shadow_persistent_zone_collapse_species_residual_kg"
	]:
		_assert_close(_value(result, field_name), 0.0, "collapse " + field_name)
	_free_setup(setup)


func _make_building() -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 38.0
	room.upper_energy_kj = 900.0
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.20
	room.o2_lower = 0.209
	room.fire_o2_mode_used = "upper"
	room.fire_o2_ref = 0.20
	building.rooms = {0: room}
	return {"building": building, "room": room}


func _assert_continuity(result: Dictionary, label: String) -> void:
	for field_name in [
		"phase3_shadow_persistent_continuity_mass_residual_kg",
		"phase3_shadow_persistent_continuity_energy_residual_kj",
		"phase3_shadow_persistent_continuity_o2_residual_kg",
		"phase3_shadow_persistent_continuity_species_residual_kg"
	]:
		_assert_close(_value(result, field_name), 0.0, label + " " + field_name)


func _value(result: Dictionary, field_name: String) -> float:
	return float(result.get(field_name, 0.0))


func _free_setup(setup: Dictionary) -> void:
	var building = setup.get("building")
	if building != null:
		building.free()


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-8 * maxf(1.0, absf(expected)):
		_fail("%s expected %.12g got %.12g" % [label, expected, actual])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
