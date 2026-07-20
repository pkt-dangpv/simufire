shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 cap_color : source_color = vec4(1.0, 0.34, 0.05, 0.42);
uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.22, 0.70);
uniform float emission_energy = 0.95;
uniform float flicker_speed = 1.8;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
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

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float r = length(centered);
	float t = TIME * flicker_speed;
	float n = noise(UV * 7.0 + vec2(t, -t * 0.63));
	float broken_edge = 1.0 - smoothstep(0.58 + n * 0.18, 1.04, r);
	float tongues = smoothstep(0.34, 0.95, n) * broken_edge;
	float alpha = cap_color.a * broken_edge * mix(0.26, 1.0, tongues);
	vec3 col = mix(cap_color.rgb, core_color.rgb, tongues * (1.0 - smoothstep(0.0, 0.95, r)));
	ALBEDO = col;
	EMISSION = col * emission_energy;
	ALPHA = clamp(alpha, 0.0, cap_color.a);
}
