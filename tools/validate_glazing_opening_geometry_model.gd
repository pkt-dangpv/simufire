extends SceneTree

## Tests deterministas de la geometria del camino libre por desprendimiento de
## vidrio (sim/core/GlazingOpeningGeometryModel.gd, fase 3B). Las instantaneas se
## obtienen con el modelo de integridad prescrita de la fase 3A. No arranca el
## motor ni carga escenarios.
##
##   <godot> --headless --path . --script res://tools/validate_glazing_opening_geometry_model.gd
##   <godot> --headless --path . --script res://tools/validate_glazing_opening_geometry_model.gd -- --dump=<ruta.json>

const Geometry := preload("res://sim/core/GlazingOpeningGeometryModel.gd")
const Integrity := preload("res://sim/core/GlazingIntegrityModel.gd")
const MODEL_PATH: String = "res://sim/core/GlazingOpeningGeometryModel.gd"

const W: float = 1.0
const H: float = 2.0
const SILL: float = 0.75
const PANEL_AREA: float = W * H
const TOL: float = 1.0e-12
const EVAL_TIME: float = 100.0

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var dump_path: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump_path = argument.substr("--dump=".length())
	_test_01_intact()
	_test_02_cracked()
	_test_03_single_rectangle()
	_test_04_two_disjoint_regions()
	_test_05_overlapping_regions()
	_test_06_open_leaf()
	_test_07_two_open_leaves()
	_test_08_open_and_partial()
	_test_09_open_and_intact()
	_test_10_identical_partials()
	_test_11_partially_overlapping_partials()
	_test_12_same_fraction_no_overlap()
	_test_13_three_leaves_small_common()
	_test_14_three_leaves_pairwise_only()
	_test_15_several_rectangles()
	_test_16_non_rectangular_hole()
	_test_17_local_and_global_heights()
	_test_18_regions_on_the_edges()
	_test_19_region_outside()
	_test_20_bad_dimensions()
	_test_21_bad_leaves()
	_test_22_bad_region_ids()
	_test_23_regions_on_intact_or_cracked()
	_test_24_partial_without_regions()
	_test_25_fraction_mismatch()
	_test_26_overlap_counted_once_for_the_fraction()
	_test_27_order_independence()
	_test_28_determinism(dump_path)
	_test_29_inputs_untouched()
	_test_30_output_is_geometry_only()
	_test_31_open_with_regions_rejected()
	_test_32_bad_snapshots()
	_test_33_islands_and_gaps()
	if _failures.is_empty():
		print("  %d checks" % _checks)
		print("GLAZING OPENING GEOMETRY MODEL VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: " + failure)
	print("GLAZING OPENING GEOMETRY MODEL VALIDATION FAIL (%d)" % _failures.size())
	quit(1)


# ---------------------------------------------------------------- helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tol: float = TOL) -> bool:
	if is_nan(actual) or is_nan(expected):
		return false
	return absf(actual - expected) <= tol * maxf(1.0, absf(expected))


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _region(region_id: String, x: float, z: float, w: float, h: float) -> Dictionary:
	return {"id": region_id, "x_m": x, "z_m": z, "width_m": w, "height_m": h}


## Historia 3A que termina en el estado pedido con la fraccion pedida.
func _events(state: String, fraction: float) -> Array:
	match state:
		"INTACT":
			return []
		"CRACKED":
			return [{"time_s": 10.0, "state": "CRACKED", "fallout_fraction": 0.0}]
		"PARTIAL_FALLOUT":
			return [
				{"time_s": 10.0, "state": "CRACKED", "fallout_fraction": 0.0},
				{"time_s": 20.0, "state": "PARTIAL_FALLOUT", "fallout_fraction": fraction},
			]
		_:
			return [
				{"time_s": 10.0, "state": "CRACKED", "fallout_fraction": 0.0},
				{"time_s": 20.0, "state": "PARTIAL_FALLOUT", "fallout_fraction": 0.5},
				{"time_s": 30.0, "state": "OPEN", "fallout_fraction": 1.0},
			]


## specs: [[leaf_id, state, [regions]], ...] en orden de indice.
## Devuelve [snapshot, spatial]. La fraccion prescrita es la de la union exacta.
func _case(specs: Array, fraction_overrides: Dictionary = {}) -> Array:
	var leaves: Array = []
	var spatial_leaves: Array = []
	for index in range(specs.size()):
		var spec: Array = specs[index]
		var fraction: float = 0.0
		if fraction_overrides.has(spec[0]):
			fraction = float(fraction_overrides[spec[0]])
		elif String(spec[1]) == "PARTIAL_FALLOUT":
			fraction = _union_area(spec[2]) / PANEL_AREA
		leaves.append({"id": spec[0], "index": index, "events": _events(String(spec[1]), fraction)})
		spatial_leaves.append({"id": spec[0], "index": index, "regions": Array(spec[2]).duplicate(true)})
	var panel: Dictionary = {
		"id": "pane_a", "width_m": W, "height_m": H, "sill_z_m": SILL,
		"glass_type": "annealed", "thickness_m": 0.004, "leaf_count": specs.size(),
		"leaf_spacing_m": 0.0 if specs.size() == 1 else 0.012,
		"frame_material": "timber", "edge_protection_depth_m": 0.01, "leaves": leaves,
	}
	var snapshot: Dictionary = Integrity.evaluate_panel(panel, EVAL_TIME)
	return [snapshot, {"panel_id": "pane_a", "leaves": spatial_leaves}]


