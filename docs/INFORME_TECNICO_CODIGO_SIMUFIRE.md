# Informe tecnico del codigo de Simufire

Generado el 25/04/2026. Repositorio: `C:\Users\dangp\Documents\GitHub\simufire`.

Alcance: scripts activos `.gd`, `.py`, `.ps1`, escena/configuracion Godot, templates, casos JSON y baselines. Se excluyen caches `.godot`, graficas generadas, reportes temporales, logs y salidas CFAST generadas. `sim/core/SimulationEngine.gd.bak` es backup historico no cargado por la escena activa.

## Resumen ejecutivo

Simufire es un simulador 2D de incendio compartimentado construido en Godot 4.6. No es un CFD: no resuelve Navier-Stokes ni malla espacial fina. Es un modelo reducido de zonas y balances globales que intenta capturar tendencias utiles para entrenamiento: crecimiento del HRR, agotamiento de oxigeno, estratificacion termica, movimiento de humo, CO/CO2, supervivencia y efecto de puertas/ventanas.

Cada habitacion se representa como un volumen con dos capas termicas aproximadas: capa alta caliente y capa baja respirable. Encima de eso se lleva masa de humo, O2, CO, CO2, combustible restante, energia de capa alta y variables de tenabilidad. Las aperturas conectan habitaciones entre si o con el exterior.

El programa se divide en modelos de datos, un motor coordinador y sistemas fisicos especializados. SimulationEngine.gd manda el orden de calculo, mientras CombustionSystem, OxygenExchangeSystem, ThermalSystem, GasExchangeSystem, SmokeModel, FireSpreadSystem y GlassFailureSystem hacen cada bloque de fisica.

La interfaz no calcula fisica. HUD solo muestra controles y estado, y Visualizer dibuja una planta 2D con capas, HRR, gases y etiquetas. La validacion headless se apoya en CaseRunner y casos JSON con baselines reproducibles.

## Mapa de arquitectura

El flujo principal es: Main.gd carga la escena, enlaza BuildingModel, SimulationEngine, HUD y Visualizer; BuildingModel construye salas y aperturas desde templates; SimulationEngine avanza la simulacion; SimulationStateBuilder empaqueta el estado; HUD, Visualizer, log y validacion consumen ese estado.

Orden de un paso: 1) combustion y produccion de humo/gases, 2) consumo e intercambio de oxigeno, 3) balance termico y capas, 4) rotura de vidrio opcional, 5) transporte de humo/CO/CO2 y presion, 6) calentamiento de combustibles pasivos, 7) propagacion opcional, 8) clamps, logs y finalizacion.

Este orden es un compromiso numerico sencillo: la combustion usa la atmosfera del paso anterior y produce demanda; oxigeno/ventilacion actualizan disponibilidad de aire; termica recalcula capas; transporte de gases mueve el resultado hacia otras estancias.

## Unidades y convenciones

Las unidades dominantes son metros, m2, m3, segundos, kg, kW, MJ, grados Celsius, Pascales, fraccion de O2 alrededor de 0.209, y ppm para CO/CO2 en salidas.

OUTSIDE_ID = -1 identifica el exterior. Una OpeningModel con b = -1 es puerta o ventana exterior. Las habitaciones tienen ids enteros y se guardan en diccionarios por id.

Las capas se expresan como altura desde el suelo: h_layer_m para humo visible, thermal_layer_m para capa caliente efectiva y layer_150c_m para la isoterma de 150 C. Si la altura baja, la condicion empeora porque la capa caliente/humo desciende hacia zona respirable.

## Modelo de datos

RoomModel concentra la memoria fisica de cada habitacion: geometria, temperatura alta/baja, oxigeno, humo, CO, CO2, FED/SVV, combustible, fuego activo, HRR, sobrepresion y exposicion a propagacion. reset_dynamic_state devuelve todo a ambiente.

OpeningModel describe cada puerta o ventana: sala A, sala B o exterior, tipo, anchura, altura, alfeizar, fraccion abierta y lado de pared para dibujo. Sus metodos solo interpretan estado.

FuelObjectModel permite tratar combustible por objetos aunque muchas salas usan un proxy legado de combustible de sala completa. Sus estados son COLD, HEATING, PYROLYZING, FLAMING, DECAYING y BURNED_OUT.

FireModel guarda parametros sencillos de incendio, sobre todo crecimiento t-cuadrado: HRR = alpha * t^2 limitado por max_hrr_kw.

## Guia de variables principales

En RoomModel, id/name/kind identifican la sala; width_m/length_m/height_m definen geometria; temp_upper_c/temp_lower_c son temperaturas de capa alta y baja; thermal_layer_m, upper_gas_kg, upper_energy_kj y layer_150c_m sostienen el modelo termico; o2, smoke_kg, smoke_prod_kg_s, h_layer_m, co_kg, co_upper_kg, co2_kg y overpressure_pa describen atmosfera, gases y presion.

Tambien en RoomModel, fuel_energy_MJ, max_hrr_kw y fuel_objects representan combustible; fire, fire_time_s, hrr_kw, hrr_target_kw, fire_dormant_time_s, fire_low_hrr_time_s y fire_o2_extinguished describen evolucion del incendio; o2_hrr_factor suaviza la limitacion por oxigeno; retained_unburned_MJ almacena gases combustibles no quemados; ventilation_response_factor mide respuesta a nueva ventilacion; flashover_triggered y fire_spread_exposure_s guardan eventos criticos.

En OpeningModel, a y b son habitaciones conectadas, con b = -1 como exterior; type distingue puerta/ventana; width_m, height_m y sill_m dan geometria vertical; open_fraction es la apertura efectiva 0..1; wall_side ayuda al dibujo de ventanas exteriores; spill_coeff modula derrame de humo por el hueco.

En FuelObjectModel, state indica frio/calendando/pirolizando/en llama/decaimiento/agotado; remaining_energy_MJ es energia disponible; max_hrr_kw limita potencia; surface_temp_c y received_flux_kw_m2 acumulan calentamiento; ignition_temp_c, pyrolysis_temp_c y ignition_flux_kw_m2 son umbrales; smoke_yield_kg_per_MJ, co_yield_kg_per_MJ y co2_yield_kg_per_MJ controlan productos.

En SimulationEngine, los exports se agrupan por comportamiento: time_scale y auto_finish_on_extinction controlan ejecucion; glass_* controla rotura de ventanas; fire_* controla crecimiento, O2, yields, latencia, gases no quemados, respuesta a ventilacion, backdraft y extincion; fire_remote_vent_path_* controla la ventilacion por rutas interiores; fire_spread_* controla propagacion; flashover_* controla umbrales de flashover; parametros thermal/smoke/gas/o2/log calibran termica, transporte, capas y salidas.

En Visualizer, los exports no son fisica: son colores, grosores, toggles de dibujo, tamano de etiquetas, limites para seleccionar densidad visual y conversion metros-pixeles. Cambiarlos altera la lectura visual, no la simulacion.

## Calculos y formulas clave

Crecimiento base del fuego: FireModel usa HRR_ideal = min(alpha * t^2, max_hrr_kw). CombustionSystem despues multiplica/limita ese valor por combustible restante, realimentacion termica, oxigeno, subventilacion, smolder y ventilacion.

Oxigeno: el factor de llama normaliza o2 entre fire_o2_min_for_flame y fire_o2_nominal. El consumo usa kg_O2 = HRR_MW * fire_o2_consumption_kg_per_MJ * dt. El codigo usa 0.076 kg/MJ, equivalente aproximado de Thornton.

Humo: la produccion base es smoke_kg_s = HRR_MW * smoke_yield_kg_per_MJ, con multiplicadores por combustion pobre, smolder y gases retenidos. La altura de capa se estima como H - volumen_humo/area, donde volumen_humo = smoke_kg / smoke_density corregido por expansion termica.

Ventilacion por ventana local: el limite tipo Kawagoe se estima con hrr_max = kawagoe_coeff * sum(area_abierta * sqrt(altura)). No predice toda la dinamica, pero impone un techo de potencia cuando el fuego esta limitado por ventilacion exterior directa.

Ventilacion remota: _outside_open_path_factor_for_room hace una busqueda por puertas abiertas hasta el exterior. Cada tramo se atenuta por fraccion de puerta, area relativa y fire_remote_vent_path_decay_per_door. El mayor camino encontrado se usa como senal de ventilacion disponible.

Flujos por orificio: entradas/salidas por huecos usan la forma q = Cd * A * sqrt(2 * dp / rho), con dp derivado de presion, flotabilidad o deficit. Es una correlacion simplificada de flujo, no una resolucion CFD.

Presion de capa caliente: GasExchangeSystem estima dp_buoyancy = rho_ext * g * h_smoke * max(0, 1 - T_ext/T_upper), relajado en el tiempo. Si supera pressure_vent_threshold_pa, purga humo/gases por fugas y huecos.

Intercambio termico interior: ThermalSystem calcula flujo convectivo aproximado por puertas con area efectiva y raiz de g*h*DeltaT/T. La masa caliente transportada mueve tambien energia de capa alta y afecta a la sala fria.

Suavizado temporal: muchos estados usan blend = 1 - exp(-dt/tau). Esto evita saltos cuando cambia O2, ventilacion o HRR objetivo, y hace que la respuesta sea estable en tiempo real.

Tenabilidad: FED suma dosis por CO, hiper-ventilacion por CO2 y deficit de O2. SVV toma el peor caso entre criterio FED y criterio termico por altura de la isoterma 150 C.

## Algoritmo de combustion

CombustionSystem.step_room_fire es el nucleo mas importante. Calcula un HRR ideal por curva t-cuadrado, lo limita por combustible restante y capacidad maxima, y luego lo modula por oxigeno, temperatura, humo, ventilacion y estado latente.

El factor de oxigeno se calcula normalizando O2 entre fire_o2_min_for_flame y fire_o2_nominal. Ese factor se suaviza con constantes de subida/bajada para evitar oscilaciones bruscas.

Cuando hay poco O2 o mucho humo caliente, el sistema reduce llama visible pero mantiene pirolisis/smolder si la sala esta caliente y queda combustible. Parte de la energia potencial pasa a retained_unburned_MJ, una reserva de gases combustibles no quemados.

Al abrir una ventana local o existir una ruta de ventilacion remota, ventilation_response_factor sube. Esa respuesta permite quemar parte de la reserva no quemada, aumenta HRR y puede simular reactivacion/backdraft suave si hay gases, temperatura y O2 bajo.

La produccion de humo parte de kg/MJ y aumenta con mala calidad de combustion. La produccion de CO sube cuando baja la calidad de combustion; CO2 baja cuando falta O2. Es una correlacion empirica para tendencias, no quimica detallada.

## Ventilacion remota y problema R0/R2

El problema observado era que una ventana abierta en una sala distinta de R0 podia no sostener el incendio de R0. El codigo actual incorpora fire_remote_vent_path_enabled y _outside_open_path_factor_for_room para resolverlo.

El algoritmo busca desde una sala hasta cualquier apertura exterior abierta siguiendo puertas interiores abiertas. Cada puerta reduce la senal por fire_remote_vent_path_decay_per_door, por su fraccion abierta y por un factor de area. El resultado 0..1 representa un camino de intercambio con el exterior aunque no sea una ventana de la misma sala.

Esa senal se pasa a combustion, oxigeno, termica, gases y estado publico. Por eso una ventana abierta en R2 puede aportar entrada/salida de gases hacia R0 a traves de puertas abiertas, con atenuacion sencilla. Evita el fallo no realista de apagar el incendio por ignorar ventilacion remota.

## Oxigeno

OxygenExchangeSystem conserva la idea de balance de masa de aire. Primero descuenta O2 consumido por HRR usando fire_o2_consumption_kg_per_MJ, derivado de la regla de Thornton. Despues repone/intercambia O2 por infiltracion, exterior e interiores.

Para aperturas exteriores usa un esquema de orificio: area efectiva, densidad, presion/deficit y velocidad aproximada sqrt(2*dp/rho). Da mas importancia a la parte baja disponible bajo la capa caliente, porque es donde entra aire fresco.

Para puertas interiores mezcla de fondo y flujo activo. La mezcla de fondo depende del area abierta, presion y ruta exterior. El flujo activo mueve una parcela caliente hacia la sala fria y una compensacion fria al contrario. Puede incluir retraso por distancia y velocidad de transporte.

## Termica y estratificacion

ThermalSystem mantiene energia en capa alta (upper_energy_kj) y masa de gas alta (upper_gas_kg). Captura una fraccion del HRR en la capa superior, calcula perdidas a capa baja, ambiente y paredes, y recalcula alturas de capa.

La densidad del gas se estima como 1.2 kg/m3 escalada por temperatura absoluta. La altura de capa caliente no es una frontera CFD; se estima desde energia, masa, humo, O2 y parametros de retencion.

Entre salas, build_interior_opening_flow_state decide cual esta mas caliente, calcula engagement por capas/dintel, y luego se usa una correlacion de flujo por flotabilidad: area efectiva por raiz de g*h*DeltaT/T. Ese flujo mueve masa y energia.

La temperatura a una altura se interpola entre capa baja y alta con una banda de gradiente y una banda fria junto al suelo. De ahi salen temp_at_0_9m_c, temp_at_1_8m_c y layer_150c_m.

step_fed integra exposicion toxica por CO, hiper-ventilacion por CO2 y deficit de O2. SVV se calcula como el peor caso entre criterio termico por isoterma 150 C y criterio FED.

## Humo, gases y presion

SmokeModel convierte produccion de humo en masa acumulada y estima altura de capa por volumen equivalente: masa / densidad, corregido por expansion termica. Si la capa baja por debajo del dintel de una apertura, puede derramar humo.

GasExchangeSystem aplica los deltas: generacion, venting exterior, transferencias interiores, purga por ACH, deposicion post-incendio y purga de CO/CO2 con aperturas exteriores. Tambien mueve parte de la energia y masa de capa alta cuando viaja humo caliente.

La sobrepresion se estima por flotabilidad de la capa caliente: rho*g*h*(1 - T_ext/T_upper), relajada en el tiempo. Si supera pressure_vent_threshold_pa, se purga por fugas y aperturas exteriores con una ley de orificio.

El sistema distingue entre co_kg total y co_upper_kg en capa alta. Esto permite que transferencias superiores y purgas por ventana tengan sesgo hacia gases de la capa caliente.

## Propagacion, vidrio y combustible pasivo

GlassFailureSystem asigna a cada ventana exterior un umbral de rotura con dispersion. Al superarse, aumenta open_fraction progresivamente hasta un maximo.

FireSpreadSystem esta desactivado por defecto en varios casos de validacion. Cuando se activa, solo propaga por puertas interiores abiertas si la fuente tiene HRR suficiente y la sala objetivo esta caliente, con humo bajo o combustible pasivo pre-calentado.

update_passive_room_fuel estima calentamiento superficial por radiacion/conveccion desde la capa caliente y por puertas. Sirve para transicionar objetos pasivos a HEATING/PYROLYZING y preparar autoignicion si se habilita.

## Validacion y reproducibilidad

CaseRunner permite ejecutar Godot en modo headless con --validation-case. Carga un caso JSON, aplica overrides de habitaciones/aperturas/motor, ejecuta pasos fijos, calcula metricas y compara contra baseline.

Los casos living_room_hallway, layer150_tenability y postfire_decay forman la bateria principal. tmp_r2_window_open_start cubre especificamente la ventilacion exterior remota abierta desde R2.

Las baselines no son verdad fisica absoluta; son contratos de regresion. Si se cambia el modelo, puede ser correcto actualizar una baseline, pero conviene justificarlo.

## Interfaz y visualizacion

HUD muestra tiempo, play/pause, escala temporal, boton de parar y generar graficas, selector de puertas/ventanas y un panel opcional de sala. No toca formulas fisicas.

Visualizer dibuja la planta desde los rectangulos de BuildingModel. Usa el estado publico para colorear calor, humo, capa caliente, isoterma 150 C, HRR, estado de ventanas y etiquetas de gases/tenabilidad.

La mini-seccion lateral representa alturas verticales de humo/capa caliente/isoterma dentro de cada sala, mientras la planta ofrece contexto espacial.

## Limitaciones importantes

El modelo usa muchas correlaciones empiricas y parametros calibrables. Puede representar tendencias plausibles, pero no debe interpretarse como prediccion pericial exacta de un incendio real.

La mezcla entre salas y el intercambio por ventanas son reducciones 0D/2-zonas; no hay chorros, turbulencia, geometria 3D real ni flujos transitorios complejos.

La pirolisis remota de materiales en salas sin llama existe parcialmente por combustible pasivo, pero la propagacion y autoignicion estan controladas por toggles y umbrales. El siguiente frente para realismo multiestancia seria enriquecer objetos combustibles por sala y activar/calibrar propagacion pasiva.

## Inventario de archivos activos

| Archivo | Tipo | Lineas |
| --- | --- | --- |
| Main.gd | .gd | 151 |
| project.godot | .godot | 26 |
| main.tscn | .tscn | 270 |
| sim/BuildingModel.gd | .gd | 350 |
| sim/building/RoomModel.gd | .gd | 120 |
| sim/building/OpeningModel.gd | .gd | 68 |
| sim/fire/FireModel.gd | .gd | 43 |
| sim/fire/FuelObjectModel.gd | .gd | 91 |
| sim/fire/CombustionSystem.gd | .gd | 904 |
| sim/smoke/SmokeModel.gd | .gd | 487 |
| sim/core/SimulationEngine.gd | .gd | 1244 |
| sim/core/OxygenExchangeSystem.gd | .gd | 526 |
| sim/core/ThermalSystem.gd | .gd | 1109 |
| sim/core/GasExchangeSystem.gd | .gd | 803 |
| sim/core/FireSpreadSystem.gd | .gd | 121 |
| sim/core/GlassFailureSystem.gd | .gd | 81 |
| sim/core/SimulationStateBuilder.gd | .gd | 149 |
| sim/core/SimulationLogWriter.gd | .gd | 250 |
| sim/templates/BuildingTemplate.gd | .gd | 555 |
| sim/templates/ApartmentTemplates.gd | .gd | 24 |
| sim/resources/default_fire_model.tres | .tres | 7 |
| sim/validation/CaseRunner.gd | .gd | 715 |
| sim/validation/run_case.ps1 | .ps1 | 111 |
| sim/validation/run_all_cases.ps1 | .ps1 | 85 |
| ui/hud.gd | .gd | 303 |
| view/Visualizer.gd | .gd | 1104 |
| scripts/generate_fire_graphs.py | .py | 486 |
| scripts/download_fire_literature.ps1 | .ps1 | 335 |
| scripts/simulation/run_ghanekar_sweep.ps1 | .ps1 | 320 |
| scripts/simulation/run_ghanekar_micro_calibration.ps1 | .ps1 | 364 |

## Explicacion por script

### Main.gd

Orquestador de la escena Godot.

- Conecta BuildingModel, SimulationEngine, HUD y Visualizer.
- En cada physics frame llama a engine.step(delta) si procede y propaga estado a UI.
- Gestiona escala temporal y botones de reproduccion/graficas.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 19 | @onready var building: BuildingModel = $World/BuildingModel |
| 20 | @onready var engine: SimulationEngine = $World/SimulationEngine |
| 21 | @onready var hud: HUD = $UI/HUD |
| 22 | @onready var visualizer: Visualizer = $World/Visualizer |
| 24 | const TIME_SCALE_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0] |
| 26 | var _simulation_paused: bool = false |
| 27 | var _validation_mode: bool = false |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 30 | func _ready() -> void: | Inicializa referencias, detecta modo validacion, conecta senales del HUD y sincroniza el estado inicial. |
| 59 | func _physics_process(delta: float) -> void: | Avanza la simulacion cuando no esta pausada y actualiza visualizador e interfaz cada frame fisico. |
| 70 | func _apply_state_to_ui(state: Dictionary) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 77 | func _build_ui_state() -> Dictionary: | Toma el estado publico del motor y le anade datos de reproduccion para el HUD. |
| 89 | func _on_play_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 96 | func _on_pause_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 103 | func _on_slower_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 110 | func _on_faster_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 117 | func _on_stop_and_generate_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 125 | func _find_time_scale_step_index(current_scale: float) -> int: | Funcion auxiliar relacionada con: find time scale step index. |
| 138 | func _set_time_scale_by_step(step_index: int) -> void: | Asigna o sincroniza time scale by step respetando validaciones locales. |
| 146 | func _is_validation_mode() -> bool: | Predicado booleano que decide si se cumple la condicion: is validation mode. |

### project.godot

Configuracion del proyecto Godot.

- Declara nombre simufire, escena principal, Godot 4.6 y renderer.
- No contiene logica fisica.

### main.tscn

Escena principal.

- Define Main, World, Visualizer, Camera2D, BuildingModel, SimulationEngine, UI/HUD y CaseRunner.
- Tambien define paneles y botones usados por HUD.

### sim/BuildingModel.gd

Modelo estructural del edificio.

