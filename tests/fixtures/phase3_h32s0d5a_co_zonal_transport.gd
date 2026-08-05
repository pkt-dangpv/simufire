extends SceneTree

## H3.2-S0d5a fixture: experimental CO zonal transport consistency.
##
## OFF must reproduce the legacy path exactly. ON must debit the source's upper
## stock with the same accepted amount as its bulk stock, keep the derived lower
## stock invariant, refund symmetrically and never create negative CO.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")
const SmokeModelScript = preload("res://sim/smoke/SmokeModel.gd")
const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd")

const EPS: float = 1.0e-12

var _failed: bool = false


func _init() -> void:
	_test_flag_defaults_false()
	_test_off_reproduces_legacy_transport()
	_test_on_debits_bulk_and_upper_together()
	_test_on_keeps_derived_lower_invariant()
	_test_on_never_creates_negative_or_upper_over_bulk()
	_test_refund_restores_bulk_and_upper()
	_test_cancellation_creates_no_co()
	_test_other_species_are_untouched()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D5A_CO_ZONAL_TRANSPORT_PASS")
	quit(0)


func _test_flag_defaults_false() -> void:
	var gas = GasExchangeSystemScript.new()
	_expect(
		not gas.phase3_co_zonal_transport_consistency_enabled,
		"CO zonal flag defaults false"
	)


func _test_off_reproduces_legacy_transport() -> void:
	var off: Dictionary = _run_transfer(false)
	# Legacy: the source loses bulk CO but keeps its upper CO untouched, which
	# is exactly the defect S0d4 measured. The derived lower stock absorbs the
	# whole debit even though the amount was sized from the upper stock.
	_expect(float(off["source_bulk_delta"]) < 0.0, "OFF debits source bulk")
	_expect(
		absf(float(off["source_upper_delta"])) <= EPS,
		"OFF leaves the source upper stock untouched"
	)
	var off_lower_delta: float = float(off["source_bulk_delta"]) \
			- float(off["source_upper_delta"])
	_expect(
		absf(off_lower_delta - float(off["source_bulk_delta"])) <= EPS,
		"OFF pushes the entire debit onto the derived lower stock"
	)


func _test_on_debits_bulk_and_upper_together() -> void:
	var on: Dictionary = _run_transfer(true)
	_expect(
		absf(float(on["source_bulk_delta"]) - float(on["source_upper_delta"])) <= 1.0e-12,
		"ON debits bulk and upper with the same accepted amount"
	)
	_expect(float(on["source_bulk_delta"]) < 0.0, "ON still debits the source")
	_expect(
		absf(float(on["target_bulk_delta"]) - float(on["target_upper_delta"])) <= 1.0e-12,
		"target credit is symmetric in bulk and upper"
	)
	_expect(
		absf(float(on["source_bulk_delta"]) + float(on["target_bulk_delta"])) <= 1.0e-9,
		"bulk CO is conserved across the transfer"
	)


func _test_on_keeps_derived_lower_invariant() -> void:
	var on: Dictionary = _run_transfer(true)
	var source_lower_delta: float = float(on["source_bulk_delta"]) \
			- float(on["source_upper_delta"])
	_expect(
		absf(source_lower_delta) <= 1.0e-12,
		"the source derived lower stock is invariant"
	)


func _test_on_never_creates_negative_or_upper_over_bulk() -> void:
	var on: Dictionary = _run_transfer(true)
	_expect(float(on["source_bulk_after"]) >= 0.0, "source bulk stays non-negative")
	_expect(float(on["source_upper_after"]) >= 0.0, "source upper stays non-negative")
	_expect(
		float(on["source_upper_after"]) <= float(on["source_bulk_after"]) + 1.0e-12,
		"ON keeps upper at or below bulk in the corrected path"
	)