## Area exacta de la union (para construir fracciones de prueba), por
## inclusion-exclusion sobre la rejilla.
func _union_area(regions: Array) -> float:
	if regions.is_empty():
		return 0.0
	var xs: Array = []
	var zs: Array = []
	for r in regions:
		xs.append(float(r["x_m"]))
		xs.append(float(r["x_m"]) + float(r["width_m"]))
		zs.append(float(r["z_m"]))
		zs.append(float(r["z_m"]) + float(r["height_m"]))
	xs.sort()
	zs.sort()
	var area: float = 0.0
	for i in range(xs.size() - 1):
		for j in range(zs.size() - 1):
			if xs[i + 1] <= xs[i] or zs[j + 1] <= zs[j]:
				continue
			for r in regions:
				if float(r["x_m"]) <= xs[i] and xs[i + 1] <= float(r["x_m"]) + float(r["width_m"]) \
						and float(r["z_m"]) <= zs[j] and zs[j + 1] <= float(r["z_m"]) + float(r["height_m"]):
					area += (xs[i + 1] - xs[i]) * (zs[j + 1] - zs[j])
					break
	return area


func _run(specs: Array, fraction_overrides: Dictionary = {}) -> Dictionary:
	var pair: Array = _case(specs, fraction_overrides)
	var result: Dictionary = Geometry.compute_open_geometry(pair[0], pair[1])
	if bool(result["valid"]):
		_check_conservation(result, specs)
	return result


## Area de la interseccion calculada aparte: rejilla propia y prueba del punto
## medio de cada celda (el modelo usa contencion de la celda entera).
func _intersection_area(specs: Array) -> float:
	var xs: Array = [0.0, W]
	var zs: Array = [0.0, H]
	for spec in specs:
		for r in spec[2]:
			xs.append(float(r["x_m"]))
			xs.append(float(r["x_m"]) + float(r["width_m"]))
			zs.append(float(r["z_m"]))
			zs.append(float(r["z_m"]) + float(r["height_m"]))
	xs.sort()
	zs.sort()
	var area: float = 0.0
	for i in range(xs.size() - 1):
		for j in range(zs.size() - 1):
			if xs[i + 1] <= xs[i] or zs[j + 1] <= zs[j]:
				continue
			var mx: float = 0.5 * (xs[i] + xs[i + 1])
			var mz: float = 0.5 * (zs[j] + zs[j + 1])
			var everywhere: bool = true
			for spec in specs:
				var inside: bool = String(spec[1]) == "OPEN"
				for r in spec[2]:
					if float(r["x_m"]) < mx and mx < float(r["x_m"]) + float(r["width_m"]) 							and float(r["z_m"]) < mz and mz < float(r["z_m"]) + float(r["height_m"]):
						inside = true
				if not inside:
					everywhere = false
					break
			if everywhere:
				area += (xs[i + 1] - xs[i]) * (zs[j + 1] - zs[j])
	return area


func _check_conservation(result: Dictionary, specs: Array) -> void:
	var open_area: float = float(result["open_area_m2"])
	_check(_close(open_area, _intersection_area(specs), 1.0e-9),
			"conservation: open area %s equals the independent intersection %s" % [open_area, _intersection_area(specs)])
	var all_open: bool = true
	for spec in specs:
		all_open = all_open and String(spec[1]) == "OPEN"
	if all_open:
		_check(open_area == float(result["panel_area_m2"]), "conservation: all-open leaves give the panel area")
	if specs.size() == 1 and String(specs[0][1]) == "PARTIAL_FALLOUT":
		_check(_close(open_area, _union_area(specs[0][2]), 1.0e-9), "conservation: a single partial leaf opens its union")
	_check(_close(float(result["panel_area_m2"]), PANEL_AREA), "conservation: panel area is width*height")


func _rejected(result: Dictionary, message: String) -> void:
	_check(not bool(result["valid"]) and not result["errors"].is_empty() and result["rectangles"].is_empty()
			and float(result["open_area_m2"]) == 0.0, message)


## Cubre el punto (x, z)?
func _covers(rectangles: Array, x: float, z: float) -> bool:
	for r in rectangles:
		if float(r["local_x_m"]) <= x and x <= float(r["local_x_m"]) + float(r["width_m"]) \
				and float(r["local_z_m"]) <= z and z <= float(r["local_z_m"]) + float(r["height_m"]):
			return true
	return false


## Accesos con guarda: una mutacion no debe convertir un FAIL en SCRIPT ERROR.
func _rect_contributors(result: Dictionary, index: int) -> Array:
	if index >= result["rectangles"].size():
		return []
	return result["rectangles"][index]["contributors"]


func _leaf_union_area(result: Dictionary, index: int) -> float:
	if index >= result["leaf_union_areas_m2"].size():
		return NAN
	return float(result["leaf_union_areas_m2"][index]["union_area_m2"])


func _geometry(result: Dictionary) -> Array:
	var out: Array = []
	for r in result["rectangles"]:
		out.append([float(r["local_x_m"]), float(r["local_z_m"]), float(r["width_m"]), float(r["height_m"])])
	return out


## Igualdad geometrica con tolerancia de redondeo: los anchos salen de restar
## bordes en coma flotante (0.6 - 0.4 no es 0.2 exacto).
func _same_geometry(result: Dictionary, expected: Array) -> bool:
	var actual: Array = _geometry(result)
	if actual.size() != expected.size():
		return false
	for i in range(actual.size()):
		for k in range(4):
			if not _close(float(actual[i][k]), float(expected[i][k])):
				return false
	return true


