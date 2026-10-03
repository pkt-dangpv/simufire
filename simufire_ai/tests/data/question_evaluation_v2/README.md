# Corpus 2: regresiones y nuevo conjunto reservado

76 preguntas: las 60 del corpus 1 pasan íntegramente a desarrollo/regresión;
16 formulaciones nuevas forman el reservado. El corpus 1 y sus informes no se
modifican. `parent_corpus_sha256` vincula ambos conjuntos y `freeze.json` congela
las entradas, etiquetas, umbrales, conocimiento y expectativas.

Se añaden dos historiales sintéticos con otra geometría, habitación, tiempos y
valores: un almacén con cambios y otro estable. Los nueve historiales anteriores
son variantes relacionadas; los nuevos tampoco constituyen datos reales de un
simulador ni una validación física o docente. Las etiquetas requieren revisión
experta independiente. No se añaden detectores ni se cambian umbrales.

El corpus 2 se conserva como archivo histórico. El predeterminado es ahora el
corpus 3. Para reproducir esta versión, añade
`--corpus-dir simufire_ai/tests/data/question_evaluation_v2` a cada evaluación:

```powershell
python simufire_ai/tests/run_all_tests.py
python simufire_ai/evaluate_questions.py --output evaluaciones/offline-v2.json
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev-v2.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout-v2.json
```

Una ruta de informe existente se rechaza. `--corpus-dir` permite reproducir otra
versión, pero el antiguo reservado del corpus 1 ya no es una medición independiente:
sus preguntas se han usado para diseñar correcciones y pruebas de regresión.
El reservado 2 ha revelado cuatro fallos y sus preguntas pasan a regresiones en
el corpus 3. Una repetición sobre estos casos ya no es una evaluación independiente.

Se mantienen las comprobaciones y el criterio estricto `passed` anteriores,
incluidos intención y temas crudos de Qwen. Se añade **`answer_passed`**, que
puntúa intención/temas finales, ámbito cuando se especifica, estado, selección
exacta de hechos/conocimiento, procedencia y restricciones de texto. La métrica
de respuesta excluye únicamente las dos comprobaciones crudas del modelo.
Así se puede ver una interpretación cruda equivocada que el validador corrige.
El código de salida sigue siendo 1 si algún caso falla el criterio estricto.

Los controles de peticiones explícitas reconocen preguntas directas sobre límites,
resúmenes y cambios de variables, y varias expresiones temporales. Qwen conserva
la interpretación de lenguaje general. Los controles nunca aportan hechos físicos,
certeza ni causalidad; esos datos siguen procediendo del análisis determinista.
Las definiciones y peticiones causales clasificadas como tales se preservan ante
una orden de resumir. Las aperturas repetidas siguen necesitando desambiguación.

Si Qwen omite el tema en una petición explícita de límites o resumen, se completa
solo cuando aparece una única variable medida literal. Una variable desconocida
o varios efectos posibles mantienen la necesidad de clasificar o aclarar.
La métrica de ámbito solo puntúa casos con expectativas de ámbito explícitas.

`question_model_regressions.json` conserva seis respuestas crudas erróneas sobre
las cinco preguntas fallidas, incluida una variante del modelo con temas vacíos.
Las pruebas las reproducen sin red y comprueban que la
respuesta final conserva la limitación y el ámbito pertinentes. El éxito de esos
replays no significa que Qwen haya corregido su clasificación ni demuestra
fiabilidad para todas las formulaciones posibles.
