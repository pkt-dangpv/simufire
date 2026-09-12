extends SceneTree
## Guardarrail de A QUE DA CADA ABERTURA.
##
## El modelo solo sabe si es puerta o ventana y si el otro lado es una sala o el
## ambiente. Con eso, **la puerta de una vivienda a un portal cerrado y la
## entrada de una unifamiliar a la calle son el mismo dato**, y la vista las
## pintaba igual: las dos echaban penacho a la calle. Una de las dos es falsa.
##
## Lo que se fija aqui, caso por caso, porque cada uno ventila distinto:
##
##   1. Puerta de piso -> rellano cerrado: NO da a la calle. Lo que sale por ahi
##      choca contra el techo del rellano, no se va al cielo.
##   2. Entrada de unifamiliar -> calle: si.
##   3. Balconera -> calle: si, aunque sea puerta y aunque el edificio sea un
##      bloque de pisos. Lo que la separa de la del portal es el balcon.
##   4. Ventana al exterior -> calle: si.
##   5. Ventana a un patio -> conducto cerrado por los lados: NO es la calle.
##   6. La boca del patio -> cielo: si, y es por donde sale el penacho.
##
## Y dos que no son huecos de fachada aunque lo parezcan por el dato: el
## encadenado entre zonas de patio y el hueco de forjado de una escalera.
##
##   <godot> --headless --path . --script res://tools/validate_opening_kinds.gd

const BuildingModelScript := preload("res://sim/BuildingModel.gd")
const OpeningKinds := preload("res://view/geometry/OpeningKinds.gd")

var _frames: int = 0
var _fails: int = 0


func _eq(que: String, got, want) -> void:
	if str(got) == str(want):
		print("  ok   %s = %s" % [que, str(got)])
	else:
		print("  FAIL %s = %s (se esperaba %s)" % [que, str(got), str(want)])
		_fails += 1


## Un edificio con las seis situaciones a la vez.
##
##   1 Recibidor  -> puerta al portal / a la calle, segun el tipo de edificio
##   1 Recibidor  -> balconera
##   2 Salon      -> ventana a la calle
##   3 Cocina     -> ventana al patio
##   4 Patio P0   -> encadenado con Patio P1
##   5 Patio P1   -> boca al cielo
##   2 Salon      -> hueco de escalera con el de arriba
func _edificio(tipo: String) -> BuildingModel:
	var building: BuildingModel = BuildingModelScript.new()
	building.load_template_data({
		"version": 1, "building_type": tipo, "apartment_floor_number": 1,
		"exterior_walls": [],
		"floors": [{"name": "R", "level_m": 0.0}, {"name": "R+1", "level_m": 2.9}],
		"room_rect_m": {
			"1": {"x": 0.0, "y": 0.0, "w": 3.0, "h": 3.0},
			"2": {"x": 3.0, "y": 0.0, "w": 4.0, "h": 3.0},
			"3": {"x": 7.0, "y": 0.0, "w": 3.0, "h": 3.0},
			"4": {"x": 10.0, "y": 0.0, "w": 2.5, "h": 2.5},
			"5": {"x": 10.0, "y": 0.0, "w": 2.5, "h": 2.5},
			"6": {"x": 3.0, "y": 0.0, "w": 4.0, "h": 3.0},
		},
		"rooms_data": [
			{"id": 1, "name": "Recibidor", "kind": "recibidor", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 2, "name": "Salon", "kind": "salon", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 3, "name": "Cocina", "kind": "cocina", "height_m": 2.5,
				"floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 4, "name": "Patio P0", "kind": "patio", "height_m": 2.9,
				"floor_level_z_m": 0.0, "fuel_objects": []},
			{"id": 5, "name": "Patio P1", "kind": "patio", "height_m": 2.9,
				"floor_level_z_m": 2.9, "fuel_objects": []},
			{"id": 6, "name": "Salon P1", "kind": "salon", "height_m": 2.5,
				"floor_level_z_m": 2.9, "fuel_objects": []},
		],
		"openings_data": [
			# 0 · la de entrada: el caso del encargo
			{"a": 1, "b": -1, "type": "door", "wall": "top", "offset_m": 1.0,
				"offset_is_fraction": false, "width_m": 0.92, "height_m": 2.05, "sill_m": 0.0},
			# 1 · balconera: puerta, pero a la calle
			{"a": 1, "b": -1, "type": "door", "wall": "left", "offset_m": 0.8,
				"offset_is_fraction": false, "width_m": 1.40, "height_m": 2.10, "sill_m": 0.0,
				"has_balcony": true, "balcony_depth_m": 1.20, "balcony_parapet_m": 1.10},
			# 2 · ventana a la calle
			{"a": 2, "b": -1, "type": "window", "wall": "top", "offset_m": 1.0,
				"offset_is_fraction": false, "width_m": 1.30, "height_m": 1.10, "sill_m": 0.90},
			# 3 · ventana al patio
			{"a": 3, "b": 4, "type": "window", "wall": "right", "offset_m": 0.8,
				"offset_is_fraction": false, "width_m": 1.20, "height_m": 1.10, "sill_m": 0.95},
			# 4 · encadenado del conducto
			{"a": 4, "b": 5, "type": "hole", "wall": "", "offset_m": 0.0,
				"offset_is_fraction": true, "width_m": 2.5, "height_m": 2.5, "sill_m": 0.0,
				"is_vertical": true},
			# 5 · la boca, al cielo
			{"a": 5, "b": -1, "type": "hole", "wall": "", "offset_m": 0.0,
				"offset_is_fraction": true, "width_m": 2.5, "height_m": 2.5, "sill_m": 0.0,
				"is_vertical": true},
			# 6 · hueco de forjado de una escalera
			{"a": 2, "b": 6, "type": "hole", "wall": "", "offset_m": 0.0,
				"offset_is_fraction": true, "width_m": 1.2, "height_m": 1.2, "sill_m": 0.0,
				"is_vertical": true},
			# 7 · puerta entre dos salas
			{"a": 1, "b": 2, "type": "door", "wall": "right", "offset_m": 1.0,
				"offset_is_fraction": false, "width_m": 0.82, "height_m": 2.05, "sill_m": 0.0},
		],
		"detectors": [], "victims": [],
		"player_start": {"room_id": 1, "x_m": 1.0, "y_m": 1.0}, "ignition_room_id": 2,
	})
	return building


