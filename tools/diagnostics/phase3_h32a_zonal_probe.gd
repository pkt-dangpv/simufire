extends SceneTree

## H3.2a probe: does the zonal decomposition reconstruct every aggregate, and
## are the aggregates themselves bit-identical to the pre-change solver?
##
## The aggregate identity is what makes H3.2a additive. Any drift here is a
## NO-GO, not a tolerance discussion.

const SolverScript = preload("res://sim/core/Phase3CoupledPressureSolver.gd")
const DATA := "res://tests/fixtures/data"
const NAMES := [
	"coupled_solver_failure_corridor_chain",
	"coupled_solver_failure_r0_window_360",
	"coupled_solver_iteration_cap_corridor_chain",
	"coupled_solver_iteration_cap_after_rescue_corridor_chain",
	"coupled_solver_iteration_cap_two_floor_stairwell",
	"coupled_solver_iteration_cap_two_storey_smoke",
	"coupled_solver_iteration_cap_three_bed_apartment",
	"coupled_solver_iteration_cap_flashover_simple_house",
	"coupled_solver_damping_exhausted_uk_bungalow",
]


func _init() -> void:
	for raw_name in NAMES:
		var name: String = String(raw_name)
		var solved: Dictionary = _solve(name)
		if solved.is_empty():
			continue
		var combos: Dictionary = {}
		var worst_mass: float = 0.0
		var worst_energy: float = 0.0
		var routes_total: int = 0
		var counterflow: int = 0
		for raw_connection in solved.get("connections", []):
			var connection: Dictionary = raw_connection
			if not bool(connection.get("zonal_decomposition_applicable", false)):
				continue
			var directions: Dictionary = {}
			for raw_route in connection.get("zonal_routes", []):
				var route: Dictionary = raw_route
				routes_total += 1
				var combo: String = "%s->%s" % [
					String(route["source_zone"]), String(route["destination_zone"])
				]
				combos[combo] = int(combos.get(combo, 0)) + 1
				directions[String(route["direction"])] = true
			if directions.size() >= 2:
				counterflow += 1
			worst_mass = maxf(
				worst_mass, float(connection.get("zonal_mass_residual_kg", 0.0))
			)
			worst_energy = maxf(
				worst_energy,
				float(connection.get("zonal_energy_residual_kj", 0.0))
			)
		print(
			"%-58s conv=%-5s it=%2d | int=%d ext=%d routes=%d cf=%d unclass=%d valid=%s mres=%s eres=%s combos=%s"
			% [
				name,
				str(bool(solved.get("converged", false))),
				int(solved.get("iterations", 0.0)),
				int(solved.get("zonal_interior_connection_count", 0.0)),
				int(solved.get("zonal_exterior_connection_skipped_count", 0.0)),
				routes_total,
				counterflow,
				int(solved.get("zonal_unclassified_interior_band_count", 0.0)),
				str(bool(solved.get("zonal_decomposition_valid", false))),
				str(worst_mass),
				str(worst_energy),
				str(combos),
			]
		)
	print("H32A_ZONAL_PROBE_PASS")
	quit(0)


func _solve(name: String) -> Dictionary:
	var path := "%s/%s.json" % [DATA, name]
	if not FileAccess.file_exists(path):
		push_error("missing capture: " + path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var capture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var input: Dictionary = capture["input"]
	var rooms: Dictionary = {}
	for raw_key in input["rooms"].keys():
		rooms[String(raw_key)] = _numbers(input["rooms"][raw_key])
	var sources: Dictionary = {}
	for raw_key in input["sources"].keys():
		sources[String(raw_key)] = _numbers(input["sources"][raw_key])
	var openings: Array = []
	for raw_opening in input["openings"]:
		var o: Dictionary = raw_opening
		openings.append({
			"opening_id": int(o["opening_id"]),
			"room_a_id": int(o["room_a_id"]),
			"room_b_id": int(o["room_b_id"]),
			"bottom_m": _number(o, "bottom_m"),
			"top_m": _number(o, "top_m"),
			"width_m": _number(o, "width_m"),
			"open_fraction": _number(o, "open_fraction"),
			"discharge_coeff": _number(o, "discharge_coeff"),
		})
	var d: Dictionary = capture["solver_defaults"]
	var solver = SolverScript.new()
	return solver.solve_coupled_pressure(
		rooms, openings, sources,
		_number(input, "dt"), _number(input, "reference_temp_c"),
		{
			"residual_tolerance": _number(d, "residual_tolerance"),
			"max_iterations": int(d["max_iterations"]),
			"dp_regularization_pa": _number(d, "dp_regularization_pa"),
			"jacobian_step_pa": _number(d, "jacobian_step_pa"),
			"band_segments": int(d["band_segments"]),
			"max_damping_halvings": int(d["max_damping_halvings"]),
		}
	)


func _decode(leaf) -> float:
	if typeof(leaf) == TYPE_DICTIONARY and leaf.has("x"):
		var hex: String = String(leaf["x"])
		var bytes: PackedByteArray = PackedByteArray()
		for index in range(0, hex.length(), 2):
			bytes.append(hex.substr(index, 2).hex_to_int())
		if bytes.size() == 8:
			return bytes.decode_double(0)
		return float(String(leaf["d"]))
	return float(String(leaf))


func _number(source: Dictionary, key: String) -> float:
	return _decode(source[key])


func _numbers(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_key in source.keys():
		out[String(raw_key)] = _decode(source[raw_key])
	return out
