extends SceneTree

## H3.2a: the zonal decomposition of the coupled solver's connection output.
##
## The decomposition is a pure read of decisions the solver already made. Bands
## are split at both rooms' interfaces by `_build_opening`, so every band lies
## entirely inside one layer of A and one layer of B, and the label is taken
## from the same midpoint that already chose the band's density and specific
## enthalpy. Nothing here may move an aggregate.
##
## Synthetic cases cover the zone combinations the real captures do not reach,
## and the exterior case pins that an exterior opening is reported inapplicable
## rather than labelled with a layer it does not have.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")

## Aggregates and routes are summed in different orders on purpose - the
## aggregate order is frozen. This is the floating-point agreement bound, not a
## physical tolerance. Maximum observed across the corpus: 1e-14 kJ.
const ZONAL_ENERGY_RESIDUAL_BOUND_KJ := 1.0e-12
const ZONAL_MASS_RESIDUAL_BOUND_KG := 1.0e-12

var _failed: bool = false


func _init() -> void:
	_check_upper_to_upper()
	_check_lower_to_upper()
	_check_exterior_is_not_zoned()
	_check_counterflow_shares_connection_id()
	_check_residual_bounds_and_determinism()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3H32A_ZONAL_DECOMPOSITION_PASS")
	quit(0)


## Both rooms hot-dominated, so both interfaces sit low and the tall band above
## them is upper on both sides.
func _check_upper_to_upper() -> void:
	var solved: Dictionary = _solve_pair(
		# A: hotter and heavier -> drives flow towards B
		{"upper_gas_kg": 60.0, "lower_gas_kg": 6.0,
		 "upper_energy_kj": 9000.0, "lower_energy_kj": 60.0},
		{"upper_gas_kg": 50.0, "lower_gas_kg": 6.0,
		 "upper_energy_kj": 7000.0, "lower_energy_kj": 60.0},
		0.0, 3.0
	)
	var combos: Dictionary = _combinations(solved)
	_assert(
		combos.has("upper->upper"),
		"upper->upper present, got %s" % str(combos.keys())
	)
	print("H32A upper_to_upper combos=%s" % str(combos))


## A cool and deep-layered, B hot and shallow-layered: the middle band is lower
## on A and upper on B.
func _check_lower_to_upper() -> void:
	var solved: Dictionary = _solve_pair(
		# A: mostly cool lower gas -> high interface
		{"upper_gas_kg": 4.0, "lower_gas_kg": 70.0,
		 "upper_energy_kj": 400.0, "lower_energy_kj": 900.0},
		# B: mostly hot upper gas -> low interface
		{"upper_gas_kg": 50.0, "lower_gas_kg": 4.0,
		 "upper_energy_kj": 7000.0, "lower_energy_kj": 40.0},
		0.0, 3.0
	)
	var combos: Dictionary = _combinations(solved)
	_assert(
		combos.has("lower->upper"),
		"lower->upper present, got %s" % str(combos.keys())
	)
	# This asymmetric pair reaches every combination at once, which is the
	# strongest single case in the fixture.
	for combo in ["upper->upper", "upper->lower", "lower->upper", "lower->lower"]:
		_assert(
			combos.has(combo),
			"all four combinations present, missing %s" % combo
		)
	print("H32A lower_to_upper combos=%s" % str(combos))