## Invariantes de conservacion comunes a todo resultado valido.
func _check_invariants(result: Dictionary, label: String) -> void:
	_check(bool(result["valid"]), "%s is valid" % label)
	if not bool(result["valid"]):
		return
	var rectangles: Array = result["rectangles"]
	var total: float = 0.0
	for index in range(rectangles.size()):
		var r: Dictionary = rectangles[index]
		var x: float = float(r["local_x_m"])
		var z: float = float(r["local_z_m"])
		var w: float = float(r["width_m"])
		var h: float = float(r["height_m"])
		_check(w > 0.0 and h > 0.0, "%s rectangle %d has positive size" % [label, index])
		_check(x >= 0.0 and z >= 0.0 and x + w <= W + TOL and z + h <= H + TOL, "%s rectangle %d lies inside the panel" % [label, index])
		_check(float(r["area_m2"]) == w * h, "%s rectangle %d area is width*height" % [label, index])
		_check(float(r["global_sill_z_m"]) == SILL + z, "%s rectangle %d global height is sill + local" % [label, index])
		_check(r["source"] == "glazing_fallout", "%s rectangle %d source" % [label, index])
		_check(r["id"] == "fallout_path_%03d" % index, "%s rectangle %d id is canonical" % [label, index])
		total += float(r["area_m2"])
		if index > 0:
			var p: Dictionary = rectangles[index - 1]
			var ordered: bool = float(p["local_z_m"]) < z or (float(p["local_z_m"]) == z and float(p["local_x_m"]) < x)
			_check(ordered, "%s rectangles are ordered by height then x" % label)
		for other_index in range(index + 1, rectangles.size()):
			var o: Dictionary = rectangles[other_index]
			var overlap_w: float = minf(x + w, float(o["local_x_m"]) + float(o["width_m"])) - maxf(x, float(o["local_x_m"]))
			var overlap_h: float = minf(z + h, float(o["local_z_m"]) + float(o["height_m"])) - maxf(z, float(o["local_z_m"]))
			_check(overlap_w <= 0.0 or overlap_h <= 0.0, "%s rectangles %d and %d are disjoint" % [label, index, other_index])
	_check(float(result["open_area_m2"]) == total, "%s open area is the sum of the rectangles" % label)
	_check(total >= 0.0 and total <= PANEL_AREA * (1.0 + TOL), "%s open area stays within the panel" % label)
	for union in result["leaf_union_areas_m2"]:
		_check(total <= float(union["union_area_m2"]) * (1.0 + TOL) + TOL,
				"%s open area never exceeds leaf %s missing area" % [label, union["leaf_id"]])


# ---------------------------------------------------------------- tests

func _test_01_intact() -> void:
	var result: Dictionary = _run([["pane", "INTACT", []]])
	_check_invariants(result, "01")
	_check(result["rectangles"].is_empty() and float(result["open_area_m2"]) == 0.0, "01 an intact leaf opens nothing")


func _test_02_cracked() -> void:
	var result: Dictionary = _run([["pane", "CRACKED", []]])
	_check_invariants(result, "02")
	_check(result["rectangles"].is_empty() and float(result["open_area_m2"]) == 0.0, "02 a cracked leaf opens nothing")


func _test_03_single_rectangle() -> void:
	var result: Dictionary = _run([["pane", "PARTIAL_FALLOUT", [_region("r1", 0.2, 0.5, 0.3, 0.4)]]])
	_check_invariants(result, "03")
	_check(_same_geometry(result, [[0.2, 0.5, 0.3, 0.4]]), "03 the output is exactly the fallen rectangle")
	var contributors: Array = _rect_contributors(result, 0)
	_check(contributors.size() == 1 and contributors[0]["region_ids"] == ["r1"] and contributors[0]["leaf_id"] == "pane",
			"03 provenance names the region")
	_check(_close(float(result["open_area_m2"]), _leaf_union_area(result, 0)),
			"03 a single partial leaf opens exactly its union")


func _test_04_two_disjoint_regions() -> void:
	var result: Dictionary = _run([["pane", "PARTIAL_FALLOUT", [_region("low", 0.1, 0.1, 0.2, 0.2), _region("high", 0.6, 1.5, 0.3, 0.3)]]])
	_check_invariants(result, "04")
	_check(_same_geometry(result, [[0.1, 0.1, 0.2, 0.2], [0.6, 1.5, 0.3, 0.3]]), "04 two disjoint regions give two rectangles")
	_check(_close(float(result["open_area_m2"]), 0.04 + 0.09), "04 area of two disjoint regions")


func _test_05_overlapping_regions() -> void:
	var regions: Array = [_region("a", 0.0, 0.0, 0.6, 0.6), _region("b", 0.4, 0.4, 0.6, 0.6)]
	var result: Dictionary = _run([["pane", "PARTIAL_FALLOUT", regions]])
	_check_invariants(result, "05")
	var union: float = 0.36 + 0.36 - 0.04
	_check(_close(float(result["open_area_m2"]), union), "05 overlapping regions count once (%s)" % result["open_area_m2"])
	_check(_close(_leaf_union_area(result, 0), union), "05 the leaf union counts the overlap once")
	var shared: int = 0
	for r in result["rectangles"]:
		if not r["contributors"].is_empty() and r["contributors"][0]["region_ids"] == ["a", "b"]:
			shared += 1
			_check(_close(float(r["area_m2"]), 0.04), "05 the shared part is 0.2 x 0.2")
	_check(shared == 1, "05 exactly one rectangle is covered by both regions")


func _test_06_open_leaf() -> void:
	var result: Dictionary = _run([["pane", "OPEN", []]])
	_check_invariants(result, "06")
	_check(_same_geometry(result, [[0.0, 0.0, W, H]]), "06 an open leaf opens the whole panel")
	var contributors: Array = _rect_contributors(result, 0)
	_check(contributors.size() == 1 and contributors[0]["leaf_state"] == "OPEN"
			and contributors[0]["region_ids"].is_empty(), "06 open provenance has no regions")


