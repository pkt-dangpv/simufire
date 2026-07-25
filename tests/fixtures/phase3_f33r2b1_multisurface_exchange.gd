extends SceneTree

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SurfaceSolverScript = preload("res://sim/core/Phase3SurfaceEnergySolver.gd")
const ZoneMassSystemScript = preload("res://sim/core/Phase3ZoneMassSystem.gd")

const EPSILON: float = 1.0e-7

var _failed: bool = false


func _init() -> void:
	_test_default_off_fails_closed()
	_test_preview_is_adiabatic_without_topology()
	_test_full_gas_to_surface_exchange()
	_test_partial_and_rejected_atomic_exchange()
	_test_surface_to_gas_signed_exchange()
	_test_explicit_exterior_loss_closes_combined_ledger()
	_test_correspondence_ledger_accumulates_and_resets()
	if _failed:
		quit(1)
		return
	print("PHASE3_F33R2B1_MULTISURFACE_EXCHANGE_PASS")
	quit(0)


func _test_default_off_fails_closed() -> void:
	var setup: Dictionary = _make_setup(100.0)
	var ledger = ZoneMassSystemScript.new()
	ledger.begin_step(setup["building"], true)
	var preview: Dictionary = ledger.preview_canonical_multisurface_exchange(
		0, _context()
	)
	_assert_true(not bool(preview.get("valid", true)), "default OFF preview")
	_assert_true(
		not ledger.queue_canonical_multisurface_exchange(
			0, {"valid": true}, "off"
		),
		"default OFF queue"
	)
	_free_setup(setup)


func _test_preview_is_adiabatic_without_topology() -> void:
	var setup: Dictionary = _make_setup(100.0)
	var ledger = _make_ledger(setup["building"])
	_assert_prepared(ledger)
	var preview: Dictionary = ledger.preview_canonical_multisurface_exchange(
		0, _context()
	)
	_assert_true(bool(preview.get("valid", false)), "adiabatic preview")
	_assert_close(
		float(preview.get("boundary_metadata_complete_flag", -1.0)),
		0.0,
		"missing boundary metadata visible"
	)
	_assert_close(
		float(preview.get("adiabatic_surface_count", -1.0)),
		4.0,
		"all surfaces adiabatic"
	)
	_assert_close(
		float(preview.get("exterior_removed_requested_kj", -1.0)),
		0.0,
		"missing topology has no exterior loss"
	)
	var radiative_context: Dictionary = _context()
	radiative_context["upper_gas_emissivity"] = 0.8
	var radiative: Dictionary = ledger.preview_canonical_multisurface_exchange(
		0, radiative_context
	)
	var upper_radiation_kj: float = 0.0
	for surface_name in ["ceiling", "upper_wall"]:
		upper_radiation_kj += float(
			radiative.get("surface_fluxes", {}).get(
				surface_name, {}
			).get("gas_radiation_requested_kj", 0.0)
		)
	_assert_true(upper_radiation_kj > 0.0, "hot-gas radiation is explicit")
	_free_setup(setup)


func _test_full_gas_to_surface_exchange() -> void:
	var setup: Dictionary = _make_setup(900.0)
	var ledger = _make_ledger(setup["building"])
	_assert_prepared(ledger)
	var preview: Dictionary = ledger.preview_canonical_multisurface_exchange(
		0, _context()
	)
	var requested_kj: float = (
		float(preview.get("upper_exchange_requested_kj", 0.0))
		+ float(preview.get("lower_exchange_requested_kj", 0.0))
	)
	_assert_true(requested_kj > 0.0, "hot gas requests surface heating")
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(0, preview, "full"),
		"full exchange queued"
	)
	_assert_true(
		not ledger.queue_canonical_multisurface_exchange(0, preview, "duplicate"),
		"duplicate exchange queue rejected"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var exchange: Dictionary = ledger.get_canonical_multisurface_exchange_record(0)
	_assert_close(
		float(exchange.get("accepted_fraction", 0.0)),
		1.0,
		"full exchange fraction"
	)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		requested_kj,
		"full exchange surface storage"
	)
	_assert_close(
		float(exchange.get("combined_energy_residual_kj", 1.0)),
		0.0,
		"full combined residual"
	)
	_free_setup(setup)


