extends RefCounted

## F2.2D4B1: catalogo TRAZABLE de perfiles de puerta, marco y vidrio.
##
## Este fichero es el UNICO propietario del catalogo. No hay constantes de
## perfil repartidas entre el editor, el serializador y el motor.
##
## Lo que este catalogo NO hace, y no debe hacer nunca:
##
##   - no calcula caudal, presion, area de flujo, viento ni transporte;
##   - no reimplementa la ley de rendijas de D1, la de orificio de R3, la
##     geometria multicapa de D3 ni el aplicador atomico;
##   - no enciende ningun interruptor: un perfil es un DATO, no una activacion;
##   - no lee PDFs, ficheros externos ni la red. Las referencias son texto.
##
## ## Que significa cada estado de evidencia
##
##   - `validated`: hay evidencia experimental ESPECIFICA y suficiente dentro
##     del dominio declarado. No significa "apto para producto": un ensayo
##     puede ser solido y su dominio no cubrir el caso del juego.
##   - `derived`: calculo REPRODUCIBLE a partir de datos medidos, con la
##     transformacion escrita y sus limites explicitos.
##   - `research_only`: provisional, extrapolado o sin base experimental
##     propia. Nunca activable por defecto.
##   - `blocked`: evidencia insuficiente o CONTRADICTORIA. No produce
##     configuracion efectiva de ninguna clase.
##
## `product_activation` es una pregunta distinta y mas estricta: dice si el
## perfil PODRIA algun dia encenderse en un escenario de producto. Es `false`
## para todo lo que no sea `validated` o `derived`, y tambien para perfiles con
## evidencia solida cuyo dominio no cubre una vivienda real. Hoy NINGUN perfil
## se activa: D4B1 no toca interruptores ni escenarios.
##
## ## Identidad y version
##
## La identidad fisica de un perfil es el par `(profile_id, version)`, y es
## INMUTABLE: una vez publicado, sus parametros no cambian nunca. Corregir un
## valor obliga a publicar una version nueva; la anterior se conserva para que
## un escenario antiguo siga resolviendo exactamente lo mismo. Un test congela
## la huella de cada version publicada, de modo que editar una version ya
## publicada rompe la suite en vez de recalibrar escenarios guardados en
## silencio.
##
## ## Unidades
##
## Cada parametro declara su unidad en `units`, sin excepcion. Un parametro sin
## unidad es un error de contrato, no una omision tolerable.
##
## ## Prohibiciones cientificas que este catalogo hace cumplir
##
##   - un valor no se convierte en calibrado por repetirse en el codigo;
##   - una referencia de orden de magnitud no es una validacion;
##   - un resultado interno de SimuFire NO es un dato experimental, y los
##     perfiles que salen de una heuristica propia lo declaran asi;
##   - una extrapolacion fuera del ensayo se escribe, no se calla.

const EVIDENCE_VALIDATED: String = "validated"
const EVIDENCE_DERIVED: String = "derived"
const EVIDENCE_RESEARCH_ONLY: String = "research_only"
const EVIDENCE_BLOCKED: String = "blocked"

const EVIDENCE_STATES: Array[String] = [
	EVIDENCE_VALIDATED, EVIDENCE_DERIVED, EVIDENCE_RESEARCH_ONLY, EVIDENCE_BLOCKED,
]
## Solo estos dos pueden aspirar a producto, y ademas deben declararlo.
const PRODUCT_CAPABLE_STATES: Array[String] = [EVIDENCE_VALIDATED, EVIDENCE_DERIVED]

const CATEGORY_DOOR_LEAKAGE: String = "door_leakage"
const CATEGORY_FRAME_LEAKAGE: String = "frame_leakage"
const CATEGORY_DEFORMATION: String = "deformation"
const CATEGORY_GLAZING: String = "glazing"
const CATEGORY_VERTICAL_SHAFT: String = "vertical_shaft"

const CATEGORIES: Array[String] = [
	CATEGORY_DOOR_LEAKAGE, CATEGORY_FRAME_LEAKAGE, CATEGORY_DEFORMATION,
	CATEGORY_GLAZING, CATEGORY_VERTICAL_SHAFT,
]

## Categorias que hoy pueden colgarse de una abertura en el escenario. Las
## demas existen como referencia cientifica: su interfaz de producto es D4B2.
const PERSISTABLE_CATEGORIES: Array[String] = [
	CATEGORY_DOOR_LEAKAGE, CATEGORY_FRAME_LEAKAGE,
]

## Aire seco a 20 C y 101 325 Pa, el mismo valor con el que NBSIR 81-2214
## (p. 4) fija K = 0,827 y con el que Gross y Haberman tabulan sus caudales
## (tabla 2, p. 177: 1,204 kg/m3 a 20 C). Se declara aqui porque TODA
## transformacion de un caudal medido a un area efectiva lo necesita.
const REFERENCE_AIR_DENSITY_KG_M3: float = 1.204

## Presion de referencia del ELA y su coeficiente, por convenio (NIST TN 1887r1
## p. 266, ec. 28-29). No es un valor ajustable: es la definicion del dato.
const ELA_REFERENCE_PRESSURE_PA: float = 4.0
const ELA_REFERENCE_DISCHARGE_COEFFICIENT: float = 1.0


