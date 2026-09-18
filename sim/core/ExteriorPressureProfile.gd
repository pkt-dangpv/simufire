extends RefCounted

## F2.2C-R1: perfil hidrostatico del exterior, en coordenadas ABSOLUTAS.
##
## Unico sitio donde vive la columna atmosferica. Lo usan el evaluador de
## compartimento (F2.2A), el solver de red (F2.2B), el adaptador de transporte
## (F2.2C) y los validadores. Copiar la formula en cada sistema es justo lo que
## produjo el defecto que esta fase corrige.
##
## El contorno exterior se declara con una presion absoluta EN UNA COTA:
##
##     outside = {pressure_abs_pa, reference_z_m, temp_k, reference_temp_k}
##
## y la presion a cualquier otra cota se obtiene con la columna de aire:
##
##     p_ext(z) = p_ext(z_ref) - rho_ext * g * (z - z_ref)
##
## `reference_z_m` ausente significa 0 m, que es lo que valia implicitamente en
## todos los casos historicos (una sola planta con el suelo en cero). Con esa
## convencion, un caso de una planta a cota cero da exactamente los mismos
## numeros que antes de esta fase.
##
## CONVENCION DECLARADA: densidad exterior CONSTANTE, evaluada a la temperatura
## del contorno. Es la aproximacion que ya usaba el motor y se mantiene aqui;
## para las alturas de un edificio (decenas de metros) el error frente a una
## atmosfera isoterma real es de milesimas de pascal. Si algun dia hace falta un
## perfil termico exterior, se cambia AQUI y en ningun otro sitio.

const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_TEMP_REF_K: float = 293.15
## Misma gravedad que el resto de la red.
const GRAVITY_M_S2: float = 9.80665


## Estado exterior normalizado, o {} si el contorno no es utilizable.
##
## Devuelve {valid, errors, pressure_abs_pa, reference_z_m, temp_k,
## reference_temp_k, density_kg_m3, gas_constant_j_kg_k}.
static func resolve(outside: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(outside) != TYPE_DICTIONARY:
		return _invalid(["outside must be a dictionary"])
	var state: Dictionary = outside

	var reference_temp_k: float = float(state.get("reference_temp_k", AIR_TEMP_REF_K))
	if not _is_finite(reference_temp_k) or reference_temp_k <= 0.0:
		errors.append("outside reference_temp_k must be finite and > 0")
	var temp_k: float = float(state.get("temp_k", reference_temp_k))
	if not _is_finite(temp_k) or temp_k <= 0.0:
		errors.append("outside temp_k must be finite and > 0")
	var pressure_abs_pa: float = float(state.get("pressure_abs_pa", AIR_PRESSURE_REF_PA))
	if not _is_finite(pressure_abs_pa) or pressure_abs_pa <= 0.0:
		errors.append("outside pressure_abs_pa must be finite and > 0")
	# Sin `reference_z_m` la cota de referencia es 0 m: es lo que valia antes de
	# que existiera el campo, y conserva los casos historicos.
	var reference_z_m: float = float(state.get("reference_z_m", 0.0))
	if not _is_finite(reference_z_m):
		errors.append("outside reference_z_m must be finite")
	if not errors.is_empty():
		return _invalid(errors)

	var gas_constant: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
	# La densidad del contorno sale de su propia presion y temperatura, no de un
	# 1,2 fijo: un exterior frio pesa mas y su columna es mayor.
	var density_kg_m3: float = float(state.get(
		"density_kg_m3", pressure_abs_pa / (gas_constant * temp_k)
	))
	if not _is_finite(density_kg_m3) or density_kg_m3 <= 0.0:
		return _invalid(["outside density_kg_m3 must be finite and > 0"])

	return {
		"valid": true,
		"errors": errors,
		"pressure_abs_pa": pressure_abs_pa,
		"reference_z_m": reference_z_m,
		"temp_k": temp_k,
		"reference_temp_k": reference_temp_k,
		"density_kg_m3": density_kg_m3,
		"gas_constant_j_kg_k": gas_constant,
	}


## Presion exterior ABSOLUTA a la cota `z_m`. `resolved` es lo que devuelve
## `resolve()`. Devuelve NAN si el contorno no era utilizable o si la columna
## llevaria la presion a cero o menos, que no es un estado fisico.
static func pressure_at(resolved: Dictionary, z_m: float) -> float:
	if not bool(resolved.get("valid", false)) or not _is_finite(z_m):
		return NAN
	var pressure_pa: float = float(resolved["pressure_abs_pa"]) \
			- float(resolved["density_kg_m3"]) * GRAVITY_M_S2 \
			* (z_m - float(resolved["reference_z_m"]))
	if not _is_finite(pressure_pa) or pressure_pa <= 0.0:
		return NAN
	return pressure_pa


## Masa que llenaria `volume_m3` a la presion exterior LOCAL del suelo del
## recinto y a la temperatura de referencia. Es el cero de la presion
## manometrica de ese recinto: con esta masa y sin energia sensible, su gauge
## es exactamente 0.
static func reference_mass_kg(
	resolved: Dictionary,
	floor_z_m: float,
	volume_m3: float
) -> float:
	var local_pressure_pa: float = pressure_at(resolved, floor_z_m)
	if is_nan(local_pressure_pa) or not _is_finite(volume_m3) or volume_m3 <= 0.0:
		return NAN
	return local_pressure_pa * volume_m3 \
			/ (float(resolved["gas_constant_j_kg_k"]) * float(resolved["reference_temp_k"]))


static func _invalid(errors: Array) -> Dictionary:
	var typed: Array[String] = []
	for entry in errors:
		typed.append(String(entry))
	return {
		"valid": false,
		"errors": typed,
		"pressure_abs_pa": NAN,
		"reference_z_m": NAN,
		"temp_k": NAN,
		"reference_temp_k": NAN,
		"density_kg_m3": NAN,
		"gas_constant_j_kg_k": NAN,
	}


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
