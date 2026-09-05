extends Node

## Mide el tamano NATIVO de cada modelo de mobiliario, sin escalar.
##
## Si los modelos ya vienen a escala real, el ajuste correcto no es
## reescalarlos al hueco que declara el escenario, sino al reves.
##
##   <godot> --headless --path . res://tools/probe_furniture_assets.tscn

const DIR: String = "res://assets/fp/furniture"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var names: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		print("no se pudo abrir ", DIR)
		get_tree().quit(1)
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".tscn"):
			names.append(file_name.get_basename())
	names.sort()

	print("%-22s %8s %8s %8s" % ["asset", "ancho", "fondo", "alto"])
	for asset_name in names:
		var packed := ResourceLoader.load("%s/%s.tscn" % [DIR, asset_name]) as PackedScene
		if packed == null:
			print("%-22s  no carga" % asset_name)
			continue
		var instance := packed.instantiate() as Node3D
		if instance == null:
			print("%-22s  no es Node3D" % asset_name)
			continue
		add_child(instance)
		var aabb: AABB = _combined_aabb(instance)
		print("%-22s %8.2f %8.2f %8.2f" % [asset_name, aabb.size.x, aabb.size.z, aabb.size.y])
		remove_child(instance)
		instance.free()
	get_tree().quit(0)


func _combined_aabb(root: Node3D) -> AABB:
	var state: Array = [AABB(), false]
	_accumulate(root, Transform3D.IDENTITY, state)
	return state[0]


func _accumulate(node: Node, xform: Transform3D, state: Array) -> void:
	for child in node.get_children():
		var child_xform: Transform3D = xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var aabb: AABB = child_xform * mi.get_aabb()
				if not bool(state[1]):
					state[0] = aabb
					state[1] = true
				else:
					state[0] = (state[0] as AABB).merge(aabb)
		if child.get_child_count() > 0:
			_accumulate(child, child_xform, state)