## El catalogo. Orden fijo y estable: la salida de este modulo es determinista.
##
## Cada entrada declara, ademas de sus parametros, DE DONDE sale cada numero,
## en que ensayo, con que rango y que transformacion se le aplico.
const PROFILES: Array = [
	# ------------------------------------------------------------------
	# Fuga fria de puerta cerrada (D1)
	# ------------------------------------------------------------------
	{
		"profile_id": "door.entry.weatherstripped.ashrae2001",
		"version": 1,
		"category": CATEGORY_DOOR_LEAKAGE,
		"evidence": EVIDENCE_RESEARCH_ONLY,
		"product_activation": false,
		"title": "Puerta de entrada con burlete, estimacion ASHRAE 2001",
		"applies_to": "puerta de entrada de vivienda, hoja simple, con burlete",
		"parameters": {"ela_m2": 0.0012},
		"units": {"ela_m2": "m2 (ELA a 4 Pa, Cd = 1)"},
		"domain": {
			"reference_pressure_pa": 4.0,
			"test_pressure_range_pa": "no declarado por la fuente",
			"temperature_c": "ambiente, no declarado",
			"sample_size": "no declarado (best estimate de manual)",
		},
		"references": [
			{
				"source": "NIST TN 2329 (2025)",
				"locator": "p. 28, seccion 5.9 Doors",
				"local_path": "docs/literature/NIST/NIST_TN_2329_US_Housing_Stock_2025.pdf",
			},
			{
				"source": "ASHRAE Fundamentals 2001, Ventilation and Infiltration",
				"locator": "Table 1, Effective Air Leakage Areas (Low-Rise Residential Applications Only), fila 'single door, weather-stripped', columna Best Estimated",
				"local_path": "no disponible localmente (manual comercial)",
			},
		],
		"transform": "ninguna: el valor se toma tal cual, ya expresado como ELA a 4 Pa.",
		"uncertainty": "desconocida: la fuente publica un unico 'best estimate', sin rango ni tamaño de muestra.",
		"warnings": [
			"La tabla ASHRAE de la que sale este valor FUE RETIRADA de las ediciones posteriores del manual (NIST TN 2329, p. 28).",
			"NIST la usaba en la coleccion de viviendas de 2006 y en la actualizacion de 2025 dice expresamente que esas fugas de puerta 'podrian eliminarse'.",
			"Es una estimacion de manual, no una campana experimental: no puede presentarse como calibrada.",
		],
	},
	{
		"profile_id": "door.interior.not_weatherstripped.ashrae2001",
		"version": 1,
		"category": CATEGORY_DOOR_LEAKAGE,
		"evidence": EVIDENCE_RESEARCH_ONLY,
		"product_activation": false,
		"title": "Puerta simple sin burlete, estimacion ASHRAE 2001",
		"applies_to": "puerta simple sin burlete; NIST la aplico a garaje-vivienda y a sotano",
		"parameters": {"ela_m2": 0.0021},
		"units": {"ela_m2": "m2 (ELA a 4 Pa, Cd = 1)"},
		"domain": {
			"reference_pressure_pa": 4.0,
			"test_pressure_range_pa": "no declarado por la fuente",
			"temperature_c": "ambiente, no declarado",
			"sample_size": "no declarado (best estimate de manual)",
		},
		"references": [
			{
				"source": "NIST TN 2329 (2025)",
				"locator": "p. 28, seccion 5.9 Doors",
				"local_path": "docs/literature/NIST/NIST_TN_2329_US_Housing_Stock_2025.pdf",
			},
			{
				"source": "ASHRAE Fundamentals 2001, Ventilation and Infiltration",
				"locator": "Table 1, fila 'single door, not weather-stripped', columna Best Estimated",
				"local_path": "no disponible localmente (manual comercial)",
			},
		],
		"transform": "ninguna: el valor se toma tal cual, ya expresado como ELA a 4 Pa.",
		"uncertainty": "desconocida: un unico 'best estimate', sin rango ni tamaño de muestra.",
		"warnings": [
			"La tabla ASHRAE de origen fue RETIRADA de ediciones posteriores del manual.",
			"El significado de la fuente es 'puerta simple SIN burlete', no 'puerta interior tipica': NIST la aplico a la puerta garaje-vivienda y a la de sotano.",
			"Comparado con las puertas realmente medidas (perfil door.interior.installed_measured_range.v1), 21 cm2 cae en el EXTREMO ESTANCO del rango observado, cerca de un especimen de laboratorio con holguras de 0,6 mm.",
			"No representa una puerta de paso residencial instalada.",
		],
	},
	{
		"profile_id": "door.interior.installed_measured_range",
		"version": 1,
		"category": CATEGORY_DOOR_LEAKAGE,
		"evidence": EVIDENCE_DERIVED,
		"product_activation": false,
		"title": "Rango de ELA de puertas interiores realmente medidas",
		"applies_to": "puertas interiores instaladas y especimenes de laboratorio de control de humos; NO son puertas de paso residenciales",
		"parameters": {
			"ela_min_m2": 0.002017,
			"ela_max_m2": 0.0234,
			"reference_flow_pressure_pa": 25.0,
			"flow_exponent_used": 0.5,
		},
		"units": {
			"ela_min_m2": "m2 (ELA a 4 Pa, Cd = 1)",
			"ela_max_m2": "m2 (ELA a 4 Pa, Cd = 1)",
			"reference_flow_pressure_pa": "Pa (presion del ensayo de origen)",
			"flow_exponent_used": "adimensional",
		},
		"domain": {
			"reference_pressure_pa": 4.0,
			"test_pressure_range_pa": "25 Pa (punto unico de ensayo)",
			"temperature_c": "ambiente",
			"sample_size": "11 conjuntos de puerta medidos (8 de escalera instalados + 3 de laboratorio)",
		},
		"references": [
			{
				"source": "Gross y Haberman 1989, Fire Safety Science 2",
				"locator": "Table 1, p. 176: caudales MEDIDOS a dp = 25 Pa, de 0,013 a 0,151 m3/s",
				"local_path": "docs/literature/NIST/Gross_Haberman_Door_Air_Leakage_1989.pdf",
			},
			{
				"source": "NBSIR 81-2214 (1981)",
				"locator": "Table 1, p. 17: exponente n = 0,5 para 'Door Gaps'; Table 2, p. 18: caudales por unidad de longitud de rendija a 25 Pa",
				"local_path": "docs/literature/NIST/NBSIR_81_2214_Door_Air_Leakage.pdf",
			},
		],
		"transform": "ELA = Q(25 Pa) * (4/25)^0,5 / raiz(2*4/rho), con rho = 1,204 kg/m3 y n = 0,5 (NBSIR tabla 1, 'Door Gaps'). Extremo estanco: Q = 0,013 m3/s (especimen [26]A, holgura 0,6 mm en todos los bordes) -> 0,002017 m2 = 20,2 cm2. Extremo permeable: Q = 0,151 m3/s (puerta de escalera [24]8, holgura inferior 17,6 mm) -> 0,0234 m2 = 234,3 cm2. El validador rehace esta cuenta y la compara con la precision con la que la fuente imprime sus numeros.",
		"uncertainty": "La propia fuente concluye que hay 'un rango amplio en las medidas entre puertas distintas, incluso de construccion similar' (NBSIR p. 12, conclusion 2). El modelo predictivo de Gross y Haberman concuerda con lo medido 'dentro del 20 por ciento'.",
		"warnings": [
			"Es un RANGO, no un valor: no puede usarse como ELA efectiva de una abertura. Sirve como envolvente de verosimilitud.",
			"Las puertas medidas son de escalera, de oficina y cortafuegos, en edificios altos canadienses y laboratorios europeos. NO hay ninguna puerta de paso residencial en la muestra.",
			"La referencia de 4 Pa queda POR DEBAJO del rango en el que se miden las ELA (NIST TN 1887r1, p. 266: ensayos de presurizacion de unos 10 a 75 Pa): llevar un caudal de 25 Pa a 4 Pa es una extrapolacion.",
			"El exponente 0,5 usado en la transformacion es el valor de la tabla para holguras de puerta, y la propia NBSIR (p. 4) advierte de que es una SUPOSICION habitual, no una medida.",
		],
	},
	{
		"profile_id": "door.interior.residential_passage",
		"version": 1,
		"category": CATEGORY_DOOR_LEAKAGE,
		"evidence": EVIDENCE_BLOCKED,
		"product_activation": false,
		"title": "Puerta de paso residencial (BLOQUEADA: no hay medicion)",
		"applies_to": "puerta interior de paso de vivienda, que es justo la del juego",
		"parameters": {},
		"units": {},
		"domain": {},
		"references": [
			{
				"source": "NBSIR 81-2214 (1981)",
				"locator": "p. 8: 'In the U.S., there are no known specifications limiting air leakage through interior door assemblies'; p. 12, conclusion 2: hacen falta medidas precisas sobre una variedad amplia de puertas interiores",
				"local_path": "docs/literature/NIST/NBSIR_81_2214_Door_Air_Leakage.pdf",
			},
		],
		"transform": "ninguna: no hay dato que transformar.",
		"uncertainty": "total.",
		"warnings": [
			"NO EXISTE una medicion de fuga de puerta de paso residencial en la biblioteca, ni una especificacion que la limite.",
			"Para desbloquearlo hace falta un ensayo tipo ASTM E283 o ISO 5925-1 sobre puertas de paso residenciales, con presion aplicada por separado en cada sentido y varios escalones entre 5 y 100 Pa.",
			"Mientras siga bloqueado, ninguna clase de fuga de puerta interior puede presentarse como calibrada.",
		],
	},
	{
		"profile_id": "door.interior.loose_fitting",
		"version": 1,
		"category": CATEGORY_DOOR_LEAKAGE,
		"evidence": EVIDENCE_BLOCKED,
		"product_activation": false,
		"title": "Puerta interior desajustada (BLOQUEADA: solo cotas inferiores)",
		"applies_to": "puerta interior vieja o mal ajustada",
		"parameters": {},
		"units": {},
		"domain": {},
		"references": [
			{
				"source": "NBSIR 81-2214 (1981)",
				"locator": "Table 2, p. 18: 'Interior wood door, hung as in use' y 'same, with 25 mm stop' figuran como '>40' m3/h.m a 25 Pa",
				"local_path": "docs/literature/NIST/NBSIR_81_2214_Door_Air_Leakage.pdf",
			},
		],
		"transform": "ninguna: un valor censurado ('>40') no define un numero.",
		"uncertainty": "no acotada por arriba.",
		"warnings": [
			"Las unicas puertas sin sellar de la tabla se publican como COTAS INFERIORES ('>15', '>40'), sin valor ni limite superior.",
			"Inventar un valor a partir de una cota inferior seria fabricar el dato que falta.",
		],
	},
	# ------------------------------------------------------------------
	# Fuga de marco exterior cerrado (R3)
	# ------------------------------------------------------------------
	{
		"profile_id": "frame.exterior.window.legacy_engine_value",
		"version": 1,
		"category": CATEGORY_FRAME_LEAKAGE,
		"evidence": EVIDENCE_RESEARCH_ONLY,
		"product_activation": false,
		"title": "Area de fuga de ventana exterior heredada del motor",
		"applies_to": "ventana exterior cerrada, cualquier tamaño (valor global historico)",
		"parameters": {"leak_area_m2": 0.005, "discharge_coefficient": 0.61},
		"units": {
			"leak_area_m2": "m2 (area GEOMETRICA de orificio; el Cd va aparte)",
			"discharge_coefficient": "adimensional",
		},
		"domain": {
			"reference_pressure_pa": "ninguna: la ley de orificio no usa presion de referencia",
			"test_pressure_range_pa": "no aplicable, no procede de un ensayo",
			"sample_size": "no aplicable",
		},
		"references": [
			{
				"source": "SimuFire, ruta historica",
				"locator": "GasExchangeSystem.step_pressure_venting: 0.61 * window_leakage_area_m2 * sqrt(2*dp/rho); SimulationEngine.window_leakage_area_m2 = 0.005",
				"local_path": "sim/core/GasExchangeSystem.gd",
			},
		],
		"transform": "ninguna: es el valor que el motor ha usado siempre.",
		"uncertainty": "desconocida.",
		"warnings": [
			"NO ES UN DATO EXPERIMENTAL. Sale de una heuristica del propio motor, y un resultado interno de SimuFire no puede presentarse como evidencia.",
			"Su unico estatus es historico: es el valor que preserva la identidad con la ruta anterior.",
			"Queda POR ENCIMA de todo el rango derivado de ventanas reales (perfil frame.exterior.window.measured_range.v1): 50 cm2 frente a 3,4-38,9 cm2 para una ventana de 1,2 x 1,0 m, es decir 1,29 veces la ventana mas permeable medida.",
			"CFAST usa, en un caso concreto, 0,007344 m2 de pared mas 0,001040 m2 de suelo con Cd 0,7. Es una referencia de ORDEN DE MAGNITUD, no una validacion.",
		],
	},
	{
		"profile_id": "frame.exterior.window.measured_range",
		"version": 1,
		"category": CATEGORY_FRAME_LEAKAGE,
		"evidence": EVIDENCE_DERIVED,
		"product_activation": false,
		"title": "Rango de area de fuga de ventanas domesticas medidas",
		"applies_to": "ventana domestica cerrada de 1,2 x 1,0 m (longitud de rendija 4,4 m)",
		"parameters": {
			"leak_area_min_m2": 0.000342,
			"leak_area_max_m2": 0.00389,
			"discharge_coefficient": 0.61,
			"reference_window_width_m": 1.2,
			"reference_window_height_m": 1.0,
		},
		"units": {
			"leak_area_min_m2": "m2 (area geometrica de orificio con Cd = 0,61 aparte)",
			"leak_area_max_m2": "m2 (area geometrica de orificio con Cd = 0,61 aparte)",
			"discharge_coefficient": "adimensional",
			"reference_window_width_m": "m",
			"reference_window_height_m": "m",
		},
		"domain": {
			"test_pressure_range_pa": "100 Pa (punto de ensayo de la fuente)",
			"temperature_c": "ambiente",
			"sample_size": "rangos publicados de ventanas domesticas con y sin burlete",
		},
		"references": [
			{
				"source": "NBSIR 81-2214 (1981)",
				"locator": "Table 3, p. 19, bloque 'Windows': domestica con burlete 2,2-13,8 m3/h.m a 100 Pa; sin burlete 6-25 m3/h.m a 100 Pa",
				"local_path": "docs/literature/NIST/NBSIR_81_2214_Door_Air_Leakage.pdf",
			},
		],
		"transform": "A = Q / (Cd * raiz(2*dp/rho)), con Q = tasa[m3/h.m] * 4,4 m / 3600, dp = 100 Pa, Cd = 0,61 y rho = 1,204 kg/m3. Extremo estanco 2,2 m3/h.m -> 0,000342 m2 = 3,4 cm2; extremo permeable 25 m3/h.m -> 0,00389 m2 = 38,9 cm2. El validador rehace esta cuenta.",
		"uncertainty": "la fuente publica rangos, no valores unicos; el reparto dentro del rango depende del tipo de carpinteria.",
		"warnings": [
			"Es un RANGO ligado a un tamaño de ventana concreto: escalarlo a otra ventana exige recalcular la longitud de rendija.",
			"La ley de orificio con Cd = 0,61 es la del motor; la fuente publica caudales, no coeficientes.",
			"No sustituye al valor historico del motor mientras no se decida una politica de producto: eso es D4B2.",
		],
	},
	# ------------------------------------------------------------------
	# Deformacion prescrita (D2)
	# ------------------------------------------------------------------
	{
		"profile_id": "deformation.steel_fire_door.furnace_topology",
		"version": 1,
		"category": CATEGORY_DEFORMATION,
		"evidence": EVIDENCE_RESEARCH_ONLY,
		"product_activation": false,
		"title": "Topologia de deformacion de puerta cortafuegos de acero en horno",
		"applies_to": "puerta cortafuegos de ACERO en horno normalizado; NO una puerta residencial",
		"parameters": {
			"gap_locations": ["top", "latch_side"],
			"observed_gap_min_m": 0.00083,
			"observed_gap_max_m": 0.0037,
			"observed_centre_deflection_m": 0.010,
			"observed_centre_deflection_time_s": 600.0,
		},
		"units": {
			"gap_locations": "enumerado de posiciones de ClosedDoorDeformationModel",
			"observed_gap_min_m": "m (espesor de hueco calculado)",
			"observed_gap_max_m": "m (espesor de hueco calculado)",
			"observed_centre_deflection_m": "m (flecha del centro de la hoja)",
			"observed_centre_deflection_time_s": "s",
		},
		"domain": {
			"specimen": "puerta cortafuegos de acero",
			"exposure": "curva de horno normalizada",
			"furnace_pressure_pa": "unos 16 Pa arriba y 0,2 Pa abajo (no uniforme)",
			"temperature_c": "exposicion normalizada de resistencia al fuego",
		},
		"references": [
			{
				"source": "Prieler et al. 2023, Journal of Structural Fire Engineering",
				"locator": "pp. 16-19, figs. 18-23: huecos principales en el borde superior y en el lado de la cerradura por encima de esta",
				"local_path": "docs/literature/Doors/Prieler_Door_Deformation_Flue_Gas_Leakage_2023.pdf",
			},
			{
				"source": "Prieler et al. 2020, Fire and Materials",
				"locator": "primeros gases entre 110 y 130 s con hueco calculado de unos 0,83 mm, creciendo hasta unos 3,7 mm",
				"local_path": "no disponible localmente (enlace registrado en el indice)",
			},
		],
		"transform": "ninguna: las magnitudes se citan como orden de magnitud y forma temporal, no se convierten en area efectiva.",
		"uncertainty": "no transferible: material, herrajes, marco y exposicion son distintos de los de una puerta residencial.",
		"warnings": [
			"La TOPOLOGIA (dintel y lado de cerradura) esta respaldada; las MAGNITUDES no lo estan para una puerta residencial.",
			"El modelo de D2 recibe area efectiva adicional, no milimetros: convertir estos huecos en ELA exigiria una hipotesis de longitud y de coeficiente que la fuente no da.",
			"No existe ninguna ley temperatura-tiempo-deformacion defendible: D2 sigue siendo prescripcion, no prediccion.",
		],
	},
	{
		"profile_id": "deformation.residential_door.thermal_law",
		"version": 1,
		"category": CATEGORY_DEFORMATION,
		"evidence": EVIDENCE_BLOCKED,
		"product_activation": false,
		"title": "Ley termica de deformacion residencial (BLOQUEADA)",
		"applies_to": "puerta de paso residencial sometida a calentamiento",
		"parameters": {},
		"units": {},
		"domain": {},
		"references": [
			{
				"source": "Gross y Haberman 1989",
				"locator": "p. 176, seccion 3: para conjuntos de puerta de control de humos la deformacion y el alabeo son pequenos por debajo de unos 300 C; por encima no se valida ninguna ley",
				"local_path": "docs/literature/NIST/Gross_Haberman_Door_Air_Leakage_1989.pdf",
			},
		],
		"transform": "ninguna.",
		"uncertainty": "total.",
		"warnings": [
			"La heuristica heredada del motor (150-350 C hasta el 4 % de la hoja) NO tiene respaldo localizado y no se usa como calibracion.",
			"Ese 4 % de una hoja de 0,92 x 2,05 m son unos 754 cm2: unas 36 veces el ELA provisional de 21 cm2. No es una fuga fisica medida.",
		],
	},
	# ------------------------------------------------------------------
	# Vidrio (D3)
	# ------------------------------------------------------------------
	{
		"profile_id": "glazing.annealed.igu.radiant_panel",
		"version": 1,
		"category": CATEGORY_GLAZING,
		"evidence": EVIDENCE_VALIDATED,
		"product_activation": false,
		"title": "Vidrio recocido en unidad aislante bajo panel radiante",
		"applies_to": "unidades de vidrio recocido de 1 a 3 hojas, 3-8 mm, lados de 200-500 mm",
		"parameters": {
			"glass_type": "annealed",
			"thickness_min_m": 0.003,
			"thickness_max_m": 0.008,
			"pane_side_min_m": 0.200,
			"pane_side_max_m": 0.500,
			"leaf_count_min": 1,
			"leaf_count_max": 3,
			"edge_cover_m": 0.020,
			"incident_heat_flux_kw_m2": 20.0,
			"fallout_fraction_at_crack_min": 0.10,
			"fallout_fraction_at_crack_max": 0.25,
			"fallout_fraction_delayed_min": 0.60,
			"fallout_fraction_delayed_max": 0.90,
		},
		"units": {
			"glass_type": "enumerado de GlazingIntegrityModel",
			"thickness_min_m": "m",
			"thickness_max_m": "m",
			"pane_side_min_m": "m",
			"pane_side_max_m": "m",
			"leaf_count_min": "hojas",
			"leaf_count_max": "hojas",
			"edge_cover_m": "m (ancho de marco que tapa el vidrio)",
			"incident_heat_flux_kw_m2": "kW/m2",
			"fallout_fraction_at_crack_min": "fraccion de area desprendida",
			"fallout_fraction_at_crack_max": "fraccion de area desprendida",
			"fallout_fraction_delayed_min": "fraccion de area desprendida",
			"fallout_fraction_delayed_max": "fraccion de area desprendida",
		},
		"domain": {
			"exposure": "flujo radiante constante de unos 20 kW/m2 (condiciones post-flashover)",
			"specimen_size_m": "lados de 0,200 a 0,500 m",
			"sample_size": "75 ensayos en total; desprendimiento observado en 15 de 18 unidades aislantes tipo 'b'",
			"temperature_c": "no se declara temperatura de gas: el control es el flujo radiante",
		},
		"references": [
			{
				"source": "Peng et al. 2024 (DTU)",
				"locator": "resumen y seccion 3.2 con la tabla 2: fracciones de desprendimiento de 10-25 % al agrietarse y 60-90 % cuando se retrasa; el 90 % equivale a 1 cm de vidrio en el borde",
				"local_path": "docs/literature/Glass/Peng_Modern_Window_Glazing_Fire_2024.pdf",
			},
		],
		"transform": "ninguna: las fracciones se usan como fracciones, que es la magnitud que consume GlazingIntegrityModel.",
		"uncertainty": "las fracciones se publican como 'rough fraction estimate'; los propios autores avisan de que los ensayos se detuvieron poco despues de agrietarse la ultima hoja.",
		"warnings": [
			"El dominio son especimenes de 200-500 mm de lado. Una ventana residencial de 0,6 a 1,2 m queda FUERA: por eso no puede activarse en producto.",
			"No se observo NUNCA un desprendimiento del 100 %: el maximo fue el 90 %, que deja 1 cm de vidrio en el borde. Un estado OPEN (fraccion 1) es una EXTRAPOLACION por encima de lo medido.",
			"La fuente da CUANDO y CUANTO se desprende en su ensayo; no da una historia prescrita para una ventana concreta del juego.",
		],
	},
	{
		"profile_id": "glazing.laminated.no_fallout",
		"version": 1,
		"category": CATEGORY_GLAZING,
		"evidence": EVIDENCE_VALIDATED,
		"product_activation": false,
		"title": "Vidrio laminado: sin desprendimiento en el dominio ensayado",
		"applies_to": "vidrio laminado con butiral, 3-8 mm, lados de 200-500 mm",
		"parameters": {
			"glass_type": "laminated",
			"observed_fallout_fraction": 0.0,
			"incident_heat_flux_kw_m2": 20.0,
		},
		"units": {
			"glass_type": "enumerado de GlazingIntegrityModel",
			"observed_fallout_fraction": "fraccion de area desprendida",
			"incident_heat_flux_kw_m2": "kW/m2",
		},
		"domain": {
			"exposure": "flujo radiante constante de unos 20 kW/m2",
			"specimen_size_m": "lados de 0,200 a 0,500 m",
			"sample_size": "todas las muestras laminadas de la campana de 75 ensayos",
		},
		"references": [
			{
				"source": "Peng et al. 2024 (DTU)",
				"locator": "seccion 3.1: 'None of the laminated samples experienced any fallout. Thus, no vent was created in these cases.'",
				"local_path": "docs/literature/Glass/Peng_Modern_Window_Glazing_Fire_2024.pdf",
			},
		],
		"transform": "ninguna.",
		"uncertainty": "los autores advierten de que con exposiciones mas largas el butiral podria no aguantar.",
		"warnings": [
			"Resultado NEGATIVO y por tanto solido dentro de su dominio: el laminado no ventila.",
			"Fuera del dominio (ventana grande, exposicion prolongada) la propia fuente se abstiene de concluir.",
		],
	},
	{
		"profile_id": "glazing.toughened.contradictory",
		"version": 1,
		"category": CATEGORY_GLAZING,
		"evidence": EVIDENCE_BLOCKED,
		"product_activation": false,
		"title": "Vidrio templado (BLOQUEADO: evidencia contradictoria)",
		"applies_to": "vidrio templado en incendio de recinto",
		"parameters": {},
		"units": {},
		"domain": {},
		"references": [
			{
				"source": "Peng et al. 2024 (DTU)",
				"locator": "resumen: 'No cracking ... observed in toughened' bajo 20 kW/m2 con especimenes de 200-500 mm",
				"local_path": "docs/literature/Glass/Peng_Modern_Window_Glazing_Fire_2024.pdf",
			},
			{
				"source": "Wang et al. 2007, AOFST 7",
				"locator": "resumen: en sala ISO 9705 con fuegos de bandeja, el templado rompe con diferencias de temperatura mayores que el flotado, pero 'almost the whole toughened glass falls out completely soon after the first breakage occurs'",
				"local_path": "docs/literature/Glass/Toughened_Glass_Enclosure_Fires_2007.pdf",
			},
		],
		"transform": "ninguna.",
		"uncertainty": "las dos fuentes describen comportamientos incompatibles en exposiciones distintas.",
		"warnings": [
			"Una fuente no ve NINGUNA grieta y la otra ve desprendimiento CASI TOTAL poco despues de la primera rotura. No se pueden promediar.",
			"Ademas, el contrato de estados de D3 (INTACT -> CRACKED -> PARTIAL_FALLOUT -> OPEN, sin saltos) no puede representar el salto casi inmediato que describe Wang sin inventar un PARTIAL_FALLOUT intermedio que nadie observo.",
			"Desbloquearlo exige decidir antes si el contrato de estados admite CRACKED -> OPEN, y eso es una decision de diseno pendiente (§14.7 del documento de puertas).",
		],
	},
	{
		"profile_id": "glazing.multilayer.free_path_rule",
		"version": 1,
		"category": CATEGORY_GLAZING,
		"evidence": EVIDENCE_DERIVED,
		"product_activation": false,
		"title": "Regla del camino libre en acristalamiento multicapa",
		"applies_to": "unidades de 2 y 3 hojas",
		"parameters": {"requires_free_path_through_all_leaves": true},
		"units": {"requires_free_path_through_all_leaves": "booleano (regla, no magnitud)"},
		"domain": {
			"exposure": "flujo radiante constante de unos 20 kW/m2",
			"specimen_size_m": "lados de 0,200 a 0,500 m",
			"sample_size": "18 unidades aislantes tipo 'b'",
		},
		"references": [
			{
				"source": "Peng et al. 2024 (DTU)",
				"locator": "resumen: el agrietamiento de las hojas siguientes se retrasa segun cuanto se desprenda la primera, 'indicating that such unit could provide no ventilation at flashover'; seccion 3.2: solo en un ensayo (S3b.2) se observo desprendimiento de la hoja 2, y ninguno en la hoja expuesta al ambiente",
				"local_path": "docs/literature/Glass/Peng_Modern_Window_Glazing_Fire_2024.pdf",
			},
		],
		"transform": "de la observacion 'la unidad puede no ventilar aunque la primera hoja se desprenda' se deriva la REGLA de que solo ventila el camino libre a traves de TODAS las hojas. La interseccion geometrica exacta la calcula GlazingOpeningGeometryModel; este perfil no la reimplementa.",
		"uncertainty": "los ensayos se detuvieron poco despues de agrietarse la ultima hoja, asi que no acotan el comportamiento a tiempos largos.",
		"warnings": [
			"La regla es cualitativa: respalda la INTERSECCION, no un valor numerico.",
			"No autoriza a suponer que la hoja exterior nunca se desprende: la fuente lo desmiente expresamente.",
		],
	},
	{
		"profile_id": "glazing.edge_protection.collapse_rule",
		"version": 1,
		"category": CATEGORY_GLAZING,
		"evidence": EVIDENCE_DERIVED,
		"product_activation": false,
		"title": "Proteccion de borde y colapso del pano",
		"applies_to": "vidrio recocido en incendio de compartimento, con y sin borde protegido",
		"parameters": {
			"edge_protected_critical_delta_t_c": 90.0,
			"edge_protected_theoretical_delta_t_c": 70.0,
			"edge_unprotected_collapse_observed": false,
		},
		"units": {
			"edge_protected_critical_delta_t_c": "C (diferencia centro-borde)",
			"edge_protected_theoretical_delta_t_c": "C (diferencia centro-borde)",
			"edge_unprotected_collapse_observed": "booleano",
		},
		"domain": {
			"exposure": "compartimento con flujos de dos capas caracteristicos de incendios de edificio",
			"glass_type": "recocido",
			"sample_size": "dos grupos de ensayo: borde protegido y borde no protegido",
		},
		"references": [
			{
				"source": "Skelly, Roby y Beyler 1990 (Virginia Tech)",
				"locator": "resumen: valor critico experimental de unos 90 C frente a 70 C teoricos de Keski-Rahkonen, diferencia atribuida al calentamiento radiativo; con borde protegido las grietas se propagan y causan 'at least partial collapse'; con borde NO protegido 'there was no window collapse in any of these cases'",
				"local_path": "docs/literature/Glass/Skelly_Glass_Breakage_Compartment_Fires_1990.pdf",
			},
		],
		"transform": "ninguna: los 90 C se citan como umbral experimental del ensayo, no se convierten en una ley del motor.",
		"uncertainty": "la propia fuente reconoce que el mecanismo del caso de borde no protegido 'is not known'.",
		"warnings": [
			"La PROTECCION DE BORDE decide si el pano llega a colapsar. Un pano de borde no protegido se agrieta pero no colapso en ningun ensayo: prescribirle un desprendimiento seria contradecir la fuente.",
			"El umbral de 90 C pertenece a un futuro modelo termico tipo BREAK1, que NO esta implementado y que D4B1 no implementa.",
		],
	},
	# ------------------------------------------------------------------
	# Hueco vertical
	# ------------------------------------------------------------------
	{
		"profile_id": "shaft.vertical_opening.uncalibrated",
		"version": 1,
		"category": CATEGORY_VERTICAL_SHAFT,
		"evidence": EVIDENCE_BLOCKED,
		"product_activation": false,
		"title": "Hueco vertical entre plantas (BLOQUEADO: sin fuente)",
		"applies_to": "hueco de forjado o de escalera entre dos plantas",
		"parameters": {},
		"units": {},
		"domain": {},
		"references": [
			{
				"source": "NIST TN 1887r1 (CONTAM)",
				"locator": "p. 266: el modelo de escalera de CONTAM se ajusta a los datos de Achakji y Tamura 1988, con Cd = 0,6 y un area efectiva funcion del area del hueco, la altura entre plantas, la densidad de personas (0, 1 y 2 personas/m2) y si los peldanos son abiertos o cerrados",
				"local_path": "docs/literature/NIST/NIST_TN_1887r1_CONTAM_User_Guide.pdf",
			},
		],
		"transform": "ninguna.",
		"uncertainty": "total: el Cd de 0,61 y el area declarada del motor no proceden de ninguna fuente.",
		"warnings": [
			"El hueco vertical del motor usa Cd = 0,61 y el area que declare el escenario, sin respaldo documental.",
			"La via para desbloquearlo esta identificada (el elemento de escalera de CONTAM), pero exige implementar otro modelo, no reetiquetar el actual.",
		],
	},
]


