extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SurfaceSolverScript = preload("res://sim/core/Phase3SurfaceEnergySolver.gd")
const ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

const EPSILON: float = 1.0e-7

var _failed: bool = false


func _init() -> void:
	_test_default_off_is_inert()
	_test_seeded_geometry_and_zero_area_edges()
	_test_full_atomic_acceptance_routes_radiation_once()
	_test_partial_atomic_acceptance_scales_radiation()
	_test_atomic_rejection_keeps_surfaces_unchanged()
	_test_interface_migration_conserves_surface_energy()
	_test_lumped_wall_path_is_mutually_exclusive()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33R2B_MULTISURFACE_TRANSACTION_PASS")
	quit(0)


func _test_default_off_is_inert() -> void:
	var setup: Dictionary = _make_setup(0.209)
	var ledger = ZoneMassSystemScript.new()
	ledger.begin_step(setup["building"], true)
	var prepared: Dictionary = ledger.prepare_canonical_multisurface_room(
		0, _geometry(1.25), _material(), 20.0
	)
	_assert_true(not bool(prepared.get("valid", true)), "default OFF prepare")
	_assert_true(
		ledger.get_canonical_multisurface_state(0).is_empty(),
		"default OFF persistent state"
	)
	_free_setup(setup)


func _test_seeded_geometry_and_zero_area_edges() -> void:
	var setup: Dictionary = _make_setup(0.209)
	var ledger = _make_enabled_ledger(setup["building"])
	var prepared: Dictionary = ledger.prepare_canonical_multisurface_room(
		0, _geometry(1.25), _material(), 20.0
	)
	_assert_true(bool(prepared.get("valid", false)), "seed valid")
	var state: Dictionary = ledger.get_canonical_multisurface_state(0)
	var surfaces: Dictionary = state.get("surfaces", {})
	_assert_close(_area(surfaces, "ceiling"), 16.0, "ceiling area")
	_assert_close(_area(surfaces, "floor"), 16.0, "floor area")
	_assert_close(_area(surfaces, "upper_wall"), 20.0, "upper wall area")
	_assert_close(_area(surfaces, "lower_wall"), 20.0, "lower wall area")
	_assert_close(_surface_energy(state), 0.0, "seed energy")

	ledger.begin_step(setup["building"], true)
	var edge: Dictionary = ledger.prepare_canonical_multisurface_room(
		0, _geometry(0.0), _material(), 20.0
	)
	_assert_true(bool(edge.get("valid", false)), "zero-area edge migration")
	state = ledger.get_canonical_multisurface_state(0)
	_assert_close(
		_area(state.get("surfaces", {}), "lower_wall"),
		0.0,
		"zero lower-wall area"
	)
	_free_setup(setup)


func _test_full_atomic_acceptance_routes_radiation_once() -> void:
	var setup: Dictionary = _make_setup(0.209)
	var ledger = _make_enabled_ledger(setup["building"])
	_assert_prepared(ledger, 1.25, "full acceptance prepare")
	_assert_true(
		ledger.stage_canonical_combustion_transaction(
			_transaction(0.0, 5.0, 100.0)
		),
		"full acceptance stage"
	)
	_assert_true(
		ledger.finalize_canonical_combustion_bundle(
			0,
			{"sensible_enthalpy_kj": 70.0},
			{},
			"f33r2b-full"
		),
		"full acceptance bundle"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var result: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		_value(result, "phase3_shadow_combustion_atomic_fraction"),
		1.0,
		"full atomic fraction"
	)
	_assert_close(
		_value(result, "phase3_shadow_combustion_accepted_radiative_energy_kj"),
		30.0,
		"full accepted radiation"
	)
	_assert_close(
		_value(result, "phase3_shadow_combustion_routed_surface_radiation_kj"),
		30.0,
		"full routed radiation"
	)
	_assert_close(
		_value(result, "phase3_shadow_multisurface_radiation_residual_kj"),
		0.0,
		"full radiation residual"
	)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		30.0,
		"full surface storage"
	)
	var energy_before_duplicate: float = _surface_energy(
		ledger.get_canonical_multisurface_state(0)
	)
	_assert_true(
		not ledger.commit_canonical_multisurface_combustion_radiation(0),
		"duplicate commit rejected"
	)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		energy_before_duplicate,
		"duplicate commit energy invariant"
	)
	_assert_close(
		float(
			ledger.get_canonical_multisurface_record(0).get(
				"duplicate_commit_count", 0.0
			)
		),
		1.0,
		"duplicate commit telemetry"
	)
	_free_setup(setup)


