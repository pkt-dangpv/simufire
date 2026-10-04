# SimuFire AI: Q&A reproducible

El motor y los detectores deterministas son la autoridad física. Qwen clasifica
la pregunta; el código resuelve los hechos y el conocimiento del contexto. El
renderer conserva las afirmaciones y la certeza de los hechos, separa la teoría
general y no transforma asociaciones temporales en relaciones causales.

Los hechos nuevos conservan el compartimento, la identidad de la apertura y el
intervalo de sus evidencias cuando están disponibles. Las dependencias se resuelven
a partir de sus acciones y eventos de origen, sin asignaciones fijas por número
de hecho. La numeración del ejemplo básico sigue siendo compatible.

Los detectores de ventilación comprueban los extremos de la apertura y no atribuyen
un mismo intervalo de medidas a una apertura concreta si hay varias intervenciones
locales. Una apertura entre dos compartimentos puede aportar evidencia a ambos;
una apertura en otro compartimento no se considera una intervención local.

Las limitaciones causales se vinculan a la observación y apertura correspondientes
del mismo compartimento. Los eventos nuevos exigen que la apertura esté dentro
del intervalo de la observación; para eventos históricos sin intervalo se usa la
apertura previa, sin otras acciones locales intermedias. Esto organiza la evidencia
y no demuestra causalidad. Los contextos rechazan ciclos, referencias inexistentes,
intervalos inválidos y dependencias entre compartimentos incompatibles.

Ejecutar desde la raíz del repositorio, con Python y `jsonschema` instalado.

## Hidráulica de una línea para entrenamiento

El módulo determinista calcula el balance de presión para un objetivo de caudal,
la intersección de curvas de bomba e instalación y el tiempo hasta la reserva
de agua. Usa perfiles con procedencia de los datos, curvas de bomba y lanza,
pérdidas de manguera y accesorios, longitud, desnivel y abastecimiento.

```powershell
python simufire_ai/hydraulics.py --profile simufire_ai/tests/data/hydraulic_profile_synthetic.json --output hydraulic_example.json
```

El perfil de ejemplo y sus curvas son ficticios. El objetivo de 400 L/min está
dado; el módulo no determina si ese caudal basta para extinguir un incendio.
La respuesta distingue presión suficiente, límite declarado de presión y agua
utilizable. Predice el punto con una configuración fija de bomba y lanza;
no selecciona un ajuste de bomba para alcanzar el objetivo.

El contrato `tactics/hydraulic_profile.schema.json` admite una única línea sin
otras salidas, régimen estacionario, un tipo de manguera y desnivel monotónico.
Interpola linealmente solo dentro del intervalo común de las curvas. Cada curva
y el objetivo deben identificar su fuente. Fuera del rango no predice caudal
ni autonomía; un límite de presión desconocido queda sin evaluar. No calcula
cavitación ni disponibilidad de presión en aspiración. El aporte se presupone
constante y adecuado para alimentar la bomba.

El resultado incluye la huella del perfil y del cálculo. La salida no sobrescribe
informes previos. Este comando no usa Ollama y aún no está conectado al Q&A de
ejecuciones ni a las decisiones tácticas de ventilación, extinción o rescate.
La ecuación de línea y el punto de funcionamiento se referencian al Manual de
incendios del CEIS Guadalajara, parte 2, edición 2015.10.05, páginas 77–79;
no se incorporan tablas ni datos de equipo de ese manual como valores por defecto.

## Pruebas deterministas

```powershell
python simufire_ai/tests/run_all_tests.py
```

La suite no requiere Ollama. `test_question_vl_e2e.py` genera un contexto nuevo
desde los cinco estados `vl_case_t*.json`, ejecuta el planificador con una
clasificación fija y ejecuta el renderer. Solo sustituye la llamada al modelo;
los detectores, la recuperación, la selección, la validación y la escritura/lectura
de los JSON son reales. Todo se genera en directorios temporales.

Se comprueban `FACT_010`, `VENTILATION_LIMITED_001`, `NIST_FIRE_DYNAMICS`,
`certainty: moderate` y `causal: false`, la ausencia de detecciones cuando no hay
evidencia, el rechazo de contextos mezclados y el renderizado actual de los cinco
modos de pregunta existentes. Los validadores devuelven un código de error ante
datos inválidos o ausentes para que la suite no comunique un falso éxito.

