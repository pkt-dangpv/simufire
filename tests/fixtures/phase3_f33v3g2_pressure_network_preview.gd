extends SceneTree

const SystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

const SPECIES_NAMES: Array[String] = [
	"smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"
]

var _failed: bool = false


func _init() -> void:
	var system = SystemScript.new()
	_test_components_single_connection(system)
	_test_components_three_room_chain(system)
	_test_components_two_disconnected(system)
	_test_components_reversed_opening_order(system)
	_test_single_component_blend(system)
	_test_disconnected_components_do_not_influence_each_other(system)
	_test_gas_inventory_limits(system)
	_test_energy_inventory_limits(system)
	_test_o2_inventory_limits(system)
	_test_species_inventory_limits(system)
	_test_invalid_base_inventory_fails_closed(system)
	_test_non_descent_is_dormant(system)
	_test_opening_order_invariance(system)
	# `quit()` only requests a shutdown, so execution continues.
	# Return explicitly or the PASS marker below is still printed.
	if _failed:
		quit(1)
		return
	print("PHASE3_F33V3G2_PRESSURE_NETWORK_PREVIEW_PASS")
	quit(0)


# ---------------------------------------------------------------------------
# connected components
# ---------------------------------------------------------------------------

func _test_components_single_connection(system) -> void:
	var components: Array = system.compute_interior_pressure_network_components(
		[{"room_a_id": 0, "room_b_id": 1}]
	)
	_assert_true(components.size() == 1, "single component count")
	_assert_true(
		String(components[0]["component_id"]) == "0|1", "single component id"
	)
	_assert_true(
		float(components[0]["connection_pairs"].size()) == 1.0,
		"single component connections"
	)


func _test_components_three_room_chain(system) -> void:
	var components: Array = system.compute_interior_pressure_network_components(
		[
			{"room_a_id": 1, "room_b_id": 2},
			{"room_a_id": 0, "room_b_id": 1},
		]
	)
	_assert_true(components.size() == 1, "chain component count")
	_assert_true(
		String(components[0]["component_id"]) == "0|1|2", "chain component id"
	)
	_assert_true(
		components[0]["connection_pairs"].size() == 2, "chain connections"
	)


func _test_components_two_disconnected(system) -> void:
	var components: Array = system.compute_interior_pressure_network_components(
		[
			{"room_a_id": 5, "room_b_id": 4},
			{"room_a_id": 0, "room_b_id": 1},
		]
	)
	_assert_true(components.size() == 2, "disconnected component count")
	_assert_true(
		String(components[0]["component_id"]) == "0|1", "disconnected first id"
	)
	_assert_true(
		String(components[1]["component_id"]) == "4|5", "disconnected second id"
	)
	_close(float(components[0]["component_index"]), 0.0, "disconnected index 0")
	_close(float(components[1]["component_index"]), 1.0, "disconnected index 1")


func _test_components_reversed_opening_order(system) -> void:
	var forward: Array = system.compute_interior_pressure_network_components(
		[
			{"room_a_id": 0, "room_b_id": 1},
			{"room_a_id": 1, "room_b_id": 2},
			{"room_a_id": 4, "room_b_id": 5},
		]
	)
	var reverse: Array = system.compute_interior_pressure_network_components(
		[
			{"room_a_id": 5, "room_b_id": 4},
			{"room_a_id": 2, "room_b_id": 1},
			{"room_a_id": 1, "room_b_id": 0},
		]
	)
	_assert_true(forward.size() == reverse.size(), "reversed component count")
	for position in range(forward.size()):
		_assert_true(
			String(forward[position]["component_id"])
					== String(reverse[position]["component_id"]),
			"reversed component id %d" % position
		)
		_assert_true(
			forward[position]["connection_pairs"]
					== reverse[position]["connection_pairs"],
			"reversed component pairs %d" % position
		)


# ---------------------------------------------------------------------------
# preview blend
# ---------------------------------------------------------------------------

