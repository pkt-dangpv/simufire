# Corpus 4: regresiones y reservado con nuevos historiales sintéticos

108 preguntas: las 92 del corpus 3 pasan íntegramente a regresiones y 16
formulaciones nuevas forman el reservado. Se añaden dos historiales sintéticos
de Laboratorio, con otra geometría, tiempos y valores. Hay 13 historiales/variantes
en total; no son datos reales de un simulador ni una validación física o docente.
Las etiquetas requieren revisión experta independiente.

Los JSON congelados anteriores se conservan sin cambios. La huella del corpus 3
se guarda en `parent_corpus_sha256`. `freeze.json` fija entradas, etiquetas,
expectativas, umbrales y conocimiento antes de ejecutar el modelo.

```powershell
python simufire_ai/tests/run_all_tests.py
python simufire_ai/evaluate_questions.py --output evaluaciones/offline-v4.json
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev-v4.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout-v4.json
```

Cada salida debe ser nueva. `--corpus-dir` permite reproducir versiones anteriores;
sus reservados usados para desarrollar correcciones ya no son independientes.
No ajustar código ni prompts con resultados del reservado 4 en este bloque.

`passed` conserva los errores crudos del modelo y ahora añade
`model_room_consistency`: ante una única habitación explícita, el modelo puede
dejarla sin especificar o nombrarla correctamente, pero no elegir otra. Se excluyen
las preguntas conceptuales y las que no nombran una sola habitación. Es una
comprobación de contradicción, no una métrica completa de precisión del ámbito.
Por este control adicional, el criterio estricto no es idéntico al de informes
anteriores. `answer_passed` excluye solo las comprobaciones `model_*` y mantiene
todo el contrato final, procedencia y restricciones de texto.

Los controles explícitos reconocen «quedó registrado/detectado» y «lista todos
los hechos registrados». Una única variable medida literal en una petición
directa de límites, resumen o detección puede sustituir el tema genérico
`fire_dynamics`; temas específicos contradictorios no se sustituyen.

Solo una propuesta nueva del modelo puede corregir una habitación existente
equivocada a partir de un nombre/ID literal único del contexto. No se acepta un
ID inventado ni se resuelve una mención de varias habitaciones arbitrariamente.
El renderer sigue rechazando planes guardados con ámbitos alterados. Los cuatro
errores del corpus 3 se reproducen desde `question_model_regressions_v3.json` sin
red y conservando los errores crudos en las métricas.

Los detectores, umbrales, teoría y certeza no cambian. Estos controles deciden
qué pregunta responder; los hechos físicos siguen procediendo del análisis.
