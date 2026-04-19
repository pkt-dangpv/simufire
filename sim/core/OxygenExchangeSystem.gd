extends RefCounted
class_name OxygenExchangeSystem

var o2_nominal: float = 0.209
var ach_infiltration: float = 0.5
var doorway_o2_exchange_coeff: float = 1.70
var doorway_o2_background_exchange_kg_s_m2: float = 0.06
var doorway_o2_background_max_fraction_per_step: float = 0.015
var doorway_o2_background_pressure_ref_pa: float = 1.5
var doorway_o2_background_min_factor: float = 0.30


func configure(settings: Dictionary) -> void:
	o2_nominal = float(settings.get("o2_nominal", o2_nominal))
	ach_infiltration = float(settings.get("ach_infiltration", ach_infiltration))
	doorway_o2_exchange_coeff = float(
		settings.get("doorway_o2_exchange_coeff", doorway_o2_exchange_coeff)
	)
	doorway_o2_background_exchange_kg_s_m2 = float(
		settings.get(
			"doorway_o2_background_exchange_kg_s_m2",
			doorway_o2_background_exchange_kg_s_m2
		)
	)
	doorway_o2_background_max_fraction_per_step = float(
		settings.get(
			"doorway_o2_background_max_fraction_per_step",
			doorway_o2_background_max_fraction_per_step
		)
	)
	doorway_o2_background_pressure_ref_pa = float(
		settings.get(
			"doorway_o2_background_pressure_ref_pa",
			doorway_o2_background_pressure_ref_pa
		)
	)
	doorway_o2_background_min_factor = float(
		settings.get(
			"doorway_o2_background_min_factor",
			doorway_o2_background_min_factor
		)
	)


func step(building: BuildingModel, dt: float, hooks: Dictionary) -> void:
	if building == null:
		return

	var effective_hot_layer_callable: Callable = hooks.get(
		"effective_hot_layer_height_callable",
		Callable()
	)
	var build_interior_flow_callable: Callable = hooks.get(
		"build_interior_opening_flow_state_callable",
		Callable()
	)
	var air_density_kg_m3: float = 1.2

	for room_id in building.get_rooms().keys():
		var room: RoomModel = building.get_room(room_id)
		if room == null:
			continue

		var air_mass_kg: float = _compute_room_air_mass_kg(room, air_density_kg_m3)
		var o2_mass_kg: float = air_mass_kg * room.o2

		if room.hrr_kw > 0.0:
			var consumption_rate: float = room.fire.o2_consumption_kg_per_MJ if room.fire != null else 0.076
			var consumed_kg: float = (room.hrr_kw / 1000.0) * consumption_rate * dt
			consumed_kg = minf(consumed_kg, o2_mass_kg * 0.05)
			o2_mass_kg = maxf(0.0, o2_mass_kg - consumed_kg)

		var ach_o2_delta_kg: float = room.volume_m3() * (ach_infiltration / 3600.0) * air_density_kg_m3 \
			* (building.outside_o2 - room.o2) * dt
		o2_mass_kg += ach_o2_delta_kg
		room.o2 = clampf(o2_mass_kg / air_mass_kg, 0.0, o2_nominal)

	var g_gravity: float = 9.8
	for op in building.get_openings():
		if op.open_fraction <= 0.0:
			continue

		var lintel_m: float = op.lintel_height_m()
		if op.a == BuildingModel.OUTSIDE_ID or op.b == BuildingModel.OUTSIDE_ID:
			_step_outside_opening_o2(
				building,
				dt,
				op,
				lintel_m,
				air_density_kg_m3,
				g_gravity,
				effective_hot_layer_callable
			)
			continue

		var room_a: RoomModel = building.get_room(op.a)
		var room_b: RoomModel = building.get_room(op.b)
		if room_a == null or room_b == null:
			continue

		_step_interior_opening_o2(
			dt,
			op,
			room_a,
			room_b,
			air_density_kg_m3,
			g_gravity,
			build_interior_flow_callable
		)


func _step_outside_opening_o2(
	building: BuildingModel,
	dt: float,
	op: OpeningModel,
	lintel_m: float,
	air_density_kg_m3: float,
	g_gravity: float,
	effective_hot_layer_callable: Callable
) -> void:
	var indoor_id: int = op.a if op.b == BuildingModel.OUTSIDE_ID else op.b
	var indoor: RoomModel = building.get_room(indoor_id)
	if indoor == null:
		return

	var effective_layer_m: float = _call_room_float(
		effective_hot_layer_callable,
		indoor,
		clampf(indoor.thermal_layer_m, 0.0, indoor.height_m)
	)
	var area_eff_m2: float = 0.0
	var h_drive_m: float = 0.0
	var t_in_k: float = building.outside_temp_c + 273.15

	if effective_layer_m <= lintel_m:
		h_drive_m = maxf(0.05, lintel_m - effective_layer_m)
		area_eff_m2 = op.width_m * minf(h_drive_m, op.height_m) * op.open_fraction
		t_in_k = indoor.temp_upper_c + 273.15
	else:
		h_drive_m = op.height_m
		area_eff_m2 = op.width_m * op.height_m * op.open_fraction
		t_in_k = indoor.temp_lower_c + 273.15

	if area_eff_m2 <= 0.0:
		return

	var t_out_k: float = building.outside_temp_c + 273.15
	var delta_t_k: float = maxf(0.0, t_in_k - t_out_k)
	if delta_t_k < 2.0:
		return

	var q_m3_s: float = 0.65 * 0.5 * area_eff_m2 * sqrt(g_gravity * h_drive_m * delta_t_k / t_in_k)
	var air_in_kg: float = q_m3_s * air_density_kg_m3 * dt
	var room_air_mass_kg: float = _compute_room_air_mass_kg(indoor, air_density_kg_m3)
	indoor.o2 = clampf(
		(indoor.o2 * room_air_mass_kg + building.outside_o2 * air_in_kg) / (room_air_mass_kg + air_in_kg),
		0.0,
		o2_nominal
	)


