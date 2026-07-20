// Cielo FP: domo geometrico (esfera invertida) con gradiente cenit->horizonte,
// disco solar con halo y suelo bajo el horizonte.
// Se usa geometria porque el renderer GL Compatibility no dibuja el `sky` de
// un Environment asignado por camara.
// Editable desde Godot: abre este .gdshader, o ajusta los parametros en
// view/fp/fp_sky_dome_material.tres (inspector).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 sky_top_color : source_color = vec4(0.24, 0.45, 0.80, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.78, 0.86, 0.93, 1.0);
uniform vec4 ground_color : source_color = vec4(0.34, 0.35, 0.35, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec3 sun_direction = vec3(0.35, 0.55, -0.75);
// cos del radio angular del sol (lo fija el codigo desde sky_sun_size_deg).
uniform float sun_cos_size = 0.9985;
// Concentracion del halo: mas alto = halo mas ceñido al disco.
uniform float sun_halo_power = 220.0;
uniform float sun_halo_strength = 0.55;
// Suavizado de la linea de horizonte.
uniform float horizon_softness = 0.04;
// Curva del degradado: <1 sube el azul hacia el cenit mas rapido.
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
	// Sol: disco nitido + halo suave, solo por encima del horizonte.
	float d = dot(dir, normalize(sun_direction));
	float disk = smoothstep(sun_cos_size, sun_cos_size + 0.0006, d);
	float halo = pow(max(d, 0.0), sun_halo_power) * sun_halo_strength;
	float above = smoothstep(-0.02, 0.05, h);
	col = mix(col, sun_color.rgb, clamp(disk + halo, 0.0, 1.0) * above);
	ALBEDO = col;
}
