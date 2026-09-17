extends SceneTree

## Tests deterministas del modelo puro de deformacion prescrita de una puerta
## cerrada (sim/core/ClosedDoorDeformationModel.gd) y de su paso por el solver
## de fuga (sim/core/ClosedDoorLeakageModel.gd). No arranca el motor.
##
##   <godot> --headless --path . --script res://tools/validate_closed_door_deformation_model.gd
##   <godot> --headless --path . --script res://tools/validate_closed_door_deformation_model.gd -- --dump=<ruta.json>

const Deformation := preload("res://sim/core/ClosedDoorDeformationModel.gd")
const Leakage := preload("res://sim/core/ClosedDoorLeakageModel.gd")

const TOL: float = 1.0e-12
const SILL_M: float = 0.0
const DOOR_H_M: float = 2.05
const BANDS: int = 8
const COLD_ELA_M2: float = 0.0021
## Parametros de PRUEBA del solver de fuga (ver su propio validador).
const FLOW_PARAMS: Dictionary = {
	"ela_reference_pressure_pa": 4.0,
	"flow_exponent": 0.65,
	"zero_pressure_regularization_pa": 0.0,
	"pressure_domain_max_pa": 50.0,
}

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_no_tracks()
	_test_02_zero_tracks()
	_test_03_lintel_gap()
	_test_04_latch_gap()
	_test_05_simultaneous_gaps()
	_test_06_before_first_point()
	_test_07_exact_points()
	_test_08_interpolation()
	_test_09_after_last_point()
	_test_10_increasing()
	_test_11_decreasing()
	_test_12_non_monotone()
	_test_13_bad_times()
	_test_14_non_finite()
	_test_15_negative_area()
	_test_16_additional_conservation()
	_test_17_combined_conservation()
	_test_18_merge()
	_test_19_insert()
	_test_20_order_independence()
	_test_21_inputs_untouched()
	_test_22_determinism(dump_path)
	_test_23_zero_equals_cold()
	_test_24_through_leakage_solver()
	_test_25_height_changes_direction()
	_test_26_identity_and_location()
	_test_27_ignored_extras()
	_test_28_output_is_geometry_only()
	_test_29_side_ids_are_two_ascii_digits()
	_test_30_band_center_preconditions()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("CLOSED DOOR DEFORMATION MODEL VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("CLOSED DOOR DEFORMATION MODEL VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	if expected == 0.0:
		return actual == 0.0
	return absf(actual - expected) <= tol * absf(expected)


func _sum_close(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= Deformation.AREA_SUM_EPSILONS * 2.220446049250313e-16 * maxf(absf(expected), 1.0e-300)


func _cold() -> Array:
	return Leakage.build_door_segments(COLD_ELA_M2, SILL_M, DOOR_H_M, Leakage.PROVISIONAL_SPLIT, BANDS)["segments"]


func _band_z(band: int) -> float:
	var center: Dictionary = Deformation.side_band_center(SILL_M, DOOR_H_M, band, BANDS)
	if not bool(center["valid"]):
		_check(false, "helper band %d must be valid" % band)
		return NAN
	return float(center["z_m"])


func _track(track_id: String, location: String, z_m: float, points: Array, metadata: Variant = null) -> Dictionary:
	var track: Dictionary = {"id": track_id, "location": location, "z_m": z_m, "points": points}
	if metadata != null:
		track["metadata"] = metadata
	return track


func _top(points: Array) -> Dictionary:
	return _track("top", "top", SILL_M + DOOR_H_M, points)


func _latch(band: int, points: Array, metadata: Variant = null) -> Dictionary:
	return _track("latch_side_%02d" % band, "latch_side", _band_z(band), points, metadata)


func _hinge(band: int, points: Array, metadata: Variant = null) -> Dictionary:
	return _track("hinge_side_%02d" % band, "hinge_side", _band_z(band), points, metadata)


## Area evaluada de una unica pista en `time_s`.
func _eval_one(points: Array, time_s: float) -> float:
	var result: Dictionary = Deformation.evaluate_tracks([_top(points)], time_s)
	if not bool(result["valid"]):
		return NAN
	return float(result["segments"][0]["area_m2"])


func _by_id(segments: Array) -> Dictionary:
	var out: Dictionary = {}
	for segment in segments:
		out[String(segment["id"])] = segment
	return out


func _geometry(segments: Array) -> Array:
	var out: Array = []
	for segment in segments:
		out.append([String(segment["id"]), float(segment["z_m"]), float(segment["area_m2"])])
	return out


func _hot_room() -> Array:
	# Sala a con capa caliente (0,6 kg/m3) por encima de 1 m y -3 Pa en el suelo;
	# b a 1,2 uniforme. Plano neutro en z = 1 + 3/(9,81*0,6) = 1,5097 m.
	return [
		{"floor_z_m": 0.0, "interface_height_m": 1.0, "rho_lower_kg_m3": 1.2, "rho_upper_kg_m3": 0.6, "p_floor_pa": -3.0},
		{"floor_z_m": 0.0, "interface_height_m": 10.0, "rho_lower_kg_m3": 1.2, "rho_upper_kg_m3": 1.2, "p_floor_pa": 0.0},
	]


# ---------------------------------------------------------------- tests

func _test_01_no_tracks() -> void:
	var evaluated: Dictionary = Deformation.evaluate_tracks([], 120.0)
	_check(bool(evaluated["valid"]) and evaluated["segments"].is_empty(), "01 no tracks evaluates to nothing")
	_check(float(evaluated["additional_ela_total_m2"]) == 0.0, "01 no tracks add no area")
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), [], 120.0)
	_check(bool(combined["valid"]), "01 no tracks combine")
	_check(_geometry(combined["segments"]) == _geometry(_cold()), "01 no tracks keep the cold segments")
	_check(float(combined["time_s"]) == 120.0, "01 evaluated time is reported")