func _test_partial_and_rejected_atomic_exchange() -> void:
	var partial_setup: Dictionary = _make_setup(50.0)
	var partial = _make_ledger(partial_setup["building"])
	_assert_prepared(partial)
	var request: Dictionary = _manual_upper_request(100.0)
	_assert_true(
		partial.queue_canonical_multisurface_exchange(0, request, "partial"),
		"partial exchange queued"
	)
	partial.finalize_step(partial_setup["building"], 20.0)
	var partial_exchange: Dictionary = \
			partial.get_canonical_multisurface_exchange_record(0)
	_assert_close(
		float(partial_exchange.get("accepted_fraction", 0.0)),
		0.5,
		"partial fraction"
	)
	_assert_close(
		_surface_energy(partial.get_canonical_multisurface_state(0)),
		50.0,
		"partial surface storage"
	)
	_assert_close(
		float(partial_exchange.get("combined_energy_residual_kj", 1.0)),
		0.0,
		"partial combined residual"
	)
	_free_setup(partial_setup)

	var rejected_setup: Dictionary = _make_setup(0.0)
	var rejected = _make_ledger(rejected_setup["building"])
	_assert_prepared(rejected)
	_assert_true(
		rejected.queue_canonical_multisurface_exchange(
			0, _manual_upper_request(100.0), "rejected"
		),
		"rejected exchange queued"
	)
	rejected.finalize_step(rejected_setup["building"], 20.0)
	var rejected_exchange: Dictionary = \
			rejected.get_canonical_multisurface_exchange_record(0)
	_assert_close(
		float(rejected_exchange.get("accepted_fraction", 1.0)),
		0.0,
		"rejected fraction"
	)
	_assert_close(
		_surface_energy(rejected.get_canonical_multisurface_state(0)),
		0.0,
		"rejected surface storage"
	)
	_free_setup(rejected_setup)


func _test_surface_to_gas_signed_exchange() -> void:
	var setup: Dictionary = _make_setup(100.0)
	var ledger = _make_ledger(setup["building"])
	_assert_prepared(ledger)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(
			0, _manual_upper_request(100.0), "preheat"
		),
		"surface preheat queued"
	)
	ledger.finalize_step(setup["building"], 20.0)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		100.0,
		"surface preheated"
	)

	ledger.begin_step(setup["building"], true)
	_assert_prepared(ledger)
	var release: Dictionary = _manual_upper_request(-40.0)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(0, release, "release"),
		"surface release queued"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var exchange: Dictionary = ledger.get_canonical_multisurface_exchange_record(0)
	_assert_close(
		_surface_energy(ledger.get_canonical_multisurface_state(0)),
		60.0,
		"surface release storage"
	)
	_assert_close(
		float(exchange.get("combined_energy_residual_kj", 1.0)),
		0.0,
		"surface release residual"
	)
	_free_setup(setup)


func _test_explicit_exterior_loss_closes_combined_ledger() -> void:
	var setup: Dictionary = _make_setup(0.0)
	var ledger = _make_ledger(setup["building"])
	_assert_prepared(ledger)
	var exterior: Dictionary = {}
	for surface_name in ["ceiling", "upper_wall", "lower_wall", "floor"]:
		exterior[surface_name] = {
			"exterior_h_kw_m2_k": 0.01,
			"exterior_temp_c": 0.0,
		}
	var context: Dictionary = _context()
	context["upper_h_kw_m2_k"] = 0.0
	context["lower_h_kw_m2_k"] = 0.0
	context["upper_temp_c"] = 20.0
	context["lower_temp_c"] = 20.0
	context["exterior_by_surface"] = exterior
	var preview: Dictionary = ledger.preview_canonical_multisurface_exchange(
		0, context
	)
	_assert_true(bool(preview.get("valid", false)), "explicit exterior preview")
	_assert_close(
		float(preview.get("boundary_metadata_complete_flag", 0.0)),
		1.0,
		"explicit boundary complete"
	)
	_assert_true(
		float(preview.get("exterior_removed_requested_kj", 0.0)) > 0.0,
		"explicit exterior removes energy"
	)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(0, preview, "exterior"),
		"explicit exterior queued"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var exchange: Dictionary = ledger.get_canonical_multisurface_exchange_record(0)
	_assert_close(
		float(exchange.get("accepted_fraction", 0.0)),
		1.0,
		"exterior no-route acceptance"
	)
	_assert_close(
		float(exchange.get("combined_energy_residual_kj", 1.0)),
		0.0,
		"exterior combined residual"
	)
	_free_setup(setup)


