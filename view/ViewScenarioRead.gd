extends RefCounted
## Lo que las tres vistas leen del mismo escenario, para que lo lean igual.
##
## La vista 2D, el visor 3D y la primera persona trabajan sobre los mismos datos
## y cada una tenia su copia de como interpretarlos. La auditoria del 2026-09-11
## encontro estos cuatro, **identicos letra por letra**:
##
##   | funcion | copias |
##   |---|---|
##   | `_state_records_by_id` | `view/2d/Visualizer.gd` y `view/3d/Visualizer3D.gd` |
##   | `_compute_bounds` | `view/3d/Visualizer3D.gd` y `view/fp/FirstPersonController.gd` |
##   | `_safety_local_position` | `view/3d/Visualizer3D.gd` y `view/fp/FirstPersonController.gd` |
##   | `_fuel_object_state_name` | `view/3d/Visualizer3D.gd` y `view/fp/FirstPersonController.gd` |
##
## Dos vistas que leen el mismo fichero de forma distinta es exactamente el fallo
## que se pago en FP-3: una ventana declarada al norte acababa plantada sobre el
## paramento derecho porque cada vista resolvia el dato a su manera. Mientras las
## copias coinciden no se nota; se nota el dia que alguien toca una.
##
## Todo estatico y puro: no toca nodos, ni escena, ni estado.

const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd")


## Los registros de estado, indexados por su `id`. Los que no traen id se
## descartan: sin id no se pueden casar con nada.
static func records_by_id(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = raw_record
		var id_text: String = String(record.get("id", ""))
		if id_text != "":
			result[id_text] = record
	return result


## La caja que engloba todas las salas. Con el diccionario vacio sale un `Rect2`
## de tamaño cero, no un rectangulo centrado en el origen: quien lo use decide
## que hacer con un edificio sin salas.
static func bounds_of_rects(rects: Dictionary) -> Rect2:
	var first: bool = true
	var bounds := Rect2()
	for value in rects.values():
		var rect := Rect2(value)
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds


## Donde va un detector o una victima dentro de su sala.
##
## La posicion es **local a la sala** y se recorta a sus medidas: un dato fuera
## de rango no saca la chincheta de la habitacion. Sin posicion declarada, al
## centro.
static func safety_local_position(data: Dictionary, rect: Rect2) -> Vector2:
	if data.has("x_m") and data.has("y_m"):
		return Vector2(
			clampf(float(data.get("x_m", rect.size.x * 0.5)), 0.0, rect.size.x),
			clampf(float(data.get("y_m", rect.size.y * 0.5)), 0.0, rect.size.y)
		)
	return rect.size * 0.5


## El nombre con el que las vistas y los ficheros se refieren al estado de un
## mueble. Lo que no sea uno de los cinco es `cold`, que es el estado de partida.
static func fuel_object_state_name(state_id: int) -> String:
	match state_id:
		FuelObjectModelScript.State.HEATING:
			return "heating"
		FuelObjectModelScript.State.PYROLYZING:
			return "pyrolyzing"
		FuelObjectModelScript.State.FLAMING:
			return "flaming"
		FuelObjectModelScript.State.DECAYING:
			return "decaying"
		FuelObjectModelScript.State.BURNED_OUT:
			return "burned_out"
		_:
			return "cold"


## La foto de los muebles de una sala tal y como la leen las vistas: id, sitio,
## medidas, carga de fuego y en que estado esta ardiendo.
##
## Estaba escrita dos veces -`_build_static_fuel_object_snapshots` en el visor 3D
## y `_build_static_fp_fuel_object_snapshots` en primera persona- y **ya habian
## empezado a separarse**: la de primera persona se saltaba los objetos
## `room_proxy_` y la del visor no. Catorce campos copiados a mano en dos sitios
## es un campo nuevo que solo llega a una vista.
##
## `skip_room_proxies` conserva esa diferencia, ahora con nombre: un
## `room_proxy_` no es un mueble, es la carga de fuego de la sala repartida, y en
## primera persona no hay que dibujarlo.
static func fuel_object_snapshots(room: RoomModel, skip_room_proxies: bool = false) -> Array:
	var snapshots: Array = []
	if room == null:
		return snapshots
	for obj in room.fuel_objects:
		if obj == null:
			continue
		if skip_room_proxies and String(obj.id).begins_with("room_proxy_"):
			continue
		snapshots.append({
			"id": String(obj.id),
			"name": String(obj.name),
			"kind": String(obj.kind),
			"room_id": int(obj.room_id),
			"position_m": obj.position_m,
			"size_m": obj.size_m,
			"rotation_deg": float(obj.rotation_deg),
			"visual_pose_locked": bool(obj.visual_pose_locked),
			"elevation_m": float(obj.elevation_m),
			"fuel_energy_MJ": maxf(0.0, obj.fuel_energy_MJ),
			"remaining_fuel_MJ": maxf(0.0, obj.remaining_fuel_MJ),
			"max_hrr_kw": maxf(0.0, obj.max_hrr_kw),
			"hrr_kw": maxf(0.0, obj.hrr_kw),
			"state": fuel_object_state_name(int(obj.state)),
			"is_primary_ignition_source": bool(obj.is_primary_ignition_source),
		})
	return snapshots