func _test_refund_restores_bulk_and_upper() -> void:
	for enabled in [false, true]:
		var building = BuildingModelScript.new()
		building.outside_temp_c = 20.0
		var source = _room(0)
		source.co_kg = 0.02
		source.co_upper_kg = 0.02
		var target = _room(1)
		# Target already saturated: the delivery must refund almost everything.
		target.co_kg = 0.40
		target.co_upper_kg = 0.40
		building.rooms = {0: source, 1: target}
		var gas = GasExchangeSystemScript.new()
		gas.phase3_co_zonal_transport_consistency_enabled = enabled
		var entry: Dictionary = {
			"from": 0, "target": 1, "connection_id": "opening:0", "delay_s": 0.0,
			"smoke_kg": 0.0, "co_kg": 0.30, "co_upper_kg": 0.30,
			"co2_kg": 0.0, "co2_upper_kg": 0.0, "hcn_kg": 0.0, "hcn_upper_kg": 0.0,
			"hcl_kg": 0.0, "acrolein_kg": 0.0, "formaldehyde_kg": 0.0,
			"upper_gas_kg": 0.0, "upper_energy_kj": 0.0, "o2_kg": 0.0,
		}
		var bulk_before: float = source.co_kg
		var upper_before: float = source.co_upper_kg
		var pending: Array[Dictionary] = [entry]
		gas._pending_interior_deliveries = pending
		gas._release_pending_interior_deliveries(building, 1.0, Callable())
		var bulk_refund: float = source.co_kg - bulk_before
		var upper_refund: float = source.co_upper_kg - upper_before
		_expect(bulk_refund > 0.0, "refund credits the source bulk (enabled=%s)" % enabled)
		_expect(
			absf(bulk_refund - upper_refund) <= 1.0e-12,
			"refund credits bulk and upper equally in a clean state (enabled=%s)" % enabled
		)
		_expect(
			source.co_upper_kg <= source.co_kg + 1.0e-12,
			"refund keeps upper at or below bulk (enabled=%s)" % enabled
		)
		building.free()

	# The legacy `minf` only differs from the corrected refund once the state is
	# already inconsistent. Pinning that keeps the claim honest: this half of the
	# change is inert in a clean state and only guards an already-violated one.
	for enabled in [false, true]:
		var building_v = BuildingModelScript.new()
		var source_v = _room(0)
		source_v.co_kg = 0.02
		source_v.co_upper_kg = 0.30
		var target_v = _room(1)
		target_v.co_kg = 0.40
		target_v.co_upper_kg = 0.40
		building_v.rooms = {0: source_v, 1: target_v}
		var gas_v = GasExchangeSystemScript.new()
		gas_v.phase3_co_zonal_transport_consistency_enabled = enabled
		var entry_v: Dictionary = {
			"from": 0, "target": 1, "connection_id": "opening:0", "delay_s": 0.0,
			"smoke_kg": 0.0, "co_kg": 0.30, "co_upper_kg": 0.30,
			"co2_kg": 0.0, "co2_upper_kg": 0.0, "hcn_kg": 0.0, "hcn_upper_kg": 0.0,
			"hcl_kg": 0.0, "acrolein_kg": 0.0, "formaldehyde_kg": 0.0,
			"upper_gas_kg": 0.0, "upper_energy_kj": 0.0, "o2_kg": 0.0,
		}
		var bulk_before_v: float = source_v.co_kg
		var upper_before_v: float = source_v.co_upper_kg
		var pending_v: Array[Dictionary] = [entry_v]
		gas_v._pending_interior_deliveries = pending_v
		gas_v._release_pending_interior_deliveries(building_v, 1.0, Callable())
		var bulk_refund_v: float = source_v.co_kg - bulk_before_v
		var upper_refund_v: float = source_v.co_upper_kg - upper_before_v
		if enabled:
			_expect(
				absf(bulk_refund_v - upper_refund_v) <= 1.0e-12,
				"ON refunds bulk and upper equally even from a violated state"
			)
		else:
			_expect(
				upper_refund_v < bulk_refund_v - 1.0e-12,
				"OFF caps the upper refund separately from a violated state"
			)
		building_v.free()


func _test_cancellation_creates_no_co() -> void:
	var building = BuildingModelScript.new()
	var source = _room(0)
	source.co_kg = 0.5
	source.co_upper_kg = 0.5
	building.rooms = {0: source}
	var gas = GasExchangeSystemScript.new()
	gas.phase3_co_zonal_transport_consistency_enabled = true
	var entry: Dictionary = {
		"from": 0, "target": 99, "connection_id": "opening:0", "delay_s": 0.0,
		"smoke_kg": 0.0, "co_kg": 0.10, "co_upper_kg": 0.10,
		"co2_kg": 0.0, "co2_upper_kg": 0.0, "hcn_kg": 0.0, "hcn_upper_kg": 0.0,
		"hcl_kg": 0.0, "acrolein_kg": 0.0, "formaldehyde_kg": 0.0,
		"upper_gas_kg": 0.0, "upper_energy_kj": 0.0, "o2_kg": 0.0,
	}
	var bulk_before: float = source.co_kg
	var upper_before: float = source.co_upper_kg
	var pending: Array[Dictionary] = [entry]
	gas._pending_interior_deliveries = pending
	gas._release_pending_interior_deliveries(building, 1.0, Callable())
	_expect(source.co_kg == bulk_before, "cancellation creates no bulk CO")
	_expect(source.co_upper_kg == upper_before, "cancellation creates no upper CO")
	_expect(gas._pending_interior_deliveries.is_empty(), "cancelled parcel leaves the queue")
	building.free()


