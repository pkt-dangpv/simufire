extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

const EPSILON: float = 1.0e-7

var _failed: bool = false


func _init() -> void:
	_test_missing_topology_fails_adiabatic()
	_test_valid_mixed_topology()
	_test_explicit_zero_exterior_is_complete()
	_test_invalid_topologies_fail_closed()
	_test_building_loads_deep_copy()
	_test_mixed_exterior_exchange_closes()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33R2B2_SURFACE_TOPOLOGY_PASS")
	quit(0)


func _test_missing_topology_fails_adiabatic() -> void:
	var ledger = ZoneMassSystemScript.new()
	var context: Dictionary = ledger.build_canonical_surface_boundary_context(
		{}, 5.0
	)
	_assert_true(not bool(context.get("valid", true)), "missing invalid")
	_assert_close(
		float(context.get("boundary_metadata_complete_flag", -1.0)),
		0.0,
		"missing incomplete"
	)
	_assert_close(
		float(context.get("adiabatic_surface_count", -1.0)),
		4.0,
		"missing all adiabatic"
	)
	_assert_true(
		Dictionary(context.get("exterior_by_surface", {})).is_empty(),
		"missing no exterior"
	)


func _test_valid_mixed_topology() -> void:
	var ledger = ZoneMassSystemScript.new()
	var context: Dictionary = ledger.build_canonical_surface_boundary_context(
		_mixed_topology(), 7.0
	)
	_assert_true(bool(context.get("valid", false)), "mixed valid")
	_assert_close(
		float(context.get("boundary_metadata_complete_flag", 0.0)),
		1.0,
		"mixed complete"
	)
	_assert_close(
		float(context.get("exterior_fraction_sum", 0.0)),
		1.5,
		"mixed exterior sum"
	)
	_assert_close(
		float(context.get("inter_room_fraction_sum", 0.0)),
		1.25,
		"mixed inter-room sum"
	)
	_assert_close(
		float(context.get("adiabatic_fraction_sum", 0.0)),
		1.25,
		"mixed adiabatic sum"
	)
	_assert_close(
		float(context.get("unsupported_inter_room_surface_count", 0.0)),
		2.0,
		"mixed inter-room visible"
	)
	_assert_close(
		float(context.get("adiabatic_surface_count", 0.0)),
		1.0,
		"mixed one fully adiabatic"
	)
	var exterior: Dictionary = context.get("exterior_by_surface", {})
	_assert_close(
		float(exterior["ceiling"]["exterior_h_kw_m2_k"]),
		0.025,
		"full exterior h"
	)
	_assert_close(
		float(exterior["upper_wall"]["exterior_h_kw_m2_k"]),
		0.0125,
		"fractional exterior h"
	)
	_assert_true(
		not exterior.has("lower_wall"),
		"inter-room is not exterior"
	)


func _test_explicit_zero_exterior_is_complete() -> void:
	var ledger = ZoneMassSystemScript.new()
	var context: Dictionary = ledger.build_canonical_surface_boundary_context(
		_all_adiabatic_topology(), 20.0
	)
	_assert_true(bool(context.get("valid", false)), "adiabatic valid")
	_assert_close(
		float(context.get("boundary_metadata_complete_flag", 0.0)),
		1.0,
		"adiabatic complete"
	)
	_assert_close(
		float(context.get("adiabatic_surface_count", 0.0)),
		4.0,
		"adiabatic count"
	)
	_assert_true(
		Dictionary(context.get("exterior_by_surface", {})).is_empty(),
		"adiabatic no exterior map"
	)


func _test_invalid_topologies_fail_closed() -> void:
	var ledger = ZoneMassSystemScript.new()
	var cases: Array = [
		"not-a-dictionary",
		{"ceiling": _fractions(1.0, 0.0, 0.0)},
		_all_adiabatic_topology().merged({
			"floor": _fractions(0.8, 0.3, 0.0)
		}, true),
		_all_adiabatic_topology().merged({
			"floor": _fractions(-0.1, 0.0, 1.1)
		}, true),
		_all_adiabatic_topology().merged({
			"floor": {
				"exterior_fraction": "outside",
				"inter_room_fraction": 0.0,
				"adiabatic_fraction": 1.0,
			}
		}, true),
	]
	for raw_topology in cases:
		var context: Dictionary = \
				ledger.build_canonical_surface_boundary_context(
					raw_topology, 20.0
				)
		_assert_true(
			not bool(context.get("valid", true)),
			"invalid topology rejected"
		)
		_assert_true(
			Dictionary(context.get("exterior_by_surface", {})).is_empty(),
			"invalid topology has no exterior"
		)


