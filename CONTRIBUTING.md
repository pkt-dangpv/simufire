# Contributing to SimuFire

Esta guía fija convenciones mínimas para que el proyecto siga creciendo como programa mantenible.

## Estructura

- `sim/`: motor de simulación y modelos de dominio.
- `editor/`: editor de escenarios.
- `view/`: visualizaciones 2D, 3D y first-person.
- `ui/`: HUD, temas, localización y componentes de interfaz.
- `scenes/`: escenas Godot de entrada.
- `scripts/`: comandos oficiales ejecutables desde consola.
- `tools/`: validadores, herramientas Godot headless y utilidades técnicas.
- `tests/`: pruebas Python.
- `docs/`: documentación vigente, histórico, auditorías y bibliografía.

## Scripts

- Usa `scripts/` para comandos estables documentados en `docs/COMMANDS.md`.
- Usa `tools/` para validadores, escenas headless y utilidades técnicas.
- Usa `tools/archive/` para scripts exploratorios conservados solo por trazabilidad.
- Evita scripts sueltos en la raíz.

## Documentación

- `docs/validation/`: estado, resumen y gaps de validación.
- `docs/audits/`: auditorías.
- `docs/architecture/`: arquitectura, diseños y planes técnicos.
- `docs/roadmaps/`: roadmaps.
- `docs/planning/`: planes, checklists y notas operativas.
- `docs/sessions/`: histórico de sesiones.
- `docs/archive/`: material histórico no operativo.
- `docs/literature/`: bibliografía y PDFs externos.

## GDScript

- Prefiere archivos con una responsabilidad clara.
- Evita añadir nuevas funciones grandes a módulos ya muy extensos sin considerar extracción.
- Mantén nombres de dominio explícitos: `SimulationEngine`, `ThermalSystem`, `ScenarioSerializer`, etc.
- Usa tipos cuando el valor sea estable y ayude a Godot a detectar errores.
- Mantén `class_name` para clases reutilizables.
- Evita rutas hardcodeadas fuera de `res://` y `user://` salvo scripts de plataforma claramente documentados.

## Python y PowerShell

- Los scripts oficiales deben calcular rutas desde la raíz del repo, no desde rutas absolutas de usuario.
- Si un script requiere Godot, respeta `GODOT_EXE` antes de usar candidatos locales.
- Las salidas generadas deben ir a `user://`, `runs/`, `graphs/`, un temporal del sistema o una ruta indicada por parámetro.

## Artefactos

- No versionar cachés, logs ni salidas temporales nuevas.
- Si se conserva un artefacto histórico, colócalo en `docs/archive/` con una nota breve.
- Si se conserva una baseline científica, colócala en `sim/validation/baselines/`.

## Antes de Cerrar un Cambio

Ejecuta la comprobación más pequeña que cubra el cambio:

- documentación: revisar enlaces tocados y `git diff --check`;
- scripts Python: ejecutar el script o su test directo;
- producto/editor: `python scripts/check_product.py`;
- motor científico: guardrails rápidos o suite científica según el riesgo.

## Decisiones de Arquitectura

Las decisiones transversales se documentan como ADRs en `docs/architecture/adr/`. Antes de cambiar estructura de carpetas, comandos oficiales, política de artefactos o carriles de validación, añade o actualiza un ADR.

## Plantillas

Usa las plantillas de `docs/templates/` para nuevas auditorías, ADRs, release notes e issues técnicos.
