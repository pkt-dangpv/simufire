extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const Phase3ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")


func _init() -> void:
	var building = BuildingModelScript.new()
	var source = _make_room(0)
	var destination = _make_room(1)
	building.rooms = {0: source, 1: destination}

	var system = Phase3ZoneMassSystemScript.new()
	system.begin_step(building)
	system.apply_species_transit_event(_created_event("parcel:delivery"))
	system.finalize_step(building)
	var created: Dictionary = system.get_results().get("0", {})
	_assert_close(
		float(created.get("phase3_shadow_parcel_atomic_created_gas_kg_total", -1.0)),
		5.0,
		"accepted gas at carve"
	)
	_assert_close(
		float(created.get("phase3_shadow_parcel_atomic_inflight_gas_kg", -1.0)),
		5.0,
		"in-flight gas after carve"
	)

	system.begin_step(building)
	system.apply_species_transit_event(_resolved_event("parcel:delivery"))
	system.apply_species_transit_event(_resolved_event("parcel:delivery"))
	system.finalize_step(building)
	var resolved: Dictionary = system.get_results().get("0", {})
	_assert_close(
		float(resolved.get("phase3_shadow_parcel_atomic_delivered_gas_kg_total", -1.0)),
		5.0,
		"delivered gas"
	)
	_assert_close(
		float(resolved.get("phase3_shadow_parcel_atomic_mass_residual_kg", -1.0)),
		0.0,
		"delivery mass residual"
	)
	_assert_close(
		float(resolved.get("phase3_shadow_parcel_atomic_energy_residual_kj", -1.0)),
		0.0,
		"delivery energy residual"
	)
	_assert_close(
		float(resolved.get("phase3_shadow_parcel_atomic_o2_residual_kg", -1.0)),
		0.0,
		"delivery O2 residual"
	)
	_assert_close(
		float(resolved.get("phase3_shadow_parcel_atomic_species_residual_kg", -1.0)),
		0.0,
		"delivery species residual"
	)
	_assert_close(
		float(resolved.get("phase3_shadow_species_orphan_delivery_count", -1.0)),
		1.0,
		"duplicate delivery rejection"
	)

	system.begin_step(building)
	system.apply_species_transit_event(_created_event("parcel:cancel"))
	system.finalize_step(building)
	system.begin_step(building)
	system.apply_species_transit_event(_cancelled_event("parcel:cancel"))
	system.finalize_step(building)
	var cancelled: Dictionary = system.get_results().get("0", {})
	_assert_close(
		float(cancelled.get("phase3_shadow_parcel_atomic_cancelled_gas_kg_total", -1.0)),
		5.0,
		"cancelled gas sink"
	)
	_assert_close(
		float(cancelled.get("phase3_shadow_parcel_atomic_mass_residual_kg", -1.0)),
		0.0,
		"cancel mass residual"
	)
	_assert_close(
		float(cancelled.get("phase3_shadow_species_active_parcel_count", -1.0)),
		0.0,
		"active parcels after terminal states"
	)
	_assert_close(
		float(
			cancelled.get(
				"phase3_shadow_parcel_atomic_unfinalized_resolution_count", -1.0
			)
		),
		0.0,
		"unfinalized resolution count"
	)

	building.free()
	print("PHASE3_ATOMIC_PARCEL_RUNTIME_PASS")
	quit(0)


func _make_room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 5.0 if room_id == 0 else 2.0
	room.lower_gas_kg = 20.0
	room.upper_energy_kj = 100.0
	room.lower_energy_kj = 20.0
	room.o2_upper = 0.20
	room.o2_lower = 0.20
	room.smoke_kg = 20.0 if room_id == 0 else 0.0
	room.co_kg = 2.0 if room_id == 0 else 0.0
	room.co_upper_kg = room.co_kg
	room.co2_kg = 4.0 if room_id == 0 else 0.0
	room.co2_upper_kg = room.co2_kg
	room.hcn_kg = 1.0 if room_id == 0 else 0.0
	room.hcn_upper_kg = room.hcn_kg
	room.hcl_kg = 1.0 if room_id == 0 else 0.0
	room.acrolein_kg = 1.0 if room_id == 0 else 0.0
	room.formaldehyde_kg = 1.0 if room_id == 0 else 0.0
	return room


func _created_event(parcel_id: String) -> Dictionary:
	return {
		"event": "created",
		"parcel_id": parcel_id,
		"source_room_id": 0,
		"destination_room_id": 1,
		"connection_id": "opening:0",
		"source_zone": "upper",
		"destination_zone": "upper",
		"gas_mass_kg": 10.0,
		"sensible_enthalpy_kj": 20.0,
		"o2_kg": 0.2,
		"species_kg": _species(),
		"upper_species_kg": _species(),
	}


func _resolved_event(parcel_id: String) -> Dictionary:
	return {
		"event": "resolved",
		"parcel_id": parcel_id,
		"source_room_id": 0,
		"destination_room_id": 1,
		"delivered_species_kg": _species(),
		"refunded_species_kg": {},
		"delivered_upper_species_kg": _species(),
		"refunded_upper_species_kg": {},
	}


func _cancelled_event(parcel_id: String) -> Dictionary:
	return {
		"event": "cancelled",
		"parcel_id": parcel_id,
		"source_room_id": 0,
		"destination_room_id": 1,
		"species_kg": _species(),
		"upper_species_kg": _species(),
	}


func _species() -> Dictionary:
	return {
		"smoke": 2.0,
		"co": 0.2,
		"co2": 0.4,
		"hcn": 0.1,
		"hcl": 0.1,
		"acrolein": 0.1,
		"formaldehyde": 0.1,
	}


func _assert_close(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		push_error("%s: expected %.9f, got %.9f" % [label, expected, actual])
		quit(1)
