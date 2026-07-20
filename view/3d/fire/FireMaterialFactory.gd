extends RefCounted
## Materiales de fuego. Shaders editables en Godot:
##  - view/3d/fire/fire_flame.gdshader
##  - view/3d/fire/fire_ceiling_cap.gdshader

const FlameShader: Shader = preload("res://view/3d/fire/fire_flame.gdshader")
const CeilingCapShader: Shader = preload("res://view/3d/fire/fire_ceiling_cap.gdshader")


static func create_flame(color: Color, core_color: Color) -> ShaderMaterial:
	var shader: Shader = FlameShader
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("flame_color", color)
	material.set_shader_parameter("core_color", core_color)
	material.set_shader_parameter("emission_energy", 1.45)
	material.set_shader_parameter("flicker_speed", 2.4 + color.a)
	return material


static func create_ceiling_cap(color: Color, core_color: Color) -> ShaderMaterial:
	var shader: Shader = CeilingCapShader
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cap_color", color)
	material.set_shader_parameter("core_color", core_color)
	material.set_shader_parameter("emission_energy", 0.95)
	material.set_shader_parameter("flicker_speed", 1.65 + color.a)
	return material
