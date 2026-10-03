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
referencias y dependencias antes de guardar la respuesta. Los planes históricos
sin huella se aceptan únicamente con el archivo de contexto predeterminado,
para mantener los ejemplos anteriores; con cualquier contexto alternativo hay
que regenerar el plan. Las respuestas incluyen la huella y `fact_metadata` con
la certeza y el flag causal de los hechos seleccionados.

`source_events` es opcional en el contexto y contiene los eventos de ese mismo
análisis. El fixture de ventilación los incorpora. Un contexto alternativo sin
eventos conserva los enunciados de sus hechos, pero no añade diferencias
numéricas tomadas de los eventos del contexto normal. El contexto predeterminado
mantiene su lectura histórica de eventos para compatibilidad.

Para aislar otras ejecuciones, el constructor admite `--output`, el planificador
y el renderer admiten `--output-dir`, y el renderer admite `--plan-dir`. Los nombres
de salida siguen usando escenario y pregunta: emplear carpetas distintas si se
quieren conservar simultáneamente planes del mismo identificador para varios
contextos.
