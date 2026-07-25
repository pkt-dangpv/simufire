extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

var _failed: bool = false


func _init() -> void:
	_test_complete_heskestad_contract()
	_test_lower_inventory_cap()
	_test_transaction_getter_is_read_only()
	_test_o2_decision_is_not_applied_twice()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33T_COUPLED_PLUME_PASS")
	quit(0)


func _test_complete_heskestad_contract() -> void:
	var room = _make_room()
	var thermal = ThermalSystemScript.new()
	var canonical_input: Dictionary = _canonical_input(38.0, 380.0, 1.25)
	var transaction: Dictionary = {
		"accepted_hrr_kw": 300.0,
		"effective_chi_rad": 0.35,
	}
	var flux: Dictionary = thermal.preview_phase3_coupled_plume_flux(
		room, canonical_input, transaction, 1.0
	)
	var qc_kw: float = 300.0 * 0.65
	var z0_m: float = -1.02 * thermal.plume_fire_diameter_m \
			+ 0.083 * pow(300.0, 0.4)
	var z_eff_m: float = maxf(0.1, 1.25 - z0_m)
	var expected_height_kg: float = 0.071 * pow(qc_kw, 1.0 / 3.0) \
			* pow(z_eff_m, 5.0 / 3.0)
	var expected_source_kg: float = 0.071 * 0.026 * qc_kw
	_assert_close(float(flux["coupled_qc_kw"]), qc_kw, "accepted Qc")
	_assert_close(float(flux["virtual_origin_m"]), z0_m, "virtual origin")
	_assert_close(float(flux["z_eff_m"]), z_eff_m, "effective height")
	_assert_close(float(flux["height_term_mass_kg"]), expected_height_kg, "height term")
	_assert_close(float(flux["source_term_mass_kg"]), expected_source_kg, "source term")
	_assert_close(
		float(flux["gas_mass_kg"]),
		expected_height_kg + expected_source_kg,
		"complete plume"
	)
	_assert_close(
		float(flux["sensible_enthalpy_kj"]),
		380.0 * float(flux["gas_mass_kg"]) / 38.0,
		"proportional enthalpy"
	)
	_assert_close(
		float(flux["o2_kg"]),
		float(flux["gas_mass_kg"]) * 0.209,
		"proportional O2"
	)
	_assert_true(bool(flux["o2_decision_applied"]), "O2 marker")


func _test_lower_inventory_cap() -> void:
	var room = _make_room()
	var thermal = ThermalSystemScript.new()
	var flux: Dictionary = thermal.preview_phase3_coupled_plume_flux(
		room,
		_canonical_input(0.05, 5.0, 0.1),
		{"accepted_hrr_kw": 1280.0, "effective_chi_rad": 0.0},
		10.0
	)
	_assert_close(float(flux["gas_mass_kg"]), 0.05, "lower mass cap")
	_assert_close(float(flux["sensible_enthalpy_kj"]), 5.0, "lower energy cap")
	_assert_close(float(flux["o2_kg"]), 0.05 * 0.209, "lower O2 cap")
	_assert_close(
		float(flux["height_term_mass_kg"]) + float(flux["source_term_mass_kg"]),
		0.05,
		"capped term split"
	)


func _test_transaction_getter_is_read_only() -> void:
	var setup: Dictionary = _make_ledger()
	var ledger = setup["ledger"]
	var transaction: Dictionary = _transaction()
	_assert_true(ledger.stage_canonical_combustion_transaction(transaction), "stage getter")
	var first: Dictionary = ledger.get_canonical_combustion_transaction(0)
	first["accepted_hrr_kw"] = -1.0
	var second: Dictionary = ledger.get_canonical_combustion_transaction(0)
	_assert_close(float(second["accepted_hrr_kw"]), 100.0, "getter duplicate")
	_free_ledger(setup)


func _test_o2_decision_is_not_applied_twice() -> void:
	var coupled_setup: Dictionary = _make_ledger()
	var coupled = coupled_setup["ledger"]
	_assert_true(coupled.stage_canonical_combustion_transaction(_transaction()), "coupled stage")
	_assert_true(coupled.finalize_canonical_combustion_bundle(
		0,
		{},
		{
			"gas_mass_kg": 0.4,
			"sensible_enthalpy_kj": 4.0,
			"o2_decision_applied": true,
		},
		"coupled"
	), "coupled finalize")
	coupled.finalize_step(coupled_setup["building"], 20.0)
	var coupled_result: Dictionary = coupled.get_results()["0"]
	_assert_close(
		float(coupled_result["phase3_shadow_combustion_accepted_plume_mass_kg"]),
		0.4,
		"coupled plume not rescaled"
	)
	_free_ledger(coupled_setup)

	var legacy_setup: Dictionary = _make_ledger()
	var legacy = legacy_setup["ledger"]
	_assert_true(legacy.stage_canonical_combustion_transaction(_transaction()), "legacy stage")
	_assert_true(legacy.finalize_canonical_combustion_bundle(
		0,
		{},
		{"gas_mass_kg": 0.4, "sensible_enthalpy_kj": 4.0},
		"legacy"
	), "legacy finalize")
	legacy.finalize_step(legacy_setup["building"], 20.0)
	var legacy_result: Dictionary = legacy.get_results()["0"]
	_assert_close(
		float(legacy_result["phase3_shadow_combustion_accepted_plume_mass_kg"]),
		0.2,
		"legacy plume keeps scale"
	)
	_free_ledger(legacy_setup)


func _make_room():
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 38.0
	room.upper_energy_kj = 900.0
	room.lower_energy_kj = 380.0
	room.o2_upper = 0.16
	room.o2_lower = 0.209
	room.o2 = 0.16
	room.temp_upper_c = 120.0
	return room


func _canonical_input(lower_mass_kg: float, lower_energy_kj: float, interface_m: float) -> Dictionary:
	return {
		"valid": true,
		"lower_gas_kg": lower_mass_kg,
		"lower_energy_kj": lower_energy_kj,
		"lower_o2_fraction": 0.209,
		"interface_m": interface_m,
	}


func _make_ledger() -> Dictionary:
	var building = BuildingModelScript.new()
	var room = _make_room()
	building.rooms = {0: room}
	var ledger = Phase3ZoneMassSystemScript.new()
	ledger.begin_step(building, true)
	return {"building": building, "ledger": ledger}


func _transaction() -> Dictionary:
	return {
		"room_id": 0,
		"decision_fraction": 0.125,
		"plume_scale": 0.5,
		"heat_scale": 0.125,
		"accepted_hrr_kw": 100.0,
		"effective_chi_rad": 0.35,
		"accepted_o2_kg": 0.0,
		"o2_source_zone": "upper",
		"accepted_species_kg": {},
		"requested_total_fire_energy_kj": 0.0,
		"accepted_total_fire_energy_kj": 0.0,
	}


func _free_ledger(setup: Dictionary) -> void:
	var building = setup.get("building")
	if building != null:
		building.free()


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label)


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-8 * maxf(1.0, absf(expected)):
		_fail("%s expected %s got %s" % [label, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