func _test_single_component_blend(system) -> void:
	var preview: Dictionary = _run_single_connection_preview(
		system, _generous_snapshots(), {"0": -150.0, "1": 150.0}
	)
	_assert_true(bool(preview["valid"]), "blend valid")
	_close(float(preview["component_count"]), 1.0, "blend component count")
	var component: Dictionary = preview["components"][0]
	_close(float(component["alpha_optimal"]), 1.0 / 3.0, "blend alpha optimal")
	_close(float(component["alpha_inventory"]), 1.0, "blend alpha inventory")
	_close(float(component["alpha_accepted"]), 1.0 / 3.0, "blend alpha accepted")
	_assert_true(
		float(component["objective_post_pa2"])
				<= float(component["objective_pre_pa2"]) + 1.0e-9,
		"blend objective descends"
	)
	# One alpha for every payload: mass, sensible enthalpy, O2 and species.
	var totals: Dictionary = component["room_totals"]["0"]
	_close(
		float(totals["accepted_out_mass_kg"]),
		1.0 + (1.0 / 3.0) * 0.2,
		"blend accepted out mass"
	)
	_close(
		float(totals["accepted_out_energy_kj"]),
		50.0 + (1.0 / 3.0) * 10.0,
		"blend accepted out energy"
	)
	_close(
		float(totals["base_out_mass_kg"]) + float(totals["base_in_mass_kg"])
				- float(totals["accepted_out_mass_kg"])
				- float(totals["accepted_in_mass_kg"]),
		0.0,
		"blend room gross preserved"
	)
	for residual_name in [
		"gross_mass_residual_kg", "mass_residual_kg", "energy_residual_kj",
		"o2_residual_kg", "species_residual_kg", "negative_quantity_count",
	]:
		_close(float(component[residual_name]), 0.0, "blend " + residual_name)
	_assert_true(
		float(component["predicted_min_upper_gas_kg"]) > 0.0
				and float(component["predicted_min_lower_gas_kg"]) > 0.0,
		"blend predicted inventory positive"
	)


func _test_disconnected_components_do_not_influence_each_other(system) -> void:
	var routes: Dictionary = _two_component_routes(system)
	var snapshots: Dictionary = _generous_snapshots()
	snapshots["2"] = snapshots["0"].duplicate(true)
	snapshots["3"] = snapshots["1"].duplicate(true)
	var preview: Dictionary = system.preview_fixed_gross_interior_pressure_network(
		routes["base"],
		routes["full"],
		{"0": 100.0, "1": 0.0, "2": 20.0, "3": 0.0},
		{},
		{"0": -150.0, "1": 150.0, "2": -10.0, "3": 10.0},
		[
			{"room_a_id": 0, "room_b_id": 1},
			{"room_a_id": 2, "room_b_id": 3},
		],
		snapshots
	)
	_assert_true(bool(preview["valid"]), "two component valid")
	_close(float(preview["component_count"]), 2.0, "two component count")
	var first: Dictionary = preview["components"][0]
	var second: Dictionary = preview["components"][1]
	_close(float(first["alpha_accepted"]), 1.0 / 3.0, "two component alpha 0")
	_close(float(second["alpha_accepted"]), 1.0, "two component alpha 1")
	var isolated: Dictionary = _run_single_connection_preview(
		system, _generous_snapshots(), {"0": -150.0, "1": 150.0}
	)
	_close(
		float(first["alpha_accepted"]),
		float(isolated["components"][0]["alpha_accepted"]),
		"two component isolation"
	)


# ---------------------------------------------------------------------------
# inventory bounds
# ---------------------------------------------------------------------------

func _test_gas_inventory_limits(system) -> void:
	var snapshots: Dictionary = _generous_snapshots()
	snapshots["0"]["upper_gas_kg"] = 1.05
	var preview: Dictionary = _run_single_connection_preview(
		system, snapshots, {"0": -150.0, "1": 150.0}
	)
	_assert_true(bool(preview["valid"]), "gas inventory valid")
	var component: Dictionary = preview["components"][0]
	_close(float(component["alpha_inventory"]), 0.25, "gas inventory alpha")
	_close(float(component["alpha_accepted"]), 0.25, "gas inventory accepted")
	_close(float(component["limiting_reason_code"]), 3.0, "gas inventory reason")


