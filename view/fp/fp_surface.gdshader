shader_type spatial;
// Material de las superficies construidas por codigo en primera persona:
// muros, suelos y techos.
//
// Hace dos cosas que StandardMaterial3D no puede hacer a la vez:
//
// 1. Ruido de superficie proyectado en METROS (triplanar en coordenadas de
//    mundo), para que un tabique de 6 m y una jamba de 0,2 m tengan el mismo
//    grano y el patron encaje entre piezas contiguas.
// 2. Oclusion ambiental de contacto sin mapa de AO ni SSAO —que GL
//    Compatibility no tiene— oscureciendo la franja cercana a las aristas de
//    la caja. Como el tamano de la caja entra por instancia, el ancho de esa
//    franja se mide en metros y el material sigue siendo unico y compartible
//    (M-2 en docs/AUDITORIA_VISUAL_2026-08-29.md).

uniform vec4 albedo : source_color = vec4(0.80, 0.80, 0.75, 1.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.96;
uniform sampler2D surface_noise : source_color, hint_default_white;
uniform bool use_noise = true;
// Ciclos de textura por metro: es 1 / tamano_del_patron_en_metros.
uniform float noise_cycles_per_m = 0.55;
// Cuanto se oscurece la arista y en cuantos metros se difumina.
uniform float ao_strength : hint_range(0.0, 1.0) = 0.35;
uniform float ao_band_m : hint_range(0.0, 2.0) = 0.35;

// Tamano de la caja en metros. Va por instancia para no tener que crear un
// material por cada tamano de pieza.
instance uniform vec3 box_size_m = vec3(1.0, 1.0, 1.0);

varying vec3 local_pos;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// La normal en fragment() viene en espacio de vista; para mezclar el
	// triplanar hace falta la de mundo.
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar_noise(vec3 pos_m, vec3 normal_ws) {
	vec3 blend = pow(abs(normal_ws), vec3(4.0));
	blend /= max(dot(blend, vec3(1.0)), 0.0001);
	vec2 uv_x = pos_m.zy * noise_cycles_per_m;
	vec2 uv_y = pos_m.xz * noise_cycles_per_m;
	vec2 uv_z = pos_m.xy * noise_cycles_per_m;
	return texture(surface_noise, uv_x).rgb * blend.x
		+ texture(surface_noise, uv_y).rgb * blend.y
		+ texture(surface_noise, uv_z).rgb * blend.z;
}

// Oscurecimiento cerca de las aristas de la caja. Sobre una cara, una de las
// tres distancias a las caras opuestas es ~0 (la de la propia cara), asi que
// la distancia util a la arista es la SEGUNDA menor de las tres.
float edge_occlusion(vec3 local_m, vec3 size_m) {
	vec3 half_size = max(size_m * 0.5, vec3(0.001));
	vec3 d = half_size - abs(local_m);
	float d_min = min(d.x, min(d.y, d.z));
	float d_max = max(d.x, max(d.y, d.z));
	float d_mid = d.x + d.y + d.z - d_min - d_max;
	return mix(1.0 - ao_strength, 1.0, smoothstep(0.0, max(0.001, ao_band_m), d_mid));
}

void fragment() {
	vec3 color = albedo.rgb;
	if (use_noise) {
		color *= triplanar_noise(world_pos, normalize(world_normal));
	}
	if (ao_strength > 0.0) {
		color *= edge_occlusion(local_pos, box_size_m);
	}
	ALBEDO = color;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
}
