# Official Commands

Estos son los comandos de entrada soportados para desarrollar, validar y ejecutar SimuFire. Los scripts exploratorios deben vivir fuera de esta lista hasta que se documenten y estabilicen.

## Producto y Editor

```powershell
python scripts/check_product.py
```

Ejecuta pruebas de editor/producto, smoke checks Godot headless y validaciones ligeras de integración.

## Guardrails Científicos Rápidos

```powershell
python scripts/simulation/validation_guardrails.py
```

Lee los resultados de referencia existentes y comprueba que los guardrails científicos requeridos sigan dentro de tolerancia.

## Recalcular Checks Desde Informes

```powershell
python scripts/simulation/validate_reference_cases.py
```

Recalcula checks a partir de reportes ya generados. No sustituye una corrida fresca completa.

## Validación Científica Completa

```powershell
powershell -ExecutionPolicy Bypass -File sim/validation/run_reference_checks.ps1 -TimeoutSeconds 900
```

Ejecuta la suite fresca contra casos de referencia. Requiere Godot y puede tardar varios minutos.

## Two-Zone V1

```powershell
powershell -ExecutionPolicy Bypass -File sim/validation/run_two_zone_v1_checks.ps1 -TimeoutSeconds 900
```

Ejecuta unitarios, contrato runtime, auditoría de flags y guardrails de Two-Zone V1.

```powershell
powershell -ExecutionPolicy Bypass -File sim/validation/run_legacy_two_zone_compare.ps1 -Action compare -CandidateMode two-zone -TwoZoneV1
```

Compara Two-Zone V1 contra la referencia legacy congelada.

## Ejecutar Escenario

```powershell
python scripts/run_scenario.py scenarios/compact_apartment_reference.json --duration 60
```

Ejecuta un escenario definido en JSON y genera salidas técnicas.

## Generar Gráficas

```powershell
python scripts/generate_fire_graphs.py
```

Genera gráficas a partir de salidas de simulación existentes.

## Actualizar Bibliografía Local

```powershell
powershell -ExecutionPolicy Bypass -File scripts/download_fire_literature.ps1
```

Descarga o actualiza documentos en `docs/literature/`.

## Limpiar Artefactos Locales

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1
```

El primer comando muestra qué se borraría. El segundo limpia cachés y salidas locales ignoradas como `graphs/`, `runs/`, `.matplotlib-cache/` y logs de validación. Para incluir `.godot/`, añade `-IncludeGodotCache`.

## Comprobar Enlaces de Documentación

```powershell
python scripts/check_docs_links.py
```

Comprueba enlaces Markdown locales en el repositorio. Los enlaces externos y anchors se ignoran.

## Tests Python de Producto Sin Godot

```powershell
python -m unittest tests.test_ui_localization -v
python -m unittest tests.test_editor_scenarios -v
```

Estos checks no ejecutan escenas Godot directamente y son apropiados para CI ligera.

`tests.test_guardrails` incluye un smoke de integración contra `reference_checks.json`; úsalo como check de validación, no como producto ligero.