## Integración con Ollama (explícita y separada)

Con Ollama local en `localhost:11434` y el modelo `qwen3:1.7b` disponible:

```powershell
python simufire_ai/tests/test_question_vl_e2e.py --ollama
python simufire_ai/tests/test_qwen_condition_classifier.py
```

El primer comando ejecuta el mismo flujo completo usando Qwen real y archivos
temporales. El segundo prueba específicamente la clasificación. Ninguno forma
parte de `run_all_tests.py`; su resultado depende del servicio y del modelo local.

## Regenerar el ejemplo `question_vl_001`

```powershell
python simufire_ai/tests/build_ventilation_limited_test_context.py
python simufire_ai/llm/plan_question.py --context simufire_ai/tests/data/instructor_context/basic_room_001_vl_test_instructor.json --question-id question_vl_001 --question "¿El incendio estaba limitado por ventilación antes de abrir la puerta?"
python simufire_ai/llm/render_question_answer.py --context simufire_ai/tests/data/instructor_context/basic_room_001_vl_test_instructor.json --question-id question_vl_001
```

Los planes nuevos incluyen `source_context_sha256`, calculado por el código a
partir del contenido JSON del contexto. Cambiar hechos, certeza, flags causales,
teoría o eventos invalida el plan: hay que regenerarlo. Mover el archivo o cambiar
su formato JSON no lo invalida. Esta huella identifica el contenido; no certifica
que una fuente externa sea fiable.

El renderer verifica esquema, escenario, pregunta, identificadores únicos,
referencias y dependencias antes de guardar la respuesta. Todos los planes exigen
la huella, incluidos los del contexto predeterminado. Los ejemplos históricos
se han migrado. Las respuestas incluyen la huella y `fact_metadata` con la certeza
y el flag causal de los hechos seleccionados.

`source_events` es opcional en el contexto y contiene los eventos de ese mismo
análisis. El fixture de ventilación los incorpora. Un contexto alternativo sin
eventos conserva los enunciados de sus hechos, pero no añade diferencias
numéricas tomadas de los eventos del contexto normal. El ejemplo predeterminado
también incorpora sus eventos; el renderer nunca lee carpetas externas de eventos.

Para aislar otras ejecuciones, el constructor admite `--output`, el planificador
y el renderer admiten `--output-dir`, y el renderer admite `--plan-dir`. Los nombres
de salida siguen usando escenario y pregunta: emplear carpetas distintas si se
quieren conservar simultáneamente planes del mismo identificador para varios
contextos.

## Flujo completo por ejecución

`pipeline.py` recibe un escenario y una carpeta con estados JSON de una sola
ejecución. No utiliza las rutas de fixtures como fuentes implícitas. El análisis
no llama a Ollama; las preguntas sí lo llaman. Ejemplo desde la raíz del repositorio:

```powershell
$runs = Join-Path $env:LOCALAPPDATA 'SimuFireAI/runs'
python simufire_ai/pipeline.py analyze --scenario simufire_ai/scenarios/basic_room_001.json --states-dir simufire_ai/tests/data/ventilation_limited_states --run-id ensayo_vl_001 --output-root $runs
python simufire_ai/pipeline.py verify --run-dir "$runs/ensayo_vl_001" --replay
python simufire_ai/pipeline.py ask --run-dir "$runs/ensayo_vl_001" --question-id question_vl_001 --question "¿El incendio estaba limitado por ventilación antes de abrir la puerta?"
python simufire_ai/pipeline.py ask --run-dir "$runs/ensayo_vl_001" --question-id question_temperature_001 --question "¿Cómo cambió la temperatura de la capa superior?"
```

Cada carpeta de ejecución contiene `manifest.json`, `scenario.json`, `states.json`,
`thresholds.json`, `knowledge.json`, `events.json`, `facts.json` y `context.json`.
Los datos originales se copian y se ordenan de manera estable. El manifiesto
registra versiones del formato, pipeline, Python y jsonschema, huella del código
y esquemas del análisis, y huellas del contenido de cada archivo.

