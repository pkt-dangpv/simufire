extends SceneTree

## Que tipo de calle sale para cada planta, y con que proporciones.
##
## La proporcion es el punto: lo que hay que mirar en esta tabla es la esbeltez
## (alto / frente). Una manzana ronda 1:1, una torre 1:4 y un rascacielos no
## deberia pasar de 1:6, o se lee como un lapiz.
##
##   <godot> --headless --path . --script res://tools/probe_urban_typology.gd

const PITCH: float = 2.85


func _initialize() -> void:
	print("plantas  altura   tipo          frente  fondo   esbeltez  ventanas  podio  retranq  corona")
	for plantas in [1, 4, 8, 12, 20, 21, 30, 40, 50, 51, 60, 70, 80]:
		var t: Dictionary = FPUrbanTypology.for_floors(plantas, PITCH)
		var altura: float = float(plantas) * PITCH
		print("%7d  %6.1f  %-12s  %6.1f  %6.1f  1:%-6.1f  %-8s  %5d  %7d  %s" % [
			plantas, altura, t["tier"], t["module_span_m"], t["depth_m"],
			altura / float(t["module_span_m"]), t["windows"],
			t["podium_floors"], (t["setbacks"] as Array).size(), t["crown"]])
	quit()