- Carga templates y construye RoomModel, OpeningModel y FuelObjectModel.
- Proporciona consultas de vecinos, aperturas, areas efectivas y HRR por ventilacion.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name BuildingModel |
| 4 | const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd") |
| 22 | const OUTSIDE_ID: int = -1 |
| 25 | @export var outside_temp_c: float = 20.0 |
| 26 | @export var outside_o2: float = 0.209 |
| 29 | @export var vent_hrr_coeff_kw_per_sqrt_m5: float = 1500.0 |
| 32 | var building_template = preload("res://sim/templates/BuildingTemplate.gd").new() |
| 34 | @export_enum("simple_house", "ghanekar_bedroom_hallway") var template_name: String = "simple_house" |
| 37 | var room_rect_m: Dictionary[int, Rect2] = {} |
| 38 | var rooms: Dictionary = {} |
| 39 | var openings: Array = [] |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 45 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 56 | func get_room_rects_m() -> Dictionary[int, Rect2]: | Devuelve room rects m calculado o almacenado. |
| 60 | func get_room_centroid_m(room_id: int) -> Vector2: | Devuelve room centroid m calculado o almacenado. |
| 65 | func estimate_room_connection_length_m(room_a_id: int, room_b_id: int) -> float: | Estima room connection length m mediante una correlacion simplificada. |
| 71 | func get_room(room_id: int) -> RoomModel: | Devuelve room calculado o almacenado. |
| 74 | func get_rooms() -> Dictionary: | Devuelve rooms calculado o almacenado. |
| 77 | func get_openings() -> Array: | Devuelve openings calculado o almacenado. |
| 80 | func load_template_data(data: Dictionary) -> void: | Carga datos externos o de plantilla en objetos del programa. |
| 87 | func _load_from_template(data: Dictionary) -> void: | Carga datos externos o de plantilla en objetos del programa. |
| 146 | func _add_room_from_rect( | Funcion auxiliar relacionada con: add room from rect. |
| 167 | func _build_fuel_objects(raw_objects: Variant) -> Array: | Construye una estructura de datos auxiliar: fuel objects. |
| 201 | func has_outside_opening(room_id: int) -> bool: | Predicado booleano que decide si se cumple la condicion: has outside opening. |
| 216 | func estimate_vent_hrr_kw(room_id: int) -> float: | Estima vent hrr kw mediante una correlacion simplificada. |
| 242 | func get_connected_openings(room_id: int) -> Array: | Devuelve connected openings calculado o almacenado. |
| 251 | func get_neighbor_room_ids(room_id: int) -> Array[int]: | Devuelve neighbor room ids calculado o almacenado. |
| 266 | func get_opening_count() -> int: | Devuelve opening count calculado o almacenado. |
| 270 | func get_opening_at(index: int): | Devuelve opening at calculado o almacenado. |
| 276 | func set_opening_fraction(index: int, open_fraction: float) -> bool: | Asigna o sincroniza opening fraction respetando validaciones locales. |
| 285 | func open_opening(index: int) -> bool: | Cambia el estado de una apertura del edificio. |
| 289 | func close_opening(index: int) -> bool: | Cambia el estado de una apertura del edificio. |
| 293 | func get_opening_label(index: int) -> String: | Devuelve opening label calculado o almacenado. |
| 307 | func get_opening_status_text(index: int) -> String: | Devuelve opening status text calculado o almacenado. |
| 320 | func build_opening_summaries() -> Array[Dictionary]: | Construye una estructura de datos auxiliar: opening summaries. |
| 340 | func _get_room_display_name(room_id: int) -> String: | Devuelve room display name calculado o almacenado. |

### sim/building/RoomModel.gd

Estado fisico de una habitacion.

- Agrupa geometria, atmosfera, capas, especies, tenabilidad, combustible y fuego.
- Solo calcula area, volumen y reset; la fisica vive fuera.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name RoomModel |
| 4 | const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd") |
| 17 | var id: int = -1 |
| 18 | var name: String = "" |
| 19 | var kind: String = "" |
| 22 | var width_m: float = 0.0 |
| 23 | var length_m: float = 0.0 |
| 24 | var height_m: float = 2.5 |
| 27 | var temp_upper_c: float = 20.0 |
| 28 | var temp_lower_c: float = 20.0 |
| 31 | var o2: float = 0.209 |
| 34 | var smoke_kg: float = 0.0 |
| 35 | var smoke_prod_kg_s: float = 0.0 |
| 36 | var h_layer_m: float = 2.5 |
| 39 | var thermal_layer_m: float = 2.5 |
| 40 | var upper_gas_kg: float = 0.0 |
| 41 | var upper_energy_kj: float = 0.0 |
| 42 | var layer_150c_m: float = 2.5 |
| 45 | var co_kg: float = 0.0 |
| 46 | var co_upper_kg: float = 0.0 |
| 49 | var co2_kg: float = 0.0 |
| 52 | var fed: float = 0.0 |
| 55 | var svv_pct: float = 100.0 |
| 56 | var svv_worst_pct: float = 100.0 |
| 59 | var fuel_energy_MJ: float = 0.0 |
| 60 | var max_hrr_kw: float = 0.0 |
| 61 | var fuel_objects: Array = [] |
| 64 | var fire: FireModel = null |
| 65 | var fire_time_s: float = 0.0 |
| 66 | var hrr_kw: float = 0.0 |
| 67 | var hrr_target_kw: float = 0.0 |
| 68 | var fire_dormant_time_s: float = 0.0 |
| 69 | var fire_low_hrr_time_s: float = 0.0 |
| 70 | var fire_o2_extinguished: bool = false |
| 71 | var o2_hrr_factor: float = 1.0 |
| 72 | var retained_unburned_MJ: float = 0.0 |
| 73 | var ventilation_response_factor: float = 0.0 |
| 76 | var overpressure_pa: float = 0.0 |
| 79 | var flashover_triggered: bool = false |
| 80 | var fire_spread_exposure_s: float = 0.0 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 83 | func floor_area_m2() -> float: | Funcion auxiliar relacionada con: floor area m2. |
| 87 | func volume_m3() -> float: | Funcion auxiliar relacionada con: volume m3. |
| 91 | func reset_dynamic_state(ambient_temp_c: float, ambient_o2: float) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |

### sim/building/OpeningModel.gd

Puerta o ventana.

- Guarda conexion, tipo, dimensiones, fraccion abierta y geometria de dibujo.
- Calcula dintel, exterior/cerrada/abierta y etiqueta.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name OpeningModel |
| 4 | enum Type { DOOR, WINDOW } |
| 6 | const EPSILON: float = 0.001 |
| 7 | const WINDOW_FULL_OPEN_THRESHOLD: float = 0.5 |
| 9 | var a: int            # room id |
| 10 | var b: int            # room id, o -1 = exterior |
| 11 | var type: int = Type.DOOR |
| 13 | var width_m: float = 0.9 |
| 14 | var height_m: float = 2.0 |
| 15 | var sill_m: float = 0.0           # para ventanas (altura del alféizar) |
| 16 | var open_fraction: float = 1.0    # 0..1 |
| 17 | var opening_index: int = -1 |
| 18 | var wall_side: String = "" |
| 21 | var spill_coeff: float = 0.65 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 24 | func _init(_a: int, _b: int, _type: int, _w: float, _h: float, _open: float = 1.0, _sill: float = 0.0) -> void: | Funcion auxiliar relacionada con: init. |
| 34 | func set_open_fraction(value: float) -> void: | Asigna o sincroniza open fraction respetando validaciones locales. |
| 38 | func lintel_height_m() -> float: | Funcion auxiliar relacionada con: lintel height m. |
| 42 | func is_exterior_opening() -> bool: | Predicado booleano que decide si se cumple la condicion: is exterior opening. |
| 46 | func is_closed() -> bool: | Predicado booleano que decide si se cumple la condicion: is closed. |
| 50 | func is_fully_open() -> bool: | Predicado booleano que decide si se cumple la condicion: is fully open. |
| 56 | func state_label() -> String: | Funcion auxiliar relacionada con: state label. |

### sim/fire/FireModel.gd

Parametros basicos de fuego.

- Contiene crecimiento t-cuadrado, HRR maximo, O2 minimo y yield de humo.
- compute_hrr_kw devuelve min(alpha*t^2, max_hrr_kw).

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name FireModel |
| 12 | var fuel_energy_MJ: float = 5000.0 |
| 13 | var remaining_fuel_MJ: float = 5000.0 |
| 14 | var max_burn_rate_kw: float = 2000.0 |
| 17 | var growth_alpha_kw_s2: float = 0.05 |
| 20 | var max_hrr_kw: float = 3000.0 |
| 23 | var secondary_hrr_gain_kw: float = 2500.0 |
| 26 | var flashover_hrr_multiplier: float = 2.2 |
| 27 | var flashover_min_hrr_kw: float = 300.0 |
| 30 | var o2_nominal: float = 0.209 |
| 31 | var o2_min_for_flame: float = 0.12 |
| 32 | var o2_consumption_kg_per_MJ: float = 0.20 |
| 35 | var smoke_yield_kg_per_MJ: float = 0.06 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 41 | func compute_hrr_kw(t_s: float) -> float: | Calcula hrr kw a partir del estado actual y parametros fisicos. |

### sim/fire/FuelObjectModel.gd

Combustible por objeto.

- Representa estado de ignicion, temperatura superficial, flujo recibido y energia restante.
- Puede crear un proxy legado para combustible de sala completa.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name FuelObjectModel |
| 12 | enum State { |
| 21 | var id: String = "" |
| 22 | var name: String = "" |
| 23 | var kind: String = "" |
| 26 | var footprint_m2: float = 0.0 |
| 27 | var exposed_area_m2: float = 0.0 |
| 28 | var elevation_m: float = 0.0 |
| 31 | var fuel_energy_MJ: float = 0.0 |
| 32 | var remaining_fuel_MJ: float = 0.0 |
| 33 | var max_hrr_kw: float = 0.0 |
| 34 | var ignition_temp_c: float = 320.0 |
| 35 | var ignition_flux_kw_m2: float = 18.0 |
| 38 | var smoke_yield_kg_per_MJ: float = 0.00375 |
| 39 | var co_yield_kg_per_MJ: float = 0.00025 |
| 40 | var o2_consumption_kg_per_MJ: float = 0.076 |
| 43 | var state: int = State.COLD |
| 44 | var surface_temp_c: float = 20.0 |
| 45 | var incident_heat_flux_kw_m2: float = 0.0 |
| 46 | var exposure_s: float = 0.0 |
| 47 | var hrr_kw: float = 0.0 |
| 48 | var autoignite_ready: bool = false |
| 49 | var ignited_by_object_id: String = "" |
| 50 | var is_primary_ignition_source: bool = false |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 53 | func configure_from_legacy_room(room: RoomModel) -> void: | Funcion auxiliar relacionada con: configure from legacy room. |
| 69 | func reset_dynamic_state(ambient_temp_c: float = 20.0) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 80 | func has_remaining_fuel() -> bool: | Predicado booleano que decide si se cumple la condicion: has remaining fuel. |
| 84 | func can_ignite() -> bool: | Predicado booleano que decide si se cumple la condicion: can ignite. |
| 88 | func remaining_fraction() -> float: | Funcion auxiliar relacionada con: remaining fraction. |

### sim/fire/CombustionSystem.gd

Sistema de combustion.

- Convierte combustible, O2, temperatura y ventilacion en HRR, humo, CO, CO2 y consumo de energia.
- Incluye llama, smolder, pirolisis subventilada, gases no quemados, respuesta a ventilacion, backdraft suave y extincion.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name CombustionSystem |
| 4 | const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd") |
| 5 | const FireModelScript = preload("res://sim/fire/FireModel.gd") |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 15 | func ensure_room_fuel_objects(room: RoomModel) -> void: | Funcion auxiliar relacionada con: ensure room fuel objects. |
| 33 | func bootstrap_building(building: BuildingModel) -> void: | Funcion auxiliar relacionada con: bootstrap building. |
| 42 | func create_legacy_room_fire(room: RoomModel, defaults: Dictionary) -> FireModel: | Crea una instancia o plantilla: legacy room fire. |
| 71 | func step_room_fire(room: RoomModel, dt: float, context: Dictionary) -> bool: | Nucleo de combustion: HRR, O2, pirolisis, brasas, gases no quemados, CO/CO2, humo y extincion. |
| 477 | func get_room_total_remaining_fuel_MJ(room: RoomModel) -> float: | Devuelve room total remaining fuel MJ calculado o almacenado. |
| 489 | func get_room_total_max_hrr_kw(room: RoomModel) -> float: | Devuelve room total max hrr kw calculado o almacenado. |
| 501 | func get_room_active_object_count(room: RoomModel) -> int: | Devuelve room active object count calculado o almacenado. |
| 514 | func get_room_heating_object_count(room: RoomModel) -> int: | Devuelve room heating object count calculado o almacenado. |
| 527 | func get_room_pyrolyzing_object_count(room: RoomModel) -> int: | Devuelve room pyrolyzing object count calculado o almacenado. |
| 540 | func get_room_passive_surface_temp_c(room: RoomModel) -> float: | Devuelve room passive surface temp c calculado o almacenado. |
| 545 | func get_room_passive_flux_kw_m2(room: RoomModel) -> float: | Devuelve room passive flux kw m2 calculado o almacenado. |
| 550 | func get_room_passive_ignition_flux_kw_m2(room: RoomModel) -> float: | Devuelve room passive ignition flux kw m2 calculado o almacenado. |
| 555 | func is_room_passive_autoignite_ready(room: RoomModel) -> bool: | Predicado booleano que decide si se cumple la condicion: is room passive autoignite ready. |
| 560 | func update_passive_room_fuel( | Actualiza calentamiento, flujo radiativo y estado de combustibles pasivos de una sala sin fuego activo. |
| 704 | func _resolve_room_fuel_energy_MJ(room: RoomModel, fallback_MJ: float) -> float: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 717 | func _resolve_room_max_hrr_kw(room: RoomModel, fallback_kw: float) -> float: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 730 | func _compute_o2_factor(o2: float, nominal: float, min_o2: float) -> float: | Calcula o2 factor a partir del estado actual y parametros fisicos. |
| 738 | func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float: | Calcula smoke production kg s a partir del estado actual y parametros fisicos. |
| 743 | func _smooth_state_value( | Funcion auxiliar relacionada con: smooth state value. |
| 757 | func _estimate_radiative_flux_kw_m2( | Estima radiative flux kw m2 mediante una correlacion simplificada. |
| 771 | func _celsius_to_kelvin(temp_c: float) -> float: | Funcion auxiliar relacionada con: celsius to kelvin. |
| 775 | func _can_sustain_latent_fire( | Decide si un fuego puede mantenerse latente por temperatura, combustible y reserva de gases. |
| 820 | func _extinguish_room_fire(room: RoomModel, fire: FireModel, burned_out: bool = false) -> bool: | Funcion auxiliar relacionada con: extinguish room fire. |
| 840 | func _get_legacy_room_proxy(room: RoomModel): | Devuelve legacy room proxy calculado o almacenado. |
| 856 | func _sync_legacy_proxy_idle(room: RoomModel) -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 872 | func _sync_legacy_proxy_from_fire(room: RoomModel, fire: FireModel, hrr_kw: float, can_flame: bool) -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 895 | func _mark_legacy_proxy_burned_out(room: RoomModel) -> void: | Funcion auxiliar relacionada con: mark legacy proxy burned out. |

### sim/smoke/SmokeModel.gd

Modelo de capa y derrame de humo.

- Calcula produccion, altura visible, capa efectiva de derrame y masas transferibles.
- Usa densidad, expansion por temperatura, presion, dintel y resistencia por sala objetivo.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name SmokeModel |
| 16 | var smoke_density_kg_m3: float = 0.9 |
| 17 | var smoke_temp_expansion_upper_weight: float = 0.45 |
| 18 | var smoke_temp_expansion_cap_c: float = 400.0 |
| 21 | var base_spill_kg_s_per_m2: float = 0.18 |
| 22 | var temp_push_factor: float = 0.008 |
| 23 | var max_spill_kg_s: float = 0.9 |
| 24 | var max_fraction_out_per_s: float = 0.025 |
| 25 | var target_smoke_resistance_coeff: float = 0.45 |
| 26 | var target_layer_block_start_m: float = 1.10 |
| 27 | var target_layer_block_full_m: float = 0.35 |
| 28 | var interior_spill_start_layer_m: float = 2.0 |
| 29 | var interior_spill_full_layer_m: float = 1.2 |
| 30 | var pressure_spill_min_delta_pa: float = 0.5 |
| 31 | var pressure_spill_ref_delta_pa: float = 8.0 |
| 32 | var pressure_spill_max_multiplier: float = 2.5 |
| 35 | var layer_relax_down: float = 0.10 |
| 36 | var layer_relax_up: float = 0.008 |
| 37 | var layer_recovery_gap_start_m: float = 0.20 |
| 38 | var layer_recovery_gap_full_m: float = 1.00 |
| 39 | var layer_recovery_boost_max: float = 6.0 |
| 40 | var layer_recovery_low_hrr_threshold_kw: float = 120.0 |
| 41 | var layer_recovery_low_hrr_boost: float = 1.6 |
| 44 | var spill_margin_m: float = 0.15 |
| 45 | var thermal_smoke_bridge_min_kg: float = 0.03 |
| 46 | var thermal_smoke_bridge_gap_start_m: float = 0.12 |
| 47 | var thermal_smoke_bridge_gap_full_m: float = 0.90 |
| 48 | var thermal_smoke_bridge_ref_kg_m3: float = 0.015 |
| 49 | var thermal_smoke_bridge_max_weight: float = 0.28 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 59 | func add_generated_smoke(room: RoomModel, dt: float) -> float: | Funcion auxiliar relacionada con: add generated smoke. |
| 63 | func estimate_smoke_layer_height_m(room: RoomModel) -> float: | Estima smoke layer height m mediante una correlacion simplificada. |
| 79 | func get_visible_smoke_layer_height_m(room: RoomModel) -> float: | Devuelve visible smoke layer height m calculado o almacenado. |
| 89 | func get_effective_smoke_spill_layer_height_m(room: RoomModel) -> float: | Devuelve effective smoke spill layer height m calculado o almacenado. |
| 122 | func get_spill_layer_height_m(room: RoomModel) -> float: | Devuelve spill layer height m calculado o almacenado. |
| 134 | func recompute_layer_from_mass(room: RoomModel, dt: float) -> void: | Relaja la altura visible de humo hacia la altura que corresponde a la masa acumulada. |
| 194 | func compute_outside_vented_kg( | Estima humo que sale al exterior segun capa, temperatura y presion. |
| 250 | func compute_room_transfers( | Calcula transferencias de humo por aperturas interiores cuando la capa invade el dintel. |
| 333 | func compute_room_transfer( | Calcula room transfer a partir del estado actual y parametros fisicos. |
| 368 | func _compute_opening_mass_budget_kg( | Calcula opening mass budget kg a partir del estado actual y parametros fisicos. |
| 385 | func _compute_transfer_mass_kg_continuous( | Calcula transfer mass kg continuous a partir del estado actual y parametros fisicos. |
| 440 | func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float: | Funcion auxiliar relacionada con: interior spill trigger layer m. |
| 447 | func _interior_spill_full_layer_m(room: RoomModel, trigger_layer_m: float) -> float: | Funcion auxiliar relacionada con: interior spill full layer m. |
| 454 | func _compute_pressure_spill_multiplier(source: RoomModel, target: RoomModel = null) -> float: | Calcula pressure spill multiplier a partir del estado actual y parametros fisicos. |
| 474 | func _compute_smoke_temp_expansion(room: RoomModel) -> float: | Calcula smoke temp expansion a partir del estado actual y parametros fisicos. |

### sim/core/SimulationEngine.gd

Motor coordinador y centro de parametros.

- Contiene la mayoria de parametros exportados calibrables.
- Coordina todos los subsistemas, calcula ventilacion remota, flashover, clamps y graficas.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name SimulationEngine |
| 4 | const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd") |
| 5 | const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd") |
| 6 | const OxygenExchangeSystemScript = preload("res://sim/core/OxygenExchangeSystem.gd") |
| 7 | const SimulationLogWriterScript = preload("res://sim/core/SimulationLogWriter.gd") |
| 8 | const SimulationStateBuilderScript = preload("res://sim/core/SimulationStateBuilder.gd") |
| 9 | const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd") |
| 10 | const FireSpreadSystemScript = preload("res://sim/core/FireSpreadSystem.gd") |
| 11 | const GlassFailureSystemScript = preload("res://sim/core/GlassFailureSystem.gd") |
| 25 | @export var building_path: NodePath |
| 27 | var building: BuildingModel |
| 28 | var smoke_model: SmokeModel = SmokeModel.new() |
| 29 | var combustion_system: CombustionSystem = CombustionSystemScript.new() |
| 30 | var gas_exchange_system = GasExchangeSystemScript.new() |
| 31 | var oxygen_exchange_system = OxygenExchangeSystemScript.new() |
| 32 | var log_writer = SimulationLogWriterScript.new() |
| 33 | var state_builder = SimulationStateBuilderScript.new() |
| 34 | var thermal_system = ThermalSystemScript.new() |
| 35 | var fire_spread_system = FireSpreadSystemScript.new() |
| 36 | var glass_failure_system = GlassFailureSystemScript.new() |
| 38 | const o2_consumption_kg_per_MJ: float = 0.35 |
| 39 | const o2_nominal: float = 0.209 |
| 45 | @export var time_scale: float = 5.0 |
| 46 | var sim_time_s: float = 0.0 |
| 49 | @export var extinction_grace_s: float = 30.0 |
| 50 | @export var auto_finish_on_extinction: bool = true |
| 51 | var is_finished: bool = false |
| 52 | var _extinction_countdown: float = 30.0 |
| 54 | var _prev_open_fracs: Dictionary = {} |
| 56 | var _graphs_launched: bool = false |
| 63 | @export var glass_auto_break_enabled: bool = false |
| 65 | @export var glass_break_temp_c: float = 250.0 |
| 67 | @export var glass_break_temp_spread_c: float = 80.0 |
| 69 | @export var glass_open_rate_per_s: float = 0.15 |
| 71 | @export var glass_max_open_fraction: float = 0.85 |
| 77 | var smoke_generated_total_kg: float = 0.0 |
| 78 | var smoke_vented_total_kg: float = 0.0 |
| 79 | var smoke_deposited_total_kg: float = 0.0 |
| 85 | @export var ignition_room_id: int = 0 |
| 86 | @export var auto_ignite_on_ready: bool = true |
| 92 | @export var fire_alpha_kw_s2: float = 0.12 |
| 93 | @export var fire_max_hrr_kw: float = 3000.0 |
| 94 | @export var fire_secondary_hrr_gain_kw: float = 2500.0 |
| 99 | @export var kawagoe_coeff: float = 1500.0 |
| 101 | @export var fire_o2_nominal: float = 0.209 |
| 102 | @export var fire_o2_min_for_flame: float = 0.10 |
| 103 | @export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2 |
| 106 | @export var fire_smoke_yield_kg_per_MJ: float = 0.0088 |
| 107 | @export var fire_smoke_yield_low_o2_multiplier: float = 5.0 |
| 108 | @export var fire_smoke_basis_min_fraction: float = 0.40 |
| 109 | @export var fire_smolder_hrr_fraction: float = 0.03 |
| 110 | @export var fire_smolder_smoke_multiplier: float = 2.8 |
| 111 | @export var fire_retained_smoke_fraction: float = 0.38 |
| 112 | @export var fire_pool_smoke_fraction: float = 0.42 |
| 113 | @export var fire_latent_hrr_cap_min_fraction: float = 0.08 |
| 114 | @export var fire_latent_hrr_cap_max_fraction: float = 0.35 |
| 115 | @export var fire_latent_co_yield_multiplier: float = 0.06 |
| 116 | @export var fire_retained_co_fraction: float = 0.08 |
| 117 | @export var fire_pool_co_fraction: float = 0.40 |
| 118 | @export var fire_co_low_quality_yield_multiplier: float = 8.0 |
| 119 | @export var fire_co_max_effective_fraction: float = 0.22 |
| 120 | @export var fire_subvent_o2_floor: float = 0.085 |
| 121 | @export var fire_subvent_temp_start_c: float = 140.0 |
| 122 | @export var fire_subvent_temp_full_c: float = 420.0 |
| 123 | @export var fire_subvent_fill_start_fraction: float = 0.06 |
| 124 | @export var fire_subvent_fill_full_fraction: float = 0.18 |
| 125 | @export var fire_starvation_o2_factor: float = 0.003 |
| 132 | @export var co_base_yield_kg_per_MJ: float = 0.00025 |
| 133 | @export var co_max_yield_kg_per_MJ: float = 0.01250 |
| 139 | @export var co2_base_yield_kg_per_MJ: float = 0.0831 |
| 140 | @export var co2_min_yield_kg_per_MJ: float = 0.0594 |
| 144 | @export var fire_extinction_hrr_kw: float = 8.0 |
| 145 | @export var fire_extinction_delay_s: float = 240.0 |
| 146 | @export var fire_latent_enabled: bool = true |
| 147 | @export var fire_latent_extinction_delay_s: float = 300.0 |
| 148 | @export var fire_latent_hold_upper_temp_c: float = 140.0 |
| 149 | @export var fire_latent_hold_lower_temp_c: float = 60.0 |
| 150 | @export var fire_latent_min_remaining_fuel_MJ: float = 25.0 |
| 154 | @export var fire_max_active_s: float = 1800.0 |
| 156 | @export var fire_flashover_hrr_multiplier: float = 2.2 |
| 157 | @export var fire_flashover_min_hrr_kw: float = 300.0 |
| 162 | @export var thermal_feedback_coeff: float = 0.15 |
| 163 | @export var thermal_feedback_max: float = 1.5 |
| 166 | @export var fire_o2_hrr_rise_tau_s: float = 14.0 |
| 167 | @export var fire_o2_hrr_fall_tau_s: float = 32.0 |
| 168 | @export var fire_subvent_pyrolysis_min_fraction: float = 0.08 |
| 169 | @export var fire_subvent_pyrolysis_max_fraction: float = 0.18 |
| 170 | @export var fire_unburned_generation_fraction: float = 0.30 |
| 171 | @export var fire_unburned_capacity_MJ_per_m2: float = 1.20 |
| 172 | @export var fire_unburned_decay_per_s: float = 0.0025 |
| 173 | @export var fire_vent_response_temp_start_c: float = 140.0 |
| 174 | @export var fire_vent_response_temp_full_c: float = 300.0 |
| 175 | @export var fire_vent_response_rise_tau_s: float = 10.0 |
| 176 | @export var fire_vent_response_fall_tau_s: float = 30.0 |
| 177 | @export var fire_pool_release_tau_slow_s: float = 180.0 |
| 178 | @export var fire_pool_release_tau_fast_s: float = 18.0 |
| 179 | @export var fire_pool_release_max_fraction: float = 0.18 |
| 180 | @export var fire_hrr_rise_tau_s: float = 6.0 |
| 181 | @export var fire_hrr_fall_tau_s: float = 20.0 |
| 182 | @export var fire_backdraft_pool_threshold_MJ: float = 8.0 |
| 183 | @export var fire_backdraft_o2_max: float = 0.13 |
| 184 | @export var fire_backdraft_temp_min_c: float = 180.0 |
| 185 | @export var fire_backdraft_release_boost: float = 1.35 |
| 186 | @export var fire_remote_vent_path_enabled: bool = true |
| 187 | @export var fire_remote_vent_path_decay_per_door: float = 0.60 |
| 188 | @export var fire_remote_vent_path_min_signal: float = 0.02 |
| 189 | @export var fire_remote_vent_path_max_doors: int = 4 |
| 195 | @export var fire_spread_enabled: bool = false |
| 196 | @export var fire_spread_ignition_temp_c: float = 340.0  # temperatura de la capa superior para ignición por calor |
| 197 | @export var fire_spread_max_layer_m: float = 1.6 |
| 198 | @export var fire_spread_min_smoke_kg: float = 0.08 |
| 199 | @export var fire_spread_min_source_hrr_kw: float = 180.0 |
| 200 | @export var fire_spread_required_exposure_s: float = 35.0 |
| 201 | @export var fire_spread_exposure_decay_s: float = 12.0 |
| 206 | @export var passive_room_autoignite_enabled: bool = false |
| 212 | @export var flashover_temp_c: float = 500.0 |
| 213 | @export var flashover_layer_m: float = 1.2 |
| 214 | @export var flashover_head_height_m: float = 1.8 |
| 215 | @export var flashover_head_temp_c: float = 150.0 |

Nota: hay 89 declaraciones adicionales omitidas aqui; ver apendice B.

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 348 | func _sync_auxiliary_services() -> void: | Copia parametros exportados del motor hacia los subsistemas especializados. |
| 449 | func _build_state_context() -> Dictionary: | Construye una estructura de datos auxiliar: state context. |
| 472 | func _build_gas_exchange_hooks() -> Dictionary: | Construye una estructura de datos auxiliar: gas exchange hooks. |
| 482 | func _build_oxygen_exchange_hooks() -> Dictionary: | Construye una estructura de datos auxiliar: oxygen exchange hooks. |
| 493 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 511 | func _reset_log_file() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 519 | func _resolve_building() -> void: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 526 | func _sync_smoke_model_settings() -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 550 | func reset_simulation(start_ignition_room_id: int = ignition_room_id, ignite_initial_fire: bool = true) -> void: | Reinicia habitaciones, sistemas auxiliares, logs y opcionalmente prende la habitacion inicial. |
| 580 | func _reset_room_state(room: RoomModel) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 596 | func step(delta: float) -> void: | Paso principal: fuego, oxigeno, termica, vidrio, gases, combustible pasivo, propagacion, clamps y log. |
| 644 | func ignite_room(room_id: int) -> void: | Crea/activa el FireModel de una sala y prepara su combustible para quemar. |
| 670 | func _build_fire_defaults() -> Dictionary: | Construye una estructura de datos auxiliar: fire defaults. |
| 684 | func _build_room_combustion_context(room_id: int) -> Dictionary: | Reune los parametros de combustion que necesita CombustionSystem para una sala. |
| 758 | func _step_gas_exchange(dt: float) -> void: | Funcion auxiliar relacionada con: step gas exchange. |
| 772 | func _step_passive_fuel(dt: float) -> void: | Funcion auxiliar relacionada con: step passive fuel. |
| 796 | func _build_passive_fuel_context(room_id: int) -> Dictionary: | Construye una estructura de datos auxiliar: passive fuel context. |
| 852 | func _step_fire(dt: float) -> void: | Funcion auxiliar relacionada con: step fire. |
| 873 | func _kawagoe_factor_for_room(room_id: int) -> float: | Calcula suma A*sqrt(H) de ventanas exteriores abiertas para limitar HRR por ventilacion local. |
| 895 | func _window_open_max_for_room(room_id: int) -> float: | Funcion auxiliar relacionada con: window open max for room. |
| 915 | func _outside_open_path_factor_for_room(room_id: int) -> float: | Busca por puertas interiores abiertas una ruta hasta una apertura exterior y devuelve una senal atenuada de ventilacion remota. |
| 981 | func _try_trigger_flashover(room: RoomModel) -> void: | Evalua temperatura, capas y tenabilidad para disparar flashover y aumentar HRR disponible. |
| 1025 | func _step_oxygen(dt: float) -> void: | Funcion auxiliar relacionada con: step oxygen. |
| 1035 | func debug_check_smoke_conservation() -> void: | Funcion auxiliar relacionada con: debug check smoke conservation. |
| 1062 | func _clamp_rooms() -> void: | Funcion auxiliar relacionada con: clamp rooms. |
| 1103 | func get_state() -> Dictionary: | Devuelve state calculado o almacenado. |
| 1109 | func is_ready_for_validation() -> bool: | Predicado booleano que decide si se cumple la condicion: is ready for validation. |
| 1121 | func are_graphs_launched() -> bool: | Funcion auxiliar relacionada con: are graphs launched. |
| 1125 | func stop_and_generate_graphs(details: String = "manual_stop_button") -> bool: | Funcion auxiliar relacionada con: stop and generate graphs. |
| 1139 | func _detect_and_log_opening_events() -> void: | Funcion auxiliar relacionada con: detect and log opening events. |
| 1166 | func _log_opening_event(opening_idx: int, event_type: String) -> void: | Funcion auxiliar relacionada con: log opening event. |
| 1179 | func _on_sim_finished() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 1183 | func _finish_and_launch_graphs(details: String) -> void: | Cierra una ejecucion, escribe resultados y deja el sistema terminado. |
| 1199 | func _force_log_final_snapshot() -> void: | Funcion auxiliar relacionada con: force log final snapshot. |
| 1204 | func _launch_graph_generator() -> void: | Funcion auxiliar relacionada con: launch graph generator. |
| 1221 | func _should_launch_graphs() -> bool: | Predicado booleano que decide si se cumple la condicion: should launch graphs. |
| 1232 | func _exit_tree() -> void: | Funcion auxiliar relacionada con: exit tree. |
| 1239 | func _maybe_log_state() -> void: | Funcion auxiliar relacionada con: maybe log state. |

### sim/core/OxygenExchangeSystem.gd

Balance de oxigeno.

- Consume O2 segun HRR y repone/intercambia aire por ACH, exterior e interiores.
- Usa modelos de orificio y mezcla con retraso opcional.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name OxygenExchangeSystem |
| 4 | var o2_nominal: float = 0.209 |
| 5 | var ach_infiltration: float = 0.5 |
| 6 | var interior_transport_enabled: bool = true |
| 7 | var interior_transport_speed_m_s: float = 0.20 |
| 8 | var interior_transport_min_distance_m: float = 0.50 |
| 9 | var interior_o2_transport_delay_multiplier: float = 1.0 |
| 10 | var doorway_o2_exchange_coeff: float = 1.70 |
| 11 | var doorway_o2_background_exchange_kg_s_m2: float = 0.06 |
| 12 | var doorway_o2_background_max_fraction_per_step: float = 0.015 |
| 13 | var doorway_o2_background_pressure_ref_pa: float = 1.5 |
| 14 | var doorway_o2_background_min_factor: float = 0.30 |
| 15 | var _pending_o2_deliveries: Array[Dictionary] = [] |
| 16 | var _reserved_transport_o2_delta_kg: Dictionary = {} |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 19 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 57 | func reset() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 62 | func step(building: BuildingModel, dt: float, hooks: Dictionary) -> void: | Consume O2 por HRR y aplica entrada/intercambio por aperturas exteriores e interiores. |
| 137 | func _step_outside_opening_o2( | Modelo de entrada de aire fresco por apertura exterior usando deficit de O2, capa caliente, presion y area baja. |
| 238 | func _step_interior_opening_o2( | Intercambio de O2 entre salas por puerta abierta, con mezcla de fondo y flujo activo. |
| 331 | func _exchange_room_o2_immediate( | Funcion auxiliar relacionada con: exchange room o2 immediate. |
| 361 | func _exchange_room_o2_active_flow( | Transporta una parcela caliente de una sala a otra y una compensacion fria al contrario. |
| 405 | func _release_pending_o2_deliveries(building: BuildingModel, dt: float, air_density_kg_m3: float) -> void: | Funcion auxiliar relacionada con: release pending o2 deliveries. |
| 428 | func _reserve_room_o2_delta(room_id: int, delta_o2_kg: float) -> void: | Funcion auxiliar relacionada con: reserve room o2 delta. |
| 439 | func _apply_room_o2_mass_delta(room: RoomModel, delta_o2_kg: float, air_density_kg_m3: float) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 448 | func _effective_room_o2_fraction(room: RoomModel, air_density_kg_m3: float) -> float: | Funcion auxiliar relacionada con: effective room o2 fraction. |
| 462 | func _estimate_interior_transport_delay_s(building: BuildingModel, room_a_id: int, room_b_id: int) -> float: | Estima interior transport delay s mediante una correlacion simplificada. |
| 473 | func _compute_room_air_mass_kg(room: RoomModel, air_density_kg_m3: float) -> float: | Calcula room air mass kg a partir del estado actual y parametros fisicos. |
| 479 | func _estimate_room_outside_open_factor(building: BuildingModel, room: RoomModel) -> float: | Estima room outside open factor mediante una correlacion simplificada. |
| 504 | func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 510 | func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 516 | func _call_interior_flow_state( | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |

### sim/core/ThermalSystem.gd

Balance termico y tenabilidad.

- Mantiene energia de capa alta, temperaturas, gradientes verticales, intercambio entre salas y criterio 150 C.
- Calcula FED/SVV y temperaturas a alturas de interes.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name ThermalSystem |
| 17 | var _building: BuildingModel |
| 18 | var _smoke_model: SmokeModel |
| 21 | var upper_to_lower_loss_rate: float = 0.025 |
| 22 | var upper_to_ambient_loss_rate: float = 0.008 |
| 23 | var lower_layer_warming_rate: float = 0.012 |
| 24 | var wall_absorption_rate: float = 0.003 |
| 25 | var max_upper_temp_c: float = 900.0 |
| 26 | var doorway_heat_exchange_coeff: float = 0.26 |
| 27 | var smoke_heat_mix_coeff: float = 0.025 |
| 28 | var retained_hot_layer_temp_start_c: float = 100.0 |
| 29 | var retained_hot_layer_temp_full_c: float = 350.0 |
| 30 | var retained_hot_layer_o2_start: float = 0.18 |
| 31 | var retained_hot_layer_o2_full: float = 0.10 |
| 32 | var retained_hot_layer_max_fraction: float = 0.85 |
| 33 | var outside_open_loss_area_fraction: float = 0.12 |
| 34 | var outside_open_ambient_loss_multiplier: float = 16.0 |
| 35 | var outside_open_wall_absorption_multiplier: float = 0.80 |
| 36 | var outside_open_upper_mix_rate: float = 0.0 |
| 37 | var outside_open_background_heat_exchange_kg_s_m2: float = 0.030 |
| 38 | var outside_open_background_heat_max_fraction_per_step: float = 0.020 |
| 39 | var outside_open_background_heat_carry_factor: float = 0.42 |
| 42 | var thermal_gradient_min_band_m: float = 0.20 |
| 43 | var thermal_gradient_max_band_m: float = 0.70 |
| 44 | var thermal_gradient_band_fraction: float = 0.35 |
| 47 | var floor_cooling_band_fraction: float = 0.24 |
| 48 | var floor_cooling_band_max_m: float = 0.35 |
| 49 | var survival_temp_threshold_c: float = 150.0 |
| 52 | var layer_150c_relax_down_per_s: float = 0.35 |
| 53 | var layer_150c_relax_up_per_s: float = 0.03 |
| 56 | var plume_fill_depth_coeff: float = 0.60 |
| 57 | var plume_fill_response_s: float = 12.0 |
| 58 | var plume_fill_max_fraction: float = 0.85 |
| 61 | var layer_relax_down: float = 0.18 |
| 62 | var layer_relax_up: float = 0.015 |
| 65 | var doorway_o2_min_band_m: float = 0.25 |
| 66 | var doorway_o2_smoke_weight: float = 0.35 |
| 67 | var doorway_o2_pressure_weight: float = 0.65 |
| 68 | var pressure_spill_ref_delta_pa: float = 8.0 |
| 69 | var interior_spill_start_layer_m: float = 2.0 |
| 72 | var fed_hypoxia_enabled: bool = true |
| 73 | var fed_hypoxia_a: float = 8.13 |
| 74 | var fed_hypoxia_b: float = 0.54 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 77 | func set_references(building: BuildingModel, smoke_model: SmokeModel) -> void: | Asigna o sincroniza references respetando validaciones locales. |
| 82 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 168 | func step(building: BuildingModel, dt: float, hooks: Dictionary = {}) -> void: | Balance termico completo: capa alta, perdidas, mezcla, transferencia entre salas e isoterma 150 C. |
| 334 | func ambient_temp_c() -> float: | Funcion auxiliar relacionada con: ambient temp c. |
| 338 | func gas_density_kg_m3(temp_c: float) -> float: | Funcion auxiliar relacionada con: gas density kg m3. |
| 344 | func estimate_target_upper_gas_mass_kg(room: RoomModel) -> float: | Estima target upper gas mass kg mediante una correlacion simplificada. |
| 360 | func estimate_retained_hot_layer_depth_m(room: RoomModel) -> float: | Estima retained hot layer depth m mediante una correlacion simplificada. |
| 391 | func estimate_room_outside_open_factor(room: RoomModel) -> float: | Estima room outside open factor mediante una correlacion simplificada. |
| 416 | func _apply_outside_assisted_background_heat_exchange( | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 550 | func remove_upper_layer_fraction(room: RoomModel, fraction: float) -> void: | Funcion auxiliar relacionada con: remove upper layer fraction. |
| 562 | func reset_thermal_layer(room: RoomModel) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 569 | func estimate_thermal_layer_height_m(room: RoomModel) -> float: | Estima thermal layer height m mediante una correlacion simplificada. |
| 582 | func compute_interroom_transfer_temp_c( | Calcula interroom transfer temp c a partir del estado actual y parametros fisicos. |
| 612 | func estimate_thermal_gradient_depth_m(room: RoomModel) -> float: | Estima thermal gradient depth m mediante una correlacion simplificada. |
| 642 | func _compute_room_vertical_mix_bonus(room: RoomModel) -> float: | Calcula room vertical mix bonus a partir del estado actual y parametros fisicos. |
| 661 | func _apply_post_transfer_vertical_mix(room: RoomModel, dt: float) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 687 | func estimate_floor_cooling_band_m(room: RoomModel) -> float: | Estima floor cooling band m mediante una correlacion simplificada. |
| 709 | func estimate_temperature_at_height_m(room: RoomModel, height_m: float) -> float: | Evalua temperatura a una altura usando dos zonas, gradiente y enfriamiento junto al suelo. |
| 737 | func estimate_isotherm_height_m(room: RoomModel, threshold_c: float) -> float: | Estima isotherm height m mediante una correlacion simplificada. |
| 774 | func update_room_layer_150c(room: RoomModel, dt: float) -> void: | Actualiza room layer 150c acumulando o relajando el estado previo. |
| 793 | func compute_co_ppm(room: RoomModel) -> float: | Calcula co ppm a partir del estado actual y parametros fisicos. |
| 800 | func compute_co_upper_ppm(room: RoomModel) -> float: | Calcula co upper ppm a partir del estado actual y parametros fisicos. |
| 809 | func compute_co_lower_ppm(room: RoomModel) -> float: | Calcula co lower ppm a partir del estado actual y parametros fisicos. |
| 818 | func compute_co2_ppm(room: RoomModel) -> float: | Calcula co2 ppm a partir del estado actual y parametros fisicos. |
| 833 | func step_fed(room: RoomModel, dt: float) -> void: | Integra FED por CO, CO2 y deficit de O2 y actualiza la supervivencia SVV. |
| 867 | func _compute_svv_pct_from_room(room: RoomModel) -> float: | Calcula svv pct from room a partir del estado actual y parametros fisicos. |
| 903 | func is_room_quiescent(room: RoomModel) -> bool: | Predicado booleano que decide si se cumple la condicion: is room quiescent. |
| 918 | func _should_collapse_thermal_layer(room: RoomModel) -> bool: | Predicado booleano que decide si se cumple la condicion: should collapse thermal layer. |
| 932 | func _call_path_factor(callable: Callable, room_id: int) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 938 | func sync_room_upper_layer(room: RoomModel, dt: float) -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 984 | func estimate_plume_upper_depth_m(room: RoomModel) -> float: | Estima plume upper depth m mediante una correlacion simplificada. |
| 1000 | func effective_hot_layer_height_m(room: RoomModel) -> float: | Funcion auxiliar relacionada con: effective hot layer height m. |
| 1008 | func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float: | Funcion auxiliar relacionada con: interior spill trigger layer m. |
| 1015 | func build_interior_opening_flow_state(room_a: RoomModel, room_b: RoomModel, op: OpeningModel) -> Dictionary: | Precalcula sala caliente/fria, capas, engagement y diferenciales para intercambios por puerta. |

### sim/core/GasExchangeSystem.gd

Transporte de humo, CO, CO2 y presion.

- Aplica generacion de humo, venting exterior, intercambio interior, limpieza post-incendio, deposicion, ACH y purgas.
- Tambien actualiza sobrepresion y retira capa alta al ventilar humo.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name GasExchangeSystem |
| 4 | var o2_nominal: float = 0.209 |
| 5 | var window_leakage_area_m2: float = 0.005 |
| 6 | var pressure_vent_threshold_pa: float = 2.0 |
| 7 | var ach_infiltration: float = 0.5 |
| 8 | var interior_transport_enabled: bool = true |
| 9 | var interior_transport_speed_m_s: float = 0.20 |
| 10 | var interior_transport_min_distance_m: float = 0.50 |
| 11 | var postfire_cleanup_hot_stop_c: float = 90.0 |
| 12 | var postfire_cleanup_cool_full_c: float = 35.0 |
| 13 | var postfire_cleanup_pressure_stop_pa: float = 0.8 |
| 14 | var postfire_cleanup_pressure_full_pa: float = 0.10 |
| 15 | var smoke_settling_base_per_s: float = 0.00004 |
| 16 | var smoke_settling_bonus_per_s: float = 0.00018 |
| 17 | var co_postfire_purge_base_per_s: float = 0.0 |
| 18 | var co_postfire_purge_bonus_per_s: float = 0.0 |
| 19 | var outside_open_species_purge_base_per_s: float = 0.0 |
| 20 | var outside_open_species_purge_bonus_per_s: float = 0.0 |
| 21 | var outside_open_species_temp_start_c: float = 60.0 |
| 22 | var outside_open_species_temp_full_c: float = 220.0 |
| 23 | var outside_open_species_pressure_ref_pa: float = 4.0 |
| 24 | var outside_open_species_upper_bias: float = 0.80 |
| 25 | var _pending_interior_deliveries: Array[Dictionary] = [] |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 28 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 64 | func reset() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 68 | func step_pressure_venting(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary: | Calcula sobrepresion por flotabilidad y purga exterior por fugas/ventanas. |
| 154 | func step_smoke(building: BuildingModel, smoke_model: SmokeModel, dt: float, hooks: Dictionary) -> Dictionary: | Mueve humo, CO, CO2 y O2: generacion, venting, transferencias, retrasos, ACH y limpieza. |
| 521 | func _compute_postfire_cleanup_factor(room: RoomModel) -> float: | Calcula postfire cleanup factor a partir del estado actual y parametros fisicos. |
| 546 | func _release_pending_interior_deliveries( | Funcion auxiliar relacionada con: release pending interior deliveries. |
| 587 | func _estimate_interior_transport_delay_s(building: BuildingModel, from_id: int, to_id: int) -> float: | Estima interior transport delay s mediante una correlacion simplificada. |
| 598 | func _apply_background_species_exchange( | Intercambio suave de especies por gradientes cuando hay camino de ventilacion local o remoto. |
| 703 | func _compute_outside_species_purge_fraction(building: BuildingModel, room: RoomModel, dt: float) -> float: | Calcula outside species purge fraction a partir del estado actual y parametros fisicos. |
| 733 | func _estimate_room_outside_open_factor(building: BuildingModel, room: RoomModel) -> float: | Estima room outside open factor mediante una correlacion simplificada. |
| 758 | func _has_any_active_fire(building: BuildingModel) -> bool: | Predicado booleano que decide si se cumple la condicion: has any active fire. |
| 770 | func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 776 | func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 782 | func _call_transfer_temp( | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 794 | func _call_room_fraction(callable: Callable, room: RoomModel, fraction: float) -> void: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 800 | func _call_room_dt(callable: Callable, room: RoomModel, dt: float) -> void: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |

### sim/core/FireSpreadSystem.gd

Propagacion entre salas.

- Acumula exposicion en salas vecinas a traves de puertas interiores abiertas.
- Llama a ignite_room cuando supera el tiempo requerido.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name FireSpreadSystem |
| 15 | var _building: BuildingModel |
| 16 | var _smoke_model: SmokeModel |
| 17 | var _combustion_system: CombustionSystem |
| 20 | var fire_spread_enabled: bool = true |
| 21 | var fire_spread_ignition_temp_c: float = 340.0 |
| 22 | var fire_spread_max_layer_m: float = 1.6 |
| 23 | var fire_spread_min_smoke_kg: float = 0.08 |
| 24 | var fire_spread_min_source_hrr_kw: float = 180.0 |
| 25 | var fire_spread_required_exposure_s: float = 35.0 |
| 26 | var fire_spread_exposure_decay_s: float = 12.0 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 29 | func set_references( | Asigna o sincroniza references respetando validaciones locales. |
| 39 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 53 | func step(dt: float, ignite_callable: Callable) -> void: | Recorre puertas interiores abiertas y acumula exposicion para propagar incendio. |
| 83 | func _update_fire_spread_exposure(source: RoomModel, target: RoomModel, dt: float) -> bool: | Actualiza fire spread exposure acumulando o relajando el estado previo. |

### sim/core/GlassFailureSystem.gd

Rotura termica de ventanas.

- Asigna umbrales con dispersion y abre progresivamente ventanas sobrecalentadas.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name GlassFailureSystem |
| 14 | var _building: BuildingModel |
| 17 | var glass_break_temp_c: float = 250.0 |
| 18 | var glass_break_temp_spread_c: float = 80.0 |
| 19 | var glass_open_rate_per_s: float = 0.15 |
| 20 | var glass_max_open_fraction: float = 0.85 |
| 23 | var _glass_break_temps: Dictionary = {} |
| 25 | var newly_broken_indices: Array[int] = [] |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 28 | func set_references(building: BuildingModel) -> void: | Asigna o sincroniza references respetando validaciones locales. |
| 32 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 39 | func reset() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 51 | func step(dt: float) -> void: | Rompe progresivamente ventanas exteriores cuando la temperatura supera el umbral asignado. |

### sim/core/SimulationStateBuilder.gd

Constructor de estado publico.

- Genera el diccionario serializable por habitacion para UI, visualizador, log y validacion.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name SimulationStateBuilder |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 5 | func build_state(context: Dictionary) -> Dictionary: | Construye el diccionario publico consumido por HUD, visualizador, log y validacion. |
| 117 | func _collect_sorted_room_ids(building: BuildingModel) -> Array[int]: | Recolecta identificadores o datos desde una estructura mayor. |
| 128 | func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 134 | func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 140 | func _call_room_height_float(callable: Callable, room: RoomModel, height_m: float, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 146 | func _call_room_bool(callable: Callable, room: RoomModel, default_value: bool) -> bool: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |

### sim/core/SimulationLogWriter.gd

Logger textual.

- Escribe sim_log.txt con bloques de tiempo y lineas por habitacion.
- Registra eventos de aperturas y snapshots finales para graficas.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name SimulationLogWriter |
| 4 | var enabled: bool = true |
| 5 | var interval_s: float = 10.0 |
| 6 | var log_file_path: String = "user://sim_log.txt" |
| 8 | var _next_log_time_s: float = 0.0 |
| 9 | var _resolved_log_file_path: String = "" |
| 10 | var _log_io_failed: bool = false |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 13 | func configure(is_enabled: bool, interval_seconds: float, path: String) -> void: | Funcion auxiliar relacionada con: configure. |
| 19 | func reset_log_file() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 36 | func resolve_log_file_path() -> String: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 44 | func should_log(sim_time_s: float) -> bool: | Predicado booleano que decide si se cumple la condicion: should log. |
| 48 | func append_snapshot(sim_time_s: float, state: Dictionary) -> void: | Anade al log un bloque TIME y una linea por habitacion con magnitudes principales. |
| 56 | func append_snapshot_now(sim_time_s: float, state: Dictionary) -> void: | Funcion auxiliar relacionada con: append snapshot now. |
| 65 | func append_event(sim_time_s: float, event_type: String, details: String) -> void: | Funcion auxiliar relacionada con: append event. |
| 79 | func _normalize_log_path(path: String) -> String: | Funcion auxiliar relacionada con: normalize log path. |
| 85 | func _get_log_file_candidates() -> Array[String]: | Devuelve log file candidates calculado o almacenado. |
| 97 | func _ensure_log_directory(resolved_path: String) -> bool: | Funcion auxiliar relacionada con: ensure log directory. |
| 108 | func _report_log_error_once(message: String) -> void: | Funcion auxiliar relacionada con: report log error once. |
| 116 | func _open_log_file(mode: FileAccess.ModeFlags, create_if_missing: bool = false) -> FileAccess: | Cambia el estado de una apertura del edificio. |
| 149 | func _append_snapshot(sim_time_s: float, state: Dictionary) -> void: | Funcion auxiliar relacionada con: append snapshot. |
| 243 | func _collect_room_ids(state: Dictionary) -> Array[int]: | Recolecta identificadores o datos desde una estructura mayor. |

### sim/templates/BuildingTemplate.gd

Templates activos de edificios.

- Define simple_house y ghanekar_bedroom_hallway: salas, rectangulos, puertas, ventanas y combustible.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 3 | func create_simple_house() -> Dictionary: | Crea una instancia o plantilla: simple house. |
| 229 | func create_ghanekar_bedroom_hallway() -> Dictionary: | Crea una instancia o plantilla: ghanekar bedroom hallway. |

### sim/templates/ApartmentTemplates.gd

Template legado minimo.

- Contiene un apartamento simple con rooms/doors, pero no sigue el formato moderno completo.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name ApartmentTemplates |

### sim/resources/default_fire_model.tres

Recurso Godot de FireModel.

- Asset serializado de FireModel por defecto.

### sim/validation/CaseRunner.gd

Runner de validacion headless.

- Lee argumentos CLI, carga caso JSON, aplica overrides, corre pasos fijos, captura metricas y compara baseline.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name CaseRunner |
| 4 | const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd") |
| 6 | @export var building_path: NodePath |
| 7 | @export var engine_path: NodePath |
| 8 | @export var reports_dir: String = "res://sim/validation/reports" |
| 9 | @export var auto_quit: bool = true |
| 11 | var building: BuildingModel |
| 12 | var engine: SimulationEngine |
| 14 | var _active: bool = false |
| 15 | var _case_name: String = "" |
| 16 | var _case_config: Dictionary = {} |
| 17 | var _cli_args: Dictionary = {} |
| 18 | var _metrics: Dictionary = {} |
| 19 | var _output_path: String = "" |
| 20 | var _baseline_path: String = "" |
| 21 | var _opening_events: Array = [] |
| 22 | var _incident_started: bool = false |
| 23 | var _runtime_error_reported: bool = false |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 26 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 35 | func _process(_delta: float) -> void: | Metodo periodico de Godot para actualizar escena o validacion. |
| 54 | func _resolve_refs() -> void: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 61 | func _parse_validation_args(args: Array[String]) -> Dictionary: | Parsea texto/argumentos y los convierte en una estructura interna. |
| 91 | func _begin_validation_run() -> void: | Funcion auxiliar relacionada con: begin validation run. |
| 143 | func _run_validation_loop() -> void: | Ejecuta headless en pasos fijos hasta la duracion del caso y aborta si no avanza. |
| 196 | func _abort_validation_run(message: String, exit_code: int = 1) -> void: | Funcion auxiliar relacionada con: abort validation run. |
| 207 | func _load_case_config(case_name: String) -> Dictionary: | Carga datos externos o de plantilla en objetos del programa. |
| 217 | func _build_case_template(case_config: Dictionary) -> Dictionary: | Construye una estructura de datos auxiliar: case template. |
| 236 | func _apply_room_overrides(template_data: Dictionary, overrides: Variant) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 261 | func _apply_opening_overrides(template_data: Dictionary, overrides: Variant) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 293 | func _apply_engine_overrides(overrides: Dictionary) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 298 | func _prepare_opening_events(raw_events: Variant) -> Array: | Prepara datos intermedios para una ejecucion posterior. |
| 315 | func _apply_due_opening_events(sim_time_s: float) -> bool: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 350 | func _resolve_opening_event_index(event_data: Dictionary) -> int: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 378 | func _resolve_opening_event_fraction(event_data: Dictionary) -> float: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 391 | func _update_metrics(state: Dictionary) -> void: | Recolecta picos, umbrales temporales, extincion, quiescencia y metricas globales. |
| 476 | func _update_room_peak_metrics(room_id: int, room_state: Dictionary) -> void: | Actualiza room peak metrics acumulando o relajando el estado previo. |
| 508 | func _capture_final_metrics(state: Dictionary) -> void: | Captura valores finales o instantaneos para reporte. |
| 537 | func _finalize_validation_run(state: Dictionary) -> void: | Cierra una ejecucion, escribe resultados y deja el sistema terminado. |
| 570 | func _compare_against_baseline(metrics: Dictionary, baseline_data: Dictionary) -> Dictionary: | Compara metricas contra reglas expected/tolerance/min/max de la baseline JSON. |
| 604 | func _collect_room_ids(state: Dictionary) -> Array[int]: | Recolecta identificadores o datos desde una estructura mayor. |
| 614 | func _get_watch_room_ids() -> Array[int]: | Devuelve watch room ids calculado o almacenado. |
| 625 | func _update_threshold_metrics(state: Dictionary, sim_time_s: float) -> void: | Actualiza threshold metrics acumulando o relajando el estado previo. |
| 652 | func _resolve_threshold_value(state: Dictionary, threshold_config: Dictionary) -> Dictionary: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 676 | func _threshold_passes(actual_value: float, op: String, threshold_value: float) -> bool: | Funcion auxiliar relacionada con: threshold passes. |
| 691 | func _read_text_file(path: String) -> String: | Funcion auxiliar relacionada con: read text file. |
| 700 | func _write_json_file(path: String, data: Dictionary) -> void: | Funcion auxiliar relacionada con: write json file. |

### sim/validation/run_case.ps1

Script PowerShell de un caso.

- Lanza Godot headless con caso concreto, log temporal, timeout y ruta de reporte.

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 62 | function Quote-ProcessArgument([string]$Value) { | Funcion auxiliar relacionada con: Quote-ProcessArgument. |

### sim/validation/run_all_cases.ps1

Bateria de validacion.

- Ejecuta casos principales y resume PASS/FAIL.

### ui/hud.gd

Interfaz de controles.

- Muestra tiempo, escala, play/pause, selector de aperturas y panel de sala.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Control |
| 2 | class_name HUD |
| 10 | @export var show_status_panel: bool = false |
| 11 | @export var status_panel_room_id: int = 0 |
| 12 | @export var compact_status_panel: bool = true |
| 13 | @export var show_openings_panel: bool = true |
| 15 | @onready var status_panel: PanelContainer = $StatusPanel |
| 16 | @onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel |
| 17 | @onready var time_label: Label = $MarginContainer/TimeLabel |
| 18 | @onready var openings_panel: PanelContainer = $OpeningsPanel |
| 19 | @onready var opening_selector: OptionButton = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningSelector |
| 20 | @onready var opening_status_label: Label = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningStatusLabel |
| 21 | @onready var btn_opening_close: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningClose |
| 22 | @onready var btn_opening_open: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningOpen |
| 23 | @onready var btn_stop_graphs: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnStopGraphs") as Button |
| 24 | @onready var btn_time_back: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeBack") as Button |
| 25 | @onready var btn_play: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPlay") as Button |
| 26 | @onready var btn_pause: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPause") as Button |
| 27 | @onready var btn_time_forward: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeForward") as Button |
| 28 | @onready var time_scale_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/TimeScaleLabel") as Label |
| 29 | @onready var playback_status_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/PlaybackStatusLabel") as Label |
| 31 | var building: BuildingModel = null |
| 32 | var selected_opening_index: int = 0 |
| 33 | var _selector_sync_in_progress: bool = false |
| 34 | var _known_opening_count: int = -1 |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 37 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 64 | func bind_building(next_building: BuildingModel) -> void: | Funcion auxiliar relacionada con: bind building. |
| 70 | func update_state(state: Dictionary) -> void: | Actualiza tiempo, play/pause, controles y panel de sala a partir del estado publico. |
| 96 | func build_room_status_text(room_state: Dictionary) -> String: | Construye una estructura de datos auxiliar: room status text. |
| 139 | func _refresh_opening_controls() -> void: | Funcion auxiliar relacionada con: refresh opening controls. |
| 176 | func _refresh_opening_status() -> void: | Funcion auxiliar relacionada con: refresh opening status. |
| 199 | func _set_openings_panel_empty(message: String) -> void: | Asigna o sincroniza openings panel empty respetando validaciones locales. |
| 212 | func _update_time_controls( | Actualiza time controls acumulando o relajando el estado previo. |
| 243 | func _format_time_scale_label(time_scale: float) -> String: | Funcion auxiliar relacionada con: format time scale label. |
| 252 | func _find_selector_item_by_opening_index(opening_index: int) -> int: | Funcion auxiliar relacionada con: find selector item by opening index. |
| 262 | func _on_opening_selected(item_index: int) -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 270 | func _on_open_button_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 278 | func _on_close_button_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 286 | func _on_stop_graphs_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 290 | func _on_time_back_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 294 | func _on_play_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 298 | func _on_pause_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 302 | func _on_time_forward_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |

### view/Visualizer.gd

Visualizador 2D.

- Pinta habitaciones, capas, humo, calor, HRR, ventanas/puertas y etiquetas adaptativas.

Declaraciones/variables principales:

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node2D |
| 2 | class_name Visualizer |
| 22 | @export var meters_to_px: float = 100.0 |
| 23 | @export var wall_thickness: float = 2.0 |
| 24 | @export var room_height_m_default: float = 2.4 |
| 26 | @export var background_color: Color = Color(0.10, 0.10, 0.11, 1.0) |
| 27 | @export var room_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0) |
| 28 | @export var room_fill_color: Color = Color(1.0, 1.0, 1.0, 0.02) |
| 30 | @export var auto_fit_to_view: bool = true |
| 31 | @export var view_margin_px: float = 20.0 |
| 33 | @export var ui_reserved_right_px: float = 200.0 |
| 34 | @export var ui_reserved_top_px: float = 0.0 |
| 40 | @export var show_room_fill: bool = true |
| 41 | @export var show_plan_atmosphere_overlay: bool = true |
| 42 | @export var show_fire_overlay: bool = false |
| 43 | @export var show_section_gauge: bool = true |
| 44 | @export var show_flashover_highlight: bool = true |
| 45 | @export var show_smoke_layer: bool = true |
| 46 | @export var show_smoke_layer_line: bool = true |
| 47 | @export var show_hot_layer_overlay: bool = true |
| 48 | @export var show_150c_layer: bool = true |
| 49 | @export var show_hrr_bar: bool = true |
| 50 | @export var show_openings: bool = true |
| 51 | @export var show_room_labels: bool = true |
| 52 | @export var show_room_name: bool = false |
| 53 | @export var show_opening_labels: bool = false |
| 59 | @export var smoke_base_color: Color = Color(0.32, 0.32, 0.36, 1.0) |
| 60 | @export var smoke_min_alpha: float = 0.30 |
| 61 | @export var smoke_max_alpha_bonus: float = 0.55 |
| 62 | @export var smoke_mass_reference_kg: float = 8.0 |
| 63 | @export var smoke_concentration_reference_kg_m3: float = 0.08 |
| 64 | @export var smoke_visible_threshold_kg: float = 0.01 |
| 65 | @export var smoke_layer_line_color: Color = Color(0.72, 0.72, 0.72, 0.95) |
| 66 | @export var smoke_layer_line_width: float = 2.0 |
| 67 | @export var hot_layer_color: Color = Color(1.0, 0.55, 0.15, 0.18) |
| 68 | @export var layer_150c_color: Color = Color(1.0, 0.10, 0.10, 0.95) |
| 69 | @export var layer_150c_line_width: float = 2.0 |
| 70 | @export var heat_room_tint_color: Color = Color(1.0, 0.42, 0.10, 1.0) |
| 71 | @export var fire_glow_color: Color = Color(1.0, 0.40, 0.10, 1.0) |
| 72 | @export var fire_core_color: Color = Color(1.0, 0.82, 0.35, 1.0) |
| 73 | @export var flashover_fill_color: Color = Color(1.0, 0.20, 0.05, 0.24) |
| 74 | @export var flashover_outline_color: Color = Color(1.0, 0.45, 0.05, 1.0) |
| 75 | @export var active_fire_outline_color: Color = Color(1.0, 0.62, 0.14, 1.0) |
| 76 | @export var low_o2_outline_color: Color = Color(0.85, 0.25, 0.25, 1.0) |
| 82 | @export var section_gauge_bg_color: Color = Color(0.0, 0.0, 0.0, 0.35) |
| 83 | @export var section_gauge_outline_color: Color = Color(1.0, 1.0, 1.0, 0.30) |
| 84 | @export var section_gauge_margin_px: float = 4.0 |
| 85 | @export var section_gauge_width_px: float = 16.0 |
| 86 | @export var section_gauge_min_height_px: float = 34.0 |
| 92 | @export var room_label_font_size: int = 10 |
| 93 | @export var room_label_color: Color = Color(1.0, 1.0, 1.0, 0.95) |
| 94 | @export var room_label_shadow: bool = true |
| 95 | @export var room_label_bg: bool = false |
| 96 | @export var room_label_bg_color: Color = Color(0.0, 0.0, 0.0, 0.40) |
| 97 | @export var room_label_padding: float = 4.0 |
| 98 | @export var room_label_offset: Vector2 = Vector2(4.0, 11.0) |
| 99 | @export var room_label_line_h: float = 11.0 |
| 100 | @export var room_label_tiny_threshold_w_px: float = 60.0 |
| 101 | @export var room_label_tiny_threshold_h_px: float = 40.0 |
| 102 | @export var room_label_compact_threshold_w_px: float = 85.0 |
| 103 | @export var room_label_compact_threshold_h_px: float = 72.0 |
| 104 | @export var room_label_medium_threshold_w_px: float = 135.0 |
| 105 | @export var room_label_medium_threshold_h_px: float = 120.0 |
| 111 | @export var hrr_bar_height_px: float = 4.0 |
| 112 | @export var hrr_bar_margin_px: float = 3.0 |
| 113 | @export var hrr_bar_max_kw: float = 3000.0 |
| 114 | @export var hrr_bar_color: Color = Color(1.0, 0.35, 0.15, 0.90) |
| 115 | @export var hrr_bar_bg_color: Color = Color(1.0, 1.0, 1.0, 0.08) |
| 121 | @export var door_color: Color = Color(0.30, 1.00, 0.40, 1.0) |
| 122 | @export var window_color: Color = Color(0.35, 0.70, 1.00, 1.0) |
| 123 | @export var window_broken_color: Color = Color(1.00, 0.55, 0.10, 1.0) |
| 124 | @export var window_open_color: Color = Color(1.00, 0.20, 0.05, 1.0) |
| 125 | @export var opening_line_width: float = 4.0 |
| 131 | @export var show_window_badge: bool = true |
| 132 | @export var window_full_open_threshold: float = 0.5 |
| 133 | @export var window_badge_size: Vector2 = Vector2(16.0, 7.0) |
| 139 | var state: Dictionary = {} |
| 140 | var rects_m: Dictionary[int, Rect2] = {} |
| 142 | @onready var building: BuildingModel = $"../BuildingModel" as BuildingModel |

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 149 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 160 | func set_state(s: Dictionary) -> void: | Asigna o sincroniza state respetando validaciones locales. |
| 169 | func _draw() -> void: | Dibuja habitaciones, capas, etiquetas, barras HRR, badges de ventana y aperturas. |
| 245 | func _draw_background() -> void: | Dibuja un elemento visual concreto en el canvas. |
| 253 | func _draw_room_atmosphere_overlay( | Dibuja un elemento visual concreto en el canvas. |
| 325 | func _draw_room_fire_overlay(rpx: Rect2, rs: Dictionary) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 358 | func _draw_section_gauge( | Dibuja un elemento visual concreto en el canvas. |
| 386 | func _draw_smoke_layer( | Dibuja un elemento visual concreto en el canvas. |
| 444 | func _draw_hot_layer_overlay(rpx: Rect2, hot_layer_m: float, room_h: float = room_height_m_default) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 459 | func _draw_150c_line(rpx: Rect2, layer_150c_m: float, room_h: float = room_height_m_default) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 481 | func _draw_hrr_bar(rpx: Rect2, hrr_kw: float) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 509 | func _compute_svv_pct(rs: Dictionary) -> float: | Replica el criterio SVV combinando isoterma 150 C y FED para colorear etiquetas. |
| 544 | func _get_svv_color(svv_pct: float) -> Color: | Devuelve svv color calculado o almacenado. |
| 556 | func _draw_room_label(id: int, rpx: Rect2, rs: Dictionary) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 591 | func _build_room_label_lines(id: int, content_rect: Rect2, rs: Dictionary) -> Array[String]: | Construye una estructura de datos auxiliar: room label lines. |
| 663 | func _pick_room_label_detail(content_rect: Rect2) -> String: | Funcion auxiliar relacionada con: pick room label detail. |
| 673 | func _fit_room_label_lines(content_rect: Rect2, lines: Array[String], flashover_triggered: bool) -> Array[String]: | Funcion auxiliar relacionada con: fit room label lines. |
| 701 | func _build_window_status_label(rs: Dictionary) -> String: | Construye una estructura de datos auxiliar: window status label. |
| 712 | func _get_room_label_bottom_reserved_px() -> float: | Devuelve room label bottom reserved px calculado o almacenado. |
| 718 | func _draw_text_line(text: String, pos: Vector2, color: Color) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 748 | func _draw_window_badge(rpx: Rect2, rs: Dictionary) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 794 | func _draw_openings() -> void: | Dibuja un elemento visual concreto en el canvas. |
| 875 | func _draw_door_top_view( | Dibuja un elemento visual concreto en el canvas. |
| 911 | func _shared_edge_segment_m(a: Rect2, b: Rect2) -> PackedVector2Array: | Funcion auxiliar relacionada con: shared edge segment m. |
| 945 | func _default_exterior_segment_m(r: Rect2, width_m: float, wall_side: String = "") -> PackedVector2Array: | Funcion auxiliar relacionada con: default exterior segment m. |
| 966 | func _build_room_outline_style(rs: Dictionary) -> Dictionary: | Construye una estructura de datos auxiliar: room outline style. |
| 1001 | func _build_section_gauge_rect(rpx: Rect2) -> Rect2: | Construye una estructura de datos auxiliar: section gauge rect. |
| 1022 | func _get_room_content_rect(rpx: Rect2) -> Rect2: | Devuelve room content rect calculado o almacenado. |
| 1040 | func _to_px(rm: Rect2) -> Rect2: | Funcion auxiliar relacionada con: to px. |
| 1050 | func _get_sorted_room_ids() -> Array[int]: | Devuelve sorted room ids calculado o almacenado. |
| 1058 | func _get_building_bounds_m() -> Rect2: | Devuelve building bounds m calculado o almacenado. |
| 1073 | func _get_draw_transform() -> Dictionary: | Devuelve draw transform calculado o almacenado. |

### scripts/generate_fire_graphs.py

Generador de graficas.

- Lee sim_log.txt, parsea series/eventos, detecta inflexiones y guarda PNGs.

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 74 | def parse_log(path): | Parsea sim_log.txt en series temporales por habitacion y eventos. |
| 133 | def _val(s, prefix, strip_suffix=""): | Funcion auxiliar relacionada con: val. |
| 198 | def _parse_event_line(line, events): | Parsea texto/argumentos y los convierte en una estructura interna. |
| 223 | def find_inflections(times, values, window_frac=0.05, min_pct=10.0, min_gap_s=40.0): | Detecta cambios bruscos por diferencias en ventana movil. |
| 263 | def _annotate_events(axes_list, events, xlim): | Funcion auxiliar relacionada con: annotate events. |
| 297 | def _annotate_inflections(ax, inflections, fmt_fn=None): | Funcion auxiliar relacionada con: annotate inflections. |
| 318 | def _save(fig, path): | Funcion auxiliar relacionada con: save. |
| 324 | def plot_room(room_id, r, room_dir, events=None): | Genera PNGs de HRR, temperaturas, capas, gases y FED/SVV para una habitacion. |
| 461 | def main(): | Punto de entrada del script. |

### scripts/download_fire_literature.ps1

Descarga bibliografia tecnica.

- Crea una libreria local de PDFs de FSRI, NIST, Springer, Figshare y otras fuentes.

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 16 | function Invoke-WebRequestCompat { | Funcion auxiliar relacionada con: Invoke-WebRequestCompat. |
| 41 | function New-DirectoryIfMissing { | Funcion auxiliar relacionada con: New-DirectoryIfMissing. |
| 49 | function Test-IsPdfFile { | Funcion auxiliar relacionada con: Test-IsPdfFile. |
| 72 | function Get-ResolvedUri { | Funcion auxiliar relacionada con: Get-ResolvedUri. |
| 82 | function Get-FirstRegexMatchValue { | Funcion auxiliar relacionada con: Get-FirstRegexMatchValue. |
| 103 | function Resolve-SpringerPdfUrl { | Funcion auxiliar relacionada con: Resolve-SpringerPdfUrl. |
| 110 | function Resolve-FigshareDownloadUrl { | Funcion auxiliar relacionada con: Resolve-FigshareDownloadUrl. |
| 128 | function Resolve-HtmlDownloadUrl { | Funcion auxiliar relacionada con: Resolve-HtmlDownloadUrl. |
| 170 | function Resolve-PmcPdfUrl { | Funcion auxiliar relacionada con: Resolve-PmcPdfUrl. |
| 188 | function Resolve-SourceUrl { | Funcion auxiliar relacionada con: Resolve-SourceUrl. |
| 213 | function Download-ResearchItem { | Funcion auxiliar relacionada con: Download-ResearchItem. |

### scripts/simulation/run_ghanekar_sweep.ps1

Barrido de calibracion.

- Genera casos temporales con variantes de parametros, ejecuta Godot y calcula ranking.

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 17 | function New-BaseCase { | Funcion auxiliar relacionada con: New-BaseCase. |
| 66 | function Get-MetricValue { | Funcion auxiliar relacionada con: Get-MetricValue. |
| 84 | function Get-Score { | Funcion auxiliar relacionada con: Get-Score. |

### scripts/simulation/run_ghanekar_micro_calibration.ps1

Micro-calibracion.

- Hace un barrido fino sobre parametros termicos/transporte y genera resumen JSON/Markdown.

Funciones:

| Linea | Funcion | Que hace |
| --- | --- | --- |
| 17 | function New-BaseCase { | Funcion auxiliar relacionada con: New-BaseCase. |
| 66 | function Get-MetricValue { | Funcion auxiliar relacionada con: Get-MetricValue. |
| 84 | function Get-Score { | Funcion auxiliar relacionada con: Get-Score. |

## Casos de validacion

| Caso | Objetivo |
| --- | --- |
| cfast_r0_window_360.json | simple_house con ventana de R0 abierta a 360 s y log para comparacion tipo CFAST. |
| ghanekar_bedroom_hallway.json | Dormitorio/pasillo con metricas de flashover, O2, CO, CO2 y FED. |
| layer150_tenability.json | Controla descenso de isoterma 150 C y temperatura respirable. |
| living_room_hallway.json | Regresion basica de humo/calor de salon a pasillo. |
| long_smoke_o2_1800.json | Corrida larga para observar acumulacion y recuperacion de humo/O2. |
| long_smoke_o2_debug.json | Version corta con logging detallado. |
| postfire_decay.json | Comprueba extincion, limpieza post-incendio, capas y humo residual. |
| tmp_r0_window_open_start.json | Ventana de R0 abierta desde el inicio; ventilacion local. |
| tmp_r2_window_open_start.json | Ventana de R2 abierta desde el inicio; valida ventilacion remota hacia R0. |

## Baselines

| Baseline | Metricas controladas |
| --- | --- |
| layer150_tenability.json | metrics, room_1_min_l150_m, room_1_final_temp_at_1_8m_c, room_0_final_layer_150c_m |
| living_room_hallway.json | metrics, time_room_0_smoke_layer_2m_s, time_room_1_smoke_start_s, room_1_peak_temp_upper_c, room_1_min_l150_m, room_1_final_temp_at_1_8m_c, room_0_final_layer_150c_m |
| postfire_decay.json | metrics, time_room_0_l150_below_1_8m_s, time_room_0_l150_below_0_5m_s, time_to_extinction_s, room_0_final_hot_layer_m, room_0_final_temp_at_1_8m_c, room_0_final_smoke_kg, room_1_final_smoke_kg, smoke_deposited_total_kg |
| tmp_r2_window_open_start.json | metrics, room_2_peak_temp_upper_c, room_2_final_temp_at_1_8m_c, room_2_peak_co2_ppm, room_2_final_smoke_kg, room_2_final_fed, room_1_peak_temp_upper_c, room_0_final_hrr_kw, room_0_final_outside_open_path_factor, room_0_final_o2 |

## Apendice A - Indice exhaustivo de funciones

### Main.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 30 | func _ready() -> void: | Inicializa referencias, detecta modo validacion, conecta senales del HUD y sincroniza el estado inicial. |
| 59 | func _physics_process(delta: float) -> void: | Avanza la simulacion cuando no esta pausada y actualiza visualizador e interfaz cada frame fisico. |
| 70 | func _apply_state_to_ui(state: Dictionary) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 77 | func _build_ui_state() -> Dictionary: | Toma el estado publico del motor y le anade datos de reproduccion para el HUD. |
| 89 | func _on_play_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 96 | func _on_pause_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 103 | func _on_slower_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 110 | func _on_faster_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 117 | func _on_stop_and_generate_requested() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 125 | func _find_time_scale_step_index(current_scale: float) -> int: | Funcion auxiliar relacionada con: find time scale step index. |
| 138 | func _set_time_scale_by_step(step_index: int) -> void: | Asigna o sincroniza time scale by step respetando validaciones locales. |
| 146 | func _is_validation_mode() -> bool: | Predicado booleano que decide si se cumple la condicion: is validation mode. |

### sim/BuildingModel.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 45 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 56 | func get_room_rects_m() -> Dictionary[int, Rect2]: | Devuelve room rects m calculado o almacenado. |
| 60 | func get_room_centroid_m(room_id: int) -> Vector2: | Devuelve room centroid m calculado o almacenado. |
| 65 | func estimate_room_connection_length_m(room_a_id: int, room_b_id: int) -> float: | Estima room connection length m mediante una correlacion simplificada. |
| 71 | func get_room(room_id: int) -> RoomModel: | Devuelve room calculado o almacenado. |
| 74 | func get_rooms() -> Dictionary: | Devuelve rooms calculado o almacenado. |
| 77 | func get_openings() -> Array: | Devuelve openings calculado o almacenado. |
| 80 | func load_template_data(data: Dictionary) -> void: | Carga datos externos o de plantilla en objetos del programa. |
| 87 | func _load_from_template(data: Dictionary) -> void: | Carga datos externos o de plantilla en objetos del programa. |
| 146 | func _add_room_from_rect( | Funcion auxiliar relacionada con: add room from rect. |
| 167 | func _build_fuel_objects(raw_objects: Variant) -> Array: | Construye una estructura de datos auxiliar: fuel objects. |
| 201 | func has_outside_opening(room_id: int) -> bool: | Predicado booleano que decide si se cumple la condicion: has outside opening. |
| 216 | func estimate_vent_hrr_kw(room_id: int) -> float: | Estima vent hrr kw mediante una correlacion simplificada. |
| 242 | func get_connected_openings(room_id: int) -> Array: | Devuelve connected openings calculado o almacenado. |
| 251 | func get_neighbor_room_ids(room_id: int) -> Array[int]: | Devuelve neighbor room ids calculado o almacenado. |
| 266 | func get_opening_count() -> int: | Devuelve opening count calculado o almacenado. |
| 270 | func get_opening_at(index: int): | Devuelve opening at calculado o almacenado. |
| 276 | func set_opening_fraction(index: int, open_fraction: float) -> bool: | Asigna o sincroniza opening fraction respetando validaciones locales. |
| 285 | func open_opening(index: int) -> bool: | Cambia el estado de una apertura del edificio. |
| 289 | func close_opening(index: int) -> bool: | Cambia el estado de una apertura del edificio. |
| 293 | func get_opening_label(index: int) -> String: | Devuelve opening label calculado o almacenado. |
| 307 | func get_opening_status_text(index: int) -> String: | Devuelve opening status text calculado o almacenado. |
| 320 | func build_opening_summaries() -> Array[Dictionary]: | Construye una estructura de datos auxiliar: opening summaries. |
| 340 | func _get_room_display_name(room_id: int) -> String: | Devuelve room display name calculado o almacenado. |

### sim/building/RoomModel.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 83 | func floor_area_m2() -> float: | Funcion auxiliar relacionada con: floor area m2. |
| 87 | func volume_m3() -> float: | Funcion auxiliar relacionada con: volume m3. |
| 91 | func reset_dynamic_state(ambient_temp_c: float, ambient_o2: float) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |

### sim/building/OpeningModel.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 24 | func _init(_a: int, _b: int, _type: int, _w: float, _h: float, _open: float = 1.0, _sill: float = 0.0) -> void: | Funcion auxiliar relacionada con: init. |
| 34 | func set_open_fraction(value: float) -> void: | Asigna o sincroniza open fraction respetando validaciones locales. |
| 38 | func lintel_height_m() -> float: | Funcion auxiliar relacionada con: lintel height m. |
| 42 | func is_exterior_opening() -> bool: | Predicado booleano que decide si se cumple la condicion: is exterior opening. |
| 46 | func is_closed() -> bool: | Predicado booleano que decide si se cumple la condicion: is closed. |
| 50 | func is_fully_open() -> bool: | Predicado booleano que decide si se cumple la condicion: is fully open. |
| 56 | func state_label() -> String: | Funcion auxiliar relacionada con: state label. |

### sim/fire/FireModel.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 41 | func compute_hrr_kw(t_s: float) -> float: | Calcula hrr kw a partir del estado actual y parametros fisicos. |

### sim/fire/FuelObjectModel.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 53 | func configure_from_legacy_room(room: RoomModel) -> void: | Funcion auxiliar relacionada con: configure from legacy room. |
| 69 | func reset_dynamic_state(ambient_temp_c: float = 20.0) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 80 | func has_remaining_fuel() -> bool: | Predicado booleano que decide si se cumple la condicion: has remaining fuel. |
| 84 | func can_ignite() -> bool: | Predicado booleano que decide si se cumple la condicion: can ignite. |
| 88 | func remaining_fraction() -> float: | Funcion auxiliar relacionada con: remaining fraction. |

### sim/fire/CombustionSystem.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 15 | func ensure_room_fuel_objects(room: RoomModel) -> void: | Funcion auxiliar relacionada con: ensure room fuel objects. |
| 33 | func bootstrap_building(building: BuildingModel) -> void: | Funcion auxiliar relacionada con: bootstrap building. |
| 42 | func create_legacy_room_fire(room: RoomModel, defaults: Dictionary) -> FireModel: | Crea una instancia o plantilla: legacy room fire. |
| 71 | func step_room_fire(room: RoomModel, dt: float, context: Dictionary) -> bool: | Nucleo de combustion: HRR, O2, pirolisis, brasas, gases no quemados, CO/CO2, humo y extincion. |
| 477 | func get_room_total_remaining_fuel_MJ(room: RoomModel) -> float: | Devuelve room total remaining fuel MJ calculado o almacenado. |
| 489 | func get_room_total_max_hrr_kw(room: RoomModel) -> float: | Devuelve room total max hrr kw calculado o almacenado. |
| 501 | func get_room_active_object_count(room: RoomModel) -> int: | Devuelve room active object count calculado o almacenado. |
| 514 | func get_room_heating_object_count(room: RoomModel) -> int: | Devuelve room heating object count calculado o almacenado. |
| 527 | func get_room_pyrolyzing_object_count(room: RoomModel) -> int: | Devuelve room pyrolyzing object count calculado o almacenado. |
| 540 | func get_room_passive_surface_temp_c(room: RoomModel) -> float: | Devuelve room passive surface temp c calculado o almacenado. |
| 545 | func get_room_passive_flux_kw_m2(room: RoomModel) -> float: | Devuelve room passive flux kw m2 calculado o almacenado. |
| 550 | func get_room_passive_ignition_flux_kw_m2(room: RoomModel) -> float: | Devuelve room passive ignition flux kw m2 calculado o almacenado. |
| 555 | func is_room_passive_autoignite_ready(room: RoomModel) -> bool: | Predicado booleano que decide si se cumple la condicion: is room passive autoignite ready. |
| 560 | func update_passive_room_fuel( | Actualiza calentamiento, flujo radiativo y estado de combustibles pasivos de una sala sin fuego activo. |
| 704 | func _resolve_room_fuel_energy_MJ(room: RoomModel, fallback_MJ: float) -> float: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 717 | func _resolve_room_max_hrr_kw(room: RoomModel, fallback_kw: float) -> float: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 730 | func _compute_o2_factor(o2: float, nominal: float, min_o2: float) -> float: | Calcula o2 factor a partir del estado actual y parametros fisicos. |
| 738 | func _compute_smoke_production_kg_s(hrr_kw: float, smoke_yield_kg_per_MJ: float) -> float: | Calcula smoke production kg s a partir del estado actual y parametros fisicos. |
| 743 | func _smooth_state_value( | Funcion auxiliar relacionada con: smooth state value. |
| 757 | func _estimate_radiative_flux_kw_m2( | Estima radiative flux kw m2 mediante una correlacion simplificada. |
| 771 | func _celsius_to_kelvin(temp_c: float) -> float: | Funcion auxiliar relacionada con: celsius to kelvin. |
| 775 | func _can_sustain_latent_fire( | Decide si un fuego puede mantenerse latente por temperatura, combustible y reserva de gases. |
| 820 | func _extinguish_room_fire(room: RoomModel, fire: FireModel, burned_out: bool = false) -> bool: | Funcion auxiliar relacionada con: extinguish room fire. |
| 840 | func _get_legacy_room_proxy(room: RoomModel): | Devuelve legacy room proxy calculado o almacenado. |
| 856 | func _sync_legacy_proxy_idle(room: RoomModel) -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 872 | func _sync_legacy_proxy_from_fire(room: RoomModel, fire: FireModel, hrr_kw: float, can_flame: bool) -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 895 | func _mark_legacy_proxy_burned_out(room: RoomModel) -> void: | Funcion auxiliar relacionada con: mark legacy proxy burned out. |

### sim/smoke/SmokeModel.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 59 | func add_generated_smoke(room: RoomModel, dt: float) -> float: | Funcion auxiliar relacionada con: add generated smoke. |
| 63 | func estimate_smoke_layer_height_m(room: RoomModel) -> float: | Estima smoke layer height m mediante una correlacion simplificada. |
| 79 | func get_visible_smoke_layer_height_m(room: RoomModel) -> float: | Devuelve visible smoke layer height m calculado o almacenado. |
| 89 | func get_effective_smoke_spill_layer_height_m(room: RoomModel) -> float: | Devuelve effective smoke spill layer height m calculado o almacenado. |
| 122 | func get_spill_layer_height_m(room: RoomModel) -> float: | Devuelve spill layer height m calculado o almacenado. |
| 134 | func recompute_layer_from_mass(room: RoomModel, dt: float) -> void: | Relaja la altura visible de humo hacia la altura que corresponde a la masa acumulada. |
| 194 | func compute_outside_vented_kg( | Estima humo que sale al exterior segun capa, temperatura y presion. |
| 250 | func compute_room_transfers( | Calcula transferencias de humo por aperturas interiores cuando la capa invade el dintel. |
| 333 | func compute_room_transfer( | Calcula room transfer a partir del estado actual y parametros fisicos. |
| 368 | func _compute_opening_mass_budget_kg( | Calcula opening mass budget kg a partir del estado actual y parametros fisicos. |
| 385 | func _compute_transfer_mass_kg_continuous( | Calcula transfer mass kg continuous a partir del estado actual y parametros fisicos. |
| 440 | func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float: | Funcion auxiliar relacionada con: interior spill trigger layer m. |
| 447 | func _interior_spill_full_layer_m(room: RoomModel, trigger_layer_m: float) -> float: | Funcion auxiliar relacionada con: interior spill full layer m. |
| 454 | func _compute_pressure_spill_multiplier(source: RoomModel, target: RoomModel = null) -> float: | Calcula pressure spill multiplier a partir del estado actual y parametros fisicos. |
| 474 | func _compute_smoke_temp_expansion(room: RoomModel) -> float: | Calcula smoke temp expansion a partir del estado actual y parametros fisicos. |

### sim/core/SimulationEngine.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 348 | func _sync_auxiliary_services() -> void: | Copia parametros exportados del motor hacia los subsistemas especializados. |
| 449 | func _build_state_context() -> Dictionary: | Construye una estructura de datos auxiliar: state context. |
| 472 | func _build_gas_exchange_hooks() -> Dictionary: | Construye una estructura de datos auxiliar: gas exchange hooks. |
| 482 | func _build_oxygen_exchange_hooks() -> Dictionary: | Construye una estructura de datos auxiliar: oxygen exchange hooks. |
| 493 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 511 | func _reset_log_file() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 519 | func _resolve_building() -> void: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 526 | func _sync_smoke_model_settings() -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 550 | func reset_simulation(start_ignition_room_id: int = ignition_room_id, ignite_initial_fire: bool = true) -> void: | Reinicia habitaciones, sistemas auxiliares, logs y opcionalmente prende la habitacion inicial. |
| 580 | func _reset_room_state(room: RoomModel) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 596 | func step(delta: float) -> void: | Paso principal: fuego, oxigeno, termica, vidrio, gases, combustible pasivo, propagacion, clamps y log. |
| 644 | func ignite_room(room_id: int) -> void: | Crea/activa el FireModel de una sala y prepara su combustible para quemar. |
| 670 | func _build_fire_defaults() -> Dictionary: | Construye una estructura de datos auxiliar: fire defaults. |
| 684 | func _build_room_combustion_context(room_id: int) -> Dictionary: | Reune los parametros de combustion que necesita CombustionSystem para una sala. |
| 758 | func _step_gas_exchange(dt: float) -> void: | Funcion auxiliar relacionada con: step gas exchange. |
| 772 | func _step_passive_fuel(dt: float) -> void: | Funcion auxiliar relacionada con: step passive fuel. |
| 796 | func _build_passive_fuel_context(room_id: int) -> Dictionary: | Construye una estructura de datos auxiliar: passive fuel context. |
| 852 | func _step_fire(dt: float) -> void: | Funcion auxiliar relacionada con: step fire. |
| 873 | func _kawagoe_factor_for_room(room_id: int) -> float: | Calcula suma A*sqrt(H) de ventanas exteriores abiertas para limitar HRR por ventilacion local. |
| 895 | func _window_open_max_for_room(room_id: int) -> float: | Funcion auxiliar relacionada con: window open max for room. |
| 915 | func _outside_open_path_factor_for_room(room_id: int) -> float: | Busca por puertas interiores abiertas una ruta hasta una apertura exterior y devuelve una senal atenuada de ventilacion remota. |
| 981 | func _try_trigger_flashover(room: RoomModel) -> void: | Evalua temperatura, capas y tenabilidad para disparar flashover y aumentar HRR disponible. |
| 1025 | func _step_oxygen(dt: float) -> void: | Funcion auxiliar relacionada con: step oxygen. |
| 1035 | func debug_check_smoke_conservation() -> void: | Funcion auxiliar relacionada con: debug check smoke conservation. |
| 1062 | func _clamp_rooms() -> void: | Funcion auxiliar relacionada con: clamp rooms. |
| 1103 | func get_state() -> Dictionary: | Devuelve state calculado o almacenado. |
| 1109 | func is_ready_for_validation() -> bool: | Predicado booleano que decide si se cumple la condicion: is ready for validation. |
| 1121 | func are_graphs_launched() -> bool: | Funcion auxiliar relacionada con: are graphs launched. |
| 1125 | func stop_and_generate_graphs(details: String = "manual_stop_button") -> bool: | Funcion auxiliar relacionada con: stop and generate graphs. |
| 1139 | func _detect_and_log_opening_events() -> void: | Funcion auxiliar relacionada con: detect and log opening events. |
| 1166 | func _log_opening_event(opening_idx: int, event_type: String) -> void: | Funcion auxiliar relacionada con: log opening event. |
| 1179 | func _on_sim_finished() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 1183 | func _finish_and_launch_graphs(details: String) -> void: | Cierra una ejecucion, escribe resultados y deja el sistema terminado. |
| 1199 | func _force_log_final_snapshot() -> void: | Funcion auxiliar relacionada con: force log final snapshot. |
| 1204 | func _launch_graph_generator() -> void: | Funcion auxiliar relacionada con: launch graph generator. |
| 1221 | func _should_launch_graphs() -> bool: | Predicado booleano que decide si se cumple la condicion: should launch graphs. |
| 1232 | func _exit_tree() -> void: | Funcion auxiliar relacionada con: exit tree. |
| 1239 | func _maybe_log_state() -> void: | Funcion auxiliar relacionada con: maybe log state. |

### sim/core/OxygenExchangeSystem.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 19 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 57 | func reset() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 62 | func step(building: BuildingModel, dt: float, hooks: Dictionary) -> void: | Consume O2 por HRR y aplica entrada/intercambio por aperturas exteriores e interiores. |
| 137 | func _step_outside_opening_o2( | Modelo de entrada de aire fresco por apertura exterior usando deficit de O2, capa caliente, presion y area baja. |
| 238 | func _step_interior_opening_o2( | Intercambio de O2 entre salas por puerta abierta, con mezcla de fondo y flujo activo. |
| 331 | func _exchange_room_o2_immediate( | Funcion auxiliar relacionada con: exchange room o2 immediate. |
| 361 | func _exchange_room_o2_active_flow( | Transporta una parcela caliente de una sala a otra y una compensacion fria al contrario. |
| 405 | func _release_pending_o2_deliveries(building: BuildingModel, dt: float, air_density_kg_m3: float) -> void: | Funcion auxiliar relacionada con: release pending o2 deliveries. |
| 428 | func _reserve_room_o2_delta(room_id: int, delta_o2_kg: float) -> void: | Funcion auxiliar relacionada con: reserve room o2 delta. |
| 439 | func _apply_room_o2_mass_delta(room: RoomModel, delta_o2_kg: float, air_density_kg_m3: float) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 448 | func _effective_room_o2_fraction(room: RoomModel, air_density_kg_m3: float) -> float: | Funcion auxiliar relacionada con: effective room o2 fraction. |
| 462 | func _estimate_interior_transport_delay_s(building: BuildingModel, room_a_id: int, room_b_id: int) -> float: | Estima interior transport delay s mediante una correlacion simplificada. |
| 473 | func _compute_room_air_mass_kg(room: RoomModel, air_density_kg_m3: float) -> float: | Calcula room air mass kg a partir del estado actual y parametros fisicos. |
| 479 | func _estimate_room_outside_open_factor(building: BuildingModel, room: RoomModel) -> float: | Estima room outside open factor mediante una correlacion simplificada. |
| 504 | func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 510 | func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 516 | func _call_interior_flow_state( | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |

### sim/core/ThermalSystem.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 77 | func set_references(building: BuildingModel, smoke_model: SmokeModel) -> void: | Asigna o sincroniza references respetando validaciones locales. |
| 82 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 168 | func step(building: BuildingModel, dt: float, hooks: Dictionary = {}) -> void: | Balance termico completo: capa alta, perdidas, mezcla, transferencia entre salas e isoterma 150 C. |
| 334 | func ambient_temp_c() -> float: | Funcion auxiliar relacionada con: ambient temp c. |
| 338 | func gas_density_kg_m3(temp_c: float) -> float: | Funcion auxiliar relacionada con: gas density kg m3. |
| 344 | func estimate_target_upper_gas_mass_kg(room: RoomModel) -> float: | Estima target upper gas mass kg mediante una correlacion simplificada. |
| 360 | func estimate_retained_hot_layer_depth_m(room: RoomModel) -> float: | Estima retained hot layer depth m mediante una correlacion simplificada. |
| 391 | func estimate_room_outside_open_factor(room: RoomModel) -> float: | Estima room outside open factor mediante una correlacion simplificada. |
| 416 | func _apply_outside_assisted_background_heat_exchange( | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 550 | func remove_upper_layer_fraction(room: RoomModel, fraction: float) -> void: | Funcion auxiliar relacionada con: remove upper layer fraction. |
| 562 | func reset_thermal_layer(room: RoomModel) -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 569 | func estimate_thermal_layer_height_m(room: RoomModel) -> float: | Estima thermal layer height m mediante una correlacion simplificada. |
| 582 | func compute_interroom_transfer_temp_c( | Calcula interroom transfer temp c a partir del estado actual y parametros fisicos. |
| 612 | func estimate_thermal_gradient_depth_m(room: RoomModel) -> float: | Estima thermal gradient depth m mediante una correlacion simplificada. |
| 642 | func _compute_room_vertical_mix_bonus(room: RoomModel) -> float: | Calcula room vertical mix bonus a partir del estado actual y parametros fisicos. |
| 661 | func _apply_post_transfer_vertical_mix(room: RoomModel, dt: float) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 687 | func estimate_floor_cooling_band_m(room: RoomModel) -> float: | Estima floor cooling band m mediante una correlacion simplificada. |
| 709 | func estimate_temperature_at_height_m(room: RoomModel, height_m: float) -> float: | Evalua temperatura a una altura usando dos zonas, gradiente y enfriamiento junto al suelo. |
| 737 | func estimate_isotherm_height_m(room: RoomModel, threshold_c: float) -> float: | Estima isotherm height m mediante una correlacion simplificada. |
| 774 | func update_room_layer_150c(room: RoomModel, dt: float) -> void: | Actualiza room layer 150c acumulando o relajando el estado previo. |
| 793 | func compute_co_ppm(room: RoomModel) -> float: | Calcula co ppm a partir del estado actual y parametros fisicos. |
| 800 | func compute_co_upper_ppm(room: RoomModel) -> float: | Calcula co upper ppm a partir del estado actual y parametros fisicos. |
| 809 | func compute_co_lower_ppm(room: RoomModel) -> float: | Calcula co lower ppm a partir del estado actual y parametros fisicos. |
| 818 | func compute_co2_ppm(room: RoomModel) -> float: | Calcula co2 ppm a partir del estado actual y parametros fisicos. |
| 833 | func step_fed(room: RoomModel, dt: float) -> void: | Integra FED por CO, CO2 y deficit de O2 y actualiza la supervivencia SVV. |
| 867 | func _compute_svv_pct_from_room(room: RoomModel) -> float: | Calcula svv pct from room a partir del estado actual y parametros fisicos. |
| 903 | func is_room_quiescent(room: RoomModel) -> bool: | Predicado booleano que decide si se cumple la condicion: is room quiescent. |
| 918 | func _should_collapse_thermal_layer(room: RoomModel) -> bool: | Predicado booleano que decide si se cumple la condicion: should collapse thermal layer. |
| 932 | func _call_path_factor(callable: Callable, room_id: int) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 938 | func sync_room_upper_layer(room: RoomModel, dt: float) -> void: | Sincroniza valores derivados entre modelos o subsistemas. |
| 984 | func estimate_plume_upper_depth_m(room: RoomModel) -> float: | Estima plume upper depth m mediante una correlacion simplificada. |
| 1000 | func effective_hot_layer_height_m(room: RoomModel) -> float: | Funcion auxiliar relacionada con: effective hot layer height m. |
| 1008 | func _interior_spill_trigger_layer_m(room: RoomModel, lintel_m: float) -> float: | Funcion auxiliar relacionada con: interior spill trigger layer m. |
| 1015 | func build_interior_opening_flow_state(room_a: RoomModel, room_b: RoomModel, op: OpeningModel) -> Dictionary: | Precalcula sala caliente/fria, capas, engagement y diferenciales para intercambios por puerta. |

### sim/core/GasExchangeSystem.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 28 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 64 | func reset() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 68 | func step_pressure_venting(building: BuildingModel, dt: float, hooks: Dictionary) -> Dictionary: | Calcula sobrepresion por flotabilidad y purga exterior por fugas/ventanas. |
| 154 | func step_smoke(building: BuildingModel, smoke_model: SmokeModel, dt: float, hooks: Dictionary) -> Dictionary: | Mueve humo, CO, CO2 y O2: generacion, venting, transferencias, retrasos, ACH y limpieza. |
| 521 | func _compute_postfire_cleanup_factor(room: RoomModel) -> float: | Calcula postfire cleanup factor a partir del estado actual y parametros fisicos. |
| 546 | func _release_pending_interior_deliveries( | Funcion auxiliar relacionada con: release pending interior deliveries. |
| 587 | func _estimate_interior_transport_delay_s(building: BuildingModel, from_id: int, to_id: int) -> float: | Estima interior transport delay s mediante una correlacion simplificada. |
| 598 | func _apply_background_species_exchange( | Intercambio suave de especies por gradientes cuando hay camino de ventilacion local o remoto. |
| 703 | func _compute_outside_species_purge_fraction(building: BuildingModel, room: RoomModel, dt: float) -> float: | Calcula outside species purge fraction a partir del estado actual y parametros fisicos. |
| 733 | func _estimate_room_outside_open_factor(building: BuildingModel, room: RoomModel) -> float: | Estima room outside open factor mediante una correlacion simplificada. |
| 758 | func _has_any_active_fire(building: BuildingModel) -> bool: | Predicado booleano que decide si se cumple la condicion: has any active fire. |
| 770 | func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 776 | func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 782 | func _call_transfer_temp( | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 794 | func _call_room_fraction(callable: Callable, room: RoomModel, fraction: float) -> void: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 800 | func _call_room_dt(callable: Callable, room: RoomModel, dt: float) -> void: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |

### sim/core/FireSpreadSystem.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 29 | func set_references( | Asigna o sincroniza references respetando validaciones locales. |
| 39 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 53 | func step(dt: float, ignite_callable: Callable) -> void: | Recorre puertas interiores abiertas y acumula exposicion para propagar incendio. |
| 83 | func _update_fire_spread_exposure(source: RoomModel, target: RoomModel, dt: float) -> bool: | Actualiza fire spread exposure acumulando o relajando el estado previo. |

### sim/core/GlassFailureSystem.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 28 | func set_references(building: BuildingModel) -> void: | Asigna o sincroniza references respetando validaciones locales. |
| 32 | func configure(settings: Dictionary) -> void: | Funcion auxiliar relacionada con: configure. |
| 39 | func reset() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 51 | func step(dt: float) -> void: | Rompe progresivamente ventanas exteriores cuando la temperatura supera el umbral asignado. |

### sim/core/SimulationStateBuilder.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 5 | func build_state(context: Dictionary) -> Dictionary: | Construye el diccionario publico consumido por HUD, visualizador, log y validacion. |
| 117 | func _collect_sorted_room_ids(building: BuildingModel) -> Array[int]: | Recolecta identificadores o datos desde una estructura mayor. |
| 128 | func _call_room_float(callable: Callable, room: RoomModel, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 134 | func _call_room_id_float(callable: Callable, room_id: int, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 140 | func _call_room_height_float(callable: Callable, room: RoomModel, height_m: float, default_value: float) -> float: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |
| 146 | func _call_room_bool(callable: Callable, room: RoomModel, default_value: bool) -> bool: | Invoca un Callable de forma defensiva, con valor por defecto si no existe. |

### sim/core/SimulationLogWriter.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 13 | func configure(is_enabled: bool, interval_seconds: float, path: String) -> void: | Funcion auxiliar relacionada con: configure. |
| 19 | func reset_log_file() -> void: | Reinicia estado dinamico para volver a una condicion inicial conocida. |
| 36 | func resolve_log_file_path() -> String: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 44 | func should_log(sim_time_s: float) -> bool: | Predicado booleano que decide si se cumple la condicion: should log. |
| 48 | func append_snapshot(sim_time_s: float, state: Dictionary) -> void: | Anade al log un bloque TIME y una linea por habitacion con magnitudes principales. |
| 56 | func append_snapshot_now(sim_time_s: float, state: Dictionary) -> void: | Funcion auxiliar relacionada con: append snapshot now. |
| 65 | func append_event(sim_time_s: float, event_type: String, details: String) -> void: | Funcion auxiliar relacionada con: append event. |
| 79 | func _normalize_log_path(path: String) -> String: | Funcion auxiliar relacionada con: normalize log path. |
| 85 | func _get_log_file_candidates() -> Array[String]: | Devuelve log file candidates calculado o almacenado. |
| 97 | func _ensure_log_directory(resolved_path: String) -> bool: | Funcion auxiliar relacionada con: ensure log directory. |
| 108 | func _report_log_error_once(message: String) -> void: | Funcion auxiliar relacionada con: report log error once. |
| 116 | func _open_log_file(mode: FileAccess.ModeFlags, create_if_missing: bool = false) -> FileAccess: | Cambia el estado de una apertura del edificio. |
| 149 | func _append_snapshot(sim_time_s: float, state: Dictionary) -> void: | Funcion auxiliar relacionada con: append snapshot. |
| 243 | func _collect_room_ids(state: Dictionary) -> Array[int]: | Recolecta identificadores o datos desde una estructura mayor. |

### sim/templates/BuildingTemplate.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 3 | func create_simple_house() -> Dictionary: | Crea una instancia o plantilla: simple house. |
| 229 | func create_ghanekar_bedroom_hallway() -> Dictionary: | Crea una instancia o plantilla: ghanekar bedroom hallway. |

### sim/validation/CaseRunner.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 26 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 35 | func _process(_delta: float) -> void: | Metodo periodico de Godot para actualizar escena o validacion. |
| 54 | func _resolve_refs() -> void: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 61 | func _parse_validation_args(args: Array[String]) -> Dictionary: | Parsea texto/argumentos y los convierte en una estructura interna. |
| 91 | func _begin_validation_run() -> void: | Funcion auxiliar relacionada con: begin validation run. |
| 143 | func _run_validation_loop() -> void: | Ejecuta headless en pasos fijos hasta la duracion del caso y aborta si no avanza. |
| 196 | func _abort_validation_run(message: String, exit_code: int = 1) -> void: | Funcion auxiliar relacionada con: abort validation run. |
| 207 | func _load_case_config(case_name: String) -> Dictionary: | Carga datos externos o de plantilla en objetos del programa. |
| 217 | func _build_case_template(case_config: Dictionary) -> Dictionary: | Construye una estructura de datos auxiliar: case template. |
| 236 | func _apply_room_overrides(template_data: Dictionary, overrides: Variant) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 261 | func _apply_opening_overrides(template_data: Dictionary, overrides: Variant) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 293 | func _apply_engine_overrides(overrides: Dictionary) -> void: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 298 | func _prepare_opening_events(raw_events: Variant) -> Array: | Prepara datos intermedios para una ejecucion posterior. |
| 315 | func _apply_due_opening_events(sim_time_s: float) -> bool: | Aplica cambios ya calculados sobre modelos, metricas o configuracion. |
| 350 | func _resolve_opening_event_index(event_data: Dictionary) -> int: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 378 | func _resolve_opening_event_fraction(event_data: Dictionary) -> float: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 391 | func _update_metrics(state: Dictionary) -> void: | Recolecta picos, umbrales temporales, extincion, quiescencia y metricas globales. |
| 476 | func _update_room_peak_metrics(room_id: int, room_state: Dictionary) -> void: | Actualiza room peak metrics acumulando o relajando el estado previo. |
| 508 | func _capture_final_metrics(state: Dictionary) -> void: | Captura valores finales o instantaneos para reporte. |
| 537 | func _finalize_validation_run(state: Dictionary) -> void: | Cierra una ejecucion, escribe resultados y deja el sistema terminado. |
| 570 | func _compare_against_baseline(metrics: Dictionary, baseline_data: Dictionary) -> Dictionary: | Compara metricas contra reglas expected/tolerance/min/max de la baseline JSON. |
| 604 | func _collect_room_ids(state: Dictionary) -> Array[int]: | Recolecta identificadores o datos desde una estructura mayor. |
| 614 | func _get_watch_room_ids() -> Array[int]: | Devuelve watch room ids calculado o almacenado. |
| 625 | func _update_threshold_metrics(state: Dictionary, sim_time_s: float) -> void: | Actualiza threshold metrics acumulando o relajando el estado previo. |
| 652 | func _resolve_threshold_value(state: Dictionary, threshold_config: Dictionary) -> Dictionary: | Resuelve referencias, rutas o valores efectivos desde entradas flexibles. |
| 676 | func _threshold_passes(actual_value: float, op: String, threshold_value: float) -> bool: | Funcion auxiliar relacionada con: threshold passes. |
| 691 | func _read_text_file(path: String) -> String: | Funcion auxiliar relacionada con: read text file. |
| 700 | func _write_json_file(path: String, data: Dictionary) -> void: | Funcion auxiliar relacionada con: write json file. |

### sim/validation/run_case.ps1

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 62 | function Quote-ProcessArgument([string]$Value) { | Funcion auxiliar relacionada con: Quote-ProcessArgument. |

### ui/hud.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 37 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 64 | func bind_building(next_building: BuildingModel) -> void: | Funcion auxiliar relacionada con: bind building. |
| 70 | func update_state(state: Dictionary) -> void: | Actualiza tiempo, play/pause, controles y panel de sala a partir del estado publico. |
| 96 | func build_room_status_text(room_state: Dictionary) -> String: | Construye una estructura de datos auxiliar: room status text. |
| 139 | func _refresh_opening_controls() -> void: | Funcion auxiliar relacionada con: refresh opening controls. |
| 176 | func _refresh_opening_status() -> void: | Funcion auxiliar relacionada con: refresh opening status. |
| 199 | func _set_openings_panel_empty(message: String) -> void: | Asigna o sincroniza openings panel empty respetando validaciones locales. |
| 212 | func _update_time_controls( | Actualiza time controls acumulando o relajando el estado previo. |
| 243 | func _format_time_scale_label(time_scale: float) -> String: | Funcion auxiliar relacionada con: format time scale label. |
| 252 | func _find_selector_item_by_opening_index(opening_index: int) -> int: | Funcion auxiliar relacionada con: find selector item by opening index. |
| 262 | func _on_opening_selected(item_index: int) -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 270 | func _on_open_button_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 278 | func _on_close_button_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 286 | func _on_stop_graphs_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 290 | func _on_time_back_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 294 | func _on_play_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 298 | func _on_pause_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |
| 302 | func _on_time_forward_pressed() -> void: | Manejador de senal o boton; traduce una accion de interfaz en cambio de estado. |

### view/Visualizer.gd

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 149 | func _ready() -> void: | Metodo de ciclo de vida de Godot que prepara referencias y estado inicial. |
| 160 | func set_state(s: Dictionary) -> void: | Asigna o sincroniza state respetando validaciones locales. |
| 169 | func _draw() -> void: | Dibuja habitaciones, capas, etiquetas, barras HRR, badges de ventana y aperturas. |
| 245 | func _draw_background() -> void: | Dibuja un elemento visual concreto en el canvas. |
| 253 | func _draw_room_atmosphere_overlay( | Dibuja un elemento visual concreto en el canvas. |
| 325 | func _draw_room_fire_overlay(rpx: Rect2, rs: Dictionary) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 358 | func _draw_section_gauge( | Dibuja un elemento visual concreto en el canvas. |
| 386 | func _draw_smoke_layer( | Dibuja un elemento visual concreto en el canvas. |
| 444 | func _draw_hot_layer_overlay(rpx: Rect2, hot_layer_m: float, room_h: float = room_height_m_default) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 459 | func _draw_150c_line(rpx: Rect2, layer_150c_m: float, room_h: float = room_height_m_default) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 481 | func _draw_hrr_bar(rpx: Rect2, hrr_kw: float) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 509 | func _compute_svv_pct(rs: Dictionary) -> float: | Replica el criterio SVV combinando isoterma 150 C y FED para colorear etiquetas. |
| 544 | func _get_svv_color(svv_pct: float) -> Color: | Devuelve svv color calculado o almacenado. |
| 556 | func _draw_room_label(id: int, rpx: Rect2, rs: Dictionary) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 591 | func _build_room_label_lines(id: int, content_rect: Rect2, rs: Dictionary) -> Array[String]: | Construye una estructura de datos auxiliar: room label lines. |
| 663 | func _pick_room_label_detail(content_rect: Rect2) -> String: | Funcion auxiliar relacionada con: pick room label detail. |
| 673 | func _fit_room_label_lines(content_rect: Rect2, lines: Array[String], flashover_triggered: bool) -> Array[String]: | Funcion auxiliar relacionada con: fit room label lines. |
| 701 | func _build_window_status_label(rs: Dictionary) -> String: | Construye una estructura de datos auxiliar: window status label. |
| 712 | func _get_room_label_bottom_reserved_px() -> float: | Devuelve room label bottom reserved px calculado o almacenado. |
| 718 | func _draw_text_line(text: String, pos: Vector2, color: Color) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 748 | func _draw_window_badge(rpx: Rect2, rs: Dictionary) -> void: | Dibuja un elemento visual concreto en el canvas. |
| 794 | func _draw_openings() -> void: | Dibuja un elemento visual concreto en el canvas. |
| 875 | func _draw_door_top_view( | Dibuja un elemento visual concreto en el canvas. |
| 911 | func _shared_edge_segment_m(a: Rect2, b: Rect2) -> PackedVector2Array: | Funcion auxiliar relacionada con: shared edge segment m. |
| 945 | func _default_exterior_segment_m(r: Rect2, width_m: float, wall_side: String = "") -> PackedVector2Array: | Funcion auxiliar relacionada con: default exterior segment m. |
| 966 | func _build_room_outline_style(rs: Dictionary) -> Dictionary: | Construye una estructura de datos auxiliar: room outline style. |
| 1001 | func _build_section_gauge_rect(rpx: Rect2) -> Rect2: | Construye una estructura de datos auxiliar: section gauge rect. |
| 1022 | func _get_room_content_rect(rpx: Rect2) -> Rect2: | Devuelve room content rect calculado o almacenado. |
| 1040 | func _to_px(rm: Rect2) -> Rect2: | Funcion auxiliar relacionada con: to px. |
| 1050 | func _get_sorted_room_ids() -> Array[int]: | Devuelve sorted room ids calculado o almacenado. |
| 1058 | func _get_building_bounds_m() -> Rect2: | Devuelve building bounds m calculado o almacenado. |
| 1073 | func _get_draw_transform() -> Dictionary: | Devuelve draw transform calculado o almacenado. |

### scripts/generate_fire_graphs.py

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 74 | def parse_log(path): | Parsea sim_log.txt en series temporales por habitacion y eventos. |
| 133 | def _val(s, prefix, strip_suffix=""): | Funcion auxiliar relacionada con: val. |
| 198 | def _parse_event_line(line, events): | Parsea texto/argumentos y los convierte en una estructura interna. |
| 223 | def find_inflections(times, values, window_frac=0.05, min_pct=10.0, min_gap_s=40.0): | Detecta cambios bruscos por diferencias en ventana movil. |
| 263 | def _annotate_events(axes_list, events, xlim): | Funcion auxiliar relacionada con: annotate events. |
| 297 | def _annotate_inflections(ax, inflections, fmt_fn=None): | Funcion auxiliar relacionada con: annotate inflections. |
| 318 | def _save(fig, path): | Funcion auxiliar relacionada con: save. |
| 324 | def plot_room(room_id, r, room_dir, events=None): | Genera PNGs de HRR, temperaturas, capas, gases y FED/SVV para una habitacion. |
| 461 | def main(): | Punto de entrada del script. |

### scripts/download_fire_literature.ps1

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 16 | function Invoke-WebRequestCompat { | Funcion auxiliar relacionada con: Invoke-WebRequestCompat. |
| 41 | function New-DirectoryIfMissing { | Funcion auxiliar relacionada con: New-DirectoryIfMissing. |
| 49 | function Test-IsPdfFile { | Funcion auxiliar relacionada con: Test-IsPdfFile. |
| 72 | function Get-ResolvedUri { | Funcion auxiliar relacionada con: Get-ResolvedUri. |
| 82 | function Get-FirstRegexMatchValue { | Funcion auxiliar relacionada con: Get-FirstRegexMatchValue. |
| 103 | function Resolve-SpringerPdfUrl { | Funcion auxiliar relacionada con: Resolve-SpringerPdfUrl. |
| 110 | function Resolve-FigshareDownloadUrl { | Funcion auxiliar relacionada con: Resolve-FigshareDownloadUrl. |
| 128 | function Resolve-HtmlDownloadUrl { | Funcion auxiliar relacionada con: Resolve-HtmlDownloadUrl. |
| 170 | function Resolve-PmcPdfUrl { | Funcion auxiliar relacionada con: Resolve-PmcPdfUrl. |
| 188 | function Resolve-SourceUrl { | Funcion auxiliar relacionada con: Resolve-SourceUrl. |
| 213 | function Download-ResearchItem { | Funcion auxiliar relacionada con: Download-ResearchItem. |

### scripts/simulation/run_ghanekar_sweep.ps1

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 17 | function New-BaseCase { | Funcion auxiliar relacionada con: New-BaseCase. |
| 66 | function Get-MetricValue { | Funcion auxiliar relacionada con: Get-MetricValue. |
| 84 | function Get-Score { | Funcion auxiliar relacionada con: Get-Score. |

### scripts/simulation/run_ghanekar_micro_calibration.ps1

| Linea | Funcion | Descripcion |
| --- | --- | --- |
| 17 | function New-BaseCase { | Funcion auxiliar relacionada con: New-BaseCase. |
| 66 | function Get-MetricValue { | Funcion auxiliar relacionada con: Get-MetricValue. |
| 84 | function Get-Score { | Funcion auxiliar relacionada con: Get-Score. |

## Apendice B - Variables y declaraciones de alto nivel

### Main.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 19 | @onready var building: BuildingModel = $World/BuildingModel |
| 20 | @onready var engine: SimulationEngine = $World/SimulationEngine |
| 21 | @onready var hud: HUD = $UI/HUD |
| 22 | @onready var visualizer: Visualizer = $World/Visualizer |
| 24 | const TIME_SCALE_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0] |
| 26 | var _simulation_paused: bool = false |
| 27 | var _validation_mode: bool = false |

### sim/BuildingModel.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name BuildingModel |
| 4 | const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd") |
| 22 | const OUTSIDE_ID: int = -1 |
| 25 | @export var outside_temp_c: float = 20.0 |
| 26 | @export var outside_o2: float = 0.209 |
| 29 | @export var vent_hrr_coeff_kw_per_sqrt_m5: float = 1500.0 |
| 32 | var building_template = preload("res://sim/templates/BuildingTemplate.gd").new() |
| 34 | @export_enum("simple_house", "ghanekar_bedroom_hallway") var template_name: String = "simple_house" |
| 37 | var room_rect_m: Dictionary[int, Rect2] = {} |
| 38 | var rooms: Dictionary = {} |
| 39 | var openings: Array = [] |

### sim/building/RoomModel.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name RoomModel |
| 4 | const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd") |
| 17 | var id: int = -1 |
| 18 | var name: String = "" |
| 19 | var kind: String = "" |
| 22 | var width_m: float = 0.0 |
| 23 | var length_m: float = 0.0 |
| 24 | var height_m: float = 2.5 |
| 27 | var temp_upper_c: float = 20.0 |
| 28 | var temp_lower_c: float = 20.0 |
| 31 | var o2: float = 0.209 |
| 34 | var smoke_kg: float = 0.0 |
| 35 | var smoke_prod_kg_s: float = 0.0 |
| 36 | var h_layer_m: float = 2.5 |
| 39 | var thermal_layer_m: float = 2.5 |
| 40 | var upper_gas_kg: float = 0.0 |
| 41 | var upper_energy_kj: float = 0.0 |
| 42 | var layer_150c_m: float = 2.5 |
| 45 | var co_kg: float = 0.0 |
| 46 | var co_upper_kg: float = 0.0 |
| 49 | var co2_kg: float = 0.0 |
| 52 | var fed: float = 0.0 |
| 55 | var svv_pct: float = 100.0 |
| 56 | var svv_worst_pct: float = 100.0 |
| 59 | var fuel_energy_MJ: float = 0.0 |
| 60 | var max_hrr_kw: float = 0.0 |
| 61 | var fuel_objects: Array = [] |
| 64 | var fire: FireModel = null |
| 65 | var fire_time_s: float = 0.0 |
| 66 | var hrr_kw: float = 0.0 |
| 67 | var hrr_target_kw: float = 0.0 |
| 68 | var fire_dormant_time_s: float = 0.0 |
| 69 | var fire_low_hrr_time_s: float = 0.0 |
| 70 | var fire_o2_extinguished: bool = false |
| 71 | var o2_hrr_factor: float = 1.0 |
| 72 | var retained_unburned_MJ: float = 0.0 |
| 73 | var ventilation_response_factor: float = 0.0 |
| 76 | var overpressure_pa: float = 0.0 |
| 79 | var flashover_triggered: bool = false |
| 80 | var fire_spread_exposure_s: float = 0.0 |

### sim/building/OpeningModel.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name OpeningModel |
| 4 | enum Type { DOOR, WINDOW } |
| 6 | const EPSILON: float = 0.001 |
| 7 | const WINDOW_FULL_OPEN_THRESHOLD: float = 0.5 |
| 9 | var a: int            # room id |
| 10 | var b: int            # room id, o -1 = exterior |
| 11 | var type: int = Type.DOOR |
| 13 | var width_m: float = 0.9 |
| 14 | var height_m: float = 2.0 |
| 15 | var sill_m: float = 0.0           # para ventanas (altura del alféizar) |
| 16 | var open_fraction: float = 1.0    # 0..1 |
| 17 | var opening_index: int = -1 |
| 18 | var wall_side: String = "" |
| 21 | var spill_coeff: float = 0.65 |

### sim/fire/FireModel.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name FireModel |
| 12 | var fuel_energy_MJ: float = 5000.0 |
| 13 | var remaining_fuel_MJ: float = 5000.0 |
| 14 | var max_burn_rate_kw: float = 2000.0 |
| 17 | var growth_alpha_kw_s2: float = 0.05 |
| 20 | var max_hrr_kw: float = 3000.0 |
| 23 | var secondary_hrr_gain_kw: float = 2500.0 |
| 26 | var flashover_hrr_multiplier: float = 2.2 |
| 27 | var flashover_min_hrr_kw: float = 300.0 |
| 30 | var o2_nominal: float = 0.209 |
| 31 | var o2_min_for_flame: float = 0.12 |
| 32 | var o2_consumption_kg_per_MJ: float = 0.20 |
| 35 | var smoke_yield_kg_per_MJ: float = 0.06 |

### sim/fire/FuelObjectModel.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name FuelObjectModel |
| 12 | enum State { |
| 21 | var id: String = "" |
| 22 | var name: String = "" |
| 23 | var kind: String = "" |
| 26 | var footprint_m2: float = 0.0 |
| 27 | var exposed_area_m2: float = 0.0 |
| 28 | var elevation_m: float = 0.0 |
| 31 | var fuel_energy_MJ: float = 0.0 |
| 32 | var remaining_fuel_MJ: float = 0.0 |
| 33 | var max_hrr_kw: float = 0.0 |
| 34 | var ignition_temp_c: float = 320.0 |
| 35 | var ignition_flux_kw_m2: float = 18.0 |
| 38 | var smoke_yield_kg_per_MJ: float = 0.00375 |
| 39 | var co_yield_kg_per_MJ: float = 0.00025 |
| 40 | var o2_consumption_kg_per_MJ: float = 0.076 |
| 43 | var state: int = State.COLD |
| 44 | var surface_temp_c: float = 20.0 |
| 45 | var incident_heat_flux_kw_m2: float = 0.0 |
| 46 | var exposure_s: float = 0.0 |
| 47 | var hrr_kw: float = 0.0 |
| 48 | var autoignite_ready: bool = false |
| 49 | var ignited_by_object_id: String = "" |
| 50 | var is_primary_ignition_source: bool = false |

### sim/fire/CombustionSystem.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name CombustionSystem |
| 4 | const FuelObjectModelScript = preload("res://sim/fire/FuelObjectModel.gd") |
| 5 | const FireModelScript = preload("res://sim/fire/FireModel.gd") |

### sim/smoke/SmokeModel.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name SmokeModel |
| 16 | var smoke_density_kg_m3: float = 0.9 |
| 17 | var smoke_temp_expansion_upper_weight: float = 0.45 |
| 18 | var smoke_temp_expansion_cap_c: float = 400.0 |
| 21 | var base_spill_kg_s_per_m2: float = 0.18 |
| 22 | var temp_push_factor: float = 0.008 |
| 23 | var max_spill_kg_s: float = 0.9 |
| 24 | var max_fraction_out_per_s: float = 0.025 |
| 25 | var target_smoke_resistance_coeff: float = 0.45 |
| 26 | var target_layer_block_start_m: float = 1.10 |
| 27 | var target_layer_block_full_m: float = 0.35 |
| 28 | var interior_spill_start_layer_m: float = 2.0 |
| 29 | var interior_spill_full_layer_m: float = 1.2 |
| 30 | var pressure_spill_min_delta_pa: float = 0.5 |
| 31 | var pressure_spill_ref_delta_pa: float = 8.0 |
| 32 | var pressure_spill_max_multiplier: float = 2.5 |
| 35 | var layer_relax_down: float = 0.10 |
| 36 | var layer_relax_up: float = 0.008 |
| 37 | var layer_recovery_gap_start_m: float = 0.20 |
| 38 | var layer_recovery_gap_full_m: float = 1.00 |
| 39 | var layer_recovery_boost_max: float = 6.0 |
| 40 | var layer_recovery_low_hrr_threshold_kw: float = 120.0 |
| 41 | var layer_recovery_low_hrr_boost: float = 1.6 |
| 44 | var spill_margin_m: float = 0.15 |
| 45 | var thermal_smoke_bridge_min_kg: float = 0.03 |
| 46 | var thermal_smoke_bridge_gap_start_m: float = 0.12 |
| 47 | var thermal_smoke_bridge_gap_full_m: float = 0.90 |
| 48 | var thermal_smoke_bridge_ref_kg_m3: float = 0.015 |
| 49 | var thermal_smoke_bridge_max_weight: float = 0.28 |

### sim/core/SimulationEngine.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name SimulationEngine |
| 4 | const CombustionSystemScript = preload("res://sim/fire/CombustionSystem.gd") |
| 5 | const GasExchangeSystemScript = preload("res://sim/core/GasExchangeSystem.gd") |
| 6 | const OxygenExchangeSystemScript = preload("res://sim/core/OxygenExchangeSystem.gd") |
| 7 | const SimulationLogWriterScript = preload("res://sim/core/SimulationLogWriter.gd") |
| 8 | const SimulationStateBuilderScript = preload("res://sim/core/SimulationStateBuilder.gd") |
| 9 | const ThermalSystemScript = preload("res://sim/core/ThermalSystem.gd") |
| 10 | const FireSpreadSystemScript = preload("res://sim/core/FireSpreadSystem.gd") |
| 11 | const GlassFailureSystemScript = preload("res://sim/core/GlassFailureSystem.gd") |
| 25 | @export var building_path: NodePath |
| 27 | var building: BuildingModel |
| 28 | var smoke_model: SmokeModel = SmokeModel.new() |
| 29 | var combustion_system: CombustionSystem = CombustionSystemScript.new() |
| 30 | var gas_exchange_system = GasExchangeSystemScript.new() |
| 31 | var oxygen_exchange_system = OxygenExchangeSystemScript.new() |
| 32 | var log_writer = SimulationLogWriterScript.new() |
| 33 | var state_builder = SimulationStateBuilderScript.new() |
| 34 | var thermal_system = ThermalSystemScript.new() |
| 35 | var fire_spread_system = FireSpreadSystemScript.new() |
| 36 | var glass_failure_system = GlassFailureSystemScript.new() |
| 38 | const o2_consumption_kg_per_MJ: float = 0.35 |
| 39 | const o2_nominal: float = 0.209 |
| 45 | @export var time_scale: float = 5.0 |
| 46 | var sim_time_s: float = 0.0 |
| 49 | @export var extinction_grace_s: float = 30.0 |
| 50 | @export var auto_finish_on_extinction: bool = true |
| 51 | var is_finished: bool = false |
| 52 | var _extinction_countdown: float = 30.0 |
| 54 | var _prev_open_fracs: Dictionary = {} |
| 56 | var _graphs_launched: bool = false |
| 63 | @export var glass_auto_break_enabled: bool = false |
| 65 | @export var glass_break_temp_c: float = 250.0 |
| 67 | @export var glass_break_temp_spread_c: float = 80.0 |
| 69 | @export var glass_open_rate_per_s: float = 0.15 |
| 71 | @export var glass_max_open_fraction: float = 0.85 |
| 77 | var smoke_generated_total_kg: float = 0.0 |
| 78 | var smoke_vented_total_kg: float = 0.0 |
| 79 | var smoke_deposited_total_kg: float = 0.0 |
| 85 | @export var ignition_room_id: int = 0 |
| 86 | @export var auto_ignite_on_ready: bool = true |
| 92 | @export var fire_alpha_kw_s2: float = 0.12 |
| 93 | @export var fire_max_hrr_kw: float = 3000.0 |
| 94 | @export var fire_secondary_hrr_gain_kw: float = 2500.0 |
| 99 | @export var kawagoe_coeff: float = 1500.0 |
| 101 | @export var fire_o2_nominal: float = 0.209 |
| 102 | @export var fire_o2_min_for_flame: float = 0.10 |
| 103 | @export var fire_o2_consumption_kg_per_MJ: float = 0.076  # Regla de Thornton: 1/13.1 MJ/kgO2 |
| 106 | @export var fire_smoke_yield_kg_per_MJ: float = 0.0088 |
| 107 | @export var fire_smoke_yield_low_o2_multiplier: float = 5.0 |
| 108 | @export var fire_smoke_basis_min_fraction: float = 0.40 |
| 109 | @export var fire_smolder_hrr_fraction: float = 0.03 |
| 110 | @export var fire_smolder_smoke_multiplier: float = 2.8 |
| 111 | @export var fire_retained_smoke_fraction: float = 0.38 |
| 112 | @export var fire_pool_smoke_fraction: float = 0.42 |
| 113 | @export var fire_latent_hrr_cap_min_fraction: float = 0.08 |
| 114 | @export var fire_latent_hrr_cap_max_fraction: float = 0.35 |
| 115 | @export var fire_latent_co_yield_multiplier: float = 0.06 |
| 116 | @export var fire_retained_co_fraction: float = 0.08 |
| 117 | @export var fire_pool_co_fraction: float = 0.40 |
| 118 | @export var fire_co_low_quality_yield_multiplier: float = 8.0 |
| 119 | @export var fire_co_max_effective_fraction: float = 0.22 |
| 120 | @export var fire_subvent_o2_floor: float = 0.085 |
| 121 | @export var fire_subvent_temp_start_c: float = 140.0 |
| 122 | @export var fire_subvent_temp_full_c: float = 420.0 |
| 123 | @export var fire_subvent_fill_start_fraction: float = 0.06 |
| 124 | @export var fire_subvent_fill_full_fraction: float = 0.18 |
| 125 | @export var fire_starvation_o2_factor: float = 0.003 |
| 132 | @export var co_base_yield_kg_per_MJ: float = 0.00025 |
| 133 | @export var co_max_yield_kg_per_MJ: float = 0.01250 |
| 139 | @export var co2_base_yield_kg_per_MJ: float = 0.0831 |
| 140 | @export var co2_min_yield_kg_per_MJ: float = 0.0594 |
| 144 | @export var fire_extinction_hrr_kw: float = 8.0 |
| 145 | @export var fire_extinction_delay_s: float = 240.0 |
| 146 | @export var fire_latent_enabled: bool = true |
| 147 | @export var fire_latent_extinction_delay_s: float = 300.0 |
| 148 | @export var fire_latent_hold_upper_temp_c: float = 140.0 |
| 149 | @export var fire_latent_hold_lower_temp_c: float = 60.0 |
| 150 | @export var fire_latent_min_remaining_fuel_MJ: float = 25.0 |
| 154 | @export var fire_max_active_s: float = 1800.0 |
| 156 | @export var fire_flashover_hrr_multiplier: float = 2.2 |
| 157 | @export var fire_flashover_min_hrr_kw: float = 300.0 |
| 162 | @export var thermal_feedback_coeff: float = 0.15 |
| 163 | @export var thermal_feedback_max: float = 1.5 |
| 166 | @export var fire_o2_hrr_rise_tau_s: float = 14.0 |
| 167 | @export var fire_o2_hrr_fall_tau_s: float = 32.0 |
| 168 | @export var fire_subvent_pyrolysis_min_fraction: float = 0.08 |
| 169 | @export var fire_subvent_pyrolysis_max_fraction: float = 0.18 |
| 170 | @export var fire_unburned_generation_fraction: float = 0.30 |
| 171 | @export var fire_unburned_capacity_MJ_per_m2: float = 1.20 |
| 172 | @export var fire_unburned_decay_per_s: float = 0.0025 |
| 173 | @export var fire_vent_response_temp_start_c: float = 140.0 |
| 174 | @export var fire_vent_response_temp_full_c: float = 300.0 |
| 175 | @export var fire_vent_response_rise_tau_s: float = 10.0 |
| 176 | @export var fire_vent_response_fall_tau_s: float = 30.0 |
| 177 | @export var fire_pool_release_tau_slow_s: float = 180.0 |
| 178 | @export var fire_pool_release_tau_fast_s: float = 18.0 |
| 179 | @export var fire_pool_release_max_fraction: float = 0.18 |
| 180 | @export var fire_hrr_rise_tau_s: float = 6.0 |
| 181 | @export var fire_hrr_fall_tau_s: float = 20.0 |
| 182 | @export var fire_backdraft_pool_threshold_MJ: float = 8.0 |
| 183 | @export var fire_backdraft_o2_max: float = 0.13 |
| 184 | @export var fire_backdraft_temp_min_c: float = 180.0 |
| 185 | @export var fire_backdraft_release_boost: float = 1.35 |
| 186 | @export var fire_remote_vent_path_enabled: bool = true |
| 187 | @export var fire_remote_vent_path_decay_per_door: float = 0.60 |
| 188 | @export var fire_remote_vent_path_min_signal: float = 0.02 |
| 189 | @export var fire_remote_vent_path_max_doors: int = 4 |
| 195 | @export var fire_spread_enabled: bool = false |
| 196 | @export var fire_spread_ignition_temp_c: float = 340.0  # temperatura de la capa superior para ignición por calor |
| 197 | @export var fire_spread_max_layer_m: float = 1.6 |
| 198 | @export var fire_spread_min_smoke_kg: float = 0.08 |
| 199 | @export var fire_spread_min_source_hrr_kw: float = 180.0 |
| 200 | @export var fire_spread_required_exposure_s: float = 35.0 |
| 201 | @export var fire_spread_exposure_decay_s: float = 12.0 |
| 206 | @export var passive_room_autoignite_enabled: bool = false |
| 212 | @export var flashover_temp_c: float = 500.0 |
| 213 | @export var flashover_layer_m: float = 1.2 |
| 214 | @export var flashover_head_height_m: float = 1.8 |
| 215 | @export var flashover_head_temp_c: float = 150.0 |
| 216 | @export var flashover_breathing_height_m: float = 0.9 |
| 217 | @export var flashover_breathing_temp_c: float = 600.0 |
| 218 | @export var flashover_require_tenability_loss: bool = true |
| 224 | @export var upper_to_lower_loss_rate: float = 0.025 |
| 225 | @export var upper_to_ambient_loss_rate: float = 0.008 |
| 226 | @export var lower_layer_warming_rate: float = 0.0120 |
| 227 | @export var max_upper_temp_c: float = 900.0 |
| 228 | @export var doorway_heat_exchange_coeff: float = 0.26 |
| 229 | @export var smoke_heat_mix_coeff: float = 0.025 |
| 230 | @export var retained_hot_layer_temp_start_c: float = 100.0 |
| 231 | @export var retained_hot_layer_temp_full_c: float = 350.0 |
| 232 | @export var retained_hot_layer_o2_start: float = 0.18 |
| 233 | @export var retained_hot_layer_o2_full: float = 0.10 |
| 234 | @export var retained_hot_layer_max_fraction: float = 0.85 |
| 235 | @export var outside_open_loss_area_fraction: float = 0.12 |
| 236 | @export var outside_open_ambient_loss_multiplier: float = 5.0 |
| 237 | @export var outside_open_wall_absorption_multiplier: float = 0.80 |
| 238 | @export var outside_open_upper_mix_rate: float = 0.10 |
| 239 | @export var outside_open_background_heat_exchange_kg_s_m2: float = 0.030 |
| 240 | @export var outside_open_background_heat_max_fraction_per_step: float = 0.020 |
| 241 | @export var outside_open_background_heat_carry_factor: float = 0.42 |
| 242 | @export var thermal_gradient_min_band_m: float = 0.20 |
| 243 | @export var thermal_gradient_max_band_m: float = 0.70 |
| 244 | @export var thermal_gradient_band_fraction: float = 0.35 |
| 245 | @export var floor_cooling_band_fraction: float = 0.24 |
| 246 | @export var floor_cooling_band_max_m: float = 0.35 |
| 247 | @export var survival_temp_threshold_c: float = 150.0 |
| 251 | @export var layer_150c_relax_down_per_s: float = 0.05 |
| 252 | @export var layer_150c_relax_up_per_s: float = 0.01 |
| 257 | @export var wall_absorption_rate: float = 0.003 |
| 260 | @export var wall_heat_transfer_w_m2k: float = 6.0 |
| 268 | @export var window_leakage_area_m2: float = 0.005 |
| 271 | @export var pressure_vent_threshold_pa: float = 2.0 |
| 277 | @export var ach_infiltration: float = 0.50  # Renovaciones de aire/hora por fugas del edificio |
| 278 | @export var interior_transport_enabled: bool = true |
| 279 | @export var interior_transport_speed_m_s: float = 0.28 |
| 280 | @export var interior_transport_min_distance_m: float = 0.50 |
| 281 | @export var interior_o2_transport_delay_multiplier: float = 1.60 |
| 282 | @export var doorway_o2_min_band_m: float = 0.25 |
| 283 | @export var doorway_o2_exchange_coeff: float = 1.00 |
| 284 | @export var doorway_o2_smoke_weight: float = 0.35 |
| 285 | @export var doorway_o2_pressure_weight: float = 0.65 |
| 286 | @export var doorway_o2_background_exchange_kg_s_m2: float = 0.035 |
| 287 | @export var doorway_o2_background_max_fraction_per_step: float = 0.015 |
| 288 | @export var doorway_o2_background_pressure_ref_pa: float = 1.5 |
| 289 | @export var doorway_o2_background_min_factor: float = 0.30 |
| 295 | @export var smoke_density_kg_m3: float = 0.18 |
| 296 | @export var smoke_temp_expansion_upper_weight: float = 0.45 |
| 297 | @export var smoke_temp_expansion_cap_c: float = 400.0 |
| 298 | @export var base_spill_kg_s_per_m2: float = 0.30 |
| 299 | @export var temp_push_factor: float = 0.005 |
| 300 | @export var max_spill_kg_s: float = 2.0 |
| 301 | @export var max_fraction_out_per_s: float = 0.18 |
| 302 | @export var layer_relax_down: float = 0.18 |
| 303 | @export var layer_relax_up: float = 0.015 |
| 304 | @export var layer_recovery_gap_start_m: float = 0.20 |
| 305 | @export var layer_recovery_gap_full_m: float = 1.00 |
| 306 | @export var layer_recovery_boost_max: float = 6.0 |
| 307 | @export var layer_recovery_low_hrr_threshold_kw: float = 120.0 |
| 308 | @export var layer_recovery_low_hrr_boost: float = 1.6 |
| 309 | @export var plume_fill_depth_coeff: float = 0.60 |
| 310 | @export var plume_fill_response_s: float = 12.0 |
| 311 | @export var plume_fill_max_fraction: float = 0.85 |
| 312 | @export var thermal_plume_depth_scale: float = 0.40 |
| 313 | @export var target_smoke_resistance_coeff: float = 0.20 |
| 314 | @export var target_layer_block_start_m: float = 0.65 |
| 315 | @export var target_layer_block_full_m: float = 0.10 |
| 316 | @export var interior_spill_start_layer_m: float = 2.0 |
| 317 | @export var interior_spill_full_layer_m: float = 0.8 |
| 318 | @export var pressure_spill_min_delta_pa: float = 0.5 |
| 319 | @export var pressure_spill_ref_delta_pa: float = 8.0 |
| 320 | @export var pressure_spill_max_multiplier: float = 2.5 |
| 321 | @export var postfire_cleanup_hot_stop_c: float = 90.0 |
| 322 | @export var postfire_cleanup_cool_full_c: float = 35.0 |
| 323 | @export var postfire_cleanup_pressure_stop_pa: float = 0.8 |
| 324 | @export var postfire_cleanup_pressure_full_pa: float = 0.10 |
| 325 | @export var smoke_settling_base_per_s: float = 0.00004 |
| 326 | @export var smoke_settling_bonus_per_s: float = 0.00018 |
| 327 | @export var co_postfire_purge_base_per_s: float = 0.0 |
| 328 | @export var co_postfire_purge_bonus_per_s: float = 0.0 |
| 329 | @export var outside_open_species_purge_base_per_s: float = 0.015 |
| 330 | @export var outside_open_species_purge_bonus_per_s: float = 0.11 |
| 331 | @export var outside_open_species_temp_start_c: float = 60.0 |
| 332 | @export var outside_open_species_temp_full_c: float = 220.0 |
| 333 | @export var outside_open_species_pressure_ref_pa: float = 4.0 |
| 334 | @export var outside_open_species_upper_bias: float = 0.80 |
| 340 | @export var enable_logging: bool = true |
| 341 | @export var log_interval_s: float = 10.0 |
| 342 | @export var log_file_path: String = "res://sim_log.txt" |

### sim/core/OxygenExchangeSystem.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name OxygenExchangeSystem |
| 4 | var o2_nominal: float = 0.209 |
| 5 | var ach_infiltration: float = 0.5 |
| 6 | var interior_transport_enabled: bool = true |
| 7 | var interior_transport_speed_m_s: float = 0.20 |
| 8 | var interior_transport_min_distance_m: float = 0.50 |
| 9 | var interior_o2_transport_delay_multiplier: float = 1.0 |
| 10 | var doorway_o2_exchange_coeff: float = 1.70 |
| 11 | var doorway_o2_background_exchange_kg_s_m2: float = 0.06 |
| 12 | var doorway_o2_background_max_fraction_per_step: float = 0.015 |
| 13 | var doorway_o2_background_pressure_ref_pa: float = 1.5 |
| 14 | var doorway_o2_background_min_factor: float = 0.30 |
| 15 | var _pending_o2_deliveries: Array[Dictionary] = [] |
| 16 | var _reserved_transport_o2_delta_kg: Dictionary = {} |

### sim/core/ThermalSystem.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name ThermalSystem |
| 17 | var _building: BuildingModel |
| 18 | var _smoke_model: SmokeModel |
| 21 | var upper_to_lower_loss_rate: float = 0.025 |
| 22 | var upper_to_ambient_loss_rate: float = 0.008 |
| 23 | var lower_layer_warming_rate: float = 0.012 |
| 24 | var wall_absorption_rate: float = 0.003 |
| 25 | var max_upper_temp_c: float = 900.0 |
| 26 | var doorway_heat_exchange_coeff: float = 0.26 |
| 27 | var smoke_heat_mix_coeff: float = 0.025 |
| 28 | var retained_hot_layer_temp_start_c: float = 100.0 |
| 29 | var retained_hot_layer_temp_full_c: float = 350.0 |
| 30 | var retained_hot_layer_o2_start: float = 0.18 |
| 31 | var retained_hot_layer_o2_full: float = 0.10 |
| 32 | var retained_hot_layer_max_fraction: float = 0.85 |
| 33 | var outside_open_loss_area_fraction: float = 0.12 |
| 34 | var outside_open_ambient_loss_multiplier: float = 16.0 |
| 35 | var outside_open_wall_absorption_multiplier: float = 0.80 |
| 36 | var outside_open_upper_mix_rate: float = 0.0 |
| 37 | var outside_open_background_heat_exchange_kg_s_m2: float = 0.030 |
| 38 | var outside_open_background_heat_max_fraction_per_step: float = 0.020 |
| 39 | var outside_open_background_heat_carry_factor: float = 0.42 |
| 42 | var thermal_gradient_min_band_m: float = 0.20 |
| 43 | var thermal_gradient_max_band_m: float = 0.70 |
| 44 | var thermal_gradient_band_fraction: float = 0.35 |
| 47 | var floor_cooling_band_fraction: float = 0.24 |
| 48 | var floor_cooling_band_max_m: float = 0.35 |
| 49 | var survival_temp_threshold_c: float = 150.0 |
| 52 | var layer_150c_relax_down_per_s: float = 0.35 |
| 53 | var layer_150c_relax_up_per_s: float = 0.03 |
| 56 | var plume_fill_depth_coeff: float = 0.60 |
| 57 | var plume_fill_response_s: float = 12.0 |
| 58 | var plume_fill_max_fraction: float = 0.85 |
| 61 | var layer_relax_down: float = 0.18 |
| 62 | var layer_relax_up: float = 0.015 |
| 65 | var doorway_o2_min_band_m: float = 0.25 |
| 66 | var doorway_o2_smoke_weight: float = 0.35 |
| 67 | var doorway_o2_pressure_weight: float = 0.65 |
| 68 | var pressure_spill_ref_delta_pa: float = 8.0 |
| 69 | var interior_spill_start_layer_m: float = 2.0 |
| 72 | var fed_hypoxia_enabled: bool = true |
| 73 | var fed_hypoxia_a: float = 8.13 |
| 74 | var fed_hypoxia_b: float = 0.54 |

### sim/core/GasExchangeSystem.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name GasExchangeSystem |
| 4 | var o2_nominal: float = 0.209 |
| 5 | var window_leakage_area_m2: float = 0.005 |
| 6 | var pressure_vent_threshold_pa: float = 2.0 |
| 7 | var ach_infiltration: float = 0.5 |
| 8 | var interior_transport_enabled: bool = true |
| 9 | var interior_transport_speed_m_s: float = 0.20 |
| 10 | var interior_transport_min_distance_m: float = 0.50 |
| 11 | var postfire_cleanup_hot_stop_c: float = 90.0 |
| 12 | var postfire_cleanup_cool_full_c: float = 35.0 |
| 13 | var postfire_cleanup_pressure_stop_pa: float = 0.8 |
| 14 | var postfire_cleanup_pressure_full_pa: float = 0.10 |
| 15 | var smoke_settling_base_per_s: float = 0.00004 |
| 16 | var smoke_settling_bonus_per_s: float = 0.00018 |
| 17 | var co_postfire_purge_base_per_s: float = 0.0 |
| 18 | var co_postfire_purge_bonus_per_s: float = 0.0 |
| 19 | var outside_open_species_purge_base_per_s: float = 0.0 |
| 20 | var outside_open_species_purge_bonus_per_s: float = 0.0 |
| 21 | var outside_open_species_temp_start_c: float = 60.0 |
| 22 | var outside_open_species_temp_full_c: float = 220.0 |
| 23 | var outside_open_species_pressure_ref_pa: float = 4.0 |
| 24 | var outside_open_species_upper_bias: float = 0.80 |
| 25 | var _pending_interior_deliveries: Array[Dictionary] = [] |

### sim/core/FireSpreadSystem.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name FireSpreadSystem |
| 15 | var _building: BuildingModel |
| 16 | var _smoke_model: SmokeModel |
| 17 | var _combustion_system: CombustionSystem |
| 20 | var fire_spread_enabled: bool = true |
| 21 | var fire_spread_ignition_temp_c: float = 340.0 |
| 22 | var fire_spread_max_layer_m: float = 1.6 |
| 23 | var fire_spread_min_smoke_kg: float = 0.08 |
| 24 | var fire_spread_min_source_hrr_kw: float = 180.0 |
| 25 | var fire_spread_required_exposure_s: float = 35.0 |
| 26 | var fire_spread_exposure_decay_s: float = 12.0 |

### sim/core/GlassFailureSystem.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name GlassFailureSystem |
| 14 | var _building: BuildingModel |
| 17 | var glass_break_temp_c: float = 250.0 |
| 18 | var glass_break_temp_spread_c: float = 80.0 |
| 19 | var glass_open_rate_per_s: float = 0.15 |
| 20 | var glass_max_open_fraction: float = 0.85 |
| 23 | var _glass_break_temps: Dictionary = {} |
| 25 | var newly_broken_indices: Array[int] = [] |

### sim/core/SimulationStateBuilder.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name SimulationStateBuilder |

### sim/core/SimulationLogWriter.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |
| 2 | class_name SimulationLogWriter |
| 4 | var enabled: bool = true |
| 5 | var interval_s: float = 10.0 |
| 6 | var log_file_path: String = "user://sim_log.txt" |
| 8 | var _next_log_time_s: float = 0.0 |
| 9 | var _resolved_log_file_path: String = "" |
| 10 | var _log_io_failed: bool = false |

### sim/templates/BuildingTemplate.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends RefCounted |

### sim/templates/ApartmentTemplates.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name ApartmentTemplates |

### sim/validation/CaseRunner.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node |
| 2 | class_name CaseRunner |
| 4 | const BuildingTemplateScript = preload("res://sim/templates/BuildingTemplate.gd") |
| 6 | @export var building_path: NodePath |
| 7 | @export var engine_path: NodePath |
| 8 | @export var reports_dir: String = "res://sim/validation/reports" |
| 9 | @export var auto_quit: bool = true |
| 11 | var building: BuildingModel |
| 12 | var engine: SimulationEngine |
| 14 | var _active: bool = false |
| 15 | var _case_name: String = "" |
| 16 | var _case_config: Dictionary = {} |
| 17 | var _cli_args: Dictionary = {} |
| 18 | var _metrics: Dictionary = {} |
| 19 | var _output_path: String = "" |
| 20 | var _baseline_path: String = "" |
| 21 | var _opening_events: Array = [] |
| 22 | var _incident_started: bool = false |
| 23 | var _runtime_error_reported: bool = false |

### ui/hud.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Control |
| 2 | class_name HUD |
| 10 | @export var show_status_panel: bool = false |
| 11 | @export var status_panel_room_id: int = 0 |
| 12 | @export var compact_status_panel: bool = true |
| 13 | @export var show_openings_panel: bool = true |
| 15 | @onready var status_panel: PanelContainer = $StatusPanel |
| 16 | @onready var status_label: Label = $StatusPanel/MarginContainer/StatusLabel |
| 17 | @onready var time_label: Label = $MarginContainer/TimeLabel |
| 18 | @onready var openings_panel: PanelContainer = $OpeningsPanel |
| 19 | @onready var opening_selector: OptionButton = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningSelector |
| 20 | @onready var opening_status_label: Label = $OpeningsPanel/MarginContainer/VBoxContainer/OpeningStatusLabel |
| 21 | @onready var btn_opening_close: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningClose |
| 22 | @onready var btn_opening_open: Button = $OpeningsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnOpeningOpen |
| 23 | @onready var btn_stop_graphs: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnStopGraphs") as Button |
| 24 | @onready var btn_time_back: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeBack") as Button |
| 25 | @onready var btn_play: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPlay") as Button |
| 26 | @onready var btn_pause: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnPause") as Button |
| 27 | @onready var btn_time_forward: Button = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/ButtonsRow/BtnTimeForward") as Button |
| 28 | @onready var time_scale_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/TimeScaleLabel") as Label |
| 29 | @onready var playback_status_label: Label = get_node_or_null("TimeControlsPanel/MarginContainer/VBoxContainer/InfoRow/PlaybackStatusLabel") as Label |
| 31 | var building: BuildingModel = null |
| 32 | var selected_opening_index: int = 0 |
| 33 | var _selector_sync_in_progress: bool = false |
| 34 | var _known_opening_count: int = -1 |

### view/Visualizer.gd

| Linea | Declaracion |
| --- | --- |
| 1 | extends Node2D |
| 2 | class_name Visualizer |
| 22 | @export var meters_to_px: float = 100.0 |
| 23 | @export var wall_thickness: float = 2.0 |
| 24 | @export var room_height_m_default: float = 2.4 |
| 26 | @export var background_color: Color = Color(0.10, 0.10, 0.11, 1.0) |
| 27 | @export var room_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0) |
| 28 | @export var room_fill_color: Color = Color(1.0, 1.0, 1.0, 0.02) |
| 30 | @export var auto_fit_to_view: bool = true |
| 31 | @export var view_margin_px: float = 20.0 |
| 33 | @export var ui_reserved_right_px: float = 200.0 |
| 34 | @export var ui_reserved_top_px: float = 0.0 |
| 40 | @export var show_room_fill: bool = true |
| 41 | @export var show_plan_atmosphere_overlay: bool = true |
| 42 | @export var show_fire_overlay: bool = false |
| 43 | @export var show_section_gauge: bool = true |
| 44 | @export var show_flashover_highlight: bool = true |
| 45 | @export var show_smoke_layer: bool = true |
| 46 | @export var show_smoke_layer_line: bool = true |
| 47 | @export var show_hot_layer_overlay: bool = true |
| 48 | @export var show_150c_layer: bool = true |
| 49 | @export var show_hrr_bar: bool = true |
| 50 | @export var show_openings: bool = true |
| 51 | @export var show_room_labels: bool = true |
| 52 | @export var show_room_name: bool = false |
| 53 | @export var show_opening_labels: bool = false |
| 59 | @export var smoke_base_color: Color = Color(0.32, 0.32, 0.36, 1.0) |
| 60 | @export var smoke_min_alpha: float = 0.30 |
| 61 | @export var smoke_max_alpha_bonus: float = 0.55 |
| 62 | @export var smoke_mass_reference_kg: float = 8.0 |
| 63 | @export var smoke_concentration_reference_kg_m3: float = 0.08 |
| 64 | @export var smoke_visible_threshold_kg: float = 0.01 |
| 65 | @export var smoke_layer_line_color: Color = Color(0.72, 0.72, 0.72, 0.95) |
| 66 | @export var smoke_layer_line_width: float = 2.0 |
| 67 | @export var hot_layer_color: Color = Color(1.0, 0.55, 0.15, 0.18) |
| 68 | @export var layer_150c_color: Color = Color(1.0, 0.10, 0.10, 0.95) |
| 69 | @export var layer_150c_line_width: float = 2.0 |
| 70 | @export var heat_room_tint_color: Color = Color(1.0, 0.42, 0.10, 1.0) |
| 71 | @export var fire_glow_color: Color = Color(1.0, 0.40, 0.10, 1.0) |
| 72 | @export var fire_core_color: Color = Color(1.0, 0.82, 0.35, 1.0) |
| 73 | @export var flashover_fill_color: Color = Color(1.0, 0.20, 0.05, 0.24) |
| 74 | @export var flashover_outline_color: Color = Color(1.0, 0.45, 0.05, 1.0) |
| 75 | @export var active_fire_outline_color: Color = Color(1.0, 0.62, 0.14, 1.0) |
| 76 | @export var low_o2_outline_color: Color = Color(0.85, 0.25, 0.25, 1.0) |
| 82 | @export var section_gauge_bg_color: Color = Color(0.0, 0.0, 0.0, 0.35) |
| 83 | @export var section_gauge_outline_color: Color = Color(1.0, 1.0, 1.0, 0.30) |
| 84 | @export var section_gauge_margin_px: float = 4.0 |
| 85 | @export var section_gauge_width_px: float = 16.0 |
| 86 | @export var section_gauge_min_height_px: float = 34.0 |
| 92 | @export var room_label_font_size: int = 10 |
| 93 | @export var room_label_color: Color = Color(1.0, 1.0, 1.0, 0.95) |
| 94 | @export var room_label_shadow: bool = true |
| 95 | @export var room_label_bg: bool = false |
| 96 | @export var room_label_bg_color: Color = Color(0.0, 0.0, 0.0, 0.40) |
| 97 | @export var room_label_padding: float = 4.0 |
| 98 | @export var room_label_offset: Vector2 = Vector2(4.0, 11.0) |
| 99 | @export var room_label_line_h: float = 11.0 |
| 100 | @export var room_label_tiny_threshold_w_px: float = 60.0 |
| 101 | @export var room_label_tiny_threshold_h_px: float = 40.0 |
| 102 | @export var room_label_compact_threshold_w_px: float = 85.0 |
| 103 | @export var room_label_compact_threshold_h_px: float = 72.0 |
| 104 | @export var room_label_medium_threshold_w_px: float = 135.0 |
| 105 | @export var room_label_medium_threshold_h_px: float = 120.0 |
| 111 | @export var hrr_bar_height_px: float = 4.0 |
| 112 | @export var hrr_bar_margin_px: float = 3.0 |
| 113 | @export var hrr_bar_max_kw: float = 3000.0 |
| 114 | @export var hrr_bar_color: Color = Color(1.0, 0.35, 0.15, 0.90) |
| 115 | @export var hrr_bar_bg_color: Color = Color(1.0, 1.0, 1.0, 0.08) |
| 121 | @export var door_color: Color = Color(0.30, 1.00, 0.40, 1.0) |
| 122 | @export var window_color: Color = Color(0.35, 0.70, 1.00, 1.0) |
| 123 | @export var window_broken_color: Color = Color(1.00, 0.55, 0.10, 1.0) |
| 124 | @export var window_open_color: Color = Color(1.00, 0.20, 0.05, 1.0) |
| 125 | @export var opening_line_width: float = 4.0 |
| 131 | @export var show_window_badge: bool = true |
| 132 | @export var window_full_open_threshold: float = 0.5 |
| 133 | @export var window_badge_size: Vector2 = Vector2(16.0, 7.0) |
| 139 | var state: Dictionary = {} |
| 140 | var rects_m: Dictionary[int, Rect2] = {} |
| 142 | @onready var building: BuildingModel = $"../BuildingModel" as BuildingModel |
