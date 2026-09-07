extends RefCounted
## Las reglas de escalera del editor de planos: el vocabulario de giros y lo que
## se deduce de un arrastre o de una sala.
##
## Todo son funciones estaticas y puras: entran un rectangulo, una direccion y un
## modo, y sale un numero o una palabra. No tocan `editor_data`, ni la escena, ni
## la seleccion, asi que se prueban con una tabla de entradas
## (tools/probe_stair_geometry.gd).
##
## **Las medidas del tramo no estan aqui**: largo, ancho, rampa, descansillo y
## hueco vertical viven en `view/geometry/StairGeometry.gd`, que es el modulo que
## comparten el mundo FP y el visor 3D. El editor tenia una copia literal de esas
## cinco funciones; si alguien hubiera tocado el modulo -que es lo que manda la
## regla de la linea visual-, el plano del editor habria dibujado una escalera y
## el 3D habria construido otra sin que nadie se enterara.
##
## Aqui solo queda lo que es del editor: `MODE_AUTO` no es "sin decidir", es
## "180 si cabe, recta si no", y eso es una decision de la herramienta de dibujo.

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


static func can_use_180_landing(rect: Rect2, stair_dir: Vector2) -> bool:
	return StairGeometry.cross_span_m(rect, stair_dir) >= MIN_CROSS_FOR_180_M and StairGeometry.long_span_m(rect, stair_dir) >= MIN_LONG_FOR_180_M


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


static func effective_run_m(rect: Rect2, stair_dir: Vector2, turn_degrees: float) -> float:
	var long_m: float = StairGeometry.long_span_m(rect, stair_dir)
	if turn_degrees >= 179.0:
		return maxf(0.60, long_m - StairGeometry.top_landing_depth_m(rect, stair_dir) - 0.30)
	return maxf(0.60, long_m - StairGeometry.top_landing_depth_m(rect, stair_dir) - 0.22)


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