func _test_partial_atomic_acceptance_scales_radiation() -> void:
	var setup: Dictionary = _make_setup(0.1)
	var ledger = _make_enabled_ledger(setup["building"])
	_assert_prepared(ledger, 1.25, "partial acceptance prepare")
	_assert_true(
		ledger.stage_canonical_combustion_transaction(
			_transaction(2.0, 5.0, 100.0)
		),
		"partial acceptance stage"
	)
	_assert_true(
		ledger.finalize_canonical_combustion_bundle(
			0,
			{"sensible_enthalpy_kj": 70.0},
			{},
			"f33r2b-partial"
		),
		"partial acceptance bundle"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var result: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		_value(result, "phase3_shadow_combustion_atomic_fraction"),
		0.5,
		"partial atomic fraction"
	)
	_assert_close(
		_value(result, "phase3_shadow_combustion_accepted_radiative_energy_kj"),
		15.0,
		"partial accepted radiation"
	)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		15.0,
		"partial surface storage"
	)
	_free_setup(setup)


func _test_atomic_rejection_keeps_surfaces_unchanged() -> void:
	var setup: Dictionary = _make_setup(0.0)
	var ledger = _make_enabled_ledger(setup["building"])
	_assert_prepared(ledger, 1.25, "rejection prepare")
	_assert_true(
		ledger.stage_canonical_combustion_transaction(
			_transaction(1.0, 30.0, 100.0)
		),
		"rejection stage"
	)
	_assert_true(
		ledger.finalize_canonical_combustion_bundle(
			0,
			{"sensible_enthalpy_kj": 70.0},
			{},
			"f33r2b-reject"
		),
		"rejection bundle"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var result: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		_value(result, "phase3_shadow_combustion_atomic_fraction"),
		0.0,
		"rejected atomic fraction"
	)
	_assert_close(
		_value(result, "phase3_shadow_combustion_accepted_radiative_energy_kj"),
		0.0,
		"rejected radiation"
	)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		0.0,
		"rejected surface storage"
	)
	_free_setup(setup)


func _test_interface_migration_conserves_surface_energy() -> void:
	var setup: Dictionary = _make_setup(0.209)
	var ledger = _make_enabled_ledger(setup["building"])
	_assert_prepared(ledger, 1.25, "migration prepare")
	_assert_true(
		ledger.stage_canonical_combustion_transaction(
			_transaction(0.0, 30.0, 100.0)
		),
		"migration radiation stage"
	)
	_assert_true(
		ledger.finalize_canonical_combustion_bundle(
			0,
			{"sensible_enthalpy_kj": 70.0},
			{},
			"f33r2b-migration"
		),
		"migration radiation bundle"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var energy_before: float = _surface_energy(
		ledger.get_canonical_multisurface_state(0)
	)

	ledger.begin_step(setup["building"], true)
	var downward: Dictionary = ledger.prepare_canonical_multisurface_room(
		0, _geometry(0.75), _material(), 20.0
	)
	_assert_true(bool(downward.get("valid", false)), "downward migration valid")
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		energy_before,
		"downward migration energy"
	)
	_assert_close(
		float(downward.get("migration_residual_kj", 0.0)),
		0.0,
		"downward migration residual"
	)

	ledger.begin_step(setup["building"], true)
	var upward: Dictionary = ledger.prepare_canonical_multisurface_room(
		0, _geometry(1.5), _material(), 20.0
	)
	_assert_true(bool(upward.get("valid", false)), "upward migration valid")
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		energy_before,
		"upward migration energy"
	)
	_assert_close(
		float(upward.get("migration_residual_kj", 0.0)),
		0.0,
		"upward migration residual"
	)
	_free_setup(setup)


