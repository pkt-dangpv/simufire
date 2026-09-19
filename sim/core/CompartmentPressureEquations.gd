extends RefCounted

## Ecuaciones locales de presion, masa y energia de un recinto: modelo puro
## (fase F2.2A de docs/PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md).
##
## NO ES UN SOLVER. Recibe un estado candidato y los flujos candidatos por
## aberturas y responde si ese candidato satisface la conservacion de masa y
## energia y la ecuacion de estado del recinto. No calcula caudales, no itera,
## no declara convergencia, no elige la presion final, no muta sus entradas, no
## toca RoomModel ni el motor, no usa nodos, escena, editor, singletons,
## archivos ni aleatoriedad. El punto fijo es de F2.2B.
##
## Estado canonico (decidido en §13.1 del documento de diseno): los estados
## conservados de un recinto son la masa y la energia sensible de cada zona
## (`upper_gas_kg`, `lower_gas_kg`, `upper_energy_kj`, `lower_energy_kj`). La
## presion, las temperaturas, los volumenes de zona, la interfaz y las
## densidades son DERIVADAS. Nunca se reconstruye masa desde la ecuacion de
## estado: la EOS es cierre y residuo diagnostico.
##
## Ecuaciones (todas en kelvin):
##   T_z     = T_ref + E_z / (m_z * c_p)                         [K]
##   p_abs   = (R / V) * (M * T_ref + E / c_p)                   [Pa]
##   p_gauge = (R / V) * ((M - M_ref) * T_ref + E / c_p)         [Pa]
##   M_ref   = p_ext_abs * V / (R * T_ref)                       [kg]
##   R       = P_ref / (rho_ref * T_ref)                         [J/(kg K)]
##   V_z     = m_z * R * T_z / p_abs                             [m3]
##   interfaz = V_inferior / area_suelo                          [m]
##   p(z)    = p_suelo - g * suma(rho_zona * tramo)              [Pa]
##
## Residuos del paso, con dt_s en segundos:
##   masa_z    = (m_z_cand - m_z_prev) - dt * (fuente_z + flujos_z)   [kg]
##   energia_z = (E_z_cand - E_z_prev) - dt * (fuente_z + flujos_z)   [kJ]
##   presion   = p_gauge_candidata - p_gauge(EOS del inventario)      [Pa]
##
## Unidades: masa kg, caudal masico kg/s, entalpia transportada kW, energia
## acumulada kJ, presion Pa, temperatura K, longitud m, area m2, volumen m3.
##
## Convencion de signo, unica para fuentes y flujos: **positivo = entra en el
## recinto** (y en la zona indicada); negativo = sale. La presion manometrica
## puede ser positiva, cero o NEGATIVA: no hay ningun recorte de signo. La cota
## de referencia de la presion es el SUELO del recinto (`floor_z_m`).
##
## La entalpia de cada abertura la calcula F2.2B; aqui solo se suma. Para que el
## resultado no dependa del orden de entrada, los flujos se ordenan por
## (opening_id, segment_id, zone) antes de sumarse, y se rechazan repetidos.

const ZONE_UPPER: String = "upper"
const ZONE_LOWER: String = "lower"
const ZONES: Array[String] = [ZONE_UPPER, ZONE_LOWER]

## Constantes canonicas del motor (identicas a Phase3ZoneMassSystem y
## Phase3CoupledPressureSolver, para que el estado sea el mismo).
const AIR_PRESSURE_REF_PA: float = 101325.0
const AIR_DENSITY_REF_KG_M3: float = 1.2
const AIR_CP_KJ_KG_K: float = 1.0
const GRAVITY_M_S2: float = 9.81

## Una zona con menos masa que esto se trata como degenerada: no tiene
## temperatura ni densidad propias y se extiende la de la otra zona.
const MASS_EPS_KG: float = 1.0e-12
const VOLUME_EPS_M3: float = 1.0e-12
## Tolerancia relativa del cierre de volumen (V_sup + V_inf = V). Solo
## diagnostico: la EOS afin lo cumple de forma exacta salvo redondeo.
const VOLUME_CLOSURE_TOLERANCE: float = 1.0e-9

