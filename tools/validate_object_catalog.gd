extends SceneTree

## Guardarrail del catalogo del editor: se puede colocar TODO lo que el visor
## sabe dibujar, y todo lo que se coloca arde de forma creible.
##
## El hallazgo D-2 era que el catalogo ofrecia 14 piezas y el visor sabia
## dibujar 38: no habia manera de amueblar un bano ni una cocina desde el
## disenador. La causa no era una decision, era la forma del codigo -un `match`
## de 250 lineas donde anadir una pieza costaba veinte-.
##
## Esta red fija cuatro cosas, y la primera vale ademas como **lista de la
## compra del kit de modelos nuevo**: los arquetipos son el contrato entre lo
## que el editor coloca, lo que el clasificador reconoce y lo que la vista
## dibuja. Si el kit nuevo no cubre un arquetipo, es aqui donde se ve.
##
##  1. Todo arquetipo del clasificador se puede colocar desde el editor.
##  2. Todo lo del catalogo tiene medidas reales en `FurnitureDimensions`.
##  3. Ninguna pieza sale con el arquetipo adivinado: lo trae escrito.
##  4. La carga de fuego es de este mundo -energia y potencia positivas,
##     ignicion entre 200 y 450 C, rendimientos de humo y CO por encima de cero
##     y por debajo de lo que da un plastico-.
##
##   <godot> --headless --path . --script res://tools/validate_object_catalog.gd

const ObjectLibraryScript := preload("res://editor/ObjectLibrary.gd")
const FurnitureVisualClassifier := preload("res://view/3d/furniture/FurnitureVisualClassifier.gd")
const FurnitureDimensions := preload("res://view/furniture/FurnitureDimensions.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var cubiertos: Dictionary = {}
	for kind in ObjectLibraryScript.get_object_kinds():
		var obj: Dictionary = ObjectLibraryScript.create_object(kind, "probe", 0, Vector2.ZERO)
		var arquetipo: String = String(obj.get("visual_archetype", ""))

		# 3. El arquetipo va escrito.
		if arquetipo == "":
			_failures.append("%s sale del catalogo sin arquetipo: la vista tendria que adivinarlo" % kind)
			continue
		if not FurnitureVisualClassifier.ARCHETYPES.has(arquetipo):
			_failures.append("%s dice ser '%s' y ese arquetipo no existe" % [kind, arquetipo])
			continue
		cubiertos[arquetipo] = true

		# 2. Y tiene medidas reales que imponer.
		if not FurnitureDimensions.SPECS.has(arquetipo):
			_failures.append("%s (%s) no tiene ficha de medidas: saldria con el tamano que diga el escenario" % [kind, arquetipo])

		_check_fire(kind, obj)

	# 1. No falta ningun arquetipo por colocar.
	var faltan: Array[String] = []
	for arquetipo in FurnitureVisualClassifier.ARCHETYPES:
		if not cubiertos.has(arquetipo):
			faltan.append(arquetipo)
	if not faltan.is_empty():
		_failures.append("%d arquetipos que el visor dibuja no se pueden colocar desde el editor: %s" % [
			faltan.size(), ", ".join(faltan)])

	if _failures.is_empty():
		print("  catalogo: %d piezas, %d arquetipos de %d" % [
			ObjectLibraryScript.get_object_kinds().size(),
			cubiertos.size(), FurnitureVisualClassifier.ARCHETYPES.size()])
		print("OBJECT CATALOG VALIDATION PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[validate_object_catalog] FAIL: " + failure)
	print("OBJECT CATALOG VALIDATION FAILED")
	quit(1)


## La carga de fuego de una pieza tiene que ser de este mundo.
func _check_fire(kind: String, obj: Dictionary) -> void:
	var mj: float = float(obj.get("fuel_energy_MJ", 0.0))
	var kw: float = float(obj.get("max_hrr_kw", 0.0))
	var t_ign: float = float(obj.get("ignition_temp_c", 0.0))
	var humo: float = float(obj.get("smoke_yield_kg_per_MJ", 0.0))
	var co: float = float(obj.get("co_yield_kg_per_MJ", 0.0))
	if mj <= 0.0 or kw <= 0.0:
		_failures.append("%s no arde: %.0f MJ y %.0f kW" % [kind, mj, kw])
	if t_ign < 200.0 or t_ign > 450.0:
		_failures.append("%s prende a %.0f C, fuera del rango creible (200-450)" % [kind, t_ign])
	# Un rendimiento de humo por encima de 0,04 kg/MJ ya no es un mueble: es
	# poliuretano puro. Por debajo de 0,004, no hace humo ni la madera.
	if humo < 0.004 or humo > 0.040:
		_failures.append("%s da %.4f kg de humo por MJ, fuera de rango (0,004-0,040)" % [kind, humo])
	if co <= 0.0 or co > 0.003:
		_failures.append("%s da %.5f kg de CO por MJ, fuera de rango (0-0,003)" % [kind, co])
	if float(obj.get("remaining_fuel_MJ", 0.0)) != mj:
		_failures.append("%s empieza con menos combustible del que tiene" % kind)
	if float(obj.get("o2_consumption_kg_per_MJ", 0.0)) <= 0.0:
		_failures.append("%s no consume oxigeno al arder" % kind)