Cada pregunta queda en `questions/<question_id>/` con `question.json`, `plan.json`
y `answer.json`. El código asigna `run_id`, escenario y pregunta; Qwen no puede
elegirlos. El plan exige el mismo `run_id` y la misma huella del contexto. Antes
y después de consultar el modelo se verifica que el análisis siga intacto.

Se rechazan estados de otros escenarios, tiempos duplicados, compartimentos
incompatibles, versiones no soportadas, umbrales inválidos y números no finitos.
Un análisis válido puede tener cero eventos y cero hechos: no se inventa una
detección para llenar el contexto. Las acciones del escenario fuera del periodo
de estados guardados no se convierten en hechos de acciones ya ocurridas.

Una ejecución o pregunta existente no se sobrescribe: usa otro identificador para
conservar una nueva versión. Los identificadores admiten 1–80 caracteres ASCII,
números, guiones y guiones bajos; se rechazan rutas y nombres reservados de Windows.
Los archivos se publican juntos mediante una carpeta temporal y renombrado, con
exclusión entre escritores concurrentes. Un error ordinario no publica un resultado
parcial. Las huellas detectan cambios de contenido; no son firmas de autenticidad.

`verify` comprueba las huellas y referencias. `verify --replay` vuelve a ejecutar
los detectores usando los estados, umbrales y conocimiento guardados, y exige
igualdad completa del análisis. La reproducción exige el mismo código, esquemas,
Python y jsonschema; no consulta el conocimiento o la configuración actuales.
Esta garantía corresponde al análisis determinista. La clasificación de Ollama
se evalúa por separado y no se promete idéntica entre versiones del modelo.

Las funciones `build_analysis`, `analyze_run`, `load_run` y `ask_run` permiten
integrar este flujo en un servicio posterior. El planificador y renderer también
exponen `create_question_plan` y `render_question_answer`, conservando sus CLI.

`test_analysis_pipeline.py` forma parte de la suite sin Ollama y verifica el
flujo completo con una clasificación fija, dos ejecuciones del mismo escenario,
evidencia numérica distinta, múltiples preguntas, reproducción, escrituras
concurrentes y rechazo de cambios o errores. Integración explícita adicional:

```powershell
python simufire_ai/tests/test_analysis_pipeline.py --ollama
```

## Preguntas con ámbito y cobertura (contrato 0.4)

Los planes nuevos guardan la pregunta y un `scope`: compartimento, relación
temporal (`all`, `before`, `after`, `between`, `at`), ancla de acción e instantes.
El código comprueba identificadores, resuelve límites y dependencias, y calcula
el estado de la respuesta. El renderer vuelve a calcular la selección y rechaza
planes cuyos hechos, ámbito o estado hayan cambiado. Los planes históricos 0.3
siguen siendo legibles; para aplicar este contrato hay que regenerar el plan.

El ámbito temporal también se aplica a condición, observación, causalidad e
incertidumbre. Antes/después excluyen el instante de la acción; entre dos tiempos
incluye ambos extremos. Los límites se refieren al instante registrado del hecho
y, para cambios medidos, exigen que su intervalo completo encaje en la consulta.
No se divide ni interpola una medición para responder a un periodo más corto.
Los eventos históricos sin intervalo no se usan para describir cambios en un
periodo delimitado.

El patrón `ventilation_limited` tiene un tratamiento explícito: el detector lo
sitúa en su referencia anterior a la apertura y usa muestras posteriores como
confirmación. Se conserva ese instante, su certeza moderada y `causal: false`.
No se traslada el patrón a una consulta posterior ni se presenta como una
observación disponible en tiempo real antes de disponer de la confirmación.
`fact_provenance` conserva el intervalo completo de evidencia retrospectiva.

Los contextos del pipeline incluyen `analysis_coverage`, con compartimentos,
tiempos de muestreo y ventanas evaluables por detector. Esto describe requisitos
de entrada, sin modificar los umbrales ni decidir si se detecta un fenómeno.
Las evaluaciones del HRR y ventilación conservan sus predicados existentes,
incluidos sus casos con HRR previo cero. La regla del patrón de ventilación
limitada mantiene sus propios requisitos de HRR positivo e historial suficiente.

La respuesta expone `answer_status` y `topic_assessments` por tema y compartimento:

| Estado | Significado |
| --- | --- |
| `evidence_found` | Hay hechos pertinentes dentro del ámbito. |
| `not_detected` | No hay detección en las ventanas evaluables consultadas; no prueba ausencia. |
| `insufficient_data` | Faltan ventanas, historial o cobertura adecuada; no permite negar el fenómeno. |
| `unsupported` | Esta evaluación no está disponible en el analizador. |
| `theory_only` | Respuesta conceptual con conocimiento general de esta ejecución. |
| `knowledge_unavailable` | No hay una entrada de conocimiento para ese concepto. |
| `clarification_required` | Hay que identificar apertura, compartimento, periodo o tema. |
| `partial` | Los temas o compartimentos tienen resultados distintos. |
| `causal_not_established` | Hay evidencia temporal, pero no demuestra la causa propuesta. |

Si el contexto no incluye cobertura, el sistema no afirma una evaluación negativa.
Sin apertura o sin muestras suficientes antes/después, el detector actual de
ventilación limitada no puede emitir un diagnóstico negativo. Una consulta
general sobre varias habitaciones conserva evaluaciones separadas y etiquetas
de compartimento en el texto. Una consulta explícita sobre una habitación filtra
los hechos correspondientes.

`primary_fact_ids` identifica los hechos que responde el texto; `supporting_fact_ids`
conserva las dependencias para revisar su procedencia. El texto no introduce
acciones u observaciones de apoyo ajenas al ámbito o tema pedido. Ambas listas
conservan certeza y flags causales en sus metadatos. Los conceptos pueden utilizar
el conocimiento guardado aunque no haya hechos de ese tema: nunca se recupera
teoría de otra ejecución ni se interpreta la teoría como detección.

Qwen clasifica la intención y propone el ámbito. Identificadores, nombres y
rangos explícitos se comprueban contra la pregunta y el contexto. Ante varias
aperturas compatibles no se elige la primera arbitrariamente; el producto guarda
una solicitud de aclaración sin hechos ni fuentes inventados. Para continuar,
formula otra pregunta con un identificador nuevo y especifica elemento/instante.

```powershell
python simufire_ai/pipeline.py ask --run-dir "$runs/ensayo_vl_001" --question-id temp_interval --question "¿Cómo cambió la temperatura en room_01 entre 179 y 195 segundos?"
python simufire_ai/pipeline.py ask --run-dir "$runs/ensayo_vl_001" --question-id vl_after --question "¿Estaba limitado por ventilación después de abrir door_01?"
python simufire_ai/pipeline.py ask --run-dir "$runs/ensayo_vl_001" --question-id backdraft_check --question "¿Hubo backdraft?"
python simufire_ai/pipeline.py ask --run-dir "$runs/ensayo_vl_001" --question-id vl_concept --question "¿Qué significa incendio limitado por ventilación?"
```

Las observaciones actuales describen cambios detectados y conservan sus valores
de origen; este contrato no añade interpolación ni lecturas de variables nuevas.
Para usar la cobertura nueva, crea una ejecución nueva con el pipeline 0.2. Una
ejecución guardada con la versión anterior mantiene su contexto original.

`test_question_scope.py` forma parte de la suite sin Ollama. Incluye ventanas
incompletas, aperturas repetidas, varios compartimentos, límites numéricos,
certeza, causalidad y rechazo de planes alterados. La integración de siete
consultas concretas con el modelo real se ejecuta por separado:

```powershell
python simufire_ai/tests/test_question_scope.py --ollama
```

La evaluación reproducible usa ahora el corpus 7: 144 regresiones y 16 nuevas
formulaciones reservadas sobre los mismos 14 historiales sintéticos, incluidas
preguntas «por qué» y «debido a» con filtros temporales y espaciales. Las versiones
anteriores y sus entradas congeladas se conservan. Consulta
`tests/data/question_evaluation_v7/README.md` para ejecutar por separado contratos
offline, desarrollo con Ollama y el nuevo reservado. El evaluador distingue la
clasificación cruda de Qwen de la respuesta final validada.