func _test_02_zero_tracks() -> void:
	var tracks: Array = [_top([[0.0, 0.0], [600.0, 0.0]]), _latch(6, [[0.0, 0.0]]), _hinge(2, [[30.0, 0.0], [90.0, 0.0]])]
	for time_s in [-10.0, 0.0, 45.0, 600.0, 1.0e6]:
		var evaluated: Dictionary = Deformation.evaluate_tracks(tracks, time_s)
		_check(bool(evaluated["valid"]) and evaluated["segments"].size() == 3, "02 zero tracks are all reported at %s s" % time_s)
		for segment in evaluated["segments"]:
			_check(float(segment["area_m2"]) == 0.0, "02 zero track %s is zero at %s s" % [segment["id"], time_s])
		_check(float(evaluated["additional_ela_total_m2"]) == 0.0, "02 zero tracks add nothing at %s s" % time_s)


func _test_03_lintel_gap() -> void:
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), [_top([[0.0, 0.0], [600.0, 0.003]])], 600.0)
	var by_id: Dictionary = _by_id(combined["segments"])
	var cold_top: float = float(_by_id(_cold())["top"]["area_m2"])
	_check(_close(float(by_id["top"]["area_m2"]), cold_top + 0.003), "03 lintel gap adds to the cold lintel")
	_check(float(by_id["top"]["additional_area_m2"]) == 0.003 and float(by_id["top"]["cold_area_m2"]) == cold_top,
			"03 lintel keeps cold and additional parts")
	for segment in combined["segments"]:
		if segment["id"] != "top":
			_check(float(segment["area_m2"]) == float(_by_id(_cold())[segment["id"]]["area_m2"]),
					"03 lintel gap leaves %s untouched" % segment["id"])
	_check(combined["segments"].size() == BANDS + 2, "03 lintel gap adds no new segment")


func _test_04_latch_gap() -> void:
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), [_latch(5, [[0.0, 0.0], [300.0, 0.0015]])], 300.0)
	var by_id: Dictionary = _by_id(combined["segments"])
	_check(by_id.has("latch_side_05"), "04 latch gap becomes its own segment")
	var latch: Dictionary = by_id["latch_side_05"]
	_check(float(latch["area_m2"]) == 0.0015 and float(latch["cold_area_m2"]) == 0.0, "04 latch gap area is only additional")
	_check(_close(float(latch["z_m"]), _band_z(5)), "04 latch gap keeps its height")
	_check(latch["location"] == "latch_side", "04 latch gap keeps its location")
	_check(not by_id.has("hinge_side_05"), "04 no hinge segment appears")
	_check(combined["segments"].size() == BANDS + 3, "04 one new segment")
	for segment in _cold():
		_check(float(by_id[segment["id"]]["area_m2"]) == float(segment["area_m2"]), "04 cold %s untouched" % segment["id"])


func _tracks_multi() -> Array:
	return [
		_top([[0.0, 0.0], [120.0, 0.0010], [600.0, 0.0030]]),
		_latch(5, [[60.0, 0.0], [300.0, 0.0012]]),
		_latch(6, [[60.0, 0.0], [300.0, 0.0008]]),
		_hinge(6, [[90.0, 0.0], [400.0, 0.0002]]),
		_track("bottom", "bottom", SILL_M, [[0.0, 0.0], [600.0, 0.0001]]),
	]