const GEOMETRY_KEYS: Array[String] = ["floor_z_m", "height_m", "floor_area_m2"]
const INVENTORY_KEYS: Array[String] = [
	"upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
]
const SOURCE_KEYS: Array[String] = [
	"upper_mass_kg_s", "lower_mass_kg_s", "upper_enthalpy_kw", "lower_enthalpy_kw",
]


## Residuos de un recinto para un estado candidato. Devuelve {valid, errors,
## pressure_residual_pa, pressure_residual_normalized, mass_residual_kg,
## energy_residual_kj, mass_residual_by_zone_kg, energy_residual_by_zone_kj,
## pressure_profile, diagnostics}.
static func evaluate_compartment_residual(
	previous_state: Variant,
	candidate_state: Variant,
	sources: Variant,
	opening_fluxes: Variant,
	outside: Variant,
	dt_s: Variant
) -> Dictionary:
	var errors: Array[String] = []

	var dt: float = _number(dt_s)
	if not _is_finite(dt) or dt <= 0.0:
		errors.append("dt_s must be finite and > 0")

	var outside_state: Dictionary = _validated_outside(outside, errors)
	var previous: Dictionary = _validated_state(previous_state, "previous_state", false, errors)
	var candidate: Dictionary = _validated_state(candidate_state, "candidate_state", true, errors)
	var source_terms: Dictionary = _validated_sources(sources, errors)
	var fluxes: Array = _validated_fluxes(opening_fluxes, errors)
	if not errors.is_empty():
		return _invalid_result(errors)

	if String(previous["room_id"]) != String(candidate["room_id"]):
		errors.append("previous_state and candidate_state must describe the same room")
	for key in GEOMETRY_KEYS:
		if float(previous[key]) != float(candidate[key]):
			errors.append("geometry '%s' cannot change within a step" % key)
	if not errors.is_empty():
		return _invalid_result(errors)

	var reference_temp_k: float = float(outside_state["reference_temp_k"])
	var gas_constant: float = AIR_PRESSURE_REF_PA / (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
	var volume_m3: float = float(candidate["floor_area_m2"]) * float(candidate["height_m"])

	var thermo: Dictionary = _thermodynamic_state(candidate, outside_state, gas_constant, volume_m3, errors)
	if not errors.is_empty():
		return _invalid_result(errors)

	var candidate_gauge_pa: float = float(candidate["gauge_pressure_pa"])
	if float(outside_state["pressure_abs_pa"]) + candidate_gauge_pa <= 0.0:
		errors.append("candidate gauge pressure implies a non-positive absolute pressure")
	if not errors.is_empty():
		return _invalid_result(errors)

	# Balances por zona. Positivo = entra en el recinto.
	var flux_mass: Dictionary = {ZONE_UPPER: 0.0, ZONE_LOWER: 0.0}
	var flux_enthalpy: Dictionary = {ZONE_UPPER: 0.0, ZONE_LOWER: 0.0}
	for flux in fluxes:
		var zone: String = String(flux["zone"])
		flux_mass[zone] = float(flux_mass[zone]) + float(flux["mass_flow_kg_s"])
		flux_enthalpy[zone] = float(flux_enthalpy[zone]) + float(flux["enthalpy_flow_kw"])

	var mass_residual_by_zone: Dictionary = {}
	var energy_residual_by_zone: Dictionary = {}
	var mass_residual_kg: float = 0.0
	var energy_residual_kj: float = 0.0
	for zone in ZONES:
		var mass_key: String = "%s_gas_kg" % zone
		var energy_key: String = "%s_energy_kj" % zone
		var mass_in_kg_s: float = float(source_terms["%s_mass_kg_s" % zone]) + float(flux_mass[zone])
		var enthalpy_in_kw: float = float(source_terms["%s_enthalpy_kw" % zone]) + float(flux_enthalpy[zone])
		var mass_residual: float = (float(candidate[mass_key]) - float(previous[mass_key])) - dt * mass_in_kg_s
		var energy_residual: float = (float(candidate[energy_key]) - float(previous[energy_key])) - dt * enthalpy_in_kw
		mass_residual_by_zone[zone] = mass_residual
		energy_residual_by_zone[zone] = energy_residual
		mass_residual_kg += mass_residual
		energy_residual_kj += energy_residual

	var pressure_residual_pa: float = candidate_gauge_pa - float(thermo["gauge_pressure_pa"])
	var pressure_scale_pa: float = maxf(1.0, absf(float(thermo["gauge_pressure_pa"])))

	return {
		"valid": true,
		"errors": errors,
		"room_id": String(candidate["room_id"]),
		"pressure_residual_pa": pressure_residual_pa,
		"pressure_residual_normalized": pressure_residual_pa / pressure_scale_pa,
		"mass_residual_kg": mass_residual_kg,
		"energy_residual_kj": energy_residual_kj,
		"mass_residual_by_zone_kg": mass_residual_by_zone,
		"energy_residual_by_zone_kj": energy_residual_by_zone,
		"pressure_profile": _pressure_profile(candidate, thermo, candidate_gauge_pa),
		"diagnostics": _diagnostics(candidate, previous, thermo, source_terms, flux_mass,
				flux_enthalpy, fluxes, outside_state, gas_constant, dt),
	}


## F2.2-R2-MASS: geometria de las dos capas A PARTIR DEL ESTADO, sin tocarlo.
##
## El volumen especifico de un gas depende de su masa, su temperatura y su
## presion ABSOLUTA, y esa presion sale de la propia ecuacion de estado del
## recinto:
##
##     p_abs = (R / V) * (M * T_ref + E / cp)
##     V_zona = m_zona * R * T_zona / p_abs
##
## Con esa presion los dos volumenes suman EXACTAMENTE el del recinto, porque
## m_u*T_u + m_l*T_l = M*T_ref + E/cp es una identidad. No hay nada que cuadrar
## y, por tanto, ninguna masa que anadir ni que borrar.
##
## Imponer en su lugar la densidad a presion ambiente es lo que obligaba a
## reescribir la masa inferior, y era la causa de que un recinto sellado
## perdiera un tercio de su gas al calentarse.
##
## Devuelve {valid, pressure_abs_pa, upper_volume_m3, lower_volume_m3,
## interface_m, upper_temp_k, lower_temp_k, upper_density_kg_m3,
## lower_density_kg_m3}. `valid` falso significa que el estado no define una
## geometria: el llamante conserva la que tenia en vez de inventarse una.
static func zone_geometry_from_state(
	upper_gas_kg: float,
	lower_gas_kg: float,
	upper_energy_kj: float,
	lower_energy_kj: float,
	floor_area_m2: float,
	height_m: float,
	reference_temp_k: float
) -> Dictionary:
	var invalid: Dictionary = {"valid": false}
	for value in [upper_gas_kg, lower_gas_kg, upper_energy_kj, lower_energy_kj,
			floor_area_m2, height_m, reference_temp_k]:
		if not _is_finite(value):
			return invalid
	if floor_area_m2 <= 0.0 or height_m <= 0.0 or reference_temp_k <= 0.0:
		return invalid
	if upper_gas_kg < 0.0 or lower_gas_kg < 0.0:
		return invalid

	var volume_m3: float = floor_area_m2 * height_m
	var total_mass_kg: float = upper_gas_kg + lower_gas_kg
	if total_mass_kg <= MASS_EPS_KG:
		return invalid
	var gas_constant: float = AIR_PRESSURE_REF_PA \
			/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)

	var upper_temp_k: float = reference_temp_k
	if upper_gas_kg > MASS_EPS_KG:
		upper_temp_k += upper_energy_kj / (upper_gas_kg * AIR_CP_KJ_KG_K)
	var lower_temp_k: float = reference_temp_k
	if lower_gas_kg > MASS_EPS_KG:
		lower_temp_k += lower_energy_kj / (lower_gas_kg * AIR_CP_KJ_KG_K)
	if upper_temp_k <= 0.0 or lower_temp_k <= 0.0:
		return invalid

	var pressure_abs_pa: float = gas_constant * (
		total_mass_kg * reference_temp_k
		+ (upper_energy_kj + lower_energy_kj) / AIR_CP_KJ_KG_K
	) / volume_m3
	if not _is_finite(pressure_abs_pa) or pressure_abs_pa <= 0.0:
		return invalid

	var upper_volume_m3: float = upper_gas_kg * gas_constant * upper_temp_k / pressure_abs_pa
	var lower_volume_m3: float = lower_gas_kg * gas_constant * lower_temp_k / pressure_abs_pa
	if not _is_finite(upper_volume_m3) or not _is_finite(lower_volume_m3):
		return invalid

	# Una zona degenerada no tiene densidad propia: se extiende la de la otra,
	# sin inventar masa, igual que hace el evaluador de residuos.
	var upper_density_kg_m3: float = 0.0
	if upper_gas_kg > MASS_EPS_KG and upper_volume_m3 > 0.0:
		upper_density_kg_m3 = upper_gas_kg / upper_volume_m3
	var lower_density_kg_m3: float = 0.0
	if lower_gas_kg > MASS_EPS_KG and lower_volume_m3 > 0.0:
		lower_density_kg_m3 = lower_gas_kg / lower_volume_m3
	if upper_density_kg_m3 <= 0.0:
		upper_density_kg_m3 = lower_density_kg_m3
	if lower_density_kg_m3 <= 0.0:
		lower_density_kg_m3 = upper_density_kg_m3
	if upper_density_kg_m3 <= 0.0 or lower_density_kg_m3 <= 0.0:
		return invalid

	return {
		"valid": true,
		"pressure_abs_pa": pressure_abs_pa,
		"upper_volume_m3": upper_volume_m3,
		"lower_volume_m3": lower_volume_m3,
		"interface_m": clampf(lower_volume_m3 / floor_area_m2, 0.0, height_m),
		"upper_temp_k": upper_temp_k,
		"lower_temp_k": lower_temp_k,
		"upper_density_kg_m3": upper_density_kg_m3,
		"lower_density_kg_m3": lower_density_kg_m3,
	}


