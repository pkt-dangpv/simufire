extends RefCounted

## Carga el modelo de un mueble y lo lleva a su TAMANO REAL.
##
## Los modelos del catalogo no vienen a escala: una cama mide 0,96 x 1,13 x
## 0,38 m en el fichero, un armario 0,40 x 0,25 x 0,85, y cada uno con un
## factor distinto. Antes se compensaba escalando el modelo para que su
## superficie en planta coincidiera con la huella que declara el escenario,
## que es un dato del modelo de FUEGO -va emparejada con footprint_m2- y no
## el tamano del mueble. El resultado eran camas de metro y medio de largo y
## un frente de cocina de 3,15 m convertido en un cubo de 1,46: al lado de un
## jugador de 1,80 m, una casa de munecas.
##
## Ahora el destino es la caja real del arquetipo, que vive en
## `FurnitureDimensions`. El escenario sigue decidiendo la orientacion y la
## dimension libre de las piezas que la tienen.

const FurnitureDimensions := preload("res://view/furniture/FurnitureDimensions.gd")

## Cuanto puede separarse la escala de un eje respecto de la uniforme.
##
## Los modelos no tienen las proporciones exactas del mueble real, asi que
## llevarlos a la caja real exige estirar algo. Un 12 % no se ve en un mueble
## y evita las dos cosas malas: ni la casa de munecas de la escala uniforme,
## ni un inodoro estirado al doble de alto.
const MAX_ANISOTROPY: float = 1.12

## Tamano nativo de cada modelo, medido una sola vez. Los ficheros no cambian
## en ejecucion y medir exige instanciar la escena.
static var _native_size_cache: Dictionary = {}


## Que va a medir de verdad esta pieza, antes de construirla.
##
## Quien la coloca necesita saberlo: si planifica con el tamano pedido y el
## modelo acaba en otro, la pieza se sale de la sala o se mete en la de al lado.
## Aqui se resuelve una vez y lo usan los dos, asi que plano y dibujo no pueden
## discrepar. Devuelve ZERO si no hay modelo para el arquetipo.
static func resolved_size_m(kind_name: String, target_m: Vector3) -> Vector3:
	var native: Vector3 = _native_size_m(kind_name)
	if native == Vector3.ZERO:
		return Vector3.ZERO
	if FurnitureDimensions.is_tiled(kind_name):
		# Una fila de modulos ocupa exactamente el frente que se le pide.
		return target_m
	var scale: Dictionary = _scale_for(native, target_m, FurnitureDimensions.fits_exactly(kind_name))
	return Vector3(float(scale["world_x"]), float(scale["world_y"]), float(scale["world_z"]))


static func _native_size_m(kind_name: String) -> Vector3:
	var asset_kind: String = _asset_kind_for(kind_name)
	if _native_size_cache.has(asset_kind):
		return Vector3(_native_size_cache[asset_kind])
	var scene_path: String = "res://assets/fp/furniture/%s.tscn" % asset_kind
	if not ResourceLoader.exists(scene_path):
		_native_size_cache[asset_kind] = Vector3.ZERO
		return Vector3.ZERO
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		_native_size_cache[asset_kind] = Vector3.ZERO
		return Vector3.ZERO
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_native_size_cache[asset_kind] = Vector3.ZERO
		return Vector3.ZERO
	var aabb: AABB = _get_combined_aabb(instance)
	instance.free()
	var size: Vector3 = aabb.size
	_native_size_cache[asset_kind] = size
	return size


