# Corpus 3: regresiones y nuevas formulaciones reservadas

92 preguntas: las 76 del corpus 2 pasan a desarrollo/regresión y 16 formulaciones
nuevas forman el reservado. Los JSON de los corpus 1 y 2 quedan intactos.
`parent_corpus_sha256` enlaza con el corpus 2; `freeze.json` fija entradas,
clasificaciones de referencia, expectativas, umbrales y conocimiento.

Se reutilizan los 11 historiales sintéticos del corpus 2. El reservado 3 mide
formulaciones nuevas, no generalización a escenarios físicos independientes.
Todas las etiquetas requieren revisión física y docente independiente.

El evaluador usa el corpus 3 por defecto. Las llamadas reales se separan de las
pruebas deterministas y cada salida debe ser una ruta nueva:

```powershell
python simufire_ai/tests/run_all_tests.py
python simufire_ai/evaluate_questions.py --output evaluaciones/offline-v3.json
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev-v3.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout-v3.json
```

`--corpus-dir` permite reproducir archivos históricos, pero los reservados 1 y 2
ya se han usado para desarrollar correcciones: ahora son regresiones. No ajustar
código ni prompts con los resultados del reservado 3 en este bloque.

`passed` incluye intención y temas crudos del modelo; `answer_passed` excluye
solo esas dos métricas y verifica el contrato final de respuesta. Los fallos
crudos siguen contando como fallos estrictos aunque los controles explícitos
corrijan la respuesta. El ámbito se puntúa solo cuando hay expectativa explícita.

`question_model_regressions_v2.json` conserva las cuatro respuestas erróneas del
reservado 2. Se reproducen sin red: peticiones directas sobre detección de cambios
se mantienen como condiciones y enumerar hechos registrados no exige un tema.
Los controles no alteran peticiones sobre magnitud, causas o definiciones;
conservan las ambigüedades de habitación, tiempo y apertura. Las enumeraciones
con una variable explícita siguen dependiendo del clasificador.

Estos controles determinan qué respuesta se pide. Los detectores siguen siendo
la autoridad física: ni añaden detecciones ni convierten muestras insuficientes
en una conclusión negativa. No cambian certeza, causalidad, umbrales ni teoría.
