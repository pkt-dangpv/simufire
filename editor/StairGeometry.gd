extends RefCounted
## La geometria de las escaleras del editor, sin editor.
##
## Todo aqui son funciones estaticas y puras: entran un rectangulo, una direccion
## y un modo de giro, y sale un numero. No tocan `editor_data`, ni la escena, ni
## la seleccion, asi que se pueden probar una a una con una tabla de entradas.
##
## Segundo modulo de E-12 (docs/AUDITORIA_EDITOR_2026-09-06.md). Las escaleras
## eran 428 lineas repartidas por el fichero del editor, y mas de la mitad no
## necesitaban nada de el.
##
## El vocabulario -auto, recta, 180- vive aqui porque aqui es donde significa
## algo: `MODE_AUTO` decide segun quepa o no el descansillo.

const Serializer = preload("res://editor/ScenarioSerializer.gd")

## Auto no es "sin decidir": es "180 si cabe, recta si no". Es lo que hace el
## editor cuando el usuario no elige.
const MODE_AUTO: String = "auto"
const MODE_STRAIGHT: String = "straight"
const MODE_SWITCHBACK: String = "switchback"

## Por debajo de esto no cabe el descansillo de un giro de 180: dos tramos de
## 0,82 m mas el hueco entre ellos.
const MIN_CROSS_FOR_180_M: float = 1.75
const MIN_LONG_FOR_180_M: float = 2.40


## Una escalera solo corre por un eje: al arrastrar en diagonal manda el eje
## dominante.
static func axis_aligned_direction(dir: Vector2) -> Vector2:
	if absf(dir.x) > absf(dir.y):
		return Vector2.RIGHT if dir.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y >= 0.0 else Vector2.UP


static func direction_from_rotation(rotation_deg: float) -> Vector2:
	var angle: float = deg_to_rad(rotation_deg + 90.0)
	return axis_aligned_direction(Vector2(cos(angle), sin(angle)))


## Hacia donde sube, mirando el arrastre. Si el arrastre no se movio, manda la
## forma del rectangulo: una caja alta sube hacia abajo en pantalla.
static func run_direction_from_drag(start_m: Vector2, end_m: Vector2, rect: Rect2) -> Vector2:
	var delta: Vector2 = end_m - start_m
	if absf(delta.x) > absf(delta.y):
		return Vector2.RIGHT if delta.x >= 0.0 else Vector2.LEFT
	if absf(delta.y) > 0.001:
		return Vector2.DOWN if delta.y >= 0.0 else Vector2.UP
	return Vector2.DOWN if rect.size.y >= rect.size.x else Vector2.RIGHT


static func run_direction_for_room(room: Dictionary) -> Vector2:
	if room.has("stair_run_direction_m"):
		return axis_aligned_direction(Serializer.vector2_from_data(room.get("stair_run_direction_m", Vector2.DOWN)))
	return axis_aligned_direction(Vector2.DOWN)


static func long_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.x if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.y


static func cross_span_m(rect: Rect2, stair_dir: Vector2) -> float:
	return rect.size.y if absf(stair_dir.x) > absf(stair_dir.y) else rect.size.x


static func can_use_180_landing(rect: Rect2, stair_dir: Vector2) -> bool:
	return cross_span_m(rect, stair_dir) >= MIN_CROSS_FOR_180_M and long_span_m(rect, stair_dir) >= MIN_LONG_FOR_180_M


static func normalized_turn_mode(mode: String) -> String:
	match mode.strip_edges().to_lower():
		MODE_STRAIGHT:
			return MODE_STRAIGHT
		MODE_SWITCHBACK:
			return MODE_SWITCHBACK
		_:
			return MODE_AUTO


## Recta son 0°; 180 son 180° solo si el descansillo cabe. Pedir 180 donde no
## cabe da una escalera recta, no una escalera imposible.
static func turn_degrees_for_mode(rect: Rect2, stair_dir: Vector2, mode: String) -> float:
	match normalized_turn_mode(mode):
		MODE_STRAIGHT:
			return 0.0
		MODE_SWITCHBACK:
			return 180.0 if can_use_180_landing(rect, stair_dir) else 0.0
		_:
			return 180.0 if can_use_180_landing(rect, stair_dir) else 0.0


static func turn_mode_from_degrees(turn_degrees: float) -> String:
	return MODE_SWITCHBACK if turn_degrees >= 179.0 else MODE_AUTO


