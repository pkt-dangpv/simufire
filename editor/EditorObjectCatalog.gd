extends RefCounted
class_name EditorObjectCatalog

## El catalogo de mobiliario del editor: la lista de piezas y su vista previa
## en 3D. Segundo modulo sacado del monolito (D-1).
##
## Esto es todo lo que hace falta para **elegir** una pieza. Lo que pasa
## despues -moverla, girarla, redimensionarla, borrarla- sigue en el editor:
## esa mitad esta enredada con el arrastre, la seleccion y el deshacer, y
## sacarla pide su propia pasada con sondas. Separarlas por ahi no es una linea
## arbitraria: elegir es de la interfaz, editar es del documento.
##
## La vista previa monta la pieza con **el mismo cargador que usa la vista 3D**,
## asi que lo que se ve aqui es lo que se va a dibujar, no una ilustracion
## aparte. Hoy los 38 arquetipos tienen modelo propio -lo que esta sin envolver
## son .glb del kit que el catalogo no usa-, asi que la caja a escala es un
## camino de reserva: se mantiene y se DICE, porque el kit va a cambiar entero
## y una pieza sin modelo tiene que ensenar algo honesto en vez de un hueco.

const ObjectLibraryScript = preload("res://editor/ObjectLibrary.gd")
const FurnitureDimensionsScript = preload("res://view/furniture/FurnitureDimensions.gd")
const FurnitureAssetLoaderScript = preload("res://view/3d/furniture/FurnitureAssetLoader.gd")

## Pieza que se ensena cuando el catalogo aun no ha elegido ninguna.
const FALLBACK_KIND: String = "sofa"

var list: ItemList = null

var _editor: Node = null
var _preview: Control = null
var _preview_root: Node3D = null
var _preview_camera: Camera3D = null
var _preview_label: Label = null
## Ultima pieza montada. Se compara para no rehacer el 3D cuando el catalogo
## emite seleccion sin que cambie la pieza -al recolocarse, por ejemplo-.
var _preview_kind: String = ""


func setup(editor: Node) -> void:
	_editor = editor
	list = _left("ObjectCatalog") as ItemList
	_preview = _left("ObjectPreview") as Control
	var base: String = "ObjectPreview/ObjectPreviewViewportContainer/ObjectPreviewViewport/"
	_preview_root = _left(base + "ObjectPreviewRoot") as Node3D
	_preview_camera = _left(base + "ObjectPreviewCamera") as Camera3D
	_preview_label = _left("ObjectPreview/ObjectPreviewLabel") as Label


func _left(path: String) -> Node:
	return _editor.call("_get_left_node", path)


## Llena el catalogo: cada pieza con su nombre en castellano y su medida, que
## es lo que hace falta para elegir. El identificador interno viaja en la
## metadata.
func populate(on_gui_input: Callable) -> void:
	if list == null:
		return
	list.clear()
	for kind in ObjectLibraryScript.get_object_kinds():
		var size_m: Vector2 = ObjectLibraryScript.size_m(kind)
		var index: int = list.add_item("%s  ·  %.2f × %.2f m" % [
			ObjectLibraryScript.display_name(kind), size_m.x, size_m.y])
		list.set_item_metadata(index, kind)
		list.set_item_tooltip(index, "Arrastra %s al plano, o selecciónalo y pulsa dentro de una habitación." % ObjectLibraryScript.display_name(kind))
	if list.item_count > 0:
		list.select(0)
	if not list.gui_input.is_connected(on_gui_input):
		list.gui_input.connect(on_gui_input)
	if not list.item_selected.is_connected(_on_item_selected):
		list.item_selected.connect(_on_item_selected)
	# La pieza NO se monta aqui. Llenar el catalogo pasa al arrancar el editor,
	# y montar un modelo 3D entonces cuesta tiempo de carga y deja piezas
	# colgando del arbol de interfaz antes de que nadie haya pedido verlas.
	# Se monta cuando la vista previa se ensena.


## La pieza elegida en el catalogo.
func selected_kind() -> String:
	if list == null:
		return FALLBACK_KIND
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty():
		return FALLBACK_KIND
	var meta: Variant = list.get_item_metadata(selected[0])
	return String(meta) if meta != null else FALLBACK_KIND


## Ensena u oculta la vista previa con el resto de mandos de la herramienta.
func set_preview_visible(visible: bool) -> void:
	if _preview == null:
		return
	_preview.visible = visible
	if not visible:
		return
	refresh_preview()
	# El panel es largo -plantas, edificio, entorno- y la vista previa cae por
	# debajo del borde: al elegir la herramienta de objeto se desplaza hasta
	# ella, que es lo que se acaba de pedir ver.
	_editor.call_deferred("_scroll_left_panel_to", _preview)


func _on_item_selected(_index: int) -> void:
	refresh_preview()


## Monta la pieza elegida en el visor, si ha cambiado.
func refresh_preview() -> void:
	if _preview_root == null or _preview_label == null:
		return
	var kind: String = selected_kind()
	if kind == _preview_kind:
		return
	_preview_kind = kind
	for child in _preview_root.get_children():
		child.queue_free()

	var footprint_m: Vector2 = ObjectLibraryScript.size_m(kind)
	var archetype: String = ObjectLibraryScript.visual_archetype(kind)
	# La altura la manda quien dibuja, no el catalogo: la columna `alto` de la
	# tabla es la ELEVACION sobre el suelo, no lo que mide la pieza.
	var height_m: float = FurnitureDimensionsScript.height_m(archetype)
	var target_m := Vector3(footprint_m.x, maxf(0.05, height_m), footprint_m.y)
	var achieved: Vector3 = FurnitureAssetLoaderScript.try_build(_preview_root, archetype, target_m, 1.0)
	var con_modelo: bool = achieved != Vector3.ZERO
	if not con_modelo:
		achieved = target_m
		_preview_root.add_child(_box(
			"CajaAEscala",
			target_m,
			Vector3(0.0, target_m.y * 0.5, 0.0),
			Color(0.62, 0.44, 0.30, 1.0),
			0.85
		))

	# Un suelo bajo la pieza: sin el, un mueble bajo flota en el vacio y no se
	# sabe a que altura esta.
	var span: float = maxf(0.8, maxf(achieved.x, achieved.z) * 1.9)
	_preview_root.add_child(_box(
		"SueloPrevio",
		Vector3(span, 0.02, span),
		Vector3(0.0, -0.01, 0.0),
		Color(0.14, 0.17, 0.19, 1.0),
		1.0
	))

	_frame_preview(achieved)
	_preview_label.text = "%s  ·  %.2f × %.2f × %.2f m\n%s" % [
		ObjectLibraryScript.display_name(kind),
		achieved.x, achieved.z, achieved.y,
		"modelo propio" if con_modelo else "sin modelo: caja a escala"
	]


func _box(node_name: String, size_m: Vector3, position: Vector3, color: Color, roughness: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size_m
	mesh.mesh = box
	mesh.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	mesh.material_override = material
	return mesh


## Aparta la camara lo justo para que quepa la pieza, mirando a media altura.
## Una silla y un armario no se encuadran igual.
func _frame_preview(size_m: Vector3) -> void:
	if _preview_camera == null:
		return
	var radius: float = maxf(0.35, size_m.length() * 0.5)
	var distance: float = radius / tan(deg_to_rad(_preview_camera.fov * 0.5)) * 1.35
	var target := Vector3(0.0, size_m.y * 0.5, 0.0)
	var direction := Vector3(0.72, 0.52, 0.9).normalized()
	_preview_camera.position = target + direction * distance
	_preview_camera.look_at(target, Vector3.UP)
