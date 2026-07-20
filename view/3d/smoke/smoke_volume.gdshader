shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 smoke_color : source_color = vec4(0.18, 0.19, 0.20, 0.34);
uniform float density = 1.0;
uniform float turbulence = 0.55;
uniform float drift_speed = 0.10;
uniform float volume_depth_m = 1.0;
uniform float edge_softness = 0.14;
uniform float bottom_waviness = 0.18;
uniform float edge_band_strength = 0.30;
uniform float side_visibility = 0.28;
uniform float bottom_surface_strength = 0.70;
uniform float top_visibility = 0.0;
uniform float vertical_gradient_strength = 0.68;
uniform float lower_density_floor = 0.30;
uniform float flow_strength = 0.0;
uniform float flow_speed = 0.30;
uniform float flow_direction = 0.0;
// Textura de ruido opcional (canal R) para sustituir/mezclar el ruido
// procedural. strength=0 -> solo procedural (sin coste extra apreciable).
uniform sampler2D noise_texture : hint_default_black;
uniform float noise_texture_strength : hint_range(0.0, 1.0) = 0.0;
uniform float noise_texture_uv_scale = 3.0;

varying float smoke_local_y;
varying float smoke_horizontal_face;
varying float smoke_normal_y;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	smoke_local_y = clamp((VERTEX.y / max(0.01, volume_depth_m)) + 0.5, 0.0, 1.0);
	smoke_horizontal_face = abs(NORMAL.y);
	smoke_normal_y = NORMAL.y;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * drift_speed;
	float n1 = noise(uv * 3.5 + vec2(t, -t * 0.7));
	float n2 = noise(uv * 8.0 + vec2(-t * 1.6, t * 1.1));
	float n = mix(n1, n2, turbulence);
	if (noise_texture_strength > 0.001) {
		float tex_n = texture(noise_texture, uv * noise_texture_uv_scale + vec2(t * 0.55, -t * 0.32)).r;
		n = mix(n, tex_n, noise_texture_strength);
	}
	float bottom_noise = noise(uv * 4.0 + vec2(t * 1.9, t * 0.7));
	float bottom_limit = 0.03 + bottom_noise * bottom_waviness;
	float bottom_fade = smoothstep(bottom_limit, bottom_limit + edge_softness, smoke_local_y);
	float edge_band = smoothstep(bottom_limit - edge_softness * 0.45, bottom_limit + edge_softness * 0.20, smoke_local_y)
		* (1.0 - smoothstep(bottom_limit + edge_softness * 0.55, bottom_limit + edge_softness * 1.70, smoke_local_y));
	float vertical_edge = smoothstep(0.00, 0.18, uv.y) * (1.0 - smoothstep(0.82, 1.0, uv.y));
	float side_edge = smoothstep(0.00, 0.05, uv.x) * (1.0 - smoothstep(0.95, 1.0, uv.x));
	float filament = smoothstep(0.18, 0.92, n);
	float bottom_face = smoothstep(0.18, 0.58, -smoke_normal_y);
	float top_face = smoothstep(0.18, 0.58, smoke_normal_y);
	float horizontal_face = max(bottom_face, top_face);
	float side_face = 1.0 - horizontal_face;
	float face_visibility = side_face * side_visibility + bottom_face + top_face * top_visibility;
	float height_gradient = mix(lower_density_floor, 1.0, smoothstep(0.02, 1.0, smoke_local_y));
	height_gradient = mix(1.0, height_gradient, vertical_gradient_strength);
	float bottom_sheet = bottom_face * smoke_color.a * density * bottom_surface_strength * mix(0.18, 0.64, filament) * height_gradient;
	float base_alpha = smoke_color.a * density * mix(0.11, 0.78, filament) * max(0.30, vertical_edge) * max(0.68, side_edge) * face_visibility * height_gradient;
	float flow_axis_mix = clamp(abs(flow_direction), 0.0, 1.0);
	float flow_axis = mix(uv.y, uv.x, flow_axis_mix);
	float flow_sign = flow_direction < 0.0 ? -1.0 : 1.0;
	// Frecuencia baja y fase decorrelacionada con el ruido: bandas de flujo
	// sueltas en vez de un patron de rayas que parece girar en el dintel.
	float moving_band = 0.5 + 0.5 * sin((flow_axis * flow_sign - TIME * flow_speed) * 6.5 + n * 5.2);
	float flow_filament = smoothstep(0.62, 0.98, moving_band) * side_face * flow_strength * (0.30 + filament * 0.55);
	float alpha = base_alpha * mix(0.26, 1.0, bottom_fade) + smoke_color.a * density * edge_band_strength * edge_band * side_face * side_visibility + bottom_sheet;
	alpha += smoke_color.a * density * flow_filament;
	ALBEDO = smoke_color.rgb * mix(0.62, 1.10, n);
	ALPHA = clamp(alpha, 0.0, min(0.99, smoke_color.a * (1.05 + flow_strength * 0.22)));
}
