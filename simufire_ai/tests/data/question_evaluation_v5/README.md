# Corpus 5: peticiones explícitas y ámbito de las mediciones

Versión histórica: el reservado se utilizó para desarrollar la corrección del
efecto en preguntas causales. Sus 128 preguntas son ahora regresiones del corpus 6;
las entradas congeladas y etiquetas de esta versión se conservan intactas.

128 preguntas: las 108 del corpus 4 pasan a regresiones y 20 formulaciones nuevas
forman el reservado. Incluyen los siete tipos de petición y un historial sintético
adicional de Garaje, con cambios que no alcanzan los umbrales de HRR, temperatura
y descenso de interfaz. Hay 14 historiales/variantes sintéticas en total, pendientes
de revisión física y docente independiente; no son datos reales de simulador.

Los JSON congelados anteriores y las etiquetas heredadas no cambian.
`parent_corpus_sha256` enlaza con el corpus 4. `freeze.json` fija entradas,
clasificaciones de referencia, expectativas, umbrales y conocimiento antes de
consultar Qwen. Las expectativas nuevas se revisan en el modo offline antes de
la primera medición real.

```powershell
python simufire_ai/tests/run_all_tests.py
python simufire_ai/evaluate_questions.py --output evaluaciones/offline-v5.json
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev-v5.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout-v5.json
```

Cada ruta de salida debe ser nueva. `--corpus-dir` permite reproducir otras
versiones, pero los reservados usados para desarrollar ajustes ya son regresiones.
No ajustar código ni prompts con el resultado del reservado 5 en este bloque.

Se mantienen `passed`, incluyendo las métricas crudas `model_*`, y
`answer_passed`, que excluye solo estas métricas y verifica el contrato final.
`model_room_consistency` mantiene su criterio del corpus 4: comprueba
contradicciones ante una única habitación literal, no toda la precisión del ámbito.

Los controles explícitos reconocen «hubo crecimiento» como consulta de detección.
Una definición directa o petición de magnitud con una única variable medida
literal conserva esa variable aunque el modelo proponga otra. Definiciones solo
usan teoría del contexto; mediciones siguen requiriendo el intervalo completo.
Peticiones causales, negaciones y varias variables se conservan para clasificación
o aclaración. Los tres errores del corpus 4 se reproducen sin red desde
`question_model_regressions_v4.json`, manteniendo sus errores crudos en las métricas.

El validador vuelve a comprobar intención y cabeceras temporales de los planes
0.4 frente a la petición explícita. Alterar una medición guardada para convertirla
en concepto se rechaza antes de renderizar. No cambian detectores, umbrales,
conocimiento, certeza ni flags causales.
