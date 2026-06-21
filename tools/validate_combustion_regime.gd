extends Node

# ============================================================
# validate_combustion_regime.gd — Headless test
# Verifica que CombustionRegimeClassifier produce los regímenes
# correctos para estados canónicos de RoomModel.
# Sin cambios de física: solo instancia RoomModel, configura
# campos existentes y afirma el string de régimen devuelto.
# ============================================================

const CombustionRegimeClassifierScript = preload("res://sim/fire/CombustionRegimeClassifier.gd")
const FireModelScript = preload("res://sim/fire/FireModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_run_all()
	if _fail_count == 0:
		print("COMBUSTION REGIME VALIDATION PASS (%d/%d)" % [_pass_count, _pass_count])
	else:
		print("COMBUSTION REGIME VALIDATION FAIL (%d passed, %d FAILED)" % [_pass_count, _fail_count])
	get_tree().quit(1 if _fail_count > 0 else 0)


func _run_all() -> void:
	_test_no_fire()
	_test_backdraft_event()
	_test_backdraft_risk()
	_test_fully_developed()
	_test_ventilation_induced_growth()
	_test_ilv_latent()
	_test_ventilation_controlled_burning()
	_test_ventilation_stressed()
	_test_fuel_controlled()


func _make_room(with_fire: bool = true) -> RoomModel:
	var room: RoomModel = RoomModelScript.new()
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.5
	room.reset_dynamic_state(20.0, 0.209)
	if with_fire:
		var fire: FireModel = FireModelScript.new()
		fire.max_hrr_kw = 1000.0
		fire.fuel_energy_MJ = 5000.0
		fire.remaining_fuel_MJ = 5000.0
		room.fire = fire
		room.hrr_kw = 100.0
		room.fire_time_s = 60.0
		room.o2_hrr_factor = 0.90
		room.temp_upper_c = 80.0
	return room


func _assert_regime(label: String, room: RoomModel, expected: String) -> void:
	var got: String = CombustionRegimeClassifierScript.classify(room)
	if got == expected:
		_pass_count += 1
		print("  PASS [%s]: %s" % [expected, label])
	else:
		_fail_count += 1
		print("  FAIL [%s]: expected=%s got=%s" % [label, expected, got])


func _test_no_fire() -> void:
	var room: RoomModel = _make_room(false)
	_assert_regime("sin fuego (fire=null)", room, "EXTINGUISHED")


func _test_backdraft_event() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = true
	room.unburned_gas_vol_frac = 0.05
	room.o2 = 0.10
	room.temp_upper_c = 250.0
	_assert_regime("backdraft activo", room, "BACKDRAFT_EVENT")


func _test_backdraft_risk() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.04
	room.o2 = 0.11
	room.o2_hrr_factor = 0.15
	room.temp_upper_c = 210.0
	room.retained_unburned_MJ = 12.0
	room.fire_smoldering = false
	room.ventilation_response_factor = 0.1
	_assert_regime("riesgo backdraft", room, "BACKDRAFT_RISK")


func _test_fully_developed() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.0
	room.hrr_kw = 900.0
	room.temp_upper_c = 650.0
	room.o2_hrr_factor = 0.80
	room.ventilation_response_factor = 0.2
	room.fire_smoldering = false
	_assert_regime("fully developed", room, "FULLY_DEVELOPED")


func _test_ventilation_induced_growth() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.0
	room.hrr_kw = 400.0
	room.temp_upper_c = 300.0
	room.o2_hrr_factor = 0.55
	room.ventilation_response_factor = 0.65
	room.retained_unburned_MJ = 2.5
	room.fire_smoldering = false
	_assert_regime("crecimiento inducido por ventilación", room, "VENTILATION_INDUCED_GROWTH")


func _test_ilv_latent() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.0
	room.hrr_kw = 3.0
	room.temp_upper_c = 120.0
	room.o2_hrr_factor = 0.05
	room.ventilation_response_factor = 0.0
	room.retained_unburned_MJ = 0.1
	room.fire_latent_active = true  # Fase 2: señal upstream sin gate de HRR
	_assert_regime("ILV latente / fire_latent_active", room, "ILV_LATENT")


func _test_ventilation_controlled_burning() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.0
	room.hrr_kw = 80.0
	room.temp_upper_c = 200.0
	room.o2_hrr_factor = 0.25
	room.ventilation_response_factor = 0.1
	room.retained_unburned_MJ = 0.0
	room.fire_smoldering = false
	_assert_regime("combustión controlada por ventilación", room, "VENTILATION_CONTROLLED_BURNING")


func _test_ventilation_stressed() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.0
	room.hrr_kw = 280.0
	room.temp_upper_c = 180.0
	room.o2_hrr_factor = 0.55
	room.ventilation_response_factor = 0.08
	room.retained_unburned_MJ = 0.0
	room.fire_smoldering = false
	_assert_regime("estrés ventilatorio", room, "VENTILATION_STRESSED")


func _test_fuel_controlled() -> void:
	var room: RoomModel = _make_room(true)
	room.backdraft_active = false
	room.unburned_gas_vol_frac = 0.0
	room.hrr_kw = 500.0
	room.temp_upper_c = 250.0
	room.o2_hrr_factor = 0.92
	room.ventilation_response_factor = 0.0
	room.retained_unburned_MJ = 0.0
	room.fire_smoldering = false
	_assert_regime("controlado por combustible", room, "FUEL_CONTROLLED")