func _test_05_simultaneous_gaps() -> void:
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), _tracks_multi(), 300.0)
	_check(bool(combined["valid"]), "05 several gaps combine")
	var by_id: Dictionary = _by_id(combined["segments"])
	for key in ["latch_side_05", "latch_side_06", "hinge_side_06"]:
		_check(by_id.has(key), "05 %s is present" % key)
	_check(_close(float(by_id["latch_side_05"]["area_m2"]), 0.0012), "05 latch 05 at 300 s")
	_check(_close(float(by_id["latch_side_06"]["area_m2"]), 0.0008), "05 latch 06 at 300 s")
	_check(_close(float(by_id["hinge_side_06"]["area_m2"]), 0.0002 * (300.0 - 90.0) / 310.0), "05 hinge 06 interpolated")
	var top_add: float = 0.0010 + (0.0030 - 0.0010) * (300.0 - 120.0) / 480.0
	_check(_close(float(by_id["top"]["additional_area_m2"]), top_add), "05 lintel additional at 300 s")
	_check(_close(float(by_id["bottom"]["additional_area_m2"]), 0.0001 * 0.5), "05 bottom additional at 300 s")


func _test_06_before_first_point() -> void:
	var points: Array = [[100.0, 0.002], [200.0, 0.004]]
	for time_s in [-1.0e6, 0.0, 99.0, 99.999999]:
		_check(_eval_one(points, time_s) == 0.0, "06 before the first point the area is 0 (%s s)" % time_s)
	_check(Deformation.BEFORE_FIRST_POINT_VALUE_M2 == 0.0, "06 documented contract is zero")


func _test_07_exact_points() -> void:
	var points: Array = [[0.0, 0.0], [60.0, 0.0011], [90.0, 0.0017], [240.0, 0.0004], [600.0, 0.0023]]
	for point in points:
		_check(_eval_one(points, float(point[0])) == float(point[1]), "07 exact value at %s s" % point[0])


func _test_08_interpolation() -> void:
	var points: Array = [[0.0, 0.0], [60.0, 0.0012], [120.0, 0.0006]]
	_check(_close(_eval_one(points, 30.0), 0.0006), "08 midpoint of a rising stretch")
	_check(_close(_eval_one(points, 15.0), 0.0003), "08 quarter of a rising stretch")
	_check(_close(_eval_one(points, 90.0), 0.0009), "08 midpoint of a falling stretch")
	# Continuidad en el punto interior.
	var left: float = _eval_one(points, 60.0 - 1.0e-9)
	var right: float = _eval_one(points, 60.0 + 1.0e-9)
	_check(absf(left - 0.0012) < 1.0e-12 and absf(right - 0.0012) < 1.0e-12, "08 continuous at the joint")


func _test_09_after_last_point() -> void:
	var points: Array = [[0.0, 0.0], [60.0, 0.001], [120.0, 0.003]]
	for time_s in [120.0, 120.000001, 180.0, 1.0e6]:
		_check(_eval_one(points, time_s) == 0.003, "09 after the last point the last value holds (%s s)" % time_s)
	var single: Array = [[10.0, 0.0007]]
	_check(_eval_one(single, 10.0) == 0.0007 and _eval_one(single, 1.0e4) == 0.0007 and _eval_one(single, 9.0) == 0.0,
			"09 single-point track")


func _test_10_increasing() -> void:
	var points: Array = [[0.0, 0.0], [60.0, 0.0005], [120.0, 0.0015], [300.0, 0.003]]
	var previous: float = -1.0
	for step in range(0, 61):
		var value: float = _eval_one(points, float(step) * 5.0)
		_check(value >= previous, "10 rising history rises at %d s" % (step * 5))
		previous = value
	_check(_eval_one(points, 300.0) == 0.003, "10 rising history reaches its end")


func _test_11_decreasing() -> void:
	var points: Array = [[0.0, 0.003], [100.0, 0.001], [200.0, 0.0]]
	_check(bool(Deformation.validate_tracks([_top(points)])["valid"]), "11 falling history is accepted")
	_check(_close(_eval_one(points, 50.0), 0.002), "11 falling history interpolates down")
	_check(_eval_one(points, 200.0) == 0.0 and _eval_one(points, 500.0) == 0.0, "11 falling history can close")
	var previous: float = INF
	for step in range(0, 41):
		var value: float = _eval_one(points, float(step) * 5.0)
		_check(value <= previous, "11 falling history falls at %d s" % (step * 5))
		previous = value


func _test_12_non_monotone() -> void:
	var points: Array = [[0.0, 0.0], [60.0, 0.002], [120.0, 0.0005], [180.0, 0.0025], [240.0, 0.001]]
	var values: Array = []
	for time_s in [30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 999.0]:
		values.append(_eval_one(points, time_s))
	var expected: Array = [0.001, 0.002, 0.00125, 0.0005, 0.0015, 0.0025, 0.00175, 0.001, 0.001]
	for index in range(values.size()):
		_check(_close(float(values[index]), float(expected[index])), "12 non-monotone value %d" % index)