## The exterior has no layers. It must be reported inapplicable, counted
## separately, and never labelled lower - while the interior network stays
## valid.
func _check_exterior_is_not_zoned() -> void:
	var rooms: Dictionary = {
		"0": _room(60.0, 20.0, 3.0, 40.0, 20.0, 5000.0, 200.0),
		"1": _room(60.0, 20.0, 3.0, 20.0, 40.0, 2000.0, 400.0),
	}
	var openings: Array = [
		_opening(0, 0, 1, 0.0, 3.0),      # interior
		_opening(1, 0, -1, 0.0, 1.5),     # exterior
	]
	var solver = SolverScript.new()
	var solved: Dictionary = solver.solve_coupled_pressure(
		rooms, openings, {"0": _source(), "1": _source()}, 1.0, 20.0
	)
	var exterior_seen: bool = false
	var interior_seen: bool = false
	for raw_connection in solved.get("connections", []):
		var connection: Dictionary = raw_connection
		var applicable: bool = bool(
			connection.get("zonal_decomposition_applicable", false)
		)
		var is_exterior: bool = int(connection["room_a_id"]) < 0 \
				or int(connection["room_b_id"]) < 0
		if is_exterior:
			exterior_seen = true
			_assert(not applicable, "exterior connection is inapplicable")
			_assert(
				Array(connection.get("zonal_routes", [])).is_empty(),
				"exterior connection emits no zonal routes"
			)
			_assert(
				int(connection.get("unclassified_interior_band_count", -1)) == 0,
				"exterior bands never count as unclassified interior bands"
			)
			_assert(
				int(connection.get("exterior_unzoned_band_count", 0)) > 0,
				"exterior bands are counted in their own bucket"
			)
		else:
			interior_seen = true
			_assert(applicable, "interior connection stays applicable")
			for raw_route in connection.get("zonal_routes", []):
				var route: Dictionary = raw_route
				for zone_key in ["source_zone", "destination_zone"]:
					var zone: String = String(route[zone_key])
					_assert(
						zone == "upper" or zone == "lower",
						"interior zones are real layers, got '%s'" % zone
					)
	_assert(exterior_seen and interior_seen, "both connection kinds present")
	# An exterior opening must not invalidate the interior network.
	_assert(
		bool(solved.get("zonal_decomposition_valid", false)),
		"exterior presence does not invalidate the interior decomposition"
	)
	_assert(
		float(solved.get("zonal_exterior_connection_skipped_count", 0.0)) >= 1.0,
		"exterior connections are counted separately"
	)
	_assert(
		float(solved.get("zonal_unclassified_interior_band_count", -1.0)) == 0.0,
		"no interior band is unclassified"
	)
	print(
		"H32A exterior int=%d ext=%d ext_bands=%d"
		% [
			int(solved.get("zonal_interior_connection_count", 0.0)),
			int(solved.get("zonal_exterior_connection_skipped_count", 0.0)),
			int(solved.get("zonal_exterior_unzoned_band_count", 0.0)),
		]
	)


## Two opposite directions on one opening keep one connection_id.
func _check_counterflow_shares_connection_id() -> void:
	var solved: Dictionary = _solve_pair(
		{"upper_gas_kg": 45.0, "lower_gas_kg": 25.0,
		 "upper_energy_kj": 6000.0, "lower_energy_kj": 250.0},
		{"upper_gas_kg": 25.0, "lower_gas_kg": 45.0,
		 "upper_energy_kj": 1500.0, "lower_energy_kj": 450.0},
		0.0, 3.0
	)
	for raw_connection in solved.get("connections", []):
		var connection: Dictionary = raw_connection
		if not bool(connection.get("zonal_decomposition_applicable", false)):
			continue
		var ids: Dictionary = {}
		var directions: Dictionary = {}
		for raw_route in connection.get("zonal_routes", []):
			var route: Dictionary = raw_route
			ids[String(route["connection_id"])] = true
			directions[String(route["direction"])] = true
		if directions.size() >= 2:
			_assert(
				ids.size() == 1,
				"both directions share one connection_id, got %d" % ids.size()
			)
			print("H32A counterflow shares %s" % str(ids.keys()))
			return
	# Not reaching counterflow here is acceptable; the real captures cover it.
	print("H32A counterflow not exercised by the synthetic pair")


