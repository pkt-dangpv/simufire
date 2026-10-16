# Official Commands

Estos son los comandos de entrada soportados para desarrollar, validar y ejecutar SimuFire. Los scripts exploratorios deben vivir fuera de esta lista hasta que se documenten y estabilicen.

La letra de unidad del checkout puede cambiar entre equipos. Consulta
[la configuración local de herramientas](LOCAL_WORKSPACE.md) para seleccionar
Godot sin editar rutas de usuario en los scripts. Los argumentos explícitos y
`GODOT_EXE` permiten seleccionar la instalación de cada máquina.

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

## Auditoria Fisica General

```powershell
python scripts/simulation/check_physics_coherence.py sim/validation/reports/<caso>.csv
python scripts/simulation/audit_physics_coherence_suite.py
```

Comprueba reglas de coherencia fisica del motor sobre CSVs existentes. La suite actual incluye reglas gating para inversion termica fuerte, FED, HRR sin combustible, regimen contra O2 superior critico y balance CO D1.

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

En este workspace Windows, cualquier agente debe ejecutar Godot fuera de su
sandbox restringido, con el editor cerrado y un proceso cada vez. Un error
`Failed to read the root certificate store` invalida el entorno del run. Véase
`docs/validation/GODOT_471_HEADLESS_CRASH_AUDIT.md`.

## Auditar Coherencia ILV Por Capas

```powershell
python scripts/simulation/check_ilv_layer_coherence.py runs/<escenario>/sim_log.csv --room-id 0
python scripts/simulation/audit_ilv_layer_coherence_suite.py --allow-findings
```

Detecta estados incoherentes de ILV/two-zone: HRR significativo con `o2_upper` crítico mientras el régimen sigue `FUEL_CONTROLLED`/`FULLY_DEVELOPED`, o mientras `o2_hrr_factor` permanece alto por la capa baja/global.

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

## Huella de Determinismo del Motor

```powershell
python -X utf8 tools/determinism_fingerprint.py run --out <huella.json> --worker
python -X utf8 tools/determinism_fingerprint.py compare <a.json> <b.json>
```

Corre siempre el mismo escenario (`tools/determinism_fingerprint_options.json`, con `user://` aislado) 7200 pasos de 1/12 s y guarda resúmenes SHA-256 del estado exportado cada 600 pasos, más las huellas de las funciones matemáticas que usa el motor en el hilo principal y en un hilo trabajador. Sirve para comprobar que el motor da exactamente los mismos números en otra máquina, en otro build o en otro hilo. `compare` sale con 1 si las huellas difieren. Huellas guardadas en `docs/validation/determinism/`.

## Tests Python de Producto Sin Godot

```powershell
python -m unittest tests.test_ui_localization -v
python -m unittest tests.test_editor_scenarios -v
```

Estos checks no ejecutan escenas Godot directamente y son apropiados para CI ligera.

`tests.test_guardrails` incluye un smoke de integración contra `reference_checks.json`; úsalo como check de validación, no como producto ligero.
