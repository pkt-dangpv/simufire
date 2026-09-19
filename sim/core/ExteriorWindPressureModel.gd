extends RefCounted

## Presion de viento sobre una abertura exterior: modelo puro y unico dueno.
##
## F2.2-R3 lo extrae de `GasExchangeSystem._compute_wind_dp_pa`, donde estaba
## como metodo privado. No cambia ni una constante: es exactamente la misma
## formula, movida para que la ruta historica y la red autoritativa compartan
## dueno en vez de tener cada una su copia. `GasExchangeSystem` delega aqui.
##
## Convenio de signo, el historico: positivo = barlovento, empuja HACIA DENTRO
## del edificio; negativo = sotavento, succiona. Quien lo consume decide que
## hacer con el; aqui no se resuelve ningun caudal.
##
## Coeficientes de presion simplificados de EN 1991-1-4 (Eurocode):
##   barlovento  cp = +0,6 * cos(incidencia)
##   sotavento   cp = +0,4 * cos(incidencia)   (cos < 0, luego cp < 0)
##
## Una abertura sin `wall_side` conocido no da a ninguna fachada y no recibe
## viento. Una abertura INTERIOR tampoco: el solver lo comprueba aparte.
##
## TODA la aritmetica va en `float` de GDScript, que son dobles, y el producto
## escalar se hace a mano. La primera version de este modelo usaba `Vector2` y
## `dot()`, y NO era bit a bit identica a la ruta historica: `Vector2` guarda sus
## componentes en `real_t`, que en las compilaciones estandar de Godot es de 32
## bits, de modo que el producto escalar redondeaba. La diferencia era de ~1e-6
## Pa —fisicamente nada— pero rompia la identidad exacta con la ruta OFF, que es
## un contrato de esta linea de trabajo. Medido: 80 de 160 combinaciones de
## fachada, direccion y velocidad diferian. Por eso aqui no se usa `Vector2`.

const AIR_DENSITY_REF_KG_M3: float = 1.2
const CP_WINDWARD: float = 0.6
const CP_LEEWARD: float = 0.4
## Por debajo de esto el viento no se calcula: es ruido.
const MIN_WIND_SPEED_M_S: float = 0.01


## Normal exterior de la fachada segun `wall_side`, en el mapa 2D con y hacia
## abajo, como `[nx, ny]` de dobles. Vacio si el lado no se conoce.
static func facade_normal(wall_side: String) -> Array:
	match wall_side:
		"top":
			return [0.0, -1.0]
		"bottom":
			return [0.0, 1.0]
		"left":
			return [-1.0, 0.0]
		"right":
			return [1.0, 0.0]
	return []


## Vector unitario que apunta HACIA el origen del viento, es decir de donde
## viene. Con la convencion del mapa: N = top, E = right, S = bottom, W = left.
static func from_wind_vector(direction_deg: float) -> Array:
	var dir_rad: float = deg_to_rad(direction_deg)
	return [sin(dir_rad), -cos(dir_rad)]


## Coeficiente de presion para un coseno de incidencia dado.
static func pressure_coefficient(cos_incidence: float) -> float:
	if cos_incidence >= 0.0:
		return CP_WINDWARD * cos_incidence
	return CP_LEEWARD * cos_incidence


## Presion de viento en Pa sobre una fachada.
##
## `speed_m_s` es la velocidad YA resuelta a la altura de la abertura: el perfil
## por altura lo aplica quien llama, porque depende del edificio.
static func wind_dp_pa(wall_side: String, direction_deg: float,
		speed_m_s: float) -> float:
	if not is_finite(speed_m_s) or speed_m_s <= MIN_WIND_SPEED_M_S:
		return 0.0
	var normal: Array = facade_normal(wall_side)
	if normal.is_empty():
		return 0.0
	var from_wind: Array = from_wind_vector(direction_deg)
	# Producto escalar a mano y en doble, no `Vector2.dot`: ver la nota de
	# cabecera sobre `real_t`.
	var cos_incidence: float = float(normal[0]) * float(from_wind[0]) \
			+ float(normal[1]) * float(from_wind[1])
	return 0.5 * AIR_DENSITY_REF_KG_M3 * speed_m_s * speed_m_s \
			* pressure_coefficient(cos_incidence)
