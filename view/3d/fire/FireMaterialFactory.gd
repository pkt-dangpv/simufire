extends RefCounted


const FLAME_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 flame_color : source_color = vec4(1.0, 0.32, 0.04, 0.85);
uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.26, 1.0);
uniform float emission_energy = 1.35;
uniform float flicker_speed = 2.8;

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
	vec2 uv = UV;
	float t = TIME * flicker_speed;
	float n = noise(vec2(uv.x * 3.0, uv.y * 5.5 - t));
	float center = abs(uv.x - 0.5) * 2.0;
	float width = mix(0.70, 0.035, pow(uv.y, 0.68)) * mix(0.82, 1.16, n);
	float lick = sin((uv.y * 8.0 - t * 3.1) + n * 2.4) * 0.10 + (n - 0.5) * 0.15;
	float body = 1.0 - smoothstep(width, width + 0.18, center + lick);
	float base = smoothstep(0.0, 0.10, uv.y);
	float tip = 1.0 - smoothstep(0.66 + n * 0.16, 1.0, uv.y);
	float split = mix(0.74, 1.0, smoothstep(0.18, 0.82, noise(vec2(uv.x * 12.0 + t, uv.y * 6.0))));
	float alpha = clamp(body * base * tip * flame_color.a, 0.0, 1.0);
	vec3 col = mix(flame_color.rgb, core_color.rgb, clamp((1.0 - center) * (1.0 - uv.y * 0.45), 0.0, 1.0));
	ALBEDO = col;
	EMISSION = col * emission_energy;
	ALPHA = alpha * split;
}
"""

const FIRE_CAP_SHADER_CODE := """
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
"""


static func create_flame(color: Color, core_color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = FLAME_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("flame_color", color)
	material.set_shader_parameter("core_color", core_color)
	material.set_shader_parameter("emission_energy", 1.45)
	material.set_shader_parameter("flicker_speed", 2.4 + color.a)
	return material


static func create_ceiling_cap(color: Color, core_color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = FIRE_CAP_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cap_color", color)
	material.set_shader_parameter("core_color", core_color)
	material.set_shader_parameter("emission_energy", 0.95)
	material.set_shader_parameter("flicker_speed", 1.65 + color.a)
	return material
