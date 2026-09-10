extends RefCounted
class_name FloorNaming

## Como se llaman las plantas en toda la aplicacion.
##
## Convencion elegida el 2026-09-10: la planta a nivel de calle es la **rasante**
## y se escribe `R`; las de encima son `R+1`, `R+2`... No hay negativos porque
## todavia no hay sotanos. Antes se usaba la notacion espanola `PB` / `P1`, que
## sigue viva en los escenarios ya guardados: `migrated_name()` la reescribe al
## cargar, para que un escenario viejo no ensene dos convenciones a la vez.
##
## El nombre se genera aqui y solo aqui. Estaba repetido en el editor, el
## serializador, el minimapa y el selector de plantas del 2D, y bastaba tocar
## uno para que los cuatro dejaran de decir lo mismo.

## Separacion por defecto entre plantas cuando solo se conoce la cota en metros.
const DEFAULT_PITCH_M: float = 2.9

## Prefijo de la rasante. Cambiarlo aqui cambia toda la aplicacion.
const GROUND_LABEL: String = "R"


## Nombre de la planta numero `index`, contando la rasante como 0.
static func label(index: int) -> String:
	if index <= 0:
		return GROUND_LABEL
	return "%s+%d" % [GROUND_LABEL, index]


## Nombre de la planta cuyo suelo esta a `level_m` sobre la rasante.
static func label_for_level(level_m: float, pitch_m: float = DEFAULT_PITCH_M) -> String:
	var pitch: float = maxf(0.1, pitch_m)
	return label(maxi(0, int(round(level_m / pitch))))


## Nombre que hay que guardar para una planta que ya venia con `raw_name`.
##
## Un nombre generado por la aplicacion -vacio, `PB`, `P3` o un `R+2` de una
## carga anterior- se rehace desde el indice. Cualquier otro se respeta: hoy no
## hay forma de renombrar una planta a mano, pero un escenario editado a mano si
## puede traer un nombre propio y no es nuestro para pisarlo.
static func migrated_name(raw_name: String, index: int) -> String:
	if is_generated_name(raw_name):
		return label(index)
	return raw_name


## Si `raw_name` es uno de los nombres que genera la aplicacion, en cualquiera
## de las dos convenciones.
static func is_generated_name(raw_name: String) -> bool:
	var name: String = raw_name.strip_edges()
	if name == "":
		return true
	if name == "PB" or name == GROUND_LABEL:
		return true
	if name.begins_with("P") and name.substr(1).is_valid_int():
		return true
	if name.begins_with(GROUND_LABEL + "+") and name.substr(GROUND_LABEL.length() + 1).is_valid_int():
		return true
	return false
