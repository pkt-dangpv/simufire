extends RefCounted
class_name GraphicsQuality

## Traduce «bajo / medio / alto» a lo que de verdad cuesta fotogramas.
##
## Decision del usuario del 2026-09-10: **un solo mando de tres niveles**, no
## una lista de casillas. Quien abre la configuracion de un simulador de
## incendios no tiene por que saber que es el MSAA; sabe si su portatil va
## justo.
##
## Lo que toca cada nivel, y por que esos y no otros: son las tres cosas que
## midieron caro en las auditorias de 2026-09-09 —sombras del sol, suavizado y
## densidad del decorado urbano— mas la escala de render, que es el mando que
## mas fotogramas devuelve en una maquina flaca.
##
## Los valores del decorado los lee `FirstPersonController` al reconstruir; los
## de sombra y suavizado son de proyecto y se aplican en caliente.

const AppSettingsScript = preload("res://ui/AppSettings.gd")


## Ficha de un nivel. `render_scale` por debajo de 1 renderiza a menos
## resolucion y reescala: es feo de cerca y es lo que salva una integrada.
static func profile(level: String) -> Dictionary:
	match level:
		AppSettingsScript.QUALITY_LOW:
			return {
				"shadows_enabled": false,
				"shadow_size": 1024,
				"soft_shadow_quality": 0,
				"msaa_3d": Viewport.MSAA_DISABLED,
				"render_scale": 0.75,
				"city_back_blocks": 2,
				"city_props_factor": 0.35,
				"fp_furniture": true,
			}
		AppSettingsScript.QUALITY_MEDIUM:
			return {
				"shadows_enabled": true,
				"shadow_size": 2048,
				"soft_shadow_quality": 1,
				"msaa_3d": Viewport.MSAA_2X,
				"render_scale": 1.0,
				"city_back_blocks": 4,
				"city_props_factor": 0.7,
				"fp_furniture": true,
			}
	return {
		"shadows_enabled": true,
		"shadow_size": 4096,
		"soft_shadow_quality": 3,
		"msaa_3d": Viewport.MSAA_2X,
		"render_scale": 1.0,
		"city_back_blocks": 5,
		"city_props_factor": 1.0,
		"fp_furniture": true,
	}


## Aplica lo que se puede cambiar sin reconstruir nada: suavizado y escala de
## render del viewport. Las sombras y el decorado los lee quien los construye.
static func apply_to_viewport(viewport: Viewport, level: String) -> void:
	if viewport == null:
		return
	var p: Dictionary = profile(level)
	viewport.msaa_3d = int(p.get("msaa_3d", Viewport.MSAA_2X))
	var scale: float = float(p.get("render_scale", 1.0))
	if scale < 0.999:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = scale


## Lo que tiene que mirar el mundo de primera persona al construirse.
static func apply_to_first_person(fp: Node, level: String) -> void:
	if fp == null:
		return
	var p: Dictionary = profile(level)
	if "city_back_block_count" in fp:
		fp.set("city_back_block_count", int(p.get("city_back_blocks", 5)))
	if "exterior_sky_light_cast_shadows" in fp:
		fp.set("exterior_sky_light_cast_shadows", bool(p.get("shadows_enabled", true)))
	if "show_fp_furniture" in fp:
		fp.set("show_fp_furniture", bool(p.get("fp_furniture", true)))
	var factor: float = float(p.get("city_props_factor", 1.0))
	for prop_name in [
		"city_lamp_count", "city_bin_count", "city_bench_count",
		"city_bollard_count", "city_sign_count", "city_planter_count",
	]:
		if prop_name in fp:
			fp.set(prop_name, maxi(0, int(round(float(fp.get(prop_name)) * factor))))
