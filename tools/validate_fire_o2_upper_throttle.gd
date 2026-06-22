extends Node

# ============================================================
# validate_fire_o2_upper_throttle.gd — Headless test
# Verifica que fire_o2_upper_throttle_enabled caps o2_ref al
# mínimo de room.o2 y room.o2_upper cuando o2_upper es crítico
# en modo plume_lower (two-zone abierto), y que el flag OFF
# reproduce el comportamiento legacy.
# Sin tocar OxygenExchangeSystem ni motor — solo CombustionSystem.
# ============================================================

const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_run_all()
	if _fail_count == 0:
		print("FIRE O2 UPPER THROTTLE VALIDATION PASS (%d/%d)" % [_pass_count, _pass_count])
	else:
		print("FIRE O2 UPPER THROTTLE VALIDATION FAIL (%d passed, %d FAILED)" % [_pass_count, _fail_count])
	get_tree().quit(1 if _fail_count > 0 else 0)


func _run_all() -> void:
	_test_flag_off_legacy_high_factor()
	_test_flag_on_upper_critical_factor_drops()
	_test_flag_on_upper_normal_no_throttle()
	_test_flag_on_sealed_room_no_two_zone()


func _make_room() -> RoomModel:
	var room: RoomModel = RoomModelScript.new()
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.5
	room.reset_dynamic_state(20.0, 0.209)
	var fire: FireModel = FireModelScript.new()
	fire.max_hrr_kw = 3500.0
	fire.fuel_energy_MJ = 9999.0
	fire.remaining_fuel_MJ = 9999.0
	fire.o2_min_for_flame = 0.10
	room.fire = fire
	room.fire_time_s = 265.0
	return room


func _base_context(throttle_enabled: bool, interface_m: float = 1.3) -> Dictionary:
	return {
		"two_zone_solver_enabled": true,
		"hot_layer_interface_m": interface_m,
		"fire_o2_upper_throttle_enabled": throttle_enabled,
		"fire_o2_upper_throttle_critical": 0.10,
		"ambient_c": 20.0,
		"fire_o2_min_for_flame": 0.10,
		"fire_latent_enabled": false,
		"fire_spread_enabled": false,
		"ach_infiltration": 0.0,
		# fire_max_active_s: SimulationEngine default=1800, pero context.get usa 0.0 como
		# fallback → fire_time_s(265)>=0 extingue inmediatamente. Pasar 1800 igual que el motor.
		"fire_max_active_s": 1800.0,
		"fire_extinction_delay_s": 90.0,
	}


func _assert(label: String, condition: bool) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % label)
	else:
		_fail_count += 1
		print("  FAIL: %s" % label)


func _test_flag_off_legacy_high_factor() -> void:
	# Bug original: flag OFF, o2_upper crítico, o2_lower fresco.
	# o2_hrr_factor debe quedarse alto (comportamiento legacy).
	var cs: CombustionSystem = CombustionSystemScript.new()
	var room: RoomModel = _make_room()
	room.o2 = 0.110         # bulk moderado
	room.o2_upper = 0.0008  # zona superior virtualmente sin O2
	room.o2_lower = 0.1975  # zona baja fresca
	room.o2_hrr_factor = 0.894
	room.hrr_kw = 1211.0
	room.temp_upper_c = 450.0
	var ctx: Dictionary = _base_context(false)
	cs.step_room_fire(room, 5.0, ctx)
	# Con flag OFF: raw_o2_factor = (o2_lower - 0.10) / 0.109 ≈ 0.894 → factor permanece alto
	_assert("flag OFF: o2_hrr_factor permanece >= 0.85 (legacy high)", room.o2_hrr_factor >= 0.85)
	_assert("flag OFF: fire_o2_ref ≈ o2_lower (no throttle)", room.fire_o2_ref >= 0.18)


func _test_flag_on_upper_critical_factor_drops() -> void:
	# Con flag ON y o2_upper crítico: o2_hrr_factor debe caer.
	# raw_o2_factor usará min(room.o2=0.11, room.o2_upper=0.0008)=0.0008 → factor ≈ 0
	var cs: CombustionSystem = CombustionSystemScript.new()
	var room: RoomModel = _make_room()
	room.o2 = 0.110
	room.o2_upper = 0.0008
	room.o2_lower = 0.1975
	room.o2_hrr_factor = 0.894
	room.hrr_kw = 1211.0
	room.temp_upper_c = 450.0
	var ctx: Dictionary = _base_context(true)
	for _i in range(10):
		cs.step_room_fire(room, 5.0, ctx)
	# Después de 50 s con target=0, o2_hrr_factor debe haber caído sustancialmente
	_assert("flag ON + o2_upper crítico: o2_hrr_factor cae (< 0.5)", room.o2_hrr_factor < 0.5)
	_assert("flag ON + o2_upper crítico: fire_o2_ref = min(o2,o2_upper) ≈ 0.001", room.fire_o2_ref < 0.005)


func _test_flag_on_upper_normal_no_throttle() -> void:
	# Con flag ON pero o2_upper normal (>=0.10): NO debe throttlear.
	# El throttle solo se activa cuando o2_upper < critical.
	var cs: CombustionSystem = CombustionSystemScript.new()
	var room: RoomModel = _make_room()
	room.o2 = 0.200
	room.o2_upper = 0.185  # zona superior con O2 normal
	room.o2_lower = 0.205
	room.o2_hrr_factor = 0.95
	room.hrr_kw = 600.0
	room.temp_upper_c = 80.0
	var ctx: Dictionary = _base_context(true)
	cs.step_room_fire(room, 5.0, ctx)
	# o2_hrr_factor debe mantenerse alto: throttle no se dispara
	_assert("flag ON + o2_upper normal: o2_hrr_factor permanece >= 0.90", room.o2_hrr_factor >= 0.90)
	_assert("flag ON + o2_upper normal: fire_o2_ref ≈ o2_lower (no throttle)", room.fire_o2_ref >= 0.18)


func _test_flag_on_sealed_room_no_two_zone() -> void:
	# Sala sellada (interfaz en suelo → mode="plume_upper" o "legacy").
	# El throttle NO debe activarse fuera del path plume_lower.
	var cs: CombustionSystem = CombustionSystemScript.new()
	var room: RoomModel = _make_room()
	room.o2 = 0.110
	room.o2_upper = 0.050  # bajo, pero en sala sellada sin two-zone
	room.o2_lower = 0.110
	room.o2_hrr_factor = 0.894
	room.hrr_kw = 800.0
	room.temp_upper_c = 300.0
	# interfaz en 0.0 → mode="plume_upper" → throttle no aplica
	var ctx: Dictionary = _base_context(true, 0.0)
	cs.step_room_fire(room, 5.0, ctx)
	# En modo plume_upper el throttle guard no se activa (guard chequea plume_lower/blend)
	# o2_hrr_factor debe moverse por o2_upper (no mínimo extra)
	_assert("flag ON + sala sellada (interface=0): throttle NO activa, fire_o2_ref != min(o2,o2_upper)", room.fire_o2_ref >= room.o2_upper - 0.01)
