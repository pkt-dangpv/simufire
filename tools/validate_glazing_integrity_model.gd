extends SceneTree

## Tests deterministas del modelo puro de integridad prescrita de panos
## acristalados (sim/core/GlazingIntegrityModel.gd, fase 3A). No arranca el
## motor ni carga escenarios.
##
##   <godot> --headless --path . --script res://tools/validate_glazing_integrity_model.gd
##   <godot> --headless --path . --script res://tools/validate_glazing_integrity_model.gd -- --dump=<ruta.json>

const Glazing := preload("res://sim/core/GlazingIntegrityModel.gd")
const MODEL_PATH: String = "res://sim/core/GlazingIntegrityModel.gd"

const INTACT: String = "INTACT"
const CRACKED: String = "CRACKED"
const PARTIAL: String = "PARTIAL_FALLOUT"
const OPEN: String = "OPEN"

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_always_intact()
	_test_02_intact_to_cracked()
	_test_03_cracked_to_partial()
	_test_04_partial_to_open()
	_test_05_before_at_after_each_event()
	_test_06_step_without_interpolation()
	_test_07_determinism(dump_path)
	_test_08_order_independence()
	_test_09_inputs_untouched()
	_test_10_multi_leaf_histories()
	_test_11_intact_leaf_with_open_leaf()
	_test_12_all_leaves_partial()
	_test_13_state_regression()
	_test_14_fraction_decrease()
	_test_15_cracked_with_fraction()
	_test_16_partial_bounds()
	_test_17_open_fraction()
	_test_18_bad_times()
	_test_19_bad_geometry()
	_test_20_leaf_count_mismatch()
	_test_21_bad_indices()
	_test_22_bad_types_and_metadata()
	_test_23_provenance_preserved()
	_test_24_no_forbidden_physics_in_source()
	_test_25_no_door_state_in_source()
	_test_26_no_skipped_states()
	_test_27_output_has_no_ventilation()
	_test_28_repeated_partial_progress()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("GLAZING INTEGRITY MODEL VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("GLAZING INTEGRITY MODEL VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _event(time_s: float, state: String, fraction: float) -> Dictionary:
	return {"time_s": time_s, "state": state, "fallout_fraction": fraction}


func _leaf(leaf_id: String, index: int, events: Array, metadata: Variant = null) -> Dictionary:
	var leaf: Dictionary = {"id": leaf_id, "index": index, "events": events}
	if metadata != null:
		leaf["metadata"] = metadata
	return leaf


func _panel(panel_id: String, leaves: Array, overrides: Dictionary = {}) -> Dictionary:
	var panel: Dictionary = {
		"id": panel_id,
		"width_m": 0.8,
		"height_m": 1.2,
		"sill_z_m": 0.9,
		"glass_type": "annealed",
		"thickness_m": 0.004,
		"leaf_count": leaves.size(),
		"leaf_spacing_m": 0.0 if leaves.size() == 1 else 0.016,
		"frame_material": "timber",
		"edge_protection_depth_m": 0.015,
		"leaves": leaves,
	}
	for key in overrides.keys():
		panel[key] = overrides[key]
	return panel


func _full_history() -> Array:
	return [
		_event(0.0, INTACT, 0.0),
		_event(120.0, CRACKED, 0.0),
		_event(180.0, PARTIAL, 0.25),
		_event(240.0, PARTIAL, 0.6),
		_event(300.0, OPEN, 1.0),
	]


func _one_leaf_panel(events: Array) -> Dictionary:
	return _panel("single", [_leaf("pane", 0, events)])


func _leaf_state(panel: Dictionary, time_s: float, index: int = 0) -> Array:
	var result: Dictionary = Glazing.evaluate_panel(panel, time_s)
	if not bool(result["valid"]):
		return ["INVALID", NAN]
	for leaf in result["leaves"]:
		if int(leaf["index"]) == index:
			return [String(leaf["state"]), float(leaf["fallout_fraction"])]
	return ["MISSING", NAN]


func _rejected(panel: Variant, message: String) -> void:
	_check(not bool(Glazing.validate_panel(panel)["valid"]), message + " (validate)")
	var evaluated: Dictionary = Glazing.evaluate_panel(panel, 10.0)
	_check(not bool(evaluated["valid"]) and evaluated["leaves"].is_empty() and not evaluated["errors"].is_empty(),
			message + " (evaluate)")


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _code_lines() -> String:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	file.close()
	return "\n".join(lines)


# ---------------------------------------------------------------- tests

func _test_01_always_intact() -> void:
	for events in [[], [_event(0.0, INTACT, 0.0)]]:
		var panel: Dictionary = _one_leaf_panel(events)
		_check(bool(Glazing.validate_panel(panel)["valid"]), "01 intact panel is valid")
		for time_s in [0.0, 1.0, 600.0, 1.0e6]:
			var state: Array = _leaf_state(panel, time_s)
			_check(state[0] == INTACT and float(state[1]) == 0.0, "01 intact at %s s" % time_s)


func _test_02_intact_to_cracked() -> void:
	var panel: Dictionary = _one_leaf_panel([_event(0.0, INTACT, 0.0), _event(60.0, CRACKED, 0.0)])
	var state: Array = _leaf_state(panel, 90.0)
	_check(state[0] == CRACKED and float(state[1]) == 0.0, "02 cracked keeps fraction 0")
	var direct: Dictionary = _one_leaf_panel([_event(60.0, CRACKED, 0.0)])
	_check(_leaf_state(direct, 60.0)[0] == CRACKED, "02 a history may start cracked (INTACT is implicit)")


func _test_03_cracked_to_partial() -> void:
	var panel: Dictionary = _one_leaf_panel([_event(60.0, CRACKED, 0.0), _event(90.0, PARTIAL, 0.35)])
	var state: Array = _leaf_state(panel, 90.0)
	_check(state[0] == PARTIAL and float(state[1]) == 0.35, "03 partial fallout shows only the prescribed fraction")
	_check(float(_leaf_state(panel, 89.999)[1]) == 0.0, "03 no fallout before the partial event")


func _test_04_partial_to_open() -> void:
	var panel: Dictionary = _one_leaf_panel(_full_history())
	var state: Array = _leaf_state(panel, 300.0)
	_check(state[0] == OPEN and float(state[1]) == 1.0, "04 open ends exactly at 1")
	_check(_leaf_state(panel, 1.0e7)[0] == OPEN and float(_leaf_state(panel, 1.0e7)[1]) == 1.0, "04 open stays open")


func _test_05_before_at_after_each_event() -> void:
	var events: Array = _full_history()
	var panel: Dictionary = _one_leaf_panel(events)
	var before_first: Dictionary = Glazing.evaluate_panel(_one_leaf_panel([_event(50.0, CRACKED, 0.0)]), 10.0)
	var leaf0: Dictionary = before_first["leaves"][0]
	_check(leaf0["state"] == INTACT and float(leaf0["fallout_fraction"]) == 0.0, "05 before the first event: INTACT")
	_check(int(leaf0["event_index"]) == -1 and leaf0["event_time_s"] == null, "05 before the first event: no active event")
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var t: float = float(event["time_s"])
		var previous: Array = [INTACT, 0.0]
		if index > 0:
			previous = [events[index - 1]["state"], float(events[index - 1]["fallout_fraction"])]
		if t > 0.0:
			var before: Array = _leaf_state(panel, t - 1.0e-6)
			_check(before[0] == previous[0] and float(before[1]) == float(previous[1]), "05 just before event %d" % index)
		var at: Dictionary = Glazing.evaluate_panel(panel, t)["leaves"][0]
		_check(at["state"] == event["state"] and float(at["fallout_fraction"]) == float(event["fallout_fraction"]),
				"05 exactly at event %d" % index)
		_check(int(at["event_index"]) == index and float(at["event_time_s"]) == t, "05 provenance at event %d" % index)
		var after: Array = _leaf_state(panel, t + 1.0e-6)
		_check(after[0] == event["state"] and float(after[1]) == float(event["fallout_fraction"]), "05 just after event %d" % index)


func _test_06_step_without_interpolation() -> void:
	var panel: Dictionary = _one_leaf_panel(_full_history())
	for time_s in [180.0, 181.0, 200.0, 239.999]:
		_check(float(_leaf_state(panel, time_s)[1]) == 0.25, "06 fraction holds at 0.25 (%s s)" % time_s)
	for time_s in [240.0, 270.0, 299.999]:
		var state: Array = _leaf_state(panel, time_s)
		_check(state[0] == PARTIAL and float(state[1]) == 0.6, "06 fraction holds at 0.6 (%s s)" % time_s)
	for time_s in [120.0, 150.0, 179.999]:
		_check(_leaf_state(panel, time_s)[0] == CRACKED and float(_leaf_state(panel, time_s)[1]) == 0.0,
				"06 no fallout creeps in while cracked (%s s)" % time_s)


func _battery() -> Dictionary:
	var battery: Dictionary = {}
	for time_s in [0.0, 100.0, 150.0, 210.0, 260.0, 400.0]:
		battery["t_%s" % time_s] = Glazing.evaluate_panels([_triple(), _double(), _one_leaf_panel(_full_history())], time_s)
	return battery


func _test_07_determinism(dump_path: String) -> void:
	var first: String = _canonical(_battery())
	var second: String = _canonical(_battery())
	_check(first == second, "07 two evaluations are identical")
	if dump_path.is_empty():
		return
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "07 could not open dump file %s" % dump_path)
		return
	file.store_string(first + "\n")
	file.close()


