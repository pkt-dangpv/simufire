extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

var _failed: bool = false


func _init() -> void:
	_test_default_off_and_exact_connection_totals()
	if _failed:
		quit(1)
	else:
		print("PHASE3_F33K_CONNECTION_RESIDENCE_LEDGER_PASS")
		quit(0)


func _test_default_off_and_exact_connection_totals() -> void:
	var building = _make_building()
	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building, true)
	_add_tagged_route(
		system, "off", "canonical_interior_opening",
		0, 1, "upper", "lower", 2.0, 100.0, 7
	)
	system.finalize_step(building, 20.0)
	_assert_true(
		system.get_connection_residence_results().is_empty(),
		"default OFF has no connection records"
	)

	system.reset()
	system.configure_connection_residence_diagnostics(true)
	system.begin_step(building, true)
	_add_tagged_route(
		system, "opening", "canonical_interior_opening",
		0, 1, "upper", "lower", 2.0, 100.0, 7
	)
	_add_tagged_route(
		system, "pressure", "canonical_interior_pressure",
		1, 0, "lower", "upper", 1.0, 10.0, 7
	)
	system.finalize_step(building, 20.0)
	var records: Array = system.get_connection_residence_results()
	_assert_true(records.size() == 2, "one record per family and direction")
	var opening: Dictionary = _find_record(records, "interior_opening")
	var pressure: Dictionary = _find_record(records, "interior_pressure")
	_assert_close(float(opening.get("accepted_mass_kg", 0.0)), 2.0, "opening mass")
	_assert_close(
		float(opening.get("accepted_enthalpy_kj", 0.0)), 100.0,
		"opening enthalpy"
	)
	_assert_close(
		float(opening.get("mass_weighted_source_temp_c", 0.0)), 70.0,
		"opening source temperature"
	)
	_assert_close(
		float(opening.get("destination_upper_fraction", -1.0)), 0.0,
		"opening lower destination"
	)
	_assert_close(
		float(pressure.get("mass_weighted_source_temp_c", 0.0)), 30.0,
		"pressure source temperature"
	)
	_assert_close(
		float(pressure.get("destination_upper_fraction", 0.0)), 1.0,
		"pressure upper destination"
	)
	system.reset()
	_assert_true(
		system.get_connection_residence_results().is_empty(),
		"reset clears cumulative connection records"
	)
	building.free()


func _add_tagged_route(
		system,
		route_id: String,
		cause: String,
		source_room_id: int,
		destination_room_id: int,
		source_zone: String,
		destination_zone: String,
		mass_kg: float,
		energy_kj: float,
		opening_id: int
	) -> void:
	var route: Dictionary = system.make_atomic_route(
		route_id, cause, source_room_id, destination_room_id,
		source_zone, destination_zone, mass_kg, energy_kj
	)
	system._tag_connection_route(route, opening_id, 20.0)
	system.add_atomic_bundle(system.make_atomic_bundle(
		route_id + ":bundle", cause, [route], {"kind": "fixture"}
	))


func _find_record(records: Array, family_name: String) -> Dictionary:
	for raw_record in records:
		var record: Dictionary = raw_record
		if String(record.get("family", "")) == family_name:
			return record
	return {}


func _make_building():
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	building.rooms = {
		0: _make_room(0),
		1: _make_room(1),
	}
	return building


func _make_room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 5.0
	room.height_m = 2.4
	room.upper_gas_kg = 28.8
	room.lower_gas_kg = 28.8
	room.upper_energy_kj = 300.0
	room.lower_energy_kj = 100.0
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	return room


func _assert_true(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		_failed = true


func _assert_close(
		actual: float,
		expected: float,
		label: String,
		tolerance: float = 1.0e-9
	) -> void:
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		push_error("%s expected %s got %s" % [label, str(expected), str(actual)])
		_failed = true