## Estado termodinamico derivado del inventario candidato. La EOS es cierre:
## no devuelve masa ni energia nuevas.
static func _thermodynamic_state(state: Dictionary, outside_state: Dictionary,
		gas_constant: float, volume_m3: float, errors: Array[String]) -> Dictionary:
	var reference_temp_k: float = float(outside_state["reference_temp_k"])
	var upper_mass_kg: float = float(state["upper_gas_kg"])
	var lower_mass_kg: float = float(state["lower_gas_kg"])
	var upper_energy_kj: float = float(state["upper_energy_kj"])
	var lower_energy_kj: float = float(state["lower_energy_kj"])
	var total_mass_kg: float = upper_mass_kg + lower_mass_kg
	var total_energy_kj: float = upper_energy_kj + lower_energy_kj
	if total_mass_kg <= MASS_EPS_KG:
		errors.append("candidate_state has no gas mass")
		return {}
	# Energia sin masa no define temperatura.
	if upper_mass_kg <= MASS_EPS_KG and absf(upper_energy_kj) > 0.0:
		errors.append("candidate_state upper zone has energy without mass")
	if lower_mass_kg <= MASS_EPS_KG and absf(lower_energy_kj) > 0.0:
		errors.append("candidate_state lower zone has energy without mass")
	if not errors.is_empty():
		return {}

	var upper_degenerate: bool = upper_mass_kg <= MASS_EPS_KG
	var lower_degenerate: bool = lower_mass_kg <= MASS_EPS_KG
	var upper_temp_k: float = reference_temp_k
	if not upper_degenerate:
		upper_temp_k += upper_energy_kj / (upper_mass_kg * AIR_CP_KJ_KG_K)
	var lower_temp_k: float = reference_temp_k
	if not lower_degenerate:
		lower_temp_k += lower_energy_kj / (lower_mass_kg * AIR_CP_KJ_KG_K)
	if upper_temp_k <= 0.0 or lower_temp_k <= 0.0:
		errors.append("candidate_state implies a zone temperature <= 0 K")
		return {}

	var pressure_abs_pa: float = gas_constant * (
		total_mass_kg * reference_temp_k + total_energy_kj / AIR_CP_KJ_KG_K
	) / volume_m3
	if not _is_finite(pressure_abs_pa) or pressure_abs_pa <= 0.0:
		errors.append("candidate_state implies a non-positive absolute pressure")
		return {}

	var upper_volume_m3: float = upper_mass_kg * gas_constant * upper_temp_k / pressure_abs_pa
	var lower_volume_m3: float = lower_mass_kg * gas_constant * lower_temp_k / pressure_abs_pa
	var closure_error_m3: float = upper_volume_m3 + lower_volume_m3 - volume_m3
	if absf(closure_error_m3) > VOLUME_CLOSURE_TOLERANCE * volume_m3:
		errors.append("zone volumes do not close the compartment volume")
		return {}

	# Una zona degenerada no tiene densidad propia: se extiende la de la otra,
	# sin inventar masa, para que el perfil tenga densidad a cualquier cota.
	var upper_density_kg_m3: float = 0.0
	var lower_density_kg_m3: float = 0.0
	if not upper_degenerate and upper_volume_m3 > VOLUME_EPS_M3:
		upper_density_kg_m3 = upper_mass_kg / upper_volume_m3
	if not lower_degenerate and lower_volume_m3 > VOLUME_EPS_M3:
		lower_density_kg_m3 = lower_mass_kg / lower_volume_m3
	if upper_density_kg_m3 <= 0.0:
		upper_density_kg_m3 = lower_density_kg_m3
	if lower_density_kg_m3 <= 0.0:
		lower_density_kg_m3 = upper_density_kg_m3
	if upper_density_kg_m3 <= 0.0 or lower_density_kg_m3 <= 0.0:
		errors.append("candidate_state has no usable gas density")
		return {}

	var floor_area_m2: float = float(state["floor_area_m2"])
	var height_m: float = float(state["height_m"])
	var interface_m: float = clampf(lower_volume_m3 / floor_area_m2, 0.0, height_m)
	var reference_mass_kg: float = float(outside_state["pressure_abs_pa"]) * volume_m3 \
			/ (gas_constant * reference_temp_k)
	var gauge_pressure_pa: float = gas_constant * (
		(total_mass_kg - reference_mass_kg) * reference_temp_k
		+ total_energy_kj / AIR_CP_KJ_KG_K
	) / volume_m3

	return {
		"volume_m3": volume_m3,
		"mass_kg": total_mass_kg,
		"energy_kj": total_energy_kj,
		"reference_mass_kg": reference_mass_kg,
		"upper_temp_k": upper_temp_k,
		"lower_temp_k": lower_temp_k,
		"upper_volume_m3": upper_volume_m3,
		"lower_volume_m3": lower_volume_m3,
		"volume_closure_error_m3": closure_error_m3,
		"upper_density_kg_m3": upper_density_kg_m3,
		"lower_density_kg_m3": lower_density_kg_m3,
		"interface_m": interface_m,
		"pressure_abs_pa": pressure_abs_pa,
		"gauge_pressure_pa": gauge_pressure_pa,
		"upper_degenerate": upper_degenerate,
		"lower_degenerate": lower_degenerate,
	}