func _test_07_two_open_leaves() -> void:
	var result: Dictionary = _run([["outer", "OPEN", []], ["inner", "OPEN", []]])
	_check_invariants(result, "07")
	_check(_same_geometry(result, [[0.0, 0.0, W, H]]), "07 two open leaves open the whole panel")
	_check(float(result["open_area_m2"]) == PANEL_AREA, "07 all open leaves give exactly the panel area")
	_check(_rect_contributors(result, 0).size() == 2, "07 both leaves are named")


func _test_08_open_and_partial() -> void:
	var hole: Dictionary = _region("h", 0.3, 0.9, 0.4, 0.5)
	var result: Dictionary = _run([["outer", "OPEN", []], ["inner", "PARTIAL_FALLOUT", [hole]]])
	_check_invariants(result, "08")
	_check(_same_geometry(result, [[0.3, 0.9, 0.4, 0.5]]), "08 open + partial equals the partial hole")
	var alone: Dictionary = _run([["inner", "PARTIAL_FALLOUT", [hole]]])
	_check(_same_geometry(result, _geometry(alone)), "08 same geometry as the partial leaf alone")


func _test_09_open_and_intact() -> void:
	for specs in [[["outer", "OPEN", []], ["inner", "INTACT", []]], [["outer", "INTACT", []], ["inner", "OPEN", []]],
			[["outer", "OPEN", []], ["inner", "CRACKED", []]]]:
		var result: Dictionary = _run(specs)
		_check_invariants(result, "09")
		_check(result["rectangles"].is_empty() and float(result["open_area_m2"]) == 0.0,
				"09 an intact or cracked leaf blocks an open one (%s/%s)" % [specs[0][1], specs[1][1]])


func _test_10_identical_partials() -> void:
	var hole: Dictionary = _region("h", 0.25, 0.25, 0.5, 0.5)
	var result: Dictionary = _run([["outer", "PARTIAL_FALLOUT", [hole]], ["inner", "PARTIAL_FALLOUT", [hole]]])
	_check_invariants(result, "10")
	_check(_same_geometry(result, [[0.25, 0.25, 0.5, 0.5]]), "10 identical holes pass through")


func _test_11_partially_overlapping_partials() -> void:
	var result: Dictionary = _run([
		["outer", "PARTIAL_FALLOUT", [_region("o", 0.0, 0.0, 0.6, 0.6)]],
		["inner", "PARTIAL_FALLOUT", [_region("i", 0.4, 0.2, 0.6, 0.6)]],
	])
	_check_invariants(result, "11")
	_check(_same_geometry(result, [[0.4, 0.2, 0.2, 0.4]]), "11 only the overlap is open (%s)" % [_geometry(result)])
	_check(_close(float(result["open_area_m2"]), 0.08), "11 overlap area 0.08")
	var contributors: Array = _rect_contributors(result, 0)
	_check(contributors.size() == 2 and contributors[0]["region_ids"] == ["o"] and contributors[1]["region_ids"] == ["i"], "11 both leaves' regions are named")


func _test_12_same_fraction_no_overlap() -> void:
	var result: Dictionary = _run([
		["outer", "PARTIAL_FALLOUT", [_region("left", 0.0, 0.0, 0.5, 1.0)]],
		["inner", "PARTIAL_FALLOUT", [_region("right", 0.5, 1.0, 0.5, 1.0)]],
	])
	_check_invariants(result, "12")
	var unions: Array = result["leaf_union_areas_m2"]
	_check(unions.size() == 2 and float(unions[0]["prescribed_fallout_fraction"]) == float(unions[1]["prescribed_fallout_fraction"]),
			"12 both leaves have the same fraction")
	_check(result["rectangles"].is_empty() and float(result["open_area_m2"]) == 0.0, "12 same fraction without overlap opens nothing")
	# Tocarse solo en una esquina tampoco abre nada.
	var touching: Dictionary = _run([
		["outer", "PARTIAL_FALLOUT", [_region("a", 0.0, 0.0, 0.5, 1.0)]],
		["inner", "PARTIAL_FALLOUT", [_region("b", 0.5, 0.0, 0.5, 1.0)]],
	])
	_check(touching["rectangles"].is_empty(), "12 regions that only share an edge open nothing")


func _test_13_three_leaves_small_common() -> void:
	var result: Dictionary = _run([
		["a", "PARTIAL_FALLOUT", [_region("ra", 0.0, 0.0, 0.6, 0.6)]],
		["b", "PARTIAL_FALLOUT", [_region("rb", 0.5, 0.0, 0.5, 0.6)]],
		["c", "PARTIAL_FALLOUT", [_region("rc", 0.0, 0.5, 1.0, 0.5)]],
	])
	_check_invariants(result, "13")
	_check(_same_geometry(result, [[0.5, 0.5, 0.1, 0.1]]), "13 three leaves share a small common square (%s)" % [_geometry(result)])
	_check(_rect_contributors(result, 0).size() == 3, "13 three contributors")


func _test_14_three_leaves_pairwise_only() -> void:
	var a: Dictionary = _region("ra", 0.0, 0.0, 0.6, 0.4)
	var b: Dictionary = _region("rb", 0.4, 0.0, 0.6, 0.4)
	var c1: Dictionary = _region("rc1", 0.0, 0.0, 0.4, 0.4)
	var c2: Dictionary = _region("rc2", 0.6, 0.0, 0.4, 0.4)
	var ab: Dictionary = _run([["a", "PARTIAL_FALLOUT", [a]], ["b", "PARTIAL_FALLOUT", [b]]])
	var ac: Dictionary = _run([["a", "PARTIAL_FALLOUT", [a]], ["c", "PARTIAL_FALLOUT", [c1, c2]]])
	var bc: Dictionary = _run([["b", "PARTIAL_FALLOUT", [b]], ["c", "PARTIAL_FALLOUT", [c1, c2]]])
	_check(float(ab["open_area_m2"]) > 0.0 and float(ac["open_area_m2"]) > 0.0 and float(bc["open_area_m2"]) > 0.0,
			"14 every pair overlaps")
	var abc: Dictionary = _run([["a", "PARTIAL_FALLOUT", [a]], ["b", "PARTIAL_FALLOUT", [b]], ["c", "PARTIAL_FALLOUT", [c1, c2]]])
	_check_invariants(abc, "14")
	_check(abc["rectangles"].is_empty() and float(abc["open_area_m2"]) == 0.0, "14 no common path across the three leaves")


