# Corpus 6: separar causa propuesta y efecto consultado

Versión histórica: el reservado se utilizó para corregir «por qué» y «debido a».
Sus 144 preguntas pasan a regresiones del corpus 7. Los JSON congelados y las
etiquetas de esta versión no se modifican.

144 preguntas: las 128 del corpus 5 pasan íntegramente a regresiones y 16
formulaciones nuevas constituyen el reservado. Conserva los mismos 14 historiales
sintéticos, sin añadir datos reales ni escenarios independientes. Las etiquetas
siguen pendientes de revisión física y docente externa.

El reservado incluye dirección causal inversa, otros pares de variables,
filtros de habitación y tiempo, cobertura incompleta y cambios bajo umbral.
También conserva preguntas de los otros seis tipos. Expectativas y entradas se
congelan en `freeze.json` antes de consultar Qwen. Los JSON anteriores y sus
etiquetas permanecen intactos; `parent_corpus_sha256` enlaza con el corpus 5.

```powershell
python simufire_ai/tests/run_all_tests.py
python simufire_ai/evaluate_questions.py --output evaluaciones/offline-v6.json
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev-v6.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout-v6.json
```

Cada salida debe usar una ruta nueva. No modificar código o prompts a partir
del reservado 6 en este bloque. Los reservados utilizados para desarrollar
correcciones pasan a regresiones y requieren una medición nueva.

Una pregunta ya clasificada como causal puede corregir su tema cuando tiene la
forma inequívoca «el incremento de X causó/provocó Y», con una variable medida
única en cada cláusula. El tema es el efecto Y: esto no demuestra su causa ni
crea hechos, valores o anclas de acción. Negaciones, alternativas, varias
cláusulas y efectos desconocidos o no medidos no reciben esta reparación.
Los planes guardados siguen rechazando selecciones alteradas.

`question_model_regressions_v5.json` conserva la respuesta cruda fallida anterior.
Su reparación no cuenta como un acierto del modelo. Se mantienen las métricas
`passed` y `answer_passed`, incluida `model_room_consistency`, con los criterios
del corpus 4. Los controles de procedencia son estructurales y no sustituyen
una revisión semántica ni la validación física de los detectores.