## Perfil hidrostatico con el SUELO como referencia: nodos suelo, interfaz y
## techo, en cota absoluta. `zone_above` es la zona del tramo que empieza en el
## nodo. La presion es continua en la interfaz por construccion.
static func _pressure_profile(state: Dictionary, thermo: Dictionary, gauge_floor_pa: float) -> Array:
	var floor_z_m: float = float(state["floor_z_m"])
	var height_m: float = float(state["height_m"])
	var interface_m: float = float(thermo["interface_m"])
	var lower_density: float = float(thermo["lower_density_kg_m3"])
	var upper_density: float = float(thermo["upper_density_kg_m3"])
	var interface_pressure_pa: float = gauge_floor_pa - lower_density * GRAVITY_M_S2 * interface_m
	var ceiling_pressure_pa: float = interface_pressure_pa \
			- upper_density * GRAVITY_M_S2 * (height_m - interface_m)
	return [
		{
			"z_m": floor_z_m,
			"gauge_pressure_pa": gauge_floor_pa,
			"density_kg_m3": lower_density,
			"zone_above": ZONE_LOWER,
			"node": "floor",
		},
		{
			"z_m": floor_z_m + interface_m,
			"gauge_pressure_pa": interface_pressure_pa,
			"density_kg_m3": upper_density,
			"zone_above": ZONE_UPPER,
			"node": "interface",
		},
		{
			"z_m": floor_z_m + height_m,
			"gauge_pressure_pa": ceiling_pressure_pa,
			"density_kg_m3": upper_density,
			"zone_above": "",
			"node": "ceiling",
		},
	]


