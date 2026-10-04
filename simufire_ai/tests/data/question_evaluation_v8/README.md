# Corpus 8: regresión de presentación tras revisión experta

160 preguntas existentes, sobre los mismos 14 historiales sintéticos. Todas son
regresiones; no hay reservado nuevo ni resultados independientes del modelo.
Se conservan intactos el corpus 7 y todas las versiones previas.

`expectation_changes.json` registra los cuatro cambios explícitos en expectativas
de presentación solicitados por el experto (E02/E04), con el valor anterior y el
nuevo. No se modifican hechos, conocimiento, umbrales, historiales ni etiquetas
de selección/estado interno. Las demás expectativas permanecen iguales. Los
archivos se congelan antes de ejecutar la evaluación y no se regeneran desde
la salida del renderer. La teoría actual de E03 se prueba además con la biblioteca
vigente en el script determinista y en el paquete de revisión humana.

El estado principal `response_status` distingue cambio medido o respuesta
compatible con ventilación del estado técnico del detector. `answer_status`
conserva el contrato histórico de selección/cobertura; no es la etiqueta principal
para presentar una respuesta docente con mediciones.

Offline: `python simufire_ai/evaluate_questions.py --output resultado.json`.
Con modelo real: añadir `--ollama --split dev`. No hay nueva prueba reservada.
Los comandos con Ollama se ejecutan explícitamente fuera de la suite determinista.
