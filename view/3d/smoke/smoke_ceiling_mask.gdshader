shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 mask_color : source_color = vec4(0.055, 0.052, 0.048, 1.0);
uniform float mask_alpha = 0.12;
uniform float density = 1.0;
uniform float drift_speed = 0.035;

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

void fragment() {
	float n1 = noise(UV * 4.0 + vec2(TIME * drift_speed, -TIME * drift_speed * 0.7));
	float n2 = noise(UV * 10.0 + vec2(-TIME * drift_speed * 2.1, TIME * drift_speed));
	float n = mix(n1, n2, 0.52);
	float sheet = mix(0.84, 1.18, smoothstep(0.12, 0.92, n));
	ALBEDO = mask_color.rgb * mix(0.72, 1.06, n);
	ALPHA = clamp(mask_alpha * density * sheet, 0.0, 0.98);
}