func _double() -> Dictionary:
	return _panel("double", [
		_leaf("outer", 0, [_event(30.0, CRACKED, 0.0), _event(60.0, PARTIAL, 0.4), _event(120.0, OPEN, 1.0)]),
		_leaf("inner", 1, [_event(200.0, CRACKED, 0.0)]),
	])


func _triple() -> Dictionary:
	return _panel("triple", [
		_leaf("outer", 0, [_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.3), _event(40.0, PARTIAL, 0.5)]),
		_leaf("middle", 1, [_event(50.0, CRACKED, 0.0), _event(90.0, PARTIAL, 0.3)]),
		_leaf("inner", 2, [_event(0.0, INTACT, 0.0), _event(150.0, CRACKED, 0.0), _event(170.0, PARTIAL, 0.3)]),
	], {"glass_type": "laminated", "thickness_m": 0.0064})


func _test_08_order_independence() -> void:
	var reference: String = _canonical(Glazing.evaluate_panels([_triple(), _double()], 175.0))
	var reversed: String = _canonical(Glazing.evaluate_panels([_double(), _triple()], 175.0))
	_check(reference == reversed, "08 panel order does not change the output")
	var shuffled: Dictionary = _triple()
	var leaves: Array = shuffled["leaves"]
	leaves.reverse()
	var shuffled_text: String = _canonical(Glazing.evaluate_panel(shuffled, 175.0))
	_check(shuffled_text == _canonical(Glazing.evaluate_panel(_triple(), 175.0)), "08 leaf order does not change the output")
	var result: Dictionary = Glazing.evaluate_panel(shuffled, 175.0)
	for index in range(result["leaves"].size()):
		_check(int(result["leaves"][index]["index"]) == index, "08 leaves come out sorted by index")
	var duplicate_ids: Dictionary = Glazing.evaluate_panels([_double(), _double()], 10.0)
	_check(not bool(duplicate_ids["valid"]), "08 duplicate panel ids are rejected")


