# G3 - Gate de publicación e integración Git con main

Fecha: 2026-10-04. Estado: **GO técnico para publicar e integrar la rama**,
con autorización explícita del usuario. No es GO a activar física nueva.

## Alcance y checkpoints

Checkpoint validado: `6f8f41b0`, ledger de masa/fase, proveedor de liberación
y caller atómico aislados, tests, contratos, trazabilidad y fuentes NIST.
Rama: `codex/g3-fed-co-zonal-shareable`. Se conservan las fuentes/avisos de
NIST; no se incorporan originales FSRI excluidos por redistribución.

El main remoto avanzó hasta `c46f1d69`. Nueve commits de main no estaban
en la rama G3; añadían AI, cielo, gráficas y configuración, no `sim/`.
Merge sin conflictos: `a5f575b2`. `git diff 6f8f41b0 a5f575b2 -- sim`
vacío. El blob de `project.godot` coincide con el del main local previo
`75ff9a2a`; no hay colisiones con archivos locales ajenos sin seguimiento.

## Comprobaciones sobre la combinación

- Importación Godot monitorizada: exit 0, sin fallos de infraestructura,
  procesos previos ni errores de parseo/compilación. Avisos de regeneración
  de sidecars UID derivados, no fallos de código.
- Producto: 168/168 PASS; 81 solicitudes y 81 lanzamientos limpios.
- Global autoritativa: `python -m pytest tests -q -p no:cacheprovider`,
  3535 passed, 41 skipped, 2 xfailed, 42 subtests passed; exit 0, 529,11 s.
- AI: `simufire_ai/tests/run_all_tests.py`, 17/17 PASS, con `jsonschema`
  instalado únicamente en un venv temporal con acceso a paquetes del sistema.
- Guardarraíles científicos: ALL PASS, incluido R2-1; estilo y diff limpios.

Producto y global se ejecutaron secuencialmente. Memoria disponible inicial:
6,436188 GiB para producto y 6,283699 GiB para global. UTF-8 heredado,
APPDATA/TEMP/TMP y basetemp nuevos fuera del repositorio, salvo el override
de APPDATA que hace el launcher de fixtures en `runs/godot_test_appdata`.
Los fixtures usan el monitor de procesos; su launcher no aplica por sí mismo
el umbral de memoria del adaptador `godot_monitored_launch`.

Evidencia externa bajo
`C:/Users/dangp/AppData/Local/Temp/simufire_atomic_caller_20261004__45gspjd/`:
`integration_import.health.jsonl`, `integration_product.health.jsonl` y
el basetemp `pytest_global_integration`. No se versionan logs ni `runs/`.

## Incidencia del arnés AI

La primera ejecución no tenía `jsonschema`: ocho validadores no arrancaron.
Se repitió con la dependencia aislada, sin cambiar el Python del sistema.
El runner entonces pasó 16/16, pero omitía `test_question_answer_safety.py`.
Esta prueba leía `basic_room_001_question_001_answer.json`, cuyo intent
es `timeline`, aunque exigía causalidad. Se reprodujo su fallo antes de tocarla.

Corrección limitada: apuntar al fixture existente
`basic_room_001_question_causality_001_answer.json` e incluir la prueba en el
runner. No se modifica respuesta, analizador ni exigencia. Ocho controles
negativos en memoria siguen fallando: intent, temas, hecho obligatorio,
hecho irrelevante, conocimiento, causalidad no autorizada, limitación y fuentes.
No se mutaron archivos del módulo ni se atribuyen estos controles a una
campaña completa de mutaciones.

## Referencia y límites

No se reejecutaron los 18 casos de referencia después del merge: las fuentes
de simulación/casos y sus informes no cambiaron por integrar main. La cadena
completa del checkpoint había pasado 346/346 con 78 gaps; R2-1 sigue verde.
Los 160 informes de caso del snapshot se reconfirmaron byte idénticos,
y el resumen difiere solo en `generated_at` respecto a ese snapshot.

Los 80 archivos locales ajenos del checkout principal se preservan por
SHA-256, incluido `project.godot`, `demo/` y sidecars UID. No se versionan,
descartan ni incluyen en commits de G3.

El caller sigue fuera del paso de simulación. CO/FED, atribución térmica
real, energía sensible, muebles y evaporación predictiva permanecen NO-GO.
Las pruebas técnicas no son calibración experimental del incendio.