func _step_interior_opening_o2(
	dt: float,
	op: OpeningModel,
	room_a: RoomModel,
	room_b: RoomModel,
	air_density_kg_m3: float,
	g_gravity: float,
	build_interior_flow_callable: Callable
) -> void:
	var base_area_eff_m2: float = maxf(0.0, op.width_m * op.height_m * op.open_fraction)
	if base_area_eff_m2 > 0.0:
		var mass_a_base_kg: float = _compute_room_air_mass_kg(room_a, air_density_kg_m3)
		var mass_b_base_kg: float = _compute_room_air_mass_kg(room_b, air_density_kg_m3)
		var background_pressure_factor: float = maxf(
			doorway_o2_background_min_factor,
			clampf(
				maxf(room_a.overpressure_pa, room_b.overpressure_pa) / maxf(
					0.1,
					doorway_o2_background_pressure_ref_pa
				),
				0.0,
				1.0
			)
		)
		var base_exchange_kg: float = base_area_eff_m2 \
			* doorway_o2_background_exchange_kg_s_m2 \
			* background_pressure_factor \
			* dt
		var base_max_exchange_kg: float = minf(mass_a_base_kg, mass_b_base_kg) \
			* doorway_o2_background_max_fraction_per_step
		base_exchange_kg = minf(base_exchange_kg, base_max_exchange_kg)
		if base_exchange_kg > 0.0:
			var new_a_o2: float = (room_a.o2 * mass_a_base_kg + room_b.o2 * base_exchange_kg) \
				/ (mass_a_base_kg + base_exchange_kg)
			var new_b_o2: float = (room_b.o2 * mass_b_base_kg + room_a.o2 * base_exchange_kg) \
				/ (mass_b_base_kg + base_exchange_kg)
			room_a.o2 = clampf(new_a_o2, 0.0, o2_nominal)
			room_b.o2 = clampf(new_b_o2, 0.0, o2_nominal)

	var flow_state: Dictionary = _call_interior_flow_state(
		build_interior_flow_callable,
		room_a,
		room_b,
		op
	)
	if not bool(flow_state.get("active", false)):
		return

	var hot_room: RoomModel = flow_state.get("hot_room", null)
	var cold_room: RoomModel = flow_state.get("cold_room", null)
	if hot_room == null or cold_room == null:
		return

	var h_drive_m: float = float(flow_state.get("h_drive_m", 0.0))
	var area_eff_m2: float = float(flow_state.get("area_eff_m2", 0.0))
	var engagement: float = float(flow_state.get("engagement", 0.0))
	if h_drive_m <= 0.0 or area_eff_m2 <= 0.0 or engagement <= 0.0:
		return

	var source_temp_c: float = float(flow_state.get("source_temp_c", hot_room.temp_upper_c))
	var t_hot_k: float = source_temp_c + 273.15
	var t_cold_k: float = cold_room.temp_lower_c + 273.15
	var delta_t_k: float = float(flow_state.get("temp_delta_k", 0.0))
	var q_m3_s: float = 0.65 * 0.5 * area_eff_m2 * sqrt(
		g_gravity * h_drive_m * delta_t_k / ((t_hot_k + t_cold_k) * 0.5)
	)
	var exchange_kg: float = q_m3_s * air_density_kg_m3 * dt * doorway_o2_exchange_coeff * engagement
	var mass_hot_kg: float = _compute_room_air_mass_kg(hot_room, air_density_kg_m3)
	var mass_cold_kg: float = _compute_room_air_mass_kg(cold_room, air_density_kg_m3)
	var max_exchange_kg: float = minf(mass_hot_kg, mass_cold_kg) * 0.08
	exchange_kg = minf(exchange_kg, max_exchange_kg)
	if exchange_kg <= 0.0:
		return

	var new_hot_o2: float = (hot_room.o2 * mass_hot_kg + cold_room.o2 * exchange_kg) \
		/ (mass_hot_kg + exchange_kg)
	var new_cold_o2: float = (cold_room.o2 * mass_cold_kg + hot_room.o2 * exchange_kg) \
		/ (mass_cold_kg + exchange_kg)
	hot_room.o2 = clampf(new_hot_o2, 0.0, o2_nominal)
	cold_room.o2 = clampf(new_cold_o2, 0.0, o2_nominal)


func _compute_room_air_mass_kg(room: RoomModel, air_density_kg_m3: float) -> float:
	if room == null:
		return 0.1
	return maxf(0.1, room.volume_m3()) * air_density_kg_m3


func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float:
	if not callable.is_valid():
		return default_value
	return float(callable.call(room))


func _call_interior_flow_state(
	callable: Callable,
	room_a: RoomModel,
	room_b: RoomModel,
	op: OpeningModel
) -> Dictionary:
	if not callable.is_valid():
		return {}

	var result: Variant = callable.call(room_a, room_b, op)
	return result if result is Dictionary else {}