func _test_09_inputs_untouched() -> void:
	var panel: Dictionary = _triple()
	panel["metadata"] = {"source": "prescribed test", "nested": {"a": 1}}
	panel["leaves"][0]["metadata"] = {"note": "outer"}
	var before: String = _canonical(panel)
	Glazing.validate_panel(panel)
	var result: Dictionary = Glazing.evaluate_panel(panel, 45.0)
	Glazing.evaluate_panels([panel], 45.0)
	_check(_canonical(panel) == before, "09 inputs are not modified")
	result["panel"]["metadata"]["nested"]["a"] = 99
	result["leaves"][0]["metadata"]["note"] = "changed"
	result["panel"]["width_m"] = 99.0
	_check(_canonical(panel) == before, "09 output does not alias the input")


func _test_10_multi_leaf_histories() -> void:
	var double: Dictionary = _double()
	var at_150: Dictionary = Glazing.evaluate_panel(double, 150.0)
	_check(at_150["leaves"].size() == 2, "10 double keeps both leaves")
	if at_150["leaves"].size() != 2:
		return
	_check(at_150["leaves"][0]["state"] == OPEN and at_150["leaves"][1]["state"] == INTACT, "10 double leaves evolve independently")
	var at_250: Dictionary = Glazing.evaluate_panel(double, 250.0)
	_check(at_250["leaves"][1]["state"] == CRACKED and float(at_250["leaves"][1]["fallout_fraction"]) == 0.0,
			"10 inner leaf of the double only cracks")
	var triple: Dictionary = _triple()
	var expected: Dictionary = {
		0.0: [[INTACT, 0.0], [INTACT, 0.0], [INTACT, 0.0]],
		25.0: [[PARTIAL, 0.3], [INTACT, 0.0], [INTACT, 0.0]],
		60.0: [[PARTIAL, 0.5], [CRACKED, 0.0], [INTACT, 0.0]],
		100.0: [[PARTIAL, 0.5], [PARTIAL, 0.3], [INTACT, 0.0]],
		160.0: [[PARTIAL, 0.5], [PARTIAL, 0.3], [CRACKED, 0.0]],
		180.0: [[PARTIAL, 0.5], [PARTIAL, 0.3], [PARTIAL, 0.3]],
	}
	for time_s in expected.keys():
		var result: Dictionary = Glazing.evaluate_panel(triple, float(time_s))
		_check(result["leaves"].size() == 3, "10 triple keeps three leaves at %s s" % time_s)
		if result["leaves"].size() != 3:
			continue
		for index in range(3):
			var want: Array = expected[time_s][index]
			var leaf: Dictionary = result["leaves"][index]
			_check(leaf["state"] == want[0] and float(leaf["fallout_fraction"]) == float(want[1]),
					"10 triple leaf %d at %s s is %s/%s" % [index, time_s, want[0], want[1]])
	var summary: Dictionary = Glazing.evaluate_panel(triple, 100.0)["damage_summary"]
	_check(bool(summary["diagnostic_only"]), "10 the damage summary is diagnostic only")
	_check(int(summary["leaf_count_by_state"][PARTIAL]) == 2 and int(summary["leaf_count_by_state"][INTACT]) == 1,
			"10 the damage summary counts leaves by state")


