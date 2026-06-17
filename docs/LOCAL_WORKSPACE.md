# Local Workspace Hygiene

Estas carpetas y archivos pueden aparecer al ejecutar Godot, validaciones o scripts auxiliares. No forman parte del producto versionado principal.

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