static func turn_mode_label(mode: String) -> String:
	match normalized_turn_mode(mode):
		MODE_STRAIGHT:
			return "recta"
		MODE_SWITCHBACK:
			return "180°"
		_:
			return "auto"


## Las salas viejas no guardan el modo, solo los grados: se deduce.
static func turn_mode_for_room(room: Dictionary) -> String:
	if room.has("stair_turn_mode"):
		return normalized_turn_mode(String(room.get("stair_turn_mode", MODE_AUTO)))
	return turn_mode_from_degrees(float(room.get("stair_turn_degrees", 0.0)))


static func ramp_width_m(rect: Rect2, stair_dir: Vector2) -> float:
	var cross: float = cross_span_m(rect, stair_dir)
	return minf(maxf(0.82, cross * 0.50), maxf(0.82, cross - 0.96))


static func landing_depth_m(rect: Rect2, stair_dir: Vector2) -> float:
	return clampf(long_span_m(rect, stair_dir) * 0.22, 0.72, 1.05)


## Lo que queda para peldaños despues de quitarle el descansillo y los remates.
static func effective_run_m(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> float:
	var long_m: float = long_span_m(rect, stair_dir)
	if turn_degrees >= 179.0:
		return maxf(0.60, long_m - landing_depth_m(rect, stair_dir) - 0.30)
	return maxf(0.60, long_m - landing_depth_m(rect, stair_dir) - 0.22)


## La pendiente que se enseña en el panel. Con giro de 180 cada tramo sube la
## mitad, asi que la pendiente se calcula sobre media altura.
static func slope_angle_deg(rect: Rect2, stair_dir: Vector2, turn_degrees: float, rise_m: float) -> float:
	var run_m: float = maxf(0.30, effective_run_m(rect, stair_dir, turn_degrees))
	if turn_degrees >= 179.0:
		return rad_to_deg(atan2(rise_m * 0.5, run_m))
	return rad_to_deg(atan2(rise_m, run_m))


static func direction_label(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "este" if dir.x > 0.0 else "oeste"
	return "sur" if dir.y > 0.0 else "norte"


## Una sala es escalera por su tipo o porque se llama asi: los escenarios de
## antes de que existiera el tipo siguen cargando.
static func is_stair_room(room: Dictionary) -> bool:
	var kind_name: String = String(room.get("kind", "")).strip_edges().to_lower()
	var name_text: String = String(room.get("name", "")).strip_edges().to_lower()
	return kind_name in ["escalera", "stair", "stairs", "stairwell"] or name_text.contains("escalera") or name_text.contains("stair")


## El hueco que la escalera abre en el forjado de arriba. Con giro de 180 es el
## ancho de los dos tramos mas su separacion; recta, solo la rampa.
static func vertical_void_rect(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> Rect2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	if turn_degrees >= 179.0:
		var gap_m: float = 0.18
		var cross_m: float = cross_span_m(rect, stair_dir)
		var flight_width_m: float = clampf((cross_m - gap_m) * 0.5, 0.72, 1.05)
		var shaft_width_m: float = minf(cross_m, flight_width_m * 2.0 + gap_m + 0.18)
		if absf(stair_dir.x) > absf(stair_dir.y):
			return Rect2(
				Vector2(rect.position.x, rect.get_center().y - shaft_width_m * 0.5),
				Vector2(rect.size.x, shaft_width_m)
			)
		return Rect2(
			Vector2(rect.get_center().x - shaft_width_m * 0.5, rect.position.y),
			Vector2(shaft_width_m, rect.size.y)
		)
	var width_m: float = minf(ramp_width_m(rect, stair_dir), maxf(0.2, cross_span_m(rect, stair_dir) - 0.2))
	var run_m: float = minf(
		maxf(0.80, long_span_m(rect, stair_dir) - landing_depth_m(rect, stair_dir) - 0.22),
		maxf(0.2, long_span_m(rect, stair_dir) - 0.2)
	)
	var start_margin_m: float = 0.22
	if absf(stair_dir.x) > absf(stair_dir.y):
		var x_m: float = rect.position.x + start_margin_m if stair_dir.x > 0.0 else rect.position.x + rect.size.x - start_margin_m - run_m
		return Rect2(
			Vector2(x_m, rect.get_center().y - width_m * 0.5),
			Vector2(run_m, width_m)
		)
	var y_m: float = rect.position.y + start_margin_m if stair_dir.y > 0.0 else rect.position.y + rect.size.y - start_margin_m - run_m
	return Rect2(
		Vector2(rect.get_center().x - width_m * 0.5, y_m),
		Vector2(width_m, run_m)
	)