func _test_11_intact_leaf_with_open_leaf() -> void:
	var result: Dictionary = Glazing.evaluate_panel(_double(), 150.0)
	_check(result["leaves"].size() == 2, "11 both leaves are reported")
	if result["leaves"].size() != 2:
		return
	_check(result["leaves"][0]["state"] == OPEN and result["leaves"][1]["state"] == INTACT, "11 one leaf open, one intact")
	_check_no_ventilation(result, "11")


func _test_12_all_leaves_partial() -> void:
	var result: Dictionary = Glazing.evaluate_panel(_triple(), 180.0)
	_check(result["leaves"].size() == 3, "12 all three leaves are reported")
	for leaf in result["leaves"]:
		_check(leaf["state"] == PARTIAL, "12 every leaf has partial fallout")
	_check_no_ventilation(result, "12")


func _check_no_ventilation(result: Dictionary, label: String) -> void:
	var text: String = _canonical(result).to_lower()
	for word in ["ventilat", "opening", "area", "flow", "path", "coincid", "free_", "open_fraction", "pressure", "bernoulli"]:
		_check(not text.contains(word), "%s the output carries nothing like '%s'" % [label, word])
	var summary: Dictionary = result["damage_summary"]
	_check(summary.keys().size() == 2, "%s the summary only has counts and its diagnostic flag" % label)