Los controles explícitos preservan peticiones sobre detección de cambios y
enumeración de hechos registrados. No aportan hechos físicos: conservan la
certeza, causalidad, cobertura y procedencia del análisis. Las consultas sobre
magnitud, causa o definiciones no se sustituyen por una pregunta de detección.
Las pruebas reproducen las cuatro respuestas erróneas del reservado 2 sin red.
Los casos usados para corregir el código son regresiones; no constituyen una
medición independiente ni sustituyen una revisión física y docente.

Una habitación nombrada literalmente y sin ambigüedad manda sobre una propuesta
nueva del modelo que elija otra habitación existente. IDs inventados y planes
guardados alterados se rechazan. La evaluación conserva ese error del modelo en
`model_room_consistency`, separado de la respuesta final. Las peticiones directas
con una variable medida única pueden sustituir el tema genérico `fire_dynamics`;
no se sustituyen temas específicos contradictorios. Se reproducen también los
cuatro fallos del corpus 3 sin red. No cambian detectores ni umbrales físicos.

Los controles explícitos también preservan consultas de detección «hubo crecimiento»,
definiciones y peticiones de magnitud con una única variable medida literal. Estas
dos últimas conservan la variable nombrada aunque el modelo proponga otra; las
definiciones no incorporan hechos de la simulación. Las consultas causales o con
varias variables siguen dependiendo de clasificación o aclaración. El validador
rechaza cambios de intención/cabeceras temporales que contradigan la petición
explícita de un plan guardado 0.4. Se reproducen los tres errores del corpus 4 sin red.

En preguntas ya clasificadas como causales, una forma activa inequívoca con una
variable medida única a cada lado de «causó/provocó» conserva el efecto como tema.
La causa propuesta no es evidencia de una relación causal. Negaciones,
alternativas, varias cláusulas y efectos desconocidos siguen dependiendo de la
clasificación o aclaración. Se reproduce el error del corpus 5 sin red y se
comprueba la dirección inversa, la cobertura y el rechazo de planes alterados.

Las explicaciones directas «por qué aumentó/descendió X» y «X cambió debido a Y»,
con variables medidas únicas e inequívocas, conservan la intención causal aunque
el modelo proponga una observación. No atribuyen una causa: seleccionan el efecto
y sus limitaciones. Negaciones, conceptos, alternativas y efectos desconocidos
no se reparan con esa regla. Se reproducen los dos errores del corpus 6 sin red.


## Mediciones y revisión experta E01–E04

La versión 0.3 del pipeline conserva en `measurement_snapshot` el escenario,
los estados y los umbrales de la ejecución. Ese bloque forma parte de la huella
del contexto. Se validan los estados y se recomputan eventos y cobertura para
evitar mezclar entradas; al cargar una ejecución también se compara con sus
artefactos originales. Los contextos antiguos siguen siendo válidos, pero no
recuperan valores que no contienen: para disponer de estas mediciones se debe
crear un análisis nuevo desde los estados originales.

El renderer devuelve `measured_changes` por pares de muestras originales, con
habitación, ambos tiempos, valores, diferencia y, para HRR, porcentaje relativo
y tasa media. Exige que ambas muestras pertenezcan al ámbito temporal solicitado;
no interpola, cruza límites ni convierte dos valores en crecimiento continuo.
Una separación excesiva se marca como `sampling_gap` y no constituye una ventana
evaluable del detector. Un HRR inicial cero no tiene porcentaje relativo definido.

`answer_status` y `topic_assessments` mantienen su contrato de detección/cobertura;
`detector_assessment_status` explicita esa interpretación. Un estado `not_detected`
puede coexistir con un aumento físico medido. Por ejemplo, 100 → 120 kW es +20 %,
pero no cumple una regla estricta HRR final > 1.20 × HRR inicial. `criterion.met`
describe el predicado numérico; la elegibilidad de la ventana y los detectores
existentes conservan la decisión de registrar un evento. No cambian los umbrales.

`concurrent_measurements` muestra otras variables del mismo par y habitación
cuando ayudan a explicar E03/E04, sin atribuir causalidad entre ellas.
`opening_comparison` presenta, por separado, un par que rodea una apertura
identificada por un patrón previo de limitación por ventilación. Declara el
intervalo completo y el hecho relacionado; nunca lo presenta como evidencia
primaria de un periodo completamente posterior, ni cambia su cobertura.