# ------------------------------------------------------------
# Consulta
# ------------------------------------------------------------

## Identidad versionada, que es la que viaja en un escenario.
static func versioned_id(profile_id: String, version: int) -> String:
	return "%s@%d" % [profile_id, version]


## Todos los identificadores versionados, en el orden del catalogo.
static func all_versioned_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_profile in PROFILES:
		var profile: Dictionary = raw_profile
		ids.append(versioned_id(String(profile["profile_id"]), int(profile["version"])))
	return ids


## Un perfil por identidad versionada, o {} si no existe. Copia profunda: el
## catalogo es constante y nadie puede modificarlo desde fuera.
static func find(profile_id: String, version: int) -> Dictionary:
	for raw_profile in PROFILES:
		var profile: Dictionary = raw_profile
		if String(profile["profile_id"]) == profile_id and int(profile["version"]) == version:
			return profile.duplicate(true)
	return {}


## ¿Existe ese `profile_id` en alguna version? Sirve para distinguir un perfil
## DESCONOCIDO de una version incompatible, que son dos errores distintos.
static func has_profile_id(profile_id: String) -> bool:
	for raw_profile in PROFILES:
		if String(Dictionary(raw_profile)["profile_id"]) == profile_id:
			return true
	return false


static func versions_of(profile_id: String) -> Array[int]:
	var versions: Array[int] = []
	for raw_profile in PROFILES:
		var profile: Dictionary = raw_profile
		if String(profile["profile_id"]) == profile_id:
			versions.append(int(profile["version"]))
	versions.sort()
	return versions


