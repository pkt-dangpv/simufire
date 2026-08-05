extends SceneTree

## H3.2-S0d5b fixture: experimental CO2 zonal transport consistency.
##
## Three legacy paths declare a lower-to-lower CO2 movement -- they mutate bulk
## only and record zero upper -- but size the amount from the bulk stock. When
## most CO2 lives in the upper layer they export more than the lower zone holds
## and drive the derived lower stock negative. The flag caps the transfer at the
## source's real lower stock, using the same expression the codebase already
## uses for a declared lower-zone move.

const BuildingModelScript = preload("res://sim/BuildingModel.gd")
const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd")
const OpeningModelScript = preload("res://sim/building/OpeningModel.gd")
const RoomModelScript = preload("res://sim/building/RoomModel.gd")

const EPS: float = 1.0e-12

var _failed: bool = false


func _init() -> void:
	_test_flag_defaults_false()
	_test_lower_stock_helper_is_the_declared_zone()
	_test_cap_is_signed_and_uses_the_exporting_room()
	_test_off_reproduces_the_legacy_over_export()
	_test_on_background_respects_the_lower_stock()
	_test_on_keeps_upper_untouched_and_lower_non_negative()
	_test_on_vertical_directed_respects_the_lower_stock()
	_test_symmetric_paths_are_untouched()
	if _failed:
		quit(1)
		return
	print("PHASE3_H32S0D5B_CO2_ZONAL_TRANSPORT_PASS")
	quit(0)


func _test_flag_defaults_false() -> void:
	var gas = GasExchangeSystemScript.new()
	_expect(
		not gas.phase3_co2_zonal_transport_consistency_enabled,
		"CO2 zonal flag defaults false"
	)


func _test_lower_stock_helper_is_the_declared_zone() -> void:
	var gas = GasExchangeSystemScript.new()
	var room = _room(0)
	room.co2_kg = 1.0
	room.co2_upper_kg = 0.9
	_expect(
		absf(gas._co2_lower_stock_kg(room) - 0.1) <= EPS,
		"lower stock is bulk minus upper"
	)
	# An already-violated state must clamp to zero, never to a negative stock.
	room.co2_upper_kg = 1.4
	_expect(gas._co2_lower_stock_kg(room) == 0.0, "violated state yields zero lower stock")
	_expect(gas._co2_lower_stock_kg(null) == 0.0, "null room is safe")


func _test_cap_is_signed_and_uses_the_exporting_room() -> void:
	var gas = GasExchangeSystemScript.new()
	var room_a = _room(0)
	room_a.co2_kg = 1.0
	room_a.co2_upper_kg = 0.95   # lower stock 0.05
	var room_b = _room(1)
	room_b.co2_kg = 2.0
	room_b.co2_upper_kg = 1.0    # lower stock 1.0
	# a -> b: capped by a's lower stock.
	_expect(
		absf(gas._cap_co2_lower_transfer(0.4, room_a, room_b) - 0.05) <= EPS,
		"positive net capped by the source lower stock"
	)
	# b -> a: capped by b's lower stock, sign preserved.
	_expect(
		absf(gas._cap_co2_lower_transfer(-0.4, room_a, room_b) + 0.4) <= EPS,
		"negative net within b's lower stock is untouched"
	)
	_expect(
		absf(gas._cap_co2_lower_transfer(-4.0, room_a, room_b) + 1.0) <= EPS,
		"negative net capped by b's lower stock, sign kept"
	)
	_expect(gas._cap_co2_lower_transfer(0.0, room_a, room_b) == 0.0, "zero stays zero")
	# A transfer that already fits must not be altered.
	_expect(
		absf(gas._cap_co2_lower_transfer(0.02, room_a, room_b) - 0.02) <= EPS,
		"a fitting transfer is not altered"
	)


func _test_off_reproduces_the_legacy_over_export() -> void:
	var result: Dictionary = _run_background(false)
	_expect(
		float(result["source_lower_after"]) < -1.0e-9,
		"OFF drives the source derived lower stock negative"
	)
	_expect(
		float(result["source_upper_after"]) > float(result["source_bulk_after"]) + 1.0e-9,
		"OFF leaves upper above bulk before the clamp"
	)


func _test_on_background_respects_the_lower_stock() -> void:
	var off: Dictionary = _run_background(false)
	var on: Dictionary = _run_background(true)
	_expect(
		float(on["moved_kg"]) < float(off["moved_kg"]) - 1.0e-12,
		"ON moves strictly less than the bulk-sized legacy amount"
	)
	_expect(
		absf(float(on["moved_kg"]) - float(on["source_lower_before"])) <= 1.0e-9,
		"ON moves exactly the available lower stock"
	)
	_expect(
		absf(float(on["source_bulk_delta"]) + float(on["target_bulk_delta"])) <= 1.0e-9,
		"bulk CO2 is conserved across the corrected transfer"
	)


func _test_on_keeps_upper_untouched_and_lower_non_negative() -> void:
	var on: Dictionary = _run_background(true)
	_expect(
		absf(float(on["source_upper_delta"])) <= EPS,
		"a lower-to-lower move never touches the upper stock"
	)
	_expect(
		float(on["source_lower_after"]) >= -1.0e-12,
		"the derived lower stock never goes negative"
	)
	_expect(
		float(on["source_upper_after"]) <= float(on["source_bulk_after"]) + 1.0e-12,
		"ON needs no clamp to keep upper at or below bulk"
	)
	_expect(float(on["source_bulk_after"]) >= 0.0, "bulk stays non-negative")


