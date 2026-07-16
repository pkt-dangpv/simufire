extends SceneTree

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")


func _init() -> void:
	var combustion = CombustionSystemScript.new()
	var room = _make_room(0.05)
	combustion.step_room_fire(room, 0.1, _base_context())

	_assert_zero(room.flame_hrr_target_kw, "flame target")
	_assert_zero(room.smolder_hrr_target_kw, "smolder target")
	_assert_zero(room.pool_release_hrr_target_kw, "pool target")
	_assert_zero(room.hrr_target_kw, "HRR target")
	_assert_zero(room.hrr_kw, "HRR")
	_assert_zero(room.burned_hrr_kw, "burned HRR")
	if not room.fire_o2_extinguished:
		_fail("fire_o2_extinguished was not set")

	var above_threshold = _make_room(0.101)
	combustion.step_room_fire(above_threshold, 0.1, _base_context())
	if above_threshold.fire_o2_extinguished:
		_fail("selected O2 above the threshold was hard-extinguished")

	var independent = _make_room(0.0)
	var independent_context = _base_context()
	independent_context["fire_o2_independent"] = true
	combustion.step_room_fire(independent, 0.1, independent_context)
	if independent.fire_o2_extinguished:
		_fail("fire_o2_independent mode was hard-extinguished")

	print("F31_ZERO_O2_EXTINCTION_RUNTIME_PASS")
	quit(0)


func _make_room(o2_upper: float):
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.temp_upper_c = 180.0
	room.temp_lower_c = 80.0
	room.o2 = 0.18
	room.o2_upper = o2_upper
	room.o2_lower = 0.20
	room.hrr_kw = 600.0
	room.hrr_target_kw = 600.0
	room.burned_hrr_kw = 600.0
	room.flame_hrr_target_kw = 600.0
	room.smolder_hrr_target_kw = 20.0
	room.pool_release_hrr_target_kw = 10.0

	var fire = FireModelScript.new()
	fire.o2_min_for_flame = 0.10
	fire.remaining_fuel_MJ = 1000.0
	fire.fuel_energy_MJ = 1000.0
	room.fire = fire
	return room


func _base_context() -> Dictionary:
	return {
		"ambient_c": 20.0,
		"fire_o2_mode": "upper",
		"fire_o2_full_hrr_open": 0.209,
		"fire_latent_enabled": true,
		"fire_latent_hold_upper_temp_c": 40.0,
		"fire_latent_hold_lower_temp_c": 40.0,
		"fire_latent_min_remaining_fuel_MJ": 25.0,
		"fire_latent_o2_viable_margin": 0.008,
		"fire_extinction_hrr_kw": 8.0,
		"fire_extinction_delay_s": 180.0,
		"fire_latent_extinction_delay_s": 180.0,
	}


func _assert_zero(actual: float, label: String) -> void:
	if absf(actual) > 1.0e-6:
		_fail("%s expected zero, got %.9f" % [label, actual])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