func _test_13_bad_times() -> void:
	var cases: Dictionary = {
		"unordered": [[0.0, 0.0], [120.0, 0.001], [60.0, 0.002]],
		"duplicated": [[0.0, 0.0], [60.0, 0.001], [60.0, 0.002]],
		"empty": [],
	}
	for label in cases.keys():
		var checked: Dictionary = Deformation.validate_tracks([_top(cases[label])])
		_check(not bool(checked["valid"]), "13 %s times are rejected" % label)
		var evaluated: Dictionary = Deformation.evaluate_tracks([_top(cases[label])], 10.0)
		_check(not bool(evaluated["valid"]) and evaluated["segments"].is_empty(), "13 %s times do not evaluate" % label)
	var dup_ids: Dictionary = Deformation.validate_tracks([_top([[0.0, 0.001]]), _top([[0.0, 0.002]])])
	_check(not bool(dup_ids["valid"]), "13 duplicate track ids are rejected")


func _test_14_non_finite() -> void:
	var cases: Array = [
		_top([[NAN, 0.001]]),
		_top([[0.0, 0.0], [INF, 0.001]]),
		_top([[0.0, NAN]]),
		_top([[0.0, INF]]),
		_track("top", "top", NAN, [[0.0, 0.001]]),
		_track("latch_side_01", "latch_side", INF, [[0.0, 0.001]]),
	]
	for index in range(cases.size()):
		_check(not bool(Deformation.validate_tracks([cases[index]])["valid"]), "14 non-finite case %d is rejected" % index)
	var bad_time: Dictionary = Deformation.evaluate_tracks([_top([[0.0, 0.001]])], NAN)
	_check(not bool(bad_time["valid"]), "14 non-finite evaluation time is rejected")
	var bad_cold: Dictionary = Deformation.combine_with_cold([{"id": "top", "z_m": NAN, "area_m2": 0.001}], [])
	_check(not bool(bad_cold["valid"]), "14 non-finite cold segment is rejected")


func _test_15_negative_area() -> void:
	_check(not bool(Deformation.validate_tracks([_top([[0.0, 0.0], [10.0, -1.0e-9]])])["valid"]), "15 negative area is rejected")
	var result: Dictionary = Deformation.evaluate_and_combine(_cold(), [_latch(1, [[0.0, -0.001]])], 5.0)
	_check(not bool(result["valid"]) and result["segments"].is_empty(), "15 negative area does not combine")
	var negative_segment: Dictionary = Deformation.combine_with_cold(_cold(), [{"id": "top", "z_m": DOOR_H_M, "area_m2": -0.001}])
	_check(not bool(negative_segment["valid"]), "15 negative evaluated segment is rejected")


func _test_16_additional_conservation() -> void:
	for time_s in [0.0, 45.0, 120.0, 300.0, 450.0, 900.0]:
		var evaluated: Dictionary = Deformation.evaluate_tracks(_tracks_multi(), time_s)
		var expected: float = 0.0
		for track in _tracks_multi():
			expected += Deformation.area_at(track["points"], time_s)
		_check(_sum_close(float(evaluated["additional_ela_total_m2"]), expected), "16 additional total at %s s" % time_s)
		var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), _tracks_multi(), time_s)
		var additional_in_segments: float = 0.0
		for segment in combined["segments"]:
			additional_in_segments += float(segment["additional_area_m2"])
		_check(_sum_close(additional_in_segments, expected), "16 no additional area lost or duplicated at %s s" % time_s)
		_check(_sum_close(float(combined["additional_ela_total_m2"]), expected), "16 combined reports the additional total at %s s" % time_s)


func _test_17_combined_conservation() -> void:
	var cold_total: float = Leakage.area_total_m2(_cold())
	for time_s in [0.0, 45.0, 120.0, 300.0, 450.0, 900.0]:
		var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), _tracks_multi(), time_s)
		_check(_sum_close(float(combined["cold_ela_total_m2"]), cold_total), "17 cold total kept at %s s" % time_s)
		var expected: float = cold_total + float(combined["additional_ela_total_m2"])
		_check(_sum_close(float(combined["combined_ela_total_m2"]), expected), "17 combined = cold + additional at %s s" % time_s)
		_check(_sum_close(Leakage.area_total_m2(combined["segments"]), expected), "17 segment areas add up at %s s" % time_s)
		var cold_in_segments: float = 0.0
		for segment in combined["segments"]:
			cold_in_segments += float(segment["cold_area_m2"])
			_check(_close(float(segment["area_m2"]), float(segment["cold_area_m2"]) + float(segment["additional_area_m2"])),
					"17 %s total = cold + additional at %s s" % [segment["id"], time_s])
		_check(_sum_close(cold_in_segments, cold_total), "17 no cold area lost at %s s" % time_s)


