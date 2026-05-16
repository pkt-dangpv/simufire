extends RefCounted

const SMOKE_TEXTURE_LIGHT := preload("res://assets/smoke/02_humo_superior_ligero_spritesheet_128.png")
const SMOKE_TEXTURE_MEDIUM := preload("res://assets/smoke/03_humo_superior_medio_spritesheet_128.png")
const SMOKE_TEXTURE_DENSE := preload("res://assets/smoke/04_humo_superior_denso_spritesheet_128.png")


static func create_puff_sprite(node_name: String) -> Sprite3D:
	var node := Sprite3D.new()
	node.name = node_name
	node.texture = SMOKE_TEXTURE_MEDIUM
	node.hframes = 8
	node.vframes = 1
	node.frame = 0
	node.pixel_size = 0.010
	node.modulate = Color(0.72, 0.74, 0.76, 0.28)
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.double_sided = true
	node.shaded = false
	node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_disable_shadow_casting(node)
	return node


static func texture_for_alpha(alpha: float) -> Texture2D:
	if alpha > 0.54:
		return SMOKE_TEXTURE_DENSE
	if alpha > 0.30:
		return SMOKE_TEXTURE_MEDIUM
	return SMOKE_TEXTURE_LIGHT


static func _disable_shadow_casting(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_disable_shadow_casting(child)
