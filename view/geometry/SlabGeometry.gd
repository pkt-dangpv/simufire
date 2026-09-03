class_name SlabGeometry
extends RefCounted

## Reparto en losas de un forjado horizontal: suelos y techos.
##
## El mundo de primera persona y el visor 3D calculaban este reparto por
## separado, con la misma aritmetica, los mismos umbrales y hasta los mismos
## nombres de nodo. Solo diferian en lo que emite cada uno: el FP una
## `StaticBody3D` con colision y material de sala; el visor, una
## `MeshInstance3D` traslucida de maqueta. Aqui vive el reparto —que losas van y
## como se llaman—; la emision sigue siendo de cada vista (FP-3).
##
## Igual que `StairGeometry`, esto es geometria pura: no toca el arbol de
## escena, no crea nodos y no depende de ningun ajuste de vista.

## Lado minimo (m) para que una losa merezca existir. Por debajo de esto la
## pieza es una brizna que solo aporta z-fighting con la contigua.
const MIN_SLAB_SPAN_M: float = 0.28

## Ancho libre (m) del hueco de escalera a partir del cual una escalera de ida y
## vuelta se reparte como dos tiros con ojo, no como una rampa unica.
const SWITCHBACK_MIN_CROSS_SPAN_M: float = 1.65

## Holgura (m) entre los dos tiros de una escalera de ida y vuelta.
const SWITCHBACK_GAP_M: float = 0.18


