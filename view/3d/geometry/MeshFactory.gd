extends RefCounted
## Las piezas sueltas con las que se arma una escena 3D: una caja, un material y
## un nombre de nodo que Godot acepte.
##
## Existe porque estaban duplicadas entre los constructores de la escena. La
## auditoria del 2026-09-11 encontro estos pares **identicos letra por letra**:
##
##   | funcion | copias |
##   |---|---|
##   | `_create_box` | `view/3d/Visualizer3D.gd` y `view/3d/geometry/RoomShellFactory.gd` |
##   | `_make_material` | `view/3d/geometry/RoomShellFactory.gd` y `view/3d/furniture/FurnitureShapeBuilder.gd` |
##   | `_to_world` | `view/3d/smoke/SmokeAnimation3D.gd` y `view/3d/smoke/SmokeOpeningCurtain3D.gd` |
##
## Que la rugosidad del material este escrita dos veces no rompe nada hoy; rompe
## el dia que alguien la cambia en una sola. Es el mismo mecanismo que se pago en
## FP-3, cuando las dos vistas repartian la geometria cada una a su manera.
##
## Todo estatico y puro: entra lo que hace falta y sale un nodo o un recurso.


## Metros del escenario a unidades del mundo 3D.
##
## El desplazamiento se suma ANTES de escalar, y ese orden importa: al reves, un
## edificio lejos del origen se descoloca proporcionalmente a su distancia.
static func to_world(meters: Vector3, meters_to_units: float, origin_offset_m: Vector2) -> Vector3:
	return Vector3(
		(meters.x + origin_offset_m.x) * meters_to_units,
		meters.y * meters_to_units,
		(meters.z + origin_offset_m.y) * meters_to_units
	)


static func box(node_name: String, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	return node


## Material mate corriente. `transparent` fuerza el canal alfa aunque el color
## venga opaco, para lo que se vaya a desvanecer en marcha.
static func material(color: Color, transparent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.94
	mat.metallic = 0.0
	if transparent or color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## Un nombre que Godot acepte para un nodo.
##
## Las dos copias que habia no limpiaban lo mismo: la del rellano dejaba pasar
## los **dos puntos**, que Godot NO admite en el nombre de un nodo. Una sala
## llamada «Salon: grande» daba un nombre invalido y Godot lo renombraba por su
## cuenta, que es como se pierde un nodo que despues se busca por nombre. Aqui se
## limpian los cuatro caracteres, que es lo que hacia la version mas estricta.
static func safe_node_name(value: String, fallback: String = "node") -> String:
	var result: String = value.strip_edges()
	if result == "":
		return fallback
	result = result.replace(" ", "_")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	result = result.replace(":", "_")
	return result