func _test_15_several_rectangles() -> void:
	var result: Dictionary = _run([
		["outer", "PARTIAL_FALLOUT", [_region("band_low", 0.0, 0.2, 1.0, 0.2), _region("band_high", 0.0, 1.4, 1.0, 0.2)]],
		["inner", "PARTIAL_FALLOUT", [_region("col_left", 0.1, 0.0, 0.2, 2.0), _region("col_right", 0.7, 0.0, 0.2, 2.0)]],
	])
	_check_invariants(result, "15")
	_check(_same_geometry(result, [[0.1, 0.2, 0.2, 0.2], [0.7, 0.2, 0.2, 0.2], [0.1, 1.4, 0.2, 0.2], [0.7, 1.4, 0.2, 0.2]]),
			"15 two bands x two columns give four rectangles (%s)" % [_geometry(result)])
	_check(_close(float(result["open_area_m2"]), 4.0 * 0.04), "15 four crossings")


func _l_shape_regions() -> Array:
	return [_region("foot", 0.0, 0.0, 0.8, 0.3), _region("leg", 0.0, 0.3, 0.3, 0.9)]


func _test_16_non_rectangular_hole() -> void:
	var result: Dictionary = _run([["pane", "PARTIAL_FALLOUT", _l_shape_regions()]])
	_check_invariants(result, "16")
	_check(_close(float(result["open_area_m2"]), 0.24 + 0.27), "16 L-shaped hole area")
	_check(float(result["open_area_m2"]) < 0.8 * 1.2 - 0.1, "16 the L is not its bounding box")
	_check(_covers(result["rectangles"], 0.7, 0.1) and _covers(result["rectangles"], 0.1, 1.1), "16 both arms are open")
	_check(not _covers(result["rectangles"], 0.6, 0.8), "16 the notch of the L stays closed")
	_check(result["rectangles"].size() == 2, "16 the L is two rectangles")


func _test_17_local_and_global_heights() -> void:
	var result: Dictionary = _run([["pane", "PARTIAL_FALLOUT", [_region("r", 0.1, 1.25, 0.2, 0.5)]]])
	_check(result["rectangles"].size() == 1, "17 one rectangle")
	if result["rectangles"].size() != 1:
		return
	var r: Dictionary = result["rectangles"][0]
	_check(float(r["local_z_m"]) == 1.25, "17 local height is kept")
	_check(float(r["global_sill_z_m"]) == SILL + 1.25, "17 global height adds the panel sill")
	_check(float(result["panel_sill_z_m"]) == SILL and float(result["panel_width_m"]) == W and float(result["panel_height_m"]) == H,
			"17 panel geometry is reported")


func _test_18_regions_on_the_edges() -> void:
	var regions: Array = [
		_region("bottom", 0.4, 0.0, 0.2, 0.1),
		_region("top", 0.4, H - 0.1, 0.2, 0.1),
		_region("left", 0.0, 0.9, 0.1, 0.2),
		_region("right", W - 0.1, 0.9, 0.1, 0.2),
	]
	var result: Dictionary = _run([["pane", "PARTIAL_FALLOUT", regions]])
	_check_invariants(result, "18")
	_check(result["rectangles"].size() == 4, "18 four edge regions are accepted")
	_check(_close(float(result["open_area_m2"]), 4.0 * 0.02), "18 edge regions area")


func _test_19_region_outside() -> void:
	var outside: Array = [
		_region("x_neg", -0.01, 0.0, 0.2, 0.2),
		_region("z_neg", 0.0, -0.01, 0.2, 0.2),
		_region("x_over", 0.9, 0.0, 0.2, 0.2),
		_region("z_over", 0.0, 1.9, 0.2, 0.2),
		_region("far", 5.0, 5.0, 0.1, 0.1),
		_region("barely", 0.8, 0.0, 0.2 + 1.0e-9, 0.2),
	]
	for region in outside:
		var pair: Array = _case([["pane", "PARTIAL_FALLOUT", [region]]], {"pane": 0.02})
		_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "19 region %s outside the panel is rejected" % region["id"])


func _test_20_bad_dimensions() -> void:
	var bad: Array = [
		_region("w0", 0.1, 0.1, 0.0, 0.2), _region("h0", 0.1, 0.1, 0.2, 0.0),
		_region("wneg", 0.3, 0.1, -0.2, 0.2), _region("hneg", 0.1, 0.3, 0.2, -0.2),
		_region("wnan", 0.1, 0.1, NAN, 0.2), _region("hinf", 0.1, 0.1, 0.2, INF),
		_region("xnan", NAN, 0.1, 0.2, 0.2), _region("zinf", 0.1, INF, 0.2, 0.2),
		{"id": "wtext", "x_m": 0.1, "z_m": 0.1, "width_m": "0.2", "height_m": 0.2},
		{"id": "missing", "x_m": 0.1, "z_m": 0.1, "width_m": 0.2},
	]
	for region in bad:
		var pair: Array = _case([["pane", "PARTIAL_FALLOUT", [region]]], {"pane": 0.02})
		_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "20 region %s is rejected" % region["id"])
	var bad_meta: Dictionary = _region("meta", 0.1, 0.1, 0.2, 0.2)
	bad_meta["metadata"] = "note"
	var pair: Array = _case([["pane", "PARTIAL_FALLOUT", [bad_meta]]], {"pane": 0.02})
	_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "20 non-dictionary region metadata is rejected")
	# Una region valida no tapa otra degenerada en la misma hoja.
	for degenerate in [_region("flat", 0.5, 0.5, 0.0, 0.2), _region("thin", 0.5, 0.5, 0.2, 0.0),
			_region("back", 0.7, 0.5, -0.2, 0.2), _region("down", 0.5, 0.7, 0.2, -0.2)]:
		var mixed: Array = _case([["pane", "PARTIAL_FALLOUT", [_region("ok", 0.1, 0.1, 0.2, 0.2), degenerate]]], {"pane": 0.02})
		_rejected(Geometry.compute_open_geometry(mixed[0], mixed[1]), "20 a degenerate region %s next to a valid one is rejected" % degenerate["id"])
	var good_meta: Dictionary = _region("meta", 0.1, 0.1, 0.2, 0.2)
	good_meta["metadata"] = {"origin": "prescribed"}
	var ok: Dictionary = _run([["pane", "PARTIAL_FALLOUT", [good_meta]]])
	_check(bool(ok["valid"]), "20 dictionary region metadata is accepted")