func _test_13_state_regression() -> void:
	var regressions: Array = [
		[_event(10.0, CRACKED, 0.0), _event(20.0, INTACT, 0.0)],
		[_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.2), _event(30.0, CRACKED, 0.0)],
		[_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.2), _event(30.0, OPEN, 1.0), _event(40.0, PARTIAL, 0.9)],
		[_event(10.0, CRACKED, 0.0), _event(20.0, CRACKED, 0.0)],
		[_event(0.0, INTACT, 0.0), _event(5.0, INTACT, 0.0)],
		_full_history() + [_event(400.0, OPEN, 1.0)],
	]
	for index in range(regressions.size()):
		_rejected(_one_leaf_panel(regressions[index]), "13 regression or repetition %d is rejected" % index)


func _test_14_fraction_decrease() -> void:
	_rejected(_one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.5), _event(30.0, PARTIAL, 0.4)]),
			"14 a decreasing fraction is rejected")
	var equal: Dictionary = _one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.5), _event(30.0, PARTIAL, 0.5)])
	_check(bool(Glazing.validate_panel(equal)["valid"]), "14 a repeated equal fraction is accepted")


func _test_15_cracked_with_fraction() -> void:
	for fraction in [1.0e-12, 0.1, 1.0]:
		_rejected(_one_leaf_panel([_event(10.0, CRACKED, fraction)]), "15 CRACKED with fraction %s is rejected" % fraction)
	_rejected(_one_leaf_panel([_event(10.0, INTACT, 0.2)]), "15 INTACT with fraction is rejected")


func _test_16_partial_bounds() -> void:
	for fraction in [0.0, 1.0]:
		_rejected(_one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, fraction)]),
				"16 PARTIAL_FALLOUT with %s is rejected" % fraction)
	for fraction in [-0.1, 1.1, NAN, INF, -INF]:
		_rejected(_one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, fraction)]),
				"16 fraction %s outside [0, 1] is rejected" % fraction)
	var edge: Dictionary = _one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 1.0e-9), _event(30.0, PARTIAL, 1.0 - 1.0e-9)])
	_check(bool(Glazing.validate_panel(edge)["valid"]), "16 fractions just inside (0, 1) are accepted")


func _test_17_open_fraction() -> void:
	for fraction in [0.0, 0.5, 0.999999, 1.000001]:
		_rejected(_one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.2), _event(30.0, OPEN, fraction)]),
				"17 OPEN with %s is rejected" % fraction)


func _test_18_bad_times() -> void:
	var cases: Dictionary = {
		"repeated": [_event(10.0, CRACKED, 0.0), _event(10.0, PARTIAL, 0.2)],
		"decreasing": [_event(10.0, CRACKED, 0.0), _event(5.0, PARTIAL, 0.2)],
		"negative": [_event(-1.0, CRACKED, 0.0)],
		"nan": [_event(NAN, CRACKED, 0.0)],
		"infinite": [_event(10.0, CRACKED, 0.0), _event(INF, PARTIAL, 0.2)],
	}
	for label in cases.keys():
		_rejected(_one_leaf_panel(cases[label]), "18 %s times are rejected" % label)
	var panel: Dictionary = _one_leaf_panel(_full_history())
	for time_s in [-1.0, NAN, INF]:
		var result: Dictionary = Glazing.evaluate_panel(panel, time_s)
		_check(not bool(result["valid"]), "18 evaluation at %s s is rejected" % time_s)
	_check(bool(Glazing.evaluate_panel(panel, 0.0)["valid"]), "18 evaluation at 0 s is accepted")


