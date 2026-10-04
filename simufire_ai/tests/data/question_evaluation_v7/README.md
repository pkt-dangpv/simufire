# Corpus 7: explicaciones causales frente a magnitudes

160 preguntas: las 144 anteriores pasan a regresiones y se congelan 16 nuevas
formulaciones reservadas, con los siete tipos de pregunta. Se reutilizan los
mismos 14 historiales sintéticos; no se añaden simulaciones reales ni una revisión
física independiente. Entradas, conocimiento, umbrales y expectativas se fijan
en `freeze.json` antes de consultar Qwen. Los JSON y etiquetas anteriores permanecen
intactos, enlazados por `parent_corpus_sha256`.

```powershell
python simufire_ai/tests/run_all_tests.py
python simufire_ai/evaluate_questions.py --output evaluaciones/offline-v7.json
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev-v7.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout-v7.json
```

Cada salida debe utilizar una ruta nueva. No ajustar código o prompts a partir
del reservado 7 en este bloque. Se conservan los criterios `passed` y
`answer_passed`, incluido `model_room_consistency`. Las correcciones deterministas
no cuentan como aciertos de Qwen. La auditoría de procedencia es estructural.

Las preguntas directas de por qué cambió una única variable medida conservan
la intención causal. En «X cambió debido a Y», una variable medida inequívoca
en cada cláusula conserva X como efecto, aunque el modelo clasifique observación
de otra variable. Se aplican las limitaciones causales del contexto; no se
crean causas, valores o anclas. Tiempo y habitación siguen exigiendo cobertura.
Negaciones, definiciones, alternativas y fenómenos desconocidos no reciben
esta reparación. `debido al` también evita convertir una petición causal en
una simple pregunta de detección.

`question_model_regressions_v6.json` conserva los dos errores crudos anteriores.
Su reproducción y los controles de ventanas/planes alterados se ejecutan sin
red. La evaluación física y docente de reglas, certeza, fuentes y etiquetas
requiere revisión experta; estas pruebas no la sustituyen.