## The decomposition must reconstruct each aggregate within the stated
## floating-point bound, and be reproducible.
func _check_residual_bounds_and_determinism() -> void:
	var first: Dictionary = _solve_pair(
		{"upper_gas_kg": 45.0, "lower_gas_kg": 25.0,
		 "upper_energy_kj": 6000.0, "lower_energy_kj": 250.0},
		{"upper_gas_kg": 25.0, "lower_gas_kg": 45.0,
		 "upper_energy_kj": 1500.0, "lower_energy_kj": 450.0},
		0.0, 3.0
	)
	var second: Dictionary = _solve_pair(
		{"upper_gas_kg": 45.0, "lower_gas_kg": 25.0,
		 "upper_energy_kj": 6000.0, "lower_energy_kj": 250.0},
		{"upper_gas_kg": 25.0, "lower_gas_kg": 45.0,
		 "upper_energy_kj": 1500.0, "lower_energy_kj": 450.0},
		0.0, 3.0
	)
	for raw_connection in first.get("connections", []):
		var connection: Dictionary = raw_connection
		if not bool(connection.get("zonal_decomposition_applicable", false)):
			continue
		_assert(
			float(connection.get("zonal_mass_residual_kg", 1.0))
					<= ZONAL_MASS_RESIDUAL_BOUND_KG,
			"zonal mass residual within bound"
		)
		_assert(
			float(connection.get("zonal_energy_residual_kj", 1.0))
					<= ZONAL_ENERGY_RESIDUAL_BOUND_KJ,
			"zonal energy residual within bound"
		)
		# Route order must be deterministic.
		var keys: Array = []
		for raw_route in connection.get("zonal_routes", []):
			var route: Dictionary = raw_route
			keys.append("%s|%s|%s|%s" % [
				String(route["connection_id"]), String(route["direction"]),
				String(route["source_zone"]), String(route["destination_zone"]),
			])
		var sorted_keys: Array = keys.duplicate()
		sorted_keys.sort()
		_assert(keys == sorted_keys, "routes are emitted in sorted order")
	for field in [
		"converged", "iterations", "residual_history", "normalized_residual",
		"zonal_mass_residual_kg", "zonal_energy_residual_kj",
		"zonal_interior_connection_count", "zonal_decomposition_valid",
	]:
		_assert(first[field] == second[field], "deterministic " + field)


func _combinations(solved: Dictionary) -> Dictionary:
	var combos: Dictionary = {}
	for raw_connection in solved.get("connections", []):
		var connection: Dictionary = raw_connection
		if not bool(connection.get("zonal_decomposition_applicable", false)):
			continue
		for raw_route in connection.get("zonal_routes", []):
			var route: Dictionary = raw_route
			var combo: String = "%s->%s" % [
				String(route["source_zone"]), String(route["destination_zone"])
			]
			combos[combo] = int(combos.get(combo, 0)) + 1
	return combos


func _solve_pair(
		state_a: Dictionary, state_b: Dictionary,
		bottom_m: float, top_m: float
	) -> Dictionary:
	var rooms: Dictionary = {
		"0": _room(
			60.0, 20.0, 3.0,
			float(state_a["upper_gas_kg"]), float(state_a["lower_gas_kg"]),
			float(state_a["upper_energy_kj"]), float(state_a["lower_energy_kj"])
		),
		"1": _room(
			60.0, 20.0, 3.0,
			float(state_b["upper_gas_kg"]), float(state_b["lower_gas_kg"]),
			float(state_b["upper_energy_kj"]), float(state_b["lower_energy_kj"])
		),
	}
	var solver = SolverScript.new()
	return solver.solve_coupled_pressure(
		rooms, [_opening(0, 0, 1, bottom_m, top_m)],
		{"0": _source(), "1": _source()}, 1.0, 20.0
	)


func _room(
		volume_m3: float, floor_area_m2: float, height_m: float,
		upper_gas_kg: float, lower_gas_kg: float,
		upper_energy_kj: float, lower_energy_kj: float
	) -> Dictionary:
	return {
		"volume_m3": volume_m3,
		"floor_area_m2": floor_area_m2,
		"height_m": height_m,
		"upper_gas_kg": upper_gas_kg,
		"lower_gas_kg": lower_gas_kg,
		"upper_energy_kj": upper_energy_kj,
		"lower_energy_kj": lower_energy_kj,
	}


func _opening(
		opening_id: int, room_a_id: int, room_b_id: int,
		bottom_m: float, top_m: float
	) -> Dictionary:
	return {
		"opening_id": opening_id,
		"room_a_id": room_a_id,
		"room_b_id": room_b_id,
		"bottom_m": bottom_m,
		"top_m": top_m,
		"width_m": 0.9,
		"open_fraction": 1.0,
		"discharge_coeff": 0.7,
	}


func _source() -> Dictionary:
	return {"mass_kg": 0.0, "energy_kj": 0.0}


func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		_failed = true