static func _diagnostics(candidate: Dictionary, previous: Dictionary, thermo: Dictionary,
		source_terms: Dictionary, flux_mass: Dictionary, flux_enthalpy: Dictionary,
		fluxes: Array, outside_state: Dictionary, gas_constant: float, dt: float) -> Dictionary:
	var diagnostics: Dictionary = {
		"dt_s": dt,
		"gas_constant_j_kg_k": gas_constant,
		"reference_temp_k": float(outside_state["reference_temp_k"]),
		"outside_pressure_abs_pa": float(outside_state["pressure_abs_pa"]),
		"candidate_absolute_pressure_pa": float(outside_state["pressure_abs_pa"])
				+ float(candidate["gauge_pressure_pa"]),
		"eos_absolute_pressure_pa": float(thermo["pressure_abs_pa"]),
		"eos_gauge_pressure_pa": float(thermo["gauge_pressure_pa"]),
		"upper_temp_k": float(thermo["upper_temp_k"]),
		"lower_temp_k": float(thermo["lower_temp_k"]),
		"upper_density_kg_m3": float(thermo["upper_density_kg_m3"]),
		"lower_density_kg_m3": float(thermo["lower_density_kg_m3"]),
		"upper_volume_m3": float(thermo["upper_volume_m3"]),
		"lower_volume_m3": float(thermo["lower_volume_m3"]),
		"volume_closure_error_m3": float(thermo["volume_closure_error_m3"]),
		"interface_m": float(thermo["interface_m"]),
		"reference_z_m": float(candidate["floor_z_m"]),
		"mass_kg": float(thermo["mass_kg"]),
		"energy_kj": float(thermo["energy_kj"]),
		"previous_mass_kg": float(previous["upper_gas_kg"]) + float(previous["lower_gas_kg"]),
		"previous_energy_kj": float(previous["upper_energy_kj"]) + float(previous["lower_energy_kj"]),
		"upper_degenerate": bool(thermo["upper_degenerate"]),
		"lower_degenerate": bool(thermo["lower_degenerate"]),
		"flux_count": fluxes.size(),
		"flux_mass_kg_s": {ZONE_UPPER: float(flux_mass[ZONE_UPPER]), ZONE_LOWER: float(flux_mass[ZONE_LOWER])},
		"flux_enthalpy_kw": {ZONE_UPPER: float(flux_enthalpy[ZONE_UPPER]), ZONE_LOWER: float(flux_enthalpy[ZONE_LOWER])},
		"source_mass_kg_s": {
			ZONE_UPPER: float(source_terms["upper_mass_kg_s"]),
			ZONE_LOWER: float(source_terms["lower_mass_kg_s"]),
		},
		"source_enthalpy_kw": {
			ZONE_UPPER: float(source_terms["upper_enthalpy_kw"]),
			ZONE_LOWER: float(source_terms["lower_enthalpy_kw"]),
		},
	}
	if candidate.has("declared_interface_height_m"):
		diagnostics["declared_interface_divergence_m"] = float(candidate["declared_interface_height_m"]) \
				- float(thermo["interface_m"])
	return diagnostics


