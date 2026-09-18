extends RefCounted

## F2.2C-R1: hueco HORIZONTAL entre plantas (hueco de escalera, patinillo).
##
## `OpeningModel.is_vertical` describe un hueco de suelo/techo: las dos salas no
## comparten un pano vertical, comparten el PLANO de la losa. Modelarlo como un
## vano de Bernoulli anclado al suelo de una de ellas es lo que hacia que el
## perfil del recinto de arriba se evaluara metros por debajo de su propia losa
## y que su zona inferior, vacia, tuviera que donar todo el caudal.
##
## Aqui el intercambio ocurre en una sola cota, la de la losa, y tiene dos
## terminos que son fisicamente distintos y se calculan por separado:
##
## 1. NETO POR PRESION. Si las dos salas no estan a la misma presion en la losa,
##    pasa gas de la de mas a la de menos, por orificio:
##
##        m_p = Cd * A * sqrt(2 * rho_origen * |dp|)
##
##    Es lo que acopla las dos presiones en el residuo de Newton.
##
## 2. INTERCAMBIO POR FLOTABILIDAD. Si el gas que toca la losa por ABAJO es mas
##    ligero que el que la toca por ARRIBA, la configuracion es inestable y
##    aparece un intercambio a dos sentidos aunque la presion este igualada:
##
##        m_b = Cd * A * sqrt(2 * g * sqrt(A) * |d_rho| * rho_media)
##
##    La raiz del area es la escala de longitud del hueco, que es lo que
##    distingue este intercambio del de un vano vertical: no hay altura de vano,
##    hay un agujero. Sube esa masa y baja esa masa; no es caudal neto.
##
## El signo de 2 lo decide la densidad, no la temperatura: es la flotabilidad la
## que manda, y con gases de distinta composicion la temperatura sola mentiria.
## Si el gas de abajo es MAS PESADO que el de arriba, la estratificacion es
## estable y el intercambio es cero.
##
## Modelo PURO: sin estado, sin nodos, sin salas. Recibe densidades y presiones
## ya evaluadas en la losa y devuelve caudales.

const GRAVITY_M_S2: float = 9.80665
## Diferencia de densidad por debajo de la cual no se considera que haya
## inestabilidad: evita un intercambio de ruido numerico entre dos salas que
## estan, a efectos practicos, a la misma densidad.
const DENSITY_EPS_KG_M3: float = 1.0e-9