func _test_19_bad_geometry() -> void:
	var leaves: Array = [_leaf("pane", 0, [])]
	var overrides: Array = [
		{"width_m": 0.0}, {"width_m": -0.8}, {"width_m": NAN}, {"width_m": INF},
		{"height_m": 0.0}, {"height_m": -1.2}, {"height_m": NAN},
		{"sill_z_m": NAN}, {"sill_z_m": INF},
		{"thickness_m": 0.0}, {"thickness_m": -0.004}, {"thickness_m": NAN},
		{"leaf_spacing_m": -0.01}, {"leaf_spacing_m": NAN}, {"leaf_spacing_m": 0.016},
		{"edge_protection_depth_m": -0.001}, {"edge_protection_depth_m": NAN},
		{"edge_protection_depth_m": 0.4}, {"edge_protection_depth_m": 0.5},
		{"width_m": "0.8"}, {"thickness_m": null},
	]
	for override in overrides:
		_rejected(_panel("bad", leaves, override), "19 invalid geometry %s is rejected" % [override])
	var no_edge: Dictionary = _panel("edge0", leaves, {"edge_protection_depth_m": 0.0})
	_check(bool(Glazing.validate_panel(no_edge)["valid"]), "19 an unprotected edge (0) is accepted")
	var spaced: Dictionary = _panel("spaced", [_leaf("a", 0, []), _leaf("b", 1, [])], {"leaf_spacing_m": 0.0})
	_check(bool(Glazing.validate_panel(spaced)["valid"]), "19 two leaves with zero spacing are accepted")
	var two_bad: Dictionary = _panel("spaced", [_leaf("a", 0, []), _leaf("b", 1, [])], {"leaf_spacing_m": -0.001})
	_rejected(two_bad, "19 two leaves with negative spacing are rejected")
	for key in ["width_m", "height_m", "sill_z_m", "thickness_m", "leaf_spacing_m", "edge_protection_depth_m", "frame_material", "glass_type", "leaves"]:
		var missing: Dictionary = _panel("missing", leaves)
		missing.erase(key)
		_rejected(missing, "19 a panel without %s is rejected" % key)


func _test_20_leaf_count_mismatch() -> void:
	var two: Array = [_leaf("a", 0, []), _leaf("b", 1, [])]
	for count in [1, 3, 0, -1]:
		_rejected(_panel("count", two, {"leaf_count": count, "leaf_spacing_m": 0.016}), "20 leaf_count %d with two leaves is rejected" % count)
	_rejected(_panel("count", two, {"leaf_count": 2.0}), "20 a non-integer leaf_count is rejected")
	_rejected(_panel("count", [], {"leaf_count": 0}), "20 a panel without leaves is rejected")


func _test_21_bad_indices() -> void:
	var cases: Dictionary = {
		"duplicate": [_leaf("a", 0, []), _leaf("b", 0, [])],
		"missing zero": [_leaf("a", 1, []), _leaf("b", 2, [])],
		"negative": [_leaf("a", -1, []), _leaf("b", 0, [])],
		"out of range": [_leaf("a", 0, []), _leaf("b", 2, [])],
	}
	for label in cases.keys():
		_rejected(_panel("idx", cases[label]), "21 %s indices are rejected" % label)
	_rejected(_panel("idx", [_leaf("a", 0, []), {"id": "b", "index": 1.0, "events": []}]), "21 a float index is rejected")
	_rejected(_panel("idx", [_leaf("a", 0, []), _leaf("a", 1, [])]), "21 duplicate leaf ids are rejected")
	_rejected(_panel("idx", [_leaf("", 0, [])]), "21 an empty leaf id is rejected")
	_rejected(_panel("idx", [_leaf("   ", 0, [])]), "21 a blank leaf id is rejected")
	_rejected(_panel("idx", [{"id": "a", "index": 0}]), "21 a leaf without events is rejected")
	_rejected(_panel("idx", [{"id": "a", "index": 0, "events": {}}]), "21 events must be an array")
	_rejected(_panel("idx", ["leaf"]), "21 a leaf must be a dictionary")