func _test_energy_inventory_limits(system) -> void:
	var snapshots: Dictionary = _generous_snapshots()
	snapshots["0"]["upper_energy_kj"] = 52.0
	var preview: Dictionary = _run_single_connection_preview(
		system, snapshots, {"0": -150.0, "1": 150.0}
	)
	var component: Dictionary = preview["components"][0]
	_close(float(component["alpha_inventory"]), 0.2, "energy inventory alpha")
	_close(float(component["alpha_accepted"]), 0.2, "energy inventory accepted")


func _test_o2_inventory_limits(system) -> void:
	var snapshots: Dictionary = _generous_snapshots()
	snapshots["0"]["upper_o2_kg"] = 0.206
	var preview: Dictionary = _run_single_connection_preview(
		system, snapshots, {"0": -150.0, "1": 150.0}
	)
	var component: Dictionary = preview["components"][0]
	_close(float(component["alpha_inventory"]), 0.15, "o2 inventory alpha")
	_close(float(component["alpha_accepted"]), 0.15, "o2 inventory accepted")


func _test_species_inventory_limits(system) -> void:
	var snapshots: Dictionary = _generous_snapshots()
	snapshots["0"]["upper_species_kg"]["co"] = 0.0103
	var preview: Dictionary = _run_single_connection_preview(
		system, snapshots, {"0": -150.0, "1": 150.0}
	)
	var component: Dictionary = preview["components"][0]
	_close(float(component["alpha_inventory"]), 0.15, "species inventory alpha")
	_close(float(component["alpha_accepted"]), 0.15, "species inventory accepted")


func _test_invalid_base_inventory_fails_closed(system) -> void:
	var snapshots: Dictionary = _generous_snapshots()
	snapshots["0"]["upper_gas_kg"] = 0.5
	var preview: Dictionary = _run_single_connection_preview(
		system, snapshots, {"0": -150.0, "1": 150.0}
	)
	_assert_true(not bool(preview["valid"]), "invalid base preview")
	var component: Dictionary = preview["components"][0]
	_close(float(component["valid_flag"]), 0.0, "invalid base valid flag")
	_close(float(component["alpha_accepted"]), 0.0, "invalid base alpha")
	_close(float(component["limiting_reason_code"]), 0.0, "invalid base reason")
	_close(
		float(component["room_totals"]["0"]["accepted_out_mass_kg"]),
		float(component["room_totals"]["0"]["base_out_mass_kg"]),
		"invalid base falls back to base routes"
	)


# ---------------------------------------------------------------------------
# descent and order invariance
# ---------------------------------------------------------------------------

func _test_non_descent_is_dormant(system) -> void:
	var preview: Dictionary = _run_single_connection_preview(
		system, _generous_snapshots(), {"0": 10.0, "1": -10.0}
	)
	_assert_true(bool(preview["valid"]), "non descent valid")
	var component: Dictionary = preview["components"][0]
	_close(float(component["alpha_accepted"]), 0.0, "non descent alpha")
	_close(float(component["limiting_reason_code"]), 4.0, "non descent reason")
	_close(
		float(component["objective_post_pa2"]),
		float(component["objective_pre_pa2"]),
		"non descent objective unchanged"
	)


func _test_opening_order_invariance(system) -> void:
	var forward: Dictionary = _run_single_connection_preview(
		system, _generous_snapshots(), {"0": -150.0, "1": 150.0}, false
	)
	var reverse: Dictionary = _run_single_connection_preview(
		system, _generous_snapshots(), {"0": -150.0, "1": 150.0}, true
	)
	var forward_component: Dictionary = forward["components"][0]
	var reverse_component: Dictionary = reverse["components"][0]
	for field_name in [
		"alpha_optimal", "alpha_crossing", "alpha_inventory", "alpha_accepted",
		"objective_pre_pa2", "objective_post_pa2",
	]:
		_close(
			float(forward_component[field_name]),
			float(reverse_component[field_name]),
			"order " + field_name
		)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _run_single_connection_preview(
		system,
		snapshots: Dictionary,
		full_delta_by_room: Dictionary,
		reversed_order: bool = false
	) -> Dictionary:
	var routes: Dictionary = _single_connection_routes(system, reversed_order)
	return system.preview_fixed_gross_interior_pressure_network(
		routes["base"],
		routes["full"],
		{"0": 100.0, "1": 0.0},
		{},
		full_delta_by_room,
		[{"room_a_id": 0, "room_b_id": 1}],
		snapshots
	)


