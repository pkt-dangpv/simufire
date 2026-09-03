class_name OpeningPlacement
extends RefCounted

## Donde cae un hueco a lo largo del paramento que lo aloja.
##
## Esta aritmetica estaba escrita dos veces —en `_opening_info_on_side()` del
## mundo de primera persona y en `_center_axis()` de `OpeningPose3D`— y era
## caracter por caracter la misma regla: el desplazamiento se interpreta como
## fraccion del tramo util o como distancia desde el arranque del lado, el ancho
## se recorta si el tramo no da para tanto, y el centro se mete a la fuerza
## dentro del tramo para que el hueco no sobresalga por ninguna jamba.
##
## Que coincidieran era suerte: nada obligaba a que un retoque en una llegara a
## la otra, y el sintoma habria sido un hueco dibujado en un sitio en el visor y
## en otro al recorrerlo a pie (FP-3).

## Ancho minimo (m) que se le reconoce a un hueco al recortarlo contra el tramo
## disponible. Sin este suelo, un tramo estrecho colapsaria el hueco a cero y el
## centro dejaria de estar definido.
const MIN_OPENING_WIDTH_M: float = 0.20


## Centro y ancho efectivo de un hueco sobre su lado.
##
## - `allowed_start` / `allowed_end`: tramo util del lado, ya recortado al
##   solape con la sala vecina si es una medianera.
## - `side_start`: arranque del lado completo, que es el origen desde el que se
##   mide un desplazamiento absoluto (no desde el tramo util).
## - `offset` / `offset_is_fraction`: el desplazamiento tal cual viene del
##   modelo de hueco.
##
## Devuelve `{ "center": float, "width_m": float }`.
static func center_along_side(
	allowed_start: float,
	allowed_end: float,
	side_start: float,
	offset: float,
	offset_is_fraction: bool,
	width_m: float
) -> Dictionary:
	var allowed_length_m: float = maxf(0.0, allowed_end - allowed_start)
	var safe_width_m: float = minf(width_m, maxf(MIN_OPENING_WIDTH_M, allowed_length_m))
	var center: float = allowed_start + allowed_length_m * offset if offset_is_fraction else side_start + offset
	return {
		"center": clampf(center, allowed_start + safe_width_m * 0.5, allowed_end - safe_width_m * 0.5),
		"width_m": safe_width_m,
	}
