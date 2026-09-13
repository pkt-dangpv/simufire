extends RefCounted
## Domo de cielo para la vista FP.
##
## El proyecto renderiza en GL Compatibility, donde el `sky` de un
## Environment asignado por Camera3D no se dibuja (se veia negro por las
## ventanas). Este domo es geometria real (esfera invertida) con gradiente
## cenit->horizonte y disco solar, asi que se ve siempre. Vive en el mundo
## FP, por lo que no afecta a la vista 3D.
##
## TODO editable desde Godot:
##  - Shader:   view/fp/fp_sky_dome.gdshader
##  - Material: view/fp/fp_sky_dome_material.tres (curva del degradado,
##              suavizado del horizonte, concentracion del halo...)
##  - Colores dia/noche, radio y tamaño del sol: exports del
##    FirstPersonController (se aplican encima al construir el mundo).

const SkyDomeMaterial: ShaderMaterial = preload("res://view/fp/fp_sky_dome_material.tres")


static func create(radius_m: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius_m
	mesh.height = radius_m * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var node := MeshInstance3D.new()
	node.name = "FPSkyDome"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = radius_m
	# Duplicado para no mutar el .tres compartido en disco.
	node.material_override = SkyDomeMaterial.duplicate(true)
	return node


## Dirección del sol a partir de los angulos de la luz direccional exterior.
static func sun_direction_from_angles(pitch_deg: float, yaw_deg: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	# La luz apunta hacia -Z local; el sol esta en la direccion opuesta.
	return (-(basis * Vector3(0.0, 0.0, -1.0))).normalized()


static func apply_colors(
	node: MeshInstance3D,
	top_color: Color,
	horizon_color: Color,
	ground_color: Color,
	sun_color: Color,
	sun_direction: Vector3,
	sun_size_deg: float,
	sun_halo_strength: float
) -> void:
	if node == null:
		return
	var material := node.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("sky_top_color", top_color)
	material.set_shader_parameter("sky_horizon_color", horizon_color)
	material.set_shader_parameter("ground_color", ground_color)
	material.set_shader_parameter("sun_color", sun_color)
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter("sun_cos_size", cos(deg_to_rad(maxf(0.15, sun_size_deg))))
	material.set_shader_parameter("sun_halo_strength", sun_halo_strength)


## Atmosfera: bruma del horizonte, nubes y noche.
##
## Va aparte de los colores porque son mandos de otra naturaleza -no dicen de
## que color es el cielo sino que hay en el- y porque asi el domo se puede
## dejar liso pasando un diccionario vacio.
static func apply_atmosphere(node: MeshInstance3D, settings: Dictionary) -> void:
	if node == null:
		return
	var material := node.material_override as ShaderMaterial
	if material == null:
		return
	for key in settings.keys():
		material.set_shader_parameter(String(key), settings[key])