func _test_other_species_are_untouched() -> void:
	var off: Dictionary = _run_transfer(false)
	var on: Dictionary = _run_transfer(true)
	for key in ["source_co2_bulk_after", "source_co2_upper_after",
			"source_hcn_bulk_after", "source_hcn_upper_after"]:
		_expect(
			absf(float(off[key]) - float(on[key])) <= EPS,
			"%s is unchanged by the CO experiment" % key
		)


func _run_transfer(enabled: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	var source = _room(0)
	source.smoke_kg = 20.0
	source.temp_upper_c = 300.0
	source.co_kg = 0.5
	source.co_upper_kg = 0.3
	source.co2_kg = 1.0
	source.co2_upper_kg = 0.8
	source.hcn_kg = 0.2
	source.hcn_upper_kg = 0.15
	var target = _room(1)
	building.rooms = {0: source, 1: target}
	var door = OpeningModelScript.new(0, 1, OpeningModelScript.Type.DOOR, 0.9, 2.0, 1.0, 0.0)
	door.opening_index = 0
	door.open_fraction_smooth = 1.0
	building.openings = [door]

	var thermal = ThermalSystemScript.new()
	var smoke_model = SmokeModelScript.new()
	thermal.set_references(building, smoke_model)
	var gas = GasExchangeSystemScript.new()
	gas.phase3_co_zonal_transport_consistency_enabled = enabled
	# Immediate transport: no delay, so the debit and credit land in one step.
	gas.interior_transport_enabled = false
	# Isolate the audited path: silence every other CO route in this step so the
	# assertions describe the transport debit alone.
	gas.ach_infiltration = 0.0
	gas.background_species_exchange_kg_s_m2 = 0.0
	gas.doorway_o2_counterflow_coeff = 0.0
	gas.smoke_settling_base_per_s = 0.0
	gas.smoke_settling_bonus_per_s = 0.0

	var source_bulk_before: float = source.co_kg
	var source_upper_before: float = source.co_upper_kg
	var target_bulk_before: float = target.co_kg
	var target_upper_before: float = target.co_upper_kg
	gas.step_smoke(building, smoke_model, 1.0, {
		"remove_upper_layer_fraction_callable": Callable(
			thermal, "remove_upper_layer_fraction"
		),
		"compute_interroom_transfer_temp_callable": Callable(
			thermal, "compute_interroom_transfer_temp_c"
		),
		"opening_flow_cache": {},
	})
	var result: Dictionary = {
		"source_bulk_delta": source.co_kg - source_bulk_before,
		"source_upper_delta": source.co_upper_kg - source_upper_before,
		"target_bulk_delta": target.co_kg - target_bulk_before,
		"target_upper_delta": target.co_upper_kg - target_upper_before,
		"source_bulk_after": source.co_kg,
		"source_upper_after": source.co_upper_kg,
		"source_co2_bulk_after": source.co2_kg,
		"source_co2_upper_after": source.co2_upper_kg,
		"source_hcn_bulk_after": source.hcn_kg,
		"source_hcn_upper_after": source.hcn_upper_kg,
	}
	building.free()
	return result


func _room(room_id: int):
	var room = RoomModelScript.new()
	room.id = room_id
	room.width_m = 5.0
	room.length_m = 4.0
	room.height_m = 2.5
	room.thermal_layer_m = 1.2
	room.temp_upper_c = 60.0
	room.temp_lower_c = 20.0
	room.upper_gas_kg = 3.0
	room.lower_gas_kg = 50.0
	room.upper_energy_kj = 200.0
	room.lower_energy_kj = 10.0
	room.o2 = 0.209
	return room


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2-S0d5a ASSERTION FAILED: %s" % label)