func _test_18_merge() -> void:
	var tracks: Array = [_top([[0.0, 0.002]]), _track("bottom", "bottom", SILL_M, [[0.0, 0.0004]])]
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), tracks, 10.0)
	var by_id: Dictionary = _by_id(combined["segments"])
	var cold: Dictionary = _by_id(_cold())
	_check(combined["segments"].size() == BANDS + 2, "18 merged segments do not duplicate")
	for key in ["top", "bottom"]:
		var entry: Dictionary = by_id[key]
		var contributions: Array = entry["contributions"]
		_check(contributions.size() == 2, "18 %s keeps both contributions" % key)
		_check(contributions[0]["source"] == "cold" and contributions[1]["source"] == "deformation", "18 %s provenance" % key)
		_check(float(contributions[0]["area_m2"]) == float(cold[key]["area_m2"]), "18 %s cold contribution" % key)
	_check(_close(float(by_id["top"]["area_m2"]), float(cold["top"]["area_m2"]) + 0.002), "18 lintel sum")
	_check(_close(float(by_id["bottom"]["area_m2"]), float(cold["bottom"]["area_m2"]) + 0.0004), "18 bottom sum")
	# Mismo id con otra cota: error, no una fusion silenciosa.
	var misplaced: Dictionary = Deformation.evaluate_and_combine(_cold(), [_track("top", "top", 1.0, [[0.0, 0.002]])], 10.0)
	_check(not bool(misplaced["valid"]), "18 same id at another height is rejected")


func _test_19_insert() -> void:
	var tracks: Array = [_hinge(0, [[0.0, 0.0003]]), _latch(7, [[0.0, 0.0009]])]
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), tracks, 10.0)
	var ids: Array = []
	var previous_z: float = -INF
	for segment in combined["segments"]:
		ids.append(segment["id"])
		_check(float(segment["z_m"]) >= previous_z, "19 inserted segments keep the height order")
		previous_z = float(segment["z_m"])
	_check(ids.size() == BANDS + 4, "19 two new segments")
	var hinge_index: int = ids.find("hinge_side_00")
	var side_index: int = ids.find("side_00")
	_check(hinge_index >= 0 and side_index >= 0 and hinge_index < side_index, "19 equal heights are ordered by id")
	_check(ids.find("latch_side_07") == ids.find("side_07") - 1, "19 latch 07 sits next to the cold band 07")
	var only_new: Dictionary = _by_id(combined["segments"])["hinge_side_00"]
	_check(only_new["contributions"].size() == 1 and only_new["contributions"][0]["track_id"] == "hinge_side_00",
			"19 new segment provenance")


func _test_20_order_independence() -> void:
	var reference: String = JSON.stringify(Deformation.evaluate_and_combine(_cold(), _tracks_multi(), 250.0), "", true, true)
	var reversed_tracks: Array = _tracks_multi()
	reversed_tracks.reverse()
	var reversed_cold: Array = _cold()
	reversed_cold.reverse()
	var rotated: Array = _tracks_multi().slice(2) + _tracks_multi().slice(0, 2)
	for variant in [[reversed_cold, _tracks_multi()], [_cold(), reversed_tracks], [reversed_cold, rotated]]:
		var text: String = JSON.stringify(Deformation.evaluate_and_combine(variant[0], variant[1], 250.0), "", true, true)
		_check(text == reference, "20 output does not depend on the input order")
	var evaluated: Dictionary = Deformation.evaluate_tracks(reversed_tracks, 250.0)
	var ordered: Dictionary = Deformation.evaluate_tracks(_tracks_multi(), 250.0)
	_check(JSON.stringify(evaluated, "", true, true) == JSON.stringify(ordered, "", true, true), "20 evaluation is order independent")


func _test_21_inputs_untouched() -> void:
	var tracks: Array = _tracks_multi()
	tracks.append(_hinge(3, [[0.0, 0.0001]], {"source": "prescribed", "gap_mm": 3.7}))
	var cold: Array = _cold()
	var before: String = JSON.stringify([tracks, cold], "", true, true)
	Deformation.validate_tracks(tracks)
	var result: Dictionary = Deformation.evaluate_and_combine(cold, tracks, 333.0)
	Deformation.combine_with_cold(cold, Deformation.evaluate_tracks(tracks, 333.0)["segments"])
	_check(JSON.stringify([tracks, cold], "", true, true) == before, "21 inputs are not modified")
	# La salida no comparte diccionarios con la entrada.
	for segment in result["segments"]:
		if segment["id"] == "hinge_side_03":
			segment["contributions"][0]["area_m2"] = 99.0
	_check(JSON.stringify([tracks, cold], "", true, true) == before, "21 output does not alias the input")


