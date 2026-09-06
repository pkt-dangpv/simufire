// Cielo FP: domo geometrico (esfera invertida).
//
// Se usa geometria porque el renderer GL Compatibility no dibuja el `sky` de
// un Environment asignado por camara: por la ventana se veia negro.
//
// Lo que dibuja, de fondo a primer plano:
//   - degradado cenit -> horizonte, con la banda de bruma baja que tiene el
//     cielo de verdad al mirarlo desde una ventana
//   - nubes procedurales en dos capas -cumulos y velo alto- que se mueven
//   - sol con disco, limbo y resplandor ancho -de noche ese mismo disco es la
//     luna, con su color y su tamano-
//   - de noche, estrellas
//
// Editable desde Godot: abre este .gdshader, o ajusta los parametros en
// view/fp/fp_sky_dome_material.tres (inspector). Los colores y el resto de
// mandos vienen ademas como @export del FirstPersonController.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 sky_top_color : source_color = vec4(0.19, 0.40, 0.78, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.76, 0.85, 0.94, 1.0);
uniform vec4 ground_color : source_color = vec4(0.34, 0.35, 0.35, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec3 sun_direction = vec3(0.35, 0.55, -0.75);
// cos del radio angular del sol (lo fija el codigo desde sky_sun_size_deg).
uniform float sun_cos_size = 0.9985;
// Concentracion del halo: mas alto = halo mas ceñido al disco.
uniform float sun_halo_power = 220.0;
uniform float sun_halo_strength = 0.55;
// Resplandor ancho alrededor del sol: es lo que da la sensacion de aire.
uniform float sun_glow_strength = 0.30;
uniform float sun_glow_power = 6.0;
// Suavizado de la linea de horizonte.
uniform float horizon_softness = 0.04;
// Curva del degradado: <1 sube el azul hacia el cenit mas rapido.
uniform float sky_curve = 0.42;
// Banda de bruma pegada al horizonte: sin ella el cielo se corta en seco.
uniform vec4 haze_color : source_color = vec4(0.88, 0.91, 0.94, 1.0);
uniform float haze_strength = 0.55;
uniform float haze_falloff = 9.0;

// --- Nubes ---
uniform float cloud_coverage = 0.42;      // 0 = despejado, 1 = cubierto
uniform float cloud_sharpness = 2.6;      // borde de los cumulos
uniform float cloud_scale = 2.4;          // tamaño de los cumulos
uniform float cloud_speed = 0.004;        // deriva
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.62, 0.66, 0.72, 1.0);
uniform float cloud_veil_strength = 0.22; // velo alto, cirros
uniform float cloud_veil_scale = 6.5;

// --- Noche ---
uniform float star_amount = 0.0;          // 0 de dia
uniform float star_size = 0.985;

varying vec3 local_dir;

// Ruido de valor con interpolacion suave. Barato y suficiente: las nubes se
// miran de lejos y a traves de una ventana.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.55);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(local_dir);
	float h = dir.y;

	// Degradado de cielo: horizonte claro -> cenit saturado.
	float t = clamp(pow(max(h, 0.0), sky_curve), 0.0, 1.0);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, t);

	// Bruma baja: el aire se acumula hacia el horizonte y lava el color.
	float haze = pow(clamp(1.0 - max(h, 0.0), 0.0, 1.0), haze_falloff);
	sky = mix(sky, haze_color.rgb, haze * haze_strength);

	// --- Nubes ---
	// Se proyecta la direccion sobre un plano alto: las nubes se estiran hacia
	// el horizonte igual que las de verdad, en vez de flotar como una bola.
	float above = smoothstep(0.005, 0.10, h);
	if (above > 0.0) {
		vec2 plane = dir.xz / max(h + 0.10, 0.05);
		vec2 drift = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);

		float veil = fbm(plane * cloud_veil_scale * 0.35 + drift * 0.4);
		sky = mix(sky, cloud_color.rgb, clamp(veil - 0.45, 0.0, 1.0) * cloud_veil_strength * above);

		float shape = fbm(plane * cloud_scale * 0.30 + drift);
		float density = clamp((shape - (1.0 - cloud_coverage)) * cloud_sharpness, 0.0, 1.0);
		// Un poco de relieve: la base de la nube mas oscura que la coronilla.
		float relief = fbm(plane * cloud_scale * 0.62 + drift * 1.7);
		vec3 cloud = mix(cloud_shadow_color.rgb, cloud_color.rgb, clamp(relief * 1.35, 0.0, 1.0));
		// Las nubes se desvanecen contra el horizonte, donde ya manda la bruma.
		sky = mix(sky, cloud, density * above * (1.0 - haze * haze_strength * 0.8));
	}

	// --- Estrellas (noche) ---
	if (star_amount > 0.0 && h > 0.0) {
		vec2 star_uv = dir.xz / max(h + 0.25, 0.05);
		float star_field = hash21(floor(star_uv * 140.0));
		float star = smoothstep(star_size, 1.0, star_field) * star_amount;
		sky += vec3(star) * smoothstep(0.0, 0.30, h);
	}

	// Suelo/bruma por debajo del horizonte.
	vec3 col = mix(ground_color.rgb, sky, smoothstep(-horizon_softness, horizon_softness, h));

	// --- Sol: disco nitido, halo ceñido y resplandor ancho ---
	vec3 sun_dir = normalize(sun_direction);
	float d = dot(dir, sun_dir);
	float disk = smoothstep(sun_cos_size, sun_cos_size + 0.0006, d);
	float halo = pow(max(d, 0.0), sun_halo_power) * sun_halo_strength;
	float glow = pow(max(d, 0.0), sun_glow_power) * sun_glow_strength;
	float sun_above = smoothstep(-0.02, 0.05, h);
	col = mix(col, sun_color.rgb, clamp(disk + halo + glow, 0.0, 1.0) * sun_above);

	ALBEDO = col;
}