El cambio geométrico de volumen de capa se calcula como área × descenso de
interfaz bajo la representación de capas horizontales del recinto rectangular.
Su tasa es neta: no equivale al caudal del penacho ni al volumen de humo puro.
La teoría de masa, energía, arrastre y expansión se identifica con NIST CFAST;
no se deduce retención del 100 % a partir de una puerta cerrada. La posibilidad
de flashover inducido por ventilación se presenta como teoría condicional, no
como una detección. Aumento de HRR/temperatura no basta para declarar flashover
o un régimen limitado por combustible.

Las pruebas offline de `tests/test_measurement_evidence.py` comprueban estos
casos y el rechazo de mezclas y metadatos alterados. Las integraciones reales
con Ollama se siguen ejecutando explícitamente y por separado. La revisión
humana de la nueva redacción y del uso docente continúa pendiente.


## Presentación docente tras la segunda revisión experta

`response_status` es el resultado principal para la presentación docente de las
respuestas 0.4 con mediciones: `measured_change`, `unchanged_endpoints` o
`ventilation_response_compatible`, cuando corresponde. Ante una aclaración,
concepto o fenómeno no evaluado conserva el estado de la consulta. No declara
causalidad ni un nuevo régimen físico. `answer_status` y
`detector_assessment_status` conservan el contrato técnico de detección/cobertura
para compatibilidad; no deben usarse como etiqueta principal de una observación
que sí contiene cambios medidos. Ninguna bandera física o umbral se modifica.

En E04 la primera línea afirma el aumento real del 20 % (+20 kW) y la nota
siguiente explica por qué no se activó la alerta estricta >20 %. Se elimina la
advertencia de ausencia cuando los valores ya documentan un cambio. Para
extremos iguales se aclara que la igualdad se refiere solo a esas muestras.

En E02 se presenta la recuperación de O₂ y HRR y la inversión de su decaimiento
previo alrededor de la apertura, como respuesta compatible con nueva ventilación.
La clasificación de régimen posterior continúa pendiente. Dos porcentajes de
O₂ no son un balance de caudales másicos ni demuestran que dejó de limitar la
combustión. La comparación conserva ambos tiempos; no se presenta como un
intervalo completamente posterior ni como una relación causal demostrada.

El cierre de E03 explica cualitativamente el llenado por el penacho en el marco
de dos zonas; lo pendiente es desglosar cuantitativamente los términos del balance.
La aprobación del experto de E01 no convierte «posible» en probabilidad calibrada.

El evaluador usa ahora el corpus 8: los 160 casos anteriores son regresiones y
no hay reservado nuevo. Cuatro expectativas de redacción se versionaron
explícitamente a petición del experto; los corpus anteriores siguen intactos.
Las explicaciones nuevas se presentan para revisión humana antes del piloto.

## Segunda tanda de revisión experta: E05–E08

Las respuestas de temperatura añaden las aperturas registradas del mismo recinto
y un resumen de la caída previa cuando el ámbito consultado incluye sus muestras.
Una consulta con intervalo explícito no recupera mediciones externas. La apertura
de una habitación distinta no se atribuye al recinto consultado; se conserva la
distinción entre asociación temporal y causa física.

`BACKDRAFT_001` aporta teoría docente contrastada con el estudio de NIST de 2022,
sin añadir un detector ni un nivel de riesgo. La respuesta de presencia conserva
`unsupported`, muestra una muestra disponible del ámbito y explica qué datos de
combustible gaseoso, mezcla e ignición faltan. O₂ <10 % no es un requisito
universal de backdraft ni ≥10 % lo descarta. Un HRR positivo no demuestra llama
abierta. La teoría solo se utiliza si pertenece al contexto ligado al plan.

Para una pregunta de condición de ILV anterior a aperturas repetidas del mismo
elemento inicialmente cerrado, sin otras intervenciones locales, se explica el
tramo común previo a la primera apertura. Se conservan las acciones y se señala
su repetición sin cierre registrado. El resultado docente es
`preopening_observations`; la cobertura interna sigue siendo `insufficient_data`
y no se inventa un hecho de ILV. Aperturas diferentes, cierre/reapertura, estado
inicial abierto, preguntas causales y periodos posteriores siguen requiriendo
desambiguación. Los tiempos explícitos del usuario conservan su ámbito.