## ¿Este perfil puede producir configuracion efectiva para una abertura?
##
## Un perfil BLOQUEADO nunca, por definicion. Uno sin parametros tampoco: no
## hay nada que congelar.
static func can_produce_configuration(profile: Dictionary) -> bool:
	if profile.is_empty():
		return false
	if String(profile.get("evidence", "")) == EVIDENCE_BLOCKED:
		return false
	return not Dictionary(profile.get("parameters", {})).is_empty()


## Perfiles que hoy podrian encenderse en un escenario de producto. Es
## deliberadamente vacia: D4B1 no activa nada.
static func product_ready_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_profile in PROFILES:
		var profile: Dictionary = raw_profile
		if not bool(profile.get("product_activation", false)):
			continue
		ids.append(versioned_id(String(profile["profile_id"]), int(profile["version"])))
	return ids


# ------------------------------------------------------------
# Integridad del propio catalogo
# ------------------------------------------------------------

## Comprueba el catalogo contra su propio contrato. Devuelve los errores.
##
## Esto no valida la ciencia -eso lo hace la revision bibliografica-, valida que
## ningun perfil pueda entrar al catalogo sin declarar de donde sale, con que
## unidades y dentro de que dominio.
static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for index in range(PROFILES.size()):
		if typeof(PROFILES[index]) != TYPE_DICTIONARY:
			errors.append("profile[%d] debe ser un diccionario" % index)
			continue
		var profile: Dictionary = PROFILES[index]
		var label: String = "profile[%d]" % index
		for key in ["profile_id", "version", "category", "evidence", "product_activation",
				"title", "applies_to", "parameters", "units", "domain", "references",
				"transform", "uncertainty", "warnings"]:
			if not profile.has(key):
				errors.append("%s no declara '%s'" % [label, key])
		if not errors.is_empty() and not profile.has("profile_id"):
			continue
		var profile_id: String = String(profile.get("profile_id", ""))
		label = "profile '%s'" % profile_id
		if profile_id.strip_edges().is_empty():
			errors.append("%s tiene un profile_id vacio" % label)
		if typeof(profile.get("version", null)) != TYPE_INT or int(profile["version"]) < 1:
			errors.append("%s debe declarar una version entera >= 1" % label)
		var key_id: String = versioned_id(profile_id, int(profile.get("version", 0)))
		if seen.has(key_id):
			errors.append("%s esta duplicado" % key_id)
		seen[key_id] = true
		if not CATEGORIES.has(String(profile.get("category", ""))):
			errors.append("%s tiene una categoria desconocida" % label)
		var evidence: String = String(profile.get("evidence", ""))
		if not EVIDENCE_STATES.has(evidence):
			errors.append("%s tiene un estado de evidencia desconocido" % label)
		if typeof(profile.get("product_activation", null)) != TYPE_BOOL:
			errors.append("%s debe declarar product_activation como booleano" % label)
		# Un estado debil no puede pedir producto. La comprobacion va en este
		# sentido y no en el contrario: un perfil solido puede seguir sin ser
		# apto para producto porque su dominio no cubra una vivienda.
		if bool(profile.get("product_activation", false)) \
				and not PRODUCT_CAPABLE_STATES.has(evidence):
			errors.append("%s pide activacion de producto con evidencia '%s'" % [label, evidence])
		_validate_parameters(profile, label, errors)
		_validate_references(profile, label, errors)
		for key in ["transform", "uncertainty"]:
			if String(profile.get(key, "")).strip_edges().is_empty():
				errors.append("%s deja '%s' vacio" % [label, key])
		if typeof(profile.get("warnings", null)) != TYPE_ARRAY:
			errors.append("%s debe declarar warnings como array" % label)
		elif Array(profile["warnings"]).is_empty() and evidence != EVIDENCE_VALIDATED:
			errors.append("%s no declara ninguna advertencia pese a no estar validado" % label)
	return errors