func _test_21_bad_leaves() -> void:
	var hole: Dictionary = _region("h", 0.2, 0.2, 0.2, 0.2)
	var pair: Array = _case([["outer", "PARTIAL_FALLOUT", [hole]], ["inner", "OPEN", []]])
	var snapshot: Dictionary = pair[0]
	var spatial: Dictionary = pair[1]
	var missing: Dictionary = spatial.duplicate(true)
	missing["leaves"].remove_at(1)
	_rejected(Geometry.compute_open_geometry(snapshot, missing), "21 a missing leaf is rejected")
	var duplicated: Dictionary = spatial.duplicate(true)
	duplicated["leaves"].append(Dictionary(spatial["leaves"][1]).duplicate(true))
	_rejected(Geometry.compute_open_geometry(snapshot, duplicated), "21 a duplicated leaf is rejected")
	var unknown: Dictionary = spatial.duplicate(true)
	unknown["leaves"][1]["id"] = "middle"
	_rejected(Geometry.compute_open_geometry(snapshot, unknown), "21 an unknown leaf is rejected")
	var extra: Dictionary = spatial.duplicate(true)
	extra["leaves"].append({"id": "ghost", "index": 2, "regions": []})
	_rejected(Geometry.compute_open_geometry(snapshot, extra), "21 an extra leaf is rejected")
	var wrong_index: Dictionary = spatial.duplicate(true)
	wrong_index["leaves"][1]["index"] = 0
	_rejected(Geometry.compute_open_geometry(snapshot, wrong_index), "21 a wrong leaf index is rejected")
	var float_index: Dictionary = spatial.duplicate(true)
	float_index["leaves"][1]["index"] = 1.0
	_rejected(Geometry.compute_open_geometry(snapshot, float_index), "21 a float leaf index is rejected")
	var wrong_panel: Dictionary = spatial.duplicate(true)
	wrong_panel["panel_id"] = "pane_b"
	_rejected(Geometry.compute_open_geometry(snapshot, wrong_panel), "21 a different panel id is rejected")
	var no_regions: Dictionary = spatial.duplicate(true)
	no_regions["leaves"][0].erase("regions")
	_rejected(Geometry.compute_open_geometry(snapshot, no_regions), "21 a leaf without regions key is rejected")
	_rejected(Geometry.compute_open_geometry(snapshot, "spatial"), "21 a non-dictionary spatial input is rejected")


func _test_22_bad_region_ids() -> void:
	for regions in [
		[_region("", 0.1, 0.1, 0.2, 0.2)],
		[_region("   ", 0.1, 0.1, 0.2, 0.2)],
		[_region("dup", 0.1, 0.1, 0.2, 0.2), _region("dup", 0.5, 0.5, 0.2, 0.2)],
	]:
		var pair: Array = _case([["pane", "PARTIAL_FALLOUT", regions]], {"pane": 0.02})
		_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "22 empty or duplicated region ids are rejected")
	var numeric: Array = _case([["pane", "PARTIAL_FALLOUT", [{"id": 7, "x_m": 0.1, "z_m": 0.1, "width_m": 0.2, "height_m": 0.2}]]], {"pane": 0.02})
	_rejected(Geometry.compute_open_geometry(numeric[0], numeric[1]), "22 a non-string region id is rejected")
	var same_id_other_leaf: Dictionary = _run([
		["outer", "PARTIAL_FALLOUT", [_region("r", 0.1, 0.1, 0.2, 0.2)]],
		["inner", "PARTIAL_FALLOUT", [_region("r", 0.1, 0.1, 0.2, 0.2)]],
	])
	_check(bool(same_id_other_leaf["valid"]), "22 the same region id in different leaves is accepted")


func _test_23_regions_on_intact_or_cracked() -> void:
	for state in ["INTACT", "CRACKED"]:
		var pair: Array = _case([["pane", state, []]])
		pair[1]["leaves"][0]["regions"] = [_region("r", 0.1, 0.1, 0.2, 0.2)]
		_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "23 regions on a %s leaf are rejected" % state)


func _test_24_partial_without_regions() -> void:
	var pair: Array = _case([["pane", "PARTIAL_FALLOUT", []]], {"pane": 0.25})
	_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "24 partial fallout without regions is rejected")