## Losas del suelo de un hueco de escalera en una planta alta: el forjado existe
## solo a los lados del tiro y en la meseta de llegada; el resto es el ojo por
## el que sube la escalera.
##
## Devuelve `[{ "name": String, "rect": Rect2 }]`, en orden de construccion.
static func stairwell_upper_floor_slabs(room_id: int, rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Array[Dictionary]:
	if turn_degrees >= 179.0 and StairGeometry.cross_span_m(rect, stair_dir) >= SWITCHBACK_MIN_CROSS_SPAN_M:
		return _switchback_slabs(room_id, rect, stair_dir)
	return _straight_run_slabs(room_id, rect, stair_dir)


static func _straight_run_slabs(room_id: int, rect: Rect2, stair_dir: Vector2) -> Array[Dictionary]:
	var ramp_width_m: float = StairGeometry.ramp_width_m(rect, stair_dir)
	var landing_depth_m: float = StairGeometry.top_landing_depth_m(rect, stair_dir)
	var slabs: Array[Dictionary] = []

	if absf(stair_dir.x) > absf(stair_dir.y):
		var ramp_top_m: float = rect.position.y + rect.size.y * 0.5 - ramp_width_m * 0.5
		var ramp_bottom_m: float = ramp_top_m + ramp_width_m
		var top_height_m: float = maxf(0.0, ramp_top_m - rect.position.y)
		if top_height_m >= MIN_SLAB_SPAN_M:
			slabs.append(_slab("StairSideFloorTop_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, rect.size.x, top_height_m)))
		var bottom_height_m: float = maxf(0.0, rect.position.y + rect.size.y - ramp_bottom_m)
		if bottom_height_m >= MIN_SLAB_SPAN_M:
			slabs.append(_slab("StairSideFloorBottom_%s" % str(room_id), Rect2(rect.position.x, ramp_bottom_m, rect.size.x, bottom_height_m)))
		if landing_depth_m >= MIN_SLAB_SPAN_M:
			var landing_x_m: float = rect.position.x + rect.size.x - landing_depth_m if stair_dir.x > 0.0 else rect.position.x
			slabs.append(_slab("StairTopLanding_%s" % str(room_id), Rect2(landing_x_m, rect.position.y, landing_depth_m, rect.size.y)))
		return slabs

	var ramp_left_m: float = rect.position.x + rect.size.x * 0.5 - ramp_width_m * 0.5
	var ramp_right_m: float = ramp_left_m + ramp_width_m
	var left_width_m: float = maxf(0.0, ramp_left_m - rect.position.x)
	if left_width_m >= MIN_SLAB_SPAN_M:
		slabs.append(_slab("StairSideFloorLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y)))
	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - ramp_right_m)
	if right_width_m >= MIN_SLAB_SPAN_M:
		slabs.append(_slab("StairSideFloorRight_%s" % str(room_id), Rect2(ramp_right_m, rect.position.y, right_width_m, rect.size.y)))
	if landing_depth_m >= MIN_SLAB_SPAN_M:
		var landing_y_m: float = rect.position.y + rect.size.y - landing_depth_m if stair_dir.y > 0.0 else rect.position.y
		slabs.append(_slab("StairTopLanding_%s" % str(room_id), Rect2(rect.position.x, landing_y_m, rect.size.x, landing_depth_m)))
	return slabs


## En ida y vuelta no hay meseta de llegada dentro del hueco: el ojo recorre el
## recinto de lado a lado y solo quedan las dos franjas laterales.
static func _switchback_slabs(room_id: int, rect: Rect2, stair_dir: Vector2) -> Array[Dictionary]:
	var cross_span_m: float = StairGeometry.cross_span_m(rect, stair_dir)
	var flight_width_m: float = clampf((cross_span_m - SWITCHBACK_GAP_M) * 0.5, 0.72, 1.05)
	var shaft_width_m: float = minf(cross_span_m, flight_width_m * 2.0 + SWITCHBACK_GAP_M + 0.18)
	var slabs: Array[Dictionary] = []

	if absf(stair_dir.x) > absf(stair_dir.y):
		var shaft_top_m: float = rect.position.y + rect.size.y * 0.5 - shaft_width_m * 0.5
		var shaft_bottom_m: float = shaft_top_m + shaft_width_m
		var top_height_m: float = maxf(0.0, shaft_top_m - rect.position.y)
		if top_height_m >= MIN_SLAB_SPAN_M:
			slabs.append(_slab("StairSwitchbackSideTop_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, rect.size.x, top_height_m)))
		var bottom_height_m: float = maxf(0.0, rect.position.y + rect.size.y - shaft_bottom_m)
		if bottom_height_m >= MIN_SLAB_SPAN_M:
			slabs.append(_slab("StairSwitchbackSideBottom_%s" % str(room_id), Rect2(rect.position.x, shaft_bottom_m, rect.size.x, bottom_height_m)))
		return slabs

	var shaft_left_m: float = rect.position.x + rect.size.x * 0.5 - shaft_width_m * 0.5
	var shaft_right_m: float = shaft_left_m + shaft_width_m
	var left_width_m: float = maxf(0.0, shaft_left_m - rect.position.x)
	if left_width_m >= MIN_SLAB_SPAN_M:
		slabs.append(_slab("StairSwitchbackSideLeft_%s" % str(room_id), Rect2(rect.position.x, rect.position.y, left_width_m, rect.size.y)))
	var right_width_m: float = maxf(0.0, rect.position.x + rect.size.x - shaft_right_m)
	if right_width_m >= MIN_SLAB_SPAN_M:
		slabs.append(_slab("StairSwitchbackSideRight_%s" % str(room_id), Rect2(shaft_right_m, rect.position.y, right_width_m, rect.size.y)))
	return slabs


## Reparte una losa alrededor de los huecos verticales y le pone nombre a cada
## trozo: `whole_name` si ningun hueco la toca y sale entera, `part_prefix_NN`
## si hay que partirla. Es el mismo criterio que aplicaban las dos vistas por
## separado, cada una con sus propios prefijos.
##
## Cada entrada lleva `whole`, que dice si la losa salio de una pieza. Al visor
## 3D le importa: cuando sale entera no emite nada, porque ya la dibuja el suelo
## de la maqueta de la sala.
static func named_slab_pieces(rect: Rect2, voids: Array[Rect2], whole_name: String, part_prefix: String) -> Array[Dictionary]:
	var pieces: Array[Rect2] = StairGeometry.split_rect_by_voids(rect, voids)
	if pieces.size() == 1 and rect_same(pieces[0], rect):
		return [_slab(whole_name, rect, true)]
	var slabs: Array[Dictionary] = []
	for i in range(pieces.size()):
		slabs.append(_slab("%s_%02d" % [part_prefix, i], pieces[i]))
	return slabs


## Dos rectangulos son el mismo dentro de la tolerancia de 1 mm con la que se
## decide si un hueco vertical ha llegado a recortar algo.
static func rect_same(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) <= 0.001 and a.size.distance_to(b.size) <= 0.001


static func _slab(node_name: String, rect: Rect2, whole: bool = false) -> Dictionary:
	return {"name": node_name, "rect": rect, "whole": whole}
