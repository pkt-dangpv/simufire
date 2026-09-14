extends SceneTree

const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

var _failed: bool = false


class FakeBuilding:
	extends RefCounted
	var rooms: Dictionary = {}

	func get_rooms() -> Dictionary:
		return rooms

	func get_room(room_id: int):
		return rooms.get(room_id)


func _init() -> void:
	_check_conversion_and_unknown_contract()
	_check_persistent_lower_mass_basis()
	_check_atomic_o2_conservation()
	if _failed:
		quit(1)
		return
	print("P1R3_ZONAL_O2_MASS_MIGRATION_PASS")
	quit(0)


func _check_conversion_and_unknown_contract() -> void:
	var system = ZoneMassSystemScript.new()
	var room = _room(7, 2.0, 7.0, 0.18, 0.209)
	var legacy: Dictionary = system._snapshot_room(room)
	_assert(
		is_equal_approx(float(legacy["upper_o2_kg"]), 0.36),
		"default OFF is legacy-identical"
	)
	system.configure_o2_zonal_mass_shadow(true)
	var migrated: Dictionary = system._snapshot_room(room)
	var expected_mass: float = 2.0 * 0.18 * 31.999 / 28.9647
	_assert(
		is_equal_approx(float(migrated["upper_o2_kg"]), expected_mass),
		"molar-to-mass conversion"
	)
	var view: Dictionary = system._o2_mass_kg_to_molar_view(expected_mass, 2.0)
	_assert(bool(view.get("known", false)), "mass-to-molar view is known")
	_assert(
		is_equal_approx(float(view.get("molar_fraction", -1.0)), 0.18),
		"mass-to-molar round trip"
	)
	var absent: Dictionary = system._o2_mass_kg_to_molar_view(0.0, 0.0)
	_assert(not bool(absent.get("known", true)), "absent zone is unknown")
	_assert(
		String(absent.get("reason", "")) == "zone_gas_mass_absent",
		"absent zone has a reason"
	)


func _check_persistent_lower_mass_basis() -> void:
	var system = ZoneMassSystemScript.new()
	system.configure_o2_zonal_mass_shadow(true)
	var room = _room(9, 2.0, 7.0, 0.18, 0.209)
	var building = FakeBuilding.new()
	building.rooms[room.id] = room
	system.begin_step(building, true)
	system.finalize_step(building)
	room.lower_gas_kg = 99.0
	system.begin_step(building, true)
	var canonical: Dictionary = system.get_canonical_combustion_input(room.id)
	_assert(
		is_equal_approx(float(canonical.get("lower_gas_kg", -1.0)), 7.0),
		"persistent lower mass ignores legacy rewrite"
	)


func _check_atomic_o2_conservation() -> void:
	var system = ZoneMassSystemScript.new()
	var shadow: Dictionary = {
		"0": _state(2.0, 1.0, 0.4, 0.2),
		"1": _state(1.0, 1.0, 0.2, 0.2),
	}
	var route: Dictionary = system.make_atomic_route(
		"p1r3:o2", "p1r3_fixture", 0, 1, "upper", "lower",
		0.5, 0.0, 0.1, {}
	)
	var bundle: Dictionary = system.make_atomic_bundle(
		"p1r3:bundle", "p1r3_fixture", [route], {}
	)
	var before_o2: float = _total_o2(shadow)
	var rejected: Dictionary = {}
	system._apply_atomic_bundle(shadow, bundle, rejected, {}, {})
	_assert(
		is_equal_approx(_total_o2(shadow), before_o2),
		"atomic O2 transfer conserves mass"
	)
	_assert(system.add_atomic_bundle(bundle), "first bundle is accepted")
	_assert(not system.add_atomic_bundle(bundle), "duplicate bundle is rejected")


func _room(
		room_id: int, upper_gas_kg: float, lower_gas_kg: float,
		upper_o2: float, lower_o2: float
	):
	var room = RoomModelScript.new()
	room.id = room_id
	room.upper_gas_kg = upper_gas_kg
	room.lower_gas_kg = lower_gas_kg
	room.upper_energy_kj = 20.0
	room.lower_energy_kj = 70.0
	room.o2_upper = upper_o2
	room.o2_lower = lower_o2
	return room


func _state(
		upper_gas_kg: float, lower_gas_kg: float,
		upper_o2_kg: float, lower_o2_kg: float
	) -> Dictionary:
	return {
		"upper_gas_kg": upper_gas_kg,
		"lower_gas_kg": lower_gas_kg,
		"upper_energy_kj": 0.0,
		"lower_energy_kj": 0.0,
		"upper_o2_kg": upper_o2_kg,
		"lower_o2_kg": lower_o2_kg,
		"upper_species_kg": {},
		"lower_species_kg": {},
	}


func _total_o2(shadow: Dictionary) -> float:
	var total: float = 0.0
	for state in shadow.values():
		total += float(state.get("upper_o2_kg", 0.0))
		total += float(state.get("lower_o2_kg", 0.0))
	return total


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("P1R3 zonal O2 mass migration: " + message)
