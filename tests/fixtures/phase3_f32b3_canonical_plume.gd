extends SceneTree

const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")


var _failed: bool = false


func _init() -> void:
	_test_canonical_interface_controls_plume()
	_test_transfer_preserves_lower_specific_enthalpy()
	_test_empty_lower_zone_requests_nothing()
	# `quit()` only requests a shutdown, so execution continues. Return
	# explicitly or the PASS marker below would still be printed.
	if _failed:
		quit(1)
		return
	print("PHASE3_F32B3_CANONICAL_PLUME_PASS")
	quit(0)


func _test_canonical_interface_controls_plume() -> void:
	var thermal = _make_thermal()
	var room = _make_room()
	var shallow: Dictionary = _canonical_input(0.26, 5.0, 50.0)
	var legacy_like: Dictionary = _canonical_input(1.458, 5.0, 50.0)
	var shallow_flux: Dictionary = thermal.preview_phase3_canonical_plume_flux(
		room, shallow, 1.0 / 12.0
	)
	var legacy_flux: Dictionary = thermal.preview_phase3_canonical_plume_flux(
		room, legacy_like, 1.0 / 12.0
	)
	_assert_true(
		float(shallow_flux["gas_mass_kg"]) < float(legacy_flux["gas_mass_kg"]) * 0.2,
		"canonical shallow interface must reduce plume request"
	)


func _test_transfer_preserves_lower_specific_enthalpy() -> void:
	var thermal = _make_thermal()
	var room = _make_room()
	var flux: Dictionary = thermal.preview_phase3_canonical_plume_flux(
		room, _canonical_input(0.6, 10.0, 125.0), 1.0 / 12.0
	)
	var moved_mass_kg: float = float(flux["gas_mass_kg"])
	_assert_close(
		float(flux["sensible_enthalpy_kj"]),
		moved_mass_kg * 12.5,
		"specific enthalpy"
	)
	_assert_close(float(flux["o2_kg"]), moved_mass_kg * 0.205, "lower O2 payload")


func _test_empty_lower_zone_requests_nothing() -> void:
	var thermal = _make_thermal()
	var room = _make_room()
	var input: Dictionary = _canonical_input(0.0, 0.0, 0.0)
	var flux: Dictionary = thermal.preview_phase3_canonical_plume_flux(
		room, input, 1.0 / 12.0
	)
	_assert_close(float(flux["gas_mass_kg"]), 0.0, "empty lower mass")
	_assert_close(float(flux["sensible_enthalpy_kj"]), 0.0, "empty lower energy")


func _make_thermal():
	var thermal = ThermalSystemScript.new()
	thermal.plume_mccaffrey_qc_fraction = 0.3
	thermal.plume_fire_diameter_m = 3.5
	return thermal


func _make_room():
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.4
	room.hrr_kw = 335.0
	return room


func _canonical_input(
		interface_m: float,
		lower_mass_kg: float,
		lower_energy_kj: float
	) -> Dictionary:
	return {
		"valid": true,
		"interface_m": interface_m,
		"lower_gas_kg": lower_mass_kg,
		"lower_energy_kj": lower_energy_kj,
		"lower_o2_fraction": 0.205,
	}


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(
		actual: float,
		expected: float,
		label: String,
		tolerance: float = 1.0e-8
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %.12g got %.12g" % [label, expected, actual])
		_failed = true