func _test_25_fraction_mismatch() -> void:
	var region: Dictionary = _region("r", 0.0, 0.0, 0.5, 0.5)
	for fraction in [0.25, 0.125 + 1.0e-6, 0.125 - 1.0e-6, 0.5]:
		var pair: Array = _case([["pane", "PARTIAL_FALLOUT", [region]]], {"pane": fraction})
		_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "25 fraction %s against a 0.125 union is rejected" % fraction)
	var exact: Array = _case([["pane", "PARTIAL_FALLOUT", [region]]], {"pane": 0.125})
	_check(bool(Geometry.compute_open_geometry(exact[0], exact[1])["valid"]), "25 the exact fraction is accepted")
	var within: Array = _case([["pane", "PARTIAL_FALLOUT", [region]]], {"pane": 0.125 + 0.5 * Geometry.FRACTION_TOLERANCE})
	_check(bool(Geometry.compute_open_geometry(within[0], within[1])["valid"]), "25 a fraction within the tolerance is accepted")
	# Una union que cubre todo el panel no es un desprendimiento parcial.
	var full: Array = _case([["pane", "PARTIAL_FALLOUT", [_region("all", 0.0, 0.0, W, H)]]], {"pane": 0.999999})
	_rejected(Geometry.compute_open_geometry(full[0], full[1]), "25 a partial union covering the whole panel is rejected")


func _test_26_overlap_counted_once_for_the_fraction() -> void:
	var regions: Array = [_region("a", 0.0, 0.0, 0.5, 1.0), _region("b", 0.0, 0.5, 0.5, 1.0)]
	var union_fraction: float = (0.5 * 1.5) / PANEL_AREA
	var summed_fraction: float = (0.5 + 0.5) / PANEL_AREA
	var right: Array = _case([["pane", "PARTIAL_FALLOUT", regions]], {"pane": union_fraction})
	var right_result: Dictionary = Geometry.compute_open_geometry(right[0], right[1])
	_check(bool(right_result["valid"]) and _close(float(right_result["open_area_m2"]), 0.75), "26 the union fraction is accepted")
	var wrong: Array = _case([["pane", "PARTIAL_FALLOUT", regions]], {"pane": summed_fraction})
	_rejected(Geometry.compute_open_geometry(wrong[0], wrong[1]), "26 a fraction that double counts the overlap is rejected")
	var contained: Array = _case([["pane", "PARTIAL_FALLOUT", [_region("big", 0.0, 0.0, 0.5, 0.5), _region("inside", 0.1, 0.1, 0.1, 0.1)]]],
			{"pane": 0.25 / PANEL_AREA})
	_check(bool(Geometry.compute_open_geometry(contained[0], contained[1])["valid"]), "26 a region inside another adds nothing")


func _multi_specs() -> Array:
	return [
		["a", "PARTIAL_FALLOUT", [_region("a1", 0.0, 0.0, 0.7, 0.8), _region("a2", 0.2, 1.0, 0.7, 0.8), _region("a3", 0.5, 0.5, 0.3, 0.9)]],
		["b", "PARTIAL_FALLOUT", [_region("b1", 0.1, 0.1, 0.8, 1.6), _region("b2", 0.0, 1.8, 1.0, 0.2)]],
		["c", "OPEN", []],
	]


func _test_27_order_independence() -> void:
	var pair: Array = _case(_multi_specs())
	var reference: String = _canonical(Geometry.compute_open_geometry(pair[0], pair[1]))
	var reordered_snapshot: Dictionary = Dictionary(pair[0]).duplicate(true)
	reordered_snapshot["leaves"].reverse()
	var reordered_spatial: Dictionary = Dictionary(pair[1]).duplicate(true)
	reordered_spatial["leaves"].reverse()
	for entry in reordered_spatial["leaves"]:
		entry["regions"].reverse()
	var reordered: String = _canonical(Geometry.compute_open_geometry(reordered_snapshot, reordered_spatial))
	_check(reordered == reference, "27 reversed leaves and regions give byte-identical output")
	_check_invariants(Geometry.compute_open_geometry(pair[0], pair[1]), "27")


func _battery() -> Dictionary:
	var battery: Dictionary = {}
	var cases: Dictionary = {
		"multi": _multi_specs(),
		"l_shape": [["pane", "PARTIAL_FALLOUT", _l_shape_regions()]],
		"grid": [
			["outer", "PARTIAL_FALLOUT", [_region("band_low", 0.0, 0.2, 1.0, 0.2), _region("band_high", 0.0, 1.4, 1.0, 0.2)]],
			["inner", "PARTIAL_FALLOUT", [_region("col_left", 0.1, 0.0, 0.2, 2.0), _region("col_right", 0.7, 0.0, 0.2, 2.0)]],
		],
		"open_intact": [["outer", "OPEN", []], ["inner", "INTACT", []]],
	}
	for key in cases.keys():
		var pair: Array = _case(cases[key])
		battery[key] = Geometry.compute_open_geometry(pair[0], pair[1])
	return battery


func _test_28_determinism(dump_path: String) -> void:
	var first: String = _canonical(_battery())
	var second: String = _canonical(_battery())
	_check(first == second, "28 two runs are identical")
	if dump_path.is_empty():
		return
	var file := FileAccess.open(dump_path, FileAccess.WRITE)
	if file == null:
		_check(false, "28 could not open dump file %s" % dump_path)
		return
	file.store_string(first + "\n")
	file.close()


func _test_29_inputs_untouched() -> void:
	var pair: Array = _case(_multi_specs())
	pair[1]["leaves"][0]["regions"][0]["metadata"] = {"origin": "test", "nested": {"k": 1}}
	var before: String = _canonical(pair)
	var result: Dictionary = Geometry.compute_open_geometry(pair[0], pair[1])
	_check(_canonical(pair) == before, "29 inputs are not modified")
	for r in result["rectangles"]:
		if not r["contributors"].is_empty():
			r["contributors"][0]["region_ids"].append("tamper")
		r["width_m"] = 99.0
	if not result["leaf_union_areas_m2"].is_empty():
		result["leaf_union_areas_m2"][0]["union_area_m2"] = -1.0
	_check(_canonical(pair) == before, "29 output does not alias the input")