## Caudales por un hueco horizontal.
##
## `dp_pa` es la presion de la sala de ABAJO menos la de ARRIBA, evaluadas las
## dos en la cota de la losa. Positiva significa que abajo empuja hacia arriba.
##
## `rho_below` y `rho_above` son las densidades del gas que toca la losa por
## cada lado, ya elegidas por el llamante segun la zona que corresponda.
##
## Devuelve {valid, errors, pressure_mass_kg_s, exchange_mass_up_kg_s,
## exchange_mass_down_kg_s, up_mass_kg_s, down_mass_kg_s, net_up_mass_kg_s,
## unstable, length_scale_m}.
##
## `up` siempre significa de la sala de abajo a la de arriba.
static func compute_flows(
	area_m2: float,
	discharge_coeff: float,
	dp_pa: float,
	rho_below_kg_m3: float,
	rho_above_kg_m3: float,
	dp_regularization_pa: float = 0.0
) -> Dictionary:
	var errors: Array[String] = []
	if not _is_finite(area_m2) or area_m2 < 0.0:
		errors.append("area_m2 must be finite and >= 0")
	if not _is_finite(discharge_coeff) or discharge_coeff <= 0.0:
		errors.append("discharge_coeff must be finite and > 0")
	if not _is_finite(dp_pa):
		errors.append("dp_pa must be finite")
	if not _is_finite(rho_below_kg_m3) or rho_below_kg_m3 <= 0.0:
		errors.append("rho_below_kg_m3 must be finite and > 0")
	if not _is_finite(rho_above_kg_m3) or rho_above_kg_m3 <= 0.0:
		errors.append("rho_above_kg_m3 must be finite and > 0")
	if not errors.is_empty():
		return _invalid(errors)

	var result: Dictionary = {
		"valid": true,
		"errors": errors,
		"pressure_mass_kg_s": 0.0,
		"exchange_mass_up_kg_s": 0.0,
		"exchange_mass_down_kg_s": 0.0,
		"up_mass_kg_s": 0.0,
		"down_mass_kg_s": 0.0,
		"net_up_mass_kg_s": 0.0,
		"unstable": false,
		"regularized": false,
		"length_scale_m": 0.0,
	}
	if area_m2 <= 0.0:
		return result

	var length_scale_m: float = sqrt(area_m2)
	result["length_scale_m"] = length_scale_m

	# 1. Neto por presion, con la densidad del lado que empuja.
	var pressure_mass_kg_s: float = 0.0
	if dp_pa != 0.0:
		var rho_source: float = rho_below_kg_m3 if dp_pa > 0.0 else rho_above_kg_m3
		# La derivada del orificio, d(m)/d(dp) = m/(2 dp), no esta acotada en el
		# origen, y dos huecos en serie hacen que Newton oscile justo ahi. Se usa
		# la MISMA linealizacion por debajo del umbral que el vano de Bernoulli
		# ya usaba en el solver: constante global de condicionamiento, nunca un
		# ajuste por caso.
		var magnitude_pa: float = absf(dp_pa)
		var factor: float = 0.0
		if dp_regularization_pa > 0.0 and magnitude_pa < dp_regularization_pa:
			factor = sqrt(2.0 * rho_source * dp_regularization_pa) \
					* (magnitude_pa / dp_regularization_pa)
			result["regularized"] = true
		else:
			factor = sqrt(2.0 * rho_source * magnitude_pa)
		var magnitude: float = discharge_coeff * area_m2 * factor
		pressure_mass_kg_s = magnitude if dp_pa > 0.0 else -magnitude
	result["pressure_mass_kg_s"] = pressure_mass_kg_s

	# 2. Intercambio por flotabilidad, solo si lo de abajo es mas ligero.
	var density_difference: float = rho_above_kg_m3 - rho_below_kg_m3
	if density_difference > DENSITY_EPS_KG_M3:
		var mean_density: float = 0.5 * (rho_above_kg_m3 + rho_below_kg_m3)
		var exchange_kg_s: float = discharge_coeff * area_m2 * sqrt(
			2.0 * GRAVITY_M_S2 * length_scale_m * density_difference * mean_density
		)
		result["unstable"] = true
		# El intercambio mueve el MISMO caudal masico en los dos sentidos: es un
		# trueque, no un caudal neto. Lo neto lo pone el termino de presion.
		result["exchange_mass_up_kg_s"] = exchange_kg_s
		result["exchange_mass_down_kg_s"] = exchange_kg_s

	var up_kg_s: float = float(result["exchange_mass_up_kg_s"])
	var down_kg_s: float = float(result["exchange_mass_down_kg_s"])
	if pressure_mass_kg_s > 0.0:
		up_kg_s += pressure_mass_kg_s
	else:
		down_kg_s += -pressure_mass_kg_s
	result["up_mass_kg_s"] = up_kg_s
	result["down_mass_kg_s"] = down_kg_s
	result["net_up_mass_kg_s"] = up_kg_s - down_kg_s
	return result


static func _invalid(errors: Array[String]) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"pressure_mass_kg_s": 0.0,
		"exchange_mass_up_kg_s": 0.0,
		"exchange_mass_down_kg_s": 0.0,
		"up_mass_kg_s": 0.0,
		"down_mass_kg_s": 0.0,
		"net_up_mass_kg_s": 0.0,
		"unstable": false,
		"regularized": false,
		"length_scale_m": 0.0,
	}


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
