extends RefCounted
## Materiales de humo. Shaders editables en Godot:
##  - view/3d/smoke/smoke_volume.gdshader
##  - view/3d/smoke/smoke_ceiling_mask.gdshader

const VolumeShader: Shader = preload("res://view/3d/smoke/smoke_volume.gdshader")
const CeilingMaskShader: Shader = preload("res://view/3d/smoke/smoke_ceiling_mask.gdshader")


static func create_volume(
	smoke_color: Color,
	noise_texture: Texture2D = null,
	noise_texture_strength: float = 0.0,
	noise_texture_uv_scale: float = 3.0
) -> ShaderMaterial:
	var shader: Shader = VolumeShader
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("smoke_color", smoke_color)
	if noise_texture != null and noise_texture_strength > 0.0:
		material.set_shader_parameter("noise_texture", noise_texture)
		material.set_shader_parameter("noise_texture_strength", noise_texture_strength)
		material.set_shader_parameter("noise_texture_uv_scale", noise_texture_uv_scale)
	material.set_shader_parameter("density", 0.72)
	material.set_shader_parameter("turbulence", 0.55)
	material.set_shader_parameter("drift_speed", 0.08)
	material.set_shader_parameter("volume_depth_m", 1.0)
	material.set_shader_parameter("meters_to_units", 1.0)
	material.set_shader_parameter("edge_softness", 0.14)
	material.set_shader_parameter("bottom_waviness", 0.18)
	material.set_shader_parameter("edge_band_strength", 0.30)
	material.set_shader_parameter("side_visibility", 0.22)
	material.set_shader_parameter("bottom_surface_strength", 0.72)
	material.set_shader_parameter("top_visibility", 0.0)
	material.set_shader_parameter("vertical_gradient_strength", 0.68)
	material.set_shader_parameter("lower_density_floor", 0.30)
	material.set_shader_parameter("flow_strength", 0.0)
	material.set_shader_parameter("flow_speed", 0.30)
	material.set_shader_parameter("flow_direction", 0.0)
	return material


static func create_ceiling_mask() -> ShaderMaterial:
	var shader: Shader = CeilingMaskShader
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("mask_color", Color(0.055, 0.052, 0.048, 1.0))
	material.set_shader_parameter("mask_alpha", 0.12)
	material.set_shader_parameter("density", 1.0)
	material.set_shader_parameter("drift_speed", 0.035)
	return material