static func _validated_outside(outside: Variant, errors: Array[String]) -> Dictionary:
	if typeof(outside) != TYPE_DICTIONARY:
		errors.append("outside must be a dictionary")
		return {}
	var checked: Dictionary = {}
	for key in ["pressure_abs_pa", "temp_k", "reference_temp_k"]:
		if not outside.has(key):
			errors.append("outside is missing '%s'" % key)
			continue
		var value: float = _number(outside[key])
		if not _is_finite(value):
			errors.append("outside %s must be finite" % key)
			continue
		if value <= 0.0:
			errors.append("outside %s must be > 0" % key)
			continue
		checked[key] = value
	if outside.has("density_kg_m3"):
		var density: float = _number(outside["density_kg_m3"])
		if not _is_finite(density) or density <= 0.0:
			errors.append("outside density_kg_m3 must be finite and > 0")
		else:
			checked["density_kg_m3"] = density
	return checked


static func _validated_state(state: Variant, label: String, needs_pressure: bool,
		errors: Array[String]) -> Dictionary:
	if typeof(state) != TYPE_DICTIONARY:
		errors.append("%s must be a dictionary" % label)
		return {}
	var checked: Dictionary = {}
	if not state.has("room_id") or _exact_text(state["room_id"]).strip_edges().is_empty():
		errors.append("%s needs a non-empty room_id" % label)
	else:
		checked["room_id"] = _exact_text(state["room_id"])
	var required: Array[String] = GEOMETRY_KEYS.duplicate()
	required.append_array(INVENTORY_KEYS)
	if needs_pressure:
		required.append("gauge_pressure_pa")
	for key in required:
		if not state.has(key):
			errors.append("%s is missing '%s'" % [label, key])
			continue
		var value: float = _number(state[key])
		if not _is_finite(value):
			errors.append("%s %s must be finite" % [label, key])
			continue
		checked[key] = value
	if not errors.is_empty():
		return checked
	if float(checked["height_m"]) <= 0.0 or float(checked["floor_area_m2"]) <= 0.0:
		errors.append("%s needs height_m and floor_area_m2 > 0" % label)
	for key in ["upper_gas_kg", "lower_gas_kg"]:
		if float(checked[key]) < 0.0:
			errors.append("%s %s must be >= 0" % [label, key])
	# La interfaz es DERIVADA. Si el llamante declara una, solo se valida y se
	# informa la divergencia: nunca se usa como estado.
	if state.has("declared_interface_height_m"):
		var declared: float = _number(state["declared_interface_height_m"])
		if not _is_finite(declared) or declared < 0.0 or declared > float(checked["height_m"]):
			errors.append("%s declared_interface_height_m must lie inside the compartment" % label)
		else:
			checked["declared_interface_height_m"] = declared
	return checked


