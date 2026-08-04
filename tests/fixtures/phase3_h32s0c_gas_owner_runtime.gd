extends SceneTree

## H3.2-S0c runtime census: drives the real GasExchangeSystem entry points over
## several steps on a building with an exterior window, a PPV opening and an
## interior door. It proves that every instrumented gas family fires from a real
## legacy mutation, that parcels are created once and delivered once, and that
## no event is emitted twice for the same physical movement.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

const EPS: float = 1.0e-12
const STEPS: int = 12
const DT: float = 1.0

var _failed: bool = false
var _owner_counts: Dictionary = {}
var _class_counts: Dictionary = {}
var _seen_ids: Dictionary = {}
var _parcel_lifecycles: Dictionary = {}
var _max_transport_mass_residual_kg: float = 0.0
var _max_transport_energy_residual_kj: float = 0.0
var _max_refund_residual_kg: float = 0.0
var _invalid_total: int = 0
var _duplicate_total: int = 0
var _duplicate_id_collisions: int = 0


func _init() -> void:
	var building = _build()
	var smoke_model = SmokeModelScript.new()
	var thermal = ThermalSystemScript.new()
	thermal.set_references(building, smoke_model)
	var gas = GasExchangeSystemScript.new()
	gas.phase3_physical_owner_ledger_enabled = true
	var hooks: Dictionary = {
		"remove_upper_layer_fraction_callable": Callable(
			thermal, "remove_upper_layer_fraction"
		),
		"compute_interroom_transfer_temp_callable": Callable(
			thermal, "compute_interroom_transfer_temp_c"
		),
		"opening_flow_cache": {},
	}

	for step_index in range(STEPS):
		_reseed(building)
		gas.begin_phase3_physical_owner_step()
		gas.step_pressure_venting(building, DT, hooks)
		gas.step_ppv(building, DT, hooks)
		gas.step_smoke(building, smoke_model, DT, hooks)
		_collect(gas, step_index)

	_expect(_invalid_total == 0, "no invalid event across the run")
	_expect(_duplicate_total == 0, "no duplicate event across the run")
	_expect(_duplicate_id_collisions == 0, "event ids unique across the run")
	_expect(
		_max_transport_mass_residual_kg <= EPS,
		"interior transport mass closes every step"
	)
	_expect(
		_max_transport_energy_residual_kj <= EPS,
		"interior transport energy closes every step"
	)
	_expect(_max_refund_residual_kg <= EPS, "parcel refunds conserve every step")

	for owner in [
		"gas_pressure_vent_upper_removal",
		"gas_ppv_inlet_upper_removal",
		"gas_ppv_exhaust_upper_removal",
		"gas_exterior_smoke_vent_upper_removal",
		"gas_background_upper_transport",
		"gas_delayed_parcel_upper",
	]:
		_expect(int(_owner_counts.get(owner, 0)) > 0, "owner fired: %s" % owner)

	var created: int = 0
	var delivered: int = 0
	for parcel_id in _parcel_lifecycles.keys():
		var lifecycles: Dictionary = _parcel_lifecycles[parcel_id]
		created += int(lifecycles.get("created", 0))
		delivered += int(lifecycles.get("delivered", 0))
		_expect(
			int(lifecycles.get("created", 0)) <= 1,
			"parcel created at most once: %s" % parcel_id
		)
		_expect(
			int(lifecycles.get("delivered", 0)) <= 1,
			"parcel delivered at most once: %s" % parcel_id
		)
	_expect(created > 0, "at least one parcel created")
	_expect(delivered > 0, "at least one parcel delivered")
	var inflight: int = int(gas.get_phase3_runtime_parcel_inventory()["count"])
	_expect(
		created - delivered == inflight,
		"created minus delivered equals in-flight inventory"
	)

	print("H3.2-S0c owner census: %s" % JSON.stringify(_owner_counts))
	print("H3.2-S0c class census: %s" % JSON.stringify(_class_counts))
	print(
		"H3.2-S0c parcels: created=%d delivered=%d inflight=%d" % [
			created, delivered, inflight
		]
	)

	building.free()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0C_GAS_OWNER_RUNTIME_PASS")
	quit(0)