func _test_correspondence_ledger_accumulates_and_resets() -> void:
	var setup: Dictionary = _make_setup(200.0)
	var ledger = _make_ledger(setup["building"])
	_assert_prepared(ledger)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(
			0, _manual_upper_request(25.0), "cumulative-1"
		),
		"cumulative step 1 queued"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var step_1: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		float(step_1.get(
			"phase3_shadow_multisurface_cumulative_gas_exchange_kj", 0.0
		)),
		25.0,
		"cumulative step 1 gas"
	)
	_assert_close(
		float(step_1.get(
			"phase3_shadow_multisurface_ceiling_cumulative_gas_exchange_kj",
			0.0
		)),
		25.0,
		"cumulative step 1 ceiling"
	)

	ledger.begin_step(setup["building"], true)
	_assert_prepared(ledger)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(
			0, _manual_upper_request(15.0), "cumulative-2"
		),
		"cumulative step 2 queued"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var step_2: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		float(step_2.get(
			"phase3_shadow_multisurface_cumulative_gas_exchange_kj", 0.0
		)),
		40.0,
		"cumulative step 2 gas"
	)
	_assert_close(
		float(step_2.get(
			"phase3_shadow_multisurface_cumulative_step_count", 0.0
		)),
		2.0,
		"cumulative step count"
	)
	_assert_close(
		float(step_2.get(
			"phase3_shadow_multisurface_cumulative_energy_residual_kj", 1.0
		)),
		0.0,
		"cumulative residual"
	)

	ledger.reset()
	ledger.configure_canonical_multisurface_shadow(true)
	ledger.begin_step(setup["building"], true)
	_assert_prepared(ledger)
	_assert_true(
		ledger.queue_canonical_multisurface_exchange(
			0, _manual_upper_request(5.0), "after-reset"
		),
		"post-reset step queued"
	)
	ledger.finalize_step(setup["building"], 20.0)
	var post_reset: Dictionary = ledger.get_results().get("0", {})
	_assert_close(
		float(post_reset.get(
			"phase3_shadow_multisurface_cumulative_gas_exchange_kj", 0.0
		)),
		5.0,
		"post-reset cumulative gas"
	)
	_assert_close(
		float(post_reset.get(
			"phase3_shadow_multisurface_cumulative_step_count", 0.0
		)),
		1.0,
		"post-reset step count"
	)
	_free_setup(setup)


func _make_setup(upper_energy_kj: float) -> Dictionary:
	var building = BuildingModelScript.new()
	var room = RoomModelScript.new()
	room.id = 0
	room.width_m = 4.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.upper_gas_kg = 10.0
	room.lower_gas_kg = 38.0
	room.upper_energy_kj = upper_energy_kj
	room.lower_energy_kj = 0.0
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	room.o2 = 0.209
	building.rooms = {0: room}
	return {"building": building}


func _make_ledger(building) -> Phase3ZoneMassSystem:
	var ledger = ZoneMassSystemScript.new()
	ledger.configure_canonical_multisurface_shadow(true)
	ledger.begin_step(building, true)
	return ledger


func _assert_prepared(ledger: Phase3ZoneMassSystem) -> void:
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
		20.0
	)
	_assert_true(bool(prepared.get("valid", false)), "surface prepare")


func _context() -> Dictionary:
	return {
		"dt_s": 1.0,
		"upper_temp_c": 110.0,
		"lower_temp_c": 20.0,
		"upper_h_kw_m2_k": 0.025,
		"lower_h_kw_m2_k": 0.025,
		"upper_gas_emissivity": 0.0,
		"lower_gas_emissivity": 0.0,
		"exterior_by_surface": {},
	}


func _manual_upper_request(requested_kj: float) -> Dictionary:
	return {
		"valid": true,
		"dt_s": 1.0,
		"upper_exchange_requested_kj": requested_kj,
		"lower_exchange_requested_kj": 0.0,
		"exterior_removed_requested_kj": 0.0,
		"surface_fluxes": {
			"ceiling": {
				"zone": "upper",
				"convection_requested_kj": requested_kj,
				"gas_radiation_requested_kj": 0.0,
				"exterior_removed_requested_kj": 0.0,
			},
		},
		"boundary_metadata_complete_flag": 0.0,
		"adiabatic_surface_count": 4.0,
	}


func _surface_energy(state: Dictionary) -> float:
	var total_kj: float = 0.0
	for surface in state.get("surfaces", {}).values():
		total_kj += SurfaceSolverScript.stored_energy_kj(surface)
	return total_kj


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
