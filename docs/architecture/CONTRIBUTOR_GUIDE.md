# Architecture Guide for Contributors

Esta guía orienta a quien entra al proyecto y quiere saber dónde tocar sin perderse.

## Si Quieres Tocar el Editor

Empieza por:

- `scenes/ScenarioEditorScene.tscn`
- `editor/ScenarioEditor.gd`
- `editor/ScenarioSerializer.gd`
- `editor/ObjectLibrary.gd`

El editor trabaja con datos de escenario y exporta un runtime template. Evita mezclar cambios de UI del editor con cambios del motor de simulación.

## Si Quieres Tocar la Simulación

Empieza por:

- `scenes/SimulationScene.tscn`
- `sim/BuildingModel.gd`
- `sim/core/SimulationEngine.gd`
- `sim/core/SimulationStateBuilder.gd`

El motor se verifica con tests y guardrails. Cambios de física deben ir acompañados de una justificación y el check mínimo correspondiente.

## Si Quieres Tocar Vistas

Empieza por:

- `ui/hud.gd`
- `view/2d/Visualizer.gd`
- `view/3d/Visualizer3D.gd`
- `view/fp/FirstPersonController.gd`

Las vistas deberían consumir estado construido, no depender de detalles internos del motor salvo cuando no haya alternativa.

## Si Quieres Tocar Validación

Empieza por:

- `scripts/check_product.py`
- `scripts/simulation/validation_guardrails.py`
- `sim/validation/`
- `tests/`
- `tools/validate_*.tscn`

Mantén separados los carriles de producto/editor y validación científica.

## Si Quieres Tocar Documentación

Empieza por:

- `docs/INDEX.md`
- `docs/COMMANDS.md`
- `docs/architecture/PROGRAM_FLOW.md`
- `CONTRIBUTING.md`

Si mueves documentación, actualiza enlaces y ejecuta `python scripts/check_docs_links.py`.
