extends RefCounted
## Domo de cielo para la vista FP.
##
## El proyecto renderiza en GL Compatibility, donde el `sky` de un
## Environment asignado por Camera3D no se dibuja (se veia negro por las
## ventanas). Este domo es geometria real (esfera invertida) con un shader
## de gradiente cenit->horizonte + disco solar con halo, asi que se ve
## siempre. Vive en el mundo FP, por lo que no afecta a la vista 3D.

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 sky_top_color : source_color = vec4(0.24, 0.45, 0.80, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.78, 0.86, 0.93, 1.0);
uniform vec4 ground_color : source_color = vec4(0.34, 0.35, 0.35, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec3 sun_direction = vec3(0.35, 0.55, -0.75);
uniform float sun_cos_size = 0.9985;
uniform float sun_halo_power = 220.0;
uniform float sun_halo_strength = 0.55;
uniform float horizon_softness = 0.04;
uniform float sky_curve = 0.42;

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(local_dir);
	float h = dir.y;
	// Gradiente de cielo: horizonte claro -> cenit saturado.
	float t = clamp(pow(max(h, 0.0), sky_curve), 0.0, 1.0);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, t);
	// Suelo/bruma por debajo del horizonte.
	vec3 col = mix(ground_color.rgb, sky, smoothstep(-horizon_softness, horizon_softness, h));
	// Sol: disco nitido + halo suave.
	float d = dot(dir, normalize(sun_direction));
	float disk = smoothstep(sun_cos_size, sun_cos_size + 0.0006, d);
	float halo = pow(max(d, 0.0), sun_halo_power) * sun_halo_strength;
	float above = smoothstep(-0.02, 0.05, h);
	col = mix(col, sun_color.rgb, clamp(disk + halo, 0.0, 1.0) * above);
	ALBEDO = col;
}
"""


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
	var shader := Shader.new()
	shader.code = DOME_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = -100
	node.material_override = material
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
