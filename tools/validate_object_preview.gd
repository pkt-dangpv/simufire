extends SceneTree
## Guardarrail de la vista previa 3D del catalogo de mobiliario.
##
## Peticion del usuario del 2026-09-10: el catalogo era una lista de nombres y
## medidas, y «mesa de centro» no dice como es la mesa. Ahora ensena la pieza
## como la va a dibujar la vista 3D.
##
## Lo que se vigila:
##
##  1. **Cada pieza del catalogo se puede previsualizar**: tiene arquetipo,
##     medidas y algo que ensenar. Un catalogo con una pieza que no se puede
##     dibujar es un catalogo con una trampa.
##  2. **La vista previa construye de verdad**, y construye lo de la pieza
##     elegida: al cambiar de pieza cambia lo que hay en el visor.
##  3. **La ficha dice la verdad**: las medidas que ensena son las del
##     catalogo, y avisa cuando lo que se ve es una caja y no un modelo.
##
##   <godot> --headless --path . --script res://tools/validate_object_preview.gd

const ObjectLibraryScript = preload("res://editor/ObjectLibrary.gd")
const FurnitureAssetLoaderScript = preload("res://view/3d/furniture/FurnitureAssetLoader.gd")
const FurnitureDimensionsScript = preload("res://view/furniture/FurnitureDimensions.gd")

var _editor: Node = null
var _frames: int = 0
var _fails: int = 0


func _initialize() -> void:
	var packed := load("res://scenes/ScenarioEditorScene.tscn") as PackedScene
	_editor = packed.instantiate()
	root.add_child(_editor)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	# 1. Todo el catalogo es previsualizable.
	var kinds: Array = ObjectLibraryScript.get_object_kinds()
	if kinds.size() < 38:
		_fail("el catalogo tiene %d piezas y deberia tener al menos 38" % kinds.size())
	for kind in kinds:
		var archetype: String = ObjectLibraryScript.visual_archetype(String(kind))
		if archetype == "":
			_fail("%s no declara arquetipo visual" % String(kind))
		var size_m: Vector2 = ObjectLibraryScript.size_m(String(kind))
		if size_m.x <= 0.0 or size_m.y <= 0.0:
			_fail("%s no tiene huella" % String(kind))
		if FurnitureDimensionsScript.height_m(archetype) <= 0.0:
			_fail("%s (%s) no tiene altura para dibujarse" % [String(kind), archetype])
		if ObjectLibraryScript.elevation_m(String(kind)) < 0.0:
			_fail("%s tiene elevacion negativa" % String(kind))

	# 2 y 3. El visor construye la pieza elegida y la ficha la describe.
	# El catalogo se mudo a `editor/EditorObjectCatalog.gd` (D-1). Las
	# comprobaciones son las mismas; solo cambia por donde se llega a ellas.
	var modulo = _editor._catalog
	var catalog: ItemList = modulo.list if modulo != null else null
	var preview_root: Node3D = modulo._preview_root if modulo != null else null
	var label: Label = modulo._preview_label if modulo != null else null
	if catalog == null or preview_root == null or label == null:
		_fail("falta la vista previa del catalogo en ScenarioEditorScene.tscn")
		_finish()
		return true

	var visto_antes: String = ""
	for index in [0, 5, 12, 20]:
		if index >= catalog.item_count:
			continue
		catalog.select(index)
		modulo.refresh_preview()
		var kind: String = String(catalog.get_item_metadata(index))
		if preview_root.get_child_count() < 2:
			_fail("%s no construyo nada en el visor" % kind)
			continue
		var texto: String = String(label.text)
		if not texto.begins_with(ObjectLibraryScript.display_name(kind)):
			_fail("la ficha dice «%s» y la pieza elegida es %s" % [texto, kind])
		var esperada: String = "%.2f × %.2f" % [
			ObjectLibraryScript.size_m(kind).x, ObjectLibraryScript.size_m(kind).y
		]
		var con_modelo: bool = FurnitureAssetLoaderScript.has_model(ObjectLibraryScript.visual_archetype(kind))
		if not con_modelo and not texto.contains("caja a escala"):
			_fail("%s se dibuja como caja y la ficha no lo dice" % kind)
		if con_modelo and not texto.contains("modelo propio"):
			_fail("%s tiene modelo y la ficha no lo dice" % kind)
		if not con_modelo and not texto.contains(esperada):
			_fail("la caja de %s deberia medir %s y la ficha dice «%s»" % [kind, esperada, texto])
		if texto == visto_antes:
			_fail("al cambiar de pieza la ficha no cambio: sigue en «%s»" % texto)
		visto_antes = texto

	_finish()
	return true


func _fail(message: String) -> void:
	_fails += 1
	push_error("- " + message)


func _finish() -> void:
	if _fails == 0:
		print("[validate_object_preview] PASS")
	else:
		push_error("[validate_object_preview] FAILED")
	quit(0 if _fails == 0 else 1)
