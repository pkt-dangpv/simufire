# Local Workspace Hygiene

Estas carpetas y archivos pueden aparecer al ejecutar Godot, validaciones o scripts auxiliares. No forman parte del producto versionado principal.

## Trabajar en distintos equipos y unidades

El checkout puede estar en `C:` o `F:`. Los lanzadores calculan la raíz desde
su propio archivo; no hay que sustituir una letra de unidad por otra en el código.
Python y PowerShell buscan Godot mediante un argumento explícito, `GODOT_EXE`,
el PATH o el escritorio del usuario de ese equipo. Los ejecutables se configuran
localmente y no se copian sus rutas entre máquinas.

Por ejemplo, en cada equipo y desde la raíz de su propio checkout:

```powershell
# Solo si Godot no está en PATH ni se detecta en el escritorio:
$env:GODOT_EXE = (Resolve-Path (Read-Host "Ruta del ejecutable Godot en este equipo")).Path
python scripts/run_scenario.py --help
```

Los lanzadores de FDS usan `%ProgramFiles%` de Windows para la instalación
estándar de firemodels; FDS y Smokeview deben estar instalados en cada equipo.

Para evitar que OneDrive mezcle el índice y las ramas de Git mientras se trabaja
en ambos equipos, conviene usar un checkout independiente fuera de OneDrive en
cada máquina y sincronizar el código mediante Git. No se han trasladado esos
checkouts como parte de la limpieza actual. Si se mantiene la carpeta compartida,
terminar la sincronización y trabajar desde un solo equipo a la vez.

Los respaldos de copias deben estar fuera del proyecto y de OneDrive. Un respaldo
local en SOBREMESA no aparece automáticamente en el portátil. Las evidencias
históricas preparadas para Git están en
[el paquete del 14 de octubre](archive/local_evidence_2026-10-14/README.md).
Los logs históricos pueden conservar rutas absolutas como procedencia; no se
usan para localizar el proyecto actual al ejecutar los lanzadores.

## Ignorados por Git

- `.godot/`: caché interna de Godot.
- `.godot_validation_logs/`: logs locales de validación.
- `.matplotlib-cache/`: caché de Matplotlib.
- `.tmp_guardrail_tests/`: temporales de tests de guardrails.
- `graphs/`: gráficas generadas localmente.
- `runs/`: salidas de ejecuciones locales.
- `*.log`, `tmp_*`, `last_run.txt`, `editor_scenario.json`: artefactos de ejecución.

## Regla Práctica

Si un archivo es necesario para reproducir un resultado oficial, debe moverse a una carpeta de dominio clara y documentarse:

- escenarios: `scenarios/` o `sim/validation/cases/`;
- baselines: `sim/validation/baselines/`;
- reportes publicables: `docs/validation/`;
- scripts oficiales: `scripts/` o `tools/`;
- histórico no ejecutable: `docs/archive/`.

## Limpieza Local Manual

Revisa antes de borrar, especialmente si acabas de generar resultados que todavía no has archivado.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1
```

No incluyas `.godot/` si tienes el editor abierto o estás depurando importaciones. Para limpiarla explícitamente, ejecuta `scripts/clean_workspace.ps1 -IncludeGodotCache`.