## La aritmetica del ajuste, en un solo sitio: la usan el calculo previo y la
## construccion real.
static func _scale_for(native: Vector3, target_m: Vector3, exact_fit: bool) -> Dictionary:
	var nx: float = maxf(0.001, native.x)
	var ny: float = maxf(0.001, native.y)
	var nz: float = maxf(0.001, native.z)
	var tx: float = maxf(0.05, target_m.x)
	var ty: float = maxf(0.05, target_m.y)
	var tz: float = maxf(0.05, target_m.z)

	# Alinea el eje largo del modelo con el eje largo del destino.
	var yaw: float = 0.0
	var scale_x: float = tx / nx
	var scale_z: float = tz / nz
	if (nx >= nz) != (tx >= tz):
		yaw = PI * 0.5
		# Girado, la x del modelo cae en la z del mundo y al reves.
		scale_x = tz / nx
		scale_z = tx / nz
	var scale_y: float = ty / ny

	# Limite de deformacion alrededor de la escala uniforme equivalente. Las
	# piezas sin forma rigida no pasan por aqui: no hay nada que conservar y el
	# limite las deformaba mas de lo que las protegia.
	if not exact_fit:
		var uniform: float = pow(maxf(0.000001, scale_x * scale_y * scale_z), 1.0 / 3.0)
		scale_x = clampf(scale_x, uniform / MAX_ANISOTROPY, uniform * MAX_ANISOTROPY)
		scale_y = clampf(scale_y, uniform / MAX_ANISOTROPY, uniform * MAX_ANISOTROPY)
		scale_z = clampf(scale_z, uniform / MAX_ANISOTROPY, uniform * MAX_ANISOTROPY)

	var world_x: float = nx * scale_x
	var world_z: float = nz * scale_z
	if yaw != 0.0:
		world_x = nz * scale_z
		world_z = nx * scale_x
	return {
		"yaw": yaw,
		"scale": Vector3(scale_x, scale_y, scale_z),
		"world_x": world_x,
		"world_y": ny * scale_y,
		"world_z": world_z,
	}


## Devuelve el tamano REAL conseguido (x, alto, z) en metros, o ZERO si no hay
## modelo para este arquetipo. Lo conseguido no tiene por que ser lo pedido -el
## limite de deformacion manda- y quien coloca la pieza necesita saberlo.
static func try_build(parent: Node3D, kind_name: String, target_m: Vector3, meters_to_units: float) -> Vector3:
	if parent == null:
		return Vector3.ZERO
	var asset_kind: String = _asset_kind_for(kind_name)
	var scene_path: String = "res://assets/fp/furniture/%s.tscn" % asset_kind
	if not ResourceLoader.exists(scene_path):
		return Vector3.ZERO
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return Vector3.ZERO
	if FurnitureDimensions.is_tiled(kind_name):
		return _build_tiled(parent, packed, asset_kind, kind_name, target_m, meters_to_units)
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return Vector3.ZERO
	instance.name = "Asset_%s" % asset_kind
	# Anadimos a la escena antes de medir para que Godot calcule el AABB real
	parent.add_child(instance)
	var achieved: Vector3 = _fit_instance(instance, target_m, meters_to_units, FurnitureDimensions.fits_exactly(kind_name))
	_prepare_asset_materials(instance)
	return achieved


## Un frente de cocina son modulos de 60 cm puestos en fila, no un mueble
## estirado cuatro metros. Se repite el modulo a lo largo del eje mayor.
static func _build_tiled(
	parent: Node3D,
	packed: PackedScene,
	asset_kind: String,
	kind_name: String,
	target_m: Vector3,
	meters_to_units: float
) -> Vector3:
	var along_x: bool = target_m.x >= target_m.z
	var run_m: float = target_m.x if along_x else target_m.z
	var deep_m: float = target_m.z if along_x else target_m.x
	var module_m: float = float(FurnitureDimensions.spec_for(kind_name).get("deep_m", 0.60))
	var count: int = maxi(1, int(round(run_m / maxf(0.20, module_m))))
	var step_m: float = run_m / float(count)
	var achieved := Vector3.ZERO
	for i in range(count):
		var instance := packed.instantiate() as Node3D
		if instance == null:
			continue
		instance.name = "Asset_%s_%02d" % [asset_kind, i]
		parent.add_child(instance)
		var module_target := Vector3(step_m, target_m.y, deep_m)
		if not along_x:
			module_target = Vector3(deep_m, target_m.y, step_m)
		var module_size: Vector3 = _fit_instance(instance, module_target, meters_to_units, false)
		var offset: float = (float(i) + 0.5) * step_m - run_m * 0.5
		if along_x:
			instance.position.x += offset * meters_to_units
			achieved = Vector3(run_m, maxf(achieved.y, module_size.y), maxf(achieved.z, module_size.z))
		else:
			instance.position.z += offset * meters_to_units
			achieved = Vector3(maxf(achieved.x, module_size.x), maxf(achieved.y, module_size.y), run_m)
		_prepare_asset_materials(instance)
	return achieved


