# Evaluación de preguntas, versión 1

60 preguntas en español: **44 de desarrollo y 16 reservadas**, siete intenciones
y nueve variantes sintéticas del mismo escenario base. Incluyen patrón positivo,
señales contradictorias, historial corto, hueco entre muestras, ausencia de apertura,
aperturas repetidas, dos compartimentos y temperatura exactamente en el umbral
de 50 °C o un grado por debajo. No constituyen nueve simulaciones independientes.

Las entradas, umbrales, conocimiento, preguntas y expectativas están congeladas
en JSON. `freeze.json` comprueba sus huellas e inventario antes y después de cada
evaluación. Las etiquetas y hechos esperados se escribieron explícitamente y se
revisaron contra el contrato; no se generan ejecutando el resolver. La revisión
física y docente independiente está pendiente. Una detección al llegar al umbral
verifica la implementación del predicado, no la validez física de ese umbral.

## Ejecución desde la raíz del repositorio

```powershell
# Suite determinista: nunca necesita Ollama.
python simufire_ai/tests/run_all_tests.py

# Corpus completo con etiquetas inyectadas. Verifica el contrato y renderer.
python simufire_ai/evaluate_questions.py --output evaluaciones/offline.json

# Modelo real: separar desarrollo y conjunto reservado.
python simufire_ai/evaluate_questions.py --ollama --split dev --output evaluaciones/dev.json
python simufire_ai/evaluate_questions.py --ollama --split holdout --output evaluaciones/holdout.json
```

Cada salida debe tener un nombre nuevo. El evaluador no sobrescribe informes.
Devuelve 0 cuando todos los casos pasan y 1 si hay fallos; conserva el informe
completo aunque algunas preguntas fallen. Una indisponibilidad inicial del modelo
o cambios durante la medición abortan la evaluación. Los errores individuales de
JSON, transporte o validación se registran sin fabricar respuestas.

## Qué se mide

- Intención y temas **crudos** del clasificador, antes de correcciones deterministas.
  En timeline los temas se derivan de los hechos y no se puntúan como clasificación.
- Intención/temas finales, estado de respuesta, hechos principales y conocimiento
  exactos, además de restricciones de texto concretas.
- Controles estructurales de identidad del contexto, metadatos de certeza/causalidad,
  procedencia y fuentes; sus fallos se contabilizan aparte de la interpretación.
- Duración de la llamada al clasificador, duración total y del renderer. La mediana
  y p95 del modo offline corresponden a una función de etiquetas, no a Ollama.
- Matriz de intenciones, errores y resultados por conjunto. Los denominadores de
  cada comprobación indican cuántos resultados pudieron evaluarse; los errores
  no cuentan como aciertos y también reducen el número total de casos superados.

Se guardan respuesta cruda, plan, respuesta final, huella de cada prompt/contexto,
código, corpus, motor, versiones de Python/jsonschema/Ollama y digest del modelo
instalado. Temperatura cero no garantiza repetir exactamente las clasificaciones.
Los controles de texto y procedencia no demuestran ausencia de toda afirmación
semánticamente incorrecta: hay que revisar también los casos fallidos y ejemplos.

## Disciplina del conjunto reservado

Congelar preguntas y etiquetas antes de ejecutar Qwen. Ajustar prompts únicamente
con desarrollo. Ejecutar el reservado al terminar esos ajustes y conservar ese
primer resultado. Si se corrige a partir de un fallo reservado, ese caso se convierte
en regresión: hace falta un nuevo conjunto/versionado para medir generalización.
No presentar una repetición del mismo reservado como una evaluación independiente.

Este corpus comprueba comportamientos del prototipo; sus tasas de acierto no son
una estimación representativa de usuarios, incendios reales ni validez para formación.
No se exige exactitud literal de toda la respuesta, pero sí de hechos seleccionados,
conocimiento y restricciones de prudencia especificadas por cada caso.