func _collect(gas, step_index: int) -> void:
	var events: Array = gas.get_phase3_physical_owner_events()
	var step_ids: Dictionary = {}
	for raw_event in events:
		var event: Dictionary = raw_event
		var event_id: String = String(event["event_id"])
		if step_ids.has(event_id):
			_duplicate_id_collisions += 1
		step_ids[event_id] = true
		var global_id: String = "%d|%s" % [step_index, event_id]
		if _seen_ids.has(global_id):
			_duplicate_id_collisions += 1
		_seen_ids[global_id] = true
		var owner: String = String(event["owner"])
		_owner_counts[owner] = int(_owner_counts.get(owner, 0)) + 1
		var classification: String = String(event["classification"])
		_class_counts[classification] = int(_class_counts.get(classification, 0)) + 1
		if classification == "exterior_boundary":
			_expect(
				int(event["destination_room_id"]) == -1
						and int(event["source_room_id"]) == int(event["room_id"]),
				"exterior event declares an explicit direction"
			)
			_expect(
				float(event["upper_mass_delta_kg"]) <= EPS
						and float(event["upper_energy_delta_kj"]) <= EPS,
				"exterior removal is signed as an outflow"
			)
		if classification == "interior_transport":
			_max_transport_mass_residual_kg = maxf(
				_max_transport_mass_residual_kg,
				absf(float(event["upper_mass_delta_kg"])
						+ float(event["lower_mass_delta_kg"])
						+ float(event["counterparty_mass_delta_kg"]))
			)
			_max_transport_energy_residual_kj = maxf(
				_max_transport_energy_residual_kj,
				absf(float(event["upper_energy_delta_kj"])
						+ float(event["lower_energy_delta_kj"])
						+ float(event["counterparty_energy_delta_kj"]))
			)
		if classification == "delayed_parcel":
			var metadata: Dictionary = event["metadata"]
			var parcel_id: String = String(metadata["parcel_id"])
			var lifecycle: String = String(metadata["lifecycle"])
			if not _parcel_lifecycles.has(parcel_id):
				_parcel_lifecycles[parcel_id] = {}
			var lifecycles: Dictionary = _parcel_lifecycles[parcel_id]
			lifecycles[lifecycle] = int(lifecycles.get(lifecycle, 0)) + 1
			_parcel_lifecycles[parcel_id] = lifecycles

	var summary: Dictionary = gas.get_phase3_physical_owner_summary()
	_invalid_total += int(summary["invalid_event_count"])
	_duplicate_total += int(summary["duplicate_event_count"])
	_expect(bool(summary["valid"]), "step aggregate valid at step %d" % step_index)
	var diagnostics: Dictionary = summary["gas_owner_diagnostics"]
	_max_refund_residual_kg = maxf(
		_max_refund_residual_kg,
		float(diagnostics["parcel_refund_max_residual_kg"])
	)


func _reseed(building) -> void:
	## El fixture repone la capa superior porque ThermalSystem.step() no corre
	## aqui. Es estado inicial de escenario, no una correccion del ledger.
	var source: RoomModel = building.get_room(0)
	source.upper_gas_kg = 6.0
	source.upper_energy_kj = 1400.0
	source.smoke_kg = maxf(source.smoke_kg, 30.0)
	source.co_kg = maxf(source.co_kg, 0.8)
	source.co_upper_kg = minf(source.co_kg, 0.8)
	source.co2_kg = maxf(source.co2_kg, 2.0)
	source.co2_upper_kg = minf(source.co2_kg, 2.0)
	source.overpressure_pa = 25.0
	var target: RoomModel = building.get_room(1)
	target.upper_gas_kg = maxf(target.upper_gas_kg, 0.4)
	target.upper_energy_kj = maxf(target.upper_energy_kj, 10.0)
	# Receptor ya saturado en CO: fuerza un refund real en la entrega diferida.
	target.co_kg = maxf(target.co_kg, 3.0)
	target.co_upper_kg = minf(target.co_kg, 3.0)


func _build():
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var source = _room(0, 420.0)
	var target = _room(1, 30.0)
	building.rooms = {0: source, 1: target}

	var door = OpeningModelScript.new(0, 1, OpeningModelScript.Type.DOOR, 0.9, 2.0, 1.0, 0.0)
	door.opening_index = 0
	door.open_fraction_smooth = 1.0
	var window = OpeningModelScript.new(
		0, BuildingModelScript.OUTSIDE_ID, OpeningModelScript.Type.WINDOW, 1.0, 1.2, 1.0, 0.9
	)
	window.opening_index = 1
	window.open_fraction_smooth = 1.0
	window.wall_side = "left"
	var ppv = OpeningModelScript.new(
		0, BuildingModelScript.OUTSIDE_ID, OpeningModelScript.Type.DOOR, 0.9, 2.0, 1.0, 0.0
	)
	ppv.opening_index = 2
	ppv.open_fraction_smooth = 1.0
	ppv.wall_side = "right"
	ppv.ppv_flow_m3_s = 2.0
	ppv.ppv_delta_p_pa = 20.0
	building.openings = [door, window, ppv]
	return building


func _room(room_id: int, temp_upper_c: float):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.6
	room.temp_upper_c = temp_upper_c
	room.temp_lower_c = 22.0
	room.upper_gas_kg = 6.0 if room_id == 0 else 0.4
	room.lower_gas_kg = 50.0
	room.upper_energy_kj = 1400.0 if room_id == 0 else 10.0
	room.lower_energy_kj = 40.0
	room.smoke_kg = 30.0 if room_id == 0 else 0.0
	room.o2 = 0.209
	room.o2_upper = 0.209
	room.o2_lower = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0c RUNTIME ASSERTION FAILED: %s" % label)