func _battery() -> Dictionary:
	var battery: Dictionary = {}
	for time_s in [0.0, 60.0, 250.0, 600.0, 1200.0]:
		var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), _tracks_multi(), time_s)
		var sides: Array = _hot_room()
		battery["t_%s" % time_s] = {
			"combined": combined,
			"flows": Leakage.compute_flows(combined["segments"], sides[0], sides[1], FLOW_PARAMS, 0.5),
		}
	return battery


func _test_22_determinism(dump_path: String) -> void:
	var first: String = JSON.stringify(_battery(), "", true, true)
	var second: String = JSON.stringify(_battery(), "", true, true)
	_check(first == second, "22 two in-process runs are identical")
	if dump_path.is_empty():
		return
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "22 could not open dump file %s" % dump_path)
		return
	file.store_string(first + "\n")
	file.close()


func _test_23_zero_equals_cold() -> void:
	var zero_tracks: Array = [
		_top([[0.0, 0.0], [600.0, 0.0]]),
		_track("bottom", "bottom", SILL_M, [[0.0, 0.0]]),
		_latch(5, [[0.0, 0.0]]),
		_hinge(2, [[0.0, 0.0]]),
	]
	var sides: Array = _hot_room()
	var cold_flows: String = JSON.stringify(Leakage.compute_flows(_cold(), sides[0], sides[1], FLOW_PARAMS, 0.5), "", true, true)
	for tracks in [[], zero_tracks, [_latch(3, [[100.0, 0.004]])]]:
		var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), tracks, 50.0)
		_check(_geometry(combined["segments"]) == _geometry(_cold()), "23 zero deformation keeps the cold segments exactly")
		_check(float(combined["combined_ela_total_m2"]) == Leakage.area_total_m2(_cold()), "23 zero deformation keeps the cold total")
		var flows: String = JSON.stringify(Leakage.compute_flows(combined["segments"], sides[0], sides[1], FLOW_PARAMS, 0.5), "", true, true)
		_check(flows == cold_flows, "23 zero deformation gives byte-identical flows")


func _test_24_through_leakage_solver() -> void:
	var sides: Array = _hot_room()
	var cold_result: Dictionary = Leakage.compute_flows(_cold(), sides[0], sides[1], FLOW_PARAMS, 0.5)
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), _tracks_multi(), 600.0)
	var result: Dictionary = Leakage.compute_flows(combined["segments"], sides[0], sides[1], FLOW_PARAMS, 0.5)
	_check(bool(result["valid"]), "24 the leakage solver accepts the combined segments")
	_check(result["flows"].size() == combined["segments"].size(), "24 one flow per combined segment")
	var cold_top: Dictionary = {}
	var top: Dictionary = {}
	for flow in cold_result["flows"]:
		if flow["segment_id"] == "top":
			cold_top = flow
	for flow in result["flows"]:
		if flow["segment_id"] == "top":
			top = flow
	var ratio: float = float(_by_id(combined["segments"])["top"]["area_m2"]) / float(_by_id(_cold())["top"]["area_m2"])
	_check(_close(float(top["mass_flow_kg_s"]) / float(cold_top["mass_flow_kg_s"]), ratio, 1.0e-12),
			"24 the lintel flow grows with its combined ELA")
	_check(float(result["gross_mass_kg_s"]) > float(cold_result["gross_mass_kg_s"]), "24 deformation adds flow")
	_check(Leakage.area_total_m2(combined["segments"]) > Leakage.area_total_m2(_cold()), "24 deformation adds area")


func _test_25_height_changes_direction() -> void:
	var sides: Array = _hot_room()
	var neutral_z: float = 1.0 + 3.0 / (Leakage.GRAVITY_M_S2 * 0.6)
	var low: Dictionary = Deformation.evaluate_and_combine([], [_latch(1, [[0.0, 0.001]])], 1.0)
	var high: Dictionary = Deformation.evaluate_and_combine([], [_latch(7, [[0.0, 0.001]])], 1.0)
	var low_flow: Dictionary = Leakage.compute_flows(low["segments"], sides[0], sides[1], FLOW_PARAMS)["flows"][0]
	var high_flow: Dictionary = Leakage.compute_flows(high["segments"], sides[0], sides[1], FLOW_PARAMS)["flows"][0]
	_check(_band_z(1) < neutral_z and _band_z(7) > neutral_z, "25 the two latch bands straddle the neutral plane")
	_check(low_flow["direction"] == Leakage.DIRECTION_B_TO_A, "25 a low latch gap draws cold air into the hot room")
	_check(high_flow["direction"] == Leakage.DIRECTION_A_TO_B, "25 a high latch gap lets hot gas out")
	_check(high_flow["source_zone"] == Leakage.ZONE_UPPER and low_flow["source_zone"] == Leakage.ZONE_LOWER,
			"25 the source zone follows the gap height")
	_check(_close(float(low_flow["z_m"]), _band_z(1)) and _close(float(high_flow["z_m"]), _band_z(7)),
			"25 the solver sees the gap heights")