func _test_30_output_is_geometry_only() -> void:
	var result: Dictionary = Geometry.compute_open_geometry(_case(_multi_specs())[0], _case(_multi_specs())[1])
	var text: String = _canonical(result).to_lower()
	for word in ["flow", "pressure", "velocity", "direction", "mass", "volume", "smoke", "o2", "oxygen", "energy",
			"enthalpy", "species", "co2", "hcn", "open_fraction", "thermal_gap", "bernoulli", "discharge"]:
		_check(not text.contains(word), "30 the output has nothing like '%s'" % word)
	var keys: Array = result.keys()
	keys.sort()
	_check(keys == ["errors", "leaf_union_areas_m2", "open_area_m2", "panel_area_m2", "panel_height_m", "panel_id",
			"panel_sill_z_m", "panel_width_m", "rectangles", "valid"], "30 result keys are fixed")
	for r in result["rectangles"]:
		var rect_keys: Array = r.keys()
		rect_keys.sort()
		_check(rect_keys == ["area_m2", "contributors", "global_sill_z_m", "height_m", "id", "local_x_m", "local_z_m", "source", "width_m"],
				"30 rectangle keys are fixed")
	var code: String = _code_lines().to_lower()
	for word in ["temperat", "pressure", "bernoulli", "flow", "velocity", "sqrt(", "pow(", "rand", "seed", "preload(",
			"load(", "open_fraction", "thermal_gap", "smoke", "oxygen", "species", "time.", "os.", "node", "class_name"]:
		_check(not code.contains(word), "30 the model code has no '%s'" % word)
	_check(code.begins_with("extends refcounted"), "30 the model is a RefCounted")


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


func _test_31_open_with_regions_rejected() -> void:
	var pair: Array = _case([["pane", "OPEN", []]])
	pair[1]["leaves"][0]["regions"] = [_region("all", 0.0, 0.0, W, H)]
	_rejected(Geometry.compute_open_geometry(pair[0], pair[1]), "31 an OPEN leaf with regions is rejected (single contract)")


func _test_32_bad_snapshots() -> void:
	var pair: Array = _case([["pane", "PARTIAL_FALLOUT", [_region("r", 0.1, 0.1, 0.2, 0.2)]]])
	var spatial: Dictionary = pair[1]
	var invalid: Dictionary = Dictionary(pair[0]).duplicate(true)
	invalid["valid"] = false
	_rejected(Geometry.compute_open_geometry(invalid, spatial), "32 an invalid 3A result is rejected")
	var cracked_with_fraction: Dictionary = Dictionary(pair[0]).duplicate(true)
	cracked_with_fraction["leaves"][0]["state"] = "CRACKED"
	_rejected(Geometry.compute_open_geometry(cracked_with_fraction, spatial), "32 a snapshot state/fraction mismatch is rejected")
	var unknown_state: Dictionary = Dictionary(pair[0]).duplicate(true)
	unknown_state["leaves"][0]["state"] = "BROKEN"
	_rejected(Geometry.compute_open_geometry(unknown_state, spatial), "32 an unknown snapshot state is rejected")
	var bad_width: Dictionary = Dictionary(pair[0]).duplicate(true)
	bad_width["panel"]["width_m"] = 0.0
	_rejected(Geometry.compute_open_geometry(bad_width, spatial), "32 a snapshot with zero width is rejected")
	var no_leaves: Dictionary = Dictionary(pair[0]).duplicate(true)
	no_leaves["leaves"] = []
	_rejected(Geometry.compute_open_geometry(no_leaves, spatial), "32 a snapshot without leaves is rejected")
	_rejected(Geometry.compute_open_geometry("snapshot", spatial), "32 a non-dictionary snapshot is rejected")


func _test_33_islands_and_gaps() -> void:
	# Dos islas en la misma franja con la misma procedencia y un hueco cerrado entre ellas.
	var result: Dictionary = _run([
		["outer", "PARTIAL_FALLOUT", [_region("wide", 0.0, 0.5, 1.0, 0.4)]],
		["inner", "PARTIAL_FALLOUT", [_region("left", 0.0, 0.0, 0.3, 2.0), _region("right", 0.7, 0.0, 0.3, 2.0)]],
	])
	_check_invariants(result, "33")
	_check(_same_geometry(result, [[0.0, 0.5, 0.3, 0.4], [0.7, 0.5, 0.3, 0.4]]), "33 two islands stay separate (%s)" % [_geometry(result)])
	_check(not _covers(result["rectangles"], 0.5, 0.7), "33 the gap between islands stays closed")
	# Isla aislada lejos de las demas.
	var lonely: Dictionary = _run([["pane", "PARTIAL_FALLOUT", [_region("main", 0.0, 0.0, 0.5, 0.5), _region("island", 0.8, 1.8, 0.1, 0.1)]]])
	_check(_covers(lonely["rectangles"], 0.85, 1.85), "33 a disconnected island is kept")
	_check(_close(float(lonely["open_area_m2"]), 0.25 + 0.01), "33 island area is kept")
	# Tres tramos iguales apilados se fusionan en uno solo; con un tramo distinto en medio, no.
	var stacked: Dictionary = _run([["pane", "PARTIAL_FALLOUT", [_region("col", 0.2, 0.0, 0.2, 1.5), _region("mark", 0.6, 0.5, 0.2, 0.5)]]])
	_check_invariants(stacked, "33 stacked")
	var column_parts: int = 0
	for r in stacked["rectangles"]:
		if float(r["local_x_m"]) == 0.2:
			column_parts += 1
	_check(column_parts == 1, "33 an uninterrupted column is a single rectangle")
