extends RefCounted
## Leer valores del formato guardado: lo que hay en el JSON, convertido al tipo
## que espera el codigo.
##
## Existe porque la misma funcion de diez lineas -«saca un Vector2 de esto, venga
## como venga»- estaba escrita **seis veces** en el repositorio, repartida por
## tres capas:
##
##   | donde | como se llamaba |
##   |---|---|
##   | `sim/BuildingModel.gd` | `_vector2_from_variant` |
##   | `editor/ScenarioSerializer.gd` | `vector2_from_data` |
##   | `view/3d/Visualizer3D.gd` | `_vector2_from_variant` |
##   | `view/fp/FirstPersonController.gd` | `_vector2_from_variant` |
##   | `view/2d/rooms/RoomStateVisuals2D.gd` | `vector2_from_variant` |
##   | `view/furniture/FurnitureRoomLayout.gd` | `_to_vector2` |
##
## Seis copias del mismo lector del formato es como se acaba con dos vistas que
## interpretan el mismo fichero de forma distinta, que es exactamente el fallo
## que se pago en FP-3: una ventana declarada al norte plantada en la pared
## derecha porque cada vista leia el dato a su manera.
##
## Vive en `sim/` y no en `editor/` por las capas
## (docs/architecture/MODULE_BOUNDARIES.md): `view/` y `editor/` pueden depender
## de `sim/`, y no al reves. El formato es del escenario, no del editor.
##
## Solo funciones estaticas y puras.


## Un `Vector2` venga como venga: ya convertido, como diccionario `{x, y}` -que
## es como se guarda en el JSON- o como lista de dos numeros.
##
## `fallback` es lo que sale si no hay nada legible, y ademas **rellena las
## componentes que falten** en un diccionario a medias: un `{"x": 2.0}` con
## fallback `(0, 1)` da `(2, 1)`, no `(2, 0)`. Esa diferencia existia ya entre
## las seis copias -tres usaban cero y tres el fallback- y se ha conservado la
## version con fallback, que es la que dice mas.
static func to_vector2(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))
	if typeof(value) == TYPE_ARRAY:
		var values: Array = value
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return fallback