func _test_26_identity_and_location() -> void:
	var evaluated: Dictionary = Deformation.evaluate_tracks([_hinge(4, [[0.0, 0.0002]]), _latch(4, [[0.0, 0.0006]])], 1.0)
	var by_id: Dictionary = _by_id(evaluated["segments"])
	_check(by_id["hinge_side_04"]["location"] == "hinge_side" and float(by_id["hinge_side_04"]["area_m2"]) == 0.0002,
			"26 hinge track stays on the hinge side")
	_check(by_id["latch_side_04"]["location"] == "latch_side" and float(by_id["latch_side_04"]["area_m2"]) == 0.0006,
			"26 latch track stays on the latch side")
	var combined: Dictionary = Deformation.combine_with_cold([], evaluated["segments"])
	var combined_by_id: Dictionary = _by_id(combined["segments"])
	_check(combined_by_id["hinge_side_04"]["location"] == "hinge_side"
			and combined_by_id["latch_side_04"]["location"] == "latch_side", "26 combined locations are kept")
	var mismatched: Array = [
		_track("hinge_side_01", "latch_side", 0.5, [[0.0, 0.001]]),
		_track("latch_side_01", "hinge_side", 0.5, [[0.0, 0.001]]),
		_track("top", "bottom", 0.0, [[0.0, 0.001]]),
		_track("latch_side_1", "latch_side", 0.5, [[0.0, 0.001]]),
		_track("side_01", "sides", 0.5, [[0.0, 0.001]]),
		_track("uniform", "door", 1.0, [[0.0, 0.001]]),
	]
	for track in mismatched:
		_check(not bool(Deformation.validate_tracks([track])["valid"]), "26 inconsistent track %s/%s is rejected" % [track["id"], track["location"]])


func _test_27_ignored_extras() -> void:
	# Ni metadatos (milimetros, deformacion central) ni temperaturas entran en el area.
	var plain: Dictionary = Deformation.evaluate_tracks([_latch(5, [[0.0, 0.0], [100.0, 0.001]])], 50.0)
	var decorated_track: Dictionary = _latch(5, [[0.0, 0.0], [100.0, 0.001]],
			{"origin": "Prieler 2023 topology", "gap_mm": 3.7, "centre_deformation_mm": 10.0, "leaf_percent": 4.0})
	decorated_track["temperature_c"] = 900.0
	decorated_track["upper_temperature_c"] = 650.0
	decorated_track["thermal_gap_fraction"] = 0.04
	decorated_track["open_fraction"] = 0.5
	var decorated: Dictionary = Deformation.evaluate_tracks([decorated_track], 50.0)
	_check(bool(decorated["valid"]), "27 extra keys are tolerated")
	_check(float(decorated["segments"][0]["area_m2"]) == float(plain["segments"][0]["area_m2"]), "27 metadata and temperature do not change the area")
	_check(decorated["segments"][0]["metadata"]["gap_mm"] == 3.7, "27 metadata is kept as provenance")
	var metadata_only: Dictionary = Deformation.evaluate_tracks([_latch(5, [[0.0, 0.0]], {"gap_mm": 10.0})], 50.0)
	_check(float(metadata_only["segments"][0]["area_m2"]) == 0.0, "27 millimetres are never converted into area")
	var bad_metadata: Dictionary = Deformation.validate_tracks([_latch(5, [[0.0, 0.0]], "3.7 mm")])
	_check(not bool(bad_metadata["valid"]), "27 metadata must be a dictionary")


func _test_28_output_is_geometry_only() -> void:
	var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), _tracks_multi(), 300.0)
	var forbidden: Array = ["volume_flow_m3_s", "mass_flow_kg_s", "direction", "dp_pa", "open_fraction", "thermal_gap_fraction"]
	for segment in combined["segments"]:
		for key in forbidden:
			_check(not segment.has(key), "28 %s carries no %s" % [segment["id"], key])
	for key in forbidden:
		_check(not combined.has(key), "28 the result carries no %s" % key)
	var evaluated: Dictionary = Deformation.evaluate_tracks(_tracks_multi(), 300.0)
	for segment in evaluated["segments"]:
		for key in forbidden:
			_check(not segment.has(key), "28 evaluated %s carries no %s" % [segment["id"], key])
	# Una sola pista en el dintel no abre el resto de la hoja.
	var top_only: Dictionary = Deformation.evaluate_and_combine(_cold(), [_top([[0.0, 0.01]])], 1.0)
	for segment in top_only["segments"]:
		if segment["id"] != "top":
			_check(float(segment["additional_area_m2"]) == 0.0, "28 no uniform opening on %s" % segment["id"])


