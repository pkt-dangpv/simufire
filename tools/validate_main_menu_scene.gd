extends SceneTree
## Valida que MainMenu.tscn contiene toda la UI (bind-only, sin fallback de
## codigo) y que el script la puebla correctamente.
## Uso: godot --headless --path . --script res://tools/validate_main_menu_scene.gd

var _stage: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load("res://scenes/MainMenu.tscn") as PackedScene
	if packed == null:
		print("[validate_main_menu] FAIL: no se pudo cargar MainMenu.tscn")
		quit(1)
		return
	var menu := packed.instantiate()
	menu.name = "MainMenu"
	root.add_child(menu)


func _process(_delta: float) -> bool:
	if _stage == 0:
		_stage = 1
		return false
	_run_checks()
	if _failures.is_empty():
		print("[validate_main_menu] PASS")
		quit(0)
	else:
		for failure in _failures:
			print("[validate_main_menu] FAIL: ", failure)
		quit(1)
	return true


func _run_checks() -> void:
	var menu := root.get_node_or_null("MainMenu")
	if menu == null:
		_failures.append("MainMenu no instanciado")
		return
	_expect_node(menu, "Center/VBox/Logo")
	_expect_node(menu, "Center/VBox/Subtitle")
	for row in ["PresetRow", "BuildingTypeRow", "ApartmentFloorRow", "HvacRow", "LightingRow", "InteriorLightsRow", "GlassBreakRow"]:
		_expect_node(menu, "Center/VBox/%s" % row)
	for btn in ["BtnNewSim", "BtnEditor", "BtnQuit"]:
		_expect_node(menu, "Center/VBox/%s" % btn)

	var template := menu.get_node_or_null("Center/VBox/PresetRow/Option") as OptionButton
	if template == null or template.item_count < 2:
		_failures.append("PresetRow/Option sin poblar (items=%d)" % (template.item_count if template != null else -1))
	var glass := menu.get_node_or_null("Center/VBox/GlassBreakRow/Option") as OptionButton
	if glass == null or glass.item_count != 3:
		_failures.append("GlassBreakRow/Option debe tener 3 items")
	var floor_row := menu.get_node_or_null("Center/VBox/ApartmentFloorRow") as Control
	var building := menu.get_node_or_null("Center/VBox/BuildingTypeRow/Option") as OptionButton
	if floor_row != null and building != null:
		var expected_visible: bool = building.selected == 1
		if floor_row.visible != expected_visible:
			_failures.append("ApartmentFloorRow.visible=%s no coincide con tipo edificio seleccionado" % floor_row.visible)
	if menu.theme == null:
		_failures.append("MainMenu sin theme asignado (debe ser assets/ui/simufire_theme.tres)")


func _expect_node(menu: Node, path: String) -> void:
	if menu.get_node_or_null(path) == null:
		_failures.append("falta nodo %s en la escena" % path)