# Lleva un modelo importado a su caja real:
#  - rota 90 grados si el eje largo del modelo no coincide con el del destino
#  - escala cada eje a su medida, con el limite de deformacion de arriba
#  - re-centra el footprint en el origen y apoya la base en el suelo (Y=0)
static func _fit_instance(instance: Node3D, target_m: Vector3, meters_to_units: float, exact_fit: bool) -> Vector3:
	var aabb: AABB = _get_combined_aabb(instance)
	var fit: Dictionary = _scale_for(aabb.size, target_m, exact_fit)
	var basis := Basis(Vector3.UP, float(fit["yaw"])) * Basis().scaled(Vector3(fit["scale"]) * meters_to_units)
	instance.transform.basis = basis

	# Re-centra: lleva el centro del footprint al origen y la base al suelo.
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var anchor := Vector3(center.x, aabb.position.y, center.z)
	instance.position = -(basis * anchor)

	return Vector3(float(fit["world_x"]), float(fit["world_y"]), float(fit["world_z"]))


static func _get_combined_aabb(root: Node3D) -> AABB:
	# Acumula transforms LOCALES desde el root (no usa global_transform, que
	# falla si el nodo aún no está dentro del árbol de escena).
	var state := [AABB(), false]
	_accumulate_aabb(root, Transform3D.IDENTITY, state)
	return state[0]


static func _accumulate_aabb(node: Node, xform: Transform3D, state: Array) -> void:
	for child in node.get_children():
		var child_xform: Transform3D = xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var aabb: AABB = _transform_aabb(child_xform, mi.get_aabb())
				if not state[1]:
					state[0] = aabb
					state[1] = true
				else:
					state[0] = state[0].merge(aabb)
		if child.get_child_count() > 0:
			_accumulate_aabb(child, child_xform, state)


static func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var p := aabb.position
	var s := aabb.size
	var corners := [
		xform * p,
		xform * Vector3(p.x + s.x, p.y, p.z),
		xform * Vector3(p.x, p.y + s.y, p.z),
		xform * Vector3(p.x, p.y, p.z + s.z),
		xform * Vector3(p.x + s.x, p.y + s.y, p.z),
		xform * Vector3(p.x + s.x, p.y, p.z + s.z),
		xform * Vector3(p.x, p.y + s.y, p.z + s.z),
		xform * Vector3(p.x + s.x, p.y + s.y, p.z + s.z),
	]
	var mn: Vector3 = corners[0]
	var mx: Vector3 = corners[0]
	for c: Vector3 in corners:
		mn = mn.min(c)
		mx = mx.max(c)
	return AABB(mn, mx - mn)


static func _asset_kind_for(kind_name: String) -> String:
	match kind_name:
		"storage":
			return "dresser"
		"containers":
			return "plastic_bin"
		"table":
			return "table"
		"bathtub", "bath":
			return "bathtub"
		"toilet":
			return "toilet"
		"sink", "bathroom_sink":
			return "bathroom_sink"
		"shower":
			return "shower"
		"bathroom_cabinet":
			return "bathroom_cabinet"
		"desk":
			return "desk"
		"chair":
			return "chair"
		"chair_desk":
			return "chair_desk"
		"bed_single":
			return "bed_single"
		"bed_bunk":
			return "bed_bunk"
		"fridge", "kitchen_fridge":
			return "kitchen_fridge"
		"stove", "kitchen_stove":
			return "kitchen_stove"
		"kitchen_sink":
			return "kitchen_sink"
		"washer":
			return "washer"
		"dryer":
			return "dryer"
		"lamp", "lamp_floor":
			return "lamp_floor"
		"lamp_table":
			return "lamp_table"
		"plant":
			return "plant"
		"side_table":
			return "side_table"
		"bench":
			return "bench"
		_:
			return kind_name


static func _prepare_asset_materials(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			# BoxMesh primitivos usan material_override
			var mat := mesh_node.material_override as StandardMaterial3D
			if mat != null:
				var material_copy := mat.duplicate() as StandardMaterial3D
				mesh_node.material_override = material_copy
				if not mesh_node.has_meta("base_color"):
					mesh_node.set_meta("base_color", material_copy.albedo_color)
			else:
				# GLBs importados usan surface_material_override por superficie
				var mesh := mesh_node.mesh
				if mesh != null:
					for surf_idx in mesh.get_surface_count():
						var surf_mat := mesh_node.get_surface_override_material(surf_idx)
						if surf_mat == null:
							surf_mat = mesh.surface_get_material(surf_idx)
						if surf_mat is StandardMaterial3D:
							var material_copy := surf_mat.duplicate() as StandardMaterial3D
							mesh_node.set_surface_override_material(surf_idx, material_copy)
							if not mesh_node.has_meta("base_color"):
								mesh_node.set_meta("base_color", material_copy.albedo_color)
		if child.get_child_count() > 0:
			_prepare_asset_materials(child)
