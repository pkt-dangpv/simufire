class_name WindRose
extends RefCounted

## La rosa de los vientos, escrita una vez para el editor y el menu.
##
## El motor guarda la direccion en grados con la **convencion meteorologica**:
## el angulo de donde VIENE el viento, no hacia donde va (0 = norte, 90 = este).
## Es la fuente clasica de errores de signo, asi que la conversion vive aqui y
## las dos interfaces la usan; y por eso los mandos dicen "viene del", no
## "direccion".
##
## Ocho rumbos y no un angulo libre porque es como se lee un parte
## meteorologico, y porque la fisica del motor solo distingue cuatro caras de
## edificio: afinar a un grado seria precision fingida.

## Rumbos en el orden en que salen en el desplegable.
const POINTS: Array[Dictionary] = [
	{"nombre": "Norte", "corto": "N", "deg": 0.0},
	{"nombre": "Noreste", "corto": "NE", "deg": 45.0},
	{"nombre": "Este", "corto": "E", "deg": 90.0},
	{"nombre": "Sureste", "corto": "SE", "deg": 135.0},
	{"nombre": "Sur", "corto": "S", "deg": 180.0},
	{"nombre": "Suroeste", "corto": "SO", "deg": 225.0},
	{"nombre": "Oeste", "corto": "O", "deg": 270.0},
	{"nombre": "Noroeste", "corto": "NO", "deg": 315.0},
]

## Tope de velocidad, en m/s. Es el techo de la fuerza 10 de Beaufort (28,4 m/s
## = 102 km/h) y coincide casi exacto con la velocidad basica de viento que el
## CTE DB-SE-AE usa para dimensionar edificios en Espana (26-29 m/s segun zona).
## Por encima de ahi el viento deja de ser "lo mas fuerte que cabe esperar" y
## pasa a ser excepcional.
const MAX_SPEED_M_S: float = 28.0

## Paso del mando. Lo interesante de un incendio con viento pasa entre 5 y 15
## m/s -los ensayos de NIST y FDNY en Governors Island vieron mas de 400 C y
## 10 m/s en el pasillo de la planta de encima con solo 9-11 m/s impuestos-, asi
## que el paso tiene que dejar afinar ahi, no en el tope.
const SPEED_STEP_M_S: float = 0.5


## Indice del rumbo mas cercano a un angulo en grados.
static func index_for_degrees(deg: float) -> int:
	var normal: float = fposmod(deg, 360.0)
	var mejor: int = 0
	var mejor_dist: float = 1000.0
	for i in range(POINTS.size()):
		var d: float = absf(_angle_delta(normal, float(POINTS[i]["deg"])))
		if d < mejor_dist:
			mejor_dist = d
			mejor = i
	return mejor


## Grados del rumbo que ocupa esa posicion del desplegable.
static func degrees_for_index(index: int) -> float:
	if index < 0 or index >= POINTS.size():
		return 0.0
	return float(POINTS[index]["deg"])


## Nombre corto del rumbo de un angulo: "NO", "S"...
static func short_name(deg: float) -> String:
	return String(POINTS[index_for_degrees(deg)]["corto"])


## Como se dice una velocidad en un resumen: los m/s que manda el motor y los
## km/h, que es como la gente lee el viento.
static func speed_text(speed_m_s: float) -> String:
	if speed_m_s <= 0.05:
		return "sin viento"
	return "%.1f m/s (%.0f km/h)" % [speed_m_s, speed_m_s * 3.6]


## Viento entero, para la linea de resumen del menu.
static func summary_text(speed_m_s: float, direction_deg: float) -> String:
	if speed_m_s <= 0.05:
		return "sin viento"
	return "viento %s del %s" % [speed_text(speed_m_s), short_name(direction_deg)]


static func _angle_delta(a: float, b: float) -> float:
	var d: float = fposmod(a - b + 180.0, 360.0) - 180.0
	return d
