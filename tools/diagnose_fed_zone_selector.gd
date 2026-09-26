extends SceneTree
## Diagnostico G3: concentraciones impuestas en dos zonas, sin transporte ni fuego.
## No es un guardarrail de la politica actual: expone la diferencia entre la
## dosis de CO que calcula FED y la dosis de las concentraciones zonales.

const ThermalSystemScript := preload("res://sim/core/ThermalSystem.gd")
const ROOM_HEIGHT_M: float = 2.4
const INTERFACE_M: float = 1.6
const LOWER_CO_PPM: float = 100.0
const UPPER_CO_PPM: float = 1000.0
const DT_S: float = 1.0


func _initialize() -> void:
	var room := RoomModel.new()
	room.id = 0
	room.name = "G3 imposed concentrations"
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = ROOM_HEIGHT_M
	room.thermal_layer_m = INTERFACE_M
	room.layer_150c_m = ROOM_HEIGHT_M
	room.temp_upper_c = 80.0
	room.temp_lower_c = 20.0

	var thermal = ThermalSystemScript.new()
	thermal.two_zone_solver_enabled = true
	thermal.fed_heat_enabled = false
	thermal.fed_hypoxia_enabled = false
	var upper_mass_kg: float = room.floor_area_m2() * (ROOM_HEIGHT_M - INTERFACE_M) * (
		thermal.gas_density_kg_m3(room.temp_upper_c))
	var lower_mass_kg: float = room.floor_area_m2() * INTERFACE_M * (
		thermal.gas_density_kg_m3(room.temp_lower_c))
	room.upper_gas_kg = upper_mass_kg
	room.lower_gas_kg = lower_mass_kg
	room.co_upper_kg = UPPER_CO_PPM * upper_mass_kg * 28.0 / 29.0e6
	room.co_kg = room.co_upper_kg + LOWER_CO_PPM * lower_mass_kg * 28.0 / 29.0e6

	var mean_ppm: float = thermal.compute_co_ppm(room)
	var exported_lower_ppm: float = thermal.compute_co_lower_ppm(room)
	var exported_upper_ppm: float = thermal.compute_co_upper_ppm(room)
	print("G3 imposed: lower=%.6f upper=%.6f mean=%.6f exported_lower=%.6f exported_upper=%.6f" % [
		LOWER_CO_PPM, UPPER_CO_PPM, mean_ppm, exported_lower_ppm, exported_upper_ppm])
	if absf(exported_upper_ppm - UPPER_CO_PPM) > 1.0e-6:
		push_error("Imposed upper concentration was not reproduced")
		quit(1)
		return

	for height_m in [0.9, 1.5, 1.8]:
		var actual_delta: float = thermal.compute_fed_delta_for_height(room, DT_S, height_m)
		var expected_lower_delta: float = 3.317e-5 * pow(LOWER_CO_PPM, 1.036) * DT_S / 60.0
		var expected_upper_delta: float = 3.317e-5 * pow(UPPER_CO_PPM, 1.036) * DT_S / 60.0
		print("G3 height=%.1f actual_delta=%.10f lower_formula=%.10f upper_formula=%.10f" % [
			height_m, actual_delta, expected_lower_delta, expected_upper_delta])

	room.fed = 0.0
	room.fed_co = 0.0
	thermal.fed_upper_layer_threshold_m = 0.9
	thermal.step_fed(room, DT_S)
	var legacy_fed_co: float = room.fed_co
	print("G3 OFF room_at_0.9m fed=%.10f fed_co=%.10f" % [room.fed, room.fed_co])
	thermal.fed_co_zonal_enabled = true
	var mass_lower_ppm: float = thermal.compute_co_lower_ppm_mass(room)
	var lower_expected_delta: float = 3.317e-5 * pow(LOWER_CO_PPM, 1.036) * DT_S / 60.0
	var upper_expected_delta: float = 3.317e-5 * pow(UPPER_CO_PPM, 1.036) * DT_S / 60.0
	if absf(mass_lower_ppm - LOWER_CO_PPM) > 1.0e-6:
		push_error("ON lower-zone inventory did not yield imposed CO ppm")
		quit(1)
		return
	for height_m in [0.9, 1.5, 1.8]:
		var actual_delta: float = thermal.compute_fed_delta_for_height(room, DT_S, height_m)
		var expected_delta: float = upper_expected_delta if height_m > INTERFACE_M else lower_expected_delta
		print("G3 ON height=%.1f actual_delta=%.10f expected_delta=%.10f" % [
			height_m, actual_delta, expected_delta])
		if absf(actual_delta - expected_delta) > 1.0e-9:
			push_error("ON FED did not use imposed CO concentration at %.1f m" % height_m)
			quit(1)
			return
	room.fed = 0.0
	room.fed_co = 0.0
	thermal.step_fed(room, DT_S)
	print("G3 ON room_at_0.9m fed=%.10f fed_co=%.10f" % [room.fed, room.fed_co])
	if absf(room.fed_co - lower_expected_delta) > 1.0e-9 or legacy_fed_co <= room.fed_co:
		push_error("ON room FED did not use the lower-zone CO inventory")
		quit(1)
		return
	room.upper_gas_kg = 0.0
	if absf(thermal.compute_co_lower_ppm_mass(room) - thermal.compute_co_ppm(room)) > 1.0e-9:
		push_error("Collapsed upper layer did not fall back to the room mean")
		quit(1)
		return
	print("G3 FED CO ZONAL VALIDATION PASS")
	quit(0)