func _test_29_side_ids_are_two_ascii_digits() -> void:
	for location in ["hinge_side", "latch_side"]:
		for suffix in ["00", "01", "09", "10", "99"]:
			var track: Dictionary = _track("%s_%s" % [location, suffix], location, 1.0, [[0.0, 0.001]])
			_check(bool(Deformation.validate_tracks([track])["valid"]), "29 %s_%s is accepted" % [location, suffix])
	var fullwidth: String = String.chr(0xFF10) + String.chr(0xFF11)
	var arabic_indic: String = String.chr(0x0661) + String.chr(0x0662)
	var rejected: Array = [
		["hinge_side_-1", "hinge_side"],
		["latch_side_+1", "latch_side"],
		["hinge_side_1", "hinge_side"],
		["hinge_side_001", "hinge_side"],
		["latch_side_1a", "latch_side"],
		["latch_side_a1", "latch_side"],
		["hinge_side_", "hinge_side"],
		["latch_side_ 1", "latch_side"],
		["hinge_side_1 ", "hinge_side"],
		["latch_side_  ", "latch_side"],
		["hinge_side_1.", "hinge_side"],
		["latch_side_.5", "latch_side"],
		["hinge_side_-0", "hinge_side"],
		["latch_side_+0", "latch_side"],
		["hinge_side_" + fullwidth, "hinge_side"],
		["latch_side_" + arabic_indic, "latch_side"],
		["hinge_side01", "hinge_side"],
		["hinge_side_01", "latch_side"],
	]
	for case in rejected:
		var track: Dictionary = _track(String(case[0]), String(case[1]), 1.0, [[0.0, 0.001]])
		_check(not bool(Deformation.validate_tracks([track])["valid"]), "29 '%s' is rejected for %s" % [case[0], case[1]])
		var combined: Dictionary = Deformation.evaluate_and_combine(_cold(), [track], 1.0)
		_check(not bool(combined["valid"]) and combined["segments"].is_empty(), "29 '%s' does not combine" % case[0])


func _test_30_band_center_preconditions() -> void:
	var first: Dictionary = Deformation.side_band_center(0.3, 2.0, 0, 8)
	var last: Dictionary = Deformation.side_band_center(0.3, 2.0, 7, 8)
	var middle: Dictionary = Deformation.side_band_center(0.3, 2.0, 3, 8)
	var single: Dictionary = Deformation.side_band_center(0.3, 2.0, 0, 1)
	_check(bool(first["valid"]) and _close(float(first["z_m"]), 0.425), "30 first band centre")
	_check(bool(last["valid"]) and _close(float(last["z_m"]), 2.175), "30 last band centre")
	_check(bool(middle["valid"]) and _close(float(middle["z_m"]), 1.175), "30 middle band centre")
	_check(bool(single["valid"]) and _close(float(single["z_m"]), 1.3), "30 single band sits at mid height")
	for result in [first, last, middle, single]:
		_check(result["errors"].is_empty(), "30 valid centres carry no errors")
		_check(float(result["z_m"]) > 0.3 and float(result["z_m"]) < 2.3, "30 valid centres lie inside the door")
	# Misma convencion que las bandas frias.
	var cold: Array = Leakage.build_door_segments(COLD_ELA_M2, 0.3, 2.0, Leakage.PROVISIONAL_SPLIT, 8)["segments"]
	for band in range(8):
		_check(float(_by_id(cold)["side_%02d" % band]["z_m"]) == float(Deformation.side_band_center(0.3, 2.0, band, 8)["z_m"]),
				"30 band %d matches the cold band height" % band)
	var invalid: Dictionary = {
		"count zero": [0.3, 2.0, 0, 0],
		"count negative": [0.3, 2.0, 0, -3],
		"band negative": [0.3, 2.0, -1, 8],
		"band equal to count": [0.3, 2.0, 8, 8],
		"band above count": [0.3, 2.0, 9, 8],
		"height zero": [0.3, 0.0, 0, 8],
		"height negative": [0.3, -2.0, 0, 8],
		"height nan": [0.3, NAN, 0, 8],
		"height infinite": [0.3, INF, 0, 8],
		"sill nan": [NAN, 2.0, 0, 8],
		"sill infinite": [-INF, 2.0, 0, 8],
	}
	for label in invalid.keys():
		var args: Array = invalid[label]
		var result: Dictionary = Deformation.side_band_center(float(args[0]), float(args[1]), int(args[2]), int(args[3]))
		_check(not bool(result["valid"]), "30 %s is rejected" % label)
		_check(not result["errors"].is_empty(), "30 %s explains the rejection" % label)
		_check(is_nan(float(result["z_m"])), "30 %s returns no height" % label)