func _test_22_bad_types_and_metadata() -> void:
	var leaves: Array = [_leaf("pane", 0, [])]
	for glass in ["float", "Annealed", " annealed", "annealed ", "", "tempered", 3]:
		_rejected(_panel("type", leaves, {"glass_type": glass}), "22 glass_type '%s' is rejected" % [glass])
	_rejected(_panel("type", leaves, {"glass_type": "other"}), "22 'other' without a description is rejected")
	_rejected(_panel("type", leaves, {"glass_type": "other", "metadata": {"glass_type_description": "  "}}),
			"22 'other' with a blank description is rejected")
	var other: Dictionary = _panel("type", leaves, {"glass_type": "other", "metadata": {"glass_type_description": "wired glass"}})
	_check(bool(Glazing.validate_panel(other)["valid"]), "22 'other' with a description is accepted")
	_check(Glazing.evaluate_panel(other, 1.0)["panel"]["glass_type"] == "other", "22 'other' is not converted into a known type")
	for glass in ["annealed", "toughened", "laminated"]:
		_check(bool(Glazing.validate_panel(_panel("type", leaves, {"glass_type": glass}))["valid"]), "22 %s is accepted" % glass)
	for frame in ["", "   ", null, 7]:
		_rejected(_panel("frame", leaves, {"frame_material": frame}), "22 frame_material '%s' is rejected" % [frame])
	_rejected(_panel("meta", leaves, {"metadata": "note"}), "22 panel metadata must be a dictionary")
	_rejected(_panel("meta", [_leaf("pane", 0, [], ["note"])]), "22 leaf metadata must be a dictionary")
	_rejected(_panel("", leaves), "22 an empty panel id is rejected")
	_rejected(_panel("state", [_leaf("pane", 0, [_event(1.0, "cracked", 0.0)])]), "22 lowercase state is rejected")
	_rejected(_panel("state", [_leaf("pane", 0, [_event(1.0, "BROKEN", 0.0)])]), "22 unknown state is rejected")
	_rejected(_panel("state", [_leaf("pane", 0, [{"time_s": 1.0, "state": CRACKED}])]), "22 an event without fraction is rejected")
	_rejected("panel", "22 a non-dictionary panel is rejected")


func _test_23_provenance_preserved() -> void:
	var panel: Dictionary = _panel("prov", [_leaf("pane", 0, [_event(5.0, CRACKED, 0.0)], {"origin": "prescribed history A"})], {
		"glass_type": "toughened",
		"thickness_m": 0.006,
		"frame_material": "aluminium",
		"edge_protection_depth_m": 0.02,
		"width_m": 0.7,
		"height_m": 1.9,
		"sill_z_m": 0.1,
		"metadata": {"source": "test fixture"},
	})
	var result: Dictionary = Glazing.evaluate_panel(panel, 10.0)
	var description: Dictionary = result["panel"]
	_check(description["glass_type"] == "toughened" and float(description["thickness_m"]) == 0.006, "23 type and thickness are kept")
	_check(description["frame_material"] == "aluminium" and float(description["edge_protection_depth_m"]) == 0.02, "23 frame and edge are kept")
	_check(float(description["width_m"]) == 0.7 and float(description["height_m"]) == 1.9 and float(description["sill_z_m"]) == 0.1,
			"23 geometry is kept")
	_check(int(description["leaf_count"]) == 1 and float(description["leaf_spacing_m"]) == 0.0, "23 leaf count and spacing are kept")
	_check(description["metadata"]["source"] == "test fixture", "23 panel metadata is kept")
	var leaf: Dictionary = result["leaves"][0]
	_check(leaf["source"] == "prescribed" and leaf["metadata"]["origin"] == "prescribed history A", "23 leaf provenance is kept")
	_check(float(result["time_s"]) == 10.0, "23 the evaluated time is reported")
	# Claves ajenas (temperatura, flujo de calor) no entran en el estado.
	var hot: Dictionary = _one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.3)])
	var hot_reference: String = _canonical(Glazing.evaluate_panel(hot, 25.0)["leaves"])
	var decorated: Dictionary = hot.duplicate(true)
	decorated["temperature_c"] = 900.0
	decorated["heat_flux_kw_m2"] = 25.0
	decorated["leaves"][0]["temperature_c"] = 650.0
	decorated["leaves"][0]["events"][1]["temperature_c"] = 700.0
	decorated["leaves"][0]["events"][1]["seed"] = 42
	_check(_canonical(Glazing.evaluate_panel(decorated, 25.0)["leaves"]) == hot_reference,
			"23 temperature, heat flux and seeds do not change the prescribed state")
	# Tipo, espesor, marco y borde no cambian el estado prescrito.
	var reference: Array = _leaf_state(panel, 10.0)
	for variant in [{"glass_type": "laminated"}, {"thickness_m": 0.012}, {"frame_material": "steel"}, {"edge_protection_depth_m": 0.0}]:
		var other: Dictionary = panel.duplicate(true)
		for key in variant.keys():
			other[key] = variant[key]
		_check(_leaf_state(other, 10.0) == reference, "23 %s does not change the prescribed state" % [variant])