func _test_on_vertical_directed_respects_the_lower_stock() -> void:
	for enabled in [false, true]:
		var gas = GasExchangeSystemScript.new()
		gas.phase3_co2_zonal_transport_consistency_enabled = enabled
		var from_r = _room(0)
		from_r.co2_kg = 1.0
		from_r.co2_upper_kg = 0.98   # lower stock 0.02
		var to_r = _room(1)
		var deltas: Dictionary = _empty_deltas()
		gas._apply_directed_species_exchange(
			from_r, to_r, 30.0, 60.0, 0,
			deltas["smoke"], deltas["co"], deltas["co_upper"], deltas["co2"],
			deltas["hcn"], deltas["hcl"], deltas["acrolein"],
			deltas["formaldehyde"], deltas["o2"]
		)
		var moved: float = -float(deltas["co2"][0])
		if enabled:
			_expect(
				absf(moved - 0.02) <= 1.0e-9,
				"ON vertical directed move equals the lower stock"
			)
		else:
			_expect(
				moved > 0.02 + 1.0e-9,
				"OFF vertical directed move exceeds the lower stock"
			)
		_expect(
			absf(float(deltas["co2"][0]) + float(deltas["co2"][1])) <= 1.0e-12,
			"vertical directed CO2 is conserved (enabled=%s)" % enabled
		)


func _test_symmetric_paths_are_untouched() -> void:
	# CO and HCN must be identical with the CO2 flag on and off.
	var off: Dictionary = _run_background(false)
	var on: Dictionary = _run_background(true)
	for key in ["source_co_bulk_after", "source_co_upper_after",
			"source_hcn_bulk_after", "source_hcn_upper_after"]:
		_expect(
			absf(float(off[key]) - float(on[key])) <= EPS,
			"%s is unchanged by the CO2 experiment" % key
		)


func _run_background(enabled: bool) -> Dictionary:
	var building = BuildingModelScript.new()
	building.outside_temp_c = 20.0
	building.outside_o2 = 0.209
	# Source holds almost all its CO2 in the upper layer: the lower zone has far
	# less than a bulk-proportional exchange would try to export.
	var room_a = _room(0)
	room_a.co2_kg = 2.0
	room_a.co2_upper_kg = 1.9995
	room_a.co_kg = 0.4
	room_a.co_upper_kg = 0.3
	room_a.hcn_kg = 0.2
	room_a.hcn_upper_kg = 0.1
	room_a.smoke_kg = 8.0
	var room_b = _room(1)
	building.rooms = {0: room_a, 1: room_b}
	var opening = OpeningModelScript.new(0, 1, OpeningModelScript.Type.DOOR, 0.9, 2.0, 1.0, 0.0)
	opening.opening_index = 4
	building.openings = [opening]

	var gas = GasExchangeSystemScript.new()
	gas.phase3_co2_zonal_transport_consistency_enabled = enabled
	var deltas: Dictionary = _empty_deltas()
	gas._apply_background_species_exchange(
		building, room_a, room_b, opening, 1.0,
		deltas["smoke"], deltas["co"], deltas["co_upper"], deltas["co2"],
		deltas["co2_upper"], deltas["hcn"], deltas["hcn_upper"], deltas["hcl"],
		deltas["acrolein"], deltas["formaldehyde"], deltas["o2"]
	)
	var source_lower_before: float = room_a.co2_kg \
			- clampf(room_a.co2_upper_kg, 0.0, room_a.co2_kg)
	var source_bulk_delta: float = float(deltas["co2"][0])
	var source_upper_delta: float = float(deltas["co2_upper"][0])
	var source_bulk_after: float = room_a.co2_kg + source_bulk_delta
	var source_upper_after: float = room_a.co2_upper_kg + source_upper_delta
	var result: Dictionary = {
		"moved_kg": -source_bulk_delta,
		"source_lower_before": source_lower_before,
		"source_bulk_delta": source_bulk_delta,
		"source_upper_delta": source_upper_delta,
		"target_bulk_delta": float(deltas["co2"][1]),
		"source_bulk_after": source_bulk_after,
		"source_upper_after": source_upper_after,
		"source_lower_after": source_bulk_after - source_upper_after,
		"source_co_bulk_after": room_a.co_kg + float(deltas["co"][0]),
		"source_co_upper_after": room_a.co_upper_kg + float(deltas["co_upper"][0]),
		"source_hcn_bulk_after": room_a.hcn_kg + float(deltas["hcn"][0]),
		"source_hcn_upper_after": room_a.hcn_upper_kg + float(deltas["hcn_upper"][0]),
	}
	building.free()
	return result


func _empty_deltas() -> Dictionary:
	var deltas: Dictionary = {}
	for key in [
		"smoke", "co", "co_upper", "co2", "co2_upper", "hcn", "hcn_upper",
		"hcl", "acrolein", "formaldehyde", "o2",
	]:
		deltas[key] = {0: 0.0, 1: 0.0}
	return deltas


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
	push_error("H3.2-S0d5b ASSERTION FAILED: %s" % label)
