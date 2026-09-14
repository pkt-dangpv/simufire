from __future__ import annotations

from datetime import datetime
from pathlib import Path
import html
import re

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
OUT_MD = DOCS / "INFORME_TECNICO_CODIGO_SIMUFIRE.md"
OUT_PDF = DOCS / "INFORME_TECNICO_CODIGO_SIMUFIRE.pdf"
REPORT_DATE = "25/04/2026"

SOURCE_FILES = [
    "Main.gd",
    "project.godot",
    "main.tscn",
    "sim/BuildingModel.gd",
    "sim/building/RoomModel.gd",
    "sim/building/OpeningModel.gd",
    "sim/fire/FireModel.gd",
    "sim/fire/FuelObjectModel.gd",
    "sim/fire/CombustionSystem.gd",
    "sim/smoke/SmokeModel.gd",
    "sim/core/SimulationEngine.gd",
    "sim/core/OxygenExchangeSystem.gd",
    "sim/core/ThermalSystem.gd",
    "sim/core/GasExchangeSystem.gd",
    "sim/core/FireSpreadSystem.gd",
    "sim/core/GlassFailureSystem.gd",
    "sim/core/SimulationStateBuilder.gd",
    "sim/core/SimulationLogWriter.gd",
    "sim/templates/BuildingTemplate.gd",
    "sim/resources/default_fire_model.tres",
    "sim/validation/CaseRunner.gd",
    "sim/validation/run_case.ps1",
    "sim/validation/run_all_cases.ps1",
    "ui/hud.gd",
    "view/2d/Visualizer.gd",
    "view/3d/Visualizer3D.gd",
    "view/3d/camera/CameraOrbit3D.gd",
    "view/3d/smoke/SmokeAnimation3D.gd",
    "view/3d/smoke/SmokeBridgeMesh.gd",
    "view/3d/smoke/SmokeLayerVisuals.gd",
    "view/3d/smoke/SmokeOpeningCurtain3D.gd",
    "view/3d/smoke/SmokePuffSpriteFactory.gd",
    "view/3d/smoke/SmokeVolumeMaterialFactory.gd",
    "view/3d/fire/FireAnimation3D.gd",
    "view/3d/fire/FireMaterialFactory.gd",
    "view/3d/fire/FireMeshFactory.gd",
    "view/3d/furniture/FurnitureAssetLoader.gd",
    "view/3d/furniture/FurniturePlacement3D.gd",
    "view/3d/furniture/FurnitureShapeBuilder.gd",
    "view/3d/furniture/FurnitureStateVisuals.gd",
    "view/3d/furniture/FurnitureVisualClassifier.gd",
    "view/3d/geometry/RoomShellFactory.gd",
    "view/3d/interaction/ScreenPicking3D.gd",
    "view/3d/openings/OpeningPose3D.gd",
    "view/fp/FirstPersonController.gd",
    "view/fp/FPVisibilityOverlay.gd",
    "view/fp/FPOpeningVisuals.gd",
    "scripts/generate_fire_graphs.py",
    "scripts/download_fire_literature.ps1",
    "scripts/simulation/run_ghanekar_sweep.ps1",
    "scripts/simulation/run_ghanekar_micro_calibration.ps1",
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def line_count(path: Path) -> int:
    return len(read_text(path).splitlines())


def extract_functions(path: Path) -> list[tuple[int, str, str]]:
    out: list[tuple[int, str, str]] = []
    for line_no, line in enumerate(read_text(path).splitlines(), 1):
        stripped = line.strip()
        if path.suffix == ".gd" and stripped.startswith("func "):
            match = re.match(r"func\s+([^\(]+)", stripped)
            if match:
                out.append((line_no, stripped, match.group(1)))
        elif path.suffix == ".py" and stripped.startswith("def "):
            match = re.match(r"def\s+([^\(]+)", stripped)
            if match:
                out.append((line_no, stripped, match.group(1)))
        elif path.suffix == ".ps1" and stripped.startswith("function "):
            match = re.match(r"function\s+([^\s\(]+)", stripped)
            if match:
                out.append((line_no, stripped, match.group(1)))
    return out


def extract_top_decls(path: Path) -> list[tuple[int, str]]:
    out: list[tuple[int, str]] = []
    for line_no, line in enumerate(read_text(path).splitlines(), 1):
        if line.startswith(("extends ", "class_name ", "enum ", "const ", "@export", "@onready", "var ")):
            stripped = line.strip()
            if len(stripped) > 180:
                stripped = stripped[:177] + "..."
            out.append((line_no, stripped))
    return out


def describe_function(file_rel: str, name: str) -> str:
    manual = {
        ("Main.gd", "_ready"): "Inicializa referencias, detecta modo validacion, conecta senales del HUD y sincroniza el estado inicial.",
        ("Main.gd", "_physics_process"): "Avanza la simulacion cuando no esta pausada y actualiza visualizador e interfaz cada frame fisico.",
        ("Main.gd", "_build_ui_state"): "Toma el estado publico del motor y le anade datos de reproduccion para el HUD.",
        ("sim/core/SimulationEngine.gd", "step"): "Paso principal: fuego, oxigeno, termica, vidrio, gases, combustible pasivo, propagacion, clamps y log.",
        ("sim/core/SimulationEngine.gd", "_sync_auxiliary_services"): "Copia parametros exportados del motor hacia los subsistemas especializados.",
        ("sim/core/SimulationEngine.gd", "reset_simulation"): "Reinicia habitaciones, sistemas auxiliares, logs y opcionalmente prende la habitacion inicial.",
        ("sim/core/SimulationEngine.gd", "ignite_room"): "Crea/activa el FireModel de una sala y prepara su combustible para quemar.",
        ("sim/core/SimulationEngine.gd", "_build_room_combustion_context"): "Reune los parametros de combustion que necesita CombustionSystem para una sala.",
        ("sim/core/SimulationEngine.gd", "_outside_open_path_factor_for_room"): "Busca por puertas interiores abiertas una ruta hasta una apertura exterior y devuelve una senal atenuada de ventilacion remota.",
        ("sim/core/SimulationEngine.gd", "_try_trigger_flashover"): "Evalua temperatura, capas y tenabilidad para disparar flashover y aumentar HRR disponible.",
        ("sim/core/SimulationEngine.gd", "_kawagoe_factor_for_room"): "Calcula suma A*sqrt(H) de ventanas exteriores abiertas para limitar HRR por ventilacion local.",
        ("sim/fire/CombustionSystem.gd", "step_room_fire"): "Nucleo de combustion: HRR, O2, pirolisis, brasas, gases no quemados, CO/CO2, humo y extincion.",
        ("sim/fire/CombustionSystem.gd", "update_passive_room_fuel"): "Actualiza calentamiento, flujo radiativo y estado de combustibles pasivos de una sala sin fuego activo.",
        ("sim/fire/CombustionSystem.gd", "_can_sustain_latent_fire"): "Decide si un fuego puede mantenerse latente por temperatura, combustible y reserva de gases.",
        ("sim/core/OxygenExchangeSystem.gd", "step"): "Consume O2 por HRR y aplica entrada/intercambio por aperturas exteriores e interiores.",
        ("sim/core/OxygenExchangeSystem.gd", "_step_outside_opening_o2"): "Modelo de entrada de aire fresco por apertura exterior usando deficit de O2, capa caliente, presion y area baja.",
        ("sim/core/OxygenExchangeSystem.gd", "_step_interior_opening_o2"): "Intercambio de O2 entre salas por puerta abierta, con mezcla de fondo y flujo activo.",
        ("sim/core/OxygenExchangeSystem.gd", "_exchange_room_o2_active_flow"): "Transporta una parcela caliente de una sala a otra y una compensacion fria al contrario.",
        ("sim/core/ThermalSystem.gd", "step"): "Balance termico completo: capa alta, perdidas, mezcla, transferencia entre salas e isoterma 150 C.",
        ("sim/core/ThermalSystem.gd", "estimate_temperature_at_height_m"): "Evalua temperatura a una altura usando dos zonas, gradiente y enfriamiento junto al suelo.",
        ("sim/core/ThermalSystem.gd", "step_fed"): "Integra FED por CO, CO2 y deficit de O2 y actualiza la supervivencia SVV.",
        ("sim/core/ThermalSystem.gd", "build_interior_opening_flow_state"): "Precalcula sala caliente/fria, capas, engagement y diferenciales para intercambios por puerta.",
        ("sim/core/GasExchangeSystem.gd", "step_smoke"): "Mueve humo, CO, CO2 y O2: generacion, venting, transferencias, retrasos, ACH y limpieza.",
        ("sim/core/GasExchangeSystem.gd", "step_pressure_venting"): "Calcula sobrepresion por flotabilidad y purga exterior por fugas/ventanas.",
        ("sim/core/GasExchangeSystem.gd", "_apply_background_species_exchange"): "Intercambio suave de especies por gradientes cuando hay camino de ventilacion local o remoto.",
        ("sim/smoke/SmokeModel.gd", "compute_room_transfers"): "Calcula transferencias de humo por aperturas interiores cuando la capa invade el dintel.",
        ("sim/smoke/SmokeModel.gd", "compute_outside_vented_kg"): "Estima humo que sale al exterior segun capa, temperatura y presion.",
        ("sim/smoke/SmokeModel.gd", "recompute_layer_from_mass"): "Relaja la altura visible de humo hacia la altura que corresponde a la masa acumulada.",
        ("sim/core/FireSpreadSystem.gd", "step"): "Recorre puertas interiores abiertas y acumula exposicion para propagar incendio.",
        ("sim/core/GlassFailureSystem.gd", "step"): "Rompe progresivamente ventanas exteriores cuando la temperatura supera el umbral asignado.",
        ("sim/core/SimulationStateBuilder.gd", "build_state"): "Construye el diccionario publico consumido por HUD, visualizador, log y validacion.",
        ("sim/core/SimulationLogWriter.gd", "append_snapshot"): "Anade al log un bloque TIME y una linea por habitacion con magnitudes principales.",
        ("sim/validation/CaseRunner.gd", "_run_validation_loop"): "Ejecuta headless en pasos fijos hasta la duracion del caso y aborta si no avanza.",
        ("sim/validation/CaseRunner.gd", "_update_metrics"): "Recolecta picos, umbrales temporales, extincion, quiescencia y metricas globales.",
        ("sim/validation/CaseRunner.gd", "_compare_against_baseline"): "Compara metricas contra reglas expected/tolerance/min/max de la baseline JSON.",
        ("view/2d/Visualizer.gd", "_draw"): "Dibuja habitaciones, capas, etiquetas, barras HRR, badges de ventana y aperturas.",
        ("view/2d/Visualizer.gd", "_compute_svv_pct"): "Replica el criterio SVV combinando isoterma 150 C y FED para colorear etiquetas.",
        ("ui/hud.gd", "update_state"): "Actualiza tiempo, play/pause, controles y panel de sala a partir del estado publico.",
        ("scripts/generate_fire_graphs.py", "parse_log"): "Parsea sim_log.txt en series temporales por habitacion y eventos.",
        ("scripts/generate_fire_graphs.py", "plot_room"): "Genera PNGs de HRR, temperaturas, capas, gases y FED/SVV para una habitacion.",
        ("scripts/generate_fire_graphs.py", "find_inflections"): "Detecta cambios bruscos por diferencias en ventana movil.",
    }
    key = (file_rel, name)
    if key in manual:
        return manual[key]

    base = name.strip().lstrip("_")
    pretty = base.replace("_", " ")
    if base in ("ready",):
        return "Metodo de ciclo de vida de Godot que prepara referencias y estado inicial."
    if base in ("process", "physics_process"):
        return "Metodo periodico de Godot para actualizar escena o validacion."
    if base.startswith("on_"):
        return "Manejador de senal o boton; traduce una accion de interfaz en cambio de estado."
    if base.startswith("get_"):
        return "Devuelve " + pretty[4:] + " calculado o almacenado."
    if base.startswith("set_"):
        return "Asigna o sincroniza " + pretty[4:] + " respetando validaciones locales."
    if base.startswith("build_"):
        return "Construye una estructura de datos auxiliar: " + pretty[6:] + "."
    if base.startswith("create_"):
        return "Crea una instancia o plantilla: " + pretty[7:] + "."
    if base.startswith("load_"):
        return "Carga datos externos o de plantilla en objetos del programa."
    if base.startswith("reset"):
        return "Reinicia estado dinamico para volver a una condicion inicial conocida."
    if base.startswith("compute_"):
        return "Calcula " + pretty[8:] + " a partir del estado actual y parametros fisicos."
    if base.startswith("estimate_"):
        return "Estima " + pretty[9:] + " mediante una correlacion simplificada."
    if base.startswith("apply_"):
        return "Aplica cambios ya calculados sobre modelos, metricas o configuracion."
    if base.startswith("update_"):
        return "Actualiza " + pretty[7:] + " acumulando o relajando el estado previo."
    if base.startswith("sync_"):
        return "Sincroniza valores derivados entre modelos o subsistemas."
    if base.startswith("resolve_"):
        return "Resuelve referencias, rutas o valores efectivos desde entradas flexibles."
    if base.startswith("parse_"):
        return "Parsea texto/argumentos y los convierte en una estructura interna."
    if base.startswith("prepare_"):
        return "Prepara datos intermedios para una ejecucion posterior."
    if base.startswith("collect_"):
        return "Recolecta identificadores o datos desde una estructura mayor."
    if base.startswith("capture_"):
        return "Captura valores finales o instantaneos para reporte."
    if base.startswith(("finalize", "finish")):
        return "Cierra una ejecucion, escribe resultados y deja el sistema terminado."
    if base.startswith("draw_"):
        return "Dibuja un elemento visual concreto en el canvas."
    if base.startswith("call_"):
        return "Invoca un Callable de forma defensiva, con valor por defecto si no existe."
    if base.startswith(("is_", "has_", "can_", "should_")):
        return "Predicado booleano que decide si se cumple la condicion: " + pretty + "."
    if base.startswith(("open_", "close_")):
        return "Cambia el estado de una apertura del edificio."
    if base == "main":
        return "Punto de entrada del script."
    return "Funcion auxiliar relacionada con: " + pretty + "."


MANUAL_SECTIONS = [
    (
        "Resumen ejecutivo",
        [
            "Simufire es un simulador 2D de incendio compartimentado construido en Godot 4.7.1. No es un CFD: no resuelve Navier-Stokes ni malla espacial fina. Es un modelo reducido de zonas y balances globales que intenta capturar tendencias utiles para entrenamiento: crecimiento del HRR, agotamiento de oxigeno, estratificacion termica, movimiento de humo, CO/CO2, supervivencia y efecto de puertas/ventanas.",
            "Cada habitacion se representa como un volumen con dos capas termicas aproximadas: capa alta caliente y capa baja respirable. Encima de eso se lleva masa de humo, O2, CO, CO2, combustible restante, energia de capa alta y variables de tenabilidad. Las aperturas conectan habitaciones entre si o con el exterior.",
            "El programa se divide en modelos de datos, un motor coordinador y sistemas fisicos especializados. SimulationEngine.gd manda el orden de calculo, mientras CombustionSystem, OxygenExchangeSystem, ThermalSystem, GasExchangeSystem, SmokeModel, FireSpreadSystem y GlassFailureSystem hacen cada bloque de fisica.",
            "La interfaz no calcula fisica. HUD solo muestra controles y estado, y Visualizer dibuja una planta 2D con capas, HRR, gases y etiquetas. La validacion headless se apoya en CaseRunner y casos JSON con baselines reproducibles.",
        ],
    ),
    (
        "Mapa de arquitectura",
        [
            "El flujo principal es: Main.gd carga la escena, enlaza BuildingModel, SimulationEngine, HUD y Visualizer; BuildingModel construye salas y aperturas desde templates; SimulationEngine avanza la simulacion; SimulationStateBuilder empaqueta el estado; HUD, Visualizer, log y validacion consumen ese estado.",
            "Orden de un paso: 1) combustion y produccion de humo/gases, 2) consumo e intercambio de oxigeno, 3) balance termico y capas, 4) rotura de vidrio opcional, 5) transporte de humo/CO/CO2 y presion, 6) calentamiento de combustibles pasivos, 7) propagacion opcional, 8) clamps, logs y finalizacion.",
            "Este orden es un compromiso numerico sencillo: la combustion usa la atmosfera del paso anterior y produce demanda; oxigeno/ventilacion actualizan disponibilidad de aire; termica recalcula capas; transporte de gases mueve el resultado hacia otras estancias.",
        ],
    ),
    (
        "Unidades y convenciones",
        [
            "Las unidades dominantes son metros, m2, m3, segundos, kg, kW, MJ, grados Celsius, Pascales, fraccion de O2 alrededor de 0.209, y ppm para CO/CO2 en salidas.",
            "OUTSIDE_ID = -1 identifica el exterior. Una OpeningModel con b = -1 es puerta o ventana exterior. Las habitaciones tienen ids enteros y se guardan en diccionarios por id.",
            "Las capas se expresan como altura desde el suelo: h_layer_m para humo visible, thermal_layer_m para capa caliente efectiva y layer_150c_m para la isoterma de 150 C. Si la altura baja, la condicion empeora porque la capa caliente/humo desciende hacia zona respirable.",
        ],
    ),
    (
        "Modelo de datos",
        [
            "RoomModel concentra la memoria fisica de cada habitacion: geometria, temperatura alta/baja, oxigeno, humo, CO, CO2, FED/SVV, combustible, fuego activo, HRR, sobrepresion y exposicion a propagacion. reset_dynamic_state devuelve todo a ambiente.",
            "OpeningModel describe cada puerta o ventana: sala A, sala B o exterior, tipo, anchura, altura, alfeizar, fraccion abierta y lado de pared para dibujo. Sus metodos solo interpretan estado.",
            "FuelObjectModel permite tratar combustible por objetos aunque muchas salas usan un proxy legado de combustible de sala completa. Sus estados son COLD, HEATING, PYROLYZING, FLAMING, DECAYING y BURNED_OUT.",
            "FireModel guarda parametros sencillos de incendio, sobre todo crecimiento t-cuadrado: HRR = alpha * t^2 limitado por max_hrr_kw.",
        ],
    ),
    (
        "Guia de variables principales",
        [
            "En RoomModel, id/name/kind identifican la sala; width_m/length_m/height_m definen geometria; temp_upper_c/temp_lower_c son temperaturas de capa alta y baja; thermal_layer_m, upper_gas_kg, upper_energy_kj y layer_150c_m sostienen el modelo termico; o2, smoke_kg, smoke_prod_kg_s, h_layer_m, co_kg, co_upper_kg, co2_kg y overpressure_pa describen atmosfera, gases y presion.",
            "Tambien en RoomModel, fuel_energy_MJ, max_hrr_kw y fuel_objects representan combustible; fire, fire_time_s, hrr_kw, hrr_target_kw, fire_dormant_time_s, fire_low_hrr_time_s y fire_o2_extinguished describen evolucion del incendio; o2_hrr_factor suaviza la limitacion por oxigeno; retained_unburned_MJ almacena gases combustibles no quemados; ventilation_response_factor mide respuesta a nueva ventilacion; flashover_triggered y fire_spread_exposure_s guardan eventos criticos.",
            "En OpeningModel, a y b son habitaciones conectadas, con b = -1 como exterior; type distingue puerta/ventana; width_m, height_m y sill_m dan geometria vertical; open_fraction es la apertura efectiva 0..1; wall_side ayuda al dibujo de ventanas exteriores; spill_coeff modula derrame de humo por el hueco.",
            "En FuelObjectModel, state indica frio/calendando/pirolizando/en llama/decaimiento/agotado; remaining_energy_MJ es energia disponible; max_hrr_kw limita potencia; surface_temp_c y received_flux_kw_m2 acumulan calentamiento; ignition_temp_c, pyrolysis_temp_c y ignition_flux_kw_m2 son umbrales; smoke_yield_kg_per_MJ, co_yield_kg_per_MJ y co2_yield_kg_per_MJ controlan productos.",
            "En SimulationEngine, los exports se agrupan por comportamiento: time_scale y auto_finish_on_extinction controlan ejecucion; glass_* controla rotura de ventanas; fire_* controla crecimiento, O2, yields, latencia, gases no quemados, respuesta a ventilacion, backdraft y extincion; fire_remote_vent_path_* controla la ventilacion por rutas interiores; fire_spread_* controla propagacion; flashover_* controla umbrales de flashover; parametros thermal/smoke/gas/o2/log calibran termica, transporte, capas y salidas.",
            "En Visualizer, los exports no son fisica: son colores, grosores, toggles de dibujo, tamano de etiquetas, limites para seleccionar densidad visual y conversion metros-pixeles. Cambiarlos altera la lectura visual, no la simulacion.",
        ],
    ),
    (
        "Calculos y formulas clave",
        [
            "Crecimiento base del fuego: FireModel usa HRR_ideal = min(alpha * t^2, max_hrr_kw). CombustionSystem despues multiplica/limita ese valor por combustible restante, realimentacion termica, oxigeno, subventilacion, smolder y ventilacion.",
            "Oxigeno: el factor de llama normaliza o2 entre fire_o2_min_for_flame y fire_o2_nominal. El consumo usa kg_O2 = HRR_MW * fire_o2_consumption_kg_per_MJ * dt. El codigo usa 0.076 kg/MJ, equivalente aproximado de Thornton.",
            "Humo: la produccion base es smoke_kg_s = HRR_MW * smoke_yield_kg_per_MJ, con multiplicadores por combustion pobre, smolder y gases retenidos. La altura de capa se estima como H - volumen_humo/area, donde volumen_humo = smoke_kg / smoke_density corregido por expansion termica.",
            "Ventilacion por ventana local: el limite tipo Kawagoe se estima con hrr_max = kawagoe_coeff * sum(area_abierta * sqrt(altura)). No predice toda la dinamica, pero impone un techo de potencia cuando el fuego esta limitado por ventilacion exterior directa.",
            "Ventilacion remota: _outside_open_path_factor_for_room hace una busqueda por puertas abiertas hasta el exterior. Cada tramo se atenuta por fraccion de puerta, area relativa y fire_remote_vent_path_decay_per_door. El mayor camino encontrado se usa como senal de ventilacion disponible.",
            "Flujos por orificio: entradas/salidas por huecos usan la forma q = Cd * A * sqrt(2 * dp / rho), con dp derivado de presion, flotabilidad o deficit. Es una correlacion simplificada de flujo, no una resolucion CFD.",
            "Presion de capa caliente: GasExchangeSystem estima dp_buoyancy = rho_ext * g * h_smoke * max(0, 1 - T_ext/T_upper), relajado en el tiempo. Si supera pressure_vent_threshold_pa, purga humo/gases por fugas y huecos.",
            "Intercambio termico interior: ThermalSystem calcula flujo convectivo aproximado por puertas con area efectiva y raiz de g*h*DeltaT/T. La masa caliente transportada mueve tambien energia de capa alta y afecta a la sala fria.",
            "Suavizado temporal: muchos estados usan blend = 1 - exp(-dt/tau). Esto evita saltos cuando cambia O2, ventilacion o HRR objetivo, y hace que la respuesta sea estable en tiempo real.",
            "Tenabilidad: FED suma dosis por CO, hiper-ventilacion por CO2 y deficit de O2. SVV toma el peor caso entre criterio FED y criterio termico por altura de la isoterma 150 C.",
        ],
    ),
    (
        "Algoritmo de combustion",
        [
            "CombustionSystem.step_room_fire es el nucleo mas importante. Calcula un HRR ideal por curva t-cuadrado, lo limita por combustible restante y capacidad maxima, y luego lo modula por oxigeno, temperatura, humo, ventilacion y estado latente.",
            "El factor de oxigeno se calcula normalizando O2 entre fire_o2_min_for_flame y fire_o2_nominal. Ese factor se suaviza con constantes de subida/bajada para evitar oscilaciones bruscas.",
            "Cuando hay poco O2 o mucho humo caliente, el sistema reduce llama visible pero mantiene pirolisis/smolder si la sala esta caliente y queda combustible. Parte de la energia potencial pasa a retained_unburned_MJ, una reserva de gases combustibles no quemados.",
            "Al abrir una ventana local o existir una ruta de ventilacion remota, ventilation_response_factor sube. Esa respuesta permite quemar parte de la reserva no quemada, aumenta HRR y puede simular reactivacion/backdraft suave si hay gases, temperatura y O2 bajo.",
            "La produccion de humo parte de kg/MJ y aumenta con mala calidad de combustion. La produccion de CO sube cuando baja la calidad de combustion; CO2 baja cuando falta O2. Es una correlacion empirica para tendencias, no quimica detallada.",
        ],
    ),
    (
        "Ventilacion remota y problema R0/R2",
        [
            "El problema observado era que una ventana abierta en una sala distinta de R0 podia no sostener el incendio de R0. El codigo actual incorpora fire_remote_vent_path_enabled y _outside_open_path_factor_for_room para resolverlo.",
            "El algoritmo busca desde una sala hasta cualquier apertura exterior abierta siguiendo puertas interiores abiertas. Cada puerta reduce la senal por fire_remote_vent_path_decay_per_door, por su fraccion abierta y por un factor de area. El resultado 0..1 representa un camino de intercambio con el exterior aunque no sea una ventana de la misma sala.",
            "Esa senal se pasa a combustion, oxigeno, termica, gases y estado publico. Por eso una ventana abierta en R2 puede aportar entrada/salida de gases hacia R0 a traves de puertas abiertas, con atenuacion sencilla. Evita el fallo no realista de apagar el incendio por ignorar ventilacion remota.",
        ],
    ),
    (
        "Oxigeno",
        [
            "OxygenExchangeSystem conserva la idea de balance de masa de aire. Primero descuenta O2 consumido por HRR usando fire_o2_consumption_kg_per_MJ, derivado de la regla de Thornton. Despues repone/intercambia O2 por infiltracion, exterior e interiores.",
            "Para aperturas exteriores usa un esquema de orificio: area efectiva, densidad, presion/deficit y velocidad aproximada sqrt(2*dp/rho). Da mas importancia a la parte baja disponible bajo la capa caliente, porque es donde entra aire fresco.",
            "Para puertas interiores mezcla de fondo y flujo activo. La mezcla de fondo depende del area abierta, presion y ruta exterior. El flujo activo mueve una parcela caliente hacia la sala fria y una compensacion fria al contrario. Puede incluir retraso por distancia y velocidad de transporte.",
        ],
    ),
    (
        "Termica y estratificacion",
        [
            "ThermalSystem mantiene energia en capa alta (upper_energy_kj) y masa de gas alta (upper_gas_kg). Captura una fraccion del HRR en la capa superior, calcula perdidas a capa baja, ambiente y paredes, y recalcula alturas de capa.",
            "La densidad del gas se estima como 1.2 kg/m3 escalada por temperatura absoluta. La altura de capa caliente no es una frontera CFD; se estima desde energia, masa, humo, O2 y parametros de retencion.",
            "Entre salas, build_interior_opening_flow_state decide cual esta mas caliente, calcula engagement por capas/dintel, y luego se usa una correlacion de flujo por flotabilidad: area efectiva por raiz de g*h*DeltaT/T. Ese flujo mueve masa y energia.",
            "La temperatura a una altura se interpola entre capa baja y alta con una banda de gradiente y una banda fria junto al suelo. De ahi salen temp_at_0_9m_c, temp_at_1_8m_c y layer_150c_m.",
            "step_fed integra exposicion toxica por CO, hiper-ventilacion por CO2 y deficit de O2. SVV se calcula como el peor caso entre criterio termico por isoterma 150 C y criterio FED.",
        ],
    ),
    (
        "Humo, gases y presion",
        [
            "SmokeModel convierte produccion de humo en masa acumulada y estima altura de capa por volumen equivalente: masa / densidad, corregido por expansion termica. Si la capa baja por debajo del dintel de una apertura, puede derramar humo.",
            "GasExchangeSystem aplica los deltas: generacion, venting exterior, transferencias interiores, purga por ACH, deposicion post-incendio y purga de CO/CO2 con aperturas exteriores. Tambien mueve parte de la energia y masa de capa alta cuando viaja humo caliente.",
            "La sobrepresion se estima por flotabilidad de la capa caliente: rho*g*h*(1 - T_ext/T_upper), relajada en el tiempo. Si supera pressure_vent_threshold_pa, se purga por fugas y aperturas exteriores con una ley de orificio.",
            "El sistema distingue entre co_kg total y co_upper_kg en capa alta. Esto permite que transferencias superiores y purgas por ventana tengan sesgo hacia gases de la capa caliente.",
        ],
    ),
    (
        "Propagacion, vidrio y combustible pasivo",
        [
            "GlassFailureSystem asigna a cada ventana exterior un umbral de rotura con dispersion. Al superarse, aumenta open_fraction progresivamente hasta un maximo.",
            "FireSpreadSystem esta desactivado por defecto en varios casos de validacion. Cuando se activa, solo propaga por puertas interiores abiertas si la fuente tiene HRR suficiente y la sala objetivo esta caliente, con humo bajo o combustible pasivo pre-calentado.",
            "update_passive_room_fuel estima calentamiento superficial por radiacion/conveccion desde la capa caliente y por puertas. Sirve para transicionar objetos pasivos a HEATING/PYROLYZING y preparar autoignicion si se habilita.",
        ],
    ),
    (
        "Validacion y reproducibilidad",
        [
            "CaseRunner permite ejecutar Godot en modo headless con --validation-case. Carga un caso JSON, aplica overrides de habitaciones/aperturas/motor, ejecuta pasos fijos, calcula metricas y compara contra baseline.",
            "Los casos living_room_hallway, layer150_tenability y postfire_decay forman la bateria principal. tmp_r2_window_open_start cubre especificamente la ventilacion exterior remota abierta desde R2.",
            "Las baselines no son verdad fisica absoluta; son contratos de regresion. Si se cambia el modelo, puede ser correcto actualizar una baseline, pero conviene justificarlo.",
        ],
    ),
    (
        "Interfaz y visualizacion",
        [
            "HUD muestra tiempo, play/pause, escala temporal, boton de parar y generar graficas, selector de puertas/ventanas y un panel opcional de sala. No toca formulas fisicas.",
            "Visualizer dibuja la planta desde los rectangulos de BuildingModel. Usa el estado publico para colorear calor, humo, capa caliente, isoterma 150 C, HRR, estado de ventanas y etiquetas de gases/tenabilidad.",
            "La mini-seccion lateral representa alturas verticales de humo/capa caliente/isoterma dentro de cada sala, mientras la planta ofrece contexto espacial.",
        ],
    ),
    (
        "Limitaciones importantes",
        [
            "El modelo usa muchas correlaciones empiricas y parametros calibrables. Puede representar tendencias plausibles, pero no debe interpretarse como prediccion pericial exacta de un incendio real.",
            "La mezcla entre salas y el intercambio por ventanas son reducciones 0D/2-zonas; no hay chorros, turbulencia, geometria 3D real ni flujos transitorios complejos.",
            "La pirolisis remota de materiales en salas sin llama existe parcialmente por combustible pasivo, pero la propagacion y autoignicion estan controladas por toggles y umbrales. El siguiente frente para realismo multiestancia seria enriquecer objetos combustibles por sala y activar/calibrar propagacion pasiva.",
        ],
    ),
]


SCRIPT_EXPLANATIONS = {
    "Main.gd": ("Orquestador de la escena Godot.", [
        "Conecta BuildingModel, SimulationEngine, HUD y Visualizer.",
        "En cada physics frame llama a engine.step(delta) si procede y propaga estado a UI.",
        "Gestiona escala temporal y botones de reproduccion/graficas.",
    ]),
    "project.godot": ("Configuracion del proyecto Godot.", [
        "Declara nombre simufire, escena principal, Godot 4.7 y renderer.",
        "No contiene logica fisica.",
    ]),
    "main.tscn": ("Escena principal.", [
        "Define Main, World, Visualizer, Camera2D, BuildingModel, SimulationEngine, UI/HUD y CaseRunner.",
        "Tambien define paneles y botones usados por HUD.",
    ]),
    "sim/BuildingModel.gd": ("Modelo estructural del edificio.", [
        "Carga templates y construye RoomModel, OpeningModel y FuelObjectModel.",
        "Proporciona consultas de vecinos, aperturas, areas efectivas y HRR por ventilacion.",
    ]),
    "sim/building/RoomModel.gd": ("Estado fisico de una habitacion.", [
        "Agrupa geometria, atmosfera, capas, especies, tenabilidad, combustible y fuego.",
        "Solo calcula area, volumen y reset; la fisica vive fuera.",
    ]),
    "sim/building/OpeningModel.gd": ("Puerta o ventana.", [
        "Guarda conexion, tipo, dimensiones, fraccion abierta y geometria de dibujo.",
        "Calcula dintel, exterior/cerrada/abierta y etiqueta.",
    ]),
    "sim/fire/FireModel.gd": ("Parametros basicos de fuego.", [
        "Contiene crecimiento t-cuadrado, HRR maximo, O2 minimo y yield de humo.",
        "compute_hrr_kw devuelve min(alpha*t^2, max_hrr_kw).",
    ]),
    "sim/fire/FuelObjectModel.gd": ("Combustible por objeto.", [
        "Representa estado de ignicion, temperatura superficial, flujo recibido y energia restante.",
        "Puede crear un proxy legado para combustible de sala completa.",
    ]),
    "sim/fire/CombustionSystem.gd": ("Sistema de combustion.", [
        "Convierte combustible, O2, temperatura y ventilacion en HRR, humo, CO, CO2 y consumo de energia.",
        "Incluye llama, smolder, pirolisis subventilada, gases no quemados, respuesta a ventilacion, backdraft suave y extincion.",
    ]),
    "sim/smoke/SmokeModel.gd": ("Modelo de capa y derrame de humo.", [
        "Calcula produccion, altura visible, capa efectiva de derrame y masas transferibles.",
        "Usa densidad, expansion por temperatura, presion, dintel y resistencia por sala objetivo.",
    ]),
    "sim/core/SimulationEngine.gd": ("Motor coordinador y centro de parametros.", [
        "Contiene la mayoria de parametros exportados calibrables.",
        "Coordina todos los subsistemas, calcula ventilacion remota, flashover, clamps y graficas.",
    ]),
    "sim/core/OxygenExchangeSystem.gd": ("Balance de oxigeno.", [
        "Consume O2 segun HRR y repone/intercambia aire por ACH, exterior e interiores.",
        "Usa modelos de orificio y mezcla con retraso opcional.",
    ]),
    "sim/core/ThermalSystem.gd": ("Balance termico y tenabilidad.", [
        "Mantiene energia de capa alta, temperaturas, gradientes verticales, intercambio entre salas y criterio 150 C.",
        "Calcula FED/SVV y temperaturas a alturas de interes.",
    ]),
    "sim/core/GasExchangeSystem.gd": ("Transporte de humo, CO, CO2 y presion.", [
        "Aplica generacion de humo, venting exterior, intercambio interior, limpieza post-incendio, deposicion, ACH y purgas.",
        "Tambien actualiza sobrepresion y retira capa alta al ventilar humo.",
    ]),
    "sim/core/FireSpreadSystem.gd": ("Propagacion entre salas.", [
        "Acumula exposicion en salas vecinas a traves de puertas interiores abiertas.",
        "Llama a ignite_room cuando supera el tiempo requerido.",
    ]),
    "sim/core/GlassFailureSystem.gd": ("Rotura termica de ventanas.", [
        "Asigna umbrales con dispersion y abre progresivamente ventanas sobrecalentadas.",
    ]),
    "sim/core/SimulationStateBuilder.gd": ("Constructor de estado publico.", [
        "Genera el diccionario serializable por habitacion para UI, visualizador, log y validacion.",
    ]),
    "sim/core/SimulationLogWriter.gd": ("Logger textual.", [
        "Escribe sim_log.txt con bloques de tiempo y lineas por habitacion.",
        "Registra eventos de aperturas y snapshots finales para graficas.",
    ]),
    "sim/templates/BuildingTemplate.gd": ("Templates activos de edificios.", [
        "Define simple_house y ghanekar_bedroom_hallway: salas, rectangulos, puertas, ventanas y combustible.",
    ]),
    "sim/resources/default_fire_model.tres": ("Recurso Godot de FireModel.", [
        "Asset serializado de FireModel por defecto.",
    ]),
    "sim/validation/CaseRunner.gd": ("Runner de validacion headless.", [
        "Lee argumentos CLI, carga caso JSON, aplica overrides, corre pasos fijos, captura metricas y compara baseline.",
    ]),
    "sim/validation/run_case.ps1": ("Script PowerShell de un caso.", [
        "Lanza Godot headless con caso concreto, log temporal, timeout y ruta de reporte.",
    ]),
    "sim/validation/run_all_cases.ps1": ("Bateria de validacion.", [
        "Ejecuta casos principales y resume PASS/FAIL.",
    ]),
    "ui/hud.gd": ("Interfaz de controles.", [
        "Muestra tiempo, escala, play/pause, estado de aperturas, panel contextual y datos de sala.",
    ]),
    "view/2d/Visualizer.gd": ("Visualizador 2D.", [
        "Pinta habitaciones, capas, humo, calor, HRR, ventanas/puertas y etiquetas adaptativas.",
    ]),
    "view/3d/Visualizer3D.gd": ("Visualizador 3D.", [
        "Construye la vivienda, camaras, mobiliario, fuego, humo y efectos volumetricos de la escena 3D.",
    ]),
    "view/3d/camera/CameraOrbit3D.gd": ("Camara orbital 3D.", [
        "Calcula distancia de encuadre, arrastre orbital, zoom y transformacion de CameraRig/Camera3D.",
    ]),
    "view/3d/smoke/SmokeAnimation3D.gd": ("Animacion de humo 3D.", [
        "Actualiza posicion, escala, textura, frame y alpha de los puffs volumetricos de humo.",
    ]),
    "view/3d/smoke/SmokeBridgeMesh.gd": ("Malla auxiliar de humo 3D.", [
        "Genera la geometria diagonal que conecta capas de humo entre estancias sin mezclarla con el visualizador completo.",
    ]),
    "view/3d/smoke/SmokeLayerVisuals.gd": ("Capas visuales de humo 3D.", [
        "Crea y actualiza mascaras de techo y planos de capas termicas/humo.",
    ]),
    "view/3d/smoke/SmokeOpeningCurtain3D.gd": ("Cortina de humo en aberturas 3D.", [
        "Actualiza el puente de humo en puertas/ventanas segun apertura, capas vecinas y modo FP/3D.",
    ]),
    "view/3d/smoke/SmokePuffSpriteFactory.gd": ("Sprites de humo 3D.", [
        "Centraliza texturas de humo y crea sprites billboard para particulas/wisps.",
    ]),
    "view/3d/smoke/SmokeVolumeMaterialFactory.gd": ("Materiales de humo 3D.", [
        "Contiene shaders y parametros base para volumen de humo y mascara tenue de techo.",
    ]),
    "view/3d/fire/FireAnimation3D.gd": ("Animacion de fuego 3D.", [
        "Actualiza escala, posicion, flicker, lenguas de llama, luz y fuego de techo de cada foco visual.",
    ]),
    "view/3d/fire/FireMaterialFactory.gd": ("Materiales de fuego 3D.", [
        "Contiene shaders y parametros base para llamas y extension de fuego bajo techo.",
    ]),
    "view/3d/fire/FireMeshFactory.gd": ("Mallas de fuego 3D.", [
        "Construye las mallas de llama cruzada y fuego de techo con sus materiales visuales.",
    ]),
    "view/3d/furniture/FurnitureAssetLoader.gd": ("Carga de mobiliario visual.", [
        "Instancia assets de mobiliario FP reutilizados en 3D y prepara copias de materiales.",
    ]),
    "view/3d/furniture/FurniturePlacement3D.gd": ("Colocacion de mobiliario visual.", [
        "Encaja muebles dentro de la habitacion segun tamano/rotacion y calcula la altura visual de anclaje del fuego.",
    ]),
    "view/3d/furniture/FurnitureShapeBuilder.gd": ("Formas procedurales de mobiliario.", [
        "Construye sofas, camas, mesas, textiles, alfombras y otros combustibles visuales cuando no hay asset dedicado.",
    ]),
    "view/3d/furniture/FurnitureStateVisuals.gd": ("Estado visual de mobiliario.", [
        "Aplica carbonizacion, emision y brillo termico segun estado de combustion del objeto.",
    ]),
    "view/3d/furniture/FurnitureVisualClassifier.gd": ("Clasificador visual de mobiliario.", [
        "Mapea nombres/tipos de combustibles a arquetipos visuales y decide si una forma necesita reconstruirse.",
    ]),
    "view/3d/geometry/RoomShellFactory.gd": ("Geometria base de sala 3D.", [
        "Construye nodos de sala, suelo, paredes y etiqueta sin mezclarlo con el estado dinamico.",
    ]),
    "view/3d/interaction/ScreenPicking3D.gd": ("Picking de pantalla 3D.", [
        "Convierte posiciones de raton en sala, apertura o zona del modelo usando la camara 3D.",
    ]),
    "view/3d/openings/OpeningPose3D.gd": ("Pose de aperturas 3D.", [
        "Calcula posicion y tamano de puertas/ventanas en paredes exteriores o compartidas.",
    ]),
    "view/fp/FirstPersonController.gd": ("Controlador primera persona.", [
        "Gestiona camara FP, colision, postura, raycast de interaccion y entrada de teclado/raton.",
    ]),
    "view/fp/FPVisibilityOverlay.gd": ("Visibilidad FP.", [
        "Calcula el oscurecimiento del overlay y la visibilidad efectiva segun altura de ojos y capa de humo.",
    ]),
    "view/fp/FPOpeningVisuals.gd": ("Visuales de aperturas FP.", [
        "Calcula poses y geometria de puertas/ventanas sin tocar el estado del simulador.",
    ]),
    "scripts/generate_fire_graphs.py": ("Generador de graficas.", [
        "Lee sim_log.txt, parsea series/eventos, detecta inflexiones y guarda PNGs.",
    ]),
    "scripts/download_fire_literature.ps1": ("Descarga bibliografia tecnica.", [
        "Crea una libreria local de PDFs de FSRI, NIST, Springer, Figshare y otras fuentes.",
    ]),
    "scripts/simulation/run_ghanekar_sweep.ps1": ("Barrido de calibracion.", [
        "Genera casos temporales con variantes de parametros, ejecuta Godot y calcula ranking.",
    ]),
    "scripts/simulation/run_ghanekar_micro_calibration.ps1": ("Micro-calibracion.", [
        "Hace un barrido fino sobre parametros termicos/transporte y genera resumen JSON/Markdown.",
    ]),
}


CASE_NOTES = [
    ("cfast_r0_window_360.json", "simple_house con ventana de R0 abierta a 360 s y log para comparacion tipo CFAST."),
    ("ghanekar_bedroom_hallway.json", "Dormitorio/pasillo con metricas de flashover, O2, CO, CO2 y FED."),
    ("layer150_tenability.json", "Controla descenso de isoterma 150 C y temperatura respirable."),
    ("living_room_hallway.json", "Regresion basica de humo/calor de salon a pasillo."),
    ("long_smoke_o2_1800.json", "Corrida larga para observar acumulacion y recuperacion de humo/O2."),
    ("long_smoke_o2_debug.json", "Version corta con logging detallado."),
    ("postfire_decay.json", "Comprueba extincion, limpieza post-incendio, capas y humo residual."),
    ("tmp_r0_window_open_start.json", "Ventana de R0 abierta desde el inicio; ventilacion local."),
    ("tmp_r2_window_open_start.json", "Ventana de R2 abierta desde el inicio; valida ventilacion remota hacia R0."),
]


def build_markdown(inventory_rows: list[tuple[str, str, str]], baseline_rows: list[tuple[str, str]]) -> None:
    md: list[str] = []

    def h(level: int, text: str) -> None:
        md.append("#" * level + " " + text)
        md.append("")

    def p(text: str) -> None:
        md.append(text)
        md.append("")

    def bullets(items: list[str]) -> None:
        for item in items:
            md.append("- " + item)
        md.append("")

    def table(headers: list[str], rows: list[tuple]) -> None:
        md.append("| " + " | ".join(headers) + " |")
        md.append("| " + " | ".join(["---"] * len(headers)) + " |")
        for row in rows:
            md.append("| " + " | ".join(str(c).replace("|", "\\|").replace("\n", "<br>") for c in row) + " |")
        md.append("")

    h(1, "Informe tecnico del codigo de Simufire")
    p(f"Generado el {REPORT_DATE}. Repositorio: `{ROOT}`.")
    p("Alcance: scripts activos `.gd`, `.py`, `.ps1`, escena/configuracion Godot, templates, casos JSON y baselines. Se excluyen caches `.godot`, graficas generadas, reportes temporales, logs y salidas CFAST generadas. `sim/core/SimulationEngine.gd.bak` es backup historico no cargado por la escena activa.")

    for title, paragraphs in MANUAL_SECTIONS:
        h(2, title)
        for paragraph in paragraphs:
            p(paragraph)

    h(2, "Inventario de archivos activos")
    table(["Archivo", "Tipo", "Lineas"], inventory_rows)

    h(2, "Explicacion por script")
    for file_rel in SOURCE_FILES:
        title, paragraphs = SCRIPT_EXPLANATIONS[file_rel]
        h(3, file_rel)
        p(title)
        bullets(paragraphs)
        path = ROOT / file_rel
        decls = extract_top_decls(path) if path.suffix in (".gd", ".py", ".ps1") else []
        funcs = extract_functions(path) if path.suffix in (".gd", ".py", ".ps1") else []
        if decls:
            p("Declaraciones/variables principales:")
            table(["Linea", "Declaracion"], decls[:120])
            if len(decls) > 120:
                p(f"Nota: hay {len(decls)-120} declaraciones adicionales omitidas aqui; ver apendice B.")
        if funcs:
            p("Funciones:")
            table(["Linea", "Funcion", "Que hace"], [(line, sig, describe_function(file_rel, name)) for line, sig, name in funcs])

    h(2, "Casos de validacion")
    table(["Caso", "Objetivo"], CASE_NOTES)

    h(2, "Baselines")
    table(["Baseline", "Metricas controladas"], baseline_rows)

    h(2, "Apendice A - Indice exhaustivo de funciones")
    for file_rel in SOURCE_FILES:
        path = ROOT / file_rel
        funcs = extract_functions(path) if path.suffix in (".gd", ".py", ".ps1") else []
        if not funcs:
            continue
        h(3, file_rel)
        table(["Linea", "Funcion", "Descripcion"], [(line, sig, describe_function(file_rel, name)) for line, sig, name in funcs])

    h(2, "Apendice B - Variables y declaraciones de alto nivel")
    for file_rel in SOURCE_FILES:
        path = ROOT / file_rel
        decls = extract_top_decls(path) if path.suffix in (".gd", ".py", ".ps1") else []
        if not decls:
            continue
        h(3, file_rel)
        table(["Linea", "Declaracion"], decls)

    OUT_MD.write_text("\n".join(md), encoding="utf-8")


def build_pdf(inventory_rows: list[tuple[str, str, str]], baseline_rows: list[tuple[str, str]]) -> None:
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(name="TitleCenter", parent=styles["Title"], alignment=TA_CENTER, fontSize=22, leading=27, spaceAfter=18))
    styles.add(ParagraphStyle(name="H1x", parent=styles["Heading1"], fontSize=15, leading=18, spaceBefore=16, spaceAfter=8))
    styles.add(ParagraphStyle(name="H2x", parent=styles["Heading2"], fontSize=12.5, leading=15, spaceBefore=12, spaceAfter=6))
    styles.add(ParagraphStyle(name="Bodyx", parent=styles["BodyText"], fontSize=9.5, leading=13, spaceAfter=6))
    styles.add(ParagraphStyle(name="Smallx", parent=styles["BodyText"], fontSize=7.2, leading=8.8, spaceAfter=2))
    styles.add(ParagraphStyle(name="Cellx", parent=styles["BodyText"], fontSize=6.8, leading=8.2))
    styles.add(ParagraphStyle(name="HeaderCellx", parent=styles["BodyText"], fontSize=7.2, leading=8.6, textColor=colors.white))

    story = []

    def esc(value: object) -> str:
        return html.escape(str(value))

    def para(text: str, style: str = "Bodyx") -> None:
        story.append(Paragraph(esc(text), styles[style]))

    def heading(text: str, level: int = 1) -> None:
        story.append(Paragraph(esc(text), styles["H1x" if level == 1 else "H2x"]))

    def table(headers: list[str], rows: list[tuple], widths: list[float] | None = None, small: bool = True) -> None:
        if not rows:
            return
        header_style = styles["HeaderCellx"]
        cell_style = styles["Cellx" if small else "Bodyx"]
        data = [[Paragraph(esc(header), header_style) for header in headers]]
        for row in rows:
            data.append([Paragraph(esc(cell), cell_style) for cell in row])
        if widths is None:
            available = A4[0] - 3.0 * cm
            widths = [available / len(headers)] * len(headers)
        table_flowable = Table(data, colWidths=widths, repeatRows=1, splitByRow=1)
        table_flowable.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2f3a45")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#c9cdd1")),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 3),
            ("RIGHTPADDING", (0, 0), (-1, -1), 3),
            ("TOPPADDING", (0, 0), (-1, -1), 2),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f7f8fa")]),
        ]))
        story.append(table_flowable)
        story.append(Spacer(1, 6))

    story.append(Paragraph("Informe tecnico del codigo de Simufire", styles["TitleCenter"]))
    para(f"Generado el {REPORT_DATE}. Repositorio: {ROOT}")
    para("Alcance: scripts activos .gd, .py, .ps1, escena/configuracion Godot, templates, casos JSON y baselines. Se excluyen caches .godot, graficas generadas, reportes temporales, logs y salidas CFAST generadas. SimulationEngine.gd.bak es backup historico no cargado por la escena activa.")

    for title, paragraphs in MANUAL_SECTIONS:
        heading(title, 1)
        for paragraph in paragraphs:
            para(paragraph)

    heading("Inventario de archivos activos", 1)
    table(["Archivo", "Tipo", "Lineas"], inventory_rows, widths=[8.8 * cm, 2.5 * cm, 2.0 * cm])
    story.append(PageBreak())

    heading("Explicacion por script", 1)
    for file_rel in SOURCE_FILES:
        title, paragraphs = SCRIPT_EXPLANATIONS[file_rel]
        heading(file_rel, 2)
        para(title)
        for paragraph in paragraphs:
            para("- " + paragraph)
        path = ROOT / file_rel
        decls = extract_top_decls(path) if path.suffix in (".gd", ".py", ".ps1") else []
        funcs = extract_functions(path) if path.suffix in (".gd", ".py", ".ps1") else []
        if decls:
            para("Declaraciones y variables principales:", "Smallx")
            table(["Linea", "Declaracion"], decls[:80], widths=[1.4 * cm, 15.0 * cm])
            if len(decls) > 80:
                para(f"Tabla resumida: {len(decls)-80} declaraciones mas aparecen en el apendice B.", "Smallx")
        if funcs:
            para("Funciones:", "Smallx")
            table(["Linea", "Funcion", "Que hace"], [(line, sig, describe_function(file_rel, name)) for line, sig, name in funcs], widths=[1.2 * cm, 5.8 * cm, 9.4 * cm])

    heading("Casos de validacion", 1)
    table(["Caso", "Objetivo"], CASE_NOTES, widths=[5.2 * cm, 11.2 * cm], small=False)

    heading("Baselines", 1)
    table(["Baseline", "Metricas controladas"], baseline_rows, widths=[5.5 * cm, 10.9 * cm])
    story.append(PageBreak())

    heading("Apendice A - Indice exhaustivo de funciones", 1)
    for file_rel in SOURCE_FILES:
        path = ROOT / file_rel
        funcs = extract_functions(path) if path.suffix in (".gd", ".py", ".ps1") else []
        if not funcs:
            continue
        heading(file_rel, 2)
        table(["Linea", "Funcion", "Descripcion"], [(line, sig, describe_function(file_rel, name)) for line, sig, name in funcs], widths=[1.2 * cm, 5.8 * cm, 9.4 * cm])

    heading("Apendice B - Variables y declaraciones de alto nivel", 1)
    for file_rel in SOURCE_FILES:
        path = ROOT / file_rel
        decls = extract_top_decls(path) if path.suffix in (".gd", ".py", ".ps1") else []
        if not decls:
            continue
        heading(file_rel, 2)
        table(["Linea", "Declaracion"], decls, widths=[1.3 * cm, 15.1 * cm])

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 7)
        canvas.setFillColor(colors.HexColor("#555555"))
        canvas.drawString(1.5 * cm, 0.9 * cm, "Simufire - informe tecnico de codigo")
        canvas.drawRightString(A4[0] - 1.5 * cm, 0.9 * cm, f"Pagina {doc.page}")
        canvas.restoreState()

    pdf = SimpleDocTemplate(
        str(OUT_PDF),
        pagesize=A4,
        rightMargin=1.5 * cm,
        leftMargin=1.5 * cm,
        topMargin=1.4 * cm,
        bottomMargin=1.4 * cm,
    )
    pdf.build(story, onFirstPage=footer, onLaterPages=footer)


def main() -> None:
    DOCS.mkdir(exist_ok=True)
    inventory_rows = []
    for file_rel in SOURCE_FILES:
        path = ROOT / file_rel
        inventory_rows.append((file_rel, path.suffix or "(config)", str(line_count(path))))

    baseline_rows = []
    for path in sorted((ROOT / "sim/validation/baselines").glob("*.json")):
        text = read_text(path)
        metrics = re.findall(r'"([^"]+)"\s*:\s*\{', text)
        baseline_rows.append((path.name, ", ".join(metrics[:12]) + ("..." if len(metrics) > 12 else "")))

    build_markdown(inventory_rows, baseline_rows)
    build_pdf(inventory_rows, baseline_rows)
    print(OUT_MD)
    print(OUT_PDF)


if __name__ == "__main__":
    main()