func _single_connection_routes(system, reversed_order: bool) -> Dictionary:
	var forward: Dictionary = _route(
		system, "f33a_interior:0:000", 0, 0, 1, "upper", "upper",
		1.0, 50.0, 0.2, 0.01
	)
	var backward: Dictionary = _route(
		system, "f33a_interior:0:001", 0, 1, 0, "lower", "lower",
		1.0, 20.0, 0.25, 0.02
	)
	var base_routes: Array = [forward, backward]
	if reversed_order:
		base_routes = [backward, forward]
	var pressure_routes: Array = [
		_route(
			system, "f33b_pressure:0:000", 0, 0, 1, "upper", "upper",
			0.4, 20.0, 0.08, 0.004
		)
	]
	var candidate: Dictionary = system.preview_fixed_gross_interior_pressure_skew(
		base_routes, pressure_routes
	)
	return {"base": base_routes, "full": candidate["routes"]}


func _two_component_routes(system) -> Dictionary:
	var first: Dictionary = _single_connection_routes(system, false)
	var second_base: Array = [
		_route(
			system, "f33a_interior:1:000", 1, 2, 3, "upper", "upper",
			1.0, 50.0, 0.2, 0.01
		),
		_route(
			system, "f33a_interior:1:001", 1, 3, 2, "lower", "lower",
			1.0, 20.0, 0.25, 0.02
		),
	]
	var second_pressure: Array = [
		_route(
			system, "f33b_pressure:1:000", 1, 2, 3, "upper", "upper",
			0.4, 20.0, 0.08, 0.004
		)
	]
	var second_candidate: Dictionary = \
			system.preview_fixed_gross_interior_pressure_skew(
				second_base, second_pressure
			)
	var base_routes: Array = []
	base_routes.append_array(first["base"])
	base_routes.append_array(second_base)
	var full_routes: Array = []
	full_routes.append_array(first["full"])
	full_routes.append_array(second_candidate["routes"])
	return {"base": base_routes, "full": full_routes}


func _route(
		system,
		route_id: String,
		opening_id: int,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		gas_mass_kg: float,
		sensible_enthalpy_kj: float,
		o2_kg: float,
		species_value_kg: float
	) -> Dictionary:
	var species: Dictionary = {}
	for species_name in SPECIES_NAMES:
		species[species_name] = species_value_kg
	var route: Dictionary = system.make_atomic_route(
		route_id,
		"canonical_interior_opening",
		source_room_id,
		destination_room_id,
		source_zone,
		destination_zone,
		gas_mass_kg,
		sensible_enthalpy_kj,
		o2_kg,
		species
	)
	route["connection_id"] = "opening:%d" % opening_id
	route["opening_id"] = opening_id
	return route


func _generous_snapshots() -> Dictionary:
	return {
		"0": _snapshot(40.0, 40.0, 4000.0, 4000.0, 8.0, 8.0, 4.0),
		"1": _snapshot(40.0, 40.0, 4000.0, 4000.0, 8.0, 8.0, 4.0),
	}


func _snapshot(
		upper_gas_kg: float,
		lower_gas_kg: float,
		upper_energy_kj: float,
		lower_energy_kj: float,
		upper_o2_kg: float,
		lower_o2_kg: float,
		species_value_kg: float
	) -> Dictionary:
	var upper_species: Dictionary = {}
	var lower_species: Dictionary = {}
	for species_name in SPECIES_NAMES:
		upper_species[species_name] = species_value_kg
		lower_species[species_name] = species_value_kg
	return {
		"upper_gas_kg": upper_gas_kg,
		"lower_gas_kg": lower_gas_kg,
		"upper_energy_kj": upper_energy_kj,
		"lower_energy_kj": lower_energy_kj,
		"upper_o2_kg": upper_o2_kg,
		"lower_o2_kg": lower_o2_kg,
		"upper_species_kg": upper_species,
		"lower_species_kg": lower_species,
	}


func _close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 1.0e-8 * maxf(1.0, absf(expected)):
		push_error("%s: got %.12f expected %.12f" % [label, actual, expected])
		_failed = true


func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failed = true