static func _validated_sources(sources: Variant, errors: Array[String]) -> Dictionary:
	var checked: Dictionary = {}
	if typeof(sources) != TYPE_DICTIONARY:
		errors.append("sources must be a dictionary")
		return checked
	for key in SOURCE_KEYS:
		var value: float = 0.0
		if sources.has(key):
			value = _number(sources[key])
			if not _is_finite(value):
				errors.append("sources %s must be finite" % key)
				continue
		checked[key] = value
	return checked


## Flujos ya resueltos por F2.2B. Se ordenan para que el resultado no dependa
## del orden de entrada y se rechazan repetidos.
static func _validated_fluxes(opening_fluxes: Variant, errors: Array[String]) -> Array:
	var checked: Array = []
	if typeof(opening_fluxes) != TYPE_ARRAY:
		errors.append("opening_fluxes must be an array")
		return checked
	var seen: Dictionary = {}
	for flux in opening_fluxes:
		if typeof(flux) != TYPE_DICTIONARY:
			errors.append("each opening flux must be a dictionary")
			continue
		for key in ["opening_id", "zone", "mass_flow_kg_s", "enthalpy_flow_kw"]:
			if not flux.has(key):
				errors.append("opening flux is missing '%s'" % key)
		if not errors.is_empty():
			continue
		var opening_id: String = _exact_text(flux["opening_id"])
		if opening_id.strip_edges().is_empty():
			errors.append("opening flux needs a non-empty opening_id")
			continue
		var segment_id: String = _exact_text(flux.get("segment_id", ""))
		var zone: String = _exact_text(flux["zone"])
		if not ZONES.has(zone):
			errors.append("opening flux '%s' has unknown zone '%s'" % [opening_id, flux["zone"]])
			continue
		var mass_flow: float = _number(flux["mass_flow_kg_s"])
		var enthalpy_flow: float = _number(flux["enthalpy_flow_kw"])
		if not _is_finite(mass_flow) or not _is_finite(enthalpy_flow):
			errors.append("opening flux '%s' needs finite mass and enthalpy flows" % opening_id)
			continue
		var key_text: String = "%s|%s|%s" % [opening_id, segment_id, zone]
		if seen.has(key_text):
			errors.append("opening flux '%s' is listed twice" % key_text)
			continue
		seen[key_text] = true
		checked.append({
			"opening_id": opening_id,
			"segment_id": segment_id,
			"zone": zone,
			"mass_flow_kg_s": mass_flow,
			"enthalpy_flow_kw": enthalpy_flow,
			"sort_key": key_text,
		})
	checked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["sort_key"]) < String(right["sort_key"]))
	return checked


static func _invalid_result(errors: Array) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"room_id": "",
		"pressure_residual_pa": NAN,
		"pressure_residual_normalized": NAN,
		"mass_residual_kg": NAN,
		"energy_residual_kj": NAN,
		"mass_residual_by_zone_kg": {},
		"energy_residual_by_zone_kj": {},
		"pressure_profile": [],
		"diagnostics": {},
	}


static func _exact_text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	return String(value)


static func _number(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return NAN


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