func _test_24_no_forbidden_physics_in_source() -> void:
	var code: String = _code_lines()
	_check(not code.is_empty(), "24 the model source is readable")
	var lowered: String = code.to_lower()
	for word in ["temperat", "temp_", "_c\"", "pressure", "bernoulli", "flow", "sqrt(", "pow(", "rand", "seed", "noise",
			"area", "opening", "ventilat", "preload(", "load(", "time.", "os.", "node", "gravity", "break1"]:
		_check(not lowered.contains(word), "24 the model code has no '%s'" % word)
	_check(not code.contains("class_name"), "24 the model registers no global class")
	_check(code.begins_with("extends RefCounted"), "24 the model is a RefCounted")


func _test_25_no_door_state_in_source() -> void:
	var code: String = _code_lines()
	for word in ["open_fraction", "thermal_gap_fraction", "OpeningModel", "BuildingModel", "SimulationEngine", "GasExchangeSystem"]:
		_check(not code.contains(word), "25 the model code has no '%s'" % word)


func _test_26_no_skipped_states() -> void:
	var skips: Array = [
		[_event(10.0, PARTIAL, 0.2)],
		[_event(10.0, OPEN, 1.0)],
		[_event(0.0, INTACT, 0.0), _event(10.0, PARTIAL, 0.2)],
		[_event(10.0, CRACKED, 0.0), _event(20.0, OPEN, 1.0)],
		[_event(0.0, INTACT, 0.0), _event(10.0, OPEN, 1.0)],
	]
	for index in range(skips.size()):
		_rejected(_one_leaf_panel(skips[index]), "26 skipped state %d is rejected" % index)


func _test_27_output_has_no_ventilation() -> void:
	for time_s in [0.0, 150.0, 400.0]:
		var result: Dictionary = Glazing.evaluate_panel(_one_leaf_panel(_full_history()), time_s)
		_check_no_ventilation(result, "27 (%s s)" % time_s)
		var keys: Array = result.keys()
		keys.sort()
		_check(keys == ["damage_summary", "errors", "leaves", "panel", "time_s", "valid"], "27 result keys are fixed (%s s)" % time_s)
		for leaf in result["leaves"]:
			var leaf_keys: Array = leaf.keys()
			leaf_keys.sort()
			_check(leaf_keys == ["event_index", "event_time_s", "fallout_fraction", "id", "index", "metadata", "source", "state"],
					"27 leaf keys are fixed (%s s)" % time_s)


func _test_28_repeated_partial_progress() -> void:
	var panel: Dictionary = _one_leaf_panel([_event(10.0, CRACKED, 0.0), _event(20.0, PARTIAL, 0.1), _event(25.0, PARTIAL, 0.2),
			_event(30.0, PARTIAL, 0.7), _event(35.0, OPEN, 1.0)])
	_check(bool(Glazing.validate_panel(panel)["valid"]), "28 progressive partial fallout is accepted")
	var expected: Array = [[22.0, 0.1], [27.0, 0.2], [33.0, 0.7], [36.0, 1.0]]
	for pair in expected:
		_check(float(_leaf_state(panel, float(pair[0]))[1]) == float(pair[1]), "28 fraction at %s s" % pair[0])
