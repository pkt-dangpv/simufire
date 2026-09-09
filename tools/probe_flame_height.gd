extends SceneTree

## Cuanto mide la llama que se dibuja, y cuanto deberia medir.
##
## Nace del hallazgo G-5: con **850 kW y 340 C** en el HUD se ve una llama de
## aproximadamente un metro en un extremo del sofa. El numero y la imagen no
## hablan de lo mismo, y en un simulador de incendios eso es lo peor que puede
## pasar.
##
## La referencia no es una opinion: la **correlacion de Heskestad** para la
## altura media de llama de un fuego de penacho libre, que es la que usan los
## manuales de ingenieria de proteccion contra incendios (SFPE):
##
##     L = 0,235 · Q^(2/5) − 1,02 · D
##
## con Q el calor liberado en kW y D el diametro de la base del fuego en metros.
## El termino de D es lo que hace que un mismo calor de una llama alta y flaca
## en un cubo de basura y una llama baja y ancha en un sofa.
##
## La ley que habia era otra cosa: `0,18 + sqrt(HRR/1000) · 1,75`, dos mandos
## elegidos a ojo y sin diametro. Esta sonda compara las dos.
##
##   <godot> --headless --path . --script res://tools/probe_flame_height.gd

## Lo que valian los mandos de la ley vieja.
const VIEJA_REF_KW: float = 1000.0
const VIEJA_MAX_M: float = 1.75


func _initialize() -> void:
	print("Altura de llama, ley vieja contra Heskestad")
	print("")
	print("  foco                     HRR kW    D (m)   vieja    Heskestad   falta")
	for caso in [
		{"que": "papelera", "kw": 100.0, "d": 0.30},
		{"que": "papelera", "kw": 250.0, "d": 0.30},
		{"que": "sillon", "kw": 500.0, "d": 1.05},
		{"que": "sofa (el del HUD)", "kw": 850.0, "d": 1.51},
		{"que": "sofa", "kw": 1400.0, "d": 1.51},
		{"que": "cama", "kw": 1200.0, "d": 1.89},
		{"que": "cocina en llamas", "kw": 2500.0, "d": 2.00},
		{"que": "sala en flashover", "kw": 4000.0, "d": 2.50},
	]:
		var kw: float = float(caso["kw"])
		var d: float = float(caso["d"])
		var vieja: float = 0.18 + clampf(sqrt(kw / VIEJA_REF_KW), 0.0, 1.35) * VIEJA_MAX_M
		var hesk: float = maxf(0.0, 0.235 * pow(kw, 0.4) - 1.02 * d)
		print("  %-22s %7.0f  %6.2f  %6.2f m  %8.2f m  %+6.2f m" % [
			caso["que"], kw, d, vieja, hesk, hesk - vieja])
	print("")
	print("El diametro sale de la huella del foco: D = sqrt(4·A/pi).")
	print("Un sofa de 2,00 x 0,90 son 1,80 m2 y D = 1,51 m.")
	quit()
