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

La evaluación reproducible usa ahora el corpus 3: 76 regresiones y 16 nuevas
formulaciones reservadas sobre los mismos 11 historiales sintéticos. Las versiones
anteriores y sus entradas congeladas se conservan. Consulta
`tests/data/question_evaluation_v3/README.md` para ejecutar por separado contratos
offline, desarrollo con Ollama y el nuevo reservado. El evaluador distingue la
clasificación cruda de Qwen de la respuesta final validada.

Los controles explícitos preservan peticiones sobre detección de cambios y
enumeración de hechos registrados. No aportan hechos físicos: conservan la
certeza, causalidad, cobertura y procedencia del análisis. Las consultas sobre
magnitud, causa o definiciones no se sustituyen por una pregunta de detección.
Las pruebas reproducen las cuatro respuestas erróneas del reservado 2 sin red.
Los casos usados para corregir el código son regresiones; no constituyen una
medición independiente ni sustituyen una revisión física y docente.