func _test_building_loads_deep_copy() -> void:
	var topology: Dictionary = _mixed_topology()
	var building = BuildingModelScript.new()
	var loaded: bool = building.load_template_data({
		"room_rect_m": {0: Rect2(0.0, 0.0, 4.0, 4.0)},
		"rooms_data": [{
			"id": 0,
			"name": "Test",
			"kind": "salon",
			"height_m": 2.5,
			"phase3_surface_boundaries": topology,
		}],
		"openings_data": [],
	})
	_assert_true(loaded, "building topology loaded")
	var room = building.get_room(0)
	_assert_true(room != null, "building room exists")
	_assert_true(
		room.phase3_surface_boundaries == topology,
		"building topology preserved"
	)
	topology["ceiling"]["exterior_fraction"] = 0.0
	_assert_close(
		float(room.phase3_surface_boundaries["ceiling"]["exterior_fraction"]),
		1.0,
		"building topology deep copied"
	)
	building.free()


func _test_mixed_exterior_exchange_closes() -> void:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 38.0
	room.upper_energy_kj = 200.0
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	room.o2 = 0.209
	building.rooms = {0: room}
	var ledger = ZoneMassSystemScript.new()
	ledger.configure_canonical_multisurface_shadow(true)
	ledger.begin_step(building, true)
	var prepared: Dictionary = ledger.prepare_canonical_multisurface_room(
		0,
		{
			"floor_area_m2": 16.0,
			"perimeter_m": 16.0,
			"height_m": 2.5,
			"interface_m": 1.25,
		},
		{
			"conductivity_kw_m_k": 0.00175,
			"density_kg_m3": 2200.0,
			"cp_kj_kg_k": 1.0,
			"thickness_m": 0.15,
			"emissivity": 0.9,
		},
		40.0
	)
	_assert_true(bool(prepared.get("valid", false)), "mixed prepare")
	var boundaries: Dictionary = ledger.build_canonical_surface_boundary_context(
		_mixed_topology(), 0.0
	)
	var preview_context: Dictionary = {
		"dt_s": 1.0,
		"upper_temp_c": 40.0,
		"lower_temp_c": 40.0,
		"upper_h_kw_m2_k": 0.0,
		"lower_h_kw_m2_k": 0.0,
		"upper_gas_emissivity": 0.0,
		"lower_gas_emissivity": 0.0,
	}
	for key in boundaries.keys():
		preview_context[key] = boundaries[key]
	var preview: Dictionary = ledger.preview_canonical_multisurface_exchange(
		0, preview_context
	)
	_assert_true(bool(preview.get("valid", false)), "mixed preview")
	_assert_true(
		float(preview.get("exterior_removed_requested_kj", 0.0)) > 0.0,
		"mixed exterior removes energy"
	)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(0, preview, "mixed"),
		"mixed queued"
	)
	ledger.finalize_step(building, 20.0)
	var exchange: Dictionary = ledger.get_canonical_multisurface_exchange_record(0)
	_assert_close(
		float(exchange.get("combined_energy_residual_kj", 1.0)),
		0.0,
		"mixed exchange conservation"
	)
	building.free()


func _mixed_topology() -> Dictionary:
	return {
		"ceiling": _fractions(1.0, 0.0, 0.0),
		"upper_wall": _fractions(0.5, 0.25, 0.25),
		"lower_wall": _fractions(0.0, 1.0, 0.0),
		"floor": _fractions(0.0, 0.0, 1.0),
	}


func _all_adiabatic_topology() -> Dictionary:
	return {
		"ceiling": _fractions(0.0, 0.0, 1.0),
		"upper_wall": _fractions(0.0, 0.0, 1.0),
		"lower_wall": _fractions(0.0, 0.0, 1.0),
		"floor": _fractions(0.0, 0.0, 1.0),
	}


func _fractions(exterior: float, inter_room: float, adiabatic: float) -> Dictionary:
	return {
		"exterior_fraction": exterior,
		"inter_room_fraction": inter_room,
		"adiabatic_fraction": adiabatic,
	}


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > EPSILON:
		_fail("%s: expected %.9f got %.9f" % [label, expected, actual])


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label)


func _fail(message: String) -> void:
	_failed = true
	push_error("PHASE3_F33R2B2_SURFACE_TOPOLOGY_FAIL: " + message)
