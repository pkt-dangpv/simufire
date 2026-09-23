extends RefCounted
class_name TenabilityPresentation

## Fase 1 de la revision FED/SVV: como se PRESENTAN estos numeros, y solo eso.
##
## Este fichero no calcula nada. Ni una formula, ni un umbral, ni una curva: lee
## lo que el estado de sala ya trae y decide con que palabras se enseña. El
## calculo vive en `ThermalSystem`, que esta fase NO toca.
##
## ## Por que existe
##
## El indice combinado se enseñaba en cuatro sitios bajo la etiqueta «SVV», y en
## los cuatro el valor mostrado era `svv_worst_pct`, el PEOR HISTORICO, no el
## calculado ahora. Al ventilar una sala el numero no se movia, porque un minimo
## historico no se mueve. Ademas dos de esos sitios FABRICABAN un valor a partir
## de `layer_150c_m` cuando el campo faltaba, de modo que un estado antiguo
## enseñaba un numero inventado sin decirlo.
##
## ## Que es el indice, y que no es
##
## Es un INDICE HEURISTICO DE CONDICIONES: el minimo entre un criterio termico,
## uno de dosis acumulada (FED) y uno de visibilidad. No es una probabilidad de
## supervivencia, no esta validado clinicamente y no debe presentarse con
## vocabulario medico.
##
## Ojo con «actual»: el indice se CALCULA en este instante, pero uno de sus
## componentes es la FED acumulada, que no baja. Por eso el indice calculado
## ahora puede seguir bajo despues de ventilar. Se dice «calculado ahora», no
## «instantaneo».
##
## ## Visibilidad
##
## Que la visibilidad participe en el indice es razonable: con menos de un metro
## de vision escapar es mas dificil. Lo que no es defendible es leer ese 0 % como
## «0 % de supervivencia». Por eso el indice se nombra por lo que mide -las
## condiciones- y no por un desenlace.
##
## ## Campo ausente
##
## Cuando el estado no trae el campo se dice `n/d`. No se deduce el actual desde
## el peor historico ni al reves: son dos magnitudes distintas.

## Valor que devuelven los accesores cuando el estado no trae el campo.
const UNAVAILABLE: float = -1.0
const UNAVAILABLE_TEXT: String = "n/d"

## Etiquetas breves. `Cond` = indice de condiciones.
const INDEX_SHORT: String = "Cond"
const INDEX_WORST_SHORT: String = "peor"
const INDEX_LONG: String = "Índice de condiciones"
const INDEX_WORST_LONG: String = "Peor índice registrado"

## Lo que se enseña en el detalle y en la ayuda. Es la frase que impide leer el
## indice como un pronostico medico.
const DISCLAIMER: String = \
	"Índice heurístico de condiciones (térmicas, visibilidad y dosis FED). " \
	+ "No es una probabilidad de supervivencia."
## FED se nombra siempre por lo que es.
const FED_CAPTION: String = "FED: dosis acumulada; no disminuye al ventilar."


## Indice combinado calculado AHORA, o `UNAVAILABLE` si el estado no lo trae.
## No se fabrica desde el peor historico ni desde la capa de 150 C.
static func current_index_pct(room_state: Dictionary) -> float:
	if not room_state.has("svv_pct"):
		return UNAVAILABLE
	return clampf(float(room_state["svv_pct"]), 0.0, 100.0)


## Peor indice registrado, o `UNAVAILABLE`. Es monotono no creciente por diseño:
## describe el peor momento de la partida, no el estado de ahora.
static func worst_index_pct(room_state: Dictionary) -> float:
	if not room_state.has("svv_worst_pct"):
		return UNAVAILABLE
	return clampf(float(room_state["svv_worst_pct"]), 0.0, 100.0)


## `78%`, o `n/d` cuando el campo falta.
static func format_pct(value: float) -> String:
	if value < 0.0:
		return UNAVAILABLE_TEXT
	return "%.0f%%" % value


## `Cond 78% (peor 40%)`, con `n/d` en el que falte. Es la linea corta de tarjeta.
static func compact_line(room_state: Dictionary) -> String:
	return "%s %s (%s %s)" % [
		INDEX_SHORT,
		format_pct(current_index_pct(room_state)),
		INDEX_WORST_SHORT,
		format_pct(worst_index_pct(room_state)),
	]


## Dos lineas para el panel de detalle, ya separadas y nombradas enteras.
static func detail_lines(room_state: Dictionary) -> Array[String]:
	return [
		"%s (ahora): %s" % [INDEX_LONG, format_pct(current_index_pct(room_state))],
		"%s: %s" % [INDEX_WORST_LONG, format_pct(worst_index_pct(room_state))],
	]