func _test_lumped_wall_path_is_mutually_exclusive() -> void:
	var setup: Dictionary = _make_setup(0.209)
	var ledger = _make_enabled_ledger(setup["building"])
	var queued: bool = ledger.queue_canonical_wall_ambient_transfer(
		0,
		{"valid": true},
		{},
		"f33r2b-wall-conflict"
	)
	_assert_true(not queued, "lumped wall path rejected")
	_free_setup(setup)


func _make_enabled_ledger(building) -> Phase3ZoneMassSystem:
	var ledger = ZoneMassSystemScript.new()
	ledger.configure_canonical_multisurface_shadow(true)
	ledger.begin_step(building, true)
	return ledger


func _make_setup(upper_o2: float) -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 38.0
	room.upper_energy_kj = 900.0
	room.lower_energy_kj = 0.0
	room.o2_upper = upper_o2
	room.o2_lower = 0.209
	room.o2 = upper_o2
	building.rooms = {0: room}
	return {"building": building, "room": room}


func _geometry(interface_m: float) -> Dictionary:
	return {
		"floor_area_m2": 16.0,
		"perimeter_m": 16.0,
		"height_m": 2.5,
		"interface_m": interface_m,
	}


func _material() -> Dictionary:
	return {
		"conductivity_kw_m_k": 0.00175,
		"density_kg_m3": 2200.0,
		"cp_kj_kg_k": 1.0,
		"thickness_m": 0.15,
		"emissivity": 0.9,
	}


func _transaction(
		accepted_o2_kg: float,
		accepted_radiation_kj: float,
		accepted_total_fire_energy_kj: float
	) -> Dictionary:
	return {
		"room_id": 0,
		"decision_fraction": 1.0,
		"heat_scale": 1.0,
		"plume_scale": 0.0,
		"accepted_o2_kg": accepted_o2_kg,
		"o2_source_zone": "upper",
		"accepted_species_kg": {},
		"requested_radiative_energy_kj": accepted_radiation_kj,
		"accepted_radiative_energy_kj": accepted_radiation_kj,
		"accepted_total_fire_energy_kj": accepted_total_fire_energy_kj,
		"dt_s": 1.0,
		"fire_state_proposed": {},
	}


func _assert_prepared(
		ledger: Phase3ZoneMassSystem,
		interface_m: float,
		label: String
	) -> void:
	var prepared: Dictionary = ledger.prepare_canonical_multisurface_room(
		0, _geometry(interface_m), _material(), 20.0
	)
	_assert_true(bool(prepared.get("valid", false)), label)


func _surface_energy(state: Dictionary) -> float:
	var total_kj: float = 0.0
	var surfaces: Dictionary = state.get("surfaces", {})
	for surface_name in ["ceiling", "upper_wall", "lower_wall", "floor"]:
		total_kj += SurfaceSolverScript.stored_energy_kj(
			surfaces.get(surface_name, {})
		)
	return total_kj


func _area(surfaces: Dictionary, surface_name: String) -> float:
	return float(surfaces.get(surface_name, {}).get("area_m2", -1.0))


func _value(result: Dictionary, field_name: String) -> float:
	return float(result.get(field_name, 0.0))


func _free_setup(setup: Dictionary) -> void:
	var building = setup.get("building")
	if building != null:
		building.free()


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label)


func _assert_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > EPSILON * maxf(1.0, absf(expected)):
		_fail("%s expected %s got %s" % [label, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