## Los tipos de las ocho aberturas, en orden.
func _tipos(building: BuildingModel) -> String:
	var out: Array[String] = []
	for raw_op in building.get_openings():
		out.append(OpeningKinds.of(building, raw_op as OpeningModel))
	return ",".join(out)


## ¿Cuales dan al aire libre?
func _al_aire(building: BuildingModel) -> String:
	var out: Array[String] = []
	var index: int = 0
	for raw_op in building.get_openings():
		if OpeningKinds.vents_outdoors(building, raw_op as OpeningModel):
			out.append(str(index))
		index += 1
	return ",".join(out)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	# ── Bloque de pisos ──
	var piso: BuildingModel = _edificio("apartment")
	_eq(
		"en un bloque de pisos",
		_tipos(piso),
		"portal_door,balcony_door,street_window,patio_window,patio_shaft,patio_mouth,stair_void,interior"
	)
	# La de entrada (0) NO esta, la balconera (1) SI. Es toda la correccion.
	_eq("dan al aire libre", _al_aire(piso), "1,2,5")

	# ── La misma planta, pero unifamiliar ──
	#
	# Cambia UNA cosa y solo una: la puerta de entrada ya no da a un rellano,
	# da a la calle. Todo lo demas tiene que quedarse igual.
	var casa: BuildingModel = _edificio("single_family")
	_eq(
		"en una unifamiliar",
		_tipos(casa),
		"street_door,balcony_door,street_window,patio_window,patio_shaft,patio_mouth,stair_void,interior"
	)
	_eq("y ahi la entrada si da a la calle", _al_aire(casa), "0,1,2,5")

	# ── Las dos preguntas cortas, que son las que usa la vista ──
	var ops: Array = piso.get_openings()
	_eq("la 0 es la puerta del portal", OpeningKinds.is_portal_door(piso, ops[0]), true)
	_eq("y en la unifamiliar no", OpeningKinds.is_portal_door(casa, casa.get_openings()[0]), false)
	_eq("la 5 es la boca del patio", OpeningKinds.is_patio_mouth(piso, ops[5]), true)
	_eq("y la 4 -el encadenado- no", OpeningKinds.is_patio_mouth(piso, ops[4]), false)

	# ── Sin edificio no se revienta ──
	_eq("sin edificio, interior", OpeningKinds.of(null, null), "interior")

	piso.free()
	casa.free()

	if _fails == 0:
		print("[validate_opening_kinds] PASS")
	else:
		push_error("[validate_opening_kinds] FAIL (%d)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