static func _validate_parameters(profile: Dictionary, label: String, errors: Array[String]) -> void:
	if typeof(profile.get("parameters", null)) != TYPE_DICTIONARY:
		errors.append("%s debe declarar parameters como diccionario" % label)
		return
	if typeof(profile.get("units", null)) != TYPE_DICTIONARY:
		errors.append("%s debe declarar units como diccionario" % label)
		return
	if typeof(profile.get("domain", null)) != TYPE_DICTIONARY:
		errors.append("%s debe declarar domain como diccionario" % label)
		return
	var parameters: Dictionary = profile["parameters"]
	var units: Dictionary = profile["units"]
	var evidence: String = String(profile.get("evidence", ""))
	# Un perfil BLOQUEADO no puede traer parametros: si los trajera, alguien
	# acabaria usandolos.
	if evidence == EVIDENCE_BLOCKED and not parameters.is_empty():
		errors.append("%s esta bloqueado y aun asi declara parametros" % label)
	# Y al reves: un perfil que se presenta como medido o derivado TIENE que
	# afirmar algo. Sin parametros no hay nada que reproducir ni que refutar, y
	# la etiqueta seria pura apariencia de calibracion.
	if PRODUCT_CAPABLE_STATES.has(evidence) and parameters.is_empty():
		errors.append("%s se declara '%s' sin ningun parametro" % [label, evidence])
	for key in parameters.keys():
		if not units.has(key):
			errors.append("%s no declara la unidad de '%s'" % [label, String(key)])
		elif String(units[key]).strip_edges().is_empty():
			errors.append("%s deja vacia la unidad de '%s'" % [label, String(key)])
	for key in units.keys():
		if not parameters.has(key):
			errors.append("%s declara la unidad de '%s' sin el parametro" % [label, String(key)])
	if not parameters.is_empty() and Dictionary(profile["domain"]).is_empty():
		errors.append("%s tiene parametros sin declarar dominio" % label)


static func _validate_references(profile: Dictionary, label: String, errors: Array[String]) -> void:
	if typeof(profile.get("references", null)) != TYPE_ARRAY:
		errors.append("%s debe declarar references como array" % label)
		return
	var references: Array = profile["references"]
	var evidence: String = String(profile.get("evidence", ""))
	# La fuente es obligatoria SIEMPRE: incluso un perfil bloqueado tiene que
	# decir de donde sale la constancia de que no hay dato.
	if references.is_empty():
		errors.append("%s no declara ninguna referencia" % label)
		return
	if PRODUCT_CAPABLE_STATES.has(evidence) and references.is_empty():
		errors.append("%s con evidencia '%s' exige al menos una referencia" % [label, evidence])
	for index in range(references.size()):
		if typeof(references[index]) != TYPE_DICTIONARY:
			errors.append("%s tiene una referencia que no es un diccionario" % label)
			continue
		var reference: Dictionary = references[index]
		for key in ["source", "locator", "local_path"]:
			if String(reference.get(key, "")).strip_edges().is_empty():
				errors.append("%s deja '%s' vacio en una referencia" % [label, key])
