# Refactor Plan

Este plan prepara la modularización de los archivos grandes sin cambiar comportamiento por accidente. La regla principal es refactorizar por extracción, con pruebas o smokes antes y después.

## Objetivos

- Reducir archivos de más de 2.000 líneas en unidades con responsabilidad clara.
- Mantener rutas públicas, escenas y contratos runtime estables durante cada paso.
- Evitar mezclar refactor con cambios de física, UI o validación.
- Hacer cambios pequeños, revisables y reversibles.

## Candidatos Prioritarios

| Archivo | Riesgo | Extracciones sugeridas |
|---|---|---|
| `editor/ScenarioEditor.gd` | Alto | herramientas, selección, propiedades, dibujo, floor/stairs, import/export, preview 3D |
| `view/fp/FirstPersonController.gd` | Alto | movimiento, interacción, HUD FP, construcción de mundo, apertura/puertas, overlays |
| `view/3d/Visualizer3D.gd` | Alto | room shell, aperturas, humo, fuego, mobiliario, selección/drag, cámara |
| `sim/core/SimulationEngine.gd` | Alto | eventos, export/resumen, setup de subsistemas, step orchestration |
| `sim/core/ThermalSystem.gd` | Alto | paredes, plume/entrainment, flashover helpers, transferencias por apertura |

## Secuencia Recomendada

1. Congelar checks mínimos antes de cada extracción.
2. Crear helper nuevo junto al módulo original.
3. Mover funciones puras o casi puras primero.
4. Mantener nombres de funciones públicas mientras se estabiliza.
5. Ejecutar el check mínimo correspondiente.
6. Repetir en lotes pequeños.

## Primeras Extracciones Seguras

- `ScenarioEditor.gd`: helpers de geometría y selección sin tocar callbacks de UI.
- `Visualizer3D.gd`: factories de nodos visuales que ya no dependan de estado global.
- `FirstPersonController.gd`: layout/HUD first-person y helpers de interacción con aperturas.
- `SimulationEngine.gd`: generación de resumen técnico y rutas de export.

## Checks por Zona

| Zona | Check mínimo |
|---|---|
| Editor | `python scripts/check_product.py` |
| Visual 3D | escenas `tools/validate_3d_*.tscn` mediante `check_product.py` |
| First-person | escenas `tools/validate_fp_*.tscn` mediante `check_product.py` |
| Motor | guardrails rápidos y tests específicos de `tests/` |
| Validación científica | `validation_guardrails.py` o suite completa según riesgo |

## Límites

- No mover escenas `.tscn` junto con código en el mismo cambio salvo necesidad clara.
- No cambiar fórmulas físicas durante una extracción.
- No rebaselinar validación en un cambio que solo pretende modularizar.
- No introducir dependencias externas para resolver organización interna.