`teaching_context` registra las observaciones y acciones suplementarias, con
tiempos, recinto y `causal: false`. El evaluador verifica su correspondencia con
el mismo contexto. El corpus 9 conserva 160 regresiones y entradas físicas
históricas; seis expectativas de ámbito/presentación de E08 están versionadas
explícitamente. No hay un reservado nuevo. La suite incluye
`test_expert_followup.py` y sigue sin depender de Ollama.

## Catálogo de equipos y consulta de referencias por internet

`tactics/catalog/equipment_and_references.json` contiene siete fichas iniciales:
Rosenbauer N25, Godiva Prima P2_2010, AWG Turbo 2130 y 2400 estándar, GH Titan
3F de 45 y 70 mm y LEADER MT236 NEO2. Incluye tres referencias tácticas de NIST
con ámbito experimental, datos que requiere un ejercicio y límites de aplicación.
Las fuentes conservan URL, edición, pasaje consultado, fecha y huella del documento
recuperado. La lectura es parcial; las fichas esperan revisión experta.

```powershell
python simufire_ai/equipment_catalog.py --query "bomba"
python simufire_ai/equipment_catalog.py --query "ventilación" --category tactical
python simufire_ai/equipment_catalog.py --query "Prima P2 2010 LP curve" --online --source godiva --evidence-dir work/catalog_evidence --output work/consulta_curva.json
python simufire_ai/equipment_catalog.py --online --fetch-url "https://www.godiva.co.uk/media/pdf/Prima_P2_2010_LP_Curve_DS626.pdf" --evidence-dir work/catalog_evidence --output work/curva_recuperada.json
```

El catálogo es una base de referencias consultable; no declara que esos equipos
estén disponibles en el servicio o en la simulación. Los puntos nominales de bomba
no constituyen una curva a rpm fijas. Los caudales seleccionables de una lanza a
6 bar son posiciones distintas del selector. Las gráficas Godiva DS626 y DS630
se registran por separado y esperan digitalización con incertidumbre, comprobación
de condiciones de ensayo y revisión. `to_hydraulic_component` rechaza estas fichas
incompletas: no genera un perfil hidráulico inventando puntos.

La presión de rotura de una manguera se conserva separada de la presión de trabajo;
el racor y el montaje pueden limitar esta última. Caudal de aire libre y AMCA 240
son magnitudes de ensayo diferentes y no equivalen al flujo entregado al edificio.
La ficha PDF y la página de LEADER discrepan en masa, dimensiones, ángulo y
posición: los valores conflictivos se conservan, sin elegir una versión automáticamente.

Internet está desactivado por defecto. `--online` permite buscar enlaces en un
índice público de fabricante o NIST y recuperar HTML/PDF de los dominios admitidos.
Es una búsqueda limitada a esa página: no es un buscador de toda la web ni ejecuta
JavaScript, sigue paginación o garantiza encontrar todo. No encontrar un enlace
no demuestra que el documento no exista. Se puede recuperar una URL conocida
mediante `--fetch-url`. No se envían estados de simulación ni credenciales.

Las consultas aplican HTTPS, dominios explícitos, conexión a direcciones públicas
comprobadas con validación TLS del nombre, redirecciones limitadas, tiempo y tamaño
de descarga acotados. Cada recuperación conserva fecha, URL final, SHA-256 y
cuerpo original como evidencia externa no validada. Los documentos y sus posibles
instrucciones no se ejecutan ni modifican el catálogo. `usable_for_calculation`
permanece `false`; incorporar un dato exige transcripción, condiciones y revisión.
Los informes existentes no se sobrescriben.

La consulta todavía no se integra en el Q&A ni activa recomendaciones de caudal,
ventilación, técnica o supervivencia. Las referencias NIST constituyen evidencia
para elaborar reglas revisables; no cambian los detectores, su certeza o causalidad.
H01–H07 siguen siendo casos sintéticos pendientes de revisión experta.

`test_equipment_catalog.py` y `test_online_sources.py` se ejecutan en la suite
determinista con dobles de transporte, sin internet ni Ollama. Las recuperaciones
reales se comprueban por separado y no son un requisito de la suite offline.
